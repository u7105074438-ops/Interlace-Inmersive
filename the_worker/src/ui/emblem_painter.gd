# emblem_painter.gd — Iconos vectoriales de los nueve finales (galería, epílogo) dibujados por código.
# PROPIETARIO DE: nada (funciones de dibujo puras).
# ESCUCHA: nada.
class_name EmblemPainter
extends RefCounted

## paint(canvas, ending_id, centro, radio, relleno, tinta): dibuja el icono del final dentro de un
## círculo de radio `r`. Los bloqueados se pintan con un relleno oscuro (silueta).


static func paint(canvas: CanvasItem, ending_id: String, c: Vector2, r: float, fill: Color, ink: Color) -> void:
	var lw: float = maxf(2.0, r * 0.09)
	match ending_id:
		"the_butcher":
			_cleaver(canvas, c, r, fill, ink, lw)
		"the_buyer":
			_envelope(canvas, c, r, fill, ink, lw)
		"the_ghost":
			_ghost(canvas, c, r, fill, ink, lw)
		"the_worker":
			_tie_and_drop(canvas, c, r, fill, ink, lw)
		"the_full_suite":
			_suit(canvas, c, r, fill, ink, lw)
		"the_figurehead":
			_crowned_chair(canvas, c, r, fill, ink, lw)
		"the_owner_in_exile":
			_deed(canvas, c, r, fill, ink, lw)
		"the_file":
			_folder(canvas, c, r, fill, ink, lw)
		_:
			_org_gap(canvas, c, r, fill, ink, lw)


static func _shape(canvas: CanvasItem, pts: PackedVector2Array, fill: Color, ink: Color, lw: float) -> void:
	canvas.draw_colored_polygon(pts, fill)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, ink, lw, true)


static func _box(canvas: CanvasItem, r: Rect2, fill: Color, ink: Color, lw: float) -> void:
	canvas.draw_rect(r, fill)
	canvas.draw_rect(r, ink, false, lw)


static func _cleaver(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var blade: PackedVector2Array = [c + Vector2(-r, -r * 0.55), c + Vector2(r * 0.45, -r * 0.55),
		c + Vector2(r * 0.55, -r * 0.3), c + Vector2(r * 0.55, r * 0.35), c + Vector2(-r * 0.85, r * 0.35), c + Vector2(-r, r * 0.1)]
	_shape(canvas, blade, fill, ink, lw)
	canvas.draw_circle(c + Vector2(-r * 0.62, -r * 0.25), r * 0.12, ink)
	_box(canvas, Rect2(c + Vector2(r * 0.5, -r * 0.2), Vector2(r * 0.6, r * 0.3)), ink, ink, lw)
	canvas.draw_line(c + Vector2(-r * 0.85, r * 0.2), c + Vector2(r * 0.4, r * 0.2), ink.lerp(fill, 0.5), lw * 0.6)


static func _envelope(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	_box(canvas, Rect2(c + Vector2(-r * 0.55, -r * 0.95), Vector2(r * 1.1, r * 0.9)), fill.darkened(0.12), ink, lw)
	canvas.draw_circle(c + Vector2(0, -r * 0.5), r * 0.22, ink)
	var body: Rect2 = Rect2(c + Vector2(-r, -r * 0.35), Vector2(r * 2.0, r * 1.2))
	_box(canvas, body, fill, ink, lw)
	canvas.draw_polyline(PackedVector2Array([body.position, c + Vector2(0, r * 0.35), Vector2(body.end.x, body.position.y)]), ink, lw, true)


static func _ghost(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var pts: PackedVector2Array = []
	var steps: int = 14
	for i: int in steps + 1:
		var a: float = PI + PI * i / steps
		pts.append(c + Vector2(cos(a) * r * 0.75, sin(a) * r * 0.75 - r * 0.15))
	var waves: int = 4
	for i: int in waves * 2 + 1:
		var x: float = r * 0.75 - (r * 1.5) * i / (waves * 2)
		pts.append(c + Vector2(x, r * (0.85 if i % 2 == 0 else 0.6)))
	_shape(canvas, pts, fill, ink, lw)
	canvas.draw_circle(c + Vector2(-r * 0.28, -r * 0.2), r * 0.13, ink)
	canvas.draw_circle(c + Vector2(r * 0.28, -r * 0.2), r * 0.13, ink)


static func _tie_and_drop(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var tie: PackedVector2Array = [c + Vector2(-r * 0.22, -r * 0.95), c + Vector2(r * 0.22, -r * 0.95),
		c + Vector2(r * 0.12, -r * 0.6), c + Vector2(r * 0.35, r * 0.6), c + Vector2(0, r * 0.95),
		c + Vector2(-r * 0.35, r * 0.6), c + Vector2(-r * 0.12, -r * 0.6)]
	_shape(canvas, tie, fill, ink, lw)
	canvas.draw_line(c + Vector2(-r * 0.12, -r * 0.6), c + Vector2(r * 0.12, -r * 0.6), ink, lw)
	var drop_c: Vector2 = c + Vector2(r * 0.72, -r * 0.35)
	var drop: PackedVector2Array = [drop_c + Vector2(0, -r * 0.42)]
	for i: int in 11:
		var a: float = -PI * 0.15 + (PI * 1.3) * i / 10.0
		drop.append(drop_c + Vector2(cos(a), sin(a)) * r * 0.22)
	_shape(canvas, drop, MenuKit.axis_color("sweat").lightened(0.35), ink, lw * 0.8)


static func _suit(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var jacket: PackedVector2Array = [c + Vector2(-r * 0.95, r * 0.95), c + Vector2(-r * 0.85, -r * 0.55),
		c + Vector2(-r * 0.3, -r * 0.85), c + Vector2(r * 0.3, -r * 0.85), c + Vector2(r * 0.85, -r * 0.55), c + Vector2(r * 0.95, r * 0.95)]
	_shape(canvas, jacket, fill, ink, lw)
	var shirt: PackedVector2Array = [c + Vector2(-r * 0.3, -r * 0.85), c + Vector2(r * 0.3, -r * 0.85), c + Vector2(0, r * 0.2)]
	_shape(canvas, shirt, MenuKit.color("paper"), ink, lw)
	var tie: PackedVector2Array = [c + Vector2(-r * 0.09, -r * 0.8), c + Vector2(r * 0.09, -r * 0.8), c + Vector2(r * 0.12, -r * 0.05), c + Vector2(0, r * 0.12), c + Vector2(-r * 0.12, -r * 0.05)]
	_shape(canvas, tie, ink, ink, lw * 0.5)
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(c + Vector2(side * r * 0.3, -r * 0.85), c + Vector2(side * r * 0.12, r * 0.45), ink, lw)


static func _crowned_chair(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	_box(canvas, Rect2(c + Vector2(-r * 0.5, -r * 0.35), Vector2(r * 1.0, r * 0.9)), fill, ink, lw)
	_box(canvas, Rect2(c + Vector2(-r * 0.65, r * 0.45), Vector2(r * 1.3, r * 0.22)), fill.darkened(0.15), ink, lw)
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(c + Vector2(side * r * 0.55, r * 0.67), c + Vector2(side * r * 0.6, r * 1.0), ink, lw)
	var crown: PackedVector2Array = [c + Vector2(-r * 0.45, -r * 0.5), c + Vector2(-r * 0.5, -r * 0.95), c + Vector2(-r * 0.22, -r * 0.72),
		c + Vector2(0, -r * 1.02), c + Vector2(r * 0.22, -r * 0.72), c + Vector2(r * 0.5, -r * 0.95), c + Vector2(r * 0.45, -r * 0.5)]
	_shape(canvas, crown, MenuKit.color("gold") if fill.v > 0.5 else fill, ink, lw)


static func _deed(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var paper: Rect2 = Rect2(c + Vector2(-r * 0.7, -r * 0.95), Vector2(r * 1.3, r * 1.75))
	_box(canvas, paper, fill, ink, lw)
	for i: int in 4:
		var y: float = paper.position.y + r * (0.35 + i * 0.28)
		canvas.draw_line(Vector2(paper.position.x + r * 0.2, y), Vector2(paper.end.x - r * 0.25, y), ink, lw * 0.6)
	var seal: Vector2 = Vector2(paper.end.x - r * 0.1, paper.end.y - r * 0.15)
	canvas.draw_circle(seal, r * 0.3, MenuKit.axis_color("blood") if fill.v > 0.5 else ink)
	canvas.draw_arc(seal, r * 0.3, 0.0, TAU, 20, ink, lw)
	var arrow: PackedVector2Array = [c + Vector2(-r * 1.05, r * 0.05), c + Vector2(-r * 0.75, -r * 0.2), c + Vector2(-r * 0.75, r * 0.3)]
	_shape(canvas, arrow, ink, ink, lw * 0.5)


static func _folder(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var back: PackedVector2Array = [c + Vector2(-r, -r * 0.7), c + Vector2(-r * 0.35, -r * 0.7), c + Vector2(-r * 0.2, -r * 0.5),
		c + Vector2(r, -r * 0.5), c + Vector2(r, r * 0.75), c + Vector2(-r, r * 0.75)]
	_shape(canvas, back, fill.darkened(0.2), ink, lw)
	_box(canvas, Rect2(c + Vector2(-r * 0.75, -r * 0.62), Vector2(r * 1.5, r * 0.6)), MenuKit.color("paper") if fill.v > 0.5 else fill, ink, lw * 0.6)
	var front: PackedVector2Array = [c + Vector2(-r, -r * 0.25), c + Vector2(r, -r * 0.25), c + Vector2(r * 0.92, r * 0.75), c + Vector2(-r * 0.92, r * 0.75)]
	_shape(canvas, front, fill, ink, lw)
	var stripe: Rect2 = Rect2(c + Vector2(-r * 0.6, r * 0.1), Vector2(r * 1.2, r * 0.26))
	_box(canvas, stripe, MenuKit.axis_color("blood") if fill.v > 0.5 else ink, ink, lw * 0.6)


static func _org_gap(canvas: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color, lw: float) -> void:
	var top: Rect2 = Rect2(c + Vector2(-r * 0.35, -r * 0.95), Vector2(r * 0.7, r * 0.5))
	_box(canvas, top, fill, ink, lw)
	canvas.draw_line(Vector2(c.x, top.end.y), c + Vector2(0, -r * 0.2), ink, lw)
	canvas.draw_line(c + Vector2(-r * 0.62, -r * 0.2), c + Vector2(r * 0.62, -r * 0.2), ink, lw)
	for side: float in [-1.0, 1.0]:
		canvas.draw_line(c + Vector2(side * r * 0.62, -r * 0.2), c + Vector2(side * r * 0.62, r * 0.2), ink, lw)
	_box(canvas, Rect2(c + Vector2(-r * 0.97, r * 0.2), Vector2(r * 0.7, r * 0.5)), fill, ink, lw)
	var gap: Rect2 = Rect2(c + Vector2(r * 0.27, r * 0.2), Vector2(r * 0.7, r * 0.5))
	var dashes: int = 6
	var edges: Array[PackedVector2Array] = [
		PackedVector2Array([gap.position, Vector2(gap.end.x, gap.position.y)]),
		PackedVector2Array([Vector2(gap.end.x, gap.position.y), gap.end]),
		PackedVector2Array([gap.end, Vector2(gap.position.x, gap.end.y)]),
		PackedVector2Array([Vector2(gap.position.x, gap.end.y), gap.position]),
	]
	for edge: PackedVector2Array in edges:
		for i: int in dashes:
			if i % 2 == 0:
				canvas.draw_line(edge[0].lerp(edge[1], float(i) / dashes), edge[0].lerp(edge[1], float(i + 1) / dashes), ink, lw)
