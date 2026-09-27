# room_painter.gd — Dibuja por código suelo, muros, puertas, ventanas y luz de una sala según su banda.
# PROPIETARIO DE: nada (presentación; lee paletas de art_bands.json vía Database).
# ESCUCHA: nada.
class_name RoomPainter
extends Node2D

## Tres capas por sala (BUILD_NOTES §8, manual §14.2-§14.3, §14.8):
##   LAYER_FLOOR  suelo con textura por material + mobiliario plano (alfombras, sillas, sofás…)
##   LAYER_WALLS  cara norte en 3/4, coronación de muros, puertas (lector, candado, servicio),
##                ventanas en muros exteriores y elementos colgados (carteles, espejos)
##   LAYER_LIGHT  luz aditiva por banda (tubos fluorescentes, luz cálida indirecta, haces de sol…)
## Quien lo crea lo coloca en la esquina superior izquierda de la sala (px); dibuja en local.

const LAYER_FLOOR := 0
const LAYER_WALLS := 1
const LAYER_LIGHT := 2
const WALL_MOUNTED: Array[String] = ["motivational_poster", "mirror"]
const FLAT_FIRST: Array[String] = ["rug", "runway", "helipad", "window_wall"]
const FACE_RATIO := 0.55
const LIGHT_ALPHA := 0.13
const AO_DEPTH := 0.45
const AO_ALPHA := 0.22
const LIGHT_RADIUS_CELLS := 2.6
const OUTLINE_W := 2.0
const TRANSPARENT := Color(0, 0, 0, 0)
const SHADE_STEP := 0.035
const STAIN := Color(0.18, 0.16, 0.08, 0.13)
const GROUT := Color(0, 0, 0, 0.09)
const HATCH := Color(1, 1, 1, 0.05)
const C_READER := Color("#26292e")
const C_LED_LOCKED := Color("#ff5a4a")
const C_LED_SERVICE := Color("#ffb347")
const C_BRASS := Color("#c9a24a")
const C_STEEL := Color("#aeb6bb")
const C_HAZARD := Color("#f2c230")
const C_EXIT_GREEN := Color("#39d97a")
const C_EXTINGUISHER := Color("#d33a2c")
const C_ROAD_LINE := Color("#e8d27a")
const C_KERB := Color("#8c8f96")
const C_MARBLE_VEIN := Color(0.5, 0.48, 0.44, 0.22)
const C_MARBLE_GOLD := Color(0.78, 0.64, 0.33, 0.35)
const C_LIGHT_WARM := Color(1.0, 0.86, 0.6)
const C_LIGHT_COOL := Color(0.9, 1.0, 0.92)
const LIGHT_GRID_CELLS := 4
const FLICKER_EVERY := 5
const POSTER_SPACING := {"high": 6, "medium": 10, "low": 16, "none": 0}
const MATERIAL_BY_KEYWORD: Dictionary = {
	"toilets": "tile", "pantry": "tile", "kitchen": "tile", "infirmary": "tile", "spa": "tile",
	"cafeteria": "tile", "break_room": "tile", "garage": "concrete", "warehouse": "concrete",
	"dock": "concrete", "workshop": "concrete", "store": "concrete", "gym": "rubber",
	"terrace": "deck", "machine_room": "concrete", "server": "raised", "backup": "raised",
}

var layer: int = LAYER_FLOOR
var room: RoomData = null
var room_id: String = ""
var rect: Rect2i = Rect2i()
var style: Dictionary = {}
var doors: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var neighbours: Array[Rect2i] = []
var _rooms_by_id: Dictionary = {}
var _furniture: Array[Dictionary] = []
var is_spine: bool = false
var cell: float = 48.0
var _painter: FurniturePainter = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Configura la capa; `plan` es el FloorPlan de FloorLayout.
func setup(p_room: RoomData, p_room_id: String, plan: Dictionary, p_style: Dictionary, p_layer: int) -> void:
	room = p_room
	room_id = p_room_id
	rect = plan["rooms"][p_room_id]
	style = p_style
	layer = p_layer
	cell = float(style["cell"])
	is_spine = p_room_id == str(plan["corridor_id"])
	_painter = FurniturePainter.new(style)
	_furniture = FloorLayout.furniture_of(plan, p_room)
	_collect_geometry(plan)
	name = "%s_%s" % [["Floor", "Walls", "Light"][layer], p_room_id.validate_node_name()]
	if layer != LAYER_WALLS:
		_clip_to_room()


## Suelo y luz no deben salirse de la sala (manchas, vetas y charcos de luz se recortan).
func _clip_to_room() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, Vector2(rect.size) * cell)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, r)
	RenderingServer.canvas_item_set_clip(get_canvas_item(), true)


func _collect_geometry(plan: Dictionary) -> void:
	for door: Dictionary in plan["doors"]:
		if door["walkable"] and (door["a"] == room_id or door["b"] == room_id):
			doors.append(door)
	for t: Dictionary in plan["transit"]:
		if t["room_id"] == room_id and t["kind"] == FloorLayout.TRANSIT_EXIT and t["door_cell"] != Vector2i(-1, -1):
			exits.append(t)
	_rooms_by_id = plan["rooms"]
	for other_id: String in plan["rooms"]:
		if other_id != room_id:
			neighbours.append(plan["rooms"][other_id])


# ─── Estilo por banda ─────────────────────────────────────────

## Estilo visual de una sala en una planta: paleta (Color), banda, material, kit, celda.
static func style_for(p_room: RoomData, room_id: String, plan: Dictionary, cell_px: float) -> Dictionary:
	var band_id: String = str(plan.get("band", ""))
	if not p_room.extra.has(FloorLayout.KEY_BASE_ID) and not p_room.art_band.is_empty():
		band_id = p_room.art_band
	var record: Dictionary = Database.get_art_band(band_id)
	var spine: bool = room_id == str(plan.get("corridor_id", ""))
	return {
		"band": band_id, "pal": palette_of(record), "cell": cell_px, "room_id": room_id,
		"kit": p_room.kit, "plastic": bool(record.get("plants_are_plastic", true)),
		"posters": str(record.get("motivational_poster_density", "none")),
		"lighting": record.get("lighting", {}), "spine": spine,
		"material": material_for(p_room, band_id, spine),
		"transit": FloorLayout.transit_kind_of(p_room), "floor": int(plan.get("floor", 0)),
	}


static func palette_of(record: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = record.get("palette", {})
	for key: String in raw:
		out[key] = Color(str(raw[key]))
	for key: String in ["floor", "wall", "accent", "light", "shadow", "carpet", "furniture", "outline", "window"]:
		if not out.has(key):
			out[key] = Color.GRAY
	return out


static func material_for(p_room: RoomData, band_id: String, spine: bool) -> String:
	var id: String = FloorLayout.base_id(p_room.id)
	if band_id == "exterior":
		return _exterior_material(id)
	if band_id == "factory":
		return "tile" if id.contains("break") else "factory"
	if spine and bool(p_room.extra.get(FloorLayout.KEY_FULL_WIDTH, false)):
		return str({"the_pit": "linoleum", "the_specialists": "linoleum", "the_power": "wood",
				"the_throne": "marble", "the_guts": "concrete"}.get(band_id, "linoleum"))
	var kind: String = FloorLayout.transit_kind_of(p_room)
	if kind == FloorLayout.TRANSIT_SERVICE_STAIRS or kind == FloorLayout.TRANSIT_FREIGHT:
		return "concrete"
	for keyword: String in MATERIAL_BY_KEYWORD:
		if id.contains(keyword):
			return str(MATERIAL_BY_KEYWORD[keyword])
	if band_id == "the_guts":
		return "concrete"
	if band_id == "the_throne":
		return "marble"
	if p_room.kit == "lobby" or kind != "":
		return "stone"
	return "carpet"


static func _exterior_material(id: String) -> String:
	if id == "street" or id == "alleys":
		return "asphalt"
	if id == "transport_stop":
		return "pavement"
	if id.begins_with("npc_house") or id == "player_flat":
		return "wood"
	return "shop_tile"


# ─── Dibujo ───────────────────────────────────────────────────

func _draw() -> void:
	_rng.seed = hash(room_id)
	match layer:
		LAYER_FLOOR:
			_draw_floor_layer()
		LAYER_WALLS:
			_draw_walls_layer()
		LAYER_LIGHT:
			_draw_light_layer()


func _size_px() -> Vector2:
	return Vector2(rect.size) * cell


func _c(key: String) -> Color:
	return (style["pal"] as Dictionary).get(key, Color.MAGENTA)


func _t() -> float:
	return Database.get_balance_float("mundo.grosor_muro") * cell


# ─── Suelo ────────────────────────────────────────────────────

func _draw_floor_layer() -> void:
	var size: Vector2 = _size_px()
	var material: String = str(style["material"])
	var method: String = "_floor_" + material
	if has_method(method):
		call(method, size)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), _c("floor"))
	_draw_transit_floor(size)
	_draw_fixtures()
	_draw_wall_occlusion(size)
	_draw_flat_furniture()


## Oclusión ambiental: degradado oscuro al pie de los muros (las salas se leen cerradas).
func _draw_wall_occlusion(size: Vector2) -> void:
	var depth: float = cell * AO_DEPTH
	var dark: Color = Color(0, 0, 0, AO_ALPHA)
	var none: Color = Color(0, 0, 0, 0)
	var top: float = cell * FACE_RATIO
	var edges: Array = [[Vector2(0, top), Vector2(size.x, top), Vector2(0, 1)],
			[Vector2(0, size.y), Vector2(size.x, size.y), Vector2(0, -1)],
			[Vector2.ZERO, Vector2(0, size.y), Vector2(1, 0)], [Vector2(size.x, 0), size, Vector2(-1, 0)]]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n: Vector2 = e[2]
		draw_polygon(PackedVector2Array([a, b, b + n * depth, a + n * depth]), PackedColorArray([dark, dark, none, none]))


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * cell, Vector2(cell, cell))


func _floor_carpet(size: Vector2) -> void:
	var base: Color = _c("carpet")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			if (x + y) % 2 == 0:
				draw_rect(_cell_rect(Vector2i(x, y)), base.darkened(SHADE_STEP))
	for x: int in range(0, rect.size.x + 1, 2):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), GROUT, 1.0)
	for y: int in range(0, rect.size.y + 1, 2):
		draw_line(Vector2(0, y * cell), Vector2(size.x, y * cell), GROUT, 1.0)
	if str(style["band"]) == "the_pit":
		_stains(size, maxi(2, rect.size.x * rect.size.y / 24))
	elif str(style["band"]) == "the_power":
		draw_rect(Rect2(Vector2.ZERO, size), _c("floor"), false, cell * 0.35)
		draw_rect(Rect2(Vector2.ONE * cell * 0.18, size - Vector2.ONE * cell * 0.36), C_BRASS.darkened(0.2), false, 1.5)


func _stains(size: Vector2, count: int) -> void:
	for i: int in count:
		var c: Vector2 = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		var r: float = _rng.randf_range(0.12, 0.38) * cell
		draw_set_transform(c, _rng.randf() * PI, Vector2(1.0, _rng.randf_range(0.5, 0.9)))
		draw_circle(Vector2.ZERO, r, STAIN)
		draw_circle(Vector2(r * 0.4, 0), r * 0.5, STAIN)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _floor_linoleum(size: Vector2) -> void:
	var base: Color = _c("floor")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			if (x + y) % 2 == 1:
				draw_rect(_cell_rect(Vector2i(x, y)), base.lightened(SHADE_STEP))
	for i: int in rect.size.x * rect.size.y / 3:
		draw_circle(Vector2(_rng.randf() * size.x, _rng.randf() * size.y), 1.2, base.darkened(0.12))
	for x: int in range(0, rect.size.x + 1):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), GROUT, 1.0)
	for y: int in range(0, rect.size.y + 1):
		draw_line(Vector2(0, y * cell), Vector2(size.x, y * cell), GROUT, 1.0)
	if is_spine and rect.size.y >= 3:
		var runner: Rect2 = Rect2(0, size.y * 0.3, size.x, size.y * 0.4)
		draw_rect(runner, _c("carpet").darkened(0.05))
		draw_line(runner.position, Vector2(runner.end.x, runner.position.y), _c("accent"), 2.0)
		draw_line(Vector2(0, runner.end.y), runner.end, _c("accent"), 2.0)
		if str(style["band"]) == "the_pit":
			_stains(size, rect.size.x / 6)


func _floor_tile(size: Vector2) -> void:
	var base: Color = _c("floor").lerp(Color("#e9ece8"), 0.55)
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var step: float = cell * 0.5
	for y: int in int(size.y / step):
		for x: int in int(size.x / step):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(x * step, y * step, step, step), base.darkened(0.05))
	for x: int in int(size.x / step) + 1:
		draw_line(Vector2(x * step, 0), Vector2(x * step, size.y), GROUT, 1.0)
	for y: int in int(size.y / step) + 1:
		draw_line(Vector2(0, y * step), Vector2(size.x, y * step), GROUT, 1.0)


func _floor_shop_tile(size: Vector2) -> void:
	_floor_tile(size)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.95, 0.8, 0.12))


func _floor_concrete(size: Vector2) -> void:
	var base: Color = _c("floor")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for i: int in maxi(3, rect.size.x * rect.size.y / 10):
		var c: Vector2 = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		draw_set_transform(c, _rng.randf() * PI, Vector2(1.0, _rng.randf_range(0.4, 1.0)))
		draw_circle(Vector2.ZERO, _rng.randf_range(0.3, 1.1) * cell, base.darkened(_rng.randf_range(0.03, 0.09)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for x: int in range(0, rect.size.x + 1, 4):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), base.darkened(0.18), 1.5)
	for y: int in range(0, rect.size.y + 1, 4):
		draw_line(Vector2(0, y * cell), Vector2(size.x, y * cell), base.darkened(0.18), 1.5)
	for i: int in maxi(1, rect.size.x / 8):
		var p: Vector2 = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		var crack: PackedVector2Array = [p]
		for k: int in 4:
			p += Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * cell
			crack.append(p)
		draw_polyline(crack, base.darkened(0.3), 1.2)


func _floor_factory(size: Vector2) -> void:
	_floor_concrete(size)
	var lane: float = cell * 0.18
	var inset: float = cell * 1.0
	var r: Rect2 = Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	if r.size.x > cell * 2.0 and r.size.y > cell * 2.0:
		draw_rect(r, C_HAZARD.darkened(0.1), false, lane)
	var stripe: float = cell * 0.5
	for i: int in int(size.x / stripe):
		if i % 2 == 0:
			draw_colored_polygon(PackedVector2Array([Vector2(i * stripe, size.y - lane * 2.0),
					Vector2(i * stripe + stripe, size.y - lane * 2.0), Vector2(i * stripe + stripe * 0.5, size.y),
					Vector2(i * stripe - stripe * 0.5, size.y)]), C_HAZARD.darkened(0.15))


func _floor_wood(size: Vector2) -> void:
	var base: Color = _c("floor") if str(style["band"]) != "exterior" else Color("#6a5040")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var plank_h: float = cell * 0.25
	var rows: int = int(size.y / plank_h) + 1
	for row: int in rows:
		var y: float = row * plank_h
		draw_line(Vector2(0, y), Vector2(size.x, y), base.darkened(0.22), 1.0)
		var x: float = -_rng.randf() * cell * 2.0
		while x < size.x:
			var length: float = _rng.randf_range(1.2, 2.6) * cell
			draw_rect(Rect2(maxf(x, 0.0), y, minf(length, size.x - maxf(x, 0.0)), plank_h),
					base.lightened(_rng.randf_range(-0.05, 0.07)))
			draw_line(Vector2(x + length, y), Vector2(x + length, y + plank_h), base.darkened(0.25), 1.0)
			x += length
	if is_spine:
		var runner: Rect2 = Rect2(0, size.y * 0.22, size.x, size.y * 0.56)
		draw_rect(runner, _c("carpet"))
		draw_rect(Rect2(runner.position + Vector2(0, 4), Vector2(runner.size.x, runner.size.y - 8)), C_BRASS, false, 1.5)


func _floor_marble(size: Vector2) -> void:
	var base: Color = _c("floor")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var slab: int = 2
	for y: int in range(0, rect.size.y, slab):
		for x: int in range(0, rect.size.x, slab):
			var tone: float = _rng.randf_range(-0.03, 0.04)
			draw_rect(Rect2(x * cell, y * cell, slab * cell, slab * cell), base.lightened(tone))
	for i: int in maxi(1, rect.size.x * rect.size.y / 30):
		var p: Vector2 = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		var vein: PackedVector2Array = [p]
		var dir: Vector2 = Vector2.RIGHT.rotated(_rng.randf_range(-0.5, 0.5) + (PI * 0.25 if i % 2 == 0 else -PI * 0.2))
		for k: int in 10:
			dir = dir.rotated(_rng.randf_range(-0.18, 0.18))
			p += dir * cell * 0.4
			vein.append(p)
		draw_polyline(vein, C_MARBLE_GOLD if i % 4 == 0 else C_MARBLE_VEIN, 1.0 + float(i % 2))
	for x: int in range(0, rect.size.x + 1, slab):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), GROUT, 1.0)
	for y: int in range(0, rect.size.y + 1, slab):
		draw_line(Vector2(0, y * cell), Vector2(size.x, y * cell), GROUT, 1.0)
	if is_spine:
		draw_rect(Rect2(0, size.y * 0.3, size.x, size.y * 0.4), Color(0.72, 0.6, 0.37, 0.18))
		draw_line(Vector2(0, size.y * 0.3), Vector2(size.x, size.y * 0.3), _c("accent"), 2.0)
		draw_line(Vector2(0, size.y * 0.7), Vector2(size.x, size.y * 0.7), _c("accent"), 2.0)


func _floor_stone(size: Vector2) -> void:
	var base: Color = _c("floor").lerp(Color("#cfcabf"), 0.5)
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			draw_rect(_cell_rect(Vector2i(x, y)), base.lightened(_rng.randf_range(-0.04, 0.04)))
	for x: int in range(0, rect.size.x + 1):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), GROUT, 1.0)
	for y: int in range(0, rect.size.y + 1):
		draw_line(Vector2(0, y * cell), Vector2(size.x, y * cell), GROUT, 1.0)


func _floor_raised(size: Vector2) -> void:
	var base: Color = Color("#8f989f").lerp(_c("floor"), 0.45)
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			var r: Rect2 = _cell_rect(Vector2i(x, y)).grow(-1.5)
			draw_rect(r, base.lightened(0.04))
			if (x * 7 + y * 3) % 5 == 0:
				for k: int in 3:
					draw_line(r.position + Vector2(6, 8 + k * 8), r.position + Vector2(r.size.x - 6, 8 + k * 8),
							base.darkened(0.25), 1.5)


func _floor_rubber(size: Vector2) -> void:
	var base: Color = Color("#2f3136")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for i: int in rect.size.x * rect.size.y:
		draw_circle(Vector2(_rng.randf() * size.x, _rng.randf() * size.y), 1.0, Color(0.6, 0.6, 0.65, 0.25))
	for x: int in range(0, rect.size.x + 1):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, size.y), Color(0, 0, 0, 0.3), 1.0)


func _floor_deck(size: Vector2) -> void:
	var base: Color = Color("#a8825a")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var plank: float = cell * 0.33
	for i: int in int(size.x / plank) + 1:
		draw_line(Vector2(i * plank, 0), Vector2(i * plank, size.y), base.darkened(0.25), 1.0)
		if i % 2 == 0:
			draw_rect(Rect2(i * plank, 0, plank, size.y), base.lightened(0.04))


func _floor_asphalt(size: Vector2) -> void:
	var base: Color = _c("floor")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for i: int in rect.size.x * rect.size.y / 2:
		draw_circle(Vector2(_rng.randf() * size.x, _rng.randf() * size.y), 1.3, base.lightened(0.08))
	if not is_spine:
		return
	var walk: float = cell * 1.6
	for y: float in [0.0, size.y - walk]:
		draw_rect(Rect2(0, y, size.x, walk), C_KERB.darkened(0.35))
		for x: int in range(0, rect.size.x + 1):
			draw_line(Vector2(x * cell, y), Vector2(x * cell, y + walk), Color(0, 0, 0, 0.2), 1.0)
	draw_line(Vector2(0, walk), Vector2(size.x, walk), C_KERB, 3.0)
	draw_line(Vector2(0, size.y - walk), Vector2(size.x, size.y - walk), C_KERB, 3.0)
	var dash: float = cell * 1.2
	for i: int in int(size.x / (dash * 2.0)) + 1:
		draw_line(Vector2(i * dash * 2.0, size.y * 0.5), Vector2(i * dash * 2.0 + dash, size.y * 0.5), C_ROAD_LINE, 3.0)


func _floor_pavement(size: Vector2) -> void:
	var base: Color = C_KERB.darkened(0.3)
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y: int in range(0, rect.size.y * 2 + 1):
		draw_line(Vector2(0, y * cell * 0.5), Vector2(size.x, y * cell * 0.5), Color(0, 0, 0, 0.18), 1.0)
	for x: int in range(0, rect.size.x * 2 + 1):
		draw_line(Vector2(x * cell * 0.5, 0), Vector2(x * cell * 0.5, size.y), Color(0, 0, 0, 0.18), 1.0)


## Escaleras y ascensores: tramo con peldaños o puertas de cabina.
func _draw_transit_floor(size: Vector2) -> void:
	var kind: String = str(style["transit"])
	if kind == FloorLayout.TRANSIT_STAIRS or kind == FloorLayout.TRANSIT_SERVICE_STAIRS:
		var head: Vector2 = Vector2(FloorLayout.spine_head(room), rect.size.y) * cell if is_spine else size
		_draw_stairs(head, kind == FloorLayout.TRANSIT_SERVICE_STAIRS)


func _draw_stairs(size: Vector2, service: bool) -> void:
	var flight: Rect2 = Rect2(cell * 0.5, cell * 0.6, size.x - cell, size.y - cell * 2.0)
	var col: Color = Color("#9a9c98") if service else _c("floor").lerp(Color("#d8d3c8"), 0.5)
	draw_rect(Rect2(flight.position + Vector2(3, 4), flight.size), Color(0, 0, 0, 0.25))
	var half: float = flight.size.x * 0.5
	for side: int in 2:
		var lane: Rect2 = Rect2(flight.position.x + side * half, flight.position.y, half - 2.0, flight.size.y)
		draw_rect(lane, col)
		var treads: int = int(lane.size.y / (cell * 0.28))
		for i: int in treads + 1:
			var y: float = lane.position.y + i * lane.size.y / maxf(1.0, treads)
			draw_line(Vector2(lane.position.x, y), Vector2(lane.end.x, y), col.darkened(0.3 - 0.2 * i / maxf(1.0, treads)), 2.0)
		draw_rect(lane, _c("outline"), false, OUTLINE_W)
	draw_line(Vector2(flight.get_center().x, flight.position.y), Vector2(flight.get_center().x, flight.end.y),
			C_HAZARD if service else C_BRASS, 3.0)
	var arrow_c: Vector2 = Vector2(flight.position.x + half * 0.5, flight.get_center().y)
	draw_colored_polygon(PackedVector2Array([arrow_c + Vector2(0, -cell * 0.35), arrow_c + Vector2(cell * 0.22, 0),
			arrow_c + Vector2(-cell * 0.22, 0)]), Color(1, 1, 1, 0.55))


## Elementos de interactivos sin mueble propio (rejillas de conducto, trampillas, cajas de suelo).
func _draw_fixtures() -> void:
	for entry: Dictionary in room.interactables:
		var r: Rect2 = _cell_rect(entry["pos"]).grow(-cell * 0.2)
		match str(entry["type"]):
			"vent_hatch":
				draw_rect(r, Color("#7d858a"))
				for k: int in 4:
					var y: float = r.position.y + (k + 0.5) * r.size.y / 4.0
					draw_line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), Color("#3b4247"), 2.0)
				draw_rect(r, _c("outline"), false, OUTLINE_W)
			"floor_safe", "trash_chute":
				draw_rect(r, Color("#4a5056"))
				draw_rect(r.grow(-4), Color("#2c3136"), false, 2.0)
				draw_circle(r.get_center(), 3.0, C_BRASS)
			"bus_stop":
				draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color("#3a6fb8"))
				draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), _c("outline"), false, OUTLINE_W)


func _draw_flat_furniture() -> void:
	var ordered: Array[Dictionary] = []
	for entry: Dictionary in _furniture:
		if FLAT_FIRST.has(str(entry["type"])):
			ordered.append(entry)
	for entry: Dictionary in _furniture:
		var type: String = str(entry["type"])
		if not FLAT_FIRST.has(type) and not FurniturePainter.is_prop(type) and not WALL_MOUNTED.has(type):
			ordered.append(entry)
	for entry: Dictionary in ordered:
		_painter.draw_item(self, entry, _footprint_px(entry))


func _footprint_px(entry: Dictionary) -> Rect2:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	return Rect2(Vector2(fp.position) * cell, Vector2(fp.size) * cell)


# ─── Muros, puertas y ventanas ────────────────────────────────

## Huecos por lado [[Vector2(desde, hasta)…] ×4] en celdas locales (puertas y salidas).
func openings() -> Array:
	var out: Array = [[], [], [], []]
	for door: Dictionary in doors:
		_add_opening(out, door["cell"], door["vertical"], int(door["width"]))
	for t: Dictionary in exits:
		_add_opening(out, t["door_cell"], t["door_vertical"], Database.get_balance_int("mundo.ancho_puerta"))
	for side: int in 4:
		(out[side] as Array).sort()
	return out


## Tramos de muro [[lado, Vector2(desde, hasta)]…] en celdas locales (para colisiones).
func wall_segments() -> Array:
	var out: Array = []
	var holes: Array = openings()
	for side: int in 4:
		for seg: Vector2 in _segments(side, holes[side]):
			out.append([side, seg])
	return out


## Rectángulo en px locales del tramo de muro (grosor mundo.grosor_muro centrado en el borde).
func segment_rect(side: int, seg: Vector2) -> Rect2:
	var t: float = _t()
	match side:
		FloorLayout.SIDE_TOP:
			return Rect2(seg.x * cell - t * 0.5, -t * 0.5, (seg.y - seg.x) * cell + t, t)
		FloorLayout.SIDE_BOTTOM:
			return Rect2(seg.x * cell - t * 0.5, rect.size.y * cell - t * 0.5, (seg.y - seg.x) * cell + t, t)
		FloorLayout.SIDE_LEFT:
			return Rect2(-t * 0.5, seg.x * cell - t * 0.5, t, (seg.y - seg.x) * cell + t)
	return Rect2(rect.size.x * cell - t * 0.5, seg.x * cell - t * 0.5, t, (seg.y - seg.x) * cell + t)


func _draw_walls_layer() -> void:
	var holes: Array = openings()
	_draw_north_face(holes[FloorLayout.SIDE_TOP])
	_draw_elevator_car(holes)
	_draw_wall_mounted()
	for side: int in 4:
		for seg: Vector2 in _segments(side, holes[side]):
			_draw_wall_segment(side, seg)
	for door: Dictionary in doors:
		if door["b"] == room_id:
			_draw_door(door)
	for t: Dictionary in exits:
		_draw_exit_door(t)


## Añade el hueco [inicio, fin) (en celdas locales) al lado correspondiente.
func _add_opening(openings: Array, cell_v: Vector2i, vertical: bool, width: int) -> void:
	if vertical:
		var from: int = cell_v.y - rect.position.y
		if cell_v.x == rect.position.x:
			(openings[FloorLayout.SIDE_LEFT] as Array).append(Vector2(from, from + width))
		elif cell_v.x == rect.end.x:
			(openings[FloorLayout.SIDE_RIGHT] as Array).append(Vector2(from, from + width))
	else:
		var from_x: int = cell_v.x - rect.position.x
		if cell_v.y == rect.position.y:
			(openings[FloorLayout.SIDE_TOP] as Array).append(Vector2(from_x, from_x + width))
		elif cell_v.y == rect.end.y:
			(openings[FloorLayout.SIDE_BOTTOM] as Array).append(Vector2(from_x, from_x + width))


## Tramos de muro de un lado (en celdas locales) descontando huecos de puerta.
func _segments(side: int, holes: Array) -> Array[Vector2]:
	var length: float = float(rect.size.x if side <= FloorLayout.SIDE_BOTTOM else rect.size.y)
	var out: Array[Vector2] = []
	var cursor: float = 0.0
	for hole: Vector2 in holes:
		if hole.x > cursor:
			out.append(Vector2(cursor, hole.x))
		cursor = maxf(cursor, hole.y)
	if cursor < length:
		out.append(Vector2(cursor, length))
	return out


## Tramos exteriores (sin sala vecina al otro lado) de un segmento, en celdas locales.
func _exterior_parts(side: int, seg: Vector2) -> Array[Vector2]:
	var covered: Array[Vector2] = []
	for other: Rect2i in neighbours:
		var wall: Dictionary = FloorLayout.shared_wall(rect, other)
		if wall.is_empty() or _wall_side(wall) != side:
			continue
		var base: int = rect.position.y if wall["vertical"] else rect.position.x
		covered.append(Vector2(int(wall["from"]) - base, int(wall["from"]) + int(wall["length"]) - base))
	covered.sort()
	var out: Array[Vector2] = []
	var cursor: float = seg.x
	for c: Vector2 in covered:
		if c.x > cursor:
			out.append(Vector2(cursor, minf(c.x, seg.y)))
		cursor = maxf(cursor, c.y)
		if cursor >= seg.y:
			break
	if cursor < seg.y:
		out.append(Vector2(cursor, seg.y))
	return out.filter(func(v: Vector2) -> bool: return v.y - v.x >= 1.0)


func _wall_side(wall: Dictionary) -> int:
	if wall["vertical"]:
		return FloorLayout.SIDE_LEFT if int(wall["line"]) == rect.position.x else FloorLayout.SIDE_RIGHT
	return FloorLayout.SIDE_TOP if int(wall["line"]) == rect.position.y else FloorLayout.SIDE_BOTTOM


func _has_windows() -> bool:
	var band: String = str(style["band"])
	return band != "the_guts" and str(style["material"]) != "asphalt" and int(style["floor"]) >= 0 \
			and str(style["transit"]).is_empty() and not is_spine


## Color de coronación de muro (vista cenital): oscuro para que las salas se lean de lejos.
func _cap() -> Color:
	match str(style["band"]):
		"the_throne":
			return Color("#232327")
		"the_power":
			return Color("#3b2819")
		"the_guts", "exterior":
			return _c("wall").lightened(0.08)
	return _c("wall").darkened(0.5)


func _draw_north_face(holes: Array) -> void:
	var face: float = cell * FACE_RATIO
	var t: float = _t()
	for seg: Vector2 in _segments(FloorLayout.SIDE_TOP, holes):
		var r: Rect2 = Rect2(seg.x * cell, t * 0.5, (seg.y - seg.x) * cell, face)
		_face_fill(r)
		if _has_windows():
			for part: Vector2 in _exterior_parts(FloorLayout.SIDE_TOP, seg):
				_draw_face_windows(Rect2(part.x * cell, t * 0.5, (part.y - part.x) * cell, face))
	if is_spine:
		_draw_spine_decor(holes)


## Cara norte del muro (vista 3/4) con el acabado de la banda.
func _face_fill(r: Rect2) -> void:
	var wall: Color = _c("wall")
	var band: String = str(style["band"])
	draw_rect(r, wall)
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.62, r.size.x, r.size.y * 0.38), wall.darkened(0.08))
	match band:
		"the_power":
			var panel: Rect2 = Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, r.size.y * 0.58)
			draw_rect(panel, Color("#6f4b2e"))
			for x: int in int(r.size.x / (cell * 0.5)):
				draw_line(Vector2(r.position.x + x * cell * 0.5, panel.position.y + 3), Vector2(r.position.x + x * cell * 0.5,
						panel.end.y - 5), Color("#5a3b22"), 1.0)
			draw_line(panel.position, Vector2(panel.end.x, panel.position.y), C_BRASS, 2.0)
		"the_throne":
			draw_rect(Rect2(r.position.x, r.position.y + 2, r.size.x, r.size.y - 6), _c("window").lerp(wall, 0.35))
			for x: int in int(r.size.x / cell) + 1:
				draw_line(Vector2(r.position.x + x * cell, r.position.y), Vector2(r.position.x + x * cell, r.end.y - 4), _c("accent"), 1.5)
		"the_guts":
			draw_line(Vector2(r.position.x, r.position.y + r.size.y * 0.45), Vector2(r.end.x, r.position.y + r.size.y * 0.45),
					_c("accent").darkened(0.2), 2.0)
		"factory":
			_hazard_band(Rect2(r.position.x, r.end.y - 9, r.size.x, 5))
	draw_line(r.position + Vector2(0, 1), Vector2(r.end.x, r.position.y + 1), wall.lightened(0.18), 2.0)
	draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, 4), _c("shadow"))


func _hazard_band(r: Rect2) -> void:
	draw_rect(r, Color("#1b1b1b"))
	var step: float = r.size.y * 2.0
	var x: float = r.position.x
	while x < r.end.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x, r.end.y), Vector2(minf(x + step * 0.5, r.end.x), r.end.y),
				Vector2(minf(x + step, r.end.x), r.position.y), Vector2(minf(x + step * 0.5, r.end.x), r.position.y)]), C_HAZARD)
		x += step


func _draw_face_windows(r: Rect2) -> void:
	var band: String = str(style["band"])
	var glass: Color = _c("window")
	var pane: float = cell * (1.0 if band == "the_throne" else 1.5)
	var count: int = int(r.size.x / pane)
	var frame: Color = _c("accent") if band in ["the_throne", "the_power"] else _cap()
	for i: int in count:
		var w: Rect2 = Rect2(r.position.x + i * pane + 5.0, r.position.y + 3.0, pane - 10.0, r.size.y * 0.62)
		if band == "the_throne":
			w = Rect2(r.position.x + i * pane, r.position.y + 1.0, pane, r.size.y - 5.0)
		draw_rect(w, glass)
		draw_rect(Rect2(w.position, Vector2(w.size.x, w.size.y * 0.35)), glass.lightened(0.18))
		draw_line(w.position + Vector2(4, w.size.y - 3), w.position + Vector2(w.size.x * 0.3, 3), Color(1, 1, 1, 0.5), 2.0)
		draw_rect(w, frame, false, 2.0)


## Pasillo: extintores, carteles motivacionales según la densidad de la banda y señal de salida.
func _draw_spine_decor(holes: Array) -> void:
	var spacing: int = int(POSTER_SPACING.get(str(style["posters"]), 0))
	var face: float = cell * FACE_RATIO
	var y: float = _t() * 0.5
	for x: int in range(3, rect.size.x - 2, 9):
		if not _in_holes(holes, x):
			var ext: Rect2 = Rect2(x * cell + cell * 0.38, y + face * 0.3, cell * 0.24, face * 0.62)
			draw_rect(ext, C_EXTINGUISHER)
			draw_rect(Rect2(ext.position, Vector2(ext.size.x, 3)), Color("#1b1b1b"))
			draw_rect(ext, _c("outline"), false, 1.5)
	if spacing > 0:
		for x: int in range(6, rect.size.x - 2, spacing):
			if not _in_holes(holes, x):
				_painter.draw_item(self, {"type": "motivational_poster", "pos": Vector2i(x, 0)},
						Rect2(x * cell, y + face * 0.95, cell, cell))
	var sign: Rect2 = Rect2(cell * 0.6, y + 3.0, cell * 0.8, face * 0.4)
	draw_rect(sign, C_EXIT_GREEN)
	draw_rect(sign, _c("outline"), false, 1.5)
	draw_colored_polygon(PackedVector2Array([sign.get_center() + Vector2(-6, -4), sign.get_center() + Vector2(6, 0),
			sign.get_center() + Vector2(-6, 4)]), Color.WHITE)


func _in_holes(holes: Array, x: int) -> bool:
	for hole: Vector2 in holes:
		if x >= hole.x - 1 and x <= hole.y:
			return true
	return false


func _draw_wall_mounted() -> void:
	for entry: Dictionary in _furniture:
		if WALL_MOUNTED.has(str(entry["type"])):
			var r: Rect2 = _footprint_px(entry)
			r.position.y += cell * FACE_RATIO * 0.95
			_painter.draw_item(self, entry, r)


func _draw_wall_segment(side: int, seg: Vector2) -> void:
	var r: Rect2 = segment_rect(side, seg)
	draw_rect(r, _cap())
	if str(style["band"]) in ["the_throne", "the_power"]:
		var inner: Rect2 = r.grow(-_t() * 0.32)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			draw_rect(inner, _c("accent").darkened(0.15))
	draw_rect(r, _c("outline"), false, OUTLINE_W)
	if _has_windows() and side != FloorLayout.SIDE_TOP:
		for part: Vector2 in _exterior_parts(side, seg):
			_draw_wall_window(side, part)


## Ventana dentro del grosor del muro (lados sur, este y oeste).
func _draw_wall_window(side: int, part: Vector2) -> void:
	var t: float = _t()
	var band: String = str(style["band"])
	var margin: float = 0.35 if band != "the_throne" else 0.05
	var from: float = (part.x + margin) * cell
	var to: float = (part.y - margin) * cell
	if to - from < cell * 0.8:
		return
	var r: Rect2
	match side:
		FloorLayout.SIDE_BOTTOM:
			r = Rect2(from, rect.size.y * cell - t * 0.32, to - from, t * 0.64)
		FloorLayout.SIDE_LEFT:
			r = Rect2(-t * 0.32, from, t * 0.64, to - from)
		_:
			r = Rect2(rect.size.x * cell - t * 0.32, from, t * 0.64, to - from)
	draw_rect(r, _c("window").lightened(0.1))
	var mullion: float = cell * (2.0 if band != "the_pit" else 1.5)
	var length: float = to - from
	for i: int in int(length / mullion) + 1:
		var a: Vector2 = r.position + (Vector2(i * mullion, 0) if side == FloorLayout.SIDE_BOTTOM else Vector2(0, i * mullion))
		var b: Vector2 = a + (Vector2(0, r.size.y) if side == FloorLayout.SIDE_BOTTOM else Vector2(r.size.x, 0))
		draw_line(a, b, _c("accent") if band in ["the_throne", "the_power"] else _cap(), 2.0)


## Puerta: umbral en el hueco, jambas, hoja abierta hacia la sala b y lector/candado según tipo.
func _draw_door(door: Dictionary) -> void:
	var t: float = _t()
	var vertical: bool = door["vertical"]
	var start: Vector2 = (Vector2(door["cell"]) - Vector2(rect.position)) * cell
	var span: float = float(door["width"]) * cell
	var along: Vector2 = Vector2(0, 1) if vertical else Vector2(1, 0)
	var across: Vector2 = Vector2(1, 0) if vertical else Vector2(0, 1)
	var into_b: Vector2 = across * (1.0 if _b_is_positive(door) else -1.0)
	var threshold: Rect2 = Rect2(start - across * t * 0.5, along * span + across * t).abs()
	draw_rect(threshold, _c("floor").lightened(0.12))
	draw_rect(threshold, _c("outline").lerp(_c("floor"), 0.5), false, 1.0)
	var kind: String = str(door["kind"])
	if _door_room_kind(door) == FloorLayout.TRANSIT_ELEVATOR:
		_draw_sliding_door(threshold, along)
	else:
		_draw_leaf(start + into_b * t * 0.5, along, into_b, span, kind)
	for end: Vector2 in [start, start + along * span]:
		var post: Rect2 = Rect2(end - Vector2(t, t) * 0.5, Vector2(t, t))
		draw_rect(post, _cap().darkened(0.2))
		draw_rect(post, _c("outline"), false, 1.5)
	if kind == FloorLayout.DOOR_READER or kind == FloorLayout.DOOR_SERVICE:
		var reader_c: Vector2 = start + along * (span + t * 1.2) - into_b * t * 0.95
		draw_rect(Rect2(reader_c - Vector2(5, 6), Vector2(10, 12)), C_READER)
		draw_rect(Rect2(reader_c - Vector2(5, 6), Vector2(10, 12)), _c("outline"), false, 1.0)
		draw_circle(reader_c + Vector2(0, -2), 2.4, C_LED_LOCKED if kind == FloorLayout.DOOR_READER else C_LED_SERVICE)


func _b_is_positive(door: Dictionary) -> bool:
	var b_rect: Rect2i = _rooms_by_id.get(str(door["b"]), rect)
	if door["vertical"]:
		return b_rect.position.x >= int((door["cell"] as Vector2i).x)
	return b_rect.position.y >= int((door["cell"] as Vector2i).y)


func _door_room_kind(door: Dictionary) -> String:
	var b: RoomData = Database.get_room(str(door["b"]))
	return FloorLayout.transit_kind_of(b) if b != null else ""


## Hoja abierta 90º, pegada al muro por la bisagra (símbolo de plano, sin arco).
func _draw_leaf(hinge_line: Vector2, along: Vector2, into_b: Vector2, span: float, kind: String) -> void:
	var col: Color = _c("furniture").darkened(0.1)
	match kind:
		FloorLayout.DOOR_OLD_LOCK:
			col = Color("#7a5230")
		FloorLayout.DOOR_SERVICE:
			col = Color("#8d969b")
		FloorLayout.DOOR_READER:
			col = _c("accent")
	var thick: float = cell * 0.13
	var length: float = span * 0.86
	var hinge: Vector2 = hinge_line + along * thick * 0.5
	var leaf: Rect2 = Rect2(hinge - along * thick * 0.5, into_b * length + along * thick).abs()
	draw_rect(Rect2(leaf.position + Vector2(2, 3), leaf.size), Color(0, 0, 0, 0.25))
	draw_rect(leaf, col)
	draw_rect(leaf, _c("outline"), false, 1.5)
	var knob: Vector2 = hinge + into_b * length * 0.85 + along * thick * 0.9
	if kind == FloorLayout.DOOR_OLD_LOCK:
		draw_circle(knob, 3.5, C_BRASS)
		draw_circle(knob, 1.3, Color("#1b1b1b"))
	elif kind == FloorLayout.DOOR_SERVICE:
		draw_line(hinge + into_b * length * 0.25, hinge + into_b * length * 0.7, C_HAZARD, thick * 0.5)
	else:
		draw_circle(knob, 2.2, C_STEEL)


func _draw_sliding_door(threshold: Rect2, along: Vector2) -> void:
	var half: Rect2 = Rect2(threshold.position, threshold.size * (Vector2(0.47, 1.0) if along.x > 0.5 else Vector2(1.0, 0.47)))
	var other: Rect2 = Rect2(threshold.end - half.size, half.size)
	for panel: Rect2 in [half, other]:
		draw_rect(panel, C_STEEL)
		draw_rect(panel, _c("outline"), false, 1.5)
		draw_line(panel.get_center() - along * 4.0, panel.get_center() + along * 4.0, C_STEEL.lightened(0.3), 2.0)


## Puertas de cabina del ascensor en el muro opuesto a su entrada, con indicador de planta.
func _draw_elevator_car(holes: Array) -> void:
	if str(style["transit"]) != FloorLayout.TRANSIT_ELEVATOR:
		return
	var entry_on_top: bool = not (holes[FloorLayout.SIDE_TOP] as Array).is_empty()
	var w: float = cell * 2.4
	var x: float = rect.size.x * cell * 0.5 - w * 0.5
	var y: float = rect.size.y * cell - _t() * 0.5 - cell * 0.18 if entry_on_top else _t() * 0.5
	var doors: Rect2 = Rect2(x, y, w, cell * FACE_RATIO if not entry_on_top else cell * 0.18)
	draw_rect(doors.grow(4.0), _cap().darkened(0.1))
	for k: int in 2:
		var panel: Rect2 = Rect2(x + k * w * 0.5 + 1.0, doors.position.y, w * 0.5 - 2.0, doors.size.y)
		draw_rect(panel, C_STEEL)
		draw_rect(panel, _c("outline"), false, 1.5)
	var lamp: Vector2 = Vector2(x + w * 0.5, doors.position.y - 6.0 if not entry_on_top else doors.end.y + 6.0)
	draw_rect(Rect2(lamp - Vector2(10, 4), Vector2(20, 8)), Color("#1b1d21"))
	draw_colored_polygon(PackedVector2Array([lamp + Vector2(-4, 2), lamp + Vector2(4, 2), lamp + Vector2(0, -3)]), C_LED_SERVICE)


func _draw_exit_door(t: Dictionary) -> void:
	var width: float = Database.get_balance_int("mundo.ancho_puerta") * cell
	var start: Vector2 = (Vector2(t["door_cell"]) - Vector2(rect.position)) * cell
	var along: Vector2 = Vector2(0, 1) if t["door_vertical"] else Vector2(1, 0)
	var thick: float = _t()
	var mat: Rect2 = Rect2(start - Vector2(thick, thick) * 0.5, along * width + Vector2(thick, thick)).abs()
	draw_rect(mat, Color("#2e3238"))
	for k: int in 2:
		var a: Vector2 = start + along * (k * width * 0.52)
		var r: Rect2 = Rect2(a - Vector2(thick, thick) * 0.3, along * width * 0.46 + Vector2(thick, thick) * 0.6).abs()
		draw_rect(r, _c("window").lightened(0.2))
		draw_rect(r, _c("outline"), false, 1.5)
	var inward: Vector2 = (Vector2(1, 0) if t["door_vertical"] else Vector2(0, 1))
	if Vector2i(t["cell"]) != Vector2i(t["door_cell"]):
		inward = -inward
	var sign_pos: Vector2 = start + along * width * 0.5 + inward * cell * 0.5
	draw_rect(Rect2(sign_pos - Vector2(11, 6), Vector2(22, 12)), C_EXIT_GREEN)
	draw_rect(Rect2(sign_pos - Vector2(11, 6), Vector2(22, 12)), _c("outline"), false, 1.0)
	draw_colored_polygon(PackedVector2Array([sign_pos + Vector2(-5, -3), sign_pos + Vector2(5, 0), sign_pos + Vector2(-5, 3)]),
			Color.WHITE)


# ─── Luz ──────────────────────────────────────────────────────

func _draw_light_layer() -> void:
	var lighting: Dictionary = style.get("lighting", {})
	match str(lighting.get("type", "")):
		"fluorescent":
			_light_panels(C_LIGHT_COOL, LIGHT_ALPHA)
		"uniform":
			_light_panels(Color.WHITE, LIGHT_ALPHA * 0.7)
		"indirect":
			_light_wall_wash()
		"natural":
			_light_sun_shafts()


## Rejilla de luminarias: charcos suaves (los que parpadean los pone RoomBuilder como nodos).
func _light_panels(col: Color, alpha: float) -> void:
	for pos: Vector2 in light_points():
		var i: int = int(pos.x * 3.0 + pos.y * 7.0)
		if bool(style["lighting"].get("flicker", false)) and i % FLICKER_EVERY == 0:
			continue
		draw_light_pool(self, pos, cell * LIGHT_RADIUS_CELLS, col, alpha)


## Centros de luminaria (px locales) en rejilla de LIGHT_GRID_CELLS celdas.
func light_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step: int = LIGHT_GRID_CELLS if not is_spine else LIGHT_GRID_CELLS + 2
	var y: float = rect.size.y * 0.5 if rect.size.y < LIGHT_GRID_CELLS * 2 else LIGHT_GRID_CELLS * 0.5
	while y < rect.size.y:
		var x: float = minf(LIGHT_GRID_CELLS * 0.5, rect.size.x * 0.5)
		while x < rect.size.x:
			out.append(Vector2(x, y) * cell)
			x += step
		y += LIGHT_GRID_CELLS
	return out


## Charco de luz suave (textura radial compartida); aditivo si el lienzo usa ese material.
static func draw_light_pool(ci: CanvasItem, c: Vector2, radius: float, col: Color, alpha: float) -> void:
	ci.draw_texture_rect(RoomBuilder.light_texture(), Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
			false, Color(col.r, col.g, col.b, alpha))


func _light_wall_wash() -> void:
	var size: Vector2 = _size_px()
	var depth: float = cell * 1.1
	var warm: Color = Color(C_LIGHT_WARM.r, C_LIGHT_WARM.g, C_LIGHT_WARM.b, 0.09)
	var none: Color = Color(C_LIGHT_WARM.r, C_LIGHT_WARM.g, C_LIGHT_WARM.b, 0.0)
	var edges: Array = [[Vector2.ZERO, Vector2(size.x, 0), Vector2(0, 1)],
			[Vector2(0, size.y), Vector2(size.x, size.y), Vector2(0, -1)],
			[Vector2.ZERO, Vector2(0, size.y), Vector2(1, 0)], [Vector2(size.x, 0), size, Vector2(-1, 0)]]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n: Vector2 = e[2]
		draw_polygon(PackedVector2Array([a, b, b + n * depth, a + n * depth]),
				PackedColorArray([warm, warm, none, none]))
	for entry: Dictionary in _furniture:
		if str(entry["type"]) in ["executive_desk", "bar_counter", "meeting_table", "sofa", "podium"]:
			draw_light_pool(self, _footprint_px(entry).get_center(), cell * 2.2, C_LIGHT_WARM, 0.16)


func _light_sun_shafts() -> void:
	var sun: Color = Color(1.0, 0.98, 0.9, 0.12)
	var none: Color = Color(1.0, 0.98, 0.9, 0.0)
	var slant: Vector2 = Vector2(cell * 1.2, cell * 3.4)
	for seg: Vector2 in _exterior_parts(FloorLayout.SIDE_TOP, Vector2(0, rect.size.x)):
		var x: float = seg.x * cell
		while x < seg.y * cell - cell:
			var w: float = cell * 1.1
			draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w, 0) + slant, Vector2(x, 0) + slant]),
					PackedColorArray([sun, sun, none, none]))
			x += cell * 1.8


# ─── Fondo de planta: ciudad a los pies, tierra, patio o calle nocturna ──

class Backdrop extends Node2D:
	const EXTRA_CELLS := 30
	const BLOCK_CELLS := 9.0
	const Z_BACKDROP := -40
	const CITY_BASE: Dictionary = {
		"the_pit": Color("#2c3230"), "the_specialists": Color("#2a3644"), "the_power": Color("#23252d"),
		"the_throne": Color("#7f93a3"),
	}
	const C_EARTH := Color("#161715")
	const C_YARD := Color("#34332f")
	const C_NIGHT := Color("#141821")
	const C_WINDOW_LIT := Color("#ffd98a")
	const C_TREE := Color("#24442d")
	const ROOM_SHADOW := Color(0, 0, 0, 0.42)

	var plan: Dictionary = {}
	var cell: float = 48.0
	var band: String = ""
	var pal: Dictionary = {}
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

	func setup(p_plan: Dictionary, p_cell: float) -> void:
		plan = p_plan
		cell = p_cell
		band = str(plan.get("band", ""))
		pal = RoomPainter.palette_of(Database.get_art_band(band))
		z_as_relative = false
		z_index = Z_BACKDROP
		name = "Backdrop"

	func _draw() -> void:
		_rng.seed = hash(int(plan.get("floor", 0)))
		var size: Vector2 = Vector2(plan.get("size", Vector2i.ONE)) * cell
		var extra: Vector2 = Vector2.ONE * EXTRA_CELLS * cell
		var outer: Rect2 = Rect2(-extra, size + extra * 2.0)
		match band:
			"the_guts":
				_earth(outer)
			"exterior":
				_blocks(outer, C_NIGHT, true)
			"factory":
				_yard(outer)
			_:
				_hatch(outer, CITY_BASE.get(band, C_NIGHT))
		_room_shadows()
		for mark: Dictionary in plan.get("landmarks", []):
			var r: Rect2i = mark["rect"]
			_facade(Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell))

	## Manzanas vistas desde lo alto: tejados apenas contrastados, calles y (de noche) ventanas.
	func _blocks(outer: Rect2, base: Color, night: bool) -> void:
		draw_rect(outer, base)
		var step: float = cell * BLOCK_CELLS
		var y: float = outer.position.y
		while y < outer.end.y:
			var x: float = outer.position.x
			while x < outer.end.x:
				var b: Rect2 = Rect2(x + cell, y + cell, step - cell * 2.0, step - cell * 2.0)
				draw_rect(b, base.lightened(_rng.randf_range(0.02, 0.07)))
				draw_rect(b.grow(-cell * 0.6), base.lightened(_rng.randf_range(0.0, 0.04)))
				if night:
					_night_detail(b, base)
				x += step
			y += step

	## Torre: fondo liso con trama diagonal tenue (el vacío alrededor del forjado).
	func _hatch(outer: Rect2, base: Color) -> void:
		draw_rect(outer, base)
		var step: float = cell * 0.75
		var line: Color = base.lightened(0.06)
		var t: float = 0.0
		while t < outer.size.x + outer.size.y:
			var a: Vector2 = outer.position + Vector2(t - outer.size.y, 0.0)
			draw_line(a, a + Vector2(outer.size.y, outer.size.y), line, 1.5)
			t += step

	func _night_detail(b: Rect2, base: Color) -> void:
		for i: int in 5:
			var w: Vector2 = b.position + Vector2(_rng.randf() * b.size.x, _rng.randf() * b.size.y)
			draw_rect(Rect2(w, Vector2(5, 5)), C_WINDOW_LIT.darkened(0.2) if _rng.randf() < 0.5 else base.lightened(0.12))
		for i: int in 2:
			var t: Vector2 = b.position + Vector2(_rng.randf() * b.size.x, b.size.y + cell * 0.5)
			draw_circle(t, cell * 0.55, C_TREE)
			draw_circle(t + Vector2(-cell * 0.15, -cell * 0.15), cell * 0.25, C_TREE.lightened(0.12))

	func _earth(outer: Rect2) -> void:
		draw_rect(outer, C_EARTH)
		for i: int in int(outer.get_area() / (cell * cell * 4.0)):
			var p: Vector2 = outer.position + Vector2(_rng.randf() * outer.size.x, _rng.randf() * outer.size.y)
			draw_circle(p, _rng.randf_range(2.0, 6.0), C_EARTH.lightened(_rng.randf_range(0.02, 0.06)))

	func _yard(outer: Rect2) -> void:
		draw_rect(outer, C_YARD)
		var x: float = outer.position.x
		while x < outer.end.x:
			draw_line(Vector2(x, outer.position.y), Vector2(x, outer.end.y), Color(1, 1, 1, 0.04), 2.0)
			x += cell * 3.0

	## Sombra arrojada de cada sala sobre el fondo (maqueta recortada).
	func _room_shadows() -> void:
		var offset: Vector2 = Vector2(cell * 0.22, cell * 0.32)
		for r: Rect2i in plan.get("rooms", {}).values():
			var px: Rect2 = Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell)
			draw_rect(Rect2(px.position + offset, px.size).grow(cell * 0.1), Color(0, 0, 0, ROOM_SHADOW.a * 0.5))
			draw_rect(Rect2(px.position + offset, px.size), ROOM_SHADOW)

	## Fachada de la sede en el exterior: cristal, ventanas encendidas, marquesina y estrella.
	func _facade(r: Rect2) -> void:
		draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.45))
		draw_rect(r, Color("#1b2430"))
		var band_h: float = cell * 1.1
		var rows: int = int((r.size.y - cell) / band_h)
		for row: int in rows:
			var strip: Rect2 = Rect2(r.position.x + 8.0, r.position.y + row * band_h + 8.0, r.size.x - 16.0, band_h * 0.62)
			draw_rect(strip, Color("#2d4058"))
			var x: float = strip.position.x
			while x < strip.end.x - cell:
				var w: float = cell * _rng.randf_range(0.8, 2.4)
				if _rng.randf() < 0.4:
					draw_rect(Rect2(x, strip.position.y, minf(w, strip.end.x - x), strip.size.y), C_WINDOW_LIT.darkened(0.25))
				x += w
			for k: int in int(strip.size.x / cell) + 1:
				draw_line(Vector2(strip.position.x + k * cell, strip.position.y), Vector2(strip.position.x + k * cell,
						strip.end.y), Color("#131a24"), 2.0)
		var canopy: Rect2 = Rect2(r.position.x, r.end.y - cell * 0.7, r.size.x, cell * 0.7)
		draw_rect(canopy, pal.get("accent", Color.GOLD).darkened(0.3))
		draw_line(canopy.position, Vector2(canopy.end.x, canopy.position.y), pal.get("accent", Color.GOLD), 3.0)
		draw_rect(r, pal.get("outline", Color.BLACK), false, 3.0)
		var c: Vector2 = Vector2(r.get_center().x, r.position.y + r.size.y * 0.4)
		var star: PackedVector2Array = []
		for k: int in 10:
			star.append(c + Vector2.UP.rotated(k * TAU / 10.0) * cell * (1.6 if k % 2 == 0 else 0.68))
		draw_colored_polygon(star, pal.get("accent", Color.GOLD))
		var loop: PackedVector2Array = star.duplicate()
		loop.append(star[0])
		draw_polyline(loop, pal.get("outline", Color.BLACK), 2.5)
