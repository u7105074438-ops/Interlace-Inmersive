# _security_keeper.gd — Nodo de escena del módulo de seguridad: cuerpos visibles y su arrastre (también en el montacargas), apagones (cámaras, lectores y penumbra), puntos de lector para tarjetas ajenas y el trabajo nocturno (copias de seguridad, sabotajes de coche).
# PROPIETARIO DE: los BodyNode y los puntos de lector de la planta actual, el cuerpo arrastrado (transitorio) y la penumbra del apagón. Lo persistente vive en banderas secops.* de PlayerState y en NPCDirector (cuerpos).
# ESCUCHA: FloorStreamer.floor_loaded, FloorTravel.travel_started/travel_finished, body_created (vía hook), body_discovered, day_advanced, player_caught_redhanded, run_started, run_loaded.
class_name SecurityKeeper
extends Node

## ensure(tree) lo crea bajo GameRoot si falta: al cargarse el módulo (hook(), diferido), en cada
## interacción del módulo, al cambiar de planta, al cargar partida y al crearse un cuerpo (ver
## REQUEST en el informe: GameRoot debería llamarlo al montar la escena, antes del primer foco).
## CUERPOS: un BodyNode por cuerpo no escondido ni hallado cuya sala está en la planta cargada, en la
## posición guardada (bandera secops.body_pos) o donde cayó la víctima. Arrastrar (start_drag) pone
## al jugador en paso "drag" (lento); el cuerpo le sigue detrás. Cambiar de planta arrastrando solo
## es posible por un tránsito que admite bultos (FloorTravel.BULK_KINDS: montacargas, salida): en
## cualquier otro cambio (desalojo del cierre) el cuerpo se queda donde estaba.
## APAGÓN: SecurityPower guarda el corte programado; aquí se aplica a la planta cargada (cámaras
## inactivas, lectores sin bloqueo, penumbra) y se anuncia el inicio y el final.
## LECTORES: dos puntos "door_reader" por puerta con lector (uno a cada lado) para usar una tarjeta
## robada o clonada; solo se ofrecen si hacen falta (SecurityLocks.reader_available).

const GROUP := "security_keeper"
const NODES_GROUP := "secops_nodes"
const READER_TYPE := "door_reader"
const READER_ID_FORMAT := "reader_%s_%d"
const SIDES: Array[float] = [-1.0, 1.0]
const F_BODY_POS := "body_pos"
const SFX_WARN := "ui_notify"

static var _hooked: bool = false

## Pruebas y QA: actos de un fotograma.
var instant: bool = false
var _root: GameRoot = null
var _streamer: FloorStreamer = null
var _player: Player = null
var _bodies: Dictionary = {}
var _dragged: String = ""
var _drag_floor: int = 0
var _carrying: bool = false
var _shade: Node2D = null
var _tick_left: float = 0.0


static func find(tree: SceneTree) -> SecurityKeeper:
	return tree.get_first_node_in_group(GROUP) as SecurityKeeper if tree != null else null


## El keeper de la escena de juego (lo crea si falta; null si no hay GameRoot).
static func ensure(tree: SceneTree) -> SecurityKeeper:
	hook()
	var keeper: SecurityKeeper = find(tree)
	if keeper != null or tree == null:
		return keeper
	var root: GameRoot = GameRoot.find(tree)
	if root == null or root.streamer == null or root.player == null:
		return null
	keeper = SecurityKeeper.new()
	keeper.name = "SecurityKeeper"
	root.add_child(keeper)
	keeper.setup(root)
	return keeper


## Engancha el bus una sola vez por proceso: un cuerpo nuevo, una carga o un cambio de planta
## despiertan al keeper (y le pasan el cuerpo recién creado).
static func hook() -> void:
	if _hooked or Engine.is_editor_hint():
		return
	_hooked = true
	EventBus.body_created.connect(func(body_id: String, npc_id: String, room_id: String) -> void:
		var keeper: SecurityKeeper = ensure(Engine.get_main_loop() as SceneTree)
		if keeper != null:
			keeper.on_body_created(body_id, npc_id, room_id))
	EventBus.run_loaded.connect(func(_day: int) -> void: ensure(Engine.get_main_loop() as SceneTree))
	EventBus.floor_changed.connect(func(_a: int, _b: int) -> void: ensure(Engine.get_main_loop() as SceneTree))
	(func() -> void: ensure(Engine.get_main_loop() as SceneTree)).call_deferred()


func _ready() -> void:
	add_to_group(GROUP)


func setup(root: GameRoot) -> void:
	_root = root
	_streamer = root.streamer
	_player = root.player
	_streamer.floor_loaded.connect(_on_floor_loaded)
	if root.travel != null:
		root.travel.travel_started.connect(_on_travel_started)
		root.travel.travel_finished.connect(_on_travel_finished)
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.player_caught_redhanded.connect(func(_n: String, _c: String, _w: int) -> void: drop_here())
	EventBus.run_started.connect(func(_seed: int) -> void: _reset())
	EventBus.run_loaded.connect(func(_day: int) -> void: _reset())
	_drag_floor = _streamer.get_current_floor()
	sync_floor()
	_announce_restores(SecurityRecords.restore_due())


func ctx() -> Dictionary:
	return {"game_root": _root, "ui_root": _root.ui if _root != null else null, "streamer": _streamer}


# ─── Planta ───────────────────────────────────────────────────

## Reconstruye lo del módulo en la planta cargada: cuerpos, puntos de lector y apagón.
func sync_floor() -> void:
	for node: Node in get_tree().get_nodes_in_group(NODES_GROUP):
		if node != body_node(_dragged):
			node.queue_free()
	for npc_id: String in _bodies.keys():
		if npc_id != _dragged:
			_bodies.erase(npc_id)
	_spawn_bodies()
	_spawn_reader_points()
	apply_blackout()


func _on_floor_loaded(floor_number: int) -> void:
	if is_dragging() and not _carrying:
		_leave_behind()
	_carrying = false
	_drag_floor = floor_number
	sync_floor()


func _reset() -> void:
	_dragged = ""
	_carrying = false
	if _player != null:
		_player.set_dragging(false)
	sync_floor()


func _physics_process(delta: float) -> void:
	if is_dragging():
		_follow()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = SecurityKit.bf("apagon.intervalo_s")
		_tick_blackout()


# ─── Cuerpos ──────────────────────────────────────────────────

func body_node(npc_id: String) -> BodyNode:
	var node: Variant = _bodies.get(npc_id)
	return node as BodyNode if node != null and is_instance_valid(node) else null


func get_body_nodes() -> Array[BodyNode]:
	var out: Array[BodyNode] = []
	for npc_id: String in _bodies:
		if body_node(npc_id) != null:
			out.append(body_node(npc_id))
	return out


func get_dragged() -> String:
	return _dragged


func is_dragging() -> bool:
	return not _dragged.is_empty() and body_node(_dragged) != null


func _spawn_bodies() -> void:
	for info: Dictionary in NPCDirector.get_all_bodies():
		var npc_id: String = str(info["npc_id"])
		var room_id: String = str(info.get("room_id", ""))
		if npc_id == _dragged or bool(info.get("hidden", false)) or bool(info.get("discovered", false)):
			continue
		if not _streamer.get_room_rect_px(room_id).has_area():
			continue
		spawn_body(npc_id, _stored_position(npc_id, room_id))


func spawn_body(npc_id: String, pos: Vector2) -> BodyNode:
	if body_node(npc_id) != null:
		return body_node(npc_id)
	var info: Dictionary = NPCDirector.get_body_info(npc_id)
	var node: BodyNode = BodyNode.new()
	node.setup_body(npc_id, str(info.get("body_id", "")), str(info.get("room_id", "")), RoomBuilder.cell_px())
	node.add_to_group(NODES_GROUP)
	_streamer.get_actor_layer().add_child(node)
	node.global_position = pos
	_bodies[npc_id] = node
	remember_position(npc_id, pos)
	return node


## body_created (vía hook): el cuerpo aparece donde cayó la víctima (su nodo) o en su sala.
func on_body_created(_body_id: String, npc_id: String, room_id: String) -> void:
	if not _streamer.get_room_rect_px(room_id).has_area():
		return
	var pos: Vector2 = _streamer.get_spawn_point(room_id)
	var layer: NPCLayer = _root.npc_layer if _root != null else null
	var victim: NPCNode = layer.get_node_for(npc_id) if layer != null else null
	if victim != null:
		pos = victim.global_position
	var node: BodyNode = spawn_body(npc_id, pos)
	node.global_position = pos
	remember_position(npc_id, pos)
	SecurityKit.toast(ctx(), "SECOPS_BODY_CREATED", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_WARN)


func _on_body_discovered(body_id: String, _room_id: String) -> void:
	var npc_id: String = NPCDirector.get_body_npc(body_id)
	if npc_id.is_empty():
		return
	if npc_id == _dragged:
		release_body()
	var node: BodyNode = body_node(npc_id)
	if node != null:
		node.queue_free()
	_bodies.erase(npc_id)
	SecurityKit.toast(ctx(), "SECOPS_BODY_FOUND", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_BAD)


func remember_position(npc_id: String, pos: Vector2) -> void:
	var stored: Dictionary = SecurityKit.flag_dict(F_BODY_POS)
	stored[npc_id] = [_streamer.get_current_floor(), pos.x, pos.y]
	SecurityKit.set_flag(F_BODY_POS, stored)


func _stored_position(npc_id: String, room_id: String) -> Vector2:
	var entry: Variant = SecurityKit.flag_dict(F_BODY_POS).get(npc_id)
	if entry is Array and (entry as Array).size() == 3 and int(entry[0]) == _streamer.get_current_floor():
		var pos: Vector2 = Vector2(float(entry[1]), float(entry[2]))
		if _streamer.get_room_rect_px(room_id).has_point(pos):
			return pos
	return _streamer.get_spawn_point(room_id)


# ─── Arrastre ─────────────────────────────────────────────────

func start_drag(npc_id: String) -> bool:
	var node: BodyNode = body_node(npc_id)
	if node == null or _player == null:
		return false
	if is_dragging():
		drop_here()
	_dragged = npc_id
	_drag_floor = _streamer.get_current_floor()
	node.set_dragged(true, _player.global_position - node.global_position)
	node.yield_check = has_body_target_near
	_player.set_dragging(true)
	_player.play_anim("drag")
	return true


## Deja de arrastrar. Con `spot_id` el cuerpo desaparece (escondido o tirado); sin él queda en el
## suelo donde está. Devuelve el personaje soltado ("" si no se arrastraba nada). La lógica del
## registro (NPCDirector, delito) la hace SecurityBodies.settle.
func release_body(spot_id: String = "") -> String:
	if _dragged.is_empty():
		return ""
	var npc_id: String = _dragged
	_dragged = ""
	if _player != null:
		_player.set_dragging(false)
	var node: BodyNode = body_node(npc_id)
	if node == null:
		return npc_id
	node.set_dragged(false, BodyNode.REST_HEADING)
	if spot_id.is_empty():
		node.room_id = _streamer.get_room_at(node.global_position)
		remember_position(npc_id, node.global_position)
	else:
		node.queue_free()
		_bodies.erase(npc_id)
	return npc_id


## Suelta el cuerpo arrastrado donde está (flagrancia, E lejos de todo destino).
func drop_here() -> String:
	var node: BodyNode = body_node(_dragged)
	if node == null:
		_dragged = ""
		return ""
	var room_id: String = _streamer.get_room_at(node.global_position)
	var npc_id: String = release_body()
	SecurityBodies.settle(npc_id, room_id if not room_id.is_empty() else node.room_id, "", false)
	return npc_id


func _follow() -> void:
	var node: BodyNode = body_node(_dragged)
	var back: Vector2 = -_player.get_facing()
	var reach: float = SecurityKit.bf("cuerpos.distancia_arrastre") * RoomBuilder.cell_px()
	node.global_position = _player.global_position + back * reach
	node.face(_player.global_position - node.global_position)
	var room_id: String = _streamer.get_room_at(node.global_position)
	if not room_id.is_empty():
		node.room_id = room_id


## Otro cambio de planta con un cuerpo a rastras (desalojo del cierre): se queda donde estaba.
func _leave_behind() -> void:
	var node: BodyNode = body_node(_dragged)
	var room_id: String = node.room_id
	var pos: Vector2 = node.global_position
	var npc_id: String = release_body()
	var stored: Dictionary = SecurityKit.flag_dict(F_BODY_POS)
	stored[npc_id] = [_drag_floor, pos.x, pos.y]
	SecurityKit.set_flag(F_BODY_POS, stored)
	SecurityBodies.settle(npc_id, room_id, "", false)
	SecurityKit.toast(ctx(), "SECOPS_BODY_LEFT_BEHIND", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_WARN)


func _on_travel_started(kind: String, _from_floor: int, _to_floor: int) -> void:
	_carrying = is_dragging() and FloorTravel.BULK_KINDS.has(kind)


func _on_travel_finished(_kind: String, _floor_number: int, room_id: String) -> void:
	_carrying = false
	if not is_dragging():
		return
	_follow()
	remember_position(_dragged, body_node(_dragged).global_position)
	SecurityBodies.settle(_dragged, room_id, "", false)


## Mientras se arrastra: ¿hay cerca un destino para el cuerpo? (el cuerpo cede el foco).
func has_body_target_near() -> bool:
	if _player == null:
		return false
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var item: Interactable = node as Interactable
		if item == null or item is BodyNode or not SecurityBodies.is_body_target(item):
			continue
		if item.global_position.distance_to(_player.global_position) <= item.get_use_radius():
			return true
	return false


# ─── Puntos de lector (tarjetas ajenas) ───────────────────────

func _spawn_reader_points() -> void:
	var offset: float = SecurityKit.bf("tarjetas.distancia_lector") * RoomBuilder.cell_px()
	for door: Door in _streamer.get_doors():
		if door.kind != Door.KIND_READER:
			continue
		var centre: Vector2 = door.to_global(door.gap_rect().get_center())
		var normal: Vector2 = Vector2.RIGHT if door.vertical else Vector2.DOWN
		for side: float in SIDES:
			var point: Vector2 = centre + normal * side * offset
			var room_id: String = _streamer.get_room_at(point)
			if room_id.is_empty():
				continue
			var node: Interactable = Interactable.new()
			node.setup(READER_ID_FORMAT % [door.door_id, int(side)], READER_TYPE, room_id, {"door_id": door.door_id},
					RoomBuilder.cell_px(), Vector2.ZERO)
			node.add_to_group(NODES_GROUP)
			_streamer.get_actor_layer().add_child(node)
			node.global_position = point


# ─── Apagón ───────────────────────────────────────────────────

func _tick_blackout() -> void:
	var change: Dictionary = SecurityPower.update_blackout()
	if change.is_empty():
		return
	var floor_label: String = MapView.floor_label_short(int(change["floor"]))
	if str(change["change"]) == SecurityPower.BLACKOUT_STARTED:
		SecurityKit.toast(ctx(), "SECOPS_BLACKOUT_ON", [floor_label, SecurityKit.bi("apagon.minutos")], ToastStack.KIND_WARN)
	else:
		SecurityKit.toast(ctx(), "SECOPS_BLACKOUT_OFF", [floor_label], ToastStack.KIND_INFO)
	SecurityKit.sfx(self, SFX_WARN)
	apply_blackout()


## Cámaras, lectores y penumbra de la planta cargada según el apagón en curso.
func apply_blackout() -> void:
	var dark: bool = SecurityPower.is_blackout_on(_streamer.get_current_floor())
	for cam: SecurityCamera in _streamer.get_cameras():
		cam.set_active(not dark)
	for door: Door in _streamer.get_doors():
		if door.kind == Door.KIND_READER:
			door.set_locked(not dark)
	_set_shade(dark)


func _set_shade(dark: bool) -> void:
	if not dark:
		if _shade != null and is_instance_valid(_shade):
			_shade.queue_free()
		_shade = null
		return
	if _shade != null and is_instance_valid(_shade):
		return
	var shade: FloorLighting.Shade = FloorLighting.Shade.new()
	shade.name = "BlackoutShade"
	shade.material = FloorLighting.multiply_material()
	shade.z_as_relative = false
	shade.z_index = FloorLighting.Z_SHADE + 1
	shade.rect = _streamer.get_floor_rect_px()
	var rgb: Array = SecurityKit.barr("apagon.sombra")
	shade.color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	_streamer.add_child(shade)
	shade.global_position = Vector2.ZERO
	_shade = shade


func is_shade_visible() -> bool:
	return _shade != null and is_instance_valid(_shade)


# ─── Trabajo nocturno ─────────────────────────────────────────

func _on_day_advanced(day_number: int) -> void:
	_announce_restores(SecurityRecords.restore_due())
	var sabotaged: Array[String] = SecurityPower.apply_car_sabotage(day_number)
	for npc_id: String in sabotaged:
		SecurityKit.toast(ctx(), "SECOPS_CAR_BROKE_DOWN", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_GOOD)


func _announce_restores(count: int) -> void:
	if count <= 0:
		return
	SecurityKit.toast(ctx(), "SECOPS_BACKUP_RESTORED", [count], ToastStack.KIND_BAD)
	SecurityKit.note("SECOPS_NOTE_RESTORED", [count])
