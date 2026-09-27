# noise_case.gd — Cuerpo de test_noise: radio efectivo con máscara acústica, giro hacia un esprint cercano (no en el call center), pasos normales ignorados, muros que atenúan, investigación solo si el ruido lo merece, reparto por NPCLayer.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Personajes reales (NPCNode sin capa, con su Perception) y, al final, la capa de la planta 2
## (call center) con EventBus.noise_emitted: el esprint dentro del call center no se oye.

const DT := 1.0 / 30.0
const EPS := 0.001
const LISTENER := "npc_george_penn"
## Sin tic de cabeza (el chivato mira a los lados por sí solo): para medir el giro hacia el ruido.
const TURNER := "npc_debbie_foyle"
const DULL_LISTENER := "npc_nate_brackley"
const WING := "wing_3b"
const CALL_CENTER := "call_center"
const MASKED_ROOMS: Array[String] = ["call_center", "boiler_room", "assembly_line", "main_copyroom"]
const PLAIN_ROOMS: Array[String] = ["wing_3b", "cafeteria", "cfo_office"]
const CALL_FLOOR := 2

var _cell: float = 48.0


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	GameClock.set_time(1, 10, 0)
	EventBus.hour_passed.emit(10, 1)
	_check_mask_radius()
	_check_turns_to_sprint()
	_check_normal_steps()
	_check_investigation()
	await _check_walls()
	await _check_layer_call_center()


func _node(npc_id: String, pos: Vector2, facing: Vector2) -> NPCNode:
	var node: NPCNode = NPCNode.new()
	node.setup(NPCDirector.get_npc(npc_id), null)
	add_child(node)
	node.global_position = pos
	node.set_lod(NPCRuntime.LOD_FULL)
	node.place_at({"pos": pos, "draw": pos, "facing": facing, "seated": false, "room": WING})
	node.step(DT)
	return node


func _steps(node: NPCNode, n: int) -> void:
	for i: int in n:
		node.perceive(DT, null, {})
		node.step(DT)


## §7.3: las máscaras reducen el radio efectivo al 15 % (ruido.reduccion_por_mascara).
func _check_mask_radius() -> void:
	var sprint: float = Database.get_balance_float("ruido.radio_esprint")
	var factor: float = Database.get_balance_float("ruido.reduccion_por_mascara")
	check_near(factor, 0.15, EPS, "the mask reduction is the manual's 15 %")
	for room: String in MASKED_ROOMS:
		check(Perception.is_masked_room(room), "%s is an acoustic mask" % room)
		check_near(Perception.effective_noise_radius(sprint, room), sprint * factor, EPS,
				"a sprint in %s is heard at %.2f m instead of %.1f m" % [room, sprint * factor, sprint])
	for room: String in PLAIN_ROOMS:
		check(not Perception.is_masked_room(room), "%s is not a mask" % room)
		check_near(Perception.effective_noise_radius(sprint, room), sprint, EPS, "full radius in %s" % room)


## PASO 11: esprintar junto a alguien le hace girarse; en el call center, no.
func _check_turns_to_sprint() -> void:
	var sprint: float = Database.get_balance_float("ruido.radio_esprint")
	var node: NPCNode = _node(TURNER, Vector2.ZERO, Vector2.DOWN)
	var origin: Vector2 = Vector2(4.0 * _cell, 0.0)
	check(node.head_direction().dot(Vector2.RIGHT) < 0.5, "the listener starts looking away from the noise")
	var masked: Dictionary = node.perception.hear(origin, sprint, "player", CALL_CENTER, false)
	node.on_heard(masked)
	_steps(node, 20)
	check(masked.is_empty(), "a sprint 4 m away inside the call center is not heard")
	check(node.head_direction().dot(Vector2.RIGHT) < 0.5, "…and nobody turns")
	var heard: Dictionary = node.perception.hear(origin, sprint, "player", WING, false)
	node.on_heard(heard)
	_steps(node, 20)
	check(not heard.is_empty(), "the same sprint in the wing is heard")
	check_eq(node.perception.get_attention_point(), origin, "attention goes to the noise origin")
	check(node.head_direction().dot(Vector2.RIGHT) > 0.9, "the listener turns towards the sprint")
	check(node.perception.get_view_direction().dot(Vector2.RIGHT) > 0.9, "…and so does the vision cone")
	node.free()


## Los pasos normales de alguien que no llama la atención no giran cabezas.
func _check_normal_steps() -> void:
	var walk: float = Database.get_balance_float("ruido.radio_normal")
	var node: NPCNode = _node(LISTENER, Vector2.ZERO, Vector2.DOWN)
	var origin: Vector2 = Vector2(2.0 * _cell, 0.0)
	check(node.perception.hear(origin, walk, "player", WING, false).is_empty(),
			"normal footsteps of a player doing nothing wrong are ignored")
	check(not node.perception.hear(origin, walk, "player", WING, true).is_empty(),
			"the same footsteps are noticed while the player is somewhere they should not be")
	check(node.perception.hear(Vector2(5.0 * _cell, 0.0), walk, "player", WING, true).is_empty(),
			"…but only within the radius (3.5 m)")
	node.free()


## Investiga (camina al origen) si su perspicacia supera el umbral, no ve el origen y el ruido lo
## merece: del jugador digno de atención o ajeno y fuerte. Un esprint legal solo gira cabezas.
func _check_investigation() -> void:
	var sprint: float = Database.get_balance_float("ruido.radio_esprint")
	var threshold: float = Database.get_balance_float("percepcion.umbral_investigar_ruido")
	var sharp: NPCNode = _node(LISTENER, Vector2.ZERO, Vector2.DOWN)
	check(sharp.perception.get_perception_value() >= threshold, "the snitch's perception is above the threshold")
	var legit: Dictionary = sharp.perception.hear(Vector2(0.0, -4.0 * _cell), sprint, "player", WING, false)
	check(not legit.is_empty() and not bool(legit.get("investigate", true)),
			"a legitimate sprint behind a perceptive NPC: it turns its head but stays at its desk")
	var behind: Dictionary = sharp.perception.hear(Vector2(0.0, -4.0 * _cell), sprint, "player", WING, true)
	check(bool(behind.get("investigate", false)), "a perceptive NPC investigates a noteworthy player's noise it cannot see")
	var crash: float = Database.get_balance_float("ruido.radio_romper_objeto")
	var broken: Dictionary = sharp.perception.hear(Vector2(0.0, -5.0 * _cell), crash, "object", WING, false)
	check(bool(broken.get("investigate", false)), "…and something breaking nearby (%.0f m noise)" % crash)
	sharp.perception.set_view(Vector2.RIGHT, true)
	var seen: Dictionary = sharp.perception.hear(Vector2(3.0 * _cell, 0.0), sprint, "player", WING, true)
	check(not seen.is_empty() and not bool(seen.get("investigate", true)), "…but only looks if it can see the origin")
	sharp.free()
	var dull: NPCNode = _node(DULL_LISTENER, Vector2.ZERO, Vector2.DOWN)
	var close: Dictionary = dull.perception.hear(Vector2(0.0, -2.0 * _cell), sprint, "player", WING, true)
	check(not close.is_empty() and not bool(close.get("investigate", true)),
			"the oblivious one hears a noteworthy sprint right next to them but does not investigate")
	check(dull.perception.hear(Vector2(0.0, -4.0 * _cell), sprint, "player", WING, true).is_empty(),
			"headphones: a sprint 4 m away goes unnoticed (radius × oido_oblivious)")
	dull.free()


## Un muro (capa 1) entre el ruido y quien escucha reduce el radio a × factor_oido_muro.
func _check_walls() -> void:
	var sprint: float = Database.get_balance_float("ruido.radio_esprint")
	var factor: float = Database.get_balance_float("percepcion.factor_oido_muro")
	var node: NPCNode = _node(TURNER, Vector2.ZERO, Vector2.DOWN)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(0.3 * _cell, 20.0 * _cell)
	shape.shape = box
	shape.position = Vector2(1.5 * _cell, 0.0)
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var far: Vector2 = Vector2((sprint * factor + 1.0) * _cell, 0.0)
	var near: Vector2 = Vector2((sprint * factor - 1.0) * _cell, 0.0)
	check(node.perception.hear(far, sprint, "player", WING, false).is_empty(),
			"a sprint %.1f m away behind a wall is not heard (radius × %.1f)" % [far.x / _cell, factor])
	check(not node.perception.hear(near, sprint, "player", WING, false).is_empty(),
			"…the same sprint %.1f m away through the wall is heard" % [near.x / _cell])
	check(not node.perception.hear(Vector2(-(sprint - 1.0) * _cell, 0.0), sprint, "player", WING, false).is_empty(),
			"without a wall in between, the full radius applies")
	wall.free()
	node.free()


## Integración: NPCLayer reparte noise_emitted; en el call center nadie reacciona a un esprint.
func _check_layer_call_center() -> void:
	EventBus.floor_changed.emit(0, CALL_FLOOR)
	EventBus.room_entered.emit(CALL_CENTER, true)
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	streamer.load_floor(CALL_FLOOR)
	var layer: NPCLayer = NPCLayer.new()
	layer.free_running = true
	add_child(layer)
	layer.set_physics_process(false)
	layer.set_streamer(streamer)
	layer.sync_now()
	var operator: NPCNode = null
	for node: NPCNode in layer.get_nodes():
		if layer.room_at(node.get_visual_position()) == CALL_CENTER and node.lod == NPCRuntime.LOD_FULL:
			operator = node
	if not check(operator != null, "the call center has operators on duty at 10:00"):
		return
	var origin: Vector2 = Vector2.INF
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var candidate: Vector2 = operator.get_visual_position() + dir * 2.5 * _cell
		if not origin.is_finite() and layer.room_at(candidate) == CALL_CENTER:
			origin = candidate
	if not check(origin.is_finite(), "a point 2.5 m from the operator inside the call center"):
		return
	EventBus.noise_emitted.emit(origin, Database.get_balance_float("ruido.radio_esprint"), "player")
	check(not operator.perception.get_attention_point().is_finite(),
			"sprinting 2.5 m from an operator inside the call center (via EventBus): no reaction")
	var plain: Vector2 = operator.get_visual_position() + Vector2(0.0, 0.5 * _cell)
	operator.perception.hear(plain, Database.get_balance_float("ruido.radio_esprint"), "player", "", false)
	check(operator.perception.get_attention_point().is_finite(), "the same operator hears a sprint outside any mask")
	layer.queue_free()
	streamer.queue_free()
	await get_tree().process_frame
