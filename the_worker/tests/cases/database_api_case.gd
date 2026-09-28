# database_api_case.gd — Cuerpo de test_database_api: accesos de §19.1 y extras de Database.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Rutas con puntos, errores de ruta inexistente (push_error comprobado con un Logger propio),
## modificador de dificultad, copias transversales por planta, solo lectura, accesos extra e
## inyección de datos rotos en una instancia aislada (load_from_raw) con el formato exacto.

const PLAYER_START_ROOM := "wing_3b"
const MISSING_JOB := "nonexistent_job"
const EXPECTED_PROMOTES_ERROR := "occupations.json → entrada %d → campo 'promotes_to[0]': referencia inexistente (esperado id de ocupación (occupations.json), recibido String \"nonexistent_job\")"
const EXPECTED_MISSING_FILE_ERROR := "rooms/p07.json → archivo: archivo no encontrado (esperado archivo JSON en data/, recibido nada)"
const EXPECTED_RANK_ERROR := "occupations.json → campo 'rank': rango sin ocupación (esperado al menos una ocupación por rango R0..R33, recibido R0)"
const EXPECTED_LINK_ERROR := "npcs_named.json → entrada 0 → campo 'initial_links[0].to': referencia inexistente (esperado id de personaje nominado (npcs_named.json), recibido String \"npc_nobody\")"
const EXPECTED_CONNECT_ERROR := "rooms/p03.json → entrada %d → campo 'connects_to[0]': referencia inexistente (esperado id de sala, \"street\" o \"exterior\", recibido String \"nowhere_room\")"


class ErrorProbe extends Logger:
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_ERROR:
			count += 1


var _probe: ErrorProbe = ErrorProbe.new()
var _expected_errors: int = 0


func run_case() -> void:
	allowed_engine_errors = -1
	OS.add_logger(_probe)
	check(Database.load_all(), "load_all() succeeds")
	_check_idempotency()
	_check_balance_paths()
	_check_balance_errors()
	_check_difficulty()
	_check_occupations()
	_check_rooms()
	_check_transversal_instances()
	_check_people_and_records()
	_check_items()
	_check_read_only()
	_check_injected_errors()
	_check_garbage_data()
	OS.remove_logger(_probe)
	check_eq(_probe.count, _expected_errors, "no unexpected engine errors during the case")


## Ejecuta `action` y comprueba que emitió exactamente un push_error.
func _expect_one_error(action: Callable, msg: String) -> Variant:
	var before: int = _probe.count
	var result: Variant = action.call()
	_expected_errors += 1
	check_eq(_probe.count - before, 1, "push_error emitted: %s" % msg)
	return result


func _check_idempotency() -> void:
	var started: int = Time.get_ticks_msec()
	var fresh: DatabaseSystem = DatabaseSystem.new()
	fresh.load_all()
	print("[database] full load in %d ms" % (Time.get_ticks_msec() - started))
	check(fresh.is_loaded() and fresh.get_load_report().is_empty(), "fresh instance loads data/")
	fresh.free()
	var ceo: OccupationData = Database.get_occupation("ceo")
	check(Database.load_all(), "second load_all() returns the cached result")
	check(is_same(ceo, Database.get_occupation("ceo")), "second load_all() is a no-op")
	check(Database.is_loaded(), "is_loaded()")
	check(Database.get_data_file_ids().has("rooms/transversal"), "file ids include rooms/*")


func _check_balance_paths() -> void:
	check_eq(Database.get_balance("percepcion.cono_angulo_base"), 75.0, "get_balance dotted path")
	check_eq(Database.get_balance_float("investigaciones.pesos_evidencia.cuerpo_hallado"), 12.0,
			"three-level dotted path")
	check_eq(typeof(Database.get_balance_int("economia.dinero_inicial")), TYPE_INT,
			"get_balance_int returns int")
	check_eq(Database.get_balance_int("economia.dinero_inicial"), 2, "get_balance_int value")
	check_eq(Database.get_balance_int("economia.estatus_por_escalon.6"), 240, "numeric dict key")
	var section: Variant = Database.get_balance("dificultad")
	check(section is Dictionary and (section as Dictionary).has("estandar"),
			"intermediate node returns a Dictionary")
	check(Database.has_balance("mundo.px_por_unidad"), "has_balance true")
	check(not Database.has_balance("mundo.nope"), "has_balance false (no error)")
	check(not Database.has_balance("economia._nota"), "comment keys are not balance paths")


func _check_balance_errors() -> void:
	var missing_any: Callable = func() -> Variant: return Database.get_balance("nope.x")
	check(_expect_one_error(missing_any, "get_balance on a missing path") == null,
			"missing path → null")
	var missing_int: Callable = func() -> Variant: return Database.get_balance_int("ruido.nope")
	check_eq(_expect_one_error(missing_int, "get_balance_int missing"), 0, "missing int → 0")
	var missing_float: Callable = func() -> Variant: return Database.get_balance_float("a.b.c")
	check_eq(_expect_one_error(missing_float, "get_balance_float missing"), 0.0,
			"missing float → 0.0")
	var text_float: Callable = func() -> Variant:
		return Database.get_balance_float("presets_por_defecto")
	check_eq(_expect_one_error(text_float, "get_balance_float on text"), 0.0,
			"non-numeric float path → 0.0")
	var fraction_int: Callable = func() -> Variant:
		return Database.get_balance_int("percepcion.umbral_parcial")
	check_eq(_expect_one_error(fraction_int, "get_balance_int on 0.45"), 0,
			"non-integer float truncated")


func _check_difficulty() -> void:
	check_eq(Database.get_difficulty_preset(), "estandar", "default preset from presets_por_defecto")
	check_eq(Database.get_difficulty_modifier("precio_soborno"), 1.0, "estandar modifier")
	check(Database.set_difficulty_preset("auditoria"), "switch preset to auditoria")
	check_eq(Database.get_difficulty_modifier("precio_soborno"), 1.25, "auditoria modifier")
	check_eq(Database.get_difficulty_modifier("margen_deberes"), 0.7, "auditoria margin")
	var bad_preset: Callable = func() -> Variant: return Database.set_difficulty_preset("hard")
	check(_expect_one_error(bad_preset, "unknown preset") == false, "unknown preset rejected")
	check_eq(Database.get_difficulty_preset(), "auditoria", "previous preset kept")
	var bad_key: Callable = func() -> Variant: return Database.get_difficulty_modifier("nope")
	check_eq(_expect_one_error(bad_key, "unknown modifier"), 1.0, "unknown modifier → 1.0")
	Database.set_difficulty_preset("estandar")
	check_eq(Database.get_difficulty_presets().size(), 3, "three difficulty presets")


func _check_occupations() -> void:
	var r1: Array[OccupationData] = Database.get_occupations_by_rank(1)
	check(r1.size() == 1 and r1[0].id == "email_worker_3b", "rank 1 = email_worker_3b")
	var tier8: Array[OccupationData] = Database.get_occupations_by_tier(8)
	var ids: Array[String] = []
	for occupation: OccupationData in tier8:
		ids.append(occupation.id)
	ids.sort()
	check_eq(ids, ["ceo", "vice_ceo"] as Array[String], "tier 8 = vice_ceo + ceo")
	check(Database.get_occupation("nope") == null, "unknown occupation → null")
	check(not Database.get_occupations_by_department("factory").is_empty(),
			"occupations by department")
	check(Database.get_occupations_by_rank(99).is_empty(), "rank without jobs → empty")


func _check_rooms() -> void:
	check_eq(Database.get_room(PLAYER_START_ROOM).floor, 3, "wing_3b on floor 3")
	check(Database.get_room("nowhere") == null, "unknown room → null")
	var ok: bool = true
	for room: RoomData in Database.get_rooms_by_clearance(0):
		ok = ok and room.clearance_required <= 0
	check(ok and not Database.get_rooms_by_clearance(0).is_empty(), "rooms by clearance filter")
	check_eq(Database.get_rooms_by_clearance(7).size(), Database.get_all_rooms().size(),
			"clearance 7 = every base room")
	var floors: Array[int] = Database.get_floor_ids()
	check(floors.has(-3) and floors.has(21) and floors.has(100) and floors.has(200),
			"floor ids span S3..roof, factory, exterior")
	check(not floors.has(RoomData.TRANSVERSAL_FLOOR), "transversal pseudo-floor excluded")
	var sorted_floors: Array[int] = floors.duplicate()
	sorted_floors.sort()
	check_eq(floors, sorted_floors, "floor ids sorted")


func _check_transversal_instances() -> void:
	var base: RoomData = Database.get_room("corridors_low")
	check(base != null and base.floor == RoomData.TRANSVERSAL_FLOOR, "base transversal room")
	var inst: RoomData = Database.get_room("corridors_low@3")
	check(inst != null and inst.floor == 3, "get_room('corridors_low@3') → floor 3")
	check(inst != null and inst.is_transversal(), "instance keeps transversal floors")
	check(inst != null and inst.extra.get("base_id") == "corridors_low", "instance base_id")
	check(Database.get_room("corridors_low@15") == null, "no instance outside its span")
	var ids: Array[String] = _room_ids(Database.get_rooms_by_floor(3))
	check(ids.has(PLAYER_START_ROOM) and ids.has("corridors_low@3"), "floor 3 lists rooms + corridor")
	check(ids.has("service_stairs@3") and ids.has("main_elevator_1@3"), "floor 3 lists stairs/lifts")
	check(not ids.has("corridors_high@3") and not ids.has("corridors_low"), "no foreign pieces")
	check(_room_ids(Database.get_rooms_by_floor(100)).has("freight_elevator@100"),
			"extra_floors: freight elevator reaches the factory")
	check(_room_ids(Database.get_rooms_by_floor(-3)).has("service_stairs@-3"), "negative floors")
	check(not Database.get_all_rooms().has(inst), "get_all_rooms lists base rooms only")
	check_eq(DatabaseSystem.get_room_base_id("corridors_low@3"), "corridors_low", "base id helper")
	var cam_a: Array[Dictionary] = Database.get_room("main_elevator_1@3").camera_positions
	var cam_b: Array[Dictionary] = Database.get_room("main_elevator_1@4").camera_positions
	check(not cam_a.is_empty() and cam_a[0]["id"] != cam_b[0]["id"], "camera ids unique per floor")


func _room_ids(rooms: Array[RoomData]) -> Array[String]:
	var out: Array[String] = []
	for room: RoomData in rooms:
		out.append(room.id)
	return out


func _check_people_and_records() -> void:
	check_eq(Database.get_archetype("gossip").name_key, "ARCH_GOSSIP", "archetype lookup")
	check_eq(Database.get_named_npc("npc_debbie_foyle").archetype, "gossip", "named NPC lookup")
	check_eq(Database.get_generation_rules("factory").get("population"), 25.0, "generation rules")
	check(Database.get_generation_rules("nope").is_empty(), "unknown department → {}")
	check_eq(Database.get_investor("inv_howard_grange").strategy, "value", "investor lookup")
	check_eq(Database.get_duty_definition("round").get("interface"), "waypoints", "duty type")
	check_eq(Database.get_all_duty_types().size(), 5, "five duty types")
	check_eq(Database.get_idea_template("design").get("quality_min"), 50.0, "idea template")
	check_eq(Database.get_idea_template("nope").get("department"), "general", "idea fallback")
	check_eq(Database.get_bribe_favour("bury_investigation").get("multiplier"), 100.0, "favour")
	check_eq(Database.get_bribe_channel("immediate").get("forced_favour"), "silence_witnessed",
			"bribe channel")
	check_eq(Database.get_social_link_type("rivalry").get("propagates"), "negative_only", "link")
	check(Database.get_gathering("chat_3b").get("room") == null, "gathering with null room")
	check_eq(Database.get_all_gatherings().size(), 5, "five gatherings")
	check(Database.get_market_params().has("simulation"), "market params")
	check_eq(Database.get_market_events().size(), 8, "market events")
	check(Database.get_investigation_params().has("thresholds"), "investigation params")
	check_eq(Database.get_ending("the_gap").get("category"), "defeat", "ending lookup")
	check_eq(Database.get_art_band_for_floor(3).get("id"), "the_pit", "band for floor 3")
	check_eq(Database.get_art_band_for_floor(100).get("id"), "factory", "band for factory")
	check_eq(Database.get_art_band_for_floor(-2).get("id"), "the_guts", "band for S2")
	check(Database.get_art_band_for_floor(999).is_empty(), "no band → {}")
	check(Database.get_duty_content().has("round_waypoint_sets"), "duty content")
	check(not Database.get_round_waypoint_set("mail_round").is_empty(), "waypoint set")
	check_eq(Database.get_archetype_variation_range(), 15, "archetype variation range")
	check_eq(Database.get_role("auditor").get("tier"), 3.0, "role lookup")


func _check_items() -> void:
	var item: ItemData = Database.get_item("balaclava")
	check(item != null and item.is_compromising(), "balaclava is compromising")
	check(item != null and item.value == 45, "balaclava price matches economia.precio_pasamontanas")
	var keys: ItemData = Database.get_item("keys_basic")
	check(keys != null and not keys.is_compromising(), "keys_basic is ordinary")
	item.stack = 7
	check_eq(Database.get_item("balaclava").stack, 1, "get_item returns a fresh copy")
	check(Database.get_item("nope") == null, "unknown item → null")
	check(Database.has_item("stamp"), "has_item")
	check(Database.get_all_items().size() >= 30, "item catalogue size")


func _check_read_only() -> void:
	var bands: Dictionary = Database.get_balance("dificultad")
	bands["estandar"]["precio_soborno"] = 99.0
	check_eq(Database.get_balance_float("dificultad.estandar.precio_soborno"), 1.0,
			"get_balance containers are copies")
	var raw: Dictionary = Database.get_raw("balance")
	raw["economia"]["dinero_inicial"] = 1
	check_eq(Database.get_balance_int("economia.dinero_inicial"), 2, "get_raw is a copy")
	check_eq(Database.get_raw("balance.json").get("presets_por_defecto"), "estandar",
			"get_raw accepts the .json suffix")
	var list: Array[OccupationData] = Database.get_all_occupations()
	list.clear()
	check_eq(Database.get_all_occupations().size(), 50, "returned arrays are copies")
	var favour: Dictionary = Database.get_bribe_favour("lend_access")
	favour["multiplier"] = 0
	check_eq(Database.get_bribe_favour("lend_access").get("multiplier"), 8.0, "records are copies")


## Datos rotos en una instancia aislada: formato exacto y aislamiento de Validate.errors.
func _check_injected_errors() -> void:
	var raw: Dictionary = {}
	for file_id: String in Database.get_data_file_ids():
		raw[file_id] = Database.get_raw(file_id)
	var clean: DatabaseSystem = DatabaseSystem.new()
	check(clean.load_from_raw(raw), "load_from_raw with the real data succeeds")
	clean.free()
	var broken: Dictionary = raw.duplicate(true)
	var jobs: Array = broken["occupations"]["occupations"]
	jobs.remove_at(_index_of(jobs, "eternal_intern"))
	var job_index: int = _index_of(jobs, "email_worker_3b")
	jobs[job_index]["promotes_to"] = [MISSING_JOB]
	broken["npcs_named"]["npcs"][0]["initial_links"][0]["to"] = "npc_nobody"
	var p03: Array = broken["rooms/p03"]["rooms"]
	var room_index: int = _index_of(p03, PLAYER_START_ROOM)
	p03[room_index]["connects_to"][0] = "nowhere_room"
	broken.erase("rooms/p07")
	Validate.clear_errors()
	Validate.errors.append("sentinel")
	var db: DatabaseSystem = DatabaseSystem.new()
	check(not db.load_from_raw(broken), "broken data → load_from_raw returns false")
	var errors: Array[String] = db.get_load_errors()
	check(errors.has(EXPECTED_PROMOTES_ERROR % job_index), "exact promotes_to error")
	check(errors.has(EXPECTED_MISSING_FILE_ERROR), "missing floor file reported")
	check(errors.has(EXPECTED_RANK_ERROR), "rank coverage error")
	check(errors.has(EXPECTED_LINK_ERROR), "NPC link error")
	check(errors.has(EXPECTED_CONNECT_ERROR % room_index), "connects_to error")
	check_eq(Validate.errors, ["sentinel"] as Array[String], "outer Validate.errors preserved")
	var report: String = db.get_load_report()
	check(report.contains(EXPECTED_MISSING_FILE_ERROR)
			and report.split("\n").size() == errors.size() + 1, "load report: header + one line each")
	Validate.clear_errors()
	db.free()


## Datos con tipos absurdos en todos los niveles: la carga falla con errores, sin SCRIPT ERROR.
func _check_garbage_data() -> void:
	var raw: Dictionary = {}
	for file_id: String in Database.get_data_file_ids():
		raw[file_id] = {}
	raw["balance"] = {"dificultad": {"a": 1, "b": {"x": "y"}}, "presets_por_defecto": 3,
			"objetos": {"bad": 5, "other": {"id": "mismatch", "name_key": 1, "category": "?"}}}
	raw["occupations"] = []
	raw["npcs_named"] = {"npcs": [1, "x", {"id": 5, "initial_links": "no"}, {"routine_overrides": [3]}]}
	raw["rooms/p03"] = {"rooms": "oops"}
	raw["rooms/p04"] = {"rooms": [{"id": "dup", "connects_to": [1, null]}, {"id": "dup"}]}
	raw["rooms/transversal"] = {"rooms": [{"id": "shaft", "name_key": "K", "floor": -99,
			"clearance_required": 0, "art_band": "nope", "kit": "k", "size": [1, 1],
			"floors": [0, 2], "extra_floors": ["x", 100]}]}
	raw["duties"] = {"duty_types": [{"id": 3}], "content": {"round_waypoint_sets": {"r": {
			"waypoints": [{"room": "shaft", "floor": 7}, "junk"]}}}}
	raw["endings"] = {"axes": "no", "endings": [{"conditions": {"cause": 5}}], "causes": [null]}
	raw["npcs_generation"] = {"departments": [{"slots": [{"occupation": 4}]}], "roles": 9,
			"routine_templates": {"t": {"segments": [{"location": 12}]}}}
	var db: DatabaseSystem = DatabaseSystem.new()
	check(not db.load_from_raw(raw), "garbage data → load fails gracefully")
	check(db.get_load_errors().size() > 10, "garbage data → many readable errors")
	check_eq(db.get_rooms_by_floor(1).size(), 1, "valid transversal piece still indexed")
	check(db.get_room("shaft@100") != null, "numeric extra_floors kept, junk reported")
	db.free()


static func _index_of(entries: Array, id: String) -> int:
	for i: int in entries.size():
		if entries[i] is Dictionary and entries[i].get("id") == id:
			return i
	return -1
