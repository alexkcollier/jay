#!/bin/bash
# The leftovers of a branch that d on a worktree removes: its backup branches
# (jay_backup_branches: named in the confirm, deleted with the branch, jay_drop_backups) and the
# remote-tracking ref of its upstream when the remote has no such branch any more
# (jay_drop_gone_upstream: in the background, that one ref only). No network: the remote is a
# bare repo in the test folder, and a branch deleted there makes the ref stale.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" origin="$TMP/origin.git"
fix="$root/shop.fix" other="$root/shop.other"
b_fix=someone/acme-185-fix-thing
repo "$shop"
git init -q --bare "$origin"
git -C "$shop" remote add origin "$origin"
git -C "$shop" push -q -u origin main 2>/dev/null
git -C "$shop" worktree add -q "$fix" -b "$b_fix"
git -C "$shop" worktree add -q "$other" -b someone/acme-186-other
git -C "$fix" commit -q --allow-empty -m fix
git -C "$fix" push -q -u origin "$b_fix" 2>/dev/null
# Backup branches: of fix by its ticket, its full name and its last part; and others.
for b in backup/acme-185-pre-rebase backup/someone/acme-185-fix-thing backup/acme-185-fix-thing.2 \
  backup/acme-1850-x backup/acme-18 backup/acme-186-pre-rebase backup/zzz someone/acme-185-x; do
  git -C "$shop" branch "$b" "$b_fix"
done

backups() { jay_backup_branches "$1" "$2" | cut -f1 | tr '\n' ' ' | sed 's/ $//'; }
mine="backup/acme-185-fix-thing.2 backup/acme-185-pre-rebase backup/someone/acme-185-fix-thing"
eq "backups: by ticket, full name and last part; not acme-1850, acme-18, another ticket" "$mine" \
  "$(backups "$fix" "$b_fix")"
eq "backups: the commit" "$(git -C "$shop" rev-parse backup/zzz)" \
  "$(jay_backup_branches "$fix" "$b_fix" | awk -F'\t' '$1 == "backup/acme-185-pre-rebase" { print $2 }')"
eq "backups: the other worktree's" "backup/acme-186-pre-rebase" "$(backups "$other" someone/acme-186-other)"
eq "backups: no branch, none" "" "$(backups "$fix" "")"
# A ticket only at the start of the last part, and before - or _ or the end.
no "backups: release-1.2 has no ticket" _jay_backup_of release-1-x release-1.2
ok "backups: a ticket alone" _jay_backup_of acme-185-x acme-185
ok "backups: a ticket before _" _jay_backup_of acme-185_x x/acme-185_y
no "backups: no ticket in the middle" _jay_backup_of acme-185-x x/fix-acme-185
no "backups: a key needs a separator after it" _jay_backup_of acme-185x-y acme-185-y

eq "backups: the longest key that fits" 18 "$(_jay_backup_of acme-185-fix-thing.2 "$b_fix")"
# Another live worktree on the same ticket: a backup named by the ticket alone could be its, so
# it stays out; one named by the last part is still fix's.
git -C "$shop" worktree add -q "$root/shop.more" -b other/acme-185-followup
eq "backups: a ticket that another worktree has too is not enough" \
  "backup/acme-185-fix-thing.2 backup/someone/acme-185-fix-thing" "$(backups "$fix" "$b_fix")"
eq "backups: and the other worktree does not get fix's" "" "$(backups "$root/shop.more" other/acme-185-followup)"
git -C "$shop" worktree remove "$root/shop.more"
# A backup branch that a worktree has checked out is never one.
git -C "$shop" worktree add -q "$root/shop.old" backup/acme-185-pre-rebase
hasnt "backups: one that a worktree has checked out" "pre-rebase" "$(backups "$fix" "$b_fix")"
git -C "$shop" worktree remove "$root/shop.old"

# jay_drop_backups: only while the branch points where it did; notes how to bring it back.
git -C "$shop" branch backup/zzz-moved "$b_fix"
moved=$(git -C "$shop" rev-parse main)
has "drop: a branch that moved stays" "backup/zzz-moved: it moved, kept" \
  "$(jay_drop_backups "$fix" "backup/zzz-moved	$moved")"
ok "drop: it is there" git -C "$shop" rev-parse -q --verify refs/heads/backup/zzz-moved
git -C "$shop" branch -D -q backup/zzz-moved

# d on fix: wt removes the worktree and deletes the branch (merged); GitHub deleted the branch on
# the remote. Another stale ref (origin/someone/old) stays: no prune of the repo.
git -C "$shop" push -q origin main:someone/old 2>/dev/null
git -C "$shop" fetch -q origin
git --git-dir="$origin" branch -D -q "$b_fix" someone/old
stub_agents '[]'
stub wt '[[ "$1 $3" == "-C remove" ]] || exit 1
b=$(git -C "$2" symbolic-ref --short HEAD); m=$(git -C "$2" worktree list --porcelain | sed -n "1s/^worktree //p")
git -C "$m" worktree remove "$2" || exit 1
[[ -f "$STUB/keep-branch" ]] || git -C "$m" branch -D -q "$b"'
rec() { # rec PATH MAIN BRANCH
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" '{path: $p, main: $m, branch: $b, client: "acme",
    repo: "shop", task: "", symbols: "", git: {added: 0, deleted: 0, staged: false, modified: false,
    untracked: false, conflicted: false, operation: null, state: (if $m then "is_main" else "ahead" end),
    ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
keep=$root/shop.keep
git -C "$shop" worktree add -q "$keep" -b someone/acme-200-keep
git -C "$shop" branch backup/acme-200-pre-rebase someone/acme-200-keep
git -C "$keep" push -q -u origin someone/acme-200-keep 2>/dev/null
{ rec "$shop" true main; rec "$fix" false "$b_fix"; rec "$other" false someone/acme-186-other
  rec "$keep" false someone/acme-200-keep; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"

export TERM=dumb
# tty_run KEY CMD...: CMD in a pty 200 columns wide; it gets KEY after 1 s.
tty_run() {
  local key=$1
  shift
  (sleep 1; printf '%s' "$key") | script -q /dev/null sh -c 'stty cols 200; exec "$@"' sh "$@" 2>&1
}
# wait_log TEXT: up to 10 s until prune.log has TEXT.
wait_log() {
  local i
  for i in $(seq 100); do grep -qF -- "$1" "$JAY_STATE/prune.log" 2>/dev/null && return 0; sleep 0.1; done
  return 1
}
out=$(tty_run n jay-sidebar --remove wt "$fix")
short=$(git -C "$shop" rev-parse --short=7 backup/acme-185-pre-rebase)
has "confirm: names the backup branches" "  backup/acme-185-pre-rebase ($short)" "$out"
has "confirm: all three" "backup/someone/acme-185-fix-thing" "$out"
hasnt "confirm: not another ticket's" "acme-186" "$out"
has "confirm: only with the branch" "and its backup branches only with it" "$out"
ok "no: fix stays" test -d "$fix"
ok "no: the backups stay" git -C "$shop" rev-parse -q --verify refs/heads/backup/acme-185-pre-rebase

sha=$(git -C "$shop" rev-parse backup/acme-185-pre-rebase)
tty_run y jay-sidebar --remove wt "$fix" >/dev/null
ok "y: fix is removed" test ! -d "$fix"
no "y: its branch is gone" git -C "$shop" rev-parse -q --verify "refs/heads/$b_fix"
left=$(git -C "$shop" for-each-ref --format='%(refname:short)' refs/heads/backup/ | tr '\n' ' ')
eq "y: its backups are gone, the others stay" \
  "backup/acme-18 backup/acme-1850-x backup/acme-186-pre-rebase backup/acme-200-pre-rebase backup/zzz " "$left"
ok "y: someone/acme-185-x is no backup: it stays" git -C "$shop" rev-parse -q --verify refs/heads/someone/acme-185-x
has "y: prune.log says how to bring a backup back" "git branch backup/acme-185-pre-rebase $sha brings it back" \
  "$(cat "$JAY_STATE/prune.log")"
ok "y: the stale ref goes (in the background)" wait_log "stale ref refs/remotes/origin/$b_fix dropped"
no "y: origin/$b_fix is gone" git -C "$shop" rev-parse -q --verify "refs/remotes/origin/$b_fix"
ok "y: the other stale ref stays (no prune)" git -C "$shop" rev-parse -q --verify refs/remotes/origin/someone/old
ok "y: origin/main stays" git -C "$shop" rev-parse -q --verify refs/remotes/origin/main

# d on keep: wt keeps the branch (not merged), so its backup stays. Its remote does not answer
# (a hung ssh): d does not wait for it, and the timeout ends it.
touch "$STUB/keep-branch"
git -C "$shop" remote add slow "ssh://example.invalid/shop.git"
git -C "$shop" update-ref refs/remotes/slow/someone/acme-200-keep someone/acme-200-keep
git -C "$shop" config branch.someone/acme-200-keep.remote slow
# The sleep names this test's pid: the same test can run at the same time.
export GIT_SSH_COMMAND="sleep 31.$$;:" JAY_FETCH_TIMEOUT=6
start=$SECONDS
tty_run y jay-sidebar --remove wt "$keep" >/dev/null
took=$((SECONDS - start))
ok "keep: d does not wait for the remote ($took s)" test "$took" -lt 6
ok "keep: removed" test ! -d "$keep"
ok "keep: the branch stays" git -C "$shop" rev-parse -q --verify refs/heads/someone/acme-200-keep
ok "keep: its backup stays with it" git -C "$shop" rev-parse -q --verify refs/heads/backup/acme-200-pre-rebase
ok "keep: the timeout ends it" wait_log "git ls-remote slow failed: no answer in 6 s"
ok "keep: the ref stays" git -C "$shop" rev-parse -q --verify refs/remotes/slow/someone/acme-200-keep
sleep 0.3
eq "keep: no ssh is left" "" "$(pgrep -f "sleep 31\\.$$([^0-9]|\$)")"
unset GIT_SSH_COMMAND JAY_FETCH_TIMEOUT

# jay_drop_gone_upstream: the remote still has the branch: the ref stays; not a remote ref: nothing.
git -C "$shop" push -q origin main:someone/live 2>/dev/null
git -C "$shop" fetch -q origin
jay_drop_gone_upstream "$shop" origin refs/heads/someone/live refs/remotes/origin/someone/live
ok "upstream: the remote has it: it stays" git -C "$shop" rev-parse -q --verify refs/remotes/origin/someone/live
jay_drop_gone_upstream "$shop" . refs/heads/main refs/heads/main
ok "upstream: a local upstream: nothing" git -C "$shop" rev-parse -q --verify refs/heads/main
jay_drop_gone_upstream "$shop" origin refs/heads/someone/old refs/heads/someone/acme-185-x
ok "upstream: never a ref outside refs/remotes" git -C "$shop" rev-parse -q --verify refs/heads/someone/acme-185-x

finish
