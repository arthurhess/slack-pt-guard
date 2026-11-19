"""Spike helper: start English Slack over --remote-debugging-pipe and expose the
pipe to local test scripts through a 0600 unix socket in a private directory.

Usage: python3 -I cdp_server.py <socket_path>
Client: send one JSON line {"method":..., "params":..., "sessionId":...}, read one JSON line back.
Events from Slack are appended to <socket_path>.events.log.
"""
import os, sys, json, socket, threading, subprocess

SLACK = "/Applications/Slack.app/Contents/MacOS/Slack"
PROFILE = os.path.expanduser("~/Library/Application Support/EnglishSlack")
sock_path = sys.argv[1]

to_r, to_w = os.pipe()
from_r, from_w = os.pipe()

def pre():
    os.dup2(to_r, 3)
    os.dup2(from_w, 4)

proc = subprocess.Popen([SLACK, "--remote-debugging-pipe", "--user-data-dir=" + PROFILE],
                        preexec_fn=pre, pass_fds=(3, 4), close_fds=True,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
os.close(to_r); os.close(from_w)

lock = threading.Lock()
pending = {}
next_id = [1000]
events = open(sock_path + ".events.log", "a", buffering=1)

def reader():
    buf = b""
    while True:
        chunk = os.read(from_r, 1 << 20)
        if not chunk:
            print("slack pipe closed", flush=True)
            os._exit(0)
        buf += chunk
        while b"\0" in buf:
            raw, buf = buf.split(b"\0", 1)
            msg = json.loads(raw)
            if "id" in msg and msg["id"] in pending:
                ev, box = pending.pop(msg["id"])
                box.append(msg); ev.set()
            else:
                events.write(json.dumps(msg)[:2000] + "\n")

threading.Thread(target=reader, daemon=True).start()

def call(req):
    with lock:
        i = next_id[0]; next_id[0] += 1
    ev, box = threading.Event(), []
    pending[i] = (ev, box)
    msg = {"id": i, "method": req["method"], "params": req.get("params", {})}
    if req.get("sessionId"):
        msg["sessionId"] = req["sessionId"]
    os.write(to_w, json.dumps(msg).encode() + b"\0")
    if not ev.wait(req.get("timeout", 30)):
        pending.pop(i, None)
        return {"error": "timeout"}
    return box[0]

if os.path.exists(sock_path):
    os.unlink(sock_path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
old = os.umask(0o177)
srv.bind(sock_path)
os.umask(old)
srv.listen(4)
print("ready pid", proc.pid, flush=True)

def handle(conn):
    with conn:
        f = conn.makefile("rwb")
        line = f.readline()
        if line:
            f.write(json.dumps(call(json.loads(line))).encode() + b"\n"); f.flush()

while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
