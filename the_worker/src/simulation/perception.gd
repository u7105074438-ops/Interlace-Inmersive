# perception.gd — Percepción de un personaje (§7.3, PASO 10-11): cono de visión progresivo con línea de visión real, oído con máscaras acústicas y muros, y dibujo del cono.
# PROPIETARIO DE: el contador de detección de su personaje, su contacto con el jugador (umbrales ya emitidos), su foco de atención auditiva y el contorno de su cono.
# ESCUCHA: nada (su NPCNode le entrega cada fotograma con tick(); NPCLayer le reparte EventBus.noise_emitted con hear()).
class_name Perception
extends Node2D

## Contrato (BUILD_NOTES §13-§14). Hijo de cada NPCNode, grupo "perception":
##   setup(npc_id, archetype) · set_view(dir) (rumbo de la CABEZA: el cono la sigue)
##   tick(delta, player, exposure) cada fotograma en LOD 0 (en LOD 1: tick(delta, null, {}) → se vacía)
##   hear(origin, radius_m, source, room_id, noteworthy) -> {} | {origin, investigate, distance}
##   sees_point(pos) (alcance + ángulo + línea de visión) · has_line_of_sight(pos)
##   can_notice(pos) (alcance + línea de visión, sin ángulo: observadores de GameClock)
##   get_counter() · get_state() (STATE_*) · is_watching() · get_attention_point() · get_anomaly_point()
##   set_debug_cones(on) (panel F1) · static cone_mode (0 ocultos, 1 automático, 2 todos)
##   señal witnessed(crime, identified): alcanzó la identificación completa durante un delito.
## DECISIONES:
##  · El contador SIEMPRE se llena dentro del cono (§7.3, PASO 10/12: «aproximarse a un personaje:
##    el indicador progresa»), pero si el jugador no es digno de atención para ESTE observador se
##    queda en percepcion.tope_contador_presencia (< umbral_parcial): el indicador en progreso
##    enseña a leer los conos sin crear creencias («verte trabajar es normal»). Digno de atención
##    (assess_exposure + disfraz del observador): acto en curso (Player.current_act), arrastrar un
##    cuerpo, una sala que su acreditación no cubre (regla del halo del HUD) o, de noche, una sala
##    acreditada sin ocupación nocturna que no es su puesto; o un uniforme incoherente.
##  · Disfraz (Disguise.evaluate, por observador): el factor multiplica el llenado. Una intrusión
##    en una sala que el uniforme coherente cubre (Disguise.grants_access) no cuenta salvo que ESTE
##    observador reconozca al jugador. Con la identidad oculta, la creencia parcial y la flagrancia
##    van contra el uniforme (Disguise.sighting_subject → BeliefNet.create_belief), no contra el
##    jugador: sin player_seen_partially ni player_caught_redhanded (el indicador se queda en parcial).
##  · Llenado/s = (velocidad_llenado_base + perspicacia_efectiva × mod_perspicacia_por_punto)
##    × min(distancia_referencia / d, factor_distancia_max) × agachado × inmóvil × esprint
##    × obstrucción parcial (capa 3) × disfraz. La perspicacia efectiva es la de NPCDirector
##    (ya incluye la sospecha, +0,005/punto, y el plus de alerta de los vigilantes).
##  · Vaciado «a menor velocidad» (§7.3): factor_vaciado_relativo × el último llenado, acotado a
##    [velocidad_vaciado_minima, velocidad_vaciado_base]: siempre más lento que como se llenó.
##  · Más allá de distancia_identificacion (× factor de alcance) el contador no supera
##    tope_contador_lejano (< 1): desde lejos solo hay percepción parcial.
##  · Umbrales: ≥ umbral_parcial → player_seen_partially(npc, creencias.certeza_parcial, sala del
##    jugador) una vez por contacto; ≥ umbral_flagrancia con delito → player_caught_redhanded(npc,
##    delito, testigos) una vez; testigos = OTROS Perception del árbol que ven al jugador en ese
##    instante (también a CaughtHandler.set_witness_ids); < umbral_perdida_contacto tras haber
##    contacto → reinicio y player_lost_from_sight.
##  · Cono: cono_angulo_base (hardliner: cono_angulo_hardliner) y cono_distancia_base, × (1 +
##    (perspicacia − perspicacia_neutra) × mod_*_por_punto) acotado. Muros y puertas (capa 1) y
##    muebles altos (capa 2) cortan la vista y el dibujo; muebles bajos (capa 3) = ×0,4.
##  · Oído: radio × ruido.reduccion_por_mascara si la sala del ruido es máscara acústica; oblivious
##    × oido_oblivious; tras un muro (capa 1) × factor_oido_muro. Los pasos normales de un jugador
##    que no llama la atención no giran cabezas; un ruido ≥ radio_ruido_anomalo sí (gira la
##    cabeza). Solo INVESTIGA (camina al origen) si su perspicacia efectiva ≥
##    umbral_investigar_ruido, no ve el origen y el ruido lo merece: del jugador digno de atención,
##    o ajeno ≥ radio_ruido_investigar (un esprint legal gira cabezas, no levanta a nadie).
##  · Dibujo: colores de la banda (art_bands) y del estado. En reposo, relleno palette.light con
##    borde palette.shadow (sobre suelos claros de la banda, relleno y borde palette.shadow): se lee
##    sobre moqueta oscura y sobre baldosa clara (las salas tienen su propio material de suelo). En
##    progreso/parcial/flagrancia, color del estado con borde oscurecido. Se reconstruye al
##    girar/moverse (como mucho cada intervalo_cono) o cada intervalo_cono_reposo, y solo se
##    redibuja si cambia algo.

signal state_changed(state: int)
signal witnessed(crime: String, identified: bool)

const GROUP := "perception"
const PLAYER_ID := "player"
const PLAYER_SOURCE := "player"
const STATE_NONE := 0
const STATE_PROGRESS := 1
const STATE_PARTIAL := 2
const STATE_FLAGRANT := 3
const CONE_OFF := 0
const CONE_AUTO := 1
const CONE_ALL := 2
const LOS_MASK := 0b011
const WALL_MASK := 0b001
const LOW_MASK := 0b100
const Z_CONE := -20
const CRIME_TRESPASS := "trespass"
const CRIME_BODY_MOVED := "body_moved"
const BAND_NIGHT := "night"
const ARCH_HARDLINER := "hardliner"
const ARCH_OBLIVIOUS := "oblivious"
const ARCH_OLD_HAND := "old_hand"
const MODE_STILL := "still"
const MODE_SPRINT := "sprint"
const MODE_SNEAK := "sneak"
const MASK_KEY := "acoustic_mask"
const WITNESS_METHOD := "set_witness_ids"
const RIM_WIDTH := 1.5
const RIM_WIDTH_CALM := 1.0
## Oscurecido del borde de un cono de estado (amarillo/naranja/rojo) respecto a su relleno.
const STATE_RIM_DARKEN := 0.35
## Giro mínimo (coseno) o desplazamiento (px²) que obliga a reconstruir el cono.
const REBUILD_COS := 0.9994
const REBUILD_MOVE_SQ := 4.0
const FILL_KEYS: Array[String] = ["velocidad_llenado_base", "mod_perspicacia_por_punto", "distancia_minima",
	"distancia_referencia", "factor_distancia_max", "mod_agachado", "mod_inmovil", "mod_esprint",
	"mod_obstruccion_parcial"]
const TICK_KEYS: Array[String] = ["umbral_parcial", "umbral_flagrancia", "umbral_perdida_contacto",
	"velocidad_vaciado_base", "velocidad_vaciado_minima", "factor_vaciado_relativo", "segundos_atencion",
	"tope_contador_lejano", "mod_cuerpo_arrastrado", "factor_identificacion_cuerpo",
	"tope_contador_presencia", "radio_proximidad_m", "factor_proximidad", "intervalo_cono", "intervalo_cono_reposo",
	"radio_conos_visibles", "alfa_cono", "alfa_cono_sigilo", "alfa_cono_alerta", "alfa_cono_depuracion",
	"factor_borde_cono", "velocidad_giro_cono", "umbral_investigar_ruido", "radio_ruido_anomalo",
	"radio_ruido_investigar", "oido_oblivious", "factor_oido_muro", "desvanecido_borde_cono",
	"velocidad_fundido_cono", "salto_refinado_cono", "tolerancia_cache_disfraz"]
const NO_DISGUISE: Dictionary = {"factor": 1.0, "suspicious": false, "hidden": false, "recognised": false}
const EMPTY_SAMPLE: Dictionary = {"rate": 0.0, "cap": 0.0, "crime": "", "noteworthy": false, "hidden": false,
	"distance": 0.0}

## Modo de conos compartido (ajuste "vision_cones", lo fija NPCLayer).
static var cone_mode: int = CONE_AUTO

var npc_id: String = ""
var archetype: String = ""
var _cell: float = 48.0
var _dir: Vector2 = Vector2.DOWN
var _target_dir: Vector2 = Vector2.DOWN
var _perception_eff: int = 0
var _half_angle: float = 0.6
var _range_px: float = 384.0
var _ident_px: float = 240.0
var _counter: float = 0.0
var _last_fill: float = 0.0
var _state: int = STATE_NONE
var _contact: bool = false
var _noteworthy_contact: bool = false
var _partial_sent: bool = false
var _flagrant_sent: bool = false
var _flagrant_hidden: bool = false
var _attention: Vector2 = Vector2.INF
var _attention_left: float = 0.0
var _anomaly: Vector2 = Vector2.INF
var _active: bool = true
var _debug_cones: bool = false
var _cone: PackedVector2Array = []
var _cone_dir: Vector2 = Vector2.ZERO
var _cone_pos: Vector2 = Vector2.INF
var _since_build: float = 0.0
var _cone_alpha: float = 0.0
var _drawn_alpha: float = -1.0
var _cone_color: Color = Color.WHITE
var _rim_color: Color = Color.BLACK
var _base_color: Color = Color.WHITE
var _base_rim: Color = Color.BLACK
var _contrast: bool = false
var _tun: Dictionary = {}
var _dz: Dictionary = {}
var _dz_distance: float = -1.0
var _dz_uniform: String = ""


func _ready() -> void:
	add_to_group(GROUP)
	z_as_relative = false
	z_index = Z_CONE
	visible = false


## Identidad del observador; lee sus parámetros de cono (perspicacia efectiva de NPCDirector).
func setup(p_npc_id: String, p_archetype: String) -> void:
	npc_id = p_npc_id
	archetype = p_archetype
	_load_tunables()
	refresh_traits()
	_debug_cones = DebugPanel.cones_visible
	set_band_colors(UITheme.band_for_floor(PlayerState.get_floor()))


func _load_tunables() -> void:
	_cell = Database.get_balance_float("mundo.px_por_unidad")
	for key: String in TICK_KEYS:
		_tun[key] = Database.get_balance_float("percepcion." + key)
	_tun.merge(load_fill_tunables(), true)
	_tun["certeza_parcial"] = Database.get_balance_float("creencias.certeza_parcial")
	_tun["certeza_completa"] = Database.get_balance_float("creencias.certeza_directa_completa")
	_tun["rayos_cono"] = maxi(2, Database.get_balance_int("percepcion.rayos_cono"))
	_tun["refinado_cono"] = Database.get_balance_int("percepcion.refinado_cono")


## Recalcula ángulo y alcance del cono con la perspicacia efectiva actual (sospecha incluida) y
## olvida la evaluación del disfraz (NPCNode.think la llama cada lod.intervalo_medio_segundos).
func refresh_traits() -> void:
	_dz_distance = -1.0
	_perception_eff = NPCDirector.get_effective_perception(npc_id) if not npc_id.is_empty() else 0
	var neutral: float = Database.get_balance_float("percepcion.perspicacia_neutra")
	var f_min: float = Database.get_balance_float("percepcion.factor_cono_min")
	var f_max: float = Database.get_balance_float("percepcion.factor_cono_max")
	var delta_p: float = float(_perception_eff) - neutral
	var fa: float = clampf(1.0 + delta_p * Database.get_balance_float("percepcion.mod_angulo_por_punto"), f_min, f_max)
	var fr: float = clampf(1.0 + delta_p * Database.get_balance_float("percepcion.mod_alcance_por_punto"), f_min, f_max)
	var base_angle: String = "percepcion.cono_angulo_hardliner" if archetype == ARCH_HARDLINER \
			else "percepcion.cono_angulo_base"
	_half_angle = deg_to_rad(Database.get_balance_float(base_angle) * fa) * 0.5
	_range_px = Database.get_balance_float("percepcion.cono_distancia_base") * fr * _cell
	_ident_px = Database.get_balance_float("percepcion.distancia_identificacion") * fr * _cell


## Colores de reposo del cono (art_bands): relleno con la luz de la banda y borde con su sombra;
## sobre suelos claros (luminancia ≥ percepcion.luminancia_suelo_clara), ambos con la sombra.
func set_band_colors(band: Dictionary) -> void:
	var palette: Dictionary = band.get("palette", {})
	var floor_c: Color = Color(str(palette.get("floor", "#808080")))
	var light: bool = floor_c.get_luminance() >= Database.get_balance_float("percepcion.luminancia_suelo_clara")
	_base_rim = Color(str(palette.get("shadow", "#000000")))
	_base_color = _base_rim if light else Color(str(palette.get("light", "#ffffff")))
	_refresh_colors()


func _refresh_colors() -> void:
	_contrast = UITheme.current_high_contrast
	_cone_color = _state_color()
	_rim_color = _base_rim if _state == STATE_NONE else _cone_color.darkened(STATE_RIM_DARKEN)
	_drawn_alpha = -1.0


# ─── Consultas ────────────────────────────────────────────────

func get_counter() -> float:
	return _counter


func get_state() -> int:
	return _state


func get_perception_value() -> int:
	return _perception_eff


func get_view_direction() -> Vector2:
	return _dir


func get_half_angle() -> float:
	return _half_angle


func get_range_px() -> float:
	return _range_px


func get_identification_range_px() -> float:
	return _ident_px


## Velocidad de vaciado actual (1/s): más lenta que el último llenado (§7.3).
func get_drain_rate() -> float:
	return drain_rate_for(_last_fill, _tun)


## Vigila al jugador: contacto vivo con algo digno de atención (en progreso o parcial). Mientras
## dura, su personaje aplaza los recados de denuncia/confrontación (NPCNode).
func is_watching() -> bool:
	return _contact and _noteworthy_contact and (_state == STATE_PROGRESS or _state == STATE_PARTIAL)


## Origen del último ruido atendido (Vector2.INF si ya no le presta atención).
func get_attention_point() -> Vector2:
	return _attention if _attention_left > 0.0 else Vector2.INF


## old_hand: posición de la anomalía (jugador digno de atención a la vista) o Vector2.INF.
func get_anomaly_point() -> Vector2:
	return _anomaly


func is_active() -> bool:
	return _active


## LOD 0 = activo (cono, oído, contador); LOD 1 = solo se vacía y no dibuja.
func set_active(active: bool) -> void:
	_active = active


func set_debug_cones(on: bool) -> void:
	_debug_cones = on
	_drawn_alpha = -1.0


## Rumbo de la cabeza (el cono gira hacia él a percepcion.velocidad_giro_cono rad/s).
func set_view(dir: Vector2, snap: bool = false) -> void:
	if dir.length_squared() < 0.0001:
		return
	_target_dir = dir.normalized()
	if snap:
		_dir = _target_dir


## Alcance + ángulo + línea de visión (muros, puertas y muebles altos). Lo barato primero.
func sees_point(pos: Vector2) -> bool:
	var to: Vector2 = pos - global_position
	var d2: float = to.length_squared()
	if d2 > _range_px * _range_px:
		return false
	if d2 > 1.0 and absf(_dir.angle_to(to)) > _half_angle:
		return false
	return has_line_of_sight(pos)


## §12.2: ¿llegaría el contador a flagrancia si el jugador hiciera ahora un acto quieto de
## `seconds` en `pos`? (aviso "te está mirando" veraz: no basta con estar en el cono).
func would_catch_in(pos: Vector2, seconds: float) -> bool:
	if not is_active() or not sees_point(pos):
		return false
	var dist: float = global_position.distance_to(pos)
	if dist > _ident_px:
		return false
	var d_m: float = dist / _cell
	var view: Dictionary = _disguise_view(d_m, PlayerState.get_room())
	var rate: float = fill_rate(d_m, _perception_eff, MODE_STILL, false,
			_ray_blocked(global_position, pos, LOW_MASK), _tun) * float(view["factor"])
	return _counter + rate * maxf(seconds, 0.0) >= float(_tun["umbral_flagrancia"])


func has_line_of_sight(pos: Vector2) -> bool:
	return not _ray_blocked(global_position, pos, LOS_MASK)


## Podría verle con solo girarse: dentro del alcance del cono y con línea de visión (sin ángulo).
## Es el «hay observadores» de GameClock.advance_to_band (NPCLayer.observers_present).
func can_notice(pos: Vector2) -> bool:
	return global_position.distance_squared_to(pos) <= _range_px * _range_px and has_line_of_sight(pos)


func _ray_blocked(from: Vector2, to: Vector2, mask: int) -> bool:
	if not is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, mask)
	query.hit_from_inside = false
	return not space.intersect_ray(query).is_empty()


# ─── Detección progresiva ─────────────────────────────────────

## Un fotograma: rumbo del cono, contador, umbrales y alfa del dibujo. `exposure` es el de
## assess_exposure() (+ "room": sala del jugador); sin jugador (LOD 1) o escondido, se vacía.
func tick(delta: float, player: Node2D, exposure: Dictionary) -> void:
	_attention_left = maxf(0.0, _attention_left - delta)
	_turn_view(delta)
	_anomaly = Vector2.INF
	var sample: Dictionary = EMPTY_SAMPLE
	if _active and player != null and not exposure.is_empty() and not bool(exposure.get("hidden", false)) \
			and _str_call(player, "current_act_target") != npc_id:
		sample = _sample(player, exposure)
	_advance_counter(delta, float(sample["rate"]), float(sample["cap"]))
	_check_thresholds(player, exposure, sample)
	_update_cone(delta, player, exposure)


func _turn_view(delta: float) -> void:
	var angle: float = _dir.angle_to(_target_dir)
	var step: float = float(_tun.get("velocidad_giro_cono", TAU)) * delta
	_dir = _target_dir if absf(angle) <= step else _dir.rotated(signf(angle) * step)


## {rate, cap, crime, noteworthy, hidden, distance} de este observador si el jugador está en su
## cono con línea de visión (si no, EMPTY_SAMPLE).
func _sample(player: Node2D, exposure: Dictionary) -> Dictionary:
	var pos: Vector2 = player.global_position
	var dist: float = global_position.distance_to(pos)
	if archetype == ARCH_OLD_HAND and bool(exposure.get("noteworthy", false)) and dist <= _range_px \
			and has_line_of_sight(pos):
		_anomaly = pos
	var d_m: float = dist / _cell
	# §7.3: además del cono, sentido periférico/auditivo a muy corta distancia (alguien pegado a
	# la espalda se nota), más lento que la vista directa.
	var proximity: bool = false
	if not sees_point(pos):
		if d_m > float(_tun["radio_proximidad_m"]) or not has_line_of_sight(pos):
			return EMPTY_SAMPLE
		proximity = true
	var room: String = str(exposure.get("room", ""))
	var view: Dictionary = _disguise_view(d_m, room)
	var crime: String = str(exposure.get("crime", ""))
	if crime == CRIME_TRESPASS and bool(exposure.get("uniform_access", false)) and not bool(view["recognised"]):
		crime = ""
	var noteworthy: bool = not crime.is_empty() or bool(view["suspicious"])
	var obstructed: bool = _ray_blocked(global_position, pos, LOW_MASK)
	var rate: float = fill_rate(d_m, _perception_eff, _str_call(player, "movement_mode"),
			_bool_call(player, "is_crouching"), obstructed, _tun) * float(view["factor"])
	if proximity:
		rate *= float(_tun["factor_proximidad"])
	var cap: float = float(_tun["umbral_flagrancia"])
	var ident_px: float = _ident_px
	# Un cuerpo arrastrado a la vista llama la atención (§12.2/§12.3): más llenado y más alcance.
	if crime == CRIME_BODY_MOVED:
		rate *= float(_tun["mod_cuerpo_arrastrado"])
		ident_px *= float(_tun["factor_identificacion_cuerpo"])
	if dist > ident_px:
		cap = float(_tun["tope_contador_lejano"])
	if not noteworthy:
		cap = minf(cap, float(_tun["tope_contador_presencia"]))
	return {"rate": rate, "cap": cap, "crime": crime, "noteworthy": noteworthy,
			"hidden": bool(view["hidden"]), "distance": d_m}


## Llena hacia `cap` a `rate`; por encima del tope (dejó de ser digno de atención, se alejó) o
## fuera del cono, se vacía a get_drain_rate().
func _advance_counter(delta: float, rate: float, cap: float) -> void:
	if rate > 0.0:
		_last_fill = rate
		if _counter < cap:
			_counter = minf(_counter + rate * delta, cap)
		elif _counter > cap:
			_counter = maxf(_counter - get_drain_rate() * delta, cap)
	else:
		_counter = maxf(_counter - get_drain_rate() * delta, 0.0)


func _check_thresholds(player: Node2D, exposure: Dictionary, sample: Dictionary) -> void:
	if _counter >= float(_tun["umbral_perdida_contacto"]):
		_contact = true
	elif _contact:
		reset_contact()
		EventBus.player_lost_from_sight.emit(npc_id)
	if bool(sample["noteworthy"]) and float(sample["rate"]) > 0.0:
		_noteworthy_contact = true
	if _counter >= float(_tun["umbral_parcial"]) and not _partial_sent:
		_partial_sent = true
		_emit_partial(sample, str(exposure.get("room", PlayerState.get_room())))
	var crime: String = str(sample["crime"])
	if _counter >= float(_tun["umbral_flagrancia"]) and not _flagrant_sent and not crime.is_empty():
		_flagrant_sent = true
		_flagrant_hidden = bool(sample["hidden"])
		if _flagrant_hidden:
			_believe_uniform(BeliefNetSystem.make_fact(BeliefNetSystem.FACT_CAUGHT_REDHANDED, crime),
					float(_tun["certeza_completa"]), sample, str(exposure.get("room", "")))
		else:
			_emit_caught(crime, player)
		witnessed.emit(crime, not _flagrant_hidden)
	_set_state(_compute_state())


## Contador a cero y umbrales rearmados (contacto perdido, cambio de planta).
func reset_contact() -> void:
	_counter = 0.0
	_last_fill = 0.0
	_contact = false
	_noteworthy_contact = false
	_partial_sent = false
	_flagrant_sent = false
	_flagrant_hidden = false
	_set_state(STATE_NONE)


func _compute_state() -> int:
	if _flagrant_sent and not _flagrant_hidden:
		return STATE_FLAGRANT
	if _counter >= float(_tun["umbral_parcial"]) or _flagrant_sent:
		return STATE_PARTIAL
	return STATE_PROGRESS if _counter > 0.0 else STATE_NONE


func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	_refresh_colors()
	state_changed.emit(state)


## Percepción parcial: creencia de certeza baja sobre el jugador (o sobre el uniforme si su
## identidad le queda oculta a este observador).
func _emit_partial(sample: Dictionary, room: String) -> void:
	var certainty: float = float(_tun["certeza_parcial"])
	if bool(sample["hidden"]):
		_believe_uniform(BeliefNetSystem.FACT_SEEN_PARTIALLY, certainty, sample, room)
	else:
		EventBus.player_seen_partially.emit(npc_id, certainty, room)


func _believe_uniform(fact: String, certainty: float, sample: Dictionary, room: String) -> void:
	var subject: String = Disguise.sighting_subject(npc_id, float(sample["distance"]), room)
	BeliefNet.create_belief(npc_id, subject, fact, certainty, Belief.SOURCE_DIRECT, room)


## Flagrancia con los testigos del instante (otros observadores que ven al jugador).
func _emit_caught(crime: String, player: Node2D) -> void:
	var ids: Array[String] = []
	if player != null and is_inside_tree():
		ids = witnesses_of(get_tree(), npc_id, player.global_position)
	EventBus.player_caught_redhanded.emit(npc_id, crime, ids.size())
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(SaveSystemNode.SCENE_GROUP):
		if node.has_method(WITNESS_METHOD):
			node.call(WITNESS_METHOD, npc_id, ids)


# ─── Funciones puras ──────────────────────────────────────────

## Tunables de fill_rate() (percepcion.*), para cachearlos.
static func load_fill_tunables() -> Dictionary:
	var out: Dictionary = {}
	for key: String in FILL_KEYS:
		out[key] = Database.get_balance_float("percepcion." + key)
	return out


## Velocidad de llenado (1/s) de §7.3 a `distance_m` metros (`tun`: load_fill_tunables()).
static func fill_rate(distance_m: float, perception: int, mode: String, crouching: bool,
		obstructed: bool, tun: Dictionary = {}) -> float:
	var t: Dictionary = tun if tun.has("mod_esprint") else load_fill_tunables()
	var base: float = float(t["velocidad_llenado_base"]) + float(perception) * float(t["mod_perspicacia_por_punto"])
	var d: float = maxf(distance_m, float(t["distancia_minima"]))
	var mult: float = minf(float(t["distancia_referencia"]) / d, float(t["factor_distancia_max"]))
	if crouching:
		mult *= float(t["mod_agachado"])
	if mode == MODE_STILL:
		mult *= float(t["mod_inmovil"])
	elif mode == MODE_SPRINT:
		mult *= float(t["mod_esprint"])
	if obstructed:
		mult *= float(t["mod_obstruccion_parcial"])
	return maxf(base, 0.0) * mult


## Vaciado (1/s) tras un llenado de `fill`: factor_vaciado_relativo × fill, acotado.
static func drain_rate_for(fill: float, tun: Dictionary = {}) -> float:
	var lo: float = float(tun["velocidad_vaciado_minima"]) if tun.has("velocidad_vaciado_minima") \
			else Database.get_balance_float("percepcion.velocidad_vaciado_minima")
	var hi: float = float(tun["velocidad_vaciado_base"]) if tun.has("velocidad_vaciado_base") \
			else Database.get_balance_float("percepcion.velocidad_vaciado_base")
	var k: float = float(tun["factor_vaciado_relativo"]) if tun.has("factor_vaciado_relativo") \
			else Database.get_balance_float("percepcion.factor_vaciado_relativo")
	return clampf(fill * k, lo, maxf(hi, lo))


## ¿Hay algo que detectar? {noteworthy, crime, hidden, room, uniform_access}. crime = acto en
## curso, "body_moved" (arrastra un cuerpo), "trespass" (sala no cubierta o fuera de horario) o "".
## uniform_access: la intrusión la cubre un uniforme coherente (solo cuenta si le reconocen).
static func assess_exposure(player: Node, room_id: String) -> Dictionary:
	var out: Dictionary = {"noteworthy": false, "crime": "", "hidden": false, "room": room_id,
			"uniform_access": false}
	if player == null:
		return out
	if _bool_call(player, "is_hiding"):
		out["hidden"] = true
		return out
	var crime: String = _str_call(player, "current_act")
	if crime.is_empty() and _bool_call(player, "is_dragging"):
		crime = CRIME_BODY_MOVED
	if crime.is_empty() and is_trespassing(room_id):
		crime = CRIME_TRESPASS
		out["uniform_access"] = uniform_covers(room_id)
	out["crime"] = crime
	var counts: bool = not crime.is_empty() and not bool(out["uniform_access"])
	out["noteworthy"] = counts or bool(disguise_effect("", 0.0, room_id)["suspicious"])
	return out


## Sala que la acreditación del jugador no cubre (regla del halo del HUD) o, de noche, sala con
## acreditación, sin ocupación nocturna y que no es la de su puesto.
static func is_trespassing(room_id: String) -> bool:
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room == null:
		return false
	var occupation: OccupationData = PlayerState.get_occupation()
	var access: Array[String] = []
	if occupation != null:
		access = occupation.special_access
	if room.clearance_required > PlayerState.get_clearance():
		var covered: bool = false
		for tag: String in room.special_access:
			covered = covered or access.has(tag)
		if not covered:
			return true
	if GameClock.get_current_band() != BAND_NIGHT or room.clearance_required <= 0:
		return false
	if occupation != null and DatabaseSystem.get_room_base_id(room.id) == occupation.office_room:
		return false
	return room.get_occupants(BAND_NIGHT) <= 0


## El disfraz puesto (no el uniforme del propio puesto ni el pasamontañas) es coherente ahora y
## su rol abre `room_id` (Disguise.grants_access).
static func uniform_covers(room_id: String) -> bool:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty() or uniform == Disguise.BALACLAVA:
		return false
	var canonical: String = Disguise.canonical_uniform(uniform)
	if canonical.is_empty() or Disguise.is_own_uniform(canonical):
		return false
	if not Disguise.is_coherent(canonical, GameClock.get_hour(), Disguise.room_floor(room_id)):
		return false
	return Disguise.grants_access(uniform, room_id) or Disguise.grants_access(canonical, room_id)


static func is_masked_room(room_id: String) -> bool:
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room == null:
		return false
	if room.extra.has(MASK_KEY):
		return bool(room.extra[MASK_KEY])
	return room.ambient_noise_level >= Database.get_balance_float("percepcion.umbral_mascara_ruido")


## Radio efectivo (metros) de un ruido emitido en `room_id` (máscara acústica: × 0,15).
static func effective_noise_radius(radius_m: float, room_id: String) -> float:
	if is_masked_room(room_id):
		return radius_m * Database.get_balance_float("ruido.reduccion_por_mascara")
	return radius_m


## Observadores (ids) del árbol que ven `pos`, sin contar a `exclude_id`.
static func witnesses_of(tree: SceneTree, exclude_id: String, pos: Vector2) -> Array[String]:
	var out: Array[String] = []
	if tree == null:
		return out
	for node: Node in tree.get_nodes_in_group(GROUP):
		var other: Perception = node as Perception
		if other == null or other.npc_id.is_empty() or other.npc_id == exclude_id:
			continue
		if other.is_inside_tree() and not out.has(other.npc_id) and other.sees_point(pos):
			out.append(other.npc_id)
	return out


static func _bool_call(obj: Object, method: String) -> bool:
	return obj != null and obj.has_method(method) and bool(obj.call(method))


static func _str_call(obj: Object, method: String) -> String:
	return str(obj.call(method)) if obj != null and obj.has_method(method) else ""


# ─── Disfraz (src/simulation/disguise.gd) ─────────────────────

## {factor, suspicious, hidden, recognised}: efecto del uniforme del jugador ante `observer_id`
## ("" = observador genérico) a `distance_m` metros en `room_id` (Disguise.evaluate).
static func disguise_effect(observer_id: String, distance_m: float, room_id: String) -> Dictionary:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty():
		return NO_DISGUISE.duplicate()
	var npc: NPCRuntime = NPCDirector.get_npc(observer_id) if not observer_id.is_empty() else null
	var r: Dictionary = Disguise.evaluate(uniform, GameClock.get_hour(), room_id, distance_m, npc)
	return {"factor": maxf(float(r[Disguise.R_MULTIPLIER]), 0.0), "suspicious": bool(r[Disguise.R_SUSPICIOUS]),
			"hidden": bool(r[Disguise.R_HIDDEN]), "recognised": bool(r[Disguise.R_RECOGNISED])}


## disguise_effect() de este observador, cacheado hasta que la distancia cambie más de
## percepcion.tolerancia_cache_disfraz metros, cambie el uniforme o piense (refresh_traits).
func _disguise_view(d_m: float, room_id: String) -> Dictionary:
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty():
		return NO_DISGUISE
	if _dz_distance >= 0.0 and uniform == _dz_uniform \
			and absf(d_m - _dz_distance) <= float(_tun["tolerancia_cache_disfraz"]):
		return _dz
	_dz = disguise_effect(npc_id, d_m, room_id)
	_dz_distance = d_m
	_dz_uniform = uniform
	return _dz


# ─── Oído ─────────────────────────────────────────────────────

## Ruido en `origin` de `radius_m` metros emitido en `room_id`. {} si no lo oye o no le importa.
func hear(origin: Vector2, radius_m: float, source: String, room_id: String, noteworthy: bool) -> Dictionary:
	if npc_id.is_empty() or not _active:
		return {}
	var player_alert: bool = noteworthy and source == PLAYER_SOURCE
	if radius_m < float(_tun["radio_ruido_anomalo"]) and not player_alert:
		return {}
	var radius: float = effective_noise_radius(radius_m, room_id)
	if archetype == ARCH_OBLIVIOUS:
		radius *= float(_tun["oido_oblivious"])
	var d_m: float = global_position.distance_to(origin) / _cell
	if d_m > radius:
		return {}
	if d_m > radius * float(_tun["factor_oido_muro"]) and _ray_blocked(global_position, origin, WALL_MASK):
		return {}
	_attention = origin
	_attention_left = float(_tun["segundos_atencion"])
	var worth: bool = player_alert or (source != PLAYER_SOURCE and radius_m >= float(_tun["radio_ruido_investigar"]))
	var investigate: bool = worth and float(_perception_eff) >= float(_tun["umbral_investigar_ruido"]) \
			and not sees_point(origin)
	return {"origin": origin, "investigate": investigate, "distance": d_m}


# ─── Dibujo del cono ──────────────────────────────────────────

func _update_cone(delta: float, player: Node2D, exposure: Dictionary) -> void:
	var target: float = _cone_target_alpha(player, exposure)
	_cone_alpha = move_toward(_cone_alpha, target, delta * float(_tun["velocidad_fundido_cono"]))
	visible = _cone_alpha > 0.0
	if not visible:
		_drawn_alpha = 0.0
		return
	_since_build += delta
	if _contrast != UITheme.current_high_contrast:
		_refresh_colors()
	var dirty: bool = absf(_cone_alpha - _drawn_alpha) > 0.002
	if _needs_rebuild(target):
		_since_build = 0.0
		_rebuild_cone()
		dirty = true
	if dirty:
		_drawn_alpha = _cone_alpha
		queue_redraw()


## Reconstruye si giró o se movió (como mucho cada intervalo_cono) o cada intervalo_cono_reposo
## (puertas que se abren); un cono en reposo que no cambia no gasta rayos.
func _needs_rebuild(target_alpha: float) -> bool:
	if _cone.is_empty():
		return true
	var calm: bool = target_alpha <= float(_tun["alfa_cono"])
	if _since_build >= float(_tun["intervalo_cono_reposo" if calm else "intervalo_cono"]):
		return true
	if _since_build < float(_tun["intervalo_cono"]):
		return false
	return _dir.dot(_cone_dir) < REBUILD_COS or global_position.distance_squared_to(_cone_pos) > REBUILD_MOVE_SQ


func _cone_target_alpha(player: Node2D, exposure: Dictionary) -> float:
	if _debug_cones:
		return float(_tun["alfa_cono_depuracion"])
	if not _active or cone_mode == CONE_OFF or player == null:
		return 0.0
	var near: bool = global_position.distance_squared_to(player.global_position) \
			<= pow(float(_tun["radio_conos_visibles"]) * _cell, 2.0)
	if not near and cone_mode != CONE_ALL:
		return 0.0
	if _counter > 0.0:
		return float(_tun["alfa_cono_alerta"])
	var stealthy: bool = bool(exposure.get("noteworthy", false)) or _bool_call(player, "is_crouching") \
			or _str_call(player, "movement_mode") == MODE_SNEAK
	return float(_tun["alfa_cono_sigilo"] if stealthy else _tun["alfa_cono"])


func _state_color() -> Color:
	var pal: Dictionary = UITheme.palette(UITheme.current_high_contrast)
	match _state:
		STATE_PROGRESS:
			return pal["det_progress"]
		STATE_PARTIAL:
			return pal["det_partial"]
		STATE_FLAGRANT:
			return pal["det_flagrant"]
	return _base_color


## Contorno: percepcion.rayos_cono rayos + bisección en los saltos (jambas nítidas).
func _rebuild_cone() -> void:
	var rays: int = int(_tun["rayos_cono"])
	var depth: int = int(_tun["refinado_cono"])
	var pts: PackedVector2Array = [Vector2.ZERO]
	var prev_a: float = -_half_angle
	var prev: Vector2 = _cast(prev_a)
	pts.append(prev)
	for i: int in range(1, rays + 1):
		var a: float = -_half_angle + 2.0 * _half_angle * i / rays
		var hit: Vector2 = _cast(a)
		_refine(pts, prev_a, prev, a, hit, depth)
		pts.append(hit)
		prev_a = a
		prev = hit
	_cone = pts
	_cone_dir = _dir
	_cone_pos = global_position


func _cast(a: float) -> Vector2:
	var to: Vector2 = global_position + _dir.rotated(a) * _range_px
	if not is_inside_tree():
		return to_local(to)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, to, LOS_MASK)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query) if space != null else {}
	return to_local(to if hit.is_empty() else (hit["position"] as Vector2))


func _refine(pts: PackedVector2Array, a0: float, p0: Vector2, a1: float, p1: Vector2, depth: int) -> void:
	if depth <= 0 or absf(p0.length() - p1.length()) < float(_tun["salto_refinado_cono"]) * _cell:
		return
	var mid: float = (a0 + a1) * 0.5
	var pm: Vector2 = _cast(mid)
	_refine(pts, a0, p0, mid, pm, depth - 1)
	pts.append(pm)
	_refine(pts, mid, pm, a1, p1, depth - 1)


## Abanico de triángulos con degradado radial y borde fino antialiasado (franja con plumas
## transparentes: el arco exterior y los dos lados, que se desvanecen hacia el vértice), todo en UNA
## orden de dibujo (índices explícitos: sin triangulación, robusto junto a los muros).
func _draw() -> void:
	if _cone_alpha <= 0.0 or _cone.size() < 3:
		return
	var pts: PackedVector2Array = PackedVector2Array(_cone)
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(pts.size())
	colors.fill(Color(_cone_color, _cone_alpha * float(_tun["desvanecido_borde_cono"])))
	colors[0] = Color(_cone_color, _cone_alpha)
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, pts.size() - 1):
		indices.append_array([0, i, i + 1])
	var calm: bool = _cone_alpha <= float(_tun["alfa_cono"]) + 0.001
	var edge: Color = Color(_rim_color, minf(1.0, _cone_alpha * float(_tun["factor_borde_cono"])))
	var width: float = RIM_WIDTH_CALM if calm else RIM_WIDTH
	var last: int = _cone.size() - 1
	_append_stroke(pts, colors, indices, _cone[0], _cone[1], Color(edge, 0.0), edge, width)
	for i: int in range(1, last):
		_append_stroke(pts, colors, indices, _cone[i], _cone[i + 1], edge, edge, width)
	_append_stroke(pts, colors, indices, _cone[last], _cone[0], edge, Color(edge, 0.0), width)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, pts, colors)


## Tramo a→b de `width` px: línea central con su color y plumas transparentes a los lados.
static func _append_stroke(pts: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array,
		a: Vector2, b: Vector2, col_a: Color, col_b: Color, width: float) -> void:
	var n: Vector2 = (b - a).orthogonal().normalized() * width
	if n == Vector2.ZERO:
		return
	var base: int = pts.size()
	pts.append_array([a + n, a, a - n, b + n, b, b - n])
	colors.append_array([Color(col_a, 0.0), col_a, Color(col_a, 0.0), Color(col_b, 0.0), col_b, Color(col_b, 0.0)])
	indices.append_array([base, base + 1, base + 4, base, base + 4, base + 3,
			base + 1, base + 2, base + 5, base + 1, base + 5, base + 4])
