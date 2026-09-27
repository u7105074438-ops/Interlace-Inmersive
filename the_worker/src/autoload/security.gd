# security.gd — Nivel de alerta, cámaras, lectores de tarjeta, investigaciones y casos fríos.
# PROPIETARIO DE: nivel de alerta, grabaciones, registro de lectores, investigaciones (activas, frías y cerradas) con su expediente, e índice forense de cuerpos/escondites observados (§19.7).
# ESCUCHA: day_advanced, hour_passed, time_band_changed, suspicion_changed, room_entered, disguise_changed, occupation_changed, camera_recorded_player, card_reader_logged, npc_reported_player, crime_committed, body_created, body_hidden, body_discovered, npc_removed, item_hidden, item_disposed, inventory_changed, player_searched, record_destroyed, belief_decayed, belief_forgotten, audit_triggered, insider_pattern_detected, month_closed, seat_vacated, seat_filled, grievance_added, bribe_offered, bribe_result.
class_name SecuritySystem
extends Node

## PASO 27 (vigilancia), 28 (investigaciones), 29 (reglas del interrogatorio) y 30 (casos fríos).
## Las reglas puras viven en InvestigationEngine (src/simulation/investigation.gd) y en
## Interrogation (src/simulation/interrogation.gd); aquí está el estado y el cableado.
## · Día y hora propios: se actualizan con day_advanced / hour_passed (arranque: GameClock).
## · Sospecha: la última recibida por suspicion_changed (BeliefNet la calcula, §7.2).
## · Una investigación avanza en el tic diario: fase 1 → 2 al abrirse; la fase 2 reparte sus tres
##   procedimientos (testigos, grabaciones, registro de salas) entre sus 2-10 jornadas; fase 3
##   (1 jornada) forma la lista corta; fase 4 si el jugador la encabeza (la escena llama a
##   begin/finish_interrogation); fase 5 dicta veredicto (investigation_resolved).
## · Piezas: Investigation.make_evidence(); record_id único por caso. Un registro destruido
##   (record_destroyed, belief_forgotten, testigo expulsado) desaparece de los casos ACTIVOS; un
##   caso frío conserva su expediente íntegro (§12.6).
## · Datos que pertenecen a otros (cuerpos → NPCDirector, escondites → PlayerState, sala y
##   disfraz del jugador → PlayerState) se leen de su dueño cuando expone el getter; si no, se
##   usa lo observado en las señales públicas (índice forense propio).

const PLAYER := InvestigationEngine.SUBJECT_PLAYER
const CASE_ID_FORMAT := "case_%d"
const FOOTAGE_ID_FORMAT := "cam_%s_%d_%d_%d"
const ACCESS_ID_FORMAT := "card_%d"
const PIECE_ID_FORMAT := "%s_ev_%d"
const BODY_PIECE_FORMAT := "body_%s"
const ITEM_PIECE_FORMAT := "item_%s_%s"
const STASH_KEY_FORMAT := "%s|%s"
const SALT := "security"

const INCIDENT_MISSING_PERSON := "missing_person"
const INCIDENT_BODY_FOUND := "body_found"
const INCIDENT_WITNESS := "direct_witness_report"
const INCIDENT_INSIDER := "insider_pattern"
const INCIDENT_FRAUD := "fraud_at_month_close"
const INCIDENT_OBJECT_MISSING := "object_missing"
const CAUSE_ELIMINATED := "eliminated"
const CRIME_FRAUD := "fraud"
const CRIME_BODY_MOVED := "body_moved"
const CRIME_FOOTAGE_DELETED := "footage_deleted"
const DESTROY_METHOD_MONITOR := "deleted_in_monitor_room"
const FAVOUR_LIE := "lie_in_interrogation"
const FAVOUR_BURY := "bury_investigation"
const BAND_NIGHT := "night"
const TRIGGER_NEW_PIECE := "new_piece"
const TRIGGER_SILENT_WITNESS := "silent_witness"
const TRIGGER_AUDITOR := "auditor_change"
## investigation_resolved tras close_case_permanently (Auditor Jefe): el caso frío muere.
const VERDICT_CLOSED := "closed_permanently"
const INTERROGATION_NONE := "none"
const INTERROGATION_IN_PROGRESS := "in_progress"
const INTERROGATION_DONE := "done"
const ALIBI_FROM_RECORDS := "records"

const B_ALERT_MAX := "seguridad.nivel_alerta_max"
const B_ALERT_SUSPICION := "seguridad.alerta_sospecha_por_nivel"
const B_ALERT_INCIDENTS := "seguridad.alerta_incidentes_por_nivel"
const B_ALERT_RECENT_DAYS := "seguridad.alerta_dias_incidente_reciente"
const B_ROUNDS_BASE := "seguridad.rondas_base_por_hora"
const B_ROUNDS_LEVEL := "seguridad.rondas_extra_por_nivel"
const B_GUARD_PERCEPTION := "seguridad.perspicacia_vigilantes_por_nivel"
const B_REVIEW_BASE := "seguridad.prob_revision_grabaciones_base"
const B_REVIEW_LEVEL := "seguridad.prob_revision_grabaciones_por_nivel"
const B_SEARCH_THRESHOLD := "seguridad.umbral_registro_corporal"
const B_MONITOR_ROOM := "seguridad.sala_monitores"
const B_PENDING_DAYS := "seguridad.dias_acumulacion_incidentes"
const B_WITNESS_WINDOW := "seguridad.dias_ventana_testigos"
const B_DIRECT_MIN := "seguridad.certeza_testigo_directo_min"
const B_HIDDEN_CERTAINTY := "seguridad.certeza_hallazgo_escondite"
const B_BODY_CERTAINTY := "seguridad.certeza_cuerpo_hallado"
const B_INCIDENT_ROOM_CHANCE := "seguridad.prob_hallazgo_sala_incidente"
const B_MISSING_WEIGHT := "seguridad.incidente_desaparicion_peso"
const B_MISSING_SEVERITY := "seguridad.incidente_desaparicion_gravedad"
const B_ABSENCE_DAYS := "seguridad.dias_deteccion_ausencia"
const B_LEGAL_AFFECTION := "seguridad.afecto_minimo_contacto_legal"
const B_CRIME_INCIDENTS := "seguridad.incidentes_por_delito"
const B_FRAUD_ROOM := "seguridad.sala_incidente_fraude"
const B_INSIDER_ROOM := "seguridad.sala_incidente_insider"
const B_OPENING := "investigaciones.umbral_apertura"
const B_SHORTLIST := "investigaciones.umbral_lista_corta"
const B_MINOR := "investigaciones.umbral_condena_leve"
const B_MAJOR := "investigaciones.umbral_condena_grave"
const B_COLLECT_MIN := "investigaciones.dias_recogida_min"
const B_COLLECT_MAX := "investigaciones.dias_recogida_max"
const B_THRESHOLD_MOD := "investigaciones.mod_umbral_por_sospecha"
const B_REST_DAYS := "investigaciones.jornadas_respiro_minimo"
const B_AUDITOR_REVIEW := "investigaciones.prob_revision_al_cambiar_auditor"
const B_LAWYER_DAYS := "investigaciones.dias_congelacion_por_abogado"
const B_BONUS_ACCESS := "investigaciones.pesos_evidencia.bonus_oportunidad"
const B_BONUS_MOTIVE := "investigaciones.pesos_evidencia.bonus_movil"
const B_BONUS_LAST := "investigaciones.pesos_evidencia.bonus_ultimo_en_salir"
const B_DAYS_PER_WEEK := "tiempo.jornadas_por_semana"
const B_DAY_START := "tiempo.hora_inicio_jornada"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## investigations.json (solo lectura, caché de Database).
var _params: Dictionary = {}
var _today: int = 0
var _hour: int = 0
var _band: String = ""
var _alert_level: int = 0
var _suspicion: float = 0.0
var _counter: int = 0
var _incident_days: Array[int] = []
## {id, camera_id, room_id, day, hour, subject}
var _footage: Array[Dictionary] = []
## {id, reader_id, card_owner, day, hour, room_id}
var _access_log: Array[Dictionary] = []
var _cases: Dictionary = {}
var _case_order: Array[String] = []
## case_id → expediente auxiliar (ver _new_meta).
var _meta: Dictionary = {}
var _has_case_history: bool = false
var _last_case_day: int = 0
var _deferred: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
## "día" → sujeto que salió el último del edificio.
var _last_out: Dictionary = {}
## body_id → {npc_id, room_id, spot_id, hidden, discovered}
var _bodies: Dictionary = {}
## npc_id → jornada de su eliminación (ausencia aún no detectada).
var _absences: Dictionary = {}
## spot_id → {room_id, items: Array}
var _stashes: Dictionary = {}
## "spot|item" ya incautados por un registro.
var _confiscated: Array[String] = []
var _found_items: Array[Dictionary] = []
var _bought_witnesses: Array[String] = []
var _pending_bribes: Dictionary = {}
var _vacated: Dictionary = {}
var _fraud_this_month: int = 0
var _marked_until: int = 0
var _player_room: String = ""
var _player_disguise: String = ""
var _player_occupation: String = ""
var _chief_auditor: String = ""
var _emitting: bool = false


func _ready() -> void:
	_connect_world_signals()
	_connect_case_signals()


func _connect_world_signals() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.suspicion_changed.connect(_on_suspicion_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.disguise_changed.connect(_on_disguise_changed)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.camera_recorded_player.connect(_on_camera_recorded_player)
	EventBus.card_reader_logged.connect(_on_card_reader_logged)
	EventBus.body_created.connect(_on_body_created)
	EventBus.body_hidden.connect(_on_body_hidden)
	EventBus.item_hidden.connect(_on_item_hidden)
	EventBus.item_disposed.connect(_on_item_disposed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.seat_vacated.connect(_on_seat_vacated)
	EventBus.seat_filled.connect(_on_seat_filled)


func _connect_case_signals() -> void:
	EventBus.npc_reported_player.connect(_on_npc_reported_player)
	EventBus.crime_committed.connect(_on_crime_committed)
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.player_searched.connect(_on_player_searched)
	EventBus.record_destroyed.connect(_on_record_destroyed)
	EventBus.belief_decayed.connect(_on_belief_decayed)
	EventBus.belief_forgotten.connect(_on_belief_forgotten)
	EventBus.audit_triggered.connect(_on_audit_triggered)
	EventBus.insider_pattern_detected.connect(_on_insider_pattern_detected)
	EventBus.month_closed.connect(_on_month_closed)
	EventBus.grievance_added.connect(_on_grievance_added)
	EventBus.bribe_offered.connect(_on_bribe_offered)
	EventBus.bribe_result.connect(_on_bribe_result)


func reset_for_new_run() -> void:
	_clear_state()
	_rng.seed = hash(SALT) ^ GameClock.get_run_seed()
	_params = Database.get_investigation_params()
	_today = GameClock.get_day()
	_hour = GameClock.get_hour()
	_band = GameClock.get_current_band()
	_suspicion = PlayerState.get_suspicion()
	var occupation: OccupationData = PlayerState.get_occupation()
	_player_occupation = occupation.id if occupation != null else ""
	_chief_auditor = Company.get_seat_holder(_watched_occupation())


func _clear_state() -> void:
	_alert_level = 0
	_counter = 0
	_has_case_history = false
	_last_case_day = 0
	_fraud_this_month = 0
	_marked_until = 0
	_player_room = ""
	_player_disguise = ""
	_band = ""
	for container: Variant in [_incident_days, _footage, _access_log, _case_order, _deferred,
			_pending, _confiscated, _found_items, _bought_witnesses]:
		(container as Array).clear()
	for container: Variant in [_cases, _meta, _last_out, _bodies, _absences, _stashes,
			_pending_bribes, _vacated]:
		(container as Dictionary).clear()


# ─── Alerta (§7.10, PASO 27) ──────────────────────────────────

## 0 a 5.
func get_alert_level() -> int:
	return _alert_level


## nivel = ⌊sospecha / 20⌋ + ⌊incidentes recientes / 2⌋, acotado a 0-5; máximo mientras el
## jugador está marcado por un veredicto leve.
func recalculate_alert_level() -> void:
	var max_level: int = _bal_i(B_ALERT_MAX)
	var level: int = max_level
	if not is_player_marked():
		level = floori(_suspicion / _bal_f(B_ALERT_SUSPICION)) \
				+ floori(float(_recent_incident_count()) / float(_bal_i(B_ALERT_INCIDENTS)))
	level = clampi(level, 0, max_level)
	if level != _alert_level:
		var old: int = _alert_level
		_alert_level = level
		EventBus.alert_level_changed.emit(old, level)


## Rondas de vigilancia por hora de juego.
func get_guard_round_frequency() -> float:
	return _bal_f(B_ROUNDS_BASE) + _bal_f(B_ROUNDS_LEVEL) * _alert_level


## Perspicacia extra de los vigilantes (suma al rasgo).
func get_guard_perception_bonus() -> int:
	return _bal_i(B_GUARD_PERCEPTION) * _alert_level


## Probabilidad de que los vigilantes revisen las grabaciones del día.
func get_footage_review_probability() -> float:
	return clampf(_bal_f(B_REVIEW_BASE) + _bal_f(B_REVIEW_LEVEL) * _alert_level, 0.0, 1.0)


## Sospecha del jugador conocida por Security (última de suspicion_changed).
func get_known_suspicion() -> float:
	return _suspicion


func is_player_marked() -> bool:
	return _today < _marked_until


func get_player_marked_until() -> int:
	return _marked_until


func _recent_incident_count() -> int:
	var window: int = _bal_i(B_ALERT_RECENT_DAYS)
	var recent: Array[int] = []
	for day: int in _incident_days:
		if _today - day < window:
			recent.append(day)
	_incident_days = recent
	return recent.size()


func _note_incident() -> void:
	_incident_days.append(_today)
	recalculate_alert_level()


# ─── Cámaras y registros (§5.5, PASO 27) ──────────────────────

## La cámara de `room_id` grabó al jugador (sin acreditación o cometiendo un delito).
## Registro permanente: solo desaparece con delete_footage desde la sala de monitores.
func register_camera_footage(room_id: String, day: int, hour: int) -> String:
	var entry: Dictionary = _store_footage("", room_id, day, hour)
	_emitting = true
	EventBus.camera_recorded_player.emit(str(entry["camera_id"]), room_id, day)
	_emitting = false
	return str(entry["id"])


## Solo desde sala de monitores.
func delete_footage(footage_id: String) -> bool:
	var monitor_room: String = str(Database.get_balance(B_MONITOR_ROOM))
	if InvestigationEngine.base_room(_current_player_room()) != monitor_room:
		return false
	var index: int = _index_of(_footage, footage_id)
	if index < 0:
		return false
	var entry: Dictionary = _footage[index]
	_footage.remove_at(index)
	EventBus.record_destroyed.emit(footage_id, DESTROY_METHOD_MONITOR)
	EventBus.crime_committed.emit(CRIME_FOOTAGE_DELETED, monitor_room, {
		"camera_id": entry["camera_id"], "room_id": entry["room_id"], "day": entry["day"],
		"footage_id": footage_id, "method": DESTROY_METHOD_MONITOR})
	return true


func get_footage_for_room(room_id: String, day: int) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in _footage:
		if InvestigationEngine.base_room(str(entry["room_id"])) \
				== InvestigationEngine.base_room(room_id) and int(entry["day"]) == day:
			out.append(str(entry["id"]))
	return out


## Extra (BUILD_NOTES §13): todas las grabaciones vigentes {id, camera_id, room_id, day, hour, subject}.
func get_footage_list() -> Array[Dictionary]:
	return _footage.duplicate(true)


## Un lector de tarjeta registró una tarjeta (la del jugador o una ajena que él usa).
## room_id vacío → la sala actual del jugador.
func log_card_access(reader_id: String, card_owner: String, day: int, hour: int,
		room_id: String = "") -> String:
	var entry: Dictionary = _store_access(reader_id, card_owner, day, hour, room_id)
	_emitting = true
	EventBus.card_reader_logged.emit(reader_id, card_owner, day, hour)
	_emitting = false
	return str(entry["id"])


## Extra (BUILD_NOTES §13): {id, reader_id, card_owner, day, hour, room_id}.
func get_access_log() -> Array[Dictionary]:
	return _access_log.duplicate(true)


func _store_footage(camera_id: String, room_id: String, day: int, hour: int) -> Dictionary:
	_counter += 1
	var id: String = FOOTAGE_ID_FORMAT % [InvestigationEngine.base_room(room_id), day, hour, _counter]
	var entry: Dictionary = {"id": id, "camera_id": id if camera_id.is_empty() else camera_id,
			"room_id": room_id, "day": day, "hour": hour, "subject": _recorded_subject()}
	_footage.append(entry)
	return entry


func _store_access(reader_id: String, card_owner: String, day: int, hour: int,
		room_id: String) -> Dictionary:
	_counter += 1
	var entry: Dictionary = {"id": ACCESS_ID_FORMAT % _counter, "reader_id": reader_id,
			"card_owner": PLAYER if card_owner.is_empty() else card_owner, "day": day,
			"hour": hour, "room_id": _current_player_room() if room_id.is_empty() else room_id}
	_access_log.append(entry)
	return entry


func _recorded_subject() -> String:
	var uniform: String = str(_ask(PlayerState, "get_disguise", _player_disguise))
	if uniform.is_empty():
		return PLAYER
	return InvestigationEngine.SUBJECT_UNIFORM_PREFIX + uniform


# ─── Investigaciones: apertura (§12.3 fase 1, §15.3) ──────────

func open_investigation(incident_type: String, severity: int, location: String) -> String:
	return report_incident(incident_type, severity, location, false)


## Extra: registra un incidente. Abre caso si su peso (más lo acumulado en la misma sala)
## alcanza el umbral de apertura (3,0 − 0,03 × sospecha) y la regla de respiro lo permite
## (exenta si player_caused). Si ya hay caso activo en la sala, se suma a él. Por debajo del
## umbral queda pendiente; bloqueado por el respiro, diferido. details: weight, subject, witness,
## victim, body_id, evidence_type, certainty, record_id, day, hour, player_culprit.
func report_incident(incident_type: String, severity: int, location: String,
		player_caused: bool, details: Dictionary = {}) -> String:
	var incident: Dictionary = _make_incident(incident_type, severity, location, player_caused,
			details)
	_note_incident()
	return _route_incident(incident)


func _make_incident(incident_type: String, severity: int, location: String, player_caused: bool,
		details: Dictionary) -> Dictionary:
	var trigger: Dictionary = InvestigationEngine.find_by_id(
			_params.get("incident_triggers", []), incident_type)
	var incident: Dictionary = {
		"type": incident_type, "location": location, "player_caused": player_caused,
		"severity": InvestigationEngine.effective_severity(severity, trigger, _max_severity()),
		"weight": float(details.get("weight", trigger.get("initial_weight", 0.0))),
		"day": int(details.get("day", _today)), "hour": int(details.get("hour", _hour)),
		"subject": str(details.get("subject", "")), "witness": str(details.get("witness", "")),
		"victim": str(details.get("victim", "")), "body_id": str(details.get("body_id", "")),
		"evidence_type": str(details.get("evidence_type", incident_type)),
		"certainty": float(details.get("certainty", Investigation.FULL_CERTAINTY)),
		"record_id": str(details.get("record_id", "")),
		"player_culprit": bool(details.get("player_culprit", player_caused)),
	}
	return incident


func _route_incident(incident: Dictionary) -> String:
	var existing: String = _find_case_for(incident)
	if not existing.is_empty():
		_merge_incident(_cases[existing], incident)
		return existing
	var location: String = str(incident["location"])
	if _pending_weight_at(location) + float(incident["weight"]) < _opening_threshold():
		_pending.append(incident)
		return ""
	if not _rest_exempt(incident) and not _rest_ok():
		_deferred.append(incident)
		return ""
	return _open_case(incident)


func _open_case(incident: Dictionary) -> String:
	_counter += 1
	var inv: Investigation = Investigation.new()
	inv.id = CASE_ID_FORMAT % _counter
	inv.incident_type = str(incident["type"])
	inv.severity = int(incident["severity"])
	inv.location = str(incident["location"])
	inv.phase = InvestigationEngine.PHASE_INCIDENT
	inv.opened_day = _today
	inv.phase_day = _today
	_cases[inv.id] = inv
	_case_order.append(inv.id)
	_meta[inv.id] = _new_meta(incident)
	_has_case_history = true
	_last_case_day = _today
	EventBus.investigation_opened.emit(inv.id, inv.incident_type, inv.severity)
	for earlier: Dictionary in _take_pending_at(inv.location):
		_add_incident_piece(inv, earlier)
	_add_incident_piece(inv, incident)
	_set_phase(inv, InvestigationEngine.PHASE_COLLECTION)
	return inv.id


func _new_meta(incident: Dictionary) -> Dictionary:
	return {
		"incident_day": int(incident["day"]), "incident_hour": int(incident["hour"]),
		"player_caused": bool(incident["player_caused"]),
		"player_culprit": bool(incident["player_culprit"]),
		"victim": str(incident["victim"]), "body_id": str(incident["body_id"]),
		"done_procedures": [], "holders": {}, "piece_days": {}, "motives": [], "framed": [],
		"silent_witnesses": [], "alibis": [], "found": [], "grievance_since_archive": {},
		"interrogation": INTERROGATION_NONE, "interrogator": "", "archived_day": -1,
		"resolved_day": -1, "revivals": 0, "buried_by": "", "culprit_innocent": false,
	}


func _merge_incident(inv: Investigation, incident: Dictionary) -> void:
	var meta: Dictionary = _meta[inv.id]
	inv.severity = maxi(inv.severity, int(incident["severity"]))
	meta["player_culprit"] = bool(meta["player_culprit"]) or bool(incident["player_culprit"])
	if str(meta["victim"]).is_empty():
		meta["victim"] = incident["victim"]
	if str(meta["body_id"]).is_empty():
		meta["body_id"] = incident["body_id"]
	_add_incident_piece(inv, incident)


func _add_incident_piece(inv: Investigation, incident: Dictionary) -> void:
	var piece: Dictionary = Investigation.make_evidence(str(incident["evidence_type"]),
			float(incident["weight"]), float(incident["certainty"]), str(incident["subject"]),
			str(incident["record_id"]))
	_append_piece(inv, piece, str(incident["witness"]))


## Caso al que se suma un incidente: el de la misma víctima, o uno activo en la misma sala
## (o, sin sala, del mismo tipo).
func _find_case_for(incident: Dictionary) -> String:
	var victim: String = str(incident["victim"])
	var location: String = InvestigationEngine.base_room(str(incident["location"]))
	for id: String in _case_order:
		var inv: Investigation = _cases[id]
		if not inv.is_active():
			continue
		if not victim.is_empty() and str(_meta[id]["victim"]) == victim:
			return id
		var same_place: bool = InvestigationEngine.base_room(inv.location) == location
		if same_place and (not location.is_empty() or inv.incident_type == incident["type"]):
			return id
	return ""


func _opening_threshold() -> float:
	return InvestigationEngine.modulated_threshold(_bal_f(B_OPENING), _bal_f(B_THRESHOLD_MOD),
			_suspicion)


func _pending_weight_at(location: String) -> float:
	var total: float = 0.0
	for incident: Dictionary in _pending:
		if InvestigationEngine.base_room(str(incident["location"])) \
				== InvestigationEngine.base_room(location):
			total += float(incident["weight"])
	return total


func _take_pending_at(location: String) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for incident: Dictionary in _pending:
		var same: bool = InvestigationEngine.base_room(str(incident["location"])) \
				== InvestigationEngine.base_room(location)
		(taken if same else kept).append(incident)
	_pending = kept
	return taken


func _rest_ok() -> bool:
	return not _has_case_history \
			or InvestigationEngine.rest_satisfied(_today, _last_case_day, _bal_i(B_REST_DAYS))


func _rest_exempt(incident: Dictionary) -> bool:
	return bool(incident["player_caused"]) \
			and bool(_params.get("rest_rule_exempt_if_player_caused", false))


# ─── Investigaciones: consulta ────────────────────────────────

func get_investigation(case_id: String) -> Investigation:
	return _cases.get(case_id) as Investigation


func get_active_investigations() -> Array[Investigation]:
	return _cases_with_status(Investigation.STATUS_ACTIVE)


func get_cold_cases() -> Array[Investigation]:
	return _cases_with_status(Investigation.STATUS_COLD)


## Extra: todas (activas, frías y cerradas), en orden de apertura.
func get_all_investigations() -> Array[Investigation]:
	var out: Array[Investigation] = []
	for id: String in _case_order:
		out.append(_cases[id])
	return out


## Extra: incidentes a la espera de la regla de respiro (§15.3).
func get_deferred_incident_count() -> int:
	return _deferred.size()


func _cases_with_status(status: String) -> Array[Investigation]:
	var out: Array[Investigation] = []
	for id: String in _case_order:
		var inv: Investigation = _cases[id]
		if inv.status == status:
			out.append(inv)
	return out


## Extra: expediente para el epílogo THE FILE y la interfaz: piezas en orden cronológico,
## investigador, sospechosos, cabezas de turco... ({} si no existe).
func get_case_report(case_id: String) -> Dictionary:
	var inv: Investigation = get_investigation(case_id)
	if inv == null:
		return {}
	var report: Dictionary = InvestigationEngine.build_report(inv, _meta[case_id])
	report["player_weight"] = get_case_weight_against(PLAYER, case_id)
	report["found"] = (_meta[case_id]["found"] as Array).duplicate(true)
	return report


# ─── Evidencia ────────────────────────────────────────────────

## Pieza nueva (certeza 1). En un caso frío la reactiva (determinista, §12.6).
func add_evidence(case_id: String, evidence_type: String, weight: float, points_to: String) -> void:
	var inv: Investigation = get_investigation(case_id)
	if inv == null:
		return
	_append_piece(inv, Investigation.make_evidence(evidence_type, weight,
			Investigation.FULL_CERTAINTY, points_to, ""), "")


## Incorpora una pieza al caso (sin duplicar record_id). Devuelve false si no se añadió.
func _append_piece(inv: Investigation, piece: Dictionary, holder: String) -> bool:
	if inv.status == Investigation.STATUS_CLOSED:
		return false
	var record_id: String = str(piece.get("record_id", ""))
	if record_id.is_empty():
		_counter += 1
		record_id = PIECE_ID_FORMAT % [inv.id, _counter]
		piece["record_id"] = record_id
	elif InvestigationEngine.has_piece(inv, record_id):
		return false
	inv.evidence.append(piece)
	var meta: Dictionary = _meta[inv.id]
	(meta["piece_days"] as Dictionary)[record_id] = _today
	if not holder.is_empty():
		(meta["holders"] as Dictionary)[record_id] = holder
	EventBus.evidence_added.emit(inv.id, str(piece["type"]), float(piece["weight"]),
			str(piece["points_to"]))
	if inv.status == Investigation.STATUS_COLD:
		revive_cold_case(inv.id, TRIGGER_NEW_PIECE)
	return true


## Extra (interrogatorio y palancas): retira una pieza de un caso activo.
func remove_evidence(case_id: String, record_id: String, _reason: String) -> bool:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or not inv.is_active():
		return false
	var index: int = InvestigationEngine.find_piece(inv, record_id)
	if index < 0:
		return false
	inv.evidence.remove_at(index)
	return true


## Extra (interrogatorio: coartada falsa verificada → ×2).
func scale_evidence(case_id: String, record_id: String, factor: float) -> bool:
	var inv: Investigation = get_investigation(case_id)
	var index: int = -1 if inv == null else InvestigationEngine.find_piece(inv, record_id)
	if index < 0 or not inv.is_active():
		return false
	inv.evidence[index]["weight"] = float(inv.evidence[index]["weight"]) * factor
	return true


## Extra (interrogatorio: acusar a otro). El acusado queda como cabeza de turco del caso.
func transfer_evidence(case_id: String, record_id: String, new_subject: String) -> bool:
	var inv: Investigation = get_investigation(case_id)
	var index: int = -1 if inv == null else InvestigationEngine.find_piece(inv, record_id)
	if index < 0 or not inv.is_active() or not InvestigationEngine.is_identified(new_subject):
		return false
	inv.evidence[index]["points_to"] = new_subject
	_append_unique(_meta[case_id]["framed"], new_subject)
	return true


## Quita de los casos ACTIVOS las piezas con ese record_id (los fríos conservan su expediente).
func _drop_record_everywhere(record_id: String) -> void:
	for inv: Investigation in get_active_investigations():
		var index: int = InvestigationEngine.find_piece(inv, record_id)
		if index >= 0:
			inv.evidence.remove_at(index)


# ─── Fases (§12.3) ────────────────────────────────────────────

## Fuerza la fase siguiente ahora (depuración, pruebas y escenas). En la fase 2 ejecuta antes
## los procedimientos pendientes.
func advance_phase(case_id: String) -> void:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or not inv.is_active():
		return
	match inv.phase:
		InvestigationEngine.PHASE_INCIDENT:
			_set_phase(inv, InvestigationEngine.PHASE_COLLECTION)
		InvestigationEngine.PHASE_COLLECTION:
			_run_due_procedures(inv, _collection_days(inv))
			_set_phase(inv, InvestigationEngine.PHASE_SHORTLIST)
		InvestigationEngine.PHASE_SHORTLIST:
			_leave_shortlist(inv)
		InvestigationEngine.PHASE_INTERROGATION:
			_set_phase(inv, InvestigationEngine.PHASE_VERDICT)


## Extra: tic diario (lo invoca day_advanced; público para pruebas y el panel F1).
func process_day(day: int) -> void:
	_today = day
	_hour = _bal_i(B_DAY_START)
	_detect_absences()
	_expire_pending()
	_open_deferred()
	for id: String in _case_order.duplicate():
		var inv: Investigation = _cases[id]
		if inv.is_active() and not inv.is_frozen(day):
			_tick_case(inv)
	recalculate_alert_level()


func _tick_case(inv: Investigation) -> void:
	var elapsed: int = _today - inv.phase_day
	match inv.phase:
		InvestigationEngine.PHASE_INCIDENT:
			_set_phase(inv, InvestigationEngine.PHASE_COLLECTION)
		InvestigationEngine.PHASE_COLLECTION:
			_run_due_procedures(inv, elapsed)
			if elapsed >= _collection_days(inv):
				_set_phase(inv, InvestigationEngine.PHASE_SHORTLIST)
		InvestigationEngine.PHASE_SHORTLIST:
			if elapsed >= _phase_days("shortlist"):
				_leave_shortlist(inv)
		InvestigationEngine.PHASE_INTERROGATION:
			var state: String = str(_meta[inv.id]["interrogation"])
			if state == INTERROGATION_DONE or (elapsed >= _phase_days("interrogation")
					and state != INTERROGATION_IN_PROGRESS):
				_set_phase(inv, InvestigationEngine.PHASE_VERDICT)


func _set_phase(inv: Investigation, phase: int) -> void:
	inv.phase = phase
	inv.phase_day = _today
	EventBus.investigation_phase_advanced.emit(inv.id, phase)
	match phase:
		InvestigationEngine.PHASE_SHORTLIST:
			_form_shortlist(inv, true)
		InvestigationEngine.PHASE_INTERROGATION:
			_start_interrogation_phase(inv)
		InvestigationEngine.PHASE_VERDICT:
			_conclude(inv)


func _leave_shortlist(inv: Investigation) -> void:
	_form_shortlist(inv, false)
	if not inv.suspects.is_empty() and inv.suspects[0] == PLAYER:
		_set_phase(inv, InvestigationEngine.PHASE_INTERROGATION)
	else:
		_set_phase(inv, InvestigationEngine.PHASE_VERDICT)


func _collection_days(inv: Investigation) -> int:
	var table: Dictionary = InvestigationEngine.dig(_params,
			"phase_durations.evidence_collection_by_severity", {})
	return InvestigationEngine.collection_days(inv.severity, table, _bal_i(B_COLLECT_MIN),
			_bal_i(B_COLLECT_MAX))


func _phase_days(phase_id: String) -> int:
	return int(InvestigationEngine.dig(_params, "phase_durations." + phase_id, 0))


func _max_severity() -> int:
	return (_params.get("severity_levels", []) as Array).size()


func _detect_absences() -> void:
	var delay: int = _bal_i(B_ABSENCE_DAYS)
	for npc_id: String in _absences.keys():
		var removed_day: int = int(_absences[npc_id])
		if _today - removed_day < delay:
			continue
		_absences.erase(npc_id)
		var body: Dictionary = _body_of(npc_id)
		report_incident(INCIDENT_MISSING_PERSON, _bal_i(B_MISSING_SEVERITY),
				str(body.get("room_id", "")), true, {"weight": _bal_f(B_MISSING_WEIGHT),
				"victim": npc_id, "body_id": str(body.get("body_id", "")), "day": removed_day,
				"hour": -1, "player_culprit": true})


func _expire_pending() -> void:
	var window: int = _bal_i(B_PENDING_DAYS)
	var kept: Array[Dictionary] = []
	for incident: Dictionary in _pending:
		if _today - int(incident["day"]) < window:
			kept.append(incident)
	_pending = kept


func _open_deferred() -> void:
	if _deferred.is_empty() or not _rest_ok():
		return
	var incident: Dictionary = _deferred.pop_front()
	var existing: String = _find_case_for(incident)
	if existing.is_empty():
		_open_case(incident)
	else:
		_merge_incident(_cases[existing], incident)


# ─── Fase 2: recogida de evidencia ────────────────────────────

func _run_due_procedures(inv: Investigation, elapsed: int) -> void:
	var procedures: Array = InvestigationEngine.dig(_params, "evidence_collection.procedures", [])
	var done: Array = _meta[inv.id]["done_procedures"]
	var total: int = _collection_days(inv)
	for i: int in procedures.size():
		var procedure: String = str(procedures[i])
		if done.has(procedure) \
				or elapsed < InvestigationEngine.procedure_due_day(i, procedures.size(), total):
			continue
		done.append(procedure)
		match procedure:
			InvestigationEngine.PROC_WITNESSES:
				_interrogate_witnesses(inv)
			InvestigationEngine.PROC_FOOTAGE:
				_review_footage(inv)
			InvestigationEngine.PROC_SEARCH:
				_search_rooms(inv)


## Procedimiento 1: creencias del grafo sobre el jugador (y registros) ligadas al incidente.
func _interrogate_witnesses(inv: Investigation) -> void:
	var meta: Dictionary = _meta[inv.id]
	var from_day: int = int(meta["incident_day"]) - _bal_i(B_WITNESS_WINDOW)
	var weights: Dictionary = _witness_weights()
	var beliefs: Array[Belief] = BeliefNet.get_beliefs_about(PLAYER)
	beliefs.append_array(BeliefNet.get_records_about(PLAYER))
	for b: Belief in beliefs:
		if not InvestigationEngine.is_belief_relevant(b, inv.location, from_day, _today):
			continue
		if not b.is_record and not bool(_ask(BeliefNet, "is_negative_fact", true, [b.fact])):
			continue
		if _bought_witnesses.has(b.holder):
			_append_unique(meta["silent_witnesses"], b.holder)
			continue
		if not b.is_record and (meta["holders"] as Dictionary).values().has(b.holder):
			continue
		var piece: Dictionary = InvestigationEngine.piece_from_belief(b, weights,
				_bal_f(B_DIRECT_MIN))
		if not piece.is_empty():
			_append_piece(inv, piece, "" if b.is_record else b.holder)


## Procedimiento 2: grabaciones y lectores de la sala del incidente en su franja.
func _review_footage(inv: Investigation) -> void:
	var meta: Dictionary = _meta[inv.id]
	var day: int = int(meta["incident_day"])
	var hour: int = int(meta["incident_hour"])
	var window: int = int(InvestigationEngine.dig(_params,
			"evidence_collection.footage_review_hours_around_incident", 0))
	for entry: Dictionary in _footage:
		if InvestigationEngine.is_record_relevant(entry, inv.location, day, hour, window):
			_append_piece(inv, Investigation.make_evidence(InvestigationEngine.EV_FOOTAGE,
					_evidence_weight(InvestigationEngine.EV_FOOTAGE),
					Investigation.FULL_CERTAINTY, str(entry["subject"]), str(entry["id"])), "")
	for entry: Dictionary in _access_log:
		if InvestigationEngine.is_record_relevant(entry, inv.location, day, hour, window):
			_append_piece(inv, Investigation.make_evidence(InvestigationEngine.EV_CARD_LOG,
					_evidence_weight(InvestigationEngine.EV_CARD_LOG),
					Investigation.FULL_CERTAINTY, str(entry["card_owner"]), str(entry["id"])), "")


## Procedimiento 3: registro físico por orden de probabilidad. Aquí aflora un cuerpo mal
## oculto o un objeto escondido (§12.3).
func _search_rooms(inv: Investigation) -> void:
	var plan: Array[Dictionary] = InvestigationEngine.search_plan(inv.location, inv.severity,
			_params.get("room_search", {}), _bal_f(B_INCIDENT_ROOM_CHANCE))
	for room: String in InvestigationEngine.plan_rooms(plan):
		if not inv.searched_rooms.has(room):
			inv.searched_rooms.append(room)
	for hit: Dictionary in InvestigationEngine.run_search(plan, _search_targets(), _rng):
		if str(hit["kind"]) == InvestigationEngine.TARGET_BODY:
			_register_body_find(inv, hit)
		else:
			_register_item_find(inv, hit)


func _search_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for body_id: String in _bodies:
		var info: Dictionary = _body_info(body_id)
		if not bool(info.get("discovered", false)):
			targets.append({"kind": InvestigationEngine.TARGET_BODY, "id": body_id,
					"room_id": str(info.get("room_id", "")), "spot_id": str(info.get("spot_id", "")),
					"hidden": bool(info.get("hidden", false))})
	var stashes: Dictionary = _current_stashes()
	for spot_id: String in stashes:
		var stash: Dictionary = stashes[spot_id]
		for item: Variant in stash.get("items", []):
			var item_id: String = str(item.get("id", "")) if item is Dictionary else str(item)
			if _is_hot(item_id) and not _confiscated.has(STASH_KEY_FORMAT % [spot_id, item_id]):
				targets.append({"kind": InvestigationEngine.TARGET_ITEM, "id": item_id,
						"room_id": str(stash.get("room_id", "")), "spot_id": spot_id,
						"hidden": true})
	return targets


func _register_body_find(inv: Investigation, hit: Dictionary) -> void:
	var body_id: String = str(hit["id"])
	var room_id: String = str(hit["room_id"])
	if _bodies.has(body_id):
		_bodies[body_id]["discovered"] = true
	_append_unique(_meta[inv.id]["found"], BODY_PIECE_FORMAT % body_id)
	_emitting = true
	EventBus.body_discovered.emit(body_id, room_id)
	_emitting = false
	_append_piece(inv, _body_piece(body_id, room_id, str(hit.get("plan_spot", ""))), "")


func _register_item_find(inv: Investigation, hit: Dictionary) -> void:
	var spot_id: String = str(hit["spot_id"])
	var item_id: String = str(hit["id"])
	_confiscated.append(STASH_KEY_FORMAT % [spot_id, item_id])
	_found_items.append({"case_id": inv.id, "spot_id": spot_id, "item_id": item_id,
			"room_id": hit["room_id"], "day": _today})
	_append_unique(_meta[inv.id]["found"], ITEM_PIECE_FORMAT % [spot_id, item_id])
	var own: bool = _is_own_workspace(str(hit["room_id"]), str(hit.get("plan_spot", "")))
	var certainty: float = Investigation.FULL_CERTAINTY if own else _bal_f(B_HIDDEN_CERTAINTY)
	_append_piece(inv, Investigation.make_evidence(InvestigationEngine.EV_ITEM,
			_evidence_weight(InvestigationEngine.EV_ITEM), certainty, PLAYER,
			ITEM_PIECE_FORMAT % [spot_id, item_id]), "")


## Pieza "cuerpo hallado" (12,0): la cadena forense (manchas, accesos, último contacto) apunta
## al jugador con certeza parcial; total si el cuerpo estaba en su propio puesto.
func _body_piece(body_id: String, room_id: String, plan_spot: String) -> Dictionary:
	var own: bool = _is_own_workspace(room_id, plan_spot)
	var certainty: float = Investigation.FULL_CERTAINTY if own else _bal_f(B_BODY_CERTAINTY)
	return Investigation.make_evidence(InvestigationEngine.EV_BODY,
			_evidence_weight(InvestigationEngine.EV_BODY), certainty, PLAYER,
			BODY_PIECE_FORMAT % body_id)


## Extra (para PlayerState): objetos incautados en registros de salas
## [{case_id, spot_id, item_id, room_id, day}].
func get_found_items() -> Array[Dictionary]:
	return _found_items.duplicate(true)


# ─── Fases 3-5: lista corta, interrogatorio y veredicto ───────

func _form_shortlist(inv: Investigation, always_emit: bool) -> void:
	var weights: Dictionary = _suspect_weights(inv)
	var shortlist: Array[String] = InvestigationEngine.form_shortlist(weights,
			_player_phase_threshold(B_SHORTLIST), _bal_f(B_SHORTLIST), _max_suspects())
	var changed: bool = shortlist != inv.suspects
	inv.suspects = shortlist
	if always_emit or changed:
		EventBus.suspect_list_formed.emit(inv.id, shortlist.duplicate())


func _suspect_weights(inv: Investigation) -> Dictionary:
	var meta: Dictionary = _meta[inv.id]
	var last: String = get_last_to_leave(int(meta["incident_day"]))
	var extra: Array[String] = [last]
	for subject: Variant in meta["motives"]:
		extra.append(str(subject))
	var out: Dictionary = {}
	for subject: String in InvestigationEngine.candidates(inv, extra):
		out[subject] = InvestigationEngine.suspect_weight(inv, subject,
				_flags(inv, subject, last), _bonuses())
	return out


func _flags(inv: Investigation, subject: String, last: String) -> Dictionary:
	return {
		InvestigationEngine.FLAG_ACCESS: _has_access(subject, inv.location),
		InvestigationEngine.FLAG_MOTIVE: (_meta[inv.id]["motives"] as Array).has(subject),
		InvestigationEngine.FLAG_LAST: not last.is_empty() and last == subject,
	}


func _bonuses() -> Dictionary:
	return {
		InvestigationEngine.FLAG_ACCESS: _bal_f(B_BONUS_ACCESS),
		InvestigationEngine.FLAG_MOTIVE: _bal_f(B_BONUS_MOTIVE),
		InvestigationEngine.FLAG_LAST: _bal_f(B_BONUS_LAST),
	}


func _player_phase_threshold(path: String) -> float:
	return InvestigationEngine.modulated_threshold(_bal_f(path), _bal_f(B_THRESHOLD_MOD),
			_suspicion)


func _max_suspects() -> int:
	return int(InvestigationEngine.dig(_params, "shortlist.max_suspects", 0))


func _start_interrogation_phase(inv: Investigation) -> void:
	var meta: Dictionary = _meta[inv.id]
	meta["interrogation"] = INTERROGATION_NONE
	meta["interrogator"] = _pick_interrogator()
	EventBus.interrogation_started.emit(inv.id, str(meta["interrogator"]))


## Por defecto Rose Miller; si no está, quien ocupe Auditoría o Seguridad (§12.5).
func _pick_interrogator() -> String:
	var default_id: String = str(InvestigationEngine.dig(_params,
			"interrogation.default_interrogator", ""))
	if NPCDirector.is_alive(default_id):
		return default_id
	for occupation: Variant in InvestigationEngine.dig(_params,
			"interrogation.interrogator_occupations", []):
		var holder: String = _seat_holder(str(occupation))
		if InvestigationEngine.is_identified(holder) and holder != PLAYER:
			return holder
	return default_id


func _conclude(inv: Investigation) -> void:
	var weights: Dictionary = _suspect_weights(inv)
	inv.suspects = InvestigationEngine.form_shortlist(weights,
			_player_phase_threshold(B_SHORTLIST), _bal_f(B_SHORTLIST), _max_suspects())
	var result: Dictionary = InvestigationEngine.decide_verdict(weights, inv.suspects,
			_bal_f(B_MINOR), _bal_f(B_MAJOR))
	resolve_investigation(inv.id, str(result["verdict"]), str(result["culprit"]))


## Aplica un veredicto (fase 5): "cold" archiva el caso (frío, no cerrado); "other_guilty"
## (NPCDirector expulsa al culpable al oír investigation_resolved); "player_minor" (un oyente de
## la fase Mundo aplica descenso y pérdida de acreditación; Security marca al jugador con alerta
## máxima unas semanas); "player_major" → game_over THE FILE.
func resolve_investigation(case_id: String, verdict: String, culprit: String) -> void:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or not inv.is_active() or not InvestigationEngine.VERDICTS.has(verdict):
		return
	var meta: Dictionary = _meta[case_id]
	if inv.phase != InvestigationEngine.PHASE_VERDICT:
		inv.phase = InvestigationEngine.PHASE_VERDICT
		EventBus.investigation_phase_advanced.emit(case_id, inv.phase)
	inv.verdict = verdict
	inv.culprit = culprit
	meta["resolved_day"] = _today
	_last_case_day = _today
	if verdict == InvestigationEngine.VERDICT_COLD:
		_archive(inv)
		return
	inv.status = Investigation.STATUS_CLOSED
	meta["culprit_innocent"] = verdict == InvestigationEngine.VERDICT_OTHER \
			and (bool(meta["player_culprit"]) or (meta["framed"] as Array).has(culprit))
	EventBus.investigation_resolved.emit(case_id, verdict, culprit)
	if verdict == InvestigationEngine.VERDICT_PLAYER_MINOR:
		_mark_player()
	elif verdict == InvestigationEngine.VERDICT_PLAYER_MAJOR:
		_emit_game_over(inv)
	recalculate_alert_level()


func _archive(inv: Investigation) -> void:
	var meta: Dictionary = _meta[inv.id]
	inv.status = Investigation.STATUS_COLD
	inv.culprit = ""
	meta["archived_day"] = _today
	meta["grievance_since_archive"] = {}
	EventBus.investigation_resolved.emit(inv.id, InvestigationEngine.VERDICT_COLD, "")
	EventBus.case_went_cold.emit(inv.id)


func _mark_player() -> void:
	var data: Dictionary = _verdict_data(InvestigationEngine.VERDICT_PLAYER_MINOR)
	var weeks: int = int(data.get("max_suspicion_weeks", 0))
	_marked_until = maxi(_marked_until, _today + weeks * _bal_i(B_DAYS_PER_WEEK))


func _emit_game_over(inv: Investigation) -> void:
	var data: Dictionary = _verdict_data(InvestigationEngine.VERDICT_PLAYER_MAJOR)
	var snapshot: Dictionary = Tracking.get_snapshot().duplicate(true)
	snapshot["case_id"] = inv.id
	snapshot["case_report"] = get_case_report(inv.id)
	EventBus.game_over.emit(str(data.get("game_over_cause", "")), str(data.get("ending_id", "")),
			snapshot)


func _verdict_data(verdict: String) -> Dictionary:
	return InvestigationEngine.find_by_id(_params.get("verdicts", []),
			str(InvestigationEngine.VERDICT_DATA_IDS.get(verdict, verdict)))


# ─── Interrogatorio (§12.5; la escena usa Interrogation) ──────

## La escena de la sala de interrogatorios empieza (el caso debe estar en fase 4).
func begin_interrogation(case_id: String) -> bool:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or not inv.is_active() or inv.phase != InvestigationEngine.PHASE_INTERROGATION:
		return false
	_meta[case_id]["interrogation"] = INTERROGATION_IN_PROGRESS
	return true


## La escena termina: {success (peso < 7,0), total_weight, verdict}. Si el caso no está
## congelado se dicta veredicto en el acto (fase 5).
func finish_interrogation(case_id: String) -> Dictionary:
	var inv: Investigation = get_investigation(case_id)
	if inv == null:
		return {}
	var total: float = get_case_weight_against(PLAYER, case_id)
	var success_below: float = float(InvestigationEngine.dig(_params,
			"interrogation.success_below_weight", 0.0))
	if inv.is_active() and inv.phase == InvestigationEngine.PHASE_INTERROGATION:
		_meta[case_id]["interrogation"] = INTERROGATION_DONE
		if not inv.is_frozen(_today):
			_set_phase(inv, InvestigationEngine.PHASE_VERDICT)
	return {"success": total < success_below, "total_weight": total, "verdict": inv.verdict}


func get_interrogator(case_id: String) -> String:
	if not _meta.has(case_id):
		return ""
	var current: String = str(_meta[case_id]["interrogator"])
	return current if not current.is_empty() else _pick_interrogator()


## Coartada utilizable al «explicar»: la real que dan los registros (el jugador consta en otra
## sala a la hora del incidente) o, si no, la mejor aportada (aliado o comprada). {} si ninguna.
func get_alibi(case_id: String) -> Dictionary:
	var inv: Investigation = get_investigation(case_id)
	if inv == null:
		return {}
	if _records_place_player_elsewhere(inv):
		return {"provider": ALIBI_FROM_RECORDS, "genuine": true}
	var best: Dictionary = {}
	for alibi: Variant in _meta[case_id]["alibis"]:
		if best.is_empty() or bool((alibi as Dictionary).get("genuine", false)):
			best = (alibi as Dictionary).duplicate()
	return best


## Contacto en el bufete de P9: alguien cuya sala es la del bufete y que aprecia al jugador,
## le debe algo o le ha hecho favores.
func has_legal_contact() -> bool:
	var room: String = str(InvestigationEngine.find_by_id(InvestigationEngine.dig(_params,
			"interrogation.answers", []), "request_lawyer").get("contact_room", ""))
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.alive or InvestigationEngine.base_room(npc.home_room) != room:
			continue
		var ledger: Dictionary = npc.ledger
		if int(ledger.get("affection", 0)) >= _bal_i(B_LEGAL_AFFECTION) \
				or int(ledger.get("debt", 0)) > 0 or not (ledger.get("favours", []) as Array).is_empty():
			return true
	return false


func _records_place_player_elsewhere(inv: Investigation) -> bool:
	var meta: Dictionary = _meta[inv.id]
	var hour: int = int(meta["incident_hour"])
	if hour < 0:
		return false
	var window: int = int(InvestigationEngine.dig(_params,
			"evidence_collection.footage_review_hours_around_incident", 0))
	var elsewhere: bool = false
	for entry: Dictionary in _player_records():
		if int(entry["day"]) != int(meta["incident_day"]) \
				or absi(int(entry["hour"]) - hour) > window:
			continue
		if InvestigationEngine.base_room(str(entry["room_id"])) \
				== InvestigationEngine.base_room(inv.location):
			return false
		elsewhere = true
	return elsewhere


func _player_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _footage:
		if str(entry["subject"]) == PLAYER:
			out.append(entry)
	for entry: Dictionary in _access_log:
		if str(entry["card_owner"]) == PLAYER:
			out.append(entry)
	return out


# ─── Palancas del jugador (§12.3) ─────────────────────────────

## Soborno «mentir en un interrogatorio» aceptado: su testimonio sale de los casos activos y
## deja de contar en recogidas futuras (queda como testigo silencioso). → piezas retiradas.
func bribe_witness(npc_id: String) -> int:
	_append_unique(_bought_witnesses, npc_id)
	var removed: int = 0
	for inv: Investigation in get_active_investigations():
		var holders: Dictionary = _meta[inv.id]["holders"]
		for record_id: Variant in holders.keys():
			if str(holders[record_id]) == npc_id and remove_evidence(inv.id, str(record_id), FAVOUR_LIE):
				removed += 1
				_append_unique(_meta[inv.id]["silent_witnesses"], npc_id)
	return removed


## Soborno «enterrar la investigación» (×100) aceptado por el Auditor Jefe: el caso se archiva
## (frío, no cerrado: un nuevo Auditor puede revisarlo). case_id vacío → el caso activo más
## pesado contra el jugador.
func bury_investigation(case_id: String, npc_id: String) -> bool:
	if npc_id.is_empty() or npc_id != _seat_holder(_watched_occupation()):
		return false
	var target: String = case_id if not case_id.is_empty() else _heaviest_case_against_player()
	var inv: Investigation = get_investigation(target)
	if inv == null or not inv.is_active():
		return false
	_meta[target]["buried_by"] = npc_id
	resolve_investigation(target, InvestigationEngine.VERDICT_COLD, "")
	return true


## Coartada de un aliado (genuine = true si es verdad) o comprada (false).
func provide_alibi(case_id: String, provider_id: String, genuine: bool) -> void:
	if _meta.has(case_id):
		(_meta[case_id]["alibis"] as Array).append({"provider": provider_id, "genuine": genuine})


## Incriminar: pieza del tipo indicado (peso de la tabla §12.4) que apunta a otro personaje.
func plant_evidence(case_id: String, target_id: String, evidence_type: String) -> bool:
	var inv: Investigation = get_investigation(case_id)
	var weight: float = _evidence_weight(evidence_type)
	if inv == null or not inv.is_active() or weight <= 0.0 or target_id == PLAYER \
			or not InvestigationEngine.is_identified(target_id):
		return false
	_append_unique(_meta[case_id]["framed"], target_id)
	return _append_piece(inv, Investigation.make_evidence(evidence_type, weight,
			Investigation.FULL_CERTAINTY, target_id, ""), "")


## Asistencia legal (contacto en P9): congela el caso tres jornadas.
func request_legal_assistance(case_id: String) -> bool:
	return has_legal_contact() and freeze_case(case_id, _bal_i(B_LAWYER_DAYS))


## Congela el caso `days` jornadas: no avanza y sus plazos se desplazan.
func freeze_case(case_id: String, days: int) -> bool:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or not inv.is_active() or days <= 0:
		return false
	inv.frozen_until_day = maxi(inv.frozen_until_day, _today + days)
	inv.phase_day += days
	return true


func register_motive(case_id: String, subject: String) -> void:
	if _meta.has(case_id) and InvestigationEngine.is_identified(subject):
		_append_unique(_meta[case_id]["motives"], subject)


func add_silent_witness(case_id: String, npc_id: String) -> void:
	if _meta.has(case_id) and not npc_id.is_empty():
		_append_unique(_meta[case_id]["silent_witnesses"], npc_id)


## Quién salió el último del edificio (la escena lo fija para los personajes; el jugador se
## detecta solo al pasar la noche dentro o salir de noche). day < 0 → hoy.
func set_last_to_leave(subject_id: String, day: int = -1) -> void:
	_last_out[str(_today if day < 0 else day)] = subject_id


func get_last_to_leave(day: int) -> String:
	return str(_last_out.get(str(day), ""))


func _heaviest_case_against_player() -> String:
	var best: String = ""
	var best_weight: float = -1.0
	for inv: Investigation in get_active_investigations():
		var weight: float = get_case_weight_against(PLAYER, inv.id)
		if weight > best_weight:
			best = inv.id
			best_weight = weight
	return best


# ─── Casos fríos (§12.6, PASO 30) ─────────────────────────────

func revive_cold_case(case_id: String, trigger: String) -> void:
	var inv: Investigation = get_investigation(case_id)
	if inv == null or inv.status != Investigation.STATUS_COLD:
		return
	var meta: Dictionary = _meta[case_id]
	inv.status = Investigation.STATUS_ACTIVE
	inv.verdict = ""
	inv.frozen_until_day = 0
	meta["done_procedures"] = []
	meta["interrogation"] = INTERROGATION_NONE
	meta["revivals"] = int(meta["revivals"]) + 1
	EventBus.case_revived.emit(case_id, trigger)
	_set_phase(inv, InvestigationEngine.PHASE_COLLECTION)


## Solo Auditor Jefe: es la única vía de cierre definitivo de un caso frío.
func close_case_permanently(case_id: String) -> bool:
	var required: String = str(InvestigationEngine.dig(_params,
			"cold_case_revival.permanent_close_occupation", ""))
	var inv: Investigation = get_investigation(case_id)
	if required.is_empty() or _player_occupation_id() != required or inv == null \
			or inv.status != Investigation.STATUS_COLD:
		return false
	inv.status = Investigation.STATUS_CLOSED
	_meta[case_id]["resolved_day"] = _today
	EventBus.investigation_resolved.emit(case_id, VERDICT_CLOSED, "")
	return true


## Cambio de ocupante en Auditoría: cada caso frío se revisa con la probabilidad de datos (40%).
func _review_cold_cases() -> void:
	var chance: float = _bal_f(B_AUDITOR_REVIEW)
	for inv: Investigation in get_cold_cases():
		if _rng.randf() < chance:
			revive_cold_case(inv.id, TRIGGER_AUDITOR)


## Un testigo silencioso agraviado desde el archivo puede hablar: p ∝ agravio acumulado.
func _check_silent_witness(npc_id: String, severity: int) -> void:
	var trigger: Dictionary = _cold_trigger(TRIGGER_SILENT_WITNESS)
	for inv: Investigation in get_cold_cases():
		var meta: Dictionary = _meta[inv.id]
		if not (meta["silent_witnesses"] as Array).has(npc_id):
			continue
		var sums: Dictionary = meta["grievance_since_archive"]
		sums[npc_id] = int(sums.get(npc_id, 0)) + severity
		var chance: float = InvestigationEngine.silent_witness_chance(int(sums[npc_id]),
				float(trigger.get("probability_per_grievance_severity", 0.0)),
				float(trigger.get("max_probability", 0.0)))
		if _rng.randf() < chance:
			_bought_witnesses.erase(npc_id)
			revive_cold_case(inv.id, TRIGGER_SILENT_WITNESS)


func _cold_trigger(trigger_id: String) -> Dictionary:
	return InvestigationEngine.find_by_id(InvestigationEngine.dig(_params,
			"cold_case_revival.triggers", []), trigger_id)


func _watched_occupation() -> String:
	return str(_cold_trigger(TRIGGER_AUDITOR).get("watched_occupation", ""))


# ─── Consulta de riesgo ───────────────────────────────────────

func get_case_weight_against(subject: String, case_id: String) -> float:
	var inv: Investigation = get_investigation(case_id)
	if inv == null:
		return 0.0
	var last: String = get_last_to_leave(int(_meta[case_id]["incident_day"]))
	return InvestigationEngine.suspect_weight(inv, subject, _flags(inv, subject, last), _bonuses())


func is_player_in_shortlist(case_id: String) -> bool:
	var inv: Investigation = get_investigation(case_id)
	return inv != null and inv.is_active() and inv.suspects.has(PLAYER)


## Registro corporal (§11.3): sospecha por encima del umbral, jugador marcado por un veredicto
## leve, o en la lista corta de una investigación abierta.
func can_search_player() -> bool:
	if _suspicion > _bal_f(B_SEARCH_THRESHOLD) or is_player_marked():
		return true
	for inv: Investigation in get_active_investigations():
		if inv.suspects.has(PLAYER):
			return true
	return false


# ─── Oyentes: tiempo y jugador ────────────────────────────────

func _on_day_advanced(day_number: int) -> void:
	process_day(day_number)


func _on_hour_passed(hour: int, _day_number: int) -> void:
	_hour = hour


## Pasar la noche dentro del edificio convierte al jugador en el último en salir.
func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	_band = new_band
	if new_band == BAND_NIGHT and _player_in_building():
		set_last_to_leave(PLAYER)


func _on_suspicion_changed(_old_value: float, new_value: float) -> void:
	_suspicion = new_value
	recalculate_alert_level()


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if not by_player:
		return
	var was_inside: bool = _player_in_building()
	_player_room = room_id
	if _band == BAND_NIGHT and was_inside and not _player_in_building():
		set_last_to_leave(PLAYER)


func _on_disguise_changed(uniform_id: String) -> void:
	_player_disguise = uniform_id


func _on_occupation_changed(_old_id: String, new_id: String, _reason: String) -> void:
	_player_occupation = new_id


## Emisión externa (p. ej. cámaras del ascensor): se guarda la grabación con su camera_id.
func _on_camera_recorded_player(camera_id: String, room_id: String, day: int) -> void:
	if not _emitting:
		_store_footage(camera_id, room_id, day, _hour)


func _on_card_reader_logged(reader_id: String, card_owner: String, day: int, hour: int) -> void:
	if not _emitting:
		_store_access(reader_id, card_owner, day, hour, "")


# ─── Oyentes: cuerpos, escondites y registros ─────────────────

func _on_body_created(body_id: String, npc_id: String, room_id: String) -> void:
	_bodies[body_id] = {"npc_id": npc_id, "room_id": room_id, "spot_id": "", "hidden": false,
			"discovered": false}


func _on_body_hidden(body_id: String, spot_id: String) -> void:
	if not _bodies.has(body_id):
		return
	_bodies[body_id]["spot_id"] = spot_id
	_bodies[body_id]["hidden"] = true
	if not _current_player_room().is_empty():
		_bodies[body_id]["room_id"] = _current_player_room()


func _on_item_hidden(item_id: String, spot_id: String) -> void:
	var stash: Dictionary = _stashes.get(spot_id, {"room_id": _current_player_room(), "items": []})
	(stash["items"] as Array).append(item_id)
	_stashes[spot_id] = stash


func _on_item_disposed(item_id: String, _method: String) -> void:
	_forget_stashed_item(item_id)


func _on_inventory_changed(item_id: String, added: bool) -> void:
	if added:
		_forget_stashed_item(item_id)


func _forget_stashed_item(item_id: String) -> void:
	for spot_id: String in _stashes.keys():
		var items: Array = _stashes[spot_id]["items"]
		if items.has(item_id):
			items.erase(item_id)
			if items.is_empty():
				_stashes.erase(spot_id)
			return


func _on_record_destroyed(record_id: String, _method: String) -> void:
	_drop_record_everywhere(record_id)


func _on_belief_decayed(belief_id: String, new_certainty: float) -> void:
	for inv: Investigation in get_active_investigations():
		var index: int = InvestigationEngine.find_piece(inv, belief_id)
		if index >= 0:
			inv.evidence[index]["certainty"] = new_certainty


func _on_belief_forgotten(belief_id: String) -> void:
	_drop_record_everywhere(belief_id)


## Un registro corporal con material comprometedor: pieza de 10,0 en cada caso activo; si el
## jugador ya está en la lista corta, el caso se cierra en su contra (veredicto inmediato).
func _on_player_searched(found_hot_items: int, _outcome: String) -> void:
	if found_hot_items <= 0:
		return
	var active: Array[Investigation] = get_active_investigations()
	if active.is_empty():
		report_incident(INCIDENT_OBJECT_MISSING, 0, _current_player_room(), true, {
			"evidence_type": InvestigationEngine.EV_ITEM, "subject": PLAYER,
			"weight": _evidence_weight(InvestigationEngine.EV_ITEM)})
		return
	for inv: Investigation in active:
		_append_piece(inv, Investigation.make_evidence(InvestigationEngine.EV_ITEM,
				_evidence_weight(InvestigationEngine.EV_ITEM), Investigation.FULL_CERTAINTY,
				PLAYER, ""), "")
		if inv.suspects.has(PLAYER) and inv.phase >= InvestigationEngine.PHASE_SHORTLIST:
			_set_phase(inv, InvestigationEngine.PHASE_VERDICT)


# ─── Oyentes: incidentes ──────────────────────────────────────

func _on_npc_reported_player(npc_id: String, _report_type: String, weight: float,
		location: String) -> void:
	var details: Dictionary = {"subject": PLAYER, "witness": npc_id,
			"evidence_type": InvestigationEngine.EV_DIRECT_WITNESS}
	if weight > 0.0:
		details["weight"] = weight
	report_incident(INCIDENT_WITNESS, 0, location, true, details)


func _on_crime_committed(crime_type: String, room_id: String, details: Dictionary) -> void:
	if crime_type == CRIME_FRAUD:
		_fraud_this_month += 1
	elif crime_type == CRIME_BODY_MOVED:
		_note_body_moved(room_id, details)
	var path: String = B_CRIME_INCIDENTS + "." + crime_type
	if Database.has_balance(path):
		report_incident(str(Database.get_balance(path)), 0, room_id, true, {})


func _note_body_moved(room_id: String, details: Dictionary) -> void:
	var body_id: String = str(details.get("body_id", ""))
	if body_id.is_empty():
		body_id = _body_id_of(str(details.get("npc_id", "")))
	if not _bodies.has(body_id):
		return
	var spot_id: String = str(details.get("spot_id", ""))
	_bodies[body_id]["room_id"] = str(details.get("room_id", room_id))
	_bodies[body_id]["spot_id"] = spot_id
	_bodies[body_id]["hidden"] = not spot_id.is_empty()


## Cuerpo hallado por otros: se suma al caso de su víctima (o lo reactiva si está frío); si no
## hay caso, abre uno de gravedad máxima.
func _on_body_discovered(body_id: String, room_id: String) -> void:
	if _emitting:
		return
	var npc_id: String = str(_bodies.get(body_id, {}).get("npc_id", ""))
	if _bodies.has(body_id):
		_bodies[body_id]["discovered"] = true
	_absences.erase(npc_id)
	var piece: Dictionary = _body_piece(body_id, room_id, "")
	for id: String in _case_order:
		var meta: Dictionary = _meta[id]
		if str(meta["body_id"]) == body_id or (not npc_id.is_empty() and meta["victim"] == npc_id):
			_append_piece(_cases[id], piece, "")
			return
	report_incident(INCIDENT_BODY_FOUND, 0, room_id, true, {"subject": PLAYER,
			"evidence_type": piece["type"], "certainty": piece["certainty"],
			"record_id": piece["record_id"], "victim": npc_id, "body_id": body_id})


func _on_npc_removed(npc_id: String, cause: String) -> void:
	for inv: Investigation in get_active_investigations():
		var holders: Dictionary = _meta[inv.id]["holders"]
		for record_id: Variant in holders.keys():
			if str(holders[record_id]) == npc_id:
				remove_evidence(inv.id, str(record_id), cause)
	if cause == CAUSE_ELIMINATED and _case_of_victim(npc_id).is_empty():
		_absences[npc_id] = _today


func _on_audit_triggered(discrepancy_found: bool) -> void:
	if discrepancy_found:
		report_incident(INCIDENT_FRAUD, 0, str(Database.get_balance(B_FRAUD_ROOM)), false,
				{"player_culprit": true})


func _on_insider_pattern_detected(_operations_count: int) -> void:
	report_incident(INCIDENT_INSIDER, 0, str(Database.get_balance(B_INSIDER_ROOM)), false,
			{"subject": PLAYER, "player_culprit": true})


## El fraude del jugador aflora en el cierre mensual (§12.3 fase 1).
func _on_month_closed(_month_number: int) -> void:
	if _fraud_this_month <= 0:
		return
	_fraud_this_month = 0
	report_incident(INCIDENT_FRAUD, 0, str(Database.get_balance(B_FRAUD_ROOM)), false,
			{"player_culprit": true})


# ─── Oyentes: sillas, agravios y sobornos ─────────────────────

func _on_seat_vacated(occupation_id: String, previous_holder: String, _cause: String) -> void:
	_vacated[occupation_id] = previous_holder


## Móvil (+1,5): quien ocupa la silla de una víctima se benefició. Auditoría: revisión de fríos.
func _on_seat_filled(occupation_id: String, new_holder: String) -> void:
	var previous: String = str(_vacated.get(occupation_id, ""))
	if not previous.is_empty():
		var case_id: String = _case_of_victim(previous)
		if not case_id.is_empty():
			register_motive(case_id, new_holder)
	if occupation_id != _watched_occupation():
		return
	_chief_auditor = new_holder
	if new_holder != PLAYER:
		_review_cold_cases()


func _on_grievance_added(npc_id: String, _grievance_type: String, severity: int) -> void:
	_check_silent_witness(npc_id, severity)


func _on_bribe_offered(npc_id: String, _amount: int, favour_type: String) -> void:
	_pending_bribes[npc_id] = favour_type


func _on_bribe_result(npc_id: String, accepted: bool, _outcome: String) -> void:
	var favour: String = str(_pending_bribes.get(npc_id, ""))
	_pending_bribes.erase(npc_id)
	if not accepted:
		return
	if favour == FAVOUR_LIE:
		bribe_witness(npc_id)
		for inv: Investigation in get_active_investigations():
			if not InvestigationEngine.pieces_against(inv, PLAYER).is_empty():
				provide_alibi(inv.id, npc_id, false)
	elif favour == FAVOUR_BURY:
		bury_investigation("", npc_id)


# ─── Utilidades ───────────────────────────────────────────────

## Getter opcional de otro autoload (BUILD_NOTES §13): si aún no existe, `fallback`.
func _ask(node: Object, method: String, fallback: Variant, args: Array = []) -> Variant:
	if node != null and node.has_method(method):
		return node.callv(method, args)
	return fallback


func _current_player_room() -> String:
	var room: String = str(_ask(PlayerState, "get_room", ""))
	return room if not room.is_empty() else _player_room


func _player_in_building() -> bool:
	var room: RoomData = Database.get_room(_current_player_room())
	return room != null and room.floor != _bal_i(B_EXTERIOR_FLOOR)


func _player_occupation_id() -> String:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation.id if occupation != null else _player_occupation


func _player_office_room() -> String:
	var occupation: OccupationData = Database.get_occupation(_player_occupation_id())
	return occupation.office_room if occupation != null else ""


## Puesto propio del jugador: su despacho; sin ocupación conocida, el escritorio de 3B.
func _is_own_workspace(room_id: String, plan_spot: String) -> bool:
	var office: String = _player_office_room()
	if office.is_empty():
		return plan_spot == InvestigationEngine.OWN_DESK_SPOT
	return InvestigationEngine.base_room(room_id) == office


func _has_access(subject: String, location: String) -> bool:
	var room: RoomData = Database.get_room(location)
	if room == null or not InvestigationEngine.is_identified(subject):
		return false
	var clearance: int = -1
	if subject == PLAYER:
		clearance = PlayerState.get_clearance()
	else:
		var npc: NPCRuntime = NPCDirector.get_npc(subject)
		var occupation: OccupationData = null if npc == null \
				else Database.get_occupation(npc.occupation_id)
		clearance = occupation.clearance if occupation != null else -1
	if clearance >= room.clearance_required:
		return true
	for entry: Dictionary in _access_log:
		if str(entry["card_owner"]) == subject and InvestigationEngine.base_room(
				str(entry["room_id"])) == InvestigationEngine.base_room(location):
			return true
	return false


func _seat_holder(occupation_id: String) -> String:
	var holder: String = Company.get_seat_holder(occupation_id)
	if holder.is_empty() and occupation_id == _watched_occupation():
		return _chief_auditor
	return holder


func _body_info(body_id: String) -> Dictionary:
	var own: Dictionary = _bodies.get(body_id, {})
	var info: Variant = _ask(NPCDirector, "get_body_info", {}, [str(own.get("npc_id", ""))])
	if info is Dictionary and not (info as Dictionary).is_empty():
		return info
	return own


func _body_of(npc_id: String) -> Dictionary:
	var body_id: String = _body_id_of(npc_id)
	if body_id.is_empty():
		return {}
	var info: Dictionary = _body_info(body_id).duplicate()
	info["body_id"] = body_id
	return info


func _body_id_of(npc_id: String) -> String:
	for body_id: String in _bodies:
		if not npc_id.is_empty() and str(_bodies[body_id]["npc_id"]) == npc_id:
			return body_id
	return ""


func _case_of_victim(npc_id: String) -> String:
	for id: String in _case_order:
		if not npc_id.is_empty() and str(_meta[id]["victim"]) == npc_id:
			return id
	return ""


## Escondites del jugador: los de PlayerState si expone get_stashes(); si no, los observados.
## Formato {spot_id: {room_id, items: [item_id | {id, ...}]}}.
func _current_stashes() -> Dictionary:
	var theirs: Variant = _ask(PlayerState, "get_stashes", {})
	if theirs is Dictionary and not (theirs as Dictionary).is_empty():
		return theirs
	return _stashes


func _is_hot(item_id: String) -> bool:
	if not Database.has_item(item_id):
		return true
	return Database.get_item(item_id).is_compromising()


func _evidence_weight(evidence_type: String) -> float:
	var entry: Dictionary = InvestigationEngine.find_by_id(_params.get("evidence_types", []),
			evidence_type)
	var path: String = str(entry.get("balance_path", ""))
	if not path.is_empty() and Database.has_balance(path):
		return Database.get_balance_float(path)
	return float(entry.get("weight", 0.0))


func _witness_weights() -> Dictionary:
	var out: Dictionary = {}
	for kind: String in [InvestigationEngine.EV_DIRECT_WITNESS,
			InvestigationEngine.EV_PARTIAL_WITNESS, InvestigationEngine.EV_RUMOUR]:
		out[kind] = _evidence_weight(kind)
	return out


func _index_of(entries: Array[Dictionary], id: String) -> int:
	for i: int in entries.size():
		if str(entries[i].get("id", "")) == id:
			return i
	return -1


static func _append_unique(list: Array, value: String) -> void:
	if not list.has(value):
		list.append(value)


func _bal_f(path: String) -> float:
	return Database.get_balance_float(path)


func _bal_i(path: String) -> int:
	return Database.get_balance_int(path)


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	var cases: Array[Dictionary] = []
	for id: String in _case_order:
		cases.append((_cases[id] as Investigation).to_dict())
	return {
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state), "today": _today, "hour": _hour,
		"band": _band, "alert_level": _alert_level, "suspicion": _suspicion, "counter": _counter,
		"incident_days": _incident_days.duplicate(), "footage": _footage.duplicate(true),
		"access_log": _access_log.duplicate(true), "cases": cases, "meta": _meta.duplicate(true),
		"has_case_history": _has_case_history, "last_case_day": _last_case_day,
		"deferred": _deferred.duplicate(true), "pending": _pending.duplicate(true),
		"last_out": _last_out.duplicate(), "bodies": _bodies.duplicate(true),
		"absences": _absences.duplicate(), "stashes": _stashes.duplicate(true),
		"confiscated": _confiscated.duplicate(), "found_items": _found_items.duplicate(true),
		"bought_witnesses": _bought_witnesses.duplicate(),
		"pending_bribes": _pending_bribes.duplicate(), "vacated": _vacated.duplicate(),
		"fraud_this_month": _fraud_this_month, "marked_until": _marked_until,
		"player_room": _player_room, "player_disguise": _player_disguise,
		"player_occupation": _player_occupation, "chief_auditor": _chief_auditor,
	}


func load_state(data: Dictionary) -> void:
	_clear_state()
	_params = Database.get_investigation_params()
	## Semilla y estado como texto: un int de 64 bits no sobrevive a JSON como número.
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()
	_load_scalars(data)
	_load_records(data)
	_load_cases(data)
	_load_indexes(data)


func _load_scalars(data: Dictionary) -> void:
	_today = int(data.get("today", 0))
	_hour = int(data.get("hour", 0))
	_band = str(data.get("band", ""))
	_alert_level = int(data.get("alert_level", 0))
	_suspicion = float(data.get("suspicion", 0.0))
	_counter = int(data.get("counter", 0))
	_has_case_history = bool(data.get("has_case_history", false))
	_last_case_day = int(data.get("last_case_day", 0))
	_fraud_this_month = int(data.get("fraud_this_month", 0))
	_marked_until = int(data.get("marked_until", 0))
	_player_room = str(data.get("player_room", ""))
	_player_disguise = str(data.get("player_disguise", ""))
	_player_occupation = str(data.get("player_occupation", ""))
	_chief_auditor = str(data.get("chief_auditor", ""))


func _load_records(data: Dictionary) -> void:
	for day: Variant in data.get("incident_days", []):
		_incident_days.append(int(day))
	_footage.assign(_int_fields(data.get("footage", []), ["day", "hour"]))
	_access_log.assign(_int_fields(data.get("access_log", []), ["day", "hour"]))
	_deferred.assign(_int_fields(data.get("deferred", []), ["severity", "day", "hour"]))
	_pending.assign(_int_fields(data.get("pending", []), ["severity", "day", "hour"]))
	_found_items.assign(_int_fields(data.get("found_items", []), ["day"]))
	for value: Variant in data.get("confiscated", []):
		_confiscated.append(str(value))
	for value: Variant in data.get("bought_witnesses", []):
		_bought_witnesses.append(str(value))


func _load_cases(data: Dictionary) -> void:
	var raw_meta: Dictionary = data.get("meta", {})
	for entry: Variant in data.get("cases", []):
		if not (entry is Dictionary):
			continue
		var inv: Investigation = Investigation.from_dict(entry, "save/security")
		_cases[inv.id] = inv
		_case_order.append(inv.id)
		var meta: Dictionary = _new_meta({"day": inv.opened_day, "hour": -1,
				"player_caused": false, "player_culprit": false, "victim": "", "body_id": ""})
		meta.merge((raw_meta.get(inv.id, {}) as Dictionary).duplicate(true), true)
		_meta[inv.id] = meta


func _load_indexes(data: Dictionary) -> void:
	_last_out = (data.get("last_out", {}) as Dictionary).duplicate()
	_bodies = (data.get("bodies", {}) as Dictionary).duplicate(true)
	_stashes = (data.get("stashes", {}) as Dictionary).duplicate(true)
	_pending_bribes = (data.get("pending_bribes", {}) as Dictionary).duplicate()
	_vacated = (data.get("vacated", {}) as Dictionary).duplicate()
	var absences: Dictionary = data.get("absences", {})
	for npc_id: Variant in absences:
		_absences[str(npc_id)] = int(absences[npc_id])


## Copia de una lista de diccionarios devolviendo a int los campos indicados (JSON → float).
static func _int_fields(raw: Variant, keys: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for entry: Variant in raw:
		if entry is Dictionary:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			for key: String in keys:
				if copy.has(key):
					copy[key] = int(copy[key])
			out.append(copy)
	return out
