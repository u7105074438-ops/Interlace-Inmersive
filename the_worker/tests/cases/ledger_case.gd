# ledger_case.gd — Cuerpo de test_ledger: agravios/favores, permanencia, precio de soborno y señales que lo alimentan.
# PROPIETARIO DE: nada.
# ESCUCHA: grievance_added, favour_added (conexiones temporales del escenario).
extends TestCase

const GEORGE := "npc_george_penn"
const SONIA := "npc_sonia_vail"
const DEBBIE := "npc_debbie_foyle"
const CLAUDIA := "npc_claudia_reeves"
const NATE := "npc_nate_brackley"
const TOM := "npc_tom_iverson"
const AMELIA := "npc_amelia_cole"
const ALVIN := "npc_alvin_pyne"
const PEARL := "npc_pearl_osgood"
const DAYS_TO_WAIT := 40
const SEVERITY := 8
const MAGNITUDE := 5

var _grievances: Array = []
var _favours: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	EventBus.grievance_added.connect(func(n: String, t: String, s: int) -> void:
		_grievances.append([n, t, s]))
	EventBus.favour_added.connect(func(n: String, t: String, m: int) -> void:
		_favours.append([n, t, m]))
	_check_add_entries()
	_check_never_decay()
	_check_price_and_bias()
	_check_seat_signals()
	_check_player_takes_seat()
	_check_investigation()
	_check_bribe_results()
	_check_blackmail_and_reputation()


func _check_add_entries() -> void:
	var per_severity: float = Database.get_balance_float("registro.afecto_por_gravedad_agravio")
	var per_magnitude: float = Database.get_balance_float("registro.afecto_por_magnitud_favor")
	NPCDirector.add_grievance(GEORGE, "idea_stolen", SEVERITY)
	check_eq(_grievances.back(), [GEORGE, "idea_stolen", SEVERITY], "add_grievance emits grievance_added")
	var ledger: Dictionary = NPCDirector.get_ledger(GEORGE)
	check_eq(ledger["grievances"], [{"type": "idea_stolen", "severity": SEVERITY,
			"day": GameClock.get_day()}], "grievance stored as {type, severity, day} (§7.9)")
	check_eq(NPCDirector.get_affection(GEORGE), -roundi(SEVERITY * per_severity),
			"grievances reduce affection")
	NPCDirector.add_favour(SONIA, "cover_up", MAGNITUDE)
	check_eq(_favours.back(), [SONIA, "cover_up", MAGNITUDE], "add_favour emits favour_added")
	check_eq(NPCDirector.get_ledger(SONIA)["favours"], [{"type": "cover_up",
			"magnitude": MAGNITUDE, "day": GameClock.get_day()}], "favour stored as {type, magnitude, day}")
	check_eq(NPCDirector.get_affection(SONIA), roundi(MAGNITUDE * per_magnitude),
			"favours raise affection")
	ledger["grievances"].clear()
	check_eq(NPCDirector.get_grievance_total(GEORGE), SEVERITY, "get_ledger returns a copy")


## §7.9: «Los agravios no decaen. Persisten durante toda la partida.»
func _check_never_decay() -> void:
	var before: Dictionary = NPCDirector.get_ledger(GEORGE)
	for i: int in DAYS_TO_WAIT:
		EventBus.day_advanced.emit(GameClock.get_day() + i + 1)
	check_eq(NPCDirector.get_ledger(GEORGE), before, "after %d days the ledger is intact" % DAYS_TO_WAIT)
	check_eq(NPCDirector.get_grievance_total(GEORGE), SEVERITY, "grievance severity never decays")


func _check_price_and_bias() -> void:
	var k_g: float = Database.get_balance_float("registro.precio_por_gravedad_agravio")
	var k_f: float = Database.get_balance_float("registro.precio_por_magnitud_favor")
	check_near(NPCDirector.get_bribe_price_modifier(DEBBIE), 1.0, 1e-9, "clean ledger → neutral price")
	check_near(NPCDirector.get_bribe_price_modifier(GEORGE), 1.0 + SEVERITY * k_g, 1e-9,
			"grievances raise the bribe price")
	check_near(NPCDirector.get_bribe_price_modifier(SONIA), 1.0 - MAGNITUDE * k_f, 1e-9,
			"favours lower the bribe price")
	var favour: String = "silence_witnessed"
	check(NPCDirector.get_fair_bribe_price(GEORGE, favour) > NPCDirector.get_daily_wage(GEORGE)
			* int(Database.get_bribe_favour(favour)["multiplier"]),
			"George's fair price exceeds wage × 20 because of his grievance")
	NPCDirector.add_grievance(NATE, "framed", 1000)
	check_near(NPCDirector.get_bribe_price_modifier(NATE),
			Database.get_balance_float("registro.precio_modificador_max"), 1e-9, "price modifier is capped")
	check(NPCDirector.get_denunciation_bias(GEORGE) > NPCDirector.get_denunciation_bias(DEBBIE),
			"grievances accelerate denunciation")
	check(NPCDirector.get_denunciation_bias(SONIA) < NPCDirector.get_denunciation_bias(DEBBIE),
			"favours slow denunciation")
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	var ctx: Dictionary = NPCDirector.build_context(GEORGE, NPCDirector.TRIGGER_BELIEF,
			{"certainty": 0.9})
	var clean: Dictionary = ctx.duplicate()
	clean["ledger"] = NPCRuntime.new_ledger()
	check(UtilityAI.score_action("report_to_security", george, ctx)
			> UtilityAI.score_action("report_to_security", george, clean),
			"the ledger term raises George's utility of reporting")


## §6.3: el que pierde la silla por obra del jugador registra un agravio; quien asciende, un favor.
func _check_seat_signals() -> void:
	var intern: NPCRuntime = NPCDirector.get_npc_by_occupation("eternal_intern")
	_grievances.clear()
	_favours.clear()
	EventBus.seat_vacated.emit("email_worker_3b", CLAUDIA, "framed")
	check_eq(_grievances, [[CLAUDIA, "seat_lost",
			Database.get_balance_int("registro.gravedad_silla_perdida")]],
			"a player-caused vacancy leaves a grievance on the ousted holder")
	check_eq(NPCDirector.get_npc(CLAUDIA).occupation_id, "", "the ousted NPC loses the occupation")
	check(NPCDirector.get_mood(CLAUDIA) < 0.0, "losing the seat sours the mood")
	EventBus.seat_vacated.emit("eternal_intern", intern.id, "promotion")
	EventBus.seat_filled.emit("email_worker_3b", intern.id)
	check_eq(_favours, [[intern.id, "promotion", Database.get_balance_int("registro.magnitud_ascenso")]],
			"the NPC promoted thanks to the player registers a favour")
	check_eq(_grievances.size(), 1, "an ordinary promotion vacancy adds no grievance")
	check_eq(intern.occupation_id, "email_worker_3b", "seat_filled updates the occupation")
	check_eq([intern.tier, intern.home_room], [1, "wing_3b"], "tier and workplace follow the seat")
	_favours.clear()
	EventBus.seat_filled.emit("order_filer", "npc_gen_050")
	check(_favours.is_empty(), "a vacancy not caused by the player gives no favour")


func _check_player_takes_seat() -> void:
	var target: String = "wing_3b_chief"
	var best: String = ""
	var best_score: float = -INF
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var occ: OccupationData = Database.get_occupation(npc.occupation_id)
		if occ == null or not occ.promotes_to.has(target):
			continue
		var score: float = npc.merit * Database.get_balance_float("npc.puntuacion_ascenso_merito") \
				+ npc.get_trait("ambition") * Database.get_balance_float("npc.puntuacion_ascenso_ambicion")
		if score > best_score:
			best_score = score
			best = npc.id
	_grievances.clear()
	EventBus.seat_filled.emit(target, "player")
	check(not best.is_empty() and _grievances == [[best, "promotion_stolen",
			Database.get_balance_int("registro.gravedad_ascenso_arrebatado")]],
			"the best-placed candidate resents the player taking the seat (%s)" % best)


func _check_investigation() -> void:
	_grievances.clear()
	EventBus.investigation_resolved.emit("case_test", "other_guilty", SONIA)
	check_eq(_grievances.front(), [SONIA, "wrongful_conviction",
			Database.get_balance_int("registro.gravedad_condena_injusta")],
			"an innocent convicted NPC registers a permanent grievance")
	check(not NPCDirector.is_active(SONIA) and NPCDirector.is_alive(SONIA)
			and NPCDirector.get_npc(SONIA).removed_cause == "expelled",
			"the convicted NPC is expelled (Company frees the seat on npc_removed)")
	_grievances.clear()
	EventBus.investigation_resolved.emit("case_other", "player_guilty_minor", "player")
	EventBus.investigation_resolved.emit("case_cold", "cold", "")
	check(_grievances.is_empty(), "verdicts against the player or cold cases add no NPC grievance")


func _check_bribe_results() -> void:
	_grievances.clear()
	_favours.clear()
	EventBus.bribe_result.emit(TOM, true, "accepted")
	check_eq(_favours, [[TOM, "bribe_paid", Database.get_balance_int("registro.magnitud_soborno_aceptado")]],
			"an accepted bribe is a favour (payment, §7.9)")
	check_eq(NPCDirector.get_debt(TOM), Database.get_balance_int("registro.deuda_por_soborno_aceptado"),
			"an accepted bribe puts the NPC in debt with the player")
	check_eq(NPCDirector.get_lod(TOM), 0, "debt with the player forces full LOD (§20.2)")
	EventBus.bribe_result.emit(AMELIA, false, "denounce")
	check_eq(_grievances.back(), [AMELIA, "bribe_offence",
			Database.get_balance_int("registro.gravedad_soborno_denunciado")],
			"a denounced bribe offends the NPC")
	EventBus.bribe_result.emit(ALVIN, false, "silence_with_memory")
	check_eq(NPCDirector.get_fear(ALVIN), Database.get_balance_int("registro.temor_por_silencio_soborno"),
			"silent refusal leaves fear (§8.2 silencio con memoria)")
	var before: int = _grievances.size()
	EventBus.bribe_result.emit(DEBBIE, false, "counteroffer")
	EventBus.bribe_result.emit(DEBBIE, false, "insufficient_funds")
	check_eq(_grievances.size(), before, "a counteroffer or a void offer does not offend")
	EventBus.bribe_result.emit(DEBBIE, false, "neutral_refusal")
	check_eq(_grievances.back(), [DEBBIE, "bribe_offence",
			Database.get_balance_int("registro.gravedad_soborno_rechazado")],
			"a neutral refusal leaves a small grievance")


func _check_blackmail_and_reputation() -> void:
	EventBus.blackmail_initiated.emit("player", PEARL, "personnel_file")
	check_eq(NPCDirector.get_fear(PEARL), Database.get_balance_int("registro.temor_por_chantaje"),
			"being blackmailed by the player raises fear")
	check(NPCDirector.get_grievance_total(PEARL) > 0, "…and leaves a grievance")
	var npc: NPCRuntime = NPCDirector.get_npc(DEBBIE)
	var expected: float = Database.get_balance_float("npc.reputacion_base") \
			+ npc.tier * Database.get_balance_float("npc.reputacion_por_escalon") \
			+ npc.merit * Database.get_balance_float("npc.reputacion_por_merito") \
			- NPCDirector.get_grievance_total(DEBBIE) \
			* Database.get_balance_float("npc.reputacion_por_gravedad_agravio")
	check_near(NPCDirector.get_npc_reputation(DEBBIE), clampf(expected, 0.0, 100.0), 1e-6,
			"NPC reputation = base + tier + merit − grievances (BUILD_NOTES §13)")
	check(NPCDirector.get_npc_reputation(NATE) < NPCDirector.get_npc_reputation(DEBBIE),
			"an NPC holding grievances is a less credible accuser")
	check(NPCDirector.knows_player(GEORGE), "anyone with a ledger entry knows the player")
	check_eq(NPCDirector.get_npc_reputation("unknown_id"), 0.0, "unknown ids have no reputation")
	var before: float = NPCDirector.get_npc_reputation(DEBBIE)
	NPCDirector.modify_npc_reputation(DEBBIE, -15.0, "aurora_false_accusation")
	check_near(NPCDirector.get_npc_reputation(DEBBIE), before - 15.0, 1e-6,
			"modify_npc_reputation adjusts it permanently (IdeaPresentation §11.2)")
	for type: String in [NPCDirector.GRIEVANCE_SEAT_LOST, NPCDirector.GRIEVANCE_PROMOTION_STOLEN,
			NPCDirector.GRIEVANCE_WRONGFUL_CONVICTION, NPCDirector.GRIEVANCE_FRIEND_SUNK,
			NPCDirector.GRIEVANCE_IDEA_STOLEN, NPCDirector.GRIEVANCE_BLACKMAILED,
			NPCDirector.GRIEVANCE_BRIBE_OFFENCE]:
		var key: String = NPCDirectorSystem.grievance_name_key(type)
		check(tr(key) != key, "grievance %s has a visible name" % type)
