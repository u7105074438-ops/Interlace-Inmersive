# security_ops.gd (escenario) — El módulo de seguridad jugado de verdad: taquilla de uniformes, un cuerpo arrastrado hasta un escondite y a la compactadora, un candado forzado, la consola de monitores con vigilantes delante, el cuadro eléctrico y el apagón, y esconderse.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y la tecla E reales; saltos de QA como el panel F1).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_secops security_ops
## Saltos de QA (como el panel F1): teletransporte entre salas, dar objetos, y una eliminación en
## frío (NPCDirector.remove_npc «eliminated», como la opción de la ventana de flagrancia).
## Capturas: secops_01_locker_menu · 02_uniform · 03_body · 04_dragging · 05_hide_body_prompt ·
## 06_body_hidden · 07_chute_prompt · 08_chute_confirm · 09_chute_done · 10_force_confirm · 11_forcing ·
## 12_forced · 13_monitor_menu · 14_footage_list · 15_wipe_confirm (o el aviso de testigos) · 16_wiping ·
## 17_breaker_panel · 18_blackout · 19_hidden.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 25.0
const WAIT_TIMEOUT := 12.0
const SHORT_FRAMES := 8
const CRATES := "hide_freight_crates"
const FREIGHT_ROOM := "freight_elevator_room"

var _pilot: Autopilot = null
var _game: GameRoot = null
var _walk_serial: int = 0


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("security_ops: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("security_ops: GameRoot did not start")
		return
	await _uniform()
	await _body()
	await _forcing()
	await _monitor()
	await _blackout()
	await _hide()


# ─── Tramos ───────────────────────────────────────────────────

func _uniform() -> void:
	await _go("security_locker_room")
	var locker: Interactable = _find_id("security_locker_room", "security_uniform_locker_a")
	await _use(locker)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("secops_01_locker_menu")
	_choose(0)
	await _wait_until(func() -> bool: return not PlayerState.get_disguise().is_empty(), WAIT_TIMEOUT)
	await _pilot.seconds(0.6)
	_log("uniform %s" % PlayerState.get_disguise())
	await _pilot.shot("secops_02_uniform")
	await _use(locker)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	_choose(0)
	await _pilot.frames(SHORT_FRAMES)


func _body() -> void:
	await _go(FREIGHT_ROOM)
	_quiet(true)
	var keeper: SecurityKeeper = SecurityKeeper.ensure(get_tree())
	var victim: String = _victim()
	NPCDirector.remove_npc(victim, "eliminated")
	NPCDirector.move_body(victim, FREIGHT_ROOM, "")
	keeper.sync_floor()
	await _pilot.seconds(0.5)
	await _pilot.shot("secops_03_body")
	var body: BodyNode = keeper.body_node(victim)
	if body == null:
		push_error("security_ops: no body node")
		return
	await _use(body)
	await _wait_until(func() -> bool: return keeper.is_dragging(), WAIT_TIMEOUT)
	var crates: Interactable = _find_id(FREIGHT_ROOM, CRATES)
	_walk_to.call(crates.global_position)
	await _pilot.seconds(1.5)
	await _pilot.shot("secops_04_dragging")
	await _wait_until(func() -> bool: return _game.player.get_focused_interactable() == crates, WALK_TIMEOUT)
	await _stop_walk()
	await _pilot.shot("secops_05_hide_body_prompt")
	await _tap("interact")
	await _wait_until(func() -> bool: return not keeper.is_dragging(), WAIT_TIMEOUT)
	await _pilot.seconds(0.4)
	_log("body hidden: %s" % str(NPCDirector.get_body_info(victim)))
	await _pilot.shot("secops_06_body_hidden")
	await _chute(keeper, victim, crates)


func _chute(keeper: SecurityKeeper, victim: String, crates: Interactable) -> void:
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	_choose(SecurityBodies.spot_actions(crates as HidingSpot, false).find(SecurityBodies.A_PULL_BODY))
	await _wait_until(func() -> bool: return keeper.is_dragging(), WAIT_TIMEOUT)
	await _go_same_floor("trash_dock")
	var chute: Interactable = _find_type("trash_dock", "trash_chute")
	await _walk_to(chute.global_position)
	await _wait_until(func() -> bool: return _game.player.get_focused_interactable() == chute, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("secops_07_chute_prompt")
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("secops_08_chute_confirm")
	_choose(0)
	await _wait_until(func() -> bool: return not keeper.is_dragging(), WAIT_TIMEOUT)
	await _pilot.seconds(0.6)
	await _pilot.shot("secops_09_chute_done")
	_log("chute: %s disposed=%s" % [str(NPCDirector.get_body_info(victim)), SecurityBodies.is_disposed(victim)])
	_quiet(false)


func _forcing() -> void:
	PlayerState.add_item("lockpick")
	await _go("old_confidential_cage")
	var lock: Interactable = _find_id("old_confidential_cage", "cage_padlock")
	await _use(lock)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("secops_10_force_confirm")
	_choose(0)
	await _pilot.seconds(2.0)
	await _pilot.shot("secops_11_forcing")
	await _wait_until(func() -> bool: return _game.player.current_act().is_empty(), WAIT_TIMEOUT)
	await _pilot.seconds(0.3)
	await _pilot.shot("secops_12_forced")
	_log("cage forced")


func _monitor() -> void:
	Security.register_camera_footage("turnstiles", GameClock.get_day(), GameClock.get_hour())
	await _go("monitor_room")
	await _pilot.seconds(1.5)
	var console: Interactable = _find_type("monitor_room", "monitor_console")
	await _use(console)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("secops_13_monitor_menu")
	_choose(0)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is FloorTravel.FloorSelectPanel, WAIT_TIMEOUT)
	await _pilot.shot("secops_14_footage_list")
	_game.ui.close_modal()
	await _pilot.frames(SHORT_FRAMES)
	await _use(console)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	_choose(1)
	await _pilot.frames(SHORT_FRAMES)
	_log("monitor: witnesses=%s" % str(SecurityKit.witnesses(_game.player)))
	await _pilot.shot("secops_15_wipe_confirm")
	_choose(0)
	await _pilot.seconds(1.0)
	if _game.ui.get_top_modal() is DialogBox:
		_choose(0)
	await _wait_until(func() -> bool: return Security.get_footage_list().is_empty() or not _game.player.current_act().is_empty(), WAIT_TIMEOUT)
	await _pilot.seconds(0.8)
	await _pilot.shot("secops_16_wiping")
	await _wait_until(func() -> bool: return _game.player.current_act().is_empty() and not _game.ui.has_modal(), WAIT_TIMEOUT)
	_log("monitor: footage left=%d" % Security.get_footage_list().size())


func _blackout() -> void:
	await _go("electrical_room")
	var breaker: Interactable = _find_type("electrical_room", "electrical_breaker")
	await _use(breaker)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is FloorTravel.FloorSelectPanel, WAIT_TIMEOUT)
	await _pilot.shot("secops_17_breaker_panel")
	var panel: FloorTravel.FloorSelectPanel = _game.ui.get_top_modal() as FloorTravel.FloorSelectPanel
	panel.choose(panel.index_of_floor(0))
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	_choose(0)
	await _wait_until(func() -> bool: return SecurityPower.is_blackout_on(0), WAIT_TIMEOUT)
	await _go("main_reception")
	await _pilot.seconds(0.8)
	_log("blackout: cases=%d" % Security.get_active_investigations().size())
	await _pilot.shot("secops_18_blackout")


func _hide() -> void:
	await _go("office_supplies")
	var spot: Interactable = null
	for node: Interactable in _game.streamer.get_hiding_spots_in_room("office_supplies"):
		spot = node
	if spot == null:
		return
	await _use(spot)
	await _pilot.frames(SHORT_FRAMES)
	if _game.ui.get_top_modal() is DialogBox:
		_choose(0)
	await _wait_until(func() -> bool: return _game.player.is_hiding(), WAIT_TIMEOUT)
	await _pilot.seconds(0.5)
	await _pilot.shot("secops_19_hidden")


# ─── Conducción ───────────────────────────────────────────────

## QA: sótano sin testigos mientras se prueba el cuerpo (la capa de personajes deja de sincronizar y
## los presentes no miran); al terminar, todo vuelve a su ser.
func _quiet(on: bool) -> void:
	_game.npc_layer.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	for node: NPCNode in _game.npc_layer.get_nodes():
		node.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		node.visible = not on
		node.perception.set_active(not on)


func _go(room_id: String) -> void:
	_game.travel.teleport_to_room(room_id)
	await _pilot.seconds(0.6)
	_log("at")


## Salto de QA dentro de la planta (el cuerpo arrastrado sigue al jugador).
func _go_same_floor(room_id: String) -> void:
	_game.player.global_position = _game.streamer.get_spawn_point(room_id)
	await _pilot.seconds(0.5)


## Camina hasta el interactivo y pulsa E cuando está enfocado.
func _use(item: Interactable) -> void:
	if item == null:
		push_error("security_ops: missing interactable")
		return
	await _walk_to(item.global_position)
	await _wait_until(func() -> bool: return _game.player.get_focused_interactable() == item, WAIT_TIMEOUT)
	await _tap("interact")


func _walk_to(target: Vector2) -> void:
	_walk_serial += 1
	var serial: int = _walk_serial
	var player: Player = _game.player
	var path: PackedVector2Array = _game.streamer.find_path_to_point(player.global_position, target)
	path.append(target)
	var index: int = 0
	var elapsed: float = 0.0
	var still: float = 0.0
	var last: Vector2 = player.global_position
	while index < path.size() and elapsed < WALK_TIMEOUT and serial == _walk_serial:
		await get_tree().physics_frame
		if serial != _walk_serial:
			return
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
	if serial == _walk_serial:
		player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.frames(2)


## Corta la caminata en curso (la que se lanzó sin esperar) y para al jugador.
func _stop_walk() -> void:
	_walk_serial += 1
	_game.player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.frames(SHORT_FRAMES)


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


func _find_type(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


func _find_id(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


func _victim() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and not npc.is_named:
			return npc.id
	return ""


func _log(label: String) -> void:
	print("[security_ops] %s: floor=%d room=%s time=%s" % [label, _game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string()])
