#!/bin/bash
# jay-guard (the PreToolUse hook on Bash): in an orchestrator's main checkout it denies the git
# and gh commands that change the branch, the history or the files, and allows reads,
# `git merge --ff-only` and `git branch -d` of a branch with no worktree (`-D` asks). A
# worktree, a plain agent and an interactive session pass.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" feat="$root/shop.feat"
repo "$shop" && git -C "$shop" worktree add -q "$feat" -b feat
mkdir -p "$shop/src"

orch_flags() { jq -nc --arg p "$(jay_orchestrator_prompt shop "$shop")" '["--name", "shop/main", "--append-system-prompt", $p]'; }
job orch0001 "{\"cwd\": \"$shop\", \"respawnFlags\": $(orch_flags)}"
job plain001 "{\"cwd\": \"$shop\", \"respawnFlags\": [\"--name\", \"shop/main\"]}"
# The orchestrator prompt in a worktree: not an orchestrator.
job orchwt01 "{\"cwd\": \"$feat\", \"respawnFlags\": $(orch_flags)}"
# An orchestrator in a worktree it entered (EnterWorktree).
job orchin01 "{\"cwd\": \"$shop\", \"worktreePath\": \"$feat\", \"respawnFlags\": $(orch_flags)}"

# guard JOB CWD COMMAND: the hook's output for a Bash call (JOB empty: no CLAUDE_JOB_DIR).
guard() {
  local input
  input=$(jq -nc --arg c "$3" --arg d "$2" \
    '{session_id: "s", cwd: $d, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}')
  if [[ -n "$1" ]]; then CLAUDE_JOB_DIR="$HOME/.claude/jobs/$1" jay-guard <<<"$input"
  else jay-guard <<<"$input"; fi
}
decision() { guard "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
denies() { eq "denies: $3 (in ${2##*/})" deny "$(decision "$@")"; }
allows() { eq "allows: $3 (in ${2##*/})" "" "$(decision "$@")"; }
asks() { eq "asks: $3 (in ${2##*/})" ask "$(decision "$@")"; }

# Denied in the main checkout.
for cmd in "git checkout -b fix" "git checkout feat" "git checkout -- a.txt" "git switch -c fix" \
  "git switch feat" "git branch fix" "git branch -D feat" "git branch -m old new" "git commit -m x" \
  "git commit -am 'a fix'" "git reset --soft HEAD~1" "git reset --hard" "git rebase main" \
  "git cherry-pick abc" "git revert HEAD" "git am x.patch" "git push" "git push -u origin feat" \
  "git pull" "git stash" "git stash push -m x" "git stash pop" "git merge feat" "git merge --no-ff feat" \
  "git merge --squash feat" "git restore a.txt" "git clean -fd" "git tag v1" "git tag -a v1 -m x" \
  "git add ." "git worktree add ../shop.x" "git fetch origin feat:feat" "git config user.name x" \
  "git lg" "gh pr checkout 12" "gh pr create --fill" "gh -R acme/shop pr create" "gh pr merge 12" \
  "/usr/bin/git commit -m x" "git -c core.x=y commit -m x" "GIT_EDITOR=true git rebase --continue" \
  "command git push" "env FOO=1 git push"; do
  denies orch0001 "$shop" "$cmd"
done
denies orch0001 "$shop/src" "git commit -m x"

# Allowed in the main checkout.
for cmd in "git status" "git status --short" "git log --oneline -5" "git diff main...feat" "git show HEAD" \
  "git branch" "git branch -a" "git branch -vv" "git branch --show-current" "git branch --list 'f*'" \
  "git branch --contains abc" "git branch --merged main" "git rev-parse HEAD" "git merge-base main feat" \
  "git fetch" "git fetch origin" "git worktree list --porcelain" "git for-each-ref refs/heads" \
  "git merge --ff-only feat" "git merge-tree --write-tree main feat" \
  "git merge-tree --write-tree --name-only main feat" "git merge-tree abc main feat" "git tag" "git tag -l 'v*'" "git stash list" "git config --get user.name" \
  "git config user.name" "git remote -v" "git -C ../shop.feat log" "git --no-pager log" "git" \
  "gh pr view 12" "gh pr list" "gh pr diff 12" "ls; echo git" "jay new fix -t x -- do it"; do
  allows orch0001 "$shop" "$cmd"
done

# The folder: cd, git -C, subshells.
allows orch0001 "$shop" "cd ../shop.feat && git commit -m x"
allows orch0001 "$shop" "cd $feat; git rebase main && git push"
allows orch0001 "$shop" "git -C $feat commit -m x"
allows orch0001 "$shop" "git -C ../shop.feat push"
allows orch0001 "$feat" "git commit -m x"
allows orch0001 "$feat" "gh pr create --fill"
denies orch0001 "$feat" "git -C $shop commit -m x"
denies orch0001 "$feat" "cd $shop && git checkout -b fix"
denies orch0001 "$feat" "cd ../shop && git stash"
denies orch0001 "$shop" "(cd ../shop.feat && git commit -m x); git commit -m y"
allows orch0001 "$shop" "(cd ../shop.feat && git commit -m x) && git status"
denies orch0001 "$shop" "cd \"\$WT\" && git commit -m x"
denies orch0001 "$shop" "git -C \"\$(wt path feat)\" commit -m x"
allows orch0001 "$shop" "git -C \"\$WT\" log"
allows orch0001 "$shop" "cd /tmp && git commit -m x"
# A worktree inside the main checkout (Claude's .claude/worktrees) is not the main checkout.
git -C "$shop" worktree add -q "$shop/.claude/worktrees/w1" -b w1
allows orch0001 "$shop" "cd .claude/worktrees/w1 && git commit -m x"

# Compound commands.
denies orch0001 "$shop" "git status && git checkout -b fix"
denies orch0001 "$shop" "git fetch; git rebase origin/main"
denies orch0001 "$shop" "git log | head -1 || git reset --hard"
denies orch0001 "$shop" $'git status\ngit push'
denies orch0001 "$shop" "echo \$(git stash)"
denies orch0001 "$shop" "x=\`git commit -m y\`"
denies orch0001 "$shop" "bash -c 'git commit -m x'"
denies orch0001 "$shop" "eval git push"
denies orch0001 "$shop" "{ git add -A; git commit -m x; }"
denies orch0001 "$shop" "if true; then git push; fi"
allows orch0001 "$shop" "git log 2>&1 | head -5 >/dev/null"
allows orch0001 "$shop" "echo 'git push' && echo \"git commit\""
allows orch0001 "$shop" "git status # git push"
allows orch0001 "$shop" $'cat <<\'EOF\'\ngit push\ngit commit -m x\nEOF\ngit status'
denies orch0001 "$shop" $'cat <<EOF >/dev/null\nnothing\nEOF\ngit push'

# The reason that Claude gets.
reason=$(guard orch0001 "$shop" "git checkout -b fix" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the reason names the command" '`git checkout -b fix`' "$reason"
has "the reason names the main checkout" "$shop" "$reason"
has "the reason: give it to the worker" "worker of that branch" "$reason"
eq "the event name" PreToolUse "$(guard orch0001 "$shop" "git push" | jq -r '.hookSpecificOutput.hookEventName')"

# Deleting local branches that no worktree has checked out: -d passes, -D asks the user.
git -C "$shop" branch old1 && git -C "$shop" branch old2
cur=$(git -C "$shop" branch --show-current)
for cmd in "git branch -d old1" "git branch -d old1 old2" "git branch --delete old1" \
  "git branch -dq old1" "git branch -d -- old1" "git branch -d 'old1'" "cd src && git branch -d old1" \
  "git branch -d old1; git status"; do
  allows orch0001 "$shop" "$cmd"
done
for cmd in "git branch -D old1" "git branch -D old1 old2" "git branch -d --force old1" \
  "git branch --delete --force old1" "git branch -df old1" "git branch -f -d old2" \
  "git branch -d old1 && git branch -D old2"; do
  asks orch0001 "$shop" "$cmd"
done
for cmd in "git branch -d $cur" "git branch -D $cur" "git branch -d feat" "git branch -D w1" \
  "git branch -d old1 feat" "git branch -D old1 $cur" "git branch -d \$b" "git branch -D \"\$b\"" \
  "git branch -d \"\$(echo old1)\"" "git branch -d \`echo old1\`" "git branch -d old*" "git branch -d 'old?'" \
  "git branch -d {old1,old2}" "git branch -d nosuch" "git branch -D old1 nosuch" "git branch -d -" \
  "git branch -d @{-1}" "git branch -d -r origin/old1" "git branch -dr origin/old1" \
  "git branch -d --remotes origin/old1" "git branch -d -m old1" "git branch -d -v old1" \
  "git branch -D old1 && git push" "git branch -m old1 new1" "git branch -f old1 HEAD" \
  "git branch --set-upstream-to=origin/main old1" "git -C \"\$X\" branch -d old1"; do
  denies orch0001 "$shop" "$cmd"
done
reason=$(guard orch0001 "$shop" "git branch -D old1 old2; git branch -D old1" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the ask names the branches" "branches old1 old2 in" "$reason"
has "the ask: unmerged work" "not merged" "$reason"
reason=$(guard orch0001 "$shop" "git branch -d feat" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: checked out in a worktree" "feat is checked out in a worktree" "$reason"
reason=$(guard orch0001 "$shop" "git branch -d $cur" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: the branch of the main checkout" "$cur is the branch of the main checkout" "$reason"
reason=$(guard orch0001 "$shop" "git branch -d nosuch" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: not a local branch" '`nosuch` is not a local branch' "$reason"
eq "the guard deletes no branch" "old1 old2" "$(git -C "$shop" for-each-ref --format='%(refname:short)' refs/heads/old1 refs/heads/old2 | xargs)"

# Other sessions pass.
allows "" "$shop" "git checkout -b fix"
allows plain001 "$shop" "git checkout -b fix"
allows orchwt01 "$feat" "git commit -m x"
allows nojob001 "$shop" "git commit -m x"
# An orchestrator in a worktree it entered: the worktree is free, its main checkout is not.
allows orchin01 "$feat" "git commit -m x"
denies orchin01 "$feat" "git -C $shop checkout feat"
# Another tool than Bash.
eq "another tool: no output" "" "$(CLAUDE_JOB_DIR="$HOME/.claude/jobs/orch0001" jay-guard <<<'{"tool_name": "Edit", "cwd": "'"$shop"'", "tool_input": {}}')"

# The hook in the settings that install.sh merges.
has "the hook is in config/claude-settings-hooks.json" '$HOME/.local/bin/jay-guard' \
  "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$REPO/config/claude-settings-hooks.json")"

finish
