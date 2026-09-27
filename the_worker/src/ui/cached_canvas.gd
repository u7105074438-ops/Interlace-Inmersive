# cached_canvas.gd — Lienzo con caché: dibuja una vez en una textura (SubViewport) y la muestra con una sola llamada.
# PROPIETARIO DE: su SubViewport y la textura cacheada.
# ESCUCHA: nada.
class_name CachedCanvas
extends Control

## Para dibujos estáticos grandes (el corte de la torre, la ciudad del menú): en vez de reenviar
## cientos de primitivas cada fotograma, se pintan una vez en un SubViewport (UPDATE_ONCE) a la
## resolución física de la pantalla y se dibuja su textura. painter(canvas: CanvasItem) recibe el
## lienzo interno, en las mismas coordenadas locales que este control. refresh() repinta.

## Lado máximo de la textura (px). Por encima se pinta a menor resolución.
const MAX_TEXTURE_SIDE := 4096

var painter: Callable
var _viewport: SubViewport
var _canvas: Control
var _queued: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "Cache"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_canvas_draw)
	_viewport.add_child(_canvas)
	add_child(_viewport, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	resized.connect(refresh)
	get_viewport().size_changed.connect(refresh)
	refresh()


## Repinta la caché (agrupado: como mucho una vez por fotograma).
func refresh() -> void:
	if _queued:
		return
	_queued = true
	_repaint.call_deferred()


func _repaint() -> void:
	_queued = false
	if not is_inside_tree() or size.x < 1.0 or size.y < 1.0:
		return
	var scale_v: Vector2 = pixel_scale()
	var px: Vector2 = (size * scale_v).ceil()
	var fit: float = minf(1.0, float(MAX_TEXTURE_SIDE) / maxf(px.x, px.y))
	scale_v *= fit
	_viewport.size = Vector2i((size * scale_v).ceil())
	_viewport.canvas_transform = Transform2D(0.0, scale_v, 0.0, Vector2.ZERO)
	_canvas.size = size
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


## Píxeles físicos por unidad local (estiramiento de la ventana × escala del lienzo).
func pixel_scale() -> Vector2:
	var t: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var s: Vector2 = t.get_scale().abs()
	return Vector2(maxf(s.x, 0.01), maxf(s.y, 0.01))


func texture_size() -> Vector2i:
	return _viewport.size


func _draw() -> void:
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)


func _on_canvas_draw() -> void:
	if painter.is_valid():
		painter.call(_canvas)
