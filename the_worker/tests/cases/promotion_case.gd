# promotion_case.gd — Cuerpo de test_promotion: regla de la silla libre (§6.2), reposición en cadena con favor y agravio (§6.3), saltos, sucesores, rechazo, laterales, descensos (§6.1), mérito con caducidad y guardado.
# PROPIETARIO DE: nada.
# ESCUCHA: seat_vacated, seat_filled, occupation_changed, promotion_available, promotion_declined, merit_gained, game_over, grievance_added, notebook_entry_added (solo para comprobarlas).
extends TestCase

const START := "email_worker_3b"
const TARGET := "order_filer"
const LATERAL := "copy_operator"
const MID_SEAT := "mail_courier"
## email_worker_3b.can_jump_to: R1 → R4 de un salto.
const JUMP := "mail_courier"
const HR_DIRECTOR := "hr_director"
const HR_ASSISTANT := "hr_assistant"
const AMELIA := "npc_amelia_cole"
## Deber de tipo "delivery" (éxito visible) y uno rutinario de volumen (no lo es).
const DELIVERY_DUTY := "duty_campaign_pieces_r11"
const ROUTINE_DUTY := "duty_emails_r1"
const NOTE_OFFER := "NOTE_PROMOTION_AVAILABLE"
const AUDITOR := "chief_auditor"
const ROSE := "npc_rose_miller"
const ROSE_DAY := 31
const START_SEATS := 10
const OCCUPATION_COUNT := 50
const EXPELLED := "expelled"
## Margen sobre la reputación mínima: absorbe la penalización de un deber fallido al pasar el día.
const REP_MARGIN := 10.0
const OFFICE_HOUR := 12
## El becario eterno (R0) no asciende solo (balance empresa.rango_minimo_candidato).
const MIN_CANDIDATE_RANK := 1
const SIGNALS: Array[String] = [
	"seat_vacated", "seat_filled", "occupation_changed", "promotion_available",
	"promotion_declined", "merit_gained", "game_over", "grievance_added", "notebook_entry_added",
]

var _log: Dictionary = {}
## Contexto de Company en cada seat_filled (get_last_fill_context en el momento de la señal).
var _contexts: Array[Dictionary] = []


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	_test_initial_seats()
	_test_three_conditions()
	_test_promotion_flow()
	_test_auto_fill_chain()
	_test_jump_promotion()
	await _test_vacancy_window()
	_test_npc_removed()
	await _test_designated_successor()
	_test_successor_on_vacancy()
	_test_decline_and_offer()
	_test_lateral_moves()
	_test_created_post_and_demotions()
	_test_board_removal()
	_test_merit_sources_and_expiry()
	_test_save_load()


# ─── Escenarios ────────────────────────────────────────────────

func _test_initial_seats() -> void:
	check_eq(Company.get_seat_count(START), START_SEATS,
			"3B: George, Nate, Claudia, Sonia + 5 generated + the player's seat")
	var seat: Dictionary = Company.get_player_seat()
	check_eq([seat.get("occupation_id"), seat.get("holder")], [START, "player"],
			"the player holds a seat of email_worker_3b")
	check(Company.get_vacant_seats().is_empty(), "no vacancies when the run starts")
	var covered: int = 0
	for occupation: OccupationData in Database.get_all_occupations():
		covered += 1 if not Company.get_seat_holder(occupation.id).is_empty() else 0
	check_eq(covered, OCCUPATION_COUNT, "all 50 occupations have a holder at the start")
	check_eq(Company.get_seat_holder(START), "npc_george_penn", "first 3B seat: George Penn")


## §6.2: reputación, mérito reciente y vacante; cada una es necesaria.
func _test_three_conditions() -> void:
	var cases: Array = [
		[true, true, true, []],
		[false, true, true, ["reputation"]],
		[true, false, true, ["merit"]],
		[true, true, false, ["vacancy"]],
		[false, false, false, ["reputation", "merit", "vacancy"]],
	]
	for c: Array in cases:
		_prepare(c[0], c[1], c[2])
		var result: Dictionary = Company.can_player_promote_to(TARGET)
		var expected: Array = c[3]
		check_eq(Array(result["missing"]), expected, "missing conditions %s" % str(expected))
		check_eq(bool(result["allowed"]), expected.is_empty(), "allowed only with all three")
		if not expected.is_empty():
			check(not Company.promote_player(TARGET) and _player_occupation() == START,
					"promote_player refuses without %s" % str(expected))
	check(Array(Company.can_player_promote_to("ceo")["missing"]).has("path"),
			"a post that is not reachable from 3B reports 'path'")
	check_eq(Company.get_merit_threshold(), 1,
			"§6.2: one recent merit event is enough (threshold 1 point)")


func _test_promotion_flow() -> void:
	_prepare(true, true, true)
	var expelled: String = _vacated_holder(TARGET)
	var passed_over: String = _expected_best(TARGET, _seats_snapshot())
	check(Company.promote_player(TARGET), "promotion with the three conditions")
	check_eq(_player_occupation(), TARGET, "PlayerState adopted the new occupation")
	check_eq(Company.get_player_seat().get("occupation_id"), TARGET, "the player's seat moved")
	check(_calls("seat_vacated").has([START, "player", "player_promoted"]),
			"seat_vacated(3B, player, player_promoted)")
	check(_calls("seat_filled").has([TARGET, "player"]), "seat_filled(order_filer, player)")
	check(_calls("occupation_changed").has([START, TARGET, "promotion"]),
			"occupation_changed(old, new, promotion)")
	check_eq(Company.get_recent_merit(), 0, "the promotion consumes the recent merit")
	check(Company.is_seat_vacant(START), "the player's old desk is now a vacancy")
	check_eq(Company.get_seat_holder(START), "",
			"get_seat_holder() is \"\" while any seat of the occupation is vacant")
	var context: Dictionary = Company.get_last_fill_context()
	check_eq([context["kind"], context["vacancy_cause"], context["grievance_to"]],
			["player", EXPELLED, passed_over],
			"context: the best-placed 3B colleague is the one passed over")
	check(_has_ledger_entry(passed_over, "grievances", "promotion_stolen"),
			"§6.3 grievance: the colleague who expected the chair (NPCDirector ledger)")
	check(_has_ledger_entry(expelled, "grievances", "seat_lost"),
			"§6.3 grievance: the holder expelled through NPCDirector.remove_npc lost the chair")
	check(not NPCDirector.is_active(expelled), "the expelled holder is off staff (realistic path)")


## §6.3: mail_courier (R4) se repone desde R3 → R2 → R1 → Rookie contratado en la base.
func _test_auto_fill_chain() -> void:
	_fresh()
	var snapshot: Array[Dictionary] = _seats_snapshot()
	var riser: String = _expected_best(MID_SEAT, snapshot)
	_expel_holder(MID_SEAT)
	_clear()
	Company.auto_fill_vacancies()
	check(Company.get_vacant_seats().is_empty(), "the chain leaves no vacancy behind")
	check_eq(Company.get_seat_holder(MID_SEAT), riser,
			"highest merit × weight + ambition × weight among the feeders rises")
	var fills: Array = _calls("seat_filled")
	check_eq(fills.size(), 4, "four fills: R4, R3, R2 and R1 (the Rookie)")
	check_eq(_calls("seat_vacated").size(), 3, "three seats freed by the chain (cause promoted)")
	check(_chain_goes_down(), "each riser comes from a lower rank than the chair it takes")
	check_eq(_contexts[0]["favour_to"], riser, "the riser owes the vacancy to the player: favour")
	check(_has_ledger_entry(riser, "favours", "promotion"), "favour in NPCDirector's ledger")
	check(str(_contexts[1]["favour_to"]).is_empty(), "further links of the chain owe nothing")
	var hires: Array[Dictionary] = Company.get_hires()
	check_eq(hires.size(), 1, "HR hires one Rookie at the base")
	check_eq([hires[0]["occupation_id"], _contexts[3]["kind"]], [START, "hire"],
			"the Rookie takes an email_worker_3b chair")
	check(Company.is_hire(str(hires[0]["npc_id"])), "is_hire() recognises the Rookie id")


## §6.1: saltos múltiples (can_jump_to) con las mismas tres condiciones.
func _test_jump_promotion() -> void:
	_fresh()
	var jump: OccupationData = Database.get_occupation(JUMP)
	check(Database.get_occupation(START).can_jump_to.has(JUMP), "data: 3B can jump to mail courier")
	PlayerState.modify_reputation(jump.min_reputation + REP_MARGIN, "test")
	Company.register_merit("test", Company.get_merit_threshold())
	check_eq(Array(Company.can_player_promote_to(JUMP)["missing"]), ["vacancy"],
			"a jump needs the same three conditions (here only the vacancy is missing)")
	_expel_holder(JUMP)
	check(Company.get_available_promotions().has(JUMP), "the jump is offered once the chair is free")
	_clear()
	check(Company.promote_player(JUMP), "multi-rank jump accepted")
	check_eq(_player_occupation(), JUMP, "the player jumped to mail courier")
	check_eq(jump.rank - Database.get_occupation(START).rank, 3, "three ranks in one move (R1 → R4)")
	check(_calls("occupation_changed").has([START, JUMP, "promotion"]), "reason 'promotion'")


## La vacante espera empresa.jornadas_vacante_abierta jornadas antes de reponerse sola.
func _test_vacancy_window() -> void:
	_fresh()
	Company.vacate_seat(TARGET, EXPELLED)
	var grace: int = Database.get_balance_int("empresa.jornadas_vacante_abierta")
	for _i: int in grace - 1:
		GameClock.advance_to_next_day()
	check(Company.is_seat_vacant(TARGET), "the vacancy stays open for the player")
	GameClock.advance_to_next_day()
	await wait_frames(1)
	check(not Company.is_seat_vacant(TARGET), "after %d day(s) the company refills it" % grace)


func _test_npc_removed() -> void:
	_fresh()
	var holder: String = Company.get_seat_holder("senior_accountant")
	_clear()
	NPCDirector.remove_npc(holder, EXPELLED)
	check(_calls("seat_vacated").has(["senior_accountant", holder, EXPELLED]),
			"npc_removed → seat_vacated(occupation, npc, cause)")
	check(Company.get_npc_seat(holder).is_empty(), "the removed NPC no longer holds a seat")
	Company.fill_seat("senior_accountant", holder)
	check(Company.get_npc_seat(holder).is_empty() and Company.is_seat_vacant("senior_accountant"),
			"fill_seat refuses an NPC who is no longer on staff")


## Rose Miller (§7.13): en la jornada 31 el Auditor Jefe generado se jubila y ella asciende.
func _test_designated_successor() -> void:
	_fresh()
	var previous: String = Company.get_seat_holder(AUDITOR)
	check(previous != ROSE and not previous.is_empty(), "a generated Chief Auditor at the start")
	GameClock.set_time(ROSE_DAY - 1, OFFICE_HOUR, 0)
	_clear()
	GameClock.advance_to_next_day()
	await wait_frames(1)
	check_eq(Company.get_seat_holder(AUDITOR), ROSE, "day 31: Rose Miller is Chief Auditor")
	check(_calls("seat_vacated").has([AUDITOR, previous, "retired"]), "the predecessor retires")
	check(_contexts.size() > 0 and _contexts[0]["kind"] == "successor",
			"future_occupation takes precedence over §6.3 scoring")


## Sucesora designada sin jornada (Amelia Cole, future_occupation hr_director): toda vacante de
## Dirección de RR. HH. es suya aunque venga de R9 (§6.3 cede ante el perfil).
func _test_successor_on_vacancy() -> void:
	_fresh()
	check_eq(str(NPCDirector.get_profile(AMELIA).get("future_occupation", "")), HR_DIRECTOR,
			"data: Amelia Cole is the designated HR director")
	check_eq(Company.get_npc_seat(AMELIA).get("occupation_id"), HR_ASSISTANT,
			"Amelia starts as HR assistant (R9)")
	_expel_holder(HR_DIRECTOR)
	_clear()
	Company.auto_fill_vacancies()
	check_eq(Company.get_seat_holder(HR_DIRECTOR), AMELIA,
			"an HR director vacancy goes straight to Amelia Cole (R9 → R23)")
	check(_contexts.size() > 0 and _contexts[0]["kind"] == "successor"
			and _contexts[0]["from_occupation"] == HR_ASSISTANT, "successor fill, from hr_assistant")
	check(Company.get_vacant_seats().is_empty(), "her old chair is refilled down the chain")


func _test_decline_and_offer() -> void:
	_prepare(true, true, true)
	check(_offered(TARGET), "promotion_available lists order_filer once the conditions hold")
	check_eq(_notes(NOTE_OFFER), 1, "the notebook records the new offer once")
	_clear()
	GameClock.advance_to_next_day()
	check(_offered(TARGET), "the offer is repeated at the start of the next day")
	check_eq(_notes(NOTE_OFFER), 0, "an unchanged offer does not write a new notebook entry")
	_clear()
	Company.decline_promotion("cfo")
	check(_calls("promotion_declined").is_empty(), "declining a post that is not on offer does nothing")
	Company.decline_promotion(TARGET)
	check(_calls("promotion_declined").has([TARGET]), "promotion_declined(order_filer)")
	check(not Company.is_seat_vacant(TARGET), "a declined chair is refilled at once")
	check_eq(_player_occupation(), START, "the player keeps the old post")
	Company.decline_promotion(TARGET)
	check_eq(_calls("promotion_declined").size(), 1, "a refilled chair cannot be declined twice")


func _test_lateral_moves() -> void:
	_fresh()
	PlayerState.set_occupation(TARGET, "test")
	check_eq(Company.get_player_seat().get("occupation_id"), TARGET,
			"an external occupation change moves the player's seat silently")
	check_eq(Company.get_seat_count(TARGET), 5, "no vacancy → a temporary extra seat")
	PlayerState.modify_reputation(Database.get_occupation(LATERAL).min_reputation + REP_MARGIN
			+ Database.get_balance_float("empresa.margen_reputacion_crear_puesto"), "test")
	check_eq(Array(Company.can_player_promote_to(LATERAL)["missing"]), ["vacancy"],
			"exceptional reputation creates posts only for promotions, never for laterals")
	_expel_holder(LATERAL)
	var result: Dictionary = Company.can_player_promote_to(LATERAL)
	check(bool(result["allowed"]), "a lateral move needs no merit, only reputation and vacancy")
	check(Company.get_available_promotions().has(LATERAL), "laterals are listed as available")
	_clear()
	check(Company.promote_player(LATERAL), "lateral move accepted")
	check(_calls("occupation_changed").has([TARGET, LATERAL, "lateral"]), "reason 'lateral'")
	check_eq(Company.get_seat_count(TARGET), 4, "the temporary seat disappears when left")
	PlayerState.set_occupation("maintenance_aide", "test")
	var targets: Array[String] = Company.get_promotion_targets()
	check(targets.has("junior_accountant") and targets.has("hr_assistant"),
			"targets: same-rank laterals and promotes_to")
	check(not targets.has("senior_sales"), "laterals to a higher rank are not allowed (§6.1)")


func _test_created_post_and_demotions() -> void:
	_fresh()
	var target: OccupationData = Database.get_occupation(TARGET)
	PlayerState.modify_reputation(target.min_reputation
			+ Database.get_balance_float("empresa.margen_reputacion_crear_puesto"), "test")
	Company.register_merit("test", Company.get_merit_threshold())
	check(bool(Company.can_player_promote_to(TARGET)["allowed"]),
			"exceptional reputation: management creates the post (no vacancy needed)")
	check(Company.promote_player(TARGET), "promotion into a created post")
	check_eq(Company.get_seat_count(TARGET), 5, "the created post is an extra seat")
	check(_calls("occupation_changed").has([START, TARGET, "created_post"]), "reason created_post")
	check_eq(Company.get_last_fill_context()["grievance_to"], "",
			"a created post takes nobody's chair: no one is passed over")
	check(not _grievance_of_type("promotion_stolen"), "no promotion_stolen grievance is recorded")
	_clear()
	Company.demote_player("test_failure")
	check_eq(_player_occupation(), "eternal_intern", "§6.1 descent: order_filer → eternal intern")
	check_eq(Company.get_seat_count(TARGET), 4, "the created post disappears with the player")
	check(_calls("occupation_changed").has([TARGET, "eternal_intern", "demotion"]),
			"reason demotion")
	check(_calls("game_over").is_empty(), "no game over yet")
	Company.demote_player("test_failure")
	var over: Array = _calls("game_over")
	check(over.size() == 1 and over[0][0] == "failed_at_r0" and over[0][1] == "the_gap",
			"failing at R0 → game_over(failed_at_r0, the_gap)")


func _test_board_removal() -> void:
	_fresh()
	PlayerState.set_occupation("ceo", "test")
	Company.demote_player("board_pressure")
	check(_calls("game_over").size() == 1 and _calls("game_over")[0][0] == "board_removal",
			"R33 degraded by the board → game_over(board_removal)")


func _test_merit_sources_and_expiry() -> void:
	_fresh()
	var day: int = GameClock.get_day()
	var expiry: int = Database.get_balance_int("empresa.jornadas_caducidad_merito")
	var duty_merit: int = Database.get_balance_int("empresa.merito_deber_exitoso")
	EventBus.duty_completed.emit(ROUTINE_DUTY, 1.0, "honest")
	check_eq(Company.get_recent_merit(), 0, "a routine duty (emails, volume) is not a visible success")
	EventBus.duty_completed.emit(DELIVERY_DUTY, 1.0, "assist")
	check_eq(Company.get_recent_merit(), 0, "an A.S.S.I.S.T. delivery is not a visible success")
	EventBus.duty_completed.emit(DELIVERY_DUTY, 1.0, "honest")
	check_eq(Company.get_recent_merit(), duty_merit, "an honest delivery is a visible success")
	check(not Array(Company.can_player_promote_to(TARGET)["missing"]).has("merit"),
			"a single visible success satisfies the merit condition")
	Company.register_merit("idea", 3)
	check(_calls("merit_gained").has(["idea", 3]), "register_merit emits merit_gained")
	_bribe_recommendation(Company.get_seat_holder(START))
	var expected: int = 3 + duty_merit + Database.get_balance_int("empresa.merito_recomendacion")
	check_eq(Company.get_recent_merit(), expected,
			"idea + visible success + bought recommendation")
	GameClock.set_time(day + expiry - 1, OFFICE_HOUR, 0)
	check_eq(Company.get_recent_merit(), expected, "merit is still recent on its last day")
	GameClock.set_time(day + expiry, OFFICE_HOUR, 0)
	check_eq(Company.get_recent_merit(), 0, "merit expires after %d days" % expiry)
	_fresh()
	PlayerState.set_occupation("deputy_cfo", "test")
	check(Array(Company.can_player_promote_to("cfo")["missing"]).has("merit"),
			"no merit yet for the CFO chair")
	_bribe_recommendation(Company.get_seat_holder("cfo"))
	check(not Array(Company.can_player_promote_to("cfo")["missing"]).has("merit"),
			"one bought recommendation satisfies the merit condition even for a tier-7 post")


func _test_save_load() -> void:
	_prepare(true, true, true)
	Company.auto_fill_vacancies()
	Company.register_merit("test", 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state()))
	var seats: Array[Dictionary] = Company.get_all_seats()
	var hires: Array[Dictionary] = Company.get_hires()
	var merit: int = Company.get_recent_merit()
	_fresh()
	Company.load_state(saved)
	check(_same_seats(Company.get_all_seats(), seats), "seats survive a JSON save/load")
	check_eq(Company.get_hires().size(), hires.size(), "hires survive")
	check_eq(Company.get_recent_merit(), merit, "recent merit survives")
	check_eq(typeof(Company.get_last_fill_context()["day"]), TYPE_INT,
			"the last fill context keeps an int day after a JSON round trip")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


## Partida nueva con las condiciones pedidas para order_filer (R2, escalón 1).
func _prepare(reputation: bool, merit: bool, vacancy: bool) -> void:
	_fresh()
	var target: OccupationData = Database.get_occupation(TARGET)
	if reputation:
		PlayerState.modify_reputation(target.min_reputation + REP_MARGIN, "test")
	if merit:
		Company.register_merit("test", Company.get_merit_threshold())
	if vacancy:
		_expel_holder(TARGET)


## Expulsa por la vía real (NPCDirector.remove_npc → npc_removed → Company libera la silla) al
## primer personaje titular de la ocupación. Devuelve su id.
func _expel_holder(occupation_id: String) -> String:
	for holder: String in Company.get_seat_holders(occupation_id):
		if not holder.is_empty() and holder != "player":
			NPCDirector.remove_npc(holder, EXPELLED)
			return holder
	return ""


## Soborno aceptado del favor «recomendación» (empresa.favor_recomendacion).
func _bribe_recommendation(npc_id: String) -> void:
	EventBus.bribe_offered.emit(npc_id, 500, str(Database.get_balance("empresa.favor_recomendacion")))
	EventBus.bribe_result.emit(npc_id, true, "accepted")


func _player_occupation() -> String:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation.id if occupation != null else ""


func _vacated_holder(occupation_id: String) -> String:
	for call: Array in _calls("seat_vacated"):
		if call[0] == occupation_id and call[2] == EXPELLED:
			return str(call[1])
	return ""


func _seats_snapshot() -> Array[Dictionary]:
	return Company.get_all_seats()


## Cálculo independiente del candidato §6.3 (misma fórmula documentada en balance npc.*).
func _expected_best(occupation_id: String, seats: Array[Dictionary]) -> String:
	var w_merit: float = Database.get_balance_float("npc.puntuacion_ascenso_merito")
	var w_ambition: float = Database.get_balance_float("npc.puntuacion_ascenso_ambicion")
	var best: String = ""
	var best_score: float = -INF
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var occupation: OccupationData = Database.get_occupation(_seat_occupation(npc.id, seats))
		if occupation == null or occupation.rank < MIN_CANDIDATE_RANK \
				or not occupation.promotes_to.has(occupation_id):
			continue
		var score: float = NPCDirector.get_merit(npc.id) * w_merit \
				+ NPCDirector.get_trait(npc.id, "ambition") * w_ambition
		if score > best_score:
			best_score = score
			best = npc.id
	return best


func _seat_occupation(npc_id: String, seats: Array[Dictionary]) -> String:
	for seat: Dictionary in seats:
		if seat["holder"] == npc_id:
			return str(seat["occupation_id"])
	return ""


func _chain_goes_down() -> bool:
	for context: Dictionary in _contexts:
		var from: OccupationData = Database.get_occupation(str(context["from_occupation"]))
		var to: OccupationData = Database.get_occupation(str(context["occupation_id"]))
		if from != null and (to == null or from.rank >= to.rank):
			return false
	return true


func _has_ledger_entry(npc_id: String, list: String, entry_type: String) -> bool:
	for entry: Variant in NPCDirector.get_ledger(npc_id).get(list, []):
		if entry is Dictionary and str(entry.get("type", "")) == entry_type:
			return true
	return false


func _notes(text_key: String) -> int:
	var count: int = 0
	for call: Array in _calls("notebook_entry_added"):
		if call[1] == text_key:
			count += 1
	return count


func _grievance_of_type(grievance_type: String) -> bool:
	for call: Array in _calls("grievance_added"):
		if call[1] == grievance_type:
			return true
	return false


func _offered(occupation_id: String) -> bool:
	for call: Array in _calls("promotion_available"):
		if Array(call[0]).has(occupation_id):
			return true
	return false


func _same_seats(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		for key: String in ["occupation_id", "seat_index", "holder", "temporary"]:
			if not values_equal(a[i][key], b[i][key]):
				return false
	return true


func _connect_bus() -> void:
	for signal_name: String in SIGNALS:
		EventBus.connect(signal_name, _record.bind(signal_name))


func _record(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	if not _log.has(signal_name):
		_log[signal_name] = []
	_log[signal_name].append(args)
	if signal_name == "seat_filled":
		_contexts.append(Company.get_last_fill_context())


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()
	_contexts.clear()
