# menus.gd (escenario) — Capturas de menú, ajustes (EN/ES), alta, galería, apertura, epílogos, promoción y error.
# PROPIETARIO DE: nada (monta cada pantalla, la fotografía y la retira).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_menus menus
## Los datos de ejemplo (nombre, cifras) son de QA; no se muestran en el juego real.
## SaveSystem se redirige a una carpeta temporal: el perfil real del desarrollador no se toca.

const PHONE_SIZE := Vector2i(1280, 592)
const SETTLE := 1.2
const TEMP_DIR := "user://qa_menus_tmp"

var _pilot: Autopilot


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	_isolate_storage()
	await pilot.frames(5)
	await _title_and_screens()
	await _title_variants()
	await _contract_large()
	await _opening()
	await _epilogues()
	await _promotion()
	await _boot_error()
	await _phone()
	_restore_storage()


func _isolate_storage() -> void:
	SaveSystem.set_storage_dir(TEMP_DIR)
	SaveSystem.delete_run()
	SaveSystem.forget_profile()
	SettingsMenu.clear_session_cache()


func _restore_storage() -> void:
	SaveSystem.delete_run()
	var profile: String = SaveSystem.get_profile_path()
	if FileAccess.file_exists(profile):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile))
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	SettingsMenu.clear_session_cache()
	TranslationServer.set_locale("en")


## Partida guardada ficticia (solo para que aparezca «Continuar»).
static func _fake_run() -> void:
	var file: FileAccess = FileAccess.open(SaveSystem.get_run_path(), FileAccess.WRITE)
	file.store_string("{}")
	file.close()


func _mount(control: Control) -> Control:
	add_child(control)
	return control


func _unmount(control: Control) -> void:
	remove_child(control)
	control.queue_free()
	await _pilot.frames(2)


func _title_and_screens() -> void:
	var menu: MainMenu = _mount(MainMenu.new()) as MainMenu
	await _pilot.seconds(SETTLE * 2.0)
	await _pilot.shot("menu_title")
	menu.open_settings()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("settings_en")
	SettingsMenu.set_value("language", "es", false)
	await _pilot.seconds(SETTLE)
	await _pilot.shot("settings_es")
	menu.close_screen()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("menu_title_es")
	SettingsMenu.set_value("language", "en", false)
	await _high_contrast(menu)
	await _new_hire(menu)
	for id: String in ["the_worker", "the_file", "the_ghost", "the_gap", "the_worker@husk"]:
		SaveSystem.unlock_ending(id)
	menu.open_gallery()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("gallery")
	await _unmount(menu)


func _high_contrast(menu: MainMenu) -> void:
	SettingsMenu.set_value("high_contrast", true, false)
	menu.theme = MenuKit.build_theme()
	menu.open_settings()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("settings_high_contrast")
	SettingsMenu.set_value("high_contrast", false, false)
	menu.theme = MenuKit.build_theme()
	menu.close_screen()


func _new_hire(menu: MainMenu) -> void:
	var entry: NameEntry = NameEntry.new()
	menu.show_screen(entry)
	await _pilot.seconds(SETTLE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	entry.set_name_text(NameEntry.suggest_name(rng))
	await _pilot.seconds(0.3)
	await _pilot.shot("name_entry")
	entry.go_to_step(NameEntry.STEP_CONTRACT)
	await _pilot.seconds(SETTLE)
	await _pilot.shot("contract")


## Título con partida guardada (cinco elementos) en EN medio y en ES grande.
func _title_variants() -> void:
	_fake_run()
	var menu: MainMenu = _mount(MainMenu.new()) as MainMenu
	await _pilot.seconds(SETTLE * 1.5)
	await _pilot.shot("menu_title_continue")
	await _unmount(menu)
	SettingsMenu.set_value("text_size", 2, false)
	SettingsMenu.set_value("language", "es", false)
	menu = _mount(MainMenu.new()) as MainMenu
	await _pilot.seconds(SETTLE * 1.5)
	await _pilot.shot("menu_title_large_es")
	await _unmount(menu)
	SettingsMenu.set_value("text_size", 1, false)
	SettingsMenu.set_value("language", "en", false)


## El contrato con texto grande: EN y ES (tarjetas que crecen, marco que desplaza si no cabe).
func _contract_large() -> void:
	SettingsMenu.set_value("text_size", 2, false)
	for locale: String in ["en", "es"]:
		SettingsMenu.set_value("language", locale, false)
		var entry: NameEntry = _mount(NameEntry.new()) as NameEntry
		entry.set_name_text("Dolores Fuertes de Barriga")
		entry.go_to_step(NameEntry.STEP_CONTRACT)
		await _pilot.seconds(SETTLE)
		await _pilot.shot("contract_large_" + locale)
		await _unmount(entry)
	SettingsMenu.set_value("text_size", 1, false)
	SettingsMenu.set_value("language", "en", false)


func _opening() -> void:
	var packed: PackedScene = load(MainMenu.OPENING_SCENE) as PackedScene
	var cine: OpeningCinematic = _mount(packed.instantiate() as Control) as OpeningCinematic
	GameLaunch.prepare_new_run("Morgan", "estandar")
	var d1: float = cine.movement_start(1)
	var d2: float = cine.movement_start(2) - d1
	var d3: float = cine.movement_start(3) - cine.movement_start(2)
	var d4: float = cine.total_duration() - cine.movement_start(3)
	var m3: float = cine.movement_start(2)
	var moments: Array[Array] = [
		["opening_1_caps", d1 * 0.27], ["opening_1_offers", cine.choice_time()], ["opening_1_hired", d1 * 0.72],
		["opening_2_bus", d1 + d2 * 0.18], ["opening_2_tower", d1 + d2 * 0.62], ["opening_2_floors", d1 + d2 * 0.9],
		["opening_3_arrive", m3 + d3 * 0.3], ["opening_3_turnstile", m3 + d3 * 0.5], ["opening_3_welcome", m3 + d3 * 0.78],
		["opening_4_title", cine.movement_start(3) + d4 * 0.6],
	]
	for moment: Array in moments:
		cine.seek(float(moment[1]))
		await _pilot.seconds(0.4)
		await _pilot.shot(str(moment[0]))
	GameLaunch.clear()
	await _unmount(cine)


func _epilogues() -> void:
	var context: Dictionary = {
		"name": "Morgan Hale", "days": 212, "company_value": "€1.9 bn", "share_price": "€48.20",
		"ruin_tier": "empire", "case_id": "INV-0457", "investigator": "Dolores Kent", "evidence_count": 17,
		"cause": "investigation_conclusive",
	}
	for id: String in ["the_worker", "the_file", "the_gap"]:
		var ctx: Dictionary = context.duplicate()
		if id == "the_worker":
			ctx.erase("cause")
		elif id == "the_gap":
			ctx["cause"] = "failed_at_r0"
			ctx["successor"] = "Priya Nandakumar"
		var screen: EpilogueScreen = _mount(EpilogueScreen.create(id, ctx)) as EpilogueScreen
		await _pilot.seconds(1.5)
		if id == "the_worker":
			await _pilot.shot("epilogue_%s_typing" % id)
		screen.finish_typing()
		await _pilot.seconds(1.0)
		await _pilot.shot("epilogue_%s" % id)
		await _unmount(screen)


func _promotion() -> void:
	var screen: PromotionScreen = PromotionScreen.present(self, "junior_sales", "senior_sales", "merit")
	await _pilot.seconds(0.6)
	await _pilot.shot("promotion_riding")
	screen.skip_to_end()
	await _pilot.seconds(0.3)
	await _pilot.shot("promotion")
	await _unmount(screen)
	screen = PromotionScreen.present(self, "call_operator", "line_operator", "transfer")
	await _pilot.seconds(0.2)
	screen.skip_to_end()
	await _pilot.seconds(0.3)
	await _pilot.shot("promotion_factory")
	await _unmount(screen)


func _boot_error() -> void:
	var errors: Array[String] = [
		"occupations.json → entrada 7 → campo 'rank': fuera de rango (esperado 0..33, recibido 41)",
		"rooms/p03.json → entrada 2 → campo 'connects_to': sala inexistente (esperado id de sala, recibido 'wing_9z')",
	]
	var screen: Control = _mount(BootScreen.build_error_screen(errors))
	await _pilot.seconds(0.6)
	await _pilot.shot("boot_error")
	await _unmount(screen)


func _phone() -> void:
	var window: Window = get_window()
	var original: Vector2i = window.size
	window.size = PHONE_SIZE
	await _pilot.frames(10)
	_fake_run()
	var menu: MainMenu = _mount(MainMenu.new()) as MainMenu
	await _pilot.seconds(SETTLE * 2.0)
	await _pilot.shot("phone_title")
	SettingsMenu.set_value("text_size", 2, false)
	menu.open_settings()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("phone_settings_large")
	menu.open_name_entry()
	var entry: NameEntry = menu.current_screen() as NameEntry
	entry.set_name_text("Morgan Hale")
	entry.go_to_step(NameEntry.STEP_CONTRACT)
	await _pilot.seconds(SETTLE)
	await _pilot.shot("phone_contract_large")
	SettingsMenu.set_value("text_size", 1, false)
	menu.open_gallery()
	await _pilot.seconds(SETTLE)
	await _pilot.shot("phone_gallery")
	await _unmount(menu)
	window.size = original
