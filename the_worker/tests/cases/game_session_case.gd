# game_session_case.gd — Cuerpo de test_game_session: partida nueva en los tornos, reloj en marcha, viajes entre plantas, halo de zona, salto temporal, flujo de ascenso, jornada con sueño y guardado, continuar, fin de partida → epílogo → menú, y despacho del InteractionRouter.
# PROPIETARIO DE: nada (monta y libera la escena de juego; su carpeta de guardado se borra al final).
# ESCUCHA: nada.
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const FAKE_MODULE := "res://tests/cases/game_session_fake_module.gd"
const STORAGE_FORMAT := "user://test_game_session_%d"
const RUN_SEED := 4242
const PLAYER_NAME := "Tess Tester"
const START_ROOM := "turnstiles"
const ELEVATOR_ROOM := "main_elevator_1@0"
const SERVICE_ROOM := "service_stairs@3"
const OFFICE := "wing_3b"
const RESTRICTED_ROOM := "monitor_room"
const CORRIDOR := "corridors_low@3"
const FLAT := "player_flat"
const EXIT_ROOM := "main_reception"
const CAUSE := "starvation"
const SLEEP_HOUR := 21
const FRAMES_SETTLE := 3
const REAL_WAIT := 0.3
const MAX_SCENE_WAITS := 120

var _dir: String = ""
var _game: GameRoot = null


func run_case() -> void:
	allowed_engine_errors = 0
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	check(new_run(RUN_SEED), "Database loaded")
	_test_router_contract()
	await _test_new_run()
	await _test_router_in_world()
	await _test_travel()
	await _test_travel_rules()
	await _test_zone_halo()
	await _test_time_skip()
	await _test_promotion_flow()
	await _test_day_and_sleep()
	await _test_continue()
	await _test_game_over()
	_cleanup()


# ─── Router ───────────────────────────────────────────────────

func _test_router_contract() -> void:
	InteractionRouter.reset()
	var map: Dictionary = InteractionRouter.handled_types_map()
	check_eq(str(map.get("elevator_panel", "")), "res://src/world/floor_travel.gd", "router: elevator panels go to FloorTravel")
	check_eq(str(map.get("roof_ledge", "")), "res://src/world/floor_travel.gd", "router: roof ledges go to FloorTravel")
	check_eq(str(map.get("dropped_item", "")), "res://src/world/world_bridges.gd", "router: dropped items go to WorldBridges")
	check(InteractionRouter.module_for("no_such_type_qa").resource_path.ends_with("_default.gd"), "router: unknown types fall back to _default.gd")
	var fake: Script = load(FAKE_MODULE) as Script
	check(InteractionRouter.register_module(fake), "router: a contract-abiding module registers")
	check(not InteractionRouter.register_module(load("res://src/world/game_session.gd") as Script), "router: a non-module is refused")
	var item: Interactable = _fake_item({})
	InteractionRouter.interact(item, self)
	var calls: Array = fake.get("calls")
	check_eq(calls.size(), 1, "router: interact() dispatches to the module of its type")
	var ctx: Dictionary = calls[0]["ctx"] if not calls.is_empty() else {}
	check(ctx.has("game_root") and ctx.has("ui_root") and ctx.has("streamer") and ctx.has("floor"), "router: ctx carries game_root, ui_root, streamer, floor")
	check_eq(str(ctx.get("room_id", "")), "qa_room", "router: ctx.room_id is the interactable's room")
	check_eq(InteractionRouter.prompt_key_for(item), "UI_INTERACT_GENERIC", "router: optional prompt_key() is honoured")
	check(InteractionRouter.is_available_for(item, self), "router: optional is_available() true")
	check(not InteractionRouter.is_available_for(_fake_item({"blocked": true}), self), "router: optional is_available() false blocks focus")


func _fake_item(data: Dictionary) -> Interactable:
	var item: Interactable = Interactable.new()
	item.setup("qa_fake", "qa_fake_type", "qa_room", data, RoomBuilder.cell_px(), Vector2.ZERO)
	item.queue_free()
	return item


# ─── Partida nueva ────────────────────────────────────────────

func _test_new_run() -> void:
	_game = await _spawn_game({"mode": "new", "seed": RUN_SEED, "player_name": PLAYER_NAME, "difficulty": "estandar"})
	check_eq(_game.get_mode(), "new", "new run: mode new")
	check_eq(GameClock.get_run_seed(), RUN_SEED, "new run: the requested seed is the run seed")
	check_eq(PlayerState.get_player_name(), PLAYER_NAME, "new run: the player's name comes from the request")
	check_eq(_game.streamer.get_current_floor(), 0, "new run: starts on the ground floor")
	check_eq(PlayerState.get_room(), START_ROOM, "new run: the player stands at the turnstiles")
	check_eq(GameClock.get_day(), 1, "new run: day 1")
	check_eq(GameClock.get_hour(), 8, "new run: 08:xx")
	check_near(GameClock.get_day_minutes(), 8 * 60.0 + Database.get_balance_float("partida.minutos_inicio"), 1.0,
			"new run: the day starts partida.minutos_inicio after 08:00 (people already arriving)")
	check(not GameClock.is_paused(), "new run: run_started resumed the clock")
	var before: float = GameClock.get_total_minutes()
	await get_tree().create_timer(REAL_WAIT).timeout
	check(GameClock.get_total_minutes() > before, "new run: the clock runs")
	check(_game.get_tree().get_first_node_in_group(DutySystem.GROUP) != null, "new run: DutySystem is in the scene")
	check(_game.get_tree().get_first_node_in_group(HomeCycle.GROUP) != null, "new run: HomeCycle is in the scene")
	check(InventoryUI.find_drop_handler(get_tree()) != null, "new run: an item_drop_handlers node exists")
	check_eq(_game.player.get_node_or_null("Camera") != null, true, "new run: the player carries its camera")


## Instancia game.tscn como escena actual y espera a que el jugador pise su sala.
func _spawn_game(overrides: Dictionary) -> GameRoot:
	var game: GameRoot = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	game.request_overrides = overrides
	game.epilogue_delay_override = 0.0
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.travel.instant = true
	game.time_skip.instant = true
	game.promotion.instant = true
	await _settle()
	return game


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _test_router_in_world() -> void:
	var nodes: Array[NPCNode] = _game.npc_layer.get_nodes()
	var tagged: int = 0
	for node: NPCNode in nodes:
		if node.interactable != null and node.interactable.interact_type == "npc" \
				and str(node.interactable.data.get("npc_id", "")) == node.npc_id:
			tagged += 1
	check_eq(tagged, nodes.size(), "npc nodes carry an 'npc' Interactable with {npc_id} (%d nodes)" % nodes.size())
	var item: Interactable = _game.streamer.get_interactables_in_room(START_ROOM)[0]
	var ctx: Dictionary = InteractionRouter.build_context(item, _game.player)
	check(ctx["game_root"] == _game and ctx["ui_root"] == _game.ui and ctx["streamer"] == _game.streamer, "router ctx in game: real game_root, ui_root, streamer")
	check_eq(int(ctx["floor"]), 0, "router ctx in game: current floor")


# ─── Viajes ───────────────────────────────────────────────────

func _test_travel() -> void:
	var panel: Interactable = _find_item(ELEVATOR_ROOM, "elevator_panel")
	check(panel != null, "travel: elevator panel on PB")
	var dests: Array[Dictionary] = _game.travel.destinations_for(panel)
	var to3: Dictionary = _dest_for(dests, 3)
	var locked: Dictionary = _dest_for(dests, 16)
	check(bool(to3.get("allowed", false)), "travel: the card opens floor 3 for R1")
	check(not bool(locked.get("allowed", true)) and int(locked.get("clearance", 0)) > PlayerState.get_clearance(), "travel: floor 16 is locked with its clearance")
	var log_before: int = Security.get_access_log().size()
	var minutes: float = GameClock.get_total_minutes()
	await _game.travel.travel_to(panel, to3)
	await _settle()
	check_eq(_game.streamer.get_current_floor(), 3, "travel: the elevator reached floor 3")
	check_eq(PlayerState.get_room(), "main_elevator_1@3", "travel: arrival in the elevator cabin of floor 3")
	check_eq(Security.get_access_log().size(), log_before + 1, "travel: the elevator card reader logged the trip")
	check(GameClock.get_total_minutes() - minutes >= FloorTravel.travel_minutes("elevator", 3) - 0.01, "travel: the ride costs game minutes")
	panel = _find_item("main_elevator_1@3", "elevator_panel")
	check(panel != null, "travel: the floor-3 elevator panel exists after the ride")
	await _game.travel.travel_to(panel, _dest_for(_game.travel.destinations_for(panel), 16))
	check_eq(_game.streamer.get_current_floor(), 3, "travel: a locked floor is refused")
	check(not _game.travel.is_busy(), "travel: not busy after a refused trip")
	await _test_service_stairs()
	await _test_exit()


func _test_service_stairs() -> void:
	var door: Interactable = _find_item(SERVICE_ROOM, "service_stairs_door")
	check(door != null, "travel: service stairs door on floor 3")
	check(_game.travel.refusal_for(door).is_empty(), "travel: nothing bulky, the stairs are usable")
	var log_before: int = Security.get_access_log().size()
	await _game.travel.travel_to(door, _dest_for(_game.travel.destinations_for(door), 1))
	await _settle()
	check_eq(_game.streamer.get_current_floor(), 1, "travel: service stairs to floor 1")
	check_eq(Security.get_access_log().size(), log_before, "travel: service stairs leave no card record")


func _test_exit() -> void:
	check(_game.travel.teleport_to_room(EXIT_ROOM), "travel: teleport to the reception")
	await _settle()
	var door: Interactable = _find_item(EXIT_ROOM, "exit")
	check(door != null, "travel: the reception has an exit")
	var dests: Array[Dictionary] = _game.travel.destinations_for(door)
	check_eq(dests.size(), 1, "travel: an exit has a single destination")
	await _game.travel.travel_to(door, dests[0])
	await _settle()
	check_eq(_game.streamer.get_current_floor(), Database.get_balance_int("mundo.planta_exterior"), "travel: the exit leads to the street floor")
	check_eq(PlayerState.get_room(), "street", "travel: the player is on the street")
	var store_door: Interactable = null
	for item: Interactable in _game.streamer.get_interactables_in_room("street"):
		if item.interact_type == "exit" and str(item.data.get("target_room", "")) == "flagship_store":
			store_door = item
	check(store_door != null, "travel: the street has a door into the flagship store")
	if store_door != null:
		await _game.travel.travel_to(store_door, _game.travel.destinations_for(store_door)[0])
		await _settle()
		check_eq(PlayerState.get_room(), "flagship_store", "travel: entering by the store door arrives in the store")


## Reglas sin viajar: conductos (aseo sí, despacho no), montacargas (R1 no), cornisas y bultos.
func _test_travel_rules() -> void:
	_game.travel.teleport_to_room("p3_toilets")
	await _settle()
	var hatch: Interactable = _find_item("p3_toilets", "vent_hatch")
	check(hatch != null and _game.travel.refusal_for(hatch).is_empty(), "rules: a toilet hatch lets anyone into the ducts")
	var vents: Array[Dictionary] = _game.travel.destinations_for(hatch) if hatch != null else []
	check(vents.size() > 10 and not str(vents[0].get("transit_id", "")).is_empty(), "rules: the ducts list every other hatch")
	check(not _game.travel.can_enter_vent("hr_office"), "rules: an office hatch needs maintenance access")
	check(FloorTravel.travel_minutes("vent_hatch", 3, true) < FloorTravel.travel_minutes("vent_hatch", 3), "rules: hurrying through the ducts is faster")
	check(not _game.travel.freight_allowed(), "rules: R1 cannot run the freight elevator")
	check(PlayerState.add_item("product_box"), "rules: carrying a bulky box")
	_game.travel.teleport_to_room(SERVICE_ROOM)
	await _settle()
	var service: Interactable = _find_item(SERVICE_ROOM, "service_stairs_door")
	check_eq(str(_game.travel.refusal_for(service).get("key", "")), "TRAVEL_REFUSE_BULKY", "rules: bulky loads only by freight elevator")
	PlayerState.remove_item("product_box")
	check(_game.travel.refusal_for(service).is_empty(), "rules: without the box the stairs are fine again")
	check(FloorTravel.travel_minutes("service_stairs", 4) > FloorTravel.travel_minutes("elevator", 4), "rules: service stairs are slower than the elevator")


func _find_item(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


func _dest_for(dests: Array[Dictionary], floor_number: int) -> Dictionary:
	for dest: Dictionary in dests:
		if int(dest["floor"]) == floor_number:
			return dest
	return {}


# ─── Halo de zona (HUD) ───────────────────────────────────────

func _test_zone_halo() -> void:
	_game.travel.teleport_to_room(RESTRICTED_ROOM)
	await _settle()
	check_eq(PlayerState.get_room(), RESTRICTED_ROOM, "halo: player inside the monitor room")
	check(_game.ui.get_hud().is_zone_restricted(), "halo: the HUD flags a room above the player's clearance")
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	check(not _game.ui.get_hud().is_zone_restricted(), "halo: the own wing is not restricted")


# ─── Salto temporal ───────────────────────────────────────────

func _test_time_skip() -> void:
	var never: Callable = func() -> bool: return false
	_game.time_skip.setup(_game.ui, _game.player, _game.travel, never)
	GameClock.set_observer_check(never)
	check_eq(_game.time_skip.check(), "", "time skip: allowed at the own desk without observers")
	var band: String = TimeSkip.next_band()
	check(await _game.time_skip.skip_now(), "time skip: skipped")
	check_eq(GameClock.get_current_band(), band, "time skip: now in the next band")
	_game.travel.teleport_to_room(CORRIDOR)
	await _settle()
	check_eq(_game.time_skip.check(), TimeSkip.REASON_UNSAFE, "time skip: refused in a corridor (not a safe place)")
	GameClock.set_observer_check(func() -> bool: return true)
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	var always: Callable = func() -> bool: return true
	_game.time_skip.setup(_game.ui, _game.player, _game.travel, always)
	check_eq(_game.time_skip.check(), TimeSkip.REASON_OBSERVED, "time skip: refused with observers")
	_game.time_skip.setup(_game.ui, _game.player, _game.travel, _game.observers_present)
	GameClock.set_observer_check(_game.observers_present)


# ─── Ascensos ─────────────────────────────────────────────────

func _test_promotion_flow() -> void:
	var toasts: int = _game.ui.get_toasts().get_child_count()
	EventBus.promotion_available.emit(["email_worker_3b"])
	check(_game.ui.get_toasts().get_child_count() > toasts, "promotion: an available promotion is announced")
	var target: OccupationData = _rank_two_with_office()
	check(target != null, "promotion: a rank-2 post with an office exists")
	if target == null:
		return
	var presented: Array = []
	_game.promotion.presented.connect(func(o: String, n: String, r: String) -> void: presented.append([o, n, r]), CONNECT_ONE_SHOT)
	PlayerState.set_occupation(target.id, "promotion")
	await _settle()
	check_eq(presented.size(), 1, "promotion: occupation_changed(promotion) is presented")
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), target.office_room, "promotion: the player lands at the new office")
	var door: Door = _door_into(target.office_room)
	if door != null:
		check(DoorAccess.allows(door), "doors: the own office always opens (even above the card level)")
	PlayerState.set_occupation(Database.get_balance("jugador.ocupacion_inicial"), "qa")
	if door != null and door.clearance > PlayerState.get_clearance():
		check(not DoorAccess.allows(door), "doors: someone else's office above the card stays shut")
	_game.travel.teleport_to_room(OFFICE)
	await _settle()


func _door_into(room_id: String) -> Door:
	for door: Door in _game.streamer.get_doors():
		if door.room_b == room_id and door.kind == Door.KIND_READER:
			return door
	return null


func _rank_two_with_office() -> OccupationData:
	for occ: OccupationData in Database.get_occupations_by_rank(2):
		if not occ.office_room.is_empty() and Database.get_room(occ.office_room) != null \
				and occ.office_room != OFFICE:
			return occ
	return null


# ─── Jornada, sueño y guardado ────────────────────────────────

func _test_day_and_sleep() -> void:
	var now: float = GameClock.get_day_minutes()
	GameClock.advance_minutes(SLEEP_HOUR * 60.0 - now)
	check_eq(GameClock.get_hour(), SLEEP_HOUR, "day: evening reached")
	check(_game.travel.teleport_to_room(FLAT), "day: home")
	await _settle()
	check_eq(PlayerState.get_room(), FLAT, "day: the player is in the flat")
	var home: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle
	var result: Dictionary = home.sleep()
	await _settle()
	check(bool(result.get("ok", false)), "day: sleeping works at home at night")
	check(bool(result.get("saved", false)), "day: sleeping saved the run")
	check_eq(GameClock.get_day(), 2, "day: sleeping produced day 2")
	check(SaveSystem.run_exists(), "day: a save file exists")
	check_eq(_game.ui.get_last_summary_day(), 1, "day: the day summary was shown")


func _test_continue() -> void:
	await _free_game()
	_game = await _spawn_game({"mode": "load"})
	check_eq(_game.get_mode(), "load", "continue: the saved run was loaded")
	check_eq(GameClock.get_day(), 2, "continue: day 2")
	check_eq(PlayerState.get_player_name(), PLAYER_NAME, "continue: the name survived")
	check_eq(_game.streamer.get_current_floor(), Database.get_balance_int("mundo.planta_exterior"), "continue: on the exterior floor")
	check_eq(PlayerState.get_room(), FLAT, "continue: the player wakes up in the flat")
	check(not GameClock.is_paused(), "continue: run_loaded resumed the clock")


func _free_game() -> void:
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame


# ─── Fin de partida ───────────────────────────────────────────

func _test_game_over() -> void:
	var ending: String = Tracking.evaluate_ending_for_cause(CAUSE)
	EventBus.game_over.emit(CAUSE, ending, Tracking.get_snapshot_for_cause(CAUSE))
	check(GameClock.is_paused(), "game over: the world stops")
	check(not SaveSystem.run_exists(), "game over: permadeath deleted the run")
	var epilogue: EpilogueScreen = await _wait_scene("EpilogueScreen") as EpilogueScreen
	check(epilogue != null, "game over: the epilogue screen replaces the game")
	if epilogue == null:
		return
	check_eq(epilogue.ending_id, ending, "game over: the epilogue shows the evaluated ending")
	epilogue.finish_typing()
	epilogue.reveal_buttons()
	epilogue.call("_close", false)
	var boot: Node = await _wait_scene("BootScreen")
	check(boot != null, "game over: closing the epilogue returns to the boot scene")
	await _settle()
	check(boot != null and boot.get_child_count() > 0 and boot.get_child(0) is MainMenu, "game over: the main menu is shown")
	_game = null


func _wait_scene(class_label: String) -> Node:
	for i: int in MAX_SCENE_WAITS:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get_script() != null and (scene.get_script() as Script).get_global_name() == class_label:
			return scene
		await get_tree().process_frame
	return null


func _cleanup() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null:
		scene.queue_free()
	SaveSystem.delete_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.get_profile_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	GameRoot.spawn_audio = true
	MenuKit.spawn_audio = true
	InteractionRouter.reset()
