#!/bin/bash
# jay_jobs, jay_orch_ranks and jay_orchestrators (lib/jay-lib.sh), and the signs that the list
# (jay-sidebar --rows) draws from them: a cyan ◇ for the orchestrator of a repo, a yellow ◇ for an
# extra one, no ◇ for an agent without the orchestrator prompt or an interactive session, and
# "→ <branch>" for an orchestrator in a worktree it entered.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" web="$root/web"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.feat" -b feat
repo "$web" && git -C "$web" worktree add -q "$root/web.fix" -b fix

prompt=$(jay_orchestrator_prompt shop "$shop")
eq "the prompt starts with the mark" "$JAY_ORCH_MARK" "${prompt:0:${#JAY_ORCH_MARK}}"
# respawnFlags: the options a background agent started with (claude keeps them in state.json).
orch_flags() { jq -nc --arg p "$(jay_orchestrator_prompt "$1" "$2")" --arg n "$1/main" '["--name", $n, "--append-system-prompt", $p]'; }
job 0000000a "{\"cwd\": \"$shop\", \"respawnFlags\": $(orch_flags shop "$shop")}"
job 0000000b "{\"cwd\": \"$shop\", \"respawnFlags\": $(orch_flags shop "$shop")}"
job 0000000c "{\"cwd\": \"$shop\", \"respawnFlags\": [\"--name\", \"shop/main\"]}"
job 0000000d "{\"cwd\": \"$shop\", \"respawnFlags\": $(orch_flags shop "$shop")}"
# In a worktree it entered (EnterWorktree): cwd is its home, worktreePath the worktree.
job 0000000e "{\"cwd\": \"$web\", \"worktreePath\": \"$root/web.fix\", \"respawnFlags\": $(orch_flags web "$web")}"
# The orchestrator prompt in a worktree (not a main checkout).
job 0000000f "{\"cwd\": \"$root/shop.feat\", \"respawnFlags\": $(orch_flags shop "$shop")}"
now=$(($(date +%s) * 1000))
agent() { # agent ID NAME CWD STARTED [STATE]
  jq -nc --arg id "$1" --arg n "$2" --arg c "$3" --argjson t "$4" --arg st "${5:-done}" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, startedAt: $t, state: $st, status: "idle"}'
}
agents=$(jq -sc . <<EOF
$(agent 0000000a "shop/orch" "$shop" $((now - 300000)))
$(agent 0000000b "shop/copy" "$shop" $((now - 200000)))
$(agent 0000000c "shop/plain" "$shop" $((now - 100000)))
$(agent 0000000d "shop/stopped" "$shop" $((now - 900000)) stopped)
$(agent 0000000e "web/orch" "$root/web.fix" $((now - 60000)))
$(agent 0000000f "shop/feat" "$root/shop.feat" $((now - 60000)))
{"kind": "interactive", "sessionId": "sid-inter", "name": "shop/inter", "cwd": "$shop", "startedAt": $now, "status": "idle"}
EOF
)
stub_agents "$agents"

jobs=$(jay_jobs "$agents")
eq "jay_jobs: an agent with the prompt" true "$(jq '.["0000000a"].orch' <<<"$jobs")"
eq "jay_jobs: an agent without the prompt" false "$(jq '.["0000000c"].orch' <<<"$jobs")"
eq "jay_jobs: home of an agent in its own folder" null "$(jq '.["0000000a"].home' <<<"$jobs")"
eq "jay_jobs: home of an agent in a worktree it entered" "$web" "$(jq -r '.["0000000e"].home' <<<"$jobs")"
eq "jay_jobs: its worktree" "$root/web.fix" "$(jq -r '.["0000000e"].tree' <<<"$jobs")"
eq "jay_jobs: no entry for an interactive session" 6 "$(jq 'length' <<<"$jobs")"
eq "jay_jobs: no background agents" '{}' "$(jay_jobs '[{"kind": "interactive", "sessionId": "x"}]')"

ranks=$(jay_orch_ranks "$agents" "$jobs")
eq "the oldest with the prompt: rank 0 (cyan)" 0 "$(jq '.["sid-0000000a"].rank' <<<"$ranks")"
eq "a second one in the same main checkout: rank 1 (yellow)" 1 "$(jq '.["sid-0000000b"].rank' <<<"$ranks")"
eq "no prompt: no rank" null "$(jq '.["sid-0000000c"]' <<<"$ranks")"
eq "a stopped agent does not count" null "$(jq '.["sid-0000000d"]' <<<"$ranks")"
eq "interactive: no rank" null "$(jq '.["sid-inter"]' <<<"$ranks")"
eq "in a worktree it entered: ranked in its home" "$web 0" "$(jq -r '.["sid-0000000e"] | "\(.home) \(.rank)"' <<<"$ranks")"

expected=$(printf '%s\t%s\t%s\n' "$shop" 0000000a shop/orch "$web" 0000000e web/orch | sort)
eq "jay_orchestrators: one per main checkout, not one in a worktree" "$expected" "$(jay_orchestrators | sort)"
eq "jay_orchestrators <main checkout>" "$(printf '%s\t0000000a\tshop/orch' "$shop")" "$(jay_orchestrators "$shop")"
eq "jay agents --orchestrators <worktree of the repo>: nothing" "" "$(jay agents --orchestrators "$root/shop.feat")"
eq "jay agents --orchestrators <main checkout>" "$(printf '%s\t0000000a\tshop/orch' "$shop")" "$(jay agents --orchestrators "$shop")"
eq "the old name: wt agents through its shim" "$(printf '%s\t0000000a\tshop/orch' "$shop")" "$(wt-agents --orchestrators "$shop" 2>/dev/null)"
has "the shim says the new name" "wt agents is now: jay agents" "$(wt-agents --orchestrators "$shop" 2>&1 >/dev/null)"

# The list's rows, from a cache of `jay all --json` (fresh, so the list does not refresh it).
rec() { # rec PATH MAIN BRANCH REPO
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" --arg r "$4" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: $r, task: "", symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
mkdir -p "$JAY_STATE"
{ rec "$shop" true main shop; rec "$root/shop.feat" false feat shop
  rec "$web" true main web; rec "$root/web.fix" false fix web; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
CYAN=$'\e[36m◇ ' YELLOW=$'\e[33m◇ '
has "the orchestrator: cyan ◇" "${CYAN}"$'\e[0m'"shop/orch" "$(row sid-0000000a)"
has "an extra one: yellow ◇" "${YELLOW}"$'\e[0m'"shop/copy" "$(row sid-0000000b)"
hasnt "no prompt: no ◇" "◇" "$(row sid-0000000c)"
hasnt "interactive: no ◇" "◇" "$(row sid-inter)"
eq "a stopped agent has no row" "" "$(row sid-0000000d)"
has "in a worktree it entered: cyan ◇" "${CYAN}"$'\e[0m'"web/orch" "$(row sid-0000000e)"
has "in a worktree it entered: → its branch" "→ fix" "$(row sid-0000000e)"
hasnt "the prompt in a worktree: no ◇" "◇" "$(row sid-0000000f)"
# It stays under its main checkout: its row comes after web's repo and main checkout rows (both
# have the main checkout's path), before web.fix.
order=$(awk -F'\t' '{ print $2 }' <<<"$rows" | grep -E "^($web|$root/web.fix|sid-0000000e)\$" | tr '\n' ' ')
eq "in a worktree it entered: under its main checkout" "$web $web sid-0000000e $root/web.fix " "$order"

finish
