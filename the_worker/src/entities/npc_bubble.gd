# npc_bubble.gd — Bocadillo de gesto sobre un personaje (§14.7): iconos breves, sin muros de texto, a tamaño de pantalla constante.
# PROPIETARIO DE: el gesto visible de su personaje (uno temporal y uno persistente, p. ej. la bombilla de idea).
# ESCUCHA: nada (lo maneja su NPCNode).
class_name NPCBubble
extends Node2D

## Tipos: exclaim (!), question (?), talk (…), idea (bombilla que late), money (moneda),
## report (escudo: va a Seguridad), sleep (dos «Z» trazadas), phone (móvil), eye (vigila). Uno temporal
## (show_emote) tapa al persistente (set_persistent) mientras dura. Se dibuja a la derecha de la
## cabeza para no tapar el indicador de detección. Colores: paleta de la interfaz (alto contraste).

const Z_BUBBLE := RenderingServer.CANVAS_ITEM_Z_MAX - 4
const KIND_EXCLAIM := "exclaim"
const KIND_QUESTION := "question"
const KIND_TALK := "talk"
const KIND_IDEA := "idea"
const KIND_MONEY := "money"
const KIND_REPORT := "report"
const KIND_SLEEP := "sleep"
const KIND_PHONE := "phone"
const KIND_EYE := "eye"
const ICONS: Dictionary = {KIND_MONEY: "coin", KIND_REPORT: "shield", KIND_PHONE: "phone", KIND_EYE: "eye"}
const POP_SECONDS := 0.16
const POP_FROM := 0.55
const BOB_HZ := 1.6
const BOB_PX := 2.0
const SIZE_FACTOR := 1.05
const IDEA_SCALE := 1.4
const CORNER := 0.42
const TAIL_W := 0.34
const OFFSET_X := 1.85
const OFFSET_Y := 0.55
const GLYPH_SCALE := 1.2
const DOT_RADIUS := 0.11
const RAY_COUNT := 5

var _kind: String = ""
var _left: float = 0.0
var _persistent: String = ""
var _age: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = Z_BUBBLE
	visible = false


## Gesto temporal durante `seconds` segundos.
func show_emote(kind: String, seconds: float) -> void:
	if kind != _kind or _left <= 0.0:
		_age = 0.0
	_kind = kind
	_left = seconds
	visible = true
	queue_redraw()


## Gesto persistente ("" lo quita), visible cuando no hay uno temporal.
func set_persistent(kind: String) -> void:
	if kind == _persistent:
		return
	_persistent = kind
	_age = 0.0
	visible = not current_kind().is_empty()
	queue_redraw()


func current_kind() -> String:
	return _kind if _left > 0.0 else _persistent


func clear() -> void:
	_left = 0.0
	_persistent = ""
	visible = false


func _process(delta: float) -> void:
	_time += delta
	_age += delta
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_age = 0.0
	visible = not current_kind().is_empty()
	if not visible:
		return
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x if get_viewport() != null else 1.0
	var pop: float = lerpf(POP_FROM, 1.0, clampf(_age / POP_SECONDS, 0.0, 1.0))
	var s: float = pop / maxf(zoom, 0.01)
	scale = Vector2(s, s)
	queue_redraw()


func _draw() -> void:
	var kind: String = current_kind()
	if kind.is_empty():
		return
	var r: float = DetectionIndicator.base_radius() * SIZE_FACTOR * (IDEA_SCALE if kind == KIND_IDEA else 1.0)
	var bob: float = sin(_time * TAU * BOB_HZ) * BOB_PX if kind == KIND_IDEA else 0.0
	draw_emote(self, Vector2(r * OFFSET_X, -r * OFFSET_Y + bob), r, kind, UITheme.current_high_contrast)


## Dibuja el bocadillo de `kind` centrado en `center` (cola hacia abajo a la izquierda).
static func draw_emote(c: CanvasItem, center: Vector2, r: float, kind: String, high_contrast: bool) -> void:
	var pal: Dictionary = UITheme.palette(high_contrast)
	var ink: Color = Color.BLACK if high_contrast else CharacterStyle.OUTLINE
	var paper: Color = Color.WHITE if high_contrast else Color(pal["paper"])
	var w: float = UITheme.tune("interfaz.indicador_deteccion_contorno") * (1.6 if high_contrast else 1.0)
	if kind == KIND_IDEA:
		_draw_bulb(c, center, r, pal, ink, w)
		return
	var box: Rect2 = Rect2(center - Vector2(r, r * 0.82), Vector2(r * 2.0, r * 1.64))
	var tail: PackedVector2Array = [box.position + Vector2(r * 0.35, box.size.y - w),
			box.position + Vector2(r * 0.35 + r * TAIL_W * 2.0, box.size.y - w),
			box.position + Vector2(-r * 0.25, box.size.y + r * 0.62)]
	c.draw_colored_polygon(UITheme.rounded_rect_points(box.grow(w), r * CORNER + w), ink)
	c.draw_colored_polygon(_grow_tail(tail, w), ink)
	c.draw_colored_polygon(UITheme.rounded_rect_points(box, r * CORNER), paper)
	c.draw_colored_polygon(tail, paper)
	_draw_content(c, center, r, kind, pal, ink, w)


static func _grow_tail(tail: PackedVector2Array, w: float) -> PackedVector2Array:
	var centroid: Vector2 = (tail[0] + tail[1] + tail[2]) / 3.0
	var out: PackedVector2Array = []
	for p: Vector2 in tail:
		out.append(p + (p - centroid).normalized() * w * 1.4)
	return out


static func _draw_content(c: CanvasItem, center: Vector2, r: float, kind: String, pal: Dictionary,
		ink: Color, w: float) -> void:
	match kind:
		KIND_EXCLAIM:
			_glyph(c, center, r, "!", pal["det_flagrant"])
		KIND_QUESTION:
			_glyph(c, center, r, "?", pal["det_partial"].darkened(0.15))
		KIND_TALK:
			for i: int in 3:
				c.draw_circle(center + Vector2((i - 1) * r * 0.55, r * 0.05), r * DOT_RADIUS * 1.6, ink)
		KIND_SLEEP:
			_zed(c, center + Vector2(-r * 0.3, r * 0.15), r * 0.34, ink, w)
			_zed(c, center + Vector2(r * 0.32, -r * 0.22), r * 0.24, ink, w)
		_:
			var icon: String = str(ICONS.get(kind, "info"))
			var side: float = r * 1.3
			UITheme.draw_icon(c, icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)),
					ink, maxf(w * 0.9, 1.5))


## Bombilla de idea (§11.1): ampolla amarilla con casquillo y rayos, sin bocadillo.
static func _draw_bulb(c: CanvasItem, center: Vector2, r: float, pal: Dictionary, ink: Color, w: float) -> void:
	var glow: Color = Color(pal["hazard"])
	for i: int in RAY_COUNT:
		var a: float = -PI * 0.5 + (float(i) - (RAY_COUNT - 1) * 0.5) * 0.55
		var dir: Vector2 = Vector2.from_angle(a)
		c.draw_line(center + dir * r * 0.95, center + dir * r * 1.35, ink, w * 2.2, true)
		c.draw_line(center + dir * r * 0.98, center + dir * r * 1.3, glow, w, true)
	c.draw_circle(center + Vector2(0, -r * 0.1), r * 0.72 + w, ink)
	c.draw_circle(center + Vector2(0, -r * 0.1), r * 0.72, glow)
	c.draw_circle(center + Vector2(-r * 0.22, -r * 0.32), r * 0.18, Color(1, 1, 1, 0.8))
	var base: Rect2 = Rect2(center + Vector2(-r * 0.34, r * 0.5), Vector2(r * 0.68, r * 0.42))
	c.draw_rect(base.grow(w), ink)
	c.draw_rect(base, Color(pal["muted"]))
	c.draw_line(base.position + Vector2(0, base.size.y * 0.5), base.end - Vector2(0, base.size.y * 0.5), ink, w * 0.8)


## «Z» de sueño trazada (sin texto).
static func _zed(c: CanvasItem, center: Vector2, half: float, col: Color, w: float) -> void:
	c.draw_polyline(PackedVector2Array([center + Vector2(-half, -half), center + Vector2(half, -half),
			center + Vector2(-half, half), center + Vector2(half, half)]), col, w * 1.3, true)


static func _glyph(c: CanvasItem, center: Vector2, r: float, text: String, col: Color) -> void:
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var size: int = maxi(8, roundi(r * GLYPH_SCALE))
	var dims: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var base: Vector2 = center + Vector2(-dims.x * 0.5, font.get_ascent(size) * 0.5 - font.get_descent(size) * 0.35)
	c.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
