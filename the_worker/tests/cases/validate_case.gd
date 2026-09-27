# validate_case.gd — Cuerpo de test_validate: formato exacto de errores y clases de src/core.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Registros de ejemplo copiados de la Parte IX del manual (§26, §27, §28, §29, §32.4), en JSON
## para que lleguen igual que desde data/ (números como float).

const OCCUPATION_JSON := """{
	"id": "email_worker_3b", "name_key": "OCC_EMAIL_WORKER", "rank": 1, "tier": 1,
	"clearance": 1, "daily_wage": 30, "office_room": "wing_3b", "desk_position": [4, 5],
	"computer_tier": 1, "personnel_file_level": 1,
	"duties": [{ "id": "duty_emails_r1", "type": "volume", "subtype": "emails", "amount": 8,
		"time_cost_minutes": 45, "assist_time_cost_minutes": 5, "deadline_hour": 18,
		"fail_penalty": "warning" }],
	"tools": ["keys_basic", "stamp"], "special_access": [],
	"opportunities": ["watch_colleagues_close", "learn_building_routines"],
	"risks": ["eleven_permanent_witnesses", "floor_chief_patrols"],
	"promotes_to": ["order_filer", "copy_operator"], "can_jump_to": ["mail_courier"],
	"demotes_to": ["eternal_intern"], "min_reputation": 0, "silhouette": "tier_1",
	"_nota": "comentario que debe ignorarse"
}"""

const ROOM_JSON := """{
	"id": "wing_3b", "name_key": "ROOM_WING_3B", "floor": 3, "wing": "B",
	"clearance_required": 1, "special_access": [], "art_band": "the_pit", "kit": "open_office",
	"ambient_sound": "office_hum", "ambient_noise_level": 0.2, "has_cameras": false,
	"camera_positions": [], "size": [20, 14],
	"furniture": [
		{ "type": "cubicle", "pos": [4, 2],  "rotation": 0, "owner": "npc_debbie_foyle" },
		{ "type": "cubicle", "pos": [4, 5],  "rotation": 0, "owner": "player_start" },
		{ "type": "cubicle", "pos": [4, 8],  "rotation": 0, "owner": "npc_george_penn" },
		{ "type": "cubicle", "pos": [8, 2],  "rotation": 0, "owner": "npc_nate_brackley" },
		{ "type": "cubicle", "pos": [8, 5],  "rotation": 0, "owner": "npc_claudia_reeves" },
		{ "type": "cubicle", "pos": [8, 8],  "rotation": 0, "owner": "npc_sonia_vail" },
		{ "type": "cubicle", "pos": [12, 2], "rotation": 0, "owner": "generated" },
		{ "type": "cubicle", "pos": [12, 5], "rotation": 0, "owner": "generated" },
		{ "type": "cubicle", "pos": [12, 8], "rotation": 0, "owner": "generated" },
		{ "type": "cubicle", "pos": [16, 2], "rotation": 0, "owner": "generated" },
		{ "type": "cubicle", "pos": [16, 5], "rotation": 0, "owner": "generated" },
		{ "type": "cubicle", "pos": [16, 8], "rotation": 0, "owner": "generated" },
		{ "type": "filing_cabinet", "pos": [1, 1],  "rotation": 90 },
		{ "type": "printer",        "pos": [18, 3], "rotation": 180 },
		{ "type": "motivational_poster", "pos": [10, 0], "rotation": 0 }
	],
	"hiding_spots": [
		{ "id": "hide_3b_desk",   "type": "under_desk",     "pos": [4, 5] },
		{ "id": "hide_3b_closet", "type": "supply_closet",  "pos": [18, 12] }
	],
	"interactables": [
		{ "id": "player_desk", "type": "desk", "pos": [4, 5],
			"contains": ["keys_basic", "stamp"], "has_computer": true },
		{ "id": "claudia_computer", "type": "npc_computer", "pos": [8, 5],
			"owner": "npc_claudia_reeves", "requires_absence": true }
	],
	"illegitimate_entries": [], "connects_to": ["corridors_low", "p3_pantry"],
	"occupants_by_band": { "arrival": 8, "work_morning": 12, "lunch": 2,
		"work_afternoon": 12, "exit": 4, "night": 0 }
}"""

const TRANSVERSAL_JSON := """{
	"id": "service_stairs", "name_key": "ROOM_SERVICE_STAIRS", "floor": -99, "floors": [-3, 20],
	"clearance_required": 0, "art_band": "the_guts", "kit": "stairs", "size": [3, 6],
	"camera_positions": [[1, 2], { "id": "stairs_door_cam", "pos": [2, 5], "rotation": 90 }],
	"illegitimate_entries": [{ "method": "vent", "pos": [1, 1] }, "stolen_card"]
}"""

const ARCHETYPE_JSON := """{
	"id": "gossip", "name_key": "ARCH_GOSSIP", "description_key": "ARCH_GOSSIP_DESC",
	"traits": { "ambition": 40, "loyalty": 45, "greed": 45,
		"courage": 40, "perception": 70, "sociability": 95 },
	"visual_tic": "leans_toward_interlocutor", "caught_reaction": "spread_at_lunch",
	"propagation_bonus": 1.4
}"""

const NPC_JSON := """{
	"id": "npc_debbie_foyle", "name": "Debbie Foyle", "archetype": "gossip",
	"traits": { "ambition": 42, "loyalty": 40, "greed": 48,
		"courage": 38, "perception": 72, "sociability": 96 },
	"occupation": "order_filer", "home_room": "wing_3b", "desk_position": [4, 2],
	"routine_template": "tier_1_2",
	"routine_overrides": [
		{ "band": "work_morning", "time": "10:30", "action": "coffee",
			"location": "p3_pantry", "duration_minutes": 15 },
		{ "band": "lunch", "time": "13:00", "action": "gossip",
			"location": "cafeteria", "duration_minutes": 60,
			"note": "Ocupa siempre la primera fila del comedor" }
	],
	"initial_links": [
		{ "to": "npc_george_penn",    "type": "department", "strength": 0.4 },
		{ "to": "npc_sonia_vail",     "type": "friendship", "strength": 0.7 },
		{ "to": "npc_claudia_reeves", "type": "rivalry",    "strength": 0.5 },
		{ "to": "npc_nate_brackley",  "type": "department", "strength": 0.3 }
	],
	"gatherings": ["cafeteria_clan", "chat_3b"],
	"weakness_key": "NPC_WEAK_FEED_GOSSIP", "danger_key": "NPC_DANGER_SPREADS_YOURS",
	"unique_accessory": "oversized_mug", "portrait_seed": 10472, "is_slacker": false
}"""

const INVESTOR_JSON := """{
	"id": "inv_howard_grange", "name": "Howard Grange", "strategy": "value",
	"capital": 4500000, "initial_confidence": 50, "bribable": false, "blackmailable": false,
	"traits": { "ambition": 40, "loyalty": 60, "greed": 30,
		"courage": 70, "perception": 90, "sociability": 40 },
	"reacts_to": ["fundamentals", "audit_results"], "on_confidence_loss": "public_statement"
}"""

const BELIEF_JSON := """{
	"id": "belief_1", "holder": "npc_george_penn", "subject": "player", "fact": "stole_stapler",
	"evidence_strength": 0.35, "source": "direct", "certainty": 0.9, "location": "wing_3b",
	"timestamp": 3, "is_record": false
}"""

const RECORD_JSON := """{
	"id": "record_1", "holder": "security", "subject": "player", "fact": "entered_after_hours",
	"evidence_strength": 1.0, "source": "record", "certainty": 1.0, "location": "lobby",
	"timestamp": 5, "is_record": true, "record_type": "card_access", "weight": 2.5
}"""

const IDEA_JSON := """{
	"id": "idea_1", "owner": "npc_claudia_reeves", "quality": 72, "department": "marketing",
	"freshness": 6, "known_by": ["npc_claudia_reeves", "npc_debbie_foyle"], "presented": false
}"""

const INVESTIGATION_JSON := """{
	"id": "case_1", "incident_type": "missing_valuable", "severity": 2, "location": "wing_3b",
	"phase": 2, "opened_day": 4, "phase_day": 5,
	"evidence": [
		{ "type": "direct_witness", "weight": 4.0, "certainty": 0.9, "points_to": "player",
			"record_id": "" },
		{ "type": "camera_footage", "weight": 4.5, "points_to": "npc_nate_brackley",
			"record_id": "record_7" }
	],
	"suspects": ["player", "npc_nate_brackley"], "status": "active", "verdict": "",
	"culprit": "", "frozen_until_day": 0, "searched_rooms": ["wing_3b"]
}"""

const ITEM_JSON := """{
	"id": "balaclava", "name_key": "ITEM_BALACLAVA", "category": "compromising", "value": 45,
	"stack": 1, "size_class": "small"
}"""

const ERROR_PATTERN := "^.+ → entrada \\d+ → campo '[^']+': .+ \\(esperado .+, recibido .+\\)$"

var _error_regex: RegEx = RegEx.create_from_string(ERROR_PATTERN)


func run_case() -> void:
	_test_error_format()
	_test_correct_values()
	_test_optionals()
	_test_occupation()
	_test_rooms()
	_test_archetype_npc_investor()
	_test_runtime_classes()
	_test_npc_runtime()
	_test_malformed_records()
	Validate.clear_errors()


# ─── Utilidades ───────────────────────────────────────────────

func _parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "example JSON parses")
	return parsed if parsed is Dictionary else {}


func _expect_error(action: Callable, expected: String, msg: String) -> void:
	Validate.clear_errors()
	action.call()
	check_eq(Validate.errors.size(), 1, "%s: exactly one error" % msg)
	if not Validate.errors.is_empty():
		check_eq(Validate.errors[0], expected, "%s: exact message" % msg)
		check(_error_regex.search(Validate.errors[0]) != null, "%s: matches format" % msg)
	Validate.clear_errors()


func _expect_no_errors(msg: String) -> void:
	check(Validate.errors.is_empty(), "%s: no validation errors %s" % [msg, str(Validate.errors)])


func _all_errors_formatted(msg: String) -> void:
	var ok: bool = true
	for line: String in Validate.errors:
		if _error_regex.search(line) == null:
			ok = false
			print("  bad format: %s" % line)
	check(ok and not Validate.errors.is_empty(), "%s: every error has the exact format" % msg)


func _has_error(expected: String, msg: String) -> void:
	check(Validate.errors.has(expected), "%s -> %s" % [msg, expected])


func _round_trip(obj: RefCounted, parser: Callable, label: String) -> void:
	var first: Dictionary = obj.call("to_dict")
	var parsed: Variant = JSON.parse_string(JSON.stringify(first))
	Validate.clear_errors()
	var again: RefCounted = parser.call(parsed, "roundtrip.json → entrada 0")
	_expect_no_errors("%s round trip" % label)
	check_eq(JSON.stringify(again.call("to_dict"), "", true), JSON.stringify(first, "", true),
			"%s to_dict round-trips through JSON" % label)


# ─── Formato exacto del error ─────────────────────────────────

func _test_error_format() -> void:
	var src: String = Validate.entry("occupations.json", 3)
	check_eq(src, "occupations.json → entrada 3", "Validate.entry builds 'ARCHIVO → entrada N'")
	var p: String = "occupations.json → entrada 3 → campo "
	_expect_error(func() -> void: Validate.require_int({}, "rank", src),
			p + "'rank': clave ausente (esperado int, recibido nada)", "missing int")
	_expect_error(func() -> void: Validate.require_int({"rank": "uno"}, "rank", src),
			p + "'rank': tipo incorrecto (esperado int, recibido String \"uno\")", "int type")
	_expect_error(func() -> void: Validate.require_int({"rank": 2.5}, "rank", src),
			p + "'rank': número no entero (esperado int, recibido float 2.5)", "non-integral")
	_expect_error(func() -> void: Validate.require_int_range({"q": 150.0}, "q", 0, 100, src),
			p + "'q': fuera de rango (esperado int 0..100, recibido int 150)", "int range")
	_expect_error(func() -> void: Validate.require_int_min({"w": -2}, "w", 0, src),
			p + "'w': por debajo del mínimo (esperado int >= 0, recibido int -2)", "int min")
	_expect_error(func() -> void: Validate.require_float({"f": "x"}, "f", src),
			p + "'f': tipo incorrecto (esperado float, recibido String \"x\")", "float type")
	_expect_error(func() -> void: Validate.require_float_range({"c": 1.5}, "c", 0.0, 1.0, src),
			p + "'c': fuera de rango (esperado float 0.0..1.0, recibido float 1.5)", "float range")
	_expect_error(func() -> void: Validate.require_bool({"b": 1}, "b", src),
			p + "'b': tipo incorrecto (esperado bool, recibido int 1)", "bool type")
	_expect_error(func() -> void: Validate.require_array({"a": "x"}, "a", src),
			p + "'a': tipo incorrecto (esperado Array, recibido String \"x\")", "array type")
	_expect_error(func() -> void: Validate.require_dict({"d": []}, "d", src),
			p + "'d': tipo incorrecto (esperado Dictionary, recibido Array [])", "dict type")
	_expect_error(func() -> void: Validate.require_vector2({"v": [1]}, "v", src),
			p + "'v': formato incorrecto (esperado [x, y], recibido Array [1])", "vector2 format")
	_expect_error(func() -> void: Validate.require_string({"s": null}, "s", src),
			p + "'s': valor nulo (esperado String, recibido null)", "null value")
	_expect_error(func() -> void: Validate.require_id({"id": "Email Worker"}, "id", src),
			p + "'id': identificador no válido (esperado identificador snake_case, "
			+ "recibido String \"Email Worker\")", "invalid id")
	_test_nested_path(src, p)


func _test_nested_path(src: String, p: String) -> void:
	Validate.clear_errors()
	Validate.enter("furniture[1]")
	Validate.require_vector2i({}, "pos", src)
	Validate.leave()
	check_eq(Validate.errors, [p + "'furniture[1].pos': clave ausente (esperado [x, y] enteros, "
			+ "recibido nada)"] as Array[String], "nested records prefix the key path")
	check(Validate.has_errors(), "has_errors() reports collected errors")
	Validate.clear_errors()
	check(not Validate.has_errors(), "clear_errors() empties the list")


# ─── Datos correctos ──────────────────────────────────────────

func _test_correct_values() -> void:
	Validate.clear_errors()
	var src: String = Validate.entry("ok.json", 0)
	var d: Dictionary = {"i": 3.0, "j": 7, "f": 2, "s": "abc", "b": true, "v": [4, 5],
			"a": [1, 2], "o": {"k": 1}, "r": 50, "c": 0.5, "vi": [4.0, 5.0], "e": "lunch"}
	var i: int = Validate.require_int(d, "i", src)
	check(typeof(i) == TYPE_INT and i == 3, "require_int accepts an integral JSON float (3.0 → 3)")
	check_eq(Validate.require_int(d, "j", src), 7, "require_int reads int")
	var f: float = Validate.require_float(d, "f", src)
	check(typeof(f) == TYPE_FLOAT and f == 2.0, "require_float accepts int and returns float")
	check_eq(Validate.require_string(d, "s", src), "abc", "require_string")
	check_eq(Validate.require_bool(d, "b", src), true, "require_bool")
	check_eq(Validate.require_vector2(d, "v", src), Vector2(4, 5), "require_vector2 from [x, y]")
	check_eq(Validate.require_vector2i(d, "vi", src), Vector2i(4, 5), "require_vector2i")
	check_eq(Validate.require_array(d, "a", src), [1, 2], "require_array")
	check_eq(Validate.require_dict(d, "o", src), {"k": 1}, "require_dict")
	check_eq(Validate.require_int_range(d, "r", 0, 100, src), 50, "require_int_range in range")
	check_eq(Validate.require_int_min(d, "r", 50, src), 50, "require_int_min at the minimum")
	check_near(Validate.require_float_range(d, "c", 0.0, 1.0, src), 0.5, 0.0001,
			"require_float_range in range")
	check_eq(Validate.require_enum(d, "e", Validate.TIME_BANDS, src), "lunch", "require_enum")
	check_eq(Validate.require_string_array({"l": ["x", "y"]}, "l", src), ["x", "y"],
			"require_string_array")
	_expect_no_errors("correct values")


func _test_optionals() -> void:
	Validate.clear_errors()
	var src: String = Validate.entry("opt.json", 1)
	var d: Dictionary = {"n": null, "s": "given", "i": 4.0}
	check_eq(Validate.optional_string(d, "missing", "def", src), "def", "optional_string default")
	check_eq(Validate.optional_string(d, "s", "def", src), "given", "optional_string value")
	check_eq(Validate.optional_int(d, "missing", 9, src), 9, "optional_int default")
	check_eq(Validate.optional_int(d, "i", 9, src), 4, "optional_int value")
	check_eq(Validate.optional_float(d, "n", 1.5, src), 1.5, "optional_float null → default")
	check_eq(Validate.optional_array(d, "missing", ["z"], src), ["z"], "optional_array default")
	check_eq(Validate.optional_dict(d, "missing", {"z": 1}, src), {"z": 1},
			"optional_dict default")
	_expect_no_errors("optional values")
	_expect_error(func() -> void: Validate.optional_string({"s": 5}, "s", "def", src),
			"opt.json → entrada 1 → campo 's': tipo incorrecto (esperado String, recibido int 5)",
			"optional with a wrong type still reports")
	_expect_error(func() -> void: Validate.optional_array({"a": 5}, "a", [], src),
			"opt.json → entrada 1 → campo 'a': tipo incorrecto (esperado Array, recibido int 5)",
			"optional_array wrong type")
	_expect_error(func() -> void: Validate.optional_dict({"o": "x"}, "o", {}, src),
			"opt.json → entrada 1 → campo 'o': tipo incorrecto (esperado Dictionary, "
			+ "recibido String \"x\")", "optional_dict wrong type")
	_expect_error(func() -> void: Validate.optional_float({"f": true}, "f", 0.0, src),
			"opt.json → entrada 1 → campo 'f': tipo incorrecto (esperado float, "
			+ "recibido bool true)",
			"optional_float wrong type")
	_expect_error(func() -> void: Validate.optional_int({"i": 1.25}, "i", 0, src),
			"opt.json → entrada 1 → campo 'i': número no entero (esperado int, "
			+ "recibido float 1.25)",
			"optional_int non-integral")


# ─── Clases de datos estáticos ────────────────────────────────

func _test_occupation() -> void:
	Validate.clear_errors()
	var o: OccupationData = OccupationData.from_dict(_parse(OCCUPATION_JSON),
			Validate.entry("occupations.json", 0))
	_expect_no_errors("OccupationData §26 example")
	check_eq(o.id, "email_worker_3b", "occupation id")
	check(typeof(o.rank) == TYPE_INT and o.rank == 1, "occupation rank is int 1")
	check_eq([o.tier, o.clearance, o.daily_wage, o.personnel_file_level, o.computer_tier],
			[1, 1, 30, 1, 1], "occupation tier/clearance/wage/file level/computer tier")
	check_eq(o.desk_position, Vector2i(4, 5), "occupation desk_position is Vector2i")
	check_eq(o.office_room, "wing_3b", "occupation office_room")
	check_eq(o.duties.size(), 1, "occupation has one duty")
	var duty: Dictionary = o.get_duty("duty_emails_r1")
	check(typeof(duty.get("amount")) == TYPE_INT and duty["amount"] == 8, "duty amount is int 8")
	check_eq(duty.get("time_cost_minutes"), 45, "duty time_cost_minutes")
	check_eq(duty.get("deadline_hour"), 18, "duty deadline_hour")
	check_eq(duty.get("subtype"), "emails", "duty keeps extra keys (subtype)")
	check_eq(o.tools, ["keys_basic", "stamp"] as Array[String], "occupation tools")
	check_eq(o.promotes_to, ["order_filer", "copy_operator"] as Array[String], "promotes_to")
	check_eq(o.can_jump_to, ["mail_courier"] as Array[String], "can_jump_to")
	check_eq(o.demotes_to, ["eternal_intern"] as Array[String], "demotes_to")
	check_eq(o.opportunities.size(), 2, "opportunities")
	check_eq(o.risks.size(), 2, "risks")
	check_eq(o.special_access.size(), 0, "special_access empty")
	check_eq(o.min_reputation, 0.0, "min_reputation")
	check_eq(o.silhouette, "tier_1", "silhouette")
	check(o.has_desk(), "has_desk()")
	check(o.extra.is_empty(), "comment keys (_nota) are ignored, not kept as extra")
	_round_trip(o, func(d: Dictionary, s: String) -> RefCounted:
			return OccupationData.from_dict(d, s),
			"OccupationData")


func _test_rooms() -> void:
	Validate.clear_errors()
	var r: RoomData = RoomData.from_dict(_parse(ROOM_JSON), Validate.entry("rooms/p03.json", 0))
	_expect_no_errors("RoomData §27 example")
	check_eq([r.id, r.floor, r.wing, r.clearance_required], ["wing_3b", 3, "B", 1], "room identity")
	check_eq(r.size, Vector2i(20, 14), "room size is Vector2i")
	check_eq(r.furniture.size(), 15, "room furniture count")
	check_eq(r.furniture[1]["pos"], Vector2i(4, 5), "furniture pos is Vector2i")
	check_eq(r.furniture[1]["owner"], "player_start", "furniture owner kept")
	check_eq(r.furniture[12]["rotation"], 90.0, "furniture rotation is float degrees")
	check_eq(r.hiding_spots[1]["id"], "hide_3b_closet", "hiding spot id")
	check_eq(r.hiding_spots[1]["pos"], Vector2i(18, 12), "hiding spot pos")
	check_eq(r.interactables[0]["contains"], ["keys_basic", "stamp"], "interactable contains")
	check_eq(r.interactables[1]["requires_absence"], true, "interactable extra flags kept")
	check_eq(r.connects_to, ["corridors_low", "p3_pantry"] as Array[String], "connects_to")
	check(typeof(r.occupants_by_band["work_morning"]) == TYPE_INT, "occupants are ints")
	check_eq(r.get_occupants("lunch"), 2, "get_occupants(lunch)")
	check_near(r.ambient_noise_level, 0.2, 0.0001, "ambient_noise_level")
	check(not r.has_cameras and not r.is_transversal(), "no cameras, not transversal")
	check(r.spans_floor(3) and not r.spans_floor(4), "spans only its own floor")
	_round_trip(r, func(d: Dictionary, s: String) -> RefCounted: return RoomData.from_dict(d, s),
			"RoomData")
	_test_transversal_room()


func _test_transversal_room() -> void:
	Validate.clear_errors()
	var t: RoomData = RoomData.from_dict(_parse(TRANSVERSAL_JSON),
			Validate.entry("rooms/transversal.json", 0))
	_expect_no_errors("transversal RoomData")
	check(t.is_transversal(), "floors [min, max] makes a transversal room")
	check_eq(t.floors, [-3, 20] as Array[int], "floors")
	check(t.spans_floor(-3) and t.spans_floor(20) and not t.spans_floor(21), "spans_floor range")
	check_eq(t.camera_positions[0], {"id": "service_stairs_cam_0", "pos": Vector2i(1, 2),
			"rotation": 0.0}, "camera [x, y] normalised with generated id")
	check_eq(t.camera_positions[1]["id"], "stairs_door_cam", "camera dict keeps its id")
	check_eq(t.camera_positions[1]["pos"], Vector2i(2, 5), "camera dict pos → Vector2i")
	check_eq(t.illegitimate_entries[0]["pos"], Vector2i(1, 1), "illegitimate entry pos")
	check_eq(t.illegitimate_entries[1], "stolen_card", "illegitimate entry strings kept")
	_round_trip(t, func(d: Dictionary, s: String) -> RefCounted: return RoomData.from_dict(d, s),
			"transversal RoomData")


func _test_archetype_npc_investor() -> void:
	Validate.clear_errors()
	var a: ArchetypeData = ArchetypeData.from_dict(_parse(ARCHETYPE_JSON),
			Validate.entry("archetypes.json", 0))
	_expect_no_errors("ArchetypeData §28 example")
	check_eq(a.get_trait("sociability"), 95, "archetype trait")
	check_eq([a.visual_tic, a.caught_reaction], ["leans_toward_interlocutor", "spread_at_lunch"],
			"archetype tic and caught reaction")
	check_near(a.propagation_bonus, 1.4, 0.0001, "archetype propagation_bonus")
	_round_trip(a, func(d: Dictionary, s: String) -> RefCounted:
			return ArchetypeData.from_dict(d, s),
			"ArchetypeData")
	var n: NPCData = NPCData.from_dict(_parse(NPC_JSON), Validate.entry("npcs_named.json", 0))
	_expect_no_errors("NPCData §29 example")
	check_eq([n.name, n.archetype, n.occupation], ["Debbie Foyle", "gossip", "order_filer"],
			"npc identity")
	check_eq(n.get_trait("sociability"), 96, "npc trait")
	check_eq(n.desk_position, Vector2i(4, 2), "npc desk_position")
	check_eq(n.routine_overrides.size(), 2, "npc routine overrides")
	check_eq(n.routine_overrides[0]["duration_minutes"], 15, "override duration is int")
	check_eq(n.routine_overrides[1]["note"], "Ocupa siempre la primera fila del comedor",
			"override extra keys kept")
	check_eq(n.initial_links.size(), 4, "npc initial links")
	check_near(n.initial_links[1]["strength"], 0.7, 0.0001, "link strength")
	check_eq(n.gatherings, ["cafeteria_clan", "chat_3b"] as Array[String], "npc gatherings")
	check_eq([n.portrait_seed, n.is_slacker], [10472, false], "portrait seed and slacker flag")
	_round_trip(n, func(d: Dictionary, s: String) -> RefCounted: return NPCData.from_dict(d, s),
			"NPCData")
	var v: InvestorData = InvestorData.from_dict(_parse(INVESTOR_JSON),
			Validate.entry("investors.json", 0))
	_expect_no_errors("InvestorData §32.4 example")
	check_eq([v.capital, v.initial_confidence, v.bribable], [4500000, 50, false], "investor")
	check_eq(v.get_trait("perception"), 90, "investor trait")
	check_eq(v.reacts_to, ["fundamentals", "audit_results"] as Array[String], "investor reacts_to")
	_round_trip(v, func(d: Dictionary, s: String) -> RefCounted:
			return InvestorData.from_dict(d, s),
			"InvestorData")


# ─── Clases de estado de partida ──────────────────────────────

func _test_runtime_classes() -> void:
	Validate.clear_errors()
	var b: Belief = Belief.from_dict(_parse(BELIEF_JSON), Validate.entry("run.json", 0))
	var rec: Belief = Belief.from_dict(_parse(RECORD_JSON), Validate.entry("run.json", 1))
	_expect_no_errors("Belief §7.2")
	check_eq([b.holder, b.subject, b.source, b.timestamp], ["npc_george_penn", "player",
			"direct", 3], "belief fields")
	check(not b.is_record and rec.is_record, "is_record flag")
	check_eq([rec.record_type, rec.weight], ["card_access", 2.5], "record type and weight")
	_round_trip(b, func(d: Dictionary, s: String) -> RefCounted: return Belief.from_dict(d, s),
			"Belief")
	_round_trip(rec, func(d: Dictionary, s: String) -> RefCounted: return Belief.from_dict(d, s),
			"Belief record")
	var made: Belief = Belief.make("b2", "npc_x", "player", "f", 0.35, "rumor", "cafeteria", 1)
	check(made.certainty == 0.35 and not made.is_record, "Belief.make")
	var idea: Idea = Idea.from_dict(_parse(IDEA_JSON), Validate.entry("run.json", 2))
	_expect_no_errors("Idea §11.1")
	check_eq([idea.owner, idea.quality, idea.freshness, idea.presented],
			["npc_claudia_reeves", 72, 6, false], "idea fields")
	check_eq(idea.known_by.size(), 2, "idea known_by")
	_round_trip(idea, func(d: Dictionary, s: String) -> RefCounted: return Idea.from_dict(d, s),
			"Idea")
	_test_investigation_and_item()


func _test_investigation_and_item() -> void:
	Validate.clear_errors()
	var inv: Investigation = Investigation.from_dict(_parse(INVESTIGATION_JSON),
			Validate.entry("run.json", 3))
	_expect_no_errors("Investigation §12.3")
	check_eq([inv.phase, inv.opened_day, inv.phase_day, inv.status], [2, 4, 5, "active"],
			"investigation phase/days/status")
	check_eq(inv.evidence[1]["certainty"], 1.0, "evidence certainty defaults to 1.0")
	check_near(inv.weight_against("player"), 3.6, 0.0001, "weight_against = Σ weight × certainty")
	check_near(inv.weight_against("npc_nate_brackley"), 4.5, 0.0001, "weight_against other")
	check(inv.is_active() and not inv.is_frozen(4), "active, not frozen")
	inv.add_evidence("card_access", 2.5, 1.0, "player", "record_1")
	check_near(inv.weight_against("player"), 6.1, 0.0001, "add_evidence accumulates")
	_round_trip(inv, func(d: Dictionary, s: String) -> RefCounted:
			return Investigation.from_dict(d, s), "Investigation")
	var item: ItemData = ItemData.from_dict(_parse(ITEM_JSON), Validate.entry("items.json", 0))
	_expect_no_errors("ItemData §11.3")
	check(item.is_compromising(), "balaclava is compromising")
	check_eq([item.value, item.stack, item.extra.get("size_class")], [45, 1, "small"],
			"item value/stack/extra")
	check(not ItemData.make("keys_basic", "ITEM_KEYS", "ordinary").is_compromising(),
			"ordinary item is not compromising")
	_round_trip(item, func(d: Dictionary, s: String) -> RefCounted: return ItemData.from_dict(d, s),
			"ItemData")


func _test_npc_runtime() -> void:
	Validate.clear_errors()
	var n: NPCData = NPCData.from_dict(_parse(NPC_JSON), Validate.entry("npcs_named.json", 0))
	var r: NPCRuntime = NPCRuntime.from_named(n)
	check(r.is_named and r.alive and r.current_room == "wing_3b", "from_named initial state")
	check_eq(r.ledger, NPCRuntime.new_ledger(), "fresh ledger")
	r.tier = 1
	r.floor = 3
	r.position = Vector2(96.5, 240.0)
	r.mood = -0.25
	r.merit = 12
	r.lod = NPCRuntime.LOD_FULL
	r.ledger["affection"] = -30
	r.ledger["grievances"].append({"type": "stole_idea", "severity": 3, "day": 7})
	r.blackmail_material.append({"type": "slacking", "day": 2})
	r.schedule_override["lunch"] = "p3_pantry"
	r.home_address = "12 Garrow Street"
	_round_trip(r, func(d: Dictionary, s: String) -> RefCounted: return NPCRuntime.from_dict(d, s),
			"NPCRuntime")
	var again: NPCRuntime = NPCRuntime.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())),
			Validate.entry("run.json", 4))
	check_eq(again.position, Vector2(96.5, 240.0), "runtime position restored as Vector2")
	check_eq(again.ledger["grievances"][0]["severity"], 3, "grievance severity restored as int")
	check_eq(again.desk_position, Vector2i(4, 2), "runtime desk restored as Vector2i")


# ─── Registros malformados ────────────────────────────────────

func _test_malformed_records() -> void:
	Validate.clear_errors()
	var occ: Dictionary = _parse(OCCUPATION_JSON)
	occ.erase("rank")
	occ["duties"][0]["amount"] = "eight"
	OccupationData.from_dict(occ, Validate.entry("occupations.json", 7))
	var p: String = "occupations.json → entrada 7 → campo "
	_has_error(p + "'rank': clave ausente (esperado int, recibido nada)", "missing rank")
	_has_error(p + "'duties[0].amount': tipo incorrecto (esperado int, recibido String "
			+ "\"eight\")", "bad duty amount")
	_all_errors_formatted("OccupationData")
	Validate.clear_errors()
	var room: Dictionary = _parse(ROOM_JSON)
	room["size"] = [-1, 5]
	room["furniture"][1].erase("pos")
	room["occupants_by_band"]["brunch"] = 3
	RoomData.from_dict(room, Validate.entry("rooms/p03.json", 2))
	p = "rooms/p03.json → entrada 2 → campo "
	_has_error(p + "'size': fuera de rango (esperado [ancho, alto] >= 0, recibido Array [-1,5])",
			"negative room size")
	_has_error(p + "'furniture[1].pos': clave ausente (esperado [x, y] enteros, recibido nada)",
			"furniture without pos")
	check(_any_error_starts(p + "'occupants_by_band.brunch': valor no permitido"),
			"unknown time band in occupants_by_band")
	_all_errors_formatted("RoomData")
	_test_malformed_people()
	_test_malformed_runtime()


func _test_malformed_people() -> void:
	Validate.clear_errors()
	var arch: Dictionary = _parse(ARCHETYPE_JSON)
	arch["traits"]["perception"] = 150
	arch.erase("caught_reaction")
	ArchetypeData.from_dict(arch, Validate.entry("archetypes.json", 5))
	var p: String = "archetypes.json → entrada 5 → campo "
	_has_error(p + "'traits.perception': fuera de rango (esperado int 0..100, recibido int 150)",
			"trait out of range")
	_has_error(p + "'caught_reaction': clave ausente (esperado String, recibido nada)",
			"missing caught_reaction")
	_all_errors_formatted("ArchetypeData")
	Validate.clear_errors()
	var npc: Dictionary = _parse(NPC_JSON)
	npc["initial_links"][0]["strength"] = "high"
	npc["routine_overrides"][0]["time"] = "half past ten"
	NPCData.from_dict(npc, Validate.entry("npcs_named.json", 1))
	p = "npcs_named.json → entrada 1 → campo "
	_has_error(p + "'initial_links[0].strength': tipo incorrecto (esperado float, recibido "
			+ "String \"high\")", "bad link strength")
	_has_error(p + "'routine_overrides[0].time': formato incorrecto (esperado \"HH:MM\", "
			+ "recibido String \"half past ten\")", "bad override time")
	_all_errors_formatted("NPCData")
	Validate.clear_errors()
	var inv: Dictionary = _parse(INVESTOR_JSON)
	inv["initial_confidence"] = 120
	InvestorData.from_dict(inv, Validate.entry("investors.json", 0))
	_has_error("investors.json → entrada 0 → campo 'initial_confidence': fuera de rango "
			+ "(esperado int 0..100, recibido int 120)", "confidence out of range")
	_all_errors_formatted("InvestorData")


func _test_malformed_runtime() -> void:
	Validate.clear_errors()
	var b: Dictionary = _parse(BELIEF_JSON)
	b["certainty"] = 1.4
	b["source"] = "gossip"
	Belief.from_dict(b, Validate.entry("run.json", 0))
	var p: String = "run.json → entrada 0 → campo "
	_has_error(p + "'certainty': fuera de rango (esperado float 0.0..1.0, recibido float 1.4)",
			"certainty out of range")
	check(_any_error_starts(p + "'source': valor no permitido (esperado uno de"),
			"unknown belief source")
	_all_errors_formatted("Belief")
	Validate.clear_errors()
	var c: Dictionary = _parse(INVESTIGATION_JSON)
	c["phase"] = 7
	c["status"] = "archived"
	Investigation.from_dict(c, Validate.entry("run.json", 3))
	_has_error("run.json → entrada 3 → campo 'phase': fuera de rango (esperado int 1..5, "
			+ "recibido int 7)", "phase out of range")
	check(_any_error_starts("run.json → entrada 3 → campo 'status': valor no permitido"),
			"unknown investigation status")
	_all_errors_formatted("Investigation")
	Validate.clear_errors()
	var it: Dictionary = _parse(ITEM_JSON)
	it["category"] = "weird"
	ItemData.from_dict(it, Validate.entry("items.json", 4))
	check(_any_error_starts("items.json → entrada 4 → campo 'category': valor no permitido"),
			"unknown item category")
	Validate.clear_errors()
	var idea: Dictionary = _parse(IDEA_JSON)
	idea["known_by"] = ["npc_a", 3]
	Idea.from_dict(idea, Validate.entry("run.json", 2))
	_has_error("run.json → entrada 2 → campo 'known_by[1]': tipo incorrecto (esperado String, "
			+ "recibido int 3)", "non-string array element")
	_all_errors_formatted("Idea")


func _any_error_starts(prefix: String) -> bool:
	for line: String in Validate.errors:
		if line.begins_with(prefix):
			return true
	return false
