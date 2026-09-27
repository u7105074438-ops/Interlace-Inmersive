# main_menu.gd — Menú principal: pantalla de título, flujo de partida nueva/continuar, galería y ajustes.
# PROPIETARIO DE: la pantalla activa del menú y el flujo nombre → contrato → apertura → juego.
# ESCUCHA: setting_changed (SettingsMenu), completed/cancelled (NameEntry), finished (OpeningCinematic).
class_name MainMenu
extends Control

## Uso: boot.gd añade MainMenu.new(). Abre con GameLaunch.take_menu_entry() ("", "new_game", "gallery").
## Nueva partida → NameEntry (nombre + preset) → OpeningCinematic (saltable; se omite si el perfil
## dice opening_seen y el jugador activó skip_seen_intro, o con --skip-intro) → GameLaunch.start_game().

signal new_run_requested(player_name: String, difficulty: String)
signal continue_requested()

const OPENING_SCENE := "res://scenes/cinematics/opening.tscn"
const FADE_TIME := 0.35
const STAGGER := 0.07
const MENU_ITEMS: Array[Dictionary] = [
	{"id": "new_game", "key": "UI_MENU_NEW_GAME"},
	{"id": "continue", "key": "UI_MENU_CONTINUE"},
	{"id": "gallery", "key": "UI_MENU_GALLERY"},
	{"id": "settings", "key": "UI_MENU_SETTINGS"},
	{"id": "quit", "key": "UI_MENU_QUIT"},
]

var _backdrop: MenuBackdrop
var _tower: TowerArt
var _title_layer: Control
var _screen_layer: Control
var _screen: Control
var _cinematic: Control
var _items: Dictionary = {}
var _climb_tween: Tween
var _built_locale: String = ""
var _pending_name: String = ""
var _pending_preset: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme = MenuKit.build_theme()
	_build_scene()
	resized.connect(_sync_layout)
	_sync_layout.call_deferred()
	_start_climb()
	_play_menu_music()
	_open_entry(GameLaunch.take_menu_entry())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built_locale != TranslationServer.get_locale():
		_rebuild_title.call_deferred()


# ─── Construcción ──────────────────────────────────────────────

func _build_scene() -> void:
	_backdrop = MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_tower = TowerArt.new()
	_tower.name = "Tower"
	_tower.show_ground = false
	_tower.anchor_x = 0.5
	_tower.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tower.anchor_left = 0.46
	_tower.offset_top = 18
	add_child(_tower)
	_title_layer = Control.new()
	_title_layer.name = "TitleLayer"
	_title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_layer)
	_screen_layer = Control.new()
	_screen_layer.name = "ScreenLayer"
	_screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_layer)
	_build_title()


func _sync_layout() -> void:
	if _tower == null:
		return
	_backdrop.ground_y = _tower.position.y + _tower.ground_y()
	var top: Rect2 = _tower.floor_rect(TowerArt.TOP_FLOOR)
	_backdrop.avoid_rect = Rect2(_tower.position + top.position - Vector2(top.size.x * 0.1, 0), Vector2(top.size.x * 1.2, size.y))
	_backdrop.queue_redraw()


func _rebuild_title() -> void:
	for child: Node in _title_layer.get_children():
		_title_layer.remove_child(child)
		child.queue_free()
	_build_title()
	_backdrop.queue_redraw()
	_tower.queue_redraw()


func _build_title() -> void:
	_built_locale = TranslationServer.get_locale()
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "TitleColumn"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.anchor_right = 0.5
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 56)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_add_logo(column)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_add_menu_items(column)
	var footer: Label = MenuKit.label(tr("UI_MENU_FOOTER"), "TWSmall")
	footer.add_theme_color_override("font_color", MenuKit.color("steel").lightened(0.2))
	column.add_child(footer)
	_animate_in(column)


func _add_logo(column: VBoxContainer) -> void:
	var kicker: Label = MenuKit.label(tr("UI_MENU_KICKER").to_upper())
	kicker.add_theme_font_override("font", MenuKit.font("bold"))
	kicker.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_SMALL))
	kicker.add_theme_color_override("font_color", MenuKit.color("amber"))
	column.add_child(kicker)
	var the_label: Label = MenuKit.label(tr("UI_LOGO_THE"))
	MenuKit.poster_text(the_label, "display", MenuKit.FONT_DISPLAY, MenuKit.color("amber"), MenuKit.color("ink"))
	the_label.add_theme_constant_override("line_spacing", -30)
	column.add_child(the_label)
	var worker: Label = MenuKit.label(tr("UI_LOGO_WORKER"))
	worker.name = "Logo"
	MenuKit.poster_text(worker, "display", MenuKit.FONT_TITLE + 40, MenuKit.color("paper"), MenuKit.color("amber"))
	column.add_child(worker)
	column.add_child(MenuKit.rule(MenuKit.color("amber"), MenuKit.OUTLINE + 2))
	var tagline: Label = MenuKit.label(tr("UI_TAGLINE"))
	MenuKit.poster_text(tagline, "italic", MenuKit.fs(46), MenuKit.color("paper"), MenuKit.color("ink"))
	column.add_child(tagline)
	var store: Label = MenuKit.label(tr("UI_STORE_TAGLINE"), "", true)
	store.add_theme_font_override("font", MenuKit.font("bold"))
	store.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_BODY))
	store.add_theme_color_override("font_color", MenuKit.color("paper_dim"))
	store.custom_minimum_size.x = 560
	column.add_child(store)


func _add_menu_items(column: VBoxContainer) -> void:
	_items.clear()
	var run_exists: bool = SaveSystem.has_method("run_exists") and SaveSystem.run_exists()
	var first: Button = null
	for item: Dictionary in MENU_ITEMS:
		var id: String = str(item["id"])
		if id == "continue" and not run_exists:
			continue
		var b: Button = MenuKit.button(tr(str(item["key"])), "TWMenuItem")
		b.name = "Item_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = 520
		b.pressed.connect(_on_item.bind(id))
		b.mouse_entered.connect(b.grab_focus)
		column.add_child(b)
		_items[id] = b
		if first == null:
			first = b
	if first != null and _screen == null:
		first.grab_focus.call_deferred()


func _animate_in(column: VBoxContainer) -> void:
	var tween: Tween = create_tween().set_parallel(true)
	var i: int = 0
	for child: Node in column.get_children():
		var c: Control = child as Control
		c.modulate.a = 0.0
		tween.tween_property(c, "modulate:a", 1.0, FADE_TIME).set_delay(i * STAGGER)
		i += 1


func _start_climb() -> void:
	var cycle: float = MenuKit.bal_float("menus.titulo.ciclo_escalada_segundos")
	if cycle <= 0.0:
		return
	_climb_tween = create_tween().set_loops()
	_climb_tween.tween_method(_tower.set_climb_progress, 0.0, float(TowerArt.TOP_FLOOR), cycle)
	_climb_tween.tween_interval(FADE_TIME * 4.0)


# ─── Acciones del menú ─────────────────────────────────────────

func _on_item(id: String) -> void:
	match id:
		"new_game":
			_request_new_game()
		"continue":
			_continue_run()
		"gallery":
			_open_gallery()
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()


func _open_entry(entry: String) -> void:
	match entry:
		GameLaunch.ENTRY_NEW_GAME:
			_request_new_game()
		GameLaunch.ENTRY_GALLERY:
			_open_gallery()


## Muestra una subpantalla sobre el título (atenúa la torre y oculta el título).
func show_screen(screen: Control) -> void:
	close_screen()
	_screen = screen
	_screen_layer.add_child(screen)
	_title_layer.visible = false
	var tween: Tween = create_tween()
	tween.tween_property(_tower, "modulate", Color(0.45, 0.45, 0.5), FADE_TIME)
	screen.modulate.a = 0.0
	tween.parallel().tween_property(screen, "modulate:a", 1.0, FADE_TIME)


## Cierra la subpantalla y vuelve al título.
func close_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen_layer.remove_child(_screen)
		_screen.queue_free()
	_screen = null
	_title_layer.visible = true
	_tower.modulate = Color.WHITE
	var first: Button = _items.get("new_game") as Button
	if first != null:
		first.grab_focus.call_deferred()


func current_screen() -> Control:
	return _screen


func _open_settings() -> void:
	var settings: SettingsMenu = SettingsMenu.new()
	settings.closed.connect(close_screen)
	settings.setting_changed.connect(_on_setting_changed)
	show_screen(settings)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "text_size" or key == "high_contrast":
		theme = MenuKit.build_theme()
		_rebuild_title.call_deferred()


func _open_gallery() -> void:
	var gallery: EndingsGallery = EndingsGallery.new()
	gallery.closed.connect(close_screen)
	show_screen(gallery)


func _request_new_game() -> void:
	var run_exists: bool = SaveSystem.has_method("run_exists") and SaveSystem.run_exists()
	if not run_exists:
		_open_name_entry()
		return
	show_screen(message_screen(tr("UI_CONFIRM_ABANDON_TITLE"), tr("UI_CONFIRM_ABANDON_BODY"), [
		[tr("UI_CONFIRM_ABANDON_YES"), _abandon_and_start],
		[tr("UI_CANCEL"), close_screen],
	]))


func _abandon_and_start() -> void:
	if SaveSystem.has_method("delete_run"):
		SaveSystem.delete_run()
	_open_name_entry()


func _open_name_entry() -> void:
	var entry: NameEntry = NameEntry.new()
	entry.completed.connect(begin_new_run)
	entry.cancelled.connect(close_screen)
	show_screen(entry)


## Arranca una partida nueva con nombre y preset ya elegidos (apertura incluida).
func begin_new_run(player_name: String, difficulty: String) -> void:
	_pending_name = player_name
	_pending_preset = difficulty
	SettingsMenu.set_value("difficulty", difficulty)
	if Database.has_method("set_difficulty_preset"):
		Database.call("set_difficulty_preset", difficulty)
	new_run_requested.emit(player_name, difficulty)
	if should_skip_opening():
		_launch_new_run(true, not SettingsMenu.get_bool("opening_seen"))
	else:
		play_opening()


## true si la apertura se omite: --skip-intro, o ya vista y el jugador pidió omitirla.
static func should_skip_opening() -> bool:
	if Autopilot.get_arg("skip-intro") == "true":
		return true
	return SettingsMenu.get_bool("skip_seen_intro") and SettingsMenu.get_bool("opening_seen")


func play_opening() -> void:
	close_screen()
	_title_layer.visible = false
	_stop_menu_music()
	var packed: PackedScene = load(OPENING_SCENE) as PackedScene
	_cinematic = (packed.instantiate() as Control) if packed != null else OpeningCinematic.new()
	add_child(_cinematic)
	_cinematic.connect("finished", _on_opening_finished)
	_cinematic.call("play")


func _on_opening_finished(skipped: bool) -> void:
	var first_run: bool = not SettingsMenu.get_bool("opening_seen")
	SettingsMenu.set_value("opening_seen", true)
	_launch_new_run(skipped, first_run)


func _launch_new_run(intro_skipped: bool, first_run: bool) -> void:
	GameLaunch.prepare_new_run(_pending_name, _pending_preset, intro_skipped, first_run)
	_launch_or_placeholder()


func _continue_run() -> void:
	continue_requested.emit()
	GameLaunch.prepare_load()
	_launch_or_placeholder()


func _launch_or_placeholder() -> void:
	if GameLaunch.start_game(get_tree()):
		return
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.queue_free()
	_cinematic = null
	show_screen(message_screen(tr("UI_PLACEHOLDER_TITLE"), MenuKit.trf("UI_PLACEHOLDER_BODY",
			{"name": _pending_name, "mode": GameLaunch.peek().get("mode", "")}), [[tr("UI_BACK"), _back_from_placeholder]]))
	_play_menu_music()


func _back_from_placeholder() -> void:
	GameLaunch.clear()
	close_screen()


## Pantalla de mensaje con botones: buttons = [[texto, Callable], ...].
func message_screen(title_text: String, body_text: String, buttons: Array) -> Control:
	var frame: Dictionary = MenuKit.memo_frame(title_text, tr("UI_MEMO_KICKER"))
	var root: Control = frame["root"]
	(frame["back"] as Button).pressed.connect(close_screen)
	var body: VBoxContainer = frame["body"]
	body.add_child(MenuKit.label(body_text, "", true))
	var row: HBoxContainer = HBoxContainer.new()
	body.add_child(row)
	for pair: Array in buttons:
		var b: Button = MenuKit.button(str(pair[0]))
		b.pressed.connect(pair[1] as Callable)
		row.add_child(b)
	if row.get_child_count() > 0:
		(row.get_child(0) as Button).grab_focus.call_deferred()
	return root


# ─── Música (única pieza no diegética junto a los epílogos, §14.9) ─

func _play_menu_music() -> void:
	MenuKit.audio_call(self, "play_menu_music", [], true)


func _stop_menu_music() -> void:
	MenuKit.audio_call(self, "stop_music", [])
