# The mux layer, tmux backend (JAY_MUX=tmux). jay-lib.sh sources it; the API is described
# there ("The mux layer"). The hub is session $JAY_SESSION on jay's own tmux server
# (`tmux -L $JAY_TMUX_SOCKET`, config ~/.config/jay/tmux.conf from config/tmux/jay.conf), so the
# user's ~/.tmux.conf and their own tmux sessions do not matter, and a zellij hub can run beside
# it. A pane id is tmux's "%<n>", a tab is a window and its id is "@<n>". Hidden panes (review
# under files, a hidden review) live in windows whose names start with "_".
# The tmux facts these functions rely on are in CLAUDE.md ("tmux facts").

JAY_TMUX_SOCKET=${JAY_TMUX_SOCKET:-jay}
JAY_TMUX_CONF=${JAY_TMUX_CONF:-$HOME/.config/jay/tmux.conf}

# Every tmux call of the hub, on jay's server; it gives up after $JAY_TMUX_TIMEOUT seconds.
# -u: without a UTF-8 locale (a notice click has no LANG or LC_*), tmux writes the tabs of a -F
# format and each non-ASCII character as "_".
_jay_tm() {
  perl -e 'alarm shift; exec @ARGV or exit 127' "${JAY_TMUX_TIMEOUT:-5}" tmux -L "$JAY_TMUX_SOCKET" -u -f "$JAY_TMUX_CONF" "$@"
}

# The caller runs in a pane of jay's tmux server ($TMUX: socket path, server pid, session).
_jay_tm_inside() {
  local sock=${TMUX:-}
  sock=${sock%%,*}
  [[ -n "$sock" && "${sock##*/}" == "$JAY_TMUX_SOCKET" ]]
}

# --- The session ---

jay_mux_in_hub() {
  _jay_tm_inside && [[ -z "${CLAUDE_JOB_DIR:-}" ]]
}

jay_mux_alive() {
  _jay_tm has-session -t "=$JAY_SESSION" >/dev/null 2>&1
}

jay_mux_has_client() {
  [[ -n "$(_jay_tm list-clients -t "=$JAY_SESSION" -F x 2>/dev/null)" ]]
}

jay_mux_server_pid() {
  _jay_tm display-message -p -t "=$JAY_SESSION:" '#{pid}' 2>/dev/null
}

# Remove a server that does not answer (or has no hub session). A server that hangs is killed by
# its socket's name.
jay_mux_kill() {
  _jay_tm kill-server >/dev/null 2>&1 && return 0
  pkill -9 -f "tmux -L $JAY_TMUX_SOCKET( |\$)" 2>/dev/null || true
}

# The hub of wt-hub (jay's old name) runs: the zellij session "hub" with the list pane
# "worktrees". It shares the hub Claude and the marks, so it quits first.
jay_mux_old_hub() {
  command -v zellij >/dev/null 2>&1 || return 1
  [[ "$JAY_SESSION" != hub ]] && jay_live_sessions | grep -qxF hub \
    && zellij -s hub action list-panes -j 2>/dev/null | jq -e 'any(.[]; .title == "worktrees")' >/dev/null 2>&1
}

# Start the hub in this terminal (exec): the server, the hub window (list | agent | review, the
# list at its saved share), then attach. The panes get JAY_MUX, JAY_SESSION and
# JAY_TMUX_SOCKET from the server's environment.
jay_mux_start() {
  local list middle right lines cols root=${JAY_ROOTS%%:*} p0 p1 p2
  read -r list middle right < <(jay_hub_widths)
  read -r lines cols < <(stty size 2>/dev/null) || true
  [[ "${cols:-}" =~ ^[0-9]+$ ]] || cols=200
  [[ "${lines:-}" =~ ^[0-9]+$ ]] || lines=50
  export JAY_MUX=tmux JAY_SESSION JAY_TMUX_SOCKET
  [[ -f "$JAY_TMUX_CONF" ]] || { echo "jay: $JAY_TMUX_CONF is missing: run ./install.sh in jay" >&2; exit 1; }
  p0=$(_jay_tm new-session -d -s "$JAY_SESSION" -n hub -x "$cols" -y "$((lines - 2))" -c "$root" \
    -P -F '#{pane_id}' "$HOME/.local/bin/jay-sidebar") || { echo "jay: tmux did not start" >&2; exit 1; }
  p1=$(_jay_tm split-window -h -d -t "$p0" -l "$((100 - list))%" -c "$root" -P -F '#{pane_id}' \
    "$HOME/.local/bin/jay-pane" agent)
  p2=$(_jay_tm split-window -h -d -t "$p1" -l "$((right * 100 / (middle + right)))%" -c "$root" \
    -P -F '#{pane_id}' "$HOME/.local/bin/jay-pane" review)
  _jay_tm_keep "$p0" list
  _jay_tm_keep "$p1" agent
  _jay_tm_keep "$p2" review
  # select-pane -T only sets the title; the last select-pane gives the agent the focus.
  _jay_tm select-pane -t "$p0" -T worktrees \; select-pane -t "$p2" -T review \; select-pane -t "$p1" -T hub \
    \; select-pane -t "$p1"
  exec tmux -L "$JAY_TMUX_SOCKET" -f "$JAY_TMUX_CONF" attach -t "=$JAY_SESSION"
}

# Pane $1 has role $2 of the hub (list, agent or review): @jay_role finds it wherever it is, and
# when its program ends (killed, crashed) tmux keeps the pane and starts the program again a
# second later (remain-on-exit and a pane-died hook of the pane's own; the delay keeps a program
# that fails at once from spinning).
_jay_tm_keep() {
  _jay_tm set-option -p -t "$1" @jay_role "$2" \; set-option -p -t "$1" remain-on-exit on \; \
    set-hook -p -t "$1" pane-died "run-shell -b -d 1 -C 'respawn-pane -t #{hook_pane}'" >/dev/null 2>&1
}

# The role of a hub pane with start command $1 (a pane of a hub that started before roles).
_jay_tm_role_of() {
  case $1 in
    *jay-sidebar | *jay-sidebar\") printf 'list\n' ;;
    *jay-pane*" agent") printf 'agent\n' ;;
    *jay-pane*" review") printf 'review\n' ;;
  esac
}

# Bring back the hub's panes that are gone (a closed pane, the closed hub window), each in its
# column (list | agent | review) at its saved width, titled $1, $2 and $3, and start again a role
# pane whose program ended. Files over a review that is gone closes; a review left in the hidden
# window of files that is gone comes back; a hidden review (Ctrl g v) stays hidden. Prints the
# roles it brought back.
jay_mux_repair() {
  local root=${JAY_ROOTS%%:*} id win role dead covers start list="" agent="" review="" rwin="" files="" fcovers=""
  local w lw mw rw made="" restarted="" right
  read -r lw mw rw < <(jay_hub_widths)
  while IFS=$'\t' read -r id win role dead covers start; do
    case $win in hub | _review | _cover) ;; *) continue ;; esac
    if [[ -z "$role" ]]; then
      role=$(_jay_tm_role_of "$start")
      [[ -n "$role" ]] && _jay_tm_keep "$id" "$role"
    fi
    case $role in
      list) [[ -z "$list" ]] && list=$id || continue ;;
      agent) [[ -z "$agent" ]] && agent=$id || continue ;;
      review) [[ -z "$review" ]] && review=$id rwin=$win || continue ;;
      *) [[ -n "$covers" && "$win" == hub ]] && files=$id fcovers=$covers
         continue ;;
    esac
    if [[ "$dead" == 1 ]]; then
      _jay_tm respawn-pane -t "$id" >/dev/null 2>&1 && restarted+="$role "
    fi
  done < <(_jay_tm list-panes -s -t "=$JAY_SESSION" \
    -F '#{pane_id}	#{window_name}	#{@jay_role}	#{pane_dead}	#{@jay_covers}	#{pane_start_command}' 2>/dev/null)
  if [[ -n "$files" && "$fcovers" != "$review" ]]; then
    _jay_tm kill-pane -t "$files" >/dev/null 2>&1
    files=""
  fi
  if [[ -z "$list" ]]; then
    if _jay_tm list-windows -t "=$JAY_SESSION" -F '#{window_name}' 2>/dev/null | grep -qx hub; then
      w=$(_jay_tm display-message -p -t "=$JAY_SESSION:hub" '#{window_width}' 2>/dev/null)
      list=$(_jay_tm split-window -h -b -f -d -t "=$JAY_SESSION:hub" -l "$((${w:-200} * lw / 100))" -c "$root" \
        -P -F '#{pane_id}' "$HOME/.local/bin/jay-sidebar")
    else
      list=$(_jay_tm new-window -d -b -t "=$JAY_SESSION:^" -n hub -c "$root" -P -F '#{pane_id}' "$HOME/.local/bin/jay-sidebar")
    fi
    [[ -n "$list" ]] || return 1
    _jay_tm_keep "$list" list
    _jay_tm select-pane -t "$list" -T "$1" >/dev/null 2>&1
    made+="list "
  fi
  w=$(_jay_tm display-message -p -t "$list" '#{window_width}' 2>/dev/null)
  w=${w:-200}
  # The column right of the agent: review, or files over it.
  right=$files
  [[ "$rwin" == hub ]] && right=$review
  if [[ -z "$agent" ]]; then
    if [[ -n "$right" ]]; then
      agent=$(_jay_tm split-window -h -b -d -t "$right" -l "$((w * mw / 100))" -c "$root" \
        -P -F '#{pane_id}' "$HOME/.local/bin/jay-pane" agent)
    else
      agent=$(_jay_tm split-window -h -d -t "$list" -l "$((w * (100 - lw) / 100))" -c "$root" \
        -P -F '#{pane_id}' "$HOME/.local/bin/jay-pane" agent)
    fi
    [[ -n "$agent" ]] || return 1
    _jay_tm_keep "$agent" agent
    _jay_tm select-pane -t "$agent" -T "$2" >/dev/null 2>&1
    made+="agent "
  fi
  if [[ -z "$review" ]]; then
    rm -f "$JAY_HIDDEN"
    review=$(_jay_tm split-window -h -d -t "$agent" -l "$((w * rw / 100))" -c "$root" \
      -P -F '#{pane_id}' "$HOME/.local/bin/jay-pane" review \; set-option -gu @jay_hidden)
    [[ -n "$review" ]] || return 1
    _jay_tm_keep "$review" review
    _jay_tm select-pane -t "$review" -T "$3" >/dev/null 2>&1
    rwin=hub right=$review
    made+="review "
  elif [[ "$rwin" == _cover && -z "$files" ]]; then
    _jay_tm join-pane -d -h -l "$((w * rw / 100))" -s "$review" -t "$agent" >/dev/null 2>&1
    rwin=hub right=$review
    made+="review "
  fi
  # A pane that came back: the columns at their saved widths (the agent's right edge only while
  # a column is right of it).
  if [[ -n "$made" ]]; then
    _jay_tm resize-pane -t "$list" -x "$((w * lw / 100))" >/dev/null 2>&1
    [[ -n "$right" ]] && _jay_tm resize-pane -t "$agent" -x "$((w * mw / 100))" >/dev/null 2>&1
  fi
  made+=$restarted
  [[ -z "$made" ]] || printf '%s\n' "${made% }"
}

jay_mux_attach() {
  exec tmux -L "$JAY_TMUX_SOCKET" -f "$JAY_TMUX_CONF" attach -t "=$JAY_SESSION"
}

jay_mux_attach_cmd() {
  printf 'tmux -L %q attach -t %q\n' "$JAY_TMUX_SOCKET" "=$JAY_SESSION"
}

# The Ghostty tab that shows the hub: its tty is one of the hub's clients; else a tab whose tmux
# client or title names the session (jay_gh_tab_session).
jay_mux_gh_tab() {
  local clients id sel front tty title
  clients=$(_jay_tm list-clients -t "=$JAY_SESSION" -F '#{client_tty}' 2>/dev/null)
  [[ -n "$clients" ]] || return 1
  while IFS=$'\t' read -r id sel front tty title; do
    grep -qxF "$tty" <<<"$clients" && { printf '%s\n' "$id"; return 0; }
  done < <(jay_gh_tabs)
  jay_gh_tab_for_session "tmux:$JAY_SESSION"
}

# What `jay --print-layout` prints: the tmux commands that make the hub window.
jay_mux_print_layout() {
  local list middle right
  read -r list middle right < <(jay_hub_widths)
  cat <<EOF
# tmux -L $JAY_TMUX_SOCKET -f $JAY_TMUX_CONF
new-session -d -s $JAY_SESSION -n hub $HOME/.local/bin/jay-sidebar           # list, $list%
split-window -h -l $((100 - list))% $HOME/.local/bin/jay-pane agent          # agent, $middle%
split-window -h -l $((right * 100 / (middle + right)))% $HOME/.local/bin/jay-pane review   # review, $right%
# each of the three: set-option -p @jay_role list|agent|review, remain-on-exit on, and a
# pane-died hook: run-shell -b -d 1 -C 'respawn-pane -t #{hook_pane}'
EOF
}

# --- Panes ---

# The hub's panes, as in the zellij backend. tab is the window name; a pane in a hidden window
# ("_cover", "_review") belongs to the hub tab and is hidden. launch is the start command
# without tmux's quotes; command is the program's name; pid is the pane's first process.
jay_mux_panes() {
  local out
  out=$(_jay_tm list-panes -s -t "=$JAY_SESSION" -F \
    '#{pane_id}	#{window_name}	#{window_id}	#{pane_left}	#{pane_width}	#{pane_active}	#{window_active}	#{pane_dead}	#{pane_dead_status}	#{pane_pid}	#{pane_current_path}	#{pane_current_command}	#{pane_title}	#{pane_start_command}' 2>/dev/null) \
    || return 1
  [[ -n "$out" ]] || return 1
  jq -Rc 'split("\t") | (.[1] | startswith("_")) as $hidden
    | {pane: .[0], n: (.[0][1:] | tonumber), tab: (if $hidden then "hub" else .[1] end), tab_id: .[2],
       title: .[12], x: (.[3] | tonumber), cols: (.[4] | tonumber),
       launch: (.[13:] | join("\t") | if . == "" then null
                else gsub("(?<!\\\\)\""; "") | gsub("\\\\(?<c>.)"; "\(.c)") end),
       command: (.[11] | if . == "" then null else . end), cwd: .[10],
       focused: (.[5] == "1" and .[6] == "1" and ($hidden | not)), floating: false, hidden: $hidden,
       exited: (.[7] == "1"), exit: (.[8] | if . == "" then null else tonumber end),
       pid: (.[9] | tonumber? // null)}' <<<"$out"
}

# The caller's own pane: $TMUX_PANE on jay's server, not in a popup (a popup has no pane; its
# TMUX_PANE is the pane under it).
jay_mux_self() {
  [[ -z "${JAY_POPUP:-}" ]] && _jay_tm_inside && [[ -n "${TMUX_PANE:-}" ]] && printf '%s\n' "$TMUX_PANE"
}

jay_mux_rename() {
  [[ -n "${1:-}" ]] || return 0
  _jay_tm select-pane -t "$1" -T "$2" >/dev/null 2>&1
}

jay_mux_read() {
  [[ -n "${1:-}" ]] || return 1
  if [[ "${2:-}" == --full ]]; then
    _jay_tm capture-pane -p -t "$1" -S - 2>/dev/null
  else
    _jay_tm capture-pane -p -t "$1" 2>/dev/null
  fi
}

jay_mux_type() {
  [[ -n "${1:-}" ]] || return 1
  _jay_tm send-keys -t "$1" -l "$2" >/dev/null 2>&1
}

jay_mux_close() {
  [[ -n "${1:-}" ]] || return 0
  _jay_tm kill-pane -t "$1" >/dev/null 2>&1
}

# A new pane over pane $1: it starts in a hidden window and swaps places with $1, which runs on
# there. The new pane records the pane it covers (@jay_covers).
jay_mux_cover() {
  local new
  new=$(_jay_tm new-window -d -t "=$JAY_SESSION:" -n _cover -c "$3" -P -F '#{pane_id}' "${@:4}") || return 1
  _jay_tm select-pane -t "$new" -T "$2" \; set-option -p -t "$new" @jay_covers "$1" \; \
    swap-pane -d -s "$new" -t "$1" >/dev/null 2>&1
  printf '%s\n' "$new"
}

# Close cover $1: the covered pane goes back to its place first.
jay_mux_uncover() {
  local under
  under=$(_jay_tm display-message -p -t "$1" '#{@jay_covers}' 2>/dev/null)
  [[ -n "$under" ]] && _jay_tm swap-pane -d -s "$1" -t "$under" >/dev/null 2>&1
  jay_mux_close "$1"
}

# The cover's own program ended (q in yazi): the covered pane goes back. The pane ends after.
jay_mux_cover_done() {
  local under
  [[ -n "${1:-}" ]] || return 0
  under=$(_jay_tm display-message -p -t "$1" '#{@jay_covers}' 2>/dev/null)
  [[ -n "$under" ]] && _jay_tm swap-pane -d -s "$1" -t "$under" >/dev/null 2>&1
  return 0
}

# Wait up to 2 s until pane $1 is in a window that shows (not hidden).
jay_mux_wait_shown() {
  local i
  for i in $(seq 20); do
    jay_mux_panes | jq -e --arg p "$1" 'select(.pane == $p and (.hidden | not))' >/dev/null && return 0
    sleep 0.1
  done
  return 1
}

jay_mux_wait_gone() {
  local end=$((SECONDS + ${2:-5}))
  [[ -n "${1:-}" ]] || return 0
  while ((SECONDS < end)); do
    jay_mux_panes | jq -e --arg p "$1" 'select(.pane == $p)' >/dev/null || return 0
    sleep 0.2
  done
  return 1
}

# The terminal's focus to column $1 of the hub window: the pane of that role (review: the pane
# right of the agent, review or files over it); in a hub without roles, panes 0, 1, 2 from the
# left. tmux moves the client's own focus, from anywhere: $2 is not needed.
jay_mux_focus() {
  local panes pane
  panes=$(_jay_tm list-panes -t "=$JAY_SESSION:hub" -F '#{pane_id} #{@jay_role}' 2>/dev/null)
  case $1 in
    list | agent) pane=$(awk -v r="$1" '$2 == r { print $1; exit }' <<<"$panes") ;;
    *) pane=$(awk 'f { print $1; exit } $2 == "agent" { f = 1 }' <<<"$panes") ;;
  esac
  if [[ -z "$pane" ]] && ! grep -q ' [a-z]' <<<"$panes"; then
    case $1 in list) pane=0 ;; agent) pane=1 ;; *) pane=2 ;; esac
    pane="=$JAY_SESSION:hub.$pane"
  fi
  [[ -n "$pane" ]] || return 0
  _jay_tm select-window -t "=$JAY_SESSION:hub" \; select-pane -t "$pane" >/dev/null 2>&1
  return 0
}

# The list (the caller's pane) narrower or wider by 5 % of the window.
jay_mux_resize_list() {
  local self w ww
  self=$(jay_mux_self)
  [[ -n "$self" ]] || return 0
  read -r w ww < <(_jay_tm display-message -p -t "$self" '#{pane_width} #{window_width}')
  [[ -n "${ww:-}" ]] || return 0
  if [[ "$1" == decrease ]]; then w=$((w - ww / 20)); else w=$((w + ww / 20)); fi
  ((w > 10)) || w=10
  _jay_tm resize-pane -t "$self" -x "$w" >/dev/null 2>&1
}

jay_mux_list_share() {
  local self w ww
  self=$(jay_mux_self)
  [[ -n "$self" ]] || return 0
  read -r w ww < <(_jay_tm display-message -p -t "$self" '#{pane_width} #{window_width}')
  [[ -n "${ww:-}" && "$ww" -gt 0 ]] && printf '%s\n' "$(((w * 100 + ww / 2) / ww))"
}

# The launcher runs in a popup of a fixed size.
jay_mux_float_height() {
  return 0
}

# Show text $1 in a popup titled $2, on the caller's client, sized to the text, until a key: the
# popup the caller runs in cannot grow, and a client has one popup at a time, so the new one
# opens just after the caller's closes (the caller ends right after this). Fails outside a popup.
jay_mux_popup_text() {
  local client file h title cmd
  [[ -n "${JAY_POPUP:-}" ]] && _jay_tm_inside || return 1
  client=$(_jay_tm display-message -p '#{client_name}' 2>/dev/null)
  [[ -n "$client" ]] || return 1
  jay_state_dir
  file=$(mktemp "$JAY_HUB_STATE/popup.XXXXXX") || return 1
  printf '%s\n' "$1" >"$file"
  h=$(($(wc -l <"$file") + 3))
  ((h > 40)) && h=40
  ((h < 5)) && h=5
  title=" ${2//#/##} · any key: close "
  cmd=$(printf '%q ' "$HOME/.local/bin/jay-run" --show "$file")
  _jay_tm run-shell -b "sleep 0.3; $(printf '%q ' "$(command -v tmux)" -L "$JAY_TMUX_SOCKET" -f "$JAY_TMUX_CONF" \
    display-popup -c "$client" -E -e JAY_POPUP=1 -w 70% -h "$h" -T "$title" "$cmd")" >/dev/null 2>&1
}

# --- Tabs (windows; the hidden ones are not tabs) ---

jay_mux_tabs() {
  _jay_tm list-windows -t "=$JAY_SESSION" -F '#{window_id}	#{window_name}	#{window_active}' 2>/dev/null \
    | jq -Rc 'split("\t") | select(.[1] | startswith("_") | not) | {id: .[0], name: .[1], active: (.[2] == "1")}'
}

jay_mux_tab_id() {
  jay_mux_tabs | jq -r --arg t "$1" 'select(.name == $t) | .id' | head -1
}

jay_mux_active_tab() {
  jay_mux_tabs | jq -r 'select(.active) | .name' | head -1
}

# By name: a window name can hold "." or ":", which a tmux target cannot; go by its id.
jay_mux_tab_go() {
  local id
  id=$(jay_mux_tab_id "$1")
  [[ -n "$id" ]] && _jay_tm select-window -t "$id" >/dev/null 2>&1
}

jay_mux_tab_go_id() {
  _jay_tm select-window -t "$1" >/dev/null 2>&1
}

# A tasks window named $1 for worktree $2: a console (your shell) in the worktree; the banner
# (status line) shows the worktree from @jay_wt. No move of the view. Prints its id.
jay_mux_tab_new() {
  local id
  id=$(_jay_tm new-window -d -t "=$JAY_SESSION:" -n "$1" -c "$2" -P -F '#{window_id}') || return 1
  _jay_tm set-option -w -t "$id" @jay_wt "$1" \; select-pane -t "$id" -T console >/dev/null 2>&1
  printf '%s\n' "$id"
}

jay_mux_tab_close() {
  _jay_tm kill-window -t "$1" >/dev/null 2>&1
}

# A new pane in window $1, titled $2, in folder $3, running "${@:4}"; prints its id. As in
# zellij's tasks tab: up to three panes side by side, more in a grid. With no room, the panes
# make room first.
jay_mux_tab_pane() {
  local pane n layout=even-horizontal
  pane=$(_jay_tm split-window -h -d -t "$1" -c "$3" -P -F '#{pane_id}' "${@:4}" 2>/dev/null) \
    || { _jay_tm select-layout -t "$1" tiled >/dev/null 2>&1
         pane=$(_jay_tm split-window -d -t "$1" -c "$3" -P -F '#{pane_id}' "${@:4}" 2>/dev/null); } || return 1
  n=$(_jay_tm display-message -p -t "$1" '#{window_panes}' 2>/dev/null)
  ((${n:-0} > 3)) && layout=tiled
  _jay_tm select-pane -t "$pane" -T "$2" \; select-layout -t "$1" "$layout" >/dev/null 2>&1
  printf '%s\n' "$pane"
}

# --- The bar and the banner: the status line (config/tmux/jay.conf) shows user options ---

# ANSI colors (the list's and jay run's texts) as tmux styles; # doubled.
_jay_tm_style() {
  perl -pe 's/#/##/g;
    s{\e\[([0-9;]*)m}{
      my @s;
      for my $c (split /;/, ($1 eq "" ? "0" : $1)) {
        push @s, $c == 0 ? "default" : $c == 1 ? "bold" : $c == 2 ? "dim" : $c == 22 ? "nobold,nodim"
          : ($c >= 30 && $c <= 37) ? "fg=colour" . ($c - 30) : ($c >= 90 && $c <= 97) ? "fg=colour" . ($c - 82)
          : $c == 39 ? "fg=default" : ();
      }
      @s ? "#[" . join(",", @s) . "]" : "";
    }ge'
}

# Part $1 of the status line (agents, tasks, where, note; see jay_bar_set): kept, then the line
# is drawn again.
jay_mux_bar() {
  jay_bar_set "$1" "$2"
  # The launcher's popup title names the picked worktree too.
  [[ "$1" == where ]] && _jay_tm set-option -g @jay_where "$2" >/dev/null 2>&1
  jay_mux_status
}

# Window $1's own note (a tasks window: its tasks that run elsewhere).
jay_mux_tab_note() {
  jay_bar_set "note.$1" "$2"
  jay_mux_status
}

# The widths of the windows, to tell when the line must be cut again.
jay_mux_width() {
  _jay_tm list-windows -t "=$JAY_SESSION" -F '#{window_width}' 2>/dev/null | sort -u | paste -sd' ' -
}

# Draw the status line of each window: @jay_left, @jay_mid and @jay_right (window options, shown
# by status-format in config/tmux/jay.conf), cut to the window's width (jay_bar_fit). The width
# beside the parts: a space before the left part, 3 after it, 2 before " HH:MM ".
jay_mux_status() {
  local IFS=$' \t\n' id name w left mid right args=() c
  while IFS=$'\t' read -r id name w; do
    [[ -n "$id" && "$name" != _* ]] || continue
    if [[ "$name" == hub ]]; then
      left=$(jay_bar_left hub "$(cat "$JAY_BAR/where" 2>/dev/null)")
    else
      left=$(jay_bar_left tasks "$name" "$(cat "$JAY_BAR/note.$id" 2>/dev/null)")
    fi
    { IFS= read -r mid; IFS= read -r right; } < <(jay_bar_fit "$((w - $(jay_bar_cells "$left") - 13))")
    ((${#args[@]})) && args+=(\;)
    args+=(set-option -w -t "$id" @jay_left "$(printf '%s' "$left" | _jay_tm_style)"
      \; set-option -w -t "$id" @jay_mid "$(printf '%s' "$mid" | _jay_tm_style)"
      \; set-option -w -t "$id" @jay_right "$(printf '%s' "$right" | _jay_tm_style)")
  done < <(_jay_tm list-windows -t "=$JAY_SESSION" -F '#{window_id}	#{window_name}	#{window_width}' 2>/dev/null)
  ((${#args[@]})) || return 0
  _jay_tm "${args[@]}" >/dev/null 2>&1
  for c in $(_jay_tm list-clients -t "=$JAY_SESSION" -F '#{client_name}' 2>/dev/null); do
    _jay_tm refresh-client -t "$c" -S >/dev/null 2>&1
  done
  return 0
}

# --- Review hidden (Ctrl g v): review moves to a hidden window, the middle takes its width ---
# Files closes first (it covers review) and opens again after show.

# Review (pane $1) is hidden: print its window's id.
jay_mux_review_hidden() {
  _jay_tm display-message -p -t "$1" '#{window_name} #{window_id}' 2>/dev/null | awk '$1 == "_review" { print $2; f = 1 } END { exit !f }'
}

jay_mux_hide_review() {
  local review=$1 cols total files=0
  if jay_hub_role files >/dev/null; then
    files=1
    jay_hub_show_review
  fi
  read -r cols total < <(_jay_tm display-message -p -t "$review" '#{pane_width} #{window_width}' 2>/dev/null)
  [[ -n "${total:-}" ]] || return 0
  printf '%s %s\n' "$((cols * 100 / total))" "$files" >"$JAY_HIDDEN"
  _jay_tm break-pane -d -s "$review" -n _review \; set-option -g @jay_hidden 1 >/dev/null 2>&1
}

# Show the hidden review (pane $1) right of the agent pane, at its old share. --focus ($2): the
# focus goes to review; else it stays.
jay_mux_unhide_review() {
  local review=$1 share files agent total
  jay_mux_review_hidden "$review" >/dev/null || { rm -f "$JAY_HIDDEN"; return 0; }
  read -r share files <"$JAY_HIDDEN" 2>/dev/null
  [[ "${share:-}" =~ ^[0-9]+$ ]] || share=35
  IFS=$'\t' read -r agent _ < <(jay_hub_role agent) || return 0
  total=$(_jay_tm display-message -p -t "$agent" '#{window_width}' 2>/dev/null)
  [[ -n "$total" ]] || return 0
  _jay_tm join-pane -d -h -l "$((total * share / 100))" -s "$review" -t "$agent" \; set-option -gu @jay_hidden >/dev/null 2>&1
  rm -f "$JAY_HIDDEN"
  [[ "${files:-0}" == 1 ]] && jay_hub_show_files
  [[ "${2:-}" == --focus ]] && jay_mux_focus review
  return 0
}

# zellij's work-arounds for floating panes: nothing to do in tmux.
jay_mux_rehide() { return 0; }
jay_mux_keep_hidden() { return 0; }
