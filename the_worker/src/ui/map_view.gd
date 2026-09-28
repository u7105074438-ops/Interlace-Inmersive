# map_view.gd — Mapa (Tab): corte vertical de toda la torre como plano de evacuación y zoom a planta (§13.6, PASO 36).
# PROPIETARIO DE: el estado de la ventana del mapa (capas, franja de ocupación, planta señalada y ampliada), la memoria de capas entre aperturas y las cachés estáticas de planos, núcleo, bandas y cornisas.
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
##    maestras (≤ mapa.llaves_maestras_nivel_max), llave de sala (mapa.llaves_sala), tarjeta ajena
##    (nivel de extra.clearance o mapa.tarjetas), llaves antiguas (entrada old_keys), herramienta de
##    forzar (forced_lock), conducto (trampilla hacia una sala verde, o red de conductos utilizable),
##    cornisa (desde una sala verde con salida a cornisa). ROJO en otro caso.
##  · Acceso por planta = el mejor estado entre sus salas propias (sin pasillos, ascensores ni
##    escaleras, que son de nivel 1 en todas las plantas). Los cuartos de servicio compartidos
##    (copias transversales: limpieza) solo dan un punto de apoyo: como mucho ámbar, y la chapa lo
##    marca aparte (roja con «!» ámbar: is_floor_foothold).
##  · Puntos: personajes vivos que el jugador conoce (nominados, marcados o NPCDirector.knows_player)
##    con rutina desbloqueada: PersonnelApp.effective_level(id) (puesto, puesto de RRHH, intrusión
##    en RRHH, chantaje) ≥ PersonnelApp.section_level("routine") (expedientes.nivel_seccion) → sala
##    actual. Un objetivo marcado sin rutina desbloqueada se muestra aproximado en su puesto (N1).
##    Los objetivos se dibujan los últimos con mira y etiqueta de nombre y se listan en el panel.
##  · El corte no baja de MIN_ROW_RATIO × letra por planta: si no cabe (móvil, texto grande) el lienzo
##    es más alto que su recorte y desplazarlo solo lo mueve (sin redibujar). Señalar con el ratón
##    no desplaza; el teclado y select_floor() desde código sí centran la planta.
##  · Planos: FloorStreamer.get_plan_for() si hay mundo (caché compartida) o FloorLayout.compute();
##    prewarm_plans() los calcula por adelantado (pantallas de carga).
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
const LAYER_SHORT_KEYS: Dictionary = {
	LAYER_CAMERAS: "MAP_LAYER_CAMERAS", LAYER_ROUTES: "MAP_LAYER_ROUTES_SHORT", LAYER_OCCUPANCY: "MAP_LAYER_OCCUPANCY",
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
const METHOD_ROOM_KEY := "room_key"
const METHOD_CARD := "card"
const METHOD_OLD_KEYS := "old_keys"
const METHOD_FORCED_LOCK := "forced_lock"
const METHOD_VENT := "vent"
const METHOD_ROOF_LEDGE := "roof_ledge"
const ALT_ORDER: Array[String] = [
	METHOD_UNIFORM, METHOD_MASTER_KEYS, METHOD_ROOM_KEY, METHOD_CARD, METHOD_OLD_KEYS, METHOD_FORCED_LOCK,
	METHOD_VENT, METHOD_ROOF_LEDGE,
]
const METHOD_KEYS: Dictionary = {
	METHOD_UNIFORM: "MAP_METHOD_UNIFORM", METHOD_MASTER_KEYS: "MAP_METHOD_MASTER_KEYS",
	METHOD_ROOM_KEY: "MAP_METHOD_ROOM_KEY", METHOD_CARD: "MAP_METHOD_CARD", METHOD_OLD_KEYS: "MAP_METHOD_OLD_KEYS",
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

const B_UNIFORMS := "mapa.uniformes"
const B_MASTER_KEYS := "mapa.llaves_maestras"
const B_MASTER_MAX := "mapa.llaves_maestras_nivel_max"
const B_ROOM_KEYS := "mapa.llaves_sala"
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
const HEADER_COMPACT_RATIO := 2.3
const COMPACT_ROWS := 34.0
const FOOTER_RATIO := 1.45
const PAD_RATIO := 0.7
const SIDE_SHARE := 0.3
const SIDE_MIN_RATIO := 13.0
const SIDE_MAX_SHARE := 0.4
const MAX_ROOM_ROWS := 16
const FADE_RATIO := 1.6
const HEADER_LINES := 2

static var _layer_memory: Dictionary = {}
static var _plan_cache: Dictionary = {}
static var _ledge_sources: Dictionary = {}
static var _ledges_indexed: bool = false
static var _columns_cache: Array[Dictionary] = []
static var _band_order: Array[String] = []

var _context: Dictionary = {}
var _layers: Dictionary = {}
var _band: String = ""
var _zoom_floor: int = NO_FLOOR
var _selected_floor: int = NO_FLOOR
var _selected_room: String = ""
var _model: Dictionary = {}
var _rects: Dictionary = {}
var _cut_clip: Control
var _cut: CutCanvas
var _cut_overlay: CutOverlay
var _plan_view: MapFloorPlan
var _title: Label
var _subtitle: Label
var _footer_left: Label
var _footer_right: Label
var _layer_bar: HBoxContainer
var _side_scroll: ScrollContainer
var _side: VBoxContainer
var _side_fade: SideFade
var _sized: Dictionary = {}
var _badge: Label
var _occ_label: Label
var _disguise_label: Label
var _toggles: Dictionary = {}
var _band_row: HBoxContainer
var _band_label: Label
var _floor_box: VBoxContainer
var _floor_title: Label
var _floor_band: Label
var _floor_status: Swatch
var _floor_status_label: Label
var _floor_status_desc: Label
var _floor_people: Label
var _room_list: VBoxContainer
var _targets_box: VBoxContainer
var _target_list: VBoxContainer
var _hint: Label
var _nav_row: HBoxContainer
var _listed: Array[String] = []
var _listed_targets: Array[String] = []
var _connected: bool = false
var _refresh_queued: bool = false
var _refresh_count: int = 0


func _init() -> void:
	name = "MapView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layers = {LAYER_CAMERAS: false, LAYER_ROUTES: false, LAYER_OCCUPANCY: false}
	_layers.merge(_layer_memory, true)
	_build()


func _ready() -> void:
	_connect_bus(true)
	if _band.is_empty():
		_band = GameClock.get_current_band()
	refresh()
	if _selected_floor == NO_FLOOR and get_step_floors().has(get_player_floor()):
		_selected_floor = get_player_floor()
		_cut.hover_floor = _selected_floor
		_refresh_floor_panel()
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
	_cut_clip.visible = false
	_plan_view.visible = true
	_plan_view.show_floor(floor_number, _plan_model(floor_number))
	_refresh_texts()
	_refresh_floor_panel()
	floor_zoomed.emit(floor_number)


func zoom_out() -> void:
	if not is_zoomed():
		return
	_zoom_floor = NO_FLOOR
	_selected_room = ""
	_plan_view.visible = false
	_cut_clip.visible = true
	_cut.hover_floor = _selected_floor
	_cut_overlay.queue_redraw()
	_refresh_texts()
	_refresh_floor_panel()
	floor_zoomed.emit(NO_FLOOR)


func is_zoomed() -> bool:
	return _zoom_floor != NO_FLOOR


func get_zoomed_floor() -> int:
	return _zoom_floor


## Planta señalada en el corte (panel lateral). NO_FLOOR = ninguna. scroll = centrarla si el corte
## se desplaza (teclado, código); señalar con el ratón pasa false para no mover lo que hay debajo.
func select_floor(floor_number: int, scroll: bool = true) -> void:
	if floor_number != NO_FLOOR and not get_cut_floors().has(floor_number):
		return
	_selected_floor = floor_number
	_cut.hover_floor = floor_number
	if scroll:
		_cut.ensure_floor_visible(floor_number)
	_cut_overlay.queue_redraw()
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


## Orden de ↑/↓: las plantas de la torre de abajo arriba (la nave queda fuera; desde ella se va a PB).
func get_step_floors() -> Array[int]:
	var out: Array[int] = []
	var factory: int = Database.get_balance_int(B_FACTORY)
	for f: int in get_cut_floors():
		if f != factory:
			out.append(f)
	return out


func get_floor_status(floor_number: int) -> int:
	return int((_model.get("floor_status", {}) as Dictionary).get(floor_number, ACCESS_FORBIDDEN))


## true si la planta solo es ámbar por un cuarto de servicio compartido (sin salas propias).
func is_floor_foothold(floor_number: int) -> bool:
	return bool((_model.get("foothold", {}) as Dictionary).get(floor_number, false))


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


## Rectángulo de una planta en el lienzo del corte (Rect2() si no se dibuja).
func get_cut_floor_rect(floor_number: int) -> Rect2:
	return _cut.floor_rect(floor_number)


func get_cut_canvas() -> CutCanvas:
	return _cut


func get_visible_dots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dot: Dictionary in _model.get("dots", []):
		out.append(dot.duplicate())
	return out


## Puntos de los objetivos marcados (con planta, sala y si es aproximado).
func get_target_dots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dot: Dictionary in _model.get("dots", []):
		if bool(dot.get("target", false)):
			out.append(dot.duplicate())
	return out


## Salas listadas en el panel lateral (planta ampliada o señalada).
func get_panel_room_ids() -> Array[String]:
	return _listed.duplicate()


## Objetivos listados en el panel lateral.
func get_panel_target_ids() -> Array[String]:
	return _listed_targets.duplicate()


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


## Veces que se ha recalculado el modelo (QA: los avisos del bus se agrupan en uno por fotograma).
func get_refresh_count() -> int:
	return _refresh_count


## Recalcula acceso, puntos y paneles (lo llaman los cambios de acreditación, disfraz, etc.).
func refresh() -> void:
	_rebuild_model()
	_refresh_texts()
	_sync_toggles()
	_push_model()


## Nivel de expediente que desbloquea la rutina (tabla de secciones de PERSONNEL).
static func routine_level() -> int:
	return PersonnelApp.section_level(PersonnelApp.S_ROUTINE)


## Nivel de expediente efectivo para un personaje: el de PERSONNEL (puesto, RRHH, intrusión,
## chantaje) o el que fije context.file_levels (QA).
func file_level_for(npc_id: String) -> int:
	var level: int = PersonnelApp.effective_level(npc_id)
	var given: Variant = _context.get(CONTEXT_FILE_LEVELS, {})
	if given is Dictionary:
		level = maxi(level, int((given as Dictionary).get(npc_id, 0)))
	return level


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
	# Cerradura antigua en la puerta: el nivel no basta (la abre la llave, ámbar), como DoorAccess.
	if not has_old_lock_door(room) and meets_door_rule(room, int(ctx.get(CTX_CLEARANCE, -1)), tags):
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


## La puerta de la sala es de cerradura antigua (interactivo lock_old con target door).
static func has_old_lock_door(room: RoomData) -> bool:
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) == "lock_old" and str(entry.get("target", "door")) == "door":
			return true
	return false


static func access_mode(room: RoomData) -> String:
	if room.extra.has(KEY_MODE):
		return str(room.extra[KEY_MODE])
	var base: RoomData = Database.get_room(str(room.extra.get(KEY_BASE_ID, "")))
	return str(base.extra.get(KEY_MODE, "")) if base != null else ""


## Etiqueta de ocupación con regla propia (balance mapa.acceso_por_etiqueta): plantas y/o salas.
static func tag_grants(tag: String, room: RoomData) -> bool:
	return rule_grants(_balance_dict(B_TAG_RULES).get(tag, null), room)


## Regla {floors, rooms (ids base), max_room_clearance} (acceso_por_etiqueta, llaves_sala).
static func rule_grants(rule: Variant, room: RoomData) -> bool:
	if not rule is Dictionary:
		return false
	var r: Dictionary = rule
	var in_floor: bool = bool(r.get("all_floors", false)) \
			or has_number(r.get(RULE_FLOORS, []), room.floor)
	var in_rooms: bool = (r.get(RULE_ROOMS, []) as Array).has(DatabaseSystem.get_room_base_id(room.id))
	if not (in_floor or in_rooms):
		return false
	# after_hour: solo fuera de horario (desde esa hora hasta el comienzo de la jornada).
	if r.has("after_hour") and GameClock.get_hour() < int(r["after_hour"]) \
			and GameClock.get_hour() >= Database.get_balance_int("tiempo.hora_inicio_jornada"):
		return false
	return not r.has(RULE_MAX_ROOM) or room.clearance_required <= int(r[RULE_MAX_ROOM])


## Array de números del JSON (llegan como float) que contiene el entero n (Array.has distingue tipos).
static func has_number(values: Variant, n: int) -> bool:
	if values is Array:
		for v: Variant in values:
			if (v is int or v is float) and int(v) == n:
				return true
	return false


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
		METHOD_ROOM_KEY:
			return _room_key_grants(room, ctx)
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


## Llave de una sala o planta concreta (mapa.llaves_sala: objeto → regla).
static func _room_key_grants(room: RoomData, ctx: Dictionary) -> bool:
	var table: Dictionary = _balance_dict(B_ROOM_KEYS)
	for item: Variant in ctx.get(CTX_ITEMS, []):
		if rule_grants(table.get(str(item), null), room):
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
## espacios transversales de datos: {id, kind, lo, hi, index (orden dentro de su tipo)}. Cacheado.
static func core_columns() -> Array[Dictionary]:
	if _columns_cache.is_empty():
		for kind: String in CutCanvas.COLUMN_ORDER:
			var index: int = 0
			for room: RoomData in Database.get_all_rooms():
				if room.is_transversal() and FloorLayout.transit_kind_of(room) == kind:
					_columns_cache.append({"id": room.id, "kind": kind, "lo": room.floors[0], "hi": room.floors[1], "index": index})
					index += 1
	var out: Array[Dictionary] = []
	for col: Dictionary in _columns_cache:
		out.append(col.duplicate())
	return out


## Bandas de la torre de abajo arriba (orden de retranqueo del corte), según art_bands.json.
static func tower_band_order() -> Array[String]:
	if not _band_order.is_empty():
		return _band_order
	var keyed: Array = []
	var roof: int = Database.get_balance_int(B_ROOF)
	for band: Dictionary in Database.get_all_art_bands():
		var low: int = roof + 1
		for f: Variant in band.get("floors", []):
			if int(f) >= -roof and int(f) <= roof:
				low = mini(low, int(f))
		if low <= roof:
			keyed.append([low, str(band.get("id", ""))])
	keyed.sort()
	for entry: Array in keyed:
		_band_order.append(str(entry[1]))
	return _band_order


## Plano cacheado (FloorLayout es determinista y los datos no cambian durante la ejecución). Con un
## FloorStreamer en el árbol se comparte su caché (get_plan_for).
static func plan_of(floor_number: int) -> Dictionary:
	if not _plan_cache.has(floor_number):
		var streamer: FloorStreamer = _streamer()
		_plan_cache[floor_number] = streamer.get_plan_for(floor_number) if streamer != null else FloorLayout.compute(floor_number)
	return _plan_cache[floor_number]


## Calcula por adelantado los planos de todas las plantas del corte (para una pantalla de carga).
static func prewarm_plans() -> void:
	var exterior: int = Database.get_balance_int(B_EXTERIOR)
	for f: int in Database.get_floor_ids():
		if f != exterior:
			plan_of(f)


static func _streamer() -> FloorStreamer:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(FloorStreamer.GROUP) as FloorStreamer if tree != null else null


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
	_model = {"ctx": ctx, "statuses": {}, "methods": {}, "floor_status": {}, "foothold": {}, "blocks": {}}
	for f: int in get_cut_floors():
		_model_floor(f, ctx)
	_model["dots"] = _collect_dots()
	_model["player_floor"] = _player_floor()
	_model["player_room"] = _player_room()
	_refresh_count += 1


func _model_floor(f: int, ctx: Dictionary) -> void:
	var best: Vector2i = Vector2i(ACCESS_FORBIDDEN, ACCESS_FORBIDDEN)
	var ids: Array[String] = []
	for room: RoomData in FloorLayout.rooms_on_floor(f):
		var status: int = room_access(room, ctx)
		_model["statuses"][room.id] = status
		_model["methods"][room.id] = alternative_method(room, ctx) if status == ACCESS_ALTERNATIVE else ""
		if MapFloorPlan.is_circulation(room):
			continue
		ids.append(room.id)
		best = Vector2i(best.x, mini(best.y, status)) if is_service_room(room) else Vector2i(mini(best.x, status), best.y)
	_model["floor_status"][f] = combine_floor(best.x, best.y)
	_model["foothold"][f] = best.x == ACCESS_FORBIDDEN and best.y != ACCESS_FORBIDDEN
	_model["blocks"][f] = _order_by_plan(f, ids)


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
	var need: int = routine_level()
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var dot: Dictionary = _dot_for(npc, targets.has(npc.id), need)
		if not dot.is_empty():
			out.append(dot)
	return out


func _dot_for(npc: NPCRuntime, is_target: bool, need: int) -> Dictionary:
	if not npc.alive or not (is_target or npc.is_named or NPCDirector.knows_player(npc.id)):
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


static func _floor_of(room_id: String, fallback: int) -> int:
	var room: RoomData = Database.get_room(room_id)
	return room.floor if room != null and not room.is_transversal() else fallback


## Objetivos marcados: context.targets (QA) o PlayerState.get_marked_targets().
func marked_targets() -> Array[String]:
	var raw: Variant = _context.get(CONTEXT_TARGETS, null)
	if raw == null:
		return PlayerState.get_marked_targets()
	var out: Array[String] = []
	if raw is Array:
		for id: Variant in raw:
			out.append(str(id))
	return out


func _player_floor() -> int:
	var streamer: FloorStreamer = _streamer() if is_inside_tree() else null
	if streamer != null and not streamer.get_plan().is_empty():
		return streamer.get_current_floor()
	return PlayerState.get_floor()


func _player_room() -> String:
	return PlayerState.get_room()


## Celda del jugador en el plano cargado (INF si no hay mundo o no es esa planta).
func _player_cell(floor_number: int) -> Vector2:
	if not is_inside_tree():
		return Vector2.INF
	var streamer: FloorStreamer = _streamer()
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
	_refresh_targets_panel()


# ─── Construcción de la interfaz ───────────────────────────────────

func _build() -> void:
	_cut_clip = Control.new()
	_cut_clip.name = "CutClip"
	_cut_clip.clip_contents = true
	_cut_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cut_clip)
	_cut = CutCanvas.new()
	_cut.view = self
	_cut_clip.add_child(_cut)
	_cut_overlay = CutOverlay.new()
	_cut_overlay.canvas = self._cut
	_cut.overlay = _cut_overlay
	_cut_clip.add_child(_cut_overlay)
	_plan_view = MapFloorPlan.new()
	_plan_view.visible = false
	add_child(_plan_view)
	_build_poster_labels()
	_build_header_card()
	_build_layer_bar()
	_build_side_column()
	_cut.floor_hovered.connect(_on_cut_hovered)
	_cut.floor_clicked.connect(zoom_to_floor)
	_plan_view.room_hovered.connect(_on_room_hovered)
	_plan_view.room_clicked.connect(_on_room_hovered)


func _build_poster_labels() -> void:
	_title = _mk_label(1.45, UITheme.FONT_BOLD, "white")
	_subtitle = _mk_label(0.78, UITheme.FONT_SEMIBOLD, "white")
	_footer_left = _mk_label(0.68, UITheme.FONT_SEMIBOLD, "ink_soft")
	_footer_right = _mk_label(0.62, UITheme.FONT_REGULAR, "ink_soft")
	for label: Label in [_title, _subtitle, _footer_left, _footer_right]:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		add_child(label)
	_footer_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Columna lateral: capas fijas arriba, panel desplazable (planta, objetivos, leyenda) y la pista
## fija abajo; un degradado con chevrón avisa de que hay más contenido debajo.
func _build_side_column() -> void:
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_side_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side)
	_build_floor_section()
	_build_targets_section()
	_build_legend_section()
	_side_fade = SideFade.new()
	add_child(_side_fade)
	_side_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_fade())
	_side_scroll.get_v_scroll_bar().changed.connect(_update_fade)
	_hint = _mk_label(0.64, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	add_child(_hint)


## Etiqueta con tinta de papel. track = true: persistente, se reescala con el tema (_apply_sizes);
## las filas efímeras del panel (track = false) reciben el tamaño al crearse.
func _mk_label(ratio: float, font_path: String, color_key: String, wrap: bool = false, track: bool = true) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override("font", UITheme.font(font_path))
	label.add_theme_color_override("font_color", MapFloorPlan.palette()[color_key])
	label.add_theme_font_size_override("font_size", maxi(9, roundi(float(_base()) * ratio)))
	label.set_meta("map_color", color_key)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if track:
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


## Tarjeta del jugador en la cabecera: nivel de acreditación, puesto, disfraz y nivel de expedientes.
func _build_header_card() -> void:
	_badge = _mk_label(1.3, UITheme.FONT_BOLD, "red")
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_badge)
	_occ_label = _mk_label(0.86, UITheme.FONT_BOLD, "white")
	_occ_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_occ_label.clip_text = true
	_disguise_label = _mk_label(0.64, UITheme.FONT_SEMIBOLD, "white", true)
	_disguise_label.max_lines_visible = HEADER_LINES
	_disguise_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_disguise_label.clip_text = true
	add_child(_occ_label)
	add_child(_disguise_label)


## Capas: tres pastillas fijas (icono, nombre corto, tecla) y el selector de franja de ocupación.
func _build_layer_bar() -> void:
	_layer_bar = HBoxContainer.new()
	add_child(_layer_bar)
	var index: int = 1
	for layer: String in LAYERS:
		var chip: LayerChip = LayerChip.new()
		chip.icon_name = str(LAYER_ICONS[layer])
		chip.hotkey = str(index)
		chip.set_meta("map_key", LAYER_SHORT_KEYS[layer])
		chip.set_meta("map_tip", LAYER_KEYS[layer])
		chip.toggled.connect(func(on: bool) -> void: set_layer(layer, on))
		_layer_bar.add_child(chip)
		_toggles[layer] = chip
		index += 1
	_band_row = HBoxContainer.new()
	add_child(_band_row)
	var prev: IconButton = IconButton.new()
	prev.glyph = IconButton.GLYPH_LEFT
	prev.pressed.connect(_shift_band.bind(-1))
	_band_row.add_child(prev)
	_band_label = _mk_label(0.74, UITheme.FONT_BOLD, "people")
	_band_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_band_label.clip_text = true
	_band_row.add_child(_band_label)
	var next: IconButton = IconButton.new()
	next.glyph = IconButton.GLYPH_RIGHT
	next.pressed.connect(_shift_band.bind(1))
	_band_row.add_child(next)


func _build_floor_section() -> void:
	_floor_box = VBoxContainer.new()
	_side.add_child(_floor_box)
	_nav_row = HBoxContainer.new()
	_floor_box.add_child(_nav_row)
	_add_nav_button(IconButton.GLYPH_BACK, "MAP_BACK", zoom_out)
	_add_nav_button(IconButton.GLYPH_UP, "", _step_zoom.bind(1))
	_add_nav_button(IconButton.GLYPH_DOWN, "", _step_zoom.bind(-1))
	_floor_title = _mk_label(1.05, UITheme.FONT_BOLD, "ink", true)
	_floor_box.add_child(_floor_title)
	_floor_band = _mk_label(0.7, UITheme.FONT_BOLD, "ink_soft")
	_floor_box.add_child(_floor_band)
	var status_row: HBoxContainer = HBoxContainer.new()
	_floor_box.add_child(status_row)
	_floor_status = Swatch.new()
	_floor_status.kind = Swatch.KIND_CHIP
	status_row.add_child(_floor_status)
	_floor_status_label = _mk_label(0.8, UITheme.FONT_BOLD, "ink")
	status_row.add_child(_floor_status_label)
	_floor_status_desc = _mk_label(0.66, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	_floor_box.add_child(_floor_status_desc)
	_floor_people = _mk_label(0.68, UITheme.FONT_SEMIBOLD, "ink_soft", true)
	_floor_box.add_child(_floor_people)
	_room_list = VBoxContainer.new()
	_room_list.add_theme_constant_override("separation", 2)
	_floor_box.add_child(_room_list)
	_side.add_child(_separator())


func _build_targets_section() -> void:
	_targets_box = VBoxContainer.new()
	_side.add_child(_targets_box)
	_targets_box.add_child(_section_title("MAP_TARGETS_TITLE"))
	_target_list = VBoxContainer.new()
	_target_list.add_theme_constant_override("separation", 2)
	_targets_box.add_child(_target_list)
	_targets_box.add_child(_separator())


## Leyenda compacta en dos columnas: estados de acceso, símbolos y capas.
func _build_legend_section() -> void:
	_side.add_child(_section_title("MAP_LEGEND_TITLE"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	_side.add_child(grid)
	var entries: Array = [
		[Swatch.KIND_STATUS, ACCESS_ALLOWED, "MAP_ACCESS_ALLOWED"], [Swatch.KIND_STATUS, ACCESS_ALTERNATIVE, "MAP_ACCESS_ALTERNATIVE"],
		[Swatch.KIND_STATUS, ACCESS_FORBIDDEN, "MAP_ACCESS_FORBIDDEN"], [Swatch.KIND_FOOTHOLD, ACCESS_ALTERNATIVE, "MAP_LEGEND_FOOTHOLD"],
		[Swatch.KIND_PIN, 0, "MAP_LEGEND_YOU"], [Swatch.KIND_EVAC, 0, "MAP_LEGEND_EVAC"],
		[Swatch.KIND_DOT, 0, "MAP_LEGEND_KNOWN"], [Swatch.KIND_TARGET, 0, "MAP_LEGEND_TARGET"],
		[Swatch.KIND_CAMERA, 0, "MAP_LEGEND_CAMERA"], [Swatch.KIND_ROUTE, 0, "MAP_LEGEND_ROUTE"],
		[Swatch.KIND_PEOPLE, 0, "MAP_LEGEND_PEOPLE"],
	]
	for entry: Array in entries:
		grid.add_child(_legend_row(str(entry[0]), int(entry[1]), str(entry[2])))


func _legend_row(kind: String, status: int, key: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var swatch: Swatch = Swatch.new()
	swatch.kind = kind
	swatch.status = status
	swatch.small = true
	row.add_child(swatch)
	var label: Label = _mk_label(0.64, UITheme.FONT_SEMIBOLD, "ink")
	label.set_meta("map_key", key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	return row


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
	var compact: bool = is_compact()
	var margin: float = maxf(6.0, minf(size.x, size.y) * MARGIN_RATIO)
	var poster: Rect2 = Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)
	var frame: float = maxf(5.0, base * FRAME_RATIO)
	var inner: Rect2 = poster.grow(-frame)
	var header: Rect2 = Rect2(inner.position, Vector2(inner.size.x, maxf(52.0, base * (HEADER_COMPACT_RATIO if compact else HEADER_RATIO))))
	var footer_h: float = 0.0 if compact else base * FOOTER_RATIO
	var footer: Rect2 = Rect2(inner.position.x, inner.end.y - footer_h, inner.size.x, footer_h)
	var pad: float = base * PAD_RATIO
	var body: Rect2 = Rect2(inner.position.x + pad, header.end.y + pad, inner.size.x - pad * 2.0, footer.position.y - header.end.y - pad * 2.0)
	var side_w: float = clampf(body.size.x * SIDE_SHARE, minf(base * SIDE_MIN_RATIO, body.size.x * SIDE_MAX_SHARE), body.size.x * SIDE_MAX_SHARE)
	var map_rect: Rect2 = Rect2(body.position, Vector2(body.size.x - side_w - pad, body.size.y))
	var side: Rect2 = Rect2(map_rect.end.x + pad, body.position.y, side_w, body.size.y)
	_rects = {"poster": poster, "inner": inner, "header": header, "footer": footer, "map": map_rect, "frame": frame, "side": side}
	_place(_cut_clip, map_rect)
	_cut.fit(map_rect.size)
	_place(_cut_overlay, Rect2(Vector2.ZERO, map_rect.size))
	_place(_plan_view, map_rect)
	_layout_side(side, base)
	_subtitle.visible = not compact
	_footer_left.visible = not compact
	_footer_right.visible = not compact
	_layout_header(header, base)
	_place(_footer_left, Rect2(footer.position.x + pad, footer.position.y, footer.size.x * 0.56 - pad, footer.size.y))
	_place(_footer_right, Rect2(footer.position.x + footer.size.x * 0.56, footer.position.y, footer.size.x * 0.44 - pad, footer.size.y))
	queue_redraw()


## Columna lateral: capas (y franja) arriba, pista abajo, panel desplazable en medio.
func _layout_side(col: Rect2, base: float) -> void:
	var gap: float = base * 0.45
	var y: float = col.position.y
	var bar_h: float = _layer_bar.get_combined_minimum_size().y
	_place(_layer_bar, Rect2(col.position.x, y, col.size.x, bar_h))
	y += bar_h + gap
	if _band_row.visible:
		var band_h: float = _band_row.get_combined_minimum_size().y
		_place(_band_row, Rect2(col.position.x, y, col.size.x, band_h))
		y += band_h + gap
	var hint_h: float = _text_height(_hint, col.size.x, 3)
	_place(_hint, Rect2(col.position.x, col.end.y - hint_h, col.size.x, hint_h))
	var scroll: Rect2 = Rect2(col.position.x, y, col.size.x, maxf(base, col.end.y - hint_h - gap - y))
	_place(_side_scroll, scroll)
	_side.custom_minimum_size.x = scroll.size.x - base * 0.8
	var fade_h: float = base * FADE_RATIO
	_place(_side_fade, Rect2(scroll.position.x, scroll.end.y - fade_h, scroll.size.x - base * 0.8, fade_h))
	_update_fade.call_deferred()


## Alto del texto de una etiqueta con ajuste de línea para un ancho dado (máximo max_lines líneas).
static func _text_height(label: Label, width: float, max_lines: int) -> float:
	var font: Font = label.get_theme_font("font")
	var fs: int = label.get_theme_font_size("font_size")
	if label.text.is_empty():
		return 0.0
	var h: float = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, width), fs, max_lines).y
	var lines: int = maxi(1, roundi(h / maxf(1.0, font.get_height(fs))))
	return h + float(label.get_theme_constant("line_spacing") * lines) + 2.0


func _update_fade() -> void:
	if _side_fade == null or _side_scroll == null:
		return
	var bar: VScrollBar = _side_scroll.get_v_scroll_bar()
	_side_fade.visible = bar.max_value - bar.page > bar.value + 1.0


## Pantalla baja respecto a la letra (móvil, texto grande): cabecera compacta y sin pie.
func is_compact() -> bool:
	return size.y / maxf(1.0, float(_base())) < COMPACT_ROWS


func _layout_header(header: Rect2, base: float) -> void:
	var sign_h: float = header.size.y * 0.62
	var right: float = header.end.x - sign_h * 2.3 - header.size.y * 0.25 - base
	var card_w: float = clampf(header.size.x * 0.28, base * 9.0, base * 17.0)
	var badge: Vector2 = Vector2(base * 2.7, sign_h)
	var card_x: float = right - card_w
	_place(_badge, Rect2(card_x, header.get_center().y - badge.y * 0.5, badge.x, badge.y))
	var text_x: float = card_x + badge.x + base * 0.45
	var text_w: float = right - text_x
	var occ_h: float = _occ_label.get_combined_minimum_size().y
	var dis_h: float = minf(_text_height(_disguise_label, text_w, HEADER_LINES), header.size.y - occ_h)
	var top: float = header.get_center().y - (occ_h + dis_h) * 0.5
	_place(_occ_label, Rect2(text_x, top, text_w, occ_h))
	_place(_disguise_label, Rect2(text_x, top + occ_h, text_w, dis_h))
	_rects["card_x"] = card_x - base * 0.6
	var left: float = header.position.x + header.size.y * 1.05
	var width: float = card_x - base * 1.2 - left
	var title_h: float = _title.get_combined_minimum_size().y
	var sub_h: float = _subtitle.get_combined_minimum_size().y if _subtitle.visible else 0.0
	var title_top: float = header.position.y + (header.size.y - title_h - sub_h) * 0.5
	_place(_title, Rect2(left, title_top, width, title_h))
	_place(_subtitle, Rect2(left, title_top + title_h, width, sub_h))


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
	_badge.add_theme_stylebox_override("normal", _badge_box(pal["white"], base))
	_side.add_theme_constant_override("separation", roundi(base * 0.42))
	_floor_box.add_theme_constant_override("separation", roundi(base * 0.3))
	_layer_bar.add_theme_constant_override("separation", roundi(base * 0.35))
	var touch: bool = _touch_ui()
	for chip: Variant in _toggles.values():
		(chip as LayerChip).show_hotkey = not touch
		(chip as LayerChip).restyle(base)
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


## Interfaz táctil: la de UIRoot si hay una en el árbol; si no, la detección de plataforma.
func _touch_ui() -> bool:
	var root: Node = get_tree().get_first_node_in_group(UIRoot.GROUP) if is_inside_tree() else null
	if root is UIRoot:
		return (root as UIRoot).is_touch_mode()
	return UIRoot.detect_touch()


func _refresh_texts() -> void:
	if _title == null:
		return
	_title.text = tr("MAP_TITLE")
	_subtitle.text = tr("MAP_SUBTITLE") if not is_zoomed() else UITheme.trf("MAP_SUBTITLE_FLOOR", [floor_name(_zoom_floor)])
	_footer_left.text = tr("MAP_FOOTER_JOKE")
	_footer_right.text = tr("MAP_FOOTER_POSTED")
	for node: Node in _side.find_children("*", "", true, false) + _layer_bar.get_children():
		if node.has_meta("map_key") and (node is Label or node is Button):
			_apply_key_text(node)
	_refresh_access_panel()
	_refresh_band_label()
	_nav_row.visible = is_zoomed()
	var touch: bool = _touch_ui()
	if is_zoomed():
		_hint.text = tr("MAP_HINT_ZOOM_TOUCH" if touch else "MAP_HINT_ZOOM")
	else:
		_hint.text = tr("MAP_HINT_TOUCH" if touch else "MAP_HINT_CUT")
	if is_inside_tree():
		_layout()


func _apply_key_text(node: Node) -> void:
	var key: String = str(node.get_meta("map_key"))
	var text: String = tr(key)
	if node is Label and str(node.get_meta("map_color", "")) == "red":
		text = text.to_upper()
	if node is LayerChip:
		(node as LayerChip).caption = text
		(node as LayerChip).tooltip_text = tr(str(node.get_meta("map_tip", key)))
		(node as LayerChip).queue_redraw()
		return
	node.set("text", text)


func _refresh_access_panel() -> void:
	var ctx: Dictionary = _model.get("ctx", {})
	_badge.text = UITheme.trf("MAP_CLEARANCE_FMT", [int(ctx.get(CTX_CLEARANCE, 0))])
	var occ: OccupationData = PlayerState.get_occupation()
	_occ_label.text = tr(occ.name_key) if occ != null else ""
	var disguise: String = str(ctx.get(CTX_DISGUISE, ""))
	var item: ItemData = Database.get_item(disguise) if not disguise.is_empty() else null
	var worn: String = UITheme.trf("MAP_DISGUISE_FMT", [tr(item.name_key)]) if item != null else tr("MAP_NO_DISGUISE")
	_disguise_label.text = worn + " · " + UITheme.trf("MAP_FILE_LEVEL_FMT", [PersonnelApp.player_level()])


func _refresh_band_label() -> void:
	if _band_label == null:
		return
	_band_label.text = UITheme.trf("MAP_OCCUPANCY_BAND_FMT", [tr(GameClock.get_band_name_key(_band))]) if not _band.is_empty() else ""
	var show: bool = is_layer_on(LAYER_OCCUPANCY)
	if _band_row.visible != show:
		_band_row.visible = show
		if is_inside_tree():
			_layout()


func _sync_toggles() -> void:
	for layer: String in _toggles:
		(_toggles[layer] as LayerChip).set_pressed_no_signal(is_layer_on(layer))
		(_toggles[layer] as LayerChip).queue_redraw()
	_refresh_band_label()


func _shift_band(delta: int) -> void:
	var order: Array[String] = GameClock.get_band_order()
	if order.is_empty():
		return
	var index: int = maxi(0, order.find(_band))
	set_band(order[posmod(index + delta, order.size())])


## Planta siguiente en el orden de ↑/↓ (desde la nave o sin planta: PB / la del jugador).
func _step_from(from_floor: int, delta: int) -> int:
	var floors: Array[int] = get_step_floors()
	if floors.is_empty():
		return NO_FLOOR
	if from_floor == Database.get_balance_int(B_FACTORY):
		return 0 if floors.has(0) else floors[0]
	var index: int = floors.find(from_floor)
	if index < 0:
		index = maxi(floors.find(get_player_floor()), floors.find(0))
		return floors[maxi(index, 0)]
	return floors[clampi(index + delta, 0, floors.size() - 1)]


func _step_zoom(delta: int) -> void:
	var next: int = _step_from(_zoom_floor, delta)
	if next != NO_FLOOR and next != _zoom_floor:
		zoom_to_floor(next)


# ─── Panel de planta y objetivos ───────────────────────────────────

func _refresh_floor_panel() -> void:
	if _floor_title == null:
		return
	var f: int = _zoom_floor if is_zoomed() else _selected_floor
	var has_floor: bool = f != NO_FLOOR
	for node: Control in [_floor_band, _floor_status.get_parent() as Control, _floor_status_desc, _floor_people]:
		node.visible = has_floor
	for child: Node in _room_list.get_children():
		_room_list.remove_child(child)
		child.queue_free()
	_listed.clear()
	if not has_floor:
		_floor_title.text = tr("MAP_FLOOR_PROMPT")
		return
	_floor_title.text = floor_name(f)
	var band: Dictionary = Database.get_art_band_for_floor(f)
	_floor_band.text = tr(str(band.get("name_key", ""))).to_upper()
	_floor_band.add_theme_color_override("font_color", CutCanvas.band_ink(f))
	_refresh_floor_status(f)
	_floor_people.text = _people_line(f)
	for room_id: String in get_cut_room_ids(f).slice(0, MAX_ROOM_ROWS):
		_room_list.add_child(_room_row(room_id))
		_listed.append(room_id)


func _refresh_floor_status(f: int) -> void:
	var status: int = get_floor_status(f)
	var foothold: bool = is_floor_foothold(f)
	_floor_status.status = status
	_floor_status.kind = Swatch.KIND_FOOTHOLD if foothold else Swatch.KIND_CHIP
	_floor_status.queue_redraw()
	_floor_status_label.text = tr("MAP_FOOTHOLD" if foothold else MapFloorPlan.status_key(status))
	_floor_status_desc.text = tr("MAP_FOOTHOLD_DESC" if foothold else MapFloorPlan.status_key(status) + "_DESC")


func _people_line(f: int) -> String:
	var known: int = 0
	var targets: int = 0
	for dot: Dictionary in _model.get("dots", []):
		if int(dot.get("floor", NO_FLOOR)) == f:
			known += 0 if bool(dot.get("target", false)) else 1
			targets += 1 if bool(dot.get("target", false)) else 0
	var line: String = UITheme.trf("MAP_DOTS_COUNT_FMT", [known])
	if targets > 0:
		line += " · " + UITheme.trf("MAP_TARGETS_COUNT_FMT", [targets])
	var need: int = routine_level()
	if PersonnelApp.player_level() < need:
		line += "\n" + UITheme.trf("MAP_ROUTINES_LOCKED_FMT", [need])
	return line


func _room_row(room_id: String) -> HBoxContainer:
	var room: RoomData = Database.get_room(room_id)
	var row: HBoxContainer = HBoxContainer.new()
	var swatch: Swatch = Swatch.new()
	swatch.kind = Swatch.KIND_STATUS
	swatch.status = get_room_status(room_id)
	swatch.small = true
	row.add_child(swatch)
	var name_label: Label = _mk_label(0.72, UITheme.FONT_BOLD if room_id == _selected_room else UITheme.FONT_SEMIBOLD, "ink", false, false)
	name_label.text = tr(room.name_key) if room != null else room_id
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	var method: String = get_room_method(room_id)
	var tail: Label = _mk_label(0.62, UITheme.FONT_BOLD, "alt_ink" if not method.is_empty() else "ink_soft", false, false)
	var level: String = UITheme.trf("MAP_CLEARANCE_FMT", [room.clearance_required if room != null else 0])
	tail.text = tr(str(METHOD_KEYS[method])) + " · " + level if not method.is_empty() else level
	row.add_child(tail)
	return row


## Lista de objetivos marcados: mira, nombre y planta; tocar la fila amplía su planta.
func _refresh_targets_panel() -> void:
	if _target_list == null:
		return
	for child: Node in _target_list.get_children():
		_target_list.remove_child(child)
		child.queue_free()
	_listed_targets.clear()
	for dot: Dictionary in get_target_dots():
		_target_list.add_child(_target_row(dot))
		_listed_targets.append(str(dot.get("npc_id", "")))
	_targets_box.visible = not _listed_targets.is_empty()


func _target_row(dot: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var f: int = int(dot.get("floor", NO_FLOOR))
	row.gui_input.connect(func(event: InputEvent) -> void:
		if UITheme.is_primary_press(event):
			zoom_to_floor(f))
	var swatch: Swatch = Swatch.new()
	swatch.kind = Swatch.KIND_TARGET
	swatch.small = true
	row.add_child(swatch)
	var name_label: Label = _mk_label(0.72, UITheme.FONT_BOLD, "ink", false, false)
	name_label.text = str(dot.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	var tail: Label = _mk_label(0.62, UITheme.FONT_BOLD, "ink_soft", false, false)
	var where: String = floor_name(f)
	tail.text = UITheme.trf("MAP_TARGET_APPROX_FMT", [where]) if bool(dot.get("approximate", false)) else where
	row.add_child(tail)
	return row


func _on_cut_hovered(floor_number: int) -> void:
	if floor_number != NO_FLOOR and floor_number != _selected_floor:
		select_floor(floor_number, false)


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
	if footer.size.y > 0.0:
		draw_line(footer.position, Vector2(footer.end.x, footer.position.y), pal["ink_faint"], 2.0)
	var side: Rect2 = _rects["side"]
	var side_x: float = side.position.x - float(_base()) * PAD_RATIO * 0.5
	draw_line(Vector2(side_x, side.position.y), Vector2(side_x, side.end.y), pal["ink_faint"], 2.0)


func _draw_header_badges(header: Rect2, pal: Dictionary) -> void:
	var s: float = header.size.y * 0.66
	var at: Vector2 = Vector2(header.position.x + header.size.y * 0.52, header.get_center().y)
	draw_circle(at, s * 0.5, pal["white"])
	UITheme.draw_icon(self, "star", Rect2(at - Vector2(s, s) * 0.32, Vector2(s, s) * 0.64), pal["red"], 2.0)
	if _rects.has("card_x"):
		var x: float = _rects["card_x"]
		draw_line(Vector2(x, header.position.y + header.size.y * 0.2), Vector2(x, header.end.y - header.size.y * 0.2), Color(pal["white"], 0.45), 2.0)
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
	var from: int = _selected_floor
	var next: int = _step_from(from, delta)
	if next != NO_FLOOR:
		select_floor(next)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
		NOTIFICATION_THEME_CHANGED:
			if is_inside_tree():
				_apply_sizes()
				_refresh_texts()
				_refresh_floor_panel()
				_refresh_targets_panel()
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_inside_tree():
				_refresh_texts()
				_push_model()


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


## Varios avisos seguidos (set_occupation emite varios) se agrupan en un solo refresco diferido.
func _refresh_later() -> void:
	if _refresh_queued or not is_inside_tree() or is_queued_for_deletion():
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	if is_inside_tree():
		refresh()


# ═══ Controles auxiliares ══════════════════════════════════════════

## Muestra de leyenda / estado: bloque de acceso, chapa, chincheta, punto, objetivo, flecha, cámara,
## ruta alternativa y ocupación.
class Swatch extends Control:
	const KIND_STATUS := "status"
	const KIND_CHIP := "chip"
	const KIND_FOOTHOLD := "foothold"
	const KIND_PIN := "pin"
	const KIND_DOT := "dot"
	const KIND_TARGET := "target"
	const KIND_EVAC := "evac"
	const KIND_CAMERA := "camera"
	const KIND_ROUTE := "route"
	const KIND_PEOPLE := "people"
	var kind: String = KIND_STATUS
	var status: int = MapFloorPlan.ACCESS_ALLOWED
	var small: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			var base: float = float(MapFloorPlan.base_font_of(self))
			custom_minimum_size = Vector2(base * (1.4 if small else 1.7), base * (1.0 if small else 1.2))

	func _draw() -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var r: Rect2 = Rect2(Vector2.ZERO, size).grow(-2.0)
		var c: Vector2 = r.get_center()
		match kind:
			KIND_STATUS:
				MapFloorPlan.draw_status_block(self, r, status, pal, r.size.y * 0.3, 1.5)
				draw_rect(r, MapFloorPlan.status_ink(status, pal), false, 2.0)
			KIND_CHIP, KIND_FOOTHOLD:
				CutCanvas.draw_chip(self, r, status, "", null, 0, pal, kind == KIND_FOOTHOLD)
			KIND_PIN:
				MapFloorPlan.draw_pin(self, c, r.size.y * 0.3, pal)
			KIND_DOT:
				MapFloorPlan.draw_npc_dot(self, c, r.size.y * 0.22, pal, false, false)
			KIND_TARGET:
				MapFloorPlan.draw_target_marker(self, c, r.size.y * 0.2, pal, false)
			KIND_EVAC:
				MapFloorPlan.draw_arrow(self, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), pal["green"], r.size.y * 0.22, r.size.y * 0.6)
			_:
				_draw_layer_sample(r, c, pal)

	func _draw_layer_sample(r: Rect2, c: Vector2, pal: Dictionary) -> void:
		match kind:
			KIND_CAMERA:
				var fan: PackedVector2Array = PackedVector2Array([Vector2(r.position.x + r.size.y * 0.4, c.y),
						Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)])
				draw_colored_polygon(fan, Color(pal["camera"], 0.18))
				fan.append(fan[0])
				draw_polyline(fan, Color(pal["camera"], 0.6), 1.2, true)
				draw_circle(fan[0], r.size.y * 0.36, pal["white"])
				UITheme.draw_icon(self, "camera", Rect2(fan[0] - Vector2.ONE * r.size.y * 0.3, Vector2.ONE * r.size.y * 0.6), pal["camera"], 1.2)
			KIND_ROUTE:
				MapFloorPlan.draw_dashed(self, Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), pal["amber"], maxf(2.0, r.size.y * 0.16), r.size.y * 0.3)
				MapFloorPlan.draw_vent(self, Rect2(c - Vector2(r.size.y, r.size.y) * 0.3, Vector2(r.size.y, r.size.y) * 0.6), pal["amber_dark"], 1.2)
			KIND_PEOPLE:
				var pill: Rect2 = Rect2(Vector2(r.position.x, c.y - r.size.y * 0.36), Vector2(r.size.x, r.size.y * 0.72))
				draw_polygon(UITheme.rounded_rect_points(pill, pill.size.y * 0.5), PackedColorArray([pal["people"]]))
				MapFloorPlan.draw_person(self, Vector2(pill.position.x + pill.size.y * 0.55, c.y), pill.size.y * 0.7, pal["white"])
				MapFloorPlan.draw_person(self, Vector2(pill.position.x + pill.size.y * 1.25, c.y), pill.size.y * 0.7, pal["white"])


## Conmutador de capa: icono arriba, nombre corto debajo y tecla en la esquina (oculta en táctil);
## activo = relleno de tinta. Un tercio de la barra de capas; el nombre completo va en la ayuda emergente.
class LayerChip extends Button:
	var icon_name: String = "camera"
	var hotkey: String = ""
	var caption: String = ""
	var show_hotkey: bool = true
	var _base: float = 16.0

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func restyle(base: float) -> void:
		_base = base
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, empty)
		custom_minimum_size = Vector2(base * 3.0, base * 2.7)
		queue_redraw()

	func _draw() -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var on: bool = button_pressed
		var fg: Color = pal["white"] if on else pal["ink"]
		var bg: Color = pal["ink"] if on else (pal["paper_shade"] if is_hovered() else pal["white"])
		var pts: PackedVector2Array = UITheme.rounded_rect_points(Rect2(Vector2.ONE, size - Vector2(2.0, 2.0)), _base * 0.3)
		draw_polygon(pts, PackedColorArray([bg]))
		pts.append(pts[0])
		draw_polyline(pts, pal["ink"], 2.0, true)
		var s: float = size.y * 0.38
		CutCanvas.draw_layer_glyph(self, icon_name, Rect2(Vector2(size.x * 0.5 - s * 0.5, size.y * 0.13), Vector2(s, s)), fg, pal)
		_draw_caption(fg)
		if show_hotkey and not hotkey.is_empty():
			var cap: Rect2 = Rect2(Vector2(size.x - size.y * 0.42, size.y * 0.09), Vector2(size.y * 0.3, size.y * 0.3))
			draw_rect(cap, pal["amber"] if on else pal["paper_shade"])
			draw_rect(cap, fg, false, 1.2)
			MapFloorPlan.draw_centered(self, UITheme.font(UITheme.FONT_BOLD), cap.get_center(), hotkey, roundi(cap.size.y * 0.72), pal["ink"])

	func _draw_caption(col: Color) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(_base * 0.66)
		while fs > 8 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - _base * 0.5:
			fs -= 1
		MapFloorPlan.draw_centered(self, font, Vector2(size.x * 0.5, size.y * 0.74), caption, fs, col)


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
		var right: float = base * (0.7 if glyph == GLYPH_BACK else 0.9)
		add_theme_stylebox_override("normal", _box(pal["white"], pal["ink"], base, pad, right))
		add_theme_stylebox_override("hover", _box(pal["paper_shade"], pal["ink"], base, pad, right))
		add_theme_stylebox_override("pressed", _box(pal["paper_shade"], pal["ink"], base, pad, right))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			add_theme_color_override(state, pal["ink"])
		add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		add_theme_font_size_override("font_size", roundi(base * 0.78))
		custom_minimum_size = Vector2(base * 2.0, base * 1.75)

	static func _box(bg: Color, border: Color, base: float, pad_l: float, pad_r: float) -> StyleBoxFlat:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(roundi(base * 0.3))
		sb.content_margin_left = pad_l
		sb.content_margin_right = pad_r
		sb.content_margin_top = base * 0.25
		sb.content_margin_bottom = base * 0.25
		return sb

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


## Degradado con chevrón al pie del panel lateral: hay más contenido debajo (se desplaza).
class SideFade extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pal: Dictionary = MapFloorPlan.palette()
		var paper: Color = pal["paper"]
		var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
		draw_polygon(pts, PackedColorArray([Color(paper, 0.0), Color(paper, 0.0), paper, paper]))
		var s: float = size.y * 0.24
		var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.66)
		draw_circle(c, s * 1.6, pal["white"])
		draw_arc(c, s * 1.6, 0.0, TAU, 20, pal["ink_faint"], 1.5, true)
		draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.35), c + Vector2(0.0, s * 0.45), c + Vector2(s, -s * 0.35)]), pal["ink"], maxf(2.0, s * 0.3), true)


## Capa superior del recorte del corte: planta señalada y barra de desplazamiento. Se redibuja sola
## (barato) al señalar o desplazar; el lienzo del corte solo cambia con el modelo o el tamaño.
class CutOverlay extends Control:
	var canvas: CutCanvas

	func _init() -> void:
		name = "CutOverlay"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if canvas != null:
			canvas.draw_overlay(self)


## Corte vertical de la torre (S3..azotea) con la nave anexa: la imagen identificativa del juego.
## Planta = fila; núcleo central continuo (ascensores, escaleras, escalera de servicio, montacargas);
## salas a ambos lados en el orden del plano; fachada (revestimiento, ventanas, forjado y cornisa)
## con la paleta de su banda y retranqueo por banda. La geometría se calcula una vez por tamaño
## (fit) y el desplazamiento solo mueve el lienzo dentro de su recorte.
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
	const SLAB_RATIO := 0.17
	const WALL_RATIO := 0.08
	const CLAD_UNITS := 0.36
	const STREET_UNITS := 0.4
	## Retranqueo total de la banda más baja a la más alta (fracción del ancho de la torre).
	const SETBACK_TOTAL := 0.3
	const COLUMN_WEIGHTS: Dictionary = {"elevator": 0.8, "stairs": 1.2, "service_stairs": 1.2, "freight": 0.8}
	const COLUMN_ORDER: Array[String] = ["elevator", "stairs", "service_stairs", "freight"]
	const LEDGE_TYPE := "roof_ledge"
	## Alto mínimo de fila respecto a la letra base: en móvil las chapas siguen siendo legibles.
	const MIN_ROW_RATIO := 1.3
	const SHADOW_UNITS := 0.16
	const DRAG_SLOP := 12.0
	const WHEEL_ROWS := 1.5
	const DOT_UNITS := 0.16
	const DOT_MIN_RATIO := 0.28
	const TAG_RATIO := 0.62
	const BADGE_RATIO := 0.56
	const SIGN_RATIO := 0.6
	const HELI_UNITS := Vector2(1.9, 0.62)
	const TAG_TRIES := 18

	var view: MapView
	var overlay: CutOverlay
	var hover_floor: int = NO_FLOOR
	var _view_size: Vector2 = Vector2.ZERO
	var _fit_key: Vector3 = Vector3(-1.0, -1.0, -1.0)
	var _dirty: bool = true
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
	var _factory_chip: Rect2 = Rect2()
	var _factory_floor: int = 0
	var _roof: int = 0
	var _lowest: int = 0
	var _scroll: float = 0.0
	var _press_pos: Vector2 = Vector2.INF
	var _dragging: bool = false
	var _auto_scrolled: bool = false

	func _init() -> void:
		name = "Cut"
		mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Tamaño, desplazamiento y geometría ──

	## Encaja el corte en un recorte de `view_size`: fila = alto / plantas, nunca menos que la letra
	## × MIN_ROW_RATIO; si no cabe, el lienzo crece en alto y se desplaza dentro del recorte.
	func fit(view_size: Vector2) -> void:
		var base: float = float(view.base_font())
		var key: Vector3 = Vector3(view_size.x, view_size.y, base)
		if key == _fit_key or view_size.x <= 0.0 or view_size.y <= 0.0:
			return
		_fit_key = key
		_view_size = view_size
		var levels: float = float(_tower_floors().size()) + TOP_UNITS + EARTH_UNITS
		_unit = maxf(view_size.y / levels, base * MIN_ROW_RATIO)
		size = Vector2(view_size.x, maxf(view_size.y, _unit * levels))
		_dirty = true
		queue_redraw()
		scroll_to(_scroll)
		if is_scrollable() and not _auto_scrolled:
			_auto_scrolled = true
			ensure_floor_visible(view.get_player_floor())

	## true si el corte no cabe en alto (texto grande, pantalla de móvil): se desplaza arrastrando.
	func is_scrollable() -> bool:
		return size.y > _view_size.y + 1.0

	func get_scroll() -> float:
		return _scroll

	func get_view_size() -> Vector2:
		return _view_size

	func scroll_by(dy: float) -> void:
		scroll_to(_scroll + dy)

	## Desplazar = mover el lienzo (sin redibujarlo); solo la capa superior se redibuja.
	func scroll_to(value: float) -> void:
		_scroll = clampf(value, 0.0, maxf(0.0, size.y - _view_size.y))
		position = Vector2(0.0, -_scroll)
		if overlay != null:
			overlay.queue_redraw()

	## Centra una planta en vertical si el corte se desplaza.
	func ensure_floor_visible(floor_number: int) -> void:
		_ensure()
		var r: Rect2 = floor_rect(floor_number)
		if is_scrollable() and r.size.y > 0.0:
			scroll_to(r.get_center().y - _view_size.y * 0.5)

	func floor_rect(floor_number: int) -> Rect2:
		_ensure()
		if floor_number == _factory_floor:
			return _factory
		return _rows.get(floor_number, Rect2())

	func block_rect(room_id: String) -> Rect2:
		_ensure()
		return _blocks.get(room_id, Rect2())

	## Planta bajo un punto del lienzo (NO_FLOOR si ninguna). Usa la geometría cacheada.
	func floor_at(pos: Vector2) -> int:
		_ensure()
		for f: int in _rows:
			var row: Rect2 = _rows[f]
			var chip: Rect2 = _chips[f]
			if Rect2(chip.position.x, row.position.y, _cx + _tower_w * 0.5 - chip.position.x, row.size.y).has_point(pos):
				return f
		var on_factory: bool = _factory.grow(_unit * 0.3).has_point(pos) or _factory_chip.has_point(pos)
		return _factory_floor if on_factory else NO_FLOOR

	func _ensure() -> void:
		if _dirty and size.x > 0.0 and size.y > 0.0:
			_dirty = false
			_compute()

	func _tower_floors() -> Array[int]:
		var out: Array[int] = view.get_step_floors()
		out.reverse()
		return out

	func _compute() -> void:
		_factory_floor = Database.get_balance_int(B_FACTORY)
		var floors: Array[int] = _tower_floors()
		if floors.is_empty():
			return
		_roof = floors[0]
		_lowest = floors[floors.size() - 1]
		var left_w: float = _unit * (BRACKET_UNITS + CHIP_UNITS + GAP_UNITS)
		var gap: float = _unit * GAP_UNITS
		var rest: float = maxf(size.x - left_w - _unit * ASSEMBLY_UNITS - gap * 2.0, _unit * 10.0)
		_tower_w = minf(rest * TOWER_SHARE / (TOWER_SHARE + FACTORY_SHARE), _unit * TOWER_MAX_UNITS)
		var factory_w: float = minf(rest - _tower_w, _unit * FACTORY_MAX_UNITS)
		var group_w: float = left_w + _tower_w + factory_w + _unit * ASSEMBLY_UNITS + gap * 2.0
		_x0 = maxf(0.0, (size.x - group_w) * 0.5)
		_cx = _x0 + left_w + _tower_w * 0.5
		_compute_rows(floors)
		_compute_annex(factory_w, gap)
		_compute_core()
		_compute_blocks()

	func _compute_rows(floors: Array[int]) -> void:
		_rows.clear()
		_chips.clear()
		for i: int in floors.size():
			var w: float = _tower_w * _band_ratio(floors[i])
			var y: float = _unit * (TOP_UNITS + float(i))
			_rows[floors[i]] = Rect2(_cx - w * 0.5, y, w, _unit)
			_chips[floors[i]] = Rect2(_x0 + _unit * BRACKET_UNITS, y + _unit * 0.1, _unit * CHIP_UNITS, _unit * 0.8)
		_ground_y = (_rows.get(0, _rows[_roof]) as Rect2).end.y

	func _compute_annex(factory_w: float, gap: float) -> void:
		var h: float = _unit * FACTORY_H_UNITS
		var pb: Rect2 = _rows.get(0, Rect2(_cx, _ground_y, 0.0, 0.0))
		_factory = Rect2(pb.end.x + gap, _ground_y - h, factory_w, h)
		_factory_body = Rect2(_factory.position.x, _factory.position.y + _unit * FACTORY_ROOF_UNITS, factory_w, h - _unit * FACTORY_ROOF_UNITS)
		_assembly = Rect2(_factory.end.x + gap, _ground_y - _unit * 2.2, _unit * ASSEMBLY_UNITS, _unit * 2.2)
		var chip_x: float = maxf(_factory.position.x, (_rows[_lowest] as Rect2).end.x + _unit * 0.6)
		_factory_chip = Rect2(chip_x, _ground_y + _unit * (STREET_UNITS + 0.3), _unit * CHIP_UNITS * 1.25, _unit * 0.8)

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
			var inner: Rect2 = _row_inner(_rows[f])
			var ids: Array[String] = view.get_cut_room_ids(f)
			var split: int = _split_index(f, ids, inner)
			_place_segment(f, ids.slice(0, split), inner.position.x, _core.x - _wall())
			_place_segment(f, ids.slice(split), _core.y + _wall(), inner.end.x)
		var body: Rect2 = _factory_body.grow(-_wall())
		_place_segment(_factory_floor, view.get_cut_room_ids(_factory_floor), body.position.x, body.end.x)

	## Interior de una fila: entre los revestimientos de fachada y sobre el forjado.
	func _row_inner(row: Rect2) -> Rect2:
		var side: float = _clad() + _wall() * 0.3
		var w: float = _wall()
		return Rect2(row.position.x + side, row.position.y + w * 0.5, row.size.x - side * 2.0, row.size.y - _slab() - w * 0.5)

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

	## Ancho relativo de la banda de una planta: retranqueo lineal por orden de banda (art_bands.json).
	func _band_ratio(f: int) -> float:
		var order: Array[String] = MapView.tower_band_order()
		var i: int = order.find(UITheme.band_id_for_floor(f))
		if i < 0 or order.size() < 2:
			return 1.0
		return 1.0 - SETBACK_TOTAL * float(i) / float(order.size() - 1)

	func _wall() -> float:
		return maxf(1.5, _unit * WALL_RATIO)

	func _slab() -> float:
		return maxf(2.5, _unit * SLAB_RATIO)

	func _clad() -> float:
		return maxf(_wall() * 2.5, _unit * CLAD_UNITS)

	func _layer(layer: String) -> bool:
		return view.is_layer_on(layer)

	# ── Dibujo ──

	func _draw() -> void:
		_ensure()
		if _rows.is_empty():
			return
		var pal: Dictionary = MapFloorPlan.palette()
		_draw_ground(pal)
		_draw_shadow(pal)
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
		_draw_markers(pal)

	## Capa superior (CutOverlay): planta señalada y barra de desplazamiento, en coordenadas del recorte.
	func draw_overlay(ci: CanvasItem) -> void:
		_ensure()
		var pal: Dictionary = MapFloorPlan.palette()
		_draw_selection(ci, pal)
		_draw_scrollbar(ci, pal)

	## Sombra plana del edificio sobre el papel (profundidad sin perspectiva).
	func _draw_shadow(pal: Dictionary) -> void:
		var off: Vector2 = Vector2(_unit, _unit) * SHADOW_UNITS
		for f: int in _rows:
			if f >= 0:
				draw_rect(Rect2((_rows[f] as Rect2).position + off, (_rows[f] as Rect2).size), pal["shadow"])
		draw_rect(Rect2(_factory_body.position + off, _factory_body.size), pal["shadow"])

	func _draw_scrollbar(ci: CanvasItem, pal: Dictionary) -> void:
		if not is_scrollable():
			return
		var w: float = maxf(5.0, _unit * 0.16)
		var track: Rect2 = Rect2(_view_size.x - w, 0.0, w, _view_size.y)
		var thumb_h: float = _view_size.y * _view_size.y / size.y
		var thumb: Rect2 = Rect2(track.position.x, (_view_size.y - thumb_h) * _scroll / maxf(1.0, size.y - _view_size.y), w, thumb_h)
		ci.draw_rect(track, Color(pal["ink_faint"], 0.35))
		ci.draw_polygon(UITheme.rounded_rect_points(thumb, w * 0.5), PackedColorArray([pal["ink_soft"]]))

	## Planta señalada: marco de tinta con halo blanco sobre la fila y la chapa, y puntero.
	func _draw_selection(ci: CanvasItem, pal: Dictionary) -> void:
		var off: Vector2 = position
		var col: Color = pal["select"]
		if hover_floor == _factory_floor:
			var factory: Rect2 = Rect2(_factory.position + off, _factory.size).grow(_wall() * 1.5)
			ci.draw_rect(factory.grow(_wall()), pal["white"], false, _wall() * 1.4)
			ci.draw_rect(factory, col, false, _wall() * 1.4)
			return
		if not _rows.has(hover_floor):
			return
		var row: Rect2 = Rect2((_rows[hover_floor] as Rect2).position + off, (_rows[hover_floor] as Rect2).size)
		var chip: Rect2 = Rect2((_chips[hover_floor] as Rect2).position + off, (_chips[hover_floor] as Rect2).size)
		ci.draw_rect(row.grow(_wall() * 2.4), pal["white"], false, _wall() * 1.6)
		ci.draw_rect(row.grow(_wall() * 1.2), col, false, _wall() * 1.6)
		ci.draw_rect(chip.grow(2.5), pal["white"], false, 2.0)
		ci.draw_rect(chip.grow(1.5), col, false, 2.5)
		var tip: Vector2 = Vector2(chip.position.x - _unit * 0.12, chip.get_center().y)
		var tri: PackedVector2Array = PackedVector2Array([tip, tip + Vector2(-_unit * 0.32, -_unit * 0.22), tip + Vector2(-_unit * 0.32, _unit * 0.22)])
		ci.draw_colored_polygon(tri, col)

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
		_draw_cladding(f, row, band)
		var slab: Rect2 = Rect2(row.position.x + _wall(), row.end.y - _slab() + _wall() * 0.35, row.size.x - _wall() * 2.0, _slab() - _wall() * 0.7)
		draw_rect(slab, Color(str(band.get("floor", "#8a8f7d"))))
		_draw_blocks(f, pal)

	## Revestimiento de fachada a ambos lados de la fila con la paleta de su banda: muro, ventana
	## (sobre rasante) y remate de acento. Así se leen las cinco bandas en el corte (§14.3).
	func _draw_cladding(f: int, row: Rect2, band: Dictionary) -> void:
		var strip_w: float = _clad() - _wall() * 0.6
		var h: float = row.size.y - _slab() - _wall() * 0.5
		var wall: Color = Color(str(band.get("wall", "#b5b8a8")))
		var glass: Color = Color(str(band.get("window", "#a8d2f4")))
		var accent: Color = Color(str(band.get("accent", "#888888")))
		for x: float in [row.position.x + _wall() * 0.6, row.end.x - _wall() * 0.6 - strip_w]:
			var strip: Rect2 = Rect2(x, row.position.y + _wall() * 0.5, strip_w, h)
			draw_rect(strip, wall)
			if f >= 0:
				draw_rect(strip.grow_individual(-strip.size.x * 0.22, -strip.size.y * 0.2, -strip.size.x * 0.22, -strip.size.y * 0.24), glass)
			draw_rect(Rect2(strip.position, Vector2(strip.size.x, maxf(1.5, _unit * 0.07))), accent)

	func _draw_blocks(f: int, pal: Dictionary) -> void:
		var spacing: float = maxf(5.0, _unit * 0.26)
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
		draw_rect(Rect2(_core.x - _wall(), row.position.y - _wall() * 0.5, _core.y - _core.x + _wall() * 2.0, row.size.y), pal["ink"])
		draw_rect(Rect2(row.position.x, row.end.y - _slab() - para_h, _wall() * 1.2, para_h), pal["ink"])
		draw_rect(Rect2(row.end.x - _wall() * 1.2, row.end.y - _slab() - para_h, _wall() * 1.2, para_h), pal["ink"])
		for id: String in view.get_cut_room_ids(_roof):
			if not _blocks.has(id):
				continue
			var r: Rect2 = _blocks[id]
			var room: RoomData = Database.get_room(id)
			if room != null and not room.illegitimate_entries.has(MapView.ENTRY_VENT) and r.size.x > _unit * 3.0:
				_draw_terrace(r, view.get_room_status(id), band, pal)
			else:
				draw_rect(r.grow(_wall() * 0.6), pal["ink"])
				MapFloorPlan.draw_status_block(self, r, view.get_room_status(id), pal, maxf(4.0, _unit * 0.2), 1.0)
		_draw_mast(pal)

	## Terraza al aire libre: cubierta con el estado de acceso, barandilla y el helicóptero de la
	## dirección aparcado en su helipuerto.
	func _draw_terrace(r: Rect2, status: int, band: Dictionary, pal: Dictionary) -> void:
		var deck: Rect2 = Rect2(r.position.x, r.end.y - r.size.y * 0.42, r.size.x, r.size.y * 0.42)
		MapFloorPlan.draw_status_block(self, deck, status, pal, maxf(4.0, _unit * 0.2), 1.0)
		draw_rect(deck, MapFloorPlan.status_ink(status, pal), false, 1.5)
		var rail_y: float = r.end.y - r.size.y * 0.72
		draw_line(Vector2(r.position.x, rail_y), Vector2(r.end.x, rail_y), pal["ink_soft"], 1.5)
		var post: float = r.position.x
		while post <= r.end.x:
			draw_line(Vector2(post, rail_y), Vector2(post, deck.position.y), pal["ink_soft"], 1.0)
			post += _unit * 0.35
		var hs: Vector2 = Vector2(minf(_unit * HELI_UNITS.x, r.size.x * 0.6), _unit * HELI_UNITS.y)
		var heli: Rect2 = Rect2(Vector2(r.get_center().x - hs.x * 0.5, deck.position.y - hs.y), hs)
		draw_rect(Rect2(heli.position.x - _unit * 0.1, deck.position.y - 1.0, hs.x + _unit * 0.2, maxf(2.0, _unit * 0.08)), pal["amber"])
		MapFloorPlan.draw_helicopter(self, heli, pal["ink"], Color(str(band.get("window", "#cde7f6"))))

	## Mástil con luz de balizamiento y el rótulo de la empresa sobre la azotea.
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
		var fs: int = maxi(roundi(float(view.base_font()) * SIGN_RATIO), roundi(_unit * 0.4))
		var text: String = tr("UI_COMPANY_NAME")
		var sign_h: float = float(fs) * 1.55
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sign_h * 1.2
		var sign_rect: Rect2 = Rect2(_core.x - tw * 0.6, base_y - _unit * 0.22 - sign_h, tw, sign_h)
		draw_line(Vector2(sign_rect.get_center().x, sign_rect.end.y), Vector2(sign_rect.get_center().x, base_y), pal["ink"], 2.0)
		draw_polygon(UITheme.rounded_rect_points(sign_rect, sign_h * 0.18), PackedColorArray([pal["ink"]]))
		var star: float = sign_h * 0.62
		UITheme.draw_icon(self, "star", Rect2(sign_rect.position + Vector2(sign_h * 0.22, (sign_h - star) * 0.5), Vector2(star, star)), pal["amber"], 1.5)
		draw_string(font, Vector2(sign_rect.position.x + sign_h * 0.95, sign_rect.get_center().y + font.get_ascent(fs) * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["white"])

	## Núcleo: huecos de ascensor (con cabinas), tramos de escalera con flechas de evacuación y
	## hormigón donde el hueco no llega.
	func _draw_core(pal: Dictionary) -> void:
		for col: Dictionary in _columns:
			for f: int in _rows:
				var row: Rect2 = _rows[f]
				var cell: Rect2 = Rect2(float(col["x0"]), row.position.y, float(col["x1"]) - float(col["x0"]), row.size.y - _slab())
				if f >= int(col["lo"]) and f <= int(col["hi"]):
					_draw_shaft_cell(col, f, cell.grow_individual(-_wall() * 0.35, -_wall() * 0.5, -_wall() * 0.35, 0.0), pal)
				else:
					_draw_concrete(cell, pal)
			_draw_cabins(col, pal)

	## Hormigón cortado (gris con rayado), convención de sección: donde el hueco no llega.
	func _draw_concrete(r: Rect2, pal: Dictionary) -> void:
		draw_rect(r, pal["concrete"])
		MapFloorPlan.draw_hatch(self, r, pal["ink_faint"], maxf(4.0, _unit * 0.2), 1.0, MapFloorPlan.HATCH_BACKSLASH)

	func _draw_shaft_cell(col: Dictionary, f: int, cell: Rect2, pal: Dictionary) -> void:
		var kind: String = str(col["kind"])
		if kind == "elevator" or kind == "freight":
			draw_rect(cell, pal["paper_shade"])
			var rail: float = cell.size.x * 0.18
			draw_line(Vector2(cell.position.x + rail, cell.position.y), Vector2(cell.position.x + rail, cell.end.y), pal["ink_faint"], 1.0)
			draw_line(Vector2(cell.end.x - rail, cell.position.y), Vector2(cell.end.x - rail, cell.end.y), pal["ink_faint"], 1.0)
			return
		draw_rect(cell, pal["white"])
		_draw_flights(cell, pal, posmod(f, 2) == 1)
		if kind != "stairs":
			return
		var up: bool = f < 0
		var c: Vector2 = MapFloorPlan._u(cell, 0.5, 0.3)
		var d: float = minf(cell.size.x, cell.size.y) * 0.2
		var tip: Vector2 = c + Vector2(0.0, -d if up else d)
		var tri: PackedVector2Array = PackedVector2Array([tip, c + Vector2(-d, (d if up else -d) * 0.3), c + Vector2(d, (d if up else -d) * 0.3)])
		draw_colored_polygon(tri, pal["green"])

	## Escalera de ida y vuelta en sección: tramo delantero con peldaños, meseta y tramo trasero
	## discontinuo; el sentido alterna de una planta a la siguiente (zigzag continuo).
	func _draw_flights(cell: Rect2, pal: Dictionary, mirrored: bool) -> void:
		var inset: float = cell.size.x * 0.1
		var x0: float = cell.position.x + inset
		var x1: float = cell.end.x - inset
		var bottom: float = cell.end.y
		var mid: float = cell.position.y + cell.size.y * 0.5
		var steps: int = 4
		var pts: PackedVector2Array = PackedVector2Array([Vector2(x0, bottom)])
		for i: int in steps:
			var y: float = lerpf(bottom, mid, float(i + 1) / float(steps))
			pts.append(Vector2(lerpf(x0, x1 - inset, float(i) / float(steps)), y))
			pts.append(Vector2(lerpf(x0, x1 - inset, float(i + 1) / float(steps)), y))
		pts.append(Vector2(x1, mid))
		var back: PackedVector2Array = PackedVector2Array([Vector2(x1 - inset, mid), Vector2(x0, cell.position.y)])
		if mirrored:
			var axis: float = cell.position.x + cell.end.x
			for i: int in pts.size():
				pts[i].x = axis - pts[i].x
			for i: int in back.size():
				back[i].x = axis - back[i].x
		var w: float = maxf(1.2, _unit * 0.05)
		draw_polyline(pts, pal["ink_soft"], w, true)
		MapFloorPlan.draw_dashed(self, back[0], back[1] + Vector2(0.0, w), pal["ink_faint"], w, maxf(2.0, _unit * 0.08))

	## Cabinas: la del primer ascensor en la planta del jugador (en PB si está fuera de la torre), el
	## resto en PB (o en el extremo de su recorrido).
	func _draw_cabins(col: Dictionary, pal: Dictionary) -> void:
		if str(col["kind"]) != "elevator" and str(col["kind"]) != "freight":
			return
		var lo: int = int(col["lo"])
		var hi: int = int(col["hi"])
		var at: int = int(view.get_player_floor()) if int(col["index"]) == 0 else 0
		if at < lo or at > hi:
			at = clampi(0, lo, hi)
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
		var h: float = maxf(3.0, _unit * 0.14)
		for f: int in _rows:
			if f == _roof or f < 0:
				continue
			var above: int = f + 1
			if _rows.has(above) and UITheme.band_id_for_floor(above) == UITheme.band_id_for_floor(f):
				continue
			var row: Rect2 = _rows[f]
			var accent: Color = Color(str(UITheme.band_palette_for_floor(f).get("accent", "#888888")))
			var cornice: Rect2 = Rect2(row.position.x - h, row.position.y - h * 0.6, row.size.x + h * 2.0, h)
			draw_rect(cornice, accent)
			draw_rect(cornice, pal["ink"], false, 1.0)

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
		draw_chip(self, _factory_chip, view.get_floor_status(_factory_floor), MapView.floor_label_short(_factory_floor), UITheme.font(UITheme.FONT_BOLD), _chip_font(), pal, view.is_floor_foothold(_factory_floor))

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
		var fs: int = maxi(10, roundi(minf(_unit * 0.36, float(view.base_font()) * 0.62)))
		var label: String = tr("MAP_ASSEMBLY_POINT")
		var lines: PackedStringArray = MapFloorPlan._wrap(label, font, fs, _assembly.size.x * 1.3)
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
				_camera_glyph(Vector2(_core.y + s * 0.75, (_rows[f] as Rect2).position.y + s * 0.62), s, pal)

	func _camera_glyph(at: Vector2, s: float, pal: Dictionary) -> void:
		draw_circle(at, s * 0.5, pal["white"])
		draw_arc(at, s * 0.5, 0.0, TAU, 16, pal["camera"], 1.2, true)
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

	## Ocupación por franja: una pastilla «figura + número» por sala (legible también en móvil).
	func _draw_occupancy(pal: Dictionary) -> void:
		var band: String = view.get_band()
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(9, roundi(minf(_unit * 0.42, float(view.base_font()) * BADGE_RATIO)))
		for id: String in _blocks:
			var room: RoomData = Database.get_room(id)
			var count: int = room.get_occupants(band) if room != null else 0
			if count <= 0:
				continue
			var r: Rect2 = _blocks[id]
			var bs: Vector2 = MapFloorPlan.people_badge_size(count, font, fs)
			if bs.x > r.size.x - 2.0:
				continue
			bs.y = minf(bs.y, r.size.y - 2.0)
			MapFloorPlan.draw_people_badge(self, Rect2(Vector2(r.position.x + 1.0, r.end.y - bs.y - 1.0), bs), count, font, fs, pal)

	# ── Personas, chapas, bandas, marcadores ──

	## Radio de los puntos: proporcional a la fila, nunca menor que la letra base × DOT_MIN_RATIO.
	func dot_radius() -> float:
		return maxf(_unit * DOT_UNITS, float(view.base_font()) * DOT_MIN_RATIO)

	func _draw_dots(pal: Dictionary) -> void:
		for dot: Dictionary in view.get_visible_dots():
			if bool(dot.get("target", false)):
				continue
			var at: Vector2 = dot_point(str(dot.get("room_id", "")), int(dot.get("floor", NO_FLOOR)), str(dot.get("npc_id", "")))
			if at.is_finite():
				MapFloorPlan.draw_npc_dot(self, at, dot_radius(), pal, false, bool(dot.get("approximate", false)))

	## Punto de una persona en el corte: dentro del bloque de su sala o, en circulación, en su fila.
	func dot_point(room_id: String, f: int, key: String) -> Vector2:
		_ensure()
		if _blocks.has(room_id):
			var r: Rect2 = _blocks[room_id]
			var p: Vector2 = MapFloorPlan.dot_position(r, key)
			return Vector2(p.x, r.end.y - r.size.y * (0.3 + 0.25 * fposmod(p.y, 1.0)))
		if not _rows.has(f):
			return Vector2.INF
		var row: Rect2 = _row_inner(_rows[f])
		var span: Rect2 = Rect2(row.position.x, row.position.y, _core.x - row.position.x, row.size.y)
		return Vector2(MapFloorPlan.dot_position(span, key).x, row.end.y - row.size.y * 0.3)

	## Objetivos marcados (mira + etiqueta con el nombre) y «usted está aquí», lo último y sin
	## solaparse: las etiquetas van a la derecha de la torre y esquivan la nave y entre sí.
	func _draw_markers(pal: Dictionary) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var taken: Array[Rect2] = [_factory.grow(_unit * 0.25), _assembly.grow(_unit * 0.2), _factory_chip.grow(_unit * 0.1)]
		var you: Dictionary = _you_box(font, taken)
		if not you.is_empty():
			taken.append(you["box"])
		var fs: int = maxi(10, roundi(minf(_unit * 0.46, float(view.base_font()) * TAG_RATIO)))
		for dot: Dictionary in view.get_target_dots():
			var f: int = int(dot.get("floor", NO_FLOOR))
			var at: Vector2 = dot_point(str(dot.get("room_id", "")), f, str(dot.get("npc_id", "")))
			if not at.is_finite():
				continue
			var approx: bool = bool(dot.get("approximate", false))
			var text: String = UITheme.trf("MAP_TARGET_APPROX_FMT", [dot.get("name", "")]) if approx else str(dot.get("name", ""))
			var box: Rect2 = _place_box(f, at, MapFloorPlan.tag_size(text, font, fs), taken)
			taken.append(box)
			MapFloorPlan.draw_tag(self, at, box, text, font, fs, pal)
			MapFloorPlan.draw_target_marker(self, at, dot_radius(), pal, approx)
		if not you.is_empty():
			MapFloorPlan.draw_callout(self, you["at"], (you["box"] as Rect2).position, you["text"], font, int(you["fs"]), pal)
			MapFloorPlan.draw_pin(self, you["at"], maxf(dot_radius() * 1.1, _unit * 0.22), pal)

	func _you_box(font: Font, taken: Array[Rect2]) -> Dictionary:
		var f: int = view.get_player_floor()
		var at: Vector2 = dot_point(view.get_player_room(), f, "player")
		if not at.is_finite():
			return {}
		var fs: int = maxi(9, roundi(minf(_unit * 0.46, float(view.base_font()) * 0.8)))
		var text: String = tr("MAP_YOU_ARE_HERE")
		var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var box: Rect2 = _place_box(f, at, ts + Vector2(fs * 1.1, fs * 0.6), taken)
		return {"at": at, "box": box, "text": text, "fs": fs}

	## Coloca una etiqueta a la derecha de la fila (sobre la nave si es la nave): a su altura o, si pisa
	## algo de `taken`, subiendo fila a fila (la mitad de los intentos) y después bajando.
	func _place_box(f: int, at: Vector2, bs: Vector2, taken: Array[Rect2]) -> Rect2:
		var origin: Vector2 = Vector2((_rows.get(f, _factory) as Rect2).end.x + _unit * 0.7, at.y - bs.y * 0.5)
		if f == _factory_floor:
			origin = Vector2(_factory.position.x + _unit * 0.4, _factory.position.y - _unit * 0.8 - bs.y)
		origin.x = minf(origin.x, size.x - bs.x - 2.0)
		var step: float = bs.y + _unit * 0.12
		for i: int in TAG_TRIES:
			var k: int = -i if i <= TAG_TRIES / 2 else i - TAG_TRIES / 2
			var box: Rect2 = Rect2(origin + Vector2(0.0, step * float(k)), bs)
			if box.position.y >= 0.0 and box.end.y <= size.y and not _hits(box, taken):
				return box
		return Rect2(origin, bs)

	static func _hits(box: Rect2, taken: Array[Rect2]) -> bool:
		for other: Rect2 in taken:
			if box.intersects(other):
				return true
		return false

	func _chip_font() -> int:
		return maxi(9, roundi(minf(_unit * 0.5, float(view.base_font()))))

	func _draw_chips(pal: Dictionary) -> void:
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		for f: int in _chips:
			draw_chip(self, _chips[f], view.get_floor_status(f), MapView.floor_label_short(f), font, _chip_font(), pal, view.is_floor_foothold(f))

	## Chapa de planta: color de estado, número y glifo de forma (✓ / ! / ✕), accesible sin color.
	## foothold: roja con el «!» sobre placa ámbar (solo el cuarto de servicio es alcanzable).
	static func draw_chip(ci: CanvasItem, r: Rect2, status: int, text: String, font: Font, fs: int, pal: Dictionary,
			foothold: bool = false) -> void:
		var fill: int = MapFloorPlan.ACCESS_FORBIDDEN if foothold else status
		ci.draw_polygon(UITheme.rounded_rect_points(r, r.size.y * 0.22), PackedColorArray([MapFloorPlan.status_ink(fill, pal)]))
		var g: float = r.size.y * 0.52
		var glyph: Rect2 = Rect2(Vector2(r.end.x - g - r.size.y * 0.2, r.get_center().y - g * 0.5), Vector2(g, g))
		if text.is_empty():
			glyph.position.x = r.get_center().x - g * 0.5
		if foothold:
			var plate: Rect2 = glyph.grow(r.size.y * 0.1)
			ci.draw_polygon(UITheme.rounded_rect_points(plate, plate.size.y * 0.25), PackedColorArray([pal["amber"]]))
			draw_status_glyph(ci, glyph, MapFloorPlan.ACCESS_ALTERNATIVE, pal["ink"])
		else:
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
		return MapFloorPlan.band_ink(UITheme.band_palette_for_floor(f))

	func _draw_brackets(pal: Dictionary) -> void:
		var spans: Dictionary = {}
		for f: int in _rows:
			var band: String = UITheme.band_id_for_floor(f)
			var r: Rect2 = _rows[f]
			var span: Vector2 = spans.get(band, Vector2(r.position.y, r.end.y))
			spans[band] = Vector2(minf(span.x, r.position.y), maxf(span.y, r.end.y))
		var font: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = maxi(9, roundi(minf(_unit * 0.38, float(view.base_font()) * 0.7)))
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

	# ── Entrada ──

	## Pasar el ratón señala la planta; clic o toque sin arrastre la amplía; arrastre o rueda desplazan.
	## Con la emulación de ratón desde el táctil (ajuste del proyecto) cada movimiento del dedo llega
	## también como ratón con el botón izquierdo: entonces solo cuenta ese, nunca los dos.
	func _gui_input(event: InputEvent) -> void:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			if _press_pos.is_finite() and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				_drag(motion.position, motion.relative.y)
			else:
				_set_hover(floor_at(motion.position))
			return
		var touch_drag: InputEventScreenDrag = event as InputEventScreenDrag
		if touch_drag != null:
			if not UITheme.touch_emulates_mouse():
				_drag(touch_drag.position, touch_drag.relative.y)
			return
		var wheel: InputEventMouseButton = event as InputEventMouseButton
		if wheel != null and wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scroll_by(_unit * WHEEL_ROWS * (-1.0 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
			accept_event()
		elif UITheme.is_primary_press(event):
			_press_pos = _event_pos(event) + position
			_dragging = false
			accept_event()
		elif _is_primary_release(event):
			_release(_event_pos(event))
			accept_event()

	## Arrastre: la distancia se mide en coordenadas del recorte (el lienzo se mueve bajo el dedo).
	func _drag(pos: Vector2, dy: float) -> void:
		if not _press_pos.is_finite():
			return
		_dragging = _dragging or (pos + position).distance_to(_press_pos) > DRAG_SLOP
		if _dragging:
			scroll_by(-dy)

	func _release(pos: Vector2) -> void:
		var tapped: bool = _press_pos.is_finite() and not _dragging
		_press_pos = Vector2.INF
		var f: int = floor_at(pos) if tapped else NO_FLOOR
		if f != NO_FLOOR:
			_set_hover(f)
			floor_clicked.emit(f)

	static func _event_pos(event: InputEvent) -> Vector2:
		if event is InputEventMouseButton:
			return (event as InputEventMouseButton).position
		if event is InputEventScreenTouch:
			return (event as InputEventScreenTouch).position
		return Vector2.INF

	static func _is_primary_release(event: InputEvent) -> bool:
		if event is InputEventScreenTouch:
			return not (event as InputEventScreenTouch).pressed and not UITheme.touch_emulates_mouse()
		var mb: InputEventMouseButton = event as InputEventMouseButton
		return mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT

	func _set_hover(f: int) -> void:
		if f == hover_floor or f == NO_FLOOR:
			return
		hover_floor = f
		floor_hovered.emit(f)
		if overlay != null:
			overlay.queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
			_dirty = true
			queue_redraw()
