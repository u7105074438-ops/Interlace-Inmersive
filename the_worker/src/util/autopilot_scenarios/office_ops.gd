# office_ops.gd (escenario) — Un día de oficina con el módulo office.gd: la mesa propia (llaves y estampa), el cajón de un compañero, material de la fotocopiadora, café, la nevera del office, el correo interno (reventa), escuchas y máquina, y los expedientes de RR. HH.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual, E con eventos de entrada reales y contesta los diálogos como lo haría el jugador).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_office office_ops
## Saltos de QA entre plantas con FloorTravel.teleport_to_room (como el F1). Capturas:
## office_01_desk_menu · 02_tools · 03_drawer_watch (si alguien mira) · 04_drawer_act ·
## 05_drawer_loot · 06_supplies · 07_copier · 08_coffee · 09_fridge · 09b_supply_room · 10_mail_menu ·
## 11_mail_sold ·
## 12_eavesdrop · 13_vending · 14_hr_files · 15_notebook.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const OFFICE := "wing_3b"
const DESK_ID := "player_desk"
const DRAWER_ID := "nate_drawer"
const COPYROOM := "p3_copyroom"
const SHELF_ID := "p3_copy_paper"
const COPIER_ID := "p3_copier_tray"
const PANTRY := "p3_pantry"
const COFFEE_ID := "pantry_coffee"
const FRIDGE_ID := "pantry_fridge"
const MAIL_ROOM := "mail_office"
const MAIL_ID := "mail_sorting_table"
const FOOSBALL := "foosball_room"
const HUDDLE_ID := "foosball_huddle"
const VENDING_ID := "foosball_vending"
const HR_ROOM := "hr_office"
const HR_FILES_ID := "hr_personnel_files"
const TAKE_TOOLS := 1
const TAKE_ALL := 0
const SELL := 1
const PROCEED := 1
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 25.0
const WAIT_TIMEOUT := 8.0
const SHORT_FRAMES := 8
const ACT_PEEK := 0.8
const REACH_CELLS := 1.2
const MAX_SIDESTEPS := 4
const SIDESTEP_SECONDS := 0.35
const SUPPLY_ROOM := "office_supplies"
const SUPPLY_SHELF_ID := "supplies_shelf_a"

var _pilot: Autopilot = null
var _game: GameRoot = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("office_ops: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("office_ops: GameRoot did not start")
		return
	await _desk()
	await _drawer()
	await _copy_room()
	await _pantry()
	await _supply_room()
	await _mail()
	await _break_room()
	await _hr_files()
	_log("done: money=%d items=%s" % [PlayerState.get_money(), _items()])


# ─── Tramos ───────────────────────────────────────────────────

func _desk() -> void:
	_game.travel.teleport_to_room(OFFICE)
	await _pilot.frames(SHORT_FRAMES)
	if not await _use(OFFICE, DESK_ID):
		return
	await _wait_dialog()
	await _pilot.shot("office_01_desk_menu")
	await _answer(TAKE_TOOLS)
	await _pilot.seconds(0.3)
	_log("tools taken: keys=%s stamp=%s" % [PlayerState.is_carrying("keys_basic"), PlayerState.is_carrying("stamp")])
	await _pilot.shot("office_02_tools")


func _drawer() -> void:
	if not await _use(OFFICE, DRAWER_ID):
		return
	await _pilot.frames(SHORT_FRAMES)
	if _game.ui.get_top_modal() is DialogBox:
		_log("someone is watching: %s" % _game.observer_name())
		await _pilot.shot("office_03_drawer_watch")
		await _answer(PROCEED)
	await _pilot.seconds(ACT_PEEK)
	_log("act: %s" % _game.player.current_act())
	await _pilot.shot("office_04_drawer_act")
	await _wait_dialog()
	await _pilot.shot("office_05_drawer_loot")
	await _answer(TAKE_ALL)
	await _pilot.seconds(0.3)
	_log("after drawer: money=%d items=%s" % [PlayerState.get_money(), _items()])


func _copy_room() -> void:
	if not await _use(COPYROOM, SHELF_ID):
		return
	await _proceed_if_watched()
	await _wait_until(func() -> bool: return _game.player.current_act().is_empty(), WAIT_TIMEOUT)
	await _pilot.seconds(0.2)
	_log("supplies: %s" % _items())
	await _pilot.shot("office_06_supplies")
	if await _use(COPYROOM, COPIER_ID):
		await _wait_dialog()
		await _pilot.shot("office_07_copier")
		await _answer(0)


func _pantry() -> void:
	if await _use(PANTRY, COFFEE_ID):
		await _pilot.seconds(0.4)
		await _pilot.shot("office_08_coffee")
	if await _use(PANTRY, FRIDGE_ID):
		await _proceed_if_watched()
		await _wait_until(func() -> bool: return _game.player.current_act().is_empty(), WAIT_TIMEOUT)
		await _pilot.seconds(0.3)
		await _pilot.shot("office_09_fridge")


## Almacén de material de la 4 (N2: con las llaves del escritorio por la cerradura antigua; aquí,
## salto de QA): la parte de hoy, ~35 € de reventa.
func _supply_room() -> void:
	_game.travel.teleport_to_room(SUPPLY_ROOM)
	await _pilot.frames(SHORT_FRAMES)
	if not await _use(SUPPLY_ROOM, SUPPLY_SHELF_ID):
		return
	await _proceed_if_watched()
	await _wait_until(func() -> bool: return _game.player.current_act().is_empty(), WAIT_TIMEOUT)
	await _pilot.seconds(0.3)
	await _pilot.shot("office_09b_supply_room")


func _mail() -> void:
	_game.travel.teleport_to_room(MAIL_ROOM)
	await _pilot.frames(SHORT_FRAMES)
	if not await _use(MAIL_ROOM, MAIL_ID):
		return
	await _wait_dialog()
	await _pilot.shot("office_10_mail_menu")
	var money: int = PlayerState.get_money()
	await _answer(SELL)
	await _pilot.seconds(0.4)
	_log("sold: +%d €" % (PlayerState.get_money() - money))
	await _pilot.shot("office_11_mail_sold")


func _break_room() -> void:
	_game.travel.teleport_to_room(FOOSBALL)
	await _pilot.frames(SHORT_FRAMES)
	if await _use(FOOSBALL, HUDDLE_ID):
		await _pilot.seconds(0.4)
		await _pilot.shot("office_12_eavesdrop")
		if _game.ui.get_top_modal() is DialogBox:
			await _answer(0)
	if await _use(FOOSBALL, VENDING_ID):
		await _pilot.seconds(0.4)
		await _pilot.shot("office_13_vending")


func _hr_files() -> void:
	_game.travel.teleport_to_room(HR_ROOM)
	await _pilot.frames(SHORT_FRAMES)
	if not await _use(HR_ROOM, HR_FILES_ID):
		return
	await _proceed_if_watched()
	await _wait_dialog()
	await _pilot.shot("office_14_hr_files")
	await _answer(0)
	_game.ui.open_computer({"app": "notebook", "instant": true})
	await _pilot.seconds(1.5)
	await _pilot.shot("office_15_notebook")


# ─── Conducción ───────────────────────────────────────────────

## Camina hasta el interactivo y pulsa E (true si lo encontró y el jugador lo enfoca).
func _use(room_id: String, interact_id: String) -> bool:
	var item: Interactable = _find(room_id, interact_id)
	if item == null:
		push_error("office_ops: %s not found in %s" % [interact_id, room_id])
		return false
	await _walk_to(_stand_point(item))
	await _pilot.frames(2)
	_log("E on %s (focus=%s, %.0f px away, item %s player %s)" % [interact_id, str(_game.player.get_focused_interactable()),
			_game.player.global_position.distance_to(item.global_position), str(item.global_position), str(_game.player.global_position)])
	await _tap("interact")
	await _pilot.frames(2)
	return true


## Dónde ponerse: una celda transitable de la misma sala junto al punto de uso desde la que ese
## interactivo sea el más cercano (el punto de uso puede quedar pegado a un mueble o a la pared).
func _stand_point(item: Interactable) -> Vector2:
	var cell: float = RoomBuilder.cell_px()
	var fallback: Vector2 = item.global_position
	for offset: Vector2 in [Vector2.ZERO, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2(1, 1), Vector2(-1, 1), Vector2.UP]:
		var w: Vector2 = _game.streamer.nearest_walkable_point(item.global_position + offset * cell)
		if w == Vector2.INF or _game.streamer.get_room_at(w) != item.room_id \
				or w.distance_to(item.global_position) > cell * REACH_CELLS:
			continue
		if _nearest_item(w, item.room_id) == item:
			return w
		fallback = w if fallback == item.global_position else fallback
	return fallback


func _nearest_item(at: Vector2, room_id: String) -> Interactable:
	var best: Interactable = null
	for other: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if best == null or other.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = other
	return best


func _proceed_if_watched() -> void:
	await _pilot.frames(SHORT_FRAMES)
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	if box != null and box.get_option_count() > 1 \
			and box.get_option_text(PROCEED).ends_with(TranslationServer.translate("OFFICE_WATCHED_PROCEED")):
		_log("watched by %s — doing it anyway" % _game.observer_name())
		box.choose(PROCEED)


func _wait_dialog() -> void:
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)


func _answer(index: int) -> void:
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	if box != null:
		box.choose(index)
	await _pilot.frames(SHORT_FRAMES)


func _walk_to(target: Vector2) -> void:
	var player: Player = _game.player
	var path: PackedVector2Array = _game.streamer.find_path_to_point(player.global_position, target)
	path.append(target)
	var index: int = 0
	var elapsed: float = 0.0
	var still: float = 0.0
	var last: Vector2 = player.global_position
	var sidesteps: int = 0
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
			still = 0.0
			sidesteps += 1
			if sidesteps > MAX_SIDESTEPS:
				index += 1
				sidesteps = 0
			else:
				await _sidestep((path[index] - player.global_position).normalized(), sidesteps)
	player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.frames(2)


## Rodea a quien bloquea el paso (un compañero parado entre las mesas): un paso de lado.
func _sidestep(heading: Vector2, attempt: int) -> void:
	var side: Vector2 = heading.orthogonal() * (1.0 if attempt % 2 == 1 else -1.0)
	_game.player.set_virtual_input(side, false)
	await _pilot.seconds(SIDESTEP_SECONDS)


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


func _find(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


func _items() -> String:
	var names: PackedStringArray = []
	for item: ItemData in PlayerState.get_inventory():
		names.append("%s×%d" % [item.id, item.stack])
	return ", ".join(names)


func _log(label: String) -> void:
	print("[office_ops] %s: room=%s time=%s" % [label, PlayerState.get_room(), GameClock.get_time_string()])
