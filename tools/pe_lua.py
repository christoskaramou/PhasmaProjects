#!/usr/bin/env python3
"""Drive the running PhasmaEditor via its MCP HTTP endpoint.

Usage:
  python tools/pe_lua.py 'pe_log("hi")'        # inline Lua
  python tools/pe_lua.py --file path/to.lua    # Lua from file
  python tools/pe_lua.py --tool list           # list MCP tools
  python tools/pe_lua.py --tool <name> [--args '{"k":"v"}']
"""
import argparse
import json
import sys
import urllib.request

URL = "http://127.0.0.1:8765/mcp"


def rpc(method, params, rpc_id=1):
    body = json.dumps({"jsonrpc": "2.0", "id": rpc_id, "method": method, "params": params}).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("code", nargs="?", help="inline Lua code")
    ap.add_argument("--file", help="Lua file to execute")
    ap.add_argument("--tool", help="MCP tool name, or 'list'")
    ap.add_argument("--args", default="{}", help="JSON arguments for --tool")
    a = ap.parse_args()

    if a.tool == "list":
        out = rpc("tools/list", {})
        for t in out["result"]["tools"]:
            print(t["name"], "-", t.get("description", "")[:100])
        return

    if a.tool:
        out = rpc("tools/call", {"name": a.tool, "arguments": json.loads(a.args)})
    else:
        code = open(a.file, encoding="utf-8").read() if a.file else a.code
        if not code:
            ap.error("need Lua code, --file, or --tool")
        out = rpc("tools/call", {"name": "execute_lua", "arguments": {"code": code}})

    if "error" in out:
        print("RPC ERROR:", json.dumps(out["error"], indent=2))
        sys.exit(1)
    result = out.get("result", {})
    for item in result.get("content", []):
        if item.get("type") == "text":
            print(item["text"])
    if result.get("isError"):
        sys.exit(1)


if __name__ == "__main__":
    main()
