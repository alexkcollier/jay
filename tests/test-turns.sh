#!/bin/bash
# jay-snapshot on a real git repo: the base, a turn commit at each Stop, the live ref of a
# running turn (at most once in 5 s; Stop removes it), edits between turns, a turn stopped
# without Stop, a move into another worktree, the name of a background agent's chain, --list
# and --prune.
source "$(dirname "$0")/lib.sh"
link_install
# The hub sees only the agents in JAY_ROOTS; the test's folders are under $TMP.
export JAY_ROOTS=$TMP

main="$TMP/shop" feat="$TMP/shop.feat"
repo "$main"
SID=1234abcd-0000-0000-0000-000000000000
C=refs/wt-turns/1234abcd
state="$HOME/.local/state/jay/turns"

# hook EVENT CWD [TOOL] [PROMPT]: the hook input that Claude sends, for session $SID.
hook() {
  jq -nc --arg e "$1" --arg c "$2" --arg s "$SID" --arg t "${3:-}" --arg p "${4:-}" \
    '{hook_event_name: $e, cwd: $c, session_id: $s, tool_name: $t, prompt: $p,
      last_assistant_message: "Some words.\nresult: done"}' | jay-snapshot
}
g() { git -C "$main" "$@"; }
rev() { g rev-parse -q --verify "$1" 2>/dev/null; }
subject() { g log -1 --format=%s "$1" | sed 's/ *$//'; }
# A snapshot during a turn waits 5 s after the one before; a test does not wait.
unstamp() { rm -f "$state/1234abcd.live"; }

hook UserPromptSubmit "$main" "" "add b"
eq "base: HEAD at the first snapshot" "$(rev HEAD)" "$(rev $C/base)"
eq "no turn yet: no head" "" "$(rev $C/head)"
eq "the worktree of the chain" "$main" "$(cat "$state/1234abcd.worktree")"

printf 'two\n' >"$main/b.txt"
hook PostToolUse "$main" Edit
ok "a running turn: live ref" rev $C/live
eq "live: on the base" "$(rev $C/base)" "$(rev $C/live^)"
eq "live: its subject" "turn, running · add b" "$(subject $C/live)"
printf 'three\n' >>"$main/b.txt"
hook PostToolUse "$main" Edit
eq "a second snapshot within 5 s: none" "two" "$(g show $C/live:b.txt)"
unstamp
hook PostToolUse "$main" Bash
eq "after 5 s: a new live snapshot" "two three" "$(g show $C/live:b.txt | tr '\n' ' ' | sed 's/ $//')"

hook Stop "$main"
eq "Stop: a turn commit" "turn · add b" "$(subject $C/head)"
eq "Stop: the result line is its body" "result: done" "$(g log -1 --format=%b $C/head | sed '/^$/d')"
eq "Stop: the turn is on the base" "$(rev $C/base)" "$(rev $C/head^)"
eq "Stop removes live" "" "$(rev $C/live)"
eq "the branch does not move" "$(rev $C/base)" "$(rev HEAD)"
eq "the index does not change" "" "$(g diff --cached --name-only)"
eq "the files do not change" "?? b.txt" "$(g status --porcelain)"
head=$(rev $C/head)
hook Stop "$main"
eq "a turn with no change: no commit" "$head" "$(rev $C/head)"

printf 'by hand\n' >"$main/c.txt"
hook UserPromptSubmit "$main" "" "next"
eq "edits between turns: a commit of their own" "between turns · edits made outside the agent" "$(subject $C/head)"

printf 'x\n' >"$main/d.txt"
unstamp
hook PostToolUse "$main" Write
ok "live before a stop" rev $C/live
hook UserPromptSubmit "$main" "" "third"
eq "a turn stopped without Stop: its own turn commit" "turn · next" "$(subject $C/head)"
has "a turn stopped without Stop: says so" "ended without Stop" "$(g log -1 --format=%b $C/head)"
eq "a turn stopped without Stop: live goes" "" "$(rev $C/live)"

# The agent goes into another worktree of the repo (EnterWorktree).
g worktree add -q "$feat" -b feat
printf 'y\n' >"$main/e.txt"
hook PostToolUse "$feat" EnterWorktree
eq "a move: the turn so far in the old worktree" "turn, in shop · third" "$(subject $C/head^)"
eq "a move: then the files of the new worktree" "worktree · shop.feat" "$(subject $C/head)"
eq "a move: the chain has the new worktree's files" "a.txt" "$(g ls-tree --name-only $C/head | tr '\n' ' ' | sed 's/ $//')"
eq "a move: the chain follows the agent" "$feat" "$(cat "$state/1234abcd.worktree")"
printf 'f\n' >"$feat/f.txt"
hook Stop "$feat"
eq "the next turn in the new worktree" "turn · third" "$(subject $C/head)"
eq "the next turn shows only its own changes" "f.txt" "$(g diff --name-only $C/head^ $C/head)"
has "--list: the chain and its last turn" "1234abcd" "$(jay-snapshot --list "$feat")"

# A background agent's chain has its job id: it stays when the session id changes.
job feedf00d '{"sessionId": "5678ef00-0000-0000-0000-000000000000"}'
jq -nc --arg c "$main" '{hook_event_name: "UserPromptSubmit", cwd: $c, prompt: "hi",
  session_id: "5678ef00-0000-0000-0000-000000000000"}' \
  | CLAUDE_JOB_DIR="$HOME/.claude/jobs/feedf00d" jay-snapshot
ok "a background agent's chain is named after its job" rev refs/wt-turns/feedf00d/base
eq "not after its session id" "" "$(rev refs/wt-turns/5678ef00/base)"

# A session outside JAY_ROOTS gets no chain: the hub does not see it.
jq -nc --arg c "$main" '{hook_event_name: "UserPromptSubmit", cwd: $c, prompt: "hi",
  session_id: "0a0a0a0a-0000-0000-0000-000000000000"}' | JAY_ROOTS="$TMP/other" jay-snapshot
eq "outside JAY_ROOTS: no chain" "" "$(rev refs/wt-turns/0a0a0a0a/base)"
no "outside JAY_ROOTS: no state file" test -e "$state/0a0a0a0a.worktree"
# A root is a folder, not the start of a name: $TMP/sho is not a root of $TMP/shop.
jq -nc --arg c "$main" '{hook_event_name: "UserPromptSubmit", cwd: $c, prompt: "hi",
  session_id: "0b0b0b0b-0000-0000-0000-000000000000"}' | JAY_ROOTS="$TMP/sho" jay-snapshot
eq "a root that is only the start of the folder's name: no chain" "" "$(rev refs/wt-turns/0b0b0b0b/base)"
# The hub Claude gets its chain wherever it is.
job hub00001 '{"sessionId": "0c0c0c0c-0000-0000-0000-000000000000"}'
printf 'hub00001\n' >"$HOME/.local/state/jay/hub-claude"
jq -nc --arg c "$main" '{hook_event_name: "UserPromptSubmit", cwd: $c, prompt: "hi",
  session_id: "0c0c0c0c-0000-0000-0000-000000000000"}' \
  | JAY_ROOTS="$TMP/other" CLAUDE_JOB_DIR="$HOME/.claude/jobs/hub00001" jay-snapshot
ok "the hub Claude outside JAY_ROOTS: its chain" rev refs/wt-turns/hub00001/base
rm -f "$HOME/.local/state/jay/hub-claude"
g update-ref -d refs/wt-turns/hub00001/base

# --prune: chains of agents that `claude agents --all` no longer lists, when their worktree is
# gone or their last turn is older than 7 days.
g update-ref refs/wt-turns/dead0001/base HEAD
printf '%s\n' "$TMP/gone" >"$state/dead0001.worktree"
old=$(printf 'old\n' | GIT_COMMITTER_DATE="2020-01-01T00:00:00" g commit-tree "$(rev 'HEAD^{tree}')")
g update-ref refs/wt-turns/old00002/head "$old"
printf '%s\n' "$main" >"$state/old00002.worktree"
jq -nc --arg p "$main" '{path: $p, main: true}' >"$HOME/.local/state/jay/worktrees.ndjson"
# An agent outside JAY_ROOTS that `claude agents` lists keeps its chain: the hub does not see
# it, but it is not gone.
old3=$(printf 'old\n' | GIT_COMMITTER_DATE="2020-01-01T00:00:00" g commit-tree "$(rev 'HEAD^{tree}')")
g update-ref refs/wt-turns/out00003/head "$old3"
printf '%s\n' "$TMP/elsewhere-gone" >"$state/out00003.worktree"
stub_agents '[{"kind": "background", "id": "feedf00d", "sessionId": "5678ef00-0000-0000-0000-000000000000", "cwd": "'"$main"'"},
  {"kind": "interactive", "sessionId": "1234abcd-0000-0000-0000-000000000000", "cwd": "'"$main"'"},
  {"kind": "background", "id": "out00003", "sessionId": "0d0d0d0d-0000-0000-0000-000000000000", "cwd": "/elsewhere"}]'
: >"$STUB/agents.fail"
jay-snapshot --prune >/dev/null
ok "--prune without an agent list: nothing goes" rev refs/wt-turns/dead0001/base
rm -f "$STUB/agents.fail"
out=$(jay-snapshot --prune --dry-run)
has "--prune --dry-run: a gone worktree" "would remove dead0001 (worktree gone" "$out"
has "--prune --dry-run: an old last turn" "would remove old00002 (last turn over 7 days ago)" "$out"
ok "--dry-run removes nothing" rev refs/wt-turns/dead0001/base
jay-snapshot --prune >/dev/null
eq "--prune: the chain of a gone worktree goes" "" "$(rev refs/wt-turns/dead0001/base)"
eq "--prune: a chain with an old last turn goes" "" "$(rev refs/wt-turns/old00002/head)"
no "--prune: their state files go" test -e "$state/dead0001.worktree"
ok "--prune: a listed agent's chain stays" rev refs/wt-turns/feedf00d/base
ok "--prune: a listed session's chain stays" rev $C/head
ok "--prune: the chain of an agent outside JAY_ROOTS stays" rev refs/wt-turns/out00003/head
ok "--prune: and its state file" test -e "$state/out00003.worktree"

finish
