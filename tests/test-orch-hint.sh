#!/bin/bash
# When a repo gets an orchestrator: the dim hint "n: orchestrator" on the main checkout row of a
# repo with two or more workers and none (jay-sidebar --rows), the main checkout row as the
# anchor of its repo in hide-idle mode (key a), and JAY_ORCHESTRATE: its parse
# (jay_orchestrate_wanted) and the pick that starts the orchestrator (jay-sidebar --act), with a
# stub claude.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" web="$root/web" docs="$root/docs" api="$root/api"
repo "$shop"
for b in a b c; do git -C "$shop" worktree add -q "$root/shop.$b" -b "$b"; done
repo "$web" && git -C "$web" worktree add -q "$root/web.x" -b x
repo "$docs"
repo "$api" && git -C "$api" worktree add -q "$root/api.y" -b y

# The list's cache of `jay all --json` (fresh, so the list does not refresh it).
rec() { # rec PATH MAIN BRANCH REPO [TASK]
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" --arg r "$4" --arg t "${5:-}" '{path: $p, main: $m,
    branch: $b, client: "acme", repo: $r, task: $t, symbols: "", git: {added: 0, deleted: 0,
    staged: false, modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
cache() { # cache [TASK of shop's main checkout]
  { rec "$shop" true main shop "${1:-}"
    for b in a b c; do rec "$root/shop.$b" false "$b" shop; done
    rec "$web" true main web; rec "$root/web.x" false x web
    rec "$docs" true main docs
    rec "$api" true main api; rec "$root/api.y" false y api; } >"$JAY_STATE/worktrees.ndjson"
}
mkdir -p "$JAY_STATE"
cache
touch "$JAY_STATE/prune.stamp"

now=$(($(date +%s) * 1000))
agent() { # agent ID CWD [STATE] [KIND]
  jq -nc --arg id "$1" --arg c "$2" --argjson t "$((now - 60000))" --arg st "${3:-done}" --arg k "${4:-background}" \
    '{kind: $k, id: $id, sessionId: ("sid-" + $id), name: ($id + "-name"), cwd: $c, startedAt: $t, state: $st, status: "idle"}'
}
orch_flags() { jq -nc --arg p "$(jay_orchestrator_prompt shop "$shop")" '["--name", "shop/main", "--append-system-prompt", $p]'; }
job 000000o1 "{\"cwd\": \"$shop\", \"respawnFlags\": $(orch_flags)}"
job 000000o2 "{\"cwd\": \"$shop\", \"worktreePath\": \"$root/shop.c\", \"respawnFlags\": $(orch_flags)}"
job 000000p1 "{\"cwd\": \"$shop\", \"respawnFlags\": [\"--name\", \"shop/plain\"]}"
agents() { stub_agents "$(printf '%s\n' "$@" | jq -sc .)"; }

rows=""
list() { rows=$(FZF_COLUMNS=${1:-80} jay-sidebar --rows); }
# The text of the worktree row of PATH, without its colors.
plain() { sed $'s/\e\\[[0-9;]*m//g'; }
treerow() { awk -F'\t' -v p="$1" '$1 == "wt" && $2 == p { print $3 }' <<<"$rows"; }
reporow() { awk -F'\t' -v p="$1" '$1 == "repo" && $2 == p { print $3 }' <<<"$rows"; }
HINT=$'\e[2m n: orchestrator'

# --- The hint ---
stub_agents '[]'
list
hasnt "0 workers: no hint" "orchestrator" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)"
list
hasnt "1 worker: no hint" "orchestrator" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")"
list
has "2 workers, no orchestrator: the hint, dim, at the end of the main checkout row" "$HINT"$'\e[0m' "$(treerow "$shop")"
eq "the hint is the end of the row" "n: orchestrator" "$(treerow "$shop" | plain | grep -o 'n: orchestrator$')"
hasnt "the hint: not on the repo row" "orchestrator" "$(reporow "$shop")"
hasnt "the hint: not on a worker's worktree row" "orchestrator" "$(treerow "$root/shop.a")"
hasnt "the hint: not on another repo" "orchestrator" "$(treerow "$web")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b" stopped)"
list
hasnt "2 workers, one stopped: no hint" "orchestrator" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")" \
  "$(agent 000000w3 "$root/shop.b" working interactive | jq -c 'del(.id)')"
list
has "3 workers, one interactive: the hint" "$HINT" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")" "$(agent 000000o1 "$shop")"
list
hasnt "2 workers and an orchestrator: no hint" "orchestrator" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")" "$(agent 000000p1 "$shop")"
list
has "2 workers and a plain agent in the main checkout: the hint" "$HINT" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")" "$(agent 000000o2 "$root/shop.c")"
list
hasnt "2 workers and an orchestrator in a worktree it entered: no hint" "orchestrator" "$(treerow "$shop")"
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000o2 "$root/shop.c")"
list
hasnt "the orchestrator in a worktree it entered is no worker" "orchestrator" "$(treerow "$shop")"

# The hint fits the list: it is cut, or it goes, before the row gets too wide.
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")"
for cols in 40 26 22 16; do
  list "$cols"
  line=$(treerow "$shop" | plain)
  ok "width $cols: the main checkout row fits ($line)" test "$(printf '%s' "$line" | wc -m)" -le $((cols - 1))
done
list 26
eq "a narrow list cuts the hint" "n: orchestra…" "$(treerow "$shop" | plain | grep -o 'n: .*$')"
list 16
hasnt "a very narrow list has no hint" "n:" "$(treerow "$shop" | plain)"
cache "plan the next release"
list 50
line=$(treerow "$shop" | plain)
has "with a task note: the note first" "· plan" "$line"
ok "with a task note: the row fits ($line)" test "$(printf '%s' "$line" | wc -m)" -le 49
cache

# --- hide-idle (a): the main checkout row is the anchor of its repo ---
agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w4 "$root/api.y")"
list
ok "all shown: the idle repo docs" test -n "$(reporow "$docs")"
: >"$JAY_STATE/sidebar.hide-idle"
list
eq "hide-idle: an idle repo goes" "" "$(reporow "$docs")$(treerow "$docs")"
ok "hide-idle: a repo with a worker shows" test -n "$(reporow "$shop")"
ok "hide-idle: its idle main checkout row stays" test -n "$(treerow "$shop")"
ok "hide-idle: main checkout row of a repo with another worktree row (no agents)" test -n "$(treerow "$web")"
ok "hide-idle: that worktree row" test -n "$(treerow "$root/web.x")"
ok "hide-idle: api's main checkout row" test -n "$(treerow "$api")"
order=$(awk -F'\t' '{ print $1 ":" $2 }' <<<"$rows" | grep -E ":($web|$root/web.x)\$" | tr '\n' ' ')
eq "hide-idle: the repo row, its main checkout, then its worktree" "repo:$web wt:$web wt:$root/web.x " "$order"
has "hide-idle: the last row counts the hidden repos only" "a shows 1 idle repo" "$(tail -1 <<<"$rows" | plain)"
hasnt "hide-idle: no idle main count" "idle main" "$rows"
rm -f "$JAY_STATE/sidebar.hide-idle"

# --- JAY_ORCHESTRATE: the setting ---
setting() { /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh"; printf "%s" "${JAY_ORCHESTRATE:-}"'; }
mkdir -p "$HOME/.config/jay"
printf '# the repos\nJAY_ORCHESTRATE = "shop:Acme/Web"\n' >"$HOME/.config/jay/config"
eq "the config file: JAY_ORCHESTRATE" "shop:Acme/Web" "$(setting)"
eq "the environment wins" "api" "$(JAY_ORCHESTRATE=api setting)"
printf 'WT_ORCHESTRATE=docs\n' >"$HOME/.config/jay/config"
eq "a WT_ name in the file works too" "docs" "$(setting)"
rm -f "$HOME/.config/jay/config"
eq "default: none" "" "$(setting)"
JAY_ORCHESTRATE="shop:Acme/Web"
ok "wanted: a repo name" jay_orchestrate_wanted acme shop
ok "wanted: any case" jay_orchestrate_wanted ACME Shop
ok "wanted: client/repo" jay_orchestrate_wanted acme web
no "not wanted: client/repo of another client" jay_orchestrate_wanted other web
no "not wanted: a repo not in the list" jay_orchestrate_wanted acme docs
no "not wanted: a part of a name" jay_orchestrate_wanted acme sho
no "not wanted: no repo" jay_orchestrate_wanted acme ""
JAY_ORCHESTRATE=" shop : web "
ok "wanted: spaces around the entries" jay_orchestrate_wanted acme web
JAY_ORCHESTRATE=""
no "not wanted: an empty list" jay_orchestrate_wanted acme shop
has "install.sh: the settings template names it" "# JAY_ORCHESTRATE=" "$(cat "$REPO/install.sh")"

# --- The start (n and the pick share it) and the pick, with a stub claude ---
stub claude '
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "--bg "*) printf "%s\n" "$PWD" >>"$STUB/bg.cwd"
            [[ -f "$STUB/bg.fail" ]] && { echo "Error: boom"; exit 1; }
            echo "backgrounded · 000000ff" ;;
  *) exit 1 ;;
esac'
bgs() { grep -c '^--bg ' "$STUB/claude.calls" 2>/dev/null || true; }
# wait_bg N: up to 5 s for the N-th --bg call.
wait_bg() { local i; for i in $(seq 50); do (($(bgs) >= $1)) && return 0; sleep 0.1; done; return 1; }
started=$(agent 000000ff "$HOME")
workers() { agents "$(agent 000000w1 "$root/shop.a" working)" "$(agent 000000w2 "$root/shop.b")" "$started" "$@"; }
workers
out=$(jay_orchestrator_start "$shop" shop main)
eq "start: claude's output" "backgrounded · 000000ff" "$out"
calls=$(cat "$STUB/claude.calls")
has "start: a background agent named <repo>/<branch>" "--bg --name shop/main --append-system-prompt You are the orchestrator of the repo shop, in its main checkout $shop" "$calls"
eq "start: in the main checkout" "$shop" "$(tail -1 "$STUB/bg.cwd")"
agents "$(agent 000000x1 "$HOME" done | jq -c '.name = "shop/main"')"
: >"$STUB/claude.calls"
jay_orchestrator_start "$shop" shop main >/dev/null
has "start: a name no agent has (jay_unique_name)" "--bg --name shop/main-2 " "$(cat "$STUB/claude.calls")"

pick() { jay-sidebar --act "$@" >/dev/null 2>&1; }
stamps() { rm -f "$JAY_STATE"/orchestrate.*; }
: >"$STUB/claude.calls"
workers
pick wt "$root/shop.a"
sleep 0.5
eq "no JAY_ORCHESTRATE: a pick starts nothing" 0 "$(bgs)"
export JAY_ORCHESTRATE=web
pick wt "$root/shop.a"
sleep 0.5
eq "a repo not in JAY_ORCHESTRATE: nothing" 0 "$(bgs)"
export JAY_ORCHESTRATE=docs:shop
pick wt "$root/shop.a"
ok "a pick of a worktree row of a listed repo: the orchestrator starts" wait_bg 1
has "the pick: the orchestrator prompt of the repo" "--name shop/main --append-system-prompt You are the orchestrator of the repo shop" "$(cat "$STUB/claude.calls")"
eq "the pick: in the main checkout" "$shop" "$(tail -1 "$STUB/bg.cwd")"
pick wt "$root/shop.b"
sleep 0.5
eq "a second pick within a minute: no second one" 1 "$(bgs)"
stamps
pick repo "$shop"
ok "a pick of the repo row: it starts" wait_bg 2
stamps
pick ag sid-000000w2
ok "a pick of an agent row of the repo: it starts" wait_bg 3
stamps
workers "$(agent 000000o1 "$shop")"
pick wt "$shop"
sleep 0.5
eq "the repo has an orchestrator: nothing" 3 "$(bgs)"
workers
printf '{"projects": {"%s": {"hasTrustDialogAccepted": false}}}\n' "$shop" >"$HOME/.claude.json"
pick wt "$shop"
sleep 0.5
eq "Claude does not trust the repo: nothing" 3 "$(bgs)"
ok "not trusted: no stamp, so a pick after n tries again" test -z "$(ls "$JAY_STATE"/orchestrate.* 2>/dev/null)"
printf '{"projects": {"%s": {"hasTrustDialogAccepted": true}}}\n' "$shop" >"$HOME/.claude.json"
touch "$STUB/bg.fail"
pick wt "$shop"
ok "a start that fails: claude ran" wait_bg 4
gone() { local i; for i in $(seq 50); do [[ -z "$(ls "$JAY_STATE"/orchestrate.* 2>/dev/null)" ]] && return 0; sleep 0.1; done; return 1; }
ok "a start that fails: the stamp goes, so the next pick tries again" gone
rm -f "$STUB/bg.fail"
pick wt "$root/shop.a"
ok "the next pick: it starts" wait_bg 5

finish
