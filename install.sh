#!/bin/bash
# install.sh [--link] [--with-mod] [--with-setup] [--force] | --check | --uninstall
# Install wt-hub for this user (macOS). It runs again safely: run it again after a git pull.
#   ~/.local/bin/<each script in bin/>, ~/.local/lib/wt-lib.sh
#                                    copies; --link: symlinks into this repo, so an edit is live
#                                    at once (for work on wt-hub itself)
#   ~/.config/wt-hub/config          your settings (WT_ROOTS, ...), made when missing
#   ~/.config/wt-hub/yazi            the hub's yazi keys
#   ~/.config/tuicr/config.toml      made when missing (q_quits = true); else only checked
#   ~/.config/worktrunk/config.toml  copied when missing (always a copy: client settings go
#                                    there); else the hub's keys it lacks are listed
#   ~/.claude/settings.json          the hub's hooks, only the missing ones (a backup first)
#   ~/.local/share/wt-hub/           zjstatus v0.25.0 for the bar (sha256 checked)
#   --with-mod                       also the Claude Code mod (/wt), marketplace alex-wt-hub
#   --with-setup                     also worktrunk's pre-start = "wt-setup": in each new
#                                    worktree, copy ignored files and install dependencies
# It never changes a file it did not install (--force: replace it), and it never edits
# ~/.config/zellij/config.kdl: it prints the pane keys to add there.
# --check: report the tools and the install, change nothing.
# --uninstall: remove what it installed; list the config entries to remove by hand.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd -P)
BIN="$HOME/.local/bin" LIB="$HOME/.local/lib" SHARE="$HOME/.local/share/wt-hub"
MANIFEST="$SHARE/installed.txt"
ZJSTATUS="$SHARE/zjstatus-v0.25.0.wasm"
ZJSTATUS_URL=https://github.com/dj95/zjstatus/releases/download/v0.25.0/zjstatus.wasm
ZJSTATUS_SHA=282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
SETTINGS="$HOME/.claude/settings.json"
SETTINGS_FILE="$HOME/.config/wt-hub/config"

mode=install link=false mod=false setup=false force=false elsewhere=""
for arg in "$@"; do
  case $arg in
    --link) link=true ;;
    --with-mod) mod=true ;;
    --force) force=true ;;
    --check) mode=check ;;
    --uninstall) mode=uninstall ;;
    --with-setup) setup=true ;;
    -h | --help) sed -n '2,20s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option $arg (see --help)" >&2; exit 2 ;;
  esac
done

todo=0
ok() { printf '  ok    %s\n' "$*"; }
did() { printf '  done  %s\n' "$*"; }
note() { printf '  note  %s\n' "$*"; }
need() { printf '  TODO  %s\n' "$*"; todo=$((todo + 1)); }
head_() { printf '\n%s\n' "$*"; }

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
    return 0
  }
  version=$("$path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  if [[ -n "$min" && -n "$version" ]] && ! version_ge "$version" "$min"; then
    need "$name $version is older than $min: $how"
  else
    ok "$name ${version:-?}"
  fi
}

check_tools() {
  head_ "Tools"
  [[ "$(uname -s)" == Darwin ]] || need "macOS only (Ghostty AppleScript, lsappinfo, BSD tools)"
  tool zellij 0.45.1 "brew install zellij"
  tool wt 0.80.0 "brew install worktrunk"
  tool fzf 0.74.0 "brew install fzf"
  tool jq 1.7 "brew install jq"
  tool tuicr 0.27.0 "brew install tuicr"
  tool yazi 26.0 "brew install yazi"
  tool claude "" "brew install --cask claude-code"
  tool git "" "xcode-select --install"
  tool perl "" "part of macOS"
  tool curl "" "part of macOS"
  if [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c '' 2>/dev/null; then
    ok "python3 $(/usr/bin/python3 --version 2>&1 | cut -d' ' -f2) (/usr/bin/python3)"
  else
    need "/usr/bin/python3 not found (wt-hub-keys needs it): xcode-select --install"
  fi
  if command -v terminal-notifier >/dev/null 2>&1; then
    ok "terminal-notifier (notices)"
  else
    note "terminal-notifier not found: no macOS notices (brew install terminal-notifier)"
  fi
  if [[ -d /Applications/Ghostty.app ]]; then
    ok "Ghostty (tab control)"
  else
    note "Ghostty not found: the hub runs in any terminal, but without tab control (brew install --cask ghostty)"
  fi
  case ":$PATH:" in
    *":$BIN:"*) ok "$BIN is on PATH" ;;
    *) need "add $BIN to PATH in your shell profile" ;;
  esac
}

# is_ours DEST: DEST was installed by this script (in the manifest), or is a link into a wt-hub
# checkout (a --link install, from this repo or another copy of it).
is_ours() {
  local dest=$1 target
  [[ -f "$MANIFEST" ]] && grep -qxF "$dest" "$MANIFEST" && return 0
  [[ -L "$dest" ]] || return 1
  target=$(readlink "$dest")
  # A relative link (wt-pick -> wt-all) is ours when its target is.
  [[ $target == /* ]] || { is_ours "$(dirname "$dest")/$target"; return; }
  case $target in
    */bin/* | */lib/wt-lib.sh) [[ -f "${target%/*}/../lib/wt-lib.sh" ]] ;;
    */config/yazi | */config/tuicr/config.toml | */mod) [[ -f "${target%/config/*}/lib/wt-lib.sh" || -f "${target%/mod}/lib/wt-lib.sh" ]] ;;
    *) return 1 ;;
  esac
}

remember() {
  mkdir -p "$SHARE"
  touch "$MANIFEST"
  grep -qxF "$1" "$MANIFEST" || printf '%s\n' "$1" >>"$MANIFEST"
}

# put SRC DEST: install SRC (file or folder) at DEST, as a link (--link) or a copy. A copy goes
# in under a new name and is then moved over DEST: a script that runs keeps its old file.
put() {
  local src=$1 dest=$2 tmp
  if [[ -e "$dest" || -L "$dest" ]] && ! is_ours "$dest"; then
    if ! $force; then
      need "$dest exists and is not from wt-hub: remove it, or run again with --force"
      return 0
    fi
  fi
  if [[ $mode == check ]]; then
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      :
    elif [[ -L "$dest" ]]; then
      # A relative link (wt-pick -> wt-all) into this checkout is fine; a link into another
      # checkout of wt-hub gets one note for all.
      tmp=$(readlink -f "$dest")
      tmp=${tmp%/bin/*}; tmp=${tmp%/lib/*}; tmp=${tmp%/config/*}
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
    tmp="$dest.wt-hub-new"
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
  local f before
  before=$todo
  for f in "$repo"/bin/*; do
    [[ -f "$f" ]] || continue
    put "$f" "$BIN/${f##*/}"
  done
  put "$repo/lib/wt-lib.sh" "$LIB/wt-lib.sh"
  put "$repo/config/yazi" "$HOME/.config/wt-hub/yazi"
  ((todo > before)) && return 0
  f="$(ls "$repo"/bin | wc -l | tr -d ' ') scripts in $BIN, wt-lib.sh in $LIB, yazi keys in ~/.config/wt-hub/yazi"
  if [[ $mode != check ]]; then
    did "$f"
  elif [[ -n "$elsewhere" ]]; then
    ok "$f, links into $elsewhere"
    note "that is another checkout: ./install.sh --link here moves the links to $repo"
  else
    ok "$f"
  fi
}

install_tuicr() {
  local dest="$HOME/.config/tuicr/config.toml"
  local before=$todo
  if [[ -L "$dest" ]] && is_ours "$dest" || { [[ -f "$MANIFEST" ]] && grep -qxF "$dest" "$MANIFEST"; }; then
    put "$repo/config/tuicr/config.toml" "$dest"
    ((todo > before)) || ok "$dest (from wt-hub)"
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
      awk -v setup="$setup" '{ print } setup == "true" && /^worktree-path/ { print ""; print "pre-start = \"wt-setup\"" }' \
        "$repo/config/worktrunk/config.toml" >"$dest"
      did "$dest (a copy: add your own settings there)$($setup && echo ', with wt-setup')"
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
  if grep -qE '^[[:space:]]*pre-start[[:space:]]*=.*wt-setup' "$dest"; then
    ok "wt-setup runs in each new worktree (pre-start)"
  elif $setup; then
    need "add pre-start = \"wt-setup\" near the top of $dest (before the first [table])"
  else
    note "wt-setup is off (optional: ./install.sh --with-setup)"
  fi
}

# ~/.config/wt-hub/config: made with comments when missing. Then the list's folders must exist.
install_settings() {
  local roots dir dirs=() missing=""
  if [[ ! -e "$SETTINGS_FILE" ]]; then
    if [[ $mode == check ]]; then
      note "$SETTINGS_FILE is missing: the defaults apply (./install.sh makes it)"
    else
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      cat >"$SETTINGS_FILE" <<'CONF'
# wt-hub settings: KEY=value lines. An environment variable of the same name wins.

# The folders with your repos, ':' between them (default: ~/Documents/projects).
# The list shows each repo 1-2 levels under them: <root>/<client>/<repo> or <root>/<repo>.
# WT_ROOTS=~/Documents/projects

# Your editor for O in files and wt-edit (default: $VISUAL, else $EDITOR, else nvim).
# WT_EDITOR=nvim

# Tab control: ghostty (on) or none (off). Default: on when Ghostty runs.
# WT_TERMINAL=ghostty

# How a task (hub-run) runs its command line, which comes after these words. Default for zsh
# and bash: $SHELL -i +m -c (your rc file and aliases, no job control); else $SHELL -l -c.
# WT_TASK_SHELL=/bin/zsh -i +m -c

# The launcher (Ctrl g r) for a shell other than zsh: a command that runs in the launcher pane,
# in the worktree, and starts what you type with: hub-run --launch -- "<line>". See the README.
# WT_LAUNCHER=bash --rcfile ~/.config/wt-hub/launcher.bash -i
CONF
      did "$SETTINGS_FILE (settings, all at their defaults)"
    fi
  else
    ok "$SETTINGS_FILE"
  fi
  roots=$(HOME="$HOME" /bin/bash -c 'source "$1" && printf "%s" "$WT_ROOTS"' _ "$repo/lib/wt-lib.sh")
  IFS=: read -ra dirs <<<"$roots"
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    [[ -d "$dir" ]] || missing+=" $dir"
  done
  if [[ -n "$missing" ]]; then
    need "the list's folders do not exist:$missing; set WT_ROOTS in $SETTINGS_FILE"
  else
    ok "the list shows the repos under ${roots//:/, }"
  fi
}

# The hub's hooks from config/claude-settings-hooks.json that settings.json does not have yet
# (by command). Prints the merged settings.
merged_settings() {
  jq --slurpfile ours "$repo/config/claude-settings-hooks.json" '
    ([.hooks // {} | .[] | .[]? | .hooks[]? | .command]) as $have
    | reduce ($ours[0].hooks | to_entries[]) as $e (.;
        .hooks[$e.key] = ((.hooks[$e.key] // []) + [ $e.value[]
          | .hooks |= map(select(.command as $c | $have | index([$c]) | not))
          | select(.hooks | length > 0) ]))' "$1"
}

install_hooks() {
  local target=$SETTINGS current merged backup
  [[ -L "$target" ]] && target=$(readlink -f "$target")
  if [[ -f "$target" ]]; then current=$(jq -S . "$target") || { need "$SETTINGS is not valid JSON: add the hooks of config/claude-settings-hooks.json by hand"; return 0; }
  else current='{}'; fi
  merged=$(merged_settings <(printf '%s\n' "$current") | jq -S .)
  if [[ "$merged" == "$current" ]]; then
    ok "$SETTINGS has the hub's hooks (SessionStart, Stop, UserPromptSubmit, Notification)"
    return 0
  fi
  if [[ $mode == check ]]; then
    need "$SETTINGS lacks some of the hub's hooks: run ./install.sh"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]]; then
    backup="$target.wt-hub-backup.$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$backup"
    merged_settings "$target" >"$target.wt-hub-new"
  else
    merged_settings <(echo '{}') >"$target.wt-hub-new"
  fi
  mv -f "$target.wt-hub-new" "$target"
  did "hooks added to $SETTINGS${backup:+ (backup: $backup)}"
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

install_mod() {
  local where
  where=$(claude plugin marketplace list 2>/dev/null | awk '/alex-wt-hub/ { f = 1; next } f && /Source:/ { print; exit }')
  if [[ -n "$where" ]]; then
    ok "mod: marketplace alex-wt-hub is there (${where#*Source: })"
    return 0
  fi
  if [[ $mode == check ]]; then
    note "the mod (/wt) is not installed (optional: ./install.sh --with-mod)"
    return 0
  fi
  put "$repo/mod" "$SHARE/mod"
  claude plugin marketplace add "$SHARE/mod" >/dev/null && claude plugin install wt-hub@alex-wt-hub >/dev/null \
    && did "mod wt-hub@alex-wt-hub (from $SHARE/mod)" \
    || need "mod: claude plugin marketplace add $SHARE/mod && claude plugin install wt-hub@alex-wt-hub"
}

check_zellij() {
  head_ "zellij keys (optional, in ~/.config/zellij/config.kdl; this script never edits it)"
  local conf="$HOME/.config/zellij/config.kdl"
  if [[ -f "$conf" ]] && grep -qF 'MoveFocus "left"; MoveFocus "left"; MoveFocus "right"' "$conf" \
    && grep -qF 'hub-run" "--switch"' "$conf" && grep -qF 'hub-run" "--launcher"' "$conf" \
    && grep -qF 'wt-sidebar" "--review" "toggle"' "$conf" && grep -qF 'wt-sidebar" "--review" "show"' "$conf"; then
    ok "pane keys (Ctrl g, then 1 2 3 h l ; v Tab r)"
    return 0
  fi
  note "for the pane keys, add these binds to the normal block of keybinds (Tab: a worktree's"
  note "tasks tab and back, through a pane of 1 cell that closes at once; zellij has no key action"
  note "for a tab by name. v: hide or show review, and 3 shows a hidden one, the same way."
  note "r: the launcher, a floating prompt that starts a task):"
  cat <<KDL
          normal {
              bind "h" { MoveFocus "left"; SwitchToMode "locked"; }
              bind "l" { MoveFocus "right"; SwitchToMode "locked"; }
              bind "1" { MoveFocus "left"; MoveFocus "left"; SwitchToMode "locked"; }
              bind "2" { MoveFocus "left"; MoveFocus "left"; MoveFocus "right"; SwitchToMode "locked"; }
              bind "3" { MoveFocus "right"; MoveFocus "right"; Run "$BIN/wt-sidebar" "--review" "show" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind ";" { FocusLastPane; SwitchToMode "locked"; }
              bind "v" { Run "$BIN/wt-sidebar" "--review" "toggle" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind "Tab" { Run "$BIN/hub-run" "--switch" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
              bind "r" { Run "$BIN/hub-run" "--launcher" { floating true; close_on_exit true; x "20%"; y "35%"; width "60%"; height "3"; }; SwitchToMode "locked"; }
          }
KDL
  note "the hub expects default_mode \"locked\", with Ctrl g to normal mode and Ctrl q to quit"
}

uninstall() {
  head_ "Uninstall"
  local f dest
  for f in "$repo"/bin/* "$repo/lib/wt-lib.sh"; do
    [[ $f == */lib/* ]] && dest="$LIB/wt-lib.sh" || dest="$BIN/${f##*/}"
    if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -f "$dest"; did "removed $dest"; fi
  done
  dest="$HOME/.config/wt-hub/yazi"
  if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -rf "$dest"; did "removed $dest"; fi
  dest="$HOME/.config/tuicr/config.toml"
  if [[ -e "$dest" || -L "$dest" ]] && is_ours "$dest"; then rm -f "$dest"; did "removed $dest"; fi
  if claude plugin marketplace list 2>/dev/null | grep -q alex-wt-hub; then
    need "the mod: claude plugin uninstall wt-hub@alex-wt-hub && claude plugin marketplace remove alex-wt-hub"
  fi
  rm -rf "$SHARE" && did "removed $SHARE (zjstatus, mod copy, list of installed files)"
  need "remove the hub's hooks (claude-notify, claude-turn-snapshot, hub-run --hook) from $SETTINGS"
  note "kept: ~/.config/wt-hub/config and ~/.config/worktrunk/config.toml (your settings), ~/.local/state (hub state and logs)"
}

if [[ $mode == uninstall ]]; then
  uninstall
  exit 0
fi

check_tools
install_files
head_ "Configs"
install_settings
install_tuicr
install_worktrunk
install_hooks
install_zjstatus
if $mod || [[ $mode == check ]]; then install_mod; fi
check_zellij

head_ "Result"
if ((todo == 0)); then
  echo "  Ready. Start the hub with: wt hub"
else
  echo "  $todo TODO item(s) above. Then start the hub with: wt hub"
fi
