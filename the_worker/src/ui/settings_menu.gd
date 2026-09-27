# settings_menu.gd — Pantalla de ajustes (§13.10 accesibilidad, §15.7 dificultad) y acceso estático a los ajustes.
# PROPIETARIO DE: la caché de ajustes de la sesión (la persistencia es de SaveSystem: profile.json).
# ESCUCHA: nada.
class_name SettingsMenu
extends Control

## Claves de ajuste (SaveSystem.get_setting/set_setting) — contrato para el resto de piezas:
##   language "en"|"es" · text_size 0|1|2 · high_contrast bool · colorblind_safe bool
##   clock_speed float (multiplicador del reloj) · difficulty "interno"|"estandar"|"auditoria"
##   max_agents int · subtitles bool · music_volume 0..1 · sfx_volume 0..1
##   skip_seen_intro bool · opening_seen bool (bandera del perfil)
## Valores por defecto: balance `menus.ajustes_por_defecto`. Lectura: SettingsMenu.get_value(key).

signal setting_changed(key: String, value: Variant)
signal closed()

const LANGUAGES: Array[String] = ["en", "es"]
const PRESETS: Array[String] = ["interno", "estandar", "auditoria"]
const PRESET_NAME_KEYS: Dictionary = {
	"interno": "UI_PRESET_INTERNO", "estandar": "UI_PRESET_ESTANDAR", "auditoria": "UI_PRESET_AUDITORIA",
}
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const ROWS: Array[Dictionary] = [
	{"section": "UI_SET_SECTION_DISPLAY"},
	{"key": "language", "kind": "choice", "label": "UI_SET_LANGUAGE", "options": ["en", "es"],
		"option_keys": ["UI_LANG_EN", "UI_LANG_ES"]},
	{"key": "text_size", "kind": "choice", "label": "UI_SET_TEXT_SIZE", "hint": "UI_SET_TEXT_SIZE_HINT",
		"options": [0, 1, 2], "option_keys": ["UI_SET_TEXT_SMALL", "UI_SET_TEXT_MEDIUM", "UI_SET_TEXT_LARGE"]},
	{"key": "high_contrast", "kind": "toggle", "label": "UI_SET_HIGH_CONTRAST", "hint": "UI_SET_HIGH_CONTRAST_HINT"},
	{"key": "colorblind_safe", "kind": "toggle", "label": "UI_SET_COLORBLIND", "hint": "UI_SET_COLORBLIND_HINT"},
	{"key": "subtitles", "kind": "toggle", "label": "UI_SET_SUBTITLES", "hint": "UI_SET_SUBTITLES_HINT"},
	{"section": "UI_SET_SECTION_GAME"},
	{"key": "difficulty", "kind": "choice", "label": "UI_SET_DIFFICULTY", "hint": "UI_SET_DIFFICULTY_HINT",
		"options": ["interno", "estandar", "auditoria"],
		"option_keys": ["UI_PRESET_INTERNO", "UI_PRESET_ESTANDAR", "UI_PRESET_AUDITORIA"]},
	{"key": "clock_speed", "kind": "slider", "label": "UI_SET_CLOCK_SPEED", "hint": "UI_SET_CLOCK_SPEED_HINT",
		"format": "UI_SET_MULTIPLIER_FMT"},
	{"key": "max_agents", "kind": "slider", "label": "UI_SET_MAX_AGENTS", "hint": "UI_SET_MAX_AGENTS_HINT",
		"format": "UI_SET_COUNT_FMT"},
	{"key": "skip_seen_intro", "kind": "toggle", "label": "UI_SET_SKIP_INTRO", "hint": "UI_SET_SKIP_INTRO_HINT"},
	{"section": "UI_SET_SECTION_AUDIO"},
	{"key": "music_volume", "kind": "slider", "label": "UI_SET_MUSIC_VOLUME", "format": "UI_SET_PERCENT_FMT"},
	{"key": "sfx_volume", "kind": "slider", "label": "UI_SET_SFX_VOLUME", "format": "UI_SET_PERCENT_FMT"},
]

static var _session: Dictionary = {}
static var _profile_loaded: bool = false

var _built_locale: String = ""
var _value_labels: Dictionary = {}
var _focus_key: String = ""


# ─── Acceso estático ───────────────────────────────────────────

static func defaults() -> Dictionary:
	return MenuKit.bal_dict("menus.ajustes_por_defecto")


## Valor efectivo: perfil (SaveSystem) → caché de sesión → valor por defecto.
static func get_value(key: String) -> Variant:
	if SaveSystem.has_method("get_setting"):
		var saved: Variant = SaveSystem.get_setting(key)
		if saved != null:
			return saved
	if _session.has(key):
		return _session[key]
	return defaults().get(key)


## Igualdad tolerante a tipos (el JSON devuelve 2.0 donde se guardó 2).
static func values_match(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return str(a) == str(b) and not (a is bool or b is bool)
	return a == b


static func get_bool(key: String) -> bool:
	var v: Variant = get_value(key)
	return bool(v) if (v is bool or v is int or v is float) else false


static func get_int(key: String) -> int:
	var v: Variant = get_value(key)
	return int(v) if (v is int or v is float or v is bool) else 0


static func get_float(key: String) -> float:
	var v: Variant = get_value(key)
	return float(v) if (v is int or v is float) else 0.0


static func get_string(key: String) -> String:
	var v: Variant = get_value(key)
	return str(v) if v != null else ""


## Guarda un ajuste (sesión + SaveSystem) y lo aplica. Devuelve true si el perfil se escribió.
static func set_value(key: String, value: Variant, persist: bool = true) -> bool:
	_session[key] = value
	if SaveSystem.has_method("set_setting"):
		SaveSystem.set_setting(key, value)
	apply_setting(key, value)
	if persist and SaveSystem.has_method("save_profile"):
		return SaveSystem.save_profile()
	return false


## Carga el perfil (una vez por proceso) y aplica idioma y volúmenes. Lo llama boot.gd.
static func load_and_apply() -> void:
	if not _profile_loaded:
		_profile_loaded = true
		if SaveSystem.has_method("load_profile"):
			SaveSystem.load_profile()
	for key: String in ["language", "music_volume", "sfx_volume"]:
		apply_setting(key, get_value(key))


## Efectos inmediatos de un ajuste. El resto (reloj, agentes, subtítulos...) lo leen sus sistemas.
static func apply_setting(key: String, value: Variant) -> void:
	match key:
		"language":
			var locale: String = str(value) if LANGUAGES.has(str(value)) else LANGUAGES[0]
			if TranslationServer.get_locale() != locale:
				TranslationServer.set_locale(locale)
		"music_volume":
			_set_bus_volume(MUSIC_BUS, value)
		"sfx_volume":
			_set_bus_volume(SFX_BUS, value)


static func _set_bus_volume(bus_name: String, value: Variant) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0 or not (value is float or value is int):
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(value), 0.0001)))


## Rango {min, max, step} de un ajuste deslizante.
static func slider_range(key: String) -> Dictionary:
	match key:
		"clock_speed":
			var r: Dictionary = MenuKit.bal_dict("menus.velocidad_reloj")
			return {"min": float(r.get("min", 1.0)), "max": float(r.get("max", 1.0)), "step": float(r.get("paso", 1.0))}
		"max_agents":
			var a: Dictionary = MenuKit.bal_dict("menus.agentes")
			var top: float = float(MenuKit.bal_int("lod.max_agentes_total"))
			return {"min": float(a.get("min", top)), "max": top, "step": float(a.get("paso", 1))}
	return {"min": 0.0, "max": 1.0, "step": MenuKit.bal_float("menus.paso_volumen")}


# ─── Pantalla ──────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built_locale != TranslationServer.get_locale():
		_rebuild.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _build() -> void:
	_built_locale = TranslationServer.get_locale()
	theme = MenuKit.build_theme()
	_value_labels.clear()
	var frame: Dictionary = MenuKit.memo_frame(tr("UI_SETTINGS_TITLE"), tr("UI_SETTINGS_KICKER"))
	add_child(frame["root"])
	(frame["back"] as Button).pressed.connect(func() -> void: closed.emit())
	var body: VBoxContainer = frame["body"]
	for row: Dictionary in ROWS:
		body.add_child(_make_row(row))
	body.add_child(MenuKit.label(tr("UI_SET_PERMADEATH_NOTE"), "TWSmall", true))
	_restore_focus(frame["back"] as Button)


func _restore_focus(fallback: Button) -> void:
	var target: Control = find_child("Row_" + _focus_key, true, false) as Control
	var first: Control = _first_focusable(target) if target != null else null
	(first if first != null else fallback).grab_focus.call_deferred()


func _first_focusable(node: Node) -> Control:
	for child: Node in node.find_children("*", "BaseButton", true, false):
		return child as Control
	for child: Node in node.find_children("*", "HSlider", true, false):
		return child as Control
	return null


func _make_row(row: Dictionary) -> Control:
	if row.has("section"):
		var header: Label = MenuKit.label(tr(str(row["section"])).to_upper(), "TWSmall")
		header.add_theme_color_override("font_color", MenuKit.color("gold").darkened(0.3))
		header.add_theme_font_override("font", MenuKit.font("bold"))
		return header
	var line: HBoxContainer = HBoxContainer.new()
	line.name = "Row_" + str(row["key"])
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	var title: Label = MenuKit.label(tr(str(row["label"])), "", true)
	title.add_theme_font_override("font", MenuKit.font("bold"))
	texts.add_child(title)
	if row.has("hint"):
		texts.add_child(MenuKit.label(tr(str(row["hint"])), "TWSmall", true))
	line.add_child(texts)
	var control: Control = _make_control(row)
	control.custom_minimum_size.x = 560
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(control)
	return line


func _make_control(row: Dictionary) -> Control:
	var key: String = str(row["key"])
	match str(row["kind"]):
		"toggle":
			return _segmented(key, [true, false], ["UI_ON", "UI_OFF"])
		"slider":
			return _slider(key, str(row.get("format", "UI_SET_PERCENT_FMT")))
	return _segmented(key, row.get("options", []), row.get("option_keys", []))


## Control segmentado: una fila de botones de alternancia (táctil y legible).
func _segmented(key: String, options: Array, option_keys: Array) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var group: ButtonGroup = ButtonGroup.new()
	var current: Variant = get_value(key)
	for i: int in options.size():
		var b: Button = MenuKit.button(tr(str(option_keys[i])))
		b.name = "Opt_%d" % i
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = values_match(current, options[i])
		var value: Variant = options[i]
		b.pressed.connect(func() -> void: _on_changed(key, value))
		box.add_child(b)
	return box


func _slider(key: String, format_key: String) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	var range_def: Dictionary = slider_range(key)
	var slider: HSlider = HSlider.new()
	slider.min_value = range_def["min"]
	slider.max_value = range_def["max"]
	slider.step = range_def["step"]
	slider.value = get_float(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = MenuKit.MIN_TOUCH * 0.6
	slider.focus_mode = Control.FOCUS_ALL
	var value_label: Label = MenuKit.label("")
	value_label.custom_minimum_size.x = 130
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", MenuKit.font("bold"))
	_value_labels[key] = [value_label, format_key]
	_update_value_label(key, slider.value)
	slider.value_changed.connect(func(v: float) -> void: _on_slider(key, v))
	slider.drag_ended.connect(func(_changed: bool) -> void: _persist(key))
	box.add_child(slider)
	box.add_child(value_label)
	return box


func _update_value_label(key: String, v: float) -> void:
	if not _value_labels.has(key):
		return
	var pair: Array = _value_labels[key]
	var shown: String = "%d" % roundi(v * 100.0) if str(pair[1]) == "UI_SET_PERCENT_FMT" else ("%.2f" % v)
	if key == "max_agents":
		shown = "%d" % roundi(v)
	(pair[0] as Label).text = MenuKit.trf(str(pair[1]), {"value": shown})


func _on_slider(key: String, v: float) -> void:
	_update_value_label(key, v)
	var value: Variant = roundi(v) if key == "max_agents" else v
	set_value(key, value, false)
	setting_changed.emit(key, value)


func _persist(key: String) -> void:
	set_value(key, get_value(key), true)


func _on_changed(key: String, value: Variant) -> void:
	_focus_key = key
	set_value(key, value, true)
	setting_changed.emit(key, value)
	if key == "text_size" or key == "high_contrast":
		_rebuild.call_deferred()
