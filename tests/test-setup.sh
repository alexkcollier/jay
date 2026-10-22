#!/bin/bash
# jay-setup (the worktrunk pre-start hook): in a new worktree it copies the main checkout's
# ignored .env files and its ignored .claude/settings.local.json, also with a .worktreeinclude,
# and never replaces a file that the worktree has.
source "$(dirname "$0")/lib.sh"
link_install

root="$HOME/Documents/projects/acme"
shop="$root/shop"
repo "$shop"
printf '.env*\n.claude/settings.local.json\n' >"$shop/.gitignore"
git -C "$shop" add .gitignore && git -C "$shop" commit -qm ignore
mkdir -p "$shop/.claude" "$shop/api"
printf 'KEY=1\n' >"$shop/.env"
printf 'KEY=2\n' >"$shop/api/.env.local"
printf '{"permissions": {"allow": ["Bash(npm test)"]}}\n' >"$shop/.claude/settings.local.json"
# An .env file under .claude is not an env file of the project.
printf 'X=1\n' >"$shop/.claude/.env"

git -C "$shop" worktree add -q "$root/shop.feat" -b feat
out=$(jay-setup "$root/shop.feat" 2>&1)
eq "the .env file" "KEY=1" "$(cat "$root/shop.feat/.env" 2>/dev/null)"
eq "an .env file in a folder" "KEY=2" "$(cat "$root/shop.feat/api/.env.local" 2>/dev/null)"
eq "Claude's local settings" "$(cat "$shop/.claude/settings.local.json")" "$(cat "$root/shop.feat/.claude/settings.local.json" 2>/dev/null)"
has "it says so" "copied .claude/settings.local.json" "$out"
no "nothing else of .claude" test -e "$root/shop.feat/.claude/.env"

# The worktree has its own: it stays.
git -C "$shop" worktree add -q "$root/shop.own" -b own
mkdir -p "$root/shop.own/.claude"
printf '{}\n' >"$root/shop.own/.claude/settings.local.json"
jay-setup "$root/shop.own" >/dev/null 2>&1
eq "the worktree's own settings stay" "{}" "$(cat "$root/shop.own/.claude/settings.local.json")"

# With a .worktreeinclude: worktrunk copies what it lists (wt is a stub here); the settings
# come too.
printf '.env\n' >"$shop/.worktreeinclude"
git -C "$shop" add .worktreeinclude && git -C "$shop" commit -qm include
git -C "$shop" worktree add -q "$root/shop.inc" -b inc
out=$(jay-setup "$root/shop.inc" 2>&1)
has "a .worktreeinclude: wt step copy-ignored" "step copy-ignored --require-include" "$(cat "$STUB/wt.calls" 2>/dev/null)"
eq "a .worktreeinclude: Claude's local settings" "$(cat "$shop/.claude/settings.local.json")" "$(cat "$root/shop.inc/.claude/settings.local.json" 2>/dev/null)"

# Not ignored: not copied (git would show it as a new file).
git -C "$shop" rm -q --cached .gitignore && rm "$shop/.gitignore"
printf '.env*\n' >"$shop/.gitignore"
git -C "$shop" worktree add -q "$root/shop.plain" -b plain
jay-setup "$root/shop.plain" >/dev/null 2>&1
no "not ignored: not copied" test -e "$root/shop.plain/.claude/settings.local.json"

# The main checkout itself: nothing to copy.
out=$(jay-setup "$shop" 2>&1)
hasnt "the main checkout: no copy" "copied" "$out"

finish
