# stellar_os.gd (escenario) — Capturas de StellarOS: arranque y escritorio por nivel del equipo, MAIL, A.S.S.I.S.T. (los tres resultados), NOTEBOOK, FILES propio e intrusión, y móvil.
# PROPIETARIO DE: nada (monta una partida de muestra, una UIRoot y un DutySystem para las capturas).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_stellar_os stellar_os

const RUN_SEED := 4242
const LIFECYCLE: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]
const OWNER := "npc_claudia_reeves"
const DEBTOR := "npc_george_penn"
const CREDITOR := "npc_sonia_vail"
const TARGET := "npc_bernard_lasker"
const AWAY_ROOM := "p3_pantry"
const PHONE_WINDOW := Vector2i(1170, 540)
const DESKTOP_WINDOW := Vector2i(1600, 900)
const PLAYER_NAME := "Morgan"
const PERSONNEL_SCRIPT := "res://src/ui/stellar_os/personnel_app.gd"

var _ui: UIRoot
var _ds: DutySystem


func run(pilot: Autopilot) -> void:
	_new_run()
	_ui = UIRoot.new()
	add_child(_ui)
	await pilot.frames(3)
	await _shot_boot(pilot)
	await _shot_desktops(pilot)
	await _shot_mail(pilot)
	await _shot_assist(pilot)
	await _shot_notebook(pilot)
	await _shot_files(pilot)
	await _shot_phone(pilot)
	await _shot_spanish(pilot)


func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(RUN_SEED)
	for system_name: String in LIFECYCLE:
		var node: Node = get_tree().root.get_node_or_null(NodePath(system_name))
		if node == null:
			continue
		if node.has_method("reset_for_new_run"):
			node.call("reset_for_new_run")
		if system_name == "NPCDirector":
			node.call("generate_population")
		elif system_name == "SocialGraph":
			node.call("build_initial_graph")
		if system_name == "GameClock":
			GameClock.set_run_seed(RUN_SEED)
	GameClock.set_time(3, 10, 42)
	GameClock.resume()
	PlayerState.set_player_name(PLAYER_NAME)
	if _ds != null:
		_ds.remove_from_group(DutySystem.GROUP)
		_ds.queue_free()
	_ds = DutySystem.new()
	add_child(_ds)
	_ds.set_witness_provider(func() -> Array: return [])


func _computer() -> StellarOS:
	return _ui.get_top_modal() as StellarOS


func _close() -> void:
	while _ui.has_modal():
		_ui.close_modal()
	await get_tree().process_frame


## Captura sin los avisos de UIRoot que se acumulan al rehacer la partida de muestra.
func _shot(pilot: Autopilot, shot_name: String) -> void:
	_ui.get_toasts().clear()
	await pilot.frames(2)
	await pilot.shot(shot_name)


## Espera (segundos reales) a que la aplicación abierta sea la pedida.
func _wait_app(pilot: Autopilot, app_id: String, timeout: float) -> Control:
	var waited: float = 0.0
	while waited < timeout:
		var os: StellarOS = _computer()
		if os != null and os.get_open_app_id() == app_id and os.get_open_app() != null:
			return os.get_open_app()
		await pilot.seconds(0.1)
		waited += 0.1
	return null


# ─── Arranque y escritorios ───────────────────────────────────────

func _shot_boot(pilot: Autopilot) -> void:
	_ui.open_computer({"tier": 1})
	await pilot.seconds(1.6)
	await _shot(pilot, "os_boot_tier1_bios")
	await pilot.seconds(2.6)
	await _shot(pilot, "os_boot_tier1_splash")
	await _close()
	_ui.open_computer({"tier": 5})
	await pilot.seconds(1.0)
	await _shot(pilot, "os_boot_tier5_splash")
	await _close()


func _shot_desktops(pilot: Autopilot) -> void:
	_ui.open_computer({"tier": 1, "instant": true})
	await pilot.frames(4)
	var os: StellarOS = _computer()
	os.spawn_ad(1)
	os.spawn_ad(4)
	os.notify(tr("OS_TRAY_SPEED_TIP"))
	await pilot.frames(6)
	await _shot(pilot, "os_desktop_tier1_ads")
	await _close()
	for tier: int in [3, 5, 8]:
		_ui.open_computer({"tier": tier, "instant": true})
		await pilot.frames(6)
		await _shot(pilot, "os_desktop_tier%d" % tier)
		await _close()
	_ui.open_computer({"tier": 1})
	await pilot.frames(3)
	_computer().skip_boot()
	_computer().open_app(StellarOS.APP_NOTEBOOK)
	await pilot.seconds(StellarOS.window_lag_for_tier(1) * 0.55)
	await _shot(pilot, "os_tier1_opening_hourglass")
	await _close()
	_ui.open_computer({"tier": 1, "instant": true})
	await pilot.frames(3)
	_computer().open_start_menu()
	await pilot.frames(4)
	await _shot(pilot, "os_start_menu_tier1")
	await _close()


# ─── Aplicaciones ─────────────────────────────────────────────────

func _shot_mail(pilot: Autopilot) -> void:
	_ui.open_computer({"tier": 1, "instant": true, "app": StellarOS.APP_MAIL})
	await pilot.frames(4)
	var mail: MailApp = _computer().get_open_app() as MailApp
	if mail == null:
		return
	PlayerState.modify_reputation(20.0, "preview")
	await mail.answer_current(mail.current_correct_reply())
	await mail.answer_current((mail.current_correct_reply() + 1) % MailApp.REPLY_COUNT)
	await pilot.frames(6)
	await _shot(pilot, "os_mail_open")
	mail.select_mail(1)
	await pilot.frames(4)
	await _shot(pilot, "os_mail_replied_wrong")
	await _close()
	for tier: int in [5, 8]:
		_ui.open_computer({"tier": tier, "instant": true, "app": StellarOS.APP_MAIL})
		await pilot.frames(6)
		await _shot(pilot, "os_mail_tier%d" % tier)
		await _close()


func _shot_assist(pilot: Autopilot) -> void:
	for outcome: String in [AssistApp.ACCEPTABLE, AssistApp.EXCELLENT, AssistApp.FAILURE]:
		_new_run()
		if outcome == AssistApp.FAILURE:
			var witness: NPCRuntime = _perceptive_npc()
			_ds.set_witness_provider(func() -> Array: return [witness] if witness != null else [])
		_ui.open_computer({"tier": 1, "instant": true, "app": StellarOS.APP_ASSIST})
		await pilot.frames(4)
		var assist: AssistApp = _computer().get_open_app() as AssistApp
		if assist == null:
			continue
		await assist.generate(outcome)
		assist.finish_typing()
		await pilot.frames(6)
		await _shot(pilot, "os_assist_" + outcome)
		await _close()


func _perceptive_npc() -> NPCRuntime:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.alive and npc.get_trait("perception") > Database.get_balance_int("deberes.assist_umbral_deteccion_perspicacia"):
			return npc
	return null


func _shot_notebook(pilot: Autopilot) -> void:
	_new_run()
	_prepare_notebook_world()
	_ui.open_computer({"tier": 2, "instant": true, "app": StellarOS.APP_NOTEBOOK})
	await pilot.frames(4)
	var nb: NotebookApp = _computer().get_open_app() as NotebookApp
	if nb == null:
		return
	nb.set_notes_text(tr("OSQA_NOTES"))
	EventBus.notebook_entry_added.emit("duties", "NOTE_DUTY_WARNING", ["DUTY_EMAILS_R1"])
	EventBus.notebook_entry_added.emit("career", "NOTE_PROMOTION_AVAILABLE", [1])
	EventBus.notebook_entry_added.emit("ideas", "NOTE_AURORA_MEETING_TODAY", ["11:00"])
	await pilot.frames(3)
	nb.select_tab(NotebookApp.TAB_FAVOURS)
	await pilot.frames(6)
	await _shot(pilot, "os_notebook_favours")
	nb.select_tab(NotebookApp.TAB_LOG)
	await pilot.frames(4)
	await _shot(pilot, "os_notebook_log")
	nb.select_tab(NotebookApp.TAB_CASES)
	await pilot.frames(4)
	await _shot(pilot, "os_notebook_cases")
	await _close()


func _prepare_notebook_world() -> void:
	NPCDirector.add_favour(DEBTOR, "promotion", 2)
	NPCDirector.add_debt(DEBTOR, 4)
	NPCDirector.add_debt(CREDITOR, -2)
	NPCDirector.add_debt(OWNER, 1)
	Security.open_investigation("object_missing", 2, "wing_3b")
	Security.open_investigation("inventory_mismatch", 3, "p3_pantry")
	IdeaPool.generate_idea(OWNER, NPCDirector.get_npc(OWNER).department)
	if ResourceLoader.exists(PERSONNEL_SCRIPT):
		var script: GDScript = load(PERSONNEL_SCRIPT) as GDScript
		if script != null and script.can_instantiate():
			script.call("set_marked", TARGET, true)
			script.call("set_marked", OWNER, true)


func _shot_files(pilot: Autopilot) -> void:
	_new_run()
	var owner: NPCRuntime = NPCDirector.get_npc(OWNER)
	var idea_id: String = IdeaPool.generate_idea(OWNER, owner.department)
	IdeaPool.generate_idea(OWNER, owner.department)
	EventBus.room_entered.emit(owner.home_room, true)
	NPCDirector.set_current_location(OWNER, AWAY_ROOM)
	StellarOS.open_intrusion(OWNER, {"contains": ["voss_agenda", "favour_ledger"]})
	await pilot.seconds(0.7)
	await _shot(pilot, "os_guest_login")
	var files: FilesApp = await _wait_app(pilot, StellarOS.APP_FILES, 6.0) as FilesApp
	if files == null:
		await _close()
		return
	files.select_file("idea_" + idea_id)
	await pilot.frames(6)
	await _shot(pilot, "os_files_intrusion")
	await files.copy_file("idea_" + idea_id)
	files.open_folder(FilesApp.FOLDER_DOCUMENTS)
	await files.copy_file("doc_voss_agenda")
	await pilot.frames(6)
	await _shot(pilot, "os_files_intrusion_copied")
	await _close()
	_ui.open_computer({"tier": 1, "instant": true, "app": StellarOS.APP_FILES})
	await pilot.frames(4)
	var own: FilesApp = _computer().get_open_app() as FilesApp
	if own != null:
		own.open_folder(FilesApp.FOLDER_IDEAS)
		await pilot.frames(4)
		await _shot(pilot, "os_files_own_ideas")
	await _close()


func _shot_phone(pilot: Autopilot) -> void:
	_new_run()
	get_window().size = PHONE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	_ui.open_computer({"tier": 1, "instant": true, "app": StellarOS.APP_MAIL})
	await pilot.frames(10)
	await _shot(pilot, "os_phone_mail")
	await _close()
	_ui.open_computer({"tier": 1, "instant": true, "app": StellarOS.APP_ASSIST})
	await pilot.frames(6)
	await _shot(pilot, "os_phone_assist")
	await _close()


## Español (idioma localizado): los textos más largos deben caber.
func _shot_spanish(pilot: Autopilot) -> void:
	_new_run()
	get_window().size = DESKTOP_WINDOW
	_ui.set_touch_mode(false)
	_ui.set_text_options(UITheme.TEXT_MEDIUM, false)
	TranslationServer.set_locale("es")
	for app_id: String in [StellarOS.APP_MAIL, StellarOS.APP_ASSIST]:
		_ui.open_computer({"tier": 1, "instant": true, "app": app_id})
		await pilot.frames(6)
		await _shot(pilot, "os_es_" + app_id)
		await _close()
	TranslationServer.set_locale("en")
