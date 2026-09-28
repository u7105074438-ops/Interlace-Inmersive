# interactions_security_case.gd — Cuerpo de test_interactions_security: el módulo de seguridad e infraestructura sobre la escena de juego real (grabaciones solo en la sala de monitores, rastros y copias, apagón con investigación, alarma nocturna, cerraduras y ruido, cajas, uniformes, carrito, armero, escondites, cuerpos por el montacargas hasta la compactadora, tarjeta robada y aviso de testigos).
# PROPIETARIO DE: nada (monta y libera la escena de juego; su carpeta de guardado se borra al final).
# ESCUCHA: EventBus.noise_emitted y crime_committed (solo para comprobar lo emitido).
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const MODULE := "res://src/world/interactions/security.gd"
const STORAGE_FORMAT := "user://test_interactions_security_%d"
const RUN_SEED := 7373
const FRAMES_SETTLE := 3
const WAIT_MS := 4000
const PLAYER := "player"
const EPS := 0.01

var _dir: String = ""
var _game: GameRoot = null
var _keeper: SecurityKeeper = null
var _noises: Array[Dictionary] = []
var _crimes: Array[Dictionary] = []


func run_case() -> void:
	allowed_engine_errors = 0
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	check(new_run(RUN_SEED), "Database loaded")
	InteractionRouter.reset()
	check(InteractionRouter.register_module(load(MODULE) as Script), "security module honours the router contract")
	_game = await _spawn_game()
	_keeper = SecurityKeeper.ensure(get_tree())
	if not check(_keeper != null, "SecurityKeeper joins the game scene"):
		return
	_keeper.instant = true
	_silence_npcs()
	EventBus.noise_emitted.connect(func(pos: Vector2, radius: float, source: String) -> void:
		_noises.append({"pos": pos, "radius": radius, "source": source}))
	EventBus.crime_committed.connect(func(crime: String, room: String, details: Dictionary) -> void:
		_crimes.append({"crime": crime, "room": room, "details": details}))
	_test_registry()
	await _test_monitor()
	await _test_reader_card()
	await _test_witness_warning()
	await _test_gear()
	await _test_hiding()
	await _test_bodies()
	await _test_records()
	await _test_forcing()
	await _test_power_cut()
	await _test_alarm()
	await _test_safes()
	_cleanup()


# ─── Montaje y conducción ─────────────────────────────────────

func _spawn_game() -> GameRoot:
	var game: GameRoot = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	game.request_overrides = {"mode": "new", "seed": RUN_SEED, "player_name": "Sam Sec", "skip_intro": true}
	game.epilogue_delay_override = 0.0
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.travel.instant = true
	game.time_skip.instant = true
	game.promotion.instant = true
	game.bridges.instant = true
	await _settle()
	return game


## Sin personajes activos: nadie mira ni sorprende (el aviso de testigos se prueba aparte). La capa
## deja de sincronizar; los nodos que quedan se congelan con la percepción apagada.
func _silence_npcs() -> void:
	_game.npc_layer.process_mode = Node.PROCESS_MODE_DISABLED
	for node: NPCNode in _game.npc_layer.get_nodes():
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.perception.set_active(false)


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _go(room_id: String) -> void:
	_game.travel.teleport_to_room(room_id)
	await _settle()
	_game.npc_layer.process_mode = Node.PROCESS_MODE_DISABLED


func _item(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var item: Interactable = node as Interactable
		if item != null and item.interact_type == interact_type and item.room_id == room_id:
			return item
	return null


func _item_id(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


## Interactivo de prueba (misma API que los de las salas) junto al jugador.
func _fake(interact_type: String, room_id: String, data: Dictionary) -> Interactable:
	var node: Interactable = Interactable.new()
	node.setup("test_" + interact_type, interact_type, room_id, data, RoomBuilder.cell_px(), Vector2.ZERO)
	_game.streamer.get_actor_layer().add_child(node)
	node.global_position = _game.player.global_position
	return node


## Arranca la interacción (como la tecla E) sin esperarla: devuelve {done}.
func _start(item: Interactable) -> Dictionary:
	var state: Dictionary = {"done": false}
	var ctx: Dictionary = InteractionRouter.build_context(item, _game.player)
	var runner: Callable = func() -> void:
		await SecurityInteractions.interact(item, _game.player, ctx)
		state["done"] = true
	runner.call()
	return state


func _wait(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


## Responde al diálogo de arriba con la opción `index` (false si no apareció).
func _answer(index: int) -> bool:
	if not await _wait(func() -> bool: return _game.ui.get_top_modal() is DialogBox):
		return false
	(_game.ui.get_top_modal() as DialogBox).choose(index)
	await wait_frames(2)
	return true


func _pick(index_of: Callable) -> bool:
	if not await _wait(func() -> bool: return _game.ui.get_top_modal() is FloorTravel.FloorSelectPanel):
		return false
	var panel: FloorTravel.FloorSelectPanel = _game.ui.get_top_modal() as FloorTravel.FloorSelectPanel
	panel.choose(int(index_of.call(panel)))
	await wait_frames(2)
	return true


func _finish(state: Dictionary, label: String) -> void:
	check(await _wait(func() -> bool: return bool(state["done"])), label + ": the interaction finishes")
	await wait_frames(2)


func _crime_seen(crime: String) -> bool:
	return _crimes.any(func(c: Dictionary) -> bool: return str(c["crime"]) == crime)


func _cleanup() -> void:
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	SaveSystem.delete_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


# ─── Registro ─────────────────────────────────────────────────

func _test_registry() -> void:
	var types: Array[String] = SecurityInteractions.handled_types()
	for t: String in ["monitor_console", "server_terminal", "backup_unit", "electrical_breaker", "alarm_panel",
			"safe", "floor_safe", "ceo_safe", "lock_old", "door_reader", "uniform_locker", "cleaning_cart",
			"tool_rack", "hiding_spot", "trash_chute", "repair_bench", "machine_controls", "car_sabotage", "body"]:
		check(types.has(t), "registry: security claims '%s'" % t)
	check(InteractionRouter.module_for("hiding_spot").resource_path == MODULE, "registry: the router sends hiding spots to security.gd")
	check(InteractionRouter.module_for("freight_panel").resource_path != MODULE, "registry: the freight elevator stays with FloorTravel")


func _records(record_type: String) -> int:
	return BeliefNet.get_records_about(PLAYER).filter(func(b: Belief) -> bool: return b.record_type == record_type).size()


func _cases_at(room_id: String) -> int:
	return Security.get_active_investigations().filter(func(i: Investigation) -> bool: return i.location == room_id).size()


func _cases_of(incident: String) -> int:
	return Security.get_active_investigations().filter(func(i: Investigation) -> bool: return i.incident_type == incident).size()


func _anywhere(interact_type: String) -> Interactable:
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var item: Interactable = node as Interactable
		if item != null and item.interact_type == interact_type and item.is_inside_tree():
			return item
	return null


# ─── Grabaciones (§5.5) ───────────────────────────────────────

func _test_monitor() -> void:
	Security.register_camera_footage("turnstiles", GameClock.get_day(), GameClock.get_hour())
	Security.register_camera_footage("main_reception", GameClock.get_day(), GameClock.get_hour())
	var before: int = Security.get_footage_list().size()
	check(before >= 2, "monitor: recordings of the player are on file (%d)" % before)
	var ids: Array[String] = []
	for entry: Dictionary in Security.get_footage_list():
		ids.append(str(entry["id"]))
	var ctx: Dictionary = {"ui_root": _game.ui, "streamer": _game.streamer}
	check_eq(await SecurityRecords.wipe_footage(_game.player, ctx, ids), 0, "monitor: outside the monitor room nothing can be erased")
	check_eq(Security.get_footage_list().size(), before, "monitor: the recordings survive outside the monitor room")
	var office: Interactable = _fake("monitor_console", "security_director_office", {})
	check_eq(SecurityRecords.prompt_key(office), "SECOPS_PROMPT_VIEW_FOOTAGE", "monitor: the director's console only views")
	office.queue_free()
	await _go("monitor_room")
	check_eq(PlayerState.get_room(), "monitor_room", "monitor: the player stands in the monitor room")
	var state: Dictionary = _start(_item("monitor_room", "monitor_console"))
	check(await _answer(1), "monitor: the console offers to erase every recording")
	check(await _answer(0), "monitor: erasing asks for confirmation")
	await _finish(state, "monitor")
	check_eq(Security.get_footage_list().size(), 0, "monitor: every recording of the player is gone")
	check_eq(_records(BeliefNetSystem.RECORD_FOOTAGE), 0, "monitor: BeliefNet lost the footage records too")
	check(_crime_seen("footage_deleted"), "monitor: erasing is the crime footage_deleted")


# ─── Tarjeta robada y clonada (§5.3) ──────────────────────────

func _test_reader_card() -> void:
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation("security_director")
	if not check(holder != null, "card: a security director exists"):
		return
	var card: ItemData = InventoryRules.make_item("stolen_card")
	card.extra["owner"] = holder.id
	check(PlayerState.add_item_data(card), "card: the stolen card goes into the inventory")
	var door: Door = null
	for d: Door in _game.streamer.get_doors():
		if door == null and d.kind == Door.KIND_READER and not DoorAccess.allows(d) and SecurityLocks.card_opens(d, card):
			door = d
	if not check(door != null, "card: a reader door here that the director's card opens"):
		return
	var point: Interactable = null
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var it: Interactable = node as Interactable
		if it != null and it.interact_type == "door_reader" and str(it.data.get("door_id", "")) == door.door_id:
			point = it
	if not check(point != null, "card: the keeper put a reader point at the door"):
		return
	check(SecurityInteractions.is_available(point, _game.player), "card: the reader point is offered with someone else's card")
	var logs: int = Security.get_access_log().size()
	await _finish(_start(point), "card")
	var last: Dictionary = Security.get_access_log().back() if Security.get_access_log().size() > logs else {}
	check_eq(str(last.get("card_owner", "")), holder.id, "card: the log names the card holder, not the player")
	check(door.is_open(), "card: the door opens")
	await _test_clone(holder.id)


func _test_clone(holder_id: String) -> void:
	var bench: Interactable = _fake("repair_bench", PlayerState.get_room(), {"actions": ["clone_card"]})
	var state: Dictionary = _start(bench)
	check(await _answer(0), "clone: the bench offers to clone the stolen card")
	await _finish(state, "clone")
	var clone: ItemData = null
	for item: ItemData in PlayerState.get_inventory():
		if item.id == "cloned_card":
			clone = item
	check(clone != null and str(clone.extra.get("owner", "")) == holder_id, "clone: a cloned card of the same holder")
	bench.queue_free()
	PlayerState.remove_item("stolen_card")
	PlayerState.remove_item("cloned_card")


# ─── Aviso de testigos ────────────────────────────────────────

func _test_witness_warning() -> void:
	var witness: NPCRuntime = NPCDirector.get_all_npcs()[0]
	var eyes: Perception = Perception.new()
	eyes.name = "TestEyes"
	_game.streamer.get_actor_layer().add_child(eyes)
	eyes.setup(witness.id, "hardliner")
	var here: Vector2 = _game.player.global_position
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if not SecurityKit.witnesses(_game.player).has(witness.id):
			eyes.global_position = here + dir * RoomBuilder.cell_px() * 1.5
			eyes.set_view(-dir, true)
	check(SecurityKit.witnesses(_game.player).has(witness.id), "witness: the test observer sees the player")
	var rack: Interactable = _fake("tool_rack", PlayerState.get_room(), {"contains": ["crowbar"]})
	var state: Dictionary = _start(rack)
	check(await _answer(0), "witness: the rack offers the crowbar")
	check(await _answer(1), "witness: doing it in front of someone asks first (and can be called off)")
	await _finish(state, "witness")
	check(not PlayerState.is_carrying("crowbar"), "witness: backing off takes nothing")
	eyes.queue_free()
	rack.queue_free()
	await wait_frames(2)


# ─── Equipo (§11.4, §22.3) ────────────────────────────────────

func _test_gear() -> void:
	await _go("security_locker_room")
	var locker: Interactable = _item_id("security_locker_room", "security_uniform_locker_a")
	var state: Dictionary = _start(locker)
	check(await _answer(0), "uniform: the locker offers the uniform")
	await _finish(state, "uniform")
	check_eq(PlayerState.get_disguise(), "uniform_security", "uniform: taking it puts it on (PlayerState disguise)")
	check(PlayerState.is_carrying("uniform_security"), "uniform: the uniform is in the inventory")
	check_eq(str(_game.player.get_appearance().get("uniform", "")), CharacterPainter.uniform_for_disguise("uniform_security"),
			"uniform: the player's clothes change")
	check(_crime_seen("theft_small"), "uniform: taking it is a theft")
	state = _start(locker)
	check(await _answer(0), "uniform: the locker offers to change back")
	await _finish(state, "uniform return")
	check_eq(PlayerState.get_disguise(), "", "uniform: changing back removes the disguise")
	check(not PlayerState.is_carrying("uniform_security"), "uniform: the uniform is back in the locker")
	await _go("cleaning_locker_room")
	await _finish(_start(_item("cleaning_locker_room", "cleaning_cart")), "cart")
	check(PlayerState.is_carrying("master_keys"), "cart: the master keys come off the cleaning cart")
	await _go("maintenance_workshop")
	state = _start(_item("maintenance_workshop", "tool_rack"))
	check(await _answer(0), "rack: the rack lists its tools")
	await _finish(state, "rack")
	check(PlayerState.is_carrying("lockpick"), "rack: the lockpick is taken")


# ─── Escondites (§11.3) ───────────────────────────────────────

func _test_hiding() -> void:
	await _go("freight_elevator_room")
	var spot: HidingSpot = _item_id("freight_elevator_room", "hide_freight_crates") as HidingSpot
	if not check(spot != null, "hiding: the freight room has its crates"):
		return
	check(PlayerState.add_item("food_basic"), "hiding: something to stash")
	check(PlayerState.stash_item("food_basic", spot.interact_id, "freight_elevator_room"), "hiding: stashed in the crates")
	var actions: Array[String] = SecurityBodies.spot_actions(spot, false)
	var state: Dictionary = _start(spot)
	check(await _answer(actions.find(SecurityBodies.A_RETRIEVE)), "hiding: the menu offers to take it out")
	check(await _pick(func(_p: FloorTravel.FloorSelectPanel) -> int: return 0), "hiding: the stash lists what's inside")
	await _finish(state, "retrieve")
	check(PlayerState.is_carrying("food_basic"), "hiding: the item is back in the inventory")
	actions = SecurityBodies.spot_actions(spot, false)
	state = _start(spot)
	check(await _answer(actions.find(SecurityBodies.A_HIDE)), "hiding: the menu offers to hide inside")
	await _finish(state, "hide")
	check(_game.player.is_hiding(), "hiding: the player is inside")
	check(bool(Perception.assess_exposure(_game.player, "freight_elevator_room")["hidden"]), "hiding: perception cannot see a hidden player")
	check_eq(SecurityInteractions.prompt_key(spot), "SECOPS_PROMPT_COME_OUT", "hiding: while hidden, E means come out")
	await _finish(_start(spot), "come out")
	check(not _game.player.is_hiding(), "hiding: E again brings the player out")
	PlayerState.dispose_item("food_basic", "test")


# ─── Cuerpos (§12.2, §14.7) ───────────────────────────────────

func _victim() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and npc.occupation_id != "security_director" and not npc.is_named:
			return npc.id
	return ""


func _test_bodies() -> void:
	var victim: String = _victim()
	NPCDirector.remove_npc(victim, "eliminated")
	await wait_frames(2)
	if not check(not NPCDirector.get_body_info(victim).is_empty(), "body: an elimination leaves a body record"):
		return
	NPCDirector.move_body(victim, "freight_elevator_room", "")
	_keeper.sync_floor()
	var body: BodyNode = _keeper.body_node(victim)
	if not check(body != null, "body: a body node lies in the room"):
		return
	await _finish(_start(body), "grab")
	check(_keeper.is_dragging() and _game.player.is_dragging(), "body: the player drags it")
	check(_game.player.get_mode_speed("drag") < _game.player.get_mode_speed("walk"), "body: dragging is slow")
	check_eq(str(NPCDirector.get_body_info(victim).get("room_id", "-")), "", "body: while dragged it is in transit (no room to be found in)")
	var exit: Interactable = _anywhere("exit")
	if exit != null:
		check(not SecurityBodies.is_body_target(exit), "body: a street exit is no way out for a body (freight only)")
	var elevator: Interactable = _anywhere("elevator_panel")
	if elevator != null:
		check_eq(str(_game.travel.refusal_for(elevator).get("key", "")), "TRAVEL_REFUSE_BULKY", "body: the passenger elevator refuses a body")
	var spot: HidingSpot = _item_id("freight_elevator_room", "hide_freight_crates") as HidingSpot
	_game.player.global_position = spot.global_position
	await _settle()
	check(not body.is_available(), "body: next to a hiding place the body yields the E key")
	await _finish(_start(spot), "hide body")
	var info: Dictionary = NPCDirector.get_body_info(victim)
	check(bool(info["hidden"]) and str(info["spot_id"]) == spot.interact_id, "body: hidden in the crates (NPCDirector)")
	check(not _keeper.is_dragging() and _keeper.body_node(victim) == null, "body: the node is gone once hidden")
	check(_crime_seen("body_moved"), "body: moving it is the crime body_moved")
	var state: Dictionary = _start(spot)
	check(await _answer(SecurityBodies.spot_actions(spot, false).find(SecurityBodies.A_PULL_BODY)), "body: the crates offer to pull it out")
	await _finish(state, "pull")
	check(_keeper.is_dragging(), "body: dragging it again")
	await _freight_round_trip(victim)
	await _chute(victim)


func _freight_round_trip(victim: String) -> void:
	await _game.travel.travel_to(_anywhere("freight_panel"), FloorTravel.make_destination(-2, "", "", "S2", true, 0))
	await _settle()
	check_eq(_game.streamer.get_current_floor(), -2, "freight: the body rides down to S2")
	check(_keeper.is_dragging() and _keeper.body_node(victim) != null, "freight: still dragging on arrival")
	var room: String = str(NPCDirector.get_body_info(victim).get("room_id", ""))
	check(_game.streamer.get_room_rect_px(room).has_area(), "freight: the body record moved to S2 (%s)" % room)
	await _game.travel.travel_to(_anywhere("freight_panel"), FloorTravel.make_destination(-1, "", "", "S1", true, 0))
	await _settle()
	check(_keeper.is_dragging() and _game.streamer.get_current_floor() == -1, "freight: and back up to S1")


func _chute(victim: String) -> void:
	var chute: Interactable = _item("trash_dock", "trash_chute")
	if not check(chute != null, "chute: the trash dock has its compactor"):
		return
	_game.player.global_position = chute.global_position
	await _settle()
	check_eq(SecurityInteractions.prompt_key(chute), "SECOPS_PROMPT_CHUTE_BODY", "chute: the prompt says what E will do")
	var state: Dictionary = _start(chute)
	check(await _answer(0), "chute: feeding a body asks for confirmation (irreversible)")
	await _finish(state, "chute")
	var info: Dictionary = NPCDirector.get_body_info(victim)
	check(str(info.get("spot_id", "")) == chute.interact_id and bool(info.get("hidden", false)), "chute: the body is in the compactor")
	check(SecurityBodies.is_disposed(victim) and SecurityBodies.bodies_in(chute.interact_id).is_empty(), "chute: gone for good, nothing to pull out")
	check(not _keeper.is_dragging() and _keeper.body_node(victim) == null, "chute: no body left to drag")


# ─── Rastros digitales y copias (§22.2) ───────────────────────

func _test_records() -> void:
	EventBus.crime_committed.emit("file_copied", "hr_office", {})
	check(_records(BeliefNetSystem.RECORD_CHAT_LOG) >= 1, "server: a copied file left a file/chat log about the player")
	await _go("server_room")
	var before: int = SecurityRecords.digital_traces().size()
	var state: Dictionary = _start(_item("server_room", "server_terminal"))
	check(await _answer(1), "server: the terminal offers to delete every trace")
	check(await _answer(0), "server: deleting asks for confirmation")
	await _finish(state, "server")
	check_eq(_records(BeliefNetSystem.RECORD_CHAT_LOG), 0, "server: the file/chat logs are gone")
	check(BeliefNet.get_records_about(PLAYER).any(func(b: Belief) -> bool: return b.location == "server_room"),
			"server: the server logged the access itself")
	check_eq(SecurityRecords.restore_queue().size(), before, "backups: every deletion waits in the restore queue")
	_age_queue()
	check(SecurityRecords.restore_due() >= 1, "backups: the nightly restore brings deleted traces back")
	check(_records(BeliefNetSystem.RECORD_CHAT_LOG) >= 1, "backups: the file/chat log is back")
	var chats: Array[Belief] = []
	chats.assign(BeliefNet.get_records_about(PLAYER).filter(func(b: Belief) -> bool: return b.record_type == BeliefNetSystem.RECORD_CHAT_LOG))
	SecurityRecords.delete_traces(chats, "server_room")
	await _go("backup_room")
	state = _start(_item("backup_room", "backup_unit"))
	check(await _answer(0), "backups: the unit offers to destroy the tapes")
	check(await _answer(0), "backups: destroying them asks for confirmation")
	await _finish(state, "backups")
	check(SecurityRecords.restore_queue().is_empty() and SecurityRecords.backups_destroyed_today(), "backups: tapes destroyed, the deletion is permanent")
	_age_queue()
	check_eq(SecurityRecords.restore_due(), 0, "backups: nothing comes back the next night")
	check_eq(_records(BeliefNetSystem.RECORD_CHAT_LOG), 0, "backups: the file/chat log stays deleted")
	EventBus.crime_committed.emit("file_copied", "hr_office", {})
	var late: Array[Belief] = []
	late.assign(BeliefNet.get_records_about(PLAYER).filter(func(b: Belief) -> bool: return b.record_type == BeliefNetSystem.RECORD_CHAT_LOG))
	SecurityRecords.delete_traces(late, "server_room")
	check(SecurityRecords.restore_queue().is_empty(), "backups: deleting after the tapes were wrecked leaves nothing to restore")
	_age_queue()
	SecurityRecords.restore_due()
	check_eq(_records(BeliefNetSystem.RECORD_CHAT_LOG), 0, "backups: a deletion after the wreck stays deleted")


## Simula la noche: los borrados de la cola pasan a ser de la jornada anterior.
func _age_queue() -> void:
	var aged: Array = []
	for entry: Variant in SecurityRecords.restore_queue():
		var e: Dictionary = entry
		e["day"] = GameClock.get_day() - 1
		aged.append(e)
	SecurityKit.set_flag(SecurityRecords.F_QUEUE, aged)


# ─── Cerraduras (§22.2) ───────────────────────────────────────

## Punto de candado que el keeper pone en el lado de fuera de la puerta de `inside` (lleva al jugador allí).
func _outer_lock(inside: String, interact_id: String) -> Interactable:
	var inner: Interactable = _item_id(inside, interact_id)
	if inner == null:
		return null
	var door_id: String = str(inner.data.get("door_id", ""))
	var door: Door = _game.streamer.get_door_by_id(door_id)
	var outside: String = door.room_b if door.room_a == inside else door.room_a
	await _go(outside)
	for node: Node in get_tree().get_nodes_in_group(SecurityKeeper.NODES_GROUP):
		var item: Interactable = node as Interactable
		if item != null and item.interact_type == "lock_old" and item.room_id == outside and str(item.data.get("door_id", "")) == door_id:
			_game.player.global_position = item.global_position + (item.global_position - door.to_global(door.gap_rect().get_center()))
			await _settle()
			return item
	return null


func _test_forcing() -> void:
	await _go("old_confidential_cage")
	var lock: Interactable = await _outer_lock("old_confidential_cage", "cage_padlock")
	if not check(lock != null, "cage: the padlock can be reached from outside the cage"):
		return
	check(_game.player.get_focused_interactable() == lock, "cage: standing outside the door, E focuses the padlock")
	check(SecurityLocks.lock_key(lock).is_empty(), "cage: no key of the player's fits the padlock")
	check_eq(SecurityLocks.lock_tool(lock), "lockpick", "cage: the lockpick can force it")
	var door: Door = SecurityLocks.lock_door(lock, {"streamer": _game.streamer})
	check(door != null and door.is_locked(), "cage: the padlocked door starts locked")
	_noises.clear()
	var state: Dictionary = _start(lock)
	check(await _answer(0), "cage: forcing asks first (it tells the noise radius)")
	await _finish(state, "force")
	var loud: Array[Dictionary] = _noises.filter(func(n: Dictionary) -> bool: return str(n["source"]) == "lock_forced")
	check(not loud.is_empty(), "cage: forcing makes noise")
	check_near(float(loud[0]["radius"]) if not loud.is_empty() else 0.0, 6.0, EPS, "cage: the padlock is heard 6 m away")
	check(_crime_seen("lock_forced"), "cage: forcing is the crime lock_forced")
	check(door != null and not door.is_locked(), "cage: the door is open after forcing")


func _test_keys() -> void:
	await _go("forgotten_corridor")
	var lock: Interactable = await _outer_lock("forgotten_corridor", "forgotten_door_lock")
	if not check(lock != null, "keys: the forgotten corridor's old lock is reachable from outside"):
		return
	check(_game.player.get_focused_interactable() == lock, "keys: standing outside the door, E focuses the old lock")
	check_eq(SecurityLocks.lock_key(lock), "keys_basic", "keys: the desk keys fit the old lock")
	var crimes: int = _crimes.size()
	await _finish(_start(lock), "keys")
	var door: Door = SecurityLocks.lock_door(lock, {"streamer": _game.streamer})
	check(door != null and not door.is_locked(), "keys: the old lock opens with the keys")
	check(not _crimes.slice(crimes).any(func(c: Dictionary) -> bool: return str(c["crime"]) == "lock_forced"), "keys: using your keys is no crime")
	check(not SecurityInteractions.is_available(lock, _game.player), "keys: an opened old lock stops offering itself")


# ─── Apagón (§22.1) ───────────────────────────────────────────

func _test_power_cut() -> void:
	await _go("electrical_room")
	var before: int = _cases_of("power_cut")
	var state: Dictionary = _start(_item("electrical_room", "electrical_breaker"))
	check(await _pick(func(p: FloorTravel.FloorSelectPanel) -> int: return p.index_of_floor(0)), "breaker: the panel lists the floors")
	check(await _answer(0), "breaker: cut the ground floor now")
	await _finish(state, "breaker")
	check(SecurityPower.is_blackout_on(0), "breaker: the ground floor is dark")
	check(_cases_of("power_cut") > before, "breaker: every blackout opens an investigation (power_cut)")
	await _test_keys()
	await _go("turnstiles")
	var cams: Array[SecurityCamera] = _game.streamer.get_cameras()
	check(not cams.is_empty() and cams.all(func(c: SecurityCamera) -> bool: return not c.is_active()), "blackout: every camera on the floor is off")
	check(_keeper.is_shade_visible(), "blackout: the floor goes dim")
	var readers: Array[Door] = _game.streamer.get_doors().filter(func(d: Door) -> bool: return d.kind == Door.KIND_READER)
	check(readers.all(func(d: Door) -> bool: return not d.is_locked()), "blackout: the card readers are down (doors unlocked)")
	GameClock.advance_minutes(SecurityKit.bf("apagon.minutos") + 1.0)
	check(await _wait(func() -> bool: return cams.all(func(c: SecurityCamera) -> bool: return c.is_active())),
			"blackout: power returns after the cut and the cameras record again")
	check(not _keeper.is_shade_visible(), "blackout: the lights come back")


# ─── Alarma nocturna ──────────────────────────────────────────

func _test_alarm() -> void:
	var day: int = GameClock.get_day()
	var hour: int = GameClock.get_hour()
	GameClock.set_time(day, 21, 0)
	check(SecurityPower.alarm_armed(0), "alarm: at night the floor's zone is armed")
	SecurityPower.disable_alarm_zone(0, "alarm_central")
	check(not SecurityPower.alarm_armed(0), "alarm: a disabled zone stays off tonight")
	SecurityKit.set_flag(SecurityPower.F_ALARM_OFF, {})
	var room: String = PlayerState.get_room()
	var cupboard: Interactable = _fake("lock_old", room, {"target": "test_cupboard", "keys_basic_opens": false})
	var before: int = _cases_at(room)
	var state: Dictionary = _start(cupboard)
	check(await _answer(0), "alarm: forcing on an armed floor warns first")
	await _finish(state, "alarm")
	check(_cases_at(room) > before, "alarm: forcing trips the alarm and a case opens in the room")
	cupboard.queue_free()
	GameClock.set_time(day, hour, 0)


# ─── Cajas y maquinaria ───────────────────────────────────────

func _test_safes() -> void:
	await _go("floor_safe")
	var safe: Interactable = _item_id("floor_safe", "floor_cash_safe")
	if not check(safe != null, "safe: the cash safe is on floor 5"):
		return
	await _finish(_start(safe), "safe locked")
	check(not PlayerState.is_carrying("cash_envelope"), "safe: without the combination it stays shut")
	check(PlayerState.add_item("safe_combination_note"), "safe: the written combination")
	var money: int = PlayerState.get_money()
	var state: Dictionary = _start(safe)
	check(await _answer(0), "safe: opening it asks for confirmation")
	await _finish(state, "safe open")
	check_eq(PlayerState.get_money() - money, SecurityKit.bi("cajas.efectivo_sobre"), "safe: the cash goes into the player's money")
	check(not PlayerState.is_carrying("cash_envelope"), "safe: no compromising envelope left in the pocket")
	var log: Array[Dictionary] = Security.get_access_log().filter(func(e: Dictionary) -> bool: return str(e["reader_id"]) == safe.interact_id)
	check(not log.is_empty(), "safe: the opening is logged")
	check(log.all(func(e: Dictionary) -> bool: return str(e["card_owner"]) != PLAYER), "safe: the opening log names no one without a card")
	var ceo: Interactable = _fake("ceo_safe", "ceo_office", {"requires": "combination"})
	await _finish(_start(ceo), "ceo safe")
	check(not PlayerState.is_carrying("ownership_documents"), "ceo safe: no combination, no documents")
	ceo.queue_free()
	await _test_infrastructure()


func _test_infrastructure() -> void:
	var owner_id: String = _victim()
	SecurityPower.sabotage_car("test_car", owner_id, "garage")
	check_eq(SecurityPower.apply_car_sabotage(GameClock.get_day() + 1), [owner_id], "car: the sabotaged car breaks down the next day")
	check_eq(NPCDirector.get_scheduled_location(owner_id, "arrival"), "garage", "car: its owner spends the morning in the garage")
	var controls: Interactable = _fake("machine_controls", PlayerState.get_room(), {"shuts_down": "assembly_line"})
	var state: Dictionary = _start(controls)
	check(await _answer(0), "machine: an emergency stop asks first")
	await _finish(state, "machine")
	var stop: Array[Dictionary] = _crimes.filter(func(c: Dictionary) -> bool: return str(c["crime"]) == "sabotage" and c["details"].has("company_loss"))
	check(not stop.is_empty(), "machine: the emergency stop is sabotage with a company loss")
	controls.queue_free()
