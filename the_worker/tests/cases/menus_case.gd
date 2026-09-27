# menus_case.gd — Cuerpo de test_menus: flujo de menús (PASO 46, §12.7, §13.9, §13.10, §15.7, §49).
# PROPIETARIO DE: nada (redirige SaveSystem a una carpeta temporal y la borra al terminar).
# ESCUCHA: finished/offer_chosen (OpeningCinematic), completed (NameEntry), setting_changed (SettingsMenu).
extends TestCase

## Nunca toca el perfil real: SaveSystem.set_storage_dir(TEMP_DIR) + forget_profile() al empezar.

## La apertura completa se reproduce acelerada; se espera en pasos cortos con un tope (≤ 12 s).
const PLAYBACK_SPEED := 400.0
const WAIT_STEP := 0.02
const MAX_WAITS := 600
const TEMP_DIR := "user://test_menus_tmp"
const FACTORY_OCCUPATION := "line_operator"
const SAME_RANK_OCCUPATION := "call_operator"
const LAYOUT_TOLERANCE := 1.5
## Pantalla de referencia (el visor headless es cuadrado): las pruebas de maquetación montan ahí.
const SCREEN_SIZE := Vector2(1920, 1080)


func run_case() -> void:
	_isolate_storage()
	_test_game_launch()
	await _test_settings()
	await _test_gallery()
	await _test_name_entry()
	await _test_contract_large_text()
	await _test_opening_skip()
	await _test_opening_choice()
	await _test_opening_full_run()
	await _test_epilogue()
	await _test_epilogue_records()
	await _test_tower_and_promotion()
	await _test_main_menu()
	await _test_abandon_and_continue()
	await _test_title_fits()
	_restore_storage()


# ─── Aislamiento del perfil ────────────────────────────────────

func _isolate_storage() -> void:
	MenuKit.spawn_audio = false
	SaveSystem.set_storage_dir(TEMP_DIR)
	SaveSystem.delete_run()
	_discard(SaveSystem.get_profile_path())
	SaveSystem.forget_profile()
	SettingsMenu.clear_session_cache()
	SettingsMenu.set_value("language", "en", false)


func _restore_storage() -> void:
	SaveSystem.delete_run()
	_discard(SaveSystem.get_profile_path())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	SettingsMenu.clear_session_cache()
	TranslationServer.set_locale("en")
	GameLaunch.clear()
	MenuKit.spawn_audio = true


static func _discard(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Simula una partida guardada (SaveSystem.run_exists() solo mira el archivo).
static func _fake_run() -> void:
	var file: FileAccess = FileAccess.open(SaveSystem.get_run_path(), FileAccess.WRITE)
	file.store_string("{}")
	file.close()


func _mount(control: Control) -> Control:
	add_child(control)
	await wait_frames(2)
	return control


## Monta dentro de un marco de SCREEN_SIZE (el control se ancla a pantalla completa en su padre).
func _mount_on_screen(control: Control) -> Control:
	var host: Control = Control.new()
	host.name = "Screen"
	host.size = SCREEN_SIZE
	add_child(host)
	host.add_child(control)
	await wait_frames(3)
	return control


# ─── GameLaunch y ajustes ──────────────────────────────────────

func _test_game_launch() -> void:
	GameLaunch.clear()
	check(not GameLaunch.has_pending(), "GameLaunch starts without a request")
	check_eq(GameLaunch.consume().get("mode"), "", "consume() without a request gives mode ''")
	GameLaunch.prepare_new_run("Ana Test", "auditoria", true, false)
	check(GameLaunch.has_pending(), "prepare_new_run leaves a pending request")
	check_eq(GameLaunch.peek().get("player_name"), "Ana Test", "peek() keeps the chosen name")
	var request: Dictionary = GameLaunch.consume()
	check_eq(request.get("mode"), GameLaunch.MODE_NEW, "new-run request mode")
	check_eq(request.get("difficulty"), "auditoria", "new-run request carries the preset")
	check_eq(request.get("intro_skipped"), true, "new-run request carries intro_skipped")
	check_eq(request.get("portrait_seed"), GameLaunch.portrait_seed_for("ana test"), "portrait seed derives from the name")
	check(not GameLaunch.has_pending(), "consume() clears the request")
	GameLaunch.prepare_load("interno")
	var load_request: Dictionary = GameLaunch.consume()
	check_eq(load_request.get("mode"), GameLaunch.MODE_LOAD, "continue request mode is 'load'")
	check_eq(load_request.get("difficulty"), "interno", "continue request carries the run's preset")
	GameLaunch.menu_entry = GameLaunch.ENTRY_GALLERY
	check_eq(GameLaunch.take_menu_entry(), GameLaunch.ENTRY_GALLERY, "menu entry handed to the menu once")
	check_eq(GameLaunch.take_menu_entry(), GameLaunch.ENTRY_TITLE, "menu entry resets after being taken")
	check_eq(GameLaunch.game_scene_exists(), ResourceLoader.exists(GameLaunch.GAME_SCENE), "game scene detection")


func _test_settings() -> void:
	check(SettingsMenu.values_match(2, 2.0), "settings compare 2 and 2.0 as equal (JSON round trip)")
	check(not SettingsMenu.values_match(true, 1), "settings do not confuse true with 1")
	check(MenuKit.bal_float("menus.apertura.m1_segundos") > 0.0, "menu tunables readable from balance")
	var persisted: bool = SettingsMenu.set_value("text_size", 2, true)
	check_eq(SettingsMenu.get_int("text_size"), 2, "text_size readable after set_value")
	check_near(MenuKit.text_scale(), float((MenuKit.bal("menus.escala_texto") as Array)[2]), 0.001, "text scale follows the setting at once")
	check(persisted, "save_profile() reported success")
	check(FileAccess.file_exists(SaveSystem.get_profile_path()), "the profile is written in the redirected folder")
	SaveSystem.forget_profile()
	SaveSystem.load_profile()
	check(SettingsMenu.values_match(SaveSystem.get_setting("text_size"), 2), "setting survives load_profile()")
	SettingsMenu.set_value("text_size", 1, true)
	SettingsMenu.set_value("language", "es", false)
	check_eq(TranslationServer.get_locale(), "es", "language setting switches the locale live")
	check_eq(tr("UI_MENU_QUIT"), "Salir", "Spanish strings after the switch")
	SettingsMenu.set_value("language", "en", false)
	check(not MenuKit.is_high_contrast(), "high contrast off by default")
	SettingsMenu.set_value("high_contrast", true, false)
	check(MenuKit.is_high_contrast(), "high contrast cache refreshes when the setting changes")
	check_eq(MenuKit.heading_color(Color.RED), MenuKit.color("ink"), "small headings use pure ink in high contrast")
	SettingsMenu.set_value("high_contrast", false, false)
	await _test_settings_screen()


func _test_settings_screen() -> void:
	var screen: SettingsMenu = await _mount(SettingsMenu.new()) as SettingsMenu
	var changes: Array = []
	screen.setting_changed.connect(func(key: String, value: Variant) -> void: changes.append([key, value]))
	var row: Node = screen.find_child("Row_text_size", true, false)
	check(row != null, "settings screen has a text size row")
	for key: String in ["Row_language", "Row_high_contrast", "Row_colorblind_safe", "Row_clock_speed",
			"Row_difficulty", "Row_max_agents", "Row_subtitles", "Row_music_volume", "Row_sfx_volume"]:
		check(screen.find_child(key, true, false) != null, "settings screen has %s" % key)
	check(screen.find_child("ScrollArea", true, false) is MenuScroll, "settings scroll with a visible affordance")
	var small: Button = row.find_child("Opt_0", true, false) as Button if row != null else null
	if small != null:
		small.pressed.emit()
	check_eq(SettingsMenu.get_int("text_size"), 0, "pressing 'Small' stores text_size 0")
	check(changes.size() > 0 and changes[0][0] == "text_size", "setting_changed emitted")
	SettingsMenu.set_value("text_size", 1, false)
	screen.queue_free()
	await wait_frames(2)


# ─── Galería ───────────────────────────────────────────────────

func _test_gallery() -> void:
	var gallery: EndingsGallery = EndingsGallery.new()
	var unlocked: Array[String] = ["the_worker", "the_file"]
	gallery.setup(unlocked)
	await _mount(gallery)
	check_eq(gallery.card_count(), 9, "gallery shows the nine endings")
	check_eq(gallery.unlocked_count(), 2, "gallery counts two unlocked endings")
	check_eq(gallery.get_card_state("the_worker"), "unlocked", "unlocked ending shows as unlocked")
	check_eq(gallery.get_card_state("the_butcher"), "locked", "locked ending shows as a silhouette")
	var locked_card: Node = gallery.find_child("Card_the_butcher", true, false)
	check(locked_card != null and str(locked_card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)).contains(tr("UI_GALLERY_LOCKED_NAME").to_upper()), "locked card hides the ending name")
	gallery.queue_free()
	SaveSystem.unlock_ending("the_ghost")
	SaveSystem.unlock_ending("the_ghost@husk")
	var profile_gallery: EndingsGallery = await _mount(EndingsGallery.new()) as EndingsGallery
	check_eq(profile_gallery.get_card_state("the_ghost"), "unlocked", "gallery reads an ending unlocked in the profile")
	check_eq(profile_gallery.unlocked_count(), 1, "only the profile's unlock shows (the ruin variant is not a card)")
	check_eq(profile_gallery.get_card_state("the_buyer"), "locked", "other endings stay locked")
	profile_gallery.size = Vector2(900, 1000)
	await wait_frames(1)
	var grid: GridContainer = profile_gallery.find_child("Grid", true, false) as GridContainer
	check(grid != null and grid.columns == EndingsGallery.NARROW_COLUMNS, "gallery columns follow a resize")
	profile_gallery.queue_free()
	check_eq(EndingsGallery.ending_axis(EndingsGallery.find_ending("the_butcher")), "blood", "butcher tinted blood")
	check_eq(EndingsGallery.ending_axis(EndingsGallery.find_ending("the_full_suite")), "hybrid", "full suite is hybrid")
	check_eq(EndingsGallery.ending_axis(EndingsGallery.find_ending("the_file")), "defeat", "the file is a defeat")
	check_eq(EndingsGallery.ending_axis(EndingsGallery.find_ending("the_figurehead"), "gold"), "gold", "partial endings use the run's axis")
	await wait_frames(2)


# ─── Alta y contrato ───────────────────────────────────────────

func _test_name_entry() -> void:
	check_eq(NameEntry.sanitize_name("  Ana   de  la Torre  "), "Ana de la Torre", "names are trimmed and collapsed")
	check_eq(NameEntry.sanitize_name("\tX\n"), "X", "control characters are removed")
	var limit: int = MenuKit.bal_int("menus.nombre_max_caracteres")
	check_eq(NameEntry.sanitize_name("A".repeat(limit + 10)).length(), limit, "names are capped at the balance limit")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = DEFAULT_SEED
	check(not NameEntry.suggest_name(rng).is_empty(), "a name can be suggested from the data name bank")
	var entry: NameEntry = await _mount(NameEntry.new()) as NameEntry
	var result: Array = []
	entry.completed.connect(func(n: String, d: String) -> void: result.append([n, d]))
	entry.set_name_text("   ")
	(entry.find_child("Next", true, false) as Button).pressed.emit()
	check(entry.find_child("NameEdit", true, false) != null, "an empty name keeps the form on the name step")
	entry.set_name_text("  Ana  ")
	(entry.find_child("Next", true, false) as Button).pressed.emit()
	await wait_frames(1)
	var audit: Button = entry.find_child("Card_auditoria", true, false) as Button
	check(audit != null, "contract step shows the three presets")
	if audit != null:
		audit.pressed.emit()
	entry.go_back()
	check_eq(entry.current_step(), NameEntry.STEP_NAME, "back from the contract returns to the name step")
	(entry.find_child("Next", true, false) as Button).pressed.emit()
	await wait_frames(1)
	(entry.find_child("Sign", true, false) as Button).pressed.emit()
	check(result.size() == 1 and result[0] == ["Ana", "auditoria"], "signing emits the clean name and the preset")
	entry.queue_free()
	await wait_frames(2)


## Texto grande en español: las tarjetas crecen con su contenido y el panel no se sale de la pantalla.
func _test_contract_large_text() -> void:
	SettingsMenu.set_value("text_size", 2, false)
	SettingsMenu.set_value("language", "es", false)
	var entry: NameEntry = await _mount_on_screen(NameEntry.new()) as NameEntry
	entry.set_name_text("Dolores Fuertes de Barriga")
	entry.go_to_step(NameEntry.STEP_CONTRACT)
	await wait_frames(4)
	var screen: Rect2 = Rect2(Vector2.ZERO, SCREEN_SIZE)
	for preset: String in SettingsMenu.PRESETS:
		var card: Button = entry.find_child("Card_" + preset, true, false) as Button
		var contents: Control = card.find_child("Contents", true, false) as Control
		var need: float = contents.get_combined_minimum_size().y + NameEntry.CARD_PAD * 2
		check(card.size.y + LAYOUT_TOLERANCE >= need, "contract card '%s' is tall enough for its text" % preset)
	var panel: Control = entry.find_children("*", "PanelContainer", true, false)[0] as Control
	var rect: Rect2 = panel.get_global_rect()
	check(rect.end.x <= screen.end.x + LAYOUT_TOLERANCE and rect.end.y <= screen.end.y + LAYOUT_TOLERANCE,
			"the contract panel stays on screen at Large text (%s in %s)" % [rect, screen])
	var area: MenuScroll = entry.find_child("ScrollArea", true, false) as MenuScroll
	check(area != null, "the compact memo scrolls when the contract does not fit")
	entry.get_parent().queue_free()
	SettingsMenu.set_value("text_size", 1, false)
	SettingsMenu.set_value("language", "en", false)
	await wait_frames(2)


# ─── Apertura ──────────────────────────────────────────────────

func _new_opening() -> OpeningCinematic:
	var packed: PackedScene = load(MainMenu.OPENING_SCENE) as PackedScene
	check(packed != null, "opening scene loads")
	var cine: OpeningCinematic = packed.instantiate() as OpeningCinematic
	check(cine != null, "opening scene root is an OpeningCinematic")
	await _mount(cine)
	return cine


func _test_opening_skip() -> void:
	var cine: OpeningCinematic = await _new_opening()
	var events: Array = []
	cine.finished.connect(func(skipped: bool) -> void: events.append(skipped))
	cine.play()
	await wait_frames(3)
	check(cine.is_playing(), "opening plays")
	check(cine.total_duration() > 60.0, "opening lasts around ninety seconds")
	cine.skip()
	check_eq(events, [true], "skip() emits finished(true) once")
	check(not cine.is_playing(), "opening stops after skipping")
	cine.skip()
	check_eq(events.size(), 1, "a second skip does not emit again")
	cine.queue_free()
	await wait_frames(2)


func _test_opening_choice() -> void:
	var cine: OpeningCinematic = await _new_opening()
	var chosen: Array = []
	cine.offer_chosen.connect(func() -> void: chosen.append(true))
	cine.play()
	cine.seek(cine.choice_time())
	cine.present_offers()
	check(cine.is_waiting_choice(), "the fan of offers waits for the player")
	check(cine.is_hint_visible(), "the choice hint shows while waiting")
	var stage: OpeningStage = cine.find_child("Back", false, false) as OpeningStage
	check(stage.card_at(cine.offer_center(0)) == 0, "a greyed-out offer can be hit")
	check_eq(stage.card_at(cine.offer_center(OpeningStage.STELLAR_CARD)), OpeningStage.STELLAR_CARD, "the Stellar Sell offer is on top")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = cine.offer_center(0) + Vector2(-60, 60)
	cine._gui_input(click)
	check(chosen.is_empty() and cine.is_waiting_choice(), "greyed-out offers cannot be chosen")
	click.position = cine.offer_center(OpeningStage.STELLAR_CARD)
	cine._gui_input(click)
	check_eq(chosen.size(), 1, "clicking Stellar Sell makes the only (fake) choice")
	check(not cine.is_waiting_choice(), "the choice closes the wait")
	cine.present_offers()
	cine.seek(cine.movement_start(1) + 1.0)
	check(not cine.is_hint_visible(), "seeking past the offers hides the choice hint")
	cine.skip()
	cine.queue_free()
	await wait_frames(2)


func _test_opening_full_run() -> void:
	var cine: OpeningCinematic = await _new_opening()
	var movements: Array = []
	var done: Array = []
	cine.movement_started.connect(func(i: int) -> void: movements.append(i))
	cine.finished.connect(func(skipped: bool) -> void: done.append(skipped))
	cine.playback_speed = PLAYBACK_SPEED
	cine.play()
	for i: int in MAX_WAITS:
		if not done.is_empty():
			break
		await get_tree().create_timer(WAIT_STEP).timeout
	check_eq(done, [false], "the opening completes on its own and emits finished(false)")
	check(movements.has(1) and movements.has(2) and movements.has(3), "all movements and the title play")
	var captioned: Array = []
	for cue: Array in OpeningCinematic.SOUND_CUES:
		captioned.append(str(cue[2]))
	check(captioned.has(OpeningSounds.ENGINE) and captioned.has(OpeningSounds.BRAKES), "the bus captions have real sounds")
	check(OpeningSounds.render_brakes(8000).size() > 0 and SynthDSP.peak(OpeningSounds.render_engine(8000)) > 0.0, "bus sounds synthesise")
	cine.queue_free()
	await wait_frames(2)


# ─── Epílogos ──────────────────────────────────────────────────

func _test_epilogue() -> void:
	var gap: String = EpilogueScreen.compose_text("the_gap", {"name": "Ana", "days": 3, "successor": "Bob"})
	check(gap.contains("Ana") and gap.contains("Bob"), "epilogue text uses the run context")
	check(not gap.contains("{"), "no raw placeholders left in the epilogue")
	var butcher: String = EpilogueScreen.compose_text("the_butcher", {"name": "Ana", "ruin_tier": "husk"})
	check(butcher.contains(tr("UI_EPILOGUE_REDACTED")), "missing placeholders are redacted")
	check(butcher.contains("\n\n"), "victory epilogues append the ruin variant")
	check_eq(EpilogueScreen.defeat_floor("the_file"), Database.get_room(EpilogueScreen.ARCHIVE_ROOM).floor, "the file highlights the archive floor from data")
	var screen: EpilogueScreen = EpilogueScreen.create("the_file", {"name": "Ana", "cause": "investigation_conclusive"})
	check(not screen.record_on_ready, "create() does not touch the profile by default")
	var closes: Array = []
	screen.closed.connect(func(again: bool) -> void: closes.append(again))
	await _mount(screen)
	await wait_frames(2)
	check(screen.is_typing(), "the epilogue types itself out")
	var start_over: Button = screen.find_child("StartOver", true, false) as Button
	check(start_over.disabled and start_over.mouse_filter == Control.MOUSE_FILTER_IGNORE, "buttons are inert while typing")
	var title: Label = screen.find_child("EndingName", true, false) as Label
	check(title != null and title.text == tr("ENDING_THE_FILE").to_upper(), "the ending name is shown")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._input(click)
	check(not screen.is_typing(), "a click completes the typewriter")
	start_over.pressed.emit()
	check(closes.is_empty() and not screen.buttons_ready(), "the skipping click cannot close the epilogue")
	screen.reveal_buttons()
	await wait_frames(2)
	check_eq(get_viewport().gui_get_focus_owner(), screen.find_child("ToMenu", true, false), "focus lands on 'Main menu'")
	start_over.pressed.emit()
	check_eq(closes, [true], "'New hire' closes the epilogue asking for a new run")
	screen.queue_free()
	await wait_frames(2)


## Registro del final: desbloqueo + variante de ruina + borrado de la partida (idempotente).
func _test_epilogue_records() -> void:
	_fake_run()
	var screen: EpilogueScreen = EpilogueScreen.create("the_butcher", {"name": "Ana", "ruin_tier": "husk"}, true)
	await _mount(screen)
	var unlocked: Array[String] = SaveSystem.get_unlocked_endings()
	check(unlocked.has("the_butcher") and unlocked.has("the_butcher@husk"), "the epilogue records the ending and its ruin variant")
	check(not SaveSystem.run_exists(), "permadeath: the run is deleted")
	screen.queue_free()
	await wait_frames(2)


# ─── Torre y promoción ─────────────────────────────────────────

func _test_tower_and_promotion() -> void:
	var tower: TowerArt = TowerArt.new()
	tower.size = Vector2(900, 1000)
	await _mount(tower)
	check(tower.floor_rect(20).position.y < tower.floor_rect(0).position.y, "floor 20 is drawn above the ground floor")
	check(tower.floor_rect(-1).position.y >= tower.ground_y() - 1.0, "basements are below the street")
	check(tower.floor_rect(TowerArt.factory_floor()).position.x > tower.floor_rect(0).position.x, "factory annex beside the tower")
	check_eq(str(MenuKit.band_for_floor(15).get("id", "")), "the_power", "floor 15 uses the_power palette")
	check_eq(TowerArt.floor_label(0), tr("UI_TOWER_GROUND_SHORT"), "ground floor label is localised")
	check(tower.get_child_count() == 0 and tower.get_child_count(true) == 2, "the cached and animated layers are internal children")
	check(tower.cache_static, "the static cut is cached in a texture by default")
	tower.queue_free()
	var host: Control = await _mount(Control.new())
	var promo: PromotionScreen = PromotionScreen.present(host, "email_worker_3b", "order_filer", "merit")
	var finished: Array = []
	promo.finished.connect(func() -> void: finished.append(true))
	await wait_frames(3)
	check(promo.is_promotion() and not promo.is_transfer(), "R1 → R2 counts as a promotion")
	promo.skip_to_end()
	var display: Label = promo.find_child("FloorDisplay", true, false) as Label
	check(display != null and not display.text.is_empty(), "the elevator display shows the destination floor")
	promo.close()
	check_eq(finished.size(), 1, "closing the promotion screen emits finished")
	var factory: PromotionScreen = PromotionScreen.present(host, SAME_RANK_OCCUPATION, FACTORY_OCCUPATION, "transfer")
	await wait_frames(2)
	check(factory.is_transfer() and not factory.is_promotion(), "same rank is a transfer, not a promotion")
	check_eq(factory.destination_floor(), TowerArt.factory_floor(), "a factory post lands in the annex")
	check_eq(factory.destination_stop(), 0, "the elevator stops at the ground floor for the factory")
	check_eq((factory.find_child("Title", true, false) as Label).text, tr("PROMO_TITLE_SAME").to_upper(), "transfer title")
	factory.close()
	host.queue_free()
	await wait_frames(2)


# ─── Menú principal ────────────────────────────────────────────

func _test_main_menu() -> void:
	var menu: MainMenu = await _mount(MainMenu.new()) as MainMenu
	check(menu.find_child("Item_new_game", true, false) != null, "main menu offers New game")
	check_eq(menu.find_child("Item_continue", true, false) != null, SaveSystem.run_exists(), "Continue only when a run exists")
	menu.open_settings()
	check(menu.current_screen() is SettingsMenu, "Settings opens over the title")
	var tower: TowerArt = menu.find_child("Tower", false, false) as TowerArt
	check(tower != null and not tower.animate, "the title tower freezes under a screen")
	menu.go_back()
	check(menu.current_screen() == null, "Back returns to the title")
	check(tower.animate, "the title tower animates again")
	menu.open_gallery()
	check(menu.current_screen() is EndingsGallery, "Endings opens the gallery")
	menu.close_screen()
	SettingsMenu.set_value("skip_seen_intro", true, false)
	SettingsMenu.set_value("opening_seen", true, false)
	check(MainMenu.should_skip_opening(), "a seen opening is skipped when the player asked for it")
	SettingsMenu.set_value("skip_seen_intro", false, false)
	check(MainMenu.should_skip_opening() == (Autopilot.get_arg("skip-intro") == "true"), "otherwise the opening plays")
	SettingsMenu.set_value("opening_seen", false, false)
	menu.play_opening()
	await wait_frames(1)
	check(not tower.visible and not tower.animate, "the menu tower is hidden and frozen under the opening")
	(menu.cinematic() as OpeningCinematic).skip()
	await wait_frames(2)
	GameLaunch.clear()
	menu.queue_free()
	await wait_frames(2)


## Abandonar: confirmar no borra; cancelar el alta conserva la partida; firmar la borra.
func _test_abandon_and_continue() -> void:
	if GameLaunch.game_scene_exists():
		print("NOTE: game.tscn exists; the placeholder paths of the menu are not exercised")
		return
	_fake_run()
	SettingsMenu.set_value("skip_seen_intro", true, false)
	SettingsMenu.set_value("opening_seen", true, false)
	var menu: MainMenu = await _mount(MainMenu.new()) as MainMenu
	check(menu.find_child("Item_continue", true, false) != null, "a saved run shows Continue")
	menu.request_new_game()
	check(SaveSystem.run_exists(), "confirming the abandon screen deletes nothing yet")
	menu.open_name_entry()
	(menu.current_screen() as NameEntry).cancelled.emit()
	await wait_frames(2)
	check(SaveSystem.run_exists() and menu.find_child("Item_continue", true, false) != null, "cancelling the new hire keeps the run and Continue")
	menu.begin_new_run("Ana", "auditoria")
	check(not SaveSystem.run_exists(), "signing the new contract ends the old run")
	check_eq(GameLaunch.run_preset(), "auditoria", "the run's preset is remembered in the profile")
	check(menu.current_screen() != null, "without game.tscn a placeholder screen is shown")
	menu.close_screen()
	await wait_frames(2)
	check(menu.find_child("Item_continue", true, false) == null, "the title drops Continue once the run is gone")
	await _test_continue(menu)


## Continuar reactiva el preset de la partida; sin guardado, aviso en vez de cargar.
func _test_continue(menu: MainMenu) -> void:
	_fake_run()
	Database.set_difficulty_preset("estandar")
	menu.close_screen()
	await wait_frames(2)
	(menu.find_child("Item_continue", true, false) as Button).pressed.emit()
	check_eq(Database.get_difficulty_preset(), "auditoria", "Continue restores the run's difficulty preset")
	check_eq(GameLaunch.peek().get("difficulty"), "auditoria", "the load request carries the preset")
	menu.close_screen()
	await wait_frames(2)
	SaveSystem.delete_run()
	GameLaunch.clear()
	(menu.find_child("Item_continue", true, false) as Button).pressed.emit()
	check(not GameLaunch.has_pending() and menu.current_screen() != null, "Continue without a save shows a notice instead of loading")
	menu.queue_free()
	Database.set_difficulty_preset(str(MenuKit.bal("presets_por_defecto")))
	await wait_frames(2)


## Con partida guardada (5 elementos), texto grande y en español, la columna cabe sobre la calle.
func _test_title_fits() -> void:
	_fake_run()
	SettingsMenu.set_value("text_size", 2, false)
	SettingsMenu.set_value("language", "es", false)
	var menu: MainMenu = await _mount_on_screen(MainMenu.new()) as MainMenu
	await wait_frames(4)
	var quit: Control = menu.find_child("Item_quit", true, false) as Control
	var road_top: float = menu.size.y - float((menu.find_child("TitleColumn", true, false) as MarginContainer).get_theme_constant("margin_bottom"))
	check(quit != null and quit.get_global_rect().end.y <= road_top + LAYOUT_TOLERANCE,
			"'Quit' stays above the street with 5 items at Large text in Spanish (level %d)" % menu.fit_level())
	var column: Control = menu.find_child("Column", true, false) as Control
	check(column.get_combined_minimum_size().y <= menu.title_space() + LAYOUT_TOLERANCE, "the title column fits its space")
	menu.get_parent().queue_free()
	SaveSystem.delete_run()
	SettingsMenu.set_value("text_size", 1, false)
	SettingsMenu.set_value("language", "en", false)
	await wait_frames(2)
