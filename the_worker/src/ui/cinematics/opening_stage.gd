# opening_stage.gd — Pintor de la apertura (§13.9): escenas vectoriales de los tres movimientos y del título.
# PROPIETARIO DE: nada (dibuja el instante que le indica OpeningCinematic).
# ESCUCHA: nada.
class_name OpeningStage
extends Control

## Se dibuja en un lienzo virtual de 1920×1080 centrado y escalado; el fondo se extiende a los bordes.
## Dos capas: LAYER_BACK (escena) y LAYER_FRONT (primer plano del segundo movimiento, sobre TowerArt).

const LAYER_BACK := 0
const LAYER_FRONT := 1
const VIRTUAL := Vector2(1920, 1080)
const OFFER_COUNT := 6
const STELLAR_CARD := 3
const CARD_SIZE := Vector2(300, 400)
const FAN_PIVOT := Vector2(960, 1320)
const FAN_RADIUS := 700.0
const FAN_SPREAD := 0.62
const CROWD_ROWS: Array[Dictionary] = [
	{"y": 790.0, "h": 150.0, "count": 11}, {"y": 880.0, "h": 180.0, "count": 9}, {"y": 990.0, "h": 215.0, "count": 7},
]
const STREET_Y := 990.0
const TOWER_TOTAL_UNITS := 27.0
const TOWER_BELOW_UNITS := 3.6
const TOWER_ROOF_UNITS := 22.4

var layer: int = LAYER_BACK
var idle_time: float = 0.0:
	set(value):
		idle_time = value
		queue_redraw()
var _movement: int = 0
var _u: float = 0.0
var _chosen: float = -1.0
var _waiting: bool = false
var _shakes: Dictionary = {}
var _k: float = 1.0
var _off: Vector2 = Vector2.ZERO


## Fija el instante: movimiento, tiempo local 0..1, progreso tras la elección (-1 = sin elegir).
func set_moment(movement: int, local_t: float, chosen_local: float, waiting: bool) -> void:
	_movement = movement
	_u = local_t
	_chosen = chosen_local
	_waiting = waiting
	queue_redraw()


func _frame() -> void:
	_k = minf(size.x / VIRTUAL.x, size.y / VIRTUAL.y)
	_off = (size - VIRTUAL * _k) * 0.5


## Rectángulo visible en coordenadas virtuales (incluye los márgenes extra de pantallas anchas).
func _vis() -> Rect2:
	return Rect2(-_off / _k, size / _k)


func _to_real(v: Vector2) -> Vector2:
	return _off + v * _k


func _draw() -> void:
	_frame()
	draw_set_transform(_off, 0.0, Vector2(_k, _k))
	if layer == LAYER_BACK:
		match _movement:
			0:
				_draw_graduation()
			1:
				_draw_commute_back()
			2:
				_draw_lobby()
			_:
				_draw_title()
	elif _movement == 1:
		_draw_commute_front()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if layer == LAYER_FRONT:
		_draw_fade()


# ─── Utilidades ────────────────────────────────────────────────

static func _seg(u: float, a: float, b: float) -> float:
	return clampf((u - a) / maxf(b - a, 0.0001), 0.0, 1.0)


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _pal(band: String, key: String) -> Color:
	return MenuKit.band_palette(band).get(key, Color.MAGENTA)


func _gradient(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))


func _text(pos: Vector2, text: String, font_size: int, fill: Color, kind: String = "bold", centered: bool = true, width: float = -1.0) -> void:
	var f: Font = MenuKit.font(kind)
	var x: float = pos.x
	if centered:
		x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).x * 0.5
	var p: Vector2 = Vector2(x, pos.y)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, maxi(3, font_size / 8), MenuKit.color("ink"))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, fill)


func _outlined_rect(r: Rect2, fill: Color, lw: float = 4.0) -> void:
	draw_rect(r, fill)
	draw_rect(r, MenuKit.color("ink"), false, lw)


## Negro de transición al principio y al final de cada movimiento.
func _draw_fade() -> void:
	var alpha: float = 0.0
	match _movement:
		0:
			alpha = maxf(1.0 - _seg(_u, 0.0, 0.03), _seg(_chosen, 0.9, 1.0) if _chosen >= 0.0 else 0.0)
		1:
			alpha = maxf(1.0 - _seg(_u, 0.0, 0.03), maxf(1.0 - absf(_u - 0.47) / 0.03, _seg(_u, 0.97, 1.0)))
		2:
			alpha = maxf(1.0 - _seg(_u, 0.0, 0.05), _seg(_u, 0.88, 1.0))
		_:
			alpha = maxf(1.0 - _seg(_u, 0.0, 0.04), _seg(_u, 0.95, 1.0))
	if alpha > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(MenuKit.color("ink"), clampf(alpha, 0.0, 1.0)))


# ─── Primer movimiento: la graduación ──────────────────────────

func _draw_graduation() -> void:
	var vis: Rect2 = _vis()
	_gradient(Rect2(vis.position.x, vis.position.y, vis.size.x, 760.0 - vis.position.y), _pal("the_throne", "window"), _pal("the_power", "light"))
	draw_circle(Vector2(1500, 330), 110.0, _pal("the_throne", "light"))
	_draw_trees(vis)
	_draw_campus()
	draw_rect(Rect2(vis.position.x, 740, vis.size.x, vis.end.y - 740), _pal("the_pit", "accent").lightened(0.1))
	_draw_crowd()
	_draw_caps()
	var dim: float = _seg(_u, 0.3, 0.4) * 0.6
	if dim > 0.0:
		draw_rect(vis, Color(MenuKit.color("ink"), dim))
	_draw_offers()


func _draw_trees(vis: Rect2) -> void:
	var green: Color = _pal("the_guts", "accent").darkened(0.15)
	for x: float in [vis.position.x + 120.0, 220.0, 1700.0, vis.end.x - 120.0]:
		draw_rect(Rect2(x - 14, 560, 28, 200), _pal("the_power", "furniture"))
		for i: int in 3:
			var c: Vector2 = Vector2(x + (i - 1) * 70.0, 520.0 - (i % 2) * 60.0)
			draw_circle(c, 95.0, green)
			draw_arc(c, 95.0, 0.0, TAU, 32, MenuKit.color("ink"), 4.0)
	draw_circle(Vector2(1640, 560), 60.0, green)


func _draw_campus() -> void:
	var marble: Color = _pal("the_throne", "floor")
	var shade: Color = _pal("the_throne", "shadow")
	var roof: PackedVector2Array = [Vector2(380, 290), Vector2(960, 140), Vector2(1540, 290)]
	draw_colored_polygon(roof, marble)
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[0]]), MenuKit.color("ink"), 5.0)
	_outlined_rect(Rect2(380, 290, 1160, 60), marble, 5.0)
	_outlined_rect(Rect2(420, 350, 1080, 390), shade.lightened(0.35), 5.0)
	for i: int in 6:
		var x: float = 470.0 + i * 190.0
		_outlined_rect(Rect2(x, 360, 64, 370), marble, 4.0)
		for j: int in 2:
			draw_line(Vector2(x + 22 + j * 20, 372), Vector2(x + 22 + j * 20, 718), shade, 3.0)
	for i: int in 3:
		_outlined_rect(Rect2(400 - i * 30, 730 + i * 14, 1120 + i * 60, 16), marble.darkened(0.05 * i), 3.0)
	var banner: Rect2 = Rect2(760, 400, 400, 230)
	_outlined_rect(banner, _pal("the_power", "carpet"), 5.0)
	draw_rect(banner.grow(-14), _pal("the_power", "accent"), false, 3.0)
	_text(Vector2(960, 500), tr("OPENING_BANNER_1"), 44, _pal("the_power", "light"), "display")
	_text(Vector2(960, 570), tr("OPENING_BANNER_2"), 30, _pal("the_power", "accent").lightened(0.2), "bold")


func _crowd_positions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("graduation_crowd")
	for row: int in CROWD_ROWS.size():
		var spec: Dictionary = CROWD_ROWS[row]
		var count: int = int(spec["count"])
		for i: int in count:
			var x: float = lerpf(160.0, 1760.0, (i + 0.5) / count) + rng.randf_range(-30.0, 30.0)
			var hero: bool = row == CROWD_ROWS.size() - 1 and i == count / 2
			if hero:
				x = 960.0
			out.append({"feet": Vector2(x, float(spec["y"])), "h": float(spec["h"]) * rng.randf_range(0.94, 1.06),
				"hero": hero, "hair": rng.randi_range(0, 3), "spin": rng.randf_range(-6.0, 6.0), "drift": rng.randf_range(-160.0, 160.0)})
	return out


func _hair(index: int) -> Color:
	var options: Array[Color] = [_pal("the_guts", "furniture"), MenuKit.color("ink"), _pal("the_throne", "accent"), _pal("the_power", "furniture")]
	return options[index % options.size()]


func _draw_crowd() -> void:
	var caps_off: bool = _u > 0.2
	for g: Dictionary in _crowd_positions():
		var feet: Vector2 = g["feet"]
		var h: float = g["h"]
		var bob: float = sin(idle_time * 3.0 + feet.x) * 3.0 if _u > 0.2 and _u < 0.34 else 0.0
		_draw_graduate(feet + Vector2(0, bob), h, _hair(int(g["hair"])), bool(g["hero"]), not caps_off)


func _draw_graduate(feet: Vector2, h: float, hair: Color, hero: bool, cap_on: bool) -> void:
	var ink: Color = MenuKit.color("ink")
	var gown: Color = _pal("the_power", "carpet") if not hero else _pal("the_power", "carpet").lightened(0.08)
	var w: float = h * 0.46
	var top: float = feet.y - h * 0.72
	var body: PackedVector2Array = [Vector2(feet.x - w * 0.62, feet.y + 40), Vector2(feet.x - w * 0.5, top + w * 0.2),
		Vector2(feet.x - w * 0.28, top), Vector2(feet.x + w * 0.28, top), Vector2(feet.x + w * 0.5, top + w * 0.2), Vector2(feet.x + w * 0.62, feet.y + 40)]
	draw_colored_polygon(body, gown)
	draw_polyline(body, ink, 4.0)
	var head_c: Vector2 = Vector2(feet.x, top - h * 0.1)
	draw_circle(head_c, h * 0.13, hair)
	draw_arc(head_c, h * 0.13, 0.0, TAU, 24, ink, 4.0)
	if hero:
		draw_arc(head_c + Vector2(0, h * 0.35), h * 0.62, 0.0, TAU, 40, MenuKit.color("amber"), 5.0)
	if cap_on:
		_draw_cap(head_c + Vector2(0, -h * 0.1), h * 0.2, 0.0, hero)


func _draw_cap(c: Vector2, s: float, angle: float, hero: bool) -> void:
	var ink: Color = MenuKit.color("ink")
	var pts: PackedVector2Array = []
	for p: Vector2 in [Vector2(-1.2, 0), Vector2(0, -0.45), Vector2(1.2, 0), Vector2(0, 0.45)]:
		pts.append(c + (p * s).rotated(angle))
	draw_colored_polygon(pts, ink.lightened(0.12))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), ink, 3.0)
	var tassel: Color = MenuKit.color("amber") if hero else _pal("the_throne", "accent")
	draw_line(c, c + (Vector2(s * 0.9, s * 0.2)).rotated(angle), tassel, 4.0)
	draw_line(c + (Vector2(s * 0.9, s * 0.2)).rotated(angle), c + (Vector2(s * 0.95, s * 0.8)).rotated(angle), tassel, 4.0)


func _draw_caps() -> void:
	var t: float = _seg(_u, 0.2, 0.42)
	if t <= 0.0:
		return
	for g: Dictionary in _crowd_positions():
		var feet: Vector2 = g["feet"]
		var h: float = g["h"]
		var start: Vector2 = Vector2(feet.x, feet.y - h * 0.72 - h * 0.3)
		var apex: float = 620.0 + float(g["drift"]) * 0.4
		var y: float = start.y - apex * 4.0 * t * (1.0 - t)
		if t >= 1.0:
			y = feet.y + 20.0
		var pos: Vector2 = Vector2(start.x + float(g["drift"]) * t, y)
		_draw_cap(pos, h * 0.2, float(g["spin"]) * t, bool(g["hero"]))


# ─── Las ofertas (la única elección, y es falsa) ───────────────

func _card_transform(i: int) -> Transform2D:
	var spread: float = _ease(_seg(_u, 0.38, 0.5))
	var angle: float = lerpf(-FAN_SPREAD, FAN_SPREAD, float(i) / (OFFER_COUNT - 1)) * spread
	var center: Vector2 = FAN_PIVOT + Vector2(0, -FAN_RADIUS * lerpf(0.55, 1.0, spread)).rotated(angle)
	var scale_v: float = 1.0
	if _chosen >= 0.0:
		var c: float = _ease(_seg(_chosen, 0.0, 0.25))
		if i == STELLAR_CARD:
			center = center.lerp(Vector2(960, 470), c)
			angle = lerpf(angle, 0.0, c)
			scale_v = lerpf(1.0, 1.55, c)
		else:
			center += Vector2(0, 900.0 * c * c)
			angle += (float(i) - STELLAR_CARD) * 0.3 * c
	if _shakes.has(i):
		var age: float = idle_time - float(_shakes[i])
		if age < 0.5:
			center.x += sin(age * 60.0) * 18.0 * (1.0 - age / 0.5)
	if i == STELLAR_CARD and _waiting:
		center.y += sin(idle_time * 4.0) * 8.0
	return Transform2D(angle, Vector2(scale_v, scale_v), 0.0, center)


func _draw_offers() -> void:
	if _u < 0.38:
		return
	var order: Array[int] = [0, 1, 2, 4, 5, STELLAR_CARD]
	var base: Transform2D = Transform2D(0.0, Vector2(_k, _k), 0.0, _off)
	for i: int in order:
		draw_set_transform_matrix(base * _card_transform(i))
		_draw_offer_card(i)
	draw_set_transform(_off, 0.0, Vector2(_k, _k))


func _draw_offer_card(i: int) -> void:
	var r: Rect2 = Rect2(-CARD_SIZE * 0.5, CARD_SIZE)
	var ink: Color = MenuKit.color("ink")
	var stellar: bool = i == STELLAR_CARD
	draw_rect(Rect2(r.position + Vector2(10, 10), r.size), ink)
	draw_rect(r, MenuKit.color("paper"))
	var header: Color = MenuKit.color("night") if stellar else _pal("the_specialists", "shadow")
	draw_rect(Rect2(r.position, Vector2(r.size.x, 86)), header)
	for line: int in 5:
		draw_rect(Rect2(r.position.x + 28, r.position.y + 190 + line * 30, r.size.x * (0.8 - (line % 2) * 0.25), 12), MenuKit.color("paper_dim"))
	if stellar:
		_draw_stellar_card(r)
	else:
		_text(Vector2(0, r.position.y + 58), tr("OPENING_OFFER_%d" % i), 30, MenuKit.color("paper"), "bold", true, r.size.x - 20)
		_text(Vector2(0, r.position.y + 140), tr("OPENING_OFFER_ROLE"), 22, _pal("the_specialists", "shadow"), "bold")
		draw_rect(r, Color(_pal("the_specialists", "shadow"), 0.45))
		_draw_stamp(Vector2(0, 40), tr("OPENING_STAMP_%d" % i), -0.25, MenuKit.axis_color("blood"))
	draw_rect(r, MenuKit.color("amber") if stellar else ink, false, 8.0 if stellar else 4.0)


func _draw_stellar_card(r: Rect2) -> void:
	var star_c: Vector2 = Vector2(r.position.x + 48, r.position.y + 43)
	var star: PackedVector2Array = []
	for k: int in 10:
		var a: float = -PI * 0.5 + k * PI / 5.0
		star.append(star_c + Vector2(cos(a), sin(a)) * (26.0 if k % 2 == 0 else 11.0))
	draw_colored_polygon(star, MenuKit.color("amber"))
	_text(Vector2(r.position.x + 84, r.position.y + 56), tr("UI_COMPANY_NAME"), 32, MenuKit.color("lamp"), "bold", false, r.size.x - 90)
	_text(Vector2(0, r.position.y + 130), tr("OCC_EMAIL_WORKER"), 26, MenuKit.color("night"), "bold", true, r.size.x - 24)
	_text(Vector2(0, r.position.y + 164), tr("OPENING_OFFER_SS_PLACE"), 22, _pal("the_specialists", "shadow"), "bold")
	_text(Vector2(0, r.end.y - 34), tr("OPENING_OFFER_SS_START"), 24, MenuKit.color("night"), "bold")
	if _waiting:
		var pulse: float = 0.5 + 0.5 * sin(idle_time * 5.0)
		draw_rect(r.grow(10.0 + pulse * 10.0), Color(MenuKit.color("amber"), 0.8 - pulse * 0.5), false, 6.0)
	if _chosen >= 0.0:
		var s: float = _seg(_chosen, 0.25, 0.32)
		if s > 0.0:
			var grow: float = lerpf(2.2, 1.0, _ease(s))
			draw_set_transform_matrix(get_canvas_transform().affine_inverse() * get_global_transform_with_canvas() * Transform2D())
			_draw_hired_stamp(r, grow, s)


func _draw_hired_stamp(r: Rect2, grow: float, alpha: float) -> void:
	var base: Transform2D = Transform2D(0.0, Vector2(_k, _k), 0.0, _off) * _card_transform(STELLAR_CARD)
	draw_set_transform_matrix(base * Transform2D(-0.2, Vector2(grow, grow), 0.0, Vector2(0, 40)))
	var c: Color = Color(_pal("the_guts", "accent"), alpha)
	var text: String = tr("OPENING_STAMP_HIRED")
	var f: Font = MenuKit.font("display")
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	draw_rect(Rect2(-tw * 0.5 - 18, -52, tw + 36, 76), c, false, 7.0)
	draw_string(f, Vector2(-tw * 0.5, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, c)


func _draw_stamp(center: Vector2, text: String, angle: float, c: Color) -> void:
	var outer: Transform2D = get_canvas_transform().affine_inverse() * get_canvas_transform()
	var f: Font = MenuKit.font("display")
	var fsize: int = 34
	var tw: float = minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x, CARD_SIZE.x * 0.8)
	var pts: PackedVector2Array = []
	for p: Vector2 in [Vector2(-tw * 0.5 - 14, -38), Vector2(tw * 0.5 + 14, -38), Vector2(tw * 0.5 + 14, 16), Vector2(-tw * 0.5 - 14, 16)]:
		pts.append(center + p.rotated(angle))
	pts.append(pts[0])
	draw_polyline(pts, c, 5.0)
	var saved: Transform2D = outer
	draw_string(f, center + Vector2(-tw * 0.5, 0).rotated(angle), text, HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x * 0.8, fsize, c)
	if saved != outer:
		return


## Índice de la oferta bajo un punto (coordenadas locales), o -1. La de Stellar Sell tiene prioridad.
func card_at(point: Vector2) -> int:
	_frame()
	var v: Vector2 = (point - _off) / _k
	var order: Array[int] = [STELLAR_CARD, 5, 4, 2, 1, 0]
	for i: int in order:
		var local: Vector2 = _card_transform(i).affine_inverse() * v
		if Rect2(-CARD_SIZE * 0.5, CARD_SIZE).has_point(local):
			return i
	return -1


func shake_card(index: int) -> void:
	_shakes[index] = idle_time


# ─── Segundo movimiento: el traslado ───────────────────────────

func _draw_commute_back() -> void:
	var vis: Rect2 = _vis()
	if _u < 0.47:
		_draw_bus_ride(vis)
	else:
		_gradient(Rect2(vis.position.x, vis.position.y, vis.size.x, STREET_Y - vis.position.y), _pal("the_pit", "window"), _pal("the_pit", "light"))
		_draw_far_city(vis, 0.0, _pal("the_pit", "window").darkened(0.12))


func _bus_scroll() -> float:
	var cruise: float = _seg(_u, 0.0, 0.34)
	var brake: float = _seg(_u, 0.34, 0.44)
	return cruise * 0.34 * 9000.0 + (brake - brake * brake * 0.5) * 0.1 * 9000.0


func _draw_bus_ride(vis: Rect2) -> void:
	var scroll: float = _bus_scroll()
	_gradient(Rect2(vis.position.x, vis.position.y, vis.size.x, 900 - vis.position.y), _pal("the_pit", "window"), _pal("the_pit", "light"))
	_draw_far_city(vis, scroll * 0.15, _pal("the_pit", "window").darkened(0.15))
	_draw_near_city(vis, scroll * 0.45)
	draw_rect(Rect2(vis.position.x, 880, vis.size.x, vis.end.y - 880), _pal("exterior", "floor"))
	draw_rect(Rect2(vis.position.x, 860, vis.size.x, 24), _pal("the_pit", "wall"))
	var dash_off: float = fmod(scroll, 240.0)
	var x: float = vis.position.x - dash_off
	while x < vis.end.x:
		draw_rect(Rect2(x, 990, 120, 12), _pal("exterior", "accent"))
		x += 240.0
	if _u > 0.3:
		_draw_bus_stop(Vector2(1700.0 + (1.0 - _seg(_u, 0.3, 0.44)) * 1400.0 - scroll * 0.0, 870))
	_draw_bus(Vector2(900, 900), scroll)


func _draw_far_city(vis: Rect2, scroll: float, fill: Color) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("commute_far")
	var widths: Array[float] = []
	var heights: Array[float] = []
	for i: int in 16:
		widths.append(rng.randf_range(110, 220))
		heights.append(rng.randf_range(160, 420))
	var period: float = 0.0
	for w: float in widths:
		period += w + 20.0
	var x: float = vis.position.x - fmod(scroll, period)
	var i: int = 0
	while x < vis.end.x:
		var w: float = widths[i % widths.size()]
		draw_rect(Rect2(x, 880 - heights[i % heights.size()], w, heights[i % heights.size()]), fill)
		x += w + 20.0
		i += 1


func _draw_near_city(vis: Rect2, scroll: float) -> void:
	var colors: Array[Color] = [_pal("the_pit", "wall"), _pal("the_pit", "furniture"), _pal("the_specialists", "floor"), _pal("the_pit", "carpet")]
	var period: float = 4 * 380.0
	var x: float = vis.position.x - fmod(scroll, period) - 380.0
	var i: int = 0
	while x < vis.end.x + 380.0:
		var h: float = 460.0 + (i % 3) * 90.0
		var r: Rect2 = Rect2(x, 880 - h, 340, h)
		_outlined_rect(r, colors[i % colors.size()], 4.0)
		for row: int in floori(h / 110.0):
			for col: int in 3:
				_outlined_rect(Rect2(r.position.x + 30 + col * 100, r.position.y + 30 + row * 110, 70, 70), _pal("the_pit", "window"), 3.0)
		x += 380.0
		i += 1


func _draw_bus(base: Vector2, scroll: float) -> void:
	var bounce: float = sin(idle_time * 9.0) * 3.0 * (1.0 - _seg(_u, 0.36, 0.44))
	var body: Rect2 = Rect2(base.x - 470, base.y - 330 + bounce, 940, 300)
	var blue: Color = _pal("the_specialists", "accent")
	_outlined_rect(Rect2(body.position + Vector2(12, 12), body.size), MenuKit.color("ink"), 0.0)
	_outlined_rect(body, blue, 5.0)
	draw_rect(Rect2(body.position.x, body.position.y + 196, body.size.x, 26), _pal("the_specialists", "wall"))
	for i: int in 6:
		var wr: Rect2 = Rect2(body.position.x + 40 + i * 132, body.position.y + 36, 110, 120)
		_outlined_rect(wr, _pal("the_specialists", "window"), 4.0)
		var hero: bool = i == 3
		var head_color: Color = MenuKit.color("amber") if hero else _pal("the_specialists", "shadow")
		MenuKit.draw_person(self, Vector2(wr.get_center().x, wr.end.y + 8), 120.0, head_color.darkened(0.1), head_color, MenuKit.color("ink"))
	var sign: Rect2 = Rect2(body.end.x - 150, body.position.y + 44, 130, 60)
	_outlined_rect(sign, MenuKit.color("night"), 3.0)
	_text(sign.get_center() + Vector2(0, 9), tr("OPENING_BUS_SIGN"), 20, MenuKit.color("lamp"), "bold", true, sign.size.x - 8)
	for wx: float in [body.position.x + 170, body.end.x - 170]:
		_draw_wheel(Vector2(wx, body.end.y + 4), 58.0, scroll)


func _draw_wheel(c: Vector2, r: float, scroll: float) -> void:
	draw_circle(c, r, MenuKit.color("ink"))
	draw_circle(c, r * 0.5, _pal("the_specialists", "furniture"))
	var a: float = scroll / r
	for k: int in 4:
		draw_line(c, c + Vector2(r * 0.5, 0).rotated(a + k * PI * 0.5), MenuKit.color("ink"), 5.0)


func _draw_bus_stop(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 6, p.y - 300, 12, 300), MenuKit.color("ink"))
	var sign: Rect2 = Rect2(p.x - 110, p.y - 330, 220, 90)
	_outlined_rect(sign, MenuKit.color("paper"), 4.0)
	_text(sign.get_center() + Vector2(0, 12), tr("OPENING_BUS_STOP"), 26, MenuKit.color("night"), "bold", true, sign.size.x - 12)


## Encuadre de la torre en el segundo movimiento (coordenadas reales para OpeningCinematic).
func tower_shot(movement: int, local_t: float) -> Dictionary:
	_frame()
	if movement != 1 or local_t < 0.47:
		return {"visible": false}
	var grow: float = _ease(_seg(local_t, 0.47, 0.72))
	var tilt: float = _ease(_seg(local_t, 0.72, 0.97))
	var h: float = lerpf(0.5, 1.05, grow) * VIRTUAL.y
	h = lerpf(h, 2.7 * VIRTUAL.y, tilt)
	var unit: float = h / TOWER_TOTAL_UNITS
	var ground_screen: float = STREET_Y
	if tilt > 0.0:
		var hf: float = lerpf(0.48, 0.9, tilt)
		ground_screen = lerpf(STREET_Y, VIRTUAL.y * 0.5 + hf * TOWER_ROOF_UNITS * unit, tilt)
	var top_left: Vector2 = Vector2(VIRTUAL.x * 0.5 - VIRTUAL.x, ground_screen + TOWER_BELOW_UNITS * unit - h)
	var real: Rect2 = Rect2(_to_real(top_left), Vector2(VIRTUAL.x * 2.0, h) * _k)
	var mist: float = _mist_amount(local_t)
	return {"visible": true, "rect": real, "tint": Color(_pal("the_pit", "light"), mist * 0.55),
		"labels": tilt > 0.05, "highlight": 3 if tilt > 0.05 else TowerArt.NO_FLOOR, "ground": ground_screen}


func _mist_amount(local_t: float) -> float:
	return lerpf(1.0, 0.18, _ease(_seg(local_t, 0.47, 0.72))) * (1.0 - _seg(local_t, 0.72, 0.85))


func _draw_commute_front() -> void:
	if _u < 0.47:
		return
	var vis: Rect2 = _vis()
	var shot: Dictionary = tower_shot(1, _u)
	var ground: float = float(shot.get("ground", STREET_Y))
	draw_rect(Rect2(vis.position.x, ground, vis.size.x, maxf(vis.end.y - ground, 0.0) + 4000.0), _pal("exterior", "floor"))
	draw_rect(Rect2(vis.position.x, ground, vis.size.x, 22), _pal("the_pit", "wall"))
	_draw_mist_bands(vis, _mist_amount(_u))
	_draw_walker(Vector2(960, ground + 80), 260.0, 0.0, true, true)
	var tilt: float = _seg(_u, 0.72, 0.97)
	if tilt > 0.0:
		var floor_n: int = clampi(roundi(lerpf(1.0, 20.0, _ease(tilt))), 1, TowerArt.TOP_FLOOR)
		_draw_floor_counter(Vector2(vis.end.x - 260, 150), floor_n, _seg(_u, 0.72, 0.76))


func _draw_mist_bands(vis: Rect2, amount: float) -> void:
	if amount <= 0.0:
		return
	var mist: Color = _pal("the_pit", "light")
	for i: int in 5:
		var y: float = 380.0 + i * 140.0 + sin(idle_time * 0.4 + i) * 20.0
		var c: Color = Color(mist, clampf(amount * (0.45 + i * 0.1), 0.0, 0.95))
		var clear: Color = Color(mist, 0.0)
		_gradient(Rect2(vis.position.x, y - 160, vis.size.x, 160), clear, c)
		_gradient(Rect2(vis.position.x, y, vis.size.x, 160), c, clear)


func _draw_floor_counter(pos: Vector2, floor_n: int, alpha: float) -> void:
	var r: Rect2 = Rect2(pos - Vector2(170, 90), Vector2(340, 190))
	draw_rect(Rect2(r.position + Vector2(10, 10), r.size), Color(MenuKit.color("ink"), alpha))
	draw_rect(r, Color(MenuKit.color("night"), alpha))
	draw_rect(r, Color(MenuKit.color("amber"), alpha), false, 5.0)
	_text(Vector2(pos.x, pos.y - 34), tr("OPENING_FLOOR_LABEL"), 28, Color(MenuKit.color("paper_dim"), alpha), "bold")
	_text(Vector2(pos.x, pos.y + 76), "%02d" % floor_n, 110, Color(MenuKit.color("amber"), alpha), "display")


## Figura del protagonista (traje barato, credencial ámbar). phase = ciclo de paso; 0 = quieto.
func _draw_walker(feet: Vector2, h: float, phase: float, looking_up: bool, from_behind: bool) -> void:
	var ink: Color = MenuKit.color("ink")
	var suit: Color = _pal("the_pit", "shadow")
	var leg_swing: float = sin(phase * TAU) * h * 0.08
	for side: float in [-1.0, 1.0]:
		var hip: Vector2 = feet + Vector2(side * h * 0.07, -h * 0.42)
		var foot: Vector2 = feet + Vector2(side * h * 0.07 + side * leg_swing, 0)
		draw_line(hip, foot, ink, h * 0.1)
		draw_line(hip, foot, suit.darkened(0.2), h * 0.07)
	var torso: Rect2 = Rect2(feet.x - h * 0.16, feet.y - h * 0.78, h * 0.32, h * 0.4)
	draw_rect(torso, suit)
	draw_rect(torso, ink, false, 4.0)
	var arm_swing: float = -leg_swing * 0.8
	for side: float in [-1.0, 1.0]:
		var shoulder: Vector2 = Vector2(feet.x + side * h * 0.16, feet.y - h * 0.74)
		draw_line(shoulder, shoulder + Vector2(side * h * 0.04 + arm_swing * side, h * 0.34), ink, h * 0.07)
	if not from_behind:
		draw_line(Vector2(feet.x - h * 0.05, torso.position.y), Vector2(feet.x + h * 0.02, torso.position.y + h * 0.2), MenuKit.color("amber"), 4.0)
		_outlined_rect(Rect2(feet.x - h * 0.02, torso.position.y + h * 0.18, h * 0.1, h * 0.12), MenuKit.color("amber"), 3.0)
	var head_c: Vector2 = Vector2(feet.x, feet.y - h * 0.9 - (h * 0.03 if looking_up else 0.0))
	draw_circle(head_c, h * 0.12, _pal("the_power", "light").darkened(0.1))
	if from_behind:
		draw_circle(head_c + Vector2(0, h * (0.03 if looking_up else -0.02)), h * 0.115, _hair(0))
	draw_arc(head_c, h * 0.12, 0.0, TAU, 24, ink, 4.0)


# ─── Tercer movimiento: el acceso ──────────────────────────────

func _draw_lobby() -> void:
	var vis: Rect2 = _vis()
	draw_rect(Rect2(vis.position.x, vis.position.y, vis.size.x, 640 - vis.position.y), _pal("the_pit", "wall"))
	draw_rect(Rect2(vis.position.x, 640, vis.size.x, vis.end.y - 640), _pal("the_pit", "floor"))
	for i: int in 13:
		var x: float = -400.0 + i * 220.0
		draw_line(Vector2(x + 400, 640), Vector2(x - 200 + (i - 6) * 60.0, 1080), _pal("the_pit", "carpet"), 3.0)
	for y: float in [700.0, 790.0, 910.0]:
		draw_line(Vector2(vis.position.x, y), Vector2(vis.end.x, y), _pal("the_pit", "carpet"), 3.0)
	draw_line(Vector2(vis.position.x, 640), Vector2(vis.end.x, 640), MenuKit.color("ink"), 5.0)
	_draw_ceiling_lights(vis)
	_draw_wordmark(Vector2(960, 250))
	_draw_poster(Rect2(170, 170, 250, 330))
	_draw_reception(Rect2(1450, 470, 360, 190))
	_draw_plant(Vector2(110, 660))
	_draw_plant(Vector2(1830, 660))
	_draw_lobby_people()
	_draw_turnstiles()


func _draw_ceiling_lights(vis: Rect2) -> void:
	for i: int in 6:
		var x: float = 200.0 + i * 300.0
		var flicker: bool = i == 4 and fmod(idle_time, 2.3) < 0.12
		var tube: Color = _pal("the_pit", "window") if flicker else _pal("the_pit", "light").lightened(0.3)
		_outlined_rect(Rect2(x - 90, vis.position.y + 30.0 - vis.position.y + maxf(vis.position.y, 0.0), 180, 18), tube, 3.0)


func _draw_wordmark(c: Vector2) -> void:
	var star: PackedVector2Array = []
	for k: int in 10:
		var a: float = -PI * 0.5 + k * PI / 5.0
		star.append(c + Vector2(-260, 0) + Vector2(cos(a), sin(a)) * (70.0 if k % 2 == 0 else 30.0))
	draw_colored_polygon(star, MenuKit.color("amber"))
	var closed: PackedVector2Array = star.duplicate()
	closed.append(star[0])
	draw_polyline(closed, MenuKit.color("ink"), 4.0)
	_text(c + Vector2(90, 30), tr("UI_COMPANY_NAME").to_upper(), 84, MenuKit.color("night"), "display")


func _draw_poster(r: Rect2) -> void:
	_outlined_rect(Rect2(r.position + Vector2(8, 8), r.size), MenuKit.color("ink"), 0.0)
	_outlined_rect(r, MenuKit.color("paper"), 4.0)
	var art: Rect2 = Rect2(r.position + Vector2(20, 20), Vector2(r.size.x - 40, r.size.y * 0.55))
	_gradient(art, _pal("the_specialists", "window"), _pal("the_specialists", "accent"))
	var peak: PackedVector2Array = [Vector2(art.position.x, art.end.y), art.position + Vector2(art.size.x * 0.55, art.size.y * 0.2), art.end]
	draw_colored_polygon(peak, _pal("the_specialists", "shadow"))
	draw_line(peak[1], peak[1] + Vector2(0, -40), MenuKit.color("ink"), 3.0)
	draw_colored_polygon(PackedVector2Array([peak[1] + Vector2(0, -40), peak[1] + Vector2(34, -30), peak[1] + Vector2(0, -20)]), MenuKit.color("amber"))
	draw_rect(art, MenuKit.color("ink"), false, 3.0)
	_text(Vector2(r.get_center().x, art.end.y + 58), tr("OPENING_POSTER_1"), 26, MenuKit.color("night"), "display", true, r.size.x - 20)
	_text(Vector2(r.get_center().x, art.end.y + 96), tr("OPENING_POSTER_2"), 26, MenuKit.color("night"), "display", true, r.size.x - 20)


func _draw_reception(r: Rect2) -> void:
	MenuKit.draw_person(self, Vector2(r.get_center().x, r.position.y + 30), 150.0, _pal("the_pit", "accent"), _pal("the_pit", "light"), MenuKit.color("ink"))
	_outlined_rect(r, _pal("the_pit", "furniture"), 5.0)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 24), _pal("the_pit", "accent"))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 24), MenuKit.color("ink"), false, 4.0)


func _draw_plant(base: Vector2) -> void:
	_outlined_rect(Rect2(base.x - 40, base.y - 70, 80, 70), _pal("the_pit", "furniture"), 4.0)
	for k: int in 5:
		var a: float = -PI * 0.5 + (k - 2) * 0.35
		var tip: Vector2 = base + Vector2(0, -70) + Vector2(cos(a), sin(a)) * 120.0
		draw_line(base + Vector2(0, -70), tip, _pal("the_pit", "accent"), 16.0)
		draw_circle(tip, 14.0, _pal("the_pit", "accent"))


const LANES: Array[float] = [560.0, 820.0, 1080.0, 1340.0]


func _draw_turnstiles() -> void:
	var open_amount: float = _seg(_u, 0.45, 0.52) * (1.0 - _seg(_u, 0.66, 0.72))
	for i: int in LANES.size():
		var x: float = LANES[i] + 130.0
		_outlined_rect(Rect2(x - 26, 700, 52, 170), _pal("the_specialists", "shadow"), 4.0)
		var hero_lane: bool = i == 1
		var granted: bool = hero_lane and _u > 0.45 and _u < 0.72
		var light: Color = _pal("the_guts", "accent") if granted else MenuKit.axis_color("blood")
		draw_circle(Vector2(x, 725), 12.0, light)
		var angle: float = -PI * 0.5 * (open_amount if hero_lane else 0.0)
		var arm_end: Vector2 = Vector2(x - 26, 790) + Vector2(-190, 0).rotated(angle)
		draw_line(Vector2(x - 26, 790), arm_end, MenuKit.color("ink"), 16.0)
		draw_line(Vector2(x - 26, 790), arm_end, _pal("the_throne", "accent"), 9.0)


func _draw_lobby_people() -> void:
	for lane: int in [0, 2, 3]:
		var t: float = fmod(idle_time * 0.12 + lane * 0.37, 1.0)
		var x: float = lerpf(-100.0, 2000.0, t)
		MenuKit.draw_person(self, Vector2(x, 860 + lane * 6.0), 250.0, _pal("the_pit", "shadow"), _pal("the_pit", "light").darkened(0.2), MenuKit.color("ink"))
	var walk_in: float = _seg(_u, 0.05, 0.4)
	var walk_out: float = _seg(_u, 0.55, 0.9)
	var x_hero: float = lerpf(-60.0, LANES[1] + 20.0, walk_in)
	x_hero = lerpf(x_hero, 1500.0, walk_out)
	var moving: bool = (_u > 0.05 and _u < 0.4) or _u > 0.55
	_draw_walker(Vector2(x_hero, 900), 300.0, idle_time * 1.6 if moving else 0.0, false, false)


# ─── Título y lema ─────────────────────────────────────────────

func _draw_title() -> void:
	var vis: Rect2 = _vis()
	_gradient(vis, MenuKit.color("night"), MenuKit.color("dusk"))
	for i: int in 12:
		var x: float = vis.position.x + i * vis.size.x / 12.0
		draw_rect(Rect2(x, vis.position.y, 3, vis.size.y), Color(MenuKit.color("paper"), 0.03))
	var stamp: float = _ease(_seg(_u, 0.04, 0.12))
	if stamp <= 0.0:
		return
	var s: float = lerpf(1.7, 1.0, stamp)
	var shake: float = sin(_u * 400.0) * 6.0 * (1.0 - _seg(_u, 0.12, 0.2)) * float(_u > 0.12)
	draw_set_transform(_off + Vector2(960 + shake, 470) * _k, 0.0, Vector2(_k * s, _k * s))
	var logo_alpha: float = stamp
	_text(Vector2(0, -190), tr("UI_LOGO_THE"), 96, Color(MenuKit.color("amber"), logo_alpha), "display")
	_text(Vector2(0, 40), tr("UI_LOGO_WORKER"), 250, Color(MenuKit.color("paper"), logo_alpha), "display")
	draw_set_transform(_off, 0.0, Vector2(_k, _k))
	var rule: float = _ease(_seg(_u, 0.14, 0.24))
	draw_rect(Rect2(960 - 520 * rule, 560, 1040 * rule, 10), MenuKit.color("amber"))
	var tag_a: float = _seg(_u, 0.24, 0.32)
	_text(Vector2(960, 660), tr("UI_TAGLINE"), 64, Color(MenuKit.color("paper"), tag_a), "italic")
	var store_a: float = _seg(_u, 0.4, 0.5)
	_text(Vector2(960, 760), tr("UI_STORE_TAGLINE"), 36, Color(MenuKit.color("paper_dim"), store_a), "bold")
