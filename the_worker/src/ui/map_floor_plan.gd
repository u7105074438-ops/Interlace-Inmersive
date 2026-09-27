# map_floor_plan.gd — Plano de una planta como «plano de evacuación» (zoom del mapa) y kit de dibujo del mapa.
# PROPIETARIO DE: nada (dibujo puro: el plano lo calcula FloorLayout y el modelo de acceso lo entrega MapView).
# ESCUCHA: nada.
class_name MapFloorPlan
extends Control

## Uso (MapView): show_floor(floor, model). model = {
##   plan: Dictionary (opcional; si falta se calcula con FloorLayout.compute), statuses: {room_id: ACCESS_*},
##   methods: {room_id: método alternativo}, layers: {cameras, routes, occupancy: bool}, band: franja,
##   dots: [{npc_id, name, floor, room_id, target, approximate}], player_floor: int, player_room: String,
##   player_cell: Vector2 (celdas de planta; Vector2.INF = desconocida)}.
## Dibuja salas con el tinte y la trama de acceso (forma además de color, §13.10), mobiliario en trazo
## fino, muros negros con puertas y barrido, ascensores (aspa), escaleras (peldaños), flechas verdes de
## evacuación siempre paralelas al eje (nunca en diagonal), extintores, nombres sobre placa de papel,
## «USTED ESTÁ AQUÍ», norte y escala. Capas: cámaras (cono de datos camaras.alcance/angulo recortado a
## su sala con Geometry2D, en tinta translúcida mapa.cono_alfa*), rutas alternativas (trampillas y
## conductos, cerraduras antiguas, escalera de servicio, cornisas) y ocupación por franja
## (occupants_by_band: una pastilla figura + número por sala). Los objetivos se dibujan los últimos
## con mira y etiqueta de nombre; los conocidos, con un punto de radio mínimo ligado a la letra base.
## El kit estático (palette, draw_status_block, draw_hatch, draw_running_man, draw_exit_sign,
## draw_arrow, draw_pin, draw_callout, draw_npc_dot, draw_target_marker, draw_tag, draw_people_badge,
## draw_helicopter, draw_person, draw_vent, draw_extinguisher) lo comparte el corte de MapView.

signal room_hovered(room_id: String)
signal room_clicked(room_id: String)

const ACCESS_ALLOWED := 0
const ACCESS_ALTERNATIVE := 1
const ACCESS_FORBIDDEN := 2
const LAYER_CAMERAS := "cameras"
const LAYER_ROUTES := "routes"
const LAYER_OCCUPANCY := "occupancy"
const HATCH_SLASH := 0
const HATCH_BACKSLASH := 1
const EVAC_KINDS: Array[String] = ["stairs", "service_stairs", "exit"]
const SHAFT_KINDS: Array[String] = ["elevator", "freight"]
const STEP_KINDS: Array[String] = ["stairs", "service_stairs"]
const ENTRY_ROOF_LEDGE := "roof_ledge"
const LEDGE_TYPE := "roof_ledge"
const FINISH_KEYS: Array[String] = ["floor", "carpet", "wall", "accent", "furniture"]
const KEY_FULL_WIDTH := "full_floor_width"
const NO_CELL := Vector2i(-1, -1)
## Maquetación del dibujo (proporciones en celdas o fracciones; diseño, no balance).
const PAD := 18.0
const WALL_RATIO := 0.22
const NAME_CELL_RATIO := 0.95
const NAME_MIN_RATIO := 0.64
const NAME_FLOOR_RATIO := 0.5
const NAME_MAX_RATIO := 0.92
const EVAC_STEP_CELLS := 7.0
const EVAC_MIN_CELLS := 3.0
const EVAC_LEN_CELLS := 2.2
const STEP_SPACING_CELLS := 0.7
const DOT_RATIO := 0.42
const DOT_MIN_RATIO := 0.3
const DOT_MAX_RATIO := 0.55
const SCALE_BAR_CELLS := 10
const HATCH_PLAN_CELLS := 0.9
const DASH_CELLS := 0.6
const ARC_SEGMENTS := 10
const FIT_MARGIN_CELLS := 1.5
const INK_MAX_LUMINANCE := 0.42
const FURNITURE_MIN_CELLS := 2
const LABEL_HIGH_RATIO := 0.36
const BADGE_RATIO := 0.62
const TAG_RATIO := 0.66
const PLATE_ALPHA := 0.9
const B_CONE_ALPHA := "mapa.cono_alfa"
const B_CONE_EDGE_ALPHA := "mapa.cono_alfa_borde"
const B_CAM_REACH := "camaras.alcance"
const B_CAM_ANGLE := "camaras.angulo"

const PAL_NORMAL: Dictionary = {
	"paper": Color("#f8f5ed"), "paper_shade": Color("#ece6d8"), "white": Color("#ffffff"),
	"ink": Color("#1d2024"), "ink_soft": Color("#676b72"), "ink_faint": Color("#b3ada1"),
	"red": Color("#c9252c"), "red_dark": Color("#971a1f"), "green": Color("#12854c"),
	"green_dark": Color("#0b6437"), "amber": Color("#e5920c"), "amber_dark": Color("#b56d05"),
	"allowed_fill": Color("#cbead4"), "alt_fill": Color("#fde2ad"), "forbidden_fill": Color("#f6caca"),
	"allowed_ink": Color("#1c8a4b"), "alt_ink": Color("#d0820f"), "forbidden_ink": Color("#c7343a"),
	"earth": Color("#e6dccb"), "earth_line": Color("#cdbfa6"), "concrete": Color("#d7d2c7"),
	"dot": Color("#22418f"), "dot_edge": Color("#ffffff"), "people": Color("#6a45a8"),
	"camera": Color("#2a2d33"), "shadow": Color(0.0, 0.0, 0.0, 0.10), "target": Color("#c8127a"),
	"select": Color("#1d2024"),
}
const PAL_CONTRAST: Dictionary = {
	"paper": Color("#ffffff"), "paper_shade": Color("#e8e8e8"), "white": Color("#ffffff"),
	"ink": Color("#000000"), "ink_soft": Color("#303030"), "ink_faint": Color("#8a8a8a"),
	"red": Color("#d10000"), "red_dark": Color("#8c0000"), "green": Color("#007a33"),
	"green_dark": Color("#004d20"), "amber": Color("#f59b00"), "amber_dark": Color("#9c5a00"),
	"allowed_fill": Color("#9fe0b4"), "alt_fill": Color("#ffd27a"), "forbidden_fill": Color("#ff9d9d"),
	"allowed_ink": Color("#006b2e"), "alt_ink": Color("#a35f00"), "forbidden_ink": Color("#b00000"),
	"earth": Color("#d9ccb3"), "earth_line": Color("#a8966f"), "concrete": Color("#bdbdbd"),
	"dot": Color("#0030a0"), "dot_edge": Color("#ffffff"), "people": Color("#5a1fb0"),
	"camera": Color("#000000"), "shadow": Color(0.0, 0.0, 0.0, 0.18), "target": Color("#b0006a"),
	"select": Color("#000000"),
}

var _floor: int = 0
var _plan: Dictionary = {}
var _model: Dictionary = {}
var _scale: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _hover: String = ""


func _init() -> void:
	name = "MapFloorPlan"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


# ─── API ───────────────────────────────────────────────────────────

func show_floor(floor_number: int, model: Dictionary) -> void:
	_floor = floor_number
	var given: Variant = model.get("plan", {})
	_plan = given if given is Dictionary and not (given as Dictionary).is_empty() else FloorLayout.compute(floor_number)
	_model = model
	_hover = ""
	queue_redraw()


## Sustituye el modelo (capas, franja, puntos) sin recalcular el plano.
func set_model(model: Dictionary) -> void:
	_model = model
	queue_redraw()


func get_floor() -> int:
	return _floor


func get_plan() -> Dictionary:
	return _plan


## Salas dibujadas, en el orden de colocación de FloorLayout.
func get_room_ids() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in _plan.get("order", []):
		out.append(str(id))
	return out


func get_hovered_room() -> String:
	return _hover


## Sala bajo un punto local ("" si ninguna).
func room_at(local_pos: Vector2) -> String:
	if _plan.is_empty():
		return ""
	_fit()
	var cell: Vector2 = (local_pos - _origin) / _scale
	var rooms: Dictionary = _plan.get("rooms", {})
	var ids: Array[String] = get_room_ids()
	for i: int in range(ids.size() - 1, -1, -1):
		if Rect2(rooms[ids[i]]).has_point(cell):
			return ids[i]
	return ""


## Rectángulo local (px) de una sala del plano (Rect2() si no está).
func room_rect(room_id: String) -> Rect2:
	var rooms: Dictionary = _plan.get("rooms", {})
	if not rooms.has(room_id):
		return Rect2()
	_fit()
	return _cell_rect(rooms[room_id])


# ─── Kit de dibujo compartido (estático) ───────────────────────────

static func palette() -> Dictionary:
	return PAL_CONTRAST if UITheme.current_high_contrast else PAL_NORMAL


## Relleno de un estado de acceso (tinte claro).
static func status_fill(status: int, pal: Dictionary) -> Color:
	match status:
		ACCESS_ALLOWED:
			return pal["allowed_fill"]
		ACCESS_ALTERNATIVE:
			return pal["alt_fill"]
	return pal["forbidden_fill"]


## Tinta de un estado de acceso (saturada: bordes, tramas, chapas).
static func status_ink(status: int, pal: Dictionary) -> Color:
	match status:
		ACCESS_ALLOWED:
			return pal["allowed_ink"]
		ACCESS_ALTERNATIVE:
			return pal["alt_ink"]
	return pal["forbidden_ink"]


## Clave de texto del estado.
static func status_key(status: int) -> String:
	match status:
		ACCESS_ALLOWED:
			return "MAP_ACCESS_ALLOWED"
		ACCESS_ALTERNATIVE:
			return "MAP_ACCESS_ALTERNATIVE"
	return "MAP_ACCESS_FORBIDDEN"


## Bloque de acceso: tinte + trama por forma (verde liso, ámbar rayado «/», rojo en retícula).
static func draw_status_block(ci: CanvasItem, rect: Rect2, status: int, pal: Dictionary, spacing: float,
		line_w: float) -> void:
	ci.draw_rect(rect, status_fill(status, pal))
	var ink: Color = status_ink(status, pal)
	if status == ACCESS_ALTERNATIVE:
		draw_hatch(ci, rect, Color(ink, 0.55), spacing, line_w, HATCH_SLASH)
	elif status == ACCESS_FORBIDDEN:
		draw_hatch(ci, rect, Color(ink, 0.3), spacing * 1.2, line_w, HATCH_SLASH)
		draw_hatch(ci, rect, Color(ink, 0.3), spacing * 1.2, line_w, HATCH_BACKSLASH)


## Trama de líneas a 45° recortadas al rectángulo (una sola llamada de dibujo).
static func draw_hatch(ci: CanvasItem, rect: Rect2, col: Color, spacing: float, line_w: float, dir: int) -> void:
	if spacing <= 0.0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	var step: float = spacing * sqrt(2.0)
	var slash: bool = dir == HATCH_SLASH
	var c0: float = rect.position.x + rect.position.y if slash else rect.position.y - rect.end.x
	var c1: float = rect.end.x + rect.end.y if slash else rect.end.y - rect.position.x
	var c: float = c0 + step * 0.5
	while c < c1:
		var seg: PackedVector2Array = _hatch_segment(rect, c, slash)
		if seg.size() == 2:
			pts.append_array(seg)
		c += step
	if not pts.is_empty():
		ci.draw_multiline(pts, col, line_w, true)


static func _hatch_segment(rect: Rect2, c: float, slash: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var x0: float = maxf(rect.position.x, c - rect.end.y) if slash else maxf(rect.position.x, rect.position.y - c)
	var x1: float = minf(rect.end.x, c - rect.position.y) if slash else minf(rect.end.x, rect.end.y - c)
	if x1 <= x0:
		return out
	out.append(Vector2(x0, c - x0 if slash else x0 + c))
	out.append(Vector2(x1, c - x1 if slash else x1 + c))
	return out


## Pictograma del hombre corriendo (señal de salida ISO 7010) dentro de `r`.
static func draw_running_man(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var w: float = maxf(1.5, r.size.y * 0.1)
	ci.draw_circle(_u(r, 0.63, 0.13), r.size.y * 0.1, col)
	var limbs: Array = [
		[0.58, 0.3, 0.44, 0.58], [0.56, 0.34, 0.74, 0.44, 0.86, 0.36], [0.54, 0.33, 0.35, 0.36, 0.24, 0.5],
		[0.44, 0.58, 0.62, 0.72, 0.6, 0.94], [0.44, 0.58, 0.31, 0.77, 0.12, 0.8],
	]
	for limb: Array in limbs:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, limb.size(), 2):
			pts.append(_u(r, float(limb[i]), float(limb[i + 1])))
		ci.draw_polyline(pts, col, w, true)
		for p: Vector2 in pts:
			ci.draw_circle(p, w * 0.5, col)


## Señal verde de salida: hombre corriendo, puerta y flecha (izquierda si `left`).
static func draw_exit_sign(ci: CanvasItem, r: Rect2, pal: Dictionary, left: bool = false) -> void:
	var radius: float = r.size.y * 0.12
	ci.draw_polygon(UITheme.rounded_rect_points(r, radius), PackedColorArray([pal["green"]]))
	var pad: float = r.size.y * 0.14
	var inner: Rect2 = r.grow(-pad)
	var white: Color = pal["white"]
	var fig_w: float = inner.size.y * 0.9
	var door: Rect2 = Rect2(inner.end.x - inner.size.y * 0.55, inner.position.y, inner.size.y * 0.55, inner.size.y)
	var man: Rect2 = Rect2(door.position.x - fig_w * 0.95, inner.position.y, fig_w, inner.size.y)
	if left:
		door.position.x = inner.position.x
		man.position.x = door.end.x + fig_w * 0.05
	ci.draw_rect(door, white, false, maxf(1.5, r.size.y * 0.07))
	draw_running_man(ci, man, white)
	var arrow_w: float = inner.size.x - door.size.x - fig_w
	if arrow_w > inner.size.y * 0.5:
		var ax: float = man.end.x + arrow_w * 0.1 if left else inner.position.x
		var a_rect: Rect2 = Rect2(ax, inner.position.y + inner.size.y * 0.2, arrow_w * 0.8, inner.size.y * 0.6)
		var tip: Vector2 = Vector2(a_rect.position.x if left else a_rect.end.x, a_rect.get_center().y)
		var tail: Vector2 = Vector2(a_rect.end.x if left else a_rect.position.x, a_rect.get_center().y)
		draw_arrow(ci, tail, tip, white, a_rect.size.y * 0.32, a_rect.size.y * 0.95)


## Flecha maciza (asta + punta) de `from` a `to`.
static func draw_arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, shaft_w: float, head: float) -> void:
	var d: Vector2 = to - from
	if d.length() < 0.001:
		return
	var n: Vector2 = d.normalized()
	var side: Vector2 = Vector2(-n.y, n.x)
	var head_len: float = minf(head, d.length() * 0.7)
	var base: Vector2 = to - n * head_len
	ci.draw_line(from, base + n * 0.5, col, shaft_w, true)
	var tri: PackedVector2Array = PackedVector2Array([to, base + side * head * 0.55, base - side * head * 0.55])
	ci.draw_colored_polygon(tri, col)


## Chincheta roja «usted está aquí».
static func draw_pin(ci: CanvasItem, pos: Vector2, radius: float, pal: Dictionary) -> void:
	ci.draw_circle(pos + Vector2(radius * 0.15, radius * 0.2), radius * 1.15, pal["shadow"])
	ci.draw_circle(pos, radius * 1.18, pal["white"])
	ci.draw_circle(pos, radius, pal["red"])
	ci.draw_circle(pos, radius * 0.38, pal["white"])


## Cartela con texto blanco sobre rojo unida a `anchor` por una línea guía. Devuelve el rectángulo.
static func draw_callout(ci: CanvasItem, anchor: Vector2, box_pos: Vector2, text: String, font: Font,
		font_size: int, pal: Dictionary) -> Rect2:
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad: Vector2 = Vector2(font_size * 0.55, font_size * 0.3)
	var box: Rect2 = Rect2(box_pos, ts + pad * 2.0)
	var near: Vector2 = Vector2(clampf(anchor.x, box.position.x, box.end.x), clampf(anchor.y, box.position.y, box.end.y))
	ci.draw_line(anchor, near, pal["red_dark"], maxf(1.5, font_size * 0.1), true)
	ci.draw_polygon(UITheme.rounded_rect_points(box.grow(1.5), font_size * 0.3), PackedColorArray([pal["white"]]))
	ci.draw_polygon(UITheme.rounded_rect_points(box, font_size * 0.28), PackedColorArray([pal["red"]]))
	var baseline: float = box.position.y + pad.y + font.get_ascent(font_size)
	ci.draw_string(font, Vector2(box.position.x + pad.x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, pal["white"])
	return box


## Punto de personaje conocido (azul con borde blanco); un objetivo usa la mira (draw_target_marker).
static func draw_npc_dot(ci: CanvasItem, pos: Vector2, radius: float, pal: Dictionary, target: bool,
		approximate: bool) -> void:
	if target:
		draw_target_marker(ci, pos, radius, pal, approximate)
		return
	var edge: float = maxf(1.2, radius * 0.3)
	if approximate:
		_dashed_ring(ci, pos, radius * 1.2, pal["dot"], edge)
		ci.draw_circle(pos, radius * 0.55, pal["dot"])
		return
	ci.draw_circle(pos, radius + edge, pal["dot_edge"])
	ci.draw_circle(pos, radius, pal["dot"])


## Objetivo marcado: mira de tinta sobre disco blanco con centro magenta (se lee sobre cualquier
## color de acceso, §14.2 silueta antes que detalle). Aproximado = aro discontinuo (puesto habitual).
static func draw_target_marker(ci: CanvasItem, pos: Vector2, radius: float, pal: Dictionary, approximate: bool) -> void:
	var r: float = radius * 1.9
	var w: float = maxf(1.5, radius * 0.34)
	ci.draw_circle(pos + Vector2(w, w) * 0.6, r + w, pal["shadow"])
	ci.draw_circle(pos, r + w, pal["white"])
	var ticks: PackedVector2Array = PackedVector2Array()
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		ticks.append_array([pos + dir * r * 0.45, pos + dir * (r + w * 2.2)])
	ci.draw_multiline(ticks, pal["white"], w * 2.4)
	ci.draw_multiline(ticks, pal["ink"], w)
	if approximate:
		_dashed_ring(ci, pos, r * 0.78, pal["ink"], w)
	else:
		ci.draw_arc(pos, r * 0.78, 0.0, TAU, 24, pal["ink"], w, true)
	ci.draw_circle(pos, r * 0.36, pal["target"])


## Tamaño de una etiqueta de nombre (draw_tag) para colocarla antes de dibujarla.
static func tag_size(text: String, font: Font, font_size: int) -> Vector2:
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(ts.x + font_size * 1.9, font_size * 1.55)


## Etiqueta de objetivo: placa de tinta con mira magenta y nombre en blanco, unida al punto.
static func draw_tag(ci: CanvasItem, anchor: Vector2, box: Rect2, text: String, font: Font, font_size: int,
		pal: Dictionary) -> void:
	var near: Vector2 = Vector2(clampf(anchor.x, box.position.x, box.end.x), clampf(anchor.y, box.position.y, box.end.y))
	ci.draw_line(anchor, near, pal["white"], maxf(3.0, font_size * 0.26), true)
	ci.draw_line(anchor, near, pal["ink"], maxf(1.5, font_size * 0.1), true)
	ci.draw_polygon(UITheme.rounded_rect_points(box.grow(1.5), font_size * 0.3), PackedColorArray([pal["white"]]))
	ci.draw_polygon(UITheme.rounded_rect_points(box, font_size * 0.28), PackedColorArray([pal["ink"]]))
	var c: Vector2 = Vector2(box.position.x + font_size * 0.72, box.get_center().y)
	ci.draw_arc(c, font_size * 0.36, 0.0, TAU, 16, pal["white"], maxf(1.2, font_size * 0.1), true)
	ci.draw_circle(c, font_size * 0.16, pal["target"])
	var baseline: float = box.get_center().y + font.get_ascent(font_size) * 0.36
	ci.draw_string(font, Vector2(box.position.x + font_size * 1.3, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, pal["white"])


## Pastilla de ocupación: figura + número (una por sala; legible aunque la sala sea pequeña).
static func people_badge_size(count: int, font: Font, font_size: int) -> Vector2:
	var tw: float = font.get_string_size(str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Vector2(tw + font_size * 1.55, font_size * 1.35)


static func draw_people_badge(ci: CanvasItem, box: Rect2, count: int, font: Font, font_size: int, pal: Dictionary) -> void:
	ci.draw_polygon(UITheme.rounded_rect_points(box.grow(1.0), box.size.y * 0.5), PackedColorArray([pal["white"]]))
	ci.draw_polygon(UITheme.rounded_rect_points(box, box.size.y * 0.5), PackedColorArray([pal["people"]]))
	draw_person(ci, Vector2(box.position.x + box.size.y * 0.5, box.get_center().y + box.size.y * 0.04), box.size.y * 0.66, pal["white"])
	var baseline: float = box.get_center().y + font.get_ascent(font_size) * 0.36
	ci.draw_string(font, Vector2(box.position.x + box.size.y * 0.86, baseline), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, pal["white"])


## Helicóptero de la dirección aparcado en la azotea (silueta lateral dentro de `r`).
static func draw_helicopter(ci: CanvasItem, r: Rect2, col: Color, glass: Color) -> void:
	var w: float = maxf(1.2, r.size.y * 0.07)
	var body: PackedVector2Array = UITheme.ellipse_points(_u(r, 0.36, 0.56), r.size.x * 0.24, r.size.y * 0.24, 18)
	ci.draw_colored_polygon(body, col)
	ci.draw_colored_polygon(UITheme.ellipse_points(_u(r, 0.26, 0.5), r.size.x * 0.09, r.size.y * 0.13, 12), glass)
	ci.draw_colored_polygon(PackedVector2Array([_u(r, 0.52, 0.46), _u(r, 0.94, 0.5), _u(r, 0.94, 0.58), _u(r, 0.52, 0.66)]), col)
	ci.draw_colored_polygon(PackedVector2Array([_u(r, 0.88, 0.26), _u(r, 0.97, 0.26), _u(r, 0.96, 0.56), _u(r, 0.9, 0.56)]), col)
	ci.draw_line(_u(r, 0.36, 0.3), _u(r, 0.36, 0.2), col, w * 1.4)
	ci.draw_line(_u(r, 0.0, 0.18), _u(r, 0.74, 0.18), col, w * 1.3, true)
	for x: float in [0.22, 0.5]:
		ci.draw_line(_u(r, x, 0.78), _u(r, x, 0.92), col, w)
	ci.draw_line(_u(r, 0.1, 0.94), _u(r, 0.62, 0.94), col, w * 1.3, true)


static func _dashed_ring(ci: CanvasItem, pos: Vector2, radius: float, col: Color, w: float) -> void:
	var segments: int = 10
	for i: int in segments:
		var a0: float = TAU * float(i) / float(segments)
		ci.draw_arc(pos, radius, a0, a0 + TAU / float(segments) * 0.55, 4, col, w, true)


## Figurita (cabeza y hombros) para la ocupación.
static func draw_person(ci: CanvasItem, center: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(center + Vector2(0.0, -s * 0.28), s * 0.2, col)
	var body: PackedVector2Array = UITheme.ellipse_points(center + Vector2(0.0, s * 0.3), s * 0.36, s * 0.28, 12)
	var half: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in body:
		if p.y <= center.y + s * 0.3:
			half.append(p)
	if half.size() >= 3:
		ci.draw_colored_polygon(half, col)


## Rejilla de conducto (ámbar).
static func draw_vent(ci: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	ci.draw_rect(r, Color(col, 0.25))
	ci.draw_rect(r, col, false, w)
	for i: int in range(1, 4):
		var y: float = r.position.y + r.size.y * float(i) / 4.0
		ci.draw_line(Vector2(r.position.x + w, y), Vector2(r.end.x - w, y), col, w * 0.8)


## Extintor (cilindro rojo con boquilla).
static func draw_extinguisher(ci: CanvasItem, pos: Vector2, s: float, pal: Dictionary) -> void:
	var body: Rect2 = Rect2(pos + Vector2(-s * 0.22, -s * 0.3), Vector2(s * 0.44, s * 0.8))
	ci.draw_polygon(UITheme.rounded_rect_points(body, s * 0.16), PackedColorArray([pal["red"]]))
	ci.draw_line(pos + Vector2(0.0, -s * 0.3), pos + Vector2(0.0, -s * 0.48), pal["ink"], maxf(1.0, s * 0.1))
	ci.draw_line(pos + Vector2(0.0, -s * 0.46), pos + Vector2(s * 0.3, -s * 0.38), pal["ink"], maxf(1.0, s * 0.1))


## Línea discontinua.
static func draw_dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var length: float = a.distance_to(b)
	if length <= 0.0 or dash <= 0.0:
		return
	var n: Vector2 = (b - a) / length
	var pts: PackedVector2Array = PackedVector2Array()
	var t: float = 0.0
	while t < length:
		pts.append(a + n * t)
		pts.append(a + n * minf(t + dash, length))
		t += dash * 2.0
	ci.draw_multiline(pts, col, w, true)


## Texto centrado en un punto (una línea).
static func draw_centered(ci: CanvasItem, font: Font, center: Vector2, text: String, font_size: int, col: Color) -> void:
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline: float = center.y - ts.y * 0.5 + font.get_ascent(font_size)
	ci.draw_string(font, Vector2(center.x - ts.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Sala de circulación (pasillo de ancho completo, ascensor, escalera, montacargas): sin tinte de acceso.
static func is_circulation(room: RoomData) -> bool:
	if room == null:
		return false
	return not FloorLayout.transit_kind_of(room).is_empty() or bool(room.extra.get(KEY_FULL_WIDTH, false))


static func _u(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(r.size.x * x, r.size.y * y)


# ─── Geometría ─────────────────────────────────────────────────────

## Encaja el contorno de las salas (más un margen) en el área útil, dejando sitio a norte y escala.
func _fit() -> void:
	var bounds: Rect2 = _room_bounds().grow(FIT_MARGIN_CELLS)
	var reserve: float = float(_base_size()) * 1.6
	var avail: Rect2 = Rect2(Vector2(PAD, PAD), size - Vector2(PAD * 2.0, PAD * 2.0 + reserve))
	_scale = maxf(0.01, minf(avail.size.x / maxf(bounds.size.x, 1.0), avail.size.y / maxf(bounds.size.y, 1.0)))
	_origin = avail.position + (avail.size - bounds.size * _scale) * 0.5 - bounds.position * _scale


func _room_bounds() -> Rect2:
	var out: Rect2 = Rect2()
	var first: bool = true
	for r: Variant in (_plan.get("rooms", {}) as Dictionary).values():
		out = Rect2(r as Rect2i) if first else out.merge(Rect2(r as Rect2i))
		first = false
	return out if not first else Rect2(Vector2.ZERO, Vector2(_plan.get("size", Vector2i.ONE)))


func _cell_rect(r: Rect2i) -> Rect2:
	return Rect2(_origin + Vector2(r.position) * _scale, Vector2(r.size) * _scale)


func _cell_pt(c: Vector2) -> Vector2:
	return _origin + c * _scale


func _center_of(cell: Vector2i) -> Vector2:
	return _cell_pt(Vector2(cell) + Vector2(0.5, 0.5))


func _layer(layer: String) -> bool:
	return bool((_model.get("layers", {}) as Dictionary).get(layer, false))


func _status(room_id: String) -> int:
	return int((_model.get("statuses", {}) as Dictionary).get(room_id, ACCESS_FORBIDDEN))


func _base_size() -> int:
	return base_font_of(self)


## Tamaño base de letra del tema heredado (UIRoot); sin tema propio, el de UITheme vigente.
static func base_font_of(ctrl: Control) -> int:
	var theme_size: int = ctrl.get_theme_default_font_size()
	return theme_size if theme_size > ThemeDB.fallback_font_size else UITheme.base_font_size(UITheme.current_text_size)


func _wall_w() -> float:
	return maxf(2.0, _scale * WALL_RATIO) * (1.5 if UITheme.current_high_contrast else 1.0)


# ─── Dibujo ────────────────────────────────────────────────────────

func _draw() -> void:
	if _plan.is_empty() or (_plan.get("rooms", {}) as Dictionary).is_empty():
		return
	_fit()
	var pal: Dictionary = palette()
	_draw_rooms(pal)
	_draw_furniture(pal)
	_draw_walls(pal)
	_draw_doors(pal)
	_draw_transit(pal)
	_draw_evacuation(pal)
	if _layer(LAYER_CAMERAS):
		_draw_cameras(pal)
	if _layer(LAYER_ROUTES):
		_draw_routes(pal)
	_draw_names(pal)
	if _layer(LAYER_OCCUPANCY):
		_draw_occupancy(pal)
	_draw_dots(pal)
	_draw_hover(pal)
	_draw_targets(pal)
	_draw_player(pal)
	_draw_compass(pal)


func _draw_rooms(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var shadow_off: Vector2 = Vector2(_scale, _scale) * 0.35
	for id: String in get_room_ids():
		draw_rect(Rect2(_cell_rect(rooms[id]).position + shadow_off, _cell_rect(rooms[id]).size), pal["shadow"])
	var line_w: float = maxf(1.0, _scale * 0.06)
	for id: String in get_room_ids():
		var r: Rect2 = _cell_rect(rooms[id])
		if is_circulation(Database.get_room(id)):
			draw_rect(r, pal["white"])
		else:
			draw_status_block(self, r, _status(id), pal, _scale * HATCH_PLAN_CELLS, line_w)


## Mobiliario en planta, en trazo fino (los planos de evacuación muestran puestos y mesas; los
## objetos de una celda —papeleras, plantas, carteles— se omiten).
func _draw_furniture(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var fill: Color = Color(pal["white"], 0.55)
	var line: Color = Color(pal["ink_soft"], 0.55)
	var w: float = maxf(1.0, _scale * 0.06)
	for id: String in get_room_ids():
		var room: RoomData = Database.get_room(id)
		if room == null or is_circulation(room):
			continue
		var origin: Vector2i = (rooms[id] as Rect2i).position
		for entry: Dictionary in FloorLayout.furniture_of(_plan, room):
			var fp: Rect2i = FurniturePainter.footprint(entry)
			if fp.get_area() < FURNITURE_MIN_CELLS:
				continue
			var r: Rect2 = _cell_rect(Rect2i(origin + fp.position, fp.size)).grow(-_scale * 0.08)
			draw_rect(r, fill)
			draw_rect(r, line, false, w)


func _draw_walls(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	for id: String in get_room_ids():
		draw_rect(_cell_rect(rooms[id]), pal["ink"], false, _wall_w())


func _draw_doors(pal: Dictionary) -> void:
	for door: Dictionary in _plan.get("doors", []):
		if str(door.get("kind", "")) == FloorLayout.DOOR_VENT:
			continue
		var hinge: Vector2 = _cell_pt(Vector2(door["cell"] as Vector2i))
		var span: float = float(door.get("width", 1)) * _scale
		var along: Vector2 = Vector2(0.0, 1.0) if bool(door["vertical"]) else Vector2(1.0, 0.0)
		draw_line(hinge + along * _wall_w() * 0.4, hinge + along * (span - _wall_w() * 0.4), pal["white"], _wall_w() + 2.0)
		var into: Vector2 = _door_into(door)
		var leaf: Vector2 = hinge + into * span * 0.92
		draw_line(hinge, leaf, pal["ink"], maxf(1.2, _wall_w() * 0.45), true)
		draw_arc(hinge, span * 0.92, along.angle(), into.angle(), ARC_SEGMENTS, pal["ink_soft"], maxf(1.0, _wall_w() * 0.25), true)
		if str(door.get("kind", "")) == FloorLayout.DOOR_READER:
			var reader: Rect2 = Rect2(hinge - into * _scale * 0.5 - Vector2(_scale, _scale) * 0.18, Vector2(_scale, _scale) * 0.36)
			draw_rect(reader, pal["ink"])


## Sentido hacia la sala b (la hoja abre hacia dentro de la sala a la que se entra).
func _door_into(door: Dictionary) -> Vector2:
	var rooms: Dictionary = _plan["rooms"]
	var cell: Vector2i = door["cell"]
	if not rooms.has(str(door["b"])):
		return Vector2(1.0, 0.0) if bool(door["vertical"]) else Vector2(0.0, 1.0)
	var b: Rect2i = rooms[str(door["b"])]
	if bool(door["vertical"]):
		return Vector2(1.0, 0.0) if b.position.x >= cell.x else Vector2(-1.0, 0.0)
	return Vector2(0.0, 1.0) if b.position.y >= cell.y else Vector2(0.0, -1.0)


func _draw_transit(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var done: Dictionary = {}
	for t: Dictionary in _plan.get("transit", []):
		var room_id: String = str(t["room_id"])
		var kind: String = str(t["kind"])
		if done.has(room_id) or not rooms.has(room_id):
			continue
		var r: Rect2 = _cell_rect(rooms[room_id])
		if SHAFT_KINDS.has(kind):
			done[room_id] = true
			_draw_shaft_symbol(r, pal, kind == FloorLayout.TRANSIT_FREIGHT)
		elif STEP_KINDS.has(kind):
			done[room_id] = true
			_draw_steps(r, pal)
			_draw_stairs_sign(r, pal)
		elif kind == FloorLayout.TRANSIT_EXIT:
			_draw_exit_marker(t, pal)


func _draw_shaft_symbol(r: Rect2, pal: Dictionary, freight: bool) -> void:
	var inner: Rect2 = r.grow(-_scale * 0.6)
	var w: float = maxf(1.0, _wall_w() * (0.55 if freight else 0.4))
	draw_rect(inner, pal["ink_soft"], false, w)
	draw_line(inner.position, inner.end, pal["ink_soft"], w, true)
	draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), pal["ink_soft"], w, true)


func _draw_steps(r: Rect2, pal: Dictionary) -> void:
	var vertical_run: bool = r.size.y >= r.size.x
	var inner: Rect2 = r.grow(-_scale * 0.4)
	var spacing: float = _scale * STEP_SPACING_CELLS
	var pts: PackedVector2Array = PackedVector2Array()
	var t: float = spacing
	var run: float = inner.size.y if vertical_run else inner.size.x
	while t < run:
		if vertical_run:
			pts.append_array([Vector2(inner.position.x, inner.position.y + t), Vector2(inner.end.x, inner.position.y + t)])
		else:
			pts.append_array([Vector2(inner.position.x + t, inner.position.y), Vector2(inner.position.x + t, inner.end.y)])
		t += spacing
	if not pts.is_empty():
		draw_multiline(pts, pal["ink_faint"], maxf(1.0, _scale * 0.08))


func _draw_stairs_sign(r: Rect2, pal: Dictionary) -> void:
	var h: float = clampf(_scale * 1.6, 14.0, r.size.y * 0.45)
	var sign_rect: Rect2 = Rect2(r.get_center() - Vector2(h, h * 0.5), Vector2(h * 2.0, h))
	draw_exit_sign(self, sign_rect, pal, false)
	draw_extinguisher(self, Vector2(r.position.x + _scale * 0.9, r.end.y - _scale * 0.9), _scale * 1.1, pal)


func _draw_exit_marker(t: Dictionary, pal: Dictionary) -> void:
	var door_cell: Vector2i = t.get("door_cell", NO_CELL)
	var at: Vector2 = _center_of(door_cell) if door_cell != NO_CELL else _center_of(t["cell"])
	var h: float = clampf(_scale * 1.5, 14.0, 44.0)
	draw_exit_sign(self, Rect2(at - Vector2(h, h * 0.5), Vector2(h * 2.0, h)), pal, at.x < size.x * 0.5)


## Flechas verdes de evacuación a lo largo del eje, hacia la escalera o salida más próxima.
func _draw_evacuation(pal: Dictionary) -> void:
	var exits: Array[Vector2] = _exit_points()
	var spine: String = str(_plan.get("corridor_id", ""))
	var rooms: Dictionary = _plan["rooms"]
	if exits.is_empty() or not rooms.has(spine):
		return
	var rect: Rect2 = Rect2(rooms[spine])
	var horizontal: bool = rect.size.x >= rect.size.y
	var length: float = rect.size.x if horizontal else rect.size.y
	var t: float = EVAC_STEP_CELLS * 0.5
	while t < length - EVAC_MIN_CELLS * 0.5:
		var p: Vector2 = rect.position + (Vector2(t, rect.size.y * 0.5) if horizontal else Vector2(rect.size.x * 0.5, t))
		_evac_arrow(p, _nearest(exits, p), horizontal, pal)
		t += EVAC_STEP_CELLS


## Flecha sobre el eje, siempre paralela a él (hacia la proyección de la salida): nunca en diagonal
## atravesando muros, también en las plantas de vestíbulo (PB, nave, azotea).
func _evac_arrow(p: Vector2, target: Vector2, along_x: bool, pal: Dictionary) -> void:
	var d: Vector2 = target - p
	d = Vector2(d.x, 0.0) if along_x else Vector2(0.0, d.y)
	if d.length() < EVAC_MIN_CELLS:
		return
	var n: Vector2 = d.normalized()
	var a: Vector2 = _cell_pt(p - n * EVAC_LEN_CELLS * 0.5)
	var b: Vector2 = _cell_pt(p + n * EVAC_LEN_CELLS * 0.5)
	draw_arrow(self, a, b, pal["green"], maxf(2.0, _scale * 0.34), maxf(7.0, _scale * 1.0))


func _exit_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t: Dictionary in _plan.get("transit", []):
		if EVAC_KINDS.has(str(t["kind"])):
			out.append(Vector2(t["cell"] as Vector2i) + Vector2(0.5, 0.5))
	return out


static func _nearest(points: Array[Vector2], p: Vector2) -> Vector2:
	var best: Vector2 = points[0]
	for q: Vector2 in points:
		if q.distance_squared_to(p) < best.distance_squared_to(p):
			best = q
	return best


# ─── Capas ─────────────────────────────────────────────────────────

## Conos de cámara recortados a la sala que vigilan (los muros ciegan): tinta translúcida con borde
## continuo, legible sobre verde, ámbar y rojo; el icono de la cámara encima.
func _draw_cameras(pal: Dictionary) -> void:
	var fill: Color = Color(pal["camera"], Database.get_balance_float(B_CONE_ALPHA))
	var edge: Color = Color(pal["camera"], Database.get_balance_float(B_CONE_EDGE_ALPHA))
	for cam: Dictionary in _plan.get("cameras", []):
		for part: PackedVector2Array in camera_cone(cam):
			draw_colored_polygon(part, fill)
			var outline: PackedVector2Array = part.duplicate()
			outline.append(part[0])
			draw_polyline(outline, edge, maxf(1.2, _scale * 0.09), true)
	for cam: Dictionary in _plan.get("cameras", []):
		var at: Vector2 = _center_of(cam["cell"])
		var s: float = clampf(_scale * 1.1, 12.0, 26.0)
		draw_circle(at, s * 0.62, pal["white"])
		draw_arc(at, s * 0.62, 0.0, TAU, 16, pal["camera"], 1.2, true)
		UITheme.draw_icon(self, "camera", Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), pal["camera"], maxf(1.5, s * 0.1))


## Cono de una cámara en px locales, recortado al rectángulo de su sala (Geometry2D). Vacío si la
## cámara no tiene sala en el plano.
func camera_cone(cam: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var rooms: Dictionary = _plan.get("rooms", {})
	if not rooms.has(str(cam.get("room_id", ""))):
		return out
	_fit()
	var reach: float = Database.get_balance_float(B_CAM_REACH) * _scale
	var half: float = deg_to_rad(Database.get_balance_float(B_CAM_ANGLE) * 0.5)
	var at: Vector2 = _center_of(cam["cell"])
	var dir: Vector2 = Vector2(0.0, 1.0).rotated(deg_to_rad(float(cam.get("rotation", 0.0))))
	var fan: PackedVector2Array = PackedVector2Array([at])
	for i: int in ARC_SEGMENTS + 1:
		fan.append(at + dir.rotated(lerpf(-half, half, float(i) / float(ARC_SEGMENTS))) * reach)
	var r: Rect2 = _cell_rect(rooms[str(cam["room_id"])])
	var box: PackedVector2Array = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for part: PackedVector2Array in Geometry2D.intersect_polygons(fan, box):
		if part.size() >= 3:
			out.append(part)
	return out


func _draw_routes(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var hatches: Dictionary = {}
	for t: Dictionary in _plan.get("transit", []):
		if str(t["kind"]) == FloorLayout.TRANSIT_VENT:
			hatches[str(t["room_id"])] = _center_of(t["cell"])
	_draw_vent_links(hatches, pal)
	for room_id: String in hatches:
		var s: float = clampf(_scale * 1.0, 10.0, 22.0)
		draw_vent(self, Rect2(hatches[room_id] - Vector2(s, s) * 0.5, Vector2(s, s)), pal["amber"], maxf(1.2, s * 0.1))
	for door: Dictionary in _plan.get("doors", []):
		if str(door.get("kind", "")) == FloorLayout.DOOR_OLD_LOCK:
			var s: float = clampf(_scale * 1.3, 12.0, 26.0)
			var at: Vector2 = _cell_pt(Vector2(door["cell"] as Vector2i)) + _door_into(door) * s * 0.7
			draw_circle(at, s * 0.62, pal["amber"])
			UITheme.draw_icon(self, "key", Rect2(at - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84), pal["ink"], maxf(1.2, s * 0.1))
	for id: String in get_room_ids():
		var kind: String = FloorLayout.transit_kind_of(Database.get_room(id)) if Database.get_room(id) != null else ""
		if kind == FloorLayout.TRANSIT_SERVICE_STAIRS or kind == FloorLayout.TRANSIT_FREIGHT:
			_route_outline(_cell_rect(rooms[id]), pal)
	_draw_ledges(pal)


func _draw_vent_links(hatches: Dictionary, pal: Dictionary) -> void:
	for door: Dictionary in _plan.get("doors", []):
		if str(door.get("kind", "")) != FloorLayout.DOOR_VENT:
			continue
		var a: Vector2 = hatches.get(str(door["a"]), _center_of(door["cell"]))
		var b: Vector2 = hatches.get(str(door["b"]), _center_of(door["cell"]))
		draw_dashed(self, a, b, pal["amber"], maxf(2.0, _scale * 0.28), _scale * DASH_CELLS)


func _route_outline(r: Rect2, pal: Dictionary) -> void:
	var inset: Rect2 = r.grow(-_wall_w())
	draw_rect(inset, Color(pal["amber"], 0.22))
	var corners: Array[Vector2] = [inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]
	for i: int in corners.size():
		draw_dashed(self, corners[i], corners[(i + 1) % corners.size()], pal["amber_dark"], maxf(1.5, _scale * 0.14), _scale * DASH_CELLS)
	var s: float = clampf(_scale * 1.1, 12.0, 24.0)
	var at: Vector2 = Vector2(inset.end.x - s * 0.7, inset.position.y + s * 0.7)
	draw_circle(at, s * 0.62, pal["white"])
	UITheme.draw_icon(self, "hide", Rect2(at - Vector2(s, s) * 0.42, Vector2(s, s) * 0.84), pal["amber_dark"], maxf(1.2, s * 0.1))


## Cornisas: línea de puntos ámbar por el muro exterior de las salas con salida a cornisa.
func _draw_ledges(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	for id: String in get_room_ids():
		var room: RoomData = Database.get_room(id)
		if room == null or not (room.illegitimate_entries.has(ENTRY_ROOF_LEDGE) or _has_ledge(room)):
			continue
		var r: Rect2 = _cell_rect(rooms[id]).grow(_wall_w() * 1.6)
		draw_dashed(self, r.position, Vector2(r.end.x, r.position.y), pal["amber"], maxf(2.0, _scale * 0.3), _scale * DASH_CELLS * 0.5)


static func _has_ledge(room: RoomData) -> bool:
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) == LEDGE_TYPE:
			return true
	return false


## Ocupación por franja (occupants_by_band): una pastilla «figura + número» por sala.
func _draw_occupancy(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var band: String = str(_model.get("band", ""))
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var fs: int = roundi(_base_size() * BADGE_RATIO)
	for id: String in get_room_ids():
		var room: RoomData = Database.get_room(id)
		var count: int = room.get_occupants(band) if room != null else 0
		if count <= 0:
			continue
		var r: Rect2 = _cell_rect(rooms[id]).grow(-_wall_w() * 1.5)
		var bs: Vector2 = people_badge_size(count, font, fs)
		if bs.x > r.size.x or bs.y > r.size.y:
			continue
		var pos: Vector2 = Vector2(r.position.x + _wall_w(), r.end.y - bs.y - _wall_w())
		draw_people_badge(self, Rect2(pos, bs), count, font, fs, pal)


# ─── Nombres, puntos, jugador ──────────────────────────────────────

func _draw_names(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	var font: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
	var base: int = _base_size()
	var fs: int = clampi(roundi(_scale * NAME_CELL_RATIO), roundi(base * NAME_MIN_RATIO), roundi(base * NAME_MAX_RATIO))
	for id: String in get_room_ids():
		var room: RoomData = Database.get_room(id)
		if room == null or is_circulation(room):
			continue
		var r: Rect2 = _cell_rect(rooms[id]).grow(-_wall_w() * 2.0)
		_draw_room_label(r, tr(room.name_key).to_upper(), room.clearance_required, _status(id), font, fs, pal)


## Nombre de sala sobre una placa de papel (no se mezcla con muebles ni muros); si no cabe ni en
## dos líneas se reduce la letra (hasta NAME_FLOOR_RATIO) y si aun así no cabe se omite (la sala sigue
## en la lista del panel). Nivel de acreditación arriba a la izquierda.
func _draw_room_label(r: Rect2, text: String, clearance: int, status: int, font: Font, fs: int, pal: Dictionary) -> void:
	var pad: float = maxf(3.0, fs * 0.35)
	var size_fs: int = fs
	var lines: PackedStringArray = _wrap(text, font, size_fs, r.size.x - pad * 2.0)
	while lines.is_empty() and size_fs > roundi(_base_size() * NAME_FLOOR_RATIO):
		size_fs -= 1
		lines = _wrap(text, font, size_fs, r.size.x - pad * 2.0)
	var line_h: float = font.get_height(size_fs)
	var block_h: float = line_h * float(lines.size())
	if lines.is_empty() or block_h + pad > r.size.y * 0.8:
		return
	var center_y: float = r.position.y + r.size.y * LABEL_HIGH_RATIO if r.size.y > block_h * 4.0 else r.get_center().y
	var y0: float = center_y - block_h * 0.5
	var widest: float = 0.0
	for line: String in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs).x)
	var plate: Rect2 = Rect2(r.get_center().x - widest * 0.5 - pad, y0 - pad * 0.5, widest + pad * 2.0, block_h + pad)
	var outline: PackedVector2Array = UITheme.rounded_rect_points(plate, pad * 0.8)
	draw_polygon(outline, PackedColorArray([Color(pal["paper"], PLATE_ALPHA)]))
	outline.append(outline[0])
	draw_polyline(outline, pal["ink_faint"], 1.0, true)
	for i: int in lines.size():
		var ts: float = font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs).x
		var pos: Vector2 = Vector2(r.get_center().x - ts * 0.5, y0 + line_h * float(i) + font.get_ascent(size_fs))
		draw_string(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_fs, pal["ink"])
	var tag_fs: int = maxi(9, roundi(size_fs * 0.78))
	if r.size.y > block_h + line_h * 2.0:
		var tag_pos: Vector2 = r.position + Vector2(tag_fs * 0.2, font.get_ascent(tag_fs) + tag_fs * 0.1)
		draw_string(font, tag_pos, tr("MAP_CLEARANCE_FMT") % clearance, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, status_ink(status, pal))


## Parte el texto en una o dos líneas que quepan en `width` ([] si no cabe).
static func _wrap(text: String, font: Font, fs: int, width: float) -> PackedStringArray:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return PackedStringArray([text])
	var words: PackedStringArray = text.split(" ", false)
	var best: PackedStringArray = PackedStringArray()
	for cut: int in range(1, words.size()):
		var a: String = " ".join(words.slice(0, cut))
		var b: String = " ".join(words.slice(cut))
		var wa: float = font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var wb: float = font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if wa <= width and wb <= width:
			best = PackedStringArray([a, b])
			break
	return best


## Conocidos con rutina desbloqueada: punto azul (radio mínimo según la letra base, legible en móvil).
func _draw_dots(pal: Dictionary) -> void:
	for dot: Dictionary in _dots_here(false):
		draw_npc_dot(self, _dot_at(dot), _dot_radius(), pal, false, bool(dot.get("approximate", false)))


## Objetivos marcados, lo último antes del «usted está aquí»: mira + etiqueta con el nombre.
func _draw_targets(pal: Dictionary) -> void:
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var fs: int = roundi(_base_size() * TAG_RATIO)
	var radius: float = _dot_radius()
	for dot: Dictionary in _dots_here(true):
		var pos: Vector2 = _dot_at(dot)
		var approx: bool = bool(dot.get("approximate", false))
		draw_target_marker(self, pos, radius, pal, approx)
		var text: String = UITheme.trf("MAP_TARGET_APPROX_FMT", [dot.get("name", "")]) if approx else str(dot.get("name", ""))
		var ts: Vector2 = tag_size(text, font, fs)
		var box: Rect2 = Rect2(pos + Vector2(radius * 3.0, -ts.y - radius), ts)
		if box.end.x > size.x - PAD:
			box.position.x = pos.x - radius * 3.0 - ts.x
		box.position.y = maxf(PAD, box.position.y)
		draw_tag(self, pos, box, text, font, fs, pal)


func _dots_here(targets: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rooms: Dictionary = _plan["rooms"]
	for dot: Dictionary in _model.get("dots", []):
		if int(dot.get("floor", -999)) == _floor and rooms.has(str(dot.get("room_id", ""))) \
				and bool(dot.get("target", false)) == targets:
			out.append(dot)
	return out


func _dot_at(dot: Dictionary) -> Vector2:
	var rooms: Dictionary = _plan["rooms"]
	return dot_position(_cell_rect(rooms[str(dot["room_id"])]).grow(-_wall_w() * 2.0), str(dot.get("npc_id", "")))


func _dot_radius() -> float:
	var base: float = float(_base_size())
	return clampf(_scale * DOT_RATIO, base * DOT_MIN_RATIO, base * DOT_MAX_RATIO)


## Posición determinista de un punto dentro de un rectángulo (reparto por hash del id).
static func dot_position(r: Rect2, npc_id: String) -> Vector2:
	var h: int = absi(hash(npc_id))
	var fx: float = 0.15 + 0.7 * float(h % 997) / 996.0
	var fy: float = 0.2 + 0.6 * float((h / 997) % 991) / 990.0
	return r.position + Vector2(r.size.x * fx, r.size.y * fy)


func _draw_hover(pal: Dictionary) -> void:
	var rooms: Dictionary = _plan["rooms"]
	if _hover.is_empty() or not rooms.has(_hover):
		return
	draw_rect(_cell_rect(rooms[_hover]).grow(_wall_w() * 0.5), pal["ink"], false, _wall_w() * 1.8)


func _draw_player(pal: Dictionary) -> void:
	if int(_model.get("player_floor", -999)) != _floor:
		return
	var at: Vector2 = Vector2.INF
	var cell: Variant = _model.get("player_cell", Vector2.INF)
	if cell is Vector2 and (cell as Vector2).is_finite():
		at = _cell_pt(cell)
	var rooms: Dictionary = _plan["rooms"]
	var room_id: String = str(_model.get("player_room", ""))
	if not at.is_finite() and rooms.has(room_id):
		at = _cell_rect(rooms[room_id]).get_center()
	if not at.is_finite():
		return
	var radius: float = clampf(_scale * 0.7, 8.0, 16.0)
	var fs: int = roundi(_base_size() * 0.78)
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var text: String = tr("MAP_YOU_ARE_HERE")
	var box: Vector2 = Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * 1.1, fs * 1.6)
	var pos: Vector2 = at + Vector2(radius * 1.6, radius * 1.4)
	if pos.x + box.x > size.x - PAD:
		pos.x = at.x - radius * 1.6 - box.x
	if pos.y + box.y > size.y - PAD:
		pos.y = at.y - radius * 1.4 - box.y
	draw_callout(self, at, pos, text, font, fs, pal)
	draw_pin(self, at, radius, pal)


## Norte y escala gráfica (1 celda = 1 m) abajo a la derecha; cartela de banda abajo a la izquierda.
func _draw_compass(pal: Dictionary) -> void:
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var fs: int = roundi(_base_size() * 0.7)
	var bar: float = float(SCALE_BAR_CELLS) * _scale
	var base: Vector2 = Vector2(size.x - PAD - bar, size.y - PAD)
	var tick: float = fs * 0.35
	draw_rect(Rect2(base - Vector2(0.0, tick), Vector2(bar * 0.5, tick)), pal["ink"])
	draw_rect(Rect2(base - Vector2(0.0, tick), Vector2(bar, tick)), pal["ink"], false, 1.5)
	draw_string(font, base + Vector2(0.0, -tick - fs * 0.3), tr("MAP_SCALE_FMT") % SCALE_BAR_CELLS, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["ink"])
	var n_at: Vector2 = Vector2(base.x - fs * 1.4, size.y - PAD - fs * 1.2)
	var tri: PackedVector2Array = PackedVector2Array([n_at + Vector2(0, -fs * 0.7), n_at + Vector2(fs * 0.38, fs * 0.35), n_at + Vector2(-fs * 0.38, fs * 0.35)])
	draw_colored_polygon(tri, pal["ink"])
	draw_centered(self, font, n_at + Vector2(0.0, fs * 0.95), tr("MAP_NORTH"), fs, pal["ink"])
	_draw_finishes(pal, font, fs)


## Cartela de banda: nombre y muestras de su paleta (suelo, moqueta, pared, acento, mobiliario).
func _draw_finishes(pal: Dictionary, font: Font, fs: int) -> void:
	var band: Dictionary = Database.get_art_band_for_floor(_floor)
	var colors: Dictionary = band.get("palette", {})
	if colors.is_empty():
		return
	var name_text: String = tr(str(band.get("name_key", ""))).to_upper()
	var at: Vector2 = Vector2(PAD, size.y - PAD)
	var chip: float = fs * 1.1
	var x: float = at.x
	for key: String in FINISH_KEYS:
		var r: Rect2 = Rect2(Vector2(x, at.y - chip), Vector2(chip, chip))
		draw_rect(r, Color(str(colors.get(key, "#888888"))))
		draw_rect(r, pal["ink"], false, 1.5)
		x += chip + fs * 0.2
	draw_string(font, Vector2(x + fs * 0.3, at.y - chip * 0.5 + font.get_ascent(fs) * 0.36), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, band_ink(colors))


## Acento de una paleta de banda oscurecido hasta leerse sobre el papel del plano.
static func band_ink(colors: Dictionary) -> Color:
	var c: Color = Color(str(colors.get("accent", "#555555")))
	while c.get_luminance() > INK_MAX_LUMINANCE:
		c = c.darkened(0.12)
	return c


# ─── Entrada ───────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_set_hover(room_at(motion.position))
		return
	if UITheme.is_primary_press(event):
		var pos: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton \
				else (event as InputEventScreenTouch).position
		var id: String = room_at(pos)
		_set_hover(id)
		if not id.is_empty():
			room_clicked.emit(id)
			accept_event()


func _set_hover(room_id: String) -> void:
	if room_id == _hover:
		return
	_hover = room_id
	room_hovered.emit(room_id)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover("")
	elif what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()
