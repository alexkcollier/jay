#!/usr/bin/python3 -I
# Throwaway tmux spike for notes/paradigm.md. Private socket, fake HOME, clean env.
import os, pty, sys, time, subprocess, threading, fcntl, termios, struct, json

D = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.join(D, "home")
LOG = os.path.join(D, "events.log")
TMUX = "/opt/homebrew/bin/tmux"
SOCK = "jayspike"
ENV = {
    "HOME": HOME, "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "TMUX_TMPDIR": os.path.join(D, "sock"),
    "SHELL": "/bin/sh",
}
CONF = os.path.join(D, "spike.conf")
open(LOG, "w").close()

with open(CONF, "w") as f:
    f.write(f"""
set -g mouse on
set -g status on
set -g status-interval 1
set -g status-left-length 80
set -g status-left '#[fg=blue,bold] ◆ jay  #{{@agents}}  #{{@tasks}} '
set -g status-right '#(date +%H:%M:%S) '
set -g pane-border-status top
set -g pane-border-format ' #{{pane_title}} '
set -g allow-rename off
set -g extended-keys on
# Ctrl g: a key table like zellij's normal mode; one key, then back
bind -n C-g switch-client -T jay
bind -T jay Tab run-shell -b 'echo key-tab $(date +%s) >> {LOG}'
bind -T jay t select-window -t :=tasks
bind -T jay h select-pane -L
bind -T jay l select-pane -R
bind -T jay 2 select-pane -t :=hub.1
bind -T jay v run-shell -b 'echo key-v >> {LOG}'
set-hook -g session-window-changed 'run-shell -b "echo hook-window #{{window_name}} >> {LOG}"'
set-hook -g pane-focus-in 'run-shell -b "echo hook-focus #{{pane_id}} >> {LOG}"'
set -g focus-events on
""")

def tm(*args, check=True):
    t = time.perf_counter()
    r = subprocess.run([TMUX, "-L", SOCK, "-f", CONF, *args], env=ENV, capture_output=True, text=True)
    ms = (time.perf_counter() - t) * 1000
    if check and r.returncode != 0:
        print("FAIL", args, r.stderr.strip())
    return r.stdout.strip(), ms

def panes(target="jay"):
    out, _ = tm("list-panes", "-s", "-t", target, "-F",
                "#{pane_id} #{window_name} #{pane_left} #{pane_width}x#{pane_height} act=#{pane_active} dead=#{pane_dead} #{pane_title}")
    return out

PROG = os.path.join(D, "prog.py")
with open(PROG, "w") as f:
    f.write(r'''
import sys, os, time, signal, select, fcntl, termios, struct, tty
name = sys.argv[1]; log = sys.argv[2]
def size():
    r, c, _, _ = struct.unpack("HHHH", fcntl.ioctl(1, termios.TIOCGWINSZ, b"\0"*8)); return f"{c}x{r}"
def w(s):
    with open(log, "a") as f: f.write(f"{name} {s}\n")
signal.signal(signal.SIGWINCH, lambda *_: w("winch " + size()))
w("start " + size())
tty.setraw(0)
sys.stdout.write("\x1b[?1000h\x1b[?1006h"); sys.stdout.flush()
n = 0
while True:
    r, _, _ = select.select([0], [], [], 1)
    if r:
        b = os.read(0, 256)
        w("input " + repr(b))
    n += 1
    sys.stdout.write(f"\r\n{name} tick {n} {size()}"); sys.stdout.flush()
''')

def prog(name):
    return f"/usr/bin/python3 -I {PROG} {name} {LOG}"

def events(prefix=None):
    lines = open(LOG).read().splitlines()
    return [l for l in lines if prefix is None or l.startswith(prefix)]

# ---- T1: three-column layout
t0 = time.perf_counter()
_, a = tm("new-session", "-d", "-s", "jay", "-x", "200", "-y", "50", "-n", "hub", prog("list"))
_, b = tm("split-window", "-h", "-t", "jay:hub.0", "-l", "78%", prog("agent"))
_, c = tm("split-window", "-h", "-t", "jay:hub.1", "-l", "45%", prog("review"))
tm("select-pane", "-t", "jay:hub.0", "-T", "worktrees")
tm("select-pane", "-t", "jay:hub.1", "-T", "hub")
tm("select-pane", "-t", "jay:hub.2", "-T", "turns · shop")
print(f"T1 layout: new-session {a:.0f} ms, splits {b:.0f}+{c:.0f} ms, total {(time.perf_counter()-t0)*1000:.0f} ms")
print(panes())
ids = [l.split()[0] for l in panes().splitlines()]
LIST, AGENT, REVIEW = ids

# attach a real client through a pty (focus, keys, mouse and the status need one)
pid, fd = pty.fork()
if pid == 0:
    os.execve(TMUX, [TMUX, "-L", SOCK, "-f", CONF, "attach", "-t", "jay"], ENV)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
screen = bytearray()
def reader():
    while True:
        try:
            d = os.read(fd, 65536)
        except OSError:
            return
        if not d:
            return
        screen.extend(d)
threading.Thread(target=reader, daemon=True).start()
time.sleep(1.0)
print("clients:", tm("list-clients", "-F", "#{client_name} #{client_width}x#{client_height}")[0])

# ---- T2: swap the middle pane's program
out, ms = tm("respawn-pane", "-k", "-t", AGENT, prog("agentB"))
tm("select-pane", "-t", AGENT, "-T", "shop/fix-login")
time.sleep(0.5)
print(f"T2 respawn-pane -k: {ms:.0f} ms; same pane id: {AGENT in panes()}; agentB started: {bool(events('agentB start'))}")
print(panes())

# ---- T3: files over review and back (review keeps running in a hidden window)
before = len(events("review tick")) if False else None
out, ms1 = tm("new-window", "-d", "-n", "_stash", "-P", "-F", "#{pane_id}", prog("files"))
FILES = out
_, ms2 = tm("swap-pane", "-d", "-s", FILES, "-t", REVIEW)
time.sleep(1.2)
p = panes()
print(f"T3 files over review: new-window {ms1:.0f} ms + swap-pane {ms2:.0f} ms")
print(p)
cap, _ = tm("capture-pane", "-p", "-t", REVIEW)
print("   review still ticking while hidden:", cap.splitlines()[-1] if cap else "?")
_, ms3 = tm("swap-pane", "-d", "-s", FILES, "-t", REVIEW)
_, ms4 = tm("kill-pane", "-t", FILES)
time.sleep(0.5)
print(f"   back: swap-pane {ms3:.0f} ms + kill-pane {ms4:.0f} ms")
print(panes())
print("   review winch events:", [l for l in events("review winch")])

# ---- T4: focus a pane from outside (a script, not the client)
tm("select-pane", "-t", LIST)
time.sleep(0.2)
_, ms = tm("select-pane", "-t", AGENT)
time.sleep(0.3)
cl, _ = tm("display-message", "-p", "-c", tm("list-clients", "-F", "#{client_name}")[0], "#{pane_id}")
print(f"T4 select-pane from outside: {ms:.0f} ms; client's pane now {cl} (want {AGENT}); focus-in hook: {events('hook-focus')[-2:]}")
print("   panes marked active:", sum(1 for l in panes().splitlines() if 'act=1' in l and l.split()[1]=='hub'))

# ---- T5: status line fed by a script (push, no plugin)
screen.clear()
_, ms = tm("set", "-g", "@agents", "● 1 working  ○ 2 idle")
tm("set", "-g", "@tasks", "● web:5174")
_, ms2 = tm("refresh-client", "-S")
time.sleep(0.4)
seen = "working" in screen.decode("utf-8", "replace")
print(f"T5 status push: set {ms:.0f} ms + refresh-client -S {ms2:.0f} ms; client shows it: {seen}")

# ---- T6: Ctrl g Tab runs a script; no pane is made
n_before = len(panes().splitlines())
t = time.perf_counter()
os.write(fd, b"\x07\t")
for _ in range(100):
    if events("key-tab"):
        break
    time.sleep(0.01)
print(f"T6 Ctrl g Tab -> run-shell -b: {(time.perf_counter()-t)*1000:.0f} ms to the script; panes before/after: {n_before}/{len(panes().splitlines())}")

# ---- T7: hide review (the middle takes its width) and show it again, at 35 %
_, ms1 = tm("break-pane", "-d", "-s", REVIEW, "-n", "_review")
time.sleep(0.3)
print(f"T7 hide review: break-pane {ms1:.0f} ms")
print(panes())
_, ms2 = tm("join-pane", "-d", "-h", "-l", "35%", "-s", REVIEW, "-t", AGENT)
time.sleep(0.3)
print(f"   show: join-pane {ms2:.0f} ms")
print(panes())

# ---- T8: a tasks tab per worktree, a key goes to it by name; the hook sees the switch
tm("new-window", "-d", "-n", "tasks", "-c", "/tmp", prog("console"))
os.write(fd, b"\x07t")
time.sleep(0.4)
print("T8 Ctrl g t -> tasks window active:", tm("display-message", "-p", "#{window_name}")[0], "; hook:", events("hook-window")[-1:])
tm("select-window", "-t", "jay:=hub")
time.sleep(0.3)

# ---- T9: a click on an unfocused pane: does it focus AND reach the program?
tm("select-pane", "-t", LIST)
time.sleep(0.3)
geo = {l.split()[0]: l for l in panes().splitlines()}
out, _ = tm("display-message", "-p", "-t", AGENT, "#{pane_left} #{pane_top}")
x, y = [int(v) for v in out.split()]
open(LOG, "a").write("--- click\n")
cx, cy = x + 5, y + 5   # 0-based pane origin; SGR is 1-based
os.write(fd, f"\x1b[<0;{cx+1};{cy+1}M\x1b[<0;{cx+1};{cy+1}m".encode())
time.sleep(0.5)
act, _ = tm("display-message", "-p", "#{pane_id}")
got = [l for l in events() if l.startswith("agentB input")]
print(f"T9 click on unfocused middle pane: focus now {act} (want {AGENT}); program got the click: {got[-1:] if got else 'no'}")

# ---- T10: control mode gets events
cm = subprocess.Popen([TMUX, "-L", SOCK, "-f", CONF, "-C", "attach", "-t", "jay"], env=ENV,
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
time.sleep(0.5)
tm("select-pane", "-t", LIST)
tm("select-window", "-t", "jay:=tasks")
tm("select-window", "-t", "jay:=hub")
time.sleep(0.5)
cm.stdin.write("detach\n"); cm.stdin.flush()
try:
    outc = cm.communicate(timeout=3)[0]
except subprocess.TimeoutExpired:
    cm.kill(); outc = cm.communicate()[0]
evs = sorted({l.split()[0] for l in outc.splitlines() if l.startswith("%")})
print("T10 control mode event kinds:", evs)

# ---- T11: read a pane / type into a pane (dump-screen / write-chars)
_, ms1 = tm("capture-pane", "-p", "-t", LIST)
_, ms2 = tm("send-keys", "-t", LIST, "-l", "x")
_, ms3 = tm("list-panes", "-a", "-F", "#{pane_id}")
print(f"T11 capture-pane {ms1:.0f} ms, send-keys -l {ms2:.0f} ms, list-panes -a {ms3:.0f} ms")

# ---- T12: wide glyph in a pane: width that tmux gives
tm("respawn-pane", "-k", "-t", LIST, "/bin/sh -c 'printf \"✋x|\\n◆x|\\n\"; sleep 100'")
time.sleep(0.3)
cap, _ = tm("capture-pane", "-p", "-t", LIST)
print("T12 wide glyph rows:", [l for l in cap.splitlines() if "|" in l])

# ---- T13: detach the client and attach again: programs keep running
os.write(fd, b"\x02d")   # default prefix C-b d
time.sleep(0.5)
print("T13 after detach: clients =", repr(tm("list-clients")[0]), "; panes alive:", len(panes().splitlines()))

tm("kill-server", check=False)
print("server killed")
