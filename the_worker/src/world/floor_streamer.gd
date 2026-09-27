# floor_streamer.gd — Carga la planta actual (una sola instanciada), sigue la sala del jugador y da rutas.
# PROPIETARIO DE: la planta instanciada, la caché de planos, el grafo de navegación y la sala del jugador.
# ESCUCHA: nada (emite room_entered/room_exited del jugador y floor_changed; sondea el grupo "player").
class_name FloorStreamer
extends Node2D

## Contrato BUILD_NOTES §14 / PASO 40:
##   load_floor(floor) · get_current_floor() · get_room_at(world_pos) · get_room_rect_px(room_id)
##   cell_to_world(floor_cell) · find_path(from_px, to_room_id) · get_spawn_point(room_id)
##   get_interactables_in_room(room_id)
## Coordenadas: las posiciones "world"/px son globales (se convierten con to_local/to_global, así
## que game_root puede desplazar el streamer); get_room_rect_px devuelve px globales también.
## Puertas con control de acceso (Door): get_door_node(a, b), get_door_by_id(id), get_doors();
## set_door_policy(Callable(door, body) -> bool) decide si el jugador pasa (por defecto: su
## acreditación y acceso especial; lectores y tornos anotan el paso en Security.log_card_access).
## floor_changed lo emite SOLO el streamer, al cargar otra planta (el diálogo de planta llama a
## load_floor; no debe emitirlo él también).
## Solo la planta actual existe como nodos; los planos (FloorLayout) de la actual y las adyacentes
## quedan en caché. Emite EventBus.room_exited/room_entered(room, true) al cambiar el jugador de sala
## (cada fotograma físico) y EventBus.floor_changed(old, new) al cargar otra planta (en la primera
## carga, old = mundo.planta_transversal). Los actores (jugador, NPC) deben ir bajo get_actor_layer()
## para ordenarse en Y con los muebles; el streamer no los libera al cambiar de planta.
## Está en el grupo "floor_streamer" (FloorStreamer.find_in(get_tree())).

signal floor_loaded(floor_number: int)
signal door_crossed(door: Dictionary, from_room: String, to_room: String)
## Reenvío de Door.access_requested (el jugador ante una puerta que no se le abre).
signal door_access_requested(door: Door)

const GROUP := "floor_streamer"
const PLAYER_GROUP := "player"
const PLAYER_CARD := "player"
const MODE_AND := "and"
const MODE_OR := "or"
const NO_CELL := Vector2i(-1, -1)
const ADJACENT_FLOORS := [-1, 1]
const NO_INITIAL_FLOOR := -9999

## Solo para escenas de prueba (scenes/world/floor_test.tscn): planta que se carga al arrancar.
@export var initial_floor: int = NO_INITIAL_FLOOR

var _floor: int = 0
var _has_floor: bool = false
var _plan: Dictionary = {}
var _plans: Dictionary = {}
var _cell: float = 48.0
var _actor_layer: Node2D = null
var _floor_root: Node2D = null
var _props_root: Node2D = null
var _index: Dictionary = {}
var _room_ids: Array[String] = []
var _cell_owner: PackedInt32Array = []
var _walkable: PackedByteArray = []
var _blocked_edges: Dictionary = {}
var _astar: AStar2D = AStar2D.new()
var _spawn_cells: Dictionary = {}
var _player: Node2D = null
var _player_room: String = ""
var _door_policy: Callable = Callable()


func _ready() -> void:
	add_to_group(GROUP)
	_ensure_layers()
	if initial_floor != NO_INITIAL_FLOOR:
		Database.load_all()
		load_floor.call_deferred(initial_floor)


func _ensure_layers() -> void:
	if _actor_layer != null:
		return
	_actor_layer = Node2D.new()
	_actor_layer.name = "Actors"
	_actor_layer.y_sort_enabled = true
	add_child(_actor_layer)


## El streamer activo del árbol (grupo "floor_streamer"), o null.
static func find_in(tree: SceneTree) -> FloorStreamer:
	return tree.get_first_node_in_group(GROUP) as FloorStreamer


# ─── Carga ────────────────────────────────────────────────────

## Sustituye la planta instanciada (libera la anterior en el acto). Llamar desde _process, una
## entrada o call_deferred; nunca desde una señal de física (body_entered…), que no admite
## liberar cuerpos durante el vaciado de consultas.
@warning_ignore("shadowed_global_identifier")
func load_floor(floor: int) -> void:
	_ensure_layers()
	var old_floor: int = _floor if _has_floor else Database.get_balance_int("mundo.planta_transversal")
	if _has_floor and not _player_room.is_empty():
		EventBus.room_exited.emit(_player_room, true)
	_player_room = ""
	_unload()
	_cell = RoomBuilder.cell_px()
	_plan = get_plan_for(floor)
	_floor = floor
	_has_floor = true
	_build_nodes()
	_build_navigation()
	_prefetch_adjacent()
	floor_loaded.emit(floor)
	if old_floor != floor:
		EventBus.floor_changed.emit(old_floor, floor)


func _unload() -> void:
	if _floor_root != null:
		_floor_root.free()
		_floor_root = null
	if _props_root != null:
		_props_root.free()
		_props_root = null
	_index = {}


func _build_nodes() -> void:
	_floor_root = Node2D.new()
	_floor_root.name = "Floor_%d" % _floor
	add_child(_floor_root)
	move_child(_floor_root, 0)
	_props_root = Node2D.new()
	_props_root.name = "Props_%d" % _floor
	_props_root.y_sort_enabled = true
	_actor_layer.add_child(_props_root)
	_actor_layer.move_child(_props_root, 0)
	_index = RoomBuilder.build_floor(_plan, _floor_root, _props_root)
	for door: Door in get_doors():
		door.policy = _apply_door_policy
		door.access_requested.connect(func(d: Door, _body: Node2D) -> void: door_access_requested.emit(d))


## Plano (en caché) de cualquier planta.
@warning_ignore("shadowed_global_identifier")
func get_plan_for(floor: int) -> Dictionary:
	if not _plans.has(floor):
		_plans[floor] = FloorLayout.compute(floor)
	return _plans[floor]


func _prefetch_adjacent() -> void:
	var floors: Array[int] = Database.get_floor_ids()
	for delta: int in ADJACENT_FLOORS:
		if floors.has(_floor + delta):
			get_plan_for(_floor + delta)


func get_current_floor() -> int:
	return _floor


func get_plan() -> Dictionary:
	return _plan


func get_actor_layer() -> Node2D:
	_ensure_layers()
	return _actor_layer


## Rectángulo de la planta en px globales (para límites de cámara y el mapa).
func get_floor_rect_px() -> Rect2:
	return Rect2(global_position, Vector2(_plan.get("size", Vector2i.ZERO)) * _cell)


# ─── Geometría ────────────────────────────────────────────────

func get_room_at(world_pos: Vector2) -> String:
	var c: Vector2i = world_to_cell(world_pos)
	var i: int = _cell_index(c)
	if i < 0 or _cell_owner[i] <= 0:
		return ""
	return _room_ids[_cell_owner[i] - 1]


func get_room_rect_px(room_id: String) -> Rect2:
	var rooms: Dictionary = _plan.get("rooms", {})
	if not rooms.has(room_id):
		return Rect2()
	var r: Rect2i = rooms[room_id]
	return Rect2(to_global(Vector2(r.position) * _cell), Vector2(r.size) * _cell)


## Centro en px globales de una celda de planta.
func cell_to_world(floor_cell: Vector2i) -> Vector2:
	return to_global((Vector2(floor_cell) + Vector2(0.5, 0.5)) * _cell)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = to_local(world_pos)
	return Vector2i(floori(local.x / _cell), floori(local.y / _cell))


func _cell_index(c: Vector2i) -> int:
	var size: Vector2i = _plan.get("size", Vector2i.ZERO)
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return -1
	return c.y * size.x + c.x


func get_spawn_point(room_id: String) -> Vector2:
	if not _spawn_cells.has(room_id):
		return get_room_rect_px(room_id).get_center()
	return cell_to_world(_spawn_cells[room_id])


## Punto de uso de un tránsito del plano (id de tránsito o de su sala).
func get_transit_point(transit_or_room_id: String) -> Vector2:
	var t: Dictionary = FloorLayout.find_transit(_plan, transit_or_room_id)
	return Vector2.ZERO if t.is_empty() else cell_to_world(t["cell"])


## Dónde aparece quien llega desde `source_room` (otra planta) por un tránsito de tipo `kind`.
func get_arrival_point(source_room: String, kind: String) -> Vector2:
	var t: Dictionary = FloorLayout.find_arrival(_plan, source_room, kind)
	return Vector2.ZERO if t.is_empty() else cell_to_world(t["cell"])


## Puerta transitable entre dos salas ({} si no hay): {a, b, cell, vertical, kind, clearance…}.
func get_door_between(a: String, b: String) -> Dictionary:
	for door: Dictionary in _plan.get("doors", []):
		if door["walkable"] and ((door["a"] == a and door["b"] == b) or (door["a"] == b and door["b"] == a)):
			return door
	return {}


func get_interactables_in_room(room_id: String) -> Array[Interactable]:
	var out: Array[Interactable] = []
	out.assign(_index.get("interactables", {}).get(room_id, []))
	return out


func get_hiding_spots_in_room(room_id: String) -> Array[HidingSpot]:
	var out: Array[HidingSpot] = []
	out.assign(_index.get("hiding", {}).get(room_id, []))
	return out


func get_cameras() -> Array[SecurityCamera]:
	var out: Array[SecurityCamera] = []
	out.assign(_index.get("cameras", []))
	return out


## Puestos de trabajo de una sala: [{owner, type, furniture_index, cell, pos (px globales: el
## punto exacto de la silla), facing}]. Un actor con su origen en `pos` queda sentado y visible.
func get_seats_in_room(room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat: Dictionary in _index.get("seats", {}).get(room_id, []):
		out.append(seat.merged({"pos": to_global(seat["pos"])}, true))
	return out


func get_room_node(room_id: String) -> Node2D:
	return _index.get("rooms", {}).get(room_id) as Node2D


# ─── Puertas con control de acceso ────────────────────────────

func get_doors() -> Array[Door]:
	var out: Array[Door] = []
	out.assign(_index.get("doors", []))
	return out


## Nodo Door de la puerta entre a y b (en cualquier orden), o null si es un hueco normal.
func get_door_node(a: String, b: String) -> Door:
	for door: Door in get_doors():
		if (door.room_a == a and door.room_b == b) or (door.room_a == b and door.room_b == a):
			return door
	return null


## Door por id ("door_<a>_<b>", o el id del interactivo del torno), o null.
func get_door_by_id(door_id: String) -> Door:
	for door: Door in get_doors():
		if door.door_id == door_id:
			return door
	return null


## Sustituye la política de acceso del jugador (Callable(door: Door, body: Node2D) -> bool).
## Callable() vacío restaura la de por defecto.
func set_door_policy(policy: Callable) -> void:
	_door_policy = policy


func _apply_door_policy(door: Door, body: Node2D) -> bool:
	if _door_policy.is_valid():
		return bool(_door_policy.call(door, body))
	return default_door_policy(door, body)


## Por defecto: cerradura antigua nunca (la abre el interactivo lock_old con llaves); el resto si la
## acreditación del jugador llega y, si la sala pide acceso especial, según su modo (and/or).
## Lectores y tornos dejan constancia en Security (card_reader_logged). Servicio: sin registro.
func default_door_policy(door: Door, _body: Node2D) -> bool:
	if door.kind == Door.KIND_OLD_LOCK or not _player_meets(door):
		return false
	if door.kind != Door.KIND_SERVICE:
		Security.log_card_access(door.door_id, PLAYER_CARD, GameClock.get_day(), GameClock.get_hour(), door.room_b)
	return true


func _player_meets(door: Door) -> bool:
	var level_ok: bool = PlayerState.get_clearance() >= door.clearance
	if door.special_access.is_empty():
		return level_ok
	var occupation: OccupationData = PlayerState.get_occupation()
	var special_ok: bool = false
	for tag: String in door.special_access:
		if occupation != null and occupation.special_access.has(tag):
			special_ok = true
	if door.special_mode == MODE_OR:
		return level_ok or special_ok
	return level_ok and special_ok if door.special_mode == MODE_AND else level_ok


# ─── Navegación ───────────────────────────────────────────────

func _build_navigation() -> void:
	var size: Vector2i = _plan["size"]
	_room_ids.clear()
	_cell_owner = PackedInt32Array()
	_cell_owner.resize(size.x * size.y)
	_walkable = PackedByteArray()
	_walkable.resize(size.x * size.y)
	_blocked_edges.clear()
	_astar.clear()
	_spawn_cells.clear()
	for room_id: String in _plan["order"]:
		_room_ids.append(room_id)
		_mark_room(room_id, _room_ids.size())
	_add_nav_points(size)
	_connect_inside(size)
	_connect_doors()
	_disable_isolated()
	for room_id: String in _room_ids:
		_spawn_cells[room_id] = _find_spawn_cell(room_id)


func _mark_room(room_id: String, owner: int) -> void:
	var rect: Rect2i = _plan["rooms"][room_id]
	var room: RoomData = Database.get_room(room_id)
	var decor: Array = _plan.get("decor", {}).get(room_id, [])
	var blocked: Dictionary = FloorLayout.blocked_cells(room, rect, decor) if room != null else {}
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var i: int = _cell_index(Vector2i(x, y))
			_cell_owner[i] = owner
			_walkable[i] = 0 if blocked.has(Vector2i(x, y)) else 1
	if room == null:
		return
	_block_face_row(room_id, rect)
	for entry: Dictionary in FloorLayout.room_furniture(room):
		if FurniturePainter.is_enclosure(str(entry["type"])):
			_block_enclosure_sides(entry, rect.position)


## La fila superior queda bajo la cara 3/4 del muro norte (su colisión la cubre): no transitable,
## salvo las celdas de los huecos de puerta de ese muro.
func _block_face_row(room_id: String, rect: Rect2i) -> void:
	if rect.size.y < Database.get_balance_int("mundo.alto_minimo_fila_muro"):
		return
	var open_x: Dictionary = {}
	for door: Dictionary in _plan["doors"]:
		var c: Vector2i = door["cell"]
		if door["walkable"] and not door["vertical"] and c.y == rect.position.y and (door["a"] == room_id or door["b"] == room_id):
			for k: int in int(door["width"]):
				open_x[c.x + k] = true
	for x: int in range(rect.position.x, rect.end.x):
		if not open_x.has(x):
			_walkable[_cell_index(Vector2i(x, rect.position.y))] = 0


## Las mamparas laterales de un recinto (cubículo, cabina) impiden entrar por los costados de su
## fila abierta: solo se entra por delante.
func _block_enclosure_sides(entry: Dictionary, origin: Vector2i) -> void:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	var row: int = origin.y + FurniturePainter.open_row(entry)
	var left: Vector2i = Vector2i(origin.x + fp.position.x, row)
	var right: Vector2i = Vector2i(origin.x + fp.end.x - 1, row)
	_blocked_edges[_edge_key(left, left + Vector2i.LEFT)] = true
	_blocked_edges[_edge_key(right, right + Vector2i.RIGHT)] = true


func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y) if (a.x < b.x or (a.x == b.x and a.y < b.y)) else Vector4i(b.x, b.y, a.x, a.y)


func _add_nav_points(size: Vector2i) -> void:
	for y: int in size.y:
		for x: int in size.x:
			var i: int = y * size.x + x
			if _cell_owner[i] > 0 and _walkable[i] == 1:
				_astar.add_point(i, (Vector2(x, y) + Vector2(0.5, 0.5)) * _cell)


func _can_step(a: Vector2i, b: Vector2i) -> bool:
	var ia: int = _cell_index(a)
	var ib: int = _cell_index(b)
	if ia < 0 or ib < 0 or _walkable[ia] == 0 or _walkable[ib] == 0:
		return false
	return _cell_owner[ia] == _cell_owner[ib] and not _blocked_edges.has(_edge_key(a, b))


func _connect_inside(size: Vector2i) -> void:
	for y: int in size.y:
		for x: int in size.x:
			var c: Vector2i = Vector2i(x, y)
			if not _astar.has_point(_cell_index(c)):
				continue
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				if _can_step(c, c + d):
					_astar.connect_points(_cell_index(c), _cell_index(c + d))
			for d: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1)]:
				var side_a: Vector2i = c + Vector2i(d.x, 0)
				var side_b: Vector2i = c + Vector2i(0, d.y)
				if _can_step(c, side_a) and _can_step(c, side_b) and _can_step(side_a, c + d) \
						and _can_step(side_b, c + d):
					_astar.connect_points(_cell_index(c), _cell_index(c + d))


## Une las celdas a ambos lados de cada hueco de puerta transitable.
func _connect_doors() -> void:
	for door: Dictionary in _plan["doors"]:
		if not door["walkable"]:
			continue
		var start: Vector2i = door["cell"]
		for k: int in int(door["width"]):
			var inner: Vector2i = start + (Vector2i(0, k) if door["vertical"] else Vector2i(k, 0))
			var outer: Vector2i = inner - (Vector2i(1, 0) if door["vertical"] else Vector2i(0, 1))
			var ia: int = _cell_index(inner)
			var ib: int = _cell_index(outer)
			if ia >= 0 and ib >= 0 and _astar.has_point(ia) and _astar.has_point(ib):
				_astar.connect_points(ia, ib)


## Celda de planta transitable (dentro de una sala y sin mueble que bloquee).
func is_walkable_cell(floor_cell: Vector2i) -> bool:
	var i: int = _cell_index(floor_cell)
	return i >= 0 and _cell_owner[i] > 0 and _walkable[i] == 1


## Centro (px globales) de la celda transitable y conectada más cercana, o Vector2.INF.
func nearest_walkable_point(world_pos: Vector2) -> Vector2:
	if _astar.get_point_count() == 0:
		return Vector2.INF
	var id: int = _astar.get_closest_point(to_local(world_pos))
	return Vector2.INF if id < 0 else to_global(_astar.get_point_position(id))


## Las celdas sin vecinos transitables (encerradas por muebles) no cuentan como destino.
func _disable_isolated() -> void:
	for id: int in _astar.get_point_ids():
		if _astar.get_point_connections(id).is_empty():
			_astar.set_point_disabled(id, true)


func _find_spawn_cell(room_id: String) -> Vector2i:
	var rect: Rect2i = _plan["rooms"][room_id]
	var centre: Vector2i = rect.get_center()
	var best: Vector2i = NO_CELL
	var best_d: int = 1 << 30
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var i: int = _cell_index(Vector2i(x, y))
			if not _astar.has_point(i) or _astar.get_point_connections(i).is_empty():
				continue
			var d: int = (Vector2i(x, y) - centre).length_squared()
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best if best != NO_CELL else centre


## Ruta (px) desde from_px hasta el punto de aparición de la sala; vacía si no hay camino.
func find_path(from_px: Vector2, to_room_id: String) -> PackedVector2Array:
	if not _spawn_cells.has(to_room_id):
		return PackedVector2Array()
	return find_path_to_point(from_px, cell_to_world(_spawn_cells[to_room_id]))


## Ruta (px) entre dos puntos cualesquiera de la planta (p. ej. hasta el asiento de un puesto).
func find_path_to_point(from_px: Vector2, to_px: Vector2) -> PackedVector2Array:
	if _astar.get_point_count() == 0:
		return PackedVector2Array()
	var a: int = _nearest_point(from_px)
	var b: int = _nearest_point(to_px)
	if a < 0 or b < 0:
		return PackedVector2Array()
	var path: PackedVector2Array = _simplify(_astar.get_point_path(a, b))
	for i: int in path.size():
		path[i] = to_global(path[i])
	return path


func _nearest_point(px: Vector2) -> int:
	var i: int = _cell_index(world_to_cell(px))
	if i >= 0 and _astar.has_point(i) and not _astar.get_point_connections(i).is_empty():
		return i
	return _astar.get_closest_point(to_local(px))


func _simplify(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 3:
		return path
	var out: PackedVector2Array = [path[0]]
	for i: int in range(1, path.size() - 1):
		var d1: Vector2 = (path[i] - path[i - 1]).normalized()
		var d2: Vector2 = (path[i + 1] - path[i]).normalized()
		if not d1.is_equal_approx(d2):
			out.append(path[i])
	out.append(path[path.size() - 1])
	return out


# ─── Seguimiento del jugador ──────────────────────────────────

func set_player(player: Node2D) -> void:
	_player = player


func get_player_room() -> String:
	return _player_room


func _physics_process(_delta: float) -> void:
	if not _has_floor:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
		if _player == null:
			return
	var room_id: String = get_room_at(_player.global_position)
	if room_id.is_empty() or room_id == _player_room:
		return
	var previous: String = _player_room
	_player_room = room_id
	if not previous.is_empty():
		EventBus.room_exited.emit(previous, true)
		door_crossed.emit(get_door_between(previous, room_id), previous, room_id)
	EventBus.room_entered.emit(room_id, true)
