# world_bridges.gd — Pegamento de la escena de juego: oyentes que necesitan el mundo (fin de partida, Aurora, puertas denegadas, citación a interrogatorio, zona casa/trabajo, dormir, sentarse al ordenador) y objetos soltados en el suelo.
# PROPIETARIO DE: los objetos soltados (planta, sala, posición; se guardan con la partida), las citaciones pendientes, la zona casa/trabajo del jugador, la postura sentada ante el ordenador y el sueño en curso.
# ESCUCHA: game_over, aurora_meeting_started, interrogation_started, room_entered; FloorStreamer.floor_loaded y door_access_requested.
class_name WorldBridges
extends Node

## GameRoot lo añade con setup(root, streamer, player, ui, travel). Contratos:
##  · game_over(causa, final) → GameRoot.end_run (para el mundo → epílogo → menú; SaveSystem borra
##    la partida: permadeath §12.7).
##  · aurora_meeting_started → IdeaPresentation.summon_attendees() (los convocados van a la sala).
##  · Puerta que no se abre al jugador (FloorStreamer.door_access_requested) → pitido card_denied
##    en la puerta + aviso con la acreditación que pide (una vez cada puentes.segundos_aviso_puerta).
##  · interrogation_started de un caso con el jugador en la lista corta → aviso; en cuanto está
##    libre dentro del edificio en horario laboral, dos vigilantes le acompañan (diálogo sin
##    cancelar) a la sala de interrogatorios (puentes.sala_interrogatorio): InterrogationScene y,
##    al terminar, vuelta a donde estaba.
##  · Zona casa/trabajo: zone_of(sala) = "home" (hogar.sala_domicilio), "work" (el edificio y la nave)
##    o "" (la calle). El trayecto casa ↔ trabajo lo cobra FloorTravel (opción de la puerta del piso y
##    de recepción); andar por la calle no cobra nada más. Entrar en casa de noche recuerda cómo dormir.
##  · DORMIR (§4.2, §12.7): request_sleep() (cama del piso con E, o T en casa de noche) comprueba
##    HomeCycle.can_sleep(), pide confirmación y hace HomeCycle.sleep() tras un fundido: resumen de
##    la jornada (UIRoot), cambio de jornada, GUARDADO (único punto de guardado) y desayuno.
##  · Ordenador propio abierto (UIRoot, clase "computer") en el despacho del puesto → el jugador se
##    sienta en su silla más cercana (animación sit_type); al cerrar vuelve a donde estaba.
##  · OBJETOS SOLTADOS: grupo item_drop_handlers → drop_player_item(id) deja una unidad llevada
##    (PlayerState.is_carrying) en el suelo como interactivo "dropped_item"; este script es también
##    el módulo del InteractionRouter para ese tipo (recoger = PlayerState.add_item). Se guardan
##    (grupo SaveSystemNode.SCENE_GROUP, clave SAVE_KEY) y reaparecen al cargar su planta.

signal item_dropped(item_id: String, room_id: String)
signal item_picked(item_id: String)

const GROUP := "world_bridges"
const DROP_GROUP := "item_drop_handlers"
const SAVE_KEY := "WorldDrops"
const DROP_TYPE := "dropped_item"
const DROP_PREFIX := "drop_%d"
const KIND_COMPUTER := "computer"
const SIT_ANIM := "sit_type"
const ZONE_HOME := "home"
const ZONE_WORK := "work"
const SFX_DENIED := "card_denied"
const B_DOOR_COOLDOWN := "puentes.segundos_aviso_puerta"
const B_INTERROGATION_ROOM := "puentes.sala_interrogatorio"
const B_SUMMONS_POLL := "puentes.segundos_citacion"
const B_SIT_RADIUS := "puentes.radio_silla_celdas"
const B_HOME := "hogar.sala_domicilio"
const B_EXTERIOR := "mundo.planta_exterior"
const NIGHT_BAND := "night"
const SLEEP_ICON := "sleep"
const SLEEP_YES := 0
const SLEEP_LOCK := "sleep"

## Pruebas: dormir sin diálogo ni fundido.
var instant: bool = false

var _root: GameRoot = null
var _streamer: FloorStreamer = null
var _player: Node2D = null
var _ui: UIRoot = null
var _travel: FloorTravel = null
var _drops: Array[Dictionary] = []
var _drop_serial: int = 0
var _summons: Array[String] = []
var _summoning: bool = false
var _summons_left: float = 0.0
var _zone: String = ""
var _door_cooldowns: Dictionary = {}
var _seated_from: Vector2 = Vector2.INF
var _seated_floor: int = 0
var _sleeping: bool = false
var _overlay: FloorTravel.TravelOverlay = null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(DROP_GROUP)
	add_to_group(SaveSystemNode.SCENE_GROUP)
	EventBus.game_over.connect(_on_game_over)
	EventBus.aurora_meeting_started.connect(_on_aurora_meeting_started)
	EventBus.interrogation_started.connect(_on_interrogation_started)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.run_started.connect(func(_seed: int) -> void: reset_for_new_run())
	var saved: Dictionary = SaveSystem.claim_scene_state(SAVE_KEY)
	if not saved.is_empty():
		load_state(saved)
	_overlay = FloorTravel.TravelOverlay.new()
	_overlay.name = "SleepOverlay"
	add_child(_overlay)


func setup(root: GameRoot, streamer: FloorStreamer, player: Node2D, ui: UIRoot, travel: FloorTravel) -> void:
	_root = root
	_streamer = streamer
	_player = player
	_ui = ui
	_travel = travel
	_streamer.floor_loaded.connect(_on_floor_loaded)
	_streamer.door_access_requested.connect(_on_door_access_requested)


static func find(tree: SceneTree) -> WorldBridges:
	return tree.get_first_node_in_group(GROUP) as WorldBridges if tree != null else null


func _process(delta: float) -> void:
	_tick_door_cooldowns(delta)
	_sync_seat()
	_summons_left -= delta
	if _summons_left <= 0.0:
		_summons_left = Database.get_balance_float(B_SUMMONS_POLL)
		_try_summons()


# ─── Persistencia ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY


func reset_for_new_run() -> void:
	_drops.clear()
	_drop_serial = 0
	_summons.clear()
	_zone = ""
	_clear_drop_nodes()


func save_state() -> Dictionary:
	return {"drops": _drops.duplicate(true), "serial": _drop_serial, "summons": _summons.duplicate(), "zone": _zone}


func load_state(data: Dictionary) -> void:
	_drops.clear()
	for entry: Variant in data.get("drops", []):
		if entry is Dictionary:
			_drops.append((entry as Dictionary).duplicate(true))
	_drop_serial = int(data.get("serial", _drops.size()))
	_summons.assign(data.get("summons", []))
	_zone = str(data.get("zone", ""))
	if _streamer != null and not _streamer.get_plan().is_empty():
		_on_floor_loaded(_streamer.get_current_floor())


# ─── Fin de partida y escenas ─────────────────────────────────

func _on_game_over(cause: String, ending_id: String, _snapshot: Dictionary) -> void:
	if _root != null:
		_root.end_run(cause, ending_id)


func _on_aurora_meeting_started(_meeting_id: String) -> void:
	IdeaPresentation.summon_attendees()


func _on_interrogation_started(case_id: String, _interrogator: String) -> void:
	if _summons.has(case_id) or not Security.is_player_in_shortlist(case_id):
		return
	_summons.append(case_id)
	_toast("WORLD_SUMMONS_NOTICE", [], ToastStack.KIND_WARN)


## Citación pendiente: se ejecuta cuando el jugador está libre en el edificio en horario laboral.
func _try_summons() -> void:
	if _summons.is_empty() or _summoning or _ui == null or _ui.has_modal() or _travel == null or _travel.is_busy():
		return
	if not GameClock.is_working_hours() or GameClock.is_paused() or PlayerState.get_floor() == Database.get_balance_int(B_EXTERIOR):
		return
	var case_id: String = _summons.pop_front()
	var inv: Investigation = Security.get_investigation(case_id)
	if inv == null or not inv.is_active() or inv.phase != InvestigationEngine.PHASE_INTERROGATION:
		return
	_run_summons(case_id)


func _run_summons(case_id: String) -> void:
	_summoning = true
	var name_text: String = _npc_name(Security.get_interrogator(case_id))
	await _ui.show_dialog("WORLD_SUMMONS_TITLE", "WORLD_SUMMONS_BODY", ["WORLD_SUMMONS_GO"], [name_text], true, false)
	var back_floor: int = _streamer.get_current_floor()
	var back_point: Vector2 = _player.global_position
	if _travel.teleport_to_room(str(Database.get_balance(B_INTERROGATION_ROOM))):
		var scene: InterrogationScene = InterrogationScene.open(_ui, case_id)
		await scene.closed
		if not SaveSystem.is_run_over():
			_travel.teleport(back_floor, back_point)
	_summoning = false


func get_pending_summons() -> Array[String]:
	return _summons.duplicate()


# ─── Puertas denegadas ────────────────────────────────────────

func _on_door_access_requested(door: Door) -> void:
	if door == null or _door_cooldowns.has(door.door_id):
		return
	_door_cooldowns[door.door_id] = Database.get_balance_float(B_DOOR_COOLDOWN)
	var audio: AudioDirector = AudioDirector.find(get_tree())
	if audio != null:
		audio.play_sfx(SFX_DENIED, door.global_position)
	if door.kind == Door.KIND_OLD_LOCK:
		_toast("WORLD_DOOR_OLD_LOCK", [], ToastStack.KIND_WARN)
	elif door.kind == Door.KIND_TURNSTILE:
		_toast("WORLD_TURNSTILE_DENIED", [door.clearance], ToastStack.KIND_WARN)
	else:
		_toast("WORLD_DOOR_DENIED", [door.clearance], ToastStack.KIND_WARN)


func _tick_door_cooldowns(delta: float) -> void:
	for door_id: String in _door_cooldowns.keys():
		_door_cooldowns[door_id] = float(_door_cooldowns[door_id]) - delta
		if float(_door_cooldowns[door_id]) <= 0.0:
			_door_cooldowns.erase(door_id)


# ─── Casa ↔ trabajo ───────────────────────────────────────────

func _on_room_entered(room_id: String, by_player: bool) -> void:
	if not by_player:
		return
	var zone: String = zone_of(room_id)
	if zone.is_empty():
		return
	var previous: String = _zone
	_zone = zone
	if zone == ZONE_HOME and previous != ZONE_HOME and GameClock.get_current_band() == NIGHT_BAND:
		_toast("HOME_HINT_SLEEP", [], ToastStack.KIND_INFO)


## "home" (el domicilio), "work" (el edificio y la nave) o "" (la calle y el resto del exterior).
static func zone_of(room_id: String) -> String:
	var base: String = DatabaseSystem.get_room_base_id(room_id)
	if base == str(Database.get_balance(B_HOME)):
		return ZONE_HOME
	var room: RoomData = Database.get_room(room_id)
	if room == null or room.floor == Database.get_balance_int(B_EXTERIOR):
		return ""
	return ZONE_WORK


func get_zone() -> String:
	return _zone


# ─── Dormir ───────────────────────────────────────────────────

func is_sleeping() -> bool:
	return _sleeping


## Cama del piso o T en casa de noche: motivo si no se puede, confirmación, fundido y
## HomeCycle.sleep() (resumen → jornada nueva → guardado → desayuno). true si durmió.
func request_sleep() -> bool:
	var home: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle if is_inside_tree() else null
	if home == null or _sleeping:
		return false
	var reason: String = home.can_sleep()
	if reason != HomeCycle.OK:
		_toast(HomeCycle.reason_key(reason), [], ToastStack.KIND_WARN)
		return false
	if _ui != null and not instant:
		var options: Array = [{"text_key": "SLEEP_CONFIRM", "icon": SLEEP_ICON}, "SLEEP_NOT_YET"]
		if await _ui.show_dialog("SLEEP_TITLE", "SLEEP_BODY", options, [GameClock.get_time_string()]) != SLEEP_YES:
			return false
	return await _sleep_now(home)


func _sleep_now(home: HomeCycle) -> bool:
	_sleeping = true
	_lock_player(true)
	var here: int = PlayerState.get_floor()
	await _overlay.play_in(SLEEP_ICON, here, here, TranslationServer.translate("SLEEP_CAPTION"), false, instant)
	var result: Dictionary = home.sleep()
	await _overlay.play_out(instant)
	_lock_player(false)
	_sleeping = false
	if not bool(result.get("ok", false)):
		_toast(HomeCycle.reason_key(str(result.get("reason", ""))), [], ToastStack.KIND_WARN)
		return false
	if bool(result.get("saved", false)):
		_toast("SLEEP_SAVED", [GameClock.get_day()], ToastStack.KIND_GOOD)
	else:
		_toast("SLEEP_NOT_SAVED", [], ToastStack.KIND_BAD)
	return true


func _lock_player(locked: bool) -> void:
	if _player != null and _player.has_method("set_input_locked"):
		_player.call("set_input_locked", locked, SLEEP_LOCK)


# ─── Sentarse ante el ordenador propio ────────────────────────

func _sync_seat() -> void:
	if _ui == null or _player == null:
		return
	var top: Control = _ui.get_top_modal()
	var at_computer: bool = top != null and str(top.get_meta(UIRoot.META_KIND, "")) == KIND_COMPUTER
	if at_computer and _seated_from == Vector2.INF:
		_sit_down()
	elif not at_computer and _seated_from != Vector2.INF:
		_stand_up()


func _sit_down() -> void:
	_seated_from = _player.global_position
	_seated_floor = _streamer.get_current_floor()
	var seat: Dictionary = _nearest_seat()
	if not seat.is_empty():
		_player.global_position = seat["pos"]
		if _player.has_method("set_facing") and seat.get("facing") is Vector2:
			_player.call("set_facing", seat["facing"])
	if _player.has_method("play_anim"):
		_player.call("play_anim", SIT_ANIM)


## Vuelve a donde estaba antes de sentarse (salvo si entretanto cambió de planta: ascenso, citación).
func _stand_up() -> void:
	if _streamer.get_current_floor() == _seated_floor:
		_player.global_position = _seated_from
	_seated_from = Vector2.INF
	if _player.has_method("play_anim"):
		_player.call("play_anim", "")


func _nearest_seat() -> Dictionary:
	var occupation: OccupationData = PlayerState.get_occupation()
	var room: String = _streamer.get_room_at(_player.global_position)
	if occupation == null or DatabaseSystem.get_room_base_id(room) != occupation.office_room:
		return {}
	var best: Dictionary = {}
	var best_d: float = Database.get_balance_float(B_SIT_RADIUS) * RoomBuilder.cell_px()
	for seat: Dictionary in _streamer.get_seats_in_room(room):
		var d: float = (seat["pos"] as Vector2).distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = seat
	return best


func is_seated() -> bool:
	return _seated_from != Vector2.INF


# ─── Objetos soltados ─────────────────────────────────────────

## Contrato de InventoryUI (grupo item_drop_handlers): deja una unidad en el suelo. false si no se lleva.
func drop_player_item(item_id: String) -> bool:
	if _player == null or _streamer == null or not PlayerState.is_carrying(item_id):
		return false
	if not PlayerState.remove_item(item_id):
		return false
	var pos: Vector2 = _player.global_position + Vector2(0.0, RoomBuilder.cell_px() * 0.3)
	_drop_serial += 1
	var entry: Dictionary = {"id": DROP_PREFIX % _drop_serial, "item_id": item_id, "floor": _streamer.get_current_floor(),
			"room_id": _streamer.get_room_at(_player.global_position), "x": pos.x, "y": pos.y}
	_drops.append(entry)
	_spawn_drop(entry)
	item_dropped.emit(item_id, str(entry["room_id"]))
	return true


## Recoge el objeto soltado `drop_id`. false si no existe o no cabe en el inventario.
func pick_up(drop_id: String) -> bool:
	for i: int in _drops.size():
		if str(_drops[i]["id"]) != drop_id:
			continue
		if not PlayerState.add_item(str(_drops[i]["item_id"])):
			_toast("WORLD_PICKUP_FULL", [], ToastStack.KIND_WARN)
			return false
		var item_id: String = str(_drops[i]["item_id"])
		_drops.remove_at(i)
		_free_drop_node(drop_id)
		item_picked.emit(item_id)
		return true
	return false


func get_drops() -> Array[Dictionary]:
	return _drops.duplicate(true)


static func handled_types() -> Array[String]:
	return [DROP_TYPE]


static func interact(interactable: Interactable, _player_node: Node, _ctx: Dictionary) -> void:
	var bridges: WorldBridges = find(interactable.get_tree()) if interactable.is_inside_tree() else null
	if bridges != null:
		bridges.pick_up(interactable.interact_id)


func _on_floor_loaded(floor_number: int) -> void:
	_clear_drop_nodes()
	for entry: Dictionary in _drops:
		if int(entry["floor"]) == floor_number:
			_spawn_drop(entry)


func _spawn_drop(entry: Dictionary) -> void:
	if _streamer == null or int(entry["floor"]) != _streamer.get_current_floor():
		return
	var node: DroppedItem = DroppedItem.new()
	node.setup(str(entry["id"]), DROP_TYPE, str(entry["room_id"]), {"item_id": entry["item_id"]},
			RoomBuilder.cell_px(), Vector2(float(entry["x"]), float(entry["y"])))
	node.add_to_group(GROUP + "_drops")
	_streamer.get_actor_layer().add_child(node)


func _free_drop_node(drop_id: String) -> void:
	for node: Node in get_tree().get_nodes_in_group(GROUP + "_drops"):
		if (node as Interactable).interact_id == drop_id:
			node.queue_free()


func _clear_drop_nodes() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(GROUP + "_drops"):
		node.queue_free()


# ─── Auxiliares ───────────────────────────────────────────────

func _toast(key: String, args: Array, kind: String) -> void:
	if _ui != null:
		_ui.toast(key, args, kind)


static func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null
	return npc.name if npc != null else TranslationServer.translate("WORLD_SUMMONS_GUARD")


## Objeto en el suelo: el icono del objeto sobre una sombra, con el realce de Interactable encima.
class DroppedItem extends Interactable:
	const ICON_RATIO := 0.55
	const SHADOW_RATIO := 0.32

	func _ready() -> void:
		z_as_relative = true
		z_index = 0

	func _draw() -> void:
		var item: ItemData = Database.get_item(str(data.get("item_id", "")))
		var size: float = cell_px * ICON_RATIO
		draw_circle(Vector2(0.0, size * 0.35), cell_px * SHADOW_RATIO, UITheme.color("shadow"))
		var icon: String = UITheme.icon_for_item(item.id, InventoryRules.get_kind(item)) if item != null else "box"
		var hot: bool = item != null and item.is_compromising()
		UITheme.draw_icon(self, icon, Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)),
				UITheme.color("hazard" if hot else "paper"), 2.0)
		super._draw()
