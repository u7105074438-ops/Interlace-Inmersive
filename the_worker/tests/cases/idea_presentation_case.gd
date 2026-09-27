# idea_presentation_case.gd — Cuerpo de test_idea_presentation: mérito, los tres resultados del choque y sus consecuencias (§11.2, §21).
# PROPIETARIO DE: nada.
# ESCUCHA: idea_contested, idea_presented, aurora_meeting_started, assist_used (conexiones del caso).
extends TestCase

const OWNER := "npc_claudia_reeves"
const WITNESS_A := "npc_debbie_foyle"
const WITNESS_B := "npc_george_penn"
const BELIEVER_A := "npc_sonia_vail"
const BELIEVER_B := "npc_ray_cudmore"
const ABSENT_OWNER := "npc_amelia_cole"
const SELLER := "npc_bernard_lasker"
const EPS := 0.0001
const SUSPICION_EPS := 0.01

var _contested: Array = []
var _presented: Array = []
var _meetings: Array = []
var _assists: Array = []


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	GameClock.set_time(1, 10, 0)
	_connect_signals()
	_check_merit_formula()
	_check_credibility_formulas()
	_check_weekly_schedule()
	IdeaPool.reset_for_new_run()
	IdeaPool.start_meeting()
	_check_win()
	_check_tie()
	_check_loss()
	_check_uncontested()
	_check_preparation()
	IdeaPool.close_meeting()
	var late: Dictionary = IdeaPool.present(_stolen_idea(BELIEVER_A))
	check_eq(late["status"], IdeaPool.STATUS_NO_MEETING, "ideas are only presented at a meeting")


func _connect_signals() -> void:
	EventBus.idea_contested.connect(func(id: String, accuser: String, result: String) -> void:
		_contested.append([id, accuser, result]))
	EventBus.idea_presented.connect(func(id: String, who: String, merit: int) -> void:
		_presented.append([id, who, merit]))
	EventBus.aurora_meeting_started.connect(func(meeting_id: String) -> void:
		_meetings.append(meeting_id))
	EventBus.assist_used.connect(func(task: String, quality: String) -> void:
		_assists.append([task, quality]))


func _check_merit_formula() -> void:
	# mérito = calidad × factor × (0,7 + 0,3 × reputación / 100)
	check_eq(IdeaPresentation.compute_merit(80, IdeaPresentation.PREP_NONE, 50.0), 41,
			"80 x 0.6 x 0.85 = 40.8 -> 41 (no preparation)")
	check_eq(IdeaPresentation.compute_merit(80, IdeaPresentation.PREP_ASSIST, 50.0), 54,
			"80 x 0.8 x 0.85 = 54.4 -> 54 (A.S.S.I.S.T.)")
	check_eq(IdeaPresentation.compute_merit(80, IdeaPresentation.PREP_REAL, 50.0), 68,
			"80 x 1.0 x 0.85 = 68 (real preparation)")
	check_eq(IdeaPresentation.compute_merit(80, IdeaPresentation.PREP_NONE, 0.0), 34,
			"reputation 0 keeps 70% (80 x 0.6 x 0.7 = 33.6 -> 34)")
	check_eq(IdeaPresentation.compute_merit(80, IdeaPresentation.PREP_REAL, 100.0), 80,
			"reputation 100 keeps 100%")


func _check_credibility_formulas() -> void:
	check_near(IdeaPresentation.accuser_credibility(40.0, 2), 80.0, EPS,
			"accuser = reputation + 20 x believers")
	check_near(IdeaPresentation.player_credibility(50.0, 2, 20.0), 70.0, EPS,
			"player = reputation + 15 x allies - 0.5 x suspicion")
	check_eq(IdeaPresentation.classify(21.0), IdeaPresentation.RESULT_WIN, "+21 -> win")
	check_eq(IdeaPresentation.classify(20.0), IdeaPresentation.RESULT_TIE, "+20 -> tie")
	check_eq(IdeaPresentation.classify(0.0), IdeaPresentation.RESULT_TIE, "0 -> tie")
	check_eq(IdeaPresentation.classify(-20.0), IdeaPresentation.RESULT_TIE, "-20 -> tie")
	check_eq(IdeaPresentation.classify(-21.0), IdeaPresentation.RESULT_LOSS, "-21 -> loss")


func _check_weekly_schedule() -> void:
	IdeaPool.reset_for_new_run()
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	check_eq(schedule["room"], "aurora_room", "meetings happen in aurora_room (P12)")
	var day: int = IdeaPool.get_next_meeting_day(1)
	check(IdeaPool.is_meeting_day(day) and not IdeaPool.is_meeting_day(day + 1),
			"one meeting day per week")
	check_eq(IdeaPool.get_next_meeting_day(day + 1),
			day + Database.get_balance_int("tiempo.jornadas_por_semana"), "weekly cadence")
	var id: String = IdeaPool.generate_for_npc(OWNER)
	IdeaPool.process_hour(int(schedule["hour"]) - 1, day)
	check(not IdeaPool.is_meeting_open(), "no meeting before its hour")
	IdeaPool.process_hour(int(schedule["hour"]), day)
	check(IdeaPool.is_meeting_open(), "the clock opens the weekly meeting")
	check_eq(_meetings.back(), "aurora_d%d" % day, "aurora_meeting_started(meeting_id)")
	var attended: bool = IdeaPool.get_meeting_attendees().has(OWNER)
	IdeaPool.process_hour(int(schedule["hour"]) + int(schedule["duration_hours"]), day)
	check(not IdeaPool.is_meeting_open(), "the meeting closes after its duration")
	check_eq(IdeaPool.get_idea(id).presented, attended,
			"an attending owner presents their idea at the close (ambition roll)")


## Idea de `owner` en poder del jugador (escuchada) con el propietario y dos testigos en la sala.
func _stolen_idea(owner: String) -> String:
	var id: String = IdeaPool.generate_idea(owner, "design")
	IdeaPool.acquire(id, IdeaPool.METHOD_OVERHEAR)
	return id


func _seat_owner_and_witnesses(owner: String) -> void:
	IdeaPool.add_meeting_attendee(owner)
	IdeaPool.add_meeting_attendee(WITNESS_A)
	IdeaPool.add_meeting_attendee(WITNESS_B)


func _effects_of(result: Dictionary, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Dictionary in result.get("effects", []):
		if effect.get("kind", "") == kind:
			out.append(effect)
	return out


func _check_win() -> void:
	var id: String = _stolen_idea(OWNER)
	_seat_owner_and_witnesses(OWNER)
	var quality: int = IdeaPool.get_idea(id).quality
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 60.0, "player_suspicion": 0.0, "allies": 1,
		"accuser_reputation": 40.0, "believers": 0})
	check(result["contested"], "win: the owner is alive and present, so they accuse")
	check_eq(result["contest_result"], IdeaPresentation.RESULT_WIN, "75 vs 40 -> player wins")
	check_near(float(result["player_credibility"]), 75.0, EPS, "win: player credibility 75")
	check_near(float(result["accuser_credibility"]), 40.0, EPS, "win: accuser credibility 40")
	var merit: int = IdeaPresentation.compute_merit(quality, IdeaPresentation.PREP_NONE, 60.0)
	check_eq(result["merit"], merit, "win: the idea is the player's and earns full merit")
	check(IdeaPool.get_idea(id).presented, "win: the idea is spent")
	check_eq(_contested.back(), [id, OWNER, "win"], "idea_contested(id, owner, win)")
	check_eq(_presented.back(), [id, "player", merit], "idea_presented(id, player, merit)")
	var rep: Array[Dictionary] = _effects_of(result, "npc_reputation")
	check_eq(rep.size(), 1, "win: the accuser is branded a usurper")
	if not rep.is_empty():
		check_eq(rep[0]["npc_id"], OWNER, "usurper = the accuser")
		check_near(float(rep[0]["delta"]), -15.0, EPS, "usurper reputation -15")
	var merits: Array[Dictionary] = _effects_of(result, "merit")
	check(merits.size() == 1 and int(merits[0]["amount"]) == merit, "merit registered in Company")


func _check_tie() -> void:
	var id: String = _stolen_idea(OWNER)
	_seat_owner_and_witnesses(OWNER)
	var suspicion_before: float = BeliefNet.calculate_player_suspicion()
	var presented_before: int = _presented.size()
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 50.0, "player_suspicion": 20.0, "allies": 0,
		"accuser_reputation": 45.0, "believers": 0})
	check_eq(result["contest_result"], IdeaPresentation.RESULT_TIE, "40 vs 45 -> tie")
	check_eq(result["merit"], 0, "tie: nobody gets merit")
	check_eq(_presented.size(), presented_before, "tie: no idea_presented")
	check(IdeaPool.get_idea(id).presented, "tie: the idea is burnt")
	check_eq(_contested.back(), [id, OWNER, "tie"], "idea_contested(id, owner, tie)")
	var records: Array[Dictionary] = _effects_of(result, "suspicion_record")
	check_eq(records.size(), 2, "tie: suspicion rises for both parties")
	var subjects: Array = []
	for record: Dictionary in records:
		subjects.append(record["subject"])
		check_near(float(record["points"]), 10.0, EPS, "tie: +10 suspicion points each")
		check(not str(record["record_id"]).is_empty(), "tie: minutes recorded in BeliefNet")
	check(subjects.has("player") and subjects.has(OWNER), "tie: player and accuser both marked")
	check_near(BeliefNet.calculate_player_suspicion() - suspicion_before, 10.0, SUSPICION_EPS,
			"tie: the player's suspicion rises exactly 10 points")


func _check_loss() -> void:
	var id: String = _stolen_idea(OWNER)
	_seat_owner_and_witnesses(OWNER)
	IdeaPool.share_idea(id, BELIEVER_A)
	IdeaPool.share_idea(id, BELIEVER_B)
	var believers: int = IdeaPresentation.count_believers(IdeaPool.get_idea(id))
	check(believers >= 2, "colleagues told about the idea believe it was the owner's")
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 30.0, "player_suspicion": 40.0, "allies": 0,
		"accuser_reputation": 40.0})
	check_eq(result["contest_result"], IdeaPresentation.RESULT_LOSS, "10 vs 80+ -> player loses")
	check_near(float(result["accuser_credibility"]), 40.0 + 20.0 * believers, EPS,
			"loss: accuser credibility counts 20 per believer")
	check_near(float(result["player_credibility"]), 10.0, EPS, "loss: 30 - 0.5 x 40 = 10")
	check_eq(result["merit"], 0, "loss: no merit")
	var idea: Idea = IdeaPool.get_idea(id)
	check(idea.acquired_by.is_empty() and not idea.presented, "loss: the idea reverts to its owner")
	check_eq(_contested.back(), [id, OWNER, "loss"], "idea_contested(id, owner, loss)")
	var rep: Array[Dictionary] = _effects_of(result, "player_reputation")
	check(rep.size() == 1 and absf(float(rep[0]["delta"]) + 20.0) < EPS, "loss: reputation -20")
	_check_steals_ideas_beliefs(result)


func _check_steals_ideas_beliefs(result: Dictionary) -> void:
	var beliefs: Array[Dictionary] = _effects_of(result, "belief")
	var holders: Array = []
	for effect: Dictionary in beliefs:
		holders.append(effect["holder"])
		check_near(float(effect["certainty"]), 0.85, EPS, "belief 'steals ideas' certainty 0.85")
		check_eq(effect["fact"], "steals_ideas", "belief fact is steals_ideas")
	check(holders.has(OWNER) and holders.has(WITNESS_A) and holders.has(WITNESS_B),
			"every attendee now believes the player steals ideas")
	var stored: int = 0
	for belief: Belief in BeliefNet.get_beliefs_about("player"):
		if belief.fact == "steals_ideas" and holders.has(belief.holder):
			stored += 1
			check(belief.certainty > 0.0 and belief.certainty <= 0.85 + EPS,
					"stored belief certainty <= 0.85 (BeliefNet may temper it by reputation)")
	check_eq(stored, holders.size(), "the beliefs live in BeliefNet (the graph propagates them)")


func _check_uncontested() -> void:
	var id: String = _stolen_idea(ABSENT_OWNER)
	check(not IdeaPool.get_meeting_attendees().has(ABSENT_OWNER), "the owner is not in the room")
	var quality: int = IdeaPool.get_idea(id).quality
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {"player_reputation": 50.0})
	check(not result["contested"], "absent owner: no credibility clash")
	check_eq(result["merit"], IdeaPresentation.compute_merit(quality, "none", 50.0),
			"absent owner: merit by the formula")
	var bought: String = IdeaPool.generate_idea(SELLER, "general")
	IdeaPool.acquire(bought, IdeaPool.METHOD_PURCHASE)
	IdeaPool.add_meeting_attendee(SELLER)
	var sold: Dictionary = IdeaPresentation.present_player_idea(bought, {"player_reputation": 50.0})
	check(not sold["contested"], "a bought idea: the seller sits in the room and keeps quiet")


func _check_preparation() -> void:
	var id: String = IdeaPool.generate_idea(BELIEVER_B, "marketing")
	IdeaPool.acquire(id, IdeaPool.METHOD_STEAL_FILE)
	var before: float = GameClock.get_total_minutes()
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_REAL), "real preparation accepted")
	check_near(GameClock.get_total_minutes() - before,
			Database.get_balance_float("ideas.minutos_preparacion_real"), EPS,
			"real preparation costs clock time")
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_ASSIST), "assisted preparation")
	check_eq(_assists.back(), ["idea_presentation", "acceptable"], "A.S.S.I.S.T. prep leaves a trace")
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_REAL), "back to real preparation")
	check(not IdeaPresentation.prepare(id, "telepathy"), "unknown preparation rejected")
	check(not IdeaPool.is_meeting_open(), "an hour of preparation outlasts a one-hour meeting")
	IdeaPool.start_meeting()
	var quality: int = IdeaPool.get_idea(id).quality
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 50.0, "accuser_present": false})
	check_eq(result["merit"], IdeaPresentation.compute_merit(quality, "real", 50.0),
			"real preparation uses factor 1.0")
