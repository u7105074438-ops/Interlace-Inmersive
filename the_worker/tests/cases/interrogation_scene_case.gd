# interrogation_scene_case.gd — Cuerpo de test_interrogation_scene: la escena de P15 (§12.5, PASO 29) presenta las piezas una a una, cada respuesta llama a Interrogation, finales de éxito, fracaso, congelación y sin caso, y las tres variantes de tono (disculpa, portazo, neutro).
# PROPIETARIO DE: nada.
# ESCUCHA: interrogation_answered, investigation_resolved, game_over (vía SignalLog).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")
const EPS := 0.001

var _log: Fx.SignalLog
var _answered: Array = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	await _check_tone_apology()
	await _check_tone_door_slam()
	await _check_tone_neutral()
	await _check_sequential_failure()
	await _check_success()
	await _check_requirement_missing()
	await _check_lawyer_frozen()
	await _check_no_case()
	await _check_populated_investigator()
	_log.stop()


func _fresh(populated: bool = false) -> void:
	if _log != null:
		_log.stop()
	new_run(DEFAULT_SEED, populated)
	_answered.clear()
	_log = Fx.SignalLog.new().watch(["interrogation_answered", "investigation_resolved", "game_over"])


## Testigo 4,0 · parcial 0,8 · grabación 4,5 (· tarjeta 2,5) contra el jugador, en fase 4.
func _case(with_card: bool) -> String:
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "partial_witness", 0.8, Fx.PLAYER)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	if with_card:
		Security.add_evidence(case_id, "card_log", 2.5, Fx.PLAYER)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	return case_id


func _open(case_id: String, context: Dictionary, instant: bool = true) -> InterrogationScene:
	var scene: InterrogationScene = InterrogationScene.new(case_id, context)
	scene.instant = instant
	scene.closed.connect(func() -> void: pass)
	scene.answered.connect(func(id: String, result: Dictionary) -> void: _answered.append([id, result["outcome"]]))
	add_child(scene)
	await wait_frames(2)
	return scene


func _close(scene: InterrogationScene) -> void:
	scene.queue_free()
	await wait_frames(1)


func _shows(scene: InterrogationScene, text: String) -> bool:
	return scene.get_visible_texts().has(text)


# ─── Tono (§12.5) ───────────────────────────────────────────────────────

func _check_tone_apology() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 90.0, "suspicion": 10.0}, false)
	var investigator: String = scene.get_investigator()
	check_eq(scene.get_tone(), Interrogation.TONE_APOLOGY, "reputation 90 → apology")
	check_eq(scene.get_stage().bubble_text(investigator), tr("INTERROGATION_INTRO_APOLOGY"),
			"the investigator opens by apologising")
	check(not bool(scene.get_stage().get_actor(investigator)["seated"]), "…standing up to greet you")
	check(bool(scene.get_stage().get_prop("coffee", false)), "…with a coffee on the table")
	check_eq(scene.get_stage().get_prop("lamp"), SceneStage.LAMP_WARM, "warm light")
	check(not scene.has_door_slammed(), "no door slam")
	scene.fast_forward()
	check(scene.get_step() == InterrogationScene.STEP_PIECE
			and bool(scene.get_stage().get_actor(investigator)["seated"]), "then sits down and presents")
	await _close(scene)


func _check_tone_door_slam() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 90.0, "suspicion": 80.0}, false)
	check_eq(scene.get_tone(), Interrogation.TONE_DOOR_SLAM, "suspicion 80 → door slam (even at reputation 90)")
	check(not scene.is_door_closed() and not scene.has_door_slammed(), "the door starts open")
	check_eq(scene.get_stage().get_prop("lamp"), SceneStage.LAMP_HARSH, "harsh light")
	var wait: float = Database.get_balance_float("escenas.portazo_espera_segundos")
	scene.advance(wait + Database.get_balance_float("escenas.pausa_segundos") + 0.01)
	check_eq(scene.get_caption(), tr("INTERROGATION_INTRO_DOOR_SLAM"), "the slam line is narrated")
	scene.fast_forward()
	check(scene.is_door_closed() and scene.has_door_slammed(), "the door slams shut")
	check_eq(scene.get_step(), InterrogationScene.STEP_PIECE, "then the first piece is presented")
	await _close(scene)


func _check_tone_neutral() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 10.0}, false)
	check_eq(scene.get_tone(), Interrogation.TONE_NEUTRAL, "neutral tone")
	check_eq(scene.get_stage().bubble_text(scene.get_investigator()), tr("INTERROGATION_INTRO_NEUTRAL"),
			"neutral opening line")
	check(not bool(scene.get_stage().get_prop("coffee", false)) and not scene.has_door_slammed(),
			"no coffee, no slam")
	await _close(scene)


# ─── Flujo secuencial ───────────────────────────────────────────────────

func _check_sequential_failure() -> void:
	_fresh()
	var case_id: String = _case(true)
	var records: Array[String] = []
	for piece: Dictionary in InvestigationEngine.pieces_against(Security.get_investigation(case_id), Fx.PLAYER):
		records.append(str(piece["record_id"]))
	var scene: InterrogationScene = await _open(case_id, {"reputation": 65.0, "suspicion": 0.0,
			"alibi": {"provider": "npc_liar", "genuine": false}, "verification_roll": 0.1,
			"has_legal_contact": false})
	check_eq(scene.get_shown_piece().get("record_id"), records[0], "exhibit 1 is the first piece")
	check_near(scene.get_meter_weight(), scene.get_case_weight(), EPS, "the meter shows Security's weight")
	check_near(scene.get_case_weight(), 11.8, EPS, "11.8 against you")
	check_eq(scene.answer(Interrogation.ANSWER_SILENCE)["outcome"], "silence_kept", "silence")
	check_eq(scene.get_shown_piece().get("record_id"), records[1], "exhibit 2 follows, one at a time")
	check_eq(scene.answer(Interrogation.ANSWER_DENY)["outcome"], "piece_removed", "weak piece denied")
	check_near(scene.get_meter_weight(), 11.0, EPS, "the meter drops by 0.8")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "alibi_false", "the bought alibi is caught")
	check_near(scene.get_case_weight(), 15.5, EPS, "the footage now weighs double (9.0)")
	check(not scene.available_answers().has(Interrogation.ANSWER_EXPLAIN), "the burnt alibi is gone")
	check_eq(scene.get_shown_piece().get("record_id"), records[3], "exhibit 4")
	check_eq(scene.answer(Interrogation.ANSWER_DENY)["outcome"], "denial_rejected", "denying 2.5 fails")
	var indices: Array = []
	for args: Array in _log.of("interrogation_answered"):
		indices.append(args[1])
	check_eq(indices, [0, 1, 2, 3], "each answer goes through Interrogation (interrogation_answered 0..3)")
	check_eq(_answered.size(), 4, "the scene emits answered() for each answer")
	check_eq(scene.get_step(), InterrogationScene.STEP_END, "all pieces answered → end")
	check_eq(scene.get_end_title(), tr("INTERROGATION_FAILURE"), "failure end state")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_VERDICT") % tr("VERDICT_PLAYER_MAJOR")),
			"the verdict is shown: serious")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_SUSPICION") % 13), "suspicion added: +5 +8")
	check_eq(_log.count("game_over"), 1, "Security ends the run (weight 15.5 > 10)")
	check(scene.answer(Interrogation.ANSWER_DENY).is_empty(), "no more answers after the end")
	await _close(scene)


func _check_success() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	Security.add_evidence(case_id, "camera_footage", 4.5, Fx.PLAYER)
	Security.register_camera_footage("turnstiles", d0, 10)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_INTERROGATION)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0})
	var candidates: Array[String] = scene.accuse_candidates()
	check(not candidates.is_empty() and not candidates.has(Fx.PLAYER)
			and not candidates.has(scene.get_investigator()), "someone to blame (never you or the investigator)")
	scene.open_accuse_picker()
	check(_shows(scene, tr("INTERROGATION_ACCUSE_TITLE")), "the accuse picker opens")
	check_eq(scene.answer(Interrogation.ANSWER_ACCUSE, Fx.SCAPEGOAT)["outcome"], "piece_transferred",
			"the witness piece is pinned on a colleague")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "alibi_accepted", "a real alibi")
	check(bool(scene.get_end_result().get("success", false)), "weight below 7.0 → success")
	check_eq(scene.get_end_title(), tr("INTERROGATION_SUCCESS"), "success end state")
	check(scene.get_end_lines().has(tr("INTERROGATION_END_VERDICT") % tr("VERDICT_COLD")), "cold verdict shown")
	check(scene.get_meter_weight() < 7.0, "the meter ends below the line")
	await _close(scene)


func _check_requirement_missing() -> void:
	_fresh()
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0,
			"has_legal_contact": false})
	var first: String = str(scene.get_shown_piece().get("record_id", ""))
	var explain: Button = scene.find_child("Answer_explain", true, false) as Button
	var lawyer: Button = scene.find_child("Answer_request_lawyer", true, false) as Button
	check(explain != null and explain.disabled and lawyer != null and lawyer.disabled,
			"explain and lawyer are disabled without alibi / P9 contact")
	check(_shows(scene, tr("INTERROGATION_REQ_ALIBI")) and _shows(scene, tr("INTERROGATION_REQ_LAWYER")),
			"the requirements are shown")
	check_eq(scene.answer(Interrogation.ANSWER_EXPLAIN)["outcome"], "requirement_missing", "explain refused")
	check(scene.get_step() == InterrogationScene.STEP_PIECE
			and str(scene.get_shown_piece().get("record_id")) == first, "the same piece stays on the table")
	check_eq(scene.get_caption(), tr("INTERROGATION_OUTCOME_REQUIREMENT_MISSING"), "and the refusal is narrated")
	await _close(scene)


func _check_lawyer_frozen() -> void:
	_fresh()
	var case_id: String = _case(false)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0,
			"has_legal_contact": true})
	check(scene.available_answers().has(Interrogation.ANSWER_LAWYER), "a P9 contact enables the lawyer")
	check_eq(scene.answer(Interrogation.ANSWER_LAWYER)["outcome"], "case_frozen", "lawyer requested")
	check_eq(scene.get_end_title(), tr("INTERROGATION_FROZEN_TITLE"), "frozen end state")
	check(Security.get_investigation(case_id).is_frozen(Security.get_current_day()), "logic: the case is frozen")
	await _close(scene)


func _check_no_case() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.SEALED_ROOM, 10, 1)
	var scene: InterrogationScene = await _open(case_id, {"reputation": 50.0, "suspicion": 0.0})
	check_eq(scene.get_step(), InterrogationScene.STEP_END, "a case still collecting evidence: nothing to ask")
	check_eq(scene.get_end_title(), tr("INTERROGATION_NO_CASE"), "the scene says so")
	var closed: Array[int] = [0]
	scene.closed.connect(func() -> void: closed[0] += 1)
	scene.request_close()
	check_eq(closed[0], 1, "and can be left")
	await _close(scene)


func _check_populated_investigator() -> void:
	_fresh(true)
	var scene: InterrogationScene = await _open(_case(false), {"reputation": 50.0, "suspicion": 0.0})
	check_eq(scene.get_investigator(), "npc_rose_miller", "Rose Miller interrogates by default")
	check(scene.get_stage().has_actor("npc_rose_miller") and scene.get_stage().has_actor("player"),
			"both sit at the table")
	check_eq(scene.get_stage().get_prop("nameplate"), NPCDirector.get_npc("npc_rose_miller").name,
			"her nameplate is on the table")
	scene.request_close()
	check_eq(scene.get_step(), InterrogationScene.STEP_PIECE, "Esc does not get you out of an interrogation")
	await _close(scene)
