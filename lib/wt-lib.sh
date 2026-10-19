# Shared helpers for wt-tab, wt-new, wt-all, wt-agents and claude-notify.
# Sourced, not executed.

WT_ROOTS=${WT_ROOTS:-$HOME/Documents/projects}

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

# Prints one line per tab: tab-id<TAB>selected<TAB>frontmost-window<TAB>tty<TAB>title
wtl_gh_tabs() {
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

# --- Hub stack: agents attached in the hub's right column (zellij session "hub") ---

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

wtl_hub_claude_pane() {
  wtl_hub_panes | jq -r 'select((.exited | not) and ((.title // "") == "hub" or ((.pane_command // "") | test("claude -n hub")))) | .id' | head -1
}

# Pane id that attaches to background agent $1 (short id), still running.
wtl_hub_agent_pane() {
  wtl_hub_panes | jq -r --arg id "$1" 'select((.exited | not) and ((.pane_command // "") | test("claude attach " + $id))) | .id' | head -1
}

wtl_hub_focus_claude() {
  local pane
  pane=$(wtl_hub_claude_pane)
  [[ -n "$pane" ]] && zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$pane" >/dev/null 2>&1
  return 0
}

# Agent viewer panes as "id<TAB>exited": every other pane in the hub Claude's column, live or
# held, and any `claude attach` pane. pane_command is not reliable (it can be null), so the
# column is the main test.
wtl_hub_viewers() {
  wtl_hub_panes | jq -rs '
    (map(select((.title // "") == "hub" and (.exited | not))) | first) as $hub
    | .[] | select((.is_floating | not) and .id != $hub.id)
    | select(((.pane_command // "") | test("^claude attach "))
        or ($hub != null and .tab_id == $hub.tab_id and .pane_x == $hub.pane_x))
    | "\(.id)\t\(.exited)"'
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

# Show background agent $1 (short id) named $2 from folder $3 in the hub's agent slot:
# one viewer pane stacked with the hub Claude, replaced in place on each pick.
# Held (exited) viewers and extra viewers are closed, so the column keeps one viewer.
wtl_hub_show() {
  local id=$1 name=$2 cwd=$3 agent keep hub new viewer exited
  agent=$(wtl_hub_agent_pane "$id")
  keep=$agent
  while IFS=$'\t' read -r viewer exited; do
    [[ "$viewer" == "$keep" ]] && continue
    if [[ "$exited" == false && -z "$keep" ]]; then keep=$viewer; continue; fi
    zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "terminal_$viewer" >/dev/null 2>&1
  done < <(wtl_hub_viewers)
  if [[ -n "$keep" ]]; then
    zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$keep" >/dev/null 2>&1
    [[ -n "$agent" ]] && return 0
    zellij -s "$WT_HUB_SESSION" run --in-place --close-replaced-pane --name "$name" --cwd "$cwd" -- claude attach "$id" >/dev/null 2>&1
    return 0
  fi
  hub=$(wtl_hub_claude_pane)
  [[ -n "$hub" ]] || return 1
  zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$hub" >/dev/null 2>&1
  new=$(zellij -s "$WT_HUB_SESSION" run --name "$name" --cwd "$cwd" -- claude attach "$id")
  [[ "$new" == terminal_* ]] || return 1
  zellij -s "$WT_HUB_SESSION" action stack-panes -- "terminal_$hub" "$new" >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action focus-pane-id "$new" >/dev/null 2>&1
  return 0
}

wtl_hub_close() {
  local pane
  pane=$(wtl_hub_agent_pane "$1")
  [[ -n "$pane" ]] && zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "terminal_$pane"
}

# --- Hub review (lazygit) and files (Neovim) panes, following the picked worktree ---

WT_HUB_NVIM="$HOME/.local/state/wt-hub-nvim.sock"
WT_HUB_TARGET="$HOME/.local/state/wt-hub-target"

wtl_hub_role_pane() {
  wtl_hub_panes | jq -r --arg role "$1" '
    ({review: "^review", files: "^files$"}[$role]) as $title
    | select((.exited | not) and ((.title // "") | test($title))) | .id' | head -1
}

wtl_hub_restack() {
  local hub ids
  hub=$(wtl_hub_claude_pane)
  [[ -n "$hub" ]] || return 0
  ids=$(wtl_hub_panes | jq -r 'select((.exited | not) and (((.pane_command // "") | test("^claude attach |wt-hub-pane |lazygit-hub\\.yml|wt-hub-nvim\\.sock")) or ((.title // "") | test("^review · |^files$")))) | "terminal_\(.id)"' | tr '\n' ' ')
  # shellcheck disable=SC2086
  [[ -n "$ids" ]] && zellij -s "$WT_HUB_SESSION" action stack-panes -- "terminal_$hub" $ids >/dev/null 2>&1
  return 0
}

wtl_nvim_alive() {
  [[ -S "$WT_HUB_NVIM" ]] && nvim --server "$WT_HUB_NVIM" --remote-expr '1' >/dev/null 2>&1
}

wtl_nvim_send() {
  nvim --server "$WT_HUB_NVIM" --remote-send "<C-\\><C-n>$1" >/dev/null 2>&1
}

wtl_hub_focused() {
  zellij -s "$WT_HUB_SESSION" action list-clients 2>/dev/null | awk 'NR == 2 { print $2 }'
}

# Run the hub pane role $1 for worktree $2 in place of pane $3, keeping the focus where it was.
wtl_hub_replace_role() {
  local role=$1 path=$2 pane=$3 name=$4 session=${5:-} before
  before=$(wtl_hub_focused)
  zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$pane" >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" run --in-place --close-replaced-pane --name "$name" --cwd "$path" -- "$HOME/.local/bin/wt-hub-pane" "$role" "$path" $session >/dev/null 2>&1
  [[ -n "$before" && "$before" != "terminal_$pane" ]] && zellij -s "$WT_HUB_SESSION" action focus-pane-id "$before" >/dev/null 2>&1
  return 0
}

# Open the files Neovim stacked with the review pane, keeping the focus where it was.
wtl_hub_open_files() {
  local path=$1 review before new
  review=$(wtl_hub_role_pane review)
  [[ -n "$review" ]] || return 0
  before=$(wtl_hub_focused)
  zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$review" >/dev/null 2>&1
  new=$(zellij -s "$WT_HUB_SESSION" run --name files --cwd "$path" -- "$HOME/.local/bin/wt-hub-pane" files "$path")
  [[ "$new" == terminal_* ]] && zellij -s "$WT_HUB_SESSION" action stack-panes -- "terminal_$review" "$new" >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$review" >/dev/null 2>&1
  [[ -n "$before" ]] && zellij -s "$WT_HUB_SESSION" action focus-pane-id "$before" >/dev/null 2>&1
  return 0
}

# Start the files Neovim in $1 if it is not running.
wtl_hub_files_ready() {
  if ! wtl_nvim_alive || [[ -z "$(wtl_hub_role_pane files)" ]]; then
    wtl_hub_open_files "$1"
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do wtl_nvim_alive && return 0; sleep 0.3; done
  fi
  return 0
}

wtl_hub_focus_role() {
  local pane
  pane=$(wtl_hub_role_pane "$1")
  [[ -n "$pane" ]] && zellij -s "$WT_HUB_SESSION" action focus-pane-id "terminal_$pane" >/dev/null 2>&1
  return 0
}
wtl_hub_focus_files() { wtl_hub_focus_role files; }
wtl_hub_focus_review() { wtl_hub_focus_role review; }

# Point the hub's review (tuicr) and files (yazi) panes at the worktree that holds $1.
# $2: the agent's session id, to review that agent's turns; empty for a worktree pick.
wtl_hub_target() {
  local top client repo branch review files session=${2:-} key
  IFS=$'\t' read -r client repo branch top < <(wtl_describe "$1")
  wtl_hub_panes | jq -rs '
    map(select((.title // "") | test("^review|^files$")) | . + {role: (.title | sub(" .*"; ""))})
    | (map(select(.exited)) + (map(select(.exited | not)) | group_by(.role) | map(.[1:]) | add // []))
    | .[].id' | while read -r extra; do
    zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "terminal_$extra" >/dev/null 2>&1
  done
  review=$(wtl_hub_role_pane review)
  [[ -n "$review" ]] || return 0
  key="$top|$session"
  [[ "$(cat "$WT_HUB_TARGET" 2>/dev/null)" == "$key|$review" ]] && return 0
  local open before
  open=$(wtl_hub_open_role)
  before=$(wtl_hub_focused)
  wtl_hub_replace_role review "$top" "$review" "review · $repo/${branch##*/}" "$session"
  files=$(wtl_hub_role_pane files)
  if [[ -n "$files" ]]; then
    wtl_hub_replace_role files "$top" "$files" "files"
  else
    wtl_hub_open_files "$top"
  fi
  wtl_hub_focus_role "$open"
  [[ -n "$before" ]] && zellij -s "$WT_HUB_SESSION" action focus-pane-id "$before" >/dev/null 2>&1
  printf '%s|%s\n' "$key" "$(wtl_hub_role_pane review)" >"$WT_HUB_TARGET"
}

# Which of review/files is expanded in the right column now (review when unknown).
wtl_hub_open_role() {
  if zellij -s "$WT_HUB_SESSION" action dump-layout 2>/dev/null | grep -q 'name="files"[^{]*expanded=true'; then
    printf 'files\n'
  else
    printf 'review\n'
  fi
}
