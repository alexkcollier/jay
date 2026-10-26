#!/bin/bash
# install.sh over an install of wt-hub (jay's old name): the last wt-hub commit installs itself in
# the fake HOME (copies, then in a second HOME links into a checkout that the rename then
# changes, as a git pull does), with an old config, old state, the old hooks and the old mod.
# Then jay's install.sh: the new layout, links at the old paths, only the new hooks, the mod
# under its new name, and the old commands through the shims.
source "$(dirname "$0")/lib.sh"

# The last commit of wt-hub, before the rename.
OLD_REV=b515aa1
old="$TMP/old"
mkdir -p "$old"
git -C "$REPO" archive "$OLD_REV" | tar -x -C "$old" || { fail "git archive $OLD_REV" "the repo needs its history"; finish; exit 1; }
new_tree() { # new_tree DIR: this checkout's files, as a pull of the rename leaves them
  rm -rf "$1"/bin "$1"/lib "$1"/config "$1"/mod "$1"/compat
  cp -R "$REPO"/bin "$REPO"/lib "$REPO"/config "$REPO"/mod "$REPO"/compat "$REPO"/install.sh "$1"/
}

# old_install MOD [--link]: wt-hub installed and used for a while, with its mod from folder MOD
# (a folder marketplace).
old_install() {
  local mod=$1
  shift
  mkdir -p "$HOME/.claude" "$HOME/Documents/projects/clients"
  printf '{"model": "opus", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "my-guard"}]}]}}\n' \
    >"$HOME/.claude/settings.json"
  "$old/install.sh" "$@" >/dev/null 2>&1
  printf 'WT_ROOTS=~/Documents/projects/clients\nWT_REVIEW=lazygit\n' >>"$HOME/.config/wt-hub/config"
  local s="$HOME/.local/state"
  mkdir -p "$s/wt-hub/ended" "$s/wt-hub/seen" "$s/wt-hub/lazygit/views/abcd0001" "$s/wt-turns" "$s/hub-tasks/started"
  touch "$s/wt-hub/ended/abcd0001" "$s/wt-hub/seen/abcd0002"
  printf '%s\n' "$HOME/Documents/projects/clients/shop" >"$s/wt-turns/abcd0001.worktree"
  printf '{"name": "web"}\n' >"$s/hub-tasks/started/123-4.json"
  printf 'feed0001\n' >"$s/wt-hub-claude"
  printf '30\n' >"$s/wt-hub-sidebar.pct"
  printf 'commits\n' >"$s/wt-hub-review.mode"
  printf 'one call\n' >"$s/claude-notify.log"
  printf '{}\n' >"$s/wt-worktrees.ndjson"
  printf '  ❯ alex-wt-hub\n    Source: Folder (%s)\n' "$mod" >"$STUB/marketplaces.txt"
}

# --- An install of copies ---
old_install "$old/mod"
ok "the old install: its copies" test -f "$HOME/.local/bin/wt-sidebar" -a ! -L "$HOME/.local/bin/wt-sidebar"
has "the old install: its hooks" "claude-turn-snapshot" "$(cat "$HOME/.claude/settings.json")"

# (Library: python3's cache, from the tools check.)
files() { find "$HOME" -path "$HOME/Library" -prune -o -print | sort | xargs cksum 2>/dev/null; find "$HOME" -path "$HOME/Library" -prune -o -type d -print | sort; }
before=$(files)
out=$("$REPO/install.sh" --check 2>&1)
has "--check: the old config folder is a TODO" "$HOME/.config/wt-hub is from wt-hub" "$out"
has "--check: the old hooks are a TODO" "has the hooks of wt-hub" "$out"
has "--check: the old mod is a TODO" "the mod is wt-hub's (marketplace alex-wt-hub)" "$out"
hasnt "--check: the old copies count as installed" "exists and is not from jay" "$out"
eq "--check changes nothing" "$before" "$(files)"

: >"$STUB/claude.calls"
out=$("$REPO/install.sh" 2>&1)
has "install: it moves wt-hub's files" "files and folders of wt-hub" "$out"
hasnt "install: no file is in the way" "exists and is not from jay" "$out"
c="$HOME/.config" s="$HOME/.local/state" sh="$HOME/.local/share"
eq "the config folder moved, a link stays" "$c/jay" "$(readlink "$c/wt-hub")"
has "the user's config is there" "WT_ROOTS=~/Documents/projects/clients" "$(cat "$c/jay/config")"
eq "the state folder moved, a link stays" "$s/jay" "$(readlink "$s/wt-hub")"
ok "the marks moved" test -f "$s/jay/ended/abcd0001" -a -f "$s/jay/seen/abcd0002"
ok "the lazygit views moved" test -d "$s/jay/lazygit/views/abcd0001"
ok "the turn chains' state moved" test -f "$s/jay/turns/abcd0001.worktree"
eq "wt-turns: a link" "$s/jay/turns" "$(readlink "$s/wt-turns")"
ok "the task records moved" test -f "$s/jay/tasks/started/123-4.json"
eq "hub-tasks: a link" "$s/jay/tasks" "$(readlink "$s/hub-tasks")"
eq "the hub Claude's id moved" feed0001 "$(cat "$s/jay/hub-claude")"
eq "the list's width moved" 30 "$(cat "$s/jay/sidebar.pct")"
eq "the review mode moved" commits "$(cat "$s/jay/review.mode")"
eq "the notify log moved" "one call" "$(cat "$s/jay/notify.log")"
eq "a state file: a link at the old path" "$s/jay/hub-claude" "$(readlink "$s/wt-hub-claude")"
eq "the share folder moved, a link stays" "$sh/jay" "$(readlink "$sh/wt-hub")"
hasnt "the list of installed files has the new paths" "/wt-hub/" "$(cat "$sh/jay/installed.txt")"
has "the list of installed files has the shims" "$HOME/.local/bin/wt-new" "$(cat "$sh/jay/installed.txt")"
has "wt-new is now the shim" "is now: jay new" "$(cat "$HOME/.local/bin/wt-new")"
ok "jay-new is there" test -x "$HOME/.local/bin/jay-new"

settings=$(cat "$HOME/.claude/settings.json")
hasnt "settings.json: no old notify hook" "claude-notify" "$settings"
hasnt "settings.json: no old snapshot hook" "claude-turn-snapshot" "$settings"
hasnt "settings.json: no old SessionStart hook" "hub-run --hook" "$settings"
has "settings.json: the new hooks" '$HOME/.local/bin/jay-run --hook' "$settings"
eq "settings.json: one jay-notify in Stop" 1 "$(jq '[.hooks.Stop[].hooks[].command | select(test("jay-notify"))] | length' <<<"$settings")"
eq "settings.json: the user's hook stays" my-guard "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' <<<"$settings")"
eq "settings.json: the user's settings stay" opus "$(jq -r .model <<<"$settings")"

calls=$(cat "$STUB/claude.calls")
has "the old mod goes" "plugin uninstall wt-hub@alex-wt-hub" "$calls"
has "its marketplace goes" "plugin marketplace remove alex-wt-hub" "$calls"
has "jay's mod comes from a copy (the old folder holds wt-hub's)" "plugin marketplace add $sh/jay/mod" "$calls"
has "jay's mod is installed" "plugin install jay@jay" "$calls"
eq "the copy is jay's mod" jay "$(jq -r .name "$sh/jay/mod/.claude-plugin/marketplace.json")"

# The scripts see the old settings under the new names.
setting() { /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh" && printf "%s" "${!1}"' _ "$1"; }
eq "WT_ROOTS in the config is JAY_ROOTS" "$HOME/Documents/projects/clients" "$(setting JAY_ROOTS)"
eq "WT_REVIEW in the config is JAY_REVIEW" lazygit "$(setting JAY_REVIEW)"
eq "an environment WT_ name works" "$HOME/x" "$(WT_ROOTS="$HOME/x" setting JAY_ROOTS)"
eq "a JAY_ name wins over a WT_ one" "$HOME/y" "$(WT_ROOTS="$HOME/x" JAY_ROOTS="$HOME/y" setting JAY_ROOTS)"
eq "WT_HUB_SESSION is JAY_SESSION" oldname "$(env -u JAY_SESSION WT_HUB_SESSION=oldname /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh" && printf %s "$JAY_SESSION"')"
eq "the hub Claude is the old one" feed0001 "$(/bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh" && jay_hub_claude_id')"
eq "a script of the old install sources wt-lib.sh: it gets jay's lib" feed0001 \
  "$(/bin/bash -c 'source "$HOME/.local/lib/wt-lib.sh" && jay_hub_claude_id')"

# The old commands, through the shims.
has "wt agents --json" "[]" "$(wt-agents --json 2>/dev/null)"
eq "claude-turn-snapshot --list (a hook name): no output of its own" "" "$(cd "$TMP" && claude-turn-snapshot --list 2>&1)"
has "wt hub --print-layout: jay's layout" "jay-sidebar" "$(wt-hub --print-layout 2>/dev/null)"

printf '  ❯ jay\n    Source: Folder (%s)\n' "$sh/jay/mod" >"$STUB/marketplaces.txt"
out=$("$REPO/install.sh" 2>&1)
hasnt "a second run: nothing more to move" "From wt-hub" "$out"
has "a second run: the hooks are there" "has the hub's hooks" "$out"
has "a second run: the mod is there" "marketplace jay is there" "$out"

# --no-compat: the shims and the links at the old paths go.
"$REPO/install.sh" --no-compat >/dev/null 2>&1
no "--no-compat: the shim goes" test -e "$HOME/.local/bin/wt-new"
no "--no-compat: the link at an old path goes" test -L "$c/wt-hub"
ok "--no-compat: the config stays" test -f "$c/jay/config"

# --- A --link install in a checkout that the rename changes ---
export HOME="$TMP/home2"
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/state"
cp "$TMP/home/.gitconfig" "$HOME/"
cp "$TMP/home/.local/bin/"{claude,zellij,wt,curl,terminal-notifier} "$HOME/.local/bin/"
checkout="$TMP/checkout"
cp -R "$old" "$checkout"
old="$checkout" old_install "$checkout/mod" --link
eq "the old link install: a link into the checkout" "$checkout/bin/wt-new" "$(readlink "$HOME/.local/bin/wt-new")"
# The pull of the rename: the old scripts are gone, the links dangle, the lib link holds the shim.
new_tree "$checkout"
no "after the pull: wt-new dangles" test -e "$HOME/.local/bin/wt-new"
eq "after the pull, before install.sh: a script that sources wt-lib.sh gets jay's lib" shop/main \
  "$(/bin/bash -c 'source "$HOME/.local/lib/wt-lib.sh" && jay_tab_name shop main')"
: >"$STUB/claude.calls"
out=$("$checkout/install.sh" --link 2>&1)
hasnt "install --link: no file is in the way" "exists and is not from jay" "$out"
eq "install --link: the dangling link becomes the shim's" "$checkout/compat/wt-new" "$(readlink "$HOME/.local/bin/wt-new")"
eq "install --link: jay-new" "$checkout/bin/jay-new" "$(readlink "$HOME/.local/bin/jay-new")"
eq "install --link: the lib" "$checkout/lib/jay-lib.sh" "$(readlink "$HOME/.local/lib/jay-lib.sh")"
eq "install --link: the yazi keys in their new folder" "$checkout/config/yazi" "$(readlink "$HOME/.config/jay/yazi")"
has "install --link: wt new works" "jay new <branch|pr:N>" "$(wt-new --help 2>/dev/null)"
calls=$(cat "$STUB/claude.calls")
has "install --link: the old mod goes" "plugin marketplace remove alex-wt-hub" "$calls"
has "install --link: jay's mod comes from the checkout's mod/ (it is jay's now)" "plugin marketplace add $checkout/mod" "$calls"
has "install --link: the hooks" '$HOME/.local/bin/jay-snapshot' "$(cat "$HOME/.claude/settings.json")"

# A hub of wt-hub that still runs: install.sh and jay say to quit it first.
stub zellij '
case "$*" in
  "list-sessions --short --no-formatting") echo hub ;;
  "list-sessions --no-formatting") echo "hub [Created 1h ago]" ;;
  "-s hub action list-panes -j") echo "[{\"id\": 0, \"title\": \"worktrees\"}]" ;;
  --version) echo "zellij 0.45.1" ;;
  *) exit 1 ;;
esac'
has "install.sh: quit the old hub first" "quit the hub of wt-hub" "$("$checkout/install.sh" --link 2>&1)"
out=$(jay --here </dev/null 2>&1)
eq "jay with the old hub running: exit 1" 1 "$(jay --here </dev/null >/dev/null 2>&1; echo $?)"
has "jay with the old hub running: it says so" "the hub of wt-hub still runs" "$out"

finish
