# menu_backdrop.gd — Fondo del menú: cielo nocturno, ciudad en silueta y valla publicitaria de Stellar Sell.
# PROPIETARIO DE: nada (dibujo puro con la paleta de la banda exterior).
# ESCUCHA: nada.
class_name MenuBackdrop
extends Control

## ground_y: altura (local) de la calle; el llamante la alinea con TowerArt.ground_y().
## avoid_rect: zona (local) donde no se dibujan edificios altos (la torre protagonista).

const STAR_COUNT := 90
const FAR_BUILDINGS := 26
const NEAR_BUILDINGS := 14

var ground_y: float = -1.0
var avoid_rect: Rect2 = Rect2()
var show_billboard: bool = true
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	if Engine.get_process_frames() % 3 == 0:
		queue_redraw()


func _draw() -> void:
	var ground: float = ground_y if ground_y > 0.0 else size.y * 0.86
	_draw_sky(ground)
	_draw_stars(ground)
	_draw_moon()
	_draw_skyline(ground, FAR_BUILDINGS, 0.55, MenuKit.color("slate").darkened(0.35), hash("far"))
	if show_billboard:
		_draw_billboard(ground)
	_draw_skyline(ground, NEAR_BUILDINGS, 0.34, MenuKit.color("night").lightened(0.04), hash("near"))
	draw_rect(Rect2(0, ground, size.x, size.y - ground), MenuKit.color("ink"))


func _draw_sky(ground: float) -> void:
	var top: Color = MenuKit.color("night")
	var mid: Color = MenuKit.color("dusk")
	var glow: Color = MenuKit.color("amber").darkened(0.55)
	var mid_y: float = ground * 0.62
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, mid_y), Vector2(0, mid_y)]),
			PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, mid_y), Vector2(size.x, mid_y), Vector2(size.x, ground), Vector2(0, ground)]),
			PackedColorArray([mid, mid, glow, glow]))


func _draw_stars(ground: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("menu_stars")
	var star: Color = MenuKit.color("paper")
	for i: int in STAR_COUNT:
		var p: Vector2 = Vector2(rng.randf() * size.x, rng.randf() * ground * 0.6)
		var twinkle: float = 0.35 + 0.35 * sin(_time * rng.randf_range(0.5, 2.0) + i)
		var c: Color = star
		c.a = twinkle * (1.0 - p.y / (ground * 0.6))
		draw_circle(p, rng.randf_range(1.0, 2.4), c)


func _draw_moon() -> void:
	var c: Vector2 = Vector2(size.x * 0.44, size.y * 0.13)
	var r: float = size.y * 0.05
	var halo: Color = MenuKit.color("lamp")
	halo.a = 0.08
	draw_circle(c, r * 2.2, halo)
	draw_circle(c, r, MenuKit.color("lamp").lightened(0.35))
	draw_circle(c + Vector2(r * 0.42, -r * 0.18), r * 0.86, MenuKit.color("night").lerp(MenuKit.color("dusk"), 0.25))


func _draw_skyline(ground: float, count: int, max_share: float, fill: Color, seed_value: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var x: float = -size.x * 0.02
	var lamp: Color = MenuKit.color("lamp")
	while x < size.x:
		var w: float = size.x / count * rng.randf_range(0.6, 1.4)
		var h: float = ground * max_share * rng.randf_range(0.25, 1.0)
		var r: Rect2 = Rect2(x, ground - h, w, h)
		if avoid_rect.size != Vector2.ZERO and r.intersects(avoid_rect):
			r = Rect2(x, ground - h * 0.35, w, h * 0.35)
		draw_rect(r, fill)
		_draw_building_windows(r, rng, lamp, fill)
		x += w + size.x * 0.004


func _draw_building_windows(r: Rect2, rng: RandomNumberGenerator, lamp: Color, fill: Color) -> void:
	var cell: float = maxf(10.0, size.y * 0.018)
	var cols: int = floori(r.size.x / (cell * 1.6))
	var rows: int = floori(r.size.y / (cell * 1.8))
	for row: int in rows:
		for col: int in cols:
			if rng.randf() > 0.22:
				continue
			var wr: Rect2 = Rect2(r.position.x + cell * 0.6 + col * cell * 1.6, r.position.y + cell + row * cell * 1.8, cell * 0.7, cell * 0.9)
			var c: Color = lamp if rng.randf() < 0.7 else fill.lightened(0.2)
			c.a = 0.75
			draw_rect(wr, c)


func _draw_billboard(ground: float) -> void:
	var w: float = size.y * 0.3
	var r: Rect2 = Rect2(size.x * 0.035, ground - size.y * 0.3, w, w * 0.42)
	var ink: Color = MenuKit.color("ink")
	draw_rect(Rect2(r.position.x + w * 0.2, r.end.y, w * 0.035, ground - r.end.y), ink)
	draw_rect(Rect2(r.end.x - w * 0.235, r.end.y, w * 0.035, ground - r.end.y), ink)
	draw_rect(r, MenuKit.color("paper_dim").darkened(0.25))
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.3, r.size.y), MenuKit.color("amber").darkened(0.25))
	draw_rect(r, ink, false, 3.0)
	var f: Font = MenuKit.font("display")
	var fsize: int = roundi(r.size.y * 0.3)
	var text_x: float = r.position.x + r.size.x * 0.34
	draw_string(f, Vector2(text_x, r.position.y + r.size.y * 0.44), tr("UI_BILLBOARD_LINE1"), HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.62, fsize, ink)
	draw_string(MenuKit.font("bold"), Vector2(text_x, r.position.y + r.size.y * 0.78), tr("UI_BILLBOARD_LINE2"), HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.62, roundi(fsize * 0.55), ink)
	var c: Vector2 = Vector2(r.position.x + r.size.x * 0.15, r.get_center().y)
	draw_circle(c, r.size.y * 0.28, MenuKit.color("paper"))
	draw_arc(c, r.size.y * 0.28, 0.0, TAU, 24, ink, 3.0)
	MenuKit.draw_person(self, c + Vector2(0, r.size.y * 0.22), r.size.y * 0.42, MenuKit.color("navy"), MenuKit.color("paper_dim"), ink)
