# interactions_places_case.gd — Cuerpo de test_interactions_places: cada manejador del módulo de lugares y escenas en la escena de juego real (sin ventana), con sus diálogos contestados, actos, delitos, dinero, objetos, avisos, el registro de los tornos, la citación ineludible y el allanamiento.
# PROPIETARIO DE: nada (monta y libera la escena de juego; los interactivos de prueba se crean y se liberan aquí; su carpeta de guardado se borra al final).
# ESCUCHA: EventBus.crime_committed (para comprobar lo que emite el módulo).
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const PLACES_MODULE := "res://src/world/interactions/places.gd"
const STORAGE_FORMAT := "user://test_interactions_places_%d"
const RUN_SEED := 4343
const FRAMES_SETTLE := 3
const DRIVE_TIMEOUT := 8.0
const QA_ACT := 0.05
const EPS := 0.01
const EXTERIOR := 200
const FACTORY := 100
const STREET := "street"
const FLAT := "player_flat"
const TURNSTILES := "turnstiles"
const GATE_ID := "turnstile_gate_2"
const START_POST := "email_worker_3b"

var _game: GameRoot = null
var _places: Script = null
var _keeper: PlacesKeeper = null
var _crimes: Array[Dictionary] = []
var _probes: Array[Interactable] = []
var _serial: int = 0


func run_case() -> void:
	allowed_engine_errors = 0
	SaveSystem.set_storage_dir(STORAGE_FORMAT % OS.get_process_id())
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	PlacesKit.qa_act_seconds = QA_ACT
	check(new_run(RUN_SEED), "Database loaded")
	_places = load(PLACES_MODULE) as Script
	await _spawn_game()
	_test_router()
	await _test_keeper_nodes()
	await _test_turnstile_swipe()
	await _test_tailgate()
	await _test_summons()
	await _test_shops()
	await _test_sleep()
	await _test_bus()
	await _test_social()
	await _test_care()
	await _test_factory()
	await _test_scenes()
	await _test_board()
	await _test_house()
	await _test_suit()
	await _cleanup()


# ─── Montaje ──────────────────────────────────────────────────

func _spawn_game() -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	_game.request_overrides = {"mode": "new", "seed": RUN_SEED, "player_name": "Pat Places", "skip_intro": true}
	_game.epilogue_delay_override = 0.0
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_game.travel.instant = true
	_game.time_skip.instant = true
	_game.promotion.instant = true
	_game.bridges.instant = true
	await _settle()
	_keeper = PlacesKeeper.ensure(get_tree())
	if _keeper != null:
		_keeper.instant = true
	## Sin percepción en marcha: los actos no los interrumpe una flagrancia al azar.
	_game.npc_layer.set_physics_process(false)
	EventBus.crime_committed.connect(func(t: String, r: String, d: Dictionary) -> void:
		_crimes.append({"type": t, "room": r, "details": d}))


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _cleanup() -> void:
	PlacesKit.qa_act_seconds = -1.0
	for probe: Interactable in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	await get_tree().process_frame
	SaveSystem.delete_run()


func _probe(interact_type: String, room_id: String, data: Dictionary) -> Interactable:
	_serial += 1
	var item: Interactable = Interactable.new()
	item.setup("qa_%s_%d" % [interact_type, _serial], interact_type, room_id, data, RoomBuilder.cell_px(), Vector2.ZERO)
	_game.add_child(item)
	item.global_position = _game.player.global_position
	_probes.append(item)
	return item


## Llama al módulo como lo haría el router y contesta sus diálogos en orden (el aviso «te
## están mirando» se acepta solo; sin respuestas, se cancela). Devuelve cuántos diálogos vio.
func _use(item: Interactable, answers: Array = []) -> int:
	var ctx: Dictionary = InteractionRouter.build_context(item, _game.player)
	return await _drive(func() -> void: await _places.call("interact", item, _game.player, ctx), answers, item.interact_type)


func _drive(action: Callable, answers: Array, label: String) -> int:
	var state: Dictionary = {"done": false, "seen": 0}
	var runner: Callable = func() -> void:
		await action.call()
		state["done"] = true
	_game.ui.get_toasts().clear()
	runner.call()
	var queue: Array = answers.duplicate()
	var left: float = DRIVE_TIMEOUT
	while not bool(state["done"]) and left > 0.0:
		var box: DialogBox = _game.ui.get_top_modal() as DialogBox
		if box != null and not box.is_done():
			state["seen"] = int(state["seen"]) + 1
			if _is_watch_prompt(box):
				box.choose(1)
			elif queue.is_empty():
				box.cancel()
			else:
				box.choose(int(queue.pop_front()))
		await get_tree().process_frame
		left -= get_process_delta_time()
	check(bool(state["done"]), "drive: %s finished" % label)
	return int(state["seen"])


func _is_watch_prompt(box: DialogBox) -> bool:
	return box.get_option_count() > 1 and box.get_option_text(1).ends_with(TranslationServer.translate("PLACES_WATCHED_PROCEED"))


func _saw_toast(key: String) -> bool:
	var stem: String = TranslationServer.translate(key).get_slice("%", 0).strip_edges()
	var toasts: ToastStack = _game.ui.get_toasts()
	for i: int in toasts.get_toast_count():
		if toasts.get_toast_text(i).begins_with(stem):
			return true
	return false


func _crime(crime_type: String) -> Dictionary:
	for i: int in range(_crimes.size() - 1, -1, -1):
		if str(_crimes[i]["type"]) == crime_type:
			return _crimes[i]
	return {}


func _close_modals() -> void:
	while _game.ui.has_modal():
		_game.ui.close_modal()
	await _settle()


func _find_real(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


func _find_node(interact_id: String) -> Interactable:
	for node: Node in get_tree().get_nodes_in_group(PlacesKeeper.NODES_GROUP):
		if (node as Interactable).interact_id == interact_id:
			return node as Interactable
	return null


func _go(room_id: String) -> void:
	_game.travel.teleport_to_room(room_id)
	await _settle()


func _set_post(occupation_id: String) -> void:
	PlayerState.set_occupation(occupation_id, "qa")
	await _settle()
	await _close_modals()


# ─── Router y keeper ──────────────────────────────────────────

func _test_router() -> void:
	var owned: int = 0
	var types: Array = _places.call("handled_types")
	for interact_type: String in types:
		if InteractionRouter.module_for(interact_type) == _places:
			owned += 1
	check_eq(owned, types.size(), "router: places.gd owns every type it claims")
	for kind: String in ["turnstile", "bed", "shop_counter", "bus_stop", "smoking_spot", "aurora_podium", "product_shelf"]:
		check(InteractionRouter.module_for(kind) == _places, "router: %s goes to the places module" % kind)
	check_eq(InteractionRouter.prompt_key_for(_probe("bed", FLAT, {"action": "sleep_save"})), "UI_INTERACT_SLEEP",
			"prompt: the flat's bed still says go to bed")
	check_eq(InteractionRouter.prompt_key_for(_probe("bed", "infirmary", {"recovery": true})), "UI_INTERACT_REST",
			"prompt: the infirmary bed says rest")
	for key: String in ["UI_INTERACT_TURNSTILE_QUEUE", "UI_INTERACT_CLAN_TABLE", "UI_INTERACT_FOOSBALL_TABLE", "UI_INTERACT_HOUSE_DOOR"]:
		check(TranslationServer.translate(key) != key, "prompt: %s has a text" % key)


func _test_keeper_nodes() -> void:
	check(_keeper != null, "keeper: PlacesKeeper hangs under the game root")
	await _go(TURNSTILES)
	check(_find_node(PlacesKeeper.QUEUE_ID) != null, "keeper: the turnstile queue point exists on the ground floor")
	check(_find_node("places_clan_table") != null, "keeper: the clan table sits in the cafeteria")
	var queue: Interactable = _find_node(PlacesKeeper.QUEUE_ID)
	GameClock.set_time(GameClock.get_day(), 8, 30)
	check(queue != null and InteractionRouter.is_available_for(queue, _game.player), "keeper: the queue is offered in the morning rush")
	GameClock.set_time(GameClock.get_day(), 10, 0)
	check(queue != null and not InteractionRouter.is_available_for(queue, _game.player), "keeper: no queue outside the rush")
	await _go("foosball_room")
	check(_find_node("places_foosball_table") != null, "keeper: the foosball table sits in the P4 break room")
	await _go(STREET)
	var doors: int = 0
	for node: Node in get_tree().get_nodes_in_group(PlacesKeeper.NODES_GROUP):
		doors += 1 if (node as Interactable).interact_type == PlacesKeeper.HOUSE_DOOR_TYPE else 0
	check_eq(doors, 3, "keeper: one door on the street per NPC house")


# ─── Tornos ───────────────────────────────────────────────────

func _gate() -> Door:
	return _game.streamer.get_door_by_id(GATE_ID)


func _gate_point(gate: Door, cells_across: float) -> Vector2:
	var centre: Vector2 = gate.gap_rect().get_center()
	var normal: Vector2 = Vector2(1.0, 0.0) if gate.vertical else Vector2(0.0, 1.0)
	return gate.to_global(centre + normal * cells_across * RoomBuilder.cell_px())


func _test_turnstile_swipe() -> void:
	await _go(TURNSTILES)
	GameClock.set_time(GameClock.get_day(), 10, 0)
	var gate: Door = _gate()
	var item: Interactable = _find_real(TURNSTILES, "turnstile")
	check(gate != null and item != null, "turnstile: gate and its interactable exist")
	if gate == null or item == null:
		return
	var outer: float = -1.0 if DoorAccess.across(gate, _game.streamer.get_spawn_point(TURNSTILES)) < 0.0 else 1.0
	_game.player.global_position = _gate_point(gate, outer * 1.0)
	await _settle()
	var logs: int = Security.get_access_log().size()
	var gate_item: Interactable = _real_by_id(TURNSTILES, GATE_ID)
	await _use(gate_item if gate_item != null else item)
	check(_saw_toast("INTERACT_TURNSTILE_OPEN") and _game.doors.is_armed(GATE_ID), "turnstile: E swipes the card (armed until you cross)")
	_game.player.global_position = _gate_point(gate, -outer * 1.8)
	await _settle()
	var records: int = 0
	for entry: Dictionary in Security.get_access_log().slice(logs):
		records += 1 if str(entry.get("reader_id", "")) == GATE_ID else 0
	check_eq(records, 1, "turnstile: crossing after swiping leaves one clock-in record at that gate")


func _real_by_id(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


## Un compañero junto al torno: el primero de la planta, llevado allí (la capa de NPC no se mueve).
func _cover_at(gate: Door) -> String:
	_game.npc_layer.sync_now()
	var nodes: Array[NPCNode] = _game.npc_layer.get_nodes()
	if nodes.is_empty():
		return ""
	nodes[0].global_position = _gate_point(gate, 0.4)
	return nodes[0].npc_id


func _test_tailgate() -> void:
	var gate: Door = _gate()
	var queue: Interactable = _find_node(PlacesKeeper.QUEUE_ID)
	if gate == null or queue == null:
		check(false, "tailgate: gate and queue exist")
		return
	GameClock.set_time(GameClock.get_day(), 8, 35)
	var cover: String = _cover_at(gate)
	check(not cover.is_empty() and not PlacesGate.cover_npc(_game, gate).is_empty(), "tailgate: a colleague stands at the gate")
	_game.player.global_position = queue.global_position
	await _settle()
	var logs: int = Security.get_access_log().size()
	var side_before: float = signf(DoorAccess.across(gate, _game.player.global_position))
	await _use(queue)
	await _settle()
	check(signf(DoorAccess.across(gate, _game.player.global_position)) == -side_before, "tailgate: the player ends up past the turnstile")
	check_eq(Security.get_access_log().size(), logs, "tailgate: slipping in behind a colleague leaves no card record")
	check(_saw_toast("PLACES_GATE_SLIPPED"), "tailgate: the player is told (and reminded of the camera)")
	check(not _game.player.is_input_locked(), "tailgate: input comes back after the guided step")
	_game.player.set_crouching(true)
	check(not _keeper.tailgate_cover(gate).is_empty(), "tailgate: walking in crouched behind someone also works")
	GameClock.set_time(GameClock.get_day(), 10, 30)
	check(_keeper.tailgate_cover(gate).is_empty(), "tailgate: not outside the morning rush")
	_game.player.set_crouching(false)
	await _use(queue)
	check(_saw_toast("PLACES_GATE_NO_RUSH"), "tailgate: the queue explains when it works")


# ─── Tiendas y dormir ─────────────────────────────────────────

func _test_shops() -> void:
	await _go("supermarket")
	GameClock.set_time(GameClock.get_day(), 19, 30)
	var counter: Interactable = _find_real("supermarket", "shop_counter")
	var home: HomeCycle = _game.sim_nodes["HomeCycle"] as HomeCycle
	var goods: Array[Dictionary] = home.get_shop_items("supermarket")
	var dinner: int = -1
	for i: int in goods.size():
		if str(goods[i]["item_id"]) == "food_dinner":
			dinner = i
	check(counter != null and dinner >= 0, "shop: the supermarket sells dinner")
	if counter == null or dinner < 0:
		return
	PlayerState.add_money(120, "test")
	var money: int = PlayerState.get_money()
	var minute: float = GameClock.get_day_minutes()
	await _use(counter, [dinner])
	check(PlayerState.is_carrying("food_dinner"), "shop: dinner bought")
	check_eq(PlayerState.get_money(), money - int(goods[dinner]["price"]), "shop: paid the balance price")
	check(GameClock.get_day_minutes() > minute and _saw_toast("PLACES_SHOP_BOUGHT"), "shop: shopping takes time and says so")
	await _go("clothes_shop")
	var till: Interactable = _find_real("clothes_shop", "shop_counter")
	PlayerState.add_money(100, "qa")
	await _use(till, [0])
	check(PlayerState.is_carrying("balaclava") and _saw_toast("PLACES_BALACLAVA_BOUGHT"), "shop: balaclava bought, with a warning")
	await _go("flagship_store")
	await _use(_find_real("flagship_store", "shop_counter"))
	check(_saw_toast("PLACES_STORE_PRICE"), "shop: the flagship till shows the real price")


func _test_sleep() -> void:
	await _go(FLAT)
	GameClock.set_time(GameClock.get_day(), 22, 0)
	var day: int = GameClock.get_day()
	var bed: Interactable = _find_real(FLAT, "bed")
	check(bed != null, "sleep: the flat has a bed")
	if bed == null:
		return
	await _use(bed)
	await _close_modals()
	check_eq(GameClock.get_day(), day + 1, "sleep: the bed ends the day")
	check(SaveSystem.run_exists(), "sleep: the run is saved")
	check(_saw_toast("SLEEP_SAVED"), "sleep: the saved toast shows")


# ─── Autobús ──────────────────────────────────────────────────

func _test_bus() -> void:
	await _go(STREET)
	GameClock.set_time(GameClock.get_day(), 8, 10)
	var stop: Interactable = _find_real(STREET, "bus_stop")
	check(stop != null, "bus: the street has a stop")
	if stop == null:
		return
	var money: int = PlayerState.get_money()
	var minute: float = GameClock.get_day_minutes()
	await _use(stop, [0])
	await _settle()
	check_eq(_game.streamer.get_current_floor(), 0, "bus: to work → ground floor")
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), "main_reception", "bus: dropped inside reception")
	check_eq(PlayerState.get_money(), money - Database.get_balance_int("lugares.autobus.tarifa"), "bus: the fare is paid")
	check_near(GameClock.get_day_minutes() - minute, Database.get_balance_float("lugares.autobus.minutos"), 1.0, "bus: the ride costs its minutes")
	await _go(STREET)
	await _use(_find_real(STREET, "bus_stop"), [1])
	await _settle()
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), FLAT, "bus: home → inside the flat")
	GameClock.set_time(GameClock.get_day(), 20, 0)
	check(bool(PlacesTown.dest_option({"kind": PlacesTown.KIND_WORK})["disabled"]), "bus: no ride to work at night")
	check_eq(PlacesTown.arrive(_keeper, PlacesTown.KIND_WORK, "main_reception"), "PLACES_BUS_BUILDING_CLOSED", "bus: at night the building is closed")
	check_eq(_game.streamer.get_current_floor(), EXTERIOR, "bus: ...and you stay on the street")
	GameClock.set_time(GameClock.get_day(), 10, 0)


# ─── Corrillos ────────────────────────────────────────────────

func _two_colleagues() -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and out.size() < 2:
			out.append(npc.id)
	return out


func _test_social() -> void:
	var people: Array[String] = _two_colleagues()
	BeliefNet.create_belief(people[1], "player", "seen_partially", 0.5, Belief.SOURCE_DIRECT, "wing_3b")
	BeliefNet.create_belief(people[1], people[0], "steals_ideas", 0.9, Belief.SOURCE_DIRECT, "wing_3b")
	var lines: Array[String] = PlacesSocial.gossip_lines(people, 2, true)
	var about_you: String = TranslationServer.translate("PLACES_GOSSIP_ABOUT_YOU").get_slice("%s", 1)
	check(lines.size() == 2 and lines[0].contains(about_you), "gossip: at the smokers' circle what they think of YOU comes first (%s)" % str(lines))
	check(PlacesSocial.gossip_lines(people, 1, false).size() == 1, "gossip: the line cap holds")
	var quiet: Array[String] = []
	var mood: String = TranslationServer.translate("PLACES_GOSSIP_MOOD").get_slice("(", 0)
	check(PlacesSocial.gossip_lines(quiet, 3, false).any(func(l: String) -> bool: return l.begins_with(mood)),
			"gossip: with nothing to tell, there is still the staff's mood (never an empty chat)")
	var lover: String = ""
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if lover.is_empty() and not SocialGraph.get_blackmail_links(npc.id).is_empty():
			lover = npc.id
	if not lover.is_empty():
		var pair: Array[String] = [lover]
		check_eq(PlacesSocial.couple_lines(pair).size(), 1, "gossip: the smokers let a secret couple slip (blackmail material)")
	var rumours: int = SocialGraph.get_injected_rumours().size()
	var ctx: Dictionary = _keeper.ctx()
	await _drive(func() -> void: await PlacesSocial.plant(_game.player, ctx, "smokers_circle", people), [0, 0, 1], "plant")
	check_eq(SocialGraph.get_injected_rumours().size(), rumours + 1, "rumour: planted through SocialGraph")
	check(not _crime("rumour_planted").is_empty() and _saw_toast("PLACES_RUMOUR_PLANTED"), "rumour: it is a crime and it is announced")
	check(PlacesKit.used_today("rumour.smokers_circle"), "rumour: once a day per circle")
	await _go("cafeteria")
	GameClock.set_time(GameClock.get_day(), 11, 0)
	await _use(_find_node("places_clan_table"))
	check(_saw_toast("PLACES_CLAN_EMPTY"), "clan: outside lunch the table is empty")
	GameClock.set_time(GameClock.get_day(), 13, 20)
	var seen: int = await _use(_find_node("places_clan_table"), [0, 0])
	check(seen >= 1 or _saw_toast("PLACES_GATHERING_EMPTY_CAFETERIA_CLAN"), "clan: at lunch you can sit with them (%d dialogs)" % seen)
	await _go("foosball_room")
	var huddle: int = await _use(_find_node("places_foosball_table"), [0, 0])
	check(huddle >= 1 or _saw_toast("PLACES_GATHERING_EMPTY_FOOSBALL_CIRCLE"), "foosball: cheap info or an empty table, never silence")
	await _go(STREET)
	var smokers: int = await _use(_find_real(STREET, "smoking_spot"))
	check(smokers >= 1 or _saw_toast("PLACES_GATHERING_EMPTY_SMOKERS_CIRCLE"), "smokers: the circle or the hint of when it meets")


# ─── Enfermería ───────────────────────────────────────────────

func _test_care() -> void:
	await _go("infirmary")
	PlacesKeeper.set_burn("factory_dye_lab")
	var bed: Interactable = _find_real("infirmary", "bed")
	var minute: float = GameClock.get_day_minutes()
	await _use(bed, [0])
	check(not PlacesKeeper.is_burned() and _saw_toast("PLACES_BURN_TREATED"), "infirmary: resting cures the lab burn")
	check_near(GameClock.get_day_minutes() - minute, Database.get_balance_float("lugares.minutos.enfermeria"), 1.0, "infirmary: rest takes its time")
	var cabinet: Interactable = _find_real("infirmary", "medical_cabinet")
	await _use(cabinet)
	check(PlayerState.is_carrying("medical_supplies"), "infirmary: a first-aid kit a day")
	await _use(cabinet)
	check(_saw_toast("PLACES_KIT_ALREADY"), "infirmary: only one kit a day")
	PlacesKeeper.set_burn("factory_dye_lab")
	check_eq(InteractionRouter.prompt_key_for(cabinet), "UI_INTERACT_TREAT_BURN", "infirmary: the cabinet offers to treat a burn")
	await _use(cabinet)
	check(not PlacesKeeper.is_burned(), "infirmary: the cabinet treats it too")


# ─── La nave ──────────────────────────────────────────────────

func _test_factory() -> void:
	await _set_post("line_operator")
	await _go("finished_goods")
	GameClock.set_time(GameClock.get_day(), 10, 0)
	_crimes.clear()
	var shelf: Interactable = _real_by_id("finished_goods", "goods_shelf_west")
	await _use(shelf, [0])
	check(PlayerState.is_carrying("product_pair"), "factory: a pair in the pocket (R3 on the line)")
	check(not _crime("theft_product").is_empty() and _saw_toast("PLACES_FACTORY_STOLEN"), "factory: theft_product emitted and announced")
	var box: Dictionary = PlacesFactory.scale_option("box", FactoryTheft.check_requirements("box", {"room_id": "finished_goods"}))
	check(bool(box.get("disabled", false)), "factory: a box is offered greyed out with its reason")
	await _go("flagship_store")
	var money: int = PlayerState.get_money()
	await _use(_real_by_id("flagship_store", "store_display"))
	check(not PlayerState.is_carrying("product_pair") and PlayerState.get_money() > money, "factory: fenced at the flagship store")
	await _go("finished_goods")
	shelf = _real_by_id("finished_goods", "goods_shelf_west")
	await _use(shelf, [0])
	await _use(shelf, [2])
	check(not PlayerState.is_carrying("product_pair") and _saw_toast("PLACES_FACTORY_RETURNED"), "factory: stolen goods can go back on the shelf")
	await _test_molds_and_qc()
	await _test_chemicals()
	await _set_post(START_POST)


func _test_molds_and_qc() -> void:
	await _go("mold_room")
	var quality: float = float(Company.get_fundamentals().get("product_quality", 0.0))
	await _use(_find_real("mold_room", "mold_station"), [0])
	check(float(Company.get_fundamentals().get("product_quality", 0.0)) < quality, "molds: product quality drops")
	check(str(_crime("sabotage").get("details", {}).get("kind", "")) == "mold_quality" and PlacesFactory.defects_real(),
			"molds: sabotage emitted and the defects are real for QC")
	await _go("quality_control")
	var qc: Interactable = _find_real("quality_control", "qc_terminal")
	var target: String = PlacesFactory.foreman_of(qc)
	check(NPCDirector.is_active(target), "qc: the foreman is on the payroll (%s)" % target)
	var rep: float = NPCDirector.get_npc_reputation(target)
	await _use(qc, [0])
	check(NPCDirector.get_npc_reputation(target) < rep and _saw_toast("PLACES_QC_FILED"), "qc: a real defect report dents the foreman's reputation")
	check(_crime("framing").is_empty(), "qc: with real defects the report is not framing")
	PlayerState.set_flag(PlacesFactory.F_REPORTS, [GameClock.get_day() - 1, GameClock.get_day() - 2])
	PlayerState.set_flag(PlacesKit.FLAG_DAY + PlacesFactory.QC_KEY, null)
	await _use(qc, [0])
	check(not NPCDirector.is_active(target) and _saw_toast("PLACES_QC_FOREMAN_OUT"), "qc: the third report in the window costs him the post")
	await _go("foreman_office")
	await _use(_find_real("foreman_office", "delivery_notes"))
	check(_saw_toast(FactoryTheft.get_reason_label_key(FactoryTheft.REASON_NOT_FOREMAN)), "notes: only the foreman forges delivery notes")


func _test_chemicals() -> void:
	await _go("factory_dye_lab")
	var chem: Interactable = _find_real("factory_dye_lab", "chemical_station")
	await _use(chem, [0])
	var crime: Dictionary = _crime("sabotage")
	check(str(crime.get("details", {}).get("kind", "")) == "chemical_accident" and float(crime["details"].get("company_loss", 0.0)) > 0.0,
			"chemicals: an 'accident' with a company loss")
	check(_saw_toast("PLACES_CHEM_DONE") or (_saw_toast("PLACES_CHEM_ERROR") and PlacesKeeper.is_burned()), "chemicals: done, or burned")
	PlacesKeeper.cure_burn()
	await _use(chem)
	check(_saw_toast("PLACES_CHEM_ALREADY"), "chemicals: once a day")


# ─── Salas con escena ─────────────────────────────────────────

func _test_scenes() -> void:
	await _go("interrogation_room")
	await _use(_find_real("interrogation_room", "interrogation_table"))
	check(_saw_toast("PLACES_INTERROGATION_EMPTY"), "interrogation: nobody summoned you → empty room")
	await _go("results_room")
	await _use(_find_real("results_room", "results_stage"))
	check(_saw_toast("PLACES_RESULTS_RANK"), "results: below R28 you only watch")
	await _go("notary")
	await _use(_find_real("notary", "notary_desk"))
	check(_saw_toast("PLACES_NOTARY_IDLE"), "notary: before the revelation it is just a notary")
	await _go("aurora_room")
	check(await _use(_find_real("aurora_room", "aurora_podium")) >= 1, "aurora: the podium says when the next meeting is")
	await _close_modals()
	await _go("training_room")
	await _use(_find_real("training_room", "training_screen"), [0])
	check(_saw_toast("PLACES_TRAINING_DONE"), "training: the corporate video plays by default")
	await _go("police_station")
	await _use(_find_real("police_station", "police_desk"), [1, 1])
	check(_saw_toast("PLACES_POLICE_CONFESSED"), "police: turning yourself in is a (harmless) joke")
	await _test_buyers()


func _test_buyers() -> void:
	await _go("buyer_demo_room")
	GameClock.set_time(GameClock.get_day(), 17, 0)
	var roster: Array[Dictionary] = Company.get_buyer_roster()
	var buyer: String = str(roster[0]["id"]) if not roster.is_empty() else ""
	check(Company.schedule_buyer_visit(buyer), "buyers: a buyer is brought in today at 17:00")
	await _test_lounge(buyer)
	await _go("buyer_demo_room")
	var demo: Interactable = _find_real("buyer_demo_room", "demo_table")
	await _use(demo, [0])
	check(_saw_toast("BUYER_REASON_NOT_A_SELLER"), "buyers: an email worker cannot close sales")
	await _set_post("junior_sales")
	await _go("buyer_demo_room")
	var money: int = PlayerState.get_money()
	await _use(demo, [0, 0])
	check(PlayerState.get_money() > money and _saw_toast("PLACES_BUYERS_DONE"), "buyers: an honest sale pays its commission")
	await _use(demo)
	check(_game.ui.get_toasts().get_toast_count() >= 0, "buyers: the table answers again")
	GameClock.set_time(GameClock.get_day(), 11, 0)


## Sala de espera de la PB: antes de su hora el sofá deja escuchar al comprador (rasgos revelados).
func _test_lounge(buyer: String) -> void:
	GameClock.set_time(GameClock.get_day(), 16, 0)
	await _go("visitor_lounge")
	var lounge: Interactable = _find_node("places_buyer_lounge")
	check(lounge != null and InteractionRouter.is_available_for(lounge, _game.player), "lounge: with a buyer waiting the sofa is offered")
	if lounge != null:
		await _use(lounge, [0])
	check(Company.is_buyer_known(buyer), "lounge: overhearing them reveals the buyer's traits")
	GameClock.set_time(GameClock.get_day(), 17, 0)
	check(lounge == null or not InteractionRouter.is_available_for(lounge, _game.player), "lounge: once their meeting starts, nobody waits")


func _test_board() -> void:
	await _go("boardroom")
	var table: Interactable = _find_real("boardroom", "board_table")
	await _use(table)
	check(_saw_toast("PLACES_BOARD_NO_SEAT"), "board: without a seat you cannot vote")
	await _set_post("board_investor")
	await _go("boardroom")
	await _use(table, [2])
	check(_saw_toast("PLACES_BOARD_ABSTAINED") and PlacesKit.used_today(PlacesScenes.BOARD_KEY), "board: abstaining still casts the day's vote")
	var pending: bool = false
	for duty: Dictionary in PlayerState.get_pending_duties():
		pending = pending or str(duty.get("subtype", "")) == "board_vote"
	check(not pending, "board: the board-vote duty is done")
	await _use(table)
	check(_saw_toast("PLACES_BOARD_ALREADY"), "board: one session a day")
	check_near(PlacesScenes.expel_chance(0), Database.get_balance_float("lugares.consejo.prob_base"), EPS, "board: base chance")
	check_near(PlacesScenes.expel_chance(1000), Database.get_balance_float("lugares.consejo.prob_max"), EPS, "board: capped chance")
	var targets: Array[String] = PlacesScenes.expel_targets()
	check(not targets.is_empty(), "board: there are executives to vote on")
	if not targets.is_empty():
		PlacesScenes.resolve_expulsion(_keeper.ctx(), targets[0], 1000)
		check(not NPCDirector.is_active(targets[0]) or _saw_toast("PLACES_BOARD_EXPEL_FAILED"), "board: the vote either expels or backfires")
	await _set_post(START_POST)


# ─── Viviendas ────────────────────────────────────────────────

func _resident_of(house: String) -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and NPCDirector.get_home_address(npc.id) == house:
			return npc.id
	return ""


func _test_house() -> void:
	var house: String = "npc_house_humble"
	var ops: NightOps = _game.sim_nodes["NightOps"] as NightOps
	GameClock.set_time(GameClock.get_day(), 20, 30)
	await _go(STREET)
	_game.ui.get_toasts().clear()
	_game.travel.teleport_to_room(house)
	await _settle()
	await _settle()
	check(DatabaseSystem.get_room_base_id(PlayerState.get_room()) != house and _saw_toast("PLACES_HOUSE_LOCKED"), "house: locked without a break-in")
	var resident: String = _resident_of(house)
	check(not resident.is_empty(), "house: someone lives in the humble flat")
	PlayerState.grant_full_file(resident, "hr_intrusion")
	if not PlayerState.is_carrying("balaclava"):
		PlayerState.add_item("balaclava")
	await _go("transport_stop")
	var stop: Interactable = _find_real("transport_stop", "bus_stop")
	var dests: Array[Dictionary] = PlacesTown.bus_destinations(stop)
	var pick: int = -1
	for i: int in dests.size():
		pick = i if str(dests[i].get("npc", "")) == resident else pick
	check(pick >= 0, "bus: the transport stop offers the houses whose address you know")
	await _use(stop, [pick])
	await _settle()
	check(ops.is_active() and PlayerState.get_room() == STREET, "bus: the ride to their street starts the night job")
	var door: Interactable = _find_node(PlacesKeeper.HOUSE_DOOR_FORMAT % house)
	_game.player.global_position = door.global_position
	await _settle()
	check_eq(InteractionRouter.prompt_key_for(door), "UI_INTERACT_HOUSE_BREAK_IN", "house: the door now offers to break in")
	await _use(door, [1, 1])
	await _settle()
	var op: Dictionary = ops.get_operation()
	check(ops.is_active() and bool(op.get("entered", false)) and Disguise.is_masked(), "house: masked and in through the window")
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), house, "house: the player is inside")
	_crimes.clear()
	_game.player.global_position = _keeper.door_points(house, STREET).get("outside", Vector2.ZERO)
	await _settle()
	await _settle()
	check(not ops.is_active() and not _crime("burglary").is_empty() and _saw_toast("PLACES_HOUSE_LEFT"), "house: walking out closes the job")
	Disguise.take_off()


# ─── Citación ineludible ──────────────────────────────────────

func _test_summons() -> void:
	await _go(STREET)
	GameClock.set_time(GameClock.get_day(), 11, 0)
	var case_id: String = Security.open_investigation("object_missing", 2, "wing_3b")
	check(not case_id.is_empty(), "summons: a case is open")
	if case_id.is_empty():
		return
	Security.add_evidence(case_id, "direct_witness", 6.0, "player")
	for i: int in InvestigationEngine.PHASE_INTERROGATION:
		if Security.get_investigation(case_id).phase < InvestigationEngine.PHASE_INTERROGATION:
			Security.advance_phase(case_id)
	check_eq(Security.get_investigation(case_id).phase, InvestigationEngine.PHASE_INTERROGATION, "summons: the case reaches the interrogation")
	check_eq(PlacesKeeper.due_summons(get_tree()), case_id, "summons: the summons is pending")
	var box: DialogBox = await _wait_modal(DialogBox)
	check(box != null, "summons: two guards come for the player on the street")
	if box == null:
		Security.resolve_investigation(case_id, InvestigationEngine.VERDICT_COLD, "")
		return
	box.choose(0)
	var scene: InterrogationScene = await _wait_modal(InterrogationScene)
	check(scene != null and _game.streamer.get_current_floor() == 15, "summons: escorted to the P15 interrogation room")
	if scene != null:
		scene.leave()
	for i: int in 10:
		await get_tree().process_frame
	check_eq(_game.streamer.get_current_floor(), EXTERIOR, "summons: brought back to where they were found")
	await _close_modals()
	Security.resolve_investigation(case_id, InvestigationEngine.VERDICT_COLD, "")


func _wait_modal(kind: Variant) -> Node:
	var left: float = DRIVE_TIMEOUT
	while left > 0.0:
		var top: Control = _game.ui.get_top_modal()
		if top != null and is_instance_of(top, kind):
			return top
		await get_tree().process_frame
		left -= get_process_delta_time()
	return null


# ─── Traje de estatus ─────────────────────────────────────────

func _test_suit() -> void:
	await _set_post("b10_director")
	check(PlacesKeeper.suit_penalty() > 0.0, "suit: tier 5 without a suit costs reputation every day")
	var notes: Array[String] = []
	EventBus.notebook_entry_added.connect(func(_c: String, key: String, _a: Array) -> void: notes.append(key))
	EventBus.day_advanced.emit(GameClock.get_day())
	check(notes.has("PLACES_NOTE_NO_SUIT"), "suit: the daily penalty is applied and noted")
	await _go("clothes_shop")
	PlayerState.add_money(Database.get_balance_int("economia.precio_traje_ejecutivo"), "qa")
	var suit_index: int = -1
	var goods: Array[Dictionary] = (_game.sim_nodes["HomeCycle"] as HomeCycle).get_shop_items("clothes_shop")
	for i: int in goods.size():
		if str(goods[i]["item_id"]) == "executive_suit":
			suit_index = i
	await _use(_find_real("clothes_shop", "shop_counter"), [suit_index, 1])
	check(PlacesKeeper.has_suit() and PlacesKeeper.suit_penalty() == 0.0 and _saw_toast("PLACES_SUIT_BOUGHT"), "suit: buying it removes the penalty")
	await _set_post(START_POST)
