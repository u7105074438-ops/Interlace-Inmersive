#!/usr/bin/env python3
"""check_data.py — cross-file consistency checks for THE WORKER content data.

Checks whatever data files exist (rooms still being written are simply skipped or
cross-checked against the manual §22 room catalogue):
  rooms      unique ids, catalogue (§22) coverage, connects_to / leads_to targets, owners
  items      room contains/sells/items/produces/uniform and occupation tools use ITEM_IDS
  desks      named NPC desk_position == a seat they own in home_room (and vice versa);
             occupation desk_position == the seat the PLAYER gets in office_room
  occupations office_room/floor, promotion links, routine template, duties + waypoint sets
  duties     round waypoint sets: rooms exist, floors match, amounts match
  npcs       named: occupation/role, home_room, links, gatherings, routine locations
             generation: population arithmetic, slots, pinned desks, seat capacity, shifts
  loc        *_key strings exist in locale/strings.csv (warnings only)

Seat furniture = SEAT_TYPES. Seat "owner" values:
  <named npc id> | <investor id>  personal seat of that character
  "generated"      seat for a procedurally generated NPC of that room
  "vacant"         free seat, never assigned by the generator (the player's desk for a job)
  "player_start"   the player's first cubicle (wing_3b)
  "player"         the player's own property (exterior player_flat)
  "resident"       only in npc_house_* rooms: whoever lives in the visited house
Occupation desk rule: the seat at office_room/desk_position must be "vacant" or
"player_start"; or owned by the named NPC that is the job's single holder; or "generated"
when the job has a single generated holder whose slot pins that seat (desk_positions).

Usage:  tools/check_data.py [--scope FILE,FILE,...] [--no-warnings]
  --scope   exit status only counts errors whose involved files are ALL in the scope
            (paths relative to data/, e.g. occupations.json,rooms/p03.json).
Exit code: 0 = no counted errors, 1 = counted errors, 2 = a data file does not parse.
"""
import csv
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
MANUAL = os.path.join(os.path.dirname(ROOT), "docs", "THE_WORKER_MANUAL_MAESTRO.md")
STRINGS = os.path.join(ROOT, "locale", "strings.csv")

ITEM_IDS = {
    "keys_basic", "stamp", "phone", "own_card", "food_basic", "food_premium", "office_supplies",
    "product_pair", "product_box", "product_pallet_note", "foreign_document", "stolen_card",
    "cloned_card", "uniform_security", "uniform_cleaning", "uniform_maintenance", "balaclava",
    "executive_suit", "ownership_documents", "forged_authorization", "lockpick", "cutting_tools",
    "master_keys", "idea_copy", "cash_envelope", "delivery_note_forged", "safe_combination_note",
    "blackmail_file", "footage_copy", "sabotage_chemicals",
}
ITEM_LIST_KEYS = ("contains", "sells", "items", "produces")
SEAT_TYPES = {"cubicle", "desk", "executive_desk", "reception_desk", "workbench", "counter", "bench"}
SPECIAL_OWNERS = {"generated", "vacant", "player_start", "player"}
PLAYER_SEAT_OWNERS = {"vacant", "player_start"}
NAMED_LOCATION_TOKENS = {"assigned_zone"}
TEMPLATE_LOCATION_TOKENS = {
    "home_room", "absent", "assigned_zone", "assigned_round", "floor_meeting_room", "other_floor",
    "floor_toilets", "floor_pantry", "floor_copyroom",
}
DUTY_TYPES_FALLBACK = {"volume", "quota", "delivery", "round", "presentation"}


class Report:
    def __init__(self):
        self.items = []  # (level, files tuple, message)

    def error(self, files, msg):
        self.items.append(("ERROR", tuple(sorted(set(files))), msg))

    def warn(self, files, msg):
        self.items.append(("WARN", tuple(sorted(set(files))), msg))


R = Report()


def load(rel):
    path = os.path.join(DATA, rel)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print("PARSE ERROR %s: %s" % (rel, e))
        sys.exit(2)


def cells(e):
    size = e.get("size")
    if not size:
        size = [2, 2] if e.get("type") == "cubicle" else [1, 1]
    x0, y0 = e["pos"]
    return {(x, y) for x in range(x0, x0 + size[0]) for y in range(y0, y0 + size[1])}


def manual_room_ids():
    if not os.path.exists(MANUAL):
        return set()
    text = open(MANUAL, encoding="utf-8").read()
    try:
        sect = text[text.index("\n## 22. "):text.index("\n## 23. ")]
    except ValueError:
        return set()
    return set(re.findall(r"^\| `([a-z0-9_]+)` \|", sect, re.M))


# ─── Loading ────────────────────────────────────────────────────────────────

class World:
    def __init__(self):
        self.rooms = {}          # id -> room dict
        self.room_file = {}      # id -> "rooms/xxx.json"
        self.manual_ids = manual_room_ids()
        for path in sorted(glob.glob(os.path.join(DATA, "rooms", "*.json"))):
            rel = os.path.relpath(path, DATA)
            doc = load(rel)
            for r in doc.get("rooms", []):
                rid = r.get("id", "")
                if rid in self.rooms:
                    R.error([rel, self.room_file[rid]], "room id '%s' defined twice" % rid)
                self.rooms[rid] = r
                self.room_file[rid] = rel
        self.occ_doc = load("occupations.json") or {}
        self.occs = {o["id"]: o for o in self.occ_doc.get("occupations", [])}
        self.named_doc = load("npcs_named.json") or {}
        self.named = {n["id"]: n for n in self.named_doc.get("npcs", [])}
        self.gen = load("npcs_generation.json") or {}
        self.duties = load("duties.json") or {}
        inv = load("investors.json") or {}
        self.investors = {i["id"] for i in inv.get("investors", [])}
        arch = load("archetypes.json") or {}
        self.archetypes = {a["id"] for a in arch.get("archetypes", [])}
        sg = load("social_graph.json") or {}
        self.gatherings = {g["id"]: g for g in sg.get("gatherings", [])}
        self.roles = {r["id"]: r for r in self.gen.get("roles", [])}
        self.templates = {k for k in self.gen.get("routine_templates", {}) if not k.startswith("_")}
        self.waypoint_sets = {k: v for k, v in
                              self.duties.get("content", {}).get("round_waypoint_sets", {}).items()
                              if not k.startswith("_")}
        self.slots = []  # (department id, slot dict)
        for dep in self.gen.get("departments", []):
            for s in dep.get("slots", []):
                self.slots.append((dep["id"], s))

    def room_known(self, rid):
        return rid in self.rooms or rid in self.manual_ids

    def room_ref(self, rid):
        """Files involved when referencing a room (its file if it exists)."""
        return [self.room_file[rid]] if rid in self.rooms else []

    def seats_at(self, rid, pos):
        r = self.rooms.get(rid)
        if r is None:
            return []
        return [e for e in r.get("furniture", [])
                if e.get("type") in SEAT_TYPES and list(e.get("pos", [])) == list(pos)]

    def seats(self, rid):
        r = self.rooms.get(rid, {})
        return [e for e in r.get("furniture", []) if e.get("type") in SEAT_TYPES]

    def holders(self, occ_id):
        named = [n for n in self.named.values() if n.get("occupation") == occ_id]
        gen = [(d, s) for d, s in self.slots if s.get("occupation") == occ_id]
        return named, gen

    def seat_count(self, occ_id):
        named, gen = self.holders(occ_id)
        return len(named) + sum(int(s.get("count", 0)) for _, s in gen)


# ─── Rooms ──────────────────────────────────────────────────────────────────

def check_rooms(w):
    for rid in sorted(w.manual_ids - set(w.rooms)):
        R.warn(["rooms/"], "§22 room '%s' has no room file yet" % rid)
    for rid in sorted(set(w.rooms) - w.manual_ids) if w.manual_ids else []:
        R.error([w.room_file[rid]], "room '%s' is not in the §22 catalogue" % rid)
    valid_owners = set(w.named) | w.investors | SPECIAL_OWNERS
    for rid, r in w.rooms.items():
        f = w.room_file[rid]
        for target in r.get("connects_to", []):
            if not w.room_known(target):
                R.error([f], "%s.connects_to: unknown room '%s'" % (rid, target))
        if "owner" in r:
            check_owner(w, f, rid, "room", r["owner"], valid_owners)
        for sec in ("furniture", "interactables", "hiding_spots"):
            for i, e in enumerate(r.get(sec, [])):
                where = "%s.%s[%d]" % (rid, sec, i)
                if "owner" in e:
                    check_owner(w, f, rid, where, e["owner"], valid_owners)
                for target in e.get("leads_to", []) if isinstance(e.get("leads_to"), list) else []:
                    if not w.room_known(target):
                        R.error([f], "%s.leads_to: unknown room '%s'" % (where, target))
                check_item_fields(f, where, e)
        check_seat_overlap(f, rid, r)


def check_owner(w, f, rid, where, owner, valid):
    if owner in valid:
        return
    if owner == "resident" and rid.startswith("npc_house_"):
        return
    R.error([f], "%s: owner '%s' is not a named NPC, investor or %s"
            % (where, owner, "/".join(sorted(SPECIAL_OWNERS))))


def check_item_fields(f, where, e):
    for key in ITEM_LIST_KEYS:
        if key not in e:
            continue
        val = e[key]
        vals = val if isinstance(val, list) else [val]
        for v in vals:
            if v not in ITEM_IDS:
                R.error([f], "%s.%s: '%s' is not an item id" % (where, key, v))
    if "uniform" in e:
        u = e["uniform"]
        if u not in ITEM_IDS or not str(u).startswith("uniform_"):
            R.error([f], "%s.uniform: '%s' is not a uniform item id" % (where, u))


def check_seat_overlap(f, rid, r):
    size = r.get("size", [0, 0])
    taken = {}
    for i, e in enumerate(r.get("furniture", [])):
        if e.get("type") not in SEAT_TYPES:
            continue
        for c in cells(e):
            if size[0] and size[1] and not (0 <= c[0] < size[0] and 0 <= c[1] < size[1]):
                R.error([f], "%s.furniture[%d] (%s) leaves the room at %s" % (rid, i, e["type"], list(c)))
                break
            if c in taken:
                R.error([f], "%s.furniture[%d] overlaps seat furniture[%d] at %s" % (rid, i, taken[c], list(c)))
                break
            taken[c] = i


# ─── Named NPCs ─────────────────────────────────────────────────────────────

def check_named(w):
    f = "npcs_named.json"
    for nid, n in w.named.items():
        occ = n.get("occupation", "")
        if occ and occ not in w.occs:
            R.error([f, "occupations.json"], "%s.occupation '%s' does not exist" % (nid, occ))
        if not occ and n.get("role") not in w.roles:
            R.error([f, "npcs_generation.json"], "%s has no occupation and role '%s' is not in roles" % (nid, n.get("role")))
        fut = n.get("future_occupation")
        if fut and fut not in w.occs:
            R.error([f, "occupations.json"], "%s.future_occupation '%s' does not exist" % (nid, fut))
        if n.get("archetype") not in w.archetypes and w.archetypes:
            R.error([f, "archetypes.json"], "%s.archetype '%s' does not exist" % (nid, n.get("archetype")))
        if w.templates and n.get("routine_template") not in w.templates:
            R.error([f, "npcs_generation.json"], "%s.routine_template '%s' does not exist" % (nid, n.get("routine_template")))
        home = n.get("home_room", "")
        if not w.room_known(home):
            R.error([f], "%s.home_room '%s' does not exist" % (nid, home))
        addr = n.get("home_address")
        if addr and not w.room_known(addr):
            R.error([f], "%s.home_address '%s' does not exist" % (nid, addr))
        for o in n.get("routine_overrides", []):
            loc = o.get("location")
            if loc and loc not in NAMED_LOCATION_TOKENS and not w.room_known(loc):
                R.error([f], "%s.routine_overrides: unknown location '%s'" % (nid, loc))
        for g in n.get("gatherings", []):
            if w.gatherings and g not in w.gatherings:
                R.error([f, "social_graph.json"], "%s.gatherings: unknown '%s'" % (nid, g))
        for link in n.get("initial_links", []):
            to = link.get("to")
            if to not in w.named and to not in w.investors:
                R.error([f], "%s.initial_links: unknown target '%s'" % (nid, to))
        check_named_desk(w, nid, n)
    check_owned_seats(w)


def check_named_desk(w, nid, n):
    home, desk = n.get("home_room", ""), n.get("desk_position")
    if desk is None or home not in w.rooms:
        return
    files = ["npcs_named.json", w.room_file[home]]
    seats = w.seats_at(home, desk)
    if not seats:
        R.error(files, "%s.desk_position %s: no seat furniture there in %s (source of truth = room)" % (nid, desk, home))
    elif seats[0].get("owner") != nid:
        R.error(files, "%s.desk_position %s: seat in %s is owned by '%s'" % (nid, desk, home, seats[0].get("owner")))


def check_owned_seats(w):
    for rid, r in w.rooms.items():
        for e in w.seats(rid):
            owner = e.get("owner")
            if owner not in w.named:
                continue
            n = w.named[owner]
            if n.get("home_room") != rid or list(n.get("desk_position") or []) != list(e["pos"]):
                R.error([w.room_file[rid], "npcs_named.json"],
                        "%s: seat %s owned by %s but npcs_named says %s %s"
                        % (rid, e["pos"], owner, n.get("home_room"), n.get("desk_position")))


# ─── Occupations ────────────────────────────────────────────────────────────

def check_occupations(w):
    f = "occupations.json"
    for oid, o in w.occs.items():
        for key in ("promotes_to", "can_jump_to", "demotes_to", "lateral_to"):
            for t in o.get(key, []):
                if t not in w.occs:
                    R.error([f], "%s.%s: unknown occupation '%s'" % (oid, key, t))
        if w.templates and o.get("routine_template") not in w.templates:
            R.error([f, "npcs_generation.json"], "%s.routine_template '%s' does not exist" % (oid, o.get("routine_template")))
        for t in o.get("tools", []):
            if t not in ITEM_IDS:
                R.error([f], "%s.tools: '%s' is not an item id" % (oid, t))
        if w.seat_count(oid) == 0 and oid != "email_worker_3b":
            R.warn([f, "npcs_named.json", "npcs_generation.json"], "%s has no holder at the start of a run" % oid)
        check_occ_room(w, oid, o)
        check_occ_duties(w, oid, o)


def check_occ_room(w, oid, o):
    rid, desk = o.get("office_room", ""), o.get("desk_position")
    if not w.room_known(rid):
        R.error(["occupations.json"], "%s.office_room '%s' does not exist" % (oid, rid))
        return
    if rid not in w.rooms:
        R.warn(["occupations.json"], "%s.office_room '%s' has no room file yet (desk not checked)" % (oid, rid))
        return
    files = ["occupations.json", w.room_file[rid]]
    room = w.rooms[rid]
    if "floor" in o and room.get("floor") != o["floor"] and not room.get("floors"):
        R.error(files, "%s.floor %s != floor %s of %s" % (oid, o["floor"], room.get("floor"), rid))
    seats = w.seats_at(rid, desk or [-1, -1])
    if not seats:
        R.error(files, "%s.desk_position %s: no seat furniture there in %s" % (oid, desk, rid))
        return
    owner = seats[0].get("owner")
    if owner in PLAYER_SEAT_OWNERS:
        return
    single = w.seat_count(oid) == 1
    if owner in w.named:
        if w.named[owner].get("occupation") == oid and single:
            return
        R.error(files, "%s.desk_position %s is %s's seat, who is not the single holder of %s"
                % (oid, desk, owner, oid))
        return
    if owner == "generated" and single:
        _, gen = w.holders(oid)
        pins = [p for _, s in gen if s.get("room") == rid for p in s.get("desk_positions", [])]
        if list(desk) in [list(p) for p in pins]:
            return
        R.error(files + ["npcs_generation.json"],
                "%s.desk_position %s is a 'generated' seat: pin it in the holder's slot desk_positions" % (oid, desk))
        return
    R.error(files, "%s.desk_position %s: seat owner '%s' cannot be the player's desk (use 'vacant')" % (oid, desk, owner))


def check_occ_duties(w, oid, o):
    f = "occupations.json"
    types = {t["id"] for t in w.duties.get("duty_types", [])} or DUTY_TYPES_FALLBACK
    for d in o.get("duties", []):
        did = d.get("id")
        if d.get("type") not in types:
            R.error([f, "duties.json"], "%s.%s: unknown duty type '%s'" % (oid, did, d.get("type")))
        if d.get("type") != "round":
            continue
        ws = d.get("waypoint_set")
        if not ws:
            R.error([f], "%s.%s: round duty without waypoint_set" % (oid, did))
            continue
        if ws not in w.waypoint_sets:
            R.error([f, "duties.json"], "%s.%s: waypoint_set '%s' not in duties.json" % (oid, did, ws))
            continue
        wset = w.waypoint_sets[ws]
        if oid not in wset.get("occupations", []):
            R.error([f, "duties.json"], "%s.%s: waypoint set '%s' does not list %s" % (oid, did, ws, oid))
        expected = expected_amount(d, wset)
        if expected is not None and d.get("amount") != expected:
            R.error([f, "duties.json"], "%s.%s: amount %s != %s (stops of '%s')" % (oid, did, d.get("amount"), expected, ws))


def expected_amount(duty, wset):
    if duty.get("is_closing"):
        return len(duty.get("steps", [])) or None
    if "random_subset" in wset:
        return wset["random_subset"]
    pts = wset.get("waypoints", [])
    if wset.get("amount_unit") == "floors" and pts:
        return len({p.get("floor") for p in pts} - {pts[0].get("floor")})
    stops = {(p.get("room"), p.get("floor")) for p in wset.get("waypoints", [])}
    return len(stops)


# ─── Duties ─────────────────────────────────────────────────────────────────

def check_duties(w):
    f = "duties.json"
    for sid, s in w.waypoint_sets.items():
        pts = s.get("waypoints", [])
        if not pts:
            R.error([f], "round set '%s' has no waypoints" % sid)
        if "random_subset" in s and not 0 < s["random_subset"] <= len({p.get("room") for p in pts}):
            R.error([f], "round set '%s': random_subset out of range" % sid)
        for occ in s.get("occupations", []):
            if occ not in w.occs:
                R.error([f, "occupations.json"], "round set '%s': unknown occupation '%s'" % (sid, occ))
        for p in pts:
            rid, fl = p.get("room"), p.get("floor")
            if not w.room_known(rid):
                R.error([f], "round set '%s': unknown room '%s'" % (sid, rid))
                continue
            room = w.rooms.get(rid)
            if room is None or fl is None:
                continue
            span = room.get("floors")
            ok = (span[0] <= fl <= span[1]) if span else room.get("floor") == fl
            if not ok:
                R.error([f] + w.room_ref(rid), "round set '%s': %s is not on floor %s" % (sid, rid, fl))


# ─── Generation ─────────────────────────────────────────────────────────────

def check_generation(w):
    f = "npcs_generation.json"
    g = w.gen
    if not g:
        return
    top_total, gen_total = 0, 0
    for dep in g.get("departments", []):
        did = dep["id"]
        for rid in dep.get("rooms", []):
            if not w.room_known(rid):
                R.error([f], "department %s: unknown room '%s'" % (did, rid))
        for nid in dep.get("named_npcs", []):
            if nid not in w.named:
                R.error([f, "npcs_named.json"], "department %s: unknown named NPC '%s'" % (did, nid))
            elif w.named[nid].get("department") != did:
                R.error([f, "npcs_named.json"], "%s.department is '%s', listed in '%s'" % (nid, w.named[nid].get("department"), did))
        n_slots = sum(int(s.get("count", 0)) for s in dep.get("slots", []))
        if n_slots != dep.get("generated"):
            R.error([f], "department %s: slot counts %d != generated %s" % (did, n_slots, dep.get("generated")))
        own = dep.get("own_population", dep.get("population"))
        if len(dep.get("named_npcs", [])) + dep.get("generated", 0) != own:
            R.error([f], "department %s: named + generated != own_population/population" % did)
        gen_total += dep.get("generated", 0)
        if "parent" not in dep:
            top_total += dep.get("population", 0)
        for s in dep.get("slots", []):
            check_slot(w, did, s)
    if g.get("total_population_target") not in (None, top_total):
        R.error([f], "top-level populations sum %d != total_population_target" % top_total)
    if g.get("generated_count") not in (None, gen_total):
        R.error([f], "generated_count %s != sum of generated %d" % (g.get("generated_count"), gen_total))
    check_pins_and_capacity(w)
    check_shifts(w)
    check_generation_refs(w)


def check_slot(w, did, s):
    f = "npcs_generation.json"
    rid, occ = s.get("room", ""), s.get("occupation", "")
    if not w.room_known(rid):
        R.error([f], "department %s: slot room '%s' does not exist" % (did, rid))
    if occ and occ not in w.occs:
        R.error([f, "occupations.json"], "department %s: slot occupation '%s' does not exist" % (did, occ))
    if not occ and s.get("role") not in w.roles:
        R.error([f], "department %s: slot role '%s' not in roles" % (did, s.get("role")))
    tpl = s.get("routine_template")
    if tpl and w.templates and tpl not in w.templates:
        R.error([f], "department %s: slot routine_template '%s' does not exist" % (did, tpl))
    if len(s.get("desk_positions", [])) > int(s.get("count", 0)):
        R.error([f], "department %s: slot %s/%s pins more desks than its count" % (did, occ or s.get("role"), rid))


def check_pins_and_capacity(w):
    f = "npcs_generation.json"
    per_room_shift = Counter()
    pinned = defaultdict(list)
    for _, s in w.slots:
        per_room_shift[(s.get("room"), s.get("shift", "day"))] += int(s.get("count", 0))
        for p in s.get("desk_positions", []):
            pinned[s.get("room")].append(tuple(p))
    for rid, pins in pinned.items():
        for p, n in Counter(pins).items():
            seats = w.seats_at(rid, list(p))
            same_shift_dupe = n > 1 and not shift_shared(w, rid, p)
            if same_shift_dupe:
                R.error([f], "%s: desk %s pinned by %d slots of the same shift" % (rid, list(p), n))
            if rid not in w.rooms:
                continue
            if not seats:
                R.error([f, w.room_file[rid]], "%s: pinned desk %s is not a seat" % (rid, list(p)))
            elif seats[0].get("owner") != "generated":
                R.error([f, w.room_file[rid]], "%s: pinned desk %s is owned by '%s', not 'generated'" % (rid, list(p), seats[0].get("owner")))
    per_room = Counter()
    for (rid, _), n in per_room_shift.items():
        per_room[rid] = max(per_room[rid], n)  # day and night shifts share seats
    for rid, n in per_room.items():
        free = [e for e in w.seats(rid) if e.get("owner") == "generated"]
        if free and len(free) < n:
            R.warn([f, w.room_file.get(rid, "rooms/")], "%s: %d generated NPCs but only %d 'generated' seats" % (rid, n, len(free)))


def shift_shared(w, rid, p):
    shifts = [s.get("shift", "day") for _, s in w.slots
              if s.get("room") == rid and tuple(p) in [tuple(x) for x in s.get("desk_positions", [])]]
    return len(shifts) == len(set(shifts))


def check_shifts(w):
    f = "npcs_generation.json"
    night_guards = [s for _, s in w.slots if s.get("occupation") == "security_guard" and s.get("shift") == "night"]
    if not night_guards:
        R.error([f], "no generated security_guard with shift 'night' (only Ludmila covers nights)")
    mapping = w.gen.get("occupation_routine_template", {})
    for _, s in w.slots:
        occ = s.get("occupation")
        if occ == "cleaner" and s.get("routine_template", mapping.get("cleaner")) != "cleaning":
            R.error([f], "generated cleaner slot without routine 'cleaning'")
        if occ == "security_guard":
            want = mapping.get("security_guard", {}).get(s.get("shift", "day"))
            if s.get("routine_template", want) != want:
                R.error([f], "security_guard slot shift %s uses routine %s" % (s.get("shift"), s.get("routine_template")))
    for nid, n in w.named.items():
        if n.get("occupation") == "cleaner" and n.get("routine_template") != "cleaning":
            R.error(["npcs_named.json"], "%s is a cleaner without routine 'cleaning'" % nid)
        if n.get("occupation") == "security_guard":
            want = "guard_night" if n.get("shift") == "night" else "guard_day"
            if n.get("routine_template") != want:
                R.error(["npcs_named.json"], "%s: guard shift %s needs routine %s" % (nid, n.get("shift"), want))
    occ = w.occs.get("cleaner")
    if occ and occ.get("routine_template") != "cleaning":
        R.error(["occupations.json"], "cleaner.routine_template must be 'cleaning'")


def check_generation_refs(w):
    f = "npcs_generation.json"
    g = w.gen
    sup = g.get("link_generation", {}).get("hierarchy", {}).get("superior_by_room", {})
    for rid, who in sup.items():
        if not w.room_known(rid):
            R.error([f], "superior_by_room: unknown room '%s'" % rid)
        if who.startswith("occ:"):
            if who[4:] not in w.occs:
                R.error([f], "superior_by_room[%s]: unknown occupation '%s'" % (rid, who))
        elif who.startswith("role:"):
            if who[5:] not in w.roles:
                R.error([f], "superior_by_room[%s]: unknown role '%s'" % (rid, who))
        elif who not in w.named:
            R.error([f], "superior_by_room[%s]: unknown NPC '%s'" % (rid, who))
    mods = g.get("routine_common_modifiers", {})
    for rid in mods.get("slacker", {}).get("hideouts", []):
        if not w.room_known(rid):
            R.error([f], "slacker hideout '%s' does not exist" % rid)
    for tid, t in g.get("routine_templates", {}).items():
        if tid.startswith("_"):
            continue
        for seg in t.get("segments", []) + t.get("events", []):
            locs = [seg.get("location"), seg.get("via")] + list(seg.get("location_choices", {}))
            for loc in locs:
                if loc and loc not in TEMPLATE_LOCATION_TOKENS and not w.room_known(loc):
                    R.error([f], "routine %s: unknown location '%s'" % (tid, loc))
    for gid in g.get("gathering_membership", {}):
        if not gid.startswith("_") and w.gatherings and gid not in w.gatherings:
            R.error([f, "social_graph.json"], "gathering_membership: unknown gathering '%s'" % gid)
    for gid, gat in w.gatherings.items():
        if gat.get("room") and not w.room_known(gat["room"]):
            R.error(["social_graph.json"], "gathering %s: unknown room '%s'" % (gid, gat["room"]))


# ─── Localisation (warnings) ────────────────────────────────────────────────

def check_loc(w):
    if not os.path.exists(STRINGS):
        return
    with open(STRINGS, encoding="utf-8", newline="") as fh:
        keys = {row[0] for row in csv.reader(fh) if row}
    files = ["occupations.json", "npcs_named.json", "npcs_generation.json", "duties.json"]
    files += sorted({w.room_file[r] for r in w.rooms})
    for rel in files:
        doc = load(rel)
        missing = sorted({k for k in iter_keys(doc) if k not in keys})
        if missing:
            R.warn([rel], "%d loc keys missing from strings.csv: %s" % (len(missing), ", ".join(missing[:8]) + (" ..." if len(missing) > 8 else "")))


def iter_keys(v):
    if isinstance(v, dict):
        for k, x in v.items():
            if k.startswith("_"):
                continue
            if isinstance(x, str) and (k.endswith("_key") or k == "name_key"):
                yield x
            elif isinstance(x, list) and k.endswith("_keys"):
                for y in x:
                    if isinstance(y, str):
                        yield y
            else:
                yield from iter_keys(x)
    elif isinstance(v, list):
        for x in v:
            yield from iter_keys(x)


# ─── Main ───────────────────────────────────────────────────────────────────

def main(argv):
    scope = None
    show_warn = "--no-warnings" not in argv
    if "--scope" in argv:
        scope = set(argv[argv.index("--scope") + 1].split(","))
    w = World()
    for fn in (check_rooms, check_named, check_occupations, check_duties, check_generation, check_loc):
        fn(w)
    counted, per_file = 0, Counter()
    for level, files, msg in R.items:
        in_scope = scope is None or all(fl in scope for fl in files)
        if level == "ERROR" and in_scope:
            counted += 1
        if level == "WARN" and not show_warn:
            continue
        tag = level if in_scope or level == "WARN" else "ERROR(out of scope)"
        print("%-20s [%s] %s" % (tag, ", ".join(files), msg))
        for fl in files:
            per_file[(fl, level)] += 1
    print("\nSummary: %d rooms loaded (%d in §22), %d occupations, %d named NPCs, %d generation slots"
          % (len(w.rooms), len(w.manual_ids), len(w.occs), len(w.named), len(w.slots)))
    for (fl, level), n in sorted(per_file.items()):
        print("  %-28s %-5s %d" % (fl, level, n))
    total_err = sum(1 for lv, _, _ in R.items if lv == "ERROR")
    print("Errors: %d total, %d counted%s. Warnings: %d."
          % (total_err, counted, " (scope: %s)" % ",".join(sorted(scope)) if scope else "",
             sum(1 for lv, _, _ in R.items if lv == "WARN")))
    return 1 if counted else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
