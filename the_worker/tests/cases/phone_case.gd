# phone_case.gd — Cuerpo de test_phone: superposición sin pausa, superior que ve el móvil (enfriamiento entre aperturas), contactos, chat con registro, llamada escuchada, sitios seguros, N5, contraoferta sin fondos, chantaje desde el chat, silencio y modo compacto.
# PROPIETARIO DE: nada.
# ESCUCHA: player_seen_partially, record_created, bribe_offered, bribe_result, belief_created, game_over (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const ROOM := "wing_3b"
const SAFE_ROOM := "p3_toilets"
const STAIRS := "service_stairs@3"
const CHIEF := "npc_bernard_lasker"
const GOSSIP := "npc_debbie_foyle"
const CLIMBER := "npc_claudia_reeves"
const OBLIVIOUS := "npc_nate_brackley"
const DIRECTOR := "npc_diana_sedgwick"
const BLACKMAILER := "npc_george_penn"
const N5_OCCUPATION := "a10_marketing_director"
const MID_OCCUPATION := "senior_sales"
const HR_OCCUPATION := "hr_assistant"
const FAVOUR := "look_away_once"
const OTHER_FAVOUR := "lend_access"
const WALLET_MONEY := 50000
const WORK_HOUR := 10
const EPS := 0.0001
const MOBILE_WINDOW := Vector2i(1170, 540)
const WATCHED: Array[String] = ["player_seen_partially", "record_created", "bribe_offered",
		"bribe_result", "belief_created", "game_over"]


## Jugador de mentira (grupo "player") para comprobar que el móvil no bloquea el movimiento.
class FakePlayer extends Node2D:
	var locked: bool = false

	func set_input_locked(on: bool) -> void:
		locked = on


var _log: Fixtures.SignalLog = null
var _ui: UIRoot = null
var _start_occupation: String = ""


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_start_occupation = PlayerState.get_occupation_id()
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_ui = UIRoot.new()
	add_child(_ui)
	await wait_frames(2)
	_setup_room()
	await _check_overlay_keeps_clock()
	_check_superior_sees_phone()
	await _check_cooldown_across_reopen()
	_check_contacts()
	await _check_contacts_budget()
	_check_chat_record()
	_check_call_overheard()
	_check_call_private()
	_check_service_stairs()
	_check_estimate_n5()
	_check_counteroffer_funds()
	await _check_demand_from_chat()
	_check_silent_and_messages()
	_check_director_ignores()
	_check_escape_steps_back()
	await _check_compact_layout()
	await _check_caught_closes_phone()
	SaveSystem.set_setting(PhoneOverlay.SETTING_SILENCED, false)
	_log.stop()
	_ui.queue_free()
	await wait_frames(2)


func _phone() -> PhoneOverlay:
	return get_tree().get_first_node_in_group(PhoneOverlay.GROUP) as PhoneOverlay


func _npc(npc_id: String) -> NPCRuntime:
	return NPCDirector.get_npc(npc_id)


## Ala 3B con el jefe (escalón 4), dos compañeras y un despistado en la sala del jugador.
func _setup_room() -> void:
	EventBus.room_entered.emit(ROOM, true)
	for npc_id: String in [CHIEF, GOSSIP, CLIMBER, OBLIVIOUS]:
		_npc(npc_id).current_room = ROOM
	check_eq(PlayerState.get_room(), ROOM, "the player is in wing 3B")


## Tiradas fijas: acepta si P > 0 (el caso comprueba canales, no la fórmula).
func _prepare_panel(panel: BribePanel, roll: float = 0.0) -> Fixtures.FakeWallet:
	var wallet: Fixtures.FakeWallet = Fixtures.FakeWallet.new(WALLET_MONEY)
	var phone: PhoneOverlay = _phone()
	panel.wallet = wallet
	panel.ctx_provider = func(channel: String) -> Dictionary:
		var ctx: Dictionary = phone.offer_context(channel)
		ctx["roll"] = roll
		ctx["counter_roll"] = 0.5
		return ctx
	panel.refresh_funds()
	return wallet


func _offer(npc_id: String, channel: String, favour: String) -> Dictionary:
	var phone: PhoneOverlay = _phone()
	phone.open_bribe(npc_id, channel)
	var panel: BribePanel = phone.get_bribe_panel()
	_prepare_panel(panel)
	panel.select_favour(favour)
	panel.set_amount(Bribery.fair_price(_npc(npc_id), favour) * 2)
	panel.request_offer()
	return panel.confirm_offer()


# ─── Superposición ────────────────────────────────────────────────

func _check_overlay_keeps_clock() -> void:
	GameClock.resume()
	var speed: float = GameClock.get_speed_multiplier()
	var before: float = GameClock.get_total_minutes()
	var fake: FakePlayer = FakePlayer.new()
	add_child(fake)
	fake.add_to_group("player")
	_ui.open_phone()
	var phone: PhoneOverlay = _ui.get_top_modal() as PhoneOverlay
	check(phone != null, "UIRoot.open_phone() instantiates src/ui/mobile/phone.gd")
	await wait_frames(3)
	check(not GameClock.is_paused() and not _ui.is_clock_paused_by_ui(), "the phone does not pause the clock")
	check_near(GameClock.get_speed_multiplier(), speed, EPS, "…nor slows it down (it is an overlay)")
	await get_tree().create_timer(0.3).timeout
	check(GameClock.get_total_minutes() > before, "game time keeps running with the phone open")
	check(phone.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and not bool(phone.get_meta(UIRoot.META_DIM, true)),
			"overlay: no dimming, the world around the handset stays visible and clickable")
	var typing: Array[Node] = phone.find_children("*", "LineEdit", true, false)
	typing.append_array(phone.find_children("*", "TextEdit", true, false))
	check(typing.is_empty(), "no text fields: the phone never needs to lock movement for typing")
	check(bool(phone.get_meta(PhoneOverlay.META_OVERLAY, false)), "it flags itself as a non-blocking overlay")
	check(PhoneOverlay.find_service(get_tree()) != null, "the session inbox service is installed")
	_check_movement(fake)
	fake.remove_from_group("player")
	fake.queue_free()


## El bloqueo de movimiento lo aplica UIRoot (no es de este constructor): ver REQUESTS 1-2.
func _check_movement(fake: FakePlayer) -> void:
	if not _ui.has_method("blocks_world_input"):
		print("PENDING (REQUEST ui_root.gd/player.gd): UIRoot.blocks_world_input() missing; with the phone open "
				+ "the player is locked=%s (must be false once the request lands)" % fake.locked)
		return
	check(not bool(_ui.call("blocks_world_input")), "UIRoot: the phone overlay does not block world input")
	check(not fake.locked, "…and the player can keep moving with the phone open (PASO 26)")


func _check_superior_sees_phone() -> void:
	var ids: Array[String] = []
	var certainty_ok: bool = true
	for args: Array in _log.all("player_seen_partially"):
		ids.append(str(args[0]))
		certainty_ok = certainty_ok and is_equal_approx(float(args[1]),
				Database.get_balance_float("movil.certeza_superior_ve_movil"))
	check(ids.has(CHIEF), "phone used in front of the wing chief: player_seen_partially(chief)")
	check(certainty_ok, "…with certainty movil.certeza_superior_ve_movil")
	check(not ids.has(GOSSIP) and not ids.has(OBLIVIOUS), "same-tier colleagues do not report phone use")
	var believes: bool = false
	for belief: Belief in BeliefNet.get_beliefs_held_by(CHIEF):
		believes = believes or belief.fact == BeliefNetSystem.FACT_SEEN_PARTIALLY
	check(believes and BeliefNet.calculate_player_suspicion() > 0.0,
			"BeliefNet turns it into a belief of the superior (suspicion rises)")
	_log.clear()
	var exposure: Dictionary = _phone().refresh_exposure()
	check((exposure[PhoneOverlay.EXPO_SUPERIORS] as Array).has(CHIEF), "the exposure strip lists the watcher")
	check_eq(_log.count_for("player_seen_partially", CHIEF), 0,
			"no spam: one report per superior per movil.enfriamiento_superior_segundos")


## Pulsar M tres veces delante del jefe no triplica su creencia: el enfriamiento vive en el Service.
func _check_cooldown_across_reopen() -> void:
	_log.clear()
	for i: int in 3:
		_ui.open_phone()
		await wait_frames(2)
		check(not PhoneOverlay.is_open(get_tree()), "M toggles the phone away (%d)" % (i + 1))
		_ui.open_phone()
		await wait_frames(2)
	check_eq(_log.count_for("player_seen_partially", CHIEF), 0,
			"closing and reopening the phone does not reset the superior's cooldown")
	var service: PhoneOverlay.Service = _phone().get_service()
	service.advance(Database.get_balance_float("movil.enfriamiento_superior_segundos") + 0.1)
	_phone().refresh_exposure()
	check_eq(_log.count_for("player_seen_partially", CHIEF), 1, "…once the cooldown has passed, he notices again")


func _check_contacts() -> void:
	var occupation: OccupationData = PlayerState.get_occupation()
	check_eq(PhoneContactsTab.contact_source(_npc(GOSSIP), occupation), PhoneContactsTab.SOURCE_COLLEAGUE,
			"fallback: Debbie's number comes from working next to her")
	check(not PhoneContactsTab.is_contact(GOSSIP), "a fresh run starts with no numbers (PlayerState.get_contacts)")
	GameClock.set_time(GameClock.get_day(), WORK_HOUR, 0)
	for i: int in Database.get_balance_int("movil.horas_proximidad_contacto"):
		EventBus.hour_passed.emit(WORK_HOUR + i, GameClock.get_day())
		_setup_room()
	var source: String = ""
	for entry: Dictionary in PhoneContactsTab.list_contacts():
		if str(entry["npc_id"]) == GOSSIP:
			source = str(entry["source"])
	check_eq(source, PhoneContactsTab.SOURCE_COLLEAGUE,
			"after movil.horas_proximidad_contacto working hours in her room she is a contact (proximity)")
	var stranger: NPCRuntime = _find_stranger(occupation)
	check(stranger != null and not PhoneContactsTab.is_contact(stranger.id),
			"a stranger from another department is not a contact")
	if stranger != null:
		NPCDirector.add_favour(stranger.id, "test_favour", 1)
		check(PhoneContactsTab.is_contact(stranger.id), "a favour in their ledger gives you their number")
	_phone().show_tab(PhoneOverlay.TAB_CONTACTS)
	_phone().get_contacts_tab().flush_rows()
	check(_phone().get_contacts_tab().has_contact(GOSSIP), "the contacts tab lists her")
	check_eq(PhoneOverlay.TAB_ICONS[PhoneOverlay.TAB_CONTACTS], "personal", "the Contacts tab shows a person glyph")


func _find_stranger(occupation: OccupationData) -> NPCRuntime:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.home_room != occupation.office_room and npc.department != str(occupation.extra.get("department", "")) \
				and npc.current_room != ROOM and not PhoneContactsTab.is_contact(npc.id) and npc.tier < 5:
			return npc
	return null


## En RR. HH. hay un número por empleado: la lista se construye por tandas, sin congelar el fotograma.
func _check_contacts_budget() -> void:
	PlayerState.set_occupation(HR_OCCUPATION, "test")
	var tab: PhoneContactsTab = _phone().get_contacts_tab()
	_phone().show_tab(PhoneOverlay.TAB_CONTACTS)
	var total: int = tab.get_rows().size()
	var budget: int = Database.get_balance_int("movil.filas_contactos_por_fotograma")
	check(total > budget * 3, "working in HR gives every number (%d)" % total)
	check(tab.get_row_count() <= budget * 2, "…but only a batch of rows is built on the first frame")
	for i: int in ceili(float(total) / budget) + 2:
		await wait_frames(1)
	check_eq(tab.get_row_count(), total, "…and the rest arrive over the next frames")
	var first: Control = tab.get_row_node(GOSSIP)
	tab.refresh()
	check(tab.get_row_count() == total and first != null and tab.get_row_node(GOSSIP) == first,
			"a refresh reuses the rows it already has")
	PlayerState.set_occupation(_start_occupation, "test")
	_phone().show_tab(PhoneOverlay.TAB_CONTACTS)


# ─── Canales ───────────────────────────────────────────────────────

func _check_chat_record() -> void:
	_log.clear()
	var phone: PhoneOverlay = _phone()
	phone.open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	var panel: BribePanel = phone.get_bribe_panel()
	_prepare_panel(panel)
	check(panel.select_favour(FAVOUR), "favour chosen from bribes.json")
	panel.set_amount(Bribery.fair_price(_npc(GOSSIP), FAVOUR) * 2)
	check(panel.request_offer() and panel.is_confirm_armed(), "first press only arms the confirmation")
	check_eq(_log.count("bribe_offered"), 0, "nothing is offered with a single press (§13.7)")
	var result: Dictionary = panel.confirm_offer()
	check(bool(result.get("ok", false)) and str(result.get("channel", "")) == Bribery.CHANNEL_MOBILE_CHAT,
			"the chat deal goes through Bribery.offer(…, mobile_chat)")
	var chat_records: int = 0
	for args: Array in _log.all("record_created"):
		if str(args[1]) == BeliefNetSystem.RECORD_CHAT_LOG:
			chat_records += 1
	check(chat_records == 1 and not str(result.get("record_id", "")).is_empty(),
			"chat creates a permanent digital record (record_created chat_log)")
	check(PhoneChatTab.server_record_count() >= 1, "the chat banner counts the records on the server")
	var outgoing: bool = false
	for message: Dictionary in phone.get_chat_tab().messages_for(GOSSIP):
		outgoing = outgoing or str(message["dir"]) == PhoneChatTab.DIR_OUT
	check(outgoing, "the chat thread shows the offer that was sent")
	phone.close_bribe()


func _check_call_overheard() -> void:
	var phone: PhoneOverlay = _phone()
	var exposure: Dictionary = phone.refresh_exposure()
	check((exposure[PhoneOverlay.EXPO_LISTENERS] as Array).has(OBLIVIOUS),
			"someone in the open-plan room is within earshot")
	check(phone.open_call(CLIMBER), "a colleague answers the call")
	var result: Dictionary = _offer(CLIMBER, Bribery.CHANNEL_PHONE_CALL, FAVOUR)
	check(bool(result.get("ok", false)), "the call deal goes through Bribery.offer(…, phone_call)")
	check(not Fixtures.find_belief(result, OBLIVIOUS, Bribery.FACT_OVERHEARD).is_empty(),
			"a call with an NPC in hearing range: that NPC overhears (belief)")
	var believes: bool = false
	for belief: Belief in BeliefNet.get_beliefs_held_by(OBLIVIOUS):
		believes = believes or belief.fact == Bribery.FACT_OVERHEARD
	check(believes, "…and BeliefNet holds the 'bribe_attempt:overheard' belief")
	check(str(result.get("record_id", "")).is_empty(), "a call leaves no written record")
	phone.close_bribe()
	phone.get_call_tab().hang_up()


func _check_call_private() -> void:
	check(PhoneOverlay.is_call_safe_room(SAFE_ROOM) and not PhoneOverlay.is_call_safe_room(ROOM),
			"toilets are safe for calls, the open-plan wing is not (rooms.safe_for_calls)")
	check(PhoneOverlay.hearing_radius(SAFE_ROOM) < PhoneOverlay.hearing_radius(ROOM),
			"voices carry further outside the safe rooms")
	_enter_alone(SAFE_ROOM)
	var exposure: Dictionary = _phone().refresh_exposure()
	check((exposure[PhoneOverlay.EXPO_LISTENERS] as Array).is_empty() and bool(exposure[PhoneOverlay.EXPO_SAFE]),
			"alone in the toilets nobody can hear you")
	var result: Dictionary = _offer(CLIMBER, Bribery.CHANNEL_PHONE_CALL, OTHER_FAVOUR)
	check(bool(result.get("ok", false)) and not (result.get("effects", []) as Array).has(Bribery.EFFECT_OVERHEARD),
			"a private call is not overheard")
	_phone().close_bribe()
	EventBus.room_entered.emit(ROOM, true)


func _enter_alone(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.current_room == room_id:
			npc.current_room = ROOM


## §13.5: la escalera de servicio (pieza transversal, id con «@planta») también es segura.
func _check_service_stairs() -> void:
	check(PhoneOverlay.is_call_safe_room(STAIRS) and PhoneOverlay.is_call_safe_room("service_stairs"),
			"the service stairs are a safe place for calls (with or without the floor suffix)")
	check(not PhoneOverlay.is_call_safe_room("corridors_low@3"), "…the transversal corridor is not")
	check_near(PhoneOverlay.hearing_radius(STAIRS), PhoneOverlay.hearing_radius(SAFE_ROOM), EPS,
			"…with the same short hearing radius as the toilets")
	_enter_alone(STAIRS)
	var phone: PhoneOverlay = _phone()
	var exposure: Dictionary = phone.refresh_exposure()
	check(bool(exposure[PhoneOverlay.EXPO_SAFE]), "the exposure strip calls the stairwell a private spot")
	phone.show_tab(PhoneOverlay.TAB_CALL)
	check(not phone.get_call_tab().get_privacy_text().contains(tr("PHONE_PRIVACY_HINT")),
			"…and the privacy card no longer tells you to go to the toilets or the stairs")
	EventBus.room_entered.emit(ROOM, true)
	phone.refresh_exposure()
	phone.show_tab(PhoneOverlay.TAB_CONTACTS)


# ─── Precio estimado, contraoferta, chantaje, silencio y directivos ─

func _check_estimate_n5() -> void:
	var phone: PhoneOverlay = _phone()
	check(PlayerState.get_personnel_file_level() < 5, "the starting job has a low personnel file level")
	phone.open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	var panel: BribePanel = phone.get_bribe_panel()
	panel.select_favour(FAVOUR)
	var fair: String = UITheme.format_money(Bribery.estimated_price(_npc(GOSSIP), FAVOUR))
	check(not panel.shows_estimate() and panel.get_estimate() == -1, "below N5 the player operates blind")
	check(not panel.get_estimate_text().contains(fair), "…and no price is printed anywhere")
	PlayerState.set_occupation(N5_OCCUPATION, "test")
	check(PlayerState.get_personnel_file_level() >= 5, "a director has personnel file N5")
	phone.open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	panel.select_favour(FAVOUR)
	var estimate: int = Bribery.estimated_price(_npc(GOSSIP), FAVOUR)
	check(panel.shows_estimate() and panel.get_estimate() == estimate and estimate > 0,
			"with N5 the bribe panel shows the estimated price")
	check(panel.get_estimate_text().contains(UITheme.format_money(estimate)), "…printed on the panel")
	phone.close_bribe()
	PlayerState.set_occupation(_start_occupation, "test")


## «Ofrecer lo que piden» nunca ofrece menos de lo pedido: sin fondos se deshabilita.
func _check_counteroffer_funds() -> void:
	var dealer: NPCRuntime = Fixtures.synthetic("test_bribable", "bribable")
	var panel: BribePanel = _phone().get_bribe_panel()
	panel.npc_resolver = func(npc_id: String) -> NPCRuntime: return dealer if npc_id == dealer.id else null
	_phone().open_bribe(dealer.id, Bribery.CHANNEL_MOBILE_CHAT)
	var wallet: Fixtures.FakeWallet = _prepare_panel(panel, 0.99)
	panel.select_favour(FAVOUR)
	panel.set_amount(Bribery.fair_price(dealer, FAVOUR))
	panel.request_offer()
	var first: Dictionary = panel.confirm_offer()
	var asked: int = panel.asked_price()
	check(str(first.get("outcome", "")) == Bribery.OUTCOME_COUNTEROFFER and asked > 0, "they ask for more")
	_log.clear()
	wallet.money = asked - 1
	panel.refresh_funds()
	check(not panel.can_pay_asked() and not panel.accept_counteroffer(),
			"short of the asked price: 'Offer what they ask' is disabled and cannot arm a lower offer")
	check(panel.get_state() == BribePanel.STATE_RESULT and _log.count("bribe_offered") == 0,
			"…no second offer, no second permanent record")
	_phone().close_bribe()
	_phone().open_bribe(dealer.id, Bribery.CHANNEL_MOBILE_CHAT)
	check(panel.get_favour() == FAVOUR and panel.asked_price() == asked,
			"closing and reopening the panel keeps their counteroffer (per contact and favour)")
	panel.step_favour(1)
	check_eq(panel.asked_price(), 0, "another favour has no standing counteroffer")
	panel.step_favour(-1)
	wallet.money = asked + 3
	panel.refresh_funds()
	check(panel.accept_counteroffer() and panel.get_amount() == asked,
			"with enough money it arms exactly the asked price (%d)" % asked)
	var second: Dictionary = panel.confirm_offer()
	check_eq(str(second.get("outcome", "")), Bribery.OUTCOME_ACCEPTED, "paying what they ask is accepted")
	check_eq(wallet.money, 3, "exactly the asked price was paid")
	panel.npc_resolver = Callable()
	_phone().close_bribe()


## Exigencia por chat: responder no pausa el reloj, deja registro y la conversación se actualiza.
func _check_demand_from_chat() -> void:
	var npc: NPCRuntime = _npc(BLACKMAILER)
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_WITNESSED, "drawer_forced",
			GameClock.get_day(), Blackmail.DEMAND_MONEY, 0)
	Blackmail.issue_demand(npc, entry, GameClock.get_day())
	await wait_frames(2)
	var phone: PhoneOverlay = _phone()
	phone.open_chat(BLACKMAILER)
	check(phone.get_chat_tab().can_answer_demand(), "the chat offers to answer their demand")
	phone.get_chat_tab().answer_demand()
	var dialog: BlackmailDialog = _ui.get_top_modal() as BlackmailDialog
	check(dialog != null and not _ui.is_clock_paused_by_ui(), "answering from the chat does not pause the world")
	check(dialog != null and bool(dialog.get_meta(PhoneOverlay.META_OVERLAY, false)) and dialog.replies_by_chat(),
			"…it is part of the phone overlay and warns that the reply is written")
	if dialog == null:
		return
	dialog.wallet = Fixtures.FakeWallet.new(WALLET_MONEY)
	dialog.press_pay()
	var paid: Dictionary = dialog.confirm()
	check(bool(paid.get("ok", false)) and not dialog.record_id.is_empty(),
			"paying through the company chat leaves a chat_log record")
	dialog.closed.emit()
	await wait_frames(3)
	check(_ui.get_top_modal() == phone and not phone.get_chat_tab().can_answer_demand(),
			"back in the chat, the settled demand no longer shows 'Answer their demand'")
	phone.get_chat_tab().close_thread()


func _check_silent_and_messages() -> void:
	var phone: PhoneOverlay = _phone()
	phone.set_silenced(true)
	EventBus.phone_message_received.emit(GOSSIP, "PHONE_BLACKMAIL_FAVOUR", true)
	check(not phone.is_vibrating() and PhoneOverlay.is_phone_silenced(get_tree()),
			"silent mode: an incoming message does not vibrate")
	phone.set_silenced(false)
	EventBus.phone_message_received.emit(GOSSIP, "PHONE_BLACKMAIL_MONEY", true)
	check(phone.is_vibrating(), "not silenced: the phone vibrates on phone_message_received")
	var service: PhoneOverlay.Service = PhoneOverlay.find_service(get_tree())
	check_eq(service.messages_from(GOSSIP).size(), 2, "both messages reach the session inbox")


func _check_director_ignores() -> void:
	var director: NPCRuntime = _npc(DIRECTOR)
	check(director.tier >= Database.get_balance_int("movil.escalon_directivo"), "Diana Sedgwick is management")
	check(not PhoneContactsTab.will_answer(director), "a director ignores a much lower-rank player")
	NPCDirector.add_favour(DIRECTOR, "test_favour", 1)
	var tab: PhoneContactsTab = _phone().get_contacts_tab()
	_phone().show_tab(PhoneOverlay.TAB_CONTACTS)
	tab.select(DIRECTOR)
	check(tab.get_selected() == DIRECTOR and not tab.choose_action(PhoneOverlay.ACTION_DEAL),
			"no deal with someone who does not answer")
	check(not _phone().open_call(DIRECTOR), "…and the call goes straight to voicemail")
	_phone().get_call_tab().hang_up()
	PlayerState.set_occupation(MID_OCCUPATION, "test")
	check(PhoneContactsTab.will_answer(director), "a player close enough in rank gets an answer")
	PlayerState.set_occupation(_start_occupation, "test")


func _check_escape_steps_back() -> void:
	var phone: PhoneOverlay = _phone()
	phone.open_chat(GOSSIP)
	phone.request_close()
	check(PhoneOverlay.is_open(get_tree()) and phone.get_chat_tab().get_thread().is_empty(),
			"Esc inside a chat thread goes back to the chat list, not out of the phone")


## Pantalla de móvil (1170×540, táctil, texto grande): deslizador, precio y riesgo siempre a la vista.
func _check_compact_layout() -> void:
	var window: Window = get_tree().root
	var old_size: Vector2i = window.size
	window.size = MOBILE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	await wait_frames(4)
	var phone: PhoneOverlay = _phone()
	check(phone.is_compact(), "a landscape phone screen with large text switches the phone to compact mode")
	phone.open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	await wait_frames(4)
	var panel: BribePanel = phone.get_bribe_panel()
	var page: Rect2 = panel.get_global_rect()
	var body: Rect2 = (panel.get("_scroll") as Control).get_global_rect()
	for node_name: String in ["_slider", "_send_button"]:
		var node: Control = panel.get(node_name) as Control
		check(page.encloses(node.get_global_rect()), "compact bribe panel: %s is fully on screen" % node_name)
	for node_name: String in ["_estimate_label", "_risk_label"]:
		var line: Control = panel.get(node_name) as Control
		check(body.encloses(line.get_global_rect()), "compact bribe panel: %s is not scrolled out of view" % node_name)
	phone.close_bribe()
	phone.open_chat(BLACKMAILER)
	await wait_frames(4)
	var em: float = PhoneOverlay.base_size(phone)
	check(phone.get_chat_tab().get_bubble_area_height() >= em * PhoneChatTab.BUBBLES_MIN_EMS - 1.0,
			"compact chat: the message list keeps room for whole messages")
	phone.get_chat_tab().close_thread()
	window.size = old_size
	_ui.set_touch_mode(false)
	_ui.set_text_options(UITheme.TEXT_MEDIUM, false)
	await wait_frames(4)


func _check_caught_closes_phone() -> void:
	EventBus.player_caught_redhanded.emit(GOSSIP, "drawer_forced", 1)
	await wait_frames(3)
	check(not PhoneOverlay.is_open(get_tree()), "being caught red-handed puts the phone away")
