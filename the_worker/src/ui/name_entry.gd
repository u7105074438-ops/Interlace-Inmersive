# name_entry.gd — Formulario de alta: nombre del protagonista (§49) y tipo de contrato = preset de dificultad (§15.7).
# PROPIETARIO DE: el borrador del formulario (nombre y preset elegidos) hasta que se firma.
# ESCUCHA: nada.
class_name NameEntry
extends Control

## Paso 1: nombre (validado con sanitize_name). Paso 2: contrato Interno / Estándar / Auditoría.
## Al firmar emite completed(nombre, preset). El permadeath es invariable en todos los presets.

signal completed(player_name: String, difficulty: String)
signal cancelled()

const STEP_NAME := 0
const STEP_CONTRACT := 1
const NAMES_FILE := "res://data/npcs_generation.json"
const MODIFIER_ROWS: Array[Dictionary] = [
	{"key": "decaimiento_sospecha", "label": "UI_CONTRACT_MOD_SUSPICION"},
	{"key": "precio_soborno", "label": "UI_CONTRACT_MOD_BRIBES"},
	{"key": "margen_deberes", "label": "UI_CONTRACT_MOD_DEADLINES"},
]

var player_name: String = ""
var difficulty: String = ""
var _step: int = STEP_NAME
var _name_edit: LineEdit
var _error: Label
var _cards: Dictionary = {}
var _built_locale: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	difficulty = SettingsMenu.get_string("difficulty")
	if not SettingsMenu.PRESETS.has(difficulty):
		difficulty = str(MenuKit.bal("presets_por_defecto"))
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built_locale != TranslationServer.get_locale():
		_rebuild.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


## Limpia un nombre: sin espacios sobrantes ni caracteres de control, con longitud máxima.
static func sanitize_name(raw: String) -> String:
	var clean: String = ""
	for ch: String in raw:
		if ch.unicode_at(0) >= 32:
			clean += ch
	var parts: PackedStringArray = clean.strip_edges().split(" ", false)
	var joined: String = " ".join(parts)
	var limit: int = MenuKit.bal_int("menus.nombre_max_caracteres")
	return joined.substr(0, limit) if limit > 0 else joined


## Nombre sugerido a partir del banco de nombres de la plantilla (datos, §24.3).
static func suggest_name(rng: RandomNumberGenerator) -> String:
	var bank: Dictionary = MenuKit.read_json(NAMES_FILE).get("name_bank", {})
	var firsts: Array = bank.get("first_names", [])
	var lasts: Array = bank.get("last_names", [])
	if firsts.is_empty() or lasts.is_empty():
		return ""
	return "%s %s" % [firsts[rng.randi_range(0, firsts.size() - 1)], lasts[rng.randi_range(0, lasts.size() - 1)]]


## Muestra el paso indicado (STEP_NAME / STEP_CONTRACT).
func go_to_step(step: int) -> void:
	_step = step
	_rebuild()


func _rebuild() -> void:
	if _name_edit != null and is_instance_valid(_name_edit):
		player_name = _name_edit.text
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _build() -> void:
	_built_locale = TranslationServer.get_locale()
	theme = MenuKit.build_theme()
	_cards.clear()
	var title_key: String = "UI_NEWHIRE_TITLE" if _step == STEP_NAME else "UI_CONTRACT_TITLE"
	var frame: Dictionary = MenuKit.memo_frame(tr(title_key), tr("UI_NEWHIRE_KICKER"))
	add_child(frame["root"])
	(frame["back"] as Button).pressed.connect(_on_back)
	if _step == STEP_NAME:
		_build_name_step(frame["body"])
	else:
		_build_contract_step(frame["body"])


func _build_name_step(body: VBoxContainer) -> void:
	var field_label: Label = MenuKit.label(tr("UI_NEWHIRE_NAME_LABEL").to_upper(), "TWSmall")
	field_label.add_theme_font_override("font", MenuKit.font("bold"))
	body.add_child(field_label)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = tr("UI_NEWHIRE_NAME_PLACEHOLDER")
	_name_edit.max_length = MenuKit.bal_int("menus.nombre_max_caracteres")
	_name_edit.text = player_name
	_name_edit.custom_minimum_size = Vector2(0, MenuKit.MIN_TOUCH * 1.4)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_next())
	body.add_child(_name_edit)
	body.add_child(MenuKit.label(tr("UI_NEWHIRE_NAME_HINT"), "TWSmall", true))
	_error = MenuKit.label(tr("UI_NEWHIRE_NAME_ERROR"), "", true)
	_error.add_theme_color_override("font_color", MenuKit.axis_color("blood"))
	_error.visible = false
	body.add_child(_error)
	var row: HBoxContainer = HBoxContainer.new()
	var suggest: Button = MenuKit.button(tr("UI_NEWHIRE_SUGGEST"))
	suggest.name = "Suggest"
	suggest.pressed.connect(_on_suggest)
	row.add_child(suggest)
	var next: Button = MenuKit.button(tr("UI_NEWHIRE_NEXT"))
	next.name = "Next"
	next.pressed.connect(_on_next)
	row.add_child(next)
	body.add_child(row)
	_name_edit.grab_focus.call_deferred()


func _build_contract_step(body: VBoxContainer) -> void:
	var intro: Label = MenuKit.label(MenuKit.trf("UI_CONTRACT_INTRO", {"name": player_name}), "", true)
	body.add_child(intro)
	var cards: HBoxContainer = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 22)
	var group: ButtonGroup = ButtonGroup.new()
	for preset: String in SettingsMenu.PRESETS:
		cards.add_child(_contract_card(preset, group))
	body.add_child(cards)
	var note: Label = MenuKit.label(tr("UI_CONTRACT_PERMADEATH"), "", true)
	note.add_theme_font_override("font", MenuKit.font("bold"))
	note.add_theme_color_override("font_color", MenuKit.axis_color("blood").darkened(0.2))
	body.add_child(note)
	var sign_button: Button = MenuKit.button(tr("UI_CONTRACT_SIGN"))
	sign_button.name = "Sign"
	sign_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	sign_button.pressed.connect(_on_sign)
	body.add_child(sign_button)
	var selected: Button = _cards.get(difficulty) as Button
	if selected != null:
		selected.grab_focus.call_deferred()


func _contract_card(preset: String, group: ButtonGroup) -> Button:
	var card: Button = MenuKit.button("")
	card.name = "Card_" + preset
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = preset == difficulty
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, MenuKit.fs(300))
	card.pressed.connect(func() -> void: difficulty = preset)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 22)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)
	var name_label: Label = MenuKit.label(tr(str(SettingsMenu.PRESET_NAME_KEYS[preset])).to_upper(), "TWHeading")
	name_label.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_HEADING))
	inner.add_child(name_label)
	inner.add_child(MenuKit.label(tr("UI_CONTRACT_DESC_" + preset.to_upper()), "TWSmall", true))
	var mods: Dictionary = MenuKit.bal_dict("dificultad." + preset)
	for mod: Dictionary in MODIFIER_ROWS:
		var value: float = float(mods.get(str(mod["key"]), 1.0))
		var line: Label = MenuKit.label(MenuKit.trf(str(mod["label"]), {"value": "×%.2f" % value}), "TWSmall", true)
		line.add_theme_font_override("font", MenuKit.font("bold"))
		inner.add_child(line)
	for child: Node in inner.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards[preset] = card
	return card


func _on_suggest() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var suggestion: String = suggest_name(rng)
	if not suggestion.is_empty():
		_name_edit.text = suggestion
		_name_edit.caret_column = suggestion.length()
	_error.visible = false


func _on_next() -> void:
	var clean: String = sanitize_name(_name_edit.text)
	if clean.is_empty():
		_error.visible = true
		_name_edit.grab_focus()
		return
	player_name = clean
	_name_edit = null
	go_to_step(STEP_CONTRACT)


func _on_sign() -> void:
	if player_name.is_empty():
		go_to_step(STEP_NAME)
		return
	completed.emit(player_name, difficulty)


func _on_back() -> void:
	if _step == STEP_CONTRACT:
		go_to_step(STEP_NAME)
	else:
		cancelled.emit()
