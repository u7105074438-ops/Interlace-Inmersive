# room_builder.gd — Construye por código el árbol de nodos de cada sala y de la planta completa.
# PROPIETARIO DE: nada (fábrica de nodos: suelo, muros, puertas, muebles, colisiones, interactivos, cámaras).
# ESCUCHA: nada.
class_name RoomBuilder
extends RefCounted

## PASO 7 + BUILD_NOTES §14. Capas físicas: 1 muros (también puertas cerradas y las puertas de
## cristal de las salidas: una salida solo se cruza con su interactivo), 2 muebles altos (bloquean
## paso y visión), 3 muebles bajos y compuertas de torno (bloquean paso, obstrucción parcial),
## 6 interactivos. Capas de dibujo (z absoluto): fondo -40 · suelo -30 · muros -10 · puertas -8 ·
## muebles y actores 0 (orden Y bajo props_root) · sombra de luz 15 · realce de interactivos 20 ·
## cámaras 30 · luz aditiva 40.
## build_floor() devuelve un índice: {rooms: {id: Node2D}, interactables: {id: [Interactable]},
## hiding: {id: [HidingSpot]}, cameras: [SecurityCamera], seats: {id: [{owner, type,
## furniture_index, cell, pos, facing}]}, doors: [Door]}. `pos` es el punto exacto de la silla.

const LAYER_WALLS := 1
const LAYER_TALL := 2
const LAYER_LOW := 3
const Z_FLOOR := -30
const Z_WALLS := -10
const Z_LIGHT := 40
const COLLISION_INSET := 3.0
const PARTITION_RATIO := 0.125
const EXIT_TYPE := "exit"
const TURNSTILE_TYPE := "turnstile"
const LOCK_TYPE := "lock_old"
const TURNSTILE_ID_FORMAT := "turnstile_%s_%d_%d"
## Muebles con animación ambiental (§14.7): la línea de ensamblaje avanza.
const ANIMATED_TYPES: Array[String] = ["conveyor"]
const SPARKS_TYPE := "industrial_machine"
const SPARKS_BAND := "factory"
## Grosor de la compuerta de torno (fracción de celda).
const GATE_THICKNESS := 0.3


class Prop extends Node2D:
	var painter: FurniturePainter
	var entry: Dictionary
	var footprint: Rect2
	var animated: bool = false
	var time: float = 0.0

	func _ready() -> void:
		set_process(animated)

	func _process(delta: float) -> void:
		time += delta
		queue_redraw()

	func _draw() -> void:
		painter.anim_time = time
		painter.draw_item(self, entry, footprint)


static func cell_px() -> float:
	return float(Database.get_balance_int("mundo.px_por_unidad"))


# ─── Planta ───────────────────────────────────────────────────

## Construye la planta de `plan` bajo floor_root; los muebles altos van a props_root (orden en Y).
static func build_floor(plan: Dictionary, floor_root: Node2D, props_root: Node2D) -> Dictionary:
	var cell: float = cell_px()
	var index: Dictionary = {"rooms": {}, "interactables": {}, "hiding": {}, "cameras": [], "seats": {}, "doors": []}
	var backdrop: FloorBackdrop = FloorBackdrop.new()
	backdrop.setup(plan, cell)
	floor_root.add_child(backdrop)
	for room_id: String in plan["order"]:
		var room: RoomData = Database.get_room(room_id)
		if room != null:
			floor_root.add_child(build_room(room, room_id, plan, props_root, index))
	_add_cameras(plan, cell, index)
	_add_exits(plan, cell, index)
	_add_doors(plan, cell, index)
	_add_turnstiles(plan, cell, index)
	FloorLighting.build(plan, floor_root, cell, index)
	return index


## Construye una sala (nodo en su esquina superior izquierda) y registra sus piezas en `index`.
static func build_room(room: RoomData, room_id: String, plan: Dictionary, props_root: Node2D,
		index: Dictionary) -> Node2D:
	var cell: float = cell_px()
	var rect: Rect2i = plan["rooms"][room_id]
	var style: Dictionary = RoomPainter.style_for(room, room_id, plan, cell)
	var node: Node2D = Node2D.new()
	node.name = "Room_%s" % room_id.validate_node_name()
	node.position = Vector2(rect.position) * cell
	node.set_meta("room_id", room_id)
	var walls: RoomPainter = null
	for layer: int in [RoomPainter.LAYER_FLOOR, RoomPainter.LAYER_WALLS, RoomPainter.LAYER_LIGHT]:
		var painter: RoomPainter = _make_painter(room, room_id, plan, style, layer)
		node.add_child(painter)
		if layer == RoomPainter.LAYER_WALLS:
			walls = painter
	index["rooms"][room_id] = node
	var furniture: Array[Dictionary] = FloorLayout.furniture_of(plan, room)
	_add_props(furniture, style, cell, node.position, props_root)
	_add_wall_collisions(walls, node)
	_add_furniture_collisions(furniture, cell, node)
	_add_interactables(room, room_id, plan, cell, node, index)
	FloorLighting.add_flicker(walls, style, node)
	index["seats"][room_id] = _seats(room, rect, cell)
	return node


static func _make_painter(room: RoomData, room_id: String, plan: Dictionary, style: Dictionary,
		layer: int) -> RoomPainter:
	var painter: RoomPainter = RoomPainter.new()
	painter.setup(room, room_id, plan, style, layer)
	painter.z_as_relative = false
	painter.z_index = [Z_FLOOR, Z_WALLS, Z_LIGHT][layer]
	if layer == RoomPainter.LAYER_LIGHT:
		painter.material = FloorLighting.additive_material()
	return painter


# ─── Muebles ──────────────────────────────────────────────────

## Un Prop por pieza de orden Y (los recintos se parten en fondo y laterales; su suelo y silla van
## a la capa plana de RoomPainter), con el origen donde el mueble se ordena con los actores.
static func _add_props(furniture: Array[Dictionary], style: Dictionary, cell: float, origin: Vector2,
		props_root: Node2D) -> void:
	var painter: FurniturePainter = FurniturePainter.new(style)
	for entry: Dictionary in furniture:
		var type: String = str(entry["type"])
		if not FurniturePainter.is_prop(type) or RoomPainter.WALL_MOUNTED.has(type):
			continue
		var fp: Rect2i = FurniturePainter.footprint(entry)
		for part: Dictionary in FurniturePainter.prop_parts(entry):
			var rows: float = float(part["origin_rows"])
			var prop: Prop = Prop.new()
			prop.painter = painter
			prop.entry = entry.merged({"part": str(part["part"])}, true)
			prop.footprint = Rect2(0, -rows * cell, fp.size.x * cell, fp.size.y * cell)
			prop.position = origin + Vector2(fp.position.x, fp.position.y + rows) * cell
			prop.name = "%s_%d_%d%s" % [type, fp.position.x, fp.position.y, str(part["part"])]
			prop.animated = ANIMATED_TYPES.has(type)
			if type == SPARKS_TYPE and str(style.get("band", "")) == SPARKS_BAND:
				prop.add_child(_sparks(prop.footprint, painter.height_of(type), style))
			props_root.add_child(prop)


## Chispas de la maquinaria de la nave (excepción de contraste §14.3): ráfagas cortas y aditivas.
static func _sparks(footprint: Rect2, height: float, style: Dictionary) -> CPUParticles2D:
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.name = "Sparks"
	sparks.position = Vector2(footprint.get_center().x, footprint.position.y - height * 0.5)
	sparks.amount = Database.get_balance_int("mundo.chispas.cantidad")
	sparks.lifetime = Database.get_balance_float("mundo.chispas.vida")
	sparks.explosiveness = 0.85
	sparks.randomness = 0.6
	sparks.direction = Vector2.UP
	sparks.spread = 70.0
	sparks.gravity = Vector2(0, Database.get_balance_float("mundo.chispas.gravedad"))
	sparks.initial_velocity_min = Database.get_balance_float("mundo.chispas.velocidad_min")
	sparks.initial_velocity_max = Database.get_balance_float("mundo.chispas.velocidad_max")
	sparks.scale_amount_min = 1.5
	sparks.scale_amount_max = 3.0
	sparks.color = (style["pal"] as Dictionary).get("light", Color.WHITE)
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = fade
	sparks.material = FloorLighting.additive_material()
	sparks.z_index = 1
	return sparks


static func _body(layer_number: int, body_name: String) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = body_name
	body.collision_layer = 1 << (layer_number - 1)
	body.collision_mask = 0
	return body


static func _add_shape(body: StaticBody2D, r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = r.size
	shape.shape = box
	shape.position = r.get_center()
	body.add_child(shape)


## Muros de la sala (sin los huecos de puerta; las salidas quedan cerradas por su cristal).
static func _add_wall_collisions(walls: RoomPainter, node: Node2D) -> void:
	var body: StaticBody2D = _body(LAYER_WALLS, "Walls")
	for pair: Array in walls.wall_segments():
		_add_shape(body, walls.segment_rect(int(pair[0]), pair[1]))
	node.add_child(body)


static func _add_furniture_collisions(furniture: Array[Dictionary], cell: float, node: Node2D) -> void:
	var tall: StaticBody2D = _body(LAYER_TALL, "TallFurniture")
	var low: StaticBody2D = _body(LAYER_LOW, "LowFurniture")
	for entry: Dictionary in furniture:
		var blocking: int = FurniturePainter.blocking_of(str(entry["type"]))
		if blocking == FurniturePainter.BLOCK_NONE:
			continue
		var target: StaticBody2D = tall if blocking == FurniturePainter.BLOCK_TALL else low
		for r: Rect2 in _collision_rects(entry, cell):
			_add_shape(target, r)
	node.add_child(tall)
	node.add_child(low)


## Rectángulos de colisión en px locales de sala; un recinto: fila del fondo + tres mamparas.
static func _collision_rects(entry: Dictionary, cell: float) -> Array[Rect2]:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	var r: Rect2 = Rect2(Vector2(fp.position) * cell, Vector2(fp.size) * cell)
	if not FurniturePainter.is_enclosure(str(entry["type"])):
		return [r.grow(-COLLISION_INSET)]
	var t: float = cell * PARTITION_RATIO
	var back: Rect2 = Rect2(r.position.x, FurniturePainter.back_row(entry) * cell, r.size.x, cell)
	var back_y: float = r.position.y if FurniturePainter.opens_south(entry) else r.end.y - t
	return [back.grow(-COLLISION_INSET), Rect2(r.position.x, back_y, r.size.x, t),
			Rect2(r.position.x, r.position.y, t, r.size.y), Rect2(r.end.x - t, r.position.y, t, r.size.y)]


# ─── Interactivos, escondites, asientos ───────────────────────

static func _add_interactables(room: RoomData, room_id: String, plan: Dictionary, cell: float, node: Node2D,
		index: Dictionary) -> void:
	var list: Array[Interactable] = []
	for entry: Dictionary in room.interactables:
		var item: Interactable = Interactable.new()
		var data: Dictionary = entry.duplicate(true)
		var transit: Dictionary = FloorLayout.find_transit(plan, str(entry["id"]))
		if not transit.is_empty() and transit["id"] == entry["id"]:
			data["transit"] = transit
		_link_door(data, room_id, plan)
		item.setup(str(entry["id"]), str(entry["type"]), room_id, data, cell, _cell_center(entry["pos"], cell))
		node.add_child(item)
		list.append(item)
	index["interactables"][room_id] = list
	var spots: Array[HidingSpot] = []
	for entry: Dictionary in room.hiding_spots:
		var spot: HidingSpot = HidingSpot.new()
		spot.setup_spot(entry, room_id, cell, _cell_center(entry["pos"], cell))
		node.add_child(spot)
		spots.append(spot)
		list.append(spot)
	index["hiding"][room_id] = spots


## data["door_id"]: la cerradura antigua apunta a su puerta ("door" = la de su sala, "door:<sala>");
## el torno, a su compuerta (mismo id que el interactivo).
static func _link_door(data: Dictionary, room_id: String, plan: Dictionary) -> void:
	var type: String = str(data.get("type", ""))
	if type == TURNSTILE_TYPE:
		data["door_id"] = str(data["id"])
		return
	if type != LOCK_TYPE:
		return
	var target: String = str(data.get("target", ""))
	var other: String = target.trim_prefix(FloorLayout.LOCK_TARGET_PREFIX) if target != FloorLayout.LOCK_TARGET_DOOR else ""
	for door: Dictionary in plan["doors"]:
		var touches: bool = door["a"] == room_id or door["b"] == room_id
		var matches: bool = other.is_empty() or FloorLayout.base_id(str(door["a"])) == other \
				or FloorLayout.base_id(str(door["b"])) == other
		if touches and matches and str(door["kind"]) == FloorLayout.DOOR_OLD_LOCK:
			data["door_id"] = str(door["id"])
			return


static func _cell_center(cell_v: Variant, cell: float) -> Vector2:
	return (Vector2(cell_v as Vector2i) + Vector2(0.5, 0.5)) * cell


static func _seats(room: RoomData, rect: Rect2i, cell: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat: Dictionary in FloorLayout.seats_of(room):
		out.append({
			"owner": seat["owner"], "type": seat["type"], "furniture_index": seat["index"],
			"cell": rect.position + (seat["cell"] as Vector2i),
			"pos": (Vector2(rect.position) + (seat["chair"] as Vector2)) * cell, "facing": seat["facing"],
		})
	return out


static func _add_cameras(plan: Dictionary, cell: float, index: Dictionary) -> void:
	for cam: Dictionary in plan["cameras"]:
		var room_node: Node2D = index["rooms"].get(cam["room_id"])
		if room_node == null:
			continue
		var camera: SecurityCamera = SecurityCamera.new()
		var local: Vector2 = (Vector2(cam["cell"]) + Vector2(0.5, 0.5)) * cell - room_node.position
		camera.setup(str(cam["id"]), str(cam["room_id"]), cell, local, float(cam["rotation"]))
		camera.set_wedge_colors(_band_record(plan))
		room_node.add_child(camera)
		(index["cameras"] as Array).append(camera)


static func _band_record(plan: Dictionary) -> Dictionary:
	return Database.get_art_band(str(plan.get("band", "")))


static func _add_exits(plan: Dictionary, cell: float, index: Dictionary) -> void:
	for t: Dictionary in plan["transit"]:
		if t["kind"] != FloorLayout.TRANSIT_EXIT:
			continue
		var room_node: Node2D = index["rooms"].get(t["room_id"])
		if room_node == null:
			continue
		var item: Interactable = Interactable.new()
		var local: Vector2 = (Vector2(t["cell"]) + Vector2(0.5, 0.5)) * cell - room_node.position
		var data: Dictionary = {"transit": t.duplicate(true), "targets": t["targets"], "target_room": t["target_room"]}
		item.setup(str(t["id"]), EXIT_TYPE, str(t["room_id"]), data, cell, local)
		room_node.add_child(item)
		(index["interactables"][t["room_id"]] as Array).append(item)


# ─── Puertas y tornos ─────────────────────────────────────────

## Un nodo Door por puerta con control de acceso, colgado de la sala a la que se entra (b).
static func _add_doors(plan: Dictionary, cell: float, index: Dictionary) -> void:
	for door: Dictionary in plan["doors"]:
		if not FloorLayout.is_controlled_door(door):
			continue
		var node: Node2D = index["rooms"].get(door["b"])
		if node == null:
			continue
		var d: Door = Door.new()
		d.setup(_door_data(plan, door, cell), Vector2(door["cell"] as Vector2i) * cell - node.position)
		node.add_child(d)
		(index["doors"] as Array).append(d)


static func _door_data(plan: Dictionary, door: Dictionary, cell: float) -> Dictionary:
	var pal: Dictionary = RoomPainter.palette_of(_band_record(plan))
	var b_rect: Rect2i = plan["rooms"][door["b"]]
	var line: int = (door["cell"] as Vector2i).x if door["vertical"] else (door["cell"] as Vector2i).y
	var b_room: RoomData = Database.get_room(str(door["b"]))
	var leaf: Color = {FloorLayout.DOOR_READER: pal["accent"], FloorLayout.DOOR_OLD_LOCK: (pal["furniture"] as Color).darkened(0.35),
			FloorLayout.DOOR_SERVICE: (pal["wall"] as Color).darkened(0.25)}.get(str(door["kind"]), pal["furniture"])
	return {
		"id": door["id"], "kind": door["kind"], "a": door["a"], "b": door["b"],
		"clearance": door["clearance"], "special_access": door["special_access"],
		"special_mode": str(b_room.extra.get("special_access_mode", "")) if b_room != null else "",
		"vertical": door["vertical"], "span": float(door["width"]) * cell,
		"thickness": Database.get_balance_float("mundo.grosor_muro") * cell,
		"into_positive": (b_rect.position.x if door["vertical"] else b_rect.position.y) >= line,
		"locked": FloorLayout.door_starts_locked(door), "cell": cell, "leaf": leaf, "outline": pal["outline"],
	}


## Compuertas de torno (Door "turnstile", capa 3) en cada celda con mueble "turnstile": cierran su
## calle; se abren con acreditación mundo.puertas.acreditacion_torno (fichaje) o para los NPC.
static func _add_turnstiles(plan: Dictionary, cell: float, index: Dictionary) -> void:
	for room_id: String in plan["order"]:
		var room: RoomData = Database.get_room(room_id)
		var node: Node2D = index["rooms"].get(room_id)
		if room == null or node == null:
			continue
		for entry: Dictionary in room.furniture:
			if str(entry["type"]) != TURNSTILE_TYPE:
				continue
			var pos: Vector2i = entry["pos"]
			var gate: Door = Door.new()
			gate.setup(_gate_data(plan, room, room_id, pos, cell), Vector2(pos.x, pos.y + 0.5) * cell)
			node.add_child(gate)
			(index["doors"] as Array).append(gate)


static func _gate_data(plan: Dictionary, room: RoomData, room_id: String, pos: Vector2i, cell: float) -> Dictionary:
	var id: String = TURNSTILE_ID_FORMAT % [room_id, pos.x, pos.y]
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) == TURNSTILE_TYPE and entry["pos"] == pos:
			id = str(entry["id"])
	var pal: Dictionary = RoomPainter.palette_of(_band_record(plan))
	return {
		"id": id, "kind": Door.KIND_TURNSTILE, "a": room_id, "b": room_id,
		"clearance": Database.get_balance_int("mundo.puertas.acreditacion_torno"), "special_access": [],
		"vertical": false, "span": cell, "thickness": cell * GATE_THICKNESS, "into_positive": true,
		"locked": true, "cell": cell, "leaf": pal["accent"], "outline": pal["outline"],
	}
