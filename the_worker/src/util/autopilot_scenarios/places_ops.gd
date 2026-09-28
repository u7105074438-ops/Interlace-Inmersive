# places_ops.gd (escenario) — El bucle del día con el módulo de lugares: colarse en los tornos en la hora punta, salir por recepción a la calle, comprar la cena en el supermercado, volver a casa en autobús, dormir (resumen y guardado) y a la mañana siguiente volver al trabajo en autobús y pasar los tornos.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y eventos de entrada reales).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_places places_ops
## Saltos de QA del reloj (advance_minutes, como el panel F1) para no esperar la jornada entera.
## Capturas: places_01_rush · 02_slipped · 03_exit_dialog · 04_street · 05_shop · 06_bought ·
## 07_bus · 08_home · 09_bed · 10_summary · 11_morning · 12_bus_work · 13_turnstiles; recorrido
## de QA (teletransporte): 14_clan · 15_gossip · 16_infirmary · 17_smokers.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const TURNSTILES := "turnstiles"
const RECEPTION := "main_reception"
const STREET := "street"
const SUPERMARKET := "supermarket"
const FLAT := "player_flat"
const LEAVE_MINUTE := 18 * 60 + 30
const EXIT_STEP_OUT := 1
const BUS_WORK := 0
const BUS_HOME := 1
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.2
const WALK_TIMEOUT := 40.0
const WAIT_TIMEOUT := 20.0
const SHORT_FRAMES := 8
const SUMMARY_SECONDS := 1.0
## Pasos hacia los tornos (sin entrar en su sensor): el primer foco carga los módulos del router.
const GATE_APPROACH_CELLS := 0.6

var _pilot: Autopilot = null
var _game: GameRoot = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("places_ops: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("places_ops: GameRoot did not start")
		return
	await _morning_rush()
	await _step_out()
	await _shopping()
	await _bus_home()
	await _sleep()
	await _back_to_work()
	await _tour()


# ─── Tramos ───────────────────────────────────────────────────

## 08:20, hora punta: colarse detrás de un compañero desde la cola de los tornos.
func _morning_rush() -> void:
	await _pilot.seconds(1.0)
	await _walk_to(_game.player.global_position + Vector2(0.0, RoomBuilder.cell_px() * GATE_APPROACH_CELLS))
	await _pilot.frames(SHORT_FRAMES)
	var queue: Interactable = _keeper_node(PlacesKeeper.QUEUE_ID)
	if queue == null:
		push_error("places_ops: no turnstile queue")
		return
	await _walk_to(queue.global_position)
	var logs: int = Security.get_access_log().size()
	_log("rush (cover at the gates: %s)" % str(_cover_names()))
	await _pilot.shot("places_01_rush")
	await _tap("interact")
	await _wait_until(func() -> bool: return not _game.player.is_input_locked(), WAIT_TIMEOUT)
	await _pilot.seconds(0.4)
	_log("slipped in: card records %d → %d" % [logs, Security.get_access_log().size()])
	await _pilot.shot("places_02_slipped")


## 18:30: por la salida de recepción a la calle («Salir a la calle»).
func _step_out() -> void:
	_jump_to(LEAVE_MINUTE)
	_game.travel.teleport_to_room(RECEPTION)
	await _pilot.frames(SHORT_FRAMES)
	var exit: Interactable = _find_item(RECEPTION, "exit")
	if exit == null:
		push_error("places_ops: reception has no exit")
		return
	await _walk_to(exit.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("places_03_exit_dialog")
	(_game.ui.get_top_modal() as DialogBox).choose(EXIT_STEP_OUT)
	await _wait_until(func() -> bool: return _on_floor(_exterior()) and not _game.travel.is_busy(), WAIT_TIMEOUT)
	await _pilot.seconds(0.5)
	_log("out on the street")
	await _pilot.shot("places_04_street")


## Andando por la calle hasta el supermercado: comprar la cena.
func _shopping() -> void:
	var counter: Interactable = _find_item(SUPERMARKET, "shop_counter")
	if counter == null:
		push_error("places_ops: no supermarket till")
		return
	await _walk_to(_game.streamer.get_spawn_point(SUPERMARKET))
	await _walk_to(counter.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("places_05_shop")
	var home: HomeCycle = _game.sim_nodes["HomeCycle"] as HomeCycle
	var goods: Array[Dictionary] = home.get_shop_items(SUPERMARKET)
	var dinner: int = 0
	for i: int in goods.size():
		dinner = i if str(goods[i]["item_id"]) == "food_dinner" else dinner
	var money: int = PlayerState.get_money()
	(_game.ui.get_top_modal() as DialogBox).choose(dinner)
	await _pilot.seconds(0.4)
	_log("bought dinner: money %d → %d, carrying=%s" % [money, PlayerState.get_money(), PlayerState.is_carrying("food_dinner")])
	await _pilot.shot("places_06_bought")


## La parada de la calle: autobús a casa.
func _bus_home() -> void:
	var stop: Interactable = _find_item(STREET, "bus_stop")
	if stop == null:
		push_error("places_ops: no bus stop on the street")
		return
	await _walk_to(_game.streamer.get_spawn_point(STREET))
	await _walk_to(stop.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("places_07_bus")
	(_game.ui.get_top_modal() as DialogBox).choose(BUS_HOME)
	await _wait_until(func() -> bool: return PlayerState.get_room() == FLAT and not _game.player.is_input_locked(), WAIT_TIMEOUT)
	await _pilot.seconds(0.6)
	_log("home by bus")
	await _pilot.shot("places_08_home")


## La cama del piso: confirmación, resumen de la jornada y guardado.
func _sleep() -> void:
	var bed: Interactable = _find_item(FLAT, "bed")
	if bed == null:
		push_error("places_ops: the flat has no bed")
		return
	_jump_to(22 * 60)
	await _walk_to(bed.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.frames(SHORT_FRAMES)
	await _pilot.shot("places_09_bed")
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DaySummary, WAIT_TIMEOUT)
	await _pilot.seconds(SUMMARY_SECONDS)
	_log("summary: saved=%s" % str(SaveSystem.run_exists()))
	await _pilot.shot("places_10_summary")
	_game.ui.close_modal()
	await _pilot.seconds(0.8)
	_log("morning")
	await _pilot.shot("places_11_morning")


## Por la mañana: de casa a la parada, autobús a la sede y a los tornos.
func _back_to_work() -> void:
	await _walk_to(_game.streamer.get_spawn_point(STREET))
	var stop: Interactable = _find_item(STREET, "bus_stop")
	if stop == null:
		return
	await _walk_to(stop.global_position)
	await _tap("interact")
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	(_game.ui.get_top_modal() as DialogBox).choose(BUS_WORK)
	await _wait_until(func() -> bool: return _on_floor(0) and not _game.player.is_input_locked(), WAIT_TIMEOUT)
	await _pilot.seconds(0.6)
	_log("at work by bus")
	await _pilot.shot("places_12_bus_work")
	var queue: Interactable = _keeper_node(PlacesKeeper.QUEUE_ID)
	if queue != null:
		await _walk_to(queue.global_position)
	await _pilot.seconds(0.4)
	_log("at the turnstiles")
	await _pilot.shot("places_13_turnstiles")


## Recorrido de QA por otros lugares del módulo (teletransporte, como el panel F1).
func _tour() -> void:
	_jump_to(13 * 60 + 20)
	await _open_at("cafeteria", "places_clan_table", "places_14_clan")
	if _game.ui.get_top_modal() is DialogBox:
		(_game.ui.get_top_modal() as DialogBox).choose(0)
		await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
		await _pilot.frames(SHORT_FRAMES)
		await _pilot.shot("places_15_gossip")
	await _close_all()
	await _open_at("infirmary", "", "places_16_infirmary", "bed")
	await _close_all()
	_jump_to(14 * 60 + 10)
	await _open_at(STREET, "", "places_17_smokers", "smoking_spot")
	await _close_all()


## Va a la sala, se planta ante el interactivo (del keeper por id o de la sala por tipo) y pulsa E.
func _open_at(room_id: String, keeper_id: String, shot_name: String, interact_type: String = "") -> void:
	_game.travel.teleport_to_room(room_id)
	await _pilot.frames(SHORT_FRAMES)
	var item: Interactable = _keeper_node(keeper_id) if not keeper_id.is_empty() else _find_item(room_id, interact_type)
	if item == null:
		push_error("places_ops: nothing to use in %s" % room_id)
		return
	await _walk_to(item.global_position)
	await _tap("interact")
	await _pilot.seconds(0.5)
	_log("tour: %s" % shot_name)
	await _pilot.shot(shot_name)


func _close_all() -> void:
	while _game.ui.has_modal():
		_game.ui.close_modal()
	await _pilot.frames(SHORT_FRAMES)


# ─── Conducción ───────────────────────────────────────────────

func _exterior() -> int:
	return Database.get_balance_int("mundo.planta_exterior")


func _on_floor(floor_number: int) -> bool:
	return _game.streamer.get_current_floor() == floor_number


func _jump_to(day_minute: int) -> void:
	var left: float = float(day_minute) - GameClock.get_day_minutes()
	if left > 0.0:
		GameClock.advance_minutes(left)


func _keeper_node(interact_id: String) -> Interactable:
	for node: Node in get_tree().get_nodes_in_group(PlacesKeeper.NODES_GROUP):
		if (node as Interactable).interact_id == interact_id:
			return node as Interactable
	return null


func _cover_names() -> Array[String]:
	var out: Array[String] = []
	for door: Door in _game.streamer.get_doors():
		var cover: String = PlacesGate.cover_npc(_game, door) if door.kind == Door.KIND_TURNSTILE else ""
		if not cover.is_empty():
			out.append(PlacesKit.npc_name(cover))
	return out


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
	print("[places_ops] %s: floor=%d room=%s time=%s day=%d money=%d" % [label, _game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string(), GameClock.get_day(), PlayerState.get_money()])
