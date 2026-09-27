# idea_presentation_case.gd — Cuerpo de test_idea_presentation: mérito, los tres resultados del choque y sus consecuencias (§11.2, §21), con contexto forzado y con estado real.
# PROPIETARIO DE: nada.
# ESCUCHA: idea_contested, idea_presented, aurora_meeting_started, assist_used (conexiones del caso).
extends TestCase

const OWNER := "npc_claudia_reeves"
const WITNESS_A := "npc_debbie_foyle"
const WITNESS_B := "npc_george_penn"
const BELIEVER_A := "npc_sonia_vail"
const BELIEVER_B := "npc_ray_cudmore"
const CONFIDANT := "npc_nate_brackley"
const ABSENT_OWNER := "npc_amelia_cole"
const SELLER := "npc_bernard_lasker"
const ALLY := "npc_tom_iverson"
const RIVAL := "npc_ludmila_petrova"
const DISCREDITED := "npc_connie_marks"
const TRUANT := "npc_ernie_vaughn"
const ELSEWHERE := "cafeteria"
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
	_check_not_staged()
	_check_win()
	_check_tie()
	_check_loss()
	_check_summon()
	_check_uncontested()
	_check_preparation()
	_check_assisted_preparation()
	IdeaPool.close_meeting()
	var late: String = _stolen_idea(BELIEVER_A)
	var result: Dictionary = IdeaPresentation.present_player_idea(late)
	check_eq(result["status"], IdeaPool.STATUS_NO_MEETING, "ideas are only presented at a meeting")
	_check_real_state()


func _connect_signals() -> void:
	EventBus.idea_contested.connect(func(id: String, accuser: String, result: String) -> void:
		_contested.append([id, accuser, result]))
	EventBus.idea_presented.connect(func(id: String, who: String, merit: int) -> void:
		_presented.append([id, who, merit]))
	EventBus.aurora_meeting_started.connect(func(meeting_id: String) -> void:
		_meetings.append(meeting_id))
	EventBus.assist_used.connect(func(task: String, quality: String) -> void:
		_assists.append([task, quality]))


# ─── Ayudas ─────────────────────────────────────────────────────────────

## Idea de `owner` escuchada por el jugador (se la cuenta a CONFIDANT con el jugador en la sala).
func _stolen_idea(owner: String, template: String = "design") -> String:
	var id: String = _untold_idea(owner, template)
	var room: String = NPCDirector.get_current_location(owner)
	if room.is_empty():
		room = NPCDirector.get_npc(owner).home_room
		NPCDirector.set_current_location(owner, room)
	IdeaPool.share_idea(id, CONFIDANT)
	EventBus.room_entered.emit(room, true)
	check(IdeaPool.acquire(id, IdeaPool.METHOD_OVERHEAR), "the player overhears %s's idea" % owner)
	return id


## Idea recién nacida que el propietario aún no ha contado a nadie (al nacer puede contársela a un
## colega: se descartan esas para que el número de creyentes sea el que fija cada prueba).
func _untold_idea(owner: String, template: String) -> String:
	var id: String = IdeaPool.generate_idea(owner, template)
	while IdeaPool.get_idea(id).known_by.size() > 1:
		id = IdeaPool.generate_idea(owner, template)
	return id


func _seat_owner_and_witnesses(owner: String) -> void:
	for npc_id: String in [owner, WITNESS_A, WITNESS_B]:
		IdeaPresentation.seat_attendee(npc_id)


func _effects_of(result: Dictionary, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for effect: Dictionary in result.get("effects", []):
		if effect.get("kind", "") == kind:
			out.append(effect)
	return out


## Ajuste por deltas públicos (el valor se acota a 0-100: se repite hasta fijarlo).
func _set_npc_reputation(npc_id: String, value: float) -> void:
	for _i: int in 3:
		var delta: float = value - NPCDirector.get_npc_reputation(npc_id)
		if absf(delta) > EPS:
			NPCDirector.modify_npc_reputation(npc_id, delta, "test")


## Una sala sin nadie (para controlar quién presencia un fallo de A.S.S.I.S.T.).
func _quiet_room() -> String:
	for room: RoomData in Database.get_all_rooms():
		if room.floor != RoomData.TRANSVERSAL_FLOOR and room.id != "aurora_room" \
				and NPCDirector.get_npcs_in_room(room.id).is_empty():
			return room.id
	return ""


func _set_player_reputation(value: float) -> void:
	PlayerState.modify_reputation(value - PlayerState.get_reputation(), "test")


func _steals_ideas_belief(holder: String) -> Belief:
	for belief: Belief in BeliefNet.get_beliefs_about("player"):
		if belief.fact == "steals_ideas" and belief.holder == holder:
			return belief
	return null


# ─── Fórmulas ───────────────────────────────────────────────────────────

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
	check_eq(schedule["seats"], 14, "aurora_room has 14 chairs (rooms/p12.json)")
	var day: int = IdeaPool.get_next_meeting_day(1)
	check(IdeaPool.is_meeting_day(day) and not IdeaPool.is_meeting_day(day + 1),
			"one meeting day per week")
	check_eq(IdeaPool.get_next_meeting_day(day + 1),
			day + Database.get_balance_int("tiempo.jornadas_por_semana"), "weekly cadence")
	var id: String = IdeaPool.generate_for_npc(OWNER)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if IdeaPool.is_ambitious_enough(npc.get_trait("ambition")):
			IdeaPool.generate_for_npc(npc.id)
	GameClock.set_time(day, int(schedule["hour"]), 0)
	IdeaPool.process_hour(int(schedule["hour"]) - 1, day)
	check(not IdeaPool.is_meeting_open(), "no meeting before its hour")
	IdeaPool.process_hour(int(schedule["hour"]), day)
	check(IdeaPool.is_meeting_open(), "the clock opens the weekly meeting")
	check_eq(_meetings.back(), "aurora_d%d" % day, "aurora_meeting_started(meeting_id)")
	var invited: Array[String] = IdeaPool.get_meeting_invitees()
	check(invited.size() <= 14, "invitations never exceed the seats (%d)" % invited.size())
	var unique: Dictionary = {}
	for npc_id: String in invited:
		unique[npc_id] = true
	check_eq(unique.size(), invited.size(), "each owner is invited at most once")
	var attended: bool = IdeaPool.get_meeting_attendees().has(OWNER)
	IdeaPool.process_hour(int(schedule["hour"]) + int(schedule["duration_hours"]), day)
	check(not IdeaPool.is_meeting_open(), "the meeting closes after its duration")
	check_eq(IdeaPool.get_idea(id).presented, attended,
			"an attending owner presents their idea at the close (ambition roll)")
	GameClock.set_time(1, 10, 0)


# ─── Los tres resultados con contexto forzado (§21) ─────────────────────

func _check_not_staged() -> void:
	var id: String = _stolen_idea(BELIEVER_B)
	var raw: Dictionary = IdeaPool.present(id)
	check_eq(raw["status"], IdeaPool.STATUS_NOT_STAGED,
			"IdeaPool.present() alone refuses: consequences need the Aurora scene")
	check_eq(raw["merit"], 0, "nothing granted without the scene")
	check(IdeaPool.get_player_ideas().has(IdeaPool.get_idea(id)), "the idea is not wasted")
	var staged: Dictionary = IdeaPresentation.present_player_idea(id, {"accuser_present": false})
	check_eq(staged["status"], IdeaPool.STATUS_OK, "the scene resolves the same idea")
	check(int(staged["merit"]) > 0 and _effects_of(staged, "merit").size() == 1,
			"merit is granted and registered in Company")


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
		check(rep[0]["applied"], "the usurper penalty reaches NPCDirector")
	var merits: Array[Dictionary] = _effects_of(result, "merit")
	check(merits.size() == 1 and int(merits[0]["amount"]) == merit, "merit registered in Company")


func _check_tie() -> void:
	var id: String = _stolen_idea(OWNER)
	_seat_owner_and_witnesses(OWNER)
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
	check_eq(records.size(), 2, "tie: minutes of the dispute for both parties")
	var subjects: Array = []
	for record: Dictionary in records:
		subjects.append(record["subject"])
		check_near(float(record["points"]), 10.0, EPS, "tie: +10 suspicion points each")
		check(not str(record["record_id"]).is_empty(), "tie: minutes recorded in BeliefNet")
		check_eq(record["affects_suspicion"], record["subject"] == "player",
				"only the player has a suspicion meter (NPC side is a documentary record)")
	check(subjects.has("player") and subjects.has(OWNER), "tie: player and accuser both marked")
	check_near(_suspicion_from(records), 10.0, SUSPICION_EPS,
			"tie: the minutes add exactly 10 points to the player's suspicion (BeliefNet formula)")


## Puntos de sospecha que aportan, según BeliefNet, los registros creados por el empate.
func _suspicion_from(records: Array[Dictionary]) -> float:
	var ids: Array = []
	for record: Dictionary in records:
		ids.append(record["record_id"])
	var total: float = 0.0
	for entry: Dictionary in BeliefNet.get_suspicion_breakdown():
		if ids.has(entry["belief_id"]):
			total += float(entry["contribution"])
	return total


func _check_loss() -> void:
	var id: String = _stolen_idea(OWNER)
	_seat_owner_and_witnesses(OWNER)
	IdeaPool.share_idea(id, BELIEVER_A)
	IdeaPool.share_idea(id, BELIEVER_B)
	var believers: int = IdeaPresentation.count_believers(IdeaPool.get_idea(id))
	check_eq(believers, 3, "the confidant and two colleagues believe it was the owner's")
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 30.0, "player_suspicion": 40.0, "allies": 0,
		"accuser_reputation": 40.0})
	check_eq(result["contest_result"], IdeaPresentation.RESULT_LOSS, "10 vs 100 -> player loses")
	check_near(float(result["accuser_credibility"]), 40.0 + 20.0 * believers, EPS,
			"loss: accuser credibility counts 20 per believer")
	check_near(float(result["player_credibility"]), 10.0, EPS, "loss: 30 - 0.5 x 40 = 10")
	check_eq(result["merit"], 0, "loss: no merit")
	var idea: Idea = IdeaPool.get_idea(id)
	check(idea.acquired_by.is_empty() and not idea.presented, "loss: the idea reverts to its owner")
	check_eq(_contested.back(), [id, OWNER, "loss"], "idea_contested(id, owner, loss)")
	var rep: Array[Dictionary] = _effects_of(result, "player_reputation")
	check(rep.size() == 1 and absf(float(rep[0]["delta"]) + 20.0) < EPS, "loss: reputation -20")
	var holders: Array = []
	for effect: Dictionary in _effects_of(result, "belief"):
		holders.append(effect["holder"])
		check_near(float(effect["certainty"]), 0.85, EPS, "belief 'steals ideas' certainty 0.85")
	check(holders.has(OWNER) and holders.has(WITNESS_A) and holders.has(WITNESS_B),
			"every attendee now believes the player steals ideas")
	var in_room: bool = true
	for holder: Variant in holders:
		in_room = in_room and (holder == OWNER or (result["attendees"] as Array).has(holder))
	check(in_room, "only people in the room (and the accuser) hold the belief")
	for holder: Variant in holders:
		var belief: Belief = _steals_ideas_belief(str(holder))
		check(belief != null and absf(belief.certainty - 0.85) < EPS,
				"%s holds 'steals ideas' at exactly 0.85 in BeliefNet" % holder)


func _check_summon() -> void:
	var invited: Array[String] = IdeaPool.get_meeting_invitees()
	check(invited.has(WITNESS_A), "seated witnesses are on the invitation list")
	check_eq(NPCDirector.get_current_location(WITNESS_A), "aurora_room",
			"summoned attendees sit in aurora_room")
	check(IdeaPool.is_meeting_staged(), "the scene made the meeting physical")
	IdeaPresentation.release_attendees(invited)
	check(NPCDirector.get_current_location(WITNESS_A) != "aurora_room",
			"released attendees go back to their routine")
	check(not IdeaPool.get_meeting_attendees().has(WITNESS_A),
			"presence is physical: a released witness no longer attends")
	IdeaPresentation.summon_attendees()
	check(IdeaPool.get_meeting_attendees().has(WITNESS_A), "summoning brings them back")


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
	IdeaPresentation.seat_attendee(SELLER)
	check(IdeaPool.get_meeting_attendees().has(SELLER), "the seller sits in the room")
	var sold: Dictionary = IdeaPresentation.present_player_idea(bought, {"player_reputation": 50.0})
	check(not sold["contested"], "a bought idea: the seller keeps quiet")


func _check_preparation() -> void:
	var id: String = IdeaPool.generate_idea(BELIEVER_B, "marketing")
	check(IdeaPool.acquire(id, IdeaPool.METHOD_PURCHASE), "bought idea to prepare")
	var before: float = GameClock.get_total_minutes()
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_REAL), "real preparation accepted")
	check_near(GameClock.get_total_minutes() - before,
			Database.get_balance_float("ideas.minutos_preparacion_real"), EPS,
			"real preparation costs clock time")
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_ASSIST), "assisted preparation")
	check_eq(_assists.back()[0], "idea_presentation", "assisted prep leaves a digital trace")
	check(IdeaPresentation.prepare(id, IdeaPresentation.PREP_REAL), "back to real preparation")
	check(not IdeaPresentation.prepare(id, "telepathy"), "unknown preparation rejected")
	check(not IdeaPool.is_meeting_open(), "an hour of preparation outlasts a one-hour meeting")
	IdeaPool.start_meeting()
	var quality: int = IdeaPool.get_idea(id).quality
	var result: Dictionary = IdeaPresentation.present_player_idea(id, {
		"player_reputation": 50.0, "accuser_present": false})
	check_eq(result["merit"], IdeaPresentation.compute_merit(quality, "real", 50.0),
			"real preparation uses factor 1.0")


## §10.4 aplicado a la preparación: misma lotería 60/25/15 y misma detección.
func _check_assisted_preparation() -> void:
	var id: String = IdeaPool.generate_idea(SELLER, "marketing")
	IdeaPool.acquire(id, IdeaPool.METHOD_PURCHASE)
	var counts: Dictionary = {"acceptable": 0, "excellent": 0, "evident_failure": 0}
	for i: int in 4000:
		var outcome: String = IdeaPool.roll_assist_outcome()
		counts[outcome] = int(counts[outcome]) + 1
	check_near(float(counts["evident_failure"]) / 4000.0, 0.15, 0.02,
			"assisted preparation fails evidently ~15% of the time")
	var sharp_room: String = _quiet_room()
	check(not sharp_room.is_empty(), "a quiet room to work in")
	NPCDirector.set_current_location(ABSENT_OWNER, sharp_room)
	EventBus.room_entered.emit(sharp_room, true)
	_set_player_reputation(50.0)
	var rep_before: float = PlayerState.get_reputation()
	var caught: Dictionary = IdeaPresentation.apply_assist_preparation(id,
			DutySystem.ASSIST_FAILURE)
	check(caught["ok"] and caught["preparation"] == "assist", "the deck is still an assisted one")
	check_eq(caught["detected_by"], ABSENT_OWNER,
			"Amelia (perception 76 > 60) in the room spots the invented figures")
	check_near(PlayerState.get_reputation() - rep_before,
			Database.get_balance_float("deberes.assist_penalizacion_reputacion_detectado"), EPS,
			"detected failure costs reputation")
	check_eq(_assists.back(), ["idea_presentation", "evident_failure"], "assist_used logged")
	var good: Dictionary = IdeaPresentation.apply_assist_preparation(id, DutySystem.ASSIST_EXCELLENT)
	check_eq(good["merit"], Database.get_balance_int("deberes.assist_merito_excelente"),
			"an excellent deck earns the minor merit")


# ─── Estado real, sin claves forzadas ───────────────────────────────────

func _check_real_state() -> void:
	new_run()
	GameClock.set_time(1, 10, 0)
	IdeaPool.start_meeting()
	_set_player_reputation(50.0)
	NPCDirector.add_affection(ALLY, Database.get_balance_int("ideas.afecto_minimo_aliado"))
	IdeaPresentation.seat_attendee(ALLY)
	_check_real_win()
	_check_real_loss()
	_check_discredited_accuser()
	_check_forced_absence()


func _expected_allies(accuser: String) -> int:
	var count: int = 0
	for npc_id: String in IdeaPool.get_meeting_attendees():
		if npc_id != accuser and (NPCDirector.get_affection(npc_id) >= Database.get_balance_int(
				"ideas.afecto_minimo_aliado") or NPCDirector.get_debt(npc_id) > 0):
			count += 1
	return count


func _check_real_win() -> void:
	var id: String = _stolen_idea(OWNER)
	# Después del robo: NPCDirector ya le sumó el agravio "idea_stolen" (baja su reputación).
	_set_npc_reputation(OWNER, 20.0)
	IdeaPresentation.seat_attendee(OWNER)
	var allies: int = _expected_allies(OWNER)
	check(allies >= 1, "an ally with affection >= 40 sits in the room")
	var suspicion: float = PlayerState.get_suspicion()
	var merit_before: int = Company.get_recent_merit()
	var result: Dictionary = IdeaPresentation.present_player_idea(id)
	check_eq(result["allies"], allies, "real state: allies counted from the ledger")
	check_near(float(result["accuser_reputation"]), 20.0, EPS, "real state: accuser reputation")
	check_eq(result["believers"], 1, "real state: the confidant believes it was hers")
	check_near(float(result["player_credibility"]), 50.0 + 15.0 * allies - 0.5 * suspicion, EPS,
			"real state: player = 50 + 15 x allies - 0.5 x suspicion")
	check_near(float(result["accuser_credibility"]), 40.0, EPS, "real state: accuser = 20 + 20")
	check_eq(result["contest_result"], IdeaPresentation.RESULT_WIN, "real state: the player wins")
	check_near(NPCDirector.get_npc_reputation(OWNER), 5.0, EPS,
			"NPCDirector: the usurper drops from 20 to 5")
	check_eq(Company.get_recent_merit() - merit_before, int(result["merit"]),
			"Company registered exactly the presentation merit")


func _check_real_loss() -> void:
	var id: String = _stolen_idea(RIVAL, "general")
	_set_npc_reputation(RIVAL, 80.0)
	IdeaPool.share_idea(id, BELIEVER_A)
	IdeaPresentation.seat_attendee(RIVAL)
	IdeaPresentation.seat_attendee(WITNESS_A)
	check_near(PlayerState.get_reputation(), 50.0, EPS, "the player walks in with reputation 50")
	var result: Dictionary = IdeaPresentation.present_player_idea(id)
	check_eq(result["contest_result"], IdeaPresentation.RESULT_LOSS,
			"real state: 80 + 2 believers crush the player")
	check_near(PlayerState.get_reputation(), 30.0, EPS, "real state: reputation 50 -> 30")
	var holders: Array = []
	for effect: Dictionary in _effects_of(result, "belief"):
		holders.append(effect["holder"])
	check(holders.has(RIVAL) and holders.has(WITNESS_A) and holders.has(ALLY),
			"everyone physically in the room holds the belief")
	check(holders.size() <= IdeaPool.get_meeting_seats() + 1, "a room, not the whole company")
	for holder: Variant in holders:
		var belief: Belief = _steals_ideas_belief(str(holder))
		check(belief != null and absf(belief.certainty - 0.85) < 0.000001,
				"%s: stored certainty exactly 0.85 despite reputation 50 (§11.2)" % holder)


func _check_discredited_accuser() -> void:
	var id: String = _stolen_idea(DISCREDITED, "general")
	_set_npc_reputation(DISCREDITED, 0.0)
	check_near(NPCDirector.get_npc_reputation(DISCREDITED), 0.0, EPS, "reputation ruined to 0")
	check_near(IdeaPresentation.npc_reputation(DISCREDITED), 0.0, EPS,
			"a discredited accuser keeps reputation 0 (not the default 50)")
	check_near(IdeaPresentation.npc_reputation("npc_nobody_at_all"),
			Database.get_balance_float("ideas.reputacion_npc_por_defecto"), EPS,
			"only unknown ids use the default reputation")
	IdeaPresentation.seat_attendee(DISCREDITED)
	var result: Dictionary = IdeaPresentation.present_player_idea(id)
	check(result["contested"], "the discredited owner still accuses")
	check_near(float(result["accuser_credibility"]), 20.0, EPS,
			"accuser = 0 + 20 x 1 believer: degrading reputation works")


func _check_forced_absence() -> void:
	IdeaPool.close_meeting()
	var id: String = _stolen_idea(TRUANT, "general")
	IdeaPool.start_meeting()
	check(IdeaPool.add_meeting_attendee(TRUANT), "the owner is invited")
	NPCDirector.override_routine(TRUANT, GameClock.get_current_band(), ELSEWHERE)
	check(not IdeaPool.is_available_for_meeting(TRUANT), "sent elsewhere: not available")
	IdeaPresentation.summon_attendees()
	check(NPCDirector.get_current_location(TRUANT) != "aurora_room",
			"summoning does not override a forced absence")
	check(not IdeaPool.get_meeting_attendees().has(TRUANT), "the owner is absent")
	var result: Dictionary = IdeaPresentation.present_player_idea(id)
	check(not result["contested"] and int(result["merit"]) > 0,
			"guaranteed absence: the idea is presented without a clash")
