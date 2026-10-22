#!/bin/bash
# install.sh: the hook merge (merged_settings) keeps the user's settings and hooks and adds only
# the missing ones; a full install in the fake HOME (offline: the zjstatus download fails), a
# second run, --check, --no-compat and --compat, and --uninstall.
source "$(dirname "$0")/lib.sh"

# merged_settings from install.sh, on its own.
repo=$REPO
eval "$(sed -n '/^OLD_HOOKS=/p; /^merged_settings() {$/,/^}$/p' "$REPO/install.sh")"
ours="$REPO/config/claude-settings-hooks.json"
cmds() { jq -r --arg e "$1" '[.hooks[$e][]?.hooks[]?.command] | join(" | ")' <<<"$2"; }

user='{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "my-stop-hook"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "my-guard"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$HOME/.local/bin/jay-snapshot"}]}]
  }
}'
printf '%s\n' "$user" >"$TMP/user.json"
merged=$(merged_settings "$TMP/user.json")
eq "other settings stay" opus "$(jq -r .model <<<"$merged")"
eq "the user's PreToolUse hook stays, ours comes after it" "my-guard | \$HOME/.local/bin/jay-guard" "$(cmds PreToolUse "$merged")"
eq "the user's Stop hook stays, ours come after it" \
  "my-stop-hook | JAY_NOTIFY_LOG=\$HOME/.local/state/jay/notify.log \$HOME/.local/bin/jay-notify | \$HOME/.local/bin/jay-snapshot" \
  "$(cmds Stop "$merged")"
eq "a hook that is there already is not added again" "\$HOME/.local/bin/jay-snapshot" "$(cmds UserPromptSubmit "$merged")"
for event in SessionStart PostToolUse Notification; do
  eq "a missing event is added: $event" "$(jq -c --arg e "$event" '.hooks[$e]' "$ours")" "$(jq -c --arg e "$event" '.hooks[$e]' <<<"$merged")"
done
printf '%s\n' "$merged" >"$TMP/merged.json"
eq "a second merge changes nothing" "$(jq -S . <<<"$merged")" "$(merged_settings "$TMP/merged.json" | jq -S .)"
eq "no settings: our hooks" "$(jq -S . "$ours")" "$(merged_settings <(echo '{}') | jq -S .)"

# A full install, offline, with a user's settings.json.
mkdir -p "$HOME/.claude" "$HOME/Documents/projects"
printf '%s\n' "$user" >"$HOME/.claude/settings.json"
# A file the installer did not make is never replaced.
printf 'mine\n' >"$HOME/.local/bin/jay-go"
out=$("$REPO/install.sh" 2>&1)
eq "install.sh ends" 0 $?
has "a file of the user's is a TODO" "jay-go exists and is not from jay" "$out"
eq "a file of the user's stays" mine "$(cat "$HOME/.local/bin/jay-go")"
has "install.sh: a missing tool is a TODO with its brew command" "fzf not found: brew install fzf" "$out"
has "install.sh: one brew command for the missing tools" "brew install fzf tuicr yazi" "$out"
has "install.sh: the zjstatus download fails offline" "zjstatus download failed" "$out"
has "install.sh: the hub starts with jay" "start the hub with: jay" "$out"
hasnt "a new install has nothing of wt-hub to move" "From wt-hub" "$out"
ok "the scripts are copies" test -f "$HOME/.local/bin/jay-sidebar" -a ! -L "$HOME/.local/bin/jay-sidebar"
ok "jay is there" test -x "$HOME/.local/bin/jay"
ok "jay-pick is there" test -e "$HOME/.local/bin/jay-pick"
ok "c is there (jay c)" test -x "$HOME/.local/bin/c"
ok "jay-lib.sh" test -f "$HOME/.local/lib/jay-lib.sh"
ok "the shim wt-lib.sh" test -f "$HOME/.local/lib/wt-lib.sh"
ok "the shim wt-new" test -x "$HOME/.local/bin/wt-new"
ok "the shim hub-run" test -x "$HOME/.local/bin/hub-run"
ok "the settings file" test -f "$HOME/.config/jay/config"
ok "the settings file names JAY_AUTO_RESPAWN" grep -q '^# JAY_AUTO_RESPAWN=idle' "$HOME/.config/jay/config"
ok "jay-respawn is there" test -x "$HOME/.local/bin/jay-respawn"
hasnt "claude has respawn: no note" "claude has no respawn" "$out"
ok "the yazi keys" test -f "$HOME/.config/jay/yazi/keymap.toml"
ok "the tuicr config" grep -q 'q_quits = true' "$HOME/.config/tuicr/config.toml"
ok "the worktrunk config" test -f "$HOME/.config/worktrunk/config.toml"
eq "settings.json: merged" "$(jq -S . "$TMP/merged.json")" "$(jq -S . "$HOME/.claude/settings.json")"
eq "settings.json: one backup" 1 "$(ls "$HOME/.claude/" | grep -c 'settings.json.jay-backup')"
eq "the backup is the user's file" "$(jq -S . <<<"$user")" "$(jq -S . "$HOME"/.claude/settings.json.jay-backup.*)"

# jay runs jay-<name>; the old names run the new commands.
has "jay --help lists the commands" "run <command...>" "$(jay --help)"
has "jay <name>: jay-<name>" "jay new <branch|pr:N>" "$(jay new --help)"
eq "jay <unknown>: an error" 2 "$(jay nothing >/dev/null 2>&1; echo $?)"
has "a user-facing shim: one line to stderr" "wt new is now: jay new" "$(wt-new --help 2>&1 >/dev/null)"
has "a user-facing shim: the new command's output" "jay new <branch|pr:N>" "$(wt-new --help 2>/dev/null)"
eq "hub-run --hook (a hook) prints only the hook text" "$(jay-run --hook)" "$(hub-run --hook 2>&1)"
has "hub-run ls: the notice" "hub-run is now: jay run" "$(hub-run ls 2>&1 >/dev/null)"
eq "an internal shim prints nothing of its own" "$(jay-sidebar --footer 2>&1)" "$(wt-sidebar --footer 2>&1)"
has "the hook text names jay run" 'jay run -n <name> -w -- <command>' "$(jay-run --hook)"

out=$("$REPO/install.sh" 2>&1)
has "a second run: the hooks are there" "has the hub's hooks" "$out"
eq "a second run: no second backup" 1 "$(ls "$HOME/.claude/" | grep -c 'settings.json.jay-backup')"
before=$(find "$HOME" -type f | sort | xargs cksum)
dirs=$(find "$HOME" -type d | sort)
"$REPO/install.sh" --check >/dev/null 2>&1
eq "--check changes nothing" "$before" "$(find "$HOME" -type f | sort | xargs cksum)"
eq "--check makes no folder" "$dirs" "$(find "$HOME" -type d | sort)"

# --no-compat: the shims go and stay away; --compat brings them back.
out=$("$REPO/install.sh" --no-compat 2>&1)
has "--no-compat says what went" "shims and" "$out"
no "--no-compat removes the shims" test -e "$HOME/.local/bin/wt-new"
no "--no-compat removes wt-lib.sh" test -e "$HOME/.local/lib/wt-lib.sh"
ok "--no-compat keeps jay" test -x "$HOME/.local/bin/jay-new"
"$REPO/install.sh" >/dev/null 2>&1
no "an install after --no-compat leaves the shims out" test -e "$HOME/.local/bin/hub-run"
"$REPO/install.sh" --compat >/dev/null 2>&1
ok "--compat brings them back" test -x "$HOME/.local/bin/hub-run"
# --no-compat waits while something of the user's calls an old name.
mkdir -p "$HOME/.config/zellij"
printf 'bind "Tab" { Run "%s/.local/bin/hub-run" "--switch" { floating true; }; }\n' "$HOME" >"$HOME/.config/zellij/config.kdl"
out=$("$REPO/install.sh" --no-compat 2>&1)
has "--no-compat: old pane keys first" "call hub-run or wt-sidebar" "$out"
ok "--no-compat: then nothing goes" test -x "$HOME/.local/bin/hub-run"
rm -f "$HOME/.config/zellij/config.kdl"

"$REPO/install.sh" --uninstall >/dev/null 2>&1
no "--uninstall removes the scripts" test -e "$HOME/.local/bin/jay-sidebar"
no "--uninstall removes the shims" test -e "$HOME/.local/bin/wt-sidebar"
eq "--uninstall keeps a file of the user's" mine "$(cat "$HOME/.local/bin/jay-go")"
ok "--uninstall keeps the settings" test -f "$HOME/.config/jay/config"
ok "--uninstall keeps the worktrunk config" test -f "$HOME/.config/worktrunk/config.toml"
ok "--uninstall keeps the stubs" test -x "$HOME/.local/bin/claude"

# old_hub_runs (the Result line asks to quit the old hub): only a running session "hub" counts,
# not an exited one that zellij keeps to resurrect, nor one whose name only ends in hub.
eval "$(sed -n '/^old_hub_runs() {$/,/^}$/p' "$REPO/install.sh")"
stub zellij '[[ "$1" == list-sessions ]] && cat "$STUB/sessions.txt"'
sessions() { printf '%s\n' "$@" >"$STUB/sessions.txt"; }
sessions "jay [Created 23m 20s ago] (current)" "hub [Created 5days 2h ago] (EXITED - attach to resurrect)"
no "old_hub_runs: an exited hub does not count" old_hub_runs
sessions "claude agent hub [Created 5days ago] " "jay [Created 23m ago] "
no "old_hub_runs: a name that ends in hub does not count" old_hub_runs
sessions "hub [Created 2h 3m ago] " "jay [Created 23m ago] (current)"
ok "old_hub_runs: a running hub" old_hub_runs
sessions "hub [Created 2h 3m ago] (current)"
ok "old_hub_runs: the hub you are in" old_hub_runs

finish
