# character_canvas.gd — Dibujo grabado de un personaje: lista de órdenes compacta (se graba una vez por pose) que se tesela en UNA malla con colores por vértice y se dibuja con una sola llamada.
# PROPIETARIO DE: sus órdenes grabadas (hasta teselarlas), su teselado en curso y su malla (ArrayMesh).
# ESCUCHA: nada.
class_name CharacterCanvas
extends RefCounted

## Ofrece los métodos de dibujo de CanvasItem que usan los pintores de personajes, pero en vez de
## dibujar graban la orden (rellenos triangulados y agrupados en lotes; contornos como parámetros).
## build_mesh() TESELA esa lista, en orden, en un único flujo de triángulos (vértices + colores +
## índices) y lo sube a una ArrayMesh: replay(canvas) la dibuja con canvas.draw_mesh(), UNA llamada
## de dibujo por personaje en vez de ~60. Hasta entonces (o en el modo de referencia de QA),
## replay() emite la lista orden a orden como antes (una llamada por contorno).
## Aspecto idéntico: los contornos se teselan EXACTAMENTE como el motor (Godot 4.7,
## renderer_canvas_cull.cpp) con los mismos parámetros float32 que recibiría: polilíneas con franja
## central y dos franjas de suavizado (FEATHER = 1.25 unidades locales, anchura compensada, uniones
## con bisectriz limitada a ×3, remates en los extremos, bucle si el primer y el último punto
## coinciden), líneas como quad + 8 franjas/esquinas, círculos suavizados como abanico de 64
## segmentos + franja. Los triángulos van en el orden de las órdenes (el GPU mezcla en orden de
## primitiva dentro de una llamada): superposiciones y transparencias no cambian. Es geometría
## vectorial: nítida a cualquier zoom (el suavizado, como antes, en unidades locales). Los vértices
## del borde de la franja central se comparten con las de suavizado (−⅓ de vértices). Los colores
## se guardan en 8 bits (formato de malla del motor, que TRUNCA): se suma medio escalón para que el
## truncado redondee. Líneas finas (anchura < 0, GL_LINES en el motor): se aproximan con anchura 1
## sin suavizado (los pintores no las usan).

enum { OP_TRIS, OP_POLYLINE, OP_CIRCLE, OP_ARC, OP_LINE, OP_RECT }

const MIN_CIRCLE_SEGMENTS := 10
const MAX_CIRCLE_SEGMENTS := 28
const SEGMENTS_PER_UNIT := 2.5
## Constantes del motor (renderer_canvas_cull.cpp / canvas_item.cpp, Godot 4.7).
const FEATHER := 1.25
const ENGINE_ELLIPSE_SEGMENTS := 64
const CMP_EPSILON := 0.00001
const BEVEL_LIMIT := 3.0
const HAIRLINE_WIDTH := 1.0
## Medio escalón de 8 bits: el motor trunca el color de la malla a byte.
const COLOR_ROUND := 0.5 / 255.0
## Bytes por vértice en la GPU (posición 2 × float32 + color RGBA8) y por índice (16 / 32 bits).
const VERTEX_BYTES := 12
const SHORT_INDEX_LIMIT := 65536
## Estimación de memoria de la lista de órdenes (bytes por elemento de cada array).
const OP_BYTES_FLOAT := 4
const OP_BYTES_COLOR := 16
const OP_BYTES_POINT := 8
## Arrays de un lote de rellenos: puntos, colores por vértice, índices, vértices por polígono, color por polígono.
const TRIS_PACKS := 5

## Giro del cuerpo (rad) de la pose grabada: se aplica con la transformación al reproducir.
var roll: float = 0.0
## Marca de último uso (LRU de las fotos en CharacterPainter).
var last_used: int = 0
var _ops: PackedInt32Array = PackedInt32Array()
var _nums: PackedFloat32Array = PackedFloat32Array()
var _cols: PackedColorArray = PackedColorArray()
var _packs: Array = []
var _batch_points: PackedVector2Array = PackedVector2Array()
var _batch_colors: PackedColorArray = PackedColorArray()
var _batch_indices: PackedInt32Array = PackedInt32Array()
var _batch_runs: PackedInt32Array = PackedInt32Array()
var _batch_run_colors: PackedColorArray = PackedColorArray()
var _op_bytes: int = 0
var _points: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()
var _mesh: ArrayMesh = null
var _vertex_count: int = 0
var _index_count: int = 0
var _built: bool = false


# ─── API de CanvasItem que usan los pintores (graba) ──────────

func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3 or color.a <= 0.0:
		return
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tris.is_empty():
		return
	var base: int = _batch_points.size()
	_batch_points.append_array(points)
	for i: int in points.size():
		_batch_colors.append(color)
	for i: int in tris.size():
		_batch_indices.append(tris[i] + base)
	_batch_runs.append(points.size())
	_batch_run_colors.append(color)


func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0,
		antialiased: bool = false) -> void:
	if points.size() < 2:
		return
	_begin(OP_POLYLINE, color)
	_packs.append(points)
	_nums.append_array(PackedFloat32Array([width, 1.0 if antialiased else 0.0]))


## Círculo: relleno sin suavizado → polígono del lote; el resto, orden propia.
func draw_circle(center: Vector2, radius: float, color: Color, filled: bool = true,
		width: float = -1.0, antialiased: bool = false) -> void:
	if filled and not antialiased:
		draw_colored_polygon(CharacterStyle.ellipse(center, Vector2(radius, radius), segments_for(radius)), color)
		return
	_begin(OP_CIRCLE, color)
	_nums.append_array(PackedFloat32Array([center.x, center.y, radius, 1.0 if filled else 0.0, width,
			1.0 if antialiased else 0.0]))


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int,
		color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	_begin(OP_ARC, color)
	_nums.append_array(PackedFloat32Array([center.x, center.y, radius, start_angle, end_angle, float(point_count),
			width, 1.0 if antialiased else 0.0]))


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0,
		antialiased: bool = false) -> void:
	_begin(OP_LINE, color)
	_nums.append_array(PackedFloat32Array([from.x, from.y, to.x, to.y, width, 1.0 if antialiased else 0.0]))


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
	if filled:
		draw_colored_polygon(_rect_points(rect), color)
		return
	_begin(OP_RECT, color)
	_nums.append_array(PackedFloat32Array([rect.position.x, rect.position.y, rect.size.x, rect.size.y, width]))


## Segmentos de un círculo según su radio (más para los grandes).
static func segments_for(radius: float) -> int:
	return clampi(roundi(radius * SEGMENTS_PER_UNIT), MIN_CIRCLE_SEGMENTS, MAX_CIRCLE_SEGMENTS)


## Anchura compensada por el suavizado (canvas_item_get_compensated_antialiasing_width del motor).
static func compensated_width(width: float) -> float:
	if width <= 0.0:
		return width
	if width <= FEATHER * 2.0 + CMP_EPSILON:
		return width * 0.5
	if width <= FEATHER * 4.0 + CMP_EPSILON:
		return remap(width, FEATHER * 2.0, FEATHER * 4.0, width * 0.5, width - FEATHER * 0.5)
	return width - FEATHER * 0.5


func _begin(code: int, color: Color) -> void:
	_flush()
	_ops.append(code)
	_cols.append(color)


func _flush() -> void:
	if _batch_indices.is_empty():
		return
	_ops.append(OP_TRIS)
	_packs.append_array([_batch_points, _batch_colors, _batch_indices, _batch_runs, _batch_run_colors])
	_batch_points = PackedVector2Array()
	_batch_colors = PackedColorArray()
	_batch_indices = PackedInt32Array()
	_batch_runs = PackedInt32Array()
	_batch_run_colors = PackedColorArray()


# ─── Cierre, malla y reproducción ─────────────────────────────

## Cierra la grabación (vuelca el último lote de rellenos). La malla se construye aparte
## (build_mesh), cuando CharacterPainter tiene presupuesto de teselado.
func finish() -> void:
	_flush()
	_op_bytes = _nums.size() * OP_BYTES_FLOAT + _cols.size() * OP_BYTES_COLOR
	for pack: Variant in _packs:
		if pack is PackedVector2Array:
			_op_bytes += (pack as PackedVector2Array).size() * OP_BYTES_POINT
		elif pack is PackedColorArray:
			_op_bytes += (pack as PackedColorArray).size() * OP_BYTES_COLOR
		elif pack is PackedInt32Array:
			_op_bytes += (pack as PackedInt32Array).size() * OP_BYTES_FLOAT


## Tesela la lista de órdenes (en orden) en vértices + colores + índices y la vacía.
func tessellate() -> void:
	_flush()
	var n: int = 0
	var c: int = 0
	var k: int = 0
	for code: int in _ops:
		if code == OP_TRIS:
			_tess_tris(_packs[k], _packs[k + 2], _packs[k + 3], _packs[k + 4])
			k += TRIS_PACKS
			continue
		var col: Color = _cols[c]
		c += 1
		match code:
			OP_POLYLINE:
				_tess_polyline(_packs[k], col, _nums[n], _nums[n + 1] > 0.5)
				k += 1
				n += 2
			OP_LINE:
				_tess_line(Vector2(_nums[n], _nums[n + 1]), Vector2(_nums[n + 2], _nums[n + 3]), col, _nums[n + 4],
						_nums[n + 5] > 0.5)
				n += 6
			_:
				n = _tess_round(code, col, n)
	_clear_ops()


## Tesela y sube la malla (una superficie de triángulos); libera órdenes y arrays de la CPU.
func build_mesh() -> void:
	if _built:
		return
	_built = true
	tessellate()
	_vertex_count = _points.size()
	_index_count = _indices.size()
	if _index_count > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _points
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()


## True cuando la pose ya está teselada (se dibuja con su malla, o no tiene nada que dibujar).
func is_built() -> bool:
	return _built


func get_mesh() -> ArrayMesh:
	return _mesh


## Órdenes de dibujo que emite replay(): 1 con malla; las de la lista mientras no la hay.
func size() -> int:
	if _built:
		return 1 if _mesh != null else 0
	return _ops.size()


## Emite la pose en `canvas` (con la transformación que el llamador haya fijado): la malla o,
## si aún no está teselada, la lista de órdenes (camino de referencia).
func replay(canvas: CanvasItem) -> void:
	if _mesh != null:
		canvas.draw_mesh(_mesh, null)
	elif not _built:
		_replay_ops(canvas)


func vertex_count() -> int:
	return _vertex_count


func triangle_count() -> int:
	return _index_count / 3


## Memoria: la de la malla en la GPU (vértices + índices) o, antes, la de la lista de órdenes.
func byte_size() -> int:
	if _mesh == null:
		return _op_bytes
	var index_bytes: int = 2 if _vertex_count <= SHORT_INDEX_LIMIT else 4
	return _vertex_count * VERTEX_BYTES + _index_count * index_bytes


## Teselado en curso (tras tessellate() y antes de build_mesh()). Para tests.
func pending_points() -> PackedVector2Array:
	return _points


func pending_colors() -> PackedColorArray:
	return _colors


func pending_indices() -> PackedInt32Array:
	return _indices


func _clear_ops() -> void:
	_ops = PackedInt32Array()
	_nums = PackedFloat32Array()
	_cols = PackedColorArray()
	_packs = []
	_op_bytes = 0


# ─── Camino de referencia: la lista orden a orden ─────────────

func _replay_ops(canvas: CanvasItem) -> void:
	var rid: RID = canvas.get_canvas_item()
	var n: int = 0
	var c: int = 0
	var k: int = 0
	for code: int in _ops:
		if code == OP_TRIS:
			RenderingServer.canvas_item_add_triangle_array(rid, _packs[k + 2], _packs[k], _packs[k + 1])
			k += TRIS_PACKS
			continue
		var col: Color = _cols[c]
		c += 1
		match code:
			OP_POLYLINE:
				canvas.draw_polyline(_packs[k], col, _nums[n], _nums[n + 1] > 0.5)
				k += 1
				n += 2
			OP_LINE:
				canvas.draw_line(Vector2(_nums[n], _nums[n + 1]), Vector2(_nums[n + 2], _nums[n + 3]), col,
						_nums[n + 4], _nums[n + 5] > 0.5)
				n += 6
			_:
				n = _replay_round(canvas, code, col, n)


## Círculos, arcos y rectángulos sin relleno; devuelve el siguiente índice de escalares.
func _replay_round(canvas: CanvasItem, code: int, col: Color, n: int) -> int:
	var at: Vector2 = Vector2(_nums[n], _nums[n + 1])
	match code:
		OP_CIRCLE:
			canvas.draw_circle(at, _nums[n + 2], col, _nums[n + 3] > 0.5, _nums[n + 4], _nums[n + 5] > 0.5)
			return n + 6
		OP_ARC:
			canvas.draw_arc(at, _nums[n + 2], _nums[n + 3], _nums[n + 4], int(_nums[n + 5]), col, _nums[n + 6],
					_nums[n + 7] > 0.5)
			return n + 8
	canvas.draw_rect(Rect2(at, Vector2(_nums[n + 2], _nums[n + 3])), col, false, _nums[n + 4])
	return n + 5


# ─── Teselado (la geometría que generaría el motor) ──────────

## Lote de rellenos: vértices tal cual, color (redondeado) de cada polígono, índices desplazados.
func _tess_tris(pts: PackedVector2Array, idx: PackedInt32Array, runs: PackedInt32Array,
		run_colors: PackedColorArray) -> void:
	var base: int = _points.size()
	_points.append_array(pts)
	for r: int in runs.size():
		var cols: PackedColorArray = PackedColorArray()
		cols.resize(runs[r])
		cols.fill(_round(run_colors[r]))
		_colors.append_array(cols)
	var k: int = _indices.size()
	_indices.resize(k + idx.size())
	for i: int in idx.size():
		_indices[k + i] = idx[i] + base


## Polígono suelto (rectángulo relleno de un trazo que lo llena).
func _tess_polygon(points: PackedVector2Array, color: Color) -> void:
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tris.is_empty() or color.a <= 0.0:
		return
	_tess_tris(points, tris, PackedInt32Array([points.size()]), PackedColorArray([color]))


## CanvasItem.draw_polyline → canvas_item_add_polyline (anchura compensada si se suaviza).
func _tess_polyline(points: PackedVector2Array, color: Color, width: float, antialiased: bool) -> void:
	var w: float = compensated_width(width) if antialiased else width
	if w < 0.0:
		_polyline(points, color, HAIRLINE_WIDTH, false)
		return
	_polyline(points, color, w, antialiased)


## Círculos, arcos y rectángulos sin relleno; devuelve el siguiente índice de escalares.
func _tess_round(code: int, col: Color, n: int) -> int:
	var at: Vector2 = Vector2(_nums[n], _nums[n + 1])
	match code:
		OP_CIRCLE:
			_tess_circle(at, _nums[n + 2], col, _nums[n + 3] > 0.5, _nums[n + 4], _nums[n + 5] > 0.5)
			return n + 6
		OP_ARC:
			_tess_arc(at, _nums[n + 2], _nums[n + 3], _nums[n + 4], int(_nums[n + 5]), col, _nums[n + 6],
					_nums[n + 7] > 0.5)
			return n + 8
	_tess_rect_outline(Rect2(at, Vector2(_nums[n + 2], _nums[n + 3])), col, _nums[n + 4])
	return n + 5


## CanvasItem.draw_circle → draw_ellipse: relleno = elipse del motor; sin relleno = aro (polilínea
## cerrada de 64 segmentos, o disco si el trazo lo llena).
func _tess_circle(center: Vector2, radius: float, color: Color, filled: bool, width: float,
		antialiased: bool) -> void:
	if filled:
		_ellipse(center, radius, radius, color, antialiased)
	elif width >= 2.0 * radius:
		_ellipse(center, radius + 0.5 * width, radius + 0.5 * width, color, antialiased)
	else:
		var ring: PackedVector2Array = PackedVector2Array()
		for i: int in ENGINE_ELLIPSE_SEGMENTS:
			var a: float = float(i) * (TAU / float(ENGINE_ELLIPSE_SEGMENTS))
			ring.append(Vector2(cos(a) * radius, sin(a) * radius) + center)
		ring.append(ring[0])
		_tess_polyline(ring, color, width, antialiased)


## CanvasItem.draw_arc → draw_ellipse_arc: point_count puntos, ángulo limitado a ±TAU, polilínea.
func _tess_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int,
		color: Color, width: float, antialiased: bool) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var delta: float = clampf(end_angle - start_angle, -TAU, TAU)
	for i: int in point_count:
		var theta: float = (float(i) / (float(point_count) - 1.0)) * delta + start_angle
		pts.append(center + Vector2(radius * cos(theta), radius * sin(theta)))
	_tess_polyline(pts, color, width, antialiased)


## CanvasItem.draw_line → canvas_item_add_line: quad (anchura compensada si se suaviza) + suavizado.
func _tess_line(from: Vector2, to: Vector2, color: Color, width: float, antialiased: bool) -> void:
	var w: float = compensated_width(width) if antialiased else width
	if w < 0.0:
		w = HAIRLINE_WIDTH
		antialiased = false
	var diff: Vector2 = from - to
	var dir: Vector2 = diff.orthogonal().normalized()
	var t: Vector2 = dir * w * 0.5
	var c: Color = _round(color)
	var q: PackedVector2Array = PackedVector2Array([from + t, from - t, to - t, to + t])
	var base: int = _add_verts(q, c)
	_quad(base, base + 1, base + 2, base + 3)
	if antialiased:
		var border_size: float = FEATHER * (w if w < 1.0 else 1.0)
		_line_feather(q, base, dir * border_size, diff.normalized() * border_size, Color(c, 0.0))


## CanvasItem.draw_rect sin relleno: rectángulo lleno si el trazo lo cubre; si no, polilínea cerrada.
func _tess_rect_outline(rect: Rect2, color: Color, width: float) -> void:
	var r: Rect2 = rect.abs()
	if width >= r.size.x or width >= r.size.y:
		_tess_polygon(_rect_points(r.grow(0.5 * width)), color)
		return
	var ring: PackedVector2Array = _rect_points(r)
	ring.append(r.position)
	_tess_polyline(ring, color, width, false)


static func _round(color: Color) -> Color:
	return Color(minf(color.r + COLOR_ROUND, 1.0), minf(color.g + COLOR_ROUND, 1.0),
			minf(color.b + COLOR_ROUND, 1.0), minf(color.a + COLOR_ROUND, 1.0))


static func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])


## Añade vértices de un mismo color; devuelve el índice del primero.
func _add_verts(pts: PackedVector2Array, c: Color) -> int:
	var base: int = _points.size()
	_points.append_array(pts)
	var cols: PackedColorArray = PackedColorArray()
	cols.resize(pts.size())
	cols.fill(c)
	_colors.append_array(cols)
	return base


## Quad de CommandPrimitive del motor: triángulos (0, 1, 2) y (0, 2, 3).
func _quad(a: int, b: int, c: int, d: int) -> void:
	_indices.append(a)
	_indices.append(b)
	_indices.append(c)
	_indices.append(a)
	_indices.append(c)
	_indices.append(d)


## Tira de triángulos (PRIMITIVE_TRIANGLE_STRIP) de `count` vértices consecutivos → lista, en orden.
## Los triángulos degenerados de la tira (área nula) no generan fragmentos.
func _strip_run(base: int, count: int) -> void:
	var k: int = _indices.size()
	_indices.resize(k + (count - 2) * 3)
	for i: int in count - 2:
		_indices[k] = base + i
		_indices[k + 1] = base + i + 1
		_indices[k + 2] = base + i + 2
		k += 3


## Tira de triángulos con vértices arbitrarios → lista, en orden.
func _strip(ids: PackedInt32Array) -> void:
	var k: int = _indices.size()
	_indices.resize(k + (ids.size() - 2) * 3)
	for i: int in ids.size() - 2:
		_indices[k] = ids[i]
		_indices[k + 1] = ids[i + 1]
		_indices[k + 2] = ids[i + 2]
		k += 3


## Franjas y esquinas de suavizado de canvas_item_add_line (izquierda, derecha, arriba, abajo y
## las cuatro esquinas, en ese orden). `base`: vértices del quad [inicio izq., inicio der., fin
## der., fin izq.].
func _line_feather(q: PackedVector2Array, base: int, border: Vector2, border2: Vector2, t: Color) -> void:
	var o: int = _add_verts(PackedVector2Array([q[0] + border, q[3] + border, q[1] - border, q[2] - border,
			q[0] + border2, q[1] + border2, q[3] - border2, q[2] - border2, q[0] + border + border2,
			q[1] - border + border2, q[3] + border - border2, q[2] - border - border2]), t)
	_quad(base, o, o + 1, base + 3)
	_quad(base + 1, o + 2, o + 3, base + 2)
	_quad(base, o + 4, o + 5, base + 1)
	_quad(base + 3, o + 6, o + 7, base + 2)
	_quad(base, o + 4, o + 8, o)
	_quad(base + 1, o + 5, o + 9, o + 2)
	_quad(base + 3, o + 6, o + 10, o + 1)
	_quad(base + 2, o + 7, o + 11, o + 3)


## Elipse rellena de canvas_item_add_ellipse: abanico de 64 segmentos (radios reducidos ¼ de
## FEATHER si se suaviza) y franja de suavizado hacia fuera.
func _ellipse(center: Vector2, major: float, minor: float, color: Color, antialiased: bool) -> void:
	var ma: float = maxf(0.0, major - FEATHER * 0.25) if antialiased else major
	var mi: float = maxf(0.0, minor - FEATHER * 0.25) if antialiased else minor
	var c: Color = _round(color)
	var step: float = TAU / float(ENGINE_ELLIPSE_SEGMENTS)
	var ring: PackedVector2Array = PackedVector2Array()
	ring.resize(ENGINE_ELLIPSE_SEGMENTS + 2)
	for i: int in ENGINE_ELLIPSE_SEGMENTS + 1:
		var a: float = float(i) * step
		ring[i] = Vector2(cos(a) * ma, sin(a) * mi) + center
	ring[ENGINE_ELLIPSE_SEGMENTS + 1] = center
	var base: int = _add_verts(ring, c)
	var mid: int = base + ENGINE_ELLIPSE_SEGMENTS + 1
	for i: int in ENGINE_ELLIPSE_SEGMENTS:
		_indices.append(mid)
		_indices.append(base + i)
		_indices.append(base + i + 1)
	if antialiased:
		_ellipse_feather(center, ma, mi, base, Color(c, 0.0))


## Franja de suavizado de la elipse (TRIANGLE_STRIP anillo interior / exterior alternos).
func _ellipse_feather(center: Vector2, ma: float, mi: float, ring: int, t: Color) -> void:
	var border_size: float = FEATHER
	var max_axis: float = maxf(ma, mi) * 2.0
	if max_axis >= 0.0 and max_axis < 1.0:
		border_size *= max_axis * 0.5
	var step: float = TAU / float(ENGINE_ELLIPSE_SEGMENTS)
	var outer: PackedVector2Array = PackedVector2Array()
	outer.resize(ENGINE_ELLIPSE_SEGMENTS + 1)
	for i: int in ENGINE_ELLIPSE_SEGMENTS + 1:
		var a: float = float(i) * step
		outer[i] = Vector2(cos(a) * (ma + border_size), sin(a) * (mi + border_size)) + center
	var o: int = _add_verts(outer, t)
	var ids: PackedInt32Array = PackedInt32Array()
	ids.resize(outer.size() * 2)
	for i: int in outer.size():
		ids[i * 2] = ring + i
		ids[i * 2 + 1] = o + i
	_strip(ids)


## Polilínea de canvas_item_add_polyline (anchura ya compensada si se suaviza): franja central
## (con remates transparentes en los extremos si no es un bucle) y, si se suaviza, franjas izquierda
## y derecha que comparten los vértices del borde de la central.
func _polyline(pts: PackedVector2Array, color: Color, width: float, antialiased: bool) -> void:
	var n: int = pts.size()
	var loop: bool = pts[0].is_equal_approx(pts[n - 1])
	var dirs: PackedVector2Array = _edge_offsets(pts, loop)
	var c: Color = _round(color)
	var border_size: float = FEATHER * (width if width < 1.0 else 1.0)
	var caps: bool = antialiased and not loop
	var first: int = 2 if caps else 0
	var mid: PackedVector2Array = PackedVector2Array()
	mid.resize(n * 2 + first * 2)
	for i: int in n:
		var e: Vector2 = dirs[i] * (width * 0.5)
		mid[first + i * 2] = pts[i] + e
		mid[first + i * 2 + 1] = pts[i] - e
	if caps:
		var bb: Vector2 = -dirs[n] * border_size
		var eb: Vector2 = dirs[n + 1] * border_size
		mid[0] = mid[2] + bb
		mid[1] = mid[3] + bb
		mid[n * 2 + 2] = mid[n * 2] + eb
		mid[n * 2 + 3] = mid[n * 2 + 1] + eb
	var base: int = _add_verts(mid, c)
	var t: Color = Color(c, 0.0)
	if caps:
		for k: int in [0, 1, n * 2 + 2, n * 2 + 3]:
			_colors[base + k] = t
	_strip_run(base, mid.size())
	if antialiased:
		_feather_side(dirs, mid, base, border_size, t, caps, 1.0)
		_feather_side(dirs, mid, base, border_size, t, caps, -1.0)


## Franja de suavizado de un lado (side = 1 izquierda / −1 derecha) con sus remates: cada
## vértice exterior es el del borde de la franja central desplazado FEATHER por la normal.
func _feather_side(dirs: PackedVector2Array, mid: PackedVector2Array, base: int, border_size: float, t: Color,
		caps: bool, side: float) -> void:
	var n: int = dirs.size() - 2
	var off: int = 0 if side > 0.0 else 1
	var first: int = 2 if caps else 0
	var o: int = 1 if caps else 0
	var outer: PackedVector2Array = PackedVector2Array()
	outer.resize(n + o * 2)
	for i: int in n:
		outer[o + i] = mid[first + i * 2 + off] + dirs[i] * border_size * side
	if caps:
		outer[0] = mid[off] + dirs[0] * border_size * side
		outer[n + 1] = mid[n * 2 + 2 + off] + dirs[n - 1] * border_size * side
	var ob: int = _add_verts(outer, t)
	var ids: PackedInt32Array = PackedInt32Array()
	ids.resize(n * 2 + (5 if caps else 0))
	for i: int in n:
		ids[o * 2 + i * 2] = base + first + i * 2 + off
		ids[o * 2 + i * 2 + 1] = ob + o + i
	if caps:
		ids[0] = base + off
		ids[1] = ob
		ids[n * 2 + 2] = base + first + (n - 1) * 2 + off
		ids[n * 2 + 3] = ob + n + 1
		ids[n * 2 + 4] = base + n * 2 + 2 + off
	_strip(ids)


## Normal de arista de cada punto (compute_polyline_edge_offset_clamped del motor) y, al final,
## dos entradas extra: la dirección del primer tramo (remate inicial) y la del penúltimo punto
## (remate final).
static func _edge_offsets(pts: PackedVector2Array, loop: bool) -> PackedVector2Array:
	var n: int = pts.size()
	var first_dir: Vector2 = _first_dir(pts)
	var last_dir: Vector2 = _last_dir(pts)
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(n + 2)
	var prev: Vector2 = Vector2.ZERO
	for i: int in n:
		var seg: Vector2 = prev
		if i < n - 1:
			seg = (pts[i + 1] - pts[i]).normalized()
			if seg.is_zero_approx():
				seg = prev
		if i == 0 and loop:
			prev = last_dir
		elif i == n - 1 and loop:
			prev = first_dir
		if i == 0:
			out[n] = seg
		if i == n - 1:
			out[n + 1] = prev
		if not loop and i == 0:
			out[i] = first_dir.orthogonal()
		elif not loop and i == n - 1:
			out[i] = last_dir.orthogonal()
		else:
			out[i] = _clamped_offset(seg, prev)
		prev = seg
	return out


static func _first_dir(pts: PackedVector2Array) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	for i: int in range(1, pts.size()):
		d = (pts[i] - pts[i - 1]).normalized()
		if not d.is_zero_approx():
			break
	return d


static func _last_dir(pts: PackedVector2Array) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	for i: int in range(pts.size() - 1, 0, -1):
		d = (pts[i] - pts[i - 1]).normalized()
		if not d.is_zero_approx():
			break
	return d


## Bisectriz de la unión entre dos tramos, alargada 1/sen(ángulo) (máx. ×3).
static func _clamped_offset(seg: Vector2, prev: Vector2) -> Vector2:
	var bisector: Vector2 = (prev * seg.length() - seg * prev.length()).normalized()
	var angle: float = atan2(bisector.cross(prev), bisector.dot(prev))
	var sin_angle: float = sin(angle)
	var length: float = 1.0
	if not is_zero_approx(sin_angle) and not seg.is_equal_approx(prev):
		length = clampf(1.0 / sin_angle, -BEVEL_LIMIT, BEVEL_LIMIT)
	else:
		bisector = seg.orthogonal()
	if bisector.is_zero_approx():
		bisector = seg.orthogonal()
	return bisector * length
