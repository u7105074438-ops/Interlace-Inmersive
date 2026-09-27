# tower_art.gd — Corte vertical de la torre de Stellar Sell (§14.1): 20 plantas, PB, azotea, 3 sótanos y nave.
# PROPIETARIO DE: nada (dibujo puro; lee las paletas de art_bands.json a través de MenuKit).
# ESCUCHA: nada.
class_name TowerArt
extends Control

## Uso: añadir como hijo, ajustar tamaño/anclas y propiedades públicas.
## Dos capas: el corte estático se dibuja en _draw() SOLO cuando cambia algo (tamaño o propiedad);
## una capa hija «Live» redibuja cada fotograma únicamente lo animado (baliza, humo, cinta, parpadeo
## de fluorescentes, ascensor y figura). animate = false congela también esa capa.
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
const CHIMNEY_UNITS := 2.2
const SHAFT_UNITS := 0.8
const LABEL_UNITS := 2.2
const BAND_LABEL_UNITS := 4.2
## Cuerpo mínimo de las etiquetas (px a 1080 de alto, escalado por el ajuste de tamaño de texto).
const LABEL_MIN_PX := 18
const WIDTH_BY_BAND: Dictionary = {
	"the_guts": 9.0, "the_pit": 8.0, "the_specialists": 8.0, "the_power": 7.2, "the_throne": 6.2,
}
const DESKS_BY_BAND: Dictionary = {
	"the_guts": 2, "the_pit": 4, "the_specialists": 3, "the_power": 2, "the_throne": 1,
}
const PEOPLE_BY_DENSITY: Dictionary = {
	"minimal": 1, "very_low": 1, "low": 1, "medium": 2, "high": 3, "very_high": 5,
}

@export var show_labels: bool = false:
	set(value):
		show_labels = value
		_changed()
@export var show_band_names: bool = false:
	set(value):
		show_band_names = value
		_changed()
@export var show_factory: bool = true:
	set(value):
		show_factory = value
		_changed()
@export var show_people: bool = true:
	set(value):
		show_people = value
		_changed()
@export var show_sign: bool = true:
	set(value):
		show_sign = value
		_changed()
@export var show_ground: bool = true:
	set(value):
		show_ground = value
		_changed()
## Reserva el hueco de las etiquetas aunque estén ocultas (la torre no salta al mostrarlas).
@export var reserve_label_space: bool = false:
	set(value):
		reserve_label_space = value
		_changed()
## Anima la capa viva (baliza, humo, figura...). false = torre congelada (sin trabajo por fotograma).
@export var animate: bool = true
## Sombra plana desplazada detrás del edificio (profundidad sobre el fondo).
@export var drop_shadow: bool = true:
	set(value):
		drop_shadow = value
		_changed()
## Altura de la figura del jugador en unidades de planta.
@export var figure_scale: float = 0.8:
	set(value):
		figure_scale = value
		_live_changed()
## 0 = grupo pegado a la izquierda del control, 1 = a la derecha.
@export var anchor_x: float = 0.5:
	set(value):
		anchor_x = value
		_changed()

var highlight_floor: int = NO_FLOOR:
	set(value):
		if value != highlight_floor:
			highlight_floor = value
			_changed()
## Tinte superpuesto a la torre (alfa = intensidad).
var tint: Color = Color(0, 0, 0, 0):
	set(value):
		if value != tint:
			tint = value
			_changed()
## Niebla 0..1 (velo del color mist_color sobre el corte).
var mist: float = 0.0:
	set(value):
		if not is_equal_approx(value, mist):
			mist = value
			_changed()
var mist_color: Color = Color(0, 0, 0, 0)
## Proporción de ventanas encendidas (noche) 0..1.
var lit_ratio: float = 0.7:
	set(value):
		lit_ratio = value
		_changed()
var figure_visible: bool = false:
	set(value):
		figure_visible = value
		_live_changed()
## Planta continua de la figura: la parte fraccionaria es el tramo de escalera hacia la siguiente.
var figure_floor: float = 0.0:
	set(value):
		figure_floor = value
		_live_changed()
## Posición horizontal (0..1) dentro de la planta cuando no está en la escalera.
var figure_x: float = 0.3:
	set(value):
		figure_x = value
		_live_changed()
var figure_looking_up: bool = false:
	set(value):
		figure_looking_up = value
		_live_changed()
var elevator_visible: bool = true:
	set(value):
		elevator_visible = value
		_live_changed()
var elevator_floor: float = 0.0:
	set(value):
		elevator_floor = value
		_live_changed()

var _live: Control
var _time: float = 0.0
var _unit: float = 10.0
var _cx: float = 0.0
var _ground: float = 0.0
var _layout_size: Vector2 = Vector2(-1, -1)
var _layout_flags: int = -1
var _layout_anchor: float = -1.0


func _init() -> void:
	_live = Control.new()
	_live.name = "Live"
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_live.draw.connect(_draw_live)
	add_child(_live, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_changed)
	if mist_color.a <= 0.0:
		mist_color = MenuKit.color("paper_dim")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_changed()


func _process(delta: float) -> void:
	if animate and is_visible_in_tree():
		_time += delta
		_live.queue_redraw()


func _changed() -> void:
	queue_redraw()
	_live_changed()


func _live_changed() -> void:
	if _live != null:
		_live.queue_redraw()


# ─── API ───────────────────────────────────────────────────────

## Rectángulo local de una planta (interior del corte). Rect2() si la planta no existe.
func floor_rect(floor_number: int) -> Rect2:
	_compute_layout()
	if floor_number == factory_floor():
		var fx: float = _cx + _band_width("the_pit") * 0.5 * _unit
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


static func factory_floor() -> int:
	var value: int = MenuKit.bal_int("mundo.planta_fabrica")
	return value if value != 0 else TOP_FLOOR * 5


## Etiqueta corta de una planta: "20", "PB"/"G", "S1"/"B1".
static func floor_label(f: int) -> String:
	if f == 0:
		return TranslationServer.translate("UI_TOWER_GROUND_SHORT")
	if f < 0:
		return TranslationServer.translate("UI_TOWER_BASEMENT_SHORT").format({"n": -f})
	return str(f)


# ─── Maquetación (cacheada: solo se recalcula si cambian tamaño u opciones) ─

func _compute_layout() -> void:
	var labels: bool = show_labels or reserve_label_space
	var names: bool = show_band_names or reserve_label_space
	var flags: int = int(labels) | (int(names) << 1) | (int(show_factory) << 2)
	if size == _layout_size and flags == _layout_flags and anchor_x == _layout_anchor:
		return
	_layout_size = size
	_layout_flags = flags
	_layout_anchor = anchor_x
	var left_units: float = WIDTH_BY_BAND["the_guts"] * 0.5 + (LABEL_UNITS if labels else 0.0)
	var right_units: float = WIDTH_BY_BAND["the_pit"] * 0.5
	right_units += FACTORY_UNITS if show_factory else WIDTH_BY_BAND["the_guts"] * 0.5
	if names:
		var factory_extra: float = FACTORY_UNITS if show_factory else 0.0
		right_units = maxf(right_units, WIDTH_BY_BAND["the_pit"] * 0.5 + factory_extra + BAND_LABEL_UNITS)
	var total_h: float = ANTENNA_UNITS + ROOF_UNITS + (TOP_FLOOR + 1) - LOWEST + EARTH_UNITS
	_unit = maxf(1.0, minf(size.y / total_h, size.x / (left_units + right_units)))
	var group_w: float = (left_units + right_units) * _unit
	_cx = (size.x - group_w) * anchor_x + left_units * _unit
	_ground = size.y - (-LOWEST + EARTH_UNITS) * _unit


func _band_width(band_id: String) -> float:
	return float(WIDTH_BY_BAND.get(band_id, WIDTH_BY_BAND["the_pit"]))


func _lw() -> float:
	return maxf(1.5, _unit * 0.07)


## Cuerpo de letra de las etiquetas: proporcional a la planta, nunca por debajo del mínimo legible.
func _label_font_size(unit_ratio: float) -> int:
	return maxi(roundi(_unit * unit_ratio), MenuKit.fs(LABEL_MIN_PX))


## Color con el tinte/niebla de la torre aplicado (la capa viva no queda por encima del velo).
func _veiled(c: Color) -> Color:
	return c.lerp(Color(tint, c.a), tint.a) if tint.a > 0.0 else c


# ─── Capa estática ─────────────────────────────────────────────

func _draw() -> void:
	_compute_layout()
	if show_ground:
		_draw_ground()
	if drop_shadow:
		_draw_drop_shadow()
	if show_factory:
		_draw_factory(floor_rect(factory_floor()))
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		_draw_floor(f, floor_rect(f))
	_draw_band_seams()
	_draw_roof(floor_rect(ROOF))
	_draw_shell()
	_draw_highlight()
	if show_labels:
		_draw_floor_labels()
	if show_band_names:
		_draw_band_names()
	_draw_mist()
	_draw_tint()


func _draw_drop_shadow() -> void:
	var shade: Color = Color(MenuKit.color("ink"), 0.55)
	var off: Vector2 = Vector2(_unit * 0.35, _unit * 0.25)
	for f: int in range(0, TOP_FLOOR + 1):
		var r: Rect2 = floor_rect(f)
		draw_rect(Rect2(r.position + off, r.size), shade)
	var roof: Rect2 = floor_rect(ROOF)
	draw_rect(Rect2(roof.position + off, roof.size), shade)
	if show_factory:
		var fr: Rect2 = floor_rect(factory_floor())
		draw_rect(Rect2(fr.position + off, fr.size), shade)


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


## Ventanas de una planta (rectángulos locales), compartidas por la capa estática y la viva.
func _window_rects(f: int, r: Rect2) -> Array[Rect2]:
	var inner_l: float = r.position.x + _unit * (SHAFT_UNITS + 0.5)
	var inner_r: float = r.end.x - _unit * (SHAFT_UNITS + 1.2)
	var count: int = maxi(2, floori((inner_r - inner_l) / (_unit * 1.15)))
	var step: float = (inner_r - inner_l) / count
	var tall: bool = str(MenuKit.band_for_floor(f).get("id", "")) == "the_throne"
	var top: float = r.position.y + r.size.y * (0.12 if tall else 0.2)
	var h: float = r.size.y * (0.5 if tall else 0.36)
	var out: Array[Rect2] = []
	for i: int in count:
		out.append(Rect2(inner_l + i * step + step * 0.12, top, step * 0.76, h))
	return out


func _is_lit(f: int, i: int) -> bool:
	return _hash01(f * 31 + i) < lit_ratio


func _draw_windows(f: int, r: Rect2, pal: Dictionary) -> void:
	var rects: Array[Rect2] = _window_rects(f, r)
	var thin: float = maxf(1.0, _lw() * 0.6)
	for i: int in rects.size():
		var wr: Rect2 = rects[i]
		draw_rect(wr, pal.get("light", Color.WHITE) if _is_lit(f, i) else pal.get("window", Color.GRAY))
		draw_line(wr.position + Vector2(wr.size.x * 0.2, wr.size.y * 0.8),
				wr.position + Vector2(wr.size.x * 0.55, wr.size.y * 0.2), Color(1, 1, 1, 0.35), thin)
		draw_rect(wr, pal.get("outline", Color.BLACK), false, thin)


func _draw_pipes(r: Rect2, pal: Dictionary) -> void:
	var y: float = r.position.y + r.size.y * 0.18
	draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), pal.get("furniture", Color.BROWN), _unit * 0.12)
	draw_line(Vector2(r.position.x, y + _unit * 0.16), Vector2(r.end.x, y + _unit * 0.16),
			pal.get("accent", Color.GREEN), _unit * 0.06)
	var lamp_count: int = 3
	var beam: Color = Color(pal.get("light", Color.WHITE), 0.22)
	for i: int in lamp_count:
		var lx: float = lerpf(r.position.x + _unit * 1.6, r.end.x - _unit * 1.8, float(i) / (lamp_count - 1))
		var cone: PackedVector2Array = [
			Vector2(lx - _unit * 0.1, y + _unit * 0.2), Vector2(lx + _unit * 0.1, y + _unit * 0.2),
			Vector2(lx + _unit * 0.55, r.end.y - r.size.y * 0.2), Vector2(lx - _unit * 0.55, r.end.y - r.size.y * 0.2),
		]
		draw_colored_polygon(cone, beam)
		draw_circle(Vector2(lx, y + _unit * 0.2), _unit * 0.08, pal.get("light", Color.WHITE))


func _draw_furniture(f: int, r: Rect2, band: Dictionary) -> void:
	var pal: Dictionary = band.get("colors", {})
	var band_id: String = str(band.get("id", ""))
	var floor_y: float = r.end.y - r.size.y * 0.2
	var inner_l: float = r.position.x + _unit * (SHAFT_UNITS + 0.45)
	var inner_r: float = r.end.x - _unit * (SHAFT_UNITS + 1.0)
	var desks: int = 1 if f == 0 else int(DESKS_BY_BAND.get(band_id, 2))
	for i: int in desks:
		var x: float = lerpf(inner_l, inner_r, (i + 0.5) / desks)
		_draw_desk(Vector2(x, floor_y), band_id, pal, f)
	if show_people:
		_draw_people(f, floor_y, inner_l, inner_r, band)
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
	if band_id == "the_throne":
		var plant: Color = MenuKit.band_palette("the_pit").get("accent", Color.GREEN)
		draw_circle(Vector2(base.x + w * 0.62, base.y - _unit * 0.28), _unit * 0.2, plant)
		return
	var screen: Rect2 = Rect2(base.x - _unit * 0.18, base.y - h - _unit * 0.26, _unit * 0.36, _unit * 0.24)
	draw_rect(screen, ink)
	draw_rect(screen.grow(-_unit * 0.04), pal.get("accent", Color.BLUE) if f % 2 == 0 else pal.get("window", Color.GRAY))


func _draw_people(f: int, floor_y: float, inner_l: float, inner_r: float, band: Dictionary) -> void:
	var count: int = int(PEOPLE_BY_DENSITY.get(str(band.get("occupancy_density", "medium")), 2))
	var pal: Dictionary = band.get("colors", {})
	var body: Color = pal.get("shadow", Color.DIM_GRAY)
	for i: int in count:
		var x: float = lerpf(inner_l, inner_r, _hash01(f * 53 + i * 11))
		MenuKit.draw_person(self, Vector2(x, floor_y), _unit * 0.55, body, body.lightened(0.15),
				pal.get("outline", Color.BLACK))


func _draw_turnstiles(base: Vector2, pal: Dictionary) -> void:
	var accent: Color = MenuKit.band_palette("exterior").get("accent", Color.YELLOW)
	for i: int in 3:
		var x: float = base.x + (i - 1) * _unit * 0.42
		draw_rect(Rect2(x - _unit * 0.08, base.y - _unit * 0.36, _unit * 0.16, _unit * 0.36), pal.get("outline", Color.BLACK))
		draw_line(Vector2(x, base.y - _unit * 0.3), Vector2(x + _unit * 0.2, base.y - _unit * 0.3), accent, maxf(1.0, _lw()))


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
	var mast_top: Vector2 = _mast_top()
	draw_line(Vector2(mast_top.x, r.position.y), mast_top, ink, maxf(2.0, _unit * 0.1))
	draw_line(Vector2(mast_top.x - _unit * 0.3, r.position.y - _unit * 0.6), Vector2(mast_top.x + _unit * 0.3, r.position.y - _unit * 0.6), ink, _lw())
	if show_sign:
		_draw_sign(Rect2(r.position.x + r.size.x * 0.02, r.position.y - _unit * 1.05, r.size.x * 0.6, _unit * 0.8))


func _mast_top() -> Vector2:
	var r: Rect2 = floor_rect(ROOF)
	return Vector2(r.end.x - r.size.x * 0.22, r.position.y - _unit * ANTENNA_UNITS * 0.95)


func _draw_sign(r: Rect2) -> void:
	var ink: Color = MenuKit.color("ink")
	draw_rect(Rect2(r.position.x + r.size.x * 0.2, r.end.y, _unit * 0.08, _unit * 0.25), ink)
	draw_rect(Rect2(r.end.x - r.size.x * 0.2, r.end.y, _unit * 0.08, _unit * 0.25), ink)
	draw_rect(r, MenuKit.color("night"))
	draw_rect(r, ink, false, _lw())
	var star_c: Vector2 = Vector2(r.position.x + r.size.y * 0.5, r.get_center().y)
	draw_colored_polygon(_star(star_c, r.size.y * 0.34, r.size.y * 0.15), MenuKit.color("amber"))
	var text: String = tr("UI_COMPANY_NAME")
	var f: Font = MenuKit.font("bold")
	var avail: float = r.size.x - r.size.y * 1.1
	var fsize: int = _fit_size(f, text, maxi(8, roundi(r.size.y * 0.5)), avail)
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
		var x0: float = r.position.x + i * tooth_w
		var glass: PackedVector2Array = [Vector2(x0, r.position.y - _unit * 0.7), Vector2(x0 + _unit * 0.18, r.position.y - _unit * 0.62),
			Vector2(x0 + _unit * 0.18, r.position.y), Vector2(x0, r.position.y)]
		draw_colored_polygon(glass, pal.get("window", Color.GRAY))
	draw_polyline(roof, ink, _lw())
	var ch: Rect2 = _chimney_rect(r)
	draw_rect(ch, pal.get("shadow", Color.DIM_GRAY))
	draw_rect(Rect2(ch.position.x, ch.position.y + _unit * 0.3, ch.size.x, _unit * 0.18), pal.get("accent", Color.ORANGE))
	draw_rect(ch, ink, false, _lw())
	draw_rect(r, pal.get("wall", Color.GRAY))
	draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.12, r.size.x, r.size.y * 0.12), pal.get("carpet", Color.DIM_GRAY))
	_draw_machines(r, pal)
	draw_rect(r, ink, false, _lw())


func _chimney_rect(r: Rect2) -> Rect2:
	return Rect2(r.end.x - _unit * 1.2, r.position.y - _unit * CHIMNEY_UNITS, _unit * 0.55, _unit * CHIMNEY_UNITS)


func _belt_y(r: Rect2) -> float:
	return r.end.y - r.size.y * 0.32


func _draw_machines(r: Rect2, pal: Dictionary) -> void:
	var ink: Color = pal.get("outline", Color.BLACK)
	var belt_y: float = _belt_y(r)
	draw_line(Vector2(r.position.x + _unit * 0.4, belt_y), Vector2(r.end.x - _unit * 0.4, belt_y), ink, _unit * 0.12)
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


## Marco ámbar de la planta resaltada; la flecha va junto a la etiqueta (si hay etiquetas) o al
## borde de la planta. La nave se señala desde arriba (su lado izquierdo es la torre).
func _draw_highlight() -> void:
	if highlight_floor == NO_FLOOR:
		return
	var r: Rect2 = floor_rect(highlight_floor)
	if r.size == Vector2.ZERO:
		return
	draw_rect(r.grow(_unit * 0.08), MenuKit.color("amber"), false, _lw() * 2.2)
	if highlight_floor == factory_floor():
		_draw_arrow(Vector2(r.get_center().x, r.position.y - _unit * 0.85), Vector2.DOWN)
	elif not show_labels:
		_draw_arrow(Vector2(r.position.x - _unit * 0.25, r.get_center().y), Vector2.RIGHT)


## Flecha ámbar con contorno; `tip` es la punta y `dir` hacia dónde señala.
func _draw_arrow(tip: Vector2, dir: Vector2) -> void:
	var back: Vector2 = -dir * _unit * 0.6
	var side: Vector2 = Vector2(-dir.y, dir.x) * _unit * 0.35
	var arrow: PackedVector2Array = [tip, tip + back + side, tip + back - side]
	draw_colored_polygon(arrow, MenuKit.color("amber"))
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), MenuKit.color("ink"), _lw())


func _draw_floor_labels() -> void:
	var f_font: Font = MenuKit.font("bold")
	var fsize: int = _label_font_size(0.46)
	var x: float = _cx - _band_width("the_guts") * 0.5 * _unit - _unit * 0.3
	var ink: Color = MenuKit.color("ink")
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		var r: Rect2 = floor_rect(f)
		var text: String = floor_label(f)
		var tw: float = f_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var pos: Vector2 = Vector2(x - tw, r.get_center().y + fsize * 0.35)
		var hot: bool = f == highlight_floor
		draw_string_outline(f_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(2, fsize / 5), ink)
		draw_string(f_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, MenuKit.color("amber") if hot else MenuKit.color("paper"))
		if hot:
			_draw_arrow(Vector2(x - tw - _unit * 0.15, r.get_center().y), Vector2.RIGHT)


## Leyenda de bandas: una columna alineada (tras la nave si se dibuja), con corchete del color de
## la banda a la altura de sus plantas y una línea de cota punteada desde la fachada.
func _draw_band_names() -> void:
	var fsize: int = _label_font_size(0.42)
	var x: float = _cx + WIDTH_BY_BAND["the_pit"] * 0.5 * _unit + _unit * 0.5
	if show_factory:
		x += FACTORY_UNITS * _unit
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
		var accent: Color = (band.get("colors", {}) as Dictionary).get("accent", Color.WHITE)
		var leader_y: float = hi.get_center().y
		draw_dashed_line(Vector2(hi.end.x + _unit * 0.2, leader_y), Vector2(x, leader_y), Color(accent, 0.8),
				maxf(1.0, _lw() * 0.6), _unit * 0.22)
		draw_line(Vector2(x, hi.position.y + _unit * 0.1), Vector2(x, lo.end.y - _unit * 0.1), accent, _lw() * 1.6)
		var text: String = tr(str(band.get("name_key", ""))).to_upper()
		_draw_band_text(text, Vector2(x + _unit * 0.3, (hi.position.y + lo.end.y) * 0.5), fsize, accent.lightened(0.25))


## Nombre de banda a la derecha del corchete; si no cabe, en dos líneas y, si aún no, más pequeño.
func _draw_band_text(text: String, left_mid: Vector2, fsize: int, fill: Color) -> void:
	var f_font: Font = MenuKit.font("bold")
	var avail: float = maxf(size.x - left_mid.x - _unit * 0.2, _unit)
	var lines: PackedStringArray = [text]
	if f_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > avail and text.contains(" "):
		var cut: int = text.rfind(" ")
		lines = [text.substr(0, cut), text.substr(cut + 1)]
	var ink: Color = MenuKit.color("ink")
	var line_h: float = fsize * 1.1
	var y: float = left_mid.y - line_h * (lines.size() - 1) * 0.5 + fsize * 0.35
	for line: String in lines:
		var size_i: int = _fit_size(f_font, line, fsize, avail)
		draw_string_outline(f_font, Vector2(left_mid.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, maxi(2, size_i / 5), ink)
		draw_string(f_font, Vector2(left_mid.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, fill)
		y += line_h


static func _fit_size(f: Font, text: String, font_size: int, width: float) -> int:
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if tw <= width or tw <= 0.0:
		return font_size
	return maxi(6, floori(font_size * width / tw))


func _draw_mist() -> void:
	if mist <= 0.0:
		return
	var layers: int = 6
	for i: int in layers:
		var y: float = size.y * (0.25 + 0.13 * i)
		var h: float = size.y * 0.22
		var c: Color = Color(mist_color, clampf(mist * (0.35 + 0.1 * i), 0.0, 1.0))
		var clear: Color = Color(c, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, y - h), Vector2(size.x, y - h), Vector2(size.x, y), Vector2(0, y)]),
				PackedColorArray([clear, clear, c, c]))
		draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(size.x, y), Vector2(size.x, y + h), Vector2(0, y + h)]),
				PackedColorArray([c, c, clear, clear]))


func _draw_tint() -> void:
	if tint.a <= 0.0:
		return
	for f: int in range(LOWEST, TOP_FLOOR + 1):
		draw_rect(floor_rect(f), tint)
	draw_rect(floor_rect(ROOF), tint)
	if show_factory:
		draw_rect(floor_rect(factory_floor()), tint)


# ─── Capa viva (cada fotograma, solo lo que se mueve) ──────────

func _draw_live() -> void:
	_compute_layout()
	_draw_flicker()
	if show_factory:
		var fr: Rect2 = floor_rect(factory_floor())
		_draw_smoke(fr)
		_draw_belt_boxes(fr)
	_draw_beacon()
	if elevator_visible:
		_draw_elevator_car()
	if figure_visible:
		_draw_figure()


## Fluorescentes que parpadean (bandas con lighting.flicker): tapa unas pocas ventanas encendidas.
func _draw_flicker() -> void:
	var beat: int = floori(_time * 3.0)
	for f: int in range(0, TOP_FLOOR + 1):
		var band: Dictionary = MenuKit.band_for_floor(f)
		if not bool((band.get("lighting", {}) as Dictionary).get("flicker", false)):
			continue
		var rects: Array[Rect2] = _window_rects(f, floor_rect(f))
		for i: int in rects.size():
			if _is_lit(f, i) and _hash01(f * 7 + i + beat) < 0.04:
				var pal: Dictionary = band.get("colors", {})
				_live.draw_rect(rects[i], _veiled(pal.get("window", Color.GRAY)))
				_live.draw_rect(rects[i], _veiled(pal.get("outline", Color.BLACK)), false, maxf(1.0, _lw() * 0.6))


func _draw_smoke(r: Rect2) -> void:
	var ch: Rect2 = _chimney_rect(r)
	var puff: Color = MenuKit.band_palette("factory").get("wall", Color.GRAY).lightened(0.3)
	for i: int in 3:
		var t: float = fmod(_time * 0.25 + i / 3.0, 1.0)
		var p: Vector2 = Vector2(ch.get_center().x + t * _unit * 0.9, ch.position.y - t * _unit * 1.6)
		_live.draw_circle(p, _unit * (0.18 + t * 0.35), Color(puff, 0.8 * (1.0 - t)))


func _draw_belt_boxes(r: Rect2) -> void:
	var pal: Dictionary = MenuKit.band_palette("factory")
	var belt_y: float = _belt_y(r)
	var shift: float = fmod(_time * _unit * 0.6, _unit * 1.2)
	var x: float = r.position.x + _unit * 0.6 + shift
	while x < r.end.x - _unit * 0.8:
		var box_r: Rect2 = Rect2(x, belt_y - _unit * 0.32, _unit * 0.4, _unit * 0.3)
		_live.draw_rect(box_r, _veiled(pal.get("light", Color.WHEAT)))
		_live.draw_rect(box_r, pal.get("outline", Color.BLACK), false, maxf(1.0, _lw() * 0.6))
		x += _unit * 1.2


func _draw_beacon() -> void:
	var blink: float = MenuKit.bal_float("menus.titulo.parpadeo_antena_segundos")
	var on: bool = blink <= 0.0 or fmod(_time, blink) < blink * 0.5
	var beacon: Color = MenuKit.axis_color("blood")
	var top: Vector2 = _mast_top()
	_live.draw_circle(top, _unit * 0.16, _veiled(beacon if on else beacon.darkened(0.6)))
	_live.draw_arc(top, _unit * 0.16, 0.0, TAU, 16, MenuKit.color("ink"), maxf(1.0, _lw() * 0.6))


func _draw_elevator_car() -> void:
	var base: int = clampi(floori(elevator_floor), LOWEST, TOP_FLOOR)
	var r: Rect2 = floor_rect(base)
	var y: float = r.position.y - (elevator_floor - base) * _unit
	var car: Rect2 = Rect2(r.position.x + _unit * 0.2, y + _unit * 0.12, _unit * (SHAFT_UNITS - 0.1), _unit * 0.8)
	_live.draw_rect(car, MenuKit.color("gold"))
	_live.draw_rect(Rect2(car.position.x + car.size.x * 0.2, car.position.y + car.size.y * 0.2, car.size.x * 0.6, car.size.y * 0.35), MenuKit.color("lamp"))
	_live.draw_rect(car, MenuKit.color("ink"), false, _lw())


func _draw_figure() -> void:
	var feet: Vector2 = figure_position()
	var h: float = _unit * figure_scale
	var halo: Color = Color(MenuKit.color("amber"), 0.28 + 0.12 * sin(_time * 4.0))
	_live.draw_circle(feet - Vector2(0, h * 0.5), h * 0.62, halo)
	MenuKit.draw_person(_live, feet, h, MenuKit.color("amber"), MenuKit.color("paper"), MenuKit.color("ink"), figure_looking_up)


## Pseudoaleatorio estable 0..1 a partir de un entero (sin estado global).
static func _hash01(n: int) -> float:
	return float(absi(hash(n * 2654435761)) % 10007) / 10007.0
