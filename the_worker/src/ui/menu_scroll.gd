# menu_scroll.gd — Zona desplazable de los menús: ScrollContainer con barra visible y aviso de «hay más».
# PROPIETARIO DE: nada (envuelve un contenido y dibuja el degradado y el chevrón inferiores).
# ESCUCHA: nada.
class_name MenuScroll
extends Control

## Uso: var area := MenuScroll.new(); area.set_content(control); añadir `area` a un contenedor.
## Sin ajuste: ocupa el espacio que le dé su contenedor (SIZE_EXPAND_FILL) y desplaza lo que sobre.
## fit_to(root, panel): altura mínima = la del contenido, acotada al hueco libre de `root` (el marco
## del memorándum) — el panel abraza su contenido y solo desplaza cuando de verdad no cabe.
## Cuando queda contenido por debajo se ve un degradado del color del papel y una píldora «Más ▼».
## Foco: al enfocar un control del contenido se desplaza lo mínimo para verlo, priorizando su borde
## superior (una tarjeta más alta que la vista muestra su cabecera, no su pie).

## Altura mínima visible del contenido cuando el ajuste se queda sin sitio (maquetación).
const MIN_VISIBLE := 160.0
const FADE_PX := 72.0
const PILL_PAD := 14.0
## Fotogramas tras aparecer en que el foco inicial no desplaza (la maquetación aún se asienta).
const SETTLE_FRAMES := 3

var scroll: ScrollContainer
var fade_color: Color = Color(0, 0, 0, 0)
## false oculta el aviso «Más» (p. ej. mientras un texto se escribe solo).
var hint_enabled: bool = true:
	set(value):
		hint_enabled = value
		if _hint != null:
			_hint.queue_redraw()
var _content: Control
var _hint: Control
var _fit_root: Control
var _fit_panel: Control
var _fit_queued: bool = false
var _ready_frame: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	_hint = Control.new()
	_hint.name = "MoreHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint.draw.connect(_draw_hint)
	add_child(_hint)


func _ready() -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	bar.value_changed.connect(func(_v: float) -> void: _hint.queue_redraw())
	bar.changed.connect(_hint.queue_redraw)
	bar.visibility_changed.connect(_hint.queue_redraw)
	resized.connect(_queue_fit)
	_ready_frame = Engine.get_process_frames()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_queue_fit()


## Pone el contenido desplazable (un único Control).
func set_content(content: Control) -> void:
	_content = content
	scroll.add_child(content)
	content.minimum_size_changed.connect(_queue_fit)


## Ajusta la altura al contenido sin salirse del hueco de `root` (MarginContainer) que ocupa `panel`.
func fit_to(root: Control, panel: Control) -> void:
	_fit_root = root
	_fit_panel = panel
	root.resized.connect(_queue_fit)
	panel.minimum_size_changed.connect(_queue_fit)


## true si hay contenido oculto por debajo del borde inferior.
func has_more_below() -> bool:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0 and bar.value < bar.max_value - bar.page - 1.0


## Desplaza lo justo para ver el control enfocado (primero su borde superior). El foco inicial no
## desplaza; los demás se atienden un fotograma después, con la maquetación ya asentada.
func _on_focus_changed(control: Control) -> void:
	if _content == null or control == null or not _content.is_ancestor_of(control):
		return
	if Engine.get_process_frames() - _ready_frame < SETTLE_FRAMES:
		return
	await get_tree().process_frame
	if is_instance_valid(control) and control.is_inside_tree():
		reveal(control)


## Desplaza lo mínimo para que `control` (del contenido) se vea, priorizando su borde superior.
func reveal(control: Control) -> void:
	var top: float = control.get_global_rect().position.y - _content.get_global_rect().position.y
	var bottom: float = top + control.size.y
	var view: float = scroll.size.y
	var shown: float = float(scroll.scroll_vertical)
	if top < shown:
		scroll.scroll_vertical = floori(top)
	elif bottom > shown + view and top > shown + view * 0.5:
		scroll.scroll_vertical = floori(minf(top, bottom - view))


## Reajuste agrupado: una vez por fotograma como mucho (las etiquetas con ajuste de línea cambian
## de altura al recibir su ancho; el ajuste converge en uno o dos fotogramas).
func _queue_fit() -> void:
	_hint.queue_redraw()
	if _fit_queued:
		return
	_fit_queued = true
	_apply_fit.call_deferred()


func _apply_fit() -> void:
	_fit_queued = false
	if _content == null or _fit_root == null or not is_inside_tree():
		return
	var height: float = minf(_content.get_combined_minimum_size().y, available_height())
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size.y = height
	_hint.queue_redraw()


## Alto libre para el contenido: el área del padre del marco (no el marco, que crece con su contenido)
## menos sus márgenes y el resto del panel (cabecera, regla, bordes).
func available_height() -> float:
	var own: float = get_combined_minimum_size().y
	var others: float = _fit_panel.get_combined_minimum_size().y - own
	var margins: float = float(_fit_root.get_theme_constant("margin_top") + _fit_root.get_theme_constant("margin_bottom"))
	return maxf(_fit_root.get_parent_area_size().y - margins - others, MIN_VISIBLE)


func _draw_hint() -> void:
	if not hint_enabled or not has_more_below():
		return
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var w: float = size.x - (bar.size.x if bar.visible else 0.0)
	var fade_h: float = minf(FADE_PX, size.y * 0.3)
	var clear: Color = Color(fade_color, 0.0)
	_hint.draw_polygon(PackedVector2Array([Vector2(0, size.y - fade_h), Vector2(w, size.y - fade_h),
			Vector2(w, size.y), Vector2(0, size.y)]), PackedColorArray([clear, clear, fade_color, fade_color]))
	_draw_pill(w - PILL_PAD * 0.5, size.y - PILL_PAD * 1.6)


## Píldora de tinta con «Más» y un chevrón hacia abajo, pegada a la derecha (junto a la barra).
func _draw_pill(right: float, center_y: float) -> void:
	var f: Font = MenuKit.font("bold")
	var fsize: int = MenuKit.fs(MenuKit.FONT_SMALL)
	var text: String = tr("UI_SCROLL_MORE").to_upper()
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var chevron_w: float = fsize * 0.8
	var pill_w: float = tw + chevron_w + PILL_PAD * 3.0
	var center: Vector2 = Vector2(right - pill_w * 0.5, center_y)
	var pill: Rect2 = Rect2(center.x - pill_w * 0.5, center.y - fsize * 0.75, pill_w, fsize * 1.5)
	_hint.draw_rect(pill, MenuKit.color("ink"))
	_hint.draw_rect(pill, MenuKit.color("amber"), false, 2.0)
	var baseline: float = center.y + fsize * 0.34
	_hint.draw_string(f, Vector2(pill.position.x + PILL_PAD, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			fsize, MenuKit.color("paper"))
	var cx: float = pill.end.x - PILL_PAD - chevron_w * 0.5
	var arrow: PackedVector2Array = [Vector2(cx - chevron_w * 0.5, center.y - fsize * 0.18),
		Vector2(cx, center.y + fsize * 0.22), Vector2(cx + chevron_w * 0.5, center.y - fsize * 0.18)]
	_hint.draw_polyline(arrow, MenuKit.color("amber"), maxf(2.0, fsize * 0.14), true)
