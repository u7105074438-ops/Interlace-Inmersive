# phone_case.gd — Cuerpo de test_phone: superposición sin pausa, superior que ve el móvil, contactos, chat con registro, llamada escuchada, N5 y silencio.
# PROPIETARIO DE: nada.
# ESCUCHA: player_seen_partially, record_created, bribe_offered, bribe_result, belief_created (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const ROOM := "wing_3b"
const SAFE_ROOM := "p3_toilets"
const CHIEF := "npc_bernard_lasker"
const GOSSIP := "npc_debbie_foyle"
const CLIMBER := "npc_claudia_reeves"
const OBLIVIOUS := "npc_nate_brackley"
const DIRECTOR := "npc_diana_sedgwick"
const N5_OCCUPATION := "a10_marketing_director"
const MID_OCCUPATION := "senior_sales"
const FAVOUR := "look_away_once"
const WALLET_MONEY := 50000
const EPS := 0.0001
const WATCHED: Array[String] = ["player_seen_partially", "record_created", "bribe_offered",
		"bribe_result", "belief_created", "game_over"]

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
	_check_contacts()
	_check_chat_record()
	_check_call_overheard()
	_check_call_private()
	_check_estimate_n5()
	_check_silent_and_messages()
	_check_director_ignores()
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
func _prepare_panel(panel: BribePanel) -> Fixtures.FakeWallet:
	var wallet: Fixtures.FakeWallet = Fixtures.FakeWallet.new(WALLET_MONEY)
	var phone: PhoneOverlay = _phone()
	panel.wallet = wallet
	panel.ctx_provider = func(channel: String) -> Dictionary:
		var ctx: Dictionary = phone.offer_context(channel)
		ctx["roll"] = 0.0
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


func _check_contacts() -> void:
	var rows: Array[Dictionary] = PhoneContactsTab.list_contacts()
	check(not rows.is_empty(), "the player's room colleagues are contacts (proximity at work)")
	var occupation: OccupationData = PlayerState.get_occupation()
	check_eq(PhoneContactsTab.contact_source(_npc(GOSSIP), occupation), PhoneContactsTab.SOURCE_COLLEAGUE,
			"Debbie's number comes from working next to her")
	var stranger: NPCRuntime = _find_stranger(occupation)
	check(stranger != null and PhoneContactsTab.contact_source(stranger, occupation).is_empty(),
			"a stranger from another department is not a contact")
	if stranger != null:
		NPCDirector.add_favour(stranger.id, "test_favour", 1)
		check_eq(PhoneContactsTab.contact_source(stranger, occupation), PhoneContactsTab.SOURCE_FAVOUR,
				"a favour in their ledger gives you their number")
	_phone().show_tab(PhoneOverlay.TAB_CONTACTS)
	check(_phone().get_contacts_tab().has_contact(GOSSIP), "the contacts tab lists her")


func _find_stranger(occupation: OccupationData) -> NPCRuntime:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.home_room != occupation.office_room and npc.department != str(occupation.extra.get("department", "")) \
				and PhoneContactsTab.contact_source(npc, occupation).is_empty() and npc.tier < 5:
			return npc
	return null


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
	EventBus.room_entered.emit(SAFE_ROOM, true)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.current_room == SAFE_ROOM:
			npc.current_room = ROOM
	var exposure: Dictionary = _phone().refresh_exposure()
	check((exposure[PhoneOverlay.EXPO_LISTENERS] as Array).is_empty() and bool(exposure[PhoneOverlay.EXPO_SAFE]),
			"alone in the toilets nobody can hear you")
	var result: Dictionary = _offer(CLIMBER, Bribery.CHANNEL_PHONE_CALL, "lend_access")
	check(bool(result.get("ok", false)) and not (result.get("effects", []) as Array).has(Bribery.EFFECT_OVERHEARD),
			"a private call is not overheard")
	_phone().close_bribe()
	EventBus.room_entered.emit(ROOM, true)


# ─── Precio estimado, silencio y directivos ────────────────────────

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


func _check_caught_closes_phone() -> void:
	EventBus.player_caught_redhanded.emit(GOSSIP, "drawer_forced", 1)
	await wait_frames(3)
	check(not PhoneOverlay.is_open(get_tree()), "being caught red-handed puts the phone away")
