#!/usr/bin/python3 -I
# pty-client.py OUT COLS ROWS CMD...: run CMD (a terminal client: jay, tmux attach, zellij) in a
# pty of COLS x ROWS and write its output to OUT. Keys to type: lines of hex appended to OUT.keys
# ("0731" is Ctrl g, then 1). Runs until killed or CMD ends.
# PTY_GHOSTTY=<secs>: answer the terminal queries in the output as Ghostty 1.3.2 does (XTVERSION,
# DA1, DA2, kitty graphics, colors, sizes). The first query of each kind at once (tmux's own, at
# the start), each later one <secs> late. The answers go to OUT.answers too.
import binascii, fcntl, os, pty, re, select, struct, sys, termios, time

out, cols, rows, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
late = os.environ.get("PTY_GHOSTTY")
pid, fd = pty.fork()
if pid == 0:
    os.environ.pop("PTY_GHOSTTY", None)
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
keys = out + ".keys"
open(keys, "a").close()
sent = 0

ST = b"\x1b\\"
QUERY = re.compile(
    rb"\x1b\[>0?q|\x1b\[0?c|\x1b\[>0?c|\x1b_G([^\x1b]*)\x1b\\|\x1b\](1[01]);\?(?:\x07|\x1b\\)"
    rb"|\x1b\[(1[468])t|\x1b\[\?u|\x1b\[\?996n|\x1b\[6n|\x1b\[\?(\d+)\$p")
seen = set()  # the kinds of query answered
pending = []  # (due, bytes)
tail = b""


def answer(m):
    q = m.group(0)
    if q.startswith(b"\x1b[>") and q.endswith(b"q"):
        return b"\x1bP>|ghostty 1.3.2" + ST
    if q.endswith(b"c"):
        return b"\x1b[>1;10;0c" if b">" in q else b"\x1b[?62;22;52c"
    if m.group(1) is not None:
        ident = re.search(rb"i=(\d+)", m.group(1))
        return b"\x1b_Gi=" + (ident.group(1) if ident else b"0") + b";OK" + ST
    if m.group(2) is not None:
        color = b"rgb:dcdc/d7d7/baba" if m.group(2) == b"10" else b"rgb:1f1f/1f1f/2828"
        return b"\x1b]" + m.group(2) + b";" + color + ST
    if m.group(3) is not None:
        size = {b"14": b"4;%d;%d" % (rows * 20, cols * 10), b"16": b"6;20;10",
                b"18": b"8;%d;%d" % (rows, cols)}[m.group(3)]
        return b"\x1b[" + size + b"t"
    if q == b"\x1b[?u":
        return b"\x1b[?0u"
    if q == b"\x1b[?996n":
        return b"\x1b[?997;1n"
    if q == b"\x1b[6n":
        return b"\x1b[1;1R"
    return b"\x1b[?" + m.group(4) + b";0$y"


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
            if late is not None:
                # A query can come in two reads: keep the end of the last one.
                buf, end = tail + data, 0
                for m in QUERY.finditer(buf):
                    # The kind: the query without a kitty image's id and data.
                    kind = m.group(0)[:3] if m.group(1) is not None else m.group(0)
                    pending.append((time.time() + (float(late) if kind in seen else 0), answer(m)))
                    seen.add(kind)
                    end = m.end()
                tail = buf[max(end, len(buf) - 256):]
        now = time.time()
        for due, reply in [p for p in pending if p[0] <= now]:
            os.write(fd, reply)
            with open(out + ".answers", "ab") as a:
                a.write(binascii.hexlify(reply) + b"\n")
        pending = [p for p in pending if p[0] > now]
        lines = open(keys).read().splitlines()
        for line in lines[sent:]:
            os.write(fd, binascii.unhexlify(line.strip()))
            time.sleep(0.05)
        sent = len(lines)
