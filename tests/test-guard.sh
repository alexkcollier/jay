#!/bin/bash
# jay-guard (the PreToolUse hook on Bash): in an orchestrator's main checkout it denies the git
# and gh commands that change the branch, the history or the files, and allows reads,
# `git merge --ff-only`, a push of the main checkout's own branch (no force, delete or tags),
# `git remote add` of a new name and `git branch -d` of a branch with no worktree (`-D` asks). A worktree, a plain agent and an
# interactive session pass.
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
  "git cherry-pick abc" "git revert HEAD" "git am x.patch" "git push -u origin feat" \
  "git pull" "git stash" "git stash push -m x" "git stash pop" "git merge feat" "git merge --no-ff feat" \
  "git merge --squash feat" "git restore a.txt" "git clean -fd" "git tag v1" "git tag -a v1 -m x" \
  "git add ." "git worktree add ../shop.x" "git fetch origin feat:feat" "git config user.name x" \
  "git lg" "gh pr checkout 12" "gh pr create --fill" "gh -R acme/shop pr create" "gh pr merge 12" \
  "/usr/bin/git commit -m x" "git -c core.x=y commit -m x" "GIT_EDITOR=true git rebase --continue" \
  "command git push origin feat" "env FOO=1 git push --force"; do
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
denies orch0001 "$shop" $'git status\ngit push origin feat'
denies orch0001 "$shop" "echo \$(git stash)"
denies orch0001 "$shop" "x=\`git commit -m y\`"
denies orch0001 "$shop" "bash -c 'git commit -m x'"
denies orch0001 "$shop" "eval git push origin feat"
denies orch0001 "$shop" "{ git add -A; git commit -m x; }"
denies orch0001 "$shop" "if true; then git push -f; fi"
allows orch0001 "$shop" "git log 2>&1 | head -5 >/dev/null"
allows orch0001 "$shop" "echo 'git push' && echo \"git commit\""
allows orch0001 "$shop" "git status # git push"
allows orch0001 "$shop" $'cat <<\'EOF\'\ngit push\ngit commit -m x\nEOF\ngit status'
denies orch0001 "$shop" $'cat <<EOF >/dev/null\nnothing\nEOF\ngit push origin feat'

# The reason that Claude gets.
reason=$(guard orch0001 "$shop" "git checkout -b fix" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the reason names the command" '`git checkout -b fix`' "$reason"
has "the reason names the main checkout" "$shop" "$reason"
has "the reason: give it to the worker" "worker of that branch" "$reason"
eq "the event name" PreToolUse "$(guard orch0001 "$shop" "git commit -m x" | jq -r '.hookSpecificOutput.hookEventName')"

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
  "git branch -D old1 && git push origin feat" "git branch -m old1 new1" "git branch -f old1 HEAD" \
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

# A push of the main checkout's own branch ($cur, not a fixed name) passes; the host guards it.
for cmd in "git push" "git push origin" "git push origin $cur" "git push -u origin $cur" \
  "git push --set-upstream origin $cur" "git push origin $cur:$cur" "git push origin HEAD" \
  "git push origin HEAD:$cur" "git push origin refs/heads/$cur" "git push origin HEAD:refs/heads/$cur" \
  "git push -uq origin $cur" "git push --dry-run origin $cur" "git push origin -- $cur" \
  "cd src && git push origin $cur" "git fetch && git merge --ff-only feat && git push origin $cur"; do
  allows orch0001 "$shop" "$cmd"
done
# Any other branch or ref, all refs, tags, a delete, a force push; a word it cannot read.
for cmd in "git push origin feat" "git push -u origin feat" "git push origin $cur feat" \
  "git push origin $cur:feat" "git push origin feat:$cur" "git push origin HEAD:feat" "git push origin HEAD~1:$cur" "git push origin HEAD:HEAD" \
  "git push --all" "git push --all origin" "git push --branches origin" "git push --mirror origin" \
  "git push --tags" "git push origin --tags" "git push --follow-tags origin $cur" "git push origin v1" \
  "git push origin tag v1" "git push origin refs/tags/v1" "git push origin refs/wt-turns/x/head" \
  "git push origin HEAD:refs/wt-turns/x/head" "git push origin refs/notes/commits" \
  "git push origin 'refs/heads/*'" "git push origin ^$cur" \
  "git push --delete origin $cur" "git push -d origin feat" "git push origin :$cur" "git push origin --prune" \
  "git push -f" "git push -f origin $cur" "git push -uf origin $cur" "git push --force origin $cur" \
  "git push --force-with-lease origin $cur" "git push --force-with-lease=$cur origin $cur" \
  "git push --force-if-includes origin $cur" "git push origin +$cur" "git push origin +HEAD:$cur" \
  "git push origin \$b" "git push \"\$R\" $cur" "git push origin \$(git branch --show-current)" \
  "git -C \"\$X\" push origin $cur" "git -c push.default=matching push" "GIT_CONFIG_COUNT=1 git push" \
  "git push --repo=origin" "git push -o ci.skip origin $cur" "git push --recurse-submodules=on-demand"; do
  denies orch0001 "$shop" "$cmd"
done
reason=$(guard orch0001 "$shop" "git push --force origin $cur" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: a force push destroys history" "can destroy its history" "$reason"
reason=$(guard orch0001 "$shop" "git push origin :$cur" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: a delete destroys history" "a delete of $cur destroys its history" "$reason"
reason=$(guard orch0001 "$shop" "git push origin feat" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: another branch comes from its worker" "the push of \`feat\` comes from the worker of its branch" "$reason"
reason=$(guard orch0001 "$shop" "git push origin refs/wt-turns/x/head" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: not a branch" "is not a branch" "$reason"
has "the reason: it can push its own branch" "push the main checkout's own branch" "$reason"
# The config can make a plain push send more.
for cfg in "push.default matching" "push.followTags true" "remote.origin.push refs/heads/*:refs/heads/*" \
  "remote.origin.mirror true"; do
  git -C "$shop" config ${cfg% *} "${cfg#* }"
  denies orch0001 "$shop" "git push"
  git -C "$shop" config --unset ${cfg% *}
done
git -C "$shop" config push.default upstream
denies orch0001 "$shop" "git push"
git -C "$shop" config "branch.$cur.merge" "refs/heads/$cur"
allows orch0001 "$shop" "git push"
git -C "$shop" config --unset push.default
# A main checkout with no branch (detached): no push.
git -C "$shop" checkout -q --detach
denies orch0001 "$shop" "git push origin HEAD"
git -C "$shop" checkout -q "$cur"
allows orch0001 "$shop" "git push origin HEAD"

# A new remote passes (a repo with no remote, pushed to a new empty repo); a change or a removal
# of one, an existing name, a mirror or an option it does not know are denied.
url=git@github.com:acme/shop.git
for cmd in "git remote add origin $url" "git remote add -f origin $url" "git remote add --fetch origin $url" \
  "git remote add -t main origin $url" "git remote add -t main -t dev -m main origin $url" \
  "git remote add --track=main --master main origin $url" "git remote add -tmain origin $url" \
  "git remote add --no-tags origin $url" "git remote add origin $url -f" "git remote add -- origin $url" \
  "git -C $shop remote add origin $url" "cd src && git remote add origin $url" \
  "git remote add origin $url && git push -u origin $cur"; do
  allows orch0001 "$shop" "$cmd"
done
git -C "$shop" remote add origin "$url"
for cmd in "git remote add upstream git@github.com:acme/shop-up.git" "git remote -v add up $url" \
  "git remote -v show origin" "git remote get-url origin" "git remote"; do
  allows orch0001 "$shop" "$cmd"
done
for cmd in "git remote add origin $url" "git remote add -f origin git@github.com:acme/other.git" \
  "git remote add --mirror up $url" "git remote add --mirror=fetch up $url" "git remote add --mirror=push up $url" \
  "git remote add -v up $url" "git remote add -ft main up $url" "git remote add -t up $url" \
  "git remote add -t 'refs/heads/*' up $url" "git remote add -t a:b up $url" "git remote add -m -x up $url" \
  "git remote add up" "git remote add up $url extra" "git remote add '-x' $url" "git remote add 'a b' $url" \
  "git remote add \$R $url" "git remote add up \"\$U\"" "git -c remote.up.mirror=true remote add up $url" \
  "GIT_CONFIG_COUNT=1 git remote add up $url" "git -C \"\$X\" remote add up $url" \
  "git remote remove origin" "git remote rm origin" "git remote rename origin up" \
  "git remote set-url origin git@github.com:acme/other.git" "git remote set-url --add origin $url" \
  "git remote set-head origin main" "git remote set-branches origin main" "git remote prune origin" \
  "git remote update" "git remote -v remove origin" "git remote --verbose set-url origin $url"; do
  denies orch0001 "$shop" "$cmd"
done
reason=$(guard orch0001 "$shop" "git remote add origin $url" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: the remote exists" "the remote origin exists" "$reason"
has "the reason: it can add a remote" "add a new remote" "$reason"
reason=$(guard orch0001 "$shop" "git remote set-url origin $url" | jq -r '.hookSpecificOutput.permissionDecisionReason')
has "the deny: a remote is only added" "it changes or removes a remote" "$reason"
eq "the guard adds no remote" origin "$(git -C "$shop" remote)"
git -C "$shop" remote remove origin

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
