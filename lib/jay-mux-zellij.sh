# The mux layer, zellij backend (JAY_MUX=zellij, the default). jay-lib.sh sources it; the API
# is described there ("The mux layer"). Every call to the hub's zellij session goes through
# these functions. A pane id is zellij's "terminal_<n>"; a tab id is zellij's number.
# The zellij traps that these functions work around are in CLAUDE.md ("zellij 0.45 facts").

# zjstatus (github.com/dj95/zjstatus) v0.25.0, sha256 282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe.
# Without it the hub uses zellij's compact bar.
JAY_ZJSTATUS="$HOME/.local/share/jay/zjstatus-v0.25.0.wasm"

# --- The session ---

jay_mux_in_hub() {
  [[ "${ZELLIJ_SESSION_NAME:-}" == "$JAY_SESSION" && -z "${CLAUDE_JOB_DIR:-}" ]]
}

# The hub runs and answers. `zellij -s <a session that is not there>` exits 0: look for the
# session first.
jay_mux_alive() {
  jay_live_sessions | grep -qxF "$JAY_SESSION" && zellij -s "$JAY_SESSION" action list-clients >/dev/null 2>&1
}

# The hub has a terminal attached.
jay_mux_has_client() {
  jay_session_has_client "$JAY_SESSION"
}

# The pid of the hub's server. -a: inside a hub pane the server is an ancestor, which pgrep
# leaves out without it.
jay_mux_server_pid() {
  pgrep -a -f "zellij --server .*/$JAY_SESSION\$" | head -1
}

# Remove a hub that does not answer: an exited copy would come back resurrected (every pane
# waiting for Enter), and a server that outlived its session hangs every zellij command.
jay_mux_kill() {
  pkill -9 -f "zellij --server .*/$JAY_SESSION\$" 2>/dev/null || true
  zellij delete-session --force "$JAY_SESSION" >/dev/null 2>&1 || true
}

# The hub of wt-hub (jay's old name) runs: the zellij session "hub", with the list pane
# "worktrees".
jay_mux_old_hub() {
  [[ "$JAY_SESSION" != hub ]] && jay_live_sessions | grep -qxF hub \
    && zellij -s hub action list-panes -j 2>/dev/null | jq -e 'any(.[]; .title == "worktrees")' >/dev/null 2>&1
}

# Start the hub in this terminal (exec): the layout, written to $JAY_STATE/layout.kdl.
jay_mux_start() {
  local layout="$JAY_STATE/layout.kdl"
  jay_state_dir
  _jay_zj_layout >"$layout"
  exec zellij -s "$JAY_SESSION" -n "$layout"
}

# Attach this terminal to the running hub (exec).
jay_mux_attach() {
  exec zellij attach "$JAY_SESSION"
}

# The command line that attaches a terminal (for a new Ghostty tab).
jay_mux_attach_cmd() {
  printf 'zellij attach %s\n' "$JAY_SESSION"
}

# The Ghostty tab that shows the hub.
jay_mux_gh_tab() {
  jay_gh_tab_for_session "$JAY_SESSION"
}

# What `jay --print-layout` prints.
jay_mux_print_layout() {
  _jay_zj_layout
}

# --- Panes ---

# The hub's panes (all tabs, no plugins), one JSON object per line: pane (id), n (number), tab,
# tab_id, title, x, cols, launch (the command the pane started with, or null), command (the
# program that runs now; zellij can give null), cwd, focused, floating, hidden (under another
# pane), exited, exit (its status), pid (null: zellij does not give it). Fails when the hub does
# not answer.
jay_mux_panes() {
  local out
  out=$(zellij -s "$JAY_SESSION" action list-panes -a -j -c 2>/dev/null) || return 1
  jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1 || return 1
  jq -c '.[] | select(.is_plugin | not)
    | {pane: "terminal_\(.id)", n: .id, tab: .tab_name, tab_id, title, x: .pane_x, cols: .pane_columns,
       launch: .terminal_command, command: .pane_command, cwd: .pane_cwd, focused: .is_focused,
       floating: .is_floating, hidden: (.is_suppressed // false), exited: (.exited // false),
       exit: .exit_status, pid: null}' <<<"$out"
}

# The caller's own pane, when it runs in one.
jay_mux_self() {
  [[ -n "${ZELLIJ_PANE_ID:-}" ]] && printf 'terminal_%s\n' "$ZELLIJ_PANE_ID"
}

jay_mux_rename() {
  zellij -s "$JAY_SESSION" action rename-pane -p "$1" "$2" >/dev/null 2>&1
}

# The text of pane $1: the screen, or with --full the scrollback too.
jay_mux_read() {
  zellij -s "$JAY_SESSION" action dump-screen -p "$1" ${2:+"$2"} 2>/dev/null
}

# Type text $2 into pane $1.
jay_mux_type() {
  zellij -s "$JAY_SESSION" action write-chars -p "$1" "$2" >/dev/null 2>&1
}

jay_mux_close() {
  zellij -s "$JAY_SESSION" action close-pane --pane-id "$1" >/dev/null 2>&1
}

# Show a new pane over pane $1, titled $2, in folder $3, running "${@:4}"; prints its id.
# zellij keeps $1 suspended under it and shows it again when the new pane closes. Never over a
# suspended pane: zellij loses the new pane (jay_mux_wait_shown first).
jay_mux_cover() {
  zellij -s "$JAY_SESSION" action new-pane --in-place --pane-id "$1" --close-on-exit \
    --name "$2" --cwd "$3" -- "${@:4}"
}

# Close the pane $1 that covers another (jay_mux_cover): the covered one comes back.
jay_mux_uncover() {
  jay_mux_close "$1"
}

# The cover's own program ended: zellij shows the covered pane again by itself.
jay_mux_cover_done() {
  return 0
}

# Wait up to 2 s until pane $1 is shown, not suspended under another pane.
jay_mux_wait_shown() {
  local i
  for i in $(seq 20); do
    jay_mux_panes | jq -e --arg p "$1" 'select(.pane == $p and (.hidden | not))' >/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# Wait while pane $1 is open, up to $2 seconds (default 5).
jay_mux_wait_gone() {
  local end=$((SECONDS + ${2:-5}))
  [[ -n "${1:-}" ]] || return 0
  while ((SECONDS < end)); do
    jay_mux_panes | jq -e --arg p "$1" 'select(.pane == $p)' >/dev/null || return 0
    sleep 0.2
  done
  return 1
}

# Move the terminal's focus to column $1 of the hub tab: list, agent or review. $2: the column
# the caller knows the focus is in (the list, for its own keys), which saves moves.
# In zellij 0.45 `focus-pane-id` from the CLI sets a focus of its own, not the terminal's, and on
# a suspended pane it makes that pane float. `move-focus` moves the terminal's focus: left twice
# reaches the list, then steps right.
jay_mux_focus() {
  local to from=${2:-} i
  case $1 in list) to=0 ;; agent) to=1 ;; *) to=2 ;; esac
  if [[ "$from" == list ]]; then
    for ((i = 0; i < to; i++)); do zellij -s "$JAY_SESSION" action move-focus right >/dev/null 2>&1; done
    return 0
  fi
  zellij -s "$JAY_SESSION" action go-to-tab-name hub >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  for ((i = 0; i < to; i++)); do zellij -s "$JAY_SESSION" action move-focus right >/dev/null 2>&1; done
  return 0
}

# The list (the caller's pane) narrower or wider: $1 = decrease or increase.
jay_mux_resize_list() {
  zellij -s "$JAY_SESSION" action resize -p "$(jay_mux_self)" "$1" right >/dev/null 2>&1
}

# The caller's pane's share of its tab's width, in %.
jay_mux_list_share() {
  zellij -s "$JAY_SESSION" action list-panes -a -j 2>/dev/null | jq --argjson me "${ZELLIJ_PANE_ID:--1}" '
    (map(select(.is_plugin | not)) | map(select(.id == $me)) | first) as $pane
    | select($pane != null)
    | [.[] | select(.tab_id == $pane.tab_id and (.is_floating | not)) | .pane_x + .pane_columns] | max
    | ($pane.pane_columns * 100 / .) | round'
}

# Set the height of the caller's floating pane $1 (the launcher) to $2 rows.
jay_mux_float_height() {
  zellij -s "$JAY_SESSION" action change-floating-pane-coordinates -p "$1" --height "$2" >/dev/null 2>&1
}

# --- Tabs ---

# The tabs, one JSON object per line: id, name, active.
jay_mux_tabs() {
  zellij -s "$JAY_SESSION" action list-tabs -j 2>/dev/null | jq -c '.[] | {id: .tab_id, name, active}' 2>/dev/null
}

# The id of the tab named $1.
jay_mux_tab_id() {
  jay_mux_tabs | jq -r --arg t "$1" 'select(.name == $t) | .id' | head -1
}

# The name of the tab the terminal shows.
jay_mux_active_tab() {
  jay_mux_tabs | jq -r 'select(.active) | .name' | head -1
}

jay_mux_tab_go() {
  zellij -s "$JAY_SESSION" action go-to-tab-name "$1" >/dev/null 2>&1
}

jay_mux_tab_go_id() {
  zellij -s "$JAY_SESSION" action go-to-tab-by-id "$1" >/dev/null 2>&1
}

# A tasks tab named $1 for worktree $2 (banner, a console in the worktree, the bar), without
# moving the view; prints its id.
jay_mux_tab_new() {
  local layout
  jay_state_dir
  layout="$JAY_STATE/tasks-tab.$$.kdl"
  _jay_zj_tasks_layout "$(sed 's/[\\"]/\\&/g' <<<"$2")" "$1" >"$layout" || return 1
  jay_without_claude zellij -s "$JAY_SESSION" action new-tab --no-focus --layout "$layout" \
    --name "$1" --cwd "$2" >/dev/null 2>&1
  rm -f "$layout"
  jay_mux_tab_id "$1"
}

jay_mux_tab_close() {
  zellij -s "$JAY_SESSION" action close-tab-by-id "$1" >/dev/null 2>&1
}

# A new pane in tab $1, titled $2, in folder $3, running "${@:4}"; prints its id. It closes when
# its program ends.
jay_mux_tab_pane() {
  jay_without_claude zellij -s "$JAY_SESSION" action new-pane --tab-id "$1" --cwd "$3" --name "$2" \
    --close-on-exit -- "${@:4}"
}

# --- The bar and the banner (zjstatus, fed through pipes) ---

# Part $1 of the bar or banner: agents (the counts), tasks, where (the picked worktree, in the
# hub tab's banner). Text $2 may have ANSI colors.
jay_mux_bar() {
  zellij -s "$JAY_SESSION" pipe "zjstatus::pipe::pipe_$1::$2" >/dev/null 2>&1
}

# A tab's own part of the banner: zjstatus pipes reach every tab alike, so the tasks tabs' banner
# has one shared part instead ("note", jay_mux_bar).
jay_mux_tab_note() {
  return 0
}

# The bar at the bottom of the hub, in kanagawa colors: the agent counts and the tasks (both
# sent by the list, see jay-sidebar), the zellij mode when it is not locked and the time. No tab
# list: there is a tab per worktree, and the banner says which one is shown.
_jay_zj_bar() {
  if [[ ! -f "$JAY_ZJSTATUS" ]]; then
    printf '%s\n' 'plugin location="zellij:compact-bar"'
    return
  fi
  local tz
  tz=$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')
  cat <<KDL
plugin location="file:$JAY_ZJSTATUS" {
                format_left   "#[fg=#7E9CD8,bold] ◆ jay  {pipe_agents}   {pipe_tasks}"
                format_right  "{mode}#[fg=#727169] {datetime} "
                format_space  ""
                pipe_agents_format     "{output}"
                pipe_agents_rendermode "raw"
                pipe_tasks_format      "{output}"
                pipe_tasks_rendermode  "raw"
                mode_locked          ""
                mode_normal          "#[fg=#1F1F28,bg=#E6C384,bold] {name} #[fg=#727169] Ctrl q: quit hub · Ctrl g: lock  "
                mode_default_to_mode "normal"
                datetime          "{format}"
                datetime_format   "%H:%M"
                datetime_timezone "$tz"
            }
KDL
}

# The banner at the top of each tab, so that each tab says it is the hub's: "◆ JAY › <what the
# tab is>" ($1), the worktree ($3; without it the picked one, sent at each pick, see
# jay_hub_target and jay-sidebar) and where Ctrl g Tab goes ($2). Without zjstatus, none.
# A tasks tab's banner also has the note (jay run's tick): the tasks that run in other worktrees
# than the picked one.
_jay_zj_banner() {
  [[ -f "$JAY_ZJSTATUS" ]] || return 0
  local where='{pipe_where}'
  [[ -n "${3:-}" ]] && where="$(sed 's/[\\"]/\\&/g; s/#\[/# [/g' <<<"$3")   {pipe_note}"
  cat <<KDL
pane size=1 borderless=true {
            plugin location="file:$JAY_ZJSTATUS" {
                format_left   "#[fg=#1F1F28,bg=#7E9CD8,bold] ◆ JAY › $1 #[fg=#1F1F28,bg=#7E9CD8]  $where"
                format_right  "#[fg=#1F1F28,bg=#7E9CD8] Ctrl g Tab: $2 "
                format_space  "#[bg=#7E9CD8]"
                pipe_where_format     "#[fg=#1F1F28,bg=#7E9CD8]{output}"
                pipe_where_rendermode "static"
                pipe_note_format      "#[fg=#1F1F28,bg=#7E9CD8]{output}"
                pipe_note_rendermode  "static"
            }
        }
KDL
}

# The hub's layout: list | agent | review, the list at its saved share of the width.
_jay_zj_layout() {
  local list middle right
  read -r list middle right < <(jay_hub_widths)
  cat <<KDL
layout {
    default_tab_template {
        children
        pane size=1 borderless=true {
            $(_jay_zj_bar)
        }
    }
    tab name="hub" focus=true {
        $(_jay_zj_banner worktrees "its tasks")
        pane split_direction="vertical" {
            pane size="$list%" name="worktrees" command="$HOME/.local/bin/jay-sidebar"
            pane size="$middle%" name="hub" focus=true command="$HOME/.local/bin/jay-pane" {
                args "agent"
            }
            pane size="$right%" name="review" command="$HOME/.local/bin/jay-pane" {
                args "review"
            }
        }
    }
}
KDL
}

# The tasks tab of worktree $1 (escaped for KDL), named $2: the banner, the console (a shell in
# the worktree, see jay-run), the bar.
_jay_zj_tasks_layout() {
  cat <<KDL
layout {
    $(_jay_zj_banner tasks "back to the hub" "$2")
    pane cwd="$1" name="console"
    pane size=1 borderless=true {
        $(_jay_zj_bar)
    }
}
KDL
}

# --- Review hidden (Ctrl g v): the middle column takes review's width ---
# zellij 0.45 cannot hide a tiled pane. Review becomes a floating pane of no size in the bottom
# right corner, and the tab's floating panes hide; tuicr runs on, so your place and draft
# comments stay. A new floating pane (Ctrl g Tab, Ctrl g r) shows the floating panes again, and
# when it closes the hidden review gets the keys: jay_mux_keep_hidden hides them again.
# An embedded floating pane goes under the biggest pane, so show opens a placeholder right of
# the middle column and stacks review with it: a floating pane takes the place of the pane it is
# stacked with. The placeholder then closes. Files closes before review hides (a floating files
# pane loses the review under it) and opens again after show.
# $JAY_HIDDEN holds review's share of the tab's width and 1 when files was open.

# Review (pane $1) is hidden (its pane floats): print the id of its tab.
jay_mux_review_hidden() {
  zellij -s "$JAY_SESSION" action list-panes -a -j -c 2>/dev/null \
    | jq -er --argjson id "${1#terminal_}" '.[] | select((.is_plugin | not) and .id == $id and .is_floating) | .tab_id'
}

# Hide review (pane $1).
jay_mux_hide_review() {
  local review=$1 tab cols total files=0
  if jay_hub_role files >/dev/null; then
    files=1
    jay_hub_show_review
    jay_mux_wait_shown "$review" || return 0
  fi
  read -r tab cols total < <(jay_mux_panes | jq -rs --arg p "$review" '
    (map(select(.pane == $p)) | first) as $r | select($r != null and ($r.floating | not))
    | [$r.tab_id, $r.cols, ([.[] | select(.tab_id == $r.tab_id and (.floating | not)) | .x + .cols] | max)]
    | @tsv')
  [[ -n "${total:-}" ]] || return 0
  printf '%s %s\n' "$((cols * 100 / total))" "$files" >"$JAY_HIDDEN"
  zellij -s "$JAY_SESSION" action toggle-pane-embed-or-floating -p "$review" >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action change-floating-pane-coordinates -p "$review" -x 100% -y 100% --width 1 --height 1 >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
}

# Show the hidden review (pane $1) in the right column again, at its old width. --focus ($2): the
# focus goes to review; else it goes back to the column that had it.
jay_mux_unhide_review() {
  local review=$1 tab share files list place i cols total
  tab=$(jay_mux_review_hidden "$review") || { rm -f "$JAY_HIDDEN"; return 0; }
  read -r share files <"$JAY_HIDDEN" 2>/dev/null
  [[ "${share:-}" =~ ^[0-9]+$ ]] || share=35
  # The focus moves below act on the tiled panes only while the floating ones are hidden.
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
  list=$(jay_mux_panes | jq -rs --argjson t "$tab" \
    'any(.[]; .tab_id == $t and (.floating | not) and .focused and .x == 0)')
  jay_mux_focus agent
  place=$(zellij -s "$JAY_SESSION" action new-pane --direction right --close-on-exit -- sleep 10)
  [[ "$place" == terminal_* ]] || return 0
  zellij -s "$JAY_SESSION" action stack-panes -- "$place" "$review" >/dev/null 2>&1
  zellij -s "$JAY_SESSION" action close-pane -p "$place" >/dev/null 2>&1
  rm -f "$JAY_HIDDEN"
  # zellij resizes in steps of 5 % of the tab.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    read -r cols total < <(jay_mux_panes | jq -rs --arg p "$review" '
      (map(select(.pane == $p)) | first) as $r | select($r != null)
      | [$r.cols, ([.[] | select(.tab_id == $r.tab_id and (.floating | not)) | .x + .cols] | max)]
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
  if [[ "${2:-}" != --focus ]]; then
    zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
    [[ "$list" == true ]] && zellij -s "$JAY_SESSION" action move-focus left >/dev/null 2>&1
  fi
  return 0
}

# Hide the floating panes of the hub tab again when the hidden review (pane $1) is the only one
# left.
jay_mux_rehide() {
  local tab
  tab=$(jay_mux_review_hidden "$1") || return 0
  jay_mux_panes | jq -se --argjson t "$tab" '[.[] | select(.tab_id == $t and .floating)] | length == 1' >/dev/null || return 0
  [[ "$(zellij -s "$JAY_SESSION" action are-floating-panes-visible -t "$tab" 2>/dev/null)" == true ]] || return 0
  zellij -s "$JAY_SESSION" action hide-floating-panes -t "$tab" >/dev/null 2>&1
}

# For a Run binding's floating pane $1 (the caller's own): when it closes, hide the floating
# panes again (review hidden). In the background, up to an hour: the pane closes when its caller
# ends.
jay_mux_keep_hidden() {
  [[ -f "$JAY_HIDDEN" && -n "${1:-}" ]] || return 0
  (trap '' HUP; jay_mux_wait_gone "$1" 3600 && jay_hub_rehide) </dev/null >/dev/null 2>&1 &
}
