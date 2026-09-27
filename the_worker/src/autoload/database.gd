# database.gd — Carga, valida y expone en solo lectura todos los datos estáticos de data/.
# PROPIETARIO DE: la totalidad de los datos estáticos cargados desde data/ (§19.1) y el preset de dificultad activo.
# ESCUCHA: nada.
class_name DatabaseSystem
extends Node

## Manual §19.1, §17.1 y PASO 4; BUILD_NOTES §2-§4.
## · load_all(): lee los 16 orígenes de data/ (15 JSON + data/rooms/*.json), valida cada registro
##   con las clases de src/core y Validate, ejecuta las comprobaciones cruzadas (DataCrossCheck)
##   y construye los índices. Idempotente: la segunda llamada devuelve el resultado en caché.
##   Nunca lanza: los problemas se acumulan en get_load_errors() con el formato exacto
##   "ARCHIVO → entrada N → campo 'clave': PROBLEMA (esperado X, recibido Y)". Los avisos no
##   bloqueantes (catálogo de objetos, etiquetas de acceso) van a get_load_warnings().
##   Cualquier consulta anterior a load_all() dispara la carga (carga perezosa, una vez).
## · load_all_or_halt(): variante del arranque real (boot.gd / game_root.gd). Si falla, publica el
##   informe (push_error + stderr) y detiene el arranque; en headless sale con código 1. Quien la
##   llama debe mostrar get_load_report() y no continuar.
## · load_from_raw(raw): igual que load_all() pero desde diccionarios ya parseados (tests).
## · Solo lectura: los Array y Dictionary devueltos son copias. Los objetos tipados estáticos
##   (OccupationData, RoomData, ArchetypeData, NPCData, InvestorData) se comparten por
##   rendimiento y NO deben modificarse. ItemData (clase de ejecución) se devuelve siempre copiado.
## · Salas transversales (§22.15, BUILD_NOTES §3): la sala base (floor -99, floors [min, max],
##   extra_floors opcional) se obtiene por su id; además hay una copia por planta abarcada con id
##   "<id>@<planta>", floor = planta y extra {base_id, instance_floor}. Los ids de cámaras,
##   escondites e interactivos de la copia llevan el mismo sufijo (su base_id guarda el original).
##   get_rooms_by_floor(p) = salas de p + esas copias. get_all_rooms() y get_rooms_by_clearance()
##   solo devuelven salas base (166 con el edificio completo).
## · Objetos (§11.3): catálogo en balance.json → objetos (clave = id; ver su _nota).
## · Partida: lo único de Database que pertenece a la partida es el preset de dificultad activo
##   (§15.7): save_state()/load_state() lo guardan y restauran (SaveSystem carga Database antes que
##   el resto de sistemas, así cada load_state ya lee los modificadores de esa partida).

const DATA_DIR := "res://data/"
const S_DIFFICULTY := "difficulty_preset"
const JSON_EXTENSION := ".json"
const ROOMS_PREFIX := "rooms/"
const ROOMS_KIND := "rooms"
const DATA_FILES: Array[String] = [
	"balance", "occupations", "archetypes", "npcs_named", "npcs_generation", "social_graph",
	"bribes", "ideas", "duties", "investors", "market", "market_events", "investigations",
	"endings", "art_bands",
]
## Un archivo por planta (§17.2) más los espacios transversales (§22.15).
const ROOM_FILES: Array[String] = [
	"s3", "s2", "s1", "pb", "factory", "p01", "p02", "p03", "p04", "p05", "p06", "p07", "p08",
	"p09", "p10", "p11", "p12", "p13", "p14", "p15", "p16", "p17", "p18", "p19", "p20",
	"transversal", "exterior",
]
## Claves de nivel superior obligatorias por archivo → tipo ("number" = int o float).
const TOP_LEVEL_KEYS: Dictionary = {
	"balance": {
		"economia": "Dictionary", "tiempo": "Dictionary", "percepcion": "Dictionary",
		"ruido": "Dictionary", "creencias": "Dictionary", "sobornos": "Dictionary",
		"investigaciones": "Dictionary", "mercado": "Dictionary", "ideas": "Dictionary",
		"deberes": "Dictionary", "descontento": "Dictionary", "seguimiento": "Dictionary",
		"lod": "Dictionary", "dificultad": "Dictionary", "presets_por_defecto": "String",
		"mundo": "Dictionary", "objetos": "Dictionary",
	},
	"occupations": {"occupations": "Array"},
	"archetypes": {"archetypes": "Array", "variation_range": "number"},
	"npcs_named": {"npcs": "Array"},
	"npcs_generation": {
		"departments": "Array", "roles": "Array", "name_bank": "Dictionary",
		"routine_templates": "Dictionary",
	},
	"social_graph": {"link_types": "Array", "gatherings": "Array"},
	"bribes": {"favours": "Array", "channels": "Array"},
	"ideas": {"templates": "Array", "acquisition_methods": "Array"},
	"duties": {"duty_types": "Array", "content": "Dictionary"},
	"investors": {"strategies": "Array", "investors": "Array"},
	"market": {"simulation": "Dictionary", "calendar": "Dictionary"},
	"market_events": {"events": "Array"},
	"investigations": {"phases": "Array", "thresholds": "Dictionary", "evidence_weights": "Dictionary"},
	"endings": {"axes": "Array", "causes": "Array", "endings": "Array", "evaluation_order": "Array"},
	"art_bands": {"bands": "Array"},
	"rooms": {"rooms": "Array"},
}
## Colecciones sin clase tipada: "archivo.clave" → {campo: tipo}. El primer campo "id" es la clave.
const RECORD_SPECS: Dictionary = {
	"bribes.favours": {"id": "id", "name_key": "String", "multiplier": "number"},
	"bribes.channels": {"id": "id", "leaves_digital_record": "bool"},
	"social_graph.link_types": {
		"id": "id", "strength_min": "number", "strength_max": "number", "propagates": "String",
		"directed": "bool",
	},
	"social_graph.gatherings": {"id": "id", "amplification": "number"},
	"ideas.templates": {
		"department": "id", "quality_min": "number", "quality_max": "number", "text_keys": "Array",
	},
	"ideas.acquisition_methods": {"id": "id", "risk": "String", "leaves_trace": "String"},
	"duties.duty_types": {"id": "id", "interface": "String", "automatable": "bool"},
	"investors.strategies": {"id": "id", "weight_fundamentals": "number"},
	"market_events.events": {
		"id": "id", "name_key": "String", "probability_per_quarter": "number",
		"effects": "Dictionary",
	},
	"investigations.phases": {"id": "id", "number": "number", "name_key": "String"},
	"endings.causes": {"id": "id", "name_key": "String"},
	"endings.endings": {
		"id": "id", "name_key": "String", "category": "String", "conditions": "Dictionary",
		"epilogue_key": "String", "has_ruin_variants": "bool",
	},
	"art_bands.bands": {"id": "id", "name_key": "String", "floors": "Array", "palette": "Dictionary"},
	"npcs_generation.departments": {
		"id": "id", "population": "number", "rooms": "Array", "archetype_bag": "Dictionary",
		"tier_range": "Array",
	},
	"npcs_generation.roles": {
		"id": "id", "name_key": "String", "tier": "number", "clearance": "number",
		"daily_wage": "number",
	},
}
## Colecciones cuya matriz es la principal del archivo: su origen es "archivo.json → entrada N".
const MAIN_COLLECTIONS: Array[String] = ["market_events.events", "art_bands.bands"]
const COL_FAVOURS := "bribes.favours"
const COL_CHANNELS := "bribes.channels"
const COL_LINK_TYPES := "social_graph.link_types"
const COL_GATHERINGS := "social_graph.gatherings"
const COL_IDEA_TEMPLATES := "ideas.templates"
const COL_DUTY_TYPES := "duties.duty_types"
const COL_STRATEGIES := "investors.strategies"
const COL_EVENTS := "market_events.events"
const COL_ENDINGS := "endings.endings"
const COL_BANDS := "art_bands.bands"
const COL_DEPARTMENTS := "npcs_generation.departments"
const COL_ROLES := "npcs_generation.roles"
const DEFAULT_IDEA_DEPARTMENT := "general"
const ITEMS_SECTION := "objetos"
const DIFFICULTY_SECTION := "dificultad"
const DEFAULT_PRESET_KEY := "presets_por_defecto"
const NEUTRAL_MODIFIER := 1.0
const INSTANCE_SEPARATOR := "@"
const INSTANCE_SUFFIX_FORMAT := "@%d"
const EXTRA_BASE_ID := "base_id"
const EXTRA_INSTANCE_FLOOR := "instance_floor"
const EXTRA_FLOORS_KEY := "extra_floors"
const INSTANCE_ID_LISTS: Array[String] = ["camera_positions", "hiding_spots", "interactables"]
const SUBARRAY_SOURCE_FORMAT := "%s (%s)"
## Clave mostrada cuando el problema afecta a un archivo o a una entrada completos.
const WHOLE_FILE_KEY := "(archivo)"
const WHOLE_ENTRY_KEY := "(entrada)"
const ITEM_SOURCE_FORMAT := "balance.json → objetos.%s"
const INSTANCE_SOURCE_FORMAT := "%s (planta %d)"
const FILE_ERROR_FORMAT := "%s → archivo: %s (esperado %s, recibido %s)"
const PROBLEM_FILE_MISSING := "archivo no encontrado"
const PROBLEM_FILE_JSON := "JSON no válido"
const PROBLEM_FILE_UNKNOWN := "archivo no previsto (se ignora)"
const PROBLEM_DUPLICATE := "identificador duplicado"
const PROBLEM_KEY_MISMATCH := "id distinto de la clave"
const PROBLEM_PRESET_KEYS := "claves distintas entre presets"
const EXPECTED_JSON_FILE := "archivo JSON en data/"
const EXPECTED_VALID_JSON := "JSON válido"
const JSON_ERROR_FORMAT := "línea %d: %s"
const BALANCE_MISSING_FORMAT := "Database: ruta de balance inexistente '%s'"
const BALANCE_TYPE_FORMAT := "Database: '%s' no es %s (recibido %s)"
const PRESET_UNKNOWN_FORMAT := "Database: preset de dificultad desconocido '%s'"
const MODIFIER_PATH_FORMAT := "dificultad.%s.%s"
const LOAD_FAILED_KEY := "UI_DATA_LOAD_FAILED"
const REPORT_LINE_FORMAT := "  - %s"
const BOOT_FAILURE_EXIT_CODE := 1
const HEADLESS_DISPLAY := "headless"

var _attempted: bool = false
var _load_ok: bool = false
var _errors: Array[String] = []
var _warnings: Array[String] = []
## file_id ("balance", "rooms/p03"...) → Dictionary parseado (JSON íntegro, con comentarios).
var _raw: Dictionary = {}
## Ruta con puntos → valor (hojas y nodos intermedios de balance.json, sin comentarios "_").
var _balance_flat: Dictionary = {}
var _difficulty_preset: String = ""
var _occupations: Dictionary = {}
var _occupation_list: Array[OccupationData] = []
var _rooms: Dictionary = {}
var _room_list: Array[RoomData] = []
var _room_instances: Dictionary = {}
## planta (int) → Array de RoomData (salas base de la planta + copias transversales).
var _rooms_by_floor: Dictionary = {}
var _archetypes: Dictionary = {}
var _archetype_list: Array[ArchetypeData] = []
var _named_npcs: Dictionary = {}
var _named_npc_list: Array[NPCData] = []
var _investors: Dictionary = {}
var _investor_list: Array[InvestorData] = []
var _items: Dictionary = {}
var _item_list: Array[ItemData] = []
## "archivo.clave" → {id → Dictionary} y "archivo.clave" → Array[String] (orden del archivo).
var _records: Dictionary = {}
var _record_order: Dictionary = {}


func reset_for_new_run() -> void:
	pass


## El preset de dificultad de la partida (§15.7).
func save_state() -> Dictionary:
	return {S_DIFFICULTY: get_difficulty_preset()}


## Un preset desconocido (datos cambiados entre versiones) conserva el activo, con aviso.
func load_state(data: Dictionary) -> void:
	var preset: String = str(data.get(S_DIFFICULTY, ""))
	if preset.is_empty() or preset == get_difficulty_preset():
		return
	if get_difficulty_presets().has(preset):
		_difficulty_preset = preset
	else:
		push_warning(PRESET_UNKNOWN_FORMAT % preset)


# ─── Carga y validación al arrancar ───────────────────────────

func load_all() -> bool:
	if _attempted:
		return _load_ok
	_attempted = true
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var raw: Dictionary = _read_all_files(errors, warnings)
	return _build(raw, errors, warnings)


func get_load_errors() -> Array[String]:
	return _errors.duplicate()


## Extra: avisos no bloqueantes de la última carga (mismo formato que los errores).
func get_load_warnings() -> Array[String]:
	return _warnings.duplicate()


## Extra: true si la última carga terminó sin errores.
func is_loaded() -> bool:
	return _load_ok


## Extra: fuerza una relectura completa de data/ (herramientas de desarrollo).
func reload_all() -> bool:
	_attempted = false
	return load_all()


## Extra (tests/herramientas): carga desde {file_id: Dictionary} sin leer disco. Los file_id
## esperados que falten se informan como archivos no encontrados.
func load_from_raw(raw: Dictionary) -> bool:
	var errors: Array[String] = []
	for file_id: String in get_expected_file_ids():
		if not raw.has(file_id):
			errors.append(FILE_ERROR_FORMAT % [_file_name(file_id), PROBLEM_FILE_MISSING,
					EXPECTED_JSON_FILE, Validate.RECEIVED_NOTHING])
	_attempted = true
	var empty: Array[String] = []
	return _build(raw.duplicate(true), errors, empty)


## Extra, para el arranque real: carga y, si falla, detiene el arranque con mensaje explícito.
## Devuelve false si el arranque no debe continuar (mostrar entonces get_load_report()).
func load_all_or_halt() -> bool:
	if load_all():
		for warning: String in _warnings:
			push_warning(warning)
		return true
	var report: String = get_load_report()
	push_error(report)
	printerr(report)
	if DisplayServer.get_name() == HEADLESS_DISPLAY:
		get_tree().quit(BOOT_FAILURE_EXIT_CODE)
	return false


## Extra: informe legible de la carga (cabecera traducida + un error por línea).
func get_load_report() -> String:
	if _errors.is_empty():
		return ""
	var header: String = tr(LOAD_FAILED_KEY)
	if header.contains("%d"):
		header = header % _errors.size()
	var lines: PackedStringArray = [header]
	for error: String in _errors:
		lines.append(REPORT_LINE_FORMAT % error)
	return "\n".join(lines)


## Extra: identificadores de los orígenes esperados ("balance", ..., "rooms/s3", ...).
func get_expected_file_ids() -> Array[String]:
	var out: Array[String] = DATA_FILES.duplicate()
	for room_file: String in ROOM_FILES:
		out.append(ROOMS_PREFIX + room_file)
	return out


## Extra: orígenes cargados en la última carga, en el orden esperado.
func get_data_file_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for file_id: String in _raw:
		out.append(file_id)
	return out


## Extra: copia profunda del JSON íntegro de un origen ("balance", "rooms/p03", con o sin
## ".json"). {} si no existe.
func get_raw(file_id: String) -> Dictionary:
	_ensure_loaded()
	var key: String = file_id.trim_suffix(JSON_EXTENSION)
	var value: Variant = _raw.get(key)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


# ─── Acceso a ocupaciones ─────────────────────────────────────

func get_occupation(id: String) -> OccupationData:
	_ensure_loaded()
	return _occupations.get(id) as OccupationData


func get_occupations_by_rank(rank: int) -> Array[OccupationData]:
	_ensure_loaded()
	var out: Array[OccupationData] = []
	for occupation: OccupationData in _occupation_list:
		if occupation.rank == rank:
			out.append(occupation)
	return out


func get_occupations_by_tier(tier: int) -> Array[OccupationData]:
	_ensure_loaded()
	var out: Array[OccupationData] = []
	for occupation: OccupationData in _occupation_list:
		if occupation.tier == tier:
			out.append(occupation)
	return out


func get_all_occupations() -> Array[OccupationData]:
	_ensure_loaded()
	return _occupation_list.duplicate()


## Extra: ocupaciones cuyo campo extra "department" coincide (base, factory, security...).
func get_occupations_by_department(department: String) -> Array[OccupationData]:
	_ensure_loaded()
	var out: Array[OccupationData] = []
	for occupation: OccupationData in _occupation_list:
		if str(occupation.extra.get("department", "")) == department:
			out.append(occupation)
	return out


# ─── Acceso a salas ───────────────────────────────────────────

## Admite ids base y de copia transversal por planta ("corridors_low@3").
func get_room(id: String) -> RoomData:
	_ensure_loaded()
	if _rooms.has(id):
		return _rooms[id]
	return _room_instances.get(id) as RoomData


@warning_ignore("shadowed_global_identifier")
func get_rooms_by_floor(floor: int) -> Array[RoomData]:
	_ensure_loaded()
	var out: Array[RoomData] = []
	out.assign(_rooms_by_floor.get(floor, []))
	return out


func get_rooms_by_clearance(max_clearance: int) -> Array[RoomData]:
	_ensure_loaded()
	var out: Array[RoomData] = []
	for room: RoomData in _room_list:
		if room.clearance_required <= max_clearance:
			out.append(room)
	return out


func get_all_rooms() -> Array[RoomData]:
	_ensure_loaded()
	return _room_list.duplicate()


## Extra: plantas con salas (sin la pseudo-planta transversal), ordenadas.
func get_floor_ids() -> Array[int]:
	_ensure_loaded()
	var out: Array[int] = []
	for key: Variant in _rooms_by_floor:
		if int(key) != RoomData.TRANSVERSAL_FLOOR:
			out.append(int(key))
	out.sort()
	return out


## Extra: id base de una copia transversal ("corridors_low@3" → "corridors_low").
static func get_room_base_id(id: String) -> String:
	return id.get_slice(INSTANCE_SEPARATOR, 0)


## Extra: id de la copia de una sala transversal en una planta ("corridors_low", 3).
static func make_room_instance_id(base_id: String, floor_number: int) -> String:
	return base_id + INSTANCE_SUFFIX_FORMAT % floor_number


# ─── Acceso a personajes y arquetipos ─────────────────────────

func get_archetype(id: String) -> ArchetypeData:
	_ensure_loaded()
	return _archetypes.get(id) as ArchetypeData


## Extra.
func get_all_archetypes() -> Array[ArchetypeData]:
	_ensure_loaded()
	return _archetype_list.duplicate()


## Extra: variación ± por rasgo de los personajes generados (archetypes.json).
func get_archetype_variation_range() -> int:
	_ensure_loaded()
	var value: Variant = _file("archetypes").get("variation_range", 0)
	return int(value) if (value is int or value is float) else 0


func get_named_npc(id: String) -> NPCData:
	_ensure_loaded()
	return _named_npcs.get(id) as NPCData


func get_all_named_npcs() -> Array[NPCData]:
	_ensure_loaded()
	return _named_npc_list.duplicate()


## Departamento de npcs_generation.json (población, salas, bolsa de arquetipos, plazas...).
## {} si no existe. Las tablas globales del archivo: get_raw("npcs_generation").
func get_generation_rules(department: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_DEPARTMENTS, department)


## Extra: puesto no jugable de npcs_generation.json roles (auditor, receptionist...).
func get_role(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_ROLES, id)


# ─── Acceso a inversores, deberes e ideas ─────────────────────

func get_investor(id: String) -> InvestorData:
	_ensure_loaded()
	return _investors.get(id) as InvestorData


func get_all_investors() -> Array[InvestorData]:
	_ensure_loaded()
	return _investor_list.duplicate()


## Extra: estrategia de investors.json strategies (pesos de fundamentales/sentimiento...).
func get_investor_strategy(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_STRATEGIES, id)


## Tipo de deber de duties.json duty_types (volume, quota, delivery, round, presentation).
func get_duty_definition(duty_type: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_DUTY_TYPES, duty_type)


## Extra: todas las definiciones de tipo de deber, en orden de archivo.
func get_all_duty_types() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_DUTY_TYPES)


## Extra: duties.json content (email_templates, call_scripts, report_fragments,
## round_waypoint_sets).
func get_duty_content() -> Dictionary:
	_ensure_loaded()
	return _copy_dict(_file("duties").get("content", {}))


## Extra: conjunto de paradas de una ronda (duties.json content.round_waypoint_sets).
func get_round_waypoint_set(id: String) -> Dictionary:
	_ensure_loaded()
	var content: Variant = _file("duties").get("content")
	var sets: Variant = (content as Dictionary).get("round_waypoint_sets") \
			if content is Dictionary else null
	return _copy_dict((sets as Dictionary).get(id) if sets is Dictionary else null)


## Plantilla de ideas del departamento; si no tiene propia, la plantilla "general".
func get_idea_template(department: String) -> Dictionary:
	_ensure_loaded()
	var template: Dictionary = _get_record(COL_IDEA_TEMPLATES, department)
	if template.is_empty():
		return _get_record(COL_IDEA_TEMPLATES, DEFAULT_IDEA_DEPARTMENT)
	return template


# ─── Acceso al balance mediante ruta con puntos ───────────────

## "percepcion.cono_angulo_base", "economia.estatus_por_escalon.5", "mercado.x.0" (índices de
## Array admitidos). Diccionarios y Arrays se devuelven copiados. Ruta inexistente → push_error
## y null (usar has_balance() para sondear sin error).
func get_balance(path: String) -> Variant:
	_ensure_loaded()
	if not _balance_flat.has(path):
		push_error(BALANCE_MISSING_FORMAT % path)
		return null
	return _copy_value(_balance_flat[path])


## Ruta inexistente o valor no entero → push_error; devuelve 0 (o el float truncado).
func get_balance_int(path: String) -> int:
	_ensure_loaded()
	if not _balance_flat.has(path):
		push_error(BALANCE_MISSING_FORMAT % path)
		return 0
	var value: Variant = _balance_flat[path]
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	push_error(BALANCE_TYPE_FORMAT % [path, "int", Validate.describe(value)])
	return int(value) if value is float else 0


## Ruta inexistente o valor no numérico → push_error; devuelve 0.0.
func get_balance_float(path: String) -> float:
	_ensure_loaded()
	if not _balance_flat.has(path):
		push_error(BALANCE_MISSING_FORMAT % path)
		return 0.0
	var value: Variant = _balance_flat[path]
	if value is float or value is int:
		return float(value)
	push_error(BALANCE_TYPE_FORMAT % [path, "float", Validate.describe(value)])
	return 0.0


## Extra: true si la ruta existe en balance.json (sin error).
func has_balance(path: String) -> bool:
	_ensure_loaded()
	return _balance_flat.has(path)


## balance.dificultad[<preset activo>][key]. Inexistente → push_error y 1.0 (neutro).
func get_difficulty_modifier(key: String) -> float:
	_ensure_loaded()
	var value: Variant = _balance_flat.get(MODIFIER_PATH_FORMAT % [_difficulty_preset, key])
	if value is float or value is int:
		return float(value)
	push_error(BALANCE_MISSING_FORMAT % (MODIFIER_PATH_FORMAT % [_difficulty_preset, key]))
	return NEUTRAL_MODIFIER


## Extra: activa un preset de balance.dificultad (interno, estandar, auditoria). Desconocido →
## push_error, false y se conserva el anterior. Tras load_all() el activo es presets_por_defecto.
func set_difficulty_preset(id: String) -> bool:
	_ensure_loaded()
	if not get_difficulty_presets().has(id):
		push_error(PRESET_UNKNOWN_FORMAT % id)
		return false
	_difficulty_preset = id
	return true


## Extra.
func get_difficulty_preset() -> String:
	_ensure_loaded()
	return _difficulty_preset


## Extra: ids de los presets de balance.dificultad, en orden de archivo.
func get_difficulty_presets() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	var section: Variant = _balance_flat.get(DIFFICULTY_SECTION)
	if section is Dictionary:
		for key: Variant in section:
			if not str(key).begins_with("_") and section[key] is Dictionary:
				out.append(str(key))
	return out


# ─── Acceso a objetos (§11.3) ─────────────────────────────────

## Extra: copia nueva del objeto del catálogo (null si no existe).
func get_item(id: String) -> ItemData:
	_ensure_loaded()
	var item: ItemData = _items.get(id) as ItemData
	return _copy_item(item) if item != null else null


## Extra: copias nuevas de todo el catálogo, en orden de archivo.
func get_all_items() -> Array[ItemData]:
	_ensure_loaded()
	var out: Array[ItemData] = []
	for item: ItemData in _item_list:
		out.append(_copy_item(item))
	return out


## Extra.
func has_item(id: String) -> bool:
	_ensure_loaded()
	return _items.has(id)


# ─── Acceso al resto de archivos (copias) ─────────────────────

## Extra: favor de bribes.json favours (multiplicador del precio justo).
func get_bribe_favour(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_FAVOURS, id)


## Extra.
func get_all_bribe_favours() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_FAVOURS)


## Extra: canal de bribes.json channels.
func get_bribe_channel(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_CHANNELS, id)


## Extra.
func get_all_bribe_channels() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_CHANNELS)


## Extra: tipo de vínculo de social_graph.json link_types.
func get_social_link_type(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_LINK_TYPES, id)


## Extra.
func get_all_social_link_types() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_LINK_TYPES)


## Extra: corrillo de social_graph.json gatherings ("room" puede ser null).
func get_gathering(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_GATHERINGS, id)


## Extra.
func get_all_gatherings() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_GATHERINGS)


## Extra: market.json completo sin comentarios de primer nivel (simulation, calendar...).
func get_market_params() -> Dictionary:
	_ensure_loaded()
	return _copy_dict(Validate.strip_comments(_file("market")))


## Extra: eventos de market_events.json, en orden de archivo.
func get_market_events() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_EVENTS)


## Extra: investigations.json completo sin comentarios de primer nivel.
func get_investigation_params() -> Dictionary:
	_ensure_loaded()
	return _copy_dict(Validate.strip_comments(_file("investigations")))


## Extra: final de endings.json endings. Reglas globales (axes, evaluation_order...): get_raw.
func get_ending(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_ENDINGS, id)


## Extra: finales en orden de archivo.
func get_all_endings() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_ENDINGS)


## Extra: banda artística de art_bands.json.
func get_art_band(id: String) -> Dictionary:
	_ensure_loaded()
	return _get_record(COL_BANDS, id)


## Extra.
func get_all_art_bands() -> Array[Dictionary]:
	_ensure_loaded()
	return _get_record_list(COL_BANDS)


## Extra: banda cuyo "floors" contiene la planta ({} si ninguna).
func get_art_band_for_floor(floor_number: int) -> Dictionary:
	_ensure_loaded()
	for band_id: String in _record_order.get(COL_BANDS, []):
		var floors: Variant = _records[COL_BANDS][band_id].get("floors", [])
		if floors is Array and _array_has_number(floors, floor_number):
			return _get_record(COL_BANDS, band_id)
	return {}


# ─── Construcción ─────────────────────────────────────────────

## Carga perezosa: una consulta anterior a load_all() la dispara (una sola vez por proceso), de
## modo que ningún sistema lee datos vacíos por orden de arranque.
func _ensure_loaded() -> void:
	if not _attempted:
		load_all()


func _build(raw: Dictionary, errors: Array[String], warnings: Array[String]) -> bool:
	var outer: Array[String] = Validate.take_errors()
	_clear_indexes()
	_raw = raw
	for file_id: String in _raw:
		_check_top_level(file_id)
	_index_balance()
	_parse_typed_files()
	_parse_records()
	_parse_items()
	_build_room_instances()
	var cross_check: DataCrossCheck = DataCrossCheck.new(self, _raw)
	cross_check.run()
	errors.append_array(Validate.take_errors())
	warnings.append_array(cross_check.warnings)
	Validate.errors.append_array(outer)
	_errors = errors
	_warnings = warnings
	_load_ok = _errors.is_empty()
	return _load_ok


func _clear_indexes() -> void:
	_raw = {}
	_balance_flat.clear()
	_occupations.clear()
	_occupation_list.clear()
	_rooms.clear()
	_room_list.clear()
	_room_instances.clear()
	_rooms_by_floor.clear()
	_archetypes.clear()
	_archetype_list.clear()
	_named_npcs.clear()
	_named_npc_list.clear()
	_investors.clear()
	_investor_list.clear()
	_items.clear()
	_item_list.clear()
	_records.clear()
	_record_order.clear()


func _read_all_files(errors: Array[String], warnings: Array[String]) -> Dictionary:
	var raw: Dictionary = {}
	for file_id: String in get_expected_file_ids():
		var path: String = DATA_DIR + file_id + JSON_EXTENSION
		if not FileAccess.file_exists(path):
			errors.append(FILE_ERROR_FORMAT % [_file_name(file_id), PROBLEM_FILE_MISSING,
					EXPECTED_JSON_FILE, Validate.RECEIVED_NOTHING])
			continue
		var parsed: Variant = _parse_json_file(path, file_id, errors)
		if parsed != null:
			raw[file_id] = parsed
	_note_unknown_room_files(warnings)
	return raw


func _parse_json_file(path: String, file_id: String, errors: Array[String]) -> Variant:
	var json: JSON = JSON.new()
	var result: Error = json.parse(FileAccess.get_file_as_string(path))
	if result != OK:
		var detail: String = JSON_ERROR_FORMAT % [json.get_error_line(), json.get_error_message()]
		errors.append(FILE_ERROR_FORMAT % [_file_name(file_id), PROBLEM_FILE_JSON,
				EXPECTED_VALID_JSON, detail])
		return null
	return json.data


func _note_unknown_room_files(warnings: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(DATA_DIR + ROOMS_PREFIX):
		if file.get_extension() == JSON_EXTENSION.trim_prefix(".") \
				and not ROOM_FILES.has(file.get_basename()):
			warnings.append(FILE_ERROR_FORMAT % [ROOMS_PREFIX + file, PROBLEM_FILE_UNKNOWN,
					str(ROOM_FILES), file])


func _check_top_level(file_id: String) -> void:
	var file_name: String = _file_name(file_id)
	if not (_raw[file_id] is Dictionary):
		Validate.report(file_name, WHOLE_FILE_KEY, Validate.PROBLEM_TYPE, "Dictionary",
				Validate.describe(_raw[file_id]))
		return
	var kind: String = ROOMS_KIND if file_id.begins_with(ROOMS_PREFIX) else file_id
	var spec: Dictionary = TOP_LEVEL_KEYS.get(kind, {})
	for key: String in spec:
		_require_typed(_raw[file_id], key, spec[key], file_name)


## Lee `key` de `d` con el validador del tipo indicado (errores a Validate.errors).
static func _require_typed(d: Dictionary, key: String, type_name: String, source: String) -> void:
	match type_name:
		"id":
			Validate.require_id(d, key, source)
		"String":
			Validate.require_string(d, key, source)
		"number":
			Validate.require_float(d, key, source)
		"bool":
			Validate.require_bool(d, key, source)
		"Array":
			Validate.require_array(d, key, source)
		"Dictionary":
			Validate.require_dict(d, key, source)


# ─── Balance ──────────────────────────────────────────────────

func _index_balance() -> void:
	var balance: Dictionary = _file("balance")
	_flatten_into("", balance)
	_check_difficulty(balance)
	var presets: Array[String] = get_difficulty_presets()
	if not presets.has(_difficulty_preset):
		var default_preset: String = str(balance.get(DEFAULT_PRESET_KEY, ""))
		_difficulty_preset = default_preset if presets.has(default_preset) else ""


func _flatten_into(prefix: String, value: Variant) -> void:
	if not prefix.is_empty():
		_balance_flat[prefix] = value
	var base: String = prefix + "." if not prefix.is_empty() else ""
	if value is Dictionary:
		for key: Variant in value:
			if not str(key).begins_with("_"):
				_flatten_into(base + str(key), value[key])
	elif value is Array:
		for i: int in (value as Array).size():
			_flatten_into(base + str(i), value[i])


## Cada preset es un diccionario de números con las mismas claves; el preset por defecto existe.
func _check_difficulty(balance: Dictionary) -> void:
	var section: Variant = balance.get(DIFFICULTY_SECTION)
	if not (section is Dictionary):
		return
	var reference: Array = []
	for preset: Variant in Validate.strip_comments(section):
		var source: String = "balance.json → %s.%s" % [DIFFICULTY_SECTION, preset]
		var values: Dictionary = Validate.as_dict(section[preset], WHOLE_ENTRY_KEY, {}, source)
		var keys: Array = Validate.strip_comments(values).keys()
		for key: Variant in keys:
			Validate.as_float(values[key], str(key), 0.0, source)
		keys.sort()
		if reference.is_empty():
			reference = keys
		elif keys != reference:
			Validate.report(source, WHOLE_ENTRY_KEY, PROBLEM_PRESET_KEYS, str(reference), str(keys))
	var default_preset: Variant = balance.get(DEFAULT_PRESET_KEY)
	if default_preset is String and not (section as Dictionary).has(default_preset):
		Validate.report("balance.json", DEFAULT_PRESET_KEY, Validate.PROBLEM_ENUM,
				"uno de %s" % str(Validate.strip_comments(section).keys()),
				Validate.describe(default_preset))


# ─── Registros tipados ────────────────────────────────────────

func _parse_typed_files() -> void:
	for item: Variant in _parse_collection("occupations", "occupations", OccupationData.from_dict):
		_occupation_list.append(item as OccupationData)
		_occupations[(item as OccupationData).id] = item
	for item: Variant in _parse_collection("archetypes", "archetypes", ArchetypeData.from_dict):
		_archetype_list.append(item as ArchetypeData)
		_archetypes[(item as ArchetypeData).id] = item
	for item: Variant in _parse_collection("npcs_named", "npcs", NPCData.from_dict):
		_named_npc_list.append(item as NPCData)
		_named_npcs[(item as NPCData).id] = item
	for item: Variant in _parse_collection("investors", "investors", InvestorData.from_dict):
		_investor_list.append(item as InvestorData)
		_investors[(item as InvestorData).id] = item
	var sources: Dictionary = {}
	for file_id: String in _raw:
		if file_id.begins_with(ROOMS_PREFIX):
			_parse_room_file(file_id, sources)


## Parsea la matriz principal de un archivo con `parser` (from_dict). Omite entradas no
## diccionario, sin id o con id repetido (informando del error).
func _parse_collection(file_id: String, array_key: String, parser: Callable) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var entries: Array = _entries(file_id, array_key)
	for i: int in entries.size():
		var source: String = Validate.entry(_file_name(file_id), i)
		if not (entries[i] is Dictionary):
			Validate.report(source, WHOLE_ENTRY_KEY, Validate.PROBLEM_TYPE, "Dictionary",
					Validate.describe(entries[i]))
			continue
		var record: Object = parser.call(entries[i], source)
		var id: String = str(record.get("id"))
		if id.is_empty():
			continue
		if seen.has(id):
			Validate.report(source, "id", PROBLEM_DUPLICATE, "id único en %s" % _file_name(file_id),
					Validate.describe(id))
			continue
		seen[id] = true
		out.append(record)
	return out


## Salas de un archivo de planta; `sources` (id → origen) detecta ids repetidos entre archivos.
func _parse_room_file(file_id: String, sources: Dictionary) -> void:
	var entries: Array = _entries(file_id, "rooms")
	for i: int in entries.size():
		var source: String = Validate.entry(_file_name(file_id), i)
		if not (entries[i] is Dictionary):
			Validate.report(source, WHOLE_ENTRY_KEY, Validate.PROBLEM_TYPE, "Dictionary",
					Validate.describe(entries[i]))
			continue
		var room: RoomData = RoomData.from_dict(entries[i], source)
		if room.id.is_empty():
			continue
		if sources.has(room.id):
			Validate.report(source, "id", PROBLEM_DUPLICATE, "id único (ya usado en %s)"
					% sources[room.id], Validate.describe(room.id))
			continue
		sources[room.id] = source
		_rooms[room.id] = room
		_room_list.append(room)


# ─── Registros sin clase (diccionarios validados) ─────────────

func _parse_records() -> void:
	for collection: String in RECORD_SPECS:
		var file_id: String = collection.get_slice(".", 0)
		var array_key: String = collection.get_slice(".", 1)
		var label: String = _file_name(file_id)
		if not MAIN_COLLECTIONS.has(collection):
			label = SUBARRAY_SOURCE_FORMAT % [label, array_key]
		_records[collection] = {}
		_record_order[collection] = []
		var entries: Array = _entries(file_id, array_key)
		for i: int in entries.size():
			_parse_record(collection, entries[i], Validate.entry(label, i))


func _parse_record(collection: String, entry: Variant, source: String) -> void:
	if not (entry is Dictionary):
		Validate.report(source, WHOLE_ENTRY_KEY, Validate.PROBLEM_TYPE, "Dictionary", Validate.describe(entry))
		return
	var spec: Dictionary = RECORD_SPECS[collection]
	var id_field: String = str(spec.keys()[0])
	var before: int = Validate.errors.size()
	for key: String in spec:
		_require_typed(entry, key, spec[key], source)
	var id: String = str(entry.get(id_field, ""))
	if Validate.errors.size() > before and not Validate.is_valid_id(id):
		return
	if _records[collection].has(id):
		Validate.report(source, id_field, PROBLEM_DUPLICATE, "id único", Validate.describe(id))
		return
	_records[collection][id] = Validate.strip_comments(entry).duplicate(true)
	(_record_order[collection] as Array).append(id)


## Catálogo de objetos: balance.json → objetos {id: {id, name_key, category, value, ...}}.
func _parse_items() -> void:
	var section: Variant = _file("balance").get(ITEMS_SECTION)
	if not (section is Dictionary):
		return
	for key: Variant in Validate.strip_comments(section):
		var source: String = ITEM_SOURCE_FORMAT % key
		var entry: Variant = section[key]
		if not (entry is Dictionary):
			Validate.report(source, WHOLE_ENTRY_KEY, Validate.PROBLEM_TYPE, "Dictionary",
					Validate.describe(entry))
			continue
		var item: ItemData = ItemData.from_dict(entry, source)
		if item.id != str(key):
			Validate.report(source, "id", PROBLEM_KEY_MISMATCH, "\"%s\"" % key,
					Validate.describe(item.id))
			continue
		_items[item.id] = item
		_item_list.append(item)


# ─── Salas transversales: copias por planta ───────────────────

func _build_room_instances() -> void:
	for room: RoomData in _room_list:
		_index_floor(room.floor, room)
		if not room.is_transversal():
			continue
		for floor_number: int in _transversal_floors(room):
			var instance: RoomData = _make_room_instance(room, floor_number)
			_room_instances[instance.id] = instance
			_index_floor(floor_number, instance)


func _index_floor(floor_number: int, room: RoomData) -> void:
	if not _rooms_by_floor.has(floor_number):
		_rooms_by_floor[floor_number] = []
	(_rooms_by_floor[floor_number] as Array).append(room)


## Intervalo floors [min, max] más las plantas sueltas de extra_floors (montacargas → fábrica).
func _transversal_floors(room: RoomData) -> Array[int]:
	var out: Array[int] = []
	for floor_number: int in range(room.floors[0], room.floors[1] + 1):
		out.append(floor_number)
	var extra_floors: Variant = room.extra.get(EXTRA_FLOORS_KEY, [])
	var source: String = "rooms/transversal.json → %s" % room.id
	for value: Variant in Validate.as_array(extra_floors, EXTRA_FLOORS_KEY, [], source):
		var floor_number: int = Validate.as_int(value, EXTRA_FLOORS_KEY, room.floors[0], source)
		if not out.has(floor_number):
			out.append(floor_number)
	return out


func _make_room_instance(base: RoomData, floor_number: int) -> RoomData:
	var suffix: String = INSTANCE_SUFFIX_FORMAT % floor_number
	var d: Dictionary = base.to_dict()
	d["id"] = base.id + suffix
	d["floor"] = floor_number
	d[EXTRA_BASE_ID] = base.id
	d[EXTRA_INSTANCE_FLOOR] = floor_number
	for list_key: String in INSTANCE_ID_LISTS:
		for entry: Variant in d.get(list_key, []):
			if entry is Dictionary and entry.has("id"):
				entry[EXTRA_BASE_ID] = entry["id"]
				entry["id"] = str(entry["id"]) + suffix
	return RoomData.from_dict(d, INSTANCE_SOURCE_FORMAT % [base.id, floor_number])


# ─── Auxiliares ───────────────────────────────────────────────

static func _file_name(file_id: String) -> String:
	return file_id + JSON_EXTENSION


## Diccionario del archivo (o {} si falta o no es diccionario). Uso interno: sin copia.
func _file(file_id: String) -> Dictionary:
	var value: Variant = _raw.get(file_id)
	return value if value is Dictionary else {}


func _entries(file_id: String, array_key: String) -> Array:
	var value: Variant = _file(file_id).get(array_key)
	return value if value is Array else []


func _get_record(collection: String, id: String) -> Dictionary:
	var records: Dictionary = _records.get(collection, {})
	return _copy_dict(records.get(id, {}))


func _get_record_list(collection: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _record_order.get(collection, []):
		out.append(_get_record(collection, id))
	return out


static func _copy_dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


static func _copy_item(item: ItemData) -> ItemData:
	var out: ItemData = ItemData.make(item.id, item.name_key, item.category)
	out.value = item.value
	out.stack = item.stack
	out.extra = item.extra.duplicate(true)
	return out


static func _array_has_number(values: Array, number: int) -> bool:
	for value: Variant in values:
		if (value is int or value is float) and int(value) == number:
			return true
	return false
