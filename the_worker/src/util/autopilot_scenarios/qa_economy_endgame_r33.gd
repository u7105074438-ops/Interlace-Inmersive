# qa_economy_endgame_r33.gd (escenario) — QA adversarial de §11.8 (caja fuerte, documentos,
# notaría) y §12.8-12.9 (seguimiento y nueve finales) jugado desde R33.
# PROPIETARIO DE: nada (conduce el juego; saltos de QA: teletransporte, reloj, ejes).
# ESCUCHA: señales de EventBus (solo registro).
extends Node

## tools/screenshot.sh /tmp/qa_r33 qa_economy_endgame_r33 --force-rank=33 --seed=7 --skip-intro
## Capturas: r33_01_start · r33_02_office · r33_03_docs · r33_04_notary · r33_05_ending(_b)

const SHORT := 8

var _pilot: Autopilot = null
var _game: GameRoot = null
var _ops: Node = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("QA End", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("qa_r33: no game scene")
		return
	await pilot.frames(SHORT * 3)
	_game = GameRoot.find(get_tree())
	_ops = (load("res://src/util/autopilot_scenarios/social_ops.gd") as GDScript).new()
	add_child(_ops)
	_ops.set("_pilot", pilot)
	_ops.set("_game", _game)
	_hook()
	_log("START rank=%d occ=%s phase=%s revealed=%s holder=%s voss_in=%s hours=%s" % [
		PlayerState.get_rank(), PlayerState.get_occupation_id(), Endgame.get_phase(),
		Endgame.is_objective_revealed(), Endgame.get_office_holder(), Endgame.is_voss_in_office(),
		str(Endgame.get_office_hours())])
	_log("OBJECTIVE key=%s text=%s" % [Endgame.get_objective_text_key(), tr(Endgame.get_objective_text_key())])
	_log("ROUTES %s" % str(Endgame.get_access_routes()))
	_log("SEAT ceo=%s vice=%s" % [Company.get_seat_holder("ceo"), Company.get_seat_holder("vice_ceo")])
	await pilot.shot("r33_01_start")
	_ending_matrix("pre_docs")
	await _office()
	_ending_matrix("with_docs")
	await _notary()
	await pilot.seconds(3.0)
	await pilot.shot("r33_05_ending")
	await pilot.seconds(4.0)
	await pilot.shot("r33_05_ending_b")
	_log("END phase=%s cause=%s ending=%s axes=%s" % [Endgame.get_phase(), Tracking.get_terminal_cause(), Tracking.evaluate_ending(), str(Tracking.get_all_axes())])


func _hook() -> void:
	EventBus.game_over.connect(func(c: String, e: String, t: Dictionary) -> void: _log("SIG GAME_OVER %s %s snap=%s" % [c, e, str(t)]))
	EventBus.ownership_documents_obtained.connect(func() -> void: _log("SIG documents_obtained"))
	EventBus.ownership_notarised.connect(func() -> void: _log("SIG notarised"))
	EventBus.suspicion_changed.connect(func(a: float, b: float) -> void: _log("SIG suspicion %.1f -> %.1f" % [a, b]))
	EventBus.investigation_opened.connect(func(c: String, t: String, sev: int) -> void: _log("SIG investigation_opened %s %s sev=%d" % [c, t, sev]))


## Pure evaluation of every terminal cause with the current state (ending reachability).
func _ending_matrix(tag: String) -> void:
	for cause: String in ["ownership_notarised", "ceo_term_without_ownership", "board_removal",
			"investigation_conclusive", "starvation", "results_failure_expulsion"]:
		_log("MATRIX %s cause=%s -> %s (docs=%s rank=%d dominant=%s hybrid=%s)" % [tag, cause,
			Tracking.evaluate_ending_for_cause(cause), Tracking.has_ownership_documents(),
			PlayerState.get_rank(), Tracking.get_dominant_axis(), Tracking.is_hybrid()])


func _office() -> void:
	GameClock.advance_minutes(maxf(20.0 * 60.0 - GameClock.get_day_minutes(), 0.0))
	_log("EVENING time=%s voss_in=%s windows=%s" % [GameClock.get_time_string(), Endgame.is_voss_in_office(), str(Endgame.get_voss_absence_windows(GameClock.get_day()))])
	await _ops.call("_go", "ceo_office")
	_log("OFFICE room=%s entry=%s" % [PlayerState.get_room(), str(Endgame.register_office_entry("main_door"))])
	_log("OFFICE open_safe(no combo)=%s" % str(Endgame.open_safe()))
	_log("OFFICE files10=%s" % str(Endgame.search_voss_files(10)))
	_log("OFFICE files40=%s" % str(Endgame.search_voss_files(40)))
	_log("OFFICE knows=%s src=%s phase=%s" % [Endgame.knows_combination(), Endgame.get_combination_source(), Endgame.get_phase()])
	await _pilot.shot("r33_02_office")
	_log("OFFICE open_safe=%s" % str(Endgame.open_safe()))
	_log("DOCS state=%s at_risk=%s phase=%s objective=%s" % [Endgame.get_documents_state(), Endgame.are_documents_at_risk(), Endgame.get_phase(), tr(Endgame.get_objective_text_key())])
	await _pilot.frames(SHORT)
	await _pilot.shot("r33_03_docs")


func _notary() -> void:
	GameClock.advance_to_next_day()
	await _pilot.frames(4)
	GameClock.advance_minutes(maxf(11.0 * 60.0 - GameClock.get_day_minutes(), 0.0))
	await _ops.call("_go", "notary")
	_log("NOTARY room=%s notary=%s present=%s preview=%s susp=%.1f rep=%.1f docs=%s" % [
		PlayerState.get_room(), Endgame.get_notary_id(), Endgame.is_notary_present(),
		Endgame.preview_notary_decision(), PlayerState.get_suspicion(), PlayerState.get_reputation(),
		Endgame.get_documents_state()])
	await _pilot.shot("r33_04_notary")
	var r: Dictionary = Endgame.request_notarisation()
	_log("NOTARY request=%s" % str(r))
	if Endgame.is_verification_pending():
		_log("VERIFY %s" % str(Endgame.get_verification()))
		for i: int in 4:
			GameClock.advance_to_next_day()
			await _pilot.frames(4)
			_log("VERIFY day=%d left=%d phase=%s" % [GameClock.get_day(), Endgame.get_verification_days_left(), Endgame.get_phase()])
	_log("EPILOGUE %s" % Tracking.get_epilogue(Tracking.evaluate_ending_for_cause("ownership_notarised")).substr(0, 400))


func _log(s: String) -> void:
	print("[qa_r33] " + s)
