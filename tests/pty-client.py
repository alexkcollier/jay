#!/usr/bin/python3 -I
# pty-client.py OUT COLS ROWS CMD...: run CMD (a terminal client: jay, tmux attach, zellij) in a
# pty of COLS x ROWS and write its output to OUT. Keys to type: lines of hex appended to OUT.keys
# ("0731" is Ctrl g, then 1). Runs until killed or CMD ends.
import binascii, fcntl, os, pty, select, struct, sys, termios, time

out, cols, rows, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
keys = out + ".keys"
open(keys, "a").close()
sent = 0
with open(out, "ab") as f:
    while True:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            f.write(data)
            f.flush()
        lines = open(keys).read().splitlines()
        for line in lines[sent:]:
            os.write(fd, binascii.unhexlify(line.strip()))
            time.sleep(0.05)
        sent = len(lines)
