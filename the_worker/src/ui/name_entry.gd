# name_entry.gd — Formulario de alta: nombre del protagonista (§49) y tipo de contrato = preset de dificultad (§15.7).
# PROPIETARIO DE: el borrador del formulario (nombre y preset elegidos) hasta que se firma.
# ESCUCHA: nada.
class_name NameEntry
extends Control

## Paso 1: nombre (validado con sanitize_name). Paso 2: contrato Interno / Estándar / Auditoría.
## Al firmar emite completed(nombre, preset). El permadeath es invariable en todos los presets.
## Las tarjetas de contrato son botones cuya altura mínima sigue a su contenido (texto grande, ES):
## el marco compacto desplaza si aun así no cabe.

signal completed(player_name: String, difficulty: String)
signal cancelled()

const STEP_NAME := 0
const STEP_CONTRACT := 1
const NAMES_FILE := "res://data/npcs_generation.json"
const CARD_PAD := 22
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
	if what == NOTIFICATION_TRANSLATION_CHANGED and MenuKit.locale_outdated(self, _built_locale):
		_rebuild.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


## Atrás (Esc o botón de Android, vía MainMenu): del contrato vuelve al nombre; del nombre, cancela.
func go_back() -> void:
	_on_back()


func current_step() -> int:
	return _step


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


## Escribe un nombre en el campo (y en la credencial) como si lo hubiera tecleado el jugador.
func set_name_text(value: String) -> void:
	if _name_edit == null or not is_instance_valid(_name_edit):
		player_name = value
		return
	_name_edit.text = value
	_name_edit.text_changed.emit(value)


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
	var frame: Dictionary = MenuKit.memo_frame(tr(title_key), tr("UI_NEWHIRE_KICKER"), true)
	add_child(frame["root"])
	(frame["back"] as Button).pressed.connect(_on_back)
	if _step == STEP_NAME:
		_build_name_step(frame["body"])
	else:
		_build_contract_step(frame["body"])


func _build_name_step(body: VBoxContainer) -> void:
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 40)
	body.add_child(split)
	var form: VBoxContainer = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	split.add_child(form)
	var badge: Badge = Badge.new()
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(MenuKit.fs(300), MenuKit.fs(420))
	badge.player_name = player_name
	split.add_child(badge)
	var field_label: Label = MenuKit.label(tr("UI_NEWHIRE_NAME_LABEL").to_upper(), "TWSmall")
	field_label.add_theme_font_override("font", MenuKit.font("bold"))
	field_label.add_theme_color_override("font_color", MenuKit.color("ink"))
	form.add_child(field_label)
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = tr("UI_NEWHIRE_NAME_PLACEHOLDER")
	_name_edit.max_length = MenuKit.bal_int("menus.nombre_max_caracteres")
	_name_edit.text = player_name
	_name_edit.custom_minimum_size = Vector2(0, MenuKit.MIN_TOUCH * 1.4)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_next())
	_name_edit.text_changed.connect(func(t: String) -> void: badge.set_player_name(t))
	form.add_child(_name_edit)
	form.add_child(MenuKit.label(tr("UI_NEWHIRE_NAME_HINT"), "TWSmall", true))
	_error = MenuKit.label(tr("UI_NEWHIRE_NAME_ERROR"), "", true)
	_error.add_theme_color_override("font_color", MenuKit.axis_color("blood"))
	_error.visible = false
	form.add_child(_error)
	form.add_child(_name_buttons())
	MenuKit.focus_later(_name_edit)


func _name_buttons() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var suggest: Button = MenuKit.button(tr("UI_NEWHIRE_SUGGEST"))
	suggest.name = "Suggest"
	suggest.pressed.connect(_on_suggest)
	row.add_child(suggest)
	var next: Button = MenuKit.button(tr("UI_NEWHIRE_NEXT"))
	next.name = "Next"
	next.pressed.connect(_on_next)
	row.add_child(next)
	return row


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
	body.add_child(_signature_row())
	var selected: Button = _cards.get(difficulty) as Button
	if selected != null:
		MenuKit.focus_later(selected)


func _signature_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var caption: Label = MenuKit.label(tr("UI_CONTRACT_SIGNATURE"), "TWSmall")
	caption.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(caption)
	var line: VBoxContainer = VBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 0)
	var signature: Label = MenuKit.label(player_name)
	signature.name = "Signature"
	signature.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	signature.add_theme_font_override("font", MenuKit.font("italic"))
	signature.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_HEADING))
	signature.add_theme_color_override("font_color", MenuKit.color("navy"))
	line.add_child(signature)
	line.add_child(MenuKit.rule(MenuKit.color("ink"), 3))
	row.add_child(line)
	var sign_button: Button = MenuKit.button(tr("UI_CONTRACT_SIGN"))
	sign_button.name = "Sign"
	sign_button.size_flags_vertical = Control.SIZE_SHRINK_END
	sign_button.pressed.connect(_on_sign)
	row.add_child(sign_button)
	return row


func _contract_card(preset: String, group: ButtonGroup) -> Button:
	var card: Button = MenuKit.button("", "TWToggle")
	card.name = "Card_" + preset
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = preset == difficulty
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.pressed.connect(func() -> void: difficulty = preset)
	var inner: VBoxContainer = _card_contents(preset)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, CARD_PAD)
	card.add_child(inner)
	var heading: Label = inner.get_child(0) as Label
	var sync: Callable = func() -> void:
		MenuKit.fit_label(heading, MenuKit.fs(MenuKit.FONT_HEADING), card.size.x - CARD_PAD * 2)
		card.custom_minimum_size.y = inner.get_combined_minimum_size().y + CARD_PAD * 2
	inner.minimum_size_changed.connect(sync)
	card.resized.connect(sync)
	sync.call_deferred()
	_cards[preset] = card
	return card


## Nombre, descripción y modificadores del preset (etiquetas transparentes al ratón).
func _card_contents(preset: String) -> VBoxContainer:
	var inner: VBoxContainer = VBoxContainer.new()
	inner.name = "Contents"
	inner.add_theme_constant_override("separation", 6)
	var name_label: Label = MenuKit.label(tr(str(SettingsMenu.PRESET_NAME_KEYS[preset])).to_upper(), "TWHeading")
	name_label.name = "Heading"
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_HEADING))
	inner.add_child(name_label)
	inner.add_child(MenuKit.label(tr("UI_CONTRACT_DESC_" + preset.to_upper()), "TWSmall", true))
	var mods: Dictionary = MenuKit.bal_dict("dificultad." + preset)
	for mod: Dictionary in MODIFIER_ROWS:
		var value: float = float(mods.get(str(mod["key"]), 1.0))
		var line: Label = MenuKit.label(MenuKit.trf(str(mod["label"]), {"value": "×%.2f" % value}), "TWSmall", true)
		line.add_theme_font_override("font", MenuKit.font("bold"))
		inner.add_child(line)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in inner.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return inner


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


## Credencial de empleado de muestra: se actualiza mientras se escribe el nombre.
class Badge extends Control:
	const START_OCCUPATION_KEY := "jugador.ocupacion_inicial"
	const SHADOW := 8.0
	var player_name: String = ""
	var _occupation: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		_occupation = PromotionScreen.occupation_record(str(MenuKit.bal(START_OCCUPATION_KEY)))

	func set_player_name(value: String) -> void:
		player_name = value
		queue_redraw()

	func _draw() -> void:
		var ink: Color = MenuKit.color("ink")
		var w: float = size.x - SHADOW
		var card: Rect2 = Rect2(0, w * 0.18, w, size.y - w * 0.18 - SHADOW)
		draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, card.position.y + 12), MenuKit.color("blue"), w * 0.07)
		draw_rect(Rect2(card.position + Vector2(SHADOW, SHADOW), card.size), ink)
		draw_rect(card, MenuKit.color("paper"))
		var header: Rect2 = Rect2(card.position, Vector2(w, card.size.y * 0.2))
		draw_rect(header, MenuKit.color("night"))
		_draw_star(header.position + Vector2(header.size.y * 0.5, header.size.y * 0.5), header.size.y * 0.3)
		_text(Vector2(header.size.y * 0.95, header.get_center().y + header.size.y * 0.13), TranslationServer.translate("UI_COMPANY_NAME"), roundi(header.size.y * 0.36), MenuKit.color("lamp"), w - header.size.y * 1.1)
		var photo: Rect2 = Rect2(w * 0.3, header.end.y + card.size.y * 0.06, w * 0.4, card.size.y * 0.32)
		draw_rect(photo, MenuKit.color("paper_dim"))
		var tier: int = int(_occupation.get("tier", 1))
		if not MenuKit.draw_portrait(self, GameLaunch.portrait_seed_for(player_name), tier, photo):
			MenuKit.draw_person(self, Vector2(photo.get_center().x, photo.end.y + photo.size.y * 0.1), photo.size.y * 1.05, MenuKit.color("slate"), MenuKit.color("sick"), ink)
		draw_rect(photo, ink, false, 3.0)
		_draw_texts(card, photo.end.y)
		draw_rect(card, ink, false, 4.0)
		draw_rect(Rect2(w * 0.42, card.position.y + 6, w * 0.16, 10), ink)

	func _draw_texts(card: Rect2, top: float) -> void:
		var w: float = card.size.x
		var shown: String = player_name.strip_edges() if not player_name.strip_edges().is_empty() else TranslationServer.translate("UI_BADGE_NAME_EMPTY")
		_text(Vector2(w * 0.07, top + card.size.y * 0.12), shown.to_upper(), roundi(card.size.y * 0.075), MenuKit.color("ink"), w * 0.86)
		var role_key: String = str(_occupation.get("name_key", ""))
		var role: String = MenuKit.trf("UI_BADGE_ROLE_FMT", {"rank": int(_occupation.get("rank", 0)), "role": TranslationServer.translate(role_key)})
		_text(Vector2(w * 0.07, top + card.size.y * 0.2), role, roundi(card.size.y * 0.045), MenuKit.color("steel"), w * 0.86)
		var number: String = "%08d" % (absi(hash(shown)) % 100000000)
		_text(Vector2(w * 0.07, top + card.size.y * 0.27), MenuKit.trf("UI_BADGE_NUMBER_FMT", {"n": number}), roundi(card.size.y * 0.04), MenuKit.color("steel"), w * 0.86)
		var bars_top: float = card.end.y - card.size.y * 0.13
		for i: int in 34:
			if (absi(hash(number + str(i))) % 3) != 0:
				draw_rect(Rect2(w * 0.07 + i * w * 0.025, bars_top, w * 0.014, card.size.y * 0.08), MenuKit.color("ink"))

	func _text(pos: Vector2, text: String, font_size: int, color: Color, width: float) -> void:
		var f: Font = MenuKit.font("bold")
		var fsize: int = font_size
		var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if tw > width and tw > 0.0:
			fsize = maxi(8, floori(fsize * width / tw))
		draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)

	func _draw_star(c: Vector2, r: float) -> void:
		var pts: PackedVector2Array = []
		for k: int in 10:
			var a: float = -PI * 0.5 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.42))
		draw_colored_polygon(pts, MenuKit.color("amber"))
