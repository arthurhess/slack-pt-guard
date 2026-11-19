"""Spike client: python3 -I cdp.py <socket> <method> [params-json] [sessionId]
Special: `cdp.py <socket> eval '<js>'` evaluates in the first app.slack.com page."""
import sys, json, socket

def call(sock, method, params=None, session=None, timeout=30):
    s = socket.socket(socket.AF_UNIX); s.connect(sock)
    f = s.makefile("rwb")
    f.write(json.dumps({"method": method, "params": params or {}, "sessionId": session, "timeout": timeout}).encode() + b"\n"); f.flush()
    return json.loads(f.readline())

def page_session(sock):
    t = call(sock, "Target.getTargets")["result"]["targetInfos"]
    pages = [x for x in t if x["type"] == "page" and "slack.com" in x["url"]]
    return call(sock, "Target.attachToTarget", {"targetId": pages[0]["targetId"], "flatten": True})["result"]["sessionId"]

def ev(sock, js, timeout=30, session=None):
    session = session or page_session(sock)
    r = call(sock, "Runtime.evaluate", {"expression": js, "returnByValue": True, "awaitPromise": True}, session, timeout)
    return r.get("result", {}).get("result", {}).get("value", r)

if __name__ == "__main__":
    sock, method = sys.argv[1], sys.argv[2]
    if method == "nav":
        print(json.dumps(call(sock, "Page.navigate", {"url": sys.argv[3]}, page_session(sock)), indent=1))
    elif method == "js":
        print(json.dumps(ev(sock, open(sys.argv[3]).read()), indent=1, ensure_ascii=False))
    else:
        params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        sess = sys.argv[4] if len(sys.argv) > 4 else None
        print(json.dumps(call(sock, method, params, sess), indent=1, ensure_ascii=False))
