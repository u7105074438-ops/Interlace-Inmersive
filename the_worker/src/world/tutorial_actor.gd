# tutorial_actor.gd — Figurante guionizado del tutorial (§13.8): un personaje real (su apariencia y su id) que camina rutas del plano, espera al jugador, gesticula, habla con bocadillo y, si se le pide, mira con una percepción real.
# PROPIETARIO DE: su ruta, su pose y su animación mientras actúa (el personaje sigue siendo de NPCDirector: su nodo real queda retirado por TutorialDirector con NPCDirector.set_lod).
# ESCUCHA: nada (TutorialDirector lo crea, lo mueve y lo libera).
class_name TutorialActor
extends CharacterBody2D

## Se mueve sin física como NPCNode (capa 5: los sensores de las puertas lo ven y, al estar en el
## grupo "npcs", las cerraduras le abren como a cualquier empleado; AudioDirector oye sus pasos).
## No lleva interactivo ni entra en NPCLayer: no es un NPCNode (no piensa, no tiene agenda).
## Correa (set_leash): si el jugador se queda atrás más de `leash_px` respecto al destino, el
## figurante se detiene y le mira hasta que se acerca (un guía que acompaña, no que huye).
## enable_perception(): cono y contador reales (Perception + DetectionIndicator) con los rasgos de
## su personaje; ver al jugador trabajando no crea creencias (Perception: «verte trabajar es normal»).

signal arrived()

const GROUP := "npcs"
const LAYER_NPC := 5
const ANIM_IDLE := "idle"
const ANIM_WALK := "walk"
const ANIM_SIT := "sit"
const CELL_PATH := "mundo.px_por_unidad"
const RADIUS_PATH := "jugador.radio_colision"
const ARRIVE_PX := 4.0
const BUBBLE_TALK := "talk"

var npc_id: String = ""
var occupation_id: String = ""
var tier: int = 1
## Tests / QA: multiplica la velocidad de marcha.
var speed_scale: float = 1.0
var perception: Perception = null
var _app: Dictionary = {}
var _archetype: String = ""
var _streamer: FloorStreamer = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_i: int = 0
var _speed_px: float = 0.0
var _facing: Vector2 = Vector2.DOWN
var _look: Vector2 = Vector2.ZERO
var _anim: String = ANIM_IDLE
var _pose: String = ""
var _frame: int = 0
var _anim_clock: float = 0.0
var _leash: Node2D = null
var _leash_px: float = 0.0
var _waiting: bool = false
var _bubble: NPCBubble = null
var _indicator: DetectionIndicator = null
var _cell: float = 48.0


## Personaje `npc` con su apariencia (o `appearance` si se da) andando a `speed_cells` celdas/s.
func setup(npc: NPCRuntime, streamer: FloorStreamer, speed_cells: float, appearance: Dictionary = {}) -> void:
	npc_id = npc.id
	occupation_id = npc.occupation_id
	tier = clampi(npc.tier, 1, CharacterStyle.OUTFIT_COUNT)
	_archetype = npc.archetype
	_streamer = streamer
	_app = appearance if not appearance.is_empty() else CharacterPainter.appearance_for_npc(npc)
	_cell = Database.get_balance_float(CELL_PATH)
	_speed_px = speed_cells * _cell
	name = "TutorialActor_%s" % npc.id.validate_node_name()
	add_to_group(GROUP)
	collision_layer = 1 << (LAYER_NPC - 1)
	collision_mask = 0
	motion_mode = MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = Database.get_balance_float(RADIUS_PATH) * _cell
	shape.shape = circle
	add_child(shape)
	_bubble = NPCBubble.new()
	_bubble.name = "Bubble"
	add_child(_bubble)
	_bubble.position = Vector2(0.0, _head_top())


## Cono y contador reales con los rasgos del personaje (patrulla del jefe de ala).
func enable_perception() -> void:
	if perception != null:
		return
	perception = Perception.new()
	perception.name = "Perception"
	add_child(perception)
	perception.setup(npc_id, _archetype)
	perception.set_active(true)
	perception.set_view(_facing, true)
	_indicator = DetectionIndicator.new()
	_indicator.name = "DetectionIndicator"
	add_child(_indicator)
	_indicator.bind(perception)
	_indicator.position = Vector2(0.0, _head_top())


func get_appearance() -> Dictionary:
	return _app


func is_seated() -> bool:
	return _pose == ANIM_SIT


func is_moving() -> bool:
	return _path_i < _path.size()


func is_waiting() -> bool:
	return _waiting


## Camina hasta `point` por las rutas del plano (esquiva muros y muebles).
func walk_to(point: Vector2) -> void:
	var route: PackedVector2Array = PackedVector2Array()
	if _streamer != null:
		route = _streamer.find_path_to_point(global_position, point)
	route.append(point)
	_path = route
	_path_i = 0
	_pose = ""


func stop() -> void:
	_path = PackedVector2Array()
	_path_i = 0


## Espera al jugador: se para si `target` queda más lejos que `distance_px` del destino que él.
func set_leash(target: Node2D, distance_px: float) -> void:
	_leash = target
	_leash_px = distance_px


func face(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		_facing = dir.normalized()
		_look = Vector2.ZERO
		if perception != null:
			perception.set_view(_facing)
		queue_redraw()


func face_point(point: Vector2) -> void:
	face(point - global_position)


## Mira hacia `dir` sin girar el cuerpo (barrido de cabeza del jefe); ZERO = al frente.
func look(dir: Vector2) -> void:
	_look = dir
	if perception != null:
		perception.set_view(dir if dir.length_squared() > 0.0001 else _facing)
	queue_redraw()


## Pose fija mientras está quieto ("" = automática: idle / walk).
func set_pose(anim: String) -> void:
	if anim != _pose:
		_pose = anim
		_frame = 0
		_anim_clock = 0.0
		queue_redraw()


## Bocadillo de charla durante `seconds`.
func say(seconds: float) -> void:
	emote(BUBBLE_TALK, seconds)


func emote(kind: String, seconds: float) -> void:
	if _bubble != null:
		_bubble.show_emote(kind, seconds)


# ─── Fotograma ────────────────────────────────────────────────

## Tiempo de mundo como los NPC reales (NPCLayer.world_time_scale: quieto con el reloj en pausa,
## más lento en el ordenador o en la cámara lenta de la flagrancia).
func _physics_process(real_delta: float) -> void:
	var layer: NPCLayer = NPCLayer.find(get_tree())
	var delta: float = real_delta * (layer.world_time_scale() if layer != null else 1.0)
	if delta <= 0.0:
		return
	_waiting = _should_wait()
	if _waiting:
		face_point(_leash.global_position)
	else:
		_move(delta)
	_tick_anim(delta)
	if perception != null:
		var player: Node2D = get_tree().get_first_node_in_group(Player.GROUP) as Node2D
		var room: String = _streamer.get_room_at(player.global_position) if player != null and _streamer != null else ""
		perception.tick(delta, player, Perception.assess_exposure(player, room))


func _should_wait() -> bool:
	if _leash == null or not is_instance_valid(_leash) or not is_moving():
		return false
	var goal: Vector2 = _path[_path.size() - 1]
	var mine: float = global_position.distance_to(goal)
	var theirs: float = _leash.global_position.distance_to(goal)
	return theirs > mine + _leash_px


func _move(delta: float) -> void:
	if not is_moving():
		return
	var target: Vector2 = _path[_path_i]
	var to: Vector2 = target - global_position
	var step: float = _speed_px * speed_scale * delta
	if to.length() <= maxf(step, ARRIVE_PX):
		global_position = target
		_path_i += 1
		if not is_moving():
			arrived.emit()
		return
	global_position += to.normalized() * step
	if absf(to.normalized().dot(_facing)) < 0.999:
		face(to)


func _tick_anim(delta: float) -> void:
	var anim: String = ANIM_WALK if is_moving() and not _waiting else (_pose if not _pose.is_empty() else ANIM_IDLE)
	if anim != _anim:
		_anim = anim
		_frame = 0
		_anim_clock = 0.0
		queue_redraw()
	var fps: float = CharacterPainter.anim_fps(_anim)
	_anim_clock += delta
	while fps > 0.0 and _anim_clock >= 1.0 / fps:
		_anim_clock -= 1.0 / fps
		var next: int = CharacterAnim.next_frame(_anim, _frame)
		if next >= 0 and next != _frame:
			_frame = next
			queue_redraw()
		elif next < 0:
			break


func _draw() -> void:
	var pose: Dictionary = CharacterPainter.make_pose(_anim, _frame, _facing, {"look": _look})
	CharacterPainter.draw(self, _app, tier, pose)


func _head_top() -> float:
	var rig: CharacterRig = CharacterRig.build(_app, tier, CharacterPainter.make_pose(ANIM_IDLE, 0, Vector2.DOWN))
	return rig.head_c.y - rig.head_radii.y
