# perception.gd — Percepción de un personaje (§7.3, PASO 10-11): cono de visión progresivo con línea de visión real, oído con máscaras acústicas y dibujo del cono.
# PROPIETARIO DE: el contador de detección de su personaje, su contacto con el jugador (umbrales ya emitidos), su foco de atención auditiva y el contorno de su cono.
# ESCUCHA: nada (su NPCNode le entrega cada fotograma con tick(); NPCLayer le reparte EventBus.noise_emitted con hear()).
class_name Perception
extends Node2D

## Contrato (BUILD_NOTES §13-§14). Hijo de cada NPCNode, grupo "perception":
##   setup(npc_id, archetype) · set_view(dir) (rumbo de la CABEZA: el cono la sigue)
##   tick(delta, player, exposure) cada fotograma en LOD 0 (en LOD 1: tick(delta, null, {}) → se vacía)
##   hear(origin, radius_m, source, room_id, noteworthy) -> {} | {origin, investigate, distance}
##   sees_point(pos) (alcance + ángulo + línea de visión) · has_line_of_sight(pos)
##   get_counter() · get_state() (STATE_*) · get_attention_point() · get_anomaly_point()
##   set_debug_cones(on) (panel F1) · static cone_mode (0 ocultos, 1 automático, 2 todos)
## DECISIONES:
##  · «Verte trabajar es normal» (§7.3): el contador SOLO se llena si el jugador es digno de
##    atención (assess_exposure): acto en curso (Player.current_act), arrastrar un cuerpo, una sala
##    que su acreditación no cubre (misma regla que el halo del HUD) o, de noche, una sala con
##    acreditación sin ocupación nocturna que no es su puesto; o un disfraz incoherente
##    (Disguise). Si no, no hay nada que detectar: el contador se vacía y no se emite nada.
##  · Llenado/s = (velocidad_llenado_base + perspicacia_efectiva × mod_perspicacia_por_punto)
##    × min(distancia_referencia / d, factor_distancia_max) × agachado × inmóvil × esprint
##    × obstrucción parcial (capa 3) × disfraz. La perspicacia efectiva es la de NPCDirector
##    (ya incluye la sospecha, +0,005/punto, y el plus de alerta de los vigilantes).
##  · Más allá de distancia_identificacion (× factor de alcance) el contador no supera
##    tope_contador_lejano (< 1): desde lejos solo hay percepción parcial (creencia de certeza
##    baja); la identificación completa exige acercarse.
##  · Umbrales: ≥ umbral_parcial → player_seen_partially(npc, creencias.certeza_parcial, sala del
##    jugador) una vez por contacto; ≥ umbral_flagrancia con delito → player_caught_redhanded(npc,
##    delito, testigos) una vez; testigos = OTROS Perception del árbol que ven al jugador en ese
##    instante (también a CaughtHandler.set_witness_ids); < umbral_perdida_contacto tras haber
##    contacto → reinicio y player_lost_from_sight.
##  · Cono: cono_angulo_base (hardliner: cono_angulo_hardliner) y cono_distancia_base, × (1 +
##    (perspicacia − perspicacia_neutra) × mod_*_por_punto) acotado. Muros y puertas (capa 1) y
##    muebles altos (capa 2) cortan la vista y el dibujo; muebles bajos (capa 3) = ×0,4.
##  · Oído: radio × ruido.reduccion_por_mascara si la sala del ruido tiene acoustic_mask;
##    oblivious × oido_oblivious. Los pasos normales de un jugador que no llama la atención no
##    giran cabezas; un ruido ≥ radio_ruido_anomalo, o cualquier ruido suyo si es digno de
##    atención, sí. Investiga (camina al origen) si la perspicacia efectiva ≥
##    umbral_investigar_ruido y no ve el origen.

signal state_changed(state: int)

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
const DISGUISE_SCRIPT := "res://src/simulation/disguise.gd"
const DISGUISE_DIRECT := "detection_factor"
const DISGUISE_METHOD := "evaluate"
const DISGUISE_FACTOR_KEYS: Array[String] = [
	"detection_factor", "detection_multiplier", "multiplier", "factor", "perception_factor",
]
const DISGUISE_SUSPICIOUS_KEYS: Array[String] = ["suspicious", "incoherent", "out_of_context"]
const RIM_WIDTH := 1.5

## Modo de conos compartido (ajuste "vision_cones", lo fija NPCLayer).
static var cone_mode: int = CONE_AUTO
static var _disguise_checked: bool = false
static var _disguise: Object = null
static var _disguise_info: Dictionary = {}

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
var _state: int = STATE_NONE
var _contact: bool = false
var _partial_sent: bool = false
var _flagrant_sent: bool = false
var _attention: Vector2 = Vector2.INF
var _attention_left: float = 0.0
var _anomaly: Vector2 = Vector2.INF
var _active: bool = true
var _debug_cones: bool = false
var _cone: PackedVector2Array = []
var _cone_timer: float = 0.0
var _cone_alpha: float = 0.0
var _cone_color: Color = Color.WHITE
var _base_color: Color = Color.WHITE
var _tun: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	z_as_relative = false
	z_index = Z_CONE


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
	for key: String in ["umbral_parcial", "umbral_flagrancia", "umbral_perdida_contacto",
			"velocidad_vaciado_base", "segundos_atencion", "tope_contador_lejano", "intervalo_cono",
			"radio_conos_visibles", "alfa_cono", "alfa_cono_sigilo", "alfa_cono_alerta",
			"alfa_cono_depuracion", "factor_borde_cono", "velocidad_giro_cono", "umbral_investigar_ruido",
			"radio_ruido_anomalo", "oido_oblivious", "desvanecido_borde_cono", "velocidad_fundido_cono"]:
		_tun[key] = Database.get_balance_float("percepcion." + key)
	_tun["certeza_parcial"] = Database.get_balance_float("creencias.certeza_parcial")


## Recalcula ángulo y alcance del cono con la perspicacia efectiva actual (sospecha incluida).
func refresh_traits() -> void:
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


## Color de reposo del cono: luz cálida (percepcion.color_cono) o, sobre suelos claros de la
## banda, un tono oscuro (percepcion.color_cono_suelo_claro) para que se lea.
func set_band_colors(band: Dictionary) -> void:
	var palette: Dictionary = band.get("palette", {})
	var floor_c: Color = Color(str(palette.get("floor", "#808080")))
	var light: bool = floor_c.get_luminance() >= Database.get_balance_float("percepcion.luminancia_suelo_clara")
	var rgb: Array = Database.get_balance("percepcion.color_cono_suelo_claro" if light else "percepcion.color_cono")
	_base_color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	_cone_color = _base_color


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
	queue_redraw()


## Rumbo de la cabeza (el cono gira hacia él a percepcion.velocidad_giro_cono rad/s).
func set_view(dir: Vector2, snap: bool = false) -> void:
	if dir.length_squared() < 0.0001:
		return
	_target_dir = dir.normalized()
	if snap:
		_dir = _target_dir


## Alcance + ángulo + línea de visión (muros, puertas y muebles altos).
func sees_point(pos: Vector2) -> bool:
	var to: Vector2 = pos - global_position
	if to.length() > _range_px:
		return false
	if to.length() > 1.0 and absf(_dir.angle_to(to)) > _half_angle:
		return false
	return has_line_of_sight(pos)


func has_line_of_sight(pos: Vector2) -> bool:
	return not _ray_blocked(global_position, pos, LOS_MASK)


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
## assess_exposure() (+ "room": sala del jugador); sin jugador o sin exposición, se vacía.
func tick(delta: float, player: Node2D, exposure: Dictionary) -> void:
	_attention_left = maxf(0.0, _attention_left - delta)
	_turn_view(delta)
	_anomaly = Vector2.INF
	var rate: float = 0.0
	var cap: float = float(_tun["umbral_flagrancia"])
	if _active and player != null and bool(exposure.get("noteworthy", false)):
		var sample: Dictionary = _sample(player, str(exposure.get("room", "")))
		rate = float(sample["rate"])
		cap = float(sample["cap"])
	if rate > 0.0:
		if _counter < cap:
			_counter = minf(_counter + rate * delta, cap)
	else:
		_counter = maxf(_counter - float(_tun["velocidad_vaciado_base"]) * delta, 0.0)
	_check_thresholds(player, exposure)
	_update_cone(delta, player, exposure)


func _turn_view(delta: float) -> void:
	var angle: float = _dir.angle_to(_target_dir)
	var step: float = float(_tun.get("velocidad_giro_cono", TAU)) * delta
	_dir = _target_dir if absf(angle) <= step else _dir.rotated(signf(angle) * step)


## {rate, cap}: velocidad de llenado si el jugador está en el cono con línea de visión.
func _sample(player: Node2D, room_id: String) -> Dictionary:
	var out: Dictionary = {"rate": 0.0, "cap": float(_tun["umbral_flagrancia"])}
	var pos: Vector2 = player.global_position
	var dist: float = global_position.distance_to(pos)
	if archetype == ARCH_OLD_HAND and dist <= _range_px and has_line_of_sight(pos):
		_anomaly = pos
	if not sees_point(pos):
		return out
	var d_m: float = dist / _cell
	var obstructed: bool = _ray_blocked(global_position, pos, LOW_MASK)
	var rate: float = fill_rate(d_m, _perception_eff, _str_call(player, "movement_mode"),
			_bool_call(player, "is_crouching"), obstructed)
	out["rate"] = rate * float(disguise_effect(npc_id, d_m, room_id)["factor"])
	if dist > _ident_px:
		out["cap"] = float(_tun["tope_contador_lejano"])
	return out


func _check_thresholds(player: Node2D, exposure: Dictionary) -> void:
	if _counter >= float(_tun["umbral_perdida_contacto"]):
		_contact = true
	elif _contact:
		reset_contact()
		EventBus.player_lost_from_sight.emit(npc_id)
	if _counter >= float(_tun["umbral_parcial"]) and not _partial_sent:
		_partial_sent = true
		EventBus.player_seen_partially.emit(npc_id, float(_tun["certeza_parcial"]),
				str(exposure.get("room", PlayerState.get_room())))
	var crime: String = str(exposure.get("crime", ""))
	if _counter >= float(_tun["umbral_flagrancia"]) and not _flagrant_sent and not crime.is_empty():
		_flagrant_sent = true
		_emit_caught(crime, player)
	_set_state(_compute_state())


## Contador a cero y umbrales rearmados (contacto perdido, cambio de planta).
func reset_contact() -> void:
	_counter = 0.0
	_contact = false
	_partial_sent = false
	_flagrant_sent = false
	_set_state(STATE_NONE)


func _compute_state() -> int:
	if _flagrant_sent:
		return STATE_FLAGRANT
	if _counter >= float(_tun["umbral_parcial"]):
		return STATE_PARTIAL
	return STATE_PROGRESS if _counter > 0.0 else STATE_NONE


func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


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

## Velocidad de llenado (1/s) de §7.3 a `distance_m` metros.
static func fill_rate(distance_m: float, perception: int, mode: String, crouching: bool,
		obstructed: bool) -> float:
	var base: float = Database.get_balance_float("percepcion.velocidad_llenado_base") \
			+ float(perception) * Database.get_balance_float("percepcion.mod_perspicacia_por_punto")
	var d: float = maxf(distance_m, Database.get_balance_float("percepcion.distancia_minima"))
	var dist_factor: float = minf(Database.get_balance_float("percepcion.distancia_referencia") / d,
			Database.get_balance_float("percepcion.factor_distancia_max"))
	var mult: float = 1.0
	if crouching:
		mult *= Database.get_balance_float("percepcion.mod_agachado")
	if mode == MODE_STILL:
		mult *= Database.get_balance_float("percepcion.mod_inmovil")
	elif mode == MODE_SPRINT:
		mult *= Database.get_balance_float("percepcion.mod_esprint")
	if obstructed:
		mult *= Database.get_balance_float("percepcion.mod_obstruccion_parcial")
	return maxf(base, 0.0) * dist_factor * mult


## ¿Hay algo que detectar? {noteworthy, crime, hidden}. crime = acto en curso, "body_moved"
## (arrastra un cuerpo), "trespass" (sala no cubierta o fuera de horario) o "".
static func assess_exposure(player: Node, room_id: String) -> Dictionary:
	var out: Dictionary = {"noteworthy": false, "crime": "", "hidden": false, "room": room_id}
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
	out["crime"] = crime
	out["noteworthy"] = not crime.is_empty() or bool(disguise_effect("", 0.0, room_id)["suspicious"])
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


# ─── Disfraz (src/simulation/disguise.gd, puede no existir aún) ─

## {factor, suspicious}: efecto del uniforme del jugador ante este observador. Sin disfraz o sin
## módulo Disguise: {1.0, false}. Acepta Disguise.detection_factor(npc_id, distance_m, room_id)
## -> float o Disguise.evaluate(...) con argumentos por nombre (-> float | Dictionary).
static func disguise_effect(observer_id: String, distance_m: float, room_id: String) -> Dictionary:
	var out: Dictionary = {"factor": 1.0, "suspicious": false}
	var uniform: String = PlayerState.get_disguise()
	if uniform.is_empty() or not _load_disguise():
		return out
	var args: Array = _disguise_args(observer_id, distance_m, room_id, uniform)
	if args.size() < int(_disguise_info.get("required", 0)):
		return out
	return _read_disguise_result(_disguise.callv(str(_disguise_info["name"]), args), out)


static func _load_disguise() -> bool:
	if _disguise_checked:
		return _disguise != null
	_disguise_checked = true
	if not ResourceLoader.exists(DISGUISE_SCRIPT):
		return false
	var script: Script = load(DISGUISE_SCRIPT) as Script
	if script == null:
		return false
	for info: Dictionary in script.get_script_method_list():
		if str(info["name"]) in [DISGUISE_DIRECT, DISGUISE_METHOD] \
				and (_disguise_info.is_empty() or str(info["name"]) == DISGUISE_DIRECT):
			_disguise_info = {"name": info["name"], "args": info["args"],
					"required": (info["args"] as Array).size() - (info["default_args"] as Array).size(),
					"static": (int(info["flags"]) & METHOD_FLAG_STATIC) != 0}
	if _disguise_info.is_empty():
		return false
	_disguise = script if bool(_disguise_info["static"]) else (script.call("new") as Object)
	return _disguise != null


## Argumentos por nombre (se detiene en el primero desconocido: los opcionales finales sobran).
static func _disguise_args(observer_id: String, distance_m: float, room_id: String,
		uniform: String) -> Array:
	var ctx: Dictionary = {"npc_id": observer_id, "observer_id": observer_id, "observer": observer_id,
			"distance": distance_m, "distance_m": distance_m, "room_id": room_id, "room": room_id,
			"location": room_id, "hour": GameClock.get_hour(), "band": GameClock.get_current_band(),
			"day": GameClock.get_day(), "uniform": uniform, "uniform_id": uniform, "disguise": uniform,
			"floor": PlayerState.get_floor()}
	var npc: NPCRuntime = NPCDirector.get_npc(observer_id)
	ctx["npc"] = npc
	ctx["knows_player"] = NPCDirector.knows_player(observer_id) if npc != null else false
	ctx["context"] = ctx.duplicate()
	var args: Array = []
	for arg: Dictionary in _disguise_info.get("args", []):
		if not ctx.has(str(arg["name"])):
			break
		args.append(ctx[str(arg["name"])])
	return args


static func _read_disguise_result(result: Variant, out: Dictionary) -> Dictionary:
	if result is float or result is int:
		out["factor"] = maxf(float(result), 0.0)
		out["suspicious"] = float(result) > 1.0
	elif result is Dictionary:
		var d: Dictionary = result
		for key: String in DISGUISE_FACTOR_KEYS:
			if d.has(key) and (d[key] is float or d[key] is int):
				out["factor"] = maxf(float(d[key]), 0.0)
				break
		for key: String in DISGUISE_SUSPICIOUS_KEYS:
			out["suspicious"] = bool(out["suspicious"]) or bool(d.get(key, false))
	return out


# ─── Oído ─────────────────────────────────────────────────────

## Ruido en `origin` de `radius_m` metros emitido en `room_id`. {} si no lo oye o no le importa.
func hear(origin: Vector2, radius_m: float, source: String, room_id: String, noteworthy: bool) -> Dictionary:
	if npc_id.is_empty() or not _active:
		return {}
	var radius: float = effective_noise_radius(radius_m, room_id)
	if archetype == ARCH_OBLIVIOUS:
		radius *= float(_tun["oido_oblivious"])
	var d_m: float = global_position.distance_to(origin) / _cell
	if d_m > radius:
		return {}
	var anomalous: bool = radius_m >= float(_tun["radio_ruido_anomalo"])
	if not anomalous and not (noteworthy and source == PLAYER_SOURCE):
		return {}
	_attention = origin
	_attention_left = float(_tun["segundos_atencion"])
	var investigate: bool = float(_perception_eff) >= float(_tun["umbral_investigar_ruido"]) \
			and not sees_point(origin)
	return {"origin": origin, "investigate": investigate, "distance": d_m}


# ─── Dibujo del cono ──────────────────────────────────────────

func _update_cone(delta: float, player: Node2D, exposure: Dictionary) -> void:
	var target: float = _cone_target_alpha(player, exposure)
	var previous: float = _cone_alpha
	_cone_alpha = move_toward(_cone_alpha, target, delta * float(_tun["velocidad_fundido_cono"]))
	_cone_color = _state_color()
	if _cone_alpha <= 0.0:
		if previous > 0.0:
			queue_redraw()
		return
	_cone_timer -= delta
	if _cone_timer <= 0.0 or _cone.is_empty():
		_cone_timer = float(_tun["intervalo_cono"])
		_rebuild_cone()
	queue_redraw()


func _cone_target_alpha(player: Node2D, exposure: Dictionary) -> float:
	if _debug_cones:
		return float(_tun["alfa_cono_depuracion"])
	if not _active or cone_mode == CONE_OFF or player == null:
		return 0.0
	var near: bool = global_position.distance_to(player.global_position) \
			<= float(_tun["radio_conos_visibles"]) * _cell
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
	var rays: int = maxi(2, Database.get_balance_int("percepcion.rayos_cono"))
	var depth: int = Database.get_balance_int("percepcion.refinado_cono")
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
	var jump: float = Database.get_balance_float("percepcion.salto_refinado_cono") * _cell
	if depth <= 0 or absf(p0.length() - p1.length()) < jump:
		return
	var mid: float = (a0 + a1) * 0.5
	var pm: Vector2 = _cast(mid)
	_refine(pts, a0, p0, mid, pm, depth - 1)
	pts.append(pm)
	_refine(pts, mid, pm, a1, p1, depth - 1)


## Abanico de triángulos con degradado radial en UNA llamada (índices explícitos: sin
## triangulación, robusto junto a los muros); el borde exterior solo cuando importa (sigilo,
## alerta o depuración): en reposo el cono es una luz tenue sin líneas.
func _draw() -> void:
	if _cone_alpha <= 0.0 or _cone.size() < 3:
		return
	var apex: Color = Color(_cone_color, _cone_alpha)
	var rim: Color = Color(_cone_color, _cone_alpha * float(_tun["desvanecido_borde_cono"]))
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(_cone.size())
	colors.fill(rim)
	colors[0] = apex
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, _cone.size() - 1):
		indices.append_array([0, i, i + 1])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, _cone, colors)
	if _cone_alpha <= float(_tun["alfa_cono"]):
		return
	var edge: Color = Color(_cone_color, minf(1.0, _cone_alpha * float(_tun["factor_borde_cono"])))
	draw_polyline(_cone.slice(1), edge, RIM_WIDTH, true)
