# _places_keeper.gd — Nodo de escena del módulo de lugares: interactivos propios (mesa del clan, futbolín, cola de los tornos, puertas de viviendas), colarse en los tornos, citación ineludible, avisos de escenas, traje de estatus, quemaduras y las viviendas cerradas.
# PROPIETARIO DE: los interactivos del módulo en la planta cargada, la intención de colarse (puerta y segundos) y la escolta en curso. Lo persistente vive en banderas places.* de PlayerState.
# ESCUCHA: FloorStreamer.floor_loaded, room_entered, hour_passed, day_advanced, results_presentation_due, aurora_meeting_started, run_loaded, floor_changed (vía hook).
class_name PlacesKeeper
extends Node

## ensure(tree) lo crea bajo GameRoot si falta (al cargarse el módulo, hook() diferido; en cada
## interacción; al cargar partida; al cambiar de planta). Reglas:
##  · INTERACTIVOS PROPIOS (grupo NODES_GROUP, se rehacen en cada planta): lugares.mesas (la mesa
##    del clan en la cafetería, el futbolín de P4, el sofá de los compradores) sobre su mueble,
##    desplazados «lado» celdas hacia donde se pone el jugador (sin sillas); la cola de los tornos
##    (lugares.torno.celda_cola, lejos del sensor); una "house_door" en la calle ante cada vivienda.
##  · COLARSE (§5.6 «acceder tras otro empleado»): decora la política de puertas de DoorAccess. En
##    un torno, en las franjas de lugares.torno.franjas_colarse, con un compañero cerca del torno
##    y la intención del jugador (entrar sigiloso/agachado o la cola: allow_tailgate) el torno se
##    abre SIN armar el registro: no hay card_log (la cámara del vestíbulo sigue grabando).
##  · CITACIÓN INELUDIBLE: WorldBridges ejecuta la citación dentro del edificio; si el jugador la
##    esquiva fuera (planta exterior) en horario laboral desde lugares.citacion.hora_recogida, dos
##    vigilantes van a buscarlo: diálogo sin cancelar → sala de interrogatorios → InterrogationScene
##    → vuelta a donde estaba. due_summons() también lo usa la mesa de interrogatorios.
##  · AVISOS: results_presentation_due para R28+ (estrado de P16); aurora_meeting_started si el
##    jugador tiene acceso a la sala Aurora.
##  · TRAJE (economia.penalizacion_reputacion_sin_traje): cada cambio de jornada, desde
##    lugares.traje.escalon_minimo y sin el traje ejecutivo (bandera places.suit_owned o llevarlo),
##    la reputación baja. Comprarlo en la tienda de ropa lo quita.
##  · QUEMADURA (laboratorio de tintes, error al sabotear): bandera places.burn. Cada hora de
##    trabajo en el edificio, alguien de la sala del jugador la ve (creencia seen_partially:
##    chemical_burn, certeza lugares.quimico.certeza_herida, en el laboratorio). La enfermería la
##    cura; sola se cura en lugares.quimico.dias_herida jornadas.
##  · VIVIENDAS (NightOps): sin allanamiento en curso la puerta está cerrada (quien entra vuelve a
##    la calle con aviso); salir andando de la vivienda allanada cierra la operación (leave_house).

const GROUP := "places_keeper"
const NODES_GROUP := "places_nodes"
const QUEUE_TYPE := "turnstile_queue"
const HOUSE_DOOR_TYPE := "house_door"
const QUEUE_ID := "places_turnstile_queue"
const HOUSE_DOOR_FORMAT := "places_door_%s"
const TABLE_ID_FORMAT := "places_%s"
const K_TYPE := "tipo"
const K_ROOM := "sala"
const K_PIECE := "mueble"
const K_POS := "pos"
const K_SIDE := "lado"
const K_GATHERING := "corrillo"
const K_HOUSE := "house"
const F_SUIT := "places.suit_owned"
const F_BURN := "places.burn"
const BURN_FACT := "seen_partially:chemical_burn"
const REP_REASON_SUIT := "no_executive_suit"
const NOTE_CATEGORY := "places"
const ESCORT_LOCK := "places_escort"
const RIDE_LOCK := "places_ride"
const B_ENTRANCE := "viaje.trayecto.entrada_edificio"
## Celdas que se miran a cada lado de una puerta para colocar al jugador.
const DOOR_DEPTH := 2
const B_TABLES := "lugares.mesas"
const B_QUEUE_ROOM := "lugares.torno.sala"
const B_QUEUE_CELL := "lugares.torno.celda_cola"
const B_RADIUS := "lugares.torno.radio_colarse_celdas"
const B_PICKUP_HOUR := "lugares.citacion.hora_recogida"
const B_ESCORT_MINUTES := "lugares.citacion.minutos_escolta"
const B_POLL := "lugares.citacion.segundos_sondeo"
const B_RESULTS_RANK := "lugares.resultados.rango_minimo"
const B_SUIT_ITEM := "lugares.traje.objeto"
const B_SUIT_TIER := "lugares.traje.escalon_minimo"
const B_SUIT_PENALTY := "economia.penalizacion_reputacion_sin_traje"
const B_BURN_CERTAINTY := "lugares.quimico.certeza_herida"
const B_BURN_DAYS := "lugares.quimico.dias_herida"
const B_INTERROGATION_ROOM := "puentes.sala_interrogatorio"
const B_EXTERIOR := "mundo.planta_exterior"
const B_STREET := "viaje.trayecto.sala_calle"
const AURORA_ROOM := "aurora_room"

static var _hooked: bool = false
static var _last_aurora_key: String = ""

## Pruebas y QA: fundidos de un fotograma.
var instant: bool = false
var _root: GameRoot = null
var _overlay: FloorTravel.TravelOverlay = null
var _streamer: FloorStreamer = null
var _player: Player = null
var _base_policy: Callable = Callable()
var _intent_door: String = ""
var _intent_left: float = 0.0
var _poll_left: float = 0.0
var _escorting: bool = false
var _last_room: String = ""


static func find(tree: SceneTree) -> PlacesKeeper:
	return tree.get_first_node_in_group(GROUP) as PlacesKeeper if tree != null else null


## El keeper de la escena de juego (lo crea si falta; null si no hay GameRoot montado).
static func ensure(tree: SceneTree) -> PlacesKeeper:
	hook()
	var keeper: PlacesKeeper = find(tree)
	if keeper != null or tree == null:
		return keeper
	var root: GameRoot = GameRoot.find(tree)
	if root == null or root.streamer == null or root.player == null or root.doors == null:
		return null
	keeper = PlacesKeeper.new()
	keeper.name = "PlacesKeeper"
	root.add_child(keeper)
	keeper.setup(root)
	return keeper


## Engancha el bus una sola vez por proceso: una carga o un cambio de planta despiertan al keeper.
static func hook() -> void:
	if _hooked or Engine.is_editor_hint():
		return
	_hooked = true
	EventBus.run_loaded.connect(func(_day: int) -> void: ensure(Engine.get_main_loop() as SceneTree))
	EventBus.floor_changed.connect(func(_a: int, _b: int) -> void: ensure(Engine.get_main_loop() as SceneTree))
	(func() -> void: ensure(Engine.get_main_loop() as SceneTree)).call_deferred()


func _ready() -> void:
	add_to_group(GROUP)


func setup(root: GameRoot) -> void:
	_root = root
	_streamer = root.streamer
	_player = root.player
	_base_policy = root.doors.policy
	_streamer.set_door_policy(_gate_policy)
	_streamer.floor_loaded.connect(func(_floor: int) -> void: sync_floor())
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.results_presentation_due.connect(_on_results_due)
	EventBus.aurora_meeting_started.connect(_on_aurora_started)
	_last_room = PlayerState.get_room()
	sync_floor()


func ctx() -> Dictionary:
	return {"game_root": _root, "ui_root": _root.ui if _root != null else null, "streamer": _streamer,
			"room_id": PlayerState.get_room(), "floor": _streamer.get_current_floor() if _streamer != null else 0}


func _process(delta: float) -> void:
	if _intent_left > 0.0:
		_intent_left -= delta
		if _intent_left <= 0.0:
			_intent_door = ""
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = Database.get_balance_float(B_POLL)
		_check_summons()


# ─── Interactivos del módulo en la planta ─────────────────────

## Rehace los interactivos del módulo en la planta cargada.
func sync_floor() -> void:
	if _streamer == null or _streamer.get_plan().is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(NODES_GROUP):
		node.remove_from_group(NODES_GROUP)
		node.queue_free()
	for entry: Variant in Database.get_balance(B_TABLES):
		if entry is Dictionary:
			_spawn_table(entry as Dictionary)
	_spawn_queue()
	_spawn_house_doors()


func _spawn_table(entry: Dictionary) -> void:
	var room_id: String = str(entry.get(K_ROOM, ""))
	var rect: Rect2 = _streamer.get_room_rect_px(room_id)
	var room: RoomData = Database.get_room(room_id)
	if rect.size == Vector2.ZERO or room == null:
		return
	var cell: Vector2 = PlacesKeeper.cell_vector(entry.get(K_POS, []))
	var size: Vector2 = Vector2.ONE
	for piece: Dictionary in room.furniture:
		if str(piece.get("type", "")) == str(entry.get(K_PIECE, "")) and Vector2(piece["pos"] as Vector2i) == cell:
			size = PlacesKeeper.cell_vector(piece.get("size", [])).max(Vector2.ONE)
	var side: Vector2 = PlacesKeeper.cell_vector(entry.get(K_SIDE, []))
	var center: Vector2 = rect.position + (cell + size * 0.5 + side) * RoomBuilder.cell_px()
	var kind: String = str(entry.get(K_TYPE, ""))
	_spawn(TABLE_ID_FORMAT % kind, kind, room_id, {K_GATHERING: str(entry.get(K_GATHERING, ""))}, center)


func _spawn_queue() -> void:
	var room_id: String = str(Database.get_balance(B_QUEUE_ROOM))
	var rect: Rect2 = _streamer.get_room_rect_px(room_id)
	if rect.size == Vector2.ZERO:
		return
	var point: Vector2 = rect.position + PlacesKeeper.cell_vector(Database.get_balance(B_QUEUE_CELL)) * RoomBuilder.cell_px()
	_spawn(QUEUE_ID, QUEUE_TYPE, room_id, {}, point)


## Una puerta "house_door" en la calle, ante cada vivienda de personaje de la planta.
func _spawn_house_doors() -> void:
	var street: String = str(Database.get_balance(B_STREET))
	for room_id: String in (_streamer.get_plan().get("rooms", {}) as Dictionary).keys():
		if NightOps.get_house_type(room_id).is_empty():
			continue
		var points: Dictionary = door_points(room_id, street)
		if points.has("outside"):
			_spawn(HOUSE_DOOR_FORMAT % room_id, HOUSE_DOOR_TYPE, street, {K_HOUSE: room_id}, points["outside"])


func _spawn(id: String, kind: String, room_id: String, data: Dictionary, point: Vector2) -> void:
	var node: Interactable = Interactable.new()
	node.setup(id, kind, room_id, data, RoomBuilder.cell_px(), point)
	node.add_to_group(NODES_GROUP)
	_streamer.get_actor_layer().add_child(node)


## Puntos a cada lado de la puerta entre `room` y `other` en la planta cargada: {inside, outside}
## (la celda transitable más honda, hasta DOOR_DEPTH celdas, de una y otra sala frente al hueco; falta
## la clave si no se encuentra).
func door_points(room: String, other: String) -> Dictionary:
	var door: Dictionary = _streamer.get_door_between(room, other)
	var out: Dictionary = {}
	if door.is_empty():
		return out
	var cell: Vector2i = door["cell"]
	var normal: Vector2i = Vector2i(1, 0) if bool(door["vertical"]) else Vector2i(0, 1)
	var into: Vector2i = normal if _room_along(cell, normal) == room else -normal
	var inside: Vector2 = _deepest(cell, into, room)
	var outside: Vector2 = _deepest(cell, -into, other)
	if inside != Vector2.INF:
		out["inside"] = inside
	if outside != Vector2.INF:
		out["outside"] = outside
	return out


## Sala de la primera celda con sala en esa dirección, más allá de la celda de la puerta.
func _room_along(cell: Vector2i, direction: Vector2i) -> String:
	for step: int in DOOR_DEPTH:
		var at: String = _streamer.get_room_at(_streamer.cell_to_world(cell + direction * (step + 1)))
		if not at.is_empty():
			return at
	return ""


func _deepest(cell: Vector2i, direction: Vector2i, room: String) -> Vector2:
	var best: Vector2 = Vector2.INF
	for step: int in DOOR_DEPTH:
		var probe: Vector2i = cell + direction * (step + 1)
		if _streamer.get_room_at(_streamer.cell_to_world(probe)) == room and _streamer.is_walkable_cell(probe):
			best = _streamer.cell_to_world(probe)
	return best


func game() -> GameRoot:
	return _root


## Dentro de recepción, junto a su salida a la calle (llegada del autobús a la sede).
func entrance_point() -> Vector2:
	var entrance: String = str(Database.get_balance(B_ENTRANCE))
	for t: Dictionary in _streamer.get_plan().get("transit", []):
		if t["kind"] == FloorLayout.TRANSIT_EXIT and t["room_id"] == entrance and t["target_room"] == str(Database.get_balance(B_STREET)):
			return _streamer.cell_to_world(t["cell"])
	return _streamer.get_spawn_point(entrance)


## Junto a la parada de autobús de esa sala (o su punto de aparición).
func stop_point(room_id: String) -> Vector2:
	for item: Interactable in _streamer.get_interactables_in_room(room_id):
		if PlacesTown.TYPES.has(item.interact_type):
			return item.global_position
	return _streamer.get_spawn_point(room_id)


## En la calle, ante la puerta de la vivienda (planta exterior).
func place_at_house(house: String) -> void:
	_root.travel.teleport_to_room(str(Database.get_balance(B_STREET)))
	var points: Dictionary = door_points(house, str(Database.get_balance(B_STREET)))
	if points.has("outside"):
		_root.travel.teleport(_streamer.get_current_floor(), points["outside"])


## Dentro de la vivienda, junto a su puerta (tras el allanamiento).
func place_in_house(house: String) -> void:
	var points: Dictionary = door_points(house, str(Database.get_balance(B_STREET)))
	if points.has("inside"):
		_root.travel.teleport(_streamer.get_current_floor(), points["inside"])
	else:
		_root.travel.teleport_to_room(house)


## Fundido de los trayectos del módulo (autobús): el jugador no se mueve mientras dura.
func fade_in(icon: String, caption: String) -> void:
	_player.set_input_locked(true, RIDE_LOCK)
	var here: int = _streamer.get_current_floor()
	await _overlay_node().play_in(icon, here, here, caption, false, instant)


func fade_out() -> void:
	await _overlay_node().play_out(instant)
	_player.set_input_locked(false, RIDE_LOCK)


func _overlay_node() -> FloorTravel.TravelOverlay:
	if _overlay == null:
		_overlay = FloorTravel.TravelOverlay.new()
		_overlay.name = "PlacesOverlay"
		add_child(_overlay)
	return _overlay


static func cell_vector(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


# ─── Colarse en los tornos (§5.6) ─────────────────────────────

## El jugador quiere colarse por ese torno durante `seconds` (la cola de los tornos).
func allow_tailgate(door_id: String, seconds: float) -> void:
	_intent_door = door_id
	_intent_left = seconds


## Compañero que da cobertura para colarse ahora por `door` ("" si no se puede).
func tailgate_cover(door: Door) -> String:
	if door == null or door.kind != Door.KIND_TURNSTILE or not PlacesGate.rush_now():
		return ""
	var wants: bool = door.door_id == _intent_door or _player.is_sneaking() or _player.is_crouching()
	return PlacesGate.cover_npc(_root, door) if wants else ""


## Decorador de DoorAccess.policy: colarse abre el torno sin armar el registro de la tarjeta.
func _gate_policy(door: Door, body: Node2D) -> bool:
	if body == _player and door != null and door.kind == Door.KIND_TURNSTILE:
		var cover: String = tailgate_cover(door)
		if not cover.is_empty():
			var queued: bool = door.door_id == _intent_door
			_intent_door = ""
			if not queued:
				PlacesKit.good(ctx(), "PLACES_GATE_SLIPPED", [PlacesKit.npc_name(cover)])
			return true
	if _base_policy.is_valid():
		return bool(_base_policy.call(door, body))
	return DoorAccess.allows(door)


# ─── Citación ineludible ──────────────────────────────────────

## Caso con citación pendiente que aún se puede celebrar hoy ("" si ninguno).
static func due_summons(tree: SceneTree) -> String:
	var bridges: WorldBridges = WorldBridges.find(tree)
	if bridges == null:
		return ""
	for case_id: String in bridges.get_pending_summons():
		var inv: Investigation = Security.get_investigation(case_id)
		if inv != null and inv.is_active() and inv.phase == InvestigationEngine.PHASE_INTERROGATION \
				and not inv.is_frozen(Security.get_current_day()):
			return case_id
	return ""


func _check_summons() -> void:
	if _escorting or _root == null or _root.is_run_ended() or _root.ui.has_modal() or _root.travel.is_busy():
		return
	if GameClock.is_paused() or not GameClock.is_working_hours() or GameClock.get_hour() < Database.get_balance_int(B_PICKUP_HOUR):
		return
	if PlayerState.get_floor() != Database.get_balance_int(B_EXTERIOR) or _world_busy():
		return
	var case_id: String = due_summons(get_tree())
	if not case_id.is_empty():
		escort(case_id)


func _world_busy() -> bool:
	var police: Police = _root.sim_nodes.get("Police") as Police
	var ops: NightOps = _root.sim_nodes.get("NightOps") as NightOps
	return (police != null and police.is_active()) or (ops != null and ops.is_active()) \
			or (_root.bridges != null and _root.bridges.is_sleeping()) or not _player.current_act().is_empty()


## Dos vigilantes llevan al jugador a la sala de interrogatorios y lo devuelven después.
func escort(case_id: String) -> void:
	_escorting = true
	var who: String = PlacesKit.npc_name(Security.get_interrogator(case_id))
	PlacesKit.sfx(_root.ui, PlacesKit.SFX_GUARD)
	await _root.ui.show_dialog("PLACES_ESCORT_TITLE", "PLACES_ESCORT_BODY", ["PLACES_ESCORT_GO"], [who], true, false)
	var back_floor: int = _streamer.get_current_floor()
	var back_point: Vector2 = _player.global_position
	_player.set_input_locked(true, ESCORT_LOCK)
	GameClock.advance_minutes(Database.get_balance_float(B_ESCORT_MINUTES))
	if _root.travel.teleport_to_room(str(Database.get_balance(B_INTERROGATION_ROOM))):
		await PlacesKit.await_closed(InterrogationScene.open(_root.ui, case_id))
		if not SaveSystem.is_run_over():
			_root.travel.teleport(back_floor, back_point)
			PlacesKit.say(ctx(), "PLACES_ESCORT_BACK")
	_player.set_input_locked(false, ESCORT_LOCK)
	_escorting = false


func is_escorting() -> bool:
	return _escorting


# ─── Avisos de escenas ────────────────────────────────────────

func _on_results_due(quarter: int) -> void:
	if PlayerState.get_rank() < Database.get_balance_int(B_RESULTS_RANK):
		return
	var room: String = Market.get_presentation_room()
	PlacesKit.say(ctx(), "PLACES_RESULTS_DUE", [quarter, PlacesKit.room_name(room)], ToastStack.KIND_WARN)
	PlacesKit.note(NOTE_CATEGORY, "PLACES_NOTE_RESULTS_DUE", [quarter, PlacesKit.room_name(room)])


func _on_aurora_started(meeting_id: String) -> void:
	# Un aviso por reunión y jornada (la señal puede llegar dos veces: arranque y reprogramación).
	var key: String = "%d:%s" % [GameClock.get_day(), meeting_id]
	if key == _last_aurora_key:
		return
	_last_aurora_key = key
	var room: RoomData = Database.get_room(AURORA_ROOM)
	if room != null and PlayerState.get_clearance() >= room.clearance_required:
		PlacesKit.say(ctx(), "PLACES_AURORA_STARTED", [PlacesKit.room_name(AURORA_ROOM)])


# ─── Traje de estatus ─────────────────────────────────────────

static func has_suit() -> bool:
	return bool(PlayerState.get_flag(F_SUIT, false)) or PlayerState.has_item(str(Database.get_balance(B_SUIT_ITEM)))


static func mark_suit_owned() -> void:
	PlayerState.set_flag(F_SUIT, true)


## La penalización diaria de reputación del escalón de estatus sin traje (0 si no toca).
static func suit_penalty() -> float:
	if PlayerState.get_tier() < Database.get_balance_int(B_SUIT_TIER) or has_suit():
		return 0.0
	return Database.get_balance_float(B_SUIT_PENALTY)


func _on_day_advanced(day: int) -> void:
	var penalty: float = suit_penalty()
	if penalty > 0.0:
		PlayerState.modify_reputation(-penalty, REP_REASON_SUIT)
		PlacesKit.note(NOTE_CATEGORY, "PLACES_NOTE_NO_SUIT", [penalty])
	var burn: Dictionary = burn_state()
	if not burn.is_empty() and day - int(burn.get("day", day)) >= Database.get_balance_int(B_BURN_DAYS):
		cure_burn()


# ─── Quemaduras del laboratorio ───────────────────────────────

static func burn_state() -> Dictionary:
	var raw: Variant = PlayerState.get_flag(F_BURN, {})
	return (raw as Dictionary).duplicate() if raw is Dictionary else {}


static func is_burned() -> bool:
	return not burn_state().is_empty()


static func set_burn(lab_room: String) -> void:
	PlayerState.set_flag(F_BURN, {"day": GameClock.get_day(), "lab": lab_room})


## Cura la quemadura. true si había una.
static func cure_burn() -> bool:
	if not is_burned():
		return false
	PlayerState.set_flag(F_BURN, null)
	return true


## Cada hora de trabajo en el edificio, alguien de la sala del jugador ve la quemadura.
func _on_hour_passed(_hour: int, _day: int) -> void:
	var burn: Dictionary = burn_state()
	if burn.is_empty() or not GameClock.is_working_hours() or not ClosingTime.is_inside():
		return
	for npc: NPCRuntime in NPCDirector.get_npcs_in_room(PlayerState.get_room()):
		if not NPCDirector.is_active(npc.id):
			continue
		BeliefNet.create_belief(npc.id, BeliefNetSystem.PLAYER_ID, BURN_FACT,
				Database.get_balance_float(B_BURN_CERTAINTY), Belief.SOURCE_DIRECT, str(burn.get("lab", "")))
		PlacesKit.say(ctx(), "PLACES_BURN_SEEN", [npc.name], ToastStack.KIND_WARN)
		return


# ─── Viviendas cerradas ───────────────────────────────────────

func _on_room_entered(room_id: String, by_player: bool) -> void:
	if not by_player or _root == null:
		return
	var previous: String = _last_room
	_last_room = room_id
	var ops: NightOps = _root.sim_nodes.get("NightOps") as NightOps
	if not NightOps.get_house_type(room_id).is_empty():
		if not inside_operation(ops, room_id):
			_push_out.call_deferred(room_id)
	elif not previous.is_empty() and not NightOps.get_house_type(previous).is_empty() \
			and inside_operation(ops, previous):
		PlacesTown.finish_burglary(ctx(), ops)


## La operación nocturna en curso ya allanó esa vivienda.
static func inside_operation(ops: NightOps, house: String) -> bool:
	if ops == null or not ops.is_active():
		return false
	var op: Dictionary = ops.get_operation()
	return bool(op.get("entered", false)) and DatabaseSystem.get_room_base_id(str(op.get("house", ""))) \
			== DatabaseSystem.get_room_base_id(house)


func _push_out(house: String) -> void:
	var points: Dictionary = door_points(house, str(Database.get_balance(B_STREET)))
	if points.has("outside"):
		_root.travel.teleport(_streamer.get_current_floor(), points["outside"])
	PlacesKit.refuse(ctx(), "PLACES_HOUSE_LOCKED")
