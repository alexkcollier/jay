#!/bin/bash
# Throwaway zellij session: time the CLI calls the hub uses most. Never touches the session jay.
set -u
D=$(cd "$(dirname "$0")" && pwd)
export HOME="$D/home"
for v in $(compgen -e | grep -E '^(ZELLIJ|CLAUDE|ANTHROPIC)'); do unset "$v"; done
S=jayspikez
cat >"$HOME/.config/zellij/config.kdl" <<'KDL'
show_startup_tips false
show_release_notes false
KDL
cat >"$D/z.kdl" <<'KDL'
layout {
    pane split_direction="vertical" {
        pane size="22%" name="worktrees" command="sleep" { args "1000"; }
        pane size="43%" name="hub" command="sleep" { args "1000"; }
        pane size="35%" name="review" command="sleep" { args "1000"; }
    }
}
KDL
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }
t() { local a b; a=$(ms); perl -e "alarm 5; exec @ARGV" "$@" </dev/null >/dev/null 2>&1; b=$(ms); printf '%-40s %4d ms\n' "${*:3:3}" $((b - a)); }

a=$(ms)
zellij attach --create-background "$S" options --default-layout "$D/z.kdl" >/dev/null 2>&1
for i in $(seq 50); do zellij -s "$S" action list-panes -j >/dev/null 2>&1 && break; sleep 0.1; done
b=$(ms); echo "session up: $((b - a)) ms"
for i in 1 2 3; do t zellij -s "$S" action list-panes -a -j -c; done
t zellij -s "$S" action rename-pane -p terminal_1 x
t zellij -s "$S" action move-focus left
t zellij -s "$S" action dump-screen -p terminal_1
t zellij -s "$S" action write-chars -p terminal_1 x
t zellij -s "$S" action list-tabs -j
t zellij -s "$S" pipe zjstatus::pipe::pipe_agents::x
p=$(zellij -s "$S" action new-pane --in-place --pane-id terminal_2 --close-on-exit -- sleep 100 2>/dev/null)
a=$(ms); zellij -s "$S" action new-pane --in-place --pane-id terminal_2 -- sleep 100 >/dev/null 2>&1; b=$(ms)
echo "new-pane --in-place                      $((b - a)) ms"
pkill -9 -f "zellij --server .*/$S\$"
sleep 0.5
pgrep -fl "zellij --server .*/$S\$" || echo "server killed"
perl -e "alarm 5; exec @ARGV" zellij delete-session --force "$S" >/dev/null 2>&1
