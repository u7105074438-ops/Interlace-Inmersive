# tower_art.gd — Corte vertical de la torre de Stellar Sell (§14.1): 20 plantas, PB, azotea, 3 sótanos y nave.
# PROPIETARIO DE: nada (dibujo puro; lee las paletas de art_bands.json a través de MenuKit).
# ESCUCHA: nada.
class_name TowerArt
extends Control

## Uso: añadir como hijo, ajustar tamaño/anclas y propiedades públicas. Todo se dibuja en _draw().
## floor_rect(f) da el rectángulo local de una planta para colocar otros elementos encima.
## Plantas: S3..S1 = -3..-1, PB = 0, P1..P20 = 1..20, azotea = 21, nave = FACTORY (mundo.planta_fabrica).

const TOP_FLOOR := 20
const ROOF := 21
const LOWEST := -3
const NO_FLOOR := -99
## Proporciones del dibujo en «unidades de planta» (maquetación del arte, no tunables).
const ANTENNA_UNITS := 1.7
const ROOF_UNITS := 0.7
const EARTH_UNITS := 0.6
const FACTORY_ROWS := 3.0
const FACTORY_UNITS := 7.0
const SHAFT_UNITS := 0.8
const LABEL_UNITS := 2.2
const BAND_LABEL_UNITS := 4.2
const WIDTH_BY_BAND: Dictionary = {
	"the_guts": 9.0, "the_pit": 8.0, "the_specialists": 8.0, "the_power": 7.2, "the_throne": 6.2,
}
const PEOPLE_BY_DENSITY: Dictionary = {
	"very_low": 1, "low": 1, "medium": 2, "high": 3, "very_high": 5,
}

@export var show_labels: bool = false
@export var show_band_names: bool = false
@export var show_factory: bool = true
@export var show_people: bool = true
@export var show_sign: bool = true
@export var show_ground: bool = true
@export var animate: bool = true
## 0 = grupo pegado a la izquierda del control, 1 = a la derecha.
@export var anchor_x: float = 0.5

var highlight_floor: int = NO_FLOOR
var figure_visible: bool = false
## Planta continua de la figura: la parte fraccionaria es el tramo de escalera hacia la siguiente.
var figure_floor: float = 0.0
## Posición horizontal (0..1) dentro de la planta cuando no está en la escalera.
var figure_x: float = 0.3
var figure_looking_up: bool = false
var elevator_visible: bool = true
var elevator_floor: float = 0.0
## Tinte superpuesto a la torre (alfa = intensidad).
var tint: Color = Color(0, 0, 0, 0)
## Niebla 0..1 (apertura, segundo movimiento).
var mist: float = 0.0
var mist_color: Color = Color(0, 0, 0, 0)
## Proporción de ventanas encendidas (noche) 0..1.
var lit_ratio: float = 0.7

var _time: float = 0.0
var _unit: float = 10.0
var _cx: float = 0.0
var _ground: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if mist_color.a <= 0.0:
		mist_color = MenuKit.color("paper_dim")


func _process(delta: float) -> void:
	if animate and is_visible_in_tree():
		_time += delta
		queue_redraw()


# ─── API ───────────────────────────────────────────────────────

## Rectángulo local de una planta (interior del corte). Rect2() si la planta no existe.
func floor_rect(floor_number: int) -> Rect2:
	_compute_layout()
	if floor_number == factory_floor():
		var fx: float = _cx + _band_width("the_pit") * 0.5
		return Rect2(fx, _ground - FACTORY_ROWS * _unit, FACTORY_UNITS * _unit, FACTORY_ROWS * _unit)
	if floor_number == ROOF:
		var rw: float = (_band_width("the_throne") - 1.2) * _unit
		return Rect2(_cx - rw * 0.5, _ground - (TOP_FLOOR + 1 + ROOF_UNITS) * _unit, rw, ROOF_UNITS * _unit)
	if floor_number < LOWEST or floor_number > TOP_FLOOR:
		return Rect2()
	var w: float = _band_width(str(MenuKit.band_for_floor(floor_number).get("id", ""))) * _unit
	var top: float = _ground - (floor_number + 1) * _unit
	if floor_number < 0:
		top = _ground + (-floor_number - 1) * _unit
	return Rect2(_cx - w * 0.5, top, w, _unit)


## Altura del suelo de la calle en coordenadas locales.
func ground_y() -> float:
	_compute_layout()
	return _ground


## Tamaño de una planta en píxeles (la «unidad» del dibujo).
func unit_px() -> float:
	_compute_layout()
	return _unit


## Posición de los pies de la figura (coordenadas locales).
func figure_position() -> Vector2:
	var base: int = floori(figure_floor)
	var frac: float = figure_floor - base
	var r: Rect2 = floor_rect(base)
	var feet_y: float = r.end.y - _unit * 0.14
	if frac <= 0.001 or base >= TOP_FLOOR:
		return Vector2(lerpf(r.position.x + _unit * 1.3, r.end.x - _unit * 1.3, figure_x), feet_y)
	var stair_x0: float = r.end.x - _unit * (SHAFT_UNITS + 0.9)
	var stair_x1: float = r.end.x - _unit * 0.35
	return Vector2(lerpf(stair_x0, stair_x1, frac), feet_y - _unit * frac)


## Progreso de escalada continuo (0 = PB). Camina por la planta y sube la escalera de servicio.
func set_climb_progress(progress: float, walk_share: float = 0.7) -> void:
	var base: int = clampi(floori(progress), 0, TOP_FLOOR)
	var frac: float = progress - floori(progress)
	figure_visible = true
	if base >= TOP_FLOOR:
		figure_floor = TOP_FLOOR
		figure_x = 0.5
	elif frac < walk_share:
		figure_floor = base
		figure_x = frac / walk_share
	else:
		figure_floor = base + (frac - walk_share) / (1.0 - walk_share)
		figure_x = 1.0
	queue_redraw()


static func factory_floor() -> int:
	var value: int = MenuKit.bal_int("mundo.planta_fabrica")
	return value if value != 0 else TOP_FLOOR * 5


# ─── Maquetación ───────────────────────────────────────────────

func _compute_layout() -> void:
	var left_units: float = WIDTH_BY_BAND["the_guts"] * 0.5 + (LABEL_UNITS if show_labels else 0.0)
	var right_units: float = WIDTH_BY_BAND["the_pit"] * 0.5
	right_units += FACTORY_UNITS if show_factory else WIDTH_BY_BAND["the_guts"] * 0.5
	if show_band_names:
		right_units = maxf(right_units, WIDTH_BY_BAND["the_pit"] * 0.5 + BAND_LABEL_UNITS)
	var total_h: float = ANTENNA_UNITS + ROOF_UNITS + (TOP_FLOOR + 1) - LOWEST + EARTH_UNITS
	_unit = maxf(1.0, minf(size.y / total_h, size.x / (left_units + right_units)))
	var group_w: float = (left_units + right_units) * _unit
	_cx = (size.x - group_w) * anchor_x + left_units * _unit
	_ground = size.y - (-LOWEST + EARTH_UNITS) * _unit


func _band_width(band_id: String) -> float:
	return float(WIDTH_BY_BAND.get(band_id, WIDTH_BY_BAND["the_pit"]))


# ─── Dibujo ────────────────────────────────────────────────────

func _draw() -> void:
	_compute_layout()
	if show_ground:
		_draw_ground()
	if show_factory:
		_draw_factory(floor_rect(factory_floor()))
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		_draw_floor(f, floor_rect(f))
	_draw_band_seams()
	_draw_roof(floor_rect(ROOF))
	_draw_shell()
	if elevator_visible:
		_draw_elevator_car()
	_draw_highlight()
	if figure_visible:
		_draw_figure()
	if show_labels:
		_draw_floor_labels()
	if show_band_names:
		_draw_band_names()
	_draw_mist()
	_draw_tint()


func _lw() -> float:
	return maxf(1.5, _unit * 0.07)


func _draw_ground() -> void:
	var guts: Dictionary = MenuKit.band_palette("the_guts")
	var street: Dictionary = MenuKit.band_palette("exterior")
	draw_rect(Rect2(0, _ground, size.x, size.y - _ground), guts.get("shadow", Color.BLACK))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("tower_earth")
	var pebble: Color = guts.get("carpet", Color.DIM_GRAY)
	for i: int in 60:
		var p: Vector2 = Vector2(rng.randf() * size.x, _ground + _unit * 0.6 + rng.randf() * (size.y - _ground))
		draw_circle(p, _unit * rng.randf_range(0.04, 0.12), pebble)
	var road_h: float = _unit * 0.32
	draw_rect(Rect2(0, _ground - road_h * 0.25, size.x, road_h), street.get("floor", Color.DIM_GRAY))
	draw_line(Vector2(0, _ground - road_h * 0.25), Vector2(size.x, _ground - road_h * 0.25),
			street.get("outline", Color.BLACK), _lw())
	var dash: float = _unit * 0.8
	var x: float = 0.0
	while x < size.x:
		draw_line(Vector2(x, _ground + road_h * 0.3), Vector2(x + dash * 0.5, _ground + road_h * 0.3),
				street.get("accent", Color.YELLOW), maxf(1.0, _unit * 0.05))
		x += dash


func _draw_floor(f: int, r: Rect2) -> void:
	var band: Dictionary = MenuKit.band_for_floor(f)
	var pal: Dictionary = band.get("colors", {})
	draw_rect(r, pal.get("wall", Color.GRAY))
	if f >= 0:
		_draw_windows(f, r, pal)
	else:
		_draw_pipes(r, pal)
	var carpet_h: float = r.size.y * 0.2
	draw_rect(Rect2(r.position.x, r.end.y - carpet_h, r.size.x, carpet_h), pal.get("carpet", Color.GRAY))
	_draw_furniture(f, r, band)
	_draw_shaft_and_stairs(r, pal)
	draw_rect(Rect2(r.position.x, r.end.y - _lw() * 1.5, r.size.x, _lw() * 1.5), pal.get("outline", Color.BLACK))
	draw_rect(r, pal.get("outline", Color.BLACK), false, _lw())


func _draw_windows(f: int, r: Rect2, pal: Dictionary) -> void:
	var inner_l: float = r.position.x + _unit * (SHAFT_UNITS + 0.5)
	var inner_r: float = r.end.x - _unit * (SHAFT_UNITS + 1.2)
	var count: int = maxi(2, floori((inner_r - inner_l) / (_unit * 1.15)))
	var step: float = (inner_r - inner_l) / count
	var tall: bool = str(MenuKit.band_for_floor(f).get("id", "")) == "the_throne"
	var top: float = r.position.y + r.size.y * (0.12 if tall else 0.2)
	var h: float = r.size.y * (0.5 if tall else 0.36)
	var flicker: bool = bool((MenuKit.band_for_floor(f).get("lighting", {}) as Dictionary).get("flicker", false))
	for i: int in count:
		var wr: Rect2 = Rect2(inner_l + i * step + step * 0.12, top, step * 0.76, h)
		var lit: bool = _hash01(f * 31 + i) < lit_ratio
		var glow: Color = pal.get("light", Color.WHITE) if lit else pal.get("window", Color.GRAY)
		if lit and flicker and _hash01(f * 7 + i + floori(_time * 3.0)) < 0.04:
			glow = pal.get("window", Color.GRAY)
		draw_rect(wr, glow)
		draw_line(wr.position + Vector2(wr.size.x * 0.2, wr.size.y * 0.8),
				wr.position + Vector2(wr.size.x * 0.55, wr.size.y * 0.2), Color(1, 1, 1, 0.35), maxf(1.0, _lw() * 0.6))
		draw_rect(wr, pal.get("outline", Color.BLACK), false, maxf(1.0, _lw() * 0.6))


func _draw_pipes(r: Rect2, pal: Dictionary) -> void:
	var y: float = r.position.y + r.size.y * 0.18
	draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), pal.get("furniture", Color.BROWN), _unit * 0.12)
	draw_line(Vector2(r.position.x, y + _unit * 0.16), Vector2(r.end.x, y + _unit * 0.16),
			pal.get("accent", Color.GREEN), _unit * 0.06)
	var lamp_count: int = 3
	for i: int in lamp_count:
		var lx: float = lerpf(r.position.x + _unit * 1.6, r.end.x - _unit * 1.8, float(i) / (lamp_count - 1))
		var cone: PackedVector2Array = [
			Vector2(lx - _unit * 0.1, y + _unit * 0.2), Vector2(lx + _unit * 0.1, y + _unit * 0.2),
			Vector2(lx + _unit * 0.55, r.end.y - r.size.y * 0.2), Vector2(lx - _unit * 0.55, r.end.y - r.size.y * 0.2),
		]
		var beam: Color = pal.get("light", Color.WHITE)
		beam.a = 0.22
		draw_colored_polygon(cone, beam)
		draw_circle(Vector2(lx, y + _unit * 0.2), _unit * 0.08, pal.get("light", Color.WHITE))


func _draw_furniture(f: int, r: Rect2, band: Dictionary) -> void:
	var pal: Dictionary = band.get("colors", {})
	var band_id: String = str(band.get("id", ""))
	var floor_y: float = r.end.y - r.size.y * 0.2
	var inner_l: float = r.position.x + _unit * (SHAFT_UNITS + 0.45)
	var inner_r: float = r.end.x - _unit * (SHAFT_UNITS + 1.0)
	var desks: int = {"the_guts": 2, "the_pit": 4, "the_specialists": 3, "the_power": 2, "the_throne": 1}.get(band_id, 2)
	if f == 0:
		desks = 1
	for i: int in desks:
		var x: float = lerpf(inner_l, inner_r, (i + 0.5) / desks)
		_draw_desk(Vector2(x, floor_y), band_id, pal, f)
	if show_people:
		_draw_people(f, r, floor_y, inner_l, inner_r, band)
	if f == 0:
		_draw_turnstiles(Vector2(lerpf(inner_l, inner_r, 0.8), floor_y), pal)


func _draw_desk(base: Vector2, band_id: String, pal: Dictionary, f: int) -> void:
	var ink: Color = pal.get("outline", Color.BLACK)
	var w: float = _unit * (1.3 if band_id == "the_throne" else 0.95)
	var h: float = _unit * 0.3
	if band_id == "the_guts":
		var crate: Rect2 = Rect2(base.x - _unit * 0.35, base.y - _unit * 0.42, _unit * 0.7, _unit * 0.42)
		draw_rect(crate, pal.get("furniture", Color.BROWN))
		draw_rect(crate, ink, false, maxf(1.0, _lw() * 0.7))
		return
	var top: Rect2 = Rect2(base.x - w * 0.5, base.y - h, w, _unit * 0.08)
	draw_rect(Rect2(base.x - w * 0.42, base.y - h, _unit * 0.06, h), ink)
	draw_rect(Rect2(base.x + w * 0.42 - _unit * 0.06, base.y - h, _unit * 0.06, h), ink)
	draw_rect(top, pal.get("furniture", Color.BEIGE))
	draw_rect(top, ink, false, maxf(1.0, _lw() * 0.6))
	var screen: Rect2 = Rect2(base.x - _unit * 0.18, base.y - h - _unit * 0.26, _unit * 0.36, _unit * 0.24)
	if band_id == "the_throne":
		draw_circle(Vector2(base.x + w * 0.62, base.y - _unit * 0.28), _unit * 0.2, MenuKit.band_palette("the_pit").get("accent", Color.GREEN))
		return
	draw_rect(screen, ink)
	draw_rect(screen.grow(-_unit * 0.04), pal.get("accent", Color.BLUE) if f % 2 == 0 else pal.get("window", Color.GRAY))


func _draw_people(f: int, r: Rect2, floor_y: float, inner_l: float, inner_r: float, band: Dictionary) -> void:
	var count: int = int(PEOPLE_BY_DENSITY.get(str(band.get("occupancy_density", "medium")), 2))
	var pal: Dictionary = band.get("colors", {})
	for i: int in count:
		var t: float = _hash01(f * 53 + i * 11)
		var sway: float = sin(_time * 0.6 + f + i) * _unit * 0.12 if animate else 0.0
		var x: float = lerpf(inner_l, inner_r, t) + sway
		MenuKit.draw_person(self, Vector2(x, floor_y), _unit * 0.55, pal.get("shadow", Color.DIM_GRAY),
				pal.get("shadow", Color.DIM_GRAY).lightened(0.15), pal.get("outline", Color.BLACK))


func _draw_turnstiles(base: Vector2, pal: Dictionary) -> void:
	for i: int in 3:
		var x: float = base.x + (i - 1) * _unit * 0.42
		draw_rect(Rect2(x - _unit * 0.08, base.y - _unit * 0.36, _unit * 0.16, _unit * 0.36), pal.get("outline", Color.BLACK))
		draw_line(Vector2(x, base.y - _unit * 0.3), Vector2(x + _unit * 0.2, base.y - _unit * 0.3),
				MenuKit.band_palette("exterior").get("accent", Color.YELLOW), maxf(1.0, _lw()))


func _draw_shaft_and_stairs(r: Rect2, pal: Dictionary) -> void:
	var shaft: Rect2 = Rect2(r.position.x + _unit * 0.15, r.position.y, _unit * SHAFT_UNITS, r.size.y)
	draw_rect(shaft, pal.get("shadow", Color.DIM_GRAY))
	var rail: Color = pal.get("outline", Color.BLACK)
	draw_line(shaft.position + Vector2(shaft.size.x * 0.5, 0), Vector2(shaft.get_center().x, shaft.end.y), rail, maxf(1.0, _lw() * 0.5))
	var sx0: float = r.end.x - _unit * (SHAFT_UNITS + 0.9)
	var sx1: float = r.end.x - _unit * 0.35
	var steps: int = 5
	var pts: PackedVector2Array = []
	for i: int in steps + 1:
		var t: float = float(i) / steps
		pts.append(Vector2(lerpf(sx0, sx1, t), r.end.y - r.size.y * 0.2 - (r.size.y * 0.8) * t))
	draw_polyline(pts, pal.get("furniture", Color.BEIGE).darkened(0.35), maxf(2.0, _unit * 0.1))
	draw_polyline(pts, rail, maxf(1.0, _lw() * 0.5))


func _draw_band_seams() -> void:
	var previous: String = ""
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		var band: Dictionary = MenuKit.band_for_floor(f)
		var band_id: String = str(band.get("id", ""))
		if not previous.is_empty() and band_id != previous:
			var r: Rect2 = floor_rect(f)
			var accent: Color = (band.get("colors", {}) as Dictionary).get("accent", Color.WHITE)
			var seam: Rect2 = Rect2(r.position.x - _unit * 0.25, r.end.y - _unit * 0.1, r.size.x + _unit * 0.5, _unit * 0.2)
			draw_rect(seam, accent)
			draw_rect(seam, MenuKit.color("ink"), false, _lw())
		previous = band_id


func _draw_roof(r: Rect2) -> void:
	var pal: Dictionary = MenuKit.band_palette("the_throne")
	var ink: Color = pal.get("outline", Color.BLACK)
	draw_rect(r, pal.get("wall", Color.WHITE))
	draw_rect(r, ink, false, _lw())
	var pad_c: Vector2 = Vector2(r.position.x + r.size.x * 0.3, r.position.y - _unit * 0.05)
	draw_line(pad_c + Vector2(-_unit * 0.7, 0), pad_c + Vector2(_unit * 0.7, 0), ink, _unit * 0.12)
	var mast_x: float = r.end.x - r.size.x * 0.22
	var mast_top: Vector2 = Vector2(mast_x, r.position.y - _unit * ANTENNA_UNITS * 0.95)
	draw_line(Vector2(mast_x, r.position.y), mast_top, ink, maxf(2.0, _unit * 0.1))
	draw_line(Vector2(mast_x - _unit * 0.3, r.position.y - _unit * 0.6), Vector2(mast_x + _unit * 0.3, r.position.y - _unit * 0.6), ink, _lw())
	var blink: float = MenuKit.bal_float("menus.titulo.parpadeo_antena_segundos")
	var on: bool = blink <= 0.0 or fmod(_time, blink) < blink * 0.5
	var beacon: Color = MenuKit.axis_color("blood")
	draw_circle(mast_top, _unit * 0.16, beacon if on else beacon.darkened(0.6))
	draw_arc(mast_top, _unit * 0.16, 0.0, TAU, 16, ink, maxf(1.0, _lw() * 0.6))
	if show_sign:
		_draw_sign(Rect2(r.position.x + r.size.x * 0.02, r.position.y - _unit * 1.05, r.size.x * 0.6, _unit * 0.8))


func _draw_sign(r: Rect2) -> void:
	var ink: Color = MenuKit.color("ink")
	draw_rect(Rect2(r.position.x + r.size.x * 0.2, r.end.y, _unit * 0.08, _unit * 0.25), ink)
	draw_rect(Rect2(r.end.x - r.size.x * 0.2, r.end.y, _unit * 0.08, _unit * 0.25), ink)
	draw_rect(r, MenuKit.color("night"))
	draw_rect(r, ink, false, _lw())
	var star_c: Vector2 = Vector2(r.position.x + r.size.y * 0.5, r.get_center().y)
	draw_colored_polygon(_star(star_c, r.size.y * 0.34, r.size.y * 0.15), MenuKit.color("amber"))
	var text: String = tr("UI_COMPANY_NAME")
	var fsize: int = maxi(8, roundi(r.size.y * 0.5))
	var f: Font = MenuKit.font("bold")
	var avail: float = r.size.x - r.size.y * 1.1
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	if tw > avail and tw > 0.0:
		fsize = maxi(6, floori(fsize * avail / tw))
	draw_string(f, Vector2(r.position.x + r.size.y * 0.95, r.get_center().y + fsize * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, avail, fsize, MenuKit.color("lamp"))


func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i: int in 10:
		var a: float = -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


func _draw_factory(r: Rect2) -> void:
	var pal: Dictionary = MenuKit.band_palette("factory")
	var ink: Color = pal.get("outline", Color.BLACK)
	var teeth: int = 4
	var tooth_w: float = r.size.x / teeth
	var roof: PackedVector2Array = [Vector2(r.position.x, r.position.y)]
	for i: int in teeth:
		roof.append(Vector2(r.position.x + i * tooth_w, r.position.y - _unit * 0.7))
		roof.append(Vector2(r.position.x + (i + 1) * tooth_w, r.position.y))
	draw_colored_polygon(roof, pal.get("wall", Color.GRAY))
	for i: int in teeth:
		var glass: PackedVector2Array = [Vector2(r.position.x + i * tooth_w, r.position.y - _unit * 0.7),
			Vector2(r.position.x + i * tooth_w + _unit * 0.18, r.position.y - _unit * 0.62),
			Vector2(r.position.x + i * tooth_w + _unit * 0.18, r.position.y), Vector2(r.position.x + i * tooth_w, r.position.y)]
		draw_colored_polygon(glass, pal.get("window", Color.GRAY))
	draw_polyline(roof, ink, _lw())
	_draw_chimney(r, pal)
	draw_rect(r, pal.get("wall", Color.GRAY))
	draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.12, r.size.x, r.size.y * 0.12), pal.get("carpet", Color.DIM_GRAY))
	_draw_machines(r, pal)
	draw_rect(r, ink, false, _lw())


func _draw_chimney(r: Rect2, pal: Dictionary) -> void:
	var ink: Color = pal.get("outline", Color.BLACK)
	var ch: Rect2 = Rect2(r.end.x - _unit * 1.2, r.position.y - _unit * 2.2, _unit * 0.55, _unit * 2.2)
	draw_rect(ch, pal.get("shadow", Color.DIM_GRAY))
	draw_rect(Rect2(ch.position.x, ch.position.y + _unit * 0.3, ch.size.x, _unit * 0.18), pal.get("accent", Color.ORANGE))
	draw_rect(ch, ink, false, _lw())
	for i: int in 3:
		var t: float = fmod(_time * 0.25 + i / 3.0, 1.0)
		var p: Vector2 = Vector2(ch.get_center().x + t * _unit * 0.9, ch.position.y - t * _unit * 1.6)
		var puff: Color = pal.get("wall", Color.GRAY).lightened(0.3)
		puff.a = 0.8 * (1.0 - t)
		draw_circle(p, _unit * (0.18 + t * 0.35), puff)


func _draw_machines(r: Rect2, pal: Dictionary) -> void:
	var ink: Color = pal.get("outline", Color.BLACK)
	var belt_y: float = r.end.y - r.size.y * 0.32
	draw_line(Vector2(r.position.x + _unit * 0.4, belt_y), Vector2(r.end.x - _unit * 0.4, belt_y), ink, _unit * 0.12)
	var shift: float = fmod(_time * _unit * 0.6, _unit * 1.2)
	var x: float = r.position.x + _unit * 0.6 + shift
	while x < r.end.x - _unit * 0.8:
		var box_r: Rect2 = Rect2(x, belt_y - _unit * 0.32, _unit * 0.4, _unit * 0.3)
		draw_rect(box_r, pal.get("light", Color.WHEAT))
		draw_rect(box_r, ink, false, maxf(1.0, _lw() * 0.6))
		x += _unit * 1.2
	for i: int in 2:
		var m: Rect2 = Rect2(r.position.x + r.size.x * (0.18 + i * 0.5), r.position.y + r.size.y * 0.18, _unit * 1.3, _unit * 1.0)
		draw_rect(m, pal.get("furniture", Color.ORANGE))
		draw_rect(Rect2(m.position.x + _unit * 0.2, m.position.y + _unit * 0.2, _unit * 0.5, _unit * 0.3), pal.get("accent", Color.ORANGE).darkened(0.3))
		draw_rect(m, ink, false, _lw())


func _draw_shell() -> void:
	var ink: Color = MenuKit.color("ink")
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		var r: Rect2 = floor_rect(f)
		draw_line(r.position, Vector2(r.position.x, r.end.y), ink, _lw() * 2.0)
		draw_line(Vector2(r.end.x, r.position.y), r.end, ink, _lw() * 2.0)
	var top: Rect2 = floor_rect(TOP_FLOOR)
	draw_line(top.position, Vector2(top.end.x, top.position.y), ink, _lw() * 2.0)


func _draw_elevator_car() -> void:
	var base: int = clampi(floori(elevator_floor), LOWEST, TOP_FLOOR)
	var r: Rect2 = floor_rect(base)
	var y: float = r.position.y - (elevator_floor - base) * _unit
	var car: Rect2 = Rect2(r.position.x + _unit * 0.2, y + _unit * 0.12, _unit * (SHAFT_UNITS - 0.1), _unit * 0.8)
	draw_rect(car, MenuKit.color("gold"))
	draw_rect(Rect2(car.position.x + car.size.x * 0.2, car.position.y + car.size.y * 0.2, car.size.x * 0.6, car.size.y * 0.35), MenuKit.color("lamp"))
	draw_rect(car, MenuKit.color("ink"), false, _lw())


func _draw_highlight() -> void:
	if highlight_floor == NO_FLOOR:
		return
	var r: Rect2 = floor_rect(highlight_floor)
	if r.size == Vector2.ZERO:
		return
	var amber: Color = MenuKit.color("amber")
	draw_rect(r.grow(_unit * 0.08), amber, false, _lw() * 2.2)
	var tip: Vector2 = Vector2(r.position.x - _unit * 0.25, r.get_center().y)
	var arrow: PackedVector2Array = [tip, tip + Vector2(-_unit * 0.6, -_unit * 0.35), tip + Vector2(-_unit * 0.6, _unit * 0.35)]
	draw_colored_polygon(arrow, amber)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), MenuKit.color("ink"), _lw())


func _draw_figure() -> void:
	var feet: Vector2 = figure_position()
	var h: float = _unit * 0.72
	var halo: Color = MenuKit.color("amber")
	halo.a = 0.28 + 0.12 * sin(_time * 4.0)
	draw_circle(feet - Vector2(0, h * 0.5), h * 0.62, halo)
	MenuKit.draw_person(self, feet, h, MenuKit.color("amber"), MenuKit.color("paper"), MenuKit.color("ink"), figure_looking_up)


func _draw_floor_labels() -> void:
	var f_font: Font = MenuKit.font("bold")
	var fsize: int = maxi(8, roundi(_unit * 0.46))
	var x: float = _cx - _band_width("the_guts") * 0.5 * _unit - _unit * 0.3
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		var r: Rect2 = floor_rect(f)
		var text: String = floor_label(f)
		var tw: float = f_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var color_f: Color = MenuKit.color("amber") if f == highlight_floor else MenuKit.color("paper")
		draw_string_outline(f_font, Vector2(x - tw, r.get_center().y + fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(2, fsize / 5), MenuKit.color("ink"))
		draw_string(f_font, Vector2(x - tw, r.get_center().y + fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color_f)


## Etiqueta corta de una planta: "20", "PB"/"G", "S1"/"B1".
static func floor_label(f: int) -> String:
	if f == 0:
		return TranslationServer.translate("UI_TOWER_GROUND_SHORT")
	if f < 0:
		return TranslationServer.translate("UI_TOWER_BASEMENT_SHORT").format({"n": -f})
	return str(f)


func _draw_band_names() -> void:
	var f_font: Font = MenuKit.font("bold")
	var fsize: int = maxi(8, roundi(_unit * 0.42))
	var seen: Dictionary = {}
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		var band: Dictionary = MenuKit.band_for_floor(f)
		var band_id: String = str(band.get("id", ""))
		if seen.has(band_id):
			continue
		seen[band_id] = true
		var floors: Array = band.get("floors", [])
		var lo: Rect2 = floor_rect(clampi(int(floors.min()), LOWEST, TOP_FLOOR))
		var hi: Rect2 = floor_rect(clampi(int(floors.max()), LOWEST, TOP_FLOOR))
		var x: float = _cx + WIDTH_BY_BAND["the_pit"] * 0.5 * _unit + _unit * 0.35
		var accent: Color = (band.get("colors", {}) as Dictionary).get("accent", Color.WHITE)
		draw_line(Vector2(x, hi.position.y + _unit * 0.1), Vector2(x, lo.end.y - _unit * 0.1), accent, _lw() * 1.6)
		var text: String = tr(str(band.get("name_key", ""))).to_upper()
		var pos: Vector2 = Vector2(x + _unit * 0.3, (hi.position.y + lo.end.y) * 0.5 + fsize * 0.35)
		draw_string_outline(f_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(2, fsize / 5), MenuKit.color("ink"))
		draw_string(f_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, accent.lightened(0.25))


func _draw_mist() -> void:
	if mist <= 0.0:
		return
	var layers: int = 6
	for i: int in layers:
		var y: float = size.y * (0.25 + 0.13 * i) + sin(_time * 0.3 + i) * _unit * 0.6
		var h: float = size.y * 0.22
		var c: Color = mist_color
		c.a = clampf(mist * (0.35 + 0.1 * i), 0.0, 1.0)
		var clear: Color = c
		clear.a = 0.0
		var poly: PackedVector2Array = [Vector2(0, y - h), Vector2(size.x, y - h), Vector2(size.x, y), Vector2(0, y),
			Vector2(0, y + h), Vector2(size.x, y + h)]
		draw_polygon(PackedVector2Array([poly[0], poly[1], poly[2], poly[3]]), PackedColorArray([clear, clear, c, c]))
		draw_polygon(PackedVector2Array([poly[3], poly[2], poly[5], poly[4]]), PackedColorArray([c, c, clear, clear]))


func _draw_tint() -> void:
	if tint.a <= 0.0:
		return
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		draw_rect(floor_rect(f), tint)
	draw_rect(floor_rect(ROOF), tint)
	if show_factory:
		draw_rect(floor_rect(factory_floor()), tint)


## Pseudoaleatorio estable 0..1 a partir de un entero (sin estado global).
static func _hash01(n: int) -> float:
	return float(absi(hash(n * 2654435761)) % 10007) / 10007.0
