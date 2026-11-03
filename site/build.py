#!/usr/bin/env python3
"""Bake .deciduous/graph.json and the commits it names into site/index.html.

    python3 site/build.py      # writes site/index.html from site/template.html
"""
import json, subprocess, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
graph = json.loads((root / ".deciduous/graph.json").read_text())

def git(*args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True).stdout

nodes = []
for n in graph["nodes"].values():
    m = n.get("metadata", {})
    nodes.append({
        "id": n["change_id"],
        "type": n["node_type"],
        "title": n["title"],
        "desc": n.get("description") or "",
        "prompt": m.get("prompt") or "",
        "confidence": m.get("confidence"),
        "commit": m.get("commit") or "",
        "files": m.get("files") or [],
        "t": n["created_at"],
    })
nodes.sort(key=lambda n: n["t"])
ids = {n["id"] for n in nodes}
edges = [{"s": e["from_change_id"], "t": e["to_change_id"], "r": e.get("rationale") or ""}
         for e in graph["edges"].values()
         if e["from_change_id"] in ids and e["to_change_id"] in ids]

commits = {}
for c in sorted({n["commit"] for n in nodes if n["commit"]}):
    out = git("show", "-s", "--format=%h%x00%s%x00%aI%x00%b", c).split("\x00")
    if len(out) >= 3:
        stat = git("show", "--shortstat", "--format=", c).strip()
        commits[c] = {"short": out[0], "subject": out[1], "date": out[2], "body": out[3].strip() if len(out) > 3 else "", "stat": stat}

log = [dict(zip(("hash", "date", "subject"), l.split("\x00")))
       for l in git("log", "--reverse", "--format=%h%x00%aI%x00%s").splitlines()]

data = {"nodes": nodes, "edges": edges, "commits": commits, "log": log}
blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
tpl = (root / "site/template.html").read_text()
(root / "site/index.html").write_text(tpl.replace("/*__DATA__*/null", blob))
print(f"{len(nodes)} nodes, {len(edges)} edges, {len(commits)} commits -> site/index.html")
