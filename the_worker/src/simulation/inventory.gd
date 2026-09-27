# inventory.gd — Reglas puras de inventario y contrabando: objetos, escondites y registro corporal.
# PROPIETARIO DE: nada (biblioteca estática; el inventario y los alijos pertenecen a PlayerState).
# ESCUCHA: nada.
class_name InventoryRules
extends RefCounted

## Manual §11.3, §12.3, §12.4, PASO 37; BUILD_NOTES §12, §13.
## · Objetos: catálogo balance.objetos vía Database.get_item(id). Si el id no está catalogado se
##   aplica la regla de respaldo: ordinario si empieza por inventario.prefijos_ordinarios, si no
##   inventario.categoria_por_defecto ("compromising": lo que no es tuyo, compromete).
##   extra.kind "post_tool" = herramienta del puesto: no ocupa inventario. extra.kind "cash" ordinario
##   = efectivo de bolsillo: PlayerState lo suma al capital. extra.stackable = comparte posición.
## · Ubicaciones de ocultación (§11.3): desk, locker, dead_archive, vents, cleaning_closet,
##   trash_dock (absoluta e irreversible: el objeto sale del juego) + forgotten_corridor (§22.1,
##   ninguna investigación lo registra), home (domicilio) y other (escondite improvisado).
##   La ubicación sale de la sala (dead_archive, trash_dock, cleaning_closet_*, ...) o, si la sala no
##   la fija, del tipo de escondite de los datos de sala (under_desk → desk, locker, vent → vents...).
##   Parámetros por ubicación en balance inventario.escondites.<ubicación>.
## · Registro corporal: resolve_body_search() aplica §12.4 — un objeto comprometedor es evidencia
##   de peso investigaciones.pesos_evidencia.objeto_comprometedor (10) y el caso se cierra contra el
##   jugador; el grado sale de los umbrales de condena modulados por la sospecha
##   (umbral + mod_umbral_por_sospecha × sospecha): "conviction_major" si el peso supera el umbral
##   grave, "conviction_minor" si alcanza el leve, "clean" sin objetos comprometedores
##   ("evidence_noted" = peso positivo por debajo del umbral leve; solo vía classify_evidence).

const LOC_DESK := "desk"
const LOC_LOCKER := "locker"
const LOC_DEAD_ARCHIVE := "dead_archive"
const LOC_VENTS := "vents"
const LOC_CLEANING_CLOSET := "cleaning_closet"
const LOC_TRASH_DOCK := "trash_dock"
const LOC_FORGOTTEN_CORRIDOR := "forgotten_corridor"
const LOC_HOME := "home"
const LOC_OTHER := "other"
const LOCATIONS: Array[String] = [
	LOC_DESK, LOC_LOCKER, LOC_DEAD_ARCHIVE, LOC_VENTS, LOC_CLEANING_CLOSET, LOC_TRASH_DOCK,
	LOC_FORGOTTEN_CORRIDOR, LOC_HOME, LOC_OTHER,
]
## Tipo de escondite de los datos de sala (§27 hiding_spots / interactables) → ubicación.
## "curtain" no figura: solo oculta al jugador, no admite objetos.
const SPOT_TYPE_LOCATION: Dictionary = {
	"under_desk": LOC_DESK, "locker": LOC_LOCKER, "vent": LOC_VENTS, "trash_chute": LOC_TRASH_DOCK,
	"supply_closet": LOC_OTHER, "archive_shelves": LOC_OTHER, "crate": LOC_OTHER,
	"car_trunk": LOC_OTHER, "dumpster": LOC_OTHER, "toilet_stall": LOC_OTHER,
}
## Sala (id base, sin sufijo @planta) → ubicación; prevalece sobre el tipo de escondite.
const ROOM_LOCATION: Dictionary = {
	"dead_archive": LOC_DEAD_ARCHIVE, "trash_dock": LOC_TRASH_DOCK, "vent_network": LOC_VENTS,
	"forgotten_corridor": LOC_FORGOTTEN_CORRIDOR, "player_flat": LOC_HOME,
}
## Prefijo de sala → ubicación (los cuatro cuartos de limpieza transversales).
const ROOM_PREFIX_LOCATION: Dictionary = {"cleaning_closet": LOC_CLEANING_CLOSET}
const ROOM_INSTANCE_SEPARATOR := "@"

const KIND_POST_TOOL := "post_tool"
const KIND_CASH := "cash"
const EXTRA_KIND := "kind"
const EXTRA_STACKABLE := "stackable"
const FALLBACK_NAME_KEY_FORMAT := "ITEM_%s"
const UNKNOWN_ITEM_WARNING := "InventoryRules: objeto '%s' ausente del catálogo balance.objetos; se aplica la regla de respaldo (%s)."

const OUTCOME_CLEAN := "clean"
const OUTCOME_EVIDENCE_NOTED := "evidence_noted"
const OUTCOME_CONVICTION_MINOR := "conviction_minor"
const OUTCOME_CONVICTION_MAJOR := "conviction_major"
const OUTCOME_KEY_FORMAT := "SEARCH_OUTCOME_%s"
const LOCATION_NAME_KEY_FORMAT := "HIDE_LOC_%s"
const LOCATION_RISK_KEY_FORMAT := "HIDE_LOC_%s_RISK"
const SECURITY_KEY_FORMAT := "HIDE_SECURITY_%s"

const P_DEFAULT_CATEGORY := "inventario.categoria_por_defecto"
const P_ORDINARY_PREFIXES := "inventario.prefijos_ordinarios"
const P_BULKY_ITEMS := "inventario.objetos_voluminosos"
const P_LOCATION_FORMAT := "inventario.escondites.%s.%s"
const P_WEIGHT_ITEM := "investigaciones.pesos_evidencia.objeto_comprometedor"
const P_MINOR_THRESHOLD := "investigaciones.umbral_condena_leve"
const P_MAJOR_THRESHOLD := "investigaciones.umbral_condena_grave"
const P_THRESHOLD_MOD := "investigaciones.mod_umbral_por_sospecha"

const F_SECURITY := "seguridad"
const F_LEVEL := "nivel"
const F_SEARCHABLE := "registrable"
const F_MIN_SEVERITY := "gravedad_minima_registro"
const F_BASEMENT_ONLY := "solo_si_registra_sotanos"
const F_SEARCH_ORDER := "orden_registro"
const F_RETRIEVAL := "minutos_recuperacion"
const F_DAILY_CHANCE := "prob_hallazgo_diaria"
const F_ACCEPTS_BULKY := "admite_voluminosos"
const F_IRREVERSIBLE := "irreversible"

const SPOT_TYPE := "type"
const SPOT_CAPACITY := "capacity"
const SPOT_LOCATION := "location"
const SPOT_ID := "id"


# ─── Objetos ───────────────────────────────────────────────────

## ItemData nuevo (copia) para `item_id`: catálogo de Database o regla de respaldo.
static func make_item(item_id: String) -> ItemData:
	var item: ItemData = Database.get_item(item_id)
	if item != null:
		return item
	var category: String = fallback_category(item_id)
	push_warning(UNKNOWN_ITEM_WARNING % [item_id, category])
	return ItemData.make(item_id, FALLBACK_NAME_KEY_FORMAT % item_id.to_upper(), category)


## Regla de respaldo para ids sin catálogo (inventario.prefijos_ordinarios / categoria_por_defecto).
static func fallback_category(item_id: String) -> String:
	for prefix: Variant in _balance_array(P_ORDINARY_PREFIXES):
		if item_id.begins_with(str(prefix)):
			return ItemData.CATEGORY_ORDINARY
	var category: String = str(Database.get_balance(P_DEFAULT_CATEGORY))
	return category if ItemData.CATEGORIES.has(category) else ItemData.CATEGORY_COMPROMISING


static func is_compromising(item_id: String) -> bool:
	return make_item(item_id).is_compromising()


static func get_kind(item: ItemData) -> String:
	return str(item.extra.get(EXTRA_KIND, ""))


## false para herramientas de puesto (post_tool): las concede la silla, no ocupan posición.
static func occupies_slot(item: ItemData) -> bool:
	return get_kind(item) != KIND_POST_TOOL


static func is_stackable(item: ItemData) -> bool:
	var value: Variant = item.extra.get(EXTRA_STACKABLE, false)
	return value is bool and value


## Efectivo ordinario: al recogerlo se convierte en capital (item.value €) y no ocupa posición.
static func is_pocket_cash(item: ItemData) -> bool:
	return get_kind(item) == KIND_CASH and not item.is_compromising()


static func is_bulky(item: ItemData) -> bool:
	return _balance_array(P_BULKY_ITEMS).has(item.id)


# ─── Ubicaciones de ocultación ─────────────────────────────────

## Ubicación (§11.3) de un escondite. `spot_type` puede ser un tipo de los datos de sala o ya una
## ubicación. "" si el escondite no admite objetos.
static func spot_location(spot_type: String, room_id: String) -> String:
	if LOCATIONS.has(spot_type):
		return spot_type
	var base_room: String = room_id.get_slice(ROOM_INSTANCE_SEPARATOR, 0)
	if ROOM_LOCATION.has(base_room) and SPOT_TYPE_LOCATION.has(spot_type):
		return ROOM_LOCATION[base_room]
	for prefix: String in ROOM_PREFIX_LOCATION:
		if base_room.begins_with(prefix) and SPOT_TYPE_LOCATION.has(spot_type):
			return ROOM_PREFIX_LOCATION[prefix]
	return str(SPOT_TYPE_LOCATION.get(spot_type, ""))


## Busca `spot_id` en hiding_spots e interactables de la sala (admite ids "sala@planta").
## Devuelve {id, type, capacity, location} o {} si no existe o no admite objetos.
static func find_spot(room_id: String, spot_id: String) -> Dictionary:
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return {}
	var candidates: Array[Dictionary] = []
	candidates.append_array(room.hiding_spots)
	candidates.append_array(room.interactables)
	for spot: Dictionary in candidates:
		if str(spot.get(SPOT_ID, "")) != spot_id:
			continue
		var spot_type: String = str(spot.get(SPOT_TYPE, ""))
		var location: String = spot_location(spot_type, room_id)
		if location.is_empty():
			return {}
		return {
			SPOT_ID: spot_id, SPOT_TYPE: spot_type, SPOT_LOCATION: location,
			SPOT_CAPACITY: int(spot.get(SPOT_CAPACITY, 0)),
		}
	return {}


## ¿Se puede ocultar `item_id` en un escondite de este tipo (o ubicación)? No admiten objetos las
## cortinas, las herramientas de puesto ni el efectivo de bolsillo; los objetos voluminosos
## (inventario.objetos_voluminosos) no caben donde admite_voluminosos = false (escritorio, conductos).
static func can_hide_in(spot_type: String, item_id: String) -> bool:
	var location: String = spot_location(spot_type, "")
	if location.is_empty():
		return false
	var item: ItemData = make_item(item_id)
	if not occupies_slot(item) or is_pocket_cash(item):
		return false
	return accepts_bulky(location) or not is_bulky(item)


static func get_location_security(location: String) -> float:
	return _location_float(location, F_SECURITY)


## "very_low" | "medium" | "high" | "very_high" | "absolute"
static func get_location_security_level(location: String) -> String:
	var value: Variant = _location_value(location, F_LEVEL)
	return str(value) if value is String else ""


static func is_irreversible(location: String) -> bool:
	return _location_bool(location, F_IRREVERSIBLE)


static func accepts_bulky(location: String) -> bool:
	return _location_bool(location, F_ACCEPTS_BULKY)


## Minutos de juego que cuesta recuperar un objeto (conductos: lento e incómodo).
static func retrieval_minutes(location: String) -> int:
	return _location_int(location, F_RETRIEVAL)


## Orden en que el registro físico (fase 2) visita la ubicación; 0 = nunca.
static func search_order(location: String) -> int:
	return _location_int(location, F_SEARCH_ORDER)


## Probabilidad diaria de hallazgo casual (cuartos de limpieza: Connie Marks). La tira quien
## gestione el hallazgo, con su propio RandomNumberGenerator sembrado desde la semilla de partida.
static func daily_discovery_chance(location: String) -> float:
	return _location_float(location, F_DAILY_CHANCE)


## ¿El registro físico de la fase 2 (§12.3) de una investigación de gravedad `severity` (1-5)
## encuentra lo oculto en `location`? El archivo muerto solo aflora si la investigación registra
## sótanos (investigations.json severity_levels[].searches_basements).
static func search_finds_stash(location: String, severity: int, searches_basements: bool) -> bool:
	if not _location_bool(location, F_SEARCHABLE):
		return false
	if _location_bool(location, F_BASEMENT_ONLY) and not searches_basements:
		return false
	return severity >= _location_int(location, F_MIN_SEVERITY)


static func get_location_name_key(location: String) -> String:
	return LOCATION_NAME_KEY_FORMAT % location.to_upper()


static func get_location_risk_key(location: String) -> String:
	return LOCATION_RISK_KEY_FORMAT % location.to_upper()


static func get_security_level_key(location: String) -> String:
	return SECURITY_KEY_FORMAT % get_location_security_level(location).to_upper()


# ─── Registro corporal ─────────────────────────────────────────

## `player_items`: ItemData y/o ids (String), p. ej. PlayerState.get_inventory(). Las unidades
## apiladas cuentan (item.stack). Devuelve {found_hot_items: int, hot_item_ids: Array[String],
## evidence_weight: float, outcome: String, suspicion: float}.
static func resolve_body_search(player_items: Array, suspicion: float) -> Dictionary:
	var hot_ids: Array[String] = []
	for entry: Variant in player_items:
		var item: ItemData = _as_item(entry)
		if item == null or not item.is_compromising():
			continue
		for _unit: int in maxi(item.stack, 1):
			hot_ids.append(item.id)
	var weight: float = 0.0
	if not hot_ids.is_empty():
		weight = Database.get_balance_float(P_WEIGHT_ITEM)
	return {
		"found_hot_items": hot_ids.size(), "hot_item_ids": hot_ids,
		"evidence_weight": weight, "outcome": classify_evidence(weight, suspicion),
		"suspicion": suspicion,
	}


## Grado de la evidencia según §12.3 fase 5 con la modulación de §12.4:
## "clean" (peso 0) | "evidence_noted" | "conviction_minor" | "conviction_major".
static func classify_evidence(weight: float, suspicion: float) -> String:
	if weight <= 0.0:
		return OUTCOME_CLEAN
	var shift: float = Database.get_balance_float(P_THRESHOLD_MOD) * suspicion
	if weight > Database.get_balance_float(P_MAJOR_THRESHOLD) + shift:
		return OUTCOME_CONVICTION_MAJOR
	if weight >= Database.get_balance_float(P_MINOR_THRESHOLD) + shift:
		return OUTCOME_CONVICTION_MINOR
	return OUTCOME_EVIDENCE_NOTED


static func get_outcome_key(outcome: String) -> String:
	return OUTCOME_KEY_FORMAT % outcome.to_upper()


# ─── Interno ───────────────────────────────────────────────────

static func _as_item(entry: Variant) -> ItemData:
	if entry is ItemData:
		return entry as ItemData
	if entry is String or entry is StringName:
		return make_item(str(entry))
	return null


static func _location_value(location: String, field: String) -> Variant:
	var path: String = P_LOCATION_FORMAT % [location, field]
	if not LOCATIONS.has(location) or not Database.has_balance(path):
		return null
	return Database.get_balance(path)


static func _location_bool(location: String, field: String) -> bool:
	var value: Variant = _location_value(location, field)
	return value is bool and value


static func _location_float(location: String, field: String) -> float:
	var value: Variant = _location_value(location, field)
	return float(value) if value is float or value is int else 0.0


static func _location_int(location: String, field: String) -> int:
	var value: Variant = _location_value(location, field)
	return int(value) if value is float or value is int else 0


static func _balance_array(path: String) -> Array:
	var value: Variant = Database.get_balance(path)
	return value as Array if value is Array else []
