#!/usr/bin/env python3
"""loc_add.py — Safely upsert localisation keys into locale/strings.csv (file-locked).
Columns: keys,en,es   (English is the base language; Spanish is the shipped localisation.)
Usage:
  tools/loc_add.py KEY "English text" "Texto en español" [KEY2 "en2" "es2" ...]
  tools/loc_add.py --file some.csv      # a CSV with header keys,en,es ; rows are upserted
Existing keys are overwritten with the new text. Rows stay sorted by first insertion."""
import csv, fcntl, io, os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "locale", "strings.csv")
args = sys.argv[1:]
rows_in = []
if args[:1] == ["--file"]:
    with open(args[1], encoding="utf-8", newline="") as f:
        r = csv.reader(f)
        header = next(r)
        for row in r:
            if row and row[0].strip():
                rows_in.append((row[0].strip(), row[1] if len(row) > 1 else "", row[2] if len(row) > 2 else ""))
else:
    if len(args) == 0 or len(args) % 3:
        print(__doc__); sys.exit(2)
    for i in range(0, len(args), 3):
        rows_in.append((args[i], args[i + 1], args[i + 2]))
os.makedirs(os.path.dirname(path), exist_ok=True)
with open("/tmp/the_worker_locale.lock", "w") as lk:
    fcntl.flock(lk, fcntl.LOCK_EX)
    existing = {}
    order = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", newline="") as f:
            r = csv.reader(f)
            next(r, None)
            for row in r:
                if row and row[0]:
                    if row[0] not in existing:
                        order.append(row[0])
                    existing[row[0]] = (row[1] if len(row) > 1 else "", row[2] if len(row) > 2 else "")
    for k, en, es in rows_in:
        if k not in existing:
            order.append(k)
        existing[k] = (en, es)
    buf = io.StringIO()
    w = csv.writer(buf, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
    w.writerow(["keys", "en", "es"])
    for k in order:
        w.writerow([k, existing[k][0], existing[k][1]])
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(buf.getvalue())
    os.replace(tmp, path)
print(f"strings.csv: upserted {len(rows_in)} key(s); total {len(order)}")
