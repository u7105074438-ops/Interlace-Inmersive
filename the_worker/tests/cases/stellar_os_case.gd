# stellar_os_case.gd — Cuerpo de test_stellar_os: apertura/cierre con restauración del reloj, arranque por nivel, MAIL como deber de volumen, lotería de A.S.S.I.S.T., cuaderno persistente, intrusión (acto visible, copia de idea y de documentos), unidad compartida, móvil, cambio de ajustes en caliente y DutySystem de respaldo.
# PROPIETARIO DE: nada.
# ESCUCHA: duty_progressed, assist_used, crime_committed, reputation_changed (conexiones del caso).
extends TestCase

const EMAILS := "duty_emails_r1"
const OWNER := "npc_claudia_reeves"
const CFO := "npc_maurice_sandbell"
const CFO_DOC_A := "real_fundamentals"
const CFO_DOC_B := "reported_figures"
const AWAY_ROOM := "p3_pantry"
const DOC_ID := "voss_agenda"
const NORMAL_SPEED := 1.0
const EPS := 0.0001
const MAIL_COUNT := 8
const MAIL_MINUTES := 45.0
const START_REPUTATION := 20.0
const NOTE_TEXT := "Claudia leaves at 13:00"
const ANNOTATION := "Owes me lunch"
const IT_POST := "it_technician"
const TEAM_POST := "wing_3b_chief"
const START_POST := "email_worker_3b"
const PHONE_CANVAS := Vector2(2340, 1080)
const DAYS_SAMPLED := 3

var _ui: UIRoot
var _ds: DutySystem
var _progress: Array = []
var _assists: Array = []
var _crimes: Array = []
var _rep: Array = []


## Jugador de mentira (grupo "player") para comprobar el acto de la sesión de invitado.
class FakePlayer extends Node:
	var act: String = ""

	func begin_act(crime_type: String, _seconds: float) -> void:
		act = crime_type

	func end_act() -> void:
		act = ""

	func current_act() -> String:
		return act


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	GameClock.set_time(1, 9, 0)
	_connect_signals()
	_ds = _new_duty_system()
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
	await _check_document_copies()
	await _check_shared_drive()
	await _check_phone_layout()
	await _check_restyle()
	await _check_fallback_duties()
	_ui.queue_free()


func _connect_signals() -> void:
	EventBus.duty_progressed.connect(func(id: String, p: float) -> void: _progress.append([id, p]))
	EventBus.assist_used.connect(func(t: String, r: String) -> void: _assists.append([t, r]))
	EventBus.crime_committed.connect(func(c: String, room: String, d: Dictionary) -> void:
		_crimes.append([c, room, d]))
	EventBus.reputation_changed.connect(func(o: float, n: float) -> void: _rep.append(n - o))


func _new_duty_system() -> DutySystem:
	var ds: DutySystem = DutySystem.new()
	add_child(ds)
	ds.set_witness_provider(func() -> Array: return [])
	return ds


## Standalone: fuera de UIRoot, con el reloj a velocidad normal.
func _open_standalone(context: Dictionary, parent: Node = null) -> StellarOS:
	var os: StellarOS = StellarOS.new()
	os.setup(context)
	(parent if parent != null else self).add_child(os)
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
	var throne: Dictionary = Database.get_art_band("the_throne").get("palette", {})
	var sovereign: Dictionary = OSTheme.palette_for_tier(8)
	check_eq(OSTheme.col(sovereign, "accent"), Color(str(throne.get("accent", ""))),
			"Sovereign skin colours are read from its art band (data), not duplicated in code")


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
	slow.open_start_menu()
	_click(slow.size * Vector2(0.6, 0.4))
	await wait_frames(1)
	check(not slow.is_start_menu_open(), "a click on the wallpaper closes the start menu")
	slow.shut_down()
	await wait_frames(2)
	check(not is_instance_valid(slow), "standalone desktop frees itself on shut down")
	check_near(GameClock.get_speed_multiplier(), NORMAL_SPEED, EPS, "standalone restores the clock")


func _click(pos: Vector2) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev)


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
	for i: int in MAIL_COUNT:
		var right: int = mail.current_correct_reply()
		var r: Dictionary = await mail.answer_current((right + 1) % MailApp.REPLY_COUNT if i == 0 else right)
		check(bool(r.get("ok", false)), "email %d answered" % (i + 1))
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
	check_eq(AssistApp.task_name("emails"), tr("DUTY_EMAILS_R1"), "the trace names the duty, not its raw subtype id")
	check(assist.get_trace_text().contains(tr("DUTY_EMAILS_R1")), "the trace panel shows the translated duty name")
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
	check(_rows_contain(nb, tr("DUTY_EMAILS_R1")), "notebook log receives notebook_entry_added entries (arguments translated)")
	NPCDirector.add_debt(OWNER, 3)
	nb.select_tab(NotebookApp.TAB_FAVOURS)
	check(_rows_contain(nb, NPCDirector.get_npc(OWNER).name), "favours tab lists who owes the player (NPCDirector ledger)")
	Security.open_investigation("object_missing", 2, "wing_3b")
	nb.select_tab(NotebookApp.TAB_CASES)
	check(nb.get_rows().size() >= 1, "cases tab lists open investigations (Security)")
	PlayerState.mark_target(OWNER)
	nb.select_tab(NotebookApp.TAB_TARGETS)
	check(_rows_contain(nb, NPCDirector.get_npc(OWNER).name), "targets tab lists PlayerState marked targets")
	nb.set_notes_text(NOTE_TEXT)
	os.close_app()
	nb = await os.open_app(StellarOS.APP_NOTEBOOK) as NotebookApp
	check_eq(nb.get_notes_text(), NOTE_TEXT, "notes survive closing and reopening NOTEBOOK")
	os.shut_down()
	await wait_frames(1)
	await _check_notebook_reopen()


func _check_notebook_reopen() -> void:
	var os: StellarOS = await _open_standalone({"tier": 2, "instant": true})
	var nb: NotebookApp = await os.open_app(StellarOS.APP_NOTEBOOK) as NotebookApp
	check_eq(nb.get_notes_text(), NOTE_TEXT, "notes survive shutting the computer down")
	var saved: Dictionary = PlayerState.save_state()
	PlayerState.set_notepad("")
	PlayerState.load_state(saved)
	check_eq(PlayerState.get_notepad(), NOTE_TEXT, "the pad is saved with the run (PlayerState save/load)")
	PlayerState.add_note(ANNOTATION, OWNER)
	nb.select_tab(NotebookApp.TAB_PEOPLE)
	check(_rows_contain(nb, ANNOTATION), "PERSONNEL annotations (PlayerState.get_notes) are listed")
	os.shut_down()
	await wait_frames(1)


func _rows_contain(nb: NotebookApp, text: String) -> bool:
	for row: Dictionary in nb.get_rows():
		if str(row["title"]).contains(text):
			return true
	return false


func _check_intrusion() -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(OWNER)
	var idea_id: String = IdeaPool.generate_idea(OWNER, npc.department)
	check(not idea_id.is_empty(), "owner has a fresh idea")
	EventBus.room_entered.emit(npc.home_room, true)
	NPCDirector.set_current_location(OWNER, AWAY_ROOM)
	var player: FakePlayer = FakePlayer.new()
	player.add_to_group(StellarOS.PLAYER_GROUP)
	add_child(player)
	var os: StellarOS = StellarOS.open_intrusion(OWNER, {"instant": true, "contains": [DOC_ID]}) as StellarOS
	check(os != null and os.is_guest(), "open_intrusion opens a guest session")
	if os == null:
		return
	await wait_frames(1)
	check_eq(player.current_act(), FilesApp.CRIME_FILE_COPIED, "sitting at someone else's computer is a visible act")
	check(not os.is_app_available(StellarOS.APP_MAIL), "guest session cannot open MAIL")
	var files: FilesApp = os.get_open_app() as FilesApp
	check(files != null and files.get_folder() == FilesApp.FOLDER_IDEAS, "guest session lands in FILES on the owner's ideas")
	if files == null:
		return
	_crimes.clear()
	check(await files.copy_file("idea_" + idea_id), "copy file succeeds with the owner away")
	check_eq(IdeaPool.get_idea(idea_id).acquired_by, "player", "copying acquires the idea (steal_file)")
	check_eq(IdeaPool.get_idea(idea_id).acquisition_method, "steal_file", "acquisition method is steal_file")
	check_eq(_crimes.size(), 1, "exactly one crime_committed for the copy (no double emission)")
	check_eq(str(_crimes[0][0]) if not _crimes.is_empty() else "", "file_copied", "crime type is file_copied")
	files.open_folder(FilesApp.FOLDER_DOCUMENTS)
	check(await files.copy_file("doc_" + DOC_ID), "a contained document can be copied")
	check(_document_ids().has(DOC_ID), "the document copy lands in the inventory")
	check_eq(_crimes.size(), 2, "document copy emits file_copied")
	_ui.close_modal()
	await wait_frames(2)
	check(not _ui.has_modal(), "guest session closes")
	check_eq(player.current_act(), "", "closing the guest session ends the act")
	player.queue_free()


func _document_ids() -> Array:
	var ids: Array = []
	for item: ItemData in PlayerState.get_inventory():
		if item.extra.has("document_id"):
			ids.append(str(item.extra["document_id"]))
	return ids


## Dos documentos del mismo ordenador (el del CFO, de data/rooms): cada uno su copia, sin repetir.
func _check_document_copies() -> void:
	var os: StellarOS = StellarOS.open_intrusion(CFO, {"instant": true}) as StellarOS
	await wait_frames(1)
	var files: FilesApp = os.get_open_app() as FilesApp if os != null else null
	check(files != null, "intrusion into the CFO computer opens FILES")
	if files == null:
		return
	files.open_folder(FilesApp.FOLDER_DOCUMENTS)
	check(files.list_files(FilesApp.FOLDER_DOCUMENTS).size() >= 2, "the CFO computer lists its data/rooms documents")
	_crimes.clear()
	check(await files.copy_file("doc_" + CFO_DOC_A), "first CFO document copied")
	check(await files.copy_file("doc_" + CFO_DOC_B), "second CFO document copied")
	check(not await files.copy_file("doc_" + CFO_DOC_A), "a document already copied cannot be copied again")
	check_eq(_crimes.size(), 2, "two copies, two file_copied crimes (a refused repeat emits nothing)")
	var ids: Array = _document_ids()
	check(ids.has(CFO_DOC_A) and ids.has(CFO_DOC_B) and ids.has(DOC_ID), "every copy keeps its own document_id (no stacking)")
	var entries: Array[Dictionary] = PlayerState.get_notebook_entries()
	var last_args: Array = entries.back().get("args", []) if not entries.is_empty() else []
	check_eq(str(last_args[0]) if not last_args.is_empty() else "", FilesApp.doc_name_key(CFO_DOC_B),
			"notebook entries carry the document name KEY, not frozen translated text")
	_ui.close_modal()
	await wait_frames(2)
	var own: StellarOS = await _open_standalone({"tier": 1, "instant": true, "app": StellarOS.APP_FILES})
	await wait_frames(1)
	var own_files: FilesApp = own.get_open_app() as FilesApp
	check(own_files != null and own_files.list_files(FilesApp.FOLDER_DOCUMENTS).size() == 3,
			"the player's own Documents folder shows the three copies")
	own.shut_down()
	await wait_frames(1)


## «Según rango» (§13.3): IT ve todos los ordenadores; un jefe, los de su equipo; R1, nada.
func _check_shared_drive() -> void:
	check_eq(FilesApp.shared_access(), FilesApp.SHARED_NONE, "an R1 worker has no shared drive")
	PlayerState.set_occupation(IT_POST, "test")
	check_eq(FilesApp.shared_access(), FilesApp.SHARED_ALL, "IT (others_computers) sees every computer")
	var os: StellarOS = await _open_standalone({"tier": 3, "instant": true, "app": StellarOS.APP_FILES})
	await wait_frames(1)
	var files: FilesApp = os.get_open_app() as FilesApp
	check(files != null and files.get_folders().has(FilesApp.FOLDER_SHARED), "FILES shows the shared drive to IT")
	var shared: Array[Dictionary] = files.list_files(FilesApp.FOLDER_SHARED) if files != null else []
	var cfo_doc: bool = false
	var read_only: bool = not shared.is_empty()
	for f: Dictionary in shared:
		cfo_doc = cfo_doc or str(f["id"]).ends_with(CFO_DOC_A)
		read_only = read_only and str(f["action"]).is_empty()
	check(cfo_doc, "the shared drive lists other people's documents (CFO)")
	check(read_only, "shared files are read-only (copying needs the owner's desk)")
	os.shut_down()
	await wait_frames(1)
	PlayerState.set_occupation(TEAM_POST, "test")
	check_eq(FilesApp.shared_access(), FilesApp.SHARED_TEAM, "a wing chief sees the files of the team")
	PlayerState.set_occupation(START_POST, "test")


## Móvil (TEXT_LARGE + táctil en un lienzo de 2340×1080): la lista de deberes de A.S.S.I.S.T.
## conserva al menos una fila entera.
func _check_phone_layout() -> void:
	check(new_run(), "fresh run for the phone layout")
	GameClock.set_time(1, 9, 0)
	_ds.reset_for_new_run()
	var saved_size: int = UITheme.current_text_size
	UITheme.current_text_size = UITheme.TEXT_LARGE
	UITheme.touch_scale_active = true
	var frame: Control = Control.new()
	frame.size = PHONE_CANVAS
	add_child(frame)
	var os: StellarOS = await _open_standalone({"tier": 1, "instant": true}, frame)
	var assist: AssistApp = await os.open_app(StellarOS.APP_ASSIST) as AssistApp
	await wait_frames(3)
	check(assist != null and assist.get_duty_list_height() >= assist.get_duty_row_height() - 1.0,
			"phone: the duty list keeps a whole, tappable row")
	os.shut_down()
	frame.queue_free()
	UITheme.current_text_size = saved_size
	UITheme.touch_scale_active = false
	await wait_frames(1)


## Cambiar el tamaño de texto con el ordenador abierto lo vuelve a maquetar sin cerrar la aplicación.
func _check_restyle() -> void:
	var os: StellarOS = await _open_standalone({"tier": 5, "instant": true, "app": StellarOS.APP_MAIL})
	await wait_frames(1)
	var before: int = os.get_base_size()
	var saved_size: int = UITheme.current_text_size
	UITheme.current_text_size = UITheme.TEXT_LARGE if saved_size != UITheme.TEXT_LARGE else UITheme.TEXT_SMALL
	await wait_frames(2)
	check(os.get_base_size() != before, "a text-size change restyles the open computer")
	check_eq(os.get_open_app_id(), StellarOS.APP_MAIL, "the open app is remounted after restyling")
	UITheme.current_text_size = saved_size
	await wait_frames(2)
	os.shut_down()
	await wait_frames(1)


## Sin DutySystem de la partida: uno de respaldo por partida, en UIRoot, que sobrevive al cierre.
func _check_fallback_duties() -> void:
	check(new_run(), "fresh run for the fallback DutySystem")
	GameClock.set_time(1, 9, 0)
	_ds.queue_free()
	await wait_frames(1)
	_ui.open_computer({"tier": 1, "instant": true})
	await wait_frames(1)
	var os: StellarOS = _ui.get_top_modal() as StellarOS
	var fb: DutySystem = os.get_duty_system()
	check(fb != null and fb.get_parent() == _ui, "without game_root, one fallback DutySystem lives in UIRoot")
	var assist: AssistApp = await os.open_app(StellarOS.APP_ASSIST) as AssistApp
	await assist.generate()
	_ui.close_modal()
	await wait_frames(2)
	check(is_instance_valid(fb), "the fallback survives closing the computer")
	_ui.open_computer({"tier": 1, "instant": true})
	await wait_frames(1)
	os = _ui.get_top_modal() as StellarOS
	check(os.get_duty_system() == fb, "reopening the computer uses the same fallback")
	check_eq(fb.get_assist_count(), 1, "the A.S.S.I.S.T. digital trace accumulates across sessions")
	var subjects: Array[String] = []
	for _d: int in DAYS_SAMPLED:
		subjects.append(_first_subject(os.get_duty_system()))
		GameClock.advance_to_next_day()
		await wait_frames(1)
	check(not (subjects[0] == subjects[1] and subjects[1] == subjects[2]), "the inbox changes from day to day")
	_ds = _new_duty_system()
	check(os.get_duty_system() == _ds, "the game's DutySystem takes over when it appears")
	await wait_frames(1)
	check(not is_instance_valid(fb), "the fallback retires (never two consequence executors)")
	_ui.close_modal()
	await wait_frames(1)


func _first_subject(ds: DutySystem) -> String:
	var inbox: Array[Dictionary] = MailApp.build_inbox(ds, MailApp.find_mail_duty())
	return str((inbox[0]["template"] as Dictionary).get("subject_key", "")) if not inbox.is_empty() else ""
