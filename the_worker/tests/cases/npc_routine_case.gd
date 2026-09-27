# npc_routine_case.gd — Cuerpo de test_npc_routine: capa de personajes de la planta 3, asientos del ala 3B, ficha rápida (N1 y expediente completo), salida por el ascensor a la cafetería (PB) sin atascos, comensales sentados a la mesa, denuncia aplazada que aún acaba en flagrancia, indicador y bocadillos.
# PROPIETARIO DE: nada.
# ESCUCHA: EventBus.player_seen_partially, player_caught_redhanded (conexiones temporales).
extends TestCase

## FloorStreamer (planta 3) + NPCLayer con la física parada: el caso avanza el mundo a mano
## (layer.advance) con el reloj fijo, para que sea determinista. Dos mundos: la jornada (mañana →
## comida → cafetería) y, en una partida nueva, el jugador forzando el cajón del jefe.

const FLOOR_3B := 3
const WING := "wing_3b"
const CAFETERIA := "cafeteria"
const CAFETERIA_FLOOR := 0
const SEVEN: Array[String] = ["npc_debbie_foyle", "npc_george_penn", "npc_nate_brackley",
	"npc_claudia_reeves", "npc_ray_cudmore", "npc_sonia_vail", "npc_bernard_lasker"]
const DT := 1.0 / 30.0
const WALK_STEPS := 60
const MAX_STEPS := 2400
const MAX_CATCH_STEPS := 1200
## 10:20 (agenda de la semilla fija): los siete en el ala — sin escaqueo, café ni ronda.
const MORNING := 10
const MORNING_MINUTE := 20
const LUNCH := 13
const LUNCH_MINUTE := 30
const SETTLE_SECONDS := 8.0
const EXIT_KINDS: Array[String] = ["elevator", "stairs"]
const DRAWER := "lasker_drawer"
const ACT := "drawer_forced"
const DRAWER_OFFSET := Vector2(1.1, 0.35)
## Dos caminantes a menos de STACK_CELLS celdas «apilados»; como mucho MAX_STACK_SECONDS seguidos.
const STACK_CELLS := 0.25
const MAX_STACK_SECONDS := 2.0
const TRAIT_COUNT := 6


## Jugador simulado (grupo "player") con la interfaz de Player que Perception consulta.
class FakePlayer extends Node2D:
	var mode: String = "still"
	var act: String = ""

	func movement_mode() -> String:
		return mode

	func is_crouching() -> bool:
		return false

	func current_act() -> String:
		return act


var _streamer: FloorStreamer = null
var _layer: NPCLayer = null
var _cell: float = 48.0


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	_morning()
	for npc_id: String in SEVEN:
		check_eq(NPCDirector.get_location_at(npc_id, MORNING, MORNING_MINUTE), WING, "%s is scheduled in wing_3b at 10:20" % npc_id)
	_build_world()
	_check_morning()
	await _check_card()
	await _check_card_full_file()
	_check_decision_and_noise()
	_check_lunch_departure()
	_check_arrival_at_cafeteria()
	_check_cafeteria_tables()
	await _teardown()
	new_run()
	_morning()
	_build_world()
	await _check_reporter_still_catches()
	await _teardown()


func _morning() -> void:
	GameClock.set_time(1, MORNING, MORNING_MINUTE)
	EventBus.time_band_changed.emit("arrival", "work_morning")


func _set_hour(hour: int, minute: int = 0) -> void:
	GameClock.set_time(1, hour, minute)
	EventBus.hour_passed.emit(hour, 1)


func _build_world() -> void:
	EventBus.floor_changed.emit(0, FLOOR_3B)
	EventBus.room_entered.emit(WING, true)
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


func _teardown() -> void:
	_layer.queue_free()
	_streamer.queue_free()
	await get_tree().process_frame


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


## 10:20 — los siete, sentados en su puesto (dibujados en su silla) y situados en NPCDirector.
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
	check_eq(seated, SEVEN.size(), "the seven 3B characters are seated at their own desks at 10:20")
	check(_layer.get_nodes().size() <= Database.get_balance_int("lod.max_agentes_completo") + Database.get_balance_int("lod.max_agentes_medio"),
			"no more nodes than the LOD 0 + LOD 1 budget")
	var george: NPCNode = _layer.get_node_for(SEVEN[1])
	check(george != null and george.lod == NPCRuntime.LOD_FULL and george.perception.is_active(),
			"colleagues in the player's room run full perception (LOD 0)")


func _card_texts(card: CharacterCard) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


## §13.7: tocar a un personaje abre su ficha rápida (identidad N1 como mínimo).
func _check_card() -> void:
	var card: CharacterCard = _layer.open_card(SEVEN[0])
	if not check(card != null, "tapping a character opens its quick card"):
		return
	await get_tree().process_frame
	var texts: Array[String] = _card_texts(card)
	check(texts.has(NPCDirector.get_npc(SEVEN[0]).name), "the card shows the character's name")
	check(not texts.has(tr("PERS_SEC_TRAITS").to_upper()), "at N1 the personality profile stays locked")
	check(_layer.npc_at(_layer.get_node_for(SEVEN[0]).get_visual_position() + Vector2(0.0, -0.5 * _cell)) == _layer.get_node_for(SEVEN[0]),
			"a tap on the character's body finds it")
	_layer.close_card()
	await get_tree().process_frame
	check(_layer.get_card() == null, "the card closes")


## Con el expediente completo (intrusión en RR. HH.): carácter, los seis rasgos y sin aviso de bloqueo.
func _check_card_full_file() -> void:
	PlayerState.grant_full_file(SEVEN[1], "hr_intrusion")
	var card: CharacterCard = _layer.open_card(SEVEN[1])
	if not check(card != null, "the full-file card opens"):
		return
	await get_tree().process_frame
	var texts: Array[String] = _card_texts(card)
	check(texts.has(tr("PERS_SEC_CHARACTER").to_upper()) and texts.has(tr("PERS_SEC_TRAITS").to_upper()),
			"with the full file the card shows character and personality sections")
	var bars: int = 0
	for child: Node in card.find_children("*", "Control", true, false):
		bars += 1 if child is UITheme.MeterBar else 0
	check_eq(bars, TRAIT_COUNT, "…with the six trait bars")
	var locked_prefix: String = tr("CARD_LOCKED_FMT").get_slice("%", 0)
	var locked: bool = false
	for text: String in texts:
		locked = locked or text.begins_with(locked_prefix)
	check(not locked, "…and no locked-level hint")
	_layer.close_card()
	await get_tree().process_frame


## Decisiones y ruido llegan a los nodos: denunciar = caminar a Seguridad; esprint cerca = atención.
func _check_decision_and_noise() -> void:
	var sonia: NPCNode = _layer.get_node_for(SEVEN[5])
	if sonia == null:
		return
	EventBus.noise_emitted.emit(sonia.get_visual_position() + Vector2(0.0, 3.0 * _cell),
			Database.get_balance_float("ruido.radio_esprint"), "player")
	check(sonia.perception.get_attention_point().is_finite(), "a nearby sprint (EventBus) catches a colleague's attention")
	check(sonia.is_seated() and sonia.get_errand_kind().is_empty(), "…who turns but stays at the desk (a legal sprint is not investigated)")
	var bernard: NPCNode = _layer.get_node_for(SEVEN[6])
	EventBus.npc_decided.emit(bernard.npc_id, UtilityAI.REPORT_TO_SECURITY, {"trigger": "belief"})
	check(bernard.is_leaving() or bernard.get_errand_kind() == NPCNode.ERRAND_REPORT,
			"with the player out of sight, a report decision sends the chief off towards Security (P15) at once")
	check_eq(bernard.get_bubble_kind(), NPCBubble.KIND_REPORT, "…with the 'going to Security' bubble")
	_advance(SETTLE_SECONDS)


## 13:00 — quien come en la cafetería (PB) y sigue en la planta se levanta y camina hacia el
## ascensor o la escalera.
func _check_lunch_departure() -> void:
	_set_hour(LUNCH)
	EventBus.time_band_changed.emit("work_morning", "lunch")
	_layer.think_all()
	var expected: int = 0
	var leaving: int = 0
	for npc_id: String in SEVEN:
		var node: NPCNode = _layer.get_node_for(npc_id)
		if node == null or NPCDirector.get_location_at(npc_id, LUNCH, 0) != CAFETERIA:
			continue
		expected += 1
		var exit: Vector2 = _exit_near(node.get_path_points())
		check(node.is_leaving() and not node.is_seated(), "%s stands up and leaves for lunch" % npc_id)
		check(exit.is_finite(), "%s paths to the elevator/stairs of floor 3" % npc_id)
		var before: float = node.get_visual_position().distance_to(exit)
		for i: int in WALK_STEPS:
			_layer.advance(DT)
		if is_instance_valid(node) and _layer.get_node_for(npc_id) != null:
			check(node.get_visual_position().distance_to(exit) < before, "%s walks towards it" % npc_id)
		if node.is_leaving() or _layer.get_node_for(npc_id) == null:
			leaving += 1
	check(expected > 0, "some 3B characters lunch in the cafeteria (%d)" % expected)
	check_eq(leaving, expected, "at 13:00 every 3B character on the floor who lunches in the cafeteria heads there")


func _exit_near(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.INF
	var last: Vector2 = points[points.size() - 1]
	for t: Dictionary in _streamer.get_plan().get("transit", []):
		var p: Vector2 = _streamer.cell_to_world(t["cell"])
		if EXIT_KINDS.has(str(t["kind"])) and p.distance_to(last) < _cell:
			return p
	return Vector2.INF


## Llegan al tránsito, desaparecen de la planta y NPCDirector los sitúa en la cafetería (PB). Por
## el camino no van apilados (colas en las puertas).
func _check_arrival_at_cafeteria() -> void:
	var steps: int = 0
	var runs: Dictionary = {}
	var worst: int = 0
	while steps < MAX_STEPS and _any_leaving():
		_layer.advance(DT)
		steps += 1
		worst = maxi(worst, _track_stacks(runs))
	check(worst * DT <= MAX_STACK_SECONDS,
			"walkers never stay stacked on each other (longest overlap %.1f s)" % (worst * DT))
	for npc_id: String in SEVEN:
		if NPCDirector.get_location_at(npc_id, LUNCH, 0) != CAFETERIA:
			continue
		check(_layer.get_node_for(npc_id) == null, "%s left floor 3" % npc_id)
		check_eq(NPCDirector.get_current_location(npc_id), CAFETERIA, "%s is now in the cafeteria" % npc_id)
		check_eq(NPCDirector.get_npc(npc_id).floor, CAFETERIA_FLOOR, "%s is on the ground floor" % npc_id)
		check(not NPCDirector.is_world_located(npc_id), "%s: the schedule places it again (node released)" % npc_id)


## Pares de caminantes a menos de STACK_CELLS: fotogramas seguidos de cada par; devuelve el máximo.
func _track_stacks(runs: Dictionary) -> int:
	var walkers: Array[NPCNode] = []
	for node: NPCNode in _layer.get_nodes():
		if node.is_moving():
			walkers.append(node)
	var worst: int = 0
	var seen: Dictionary = {}
	for i: int in walkers.size():
		for j: int in range(i + 1, walkers.size()):
			if walkers[i].global_position.distance_to(walkers[j].global_position) < STACK_CELLS * _cell:
				var key: String = walkers[i].npc_id + "|" + walkers[j].npc_id
				seen[key] = int(runs.get(key, 0)) + 1
				worst = maxi(worst, int(seen[key]))
	runs.clear()
	runs.merge(seen)
	return worst


func _any_leaving() -> bool:
	for node: NPCNode in _layer.get_nodes():
		if node.is_leaving():
			return true
	return false


## 13:30 en la cafetería: quien se sienta de cara a la cámara lo hace A la mesa (el dibujo se
## mete en ella y el nodo queda en la silla, detrás de la mesa en el orden Y).
func _check_cafeteria_tables() -> void:
	_set_hour(LUNCH, LUNCH_MINUTE)
	_streamer.load_floor(CAFETERIA_FLOOR)
	EventBus.room_entered.emit(CAFETERIA, true)
	_layer.sync_now()
	_advance(1.0)
	var tuck: float = Database.get_balance_float("npc_nodo.recogida_mesa_frontal") * _cell
	var front: int = 0
	var tucked: int = 0
	for node: NPCNode in _layer.get_nodes():
		var facing: Vector2 = node.get_spot().get("facing", Vector2.ZERO)
		if not node.is_seated() or _layer.room_at(node.global_position) != CAFETERIA or facing.dot(Vector2.DOWN) < 0.5:
			continue
		front += 1
		if absf(node.get_visual_position().y - node.global_position.y - tuck) < 1.0:
			tucked += 1
	check(front > 0, "diners face the camera at the cafeteria tables (%d)" % front)
	check_eq(tucked, front, "…each drawn %.1f cells into the table, the node kept on the chair" % (tuck / _cell))


# ─── Denuncia aplazada (partida nueva) ─────────────────────────

func _drawer_point() -> Vector2:
	for item: Interactable in _streamer.get_interactables_in_room(WING):
		if item.interact_id == DRAWER:
			return item.global_position + DRAWER_OFFSET * _cell
	return Vector2.INF


## PASO 10 + §7.3: forzar el cajón del jefe ante la plantilla. Quien le ve de reojo decide
## denunciar, pero no se marcha mientras le vigila: sigue mirando y el acto acaba en flagrancia.
func _check_reporter_still_catches() -> void:
	var player: FakePlayer = FakePlayer.new()
	add_child(player)
	player.add_to_group(NPCLayer.PLAYER_GROUP)
	player.global_position = _drawer_point()
	player.act = ACT
	var reporters: Array[String] = []
	var caught: Array[String] = []
	var on_partial: Callable = func(npc_id: String, _c: float, _l: String) -> void:
		if reporters.is_empty():
			reporters.append(npc_id)
			EventBus.npc_decided.emit(npc_id, UtilityAI.REPORT_TO_SECURITY, {"trigger": NPCDirectorSystem.TRIGGER_BELIEF})
	var on_caught: Callable = func(npc_id: String, _t: String, _w: int) -> void: caught.append(npc_id)
	EventBus.player_seen_partially.connect(on_partial)
	EventBus.player_caught_redhanded.connect(on_caught)
	var watch: Dictionary = await _run_act(reporters, caught)
	EventBus.player_seen_partially.disconnect(on_partial)
	EventBus.player_caught_redhanded.disconnect(on_caught)
	check(not reporters.is_empty(), "a colleague glimpses the player forcing the drawer (partial perception)")
	check(bool(watch["deferred"]), "the report decision is postponed while that observer keeps watching")
	check(not bool(watch["left"]), "…the observer does not walk off to Security mid-act")
	check(not caught.is_empty(), "the act in front of a would-be reporter still ends in player_caught_redhanded")
	await _check_indicator_and_bubbles(caught, reporters)
	check(_layer.observers_present(), "with colleagues watching, there are observers (no time skipping)")
	check(not GameClock.advance_to_band("night"), "…so GameClock.advance_to_band refuses to skip to the night")
	player.global_position = Vector2(-1000.0, -1000.0) * _cell
	check(not _layer.observers_present(), "out of everyone's reach and sight: no observers")
	player.queue_free()


## Avanza hasta la flagrancia: {deferred, left} del primer observador que decidió denunciar.
func _run_act(reporters: Array[String], caught: Array[String]) -> Dictionary:
	var out: Dictionary = {"deferred": false, "left": false}
	var steps: int = 0
	while caught.is_empty() and steps < MAX_CATCH_STEPS:
		_layer.advance(DT)
		steps += 1
		if reporters.is_empty() or not caught.is_empty():
			continue
		var node: NPCNode = _layer.get_node_for(reporters[0])
		if node == null or node.is_leaving() or node.get_errand_kind() == NPCNode.ERRAND_REPORT:
			out["left"] = true
		elif node.get_pending_action() == UtilityAI.REPORT_TO_SECURITY:
			out["deferred"] = true
	return out


## §13.2: el indicador de quien pilla está en flagrancia y a la vista, sin «!» duplicado en
## bocadillo; la denuncia aplazada del que pilla se descarta; quien no ve al jugador no lo muestra.
func _check_indicator_and_bubbles(caught: Array[String], reporters: Array[String]) -> void:
	if caught.is_empty():
		return
	var catcher: NPCNode = _layer.get_node_for(caught[0])
	if not check(catcher != null, "the catcher is on the floor"):
		return
	_layer.advance(DT)
	await get_tree().process_frame
	check_eq(catcher.perception.get_state(), Perception.STATE_FLAGRANT, "the catcher's counter is in the flagrancy state")
	check(catcher.indicator.visible, "…and its detection indicator is on screen")
	check(catcher.get_bubble_kind() != NPCBubble.KIND_EXCLAIM, "…without a duplicate '!' speech bubble next to it")
	if caught[0] == reporters[0]:
		check_eq(catcher.get_pending_action(), "", "the flagrancy drops the catcher's postponed report (CaughtHandler takes over)")
	var blind: int = 0
	for node: NPCNode in _layer.get_nodes():
		if node.perception.get_state() == Perception.STATE_NONE:
			blind += 1
			check(not node.indicator.visible, "%s does not see the player: no indicator" % node.npc_id)
	check(blind > 0, "some characters on the floor do not see the player (%d)" % blind)
