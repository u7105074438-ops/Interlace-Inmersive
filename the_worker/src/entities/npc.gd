# npc.gd — Personaje vivo de la planta (PASO 9, §14.4-§14.7, §20, §24.5): sigue su agenda, camina las rutas del plano, se sienta en su puesto, muestra tics y gestos, reacciona a sus decisiones y lleva su percepción, su indicador y su bocadillo.
# PROPIETARIO DE: el estado de presentación de su personaje (destino, ruta, sitio, pose, gesto, recado); su sala real se la comunica a NPCDirector (set_current_location).
# ESCUCHA: nada (NPCLayer le da cada fotograma y le reenvía decisiones, denuncias, ruidos, flagrancias e ideas).
class_name NPCNode
extends CharacterBody2D

## Contrato (BUILD_NOTES §14): grupo "npcs", npc_id, occupation_id, is_seated(), can_see_player(),
## set_debug_cones(on), get_perception(). Lo crea y lo libera NPCLayer (solo LOD 0/1 de la planta
## cargada); step(delta) cada fotograma, think() cada lod.intervalo_medio_segundos, perceive() solo
## en LOD 0. Se mueve sin física (capa 5 para los sensores de puertas y los clics): la ruta del
## FloorStreamer ya esquiva muros y muebles.
## DECISIONES:
##  · Destino = NPCDirector.get_location_at(ahora) y su actividad (agenda del día). Sala de otra
##    planta o "" (fuera del edificio) → camina al tránsito (ascensor/escalera, o la puerta de la
##    calle en la PB) y emite arrived_at_exit: NPCLayer lo sitúa allí (set_current_location +
##    release_current_location) y lo libera.
##  · Sitio: su puesto (asiento con su id o su desk_position; los "generated" por orden), una
##    silla libre (cafetería, reuniones) o una celda libre de la sala (NPCLayer reparte).
##  · Tics §14.6 por arquetipo (CharacterAnim.apply_tic) + conducta: old_hand lento y mirando la
##    anomalía, hardliner barre con la cabeza (y el cono), snitch mira a los lados a menudo,
##    oblivious nunca gira la cabeza, burnout se apoya en las paredes, coward retrocede medio
##    paso si el jugador se le acerca, climber acelera hacia despachos de superiores, escalón 4
##    se detiene a observar.
##  · Reacciones (npc_decided): denunciar → camina a Seguridad (npc_nodo.sala_denuncia_seguridad)
##    con walk_report y escudo; al superior → hacia su jefe; confrontar → se planta ante el
##    jugador señalando con «!»; chantaje → «moneda»; huir → sobresalto y carrera; cotilleo →
##    se acerca a un colega y charla («…»); descanso → a la sala de descanso de la planta
##    (npc_nodo.patron_sala_descanso). Las decisiones de franja (cotillear, descansar) solo si se
##    queda en la sala.
##  · Denunciar/confrontar mientras VIGILA al jugador (Perception.is_watching: contacto vivo con
##    algo digno de atención) se APLAZA: sigue mirándole (sospecha) hasta perder el contacto
##    (entonces sale el recado), hasta la flagrancia (se descarta: manda CaughtHandler) o como
##    mucho npc_nodo.espera_max_reaccion s. Así quien le ve de reojo puede llegar a pillarle.
##  · Bocadillos: sin «?» ni «!» mientras su indicador de detección está a la vista (no se
##    duplica el glifo); la bombilla de idea se apila encima del indicador.
##  · Tics §14.6: oblivious no se gira hacia ruidos ni charlas; incorruptible no echa vistazos
##    (postura estática y frontal); el hardliner sentado vigila («sit», con barrido de cabeza).
##  · Tránsito (NPCLayer.space_walkers): espera tras quien camina delante en su mismo sentido
##    (colas en las puertas), se aparta a su derecha ante quien viene de frente y se aparta más
##    (y se detiene) ante un escalón 7-8 (§14.5); un escalón 5-6 marca el paso de un subordinado
##    de su departamento que va al mismo sitio (le acompaña).
##  · El cono sigue a la CABEZA (misma fórmula que CharacterRig): mirar a un lado mueve la vista.

signal arrived_at_exit(node: NPCNode, target_room: String)

const GROUP := "npcs"
const LAYER_NPC := 5
const OBLIVIOUS_TIC := "headphones_never_turns_head"
const ARCH_OLD_HAND := "old_hand"
const ARCH_HARDLINER := "hardliner"
const ARCH_SNITCH := "snitch"
const ARCH_OBLIVIOUS := "oblivious"
const ARCH_BURNOUT := "burnout"
const ARCH_COWARD := "coward"
const ARCH_CLIMBER := "climber"
const ARCH_INCORRUPTIBLE := "incorruptible"
const OBSERVING_TIER := 4
const ACTIVITY_SLACKING := "slacking"
const EAT_ACTIVITIES: Array[String] = ["lunch"]
const WANDER_ACTIVITIES: Array[String] = ["patrol", "patrol_zone", "round", "clean", "clean_zone",
	"assign_tasks", "attendance_check"]
const STANDING_GESTURES: Array[String] = ["check_watch", "yawn", "check_watch"]
const SEATED_GESTURES: Array[String] = ["yawn", "check_watch"]
const ERRAND_REPORT := "report"
const ERRAND_SUPERIOR := "report_superior"
const ERRAND_CONFRONT := "confront"
const ERRAND_DEMAND := "demand"
const ERRAND_FLEE := "flee"
const ERRAND_GOSSIP := "gossip"
const ERRAND_REST := "rest"
const ERRAND_INVESTIGATE := "investigate"
const ERRAND_SABOTAGE := "sabotage"
const ERRAND_TELL_IDEA := "tell_idea"
const ERRAND_FOCUS := "focus"
## Recado → {bubble, walk (animación al ir), stay (animación al llegar), speed (clave de balance)}.
const ERRANDS: Dictionary = {
	ERRAND_REPORT: {"bubble": "report", "walk": "walk_report", "stay": "idle", "speed": "mod_velocidad_denuncia"},
	ERRAND_SUPERIOR: {"bubble": "report", "walk": "walk_report", "stay": "chat", "speed": "mod_velocidad_denuncia"},
	ERRAND_CONFRONT: {"bubble": "exclaim", "walk": "walk", "stay": "point", "speed": ""},
	ERRAND_DEMAND: {"bubble": "money", "walk": "walk", "stay": "chat", "speed": ""},
	ERRAND_FLEE: {"bubble": "exclaim", "walk": "sprint", "stay": "hide", "speed": "mod_velocidad_huida"},
	ERRAND_GOSSIP: {"bubble": "talk", "walk": "walk", "stay": "chat", "speed": ""},
	ERRAND_REST: {"bubble": "sleep", "walk": "walk", "stay": "idle", "speed": ""},
	ERRAND_INVESTIGATE: {"bubble": "question", "walk": "walk", "stay": "suspicion", "speed": ""},
	ERRAND_SABOTAGE: {"bubble": "", "walk": "walk", "stay": "drawer", "speed": ""},
	ERRAND_TELL_IDEA: {"bubble": "", "walk": "walk", "stay": "chat", "speed": ""},
	ERRAND_FOCUS: {"bubble": "", "walk": "walk", "stay": "type_intense", "speed": ""},
}
## Interactivo de persona (InteractionRouter, tipo "npc", data {npc_id}): invisible (sin realce
## propio; la indicación contextual del HUD basta) y con su sala al día (_report_room).
const INTERACT_TYPE := "npc"
const INTERACT_NODE := "Interact"
const PHASE_GO := "go"
const PHASE_STAY := "stay"
const IDEA_AGITATION := "agitation"
const IDEA_COMPUTER := "to_computer"
const IDEA_TELL := "tell_colleague"
## Destino "sin decidir" (ningún id de sala lo usa): obliga a reaplicar la agenda.
const NO_GOAL := "#none"
## Reacciones que se aplazan mientras vigila al jugador (ver DECISIONES).
const DEFERRABLE: Array[String] = [UtilityAI.REPORT_TO_SECURITY, UtilityAI.REPORT_TO_SUPERIOR,
	UtilityAI.CONFRONT_PLAYER]
const TRIGGER_UNIFORM := "uniform"
## Recados que ceden ante la agenda (la comida o la salida los interrumpen); denunciar, confrontar,
## chantajear, huir e investigar no.
const SOFT_ERRANDS: Array[String] = [ERRAND_GOSSIP, ERRAND_SABOTAGE, ERRAND_REST, ERRAND_TELL_IDEA, ERRAND_FOCUS]
## La mirada se cuantiza a 16 rumbos (el dibujo usa 8): menos redibujados con objetivos móviles.
const LOOK_STEPS := 16.0

var npc_id: String = ""
var occupation_id: String = ""
var archetype: String = ""
var department: String = ""
var home_room: String = ""
var tier: int = 1
var lod: int = NPCRuntime.LOD_MEDIUM
var perception: Perception = null
var indicator: DetectionIndicator = null
## Interactivo "npc" hijo (BUILD_NOTES §15): el jugador puede dirigirse a esta persona.
var interactable: Interactable = null
## Segundos de mundo que NPCLayer lo mantiene fuera de la planta tras salir (recados).
var away_after_exit: float = 0.0

var _layer: NPCLayer = null
var _bubble: NPCBubble = null
var _app: Dictionary = {}
var _tic: String = ""
var _cell: float = 48.0
var _tun: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _anim: String = "idle"
var _frame: int = 0
var _anim_clock: float = 0.0
var _gesture: String = ""
var _tic_frame: int = 0
var _tic_clock: float = 0.0
var _tic_period: float = 0.4
var _facing: Vector2 = Vector2.DOWN
var _look: Vector2 = Vector2.ZERO
var _glance: Vector2 = Vector2.ZERO
var _glance_left: float = 0.0
var _glance_timer: float = 0.0
var _idle_timer: float = 0.0
var _seated: bool = false
var _draw_offset: Vector2 = Vector2.ZERO
var _dirty: bool = true
var _path: PackedVector2Array = []
var _path_i: int = 0
var _speed: float = 0.0
var _speed_mod: float = 1.0
var _walk_anim: String = "walk"
var _pause_left: float = 0.0
var _pause_timer: float = 0.0
var _goal_room: String = NO_GOAL
var _goal_activity: String = ""
var _spot: Dictionary = {}
var _leaving: bool = false
var _leave_target: String = ""
var _errand: Dictionary = {}
var _idea: String = ""
var _idea_confidant: String = ""
var _pace_left: float = 0.0
var _partner: NPCNode = null
var _reported_room: String = ""
var _wander_left: float = 0.0
## Carril propio (desplazamiento fijo de los puntos intermedios): los grupos no caminan apilados.
var _lane: Vector2 = Vector2.ZERO
## Reacción aplazada mientras vigila al jugador: {action, context, left}.
var _pending: Dictionary = {}
## Tránsito: segundos seguidos esperando en cola (tope npc_nodo.espera_max_cola) y jefe al que
## acompaña (marca el paso).
var _queue_wait: float = 0.0
var _pace_leader: NPCNode = null
var _pace_mod: float = 1.0
var _detour_i: int = -1
var _head_tops: Dictionary = {}
## Sentado de cara a una mesa: el desplazamiento del dibujo es solo visual (al levantarse no se mueve).
var _seat_tucked: bool = false


func _ready() -> void:
	add_to_group(GROUP)


## Crea al personaje para `npc` (apariencia de CharacterPainter por su semilla y escalón).
func setup(npc: NPCRuntime, layer: NPCLayer) -> void:
	npc_id = npc.id
	occupation_id = npc.occupation_id
	archetype = npc.archetype
	department = npc.department
	home_room = npc.home_room
	tier = clampi(npc.tier, 1, CharacterStyle.OUTFIT_COUNT)
	_layer = layer
	name = "NPC_%s" % npc.id.validate_node_name()
	_rng.seed = hash(npc.id) ^ GameClock.get_run_seed()
	_app = CharacterPainter.appearance_for_npc(npc)
	_tic = CharacterPainter.tic_for_archetype(npc.archetype)
	_load_tunables()
	_setup_physics()
	_build_children()
	_idle_timer = _rand_range("idle_intervalo")
	_glance_timer = _rand_range("vistazo_intervalo") * _glance_factor()
	var lane: float = Database.get_balance_float("npc_nodo.carril") * _cell
	_lane = Vector2(_rng.randf_range(-lane, lane), _rng.randf_range(-lane, lane))


func _load_tunables() -> void:
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	for key: String in ["vistazo_duracion", "vistazo_angulo", "recado_segundos", "confrontacion_segundos",
			"distancia_confrontacion", "distancia_charla", "emote_segundos", "investigacion_segundos",
			"pausa_escalon4_intervalo", "pausa_escalon4_segundos", "distancia_retroceso_coward",
			"paso_retroceso_coward", "margen_llegada", "mod_velocidad_old_hand", "mod_velocidad_prisa",
			"mod_velocidad_denuncia", "mod_velocidad_huida", "mod_velocidad_agitacion", "factor_vistazo_snitch",
			"segundos_agitacion", "fps_tic", "prob_gesto", "distancia_sobresalto",
			"factor_gesto_breve", "celdas_inalcanzable", "espera_max_reaccion", "radio_destino_recado",
			"espera_max_cola", "factor_retraso_escolta"]:
		_tun[key] = Database.get_balance_float("npc_nodo." + key)
	var by_tier: Array = Database.get_balance("npc_nodo.velocidad_por_escalon")
	var tier_factor: float = float(by_tier[tier]) if tier < by_tier.size() else 1.0
	_speed = Database.get_balance_float("npc_nodo.velocidad_base") * tier_factor * _cell
	if archetype == ARCH_OLD_HAND:
		_speed *= float(_tun["mod_velocidad_old_hand"])
	_tic_period = 1.0 / maxf(float(_tun["fps_tic"]), 0.01)
	if archetype == ARCH_HARDLINER:
		_tic_period = Database.get_balance_float("percepcion.periodo_barrido_hardliner") / CharacterAnim.TIC_CYCLE


func _setup_physics() -> void:
	collision_layer = 1 << (LAYER_NPC - 1)
	collision_mask = 0
	motion_mode = MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = Database.get_balance_float("jugador.radio_colision") * _cell
	shape.shape = circle
	add_child(shape)


func _build_children() -> void:
	perception = Perception.new()
	perception.name = "Perception"
	add_child(perception)
	perception.setup(npc_id, archetype)
	perception.set_view(_facing, true)
	perception.state_changed.connect(_on_perception_state)
	indicator = DetectionIndicator.new()
	indicator.name = "DetectionIndicator"
	add_child(indicator)
	indicator.bind(perception)
	perception.witnessed.connect(_on_witnessed)
	_bubble = NPCBubble.new()
	_bubble.name = "Bubble"
	add_child(_bubble)
	_build_interactable()
	_set_draw_offset(Vector2.ZERO)


## Integración (game_root, BUILD_NOTES §15): interactivo "npc" con {npc_id}; lo despacha el router.
func _build_interactable() -> void:
	interactable = Interactable.new()
	interactable.setup(npc_id, INTERACT_TYPE, home_room, {"npc_id": npc_id}, _cell, Vector2.ZERO)
	interactable.name = INTERACT_NODE
	interactable.visible = false
	add_child(interactable)


# ─── API pública ──────────────────────────────────────────────

func is_seated() -> bool:
	return _seated


func is_moving() -> bool:
	return _path_i < _path.size()


func is_leaving() -> bool:
	return _leaving


func get_perception() -> Perception:
	return perception


func get_spot() -> Dictionary:
	return _spot


func get_goal() -> Dictionary:
	return {"room": _goal_room, "activity": _goal_activity}


## Sala a la que se dirige: la de su salida si abandona la planta; si no, su destino de agenda.
func get_destination() -> String:
	return _leave_target if _leaving else _goal_room


func get_path_points() -> PackedVector2Array:
	return _path.slice(_path_i)


func get_errand_kind() -> String:
	return str(_errand.get("kind", ""))


## Acción aplazada mientras vigila al jugador ("" = ninguna).
func get_pending_action() -> String:
	return str(_pending.get("action", ""))


## Rumbo de marcha (hacia el siguiente punto de la ruta) o Vector2.ZERO si está quieto.
func get_travel_dir() -> Vector2:
	if not is_moving():
		return Vector2.ZERO
	var to: Vector2 = _path[_path_i] - global_position
	return to.normalized() if to.length_squared() > 0.01 else _facing


## Velocidad de marcha actual (px/s de mundo).
func get_speed_px() -> float:
	return _speed * _speed_mod


func get_bubble_kind() -> String:
	return _bubble.current_kind() if _bubble != null else ""


func get_appearance() -> Dictionary:
	return _app


## Punto donde se ve al personaje (sentado: la silla; si no, los pies).
func get_visual_position() -> Vector2:
	return global_position + _draw_offset


func can_see_player() -> bool:
	var player: Node2D = _layer.get_player() if _layer != null else null
	return player != null and perception != null and perception.sees_point(player.global_position)


func set_debug_cones(on: bool) -> void:
	if perception != null:
		perception.set_debug_cones(on)


func set_lod(level: int) -> void:
	lod = level
	if perception != null:
		perception.set_active(level == NPCRuntime.LOD_FULL)


## Gesto en bocadillo durante `seconds` (≤ 0: npc_nodo.emote_segundos).
func show_emote(kind: String, seconds: float = 0.0) -> void:
	if _bubble != null:
		_bubble.show_emote(kind, seconds if seconds > 0.0 else float(_tun["emote_segundos"]))


## Colocado ya en su sitio (carga de planta o promoción de LOD): sin caminar.
func place_at(spot: Dictionary) -> void:
	_spot = spot
	global_position = spot.get("pos", global_position)
	_path = PackedVector2Array()
	_path_i = 0
	_settle()


## Entra por un tránsito (ascensor, escalera, calle) y camina a `spot`.
func enter_at(point: Vector2, spot: Dictionary) -> void:
	global_position = point
	_spot = spot
	_walk_to_spot()


## Destino de agenda ya decidido por NPCLayer (tests / escenas).
func set_goal(room: String, activity: String) -> void:
	_goal_room = room
	_goal_activity = activity


# ─── Fotograma ────────────────────────────────────────────────

## Movimiento, gestos y animación durante `delta` segundos de mundo (0 = pausa).
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick_errand_clock(delta)
	_tick_pending(delta)
	_tick_pace()
	if _bubble != null and perception != null:
		_bubble.set_indicator_shown(perception.get_state() != Perception.STATE_NONE)
	_move(delta)
	_tick_look(delta)
	_tick_idle(delta)
	_tick_anim(delta)
	if _dirty:
		_dirty = false
		if perception != null:
			perception.set_view(head_direction())
		queue_redraw()


## Percepción en LOD 0 (NPCLayer: una vez por fotograma con el jugador y su exposición).
func perceive(delta: float, player: Node2D, exposure: Dictionary) -> void:
	if perception == null:
		return
	if lod == NPCRuntime.LOD_FULL:
		perception.tick(delta, player, exposure)
	else:
		perception.tick(delta, null, {})


func _move(delta: float) -> void:
	if _path_i >= _path.size():
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	_queue_wait = maxf(0.0, _queue_wait - delta)
	var target: Vector2 = _path[_path_i]
	var to: Vector2 = target - global_position
	var step_px: float = _speed * _speed_mod * _pace_mod * delta
	if to.length() <= step_px:
		global_position = target
		_path_i += 1
		if _path_i >= _path.size():
			_on_path_end()
		return
	global_position += to / to.length() * step_px
	_set_facing(to)
	_tick_observation(delta)


## Escalón 4 (§14.5): pausas de observación al caminar (no en recados urgentes).
func _tick_observation(delta: float) -> void:
	if tier != OBSERVING_TIER or not _errand.is_empty() or _leaving:
		return
	_pause_timer += delta
	if _pause_timer >= float(_tun["pausa_escalon4_intervalo"]):
		_pause_timer = 0.0
		_pause_left = float(_tun["pausa_escalon4_segundos"])
		if _glances():
			_glance = _facing.rotated(deg_to_rad(float(_tun["vistazo_angulo"])) * _sign())
			_glance_left = _pause_left


# ─── Tránsito (NPCLayer.space_walkers) ────────────────────────

## Espera `seconds` en cola tras otro; false si ya esperó npc_nodo.espera_max_cola seguidos (sigue:
## nunca se atasca).
func hold(seconds: float) -> bool:
	if not is_moving() or _queue_wait >= float(_tun["espera_max_cola"]):
		return false
	_pause_left = maxf(_pause_left, seconds)
	_queue_wait += seconds
	return true


## Se aparta `offset` px con un punto de desvío antes del siguiente punto de la ruta (uno por tramo).
func sidestep(offset: Vector2, ahead_px: float) -> void:
	if not is_moving() or _layer == null or _detour_i == _path_i:
		return
	var to: Vector2 = _path[_path_i] - global_position
	var point: Vector2 = global_position + to.limit_length(ahead_px) * 0.5 + offset
	if _layer.is_walkable_point(point):
		_path.insert(_path_i, point)
		_detour_i = _path_i


## Acompaña a `leader` (escalón 5-6): ajusta su paso al del jefe mientras ambos caminan.
func match_pace(leader: NPCNode) -> void:
	_pace_leader = leader


func get_pace_leader() -> NPCNode:
	return _pace_leader if _pace_leader != null and is_instance_valid(_pace_leader) else null


func _tick_pace() -> void:
	_pace_mod = 1.0
	if _pace_leader == null:
		return
	if not is_instance_valid(_pace_leader) or not _pace_leader.is_moving() or not is_moving():
		_pace_leader = null
		return
	var own: float = maxf(_speed * _speed_mod, 1.0)
	_pace_mod = _pace_leader.get_speed_px() / own
	var lead_dir: Vector2 = _pace_leader.get_travel_dir()
	if (global_position - _pace_leader.global_position).dot(lead_dir) > 0.0:
		_pace_mod *= float(_tun.get("factor_retraso_escolta", 1.0))


func _set_facing(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	var snapped_dir: Vector2 = Vector2.from_angle(roundf(dir.angle() / (PI / 4.0)) * PI / 4.0)
	if not snapped_dir.is_equal_approx(_facing):
		_facing = snapped_dir
		_dirty = true


func _on_path_end() -> void:
	_path = PackedVector2Array()
	_path_i = 0
	_speed_mod = 1.0
	if _leaving:
		arrived_at_exit.emit(self, _leave_target)
		return
	if not _errand.is_empty() and str(_errand.get("phase", "")) == PHASE_GO:
		_errand["phase"] = PHASE_STAY
		_face_errand_target()
		_dirty = true
		return
	if not _spot.is_empty():
		_settle()


func _settle() -> void:
	var seated: bool = bool(_spot.get("seated", false))
	global_position = _spot.get("pos", global_position)
	_seated = seated
	var facing: Vector2 = _spot.get("facing", Vector2.ZERO)
	if facing.length_squared() > 0.0:
		_facing = facing.normalized()
	_seat_tucked = seated and bool(_spot.get("tucked", false))
	_set_draw_offset((_spot.get("draw", global_position) as Vector2) - global_position if seated else Vector2.ZERO)
	_dirty = true


## Coronilla (px de mundo sobre el origen de dibujo, negativa) de pie o sentado: ahí se anclan el
## indicador y los bocadillos (que se dibujan hacia arriba a tamaño de pantalla constante).
func head_top(seated: bool) -> float:
	if not _head_tops.has(seated):
		var anim: String = "sit" if seated else "idle"
		var rig: CharacterRig = CharacterRig.build(_app, tier, CharacterPainter.make_pose(anim, 0, Vector2.DOWN,
				{"seated": seated}))
		_head_tops[seated] = rig.head_c.y - rig.head_radii.y
	return float(_head_tops[seated])


func _set_draw_offset(offset: Vector2) -> void:
	_draw_offset = offset
	var head: Vector2 = offset + Vector2(0.0, head_top(_seated))
	if perception != null:
		perception.position = offset
	if indicator != null:
		indicator.position = head
	if _bubble != null:
		_bubble.position = head


## Se levanta: el nodo pasa a donde se le veía sentado (salvo de cara a una mesa: sigue en la silla).
func _stand_up() -> void:
	if not _seated:
		return
	if not _seat_tucked:
		global_position += _draw_offset
	_seat_tucked = false
	_seated = false
	_set_draw_offset(Vector2.ZERO)
	_dirty = true


## Ruta del plano hasta `target` (con su carril). Sin ruta posible y lejos: aparece allí (nunca
## atraviesa muros).
func _walk_to(target: Vector2) -> void:
	_stand_up()
	_path = _layer.path_between(global_position, target) if _layer != null else PackedVector2Array()
	if _path.is_empty() and _layer != null \
			and global_position.distance_to(target) > _cell * float(_tun["celdas_inalcanzable"]):
		global_position = target
	if _path.is_empty() or _path[_path.size() - 1].distance_to(target) > 1.0:
		_path.append(target)
	for i: int in range(1, _path.size() - 1):
		_path[i] += _lane
	_path_i = 0
	_detour_i = -1
	_pause_timer = 0.0


## Camina a su sitio: al punto de acceso y de ahí a donde se sienta o se queda ("walk_end"; si no,
## el punto de dibujo).
func _walk_to_spot() -> void:
	_walk_to(_spot.get("approach", _spot.get("pos", global_position)))
	var final_point: Vector2 = _spot.get("walk_end", _spot.get("draw", _spot.get("pos", global_position)))
	if _path[_path.size() - 1].distance_to(final_point) > 1.0:
		_path.append(final_point)
	_walk_anim = "walk"
	_speed_mod = _hurry_factor(str(_spot.get("room", "")))


## climber: prisa hacia los despachos de superiores (no hacia su propia sala).
func _hurry_factor(room_id: String) -> float:
	if archetype == ARCH_CLIMBER and _layer != null and DatabaseSystem.get_room_base_id(room_id) != home_room \
			and _layer.is_superior_office(room_id, tier):
		return float(_tun["mod_velocidad_prisa"])
	return 1.0


# ─── Mirada, gestos y animación ───────────────────────────────

func _tick_look(delta: float) -> void:
	_glance_left = maxf(0.0, _glance_left - delta)
	if not is_moving() and _glances():
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			_glance_timer = _rand_range("vistazo_intervalo") * _glance_factor()
			_glance = _facing.rotated(deg_to_rad(float(_tun["vistazo_angulo"])) * _sign())
			_glance_left = float(_tun["vistazo_duracion"])
	var look: Vector2 = _wanted_look()
	if not look.is_equal_approx(_look):
		_look = look
		_dirty = true


## Prioridad: ruido atendido > anomalía (old_hand) > sospecha > recado > charla > vistazo.
func _wanted_look() -> Vector2:
	var target: Vector2 = Vector2.INF
	if perception != null:
		target = perception.get_attention_point()
		if not target.is_finite():
			target = perception.get_anomaly_point()
		if not target.is_finite() and perception.get_state() >= Perception.STATE_PARTIAL:
			target = _player_position()
	if not target.is_finite() and str(_errand.get("phase", "")) == PHASE_STAY:
		target = _errand_target_point()
	if not target.is_finite() and _partner != null and is_instance_valid(_partner):
		target = _partner.get_visual_position()
	if target.is_finite():
		var dir: Vector2 = target - get_visual_position()
		if not _seated and not is_moving() and dir.length_squared() > 1.0 and archetype != ARCH_OBLIVIOUS:
			_set_facing(dir)
		return _quantize(dir) if dir.length_squared() > 1.0 else Vector2.ZERO
	return _glance if _glance_left > 0.0 else Vector2.ZERO


static func _quantize(dir: Vector2) -> Vector2:
	var step: float = TAU / LOOK_STEPS
	return Vector2.from_angle(roundf(dir.angle() / step) * step)


## Rumbo de la cabeza (CharacterRig): tic y head_turn de la pose sobre la mirada o la orientación.
func head_direction() -> Vector2:
	var p: Dictionary = CharacterAnim.params(_anim, _frame, tier)
	CharacterAnim.apply_tic(p, _anim, _tic, _tic_frame)
	var base: Vector2 = _facing
	if _tic != OBLIVIOUS_TIC and _look.length_squared() > 0.0001:
		base = _look.normalized()
	return base.rotated(float(p["head_turn"]) * CharacterRig.HEAD_TURN_MAX)


func _tick_idle(delta: float) -> void:
	if is_moving() or not _gesture.is_empty() or not _errand.is_empty() or _partner != null:
		return
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	_idle_timer = _rand_range("idle_intervalo")
	var pool: Array[String] = SEATED_GESTURES if _seated else STANDING_GESTURES
	if archetype == ARCH_BURNOUT or _rng.randf() < float(_tun["prob_gesto"]):
		_gesture = pool[_rng.randi_range(0, pool.size() - 1)]


func _tick_anim(delta: float) -> void:
	var anim: String = _current_anim()
	if anim != _anim:
		_anim = anim
		_frame = 0
		_anim_clock = 0.0
		_dirty = true
	var fps: float = CharacterPainter.anim_fps(_anim) * (_speed_mod if CharacterAnim.is_locomotion(_anim) else 1.0)
	_anim_clock += delta
	while fps > 0.0 and _anim_clock >= 1.0 / fps:
		_anim_clock -= 1.0 / fps
		var next: int = CharacterAnim.next_frame(_anim, _frame)
		if next < 0:
			_gesture = ""
			_anim_clock = 0.0
			break
		if next != _frame:
			_frame = next
			_dirty = true
	_tic_clock += delta
	if _tic_clock >= _tic_period:
		_tic_clock = 0.0
		_tic_frame = (_tic_frame + 1) % CharacterAnim.TIC_CYCLE
		_dirty = _dirty or CharacterAnim.TIC_ANIMS.has(_anim)


func _current_anim() -> String:
	if is_moving():
		return "idle" if _pause_left > 0.0 else _walk_anim
	if not _gesture.is_empty():
		return _gesture
	if str(_errand.get("phase", "")) == PHASE_STAY:
		return str(ERRANDS[_errand["kind"]]["stay"])
	if perception != null and perception.get_state() >= Perception.STATE_PARTIAL and not _seated:
		return "suspicion"
	if _seated:
		return _seated_anim()
	if _partner != null:
		return "chat"
	return "phone_sneak" if _goal_activity == ACTIVITY_SLACKING else "idle"


func _seated_anim() -> String:
	if _goal_activity == ACTIVITY_SLACKING:
		return "phone_sneak"
	if _idea == IDEA_COMPUTER:
		return "type_intense"
	if EAT_ACTIVITIES.has(_goal_activity) or str(_spot.get("room", "")) != home_room:
		return "chat" if _partner != null else "sit"
	if archetype == ARCH_BURNOUT or archetype == ARCH_HARDLINER:
		return "sit"
	return "type_intense" if archetype == ARCH_CLIMBER else "sit_type"


func _draw() -> void:
	var pose: Dictionary = CharacterPainter.make_pose(_anim, _frame, _facing, {"look": _look, "tic": _tic,
			"tic_frame": _tic_frame, "seated": _seated, "origin": _draw_offset})
	CharacterPainter.draw(self, _app, tier, pose)


# ─── Pensar (cada lod.intervalo_medio_segundos) ───────────────

## Agenda, recados, ideas y vida social. Lo llama NPCLayer.
func think() -> void:
	_report_room()
	if perception != null and lod == NPCRuntime.LOD_FULL:
		perception.refresh_traits()
	if _leaving or _layer == null:
		return
	if not _errand.is_empty() and SOFT_ERRANDS.has(get_errand_kind()) and not _staying():
		_end_errand()
	if not _errand.is_empty():
		_think_errand()
		return
	var goal: Dictionary = _layer.schedule_goal(npc_id)
	if str(goal["room"]) != _goal_room or str(goal["activity"]) != _goal_activity:
		_apply_goal(str(goal["room"]), str(goal["activity"]))
	if not is_moving():
		_think_idea()
		_think_social()


## Comunica ya su sala real a NPCDirector (NPCLayer lo llama al crearlo).
func report_room() -> void:
	_report_room()


func _report_room() -> void:
	if _layer == null:
		return
	var room: String = _layer.room_at(get_visual_position())
	if not room.is_empty() and room != _reported_room:
		_reported_room = room
		NPCDirector.set_current_location(npc_id, room)
		if interactable != null:
			interactable.room_id = room


func get_reported_room() -> String:
	return _reported_room


func _apply_goal(room: String, activity: String) -> void:
	var same_room: bool = room == _goal_room
	_goal_room = room
	_goal_activity = activity
	var local: String = _layer.local_room(room)
	if local.is_empty():
		leave_floor(room)
		return
	if same_room and not _spot.is_empty() and str(_spot["room"]) == local and not _needs_new_spot(activity):
		return
	var spot: Dictionary = _layer.claim_spot(self, local, activity)
	if spot.is_empty():
		return
	_spot = spot
	if get_visual_position().distance_to(spot["draw"]) <= float(_tun["margen_llegada"]) * _cell:
		_settle()
	else:
		_walk_to_spot()


func _needs_new_spot(activity: String) -> bool:
	return bool(_spot.get("seated", false)) != _layer.wants_seat(self, activity)


## Camina al tránsito de salida (otra planta o la calle) y emite arrived_at_exit al llegar.
## `away_seconds` > 0: tiempo (de mundo) que tarda en volver a verse por esta planta aunque la
## agenda lo devuelva (un recado a otra planta no dura un instante).
func leave_floor(target_room: String, away_seconds: float = 0.0) -> void:
	_leaving = true
	_leave_target = target_room
	away_after_exit = away_seconds
	_partner = null
	if _layer != null:
		_layer.release_spot(self)
	var exit: Vector2 = _layer.exit_point(self, target_room) if _layer != null else Vector2.INF
	if not exit.is_finite():
		arrived_at_exit.emit(self, target_room)
		return
	_walk_to(exit)
	_walk_anim = "walk"
	_speed_mod = _hurry_factor(target_room)


func _think_social() -> void:
	_partner = _layer.chat_partner(self) if not _seated or EAT_ACTIVITIES.has(_goal_activity) else null
	if archetype == ARCH_COWARD and not _seated:
		_step_back_from_player()
	if WANDER_ACTIVITIES.has(_goal_activity) and not _seated:
		_wander_left -= _layer.think_interval()
		if _wander_left <= 0.0:
			_wander_left = _rand_range("idle_intervalo")
			var spot: Dictionary = _layer.claim_spot(self, str(_spot.get("room", "")), _goal_activity)
			if not spot.is_empty():
				_spot = spot
				_walk_to_spot()


## coward (§14.6): retrocede medio paso cuando el jugador se le acerca.
func _step_back_from_player() -> void:
	var player: Vector2 = _player_position()
	if not player.is_finite():
		return
	var away: Vector2 = global_position - player
	if away.length() > float(_tun["distancia_retroceso_coward"]) * _cell or away.length() < 1.0:
		return
	_set_facing(-away)
	_walk_to(global_position + away.normalized() * float(_tun["paso_retroceso_coward"]) * _cell)
	_speed_mod = 1.0


func _player_position() -> Vector2:
	var player: Node2D = _layer.get_player() if _layer != null else null
	return player.global_position if player != null else Vector2.INF


# ─── Ideas (IdeaPool.get_signalling_npcs) ─────────────────────

## Señal de idea activa ({} = ninguna): bombilla + conducta (agitación, al ordenador, contarla).
func set_idea(entry: Dictionary) -> void:
	var behaviour: String = str(entry.get("behaviour", ""))
	if _bubble != null:
		_bubble.set_persistent(NPCBubble.KIND_IDEA if not behaviour.is_empty() else "")
	if behaviour == _idea:
		return
	_idea = behaviour
	_idea_confidant = str(entry.get("confidant", ""))
	_dirty = true
	if _idea == IDEA_TELL and _layer != null:
		var confidant: NPCNode = _layer.get_node_for(_idea_confidant)
		if confidant != null:
			_start_errand(ERRAND_TELL_IDEA, {"node": confidant})


func get_idea_behaviour() -> String:
	return _idea


## agitation: se levanta y va y viene junto a su puesto.
func _think_idea() -> void:
	if _idea != IDEA_AGITATION or _spot.is_empty():
		return
	_pace_left -= _layer.think_interval()
	if _pace_left > 0.0:
		return
	_pace_left = float(_tun["segundos_agitacion"])
	var anchor: Vector2 = _spot.get("approach", global_position)
	var point: Vector2 = _layer.free_point_near(anchor, Database.get_balance_int("npc_nodo.radio_agitacion"), _rng.randi())
	if point.is_finite():
		_walk_to(point)
		_walk_anim = "walk"
		_speed_mod = float(_tun["mod_velocidad_agitacion"])


# ─── Reacciones ───────────────────────────────────────────────

## npc_decided / npc_reported_player (NPCLayer): conducta visible de la decisión. Denunciar o
## confrontar mientras vigila al jugador se aplaza (ver DECISIONES).
func react(action: String, context: Dictionary) -> void:
	if DEFERRABLE.has(action) and perception != null and perception.is_watching() and not _leaving:
		_pending = {"action": action, "context": context, "left": float(_tun["espera_max_reaccion"])}
		_dirty = true
		return
	if DEFERRABLE.has(action):
		_pending = {}
	_perform(action, context)


## Reacción aplazada: sale al perder el contacto o al agotar npc_nodo.espera_max_reaccion; la
## flagrancia la descarta (CaughtHandler lleva la escena).
func _tick_pending(delta: float) -> void:
	if _pending.is_empty() or perception == null:
		return
	if perception.get_state() == Perception.STATE_FLAGRANT:
		_pending = {}
		return
	_pending["left"] = float(_pending["left"]) - delta
	if perception.is_watching() and float(_pending["left"]) > 0.0:
		return
	var pending: Dictionary = _pending
	_pending = {}
	_perform(str(pending["action"]), pending["context"])


func _perform(action: String, context: Dictionary) -> void:
	var band: bool = str(context.get("trigger", "")) == NPCDirectorSystem.TRIGGER_BAND
	match action:
		UtilityAI.REPORT_TO_SECURITY:
			_start_errand(ERRAND_REPORT, {"room": Database.get_balance("npc_nodo.sala_denuncia_seguridad")})
		UtilityAI.REPORT_TO_SUPERIOR:
			_start_errand(ERRAND_SUPERIOR, _layer.superior_target(self) if _layer != null else {})
		UtilityAI.CONFRONT_PLAYER:
			_start_errand(ERRAND_CONFRONT, {"player": true})
		UtilityAI.BLACKMAIL_PLAYER:
			_start_errand(ERRAND_DEMAND, {"player": true})
		UtilityAI.FLEE:
			_gesture = "startle"
			_start_errand(ERRAND_FLEE, {})
		UtilityAI.GOSSIP, UtilityAI.SABOTAGE_RIVAL:
			if not band or _staying():
				_start_gossip(action, str(context.get("target", "")))
		UtilityAI.REST:
			if _staying():
				_start_errand(ERRAND_REST, {"room": _layer.rest_room() if _layer != null else ""})
		UtilityAI.GENERATE_IDEA:
			if _seated:
				_start_errand(ERRAND_FOCUS, {"here": true})
		UtilityAI.STAY_SILENT:
			show_emote(NPCBubble.KIND_QUESTION)


func _start_gossip(action: String, target_id: String) -> void:
	var node: NPCNode = _layer.get_node_for(target_id) if _layer != null and not target_id.is_empty() else null
	if node == null and _layer != null:
		node = _layer.gossip_partner(self)
	if node != null:
		_start_errand(ERRAND_SABOTAGE if action == UtilityAI.SABOTAGE_RIVAL else ERRAND_GOSSIP, {"node": node})


## Sigue en la misma sala esta franja (las decisiones de franja no le hacen perder su agenda).
func _staying() -> bool:
	if _leaving or _layer == null:
		return false
	var goal: Dictionary = _layer.schedule_goal(npc_id)
	return _layer.local_room(str(goal["room"])) == str(_spot.get("room", ""))


## Un ruido atendido (Perception.hear): gira la cabeza, se sobresalta si fue muy cerca
## (npc_nodo.distancia_sobresalto) y, si le compensa, investiga.
func on_heard(reaction: Dictionary) -> void:
	if reaction.is_empty():
		return
	if float(reaction.get("distance", INF)) <= float(_tun["distancia_sobresalto"]) and _gesture.is_empty():
		_gesture = "startle"
	if bool(reaction.get("investigate", false)) and (_errand.is_empty() or get_errand_kind() == ERRAND_INVESTIGATE):
		_start_errand(ERRAND_INVESTIGATE, {"point": reaction["origin"]})
	elif _errand.is_empty():
		show_emote(NPCBubble.KIND_QUESTION, float(_tun["emote_segundos"]) * float(_tun["factor_gesto_breve"]))
		_dirty = true


## Este personaje declaró la flagrancia: se detiene y señala (el «!» lo da su indicador; si no
## está a la vista, un bocadillo). Lo que tuviera aplazado se descarta.
func on_caught() -> void:
	_stand_up()
	_path = PackedVector2Array()
	_path_i = 0
	_pending = {}
	_gesture = "point"
	show_emote(NPCBubble.KIND_EXCLAIM, UITheme.tune("interfaz.flagrancia_aviso_segundos"))
	var player: Vector2 = _player_position()
	if player.is_finite():
		_set_facing(player - global_position)


## El indicador ya dice «?» (parcial) y «!» (flagrancia): aquí solo la conducta.
func _on_perception_state(state: int) -> void:
	if state == Perception.STATE_NONE and _gesture == "point":
		_gesture = ""
		_goal_room = NO_GOAL
	if state == Perception.STATE_FLAGRANT:
		on_caught()
	_dirty = true


## Vio un delito con la identidad oculta por el disfraz: se sobresalta y, al perder el contacto,
## va a Seguridad a contarlo (la creencia es sobre el uniforme, no sobre el jugador).
func _on_witnessed(_crime: String, identified: bool) -> void:
	if identified:
		return
	_gesture = "startle"
	react(UtilityAI.REPORT_TO_SECURITY, {"trigger": TRIGGER_UNIFORM})


## Recado de `kind` con destino en `data`: {room} | {node} | {player} | {point} | {here}.
func _start_errand(kind: String, data: Dictionary) -> void:
	if _leaving or _layer == null or not ERRANDS.has(kind):
		return
	var spec: Dictionary = ERRANDS[kind]
	_errand = data.duplicate()
	_errand["kind"] = kind
	_errand["phase"] = PHASE_GO
	_errand["left"] = _errand_seconds(kind)
	if not str(spec["bubble"]).is_empty():
		show_emote(str(spec["bubble"]), float(_errand["left"]))
	if not bool(_errand.get("here", false)):
		_layer.release_spot(self)
	_partner = null
	_go_errand(spec)


func _errand_seconds(kind: String) -> float:
	match kind:
		ERRAND_CONFRONT, ERRAND_DEMAND:
			return float(_tun["confrontacion_segundos"])
		ERRAND_INVESTIGATE:
			return float(_tun["investigacion_segundos"])
	return float(_tun["recado_segundos"])


## Primer tramo del recado: hacia su sala, su compañero, el jugador o el punto del ruido.
func _go_errand(spec: Dictionary) -> void:
	if bool(_errand.get("here", false)):
		_errand["phase"] = PHASE_STAY
		return
	var room: String = str(_errand.get("room", ""))
	var speed_key: String = str(spec["speed"])
	if _errand.has("room") and _layer.local_room(room).is_empty():
		var away: float = float(_errand.get("left", 0.0))
		_errand = {}
		leave_floor(room, away)
		_walk_anim = str(spec["walk"])
		if not speed_key.is_empty():
			_speed_mod = float(_tun[speed_key])
		return
	var target: Vector2 = _errand_destination()
	if not target.is_finite():
		_end_errand()
		return
	_walk_to(target)
	_walk_anim = str(spec["walk"])
	_speed_mod = float(_tun[speed_key]) if not speed_key.is_empty() else 1.0


func _errand_destination() -> Vector2:
	if _errand.has("room"):
		var spot: Dictionary = _layer.claim_spot(self, _layer.local_room(str(_errand["room"])), "")
		return spot.get("approach", Vector2.INF)
	if _errand.has("node"):
		var other: NPCNode = _errand["node"] as NPCNode
		if other == null or not is_instance_valid(other):
			return Vector2.INF
		return _layer.free_point_near(other.get_visual_position(), _errand_reach(), _rng.randi())
	if bool(_errand.get("player", false)):
		var player: Vector2 = _player_position()
		return _layer.free_point_near(player, _errand_reach(), _rng.randi()) if player.is_finite() else Vector2.INF
	if _errand.has("point"):
		return _layer.free_point_near(_errand["point"], _errand_reach(), _rng.randi())
	if _errand.get("kind") == ERRAND_FLEE:
		return _layer.farthest_point_from(self, _player_position())
	return Vector2.INF


func _errand_target_point() -> Vector2:
	if _errand.has("node") and is_instance_valid(_errand["node"]):
		return (_errand["node"] as NPCNode).get_visual_position()
	if bool(_errand.get("player", false)):
		return _player_position()
	if _errand.has("point"):
		return _errand["point"]
	return Vector2.INF


func _face_errand_target() -> void:
	var target: Vector2 = _errand_target_point()
	if target.is_finite():
		_set_facing(target - global_position)
	if _errand.has("node") and is_instance_valid(_errand["node"]):
		(_errand["node"] as NPCNode).join_chat(self)


## Otro personaje viene a hablarle: le mira y charla (si está de pie y libre).
func join_chat(other: NPCNode) -> void:
	if other == null or not _errand.is_empty() or is_moving():
		return
	_partner = other
	_dirty = true


func _think_errand() -> void:
	if str(_errand.get("phase", "")) != PHASE_GO or not bool(_errand.get("player", false)):
		return
	var player: Vector2 = _player_position()
	if not player.is_finite():
		_end_errand()
		return
	if global_position.distance_to(player) <= float(_tun["distancia_confrontacion"]) * _cell:
		_path = PackedVector2Array()
		_path_i = 0
		_errand["phase"] = PHASE_STAY
		_face_errand_target()
	elif is_moving() and _path[_path.size() - 1].distance_to(player) > _cell:
		_walk_to(_layer.free_point_near(player, _errand_reach(), _rng.randi()))


func _tick_errand_clock(delta: float) -> void:
	if _errand.is_empty():
		return
	_errand["left"] = float(_errand["left"]) - delta
	if float(_errand["left"]) <= 0.0:
		_end_errand()


func _end_errand() -> void:
	if _errand.is_empty():
		return
	_errand = {}
	_partner = null
	_speed_mod = 1.0
	_goal_room = NO_GOAL
	_dirty = true


# ─── Utilidades ───────────────────────────────────────────────

## Radio (celdas) del punto libre junto al destino de un recado.
func _errand_reach() -> int:
	return int(_tun["radio_destino_recado"])


func _rand_range(key: String) -> float:
	var r: Array = Database.get_balance("npc_nodo." + key)
	return _rng.randf_range(float(r[0]), float(r[1]))


func _glance_factor() -> float:
	return float(_tun["factor_vistazo_snitch"]) if archetype == ARCH_SNITCH else 1.0


## Vistazos laterales: no el oblivious (no gira la cabeza) ni el incorruptible (estático y frontal).
func _glances() -> bool:
	return _tic != OBLIVIOUS_TIC and archetype != ARCH_INCORRUPTIBLE


func _sign() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0
