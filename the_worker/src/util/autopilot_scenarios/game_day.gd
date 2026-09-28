# game_day.gd (escenario) — Una mañana jugada de verdad: tornos de la PB → ascensor a la 3 → mesa del 3B → ordenador (arranque, MAIL, dos correos) → office de planta → la gente sale a comer a las 13:00.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y eventos de entrada reales).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_game_day game_day
## El jugador camina por las rutas de FloorStreamer (set_virtual_input, como el stick de Android),
## interactúa con E (InputEventAction reales: InteractionRouter → FloorTravel), elige planta en el
## panel, abre el ordenador con C en su mesa (WorldBridges lo sienta), contesta dos correos con MAIL
## y camina al office. Para la comida, un salto de QA del reloj hasta las 12:50 y espera real.
## Capturas: game_day_01_turnstiles · 02_elevator_panel · 03_ride · 04_floor3 · 05_desk ·
## 06_computer_boot · 06b_seated · 07_mail · 07b_time_skip (T en la mesa con los compañeros
## trabajando: diálogo si nadie le mira, o la negativa con el nombre de quien mira) · 08_pantry ·
## 09_lunch_start · 10_lunch_leaving.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const ELEVATOR_ROOM := "main_elevator_1@0"
const PANEL_TYPE := "elevator_panel"
const TARGET_FLOOR := 3
const OFFICE := "wing_3b"
const DESK_ID := "player_desk"
const PANTRY := "p3_pantry"
const LUNCH_WATCH_CELLS := Vector2(15.0, 7.0)
const MAILS_TO_ANSWER := 2
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 40.0
const BOOT_TIMEOUT := 20.0
const APP_TIMEOUT := 10.0
const LUNCH_JUMP_HOUR := 12
const LUNCH_JUMP_MINUTE := 50
const LUNCH_HOUR := 13
const LUNCH_WATCH_MINUTES := 4
const OVERVIEW_ZOOM := 0.8
const SHORT_FRAMES := 8
const DIM_PATH := "Root/Modals/Dim"

var _pilot: Autopilot = null
var _game: GameRoot = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("game_day: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("game_day: GameRoot did not start")
		return
	_log("start")
	await pilot.shot("game_day_01_turnstiles")
	await _ride_elevator()
	await _work_at_desk()
	await _go_to_pantry()
	await _watch_lunch()


# ─── Tramos ───────────────────────────────────────────────────

func _ride_elevator() -> void:
	var panel: Interactable = _find_item(ELEVATOR_ROOM, PANEL_TYPE)
	await _walk_to(panel.global_position)
	await _tap("interact")
	var select: FloorTravel.FloorSelectPanel = await _wait_panel()
	if select == null:
		push_error("game_day: the elevator panel did not open")
		return
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("game_day_02_elevator_panel")
	select.choose(select.index_of_floor(TARGET_FLOOR))
	await _pilot.seconds(0.55)
	await _pilot.shot("game_day_03_ride")
	await _wait_until(func() -> bool: return not _game.travel.is_busy(), APP_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	_log("arrived")
	await _pilot.shot("game_day_04_floor3")


func _work_at_desk() -> void:
	var desk: Interactable = _find_item(OFFICE, "desk")
	await _walk_to(desk.global_position)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("game_day_05_desk")
	await _tap("computer")
	var computer: StellarOS = await _wait_computer()
	if computer == null:
		push_error("game_day: the computer did not open at the desk")
		return
	await _pilot.seconds(1.5)
	await _pilot.shot("game_day_06_computer_boot")
	await _wait_until(func() -> bool: return computer.is_booted(), BOOT_TIMEOUT)
	await _seated_shot(computer)
	computer.open_app(StellarOS.APP_MAIL)
	await _wait_until(func() -> bool: return computer.get_open_app() is MailApp, APP_TIMEOUT)
	var mail: MailApp = computer.get_open_app() as MailApp
	for i: int in MAILS_TO_ANSWER:
		await mail.answer_current(mail.current_correct_reply())
		await _pilot.frames(SHORT_FRAMES)
	_log("answered %d mails" % MAILS_TO_ANSWER)
	await _pilot.shot("game_day_07_mail")
	await _tap("computer")
	await _pilot.frames(SHORT_FRAMES)
	await _try_time_skip()


## T en la mesa: el diálogo (se cancela) o la negativa que nombra a quien mira.
func _try_time_skip() -> void:
	_log("time skip at the desk: check=%s observer=%s" % [_game.time_skip.check(), _game.observer_name()])
	await _tap("time_skip")
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("game_day_07b_time_skip")
	var top: Control = _game.ui.get_top_modal()
	if top is DialogBox:
		(top as DialogBox).choose((top as DialogBox).get_option_count() - 1)
		await _pilot.frames(SHORT_FRAMES)


## QA: oculta un instante el escritorio (pantalla completa) para ver al jugador sentado a su mesa.
func _seated_shot(computer: StellarOS) -> void:
	var dim: CanvasItem = _game.ui.get_node_or_null(DIM_PATH) as CanvasItem
	computer.visible = false
	if dim != null:
		dim.visible = false
	await _pilot.frames(3)
	_log("seated=%s" % str(_game.bridges.is_seated()))
	await _pilot.shot("game_day_06b_seated")
	computer.visible = true
	if dim != null:
		dim.visible = true


func _go_to_pantry() -> void:
	await _walk_to(_game.streamer.get_spawn_point(PANTRY))
	await _pilot.frames(SHORT_FRAMES)
	_log("pantry")
	await _pilot.shot("game_day_08_pantry")


## Salto de QA hasta las 12:50 (el reloj pasa por cada hora: nadie se pierde nada) y espera real:
## a las 13:00 los compañeros se levantan y salen hacia los ascensores.
func _watch_lunch() -> void:
	var target: float = float(LUNCH_JUMP_HOUR * 60 + LUNCH_JUMP_MINUTE)
	GameClock.advance_minutes(target - GameClock.get_day_minutes())
	var wing: Rect2 = _game.streamer.get_room_rect_px(OFFICE)
	await _walk_to(wing.position + LUNCH_WATCH_CELLS * RoomBuilder.cell_px())
	var cam: Camera2D = _game.player.get_node_or_null("Camera") as Camera2D
	if cam != null:
		cam.zoom = Vector2(OVERVIEW_ZOOM, OVERVIEW_ZOOM)
	await _wait_until(func() -> bool: return GameClock.get_hour() >= LUNCH_HOUR, WALK_TIMEOUT)
	_log("lunch starts")
	await _pilot.seconds(1.0)
	await _pilot.shot("game_day_09_lunch_start")
	await _wait_until(func() -> bool: return GameClock.get_minute() >= LUNCH_WATCH_MINUTES, WALK_TIMEOUT)
	_log("lunch")
	await _pilot.shot("game_day_10_lunch_leaving")


# ─── Conducción ───────────────────────────────────────────────

## Camina por la ruta de FloorStreamer con el stick virtual; recalcula si se atasca.
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


func _wait_panel() -> FloorTravel.FloorSelectPanel:
	await _wait_until(func() -> bool: return _game.travel.get_panel() != null, APP_TIMEOUT)
	return _game.travel.get_panel()


func _wait_computer() -> StellarOS:
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is StellarOS, APP_TIMEOUT)
	return _game.ui.get_top_modal() as StellarOS


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
	print("[game_day] %s: floor=%d room=%s time=%s npcs=%d duty=%s" % [label, _game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string(), _game.npc_layer.get_nodes().size(),
			str(PlayerState.get_todays_duties().map(func(d: Dictionary) -> String: return "%s:%.2f" % [d["id"], float(d.get("progress", 0.0))]))])
