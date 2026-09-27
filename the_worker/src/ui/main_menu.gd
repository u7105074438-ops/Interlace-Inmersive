# main_menu.gd — Menú principal: pantalla de título, flujo de partida nueva/continuar, galería y ajustes.
# PROPIETARIO DE: la pantalla activa del menú y el flujo nombre → contrato → apertura → juego.
# ESCUCHA: setting_changed (SettingsMenu), completed/cancelled (NameEntry), finished (OpeningCinematic).
class_name MainMenu
extends Control

## Uso: boot.gd añade MainMenu.new(). Abre con GameLaunch.take_menu_entry() ("", "new_game", "gallery").
## Nueva partida → NameEntry (nombre + preset) → OpeningCinematic (saltable; se omite si el perfil
## dice opening_seen y el jugador activó skip_seen_intro, o con --skip-intro) → GameLaunch.start_game().
## Con una partida guardada, «Nueva partida» pide confirmación; la partida vieja solo se borra al
## firmar el contrato nuevo (cancelar el alta la conserva). «Continuar» reactiva el preset de la
## partida (GameLaunch.run_preset) y comprueba que el guardado siga existiendo.
## Título: la columna se compacta por niveles (FIT_LOGO_SCALES) hasta caber sobre la calle.
## Android: «atrás» cierra la subpantalla, salta la apertura (la gestiona ella) o sale en el título.

signal new_run_requested(player_name: String, difficulty: String)
signal continue_requested()

const OPENING_SCENE := "res://scenes/cinematics/opening.tscn"
const FADE_TIME := 0.35
## Margen sobre la calle (en plantas del dibujo de la torre) para que el menú no pise el asfalto.
const ROAD_UNITS := 0.6
const TITLE_SCRIM := 0.5
const STAGGER := 0.07
const TITLE_TOP := 70
const TITLE_LEFT := 110
const DIM_COLOR := Color(0.45, 0.45, 0.5)
## Niveles de compactación del título: escala del logotipo por nivel. Desde FIT_HIDE_STORE se oculta
## el lema de tienda; desde FIT_HIDE_KICKER el antetítulo; desde FIT_COMPACT_ITEMS los elementos
## del menú usan letra menor; desde FIT_HIDE_TAGLINE se oculta también el lema.
const FIT_LOGO_SCALES: Array[float] = [1.0, 1.0, 1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
const FIT_HIDE_STORE := 1
const FIT_HIDE_KICKER := 2
const FIT_COMPACT_ITEMS := 6
const FIT_HIDE_TAGLINE := 7
## Interlineado negativo de «THE» para pegarlo a «WORKER» (a escala 1).
const LOGO_TUCK := -30
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
var _title_margin: MarginContainer
var _column: VBoxContainer
var _logo: Dictionary = {}
var _fit_level: int = 0
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
	get_tree().quit_on_go_back = false
	theme = MenuKit.build_theme()
	_build_scene()
	resized.connect(_sync_layout)
	_sync_layout.call_deferred()
	_start_climb()
	_play_menu_music()
	_open_entry(GameLaunch.take_menu_entry())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and MenuKit.locale_outdated(self, _built_locale):
		_rebuild_title.call_deferred()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		go_back()


## Esc / botón atrás cierra la subpantalla (las que lo gestionan ya lo marcaron como atendido).
func _unhandled_input(event: InputEvent) -> void:
	if _screen != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_screen()


## «Atrás» de Android: la apertura se salta sola; una subpantalla retrocede; el título sale.
func go_back() -> void:
	if _cinematic != null and is_instance_valid(_cinematic):
		return
	if _screen != null and is_instance_valid(_screen):
		if _screen.has_method("go_back"):
			_screen.call("go_back")
		else:
			close_screen()
		return
	get_tree().quit()


# ─── Construcción ──────────────────────────────────────────────

func _build_scene() -> void:
	_backdrop = MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	_backdrop.show_billboard = false
	_backdrop.left_scrim = TITLE_SCRIM
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_tower = TowerArt.new()
	_tower.name = "Tower"
	_tower.show_ground = false
	_tower.figure_scale = 1.1
	_tower.anchor_x = 0.5
	_tower.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tower.anchor_left = 0.46
	_tower.offset_top = 18
	add_child(_tower)
	_title_layer = _layer("TitleLayer")
	_screen_layer = _layer("ScreenLayer")
	_build_title()


func _layer(layer_name: String) -> Control:
	var layer: Control = Control.new()
	layer.name = layer_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _sync_layout() -> void:
	if _tower == null:
		return
	_backdrop.ground_y = _tower.position.y + _tower.ground_y()
	if _title_margin != null and is_instance_valid(_title_margin):
		var road: float = _tower.unit_px() * ROAD_UNITS
		_title_margin.add_theme_constant_override("margin_bottom", roundi(size.y - _backdrop.ground_y + road))
		_fit_title()
	var top: Rect2 = _tower.floor_rect(TowerArt.TOP_FLOOR)
	_backdrop.avoid_rect = Rect2(_tower.position + top.position - Vector2(top.size.x * 0.1, 0), Vector2(top.size.x * 1.2, size.y))


func _rebuild_title() -> void:
	if not is_inside_tree():
		return
	for child: Node in _title_layer.get_children():
		_title_layer.remove_child(child)
		child.queue_free()
	_build_title()
	_backdrop.refresh()
	_tower.refresh()


func _build_title() -> void:
	_built_locale = TranslationServer.get_locale()
	_title_margin = MarginContainer.new()
	_title_margin.name = "TitleColumn"
	_title_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_margin.anchor_right = 0.5
	_title_margin.add_theme_constant_override("margin_left", TITLE_LEFT)
	_title_margin.add_theme_constant_override("margin_top", TITLE_TOP)
	_title_margin.add_theme_constant_override("margin_bottom", 56)
	_title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(_title_margin)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_margin.add_child(_column)
	_add_logo(_column)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(spacer)
	_add_menu_items(_column)
	_title_layer.add_child(_make_footer())
	_fit_level = -1
	_apply_fit(0)
	_animate_in(_column)
	_sync_layout.call_deferred()
	_refit_next_frame()


## Pie en la franja de tierra, fuera del flujo de la columna (nunca lo pisa el menú).
func _make_footer() -> Label:
	var footer: Label = MenuKit.label(tr("UI_MENU_FOOTER"), "TWSmall")
	footer.name = "Footer"
	footer.add_theme_color_override("font_color", MenuKit.color("steel").lightened(0.25))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	footer.offset_left = TITLE_LEFT
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return footer


## Las etiquetas con ajuste de línea conocen su altura tras la primera maquetación: se reajusta.
func _refit_next_frame() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_fit_title()


func _add_logo(column: VBoxContainer) -> void:
	var kicker: Label = MenuKit.label(tr("UI_MENU_KICKER").to_upper())
	kicker.add_theme_font_override("font", MenuKit.font("bold"))
	kicker.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_SMALL))
	kicker.add_theme_color_override("font_color", MenuKit.color("amber"))
	column.add_child(kicker)
	var the_label: Label = MenuKit.label(tr("UI_LOGO_THE"))
	column.add_child(the_label)
	var worker: Label = MenuKit.label(tr("UI_LOGO_WORKER"))
	worker.name = "Logo"
	column.add_child(worker)
	column.add_child(MenuKit.rule(MenuKit.color("amber"), MenuKit.OUTLINE + 2))
	var tagline: Label = MenuKit.label(tr("UI_TAGLINE"))
	tagline.name = "Tagline"
	column.add_child(tagline)
	var store: Label = MenuKit.label(tr("UI_STORE_TAGLINE"), "", true)
	store.name = "StoreTagline"
	store.add_theme_font_override("font", MenuKit.font("bold"))
	store.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_BODY))
	store.add_theme_color_override("font_color", MenuKit.color("paper_dim"))
	store.custom_minimum_size.x = 560
	column.add_child(store)
	_logo = {"kicker": kicker, "the": the_label, "worker": worker, "tagline": tagline, "store": store}


func _add_menu_items(column: VBoxContainer) -> void:
	_items.clear()
	var first: Button = null
	for item: Dictionary in MENU_ITEMS:
		var id: String = str(item["id"])
		if id == "continue" and not _run_exists():
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
		MenuKit.focus_later(first)


# ─── Ajuste del título al hueco sobre la calle ─────────────────

## Busca el primer nivel de compactación con el que la columna cabe entre el margen y la calle.
func _fit_title() -> void:
	if _column == null or not is_instance_valid(_column) or _logo.is_empty():
		return
	var avail: float = title_space()
	for level: int in FIT_LOGO_SCALES.size():
		_apply_fit(level)
		if _column.get_combined_minimum_size().y <= avail:
			return


## Alto disponible para la columna del título (del margen superior al borde de la calle).
func title_space() -> float:
	var bottom: int = _title_margin.get_theme_constant("margin_bottom")
	return size.y - TITLE_TOP - bottom


func fit_level() -> int:
	return _fit_level


func _apply_fit(level: int) -> void:
	if level == _fit_level:
		return
	_fit_level = level
	var s: float = FIT_LOGO_SCALES[level]
	var ink: Color = MenuKit.color("ink")
	(_logo["store"] as Label).visible = level < FIT_HIDE_STORE
	(_logo["kicker"] as Label).visible = level < FIT_HIDE_KICKER
	(_logo["tagline"] as Label).visible = level < FIT_HIDE_TAGLINE
	MenuKit.poster_text(_logo["the"], "display", roundi(MenuKit.FONT_DISPLAY * s), MenuKit.color("amber"), ink)
	(_logo["the"] as Label).add_theme_constant_override("line_spacing", roundi(LOGO_TUCK * s))
	MenuKit.poster_text(_logo["worker"], "display", roundi((MenuKit.FONT_TITLE + 16) * s), MenuKit.color("paper"), MenuKit.color("amber"))
	MenuKit.poster_text(_logo["tagline"], "italic", roundi(MenuKit.fs(46) * maxf(s, 0.7)), MenuKit.color("paper"), ink)
	for b: Button in _items.values():
		if level >= FIT_COMPACT_ITEMS:
			b.add_theme_font_size_override("font_size", MenuKit.fs(MenuKit.FONT_BUTTON + 4))
		else:
			b.remove_theme_font_size_override("font_size")


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


## Anima o congela el decorado (torre y cielo). Congelado no cuesta nada por fotograma.
func _set_scenery_live(live: bool) -> void:
	_tower.animate = live
	_backdrop.animate = live
	if _climb_tween != null and _climb_tween.is_valid():
		if live:
			_climb_tween.play()
		else:
			_climb_tween.pause()


# ─── Acciones del menú ─────────────────────────────────────────

func _on_item(id: String) -> void:
	MenuKit.audio_call(self, "play_sfx", ["ui_click"])
	match id:
		"new_game":
			request_new_game()
		"continue":
			_continue_run()
		"gallery":
			open_gallery()
		"settings":
			open_settings()
		"quit":
			get_tree().quit()


func _open_entry(entry: String) -> void:
	match entry:
		GameLaunch.ENTRY_NEW_GAME:
			request_new_game()
		GameLaunch.ENTRY_GALLERY:
			open_gallery()


static func _run_exists() -> bool:
	return SaveSystem.has_method("run_exists") and SaveSystem.run_exists()


## Muestra una subpantalla sobre el título (atenúa y congela la torre y oculta el título).
func show_screen(screen: Control) -> void:
	close_screen()
	_screen = screen
	_screen_layer.add_child(screen)
	_title_layer.visible = false
	_set_scenery_live(false)
	var tween: Tween = create_tween()
	tween.tween_property(_tower, "modulate", DIM_COLOR, FADE_TIME)
	screen.modulate.a = 0.0
	tween.parallel().tween_property(screen, "modulate:a", 1.0, FADE_TIME)


## Cierra la subpantalla y vuelve al título (rehecho si el guardado cambió mientras tanto).
func close_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen_layer.remove_child(_screen)
		_screen.queue_free()
	_screen = null
	_title_layer.visible = true
	_tower.modulate = Color.WHITE
	_set_scenery_live(true)
	if _items.has("continue") != _run_exists():
		_rebuild_title()
	var first: Button = _items.get("new_game") as Button
	if first != null:
		MenuKit.focus_later(first)


func current_screen() -> Control:
	return _screen


## Abre la pantalla de ajustes.
func open_settings() -> void:
	var settings: SettingsMenu = SettingsMenu.new()
	settings.closed.connect(close_screen)
	settings.setting_changed.connect(_on_setting_changed)
	show_screen(settings)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "text_size" or key == "high_contrast":
		theme = MenuKit.build_theme()
		_rebuild_title.call_deferred()


## Abre la galería de finales.
func open_gallery() -> void:
	var gallery: EndingsGallery = EndingsGallery.new()
	gallery.closed.connect(close_screen)
	show_screen(gallery)


## Nueva partida: confirma si hay una en curso (permadeath) y abre el alta. Confirmar no borra
## nada todavía: la partida vieja muere al firmar el contrato nuevo (begin_new_run).
func request_new_game() -> void:
	if not _run_exists():
		open_name_entry()
		return
	show_screen(message_screen(tr("UI_CONFIRM_ABANDON_TITLE"), tr("UI_CONFIRM_ABANDON_BODY"), [
		[tr("UI_CONFIRM_ABANDON_YES"), open_name_entry],
		[tr("UI_CANCEL"), close_screen],
	]))


## Abre el formulario de alta (nombre + contrato).
func open_name_entry() -> void:
	var entry: NameEntry = NameEntry.new()
	entry.completed.connect(begin_new_run)
	entry.cancelled.connect(close_screen)
	show_screen(entry)


## Arranca una partida nueva con nombre y preset ya elegidos (apertura incluida). Si había una
## partida guardada, aquí termina (el jugador ya confirmó el abandono y firmó el contrato).
func begin_new_run(player_name: String, difficulty: String) -> void:
	_pending_name = player_name
	_pending_preset = difficulty
	if _run_exists() and SaveSystem.has_method("delete_run"):
		SaveSystem.delete_run()
	SettingsMenu.set_value("difficulty", difficulty)
	GameLaunch.remember_run_preset(difficulty)
	new_run_requested.emit(player_name, difficulty)
	var first_run: bool = not SettingsMenu.get_bool("opening_seen")
	GameLaunch.prepare_new_run(player_name, difficulty, false, first_run)
	if should_skip_opening():
		_launch_new_run(true, first_run)
	else:
		play_opening()


## true si la apertura se omite: --skip-intro, o ya vista y el jugador pidió omitirla.
static func should_skip_opening() -> bool:
	if Autopilot.get_arg("skip-intro") == "true":
		return true
	return SettingsMenu.get_bool("skip_seen_intro") and SettingsMenu.get_bool("opening_seen")


## Reproduce la apertura a pantalla completa; el decorado del menú se oculta y deja de animarse.
func play_opening() -> void:
	close_screen()
	_title_layer.visible = false
	_set_scenery_visible(false)
	_stop_menu_music()
	var packed: PackedScene = load(OPENING_SCENE) as PackedScene
	_cinematic = (packed.instantiate() as Control) if packed != null else OpeningCinematic.new()
	add_child(_cinematic)
	_cinematic.connect("finished", _on_opening_finished)
	_cinematic.call("play")


func _set_scenery_visible(shown: bool) -> void:
	_backdrop.visible = shown
	_tower.visible = shown
	_set_scenery_live(shown)


func cinematic() -> Control:
	return _cinematic


func _on_opening_finished(skipped: bool) -> void:
	var first_run: bool = not SettingsMenu.get_bool("opening_seen")
	SettingsMenu.set_value("opening_seen", true)
	_launch_new_run(skipped, first_run)


func _launch_new_run(intro_skipped: bool, first_run: bool) -> void:
	GameLaunch.prepare_new_run(_pending_name, _pending_preset, intro_skipped, first_run)
	_launch_or_placeholder()


## Continuar: vuelve a comprobar el guardado y reactiva el preset de esa partida (§15.7).
func _continue_run() -> void:
	if not _run_exists():
		_rebuild_title()
		show_screen(message_screen(tr("UI_CONTINUE_GONE_TITLE"), tr("UI_CONTINUE_GONE_BODY"), [[tr("UI_BACK"), close_screen]]))
		return
	var preset: String = GameLaunch.run_preset()
	GameLaunch.apply_preset(preset)
	continue_requested.emit()
	GameLaunch.prepare_load(preset)
	_launch_or_placeholder()


func _launch_or_placeholder() -> void:
	if GameLaunch.start_game(get_tree()):
		return
	get_tree().quit_on_go_back = false
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.queue_free()
	_cinematic = null
	_set_scenery_visible(true)
	show_screen(message_screen(tr("UI_PLACEHOLDER_TITLE"), MenuKit.trf("UI_PLACEHOLDER_BODY",
			{"name": _pending_name, "mode": GameLaunch.peek().get("mode", "")}), [[tr("UI_BACK"), _back_from_placeholder]]))
	_play_menu_music()


func _back_from_placeholder() -> void:
	GameLaunch.clear()
	close_screen()


## Pantalla de mensaje con botones: buttons = [[texto, Callable], ...].
func message_screen(title_text: String, body_text: String, buttons: Array) -> Control:
	var frame: Dictionary = MenuKit.memo_frame(title_text, tr("UI_MEMO_KICKER"), true)
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
		MenuKit.focus_later(row.get_child(0) as Button)
	return root


# ─── Música (única pieza no diegética junto a los epílogos, §14.9) ─

func _play_menu_music() -> void:
	MenuKit.audio_call(self, "play_menu_music", [], true)


func _stop_menu_music() -> void:
	MenuKit.audio_call(self, "stop_music", [])
