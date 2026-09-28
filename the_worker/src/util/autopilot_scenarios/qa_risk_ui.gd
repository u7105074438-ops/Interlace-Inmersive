# qa_risk_ui.gd (escenario QA) — Riesgo: robar un cajón con gente delante (ventana de flagrancia), eliminar sin testigos, esconder el cuerpo y dejar correr los días de la investigación (§11.3, §12.1-12.7, §13).
# PROPIETARIO DE: nada (conduce al jugador con stick virtual y E; saltos de QA como el panel F1).
# ESCUCHA: EventBus (solo registra lo que vería el jugador).
extends Node

## tools/screenshot.sh /tmp/qa_risk qa_risk_ui
## Salida: "[qa_risk_ui] PASS|FAIL|INFO ...". Capturas: qarisk_01_office · 02_watched · 03_act · 04_caught ·
## 05_after_choice · 06_body · 07_hidden · 08_dayN_* · 09_final.

const TAG := "[qa_risk_ui]"
const OFFICE := "wing_3b"
const DRAWER := "nate_drawer"
const WAIT_TIMEOUT := 12.0
const WALK_TIMEOUT := 25.0
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const SHORT_FRAMES := 8

var _pilot: Autopilot = null
var _game: GameRoot = null
var _fails: int = 0
var _toasts: Array[String] = []
var _crimes: Array[String] = []


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("Risk Tester", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		_fail("game did not start")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		_fail("no GameRoot")
		return
	EventBus.crime_committed.connect(func(c: String, r: String, _d: Dictionary) -> void: _crimes.append("%s@%s" % [c, r]))
	if EventBus.has_signal("toast_requested"):
		EventBus.connect("toast_requested", func(a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: _toasts.append(str(a)))
	await _steal_watched()
	await _eliminate_and_hide()
	await _investigation_days()
	_info("crimes=%s" % str(_crimes))
	_info("toasts=%s" % str(_toasts))
	print("%s DONE fails=%d" % [TAG, _fails])


func _steal_watched() -> void:
	_game.travel.teleport_to_room(OFFICE)
	GameClock.set_time(GameClock.get_day(), 10, 0)
	await _pilot.seconds(1.5)
	await _pilot.shot("qarisk_01_office")
	var drawer: Interactable = _find_id(OFFICE, DRAWER)
	if drawer == null:
		_fail("drawer %s missing" % DRAWER)
		return
	var money0: int = PlayerState.get_money()
	var inv0: int = PlayerState.get_inventory().size() if true else -1
	await _use(drawer)
	await _pilot.frames(SHORT_FRAMES)
	var watched: bool = _game.ui.get_top_modal() is DialogBox
	var observer: Dictionary = _game.find_observer(OfficeKit.act_seconds("cajon"))
	_info("watched-confirm shown=%s observer=%s" % [watched, str(observer)])
	await _pilot.shot("qarisk_02_watched")
	if watched:
		_choose(1)  # «Hacerlo igualmente» (índice 0 = «Ahora no»)
	await _pilot.seconds(0.8)
	await _pilot.shot("qarisk_03_act")
	var caught: CaughtHandler = _game.sim_nodes.get("CaughtHandler") as CaughtHandler
	await _wait_until(func() -> bool: return caught.is_window_open() or _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	_info("crimes so far=%s act=%s modal=%s" % [str(_crimes), str(_game.player.current_act()), str(_game.ui.get_top_modal())])
	await _pilot.seconds(0.5)
	var held: Array[String] = []
	for b: Belief in BeliefNet.get_beliefs_held_by(str(_game.find_observer().get("id", "npc_claudia_reeves"))):
		held.append("%s c=%.2f" % [b.id, b.certainty])
	_info("observer beliefs after theft=%s" % str(held))
	_check(not held.is_empty() or caught.is_window_open(), "an NPC announced as 'can see you' registers the theft (belief or flagrancy)")
	_info("caught window open=%s options=%s" % [caught.is_window_open(), str(caught.get_options())])
	# §12.2: el aviso fuerte ("te pillará") solo cuando el testigo llega a flagrancia.
	if bool(observer.get("catches", false)) and str(observer.get("kind", "")) == "npc":
		_check(caught.is_window_open() or _has_full_belief(held),
				"a 'will catch you' warning is followed by flagrancy")
	await _pilot.shot("qarisk_04_caught")
	if _game.ui.get_top_modal() is DialogBox:
		_choose(0)
		await _pilot.seconds(0.5)
	_info("money %d->%d items %d->%d" % [money0, PlayerState.get_money(), inv0,
			PlayerState.get_inventory().size() if true else -1])
	if caught.is_window_open():
		var r: Dictionary = caught.choose_elimination()
		_info("choose_elimination with witnesses? -> %s" % str(r))
		if not bool(r.get("ok", false)):
			var b: Dictionary = caught.choose_bribe()
			_info("bribe -> %s" % str(b))
	await _pilot.seconds(1.0)
	await _pilot.shot("qarisk_05_after_choice")
	_check(not _game.ui.has_modal() or not (_game.ui.get_top_modal() is DialogBox), "no dangling modal after caught flow")


func _has_full_belief(held: Array[String]) -> bool:
	for line: String in held:
		if float(line.get_slice("c=", 1)) >= Database.get_balance_float("creencias.certeza_directa_completa") - 0.01:
			return true
	return false


func _eliminate_and_hide() -> void:
	_game.travel.teleport_to_room("freight_elevator_room")
	await _pilot.seconds(0.6)
	var victim: String = ""
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and not npc.is_named:
			victim = npc.id
			break
	var cases0: int = Security.get_all_investigations().size()
	NPCDirector.remove_npc(victim, "eliminated")
	EventBus.crime_committed.emit("elimination", "freight_elevator_room", {"npc_id": victim, "witnesses": 0})
	NPCDirector.move_body(victim, "freight_elevator_room", "")
	var keeper: SecurityKeeper = SecurityKeeper.ensure(get_tree())
	keeper.sync_floor()
	await _pilot.seconds(0.5)
	await _pilot.shot("qarisk_06_body")
	var body: BodyNode = keeper.body_node(victim)
	if body == null:
		_fail("no body node for %s" % victim)
		return
	await _use(body)
	await _wait_until(func() -> bool: return keeper.is_dragging(), WAIT_TIMEOUT)
	_check(keeper.is_dragging(), "body drag starts")
	for i: int in 4:
		await _pilot.seconds(0.5)
		var info: Array[String] = []
		for n: NPCNode in _game.npc_layer.get_nodes():
			var d: float = n.global_position.distance_to(_game.player.global_position) / RoomBuilder.cell_px()
			if d < 14.0 and n.get_perception() != null:
				info.append("%s d=%.1f c=%.2f st=%d sees=%s" % [n.npc_id, d, n.get_perception().get_counter(),
						n.get_perception().get_state(), n.get_perception().sees_point(_game.player.global_position)])
		_info("drag t=%.1f exposure=%s npcs=%s" % [i * 0.5, str(Perception.assess_exposure(_game.player,
				PlayerState.get_room())), str(info)])
	var crates: Interactable = _find_id("freight_elevator_room", "hide_freight_crates")
	if crates != null:
		await _use(crates)
		await _wait_until(func() -> bool: return not keeper.is_dragging(), WAIT_TIMEOUT)
	_check(not keeper.is_dragging(), "body hidden in crates")
	await _pilot.seconds(0.4)
	await _pilot.shot("qarisk_07_hidden")
	_info("body=%s cases %d->%d" % [str(NPCDirector.get_body_info(victim)), cases0, Security.get_all_investigations().size()])


func _investigation_days() -> void:
	for i: int in 6:
		var day: int = GameClock.get_day()
		GameClock.set_time(day + 1, 9, 0)
		Security.process_day(day + 1)
		await _pilot.frames(2)
		for inv: Investigation in Security.get_all_investigations():
			_info("d%d case %s" % [day + 1, str(Security.get_case_report(inv.id)).left(400)])
		_info("d%d suspicion=%.1f alert=%d cold=%d" % [day + 1, Security.get_effective_suspicion(),
				Security.get_alert_level(), Security.get_cold_cases().size()])
	await _pilot.seconds(0.5)
	await _pilot.shot("qarisk_09_final")


func _use(item: Node2D) -> void:
	await _walk_to(item.global_position)
	await _wait_until(func() -> bool: return _game.player.get_focused_interactable() == item, WAIT_TIMEOUT)
	if _game.player.get_focused_interactable() != item:
		_fail("could not focus %s" % item.name)
	await _tap("interact")


func _walk_to(target: Vector2) -> void:
	var player: Player = _game.player
	var path: PackedVector2Array = _game.streamer.find_path_to_point(player.global_position, target)
	path.append(target)
	var index: int = 0
	var elapsed: float = 0.0
	var still: float = 0.0
	var last: Vector2 = player.global_position
	while index < path.size() and elapsed < WALK_TIMEOUT:
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


func _choose(index: int) -> void:
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	if box != null:
		box.choose(index)


func _wait_until(condition: Callable, timeout: float) -> void:
	var left: float = timeout
	while left > 0.0 and not bool(condition.call()):
		await get_tree().process_frame
		left -= get_process_delta_time()


func _find_id(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


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
