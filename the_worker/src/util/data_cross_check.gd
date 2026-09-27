# data_cross_check.gd — Comprobaciones cruzadas entre los archivos de data/ (manual §17.1, PASO 4).
# PROPIETARIO DE: nada (la lista de avisos que produce pasa a Database).
# ESCUCHA: nada.
class_name DataCrossCheck
extends RefCounted

## Uso exclusivo de Database (DatabaseSystem._build): DataCrossCheck.new(db, raw).run()
## · Errores (referencias rotas) → Validate.errors, formato exacto de Validate; impiden arrancar.
## · Avisos (coherencia no bloqueante: catálogo de objetos, etiquetas de special_access,
##   leads_to, finales fuera de evaluation_order) → `warnings`, mismo formato.
## Lee el JSON crudo (índices exactos de cada entrada) de forma defensiva: los tipos incorrectos
## ya los ha informado la validación de cada registro, aquí solo se ignoran.

const PROBLEM_REFERENCE := "referencia inexistente"
const PROBLEM_UNCOVERED := "rango sin ocupación"
const PROBLEM_FLOOR := "planta no abarcada por la sala"
const PROBLEM_OVERLAP := "planta asignada a varias bandas"
const PROBLEM_NOT_EVALUATED := "final ausente de evaluation_order"
const EXPECT_OCCUPATION := "id de ocupación (occupations.json)"
const EXPECT_ROOM := "id de sala (rooms/*.json)"
const EXPECT_ROOM_TARGET := "id de sala, \"street\" o \"exterior\""
const EXPECT_LOCATION := "id de sala o ubicación simbólica de rutina"
const EXPECT_ARCHETYPE := "id de arquetipo (archetypes.json)"
const EXPECT_NPC := "id de personaje nominado (npcs_named.json)"
const EXPECT_ROLE := "id de puesto (npcs_generation.json roles) si occupation está vacío"
const EXPECT_DEPARTMENT := "id de departamento (npcs_generation.json departments)"
const EXPECT_TEMPLATE := "id de plantilla (npcs_generation.json routine_templates)"
const EXPECT_SUPERIOR := "id de personaje nominado, \"occ:<ocupación>\" o \"role:<puesto>\""
const EXPECT_LINK_TYPE := "id de vínculo (social_graph.json link_types)"
const EXPECT_GATHERING := "id de corrillo (social_graph.json gatherings)"
const EXPECT_DUTY_TYPE := "id de tipo de deber (duties.json duty_types)"
const EXPECT_WAYPOINT_SET := "id de ronda (duties.json content.round_waypoint_sets)"
const EXPECT_STRATEGY := "id de estrategia (investors.json strategies)"
const EXPECT_FAVOUR := "id de favor (bribes.json favours)"
const EXPECT_AXIS := "eje (endings.json axes)"
const EXPECT_CAUSE := "id de causa (endings.json causes) o \"any\""
const EXPECT_ENDING := "id de final (endings.json endings)"
const EXPECT_PLACEHOLDER := "clave de endings.json placeholder_catalogue"
const EXPECT_BAND := "id de banda (art_bands.json)"
const EXPECT_BALANCE_PATH := "ruta existente de balance.json"
const EXPECT_ITEM := "id de objeto (balance.json objetos)"
const EXPECT_ACCESS_TAG := "etiqueta de occupations.json _special_access_tags"
const EXPECT_ONE_BAND := "una sola banda por planta"
const EXPECT_RANKS := "al menos una ocupación por rango R%d..R%d"
const OCCUPATION_LINK_KEYS: Array[String] = ["promotes_to", "can_jump_to", "demotes_to", "lateral_to"]
## Destinos de connects_to que no son salas de archivo (BUILD_NOTES §3; "street" también es sala).
const ROOM_SPECIAL_TARGETS: Array[String] = ["street", "exterior"]
## Ubicaciones simbólicas de rutina que resuelve NPCDirector (npcs_generation.json, §24.5).
const SYMBOLIC_LOCATIONS: Array[String] = [
	"absent", "home_room", "assigned_zone", "assigned_round", "other_floor", "floor_toilets",
	"floor_pantry", "floor_copyroom", "floor_meeting_room",
]
const LOCATION_KEYS: Array[String] = ["location", "via"]
const LOCATION_LIST_KEYS: Array[String] = ["hideouts"]
## Contenedores cuyo "contains" es información (se lee en pantalla), no objetos de inventario.
const INFO_CONTAINERS: Array[String] = ["npc_computer", "computer", "personnel_files"]
const ITEM_LIST_KEYS: Array[String] = ["contains", "items", "sells", "produces"]
const UNIFORM_ITEM_FORMAT := "uniform_%s"
const ANY_CAUSE := "any"
const OCC_PREFIX := "occ:"
const ROLE_PREFIX := "role:"
const ACCESS_TAGS_KEY := "_special_access_tags"
const LIST_KEY_FORMAT := "%s[%d]"
const PATH_FORMAT := "%s.%s"
const SUBARRAY_FORMAT := "%s (%s)"

var warnings: Array[String] = []
var _db: DatabaseSystem
var _raw: Dictionary
## nombre de conjunto → {id: true} (ids construidos desde el JSON crudo).
var _sets: Dictionary = {}


func _init(db: DatabaseSystem, raw: Dictionary) -> void:
	_db = db
	_raw = raw
	_build_sets()


func run() -> void:
	_check_occupations()
	_check_rank_coverage()
	_check_named_npcs()
	_check_departments()
	_check_generation_tables()
	_check_routine_locations()
	_check_rooms()
	_check_gatherings()
	_check_waypoint_sets()
	_check_investors()
	_check_market()
	_check_investigations()
	_check_endings()
	_check_bribes()
	_check_art_band_floors()
	_check_roles_access()


# ─── Conjuntos de ids ─────────────────────────────────────────

func _build_sets() -> void:
	_sets["role"] = _ids_of("npcs_generation", "roles", "id")
	_sets["department"] = _ids_of("npcs_generation", "departments", "id")
	_sets["link_type"] = _ids_of("social_graph", "link_types", "id")
	_sets["gathering"] = _ids_of("social_graph", "gatherings", "id")
	_sets["duty_type"] = _ids_of("duties", "duty_types", "id")
	_sets["strategy"] = _ids_of("investors", "strategies", "id")
	_sets["favour"] = _ids_of("bribes", "favours", "id")
	_sets["cause"] = _ids_of("endings", "causes", "id")
	_sets["ending"] = _ids_of("endings", "endings", "id")
	_sets["band"] = _ids_of("art_bands", "bands", "id")
	_sets["axis"] = _values_of(_file("endings").get("axes"))
	_sets["template"] = _keys_of(_file("npcs_generation").get("routine_templates"))
	var duty_content: Dictionary = _dict(_file("duties").get("content"))
	_sets["waypoint_set"] = _keys_of(duty_content.get("round_waypoint_sets"))
	_sets["placeholder"] = _keys_of(_file("endings").get("placeholder_catalogue"))
	_sets["item"] = _keys_of(_file("balance").get("objetos"))
	_sets["access_tag"] = _keys_of(_file("occupations").get(ACCESS_TAGS_KEY))


func _ids_of(file_id: String, array_key: String, id_field: String) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in _entries(_file(file_id), array_key):
		if entry is Dictionary and entry.get(id_field) is String:
			out[entry[id_field]] = true
	return out


static func _keys_of(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key: Variant in value:
			if not str(key).begins_with("_"):
				out[str(key)] = true
	return out


static func _values_of(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Array:
		for element: Variant in value:
			if element is String:
				out[element] = true
	return out


# ─── Predicados de existencia (Callable) ──────────────────────

func _in_set(id: String, set_name: String) -> bool:
	return (_sets.get(set_name, {}) as Dictionary).has(id)


func _is_occupation(id: String) -> bool:
	return _db.get_occupation(id) != null


func _is_room(id: String) -> bool:
	return _db.get_room(id) != null


func _is_room_target(id: String) -> bool:
	return _is_room(id) or ROOM_SPECIAL_TARGETS.has(id)


func _is_location(id: String) -> bool:
	return _is_room(id) or SYMBOLIC_LOCATIONS.has(id)


func _is_archetype(id: String) -> bool:
	return _db.get_archetype(id) != null


func _is_npc(id: String) -> bool:
	return _db.get_named_npc(id) != null


func _is_cause(id: String) -> bool:
	return id == ANY_CAUSE or _in_set(id, "cause")


func _is_balance_path(path: String) -> bool:
	return _db.has_balance(path)


## Superior de sala: personaje nominado, "occ:<ocupación>" o "role:<puesto>".
func _is_superior(ref: String) -> bool:
	if ref.begins_with(OCC_PREFIX):
		return _is_occupation(ref.trim_prefix(OCC_PREFIX))
	if ref.begins_with(ROLE_PREFIX):
		return _in_set(ref.trim_prefix(ROLE_PREFIX), "role")
	return _is_npc(ref)


func _in(set_name: String) -> Callable:
	return _in_set.bind(set_name)


## Sin vocabulario de etiquetas no se comprueba special_access.
func _has_access_tags() -> bool:
	return not (_sets.get("access_tag", {}) as Dictionary).is_empty()


# ─── Informe ──────────────────────────────────────────────────

func _report(warn: bool, source: String, key: String, problem: String, expected: String,
		received: String) -> void:
	if warn:
		warnings.append(Validate.ERROR_FORMAT % [source, key, problem, expected, received])
	else:
		Validate.report(source, key, problem, expected, received)


## Informa si `value` no es un String que cumpla `exists`.
func _check_id(value: Variant, key: String, source: String, exists: Callable, expected: String,
		warn: bool = false) -> void:
	if value is String and exists.call(value):
		return
	_report(warn, source, key, PROBLEM_REFERENCE, expected, Validate.describe(value))


## Campo opcional: se comprueba solo si es una cadena no vacía (o un tipo inesperado no nulo).
## `prefix` antepone la ruta mostrada ("duties[2]" → campo 'duties[2].type').
func _check_opt(d: Dictionary, key: String, source: String, exists: Callable, expected: String,
		warn: bool = false, prefix: String = "") -> void:
	var value: Variant = d.get(key)
	if value == null or (value is String and (value as String).is_empty()):
		return
	_check_id(value, _join(prefix, key), source, exists, expected, warn)


## Cada elemento de la lista `key` de `d` (si es lista).
func _check_ids(d: Dictionary, key: String, source: String, exists: Callable, expected: String,
		warn: bool = false, prefix: String = "") -> void:
	var list: Array = _array(d.get(key))
	for j: int in list.size():
		_check_id(list[j], LIST_KEY_FORMAT % [_join(prefix, key), j], source, exists, expected,
				warn)


## Cada clave (no comentario) del diccionario `key` de `d`.
func _check_keys(d: Dictionary, key: String, source: String, exists: Callable,
		expected: String) -> void:
	for sub_key: Variant in Validate.strip_comments(_dict(d.get(key))):
		_check_id(str(sub_key), PATH_FORMAT % [key, sub_key], source, exists, expected)


# ─── Ocupaciones ──────────────────────────────────────────────

func _check_occupations() -> void:
	var list: Array = _entries(_file("occupations"), "occupations")
	for i: int in list.size():
		if not (list[i] is Dictionary):
			continue
		var d: Dictionary = list[i]
		var src: String = Validate.entry("occupations.json", i)
		for key: String in OCCUPATION_LINK_KEYS:
			_check_ids(d, key, src, _is_occupation, EXPECT_OCCUPATION)
		_check_opt(d, "office_room", src, _is_room, EXPECT_ROOM)
		_check_duties(d, src)
		_check_ids(d, "tools", src, _in("item"), EXPECT_ITEM, true)
		if _has_access_tags():
			_check_ids(d, "special_access", src, _in("access_tag"), EXPECT_ACCESS_TAG, true)


func _check_duties(d: Dictionary, src: String) -> void:
	var duties: Array = _array(d.get("duties"))
	for j: int in duties.size():
		var duty: Dictionary = _dict(duties[j])
		var prefix: String = LIST_KEY_FORMAT % ["duties", j]
		_check_opt(duty, "type", src, _in("duty_type"), EXPECT_DUTY_TYPE, false, prefix)
		_check_opt(duty, "waypoint_set", src, _in("waypoint_set"), EXPECT_WAYPOINT_SET, false,
				prefix)


func _check_rank_coverage() -> void:
	var covered: Dictionary = {}
	for occupation: OccupationData in _db.get_all_occupations():
		covered[occupation.rank] = true
	for rank: int in range(OccupationData.MIN_RANK, OccupationData.MAX_RANK + 1):
		if not covered.has(rank):
			Validate.report("occupations.json", "rank", PROBLEM_UNCOVERED,
					EXPECT_RANKS % [OccupationData.MIN_RANK, OccupationData.MAX_RANK], "R%d" % rank)


# ─── Personajes nominados ─────────────────────────────────────

func _check_named_npcs() -> void:
	var list: Array = _entries(_file("npcs_named"), "npcs")
	for i: int in list.size():
		if not (list[i] is Dictionary):
			continue
		var d: Dictionary = list[i]
		var src: String = Validate.entry("npcs_named.json", i)
		_check_npc_post(d, src)
		_check_npc_archetype(d, src)
		_check_opt(d, "home_room", src, _is_room, EXPECT_ROOM)
		_check_opt(d, "home_address", src, _is_room, EXPECT_ROOM)
		_check_opt(d, "future_occupation", src, _is_occupation, EXPECT_OCCUPATION)
		_check_opt(d, "department", src, _in("department"), EXPECT_DEPARTMENT)
		_check_ids(d, "gatherings", src, _in("gathering"), EXPECT_GATHERING)
		_check_npc_links(d, src)
		_check_npc_overrides(d, src)


## occupation existente, o cadena vacía con un role de npcs_generation.json.
func _check_npc_post(d: Dictionary, src: String) -> void:
	var occupation: Variant = d.get("occupation")
	if occupation is String and not (occupation as String).is_empty():
		_check_id(occupation, "occupation", src, _is_occupation, EXPECT_OCCUPATION)
	elif occupation is String:
		_check_id(d.get("role"), "role", src, _in("role"), EXPECT_ROLE)


## Arquetipo existente; se admite un perfil único declarado (unique_profile, p. ej. "ceo").
func _check_npc_archetype(d: Dictionary, src: String) -> void:
	var archetype: Variant = d.get("archetype")
	var unique_profile: Variant = d.get("unique_profile")
	var is_unique: bool = archetype is String and unique_profile is String \
			and not (unique_profile as String).is_empty() and archetype == unique_profile
	if not is_unique and archetype != null:
		_check_id(archetype, "archetype", src, _is_archetype, EXPECT_ARCHETYPE)
	_check_opt(d, "secondary_archetype", src, _is_archetype, EXPECT_ARCHETYPE)


func _check_npc_links(d: Dictionary, src: String) -> void:
	var links: Array = _array(d.get("initial_links"))
	for j: int in links.size():
		var link: Dictionary = _dict(links[j])
		var prefix: String = LIST_KEY_FORMAT % ["initial_links", j]
		_check_opt(link, "to", src, _is_npc, EXPECT_NPC, false, prefix)
		_check_opt(link, "type", src, _in("link_type"), EXPECT_LINK_TYPE, false, prefix)
		_check_opt(link, "beneficiary", src, _is_npc, EXPECT_NPC, false, prefix)
		if link.get("to") is String and link["to"] == str(d.get("id", "")):
			_report(false, src, PATH_FORMAT % [prefix, "to"], PROBLEM_REFERENCE,
					"otro personaje", Validate.describe(link["to"]))


func _check_npc_overrides(d: Dictionary, src: String) -> void:
	var overrides: Array = _array(d.get("routine_overrides"))
	for j: int in overrides.size():
		var entry: Dictionary = _dict(overrides[j])
		var prefix: String = LIST_KEY_FORMAT % ["routine_overrides", j]
		_check_opt(entry, "location", src, _is_location, EXPECT_LOCATION, false, prefix)
		_check_opt(entry, "target", src, _is_npc, EXPECT_NPC, false, prefix)


# ─── Generación de plantilla (npcs_generation.json) ───────────

func _check_departments() -> void:
	var list: Array = _entries(_file("npcs_generation"), "departments")
	for i: int in list.size():
		if not (list[i] is Dictionary):
			continue
		var d: Dictionary = list[i]
		var src: String = Validate.entry(SUBARRAY_FORMAT % ["npcs_generation.json", "departments"],
				i)
		_check_ids(d, "rooms", src, _is_room, EXPECT_ROOM)
		_check_ids(d, "named_npcs", src, _is_npc, EXPECT_NPC)
		_check_ids(d, "occupations", src, _is_occupation, EXPECT_OCCUPATION)
		_check_ids(d, "roles", src, _in("role"), EXPECT_ROLE)
		_check_keys(d, "archetype_bag", src, _is_archetype, EXPECT_ARCHETYPE)
		_check_opt(d, "parent", src, _in("department"), EXPECT_DEPARTMENT)
		_check_ids(d, "subsets", src, _in("department"), EXPECT_DEPARTMENT)
		_check_slots(d, src)


func _check_slots(d: Dictionary, src: String) -> void:
	var slots: Array = _array(d.get("slots"))
	for j: int in slots.size():
		var slot: Dictionary = _dict(slots[j])
		var prefix: String = LIST_KEY_FORMAT % ["slots", j]
		var occupation: Variant = slot.get("occupation", "")
		if occupation is String and (occupation as String).is_empty():
			_check_id(slot.get("role"), _join(prefix, "role"), src, _in("role"), EXPECT_ROLE)
		else:
			_check_id(occupation, _join(prefix, "occupation"), src, _is_occupation,
					EXPECT_OCCUPATION)
		_check_id(slot.get("room"), _join(prefix, "room"), src, _is_room, EXPECT_ROOM)
		_check_opt(slot, "archetype", src, _is_archetype, EXPECT_ARCHETYPE, false, prefix)
		_check_opt(slot, "routine_template", src, _in("template"), EXPECT_TEMPLATE, false, prefix)


func _check_generation_tables() -> void:
	var gen: Dictionary = _file("npcs_generation")
	var src: String = "npcs_generation.json"
	_check_values(gen, "tier_to_routine_template", src, _in("template"), EXPECT_TEMPLATE)
	_check_values(gen, "tier_to_home_address", src, _is_room, EXPECT_ROOM)
	var table_key: String = "occupation_routine_template"
	var by_occupation: Dictionary = Validate.strip_comments(_dict(gen.get(table_key)))
	for occupation: Variant in by_occupation:
		var key: String = PATH_FORMAT % [table_key, occupation]
		_check_id(str(occupation), key, src, _is_occupation, EXPECT_OCCUPATION)
		var templates: Variant = by_occupation[occupation]
		for template: Variant in (templates.values() if templates is Dictionary else [templates]):
			_check_id(template, key, src, _in("template"), EXPECT_TEMPLATE)
	_check_hierarchy(_dict(_dict(gen.get("link_generation")).get("hierarchy")), src)
	_check_fixed_links(_array(gen.get("fixed_generated_links")))
	_check_gathering_membership(_dict(gen.get("gathering_membership")), src)


## Cada valor (no comentario) del diccionario `key` de `d`.
func _check_values(d: Dictionary, key: String, source: String, exists: Callable,
		expected: String) -> void:
	var table: Dictionary = Validate.strip_comments(_dict(d.get(key)))
	for sub_key: Variant in table:
		_check_id(table[sub_key], PATH_FORMAT % [key, sub_key], source, exists, expected)


func _check_hierarchy(hierarchy: Dictionary, src: String) -> void:
	var by_room: Dictionary = Validate.strip_comments(_dict(hierarchy.get("superior_by_room")))
	for room_id: Variant in by_room:
		var key: String = "link_generation.hierarchy.superior_by_room.%s" % room_id
		_check_id(str(room_id), key, src, _is_room, EXPECT_ROOM)
		_check_id(by_room[room_id], key, src, _is_superior, EXPECT_SUPERIOR)


func _check_fixed_links(links: Array) -> void:
	for j: int in links.size():
		var link: Dictionary = _dict(links[j])
		var src: String = Validate.entry(SUBARRAY_FORMAT % ["npcs_generation.json",
				"fixed_generated_links"], j)
		_check_opt(link, "type", src, _in("link_type"), EXPECT_LINK_TYPE)
		_check_opt(link, "department", src, _in("department"), EXPECT_DEPARTMENT)
		_check_opt(link, "room", src, _is_room, EXPECT_ROOM)
		_check_opt(link, "gathering", src, _in("gathering"), EXPECT_GATHERING)


func _check_gathering_membership(membership: Dictionary, src: String) -> void:
	for gathering: Variant in Validate.strip_comments(membership):
		var key: String = PATH_FORMAT % ["gathering_membership", gathering]
		_check_id(str(gathering), key, src, _in("gathering"), EXPECT_GATHERING)
		var rule: Dictionary = _dict(membership[gathering])
		_check_ids(rule, "departments", src, _in("department"), EXPECT_DEPARTMENT)
		_check_ids(rule, "home_rooms", src, _is_room, EXPECT_ROOM)


## Ubicaciones de routine_templates y routine_common_modifiers (location, via, hideouts).
func _check_routine_locations() -> void:
	var gen: Dictionary = _file("npcs_generation")
	for key: String in ["routine_templates", "routine_common_modifiers"]:
		_walk_locations(gen.get(key), key)


func _walk_locations(value: Variant, path: String) -> void:
	if value is Array:
		for j: int in (value as Array).size():
			_walk_locations(value[j], LIST_KEY_FORMAT % [path, j])
		return
	if not (value is Dictionary):
		return
	for key: Variant in Validate.strip_comments(value):
		var sub_path: String = PATH_FORMAT % [path, key]
		if LOCATION_KEYS.has(str(key)) and value[key] is String:
			_check_id(value[key], sub_path, "npcs_generation.json", _is_location, EXPECT_LOCATION)
		elif LOCATION_LIST_KEYS.has(str(key)):
			_check_ids(value, str(key), "npcs_generation.json → %s" % path, _is_location,
					EXPECT_LOCATION)
		else:
			_walk_locations(value[key], sub_path)


# ─── Salas ────────────────────────────────────────────────────

func _check_rooms() -> void:
	for file_id: String in _raw:
		if not file_id.begins_with(DatabaseSystem.ROOMS_PREFIX):
			continue
		var list: Array = _entries(_file(file_id), "rooms")
		for i: int in list.size():
			if not (list[i] is Dictionary):
				continue
			var d: Dictionary = list[i]
			var src: String = Validate.entry(file_id + DatabaseSystem.JSON_EXTENSION, i)
			_check_ids(d, "connects_to", src, _is_room_target, EXPECT_ROOM_TARGET)
			_check_opt(d, "art_band", src, _in("band"), EXPECT_BAND)
			if _has_access_tags():
				_check_ids(d, "special_access", src, _in("access_tag"), EXPECT_ACCESS_TAG, true)
			_check_interactables(_array(d.get("interactables")), src)


## Avisos: objetos que contienen/venden/producen los interactivos, uniformes y leads_to.
func _check_interactables(list: Array, src: String) -> void:
	for j: int in list.size():
		var it: Dictionary = _dict(list[j])
		var prefix: String = LIST_KEY_FORMAT % ["interactables", j]
		if not INFO_CONTAINERS.has(str(it.get("type", ""))):
			for key: String in ITEM_LIST_KEYS:
				if it.get(key) is String:
					_check_opt(it, key, src, _in("item"), EXPECT_ITEM, true, prefix)
				else:
					_check_ids(it, key, src, _in("item"), EXPECT_ITEM, true, prefix)
		if it.get("uniform") is String:
			_check_id(it["uniform"], _join(prefix, "uniform"), src, _is_uniform, EXPECT_ITEM, true)
		_check_ids(it, "leads_to", src, _is_room_target, EXPECT_ROOM_TARGET, true, prefix)


## Uniforme: id de objeto ("uniform_security") o su forma corta ("security").
func _is_uniform(value: String) -> bool:
	return _in_set(value, "item") or _in_set(UNIFORM_ITEM_FORMAT % value, "item")


func _check_gatherings() -> void:
	var list: Array = _entries(_file("social_graph"), "gatherings")
	for i: int in list.size():
		var src: String = Validate.entry(SUBARRAY_FORMAT % ["social_graph.json", "gatherings"], i)
		_check_opt(_dict(list[i]), "room", src, _is_room_target, EXPECT_ROOM_TARGET)


## Paradas de ronda: la sala existe y abarca la planta indicada (transversales: "@planta").
func _check_waypoint_sets() -> void:
	var sets: Dictionary = _dict(_dict(_file("duties").get("content")).get("round_waypoint_sets"))
	for set_id: Variant in Validate.strip_comments(sets):
		var round_set: Dictionary = _dict(sets[set_id])
		var src: String = "duties.json → content.round_waypoint_sets.%s" % set_id
		_check_ids(round_set, "occupations", src, _is_occupation, EXPECT_OCCUPATION)
		var waypoints: Array = _array(round_set.get("waypoints"))
		for j: int in waypoints.size():
			_check_waypoint(_dict(waypoints[j]), LIST_KEY_FORMAT % ["waypoints", j], src)


func _check_waypoint(waypoint: Dictionary, prefix: String, src: String) -> void:
	var room_id: Variant = waypoint.get("room")
	_check_id(room_id, PATH_FORMAT % [prefix, "room"], src, _is_room, EXPECT_ROOM)
	var floor_value: Variant = waypoint.get("floor")
	if not (room_id is String and _is_room(room_id)) or floor_value == null:
		return
	var room: RoomData = _db.get_room(room_id)
	var floor_number: int = int(floor_value) if (floor_value is int or floor_value is float) else 0
	var instance_id: String = DatabaseSystem.make_room_instance_id(room.id, floor_number)
	var ok: bool = _is_room(instance_id) if room.is_transversal() else room.floor == floor_number
	if not ok:
		_report(false, src, PATH_FORMAT % [prefix, "floor"], PROBLEM_FLOOR,
				"planta de la sala '%s'" % room.id, Validate.describe(floor_value))


# ─── Inversores, mercado, investigaciones ─────────────────────

func _check_investors() -> void:
	var list: Array = _entries(_file("investors"), "investors")
	for i: int in list.size():
		var d: Dictionary = _dict(list[i])
		var src: String = Validate.entry("investors.json", i)
		_check_opt(d, "strategy", src, _in("strategy"), EXPECT_STRATEGY)
		_check_opt(d, "office_room", src, _is_room, EXPECT_ROOM)


func _check_market() -> void:
	var events: Array = _entries(_file("market_events"), "events")
	for i: int in events.size():
		var d: Dictionary = _dict(events[i])
		var src: String = Validate.entry("market_events.json", i)
		_check_opt(d, "mitigable_by", src, _is_occupation, EXPECT_OCCUPATION)
		_check_opt(d, "amplifiable_by", src, _is_occupation, EXPECT_OCCUPATION)
	var calendar: Dictionary = _dict(_file("market").get("calendar"))
	_check_opt(_dict(calendar.get("results_presentation")), "room",
			"market.json → calendar.results_presentation", _is_room, EXPECT_ROOM)


func _check_investigations() -> void:
	var inv: Dictionary = _file("investigations")
	var search: Dictionary = _dict(inv.get("room_search"))
	var order: Array = _array(search.get("order"))
	for j: int in order.size():
		_check_opt(_dict(order[j]), "room", "investigations.json → room_search.order[%d]" % j,
				_is_room, EXPECT_ROOM)
	_check_ids(search, "never_searched", "investigations.json → room_search", _is_room, EXPECT_ROOM)
	_check_ids(search, "irrelevant", "investigations.json → room_search", _is_room, EXPECT_ROOM)
	var interrogation: Dictionary = _dict(inv.get("interrogation"))
	var src: String = "investigations.json → interrogation"
	_check_opt(interrogation, "room", src, _is_room, EXPECT_ROOM)
	_check_opt(interrogation, "default_interrogator", src, _is_npc, EXPECT_NPC)
	_check_ids(interrogation, "interrogator_occupations", src, _is_occupation, EXPECT_OCCUPATION)
	var types: Array = _array(inv.get("evidence_types"))
	for j: int in types.size():
		_check_opt(_dict(types[j]), "balance_path",
				Validate.entry(SUBARRAY_FORMAT % ["investigations.json", "evidence_types"], j),
				_is_balance_path, EXPECT_BALANCE_PATH)
	_check_opt(_dict(inv.get("cold_case_revival")), "permanent_close_occupation",
			"investigations.json → cold_case_revival", _is_occupation, EXPECT_OCCUPATION)


# ─── Finales ──────────────────────────────────────────────────

func _check_endings() -> void:
	var endings: Dictionary = _file("endings")
	var list: Array = _entries(endings, "endings")
	for i: int in list.size():
		var d: Dictionary = _dict(list[i])
		var src: String = Validate.entry("endings.json", i)
		var conditions: Dictionary = _dict(d.get("conditions"))
		_check_opt(conditions, "dominant_axis", src, _in("axis"), EXPECT_AXIS, false, "conditions")
		_check_ids(conditions, "cause", src, _is_cause, EXPECT_CAUSE, false, "conditions")
		_check_ids(d, "placeholders", src, _in("placeholder"), EXPECT_PLACEHOLDER)
		var evaluated: Array = _array(endings.get("evaluation_order"))
		if d.get("id") is String and not evaluated.has(d["id"]):
			_report(true, src, "id", PROBLEM_NOT_EVALUATED, "id listado en evaluation_order",
					Validate.describe(d["id"]))
	var src_file: String = "endings.json"
	_check_ids(endings, "evaluation_order", src_file, _in("ending"), EXPECT_ENDING)
	_check_opt(endings, "fallback_ending", src_file, _in("ending"), EXPECT_ENDING)
	_check_ids(endings, "dominant_tie_break", src_file, _in("axis"), EXPECT_AXIS)
	var ruin: Dictionary = _dict(endings.get("ruin_modifier"))
	var axis_keys: Dictionary = _keys_of(endings.get("axis_name_keys"))
	if ruin.get("axis") is String and not axis_keys.has(ruin["axis"]):
		_report(false, src_file, "ruin_modifier.axis", PROBLEM_REFERENCE,
				"clave de axis_name_keys", Validate.describe(ruin["axis"]))


# ─── Sobornos, bandas, etiquetas ──────────────────────────────

func _check_bribes() -> void:
	var channels: Array = _entries(_file("bribes"), "channels")
	for i: int in channels.size():
		_check_opt(_dict(channels[i]), "forced_favour",
				Validate.entry(SUBARRAY_FORMAT % ["bribes.json", "channels"], i), _in("favour"),
				EXPECT_FAVOUR)


## Cada planta pertenece como mucho a una banda (get_art_band_for_floor es inequívoco).
func _check_art_band_floors() -> void:
	var owner: Dictionary = {}
	var list: Array = _entries(_file("art_bands"), "bands")
	for i: int in list.size():
		var band: Dictionary = _dict(list[i])
		var floors: Array = _array(band.get("floors"))
		for j: int in floors.size():
			if not (floors[j] is int or floors[j] is float):
				continue
			var floor_number: int = int(floors[j])
			if owner.has(floor_number):
				_report(false, Validate.entry("art_bands.json", i), LIST_KEY_FORMAT % ["floors", j],
						PROBLEM_OVERLAP, EXPECT_ONE_BAND, "planta %d (ya en %s)"
						% [floor_number, owner[floor_number]])
			else:
				owner[floor_number] = str(band.get("id", ""))


## Avisos: etiquetas de special_access de los puestos no jugables.
func _check_roles_access() -> void:
	if not _has_access_tags():
		return
	var roles: Array = _entries(_file("npcs_generation"), "roles")
	for i: int in roles.size():
		_check_ids(_dict(roles[i]), "special_access",
				Validate.entry(SUBARRAY_FORMAT % ["npcs_generation.json", "roles"], i),
				_in("access_tag"), EXPECT_ACCESS_TAG, true)


# ─── Acceso defensivo al JSON crudo ───────────────────────────

func _file(file_id: String) -> Dictionary:
	return _dict(_raw.get(file_id))


static func _join(prefix: String, key: String) -> String:
	return key if prefix.is_empty() else PATH_FORMAT % [prefix, key]


static func _entries(d: Dictionary, key: String) -> Array:
	return _array(d.get(key))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _array(value: Variant) -> Array:
	return value if value is Array else []
