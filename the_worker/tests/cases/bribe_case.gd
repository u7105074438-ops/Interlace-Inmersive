# bribe_case.gd — Cuerpo de test_bribe: la fórmula de sobornos de §8.2 y sus consecuencias.
# PROPIETARIO DE: nada.
# ESCUCHA: bribe_offered, bribe_result, crime_committed, game_over (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
## Números literales del manual §8.2: el caso comprueba que balance.json y el código los respetan.
const M_BASE := 0.10
const M_GREED := 0.40
const M_RATIO := 0.20
const M_AFFECTION := 0.10
const M_REPUTATION := 0.10
const M_SUSPICION := -0.30
const M_COURAGE := -0.15
const M_LOYALTY := -0.20
const M_RANK := 0.10
const M_MAX_P := 0.95
const M_INSULT_FACTOR := 0.33
const EPS := 0.000001
const RICH := 1000000
const EXTRA_SEEDS: Array[int] = [7, 99, 2024]
## Contexto neutro: sin reputación, sospecha, registro ni relación jerárquica; precio sin registro.
const NEUTRAL: Dictionary = {"reputation": 0.0, "suspicion": 0.0, "affection": 0, "debt": 0,
		"rank_relation": 0, "price_modifier": 1.0}
const WATCHED: Array[String] = ["bribe_offered", "bribe_result", "crime_committed", "game_over"]

var _log: Fixtures.SignalLog = null


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_check_manual_price_table()
	_check_wages_and_fair_price()
	_check_population_prices()
	_check_suspicion_price()
	_check_difficulty_presets()
	_check_unbribable()
	_check_generated_incorruptibles()
	_check_frank_rudd()
	_check_formula_terms()
	_check_clamp_and_exception()
	_check_rank_relation()
	_check_insulting_offer()
	_check_ledger()
	_check_rejection_table()
	_check_offer_outcomes()
	_check_counteroffer_negotiation()
	_check_counteroffer_tokens()
	_check_no_reroll()
	_check_channels()
	_log.stop()
	await get_tree().process_frame


func _expected_p(traits: Dictionary, ratio: float, inputs: Dictionary) -> float:
	return M_BASE + M_GREED * traits["greed"] / 100.0 + M_RATIO * ratio \
			+ M_AFFECTION * (inputs.get("affection", 0) + inputs.get("debt", 0)) / 100.0 \
			+ M_REPUTATION * inputs.get("reputation", 0.0) / 100.0 \
			+ M_SUSPICION * inputs.get("suspicion", 0.0) / 100.0 \
			+ M_COURAGE * traits["courage"] / 100.0 + M_LOYALTY * traits["loyalty"] / 100.0 \
			+ M_RANK * inputs.get("rank_relation", 0)


func _ctx(extra: Dictionary) -> Dictionary:
	var ctx: Dictionary = NEUTRAL.duplicate()
	ctx.merge(extra, true)
	return ctx


func _check_manual_price_table() -> void:
	var table: Array = [[70, "look_away_once", 210], [56, "lend_access", 448],
			[120, "praise_to_superior", 1800], [30, "silence_witnessed", 600],
			[300, "silence_witnessed", 6000], [300, "lie_in_interrogation", 12000],
			[520, "bury_investigation", 52000], [800, "vote_in_board", 200000]]
	for row: Array in table:
		check_eq(Bribery.base_price(row[0], row[1]), row[2],
				"§8.2 table: wage %d × %s = %d" % [row[0], row[1], row[2]])


func _check_wages_and_fair_price() -> void:
	check_eq(Bribery.npc_daily_wage(Fixtures.named("npc_frank_rudd")), 56,
			"Frank Rudd earns the maintenance_aide wage (56)")
	check_eq(Bribery.npc_daily_wage(Fixtures.named("npc_tom_iverson")), 70,
			"Tom Iverson earns the security_guard wage (70)")
	check_eq(Bribery.npc_daily_wage(Fixtures.named("npc_rose_miller")), 90,
			"Rose Miller (no seat) earns her auditor role wage (90)")
	check_eq(Bribery.npc_daily_wage(Fixtures.named("npc_george_penn")), 30,
			"George Penn earns the email_worker_3b wage (30)")
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	check_eq(Bribery.fair_price(frank, "lend_access", NEUTRAL), 448,
			"fair price = daily wage × favour multiplier (Frank, lend access: 448)")
	check_eq(Bribery.fair_price(Fixtures.named("npc_rose_miller"), "silence_witnessed", NEUTRAL),
			1800, "Rose Miller's silence costs 90 × 20 = 1800")
	var loose: NPCRuntime = Fixtures.synthetic("test_no_wage", "burnout", {}, "")
	loose.tier = 1
	check_eq(Bribery.npc_daily_wage(loose), Bribery.tier_daily_wage(1),
			"no seat, no role → the tier average wage")


## Regresión: los puestos no jugables generados cobran su salario de rol, y el precio justo de
## Bribery coincide con el de NPCDirector para toda la plantilla (sospecha 0).
func _check_population_prices() -> void:
	var wage_diffs: int = 0
	var price_diffs: int = 0
	var role_npc: NPCRuntime = null
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if Bribery.npc_daily_wage(npc) != NPCDirector.get_daily_wage(npc.id):
			wage_diffs += 1
		for favour: String in ["look_away_once", "silence_witnessed", "bury_investigation"]:
			if Bribery.fair_price(npc, favour, {"suspicion": 0.0}) \
					!= NPCDirector.get_fair_bribe_price(npc.id, favour):
				price_diffs += 1
		if role_npc == null and not npc.is_named and not NPCDirector.get_role(npc.id).is_empty():
			role_npc = npc
	check(NPCDirector.get_all_npcs().size() > 100, "the population is generated")
	check_eq(wage_diffs, 0, "every NPC's bribe wage is NPCDirector's daily wage")
	check_eq(price_diffs, 0, "Bribery.fair_price == NPCDirector.get_fair_bribe_price for all NPCs")
	check(role_npc != null, "a generated role NPC exists")
	if role_npc != null:
		var role_wage: int = int(Database.get_role(NPCDirector.get_role(role_npc.id))["daily_wage"])
		check_eq(Bribery.npc_daily_wage(role_npc), role_wage,
				"generated %s earns the %s role wage" % [role_npc.id, NPCDirector.get_role(role_npc.id)])
		check_eq(Bribery.fair_price(role_npc, "silence_witnessed", _ctx({})), role_wage * 20,
				"their silence costs role wage × 20")


## §7.10: la sospecha encarece el soborno (sobornos.mod_precio_por_sospecha).
func _check_suspicion_price() -> void:
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	var mod: float = Database.get_balance_float("sobornos.mod_precio_por_sospecha")
	check(mod > 0.0, "suspicion has a price modifier")
	for suspicion: float in [0.0, 40.0, 100.0]:
		check_eq(Bribery.fair_price(frank, "lend_access", _ctx({"suspicion": suspicion})),
				roundi(448.0 * (1.0 + mod * suspicion / 100.0)),
				"suspicion %d makes the envelope dearer" % int(suspicion))
	var fair_s: int = Bribery.fair_price(frank, "lend_access", _ctx({"suspicion": 100.0}))
	var p0: float = Bribery.acceptance_probability(frank, 448, "lend_access", NEUTRAL)
	var p1: float = Bribery.acceptance_probability(frank, 448, "lend_access",
			_ctx({"suspicion": 100.0}))
	check_near(p1 - p0, M_SUSPICION + M_RATIO * (Bribery.offer_ratio(448, fair_s) - 0.5), EPS,
			"suspicion lowers P twice: −0.30 term and a worse offer ratio")


func _check_difficulty_presets() -> void:
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	var no_ledger: Dictionary = {"price_modifier": 1.0, "suspicion": 0.0}
	Database.set_difficulty_preset("interno")
	check_eq(Bribery.fair_price(frank, "lend_access", no_ledger), 336,
			"§15.7 Interno preset: bribes × 0.75 (448 → 336)")
	Database.set_difficulty_preset("auditoria")
	check_eq(Bribery.fair_price(frank, "lend_access", no_ledger), 560,
			"§15.7 Auditoría preset: bribes × 1.25 (448 → 560)")
	Database.set_difficulty_preset("estandar")
	check_eq(Bribery.fair_price(frank, "lend_access", no_ledger), 448,
			"§15.7 Estándar preset: bribes × 1.00")


func _check_unbribable() -> void:
	var generous: Dictionary = {"reputation": 100.0, "suspicion": 0.0, "affection": 100,
			"debt": 100, "rank_relation": Bribery.RANK_PLAYER_SUPERIOR, "price_modifier": 1.0}
	for npc_id: String in ["npc_rose_miller", "npc_amelia_cole", "npc_pearl_osgood"]:
		var npc: NPCRuntime = Fixtures.named(npc_id)
		check_eq(_worst_case_p(npc, generous), 0.0,
				"%s: P = 0 whatever the offer (greed < 20, loyalty > 80)" % npc.name)
	var rose: NPCRuntime = Fixtures.named("npc_rose_miller")
	_log.clear()
	var result: Dictionary = Bribery.offer(rose, 50000, "look_away_once", "in_person",
			_ctx({"wallet": Fixtures.FakeWallet.new(RICH), "roll": 0.0}))
	check(not bool(result["accepted"]), "Rose Miller refuses even a 50000 envelope with roll 0")
	check_eq(result["outcome"], Bribery.OUTCOME_DENOUNCED, "Rose Miller (loyalty 92) denounces it")
	var over: Array = _log.last("game_over")
	check(not over.is_empty() and over[0] == "bribe_denounced" and over[1] == "the_file",
			"denounced bribe → game_over('bribe_denounced', 'the_file')")


func _worst_case_p(npc: NPCRuntime, ctx: Dictionary) -> float:
	var fair: int = Bribery.fair_price(npc, "look_away_once", ctx)
	var worst: float = 0.0
	for offer: int in [1, fair / 2, fair, fair * 2, fair * 100]:
		worst = maxf(worst, Bribery.acceptance_probability(npc, offer, "look_away_once", ctx))
	return worst


## Regresión §8.1: el incorruptible es nulo por definición, aunque la variación ±15 lo saque de la
## regla de rasgos (codicia 0 / lealtad 80 no cumple «lealtad > 80»).
func _check_generated_incorruptibles() -> void:
	var generous: Dictionary = _ctx({"reputation": 100.0, "affection": 100, "debt": 100,
			"rank_relation": Bribery.RANK_PLAYER_SUPERIOR})
	var edge: NPCRuntime = Fixtures.synthetic("test_edge_incorruptible", "incorruptible",
			{"greed": 0, "loyalty": 80, "courage": 60})
	check(not Bribery.is_unbribable(edge.traits), "greed 0 / loyalty 80 escapes the trait rule")
	check_eq(_worst_case_p(edge, generous), 0.0, "…but an incorruptible still has P = 0")
	var decision: Dictionary = Bribery.evaluate(edge, 100000, "look_away_once",
			_ctx({"roll": 0.0}))
	check(not bool(decision["accepted"]), "an incorruptible never accepts, even with roll 0")
	var checked: int = 0
	var bribable: int = 0
	for run_seed: int in [DEFAULT_SEED] + EXTRA_SEEDS:
		new_run(run_seed)
		for npc: NPCRuntime in NPCDirector.get_npcs_by_archetype("incorruptible"):
			checked += 1
			if _worst_case_p(npc, generous) > 0.0:
				bribable += 1
	check(checked > 10, "%d generated/named incorruptibles checked over %d seeds"
			% [checked, EXTRA_SEEDS.size() + 1])
	check_eq(bribable, 0, "no incorruptible of any seed has P > 0")
	new_run()


func _check_frank_rudd() -> void:
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	var inputs: Dictionary = {"reputation": 50.0, "suspicion": 10.0}
	var fair: int = Bribery.fair_price(frank, "lend_access", _ctx(inputs))
	var p: float = Bribery.acceptance_probability(frank, fair * 2, "lend_access", _ctx(inputs))
	check_near(p, _expected_p(frank.traits, 1.0, inputs), EPS,
			"Frank Rudd, double offer: P matches the §8.2 formula term by term")
	check_near(p, 0.491, EPS, "Frank Rudd (greed 58, loyalty 14, courage 22): P = 0.491")
	check(p > 0.45, "Frank Rudd is cheap and willing: high acceptance probability")
	for other_id: String in ["npc_george_penn", "npc_bernard_lasker", "npc_amelia_cole"]:
		var other: NPCRuntime = Fixtures.named(other_id)
		var other_fair: int = Bribery.fair_price(other, "lend_access", _ctx(inputs))
		check(p > Bribery.acceptance_probability(other, other_fair * 2, "lend_access",
				_ctx(inputs)), "Frank Rudd is easier to bribe than %s" % other.name)


## Cada término de P con precio justo fijo (probability_from): el desplazamiento es el del manual.
func _check_formula_terms() -> void:
	var npc: NPCRuntime = Fixtures.synthetic("test_mid", "bribable",
			{"greed": 80, "loyalty": 20, "courage": 20})
	var fair: int = Bribery.fair_price(npc, "praise_to_superior", NEUTRAL)
	var base: float = Bribery.probability_from(npc.traits, fair, fair, NEUTRAL)
	check_near(base, _expected_p(npc.traits, 0.5, {}), EPS, "fair offer → ratio_oferta 0.5")
	check_near(Bribery.acceptance_probability(npc, fair, "praise_to_superior", NEUTRAL), base,
			EPS, "acceptance_probability = probability_from at the fair price")
	var terms: Array = [["reputation", 100.0, M_REPUTATION], ["suspicion", 100.0, M_SUSPICION],
			["affection", 50, M_AFFECTION * 0.5], ["debt", 30, M_AFFECTION * 0.3],
			["rank_relation", Bribery.RANK_PLAYER_SUPERIOR, M_RANK],
			["rank_relation", Bribery.RANK_NPC_SUPERIOR, -M_RANK]]
	for term: Array in terms:
		var p: float = Bribery.probability_from(npc.traits, fair, fair, _ctx({term[0]: term[1]}))
		check_near(p - base, term[2], EPS, "term %s = %s shifts P by %s" % term)
	check_near(Bribery.offer_ratio(fair * 3, fair), 1.0, EPS, "ratio_oferta is capped at 2.0 / 2.0")
	check_near(Bribery.offer_ratio(fair, fair), 0.5, EPS, "ratio_oferta(fair) = 0.5")
	check_eq(Bribery.acceptance_probability(npc, fair * 3, "praise_to_superior", NEUTRAL),
			Bribery.acceptance_probability(npc, fair * 2, "praise_to_superior", NEUTRAL),
			"offering more than twice the fair price adds nothing")


func _check_clamp_and_exception() -> void:
	var greedy: NPCRuntime = Fixtures.synthetic("test_greedy", "bribable",
			{"greed": 100, "loyalty": 0, "courage": 0})
	var fair: int = Bribery.fair_price(greedy, "look_away_once", NEUTRAL)
	var best: Dictionary = _ctx({"reputation": 100.0, "affection": 100, "debt": 100,
			"rank_relation": Bribery.RANK_PLAYER_SUPERIOR})
	check_near(Bribery.acceptance_probability(greedy, fair * 2, "look_away_once", best), M_MAX_P,
			EPS, "P is clamped to 0.95")
	var hopeless: NPCRuntime = Fixtures.synthetic("test_hopeless", "hardliner",
			{"greed": 20, "loyalty": 80, "courage": 100})
	check_eq(Bribery.acceptance_probability(hopeless, 1, "look_away_once",
			_ctx({"suspicion": 100.0})), 0.0, "P is clamped to 0.00 from below")
	var cases: Array = [[19, 81, true], [20, 81, false], [19, 80, false]]
	for row: Array in cases:
		check_eq(Bribery.is_unbribable({"greed": row[0], "loyalty": row[1]}), row[2],
				"absolute exception: greed %d, loyalty %d → unbribable %s" % row)


func _check_rank_relation() -> void:
	var rows: Array = [
		["email_worker_3b", "wing_3b_chief", Bribery.RANK_NPC_SUPERIOR,
				"the wing 3B chief is the email worker's direct superior (−0.10)"],
		["wing_3b_chief", "email_worker_3b", Bribery.RANK_PLAYER_SUPERIOR,
				"a wing 3B chief player is the email workers' direct superior (+0.10)"],
		["email_worker_3b", "order_filer", Bribery.RANK_NONE,
				"a colleague one rank up is not a hierarchical superior"],
		["email_worker_3b", "ceo", Bribery.RANK_NPC_SUPERIOR,
				"the CEO is a superior of everyone, even if not direct (−0.10)"],
		["email_worker_3b", "purchasing_chief", Bribery.RANK_NPC_SUPERIOR,
				"a chief higher up the same department is a superior (−0.10)"],
		["purchasing_chief", "email_worker_3b", Bribery.RANK_NONE,
				"…but the player needs to be the DIRECT superior for +0.10"],
		["email_worker_3b", "factory_foreman", Bribery.RANK_NONE,
				"a chief of another chain is not the player's superior"],
		["junior_sales", "b10_director", Bribery.RANK_NPC_SUPERIOR,
				"superior_by_room: wing 4A answers to the B10 director (−0.10)"],
		["b10_director", "junior_sales", Bribery.RANK_PLAYER_SUPERIOR,
				"a B10 director player is the junior sales' direct superior (+0.10)"],
	]
	for row: Array in rows:
		check_eq(Bribery.rank_relation_between(Database.get_occupation(row[0]),
				Database.get_occupation(row[1])), row[2], row[3])
	check_eq(Bribery.rank_relation_between(Database.get_occupation("email_worker_3b"), null),
			Bribery.RANK_NONE, "no seat (role NPC) → no rank modifier")


func _check_insulting_offer() -> void:
	var npc: NPCRuntime = Fixtures.synthetic("test_insulted", "bribable",
			{"greed": 80, "loyalty": 20, "courage": 40})
	var fair: int = Bribery.fair_price(npc, "look_away_once", NEUTRAL)
	var low: int = floori(fair * 0.4)
	var raw: float = _expected_p(npc.traits, Bribery.offer_ratio(low, fair), {})
	check(Bribery.is_insulting(low, fair), "an offer below 50% of the fair price is insulting")
	check(not Bribery.is_insulting(ceili(fair * 0.5), fair), "exactly 50% is not insulting")
	check_near(Bribery.acceptance_probability(npc, low, "look_away_once", NEUTRAL),
			raw * M_INSULT_FACTOR, EPS, "insulting offer → P reduced to a third")
	var result: Dictionary = Bribery.offer(npc, low, "look_away_once", "in_person",
			_ctx({"wallet": Fixtures.FakeWallet.new(RICH), "roll": 0.99}))
	var insult: Dictionary = Fixtures.find_belief(result, npc.id, Bribery.FACT_INSULTED)
	check(not insult.is_empty() and Bribery.EFFECT_INSULTED in result["effects"],
			"insulting offer raises suspicion (a belief) even without a report")
	check_near(float(insult.get("certainty", 0.0)),
			Database.get_balance_float("sobornos.certeza_oferta_insultante"), EPS,
			"the insult belief has the balance certainty")
	check_eq([result["text_key"], result["insult_text_key"]],
			[Bribery.TEXT_INSULTED, Bribery.TEXT_INSULTED], "the UI is told the amount offends")


func _check_ledger() -> void:
	var npc: NPCRuntime = Fixtures.synthetic("test_ledger", "burnout")
	var ctx: Dictionary = {"difficulty_modifier": 1.0, "suspicion": 0.0}
	var base: int = Bribery.fair_price(npc, "lend_access", ctx)
	check_eq(base, Bribery.base_price(Bribery.npc_daily_wage(npc), "lend_access"),
			"empty ledger → no price modifier")
	var per_severity: float = Database.get_balance_float("registro.precio_por_gravedad_agravio")
	var per_magnitude: float = Database.get_balance_float("registro.precio_por_magnitud_favor")
	npc.ledger["grievances"].append({"type": "idea_stolen", "severity": 4, "day": 1})
	check_eq(Bribery.fair_price(npc, "lend_access", ctx), roundi(base * (1.0 + 4 * per_severity)),
			"grievances make the bribe more expensive (registro.precio_por_gravedad_agravio)")
	npc.ledger = NPCRuntime.new_ledger()
	npc.ledger["favours"].append({"type": "cover_up", "magnitude": 5, "day": 1})
	check_eq(Bribery.fair_price(npc, "lend_access", ctx), roundi(base * (1.0 - 5 * per_magnitude)),
			"favours make the bribe cheaper (registro.precio_por_magnitud_favor)")
	npc.ledger = NPCRuntime.new_ledger()
	npc.ledger["affection"] = 40
	npc.ledger["debt"] = 20
	var inputs: Dictionary = Bribery.gather_inputs(npc, {"reputation": 0.0, "suspicion": 0.0,
			"rank_relation": 0})
	check_eq([inputs["affection"], inputs["debt"]], [40, 20],
			"affection and debt are read from the NPC's ledger")
	_check_live_ledger()


## El registro real de NPCDirector mueve el precio, con los mismos ajustes que el de reserva.
func _check_live_ledger() -> void:
	var frank: NPCRuntime = NPCDirector.get_npc("npc_frank_rudd")
	var ctx: Dictionary = {"suspicion": 0.0}
	var before: int = Bribery.fair_price(frank, "lend_access", ctx)
	NPCDirector.add_grievance(frank.id, "idea_stolen", 5)
	var after: int = Bribery.fair_price(frank, "lend_access", ctx)
	check(after > before, "NPCDirector grievance raises Frank Rudd's price (%d > %d)"
			% [after, before])
	check_near(Bribery.ledger_modifier_from(frank.ledger),
			NPCDirector.get_bribe_price_modifier(frank.id), EPS,
			"the fallback ledger modifier uses NPCDirector's registro.* tunables")
	NPCDirector.add_favour(frank.id, "cover_up", 10)
	check(Bribery.fair_price(frank, "lend_access", ctx) < after,
			"NPCDirector favour lowers it again")
	check_eq(Bribery.fair_price(frank, "lend_access", ctx),
			NPCDirector.get_fair_bribe_price(frank.id, "lend_access"),
			"same price as NPCDirector after ledger changes")


func _check_rejection_table() -> void:
	var fair: int = 1000
	var rows: Array = [
		[{"courage": 61, "loyalty": 10, "greed": 90}, fair, Bribery.OUTCOME_DENOUNCED],
		[{"courage": 20, "loyalty": 71, "greed": 90}, fair, Bribery.OUTCOME_DENOUNCED],
		[{"courage": 60, "loyalty": 70, "greed": 50}, fair, Bribery.OUTCOME_NEUTRAL],
		[{"courage": 29, "loyalty": 50, "greed": 90}, fair, Bribery.OUTCOME_SILENCE],
		[{"courage": 45, "loyalty": 50, "greed": 71}, 700, Bribery.OUTCOME_COUNTEROFFER],
		[{"courage": 45, "loyalty": 50, "greed": 71}, 699, Bribery.OUTCOME_NEUTRAL],
		[{"courage": 45, "loyalty": 50, "greed": 70}, fair, Bribery.OUTCOME_NEUTRAL],
	]
	for row: Array in rows:
		check_eq(Bribery.rejection_outcome(row[0], row[1], fair), row[2],
				"rejection table: %s, offer %d → %s" % [str(row[0]), row[1], row[2]])
	check_eq(Bribery.counteroffer_price(fair, 0.0), 1300, "counteroffer asks at least 1.3 × fair")
	check_eq(Bribery.counteroffer_price(fair, 1.0), 1800, "counteroffer asks at most 1.8 × fair")
	check_eq(Bribery.counteroffer_price(fair, 0.5), 1550, "counteroffer interpolates 1.3–1.8")


func _check_offer_outcomes() -> void:
	var wallet: Fixtures.FakeWallet = Fixtures.FakeWallet.new(1000)
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	_log.clear()
	var ok: Dictionary = Bribery.offer(frank, 448, "lend_access", "in_person",
			_ctx({"wallet": wallet, "roll": 0.0}))
	check(bool(ok["accepted"]) and ok["outcome"] == Bribery.OUTCOME_ACCEPTED, "Frank accepts 448")
	check_eq(wallet.money, 552, "the accepted amount is paid (1000 − 448)")
	check_eq(_log.last("bribe_offered"), [frank.id, 448, "lend_access"], "bribe_offered emitted")
	check_eq(_log.last("bribe_result"), [frank.id, true, Bribery.OUTCOME_ACCEPTED],
			"bribe_result(accepted) emitted")
	var crime: Array = _log.last("crime_committed")
	check(not crime.is_empty() and crime[0] == "bribe" and crime[2]["paid"] == 448,
			"crime_committed('bribe') carries the amount paid (Tracking: gold)")
	check_eq(_log.count("game_over"), 0, "an accepted bribe is not a game over")
	_check_silence_branch(frank, wallet)
	_check_neutral_branch()
	_check_denounce_branch(wallet)
	var poor: Dictionary = Bribery.offer(frank, 448, "lend_access", "in_person",
			_ctx({"wallet": Fixtures.FakeWallet.new(100), "roll": 0.0}))
	check(not bool(poor["ok"]) and poor["outcome"] == Bribery.OUTCOME_NO_FUNDS,
			"an offer the player cannot pay is refused before anything happens")
	check_eq(Bribery.offer(frank, 0, "lend_access", "in_person", _ctx({}))["outcome"],
			Bribery.OUTCOME_INVALID, "a zero offer is invalid")


func _check_silence_branch(frank: NPCRuntime, wallet: Fixtures.FakeWallet) -> void:
	var money: int = wallet.money
	var result: Dictionary = Bribery.offer(frank, 448, "lend_access", "in_person",
			_ctx({"wallet": wallet, "roll": 0.99, "day": 3}))
	check_eq(result["outcome"], Bribery.OUTCOME_SILENCE,
			"Frank (courage 22) refusing → silence with memory")
	var memory: Dictionary = Fixtures.find_belief(result, frank.id, Bribery.FACT_REMEMBERED)
	check_near(float(memory.get("certainty", 0.0)), 0.9, EPS, "silence with memory: belief 0.9")
	var material: Dictionary = Fixtures.material_of_kind(frank, Blackmail.KIND_SILENCE_MEMORY)
	check(not material.is_empty() and bool(material["will_demand"]),
			"silence with memory: Frank now holds blackmail material and will use it")
	check_eq(wallet.money, money, "a refused bribe costs nothing")


func _check_neutral_branch() -> void:
	var npc: NPCRuntime = Fixtures.synthetic("test_neutral", "gossip",
			{"greed": 50, "loyalty": 50, "courage": 45})
	var result: Dictionary = Bribery.offer(npc, 600, "silence_witnessed", "in_person",
			_ctx({"wallet": Fixtures.FakeWallet.new(RICH), "roll": 0.99}))
	check_eq(result["outcome"], Bribery.OUTCOME_NEUTRAL, "mid traits refusing → neutral refusal")
	var belief: Dictionary = Fixtures.find_belief(result, npc.id, Bribery.FACT_REFUSED)
	check_near(float(belief.get("certainty", 0.0)),
			Database.get_balance_float("sobornos.certeza_rechazo_neutro"), EPS,
			"neutral refusal raises suspicion (belief) without a report")
	check_eq(_log.last("bribe_result"), [npc.id, false, Bribery.OUTCOME_NEUTRAL],
			"bribe_result(neutral_refusal) emitted")


func _check_denounce_branch(wallet: Fixtures.FakeWallet) -> void:
	var george: NPCRuntime = Fixtures.named("npc_george_penn")
	var money: int = wallet.money
	_log.clear()
	var result: Dictionary = Bribery.offer(george, 90, "look_away_once", "in_person",
			_ctx({"wallet": wallet, "roll": 0.99}))
	check_eq(result["outcome"], Bribery.OUTCOME_DENOUNCED, "George Penn (loyalty 88) denounces")
	check_eq(_log.count("game_over"), 1, "denounce → exactly one game_over")
	check_eq(_log.last("game_over").slice(0, 2), ["bribe_denounced", "the_file"],
			"game_over cause comes from endings.json causes")
	check_eq(wallet.money, money, "the denounced envelope is not paid")


## §8.2 «la negociación tiene coste»: contraoferta con ficha, rondas limitadas, sin nueva tirada.
func _check_counteroffer_negotiation() -> void:
	var tom: NPCRuntime = Fixtures.named("npc_tom_iverson")
	var wallet: Fixtures.FakeWallet = Fixtures.FakeWallet.new(1000)
	var ctx: Dictionary = _ctx({"wallet": wallet, "roll": 0.99, "counter_roll": 0.0})
	var first: Dictionary = Bribery.offer(tom, 210, "look_away_once", "in_person", ctx)
	check_eq(first["outcome"], Bribery.OUTCOME_COUNTEROFFER,
			"Tom Iverson (greed 92) answers a fair offer with a counteroffer")
	check_eq(first["asked_price"], 273, "he asks 1.3 × 210 = 273")
	check_eq([first["counteroffer"]["npc_id"], first["counteroffer"]["favour"],
			first["counteroffer"]["asked_price"], first["counteroffer"]["rounds"]],
			[tom.id, "look_away_once", 273, 1], "the counteroffer comes as a token")
	var cost: Dictionary = Fixtures.find_belief(first, tom.id, Bribery.FACT_COUNTERED)
	check(not cost.is_empty(), "haggling has a cost: a bribe_attempt:countered belief")
	var certainty_1: float = BeliefNet.get_belief(str(cost.get("id", ""))).certainty
	ctx.erase("roll")
	ctx[Bribery.CTX_COUNTEROFFER] = first["counteroffer"]
	var lowball: Dictionary = Bribery.offer(tom, 250, "look_away_once", "in_person", ctx)
	check_eq([lowball["outcome"], lowball["asked_price"], lowball["counteroffer"]["rounds"]],
			[Bribery.OUTCOME_COUNTEROFFER, 273, 2],
			"a lower offer does not re-enter the formula: he repeats 273 (round 2)")
	check(BeliefNet.get_belief(str(cost["id"])).certainty > certainty_1,
			"each round reinforces the haggling belief")
	ctx[Bribery.CTX_COUNTEROFFER] = lowball["counteroffer"]
	var fed_up: Dictionary = Bribery.offer(tom, 260, "look_away_once", "in_person", ctx)
	check_eq(fed_up["outcome"], Bribery.OUTCOME_NEUTRAL,
			"past sobornos.max_contraofertas rounds he refuses (neutral)")
	ctx[Bribery.CTX_COUNTEROFFER] = first["counteroffer"]
	var retry: Dictionary = Bribery.offer(tom, 273, "look_away_once", "in_person", ctx)
	check(bool(retry["accepted"]) and retry["probability"] == 1.0,
			"paying the asked price with a standing token is accepted")
	check_eq(wallet.money, 1000 - 273, "the asked price is paid")


## Regresión: la ficha no salta la excepción absoluta ni sirve para otro favor, personaje o día.
func _check_counteroffer_tokens() -> void:
	var rose: NPCRuntime = Fixtures.named("npc_rose_miller")
	var fair: int = Bribery.fair_price(rose, "bury_investigation", _ctx({}))
	var forged: Dictionary = Bribery.make_counteroffer(rose.id, "bury_investigation", 1, 1,
			GameClock.get_day())
	var ctx: Dictionary = _ctx({"roll": 0.0, Bribery.CTX_COUNTEROFFER: forged})
	check(not bool(Bribery.evaluate(rose, 5, "bury_investigation", ctx)["accepted"]),
			"Rose Miller + asked_price 1: the forged token is ignored (P = 0)")
	ctx[Bribery.CTX_COUNTEROFFER] = Bribery.make_counteroffer(rose.id, "bury_investigation",
			fair * 2, 1, GameClock.get_day())
	check(not bool(Bribery.evaluate(rose, fair * 2, "bury_investigation", ctx)["accepted"]),
			"even a well-formed token cannot buy an unbribable NPC")
	var tom: NPCRuntime = Fixtures.named("npc_tom_iverson")
	var stale: Dictionary = Bribery.make_counteroffer(tom.id, "look_away_once", 273, 1,
			GameClock.get_day())
	var roll_high: Dictionary = _ctx({"roll": 0.99, Bribery.CTX_COUNTEROFFER: stale})
	check(not bool(Bribery.evaluate(tom, 273, "bury_investigation", roll_high)["accepted"]),
			"Tom's 273 for look_away_once cannot be replayed for bury_investigation")
	var george: NPCRuntime = Fixtures.named("npc_george_penn")
	check(not bool(Bribery.evaluate(george, 273, "look_away_once", roll_high)["accepted"]),
			"a token for another NPC is ignored")
	roll_high["day"] = GameClock.get_day() + 1
	check(not bool(Bribery.evaluate(tom, 273, "look_away_once", roll_high)["accepted"]),
			"a token from an earlier day has expired")
	roll_high.erase("day")
	check(bool(Bribery.evaluate(tom, 273, "look_away_once", roll_high)["accepted"]),
			"the genuine token still works the same day")


## Una tirada por personaje, favor y jornada: subir la oferta 1 € o esperar no vuelve a tirar.
func _check_no_reroll() -> void:
	var tom: NPCRuntime = Fixtures.named("npc_tom_iverson")
	var ctx: Dictionary = _ctx({})
	var rolls: Dictionary = {}
	for amount: int in [150, 151, 152, 400]:
		rolls[Bribery.evaluate(tom, amount, "lend_access", ctx)["roll"]] = true
	GameClock.advance_minutes(90.0)
	rolls[Bribery.evaluate(tom, 153, "lend_access", ctx)["roll"]] = true
	check_eq(rolls.size(), 1, "same roll whatever the amount or the hour")
	check(Bribery.evaluate(tom, 150, "look_away_once", ctx)["roll"] != rolls.keys()[0],
			"another favour is another roll")


func _check_channels() -> void:
	var frank: NPCRuntime = Fixtures.named("npc_frank_rudd")
	var ctx: Dictionary = _ctx({"wallet": Fixtures.FakeWallet.new(RICH), "roll": 0.0})
	var chat: Dictionary = Bribery.offer(frank, 448, "lend_access", "mobile_chat", ctx)
	var record: Belief = BeliefNet.get_belief(str(chat["record_id"]))
	check(Bribery.EFFECT_DIGITAL_RECORD in chat["effects"] and record != null
			and record.is_record and record.subject == "player" and record.fact == "chat_log",
			"mobile chat leaves a permanent chat_log record about the player")
	check(record != null and is_equal_approx(record.weight,
			Database.get_balance_float("creencias.peso_tipo.chat_log")),
			"the chat record weighs creencias.peso_tipo.chat_log")
	check(BeliefNet.get_records_about("player").any(
			func(b: Belief) -> bool: return b.id == str(chat["record_id"])),
			"BeliefNet lists the chat record among the records about the player")
	_check_phone_channel(frank, ctx)
	_check_in_person_channel(frank, ctx)
	_check_immediate_channel(frank)


func _check_phone_channel(frank: NPCRuntime, ctx: Dictionary) -> void:
	ctx["listeners"] = ["npc_debbie_foyle", frank.id]
	var phone: Dictionary = Bribery.offer(frank, 448, "lend_access", "phone_call", ctx)
	check(Bribery.EFFECT_OVERHEARD in phone["effects"] and _holds(
			"npc_debbie_foyle", Bribery.FACT_OVERHEARD),
			"phone call without privacy: Debbie Foyle now believes she overheard a bribe")
	check(Fixtures.find_belief(phone, frank.id, Bribery.FACT_OVERHEARD).is_empty(),
			"the bribed NPC is not his own eavesdropper")
	check(phone["record_id"] == "", "a phone call leaves no written record")
	ctx.erase("listeners")
	var quiet: Dictionary = Bribery.offer(frank, 448, "lend_access", "phone_call", ctx)
	check(quiet["beliefs"].is_empty() and quiet["record_id"] == "",
			"private phone call: no record, no listeners")


func _check_in_person_channel(frank: NPCRuntime, ctx: Dictionary) -> void:
	ctx.merge({"witnesses": ["npc_nate_brackley"], "cameras": ["wing_3b_cam_0"]}, true)
	var met: Dictionary = Bribery.offer(frank, 448, "lend_access", "in_person", ctx)
	check(Bribery.EFFECT_WITNESSED in met["effects"] and _holds("npc_nate_brackley",
			Bribery.FACT_WITNESSED), "in person: the witness believes what he saw")
	check(Bribery.EFFECT_CAMERA in met["effects"] and Security.get_footage_list().any(
			func(f: Dictionary) -> bool: return f.values().has(str(met["footage_id"]))),
			"in person under a camera: Security holds the footage")
	check(met["record_id"] == "", "in person leaves no digital record")


func _check_immediate_channel(frank: NPCRuntime) -> void:
	var spot: Dictionary = Bribery.offer(frank, 1120, "look_away_once", "immediate",
			_ctx({"wallet": Fixtures.FakeWallet.new(RICH), "roll": 0.0,
			"witnesses": ["npc_lorna_vickers"]}))
	check_eq([spot["favour"], spot["fair_price"]], ["silence_witnessed", 1120],
			"immediate channel forces silence_witnessed ×20 (56 × 20 = 1120)")
	check(not Fixtures.material_of_kind(frank, Blackmail.KIND_BRIBED_SILENCE).is_empty(),
			"bought silence gives the NPC blackmail material")
	check(_holds("npc_lorna_vickers", Bribery.FACT_WITNESSED),
			"the other witnesses of the flagrancy see the envelope change hands")


func _holds(holder: String, fact: String) -> bool:
	return BeliefNet.get_beliefs_held_by(holder).any(
			func(b: Belief) -> bool: return b.fact == fact and b.subject == "player")
