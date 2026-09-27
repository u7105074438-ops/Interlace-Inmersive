# npc_bubble.gd — Bocadillo de gesto sobre un personaje (§14.7): iconos breves, sin muros de texto, a tamaño de pantalla constante.
# PROPIETARIO DE: el gesto visible de su personaje (uno temporal y uno persistente, p. ej. la bombilla de idea).
# ESCUCHA: nada (lo maneja su NPCNode).
class_name NPCBubble
extends Node2D

## Tipos: exclaim (!), question (?), talk (…), idea (bombilla que late), money (moneda),
## report (escudo: va a Seguridad), sleep (dos «Z» trazadas), phone (móvil), eye (vigila). Uno temporal
## (show_emote) tapa al persistente (set_persistent) mientras dura. Los bocadillos van a la derecha
## de la cabeza (cola hacia ella) para no tapar el indicador de detección; mientras el indicador
## está a la vista (set_indicator_shown) no se muestran «?» ni «!» (el indicador ya los dice). La
## bombilla de idea va centrada SOBRE la cabeza de su dueño con un rabillo que la señala; si el
## indicador está a la vista, se apila encima de él. Colores: paleta de la interfaz (alto contraste).

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
## Bombilla (en radios del indicador): punta del rabillo sobre la coronilla (o sobre el borde
## superior del indicador si está a la vista) y largo del rabillo.
const IDEA_TIP := 0.2
const IDEA_STACK_TIP := 1.12
const IDEA_STEM := 0.6
const MARK_KINDS: Array[String] = [KIND_EXCLAIM, KIND_QUESTION]

var _kind: String = ""
var _left: float = 0.0
var _persistent: String = ""
var _age: float = 0.0
var _time: float = 0.0
var _indicator_shown: bool = false
var _drawn_kind: String = ""
var _contrast: bool = false


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


## El indicador de detección de su personaje está a la vista (oculta «?» y «!», apila la bombilla).
func set_indicator_shown(shown: bool) -> void:
	if shown != _indicator_shown:
		_indicator_shown = shown
		queue_redraw()


func current_kind() -> String:
	if _left > 0.0 and not (_indicator_shown and MARK_KINDS.has(_kind)):
		return _kind
	return _persistent


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
	if not is_equal_approx(scale.x, s):
		scale = Vector2(s, s)
	var kind: String = current_kind()
	if kind == KIND_IDEA or kind != _drawn_kind or _contrast != UITheme.current_high_contrast:
		queue_redraw()


## Bocadillo actual en pantalla (lo que el último _draw dibujó; "" si nada). Tests / QA.
func shown_kind() -> String:
	return _drawn_kind if visible else ""


func _draw() -> void:
	var kind: String = current_kind()
	_drawn_kind = kind
	_contrast = UITheme.current_high_contrast
	if kind.is_empty():
		return
	var ind_r: float = DetectionIndicator.base_radius()
	var ind_y: float = -ind_r * DetectionIndicator.ANCHOR_LIFT
	var r: float = ind_r * SIZE_FACTOR
	if kind == KIND_IDEA:
		var bulb_r: float = r * IDEA_SCALE
		var tip_y: float = ind_y - ind_r * IDEA_STACK_TIP if _indicator_shown else -ind_r * IDEA_TIP
		var bob: float = sin(_time * TAU * BOB_HZ) * BOB_PX
		var center: Vector2 = Vector2(0.0, tip_y - ind_r * IDEA_STEM - bulb_r * 0.95 + bob)
		draw_idea(self, center, bulb_r, tip_y - center.y, UITheme.current_high_contrast)
		return
	draw_emote(self, Vector2(r * OFFSET_X, ind_y - r * OFFSET_Y), r, kind, UITheme.current_high_contrast)


## Bombilla centrada en `center` con un rabillo de `stem` px hacia la cabeza (el origen).
static func draw_idea(c: CanvasItem, center: Vector2, r: float, stem: float, high_contrast: bool) -> void:
	var pal: Dictionary = UITheme.palette(high_contrast)
	var ink: Color = Color.BLACK if high_contrast else CharacterStyle.OUTLINE
	var w: float = UITheme.tune("interfaz.indicador_deteccion_contorno") * (1.6 if high_contrast else 1.0)
	var tip: Vector2 = center + Vector2(0.0, stem)
	var base_y: float = center.y + r * 0.95
	if tip.y > base_y + w:
		var tail: PackedVector2Array = [Vector2(-r * TAIL_W, base_y), Vector2(r * TAIL_W, base_y), tip]
		c.draw_colored_polygon(_grow_tail(tail, w), ink)
		c.draw_colored_polygon(tail, Color(pal["hazard"]))
	_draw_bulb(c, center, r, pal, ink, w)


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
