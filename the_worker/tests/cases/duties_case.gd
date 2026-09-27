# duties_case.gd — Cuerpo de test_duties: coste temporal, A.S.S.I.S.T., detección, viabilidad, rondas, cuota, delegación y escalera de consecuencias (§10).
# PROPIETARIO DE: nada.
# ESCUCHA: duty_progressed, duty_completed, duty_failed, duty_deadline_warned, assist_used, notebook_entry_added, record_created, game_over (conexiones del caso).
extends TestCase

const EMAILS := "duty_emails_r1"
const INVOICES := "duty_invoices_r5"
const PAYSLIPS := "duty_payslips_r6"
const PERSONNEL := "duty_personnel_files_r9"
const TICKETS := "duty_it_tickets_r12"
const AREA_REPORT := "duty_monthly_area_report_r22"
const HR_TURNOVER := "duty_turnover_hiring_r23"
const QUARTERLY := "duty_quarterly_results_r28"
const MAIL_ROUND := "duty_mail_round_r4"
const GUARD_ROUND := "duty_guard_round_morning_r10"
const CLOSING_ROUND := "duty_closing_round_r10"
const ERRANDS := "duty_errands_r0"
const LINE_QUOTA := "duty_line_units_r3"
const CAMPAIGN := "duty_campaign_pieces_r11"
const WING_QUOTA := "duty_wing_performance_r15"
const GEORGE := "npc_george_penn"
const SONIA := "npc_sonia_vail"
const CEO := "npc_harlan_voss"
const WING_CHIEF := "npc_bernard_lasker"
const LOTTERY_TRIALS := 10000
## Jornada que cierra mes (20) y trimestre (25) a la vez: se asignan R22 (mensual) y R28 (trimestral).
const PERIOD_END_DAY := 100
const EPS := 0.0001

var _ds: DutySystem
var _progress: Array = []
var _completed: Array = []
var _failed: Array = []
var _warned: Array = []
var _assists: Array = []
var _notes: Array = []
var _records: Array = []
var _game_overs: Array = []


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	GameClock.set_time(1, 9, 0)
	_connect_signals()
	_ds = DutySystem.new()
	add_child(_ds)
	_ds.set_witness_provider(func() -> Array: return [])
	_check_session_scope()
	_check_r1_emails_honest()
	_check_r1_emails_assist()
	_check_partial_assist()
	_check_lottery()
	_ds.set_witness_provider(Callable())
	_check_detection()
	_check_viability()
	_check_rounds()
	_check_quota_theft()
	_check_material()
	_check_delegation()
	_check_save_load()
	_check_consequence_execution()
	_check_failure_escalation()


func _connect_signals() -> void:
	EventBus.duty_progressed.connect(func(id: String, p: float) -> void: _progress.append([id, p]))
	EventBus.duty_completed.connect(func(id: String, q: float, m: String) -> void:
		_completed.append([id, q, m]))
	EventBus.duty_failed.connect(func(id: String, c: String) -> void: _failed.append([id, c]))
	EventBus.duty_deadline_warned.connect(func(id: String, h: float) -> void:
		_warned.append([id, h]))
	EventBus.assist_used.connect(func(t: String, r: String) -> void: _assists.append([t, r]))
	EventBus.notebook_entry_added.connect(func(c: String, k: String, a: Array) -> void:
		_notes.append([c, k, a]))
	EventBus.record_created.connect(func(id: String, t: String, w: float) -> void:
		_records.append([id, t, w]))
	EventBus.game_over.connect(func(cause: String, ending: String, _s: Dictionary) -> void:
		_game_overs.append([cause, ending]))


# ─── Ayudas ─────────────────────────────────────────────────────────────

## Personaje sintético (fuera de NPCDirector) para las funciones puras.
func _npc(id: String, archetype: String, perception: int, ambition: int) -> NPCRuntime:
	var npc: NPCRuntime = NPCRuntime.new()
	npc.id = id
	npc.name = id
	npc.archetype = archetype
	npc.traits["perception"] = perception
	npc.traits["ambition"] = ambition
	return npc


## El jugador ocupa `occupation_id` a la hora dada: PlayerState monta sus deberes de hoy.
func _become(occupation_id: String, hour: int = 9) -> void:
	GameClock.set_time(GameClock.get_day(), hour, 0)
	PlayerState.set_occupation(occupation_id, "test")


func _player_to(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)


## Una sala sin nadie (para controlar quién presencia un fallo de A.S.S.I.S.T.).
func _quiet_room(skip: String = "") -> String:
	for room: RoomData in Database.get_all_rooms():
		if room.floor != RoomData.TRANSVERSAL_FLOOR and room.id != skip \
				and NPCDirector.get_npcs_in_room(room.id).is_empty():
			return room.id
	return ""


func _session_ids() -> Array[String]:
	var out: Array[String] = []
	for session: Dictionary in _ds.get_sessions():
		out.append(str(session["duty_id"]))
	return out


# ─── Alcance: solo los deberes de hoy del jugador ───────────────────────

func _check_session_scope() -> void:
	check_eq(PlayerState.get_occupation_id(), "email_worker_3b", "the run starts at R1")
	check_eq(_session_ids(), [EMAILS] as Array[String], "one session: today's emails")
	check(not _ds.register_duty(INVOICES), "another post's duty is not the player's")
	var foreign: Dictionary = _ds.start_duty(INVOICES)
	check_eq(foreign["error"], DutySystem.ERR_UNKNOWN_DUTY, "foreign duty -> unknown_duty")
	check_eq(foreign["error_key"], "DUTY_ERR_UNKNOWN_DUTY", "... 'not on today's list'")


# ─── §10.6: R1, ocho correos = 45 min; con A.S.S.I.S.T. = 5 min ────────

func _check_r1_emails_honest() -> void:
	var info: Dictionary = _ds.start_duty(EMAILS)
	check(info["ok"], "R1 emails duty opens")
	check_eq(info["amount"], 8, "R1: eight emails")
	check_eq(info["honest_minutes"], 45, "R1: eight emails cost 45 game minutes honestly")
	check_eq(info["assist_minutes"], 5, "R1: 5 minutes with A.S.S.I.S.T.")
	var before: float = GameClock.get_total_minutes()
	var steps: Array[int] = []
	_progress.clear()
	for i: int in 8:
		var email: Dictionary = _ds.get_unit_content(EMAILS)
		check(email.has("subject_key") and email.has("correct_reply"), "email %d has content" % i)
		var answer: int = int(email.get("correct_reply", 0))
		steps.append(int(_ds.submit_unit(EMAILS, answer)["minutes"]))
	check_near(GameClock.get_total_minutes() - before, 45.0, EPS,
			"answering 8 emails advanced the clock exactly 45 game minutes")
	check(steps.min() >= 5 and steps.max() <= 6, "each email costs its share (45/8 ≈ 5.6 min)")
	var session: Dictionary = _ds.get_session(EMAILS)
	check_eq(session["minutes_spent"], 45, "session accounts 45 minutes")
	check_eq(session["status"], DutySystem.STATUS_COMPLETED, "8/8 emails complete the duty")
	check_eq(_completed.back(), [EMAILS, 1.0, "honest"], "duty_completed(id, 1.0, honest)")
	check_eq(_progress.size(), 8, "duty_progressed once per email")
	check_near(float(_progress.back()[1]), 1.0, EPS, "progress reaches 1.0")
	check_eq(PlayerState.get_duty(EMAILS).get("status", ""), "completed",
			"PlayerState records the duty as completed")
	check_eq(_ds.submit_unit(EMAILS)["error"], DutySystem.ERR_ALREADY_RESOLVED,
			"a closed duty takes no more work")


func _check_r1_emails_assist() -> void:
	GameClock.advance_to_next_day()
	check(_ds.get_session(EMAILS).get("day", 0) == GameClock.get_day(),
			"a new day opens a fresh emails session")
	var uses: int = _ds.get_assist_count()
	var before: float = GameClock.get_total_minutes()
	var result: Dictionary = _ds.use_assist(EMAILS)
	check(result["ok"], "A.S.S.I.S.T. accepts the emails")
	check_eq(result["minutes"], 5, "A.S.S.I.S.T. does the 8 emails in 5 minutes")
	check_near(GameClock.get_total_minutes() - before, 5.0, EPS, "the clock advanced 5 minutes")
	check_eq(result["method"], "assist", "method assist")
	check(result["completed"], "the duty is done (acceptable/excellent/unnoticed failure)")
	check_eq(_assists.back(), ["emails", result["outcome"]], "assist_used(task_type, result)")
	check_eq(_ds.get_assist_count(), uses + 1, "every use adds to the digital log")
	check_eq(_ds.get_assist_log().back()["task_type"], "emails", "log readable by IT")


func _check_partial_assist() -> void:
	_become("billing_clerk")
	check_eq(_session_ids(), [INVOICES] as Array[String],
			"a new post replaces the old post's sessions")
	var honest: Dictionary = _ds.submit_units(INVOICES, 15)
	check_eq(honest["minutes"], 30, "15/30 invoices honestly = 30 of 60 minutes")
	var assisted: Dictionary = _ds.apply_assist_outcome(INVOICES, DutySystem.ASSIST_ACCEPTABLE)
	check_eq(assisted["minutes"], 8, "A.S.S.I.S.T. charges 15 min x the pending half (7.5 -> 8)")
	check_near(float(assisted["quality"]), 0.6, EPS, "acceptable quality")


func _check_lottery() -> void:
	var counts: Dictionary = {"acceptable": 0, "excellent": 0, "evident_failure": 0}
	for i: int in LOTTERY_TRIALS:
		var outcome: String = _ds.roll_assist()
		counts[outcome] = int(counts[outcome]) + 1
	check_near(float(counts["acceptable"]) / LOTTERY_TRIALS, 0.60, 0.02, "acceptable ~60%")
	check_near(float(counts["excellent"]) / LOTTERY_TRIALS, 0.25, 0.02, "excellent ~25%")
	check_near(float(counts["evident_failure"]) / LOTTERY_TRIALS, 0.15, 0.015,
			"evident failure ~15%")
	var bands: Array[String] = []
	for roll: float in [0.0, 0.1499, 0.15, 0.3999, 0.4, 0.9999]:
		bands.append(DutySystem.assist_outcome_for_roll(roll))
	var expected: Array[String] = ["evident_failure", "evident_failure", "excellent", "excellent",
			"acceptable", "acceptable"]
	check_eq(bands, expected, "exact bands: [0, .15) failure, [.15, .40) excellent, rest acceptable")
	GameClock.set_time(PERIOD_END_DAY, 9, 0)
	_become("floor10_general_director")
	check_eq(_session_ids(), [AREA_REPORT] as Array[String], "month end: the monthly report is due")
	var info: Dictionary = _ds.start_duty(AREA_REPORT)
	check(info["assist_high_risk"], "R22 report is flagged as risky for the UI")
	check_eq(DutySystem.assist_outcome_for_roll(0.2), "excellent",
			"... but the lottery is the same 60/25/15 for every duty (§10.4)")


func _check_detection() -> void:
	_set_player_reputation(50.0)
	var room: String = _quiet_room()
	_become("payroll_clerk", 10)
	NPCDirector.set_current_location(GEORGE, room)
	_player_to(room)
	_records.clear()
	var caught: Dictionary = _ds.apply_assist_outcome(PAYSLIPS, DutySystem.ASSIST_FAILURE)
	check_eq(caught["detected_by"], GEORGE,
			"George (perception 84 > 60) in the player's room detects the evident failure")
	check_near(float(caught["reputation_delta"]), -6.0, EPS, "detected failure costs reputation")
	check_near(PlayerState.get_reputation(), 44.0, EPS, "PlayerState reputation 50 -> 44")
	check(caught["annotated"], "detected failure is annotated in the personnel file")
	check(_records.size() == 1 and _records[0][1] == "stamped_document",
			"the annotation is a permanent record in BeliefNet")
	check_eq(_notes.back()[1], "NOTE_ASSIST_DETECTED", "notebook entry for the detection")
	var other: String = _quiet_room(room)
	_become("hr_assistant", 10)
	NPCDirector.set_current_location(SONIA, other)
	_player_to(other)
	var unseen: Dictionary = _ds.apply_assist_outcome(PERSONNEL, DutySystem.ASSIST_FAILURE)
	check_eq(unseen["detected_by"], "", "Sonia (perception 32) does not notice")
	check(not unseen["annotated"], "no annotation when nobody notices")
	check(DutySystem.perceptive_witness([_npc("p60", "snitch", 60, 50)] as Array[NPCRuntime])
			== null, "perception 60 is not > 60")
	check(DutySystem.perceptive_witness([_npc("p61", "snitch", 61, 50)] as Array[NPCRuntime])
			!= null, "perception 61 is > 60")
	_become("it_technician", 10)
	NPCDirector.set_current_location(GEORGE, room)
	_player_to(room)
	var fine: Dictionary = _ds.apply_assist_outcome(TICKETS, DutySystem.ASSIST_ACCEPTABLE)
	check_eq(fine["detected_by"], "", "an acceptable result gives nothing away")


func _set_player_reputation(value: float) -> void:
	PlayerState.modify_reputation(value - PlayerState.get_reputation(), "test")


# ─── §10.3: escala de viabilidad honesta ────────────────────────────────

func _check_viability() -> void:
	check_eq(_ds.get_honest_minutes(AREA_REPORT), 1200,
			"R22 monthly report: 240 min x 5 when honest_viable=false")
	check_eq(_ds.get_honest_minutes(HR_TURNOVER), 750, "R23: 150 x 5 = 750 min")
	var report: Dictionary = _ds.get_viability_report([AREA_REPORT])
	check_eq(report["workday_minutes"], 660, "an office day is 11 hours")
	check(not report["viable_in_workday"], "the R22 report cannot be done honestly in a day")
	check(_ds.get_viability_report([EMAILS])["viable_in_workday"], "R1 emails are honestly viable")
	var bands: Array[String] = []
	for tier: int in range(1, 9):
		bands.append(_ds.get_viability_band(tier))
	var expected: Array[String] = ["viable", "viable", "full_day", "full_day", "needs_help",
			"needs_help", "impossible", "impossible"]
	check_eq(bands, expected, "§10.3 bands by tier")
	check(_ds.is_honest_possible(6) and not _ds.is_honest_possible(7), "tiers 7-8: never alone")
	_check_difficulty_margin()
	_become("cfo")
	check_eq(_ds.submit_unit(QUARTERLY)["error"], DutySystem.ERR_NOT_VIABLE,
			"R28 quarterly results refuse honest solo work")
	check_eq(_ds.use_assist(QUARTERLY)["error"], DutySystem.ERR_NOT_AUTOMATABLE,
			"R28 quarterly results: A.S.S.I.S.T. not applicable")
	check_eq(_ds.can_delegate(QUARTERLY), "", "R28 is force-delegatable for the CFO")
	check_eq(_ds.get_viability_report()["honest_minutes"], _ds.get_honest_minutes(QUARTERLY),
			"the default report sums only the player's duties of today")


## §15.7: el margen alivia lo viable; lo estructuralmente inviable no cambia en ningún preset.
func _check_difficulty_margin() -> void:
	Database.set_difficulty_preset("interno")
	check_eq(_ds.get_honest_minutes(EMAILS), 30, "interno: 45 / 1.5 = 30 min of emails")
	check_eq(_ds.get_honest_minutes(AREA_REPORT), 1200, "interno: R22 still 1200 min")
	check(not _ds.get_viability_report([HR_TURNOVER])["viable_in_workday"],
			"interno: R23 still exceeds the workday (750 > 660)")
	Database.set_difficulty_preset("auditoria")
	check_eq(_ds.get_honest_minutes(EMAILS), 64, "auditoria: 45 / 0.7 = 64 min of emails")
	Database.set_difficulty_preset("estandar")
	check_eq(_ds.get_honest_minutes(EMAILS), 45, "estandar: the §10.6 figure")


# ─── §10.2: rondas (coartada) ───────────────────────────────────────────

func _check_rounds() -> void:
	_become("mail_courier")
	var info: Dictionary = _ds.start_duty(MAIL_ROUND)
	var waypoints: Array = info["waypoints"]
	check(waypoints.size() >= 9, "mail round has its stops from duties.json")
	check(_ds.is_on_round(), "a started round is an alibi")
	check(_ds.is_room_on_round("hr_office"), "rooms on the route are covered by the alibi")
	check_eq(_ds.submit_unit(MAIL_ROUND)["error"], DutySystem.ERR_WRONG_INTERFACE,
			"rounds are walked, not clicked")
	var material: Dictionary = _ds.submit_with_material(MAIL_ROUND, "area_report_drafts")
	check_eq(material["error_key"], "DUTY_ERR_NOT_DELIVERY", "material only feeds deliveries")
	_ds.visit_room("ceo_office")
	check_eq(_ds.get_session(MAIL_ROUND)["done"], 0, "an off-route room does not count")
	_player_to(str(waypoints[0]["room"]))
	check_eq(_ds.get_session(MAIL_ROUND)["done"], 1, "the player's room_entered advances the round")
	for i: int in range(1, waypoints.size()):
		_ds.visit_room(str(waypoints[i]["room"]))
	check_eq(_ds.get_session(MAIL_ROUND)["status"], DutySystem.STATUS_COMPLETED,
			"visiting every stop in order completes the round")
	check(not _ds.is_on_round(), "a finished round no longer covers the player")
	_check_guard_rounds()
	_check_errands()


func _check_guard_rounds() -> void:
	_become("security_guard")
	var guard: Array = _ds.start_duty(GUARD_ROUND)["waypoints"]
	for i: int in 3:
		_ds.visit_room(str(guard[i]["room"]))
	_ds.visit_room("corridors_low@3")
	check_eq(_ds.get_session(GUARD_ROUND)["done"], 3, "a corridor on another floor is not the stop")
	_ds.visit_room("corridors_low@1")
	check_eq(_ds.get_session(GUARD_ROUND)["done"], 4, "transversal stop matched by id@floor")
	var closing: Dictionary = _ds.start_duty(CLOSING_ROUND)
	check(closing["closing"] and not closing["closing_open"],
			"the closing round cannot start while the building is busy")
	var stops: Array = closing["waypoints"]
	_ds.visit_room(str(stops[0]["room"]))
	check_eq(_ds.get_session(CLOSING_ROUND)["done"], 0, "before closing time the stops do not count")
	GameClock.set_time(GameClock.get_day(), Database.get_balance_int("tiempo.hora_fin_jornada"), 0)
	for stop: Variant in stops:
		_ds.visit_room(str((stop as Dictionary)["room"]))
	var done: Dictionary = _ds.get_session(CLOSING_ROUND)
	check_eq(done["status"], DutySystem.STATUS_COMPLETED, "the last one out closes the building")
	check_eq(done["steps_done"], ["be_last_out", "lock_up", "shut_down_machinery"],
			"the three closing steps are done")


func _check_errands() -> void:
	_become("eternal_intern")
	var route: Array = _ds.start_duty(ERRANDS)["waypoints"]
	var pool: Array = []
	for stop: Variant in Database.get_round_waypoint_set("errands")["waypoints"]:
		pool.append(str((stop as Dictionary)["room"]))
	var rooms: Dictionary = {}
	var from_pool: bool = true
	for stop: Variant in route:
		rooms[str((stop as Dictionary)["room"])] = true
		from_pool = from_pool and pool.has(str((stop as Dictionary)["room"]))
	check_eq(route.size(), 4, "errands: random_subset draws 4 of the 5 stops")
	check(rooms.size() == 4 and from_pool, "four distinct stops of the errands set")
	for stop: Variant in route:
		_ds.visit_room(str((stop as Dictionary)["room"]))
	check_eq(_ds.get_session(ERRANDS)["status"], DutySystem.STATUS_COMPLETED,
			"running the drawn errands completes the day")


# ─── §10.2: cuota y entrega ─────────────────────────────────────────────

func _check_quota_theft() -> void:
	_become("line_operator")
	check_eq(_ds.submit_units(LINE_QUOTA, 10)["minutes"], 10, "10/120 units = 10 of 120 minutes")
	EventBus.crime_committed.emit("theft_product", "assembly_line", {"quantity": 4})
	var session: Dictionary = _ds.get_session(LINE_QUOTA)
	check_eq(session["done"], 6, "stolen product comes out of the own quota")
	check_near(float(PlayerState.get_duty(LINE_QUOTA)["progress"]), 6.0 / 120.0, EPS,
			"PlayerState progress drops with the theft")
	var before: float = GameClock.get_total_minutes()
	var redo: Dictionary = _ds.submit_units(LINE_QUOTA, 4)
	check_eq(redo["minutes"], 4, "redoing the 4 stolen units costs their share again")
	check_near(GameClock.get_total_minutes() - before, 4.0, EPS, "the clock advanced 4 minutes")
	check_eq(_ds.get_session(LINE_QUOTA)["minutes_spent"], 14, "14 minutes for 10 units kept")


func _check_material() -> void:
	_become("marketing_creative")
	check_eq(_ds.submit_with_material(CAMPAIGN, "area_report_drafts")["error"],
			DutySystem.ERR_NO_MATERIAL, "no material in the inventory -> rejected")
	var idea_id: String = IdeaPool.generate_idea(GEORGE, "marketing")
	check(IdeaPool.acquire(idea_id, IdeaPool.METHOD_PURCHASE), "the player buys George's idea")
	var quality: float = float(IdeaPool.get_idea(idea_id).quality) / 100.0
	var result: Dictionary = _ds.submit_with_material(CAMPAIGN, idea_id)
	check(result["completed"], "a stolen idea completes the delivery")
	check_eq(result["method"], "stolen_material", "method stolen_material")
	check_near(float(result["quality"]), quality, EPS, "quality comes from the stolen idea")
	check(IdeaPool.get_idea(idea_id).presented, "the idea is spent in the report")


# ─── §10.5: delegación ──────────────────────────────────────────────────

func _check_delegation() -> void:
	var burnout: NPCRuntime = _npc("npc_test_burnout", "burnout", 40, 10)
	var sharp: NPCRuntime = _npc("npc_test_competent", "climber", 90, 90)
	check_near(_ds.delegation_failure_probability(burnout), 0.8, EPS,
			"delegating to a burnout fails with high probability")
	check_near(_ds.subordinate_competence(sharp), 0.9, EPS, "competence from perception+ambition")
	check_near(_ds.delegation_failure_probability(sharp), 0.05, EPS,
			"a competent subordinate rarely fails (0.5 x (1 - 0.9))")
	var severities: Array[int] = []
	for i: int in 3:
		severities.append(_ds.record_delegation("npc_test_overworked"))
	check_eq(severities, [1, 1, 1] as Array[int],
			"each delegation adds the same grievance: the total grows with frequency")
	check_eq(_ds.get_delegation_count("npc_test_overworked"), 3, "frequency in the window")
	_become("email_worker_3b")
	check_eq(_ds.can_delegate(EMAILS), DutySystem.ERR_TIER_TOO_LOW, "R1 has nobody below")
	_check_wing_chief_delegation()
	_become("cfo")
	check(_ds.is_subordinate(NPCDirector.get_npc(GEORGE)), "for the CFO the whole house is below")
	check(not _ds.is_subordinate(NPCDirector.get_npc(CEO)), "... except the CEO")


func _check_wing_chief_delegation() -> void:
	_become("wing_3b_chief")
	check_eq(PlayerState.get_tier(), 4, "wing chief is tier 4")
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	check(_ds.is_subordinate(george), "a 3B clerk works under the wing chief")
	check(not _ds.is_subordinate(NPCDirector.get_npc(CEO)), "the CEO is nobody's subordinate")
	check(not _ds.is_subordinate(NPCDirector.get_npc(WING_CHIEF)), "same tier: not a subordinate")
	check(not _ds.is_subordinate(_npc("npc_ghost", "climber", 90, 90)),
			"only real staff (NPCDirector) can take the work")
	var to_ceo: Dictionary = _ds.delegate(WING_QUOTA, CEO)
	check_eq(to_ceo["error"], DutySystem.ERR_INVALID_SUBORDINATE, "delegating upwards is refused")
	var subordinates: Array[NPCRuntime] = _ds.get_subordinates()
	check(subordinates.has(george) and subordinates.all(
			func(n: NPCRuntime) -> bool: return n.tier < 4), "subordinates are all below tier 4")
	var grievance_before: int = NPCDirector.get_grievance_total(GEORGE)
	var competence: float = _ds.subordinate_competence(george)
	var result: Dictionary = _ds.delegate(WING_QUOTA, GEORGE)
	check(result["ok"], "tier 4 delegates the wing quota to George")
	check_near(float(result["failure_probability"]), 0.5 * (1.0 - competence), EPS,
			"failure probability from George's competence")
	check_eq(NPCDirector.get_grievance_total(GEORGE) - grievance_before, 1,
			"George's grievance grows by one delegation")
	check_eq(str(george.schedule_override.get(GameClock.get_current_band(), "")), george.home_room,
			"the work consumes George's time at his desk")
	var expected_status: String = DutySystem.STATUS_FAILED if result["failed"] \
			else DutySystem.STATUS_COMPLETED
	check_eq(result["status"], expected_status, "delegation outcome closes the duty")
	if not result["failed"]:
		check_eq(result["method"], "delegated", "method delegated")
		check_near(float(result["quality"]), competence, EPS, "quality = subordinate competence")


func _check_save_load() -> void:
	var saved: Variant = JSON.parse_string(JSON.stringify(_ds.save_state()))
	var copy: DutySystem = DutySystem.new()
	add_child(copy)
	copy.load_state(saved as Dictionary)
	check_eq(copy.get_sessions(), _ds.get_sessions(), "sessions restored")
	check_eq(copy.get_assist_count(), _ds.get_assist_count(), "assist log restored")
	var a: Array[String] = []
	var b: Array[String] = []
	for i: int in 5:
		a.append(_ds.roll_assist())
		b.append(copy.roll_assist())
	check_eq(b, a, "RNG stream restored")
	remove_child(copy)
	copy.free()


# ─── Consecuencias: aviso → descenso → expulsión ────────────────────────

func _check_consequence_execution() -> void:
	_notes.clear()
	var logged: int = _ds.get_consequence_log().size()
	check_eq(_ds.execute_consequence(EMAILS, "warning"), "warning", "warning executed")
	check_eq(_notes.back()[1], "NOTE_DUTY_WARNING", "warning goes to the notebook")
	check_eq(_notes.back()[2], ["DUTY_EMAILS_R1"], "the duty name travels as a key (tr at display)")
	check_eq(_ds.execute_consequence(EMAILS, "none"), "none", "no consequence, nothing to do")
	check_eq(_ds.get_consequence_log().size(), logged + 1, "only real consequences are logged")


## Un fallo al día: 1 → aviso, 2 → aviso, 3 → descenso (R1 → R0), 4 → expulsión, porque el recado
## del becario (R0) tiene fail_penalty "expulsion" como suelo (con R1 habría sido descenso hasta
## el 5.º fallo).
func _check_failure_escalation() -> void:
	new_run()
	_ds.reset_for_new_run()
	_game_overs.clear()
	_warned.clear()
	var failures: Array = []
	for day: int in 6:
		if not _game_overs.is_empty():
			break
		_failed.clear()
		GameClock.advance_minutes(18.0 * 60.0 - GameClock.get_day_minutes())
		failures.append_array(_failed)
		if _game_overs.is_empty():
			GameClock.advance_to_next_day()
	var consequences: Array[String] = []
	for entry: Array in failures:
		consequences.append(str(entry[1]))
	check_eq(consequences, ["warning", "warning", "demotion", "expulsion"] as Array[String],
			"one failure a day: warning, warning, demotion, expulsion")
	check_eq(Database.get_balance_int("deberes.fallos_para_aviso"), 1, "1st failure: warning")
	check_eq(Database.get_balance_int("deberes.fallos_para_descenso"), 3, "3rd failure: demotion")
	check(failures.size() == 4 and failures[3][0] == ERRANDS
			and _duty_definition(ERRANDS).get("fail_penalty", "") == "expulsion",
			"4th failure is the R0 errands, whose fail_penalty floors it to expulsion")
	check(not _warned.is_empty() and absf(float(_warned[0][1]) - 1.0) < 0.01,
			"one hour before the deadline the duty is warned (§15.6)")
	check_eq(_game_overs.size(), 1, "expulsion ends the run once")
	check(not _game_overs.is_empty() and _game_overs[0][0] == "failed_at_r0",
			"expelled at R0 -> failed_at_r0")
	check(not _game_overs.is_empty()
			and _game_overs[0][1] == Tracking.evaluate_ending_for_cause("failed_at_r0"),
			"the ending is evaluated for the terminal cause")
	check_eq(_ds.get_consequence_log().size(), consequences.size(),
			"DutySystem executed every consequence PlayerState decided")
	_check_game_over_listener()


## Otro sistema (Company al degradar en R0) ya terminó la partida: este nodo no la termina otra vez.
func _check_game_over_listener() -> void:
	var watcher: DutySystem = DutySystem.new()
	add_child(watcher)
	EventBus.game_over.emit("test_other_system", "", {})
	_game_overs.clear()
	watcher.execute_consequence(ERRANDS, "expulsion")
	check(_game_overs.is_empty(), "after another system's game_over, DutySystem never ends it again")
	remove_child(watcher)
	watcher.free()


func _duty_definition(duty_id: String) -> Dictionary:
	for occupation: OccupationData in Database.get_all_occupations():
		var duty: Dictionary = occupation.get_duty(duty_id)
		if not duty.is_empty():
			return duty
	return {}
