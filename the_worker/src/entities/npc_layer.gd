# npc_layer.gd — Capa de personajes de la planta cargada (§20, PASO 9/40): crea y libera los NPCNode de LOD 0/1, les da cada fotograma y les reparte eventos, sitios, rutas y tránsitos.
# PROPIETARIO DE: los nodos de personaje de la planta, el reparto de sitios (asientos, sillas, celdas), los cachés de sala de la planta, la última planta vista de cada personaje y la ficha rápida abierta.
# ESCUCHA: EventBus.noise_emitted, npc_decided, npc_reported_player, player_caught_redhanded; FloorStreamer.floor_loaded.
class_name NPCLayer
extends Node

## Contrato: grupo "npc_layer". game_root la añade y llama set_streamer(streamer) (si no, busca el
## FloorStreamer del árbol). NPCLayer.find(tree) · get_node_for(npc_id) · get_nodes() · sync_now()
## · open_card(npc_id) · free_running (QA: ignora la pausa del reloj).
## DECISIONES:
##  · Cada lod.intervalo_medio_segundos: sincroniza con NPCDirector — nodo para cada personaje en
##    plantilla de LOD ≤ 1 cuya sala está en la planta cargada (tope lod.max_agentes_completo +
##    lod.max_agentes_medio); libera los que bajan a LOD 2 o salen de la plantilla
##    (release_current_location). Después, think() de cada nodo (agenda, recados, vida social).
##  · Aparición: en la primera sincronización de una planta, o si ya estaba en esta planta (sube
##    de LOD), aparece YA en su sitio; si venía de otra planta, entra por el ascensor/escalera (o
##    por la puerta de la calle en la PB si venía de fuera) y camina a su sitio.
##  · Salida: el nodo que llega a su tránsito se sitúa en su destino con
##    set_current_location(destino) + release_current_location y se libera.
##  · Cada fotograma (física): exposición del jugador UNA vez (Perception.assess_exposure con la
##    sala de FloorStreamer), step() de todos y perceive() (LOD 0). Tiempo de mundo = 0 con el
##    reloj en pausa; × GameClock.get_speed_multiplier() (cámara lenta de la flagrancia).
##  · Ruido (noise_emitted): sala del origen por FloorStreamer; solo oyen los de LOD 0.
##  · Conos: ajuste "vision_cones" (0 ocultos, 1 automático = cercanos y sutiles, 2 todos; bool →
##    1/0) → Perception.cone_mode. F1 (DebugPanel) fuerza todos con set_debug_cones.
##  · Clic/toque sobre un personaje (sin dirección pulsada ni ventana modal) → CharacterCard.

const GROUP := "npc_layer"
const PLAYER_GROUP := "player"
const SETTING_CONES := "vision_cones"
const MOVE_ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
const KIND_EXIT := "exit"
const KIND_ELEVATOR := "elevator"
const KIND_STAIRS := "stairs"
const KIND_FREIGHT := "freight"
const STAND_ACTIVITIES: Array[String] = ["coffee", "tea_break", "toilet", "copier", "smoke", "slacking",
	"relief", "preparation", "watch", "clean", "clean_zone", "round", "patrol", "patrol_zone", "assign_tasks",
	"attendance_check"]
const KEY_FORMAT := "cell:%s:%d:%d"
const PICK_FORMAT := "%s|%s|%d"
const OWNER_GENERATED := "generated"
const SELECT_LIFT := 0.7
const GOSSIP_REACH := 16.0
const ROLL_STEPS := 1000
## Celdas libres alrededor de cada hueco de puerta (nadie se planta en el paso).
const DOOR_CLEARANCE := 2

var free_running: bool = false
## Coste del último fotograma de la capa (µs de CPU: sincronía, pasos y percepción). QA / perfil.
var last_advance_usec: int = 0

var _streamer: FloorStreamer = null
var _nodes: Dictionary = {}
var _claims: Dictionary = {}
var _claim_of: Dictionary = {}
var _last_floor: Dictionary = {}
var _initial: bool = true
var _sync_left: float = 0.0
var _interval: float = 0.5
var _cell: float = 48.0
var _player: Node2D = null
var _exposure: Dictionary = {}
var _room_cells: Dictionary = {}
var _room_seats: Dictionary = {}
var _room_chairs: Dictionary = {}
var _day_plans: Dictionary = {}
var _office_tiers: Dictionary = {}
var _card: CharacterCard = null


func _ready() -> void:
	add_to_group(GROUP)
	_interval = maxf(Database.get_balance_float("lod.intervalo_medio_segundos"), 0.05)
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.npc_decided.connect(_on_npc_decided)
	EventBus.npc_reported_player.connect(_on_npc_reported)
	EventBus.player_caught_redhanded.connect(_on_caught)
	if _streamer == null:
		_find_streamer.call_deferred()


static func find(tree: SceneTree) -> NPCLayer:
	return tree.get_first_node_in_group(GROUP) as NPCLayer if tree != null else null


func set_streamer(streamer: FloorStreamer) -> void:
	if streamer == _streamer:
		return
	_streamer = streamer
	if _streamer != null:
		_streamer.floor_loaded.connect(_on_floor_loaded)
		if not _streamer.get_plan().is_empty():
			_on_floor_loaded(_streamer.get_current_floor())


func _find_streamer() -> void:
	if _streamer == null:
		set_streamer(FloorStreamer.find_in(get_tree()))


func get_streamer() -> FloorStreamer:
	return _streamer


func _has_floor() -> bool:
	return _streamer != null and is_instance_valid(_streamer) and not _streamer.get_plan().is_empty()


# ─── Consultas públicas ───────────────────────────────────────

func get_node_for(npc_id: String) -> NPCNode:
	var node: NPCNode = _nodes.get(npc_id) as NPCNode
	return node if node != null and is_instance_valid(node) else null


func get_nodes() -> Array[NPCNode]:
	var out: Array[NPCNode] = []
	for node: Variant in _nodes.values():
		if is_instance_valid(node):
			out.append(node as NPCNode)
	return out


func get_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D if is_inside_tree() else null
	return _player


func get_exposure() -> Dictionary:
	return _exposure


func think_interval() -> float:
	return _interval


## Tiempo de mundo: 0 con el reloj en pausa; cámara lenta de la flagrancia incluida.
func world_time_scale() -> float:
	if free_running:
		return 1.0
	if GameClock.is_paused():
		return 0.0
	return GameClock.get_speed_multiplier()


# ─── Ciclo ────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	advance(delta)


## Un fotograma de `delta` segundos reales: sincroniza/piensa a su cadencia, exposición del
## jugador, step() de todos y perceive() (los tests lo llaman a mano con la física parada).
func advance(delta: float) -> void:
	if not _has_floor():
		return
	var started: int = Time.get_ticks_usec()
	_advance_world(delta)
	last_advance_usec = Time.get_ticks_usec() - started


func _advance_world(delta: float) -> void:
	var world_delta: float = delta * world_time_scale()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = _interval
		sync_now()
		if world_delta > 0.0:
			think_all()
	get_player()
	_exposure = _compute_exposure()
	for node: NPCNode in get_nodes():
		node.step(world_delta)
		node.perceive(world_delta, _player, _exposure)


func think_all() -> void:
	for node: NPCNode in get_nodes():
		if not node.is_queued_for_deletion():
			node.think()


func _compute_exposure() -> Dictionary:
	if _player == null:
		return {}
	return Perception.assess_exposure(_player, room_at(_player.global_position))


## Reconciliación con NPCDirector (LOD, planta, plantilla) + ideas y ajustes.
func sync_now() -> void:
	if not _has_floor():
		return
	var floor_number: int = _streamer.get_current_floor()
	var cap: int = Database.get_balance_int("lod.max_agentes_completo") + Database.get_balance_int("lod.max_agentes_medio")
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var previous: int = int(_last_floor.get(npc.id, NPCDirectorSystem.FLOOR_NONE))
		_last_floor[npc.id] = npc.floor
		var node: NPCNode = get_node_for(npc.id)
		if node != null:
			if npc.lod > NPCRuntime.LOD_MEDIUM:
				_despawn(npc.id, true)
			else:
				node.set_lod(npc.lod)
		elif _nodes.size() < cap and npc.lod <= NPCRuntime.LOD_MEDIUM and npc.floor == floor_number \
				and not local_room(npc.current_room).is_empty():
			_spawn(npc, previous)
	for npc_id: String in _nodes.keys():
		if not NPCDirector.is_active(npc_id):
			_despawn(npc_id, true)
	_initial = false
	_sync_ideas()
	_sync_settings()


func _spawn(npc: NPCRuntime, previous_floor: int) -> void:
	var node: NPCNode = NPCNode.new()
	node.setup(npc, self)
	node.set_lod(npc.lod)
	node.arrived_at_exit.connect(_on_node_exit)
	_streamer.get_actor_layer().add_child(node)
	_nodes[npc.id] = node
	node.perception.set_band_colors(UITheme.band_for_floor(_streamer.get_current_floor()))
	node.set_debug_cones(DebugPanel.cones_visible)
	var goal: Dictionary = schedule_goal(npc.id)
	var room: String = local_room(str(goal["room"]))
	var activity: String = str(goal["activity"])
	if room.is_empty():
		room = local_room(npc.current_room)
		activity = ""
	node.set_goal(str(goal["room"]) if room == local_room(str(goal["room"])) else npc.current_room, activity)
	var spot: Dictionary = claim_spot(node, room, activity)
	if spot.is_empty():
		spot = {"room": room, "pos": _streamer.get_spawn_point(room), "draw": _streamer.get_spawn_point(room)}
	if _initial or previous_floor == _streamer.get_current_floor():
		node.place_at(spot)
	else:
		node.enter_at(arrival_point(npc.id, previous_floor), spot)
	node.report_room()


func _despawn(npc_id: String, release: bool) -> void:
	var node: NPCNode = get_node_for(npc_id)
	_nodes.erase(npc_id)
	_release_claim(npc_id)
	if release:
		NPCDirector.release_current_location(npc_id)
	if node != null:
		node.queue_free()


## Llega a su tránsito: queda situado en su destino (otra planta o fuera) y desaparece.
func _on_node_exit(node: NPCNode, target_room: String) -> void:
	NPCDirector.set_current_location(node.npc_id, target_room)
	NPCDirector.release_current_location(node.npc_id)
	var npc: NPCRuntime = NPCDirector.get_npc(node.npc_id)
	if npc != null:
		_last_floor[node.npc_id] = npc.floor
	_despawn(node.npc_id, false)


func _on_floor_loaded(_floor_number: int) -> void:
	for npc_id: String in _nodes.keys():
		_despawn(npc_id, true)
	_claims.clear()
	_claim_of.clear()
	_room_cells.clear()
	_room_seats.clear()
	_room_chairs.clear()
	_initial = true
	_sync_left = 0.0
	close_card()


func _sync_ideas() -> void:
	var active: Dictionary = {}
	for entry: Dictionary in IdeaPool.get_signalling_npcs():
		if int(entry.get("day", 0)) == GameClock.get_day() and GameClock.get_hour() < int(entry.get("until_hour", 0)):
			active[str(entry.get("npc_id", ""))] = entry
	for node: NPCNode in get_nodes():
		node.set_idea(active.get(node.npc_id, {}))


func _sync_settings() -> void:
	var value: Variant = SaveSystem.get_setting(SETTING_CONES)
	if value is int or value is float:
		Perception.cone_mode = clampi(int(value), Perception.CONE_OFF, Perception.CONE_ALL)
	elif value is bool:
		Perception.cone_mode = Perception.CONE_AUTO if value else Perception.CONE_OFF


# ─── Eventos ──────────────────────────────────────────────────

func _on_noise(pos: Vector2, radius: float, source: String) -> void:
	if not _has_floor():
		return
	var room: String = room_at(pos)
	var noteworthy: bool = bool(_exposure.get("noteworthy", false))
	for node: NPCNode in get_nodes():
		if node.lod == NPCRuntime.LOD_FULL and node.perception != null:
			node.on_heard(node.perception.hear(pos, radius, source, room, noteworthy))


func _on_npc_decided(npc_id: String, action: String, context: Dictionary) -> void:
	var node: NPCNode = get_node_for(npc_id)
	if node != null:
		node.react(action, context)


## Denuncias sin decisión propia (CaughtHandler, Blackmail): también caminan a Seguridad.
func _on_npc_reported(npc_id: String, report_type: String, _weight: float, _location: String) -> void:
	var node: NPCNode = get_node_for(npc_id)
	if node == null or node.get_errand_kind() in [NPCNode.ERRAND_REPORT, NPCNode.ERRAND_SUPERIOR]:
		return
	var superior: bool = report_type == NPCDirectorSystem.CHANNEL_SUPERIOR
	node.react(UtilityAI.REPORT_TO_SUPERIOR if superior else UtilityAI.REPORT_TO_SECURITY, {})


func _on_caught(npc_id: String, _crime_type: String, _witnesses: int) -> void:
	var node: NPCNode = get_node_for(npc_id)
	if node != null:
		node.on_caught()


# ─── Agenda y geometría ───────────────────────────────────────

## {room, activity} de la agenda ahora (NPCDirector; room "" = fuera del edificio).
func schedule_goal(npc_id: String) -> Dictionary:
	var hour: int = GameClock.get_hour()
	var minute: int = GameClock.get_minute()
	var room: String = NPCDirector.get_location_at(npc_id, hour, minute)
	var iv: Dictionary = NPCRoutinePlanner.pick(_plan_of(npc_id), hour * NPCRoutinePlanner.MINUTES_PER_HOUR + minute, true)
	var activity: String = str(iv.get("activity", "")) if str(iv.get("room", "")) == room else ""
	return {"room": room, "activity": activity}


func _plan_of(npc_id: String) -> Array:
	var cached: Dictionary = _day_plans.get(npc_id, {})
	if int(cached.get("day", -1)) != GameClock.get_day():
		cached = {"day": GameClock.get_day(), "plan": NPCDirector.get_day_plan(npc_id)}
		_day_plans[npc_id] = cached
	return cached["plan"]


## Id de la sala en la planta cargada ("" si está en otra planta o fuera).
func local_room(room_id: String) -> String:
	if room_id.is_empty() or not _has_floor():
		return ""
	var rooms: Dictionary = _streamer.get_plan().get("rooms", {})
	if rooms.has(room_id):
		return room_id
	var instance: String = DatabaseSystem.make_room_instance_id(DatabaseSystem.get_room_base_id(room_id),
			_streamer.get_current_floor())
	return instance if rooms.has(instance) else ""


func room_at(pos: Vector2) -> String:
	return _streamer.get_room_at(pos) if _has_floor() else ""


func path_between(from: Vector2, to: Vector2) -> PackedVector2Array:
	return _streamer.find_path_to_point(from, to) if _has_floor() else PackedVector2Array()


func _floor_of_room(room_id: String) -> int:
	if room_id.is_empty():
		return NPCDirectorSystem.FLOOR_NONE
	if room_id.contains(DatabaseSystem.INSTANCE_SEPARATOR):
		return room_id.get_slice(DatabaseSystem.INSTANCE_SEPARATOR, 1).to_int()
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return NPCDirectorSystem.FLOOR_NONE
	return _streamer.get_current_floor() if room.is_transversal() else room.floor


## Punto del tránsito por el que sale hacia `target_room` (Vector2.INF si la planta no tiene).
func exit_point(node: NPCNode, target_room: String) -> Vector2:
	var t: Dictionary = _pick_transit(node.npc_id, _floor_of_room(target_room))
	return _streamer.cell_to_world(t["cell"]) if not t.is_empty() else Vector2.INF


## Por dónde entra quien viene de `from_floor` (de fuera: la puerta de la calle en la PB).
func arrival_point(npc_id: String, from_floor: int) -> Vector2:
	var t: Dictionary = _pick_transit(npc_id, from_floor)
	return _streamer.cell_to_world(t["cell"]) if not t.is_empty() else _streamer.get_spawn_point(_streamer.get_plan().get("corridor_id", ""))


func _pick_transit(npc_id: String, other_floor: int) -> Dictionary:
	var outside: bool = other_floor == NPCDirectorSystem.FLOOR_NONE \
			or other_floor == Database.get_balance_int("mundo.planta_exterior")
	var kinds: Array[String] = [KIND_ELEVATOR, KIND_STAIRS]
	var roll: float = float(absi(hash(npc_id + str(GameClock.get_hour()))) % ROLL_STEPS) / float(ROLL_STEPS)
	if outside:
		kinds = [KIND_EXIT, KIND_ELEVATOR]
	elif other_floor == Database.get_balance_int("mundo.planta_fabrica"):
		kinds = [KIND_FREIGHT, KIND_ELEVATOR]
	elif roll < Database.get_balance_float("npc_nodo.prob_escaleras"):
		kinds = [KIND_STAIRS, KIND_ELEVATOR]
	for kind: String in kinds:
		var list: Array[Dictionary] = _transits_of(kind)
		if not list.is_empty():
			return list[absi(hash(npc_id)) % list.size()]
	var all: Array = _streamer.get_plan().get("transit", [])
	return all[0] if not all.is_empty() else {}


## Tránsitos de un tipo; las salidas, solo las de la calle y primero la del vestíbulo.
func _transits_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hub: String = str(_streamer.get_plan().get("corridor_id", ""))
	for t: Dictionary in _streamer.get_plan().get("transit", []):
		if str(t["kind"]) != kind:
			continue
		if kind == KIND_EXIT and not (t.get("targets", []) as Array).has(Database.get_balance_int("mundo.planta_exterior")):
			continue
		if kind == KIND_EXIT and str(t["room_id"]) == hub:
			return [t]
		out.append(t)
	return out


# ─── Sitios: asientos, sillas y celdas ────────────────────────

## Actividades de pie (café, baño, rondas...) frente a las sentadas (trabajo, comida, reuniones).
func wants_seat(_node: NPCNode, activity: String) -> bool:
	return not STAND_ACTIVITIES.has(activity)


## Reserva un sitio en `room_id` para la actividad: su puesto, una silla libre o una celda libre.
## {key, room, pos (nodo), draw (dibujo), approach (destino de la ruta), seated, facing}.
func claim_spot(node: NPCNode, room_id: String, activity: String) -> Dictionary:
	release_spot(node)
	if room_id.is_empty() or not _has_floor() or not _streamer.get_plan().get("rooms", {}).has(room_id):
		return {}
	var spot: Dictionary = {}
	if wants_seat(node, activity):
		spot = _own_seat(node, room_id)
		if spot.is_empty():
			spot = _free_chair(node, room_id)
	if spot.is_empty():
		spot = _free_cell(node, room_id)
	if not spot.is_empty():
		_claims[str(spot["key"])] = node.npc_id
		_claim_of[node.npc_id] = str(spot["key"])
	return spot


func release_spot(node: NPCNode) -> void:
	if node != null:
		_release_claim(node.npc_id)


func _release_claim(npc_id: String) -> void:
	var key: String = str(_claim_of.get(npc_id, ""))
	if not key.is_empty() and str(_claims.get(key, "")) == npc_id:
		_claims.erase(key)
	_claim_of.erase(npc_id)


func _free_key(key: String, npc_id: String) -> bool:
	return not _claims.has(key) or str(_claims[key]) == npc_id


## Su puesto en su sala: asiento con su id, con su desk_position o, si no, uno "generated" libre.
func _own_seat(node: NPCNode, room_id: String) -> Dictionary:
	if DatabaseSystem.get_room_base_id(room_id) != DatabaseSystem.get_room_base_id(node.home_room):
		return {}
	var npc: NPCRuntime = NPCDirector.get_npc(node.npc_id)
	var seats: Array[Dictionary] = _seats(room_id)
	for seat: Dictionary in seats:
		if str(seat["owner"]) == node.npc_id or (npc != null and seat["desk"] == npc.desk_position):
			return _seat_spot(seat, room_id, node) if _free_key(str(seat["key"]), node.npc_id) else {}
	for seat: Dictionary in seats:
		if str(seat["owner"]) == OWNER_GENERATED and _free_key(str(seat["key"]), node.npc_id) \
				and not _seat_reserved(seat):
			return _seat_spot(seat, room_id, node)
	return {}


## Un asiento "generated" cuyo mueble es el desk_position de un personaje de la sala queda para él.
func _seat_reserved(seat: Dictionary) -> bool:
	return bool(seat.get("reserved", false))


func _seats(room_id: String) -> Array[Dictionary]:
	if _room_seats.has(room_id):
		return _room_seats[room_id]
	var out: Array[Dictionary] = []
	var room: RoomData = Database.get_room(room_id)
	var furniture: Array[Dictionary] = []
	if room != null:
		furniture = FloorLayout.room_furniture(room)
	var desks: Dictionary = _desks_of(room_id)
	for seat: Dictionary in _streamer.get_seats_in_room(room_id):
		var index: int = int(seat["furniture_index"])
		var entry: Dictionary = furniture[index] if index >= 0 and index < furniture.size() else {}
		var cell: Vector2i = seat["cell"]
		var desk: Vector2i = Vector2i(entry["pos"]) if entry.has("pos") else NPCRuntime.NO_DESK
		out.append(seat.merged({"room": room_id, "entry": entry, "key": KEY_FORMAT % [room_id, cell.x, cell.y],
				"desk": desk, "reserved": desks.has(desk)}))
	_room_seats[room_id] = out
	return out


## desk_position de la plantilla cuya sala propia es `room_id` (puestos ya asignados).
func _desks_of(room_id: String) -> Dictionary:
	var out: Dictionary = {}
	var base: String = DatabaseSystem.get_room_base_id(room_id)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if DatabaseSystem.get_room_base_id(npc.home_room) == base and npc.desk_position != NPCRuntime.NO_DESK:
			out[npc.desk_position] = npc.id
	return out


## Sitio sentado: el dibujo cae en la silla (seat_origin); en un cubículo abierto al sur el nodo se
## ordena justo delante del mueble (su borde inferior) para no quedar tapado por él.
func _seat_spot(seat: Dictionary, room_id: String, node: NPCNode) -> Dictionary:
	var draw: Vector2 = CharacterPainter.seat_origin(seat["pos"], node.get_appearance(), node.tier)
	var pos: Vector2 = draw
	var entry: Dictionary = seat["entry"]
	var facing: Vector2 = seat["facing"]
	if not entry.is_empty() and FurniturePainter.is_enclosure(str(entry.get("type", ""))) and facing == Vector2.UP:
		var fp: Rect2i = FurniturePainter.footprint(entry)
		var bottom: float = _streamer.get_room_rect_px(room_id).position.y + float(fp.end.y) * _cell
		pos.y = maxf(draw.y, bottom + 1.0)
	return {"key": seat["key"], "room": room_id, "pos": pos, "draw": draw, "seated": true, "facing": facing,
			"approach": _streamer.cell_to_world(seat["cell"])}


## Silla libre de la sala (cafetería, reuniones), empezando en un punto propio del personaje.
func _free_chair(node: NPCNode, room_id: String) -> Dictionary:
	var chairs: Array[Dictionary] = _chairs(room_id)
	if chairs.is_empty():
		return {}
	var start: int = absi(hash(PICK_FORMAT % [node.npc_id, room_id, GameClock.get_day()])) % chairs.size()
	for k: int in chairs.size():
		var chair: Dictionary = chairs[(start + k) % chairs.size()]
		if _free_key(str(chair["key"]), node.npc_id):
			var draw: Vector2 = CharacterPainter.seat_origin(chair["center"], node.get_appearance(), node.tier)
			return {"key": chair["key"], "room": room_id, "pos": draw, "draw": draw, "seated": true,
					"facing": chair["facing"], "approach": chair["center"]}
	return {}


func _chairs(room_id: String) -> Array[Dictionary]:
	if _room_chairs.has(room_id):
		return _room_chairs[room_id]
	var out: Array[Dictionary] = []
	var room: RoomData = Database.get_room(room_id)
	var origin: Vector2i = (_streamer.get_plan()["rooms"][room_id] as Rect2i).position
	for entry: Dictionary in (FloorLayout.room_furniture(room) if room != null else []):
		if str(entry.get("type", "")) != FloorLayout.CHAIR_TYPE:
			continue
		var cell: Vector2i = origin + Vector2i(entry["pos"])
		out.append({"key": KEY_FORMAT % [room_id, cell.x, cell.y], "center": _streamer.cell_to_world(cell),
				"facing": Vector2.DOWN.rotated(deg_to_rad(float(entry.get("rotation", 0.0))))})
	_room_chairs[room_id] = out
	return out


## Celda libre de la sala (burnout: junto a la pared, de espaldas a ella).
func _free_cell(node: NPCNode, room_id: String) -> Dictionary:
	var cells: Array[Vector2i] = _cells(room_id, node.archetype == NPCNode.ARCH_BURNOUT)
	if cells.is_empty():
		return {}
	var start: int = absi(hash(PICK_FORMAT % [node.npc_id, room_id, GameClock.get_day() * 24 + GameClock.get_hour()])) % cells.size()
	var centre: Vector2 = _streamer.get_room_rect_px(room_id).get_center()
	for k: int in cells.size():
		var cell: Vector2i = cells[(start + k) % cells.size()]
		var key: String = KEY_FORMAT % [room_id, cell.x, cell.y]
		if _free_key(key, node.npc_id):
			var p: Vector2 = _streamer.cell_to_world(cell)
			return {"key": key, "room": room_id, "pos": p, "draw": p, "approach": p, "seated": false,
					"facing": (centre - p).normalized() if centre.distance_to(p) > 1.0 else Vector2.DOWN}
	return {}


## Celdas transitables de la sala lejos de las puertas y de los asientos (cacheadas por planta).
func _cells(room_id: String, near_walls: bool) -> Array[Vector2i]:
	var cache_key: String = room_id + ("#w" if near_walls else "")
	if _room_cells.has(cache_key):
		return _room_cells[cache_key]
	var rect: Rect2i = _streamer.get_plan()["rooms"][room_id]
	var avoid: Dictionary = _door_cells(room_id)
	for seat: Dictionary in _seats(room_id):
		avoid[seat["cell"]] = true
	var out: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var c: Vector2i = Vector2i(x, y)
			if avoid.has(c) or not _streamer.is_walkable_cell(c):
				continue
			if near_walls and not _touches_wall(c, rect):
				continue
			out.append(c)
	if near_walls and out.is_empty():
		out = _cells(room_id, false)
	_room_cells[cache_key] = out
	return out


func _touches_wall(c: Vector2i, rect: Rect2i) -> bool:
	return c.x == rect.position.x or c.x == rect.end.x - 1 or c.y == rect.end.y - 1 \
			or not _streamer.is_walkable_cell(c + Vector2i.UP)


## Celdas a una de distancia de los huecos de puerta de la sala (no taponar el paso).
func _door_cells(room_id: String) -> Dictionary:
	var out: Dictionary = {}
	for door: Dictionary in _streamer.get_plan().get("doors", []):
		if str(door.get("a", "")) != room_id and str(door.get("b", "")) != room_id:
			continue
		var start: Vector2i = door["cell"]
		for k: int in int(door.get("width", 1)):
			var gap: Vector2i = start + (Vector2i(0, k) if bool(door["vertical"]) else Vector2i(k, 0))
			for dy: int in range(-DOOR_CLEARANCE, DOOR_CLEARANCE + 1):
				for dx: int in range(-DOOR_CLEARANCE, DOOR_CLEARANCE + 1):
					out[gap + Vector2i(dx, dy)] = true
	return out


## Punto transitable libre a `radius_cells` celdas de `pos` (elegido con `seed`).
func free_point_near(pos: Vector2, radius_cells: int, seed: int) -> Vector2:
	if not _has_floor():
		return Vector2.INF
	var centre: Vector2i = _streamer.world_to_cell(pos)
	var options: Array[Vector2i] = []
	for dy: int in range(-radius_cells, radius_cells + 1):
		for dx: int in range(-radius_cells, radius_cells + 1):
			var c: Vector2i = centre + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and _streamer.is_walkable_cell(c) and not _claims.has(KEY_FORMAT % [room_at(_streamer.cell_to_world(c)), c.x, c.y]):
				options.append(c)
	if options.is_empty():
		return _streamer.nearest_walkable_point(pos)
	return _streamer.cell_to_world(options[absi(seed) % options.size()])


## Celda de la sala del personaje más alejada de `pos` (huida).
func farthest_point_from(node: NPCNode, pos: Vector2) -> Vector2:
	var room: String = room_at(node.get_visual_position())
	if room.is_empty() or not pos.is_finite():
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	for c: Vector2i in _cells(room, false):
		var p: Vector2 = _streamer.cell_to_world(c)
		if not best.is_finite() or p.distance_squared_to(pos) > best.distance_squared_to(pos):
			best = p
	return best


# ─── Vida social ──────────────────────────────────────────────

## Compañero de charla: otro personaje quieto a npc_nodo.distancia_charla, en su misma postura.
func chat_partner(node: NPCNode) -> NPCNode:
	var reach: float = Database.get_balance_float("npc_nodo.distancia_charla") * _cell
	var best: NPCNode = null
	for other: NPCNode in get_nodes():
		if other == node or other.is_moving() or other.is_leaving() or other.is_seated() != node.is_seated():
			continue
		var d: float = other.get_visual_position().distance_to(node.get_visual_position())
		if d <= reach and (best == null or d < best.get_visual_position().distance_to(node.get_visual_position())):
			best = other
	return best


## Destinatario de un cotilleo: el más cercano de su sala, o de la planta a GOSSIP_REACH celdas.
func gossip_partner(node: NPCNode) -> NPCNode:
	var room: String = room_at(node.get_visual_position())
	var best: NPCNode = null
	var best_d: float = GOSSIP_REACH * _cell
	for other: NPCNode in get_nodes():
		if other == node or other.is_leaving():
			continue
		var d: float = other.get_visual_position().distance_to(node.get_visual_position())
		if room_at(other.get_visual_position()) != room:
			d += GOSSIP_REACH * _cell * 0.5
		if d < best_d:
			best_d = d
			best = other
	return best


## {node} (jefe presente en la planta: mismo departamento, escalón superior más cercano) o {room}
## (despacho de la ocupación superior de su departamento; si no, Seguridad).
func superior_target(node: NPCNode) -> Dictionary:
	var best: NPCNode = null
	for other: NPCNode in get_nodes():
		if other.department == node.department and other.tier > node.tier and not other.is_leaving() \
				and (best == null or other.tier < best.tier):
			best = other
	if best != null:
		return {"node": best}
	var office: String = ""
	var office_tier: int = OccupationData.MAX_TIER + 1
	for occ: OccupationData in Database.get_all_occupations():
		if str(occ.extra.get("department", "")) == node.department and occ.tier > node.tier \
				and occ.tier < office_tier and not occ.office_room.is_empty():
			office = occ.office_room
			office_tier = occ.tier
	return {"room": office if not office.is_empty() else str(Database.get_balance("npc_nodo.sala_denuncia_seguridad"))}


## Primera sala de la planta cuyo id contiene `pattern` ("pantry" → office de la planta).
func room_like(pattern: String) -> String:
	for room_id: String in _streamer.get_plan().get("rooms", {}).keys():
		if room_id.contains(pattern):
			return room_id
	return ""


## Despacho de una ocupación de escalón superior a `tier` (climber acelera hacia él).
func is_superior_office(room_id: String, tier: int) -> bool:
	if _office_tiers.is_empty():
		for occ: OccupationData in Database.get_all_occupations():
			if not occ.office_room.is_empty():
				_office_tiers[occ.office_room] = maxi(int(_office_tiers.get(occ.office_room, 0)), occ.tier)
	return int(_office_tiers.get(DatabaseSystem.get_room_base_id(room_id), 0)) > tier


# ─── Ficha rápida (§13.7) ─────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or mb.double_click:
		return
	if not _has_floor() or _direction_held() or _ui_busy():
		return
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * mb.position
	var node: NPCNode = npc_at(world)
	if node == null:
		close_card()
		return
	open_card(node.npc_id)
	get_viewport().set_input_as_handled()


## Personaje bajo `world_pos` (su cuerpo, algo por encima de los pies) o null.
func npc_at(world_pos: Vector2) -> NPCNode:
	var radius: float = Database.get_balance_float("npc_nodo.radio_seleccion") * _cell
	var best: NPCNode = null
	for node: NPCNode in get_nodes():
		var centre: Vector2 = node.get_visual_position() + Vector2(0.0, -SELECT_LIFT * _cell)
		var d: float = centre.distance_to(world_pos)
		if d <= radius:
			radius = d
			best = node
	return best


func open_card(npc_id: String) -> CharacterCard:
	close_card()
	_card = CharacterCard.open_for(get_tree(), npc_id)
	return _card


func close_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


func get_card() -> CharacterCard:
	return _card if _card != null and is_instance_valid(_card) else null


func _direction_held() -> bool:
	for action: String in MOVE_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func _ui_busy() -> bool:
	var ui: UIRoot = UIRoot.find(get_tree())
	return ui != null and ui.has_modal()
