# Shared helpers for the jay scripts (bin/). Sourced, not executed.

# Settings: an environment variable wins, else ~/.config/jay/config (KEY=value lines, #
# comments), else the default. The file reaches what a shell profile does not: hooks in
# background agents, and a notice click. ~ at the start of a JAY_ROOTS folder is $HOME.
# The names of wt-hub (jay's old name) still work: WT_<name> in the environment or the file is
# JAY_<name> (WT_HUB_SESSION is JAY_SESSION); a JAY_ name wins.
JAY_CONFIG="$HOME/.config/jay/config"
for _key in ROOTS TERMINAL EDITOR EDITOR_GUI TASK_SHELL LAUNCHER REVIEW REVIEW_DIFF ZELLIJ_TIMEOUT ZELLIJ_SESSION NOTIFY_LOG HUB_SESSION; do
  _old=WT_$_key _new=JAY_$_key
  [[ $_key == HUB_SESSION ]] && _new=JAY_SESSION
  [[ -z "${!_new:-}" && -n "${!_old:-}" ]] && export "$_new=${!_old}"
done
if [[ -f "$JAY_CONFIG" ]]; then
  _re='^[[:space:]]*(JAY|WT)_(ROOTS|TERMINAL|EDITOR|EDITOR_GUI|TASK_SHELL|LAUNCHER|REVIEW|REVIEW_DIFF|AUTO_RESPAWN)[[:space:]]*=[[:space:]]*(.*)$'
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ "$_line" =~ $_re ]] || continue
    _key=JAY_${BASH_REMATCH[2]} _val=${BASH_REMATCH[3]}
    _val=${_val%"${_val##*[![:space:]]}"}
    _val=${_val#\"}; _val=${_val%\"}
    [[ -n "${!_key:-}" ]] || export "$_key=$_val"
  done <"$JAY_CONFIG"
  unset _re _line _val
fi
unset _key _old _new
JAY_ROOTS=${JAY_ROOTS:-$HOME/Documents/projects}
# idle: the list respawns an agent on an old Claude Code at a quiet moment (jay_respawn_auto);
# off: only `jay respawn` does.
JAY_AUTO_RESPAWN=${JAY_AUTO_RESPAWN:-idle}
_roots=""
IFS=: read -ra _dirs <<<"$JAY_ROOTS"
for _dir in ${_dirs[@]+"${_dirs[@]}"}; do
  _roots+="${_roots:+:}${_dir/#\~/$HOME}"
done
JAY_ROOTS=$_roots
unset _roots _dirs _dir

# The hub's state: what its panes show, the turn chains' worktrees, the marks, the tasks, logs.
JAY_STATE="$HOME/.local/state/jay"

# Make the state folder before a write there. Not when this file loads: install.sh --check
# loads it and must change nothing.
jay_state_dir() {
  [[ -d "$JAY_STATE" ]] || mkdir -p "$JAY_STATE" 2>/dev/null
  return 0
}

# A click on a notice runs `jay-go` through /bin/sh with launchd's PATH (/usr/bin:/bin:...),
# which has no claude or zellij. Add their folders at the end, so a caller's own order wins
# (Homebrew: /opt/homebrew/bin on Apple silicon, /usr/local/bin on Intel).
for _dir in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$_dir:"*) ;; *) PATH="$PATH:$_dir" ;; esac
done
unset _dir
export PATH

# Every zellij call from these scripts gives up after $JAY_ZELLIJ_TIMEOUT seconds: a session
# whose server outlives it (seen after a quit) stalls even list-sessions, and with it every
# pick, hook and sidebar tick. Interactive zellij runs through `exec` or a new Ghostty tab,
# never through this function.
zellij() {
  perl -e 'alarm shift; exec @ARGV or exit 127' "${JAY_ZELLIJ_TIMEOUT:-5}" zellij "$@"
}

jay_toplevel() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$1"
}

jay_primary() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk 'NR==1 { sub(/^worktree /, ""); print; exit }'
}

jay_client() {
  local parent root
  parent=$(dirname "$1")
  IFS=: read -ra roots <<<"$JAY_ROOTS"
  for root in "${roots[@]}"; do
    [[ "$parent" == "$root" ]] && { basename "$1"; return; }
  done
  basename "$parent"
}

# Prints: client<TAB>repo<TAB>branch<TAB>worktree-root
jay_describe() {
  local top primary branch
  top=$(jay_toplevel "$1")
  primary=$(jay_primary "$top")
  [[ -n "$primary" ]] || primary=$top
  branch=$(git -C "$top" branch --show-current 2>/dev/null)
  [[ -n "$branch" ]] || branch=$(basename "$top")
  printf '%s\t%s\t%s\t%s\n' "$(jay_client "$primary")" "$(basename "$primary")" "$branch" "$top"
}

jay_tab_name() {
  local repo=$1 branch=${2##*/}
  printf '%s/%s\n' "$repo" "${branch:0:32}"
}

jay_in_zellij() {
  [[ -n "${ZELLIJ_SESSION_NAME:-}" && -z "${CLAUDE_JOB_DIR:-}" ]]
}

jay_live_sessions() {
  zellij list-sessions --no-formatting 2>/dev/null | grep -v 'EXITED' | awk '{ print $1 }'
}

jay_session_has_client() {
  [[ $(zellij -s "$1" action list-clients 2>/dev/null | wc -l) -gt 1 ]]
}

# The zellij session to act on: the caller's own, else the one with a client attached.
jay_session() {
  if jay_in_zellij; then
    printf '%s\n' "$ZELLIJ_SESSION_NAME"
    return
  fi
  [[ -n "${JAY_ZELLIJ_SESSION:-}" ]] && { printf '%s\n' "$JAY_ZELLIJ_SESSION"; return; }
  local s first=""
  while IFS= read -r s; do
    [[ -z "$first" ]] && first=$s
    jay_session_has_client "$s" && { printf '%s\n' "$s"; return; }
  done < <(jay_live_sessions)
  [[ -n "$first" ]] && printf '%s\n' "$first"
}

# Panes of a session whose cwd sits in worktree $2, as JSON lines. Optional $3: jq regex on pane_command.
jay_panes_in() {
  local session=$1 path=$2 cmd=${3:-}
  zellij -s "$session" action list-panes -j -c 2>/dev/null | jq -c --arg p "$path" --arg cmd "$cmd" '
    .[] | select(.is_plugin | not)
        | select(.pane_cwd == $p or (.pane_cwd | startswith($p + "/") and (contains("/.claude/worktrees/") | not)))
        | select($cmd == "" or ((.pane_command // .terminal_command // "") | test($cmd)))'
}

jay_focus_pane() {
  local session=$1 pane=$2 tab=$3
  [[ -n "$tab" ]] && zellij -s "$session" action go-to-tab-name "$tab" >/dev/null 2>&1
  zellij -s "$session" action focus-pane-id "terminal_$pane" >/dev/null 2>&1
}

jay_raise_terminal() {
  jay_gh_ok || return 1
  open -b com.mitchellh.ghostty 2>/dev/null
}

jay_frontmost_bundle() {
  lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*"*bundleID"*="\([^"]*\)".*/\1/p'
}

jay_has_transcripts() {
  local slug=${1//[\/.]/-}
  compgen -G "$HOME/.claude/projects/$slug/*.jsonl" >/dev/null
}

# --- Ghostty tabs (AppleScript, Ghostty 1.3+) ---

# Tab control works in Ghostty only; other terminals can be added later. JAY_TERMINAL=ghostty
# turns it on, any other value off. Else it is on when Ghostty runs and the caller's terminal,
# if it has one, is Ghostty (zellij panes get the TERM_PROGRAM of the terminal that started
# the session; hooks and a notice click may have none). Without it the jay_gh_* functions
# fail and do nothing.
jay_gh_ok() {
  case ${JAY_TERMINAL:-} in
    ghostty) return 0 ;;
    "") ;;
    *) return 1 ;;
  esac
  case ${TERM_PROGRAM:-ghostty} in
    ghostty | tmux | zellij) ;;
    *) return 1 ;;
  esac
  pgrep -xq ghostty
}

# Prints one line per tab: tab-id<TAB>selected<TAB>frontmost-window<TAB>tty<TAB>title
jay_gh_tabs() {
  jay_gh_ok || return 1
  osascript -e '
set out to ""
set TB to character id 9
tell application "Ghostty"
  set fw to ""
  if (count of windows) > 0 then set fw to id of front window
  repeat with w in windows
    repeat with t in tabs of w
      set term to focused terminal of t
      set out to out & (id of t) & TB & (selected of t) & TB & ((id of w) is fw) & TB & (tty of term) & TB & (name of t) & linefeed
    end repeat
  end repeat
end tell
return out' 2>/dev/null | sed '/^$/d'
}

# Zellij session a Ghostty tab shows, from its client process or its title ("name | pane").
jay_gh_tab_session() {
  local tty=${1#/dev/} title=$2 args
  args=$(ps -t "$tty" -o command= 2>/dev/null | awk '$1 ~ /(^|\/)zellij$/ { print; exit }')
  [[ -n "$args" ]] || return 1
  if [[ "$args" =~ (attach|a|-s|--session)[[:space:]]+(-c[[:space:]]+)?([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
  else
    printf '%s\n' "${title%% | *}"
  fi
}

# Ghostty tab id whose terminal runs zellij session $1.
jay_gh_tab_for_session() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    [[ "$(jay_gh_tab_session "$tty" "$title")" == "$1" ]] && { printf '%s\n' "$id"; return 0; }
  done < <(jay_gh_tabs)
  return 1
}

# Ghostty tab id whose own tty runs a process matching regex $1 (e.g. "^claude attach 1234").
jay_gh_tab_for_command() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    ps -t "${tty#/dev/}" -o command= 2>/dev/null | grep -qE "$1" && { printf '%s\n' "$id"; return 0; }
  done < <(jay_gh_tabs)
  return 1
}

# Ghostty tab id whose tty is $1.
jay_gh_tab_for_tty() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    [[ "$tty" == "/dev/${1#/dev/}" ]] && { printf '%s\n' "$id"; return 0; }
  done < <(jay_gh_tabs)
  return 1
}

jay_gh_select() {
  jay_gh_ok || return 1
  osascript - "$1" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set wanted to item 1 of argv
  tell application "Ghostty"
    repeat with w in windows
      repeat with t in tabs of w
        if (id of t) is wanted then
          select tab t
          activate window w
          activate
          return
        end if
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

# New Ghostty tab in folder $1 that types command $2 into the shell. Prints the tab id.
jay_gh_new_tab() {
  jay_gh_ok || return 1
  osascript - "$1" "$2" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wd to item 1 of argv
  set cmd to (item 2 of argv) & return
  tell application "Ghostty"
    set cfg to {initial working directory:wd, initial input:cmd}
    if (count of windows) is 0 then
      set w to new window with configuration cfg
      activate
      return id of selected tab of w
    end if
    set t to new tab in front window with configuration cfg
    activate
    return id of t
  end tell
end run
APPLESCRIPT
}

# The zellij session for a worktree: the default name, else the live session whose panes sit in it.
jay_session_name() {
  local repo=$1 branch=${2##*/} name
  name="$repo.${branch}"
  name=${name//[^A-Za-z0-9._-]/-}
  printf '%s\n' "${name:0:30}"
}

jay_session_for_worktree() {
  local path=$1 name=$2 s
  if zellij list-sessions --short --no-formatting 2>/dev/null | grep -qxF "$name"; then
    printf '%s\n' "$name"; return 0
  fi
  while IFS= read -r s; do
    [[ -n "$(jay_panes_in "$s" "$path" | head -1)" ]] && { printf '%s\n' "$s"; return 0; }
  done < <(jay_live_sessions)
  return 1
}

# The short id in the output $1 of `claude --bg` ("backgrounded · <short id> · <name> ...").
jay_bg_id() {
  grep -oE 'backgrounded · [0-9a-f]{8}' <<<"$1" | grep -oE '[0-9a-f]{8}$' | tail -1
}

# --- Agent names: one name for each agent, where the hub can see to it ---
# The name for a new agent: $1 when no agent in agents JSON $2 (default: `claude agents --json
# --all`) has it, else $1-2, $1-3, ... Every agent that `claude agents` lists counts, also a
# stopped or done one: it still exists. A removed one does not. Names match in any case, as in
# `jay go`. $3: a session id to leave out (an agent that keeps its own name, say after a resume).
jay_unique_name() {
  local agents=${2:-}
  [[ -n "$agents" ]] || agents=$(claude agents --json --all 2>/dev/null)
  [[ -n "$agents" ]] || agents='[]'
  jq -r --arg n "$1" --arg self "${3:-}" '
    [.[] | select(.sessionId != $self) | .name // empty | ascii_downcase] as $taken
    | first(range(1; 1000) | (if . == 1 then $n else "\($n)-\(.)" end)
        | select(ascii_downcase as $c | $taken | index([$c]) | not)) // $n' <<<"$agents" 2>/dev/null \
    || printf '%s\n' "$1"
}

# --- Folder trust: `claude --bg` does not start in a repo that was never trusted ---
# Claude keeps the trust in ~/.claude.json (projects.<path>.hasTrustDialogAccepted), under the
# path of the repo's main checkout: all its worktrees share it. A trusted parent folder of the
# repo does not count. Plain `claude` asks with its trust prompt; `claude --bg` only fails.

# The path Claude keeps the trust of folder $1 under: the main checkout of its repo.
jay_trust_key() {
  local top primary
  top=$(jay_toplevel "$1")
  primary=$(jay_primary "$top")
  (cd "${primary:-$top}" 2>/dev/null && pwd -P)
}

# Folder $1 is trusted. When ~/.claude.json cannot be read, it is: `claude --bg` then decides.
jay_trusted() {
  local key cfg="$HOME/.claude.json"
  key=$(jay_trust_key "$1")
  [[ -n "$key" && -r "$cfg" ]] || return 0
  jq -e --arg k "$key" '.projects[$k].hasTrustDialogAccepted == true' "$cfg" >/dev/null 2>&1 \
    || [[ $? -gt 1 ]]
}

# Trust folder $1 as the trust prompt of `claude` does. Under Claude's own config lock (the
# folder ~/.claude.json.lock; Claude takes a lock over 10 s old as stale), and written through
# a copy, so running sessions never read half a file.
jay_trust() {
  local key cfg="$HOME/.claude.json" lock tmp i got=false rc=0
  key=$(jay_trust_key "$1")
  [[ -n "$key" && -f "$cfg" ]] || return 1
  lock="$cfg.lock"
  for i in $(seq 50); do
    mkdir "$lock" 2>/dev/null && { got=true; break; }
    sleep 0.1
  done
  [[ "$got" == true ]] || return 1
  tmp=$(mktemp "$cfg.jay.XXXXXX") \
    && jq --arg k "$key" '.projects[$k] = ((.projects[$k] // {}) + {hasTrustDialogAccepted: true})' \
      "$cfg" >"$tmp" \
    && [[ -s "$tmp" ]] && mv "$tmp" "$cfg" || rc=1
  rm -f "$tmp"
  rmdir "$lock" 2>/dev/null
  return $rc
}

# --- Agent phases: the one rule of the list, jay all, jay agents and the mod (`jay agents --json`) ---
# input    blocked, or it asks (status waiting)
# failed   state failed
# unread   a turn ended after the user last saw the agent
# working  the process works (status busy); state working with status idle (it waits for its
#          workers) is not working
# idle     seen since its last turn, shown in the middle column now, or new (no first prompt)
# The marks are empty files; their mtime is the time: $JAY_MARKS/ended/<key> (a turn ended:
# the Stop hook, jay-notify) and seen/<key> (the agent came into or left the middle column,
# `jay go` showed it, or its own Ghostty tab was in front when its turn ended). <key> is the id
# of a background agent (its job id), else the session id.
JAY_MARKS=$JAY_STATE

# Set mark $1 (seen, ended) of agent key $2 to now. An empty key does nothing.
jay_mark() {
  [[ -n "${2:-}" ]] || return 0
  mkdir -p "$JAY_MARKS/$1" 2>/dev/null && touch "$JAY_MARKS/$1/$2" 2>/dev/null
  return 0
}

# The key of session id $1, for a hook: the job id of a background agent, which stays when its
# session id changes (a resume, /clear), when the job's state names this session.
jay_agent_key() {
  local job=${CLAUDE_JOB_DIR:-}
  if [[ -n "$job" ]] && jq -e --arg s "$1" '.sessionId == $s or .resumeSessionId == $s' "$job/state.json" >/dev/null 2>&1; then
    basename "$job"
  else
    printf '%s\n' "$1"
  fi
}

# The marks as JSON: {seen: {key: time}, ended: {key: time}} (seconds, with fractions).
jay_agent_marks() {
  { find "$JAY_MARKS/seen" "$JAY_MARKS/ended" -type f -exec stat -f '%N%t%Fm' {} + 2>/dev/null || true; } \
    | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {k: (.[0] | split("/")), t: (.[1] | tonumber)})
      | reduce .[] as $m ({seen: {}, ended: {}}; .[$m.k[-2]][$m.k[-1]] = $m.t)'
}

# The background agents in agents JSON $1 that wait for their first prompt, as a JSON array of
# ids. `claude agents` calls such a new idle agent "blocked", as it does an agent that asks you
# something; its job state says "send a prompt to start".
jay_fresh_ids() {
  local id jobs="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs"
  jq -r '.[] | select(.kind == "background" and .state == "blocked") | .id // empty' <<<"$1" | while IFS= read -r id; do
    [[ "$(jq -r '.needs // ""' "$jobs/$id/state.json" 2>/dev/null)" == "send a prompt to start" ]] && printf '%s\n' "$id"
  done | jq -Rsc 'split("\n") | map(select(. != ""))'
}

# Agents JSON $1 (`claude agents --json --all`) with .phase on each agent (see above). $2: the
# id shown in the middle column, when the caller has it (else jay_hub_shown).
jay_agent_phases() {
  local IFS=$' \t\n' shown
  if (($# > 1)); then shown=$2; else shown=$(jay_hub_shown); fi
  jq -c --arg shown "$shown" --argjson fresh "$(jay_fresh_ids "$1")" --argjson marks "$(jay_agent_marks)" '
    def at($m): [$marks[$m][.id // ""], $marks[$m][.sessionId // ""], 0] | map(. // 0) | max;
    map(. + {phase: (
      if .state == "failed" then "failed"
      elif (.id // "") as $i | $fresh | index([$i]) then "idle"
      elif .state == "blocked" or .status == "waiting" then "input"
      elif (.state == "working" and .status != "idle") or (.state == null and .status == "busy") then "working"
      elif $shown != "" and (.id // .sessionId) == $shown then "idle"
      elif at("ended") > at("seen") then "unread"
      else "idle" end)})' <<<"$1"
}

# --- Hub panes (zellij session "jay"): agent viewer, review ⇄ files ---
# One pane in each column. The agent viewer (middle) and review (right) are layout panes; files
# opens in place over review: zellij keeps review suspended and shows it again when files
# closes. The panes run `jay-pane <role>`, which follows the target in
# $JAY_STATE/<role>.target; a pick writes the target and stops the running program, so the pane
# stays where it is and only its program and title change.

JAY_SESSION=${JAY_SESSION:-jay}

jay_in_hub() {
  [[ "${ZELLIJ_SESSION_NAME:-}" == "$JAY_SESSION" && -z "${CLAUDE_JOB_DIR:-}" ]]
}

# The hub runs with a terminal attached, wherever the caller is (an agent viewed in the hub
# runs outside it).
jay_hub_live() {
  jay_session_has_client "$JAY_SESSION"
}

jay_hub_panes() {
  zellij -s "$JAY_SESSION" action list-panes -a -j -c 2>/dev/null | jq -c '.[] | select(.is_plugin | not)'
}

# The files of role $1 (agent, review, files); the folder is made for the write that may follow.
jay_hub_target_file() { jay_state_dir; printf '%s/%s.target\n' "$JAY_STATE" "$1"; }
jay_hub_pane_file() { jay_state_dir; printf '%s/%s.pane\n' "$JAY_STATE" "$1"; }

# Forget all hub pane targets (a fresh hub).
jay_hub_reset() {
  local role
  for role in agent review files; do rm -f "$(jay_hub_target_file $role)" "$(jay_hub_pane_file $role)"; done
  rm -f "$JAY_HIDDEN"
}

# jay-pane $1 (pid $2) ends.
jay_hub_pane_gone() {
  local file pid
  file=$(jay_hub_pane_file "$1")
  IFS=$'\t' read -r _ pid 2>/dev/null <"$file"
  [[ "${pid:-}" == "$2" ]] && rm -f "$file"
  return 0
}

# "terminal_<id><TAB>pid" of the running jay-pane for role $1; fails when there is none.
# A recorded pane that zellij no longer lists is lost (an in-place pane opened over a suspended
# one): its jay-pane still runs and takes every pick, but nobody sees it. It is stopped and
# forgotten. A pane of the role without a record is taken on when it is the only one and one
# jay-pane of the role runs in the hub. When zellij does not answer, the record is trusted.
jay_hub_role() {
  local file pane="" pid="" lost="" panes pids
  file=$(jay_hub_pane_file "$1")
  IFS=$'\t' read -r pane pid 2>/dev/null <"$file"
  if [[ -n "$pane" && -n "$pid" ]] && ps -o command= -p "$pid" 2>/dev/null | grep -q "jay-pane $1"; then
    panes=$(jay_hub_panes)
    if [[ -z "$panes" ]] || jq -e --argjson id "$pane" 'select(.id == $id and (.exited | not))' <<<"$panes" >/dev/null; then
      printf 'terminal_%s\t%s\n' "$pane" "$pid"
      return 0
    fi
    lost=$pid
    jay_kill_children "$pid"
    kill -TERM "$pid" 2>/dev/null
    jay_hub_pane_gone "$1" "$pid"
  else
    panes=$(jay_hub_panes)
  fi
  pane=$(jq -r --arg role "$1" \
    'select((.exited | not) and ((.terminal_command // "") | test("jay-pane " + $role + "$"))) | .id' <<<"$panes")
  [[ -n "$pane" && "$pane" != *$'\n'* ]] || return 1
  # pgrep -a: from inside a hub pane the server is an ancestor, which pgrep leaves out without it.
  pids=$(pgrep -P "$(pgrep -a -f "zellij --server .*/$JAY_SESSION\$" | head -1)" -f "jay-pane $1\$" | grep -vxF "${lost:-none}")
  [[ -n "$pids" && "$pids" != *$'\n'* ]] || return 1
  printf '%s\t%s\n' "$pane" "$pids" >"$file.$$" && mv "$file.$$" "$file"
  printf 'terminal_%s\t%s\n' "$pane" "$pids"
}

# Wait up to 2 s until pane $1 (a terminal id) is shown, not suspended under another pane.
jay_hub_wait_shown() {
  local i
  for i in $(seq 20); do
    jay_hub_panes | jq -e --argjson id "$1" 'select(.id == $id and (.is_suppressed | not))' >/dev/null && return 0
    sleep 0.1
  done
  return 1
}

jay_hub_write_target() {
  local file
  file=$(jay_hub_target_file "$1")
  # The user saw the agent that leaves the middle column and the one that comes (jay_agent_phases).
  if [[ "$1" == agent ]]; then
    jay_mark seen "$(cut -f1 "$file" 2>/dev/null)"
    jay_mark seen "${2%%$'\t'*}"
  fi
  printf '%s\n' "$2" >"$file.$$" && mv "$file.$$" "$file"
}

# The id in the hub's middle column (the agent target) while its jay-pane runs, else
# nothing. No zellij call: jay_agent_phases reads it every few seconds.
jay_hub_shown() {
  local pane="" pid=""
  IFS=$'\t' read -r pane pid 2>/dev/null <"$(jay_hub_pane_file agent)"
  if [[ -n "$pid" ]] && ps -o command= -p "$pid" 2>/dev/null | grep -q "jay-pane agent"; then
    cut -f1 "$(jay_hub_target_file agent)" 2>/dev/null
  fi
  return 0
}

# Wait up to 2 s for the new jay-pane of role $1 to start.
jay_hub_role_ready() {
  local i
  for i in $(seq 40); do jay_hub_role "$1" >/dev/null && return 0; sleep 0.05; done
  return 1
}

# Callers run it inside `IFS=$'\t' read … < <(…)`, whose IFS bash 3.2 passes on: split the pids
# with the usual IFS.
jay_kill_children() {
  local child IFS=$' \t\n'
  for child in $(pgrep -P "$1"); do
    jay_kill_children "$child"
    kill -TERM "$child" 2>/dev/null
  done
  return 0
}

# Point the running hub pane of role $1 at target line $2. Prints "terminal_<id><TAB>changed",
# changed being 1 when the pane restarts its program for the new target, else 0.
# Fails when no pane of that role runs.
jay_hub_point() {
  local pane pid
  IFS=$'\t' read -r pane pid < <(jay_hub_role "$1") || return 1
  if [[ "$(cat "$(jay_hub_target_file "$1")" 2>/dev/null)" == "$2" ]]; then
    printf '%s\t0\n' "$pane"
    return 0
  fi
  jay_hub_write_target "$1" "$2"
  jay_kill_children "$pid"
  printf '%s\t1\n' "$pane"
}

# In zellij 0.45 `focus-pane-id` from the CLI sets a focus of its own, not the terminal's, and on
# a suspended pane it makes that pane float. `move-focus` moves the terminal's focus.

# Move the focus to the middle column (the agent viewer), from any column: left twice reaches
# the list, then one step right. From the tasks tab, go to the hub's tab first.
jay_hub_focus_middle() {
  zellij -s "$JAY_SESSION" action go-to-tab-name hub >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action move-focus right >/dev/null 2>&1
  return 0
}

# Run "$@" holding the hub lock, so two picks (sidebar, /jay go, a notice click) never move
# the hub's panes at the same time. A lock older than 5 s is taken over.
jay_hub_locked() {
  local lock="$JAY_STATE/hub.lock" i rc=0
  jay_state_dir
  for i in $(seq 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  [[ -d "$lock" ]] || mkdir "$lock"
  "$@" || rc=$?
  rmdir "$lock" 2>/dev/null
  return $rc
}

# Show background agent $1 (short id) named $2 from folder $3 in the hub's middle column: the
# viewer pane follows the new agent. The focus goes there. With $4 = interactive, $1 is a
# session id and the viewer only says where that agent runs.
jay_hub_show() {
  local id=$1 name=$2 cwd=$3 line viewer changed
  line=$(printf '%s\t%s' "$id" "$cwd")
  [[ "${4:-}" == interactive ]] && line=$(printf '%s\tinteractive\t%s' "$line" "$name")
  IFS=$'\t' read -r viewer changed < <(jay_hub_point agent "$line") || return 1
  [[ "$changed" == 1 ]] && zellij -s "$JAY_SESSION" action rename-pane -p "$viewer" "$name" >/dev/null 2>&1
  jay_hub_focus_middle
}

# --- The hub Claude: a background agent named "hub" in the first root folder, to start and
# steer agents and to answer questions across repos. The "◆ hub" row of the list shows it in
# the middle column, and a fresh hub opens on it. Its short id is in JAY_HUB_CLAUDE_FILE.

JAY_HUB_CLAUDE_FILE=${JAY_HUB_CLAUDE_FILE:-$JAY_STATE/hub-claude}

# The first words of the hub Claude's prompt: they tell it from other agents (respawnFlags in
# the job's state.json, as for $JAY_ORCH_MARK).
JAY_HUB_MARK="You are the hub Claude"

# Added to the hub Claude's system prompt. It must start with $JAY_HUB_MARK.
jay_hub_claude_prompt() {
  cat <<EOF
You are the hub Claude of jay, a worktree hub: a zellij session "jay" with a list of worktrees and
Claude agents on the left, one agent in the middle column (you now) and a review of that agent's
turns on the right. The user comes to you to start and steer agents, and with questions across
repos. Each agent is a background Claude session in its own git worktree. Repos live under
$JAY_ROOTS (a folder per client, then the repo; worktrees are siblings named <repo>.<branch>).

- Agents: \`claude agents --json --all\` (id, name, cwd, state, status); recent output:
  \`claude logs <id>\`; what an agent did per turn: \`git log refs/wt-turns/<id>/base..refs/wt-turns/<id>/head\`
  in its worktree.
- Worktrees with git state and task notes: \`jay all --json\`; in a repo also \`wt list\`
  (worktrunk).
- New worktree with an agent: in the repo's main checkout, \`jay new <branch> -t "<task>" -- <prompt>\`
  (-a: an idle agent); for a branch whose worktree exists, the same command starts an agent in
  that worktree. It gives the agent a name no other agent has. Start agents only when the user
  asks or agrees.
  "Workspace not trusted": Claude never ran in that repo. Do not change ~/.claude.json; tell the
  user to press n on one of its worktrees in the list, or N on its repo row (both ask to trust
  the repo), or to run \`c\` in it.
- Send a prompt to a running agent: the ListAgents and SendMessage tools.
- Orchestrators: a repo can have one, an agent in its main checkout with an orchestrator prompt
  (◇ in the list). \`jay agents --orchestrators\` lists them (main checkout, id, name). Send work
  for such a repo to its orchestrator (SendMessage). For a repo without one, start workers
  yourself with \`jay new\`, or tell the user that n on the repo's main checkout row starts one.
  An orchestrator only reads, plans and reviews: skills that change a branch run in its workers.
- Show an agent in the middle column: \`jay go <id or name>\`; \`jay go hub\` comes back to you.
  Prefer ids: two agents made outside the hub can have one name.
- Dev servers and other long-running commands: the hub's "tasks" tab (\`jay run ls --json\`,
  \`jay run log <task>\`, \`jay run -n <name> -w -- <command>\`), not a background Bash call.
- Read other worktrees in place. Do not edit files in an agent's worktree, and never remove
  worktrees or agents (\`wt remove\`, \`claude rm\`, \`wt step prune\`) unless the user asks.
  Never \`claude --resume\` a conversation that a live agent holds.
EOF
}

# --- Orchestrators: an agent in a repo's main checkout plans and starts workers, one in a worktree
# for each change, so that work does not pile up on main and agents do not move between
# worktrees. The list starts one with this prompt (n on a main checkout) and marks it with ◇.
# Claude keeps the prompt in the job's state.json (respawnFlags); its first words
# ($JAY_ORCH_MARK) tell an orchestrator from another agent in the main checkout.

JAY_ORCH_MARK="You are the orchestrator"

# Added to the system prompt of an orchestrator of repo $1 in main checkout $2. It must start
# with $JAY_ORCH_MARK.
jay_orchestrator_prompt() {
  cat <<EOF
You are the orchestrator of the repo $1, in its main checkout $2, in jay, a worktree hub: a list
of worktrees and Claude agents. Each worker is a background Claude session in its own git
worktree (siblings named $1.<branch>). Plan, read, review and answer questions here; give each
change to a worker. Keep the main checkout free of work.

- New worker for a change: here, \`jay new <branch> -t "<task>" -- <prompt>\` (a new worktree
  and a background agent in it). Give it a prompt it can act on alone: the goal, the files, how
  to test. Start workers only when the user asks or agrees.
- Do not edit files in the main checkout, and do not use EnterWorktree: a change that you make
  yourself takes you into its worktree. When the user tells you to make a change yourself, do
  as they say.
- Skills and commands that change the branch or write (make or switch a branch, commit, rebase,
  push, stash, edit files) run in the worker of that branch, never here; the jay-guard hook
  denies such git commands here. A skill that only the user can start: tell the user which
  worker is ready for which command.
- Workers: \`claude agents --json --all\` (id, name, cwd, state, status); recent output:
  \`claude logs <id>\`; what a worker did per turn: \`git log refs/wt-turns/<id>/base..refs/wt-turns/<id>/head\`
  in its worktree. Send a prompt to a worker: the ListAgents and SendMessage tools.
- Worktrees with git state and task notes: \`wt list\` (worktrunk).
- Read the workers' worktrees in place; do not edit files in them. Never merge, and never remove
  worktrees or agents (\`wt merge\`, \`wt remove\`, \`claude rm\`), unless the user asks.
EOF
}

# What the job state.json files tell about the background agents in agents JSON $1 (from
# `claude agents --json --all`), as a JSON object id: {home, tree, orch, cwd, ver, tempo, tasks,
# created}. For an agent in a
# worktree it entered (EnterWorktree): home is the folder it came from (state.json cwd), tree the
# folder it is in now; else both are null. Claude wakes a stopped agent in its home, and `claude
# agents` gives the home as the folder of one that does not run now. Where it is now:
# state.json worktreePath for a worktree that EnterWorktree made; else (EnterWorktree with the
# path of a worktree that was there already leaves worktreePath empty) the folder `claude agents`
# gives while it runs, or the last folder in its transcript. Such an agent does not go with the
# worktree. orch: the agent has the orchestrator prompt. For the respawn rule (jay_respawn_plan):
# cwd is the folder Claude wakes and respawns the agent in (state.json cwd, its home); ver the
# Claude Code version of its last turn (cliVersion: a respawn does not change it, the next turn
# does); tempo "active" while a turn runs; tasks the count of its background tasks, crons and
# wakeups (inFlight); created the time Claude made the job, in ms (a respawn keeps it, but
# changes startedAt). An interactive session has no job, so no entry.
jay_jobs() {
  local IFS=$' \t\n' id log sid cwd cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" files=() base last
  for id in $(jq -r '.[] | select(.kind == "background") | .id // empty' <<<"$1"); do
    [[ -f "$cfg/jobs/$id/state.json" ]] && files+=("$cfg/jobs/$id/state.json")
  done
  ((${#files[@]})) || { echo '{}'; return 0; }
  base=$(jq -nc --arg mark "$JAY_ORCH_MARK" '[inputs | {(input_filename | split("/")[-2]): {
      cwd: (.cwd // .originCwd // ""), wt: .worktreePath, log: (.linkScanPath // ""),
      sid: (.resumeSessionId // .sessionId // ""),
      orch: (.respawnFlags // [] | any(.[]; type == "string" and startswith($mark))),
      ver: (.cliVersion // ""), tempo: (.tempo // ""),
      tasks: ((.inFlight.tasks // 0) + (.inFlight.queued // 0) + (if .inFlight.wake != null then 1 else 0 end)),
      created: (.createdAt // "" | sub("\\.[0-9]+Z$"; "Z") | (try (fromdateiso8601 * 1000) catch null))}}] | add // {}' \
    "${files[@]}" 2>/dev/null) || base='{}'
  # The last folder in the transcript of each agent that does not run and has no worktreePath.
  # Each line of a transcript has its cwd; the tail of a big one is enough.
  last=$(jq -r --argjson agents "$1" '
      ($agents | map(select(.pid != null) | .id) | map({(. // ""): true}) | add // {}) as $runs
      | to_entries[] | select(.value.wt == null and ($runs[.key] | not))
      | [.key, (.value.log | if . == "" then "-" else . end), .value.sid] | @tsv' <<<"$base" \
    | while IFS=$'\t' read -r id log sid; do
        [[ -f "$log" ]] || log=$(compgen -G "$cfg/projects/*/$sid.jsonl" | head -1)
        [[ -n "$log" && -f "$log" ]] || continue
        cwd=$(tail -c 1000000 "$log" | grep -o '"cwd":"[^"]*"' | tail -1)
        cwd=${cwd#\"cwd\":\"}
        [[ -n "$cwd" ]] && printf '%s\t%s\n' "$id" "${cwd%\"}"
      done | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}')
  [[ -n "$last" ]] || last='{}'
  # A folder in the home (a cd) is no worktree, unless it is one of Claude's (.claude/worktrees).
  jq -c --argjson agents "$1" --argjson last "$last" '
    ($agents | map(select(.kind == "background" and .id != null) | {(.id): .}) | add // {}) as $ag
    | with_entries(.key as $id | .value |= (.cwd as $home
        | (if .wt != null then .wt
           elif $ag[$id].pid != null then $ag[$id].cwd // null
           else $last[$id] end) as $now
        | (if .wt != null then .wt
           elif $now == null or $now == "" or $now == $home then null
           elif ($now | startswith($home + "/")) and ($now | test("/\\.claude/worktrees/") | not) then null
           else $now end) as $tree
        | {home: (if $tree != null then $home else null end), tree: $tree, orch,
           cwd: $home, ver, tempo, tasks, created}))' <<<"$base" 2>/dev/null \
    || echo '{}'
}

# The agents with the orchestrator prompt in agents JSON $1 (jobs JSON $2, from jay_jobs), as a
# JSON object session id: {id, name, home, rank}. home is the folder the agent belongs to (the
# one it came from, when it is in a worktree it entered). One orchestrator for each repo: rank 0
# is the oldest in its home, the orchestrator; rank 1 and up are extra ones (a resumed copy, say).
# Oldest by the job's creation: a respawn gives an agent a new startedAt. A stopped agent does
# not count. The callers check that home is a main checkout.
jay_orch_ranks() {
  jq -c --argjson jobs "$2" '
    [.[] | select(.kind == "background" and .state != "stopped" and ($jobs[.id // ""].orch // false))
      | {sid: .sessionId, id, name: (.name // .id), home: ($jobs[.id].home // .cwd),
         t: ($jobs[.id].created // .startedAt // 0)}]
    | group_by(.home) | map(sort_by(.t) | to_entries[] | {(.value.sid): ((.value | del(.sid, .t)) + {rank: .key})})
    | add // {}' <<<"$1"
}

# The orchestrator of each main checkout, one line each: main checkout<TAB>id<TAB>name.
# Optional $1: only the one of that main checkout.
jay_orchestrators() {
  local agents home id name
  agents=$(claude agents --json --all 2>/dev/null) || agents='[]'
  while IFS=$'\t' read -r home id name; do
    [[ -n "$home" && ( -z "${1:-}" || "$home" == "$1" ) ]] || continue
    [[ "$(jay_primary "$home")" == "$home" ]] && printf '%s\t%s\t%s\n' "$home" "$id" "$name"
  done < <(jay_orch_ranks "$agents" "$(jay_jobs "$agents")" \
    | jq -r 'to_entries[] | .value | select(.rank == 0) | [.home, .id, .name] | @tsv')
  return 0
}

# The newest background agent in agents JSON $1 with the hub Claude's prompt, as a short id; fails
# when there is none.
jay_hub_claude_find() {
  local IFS=$' \t\n' id dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs"
  for id in $(jq -r 'sort_by(-(.startedAt // 0)) | .[] | select(.kind == "background") | .id // empty' <<<"$1"); do
    jq -e --arg mark "$JAY_HUB_MARK" '.respawnFlags // [] | any(.[]; type == "string" and startswith($mark))' \
      "$dir/$id/state.json" >/dev/null 2>&1 && { printf '%s\n' "$id"; return 0; }
  done
  return 1
}

# --- Agents whose home is gone ---
# Claude wakes a stopped background agent in its home, the folder it started in (see jay_jobs),
# also when it went into another worktree since. When that home is gone, the wake fails ("Couldn't
# wake <id> — Workspace not trusted. <home> could not be resolved on disk"), and so does
# `claude --bg --resume <session id>` without options: it wakes the same agent. With options,
# `claude --bg --resume` starts a copy: a new agent with a new id and the same conversation,
# whose home is the folder it starts in. So the hub continues such an agent as a copy in the
# worktree it is in (jay_continue_in). The old entry then is "replaced" (a mark
# $JAY_STATE/replaced/<old id>, with the new id): the list hides it and removes it when that is
# safe (jay_drop_replaced).

# The ids of the replaced agents, as a JSON array.
jay_replaced_ids() {
  { ls "$JAY_STATE/replaced" 2>/dev/null || true; } | jq -Rsc 'split("\n") | map(select(. != ""))'
}

# The background agents in agents JSON $1 (jobs JSON $2, from jay_jobs) that are in a worktree
# they entered and whose home is gone, but not the replaced ones. One line each:
# id<TAB>name<TAB>home<TAB>tree<TAB>fix<TAB>runs. fix: move (the tree is on disk: the agent can
# go on there) or lost (the tree is gone too). runs: 1 while its process runs (it works on, but
# cannot wake after it stops), else 0.
jay_stranded() {
  local IFS=$' \t\n' id name home tree runs
  jq -r --argjson jobs "$2" --argjson replaced "$(jay_replaced_ids)" '.[]
    | select(.kind == "background" and .id != null and $jobs[.id].tree != null)
    | select(.id as $i | $replaced | index([$i]) | not)
    | [.id, (.name // .id), $jobs[.id].home, $jobs[.id].tree, (if .pid != null then 1 else 0 end)] | @tsv' <<<"$1" \
    | while IFS=$'\t' read -r id name home tree runs; do
        [[ -n "$home" && ! -d "$home" ]] || continue
        if [[ -d "$tree" ]]; then
          printf '%s\t%s\t%s\t%s\tmove\t%s\n' "$id" "$name" "$home" "$tree" "$runs"
        else
          printf '%s\t%s\t%s\t%s\tlost\t%s\n' "$id" "$name" "$home" "$tree" "$runs"
        fi
      done
  return 0
}

# The main checkout of the repo of folder $1, also when $1 is gone (a removed worktree): the first
# folder up from it that is on disk, or a folder <repo> beside a gone <repo>.<branch>. Empty when
# none is a repo.
jay_repo_main() {
  local p=$1 base cand
  while [[ -n "$p" && "$p" != / ]]; do
    if [[ -d "$p" ]]; then
      git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || return 0
      jay_primary "$p"
      return 0
    fi
    base=${p##*/}
    while [[ "$base" == *.* ]]; do
      base=${base%.*}
      cand=${p%/*}/$base
      if [[ -n "$base" && -d "$cand" ]] && git -C "$cand" rev-parse --git-dir >/dev/null 2>&1; then
        jay_primary "$cand"
        return 0
      fi
    done
    p=${p%/*}
  done
  return 0
}

# Stop background agent $1 and wait (up to 10 s) until its process is gone.
jay_stop_agent() {
  local i
  claude stop "$1" >/dev/null 2>&1
  for i in $(seq 20); do
    claude agents --json --all 2>/dev/null \
      | jq -e --arg i "$1" 'any(.[]; .id == $i and .pid != null)' >/dev/null || return 0
    sleep 0.5
  done
  return 1
}

# Background agent $1 (an id; it must not run) goes on in folder $2 as a copy: `claude --bg
# --resume` of its conversation with its saved options (state.json respawnFlags: name, model,
# system prompt), so Claude starts a copy there (see above). Print the new id, and mark the old
# entry replaced. Without CLAUDE*/ANTHROPIC* variables, as in jay new. On a fault: Claude's
# output on stderr, and return 1.
jay_continue_in() {
  local id=$1 dir=$2 state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs/$1/state.json" sid out new name
  local wt self="" flags=() strip=() var
  [[ -f "$state" && -d "$dir" ]] || { echo "No job $id, or no folder $dir." >&2; return 1; }
  sid=$(jq -r '.resumeSessionId // .sessionId // empty' "$state")
  [[ -n "$sid" ]] || { echo "Job $id has no session id." >&2; return 1; }
  # The saved options without the name: the copy gets its own (jay_unique_name). It keeps the
  # old name when the old entry goes at once (jay_drop_replaced: no recorded worktree on disk).
  eval "flags=($(jq -r '.respawnFlags // [] | map(select(type == "string"))
    | reduce .[] as $f ({out: [], skip: false};
        if .skip then .skip = false elif $f == "--name" or $f == "-n" then .skip = true
        elif ($f | startswith("--name=")) then . else .out += [$f] end) | .out | @sh' "$state"))"
  name=$(jq -r '.name // (.respawnFlags // [] | (index("--name") // index("-n")) as $i
    | if $i != null then .[$i + 1] else null end) // empty' "$state")
  [[ -n "$name" ]] || name=$(claude agents --json --all 2>/dev/null \
    | jq -r --arg i "$id" 'first(.[] | select(.id == $i) | .name // empty) // empty' 2>/dev/null)
  wt=$(jq -r '.worktreePath // empty' "$state")
  [[ -n "$wt" && -d "$wt" ]] || self=$(jq -r '.sessionId // empty' "$state")
  # Always with an option: without, Claude would wake the old agent in its home.
  flags=(--name "$(jay_unique_name "${name:-$id}" "" "$self")" ${flags[@]+"${flags[@]}"})
  for var in $(compgen -e | grep -E '^(CLAUDE|ANTHROPIC)'); do strip+=(-u "$var"); done
  out=$(cd "$dir" && env ${strip[@]+"${strip[@]}"} claude --bg --resume "$sid" "${flags[@]}" 2>&1)
  new=$(jay_bg_id "$out")
  if [[ -z "$new" ]]; then
    printf '%s\n' "$out" >&2
    return 1
  fi
  if [[ "$new" != "$id" ]]; then
    jay_state_dir
    mkdir -p "$JAY_STATE/replaced" && printf '%s\n' "$new" >"$JAY_STATE/replaced/$id"
  fi
  printf '%s\n' "$new"
}

# Remove the replaced entry $1 (`claude rm`), when that is safe: `claude rm` deletes the worktree
# Claude recorded for the agent (state.json worktreePath), where the copy can work now. So while
# that worktree is on disk, the entry stays (return 1); it goes with that worktree (d) or the
# prune. Its transcript stays.
jay_drop_replaced() {
  local wt state="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs/$1/state.json"
  # Removed already (by hand, say): only the mark goes.
  [[ -f "$state" ]] || { rm -f "$JAY_STATE/replaced/$1"; return 0; }
  wt=$(jq -r '.worktreePath // empty' "$state" 2>/dev/null)
  [[ -n "$wt" && -d "$wt" ]] && return 1
  claude rm "$1" >/dev/null 2>&1 || return 1
  rm -f "$JAY_STATE/replaced/$1"
  return 0
}

# The short id of the hub Claude. When the id file has none that `claude agents` lists, a hub
# Claude the file lost (a new state folder) is taken on. When there is none (never started, or
# `claude rm` removed it), start it, and wait until `claude agents` lists it. Its name is "hub",
# or "hub-2"... when another agent has that name. A stopped one stays: `claude attach` opens it
# again. A lock keeps two callers (the pane at hub start, a list pick) from starting two.
jay_hub_claude() {
  local lock="$JAY_STATE/hub-claude.lock" id out var i agents rc=0
  local strip=() dirs=() args=()
  jay_state_dir
  for i in $(seq 150); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  [[ -d "$lock" ]] || mkdir "$lock"
  id=$(cat "$JAY_HUB_CLAUDE_FILE" 2>/dev/null)
  agents=$(claude agents --json --all 2>/dev/null) || agents='[]'
  if [[ -z "$id" ]] || ! jq -e --arg id "$id" 'any(.[]; .id == $id)' <<<"$agents" >/dev/null 2>&1; then
    id=$(jay_hub_claude_find "$agents") && printf '%s\n' "$id" >"$JAY_HUB_CLAUDE_FILE"
  fi
  if [[ -z "$id" ]]; then
    # An inherited CLAUDE_CODE_CHILD_SESSION (a caller in an agent) hides a session from
    # `claude agents`: start it without CLAUDE*/ANTHROPIC* variables.
    for var in $(compgen -e | grep -E '^(CLAUDE|ANTHROPIC)'); do strip+=(-u "$var"); done
    # It starts in the first root; the other roots are added folders.
    IFS=: read -ra dirs <<<"$JAY_ROOTS"
    for ((i = 1; i < ${#dirs[@]}; i++)); do args+=(--add-dir "${dirs[i]}"); done
    out=$(cd "${dirs[0]:-$HOME}" && env ${strip[@]+"${strip[@]}"} claude --bg --name "$(jay_unique_name hub "$agents")" \
      ${args[@]+"${args[@]}"} --append-system-prompt "$(jay_hub_claude_prompt)" 2>&1)
    id=$(jay_bg_id "$out")
    if [[ -n "$id" ]]; then
      printf '%s\n' "$id" >"$JAY_HUB_CLAUDE_FILE"
      for i in $(seq 20); do
        claude agents --json --all 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
        sleep 0.5
      done
    else
      printf '%s\n' "$out" >&2
      rc=1
    fi
  fi
  rmdir "$lock" 2>/dev/null
  ((rc == 0)) && printf '%s\n' "$id"
  return $rc
}

# The hub Claude's id when it has one, without starting it.
jay_hub_claude_id() {
  cat "$JAY_HUB_CLAUDE_FILE" 2>/dev/null || true
}

# Move the cursor of each running list (jay-sidebar's fzf, through its --listen socket) to the
# row of the agent with session id $1, so the cursor follows a pick made elsewhere (a notice
# click, `jay go`, a new agent). A new agent's row may not be there yet: then reload and wait up
# to 3 s for it. `pos` must come after a reload ends: the list's --track puts the cursor back
# on the old row when a reload ends.
jay_list_follow() {
  local sid=$1 sock pid pos i
  for sock in "$JAY_STATE"/sidebar.*.sock; do
    [[ -S "$sock" ]] || continue
    pid=${sock##*/sidebar.}; pid=${pid%.sock}
    kill -0 "$pid" 2>/dev/null || continue
    for i in $(seq 12); do
      pos=$(curl -s --max-time 2 --unix-socket "$sock" 'http://localhost?limit=1000' 2>/dev/null \
        | jq -r --arg s "$sid" '[.matches[] | .text | split("\t")[1]] | index($s) // empty | . + 1')
      [[ -n "$pos" ]] && break
      ((i == 1)) && curl -s --max-time 2 --unix-socket "$sock" -X POST http://localhost \
        -d 'reload-sync(jay-sidebar --rows)' >/dev/null 2>&1
      sleep 0.25
    done
    [[ -n "$pos" ]] && curl -s --max-time 2 --unix-socket "$sock" -X POST http://localhost -d "pos($pos)" >/dev/null 2>&1
  done
  return 0
}

# --- Hub review (tuicr) and files (yazi) panes, following the picked worktree ---

# The repo of the worktree $1, for the review and files titles (no branch: the list shows it).
jay_hub_title() {
  local client repo branch top
  IFS=$'\t' read -r client repo branch top < <(jay_describe "$1")
  printf '%s\n' "$repo"
}

# Review mode: turns (the agent's turn chain) or commits (the branch's commits).
JAY_MODE="$JAY_STATE/review.mode"
jay_hub_mode() {
  if [[ "$(cat "$JAY_MODE" 2>/dev/null)" == commits ]]; then printf 'commits\n'; else printf 'turns\n'; fi
}
jay_hub_toggle_mode() {
  local next=turns
  [[ "$(jay_hub_mode)" == turns ]] && next=commits
  jay_state_dir
  printf '%s\n' "$next" >"$JAY_MODE"
}

# Point review (and files, when shown) at the worktree that holds $1.
# $2: the agent's id, to review that agent's turns; empty for a worktree pick.
jay_hub_target() {
  local top title pane changed
  top=$(jay_toplevel "$1")
  title=$(jay_hub_title "$top")
  if IFS=$'\t' read -r pane changed < <(jay_hub_point review "$(printf '%s\t%s' "$top" "${2:-}")"); then
    [[ "$changed" == 1 ]] && zellij -s "$JAY_SESSION" action rename-pane -p "$pane" "$(jay_hub_pane_title review "$title")" >/dev/null 2>&1
  fi
  if IFS=$'\t' read -r pane changed < <(jay_hub_point files "$top"); then
    [[ "$changed" == 1 ]] && zellij -s "$JAY_SESSION" action rename-pane -p "$pane" "$(jay_hub_pane_title files "$title")" >/dev/null 2>&1
  fi
  # The hub tab's banner shows the picked worktree (Ctrl g Tab goes to its tasks tab).
  ("$HOME/.local/bin/jay-run" --where "$top" >/dev/null 2>&1 &)
  return 0
}

# Title of the pane of role $1 (review or files) on worktree title $2 (the repo): review's
# starts with its mode. Both end with the pane's keys, the only place they can show (tuicr and
# yazi fill the pane).
jay_hub_pane_title() {
  case $1 in
    review) if [[ "$(jay_hub_mode)" == commits ]]; then
        printf 'commits · %s   e files · t turns\n' "$2"
      else
        printf 'turns · %s   e files · t commits\n' "$2"
      fi ;;
    files) printf 'files · %s   e review · o open here · O editor tab · W open with\n' "$2" ;;
  esac
}

# Title the pane of role $1 (review or files) after the worktree in its target. zellij does not
# rename a suspended pane, so review gets its title again when files closes.
jay_hub_retitle() {
  local pane top
  IFS=$'\t' read -r pane _ < <(jay_hub_role "$1") || return 0
  top=$(cut -f1 "$(jay_hub_target_file "$1")" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  zellij -s "$JAY_SESSION" action rename-pane -p "$pane" "$(jay_hub_pane_title "$1" "$(jay_hub_title "$top")")" >/dev/null 2>&1
}

# Show files (yazi) in place over review, in the review's worktree. Not while review is hidden
# (Ctrl g v).
jay_hub_show_files() {
  local review top pane
  [[ -f "$JAY_HIDDEN" ]] && return 0
  jay_hub_role files >/dev/null && return 0
  IFS=$'\t' read -r review _ < <(jay_hub_role review) || return 0
  top=$(cut -f1 "$(jay_hub_target_file review)" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  jay_hub_wait_shown "${review#terminal_}" || return 0
  jay_hub_write_target files "$top"
  pane=$(zellij -s "$JAY_SESSION" action new-pane --in-place --pane-id "$review" --close-on-exit \
    --name "$(jay_hub_pane_title files "$(jay_hub_title "$top")")" --cwd "$top" -- "$HOME/.local/bin/jay-pane" files)
  [[ "$pane" == terminal_* ]] && jay_hub_role_ready files
  return 0
}

# Show review: close files over it.
jay_hub_show_review() {
  local pane
  IFS=$'\t' read -r pane _ < <(jay_hub_role files) || return 0
  zellij -s "$JAY_SESSION" action close-pane --pane-id "$pane" >/dev/null 2>&1
  jay_hub_retitle review
}

# --- Review hidden (Ctrl g v): the middle column takes review's width ---
# zellij 0.45 cannot hide a tiled pane. Review becomes a floating pane of no size in the bottom
# right corner, and the tab's floating panes hide; tuicr runs on, so your place and draft
# comments stay. A new floating pane (Ctrl g Tab, Ctrl g r) shows the floating panes again, and
# when it closes the hidden review gets the keys: jay_hub_keep_hidden hides them again.
# An embedded floating pane goes under the biggest pane, so show opens a placeholder right of
# the middle column and stacks review with it: a floating pane takes the place of the pane it is
# stacked with. The placeholder then closes. Files closes before review hides (a floating files
# pane loses the review under it) and opens again after show.
# The file holds review's share of the tab's width and 1 when files was open.
JAY_HIDDEN="$JAY_STATE/review.hidden"

# Review is hidden (its pane floats): print the id of its tab.
jay_hub_review_hidden() {
  local pane
  IFS=$'\t' read -r pane _ < <(jay_hub_role review) || return 1
  jay_hub_panes | jq -er --argjson id "${pane#terminal_}" 'select(.id == $id and .is_floating) | .tab_id'
}

# Wait while pane $1 (a terminal id, as in ZELLIJ_PANE_ID) is open, up to $2 seconds (default 5).
jay_hub_wait_gone() {
  local end=$((SECONDS + ${2:-5}))
  [[ -n "${1:-}" ]] || return 0
  while ((SECONDS < end)); do
    jay_hub_panes | jq -e --argjson id "$1" 'select(.id == $id)' >/dev/null || return 0
    sleep 0.2
  done
  return 1
}

jay_hub_hide_review() {
  local review tab cols total files=0
  IFS=$'\t' read -r review _ < <(jay_hub_role review) || return 0
  if jay_hub_role files >/dev/null; then
    files=1
    jay_hub_show_review
    jay_hub_wait_shown "${review#terminal_}" || return 0
  fi
  read -r tab cols total < <(jay_hub_panes | jq -rs --argjson id "${review#terminal_}" '
    (map(select(.id == $id)) | first) as $r | select($r != null and ($r.is_floating | not))
    | [$r.tab_id, $r.pane_columns, ([.[] | select(.tab_id == $r.tab_id and (.is_floating | not)) | .pane_x + .pane_columns] | max)]
    | @tsv')
  [[ -n "${total:-}" ]] || return 0
  printf '%s %s\n' "$((cols * 100 / total))" "$files" >"$JAY_HIDDEN"
  zellij -s "$JAY_SESSION" action toggle-pane-embed-or-floating -p "$review" >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action change-floating-pane-coordinates -p "$review" -x 100% -y 100% --width 1 --height 1 >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
}

# Show the hidden review in the right column again, at its old width. --focus: the focus goes to
# review; else it goes back to the column that had it.
jay_hub_unhide_review() {
  local review tab share files list place i cols total
  IFS=$'\t' read -r review _ < <(jay_hub_role review) || return 0
  tab=$(jay_hub_review_hidden) || { rm -f "$JAY_HIDDEN"; return 0; }
  read -r share files <"$JAY_HIDDEN" 2>/dev/null
  [[ "${share:-}" =~ ^[0-9]+$ ]] || share=35
  # The focus moves below act on the tiled panes only while the floating ones are hidden.
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
  list=$(jay_hub_panes | jq -rs --argjson t "$tab" \
    'any(.[]; .tab_id == $t and (.is_floating | not) and .is_focused and .pane_x == 0)')
  jay_hub_focus_middle
  place=$(zellij -s "$JAY_SESSION" action new-pane --direction right --close-on-exit -- sleep 10)
  [[ "$place" == terminal_* ]] || return 0
  zellij -s "$JAY_SESSION" action stack-panes -- "$place" "$review" >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action close-pane -p "$place" >/dev/null 2>&1
  rm -f "$JAY_HIDDEN"
  # zellij resizes in steps of 5 % of the tab.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    read -r cols total < <(jay_hub_panes | jq -rs --argjson id "${review#terminal_}" '
      (map(select(.id == $id)) | first) as $r | select($r != null)
      | [$r.pane_columns, ([.[] | select(.tab_id == $r.tab_id and (.is_floating | not)) | .pane_x + .pane_columns] | max)]
      | @tsv')
    [[ -n "${total:-}" ]] || break
    if ((cols * 100 / total > share + 2)); then
      zellij -s "$JAY_SESSION" action resize -p "$review" decrease left >/dev/null 2>&1
    elif ((cols * 100 / total < share - 2)); then
      zellij -s "$JAY_SESSION" action resize -p "$review" increase left >/dev/null 2>&1
    else
      break
    fi
  done
  [[ "${files:-0}" == 1 ]] && jay_hub_show_files
  # Review (or files over it) has the focus now.
  if [[ "${1:-}" != --focus ]]; then
    zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
    [[ "$list" == true ]] && zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  fi
  return 0
}

jay_hub_toggle_review() {
  if jay_hub_review_hidden >/dev/null; then jay_hub_unhide_review; else jay_hub_hide_review; fi
}

# Hide the floating panes of the hub tab again when review is hidden and is the only one left.
jay_hub_rehide() {
  local tab
  [[ -f "$JAY_HIDDEN" ]] || return 0
  tab=$(jay_hub_review_hidden) || return 0
  zellij -s "$JAY_SESSION" action list-panes -a -j -c 2>/dev/null \
    | jq -e --argjson t "$tab" '[.[] | select(.tab_id == $t and .is_floating)] | length == 1' >/dev/null || return 0
  [[ "$(zellij -s "$JAY_SESSION" action are-floating-panes-visible -t "$tab" 2>/dev/null)" == true ]] || return 0
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
}

# For a Run binding's floating pane $1 (the caller's ZELLIJ_PANE_ID): when it closes, hide the
# floating panes again (review hidden). In the background, up to an hour: the pane closes when
# its caller ends.
jay_hub_keep_hidden() {
  [[ -f "$JAY_HIDDEN" && -n "${1:-}" ]] || return 0
  (trap '' HUP; jay_hub_wait_gone "$1" 3600 && jay_hub_rehide) </dev/null >/dev/null 2>&1 &
}

# --- Claude Code updates: agents on an old binary move to the new one at a quiet moment ---
# An update (the native installer, Homebrew's cask) puts a new claude binary in place. New agents
# and new `claude attach` clients use it at once; a running background agent keeps the binary it
# started with. `claude respawn <id>` restarts it on the installed binary in about a second, with
# the same id, name, conversation, system prompt, folder and entered worktree, and a `claude
# attach` client stays. But it kills a turn that runs (the turn does not resume), the agent's
# Monitor tasks and the notify_when_idle subscriptions it holds, and it fails while the folder
# Claude wakes the agent in is gone. So the list respawns an agent only at a quiet moment
# (jay_respawn_plan); `jay respawn` does the same on demand. See docs/working.md.

# The version of the installed claude, cached in $JAY_STATE/claude-version under the binary's
# real path and mtime (an update changes them): `claude --version` is slow. Empty without claude.
jay_claude_version() {
  local bin real key k="" v="" cache="$JAY_STATE/claude-version"
  bin=$(command -v claude) || return 0
  real=$(perl -MCwd=abs_path -e 'print abs_path(shift) // ""' "$bin" 2>/dev/null)
  [[ -n "$real" ]] || real=$bin
  key="$real $(stat -f %m "$real" 2>/dev/null)"
  IFS=$'\t' read -r k v 2>/dev/null <"$cache"
  if [[ "$k" == "$key" && -n "$v" ]]; then
    printf '%s\n' "$v"
    return 0
  fi
  v=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [[ -n "$v" ]] || return 0
  jay_state_dir
  printf '%s\t%s\n' "$key" "$v" >"$cache.$$" && mv "$cache.$$" "$cache"
  printf '%s\n' "$v"
}

# The version that each running background agent in agents JSON $1 runs, as a JSON object id:
# version. Claude's daemon runs an agent (.pid) under `claude bg-pty-host ... -- <binary> ...`,
# and the binary's path has the version: .../claude/versions/<v> (native), .../Caskroom/
# claude-code/<v>/claude (Homebrew). state.json cliVersion is no help here: it is the version of
# the agent's last turn, and a restart does not change it. No entry when no path tells.
jay_running_versions() {
  local pids
  pids=$(jq -r '[.[] | select(.kind == "background" and .id != null and .pid != null)
    | "\(.pid)=\(.id)"] | join(" ")' <<<"$1")
  [[ -n "$pids" ]] || { echo '{}'; return 0; }
  ps -axo pid=,ppid=,command= 2>/dev/null | awk -v want="$pids" '
    # The binary of a command line: the word after "--", else the first word.
    function bin(c,   n, a, i) { n = split(c, a, " "); for (i = 1; i < n; i++) if (a[i] == "--") return a[i + 1]; return a[1] }
    # The last x.y.z in the path of a claude binary (not, say, the path of node).
    function ver(b,   m) { m = ""; if (b !~ /claude/) return ""
      while (match(b, /[0-9]+\.[0-9]+\.[0-9]+/)) { m = substr(b, RSTART, RLENGTH); b = substr(b, RSTART + RLENGTH) }
      return m }
    BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) { split(w[i], kv, "="); id[kv[1]] = kv[2] } }
    { p = $1; pp[p] = $2; $1 = ""; $2 = ""; sub(/^ +/, ""); cmd[p] = $0 }
    END { for (p in id) if (p in cmd) {
      v = ver(bin(cmd[p]))
      if (v == "" && (pp[p] in cmd)) v = ver(bin(cmd[pp[p]]))
      if (v != "") print id[p] "\t" v } }' \
    | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}'
}

# The respawns the hub made, as a JSON object id: {to, t}: the version it respawned the agent
# onto and when (seconds). One file each, $JAY_STATE/respawned/<id>.
jay_respawned() {
  local f
  for f in "$JAY_STATE"/respawned/*; do
    [[ -f "$f" ]] || continue
    printf '%s\t%s\t%s\n' "${f##*/}" "$(head -1 "$f")" "$(stat -f %m "$f")"
  done | jq -Rsc 'split("\n") | map(select(. != "") | split("\t") | {(.[0]): {to: .[1], t: (.[2] | tonumber)}})
    | add // {}'
}

# The running background agents in agents JSON $1 (jobs JSON $2, from jay_jobs) on another Claude
# Code version than the installed one, as a JSON object id: the version they run. The version is
# the process's (jay_running_versions); when that tells none, cliVersion, unless the hub
# respawned the agent onto the installed version since (cliVersion changes only at its next turn).
# An agent that does not run is not in it: it wakes on the installed binary.
jay_stale() {
  local want
  want=$(jay_claude_version)
  [[ -n "$want" ]] || { echo '{}'; return 0; }
  jq -c --arg want "$want" --argjson jobs "$2" --argjson run "$(jay_running_versions "$1")" \
    --argjson done "$(jay_respawned)" '
    [.[] | select(.kind == "background" and .id != null and .pid != null)
      | ($run[.id] // (if $done[.id].to == $want then $want else $jobs[.id].ver // "" end)) as $v
      | select($v != "" and $v != $want) | {(.id): $v}] | add // {}' <<<"$1"
}

# The ids and names that `claude attach` processes name, as a JSON array: a client is attached to
# those agents (a terminal tab, the hub's middle column, jay-clear).
jay_attached() {
  ps -axo command= 2>/dev/null | awk '$1 ~ /(^|\/)claude$/ && $2 == "attach" && $3 != "" { print $3 }' \
    | jq -Rsc 'split("\n") | map(select(. != ""))'
}

# The respawn rule. One line for each background agent in agents JSON $1 (with phases, see
# jay_agent_phases) that stale JSON $3 (from jay_stale) names: id<TAB>name<TAB>version it
# runs<TAB>why not. An empty "why not": it may respawn now. $2: jobs JSON (jay_jobs); $4: the id
# shown in the hub's middle column; $5 = force: only the reasons that `jay respawn --force` keeps.
# Always: it runs, it is no replaced entry (jay_continue_in), the folder Claude wakes it in is on
# disk (else `claude respawn` fails), and no turn runs, also none that waits for a permission or
# an answer (status waiting; a respawn ends the turn for good). Not forced: it is idle or unread
# (not input: it asked you something at the end of its turn), its process too (status
# idle), it has no background tasks, crons or wakeups (state.json inFlight; a respawn kills its
# Monitors), it is not in the middle column and no `claude attach` shows it (a draft in its input
# box would go), and the hub did not respawn it in the last 10 minutes. A respawn also drops the
# notify_when_idle subscriptions the agent holds: an orchestrator waits until no other agent of
# its repo works or waits, the hub Claude until no other agent does.
jay_respawn_plan() {
  local IFS=$' \t\n' dirs gone
  dirs=$(jq -r --argjson jobs "$2" --argjson stale "$3" \
    '.[] | select(.id != null and $stale[.id] != null) | $jobs[.id].cwd // .cwd // empty' <<<"$1")
  gone=$(while IFS= read -r d; do [[ -z "$d" || -d "$d" ]] || printf '%s\n' "$d"; done <<<"$dirs" \
    | jq -Rsc 'split("\n") | map(select(. != ""))')
  jq -r --argjson jobs "$2" --argjson stale "$3" --arg shown "${4:-}" --arg force "${5:-}" \
    --arg hub "$(jay_hub_claude_id)" --argjson attached "$(jay_attached)" --argjson done "$(jay_respawned)" \
    --argjson replaced "$(jay_replaced_ids)" --argjson gone "$gone" --argjson now "$(date +%s)" '
    . as $agents
    | def busy: .phase == "working" or .phase == "input";
      def inrepo($h): (.cwd // "") as $c | $c == $h or ($c | startswith($h + "/")) or ($c | startswith($h + "."));
    .[] | select(.kind == "background" and .id != null and $stale[.id] != null)
    | . as $a | ($jobs[.id] // {}) as $j | ($j.cwd // .cwd // "") as $dir
    | [ (if .pid == null then "it does not run: it wakes on the new version" else empty end),
        (if $replaced | index([$a.id]) then "a copy replaced it" else empty end),
        (if $gone | index([$dir]) then "its folder is gone: \($dir)" else empty end),
        (if $j.tempo == "active" or (($j.tempo // "") == "" and .phase == "working") then "a turn runs" else empty end),
        (if .status == "waiting" then "it waits for an answer in a turn" else empty end),
        (if $force == "force" then empty else
          (if .phase == "input" then "it asked you something" else empty end),
          (if .phase == "failed" then "it failed" else empty end),
          (if ($j.tasks // 0) > 0 then "it has background tasks, crons or wakeups" else empty end),
          (if .status != null and .status != "idle" then "it works" else empty end),
          (if $shown != "" and (.id == $shown or .sessionId == $shown) then "it is in the hub'"'"'s middle column" else empty end),
          (if $attached | index([$a.id]) or ($a.name != null and ($attached | index([$a.name]))) then "a claude attach client shows it" else empty end),
          (($done[.id].t // 0) as $t | if $now - $t < 600 then "respawned \(($now - $t) / 60 | floor) min ago" else empty end),
          (if $j.orch and any($agents[]; .id != $a.id and busy and inrepo($j.home // $dir))
           then "an orchestrator, and agents of its repo work" else empty end),
          (if .id == $hub and any($agents[]; .id != $a.id and busy) then "the hub Claude, and other agents work" else empty end)
        end) ] as $why
    | [.id, (.name // .id), $stale[.id], ($why[0] // "")] | @tsv' <<<"$1"
}

# Respawn background agent $1 (name $2, on version $3) onto the installed Claude Code, with
# `claude respawn` and without the caller's CLAUDE*/ANTHROPIC* variables. Notes it in
# $JAY_STATE/respawned/<id> (also when it fails: the next try waits 10 minutes) and in prune.log.
# Prints Claude's output, and fails when `claude respawn` fails.
jay_respawn() {
  local id=$1 name=${2:-$1} from=${3:-?} want out new rc=0 var strip=()
  want=$(jay_claude_version)
  jay_state_dir
  mkdir -p "$JAY_STATE/respawned" && printf '%s\n' "${want:-?}" >"$JAY_STATE/respawned/$id"
  for var in $(compgen -e | grep -E '^(CLAUDE|ANTHROPIC)'); do strip+=(-u "$var"); done
  out=$(env ${strip[@]+"${strip[@]}"} claude respawn "$id" 2>&1) || rc=$?
  printf '%s %s (%s): respawn %s → %s: %s\n' "$(date '+%F %T')" "$id" "$name" "$from" "${want:-?}" \
    "$(tr '\n' ' ' <<<"$out" | sed 's/ *$//')" >>"$JAY_STATE/prune.log"
  # Claude can give the agent a new short id ("respawned <id> → <new id>").
  new=$(grep -oE '→ [0-9a-f]{8}' <<<"$out" | grep -oE '[0-9a-f]{8}' | tail -1)
  if ((rc == 0)) && [[ -n "$new" && "$new" != "$id" ]]; then
    [[ "$(jay_hub_claude_id)" == "$id" ]] && printf '%s\n' "$new" >"$JAY_HUB_CLAUDE_FILE"
    printf '%s\n' "${want:-?}" >"$JAY_STATE/respawned/$new"
  fi
  printf '%s\n' "$out"
  return $rc
}

# With JAY_AUTO_RESPAWN=idle, at most once a minute: respawn each agent that the rule lets
# (jay_respawn_plan). The list's loop calls it with its agents JSON $1 (with phases), jobs JSON
# $2, the id shown in the middle column $3 and stale JSON $4 (jay_stale).
jay_respawn_auto() {
  local stamp="$JAY_STATE/respawn.stamp" id name from why
  [[ "$JAY_AUTO_RESPAWN" == idle && -n "${4:-}" && "$4" != '{}' ]] || return 0
  (($(date +%s) - $(stat -f %m "$stamp" 2>/dev/null || echo 0) < 60)) && return 0
  jay_state_dir
  touch "$stamp"
  while IFS=$'\t' read -r id name from why; do
    [[ -n "$id" && -z "$why" ]] && jay_respawn "$id" "$name" "$from" >/dev/null
  done < <(jay_respawn_plan "$1" "$2" "$4" "$3")
  find "$JAY_STATE/respawned" -type f -mtime +14 -delete 2>/dev/null
  return 0
}
