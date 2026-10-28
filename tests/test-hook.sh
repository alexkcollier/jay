#!/bin/bash
# The SessionStart hook (jay-run --hook): the tasks text for every session, and for a session in
# a linked worktree that is not under .claude/worktrees/ also that it is isolated already (no
# EnterWorktree). The folder comes from the hook's stdin JSON (cwd), else the hook's own folder.
source "$(dirname "$0")/lib.sh"
link_install

root="$HOME/Documents/projects/acme"
shop="$root/shop"
repo "$shop"
git -C "$shop" worktree add -q -b feat "$root/shop.feat"
git -C "$shop" worktree add -q --detach "$root/shop.old"
git -C "$shop" worktree add -q -b agent-x "$shop/.claude/worktrees/agent-x"
mkdir -p "$TMP/plain" "$root/shop.feat/sub"
rev=$(git -C "$shop" rev-parse --short HEAD)
tasks='jay run -n <name> -w -- <command>'
isolated='Do not call EnterWorktree'

hook() { printf '{"session_id":"s1","hook_event_name":"SessionStart","cwd":"%s"}\n' "$1" | (cd "$TMP/plain" && jay-run --hook); }

out=$(hook "$root/shop.feat")
has "a linked worktree: the branch" "This folder is the worktree of branch feat ($root/shop.feat):" "$out"
has "a linked worktree: isolated" "$isolated" "$out"
has "a linked worktree: the tasks text too" "$tasks" "$out"
out=$(hook "$root/shop.feat/sub")
has "a folder in a linked worktree: its top" "the worktree of branch feat ($root/shop.feat):" "$out"
out=$(hook "$root/shop.old")
has "a detached worktree: its revision" "This folder is a worktree detached at $rev ($root/shop.old):" "$out"
for dir in "$shop" "$shop/.claude/worktrees/agent-x" "$TMP/plain" "$TMP/gone"; do
  out=$(hook "$dir")
  hasnt "no isolation text: ${dir#"$TMP"/}" "$isolated" "$out"
  has "the tasks text: ${dir#"$TMP"/}" "$tasks" "$out"
done
eq "the main checkout: only the tasks text" "$(cd "$TMP/plain" && jay-run --hook </dev/null)" "$(hook "$shop")"

# No JSON on stdin (a hook by hand, an old Claude): the hook's own folder.
has "no stdin JSON: the hook's folder" "$isolated" "$(cd "$root/shop.feat" && jay-run --hook </dev/null)"
hasnt "no stdin JSON in a main checkout" "$isolated" "$(cd "$shop" && jay-run --hook </dev/null)"
has "bad JSON: the hook's folder" "$isolated" "$(cd "$root/shop.feat" && echo 'not json' | jay-run --hook 2>&1)"

finish
