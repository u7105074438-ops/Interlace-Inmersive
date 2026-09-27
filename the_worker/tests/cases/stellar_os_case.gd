# stellar_os_case.gd — Cuerpo de test_stellar_os: apertura/cierre con restauración del reloj, arranque por nivel, MAIL como deber de volumen, lotería de A.S.S.I.S.T., registro del cuaderno e intrusión con copia de idea y documento.
# PROPIETARIO DE: nada.
# ESCUCHA: duty_progressed, assist_used, crime_committed, reputation_changed, idea_acquired (conexiones del caso).
extends TestCase

const EMAILS := "duty_emails_r1"
const OWNER := "npc_claudia_reeves"
const AWAY_ROOM := "p3_pantry"
const DOC_ID := "voss_agenda"
const NORMAL_SPEED := 1.0
const EPS := 0.0001
const MAIL_COUNT := 8
const MAIL_MINUTES := 45.0
const START_REPUTATION := 20.0

var _ui: UIRoot
var _ds: DutySystem
var _progress: Array = []
var _assists: Array = []
var _crimes: Array = []
var _rep: Array = []


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	GameClock.set_time(1, 9, 0)
	_connect_signals()
	_ds = DutySystem.new()
	add_child(_ds)
	_ds.set_witness_provider(func() -> Array: return [])
	_ui = UIRoot.new()
	get_tree().root.add_child(_ui)
	await wait_frames(2)
	_check_tiers()
	await _check_ui_root_session()
	await _check_standalone_clock()
	await _check_mail()
	await _check_assist()
	await _check_notebook()
	await _check_intrusion()
	_ui.queue_free()


func _connect_signals() -> void:
	EventBus.duty_progressed.connect(func(id: String, p: float) -> void: _progress.append([id, p]))
	EventBus.assist_used.connect(func(t: String, r: String) -> void: _assists.append([t, r]))
	EventBus.crime_committed.connect(func(c: String, room: String, d: Dictionary) -> void:
		_crimes.append([c, room, d]))
	EventBus.reputation_changed.connect(func(o: float, n: float) -> void: _rep.append(n - o))


## Standalone: fuera de UIRoot, con el reloj a velocidad normal.
func _open_standalone(context: Dictionary) -> StellarOS:
	var os: StellarOS = StellarOS.new()
	os.setup(context)
	add_child(os)
	await wait_frames(1)
	return os


func _check_tiers() -> void:
	var boot: Array = Database.get_balance("ordenador.arranque_segundos_por_nivel")
	check_near(StellarOS.boot_seconds_for_tier(1), float(boot[0]), EPS, "tier 1 boot time comes from balance")
	check(StellarOS.boot_seconds_for_tier(1) > StellarOS.boot_seconds_for_tier(4), "tier 4 boots faster than tier 1")
	check(StellarOS.boot_seconds_for_tier(4) > StellarOS.boot_seconds_for_tier(8), "tier 8 boots faster than tier 4")
	check_near(StellarOS.boot_seconds_for_tier(8), 0.0, EPS, "tier 8 boots instantly")
	check(StellarOS.window_lag_for_tier(1) > StellarOS.window_lag_for_tier(8), "windows lag less with rank")
	check_eq(OSTheme.skin_for_tier(1), OSTheme.SKIN_RETRO, "R1 terminal is StellarOS 98 (retro)")
	check_eq(OSTheme.skin_for_tier(8), OSTheme.SKIN_SOVEREIGN, "top terminal is Sovereign")
	check_eq(StellarOS.tier_for_player(), 1, "R1 player gets computer_tier 1")


func _check_ui_root_session() -> void:
	GameClock.set_speed_multiplier(NORMAL_SPEED)
	GameClock.resume()
	_ui.open_computer({"tier": 8, "instant": true})
	var os: StellarOS = _ui.get_top_modal() as StellarOS
	check(os != null, "UIRoot.open_computer instantiates StellarOS")
	if os == null:
		return
	await wait_frames(1)
	check(os.is_booted(), "tier 8 desktop is ready at once")
	check_near(GameClock.get_speed_multiplier(), Database.get_balance_float("tiempo.velocidad_en_ordenador"), EPS,
			"clock slowed to 0.4 inside the computer")
	check(not GameClock.is_paused(), "the clock is never paused by the computer")
	check(os.get_desktop_apps().has(StellarOS.APP_MAIL) and not os.get_desktop_apps().has(StellarOS.APP_MARKET),
			"R1 desktop has MAIL but no MARKET")
	var mail: Control = await os.open_app(StellarOS.APP_MAIL)
	check(mail is MailApp and os.get_open_app_id() == StellarOS.APP_MAIL, "MAIL opens in a window")
	os.request_close()
	check(os.get_open_app() == null, "Esc closes the app window first")
	os.request_close()
	await wait_frames(2)
	check(not _ui.has_modal(), "Esc on the empty desktop shuts the computer down")
	check_near(GameClock.get_speed_multiplier(), NORMAL_SPEED, EPS, "clock speed restored after closing")
	_ui.open_computer({"tier": 3, "instant": true})
	_ui.open_computer({})
	await wait_frames(2)
	check(not _ui.has_modal(), "C toggles the computer closed")
	check_near(GameClock.get_speed_multiplier(), NORMAL_SPEED, EPS, "clock restored after C")


func _check_standalone_clock() -> void:
	GameClock.set_speed_multiplier(NORMAL_SPEED)
	var slow: StellarOS = await _open_standalone({"tier": 1})
	check_near(slow.get_boot_duration(), StellarOS.boot_seconds_for_tier(1), EPS, "tier 1 boot lasts its balance seconds")
	check(not slow.is_booted(), "tier 1 is still booting after a frame")
	check(await slow.open_app(StellarOS.APP_MAIL) == null, "no apps while booting")
	check_near(GameClock.get_speed_multiplier(), Database.get_balance_float("tiempo.velocidad_en_ordenador"), EPS,
			"standalone desktop slows the clock itself")
	var before: float = GameClock.get_total_minutes()
	await get_tree().create_timer(0.3).timeout
	check(GameClock.get_total_minutes() >= before, "game time keeps running while booting")
	slow.skip_boot()
	check(slow.is_booted(), "boot can finish")
	var ad: Control = slow.spawn_ad(3)
	check(ad != null and slow.get_ads().size() == 1, "internal ad pops up on the budget terminal")
	slow.shut_down()
	await wait_frames(2)
	check(not is_instance_valid(slow), "standalone desktop frees itself on shut down")
	check_near(GameClock.get_speed_multiplier(), NORMAL_SPEED, EPS, "standalone restores the clock")


func _check_mail() -> void:
	var os: StellarOS = await _open_standalone({"tier": 1, "instant": true})
	var mail: MailApp = await os.open_app(StellarOS.APP_MAIL) as MailApp
	check(mail != null, "MAIL app mounted")
	if mail == null:
		return
	check_eq(mail.get_duty_id(), EMAILS, "MAIL serves the R1 email duty")
	check_eq(mail.get_inbox().size(), MAIL_COUNT, "inbox holds the 8 emails of the duty")
	check_eq(MailApp.pending_count(os.get_duty_system()), MAIL_COUNT, "desktop badge counts 8 pending emails")
	mail.select_mail(MAIL_COUNT - 1)
	var early: Dictionary = await mail.answer(0)
	check(not bool(early.get("ok", true)), "Policy 7.3.1: later emails cannot be answered first")
	PlayerState.modify_reputation(START_REPUTATION, "test")
	var start: float = GameClock.get_total_minutes()
	var rep_before: float = PlayerState.get_reputation()
	_progress.clear()
	var wrong: bool = true
	for i: int in MAIL_COUNT:
		var right: int = mail.current_correct_reply()
		var choice: int = (right + 1) % MailApp.REPLY_COUNT if wrong else right
		var r: Dictionary = await mail.answer_current(choice)
		check(bool(r.get("ok", false)), "email %d answered" % (i + 1))
		wrong = false
	check_near(GameClock.get_total_minutes() - start, MAIL_MINUTES, EPS, "8 replies advanced the clock 45 game minutes")
	check_eq(_progress.size(), MAIL_COUNT, "each reply publishes duty progress")
	check_near(PlayerState.get_reputation() - rep_before,
			Database.get_balance_float("ordenador.correo_reputacion_respuesta_erronea"), EPS,
			"one wrong reply cost the balance reputation penalty")
	check_eq(str(PlayerState.get_duty(EMAILS).get("status", "")), "completed", "the R1 duty is completed (HUD strike-through)")
	check(PlayerState.get_duty(EMAILS).get("quality", 1.0) < 1.0, "the wrong reply lowered the quality")
	check_eq(MailApp.pending_count(os.get_duty_system()), 0, "no pending emails left")
	os.shut_down()
	await wait_frames(1)


func _check_assist() -> void:
	check(new_run(), "fresh run for A.S.S.I.S.T.")
	GameClock.set_time(1, 9, 0)
	_ds.reset_for_new_run()
	var os: StellarOS = await _open_standalone({"tier": 1, "instant": true})
	var assist: AssistApp = await os.open_app(StellarOS.APP_ASSIST) as AssistApp
	check(assist != null, "A.S.S.I.S.T. app mounted")
	if assist == null:
		return
	check_eq(assist.get_automatable_duties(), [EMAILS] as Array[String], "the R1 email duty is automatable")
	_assists.clear()
	var before: int = _ds.get_assist_count()
	var start: float = GameClock.get_total_minutes()
	var result: Dictionary = await assist.generate()
	check(bool(result.get("ok", false)), "generate() runs the lottery")
	check_eq(_assists.size(), 1, "assist_used emitted once (digital trace)")
	check_eq(_ds.get_assist_count(), before + 1, "DutySystem logs the use")
	check(str(result.get("outcome", "")) in [AssistApp.ACCEPTABLE, AssistApp.EXCELLENT, AssistApp.FAILURE],
			"outcome is one of the three §10.4 results")
	check_near(GameClock.get_total_minutes() - start, 5.0, EPS, "A.S.S.I.S.T. costs 5 game minutes at R1")
	check_eq(str(PlayerState.get_duty(EMAILS).get("method", "")), "assist", "the duty is completed by assist")
	check(not assist.get_output_text().is_empty(), "the generated document is shown")
	var texts: Array[String] = []
	for outcome: String in [AssistApp.ACCEPTABLE, AssistApp.EXCELLENT, AssistApp.FAILURE]:
		texts.append(AssistApp.compose(outcome, "X", 7))
	check(texts[0] != texts[1] and texts[1] != texts[2], "each outcome reads differently")
	check_eq(AssistApp.compose(AssistApp.FAILURE, "X", 7), texts[2], "generated text is deterministic per seed")
	check(assist.get_automatable_duties().is_empty(), "no automatable duty left after the use")
	os.shut_down()
	await wait_frames(1)


func _check_notebook() -> void:
	var os: StellarOS = await _open_standalone({"tier": 2, "instant": true})
	var nb: NotebookApp = await os.open_app(StellarOS.APP_NOTEBOOK) as NotebookApp
	check(nb != null, "NOTEBOOK app mounted")
	if nb == null:
		return
	EventBus.notebook_entry_added.emit("duties", "NOTE_DUTY_WARNING", ["DUTY_EMAILS_R1"])
	await wait_frames(2)
	nb.select_tab(NotebookApp.TAB_LOG)
	var found: bool = false
	for row: Dictionary in nb.get_rows():
		found = found or str(row["title"]).contains(tr("DUTY_EMAILS_R1"))
	check(found, "notebook log receives notebook_entry_added entries (arguments translated)")
	var npc: NPCRuntime = NPCDirector.get_npc(OWNER)
	NPCDirector.add_debt(OWNER, 3)
	nb.select_tab(NotebookApp.TAB_FAVOURS)
	var favour: bool = false
	for row: Dictionary in nb.get_rows():
		favour = favour or str(row["title"]).contains(npc.name)
	check(favour, "favours tab lists who owes the player (NPCDirector ledger)")
	Security.open_investigation("object_missing", 2, "wing_3b")
	nb.select_tab(NotebookApp.TAB_CASES)
	check(nb.get_rows().size() >= 1, "cases tab lists open investigations (Security)")
	nb.set_notes_text("Claudia leaves at 13:00")
	check_eq(nb.save_notes(), NotebookApp.notes_supported(), "notes are saved through PlayerState when it supports them")
	os.shut_down()
	await wait_frames(1)


func _check_intrusion() -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(OWNER)
	var idea_id: String = IdeaPool.generate_idea(OWNER, npc.department)
	check(not idea_id.is_empty(), "owner has a fresh idea")
	EventBus.room_entered.emit(npc.home_room, true)
	NPCDirector.set_current_location(OWNER, AWAY_ROOM)
	var os: StellarOS = StellarOS.open_intrusion(OWNER, {"instant": true, "contains": [DOC_ID]}) as StellarOS
	check(os != null and os.is_guest(), "open_intrusion opens a guest session")
	if os == null:
		return
	await wait_frames(1)
	check(not os.is_app_available(StellarOS.APP_MAIL), "guest session cannot open MAIL")
	var files: FilesApp = os.get_open_app() as FilesApp
	check(files != null, "guest session lands in FILES")
	if files == null:
		return
	check_eq(files.get_folder(), FilesApp.FOLDER_IDEAS, "FILES opens the owner's ideas")
	_crimes.clear()
	check(await files.copy_file("idea_" + idea_id), "copy file succeeds with the owner away")
	check_eq(IdeaPool.get_idea(idea_id).acquired_by, "player", "copying acquires the idea (steal_file)")
	check_eq(IdeaPool.get_idea(idea_id).acquisition_method, "steal_file", "acquisition method is steal_file")
	check_eq(_crimes.size(), 1, "exactly one crime_committed for the copy (no double emission)")
	check_eq(str(_crimes[0][0]) if not _crimes.is_empty() else "", "file_copied", "crime type is file_copied")
	files.open_folder(FilesApp.FOLDER_DOCUMENTS)
	check(await files.copy_file("doc_" + DOC_ID), "a contained document can be copied")
	var copied: bool = false
	for item: ItemData in PlayerState.get_inventory():
		copied = copied or str(item.extra.get("document_id", "")) == DOC_ID
	check(copied, "the document copy lands in the inventory")
	check_eq(_crimes.size(), 2, "document copy emits file_copied")
	_ui.close_modal()
	await wait_frames(2)
	check(not _ui.has_modal(), "guest session closes")
