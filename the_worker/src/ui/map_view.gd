# map_view.gd — Mapa (Tab): corte vertical de toda la torre como plano de evacuación y zoom a planta (§13.6, PASO 36).
# PROPIETARIO DE: el estado de la ventana del mapa (capas, franja de ocupación, planta señalada y ampliada), la memoria de capas entre aperturas y las cachés estáticas de planos y cornisas.
# ESCUCHA: clearance_changed, occupation_changed, disguise_changed, inventory_changed, floor_changed, room_entered (solo para refrescarse mientras está abierto).
class_name MapView
extends Control

## UIRoot.open_map(context) instancia este script, llama setup(context) y lo abre como modal que
## pausa el reloj; close_requested lo cierra; Esc llama request_close() (desde el zoom vuelve al corte).
## context (todo opcional): floor (abre ampliada esa planta), layers {cameras, routes, occupancy},
## band (franja de la capa de ocupación), targets (ids marcados), file_levels {npc_id: nivel},
## access (contexto de acceso ya construido, p. ej. para QA; ver make_access_context).
##
## DECISIONES
##  · Acceso por sala (verde/ámbar/rojo) = room_access(): VERDE si la regla de puertas de
##    FloorStreamer se cumple (nivel ≥ clearance_required; con special_access, modo "and"/"or"),
##    si es el despacho de la ocupación o si una etiqueta de la ocupación la concede
##    (balance mapa.acceso_por_etiqueta). ÁMBAR si hay un método alternativo AHORA (primero que
##    aplique): uniforme (disfraz puesto o llevado: etiquetas de rol de mapa.uniformes), llaves
##    maestras (≤ mapa.llaves_maestras_nivel_max), tarjeta ajena (nivel de extra.clearance o
##    mapa.tarjetas), llaves antiguas (entrada old_keys), herramienta de forzar (forced_lock),
##    conducto (trampilla hacia una sala verde, o red de conductos utilizable), cornisa (desde una
##    sala verde con salida a cornisa). ROJO en otro caso.
##  · Acceso por planta = el mejor estado entre sus salas propias (sin pasillos, ascensores ni
##    escaleras, que son de nivel 1 en todas las plantas): «tengo algo que hacer ahí». Los cuartos
##    de servicio compartidos (copias transversales: limpieza) solo dan un punto de apoyo → como
##    mucho ámbar (acceso parcial).
##  · Puntos: personajes vivos que el jugador conoce (nominados, marcados o NPCDirector.knows_player)
##    con rutina desbloqueada (nivel de expediente ≥ mapa.nivel_expediente_rutina) → sala actual.
##    Un objetivo marcado sin rutina desbloqueada se muestra aproximado en su puesto (dato N1).
##  · Objetivos y niveles de expediente por personaje: context, o el primer autoload que exponga
##    get_marked_targets() / get_file_level(npc_id) (PlayerState o NPCDirector).
##  · Las capas elegidas se recuerdan entre aperturas (static, solo en esta ejecución).

signal close_requested
signal floor_zoomed(floor_number: int)
signal layer_toggled(layer: String, on: bool)

const ACCESS_ALLOWED := MapFloorPlan.ACCESS_ALLOWED
const ACCESS_ALTERNATIVE := MapFloorPlan.ACCESS_ALTERNATIVE
const ACCESS_FORBIDDEN := MapFloorPlan.ACCESS_FORBIDDEN
const LAYER_CAMERAS := MapFloorPlan.LAYER_CAMERAS
const LAYER_ROUTES := MapFloorPlan.LAYER_ROUTES
const LAYER_OCCUPANCY := MapFloorPlan.LAYER_OCCUPANCY
const LAYERS: Array[String] = [LAYER_CAMERAS, LAYER_ROUTES, LAYER_OCCUPANCY]
const LAYER_KEYS: Dictionary = {
	LAYER_CAMERAS: "MAP_LAYER_CAMERAS", LAYER_ROUTES: "MAP_LAYER_ROUTES", LAYER_OCCUPANCY: "MAP_LAYER_OCCUPANCY",
}
const LAYER_ICONS: Dictionary = {LAYER_CAMERAS: "camera", LAYER_ROUTES: "vent", LAYER_OCCUPANCY: "people"}
const LAYER_HOTKEYS: Dictionary = {KEY_1: LAYER_CAMERAS, KEY_2: LAYER_ROUTES, KEY_3: LAYER_OCCUPANCY}
const NO_FLOOR := -1000

const CTX_CLEARANCE := "clearance"
const CTX_TAGS := "tags"
const CTX_OFFICE := "office_room"
const CTX_DISGUISE := "disguise"
const CTX_ITEMS := "items"
const CTX_CARD_LEVELS := "card_levels"
const CONTEXT_FLOOR := "floor"
const CONTEXT_LAYERS := "layers"
const CONTEXT_BAND := "band"
const CONTEXT_TARGETS := "targets"
const CONTEXT_FILE_LEVELS := "file_levels"
const CONTEXT_ACCESS := "access"

const METHOD_UNIFORM := "uniform"
const METHOD_MASTER_KEYS := "master_keys"
const METHOD_CARD := "card"
const METHOD_OLD_KEYS := "old_keys"
const METHOD_FORCED_LOCK := "forced_lock"
const METHOD_VENT := "vent"
const METHOD_ROOF_LEDGE := "roof_ledge"
const ALT_ORDER: Array[String] = [
	METHOD_UNIFORM, METHOD_MASTER_KEYS, METHOD_CARD, METHOD_OLD_KEYS, METHOD_FORCED_LOCK, METHOD_VENT,
	METHOD_ROOF_LEDGE,
]
const METHOD_KEYS: Dictionary = {
	METHOD_UNIFORM: "MAP_METHOD_UNIFORM", METHOD_MASTER_KEYS: "MAP_METHOD_MASTER_KEYS",
	METHOD_CARD: "MAP_METHOD_CARD", METHOD_OLD_KEYS: "MAP_METHOD_OLD_KEYS",
	METHOD_FORCED_LOCK: "MAP_METHOD_FORCED_LOCK", METHOD_VENT: "MAP_METHOD_VENT",
	METHOD_ROOF_LEDGE: "MAP_METHOD_ROOF_LEDGE",
}
const ENTRY_OLD_KEYS := "old_keys"
const ENTRY_FORCED_LOCK := "forced_lock"
const ENTRY_VENT := "vent"
const ENTRY_ROOF_LEDGE := "roof_ledge"
const VENT_HATCH_TYPE := "vent_hatch"
const LEDGE_TYPE := "roof_ledge"
const LEADS_TO := "leads_to"
const VENT_NETWORK_ID := "vent_network"
const MODE_AND := "and"
const MODE_OR := "or"
const KEY_MODE := "special_access_mode"
const KEY_BASE_ID := "base_id"
const RULE_FLOORS := "floors"
const RULE_ROOMS := "rooms"
const RULE_MAX_ROOM := "max_room_clearance"
const EXTRA_CLEARANCE := "clearance"
const UNIFORM_PREFIX := "uniform_"
const TARGETS_GETTER := "get_marked_targets"
const FILE_LEVEL_GETTER := "get_file_level"

const B_ROUTINE_LEVEL := "mapa.nivel_expediente_rutina"
const B_UNIFORMS := "mapa.uniformes"
const B_MASTER_KEYS := "mapa.llaves_maestras"
const B_MASTER_MAX := "mapa.llaves_maestras_nivel_max"
const B_CARDS := "mapa.tarjetas"
const B_OLD_KEYS := "mapa.llaves_antiguas"
const B_FORCE_TOOLS := "mapa.herramientas_forzar"
const B_VENT_KEYS := "mapa.llaves_conductos"
const B_TAG_RULES := "mapa.acceso_por_etiqueta"
const B_FACTORY := "mundo.planta_fabrica"
const B_EXTERIOR := "mundo.planta_exterior"
const B_ROOF := "mundo.planta_azotea"

## Maquetación del cartel (fracciones del tamaño base de letra o de la ventana; diseño, no balance).
const MARGIN_RATIO := 0.018
const FRAME_RATIO := 0.42
const HEADER_RATIO := 3.3
const FOOTER_RATIO := 1.45
const PAD_RATIO := 0.7
const SIDE_SHARE := 0.3
const SIDE_MIN_RATIO := 13.0
const SIDE_MAX_SHARE := 0.4
const MAX_ROOM_ROWS := 16

static var _layer_memory: Dictionary = {}
static var _plan_cache: Dictionary = {}
static var _ledge_sources: Dictionary = {}
static var _ledges_indexed: bool = false

var _context: Dictionary = {}
var _layers: Dictionary = {}
var _band: String = ""
var _zoom_floor: int = NO_FLOOR
var _selected_floor: int = NO_FLOOR
var _selected_room: String = ""
var _model: Dictionary = {}
var _rects: Dictionary = {}
var _cut: CutCanvas
var _plan_view: MapFloorPlan
var _title: Label
var _subtitle: Label
var _footer_left: Label
var _footer_right: Label
var _side_scroll: ScrollContainer
var _side: VBoxContainer
var _sized: Dictionary = {}
var _badge: Label
var _occ_label: Label
var _disguise_label: Label
var _files_label: Label
var _toggles: Dictionary = {}
var _band_row: HBoxContainer
var _band_label: Label
var _floor_title: Label
var _floor_band: Label
var _floor_status: Swatch
var _floor_status_label: Label
var _floor_people: Label
var _room_list: VBoxContainer
var _hint: Label
var _nav_row: HBoxContainer
var _listed: Array[String] = []
var _connected: bool = false


func _init() -> void:
	name = "MapView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_layers = {LAYER_CAMERAS: false, LAYER_ROUTES: false, LAYER_OCCUPANCY: false}
	_layers.merge(_layer_memory, true)
	_build()


func _ready() -> void:
	_connect_bus(true)
	if _band.is_empty():
		_band = GameClock.get_current_band()
	refresh()
	_apply_sizes()
	_layout()


func _exit_tree() -> void:
	_connect_bus(false)


# ─── API pública ───────────────────────────────────────────────────

## Contexto de apertura (ver cabecera). Puede llamarse antes o después de entrar en el árbol.
func setup(context: Dictionary) -> void:
	_context = context.duplicate(true)
	var layers: Variant = _context.get(CONTEXT_LAYERS, {})
	if layers is Dictionary:
		for layer: Variant in layers:
			if LAYERS.has(str(layer)):
				_layers[str(layer)] = bool(layers[layer])
	_band = str(_context.get(CONTEXT_BAND, _band))
	if is_inside_tree():
		refresh()
	if _context.has(CONTEXT_FLOOR):
		zoom_to_floor(int(_context[CONTEXT_FLOOR]))


## Esc: desde el zoom vuelve al corte; desde el corte pide el cierre.
func request_close() -> void:
	if is_zoomed():
		zoom_out()
	else:
		close_requested.emit()


func set_layer(layer: String, on: bool) -> void:
	if not LAYERS.has(layer) or bool(_layers.get(layer, false)) == on:
		return
	_layers[layer] = on
	_layer_memory[layer] = on
	layer_toggled.emit(layer, on)
	_sync_toggles()
	_push_model()


func toggle_layer(layer: String) -> void:
	set_layer(layer, not is_layer_on(layer))


func is_layer_on(layer: String) -> bool:
	return bool(_layers.get(layer, false))


func get_layers() -> Dictionary:
	return _layers.duplicate()


## Franja de la capa de ocupación ("arrival", "work_morning", "lunch"...).
func set_band(band: String) -> void:
	if not GameClock.get_band_order().has(band):
		return
	_band = band
	_refresh_band_label()
	_push_model()


func get_band() -> String:
	return _band


func zoom_to_floor(floor_number: int) -> void:
	if not get_cut_floors().has(floor_number):
		return
	_zoom_floor = floor_number
	_selected_floor = floor_number
	_selected_room = ""
	_cut.visible = false
	_plan_view.visible = true
	_plan_view.show_floor(floor_number, _plan_model(floor_number))
	_refresh_texts()
	floor_zoomed.emit(floor_number)


func zoom_out() -> void:
	if not is_zoomed():
		return
	_zoom_floor = NO_FLOOR
	_selected_room = ""
	_plan_view.visible = false
	_cut.visible = true
	_cut.queue_redraw()
	_refresh_texts()
	floor_zoomed.emit(NO_FLOOR)


func is_zoomed() -> bool:
	return _zoom_floor != NO_FLOOR


func get_zoomed_floor() -> int:
	return _zoom_floor


## Planta señalada en el corte (panel lateral). NO_FLOOR = ninguna.
func select_floor(floor_number: int) -> void:
	if floor_number != NO_FLOOR and not get_cut_floors().has(floor_number):
		return
	_selected_floor = floor_number
	_cut.hover_floor = floor_number
	_cut.queue_redraw()
	_refresh_floor_panel()


func get_selected_floor() -> int:
	return _selected_floor


## Plantas del corte: S3..azotea y la nave (sin el exterior), de abajo arriba.
func get_cut_floors() -> Array[int]:
	var out: Array[int] = []
	var exterior: int = Database.get_balance_int(B_EXTERIOR)
	for f: int in Database.get_floor_ids():
		if f != exterior:
			out.append(f)
	return out


func get_floor_status(floor_number: int) -> int:
	return int((_model.get("floor_status", {}) as Dictionary).get(floor_number, ACCESS_FORBIDDEN))


func get_room_status(room_id: String) -> int:
	return int((_model.get("statuses", {}) as Dictionary).get(room_id, ACCESS_FORBIDDEN))


func get_room_method(room_id: String) -> String:
	return str((_model.get("methods", {}) as Dictionary).get(room_id, ""))


## Salas dibujadas como bloque en el corte para una planta (orden izquierda → derecha).
func get_cut_room_ids(floor_number: int) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in (_model.get("blocks", {}) as Dictionary).get(floor_number, []):
		out.append(str(id))
	return out


## Rectángulo local del corte para una planta (Rect2() si no se dibuja).
func get_cut_floor_rect(floor_number: int) -> Rect2:
	return _cut.floor_rect(floor_number)


func get_visible_dots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dot: Dictionary in _model.get("dots", []):
		out.append(dot.duplicate())
	return out


## Salas listadas en el panel lateral (planta ampliada o señalada).
func get_panel_room_ids() -> Array[String]:
	return _listed.duplicate()


func get_floor_plan_view() -> MapFloorPlan:
	return _plan_view


func get_player_floor() -> int:
	return int(_model.get("player_floor", NO_FLOOR))


func get_player_room() -> String:
	return str(_model.get("player_room", ""))


## Tamaño base de letra vigente (tema de UIRoot; escala todo el cartel).
func base_font() -> int:
	return _base()


func get_access_context() -> Dictionary:
	return (_model.get("ctx", {}) as Dictionary).duplicate(true)


## Recalcula acceso, puntos y paneles (lo llaman los cambios de acreditación, disfraz, etc.).
func refresh() -> void:
	_rebuild_model()
	_refresh_texts()
	_sync_toggles()
	_push_model()


# ─── Modelo de acceso (estático, puro salvo lecturas de Database/PlayerState) ─

static func make_access_context(clearance: int, tags: Array = [], office_room: String = "",
		disguise: String = "", items: Array = []) -> Dictionary:
	var tag_list: Array[String] = []
	for tag: Variant in tags:
		tag_list.append(str(tag))
	var item_list: Array[String] = []
	for item: Variant in items:
		if not item_list.has(str(item)):
			item_list.append(str(item))
	return {
		CTX_CLEARANCE: clearance, CTX_TAGS: tag_list, CTX_OFFICE: office_room,
		CTX_DISGUISE: uniform_id(disguise), CTX_ITEMS: item_list, CTX_CARD_LEVELS: {},
	}


## Contexto del jugador: acreditación (nunca inferior a la de su ocupación), etiquetas y despacho de
## la ocupación, disfraz, herramientas del puesto e inventario (con el nivel de tarjetas ajenas).
static func player_access_context() -> Dictionary:
	var occ: OccupationData = PlayerState.get_occupation()
	var clearance: int = PlayerState.get_clearance()
	var tags: Array = []
	var office: String = ""
	var items: Array = []
	if occ != null:
		clearance = maxi(clearance, occ.clearance)
		tags = occ.special_access.duplicate()
		office = occ.office_room
		items.append_array(occ.tools)
	var ctx: Dictionary = make_access_context(clearance, tags, office, PlayerState.get_disguise(), items)
	for item: ItemData in PlayerState.get_inventory():
		if not (ctx[CTX_ITEMS] as Array).has(item.id):
			(ctx[CTX_ITEMS] as Array).append(item.id)
		if item.extra.has(EXTRA_CLEARANCE):
			(ctx[CTX_CARD_LEVELS] as Dictionary)[item.id] = int(item.extra[EXTRA_CLEARANCE])
	return ctx


## "security" → "uniform_security" cuando esa forma existe en mapa.uniformes.
static func uniform_id(disguise: String) -> String:
	if disguise.is_empty():
		return ""
	var table: Dictionary = _balance_dict(B_UNIFORMS)
	if not table.has(disguise) and table.has(UNIFORM_PREFIX + disguise):
		return UNIFORM_PREFIX + disguise
	return disguise


static func room_access(room: RoomData, ctx: Dictionary) -> int:
	if room == null:
		return ACCESS_FORBIDDEN
	if is_room_allowed(room, ctx):
		return ACCESS_ALLOWED
	return ACCESS_FORBIDDEN if alternative_method(room, ctx).is_empty() else ACCESS_ALTERNATIVE


static func is_room_allowed(room: RoomData, ctx: Dictionary) -> bool:
	var tags: Array = ctx.get(CTX_TAGS, [])
	var office: String = str(ctx.get(CTX_OFFICE, ""))
	if not office.is_empty() and DatabaseSystem.get_room_base_id(room.id) == office:
		return true
	if meets_door_rule(room, int(ctx.get(CTX_CLEARANCE, -1)), tags):
		return true
	for tag: Variant in tags:
		if tag_grants(str(tag), room):
			return true
	return false


## Regla de puertas de FloorStreamer: nivel; con special_access, "and" exige nivel y etiqueta, "or"
## cualquiera de los dos (sin modo: solo el nivel).
static func meets_door_rule(room: RoomData, clearance: int, tags: Array) -> bool:
	var level_ok: bool = clearance >= room.clearance_required
	if room.special_access.is_empty():
		return level_ok
	var special_ok: bool = false
	for tag: String in room.special_access:
		special_ok = special_ok or tags.has(tag)
	match access_mode(room):
		MODE_OR:
			return level_ok or special_ok
		MODE_AND:
			return level_ok and special_ok
	return level_ok


static func access_mode(room: RoomData) -> String:
	if room.extra.has(KEY_MODE):
		return str(room.extra[KEY_MODE])
	var base: RoomData = Database.get_room(str(room.extra.get(KEY_BASE_ID, "")))
	return str(base.extra.get(KEY_MODE, "")) if base != null else ""


## Etiqueta de ocupación con regla propia (balance mapa.acceso_por_etiqueta): plantas y/o salas.
static func tag_grants(tag: String, room: RoomData) -> bool:
	var rule: Variant = _balance_dict(B_TAG_RULES).get(tag, null)
	if not rule is Dictionary:
		return false
	var r: Dictionary = rule
	var in_floor: bool = (r.get(RULE_FLOORS, []) as Array).has(room.floor)
	var in_rooms: bool = (r.get(RULE_ROOMS, []) as Array).has(DatabaseSystem.get_room_base_id(room.id))
	if not (in_floor or in_rooms):
		return false
	return not r.has(RULE_MAX_ROOM) or room.clearance_required <= int(r[RULE_MAX_ROOM])


## Primer método alternativo aplicable ("" si ninguno). Ver METHOD_*.
static func alternative_method(room: RoomData, ctx: Dictionary) -> String:
	for method: String in ALT_ORDER:
		if _alt_applies(method, room, ctx):
			return method
	return ""


static func _alt_applies(method: String, room: RoomData, ctx: Dictionary) -> bool:
	match method:
		METHOD_UNIFORM:
			return _uniform_grants(room, ctx)
		METHOD_MASTER_KEYS:
			return _has_any(ctx, B_MASTER_KEYS) and room.clearance_required <= Database.get_balance_int(B_MASTER_MAX)
		METHOD_CARD:
			return _card_grants(room, ctx)
		METHOD_OLD_KEYS:
			return room.illegitimate_entries.has(ENTRY_OLD_KEYS) and _has_any(ctx, B_OLD_KEYS)
		METHOD_FORCED_LOCK:
			return room.illegitimate_entries.has(ENTRY_FORCED_LOCK) and _has_any(ctx, B_FORCE_TOOLS)
		METHOD_VENT:
			return _vent_grants(room, ctx)
		METHOD_ROOF_LEDGE:
			return _ledge_grants(room, ctx)
	return false


## Etiquetas de rol que imita el disfraz puesto o un uniforme llevado encima.
static func disguise_tags(ctx: Dictionary) -> Array[String]:
	var table: Dictionary = _balance_dict(B_UNIFORMS)
	var sources: Array[String] = [str(ctx.get(CTX_DISGUISE, ""))]
	for item: Variant in ctx.get(CTX_ITEMS, []):
		sources.append(str(item))
	var out: Array[String] = []
	for source: String in sources:
		for tag: Variant in table.get(source, []):
			if not out.has(str(tag)):
				out.append(str(tag))
	return out


## Uniforme: la sala pertenece al rol imitado (su special_access o una regla de etiqueta).
static func _uniform_grants(room: RoomData, ctx: Dictionary) -> bool:
	for tag: String in disguise_tags(ctx):
		if room.special_access.has(tag) or tag_grants(tag, room):
			return true
	return false


static func _card_grants(room: RoomData, ctx: Dictionary) -> bool:
	var table: Dictionary = _balance_dict(B_CARDS)
	var levels: Dictionary = ctx.get(CTX_CARD_LEVELS, {})
	for item: Variant in ctx.get(CTX_ITEMS, []):
		var id: String = str(item)
		var level: int = int(levels.get(id, table.get(id, -1)))
		if level >= 0 and meets_door_rule(room, level, ctx.get(CTX_TAGS, [])):
			return true
	return false


## Conducto: trampilla hacia una sala verde del jugador, o hacia la red si puede usarla.
static func _vent_grants(room: RoomData, ctx: Dictionary) -> bool:
	var targets: Array[String] = vent_targets(room)
	if targets.is_empty() and not room.illegitimate_entries.has(ENTRY_VENT):
		return false
	for target: String in targets:
		var other: RoomData = Database.get_room(target)
		if target != VENT_NETWORK_ID and other != null and is_room_allowed(other, ctx):
			return true
	if targets.is_empty() or targets.has(VENT_NETWORK_ID):
		return vent_network_usable(ctx)
	return false


## Destinos (ids base) de las trampillas de conducto de una sala.
static func vent_targets(room: RoomData) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) != VENT_HATCH_TYPE:
			continue
		for target: Variant in entry.get(LEADS_TO, []):
			if not out.has(str(target)):
				out.append(str(target))
	return out


static func vent_network_usable(ctx: Dictionary) -> bool:
	if _has_any(ctx, B_VENT_KEYS):
		return true
	var net: RoomData = Database.get_room(VENT_NETWORK_ID)
	return net != null and (is_room_allowed(net, ctx) or _uniform_grants(net, ctx))


static func _ledge_grants(room: RoomData, ctx: Dictionary) -> bool:
	if not room.illegitimate_entries.has(ENTRY_ROOF_LEDGE):
		return false
	_index_ledges()
	for source: String in _ledge_sources.get(DatabaseSystem.get_room_base_id(room.id), []):
		var src: RoomData = Database.get_room(source)
		if src != null and is_room_allowed(src, ctx):
			return true
	return false


## Índice (una vez por proceso): sala destino → salas con cornisa que llevan a ella.
static func _index_ledges() -> void:
	if _ledges_indexed:
		return
	_ledges_indexed = true
	for room: RoomData in Database.get_all_rooms():
		for entry: Dictionary in room.interactables:
			if str(entry.get("type", "")) != LEDGE_TYPE:
				continue
			for target: Variant in entry.get(LEADS_TO, []):
				if not _ledge_sources.has(str(target)):
					_ledge_sources[str(target)] = []
				(_ledge_sources[str(target)] as Array).append(room.id)


static func _has_any(ctx: Dictionary, balance_path: String) -> bool:
	var items: Array = ctx.get(CTX_ITEMS, [])
	var wanted: Variant = Database.get_balance(balance_path)
	if not wanted is Array:
		return false
	for id: Variant in wanted:
		if items.has(str(id)):
			return true
	return false


static func _balance_dict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(path)
	return value if value is Dictionary else {}


## Salas propias de una planta (sin circulación ni salas virtuales), en orden de datos.
static func floor_rooms(floor_number: int) -> Array[RoomData]:
	var out: Array[RoomData] = []
	for room: RoomData in FloorLayout.rooms_on_floor(floor_number):
		if not MapFloorPlan.is_circulation(room):
			out.append(room)
	return out


## Estado de la planta: el mejor de sus salas propias; los cuartos de servicio compartidos
## (copias transversales como los de limpieza) solo dan un punto de apoyo: como mucho ámbar.
static func floor_access(floor_number: int, ctx: Dictionary) -> int:
	var own: int = ACCESS_FORBIDDEN
	var service: int = ACCESS_FORBIDDEN
	for room: RoomData in floor_rooms(floor_number):
		if is_service_room(room):
			service = mini(service, room_access(room, ctx))
		else:
			own = mini(own, room_access(room, ctx))
	return combine_floor(own, service)


static func combine_floor(own: int, service: int) -> int:
	if own != ACCESS_FORBIDDEN:
		return own
	return ACCESS_FORBIDDEN if service == ACCESS_FORBIDDEN else ACCESS_ALTERNATIVE


## Copia por planta de un espacio transversal (cuarto de limpieza...): no es «la planta».
static func is_service_room(room: RoomData) -> bool:
	return room.extra.has(KEY_BASE_ID)


## Huecos verticales del núcleo (ascensores, escaleras, escalera de servicio, montacargas) según los
## espacios transversales de datos: {id, kind, lo, hi, index (orden dentro de su tipo)}.
static func core_columns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: String in CutCanvas.COLUMN_ORDER:
		var index: int = 0
		for room: RoomData in Database.get_all_rooms():
			if room.is_transversal() and FloorLayout.transit_kind_of(room) == kind:
				out.append({"id": room.id, "kind": kind, "lo": room.floors[0], "hi": room.floors[1], "index": index})
				index += 1
	return out


## Plano cacheado (FloorLayout es determinista y los datos no cambian durante la ejecución).
static func plan_of(floor_number: int) -> Dictionary:
	if not _plan_cache.has(floor_number):
		_plan_cache[floor_number] = FloorLayout.compute(floor_number)
	return _plan_cache[floor_number]


# ─── Etiquetas de planta ───────────────────────────────────────────

## Etiqueta corta: "20", "G"/"PB", "B1"/"S1", "Roof", "Plant".
static func floor_label_short(floor_number: int) -> String:
	if floor_number == Database.get_balance_int(B_FACTORY):
		return TranslationServer.translate("MAP_FACTORY_SHORT")
	if floor_number == Database.get_balance_int(B_ROOF):
		return TranslationServer.translate("MAP_ROOF_SHORT")
	if floor_number == 0:
		return TranslationServer.translate("UI_TOWER_GROUND_SHORT")
	if floor_number < 0:
		return String(TranslationServer.translate("UI_TOWER_BASEMENT_SHORT")).format({"n": -floor_number})
	return str(floor_number)


static func floor_name(floor_number: int) -> String:
	if floor_number == Database.get_balance_int(B_FACTORY):
		return TranslationServer.translate("MAP_FLOOR_FACTORY")
	if floor_number == Database.get_balance_int(B_ROOF):
		return TranslationServer.translate("MAP_FLOOR_ROOF")
	if floor_number == 0:
		return TranslationServer.translate("MAP_FLOOR_GROUND")
	if floor_number < 0:
		return UITheme.trf("MAP_FLOOR_BASEMENT_FMT", [-floor_number])
	return UITheme.trf("MAP_FLOOR_NAME_FMT", [floor_number])


# ─── Modelo de la vista ────────────────────────────────────────────

func _access_context() -> Dictionary:
	var given: Variant = _context.get(CONTEXT_ACCESS, null)
	if given is Dictionary and not (given as Dictionary).is_empty():
		var ctx: Dictionary = (given as Dictionary).duplicate(true)
		ctx[CTX_DISGUISE] = uniform_id(str(ctx.get(CTX_DISGUISE, "")))
		return ctx
	return player_access_context()


func _rebuild_model() -> void:
	var ctx: Dictionary = _access_context()
	var statuses: Dictionary = {}
	var methods: Dictionary = {}
	var floor_status: Dictionary = {}
	var blocks: Dictionary = {}
	for f: int in get_cut_floors():
		var best: Vector2i = Vector2i(ACCESS_FORBIDDEN, ACCESS_FORBIDDEN)
		var ids: Array[String] = []
		for room: RoomData in FloorLayout.rooms_on_floor(f):
			var status: int = room_access(room, ctx)
			statuses[room.id] = status
			methods[room.id] = alternative_method(room, ctx) if status == ACCESS_ALTERNATIVE else ""
			if MapFloorPlan.is_circulation(room):
				continue
			ids.append(room.id)
			best = Vector2i(best.x, mini(best.y, status)) if is_service_room(room) else Vector2i(mini(best.x, status), best.y)
		floor_status[f] = combine_floor(best.x, best.y)
		blocks[f] = _order_by_plan(f, ids)
	_model = {"ctx": ctx, "statuses": statuses, "methods": methods, "floor_status": floor_status, "blocks": blocks}
	_model["dots"] = _collect_dots()
	_model["player_floor"] = _player_floor()
	_model["player_room"] = _player_room()


## Orden izquierda → derecha según el plano (centro x del rectángulo), estable por datos.
func _order_by_plan(floor_number: int, ids: Array[String]) -> Array[String]:
	var rooms: Dictionary = plan_of(floor_number).get("rooms", {})
	var keyed: Array = []
	for i: int in ids.size():
		var rect: Rect2i = rooms.get(ids[i], Rect2i())
		keyed.append([rect.position.x * 2 + rect.size.x, i, ids[i]])
	keyed.sort()
	var out: Array[String] = []
	for entry: Array in keyed:
		out.append(str(entry[2]))
	return out


func _collect_dots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var targets: Array[String] = marked_targets()
	var need: int = Database.get_balance_int(B_ROUTINE_LEVEL)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var dot: Dictionary = _dot_for(npc, targets.has(npc.id), need)
		if not dot.is_empty():
			out.append(dot)
	return out


func _dot_for(npc: NPCRuntime, is_target: bool, need: int) -> Dictionary:
	if not npc.alive or not (is_target or npc.is_named or _knows(npc.id)):
		return {}
	var dot: Dictionary = {"npc_id": npc.id, "name": npc.name, "target": is_target, "approximate": false}
	if file_level_for(npc.id) >= need and not npc.current_room.is_empty():
		dot["room_id"] = npc.current_room
		dot["floor"] = _floor_of(npc.current_room, npc.floor)
		return dot
	if not is_target or npc.home_room.is_empty():
		return {}
	dot["room_id"] = npc.home_room
	dot["floor"] = _floor_of(npc.home_room, npc.floor)
	dot["approximate"] = true
	return dot


func _knows(npc_id: String) -> bool:
	return NPCDirector.has_method("knows_player") and bool(NPCDirector.call("knows_player", npc_id))


static func _floor_of(room_id: String, fallback: int) -> int:
	var room: RoomData = Database.get_room(room_id)
	return room.floor if room != null and not room.is_transversal() else fallback


## Objetivos marcados: context.targets, o get_marked_targets() del autoload que lo exponga.
func marked_targets() -> Array[String]:
	var raw: Variant = _context.get(CONTEXT_TARGETS, null)
	if raw == null:
		for owner: Node in [PlayerState, NPCDirector]:
			if owner.has_method(TARGETS_GETTER):
				raw = owner.call(TARGETS_GETTER)
				break
	var out: Array[String] = []
	if raw is Array:
		for id: Variant in raw:
			out.append(str(id))
	return out


## Nivel de expediente efectivo para un personaje: el del puesto, context.file_levels o el que
## conceda get_file_level(npc_id) (intrusión en RRHH, chantaje...).
func file_level_for(npc_id: String) -> int:
	var level: int = PlayerState.get_personnel_file_level()
	var given: Variant = _context.get(CONTEXT_FILE_LEVELS, {})
	if given is Dictionary:
		level = maxi(level, int((given as Dictionary).get(npc_id, 0)))
	for owner: Node in [PlayerState, NPCDirector]:
		if owner.has_method(FILE_LEVEL_GETTER):
			level = maxi(level, int(owner.call(FILE_LEVEL_GETTER, npc_id)))
	return level


func _player_floor() -> int:
	var streamer: Node = get_tree().get_first_node_in_group(FloorStreamer.GROUP) if is_inside_tree() else null
	if streamer is FloorStreamer and not (streamer as FloorStreamer).get_plan().is_empty():
		return (streamer as FloorStreamer).get_current_floor()
	return PlayerState.get_floor()


func _player_room() -> String:
	return PlayerState.get_room()


## Celda del jugador en el plano cargado (INF si no hay mundo o no es esa planta).
func _player_cell(floor_number: int) -> Vector2:
	if not is_inside_tree():
		return Vector2.INF
	var streamer: FloorStreamer = get_tree().get_first_node_in_group(FloorStreamer.GROUP) as FloorStreamer
	var player: Node2D = get_tree().get_first_node_in_group(Player.GROUP) as Node2D
	if streamer == null or player == null or streamer.get_current_floor() != floor_number:
		return Vector2.INF
	return Vector2(streamer.world_to_cell(player.global_position)) + Vector2(0.5, 0.5)


func _plan_model(floor_number: int) -> Dictionary:
	return {
		"plan": plan_of(floor_number), "statuses": _model.get("statuses", {}),
		"methods": _model.get("methods", {}), "layers": _layers.duplicate(), "band": _band,
		"dots": _model.get("dots", []), "player_floor": _model.get("player_floor", NO_FLOOR),
		"player_room": _model.get("player_room", ""), "player_cell": _player_cell(floor_number),
	}


func _push_model() -> void:
	if _cut != null:
		_cut.queue_redraw()
	if _plan_view != null and is_zoomed():
		_plan_view.set_model(_plan_model(_zoom_floor))
	_refresh_floor_panel()


# ─── Construcción de la interfaz ───────────────────────────────────

func _build() -> void:
	_cut = CutCanvas.new()
	_cut.view = self
	add_child(_cut)
	_plan_view = MapFloorPlan.new()
	_plan_view.visible = false
	add_child(_plan_view)
	_title = _mk_label(1.45, UITheme.FONT_BOLD, "white")
	_subtitle = _mk_label(0.78, UITheme.FONT_SEMIBOLD, "white")
	_footer_left = _mk_label(0.68, UITheme.FONT_SEMIBOLD, "ink_soft")
	_footer_right = _mk_label(0.62, UITheme.FONT_REGULAR, "ink_soft")
	for label: Label in [_title, _subtitle, _footer_left, _footer_right]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		add_child(label)
	_footer_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_side_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side)
	_build_access_section()
	_build_legend_section()
	_build_layer_section()
	_build_floor_section()
	_cut.floor_hovered.connect(_on_cut_hovered)
	_cut.floor_clicked.connect(zoom_to_floor)
	_plan_view.room_hovered.connect(_on_room_hovered)
	_plan_view.room_clicked.connect(_on_room_hovered)


func _mk_label(ratio: float, font_path: String, color_key: String, wrap: bool = false) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override("font", UITheme.font(font_path))
	label.add_theme_color_override("font_color", MapFloorPlan.palette()[color_key])
	label.set_meta("map_color", color_key)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sized[label] = ratio
	return label


func _section_title(key: String) -> Label:
	var label: Label = _mk_label(0.72, UITheme.FONT_BOLD, "red")
	label.text = tr(key).to_upper()
	label.set_meta("map_key", key)
	return label


func _separator() -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.color = MapFloorPlan.palette()["ink_faint"]
	line.custom_minimum_size = Vector2(0.0, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _build_access_section() -> void:
	_side.add_child(_section_title("MAP_YOUR_ACCESS"))
	var row: HBoxContainer = HBoxContainer.new()
	_side.add_child(row)
	_badge = _mk_label(1.35, UITheme.FONT_BOLD, "white")
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_badge)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_occ_label = _mk_label(0.92, UITheme.FONT_BOLD, "ink", true)
	_disguise_label = _mk_label(0.72, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	_files_label = _mk_label(0.72, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	for label: Label in [_occ_label, _disguise_label, _files_label]:
		col.add_child(label)
	_side.add_child(_separator())


func _build_legend_section() -> void:
	_side.add_child(_section_title("MAP_LEGEND_TITLE"))
	for status: int in [ACCESS_ALLOWED, ACCESS_ALTERNATIVE, ACCESS_FORBIDDEN]:
		var desc: String = MapFloorPlan.status_key(status) + "_DESC"
		_side.add_child(_legend_row(Swatch.KIND_STATUS, status, MapFloorPlan.status_key(status), desc))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_side.add_child(grid)
	var symbols: Array = [
		[Swatch.KIND_PIN, "MAP_LEGEND_YOU"], [Swatch.KIND_EVAC, "MAP_LEGEND_EVAC"],
		[Swatch.KIND_DOT, "MAP_LEGEND_KNOWN"], [Swatch.KIND_TARGET, "MAP_LEGEND_TARGET"],
	]
	for entry: Array in symbols:
		grid.add_child(_legend_row(str(entry[0]), ACCESS_ALLOWED, str(entry[1]), ""))
	_side.add_child(_separator())


func _legend_row(kind: String, status: int, key: String, desc_key: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var swatch: Swatch = Swatch.new()
	swatch.kind = kind
	swatch.status = status
	row.add_child(swatch)
	var label: Label = _mk_label(0.74, UITheme.FONT_BOLD if desc_key.is_empty() else UITheme.FONT_BOLD, "ink")
	label.set_meta("map_key", key)
	label.set_meta("map_desc", desc_key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return row


func _build_layer_section() -> void:
	_side.add_child(_section_title("MAP_LAYERS_TITLE"))
	var index: int = 1
	for layer: String in LAYERS:
		var chip: ToggleChip = ToggleChip.new()
		chip.icon_name = str(LAYER_ICONS[layer])
		chip.hotkey = str(index)
		chip.set_meta("map_key", LAYER_KEYS[layer])
		chip.toggled.connect(func(on: bool) -> void: set_layer(layer, on))
		_side.add_child(chip)
		_toggles[layer] = chip
		index += 1
	_band_row = HBoxContainer.new()
	_side.add_child(_band_row)
	var prev: IconButton = IconButton.new()
	prev.glyph = IconButton.GLYPH_LEFT
	prev.pressed.connect(_shift_band.bind(-1))
	_band_row.add_child(prev)
	_band_label = _mk_label(0.78, UITheme.FONT_BOLD, "people")
	_band_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band_row.add_child(_band_label)
	var next: IconButton = IconButton.new()
	next.glyph = IconButton.GLYPH_RIGHT
	next.pressed.connect(_shift_band.bind(1))
	_band_row.add_child(next)
	_side.add_child(_separator())


func _build_floor_section() -> void:
	_floor_title = _mk_label(1.05, UITheme.FONT_BOLD, "ink", true)
	_side.add_child(_floor_title)
	_floor_band = _mk_label(0.7, UITheme.FONT_BOLD, "ink_soft")
	_side.add_child(_floor_band)
	var status_row: HBoxContainer = HBoxContainer.new()
	_side.add_child(status_row)
	_floor_status = Swatch.new()
	_floor_status.kind = Swatch.KIND_CHIP
	status_row.add_child(_floor_status)
	_floor_status_label = _mk_label(0.8, UITheme.FONT_BOLD, "ink")
	status_row.add_child(_floor_status_label)
	_floor_people = _mk_label(0.7, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	_side.add_child(_floor_people)
	_room_list = VBoxContainer.new()
	_room_list.add_theme_constant_override("separation", 2)
	_side.add_child(_room_list)
	_nav_row = HBoxContainer.new()
	_side.add_child(_nav_row)
	_add_nav_button(IconButton.GLYPH_BACK, "MAP_BACK", zoom_out)
	_add_nav_button(IconButton.GLYPH_UP, "", _step_zoom.bind(1))
	_add_nav_button(IconButton.GLYPH_DOWN, "", _step_zoom.bind(-1))
	_hint = _mk_label(0.66, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	_side.add_child(_hint)


func _add_nav_button(glyph: String, key: String, action: Callable) -> void:
	var button: IconButton = IconButton.new()
	button.glyph = glyph
	if not key.is_empty():
		button.set_meta("map_key", key)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	_nav_row.add_child(button)


# ─── Maquetación y textos ──────────────────────────────────────────

func _base() -> int:
	return MapFloorPlan.base_font_of(self)


func _layout() -> void:
	var base: float = float(_base())
	var margin: float = maxf(6.0, minf(size.x, size.y) * MARGIN_RATIO)
	var poster: Rect2 = Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	var frame: float = maxf(5.0, base * FRAME_RATIO)
	var inner: Rect2 = poster.grow(-frame)
	var header: Rect2 = Rect2(inner.position, Vector2(inner.size.x, maxf(52.0, base * HEADER_RATIO)))
	var footer_h: float = base * FOOTER_RATIO
	var footer: Rect2 = Rect2(inner.position.x, inner.end.y - footer_h, inner.size.x, footer_h)
	var pad: float = base * PAD_RATIO
	var body: Rect2 = Rect2(inner.position.x + pad, header.end.y + pad, inner.size.x - pad * 2.0, footer.position.y - header.end.y - pad * 2.0)
	var side_w: float = clampf(body.size.x * SIDE_SHARE, minf(base * SIDE_MIN_RATIO, body.size.x * SIDE_MAX_SHARE), body.size.x * SIDE_MAX_SHARE)
	var map_rect: Rect2 = Rect2(body.position, Vector2(body.size.x - side_w - pad, body.size.y))
	_rects = {"poster": poster, "inner": inner, "header": header, "footer": footer, "map": map_rect, "frame": frame}
	_place(_cut, map_rect)
	_place(_plan_view, map_rect)
	_place(_side_scroll, Rect2(map_rect.end.x + pad, body.position.y, side_w, body.size.y))
	_side.custom_minimum_size.x = side_w - base * 0.8
	_layout_header(header, base)
	_place(_footer_left, Rect2(footer.position.x + pad, footer.position.y, footer.size.x * 0.56 - pad, footer.size.y))
	_place(_footer_right, Rect2(footer.position.x + footer.size.x * 0.56, footer.position.y, footer.size.x * 0.44 - pad, footer.size.y))
	queue_redraw()


func _layout_header(header: Rect2, base: float) -> void:
	var left: float = header.position.x + header.size.y * 1.05
	var sign_w: float = header.size.y * 1.55
	var width: float = header.size.x - (left - header.position.x) - sign_w - base
	var title_h: float = _title.get_combined_minimum_size().y
	var sub_h: float = _subtitle.get_combined_minimum_size().y
	var top: float = header.position.y + (header.size.y - title_h - sub_h) * 0.5
	_place(_title, Rect2(left, top, width, title_h))
	_place(_subtitle, Rect2(left, top + title_h, width, sub_h))


static func _place(ctrl: Control, r: Rect2) -> void:
	ctrl.position = r.position
	ctrl.size = r.size


func _apply_sizes() -> void:
	var base: float = float(_base())
	var pal: Dictionary = MapFloorPlan.palette()
	for label: Variant in _sized:
		if is_instance_valid(label):
			(label as Label).add_theme_font_size_override("font_size", maxi(9, roundi(base * float(_sized[label]))))
			(label as Label).add_theme_color_override("font_color", pal[str((label as Label).get_meta("map_color"))])
	_badge.custom_minimum_size = Vector2(base * 2.9, base * 2.3)
	_badge.add_theme_stylebox_override("normal", _badge_box(pal["ink"], base))
	_side.add_theme_constant_override("separation", roundi(base * 0.42))
	for chip: Variant in _toggles.values():
		(chip as ToggleChip).restyle(base)
	for button: Node in _band_row.get_children() + _nav_row.get_children():
		if button is IconButton:
			(button as IconButton).restyle(base)


static func _badge_box(col: Color, base: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(roundi(base * 0.3))
	sb.content_margin_left = base * 0.3
	sb.content_margin_right = base * 0.3
	return sb


func _refresh_texts() -> void:
	if _title == null:
		return
	_title.text = tr("MAP_TITLE")
	_subtitle.text = tr("MAP_SUBTITLE") if not is_zoomed() else UITheme.trf("MAP_SUBTITLE_FLOOR", [floor_name(_zoom_floor)])
	_footer_left.text = tr("MAP_FOOTER_JOKE")
	_footer_right.text = tr("MAP_FOOTER_POSTED")
	for node: Node in _side.find_children("*", "", true, false):
		if node.has_meta("map_key") and (node is Label or node is Button):
			_apply_key_text(node)
	_refresh_access_panel()
	_refresh_band_label()
	_refresh_floor_panel()
	_nav_row.visible = is_zoomed()
	var touch: bool = UIRoot.detect_touch()
	_hint.text = tr("MAP_HINT_ZOOM") if is_zoomed() else tr("MAP_HINT_TOUCH" if touch else "MAP_HINT_CUT")


func _apply_key_text(node: Node) -> void:
	var key: String = str(node.get_meta("map_key"))
	var text: String = tr(key)
	if node is Label and str(node.get_meta("map_color", "")) == "red":
		text = text.to_upper()
	var desc: String = str(node.get_meta("map_desc", ""))
	if not desc.is_empty():
		text += " — " + tr(desc)
	node.set("text", text)


func _refresh_access_panel() -> void:
	var ctx: Dictionary = _model.get("ctx", {})
	_badge.text = UITheme.trf("MAP_CLEARANCE_FMT", [int(ctx.get(CTX_CLEARANCE, 0))])
	var occ: OccupationData = PlayerState.get_occupation()
	_occ_label.text = tr(occ.name_key) if occ != null else ""
	var disguise: String = str(ctx.get(CTX_DISGUISE, ""))
	var item: ItemData = Database.get_item(disguise) if not disguise.is_empty() else null
	_disguise_label.text = UITheme.trf("MAP_DISGUISE_FMT", [tr(item.name_key)]) if item != null else tr("MAP_NO_DISGUISE")
	var level: int = PlayerState.get_personnel_file_level()
	var need: int = Database.get_balance_int(B_ROUTINE_LEVEL)
	_files_label.text = UITheme.trf("MAP_FILE_LEVEL_FMT", [level])
	if level < need:
		_files_label.text += "\n" + UITheme.trf("MAP_ROUTINES_LOCKED_FMT", [need])


func _refresh_band_label() -> void:
	if _band_label == null:
		return
	_band_label.text = UITheme.trf("MAP_OCCUPANCY_BAND_FMT", [tr(GameClock.get_band_name_key(_band))]) if not _band.is_empty() else ""
	_band_row.visible = is_layer_on(LAYER_OCCUPANCY)


func _sync_toggles() -> void:
	for layer: String in _toggles:
		(_toggles[layer] as ToggleChip).set_pressed_no_signal(is_layer_on(layer))
		(_toggles[layer] as ToggleChip).queue_redraw()
	_refresh_band_label()


func _shift_band(delta: int) -> void:
	var order: Array[String] = GameClock.get_band_order()
	if order.is_empty():
		return
	var index: int = maxi(0, order.find(_band))
	set_band(order[posmod(index + delta, order.size())])


func _step_zoom(delta: int) -> void:
	var floors: Array[int] = get_cut_floors()
	var index: int = floors.find(_zoom_floor)
	if index >= 0 and index + delta >= 0 and index + delta < floors.size():
		zoom_to_floor(floors[index + delta])


# ─── Panel de planta ───────────────────────────────────────────────

func _refresh_floor_panel() -> void:
	if _floor_title == null:
		return
	var f: int = _zoom_floor if is_zoomed() else _selected_floor
	var has_floor: bool = f != NO_FLOOR
	_floor_band.visible = has_floor
	_floor_status.get_parent().visible = has_floor
	_floor_people.visible = has_floor
	for child: Node in _room_list.get_children():
		child.queue_free()
	_listed.clear()
	if not has_floor:
		_floor_title.text = tr("MAP_FLOOR_PROMPT")
		return
	_floor_title.text = floor_name(f)
	var band: Dictionary = Database.get_art_band_for_floor(f)
	_floor_band.text = tr(str(band.get("name_key", ""))).to_upper()
	_floor_band.add_theme_color_override("font_color", CutCanvas.band_ink(f))
	_floor_status.status = get_floor_status(f)
	_floor_status.queue_redraw()
	_floor_status_label.text = tr(MapFloorPlan.status_key(get_floor_status(f)))
	_floor_people.text = _people_line(f)
	for room_id: String in get_cut_room_ids(f).slice(0, MAX_ROOM_ROWS):
		_room_list.add_child(_room_row(room_id))
		_listed.append(room_id)


func _people_line(f: int) -> String:
	var known: int = 0
	var targets: int = 0
	for dot: Dictionary in _model.get("dots", []):
		if int(dot.get("floor", NO_FLOOR)) == f:
			known += 1
			targets += 1 if bool(dot.get("target", false)) else 0
	var line: String = UITheme.trf("MAP_DOTS_COUNT_FMT", [known])
	if targets > 0:
		line += " · " + UITheme.trf("MAP_TARGETS_COUNT_FMT", [targets])
	return line


func _room_row(room_id: String) -> HBoxContainer:
	var room: RoomData = Database.get_room(room_id)
	var row: HBoxContainer = HBoxContainer.new()
	var swatch: Swatch = Swatch.new()
	swatch.kind = Swatch.KIND_STATUS
	swatch.status = get_room_status(room_id)
	swatch.small = true
	row.add_child(swatch)
	var name_label: Label = _mk_label(0.74, UITheme.FONT_BOLD if room_id == _selected_room else UITheme.FONT_SEMIBOLD, "ink")
	name_label.text = tr(room.name_key) if room != null else room_id
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	var method: String = get_room_method(room_id)
	var tail: Label = _mk_label(0.64, UITheme.FONT_BOLD, "alt_ink" if not method.is_empty() else "ink_soft")
	var level: String = UITheme.trf("MAP_CLEARANCE_FMT", [room.clearance_required if room != null else 0])
	tail.text = tr(str(METHOD_KEYS[method])) + " · " + level if not method.is_empty() else level
	row.add_child(tail)
	var base: float = float(_base())
	for label: Label in [name_label, tail]:
		label.add_theme_font_size_override("font_size", maxi(9, roundi(base * float(_sized[label]))))
	return row


func _on_cut_hovered(floor_number: int) -> void:
	if floor_number != NO_FLOOR:
		select_floor(floor_number)


func _on_room_hovered(room_id: String) -> void:
	if room_id.is_empty() or room_id == _selected_room:
		return
	_selected_room = room_id
	_refresh_floor_panel()


# ─── Dibujo del cartel ─────────────────────────────────────────────

func _draw() -> void:
	if _rects.is_empty():
		return
	var pal: Dictionary = MapFloorPlan.palette()
	var poster: Rect2 = _rects["poster"]
	var frame: float = _rects["frame"]
	var radius: float = frame * 1.4
	draw_polygon(UITheme.rounded_rect_points(Rect2(poster.position + Vector2(frame, frame) * 0.8, poster.size), radius),
			PackedColorArray([Color(0, 0, 0, 0.35)]))
	draw_polygon(UITheme.rounded_rect_points(poster, radius), PackedColorArray([pal["red"]]))
	draw_rect(_rects["inner"], pal["paper"])
	var header: Rect2 = _rects["header"]
	draw_rect(header, pal["red"])
	draw_rect(Rect2(header.position.x, header.end.y - frame * 0.35, header.size.x, frame * 0.35), pal["red_dark"])
	_draw_header_badges(header, pal)
	_draw_screws(poster, frame, pal)
	var footer: Rect2 = _rects["footer"]
	draw_line(footer.position, Vector2(footer.end.x, footer.position.y), pal["ink_faint"], 2.0)
	var side_x: float = _side_scroll.position.x - float(_base()) * PAD_RATIO * 0.5
	draw_line(Vector2(side_x, _side_scroll.position.y), Vector2(side_x, _side_scroll.position.y + _side_scroll.size.y), pal["ink_faint"], 2.0)


func _draw_header_badges(header: Rect2, pal: Dictionary) -> void:
	var s: float = header.size.y * 0.66
	var at: Vector2 = Vector2(header.position.x + header.size.y * 0.52, header.get_center().y)
	draw_circle(at, s * 0.5, pal["white"])
	UITheme.draw_icon(self, "star", Rect2(at - Vector2(s, s) * 0.32, Vector2(s, s) * 0.64), pal["red"], 2.0)
	var sign_h: float = header.size.y * 0.62
	var sign_rect: Rect2 = Rect2(header.end.x - sign_h * 2.3 - header.size.y * 0.25, header.get_center().y - sign_h * 0.5, sign_h * 2.3, sign_h)
	draw_polygon(UITheme.rounded_rect_points(sign_rect.grow(3.0), sign_h * 0.16), PackedColorArray([pal["white"]]))
	MapFloorPlan.draw_exit_sign(self, sign_rect, pal)


## Tornillos en las esquinas del marco: el plano es una placa atornillada a la pared.
func _draw_screws(poster: Rect2, frame: float, pal: Dictionary) -> void:
	var r: float = frame * 0.32
	var inset: float = frame * 0.5
	for corner: Vector2 in [poster.position, Vector2(poster.end.x, poster.position.y), poster.end, Vector2(poster.position.x, poster.end.y)]:
		var at: Vector2 = Vector2(corner.x + (inset if corner.x == poster.position.x else -inset),
				corner.y + (inset if corner.y == poster.position.y else -inset))
		draw_circle(at, r, pal["concrete"])
		draw_arc(at, r, 0.0, TAU, 12, pal["red_dark"], 1.0, true)
		draw_line(at - Vector2(r, -r) * 0.6, at + Vector2(r, -r) * 0.6, pal["ink_soft"], maxf(1.0, r * 0.3))


# ─── Entrada y ciclo de vida ───────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if LAYER_HOTKEYS.has(key.keycode):
		toggle_layer(str(LAYER_HOTKEYS[key.keycode]))
	elif key.keycode == KEY_UP or key.keycode == KEY_DOWN:
		_step_selection(1 if key.keycode == KEY_UP else -1)
	elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not is_zoomed() and _selected_floor != NO_FLOOR:
		zoom_to_floor(_selected_floor)
	else:
		return
	get_viewport().set_input_as_handled()


func _step_selection(delta: int) -> void:
	if is_zoomed():
		_step_zoom(delta)
		return
	var floors: Array[int] = get_cut_floors()
	var index: int = floors.find(_selected_floor)
	if index < 0:
		index = floors.find(int(_model.get("player_floor", 0)))
	select_floor(floors[clampi(index + delta, 0, floors.size() - 1)])


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
		NOTIFICATION_THEME_CHANGED:
			if is_inside_tree():
				_apply_sizes()
				_layout()
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_inside_tree():
				_refresh_texts()


func _connect_bus(on: bool) -> void:
	if on == _connected:
		return
	_connected = on
	var pairs: Array = [
		[EventBus.clearance_changed, _on_bus_changed_ii], [EventBus.occupation_changed, _on_bus_changed_sss],
		[EventBus.disguise_changed, _on_bus_changed_s], [EventBus.inventory_changed, _on_bus_changed_sb],
		[EventBus.floor_changed, _on_bus_changed_ii], [EventBus.room_entered, _on_bus_changed_sb],
	]
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if on and not sig.is_connected(cb):
			sig.connect(cb)
		elif not on and sig.is_connected(cb):
			sig.disconnect(cb)


func _on_bus_changed_ii(_a: int, _b: int) -> void:
	_refresh_later()


func _on_bus_changed_sss(_a: String, _b: String, _c: String) -> void:
	_refresh_later()


func _on_bus_changed_s(_a: String) -> void:
	_refresh_later()


func _on_bus_changed_sb(_a: String, _b: bool) -> void:
	_refresh_later()


func _refresh_later() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		refresh.call_deferred()


# ═══ Controles auxiliares ══════════════════════════════════════════

## Muestra de leyenda / estado: bloque de acceso, chapa, chincheta, punto, objetivo, flecha.
class Swatch extends Control:
	const KIND_STATUS := "status"
	const KIND_CHIP := "chip"
	const KIND_PIN := "pin"
	const KIND_DOT := "dot"
	const KIND_TARGET := "target"
	const KIND_EVAC := "evac"
	var kind: String = KIND_STATUS
	var status: int = MapFloorPlan.ACCESS_ALLOWED
	var small: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			var base: float = float(MapFloorPlan.base_font_of(self))
			var w: float = base * (1.2 if small else 1.7)
			custom_minimum_size = Vector2(w, base * (0.9 if small else 1.2))

	func _draw() -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var r: Rect2 = Rect2(Vector2.ZERO, size).grow(-2.0)
		var c: Vector2 = r.get_center()
		match kind:
			KIND_STATUS:
				MapFloorPlan.draw_status_block(self, r, status, pal, r.size.y * 0.3, 1.5)
				draw_rect(r, MapFloorPlan.status_ink(status, pal), false, 2.0)
			KIND_CHIP:
				CutCanvas.draw_chip(self, r, status, "", null, 0, pal)
			KIND_PIN:
				MapFloorPlan.draw_pin(self, c, r.size.y * 0.32, pal)
			KIND_DOT:
				MapFloorPlan.draw_npc_dot(self, c, r.size.y * 0.2, pal, false, false)
			KIND_TARGET:
				MapFloorPlan.draw_npc_dot(self, c, r.size.y * 0.2, pal, true, false)
			KIND_EVAC:
				MapFloorPlan.draw_arrow(self, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), pal["green"], r.size.y * 0.22, r.size.y * 0.6)


## Botón conmutador de capa con glifo y tecla.
class ToggleChip extends Button:
	var icon_name: String = "camera"
	var hotkey: String = ""

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func restyle(base: float) -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var pad_l: float = base * 2.1
		add_theme_stylebox_override("normal", _box(pal["white"], pal["ink"], base, pad_l))
		add_theme_stylebox_override("hover", _box(pal["paper_shade"], pal["ink"], base, pad_l))
		add_theme_stylebox_override("pressed", _box(pal["ink"], pal["ink"], base, pad_l))
		add_theme_stylebox_override("hover_pressed", _box(Color(pal["ink"]).lightened(0.15), pal["ink"], base, pad_l))
		for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
			add_theme_color_override(state, pal["ink"])
		add_theme_color_override("font_pressed_color", pal["white"])
		add_theme_color_override("font_hover_pressed_color", pal["white"])
		add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		add_theme_font_size_override("font_size", roundi(base * 0.78))
		custom_minimum_size.y = base * 1.75

	static func _box(bg: Color, border: Color, base: float, pad_l: float) -> StyleBoxFlat:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(roundi(base * 0.3))
		sb.content_margin_left = pad_l
		sb.content_margin_right = base * 2.0
		sb.content_margin_top = base * 0.25
		sb.content_margin_bottom = base * 0.25
		return sb

	func _draw() -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var ink: Color = pal["white"] if button_pressed else pal["ink"]
		var s: float = size.y * 0.56
		var at: Rect2 = Rect2(Vector2(size.y * 0.32, (size.y - s) * 0.5), Vector2(s, s))
		CutCanvas.draw_layer_glyph(self, icon_name, at, ink, pal)
		if not hotkey.is_empty():
			var cap: Rect2 = Rect2(Vector2(size.x - size.y * 0.95, size.y * 0.2), Vector2(size.y * 0.6, size.y * 0.6))
			draw_rect(cap, pal["amber"] if button_pressed else pal["paper_shade"])
			draw_rect(cap, ink, false, 1.5)
			MapFloorPlan.draw_centered(self, UITheme.font(UITheme.FONT_BOLD), cap.get_center(), hotkey, roundi(cap.size.y * 0.7), pal["ink"])


## Botón de flecha (franja anterior/siguiente, planta arriba/abajo, volver al corte).
class IconButton extends Button:
	const GLYPH_LEFT := "left"
	const GLYPH_RIGHT := "right"
	const GLYPH_UP := "up"
	const GLYPH_DOWN := "down"
	const GLYPH_BACK := "back"
	var glyph: String = GLYPH_LEFT

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE

	func restyle(base: float) -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var pad: float = base * (1.9 if glyph == GLYPH_BACK else 0.9)
		add_theme_stylebox_override("normal", ToggleChip._box(pal["white"], pal["ink"], base, pad))
		add_theme_stylebox_override("hover", ToggleChip._box(pal["paper_shade"], pal["ink"], base, pad))
		add_theme_stylebox_override("pressed", ToggleChip._box(pal["paper_shade"], pal["ink"], base, pad))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			add_theme_color_override(state, pal["ink"])
		add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		add_theme_font_size_override("font_size", roundi(base * 0.78))
		custom_minimum_size = Vector2(base * 2.0, base * 1.75)
		if glyph == GLYPH_BACK:
			(get_theme_stylebox("normal") as StyleBoxFlat).content_margin_right = base * 0.7

	func _draw() -> void:
		var ink: Color = MapFloorPlan.palette()["ink"]
		var s: float = size.y * 0.36
		var c: Vector2 = Vector2(size.y * 0.55, size.y * 0.5) if glyph == GLYPH_BACK else size * 0.5
		var pts: Dictionary = {
			GLYPH_LEFT: [Vector2(s * 0.4, -s), Vector2(-s * 0.4, 0.0), Vector2(s * 0.4, s)],
			GLYPH_BACK: [Vector2(s * 0.4, -s), Vector2(-s * 0.4, 0.0), Vector2(s * 0.4, s)],
			GLYPH_RIGHT: [Vector2(-s * 0.4, -s), Vector2(s * 0.4, 0.0), Vector2(-s * 0.4, s)],
			GLYPH_UP: [Vector2(-s, s * 0.4), Vector2(0.0, -s * 0.4), Vector2(s, s * 0.4)],
			GLYPH_DOWN: [Vector2(-s, -s * 0.4), Vector2(0.0, s * 0.4), Vector2(s, -s * 0.4)],
		}
		var line: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in pts.get(glyph, []):
			line.append(c + p)
		draw_polyline(line, ink, maxf(2.0, s * 0.3), true)


## Corte vertical de la torre (S3..azotea) con la nave anexa: la imagen identificativa del juego.
## Planta = fila; núcleo central continuo (ascensores, escaleras, escalera de servicio, montacargas);
## salas a ambos lados en el orden del plano; fachada, forjados y cornisas con la paleta de su banda.
class CutCanvas extends Control:
	signal floor_hovered(floor_number: int)
	signal floor_clicked(floor_number: int)

	const TOP_UNITS := 1.6
	const EARTH_UNITS := 0.55
	const BRACKET_UNITS := 1.3
	const CHIP_UNITS := 2.3
	const GAP_UNITS := 0.45
	const TOWER_SHARE := 0.6
	const TOWER_MAX_UNITS := 26.0
	const FACTORY_SHARE := 0.3
	const FACTORY_MAX_UNITS := 12.0
	const FACTORY_H_UNITS := 2.4
	const FACTORY_ROOF_UNITS := 0.55
	const ASSEMBLY_UNITS := 2.6
	const CORE_SHARE := 0.2
	const SLAB_RATIO := 0.14
	const WALL_RATIO := 0.08
	const STREET_UNITS := 0.4
	const WIDTH_BY_BAND: Dictionary = {
		"the_guts": 1.0, "the_pit": 0.9, "the_specialists": 0.88, "the_power": 0.8, "the_throne": 0.7,
	}
	const COLUMN_WEIGHTS: Dictionary = {"elevator": 0.8, "stairs": 1.2, "service_stairs": 1.2, "freight": 0.8}
	const COLUMN_ORDER: Array[String] = ["elevator", "stairs", "service_stairs", "freight"]
	const LEDGE_TYPE := "roof_ledge"
	const INK_MAX_LUMINANCE := 0.42

	var view: MapView
	var hover_floor: int = NO_FLOOR
	var _unit: float = 10.0
	var _cx: float = 0.0
	var _tower_w: float = 0.0
	var _ground_y: float = 0.0
	var _x0: float = 0.0
	var _rows: Dictionary = {}
	var _chips: Dictionary = {}
	var _blocks: Dictionary = {}
	var _block_floor: Dictionary = {}
	var _columns: Array[Dictionary] = []
	var _core: Vector2 = Vector2.ZERO
	var _factory: Rect2 = Rect2()
	var _factory_body: Rect2 = Rect2()
	var _assembly: Rect2 = Rect2()
	var _factory_floor: int = 0
	var _roof: int = 0
	var _lowest: int = 0

	func _init() -> void:
		name = "Cut"
		mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Geometría ──

	func floor_rect(floor_number: int) -> Rect2:
		_compute()
		if floor_number == _factory_floor:
			return _factory
		return _rows.get(floor_number, Rect2())

	func block_rect(room_id: String) -> Rect2:
		_compute()
		return _blocks.get(room_id, Rect2())

	func floor_at(pos: Vector2) -> int:
		_compute()
		for f: int in _rows:
			var row: Rect2 = _rows[f]
			var chip: Rect2 = _chips[f]
			if Rect2(chip.position.x, row.position.y, _cx + _tower_w * 0.5 - chip.position.x, row.size.y).has_point(pos):
				return f
		return _factory_floor if _factory.grow(_unit * 0.3).has_point(pos) else NO_FLOOR

	func _tower_floors() -> Array[int]:
		var out: Array[int] = []
		for f: int in view.get_cut_floors():
			if f != _factory_floor:
				out.append(f)
		out.sort()
		out.reverse()
		return out

	func _compute() -> void:
		_factory_floor = Database.get_balance_int(B_FACTORY)
		var floors: Array[int] = _tower_floors()
		if floors.is_empty() or size.x <= 0.0 or size.y <= 0.0:
			return
		_roof = floors[0]
		_lowest = floors[floors.size() - 1]
		_unit = size.y / (float(floors.size()) + TOP_UNITS + EARTH_UNITS)
		var left_w: float = _unit * (BRACKET_UNITS + CHIP_UNITS + GAP_UNITS)
		var avail: float = maxf(size.x - left_w, _unit * 10.0)
		_tower_w = minf(avail * TOWER_SHARE, _unit * TOWER_MAX_UNITS)
		var factory_w: float = minf(avail * FACTORY_SHARE, _unit * FACTORY_MAX_UNITS)
		var gap: float = _unit * GAP_UNITS
		var group_w: float = left_w + _tower_w + factory_w + _unit * ASSEMBLY_UNITS + gap * 2.0
		_x0 = maxf(0.0, (size.x - group_w) * 0.5)
		_cx = _x0 + left_w + _tower_w * 0.5
		_rows.clear()
		_chips.clear()
		for i: int in floors.size():
			var w: float = _tower_w * _band_ratio(floors[i])
			var y: float = _unit * (TOP_UNITS + float(i))
			_rows[floors[i]] = Rect2(_cx - w * 0.5, y, w, _unit)
			_chips[floors[i]] = Rect2(_x0 + _unit * BRACKET_UNITS, y + _unit * 0.1, _unit * CHIP_UNITS, _unit * 0.8)
		_ground_y = (_rows.get(0, _rows[_roof]) as Rect2).end.y
		_compute_annex(factory_w, gap)
		_compute_core()
		_compute_blocks()

	func _compute_annex(factory_w: float, gap: float) -> void:
		var h: float = _unit * FACTORY_H_UNITS
		var pb: Rect2 = _rows.get(0, Rect2(_cx, _ground_y, 0.0, 0.0))
		_factory = Rect2(pb.end.x + gap, _ground_y - h, factory_w, h)
		_factory_body = Rect2(_factory.position.x, _factory.position.y + _unit * FACTORY_ROOF_UNITS, factory_w, h - _unit * FACTORY_ROOF_UNITS)
		_assembly = Rect2(_factory.end.x + gap, _ground_y - _unit * 2.2, _unit * ASSEMBLY_UNITS, _unit * 2.2)

	func _compute_core() -> void:
		_columns = MapView.core_columns()
		var core_w: float = _tower_w * CORE_SHARE
		_core = Vector2(_cx - core_w * 0.5, _cx + core_w * 0.5)
		var total: float = 0.0
		for col: Dictionary in _columns:
			total += float(COLUMN_WEIGHTS.get(col["kind"], 1.0))
		var x: float = _core.x
		for col: Dictionary in _columns:
			var w: float = core_w * float(COLUMN_WEIGHTS.get(col["kind"], 1.0)) / maxf(total, 0.001)
			col["x0"] = x
			col["x1"] = x + w
			x += w

	func _compute_blocks() -> void:
		_blocks.clear()
		_block_floor.clear()
		for f: int in _rows:
			var row: Rect2 = _rows[f]
			var inner: Rect2 = _row_inner(row)
			var ids: Array[String] = view.get_cut_room_ids(f)
			var split: int = _split_index(f, ids, inner)
			_place_segment(f, ids.slice(0, split), inner.position.x, _core.x - _wall())
			_place_segment(f, ids.slice(split), _core.y + _wall(), inner.end.x)
		var body: Rect2 = _factory_body.grow(-_wall())
		_place_segment(_factory_floor, view.get_cut_room_ids(_factory_floor), body.position.x, body.end.x)

	func _row_inner(row: Rect2) -> Rect2:
		var w: float = _wall()
		return Rect2(row.position.x + w * 1.6, row.position.y + w * 0.5, row.size.x - w * 3.2, row.size.y - _slab() - w * 0.5)

	## Reparto izquierda/derecha del núcleo según el ancho de las salas en el plano.
	func _split_index(f: int, ids: Array[String], inner: Rect2) -> int:
		var weights: Array[float] = _weights(f, ids)
		var total: float = 0.0
		for w: float in weights:
			total += w
		var left_share: float = (_core.x - inner.position.x) / maxf(inner.size.x - (_core.y - _core.x), 1.0)
		var acc: float = 0.0
		for i: int in weights.size():
			if acc + weights[i] * 0.5 > total * left_share:
				return i
			acc += weights[i]
		return weights.size()

	func _weights(f: int, ids: Array[String]) -> Array[float]:
		var rooms: Dictionary = MapView.plan_of(f).get("rooms", {})
		var out: Array[float] = []
		for id: String in ids:
			var rect: Rect2i = rooms.get(id, Rect2i(0, 0, 4, 4))
			out.append(maxf(3.0, float(rect.size.x)))
		return out

	func _place_segment(f: int, ids: Array, x0: float, x1: float) -> void:
		if ids.is_empty() or x1 <= x0:
			return
		var typed: Array[String] = []
		for id: Variant in ids:
			typed.append(str(id))
		var weights: Array[float] = _weights(f, typed)
		var total: float = 0.0
		for w: float in weights:
			total += w
		var row: Rect2 = _factory_body.grow(-_wall()) if f == _factory_floor else _row_inner(_rows[f])
		var gap: float = _wall()
		var avail: float = x1 - x0 - gap * float(typed.size() - 1)
		var x: float = x0
		for i: int in typed.size():
			var w: float = avail * weights[i] / maxf(total, 0.001)
			_blocks[typed[i]] = Rect2(x, row.position.y, w, row.size.y)
			_block_floor[typed[i]] = f
			x += w + gap

	func _band_ratio(f: int) -> float:
		return float(WIDTH_BY_BAND.get(UITheme.band_id_for_floor(f), 1.0))

	func _wall() -> float:
		return maxf(1.5, _unit * WALL_RATIO)

	func _slab() -> float:
		return maxf(2.0, _unit * SLAB_RATIO)

	func _layer(layer: String) -> bool:
		return view.is_layer_on(layer)

	# ── Dibujo ──

	func _draw() -> void:
		_compute()
		if _rows.is_empty():
			return
		var pal: Dictionary = MapFloorPlan.palette()
		_draw_ground(pal)
		for f: int in _rows:
			if f == _roof:
				_draw_roof(pal)
			else:
				_draw_row(f, pal)
		_draw_core(pal)
		_draw_cornices(pal)
		_draw_factory(pal)
		_draw_assembly(pal)
		_draw_layers(pal)
		_draw_dots(pal)
		_draw_chips(pal)
		_draw_brackets(pal)
		_draw_hover(pal)
		_draw_player(pal)

	func _draw_ground(pal: Dictionary) -> void:
		var earth: Rect2 = Rect2(0.0, _ground_y, size.x, size.y - _ground_y)
		draw_rect(earth, pal["earth"])
		MapFloorPlan.draw_hatch(self, earth, pal["earth_line"], _unit * 0.32, 1.0, MapFloorPlan.HATCH_SLASH)
		var lowest: Rect2 = _rows[_lowest]
		var pit: Rect2 = Rect2(lowest.position.x - _wall(), _ground_y, lowest.size.x + _wall() * 2.0, lowest.end.y - _ground_y + _wall() * 2.5)
		draw_rect(pit, pal["concrete"])
		var street_h: float = _unit * STREET_UNITS
		draw_rect(Rect2(0.0, _ground_y, pit.position.x, street_h), pal["paper_shade"])
		draw_rect(Rect2(pit.end.x, _ground_y, size.x - pit.end.x, street_h), pal["paper_shade"])
		draw_line(Vector2(0.0, _ground_y), Vector2(size.x, _ground_y), pal["ink"], _wall() * 1.2)
		var path_y: float = _ground_y + street_h * 0.5
		var start: Vector2 = Vector2((_rows[0] as Rect2).end.x, path_y) if _rows.has(0) else Vector2(_cx, path_y)
		var end: Vector2 = Vector2(_assembly.get_center().x, path_y)
		MapFloorPlan.draw_dashed(self, start, end - Vector2(_unit * 0.5, 0.0), pal["green"], maxf(2.0, _unit * 0.1), _unit * 0.3)
		MapFloorPlan.draw_arrow(self, end - Vector2(_unit * 0.9, 0.0), end, pal["green"], maxf(2.0, _unit * 0.1), _unit * 0.4)

	func _draw_row(f: int, pal: Dictionary) -> void:
		var row: Rect2 = _rows[f]
		var band: Dictionary = UITheme.band_palette_for_floor(f)
		draw_rect(row, pal["ink"])
		var glass_w: float = maxf(2.0, _unit * 0.14)
		var glass: Color = Color(str(band.get("window", "#a8d2f4")))
		var inner_h: float = row.size.y - _slab() - _wall()
		if f >= 0:
			draw_rect(Rect2(row.position.x + _wall() * 0.6, row.position.y + _wall() * 0.5, glass_w, inner_h), glass)
			draw_rect(Rect2(row.end.x - _wall() * 0.6 - glass_w, row.position.y + _wall() * 0.5, glass_w, inner_h), glass)
		var slab: Rect2 = Rect2(row.position.x + _wall(), row.end.y - _slab() + _wall() * 0.35, row.size.x - _wall() * 2.0, _slab() - _wall() * 0.7)
		draw_rect(slab, Color(str(band.get("floor", "#8a8f7d"))))
		_draw_blocks(f, pal)

	func _draw_blocks(f: int, pal: Dictionary) -> void:
		var spacing: float = maxf(4.0, _unit * 0.2)
		for id: String in view.get_cut_room_ids(f):
			if not _blocks.has(id):
				continue
			var r: Rect2 = _blocks[id]
			MapFloorPlan.draw_status_block(self, r, view.get_room_status(id), pal, spacing, maxf(1.0, _unit * 0.04))

	func _draw_roof(pal: Dictionary) -> void:
		var row: Rect2 = _rows[_roof]
		var band: Dictionary = UITheme.band_palette_for_floor(_roof)
		var slab: Rect2 = Rect2(row.position.x, row.end.y - _slab(), row.size.x, _slab())
		draw_rect(slab, pal["ink"])
		draw_rect(slab.grow(-_wall() * 0.4), Color(str(band.get("floor", "#e8e5de"))))
		var para_h: float = _unit * 0.34
		draw_rect(Rect2(row.position.x, row.end.y - _slab() - para_h, _wall() * 1.2, para_h), pal["ink"])
		draw_rect(Rect2(row.end.x - _wall() * 1.2, row.end.y - _slab() - para_h, _wall() * 1.2, para_h), pal["ink"])
		for id: String in view.get_cut_room_ids(_roof):
			if not _blocks.has(id):
				continue
			var r: Rect2 = _blocks[id]
			var room: RoomData = Database.get_room(id)
			var open_air: bool = room != null and not room.illegitimate_entries.has(MapView.ENTRY_VENT) and r.size.x > _unit * 3.0
			if open_air:
				_draw_terrace(r, view.get_room_status(id), pal)
			else:
				draw_rect(r.grow(_wall() * 0.6), pal["ink"])
				MapFloorPlan.draw_status_block(self, r, view.get_room_status(id), pal, maxf(4.0, _unit * 0.2), 1.0)
		_draw_mast(pal)

	func _draw_terrace(r: Rect2, status: int, pal: Dictionary) -> void:
		var deck: Rect2 = Rect2(r.position.x, r.end.y - r.size.y * 0.42, r.size.x, r.size.y * 0.42)
		MapFloorPlan.draw_status_block(self, deck, status, pal, maxf(4.0, _unit * 0.2), 1.0)
		draw_rect(deck, MapFloorPlan.status_ink(status, pal), false, 1.5)
		var rail_y: float = r.end.y - r.size.y * 0.72
		draw_line(Vector2(r.position.x, rail_y), Vector2(r.end.x, rail_y), pal["ink_soft"], 1.5)
		var post: float = r.position.x
		while post <= r.end.x:
			draw_line(Vector2(post, rail_y), Vector2(post, deck.position.y), pal["ink_soft"], 1.0)
			post += _unit * 0.35
		var pad_c: Vector2 = Vector2(r.position.x + r.size.x * 0.5, deck.position.y - _unit * 0.06)
		draw_colored_polygon(UITheme.ellipse_points(pad_c, _unit * 0.9, _unit * 0.14, 18), Color(pal["ink"], 0.75))
		MapFloorPlan.draw_centered(self, UITheme.font(UITheme.FONT_BOLD), pad_c + Vector2(0.0, -_unit * 0.02), "H", roundi(_unit * 0.24), pal["white"])

	func _draw_mast(pal: Dictionary) -> void:
		var row: Rect2 = _rows[_roof]
		var base_y: float = row.position.y + _unit * 0.1
		var top_y: float = base_y - _unit * (TOP_UNITS - 0.35)
		var x: float = _core.y - (_core.y - _core.x) * 0.25
		draw_line(Vector2(x, base_y), Vector2(x, top_y), pal["ink"], maxf(2.0, _unit * 0.08))
		for i: int in 3:
			var y: float = lerpf(base_y, top_y, 0.25 + 0.22 * float(i))
			draw_line(Vector2(x - _unit * (0.28 - 0.06 * i), y), Vector2(x + _unit * (0.28 - 0.06 * i), y), pal["ink"], 1.5)
		draw_circle(Vector2(x, top_y), _unit * 0.12, pal["red"])
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(9, roundi(_unit * 0.36))
		var text: String = tr("UI_COMPANY_NAME")
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _unit * 0.9
		var sign_rect: Rect2 = Rect2(_core.x - tw * 0.55, base_y - _unit * 0.95, tw, _unit * 0.6)
		draw_line(Vector2(sign_rect.get_center().x, sign_rect.end.y), Vector2(sign_rect.get_center().x, base_y), pal["ink"], 2.0)
		draw_rect(sign_rect, pal["ink"])
		UITheme.draw_icon(self, "star", Rect2(sign_rect.position + Vector2(_unit * 0.12, _unit * 0.1), Vector2(_unit * 0.4, _unit * 0.4)), pal["amber"], 1.5)
		draw_string(font, Vector2(sign_rect.position.x + _unit * 0.6, sign_rect.get_center().y + font.get_ascent(fs) * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["white"])

	## Núcleo: huecos de ascensor (con cabinas), tramos de escalera con flechas de evacuación y
	## hormigón donde el hueco no llega.
	func _draw_core(pal: Dictionary) -> void:
		for col: Dictionary in _columns:
			for f: int in _rows:
				var row: Rect2 = _rows[f]
				var cell: Rect2 = Rect2(float(col["x0"]), row.position.y + _wall() * 0.5, float(col["x1"]) - float(col["x0"]), row.size.y - _slab() - _wall() * 0.5)
				if f >= int(col["lo"]) and f <= int(col["hi"]):
					_draw_shaft_cell(col, f, cell.grow_individual(-_wall() * 0.35, 0.0, -_wall() * 0.35, 0.0), pal)
				elif f != _roof or str(col["kind"]) != "elevator":
					draw_rect(cell, pal["ink"])
			_draw_cabins(col, pal)

	func _draw_shaft_cell(col: Dictionary, f: int, cell: Rect2, pal: Dictionary) -> void:
		var kind: String = str(col["kind"])
		draw_rect(cell, pal["paper_shade"] if kind == "elevator" or kind == "freight" else pal["white"])
		if kind == "elevator" or kind == "freight":
			var rail: float = cell.size.x * 0.18
			draw_line(Vector2(cell.position.x + rail, cell.position.y), Vector2(cell.position.x + rail, cell.end.y), pal["ink_faint"], 1.0)
			draw_line(Vector2(cell.end.x - rail, cell.position.y), Vector2(cell.end.x - rail, cell.end.y), pal["ink_faint"], 1.0)
			return
		var inset: float = cell.size.x * 0.1
		draw_line(Vector2(cell.position.x + inset, cell.end.y), Vector2(cell.end.x - inset, cell.position.y + cell.size.y * 0.25), pal["ink_soft"], maxf(1.2, _unit * 0.05))
		var up: bool = f < 0
		var c: Vector2 = cell.get_center() + Vector2(cell.size.x * 0.18, cell.size.y * 0.1)
		var d: float = minf(cell.size.x, cell.size.y) * 0.22
		var tri: PackedVector2Array = PackedVector2Array([c + Vector2(0.0, -d if up else d), c + Vector2(-d, d * 0.2 if up else -d * 0.2), c + Vector2(d, d * 0.2 if up else -d * 0.2)])
		draw_colored_polygon(tri, pal["green"])

	func _draw_cabins(col: Dictionary, pal: Dictionary) -> void:
		if str(col["kind"]) != "elevator" and str(col["kind"]) != "freight":
			return
		var lo: int = int(col["lo"])
		var hi: int = int(col["hi"])
		var at: int = clampi(int(view.get_player_floor()) if col["index"] == 0 else 0, lo, hi)
		var top_row: Rect2 = _rows.get(hi, Rect2())
		var row: Rect2 = _rows.get(at, Rect2())
		if row.size.y <= 0.0:
			return
		var x0: float = float(col["x0"]) + _wall() * 0.6
		var x1: float = float(col["x1"]) - _wall() * 0.6
		var cabin: Rect2 = Rect2(x0, row.position.y + _unit * 0.18, x1 - x0, row.size.y - _slab() - _unit * 0.22)
		var mid: float = (x0 + x1) * 0.5
		draw_line(Vector2(mid, top_row.position.y), Vector2(mid, cabin.position.y), pal["ink_soft"], 1.0)
		draw_rect(cabin, pal["concrete"])
		draw_rect(cabin, pal["ink"], false, 1.5)
		draw_line(Vector2(mid, cabin.position.y + 2.0), Vector2(mid, cabin.end.y - 1.0), pal["ink_soft"], 1.0)

	## Cornisa con el acento de la banda en la última planta de cada banda (retranqueos visibles).
	func _draw_cornices(pal: Dictionary) -> void:
		var h: float = maxf(2.0, _unit * 0.1)
		for f: int in _rows:
			if f == _roof or f < 0:
				continue
			var above: int = f + 1
			if _rows.has(above) and UITheme.band_id_for_floor(above) == UITheme.band_id_for_floor(f):
				continue
			var row: Rect2 = _rows[f]
			var accent: Color = Color(str(UITheme.band_palette_for_floor(f).get("accent", "#888888")))
			draw_rect(Rect2(row.position.x - h, row.position.y - h * 0.5, row.size.x + h * 2.0, h), accent)
			draw_rect(Rect2(row.position.x - h, row.position.y - h * 0.5, row.size.x + h * 2.0, h), pal["ink"], false, 1.0)

	func _draw_factory(pal: Dictionary) -> void:
		var band: Dictionary = UITheme.band_palette_for_floor(_factory_floor)
		var accent: Color = Color(str(band.get("accent", "#f28c1c")))
		var wall: Color = Color(str(band.get("wall", "#8a8378")))
		var chimney: Rect2 = Rect2(_factory.end.x - _unit * 1.1, _factory.position.y - _unit * 1.3, _unit * 0.45, _unit * 1.6)
		for i: int in 3:
			draw_circle(chimney.position + Vector2(_unit * (0.3 + 0.35 * i), -_unit * (0.25 + 0.3 * i)), _unit * (0.18 + 0.07 * i), Color(pal["ink_faint"], 0.5))
		draw_rect(chimney, wall)
		draw_rect(Rect2(chimney.position.x, chimney.position.y + _unit * 0.2, chimney.size.x, _unit * 0.14), accent)
		draw_rect(chimney, pal["ink"], false, 1.5)
		_draw_sawtooth(wall, Color(str(band.get("window", "#98a1a6"))), pal)
		draw_rect(_factory_body, pal["ink"])
		draw_rect(Rect2(_factory_body.position.x, _factory_body.position.y, _factory_body.size.x, _unit * 0.12), accent)
		var slab: Rect2 = Rect2(_factory_body.position.x + _wall(), _factory_body.end.y - _slab(), _factory_body.size.x - _wall() * 2.0, _slab() - _wall() * 0.5)
		draw_rect(slab, Color(str(band.get("floor", "#5a5650"))))
		_draw_blocks(_factory_floor, pal)
		var chip: Rect2 = Rect2(_factory.position.x, _factory.position.y - _unit * 1.05, _unit * CHIP_UNITS * 1.25, _unit * 0.8)
		draw_chip(self, chip, view.get_floor_status(_factory_floor), MapView.floor_label_short(_factory_floor), UITheme.font(UITheme.FONT_BOLD), _chip_font(), pal)
		if hover_floor == _factory_floor:
			draw_rect(_factory.grow(_wall() * 1.5), pal["ink"], false, _wall() * 1.4)

	func _draw_sawtooth(wall: Color, glass: Color, pal: Dictionary) -> void:
		var teeth: int = maxi(3, int(_factory.size.x / (_unit * 1.4)))
		var tw: float = _factory.size.x / float(teeth)
		var base_y: float = _factory_body.position.y
		var top_y: float = _factory.position.y
		for i: int in teeth:
			var x: float = _factory.position.x + tw * float(i)
			var tooth: PackedVector2Array = PackedVector2Array([Vector2(x, base_y), Vector2(x + tw * 0.78, top_y), Vector2(x + tw * 0.78, base_y)])
			draw_colored_polygon(tooth, wall)
			draw_rect(Rect2(x + tw * 0.78, top_y, tw * 0.22, base_y - top_y), glass)
			tooth.append(tooth[0])
			draw_polyline(tooth, pal["ink"], 1.5, true)

	func _draw_assembly(pal: Dictionary) -> void:
		var s: float = minf(_assembly.size.x * 0.62, _unit * 1.5)
		var sign_rect: Rect2 = Rect2(_assembly.get_center().x - s * 0.5, _assembly.position.y, s, s)
		draw_line(Vector2(sign_rect.get_center().x, sign_rect.end.y), Vector2(sign_rect.get_center().x, _ground_y), pal["ink_soft"], maxf(2.0, _unit * 0.08))
		draw_polygon(UITheme.rounded_rect_points(sign_rect, s * 0.1), PackedColorArray([pal["green"]]))
		for i: int in 3:
			MapFloorPlan.draw_person(self, sign_rect.position + Vector2(s * (0.28 + 0.22 * i), s * 0.62), s * 0.3, pal["white"])
		for corner: Vector2 in [Vector2(0.14, 0.14), Vector2(0.86, 0.14)]:
			var c: Vector2 = sign_rect.position + corner * s
			MapFloorPlan.draw_arrow(self, c, c + (Vector2(0.5, 0.36) * s - corner * s) * 0.35, pal["white"], s * 0.05, s * 0.12)
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(9, roundi(_unit * 0.3))
		var label: String = tr("MAP_ASSEMBLY_POINT")
		var lines: PackedStringArray = MapFloorPlan._wrap(label, font, fs, _assembly.size.x * 1.25)
		if lines.is_empty():
			lines = PackedStringArray([label])
		for i: int in lines.size():
			MapFloorPlan.draw_centered(self, font, Vector2(_assembly.get_center().x, sign_rect.position.y - _unit * 0.3 - float(lines.size() - 1 - i) * fs * 1.1), lines[i], fs, pal["green_dark"])

	# ── Capas ──

	func _draw_layers(pal: Dictionary) -> void:
		if _layer(LAYER_OCCUPANCY):
			_draw_occupancy(pal)
		if _layer(LAYER_ROUTES):
			_draw_routes(pal)
		if _layer(LAYER_CAMERAS):
			_draw_cameras(pal)

	func _draw_cameras(pal: Dictionary) -> void:
		var s: float = _unit * 0.5
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			if room == null or not room.has_cameras:
				continue
			var r: Rect2 = _blocks[id]
			var size_px: float = minf(s, r.size.x * 0.8)
			var at: Vector2 = Vector2(r.end.x - size_px * 0.62, r.position.y + size_px * 0.62)
			_camera_glyph(at, size_px, pal)
		for f: int in _rows:
			if _corridor_has_cameras(f):
				_camera_glyph(Vector2(_core.x - s * 0.75, (_rows[f] as Rect2).position.y + s * 0.62), s, pal)

	func _camera_glyph(at: Vector2, s: float, pal: Dictionary) -> void:
		draw_circle(at, s * 0.5, pal["white"])
		draw_arc(at, s * 0.5, 0.0, TAU, 16, pal["red"], 1.5, true)
		UITheme.draw_icon(self, "camera", Rect2(at - Vector2(s, s) * 0.36, Vector2(s, s) * 0.72), pal["camera"], maxf(1.2, s * 0.09))

	func _corridor_has_cameras(f: int) -> bool:
		for room: RoomData in FloorLayout.rooms_on_floor(f):
			if bool(room.extra.get(MapFloorPlan.KEY_FULL_WIDTH, false)) and room.has_cameras:
				return true
		return false

	func _draw_routes(pal: Dictionary) -> void:
		for col: Dictionary in _columns:
			if str(col["kind"]) == "service_stairs" or str(col["kind"]) == "freight":
				_route_column(col, pal)
		_draw_vents(pal)
		_draw_freight_link(pal)
		_draw_ledges(pal)
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			if room != null and room.illegitimate_entries.has(MapView.ENTRY_OLD_KEYS):
				var r: Rect2 = _blocks[id]
				var s: float = minf(_unit * 0.48, r.size.x * 0.8)
				var at: Vector2 = Vector2(r.position.x + s * 0.62, r.position.y + s * 0.62)
				draw_circle(at, s * 0.5, pal["amber"])
				UITheme.draw_icon(self, "key", Rect2(at - Vector2(s, s) * 0.34, Vector2(s, s) * 0.68), pal["ink"], maxf(1.2, s * 0.09))

	func _route_column(col: Dictionary, pal: Dictionary) -> void:
		var top: Rect2 = _rows.get(int(col["hi"]), Rect2())
		var bottom: Rect2 = _rows.get(int(col["lo"]), Rect2())
		if top.size.y <= 0.0 or bottom.size.y <= 0.0:
			return
		var r: Rect2 = Rect2(float(col["x0"]), top.position.y, float(col["x1"]) - float(col["x0"]), bottom.end.y - top.position.y)
		draw_rect(r, Color(pal["amber"], 0.28))
		var w: float = maxf(2.0, _unit * 0.08)
		for x: float in [r.position.x + w * 0.5, r.end.x - w * 0.5]:
			MapFloorPlan.draw_dashed(self, Vector2(x, r.position.y), Vector2(x, r.end.y), pal["amber_dark"], w, _unit * 0.22)
		if str(col["kind"]) == "service_stairs":
			var s: float = r.size.x * 0.9
			var at: Vector2 = Vector2(r.get_center().x, top.position.y - s * 0.7)
			draw_circle(at, s * 0.55, pal["white"])
			UITheme.draw_icon(self, "hide", Rect2(at - Vector2(s, s) * 0.4, Vector2(s, s) * 0.8), pal["amber_dark"], maxf(1.2, s * 0.09))

	## Montante de conductos junto al núcleo y ramales por el techo hasta cada sala con trampilla.
	func _draw_vents(pal: Dictionary) -> void:
		var net: RoomData = Database.get_room(MapView.VENT_NETWORK_ID)
		if net == null or not net.is_transversal():
			return
		var x: float = _core.x - _unit * 0.3
		var top: Rect2 = _rows.get(net.floors[1], Rect2())
		var bottom: Rect2 = _rows.get(net.floors[0], Rect2())
		var w: float = maxf(2.0, _unit * 0.1)
		MapFloorPlan.draw_dashed(self, Vector2(x, top.position.y + _unit * 0.16), Vector2(x, bottom.end.y - _slab()), pal["amber"], w * 1.6, _unit * 0.25)
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			var f: int = int(_block_floor[id])
			if room == null or f == _factory_floor or MapView.vent_targets(room).is_empty():
				continue
			var r: Rect2 = _blocks[id]
			var y: float = (_rows[f] as Rect2).position.y + _unit * 0.16
			MapFloorPlan.draw_dashed(self, Vector2(x, y), Vector2(r.get_center().x, y), pal["amber"], w, _unit * 0.18)
			var s: float = minf(_unit * 0.34, r.size.x * 0.6)
			MapFloorPlan.draw_vent(self, Rect2(Vector2(r.get_center().x - s * 0.5, y - s * 0.3), Vector2(s, s * 0.6)), pal["amber_dark"], 1.2)

	func _draw_freight_link(pal: Dictionary) -> void:
		for col: Dictionary in _columns:
			if str(col["kind"]) != "freight" or not _rows.has(0):
				continue
			var y: float = (_rows[0] as Rect2).end.y - _slab() - _unit * 0.22
			var a: Vector2 = Vector2(float(col["x1"]), y)
			var b: Vector2 = Vector2(_factory_body.position.x + _unit * 0.6, y)
			MapFloorPlan.draw_dashed(self, a, b, pal["amber_dark"], maxf(2.0, _unit * 0.1), _unit * 0.2)
			MapFloorPlan.draw_arrow(self, b - Vector2(_unit * 0.6, 0.0), b, pal["amber_dark"], maxf(2.0, _unit * 0.1), _unit * 0.35)

	## Cornisas: recorrido de puntos por fuera de la fachada entre las salas con salida a cornisa.
	func _draw_ledges(pal: Dictionary) -> void:
		var points: Array[Vector2] = []
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			if room == null or not (room.illegitimate_entries.has(MapView.ENTRY_ROOF_LEDGE) or _has_ledge(room)):
				continue
			var r: Rect2 = _blocks[id]
			var row: Rect2 = _rows.get(int(_block_floor[id]), r)
			points.append(Vector2(row.end.x + _unit * 0.35, r.get_center().y))
			MapFloorPlan.draw_dashed(self, Vector2(r.end.x, r.get_center().y), points.back(), pal["amber"], maxf(2.0, _unit * 0.08), _unit * 0.12)
		points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
		for i: int in range(1, points.size()):
			MapFloorPlan.draw_dashed(self, points[i - 1], points[i], pal["amber"], maxf(2.0, _unit * 0.1), _unit * 0.12)
		for p: Vector2 in points:
			draw_circle(p, _unit * 0.1, pal["amber_dark"])

	static func _has_ledge(room: RoomData) -> bool:
		for entry: Dictionary in room.interactables:
			if str(entry.get("type", "")) == LEDGE_TYPE:
				return true
		return false

	func _draw_occupancy(pal: Dictionary) -> void:
		var band: String = view.get_band()
		var cap: int = maxi(1, Database.get_balance_int("mapa.ocupacion_marcas_max"))
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			var count: int = room.get_occupants(band) if room != null else 0
			if count <= 0:
				continue
			var r: Rect2 = _blocks[id]
			var s: float = _unit * 0.3
			var fit: int = maxi(1, int((r.size.x - s * 0.4) / (s * 0.78)))
			var shown: int = mini(mini(count, cap), fit)
			for i: int in shown:
				MapFloorPlan.draw_person(self, Vector2(r.position.x + s * (0.55 + 0.78 * i), r.end.y - s * 0.55), s, pal["people"])
			if count > shown and r.size.x > s * 2.0:
				var fs: int = maxi(8, roundi(_unit * 0.3))
				var label: String = str(count)
				var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var at: Vector2 = Vector2(r.end.x - tw - s * 0.2, r.position.y + font.get_ascent(fs) + s * 0.1)
				draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, pal["white"])
				draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["people"])

	# ── Personas, chapas, bandas, selección ──

	func _draw_dots(pal: Dictionary) -> void:
		var radius: float = maxf(3.0, _unit * 0.13)
		for dot: Dictionary in view.get_visible_dots():
			var at: Vector2 = dot_point(str(dot.get("room_id", "")), int(dot.get("floor", NO_FLOOR)), str(dot.get("npc_id", "")))
			if at.is_finite():
				MapFloorPlan.draw_npc_dot(self, at, radius, pal, bool(dot.get("target", false)), bool(dot.get("approximate", false)))

	## Punto de una persona en el corte: dentro del bloque de su sala o, en circulación, en su fila.
	func dot_point(room_id: String, f: int, key: String) -> Vector2:
		if _blocks.has(room_id):
			var r: Rect2 = _blocks[room_id]
			var p: Vector2 = MapFloorPlan.dot_position(r, key)
			return Vector2(p.x, r.end.y - r.size.y * (0.3 + 0.25 * fposmod(p.y, 1.0)))
		if not _rows.has(f):
			return Vector2.INF
		var row: Rect2 = _row_inner(_rows[f])
		var span: Rect2 = Rect2(row.position.x, row.position.y, _core.x - row.position.x, row.size.y)
		return Vector2(MapFloorPlan.dot_position(span, key).x, row.end.y - row.size.y * 0.3)

	func _chip_font() -> int:
		return maxi(9, roundi(minf(_unit * 0.5, float(view.base_font()))))

	func _draw_chips(pal: Dictionary) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		for f: int in _chips:
			draw_chip(self, _chips[f], view.get_floor_status(f), MapView.floor_label_short(f), font, _chip_font(), pal)

	## Chapa de planta: color de estado, número y glifo de forma (✓ / ! / ✕), accesible sin color.
	static func draw_chip(ci: CanvasItem, r: Rect2, status: int, text: String, font: Font, fs: int, pal: Dictionary) -> void:
		ci.draw_polygon(UITheme.rounded_rect_points(r, r.size.y * 0.22), PackedColorArray([MapFloorPlan.status_ink(status, pal)]))
		var g: float = r.size.y * 0.52
		var glyph: Rect2 = Rect2(Vector2(r.end.x - g - r.size.y * 0.2, r.get_center().y - g * 0.5), Vector2(g, g))
		if text.is_empty():
			glyph.position.x = r.get_center().x - g * 0.5
		draw_status_glyph(ci, glyph, status, pal["white"])
		if font != null and not text.is_empty():
			var at: Vector2 = Vector2(r.position.x + r.size.y * 0.3, r.get_center().y + font.get_ascent(fs) * 0.36)
			ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, glyph.position.x - at.x, fs, pal["white"])

	static func draw_status_glyph(ci: CanvasItem, r: Rect2, status: int, col: Color) -> void:
		var w: float = maxf(1.5, r.size.y * 0.16)
		match status:
			MapFloorPlan.ACCESS_ALLOWED:
				ci.draw_polyline(PackedVector2Array([MapFloorPlan._u(r, 0.1, 0.52), MapFloorPlan._u(r, 0.4, 0.8), MapFloorPlan._u(r, 0.92, 0.2)]), col, w, true)
			MapFloorPlan.ACCESS_ALTERNATIVE:
				ci.draw_line(MapFloorPlan._u(r, 0.5, 0.08), MapFloorPlan._u(r, 0.5, 0.62), col, w * 1.1, true)
				ci.draw_circle(MapFloorPlan._u(r, 0.5, 0.86), w * 0.7, col)
			_:
				ci.draw_line(MapFloorPlan._u(r, 0.14, 0.14), MapFloorPlan._u(r, 0.86, 0.86), col, w, true)
				ci.draw_line(MapFloorPlan._u(r, 0.86, 0.14), MapFloorPlan._u(r, 0.14, 0.86), col, w, true)

	## Glifo de capa para los conmutadores (cámara, conducto, personas).
	static func draw_layer_glyph(ci: CanvasItem, icon: String, r: Rect2, col: Color, _pal: Dictionary) -> void:
		match icon:
			"vent":
				MapFloorPlan.draw_vent(ci, r.grow(-r.size.y * 0.12), col, maxf(1.5, r.size.y * 0.09))
			"people":
				MapFloorPlan.draw_person(ci, MapFloorPlan._u(r, 0.32, 0.55), r.size.y * 0.7, col)
				MapFloorPlan.draw_person(ci, MapFloorPlan._u(r, 0.72, 0.6), r.size.y * 0.6, col)
			_:
				UITheme.draw_icon(ci, icon, r, col, maxf(1.5, r.size.y * 0.09))

	## Acento de banda oscurecido para leerse sobre el papel del plano.
	static func band_ink(f: int) -> Color:
		var pal: Dictionary = UITheme.band_palette_for_floor(f)
		var c: Color = Color(str(pal.get("accent", "#555555")))
		while c.get_luminance() > INK_MAX_LUMINANCE:
			c = c.darkened(0.12)
		return c

	func _draw_brackets(pal: Dictionary) -> void:
		var spans: Dictionary = {}
		for f: int in _rows:
			var band: String = UITheme.band_id_for_floor(f)
			var r: Rect2 = _rows[f]
			var span: Vector2 = spans.get(band, Vector2(r.position.y, r.end.y))
			spans[band] = Vector2(minf(span.x, r.position.y), maxf(span.y, r.end.y))
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(8, roundi(minf(_unit * 0.36, float(view.base_font()) * 0.7)))
		var x: float = _x0 + _unit * BRACKET_UNITS * 0.78
		for band_id: String in spans:
			var span: Vector2 = spans[band_id]
			var band: Dictionary = Database.get_art_band(band_id)
			var col: Color = band_ink(int((band.get("floors", [0]) as Array)[0]))
			var tick: float = _unit * 0.22
			draw_polyline(PackedVector2Array([Vector2(x + tick, span.x + 3.0), Vector2(x, span.x + 3.0), Vector2(x, span.y - 3.0), Vector2(x + tick, span.y - 3.0)]), col, maxf(2.0, _unit * 0.08))
			_draw_vertical_text(tr(str(band.get("name_key", ""))).to_upper(), Vector2(x - _unit * 0.28, (span.x + span.y) * 0.5), span.y - span.x, font, fs, col)

	func _draw_vertical_text(text: String, center: Vector2, max_len: float, font: Font, fs: int, col: Color) -> void:
		var size_fs: int = fs
		while size_fs > 7 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs).x > max_len - 6.0:
			size_fs -= 1
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs).x
		if tw > max_len:
			return
		draw_set_transform(center, -PI * 0.5, Vector2.ONE)
		draw_string(font, Vector2(-tw * 0.5, font.get_ascent(size_fs) * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_hover(pal: Dictionary) -> void:
		if not _rows.has(hover_floor):
			return
		var row: Rect2 = _rows[hover_floor]
		var chip: Rect2 = _chips[hover_floor]
		draw_rect(row.grow(_wall() * 1.2), pal["amber"], false, _wall() * 1.6)
		draw_rect(chip.grow(2.0), pal["ink"], false, 2.5)
		var tip: Vector2 = Vector2(chip.position.x - _unit * 0.12, chip.get_center().y)
		var tri: PackedVector2Array = PackedVector2Array([tip, tip + Vector2(-_unit * 0.32, -_unit * 0.22), tip + Vector2(-_unit * 0.32, _unit * 0.22)])
		draw_colored_polygon(tri, pal["ink"])

	func _draw_player(pal: Dictionary) -> void:
		var f: int = view.get_player_floor()
		var at: Vector2 = dot_point(view.get_player_room(), f, "player")
		if not at.is_finite():
			return
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(9, roundi(minf(_unit * 0.46, float(view.base_font()) * 0.8)))
		var text: String = tr("MAP_YOU_ARE_HERE")
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * 1.1
		var box: Rect2 = Rect2(Vector2(_cx + _tower_w * 0.5 + _unit * 0.5, at.y - _unit * 1.1), Vector2(tw, fs * 1.6))
		if box.intersects(_factory.grow(_unit * 0.3)):
			box.position.y = _factory.position.y - _unit * 1.3 - box.size.y
		MapFloorPlan.draw_callout(self, at, box.position, text, font, fs, pal)
		MapFloorPlan.draw_pin(self, at, maxf(4.0, _unit * 0.22), pal)

	# ── Entrada ──

	func _gui_input(event: InputEvent) -> void:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			_set_hover(floor_at(motion.position))
			return
		if UITheme.is_primary_press(event):
			var pos: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton \
					else (event as InputEventScreenTouch).position
			var f: int = floor_at(pos)
			if f != NO_FLOOR:
				_set_hover(f)
				floor_clicked.emit(f)
				accept_event()

	func _set_hover(f: int) -> void:
		if f == hover_floor or f == NO_FLOOR:
			return
		hover_floor = f
		floor_hovered.emit(f)
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
			queue_redraw()
