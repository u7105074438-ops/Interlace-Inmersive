# toast.gd — Pila de avisos breves (toasts) en la parte superior central de la pantalla.
# PROPIETARIO DE: los avisos visibles y su tiempo de vida.
# ESCUCHA: nada (UIRoot decide qué avisar).
class_name ToastStack
extends VBoxContainer

## Tipos: info · good · bad · warn. Cada tipo tiene color Y forma propios (icono), §13.10.
## Duración y máximo visible en balance: interfaz.toast_segundos, interfaz.toast_max_visibles.

const KIND_INFO := "info"
const KIND_GOOD := "good"
const KIND_BAD := "bad"
const KIND_WARN := "warn"
const KIND_ICONS: Dictionary = {"info": "info", "good": "check", "bad": "cross", "warn": "hazard"}
const KIND_COLORS: Dictionary = {"info": "paper", "good": "gain", "bad": "loss", "warn": "warn"}
const STRIPE_WIDTH := 6
const MAX_WIDTH_EMS := 24.0
const MIN_BG_ALPHA := 0.96
const LABEL_OUTLINE := 3

func _init() -> void:
	name = "ToastStack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN


## Muestra un aviso con texto ya traducido. Devuelve el panel creado.
func push(text: String, kind: String = KIND_INFO, icon_override: String = "") -> Control:
	var panel: PanelContainer = _make_panel(text, kind, icon_override)
	add_child(panel)
	_trim()
	var life: Timer = Timer.new()
	life.one_shot = true
	life.wait_time = maxf(UITheme.tune("interfaz.toast_segundos"), 0.1)
	life.timeout.connect(_expire.bind(panel))
	panel.add_child(life)
	life.start()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, UITheme.tune("interfaz.animacion_panel_segundos"))
	return panel


func get_toast_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func get_toast_text(index: int) -> String:
	var live: Array[Node] = []
	for child: Node in get_children():
		if not child.is_queued_for_deletion():
			live.append(child)
	if index < 0 or index >= live.size():
		return ""
	return str(live[index].get_meta("toast_text", ""))


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func _make_panel(text: String, kind: String, icon_override: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = UITheme.V_TOAST
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.set_meta("toast_text", text)
	panel.set_meta("toast_kind", kind)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var color_name: String = str(KIND_COLORS.get(kind, "paper"))
	var icon_id: String = icon_override if not icon_override.is_empty() else str(KIND_ICONS.get(kind, "info"))
	row.add_child(UITheme.IconView.new(icon_id, color_name))
	var label: Label = Label.new()
	label.theme_type_variation = UITheme.V_STRONG
	label.text = text
	row.add_child(label)
	panel.ready.connect(_style_panel.bind(panel, label, color_name), CONNECT_ONE_SHOT)
	return panel


## Franja lateral del color del tipo y ancho máximo con ajuste de línea.
func _style_panel(panel: PanelContainer, label: Label, color_name: String) -> void:
	var base_box: StyleBox = panel.get_theme_stylebox("panel", UITheme.V_TOAST)
	if base_box is StyleBoxFlat:
		var sb: StyleBoxFlat = (base_box as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.border_color = panel.get_theme_color(color_name, UITheme.HUD_TYPE)
		sb.border_width_left = STRIPE_WIDTH
		# Legibilidad (§13): el aviso cae sobre arte cargado (estanterías, carteles); fondo casi
		# opaco en vez del translúcido de los paneles.
		sb.bg_color.a = maxf(sb.bg_color.a, MIN_BG_ALPHA)
		panel.add_theme_stylebox_override("panel", sb)
	label.add_theme_constant_override("outline_size", LABEL_OUTLINE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var f: Font = label.get_theme_font("font")
	var fs: int = label.get_theme_font_size("font_size")
	var max_w: float = fs * MAX_WIDTH_EMS
	if f.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = max_w


func _trim() -> void:
	var max_visible: int = maxi(UITheme.tune_int("interfaz.toast_max_visibles"), 1)
	var live: Array[Node] = []
	for child: Node in get_children():
		if not child.is_queued_for_deletion():
			live.append(child)
	while live.size() > max_visible:
		var oldest: Node = live.pop_front()
		remove_child(oldest)
		oldest.queue_free()


func _expire(panel: Control) -> void:
	if not is_instance_valid(panel) or panel.is_queued_for_deletion():
		return
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, UITheme.tune("interfaz.animacion_panel_segundos"))
	tween.tween_callback(panel.queue_free)
