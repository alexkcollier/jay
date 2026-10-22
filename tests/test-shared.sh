#!/bin/bash
# Agents that share a worktree: jay new <existing branch> adds an agent there (-n names it by its
# role), keeps each agent's task note (jay_agent_note) and adds it to the worktree's note, tells
# the new agent of an agent caller to commit only its own files, and refuses the main
# checkout's branch. The list shows each agent's note after its row in a shared worktree.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.eval" -b eval
git -C "$shop" worktree add -q "$root/shop.solo" -b solo

# A claude that starts agents: `claude --bg [--name N] [prompt]` adds a blocked background agent
# in this folder to $STUB/agents.json and prints its short id as claude does. Each call goes to
# $STUB/claude.calls, one call per record (NUL after it): a prompt can have new lines.
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/bin/bash
printf '%s\0' "$*" >>"$STUB/claude.calls"
case ${1:-} in
  agents) cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  --bg)
    name=""
    while (($#)); do [[ "$1" == --name ]] && name=$2; shift; done
    n=$(cat "$STUB/next" 2>/dev/null || echo 1); echo $((n + 1)) >"$STUB/next"
    id=$(printf 'b%07d' "$n")
    jq -c --arg id "$id" --arg n "$name" --arg c "$PWD" \
      '. + [{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, state: "blocked", startedAt: 0}]' \
      "$STUB/agents.json" >"$STUB/agents.new" && mv "$STUB/agents.new" "$STUB/agents.json"
    echo "backgrounded · $id · $name" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME/.local/bin/claude"
# A wt that knows the worktrees by branch and keeps the state variable task per worktree.
cat >"$HOME/.local/bin/wt" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$STUB/wt.calls"
if [[ "\$1" == switch ]]; then
  case \$2 in main) p="$shop" ;; *) p="$root/shop.\$2" ;; esac
  echo "{\"path\": \"\$p\"}"
elif [[ "\$1" == -C && "\$3 \$4 \$5" == "config state vars" ]]; then
  f="$STUB/task.\$(basename "\$2")"
  case \$6 in
    get) cat "\$f" 2>/dev/null ;;
    set) printf '%s\n' "\${7#task=}" >"\$f" ;;
  esac
fi
exit 0
EOF
chmod +x "$HOME/.local/bin/wt"

# The --bg calls, and the last one.
bg_calls() { tr '\0' '\n' <"$STUB/claude.calls" | awk '/^--bg/ { p = 1 } /^agents/ { p = 0 } p'; }
last_call() { tr '\0' '\n' <"$STUB/claude.calls" | awk '/^--bg/ { s = "" } { s = s $0 "\n" } END { printf "%s", s }' | awk '/^agents/ { exit } { print }'; }
last_name() { bg_calls | grep -e '^--bg' | tail -1 | sed -E 's/.*--name ([^ ]*).*/\1/'; }
note() { cat "$STUB/task.shop.$1" 2>/dev/null; }
# The orchestrator that runs jay new as an agent caller (CLAUDE_CODE_SESSION_ID).
echo '[{"kind": "background", "id": "0000000a", "sessionId": "sid-0000000a", "name": "shop/main", "cwd": "'"$shop"'", "state": "working", "startedAt": 0}]' >"$STUB/agents.json"
as_orch() { (cd "$shop" && CLAUDE_CODE_SESSION_ID=sid-0000000a jay-new "$@") 2>&1; }

# --- The first agent in a worktree ---
: >"$STUB/claude.calls"
as_orch eval -t "evaluate the list" -- evaluate the list >/dev/null
eq "the first agent: <repo>/<branch>" shop/eval "$(last_name)"
eq "the worktree's task note" "evaluate the list" "$(note eval)"
eq "its own note" "evaluate the list" "$(cat "$JAY_NOTES/b0000001")"
has "an agent caller: the report line" "report to shop/main with SendMessage" "$(last_call)"
hasnt "alone in the worktree: no line about other agents" "Other agents" "$(last_call)"

# --- A second agent in the same worktree, named by its role ---
: >"$STUB/claude.calls"
as_orch eval -n list-critique -t "critique the eval" -- critique the evaluation >/dev/null
eq "-n: <repo>/<name>" shop/list-critique "$(last_name)"
eq "the worktree's note keeps the first agent's note" "evaluate the list · critique the eval" "$(note eval)"
eq "its own note" "critique the eval" "$(cat "$JAY_NOTES/b0000002")"
eq "the first agent's own note stays" "evaluate the list" "$(cat "$JAY_NOTES/b0000001")"
has "other agents in the worktree: commit only your own files" "Other agents work in this worktree: commit only your own files." "$(last_call)"
eq "the agent works in the shared worktree" "$root/shop.eval" "$(jq -r '.[] | select(.id == "b0000002") | .cwd' "$STUB/agents.json")"

# --- A third one without -n: <repo>/<branch>-2 ---
as_orch eval -t "critique the eval" -- once more >/dev/null
eq "no -n: a second agent on the branch gets -2" shop/eval-2 "$(last_name)"
eq "the same note again: not added twice" "evaluate the list · critique the eval" "$(note eval)"
as_orch eval -n list-critique -- a fourth one >/dev/null
eq "-n with a taken name: jay_unique_name" shop/list-critique-2 "$(last_name)"
as_orch eval -n acme/other -- a fifth one >/dev/null
eq "-n with a /: the name as it is" acme/other "$(last_name)"

# --- A person in a shell, and a worktree where all agents stopped ---
: >"$STUB/claude.calls"
(cd "$shop" && jay-new eval -- from a shell) >/dev/null 2>&1
hasnt "from a shell: no report line, also in a shared worktree" "Other agents" "$(last_call)"
as_orch solo -t "first note" -- one >/dev/null
jq -c 'map(if .cwd == "'"$root/shop.solo"'" then .state = "stopped" else . end)' "$STUB/agents.json" >"$STUB/agents.new" \
  && mv "$STUB/agents.new" "$STUB/agents.json"
as_orch solo -t "second note" -- two >/dev/null
eq "the other agents stopped: the note is replaced, as before" "second note" "$(note solo)"
hasnt "the other agents stopped: no line about other agents" "Other agents" "$(last_call)"

# --- The main checkout's branch: no agent there ---
: >"$STUB/claude.calls"
out=$(as_orch main -- work on main)
rc=$?
eq "jay new <main checkout's branch>: exit 1" 1 "$rc"
has "it says why" "is checked out in the main checkout ($shop)" "$out"
eq "no agent starts" "" "$(bg_calls)"
eq "no wt switch" "" "$(grep -c '^switch main' "$STUB/wt.calls" | grep -v '^0$')"
(cd "$root/shop.eval" && jay-new main -a) >/dev/null 2>&1
eq "also from a worktree, and with -a" 1 "$?"
# pr:N (the branch is known only after wt switch): refused by the path.
cat >"$HOME/.local/bin/wt" <<EOF
#!/bin/bash
[[ "\$1" == switch ]] && echo '{"path": "$shop"}'
exit 0
EOF
chmod +x "$HOME/.local/bin/wt"
out=$(as_orch pr:7 -- review it)
eq "pr:N that is the main checkout: exit 1" 1 "$?"
eq "no agent starts for it" "" "$(bg_calls)"

# --- The list: two or more agents in a worktree show their own notes ---
rec() { # rec PATH MAIN BRANCH TASK
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" --arg t "$4" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: "shop", task: $t, symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
mkdir -p "$JAY_STATE"
{ rec "$shop" true main ""; rec "$root/shop.eval" false eval "$(note eval)"
  rec "$root/shop.solo" false solo "second note"; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
rows=$(FZF_COLUMNS=100 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
plain() { sed -E $'s/\e\\[[0-9;]*m//g'; }
has "a shared worktree: the first agent's note after its row" "· evaluate the list" "$(row sid-b0000001 | plain)"
has "a shared worktree: the second agent's note" "shop/list-critique bg " "$(row sid-b0000002 | plain)"
has "the second agent's note" "· critique the eval" "$(row sid-b0000002 | plain)"
has "the worktree row: the joined note" "evaluate the list · critique the eval" "$(row "$root/shop.eval" | plain)"
solo=$(jq -r '.[] | select(.cwd == "'"$root/shop.solo"'" and .state != "stopped") | .sessionId' "$STUB/agents.json")
hasnt "one agent in a worktree: no note after its row (as before)" "·" "$(row "$solo" | plain)"
eq "a shared worktree: every agent has a row under it" 6 "$(awk -F'\t' '$1 == "ag"' <<<"$rows" | grep -c 'shop/\(eval\|list-critique\)\|acme/other')"
rows=$(FZF_COLUMNS=40 jay-sidebar --rows)
has "a narrow list: the note is cut" "· evaluate t…" "$(row sid-b0000001 | plain)"
rows=$(FZF_COLUMNS=30 jay-sidebar --rows)
hasnt "no room: no note" "·" "$(row sid-b0000001 | plain)"

finish
