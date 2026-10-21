#!/bin/bash
# tests/run.sh [name...] — run the shell tests (tests/test-*.sh), each under /bin/bash (3.2 on
# macOS) in a fake HOME, with stubs for claude, zellij, wt and curl: no network, and nothing of
# your own install or sessions is touched. With names, only the test files whose name has one
# of them. VERBOSE=1 also lists the checks that pass. Exit 1 when a check fails.
cd "$(dirname "$0")" || exit 2
failed=0 ran=0
for test in test-*.sh; do
  if (($#)); then
    match=false
    for name in "$@"; do [[ "$test" == *"$name"* ]] && match=true; done
    $match || continue
  fi
  ran=$((ran + 1))
  /bin/bash "$test" || failed=$((failed + 1))
done
((ran > 0)) || { echo "tests/run.sh: no test matches: $*" >&2; exit 2; }
if ((failed > 0)); then
  echo "$failed of $ran test files failed."
  exit 1
fi
echo "All $ran test files passed."
