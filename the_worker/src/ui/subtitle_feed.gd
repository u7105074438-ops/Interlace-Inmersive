# subtitle_feed.gd — Subtítulos descriptivos de todo sonido informativo (§13.10, §14.10).
# PROPIETARIO DE: las líneas de subtítulo visibles, su duración y el ajuste activado/desactivado.
# ESCUCHA: EventBus.subtitle_posted.
class_name SubtitleFeed
extends VBoxContainer

## subtitle_posted(text_key, source_position, importance):
##  · text_key: clave de strings.csv ("SFX_FOOTSTEPS"...), se muestra entre corchetes.
##  · source_position: posición de mundo del sonido; Vector2.INF = sin posición (sin flecha).
##    La flecha apunta desde el jugador (grupo "player") hacia la fuente.
##  · importance: 0 ambiente (gris) · 1 informativo (blanco) · 2 peligro (ámbar, negrita).
## Un subtítulo idéntico aún visible se agrupa ("×2") y renueva su duración.

const IMPORTANCE_COLORS: Array[String] = ["muted", "paper", "warn"]
const MAX_IMPORTANCE := 2

var _enabled: bool = true
var _lines: Array[Dictionary] = []


func _init() -> void:
	name = "SubtitleFeed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END


func _ready() -> void:
	EventBus.subtitle_posted.connect(post)
	set_process(false)


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		clear_lines()


func is_enabled() -> bool:
	return _enabled


func post(text_key: String, source_position: Vector2, importance: int) -> void:
	if not _enabled or text_key.is_empty():
		return
	var level: int = clampi(importance, 0, MAX_IMPORTANCE)
	var angle: float = _direction_angle(source_position)
	if not _lines.is_empty() and str(_lines.back()["key"]) == text_key:
		_repeat_last(angle, level)
		return
	var line: Dictionary = _make_line(text_key, angle, level)
	_lines.append(line)
	add_child(line["panel"])
	_trim()
	set_process(true)


func get_line_count() -> int:
	return _lines.size()


func get_line_text(index: int) -> String:
	if index < 0 or index >= _lines.size():
		return ""
	return (_lines[index]["label"] as Label).text


func clear_lines() -> void:
	for line: Dictionary in _lines:
		(line["panel"] as Node).queue_free()
	_lines.clear()
	set_process(false)


func _process(delta: float) -> void:
	var i: int = 0
	while i < _lines.size():
		var line: Dictionary = _lines[i]
		line["remaining"] = float(line["remaining"]) - delta
		var panel: Control = line["panel"]
		panel.modulate.a = clampf(float(line["remaining"]) / maxf(float(line["fade"]), 0.01), 0.0, 1.0)
		if float(line["remaining"]) <= 0.0:
			panel.queue_free()
			_lines.remove_at(i)
		else:
			i += 1
	if _lines.is_empty():
		set_process(false)


func _make_line(text_key: String, angle: float, level: int) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = UITheme.V_SUBTITLE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon: UITheme.IconView = UITheme.IconView.new("speaker", IMPORTANCE_COLORS[level], 0.8)
	row.add_child(icon)
	var label: Label = Label.new()
	label.theme_type_variation = UITheme.V_STRONG if level == MAX_IMPORTANCE else ""
	label.text = UITheme.trf("HUD_SUBTITLE_FMT", [UITheme.trf(text_key)])
	row.add_child(label)
	var line: Dictionary = {
		"panel": panel, "label": label, "icon": icon, "key": text_key, "count": 1,
		"text": label.text, "remaining": _duration(level), "fade": _duration(0) * 0.25,
	}
	_apply_style(line, angle, level)
	return line


func _repeat_last(angle: float, level: int) -> void:
	var line: Dictionary = _lines.back()
	line["count"] = int(line["count"]) + 1
	line["remaining"] = _duration(level)
	(line["label"] as Label).text = UITheme.trf("HUD_SUBTITLE_REPEAT", [str(line["text"]), int(line["count"])])
	_apply_style(line, angle, level)


func _apply_style(line: Dictionary, angle: float, level: int) -> void:
	var icon: UITheme.IconView = line["icon"]
	icon.set_color_name(IMPORTANCE_COLORS[level])
	if is_nan(angle):
		icon.set_icon("speaker")
		icon.set_angle(0.0)
	else:
		icon.set_icon("arrow")
		icon.set_angle(angle)
	var label: Label = line["label"]
	label.remove_theme_color_override("font_color")
	if level != 1:
		label.add_theme_color_override("font_color", UITheme.color(IMPORTANCE_COLORS[level]))


func _duration(level: int) -> float:
	var per_level: Array = UITheme.tune_array("interfaz.subtitulo_segundos_por_importancia")
	if per_level.is_empty():
		return UITheme.tune("interfaz.toast_segundos")
	return float(per_level[clampi(level, 0, per_level.size() - 1)])


func _trim() -> void:
	var max_lines: int = maxi(UITheme.tune_int("interfaz.subtitulos_max_lineas"), 1)
	while _lines.size() > max_lines:
		var oldest: Dictionary = _lines.pop_front()
		(oldest["panel"] as Node).queue_free()


## Ángulo (radianes, pantalla) del jugador a la fuente; NAN si no hay dirección útil.
func _direction_angle(source_position: Vector2) -> float:
	if not source_position.is_finite() or not is_inside_tree():
		return NAN
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return NAN
	var delta: Vector2 = source_position - player.global_position
	var min_px: float = UITheme.tune("interfaz.subtitulo_distancia_sin_flecha") * UITheme.tune("mundo.px_por_unidad")
	if delta.length() < min_px:
		return NAN
	return delta.angle()
