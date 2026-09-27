# ledger_case.gd — Cuerpo de test_ledger: agravios/favores, permanencia, precio de soborno y señales que lo alimentan.
# PROPIETARIO DE: nada.
# ESCUCHA: grievance_added, favour_added, npc_removed (conexiones temporales del escenario).
extends TestCase

const GEORGE := "npc_george_penn"
const SONIA := "npc_sonia_vail"
const DEBBIE := "npc_debbie_foyle"
const NATE := "npc_nate_brackley"
const TOM := "npc_tom_iverson"
const AMELIA := "npc_amelia_cole"
const ALVIN := "npc_alvin_pyne"
const PEARL := "npc_pearl_osgood"
const RAY := "npc_ray_cudmore"
const DIANA := "npc_diana_sedgwick"
const BREE := "npc_bree_nash"
const ROSE := "npc_rose_miller"
const ROSE_DAY := 31
const DAYS_TO_WAIT := 40
const SEVERITY := 8
const MAGNITUDE := 5

var _grievances: Array = []
var _favours: Array = []
var _removed: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	EventBus.grievance_added.connect(func(n: String, t: String, s: int) -> void:
		_grievances.append([n, t, s]))
	EventBus.favour_added.connect(func(n: String, t: String, m: int) -> void:
		_favours.append([n, t, m]))
	EventBus.npc_removed.connect(func(n: String, c: String) -> void: _removed.append([n, c]))
	_check_add_entries()
	var chief: NPCRuntime = NPCDirector.get_npc_by_occupation("chief_auditor")
	_check_never_decay()
	await _check_retirement(chief)
	_check_price_and_bias()
	_check_expulsion_by_player()
	await _check_elimination_and_dismissal()
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


## §7.13: el día 31 Company jubila al Auditor Jefe generado para que Rose ocupe la silla. El
## jubilado deja la plantilla (no sigue yendo al despacho) sin agravio: no es obra del jugador.
func _check_retirement(chief: NPCRuntime) -> void:
	if not check(chief != null and not chief.is_named, "a generated chief auditor exists"):
		return
	check(not NPCDirector.is_active(chief.id) and NPCDirector.is_alive(chief.id)
			and chief.removed_cause == "retired", "day %d: the chief auditor retired" % ROSE_DAY)
	check_eq(NPCDirector.get_npc(ROSE).occupation_id, "chief_auditor", "Rose holds the seat")
	check(not NPCDirector.get_all_npcs().has(chief) and chief.current_room.is_empty()
			and chief.state == "removed", "the retiree is off staff and nowhere in the building")
	check(NPCDirector.get_ledger(chief.id)["grievances"].is_empty(),
			"a retirement is not the player's doing: no grievance")
	await wait_frames(1)
	check_eq(_removed.filter(func(e: Array) -> bool: return e[0] == chief.id),
			[[chief.id, "retired"]], "npc_removed(retired) is announced once, after Company's chain")


func _check_price_and_bias() -> void:
	var k_g: float = Database.get_balance_float("registro.precio_por_gravedad_agravio")
	var k_f: float = Database.get_balance_float("registro.precio_por_magnitud_favor")
	check_near(NPCDirector.get_bribe_price_modifier(DEBBIE), 1.0, 1e-9, "clean ledger → neutral price")
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	check_near(NPCDirector.get_bribe_price_modifier(GEORGE), Bribery.ledger_price_modifier(george),
			1e-9, "one price formula: NPCDirector and Bribery agree")
	check_eq(NPCDirector.get_fair_bribe_price(GEORGE, "look_away_once"),
			Bribery.fair_price(george, "look_away_once"), "fair price = Bribery.fair_price")
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
	var ctx: Dictionary = NPCDirector.build_context(GEORGE, NPCDirector.TRIGGER_BELIEF,
			{"certainty": 0.9})
	var clean: Dictionary = ctx.duplicate()
	clean["ledger"] = NPCRuntime.new_ledger()
	check(UtilityAI.score_action("report_to_security", george, ctx)
			> UtilityAI.score_action("report_to_security", george, clean),
			"the ledger term raises George's utility of reporting")


## §6.3 y §7.9 por el flujo real: remove_npc → npc_removed → Company vacía la silla → la repone.
## El expulsado registra seat_lost, sus amigos friend_sunk y quien asciende a su silla, un favor.
func _check_expulsion_by_player() -> void:
	var allies: Array[String] = _allies_of(RAY)
	check(not allies.is_empty(), "Ray has friends (%s)" % str(allies))
	_grievances.clear()
	_favours.clear()
	NPCDirector.remove_npc(RAY, "expelled")
	var expected: Array = [[RAY, "seat_lost", Database.get_balance_int("registro.gravedad_silla_perdida")]]
	for ally: String in allies:
		expected.append([ally, "friend_sunk", Database.get_balance_int("registro.gravedad_amigo_hundido")])
	check_eq(_grievances, expected, "expelled by the player: seat_lost + friend_sunk to his friends")
	check(NPCDirector.get_mood(RAY) < 0.0, "losing the seat sours the mood")
	check(Company.get_npc_seat(RAY).is_empty() and NPCDirector.get_npc(RAY).occupation_id.is_empty(),
			"Company freed the seat on npc_removed and NPCDirector cleared the occupation")
	Company.auto_fill_vacancies()
	var promoted: NPCRuntime = NPCDirector.get_npc(_favours[0][0]) if _favours.size() == 1 else null
	check(promoted != null and _favours[0][1] == "promotion"
			and _favours[0][2] == Database.get_balance_int("registro.magnitud_ascenso")
			and promoted.occupation_id == "order_filer",
			"the NPC promoted into the vacancy the player opened registers one favour (%s)" % str(_favours))
	check_eq(_grievances.size(), expected.size(), "the ordinary promotions of the chain add no grievance")


## Eliminación (sin agravio del muerto; sí de sus amigos) y despido decidido por Company con una
## causa del jugador sobre alguien en plantilla (deja la empresa y lo anuncia una vez).
func _check_elimination_and_dismissal() -> void:
	var allies: Array[String] = _allies_of(DIANA)
	check(not allies.is_empty(), "Diana has friends (%s)" % str(allies))
	_grievances.clear()
	NPCDirector.remove_npc(DIANA, "eliminated")
	check(_grievances.all(func(e: Array) -> bool: return e[0] != DIANA and e[1] == "friend_sunk")
			and _grievances.size() == allies.size(), "an elimination angers the victim's friends")
	var bree_allies: Array[String] = _allies_of(BREE)
	_grievances.clear()
	_removed.clear()
	check(Company.vacate_npc_seat(BREE, "fired"), "Company fires Bree")
	check(not NPCDirector.is_active(BREE) and NPCDirector.get_npc(BREE).removed_cause == "fired",
			"a fired NPC leaves the staff")
	check_eq(_grievances.size(), 1 + bree_allies.size(), "…with seat_lost and her friends' grievances")
	check(_grievances.size() > 0 and _grievances[0] == [BREE, "seat_lost",
			Database.get_balance_int("registro.gravedad_silla_perdida")], "Bree resents the dismissal")
	await wait_frames(1)
	check_eq(_removed, [[BREE, "fired"]], "npc_removed(fired) is announced once, deferred")


func _allies_of(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for link: Dictionary in SocialGraph.get_links(npc_id):
		var other: String = str(link.get("to", ""))
		if other == npc_id:
			other = str(link.get("from", ""))
		if ["friendship", "couple"].has(str(link.get("type", ""))) and NPCDirector.is_active(other) \
				and not out.has(other):
			out.append(other)
	return out


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


## §12.3 fase 5: Security sabe si el condenado era inocente. Culpable → condena sin agravios;
## incriminado o incidente del jugador → agravio permanente, aliados hostiles y expulsión.
func _check_investigation() -> void:
	var removed_before: int = _removed.size()
	var guilty_case: String = Security.open_investigation("object_missing", 2, "wing_3b")
	check(not guilty_case.is_empty(), "Security opens a case on its own")
	_grievances.clear()
	Security.resolve_investigation(guilty_case, "other_guilty", SONIA)
	check(_grievances.is_empty(), "a guilty NPC's conviction is not the player's doing: no grievance")
	check(not NPCDirector.is_active(SONIA) and NPCDirector.get_npc(SONIA).removed_cause == "convicted",
			"the guilty NPC is convicted (cause 'convicted', not a player-caused vacancy)")
	check_eq(_removed.slice(removed_before), [[SONIA, "convicted"]], "npc_removed(convicted)")
	var allies: Array[String] = _allies_of(ROSE)
	var framed_case: String = Security.report_incident("object_missing", 2, "internal_audit", true,
			{"always_opens": true})
	check(not framed_case.is_empty() and allies.size() > 0, "a player-caused case; Rose has friends")
	Security.resolve_investigation(framed_case, "other_guilty", ROSE)
	check_eq(_grievances.front(), [ROSE, "wrongful_conviction",
			Database.get_balance_int("registro.gravedad_condena_injusta")],
			"an innocent convicted NPC registers a permanent grievance")
	check_eq(_grievances.slice(1).map(func(e: Array) -> String: return e[0]), allies,
			"her friends turn hostile (friend_sunk)")
	check(not NPCDirector.is_active(ROSE) and NPCDirector.is_alive(ROSE)
			and NPCDirector.get_npc(ROSE).removed_cause == "expelled",
			"the innocent is expelled (a vacancy the player caused)")
	_grievances.clear()
	EventBus.investigation_resolved.emit("case_other", "player_minor", "player")
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
