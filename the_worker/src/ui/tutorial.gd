# tutorial.gd — Interfaz del primer día (§13.8, PASO 46): el vídeo corporativo con sus subtítulos, la tarjeta de quien habla, la nota de «tu primer día» y los fundidos; además instala el tutorial en la partida nueva.
# PROPIETARIO DE: los paneles visibles del tutorial (vídeo, tarjeta de diálogo, nota de tareas, fundido) y sus textos del momento.
# ESCUCHA: nada (TutorialDirector la maneja).
class_name Tutorial
extends CanvasLayer

## Tutorial.install() (lo llama el menú principal al lanzar una partida nueva, tras la apertura):
## registra TutorialDirector.begin como GameRoot.tutorial_hook. GameRoot lo invoca tras run_started
## si GameSession.wants_tutorial(): primera partida, o partidas posteriores sin «omitir lo ya visto».
## Capa UIRoot.LAYER - 1: el HUD y las ventanas quedan por encima; la atenuación de una ventana
## también cubre estos paneles. Nunca se llama «tutorial» en pantalla: es el vídeo de bienvenida,
## HR que te acompaña y la nota de tu primer día (§13.8: el vídeo no se declara tutorial).
## Textos con teclas: RichTextLabel con BBCode; keycaps() dibuja cada tecla como una tecla (en modo
## táctil, el nombre del control táctil); escape() protege nombres y textos traducidos.

const LAYER_OFFSET := 1
const MARGIN := 28
const VIDEO_TOP := 150
const NOTE_TOP := 110
const VIDEO_EMS := 25.0
const SPEECH_EMS := 24.0
const NOTE_EMS := 19.0
const PORTRAIT_EMS := 4.6
const VIDEO_ASPECT := 0.5625
const STATE_PENDING := "pending"
const STATE_ACTIVE := "active"
const STATE_DONE := "done"
const KEYCAP_FMT := "[bgcolor=#%s][color=#%s][b] %s [/b][/color][/bgcolor]"
const NOTE_BG := Color("#ffe98a")
const NOTE_INK := Color("#2a2410")
const NOTE_DONE := Color("#6b6340")
const FADE_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const B_PANEL_ANIM := "interfaz.animacion_panel_segundos"

var _root: Control
var _base: int = 18
var _video: PanelContainer
var _feed: TutorialVideoFeed
var _file_label: Label
var _speaker_label: Label
var _caption: RichTextLabel
var _speech: PanelContainer
var _portrait: PortraitView
var _speech_name: Label
var _speech_role: Label
var _speech_text: RichTextLabel
var _note: PanelContainer
var _note_rows: Array[Dictionary] = []
var _note_hint: RichTextLabel
var _note_box: VBoxContainer
var _fade: ColorRect
var _tweens: Dictionary = {}
var _speech_token: int = 0


## Busto de quien habla (CharacterPainter.draw_portrait).
class PortraitView extends Control:
	var appearance: Dictionary = {}

	func _draw() -> void:
		if not appearance.is_empty():
			CharacterPainter.draw_portrait(self, appearance, Rect2(Vector2.ZERO, size))


## Registra el tutorial como gancho de partida nueva de GameRoot (idempotente).
static func install() -> void:
	GameRoot.tutorial_hook = TutorialDirector.begin


static func is_installed() -> bool:
	return GameRoot.tutorial_hook.is_valid()


func _init() -> void:
	name = "Tutorial"
	layer = UIRoot.LAYER - LAYER_OFFSET
	_base = UITheme.base_font_size(UITheme.current_text_size)
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
	add_child(_root)
	_build_video()
	_build_speech()
	_build_note()
	_build_fade()


# ─── Texto ────────────────────────────────────────────────────

## Texto seguro para BBCode (nombres y traducciones).
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


## Teclas de las acciones como teclas dibujadas; en táctil, el control táctil (`touch_key`).
static func keycaps(actions: Array, touch: bool = false, touch_key: String = "") -> String:
	if touch and not touch_key.is_empty():
		return "[i]%s[/i]" % escape(TranslationServer.translate(touch_key))
	var pal: Dictionary = UITheme.palette(UITheme.current_high_contrast)
	var parts: PackedStringArray = PackedStringArray()
	for action: Variant in actions:
		parts.append(KEYCAP_FMT % [(pal["paper"] as Color).to_html(false), (pal["ink"] as Color).to_html(false),
				escape(ContextPrompt.key_text(str(action)))])
	return " ".join(parts)


## Línea traducida con sus argumentos ya preparados (BBCode seguro: los textos se escapan antes).
static func line(key: String, args: Array = []) -> String:
	var text: String = escape(TranslationServer.translate(key))
	return text % args if not args.is_empty() else text


## BBCode → texto plano (pruebas, lectores de pantalla).
static func plain(bbcode: String) -> String:
	var out: String = ""
	var depth: int = 0
	for ch: String in bbcode.replace("[lb]", "\u0001"):
		if ch == "[":
			depth += 1
		elif ch == "]" and depth > 0:
			depth -= 1
		elif depth == 0:
			out += "[" if ch == "\u0001" else ch
	return out


# ─── Vídeo ────────────────────────────────────────────────────

func _build_video() -> void:
	_video = _panel(UITheme.V_MODAL)
	_video.name = "Video"
	_video.offset_left = MARGIN
	_video.offset_top = VIDEO_TOP
	var width: float = _base * VIDEO_EMS
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = width
	_video.add_child(box)
	_file_label = _label(UITheme.V_MONO)
	box.add_child(_file_label)
	_feed = TutorialVideoFeed.new()
	_feed.custom_minimum_size = Vector2(width, width * VIDEO_ASPECT)
	box.add_child(_feed)
	_speaker_label = _label(UITheme.V_CAPTION)
	_speaker_label.uppercase = true
	box.add_child(_speaker_label)
	_caption = _rich(width)
	box.add_child(_caption)
	_video.visible = false
	_root.add_child(_video)


func show_video(appearance: Dictionary, tier: int, file_key: String, speaker_key: String) -> void:
	_feed.set_speaker(appearance, tier)
	_feed.set_mode(TutorialVideoFeed.MODE_TALK)
	_file_label.text = tr(file_key)
	_speaker_label.text = tr(speaker_key)
	_caption.text = ""
	_pop_in(_video)


func hide_video() -> void:
	_pop_out(_video)


func set_caption(bbcode: String) -> void:
	_caption.text = bbcode


func set_video_mode(mode: String) -> void:
	_feed.set_mode(mode)


func is_video_visible() -> bool:
	return _video.visible


func get_caption_text() -> String:
	return plain(_caption.text)


func get_video_mode() -> String:
	return _feed.get_mode()


# ─── Tarjeta de diálogo ───────────────────────────────────────

func _build_speech() -> void:
	_speech = _panel(UITheme.V_MODAL)
	_speech.name = "Speech"
	_speech.anchor_top = 0.5
	_speech.anchor_bottom = 0.5
	_speech.offset_left = MARGIN
	_speech.grow_vertical = Control.GROW_DIRECTION_BOTH
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech.add_child(row)
	_portrait = PortraitView.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.custom_minimum_size = Vector2.ONE * _base * PORTRAIT_EMS
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_speech_name = _label(UITheme.V_HEADING)
	col.add_child(_speech_name)
	_speech_role = _label(UITheme.V_CAPTION)
	col.add_child(_speech_role)
	_speech_text = _rich(_base * SPEECH_EMS)
	col.add_child(_speech_text)
	_speech.visible = false
	_root.add_child(_speech)


## Quién habla (nombre, cargo, busto) y qué dice (BBCode). `seconds` > 0: se retira sola pasado ese
## tiempo si nadie ha hablado después.
func show_speech(speaker_name: String, role: String, appearance: Dictionary, bbcode: String, seconds: float = 0.0) -> void:
	_speech_token += 1
	if seconds > 0.0 and is_inside_tree():
		get_tree().create_timer(seconds).timeout.connect(_hide_speech_if.bind(_speech_token))
	_speech_name.text = speaker_name
	_speech_role.text = role
	_speech_role.visible = not role.is_empty()
	_portrait.appearance = appearance
	_portrait.visible = not appearance.is_empty()
	_portrait.queue_redraw()
	_speech_text.text = bbcode
	if not _speech.visible:
		_pop_in(_speech)
	_recenter.call_deferred(_speech)


func hide_speech() -> void:
	_pop_out(_speech)


func _hide_speech_if(token: int) -> void:
	if token == _speech_token:
		hide_speech()


func is_speech_visible() -> bool:
	return _speech.visible


func get_speech_text() -> String:
	return plain(_speech_text.text)


func get_speaker_name() -> String:
	return _speech_name.text


# ─── Nota del primer día ──────────────────────────────────────

func _build_note() -> void:
	_note = PanelContainer.new()
	_note.name = "FirstDayNote"
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = NOTE_BG
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(_base * 0.9)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(3, 5)
	_note.add_theme_stylebox_override("panel", sb)
	_note.anchor_left = 1.0
	_note.anchor_right = 1.0
	_note.offset_right = -MARGIN
	_note.offset_top = NOTE_TOP
	_note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_note.rotation_degrees = -1.5
	_note_box = VBoxContainer.new()
	_note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_box.custom_minimum_size.x = _base * NOTE_EMS
	_note.add_child(_note_box)
	_note.visible = false
	_root.add_child(_note)


## La nota con sus tareas (textos BBCode ya traducidos) y el remite.
func show_note(title_key: String, from_key: String, task_texts: Array) -> void:
	for child: Node in _note_box.get_children():
		child.queue_free()
	_note_rows.clear()
	var title: Label = _label(UITheme.V_TITLE)
	title.text = tr(title_key)
	title.add_theme_color_override("font_color", NOTE_INK)
	_note_box.add_child(title)
	var from: Label = _label(UITheme.V_SMALL)
	from.text = tr(from_key)
	from.add_theme_color_override("font_color", NOTE_DONE)
	_note_box.add_child(from)
	for text: Variant in task_texts:
		_add_note_row(str(text))
	_note_hint = _rich(_base * NOTE_EMS)
	_note_hint.add_theme_color_override("default_color", NOTE_INK)
	_note_hint.visible = false
	_note_box.add_child(_note_hint)
	_pop_in(_note)


func _add_note_row(bbcode: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon: UITheme.IconView = UITheme.IconView.new("target", "hazard_ink", 0.8)
	row.add_child(icon)
	var text: RichTextLabel = _rich(_base * (NOTE_EMS - 2.0))
	text.add_theme_color_override("default_color", NOTE_INK)
	row.add_child(text)
	_note_box.add_child(row)
	_note_rows.append({"icon": icon, "text": text, "state": STATE_PENDING, "bbcode": bbcode})
	_paint_row(_note_rows.size() - 1, STATE_PENDING, bbcode)


## Estado de una tarea (STATE_*) y su texto (BBCode; "" = el último que tuvo).
func set_task(index: int, state: String, bbcode: String = "") -> void:
	if index < 0 or index >= _note_rows.size():
		return
	var text: String = bbcode if not bbcode.is_empty() else str(_note_rows[index]["bbcode"])
	_note_rows[index]["bbcode"] = text
	_paint_row(index, state, text)


func _paint_row(index: int, state: String, bbcode: String) -> void:
	var row: Dictionary = _note_rows[index]
	row["state"] = state
	var icon: UITheme.IconView = row["icon"]
	icon.set_icon("check" if state == STATE_DONE else "target")
	icon.modulate = Color(1, 1, 1, 0.45) if state == STATE_PENDING else Color.WHITE
	var shown: String = bbcode
	match state:
		STATE_DONE:
			shown = "[s][color=#%s]%s[/color][/s]" % [NOTE_DONE.to_html(false), bbcode]
		STATE_ACTIVE:
			shown = "[b]%s[/b]" % bbcode
		_:
			shown = "[color=#%s]%s[/color]" % [NOTE_DONE.to_html(false), bbcode]
	(row["text"] as RichTextLabel).text = shown


func set_note_hint(bbcode: String) -> void:
	if _note_hint != null:
		_note_hint.text = bbcode
		_note_hint.visible = not bbcode.is_empty()


func hide_note() -> void:
	_pop_out(_note)


func is_note_visible() -> bool:
	return _note.visible


func get_task_state(index: int) -> String:
	return str(_note_rows[index]["state"]) if index >= 0 and index < _note_rows.size() else ""


func get_task_text(index: int) -> String:
	return plain((_note_rows[index]["text"] as RichTextLabel).text) if index >= 0 and index < _note_rows.size() else ""


func get_note_hint() -> String:
	return plain(_note_hint.text) if _note_hint != null else ""


# ─── Fundido ──────────────────────────────────────────────────

func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = FADE_COLOR
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_fade)


## Fundido a negro (to_black) o desde negro, en `seconds` (0 = inmediato). Con await.
func fade(to_black: bool, seconds: float) -> void:
	var target: float = 1.0 if to_black else 0.0
	if seconds <= 0.0 or not is_inside_tree():
		_fade.modulate.a = target
		return
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "modulate:a", target, seconds)
	await tween.finished


func get_fade_alpha() -> float:
	return _fade.modulate.a


# ─── Piezas ───────────────────────────────────────────────────

func _panel(variation: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _label(variation: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _rich(width: float) -> RichTextLabel:
	var rich: RichTextLabel = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.custom_minimum_size.x = width
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		rich.add_theme_font_size_override(key, _base)
	return rich


func _pop_in(panel: Control) -> void:
	_kill_tween(panel)
	panel.visible = true
	panel.modulate.a = 0.0
	if not is_inside_tree():
		panel.modulate.a = 1.0
		return
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, UITheme.tune(B_PANEL_ANIM))
	_tweens[panel.name] = tween


func _pop_out(panel: Control) -> void:
	if not panel.visible:
		return
	_kill_tween(panel)
	if not is_inside_tree():
		panel.visible = false
		return
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, UITheme.tune(B_PANEL_ANIM))
	tween.tween_callback(func() -> void: panel.visible = false)
	_tweens[panel.name] = tween


func _kill_tween(panel: Control) -> void:
	var old: Tween = _tweens.get(panel.name) as Tween
	if old != null and old.is_valid():
		old.kill()
	_tweens.erase(panel.name)


## Centrado vertical de la tarjeta tras cambiar su texto (crece hacia ambos lados).
func _recenter(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	var h: float = panel.get_combined_minimum_size().y
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5
