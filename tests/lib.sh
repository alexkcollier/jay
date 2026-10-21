# Helpers for the shell tests (tests/run.sh). Each test file sources this first.
# A test runs in a fake HOME in a temporary folder, with the system PATH only. The scripts of
# bin/ and lib/ are links in the fake ~/.local, so they run as installed. Stubs in the same
# ~/.local/bin take the place of claude, zellij, wt, curl and terminal-notifier: no network, no
# notice, no session of the user's Claude or zellij. The stub claude answers from files in
# $STUB (see stub_agents).
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_NAME=$(basename "$0" .sh)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/wt-hub-test.XXXXXX") || exit 1
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

# The user's Claude, zellij and hub variables must not reach the scripts: an agent's
# CLAUDE_JOB_DIR changes the turn chain's name, and ZELLIJ* would point at a live session.
for _var in $(compgen -e | grep -E '^(CLAUDE|ANTHROPIC|ZELLIJ|WT_|GIT_)'); do unset "$_var"; done
unset _var
export HOME="$TMP/home" STUB="$TMP/stub"
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export WT_TERMINAL=none WT_HUB_SESSION=wt-hub-test-none LC_ALL=en_US.UTF-8
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/state" "$HOME/.claude/jobs" "$STUB"
printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' >"$HOME/.gitconfig"

# The scripts as a --link install has them.
link_install() {
  local f
  for f in "$REPO"/bin/*; do ln -sfn "$f" "$HOME/.local/bin/${f##*/}"; done
  ln -sfn "$REPO/lib/wt-lib.sh" "$HOME/.local/lib/wt-lib.sh"
}

# stub NAME BODY: a script NAME in ~/.local/bin that runs BODY (bash).
stub() {
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$STUB/%s.calls"\n%s\n' "$1" "$2" >"$HOME/.local/bin/$1"
  chmod +x "$HOME/.local/bin/$1"
}

stub claude '
case "${1:-} ${2:-}" in
  "agents --json") [[ -f "$STUB/agents.fail" ]] && exit 1; cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "agents --help") echo "  --all   With --json: also include completed"; echo "  --json  Print active sessions" ;;
  "--version "*) echo "2.1.306 (Claude Code)" ;;
  "--help "*) echo "  --bg, --background   Start the session in the background" ;;
  "attach --help" | "rm --help" | "logs --help") echo "Usage: claude $1 <id>" ;;
  "rm "*) exit 0 ;;
  *) exit 1 ;;
esac'
stub zellij '[[ "${1:-}" == --version ]] && echo "zellij 0.45.1"; [[ "${1:-}" == --version ]]'
stub wt 'exit 1'
stub curl 'exit 7'
stub terminal-notifier 'exit 0'

# stub_agents JSON: what `claude agents --json --all` prints.
stub_agents() { printf '%s\n' "$1" >"$STUB/agents.json"; }

# job ID JSON: the state.json of background agent ID.
job() { mkdir -p "$HOME/.claude/jobs/$1" && printf '%s\n' "$2" >"$HOME/.claude/jobs/$1/state.json"; }

# repo PATH: a git repo with one commit (a.txt).
repo() {
  mkdir -p "$1" && git -C "$1" init -q && printf 'one\n' >"$1/a.txt" \
    && git -C "$1" add a.txt && git -C "$1" commit -qm first
}

PASSES=0 FAILS=0
pass() { PASSES=$((PASSES + 1)); [[ -z "${VERBOSE:-}" ]] || printf '  ok    %s\n' "$1"; }
fail() {
  FAILS=$((FAILS + 1))
  printf '  FAIL  %s: %s\n' "$TEST_NAME" "$1"
  shift
  local line
  for line in "$@"; do printf '        %s\n' "$line"; done
}
# eq NAME EXPECTED ACTUAL
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2" "actual:   $3"; fi; }
# has NAME NEEDLE TEXT: TEXT has NEEDLE in it.
has() { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "missing: $2" "in:      $3"; fi; }
# hasnt NAME NEEDLE TEXT
hasnt() { if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "unwanted: $2" "in:       $3"; fi; }
# ok NAME COMMAND...: the command succeeds.
ok() { local name=$1; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name" "failed: $*"; fi; }
# no NAME COMMAND...: the command fails.
no() { local name=$1; shift; if "$@" >/dev/null 2>&1; then fail "$name" "succeeded: $*"; else pass "$name"; fi; }

finish() {
  printf '%-20s %3d passed, %d failed\n' "$TEST_NAME" "$PASSES" "$FAILS"
  ((FAILS == 0))
}
