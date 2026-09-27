# interrogation_case.gd — Cuerpo de test_interrogation (§12.5, PASO 29): tono de apertura, cada regla de respuesta (tabla exacta), sospecha aplicada al juego, coartada quemada, presentación secuencial, condición de éxito, congelación por abogado, escena rechazada o abandonada y, con población, acusación con aliados, contacto legal e investigador.
# PROPIETARIO DE: nada.
# ESCUCHA: interrogation_answered, investigation_resolved, game_over, grievance_added, interrogation_started (vía SignalLog).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")

var _log: Fx.SignalLog
var _rules: Dictionary = {}


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	_rules = Interrogation.load_rules()
	_test_tone()
	_test_deny_rule()
	_test_explain_rule()
	_test_other_rules()
	_test_session_mixed_answers()
	_test_bought_alibi_burns()
	_test_session_success()
	_test_lawyer_freezes_case()
	_test_scene_refused_outside_phase_4()
	_test_abandoned_scene_expires()
	_test_populated_accusation_allies()
	_test_populated_lawyer_and_interrogator()
	_log.stop()


func _fresh(populated: bool = false) -> void:
	if _log != null:
		_log.stop()
	new_run(DEFAULT_SEED, populated)
	_log = Fx.SignalLog.new().watch(["interrogation_answered", "investigation_resolved",
			"game_over", "grievance_added", "interrogation_started"])


func _test_tone() -> void:
	check(is_equal_approx(float(_rules["apology_above"]), 85.0)
			and is_equal_approx(float(_rules["door_slam_above"]), 70.0), "tone thresholds 85 / 70")
	check_eq(Interrogation.opening_tone(90.0, 10.0, _rules), "apology", "reputation > 85 → apology")
	check_eq(Interrogation.opening_tone(85.0, 10.0, _rules), "neutral", "reputation 85 → neutral")
	check_eq(Interrogation.opening_tone(50.0, 71.0, _rules), "door_slam", "suspicion > 70 → door slam")
	check_eq(Interrogation.opening_tone(50.0, 70.0, _rules), "neutral", "suspicion 70 → neutral")
	check_eq(Interrogation.opening_tone(90.0, 80.0, _rules), "door_slam", "both → the door slams")
	var session: Interrogation = Interrogation.new("none", {"reputation": 90.0, "suspicion": 0.0})
	check_eq(session.get_opening_tone(), "apology", "get_opening_tone() uses the player's standing")
	check_eq(session.get_opening_key(), "INTERROGATION_INTRO_APOLOGY", "apology intro key")


func _test_deny_rule() -> void:
	var removed: Dictionary = Interrogation.rule_deny(0.8, 61.0, _rules)
	check(removed["outcome"] == "piece_removed" and removed["remove"],
			"deny: reputation 61 > 60 and weight 0.8 < 2.0 → piece removed")
	var low_rep: Dictionary = Interrogation.rule_deny(0.8, 60.0, _rules)
	check(low_rep["outcome"] == "denial_rejected" and not low_rep["remove"]
			and low_rep["suspicion_delta"] == 8, "deny with reputation 60 → suspicion up (+8)")
	check_eq(Interrogation.rule_deny(2.0, 90.0, _rules)["outcome"], "denial_rejected",
			"deny against a piece of weight 2.0 fails")
	check_eq(Interrogation.rule_deny(1.99, 90.0, _rules)["outcome"], "piece_removed",
			"weight 1.99 is weak enough")
	var slammed: Interrogation = Interrogation.new("none", {"reputation": 90.0,
			"suspicion": 75.0})
	check_eq(slammed.get_opening_tone(), "door_slam", "suspicion 75: the door slams…")
	check_eq(Interrogation.rule_deny(0.8, 90.0, _rules)["outcome"], "piece_removed",
			"…but the §12.5 table decides the denial: rep 90, weight 0.8 → removed")


func _test_explain_rule() -> void:
	var none: Dictionary = Interrogation.rule_explain({}, 0.0, _rules)
	check(none["outcome"] == "requirement_missing" and not none["consumes_turn"],
			"explain without an alibi is not possible (turn not consumed)")
	check(Interrogation.rule_explain({"genuine": true}, 0.0, _rules)["remove"],
			"a real alibi removes the piece")
	check_near(float(_rules["alibi_verification_chance"]), 0.25, 0.0001, "bought alibi checked 25%")
	var caught: Dictionary = Interrogation.rule_explain({"genuine": false}, 0.1, _rules)
	check(caught["outcome"] == "alibi_false" and is_equal_approx(caught["weight_multiplier"], 2.0),
			"a false alibi verified → the piece weighs double")
	check_eq(Interrogation.rule_explain({"genuine": false}, 0.9, _rules)["outcome"],
			"alibi_accepted", "an unverified bought alibi works")


func _test_other_rules() -> void:
	check_eq(Interrogation.rule_accuse("", _rules)["outcome"], "requirement_missing",
			"accuse needs someone to accuse")
	check_eq(Interrogation.rule_accuse(Fx.PLAYER, _rules)["outcome"], "requirement_missing",
			"cannot accuse yourself")
	var accused: Dictionary = Interrogation.rule_accuse(Fx.SCAPEGOAT, _rules)
	check(accused["outcome"] == "piece_transferred" and accused["new_subject"] == Fx.SCAPEGOAT
			and accused["grievance_severity"] == 8, "accuse → piece moves, permanent grievance 8")
	var silence: Dictionary = Interrogation.rule_silence(_rules)
	check(silence["suspicion_delta"] == 5 and not silence["remove"]
			and is_equal_approx(silence["weight_multiplier"], 1.0), "silence: no weight change, +5")
	check_eq(Interrogation.rule_lawyer(false, _rules)["outcome"], "requirement_missing",
			"lawyer needs a contact in the P9 firm")
	var lawyer: Dictionary = Interrogation.rule_lawyer(true, _rules)
	check(lawyer["outcome"] == "case_frozen" and lawyer["freeze_days"] == 3, "lawyer freezes 3 days")
	check(Interrogation.is_success(6.99, _rules) and not Interrogation.is_success(7.0, _rules),
			"success = total weight below 7.0")
	var keys_ok: bool = true
	for outcome: String in ["piece_removed", "denial_rejected", "alibi_accepted", "alibi_false",
			"piece_transferred", "silence_kept", "case_frozen", "requirement_missing", "no_piece"]:
		var key: String = Interrogation.outcome_key(outcome)
		keys_ok = keys_ok and tr(key) != key
	check(keys_ok, "every answer outcome has a localised text key")


## Testigo 4,0 · parcial 0,8 · grabación 4,5 contra el jugador (sin acceso a la sala).
func _interrogation_case(location: String = Fx.SEALED_ROOM) -> String:
	var case_id: String = Fx.open_witness_case(location, 10, 1)
	Security.add_evidence(case_id, "partial_witness", 0.8, Fx.PLAYER)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	return case_id


## Testigo 4,0 · parcial 0,8 · grabación 4,5 · tarjeta 2,5 contra el jugador (sin acceso a la
## sala). La sospecha que suben las respuestas llega a BeliefNet (estado del juego).
func _test_session_mixed_answers() -> void:
	_fresh()
	var case_id: String = _interrogation_case()
	Security.add_evidence(case_id, "card_log", 2.5, Fx.PLAYER)
	check_eq(Security.get_investigation(case_id).phase, InvestigationEngine.PHASE_INTERROGATION,
			"player tops the shortlist → phase 4")
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 65.0, "suspicion": 0.0,
			"alibi": {"provider": "npc_ally", "genuine": false}, "verification_roll": 0.1,
			"has_legal_contact": false})
	var intro: Dictionary = session.start()
	check(intro.get("pieces") == 4 and intro.get("tone") == "neutral", "four pieces, neutral tone")
	check_eq(session.available_answers(),
			["deny", "explain", "accuse_other", "silence"] as Array[String],
			"no lawyer without a contact in the firm")
	var start_suspicion: float = BeliefNet.calculate_player_suspicion()
	check_eq(session.current_piece().get("type"), "direct_witness", "pieces presented in order")
	check_eq(session.answer("silence")["outcome"], "silence_kept", "silence")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 11.8, 0.001, "weight unchanged")
	check_near(BeliefNet.calculate_player_suspicion() - start_suspicion, 5.0, 0.001,
			"silence raises the player's real suspicion by 5 (BeliefNet)")
	check_eq(session.answer("deny")["outcome"], "piece_removed", "weak partial witness denied")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 11.0, 0.001, "0.8 removed")
	check_eq(session.answer("explain")["outcome"], "alibi_false", "bought alibi caught")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 15.5, 0.001,
			"the footage now weighs 9.0")
	check(not session.available_answers().has("explain"), "a false alibi is burned")
	check_eq(session.answer("deny")["outcome"], "denial_rejected", "denying the 2.5 card log fails")
	check_near(BeliefNet.calculate_player_suspicion() - start_suspicion, 13.0, 0.001,
			"the rejected denial adds 8 more (5 + 8)")
	check(session.is_finished() and session.get_suspicion_delta() == 13, "all pieces answered")
	var indices: Array = []
	for args: Array in _log.of("interrogation_answered"):
		indices.append(args[1])
	check_eq(indices, [0, 1, 2, 3], "interrogation_answered emitted for each piece in sequence")
	var result: Dictionary = session.finish()
	check(not result["success"] and result["verdict"] == "player_major",
			"15.5 ≥ 7.0: failure; > 10.0 → game over")
	check_eq(_log.count("game_over"), 1, "game_over emitted")


## Coartada comprada guardada en Security (soborno «mentir»): verificada falsa, se quema.
func _test_bought_alibi_burns() -> void:
	_fresh()
	var case_id: String = _interrogation_case()
	Security.provide_alibi(case_id, "npc_liar", false)
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 50.0,
			"suspicion": 0.0, "verification_roll": 0.1})
	session.start()
	check(session.available_answers().has("explain"), "the bought alibi can be used")
	check_eq(session.answer("explain")["outcome"], "alibi_false", "and it is caught")
	check(Security.get_alibi(case_id).is_empty() and not session.available_answers().has(
			"explain"), "a verified false alibi is withdrawn from the case")
	check_eq(session.answer("explain")["outcome"], "requirement_missing",
			"it cannot 'work' on a later piece")


func _test_session_success() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	Security.register_camera_footage("turnstiles", d0, 10)
	check(bool(Security.get_alibi(case_id).get("genuine", false)),
			"records placing the player elsewhere at that hour are a real alibi")
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 50.0, "suspicion": 0.0})
	session.start()
	var missing: Dictionary = session.answer("accuse_other", "")
	check(missing["outcome"] == "requirement_missing" and session.get_current_index() == 0,
			"an invalid answer does not use up the piece")
	check_eq(session.answer("accuse_other", Fx.SCAPEGOAT)["outcome"], "piece_transferred",
			"the witness piece is pinned on a colleague")
	check_eq(session.answer("explain")["outcome"], "alibi_accepted", "real alibi explains the tape")
	var result: Dictionary = session.finish()
	check(result["success"] and float(result["total_weight"]) < 7.0,
			"total weight below 7.0 → the interrogation succeeds")
	check_eq(result["verdict"], "cold", "the scapegoat's 4.0 is not enough either: cold case")
	check((Security.get_case_report(case_id)["scapegoats"] as Array).has(Fx.SCAPEGOAT),
			"the accused is recorded as scapegoat")


func _test_lawyer_freezes_case() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	var footage: String = Security.register_camera_footage(Fx.SEALED_ROOM, d0, 10)
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	check(not Security.request_legal_assistance(case_id), "no contact in the firm → no lawyer")
	Fx.advance_days(3)
	var inv: Investigation = Security.get_investigation(case_id)
	check_eq(inv.phase, InvestigationEngine.PHASE_INTERROGATION, "witness + footage → phase 4")
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 50.0, "suspicion": 0.0,
			"has_legal_contact": true})
	session.start()
	check_eq(session.answer("request_lawyer")["outcome"], "case_frozen", "lawyer requested")
	var today: int = Security.get_current_day()
	check(session.is_finished() and inv.is_frozen(today) and inv.frozen_until_day == today + 3,
			"the case is frozen for three days")
	check_eq(session.finish()["verdict"], "", "no verdict while frozen")
	Fx.advance_days(2)
	check_eq(inv.phase, InvestigationEngine.PHASE_INTERROGATION, "still waiting after 2 days")
	Fx.enter_room("monitor_room")
	check(Security.delete_footage(footage), "the freeze is used to destroy the tape")
	check(not Fx.piece_types(case_id).has("camera_footage"), "the open case loses the footage")
	Fx.advance_days(1)
	check(_log.last("investigation_resolved") == [case_id, "cold", ""],
			"after the freeze the verdict falls on the reduced file: cold")


## start() solo abre la escena si Security la acepta (fase 4).
func _test_scene_refused_outside_phase_4() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 90.0,
			"suspicion": 0.0})
	check(session.start().is_empty() and session.is_finished(),
			"a case still collecting evidence (phase 2) cannot be interrogated")
	check_eq(session.answer("deny")["outcome"], "no_piece", "answers change nothing")
	check_near(Security.get_case_weight_against(Fx.PLAYER, case_id), 4.0, 0.0001,
			"the witness piece is untouched")


## Una escena abierta y nunca cerrada caduca: fase 4 + dias_gracia_interrogatorio.
func _test_abandoned_scene_expires() -> void:
	_fresh()
	var case_id: String = _interrogation_case()
	Interrogation.new(case_id, {"reputation": 50.0, "suspicion": 0.0}).start()
	var grace: int = Database.get_balance_int("seguridad.dias_gracia_interrogatorio")
	var due: int = int(InvestigationEngine.dig(Database.get_investigation_params(),
			"phase_durations.interrogation", 0))
	Fx.advance_days(due + grace - 1)
	check_eq(Security.get_investigation(case_id).phase, InvestigationEngine.PHASE_INTERROGATION,
			"an open scene holds the verdict while it lasts")
	Fx.advance_days(1)
	check(_log.of("investigation_resolved").any(func(args: Array) -> bool:
			return args[0] == case_id), "an abandoned scene expires and the verdict falls")


## Con población: acusar traslada la pieza, agravio permanente al acusado y hostilidad de sus
## ALIADOS (amistad/pareja); rivales, jerarquía y departamento no.
func _test_populated_accusation_allies() -> void:
	_fresh(true)
	var accused: String = "npc_debbie_foyle"
	var allies: Array[String] = Interrogation.accused_allies(accused, float(_rules["ally_min_strength"]))
	var others: Array[String] = []
	for npc_id: String in SocialGraph.get_neighbours(accused, float(_rules["ally_min_strength"])):
		if not allies.has(npc_id):
			others.append(npc_id)
	check(not allies.is_empty() and not others.is_empty(),
			"the accused has strong friends and strong non-allies (rivals, hierarchy)")
	var case_id: String = _interrogation_case()
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 50.0, "suspicion": 0.0})
	session.start()
	check_eq(session.answer("accuse_other", accused)["outcome"], "piece_transferred", "accused")
	var hurt: Dictionary = {}
	for args: Array in _log.of("grievance_added"):
		hurt[str(args[0])] = str(args[1])
	check_eq(hurt.get(accused), "accused_in_interrogation", "the accused keeps a grievance")
	check(allies.all(func(id: String) -> bool: return hurt.get(id) == "ally_accused"),
			"every friend of the accused turns hostile")
	check(not others.any(func(id: String) -> bool: return hurt.has(id)),
			"rivals and other links do not (e.g. %s)" % str(others))
	check_eq(Security.get_investigation(case_id).evidence[0]["points_to"], accused,
			"the piece now points at the accused")


## Con población: el investigador es Rose Miller mientras está en plantilla; si no, quien ocupe
## Auditoría o Seguridad. El abogado exige un contacto real en el bufete de P9.
func _test_populated_lawyer_and_interrogator() -> void:
	_fresh(true)
	var case_id: String = _interrogation_case()
	check_eq(_log.last("interrogation_started"), [case_id, "npc_rose_miller"],
			"Rose Miller interrogates while she is on the staff")
	var contact: String = _legal_firm_npc()
	var had_contact: bool = Security.has_legal_contact()
	NPCDirector.add_favour(contact, "test_favour", 5)
	check(Security.has_legal_contact(), "a favour to someone at the P9 firm gives a legal contact")
	var session: Interrogation = Interrogation.new(case_id, {"reputation": 50.0, "suspicion": 0.0})
	session.start()
	check(session.available_answers().has("request_lawyer") and not had_contact,
			"request_lawyer only appears with the contact")
	check_eq(session.answer("request_lawyer")["outcome"], "case_frozen", "the lawyer freezes the case")
	NPCDirector.remove_npc("npc_rose_miller", "fired")
	var second: String = _interrogation_case("hr_office")
	var started: Array = _log.last("interrogation_started")
	var interrogator: String = str(started[1]) if started.size() == 2 else ""
	check(started.size() == 2 and started[0] == second and interrogator != "npc_rose_miller"
			and NPCDirector.is_active(interrogator) and _holds_interrogator_seat(interrogator),
			"with Rose gone, the active holder of Audit or Security interrogates (%s)" % interrogator)


func _legal_firm_npc() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.home_room == "legal_firm":
			return npc.id
	return ""


func _holds_interrogator_seat(npc_id: String) -> bool:
	for occupation: Variant in InvestigationEngine.dig(Database.get_investigation_params(),
			"interrogation.interrogator_occupations", []):
		if Company.get_seat_holder(str(occupation)) == npc_id:
			return true
	return false
