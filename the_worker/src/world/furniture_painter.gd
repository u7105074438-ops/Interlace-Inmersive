# furniture_painter.gd — Siluetas vectoriales de todo el mobiliario de data/rooms, dibujadas por código.
# PROPIETARIO DE: nada (dibuja; la tabla de huellas/bloqueos es dato constante de presentación).
# ESCUCHA: nada.
class_name FurniturePainter
extends RefCounted

## Uso: var p := FurniturePainter.new(style)  (style = RoomPainter.style_for(...))
##      p.draw_item(canvas_item, entry, footprint_rect_px)
## `footprint_rect_px` es la huella del mueble en coordenadas locales del canvas; las piezas altas
## se extruyen hacia arriba (vista cenital 3/4). Orientación (§27): grados horario, 0 = mira al sur.
## Clases de bloqueo (BUILD_NOTES §14): TALL capa 2 (bloquea paso y visión), LOW capa 3 (bloquea
## paso, obstrucción parcial ×0,4), NONE sin colisión. Tipos desconocidos → caja genérica LOW.
## Recintos (cubículo, cabina de aseo): solo bloquea su fila del fondo (mesa, inodoro); la fila
## abierta es transitable y sus mamparas laterales cortan el paso por los costados. Se dibujan en
## piezas (entry["part"]): "floor" plano bajo los actores, "back" (mampara del fondo + mesa, con
## origen de orden Y al pie de la fila del fondo) y "sides" (mamparas laterales, origen al pie de
## la huella), para que quien se sienta dentro se vea (BUILD_NOTES §14: los NPC llegan a su mesa).

const BLOCK_NONE := 0
const BLOCK_LOW := 1
const BLOCK_TALL := 2
const PART_FULL := ""
const PART_FLOOR := "floor"
const PART_BACK := "back"
const PART_SIDES := "sides"
const ENCLOSURES: Array[String] = ["cubicle", "toilet_stall"]
## Silla del cubículo: centro del hueco + x, a y px del borde abierto (px de referencia).
const CHAIR_OFFSET := Vector2(6, 16)
const PARTITION_REF := 7.0
const DEFAULT_SIZES: Dictionary = {"cubicle": Vector2i(2, 2), "toilet_stall": Vector2i(2, 2)}
## tipo → [bloqueo, altura de extrusión en px a 48 px/celda, "prop" (ordenado en Y) | "flat"]
const SPECS: Dictionary = {
	"armchair": [BLOCK_LOW, 8, "flat"], "bar_counter": [BLOCK_LOW, 14, "prop"],
	"bed": [BLOCK_LOW, 6, "flat"], "bench": [BLOCK_LOW, 5, "flat"],
	"boiler": [BLOCK_TALL, 30, "prop"], "bookshelf": [BLOCK_TALL, 30, "prop"],
	"car": [BLOCK_LOW, 12, "prop"], "cash_register": [BLOCK_LOW, 10, "prop"],
	"chair": [BLOCK_NONE, 0, "flat"], "clothes_rack": [BLOCK_LOW, 22, "prop"],
	"coffee_machine": [BLOCK_LOW, 16, "prop"], "conveyor": [BLOCK_LOW, 8, "prop"],
	"counter": [BLOCK_LOW, 13, "prop"], "crate": [BLOCK_LOW, 14, "prop"],
	"cubicle": [BLOCK_LOW, 14, "prop"], "desk": [BLOCK_LOW, 8, "prop"], "curtain": [BLOCK_NONE, 0, "flat"],
	"dumpster": [BLOCK_LOW, 16, "prop"], "electrical_panel": [BLOCK_TALL, 26, "prop"],
	"executive_desk": [BLOCK_LOW, 10, "prop"], "filing_cabinet": [BLOCK_TALL, 22, "prop"],
	"foosball_table": [BLOCK_LOW, 9, "prop"], "fridge": [BLOCK_TALL, 30, "prop"],
	"helipad": [BLOCK_NONE, 0, "flat"], "holding_cell": [BLOCK_TALL, 26, "prop"],
	"hot_tub": [BLOCK_LOW, 6, "prop"], "hvac_unit": [BLOCK_TALL, 18, "prop"],
	"industrial_machine": [BLOCK_TALL, 26, "prop"], "kitchen_counter": [BLOCK_LOW, 13, "prop"],
	"light_stand": [BLOCK_LOW, 26, "prop"], "lockers": [BLOCK_TALL, 32, "prop"],
	"mannequin": [BLOCK_LOW, 26, "prop"], "massage_table": [BLOCK_LOW, 6, "flat"],
	"meeting_table": [BLOCK_LOW, 8, "prop"], "mirror": [BLOCK_NONE, 0, "flat"],
	"mixing_desk": [BLOCK_LOW, 10, "prop"], "monitor_wall": [BLOCK_LOW, 24, "prop"],
	"motivational_poster": [BLOCK_NONE, 0, "flat"], "pallet_stack": [BLOCK_TALL, 22, "prop"],
	"photo_backdrop": [BLOCK_TALL, 28, "prop"], "photocopier": [BLOCK_LOW, 14, "prop"],
	"piano": [BLOCK_LOW, 10, "prop"], "plant": [BLOCK_LOW, 22, "prop"],
	"planter_box": [BLOCK_LOW, 10, "prop"], "podium": [BLOCK_LOW, 16, "prop"],
	"printer": [BLOCK_LOW, 10, "prop"], "reception_desk": [BLOCK_LOW, 14, "prop"],
	"rug": [BLOCK_NONE, 0, "flat"], "runway": [BLOCK_NONE, 0, "flat"],
	"safe": [BLOCK_LOW, 16, "prop"], "sauna": [BLOCK_TALL, 28, "prop"],
	"server_rack": [BLOCK_TALL, 32, "prop"], "shelf_rack": [BLOCK_TALL, 28, "prop"],
	"sink": [BLOCK_LOW, 9, "prop"], "sofa": [BLOCK_LOW, 8, "flat"],
	"statue": [BLOCK_TALL, 30, "prop"], "street_lamp": [BLOCK_LOW, 40, "prop"],
	"table": [BLOCK_LOW, 8, "prop"], "toilet_stall": [BLOCK_TALL, 28, "prop"],
	"trash_bin": [BLOCK_LOW, 8, "prop"], "treadmill": [BLOCK_LOW, 8, "prop"],
	"trophy_case": [BLOCK_TALL, 28, "prop"], "turnstile": [BLOCK_NONE, 12, "prop"],
	"tv": [BLOCK_LOW, 16, "prop"], "vending_machine": [BLOCK_TALL, 32, "prop"],
	"wardrobe": [BLOCK_TALL, 30, "prop"], "water_cooler": [BLOCK_LOW, 20, "prop"],
	"weight_bench": [BLOCK_LOW, 6, "flat"], "whiteboard": [BLOCK_LOW, 24, "prop"],
	"window_wall": [BLOCK_LOW, 0, "flat"], "workbench": [BLOCK_LOW, 10, "prop"],
	"barrier": [BLOCK_LOW, 16, "prop"], "wall_clock": [BLOCK_NONE, 0, "flat"],
	"fire_extinguisher": [BLOCK_NONE, 0, "flat"], "wall_art": [BLOCK_NONE, 0, "flat"],
}
const UNKNOWN_SPEC: Array = [BLOCK_LOW, 12, "prop"]
## Silueta normalizada de un piano de cola (teclado arriba, cola curva abajo).
const PIANO_SHAPE: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.28), Vector2(0.92, 0.42),
		Vector2(0.8, 0.5), Vector2(0.7, 0.6), Vector2(0.66, 0.72), Vector2(0.62, 0.85), Vector2(0.5, 0.96),
		Vector2(0.3, 1.0), Vector2(0.12, 0.97), Vector2(0.02, 0.88), Vector2(0, 0.75)]
const REFERENCE_CELL := 48.0
const CONVEYOR_SPEED := 16.0
const INSET := 3.0
const OUTLINE_W := 2.0
const THIN_W := 1.0
## Radio (px de referencia) hasta el que un punto se pinta como cuadradito agrupable (PASO 40).
const DOT_MAX := 3.2
const SHADOW := Color(0, 0, 0, 0.22)
const SHADOW_OFFSET := Vector2(3, 4)
const C_SCREEN := Color("#9fd8f0")
const C_SCREEN_DARK := Color("#1d2733")
const C_PAPER := Color("#f4f1e8")
const C_METAL := Color("#9aa3a8")
const C_STEEL_DARK := Color("#3b4247")
const C_WOOD := Color("#9b6a3f")
const C_CARDBOARD := Color("#b8895a")
const C_HAZARD := Color("#f2c230")
const C_GREEN_LED := Color("#5dff8a")
const C_RED_LED := Color("#ff4d4d")
const C_WATER := Color("#6fc9e6")
const C_GOLD := Color("#d9b45a")
const C_CERAMIC := Color("#eef1f2")
const C_LEAF_PLASTIC: Array[Color] = [Color("#2fd05a"), Color("#46e06a"), Color("#1fb84b")]
const C_LEAF_NATURAL: Array[Color] = [Color("#3f7d3a"), Color("#5a9a48"), Color("#2e5e34"),
		Color("#79a95a"), Color("#4c8a52")]
const C_BOOKS: Array[Color] = [Color("#b8433a"), Color("#3a6fb8"), Color("#e0b43a"),
		Color("#4a9a5a"), Color("#7a4ab8"), Color("#d9d2c0"), Color("#2d2d38")]
const C_PRODUCTS: Array[Color] = [Color("#e84a3a"), Color("#f2c230"), Color("#3a8fe8"), Color("#4ac06a"),
		Color("#f28c1c"), Color("#b04ae8"), Color("#f4f1e8")]
const C_BINDERS: Array[Color] = [Color("#e8e0c8"), Color("#c9b98f"), Color("#7fa0c0"), Color("#d8d2c0")]
const C_CARS: Array[Color] = [Color("#c23b35"), Color("#2c5fa8"), Color("#e8e6df"),
		Color("#1f1f24"), Color("#6b7580"), Color("#d8a83a")]
const C_CLOTHES: Array[Color] = [Color("#c94a4a"), Color("#3a6fb8"), Color("#e8d8b0"),
		Color("#2d2d38"), Color("#5aa06a"), Color("#d98a3a")]

var pal: Dictionary = {}
var style: Dictionary = {}
var scale: float = 1.0
## Tiempo de animación ambiental (lo fija el nodo que dibuja, p. ej. la cinta transportadora).
var anim_time: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _entry: Dictionary = {}
var _part: String = PART_FULL
var _open_south: bool = true
var _seed: int = 0
var _owner: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(room_style: Dictionary) -> void:
	style = room_style
	pal = room_style.get("pal", {})
	scale = float(room_style.get("cell", REFERENCE_CELL)) / REFERENCE_CELL


# ─── Metadatos estáticos ──────────────────────────────────────

static func spec_of(type: String) -> Array:
	return SPECS.get(type, UNKNOWN_SPEC)


static func blocking_of(type: String) -> int:
	return int(spec_of(type)[0])


static func is_prop(type: String) -> bool:
	return str(spec_of(type)[2]) == "prop"


## Huella del mueble en celdas locales de la sala.
static func footprint(entry: Dictionary) -> Rect2i:
	var pos: Vector2i = entry.get("pos", Vector2i.ZERO)
	var size: Vector2i = DEFAULT_SIZES.get(str(entry["type"]), Vector2i.ONE)
	if entry.has("size") and entry["size"] is Array and (entry["size"] as Array).size() == 2:
		size = Vector2i(int(entry["size"][0]), int(entry["size"][1]))
	return Rect2i(pos, Vector2i(maxi(1, size.x), maxi(1, size.y)))


## Celdas que bloquean el paso (un recinto solo bloquea su fila del fondo).
static func blocked_cells(entry: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rect: Rect2i = footprint(entry)
	var type: String = str(entry["type"])
	if blocking_of(type) == BLOCK_NONE:
		return out
	var enclosure: bool = is_enclosure(type)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if enclosure and y != back_row(entry):
				continue
			out.append(Vector2i(x, y))
	return out


static func is_enclosure(type: String) -> bool:
	return ENCLOSURES.has(type)


## Recinto abierto al sur (rotación 0; los laterales 90/270 se tratan como 0) o al norte (180).
static func opens_south(entry: Dictionary) -> bool:
	return facing_of(float(entry.get("rotation", 0.0))).y > -0.5


## Fila (celdas locales de sala) del fondo de un recinto: mesa del cubículo, inodoro de la cabina.
static func back_row(entry: Dictionary) -> int:
	var rect: Rect2i = footprint(entry)
	return rect.position.y if opens_south(entry) else rect.end.y - 1


## Fila abierta (la del asiento) de un recinto: la contigua a la fila del fondo.
static func open_row(entry: Dictionary) -> int:
	return back_row(entry) + (1 if opens_south(entry) else -1)


## Celdas justo fuera del lado abierto de un recinto (por donde se entra).
static func front_cells(entry: Dictionary) -> Array[Vector2i]:
	var rect: Rect2i = footprint(entry)
	var y: int = rect.end.y if opens_south(entry) else rect.position.y - 1
	var out: Array[Vector2i] = []
	for x: int in range(rect.position.x, rect.end.x):
		out.append(Vector2i(x, y))
	return out


## Punto de la silla de un cubículo en px, dada su huella en px (lo usan el dibujo y los asientos).
static func chair_point(entry: Dictionary, r: Rect2) -> Vector2:
	var k: float = r.size.x / (REFERENCE_CELL * float(footprint(entry).size.x))
	var x: float = r.get_center().x + CHAIR_OFFSET.x * k
	return Vector2(x, r.end.y - CHAIR_OFFSET.y * k) if opens_south(entry) \
			else Vector2(x, r.position.y + CHAIR_OFFSET.y * k)


## Celda de asiento por defecto (sin silla ni sala): la fila abierta del recinto o detrás de la mesa.
static func seat_cell(entry: Dictionary) -> Vector2i:
	var rect: Rect2i = footprint(entry)
	var facing: Vector2 = facing_of(float(entry.get("rotation", 0.0)))
	if is_enclosure(str(entry["type"])):
		return Vector2i(rect.position.x + rect.size.x / 2 if rect.size.x > 1 else rect.position.x, open_row(entry))
	var behind: Vector2i = Vector2i(roundi(-facing.x), roundi(-facing.y))
	if behind.y < 0:
		return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y - 1)
	if behind.y > 0:
		return Vector2i(rect.position.x + rect.size.x / 2, rect.end.y)
	return Vector2i(rect.position.x - 1 if behind.x < 0 else rect.end.x, rect.position.y)


## Piezas de orden Y de un mueble "prop": [{part, origin_rows}] con el origen (filas desde el borde
## superior de la huella) donde se ordena con los actores. Los recintos se parten en fondo y laterales.
static func prop_parts(entry: Dictionary) -> Array[Dictionary]:
	var rect: Rect2i = footprint(entry)
	if not is_enclosure(str(entry["type"])):
		return [{"part": PART_FULL, "origin_rows": float(rect.size.y)}]
	var back_end: float = float(back_row(entry) - rect.position.y + 1)
	return [{"part": PART_BACK, "origin_rows": back_end}, {"part": PART_SIDES, "origin_rows": float(rect.size.y)}]


static func facing_of(rotation_deg: float) -> Vector2:
	var v: Vector2 = Vector2.DOWN.rotated(deg_to_rad(rotation_deg))
	return Vector2(roundf(v.x), roundf(v.y))


## Altura de extrusión en px (escalada a la celda del estilo).
func height_of(type: String) -> float:
	return float(spec_of(type)[1]) * scale


# ─── Dibujo ───────────────────────────────────────────────────

func draw_item(ci: CanvasItem, entry: Dictionary, r: Rect2) -> void:
	var type: String = str(entry["type"])
	_entry = entry
	_part = str(entry.get("part", PART_FULL))
	_open_south = opens_south(entry)
	_facing = facing_of(float(entry.get("rotation", 0.0)))
	_owner = str(entry.get("owner", ""))
	_seed = hash(str(style.get("room_id", ""))) ^ hash(entry.get("pos", Vector2i.ZERO)) ^ hash(type)
	_rng.seed = _seed
	var method: String = "_draw_" + type
	if has_method(method):
		call(method, ci, r)
	else:
		_draw_generic(ci, r)


# ─── Primitivas ───────────────────────────────────────────────

func _c(key: String) -> Color:
	return pal.get(key, Color.MAGENTA)


func _ol() -> Color:
	return _c("outline")


func _px(v: float) -> float:
	return v * scale


func _inset(r: Rect2, amount: float = INSET) -> Rect2:
	var a: float = _px(amount)
	return Rect2(r.position + Vector2(a, a), r.size - Vector2(a, a) * 2.0)


## Caja 3/4: huella r, cara superior elevada h px y cara frontal visible.
func _box(ci: CanvasItem, r: Rect2, h: float, top: Color, front: Color = Color.TRANSPARENT) -> Rect2:
	var front_col: Color = front if front.a > 0.0 else top.darkened(0.28)
	ci.draw_rect(Rect2(r.position + SHADOW_OFFSET * scale, r.size), SHADOW)
	var top_r: Rect2 = Rect2(r.position.x, r.position.y - h, r.size.x, r.size.y)
	if h > 0.0:
		ci.draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), front_col)
	ci.draw_rect(top_r, top)
	frame_rect(ci, Rect2(r.position.x, r.position.y - h, r.size.x, r.size.y + h), _ol(), _px(OUTLINE_W))
	if h > 0.0:
		segment(ci, Vector2(r.position.x, r.end.y - h), Vector2(r.end.x, r.end.y - h), _ol(), _px(THIN_W))
	return top_r


## Cara frontal de una caja (útil para detallar puertas, cajones, estantes).
func _front(r: Rect2, h: float) -> Rect2:
	return Rect2(r.position.x, r.end.y - h, r.size.x, h)


func _rect(ci: CanvasItem, r: Rect2, fill: Color, outline: bool = true) -> void:
	ci.draw_rect(r, fill)
	if outline:
		frame_rect(ci, r, _ol(), _px(OUTLINE_W))


## Contorno de rectángulo hecho de cuatro rectángulos rellenos (se agrupan con el resto: PASO 40).
static func frame_rect(ci: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var t: float = maxf(1.0, w)
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, t), col)
	ci.draw_rect(Rect2(r.position.x, r.end.y - t, r.size.x, t), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + t, t, maxf(0.0, r.size.y - t * 2.0)), col)
	ci.draw_rect(Rect2(r.end.x - t, r.position.y + t, t, maxf(0.0, r.size.y - t * 2.0)), col)


## Segmento: si es horizontal o vertical, un rectángulo relleno (agrupable); si no, una línea.
static func segment(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
	var t: float = maxf(1.0, w)
	if is_equal_approx(a.y, b.y):
		ci.draw_rect(Rect2(minf(a.x, b.x), a.y - t * 0.5, absf(b.x - a.x), t), col)
	elif is_equal_approx(a.x, b.x):
		ci.draw_rect(Rect2(a.x - t * 0.5, minf(a.y, b.y), t, absf(b.y - a.y)), col)
	else:
		ci.draw_line(a, b, col, w)


## Punto: si es pequeño (≤ DOT_MAX px de referencia), un cuadradito agrupable; si no, un círculo.
func _dot(ci: CanvasItem, c: Vector2, rad: float, fill: Color) -> void:
	if rad <= _px(DOT_MAX):
		ci.draw_rect(Rect2(c - Vector2(rad, rad) * 0.9, Vector2(rad, rad) * 1.8), fill)
	else:
		ci.draw_circle(c, rad, fill)


func _circle(ci: CanvasItem, c: Vector2, rad: float, fill: Color, outline: bool = true) -> void:
	if rad <= _px(DOT_MAX):
		_rect(ci, Rect2(c - Vector2(rad, rad) * 0.9, Vector2(rad, rad) * 1.8), fill, outline)
		return
	ci.draw_circle(c, rad, fill)
	if outline:
		ci.draw_arc(c, rad, 0.0, TAU, 24, _ol(), _px(OUTLINE_W))


func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: bool = true) -> void:
	ci.draw_colored_polygon(pts, fill)
	if outline:
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		ci.draw_polyline(loop, _ol(), _px(OUTLINE_W))


func _rounded(r: Rect2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners: Array[Vector2] = [r.position + Vector2(r.size.x - rad, rad), r.end - Vector2(rad, rad),
			r.position + Vector2(rad, r.size.y - rad), r.position + Vector2(rad, rad)]
	for i: int in 4:
		for step: int in 5:
			var ang: float = -PI * 0.5 + (i + step / 4.0) * PI * 0.5
			pts.append(corners[i] + Vector2(cos(ang), sin(ang)) * rad)
	return pts


func _shadow(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(Rect2(r.position + SHADOW_OFFSET * scale, r.size), SHADOW)


func _pick(colors: Array[Color]) -> Color:
	return colors[_rng.randi_range(0, colors.size() - 1)]


func _fabric() -> Color:
	return _c("accent").lerp(_c("wall"), 0.35)


func _leather() -> Color:
	match str(style.get("band", "")):
		"the_throne":
			return Color("#1c1c1f")
		"the_power":
			return Color("#6e2f22")
		"the_specialists":
			return Color("#2f4a6b")
	return _c("accent").darkened(0.15)


func _monitor(ci: CanvasItem, c: Vector2, w: float, facing_camera: bool) -> void:
	var body: Rect2 = Rect2(c.x - w * 0.5, c.y - _px(14), w, _px(12))
	ci.draw_rect(Rect2(c.x - _px(2), c.y - _px(3), _px(4), _px(4)), C_STEEL_DARK)
	_rect(ci, body, C_SCREEN_DARK)
	if facing_camera:
		ci.draw_rect(_inset(body, 2.0), C_SCREEN)
		segment(ci, body.position + Vector2(_px(4), _px(4)), body.position + Vector2(w * 0.6, _px(4)),
				Color(1, 1, 1, 0.6), _px(1))


func _papers(ci: CanvasItem, r: Rect2, count: int) -> void:
	for i: int in count:
		var p: Vector2 = r.position + Vector2(_rng.randf() * maxf(1.0, r.size.x - _px(10)),
				_rng.randf() * maxf(1.0, r.size.y - _px(8)))
		ci.draw_rect(Rect2(p, Vector2(_px(9), _px(7))), C_PAPER)
		frame_rect(ci, Rect2(p, Vector2(_px(9), _px(7))), _ol().lerp(C_PAPER, 0.5), _px(1))


func _mug(ci: CanvasItem, p: Vector2) -> void:
	_rect(ci, Rect2(p - Vector2(_px(3.5), _px(3.5)), Vector2(_px(7), _px(7))), _pick(C_BOOKS))
	ci.draw_rect(Rect2(p - Vector2(_px(1.5), _px(1.5)), Vector2(_px(3), _px(3))), Color("#3a2418"))


# ─── Oficina ──────────────────────────────────────────────────

## Cubículo en tres piezas (ver cabecera): suelo + ala lateral + silla, fondo (mampara + mesa) y
## laterales. Abierto al sur: mesa arriba, silla abajo mirando al norte; al norte, en espejo.
func _draw_cubicle(ci: CanvasItem, r: Rect2) -> void:
	var t: float = _px(PARTITION_REF)
	var south: bool = _open_south
	var inner: Rect2 = Rect2(r.position.x + t, r.position.y + (t if south else 0.0), r.size.x - t * 2.0, r.size.y - t)
	var desk: Rect2 = Rect2(inner.position.x, inner.position.y if south else inner.end.y - inner.size.y * 0.4,
			inner.size.x, inner.size.y * 0.4)
	var vacant: bool = _owner == "vacant"
	if _part == PART_FLOOR or _part == PART_FULL:
		ci.draw_rect(inner, _c("carpet").lightened(0.04))
		var side_y: float = desk.end.y - _px(4) if south else desk.position.y - inner.size.y * 0.34 + _px(4)
		_box(ci, Rect2(inner.position.x, side_y, inner.size.x * 0.26, inner.size.y * 0.34), _px(5), _c("furniture").darkened(0.04))
		_office_chair(ci, chair_point(_entry, r), Vector2.UP if south else Vector2.DOWN, vacant)
	if _part == PART_BACK or _part == PART_FULL:
		var back: Rect2 = Rect2(r.position.x, r.position.y if south else r.end.y - t, r.size.x, t)
		if south:
			_partition(ci, back)
		var top: Rect2 = _box(ci, desk, _px(5), _c("furniture"))
		_cubicle_desk_items(ci, top, vacant, south)
		if not south:
			_partition(ci, back, 0.6)
	if _part == PART_SIDES or _part == PART_FULL:
		_partition(ci, Rect2(r.position.x, r.position.y, t, r.size.y))
		_partition(ci, Rect2(r.end.x - t, r.position.y, t, r.size.y))


## Mampara tapizada con remate claro (altura del cubículo × `ratio`).
func _partition(ci: CanvasItem, wall: Rect2, ratio: float = 1.0) -> void:
	var fabric: Color = _fabric()
	var rail: Color = _c("furniture").lightened(0.18)
	var wall_top: Rect2 = _box(ci, wall, height_of("cubicle") * ratio, fabric, fabric.darkened(0.25))
	ci.draw_rect(Rect2(wall_top.position, Vector2(wall_top.size.x, _px(2.5))), rail)
	ci.draw_rect(Rect2(wall_top.position, Vector2(_px(2.5), wall_top.size.y)), rail)


## Monitor al fondo de la mesa (de frente si el puesto abre al sur) y teclado del lado del asiento.
func _cubicle_desk_items(ci: CanvasItem, top: Rect2, vacant: bool, screen_visible: bool) -> void:
	var mon_y: float = top.position.y + _px(15) if screen_visible else top.end.y - _px(2)
	var key_y: float = top.end.y - _px(11) if screen_visible else top.position.y + _px(4)
	var mon_c: Vector2 = Vector2(top.get_center().x + _px(6), mon_y)
	ci.draw_rect(Rect2(mon_c.x - _px(11), key_y, _px(22), _px(6)), Color("#e7e4dc"))
	frame_rect(ci, Rect2(mon_c.x - _px(11), key_y, _px(22), _px(6)), _ol(), _px(1))
	_dot(ci, Vector2(mon_c.x + _px(16), key_y + _px(3)), _px(2.5), Color("#e7e4dc"))
	_monitor(ci, mon_c, _px(26), screen_visible)
	if vacant:
		ci.draw_rect(Rect2(top.position.x + _px(4), top.position.y + _px(4), _px(12), _px(9)), C_CARDBOARD)
		return
	_papers(ci, Rect2(top.position.x + _px(3), top.position.y + _px(3), _px(18), _px(14)), 2)
	_mug(ci, Vector2(top.end.x - _px(7), top.position.y + _px(10)))
	if _rng.randf() < 0.5:
		_rect(ci, Rect2(top.position.x + _px(4), top.end.y - _px(12), _px(7), _px(8)), _pick(C_BOOKS))
	if _rng.randf() < 0.35:
		_dot(ci, Vector2(top.end.x - _px(6), top.end.y - _px(8)), _px(3.5), _pick(C_LEAF_PLASTIC))


## Silla de oficina en rectángulos (asiento, respaldo, contorno): se agrupa con el resto (PASO 40).
func _office_chair(ci: CanvasItem, c: Vector2, facing: Vector2, pushed: bool) -> void:
	var col: Color = Color("#3b3f45") if str(style.get("band", "")) != "the_throne" else _leather()
	var off: Vector2 = facing * _px(4) if pushed else Vector2.ZERO
	var seat: Rect2 = Rect2(c + off - Vector2(_px(9), _px(9)), Vector2(_px(18), _px(18)))
	_shadow(ci, seat)
	_rect(ci, seat, col)
	ci.draw_rect(seat.grow(-_px(4)), col.lightened(0.08))
	var back: Rect2 = _edge_strip(seat.grow(_px(1)), -facing, _px(6))
	_rect(ci, back, col.lightened(0.14))


func _draw_chair(ci: CanvasItem, r: Rect2) -> void:
	_office_chair(ci, r.get_center(), _facing, false)


func _draw_desk(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var top: Rect2 = _box(ci, d, height_of("desk"), _c("furniture"))
	var screen_south: bool = _facing.y < -0.5
	var mon_y: float = top.position.y + _px(10) if screen_south else top.end.y - _px(4)
	if _owner != "vacant":
		_papers(ci, Rect2(top.position.x + _px(3), top.position.y + _px(3), top.size.x * 0.35, top.size.y - _px(8)), 2)
		_mug(ci, Vector2(top.end.x - _px(8), top.get_center().y))
	_monitor(ci, Vector2(top.get_center().x, mon_y), _px(20), screen_south)


func _draw_executive_desk(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var wood: Color = _c("furniture") if str(style.get("band", "")) != "the_throne" else Color("#141416")
	var top: Rect2 = _box(ci, d, height_of("executive_desk"), wood.lightened(0.08), wood.darkened(0.35))
	frame_rect(ci, _inset(top, 3.0), _c("accent"), _px(1.5))
	var pad: Rect2 = Rect2(top.get_center().x - top.size.x * 0.22, top.position.y + top.size.y * 0.3,
			top.size.x * 0.44, top.size.y * 0.42)
	_rect(ci, pad, Color("#1d3a2c") if str(style.get("band", "")) == "the_power" else Color("#2a2a2e"))
	_monitor(ci, Vector2(top.get_center().x, top.position.y + _px(12)), _px(26), _facing.y < -0.5)
	_circle(ci, Vector2(top.position.x + _px(9), top.position.y + _px(9)), _px(5), C_GOLD)
	_dot(ci, Vector2(top.position.x + _px(9), top.position.y + _px(9)), _px(2.5), Color("#fff3c4"))
	ci.draw_rect(Rect2(top.end.x - _px(18), top.end.y - _px(10), _px(12), _px(4)), C_GOLD)
	_papers(ci, Rect2(top.end.x - _px(22), top.position.y + _px(4), _px(14), _px(10)), 1)


func _draw_table(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var col: Color = _c("furniture").lightened(0.05)
	if str(style.get("band", "")) == "the_throne":
		col = Color("#d9ecf2")
	var top: Rect2 = _box(ci, d, height_of("table"), col)
	if r.size.x >= _px(90) and r.size.y >= _px(90):
		_circle(ci, top.get_center(), _px(6), C_CERAMIC)
	for i: int in _rng.randi_range(0, 2):
		_mug(ci, top.position + Vector2(_rng.randf_range(_px(6), top.size.x - _px(6)),
				_rng.randf_range(_px(6), top.size.y - _px(6))))


func _draw_meeting_table(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var band: String = str(style.get("band", ""))
	var col: Color = _c("furniture").darkened(0.1)
	if band == "the_throne":
		col = Color("#1a1a1d")
	elif band == "the_specialists":
		col = Color("#f7f9fb")
	var h: float = height_of("meeting_table")
	_shadow(ci, d)
	ci.draw_rect(Rect2(d.position.x, d.end.y - h, d.size.x, h), col.darkened(0.3))
	var top: Rect2 = Rect2(d.position.x, d.position.y - h, d.size.x, d.size.y)
	_poly(ci, _rounded(top, _px(10)), col)
	frame_rect(ci, _inset(top, 5.0), _c("accent").lerp(col, 0.4), _px(1.5))
	var seats: int = maxi(1, int(top.size.x / _px(48)))
	for i: int in seats:
		var x: float = top.position.x + (i + 0.5) * top.size.x / seats
		ci.draw_rect(Rect2(x - _px(7), top.position.y + _px(6), _px(14), _px(9)), C_PAPER)
		ci.draw_rect(Rect2(x - _px(6), top.end.y - _px(15), _px(12), _px(8)), C_SCREEN_DARK)


func _draw_filing_cabinet(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 5.0)
	var h: float = height_of("filing_cabinet")
	var col: Color = _c("furniture").lerp(C_METAL, 0.45)
	_box(ci, d, h, col.lightened(0.08), col.darkened(0.2))
	var front: Rect2 = _front(d, h)
	for i: int in 3:
		var y: float = front.position.y + front.size.y * (i + 0.5) / 3.0
		segment(ci, Vector2(front.position.x, front.position.y + front.size.y * i / 3.0),
				Vector2(front.end.x, front.position.y + front.size.y * i / 3.0), _ol(), _px(1))
		ci.draw_rect(Rect2(front.get_center().x - _px(4), y - _px(1), _px(8), _px(2.5)), C_STEEL_DARK)


func _draw_printer(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 6.0)
	var top: Rect2 = _box(ci, d, height_of("printer"), Color("#d8dadb"), Color("#9ea3a6"))
	ci.draw_rect(Rect2(top.position.x + _px(5), top.position.y + _px(4), top.size.x - _px(10), _px(8)), C_STEEL_DARK)
	ci.draw_rect(Rect2(top.position.x + _px(7), top.end.y - _px(10), top.size.x - _px(14), _px(6)), C_PAPER)
	_dot(ci, Vector2(top.end.x - _px(6), top.end.y - _px(5)), _px(1.8), C_GREEN_LED)


func _draw_photocopier(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var top: Rect2 = _box(ci, d, height_of("photocopier"), Color("#e2e4e3"), Color("#a7abad"))
	_rect(ci, Rect2(top.position.x + _px(4), top.position.y + _px(4), top.size.x * 0.62, top.size.y - _px(10)),
			Color("#bcc3c6"))
	ci.draw_rect(Rect2(top.end.x - top.size.x * 0.3, top.position.y + _px(6), top.size.x * 0.24, _px(8)),
			C_SCREEN_DARK)
	ci.draw_rect(Rect2(top.end.x - top.size.x * 0.28, top.position.y + _px(8), _px(8), _px(4)), C_SCREEN)
	ci.draw_rect(Rect2(d.end.x - _px(4), d.end.y - _px(12), _px(8), _px(8)), C_PAPER)


func _draw_whiteboard(ci: CanvasItem, r: Rect2) -> void:
	var tall: float = height_of("whiteboard")
	var horizontal: bool = r.size.x >= r.size.y
	var board: Rect2 = Rect2(r.position.x + _px(3), r.end.y - _px(10) - tall, r.size.x - _px(6), tall)
	if not horizontal:
		board = Rect2(r.get_center().x - _px(5), r.position.y - tall * 0.3, _px(10), r.size.y + tall * 0.3)
	_shadow(ci, Rect2(r.position.x, r.end.y - _px(10), r.size.x, _px(8)))
	segment(ci, Vector2(board.position.x + _px(4), board.end.y), Vector2(board.position.x + _px(4), r.end.y - _px(3)),
			C_STEEL_DARK, _px(2))
	segment(ci, Vector2(board.end.x - _px(4), board.end.y), Vector2(board.end.x - _px(4), r.end.y - _px(3)),
			C_STEEL_DARK, _px(2))
	_rect(ci, board, Color("#fbfcfd"))
	if horizontal:
		for i: int in 3:
			var y: float = board.position.y + _px(5) + i * _px(5)
			segment(ci, Vector2(board.position.x + _px(5), y),
					Vector2(board.position.x + _rng.randf_range(0.3, 0.85) * board.size.x, y), _pick(C_BOOKS), _px(1.5))


## Colgados (cartel, espejo, reloj, extintor): r.position.y es el pie de la cara norte del muro.
func _draw_motivational_poster(ci: CanvasItem, r: Rect2) -> void:
	var w: float = _px(26)
	var poster: Rect2 = Rect2(r.get_center().x - w * 0.5, r.position.y - _px(19), w, _px(17))
	_rect(ci, poster, _c("accent").lightened(0.25))
	var img: Rect2 = _inset(poster, 3.0)
	img.size.y *= 0.62
	ci.draw_rect(img, Color("#5b8fc9"))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(img.position.x, img.end.y),
			Vector2(img.get_center().x - _px(3), img.position.y + _px(3)), Vector2(img.end.x, img.end.y)]), Color("#e9eef2"))
	ci.draw_rect(Rect2(poster.position.x + _px(3), poster.end.y - _px(6), w - _px(6), _px(3.5)), Color("#1b1b1b"))
	segment(ci, Vector2(poster.position.x + _px(6), poster.end.y - _px(4.3)),
			Vector2(poster.end.x - _px(6), poster.end.y - _px(4.3)), C_GOLD, _px(1))


func _draw_water_cooler(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center()
	var base: Rect2 = Rect2(c.x - _px(9), c.y - _px(8), _px(18), _px(16))
	_box(ci, base, _px(10), Color("#e9ecee"), Color("#b7bec2"))
	var bottle_c: Vector2 = Vector2(c.x, base.position.y - _px(16))
	_circle(ci, bottle_c, _px(9), C_WATER.lightened(0.2))
	_dot(ci, bottle_c + Vector2(-_px(3), -_px(3)), _px(3), Color(1, 1, 1, 0.7))
	_dot(ci, Vector2(c.x - _px(4), base.end.y - _px(12)), _px(1.6), C_RED_LED)
	_dot(ci, Vector2(c.x + _px(4), base.end.y - _px(12)), _px(1.6), Color("#4da3ff"))


func _draw_coffee_machine(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = Rect2(r.get_center().x - _px(12), r.position.y + _px(8), _px(24), _px(30))
	var top: Rect2 = _box(ci, d, height_of("coffee_machine"), Color("#2b2b2e"), Color("#18181a"))
	ci.draw_rect(Rect2(top.position.x + _px(4), top.position.y + _px(4), _px(9), _px(6)), C_SCREEN)
	_dot(ci, Vector2(top.end.x - _px(6), top.position.y + _px(7)), _px(2), C_RED_LED)
	_circle(ci, Vector2(d.get_center().x, d.end.y - _px(6)), _px(3.5), C_CERAMIC)


func _draw_trash_bin(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center() + Vector2(0, _px(6))
	var body: Rect2 = Rect2(c.x - _px(8), c.y - _px(8), _px(16), _px(12))
	_box(ci, body, height_of("trash_bin"), Color("#6f777c"), Color("#4c5357"))
	ci.draw_rect(Rect2(body.position.x + _px(3), body.position.y - height_of("trash_bin") + _px(3),
			_px(10), _px(6)), Color("#2a2e30"))
	ci.draw_rect(Rect2(body.position.x + _px(5), body.position.y - height_of("trash_bin") + _px(3), _px(5), _px(3)),
			C_PAPER)


func _draw_plant(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center() + Vector2(0, _px(8))
	var pot: Rect2 = Rect2(c.x - _px(9), c.y - _px(6), _px(18), _px(12))
	var pot_col: Color = Color("#c8643b") if bool(style.get("plastic", true)) else Color("#e8e4dc")
	if str(style.get("band", "")) == "the_throne":
		pot_col = Color("#1c1c1f")
	_box(ci, pot, _px(8), pot_col)
	_foliage(ci, Vector2(c.x, pot.position.y - _px(14)), _px(15))


## Follaje: sprite horneado (una textura por tipo de planta y variante: un solo draw y agrupable).
func _foliage(ci: CanvasItem, c: Vector2, size: float) -> void:
	var plastic: bool = bool(style.get("plastic", true))
	var tex: ImageTexture = FurnitureSprites.foliage(plastic, _rng.randi_range(0, FurnitureSprites.FOLIAGE_VARIANTS - 1),
			C_LEAF_PLASTIC if plastic else C_LEAF_NATURAL, _ol())
	var half: float = size * FurnitureSprites.FOLIAGE_SPAN
	ci.draw_texture_rect(tex, Rect2(c - Vector2(half, half) + Vector2(_px(2), _px(3)), Vector2(half, half) * 2.0), false, SHADOW)
	ci.draw_texture_rect(tex, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false)


func _draw_planter_box(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var top: Rect2 = _box(ci, d, height_of("planter_box"), Color("#5a4a3a"), Color("#3e3228"))
	var count: int = maxi(2, int(top.size.x / _px(18)))
	for i: int in count:
		_foliage(ci, Vector2(top.position.x + (i + 0.5) * top.size.x / count, top.get_center().y - _px(4)),
				_px(10))


func _draw_bookshelf(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("bookshelf")
	var wood: Color = C_WOOD if str(style.get("band", "")) != "the_throne" else Color("#2a2522")
	_box(ci, d, h, wood.lightened(0.1), wood.darkened(0.35))
	var front: Rect2 = _inset(_front(d, h), 2.0)
	var rows: int = 2
	for row: int in rows:
		var y0: float = front.position.y + front.size.y * row / rows
		var x: float = front.position.x
		while x < front.end.x - _px(3):
			var bw: float = _rng.randf_range(_px(3), _px(6))
			var bh: float = front.size.y / rows * _rng.randf_range(0.65, 0.95)
			ci.draw_rect(Rect2(x, y0 + front.size.y / rows - bh, minf(bw, front.end.x - x), bh), _pick(C_BOOKS))
			x += bw + _px(0.8)
		segment(ci, Vector2(front.position.x, y0 + front.size.y / rows), Vector2(front.end.x, y0 + front.size.y / rows),
				wood.darkened(0.5), _px(1.5))


func _draw_shelf_rack(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("shelf_rack")
	var metal: Color = C_METAL.lerp(_c("wall"), 0.25)
	var top: Rect2 = _box(ci, d, h, metal.darkened(0.1), metal.darkened(0.45))
	var goods: Array[Color] = _goods_palette()
	_goods_grid(ci, top.grow(-_px(2)), goods)
	if r.size.x < r.size.y:
		return
	var front: Rect2 = _inset(_front(d, h), 1.5)
	for row: int in 2:
		var y: float = front.position.y + front.size.y * (row + 1) / 2.0
		var x: float = front.position.x + _px(1)
		while x < front.end.x - _px(6):
			var bw: float = _rng.randf_range(_px(6), _px(11))
			ci.draw_rect(Rect2(x, y - front.size.y * 0.42, minf(bw, front.end.x - x), front.size.y * 0.4), _pick(goods))
			x += bw + _px(1.5)
		segment(ci, Vector2(front.position.x, y), Vector2(front.end.x, y), C_STEEL_DARK, _px(1.5))


## Mercancía según el uso de la sala: productos de colores (tiendas), archivadores o cajas.
func _goods_palette() -> Array[Color]:
	var room_id: String = str(style.get("room_id", ""))
	var band: String = str(style.get("band", ""))
	if band == "exterior" or room_id.begins_with("flagship") or room_id.contains("shop"):
		return C_PRODUCTS
	if str(style.get("kit", "")) == "archive" or not band in ["the_guts", "factory"]:
		return C_BINDERS
	return [C_CARDBOARD, C_CARDBOARD.darkened(0.12), C_CARDBOARD.lightened(0.1)]


## Rejilla de artículos sobre la balda, a lo largo de su eje mayor (1 o 2 filas).
func _goods_grid(ci: CanvasItem, top: Rect2, goods: Array[Color]) -> void:
	var long_x: bool = top.size.x >= top.size.y
	var length: float = top.size.x if long_x else top.size.y
	var depth: float = top.size.y if long_x else top.size.x
	var lanes: int = 2 if depth > _px(30) else 1
	var step: float = _px(9)
	for lane: int in lanes:
		var t: float = 0.0
		while t < length - step * 0.5:
			var along: float = minf(step - _px(1.5), length - t)
			var across: float = depth / lanes - _px(2)
			var p: Vector2 = Vector2(t, lane * depth / lanes) if long_x else Vector2(lane * depth / lanes, t)
			var size: Vector2 = Vector2(along, across) if long_x else Vector2(across, along)
			ci.draw_rect(Rect2(top.position + p, size), _pick(goods))
			t += step
	frame_rect(ci, top, _ol().lerp(C_METAL, 0.5), _px(1))


func _draw_wardrobe(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("wardrobe")
	_box(ci, d, h, C_WOOD.lightened(0.1), C_WOOD.darkened(0.25))
	var front: Rect2 = _front(d, h)
	segment(ci, Vector2(front.get_center().x, front.position.y), Vector2(front.get_center().x, front.end.y), _ol(), _px(1))
	_dot(ci, Vector2(front.get_center().x - _px(4), front.get_center().y), _px(1.6), C_GOLD)
	_dot(ci, Vector2(front.get_center().x + _px(4), front.get_center().y), _px(1.6), C_GOLD)


func _draw_lockers(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("lockers")
	var col: Color = _c("accent").lerp(C_METAL, 0.55)
	_box(ci, d, h, col.lightened(0.1), col.darkened(0.2))
	var front: Rect2 = _front(d, h) if r.size.x >= r.size.y else Rect2(d.position.x, d.position.y - h, d.size.x, d.size.y + h)
	var doors: int = maxi(1, int(front.size.x / _px(15))) if r.size.x >= r.size.y else maxi(1, int(front.size.y / _px(15)))
	for i: int in doors:
		if r.size.x >= r.size.y:
			var x: float = front.position.x + front.size.x * i / doors
			segment(ci, Vector2(x, front.position.y), Vector2(x, front.end.y), _ol(), _px(1))
			for v: int in 3:
				segment(ci, Vector2(x + _px(3), front.position.y + _px(3 + v * 2.5)),
						Vector2(x + front.size.x / doors - _px(3), front.position.y + _px(3 + v * 2.5)), col.darkened(0.45), _px(1))
		else:
			var y: float = front.position.y + front.size.y * i / doors
			segment(ci, Vector2(front.position.x, y), Vector2(front.end.x, y), _ol(), _px(1))


func _draw_server_rack(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("server_rack")
	_box(ci, d, h, Color("#2a2f36"), Color("#171a1e"))
	var front: Rect2 = _inset(_front(d, h), 2.0)
	var units: int = maxi(1, int(front.size.x / _px(14)))
	for u: int in units:
		var x: float = front.position.x + front.size.x * u / units
		for row: int in 4:
			var y: float = front.position.y + _px(3) + row * front.size.y / 4.0
			segment(ci, Vector2(x + _px(2), y), Vector2(x + front.size.x / units - _px(2), y), Color("#3c434c"), _px(1))
			var led: Color = [C_GREEN_LED, Color("#4da3ff"), Color("#ffb14d")][_rng.randi_range(0, 2)]
			_dot(ci, Vector2(x + _px(4), y + _px(2)), _px(1.3), led)


func _draw_vending_machine(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var h: float = height_of("vending_machine")
	var body: Color = _pick([Color("#c9332f"), Color("#2b5fae")])
	_box(ci, d, h, body.lightened(0.1), body.darkened(0.2))
	var front: Rect2 = _front(d, h)
	var glass: Rect2 = Rect2(front.position.x + _px(3), front.position.y + _px(3), front.size.x * 0.64, front.size.y - _px(6))
	ci.draw_rect(glass, Color("#1c2530"))
	for row: int in 3:
		for col: int in 3:
			ci.draw_rect(Rect2(glass.position.x + _px(2) + col * glass.size.x / 3.0, glass.position.y + _px(2)
					+ row * glass.size.y / 3.0, glass.size.x / 3.0 - _px(3), glass.size.y / 3.0 - _px(4)), _pick(C_BOOKS))
	ci.draw_rect(Rect2(front.end.x - _px(9), front.position.y + _px(5), _px(5), _px(8)), C_SCREEN)


func _draw_fridge(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var h: float = height_of("fridge")
	_box(ci, d, h, Color("#f1f3f4"), Color("#c9cfd2"))
	var front: Rect2 = _front(d, h)
	segment(ci, Vector2(front.position.x, front.position.y + front.size.y * 0.35),
			Vector2(front.end.x, front.position.y + front.size.y * 0.35), _ol(), _px(1))
	segment(ci, Vector2(front.end.x - _px(5), front.position.y + _px(3)),
			Vector2(front.end.x - _px(5), front.position.y + front.size.y * 0.3), C_STEEL_DARK, _px(2))
	segment(ci, Vector2(front.end.x - _px(5), front.position.y + front.size.y * 0.42),
			Vector2(front.end.x - _px(5), front.end.y - _px(4)), C_STEEL_DARK, _px(2))
	ci.draw_rect(Rect2(front.position.x + _px(5), front.position.y + front.size.y * 0.5, _px(6), _px(5)), _pick(C_BOOKS))


func _draw_trophy_case(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("trophy_case")
	_box(ci, d, h, C_WOOD.darkened(0.2), C_WOOD.darkened(0.45))
	var glass: Rect2 = _inset(_front(d, h), 2.5)
	ci.draw_rect(glass, Color(0.75, 0.88, 0.95, 0.55))
	var cups: int = maxi(1, int(glass.size.x / _px(14)))
	for i: int in cups:
		var cx: float = glass.position.x + (i + 0.5) * glass.size.x / cups
		ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - _px(4), glass.position.y + _px(4)),
				Vector2(cx + _px(4), glass.position.y + _px(4)), Vector2(cx + _px(1.5), glass.end.y - _px(6)),
				Vector2(cx - _px(1.5), glass.end.y - _px(6))]), C_GOLD)
		ci.draw_rect(Rect2(cx - _px(3.5), glass.end.y - _px(5), _px(7), _px(3)), C_GOLD.darkened(0.3))
	segment(ci, glass.position + Vector2(_px(2), glass.size.y), glass.position + Vector2(_px(8), 0),
			Color(1, 1, 1, 0.5), _px(1.5))


func _draw_monitor_wall(ci: CanvasItem, r: Rect2) -> void:
	var h: float = height_of("monitor_wall")
	var horizontal: bool = r.size.x >= r.size.y
	var d: Rect2 = _inset(r, 2.0)
	if not horizontal:
		_box(ci, d, h * 0.5, Color("#1b1f25"))
		return
	var frame: Rect2 = Rect2(d.position.x, d.end.y - _px(12) - h, d.size.x, h)
	_shadow(ci, Rect2(d.position.x, d.end.y - _px(12), d.size.x, _px(10)))
	ci.draw_rect(Rect2(d.position.x, d.end.y - _px(12), d.size.x, _px(10)), Color("#2a2f36"))
	_rect(ci, frame, Color("#15181c"))
	var screens: int = maxi(1, int(frame.size.x / _px(26)))
	var cctv: bool = str(style.get("kit", "")) == "lobby" or str(style.get("band", "")) == "the_guts"
	for i: int in screens:
		var s: Rect2 = Rect2(frame.position.x + _px(2) + i * frame.size.x / screens, frame.position.y + _px(2),
				frame.size.x / screens - _px(4), frame.size.y - _px(4))
		ci.draw_rect(s, Color("#7f9aa6") if cctv else _pick([C_SCREEN, Color("#8fe0a8"), Color("#f2c46b")]))
		segment(ci, s.position + Vector2(_px(2), s.size.y * 0.6), s.end - Vector2(_px(2), s.size.y * 0.25),
				Color(0, 0, 0, 0.35), _px(1.5))


func _draw_tv(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var h: float = height_of("tv")
	_box(ci, Rect2(d.position.x + _px(6), d.end.y - _px(10), d.size.x - _px(12), _px(8)), _px(4), Color("#2a2f36"))
	var screen: Rect2 = Rect2(d.position.x, d.end.y - _px(10) - h, d.size.x, h)
	_rect(ci, screen, Color("#111317"))
	ci.draw_rect(_inset(screen, 2.0), Color("#3d6d8f"))


# ─── Asientos y descanso ──────────────────────────────────────

func _seat_piece(ci: CanvasItem, r: Rect2, col: Color, arm: float, back: float) -> void:
	var along: Vector2 = Vector2(-_facing.y, _facing.x)
	var body: Rect2 = r
	_shadow(ci, body)
	_poly(ci, _rounded(body, _px(6)), col)
	var back_rect: Rect2 = _edge_strip(body, -_facing, back)
	_poly(ci, _rounded(back_rect, _px(3)), col.darkened(0.18))
	for side: float in [-1.0, 1.0]:
		var arm_rect: Rect2 = _edge_strip(body, along * side, arm)
		_poly(ci, _rounded(arm_rect, _px(3)), col.darkened(0.1))


## Franja de grosor `t` pegada al borde de r en la dirección `dir`.
func _edge_strip(r: Rect2, dir: Vector2, t: float) -> Rect2:
	if dir.y < -0.5:
		return Rect2(r.position.x, r.position.y, r.size.x, t)
	if dir.y > 0.5:
		return Rect2(r.position.x, r.end.y - t, r.size.x, t)
	if dir.x < -0.5:
		return Rect2(r.position.x, r.position.y, t, r.size.y)
	return Rect2(r.end.x - t, r.position.y, t, r.size.y)


func _draw_armchair(ci: CanvasItem, r: Rect2) -> void:
	_seat_piece(ci, _inset(r, 4.0), _leather(), _px(7), _px(10))


func _draw_sofa(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var col: Color = _leather().lightened(0.08)
	_seat_piece(ci, d, col, _px(7), _px(11))
	var cushions: int = maxi(2, int(maxf(d.size.x, d.size.y) / _px(46)) + 1)
	for i: int in range(1, cushions):
		if absf(_facing.y) > 0.5:
			var x: float = d.position.x + d.size.x * i / cushions
			segment(ci, Vector2(x, d.position.y + _px(12)), Vector2(x, d.end.y - _px(12)), col.darkened(0.3), _px(1))
		else:
			var y: float = d.position.y + d.size.y * i / cushions
			segment(ci, Vector2(d.position.x + _px(12), y), Vector2(d.end.x - _px(12), y), col.darkened(0.3), _px(1))


func _draw_bench(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 8.0)
	var wood: Color = C_WOOD if str(style.get("band", "")) != "exterior" else Color("#7a5a3a")
	_shadow(ci, d)
	_rect(ci, d, wood)
	for i: int in 3:
		var y: float = d.position.y + d.size.y * (i + 1) / 4.0
		segment(ci, Vector2(d.position.x + _px(2), y), Vector2(d.end.x - _px(2), y), wood.darkened(0.35), _px(1))


func _draw_bed(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	_shadow(ci, d)
	_rect(ci, d, C_WOOD.darkened(0.1))
	var mattress: Rect2 = _inset(d, 3.0)
	_rect(ci, mattress, Color("#f3f0e8"))
	var blanket: Rect2 = Rect2(mattress.position.x, mattress.position.y + mattress.size.y * 0.36, mattress.size.x,
			mattress.size.y * 0.64)
	_rect(ci, blanket, _pick([Color("#5a78a8"), Color("#a85a5a"), Color("#6a9a6a"), Color("#c9a86a")]))
	segment(ci, blanket.position + Vector2(0, _px(5)), Vector2(blanket.end.x, blanket.position.y + _px(5)),
			Color(1, 1, 1, 0.5), _px(2))
	var pillows: int = 2 if mattress.size.x > _px(80) else 1
	for i: int in pillows:
		var pw: float = mattress.size.x / pillows - _px(6)
		_poly(ci, _rounded(Rect2(mattress.position.x + _px(3) + i * (pw + _px(6)), mattress.position.y + _px(4), pw,
				mattress.size.y * 0.22), _px(4)), Color("#ffffff"))


func _draw_massage_table(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 6.0)
	_shadow(ci, d)
	_poly(ci, _rounded(d, _px(8)), Color("#e8d8c4"))
	_dot(ci, Vector2(d.position.x + _px(10), d.get_center().y), _px(4), Color("#b8a894"))
	ci.draw_rect(Rect2(d.get_center().x, d.position.y + _px(3), d.size.x * 0.35, d.size.y - _px(6)), Color("#ffffff"))


func _draw_weight_bench(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 8.0)
	_shadow(ci, d)
	_poly(ci, _rounded(d, _px(5)), Color("#26282c"))
	var bar_x: float = d.position.x + d.size.x * 0.25
	segment(ci, Vector2(bar_x, d.position.y - _px(10)), Vector2(bar_x, d.end.y + _px(10)), C_METAL, _px(2.5))
	for y: float in [d.position.y - _px(8), d.end.y + _px(8)]:
		_rect(ci, Rect2(bar_x - _px(5), y - _px(3), _px(10), _px(6)), Color("#1a1a1a"))


func _draw_treadmill(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 5.0)
	var top: Rect2 = _box(ci, d, height_of("treadmill"), Color("#3a3d42"))
	ci.draw_rect(Rect2(top.position.x + _px(5), top.position.y + _px(14), top.size.x - _px(10), top.size.y - _px(18)),
			Color("#141518"))
	_rect(ci, Rect2(top.position.x + _px(2), top.position.y + _px(2), top.size.x - _px(4), _px(10)), Color("#5a5f66"))
	ci.draw_rect(Rect2(top.get_center().x - _px(5), top.position.y + _px(4), _px(10), _px(5)), C_SCREEN)


# ─── Servicios ────────────────────────────────────────────────

func _draw_toilet_stall(ci: CanvasItem, r: Rect2) -> void:
	var h: float = height_of("toilet_stall")
	var t: float = _px(4)
	var col: Color = _c("accent").lerp(Color("#d8d4c8"), 0.55)
	var south: bool = _open_south
	if _part == PART_FLOOR or _part == PART_FULL:
		ci.draw_rect(r, _c("floor").lightened(0.05))
	if _part == PART_BACK or _part == PART_FULL:
		var tank_y: float = r.position.y + _px(4) if south else r.end.y - _px(11)
		var bowl_c: Vector2 = Vector2(r.get_center().x, r.position.y + _px(18) if south else r.end.y - _px(22))
		_rect(ci, Rect2(bowl_c.x - _px(9), tank_y, _px(18), _px(7)), C_CERAMIC)
		_poly(ci, _rounded(Rect2(bowl_c.x - _px(8), bowl_c.y - _px(6), _px(16), _px(20)), _px(8)), C_CERAMIC)
		_dot(ci, bowl_c + Vector2(0, _px(4)), _px(4), C_WATER.lightened(0.3))
	if _part == PART_SIDES or _part == PART_FULL:
		for wall: Rect2 in [Rect2(r.position.x, r.position.y, t, r.size.y), Rect2(r.end.x - t, r.position.y, t, r.size.y)]:
			_box(ci, wall, h, col, col.darkened(0.25))
		var door: Rect2 = Rect2(r.position.x + t, r.end.y - t if south else r.position.y, r.size.x * 0.62, t)
		_box(ci, door, h * 0.92, col.darkened(0.08), col.darkened(0.2))
		_dot(ci, Vector2(door.end.x - _px(5), door.position.y - h * 0.45), _px(1.6), C_RED_LED)


func _draw_sink(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 5.0)
	var counter: Rect2 = _edge_strip(d, -_facing, d.size.y * 0.7 if absf(_facing.y) > 0.5 else d.size.x * 0.7)
	var top: Rect2 = _box(ci, counter, height_of("sink"), Color("#dfe3e5"), Color("#aeb5b9"))
	var basin: Rect2 = _inset(top, 5.0)
	_poly(ci, _rounded(basin, _px(6)), Color("#f6f8f9"))
	_dot(ci, basin.get_center(), _px(1.8), C_STEEL_DARK)
	segment(ci, basin.get_center() - _facing * _px(8), basin.get_center() - _facing * _px(3), C_METAL, _px(2))


func _draw_mirror(ci: CanvasItem, r: Rect2) -> void:
	var m: Rect2 = Rect2(r.position.x + _px(8), r.position.y - _px(17), r.size.x - _px(16), _px(14))
	_rect(ci, m, Color("#cfe6f0"))
	segment(ci, m.position + Vector2(_px(4), m.size.y - _px(3)), m.position + Vector2(_px(11), _px(3)),
			Color(1, 1, 1, 0.8), _px(2))


func _draw_counter(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var top: Rect2 = _box(ci, d, height_of("counter"), _c("furniture").lightened(0.12), _c("furniture").darkened(0.25))
	ci.draw_rect(_edge_strip(top, Vector2.DOWN, _px(3)), _c("accent"))
	_papers(ci, _inset(top, 4.0), 1)


func _draw_kitchen_counter(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var top: Rect2 = _box(ci, d, height_of("kitchen_counter"), Color("#c9ced1"), Color("#e9e4d8"))
	var front: Rect2 = _front(d, height_of("kitchen_counter"))
	var doors: int = maxi(1, int(front.size.x / _px(22)))
	for i: int in doors:
		segment(ci, Vector2(front.position.x + front.size.x * i / doors, front.position.y),
				Vector2(front.position.x + front.size.x * i / doors, front.end.y), _ol(), _px(1))
	if top.size.x > _px(80):
		for k: int in 2:
			ci.draw_arc(Vector2(top.position.x + _px(14) + k * _px(20), top.get_center().y), _px(6), 0.0, TAU, 16,
					C_STEEL_DARK, _px(2))
	var basin: Rect2 = Rect2(top.end.x - _px(24), top.position.y + _px(6), _px(16), top.size.y - _px(12))
	ci.draw_rect(basin, Color("#aab4ba"))
	frame_rect(ci, basin, _ol(), _px(1))


func _draw_bar_counter(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var wood: Color = Color("#3a2418") if str(style.get("band", "")) != "the_throne" else Color("#141416")
	var top: Rect2 = _box(ci, d, height_of("bar_counter"), wood.lightened(0.15), wood)
	ci.draw_rect(_edge_strip(top, Vector2.DOWN, _px(2.5)), C_GOLD)
	var bottles: int = maxi(2, int(top.size.x / _px(12)))
	for i: int in bottles:
		var p: Vector2 = Vector2(top.position.x + (i + 0.5) * top.size.x / bottles, top.position.y + _px(8))
		_circle(ci, p, _px(3), _pick([Color("#3f8a4a"), Color("#8a3f3f"), Color("#d9b45a"), Color("#e8e8e8")]))


func _draw_reception_desk(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var h: float = height_of("reception_desk")
	var top: Rect2 = _box(ci, d, h, _c("furniture").lightened(0.15), _c("accent"))
	var front: Rect2 = _front(d, h)
	ci.draw_rect(Rect2(front.position.x, front.position.y + front.size.y * 0.4, front.size.x, _px(3)), C_GOLD)
	_circle(ci, Vector2(front.get_center().x, front.get_center().y - _px(1)), _px(4), _c("light"))
	_monitor(ci, Vector2(top.position.x + top.size.x * 0.3, top.position.y + _px(12)), _px(18), false)
	_monitor(ci, Vector2(top.position.x + top.size.x * 0.7, top.position.y + _px(12)), _px(18), false)
	_papers(ci, Rect2(top.get_center().x - _px(6), top.end.y - _px(12), _px(12), _px(8)), 1)


func _draw_cash_register(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = Rect2(r.get_center().x - _px(12), r.get_center().y - _px(8), _px(24), _px(18))
	var top: Rect2 = _box(ci, d, height_of("cash_register"), Color("#2f3338"))
	ci.draw_rect(Rect2(top.position.x + _px(3), top.position.y + _px(2), _px(12), _px(6)), C_GREEN_LED.darkened(0.4))
	for i: int in 3:
		ci.draw_rect(Rect2(top.position.x + _px(3) + i * _px(5), top.end.y - _px(7), _px(4), _px(4)), Color("#9aa3a8"))


func _draw_safe(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 6.0)
	var h: float = height_of("safe")
	_box(ci, d, h, Color("#454c52"), Color("#2c3136"))
	var front: Rect2 = _front(d, h)
	_circle(ci, Vector2(front.position.x + front.size.x * 0.4, front.get_center().y), minf(_px(5), front.size.y * 0.35),
			Color("#b8bfc4"))
	segment(ci, Vector2(front.end.x - _px(6), front.position.y + _px(3)), Vector2(front.end.x - _px(6), front.end.y - _px(3)),
			C_GOLD, _px(2))


func _draw_electrical_panel(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = Rect2(r.position.x + _px(8), r.position.y + _px(2), r.size.x - _px(16), _px(12))
	var h: float = height_of("electrical_panel")
	_box(ci, d, h, Color("#8d969b"), Color("#6c757a"))
	var front: Rect2 = _front(d, h)
	var c: Vector2 = front.get_center()
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -_px(6)), c + Vector2(_px(6), _px(5)),
			c + Vector2(-_px(6), _px(5))]), C_HAZARD)
	segment(ci, c + Vector2(0, -_px(2)), c + Vector2(0, _px(2)), Color("#1b1b1b"), _px(1.5))


func _draw_boiler(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var h: float = height_of("boiler")
	var rust: Color = Color("#8a4a2b")
	_shadow(ci, d)
	ci.draw_rect(Rect2(d.position.x, d.get_center().y - h, d.size.x, d.size.y * 0.5 + h), rust.darkened(0.2))
	frame_rect(ci, Rect2(d.position.x, d.get_center().y - h, d.size.x, d.size.y * 0.5 + h), _ol(), _px(OUTLINE_W))
	var top_c: Vector2 = Vector2(d.get_center().x, d.get_center().y - h)
	ci.draw_set_transform(top_c, 0.0, Vector2(1.0, 0.55))
	_circle(ci, Vector2.ZERO, d.size.x * 0.5, rust.lightened(0.1))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i: int in 3:
		var y: float = d.get_center().y - h + _px(10) + i * (h + d.size.y * 0.5 - _px(14)) / 3.0
		segment(ci, Vector2(d.position.x, y), Vector2(d.end.x, y), rust.darkened(0.45), _px(2))
	_circle(ci, Vector2(d.get_center().x, d.end.y - _px(10)), _px(5), C_PAPER)
	segment(ci, Vector2(d.get_center().x, d.end.y - _px(10)), Vector2(d.get_center().x + _px(3), d.end.y - _px(13)),
			C_RED_LED, _px(1.5))


func _draw_hvac_unit(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var top: Rect2 = _box(ci, d, height_of("hvac_unit"), Color("#b9c0c4"), Color("#8b9398"))
	var c: Vector2 = Vector2(top.position.x + top.size.y * 0.5 + _px(2), top.get_center().y)
	_circle(ci, c, top.size.y * 0.38, Color("#2b3035"))
	for k: int in 4:
		var ang: float = k * PI * 0.5 + 0.4
		segment(ci, c, c + Vector2(cos(ang), sin(ang)) * top.size.y * 0.34, C_METAL, _px(3))
	for i: int in 4:
		var x: float = top.get_center().x + _px(4) + i * _px(5)
		segment(ci, Vector2(x, top.position.y + _px(4)), Vector2(x, top.end.y - _px(4)), Color("#7d858a"), _px(1.5))


func _draw_crate(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 5.0)
	var wood: Color = Color("#b98b52")
	var top: Rect2 = _box(ci, d, height_of("crate"), wood, wood.darkened(0.25))
	segment(ci, top.position, top.end, wood.darkened(0.4), _px(2))
	segment(ci, Vector2(top.end.x, top.position.y), Vector2(top.position.x, top.end.y), wood.darkened(0.4), _px(2))
	frame_rect(ci, _inset(top, 3.0), wood.darkened(0.3), _px(1.5))


func _draw_pallet_stack(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	_box(ci, d, _px(5), C_WOOD.lightened(0.2))
	var boxes: Rect2 = _inset(d, 3.0)
	var h: float = height_of("pallet_stack")
	boxes.position.y -= _px(5)
	var top: Rect2 = _box(ci, boxes, h, C_CARDBOARD, C_CARDBOARD.darkened(0.2))
	segment(ci, Vector2(top.get_center().x, top.position.y), Vector2(top.get_center().x, top.end.y), Color("#d9c28f"), _px(3))
	segment(ci, Vector2(top.position.x, top.get_center().y), Vector2(top.end.x, top.get_center().y), C_CARDBOARD.darkened(0.3), _px(1))
	var front: Rect2 = _front(boxes, h)
	segment(ci, Vector2(front.position.x, front.get_center().y), Vector2(front.end.x, front.get_center().y),
			C_CARDBOARD.darkened(0.4), _px(1))


func _draw_dumpster(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var col: Color = Color("#3f7a4a")
	var top: Rect2 = _box(ci, d, height_of("dumpster"), col.lightened(0.05), col.darkened(0.25))
	segment(ci, Vector2(top.get_center().x, top.position.y), Vector2(top.get_center().x, top.end.y), _ol(), _px(1.5))
	ci.draw_rect(Rect2(top.position.x + _px(4), top.position.y + _px(3), top.size.x * 0.4, _px(4)), col.lightened(0.25))


func _draw_workbench(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var top: Rect2 = _box(ci, d, height_of("workbench"), C_WOOD.lightened(0.15), C_WOOD.darkened(0.3))
	_rect(ci, Rect2(top.position.x + _px(4), top.position.y + _px(4), _px(12), _px(10)), C_STEEL_DARK)
	segment(ci, top.get_center() + Vector2(-_px(8), _px(2)), top.get_center() + Vector2(_px(10), -_px(4)), C_METAL, _px(3))
	ci.draw_rect(Rect2(top.get_center().x + _px(8), top.get_center().y - _px(7), _px(6), _px(5)), Color("#c23b35"))
	_rect(ci, Rect2(top.end.x - _px(16), top.end.y - _px(12), _px(12), _px(8)), C_HAZARD)


func _draw_industrial_machine(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("industrial_machine")
	var body: Color = _c("furniture") if str(style.get("band", "")) == "factory" else Color("#e0761a")
	var top: Rect2 = _box(ci, d, h, body, body.darkened(0.3))
	_rect(ci, Rect2(top.position.x + _px(5), top.position.y + _px(5), top.size.x * 0.45, top.size.y * 0.45), Color("#2b3035"))
	_dot(ci, Vector2(top.end.x - _px(8), top.position.y + _px(8)), _px(3), C_GREEN_LED)
	var front: Rect2 = _front(d, h)
	var stripes: int = maxi(3, int(front.size.x / _px(8)))
	for i: int in stripes:
		var x: float = front.position.x + i * front.size.x / stripes
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, front.end.y), Vector2(x + front.size.x / stripes * 0.5, front.end.y),
				Vector2(x + front.size.x / stripes, front.end.y - _px(6)), Vector2(x + front.size.x / stripes * 0.5,
				front.end.y - _px(6))]), C_HAZARD if i % 2 == 0 else Color("#1b1b1b"))


func _draw_conveyor(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("conveyor")
	var top: Rect2 = _box(ci, d, h, Color("#2a2c2f"), Color("#4a4d52"))
	var vertical: bool = r.size.y > r.size.x
	var length: float = top.size.y if vertical else top.size.x
	var steps: int = int(length / _px(8))
	for i: int in steps:
		var t: float = i * _px(8)
		if vertical:
			segment(ci, Vector2(top.position.x + _px(2), top.position.y + t), Vector2(top.end.x - _px(2), top.position.y + t),
					Color("#3c3f44"), _px(1))
		else:
			segment(ci, Vector2(top.position.x + t, top.position.y + _px(2)), Vector2(top.position.x + t, top.end.y - _px(2)),
					Color("#3c3f44"), _px(1))
	var shift: float = fmod(anim_time * _px(CONVEYOR_SPEED), _px(40))
	for i: int in int(length / _px(40)):
		var t: float = _px(20) + i * _px(40) + shift
		if t > length - _px(10):
			continue
		var p: Vector2 = top.position + (Vector2(top.size.x * 0.5, t) if vertical else Vector2(t, top.size.y * 0.5))
		_rect(ci, Rect2(p - Vector2(_px(8), _px(6)), Vector2(_px(16), _px(12))), C_CARDBOARD)
	frame_rect(ci, top, C_HAZARD, _px(2))


func _draw_holding_cell(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var h: float = height_of("holding_cell")
	ci.draw_rect(d, _c("floor").darkened(0.15))
	_rect(ci, Rect2(d.position.x + _px(4), d.position.y + _px(6), d.size.x * 0.5, _px(12)), C_WOOD)
	var bars: int = int(d.size.x / _px(8))
	for i: int in bars + 1:
		var x: float = d.position.x + i * d.size.x / bars
		segment(ci, Vector2(x, d.end.y), Vector2(x, d.end.y - h), C_STEEL_DARK, _px(2))
	segment(ci, Vector2(d.position.x, d.end.y - h), Vector2(d.end.x, d.end.y - h), C_STEEL_DARK, _px(3))
	frame_rect(ci, d, C_STEEL_DARK, _px(3))


# ─── Especiales y exteriores ──────────────────────────────────

func _draw_car(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 5.0)
	var col: Color = _pick(C_CARS)
	var vertical: bool = d.size.y > d.size.x
	_shadow(ci, d)
	_poly(ci, _rounded(d, _px(12)), col)
	var glass: Color = Color("#1e2a36")
	var roof: Rect2 = _inset(d, 7.0)
	if vertical:
		roof = Rect2(d.position.x + _px(6), d.position.y + d.size.y * 0.3, d.size.x - _px(12), d.size.y * 0.42)
		_poly(ci, _rounded(Rect2(roof.position.x, roof.position.y - _px(12), roof.size.x, _px(14)), _px(4)), glass)
		_poly(ci, _rounded(Rect2(roof.position.x, roof.end.y - _px(3), roof.size.x, _px(12)), _px(4)), glass)
		_dot(ci, Vector2(d.position.x + _px(8), d.position.y + _px(5)), _px(3), Color("#fff4c8"))
		_dot(ci, Vector2(d.end.x - _px(8), d.position.y + _px(5)), _px(3), Color("#fff4c8"))
	else:
		roof = Rect2(d.position.x + d.size.x * 0.3, d.position.y + _px(6), d.size.x * 0.42, d.size.y - _px(12))
		_poly(ci, _rounded(Rect2(roof.end.x - _px(3), roof.position.y, _px(14), roof.size.y), _px(4)), glass)
		_poly(ci, _rounded(Rect2(roof.position.x - _px(11), roof.position.y, _px(12), roof.size.y), _px(4)), glass)
	_poly(ci, _rounded(roof, _px(6)), col.lightened(0.12))


func _draw_street_lamp(ci: CanvasItem, r: Rect2) -> void:
	var base: Vector2 = r.get_center() + Vector2(0, _px(10))
	var h: float = height_of("street_lamp")
	_dot(ci, base + Vector2(_px(2), _px(3)), _px(6), SHADOW)
	_circle(ci, base, _px(5), Color("#2b2f38"))
	segment(ci, base, base - Vector2(0, h), Color("#2b2f38"), _px(3.5))
	var head: Vector2 = base - Vector2(-_px(8), h)
	segment(ci, base - Vector2(0, h), head, Color("#2b2f38"), _px(3))
	_poly(ci, _rounded(Rect2(head - Vector2(_px(8), _px(4)), Vector2(_px(16), _px(8))), _px(3)), Color("#3a404c"))
	_dot(ci, head + Vector2(0, _px(2)), _px(4), Color("#ffe6a0"))


## Pedestal del torno (a la izquierda de su calle): acero pulido, lector y flecha verde. La aleta de
## cristal que abre y cierra la calle la dibuja la compuerta (Door de tipo "turnstile").
func _draw_turnstile(ci: CanvasItem, r: Rect2) -> void:
	var h: float = height_of("turnstile")
	var d: Rect2 = Rect2(r.position.x + _px(2), r.position.y + _px(6), _px(12), r.size.y - _px(10))
	var top: Rect2 = _box(ci, d, h, C_METAL.lightened(0.15), C_METAL.darkened(0.3))
	ci.draw_rect(Rect2(top.position.x + _px(2), top.position.y + _px(4), top.size.x - _px(4), _px(9)), C_SCREEN_DARK)
	ci.draw_rect(Rect2(top.position.x + _px(3.5), top.position.y + _px(5.5), top.size.x - _px(7), _px(6)), C_SCREEN)
	var arrow: Vector2 = Vector2(top.get_center().x, top.end.y - _px(9))
	ci.draw_colored_polygon(PackedVector2Array([arrow + Vector2(-_px(4), -_px(3)), arrow + Vector2(_px(4), -_px(3)),
			arrow + Vector2(0, _px(3))]), C_GREEN_LED)


## Barandilla de cristal (cierra la fila de tornos): postes de acero y panel translúcido.
func _draw_barrier(ci: CanvasItem, r: Rect2) -> void:
	var h: float = height_of("barrier")
	var d: Rect2 = Rect2(r.position.x, r.get_center().y - _px(3), r.size.x, _px(6))
	_shadow(ci, d)
	var glass: Rect2 = Rect2(d.position.x, d.position.y - h, d.size.x, h + d.size.y)
	ci.draw_rect(glass, Color(C_SCREEN.r, C_SCREEN.g, C_SCREEN.b, 0.45))
	segment(ci, glass.position + Vector2(_px(5), glass.size.y - _px(3)), glass.position + Vector2(_px(14), _px(3)),
			Color(1, 1, 1, 0.6), _px(2))
	frame_rect(ci, glass, _ol(), _px(1.5))
	segment(ci, glass.position, Vector2(glass.end.x, glass.position.y), C_METAL.lightened(0.2), _px(3))
	for x: float in [d.position.x + _px(2), d.end.x - _px(2)]:
		segment(ci, Vector2(x, d.end.y), Vector2(x, glass.position.y), C_STEEL_DARK, _px(3))


## Reloj de pared (colgado en la cara norte): esfera, agujas y marco.
func _draw_wall_clock(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = Vector2(r.get_center().x, r.position.y - _px(10))
	_circle(ci, c, _px(7), C_PAPER)
	segment(ci, c, c + Vector2(0, -_px(5.5)), Color("#1b1b1b"), _px(1.5))
	segment(ci, c, c + Vector2(_px(4), _px(1.5)), Color("#1b1b1b"), _px(1.5))
	_dot(ci, c, _px(1.4), C_RED_LED)


## Cuadro colgado (cara norte): marco (dorado en las bandas altas) y composición abstracta.
func _draw_wall_art(ci: CanvasItem, r: Rect2) -> void:
	var frame: Rect2 = Rect2(r.get_center().x - _px(15), r.position.y - _px(18), _px(30), _px(15))
	var gold: bool = str(style.get("band", "")) in ["the_power", "the_throne"]
	_rect(ci, frame, C_GOLD if gold else _c("furniture"))
	var canvas: Rect2 = _inset(frame, 2.5)
	ci.draw_rect(canvas, _c("window").lerp(_c("wall"), 0.3))
	ci.draw_rect(Rect2(canvas.position, Vector2(canvas.size.x * 0.45, canvas.size.y)), _c("accent").lerp(_c("floor"), 0.3))
	ci.draw_rect(Rect2(canvas.position + Vector2(canvas.size.x * 0.55, canvas.size.y * 0.35), canvas.size * Vector2(0.3, 0.45)),
			_pick(C_BOOKS))


## Extintor colgado (cara norte): cuerpo rojo, válvula negra y soporte.
func _draw_fire_extinguisher(ci: CanvasItem, r: Rect2) -> void:
	var ext: Rect2 = Rect2(r.get_center().x - _px(5), r.position.y - _px(17), _px(10), _px(15))
	_poly(ci, _rounded(ext, _px(4)), Color("#d33a2c"))
	ci.draw_rect(Rect2(ext.position.x + _px(2), ext.position.y - _px(3), ext.size.x - _px(4), _px(4)), Color("#1b1b1b"))
	segment(ci, ext.position + Vector2(_px(2), _px(5)), ext.position + Vector2(_px(2), ext.size.y - _px(4)),
			Color(1, 1, 1, 0.45), _px(1.5))


func _draw_statue(ci: CanvasItem, r: Rect2) -> void:
	var base: Rect2 = Rect2(r.get_center().x - _px(12), r.get_center().y - _px(4), _px(24), _px(18))
	var marble: Color = Color("#ece8e0")
	_box(ci, base, _px(10), marble, marble.darkened(0.2))
	var gold: bool = str(style.get("band", "")) in ["the_throne", "the_power"]
	var fig: Color = C_GOLD if gold else Color("#c9c4b8")
	var top: float = base.position.y - _px(10)
	_poly(ci, PackedVector2Array([Vector2(base.get_center().x - _px(7), top), Vector2(base.get_center().x + _px(7), top),
			Vector2(base.get_center().x + _px(3), top - _px(22)), Vector2(base.get_center().x - _px(4), top - _px(20))]), fig)
	_circle(ci, Vector2(base.get_center().x - _px(1), top - _px(26)), _px(5), fig)


func _draw_podium(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = Rect2(r.get_center().x - _px(12), r.get_center().y - _px(8), _px(24), _px(18))
	var top: Rect2 = _box(ci, d, height_of("podium"), C_WOOD.lightened(0.1), C_WOOD.darkened(0.25))
	ci.draw_rect(Rect2(d.get_center().x - _px(5), d.end.y - _px(12), _px(10), _px(8)), C_GOLD)
	segment(ci, top.get_center(), top.get_center() + Vector2(_px(4), -_px(10)), C_STEEL_DARK, _px(1.5))
	_dot(ci, top.get_center() + Vector2(_px(4), -_px(11)), _px(2.2), Color("#1b1b1b"))


func _draw_light_stand(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center() + Vector2(0, _px(8))
	var h: float = height_of("light_stand")
	for k: int in 3:
		var ang: float = PI * 0.5 + (k - 1) * 0.9
		segment(ci, c - Vector2(0, _px(6)), c + Vector2(cos(ang), sin(ang) * 0.4) * _px(12), C_STEEL_DARK, _px(2))
	segment(ci, c, c - Vector2(0, h), C_STEEL_DARK, _px(2))
	_rect(ci, Rect2(c.x - _px(9), c.y - h - _px(8), _px(18), _px(12)), Color("#2b2f36"))
	ci.draw_rect(Rect2(c.x - _px(7), c.y - h - _px(6), _px(14), _px(8)), Color("#fff6d8"))


func _draw_photo_backdrop(ci: CanvasItem, r: Rect2) -> void:
	var h: float = height_of("photo_backdrop")
	var d: Rect2 = _inset(r, 2.0)
	_shadow(ci, d)
	ci.draw_rect(Rect2(d.position.x, d.position.y - h, d.size.x, d.size.y + h + _px(10)), Color("#f7f7f5"))
	frame_rect(ci, Rect2(d.position.x, d.position.y - h, d.size.x, d.size.y + h + _px(10)), _ol(), _px(OUTLINE_W))
	_rect(ci, Rect2(d.position.x - _px(2), d.position.y - h - _px(5), d.size.x + _px(4), _px(6)), C_STEEL_DARK)


func _draw_mannequin(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center() + Vector2(0, _px(10))
	_dot(ci, c + Vector2(_px(2), _px(3)), _px(7), SHADOW)
	segment(ci, c, c - Vector2(0, _px(12)), C_STEEL_DARK, _px(2))
	_poly(ci, _rounded(Rect2(c.x - _px(8), c.y - _px(30), _px(16), _px(20)), _px(6)), _pick(C_CLOTHES))
	_circle(ci, c - Vector2(0, _px(34)), _px(5), Color("#e8dcc8"))


func _draw_clothes_rack(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var h: float = height_of("clothes_rack")
	var rail_y: float = d.get_center().y - h
	segment(ci, Vector2(d.position.x, d.get_center().y), Vector2(d.position.x, rail_y), C_STEEL_DARK, _px(2))
	segment(ci, Vector2(d.end.x, d.get_center().y), Vector2(d.end.x, rail_y), C_STEEL_DARK, _px(2))
	var count: int = int(d.size.x / _px(7))
	for i: int in count:
		var x: float = d.position.x + _px(4) + i * (d.size.x - _px(8)) / maxf(1.0, count - 1)
		_rect(ci, Rect2(x - _px(3), rail_y + _px(1), _px(6), h * 0.8), _pick(C_CLOTHES))
	segment(ci, Vector2(d.position.x, rail_y), Vector2(d.end.x, rail_y), C_METAL, _px(2.5))


## Piano de cola visto desde arriba: caja curva lacada, tapa abierta con su vara, teclado blanco
## y negro del lado del pianista (norte) y banqueta.
func _draw_piano(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("piano")
	var body: PackedVector2Array = _piano_outline(Rect2(d.position.x, d.position.y + _px(8) - h, d.size.x, d.size.y - _px(8)))
	var shadow: PackedVector2Array = _piano_outline(Rect2(d.position.x + _px(3), d.position.y + _px(12), d.size.x, d.size.y - _px(8)))
	ci.draw_colored_polygon(shadow, SHADOW)
	_poly(ci, body, Color("#18181b"))
	var lid: PackedVector2Array = _piano_outline(Rect2(d.position.x + _px(5), d.position.y + _px(14) - h,
			d.size.x - _px(10), d.size.y - _px(22)))
	_poly(ci, lid, Color("#2c2c31"))
	segment(ci, lid[0] + Vector2(_px(4), _px(4)), lid[lid.size() / 2], Color(1, 1, 1, 0.22), _px(2))
	segment(ci, Vector2(d.get_center().x, d.position.y + _px(14) - h), Vector2(d.get_center().x + _px(10),
			d.get_center().y - h), C_GOLD, _px(1.5))
	var keys: Rect2 = Rect2(d.position.x + _px(3), d.position.y + _px(2) - h, d.size.x - _px(6), _px(7))
	_rect(ci, keys, Color("#f7f7f2"))
	for i: int in int(keys.size.x / _px(6)):
		if i % 7 != 2 and i % 7 != 6:
			ci.draw_rect(Rect2(keys.position.x + _px(4) + i * _px(6), keys.position.y, _px(2.5), _px(4)), Color("#141416"))
	_rect(ci, Rect2(d.get_center().x - _px(12), d.position.y - _px(9), _px(24), _px(8)), Color("#2a1c16"))


## Contorno de la caja de un piano de cola dentro de `r` (recto al teclado, curvo al fondo).
func _piano_outline(r: Rect2) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for p: Vector2 in PIANO_SHAPE:
		pts.append(r.position + p * r.size)
	return pts


func _draw_mixing_desk(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var top: Rect2 = _box(ci, d, height_of("mixing_desk"), Color("#2b2f36"))
	var faders: int = int(top.size.x / _px(6))
	for i: int in faders:
		var x: float = top.position.x + _px(4) + i * _px(6)
		segment(ci, Vector2(x, top.position.y + _px(4)), Vector2(x, top.end.y - _px(4)), Color("#11141a"), _px(1.5))
		ci.draw_rect(Rect2(x - _px(1.5), top.position.y + _rng.randf_range(_px(4), top.size.y - _px(8)), _px(3), _px(3)),
				_pick([C_GREEN_LED, C_RED_LED, C_HAZARD]))


func _draw_foosball_table(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 4.0)
	var top: Rect2 = _box(ci, d, height_of("foosball_table"), C_WOOD)
	var pitch: Rect2 = _inset(top, 4.0)
	ci.draw_rect(pitch, Color("#3a9a4a"))
	for i: int in 4:
		var x: float = pitch.position.x + (i + 0.5) * pitch.size.x / 4.0
		segment(ci, Vector2(x, top.position.y - _px(3)), Vector2(x, top.end.y + _px(3)), C_METAL, _px(1.5))
		_dot(ci, Vector2(x, pitch.get_center().y), _px(2.5), C_RED_LED if i % 2 == 0 else Color("#4da3ff"))


func _draw_hot_tub(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var top: Rect2 = _box(ci, d, height_of("hot_tub"), Color("#b08a5e"))
	var water: Rect2 = _inset(top, 6.0)
	_poly(ci, _rounded(water, _px(14)), C_WATER)
	for i: int in 6:
		ci.draw_arc(water.position + Vector2(_rng.randf() * water.size.x, _rng.randf() * water.size.y), _px(2.5), 0.0, TAU,
				10, Color(1, 1, 1, 0.7), _px(1))


func _draw_sauna(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 3.0)
	var h: float = height_of("sauna")
	var wood: Color = Color("#c08850")
	var top: Rect2 = _box(ci, d, h, wood.darkened(0.1), wood)
	for i: int in int(top.size.y / _px(7)):
		segment(ci, Vector2(top.position.x, top.position.y + i * _px(7)), Vector2(top.end.x, top.position.y + i * _px(7)),
				wood.darkened(0.3), _px(1))
	var front: Rect2 = _front(d, h)
	_rect(ci, Rect2(front.get_center().x - _px(8), front.position.y + _px(2), _px(16), front.size.y - _px(2)), wood.darkened(0.2))
	ci.draw_rect(Rect2(front.get_center().x - _px(5), front.position.y + _px(5), _px(10), _px(7)), Color("#f2c46b"))


func _draw_rug(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	var band: String = str(style.get("band", ""))
	var base: Color = _c("accent").darkened(0.35) if band != "the_throne" else Color("#8f1e24")
	ci.draw_rect(d, base)
	frame_rect(ci, _inset(d, 6.0), _c("carpet").lerp(base, 0.35), _px(3))
	frame_rect(ci, _inset(d, 12.0), C_GOLD.lerp(base, 0.4), _px(1.5))
	frame_rect(ci, d, _ol().lerp(base, 0.5), _px(1))


func _draw_runway(ci: CanvasItem, r: Rect2) -> void:
	var d: Rect2 = _inset(r, 2.0)
	ci.draw_rect(Rect2(d.position + Vector2(_px(2), _px(4)), d.size), SHADOW)
	_rect(ci, d, Color("#f4f4f2"))
	for i: int in int(d.size.x / _px(24)):
		var x: float = d.position.x + _px(12) + i * _px(24)
		_dot(ci, Vector2(x, d.position.y + _px(3)), _px(2), Color("#fff2b0"))
		_dot(ci, Vector2(x, d.end.y - _px(3)), _px(2), Color("#fff2b0"))


func _draw_helipad(ci: CanvasItem, r: Rect2) -> void:
	var c: Vector2 = r.get_center()
	var rad: float = minf(r.size.x, r.size.y) * 0.48
	_dot(ci, c, rad, Color("#3a3f47"))
	ci.draw_arc(c, rad - _px(6), 0.0, TAU, 48, C_HAZARD, _px(5))
	ci.draw_arc(c, rad, 0.0, TAU, 48, _ol(), _px(2))
	var s: float = rad * 0.4
	for x: float in [-s * 0.6, s * 0.6]:
		segment(ci, c + Vector2(x, -s), c + Vector2(x, s), Color("#f4f4f2"), _px(8))
	segment(ci, c + Vector2(-s * 0.6, 0), c + Vector2(s * 0.6, 0), Color("#f4f4f2"), _px(8))


func _draw_window_wall(ci: CanvasItem, r: Rect2) -> void:
	var horizontal: bool = r.size.x >= r.size.y
	var glass: Rect2 = Rect2(r.position.x, r.position.y, r.size.x, _px(8)) if horizontal \
			else Rect2(r.position.x, r.position.y, _px(8), r.size.y)
	ci.draw_rect(glass, _c("window").lightened(0.2))
	frame_rect(ci, glass, _c("accent"), _px(2))
	var panes: int = maxi(1, int((r.size.x if horizontal else r.size.y) / _px(48)))
	for i: int in panes:
		var t: float = i * (r.size.x if horizontal else r.size.y) / panes
		var a: Vector2 = glass.position + (Vector2(t, 0) if horizontal else Vector2(0, t))
		segment(ci, a, a + (Vector2(0, glass.size.y) if horizontal else Vector2(glass.size.x, 0)), _c("accent"), _px(2))


## Cortinas: pliegues verticales colgados del muro más cercano (escondite).
func _draw_curtain(ci: CanvasItem, r: Rect2) -> void:
	var col: Color = Color("#8f1e24") if str(style.get("band", "")) in ["the_throne", "the_power"] else Color("#5a6f8a")
	var folds: int = 4
	var d: Rect2 = Rect2(r.position.x + _px(4), r.position.y - _px(10), r.size.x - _px(8), r.size.y + _px(6))
	_shadow(ci, d)
	for i: int in folds:
		var f: Rect2 = Rect2(d.position.x + i * d.size.x / folds, d.position.y, d.size.x / folds, d.size.y)
		ci.draw_rect(f, col if i % 2 == 0 else col.darkened(0.2))
	frame_rect(ci, d, _ol(), _px(OUTLINE_W))
	segment(ci, d.position, Vector2(d.end.x, d.position.y), C_GOLD, _px(3))


func _draw_generic(ci: CanvasItem, r: Rect2) -> void:
	_box(ci, _inset(r, 4.0), float(UNKNOWN_SPEC[1]) * scale, _c("furniture"))
