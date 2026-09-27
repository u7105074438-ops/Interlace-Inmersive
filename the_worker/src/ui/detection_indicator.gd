# detection_indicator.gd — Indicador de detección sobre la cabeza de un personaje (§13.2, §13.10, PASO 12): cuatro estados distinguibles por forma y color, a tamaño de pantalla constante.
# PROPIETARIO DE: nada (dibuja el estado del contador de la Perception a la que se ata).
# ESCUCHA: nada (sondea su Perception cada fotograma; solo redibuja al cambiar).
class_name DetectionIndicator
extends Node2D

## Estados (Perception.STATE_*) y su forma — el color refuerza, nunca es la única pista:
##   sin contacto → ausente.
##   en progreso  → disco oscuro con CUÑA amarilla que crece desde las 12 (muesca creciente) y
##                  una aguja en su borde de avance.
##   parcial      → círculo COMPLETO naranja con «?» (creencia de certeza baja; sin confrontación).
##                  Un arco exterior fino avanza hacia la flagrancia si el contador sigue subiendo.
##   flagrancia   → ESTRELLA de puntas roja con «!» que late (ventana de decisión).
## Siempre con cola hacia la cabeza. Tamaño constante en pantalla (compensa el zoom de cámara):
## radio interfaz.indicador_deteccion_radio px (× escala táctil de UITheme en móvil). Alto
## contraste (ajuste high_contrast → UITheme.current_high_contrast): paleta de alto contraste,
## contorno más grueso, halo blanco y escala interfaz.indicador_deteccion_escala_alto_contraste.
## draw_state() es estática: la reutilizan la leyenda de QA y otras piezas de interfaz.

const Z_INDICATOR := RenderingServer.CANVAS_ITEM_Z_MAX - 3
const BURST_POINTS := 10
const ARC_SEGMENTS := 40
const TAIL_HALF := 0.36
const TAIL_TOP := 0.78
const TAIL_TIP := 1.38
const GLYPH_SCALE := 1.28
const BURST_OUTER := 1.3
const BURST_INNER := 1.02
const PULSE_AMPLITUDE := 0.08
const NEEDLE_REACH := 1.24
const OUTER_ARC_GAP := 0.28
const SHADOW_OFFSET := Vector2(1.5, 2.5)
const SHADOW_ALPHA := 0.35
const BACKDROP_ALPHA := 0.72
const HALO_EXTRA := 2.0

var _perception: Perception = null
var _state: int = Perception.STATE_NONE
var _counter: float = 0.0
var _pulse: float = 0.0
var _contrast: bool = false


func _ready() -> void:
	z_as_relative = false
	z_index = Z_INDICATOR
	visible = false


## Perception cuyo contador representa.
func bind(perception: Perception) -> void:
	_perception = perception


func _process(delta: float) -> void:
	if _perception == null or not is_instance_valid(_perception):
		visible = false
		return
	var state: int = _perception.get_state()
	var counter: float = _perception.get_counter()
	visible = state != Perception.STATE_NONE
	if not visible:
		_state = state
		return
	_compensate_zoom()
	_pulse = fmod(_pulse + delta * UITheme.tune("interfaz.flagrancia_pulso_hz"), 1.0)
	var changed: bool = state != _state or absf(counter - _counter) > 0.004 \
			or UITheme.current_high_contrast != _contrast or state == Perception.STATE_FLAGRANT
	_state = state
	_counter = counter
	_contrast = UITheme.current_high_contrast
	if changed:
		queue_redraw()


## Tamaño constante en pantalla: deshace la escala del lienzo (zoom de la cámara).
func _compensate_zoom() -> void:
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x if get_viewport() != null else 1.0
	var s: float = 1.0 / maxf(zoom, 0.01)
	scale = Vector2(s, s)


func _draw() -> void:
	draw_state(self, Vector2.ZERO, base_radius(), _state, _counter, _contrast, _pulse)


## Radio base en píxeles de pantalla (tamaño de texto táctil y alto contraste incluidos).
static func base_radius() -> float:
	var r: float = UITheme.tune("interfaz.indicador_deteccion_radio")
	if UITheme.touch_scale_active:
		r *= UITheme.tune("interfaz.escala_texto_tactil")
	if UITheme.current_high_contrast:
		r *= UITheme.tune("interfaz.indicador_deteccion_escala_alto_contraste")
	return r


# ─── Dibujo de un estado ─────────────────────────────────────

## Dibuja el indicador en `center` (la cola apunta hacia abajo). `counter` 0..1; pulse 0..1.
static func draw_state(c: CanvasItem, center: Vector2, radius: float, state: int, counter: float,
		high_contrast: bool, pulse: float = 0.0) -> void:
	if state == Perception.STATE_NONE:
		return
	var pal: Dictionary = UITheme.palette(high_contrast)
	var ink: Color = Color.BLACK if high_contrast else CharacterStyle.OUTLINE
	var w: float = UITheme.tune("interfaz.indicador_deteccion_contorno") * (1.6 if high_contrast else 1.0)
	var fill: Color = _state_color(pal, state)
	_draw_tail(c, center, radius, fill, ink, w)
	match state:
		Perception.STATE_PROGRESS:
			_draw_progress(c, center, radius, counter, fill, ink, w, high_contrast)
		Perception.STATE_PARTIAL:
			_draw_partial(c, center, radius, counter, pal, ink, w, high_contrast)
		Perception.STATE_FLAGRANT:
			var r: float = radius * (1.0 + PULSE_AMPLITUDE * sin(pulse * TAU))
			_draw_flagrant(c, center, r, fill, ink, w, high_contrast)


static func _state_color(pal: Dictionary, state: int) -> Color:
	match state:
		Perception.STATE_PARTIAL:
			return pal["det_partial"]
		Perception.STATE_FLAGRANT:
			return pal["det_flagrant"]
	return pal["det_progress"]


static func _draw_tail(c: CanvasItem, center: Vector2, r: float, fill: Color, ink: Color, w: float) -> void:
	var tail: PackedVector2Array = [center + Vector2(-r * TAIL_HALF, r * TAIL_TOP),
			center + Vector2(r * TAIL_HALF, r * TAIL_TOP), center + Vector2(0.0, r * TAIL_TIP)]
	c.draw_colored_polygon(tail, ink)
	var inner: PackedVector2Array = [tail[0].lerp(tail[2], 0.2) + Vector2(w * 0.6, 0.0),
			tail[1].lerp(tail[2], 0.2) - Vector2(w * 0.6, 0.0), tail[2] - Vector2(0.0, w * 1.4)]
	c.draw_colored_polygon(inner, fill)


## En progreso: disco oscuro, cuña amarilla desde las 12 (fracción del umbral parcial) y aguja.
static func _draw_progress(c: CanvasItem, center: Vector2, r: float, counter: float, fill: Color,
		ink: Color, w: float, high_contrast: bool) -> void:
	var partial: float = maxf(Database.get_balance_float("percepcion.umbral_parcial"), 0.01)
	var f: float = clampf(counter / partial, 0.0, 1.0)
	_disc(c, center, r, ink, w, high_contrast)
	c.draw_circle(center, r - w, Color(ink, BACKDROP_ALPHA if not high_contrast else 1.0))
	var start: float = -PI * 0.5
	var end: float = start + TAU * f
	if f > 0.0:
		var pie: PackedVector2Array = [center]
		var steps: int = maxi(2, ceili(ARC_SEGMENTS * f))
		for i: int in steps + 1:
			pie.append(center + Vector2.from_angle(lerpf(start, end, float(i) / steps)) * (r - w))
		c.draw_colored_polygon(pie, fill)
	c.draw_arc(center, r - w * 0.5, 0.0, TAU, ARC_SEGMENTS, fill, w, true)
	var tip: Vector2 = Vector2.from_angle(end)
	c.draw_line(center + tip * r * 0.25, center + tip * r * NEEDLE_REACH, ink, w * 1.8, true)
	c.draw_line(center + tip * r * 0.3, center + tip * r * (NEEDLE_REACH - 0.06), fill, w * 0.8, true)
	c.draw_circle(center, w * 1.1, ink)


## Parcial: círculo completo naranja con «?» y arco exterior hacia la flagrancia.
static func _draw_partial(c: CanvasItem, center: Vector2, r: float, counter: float, pal: Dictionary,
		ink: Color, w: float, high_contrast: bool) -> void:
	var partial: float = Database.get_balance_float("percepcion.umbral_parcial")
	var full: float = Database.get_balance_float("percepcion.umbral_flagrancia")
	var fill: Color = pal["det_partial"]
	_disc(c, center, r, ink, w, high_contrast)
	c.draw_circle(center, r - w, fill)
	var toward: float = clampf((counter - partial) / maxf(full - partial, 0.01), 0.0, 1.0)
	if toward > 0.0:
		var arc_r: float = r + w * 1.5 + r * OUTER_ARC_GAP * 0.5
		c.draw_arc(center, arc_r, -PI * 0.5, -PI * 0.5 + TAU * toward, ARC_SEGMENTS, ink, w * 2.2, true)
		c.draw_arc(center, arc_r, -PI * 0.5, -PI * 0.5 + TAU * toward, ARC_SEGMENTS, pal["det_flagrant"], w, true)
	_glyph(c, center, r, "?", ink, Color.WHITE if high_contrast else Color(ink, 0.0))


## Flagrancia: estrella de puntas roja, disco interior y «!» blanco con contorno.
static func _draw_flagrant(c: CanvasItem, center: Vector2, r: float, fill: Color, ink: Color, w: float,
		high_contrast: bool) -> void:
	var star: PackedVector2Array = []
	for i: int in BURST_POINTS * 2:
		var k: float = BURST_OUTER if i % 2 == 0 else BURST_INNER
		star.append(center + Vector2.from_angle(-PI * 0.5 + PI * i / BURST_POINTS) * r * k)
	if high_contrast:
		c.draw_colored_polygon(_grow(star, center, w * 1.2), Color.WHITE)
	c.draw_colored_polygon(_grow(star, center, w), ink)
	c.draw_colored_polygon(star, fill)
	c.draw_circle(center, r * 0.78, fill.darkened(0.12))
	_glyph(c, center, r, "!", Color.WHITE, ink)


static func _disc(c: CanvasItem, center: Vector2, r: float, ink: Color, w: float, high_contrast: bool) -> void:
	c.draw_circle(center + SHADOW_OFFSET, r + w, Color(0, 0, 0, SHADOW_ALPHA))
	if high_contrast:
		c.draw_circle(center, r + w * HALO_EXTRA, Color.WHITE)
	c.draw_circle(center, r + w * 0.5, ink)


static func _grow(poly: PackedVector2Array, center: Vector2, amount: float) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p: Vector2 in poly:
		out.append(p + (p - center).normalized() * amount)
	return out


## Glifo centrado con la fuente gruesa del tema (con contorno si `outline` es visible).
static func _glyph(c: CanvasItem, center: Vector2, r: float, text: String, col: Color, outline: Color) -> void:
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var size: int = maxi(8, roundi(r * GLYPH_SCALE))
	var dims: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var base: Vector2 = center + Vector2(-dims.x * 0.5, font.get_ascent(size) * 0.5 - font.get_descent(size) * 0.35)
	if outline.a > 0.0:
		c.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, roundi(r * 0.22)), outline)
	c.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
