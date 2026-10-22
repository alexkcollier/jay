#!/bin/bash
# The hub sees only the Claude agents whose folder is in JAY_ROOTS (a root, or under one), and
# the hub Claude: jay agents --json (jay all, the mod), the list, jay go, jay respawn, the
# notices. jay_agents_in_roots, jay_in_roots. (The turn chains: test-turns.)
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

# The default root: ~/Documents/projects.
root="$HOME/Documents/projects"
shop="$root/acme/shop"
repo "$shop"

# agent ID NAME CWD [KIND]: one entry of `claude agents --json --all`.
agent() {
  jq -nc --arg id "$1" --arg n "$2" --arg c "$3" --arg k "${4:-background}" '
    {kind: $k, sessionId: ("sid-" + $id), name: $n, cwd: $c, state: "done", status: "idle", startedAt: 0}
    + (if $k == "background" then {id: $id} else {} end)'
}
stub_agents "$(jq -sc . <<EOF
$(agent in000001 shop/in "$shop")
$(agent pre00002 x/prefix "$HOME/Documents/projects-old/x")
$(agent out00003 other/out "$HOME/elsewhere")
$(agent hub00004 hub "$root")
$(agent hub00005 hub-2 "$HOME/hubhome")
$(agent int00006 talk "$shop" interactive)
$(agent int00007 far "/var/far" interactive)
EOF
)"
ids() { jq -r 'map(.id // .sessionId) | join(" ")'; }

eq "jay agents --json: only the agents in the root" "in000001 hub00004 sid-int00006" "$(jay-agents --json | ids)"
eq "the hub Claude by its id, also outside the root" "in000001 hub00004 hub00005 sid-int00006" \
  "$(printf 'hub00005\n' >"$JAY_HUB_CLAUDE_FILE"; jay-agents --json | ids)"
rm -f "$JAY_HUB_CLAUDE_FILE"
eq "two roots, one with a / at the end" "in000001 pre00002 hub00004 sid-int00006" \
  "$(JAY_ROOTS="$root:$HOME/Documents/projects-old/" jay-agents --json | ids)"
eq "a root through a symlink" "in000001 sid-int00006" \
  "$(ln -s "$root/acme" "$TMP/link" && JAY_ROOTS="$TMP/link" jay-agents --json | ids)"
eq "~ at the start of a root" "in000001 hub00004 sid-int00006" "$(JAY_ROOTS='~/Documents/projects' jay-agents --json | ids)"
: >"$STUB/agents.fail"
eq "claude agents fails: jay agents --json gives []" "[]" "$(jay-agents --json)"
rm -f "$STUB/agents.fail"

ok "jay_in_roots: the root" jay_in_roots "$root"
ok "jay_in_roots: under the root" jay_in_roots "$shop"
no "jay_in_roots: a name that starts with the root's" jay_in_roots "$root-old"
no "jay_in_roots: outside" jay_in_roots "$HOME"
no "jay_in_roots: an empty root is not /" env JAY_ROOTS="$root::" bash -c "source $HOME/.local/lib/jay-lib.sh; jay_in_roots /var"

# jay go and jay respawn do not find an agent outside the roots.
out=$(jay-go other/out 2>&1)
has "jay go: an agent outside the roots is not found" 'No Claude session matches "other/out"' "$out"
out=$(jay-go out00003 2>&1)
has "jay go <id>: not found either" 'No Claude session matches' "$out"
out=$(jay-respawn out00003 2>&1)
has "jay respawn <id> outside the roots: no such agent" "no background agent out00003" "$out"

# The list: rows for the agents in the root only.
mkdir -p "$JAY_STATE"
jq -nc --arg p "$shop" '{path: $p, main: true, branch: "main", client: "acme", repo: "shop", task: "",
  symbols: "", git: {added: 0, deleted: 0, staged: false, modified: false, untracked: false,
  conflicted: false, operation: null, state: "is_main", ahead: 0, behind: 0, remote: false, push: 0,
  pull: 0}}' >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
sids=$(awk -F'\t' '$2 ~ /^sid-/ { print $2 }' <<<"$rows" | sort | tr '\n' ' ')
eq "the list: rows of the agents in the root (also in the root itself)" "sid-hub00004 sid-in000001 sid-int00006 " "$sids"

# The notices and the unread mark: not for a session outside the roots.
stop() { # stop SESSION CWD
  jq -nc --arg s "$1" --arg c "$2" '{hook_event_name: "Stop", session_id: $s, cwd: $c, last_assistant_message: "result: done"}' \
    | jay-notify
}
stop s-out "$HOME/elsewhere"
stop s-in "$shop"
for i in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$STUB/terminal-notifier.calls" ]] && break; sleep 0.2; done
sleep 0.5
no "Stop outside the roots: no ended mark" test -e "$JAY_MARKS/ended/s-out"
ok "Stop in the root: an ended mark" test -f "$JAY_MARKS/ended/s-in"
eq "one notice: the one in the root" 1 "$(grep -c 'Turn finished' "$STUB/terminal-notifier.calls" 2>/dev/null)"
job hub00005 '{"sessionId": "s-hub"}'
printf 'hub00005\n' >"$JAY_HUB_CLAUDE_FILE"
CLAUDE_JOB_DIR="$HOME/.claude/jobs/hub00005" stop s-hub "$HOME/hubhome"
ok "Stop of the hub Claude outside the roots: an ended mark" test -f "$JAY_MARKS/ended/hub00005"

finish
