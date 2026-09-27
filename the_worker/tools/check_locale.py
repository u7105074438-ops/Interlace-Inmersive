#!/usr/bin/env python3
"""check_locale.py — Every localisation key used by data and code exists in locale/strings.csv
with both columns (en, es) filled (BUILD_NOTES §5).

Usage:
  tools/check_locale.py            # full report; exit 1 if any key is missing or incomplete
  tools/check_locale.py --sim      # only the simulation layer + data (src/autoload, src/simulation,
                                   # src/core, data/) decide the exit code; the rest is listed
  tools/check_locale.py --quiet    # summary lines only

What is checked:
  1. strings.csv itself: duplicated keys, empty EN or ES text.
  2. data/*.json and data/rooms/*.json: every value of a field named "*_key" / "key", every item of
     a "*_keys" list, and any ALL_CAPS_WITH_UNDERSCORES string value (comment keys "_*" skipped).
  3. src/**/*.gd: every string literal that looks like a key (ALL_CAPS_WITH_UNDERSCORES).
  4. Dynamic keys of the simulation layer, expanded from their real domains (DOMAINS below):
     "LEDGER_GRIEVANCE_%s" x every GRIEVANCE_* constant, "TIME_BAND_%s" x GameClock.BANDS, ...
  5. Every other key format ("PREFIX_%s", "PREFIX_%d") and every "PREFIX_" + value concatenation
     must match at least one key (weak check: the full domain is not known).
Lines are grouped by layer: sim (autoload/simulation/core), data, ui, world (world/entities), util.
"""
import csv, glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPS = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$")
CAPS_LITERAL = re.compile(r'"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)"')
FORMAT_LITERAL = re.compile(r'"([A-Z][A-Z0-9_]*%[sd][A-Z0-9_%sd]*)"')
PREFIX_LITERAL = re.compile(r'"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*_)"\s*\+')
CONST_STR = re.compile(r'^const\s+([A-Z0-9_]+)\s*(?::\s*[A-Za-z\[\]]+\s*)?:?=\s*"([^"]*)"', re.M)
CONST_ARRAY = re.compile(r'^const\s+([A-Z0-9_]+)\s*:\s*Array\[String\]\s*=\s*\[(.*?)\]', re.M | re.S)
# Literals that look like keys but are not localisation keys (ids, test fixtures, format tokens).
NOT_KEYS = {"R%d", "I_%s"}
ID_VALUE = re.compile(r"^[a-z0-9_]+$")
SIM_DIRS = ("src/autoload/", "src/simulation/", "src/core/")


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def layer_of(path):
    if path.startswith("data/"):
        return "data"
    if path.startswith(SIM_DIRS):
        return "sim"
    if path.startswith("src/ui/"):
        return "ui"
    if path.startswith(("src/world/", "src/entities/")):
        return "world"
    return "util"


def load_strings():
    keys, problems = {}, []
    with open(os.path.join(ROOT, "locale", "strings.csv"), encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if not row or not row[0]:
                continue
            if row[0] in keys:
                problems.append(f"duplicated key {row[0]}")
            en = row[1] if len(row) > 1 else ""
            es = row[2] if len(row) > 2 else ""
            if not en.strip() or not es.strip():
                problems.append(f"{row[0]}: empty {'EN' if not en.strip() else 'ES'} text")
            keys[row[0]] = (en, es)
    return keys, problems


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


# ─── Dominios de las claves dinámicas de la capa de simulación ────────────────────────────

def consts(path, name_regex):
    """String values of `const NAME := "value"` whose NAME matches name_regex."""
    rx = re.compile(name_regex)
    return [v for n, v in CONST_STR.findall(read(path)) if rx.fullmatch(n) and ID_VALUE.match(v)]


def array_const(path, name):
    """Values of `const NAME: Array[String] = [...]`, resolving constant names of the file."""
    text = read(path)
    table = dict(CONST_STR.findall(text))
    for n, body in CONST_ARRAY.findall(text):
        if n != name:
            continue
        out = []
        for token in [t.strip() for t in body.replace("\n", " ").split(",") if t.strip()]:
            out.append(token.strip('"') if token.startswith('"') else table.get(token, token))
        return out
    return []


def balance(path):
    node = json.loads(read("data/balance.json"))
    for part in path.split("."):
        node = node[part]
    return node


def balance_keys(path):
    return [k for k in balance(path) if not k.startswith("_")]


def balance_field(path, field):
    return sorted({str(v[field]) for k, v in balance(path).items()
                   if not k.startswith("_") and isinstance(v, dict) and field in v})


def blackmail_favours():
    return ["blackmail_" + d for d in array_const("src/simulation/blackmail.gd", "DEMAND_TYPES")]


def grievance_types():
    out = consts("src/autoload/npc_director.gd", r"GRIEVANCE_[A-Z_]+")
    for path in ("src/simulation/blackmail.gd", "src/simulation/interrogation.gd",
                 "src/simulation/duty_system.gd"):
        out += consts(path, r"GRIEVANCE_[A-Z_]+")
    return out


# (format, owner file, domain) — %s receives value.upper(); %d receives an int.
DOMAINS = [
    ("TIME_BAND_%s", "src/autoload/game_clock.gd",
     lambda: array_const("src/autoload/game_clock.gd", "BANDS")),
    ("NPC_STATE_%s", "src/autoload/npc_director.gd",
     lambda: consts("src/autoload/npc_director.gd", r"STATE_[A-Z_]+")
     + consts("src/core/npc_runtime.gd", r"STATE_[A-Z_]+")),
    ("NPC_LOD_%d", "src/autoload/npc_director.gd", lambda: [0, 1, 2]),
    ("LEDGER_GRIEVANCE_%s", "src/autoload/npc_director.gd", grievance_types),
    ("LEDGER_FAVOUR_%s", "src/autoload/npc_director.gd",
     lambda: consts("src/autoload/npc_director.gd", r"FAVOUR_[A-Z_]+") + blackmail_favours()),
    ("IDEA_BLOCK_%s", "src/autoload/idea_pool.gd",
     lambda: consts("src/autoload/idea_pool.gd", r"BLOCK_(?!KEY_FORMAT)[A-Z_]+")),
    ("DUTY_ERR_%s", "src/simulation/duty_system.gd",
     lambda: consts("src/simulation/duty_system.gd", r"ERR_[A-Z_]+")),
    ("UTILITY_ACTION_%s", "src/simulation/utility_ai.gd",
     lambda: array_const("src/simulation/utility_ai.gd", "ACTIONS")),
    ("BELIEF_FACT_%s", "src/autoload/belief_net.gd",
     lambda: array_const("src/autoload/belief_net.gd", "KNOWN_FACT_TYPES") + ["unknown"]),
    ("BELIEF_SOURCE_%s", "src/autoload/belief_net.gd",
     lambda: array_const("src/core/belief.gd", "SOURCES")
     + consts("src/autoload/belief_net.gd", r"NEWS_SOURCE")),
    ("INTERROGATION_OUTCOME_%s", "src/simulation/interrogation.gd",
     lambda: consts("src/simulation/interrogation.gd", r"OUTCOME_(?!KEY_PREFIX)[A-Z_]+")),
    ("SEARCH_OUTCOME_%s", "src/simulation/inventory.gd",
     lambda: consts("src/simulation/inventory.gd", r"OUTCOME_(?!KEY_FORMAT)[A-Z_]+")),
    ("HIDE_LOC_%s", "src/simulation/inventory.gd",
     lambda: balance_keys("inventario.escondites")),
    ("HIDE_LOC_%s_RISK", "src/simulation/inventory.gd",
     lambda: balance_keys("inventario.escondites")),
    ("HIDE_SECURITY_%s", "src/simulation/inventory.gd",
     lambda: balance_field("inventario.escondites", "nivel")),
    ("ALERT_LEVEL_%d", "src/autoload/security.gd",
     lambda: list(range(0, int(balance("seguridad.nivel_alerta_max")) + 1))),
    ("CONTACT_SOURCE_%s", "src/autoload/player_state.gd",
     lambda: array_const("src/simulation/player_records.gd", "SOURCES")),
]


def expand(fmt, value):
    return fmt % (value if isinstance(value, int) else str(value).upper())


# ─── Barridos ─────────────────────────────────────────────────────────────────────────

def scan_data(keys, missing):
    files = sorted(glob.glob(os.path.join(ROOT, "data", "*.json"))
                   + glob.glob(os.path.join(ROOT, "data", "rooms", "*.json")))
    for path in files:
        where = rel(path)
        walk(json.loads(read(where)), where, "", keys, missing)


def walk(node, where, trail, keys, missing):
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(k, str) and k.startswith("_"):
                continue
            here = f"{trail}.{k}"
            if isinstance(v, str) and (k.endswith("_key") or k == "key" or CAPS.match(v)):
                if v and v not in keys:
                    missing.append((where, v, here))
            elif isinstance(v, list) and isinstance(k, str) and k.endswith("_keys"):
                for x in v:
                    if isinstance(x, str) and x not in keys:
                        missing.append((where, x, here))
            walk(v, where, here, keys, missing)
    elif isinstance(node, list):
        for i, x in enumerate(node):
            if isinstance(x, str) and CAPS.match(x) and x not in keys:
                missing.append((where, x, f"{trail}[{i}]"))
            walk(x, where, f"{trail}[{i}]", keys, missing)


def code_without_comments(text):
    """The .gd text with whole-line comments blanked (line numbers are kept)."""
    return "\n".join("" if line.lstrip().startswith("#") else line for line in text.split("\n"))


def scan_code(keys, missing, weak):
    for path in sorted(glob.glob(os.path.join(ROOT, "src", "**", "*.gd"), recursive=True)):
        where = rel(path)
        text = code_without_comments(read(where))
        for m in CAPS_LITERAL.finditer(text):
            if m.group(1) not in keys and m.group(1) not in NOT_KEYS:
                line = text.count("\n", 0, m.start()) + 1
                missing.append((where, m.group(1), f"line {line}"))
        for m in FORMAT_LITERAL.finditer(text):
            fmt = m.group(1)
            if fmt in NOT_KEYS:
                continue
            rx = re.compile("^" + re.escape(fmt).replace("%s", "[A-Z0-9_]+").replace("%d", "[0-9]+") + "$")
            if not any(rx.match(k) for k in keys):
                weak.append((where, fmt, "format matches no key"))
        for m in PREFIX_LITERAL.finditer(text):
            if not any(k.startswith(m.group(1)) for k in keys):
                weak.append((where, m.group(1), "key prefix matches no key"))


def scan_domains(keys, missing):
    for fmt, owner, domain in DOMAINS:
        for value in domain():
            key = expand(fmt, value)
            if key not in keys:
                missing.append((owner, key, f"{fmt} × {value!r}"))


def main():
    sim_only = "--sim" in sys.argv
    quiet = "--quiet" in sys.argv
    keys, problems = load_strings()
    missing, weak = [], []
    scan_data(keys, missing)
    scan_code(keys, missing, weak)
    scan_domains(keys, missing)
    missing = sorted(set(missing))
    by_layer = {}
    for where, key, how in missing + weak:
        by_layer.setdefault(layer_of(where), []).append((where, key, how))
    if not quiet:
        for p in problems:
            print(f"[strings.csv] {p}")
        for layer in ("sim", "data", "ui", "world", "util"):
            for where, key, how in by_layer.get(layer, []):
                print(f"[{layer}] {where}: {key}  ({how})")
    counted = problems + [m for m in missing + weak
                          if not sim_only or layer_of(m[0]) in ("sim", "data")]
    print(f"strings.csv: {len(keys)} keys · {len(problems)} table problems · "
          + " · ".join(f"{layer}: {len(by_layer.get(layer, []))}"
                       for layer in ("sim", "data", "ui", "world", "util")))
    print("OK" if not counted else f"MISSING: {len(counted)}")
    return 1 if counted else 0


if __name__ == "__main__":
    sys.exit(main())
