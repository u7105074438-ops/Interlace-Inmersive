# npc_routine_case.gd — Cuerpo de test_npc_routine: capa de personajes de la planta 3, asientos del ala 3B, salida por el ascensor a la cafetería (PB), sala real comunicada a NPCDirector, reparto de ruidos y decisiones.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## FloorStreamer (planta 3) + NPCLayer con la física parada: el caso avanza el mundo a mano
## (layer.advance) con el reloj fijo, para que sea determinista.

const FLOOR_3B := 3
const WING := "wing_3b"
const CAFETERIA := "cafeteria"
const CAFETERIA_FLOOR := 0
const SEVEN: Array[String] = ["npc_debbie_foyle", "npc_george_penn", "npc_nate_brackley",
	"npc_claudia_reeves", "npc_ray_cudmore", "npc_sonia_vail", "npc_bernard_lasker"]
const DT := 1.0 / 30.0
const WALK_STEPS := 60
const MAX_STEPS := 2400
## 10:20 (agenda de la semilla fija): los siete en el ala — sin escaqueo, café ni ronda.
const MORNING := 10
const MORNING_MINUTE := 20
const LUNCH := 13
const SETTLE_SECONDS := 8.0
const EXIT_KINDS: Array[String] = ["elevator", "stairs"]

var _streamer: FloorStreamer = null
var _layer: NPCLayer = null
var _cell: float = 48.0


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	GameClock.set_time(1, MORNING, MORNING_MINUTE)
	EventBus.time_band_changed.emit("arrival", "work_morning")
	for npc_id: String in SEVEN:
		check_eq(NPCDirector.get_location_at(npc_id, MORNING, MORNING_MINUTE), WING, "%s is scheduled in wing_3b at 10:20" % npc_id)
	EventBus.floor_changed.emit(0, FLOOR_3B)
	EventBus.room_entered.emit(WING, true)
	_build_world()
	_check_morning()
	await _check_card()
	_check_decision_and_noise()
	_check_lunch_departure()
	_check_arrival_at_cafeteria()
	_layer.queue_free()
	_streamer.queue_free()
	await get_tree().process_frame


func _set_hour(hour: int) -> void:
	GameClock.set_time(1, hour, 0)
	EventBus.hour_passed.emit(hour, 1)


func _build_world() -> void:
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(FLOOR_3B)
	_layer = NPCLayer.new()
	_layer.free_running = true
	add_child(_layer)
	_layer.set_physics_process(false)
	_layer.set_streamer(_streamer)
	_layer.sync_now()
	_advance(1.0)


func _advance(seconds: float) -> void:
	for i: int in roundi(seconds / DT):
		_layer.advance(DT)


func _seat_of(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var furniture: Array[Dictionary] = FloorLayout.room_furniture(Database.get_room(WING))
	for seat: Dictionary in _streamer.get_seats_in_room(WING):
		var index: int = int(seat["furniture_index"])
		if str(seat["owner"]) == npc_id or Vector2i(furniture[index]["pos"]) == npc.desk_position:
			return seat
	return {}


## 10:00 — los siete, sentados en su puesto (dibujados en su silla) y situados en NPCDirector.
func _check_morning() -> void:
	var seated: int = 0
	for npc_id: String in SEVEN:
		var node: NPCNode = _layer.get_node_for(npc_id)
		if not check(node != null, "%s has a node on floor 3 in the morning" % npc_id):
			continue
		var seat: Dictionary = _seat_of(npc_id)
		var chair: Vector2 = seat.get("pos", Vector2.INF)
		var dist: float = node.get_visual_position().distance_to(chair) / _cell
		if node.is_seated() and dist <= 1.0:
			seated += 1
		check_eq(NPCDirector.get_current_location(npc_id), WING, "%s is located in wing_3b by its node" % npc_id)
		check(NPCDirector.is_world_located(npc_id), "%s: the node (not the schedule) places it" % npc_id)
	check_eq(seated, SEVEN.size(), "the seven 3B characters are seated at their own desks at 10:00")
	check(_layer.get_nodes().size() <= Database.get_balance_int("lod.max_agentes_completo") + Database.get_balance_int("lod.max_agentes_medio"),
			"no more nodes than the LOD 0 + LOD 1 budget")
	var george: NPCNode = _layer.get_node_for(SEVEN[1])
	check(george != null and george.lod == NPCRuntime.LOD_FULL and george.perception.is_active(),
			"colleagues in the player's room run full perception (LOD 0)")


## §13.7: tocar a un personaje abre su ficha rápida (identidad N1 como mínimo).
func _check_card() -> void:
	var card: CharacterCard = _layer.open_card(SEVEN[0])
	if not check(card != null, "tapping a character opens its quick card"):
		return
	await get_tree().process_frame
	var names: Array[String] = []
	for label: Node in card.find_children("*", "Label", true, false):
		names.append((label as Label).text)
	check(names.has(NPCDirector.get_npc(SEVEN[0]).name), "the card shows the character's name")
	check(_layer.npc_at(_layer.get_node_for(SEVEN[0]).get_visual_position() + Vector2(0.0, -0.5 * _cell)) == _layer.get_node_for(SEVEN[0]),
			"a tap on the character's body finds it")
	_layer.close_card()
	await get_tree().process_frame
	check(_layer.get_card() == null, "the card closes")


## Decisiones y ruido llegan a los nodos: denunciar = caminar a Seguridad; esprint cerca = atención.
func _check_decision_and_noise() -> void:
	var sonia: NPCNode = _layer.get_node_for(SEVEN[5])
	if sonia == null:
		return
	EventBus.noise_emitted.emit(sonia.get_visual_position() + Vector2(0.0, 3.0 * _cell),
			Database.get_balance_float("ruido.radio_esprint"), "player")
	check(sonia.perception.get_attention_point().is_finite(), "a nearby sprint (EventBus) catches a colleague's attention")
	var bernard: NPCNode = _layer.get_node_for(SEVEN[6])
	EventBus.npc_decided.emit(bernard.npc_id, UtilityAI.REPORT_TO_SECURITY, {"trigger": "belief"})
	check(bernard.is_leaving() or bernard.get_errand_kind() == NPCNode.ERRAND_REPORT,
			"a report decision sends the chief off towards Security (P15)")
	check_eq(bernard.get_bubble_kind(), NPCBubble.KIND_REPORT, "…with the 'going to Security' bubble")
	_advance(SETTLE_SECONDS)


## 13:00 — quien come en la cafetería (PB) se levanta y camina hacia el ascensor o la escalera.
func _check_lunch_departure() -> void:
	_set_hour(LUNCH)
	EventBus.time_band_changed.emit("work_morning", "lunch")
	_layer.think_all()
	var leaving: int = 0
	for npc_id: String in SEVEN:
		var node: NPCNode = _layer.get_node_for(npc_id)
		var target: String = NPCDirector.get_location_at(npc_id, LUNCH, 0)
		if node == null or target != CAFETERIA:
			continue
		var exit: Vector2 = _exit_near(node.get_path_points())
		check(node.is_leaving() and not node.is_seated(), "%s stands up and leaves for lunch" % npc_id)
		check(exit.is_finite(), "%s paths to the elevator/stairs of floor 3" % npc_id)
		var before: float = node.get_visual_position().distance_to(exit)
		for i: int in WALK_STEPS:
			_layer.advance(DT)
		if is_instance_valid(node) and _layer.get_node_for(npc_id) != null:
			check(node.get_visual_position().distance_to(exit) < before, "%s walks towards it" % npc_id)
		leaving += 1
	check(leaving >= SEVEN.size() - 1, "at 13:00 the 3B characters head to the cafeteria (%d of 7)" % leaving)


func _exit_near(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.INF
	var last: Vector2 = points[points.size() - 1]
	for t: Dictionary in _streamer.get_plan().get("transit", []):
		var p: Vector2 = _streamer.cell_to_world(t["cell"])
		if EXIT_KINDS.has(str(t["kind"])) and p.distance_to(last) < _cell:
			return p
	return Vector2.INF


## Llegan al tránsito, desaparecen de la planta y NPCDirector los sitúa en la cafetería (PB).
func _check_arrival_at_cafeteria() -> void:
	var steps: int = 0
	while steps < MAX_STEPS and _any_leaving():
		_layer.advance(DT)
		steps += 1
	for npc_id: String in SEVEN:
		if NPCDirector.get_location_at(npc_id, LUNCH, 0) != CAFETERIA:
			continue
		check(_layer.get_node_for(npc_id) == null, "%s left floor 3" % npc_id)
		check_eq(NPCDirector.get_current_location(npc_id), CAFETERIA, "%s is now in the cafeteria" % npc_id)
		check_eq(NPCDirector.get_npc(npc_id).floor, CAFETERIA_FLOOR, "%s is on the ground floor" % npc_id)
		check(not NPCDirector.is_world_located(npc_id), "%s: the schedule places it again (node released)" % npc_id)


func _any_leaving() -> bool:
	for node: NPCNode in _layer.get_nodes():
		if node.is_leaving():
			return true
	return false
