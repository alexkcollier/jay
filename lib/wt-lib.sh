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

# --- Hub panes (zellij session "hub"): hub Claude ⇄ agent viewer, review ⇄ files ---
# One pane in each column. The agent viewer opens in place over the hub Claude, and files in
# place over review: zellij keeps the pane under it suspended and shows it again when the top
# pane closes. The viewer, review and files panes run `wt-hub-pane <role>`, which follows the
# target in wt-hub-<role>.target; a pick writes the target and stops the running program, so
# the pane stays where it is and only its program and title change.

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
wtl_hub_role() {
  local pane pid
  IFS=$'\t' read -r pane pid 2>/dev/null <"$(wtl_hub_pane_file "$1")" || return 1
  [[ -n "$pane" && -n "$pid" ]] || return 1
  ps -o command= -p "$pid" 2>/dev/null | grep -q "wt-hub-pane $1" || return 1
  printf 'terminal_%s\t%s\n' "$pane" "$pid"
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

wtl_kill_children() {
  local child
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

# Move the focus to the middle column (the hub Claude or the agent viewer), from any column:
# left twice reaches the list, then one step right.
wtl_hub_focus_middle() {
  zellij -s "$WT_HUB_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$WT_HUB_SESSION" action move-focus right >/dev/null 2>&1
  return 0
}

# Show the hub Claude: close the agent viewer over it (the agent keeps running), focus it.
wtl_hub_show_claude() {
  local pane
  if IFS=$'\t' read -r pane _ < <(wtl_hub_role agent); then
    zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "$pane" >/dev/null 2>&1
  fi
  wtl_hub_focus_middle
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
# viewer pane follows the new agent, or opens in place over the hub Claude. The focus goes there.
wtl_hub_show() {
  local id=$1 name=$2 cwd=$3 line viewer changed hub
  line=$(printf '%s\t%s' "$id" "$cwd")
  if IFS=$'\t' read -r viewer changed < <(wtl_hub_point agent "$line"); then
    [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$viewer" "$name" >/dev/null 2>&1
  else
    hub=$(wtl_hub_claude_pane)
    [[ -n "$hub" ]] || return 1
    wtl_hub_write_target agent "$line"
    viewer=$(zellij -s "$WT_HUB_SESSION" action new-pane --in-place --pane-id "terminal_$hub" --close-on-exit \
      --name "$name" --cwd "$cwd" -- "$HOME/.local/bin/wt-hub-pane" agent)
    [[ "$viewer" == terminal_* ]] || return 1
    wtl_hub_role_ready agent
  fi
  wtl_hub_focus_middle
}

# Close the agent viewer when it shows agent $1 (short id); the hub Claude comes back.
wtl_hub_close() {
  local pane
  IFS=$'\t' read -r pane _ < <(wtl_hub_role agent) || return 0
  [[ "$(cut -f1 "$(wtl_hub_target_file agent)" 2>/dev/null)" == "$1" ]] || return 0
  zellij -s "$WT_HUB_SESSION" action close-pane --pane-id "$pane"
}

# --- Hub review (tuicr) and files (yazi) panes, following the picked worktree ---

WT_HUB_NVIM="$HOME/.local/state/wt-hub-nvim.sock"

wtl_nvim_alive() {
  [[ -S "$WT_HUB_NVIM" ]] && nvim --server "$WT_HUB_NVIM" --remote-expr '1' >/dev/null 2>&1
}

wtl_nvim_send() {
  nvim --server "$WT_HUB_NVIM" --remote-send "<C-\\><C-n>$1" >/dev/null 2>&1
}

# "repo/branch" of the worktree $1, for pane titles.
wtl_hub_title() {
  local client repo branch top
  IFS=$'\t' read -r client repo branch top < <(wtl_describe "$1")
  printf '%s/%s\n' "$repo" "${branch##*/}"
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
    [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "$(wtl_hub_mode) · $title" >/dev/null 2>&1
  fi
  if IFS=$'\t' read -r pane changed < <(wtl_hub_point files "$top"); then
    [[ "$changed" == 1 ]] && zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "files · $title" >/dev/null 2>&1
  fi
  return 0
}

# Title the pane of role $1 (review or files) after the worktree in its target; review's title
# starts with its mode. zellij does not rename a suspended pane, so review gets its title again
# when files closes.
wtl_hub_retitle() {
  local pane top prefix=$1
  IFS=$'\t' read -r pane _ < <(wtl_hub_role "$1") || return 0
  top=$(cut -f1 "$(wtl_hub_target_file "$1")" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  [[ "$1" == review ]] && prefix=$(wtl_hub_mode)
  zellij -s "$WT_HUB_SESSION" action rename-pane -p "$pane" "$prefix · $(wtl_hub_title "$top")" >/dev/null 2>&1
}

# Switch review between turns and commits (the list's t): the pane starts tuicr again.
wtl_hub_toggle_review() {
  local pid
  wtl_hub_toggle_mode
  IFS=$'\t' read -r _ pid < <(wtl_hub_role review) || return 0
  wtl_kill_children "$pid"
}

# Show files (yazi) in place over review, in the review's worktree.
wtl_hub_show_files() {
  local review top pane
  wtl_hub_role files >/dev/null && return 0
  IFS=$'\t' read -r review _ < <(wtl_hub_role review) || return 0
  top=$(cut -f1 "$(wtl_hub_target_file review)" 2>/dev/null)
  [[ -n "$top" ]] || return 0
  wtl_hub_write_target files "$top"
  pane=$(zellij -s "$WT_HUB_SESSION" action new-pane --in-place --pane-id "$review" --close-on-exit \
    --name "files · $(wtl_hub_title "$top")" --cwd "$top" -- "$HOME/.local/bin/wt-hub-pane" files)
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
