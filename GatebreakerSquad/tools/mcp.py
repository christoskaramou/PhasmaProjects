import json,sys,urllib.request
import os; U="http://127.0.0.1:%s/mcp"%os.environ["PORT"]; sid=None
def call(method,params,i=1):
    global sid
    h={"Content-Type":"application/json","Accept":"application/json, text/event-stream"}
    if sid: h["Mcp-Session-Id"]=sid
    r=urllib.request.urlopen(urllib.request.Request(U,json.dumps({"jsonrpc":"2.0","id":i,"method":method,"params":params}).encode(),h),timeout=30)
    sid=r.headers.get("Mcp-Session-Id") or sid
    return r.read().decode()
call("initialize",{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}})
for a in sys.argv[1:]:
    name,arg=a.split("=",1) if "=" in a else (a,"{}")
    print(call("tools/call",{"name":name,"arguments":json.loads(arg)},2)[:1500])
