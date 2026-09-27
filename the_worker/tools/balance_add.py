#!/usr/bin/env python3
"""balance_add.py — Safely add/update tunables in data/balance.json (file-locked, preserves order).
Usage:
  tools/balance_add.py <dotted.path> '<json value>' [<dotted.path> '<json value>' ...]
Example:
  tools/balance_add.py mundo.px_por_unidad 48 perception_ui.indicator_radius 14.0
Existing keys are overwritten; missing intermediate objects are created."""
import fcntl, json, os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "data", "balance.json")
args = sys.argv[1:]
if len(args) == 0 or len(args) % 2:
    print(__doc__); sys.exit(2)
with open("/tmp/the_worker_balance.lock", "w") as lk:
    fcntl.flock(lk, fcntl.LOCK_EX)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for i in range(0, len(args), 2):
        keys = args[i].split(".")
        node = data
        for k in keys[:-1]:
            node = node.setdefault(k, {})
        node[keys[-1]] = json.loads(args[i + 1])
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    json.load(open(tmp, encoding="utf-8"))
    os.replace(tmp, path)
print("balance.json updated:", ", ".join(args[0::2]))
