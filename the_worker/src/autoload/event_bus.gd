# event_bus.gd — Tablón central de comunicación entre sistemas.
# PROPIETARIO DE: nada. Únicamente declara y distribuye señales.
# ESCUCHA: nada.
class_name EventBusNode
extends Node

## Catálogo completo de la sección 18.2 del manual. Toda señal va en tiempo pasado (§18.3).
## Añadir una señal solo si el catálogo carece de ella de verdad: al final de su sección,
## con un comentario `# EXT:` (BUILD_NOTES §2).

@warning_ignore_start("unused_signal")

# ─── PERCEPCIÓN Y SIGILO ───────────────────────────────────────
signal player_seen_partially(npc_id: String, certainty: float, location: String)
signal player_caught_redhanded(npc_id: String, crime_type: String, witnesses: int)
signal player_lost_from_sight(npc_id: String)
signal noise_emitted(position: Vector2, radius: float, source: String)
signal camera_recorded_player(camera_id: String, room_id: String, day: int)
signal card_reader_logged(reader_id: String, card_owner: String, day: int, hour: int)

# ─── CREENCIAS Y SOCIAL ────────────────────────────────────────
signal belief_created(belief_id: String, holder: String, subject: String, certainty: float)
signal belief_decayed(belief_id: String, new_certainty: float)
signal belief_forgotten(belief_id: String)
signal record_created(record_id: String, record_type: String, weight: float)
signal record_destroyed(record_id: String, method: String)
signal rumor_spread(from_npc: String, to_npc: String, belief_id: String)
signal suspicion_changed(old_value: float, new_value: float)
signal reputation_changed(old_value: float, new_value: float)

# ─── SOBORNOS Y RELACIONES ─────────────────────────────────────
signal bribe_offered(npc_id: String, amount: int, favour_type: String)
signal bribe_result(npc_id: String, accepted: bool, outcome: String)
signal grievance_added(npc_id: String, grievance_type: String, severity: int)
signal favour_added(npc_id: String, favour_type: String, magnitude: int)
signal blackmail_initiated(npc_id: String, target: String, leverage: String)

# ─── IDEAS Y TRABAJO ───────────────────────────────────────────
signal idea_generated(idea_id: String, owner: String, quality: int, department: String)
signal idea_acquired(idea_id: String, method: String)
signal idea_expired(idea_id: String)
signal idea_presented(idea_id: String, presenter: String, merit_gained: int)
signal idea_contested(idea_id: String, accuser: String, result: String)
signal duty_assigned(duty_id: String, duty_type: String, deadline_hour: int)
signal duty_completed(duty_id: String, quality: float, method: String)
signal duty_failed(duty_id: String, consequence: String)
signal assist_used(task_type: String, result_quality: String)

# ─── PROGRESIÓN ────────────────────────────────────────────────
signal occupation_changed(old_id: String, new_id: String, reason: String)
signal seat_vacated(occupation_id: String, previous_holder: String, cause: String)
signal seat_filled(occupation_id: String, new_holder: String)
signal promotion_available(occupation_ids: Array)
signal promotion_declined(occupation_id: String)
signal merit_gained(source: String, amount: int)
signal clearance_changed(old_level: int, new_level: int)

# ─── SEGURIDAD E INVESTIGACIÓN ─────────────────────────────────
signal alert_level_changed(old_level: int, new_level: int)
signal investigation_opened(case_id: String, incident_type: String, severity: int)
signal investigation_phase_advanced(case_id: String, new_phase: int)
signal evidence_added(case_id: String, evidence_type: String, weight: float, points_to: String)
signal suspect_list_formed(case_id: String, suspects: Array)
signal interrogation_started(case_id: String, interrogator: String)
signal investigation_resolved(case_id: String, verdict: String, culprit: String)
signal case_went_cold(case_id: String)
signal case_revived(case_id: String, trigger: String)
signal body_discovered(body_id: String, room_id: String)
signal police_dispatched(target_location: String, response_time: float)

# ─── ECONOMÍA Y NOTICIAS ───────────────────────────────────────
signal news_published(headline_id: String, sentiment_delta: float, is_scandal: bool)
signal news_buried(headline_id: String, by_whom: String)
signal fundamentals_updated(revenue: float, costs: float, risk: float)
signal quarter_reported(real_figures: Dictionary, reported_figures: Dictionary)
signal audit_fuse_lit(discrepancy: float, weeks_until_check: int)
signal audit_triggered(discrepancy_found: bool)
signal stock_price_updated(price: float, delta_percent: float)
signal investor_confidence_changed(investor_id: String, old_value: int, new_value: int)
signal insider_pattern_detected(operations_count: int)

# ─── MUNDO Y TIEMPO ────────────────────────────────────────────
signal day_advanced(day_number: int)
signal time_band_changed(old_band: String, new_band: String)
signal week_closed(week_number: int)
signal month_closed(month_number: int)
signal quarter_closed(quarter_number: int)
signal room_entered(room_id: String, by_player: bool)
signal room_exited(room_id: String, by_player: bool)
signal floor_changed(old_floor: int, new_floor: int)
signal strike_discontent_changed(old_value: int, new_value: int)
signal strike_started()
signal strike_resolved(resolution: String)

# ─── FIN DE PARTIDA ────────────────────────────────────────────
signal ownership_documents_obtained()
signal ownership_notarised()
signal game_over(cause: String, ending_id: String, tracking_snapshot: Dictionary)

@warning_ignore_restore("unused_signal")

# ─── DEPURACIÓN (§18.4) ────────────────────────────────────────
const DEBUG_SIGNALS := false


func _ready() -> void:
	if not DEBUG_SIGNALS:
		return
	for info: Dictionary in get_script().get_script_signal_list():
		var signal_name: String = info["name"]
		connect(signal_name, func(...args: Array) -> void: _log(signal_name, args))


func _log(signal_name: String, args: Array) -> void:
	if DEBUG_SIGNALS:
		print("[BUS] %s → %s" % [signal_name, str(args)])
