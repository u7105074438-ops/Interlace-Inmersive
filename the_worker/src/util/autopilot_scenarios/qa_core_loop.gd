# qa_core_loop.gd (escenario QA) — Juega las jornadas 1-3 como un jugador nuevo (§4, §5, §6, §15): tornos, ascensor (planta prohibida), mesa y correos, salto temporal, comida, cierre, trayecto, compra, cena, dormir; jornada 2 sin trabajar; jornada 3 sin ir a la oficina.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y eventos de entrada reales).
# ESCUCHA: EventBus (solo para registrar lo que el jugador vería: avisos, deberes, dinero, cámaras, lectores).
extends Node

## tools/screenshot.sh /tmp/qa_core qa_core_loop
## Cada comprobación imprime "[qa_core_loop] PASS|FAIL|INFO ..." para poder buscarla con grep.
## Capturas: qa_d1_01_start · 02_panel · 03_denied · 04_floor3 · 05_mail · 06_skip_desk · 07_corridor_skip ·
## 08_lunch · 09_closing · 10_street · 11_shop · 12_summary · qa_d2_* · qa_d3_*.

const PLAYER_NAME := "Quinn Tester"
const DIFFICULTY := "estandar"
const ELEVATOR_ROOM := "main_elevator_1@0"
const OFFICE := "wing_3b"
const FORBIDDEN_FLOOR := 6
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 40.0
const WAIT_TIMEOUT := 20.0
const SHORT_FRAMES := 8
const TAG := "[qa_core_loop]"

var _pilot: Autopilot = null
var _game: GameRoot = null
var _toasts_seen: Array[String] = []
var _events: Array[String] = []
var _fails: int = 0


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		_fail("game scene did not start")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		_fail("GameRoot missing")
		return
	_listen()
	await _day1()
	await _day2_slacker()
	await _day3_absent()
	_info("events: %s" % str(_events))
	_info("toasts seen: %s" % str(_toasts_seen))
	print("%s DONE fails=%d" % [TAG, _fails])


# ─── Jornada 1: el jugador honrado ────────────────────────────

func _day1() -> void:
	_state("d1 start")
	_check(GameClock.get_day() == 1, "day 1 at start")
	_check(PlayerState.get_occupation_id() == "email_worker_3b", "starts at R1 email_worker_3b (§6.1)")
	_check(PlayerState.get_clearance() == 1, "starts with N1 (§5.2)")
	_info("start money=%d (manual §6.5 implies ~0 savings: 26 days to 210 €)" % PlayerState.get_money())
	var days_to_bribe: float = float(210 - PlayerState.get_money()) / float(PlayerState.get_daily_wage() - PlayerState.get_daily_expenses())
	_check(absf(days_to_bribe - 26.0) <= 2.0, "honest days to cheapest bribe ~26 (§6.5) got %.1f" % days_to_bribe)
	await _pilot.shot("qa_d1_01_start")
	var logs_before: int = Security.get_access_log().size()
	# Elevator: the new player walks from the turnstiles to the lift.
	var panel_item: Interactable = _find_item(ELEVATOR_ROOM, "elevator_panel")
	if panel_item == null:
		_fail("no elevator panel in %s" % ELEVATOR_ROOM)
		return
	await _walk_to(panel_item.global_position)
	_check(Security.get_access_log().size() > logs_before, "turnstile crossing logged in access log (§5.3)")
	_info("rooms walked: %s at %s" % [PlayerState.get_room(), GameClock.get_time_string()])
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.travel.get_panel() != null, WAIT_TIMEOUT)
	var select: FloorTravel.FloorSelectPanel = _game.travel.get_panel()
	if select == null:
		_fail("elevator panel did not open")
		return
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("qa_d1_02_panel")
	var allowed: Array[int] = []
	for f: int in range(-3, 21):
		if FloorTravel.card_opens_floor(f):
			allowed.append(f)
	_info("elevator floors open with N1: %s" % str(allowed))
	_check(not allowed.has(5), "N1 does not open floor 5 (§5.2: N2 = plantas 1-5 completas)")
	_check(not allowed.has(6), "N1 does not open floor 6")
	var forbidden: int = select.index_of_floor(FORBIDDEN_FLOOR)
	var denied_before: int = _toasts_seen.size()
	if forbidden >= 0:
		select.choose(forbidden)
		await _pilot.frames(SHORT_FRAMES)
		await _pilot.shot("qa_d1_03_denied")
		_check(_game.streamer.get_current_floor() == 0, "choosing a locked floor does not travel")
		_check(_toasts_seen.size() > denied_before, "locked floor gives a readable toast")
	else:
		_fail("floor %d not listed on elevator panel" % FORBIDDEN_FLOOR)
	select = _game.travel.get_panel()
	if select == null:
		_fail("panel closed after a denied floor (player has to re-open it)")
		await _tap("interact")
		await _wait_until(func() -> bool: return _game.travel.get_panel() != null, WAIT_TIMEOUT)
		select = _game.travel.get_panel()
	var t0: float = GameClock.get_total_minutes()
	select.choose(select.index_of_floor(3))
	await _wait_until(func() -> bool: return _game.streamer.get_current_floor() == 3 and not _game.travel.is_busy(), WAIT_TIMEOUT)
	_check(_game.streamer.get_current_floor() == 3, "elevator reached floor 3")
	_info("elevator ride cost %.1f game min" % (GameClock.get_total_minutes() - t0))
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("qa_d1_04_floor3")
	# Door policy on floor 3 (all N1) and a stairs trip to floor 5 to test a forbidden door.
	await _desk_and_mail(true)
	await _time_skip_tests()
	await _forbidden_doors()
	await _lunch_check()
	await _leave_and_go_home(true)
	await _sleep("qa_d1")


func _desk_and_mail(answer_all: bool) -> void:
	if DatabaseSystem.get_room_base_id(PlayerState.get_room()) != OFFICE:
		_game.travel.teleport_to_room(OFFICE)
	await _pilot.frames(SHORT_FRAMES)
	var desk: Interactable = _find_item(OFFICE, "desk")
	if desk == null:
		_fail("no desk in %s" % OFFICE)
		return
	await _walk_to(desk.global_position)
	await _tap("computer")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is StellarOS, WAIT_TIMEOUT)
	var os: StellarOS = _game.ui.get_top_modal() as StellarOS
	if os == null:
		_fail("computer did not open at own desk (C)")
		return
	await _wait_until(func() -> bool: return os.is_booted(), WAIT_TIMEOUT)
	if not answer_all:
		await _pilot.shot("qa_d2_01_computer")
		await _tap("computer")
		return
	os.open_app(StellarOS.APP_MAIL)
	await _wait_until(func() -> bool: return os.get_open_app() is MailApp, WAIT_TIMEOUT)
	var mail: MailApp = os.get_open_app() as MailApp
	var t0: float = GameClock.get_total_minutes()
	var answered: int = 0
	for i: int in 20:
		var duty: Dictionary = PlayerState.get_duty("duty_emails_r1")
		if str(duty.get("status", "")) == "completed" or mail == null:
			break
		await mail.answer_current(mail.current_correct_reply())
		answered += 1
		await _pilot.frames(3)
	var spent: float = GameClock.get_total_minutes() - t0
	_info("answered %d mails in %.1f game min (§10.6: 8 mails = 45 min)" % [answered, spent])
	_check(str(PlayerState.get_duty("duty_emails_r1").get("status", "")) == "completed", "email duty completed")
	await _pilot.shot("qa_d1_05_mail")
	await _tap("computer")
	await _pilot.frames(SHORT_FRAMES)
	_state("after mail")


func _time_skip_tests() -> void:
	var reason: String = _game.time_skip.check()
	_info("T at own desk: check='%s' observer='%s'" % [reason, _game.observer_name()])
	await _tap("time_skip")
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("qa_d1_06_skip_desk")
	var top: Control = _game.ui.get_top_modal()
	if top is DialogBox:
		(top as DialogBox).choose((top as DialogBox).get_option_count() - 1)
		await _pilot.frames(SHORT_FRAMES)
	# Corridor: cameras (§5.5) -> skip must be refused.
	var corridor: String = "corridors_low@3"
	var rect: Rect2 = _game.streamer.get_room_rect_px(corridor)
	if rect.size == Vector2.ZERO:
		_info("no %s rect on floor 3" % corridor)
		return
	await _walk_to(rect.get_center())
	var obs: Dictionary = _game.find_observer()
	_info("in corridor room=%s observer=%s skip=%s" % [PlayerState.get_room(), str(obs), _game.time_skip.check()])
	_check(_game.time_skip.check() != "", "time skip refused in a corridor (unsafe / camera)")
	await _pilot.shot("qa_d1_07_corridor_skip")
	# Toilets are a blind spot (§5.5): no camera observer should be found.
	var toilets: Rect2 = _game.streamer.get_room_rect_px("p3_toilets")
	if toilets.size != Vector2.ZERO:
		await _walk_to(toilets.get_center())
		var o2: Dictionary = _game.find_observer()
		_info("in toilets room=%s observer=%s skip=%s" % [PlayerState.get_room(), str(o2), _game.time_skip.check()])
		_check(str(o2.get("kind", "")) != "camera", "no camera sees the player in toilets (blind spot §5.5)")


func _forbidden_doors() -> void:
	var denied: Array[String] = []
	var allowed: Array[String] = []
	for f: int in [1, 5]:
		var room: String = "corridors_low"
		_game.travel.teleport_to_room("%s@%d" % [room, f])
		await _pilot.frames(SHORT_FRAMES)
		for door: Door in _game.streamer.get_doors():
			var label: String = "%s(%d)" % [DatabaseSystem.get_room_base_id(door.room_b), door.clearance]
			if DoorAccess.allows(door):
				allowed.append(label)
			else:
				denied.append(label)
	_info("N1 doors allowed: %s" % str(allowed))
	_info("N1 doors denied: %s" % str(denied))
	# Try physically walking into accounting (floor 5, N2).
	var acc: Rect2 = _game.streamer.get_room_rect_px("accounting")
	if acc.size != Vector2.ZERO:
		var toast_n: int = _toasts_seen.size()
		await _walk_to(acc.get_center())
		_check(DatabaseSystem.get_room_base_id(PlayerState.get_room()) != "accounting", "N1 cannot walk into accounting (N2)")
		_info("walking into accounting: toasts added=%s" % str(_toasts_seen.slice(toast_n)))
		await _pilot.shot("qa_d1_07b_denied_door")
	_game.travel.teleport_to_room(OFFICE)
	await _pilot.frames(SHORT_FRAMES)


func _lunch_check() -> void:
	_jump_to(11 * 60)
	await _pilot.seconds(1.0)
	var morning: int = NPCDirector.get_npcs_in_room(OFFICE).size()
	var cafe_morning: int = NPCDirector.get_npcs_in_room("cafeteria").size()
	_jump_to(13 * 60 + 20)
	await _pilot.seconds(1.5)
	# El salto de reloj deja a los de la planta activa saliendo a pie: se les da ~12 min de juego.
	await _pilot.seconds(12.0)
	var lunch: int = NPCDirector.get_npcs_in_room(OFFICE).size()
	var cafe_lunch: int = NPCDirector.get_npcs_in_room("cafeteria").size()
	_info("wing_3b npcs 11:00=%d 13:20=%d · cafeteria 11:00=%d 13:20=%d" % [morning, lunch, cafe_morning, cafe_lunch])
	_check(lunch < morning, "offices empty at lunch (§5.6)")
	_check(cafe_lunch > cafe_morning, "cafeteria fills at lunch (§5.6)")
	await _pilot.shot("qa_d1_08_lunch")
	# Can the player eat lunch? §4.1 does not mention it but the day has no lunch meal in HomeCycle.
	_info("meal slots in HomeCycle: %s" % str(HomeCycle.MEALS))


func _leave_and_go_home(shop: bool) -> void:
	_jump_to(18 * 60 + 10)
	await _pilot.frames(SHORT_FRAMES)
	_state("leaving")
	_game.travel.teleport_to_room("turnstiles", Vector2(4.5, 5.5))
	await _pilot.frames(SHORT_FRAMES)
	var rect: Rect2 = _game.streamer.get_room_rect_px("turnstiles")
	await _walk_to(rect.position + Vector2(4.5, 0.6) * RoomBuilder.cell_px())
	await _pilot.frames(SHORT_FRAMES)
	_info("after turnstiles room=%s" % PlayerState.get_room())
	var exit_item: Interactable = null
	for item: Interactable in _game.streamer.get_interactables_in_room("main_reception"):
		if item.interact_type == "exit":
			exit_item = item
	if exit_item == null:
		_fail("no street exit in main_reception")
		return
	await _walk_to(exit_item.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("qa_d1_09_exit_dialog")
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	if box == null:
		_fail("street exit did not offer the commute dialog")
		return
	box.choose(0)
	await _wait_until(func() -> bool: return DatabaseSystem.get_room_base_id(PlayerState.get_room()) == "player_flat" and not _game.travel.is_busy(), WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	_state("home")
	await _pilot.shot("qa_d1_10_home")
	if shop:
		await _shop()


func _shop() -> void:
	var hc: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle
	var items: Array[Dictionary] = hc.get_shop_items("supermarket")
	_info("supermarket sells: %s" % str(items))
	var counter: Interactable = null
	_game.travel.teleport_to_room("supermarket")
	await _pilot.frames(SHORT_FRAMES)
	for item: Interactable in _game.streamer.get_interactables_in_room("supermarket"):
		if item.interact_type == "shop_counter":
			counter = item
	if counter == null:
		_fail("no shop_counter in supermarket")
		return
	await _walk_to(counter.global_position)
	await _tap("interact")
	await _pilot.frames(SHORT_FRAMES * 2)
	var top: Control = _game.ui.get_top_modal()
	_info("shop UI = %s" % (top.get_class() + ":" + str(top.get_script().resource_path) if top != null else "none"))
	await _pilot.shot("qa_d1_11_shop")
	if top is DialogBox:
		(top as DialogBox).choose(0)
		await _pilot.frames(SHORT_FRAMES)
		var top2: Control = _game.ui.get_top_modal()
		if top2 is DialogBox:
			await _pilot.shot("qa_d1_11b_shop")
			(top2 as DialogBox).choose((top2 as DialogBox).get_option_count() - 1)
	while _game.ui.has_modal():
		_game.ui.close_modal()
		await _pilot.frames(2)
	_state("after shop")
	_game.travel.teleport_to_room("player_flat")
	await _pilot.frames(SHORT_FRAMES)


func _sleep(prefix: String) -> void:
	if GameClock.get_hour() < 19 and GameClock.get_hour() >= 6:
		_jump_to(19 * 60 + 30)
	var bed: Interactable = _find_item("player_flat", "bed")
	if bed != null:
		await _walk_to(bed.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	if box == null:
		_fail("bed did not offer to sleep")
		return
	box.choose(0)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DaySummary, WAIT_TIMEOUT)
	await _pilot.seconds(0.8)
	await _pilot.shot(prefix + "_12_summary")
	_check(SaveSystem.run_exists(), "run saved after sleeping (§4.2)")
	while _game.ui.has_modal():
		_game.ui.close_modal()
		await _pilot.frames(2)
	await _pilot.seconds(0.5)
	_state(prefix + " morning")


# ─── Jornada 2: va a la oficina y no trabaja ─────────────────

func _day2_slacker() -> void:
	_check(GameClock.get_day() == 2, "day 2 after sleep")
	var rep0: float = PlayerState.get_reputation()
	var money0: int = PlayerState.get_money()
	_game.travel.teleport_to_room(OFFICE)
	await _pilot.frames(SHORT_FRAMES)
	await _desk_and_mail(false)
	_jump_to(17 * 60 + 5)
	await _pilot.seconds(0.6)
	await _pilot.shot("qa_d2_02_deadline_warning")
	_jump_to(18 * 60 + 5)
	await _pilot.seconds(0.6)
	await _pilot.shot("qa_d2_03_duty_failed")
	_state("d2 after deadline")
	_info("duty after deadline: %s streak=%d" % [str(PlayerState.get_duty("duty_emails_r1")), PlayerState.get_duty_failure_streak("duty_emails_r1")])
	_check(PlayerState.get_reputation() < rep0 or rep0 <= 0.0, "failing a duty costs reputation")
	if rep0 <= 0.0:
		_fail("reputation starts at 0 and is clamped: the -8 failure penalty is invisible (rep %.1f)" % PlayerState.get_reputation())
	await _leave_and_go_home(false)
	await _sleep("qa_d2")
	_info("d2 net money %d (wage paid although no work done?)" % (PlayerState.get_money() - money0))


# ─── Jornada 3: no va al trabajo ─────────────────────────────

func _day3_absent() -> void:
	_check(GameClock.get_day() == 3, "day 3 after sleep")
	var money0: int = PlayerState.get_money()
	_info("d3 at home all day; T at home: %s" % _game.time_skip.check())
	for i: int in 8:
		if _game.time_skip.check() != "":
			break
		await _game.time_skip.skip_now()
		await _pilot.frames(SHORT_FRAMES)
		_info("skipped to %s band=%s" % [GameClock.get_time_string(), GameClock.get_current_band()])
	await _pilot.shot("qa_d3_01_home_evening")
	_state("d3 evening")
	# Starvation: empty wallet and pantry, sleep twice.
	PlayerState.spend_money(PlayerState.get_money(), "qa_drain")
	await _sleep("qa_d3")
	_info("d3 wage while absent: money delta before drain=%d" % (money0))
	var hc: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle
	_info("hungry days=%d game_over=%s" % [hc.get_hungry_days(), str(SaveSystem.is_run_over())])
	await _pilot.shot("qa_d4_01_morning_broke")


# ─── Registro ────────────────────────────────────────────────

func _listen() -> void:
	EventBus.duty_failed.connect(func(id: String, c: String) -> void: _event("duty_failed %s %s" % [id, c]))
	EventBus.duty_completed.connect(func(id: String, q: float, m: String) -> void: _event("duty_completed %s %.2f %s" % [id, q, m]))
	EventBus.duty_deadline_warned.connect(func(id: String, h: float) -> void: _event("deadline_warned %s %.1f" % [id, h]))
	EventBus.card_reader_logged.connect(func(r: String, o: String, d: int, h: int) -> void: _event("card %s %s d%d h%d" % [r, o, d, h]))
	EventBus.camera_recorded_player.connect(func(c: String, r: String, d: int) -> void: _event("camera %s %s" % [c, r]))
	EventBus.money_changed.connect(func(a: int, b: int, r: String) -> void: _event("money %d->%d %s" % [a, b, r]))
	EventBus.notebook_entry_added.connect(func(c: String, k: String, a: Array) -> void: _event("note %s %s %s" % [c, k, str(a)]))
	EventBus.game_over.connect(func(c: String, e: String, _s: Dictionary) -> void: _event("GAME_OVER %s %s" % [c, e]))
	EventBus.promotion_available.connect(func(ids: Array) -> void: _event("promotion_available %s" % str(ids)))


func _process(_delta: float) -> void:
	if _game == null or _game.ui == null:
		return
	var stack: Variant = _game.ui.get("_toasts")
	if stack is ToastStack:
		var ts: ToastStack = stack as ToastStack
		for i: int in ts.get_toast_count():
			var text: String = ts.get_toast_text(i)
			if not _toasts_seen.has(text):
				_toasts_seen.append(text)
				print("%s TOAST %s | %s" % [TAG, GameClock.get_time_string(), text])


func _event(text: String) -> void:
	var line: String = "d%d %s %s" % [GameClock.get_day(), GameClock.get_time_string(), text]
	_events.append(line)
	print("%s EVENT %s" % [TAG, line])


func _check(ok: bool, what: String) -> void:
	if ok:
		print("%s PASS %s" % [TAG, what])
	else:
		_fail(what)


func _fail(what: String) -> void:
	_fails += 1
	print("%s FAIL %s" % [TAG, what])


func _info(what: String) -> void:
	print("%s INFO %s" % [TAG, what])


func _state(label: String) -> void:
	_info("%s: day=%d %s band=%s floor=%d room=%s money=%d rep=%.1f susp=%.1f duties=%s" % [label, GameClock.get_day(),
			GameClock.get_time_string(), GameClock.get_current_band(), _game.streamer.get_current_floor(), PlayerState.get_room(),
			PlayerState.get_money(), PlayerState.get_reputation(), PlayerState.get_suspicion(),
			str(PlayerState.get_todays_duties().map(func(d: Dictionary) -> String: return "%s:%s:%.2f" % [d.get("id", ""), d.get("status", ""), float(d.get("progress", 0.0))]))])


# ─── Conducción ──────────────────────────────────────────────

func _jump_to(day_minute: int) -> void:
	var left: float = float(day_minute) - GameClock.get_day_minutes()
	if left > 0.0:
		GameClock.advance_minutes(left)


func _walk_to(target: Vector2) -> void:
	var player: Player = _game.player
	var path: PackedVector2Array = _game.streamer.find_path_to_point(player.global_position, target)
	path.append(target)
	var index: int = 0
	var elapsed: float = 0.0
	var still: float = 0.0
	var last: Vector2 = player.global_position
	var start_floor: int = _game.streamer.get_current_floor()
	while index < path.size() and elapsed < WALK_TIMEOUT and _game.streamer.get_current_floor() == start_floor:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		if player.global_position.distance_to(path[index]) <= ARRIVE_PX:
			index += 1
			continue
		player.set_virtual_input((path[index] - player.global_position).normalized(), false)
		still = still + delta if player.global_position.distance_to(last) < 0.5 else 0.0
		last = player.global_position
		if still > STUCK_SECONDS:
			index += 1
			still = 0.0
	player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.frames(2)


func _tap(action: String) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _wait_until(condition: Callable, timeout: float) -> void:
	var left: float = timeout
	while left > 0.0 and not bool(condition.call()):
		await get_tree().process_frame
		left -= get_process_delta_time()


func _find_item(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null
