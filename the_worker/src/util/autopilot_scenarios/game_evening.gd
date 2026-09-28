# game_evening.gd (escenario) — Una tarde jugada de verdad: aviso de salida en la mesa, salto temporal, cierre de las 19:00 (el vigilante acompaña fuera), la calle hasta el piso, dormir en la cama (resumen y guardado) y el trayecto al trabajo por la mañana.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y eventos de entrada reales).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_evening game_evening [--force-rank=N]   (luego: game_continue)
## Saltos de QA del reloj (advance_minutes, como el panel F1) para no esperar la jornada entera.
## Capturas: evening_01_warning · 02_skip · 03_leaving · 04_swept · 05_home · 06_bed_dialog ·
## 07_summary · 08_morning · 09_commute.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const DESK_TYPE := "desk"
const BED_TYPE := "bed"
const TURNSTILES := "turnstiles"
const TURNSTILES_INNER := Vector2(4.5, 5.5)
const TURNSTILES_OUTER := Vector2(4.5, 0.6)
const WARN_MINUTE := 17 * 60 + 58
const SKIP_MINUTE := 18 * 60 + 5
const LEAVE_MINUTE := 18 * 60 + 58
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 40.0
const WAIT_TIMEOUT := 20.0
const SHORT_FRAMES := 8

var _pilot: Autopilot = null
var _game: GameRoot = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("game_evening: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("game_evening: GameRoot did not start")
		return
	await _desk_evening()
	await _closing()
	await _home_and_sleep()
	await _commute_morning()


# ─── Tramos ───────────────────────────────────────────────────

func _desk_evening() -> void:
	var office: String = PlayerState.get_occupation().office_room
	_game.travel.teleport_to_room(office)
	await _pilot.frames(SHORT_FRAMES)
	var desk: Interactable = _find_item(office, DESK_TYPE)
	if desk != null:
		await _walk_to(desk.global_position)
	_jump_to(WARN_MINUTE)
	await _wait_until(func() -> bool: return GameClock.get_hour() >= 18, WAIT_TIMEOUT)
	await _pilot.seconds(0.4)
	_log("clock-out warning")
	await _pilot.shot("evening_01_warning")
	_jump_to(SKIP_MINUTE)
	await _tap("time_skip")
	await _pilot.frames(SHORT_FRAMES)
	_log("time skip at the desk: check=%s observer=%s" % [_game.time_skip.check(), _game.observer_name()])
	await _pilot.shot("evening_02_skip")
	if _game.ui.get_top_modal() is DialogBox:
		(_game.ui.get_top_modal() as DialogBox).choose(1)
		await _pilot.frames(SHORT_FRAMES)


## A las 18:58 en los tornos, camino de la salida: a las 19:00 el vigilante acompaña fuera.
func _closing() -> void:
	_game.travel.teleport_to_room(TURNSTILES, TURNSTILES_INNER)
	_jump_to(LEAVE_MINUTE)
	await _pilot.frames(SHORT_FRAMES)
	var before: float = BeliefNet.calculate_player_suspicion()
	var swipes: int = Security.get_access_log().size()
	_log("leaving (suspicion %.1f, swipes %d)" % [before, swipes])
	await _pilot.shot("evening_03_leaving")
	var rect: Rect2 = _game.streamer.get_room_rect_px(TURNSTILES)
	_walk_to.call(rect.position + TURNSTILES_OUTER * RoomBuilder.cell_px())
	await _wait_until(func() -> bool: return _game.streamer.get_current_floor() == Database.get_balance_int("mundo.planta_exterior"), WAIT_TIMEOUT)
	_game.player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.seconds(0.6)
	_log("swept (suspicion %.1f → %.1f, swipes %d → %d, alert %d)" % [before, BeliefNet.calculate_player_suspicion(),
			swipes, Security.get_access_log().size(), Security.get_alert_level()])
	await _pilot.shot("evening_04_swept")


func _home_and_sleep() -> void:
	var home: String = str(Database.get_balance("hogar.sala_domicilio"))
	var bed: Interactable = _find_item(home, BED_TYPE)
	await _walk_to(_game.streamer.get_spawn_point(home))
	if bed != null:
		await _walk_to(bed.global_position)
	await _pilot.frames(SHORT_FRAMES)
	_log("home: T would %s" % _game.time_skip.check())
	await _pilot.shot("evening_05_home")
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("evening_06_bed_dialog")
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DaySummary, WAIT_TIMEOUT)
	await _pilot.seconds(1.0)
	_log("summary: saved=%s" % str(SaveSystem.run_exists()))
	await _pilot.shot("evening_07_summary")
	_game.ui.close_modal()
	await _pilot.seconds(0.8)
	_log("morning: look=%d tier=%d" % [hash(_game.player.get_appearance()), _game.player.get_tier()])
	await _pilot.shot("evening_08_morning")


func _commute_morning() -> void:
	var door: Interactable = null
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if (node as Interactable).interact_id == WorldBridges.COMMUTE_DOOR_ID:
			door = node as Interactable
	if door == null:
		push_error("game_evening: no 'go to work' door in the flat")
		return
	await _walk_to(door.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	await _wait_until(func() -> bool: return _game.streamer.get_current_floor() == 0 and not _game.travel.is_busy(), WAIT_TIMEOUT)
	await _pilot.seconds(0.5)
	_log("commuted")
	await _pilot.shot("evening_09_commute")


# ─── Conducción ───────────────────────────────────────────────

func _jump_to(day_minute: int) -> void:
	var left: float = float(day_minute) - GameClock.get_day_minutes()
	if left > 0.0:
		GameClock.advance_minutes(left)


## Camina por la ruta de FloorStreamer con el stick virtual; recalcula si se atasca.
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


func _log(label: String) -> void:
	print("[game_evening] %s: floor=%d room=%s time=%s day=%d" % [label, _game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string(), GameClock.get_day()])
