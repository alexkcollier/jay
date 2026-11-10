#!/bin/bash
# jay new --model <m> --effort <e>: the values go to `claude --bg` as they are (a new worktree, a
# second agent in a worktree with -n, an idle agent with -a), nothing extra without them, the
# caller's ANTHROPIC_MODEL does not reach the agent, a flag with no value is a usage error, and
# a failure of claude gives its output on stderr and a non-zero exit.
source "$(dirname "$0")/lib.sh"
link_install

root="$HOME/Documents/projects/acme"
shop="$root/shop"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.eval" -b eval

# A claude that starts agents: each call goes to $STUB/claude.calls, one arg per line and a NUL
# after the call; the agent's ANTHROPIC*/CLAUDE* variables go to $STUB/claude.env.
# $STUB/bg.fail: `claude --bg` prints an error and exits 3.
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/bin/bash
{ printf '%s\n' "$@"; printf '\0'; } >>"$STUB/claude.calls"
case ${1:-} in
  agents) cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  --bg)
    { env | grep -E '^(ANTHROPIC|CLAUDE)' || true; } >"$STUB/claude.env"
    if [[ -f "$STUB/bg.fail" ]]; then echo "Error: something claude did not like"; exit 3; fi
    n=$(cat "$STUB/next" 2>/dev/null || echo 1); echo $((n + 1)) >"$STUB/next"
    printf 'backgrounded · b%07d · x\n' "$n" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME/.local/bin/claude"
# A wt that makes the worktree with --create (a new branch) and says where it is.
cat >"$HOME/.local/bin/wt" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$STUB/wt.calls"
if [[ "\$1" == switch ]]; then
  [[ " \$* " != *" --create "* ]] || git -C "$shop" worktree add -q "$root/shop.\$2" -b "\$2"
  echo "{\"path\": \"$root/shop.\$2\"}"
fi
exit 0
EOF
chmod +x "$HOME/.local/bin/wt"

# The args of the last --bg call (the last call: jay new asks `claude agents` before it), one
# per line, without empty lines.
last_bg() { tr '\0' '\n' <"$STUB/claude.calls" | awk '/^--bg$/ { s = "" } NF { s = s $0 "\n" } END { printf "%s", s }'; }
bg_count() { tr '\0' '\n' <"$STUB/claude.calls" | grep -c '^--bg$'; }
new() { (cd "$shop" && jay-new "$@"); }

# --- A new worktree, with a prompt ---
: >"$STUB/claude.calls"
out=$(new fresh --model sonnet --effort low -- write the tests 2>&1)
eq "a new worktree: exit 0" 0 "$?"
has "a new worktree: wt switch --create" "switch fresh --no-cd --format=json --create" "$(cat "$STUB/wt.calls")"
eq "the agent starts in the new worktree" 1 "$(bg_count)"
opts=$(last_bg | tr '\n' ' ')
has "a new worktree: --model sonnet" "--model sonnet " "$opts"
has "a new worktree: --effort low" "--effort low " "$opts"
has "the prompt comes after them" "--effort low write the tests" "$opts"
has "the output says the model and effort" "Started with: model sonnet, effort low" "$out"

# --- A second agent in an existing worktree (-n), only --model, a full id ---
: >"$STUB/claude.calls"
out=$(new eval -n judge --model claude-opus-5-5 -- judge it 2>&1)
opts=$(last_bg | tr '\n' ' ')
has "an existing worktree with -n: --model as it is" "--name shop/judge --model claude-opus-5-5 judge it" "$opts"
hasnt "only --model: no --effort" "--effort" "$opts"
has "only --model: the effort is the default" "Started with: model claude-opus-5-5, effort default" "$out"

# --- An idle agent (-a), the =value form ---
: >"$STUB/claude.calls"
out=$(new eval -a --effort=max --model=haiku 2>&1)
eq "-a: the args" "--bg|--name|shop/eval|--model|haiku|--effort|max" "$(last_bg | paste -sd '|' -)"
has "-a: the output" "Started with: model haiku, effort max" "$out"

# --- Without the flags: nothing extra ---
: >"$STUB/claude.calls"
out=$(new eval -a 2>&1)
eq "no flags: only --bg and --name" "--bg|--name|shop/eval" "$(last_bg | paste -sd '|' -)"
hasnt "no flags: no line on the model" "Started with" "$out"
new eval -- a prompt >/dev/null 2>&1
opts=$(last_bg | tr '\n' ' ')
hasnt "no flags, a prompt: no --model" "--model" "$opts"
hasnt "no flags, a prompt: no --effort" "--effort" "$opts"

# --- The caller's ANTHROPIC_MODEL and CLAUDE* do not reach the agent ---
(cd "$shop" && ANTHROPIC_MODEL=claude-haiku-5-5 CLAUDE_CODE_EFFORT_LEVEL=max jay-new eval -a) >/dev/null 2>&1
eq "the agent's env: no ANTHROPIC*/CLAUDE*" "" "$(cat "$STUB/claude.env")"
(cd "$shop" && ANTHROPIC_MODEL=claude-haiku-5-5 jay-new eval -a --model sonnet) >/dev/null 2>&1
eq "with --model: still no ANTHROPIC_MODEL" "" "$(cat "$STUB/claude.env")"
has "with --model: the flag" "--model sonnet" "$(last_bg | tr '\n' ' ')"

# --- A flag with no value: a usage error, no worktree, no agent ---
: >"$STUB/claude.calls"
for args in "eval -a --model" "eval -a --effort" "eval --model -- x" "eval --effort -a" "eval -a --model=" \
  "eval -a --model ''"; do
  eval "set -- $args"
  out=$(new "$@" 2>&1)
  rc=$?
  eq "jay new $args: exit 2" 2 "$rc"
  has "jay new $args: it says which" "needs a value" "$out"
done
out=$(new eval -n 2>&1)
eq "-n with no value: exit 2 (not an unbound variable)" 2 "$?"
eq "no agent starts" 0 "$(bg_count)"

# --- The flags without a prompt or -a: a usage error before the worktree ---
out=$(new eval --model sonnet 2>&1)
eq "--model without an agent: exit 2" 2 "$?"
has "it says why" "give a prompt (-- ...) or -a" "$out"
eq "no agent starts for it" 0 "$(bg_count)"

# --- A failure of claude: its output on stderr, its exit code ---
touch "$STUB/bg.fail"
err=$(new eval -a --model bogus 2>&1 >/dev/null)
rc=$?
eq "claude fails: jay new exits with its code" 3 "$rc"
has "claude's error on stderr" "Error: something claude did not like" "$err"
out=$(new eval -a --model bogus 2>/dev/null)
hasnt "claude fails: no 'Started with' line" "Started with" "$out"
rm -f "$STUB/bg.fail"

finish
