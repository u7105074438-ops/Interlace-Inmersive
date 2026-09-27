# character_canvas.gd — Lista de dibujo grabada de un personaje: se calcula una vez por pose y se reproduce en cualquier lienzo.
# PROPIETARIO DE: sus propias órdenes de dibujo grabadas (inmutables una vez cerradas con finish()).
# ESCUCHA: nada.
class_name CharacterCanvas
extends RefCounted

## Ofrece los métodos de dibujo de CanvasItem que usan los pintores de personajes, pero en vez de
## dibujar graban la orden; replay(canvas) las emite en un CanvasItem real (dentro de su _draw).
## La geometría cara (superelipses, recortes del pelo, contornos de miembros) se calcula una sola
## vez por personaje y pose (caché de CharacterPainter). Los rellenos se triangulan al grabar y
## los consecutivos se agrupan en un único lote de triángulos (una sola orden al reproducir); los
## contornos siguen siendo polilíneas con antialiasing del motor. Los polígonos que no se pueden
## triangular se descartan al grabar.
## Almacenamiento compacto (muchas poses en caché): códigos de orden, escalares, colores y
## arrays empaquetados en listas planas que replay() recorre en orden.

enum { OP_TRIS, OP_POLYLINE, OP_CIRCLE, OP_ARC, OP_LINE, OP_RECT }

const MIN_CIRCLE_SEGMENTS := 10
const MAX_CIRCLE_SEGMENTS := 28
const SEGMENTS_PER_UNIT := 2.5

## Giro del cuerpo (rad) de la pose grabada: se aplica con la transformación al reproducir.
var roll: float = 0.0
var _codes: PackedInt32Array = PackedInt32Array()
var _nums: PackedFloat32Array = PackedFloat32Array()
var _cols: PackedColorArray = PackedColorArray()
var _packs: Array = []
var _points: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()


func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3 or color.a <= 0.0:
		return
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	if tris.is_empty():
		return
	var base: int = _points.size()
	_points.append_array(points)
	for i: int in points.size():
		_colors.append(color)
	for i: int in tris.size():
		_indices.append(tris[i] + base)


func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0,
		antialiased: bool = false) -> void:
	if points.size() < 2:
		return
	_begin(OP_POLYLINE, color)
	_packs.append(points)
	_nums.append_array(PackedFloat32Array([width, 1.0 if antialiased else 0.0]))


## Círculo: relleno sin antialiasing → polígono del lote; el resto, orden propia.
func draw_circle(center: Vector2, radius: float, color: Color, filled: bool = true,
		width: float = -1.0, antialiased: bool = false) -> void:
	if filled and not antialiased:
		draw_colored_polygon(CharacterStyle.ellipse(center, Vector2(radius, radius), segments_for(radius)), color)
		return
	_begin(OP_CIRCLE, color)
	_nums.append_array(PackedFloat32Array([center.x, center.y, radius, 1.0 if filled else 0.0, width, 1.0 if antialiased else 0.0]))


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int,
		color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	_begin(OP_ARC, color)
	_nums.append_array(PackedFloat32Array([center.x, center.y, radius, start_angle, end_angle, float(point_count), width,
			1.0 if antialiased else 0.0]))


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0,
		antialiased: bool = false) -> void:
	_begin(OP_LINE, color)
	_nums.append_array(PackedFloat32Array([from.x, from.y, to.x, to.y, width, 1.0 if antialiased else 0.0]))


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
	if filled:
		draw_colored_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y)]), color)
		return
	_begin(OP_RECT, color)
	_nums.append_array(PackedFloat32Array([rect.position.x, rect.position.y, rect.size.x, rect.size.y, width]))


## Segmentos de un círculo según su radio (más para los grandes).
static func segments_for(radius: float) -> int:
	return clampi(roundi(radius * SEGMENTS_PER_UNIT), MIN_CIRCLE_SEGMENTS, MAX_CIRCLE_SEGMENTS)


## Cierra la grabación (vuelca el último lote de rellenos).
func finish() -> void:
	_flush()


## Órdenes grabadas (lotes de triángulos incluidos).
func size() -> int:
	return _codes.size()


## Emite las órdenes grabadas en `canvas` (con la transformación que el llamador haya fijado).
func replay(canvas: CanvasItem) -> void:
	var rid: RID = canvas.get_canvas_item()
	var n: int = 0
	var c: int = 0
	var k: int = 0
	for code: int in _codes:
		if code == OP_TRIS:
			RenderingServer.canvas_item_add_triangle_array(rid, _packs[k + 2], _packs[k], _packs[k + 1])
			k += 3
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


func _begin(code: int, color: Color) -> void:
	_flush()
	_codes.append(code)
	_cols.append(color)


func _flush() -> void:
	if _indices.is_empty():
		return
	_codes.append(OP_TRIS)
	_packs.append_array([_points, _colors, _indices])
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
