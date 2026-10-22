#!/bin/bash
# Agent names: jay_unique_name (lib/jay-lib.sh) and the places that start agents with it (jay new,
# jay c, the hub Claude), and the places that find an agent by name when two agents share one
# (made outside the hub): jay go lists their ids, the list shows the id after the name.
source "$(dirname "$0")/lib.sh"
link_install
# The hub sees only the agents in JAY_ROOTS; the test's folders are under $TMP.
export JAY_ROOTS=$TMP
source "$HOME/.local/lib/jay-lib.sh"

# A claude that also starts agents: `claude --bg [--name N] ...` adds a blocked background agent
# in this folder to $STUB/agents.json and prints its short id as claude does.
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB/claude.calls"
case ${1:-} in
  agents) [[ -f "$STUB/agents.fail" ]] && exit 1; cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  --bg)
    name=""
    while (($#)); do [[ "$1" == --name ]] && name=$2; shift; done
    n=$(cat "$STUB/next" 2>/dev/null || echo 1); echo $((n + 1)) >"$STUB/next"
    id=$(printf 'b%07d' "$n")
    jq -c --arg id "$id" --arg n "$name" --arg c "$PWD" \
      '. + [{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, state: "blocked", startedAt: 0}]' \
      "$STUB/agents.json" >"$STUB/agents.new" && mv "$STUB/agents.new" "$STUB/agents.json"
    echo "backgrounded · $id · $name" ;;
  attach) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME/.local/bin/claude"
# The --name of the last `claude --bg`.
last_name() { grep -e '^--bg' "$STUB/claude.calls" | tail -1 | sed -E 's/.*--name ([^ ]*).*/\1/'; }

agent() { # agent ID NAME [STATE] [CWD]
  jq -nc --arg id "$1" --arg n "$2" --arg st "${3:-blocked}" --arg c "${4:-$HOME}" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, startedAt: 0, state: $st, status: "idle"}'
}

# --- jay_unique_name, on fixture agents JSON ---
fixture=$(jq -sc . <<EOF
$(agent 0000000a shop/main working)
$(agent 0000000b shop/feat)
$(agent 0000000c shop/feat-2 done)
$(agent 0000000d shop/old stopped)
{"kind": "interactive", "sessionId": "sid-inter", "name": "Shop/Talk", "cwd": "$HOME", "startedAt": 0, "status": "idle"}
EOF
)
eq "a free name stays" shop/new "$(jay_unique_name shop/new "$fixture")"
eq "a taken name gets -2" shop/main-2 "$(jay_unique_name shop/main "$fixture")"
eq "-2 taken too (a done agent): -3" shop/feat-3 "$(jay_unique_name shop/feat "$fixture")"
eq "a stopped agent still has its name" shop/old-2 "$(jay_unique_name shop/old "$fixture")"
eq "an interactive session counts, in any case" shop/talk-2 "$(jay_unique_name shop/talk "$fixture")"
eq "the agent itself does not count (\$3)" shop/feat "$(jay_unique_name shop/feat "$fixture" sid-0000000b)"
eq "a removed agent does not count" shop/gone "$(jay_unique_name shop/gone "$fixture")"
stub_agents "$fixture"
eq "no JSON given: claude agents" shop/main-2 "$(jay_unique_name shop/main)"
touch "$STUB/agents.fail"
eq "claude agents fails: the name stays" shop/main "$(jay_unique_name shop/main)"
rm -f "$STUB/agents.fail"
eq "bad JSON: the name stays" shop/main "$(jay_unique_name shop/main 'not json')"

# --- jay new: a second agent in the same worktree ---
root="$HOME/Documents/projects/acme"
shop="$root/shop"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.feat" -b feat
cat >"$HOME/.local/bin/wt" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$STUB/wt.calls"
[[ "\$1" == switch ]] && echo '{"path": "$root/shop.feat"}'
exit 0
EOF
chmod +x "$HOME/.local/bin/wt"
stub_agents "$fixture"
(cd "$shop" && jay-new feat -a) >/dev/null 2>&1
eq "jay new -a: shop/feat and shop/feat-2 taken: shop/feat-3" shop/feat-3 "$(last_name)"
(cd "$shop" && jay-new feat -- write the tests) >/dev/null 2>&1
eq "jay new with a prompt, once more: shop/feat-4" shop/feat-4 "$(last_name)"
stub_agents '[]'
(cd "$shop" && jay-new feat -a) >/dev/null 2>&1
eq "jay new: a free name" shop/feat "$(last_name)"

# --- jay new from a Claude agent: the worker's prompt says to report back to it ---
report="report to shop/main with SendMessage"
: >"$STUB/claude.calls"
(cd "$shop" && jay-new feat -- write the tests) >/dev/null 2>&1
hasnt "jay new from a shell: no report line" "report to" "$(cat "$STUB/claude.calls")"
stub_agents "[$(agent 0000000a shop/main working "$shop")]"
: >"$STUB/claude.calls"
(cd "$shop" && CLAUDE_CODE_SESSION_ID=sid-0000000a jay-new feat -- write the tests) >/dev/null 2>&1
has "jay new from an agent: its name from claude agents" "$report" "$(cat "$STUB/claude.calls")"
has "the prompt comes first" "write the tests" "$(grep -e '^--bg' "$STUB/claude.calls")"
eq "the task note: still the first line of the prompt" "task=write the tests" "$(grep -o 'task=.*' "$STUB/wt.calls" | tail -1)"
job 0000000c '{"name": "shop/main"}'
: >"$STUB/claude.calls"
(cd "$shop" && CLAUDE_JOB_DIR="$HOME/.claude/jobs/0000000c" jay-new feat -- write the tests) >/dev/null 2>&1
has "jay new from an agent: its name from its job's state.json" "$report" "$(cat "$STUB/claude.calls")"
: >"$STUB/claude.calls"
(cd "$shop" && CLAUDE_CODE_SESSION_ID=sid-0000000a jay-new feat --no-report -- write the tests) >/dev/null 2>&1
hasnt "jay new --no-report: no report line" "report to" "$(cat "$STUB/claude.calls")"
has "jay new --no-report: the prompt" "write the tests" "$(cat "$STUB/claude.calls")"
: >"$STUB/claude.calls"
(cd "$shop" && CLAUDE_CODE_SESSION_ID=sid-0000000a jay-new feat -a) >/dev/null 2>&1
hasnt "jay new -a from an agent: no prompt, so no report line" "report to" "$(cat "$STUB/claude.calls")"

# --- jay c (and its link c) ---
stub_agents "[$(agent 0000000e shop/feat)]"
(cd "$root/shop.feat" && jay-c) >/dev/null 2>&1
eq "jay c names the agent as the hub does, unique" shop/feat-2 "$(last_name)"
(cd "$root/shop.feat" && c --name shop/feat "a prompt") >/dev/null 2>&1
eq "c --name: a taken name gets the next number" shop/feat-3 "$(last_name)"
has "c: the prompt goes on" "a prompt" "$(tail -2 "$STUB/claude.calls" | head -1)"
(cd "$root/shop.feat" && jay-c --name=mine) >/dev/null 2>&1
eq "jay c --name=: a free name stays" mine "$(last_name)"
mkdir -p "$HOME/plain"
(cd "$HOME/plain" && jay-c) >/dev/null 2>&1
eq "jay c outside a repo: the folder's name" plain "$(last_name)"
(cd "$root/shop.feat" && jay-c --resume sid-x) >/dev/null 2>&1
hasnt "jay c --resume without a name: no --name" "--name" "$(grep -e '^--bg' "$STUB/claude.calls" | tail -1)"

# --- The hub Claude ---
export JAY_HUB_CLAUDE_FILE="$JAY_STATE/hub-claude"
stub_agents "[$(agent 0000000f hub)]"
: >"$STUB/claude.calls"
id=$(jay_hub_claude)
eq "an agent that is not the hub Claude has the name hub: hub-2" hub-2 "$(last_name)"
eq "the id file has the new hub Claude" "$id" "$(cat "$JAY_HUB_CLAUDE_FILE")"
: >"$STUB/claude.calls"
eq "it runs: the same id, nothing started" "$id" "$(jay_hub_claude)"
eq "nothing started" "" "$(grep -e '^--bg' "$STUB/claude.calls")"
# The id file lost (a new state folder): the agent with the hub prompt is taken on.
rm -f "$JAY_HUB_CLAUDE_FILE"
job 0000000f "$(jq -nc --arg p "$(jay_hub_claude_prompt)" '{respawnFlags: ["--name", "hub", "--append-system-prompt", $p]}')"
stub_agents "[$(agent 0000000f hub done)]"
eq "a hub Claude the id file lost is taken on" 0000000f "$(jay_hub_claude)"
eq "it is not started again" "" "$(grep -e '^--bg' "$STUB/claude.calls")"
eq "the id file has it again" 0000000f "$(cat "$JAY_HUB_CLAUDE_FILE")"
stub_agents '[]'
: >"$STUB/claude.calls"
jay_hub_claude >/dev/null
eq "no agent named hub: hub" hub "$(last_name)"

# --- jay go: two agents with one name ---
stub_agents "$(jq -sc . <<EOF
$(agent 0000aaaa ui/review done)
$(agent 0000bbbb ui/review blocked)
$(agent 0000cccc shop/a done)
$(agent 0000dddd shop/ab blocked)
EOF
)"
out=$(jay-go ui/review 2>&1)
has "a shared name: jay go says so" "Several Claude sessions match \"ui/review\"" "$out"
has "and lists one id" "0000aaaa  ui/review  done" "$out"
has "and the other" "0000bbbb  ui/review  blocked" "$out"
has "the id finds the agent (no hub, no Ghostty here)" "Bringing 0000bbbb in front" "$(jay-go 0000bbbb 2>&1)"
has "a part of a name: the live one wins over another name" "Bringing 0000dddd in front" "$(jay-go shop 2>&1)"
has "a session id prefix that two agents have: listed" "Several Claude sessions match" "$(jay-go sid-0000 2>&1)"
has "a session id prefix that one agent has" "Bringing 0000aaaa in front" "$(jay-go sid-0000a 2>&1)"
has "the old name: wt go, through its shim" "Several Claude sessions match" "$(wt-go ui/review 2>&1)"

# --- The list: the id after a name that two shown agents share ---
rec() { # rec PATH MAIN BRANCH
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: "shop", task: "", symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
mkdir -p "$JAY_STATE"
{ rec "$shop" true main; rec "$root/shop.feat" false feat; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
feat="$root/shop.feat"
stub_agents "$(jq -sc . <<EOF
$(agent 00000001 shop/feat blocked "$feat")
$(agent 00000002 shop/feat done "$feat")
$(agent 00000003 shop/solo blocked "$feat")
$(agent 00000004 shop/solo stopped "$feat")
EOF
)"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
plain() { sed -E $'s/\x1b\\[[0-9;]*m//g' <<<"$1"; }
has "a shared name: the row has the id" "shop/feat 00000001" "$(plain "$(row sid-00000001)")"
has "and the other row its own" "shop/feat 00000002" "$(plain "$(row sid-00000002)")"
hasnt "a name shared only with a stopped agent (no row): no id" "00000003" "$(plain "$(row sid-00000003)")"

finish
