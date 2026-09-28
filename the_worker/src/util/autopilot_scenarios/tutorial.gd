# tutorial.gd (escenario) — El primer día completo en el juego real (§13.8): vídeo de bienvenida en la sala de formación, paseo con HR hasta la mesa del 3B y las tres tareas (correos, la idea de Claudia, la ronda de Lasker).
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y eventos de entrada reales).
# ESCUCHA: nada.
extends Node

## SHOT_TIMEOUT=480 tools/screenshot.sh /tmp/shots_tutorial tutorial
## Partida nueva desde el menú principal real (alta, apertura saltada, MainMenu instala el tutorial). Esperas del tutorial a
## TIME_SCALE (lecturas y presupuestos más cortos; los figurantes a su velocidad real).
## Capturas: tut_01_video_move · 02_video_sneak · 03_video_crouch · 04_video_ack · 05_tape_end ·
## 06_hr_hello · 07_hr_corridor · 08_hr_elevator · 09_hr_floor3 · 10_hr_desk · 11_task_emails ·
## 12_mail · 13_task_idea · 14_idea_told · 15_task_hide · 16_hidden · 17_done.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const TIME_SCALE := 0.6
const SHORT_FRAMES := 8
const ARRIVE_PX := 12.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 40.0
const STEP_TIMEOUT := 60.0
const FOLLOW_PX := 70.0
const MAILS := 3
const PANEL_TYPE := "elevator_panel"
const DESK_TYPE := "desk"

var _pilot: Autopilot = null
var _game: GameRoot = null
var _dir: TutorialDirector = null
var _seen_steps: Dictionary = {}


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	SettingsMenu.set_value(TutorialDirector.SETTING_SEEN, false, false)
	await _start_from_menu()
	_game = GameRoot.find(get_tree())
	_dir = TutorialDirector.find(get_tree())
	if _game == null or _dir == null:
		push_error("tutorial: the tutorial did not start (game=%s)" % str(_game))
		return
	_dir.budget_scale = TIME_SCALE
	_seen_steps[_dir.get_step()] = true
	_dir.step_changed.connect(func(step: String) -> void: _seen_steps[step] = true)
	await _video()
	await _walk()
	await _first_day()
	_log("end")


## Como el jugador: menú principal → alta → apertura (se salta) → MainMenu._launch_new_run instala el
## tutorial (Tutorial.install) y cambia a la escena de juego.
func _start_from_menu() -> void:
	var menu: MainMenu = MainMenu.new()
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	host.add_child(menu)
	await _pilot.frames(SHORT_FRAMES)
	menu.begin_new_run(PLAYER_NAME, DIFFICULTY)
	await _pilot.frames(SHORT_FRAMES)
	var cine: Control = menu.cinematic()
	if cine != null and is_instance_valid(cine) and cine.has_method("skip"):
		cine.call("skip")
	await _wait_until(func() -> bool: return GameRoot.find(get_tree()) != null, WALK_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	_log_install()


func _log_install() -> void:
	print("[tutorial-qa] menu launch: hook installed=%s director=%s" % [str(Tutorial.is_installed()),
			str(TutorialDirector.find(get_tree()) != null)])


# ─── Parte 1 ──────────────────────────────────────────────────

func _video() -> void:
	await _wait_step("video_move")
	await _pilot.seconds(0.6)
	await _pilot.shot("tut_01_video_move")
	await _hold_move(Vector2.LEFT, 1.2, false)
	await _wait_step("video_sneak")
	_game.player.set_sneak_held(true)
	await _hold_move(Vector2.RIGHT, 0.7, false)
	await _pilot.shot("tut_02_video_sneak")
	await _hold_move(Vector2.RIGHT, 0.8, false)
	_game.player.set_sneak_held(false)
	await _wait_step("video_crouch")
	_game.player.set_crouching(true)
	await _pilot.seconds(0.6)
	await _pilot.shot("tut_03_video_crouch")
	await _pilot.seconds(0.6)
	_game.player.set_crouching(false)
	await _wait_step("video_sprint")
	await _hold_move(Vector2.DOWN, 0.9, true)
	await _wait_step("video_interact")
	var screen: Interactable = _find_item(_dir.tutorial_room(), "training_screen")
	await _walk_to(screen.global_position + Vector2(0.0, RoomBuilder.cell_px()))
	await _tap("interact")
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("tut_04_video_ack")
	await _wait_step("video_end")
	await _pilot.seconds(0.4)
	await _pilot.shot("tut_05_tape_end")


# ─── Parte 2 ──────────────────────────────────────────────────

func _walk() -> void:
	await _wait_step("walk_hello")
	await _pilot.seconds(1.6)
	await _pilot.shot("tut_06_hr_hello")
	await _follow_until("walk_keys")
	await _pilot.shot("tut_07_hr_corridor")
	await _follow_until("walk_elevator")
	await _follow_guide_stop()
	await _pilot.shot("tut_08_hr_elevator")
	await _ride_elevator(_dir.office_floor())
	await _pilot.seconds(1.0)
	await _pilot.shot("tut_09_hr_floor3")
	await _follow_until("walk_desk")
	await _follow_guide_stop()
	await _walk_to(_dir.seat_point())
	await _pilot.seconds(0.8)
	await _pilot.shot("tut_10_hr_desk")


func _follow_until(step: String) -> void:
	var left: float = STEP_TIMEOUT
	while _dir != null and is_instance_valid(_dir) and not _seen_steps.has(step) and left > 0.0:
		await _step_toward_guide()
		left -= get_physics_process_delta_time()
	_game.player.set_virtual_input(Vector2.ZERO, false)


## Sigue al guía hasta que se detiene en su punto.
func _follow_guide_stop() -> void:
	var left: float = STEP_TIMEOUT
	var walk: TutorialWalk = _dir.get_walk()
	while walk != null and walk.guide != null and is_instance_valid(walk.guide) and walk.guide.is_moving() and left > 0.0:
		await _step_toward_guide()
		left -= get_physics_process_delta_time()
	_game.player.set_virtual_input(Vector2.ZERO, false)


func _step_toward_guide() -> void:
	await get_tree().physics_frame
	var walk: TutorialWalk = _dir.get_walk() if is_instance_valid(_dir) else null
	var guide: TutorialActor = walk.guide if walk != null else null
	if guide == null or not is_instance_valid(guide):
		_game.player.set_virtual_input(Vector2.ZERO, false)
		return
	var p: Vector2 = _game.player.global_position
	if p.distance_to(guide.global_position) <= FOLLOW_PX:
		_game.player.set_virtual_input(Vector2.ZERO, false)
		return
	var path: PackedVector2Array = _game.streamer.find_path_to_point(p, guide.global_position)
	var next: Vector2 = path[1] if path.size() > 1 else guide.global_position
	_game.player.set_virtual_input((next - p).normalized(), false)


func _ride_elevator(target_floor: int) -> void:
	var panel: Interactable = null
	for item: Node in get_tree().get_nodes_in_group("interactables"):
		var it: Interactable = item as Interactable
		if it != null and it.interact_type == PANEL_TYPE and (panel == null or it.global_position.distance_to(_game.player.global_position) < panel.global_position.distance_to(_game.player.global_position)):
			panel = it
	if panel == null:
		push_error("tutorial: no elevator panel")
		return
	await _walk_to(panel.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.travel.get_panel() != null, 10.0)
	var select: FloorTravel.FloorSelectPanel = _game.travel.get_panel()
	if select == null:
		push_error("tutorial: the elevator panel did not open")
		return
	select.choose(select.index_of_floor(target_floor))
	await _wait_until(func() -> bool: return not _game.travel.is_busy(), 20.0)
	_log("arrived on floor %d" % _game.streamer.get_current_floor())


# ─── Parte 3 ──────────────────────────────────────────────────

func _first_day() -> void:
	await _wait_step("day_emails")
	await _pilot.seconds(0.8)
	await _pilot.shot("tut_11_task_emails")
	await _answer_mails()
	await _wait_step("day_idea")
	await _pilot.seconds(0.6)
	await _pilot.shot("tut_13_task_idea")
	await _wait_step("day_idea_watch")
	await _follow_npc(str(_dir.bal("tareas.idea_npc")), 2.0)
	await _pilot.shot("tut_14_idea_told")
	await _wait_step("day_hide")
	await _pilot.seconds(1.0)
	await _pilot.shot("tut_15_task_hide")
	await _hide_in_closet()
	await _watch_patrol()
	await _wait_step("day_done")
	await _pilot.seconds(1.0)
	await _pilot.shot("tut_17_done")


func _answer_mails() -> void:
	await _tap("computer")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is StellarOS, 10.0)
	var computer: StellarOS = _game.ui.get_top_modal() as StellarOS
	if computer == null:
		push_error("tutorial: the computer did not open at the desk")
		return
	await _wait_until(func() -> bool: return computer.is_booted(), 20.0)
	computer.open_app(StellarOS.APP_MAIL)
	await _wait_until(func() -> bool: return computer.get_open_app() is MailApp, 10.0)
	var mail: MailApp = computer.get_open_app() as MailApp
	for i: int in MAILS:
		await mail.answer_current(mail.current_correct_reply())
		await _pilot.frames(SHORT_FRAMES)
		if i == 1:
			await _pilot.shot("tut_12_mail")
	await _tap("computer")
	await _pilot.frames(SHORT_FRAMES)


func _hide_in_closet() -> void:
	var spot: HidingSpot = _dir.get_first_day().hiding_spot() if _dir.get_first_day() != null else null
	if spot == null:
		push_error("tutorial: no hiding spot")
		return
	await _walk_to(spot.global_position)
	await _tap("interact")
	await _pilot.frames(SHORT_FRAMES)
	var top: Control = _game.ui.get_top_modal()
	if top is DialogBox:
		(top as DialogBox).choose(0)
	await _pilot.frames(SHORT_FRAMES)
	_log("hiding=%s" % str(_game.player.is_hiding()))


func _watch_patrol() -> void:
	var day: TutorialFirstDay = _dir.get_first_day()
	var shot_taken: bool = false
	var left: float = STEP_TIMEOUT
	while is_instance_valid(_dir) and _dir.get_step() == "day_hide" and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		var b: TutorialActor = day.bernard if day != null else null
		if not shot_taken and b != null and is_instance_valid(b) and b.global_position.distance_to(_game.player.global_position) < 4.0 * RoomBuilder.cell_px():
			shot_taken = true
			await _pilot.shot("tut_16_hidden")
	_log("patrol outcomes=%s" % str(day.get_patrol_outcomes() if day != null else []))


# ─── Conducción ───────────────────────────────────────────────

## Se acerca al nodo de un personaje y se queda a su lado `seconds`.
func _follow_npc(npc_id: String, seconds: float) -> void:
	var node: NPCNode = _game.npc_layer.get_node_for(npc_id)
	if node == null:
		return
	await _walk_to(_game.streamer.nearest_walkable_point(node.get_visual_position() + Vector2(0.0, 1.5 * RoomBuilder.cell_px())))
	await _pilot.seconds(seconds)


## Espera a que el tutorial haya llegado a `step` (aunque ya lo haya pasado).
func _wait_step(step: String) -> void:
	await _wait_until(func() -> bool: return not is_instance_valid(_dir) or _seen_steps.has(step), STEP_TIMEOUT)
	_log("step " + step)


func _hold_move(dir: Vector2, seconds: float, sprint: bool) -> void:
	_game.player.set_virtual_input(dir, sprint)
	await _pilot.seconds(seconds)
	_game.player.set_virtual_input(Vector2.ZERO, false)


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
	print("[tutorial-qa] %s: step=%s floor=%d room=%s time=%s elapsed=%.1f" % [label,
			_dir.get_step() if is_instance_valid(_dir) else "-", _game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string(), _dir.get_elapsed() if is_instance_valid(_dir) else -1.0])
