# investigation_case.gd — Cuerpo de test_investigation (§21, PASO 28): las cinco fases con y sin interferencia, un cuerpo mal oculto aflora en la fase 2 (en otra sala que la del incidente), regla de respiro, umbrales de veredicto y las vías de señales reales (denuncias, delitos, fraude, auditoría, insider, último en salir, móvil).
# PROPIETARIO DE: nada.
# ESCUCHA: señales de investigación de EventBus, body_discovered y npc_reported_player (vía SignalLog).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")
const BriberyFx := preload("res://tests/cases/bribery_fixtures.gd")
const WATCHED: Array[String] = ["investigation_opened", "investigation_phase_advanced",
		"evidence_added", "suspect_list_formed", "interrogation_started", "investigation_resolved",
		"case_went_cold", "game_over", "body_discovered", "npc_reported_player"]

var _log: Fx.SignalLog
var _phase_at_discovery: Dictionary = {}
var _watched_case: String = ""


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	_test_trigger_table()
	_test_opening_threshold()
	_test_rest_rule()
	_test_witnesses_from_belief_graph()
	_test_rumour_about_another_npc()
	_test_five_phases_without_interference()
	_test_five_phases_with_interference()
	_test_footage_review_zones()
	_test_framing_convicts_another()
	_test_badly_hidden_body_surfaces_in_phase_2()
	_test_hidden_items_found_by_search()
	_test_stash_in_other_room_seeded()
	_test_body_search_closes_case()
	_test_pure_rules()
	_test_verdict_thresholds()
	_test_minor_verdict_marks_player()
	_test_report_payloads()
	_test_crime_signal_paths()
	_test_fraud_surfaces_at_month_close()
	_test_audit_and_insider_signals()
	_test_last_to_leave_signals()
	_test_motive_from_seat_change()
	_test_populated_body_case()
	_log.stop()


func _fresh(run_seed: int = DEFAULT_SEED, populated: bool = false) -> void:
	if _log != null:
		_log.stop()
	new_run(run_seed, populated)
	_log = Fx.SignalLog.new().watch(WATCHED)


func _test_trigger_table() -> void:
	var triggers: Array = Database.get_investigation_params()["incident_triggers"]
	var expected: Dictionary = {"object_missing": 2.5, "inventory_mismatch": 2.0,
			"body_found": 12.0, "fraud_at_month_close": 4.0, "direct_witness_report": 4.0,
			"insider_pattern": 6.0}
	for id: String in expected:
		var trigger: Dictionary = InvestigationEngine.find_by_id(triggers, id)
		check_near(float(trigger.get("initial_weight", -1.0)), expected[id], 0.0001,
				"§12.3 trigger weight %s = %s" % [id, expected[id]])
	var base: float = Fx.bal("investigaciones.umbral_apertura")
	var mod: float = Fx.bal("investigaciones.mod_umbral_por_sospecha")
	check_near(base, 3.0, 0.0001, "opening threshold 3.0")
	check_near(InvestigationEngine.modulated_threshold(base, mod, 80.0), 0.6, 0.0001,
			"§12.4: suspicion 80 lowers the opening threshold to 0.6")


func _test_opening_threshold() -> void:
	_fresh()
	check_eq(Security.report_incident("object_missing", 0, "hr_office", true), "",
			"object missing (2.5) alone stays below 3.0: no case")
	check_eq(Security.report_incident("power_cut", 0, "electrical_room", true, {"weight": 3.0})
			.is_empty(), false, "a power cut always opens a case (§22: automatic investigation)")
	check_eq(Security.report_incident("inventory_mismatch", 0, "boiler_room", true,
			{"weight": 3.0}), "", "§12.3 «supera»: exactly 3.0 does not open")
	var case_id: String = Security.report_incident("object_missing", 0, "hr_office", true)
	check(not case_id.is_empty(), "a second theft in the same room adds up (5.0) and opens a case")
	check_eq(Fx.piece_types(case_id), ["object_missing", "object_missing"] as Array[String],
			"both incidents are pieces of the case")
	var opened: Array = _log.of("investigation_opened")[1]
	check(opened == [case_id, "object_missing", 2], "investigation_opened(case, type, default severity 2)")
	check_eq(Security.get_investigation(case_id).phase, InvestigationEngine.PHASE_COLLECTION,
			"phase 1 (incident) moves straight to phase 2")
	Fx.set_suspicion(80.0)
	var mismatch: String = Security.report_incident("inventory_mismatch", 0, "general_warehouse", true)
	check(not mismatch.is_empty(), "with suspicion 80 an inventory mismatch (2.0) opens a case")
	Fx.set_suspicion(0.0)


func _test_rest_rule() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	var first: String = Security.open_investigation("direct_witness_report", 0, "hr_office")
	check(not first.is_empty(), "first investigation opens")
	check_eq(Security.open_investigation("power_cut", 0, "electrical_room"), "",
			"a second one the same day is held back (3-day rest rule)")
	check_eq(Security.get_deferred_incident_count(), 1, "the incident waits, it is not lost")
	var rest: int = Database.get_balance_int("investigaciones.jornadas_respiro_minimo")
	check_eq(rest, 3, "rest interval is 3 days (§15.3)")
	Fx.advance_days(rest - 1)
	check_eq(Security.get_active_investigations().size(), 1, "still one active case after 2 days")
	Fx.advance_days(1)
	var active: Array[Investigation] = Security.get_active_investigations()
	check_eq(active.size(), 2, "the deferred case opens once 3 days have passed")
	check_eq(active[1].opened_day, d0 + rest, "opened exactly on day +3")
	var provoked: String = Security.report_incident("power_cut", 0, "boiler_room", true)
	check(not provoked.is_empty(), "a player-provoked incident is exempt from the rest rule")
	check_eq(Security.open_investigation("power_cut", 0, "server_room"), "",
			"an unprovoked one right after is held back again")


## Procedimiento 1: el investigador consulta el grafo de creencias (vía señales de percepción).
func _test_witnesses_from_belief_graph() -> void:
	_fresh()
	Fx.enter_room(Fx.OPEN_ROOM)
	EventBus.player_caught_redhanded.emit("npc_seer", "theft_small", 1)
	EventBus.player_seen_partially.emit("npc_seer", 0.35, Fx.OPEN_ROOM)
	EventBus.player_seen_partially.emit("npc_glimpse", 0.35, Fx.OPEN_ROOM)
	EventBus.player_seen_partially.emit("npc_elsewhere", 0.35, "cafeteria")
	var beliefs: Dictionary = {}
	for b: Belief in BeliefNet.get_beliefs_about(Fx.PLAYER):
		if b.fact.begins_with("caught_redhanded") or b.holder == "npc_glimpse":
			beliefs[b.holder] = b
	check(beliefs.size() == 2, "BeliefNet holds the witnesses' beliefs")
	var case_id: String = Security.report_incident("object_missing", 1, Fx.OPEN_ROOM, true,
			{"weight": 3.0, "always_opens": true})
	Fx.advance_days(1)
	var by_holder: Dictionary = {}
	for piece: Dictionary in Security.get_investigation(case_id).evidence:
		if piece["type"] in ["direct_witness", "partial_witness"]:
			by_holder[piece["record_id"]] = piece
	check_eq(by_holder.size(), 2, "one piece per witness in the room; the cafeteria one ignored")
	var seer: Belief = beliefs.get("npc_seer")
	var direct: Dictionary = by_holder.get(seer.id if seer != null else "", {})
	check(not direct.is_empty() and direct["type"] == "direct_witness"
			and is_equal_approx(float(direct["weight"]), 4.0)
			and is_equal_approx(float(direct["certainty"]), seer.certainty),
			"caught red-handed → direct witness 4.0 × the belief's certainty (strongest kept)")
	var glimpse: Belief = beliefs.get("npc_glimpse")
	var partial: Dictionary = by_holder.get(glimpse.id if glimpse != null else "", {})
	check(not partial.is_empty() and partial["type"] == "partial_witness"
			and is_equal_approx(float(partial["weight"]), 0.8), "seen partially → partial witness 0.8")
	var rumour: Belief = Belief.make("r1", "npc_gossip", Fx.PLAYER, "seen_partially", 0.5,
			Belief.SOURCE_RUMOR, Fx.OPEN_ROOM, 0)
	var weights: Dictionary = {"direct_witness": 4.0, "partial_witness": 0.8,
			"unsourced_rumour": 0.3}
	var piece: Dictionary = InvestigationEngine.piece_from_belief(rumour, weights, 0.6)
	check(piece["type"] == "unsourced_rumour" and is_equal_approx(piece["weight"], 0.3),
			"a rumour is an unsourced rumour (0.3)")


## Testigo (4,0) + grabación (4,5) + acceso (2,0) + último en salir (3,5) = 14,0 → grave.
func _test_five_phases_without_interference() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	Security.set_last_to_leave(Fx.PLAYER)
	Security.register_camera_footage(Fx.OPEN_ROOM, d0, 11)
	Security.register_camera_footage(Fx.OPEN_ROOM, d0, 16)
	Security.register_camera_footage("turnstiles", d0, 10)
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 3)
	var inv: Investigation = Security.get_investigation(case_id)
	check_eq(inv.severity, 3, "severity 3")
	Fx.advance_days(3)
	check(not Fx.piece_types(case_id).has("camera_footage"), "footage not reviewed before day 4")
	Fx.advance_days(1)
	check_eq(Fx.piece_types(case_id).count("camera_footage"), 1,
			"day 4: only the footage of the incident room within ±2 h is collected")
	Fx.advance_days(1)
	check_eq(inv.phase, InvestigationEngine.PHASE_COLLECTION, "phase 2 lasts 6 days at severity 3")
	Fx.advance_days(1)
	check_eq(inv.phase, InvestigationEngine.PHASE_SHORTLIST, "day 6: phase 3")
	check(_log.last("suspect_list_formed") == [case_id, [Fx.PLAYER]], "suspect_list_formed([player])")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 14.0, 0.001,
			"weight = 4.0 witness + 4.5 footage + 2.0 access + 3.5 last to leave")
	Fx.advance_days(1)
	check_eq(inv.phase, InvestigationEngine.PHASE_INTERROGATION, "player tops the list: phase 4")
	var started: Array = _log.last("interrogation_started")
	check(started.size() == 2 and started[0] == case_id and not str(started[1]).is_empty(),
			"interrogation_started(case, interrogator)")
	Fx.advance_days(1)
	_check_phase_sequence(case_id, [2, 3, 4, 5])
	check(_log.last("investigation_resolved") == [case_id, "player_major", Fx.PLAYER],
			"verdict: player guilty, serious (> 10.0)")
	_check_game_over(case_id)


func _check_phase_sequence(case_id: String, expected: Array) -> void:
	var seen: Array = []
	for args: Array in _log.of("investigation_phase_advanced"):
		if args[0] == case_id:
			seen.append(args[1])
	check_eq(seen, expected, "the case walks the phases %s" % str(expected))


func _check_game_over(case_id: String) -> void:
	var over: Array = _log.last("game_over")
	var verdict: Dictionary = InvestigationEngine.find_by_id(
			Database.get_investigation_params()["verdicts"], "player_guilty_major")
	check(over.size() == 3 and over[0] == verdict["game_over_cause"]
			and over[1] == verdict["ending_id"], "game_over(investigation_conclusive, the_file)")
	var snapshot: Dictionary = over[2] if over.size() == 3 else {}
	var report: Dictionary = snapshot.get("case_report", {})
	check(snapshot.get("case_id") == case_id and int(report.get("evidence_count", 0)) == 2,
			"the snapshot carries the case file with its evidence for the epilogue")


## Mismo caso, pero el jugador soborna al testigo y borra la grabación antes de la revisión.
func _test_five_phases_with_interference() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	Security.set_last_to_leave(Fx.PLAYER)
	var footage: String = Security.register_camera_footage(Fx.OPEN_ROOM, d0, 10)
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 3)
	check_eq(Security.bribe_witness(Fx.WITNESS), 1, "bribed witness withdraws the testimony")
	Fx.enter_room("monitor_room")
	check(Security.delete_footage(footage), "footage deleted before the review")
	Fx.advance_days(6)
	check(Security.get_investigation(case_id).evidence.is_empty(), "no evidence left in the file")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 5.5, 0.001,
			"only access (2.0) + last to leave (3.5) remain")
	Fx.advance_days(2)
	_check_phase_sequence(case_id, [2, 3, 4, 5])
	check(_log.last("investigation_resolved") == [case_id, "cold", ""], "max weight < 7.0 → cold")
	check(_log.last("case_went_cold") == [case_id], "case_went_cold emitted")
	check_eq(_log.count("game_over"), 0, "no game over")
	check_eq(Security.get_cold_cases().size(), 1, "the case is cold, not closed")


func _test_framing_convicts_another() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	Security.register_camera_footage(Fx.OPEN_ROOM, d0, 10)
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 1)
	check(Security.plant_evidence(case_id, Fx.SCAPEGOAT, "compromising_item"),
			"planting an object in someone's locker adds evidence against them")
	Security.set_last_to_leave(Fx.SCAPEGOAT, d0)
	Fx.advance_days(2)
	var inv: Investigation = Security.get_investigation(case_id)
	check_eq(inv.suspects, [Fx.SCAPEGOAT, Fx.PLAYER] as Array[String],
			"shortlist ordered by weight: the scapegoat (10.0 + 3.5) above the player (10.5)")
	Fx.advance_days(1)
	check(_log.last("investigation_resolved") == [case_id, "other_guilty", Fx.SCAPEGOAT],
			"verdict: another employee guilty (> 7.0) — NPCDirector expels them")
	var report: Dictionary = Security.get_case_report(case_id)
	check(bool(report["culprit_innocent"]) and (report["scapegoats"] as Array).has(Fx.SCAPEGOAT),
			"the report knows the culprit was innocent (grievance for NPCDirector)")


## Víctima A eliminada en hr_office y arrastrada sin ocultar al almacén general: el caso se abre
## donde se la echa en falta (hr_office, sin datos de población: la sala de la eliminación), no
## donde está el cuerpo; el registro de salas lo encuentra en OTRA sala en la fase 2.
func _test_badly_hidden_body_surfaces_in_phase_2() -> void:
	_fresh()
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.npc_removed.emit("npc_victim_a", "eliminated")
	EventBus.body_created.emit("body_a", "npc_victim_a", "hr_office")
	EventBus.crime_committed.emit("body_moved", "general_warehouse",
			{"body_id": "body_a", "room_id": "general_warehouse", "spot_id": ""})
	EventBus.npc_removed.emit("npc_victim_b", "elimination")
	EventBus.body_created.emit("body_b", "npc_victim_b", "forgotten_corridor")
	Fx.enter_room("forgotten_corridor")
	EventBus.body_hidden.emit("body_b", "hide_forgotten_alcove")
	check(Security.get_active_investigations().is_empty(), "absence not noticed the same day")
	Fx.advance_days(1)
	var cases: Array[Investigation] = Security.get_active_investigations()
	check_eq(cases.size(), 2, "next day both absences open a case (\"elimination\" alias too)")
	var case_a: Investigation = _case_at(cases, "hr_office")
	var case_b: Investigation = _case_at(cases, "forgotten_corridor")
	check(case_a != null and case_a.incident_type == "missing_person" and case_a.severity == 5,
			"maximum severity missing-person case where the victim was last seen, not at the body")
	_watched_case = case_a.id if case_a != null else ""
	Fx.advance_days(9)
	check_eq(_log.count("body_discovered"), 0, "the search has not reached the room yet (day 9)")
	Fx.advance_days(1)
	check(_log.of("body_discovered").has(["body_a", "general_warehouse"]),
			"the badly hidden body surfaces in the room search, in another room")
	check_eq(_phase_at_discovery.get("body_a", -1), InvestigationEngine.PHASE_COLLECTION,
			"it surfaces during phase 2")
	var piece: Dictionary = Fx.piece_of_type(case_a.id, "body_found")
	check(not piece.is_empty() and is_equal_approx(float(piece["weight"]), 12.0)
			and piece["points_to"] == Fx.PLAYER, "body found: 12.0 piece in the case file")
	check_near(float(piece.get("certainty", 0.0)), Fx.bal("seguridad.certeza_cuerpo_hallado"),
			0.0001, "the forensic chain points to the player with partial certainty")
	check(not _log.of("body_discovered").has(["body_b", "forgotten_corridor"]),
			"a body in forgotten_corridor is never found")
	check(not case_b.searched_rooms.has("forgotten_corridor"), "forgotten_corridor never searched")
	check(case_a.searched_rooms.has("dead_archive") and not case_a.searched_rooms.has("trash_dock"),
			"the search covers the basements at severity 5, never the trash dock")
	EventBus.body_discovered.disconnect(_on_body_discovered)


func _on_body_discovered(body_id: String, _room_id: String) -> void:
	var inv: Investigation = Security.get_investigation(_watched_case)
	_phase_at_discovery[body_id] = inv.phase if inv != null else -1


func _case_at(cases: Array[Investigation], location: String) -> Investigation:
	for inv: Investigation in cases:
		if inv.location == location:
			return inv
	return null


func _test_hidden_items_found_by_search() -> void:
	_fresh()
	Fx.enter_room("wing_3b")
	var hidden: int = 40
	for i: int in hidden:
		EventBus.item_hidden.emit("product_box", "hide_3b_spot_%d" % i)
	EventBus.item_hidden.emit("paper", "hide_3b_paper")
	var case_id: String = Security.report_incident("object_missing", 1, "wing_3b", true,
			{"weight": 3.0, "always_opens": true})
	Fx.advance_days(2)
	var found: Array[Dictionary] = []
	for piece: Dictionary in Security.get_investigation(case_id).evidence:
		if piece["type"] == "compromising_item":
			found.append(piece)
	check(found.size() >= 30 and found.size() <= hidden,
			"own desk searched first with find chance 0.95: %d of 40 found" % found.size())
	var all_ok: bool = true
	for piece: Dictionary in found:
		all_ok = all_ok and is_equal_approx(float(piece["weight"]), 10.0) \
				and piece["points_to"] == Fx.PLAYER and is_equal_approx(float(piece["certainty"]), 1.0)
	check(all_ok, "each hidden item in the player's desk is a 10.0 piece against the player")
	check_eq(Security.get_found_items().size(), found.size(), "found items reported for PlayerState")
	check(not str(Security.get_found_items()).contains("paper"), "ordinary items are not evidence")


## Una tanda de objetos calientes escondidos en los vestuarios de limpieza (no es la sala del
## incidente): cada uno aflora con la probabilidad del orden de registro (0,7) según la RNG de la
## partida: misma semilla → mismos hallazgos; otra semilla → otros.
func _test_stash_in_other_room_seeded() -> void:
	var first: Array[String] = _locker_finds(DEFAULT_SEED)
	var again: Array[String] = _locker_finds(DEFAULT_SEED)
	var other: Array[String] = _locker_finds(DEFAULT_SEED + 1)
	check(first.size() >= 12 and first.size() <= 29,
			"%d of 30 stashed items found in cleaning_locker_room (find chance 0.7)" % first.size())
	check_eq(again, first, "same run seed → exactly the same items found")
	check(other != first, "another run seed → a different search outcome")


func _locker_finds(run_seed: int) -> Array[String]:
	_fresh(run_seed)
	Fx.enter_room("cleaning_locker_room")
	for i: int in 30:
		EventBus.item_hidden.emit("product_box", "hide_locker_%d" % i)
	var case_id: String = Security.report_incident("object_missing", 2, "hr_office", true,
			{"weight": 3.0, "always_opens": true})
	Fx.advance_days(4)
	var inv: Investigation = Security.get_investigation(case_id)
	check(inv.searched_rooms[0] == "hr_office" and inv.searched_rooms.has("cleaning_locker_room"),
			"the search starts in the incident room and reaches the locker room (severity 2)")
	var found: Array[String] = []
	for piece: Dictionary in inv.evidence:
		if piece["type"] == "compromising_item":
			found.append(str(piece["record_id"]))
	return found


## §11.3: «evidencia definitiva de peso 10. El caso se cierra en contra del jugador».
func _test_body_search_closes_case() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 1)
	var unrelated: String = Security.report_incident("object_missing", 2, "hr_office", true,
			{"weight": 3.5})
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_SHORTLIST)
	check(Security.is_player_in_shortlist(case_id), "player shortlisted")
	EventBus.player_searched.emit(1, "found")
	check(_log.last("investigation_resolved") == [case_id, "player_major", Fx.PLAYER],
			"compromising item found on the player (10.0) closes the case against them")
	check(not Fx.piece_types(unrelated).has("compromising_item")
			and Security.get_investigation(unrelated).is_active(),
			"the unrelated open case does not receive the piece")
	_fresh()
	Fx.enter_room(Fx.SEALED_ROOM)
	var other: String = Security.report_incident("object_missing", 2, "hr_office", true,
			{"weight": 3.5})
	EventBus.player_searched.emit(2, "found")
	var opened: Array = _log.last("investigation_opened")
	var new_case: String = str(opened[0]) if opened.size() == 3 else ""
	check(new_case != other and Fx.piece_types(new_case).has("compromising_item"),
			"with no case shortlisting the player, the search opens its own case with the 10.0 piece")
	check(_log.last("investigation_resolved") == [new_case, "player_minor", Fx.PLAYER],
			"and it goes straight to the verdict (10.0, no access to the room → minor)")
	check(not Fx.piece_types(other).has("compromising_item"), "other cases do not get the piece")


func _test_pure_rules() -> void:
	var inv: Investigation = Investigation.new()
	inv.id = "pure"
	inv.add_evidence("direct_witness", 4.0, 0.5, Fx.PLAYER, "a")
	inv.add_evidence("camera_footage", 4.5, 1.0, Fx.PLAYER, "b")
	inv.add_evidence("card_log", 2.5, 1.0, "npc_x", "c")
	var bonuses: Dictionary = {"access": 2.0, "motive": 1.5, "last_to_leave": 3.5}
	var flags: Dictionary = {"access": true, "motive": true, "last_to_leave": true}
	check_near(InvestigationEngine.suspect_weight(inv, Fx.PLAYER, flags, bonuses), 13.5, 0.0001,
			"Σ(weight × certainty) 2.0 + 4.5 + 2.0 access + 1.5 motive + 3.5 last = 13.5")
	check_near(InvestigationEngine.suspect_weight(inv, "npc_x", {}, bonuses), 2.5, 0.0001,
			"no bonuses → only the pieces")
	var weights: Dictionary = {"a": 9.0, "b": 8.0, "c": 7.0, "d": 6.0, Fx.PLAYER: 2.7}
	check_eq(InvestigationEngine.form_shortlist(weights, 2.6, 5.0, 3), ["a", "b", "c"] as Array[String],
			"shortlist keeps at most 3 suspects, by weight")
	check_eq(InvestigationEngine.form_shortlist({"a": 4.0, Fx.PLAYER: 2.7}, 2.6, 5.0, 3),
			[Fx.PLAYER] as Array[String], "the player's threshold is lowered by suspicion")
	var tie: Dictionary = {"npc_a": 6.0, Fx.PLAYER: 6.0}
	check_eq(InvestigationEngine.rank(tie, [Fx.PLAYER, "npc_a"] as Array[String]),
			[Fx.PLAYER, "npc_a"] as Array[String], "tie → whoever the file pointed at first")
	check_eq(InvestigationEngine.rank(tie, ["npc_a", Fx.PLAYER] as Array[String]),
			["npc_a", Fx.PLAYER] as Array[String], "tie-break follows the file, not the alphabet")
	var table: Dictionary = InvestigationEngine.dig(Database.get_investigation_params(),
			"phase_durations.evidence_collection_by_severity", {})
	var days: Array[int] = []
	for severity: int in range(1, 6):
		days.append(InvestigationEngine.collection_days(severity, table, 2, 10))
	check_eq(days, [2, 4, 6, 8, 10] as Array[int], "phase 2 lasts 2-10 days by severity")
	check_eq([InvestigationEngine.procedure_due_day(0, 3, 10),
			InvestigationEngine.procedure_due_day(1, 3, 10),
			InvestigationEngine.procedure_due_day(2, 3, 10)], [4, 7, 10],
			"the three procedures are spread over the collection, the search last")
	_test_search_plan()


func _test_search_plan() -> void:
	var room_search: Dictionary = Database.get_investigation_params()["room_search"]
	var low: Array[String] = InvestigationEngine.plan_rooms(
			InvestigationEngine.search_plan("hr_office", 1, room_search, 0.8))
	check(low[0] == "hr_office" and low[1] == "wing_3b" and not low.has("dead_archive"),
			"incident room first, then the player's desk; no basements at severity 1")
	var high: Array[String] = InvestigationEngine.plan_rooms(
			InvestigationEngine.search_plan("forgotten_corridor", 5, room_search, 0.8))
	check(high.has("dead_archive") and not high.has("forgotten_corridor")
			and not high.has("trash_dock"), "severity 5 searches basements, never the corridor")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var plan: Array[Dictionary] = [{"room": "x", "spot": "", "find_chance": 0.0}]
	var targets: Array[Dictionary] = [
		{"kind": "body", "id": "open", "room_id": "x", "hidden": false},
		{"kind": "item", "id": "hidden", "room_id": "x", "hidden": true}]
	var hits: Array[Dictionary] = InvestigationEngine.run_search(plan, targets, rng)
	check(hits.size() == 1 and hits[0]["id"] == "open", "badly hidden: always found; hidden: chance")
	plan[0]["find_chance"] = 1.0
	check_eq(InvestigationEngine.run_search(plan, targets, rng).size(), 2, "certain search finds both")


func _test_verdict_thresholds() -> void:
	var minor: float = Fx.bal("investigaciones.umbral_condena_leve")
	var major: float = Fx.bal("investigaciones.umbral_condena_grave")
	check(is_equal_approx(minor, 7.0) and is_equal_approx(major, 10.0), "verdict thresholds 7 / 10")
	var p: String = Fx.PLAYER
	var cases: Array = [
		[{p: 6.99}, [p], "cold", ""], [{p: 7.0}, [p], "player_minor", p],
		[{p: 10.0}, [p], "player_minor", p], [{p: 10.01}, [p], "player_major", p],
		[{"npc_a": 7.0, p: 5.0}, ["npc_a", p], "other_guilty", "npc_a"],
		[{"npc_a": 6.5, p: 6.0}, ["npc_a", p], "cold", ""], [{}, [], "cold", ""],
		[{"npc_a": 8.0, p: 9.0}, [p, "npc_a"], "player_minor", p],
	]
	for entry: Array in cases:
		var shortlist: Array[String] = []
		shortlist.assign(entry[1])
		var result: Dictionary = InvestigationEngine.decide_verdict(entry[0], shortlist, minor, major)
		check(result["verdict"] == entry[2] and result["culprit"] == entry[3],
				"weights %s → %s" % [str(entry[0]), entry[2]])
	_test_modulated_verdict(minor, major)


## §12.4 «reduce el umbral de todas las fases»: con sospecha 80 los umbrales de condena del
## jugador bajan 2,4 (7,0 → 4,6 y 10,0 → 7,6); los de los personajes no.
func _test_modulated_verdict(minor: float, major: float) -> void:
	var shift: float = Fx.bal("investigaciones.mod_umbral_por_sospecha") * 80.0
	check_near(shift, -2.4, 0.0001, "suspicion 80 shifts the player's verdict thresholds by -2.4")
	var p: String = Fx.PLAYER
	var cases: Array = [
		[{p: 4.5}, [p], "cold"], [{p: 4.7}, [p], "player_minor"], [{p: 7.5}, [p], "player_minor"],
		[{p: 7.7}, [p], "player_major"], [{"npc_a": 6.9}, ["npc_a"], "cold"],
	]
	for entry: Array in cases:
		var shortlist: Array[String] = []
		shortlist.assign(entry[1])
		var result: Dictionary = InvestigationEngine.decide_verdict(entry[0], shortlist, minor,
				major, shift)
		check_eq(result["verdict"], entry[2], "suspicion 80: %s → %s" % [str(entry[0]), entry[2]])


func _test_minor_verdict_marks_player() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "card_log", 2.5, Fx.PLAYER)
	Security.add_evidence(case_id, "partial_witness", 0.8, Fx.PLAYER)
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 7.3, 0.001,
			"4.0 + 2.5 + 0.8 with no access to the sealed room = 7.3")
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_VERDICT)
	check(_log.last("investigation_resolved") == [case_id, "player_minor", Fx.PLAYER],
			"7.0-10.0 → player guilty, minor (demotion handled by the World listener)")
	check(Security.is_player_marked() and Security.get_alert_level() == 5,
			"maximum suspicion for weeks: alert at maximum")
	check_near(Security.get_effective_suspicion(), 100.0, 0.0001,
			"while marked, Security and the interrogation work with maximum suspicion")
	check_eq(Interrogation.new("none").get_opening_tone(), "door_slam",
			"a marked player's next interrogation opens with the door slamming")
	check(Security.can_search_player(), "a marked player can be searched")
	var days: int = 3 * Database.get_balance_int("tiempo.jornadas_por_semana")
	Fx.advance_days(days - 1)
	check(Security.is_player_marked(), "still marked the day before 3 weeks pass")
	Fx.advance_days(1)
	check(not Security.is_player_marked() and Security.get_alert_level() < 5,
			"after 3 weeks the mark lapses")
	_log.stop()


# ─── Vías de señales con las cargas reales de sus emisores ────

## Procedimiento 1 «dirigiendo un rumor» (§12.3 fase 3): un rumor plantado sobre un compañero
## (SocialGraph.inject_rumour) se recoge como rumor sin fuente contra él.
func _test_rumour_about_another_npc() -> void:
	_fresh()
	var case_id: String = Security.report_incident("object_missing", 1, "hr_office", true,
			{"weight": 3.0, "always_opens": true})
	var rumour: String = SocialGraph.inject_rumour("npc_debbie_foyle",
			"steals_ideas:" + Fx.SCAPEGOAT, 0.8)
	check(not rumour.is_empty(), "the player plants a rumour about a colleague")
	Fx.advance_days(1)
	var piece: Dictionary = Fx.piece_of_type(case_id, "unsourced_rumour")
	check(not piece.is_empty() and piece["points_to"] == Fx.SCAPEGOAT
			and is_equal_approx(float(piece["weight"]), 0.3),
			"the directed rumour becomes an unsourced-rumour piece (0.3) against the colleague")
	check(Security.get_case_weight_against(Fx.SCAPEGOAT, case_id) > 0.0,
			"the colleague now carries weight in the case")


## Procedimiento 2 en las zonas relevantes (§12.3, §5.4-5.5): pasillo, ascensores y escaleras de
## la planta del incidente; un clip por cámara; el uniforme se cruza con los accesos (§11.4).
func _test_footage_review_zones() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	Security.register_camera_footage("corridors_low@3", d0, 10)
	Security.register_camera_footage("corridors_low@4", d0, 10)
	Security.register_camera_footage("main_elevator_1@3", d0, 11)
	Security.register_camera_footage("main_elevator_1@3", d0, 12)
	Security.log_card_access("elevator_reader@3", Fx.PLAYER, d0, 11, "main_elevator_1@3")
	Security.log_card_access("elevator_reader@7", Fx.PLAYER, d0, 11, "main_elevator_1@7")
	Fx.wear("uniform_cleaning")
	Security.register_camera_footage("main_stairs@3", d0, 9)
	Fx.wear("")
	var case_id: String = Security.report_incident("object_missing", 1, "wing_3b", true,
			{"weight": 3.0, "always_opens": true})
	Fx.advance_days(2)
	var footage: Array[Dictionary] = _pieces_of(case_id, "camera_footage")
	var cards: Array[Dictionary] = _pieces_of(case_id, "card_log")
	check_eq(footage.size(), 3, "floor-3 corridor, elevator (one clip per camera) and stairs")
	check_eq(cards.size(), 1, "the floor-3 elevator reader, not the floor-7 one")
	var disguised: Dictionary = {}
	for piece: Dictionary in footage:
		if str(piece["record_id"]).contains("main_stairs"):
			disguised = piece
	check(disguised.get("points_to") == Fx.PLAYER and is_equal_approx(float(disguised.get(
			"certainty", 0.0)), Fx.bal("seguridad.certeza_cruce_uniforme")),
			"uniform footage cross-checked with the access log points to the player (partial)")


func _pieces_of(case_id: String, evidence_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in Security.get_investigation(case_id).evidence:
		if piece["type"] == evidence_type:
			out.append(piece)
	return out


## §12.2: CaughtHandler y Blackmail mandan PUNTOS de sospecha (20 / 10) en `weight`; la pieza
## es la de §12.3 (4,0; superior y chivatazo ×0,5). NPCDirector manda pesos de evidencia.
func _test_report_payloads() -> void:
	_fresh()
	var hardliner: NPCRuntime = BriberyFx.synthetic("npc_test_hardliner", "hardliner")
	CaughtHandler.apply_caught_reaction(hardliner, "drawer_forced", Fx.SEALED_ROOM, 0.0)
	check_eq(_log.last("npc_reported_player"), [hardliner.id, "security", 20.0, Fx.SEALED_ROOM],
			"CaughtHandler reports with its real payload (20 suspicion points)")
	var cases: Array[Investigation] = Security.get_active_investigations()
	check_eq(cases.size(), 1, "a report to Security opens a case (4.0 > 3.0)")
	var case_id: String = cases[0].id if cases.size() == 1 else ""
	var piece: Dictionary = Fx.piece_of_type(case_id, "direct_witness")
	check_near(float(piece.get("weight", 0.0)), 4.0, 0.0001,
			"the piece weighs 4.0 (§12.3), not the 20 suspicion points")
	var belief: Belief = BeliefNet.get_belief(str(piece.get("record_id", "")))
	check(belief != null and belief.holder == hardliner.id and belief.fact == "reported:security",
			"the piece is the reporter's own belief")
	BeliefNet.apply_daily_decay()
	check(belief != null and float(Fx.piece_of_type(case_id, "direct_witness")["certainty"])
			< 1.0 and is_equal_approx(float(Fx.piece_of_type(case_id, "direct_witness")[
			"certainty"]), belief.certainty), "the testimony decays with the witness's belief")
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_VERDICT)
	check(_log.last("investigation_resolved") == [case_id, "cold", ""] and _log.count(
			"game_over") == 0, "a single report never ends the game: the case goes cold")
	_test_weaker_report_channels()


func _test_weaker_report_channels() -> void:
	_fresh()
	var company_man: NPCRuntime = BriberyFx.synthetic("npc_test_company", "company_man")
	CaughtHandler.apply_caught_reaction(company_man, "drawer_forced", "hr_office", 0.0)
	check_eq(_log.last("npc_reported_player"), [company_man.id, "superior", 10.0, "hr_office"],
			"company_man reports to the superior (10 points)")
	check(Security.get_active_investigations().is_empty(),
			"a note to the superior (2.0) is only a file annotation: no case yet")
	EventBus.npc_reported_player.emit("npc_test_other", "superior", 10.0, "hr_office")
	check_eq(Security.get_active_investigations().size(), 1,
			"a second annotation in the same room adds up (4.0) and opens the case")
	_fresh()
	EventBus.npc_reported_player.emit("npc_test_coward", Blackmail.REPORT_ANONYMOUS,
			Database.get_balance_float("chantaje.peso_chivatazo_anonimo"), "cafeteria")
	check(Security.get_active_investigations().is_empty(), "an anonymous tip alone (2.0) waits")
	EventBus.npc_reported_player.emit("npc_test_seen", "partial_witness", 0.8, "main_reception")
	EventBus.npc_reported_player.emit("npc_test_direct", "direct_witness", 4.0, "hr_office")
	var cases: Array[Investigation] = Security.get_active_investigations()
	check(cases.size() == 1 and _pieces_of(cases[0].id, "direct_witness").size() == 1
			and is_equal_approx(float(_pieces_of(cases[0].id, "direct_witness")[0]["weight"]),
			4.0), "NPCDirector's evidence-type report keeps its evidence weight")


## crime_committed → incident_triggers (seguridad.incidentes_por_delito).
func _test_crime_signal_paths() -> void:
	_fresh()
	EventBus.crime_committed.emit("theft_small", "hr_office", {})
	check(Security.get_active_investigations().is_empty(), "one small theft (2.5) stays pending")
	EventBus.crime_committed.emit("drawer_forced", "hr_office", {})
	var cases: Array[Investigation] = Security.get_active_investigations()
	var expected: Array[String] = ["object_missing", "object_missing"]
	check(cases.size() == 1 and cases[0].incident_type == "object_missing"
			and Fx.piece_types(cases[0].id) == expected,
			"a second theft in the room opens the object-missing case (2.5 + 2.5)")
	EventBus.crime_committed.emit("power_cut", "electrical_room", {})
	check(_case_at(Security.get_active_investigations(), "electrical_room") != null,
			"every power cut opens a case")
	EventBus.crime_committed.emit("theft_product", "general_warehouse", {"leaves_record": false})
	check(_case_at(Security.get_active_investigations(), "general_warehouse") == null,
			"an act that leaves no record raises no incident")


## §12.3 fase 1: el fraude aflora en el cierre mensual y el rastro contable (BeliefNet, 14
## jornadas de retardo) se recoge desde la jornada del fraude, en cualquier sala.
func _test_fraud_surfaces_at_month_close() -> void:
	_fresh()
	Fx.enter_room("street")
	var d0: int = Security.get_current_day()
	EventBus.crime_committed.emit("fraud", "wing_3b", {"amount": 5000})
	_broadcast_days(d0 + 1, d0 + 18)
	check(Security.get_all_investigations().is_empty(), "the fraud stays hidden until month close")
	check_eq(_accounting_records().size(), 1, "the accounting trail surfaced after its delay")
	EventBus.month_closed.emit(1)
	var cases: Array[Investigation] = Security.get_active_investigations()
	var case_id: String = cases[0].id if cases.size() == 1 else ""
	var fraud: Dictionary = Fx.piece_of_type(case_id, "fraud_at_month_close")
	check(not fraud.is_empty() and fraud["points_to"] == Fx.PLAYER
			and is_equal_approx(float(fraud["weight"]), 4.0),
			"fraud surfaced at month close: 4.0 against the player, author of the entries")
	_broadcast_days(d0 + 19, d0 + 21)
	var trail: Dictionary = Fx.piece_of_type(case_id, "accounting_trail")
	check(not trail.is_empty() and trail["points_to"] == Fx.PLAYER
			and is_equal_approx(float(trail["weight"]), 3.0),
			"the accounting trail (3.0, recorded in another room) joins the fraud case")
	_broadcast_days(d0 + 22, d0 + 30)
	var resolved: Array = _log.last("investigation_resolved")
	check(resolved.size() == 3 and resolved[0] == case_id and resolved[2] == Fx.PLAYER
			and str(resolved[1]).begins_with("player_"), "the fraud case convicts the player")
	_test_small_fraud_stays_hidden()


func _test_small_fraud_stays_hidden() -> void:
	_fresh()
	EventBus.crime_committed.emit("fraud", "accounting", {"amount": 500})
	EventBus.month_closed.emit(1)
	check(Security.get_all_investigations().is_empty(),
			"a fraud of reduced magnitude (< 2000 €) does not surface (§12.3 lever)")
	EventBus.crime_committed.emit("fraud", "accounting", {})
	EventBus.month_closed.emit(2)
	check_eq(Security.get_all_investigations().size(), 1, "a fraud of unknown size surfaces")


func _accounting_records() -> Array[Belief]:
	var out: Array[Belief] = []
	for rec: Belief in BeliefNet.get_records_about(Fx.PLAYER):
		if rec.record_type == "accounting_entry":
			out.append(rec)
	return out


## Difunde day_advanced (BeliefNet libera los registros diferidos; Security hace su tic).
func _broadcast_days(from_day: int, to_day: int) -> void:
	for day: int in range(from_day, to_day + 1):
		EventBus.day_advanced.emit(day)


func _test_audit_and_insider_signals() -> void:
	_fresh()
	EventBus.audit_triggered.emit(false)
	check(Security.get_all_investigations().is_empty(), "an audit that finds nothing opens nothing")
	EventBus.audit_triggered.emit(true)
	var cases: Array[Investigation] = Security.get_active_investigations()
	check(cases.size() == 1 and Fx.piece_of_type(cases[0].id, "fraud_at_month_close").get(
			"points_to") == Fx.PLAYER, "audit discrepancy: fraud case pointing at the player")
	EventBus.insider_pattern_detected.emit(4)
	check_eq(Security.get_deferred_incident_count(), 1,
			"the insider pattern (not provoked right now) waits for the 3-day rest")
	Fx.advance_days(3)
	var insider: Investigation = _case_at(Security.get_active_investigations(), "trading_room")
	check(insider != null and Fx.piece_of_type(insider.id, "insider_pattern").get("points_to")
			== Fx.PLAYER and is_equal_approx(float(Fx.piece_of_type(insider.id,
			"insider_pattern").get("weight", 0.0)), 6.0), "insider pattern case: 6.0 on the player")


## time_band_changed (noche con el jugador dentro) y room_entered (salir de noche).
func _test_last_to_leave_signals() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	Fx.enter_room("wing_3b")
	EventBus.time_band_changed.emit("exit", "night")
	check_eq(Security.get_last_to_leave(d0), Fx.PLAYER, "spending the night inside: last to leave")
	_fresh()
	Fx.enter_room("street")
	EventBus.time_band_changed.emit("exit", "night")
	check_eq(Security.get_last_to_leave(d0), "", "at home when night falls: not the last")
	Fx.enter_room("main_reception")
	Fx.enter_room("street")
	check_eq(Security.get_last_to_leave(d0), Fx.PLAYER, "leaving the building at night: last")


## seat_vacated / seat_filled: quien ocupa la silla de la víctima tiene móvil (+1,5).
func _test_motive_from_seat_change() -> void:
	_fresh()
	EventBus.npc_removed.emit("npc_victim_m", "eliminated")
	EventBus.body_created.emit("body_m", "npc_victim_m", "hr_office")
	EventBus.seat_vacated.emit("billing_clerk", "npc_victim_m", "eliminated")
	EventBus.seat_filled.emit("billing_clerk", "npc_heir")
	Fx.advance_days(1)
	var inv: Investigation = _case_at(Security.get_active_investigations(), "hr_office")
	var case_id: String = inv.id if inv != null else ""
	check_near(Security.get_case_weight_against("npc_heir", case_id), 1.5, 0.0001,
			"the heir of the victim's seat has a motive (+1.5), filled before the case opened")
	EventBus.npc_removed.emit("npc_victim_n", "eliminated")
	EventBus.body_created.emit("body_n", "npc_victim_n", "cafeteria")
	Fx.advance_days(1)
	var second: Investigation = _case_at(Security.get_active_investigations(), "cafeteria")
	var before: float = Security.get_case_weight_against(Fx.PLAYER, second.id)
	EventBus.seat_vacated.emit("billing_clerk", "npc_victim_n", "eliminated")
	EventBus.seat_filled.emit("billing_clerk", Fx.PLAYER)
	check_near(Security.get_case_weight_against(Fx.PLAYER, second.id) - before, 1.5, 0.0001,
			"the player taking the victim's seat benefits from the crime (+1.5)")


## Con población: el caso de desaparición se abre donde se vio a la víctima (sala de la eliminación) y el
## cuerpo, arrastrado al archivo muerto sin ocultar (NPCDirector.move_body), aflora allí.
func _test_populated_body_case() -> void:
	_fresh(DEFAULT_SEED, true)
	var victim: String = Fx.SCAPEGOAT
	NPCDirector.remove_npc(victim, "eliminated")
	var body_id: String = str(NPCDirector.get_body_info(victim).get("body_id", ""))
	# §12.2: el caso se abre donde se la vio por última vez (la sala de la eliminación).
	var home: String = str(NPCDirector.get_body_info(victim).get("room_id", ""))
	NPCDirector.move_body(victim, "dead_archive", "")
	Fx.advance_days(1)
	var inv: Investigation = _case_at(Security.get_active_investigations(), home)
	check(inv != null and inv.incident_type == "missing_person" and home != "dead_archive",
			"populated run: the case opens where the victim was last seen (%s)" % home)
	Fx.advance_days(10)
	check(_log.of("body_discovered").has([body_id, "dead_archive"]),
			"the body dragged to the dead archive surfaces in the phase-2 search")
	var guard: int = Investigation.MAX_PHASE * 2
	while inv != null and inv.is_active() and guard > 0:
		Fx.advance_days(1)
		guard -= 1
	check_eq(Security.get_case_report(inv.id).get("investigator"), "npc_rose_miller",
			"the case file names its investigator (Rose Miller, alive) even without phase 4")
