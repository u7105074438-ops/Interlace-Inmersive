# menu_backdrop.gd — Fondo del menú: cielo nocturno, ciudad en silueta y valla publicitaria de Stellar Sell.
# PROPIETARIO DE: nada (dibujo puro con la paleta de la banda exterior).
# ESCUCHA: nada.
class_name MenuBackdrop
extends Control

## ground_y: altura (local) de la calle; el llamante la alinea con TowerArt.ground_y().
## avoid_rect: zona (local) donde no se dibujan edificios altos (la torre protagonista).
## Dos capas internas: «Static» (CachedCanvas: cielo, estrellas, luna, ciudad, valla, velo y calle,
## pintados una vez en una textura) y «Twinkle» (solo el brillo de las estrellas altas, que ningún
## edificio tapa, redibujado a TWINKLE_FPS mientras animate).

const STAR_COUNT := 90
const FAR_BUILDINGS := 26
const NEAR_BUILDINGS := 14
## Frecuencia de redibujado del titileo de estrellas.
const TWINKLE_FPS := 8.0
## Las estrellas por encima de esta fracción de la calle titilan (los edificios no llegan tan alto).
const TWINKLE_BAND := 0.4

var ground_y: float = -1.0:
	set(value):
		if not is_equal_approx(value, ground_y):
			ground_y = value
			refresh()
var avoid_rect: Rect2 = Rect2():
	set(value):
		if value != avoid_rect:
			avoid_rect = value
			refresh()
var show_billboard: bool = true:
	set(value):
		show_billboard = value
		refresh()
## Velo oscuro desde la izquierda (fracción del ancho) para que el texto del título se lea mejor.
var left_scrim: float = 0.0:
	set(value):
		left_scrim = value
		refresh()
## Titileo de estrellas; false = fondo completamente estático.
var animate: bool = true
var _time: float = 0.0
var _since_redraw: float = 0.0
var _cache: CachedCanvas
var _twinkle: Control
var _palette_seen: int = -1
## Lienzo del pintado en curso (el de la caché o el del titileo).
var _c: CanvasItem


func _init() -> void:
	_cache = CachedCanvas.new()
	_cache.name = "Static"
	_cache.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cache.painter = _paint_static
	add_child(_cache, false, Node.INTERNAL_MODE_FRONT)
	_twinkle = Control.new()
	_twinkle.name = "Twinkle"
	_twinkle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_twinkle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_twinkle.draw.connect(_draw_twinkle)
	add_child(_twinkle, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette_seen = MenuKit.palette_version()
	resized.connect(refresh)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh()


func _process(delta: float) -> void:
	if _palette_seen != MenuKit.palette_version():
		_palette_seen = MenuKit.palette_version()
		refresh()
	if not animate or not is_visible_in_tree():
		return
	_time += delta
	_since_redraw += delta
	if _since_redraw >= 1.0 / TWINKLE_FPS:
		_since_redraw = 0.0
		_twinkle.queue_redraw()


## Repinta ambas capas (tras cambiar tamaño, colores, idioma o propiedades).
func refresh() -> void:
	if _cache != null:
		_cache.refresh()
		_twinkle.queue_redraw()


func _ground() -> float:
	return ground_y if ground_y > 0.0 else size.y * 0.86


func _paint_static(canvas: CanvasItem) -> void:
	_c = canvas
	var ground: float = _ground()
	_draw_sky(ground)
	_draw_stars(ground, false)
	_draw_moon(ground)
	_draw_skyline(ground, FAR_BUILDINGS, 0.55, MenuKit.color("slate").darkened(0.35), hash("far"))
	if show_billboard:
		_draw_billboard(ground)
	_draw_skyline(ground, NEAR_BUILDINGS, 0.34, MenuKit.color("night").lightened(0.04), hash("near"))
	if left_scrim > 0.0:
		var dark: Color = Color(MenuKit.color("night"), 0.7)
		var clear: Color = Color(dark, 0.0)
		var w: float = size.x * left_scrim
		_c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, ground), Vector2(0, ground)]),
				PackedColorArray([dark, clear, clear, dark]))
	_draw_ground(ground)


func _draw_twinkle() -> void:
	_c = _twinkle
	_draw_stars(_ground(), true)


## Calle y corte del terreno (sótanos a la vista), a todo el ancho.
func _draw_ground(ground: float) -> void:
	var guts: Dictionary = MenuKit.band_palette("the_guts")
	var street: Dictionary = MenuKit.band_palette("exterior")
	_c.draw_rect(Rect2(0, ground, size.x, size.y - ground), guts.get("shadow", Color.BLACK))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("backdrop_earth")
	var cell: float = maxf(8.0, size.y * 0.012)
	for i: int in STAR_COUNT:
		var p: Vector2 = Vector2(rng.randf() * size.x, ground + cell * 3.0 + rng.randf() * (size.y - ground))
		_c.draw_circle(p, cell * rng.randf_range(0.15, 0.4), guts.get("carpet", Color.DIM_GRAY))
	var road: Rect2 = Rect2(0, ground - cell * 0.6, size.x, cell * 2.2)
	_c.draw_rect(road, street.get("floor", Color.DIM_GRAY))
	_c.draw_line(Vector2(0, road.position.y), Vector2(size.x, road.position.y), street.get("outline", Color.BLACK), 3.0)
	_c.draw_line(Vector2(0, road.end.y), Vector2(size.x, road.end.y), street.get("outline", Color.BLACK), 3.0)
	var x: float = 0.0
	while x < size.x:
		_c.draw_rect(Rect2(x, road.get_center().y - 2.0, cell * 2.5, 4.0), street.get("accent", Color.YELLOW))
		x += cell * 5.0


func _draw_sky(ground: float) -> void:
	var top: Color = MenuKit.color("night")
	var mid: Color = MenuKit.color("dusk")
	var glow: Color = MenuKit.color("amber").darkened(0.55)
	var mid_y: float = ground * 0.62
	_c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, mid_y), Vector2(0, mid_y)]),
			PackedColorArray([top, top, mid, mid]))
	_c.draw_polygon(PackedVector2Array([Vector2(0, mid_y), Vector2(size.x, mid_y), Vector2(size.x, ground), Vector2(0, ground)]),
			PackedColorArray([mid, mid, glow, glow]))


## Estrellas: la capa estática las pinta todas con su brillo base; la de titileo añade un pulso
## solo a las altas (twinkle = true).
func _draw_stars(ground: float, twinkle: bool) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("menu_stars")
	var star: Color = MenuKit.color("paper")
	for i: int in STAR_COUNT:
		var p: Vector2 = Vector2(rng.randf() * size.x, rng.randf() * ground * 0.6)
		var speed: float = rng.randf_range(0.5, 2.0)
		var radius: float = rng.randf_range(1.0, 2.4)
		var fade: float = 1.0 - p.y / (ground * 0.6)
		if not twinkle:
			_c.draw_circle(p, radius, Color(star, 0.35 * fade))
		elif p.y < ground * TWINKLE_BAND:
			var pulse: float = maxf(0.0, 0.35 * sin(_time * speed + i))
			if pulse > 0.02:
				_c.draw_circle(p, radius, Color(star, pulse * fade))


func _draw_moon(ground: float) -> void:
	var c: Vector2 = Vector2(size.x * 0.44, size.y * 0.13)
	var r: float = size.y * 0.045
	for i: int in 2:
		_c.draw_circle(c, r * (1.4 + i * 0.4), Color(MenuKit.color("lamp"), 0.035))
	_c.draw_circle(c, r, MenuKit.color("lamp").lightened(0.35))
	_c.draw_circle(c + Vector2(r * 0.45, -r * 0.12), r * 0.86, _sky_at(c.y, ground))


## Color del cielo a una altura (el mismo degradado que _draw_sky).
func _sky_at(y: float, ground: float) -> Color:
	var mid_y: float = ground * 0.62
	if y <= mid_y:
		return MenuKit.color("night").lerp(MenuKit.color("dusk"), clampf(y / mid_y, 0.0, 1.0))
	return MenuKit.color("dusk").lerp(MenuKit.color("amber").darkened(0.55), clampf((y - mid_y) / (ground - mid_y), 0.0, 1.0))


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
		_c.draw_rect(r, fill)
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
			_c.draw_rect(wr, Color(c, 0.75))


func _draw_billboard(ground: float) -> void:
	var w: float = size.y * 0.3
	var r: Rect2 = Rect2(size.x * 0.035, ground - size.y * 0.3, w, w * 0.42)
	var ink: Color = MenuKit.color("ink")
	_c.draw_rect(Rect2(r.position.x + w * 0.2, r.end.y, w * 0.035, ground - r.end.y), ink)
	_c.draw_rect(Rect2(r.end.x - w * 0.235, r.end.y, w * 0.035, ground - r.end.y), ink)
	_c.draw_rect(r, MenuKit.color("paper_dim").darkened(0.25))
	_c.draw_rect(Rect2(r.position.x, r.position.y, r.size.x * 0.3, r.size.y), MenuKit.color("amber").darkened(0.25))
	_c.draw_rect(r, ink, false, 3.0)
	var fsize: int = roundi(r.size.y * 0.3)
	var text_x: float = r.position.x + r.size.x * 0.34
	_c.draw_string(MenuKit.font("display"), Vector2(text_x, r.position.y + r.size.y * 0.44), tr("UI_BILLBOARD_LINE1"),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.62, fsize, ink)
	_c.draw_string(MenuKit.font("bold"), Vector2(text_x, r.position.y + r.size.y * 0.78), tr("UI_BILLBOARD_LINE2"),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.62, roundi(fsize * 0.55), ink)
	var c: Vector2 = Vector2(r.position.x + r.size.x * 0.15, r.get_center().y)
	_c.draw_circle(c, r.size.y * 0.28, MenuKit.color("paper"))
	_c.draw_arc(c, r.size.y * 0.28, 0.0, TAU, 24, ink, 3.0)
	MenuKit.draw_person(_c, c + Vector2(0, r.size.y * 0.22), r.size.y * 0.42, MenuKit.color("navy"), MenuKit.color("paper_dim"), ink)
