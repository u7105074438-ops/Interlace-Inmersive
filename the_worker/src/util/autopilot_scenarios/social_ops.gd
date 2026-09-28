# social_ops.gd (escenario) — El módulo social jugado de verdad: acercarse a un compañero y pulsar E, charlar, preguntar por la agenda, plantar un rumor en Debbie, cederle el mérito a George, el sobre para que Tom mire hacia otro lado, el uniforme de Frank Rudd, «Eliminar» en rojo con testigos y una eliminación sin testigos (fundido a negro), y el trato en la cúspide.
# PROPIETARIO DE: nada (conduce al jugador con el stick virtual y teclas reales: E, números, Esc; saltos de QA como el panel F1).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_social social_ops
## Saltos de QA (como el panel F1): teletransporte a la sala, forzar el rango para el trato de la
## cúspide, dinero para el sobre y, para la eliminación, apartar a los demás de la planta si nadie
## está solo (la captura documenta la escena, no la búsqueda de una víctima).
## Capturas: social_01_menu · 02_chat · 03_directions · 04_rumour_menu · 05_rumour_done ·
## 06_credit_confirm · 07_credit_done · 08_tom_menu · 09_tom_bribe · 10_tom_result · 11_frank_menu ·
## 12_frank_favours · 13_frank_uniform · 14_eliminate_red · 15_eliminate_confirm · 16_eliminate_black ·
## 17_eliminate_after · 18_top_flattery.

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const TOM := "npc_tom_iverson"
const FRANK := "npc_frank_rudd"
const WING := "wing_3b"
const ARRIVE_PX := 10.0
const STUCK_SECONDS := 1.0
const WALK_TIMEOUT := 20.0
const WAIT_TIMEOUT := 8.0
const SHORT_FRAMES := 8
const MAX_SIDESTEPS := 4
const SIDESTEP_SECONDS := 0.3
const QA_MONEY := 2000
## Distancia (celdas) a la que el jugador se planta junto al personaje para que su «Hablar» tenga el foco.
const REACH_CELLS := 1.05
const TOP_TIER := 8
const FAR_AWAY := Vector2(-100000, -100000)
## 09:30: la plantilla ya está en sus puestos (a las 08:20 aún llega).
const WORK_MINUTE := 570
## Búsqueda de _meet: hasta las 18:00, de 10 en 10 minutos.
const END_MINUTE := 1080
const STEP_MINUTES := 10

var _pilot: Autopilot = null
var _game: GameRoot = null
## Nodos apartados para la escena de la eliminación → posición original (se devuelven después).
var _moved: Dictionary = {}


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("social_ops: the game scene does not exist")
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("social_ops: GameRoot did not start")
		return
	PlayerState.add_money(QA_MONEY, "qa")
	GameClock.advance_minutes(maxf(float(WORK_MINUTE) - GameClock.get_day_minutes(), 0.0))
	await _debbie()
	await _george()
	await _tom()
	await _frank()
	await _witnesses()
	await _elimination()
	await _top()
	_log("done: money=%d" % PlayerState.get_money())


# ─── Tramos ───────────────────────────────────────────────────

func _debbie() -> void:
	await _go(WING)
	var menu: NPCInteractionMenu = await _talk_to(DEBBIE)
	if menu == null:
		return
	await _pilot.shot("social_01_menu")
	await _key(KEY_1)
	await _pilot.seconds(0.4)
	_log("chat reply: %s" % menu.get_reply_text())
	await _pilot.shot("social_02_chat")
	await _key(KEY_2)
	await _key(KEY_1)
	await _pilot.seconds(0.3)
	await _pilot.shot("social_03_directions")
	await _key(KEY_3)
	await _pilot.seconds(0.3)
	await _pilot.shot("social_04_rumour_menu")
	await _key(KEY_2)
	await _pilot.seconds(0.5)
	_log("rumours planted: %d" % SocialGraph.get_injected_rumours().size())
	await _pilot.shot("social_05_rumour_done")
	await _key(KEY_ESCAPE)


func _george() -> void:
	var menu: NPCInteractionMenu = await _talk_to(GEORGE)
	if menu == null or not menu.press_option(SocialRules.OPT_CREDIT):
		return
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("social_06_credit_confirm")
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	await _pilot.seconds(0.5)
	_log("George debt %d" % NPCDirector.get_debt(GEORGE))
	await _pilot.shot("social_07_credit_done")
	await _key(KEY_ESCAPE)


func _tom() -> void:
	await _go(NPCDirector.get_npc(TOM).home_room)
	var menu: NPCInteractionMenu = await _talk_to(TOM)
	if menu == null:
		return
	await _pilot.shot("social_08_tom_menu")
	if not menu.press_option(SocialRules.OPT_LOOK):
		return
	await _pilot.seconds(0.3)
	var panel: BribePanel = menu.get_bribe_panel()
	if panel == null:
		return
	panel.set_amount(Bribery.fair_price(NPCDirector.get_npc(TOM), "look_away_once"))
	await _pilot.shot("social_09_tom_bribe")
	panel.request_offer()
	panel.confirm_offer()
	await _pilot.seconds(0.6)
	_log("Tom: %s" % str(panel.get_last_result().get("outcome", "")))
	await _pilot.shot("social_10_tom_result")
	await _key(KEY_ESCAPE)
	_log("after esc 1: menu=%s page=%s modal=%s" % [NPCInteractionMenu.find(get_tree()) != null, menu.get_page() if is_instance_valid(menu) else "-", str(_game.ui.get_top_modal())])
	await _key(KEY_ESCAPE)
	_log("after esc 2: menu=%s modal=%s" % [NPCInteractionMenu.find(get_tree()) != null, str(_game.ui.get_top_modal())])


func _frank() -> void:
	if not await _meet(FRANK):
		return
	var menu: NPCInteractionMenu = await _talk_to(FRANK)
	if menu == null:
		return
	await _pilot.shot("social_11_frank_menu")
	if not menu.press_option(SocialRules.OPT_FAVOUR):
		return
	await _pilot.seconds(0.3)
	await _pilot.shot("social_12_frank_favours")
	menu.press_choice("lend")
	await _pilot.seconds(0.6)
	_log("disguise: %s" % PlayerState.get_disguise())
	await _pilot.shot("social_13_frank_uniform")
	await _key(KEY_ESCAPE)


func _witnesses() -> void:
	await _go(WING)
	var menu: NPCInteractionMenu = await _talk_to(_busiest_npc())
	if menu == null:
		return
	await _pilot.seconds(0.4)
	_log("witnesses: %s" % str(menu.get_exposure().get("witnesses", [])))
	await _pilot.shot("social_14_eliminate_red")
	await _key(KEY_ESCAPE)


func _elimination() -> void:
	var victim: String = _lonely_npc()
	var menu: NPCInteractionMenu = await _talk_to(victim)
	if menu == null:
		return
	_clear_witnesses(victim)
	await _pilot.seconds(0.5)
	if not menu.press_option(SocialRules.OPT_ELIMINATE):
		_log("eliminate still closed: %s" % str(menu.get_exposure()))
		return
	await _wait_until(func() -> bool: return _game.ui.get_top_modal() is DialogBox, WAIT_TIMEOUT)
	await _pilot.shot("social_15_eliminate_confirm")
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	await _wait_until(func() -> bool: return not NPCDirector.is_alive(victim), WAIT_TIMEOUT)
	await _pilot.shot("social_16_eliminate_black")
	await _wait_until(func() -> bool: return NPCInteractionMenu.find(get_tree()) == null, WAIT_TIMEOUT)
	await _pilot.seconds(0.4)
	_log("body: %s" % str(NPCDirector.get_body_info(victim)))
	await _pilot.shot("social_17_eliminate_after")
	for node: Variant in _moved:
		if is_instance_valid(node):
			(node as NPCNode).global_position = _moved[node]
	_moved.clear()
	get_tree().call_group(SecurityCamera.GROUP, "set_active", true)


func _top() -> void:
	var occupations: Array[OccupationData] = Database.get_occupations_by_tier(TOP_TIER)
	if occupations.is_empty():
		return
	PlayerState.set_occupation(occupations[0].id, "qa")
	await _pilot.seconds(0.5)
	while _game.ui.has_modal():
		_game.ui.close_modal()
		await _pilot.frames(2)
	await _go(WING)
	var menu: NPCInteractionMenu = await _talk_to(_busiest_npc())
	if menu == null:
		return
	await _key(KEY_2)
	await _key(KEY_1)
	await _pilot.seconds(0.4)
	_log("top reply: %s" % menu.get_reply_text())
	await _pilot.shot("social_18_top_flattery")
	await _key(KEY_ESCAPE)


# ─── Personajes ───────────────────────────────────────────────

## QA: adelanta el reloj hasta que el personaje esté en una sala a la que el jugador puede entrar
## (Frank vive en el taller de S1, vetado a un R1: se le busca en su pausa) y va allí.
func _meet(npc_id: String) -> bool:
	var now: int = int(GameClock.get_day_minutes())
	for minute: int in range(now, END_MINUTE, STEP_MINUTES):
		var room: String = NPCDirector.get_location_at(npc_id, minute / 60, minute % 60)
		if room.is_empty() or BeliefNet.is_room_forbidden_for_player(DatabaseSystem.get_room_base_id(room)):
			continue
		GameClock.advance_minutes(float(minute - now))
		await _go(DatabaseSystem.get_room_base_id(room))
		_log("meeting %s in %s" % [npc_id, room])
		return true
	_log("%s never comes to a public room today" % npc_id)
	return false


func _busiest_npc() -> String:
	var nodes: Array[NPCNode] = _game.npc_layer.get_nodes()
	var best: String = ""
	var best_count: int = -1
	for node: NPCNode in nodes:
		var here: String = _game.streamer.get_room_at(node.global_position)
		var count: int = nodes.filter(func(o: NPCNode) -> bool: return _game.streamer.get_room_at(o.global_position) == here).size()
		if count > best_count:
			best = node.npc_id
			best_count = count
	return best


func _lonely_npc() -> String:
	var nodes: Array[NPCNode] = _game.npc_layer.get_nodes()
	for node: NPCNode in nodes:
		var here: String = _game.streamer.get_room_at(node.global_position)
		if nodes.filter(func(o: NPCNode) -> bool: return _game.streamer.get_room_at(o.global_position) == here).size() == 1:
			return node.npc_id
	return nodes[0].npc_id if not nodes.is_empty() else ""


## QA: si alguien más ve la escena, se le aparta de la planta (la captura documenta la eliminación).
func _clear_witnesses(victim: String) -> void:
	var menu: NPCInteractionMenu = NPCInteractionMenu.find(get_tree())
	if menu == null:
		return
	var env: Dictionary = SocialWorld.exposure(_game.player, victim)
	if not (env["witnesses"] as Array).is_empty():
		_game.npc_layer.process_mode = Node.PROCESS_MODE_DISABLED
		for node: NPCNode in _game.npc_layer.get_nodes():
			if node.npc_id != victim:
				_moved[node] = node.global_position
				node.global_position = FAR_AWAY
	if not (env["cameras"] as Array).is_empty():
		get_tree().call_group(SecurityCamera.GROUP, "set_active", false)
	_log("cleared for the scene: %s" % str(env))


# ─── Conducción ───────────────────────────────────────────────

func _go(room_id: String) -> void:
	_game.npc_layer.process_mode = Node.PROCESS_MODE_INHERIT
	_game.travel.teleport_to_room(room_id)
	await _pilot.frames(SHORT_FRAMES)
	_game.npc_layer.sync_now()
	await _pilot.seconds(0.5)


## Camina hasta el personaje y pulsa E (si el foco es otro objeto, habla con él por el router).
func _talk_to(npc_id: String) -> NPCInteractionMenu:
	var node: NPCNode = _game.npc_layer.get_node_for(npc_id)
	if node == null:
		_log("%s is not on this floor" % npc_id)
		return null
	for attempt: int in 3:
		if not is_instance_valid(node) or _game.player.get_focused_interactable() == node.interactable:
			break
		await _walk_to(_stand_point(node))
	await _pilot.frames(2)
	if not is_instance_valid(node):
		return null
	_log("distance to %s: %.0f px" % [npc_id, _game.player.global_position.distance_to(node.global_position)])
	var focus: Node = _game.player.get_focused_interactable()
	if focus == node.interactable:
		await _tap("interact")
	else:
		_log("focus was %s; talking through the router" % str(focus))
		InteractionRouter.interact(node.interactable, _game.player)
	await _pilot.frames(SHORT_FRAMES)
	var menu: NPCInteractionMenu = NPCInteractionMenu.find(get_tree())
	_log("menu for %s: %s (locked=%s act=%s modal=%s active=%s)" % [npc_id, menu != null, _game.player.is_input_locked(),
			_game.player.current_act(), str(_game.ui.get_top_modal()), NPCDirector.is_active(npc_id)])
	return menu


func _stand_point(node: NPCNode) -> Vector2:
	var cell: float = RoomBuilder.cell_px()
	var best: Vector2 = node.global_position
	var best_d: float = INF
	for dir: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2(1, 1), Vector2(-1, 1)]:
		var w: Vector2 = _game.streamer.nearest_walkable_point(node.global_position + dir * cell)
		if not w.is_finite() or w.distance_to(node.global_position) > cell * REACH_CELLS:
			continue
		var d: float = w.distance_to(_game.player.global_position)
		if d < best_d:
			best = w
			best_d = d
	return best


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
			index += 1 if sidesteps > MAX_SIDESTEPS else 0
			await _sidestep((path[mini(index, path.size() - 1)] - player.global_position).normalized(), sidesteps)
	player.set_virtual_input(Vector2.ZERO, false)
	await _pilot.frames(2)


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


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _pilot.frames(3)


func _wait_until(condition: Callable, timeout: float) -> void:
	var left: float = timeout
	while left > 0.0 and not bool(condition.call()):
		await get_tree().process_frame
		left -= get_process_delta_time()


func _log(label: String) -> void:
	print("[social_ops] %s: room=%s time=%s" % [label, PlayerState.get_room(), GameClock.get_time_string()])
