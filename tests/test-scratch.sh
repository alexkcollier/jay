#!/bin/bash
# Scratch worktrees: git worktrees that an agent makes in its job folder (jobs/<id>/tmp/<name>)
# to compare revisions. jay rm removes them and prunes (jay_remove_scratch), also when the agent's
# folder is gone; a worktree outside that job folder stays. The list's prune (jay_prune_worktrees,
# auto_prune) drops the entries whose folder is gone and keeps the others. The list marks a
# scratch worktree (dim, "scratch of <agent>"), under its agent's row.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

# claude: `agents --json` prints $STUB/agents.json; `rm` deletes the agent and its job folder.
stub claude '
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "rm "*) jq -c --arg i "$2" "map(select(.id != \$i))" "$STUB/agents.json" >"$STUB/agents.new" \
      && mv "$STUB/agents.new" "$STUB/agents.json"; rm -rf "$HOME/.claude/jobs/$2"; echo "removed $2" ;;
  *) exit 1 ;;
esac'

root="$HOME/Documents/projects/acme"
shop="$root/shop"
jobs="$HOME/.claude/jobs"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.feat" -b feat
git -C "$shop" worktree add -q "$root/shop.gone" -b gone
bg() { # bg ID NAME CWD: a background agent, done and stopped
  jq -nc --arg id "$1" --arg name "$2" --arg cwd "$3" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $name, cwd: $cwd, state: "done", status: null, pid: null, startedAt: 0}'
}
job 000000c1 "{\"cwd\": \"$root/shop.feat\"}"
job 000000c2 "{\"cwd\": \"$root/shop.feat\"}"
job 000000c3 "{\"cwd\": \"$root/shop.gone\"}"
stub_agents "$(jq -sc . <<EOF
$(bg 000000c1 shop/feat "$root/shop.feat")
$(bg 000000c2 shop/other "$root/shop.feat")
$(bg 000000c3 shop/gone "$root/shop.gone")
EOF
)"
add() { git -C "$shop" worktree add -q --detach "$1" HEAD; }
add "$jobs/000000c1/tmp/base"
add "$jobs/000000c1/tmp/v1"
add "$jobs/000000c2/tmp/x"
add "$jobs/000000c3/tmp/y"
add "$TMP/outside"
trees() { git -C "$shop" worktree list --porcelain | sed -n 's/^worktree //p'; }

# --- jay rm: the scratch worktrees in its job folder go, with git worktree remove --force (one
# has a change), then a prune; a worktree outside it and another job's stay ---
echo changed >"$jobs/000000c1/tmp/v1/a.txt"
out=$(jay rm 000000c1 2>&1); rc=$?
eq "rm: exit 0" 0 "$rc"
list=$(trees)
hasnt "rm: its scratch base goes" "$jobs/000000c1/tmp/base" "$list"
hasnt "rm: its scratch v1 (changed) goes" "$jobs/000000c1/tmp/v1" "$list"
no "rm: the folder base is gone" test -d "$jobs/000000c1/tmp/base"
has "rm: a worktree outside the job folder stays" "$TMP/outside" "$list"
has "rm: the scratch of another job stays" "$jobs/000000c2/tmp/x" "$list"
has "rm: its worktree stays" "$root/shop.feat" "$list"
log=$(cat "$JAY_STATE/prune.log")
has "rm: prune.log: base" "000000c1 (shop/feat): scratch worktree $jobs/000000c1/tmp/base: removed" "$log"
has "rm: prune.log: v1" "000000c1 (shop/feat): scratch worktree $jobs/000000c1/tmp/v1: removed" "$log"
has "rm: prune.log: then claude rm" "000000c1 (shop/feat): rm: removed 000000c1" "$log"

# --- The agent's folder is gone (wt remove first): its repo comes from the scratch worktree;
# the entry of a scratch folder that is gone goes too; the prune drops the stale entries of the
# repo (here one outside the job folder: git keeps nothing whose folder is gone) ---
git -C "$shop" worktree remove --force "$root/shop.gone"
add "$jobs/000000c3/tmp/z"
rm -rf "$jobs/000000c3/tmp/z"
add "$TMP/stale0"
rm -rf "$TMP/stale0"
out=$(jay rm shop/gone 2>&1); rc=$?
eq "folder gone: exit 0" 0 "$rc"
list=$(trees)
hasnt "folder gone: its scratch goes" "$jobs/000000c3/tmp/y" "$list"
hasnt "folder gone: the entry of a gone scratch folder goes" "$jobs/000000c3/tmp/z" "$list"
has "folder gone: prune.log: the gone scratch folder" "000000c3 (shop/gone): scratch worktree $jobs/000000c3/tmp/z: removed" "$(cat "$JAY_STATE/prune.log")"
hasnt "folder gone: the prune drops a stale entry" "$TMP/stale0" "$list"
has "folder gone: prune.log: the prune" "000000c3 (shop/gone): git worktree prune in $shop: Removing worktrees/stale0" "$(cat "$JAY_STATE/prune.log")"
has "folder gone: the other worktrees stay" "$TMP/outside" "$list"

# --- The list's prune: only the entries whose folder is gone ---
add "$TMP/stale"
rm -rf "$TMP/stale"
jay_prune_worktrees
list=$(trees)
hasnt "prune: the entry of a gone folder goes" "$TMP/stale" "$list"
has "prune: a worktree on disk stays" "$TMP/outside" "$list"
has "prune: a scratch worktree on disk stays" "$jobs/000000c2/tmp/x" "$list"
has "prune: a worktree of the repo stays" "$root/shop.feat" "$list"
has "prune: prune.log" "git worktree prune in $shop: Removing worktrees/stale" "$(cat "$JAY_STATE/prune.log")"
# auto_prune (every 10 minutes, from the list's rows) runs it too.
add "$TMP/stale2"
rm -rf "$TMP/stale2"
rm -f "$JAY_STATE/prune.stamp"
JAY_ROOTS=$HOME/Documents/projects FZF_COLUMNS=80 jay-sidebar --rows >/dev/null 2>&1
for _ in $(seq 50); do grep -q 'Removing worktrees/stale2' "$JAY_STATE/prune.log" && break; sleep 0.1; done
hasnt "auto_prune: the entry of a gone folder goes" "$TMP/stale2" "$(trees)"

# --- The list: a scratch worktree is dim with "scratch of <agent>", under that agent's row; a
# job that no agent has shows its short id, in its place ---
add "$jobs/000000zz/tmp/old"
rec() { # rec PATH MAIN BRANCH
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: "shop", task: "", symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
{ rec "$shop" true main; rec "$jobs/000000c2/tmp/x" false "(detached)"; rec "$jobs/000000zz/tmp/old" false "(detached)"
  rec "$root/shop.feat" false feat; rec "$TMP/outside" false "(detached)"; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
plain() { sed -E $'s/\e\\[[0-9;]*m//g'; }
eq "list: the mark" "      x · scratch of shop/other" "$(row "$jobs/000000c2/tmp/x" | plain)"
has "list: dim" $'\e[2mx · scratch' "$(row "$jobs/000000c2/tmp/x")"
eq "list: under the agent's row" "$jobs/000000c2/tmp/x" "$(awk -F'\t' 'p { print $2; exit } $2 == "sid-000000c2" { p = 1 }' <<<"$rows")"
eq "list: no agent: the short id, in place" "  old · scratch of 000000zz" "$(row "$jobs/000000zz/tmp/old" | plain)"
hasnt "list: a worktree outside a job folder: no mark" "scratch" "$(row "$TMP/outside" | plain)"
eq "list: each scratch worktree once" 2 "$(grep -c 'scratch of' <<<"$rows")"
rows=$(FZF_COLUMNS=20 jay-sidebar --rows)
eq "list: narrow: cut" "      x · scratch …" "$(row "$jobs/000000c2/tmp/x" | plain)"

# --- The prompts: how to compare revisions ---
has "hub prompt: a plain copy" 'git archive <rev> | tar -x -C "$CLAUDE_JOB_DIR/tmp/<name>"' "$(jay_hub_claude_prompt)"
has "orchestrator prompt: a worktree only when git must work in it" 'git worktree add --detach "$CLAUDE_JOB_DIR/tmp/<name>" <rev>' "$(jay_orchestrator_prompt shop "$shop")"

for p in $(trees); do [[ "$p" == "$shop" ]] || git -C "$shop" worktree remove --force "$p"; done
finish
