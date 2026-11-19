"""Spike: inject detect.js + guard.js into English Slack's page now and on future loads."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from cdp import call, page_session

sock = sys.argv[1]
root = os.path.join(os.path.dirname(__file__), "..", "guard")
src = open(os.path.join(root, "detect.js")).read() + "\n" + open(os.path.join(root, "guard.js")).read()
sid = page_session(sock)
print(call(sock, "Page.addScriptToEvaluateOnNewDocument", {"source": src}, sid).get("result"))
r = call(sock, "Runtime.evaluate", {"expression": src + "\n;JSON.stringify(window.__ptGuard)", "returnByValue": True}, sid)
print(r.get("result", {}).get("result", {}).get("value"), r.get("result", {}).get("exceptionDetails", ""))
