# room_builder.gd — Construye por código el árbol de nodos de cada sala y de la planta completa.
# PROPIETARIO DE: nada (fábrica de nodos: suelo, muros, muebles, colisiones, interactivos, cámaras, luz).
# ESCUCHA: nada.
class_name RoomBuilder
extends RefCounted

## PASO 7 + BUILD_NOTES §14. Capas físicas: 1 muros, 2 muebles altos (bloquean paso y visión),
## 3 muebles bajos (bloquean paso, obstrucción parcial), 6 interactivos. Capas de dibujo (z absoluto):
## fondo -40 · suelo -30 · muros -10 · muebles y actores 0 (ordenados en Y bajo props_root) ·
## realce de interactivos 20 · cámaras 30 · luz aditiva 40.
## build_floor() devuelve un índice: {rooms: {id: Node2D}, interactables: {id: [Interactable]},
## hiding: {id: [HidingSpot]}, cameras: [SecurityCamera], seats: {id: [{owner, pos, facing, type}]}}.

const LAYER_WALLS := 1
const LAYER_TALL := 2
const LAYER_LOW := 3
const Z_BACKDROP := -40
const Z_FLOOR := -30
const Z_WALLS := -10
const Z_LIGHT := 40
const SEAT_TYPES: Array[String] = ["cubicle", "desk", "executive_desk", "counter", "reception_desk", "workbench"]
const COLLISION_INSET := 3.0
const PARTITION_RATIO := 0.125
const EXIT_TYPE := "exit"
## Muebles con animación ambiental (§14.7): la línea de ensamblaje avanza.
const ANIMATED_TYPES: Array[String] = ["conveyor"]
const SPARK_COLOR := Color(1.0, 0.72, 0.25)
const SPARK_AMOUNT := 14
const SPARK_LIFETIME := 1.8
const LIGHT_TEXTURE_SIZE := 256
## Ambiente (CanvasModulate) por tipo de iluminación de art_bands.json.
const AMBIENT: Dictionary = {
	"fluorescent": Color(0.95, 0.99, 0.91), "uniform": Color(1.0, 1.0, 1.0),
	"indirect": Color(0.94, 0.87, 0.77), "natural": Color(1.0, 1.0, 0.98),
	"isolated_spots": Color(0.34, 0.35, 0.37), "industrial": Color(0.8, 0.76, 0.7),
	"streetlight": Color(0.36, 0.4, 0.56),
}
## Luces puntuales: [radio en celdas, energía, cada cuántas luminarias una luz].
const POINT_LIGHTS: Dictionary = {
	"isolated_spots": [3.4, 0.95, 2], "industrial": [4.5, 0.5, 1], "streetlight": [4.2, 1.15, 1],
}

static var _light_texture: GradientTexture2D = null
static var _additive: CanvasItemMaterial = null


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


class FlickerLight extends Node2D:
	var radius: float = 96.0
	var color: Color = Color.WHITE
	var alpha: float = 0.1
	var phase: float = 0.0
	var period: float = 5.0
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		var f: float = fmod(_time + phase, period)
		var target: float = 1.0
		if f < 0.45:
			target = 0.25 if sin(f * 55.0) > 0.0 else 0.9
		if not is_equal_approx(target, modulate.a):
			modulate.a = target

	func _draw() -> void:
		RoomPainter.draw_light_pool(self, Vector2.ZERO, radius, color, alpha)


static func cell_px() -> float:
	return float(Database.get_balance_int("mundo.px_por_unidad"))


# ─── Planta ───────────────────────────────────────────────────

## Construye la planta de `plan` bajo floor_root; los muebles altos van a props_root (orden en Y).
static func build_floor(plan: Dictionary, floor_root: Node2D, props_root: Node2D) -> Dictionary:
	var cell: float = cell_px()
	var index: Dictionary = {"rooms": {}, "interactables": {}, "hiding": {}, "cameras": [], "seats": {}}
	var backdrop: RoomPainter.Backdrop = RoomPainter.Backdrop.new()
	backdrop.setup(plan, cell)
	floor_root.add_child(backdrop)
	for room_id: String in plan["order"]:
		var room: RoomData = Database.get_room(room_id)
		if room != null:
			floor_root.add_child(build_room(room, room_id, plan, props_root, index))
	_add_cameras(plan, cell, index)
	_add_exits(plan, cell, index)
	_add_lighting(plan, floor_root, cell, index)
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
	_add_flicker(walls, style, node)
	index["seats"][room_id] = _seats(room, rect, cell)
	return node


static func _make_painter(room: RoomData, room_id: String, plan: Dictionary, style: Dictionary,
		layer: int) -> RoomPainter:
	var painter: RoomPainter = RoomPainter.new()
	painter.setup(room, room_id, plan, style, layer)
	painter.z_as_relative = false
	painter.z_index = [Z_FLOOR, Z_WALLS, Z_LIGHT][layer]
	if layer == RoomPainter.LAYER_LIGHT:
		painter.material = additive_material()
	return painter


static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


# ─── Muebles ──────────────────────────────────────────────────

static func _add_props(furniture: Array[Dictionary], style: Dictionary, cell: float, origin: Vector2,
		props_root: Node2D) -> void:
	var painter: FurniturePainter = FurniturePainter.new(style)
	for entry: Dictionary in furniture:
		var type: String = str(entry["type"])
		if not FurniturePainter.is_prop(type) or RoomPainter.WALL_MOUNTED.has(type):
			continue
		var fp: Rect2i = FurniturePainter.footprint(entry)
		var prop: Prop = Prop.new()
		prop.painter = painter
		prop.entry = entry
		prop.footprint = Rect2(0, -fp.size.y * cell, fp.size.x * cell, fp.size.y * cell)
		prop.position = origin + Vector2(fp.position.x, fp.end.y) * cell
		prop.name = "%s_%d_%d" % [type, fp.position.x, fp.position.y]
		prop.animated = ANIMATED_TYPES.has(type)
		if type == "industrial_machine" and str(style.get("band", "")) == "factory":
			prop.add_child(_sparks(prop.footprint, painter.height_of(type)))
		props_root.add_child(prop)


## Chispas de la maquinaria de la nave (excepción de contraste §14.3): ráfagas cortas y aditivas.
static func _sparks(footprint: Rect2, height: float) -> CPUParticles2D:
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.name = "Sparks"
	sparks.position = Vector2(footprint.get_center().x, footprint.position.y - height * 0.5)
	sparks.amount = SPARK_AMOUNT
	sparks.lifetime = SPARK_LIFETIME
	sparks.explosiveness = 0.85
	sparks.randomness = 0.6
	sparks.direction = Vector2.UP
	sparks.spread = 70.0
	sparks.gravity = Vector2(0, 260)
	sparks.initial_velocity_min = 50.0
	sparks.initial_velocity_max = 120.0
	sparks.scale_amount_min = 1.5
	sparks.scale_amount_max = 3.0
	sparks.color = SPARK_COLOR
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = fade
	sparks.material = additive_material()
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


static func _add_wall_collisions(walls: RoomPainter, node: Node2D) -> void:
	var body: StaticBody2D = _body(LAYER_WALLS, "Walls")
	for pair: Array in walls.wall_segments():
		_add_shape(body, walls.segment_rect(int(pair[0]), pair[1]))
	node.add_child(body)


static func _add_furniture_collisions(furniture: Array[Dictionary], cell: float, node: Node2D) -> void:
	var tall: StaticBody2D = _body(LAYER_TALL, "TallFurniture")
	var low: StaticBody2D = _body(LAYER_LOW, "LowFurniture")
	for entry: Dictionary in furniture:
		var type: String = str(entry["type"])
		var blocking: int = FurniturePainter.blocking_of(type)
		if blocking == FurniturePainter.BLOCK_NONE:
			continue
		var target: StaticBody2D = tall if blocking == FurniturePainter.BLOCK_TALL else low
		for r: Rect2 in _collision_rects(entry, cell):
			_add_shape(target, r)
	node.add_child(tall)
	node.add_child(low)


## Rectángulos de colisión en px locales de sala; el cubículo: mesa + tres mamparas.
static func _collision_rects(entry: Dictionary, cell: float) -> Array[Rect2]:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	var r: Rect2 = Rect2(Vector2(fp.position) * cell, Vector2(fp.size) * cell)
	if str(entry["type"]) != "cubicle":
		return [r.grow(-COLLISION_INSET)]
	var t: float = cell * PARTITION_RATIO
	var desk_row: int = FurniturePainter.blocked_cells(entry)[0].y
	var desk: Rect2 = Rect2(r.position.x, desk_row * cell, r.size.x, cell)
	var back_y: float = r.position.y if desk_row == fp.position.y else r.end.y - t
	return [desk.grow(-COLLISION_INSET), Rect2(r.position.x, back_y, r.size.x, t),
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


static func _cell_center(cell_v: Variant, cell: float) -> Vector2:
	return (Vector2(cell_v as Vector2i) + Vector2(0.5, 0.5)) * cell


static func _seats(room: RoomData, rect: Rect2i, cell: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in room.furniture.size():
		var entry: Dictionary = room.furniture[i]
		if not SEAT_TYPES.has(str(entry["type"])) or not entry.has("owner"):
			continue
		var seat: Vector2i = FurniturePainter.seat_cell(entry)
		var facing: Vector2 = FurniturePainter.facing_of(float(entry.get("rotation", 0.0)))
		if str(entry["type"]) == "cubicle":
			facing = Vector2.UP if FurniturePainter.blocked_cells(entry)[0].y < seat.y else Vector2.DOWN
		out.append({
			"owner": str(entry["owner"]), "type": str(entry["type"]), "furniture_index": i,
			"cell": rect.position + seat, "pos": (Vector2(rect.position + seat) + Vector2(0.5, 0.5)) * cell,
			"facing": facing,
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
		room_node.add_child(camera)
		(index["cameras"] as Array).append(camera)


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


# ─── Luz ──────────────────────────────────────────────────────

static func _add_flicker(walls: RoomPainter, style: Dictionary, node: Node2D) -> void:
	var lighting: Dictionary = style.get("lighting", {})
	if not bool(lighting.get("flicker", false)):
		return
	for pos: Vector2 in walls.light_points():
		var i: int = int(pos.x * 3.0 + pos.y * 7.0)
		if i % RoomPainter.FLICKER_EVERY != 0:
			continue
		var light: FlickerLight = FlickerLight.new()
		light.position = pos
		light.radius = walls.cell * 2.1
		light.color = RoomPainter.C_LIGHT_COOL
		light.alpha = 0.11
		light.phase = float(absi(hash(pos)) % 997) / 100.0
		light.period = 3.5 + float(absi(hash(pos) >> 3) % 50) / 10.0
		light.z_as_relative = false
		light.z_index = Z_LIGHT
		light.material = additive_material()
		node.add_child(light)


static func _add_lighting(plan: Dictionary, floor_root: Node2D, cell: float, index: Dictionary) -> void:
	var record: Dictionary = Database.get_art_band(str(plan.get("band", "")))
	var lighting: Dictionary = record.get("lighting", {})
	var type: String = str(lighting.get("type", ""))
	var modulate: CanvasModulate = CanvasModulate.new()
	modulate.name = "Ambient"
	modulate.color = AMBIENT.get(type, Color.WHITE)
	floor_root.add_child(modulate)
	if not POINT_LIGHTS.has(type):
		return
	var pal: Dictionary = RoomPainter.palette_of(record)
	for spot: Vector3 in _point_lights(plan, type, cell, index):
		var light: PointLight2D = PointLight2D.new()
		light.texture = light_texture()
		light.texture_scale = spot.z * cell / (LIGHT_TEXTURE_SIZE * 0.5)
		light.energy = float(POINT_LIGHTS[type][1])
		light.color = pal["light"]
		light.position = Vector2(spot.x, spot.y)
		floor_root.add_child(light)


## Luces puntuales (x, y en px; z = radio en celdas): farolas, luminarias en rejilla y, en el
## exterior, una luz interior por sala que cubre su tamaño.
static func _point_lights(plan: Dictionary, type: String, cell: float, index: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var every: int = int(POINT_LIGHTS[type][2])
	var radius: float = float(POINT_LIGHTS[type][0])
	for room_id: String in plan["order"]:
		var node: Node2D = index["rooms"][room_id]
		var lamps: int = 0
		for entry: Dictionary in FloorLayout.furniture_of(plan, Database.get_room(room_id)):
			if str(entry["type"]) == "street_lamp":
				var p: Vector2 = node.position + _cell_center(entry["pos"], cell) + Vector2(cell * 0.2, -cell * 0.4)
				out.append(Vector3(p.x, p.y, radius))
				lamps += 1
		var size: Vector2i = plan["rooms"][room_id].size
		if lamps > 0 or type == "streetlight":
			if lamps == 0:
				var c: Vector2 = node.position + Vector2(size) * cell * 0.5
				out.append(Vector3(c.x, c.y, maxf(size.x, size.y) * 0.62))
			continue
		var points: Array[Vector2] = (node.get_child(RoomPainter.LAYER_WALLS) as RoomPainter).light_points()
		for i: int in points.size():
			if i % every == 0:
				out.append(Vector3(node.position.x + points[i].x, node.position.y + points[i].y, radius))
	return out


static func light_texture() -> GradientTexture2D:
	if _light_texture != null:
		return _light_texture
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	_light_texture = GradientTexture2D.new()
	_light_texture.gradient = gradient
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(1.0, 0.5)
	_light_texture.width = LIGHT_TEXTURE_SIZE
	_light_texture.height = LIGHT_TEXTURE_SIZE
	return _light_texture
