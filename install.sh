#!/bin/bash
# install.sh [--link] [--with-mod] [--with-setup] [--force] [--compat] | --check | --no-compat | --uninstall
# Install jay (it was wt-hub) for this user (macOS). It runs again safely: run it again after a
# git pull.
#   ~/.local/bin/<each script in bin/>, ~/.local/lib/jay-lib.sh and jay-mux-*.sh
#                                    copies; --link: symlinks into this repo, so an edit is live
#                                    at once (for work on jay itself)
#   ~/.local/bin/<old names>, ~/.local/lib/wt-lib.sh
#                                    the shims in compat/: wt new, hub-run, ... run jay's commands
#   ~/.config/jay/config             your settings (JAY_ROOTS, ...), made when missing
#   ~/.config/jay/yazi, lazygit      the hub's yazi keys and lazygit settings (JAY_REVIEW=lazygit)
#   ~/.config/jay/tmux.conf          the tmux hub's own config (JAY_MUX=tmux), from config/tmux
#   ~/.config/tuicr/config.toml      made when missing (q_quits = true); else only checked
#   ~/.config/worktrunk/config.toml  copied when missing (always a copy: client settings go
#                                    there); else the hub's keys it lacks are listed
#   ~/.claude/settings.json          the hub's hooks, only the missing ones (a backup first); the
#                                    hooks of wt-hub go
#   ~/.local/share/jay/              zjstatus v0.25.0 for the bar (sha256 checked)
#   --with-mod                       also the Claude Code mod (/jay), marketplace jay
#   --with-setup                     also worktrunk's pre-start = "jay-setup": in each new
#                                    worktree, copy ignored files and install dependencies
# From wt-hub: it moves ~/.config/wt-hub, ~/.local/share/wt-hub and the hub's state files in
# ~/.local/state to their jay places (a link stays at each old path, for a hub that still runs),
# and an installed wt-hub mod becomes the jay mod.
# It never changes a file it did not install (--force: replace it), and it never edits
# ~/.config/zellij/config.kdl: it prints the pane keys to add there.
# --check: report the tools and the install, change nothing.
# --no-compat: remove the shims and the links at the old paths, and leave them out from now on
# (--compat: put them back).
# --uninstall: remove what it installed; list the config entries to remove by hand.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HOME/.local/bin" LIB="$HOME/.local/lib" SHARE="$HOME/.local/share/jay"
CONF="$HOME/.config/jay"
MANIFEST="$SHARE/installed.txt"
NOCOMPAT="$SHARE/no-compat"
ZJSTATUS="$SHARE/zjstatus-v0.25.0.wasm"
ZJSTATUS_URL=https://github.com/dj95/zjstatus/releases/download/v0.25.0/zjstatus.wasm
ZJSTATUS_SHA=282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
SETTINGS="$HOME/.claude/settings.json"
SETTINGS_FILE="$CONF/config"
# --check on an install of wt-hub that was not moved yet: its list of installed files.
[[ " $* " == *" --check "* && ! -f "$MANIFEST" && -f "$HOME/.local/share/wt-hub/installed.txt" ]] \
  && MANIFEST="$HOME/.local/share/wt-hub/installed.txt"

mode=install link=false mod=false setup=false force=false compat=false elsewhere=""
for arg in "$@"; do
  case $arg in
    --link) link=true ;;
    --with-mod) mod=true ;;
    --force) force=true ;;
    --check) mode=check ;;
    --uninstall) mode=uninstall ;;
    --no-compat) mode=nocompat ;;
    --compat) compat=true ;;
    --with-setup) setup=true ;;
    -h | --help) sed -n '2,29s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option $arg (see --help)" >&2; exit 2 ;;
  esac
done

todo=0 formulas="" casks=""
ok() { printf '  ok    %s\n' "$*"; }
did() { printf '  done  %s\n' "$*"; }
note() { printf '  note  %s\n' "$*"; }
need() { printf '  TODO  %s\n' "$*"; todo=$((todo + 1)); }
head_() { printf '\n%s\n' "$*"; }

# A setting of the lib (JAY_ROOTS, JAY_REVIEW, ...) as the scripts see it: the environment, else
# ~/.config/jay/config, with the old WT_ names too.
setting() {
  HOME="$HOME" /bin/bash -c 'source "$1" && printf "%s" "${!2:-}"' _ "$repo/lib/jay-lib.sh" "$1"
}

# version_ge A B: version A is B or newer (numeric x.y.z).
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN { split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0 }'
}

# tool NAME MIN HOW: check a program on PATH (and mise's shims) and its version.
tool() {
  local name=$1 min=$2 how=$3 path version
  path=$(PATH="$HOME/.local/share/mise/shims:$PATH" command -v "$name" 2>/dev/null) || {
    need "$name not found: $how"
    # For one brew command at the end.
    case $how in
      "brew install --cask "*) how=${how#brew install --cask }; casks+=" ${how%% *}" ;;
      "brew install "*) how=${how#brew install }; formulas+=" ${how%% *}" ;;
    esac
    return 0
  }
  # A program that fails or prints no version (a broken shim) must not stop the script.
  version=$("$path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1) || true
  if [[ -z "$version" ]] && ! "$path" --version >/dev/null 2>&1; then
    need "$name ($path) does not run: $how"
  elif [[ -n "$min" && -n "$version" ]] && ! version_ge "$version" "$min"; then
    need "$name $version is older than $min: $how"
  else
    ok "$name ${version:-?}"
  fi
}

# The Claude Code features of the hub, from the help texts: background agents (--bg), attach,
# agents --json --all, rm, logs; respawn (a note when it is missing). Plugins (the mod) and hooks
# are older than these.
check_claude() {
  local path out missing=""
  path=$(PATH="$HOME/.local/share/mise/shims:$PATH" command -v claude 2>/dev/null) || return 0
  out=$("$path" --help 2>&1) || true
  [[ "$out" == *--bg* ]] || missing+=" --bg"
  out=$("$path" agents --help 2>&1) || true
  [[ "$out" == *--json* && "$out" == *--all* ]] || missing+=" 'agents --json --all'"
  for cmd in attach rm logs; do
    out=$("$path" "$cmd" --help 2>&1) || true
    [[ "$out" == *"claude $cmd"* ]] || missing+=" $cmd"
  done
  if [[ -n "$missing" ]]; then
    need "claude lacks what the hub needs:$missing (claude update)"
  else
    ok "claude has background agents (--bg, attach, agents --json --all, rm, logs)"
  fi
  # jay respawn and the list's auto step (JAY_AUTO_RESPAWN) need claude respawn.
  out=$("$path" respawn --help 2>&1) || true
  [[ "$out" == *"claude respawn"* ]] \
    || note "claude has no respawn (claude update): after an update, agents run the old Claude Code until they stop"
}

check_tools() {
  head_ "Tools"
  [[ "$(uname -s)" == Darwin ]] || need "macOS only (Ghostty AppleScript, lsappinfo, BSD tools)"
  tool zellij 0.45.1 "brew install zellij"
  # tmux: the other hub (JAY_MUX=tmux), on jay's own server and config. Optional for now.
  if [[ "$(setting JAY_MUX)" == tmux ]]; then
    tool tmux 3.5 "brew install tmux (the hub: JAY_MUX=tmux)"
  elif command -v tmux >/dev/null 2>&1; then
    note "tmux $(tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1): JAY_MUX=tmux jay starts the tmux hub (beside the zellij one); 3.5 or newer"
  else
    note "tmux: optional, for the tmux hub (JAY_MUX=tmux; brew install tmux)"
  fi
  tool wt 0.80.0 "brew install worktrunk"
  tool fzf 0.74.0 "brew install fzf"
  tool jq 1.7 "brew install jq"
  tool tuicr 0.27.0 "brew install tuicr"
  # lazygit is the other review (JAY_REVIEW=lazygit). 0.66 refreshes by itself on a new turn.
  # Its patch: jay-diff with delta, or difftastic (JAY_REVIEW_DIFF=difft).
  if [[ "$(setting JAY_REVIEW)" == lazygit ]]; then
    tool lazygit 0.66.0 "brew install lazygit (review: JAY_REVIEW=lazygit)"
    tool delta "" "brew install git-delta (the patch in lazygit review)"
    if [[ "$(setting JAY_REVIEW_DIFF)" == difft ]]; then
      tool difft "" "brew install difftastic (JAY_REVIEW_DIFF=difft)"
    else
      note "difftastic: optional, for JAY_REVIEW_DIFF=difft in $SETTINGS_FILE (brew install difftastic)"
    fi
  else
    note "lazygit: optional, for JAY_REVIEW=lazygit in $SETTINGS_FILE (0.66 or newer)"
  fi
  tool yazi 26.0 "brew install yazi"
  # The hub was built on Claude Code 2.1.304. It needs background agents and their commands.
  tool claude 2.1.304 "brew install --cask claude-code (an older one: claude update)"
  check_claude
  tool git "" "xcode-select --install"
  tool perl "" "part of macOS"
  tool curl "" "part of macOS"
  if [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c '' 2>/dev/null; then
    ok "python3 $(/usr/bin/python3 --version 2>&1 | cut -d' ' -f2) (/usr/bin/python3)"
  else
    need "/usr/bin/python3 not found (jay-keys and jay clear need it): xcode-select --install"
  fi
  if command -v terminal-notifier >/dev/null 2>&1; then
    ok "terminal-notifier (notices)"
  else
    note "terminal-notifier not found: no macOS notices (brew install terminal-notifier)"
  fi
  if [[ -d /Applications/Ghostty.app || -d "$HOME/Applications/Ghostty.app" ]]; then
    ok "Ghostty (tab control)"
  else
    note "Ghostty not found: the hub runs in any terminal, but without tab control (brew install --cask ghostty)"
  fi
  case ":$PATH:" in
    *":$BIN:"*) ok "$BIN is on PATH" ;;
    *) need "add $BIN to PATH in your shell profile" ;;
  esac
}

# --- From wt-hub (jay's old name) ---

# The paths of wt-hub and their jay places, under $HOME: the folders first.
OLD_PATHS=(
  .config/wt-hub:.config/jay
  .local/share/wt-hub:.local/share/jay
  .local/state/wt-hub:.local/state/jay
  .local/state/wt-turns:.local/state/jay/turns
  .local/state/hub-tasks:.local/state/jay/tasks
  .local/state/wt-hub-claude:.local/state/jay/hub-claude
  .local/state/wt-hub-review.mode:.local/state/jay/review.mode
  .local/state/wt-hub-review.hidden:.local/state/jay/review.hidden
  .local/state/wt-hub-sidebar.pct:.local/state/jay/sidebar.pct
  .local/state/wt-hub-sidebar.hide-idle:.local/state/jay/sidebar.hide-idle
  .local/state/wt-worktrees.ndjson:.local/state/jay/worktrees.ndjson
  .local/state/wt-hub-prune.stamp:.local/state/jay/prune.stamp
  .local/state/wt-hub-prune.log:.local/state/jay/prune.log
  .local/state/claude-notify.log:.local/state/jay/notify.log
  .local/state/wt-hub-layout.kdl:.local/state/jay/layout.kdl
  .local/state/wt-hub-agent.target:.local/state/jay/agent.target
  .local/state/wt-hub-review.target:.local/state/jay/review.target
  .local/state/wt-hub-files.target:.local/state/jay/files.target
  .local/state/wt-hub-agent.pane:.local/state/jay/agent.pane
  .local/state/wt-hub-review.pane:.local/state/jay/review.pane
  .local/state/wt-hub-files.pane:.local/state/jay/files.pane
)

# The hooks of wt-hub in settings.json: its scripts in ~/.local/bin, with any VAR=value before
# them. jay's hooks take their place.
OLD_HOOKS='/\.local/bin/(claude-notify|claude-turn-snapshot|hub-run --hook)$'

# move_old OLD NEW (under $HOME): a file or folder of wt-hub goes to its jay place, and a link to
# it stays at the old path, for a hub of the old version that still runs. When both exist, the
# entries of the old folder that the new one lacks move over; of two files, the new one stays.
moved=0
move_old() {
  local old="$HOME/$1" new="$HOME/$2" f
  [[ -L "$old" || ! -e "$old" ]] && return 0
  if [[ $mode == check ]]; then
    need "$old is from wt-hub (jay's old name): ./install.sh moves it to $new"
    return 0
  fi
  mkdir -p "$(dirname "$new")"
  if [[ ! -e "$new" && ! -L "$new" ]]; then
    mv "$old" "$new" || { need "could not move $old to $new"; return 0; }
  elif [[ -d "$old" && -d "$new" && ! -L "$new" ]]; then
    for f in "$old"/* "$old"/.[!.]*; do
      [[ -e "$f" || -L "$f" ]] || continue
      [[ -e "$new/${f##*/}" || -L "$new/${f##*/}" ]] || mv "$f" "$new/"
    done
    rmdir "$old" 2>/dev/null || { note "$old and $new both hold the same names: $old stays"; return 0; }
  else
    note "$new exists: $old stays (remove it when you do not need it)"
    return 0
  fi
  ln -s "$new" "$old"
  moved=$((moved + 1))
}

migrate() {
  local pair line found=false
  for pair in "${OLD_PATHS[@]}"; do
    [[ -e "$HOME/${pair%%:*}" && ! -L "$HOME/${pair%%:*}" ]] && found=true
  done
  $found || return 0
  head_ "From wt-hub (jay's old name)"
  for pair in "${OLD_PATHS[@]}"; do move_old "${pair%%:*}" "${pair#*:}"; done
  [[ $mode == check ]] && return 0
  # The list of installed files names the old folders: it follows them.
  if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r line; do
      case $line in
        "$HOME/.config/wt-hub/"*) line="$CONF/${line#"$HOME/.config/wt-hub/"}" ;;
        "$HOME/.local/share/wt-hub/"*) line="$SHARE/${line#"$HOME/.local/share/wt-hub/"}" ;;
      esac
      printf '%s\n' "$line"
    done <"$MANIFEST" >"$MANIFEST.new" && mv -f "$MANIFEST.new" "$MANIFEST"
  fi
  ((moved == 0)) || did "moved $moved files and folders of wt-hub to ~/.config/jay, ~/.local/share/jay and ~/.local/state/jay (a link stays at each old path)"
}

# Remove the links that move_old left at the old paths. Prints how many went.
remove_old_links() {
  local pair old n=0
  for pair in "${OLD_PATHS[@]}"; do
    old="$HOME/${pair%%:*}"
    if [[ -L "$old" && "$(readlink "$old")" == "$HOME/${pair#*:}" ]]; then rm -f "$old"; n=$((n + 1)); fi
  done
  printf '%s\n' "$n"
}

# --- Scripts and keys ---

# is_checkout DIR: DIR is a checkout of jay (or of wt-hub, its old name).
is_checkout() { [[ -f "$1/lib/jay-lib.sh" || -f "$1/lib/wt-lib.sh" ]]; }

# is_ours DEST: DEST was installed by this script (in the manifest), or is a link into a jay
# checkout (a --link install, from this repo or another copy of it). The link of an older
# install can point at a file that this checkout no longer has (bin/wt-new, say).
is_ours() {
  local dest=$1 target
  [[ -f "$MANIFEST" ]] && grep -qxF "$dest" "$MANIFEST" && return 0
  [[ -L "$dest" ]] || return 1
  target=$(readlink "$dest")
  # A relative link (jay-pick -> jay-all) is ours when its target is.
  [[ $target == /* ]] || { is_ours "$(dirname "$dest")/$target"; return; }
  case $target in
    */bin/* | */compat/* | */lib/*.sh) is_checkout "${target%/*}/.." ;;
    */config/yazi | */config/lazygit | */config/tuicr/config.toml | */config/tmux/jay.conf) is_checkout "${target%/config/*}" ;;
    */mod) is_checkout "${target%/mod}" ;;
    *) return 1 ;;
  esac
}

remember() {
  mkdir -p "$SHARE"
  touch "$MANIFEST"
  grep -qxF "$1" "$MANIFEST" || printf '%s\n' "$1" >>"$MANIFEST"
}

forget() {
  [[ -f "$MANIFEST" ]] || return 0
  grep -vxF "$1" "$MANIFEST" >"$MANIFEST.new" || true
  mv -f "$MANIFEST.new" "$MANIFEST"
}

# put SRC DEST: install SRC (file or folder) at DEST, as a link (--link) or a copy. A copy goes
# in under a new name and is then moved over DEST: a script that runs keeps its old file.
put() {
  local src=$1 dest=$2 tmp
  if [[ -e "$dest" || -L "$dest" ]] && ! is_ours "$dest"; then
    if ! $force; then
      need "$dest exists and is not from jay: remove it, or run again with --force"
      return 0
    fi
  fi
  if [[ $mode == check ]]; then
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      :
    elif [[ -L "$dest" && -e "$dest" ]]; then
      # A relative link (jay-pick -> jay-all) into this checkout is fine; a link into another
      # checkout of jay gets one note for all.
      tmp=$(readlink -f "$dest")
      tmp=${tmp%/bin/*}; tmp=${tmp%/compat/*}; tmp=${tmp%/lib/*}; tmp=${tmp%/config/*}
      [[ "$tmp" == "$repo" ]] || elsewhere=$tmp
    elif [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
      :
    elif [[ -d "$dest" && ! -L "$dest" ]] && diff -rq "$src" "$dest" >/dev/null 2>&1; then
      :
    else
      need "$dest is missing, out of date or from another checkout: run ./install.sh (or --link)"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if $link; then
    [[ -d "$dest" && ! -L "$dest" ]] && rm -rf "$dest"
    ln -sfn "$src" "$dest"
  else
    tmp="$dest.jay-new"
    rm -rf "$tmp"
    cp -R -L "$src" "$tmp"
    # mv onto a link to a folder would move into that folder: remove the link first.
    [[ -L "$dest" || -d "$dest" ]] && rm -rf "$dest"
    mv -f "$tmp" "$dest"
  fi
  remember "$dest"
}

install_files() {
  if [[ $mode == check ]]; then head_ "Scripts and keys"
  else head_ "Scripts and keys ($($link && echo links into "$repo" || echo copies))"; fi
  local f before shims=""
  before=$todo
  for f in "$repo"/bin/*; do
    [[ -f "$f" ]] || continue
    put "$f" "$BIN/${f##*/}"
  done
  # The lib and its mux backends (jay-mux-<name>.sh).
  for f in "$repo"/lib/jay-*.sh; do put "$f" "$LIB/${f##*/}"; done
  # The old names (wt-hub's) run the new commands, unless --no-compat took them away.
  if [[ ! -f "$NOCOMPAT" ]]; then
    for f in "$repo"/compat/*; do put "$f" "$BIN/${f##*/}"; done
    put "$repo/lib/wt-lib.sh" "$LIB/wt-lib.sh"
    shims=", the shims of the old names (compat/)"
  fi
  put "$repo/config/yazi" "$CONF/yazi"
  put "$repo/config/lazygit" "$CONF/lazygit"
  put "$repo/config/tmux/jay.conf" "$CONF/tmux.conf"
  ((todo > before)) && return 0
  f="$(ls "$repo"/bin | wc -l | tr -d ' ') scripts in $BIN, jay-lib.sh in $LIB$shims, yazi keys, lazygit settings and the tmux hub's config in ~/.config/jay"
  if [[ $mode != check ]]; then
    did "$f"
  elif [[ -n "$elsewhere" ]]; then
    ok "$f, links into $elsewhere"
    note "that is another checkout: ./install.sh --link here moves the links to $repo"
  else
    ok "$f"
  fi
  [[ -f "$NOCOMPAT" ]] && note "no shims of the old names (--no-compat; ./install.sh --compat puts them back)"
  return 0
}

install_tuicr() {
  local dest="$HOME/.config/tuicr/config.toml"
  local before=$todo
  if [[ -L "$dest" ]] && is_ours "$dest" || { [[ -f "$MANIFEST" ]] && grep -qxF "$dest" "$MANIFEST"; }; then
    put "$repo/config/tuicr/config.toml" "$dest"
    ((todo > before)) || ok "$dest (from jay)"
  elif [[ -f "$dest" ]]; then
    if grep -qE '^[[:space:]]*q_quits[[:space:]]*=[[:space:]]*true' "$dest"; then
      ok "$dest has q_quits = true"
    else
      need "add q_quits = true at the top of $dest (q in review goes back)"
    fi
  else
    put "$repo/config/tuicr/config.toml" "$dest"
    [[ $mode == check ]] || did "$dest"
  fi
}

install_worktrunk() {
  local dest="$HOME/.config/worktrunk/config.toml"
  if [[ ! -e "$dest" ]]; then
    if [[ $mode == check ]]; then
      need "$dest is missing: run ./install.sh"
    else
      mkdir -p "$(dirname "$dest")"
      # --with-setup: the pre-start hook goes under worktree-path (a top-level key, before
      # the first table).
      awk -v setup="$setup" '{ print } setup == "true" && /^worktree-path/ { print ""; print "pre-start = \"jay-setup\"" }' \
        "$repo/config/worktrunk/config.toml" >"$dest"
      did "$dest (a copy: add your own settings there)$($setup && echo ', with jay-setup')"
    fi
    return 0
  fi
  local missing=()
  grep -qF '[list.custom-columns.Task]' "$dest" || missing+=('[list.custom-columns.Task]')
  grep -qE '^[[:space:]]*task[[:space:]]*=' "$dest" || missing+=('the task alias')
  grep -qF '{{ repo }}.{{ branch' "$dest" || missing+=('worktree-path <repo>.<branch>')
  if ((${#missing[@]} == 0)); then
    ok "$dest has the hub's settings"
  else
    need "merge into $dest from config/worktrunk/config.toml: ${missing[*]}"
  fi
  if grep -qE '^[[:space:]]*pre-start[[:space:]]*=.*jay-setup' "$dest"; then
    ok "jay-setup runs in each new worktree (pre-start)"
  elif grep -qE '^[[:space:]]*pre-start[[:space:]]*=.*wt-setup' "$dest"; then
    ok "wt-setup runs in each new worktree (pre-start; a shim of jay-setup)"
    note "change pre-start = \"wt-setup\" to \"jay-setup\" in $dest (wt-setup is the old name)"
  elif $setup; then
    need "add pre-start = \"jay-setup\" near the top of $dest (before the first [table])"
  else
    note "jay-setup is off (optional: ./install.sh --with-setup)"
  fi
}

# ~/.config/jay/config: made with comments when missing. Then the list's folders must exist.
install_settings() {
  local roots dir dirs=() missing=""
  if [[ ! -e "$SETTINGS_FILE" ]]; then
    if [[ $mode == check ]]; then
      note "$SETTINGS_FILE is missing: the defaults apply (./install.sh makes it)"
    else
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      cat >"$SETTINGS_FILE" <<'CONF'
# jay settings: KEY=value lines. An environment variable of the same name wins. The names of
# wt-hub (jay's old name: WT_ROOTS and so on) still work.

# The folders with your repos, ':' between them (default: ~/Documents/projects).
# The list shows each repo 1-2 levels under them: <root>/<client>/<repo> or <root>/<repo>.
# JAY_ROOTS=~/Documents/projects

# Your editor for O in files and jay edit (default: $VISUAL, else $EDITOR, else nvim).
# JAY_EDITOR=nvim

# Tab control: ghostty (on) or none (off). Default: on when Ghostty runs.
# JAY_TERMINAL=ghostty

# How a task (jay run) runs its command line, which comes after these words. Default for zsh
# and bash: $SHELL -i +m -c (your rc file and aliases, no job control); else $SHELL -l -c.
# JAY_TASK_SHELL=/bin/zsh -i +m -c

# The launcher (Ctrl g r) for a shell other than zsh: a command that runs in the launcher pane,
# in the worktree, and starts what you type with: jay-run --launch -- "<line>". See docs/tasks.md.
# JAY_LAUNCHER=bash --rcfile ~/.config/jay/launcher.bash -i

# The review pane: tuicr (default; review comments) or lazygit (0.66 or newer; git actions).
# JAY_REVIEW=tuicr

# The patch in lazygit review: delta (default: one number column, file and hunk places, wrap
# under the code), difft (difftastic: a diff of the syntax) or plain (delta, no wrap: H and L).
# | in lazygit goes to the next one.
# JAY_REVIEW_DIFF=delta

# After a Claude Code update: idle (default) — the list moves each agent that still runs the old
# binary onto the new one at a quiet moment (claude respawn); off — only jay respawn does.
# JAY_AUTO_RESPAWN=idle

# The hub's multiplexer: zellij (default) or tmux (jay's own tmux server, beside a zellij hub;
# tmux 3.5 or newer). JAY_MUX=tmux jay tries it without this line.
# JAY_MUX=zellij

# The repos that always get an orchestrator, ':' between them: a repo's name as the list shows
# it (shop), or client/repo (acme/shop). When such a repo has none, a pick of one of its rows
# starts one. Default: none (the hub Claude plans and starts workers; n starts an orchestrator).
# JAY_ORCHESTRATE=shop:acme/web
CONF
      did "$SETTINGS_FILE (settings, all at their defaults)"
    fi
  else
    ok "$SETTINGS_FILE"
    grep -qE '^[[:space:]]*WT_[A-Z_]+[[:space:]]*=' "$SETTINGS_FILE" \
      && note "$SETTINGS_FILE uses WT_ names (wt-hub's): they work; JAY_ is the new name"
  fi
  roots=$(setting JAY_ROOTS)
  IFS=: read -ra dirs <<<"$roots"
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    [[ -d "$dir" ]] || missing+=" $dir"
  done
  if [[ -n "$missing" ]]; then
    need "the list's folders do not exist:$missing; set JAY_ROOTS in $SETTINGS_FILE"
  else
    ok "the list shows the repos under ${roots//:/, }"
  fi
}

# The hub's hooks from config/claude-settings-hooks.json that settings.json does not have yet
# (by event and command: one command can be the hook of several events). The hooks of wt-hub
# (OLD_HOOKS) go first; an event or group that they leave empty goes too. Prints the merged
# settings.
merged_settings() {
  jq --slurpfile ours "$repo/config/claude-settings-hooks.json" --arg old "$OLD_HOOKS" '
    def drop_old: if (.hooks | type) == "array" and (.hooks | length) > 0
      then .hooks |= map(select((.command // "") | test($old) | not)) | select(.hooks | length > 0)
      else . end;
    (if (.hooks | type) == "object" then .hooks |= (to_entries | map(
        if (.value | type) == "array" and (.value | length) > 0
        then (.value |= map(drop_old)) | select(.value | length > 0) else . end) | from_entries)
     else . end)
    | reduce ($ours[0].hooks | to_entries[]) as $e (.;
        ([.hooks[$e.key] // [] | .[]? | .hooks[]? | .command]) as $have
        | .hooks[$e.key] = ((.hooks[$e.key] // []) + [ $e.value[]
          | .hooks |= map(select(.command as $c | $have | index([$c]) | not))
          | select(.hooks | length > 0) ]))' "$1"
}

install_hooks() {
  local target=$SETTINGS current merged backup old
  [[ -L "$target" ]] && target=$(readlink -f "$target")
  if [[ -f "$target" ]]; then current=$(jq -S . "$target") || { need "$SETTINGS is not valid JSON: add the hooks of config/claude-settings-hooks.json by hand"; return 0; }
  else current='{}'; fi
  merged=$(merged_settings <(printf '%s\n' "$current") | jq -S .)
  if [[ "$merged" == "$current" ]]; then
    ok "$SETTINGS has the hub's hooks (SessionStart, Stop, UserPromptSubmit, PreToolUse, PostToolUse, Notification)"
    return 0
  fi
  old=$(jq --arg old "$OLD_HOOKS" '[.hooks[]?[]?.hooks[]?.command // empty | select(test($old))] | length' <<<"$current")
  if [[ $mode == check ]]; then
    if ((old > 0)); then need "$SETTINGS has the hooks of wt-hub (jay's old name): ./install.sh puts jay's in their place"
    else need "$SETTINGS lacks some of the hub's hooks: run ./install.sh"; fi
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    backup="$target.jay-backup.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$backup"
    merged_settings "$target" >"$target.jay-new"
  else
    merged_settings <(echo '{}') >"$target.jay-new"
  fi
  mv -f "$target.jay-new" "$target"
  if ((old > 0)); then did "hooks of wt-hub replaced by jay's in $SETTINGS${backup:+ (backup: $backup)}"
  else did "hooks added to $SETTINGS${backup:+ (backup: $backup)}"; fi
}

install_zjstatus() {
  if [[ -f "$ZJSTATUS" ]] && [[ "$(shasum -a 256 "$ZJSTATUS" | cut -d' ' -f1)" == "$ZJSTATUS_SHA" ]]; then
    ok "zjstatus v0.25.0 (the bar)"
    return 0
  fi
  if [[ $mode == check ]]; then
    need "zjstatus is missing (the hub uses zellij's compact bar): run ./install.sh"
    return 0
  fi
  mkdir -p "$SHARE"
  if curl -fsSL -o "$ZJSTATUS.part" "$ZJSTATUS_URL" \
    && [[ "$(shasum -a 256 "$ZJSTATUS.part" | cut -d' ' -f1)" == "$ZJSTATUS_SHA" ]]; then
    mv -f "$ZJSTATUS.part" "$ZJSTATUS"
    did "zjstatus v0.25.0; at the first hub start, click the bar and press y (its permissions)"
  else
    rm -f "$ZJSTATUS.part"
    need "zjstatus download failed or its sha256 differs: the hub uses zellij's compact bar"
  fi
}

# --- The mod ---

# The mod's marketplaces as `claude plugin marketplace list` names them: jay, or wt-hub and
# alex-wt-hub (wt-hub was jay's name; Claude keeps the name a marketplace had when it was added).
# Prints name<TAB>folder lines.
mod_marketplaces() {
  claude plugin marketplace list 2>/dev/null | awk '
    $1 == "❯" { name = ($2 == "jay" || $2 == "wt-hub" || $2 == "alex-wt-hub") ? $2 : ""; next }
    name != "" && /Source:/ { sub(/^.*Source: /, ""); sub(/^Folder \(/, ""); sub(/\)$/, "")
      printf "%s\t%s\n", name, $0; name = "" }' || true
}

add_mod() {
  claude plugin marketplace add "$1" >/dev/null 2>&1 && claude plugin install jay@jay >/dev/null 2>&1 \
    && did "mod jay@jay (from $1)" \
    || need "mod: claude plugin marketplace add $1 && claude plugin install jay@jay"
}

# The mod: with --with-mod, or when the mod of wt-hub is installed. That one fails to load after
# the rename ("Plugin wt-hub not found in marketplace ..."): it goes, and jay's comes from the
# same folder when that folder holds jay's mod now (this repo's mod/, say), else from a copy.
install_mod() {
  local name where old="" oldwhere="" new=""
  while IFS=$'\t' read -r name where; do
    case $name in
      jay) new=$where ;;
      *) old=$name oldwhere=$where ;;
    esac
  done < <(mod_marketplaces)
  if [[ -n "$old" ]]; then
    if [[ $mode == check ]]; then
      need "the mod is wt-hub's (marketplace $old), which no longer loads: ./install.sh puts jay's in its place"
      return 0
    fi
    claude plugin uninstall "wt-hub@$old" >/dev/null 2>&1 || true
    if ! claude plugin marketplace remove "$old" >/dev/null 2>&1; then
      need "mod: claude plugin uninstall wt-hub@$old && claude plugin marketplace remove $old, then ./install.sh --with-mod"
      return 0
    fi
    did "removed the mod of wt-hub (marketplace $old)"
    if [[ -n "$new" ]]; then
      ok "mod: marketplace jay is there ($new)"
    elif [[ -n "$oldwhere" && "$(jq -r '.name // ""' "$oldwhere/.claude-plugin/marketplace.json" 2>/dev/null)" == jay ]]; then
      add_mod "$oldwhere"
    else
      put "$repo/mod" "$SHARE/mod"
      add_mod "$SHARE/mod"
    fi
    return 0
  fi
  if [[ -n "$new" ]]; then
    ok "mod: marketplace jay is there ($new)"
  elif [[ $mode == check ]]; then
    note "the mod (/jay) is not installed (optional: ./install.sh --with-mod)"
  elif $mod; then
    put "$repo/mod" "$SHARE/mod"
    add_mod "$SHARE/mod"
  fi
}

check_zellij() {
  head_ "zellij keys (optional, in ~/.config/zellij/config.kdl; this script never edits it)"
  local conf="$HOME/.config/zellij/config.kdl"
  if [[ -f "$conf" ]] && grep -qF 'MoveFocus "left"; MoveFocus "left"; MoveFocus "right"' "$conf" \
    && grep -qF 'jay-run" "--switch"' "$conf" && grep -qF 'jay-run" "--launcher"' "$conf" \
    && grep -qF 'jay-sidebar" "--review" "toggle"' "$conf" && grep -qF 'jay-sidebar" "--review" "show"' "$conf" \
    && grep -qF 'jay-run" "--pick"' "$conf"; then
    ok "pane keys (Ctrl g, then 1 2 3 h l ; v Tab r t)"
    return 0
  fi
  if [[ -f "$conf" ]] && grep -qE '(hub-run|wt-sidebar)" "--' "$conf"; then
    note "your pane keys call hub-run and wt-sidebar, wt-hub's names: the shims keep them working."
    note "change them to jay-run and jay-sidebar (as below) before ./install.sh --no-compat."
  fi
  note "for the pane keys, add these binds to the normal block of keybinds (Tab: a worktree's"
  note "tasks tab and back, through a pane of 1 cell that closes at once; zellij has no key action"
  note "for a tab by name. v: hide or show review, and 3 shows a hidden one, the same way."
  note "r: the launcher, a floating prompt that starts a task. t: all tasks in a picker):"
  cat <<KDL
          normal {
              bind "h" { MoveFocus "left"; SwitchToMode "locked"; }
              bind "l" { MoveFocus "right"; SwitchToMode "locked"; }
              bind "1" { MoveFocus "left"; MoveFocus "left"; SwitchToMode "locked"; }
              bind "2" { MoveFocus "left"; MoveFocus "left"; MoveFocus "right"; SwitchToMode "locked"; }
              bind "3" { MoveFocus "right"; MoveFocus "right"; Run "$BIN/jay-sidebar" "--review" "show" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind ";" { FocusLastPane; SwitchToMode "locked"; }
              bind "v" { Run "$BIN/jay-sidebar" "--review" "toggle" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind "Tab" { Run "$BIN/jay-run" "--switch" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind "r" { Run "$BIN/jay-run" "--launcher" { floating true; close_on_exit true; x "20%"; y "35%"; width "60%"; height "3"; }; SwitchToMode "locked"; }
              bind "t" { Run "$BIN/jay-run" "--pick" { floating true; close_on_exit true; x "10%"; y "15%"; width "80%"; height "60%"; }; SwitchToMode "locked"; }
          }
KDL
  note "the tmux hub (JAY_MUX=tmux) has these keys already, in ~/.config/jay/tmux.conf"
  note "the hub expects default_mode \"locked\", with Ctrl g to normal mode and Ctrl q to quit"
}

# The hub of wt-hub runs: the zellij session "hub" (jay's is "jay"). zellij also lists exited
# sessions that it keeps to resurrect ("hub [Created …] (EXITED - attach to resurrect)"); they
# do not count. A name can have spaces: it ends before " [Created".
old_hub_runs() {
  perl -e 'alarm 5; exec @ARGV or exit 127' zellij list-sessions --no-formatting 2>/dev/null \
    | grep -v '(EXITED' | sed 's/ \[Created .*$//' | grep -qxF hub
}

# --no-compat: the shims and the links at the old paths go, once nothing of the user's calls the
# old names; later installs leave them out.
no_compat() {
  head_ "Shims of the old names (wt-hub)"
  local f dest n=0 links
  if [[ -f "$SETTINGS" ]] && jq -e --arg old "$OLD_HOOKS" \
    '[.hooks[]?[]?.hooks[]?.command // empty | select(test($old))] | length > 0' "$SETTINGS" >/dev/null 2>&1; then
    need "$SETTINGS still has the hooks of wt-hub: run ./install.sh first"
  fi
  if grep -qE '^[[:space:]]*pre-start[[:space:]]*=.*wt-setup' "$HOME/.config/worktrunk/config.toml" 2>/dev/null; then
    need "pre-start in ~/.config/worktrunk/config.toml runs wt-setup: change it to jay-setup first"
  fi
  if grep -qE '(hub-run|wt-sidebar)" "--' "$HOME/.config/zellij/config.kdl" 2>/dev/null; then
    need "the pane keys in ~/.config/zellij/config.kdl call hub-run or wt-sidebar: change them to jay-run and jay-sidebar first"
  fi
  if ((todo > 0)); then
    echo "  Nothing removed."
    return 0
  fi
  for f in "$repo"/compat/* "$repo/lib/wt-lib.sh"; do
    [[ $f == */lib/* ]] && dest="$LIB/wt-lib.sh" || dest="$BIN/${f##*/}"
    if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then
      rm -f "$dest"
      forget "$dest"
      n=$((n + 1))
    fi
  done
  links=$(remove_old_links)
  mkdir -p "$SHARE"
  : >"$NOCOMPAT"
  did "removed $n shims and $links links at old paths; later installs leave them out (--compat puts them back)"
}

uninstall() {
  head_ "Uninstall"
  local f dest n=0 name where
  for f in "$repo"/bin/* "$repo"/compat/* "$repo"/lib/jay-*.sh "$repo/lib/wt-lib.sh"; do
    [[ $f == */lib/* ]] && dest="$LIB/${f##*/}" || dest="$BIN/${f##*/}"
    if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -f "$dest"; n=$((n + 1)); fi
  done
  did "removed $n scripts and shims from $BIN and $LIB"
  for dest in "$CONF/yazi" "$CONF/lazygit" "$CONF/tmux.conf"; do
    if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -rf "$dest"; did "removed $dest"; fi
  done
  dest="$HOME/.config/tuicr/config.toml"
  if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -f "$dest"; did "removed $dest"; fi
  while IFS=$'\t' read -r name where; do
    if [[ $name == jay ]]; then
      need "the mod: claude plugin uninstall jay@jay && claude plugin marketplace remove jay"
    else
      need "the mod: claude plugin uninstall wt-hub@$name && claude plugin marketplace remove $name"
    fi
  done < <(mod_marketplaces)
  rm -rf "$SHARE" && did "removed $SHARE (zjstatus, mod copy, list of installed files)"
  n=$(remove_old_links)
  ((n == 0)) || did "removed $n links at the old paths of wt-hub"
  need "remove the hub's hooks (jay-notify, jay-snapshot, jay-guard, jay-run --hook; wt-hub's were claude-notify, claude-turn-snapshot, hub-run --hook) from $SETTINGS"
  note "kept: ~/.config/jay/config and ~/.config/worktrunk/config.toml (your settings), ~/.local/state/jay (hub state and logs)"
}

if [[ $mode == uninstall ]]; then
  migrate
  uninstall
  exit 0
fi
if [[ $mode == nocompat ]]; then
  no_compat
  exit 0
fi

$compat && rm -f "$NOCOMPAT"
check_tools
migrate
install_files
head_ "Configs"
install_settings
install_tuicr
install_worktrunk
install_hooks
install_zjstatus
install_mod
check_zellij

head_ "Result"
start="start the hub with: jay"
if old_hub_runs; then
  start="quit the hub of wt-hub (zellij session hub: Ctrl g, then Ctrl q; the agents keep running), then start the hub with: jay"
fi
if ((todo == 0)); then
  echo "  Ready: $start"
else
  echo "  $todo TODO item(s) above. Then $start"
  if [[ -n "$formulas$casks" ]]; then
    echo "  The missing tools in one go:"
    [[ -z "$formulas" ]] || echo "    brew install$formulas"
    [[ -z "$casks" ]] || echo "    brew install --cask$casks"
  fi
fi
