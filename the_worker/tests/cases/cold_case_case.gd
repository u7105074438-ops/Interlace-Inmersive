# cold_case_case.gd — Cuerpo de test_cold_case (§21, PASO 30): archivo con evidencia permanente, reactivación por pieza nueva (también la del rastro contable que aflora tarde), testigo silencioso y cambio de Auditor Jefe (RNG de la partida) bajo la regla de respiro, entierro y cierre definitivo solo como chief_auditor.
# PROPIETARIO DE: nada.
# ESCUCHA: case_went_cold, case_revived, investigation_resolved (vía SignalLog).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")
const CASES_FOR_REVIEW := 20
const SILENT_CASES := 40
const AUDITOR_ID := "npc_new_auditor"

var _log: Fx.SignalLog


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	_test_archive_keeps_evidence()
	_test_auditor_change_revival()
	_test_silent_witness()
	_test_late_trail_revives_fraud_case()
	_test_bribes_on_cases()
	_test_permanent_close_only_as_chief_auditor()
	if _log != null:
		_log.stop()


func _fresh(run_seed: int = DEFAULT_SEED) -> void:
	if _log != null:
		_log.stop()
	new_run(run_seed, false)
	_log = Fx.SignalLog.new().watch(["case_went_cold", "case_revived", "investigation_resolved"])


## Caso de peso bajo (incidente sin autor 3,0) en una sala propia, archivado como frío.
func _cold_case(location: String) -> String:
	var case_id: String = Security.report_incident("object_missing", 1, location, true,
			{"weight": 3.0, "always_opens": true})
	Security.resolve_investigation(case_id, "cold", "")
	return case_id


func _test_archive_keeps_evidence() -> void:
	_fresh()
	var d0: int = Security.get_current_day()
	EventBus.hour_passed.emit(10, d0)
	var footage: String = Security.register_camera_footage(Fx.SEALED_ROOM, d0, 10)
	var case_id: String = Security.report_incident("object_missing", 1, Fx.SEALED_ROOM, true,
			{"weight": 3.0, "always_opens": true})
	var inv: Investigation = Security.get_investigation(case_id)
	var guard: int = Investigation.MAX_PHASE
	while inv.is_active() and guard > 0:
		Fx.advance_days(1)
		guard -= 1
	check_eq(inv.status, Investigation.STATUS_COLD, "footage 4.5 alone (< 7.0) → the case goes cold")
	check(_log.of("case_went_cold").has([case_id]), "case_went_cold emitted")
	check(Security.get_cold_cases().has(inv), "listed among cold cases")
	check_eq(inv.evidence.size(), 2, "archived with its evidence (incident + footage)")
	Fx.enter_room("monitor_room")
	check(Security.delete_footage(footage), "the tape itself can still be deleted")
	check_eq(inv.evidence.size(), 2, "the archived file keeps the footage piece (permanent record)")
	Fx.advance_days(20)
	check_eq(inv.status, Investigation.STATUS_COLD, "a cold case does not revive by itself")
	Security.add_evidence(case_id, "partial_witness", 0.8, Fx.PLAYER)
	check(_log.of("case_revived").has([case_id, "new_piece"]),
			"a new piece added by the player's hands revives it at once (case_revived new_piece)")
	check(inv.is_active() and inv.phase == InvestigationEngine.PHASE_COLLECTION,
			"revived case collects evidence again")
	check_eq(inv.evidence.size(), 3, "the old evidence is still there, plus the new piece")


## Cambio de ocupante en Auditoría: 40% de revisión por expediente, con la RNG de la partida
## (semilla de GameClock). Los elegidos no los provoca el jugador: se reactivan de uno en uno,
## cada 3 jornadas (§15.3).
func _test_auditor_change_revival() -> void:
	var chance: float = Fx.bal("investigaciones.prob_revision_al_cambiar_auditor")
	check_near(chance, 0.4, 0.0001, "auditor change reviews archived files with 40% chance")
	var first: Array[String] = _auditor_selection(DEFAULT_SEED)
	var again: Array[String] = _auditor_selection(DEFAULT_SEED)
	var other: Array[String] = _auditor_selection(DEFAULT_SEED + 7)
	check(first.size() >= 2 and first.size() <= 14,
			"%d of %d cold cases selected for review (binomial 20 × 0.4)" % [first.size(),
			CASES_FOR_REVIEW])
	check_eq(again, first, "same run seed → exactly the same cases selected")
	check(other != first, "another run seed → another selection (the RNG follows the run seed)")
	_check_one_revival_per_rest(first)
	_fresh()
	var case_id: String = _cold_case("test_room_player_auditor")
	EventBus.seat_filled.emit("chief_auditor", Fx.PLAYER)
	EventBus.seat_filled.emit("cfo", AUDITOR_ID)
	Fx.advance_days(3)
	check_eq(_log.count("case_revived") + Security.get_pending_revivals().size(), 0,
			"no review when the player takes the seat or another seat changes")
	check_eq(Security.get_investigation(case_id).status, Investigation.STATUS_COLD, "still cold")


## Casos elegidos por la revisión (reactivados ya + en cola), en orden.
func _auditor_selection(run_seed: int) -> Array[String]:
	_fresh(run_seed)
	for i: int in CASES_FOR_REVIEW:
		_cold_case("test_room_%d" % i)
	check_eq(Security.get_cold_cases().size(), CASES_FOR_REVIEW, "%d cases archived" % CASES_FOR_REVIEW)
	EventBus.seat_filled.emit("chief_auditor", AUDITOR_ID)
	var selected: Array[String] = []
	for args: Array in _log.of("case_revived"):
		selected.append(str(args[0]))
	selected.append_array(Security.get_pending_revivals())
	return selected


## Tras la revisión de la última semilla: ninguno revive el día del archivo (respiro), después
## uno cada 3 jornadas, en el orden de la cola.
func _check_one_revival_per_rest(selected: Array[String]) -> void:
	_auditor_selection(DEFAULT_SEED)
	check_eq(_log.count("case_revived"), 0, "the files were archived today: no revival yet")
	var rest: int = Database.get_balance_int("investigaciones.jornadas_respiro_minimo")
	Fx.advance_days(rest - 1)
	check_eq(_log.count("case_revived"), 0, "still none before the 3-day rest")
	Fx.advance_days(1)
	var revived: Array[Array] = _log.of("case_revived")
	check(revived.size() == 1 and revived[0] == [selected[0], "auditor_change"],
			"day 3: exactly the first selected case revives")
	Fx.advance_days(rest)
	check(_log.count("case_revived") == 2 and _log.last("case_revived")[0] == selected[1],
			"three days later the next one: never two unprovoked investigations back to back")


## Testigo silencioso: p = agravio acumulado desde el archivo × 0,02 (tope 0,8), por caso.
func _test_silent_witness() -> void:
	var trigger: Dictionary = InvestigationEngine.find_by_id(InvestigationEngine.dig(
			Database.get_investigation_params(), "cold_case_revival.triggers", []), "silent_witness")
	var per: float = float(trigger["probability_per_grievance_severity"])
	var cap: float = float(trigger["max_probability"])
	check_near(InvestigationEngine.silent_witness_chance(10, per, cap), 0.2, 0.0001,
			"chance proportional to grievances since archive (10 × 0.02)")
	check_near(InvestigationEngine.silent_witness_chance(100, per, cap), cap, 0.0001, "capped")
	var first: Array[String] = _silent_selection(DEFAULT_SEED)
	check(first.size() >= 2 and first.size() <= 16,
			"one grievance of severity 10: %d of %d files reopened (binomial 40 × 0.2)" % [
			first.size(), SILENT_CASES])
	check_eq(_silent_selection(DEFAULT_SEED), first, "same run seed → same witnesses talk")
	var before: int = Security.get_pending_revivals().size()
	EventBus.grievance_added.emit("npc_silent", "passed_over", 40)
	check(Security.get_pending_revivals().size() > before,
			"more grievance since the archive (sum 50 → p 0.8 capped): more files reopen")


func _silent_selection(run_seed: int) -> Array[String]:
	_fresh(run_seed)
	for i: int in SILENT_CASES:
		var case_id: String = Security.report_incident("object_missing", 1, "test_room_s%d" % i,
				true, {"weight": 3.0, "always_opens": true})
		Security.add_silent_witness(case_id, "npc_silent")
		Security.resolve_investigation(case_id, "cold", "")
	EventBus.grievance_added.emit("npc_talkative", "demoted", 50)
	EventBus.grievance_added.emit("npc_silent", "slighted", 0)
	check_eq(Security.get_pending_revivals().size(), 0,
			"no grievance (or someone else's) → nobody talks")
	EventBus.grievance_added.emit("npc_silent", "passed_over", 10)
	var selected: Array[String] = Security.get_pending_revivals()
	for args: Array in _log.of("case_revived"):
		selected.append(str(args[0]))
	return selected


## Un asiento contable que aflora 14 jornadas después del fraude es una pieza nueva: reaviva el
## caso de fraude archivado, pero bajo la regla de respiro (no lo provoca un acto del jugador).
func _test_late_trail_revives_fraud_case() -> void:
	_fresh()
	Fx.enter_room("street")
	var d0: int = Security.get_current_day()
	EventBus.crime_committed.emit("fraud", "wing_3b", {"amount": 5000})
	EventBus.month_closed.emit(1)
	var case_id: String = Security.get_all_investigations()[0].id
	Security.resolve_investigation(case_id, "cold", "")
	_broadcast_days(d0 + 1, d0 + 13)
	check_eq(_log.count("case_revived"), 0, "the trail has not surfaced yet")
	var delay: int = int(Database.get_balance("creencias.registros_por_delito.fraud.retardo_dias"))
	_broadcast_days(d0 + 14, d0 + delay)
	check(_log.of("case_revived").has([case_id, "new_piece"])
			and Fx.piece_types(case_id).has("accounting_trail"),
			"the late accounting trail revives the archived fraud case (new piece)")
	_fresh()
	EventBus.crime_committed.emit("fraud", "wing_3b", {"amount": 5000})
	EventBus.month_closed.emit(1)
	var fraud: String = Security.get_all_investigations()[0].id
	Security.resolve_investigation(fraud, "cold", "")
	_broadcast_days(d0 + 1, d0 + delay - 1)
	Security.report_incident("object_missing", 1, "hr_office", true, {"weight": 3.5})
	_broadcast_days(d0 + delay, d0 + delay)
	check(Security.get_pending_revivals().has(fraud) and _log.count("case_revived") == 0,
			"a case opened the same day: the revival waits for the rest")
	var rest: int = Database.get_balance_int("investigaciones.jornadas_respiro_minimo")
	_broadcast_days(d0 + delay + 1, d0 + delay + rest)
	check(_log.of("case_revived").has([fraud, "new_piece"]), "and happens once the rest is over")


func _broadcast_days(from_day: int, to_day: int) -> void:
	for day: int in range(from_day, to_day + 1):
		EventBus.day_advanced.emit(day)


func _test_bribes_on_cases() -> void:
	_fresh()
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 1)
	EventBus.bribe_offered.emit(Fx.WITNESS, 1200, "lie_in_interrogation")
	EventBus.bribe_result.emit(Fx.WITNESS, true, "accepted")
	check(Security.get_investigation(case_id).evidence.is_empty(),
			"a witness paid to lie withdraws the testimony")
	check(Security.get_alibi(case_id).get("provider") == Fx.WITNESS
			and not bool(Security.get_alibi(case_id).get("genuine", true)),
			"and offers a bought alibi for the interrogation")
	var auditor: String = Company.get_seat_holder("chief_auditor")
	if auditor.is_empty():
		auditor = AUDITOR_ID
		EventBus.seat_filled.emit("chief_auditor", auditor)
	var buried: String = Fx.open_witness_case("hr_office", 10, 1)
	EventBus.bribe_offered.emit("npc_nobody", 52000, "bury_investigation")
	EventBus.bribe_result.emit("npc_nobody", true, "accepted")
	check(Security.get_investigation(buried).is_active(), "only the Chief Auditor can bury a case")
	check(Security.get_case_weight_against(Fx.PLAYER, buried)
			> Security.get_case_weight_against(Fx.PLAYER, case_id), "the new case is the heaviest")
	EventBus.bribe_offered.emit(auditor, 52000, "bury_investigation")
	EventBus.bribe_result.emit(auditor, true, "accepted")
	check_eq(Security.get_investigation(buried).status, Investigation.STATUS_COLD,
			"bribed Chief Auditor buries the heaviest open case: it goes cold (not closed)")
	check(Security.get_investigation(case_id).is_active(), "the other case stays open")


func _test_permanent_close_only_as_chief_auditor() -> void:
	_fresh()
	var cold: String = _cold_case("test_room_close")
	var active: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10, 1)
	check(not Security.close_case_permanently(cold), "cannot close a cold case without the seat")
	Fx.become("chief_auditor")
	check(not Security.close_case_permanently(active), "an active case cannot be closed for good")
	check(Security.close_case_permanently(cold), "as chief_auditor the cold case closes for good")
	check_eq(Security.get_investigation(cold).status, Investigation.STATUS_CLOSED, "status closed")
	check(_log.of("investigation_resolved").has([cold, "closed_permanently", ""]),
			"investigation_resolved(case, closed_permanently)")
	Security.add_evidence(cold, "partial_witness", 0.8, Fx.PLAYER)
	EventBus.seat_filled.emit("chief_auditor", AUDITOR_ID)
	check_eq(Security.get_investigation(cold).status, Investigation.STATUS_CLOSED,
			"a closed case never revives")
	check(not _log.of("case_revived").any(func(args: Array) -> bool: return args[0] == cold),
			"no case_revived for the closed case")
