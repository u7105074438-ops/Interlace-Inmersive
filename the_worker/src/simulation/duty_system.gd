# duty_system.gd — Minijuegos de los deberes (§10): volumen, cuota, entrega, ronda y presentación; A.S.S.I.S.T., delegación y consecuencias.
# PROPIETARIO DE: las sesiones de minijuego de los deberes de hoy del jugador (unidades, minutos pagados, contenido, ronda), el registro de usos de A.S.S.I.S.T., el historial de delegaciones, el registro de consecuencias ejecutadas y su RNG. El estado oficial de cada deber (plazos, avisos, fallos consecutivos) es de PlayerState.
# ESCUCHA: duty_assigned, duty_completed, duty_failed, day_advanced, occupation_changed, room_entered, crime_committed, assist_used, run_loaded, game_over.
class_name DutySystem
extends Node

## Manual §10 (completa), §15.6, §15.7, §32.2, PASO 22; BUILD_NOTES §2 (manos), §12-§14.
## game_root.gd añade este nodo; la UI (MAIL, ASSIST, PORTAL, HUD) lo encuentra en el grupo
## "duty_system" y maneja los minijuegos con start_duty / submit_unit / submit_units /
## use_assist / delegate / submit_with_material; las rondas avanzan solas con room_entered.
## DECISIONES:
##  · Sesiones: solo los deberes de HOY del jugador (PlayerState.get_todays_duties); un id ajeno
##    devuelve "unknown_duty". Al cambiar de puesto o de jornada se descartan las sesiones que ya
##    no están en la lista; una sesión nueva adopta el progreso y el estado que guarda PlayerState.
##  · Tiempo (§10.1, §10.6): cada unidad honesta avanza el reloj con GameClock.advance_minutes por
##    su parte de time_cost_minutes (acumulado redondeado: 8 correos → exactamente 45 min). Los
##    minutos «pagados» siguen a las unidades hechas: si un robo de producto descuenta unidades de
##    la cuota, rehacerlas vuelve a costar su parte. Tiempo honesto total = time_cost_minutes ×
##    (honest_viable ? 1 : deberes.factor_tiempo_honesto_no_viable), y solo los deberes
##    honest_viable se dividen por el margen de dificultad (margen_deberes, §15.7): un deber no
##    viable nunca cabe en la jornada en ningún preset (la dureza estructural no es configurable).
##    Las cifras de §10.6 son las del preset estándar. A.S.S.I.S.T. cobra
##    assist_time_cost_minutes × fracción pendiente. Las rondas no avanzan el reloj: se recorren.
##  · Viabilidad honesta (§10.3, deberes.viabilidad_por_escalon): escalones 1-2 viable; 3-4 llena la
##    jornada; 5-6 los deberes honest_viable=false cuestan ×5 (≥ 700 min > 660 min de oficina), así
##    que solo salen con material robado, IA o delegación; 7-8 imposible: submit_unit devuelve
##    "not_viable" y el deber exige delegación forzada, material o A.S.S.I.S.T.
##  · Plazos, aviso una hora antes (duty_deadline_warned) y escalera de fallos (1 aviso, 3
##    descenso, 5 expulsión; fail_penalty del deber como suelo): los emite PlayerState (único emisor
##    de duty_failed con su consecuencia). Este nodo EJECUTA la consecuencia al oír duty_failed:
##    warning → cuaderno; demotion → Company.demote_player; expulsion → game_over
##    ("duty_failure_expulsion", o "failed_at_r0" en R0) con Tracking.evaluate_ending_for_cause.
##  · A.S.S.I.S.T. (§10.4): lotería exacta 60/25/15 (deberes.assist_prob_*) para todos los deberes;
##    assist_high_failure_risk solo se expone a la UI (aviso). Todo uso emite assist_used y este
##    nodo registra CADA assist_used del juego (get_assist_log, consultable por IT). Fallo
##    evidente: un personaje con Perspicacia > 60 en la sala del jugador lo detecta → reputación y
##    anotación en el expediente (registro stamped_document en BeliefNet).
##  · Delegación (§10.5): desde el escalón 4 y solo en subordinados (is_subordinate: escalón
##    inferior y mismo departamento o sala de trabajo; desde el escalón de delegación forzada,
##    cualquiera de escalón inferior). Consume el tiempo del subordinado (override_routine a su
##    puesto); cada delegación suma un agravio "overworked" de gravedad fija
##    (deberes.delegacion_agravio_por_uso): el agravio acumulado es proporcional a la frecuencia.
##    Calidad = competencia (media de deberes.delegacion_rasgos_competencia); fallo con
##    probabilidad delegacion_prob_fallo_max × (1 − competencia), o delegacion_prob_fallo_burnout
##    si es burnout; el fallo cuenta como incumplimiento del jugador.
##  · Rondas (§10.2): paradas de duties.json; random_subset (recados del becario, coste
##    «variable») sortea cada jornada las paradas y su orden. Rondas de cierre (is_closing, steps
##    be_last_out / lock_up / shut_down_machinery, §10.6 «obliga a ser el último»): sus paradas solo
##    cuentan desde tiempo.hora_fin_jornada, cuando el edificio se vacía; al recorrerlas se cumplen
##    los tres pasos. is_on_round() es la coartada.
##  · Persistencia: save_state/load_state completos; SaveSystem solo guarda autoloads, así que
##    game_root debe incluir este nodo (petición abierta). Sin ello, al cargar se reconstruyen las
##    sesiones de hoy desde PlayerState (run_loaded); el registro de A.S.S.I.S.T. y las delegaciones
##    se pierden.

const TYPE_VOLUME := "volume"
const TYPE_QUOTA := "quota"
const TYPE_DELIVERY := "delivery"
const TYPE_ROUND := "round"
const TYPE_PRESENTATION := "presentation"
const METHOD_HONEST := "honest"
const METHOD_ASSIST := "assist"
const METHOD_DELEGATED := "delegated"
const METHOD_STOLEN := "stolen_material"
const STATUS_PENDING := "pending"
const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
const ASSIST_ACCEPTABLE := "acceptable"
const ASSIST_EXCELLENT := "excellent"
const ASSIST_FAILURE := "evident_failure"
const ASSIST_RESULT_KEYS: Dictionary = {
	ASSIST_ACCEPTABLE: "ASSIST_RESULT_ACCEPTABLE", ASSIST_EXCELLENT: "ASSIST_RESULT_EXCELLENT",
	ASSIST_FAILURE: "ASSIST_RESULT_EVIDENT_FAILURE",
}
const CONSEQ_NONE := "none"
const CONSEQ_WARNING := "warning"
const CONSEQ_DEMOTION := "demotion"
const CONSEQ_EXPULSION := "expulsion"
const ERR_UNKNOWN_DUTY := "unknown_duty"
const ERR_ALREADY_RESOLVED := "already_resolved"
const ERR_NOT_AUTOMATABLE := "not_automatable"
const ERR_NOT_DELEGATABLE := "not_delegatable"
const ERR_TIER_TOO_LOW := "tier_too_low"
const ERR_NOT_VIABLE := "not_viable"
const ERR_NO_MATERIAL := "no_material"
const ERR_NOT_DELIVERY := "not_delivery"
const ERR_WRONG_INTERFACE := "wrong_interface"
const ERR_INVALID_SUBORDINATE := "invalid_subordinate"
const ERROR_KEY_FORMAT := "DUTY_ERR_%s"
const GROUP := "duty_system"
const PLAYER_ID := "player"
const CAUSE_EXPULSION := "duty_failure_expulsion"
const CAUSE_FAILED_AT_R0 := "failed_at_r0"
const DEMOTION_REASON := "duty_failures"
const GRIEVANCE_OVERWORKED := "overworked"
const RECORD_FILE_NOTE := "stamped_document"
const REASON_ASSIST_DETECTED := "assist_evident_failure"
const REASON_PRESENTATION := "duty_presentation"
const MERIT_SOURCE_ASSIST := "assist_excellent"
const TRAIT_PERCEPTION := "perception"
const BURNOUT_ARCHETYPE := "burnout"
const CRIME_THEFT_PRODUCT := "theft_product"
const DETAIL_QUANTITY := "quantity"
const ANSWER_KEYS: Array[String] = ["correct_reply", "correct_answer"]
const KIND_KEY := "kind"
const KEY_HAS_SUBORDINATES := "has_subordinates"
const KEY_DEPARTMENT := "department"
const KEY_RANDOM_SUBSET := "random_subset"
const KEY_IS_CLOSING := "is_closing"
const PS_STATUS := "status"
const PS_PROGRESS := "progress"
const PS_QUALITY := "quality"
const PS_METHOD := "method"
const PS_DEADLINE := "deadline_hour"
const NOTE_CATEGORY := "duties"
const NOTE_BY_CONSEQUENCE: Dictionary = {
	CONSEQ_WARNING: "NOTE_DUTY_WARNING", CONSEQ_DEMOTION: "NOTE_DUTY_DEMOTION",
	CONSEQ_EXPULSION: "NOTE_DUTY_EXPULSION",
}
const NOTE_ASSIST_DETECTED := "NOTE_ASSIST_DETECTED"
const NOTE_DELEGATION_FAILED := "NOTE_DELEGATION_FAILED"
const RNG_SALT := "duty_system"
const MINUTES_PER_HOUR := 60
const DIFFICULTY_MARGIN := "margen_deberes"

const B_ASSIST_P_OK := "deberes.assist_prob_aceptable"
const B_ASSIST_P_EXCELLENT := "deberes.assist_prob_excelente"
const B_ASSIST_P_FAILURE := "deberes.assist_prob_desastre"
const B_ASSIST_Q_OK := "deberes.assist_calidad_aceptable"
const B_ASSIST_Q_EXCELLENT := "deberes.assist_calidad_excelente"
const B_ASSIST_Q_FAILURE := "deberes.assist_calidad_desastre"
const B_ASSIST_MERIT := "deberes.assist_merito_excelente"
const B_ASSIST_PERCEPTION := "deberes.assist_umbral_deteccion_perspicacia"
const B_ASSIST_REPUTATION := "deberes.assist_penalizacion_reputacion_detectado"
const B_ASSIST_FILE_WEIGHT := "deberes.assist_peso_anotacion_expediente"
const B_DELEGATION_TIER := "deberes.escalon_delegacion"
const B_FORCED_DELEGATION_TIER := "deberes.escalon_delegacion_forzada"
const B_HONEST_IMPOSSIBLE_TIER := "deberes.escalon_honesto_imposible"
const B_NOT_VIABLE_FACTOR := "deberes.factor_tiempo_honesto_no_viable"
const B_HONEST_QUALITY := "deberes.calidad_honesta"
const B_DELEGATION_WINDOW := "deberes.delegacion_ventana_jornadas"
const B_DELEGATION_GRIEVANCE := "deberes.delegacion_agravio_por_uso"
const B_DELEGATION_BURNOUT := "deberes.delegacion_prob_fallo_burnout"
const B_DELEGATION_MAX_FAIL := "deberes.delegacion_prob_fallo_max"
const B_DELEGATION_TRAITS := "deberes.delegacion_rasgos_competencia"
const B_MATERIAL_QUALITY := "deberes.calidad_material_robado"
const B_MATERIAL_MINUTES := "deberes.minutos_entrega_con_material"
const B_MATERIAL_KINDS := "deberes.tipos_material_entrega"
const B_PRESENTATION_FACTOR := "deberes.presentacion_reputacion_por_calidad"
const B_PRESENTATION_NEUTRAL := "deberes.presentacion_calidad_neutra"
const B_CONTENT_BY_SUBTYPE := "deberes.contenido_por_subtipo"
const B_CONTENT_BY_TYPE := "deberes.contenido_por_tipo"
const B_VIABILITY := "deberes.viabilidad_por_escalon"
const B_DAY_START := "tiempo.hora_inicio_jornada"
const B_DAY_END := "tiempo.hora_fin_jornada"

## duty_id → sesión (ver _make_session).
var _sessions: Dictionary[String, Dictionary] = {}
## [{day, hour, task_type, result}] — rastro digital de A.S.S.I.S.T. (§10.4).
var _assist_log: Array[Dictionary] = []
## [{npc_id, day}] — frecuencia de delegación por subordinado (§10.5).
var _delegations: Array[Dictionary] = []
## [{duty_id, consequence, day}] — consecuencias de incumplimiento ejecutadas.
var _consequence_log: Array[Dictionary] = []
var _game_over_sent: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Caché de definiciones de deber (occupations.json); no se guarda.
var _duty_index: Dictionary = {}
var _witness_provider: Callable = Callable()


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.duty_assigned.connect(_on_duty_assigned)
	EventBus.duty_completed.connect(_on_duty_completed)
	EventBus.duty_failed.connect(_on_duty_failed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.crime_committed.connect(_on_crime_committed)
	EventBus.assist_used.connect(_on_assist_used)
	EventBus.run_loaded.connect(_on_run_loaded)
	EventBus.game_over.connect(_on_game_over)
	reset_for_new_run()


func reset_for_new_run() -> void:
	_sessions.clear()
	_assist_log.clear()
	_delegations.clear()
	_consequence_log.clear()
	_game_over_sent = false
	_rng.seed = hash("%d:%s" % [GameClock.get_run_seed(), RNG_SALT])
	_sync_todays_duties()


## Función sin argumentos que devuelve los personajes presentes (Array de NPCRuntime) para la
## detección del fallo evidente. Sin función (Callable()): NPCDirector.get_npcs_in_room(sala del
## jugador).
func set_witness_provider(provider: Callable) -> void:
	_witness_provider = provider


# ─── Sesiones ─────────────────────────────────────────────────

## Crea (o conserva) la sesión de hoy de un deber de la lista de hoy del jugador.
## deadline_hour < 0 = el de PlayerState.
func register_duty(duty_id: String, deadline_hour: int = -1) -> bool:
	var duty: Dictionary = PlayerState.get_duty(duty_id)
	if duty.is_empty():
		return false
	var existing: Dictionary = _sessions.get(duty_id, {})
	if not existing.is_empty() and int(existing["day"]) == GameClock.get_day():
		if deadline_hour >= 0:
			existing["deadline_hour"] = deadline_hour
		return true
	var deadline: int = deadline_hour if deadline_hour >= 0 else int(duty.get(PS_DEADLINE, -1))
	var session: Dictionary = _make_session(duty_id, deadline)
	if session.is_empty():
		return false
	_adopt_player_status(session, duty)
	_sessions[duty_id] = session
	return true


func get_session(duty_id: String) -> Dictionary:
	return (_sessions.get(duty_id, {}) as Dictionary).duplicate(true)


func get_sessions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for session: Dictionary in _sessions.values():
		out.append(session.duplicate(true))
	return out


## Abre el minijuego. Devuelve {ok, error, error_key, duty_id, type, subtype, interface, amount,
## done, progress, honest_minutes, assist_available, assist_minutes, assist_high_risk, delegatable,
## waypoints, steps, steps_done, closing, closing_open, content}.
func start_duty(duty_id: String) -> Dictionary:
	if not register_duty(duty_id):
		return _error(duty_id, ERR_UNKNOWN_DUTY)
	var s: Dictionary = _sessions[duty_id]
	if _is_resolved(s):
		return _error(duty_id, ERR_ALREADY_RESOLVED)
	if s["status"] == STATUS_PENDING:
		s["status"] = STATUS_ACTIVE
	var info: Dictionary = _result(s)
	info.merge({
		"subtype": s["subtype"], "interface": s["interface"], "amount": s["amount"],
		"honest_minutes": get_honest_minutes(duty_id), "assist_available": _assist_available(s),
		"assist_minutes": s["assist_cost"], "assist_high_risk": s["high_risk"],
		"delegatable": _is_delegatable(s), "waypoints": (s["waypoints"] as Array).duplicate(true),
		"steps": s["steps"], "closing_open": not bool(s["closing"]) or is_closing_open(),
		"content": get_unit_content(duty_id),
	}, true)
	return info


## Contenido de la unidad actual: un correo (email_templates), una llamada (call_scripts), un
## fragmento de informe (report_fragments) o la siguiente parada de la ronda. {} si no aplica.
func get_unit_content(duty_id: String) -> Dictionary:
	var s: Dictionary = _sessions.get(duty_id, {})
	if s.is_empty():
		return {}
	var waypoints: Array = s["waypoints"]
	if not waypoints.is_empty():
		var index: int = int(s["done"])
		return (waypoints[index] as Dictionary).duplicate() if index < waypoints.size() else {}
	var items: Array = _content_list(s)
	if items.is_empty():
		return {}
	var item: Dictionary = (items[(int(s["content_offset"]) + int(s["done"])) % items.size()]
			as Dictionary).duplicate(true)
	item["unit_index"] = int(s["done"])
	return item


## Una unidad honesta (un correo, una llamada, una pieza...). `answer` = índice de respuesta cuando
## el contenido la tiene (correct_reply / correct_answer); las respuestas erróneas bajan la calidad.
func submit_unit(duty_id: String, answer: int = -1) -> Dictionary:
	var error: String = _honest_error(duty_id)
	if not error.is_empty():
		return _error(duty_id, error)
	var correct: int = 1 if _is_correct(get_unit_content(duty_id), answer) else 0
	return _advance(_sessions[duty_id], 1, correct)


## Varias unidades honestas sin respuesta (interfaces de contador: fotocopias, piezas, ventas).
func submit_units(duty_id: String, count: int) -> Dictionary:
	var error: String = _honest_error(duty_id)
	if not error.is_empty():
		return _error(duty_id, error)
	var units: int = maxi(count, 0)
	return _advance(_sessions[duty_id], units, units)


# ─── A.S.S.I.S.T. (§10.4) ─────────────────────────────────────

func use_assist(duty_id: String) -> Dictionary:
	var error: String = _assist_error(duty_id)
	if not error.is_empty():
		return _error(duty_id, error)
	return apply_assist_outcome(duty_id, roll_assist())


## Lotería con el RNG de este nodo: aceptable 60 %, excelente 25 %, fallo evidente 15 %.
func roll_assist() -> String:
	return assist_outcome_for_roll(_rng.randf())


## Lotería §10.4 para una tirada uniforme en [0, 1): pesos deberes.assist_prob_* (60/25/15),
## iguales para todos los deberes. Pura: la comparte IdeaPresentation (preparación asistida).
static func assist_outcome_for_roll(roll: float) -> String:
	var w_ok: float = Database.get_balance_float(B_ASSIST_P_OK)
	var w_excellent: float = Database.get_balance_float(B_ASSIST_P_EXCELLENT)
	var w_failure: float = Database.get_balance_float(B_ASSIST_P_FAILURE)
	var scaled: float = roll * (w_ok + w_excellent + w_failure)
	if scaled < w_failure:
		return ASSIST_FAILURE
	if scaled < w_failure + w_excellent:
		return ASSIST_EXCELLENT
	return ASSIST_ACCEPTABLE


## Primer personaje vivo con Perspicacia > deberes.assist_umbral_deteccion_perspicacia (o null).
static func perceptive_witness(candidates: Array[NPCRuntime]) -> NPCRuntime:
	var threshold: int = Database.get_balance_int(B_ASSIST_PERCEPTION)
	for npc: NPCRuntime in candidates:
		if npc != null and npc.alive and npc.get_trait(TRAIT_PERCEPTION) > threshold:
			return npc
	return null


## Manos: un fallo evidente que `witness` detecta (null = nadie lo nota) cuesta reputación, deja
## una anotación en el expediente (registro stamped_document) y una entrada de cuaderno.
## Devuelve {detected_by, reputation_delta, annotated}.
static func expose_evident_failure(witness: NPCRuntime, room_id: String) -> Dictionary:
	if witness == null:
		return {"detected_by": "", "reputation_delta": 0.0, "annotated": false}
	var delta: float = Database.get_balance_float(B_ASSIST_REPUTATION)
	PlayerState.modify_reputation(delta, REASON_ASSIST_DETECTED)
	BeliefNet.create_record(RECORD_FILE_NOTE, PLAYER_ID,
			Database.get_balance_float(B_ASSIST_FILE_WEIGHT), room_id)
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_ASSIST_DETECTED, [witness.name])
	return {"detected_by": witness.id, "reputation_delta": delta, "annotated": true}


## Aplica un resultado de la lotería (use_assist lo sortea). Devuelve {ok, duty_id, outcome,
## text_key, minutes, quality, merit, detected_by, reputation_delta, annotated, ...}.
func apply_assist_outcome(duty_id: String, outcome: String) -> Dictionary:
	var error: String = _assist_error(duty_id)
	if not error.is_empty():
		return _error(duty_id, error)
	var s: Dictionary = _sessions[duty_id]
	var remaining: float = 1.0 - float(s["done"]) / float(maxi(int(s["amount"]), 1))
	var minutes: int = roundi(float(s["assist_cost"]) * remaining)
	var result: Dictionary = {"outcome": outcome, "text_key": ASSIST_RESULT_KEYS.get(outcome, ""),
			"minutes": minutes, "merit": 0, "detected_by": "", "reputation_delta": 0.0,
			"annotated": false, "quality": _assist_quality(outcome)}
	_consume_minutes(s, minutes)
	if outcome == ASSIST_EXCELLENT:
		result["merit"] = Database.get_balance_int(B_ASSIST_MERIT)
		Company.register_merit(MERIT_SOURCE_ASSIST, int(result["merit"]))
	elif outcome == ASSIST_FAILURE:
		result.merge(expose_evident_failure(perceptive_witness(_witnesses()),
				PlayerState.get_room()), true)
	EventBus.assist_used.emit(str(s["subtype"]), outcome)
	_complete(s, METHOD_ASSIST, float(result["quality"]))
	result.merge(_result(s), false)
	return result


## Rastro digital acumulado: [{day, hour, task_type, result}] (todo assist_used del juego).
func get_assist_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _assist_log:
		out.append(entry.duplicate())
	return out


## Usos de A.S.S.I.S.T. en las últimas `days` jornadas (−1 = toda la partida).
func get_assist_count(days: int = -1) -> int:
	if days < 0:
		return _assist_log.size()
	var count: int = 0
	for entry: Dictionary in _assist_log:
		if GameClock.get_day() - int(entry["day"]) < days:
			count += 1
	return count


# ─── Delegación (§10.5) ───────────────────────────────────────

## "" si el jugador puede delegar este deber; si no, el código de error.
func can_delegate(duty_id: String) -> String:
	if not register_duty(duty_id):
		return ERR_UNKNOWN_DUTY
	var s: Dictionary = _sessions[duty_id]
	if _is_resolved(s):
		return ERR_ALREADY_RESOLVED
	if not _is_delegatable(s):
		return ERR_NOT_DELEGATABLE
	if PlayerState.get_tier() < Database.get_balance_int(B_DELEGATION_TIER):
		return ERR_TIER_TOO_LOW
	return ""


## §10.5: personaje en plantilla de escalón inferior al del jugador (cuyo puesto tiene
## subordinados) y de su mismo departamento o sala de trabajo; desde
## deberes.escalon_delegacion_forzada, cualquiera de escalón inferior (toda la casa está debajo).
func is_subordinate(npc: NPCRuntime) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if npc == null or occupation == null or NPCDirector.get_npc(npc.id) != npc:
		return false
	if not NPCDirector.is_active(npc.id) or npc.tier >= occupation.tier:
		return false
	if not bool(occupation.extra.get(KEY_HAS_SUBORDINATES, false)):
		return false
	if occupation.tier >= Database.get_balance_int(B_FORCED_DELEGATION_TIER):
		return true
	return npc.department == str(occupation.extra.get(KEY_DEPARTMENT, "")) \
			or npc.home_room == occupation.office_room


## Subordinados actuales del jugador (UI de delegación).
func get_subordinates() -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if is_subordinate(npc):
			out.append(npc)
	return out


func delegate(duty_id: String, subordinate_id: String) -> Dictionary:
	return delegate_to(duty_id, NPCDirector.get_npc(subordinate_id))


## Delegación con el personaje ya resuelto (debe ser un subordinado de NPCDirector). Devuelve {ok,
## duty_id, subordinate, failed, quality, grievance_severity, failure_probability, ...}.
func delegate_to(duty_id: String, subordinate: NPCRuntime) -> Dictionary:
	var error: String = can_delegate(duty_id)
	if not error.is_empty():
		return _error(duty_id, error)
	if not is_subordinate(subordinate):
		return _error(duty_id, ERR_INVALID_SUBORDINATE)
	var s: Dictionary = _sessions[duty_id]
	var severity: int = record_delegation(subordinate.id)
	NPCDirector.add_grievance(subordinate.id, GRIEVANCE_OVERWORKED, severity)
	NPCDirector.override_routine(subordinate.id, GameClock.get_current_band(),
			subordinate.home_room)
	var p_fail: float = delegation_failure_probability(subordinate)
	var failed: bool = _rng.randf() < p_fail
	var quality: float = 0.0 if failed else subordinate_competence(subordinate)
	if failed:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_DELEGATION_FAILED,
				[subordinate.name])
		_fail_session(s)
	else:
		_complete(s, METHOD_DELEGATED, quality)
	var result: Dictionary = _result(s)
	result.merge({"subordinate": subordinate.id, "failed": failed, "quality": quality,
			"grievance_severity": severity, "failure_probability": p_fail}, true)
	return result


## Competencia 0–1: media de los rasgos deberes.delegacion_rasgos_competencia.
func subordinate_competence(npc: NPCRuntime) -> float:
	var traits: Variant = Database.get_balance(B_DELEGATION_TRAITS)
	if not (traits is Array) or (traits as Array).is_empty():
		return 0.0
	var total: float = 0.0
	for trait_name: Variant in traits:
		total += float(npc.get_trait(str(trait_name)))
	return clampf(total / float((traits as Array).size()) / float(Validate.TRAIT_MAX), 0.0, 1.0)


## Delegar en un burnout falla con probabilidad alta; si no, ∝ a la incompetencia.
func delegation_failure_probability(npc: NPCRuntime) -> float:
	if npc.archetype == BURNOUT_ARCHETYPE:
		return Database.get_balance_float(B_DELEGATION_BURNOUT)
	return Database.get_balance_float(B_DELEGATION_MAX_FAIL) * (1.0 - subordinate_competence(npc))


## Registra una delegación en `npc_id` y devuelve la gravedad del agravio que suma: fija por uso
## (deberes.delegacion_agravio_por_uso), así el agravio acumulado es proporcional a la frecuencia.
func record_delegation(npc_id: String) -> int:
	_delegations.append({"npc_id": npc_id, "day": GameClock.get_day()})
	return Database.get_balance_int(B_DELEGATION_GRIEVANCE)


## Delegaciones en `npc_id` dentro de deberes.delegacion_ventana_jornadas (frecuencia reciente).
func get_delegation_count(npc_id: String) -> int:
	var today: int = GameClock.get_day()
	var window: int = Database.get_balance_int(B_DELEGATION_WINDOW)
	var recent: int = 0
	for entry: Dictionary in _delegations:
		if entry["npc_id"] == npc_id and today - int(entry["day"]) < window:
			recent += 1
	return recent


# ─── Material robado (§10.2 Entrega) ──────────────────────────

## `source_id`: una idea en poder del jugador (IdeaPool) o un documento del inventario cuyo kind
## esté en deberes.tipos_material_entrega. La idea se gasta; el documento se entrega.
func submit_with_material(duty_id: String, source_id: String) -> Dictionary:
	if not register_duty(duty_id):
		return _error(duty_id, ERR_UNKNOWN_DUTY)
	var s: Dictionary = _sessions[duty_id]
	if _is_resolved(s):
		return _error(duty_id, ERR_ALREADY_RESOLVED)
	if s["type"] != TYPE_DELIVERY:
		return _error(duty_id, ERR_NOT_DELIVERY)
	var quality: float = _take_material(source_id)
	if quality < 0.0:
		return _error(duty_id, ERR_NO_MATERIAL)
	_consume_minutes(s, Database.get_balance_int(B_MATERIAL_MINUTES))
	_complete(s, METHOD_STOLEN, quality)
	var result: Dictionary = _result(s)
	result["quality"] = quality
	return result


# ─── Rondas (§10.2: coartada) ─────────────────────────────────

## true mientras el jugador recorre una ronda empezada y no terminada (justifica su presencia).
func is_on_round() -> bool:
	for s: Dictionary in _sessions.values():
		if s["type"] == TYPE_ROUND and s["status"] == STATUS_ACTIVE:
			return true
	return false


## true si la sala forma parte de una ronda en curso.
func is_room_on_round(room_id: String) -> bool:
	for s: Dictionary in _sessions.values():
		if s["type"] != TYPE_ROUND or s["status"] != STATUS_ACTIVE:
			continue
		for waypoint: Dictionary in s["waypoints"]:
			if _waypoint_matches(waypoint, room_id):
				return true
	return false


## Las rondas de cierre solo cuentan desde tiempo.hora_fin_jornada (hay que ser el último).
func is_closing_open() -> bool:
	return GameClock.get_hour() >= Database.get_balance_int(B_DAY_END)


## El jugador entra en una sala: avanza las rondas cuya siguiente parada es esa sala.
func visit_room(room_id: String) -> void:
	for s: Dictionary in _sessions.values():
		if s["type"] != TYPE_ROUND or _is_resolved(s):
			continue
		if bool(s["closing"]) and not is_closing_open():
			continue
		var waypoints: Array = s["waypoints"]
		var index: int = int(s["done"])
		if index >= waypoints.size() or not _waypoint_matches(waypoints[index], room_id):
			continue
		s["status"] = STATUS_ACTIVE
		s["done"] = index + 1
		_publish_progress(s)
		if int(s["done"]) >= waypoints.size():
			s["steps_done"] = (s["steps"] as Array).duplicate()
			_complete(s, METHOD_HONEST, Database.get_balance_float(B_HONEST_QUALITY))


# ─── Consecuencias del incumplimiento ─────────────────────────

## Ejecuta la consecuencia que PlayerState decidió (duty_failed). Devuelve lo ejecutado.
func execute_consequence(duty_id: String, consequence: String) -> String:
	var session: Dictionary = _sessions.get(duty_id, {})
	if not session.is_empty() and not _is_resolved(session):
		session["status"] = STATUS_FAILED
	if not NOTE_BY_CONSEQUENCE.has(consequence):
		return CONSEQ_NONE
	_consequence_log.append({"duty_id": duty_id, "consequence": consequence,
			"day": GameClock.get_day()})
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_BY_CONSEQUENCE[consequence],
			[_duty_name_key(duty_id)])
	if consequence == CONSEQ_DEMOTION:
		Company.demote_player(DEMOTION_REASON)
	elif consequence == CONSEQ_EXPULSION and not _game_over_sent:
		_game_over_sent = true
		var cause: String = CAUSE_FAILED_AT_R0 if PlayerState.get_rank() == 0 else CAUSE_EXPULSION
		EventBus.game_over.emit(cause, Tracking.evaluate_ending_for_cause(cause),
				Tracking.get_snapshot())
	return consequence


## [{duty_id, consequence, day}] de las consecuencias ejecutadas en la partida.
func get_consequence_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _consequence_log:
		out.append(entry.duplicate())
	return out


# ─── Viabilidad honesta (§10.3) ───────────────────────────────

## Minutos de reloj que cuesta el deber hecho honestamente de principio a fin (cualquier deber).
func get_honest_minutes(duty_id: String) -> int:
	var definition: Dictionary = _definition(duty_id)
	if definition.is_empty():
		return 0
	return roundi(_honest_total_minutes(definition))


## Escalones 7-8: el deber no puede hacerse en solitario (§10.3 «inviable en términos absolutos»).
func is_honest_possible(tier: int) -> bool:
	return tier < Database.get_balance_int(B_HONEST_IMPOSSIBLE_TIER)


## "viable" | "full_day" | "needs_help" | "impossible" (deberes.viabilidad_por_escalon).
func get_viability_band(tier: int) -> String:
	var table: Variant = Database.get_balance(B_VIABILITY)
	if table is Dictionary and (table as Dictionary).has(str(tier)):
		return str(table[str(tier)])
	return ""


## Informe para PORTAL/HUD: {honest_minutes, workday_minutes, available_minutes,
## viable_in_workday, viable_now, band}. Sin ids: los deberes de hoy del jugador.
func get_viability_report(duty_ids: Array[String] = []) -> Dictionary:
	var ids: Array[String] = duty_ids.duplicate()
	if ids.is_empty():
		for duty_id: String in _sessions.keys():
			ids.append(duty_id)
	var honest: int = 0
	for duty_id: String in ids:
		honest += get_honest_minutes(duty_id)
	var workday: int = (Database.get_balance_int(B_DAY_END)
			- Database.get_balance_int(B_DAY_START)) * MINUTES_PER_HOUR
	var available: int = roundi(GameClock.hours_until_closing() * MINUTES_PER_HOUR)
	return {
		"honest_minutes": honest, "workday_minutes": workday, "available_minutes": available,
		"viable_in_workday": honest <= workday, "viable_now": honest <= available,
		"band": get_viability_band(PlayerState.get_tier()),
	}


# ─── Persistencia (game_root la incluye en la partida) ────────

func save_state() -> Dictionary:
	return {
		"sessions": _sessions.duplicate(true), "assist_log": _assist_log.duplicate(true),
		"delegations": _delegations.duplicate(true),
		"consequence_log": _consequence_log.duplicate(true), "game_over_sent": _game_over_sent,
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	reset_for_new_run()
	_sessions.clear()
	for duty_id: Variant in data.get("sessions", {}):
		_sessions[str(duty_id)] = _normalize_session(data["sessions"][duty_id])
	_assist_log = _int_entries(data.get("assist_log", []), ["day", "hour"])
	_delegations = _int_entries(data.get("delegations", []), ["day"])
	_consequence_log = _int_entries(data.get("consequence_log", []), ["day"])
	_game_over_sent = bool(data.get("game_over_sent", false))
	_rng.seed = str(data.get("rng_seed", str(_rng.seed))).to_int()
	_rng.state = str(data.get("rng_state", str(_rng.state))).to_int()


# ─── Internos: definiciones y sesiones ────────────────────────

func _definition(duty_id: String) -> Dictionary:
	if _duty_index.is_empty():
		for occupation: OccupationData in Database.get_all_occupations():
			for duty: Dictionary in occupation.duties:
				var entry: Dictionary = duty.duplicate(true)
				entry["occupation_tier"] = occupation.tier
				_duty_index[str(duty.get("id", ""))] = entry
	return _duty_index.get(duty_id, {})


func _make_session(duty_id: String, deadline_hour: int) -> Dictionary:
	var d: Dictionary = _definition(duty_id)
	if d.is_empty():
		return {}
	var type_def: Dictionary = Database.get_duty_definition(str(d.get("type", "")))
	var waypoints: Array = _waypoints_for(d)
	var amount: int = waypoints.size() if not waypoints.is_empty() else int(d.get("amount", 1))
	var s: Dictionary = {
		"duty_id": duty_id, "type": str(d.get("type", "")), "subtype": str(d.get("subtype", "")),
		"interface": str(type_def.get("interface", "")), "tier": int(d["occupation_tier"]),
		"amount": maxi(amount, 1), "time_cost": int(d.get("time_cost_minutes", 0)),
		"assist_cost": int(d.get("assist_time_cost_minutes", -1)),
		"deadline_hour": deadline_hour if deadline_hour >= 0 else int(d.get("deadline_hour", 0)),
		"honest_viable": bool(d.get("honest_viable", true)),
		"high_risk": bool(d.get("assist_high_failure_risk", false)),
		"automatable": bool(type_def.get("automatable", false)),
		"delegatable": bool(type_def.get("delegatable", false)),
		"affected_by_theft": bool(type_def.get("affected_by_theft", false)),
		"waypoints": waypoints, "steps": (d.get("steps", []) as Array).duplicate(),
		"steps_done": [], "closing": bool(d.get(KEY_IS_CLOSING, false)),
		"day": GameClock.get_day(), "status": STATUS_PENDING, "done": 0, "correct": 0,
		"honest_minutes_spent": 0, "minutes_spent": 0, "method": "", "quality": 0.0,
	}
	var items: Array = _content_list(s)
	s["content_offset"] = _rng.randi_range(0, items.size() - 1) if not items.is_empty() else 0
	return s


## Una sesión nueva (carga, cambio de jornada) parte del progreso y el estado de PlayerState.
func _adopt_player_status(s: Dictionary, duty: Dictionary) -> void:
	var amount: int = int(s["amount"])
	s["done"] = clampi(roundi(float(duty.get(PS_PROGRESS, 0.0)) * amount), 0, amount)
	s["honest_minutes_spent"] = _paid_minutes(s)
	match str(duty.get(PS_STATUS, "")):
		STATUS_COMPLETED:
			s.merge({"status": STATUS_COMPLETED, "method": str(duty.get(PS_METHOD, "")),
					"quality": float(duty.get(PS_QUALITY, 0.0))}, true)
		STATUS_FAILED:
			s["status"] = STATUS_FAILED
		_:
			if int(s["done"]) > 0:
				s["status"] = STATUS_ACTIVE


## Paradas de duties.json; random_subset sortea cada jornada cuáles y en qué orden.
func _waypoints_for(definition: Dictionary) -> Array:
	var set_id: String = str(definition.get("waypoint_set", ""))
	if set_id.is_empty():
		return []
	var waypoint_set: Dictionary = Database.get_round_waypoint_set(set_id)
	var out: Array = []
	for waypoint: Variant in waypoint_set.get("waypoints", []):
		if waypoint is Dictionary:
			out.append({"room": str(waypoint.get("room", "")),
					"floor": int(waypoint.get("floor", 0))})
	var subset: int = int(waypoint_set.get(KEY_RANDOM_SUBSET, 0))
	if subset <= 0 or subset >= out.size():
		return out
	var route: Array = []
	for _i: int in subset:
		route.append(out.pop_at(_rng.randi_range(0, out.size() - 1)))
	return route


func _content_list(s: Dictionary) -> Array:
	var by_subtype: Variant = Database.get_balance(B_CONTENT_BY_SUBTYPE)
	var by_type: Variant = Database.get_balance(B_CONTENT_BY_TYPE)
	var key: String = ""
	if by_subtype is Dictionary and (by_subtype as Dictionary).has(s["subtype"]):
		key = str(by_subtype[s["subtype"]])
	elif by_type is Dictionary and (by_type as Dictionary).has(s["type"]):
		key = str(by_type[s["type"]])
	var items: Variant = Database.get_duty_content().get(key, []) if not key.is_empty() else []
	return items if items is Array else []


func _normalize_session(raw: Variant) -> Dictionary:
	var s: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	for key: String in ["tier", "amount", "time_cost", "assist_cost", "deadline_hour", "day",
			"done", "correct", "honest_minutes_spent", "minutes_spent", "content_offset"]:
		s[key] = int(s.get(key, 0))
	var waypoints: Array = []
	for waypoint: Variant in s.get("waypoints", []):
		if waypoint is Dictionary:
			waypoints.append({"room": str(waypoint.get("room", "")),
					"floor": int(waypoint.get("floor", 0))})
	s["waypoints"] = waypoints
	s["steps"] = (s.get("steps", []) as Array).duplicate() if s.get("steps") is Array else []
	s["steps_done"] = (s.get("steps_done", []) as Array).duplicate() \
			if s.get("steps_done") is Array else []
	s["closing"] = bool(s.get("closing", false))
	s["quality"] = float(s.get("quality", 0.0))
	return s


func _is_resolved(s: Dictionary) -> bool:
	return s["status"] == STATUS_COMPLETED or s["status"] == STATUS_FAILED


func _is_delegatable(s: Dictionary) -> bool:
	return bool(s["delegatable"]) \
			or int(s["tier"]) >= Database.get_balance_int(B_FORCED_DELEGATION_TIER)


func _assist_available(s: Dictionary) -> bool:
	return bool(s["automatable"]) and int(s["assist_cost"]) > 0


## Deberes de hoy del jugador: se descartan las sesiones que ya no están y se abren las nuevas.
func _sync_todays_duties() -> void:
	var today: int = GameClock.get_day()
	for duty_id: String in _sessions.keys():
		if int(_sessions[duty_id]["day"]) != today or PlayerState.get_duty(duty_id).is_empty():
			_sessions.erase(duty_id)
	for duty: Dictionary in PlayerState.get_todays_duties():
		register_duty(str(duty.get("id", "")), int(duty.get(PS_DEADLINE, -1)))


# ─── Internos: trabajo honesto y tiempo ───────────────────────

func _honest_error(duty_id: String) -> String:
	if not register_duty(duty_id):
		return ERR_UNKNOWN_DUTY
	var s: Dictionary = _sessions[duty_id]
	if _is_resolved(s):
		return ERR_ALREADY_RESOLVED
	if not (s["waypoints"] as Array).is_empty():
		return ERR_WRONG_INTERFACE
	if not is_honest_possible(int(s["tier"])):
		return ERR_NOT_VIABLE
	return ""


## Minutos de trabajo honesto del deber completo. El margen de dificultad solo alivia los deberes
## honest_viable (§15.7: la inviabilidad estructural no es configurable).
func _honest_total_minutes(definition: Dictionary) -> float:
	var minutes: float = float(definition.get("time_cost_minutes", 0))
	if not bool(definition.get("honest_viable", true)):
		return minutes * Database.get_balance_float(B_NOT_VIABLE_FACTOR)
	var margin: float = Database.get_difficulty_modifier(DIFFICULTY_MARGIN)
	return minutes / margin if margin > 0.0 else minutes


## Minutos honestos que corresponden a las unidades hechas ahora (lo ya «pagado» en reloj).
func _paid_minutes(s: Dictionary) -> int:
	return roundi(_honest_total_minutes(_definition(s["duty_id"])) * float(s["done"])
			/ float(maxi(int(s["amount"]), 1)))


## Suma `units` unidades (`correct` de ellas bien hechas), cobra su parte del tiempo honesto y
## completa el deber al llegar a la cantidad. Si el plazo vence mientras se trabaja, el deber ya
## está fallado: no publica progreso ni lo completa.
func _advance(s: Dictionary, units: int, correct: int) -> Dictionary:
	if s["status"] == STATUS_PENDING:
		s["status"] = STATUS_ACTIVE
	var amount: int = int(s["amount"])
	var added: int = mini(units, amount - int(s["done"]))
	s["done"] = int(s["done"]) + added
	s["correct"] = int(s["correct"]) + mini(correct, added)
	var target: int = _paid_minutes(s)
	var step: int = maxi(target - int(s["honest_minutes_spent"]), 0)
	s["honest_minutes_spent"] = maxi(target, int(s["honest_minutes_spent"]))
	_consume_minutes(s, step)
	if not _is_resolved(s):
		_publish_progress(s)
		if int(s["done"]) >= amount:
			_complete(s, METHOD_HONEST, _honest_quality(s))
	var result: Dictionary = _result(s)
	result["minutes"] = step
	return result


func _honest_quality(s: Dictionary) -> float:
	var base: float = Database.get_balance_float(B_HONEST_QUALITY)
	if _content_has_answers(s):
		return base * float(s["correct"]) / float(maxi(int(s["amount"]), 1))
	return base


func _content_has_answers(s: Dictionary) -> bool:
	var items: Array = _content_list(s)
	if items.is_empty() or not (items[0] is Dictionary):
		return false
	for key: String in ANSWER_KEYS:
		if (items[0] as Dictionary).has(key):
			return true
	return false


func _is_correct(content: Dictionary, answer: int) -> bool:
	for key: String in ANSWER_KEYS:
		if content.has(key):
			return answer == int(content[key])
	return true


## El trabajo tedioso consume reloj (§10.1): GameClock avanza (y emite sus horas) al trabajar.
func _consume_minutes(s: Dictionary, minutes: int) -> void:
	if minutes <= 0:
		return
	s["minutes_spent"] = int(s["minutes_spent"]) + minutes
	GameClock.advance_minutes(float(minutes))


func _publish_progress(s: Dictionary) -> void:
	PlayerState.set_duty_progress(s["duty_id"],
			float(s["done"]) / float(maxi(int(s["amount"]), 1)))


func _is_player_duty(duty_id: String) -> bool:
	return str(PlayerState.get_duty(duty_id).get(PS_STATUS, "")) == STATUS_PENDING


## Cierra la sesión y lo comunica a PlayerState (que emite duty_completed). Las presentaciones
## exponen la reputación ante el público (§10.2).
func _complete(s: Dictionary, method: String, quality: float) -> void:
	if _is_resolved(s):
		return
	s["status"] = STATUS_COMPLETED
	s["method"] = method
	s["quality"] = quality
	if s["type"] == TYPE_PRESENTATION:
		PlayerState.modify_reputation((quality - Database.get_balance_float(B_PRESENTATION_NEUTRAL))
				* Database.get_balance_float(B_PRESENTATION_FACTOR), REASON_PRESENTATION)
	PlayerState.complete_duty(s["duty_id"], quality, method)


## Incumplimiento imputable al jugador: PlayerState lo registra y emite duty_failed (cuya
## consecuencia se ejecuta en _on_duty_failed).
func _fail_session(s: Dictionary) -> void:
	if _is_player_duty(s["duty_id"]):
		PlayerState.fail_duty(s["duty_id"])
	s["status"] = STATUS_FAILED


func _result(s: Dictionary) -> Dictionary:
	return {
		"ok": true, "error": "", "error_key": "", "duty_id": s["duty_id"], "type": s["type"],
		"status": s["status"], "done": s["done"],
		"progress": float(s["done"]) / float(maxi(int(s["amount"]), 1)),
		"completed": s["status"] == STATUS_COMPLETED, "method": s["method"],
		"quality": s["quality"], "minutes_spent": s["minutes_spent"],
		"closing": s["closing"], "steps_done": (s["steps_done"] as Array).duplicate(),
	}


func _error(duty_id: String, error: String) -> Dictionary:
	return {"ok": false, "error": error, "error_key": ERROR_KEY_FORMAT % error.to_upper(),
			"duty_id": duty_id, "completed": false}


# ─── Internos: A.S.S.I.S.T., material y rondas ────────────────

func _assist_error(duty_id: String) -> String:
	if not register_duty(duty_id):
		return ERR_UNKNOWN_DUTY
	var s: Dictionary = _sessions[duty_id]
	if _is_resolved(s):
		return ERR_ALREADY_RESOLVED
	if not _assist_available(s):
		return ERR_NOT_AUTOMATABLE
	return ""


func _assist_quality(outcome: String) -> float:
	match outcome:
		ASSIST_EXCELLENT:
			return Database.get_balance_float(B_ASSIST_Q_EXCELLENT)
		ASSIST_FAILURE:
			return Database.get_balance_float(B_ASSIST_Q_FAILURE)
		_:
			return Database.get_balance_float(B_ASSIST_Q_OK)


func _witnesses() -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	if not _witness_provider.is_valid():
		out.assign(NPCDirector.get_npcs_in_room(PlayerState.get_room()))
		return out
	for candidate: Variant in _witness_provider.call():
		if candidate is NPCRuntime:
			out.append(candidate)
	return out


## Calidad del material (0–1) tras gastarlo, o −1 si el jugador no lo tiene.
func _take_material(source_id: String) -> float:
	var idea_quality: int = IdeaPool.use_as_material(source_id)
	if idea_quality >= 0:
		return float(idea_quality) / float(Idea.MAX_QUALITY)
	var item: ItemData = Database.get_item(source_id)
	var kinds: Variant = Database.get_balance(B_MATERIAL_KINDS)
	if item == null or not (kinds is Array):
		return -1.0
	if not (kinds as Array).has(item.extra.get(KIND_KEY, "")):
		return -1.0
	if not PlayerState.has_item(source_id) or not PlayerState.remove_item(source_id):
		return -1.0
	return Database.get_balance_float(B_MATERIAL_QUALITY)


## Parada {room, floor}: vale el id base o su instancia transversal "<id>@<planta>".
func _waypoint_matches(waypoint: Dictionary, room_id: String) -> bool:
	var room: String = str(waypoint.get("room", ""))
	return room_id == room \
			or room_id == DatabaseSystem.make_room_instance_id(room, int(waypoint.get("floor", 0)))


## Clave de texto del nombre del deber (el cuaderno la traduce al mostrarla: tr() de un texto que
## no es clave lo deja igual).
func _duty_name_key(duty_id: String) -> String:
	var name_key: String = str(_definition(duty_id).get("name_key", ""))
	return name_key if not name_key.is_empty() else duty_id


func _int_entries(raw: Variant, int_keys: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for entry: Variant in raw:
		if entry is Dictionary:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			for key: String in int_keys:
				copy[key] = int(copy.get(key, 0))
			out.append(copy)
	return out


# ─── Oyentes ──────────────────────────────────────────────────

func _on_duty_assigned(duty_id: String, _duty_type: String, deadline_hour: int) -> void:
	register_duty(duty_id, deadline_hour)


func _on_duty_completed(duty_id: String, quality: float, method: String) -> void:
	var s: Dictionary = _sessions.get(duty_id, {})
	if not s.is_empty() and not _is_resolved(s):
		s.merge({"status": STATUS_COMPLETED, "quality": quality, "method": method}, true)


func _on_duty_failed(duty_id: String, consequence: String) -> void:
	execute_consequence(duty_id, consequence)


## Nueva jornada (PlayerState ya falló las pendientes y montó la lista nueva).
func _on_day_advanced(_day_number: int) -> void:
	_sync_todays_duties()


## Ascenso, descenso o cambio lateral: los deberes del puesto anterior dejan de existir.
func _on_occupation_changed(_old_id: String, _new_id: String, _reason: String) -> void:
	_sync_todays_duties()


func _on_run_loaded(_day_number: int) -> void:
	_sync_todays_duties()


func _on_game_over(_cause: String, _ending_id: String, _snapshot: Dictionary) -> void:
	_game_over_sent = true


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		visit_room(room_id)


## Los robos de producto del jugador salen de su propia cuota (§10.2): las unidades robadas se
## descuentan y los minutos ya pagados bajan con ellas, así rehacerlas vuelve a costar reloj.
func _on_crime_committed(crime_type: String, _room_id: String, details: Dictionary) -> void:
	if crime_type != CRIME_THEFT_PRODUCT:
		return
	var quantity: int = maxi(int(details.get(DETAIL_QUANTITY, 1)), 0)
	for s: Dictionary in _sessions.values():
		if s["type"] == TYPE_QUOTA and bool(s["affected_by_theft"]) and not _is_resolved(s):
			s["done"] = maxi(int(s["done"]) - quantity, 0)
			s["honest_minutes_spent"] = _paid_minutes(s)
			_publish_progress(s)


func _on_assist_used(task_type: String, result_quality: String) -> void:
	_assist_log.append({"day": GameClock.get_day(), "hour": GameClock.get_hour(),
			"task_type": task_type, "result": result_quality})
