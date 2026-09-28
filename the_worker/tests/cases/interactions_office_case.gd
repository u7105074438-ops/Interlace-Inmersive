# interactions_office_case.gd — Cuerpo de test_interactions_office: cada manejador del módulo de oficina en la escena de juego real (sin ventana), con sus diálogos contestados, sus actos, delitos, ruidos, dinero, objetos y avisos.
# PROPIETARIO DE: nada (monta y libera la escena de juego; los interactivos de prueba se crean y se liberan aquí; su carpeta de guardado se borra al final).
# ESCUCHA: EventBus.crime_committed, EventBus.noise_emitted, Player.act_finished (para comprobar lo que emite el módulo).
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const OFFICE_MODULE := "res://src/world/interactions/office.gd"
const STORAGE_FORMAT := "user://test_interactions_office_%d"
const RUN_SEED := 4242
const OFFICE := "wing_3b"
const INITIAL := "email_worker_3b"
const FRAMES_SETTLE := 3
const DRIVE_TIMEOUT := 5.0
const QA_ACT := 0.05
const EPS := 0.01
const CARD_FLOOR_ROOM := "training_room"
const CARD_POST := "payroll_clerk"

var _game: GameRoot = null
var _office: Script = null
var _crimes: Array[Dictionary] = []
var _noises: Array[Dictionary] = []
var _acts: Array[String] = []
var _probes: Array[Interactable] = []
var _serial: int = 0


func run_case() -> void:
	allowed_engine_errors = 0
	var dir: String = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(dir)
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	OfficeKit.qa_act_seconds = QA_ACT
	check(new_run(RUN_SEED), "Database loaded")
	_office = load(OFFICE_MODULE) as Script
	await _spawn_game()
	_test_router_claims()
	await _test_desk()
	await _test_npc_computer()
	await _test_drawer()
	await _test_watched_abort()
	await _test_archives()
	await _test_personnel()
	await _test_supplies_and_mail()
	await _test_info_terminals()
	await _test_fraud_terminals()
	await _test_press()
	await _test_trading_campaign_forgery()
	await _test_break_room()
	await _test_food()
	await _cleanup()


# ─── Montaje ──────────────────────────────────────────────────

func _spawn_game() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	_game.request_overrides = {"mode": "new", "seed": RUN_SEED, "player_name": "Olive Office", "skip_intro": true}
	_game.epilogue_delay_override = 0.0
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_game.travel.instant = true
	_game.time_skip.instant = true
	_game.promotion.instant = true
	_game.bridges.instant = true
	await _settle()
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	## Sin percepción en marcha: los actos no los interrumpe una flagrancia al azar (los testigos
	## siguen existiendo para GameRoot.find_observer).
	_game.npc_layer.set_physics_process(false)
	EventBus.crime_committed.connect(func(t: String, r: String, d: Dictionary) -> void:
		_crimes.append({"type": t, "room": r, "details": d}))
	EventBus.noise_emitted.connect(func(p: Vector2, radius: float, s: String) -> void:
		_noises.append({"radius": radius, "source": s}))
	_game.player.act_finished.connect(func(c: String, _done: bool) -> void: _acts.append(c))


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _cleanup() -> void:
	OfficeKit.qa_act_seconds = -1.0
	for probe: Interactable in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	await get_tree().process_frame
	SaveSystem.delete_run()


## Interactivo de prueba en la posición del jugador (se libera al final).
func _probe(interact_type: String, room_id: String, data: Dictionary) -> Interactable:
	_serial += 1
	var item: Interactable = Interactable.new()
	item.setup("qa_%s_%d" % [interact_type, _serial], interact_type, room_id, data, RoomBuilder.cell_px(), Vector2.ZERO)
	_game.add_child(item)
	item.global_position = _game.player.global_position
	_probes.append(item)
	return item


## Llama al módulo como lo haría el router y contesta sus diálogos en orden (el aviso «te
## están mirando» se acepta solo; sin respuestas, se cancela). Devuelve cuántos diálogos vio.
func _use(item: Interactable, answers: Array = []) -> int:
	var state: Dictionary = {"done": false, "seen": 0}
	var ctx: Dictionary = InteractionRouter.build_context(item, _game.player)
	var runner: Callable = func() -> void:
		await _office.call("interact", item, _game.player, ctx)
		state["done"] = true
	_game.ui.get_toasts().clear()
	runner.call()
	var queue: Array = answers.duplicate()
	var left: float = DRIVE_TIMEOUT
	while not bool(state["done"]) and left > 0.0:
		var box: DialogBox = _game.ui.get_top_modal() as DialogBox
		if box != null and not box.is_done():
			state["seen"] = int(state["seen"]) + 1
			if _is_watch_prompt(box):
				box.choose(1)
			elif queue.is_empty():
				box.cancel()
			else:
				box.choose(int(queue.pop_front()))
		await get_tree().process_frame
		left -= get_process_delta_time()
	check(bool(state["done"]), "drive: %s finished" % item.interact_type)
	return int(state["seen"])


func _is_watch_prompt(box: DialogBox) -> bool:
	return box.get_option_count() > 1 and box.get_option_text(1).ends_with(TranslationServer.translate("OFFICE_WATCHED_PROCEED"))


func _saw_toast(key: String) -> bool:
	var stem: String = TranslationServer.translate(key).get_slice("%", 0).strip_edges()
	var toasts: ToastStack = _game.ui.get_toasts()
	for i: int in toasts.get_toast_count():
		if toasts.get_toast_text(i).begins_with(stem) or (stem.is_empty() and not toasts.get_toast_text(i).is_empty()):
			return true
	return false


func _close_modals() -> void:
	while _game.ui.has_modal():
		_game.ui.close_modal()
	await _settle()


func _crime(crime_type: String) -> Dictionary:
	for i: int in range(_crimes.size() - 1, -1, -1):
		if str(_crimes[i]["type"]) == crime_type:
			return _crimes[i]
	return {}


func _reset_signals() -> void:
	_crimes.clear()
	_noises.clear()
	_acts.clear()


func _drop_all(item_id: String) -> void:
	while PlayerState.is_carrying(item_id):
		PlayerState.remove_item(item_id)


# ─── Router ───────────────────────────────────────────────────

func _test_router_claims() -> void:
	var owned: int = 0
	for interact_type: String in _office.call("handled_types"):
		if InteractionRouter.module_for(interact_type) == _office:
			owned += 1
	check_eq(owned, (_office.call("handled_types") as Array).size(), "router: office.gd owns every type it claims")
	check(InteractionRouter.module_for("drawer") == _office and InteractionRouter.module_for("npc_computer") == _office,
			"router: drawers and colleagues' computers go to the office module")
	var desk: Interactable = _probe("desk", OFFICE, {})
	check_eq(InteractionRouter.prompt_key_for(desk), "UI_INTERACT_OWN_DESK", "prompt: a bare own desk promises the computer")
	check_eq(InteractionRouter.prompt_key_for(_find_real(OFFICE, "desk")), "UI_INTERACT_OWN_DESK_MENU", "prompt: the 3B desk with keys and a stash says so")
	var other: Interactable = _probe("desk", "wing_4a", {})
	check_eq(InteractionRouter.prompt_key_for(other), "UI_INTERACT_EXAMINE", "prompt: another desk only promises a look")
	check_eq(InteractionRouter.prompt_key_for(_probe("lunch_counter", "exec_dining", {"free": true})), "UI_INTERACT_FREE_FOOD",
			"prompt: a free buffet says help yourself")
	check_eq(InteractionRouter.prompt_key_for(_probe("food_fridge", "player_flat", {"owner": "player"})), "UI_INTERACT_EAT_HOME",
			"prompt: the flat's fridge says eat something")
	check(TranslationServer.translate("UI_INTERACT_WHITEBOARD") != "UI_INTERACT_WHITEBOARD", "prompt: whiteboards have their own text")


# ─── Mesa ─────────────────────────────────────────────────────

func _test_desk() -> void:
	var desk: Interactable = _find_real(OFFICE, "desk")
	check(desk != null, "desk: the player's desk exists in wing 3B")
	if desk == null:
		return
	_game.player.global_position = desk.global_position
	var options: Array[String] = OfficeDesk.desk_options(desk)
	check(options[0] == OfficeDesk.OPT_COMPUTER and options.has(OfficeDesk.OPT_TAKE_TOOLS) and options.has(OfficeDesk.OPT_HIDE),
			"desk: computer first, then keys/stamp and the stash (%s)" % str(options))
	await _use(desk, [0])
	check(_game.ui.get_top_modal() is StellarOS, "desk: E + 1 sits you at your computer")
	await _close_modals()
	await _use(desk, [options.find(OfficeDesk.OPT_TAKE_TOOLS)])
	check(PlayerState.is_carrying("keys_basic") and PlayerState.is_carrying("stamp"), "desk: keys and stamp taken into the inventory")
	check(_saw_toast("OFFICE_DESK_TOOLS_TAKEN"), "desk: taking the tools is announced")
	check(OfficeDesk.desk_options(desk).has(OfficeDesk.OPT_RETURN_TOOLS), "desk: once carried, they can be left in the drawer")
	await _use(desk, [OfficeDesk.desk_options(desk).find(OfficeDesk.OPT_RETURN_TOOLS)])
	check(not PlayerState.is_carrying("keys_basic") and PlayerState.has_item("keys_basic"), "desk: returned (still issued by the post)")
	await _test_desk_stash(desk)
	var foreign: Interactable = _probe("desk", "wing_4a", {})
	await _use(foreign)
	check(_saw_toast("INTERACT_NOT_YOUR_DESK"), "desk: another desk answers 'Not your desk'")


func _test_desk_stash(desk: Interactable) -> void:
	var spot: String = str(OfficeDesk.stash_spot(desk).get("id", ""))
	check(not spot.is_empty(), "desk: there is an under-desk stash (%s)" % spot)
	await _use(desk, [OfficeDesk.desk_options(desk).find(OfficeDesk.OPT_HIDE)])
	var inv: InventoryUI = _game.ui.get_top_modal() as InventoryUI
	check(inv != null and str(inv.get_context().get("hide_spot_id", "")) == spot, "desk: 'hide' opens the inventory on that stash")
	await _close_modals()
	PlayerState.add_item("paper")
	check(PlayerState.stash_item("paper", spot, OFFICE), "desk: precondition — paper hidden under the desk")
	var options: Array[String] = OfficeDesk.desk_options(desk)
	check(options.has(OfficeDesk.OPT_RETRIEVE), "desk: hidden things can be taken back")
	await _use(desk, [options.find(OfficeDesk.OPT_RETRIEVE), 0])
	check(PlayerState.is_carrying("paper"), "desk: the paper is back in the pocket")
	_drop_all("paper")


func _find_real(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


# ─── Ordenadores ajenos ───────────────────────────────────────

func _test_npc_computer() -> void:
	var colleague: NPCNode = _colleague_in(OFFICE)
	check(colleague != null, "npc_computer: a colleague is at work in wing 3B")
	if colleague != null:
		var busy: Interactable = _probe("npc_computer", OFFICE, {"owner": colleague.npc_id, "requires_absence": true})
		await _use(busy)
		check(_saw_toast("OFFICE_PC_OWNER_HERE") and not _game.ui.get_top_modal() is StellarOS, "npc_computer: refused while its owner is in the room")
	var away: Interactable = _probe("npc_computer", OFFICE, {"owner": "npc_harlan_voss", "requires_absence": true, "contains": ["safe_combination"]})
	await _use(away)
	var os: StellarOS = _game.ui.get_top_modal() as StellarOS
	check(os != null and os.is_guest() and os.get_intrusion_npc() == "npc_harlan_voss", "npc_computer: owner away → guest session on their computer")
	check_eq(_game.player.current_act(), "file_copied", "npc_computer: the player is visibly at someone else's computer (act)")
	await _close_modals()
	check_eq(_game.player.current_act(), "", "npc_computer: leaving the computer ends the act")


func _colleague_in(room_id: String) -> NPCNode:
	for node: NPCNode in _game.npc_layer.get_nodes():
		if NPCDirector.get_current_location(node.npc_id) == room_id:
			return node
	return null


# ─── Cajones ──────────────────────────────────────────────────

func _test_drawer() -> void:
	_reset_signals()
	var drawer: Interactable = _probe("drawer", OFFICE, {"owner": "npc_nate_brackley", "contains": ["foreign_document"]})
	await _use(drawer, [0])
	check(_acts.has("drawer_forced"), "drawer: forcing it is a visible act (drawer_forced)")
	check(not _crime("drawer_forced").is_empty(), "drawer: crime_committed drawer_forced")
	var noise: Dictionary = _noises[0] if not _noises.is_empty() else {}
	check(str(noise.get("source", "")) == "drawer" and absf(float(noise.get("radius", 0.0)) - Database.get_balance_float("ruido.radio_cajon")) < EPS,
			"drawer: opening it makes drawer noise of radius %.1f" % Database.get_balance_float("ruido.radio_cajon"))
	check(PlayerState.is_carrying("foreign_document"), "drawer: 'take everything' pockets the document")
	var theft: Dictionary = _crime("theft_small")
	check(not theft.is_empty() and theft["details"].has("value") and str(theft["details"].get("owner", "")) == "npc_nate_brackley",
			"drawer: each thing taken is a theft_small with value and owner")
	_reset_signals()
	await _use(drawer)
	check(_saw_toast("OFFICE_DRAWER_EMPTY_TODAY") and _acts.is_empty(), "drawer: emptied today → it says so, no new act")
	_drop_all("foreign_document")


## Alguien mira: se pregunta antes y «Ahora no» no deja delito.
func _test_watched_abort() -> void:
	var watcher: NPCNode = _colleague_in(OFFICE)
	if watcher == null:
		check(false, "watched: no colleague to watch the player")
		return
	var before: Vector2 = _game.player.global_position
	_game.player.global_position = watcher.global_position + Vector2(RoomBuilder.cell_px() * 0.8, 0.0)
	await _settle()
	check(not _game.find_observer().is_empty(), "watched: precondition — a colleague right next to the player observes")
	_reset_signals()
	var drawer: Interactable = _probe("drawer", OFFICE, {"owner": "npc_sonia_vail"})
	var state: Dictionary = {"done": false, "watched": false}
	var ctx: Dictionary = InteractionRouter.build_context(drawer, _game.player)
	var runner: Callable = func() -> void:
		await _office.call("interact", drawer, _game.player, ctx)
		state["done"] = true
	runner.call()
	for i: int in 20:
		var box: DialogBox = _game.ui.get_top_modal() as DialogBox
		if box != null and not box.is_done():
			state["watched"] = _is_watch_prompt(box)
			box.choose(box.get_default_index())
		await get_tree().process_frame
	check(bool(state["watched"]), "watched: the office asks first, naming who is looking")
	check(_crimes.is_empty() and _acts.is_empty(), "watched: the safe default ('Not now') leaves no crime and no act")
	_game.player.global_position = before


# ─── Archivos y expedientes ───────────────────────────────────

func _test_archives() -> void:
	_reset_signals()
	var cabinet: Interactable = _probe("filing_cabinet", OFFICE, {})
	check(OfficeLoot.archive_is_legal(cabinet), "archive: the own room's cabinet is legal")
	await _use(cabinet)
	check(_acts.is_empty() and _crime("drawer_forced").is_empty(), "archive: a legal search is no act and no crime")
	var audit: Interactable = _probe("archive_files", "internal_audit", {"documents": "audit_cases", "contains": ["incident_history"]})
	check(not OfficeLoot.archive_is_legal(audit), "archive: Internal Audit's files are not an R1's business")
	await _use(audit, [0])
	check(_acts.has("drawer_forced") and not _crime("drawer_forced").is_empty(), "archive: rifling a foreign archive is drawer_forced")
	check(PlayerState.is_carrying("incident_history"), "archive: its documents can be taken")
	_drop_all("incident_history")
	var target: String = "npc_george_penn"
	PlayerState.mark_target(target)
	var rep: float = NPCDirector.get_npc_reputation(target)
	var orders: Interactable = _probe("archive_files", "orders_archive", {"documents": "orders", "can_misplace": true})
	await _use(orders, [0, 0])
	check(not _crime("sabotage").is_empty() and str(_crime("sabotage")["details"].get("target", "")) == target,
			"archive: misplacing a marked target's orders is sabotage against them")
	check(NPCDirector.get_npc_reputation(target) < rep, "archive: their reputation drops (%.1f → %.1f)" % [rep, NPCDirector.get_npc_reputation(target)])
	PlayerState.unmark_target(target)


func _test_personnel() -> void:
	_reset_signals()
	var target: String = "npc_claudia_reeves"
	PlayerState.mark_target(target)
	var files: Interactable = _probe("personnel_files", "hr_office", {"contains": ["blackmail_file"]})
	await _use(files, [0])
	check(_acts.has("drawer_forced"), "hr: the intrusion is a visible act")
	check(PlayerState.has_full_file(target) and PlayerState.get_full_file_reason(target) == "hr_intrusion",
			"hr: the marked target's full file is open (hr_intrusion)")
	var leverage: ItemData = _carried("blackmail_file")
	check(leverage != null and str(leverage.extra.get("npc_id", "")) == target, "hr: a blackmail_file about the target is taken")
	await _use(files)
	check(_saw_toast("OFFICE_HR_DONE_TODAY"), "hr: once a day")
	_drop_all("blackmail_file")
	PlayerState.unmark_target(target)
	PlayerState.set_occupation("hr_assistant", "qa")
	await _use(files)
	check(_game.ui.get_top_modal() is StellarOS and _saw_toast("OFFICE_HR_LEGAL"), "hr: with the HR post the files open in PERSONNEL")
	await _close_modals()
	PlayerState.set_occupation(INITIAL, "qa")


func _carried(item_id: String) -> ItemData:
	for item: ItemData in PlayerState.get_inventory():
		if item.id == item_id:
			return item
	return null


# ─── Material y correo ────────────────────────────────────────

func _test_supplies_and_mail() -> void:
	_reset_signals()
	var shelf: Interactable = _probe("supply_shelf", "office_supplies", {"items": ["office_supplies"], "resale_value": 35, "daily_value": 35})
	await _use(shelf)
	var theft: Dictionary = _crime("theft_small")
	check(PlayerState.is_carrying("office_supplies"), "supplies: a pack of office supplies taken")
	check(not theft.is_empty() and int(theft["details"].get("value", 0)) == 35 and int(theft["details"].get("company_loss", 0)) == 35,
			"supplies: theft_small with value and company loss 35 €")
	await _use(_probe("supply_shelf", "office_supplies", {"items": ["office_supplies"], "resale_value": 35}))
	check(_saw_toast("OFFICE_SUPPLIES_DONE_TODAY"), "supplies: one share per room and day")
	await _use(_probe("supply_shelf", "p3_copyroom", {"items": ["office_supplies"], "resale_value": 5}))
	check(PlayerState.is_carrying("paper"), "supplies: a cheap copy-room shelf gives paper")
	var money: int = PlayerState.get_money()
	var mail: Interactable = _probe("mail_sorting", "mail_office", {"intercept": true})
	await _use(mail, [1])
	check_eq(PlayerState.get_money() - money, 40, "mail: posting the stolen supplies sells them (+40 €)")
	check(not PlayerState.is_carrying("office_supplies") and not PlayerState.is_carrying("paper"), "mail: the sold items are gone")
	_reset_signals()
	await _use(mail, [0])
	check(_acts.has("theft_small"), "mail: going through the envelopes is a visible theft act")
	await _use(mail)
	check(_saw_toast("OFFICE_MAIL_DONE_TODAY"), "mail: nothing more to open today")


# ─── Pantallas de lectura ─────────────────────────────────────

func _test_info_terminals() -> void:
	var notes: int = PlayerState.get_notebook_entries().size()
	var copier: Interactable = _probe("copier_memory", "p3_copyroom", {"leftover_copies": true})
	var seen: int = await _use(copier)
	check(seen == 1 and PlayerState.get_notebook_entries().size() > notes, "copier: a leftover copy is read and noted in the notebook")
	await _use(copier)
	check(_saw_toast("OFFICE_COPIER_DONE_TODAY"), "copier: one leftover per day for non-operators")
	var board: Interactable = _probe("whiteboard", OFFICE, {})
	check_eq(await _use(board), 1, "whiteboard: shows the Aurora agenda")
	var minutes: float = GameClock.get_total_minutes()
	check_eq(await _use(_probe("computer", "block_coordination_room", {"shows": "floor_planning"})), 1, "computer: a room terminal shows its screen")
	check(GameClock.get_total_minutes() > minutes, "computer: reading costs a couple of minutes")
	await _use(_probe("computer", "recording_studio", {"contains": ["compromising_recordings"]}))
	check(_game.ui.get_top_modal() is StellarOS and (_game.ui.get_top_modal() as StellarOS).is_guest(), "computer: a terminal with files is an intrusion")
	await _close_modals()
	await _test_card_reader()


## Lector de tarjeta: en la 1 (puertas con lector de nóminas y RR. HH.): denegado con R1,
## concedido con el puesto de nóminas (N2).
func _test_card_reader() -> void:
	_game.travel.teleport_to_room(CARD_FLOOR_ROOM)
	await _settle()
	var reader: Door = null
	for door: Door in _game.streamer.get_doors():
		if door.kind == Door.KIND_READER and door.clearance > PlayerState.get_clearance() and door.special_access.is_empty():
			reader = door
			break
	check(reader != null, "card_reader: precondition — a reader door above R1 on floor 1")
	if reader != null:
		var item: Interactable = _probe("card_reader", reader.room_a, {"door_id": reader.door_id})
		await _use(item)
		check(_saw_toast("OFFICE_CARD_DENIED"), "card_reader: an R1 card is refused (N%d)" % reader.clearance)
		PlayerState.set_occupation(CARD_POST, "qa")
		await _use(item)
		check(_saw_toast("OFFICE_CARD_OK") and reader.is_open(), "card_reader: the right card opens the door")
		PlayerState.set_occupation(INITIAL, "qa")
	_game.travel.teleport_to_room(OFFICE)
	await _settle()


# ─── Fraudes de puesto ────────────────────────────────────────

func _test_fraud_terminals() -> void:
	var payroll: Interactable = _probe("payroll_terminal", "payroll_office", {"ghost_employees": true})
	await _use(payroll)
	check(_saw_toast("OFFICE_TERMINAL_NO_ACCESS"), "payroll: an R1 has no credentials")
	PlayerState.set_occupation("payroll_clerk", "qa")
	_reset_signals()
	var money: int = PlayerState.get_money()
	await _use(payroll, [0, 1])
	var fraud: Dictionary = _crime("fraud")
	var gained: int = PlayerState.get_money() - money
	check(gained >= 40 and gained <= 60, "payroll: the clerk's quiet raise pays 40-60 € (%d)" % gained)
	check(not fraud.is_empty() and int(fraud["details"].get("company_loss", 0)) == gained and _acts.has("fraud"),
			"payroll: it is a visible fraud act with the company loss booked")
	await _use(payroll, [0])
	check(_saw_toast("OFFICE_FRAUD_TOO_SOON"), "payroll: not again until the cooldown passes")
	PlayerState.set_occupation("junior_accountant", "qa")
	var ledger: Interactable = _probe("accounting_terminal", "accounting", {"action": ["falsify_entries", "detect_fraud"]})
	check_eq(str(OfficeTerminals.fraud_actions(ledger)), str(["falsify_entries", "detect_fraud"]), "accounting: the junior accountant can falsify and detect")
	await _use(ledger, [1])
	check(_saw_toast("OFFICE_FRAUD_FOUND") or _saw_toast("OFFICE_FRAUD_CLEAN_BOOKS"), "accounting: looking for others' fraud answers")
	_drop_all("blackmail_file")
	PlayerState.set_occupation(INITIAL, "qa")


# ─── Prensa ───────────────────────────────────────────────────

func _test_press() -> void:
	var pr: Interactable = _probe("press_terminal", "public_relations", {"actions": ["bury_news", "fabricate_scandal"]})
	await _use(pr)
	check(_saw_toast("OFFICE_PRESS_NO_ACCESS"), "press: an R1 cannot publish")
	PlayerState.set_occupation("comms_director", "qa")
	var news_id: String = NewsFeed.publish("NEWS_INVESTIGATION_OPENED", -0.08, true)
	await _use(pr, [0, _bury_index(news_id)])
	check(bool(NewsFeed.get_news(news_id).get("buried", false)), "press: the director buries a scandal")
	var target: String = "npc_debbie_foyle"
	PlayerState.mark_target(target)
	_reset_signals()
	await _use(pr, [1, 0, 1])
	check(not _crime("framing").is_empty() and str(_crime("framing")["details"].get("target", "")) == target,
			"press: a fabricated scandal is framing against the target")
	PlayerState.unmark_target(target)
	PlayerState.set_occupation(INITIAL, "qa")


func _bury_index(news_id: String) -> int:
	var index: int = 0
	for entry: Dictionary in NewsFeed.get_active_news():
		if (bool(entry.get("is_scandal", false)) or float(entry.get("sentiment", 0.0)) < 0.0) and not bool(entry.get("consolidated", false)):
			if str(entry.get("id", "")) == news_id:
				return index
			index += 1
	return 0


# ─── Bolsa, campañas, falsificación, diseños ──────────────────

func _test_trading_campaign_forgery() -> void:
	var desk: Interactable = _probe("trading_terminal", "trading_room", {"mode": "trade"})
	check_eq(await _use(desk), 1, "trading: below the MARKET rank, a quotes screen")
	await _use(_probe("campaign_terminal", "campaign_room", {"action": "self_promotion"}))
	check(_saw_toast("OFFICE_CAMPAIGN_NO_POST"), "campaign: only marketing posts")
	PlayerState.set_occupation("marketing_creative", "qa")
	var rep: float = PlayerState.get_reputation()
	var campaign: Interactable = _probe("campaign_terminal", "campaign_room", {"action": "self_promotion"})
	await _use(campaign)
	check(PlayerState.get_reputation() != rep, "campaign: self-praise moves the reputation (%.1f → %.1f)" % [rep, PlayerState.get_reputation()])
	await _use(campaign)
	check(_saw_toast("OFFICE_CAMPAIGN_DONE_TODAY"), "campaign: once a day")
	await _use(_probe("forgery_station", "graphic_design", {"produces": ["forged_authorization", "forged_official_document"]}))
	check(_saw_toast("OFFICE_FORGE_NO_STAMP"), "forgery: without a stamp nothing is forged")
	PlayerState.set_occupation(INITIAL, "qa")
	_reset_signals()
	await _use(_probe("forgery_station", "graphic_design", {"produces": ["forged_authorization", "forged_official_document"]}), [1, 1])
	check(PlayerState.is_carrying("forged_official_document") and not _crime("forgery").is_empty() and _acts.has("forgery"),
			"forgery: with the desk stamp, a forged document (act + forgery crime)")
	_drop_all("forged_official_document")
	_reset_signals()
	var archive: Interactable = _probe("design_archive", "historic_designs_archive", {"decades_old": 3})
	await _use(archive)
	var copy: ItemData = _carried("idea_copy")
	check(copy != null and bool(copy.extra.get("historic_design", false)) and _acts.has("idea_stolen"), "design: an old design copied (act idea_stolen)")
	await _use(archive)
	check(_saw_toast("OFFICE_DESIGN_DONE_TODAY"), "design: once a day")
	_drop_all("idea_copy")


# ─── Café y escuchas ──────────────────────────────────────────

func _test_break_room() -> void:
	var colleague: NPCNode = _colleague_in(OFFICE)
	if colleague != null:
		_game.player.global_position = colleague.global_position + Vector2(RoomBuilder.cell_px(), 0.0)
		var affection: int = NPCDirector.get_affection(colleague.npc_id)
		var coffee: Interactable = _probe("water_cooler", OFFICE, {})
		await _use(coffee)
		check(NPCDirector.get_affection(colleague.npc_id) > affection, "coffee: a chat warms the colleague up")
		check(PlayerState.has_contact(colleague.npc_id), "coffee: and gets you their number")
		await _test_overhear(colleague)
	var minutes: float = GameClock.get_total_minutes()
	await _use(_probe("coffee_machine_use", "p3_copyroom", {}))
	check(_saw_toast("OFFICE_COFFEE_ALONE") and GameClock.get_total_minutes() - minutes >= Database.get_balance_float("oficina.minutos.cafe") - EPS,
			"coffee: alone it is just a coffee break (minutes pass)")
	var huddle: Interactable = _probe("eavesdrop_point", "factory_break_room", {"measures": "discontent"})
	check_eq(await _use(huddle), 1, "eavesdrop: the factory huddle reveals the discontent level")


func _test_overhear(owner_node: NPCNode) -> void:
	var owner: String = owner_node.npc_id
	var confidant: String = ""
	for npc: NPCRuntime in NPCDirector.get_npcs_in_room(OFFICE):
		if npc.id != owner:
			confidant = npc.id
			break
	var idea_id: String = IdeaPool.generate_idea(owner, "general")
	IdeaPool.share_idea(idea_id, confidant)
	check(IdeaPool.is_being_told(idea_id), "overhear: precondition — %s is telling an idea" % owner)
	await _use(_probe("eavesdrop_point", OFFICE, {}))
	check_eq(IdeaPool.get_idea(idea_id).acquired_by, "player", "overhear: the idea is overheard (IdeaPool overhear)")
	check_eq(IdeaPool.get_idea(idea_id).acquisition_method, "overhear", "overhear: by the overhear route")


# ─── Comida ───────────────────────────────────────────────────

func _test_food() -> void:
	var money: int = PlayerState.get_money()
	await _use(_probe("vending", "foosball_room", {"sells": ["food_basic"]}))
	check(PlayerState.is_carrying("food_basic") and money - PlayerState.get_money() == OfficeKit.item_value("food_basic"),
			"vending: buys a meal at its price")
	_drop_all("food_basic")
	_reset_signals()
	await _use(_probe("food_fridge", "p3_pantry", {"contains": ["food_basic"], "communal": true}))
	check(PlayerState.is_carrying("food_basic") and _acts.has("theft_small") and bool(_crime("theft_small")["details"].get("food", false)),
			"fridge: someone's lunch stolen (act + food theft)")
	_drop_all("food_basic")
	_reset_signals()
	await _use(_probe("kitchen_food", "investor_lounge", {"free": true, "quality": "luxury"}))
	check(PlayerState.is_carrying("food_premium") and not _crime("theft_small").is_empty(),
			"free food: in a room above your card, the executive buffet is theft")
	_drop_all("food_premium")
	money = PlayerState.get_money()
	await _use(_probe("lunch_counter", "cafeteria", {"sells": ["food_basic"], "paid": true}))
	check(money - PlayerState.get_money() == OfficeKit.item_value("food_basic"), "lunch counter: pays for the meal")
	_drop_all("food_basic")
	var home: HomeCycle = _game.sim_nodes["HomeCycle"] as HomeCycle
	var meal: String = "breakfast" if GameClock.get_hour() < Database.get_balance_int("oficina.comida.hora_cambio_comida") else "dinner"
	await _use(_probe("food_fridge", "player_flat", {"owner": "player"}))
	check(home.has_eaten(meal), "own fridge: eats the %s" % meal)
