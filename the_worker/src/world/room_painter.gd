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
const WALL_MOUNTED: Array[String] = ["motivational_poster", "mirror", "wall_clock", "fire_extinguisher", "wall_art"]
const FLAT_FIRST: Array[String] = ["rug", "runway", "helipad", "window_wall"]
const LIGHT_ALPHA := 0.13
const AO_DEPTH := 0.45
const AO_ALPHA := 0.22
const LIGHT_RADIUS_CELLS := 2.6
const OUTLINE_W := 2.0
const C_READER := Color("#26292e")
const C_LED_SERVICE := Color("#ffb347")
const C_BRASS := Color("#c9a24a")
const C_STEEL := Color("#aeb6bb")
const C_HAZARD := Color("#f2c230")
const C_EXIT_GREEN := Color("#39d97a")
const C_ROAD_LINE := Color("#e8d27a")
const C_KERB := Color("#8c8f96")
const LIGHT_GRID_CELLS := 4
const WARM_LIT_TYPES: Array[String] = ["executive_desk", "bar_counter", "meeting_table", "sofa", "podium"]
const POSTER_SPACING := {"high": 6, "medium": 10, "low": 16, "none": 0}
## Material de suelo por palabra completa del id de sala (tokens separados por "_"). Un id que
## no encaja con su palabra va en MATERIAL_BY_ID; una sala puede fijarlo con "floor_material".
const MATERIAL_BY_KEYWORD: Dictionary = {
	"toilets": "tile", "pantry": "tile", "kitchen": "tile", "infirmary": "tile", "spa": "tile",
	"cafeteria": "tile", "break": "tile", "garage": "concrete", "warehouse": "concrete",
	"dock": "concrete", "workshop": "concrete", "store": "concrete", "gym": "rubber",
	"terrace": "deck", "machine": "concrete", "server": "raised", "backup": "raised",
}
const MATERIAL_BY_ID: Dictionary = {"flagship_store": "shop_tile"}
const KEY_FLOOR_MATERIAL := "floor_material"

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
	if layer != LAYER_LIGHT:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


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
	if p_room.extra.has(KEY_FLOOR_MATERIAL):
		return str(p_room.extra[KEY_FLOOR_MATERIAL])
	if MATERIAL_BY_ID.has(id):
		return str(MATERIAL_BY_ID[id])
	for token: String in id.split("_"):
		if MATERIAL_BY_KEYWORD.has(token):
			return str(MATERIAL_BY_KEYWORD[token])
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


func _t_draw() -> float:
	return Database.get_balance_float("mundo.grosor_muro_dibujo") * cell


## Alto de la cara norte del muro en 3/4 (mundo.cara_muro celdas; ≈ radio de un actor, para que
## quien pisa la fila de arriba quede al pie del muro y no encima).
func _face() -> float:
	return Database.get_balance_float("mundo.cara_muro") * cell


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
	var top: float = _face() + _t_draw() * 0.5
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


## Suelo en mosaico (FloorTiles: un draw por sala, con mipmaps) de color `base`.
func _tiled(material: String, base: Color, r: Rect2 = Rect2(), extra: Color = Color.BLACK) -> void:
	var area: Rect2 = r if r.has_area() else Rect2(Vector2.ZERO, _size_px())
	draw_texture_rect(FloorTiles.tile(material, base, int(cell), extra), area, true)


func _floor_carpet(size: Vector2) -> void:
	_tiled("carpet", _c("carpet"))
	if str(style["band"]) == "the_pit":
		_tiled("stains", Color.TRANSPARENT)
	elif str(style["band"]) == "the_power":
		FurniturePainter.frame_rect(self, Rect2(Vector2.ZERO, size), _c("floor"), cell * 0.35)
		FurniturePainter.frame_rect(self, Rect2(Vector2.ONE * cell * 0.18, size - Vector2.ONE * cell * 0.36), _c("accent").darkened(0.2), 1.5)


func _floor_linoleum(size: Vector2) -> void:
	_tiled("linoleum", _c("floor"))
	if is_spine and rect.size.y >= 3:
		var runner: Rect2 = Rect2(0, size.y * 0.3, size.x, size.y * 0.4)
		draw_rect(runner, _c("carpet").darkened(0.05))
		FurniturePainter.frame_rect(self, runner, _c("accent"), 2.0)
		if str(style["band"]) == "the_pit":
			_tiled("stains", Color.TRANSPARENT)


func _floor_tile(_size: Vector2) -> void:
	_tiled("tile", _c("floor").lerp(Color("#e9ece8"), 0.55))


func _floor_shop_tile(_size: Vector2) -> void:
	_tiled("shop_tile", _c("floor").lerp(Color("#e9ece8"), 0.55).lerp(_c("light"), 0.12))


func _floor_concrete(size: Vector2) -> void:
	var base: Color = _c("floor")
	_tiled("concrete", base)
	for i: int in maxi(1, rect.size.x / 8):
		var p: Vector2 = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)
		var crack: PackedVector2Array = [p]
		for k: int in 4:
			p += Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * cell
			crack.append(p)
		draw_polyline(crack, base.darkened(0.3), 1.2)


## Nave: hormigón, calle de seguridad amarilla y franja de peligro al pie del muro sur.
func _floor_factory(size: Vector2) -> void:
	_floor_concrete(size)
	var lane: float = cell * 0.18
	var r: Rect2 = Rect2(Vector2(cell, cell), size - Vector2(cell, cell) * 2.0)
	if r.size.x > cell * 2.0 and r.size.y > cell * 2.0:
		FurniturePainter.frame_rect(self, r, C_HAZARD.darkened(0.1), lane)
	var band: Rect2 = Rect2(0, size.y - float(maxi(2, int(cell) / 3)), size.x, float(maxi(2, int(cell) / 3)))
	_tiled("hazard", _c("floor").darkened(0.2), band, C_HAZARD.darkened(0.15))


func _floor_wood(size: Vector2) -> void:
	_tiled("wood", _c("floor") if str(style["band"]) != "exterior" else _c("furniture").lerp(Color("#6a5040"), 0.8))
	if is_spine:
		var runner: Rect2 = Rect2(0, size.y * 0.22, size.x, size.y * 0.56)
		draw_rect(runner, _c("carpet"))
		FurniturePainter.frame_rect(self, Rect2(runner.position + Vector2(0, 4), Vector2(runner.size.x, runner.size.y - 8)),
				_c("accent"), 1.5)


func _floor_marble(size: Vector2) -> void:
	_tiled("marble", _c("floor"))
	if is_spine:
		draw_rect(Rect2(0, size.y * 0.3, size.x, size.y * 0.4), Color(_c("accent"), 0.18))
		FurniturePainter.frame_rect(self, Rect2(0, size.y * 0.3, size.x, size.y * 0.4), _c("accent"), 2.0)


func _floor_stone(_size: Vector2) -> void:
	_tiled("stone", _c("floor").lerp(Color("#cfcabf"), 0.5))


func _floor_raised(_size: Vector2) -> void:
	_tiled("raised", Color("#8f989f").lerp(_c("floor"), 0.45))


func _floor_rubber(_size: Vector2) -> void:
	_tiled("rubber", _c("shadow").lerp(Color("#2f3136"), 0.8))


func _floor_deck(_size: Vector2) -> void:
	_tiled("deck", Color("#a8825a"))


## Calzada: asfalto; en la calle, aceras con bordillo arriba y abajo y línea discontinua central.
func _floor_asphalt(size: Vector2) -> void:
	_tiled("asphalt", _c("floor"))
	if not is_spine:
		return
	var walk: float = cell * 1.6
	var kerb: Color = C_KERB.darkened(0.35)
	_tiled("sidewalk", kerb, Rect2(0, 0, size.x, walk), C_KERB)
	draw_set_transform(Vector2(0, size.y), 0.0, Vector2(1, -1))
	_tiled("sidewalk", kerb, Rect2(0, 0, size.x, walk), C_KERB)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var dash: float = cell * 1.2
	for i: int in int(size.x / (dash * 2.0)) + 1:
		draw_rect(Rect2(i * dash * 2.0, size.y * 0.5 - 1.5, dash, 3.0), C_ROAD_LINE)


func _floor_pavement(_size: Vector2) -> void:
	_tiled("pavement", C_KERB.darkened(0.3))


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
			FurniturePainter.segment(self, Vector2(lane.position.x, y), Vector2(lane.end.x, y), col.darkened(0.3 - 0.2 * i / maxf(1.0, treads)), 2.0)
		FurniturePainter.frame_rect(self, lane, _c("outline"), OUTLINE_W)
	FurniturePainter.segment(self, Vector2(flight.get_center().x, flight.position.y), Vector2(flight.get_center().x, flight.end.y),
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
					FurniturePainter.segment(self, Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), Color("#3b4247"), 2.0)
				FurniturePainter.frame_rect(self, r, _c("outline"), OUTLINE_W)
			"floor_safe", "trash_chute":
				draw_rect(r, Color("#4a5056"))
				FurniturePainter.frame_rect(self, r.grow(-4), Color("#2c3136"), 2.0)
				draw_circle(r.get_center(), 3.0, C_BRASS)
			"bus_stop":
				draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color("#3a6fb8"))
				FurniturePainter.frame_rect(self, Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), _c("outline"), OUTLINE_W)


## Mobiliario plano (alfombras primero; sillas, sofás, camas…) y la pieza de suelo de los recintos
## (moqueta del cubículo, ala lateral y silla; suelo de la cabina): quedan bajo los actores.
func _draw_flat_furniture() -> void:
	var ordered: Array[Dictionary] = []
	for entry: Dictionary in _furniture:
		if FLAT_FIRST.has(str(entry["type"])):
			ordered.append(entry)
	for entry: Dictionary in _furniture:
		var type: String = str(entry["type"])
		if FurniturePainter.is_enclosure(type):
			ordered.append(entry.merged({"part": FurniturePainter.PART_FLOOR}, true))
		elif not FLAT_FIRST.has(type) and not FurniturePainter.is_prop(type) and not WALL_MOUNTED.has(type):
			ordered.append(entry)
	for entry: Dictionary in ordered:
		_painter.draw_item(self, entry, _footprint_px(entry))


func _footprint_px(entry: Dictionary) -> Rect2:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	return Rect2(Vector2(fp.position) * cell, Vector2(fp.size) * cell)


# ─── Muros, puertas y ventanas ────────────────────────────────

## Huecos por lado [[Vector2(desde, hasta)…] ×4] en celdas locales (puertas y, para el dibujo,
## las salidas al exterior, que son puertas de cristal cerradas: se cruzan con su interactivo).
func openings(include_exits: bool = true) -> Array:
	var out: Array = [[], [], [], []]
	for door: Dictionary in doors:
		_add_opening(out, door["cell"], door["vertical"], int(door["width"]))
	if include_exits:
		for t: Dictionary in exits:
			_add_opening(out, t["door_cell"], t["door_vertical"], Database.get_balance_int("mundo.ancho_puerta"))
	for side: int in 4:
		(out[side] as Array).sort()
	return out


## Tramos de muro [[lado, Vector2(desde, hasta)]…] en celdas locales para colisiones: las salidas
## no son hueco (sus puertas de cristal cierran el paso; solo se cruzan con el interactivo).
func wall_segments() -> Array:
	var out: Array = []
	var holes: Array = openings(false)
	for side: int in 4:
		for seg: Vector2 in _segments(side, holes[side]):
			out.append([side, seg])
	return out


## Rectángulo en px locales del tramo de muro centrado en el borde: grosor mundo.grosor_muro
## (colisión) o, con `drawn`, mundo.grosor_muro_dibujo (más grueso: se lee a zoom de planta).
func segment_rect(side: int, seg: Vector2, drawn: bool = false) -> Rect2:
	var t: float = _t_draw() if drawn else _t()
	match side:
		FloorLayout.SIDE_TOP:
			return Rect2(seg.x * cell - t * 0.5, -t * 0.5, (seg.y - seg.x) * cell + t, t)
		FloorLayout.SIDE_BOTTOM:
			return Rect2(seg.x * cell - t * 0.5, rect.size.y * cell - t * 0.5, (seg.y - seg.x) * cell + t, t)
		FloorLayout.SIDE_LEFT:
			return Rect2(-t * 0.5, seg.x * cell - t * 0.5, t, (seg.y - seg.x) * cell + t)
	return Rect2(rect.size.x * cell - t * 0.5, seg.x * cell - t * 0.5, t, (seg.y - seg.x) * cell + t)


## Colisión de un tramo de muro: el norte cubre además su cara 3/4 (nadie pisa la pared dibujada;
## FloorStreamer marca esa fila como no transitable salvo en los huecos de puerta).
func collision_rect(side: int, seg: Vector2) -> Rect2:
	var r: Rect2 = segment_rect(side, seg)
	if side == FloorLayout.SIDE_TOP and rect.size.y >= Database.get_balance_int("mundo.alto_minimo_fila_muro"):
		r.size.y = face_bottom(cell) - r.position.y
	return r


## Pie de la cara 3/4 del muro norte, en px desde el borde superior de la sala.
static func face_bottom(cell_px: float) -> float:
	return (Database.get_balance_float("mundo.grosor_muro_dibujo") * 0.5 + Database.get_balance_float("mundo.cara_muro")) * cell_px


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


## Color de coronación de muro (vista cenital, de la paleta): oscuro para leerse de lejos.
func _cap() -> Color:
	match str(style["band"]):
		"the_throne":
			return _c("outline").lightened(0.08)
		"the_power":
			return _c("shadow").lightened(0.08)
		"the_guts", "exterior":
			return _c("wall").lightened(0.08)
	return _c("wall").darkened(0.5)


func _draw_north_face(holes: Array) -> void:
	var face: float = _face()
	var y: float = _t_draw() * 0.5
	for seg: Vector2 in _segments(FloorLayout.SIDE_TOP, holes):
		var r: Rect2 = Rect2(seg.x * cell, y, (seg.y - seg.x) * cell, face)
		_face_fill(r)
		if _has_windows():
			for part: Vector2 in _exterior_parts(FloorLayout.SIDE_TOP, seg):
				_draw_face_windows(Rect2(part.x * cell, y, (part.y - part.x) * cell, face))
	if is_spine:
		_draw_spine_decor(holes)


## Cara norte del muro (vista 3/4) con el acabado de la banda.
func _face_fill(r: Rect2) -> void:
	var wall: Color = _c("wall")
	draw_rect(r, wall)
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.62, r.size.x, r.size.y * 0.38), wall.darkened(0.08))
	match str(style["band"]):
		"the_power":
			var panel: Rect2 = Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, r.size.y * 0.58)
			draw_rect(panel, _c("floor"))
			for x: int in int(r.size.x / (cell * 0.5)):
				FurniturePainter.segment(self, Vector2(r.position.x + x * cell * 0.5, panel.position.y + 3), Vector2(r.position.x + x * cell * 0.5,
						panel.end.y - 5), _c("floor").darkened(0.2), 1.0)
			FurniturePainter.segment(self, panel.position, Vector2(panel.end.x, panel.position.y), _c("accent"), 2.0)
		"the_throne":
			draw_rect(Rect2(r.position.x, r.position.y + 2, r.size.x, r.size.y - 6), _c("window").lerp(wall, 0.35))
			for x: int in int(r.size.x / cell) + 1:
				FurniturePainter.segment(self, Vector2(r.position.x + x * cell, r.position.y), Vector2(r.position.x + x * cell, r.end.y - 4), _c("accent"), 1.5)
		"the_guts":
			FurniturePainter.segment(self, Vector2(r.position.x, r.position.y + r.size.y * 0.45), Vector2(r.end.x, r.position.y + r.size.y * 0.45),
					_c("accent").darkened(0.2), 2.0)
		"factory":
			_hazard_band(Rect2(r.position.x, r.end.y - 10, r.size.x, 6))
	FurniturePainter.segment(self, r.position + Vector2(0, 1), Vector2(r.end.x, r.position.y + 1), wall.lightened(0.18), 2.0)
	draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, 4), _c("shadow"))


## Franja de peligro (nave) en la cara del muro: mosaico de diagonales, un solo draw.
func _hazard_band(r: Rect2) -> void:
	_tiled("hazard_thin", Color("#1b1b1b"), r, C_HAZARD)


func _draw_face_windows(r: Rect2) -> void:
	var band: String = str(style["band"])
	var glass: Color = _c("window")
	var pane: float = cell * (1.0 if band == "the_throne" else 1.5)
	var frame: Color = _c("accent") if band in ["the_throne", "the_power"] else _cap()
	for i: int in int(r.size.x / pane):
		var w: Rect2 = Rect2(r.position.x + i * pane + 5.0, r.position.y + 3.0, pane - 10.0, r.size.y * 0.62)
		if band == "the_throne":
			w = Rect2(r.position.x + i * pane, r.position.y + 1.0, pane, r.size.y - 5.0)
		draw_rect(w, glass)
		draw_rect(Rect2(w.position, Vector2(w.size.x, w.size.y * 0.35)), glass.lightened(0.18))
		FurniturePainter.segment(self, w.position + Vector2(4, w.size.y - 3), w.position + Vector2(w.size.x * 0.3, 3), Color(1, 1, 1, 0.5), 2.0)
		FurniturePainter.frame_rect(self, w, frame, 2.0)


## Pasillo: extintores, carteles motivacionales según la densidad de la banda y señal de salida.
func _draw_spine_decor(holes: Array) -> void:
	var spacing: int = int(POSTER_SPACING.get(str(style["posters"]), 0))
	var bottom: float = _t_draw() * 0.5 + _face()
	for x: int in range(3, rect.size.x - 2, 9):
		if not _in_holes(holes, x):
			_painter.draw_item(self, {"type": "fire_extinguisher", "pos": Vector2i(x, 0)}, Rect2(x * cell, bottom, cell, cell))
	if spacing > 0:
		for x: int in range(6, rect.size.x - 2, spacing):
			if not _in_holes(holes, x):
				_painter.draw_item(self, {"type": "motivational_poster", "pos": Vector2i(x, 0)}, Rect2(x * cell, bottom, cell, cell))
	var sign: Rect2 = Rect2(cell * 0.6, _t_draw() * 0.5 + 3.0, cell * 0.8, _face() * 0.55)
	draw_rect(sign, C_EXIT_GREEN)
	FurniturePainter.frame_rect(self, sign, _c("outline"), 1.5)
	draw_colored_polygon(PackedVector2Array([sign.get_center() + Vector2(-6, -4), sign.get_center() + Vector2(6, 0),
			sign.get_center() + Vector2(-6, 4)]), Color.WHITE)


func _in_holes(holes: Array, x: int) -> bool:
	for hole: Vector2 in holes:
		if x >= hole.x - 1 and x <= hole.y:
			return true
	return false


## Elementos colgados en la cara norte (carteles, espejos, relojes, extintores): el pie de su
## dibujo queda en el pie de la cara del muro.
func _draw_wall_mounted() -> void:
	for entry: Dictionary in _furniture:
		if WALL_MOUNTED.has(str(entry["type"])):
			var r: Rect2 = _footprint_px(entry)
			r.position.y = _t_draw() * 0.5 + _face()
			_painter.draw_item(self, entry, r)


func _draw_wall_segment(side: int, seg: Vector2) -> void:
	var r: Rect2 = segment_rect(side, seg, true)
	draw_rect(r, _cap())
	if str(style["band"]) in ["the_throne", "the_power"]:
		var inner: Rect2 = r.grow(-_t_draw() * 0.32)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			draw_rect(inner, _c("accent").darkened(0.15))
	FurniturePainter.frame_rect(self, r, _c("outline"), OUTLINE_W)
	if _has_windows() and side != FloorLayout.SIDE_TOP:
		for part: Vector2 in _exterior_parts(side, seg):
			_draw_wall_window(side, part)


## Ventana dentro del grosor del muro (lados sur, este y oeste).
func _draw_wall_window(side: int, part: Vector2) -> void:
	var t: float = _t_draw()
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
	for i: int in int((to - from) / mullion) + 1:
		var a: Vector2 = r.position + (Vector2(i * mullion, 0) if side == FloorLayout.SIDE_BOTTOM else Vector2(0, i * mullion))
		var b: Vector2 = a + (Vector2(0, r.size.y) if side == FloorLayout.SIDE_BOTTOM else Vector2(r.size.x, 0))
		FurniturePainter.segment(self, a, b, _c("accent") if band in ["the_throne", "the_power"] else _cap(), 2.0)


## Puerta: umbral de color por tipo, marco a ambos lados y hoja. Las puertas con control de
## acceso (lector, cerradura antigua, servicio) dibujan su hoja y lector en su nodo Door (estado
## abierto/cerrado); aquí solo umbral y marco. Ascensor: puertas correderas de acero.
func _draw_door(door: Dictionary) -> void:
	var t: float = _t_draw()
	var vertical: bool = door["vertical"]
	var start: Vector2 = (Vector2(door["cell"]) - Vector2(rect.position)) * cell
	var span: float = float(door["width"]) * cell
	var along: Vector2 = Vector2(0, 1) if vertical else Vector2(1, 0)
	var across: Vector2 = Vector2(1, 0) if vertical else Vector2(0, 1)
	var into_b: Vector2 = across * (1.0 if _b_is_positive(door) else -1.0)
	var kind: String = str(door["kind"])
	var threshold: Rect2 = Rect2(start - across * t * 0.5, along * span + across * t).abs()
	draw_rect(threshold, _threshold_color(kind))
	FurniturePainter.frame_rect(self, threshold.grow(-3.0), _c("outline").lerp(_threshold_color(kind), 0.6), 1.5)
	if _door_room_kind(door) == FloorLayout.TRANSIT_ELEVATOR:
		_draw_sliding_door(threshold, along)
	elif not FloorLayout.is_controlled_door(door):
		_draw_leaf(start + into_b * t * 0.5, along, into_b, span)
	for end: Vector2 in [start, start + along * span]:
		var post: Rect2 = Rect2(end - Vector2(t, t) * 0.62, Vector2(t, t) * 1.24)
		draw_rect(post, _cap().lightened(0.12))
		FurniturePainter.frame_rect(self, post, _c("outline"), 2.0)
	if FloorLayout.is_controlled_door(door) and kind != FloorLayout.DOOR_OLD_LOCK:
		var reader_c: Vector2 = start + along * (span + t * 1.25) - into_b * t * 0.95
		draw_rect(Rect2(reader_c - Vector2(6, 8), Vector2(12, 16)), C_READER)
		FurniturePainter.frame_rect(self, Rect2(reader_c - Vector2(6, 8), Vector2(12, 16)), _c("outline"), 1.5)
		draw_rect(Rect2(reader_c + Vector2(-3, 1), Vector2(6, 4)), C_LED_SERVICE if kind == FloorLayout.DOOR_SERVICE else C_STEEL)


## Umbral del hueco: acento de la banda (lector), madera (antigua), rayas de peligro (servicio).
func _threshold_color(kind: String) -> Color:
	match kind:
		FloorLayout.DOOR_READER:
			return _c("accent").lerp(_c("floor"), 0.35)
		FloorLayout.DOOR_OLD_LOCK:
			return _c("furniture").darkened(0.35)
		FloorLayout.DOOR_SERVICE:
			return C_HAZARD.darkened(0.25)
	return _c("floor").lightened(0.18)


func _b_is_positive(door: Dictionary) -> bool:
	var b_rect: Rect2i = _rooms_by_id.get(str(door["b"]), rect)
	if door["vertical"]:
		return b_rect.position.x >= int((door["cell"] as Vector2i).x)
	return b_rect.position.y >= int((door["cell"] as Vector2i).y)


func _door_room_kind(door: Dictionary) -> String:
	var b: RoomData = Database.get_room(str(door["b"]))
	return FloorLayout.transit_kind_of(b) if b != null else ""


## Hoja abierta 90º hacia la sala b, gruesa, con arco de barrido y pomo (se lee a zoom de móvil).
func _draw_leaf(hinge_line: Vector2, along: Vector2, into_b: Vector2, span: float) -> void:
	var col: Color = _c("furniture").darkened(0.1)
	var thick: float = cell * 0.2
	var length: float = span * 0.9
	var hinge: Vector2 = hinge_line + along * thick * 0.5
	draw_arc(hinge - along * thick * 0.5, length, along.angle(), into_b.angle(), 14, Color(_c("outline"), 0.45), 2.0)
	var leaf: Rect2 = Rect2(hinge - along * thick * 0.5, into_b * length + along * thick).abs()
	draw_rect(Rect2(leaf.position + Vector2(2, 3), leaf.size), Color(0, 0, 0, 0.25))
	draw_rect(leaf, col)
	FurniturePainter.frame_rect(self, leaf, _c("outline"), 2.0)
	draw_circle(hinge + into_b * length * 0.82 + along * thick * 0.9, 3.0, C_STEEL)


func _draw_sliding_door(threshold: Rect2, along: Vector2) -> void:
	var half: Rect2 = Rect2(threshold.position, threshold.size * (Vector2(0.47, 1.0) if along.x > 0.5 else Vector2(1.0, 0.47)))
	var other: Rect2 = Rect2(threshold.end - half.size, half.size)
	for panel: Rect2 in [half, other]:
		draw_rect(panel, C_STEEL)
		FurniturePainter.frame_rect(self, panel, _c("outline"), 1.5)
		FurniturePainter.segment(self, panel.get_center() - along * 4.0, panel.get_center() + along * 4.0, C_STEEL.lightened(0.3), 2.0)


## Cabina del ascensor en el fondo (muro opuesto a la entrada): marco, puertas de acero,
## indicador de planta encendido y botonera de llamada junto a la puerta.
func _draw_elevator_car(holes: Array) -> void:
	if str(style["transit"]) != FloorLayout.TRANSIT_ELEVATOR:
		return
	var entry_on_top: bool = not (holes[FloorLayout.SIDE_TOP] as Array).is_empty()
	var w: float = minf(cell * 3.0, rect.size.x * cell - cell * 1.2)
	var x: float = rect.size.x * cell * 0.5 - w * 0.5
	var y: float = rect.size.y * cell - _t_draw() * 0.5 - cell * 1.1 if entry_on_top else _t_draw() * 0.5
	var shaft: Rect2 = Rect2(x, y, w, cell * 1.1 if entry_on_top else _face() + cell * 0.7)
	var mat: Rect2 = Rect2(x, shaft.position.y - cell * 0.9, w, cell * 0.8) if entry_on_top \
			else Rect2(x, shaft.end.y + 5.0, w, cell * 0.8)
	draw_rect(mat, _c("shadow").darkened(0.2))
	FurniturePainter.frame_rect(self, mat.grow(-3.0), _c("accent"), 2.0)
	draw_rect(shaft.grow(5.0), _cap())
	FurniturePainter.frame_rect(self, shaft.grow(5.0), _c("outline"), 2.0)
	for k: int in 2:
		var panel: Rect2 = Rect2(x + k * w * 0.5 + 1.5, shaft.position.y, w * 0.5 - 3.0, shaft.size.y)
		draw_rect(panel, C_STEEL.lerp(_c("wall"), 0.2))
		draw_rect(Rect2(panel.position, Vector2(panel.size.x, panel.size.y * 0.3)), C_STEEL.lightened(0.18))
		FurniturePainter.frame_rect(self, panel, _c("outline"), 1.5)
	var lamp: Vector2 = Vector2(x + w * 0.5, shaft.position.y - 12.0 if not entry_on_top else shaft.end.y + 12.0)
	draw_rect(Rect2(lamp - Vector2(16, 6), Vector2(32, 12)), Color("#15171b"))
	FurniturePainter.frame_rect(self, Rect2(lamp - Vector2(16, 6), Vector2(32, 12)), _c("outline"), 1.5)
	draw_colored_polygon(PackedVector2Array([lamp + Vector2(-5, 3), lamp + Vector2(5, 3), lamp + Vector2(0, -4)]), C_LED_SERVICE)
	var panel_c: Vector2 = Vector2(shaft.end.x + cell * 0.45, shaft.get_center().y)
	draw_rect(Rect2(panel_c - Vector2(7, 12), Vector2(14, 24)), C_STEEL.darkened(0.2))
	FurniturePainter.frame_rect(self, Rect2(panel_c - Vector2(7, 12), Vector2(14, 24)), _c("outline"), 1.5)
	draw_circle(panel_c + Vector2(0, -5), 3.5, C_EXIT_GREEN)
	draw_circle(panel_c + Vector2(0, 5), 3.5, C_LED_SERVICE)


## Salida al exterior: puertas dobles de cristal cerradas (colisión en RoomBuilder), felpudo y cartel.
func _draw_exit_door(t: Dictionary) -> void:
	var width: float = Database.get_balance_int("mundo.ancho_puerta") * cell
	var start: Vector2 = (Vector2(t["door_cell"]) - Vector2(rect.position)) * cell
	var along: Vector2 = Vector2(0, 1) if t["door_vertical"] else Vector2(1, 0)
	var thick: float = _t_draw()
	var inward: Vector2 = (Vector2(1, 0) if t["door_vertical"] else Vector2(0, 1))
	if Vector2i(t["cell"]) != Vector2i(t["door_cell"]):
		inward = -inward
	var mat: Rect2 = Rect2(start + inward * thick * 0.5, along * width + inward * cell * 0.7).abs()
	draw_rect(mat, _c("shadow").darkened(0.2))
	FurniturePainter.frame_rect(self, mat.grow(-4.0), _c("accent").darkened(0.2), 2.0)
	for k: int in 2:
		var a: Vector2 = start + along * (k * width * 0.5)
		var r: Rect2 = Rect2(a - Vector2(thick, thick) * 0.4, along * width * 0.5 + Vector2(thick, thick) * 0.8).abs()
		draw_rect(r, _c("window").lightened(0.25))
		FurniturePainter.frame_rect(self, r, _c("outline"), 2.0)
		FurniturePainter.segment(self, r.get_center() - along * 6.0, r.get_center() + along * 6.0, C_STEEL, 3.0)
	for end: Vector2 in [start, start + along * width]:
		draw_rect(Rect2(end - Vector2(thick, thick) * 0.62, Vector2(thick, thick) * 1.24), _cap().lightened(0.12))
	var sign_pos: Vector2 = start + along * width * 0.5 + inward * cell * 1.05
	draw_rect(Rect2(sign_pos - Vector2(14, 8), Vector2(28, 16)), C_EXIT_GREEN)
	FurniturePainter.frame_rect(self, Rect2(sign_pos - Vector2(14, 8), Vector2(28, 16)), _c("outline"), 1.5)
	draw_colored_polygon(PackedVector2Array([sign_pos + Vector2(-6, -4), sign_pos + Vector2(6, 0), sign_pos + Vector2(-6, 4)]),
			Color.WHITE)


# ─── Luz ──────────────────────────────────────────────────────

## Luz aditiva por banda (color "light" de la paleta; alfa × art_bands lighting.intensity).
func _draw_light_layer() -> void:
	var lighting: Dictionary = style.get("lighting", {})
	var strength: float = float(lighting.get("intensity", 1.0))
	match str(lighting.get("type", "")):
		"fluorescent":
			_light_panels(_c("light"), LIGHT_ALPHA * strength)
		"uniform":
			_light_panels(_c("light"), LIGHT_ALPHA * 0.7 * strength)
		"indirect":
			_light_wall_wash(strength)
		"natural":
			_light_sun_shafts(strength)


## Rejilla de luminarias: charcos suaves (los que parpadean los pone FloorLighting como nodos).
func _light_panels(col: Color, alpha: float) -> void:
	var flicker: bool = bool(style["lighting"].get("flicker", false))
	for pos: Vector2 in light_points():
		if flicker and FloorLighting.is_flicker_point(pos):
			continue
		FloorLighting.draw_light_pool(self, pos, cell * LIGHT_RADIUS_CELLS, col, alpha)


## Centros de luminaria (px locales) de esta sala.
func light_points() -> Array[Vector2]:
	return grid_points(rect.size, is_spine, cell)


## Centros de luminaria (px locales) en rejilla de LIGHT_GRID_CELLS celdas (más espaciada en el eje).
static func grid_points(size: Vector2i, spine: bool, cell_px: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step: int = LIGHT_GRID_CELLS if not spine else LIGHT_GRID_CELLS + 2
	var y: float = size.y * 0.5 if size.y < LIGHT_GRID_CELLS * 2 else LIGHT_GRID_CELLS * 0.5
	while y < size.y:
		var x: float = minf(LIGHT_GRID_CELLS * 0.5, size.x * 0.5)
		while x < size.x:
			out.append(Vector2(x, y) * cell_px)
			x += step
		y += LIGHT_GRID_CELLS
	return out


## Luz cálida indirecta (the_power): baño en la base de los muros y charcos sobre los muebles nobles.
func _light_wall_wash(strength: float) -> void:
	var size: Vector2 = _size_px()
	var depth: float = cell * 1.1
	var warm_c: Color = _c("light")
	var warm: Color = Color(warm_c, 0.09 * strength)
	var none: Color = Color(warm_c, 0.0)
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
		if str(entry["type"]) in WARM_LIT_TYPES:
			FloorLighting.draw_light_pool(self, _footprint_px(entry).get_center(), cell * 2.2, warm_c, 0.16 * strength)


## Haces de sol oblicuos que entran por las ventanas del norte (the_throne).
func _light_sun_shafts(strength: float) -> void:
	var sun: Color = Color(_c("light"), 0.12 * strength)
	var none: Color = Color(_c("light"), 0.0)
	var slant: Vector2 = Vector2(cell * 1.2, cell * 3.4)
	for seg: Vector2 in _exterior_parts(FloorLayout.SIDE_TOP, Vector2(0, rect.size.x)):
		var x: float = seg.x * cell
		while x < seg.y * cell - cell:
			var w: float = cell * 1.1
			draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w, 0) + slant, Vector2(x, 0) + slant]),
					PackedColorArray([sun, sun, none, none]))
			x += cell * 1.8
