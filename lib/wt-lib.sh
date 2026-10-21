# Shared helpers for the wt-hub scripts (bin/). Sourced, not executed.

# Settings: an environment variable wins, else ~/.config/wt-hub/config (KEY=value lines, #
# comments), else the default. The file reaches what a shell profile does not: hooks in
# background agents, and a notice click. ~ at the start of a WT_ROOTS folder is $HOME.
WT_HUB_CONFIG="$HOME/.config/wt-hub/config"
if [[ -f "$WT_HUB_CONFIG" ]]; then
  _re='^[[:space:]]*(WT_ROOTS|WT_TERMINAL|WT_EDITOR|WT_EDITOR_GUI|WT_TASK_SHELL|WT_LAUNCHER)[[:space:]]*=[[:space:]]*(.*)$'
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ "$_line" =~ $_re ]] || continue
    _key=${BASH_REMATCH[1]} _val=${BASH_REMATCH[2]}
    _val=${_val%"${_val##*[![:space:]]}"}
    _val=${_val#\"}; _val=${_val%\"}
    [[ -n "${!_key:-}" ]] || export "$_key=$_val"
  done <"$WT_HUB_CONFIG"
  unset _re _line _key _val
fi
WT_ROOTS=${WT_ROOTS:-$HOME/Documents/projects}
_roots=""
IFS=: read -ra _dirs <<<"$WT_ROOTS"
for _dir in ${_dirs[@]+"${_dirs[@]}"}; do
  _roots+="${_roots:+:}${_dir/#\~/$HOME}"
done
WT_ROOTS=$_roots
unset _roots _dirs _dir

# A click on a notice runs `wt-go` through /bin/sh with launchd's PATH (/usr/bin:/bin:...),
# which has no claude or zellij. Add their folders at the end, so a caller's own order wins.
for _dir in "$HOME/.local/bin" /opt/homebrew/bin; do
  case ":$PATH:" in *":$_dir:"*) ;; *) PATH="$PATH:$_dir" ;; esac
done
unset _dir
export PATH

# Every zellij call from these scripts gives up after $WT_ZELLIJ_TIMEOUT seconds: a session
# whose server outlives it (seen after a quit) stalls even list-sessions, and with it every
# pick, hook and sidebar tick. Interactive zellij runs through `exec` or a new Ghostty tab,
# never through this function.
zellij() {
  perl -e 'alarm shift; exec @ARGV or exit 127' "${WT_ZELLIJ_TIMEOUT:-5}" zellij "$@"
}

wtl_toplevel() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$1"
}

wtl_primary() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk 'NR==1 { sub(/^worktree /, ""); print; exit }'
}

wtl_client() {
  local parent root
  parent=$(dirname "$1")
  IFS=: read -ra roots <<<"$WT_ROOTS"
  for root in "${roots[@]}"; do
    [[ "$parent" == "$root" ]] && { basename "$1"; return; }
  done
  basename "$parent"
}

# Prints: client<TAB>repo<TAB>branch<TAB>worktree-root
wtl_describe() {
  local top primary branch
  top=$(wtl_toplevel "$1")
  primary=$(wtl_primary "$top")
  [[ -n "$primary" ]] || primary=$top
  branch=$(git -C "$top" branch --show-current 2>/dev/null)
  [[ -n "$branch" ]] || branch=$(basename "$top")
  printf '%s\t%s\t%s\t%s\n' "$(wtl_client "$primary")" "$(basename "$primary")" "$branch" "$top"
}

wtl_tab_name() {
  local repo=$1 branch=${2##*/}
  printf '%s/%s\n' "$repo" "${branch:0:32}"
}

wtl_in_zellij() {
  [[ -n "${ZELLIJ_SESSION_NAME:-}" && -z "${CLAUDE_JOB_DIR:-}" ]]
}

wtl_live_sessions() {
  zellij list-sessions --no-formatting 2>/dev/null | grep -v 'EXITED' | awk '{ print $1 }'
}

wtl_session_has_client() {
  [[ $(zellij -s "$1" action list-clients 2>/dev/null | wc -l) -gt 1 ]]
}

# The zellij session to act on: the caller's own, else the one with a client attached.
wtl_session() {
  if wtl_in_zellij; then
    printf '%s\n' "$ZELLIJ_SESSION_NAME"
    return
  fi
  [[ -n "${WT_ZELLIJ_SESSION:-}" ]] && { printf '%s\n' "$WT_ZELLIJ_SESSION"; return; }
  local s first=""
  while IFS= read -r s; do
    [[ -z "$first" ]] && first=$s
    wtl_session_has_client "$s" && { printf '%s\n' "$s"; return; }
  done < <(wtl_live_sessions)
  [[ -n "$first" ]] && printf '%s\n' "$first"
}

# Panes of a session whose cwd sits in worktree $2, as JSON lines. Optional $3: jq regex on pane_command.
wtl_panes_in() {
  local session=$1 path=$2 cmd=${3:-}
  zellij -s "$session" action list-panes -j -c 2>/dev/null | jq -c --arg p "$path" --arg cmd "$cmd" '
    .[] | select(.is_plugin | not)
        | select(.pane_cwd == $p or (.pane_cwd | startswith($p + "/") and (contains("/.claude/worktrees/") | not)))
        | select($cmd == "" or ((.pane_command // .terminal_command // "") | test($cmd)))'
}

wtl_focus_pane() {
  local session=$1 pane=$2 tab=$3
  [[ -n "$tab" ]] && zellij -s "$session" action go-to-tab-name "$tab" >/dev/null 2>&1
  zellij -s "$session" action focus-pane-id "terminal_$pane" >/dev/null 2>&1
}

wtl_raise_terminal() {
  wtl_gh_ok || return 1
  open -b com.mitchellh.ghostty 2>/dev/null
}

wtl_frontmost_bundle() {
  lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*"*bundleID"*="\([^"]*\)".*/\1/p'
}

wtl_has_transcripts() {
  local slug=${1//[\/.]/-}
  compgen -G "$HOME/.claude/projects/$slug/*.jsonl" >/dev/null
}

# --- Ghostty tabs (AppleScript, Ghostty 1.3+) ---

# Tab control works in Ghostty only; other terminals can be added later. WT_TERMINAL=ghostty
# turns it on, any other value off. Else it is on when Ghostty runs and the caller's terminal,
# if it has one, is Ghostty (zellij panes get the TERM_PROGRAM of the terminal that started
# the session; hooks and a notice click may have none). Without it the wtl_gh_* functions
# fail and do nothing.
wtl_gh_ok() {
  case ${WT_TERMINAL:-} in
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
wtl_gh_tabs() {
  wtl_gh_ok || return 1
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
wtl_gh_tab_session() {
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
wtl_gh_tab_for_session() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    [[ "$(wtl_gh_tab_session "$tty" "$title")" == "$1" ]] && { printf '%s\n' "$id"; return 0; }
  done < <(wtl_gh_tabs)
  return 1
}

# Ghostty tab id whose own tty runs a process matching regex $1 (e.g. "^claude attach 1234").
wtl_gh_tab_for_command() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    ps -t "${tty#/dev/}" -o command= 2>/dev/null | grep -qE "$1" && { printf '%s\n' "$id"; return 0; }
  done < <(wtl_gh_tabs)
  return 1
}

# Ghostty tab id whose tty is $1.
wtl_gh_tab_for_tty() {
  local id sel front tty title
  while IFS=$'\t' read -r id sel front tty title; do
    [[ "$tty" == "/dev/${1#/dev/}" ]] && { printf '%s\n' "$id"; return 0; }
  done < <(wtl_gh_tabs)
  return 1
}

wtl_gh_select() {
  wtl_gh_ok || return 1
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
wtl_gh_new_tab() {
  wtl_gh_ok || return 1
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
wtl_session_name() {
  local repo=$1 branch=${2##*/} name
  name="$repo.${branch}"
  name=${name//[^A-Za-z0-9._-]/-}
  printf '%s\n' "${name:0:30}"
}

wtl_session_for_worktree() {
  local path=$1 name=$2 s
  if zellij list-sessions --short --no-formatting 2>/dev/null | grep -qxF "$name"; then
    printf '%s\n' "$name"; return 0
  fi
  while IFS= read -r s; do
    [[ -n "$(wtl_panes_in "$s" "$path" | head -1)" ]] && { printf '%s\n' "$s"; return 0; }
  done < <(wtl_live_sessions)
  return 1
}

# The short id in the output $1 of `claude --bg` ("backgrounded · <short id> · <name> ...").
wtl_bg_id() {
  grep -oE 'backgrounded · [0-9a-f]{8}' <<<"$1" | grep -oE '[0-9a-f]{8}$' | tail -1
}

# --- Folder trust: `claude --bg` does not start in a repo that was never trusted ---
# Claude keeps the trust in ~/.claude.json (projects.<path>.hasTrustDialogAccepted), under the
# path of the repo's main checkout: all its worktrees share it. A trusted parent folder of the
# repo does not count. Plain `claude` asks with its trust prompt; `claude --bg` only fails.

# The path Claude keeps the trust of folder $1 under: the main checkout of its repo.
wtl_trust_key() {
  local top primary
  top=$(wtl_toplevel "$1")
  primary=$(wtl_primary "$top")
  (cd "${primary:-$top}" 2>/dev/null && pwd -P)
}

# Folder $1 is trusted. When ~/.claude.json cannot be read, it is: `claude --bg` then decides.
wtl_trusted() {
  local key cfg="$HOME/.claude.json"
  key=$(wtl_trust_key "$1")
  [[ -n "$key" && -r "$cfg" ]] || return 0
  jq -e --arg k "$key" '.projects[$k].hasTrustDialogAccepted == true' "$cfg" >/dev/null 2>&1 \
    || [[ $? -gt 1 ]]
}

# Trust folder $1 as the trust prompt of `claude` does. Under Claude's own config lock (the
# folder ~/.claude.json.lock; Claude takes a lock over 10 s old as stale), and written through
# a copy, so running sessions never read half a file.
wtl_trust() {
  local key cfg="$HOME/.claude.json" lock tmp i got=false rc=0
  key=$(wtl_trust_key "$1")
  [[ -n "$key" && -f "$cfg" ]] || return 1
  lock="$cfg.lock"
  for i in $(seq 50); do
    mkdir "$lock" 2>/dev/null && { got=true; break; }
    sleep 0.1
  done
  [[ "$got" == true ]] || return 1
  tmp=$(mktemp "$cfg.wt-hub.XXXXXX") \
    && jq --arg k "$key" '.projects[$k] = ((.projects[$k] // {}) + {hasTrustDialogAccepted: true})' \
      "$cfg" >"$tmp" \
    && [[ -s "$tmp" ]] && mv "$tmp" "$cfg" || rc=1
  rm -f "$tmp"
  rmdir "$lock" 2>/dev/null
  return $rc
}

# --- Hub panes (zellij session "hub"): agent viewer, review ⇄ files ---
# One pane in each column. The agent viewer (middle) and review (right) are layout panes; files
# opens in place over review: zellij keeps review suspended and shows it again when files
# closes. The panes run `wt-hub-pane <role>`, which follows the target in
# wt-hub-<role>.target; a pick writes the target and stops the running program, so the pane
# stays where it is and only its program and title change.

WT_HUB_SESSION=${WT_HUB_SESSION:-hub}

wtl_in_hub() {
  [[ "${ZELLIJ_SESSION_NAME:-}" == "$WT_HUB_SESSION" && -z "${CLAUDE_JOB_DIR:-}" ]]
}

# The hub runs with a terminal attached, wherever the caller is (an agent viewed in the hub
# runs outside it).
wtl_hub_live() {
  wtl_session_has_client "$WT_HUB_SESSION"
}

wtl_hub_panes() {
  zellij -s "$WT_HUB_SESSION" action list-panes -a -j -c 2>/dev/null | jq -c '.[] | select(.is_plugin | not)'
}

wtl_hub_target_file() { printf '%s/.local/state/wt-hub-%s.target\n' "$HOME" "$1"; }
wtl_hub_pane_file() { printf '%s/.local/state/wt-hub-%s.pane\n' "$HOME" "$1"; }

# Forget all hub pane targets (a fresh hub).
wtl_hub_reset() {
  local role
  for role in agent review files; do rm -f "$(wtl_hub_target_file $role)" "$(wtl_hub_pane_file $role)"; done
}

# wt-hub-pane $1 (pid $2) ends.
wtl_hub_pane_gone() {
  local file pid
  file=$(wtl_hub_pane_file "$1")
  IFS=$'\t' read -r _ pid 2>/dev/null <"$file"
  [[ "${pid:-}" == "$2" ]] && rm -f "$file"
  return 0
}

# "terminal_<id><TAB>pid" of the running wt-hub-pane for role $1; fails when there is none.
# A recorded pane that zellij no longer lists is lost (an in-place pane opened over a suspended
# one): its wt-hub-pane still runs and takes every pick, but nobody sees it. It is stopped and
# forgotten. A pane of the role without a record is taken on when it is the only one and one
# wt-hub-pane of the role runs in the hub. When zellij does not answer, the record is trusted.
wtl_hub_role() {
  local file pane="" pid="" lost="" panes pids
  file=$(wtl_hub_pane_file "$1")
  IFS=$'\t' read -r pane pid 2>/dev/null <"$file"
  if [[ -n "$pane" && -n "$pid" ]] && ps -o command= -p "$pid" 2>/dev/null | grep -q "wt-hub-pane $1"; then
    panes=$(wtl_hub_panes)
    if [[ -z "$panes" ]] || jq -e --argjson id "$pane" 'select(.id == $id and (.exited | not))' <<<"$panes" >/dev/null; then
      printf 'terminal_%s\t%s\n' "$pane" "$pid"
      return 0
    fi
    lost=$pid
    wtl_kill_children "$pid"
    kill -TERM "$pid" 2>/dev/null
    wtl_hub_pane_gone "$1" "$pid"
  else
    panes=$(wtl_hub_panes)
  fi
  pane=$(jq -r --arg role "$1" \
    'select((.exited | not) and ((.terminal_command // "") | test("wt-hub-pane " + $role + "$"))) | .id' <<<"$panes")
  [[ -n "$pane" && "$pane" != *$'\n'* ]] || return 1
  pids=$(pgrep -P "$(pgrep -f "zellij --server .*/$WT_HUB_SESSION\$" | head -1)" -f "wt-hub-pane $1\$" | grep -vxF "${lost:-none}")
  [[ -n "$pids" && "$pids" != *$'\n'* ]] || return 1
  printf '%s\t%s\n' "$pane" "$pids" >"$file.$$" && mv "$file.$$" "$file"
  printf 'terminal_%s\t%s\n' "$pane" "$pids"
}

# Wait up to 2 s until pane $1 (a terminal id) is shown, not suspended under another pane.
wtl_hub_wait_shown() {
  local i
  for i in $(seq 20); do
    wtl_hub_panes | jq -e --argjson id "$1" 'select(.id == $id and (.is_suppressed | not))' >/dev/null && return 0
    sleep 0.1
  done
  return 1
}

wtl_hub_write_target() {
  local file
  file=$(wtl_hub_target_file "$1")
  printf '%s\n' "$2" >"$file.$$" && mv "$file.$$" "$file"
}

# Wait up to 2 s for the new wt-hub-pane of role $1 to start.
wtl_hub_role_ready() {
  local i
  for i in $(seq 40); do wtl_hub_role "$1" >/dev/null && return 0; sleep 0.05; done
  return 1
}

# Callers run it inside `IFS=$'\t' read … < <(…)`, whose IFS bash 3.2 passes on: split the pids
# with the usual IFS.
wtl_kill_children() {
  local child IFS=$' \t\n'
  for child in $(pgrep -P "$1"); do
    wtl_kill_children "$child"
    kill -TERM "$child" 2>/dev/null
  done
  return 0
}

# Point the running hub pane of role $1 at target line $2. Prints "terminal_<id><TAB>changed",
# changed being 1 when the pane restarts its program for the new target, else 0.
# Fails when no pane of that role runs.
wtl_hub_point() {
  local pane pid
  IFS=$'\t' read -r pane pid < <(wtl_hub_role "$1") || return 1
  if [[ "$(cat "$(wtl_hub_target_file "$1")" 2>/dev/null)" == "$2" ]]; then
    printf '%s\t0\n' "$pane"
    return 0
  fi
  wtl_hub_write_target "$1" "$2"
  wtl_kill_children "$pid"
  printf '%s\t1\n' "$pane"
}

# In zellij 0.45 `focus-pane-id` from the CLI sets a focus of its own, not the terminal's, and on
# a suspended pane it makes that pane float. `move-focus` moves the terminal's focus.

# Move the focus to the middle column (the agent viewer), from any column: left twice reaches
# the list, then one step right. From the tasks tab, go to the hub's tab first.
wtl_hub_focus_middle() {
  zellij -s "$WT_HUB_SESSION" action go-to-tab-name hub >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action move-focus right >/dev/null 2>&1
  return 0
}

# Run "$@" holding the hub lock, so two picks (sidebar, /wt go, a notice click) never move
# the hub's panes at the same time. A lock older than 5 s is taken over.
wtl_hub_locked() {
  local lock="$HOME/.local/state/wt-hub.lock" i rc=0
  for i in $(seq 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  [[ -d "$lock" ]] || mkdir "$lock"
  "$@" || rc=$?
  rmdir "$lock" 2>/dev/null
  return $rc
}

# Show background agent $1 (short id) named $2 from folder $3 in the hub's middle column: the
# viewer pane follows the new agent. The focus goes there. With $4 = interactive, $1 is a
# session id and the viewer only says where that agent runs.
wtl_hub_show() {
  local id=$1 name=$2 cwd=$3 line viewer changed
  line=$(printf '%s\t%s' "$id" "$cwd")
  [[ "${4:-}" == interactive ]] && line=$(printf '%s\tinteractive\t%s' "$line" "$name")
  IFS=$'\t' read -r viewer changed < <(wtl_hub_point agent "$line") || return 1
  [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$viewer" "$name" >/dev/null 2>&1
  wtl_hub_focus_middle
}

# --- The hub Claude: a background agent named "hub" in the first root folder, to start and
# steer agents and to answer questions across repos. The "◆ hub" row of the list shows it in
# the middle column, and a fresh hub opens on it. Its short id is in WT_HUB_CLAUDE_FILE.

WT_HUB_CLAUDE_FILE=${WT_HUB_CLAUDE_FILE:-$HOME/.local/state/wt-hub-claude}

# Added to the hub Claude's system prompt.
wtl_hub_claude_prompt() {
  cat <<EOF
You are the hub Claude of a worktree hub: a zellij session "hub" with a list of worktrees and
Claude agents on the left, one agent in the middle column (you now) and a review of that agent's
turns on the right. The user comes to you to start and steer agents, and with questions across
repos. Each agent is a background Claude session in its own git worktree. Repos live under
$WT_ROOTS (a folder per client, then the repo; worktrees are siblings named <repo>.<branch>).

- Agents: \`claude agents --json --all\` (id, name, cwd, state, status); recent output:
  \`claude logs <id>\`; what an agent did per turn: \`git log refs/wt-turns/<id>/base..refs/wt-turns/<id>/head\`
  in its worktree.
- Worktrees with git state and task notes: \`wt-all --json\`; in a repo also \`wt list\`.
- New worktree with an agent: in the repo's main checkout, \`wt new <branch> -t "<task>" -- <prompt>\`
  (-a: an idle agent). New agent in a worktree that exists: \`cd <worktree> && claude --bg
  --name "<repo>/<branch>" "<prompt>"\`. Start agents only when the user asks or agrees.
  "Workspace not trusted": Claude never ran in that repo. Do not change ~/.claude.json; tell the
  user to press n on one of its worktrees in the list, or N on its repo row (both ask to trust
  the repo), or to run \`c\` in it.
- Send a prompt to a running agent: the ListAgents and SendMessage tools.
- Show an agent in the middle column: \`wt go <id or name>\`; \`wt go hub\` comes back to you.
- Dev servers and other long-running commands: the hub's "tasks" tab (\`hub-run ls --json\`,
  \`hub-run log <task>\`, \`hub-run -n <name> -w -- <command>\`), not a background Bash call.
- Read other worktrees in place. Do not edit files in an agent's worktree, and never remove
  worktrees or agents (\`wt remove\`, \`claude rm\`, \`wt step prune\`) unless the user asks.
  Never \`claude --resume\` a conversation that a live agent holds.
EOF
}

# The short id of the hub Claude. When there is none (never started, or `claude rm` removed it),
# start it, and wait until `claude agents` lists it. A stopped one stays: `claude attach` opens
# it again. A lock keeps two callers (the pane at hub start, a list pick) from starting two.
wtl_hub_claude() {
  local lock="$HOME/.local/state/wt-hub-claude.lock" id out var i rc=0
  local strip=() dirs=() args=()
  for i in $(seq 150); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  [[ -d "$lock" ]] || mkdir "$lock"
  id=$(cat "$WT_HUB_CLAUDE_FILE" 2>/dev/null)
  if [[ -z "$id" ]] || ! claude agents --json --all 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
    # An inherited CLAUDE_CODE_CHILD_SESSION (a caller in an agent) hides a session from
    # `claude agents`: start it without CLAUDE*/ANTHROPIC* variables.
    for var in $(compgen -e | grep -E '^(CLAUDE|ANTHROPIC)'); do strip+=(-u "$var"); done
    # It starts in the first root; the other roots are added folders.
    IFS=: read -ra dirs <<<"$WT_ROOTS"
    for ((i = 1; i < ${#dirs[@]}; i++)); do args+=(--add-dir "${dirs[i]}"); done
    out=$(cd "${dirs[0]:-$HOME}" && env ${strip[@]+"${strip[@]}"} claude --bg --name hub \
      ${args[@]+"${args[@]}"} --append-system-prompt "$(wtl_hub_claude_prompt)" 2>&1)
    id=$(wtl_bg_id "$out")
    if [[ -n "$id" ]]; then
      printf '%s\n' "$id" >"$WT_HUB_CLAUDE_FILE"
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
wtl_hub_claude_id() {
  cat "$WT_HUB_CLAUDE_FILE" 2>/dev/null
}

# Move the cursor of each running list (wt-sidebar's fzf, through its --listen socket) to the
# row of the agent with session id $1, so the cursor follows a pick made elsewhere (a notice
# click, `wt go`, a new agent). A new agent's row may not be there yet: then reload and wait up
# to 3 s for it. `pos` must come after a reload ends: the list's --track puts the cursor back
# on the old row when a reload ends.
wtl_list_follow() {
  local sid=$1 sock pid pos i
  for sock in "$HOME"/.local/state/wt-sidebar.*.sock; do
    [[ -S "$sock" ]] || continue
    pid=${sock##*/wt-sidebar.}; pid=${pid%.sock}
    kill -0 "$pid" 2>/dev/null || continue
    for i in $(seq 12); do
      pos=$(curl -s --max-time 2 --unix-socket "$sock" 'http://localhost?limit=1000' 2>/dev/null \
        | jq -r --arg s "$sid" '[.matches[] | .text | split("\t")[1]] | index($s) // empty | . + 1')
      [[ -n "$pos" ]] && break
      ((i == 1)) && curl -s --max-time 2 --unix-socket "$sock" -X POST http://localhost \
        -d 'reload-sync(wt-sidebar --rows)' >/dev/null 2>&1
      sleep 0.25
    done
    [[ -n "$pos" ]] && curl -s --max-time 2 --unix-socket "$sock" -X POST http://localhost -d "pos($pos)" >/dev/null 2>&1
  done
  return 0
}

# --- Hub review (tuicr) and files (yazi) panes, following the picked worktree ---

# The repo of the worktree $1, for the review and files titles (no branch: the list shows it).
wtl_hub_title() {
  local client repo branch top
  IFS=$'\t' read -r client repo branch top < <(wtl_describe "$1")
  printf '%s\n' "$repo"
}

# Review mode: turns (the agent's turn chain) or commits (the branch's commits).
WT_HUB_MODE="$HOME/.local/state/wt-hub-review.mode"
wtl_hub_mode() {
  if [[ "$(cat "$WT_HUB_MODE" 2>/dev/null)" == commits ]]; then printf 'commits\n'; else printf 'turns\n'; fi
}
wtl_hub_toggle_mode() {
  local next=turns
  [[ "$(wtl_hub_mode)" == turns ]] && next=commits
  printf '%s\n' "$next" >"$WT_HUB_MODE"
}

# Point review (and files, when shown) at the worktree that holds $1.
# $2: the agent's id, to review that agent's turns; empty for a worktree pick.
wtl_hub_target() {
  local top title pane changed
  top=$(wtl_toplevel "$1")
  title=$(wtl_hub_title "$top")
  if IFS=$'\t' read -r pane changed < <(wtl_hub_point review "$(printf '%s\t%s' "$top" "${2:-}")"); then
    [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "$(wtl_hub_pane_title review "$title")" >/dev/null 2>&1
  fi
  if IFS=$'\t' read -r pane changed < <(wtl_hub_point files "$top"); then
    [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "$(wtl_hub_pane_title files "$title")" >/dev/null 2>&1
  fi
  # The hub tab's banner shows the picked worktree (Ctrl g Tab goes to its tasks tab).
  ("$HOME/.local/bin/hub-run" --where "$top" >/dev/null 2>&1 &)
  return 0
}

# Title of the pane of role $1 (review or files) on worktree title $2 (the repo): review's
# starts with its mode. Both end with the pane's keys, the only place they can show (tuicr and
# yazi fill the pane).
wtl_hub_pane_title() {
  case $1 in
    review) if [[ "$(wtl_hub_mode)" == commits ]]; then
        printf 'commits · %s   e files · t turns\n' "$2"
      else
        printf 'turns · %s   e files · t commits\n' "$2"
      fi ;;
    files) printf 'files · %s   e review · o open here · O editor tab · W open with\n' "$2" ;;
  esac
}

# Title the pane of role $1 (review or files) after the worktree in its target. zellij does not
# rename a suspended pane, so review gets its title again when files closes.
wtl_hub_retitle() {
  local pane top
  IFS=$'\t' read -r pane _ < <(wtl_hub_role "$1") || return 0
  top=$(cut -f1 "$(wtl_hub_target_file "$1")" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "$(wtl_hub_pane_title "$1" "$(wtl_hub_title "$top")")" >/dev/null 2>&1
}

# Show files (yazi) in place over review, in the review's worktree.
wtl_hub_show_files() {
  local review top pane
  wtl_hub_role files >/dev/null && return 0
  IFS=$'\t' read -r review _ < <(wtl_hub_role review) || return 0
  top=$(cut -f1 "$(wtl_hub_target_file review)" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  wtl_hub_wait_shown "${review#terminal_}" || return 0
  wtl_hub_write_target files "$top"
  pane=$(zellij -s "$WT_HUB_SESSION" action new-pane --in-place --pane-id "$review" --close-on-exit \
    --name "$(wtl_hub_pane_title files "$(wtl_hub_title "$top")")" --cwd "$top" -- "$HOME/.local/bin/wt-hub-pane" files)
  [[ "$pane" == terminal_* ]] && wtl_hub_role_ready files
  return 0
}

# Show review: close files over it.
wtl_hub_show_review() {
  local pane
  IFS=$'\t' read -r pane _ < <(wtl_hub_role files) || return 0
  zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "$pane" >/dev/null 2>&1
  wtl_hub_retitle review
}
