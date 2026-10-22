#!/bin/bash
# jay renew while the hub's middle column shows the agent: the pane follows to the new agent
# (jay_hub_retarget) before the old one stops, also in the hub of the other backend (a zellij hub
# and a tmux hub side by side, each with its own state). Without that, the old agent's `claude
# attach` ends when it stops and the pane says "You left this agent" with an empty target.
# Two real jay-pane agent processes, one per backend, with no multiplexer: the stub claude's
# attach runs until its agent stops.
source "$(dirname "$0")/lib.sh"
export JAY_ROOTS="$HOME/Documents/projects"
link_install
# No tmux server of the user: a socket of this test only.
export JAY_TMUX_SOCKET=jaytest$$ TMUX_TMPDIR=$TMP
unset TMUX TMUX_PANE
source "$HOME/.local/lib/jay-lib.sh"

shop="$HOME/Documents/projects/acme/shop"
repo "$shop"

# The stub claude: `--bg` starts an agent (its id from $STUB/next-id), `stop <id>` ends its
# attach clients and its process (no pid), `rm <id>` removes it; `attach <id>` leaves its id in
# $STUB/attach.log and runs until stopped. jay-pane puts mise's shims first on its PATH.
mkdir -p "$HOME/.local/share/mise/shims"
for d in "$HOME/.local/bin" "$HOME/.local/share/mise/shims"; do
  cat >"$d/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB/claude.calls"
jobs="$HOME/.claude/jobs"
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "--version "*) echo "2.1.306 (Claude Code)" ;;
  "--bg "*)
    id=$(cat "$STUB/next-id")
    shift
    flags=$(jq -nc '$ARGS.positional' --args -- "$@")
    name=$(jq -r 'index("--name") as $i | .[$i + 1]' <<<"$flags")
    mkdir -p "$jobs/$id"
    jq -nc --arg c "$PWD" --arg s "sid-$id" --argjson f "$flags" '{cwd: $c, sessionId: $s, respawnFlags: $f}' >"$jobs/$id/state.json"
    jq --arg i "$id" --arg n "$name" --arg c "$PWD" \
      '. + [{kind: "background", id: $i, sessionId: ("sid-" + $i), name: $n, cwd: $c, pid: 4242,
             startedAt: 0, state: "done", status: "idle"}]' "$STUB/agents.json" >"$STUB/a.tmp" \
      && mv "$STUB/a.tmp" "$STUB/agents.json"
    printf 'backgrounded · %s · %s\n' "$id" "$name" ;;
  "stop "*) jq --arg i "$2" 'map(if .id == $i then del(.pid) else . end)' "$STUB/agents.json" >"$STUB/a.tmp" \
    && mv "$STUB/a.tmp" "$STUB/agents.json"
    pkill -f "claude attach $2\$" ;;
  "rm "*) jq --arg i "$2" 'map(select(.id != $i))' "$STUB/agents.json" >"$STUB/a.tmp" && mv "$STUB/a.tmp" "$STUB/agents.json"
    rm -rf "${jobs:?}/$2" ;;
  "attach "*) printf '%s\n' "$2" >>"$STUB/attach.log"
    while sleep 0.2; do :; done ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$d/claude"
done

agent() { # agent ID NAME CWD
  jq -nc --arg id "$1" --arg n "$2" --arg c "$3" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, pid: 100, startedAt: 0, state: "done", status: "idle"}'
}
flags() { jq -nc --arg n "$1" --arg p "$2" '["--name", $n, "--append-system-prompt", $p]'; }
job 000000hb "{\"cwd\": \"$JAY_ROOTS\", \"sessionId\": \"sid-000000hb\",
  \"respawnFlags\": $(flags hub "You are the hub Claude of a worktree hub: an older text.")}"
job 000000o1 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-000000o1\",
  \"respawnFlags\": $(flags shop/main "You are the orchestrator of the repo shop, in its main checkout $shop. An older text.")}"
stub_agents "$(jq -sc . <<EOF
$(agent 000000hb hub "$JAY_ROOTS")
$(agent 000000o1 shop/main "$shop")
EOF
)"
mkdir -p "$JAY_STATE/tmux"
printf '000000hb\n' >"$JAY_HUB_CLAUDE_FILE"

# pane MUX: a jay-pane agent of that backend's hub, in its pane 7, with no multiplexer.
panes=()
pane() {
  local log="$TMP/pane-$1.log"
  if [[ "$1" == tmux ]]; then
    env JAY_MUX=tmux TMUX="$TMP/$JAY_TMUX_SOCKET,1,0" TMUX_PANE=%7 TERM=dumb \
      "$HOME/.local/bin/jay-pane" agent </dev/null >"$log" 2>&1 &
  else
    env ZELLIJ_PANE_ID=7 TERM=dumb "$HOME/.local/bin/jay-pane" agent </dev/null >"$log" 2>&1 &
  fi
  panes+=($!)
  disown $! # no "Terminated" line at the end
}
cleanup() {
  local p
  for p in ${panes[@]+"${panes[@]}"}; do jay_kill_children "$p"; kill "$p" 2>/dev/null; done
  pkill -f "$HOME/.*/claude attach" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
# within NAME SECS CMD...: CMD succeeds within SECS seconds.
within() {
  local name=$1 end=$((SECONDS + $2))
  shift 2
  while :; do
    "$@" >/dev/null 2>&1 && { pass "$name"; return 0; }
    ((SECONDS >= end)) && { fail "$name" "never: $*"; return 1; }
    sleep 0.2
  done
}
attached() { [[ "$(grep -c "^$1\$" "$STUB/attach.log" 2>/dev/null)" -ge "$2" ]]; }
target_of() { cut -f1 "$1/agent.target" 2>/dev/null; }

# --- The hub Claude, shown in a zellij hub and in a tmux hub; jay renew from the tmux hub ---
line=$(printf '000000hb\t%s\tbackground\thub' "$JAY_ROOTS")
printf '%s\n' "$line" >"$JAY_STATE/agent.target"
printf '%s\n' "$line" >"$JAY_STATE/tmux/agent.target"
pane zellij
pane tmux
within "both hubs attach the hub Claude" 10 attached 000000hb 2
echo 0000ee01 >"$STUB/next-id"
out=$(JAY_MUX=tmux jay-renew 000000hb 2>&1)
has "hub Claude: renewed" '"hub" is 0000ee01 now' "$out"
eq "hub Claude: its id file" 0000ee01 "$(jay_hub_claude_id)"
eq "hub Claude: the tmux hub's target" 0000ee01 "$(target_of "$JAY_STATE/tmux")"
eq "hub Claude: the zellij hub's target (the other backend)" 0000ee01 "$(target_of "$JAY_STATE")"
within "hub Claude: both middle columns attach the new agent" 10 attached 0000ee01 2
sleep 1
eq "hub Claude: the targets stay on the new agent" "0000ee01 0000ee01" \
  "$(target_of "$JAY_STATE") $(target_of "$JAY_STATE/tmux")"
hasnt "hub Claude: the zellij pane did not say you left" "You left this agent" "$(cat "$TMP/pane-zellij.log")"
hasnt "hub Claude: the tmux pane did not say you left" "You left this agent" "$(cat "$TMP/pane-tmux.log")"
eq "hub Claude: the target keeps its folder, kind and name" "$JAY_ROOTS background hub" \
  "$(cut -f2- "$JAY_STATE/agent.target" | tr '\t' ' ')"

# --- An orchestrator, from the zellij hub: the tmux hub's middle column and review follow ---
# A pick of it in the tmux hub (jay_hub_show; review has no pane here).
JAY_MUX=tmux bash -c 'source "$HOME/.local/lib/jay-lib.sh"; jay_hub_point agent "$1"' _ \
  "$(printf '000000o1\t%s\tbackground\tshop/main' "$shop")" >/dev/null
printf '%s\t000000o1\n' "$shop" >"$JAY_STATE/tmux/review.target"
within "orchestrator: the tmux hub attaches it" 10 attached 000000o1 1
echo 0000ee02 >"$STUB/next-id"
out=$(jay-renew 000000o1 2>&1)
has "orchestrator: renewed" '"shop/main" is 0000ee02 now' "$out"
eq "orchestrator: the zellij hub stays on the hub Claude" 0000ee01 "$(target_of "$JAY_STATE")"
eq "orchestrator: the tmux hub's target" 0000ee02 "$(target_of "$JAY_STATE/tmux")"
eq "orchestrator: the tmux hub's review" "$shop 0000ee02" "$(tr '\t' ' ' <"$JAY_STATE/tmux/review.target")"
within "orchestrator: the tmux middle column attaches the new agent" 10 attached 0000ee02 1
sleep 1
eq "orchestrator: the target stays on the new agent" 0000ee02 "$(target_of "$JAY_STATE/tmux")"
hasnt "orchestrator: the tmux pane did not say you left" "You left this agent" "$(cat "$TMP/pane-tmux.log")"

finish
