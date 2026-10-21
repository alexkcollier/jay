#!/bin/bash
# install.sh: the hook merge (merged_settings) keeps the user's settings and hooks and adds only
# the missing ones; a full install in the fake HOME (offline: the zjstatus download fails), a
# second run, --check and --uninstall.
source "$(dirname "$0")/lib.sh"

# merged_settings from install.sh, on its own.
repo=$REPO
eval "$(sed -n '/^merged_settings() {$/,/^}$/p' "$REPO/install.sh")"
ours="$REPO/config/claude-settings-hooks.json"
cmds() { jq -r --arg e "$1" '[.hooks[$e][]?.hooks[]?.command] | join(" | ")' <<<"$2"; }

user='{
  "model": "opus",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "my-stop-hook"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "my-guard"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$HOME/.local/bin/claude-turn-snapshot"}]}]
  }
}'
printf '%s\n' "$user" >"$TMP/user.json"
merged=$(merged_settings "$TMP/user.json")
eq "other settings stay" opus "$(jq -r .model <<<"$merged")"
eq "a hook of another event stays" "my-guard" "$(cmds PreToolUse "$merged")"
eq "the user's Stop hook stays, ours come after it" \
  "my-stop-hook | WT_NOTIFY_LOG=\$HOME/.local/state/claude-notify.log \$HOME/.local/bin/claude-notify | \$HOME/.local/bin/claude-turn-snapshot" \
  "$(cmds Stop "$merged")"
eq "a hook that is there already is not added again" "\$HOME/.local/bin/claude-turn-snapshot" "$(cmds UserPromptSubmit "$merged")"
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
printf 'mine\n' >"$HOME/.local/bin/wt-go"
out=$("$REPO/install.sh" 2>&1)
eq "install.sh ends" 0 $?
has "a file of the user's is a TODO" "wt-go exists and is not from wt-hub" "$out"
eq "a file of the user's stays" mine "$(cat "$HOME/.local/bin/wt-go")"
has "install.sh: a missing tool is a TODO with its brew command" "fzf not found: brew install fzf" "$out"
has "install.sh: one brew command for the missing tools" "brew install fzf tuicr yazi" "$out"
has "install.sh: the zjstatus download fails offline" "zjstatus download failed" "$out"
ok "the scripts are copies" test -f "$HOME/.local/bin/wt-sidebar" -a ! -L "$HOME/.local/bin/wt-sidebar"
ok "wt-pick is there" test -e "$HOME/.local/bin/wt-pick"
ok "wt-lib.sh" test -f "$HOME/.local/lib/wt-lib.sh"
ok "the settings file" test -f "$HOME/.config/wt-hub/config"
ok "the tuicr config" grep -q 'q_quits = true' "$HOME/.config/tuicr/config.toml"
ok "the worktrunk config" test -f "$HOME/.config/worktrunk/config.toml"
eq "settings.json: merged" "$(jq -S . "$TMP/merged.json")" "$(jq -S . "$HOME/.claude/settings.json")"
eq "settings.json: one backup" 1 "$(ls "$HOME/.claude/" | grep -c 'settings.json.wt-hub-backup')"
eq "the backup is the user's file" "$(jq -S . <<<"$user")" "$(jq -S . "$HOME"/.claude/settings.json.wt-hub-backup.*)"

out=$("$REPO/install.sh" 2>&1)
has "a second run: the hooks are there" "has the hub's hooks" "$out"
eq "a second run: no second backup" 1 "$(ls "$HOME/.claude/" | grep -c 'settings.json.wt-hub-backup')"
before=$(find "$HOME" -type f | sort | xargs cksum)
"$REPO/install.sh" --check >/dev/null 2>&1
eq "--check changes nothing" "$before" "$(find "$HOME" -type f | sort | xargs cksum)"

"$REPO/install.sh" --uninstall >/dev/null 2>&1
no "--uninstall removes the scripts" test -e "$HOME/.local/bin/wt-sidebar"
eq "--uninstall keeps a file of the user's" mine "$(cat "$HOME/.local/bin/wt-go")"
ok "--uninstall keeps the settings" test -f "$HOME/.config/wt-hub/config"
ok "--uninstall keeps the worktrunk config" test -f "$HOME/.config/worktrunk/config.toml"
ok "--uninstall keeps the stubs" test -x "$HOME/.local/bin/claude"

finish
