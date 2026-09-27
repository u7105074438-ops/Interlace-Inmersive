# perception_case.gd — Cuerpo de test_perception: multiplicadores §7.3, llenado/vaciado, creencia parcial a media distancia, flagrancia solo con acto, muros y muebles bajos, testigos.
# PROPIETARIO DE: nada.
# ESCUCHA: EventBus.player_seen_partially, player_caught_redhanded, player_lost_from_sight (conexiones temporales).
extends TestCase

## Observadores reales (Perception con un personaje de la plantilla) frente a un jugador simulado
## (FakePlayer: la misma interfaz que Player). Física 2D real para la línea de visión: un muro en
## la capa 1 corta la vista; un mueble bajo en la capa 3 la reduce a ×0,4.

const OBSERVER := "npc_debbie_foyle"
const HARDLINER := "npc_bernard_lasker"
const WITNESS_A := "npc_george_penn"
const WITNESS_B := "npc_claudia_reeves"
const WITNESS_C := "npc_sonia_vail"
const FAR_OBSERVER := "npc_ray_cudmore"
const DT := 1.0 / 30.0
const EPS := 0.0005
const ACT := "drawer_forced"
const LEGIT_ROOM := "wing_3b"
const OTHER_WING := "wing_3a"
const RESTRICTED_ROOM := "cfo_office"
const MASKED_ROOM := "call_center"
const NIGHT_HOUR := 21
const DAY_HOUR := 10


## Jugador simulado con la interfaz de Player que Perception consulta.
class FakePlayer extends Node2D:
	var mode: String = "walk"
	var crouching: bool = false
	var act: String = ""
	var hiding: bool = false
	var dragging: bool = false

	func movement_mode() -> String:
		return mode

	func is_crouching() -> bool:
		return crouching

	func current_act() -> String:
		return act

	func is_hiding() -> bool:
		return hiding

	func is_dragging() -> bool:
		return dragging


var _partials: Array = []
var _caught: Array = []
var _lost: Array = []
var _cell: float = 48.0
var _player: FakePlayer = null


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	GameClock.set_time(1, DAY_HOUR, 0)
	EventBus.player_seen_partially.connect(func(n: String, c: float, l: String) -> void: _partials.append([n, c, l]))
	EventBus.player_caught_redhanded.connect(func(n: String, t: String, w: int) -> void: _caught.append([n, t, w]))
	EventBus.player_lost_from_sight.connect(func(n: String) -> void: _lost.append(n))
	_player = FakePlayer.new()
	add_child(_player)
	_check_multipliers()
	_check_exposure()
	await _check_fill_and_drain()
	await _check_medium_distance_is_partial()
	await _check_close_act_is_flagrant()
	await _check_legit_is_ignored()
	await _check_walls()
	await _check_low_furniture()
	await _check_cone_and_hardliner()
	await _check_witnesses()


# ─── Utilidades ───────────────────────────────────────────────

func _observer(npc_id: String, archetype: String, pos: Vector2, facing: Vector2) -> Perception:
	var p: Perception = Perception.new()
	add_child(p)
	p.global_position = pos
	p.setup(npc_id, archetype)
	p.set_view(facing, true)
	return p


func _exposure(crime: String) -> Dictionary:
	return {"noteworthy": not crime.is_empty(), "crime": crime, "hidden": false, "room": LEGIT_ROOM}


func _run(p: Perception, seconds: float, exposure: Dictionary) -> void:
	for i: int in roundi(seconds / DT):
		p.tick(DT, _player, exposure)


func _clear_events() -> void:
	_partials.clear()
	_caught.clear()
	_lost.clear()


func _physics_ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _body(layer: int, rect: Rect2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	add_child(body)
	return body


# ─── Casos ────────────────────────────────────────────────────

## §7.3: agachado ×0,5, inmóvil ×0,7, esprint ×1,8, obstrucción ×0,4, +0,01/punto, distancia inversa.
func _check_multipliers() -> void:
	var p: int = 60
	var walk: float = Perception.fill_rate(4.0, p, "walk", false, false)
	check(walk > 0.0, "a player in the cone fills the counter (%.3f/s at 4 m)" % walk)
	check_near(Perception.fill_rate(4.0, p, "crouch", true, false) / walk, 0.5, EPS, "crouching fills ×0.5")
	check_near(Perception.fill_rate(4.0, p, "still", false, false) / walk, 0.7, EPS, "standing still fills ×0.7")
	check_near(Perception.fill_rate(4.0, p, "still", true, false) / walk, 0.35, EPS, "crouched and still: ×0.5 × ×0.7")
	check_near(Perception.fill_rate(4.0, p, "sprint", false, false) / walk, 1.8, EPS, "sprinting fills ×1.8")
	check_near(Perception.fill_rate(4.0, p, "walk", false, true) / walk, 0.4, EPS, "low furniture in the way: ×0.4")
	check_near(Perception.fill_rate(2.0, p, "walk", false, false) / walk, 2.0, EPS, "distance: half the distance, twice the speed")
	var per_point: float = (Perception.fill_rate(1.0, p + 10, "walk", false, false) - Perception.fill_rate(1.0, p, "walk", false, false)) / 10.0
	check_near(per_point, 0.01, EPS, "perception adds +0.01 per point (at the reference distance)")
	var ratio: float = Database.get_balance_float("percepcion.mod_sospecha_por_punto") / Database.get_balance_float("percepcion.mod_perspicacia_por_punto")
	check_near(ratio, 0.5, EPS, "suspicion counts +0.005 per point (NPCDirector folds it into effective perception)")
	check(Perception.fill_rate(1.0, 0, "walk", false, false) > Database.get_balance_float("percepcion.velocidad_vaciado_base"),
			"at base conditions the counter drains slower than it fills")


## Exposición: acto, arrastre, sala sin acreditación, noche fuera de su puesto, escondido.
func _check_exposure() -> void:
	check(not bool(Perception.assess_exposure(_player, LEGIT_ROOM)["noteworthy"]), "being seen working in your own wing is normal")
	_player.act = ACT
	check_eq(Perception.assess_exposure(_player, LEGIT_ROOM)["crime"], ACT, "an illegal act in progress is what gets detected")
	_player.act = ""
	_player.dragging = true
	check_eq(Perception.assess_exposure(_player, LEGIT_ROOM)["crime"], Perception.CRIME_BODY_MOVED, "dragging a body is noteworthy")
	_player.dragging = false
	check_eq(Perception.assess_exposure(_player, RESTRICTED_ROOM)["crime"], Perception.CRIME_TRESPASS, "a room your clearance does not cover is trespass")
	GameClock.set_time(1, NIGHT_HOUR, 0)
	check_eq(Perception.assess_exposure(_player, OTHER_WING)["crime"], Perception.CRIME_TRESPASS, "at night, another department's wing is trespass")
	check_eq(Perception.assess_exposure(_player, LEGIT_ROOM)["crime"], "", "at night, your own workplace is still yours")
	GameClock.set_time(1, DAY_HOUR, 0)
	check_eq(Perception.assess_exposure(_player, OTHER_WING)["crime"], "", "by day, a wing of your clearance is fine")
	_player.hiding = true
	_player.act = ACT
	var hidden: Dictionary = Perception.assess_exposure(_player, LEGIT_ROOM)
	check(bool(hidden["hidden"]) and not bool(hidden["noteworthy"]), "a hidden player cannot be detected")
	_player.hiding = false
	_player.act = ""


## Llena dentro del cono; fuera se vacía a velocidad_vaciado_base; < 0,10 → reinicio y pérdida.
func _check_fill_and_drain() -> void:
	await _physics_ready()
	_clear_events()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(1.5 * _cell, 0.0)
	_player.mode = "still"
	_run(p, 0.2, _exposure(ACT))
	var filled: float = p.get_counter()
	check(filled > 0.0 and p.get_state() == Perception.STATE_PROGRESS, "inside the cone the counter fills (%.3f): state in progress" % filled)
	_run(p, 0.4, _exposure(ACT))
	check(p.get_counter() >= Database.get_balance_float("percepcion.umbral_parcial"), "…and keeps filling to partial perception")
	check_eq(p.get_state(), Perception.STATE_PARTIAL, "state partial at 0.45")
	var before: float = p.get_counter()
	_player.global_position = Vector2(-2.0 * _cell, 0.0)
	_run(p, 0.5, _exposure(ACT))
	check_near(before - p.get_counter(), 0.5 * Database.get_balance_float("percepcion.velocidad_vaciado_base"), 0.01,
			"outside the cone it drains at velocidad_vaciado_base (slower than it filled here)")
	_run(p, 3.0, _exposure(ACT))
	check(p.get_counter() == 0.0 and p.get_state() == Perception.STATE_NONE, "below 0.10 the counter resets")
	check_eq(_lost.size(), 1, "player_lost_from_sight emitted once when contact is lost")
	check(_caught.is_empty(), "no flagrancy without reaching 1.0")
	p.queue_free()


## §21 / PASO 10: a media distancia, aunque dure, solo creencia de certeza baja.
func _check_medium_distance_is_partial() -> void:
	_clear_events()
	var p: Perception = _observer(FAR_OBSERVER, "old_hand", Vector2.ZERO, Vector2.RIGHT)
	var mid: float = (p.get_identification_range_px() + p.get_range_px()) * 0.5
	_player.global_position = Vector2(mid, 0.0)
	_player.mode = "still"
	_player.act = ACT
	_run(p, 20.0, _exposure(ACT))
	check(p.get_counter() < Database.get_balance_float("percepcion.umbral_flagrancia"),
			"at medium distance (%.1f m) the counter never reaches full identification (%.2f)" % [mid / _cell, p.get_counter()])
	check_eq(_partials.size(), 1, "exactly one partial perception")
	if not _partials.is_empty():
		check_near(float(_partials[0][1]), Database.get_balance_float("creencias.certeza_parcial"), EPS, "…with certainty 0.35")
	check(_caught.is_empty(), "no flagrancy at medium distance")
	var best: float = 0.0
	for b: Belief in BeliefNet.get_beliefs_held_by(FAR_OBSERVER):
		if b.subject == "player":
			best = maxf(best, b.certainty)
	check(best > 0.0 and best < Database.get_balance_float("creencias.certeza_directa_completa"),
			"the observer holds a LOW-certainty belief (%.2f), not a high one" % best)
	_player.act = ""
	p.queue_free()


## De cerca y con un acto: parcial y después flagrancia con su tipo de delito, una sola vez.
func _check_close_act_is_flagrant() -> void:
	_clear_events()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(2.0 * _cell, 0.0)
	_player.act = ACT
	_run(p, 6.0, _exposure(ACT))
	check_eq(_caught.size(), 1, "full identification during an act → player_caught_redhanded once")
	if not _caught.is_empty():
		check_eq(_caught[0][1], ACT, "…with the act's crime type")
		check_eq(_caught[0][0], OBSERVER, "…by the observer")
	check_eq(_partials.size(), 1, "partial perception came first")
	check_eq(p.get_state(), Perception.STATE_FLAGRANT, "state flagrant")
	_player.act = ""
	p.queue_free()


## Visto de cerca haciendo su trabajo: nada que detectar.
func _check_legit_is_ignored() -> void:
	_clear_events()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(1.0 * _cell, 0.0)
	_player.mode = "walk"
	_run(p, 5.0, Perception.assess_exposure(_player, LEGIT_ROOM))
	check(p.get_counter() == 0.0 and _partials.is_empty() and _caught.is_empty(),
			"seen working at 1 m for 5 s: no counter, no belief, no flagrancy")
	var trespass: Dictionary = Perception.assess_exposure(_player, RESTRICTED_ROOM)
	_run(p, 5.0, trespass)
	check_eq(_caught.size(), 1, "the same observer catches a trespasser")
	if not _caught.is_empty():
		check_eq(_caught[0][1], Perception.CRIME_TRESPASS, "…as trespass")
	p.queue_free()


## Un muro (capa 1) corta la vista; sin él, se llena.
func _check_walls() -> void:
	_clear_events()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(3.0 * _cell, 0.0)
	var wall: StaticBody2D = _body(1, Rect2(Vector2(1.4 * _cell, -_cell), Vector2(0.3 * _cell, 2.0 * _cell)))
	await _physics_ready()
	check(not p.has_line_of_sight(_player.global_position), "a wall blocks the line of sight")
	_run(p, 2.0, _exposure(ACT))
	check(p.get_counter() == 0.0 and _partials.is_empty(), "behind a wall the counter does not fill")
	wall.free()
	await _physics_ready()
	_run(p, 0.5, _exposure(ACT))
	check(p.get_counter() > 0.0, "without the wall it fills")
	p.queue_free()


## Mueble bajo (capa 3) en medio: la misma exposición llena ×0,4.
func _check_low_furniture() -> void:
	var clear_p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(3.0 * _cell, 0.0)
	_player.mode = "still"
	_run(clear_p, 0.3, _exposure(ACT))
	var free_fill: float = clear_p.get_counter()
	clear_p.queue_free()
	var desk: StaticBody2D = _body(3, Rect2(Vector2(1.4 * _cell, -_cell * 0.5), Vector2(0.6 * _cell, _cell)))
	await _physics_ready()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_run(p, 0.3, _exposure(ACT))
	check_near(p.get_counter() / maxf(free_fill, 0.0001), 0.4, 0.02, "low furniture in between: ×0.4 (partial obstruction)")
	desk.free()
	p.queue_free()
	await _physics_ready()


## Fuera del cono no ve; el hardliner tiene el cono ampliado.
func _check_cone_and_hardliner() -> void:
	_clear_events()
	var p: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	_player.global_position = Vector2(-2.0 * _cell, 0.0)
	_run(p, 2.0, _exposure(ACT))
	check(p.get_counter() == 0.0, "behind the observer (outside the cone) nothing fills")
	var normal: Perception = _observer(HARDLINER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	var hard: Perception = _observer(HARDLINER, "hardliner", Vector2.ZERO, Vector2.RIGHT)
	check_near(hard.get_half_angle() / normal.get_half_angle(),
			Database.get_balance_float("percepcion.cono_angulo_hardliner") / Database.get_balance_float("percepcion.cono_angulo_base"),
			EPS, "hardliner uses cono_angulo_hardliner")
	var side: Vector2 = Vector2.RIGHT.rotated((normal.get_half_angle() + hard.get_half_angle()) * 0.5) * 3.0 * _cell
	check(hard.sees_point(side) and not normal.sees_point(side), "a point between both cone edges: only the hardliner sees it")
	p.queue_free()
	normal.queue_free()
	hard.queue_free()


## Testigos = OTROS observadores con el jugador a la vista en el instante de la flagrancia.
func _check_witnesses() -> void:
	_clear_events()
	_player.global_position = Vector2(2.0 * _cell, 0.0)
	var catcher: Perception = _observer(OBSERVER, "gossip", Vector2.ZERO, Vector2.RIGHT)
	var a: Perception = _observer(WITNESS_A, "snitch", Vector2(2.0 * _cell, 3.0 * _cell), Vector2.UP)
	var b: Perception = _observer(WITNESS_B, "climber", Vector2(5.0 * _cell, 0.0), Vector2.LEFT)
	var c: Perception = _observer(WITNESS_C, "rookie", Vector2(2.0 * _cell, -3.0 * _cell), Vector2.UP)
	await _physics_ready()
	_player.act = ACT
	_run(catcher, 5.0, _exposure(ACT))
	check_eq(_caught.size(), 1, "one flagrancy")
	if not _caught.is_empty():
		check_eq(int(_caught[0][2]), 2, "witnesses = the two others that see the player (the third looks away)")
	_player.act = ""
	for p: Perception in [catcher, a, b, c]:
		p.queue_free()
