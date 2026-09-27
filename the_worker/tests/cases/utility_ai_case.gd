# utility_ai_case.gd — Cuerpo de test_utility_ai: fórmula de §7.5, trato por rango emergente, disparo por eventos.
# PROPIETARIO DE: nada.
# ESCUCHA: npc_decided, npc_reported_player (conexiones temporales del escenario).
extends TestCase

const GEORGE := "npc_george_penn"
const LUDMILA := "npc_ludmila_petrova"
const TOM := "npc_tom_iverson"
const AMELIA := "npc_amelia_cole"
const ALVIN := "npc_alvin_pyne"
const SONIA := "npc_sonia_vail"
const PEARL := "npc_pearl_osgood"
const LOW_RANK := 1
const HIGH_RANK := 28
const DIRECT := 0.9
const PARTIAL := 0.35
const WEIGHT_KEYS: Array[String] = [
	"rasgos", "creencia", "animo", "relacion", "rango", "sospecha", "reputacion", "sesgo",
]
## Reacción documentada en §12.2 / archetypes.json caught_reaction → acción esperada del repertorio.
const REACTION_TO_ACTION: Dictionary = {
	"report_to_security": "report_to_security", "report_to_superior": "report_to_superior",
	"spread_at_lunch": "gossip", "silent_blackmail": "stay_silent",
	"remembers_quietly": "stay_silent", "use_as_leverage": "stay_silent",
	"ask_for_money": "stay_silent", "indifferent": "work",
}
## Rejilla en la que el cambio de rango debe invertir la conducta: sospecha y reputación 0-100
## (también sospecha > reputación) y creencias previas del mismo testigo sobre el jugador.
const METER_STEPS: Array[float] = [0.0, 25.0, 50.0, 75.0, 100.0]
const PRIOR_BELIEFS: Array = [[], [0.2], [0.9], [0.9, 0.9]]
## Variantes ±15 por arquetipo y cuota mínima de su reacción documentada (§8.1: el jugador no
## puede memorizar tablas, pero el arquetipo debe reconocerse).
const VARIANTS := 200
const VARIANT_SEED := 20240927
const MIN_REACTION_SHARE := 0.6

var _decided: Array = []
var _reported: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	EventBus.npc_decided.connect(_on_decided)
	EventBus.npc_reported_player.connect(_on_reported)
	_check_repertoire()
	_check_rank_flip()
	_check_rank_monotonic()
	_check_archetype_reactions()
	_check_variant_reactions()
	_check_named_reactions()
	_check_event_trigger()
	_check_partial_witness()
	_check_superior_report()
	_check_silence_and_positive_facts()
	_check_positive_beliefs_do_not_count()
	_check_cooldown_counts_other_reports()
	_check_debt_suppression()
	_check_bribe_inclination()
	_check_reinforcement_escalation()


func _check_repertoire() -> void:
	var weights: Dictionary = Database.get_balance("utilidad")
	var complete: bool = true
	for action: String in UtilityAI.ACTIONS:
		for key: String in WEIGHT_KEYS:
			complete = complete and weights.has(action) and (weights[action] as Dictionary).has(key)
	check(complete, "every action has all formula weights in balance.json → utilidad")
	for action: String in UtilityAI.BASE_ACTIONS:
		check(UtilityAI.ACTIONS.has(action), "§7.5 action %s is in the repertoire" % action)
	check_eq(UtilityAI.BASE_ACTIONS.size(), 11, "the §7.5 base repertoire has eleven actions")
	for action: String in UtilityAI.ACTIONS:
		var key: String = UtilityAI.action_name_key(action)
		check(tr(key) != key, "action %s has a visible name (%s)" % [action, key])


## §21 test_utility_ai: George (snitch), la MISMA creencia; solo cambia el rango del jugador. Debe
## valer en toda la rejilla de sospecha/reputación y con creencias previas, con margen.
func _check_rank_flip() -> void:
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	var wrong: Array = []
	var margin: float = INF
	for suspicion: float in METER_STEPS:
		for reputation: float in METER_STEPS:
			for prior: Array in PRIOR_BELIEFS:
				var meters: Array = [suspicion, reputation, prior]
				var low: Dictionary = UtilityAI.evaluate(george, _context(GEORGE, LOW_RANK, meters))
				var high: Dictionary = UtilityAI.evaluate(george, _context(GEORGE, HIGH_RANK, meters))
				if low["action"] != "report_to_security" or high["action"] != "stay_silent":
					wrong.append(meters)
				margin = minf(margin, minf(_margin(low), _margin(high)))
	check(wrong.is_empty(), "rank 1 → George reports; rank 28 → he keeps quiet, for every "
			+ "suspicion/reputation 0-100 and prior belief (failures: %s)" % str(wrong))
	check(margin >= 0.2, "…with a clear utility margin (min %.3f)" % margin)
	_check_only_rank_differs(george)


## Diferencia entre la acción elegida y la segunda mejor.
func _margin(result: Dictionary) -> float:
	var best: float = float(result["score"])
	var second: float = -INF
	for action: String in result["scores"]:
		if action != result["action"]:
			second = maxf(second, float(result["scores"][action]))
	return best - second


## La diferencia entre ambos casos es exactamente peso_rango × Δrango/33: nada más cambia.
func _check_only_rank_differs(george: NPCRuntime) -> void:
	var low: Dictionary = _context(GEORGE, LOW_RANK, [0.0, 0.0, []])
	var high: Dictionary = _context(GEORGE, HIGH_RANK, [0.0, 0.0, []])
	for action: String in ["report_to_security", "stay_silent"]:
		var a: Dictionary = UtilityAI.breakdown(action, george, low)
		var b: Dictionary = UtilityAI.breakdown(action, george, high)
		for term: String in a:
			if term != "rango" and term != "total":
				check_near(float(a[term]), float(b[term]), 1e-9, "%s: term %s ignores rank" % [action, term])
		var w: float = float(Database.get_balance("utilidad.%s.rango" % action))
		check_near(float(b["rango"]) - float(a["rango"]), w * (HIGH_RANK - LOW_RANK) / 33.0, 1e-9,
				"%s: rank term = weight × Δrank / 33" % action)


func _check_rank_monotonic() -> void:
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	var previous_report: float = INF
	var previous_silence: float = -INF
	var monotonic: bool = true
	for rank: int in range(0, 34):
		var ctx: Dictionary = _context(GEORGE, rank, [0.0, 0.0, []])
		var report: float = UtilityAI.score_action("report_to_security", george, ctx)
		var silence: float = UtilityAI.score_action("stay_silent", george, ctx)
		monotonic = monotonic and report < previous_report and silence > previous_silence
		previous_report = report
		previous_silence = silence
	check(monotonic, "reporting falls and silence rises strictly with the player's rank")


## §12.2: con un jugador de rango bajo cada arquetipo base elige su reacción documentada.
func _check_archetype_reactions() -> void:
	for archetype: ArchetypeData in Database.get_all_archetypes():
		var npc: NPCRuntime = _probe(archetype, archetype.traits)
		var expected: String = str(REACTION_TO_ACTION.get(archetype.caught_reaction, ""))
		check_eq(UtilityAI.evaluate(npc, _probe_context())["action"], expected,
				"%s reacts with %s (§12.2 %s)" % [archetype.id, expected, archetype.caught_reaction])


## Con la variación ±15 de §8.1 la reacción documentada sigue siendo la más frecuente de cada
## arquetipo y la elige al menos MIN_REACTION_SHARE de sus variantes.
func _check_variant_reactions() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = VARIANT_SEED
	var variation: int = Database.get_archetype_variation_range()
	for archetype: ArchetypeData in Database.get_all_archetypes():
		var counts: Dictionary = {}
		for i: int in VARIANTS:
			var traits: Dictionary = {}
			for trait_name: Variant in archetype.traits:
				traits[trait_name] = clampi(int(archetype.traits[trait_name])
						+ rng.randi_range(-variation, variation), 0, 100)
			var action: String = str(UtilityAI.evaluate(_probe(archetype, traits),
					_probe_context())["action"])
			counts[action] = int(counts.get(action, 0)) + 1
		var expected: String = str(REACTION_TO_ACTION.get(archetype.caught_reaction, ""))
		var share: float = float(counts.get(expected, 0)) / VARIANTS
		var top: int = counts.values().max()
		check(share >= MIN_REACTION_SHARE and int(counts.get(expected, 0)) == top,
				"±%d variants of %s mostly react with %s (%.0f%% %s)"
				% [variation, archetype.id, expected, share * 100.0, str(counts)])


## Los 23 nominados (rasgos exactos de §24.2) reaccionan como su arquetipo documentado.
func _check_named_reactions() -> void:
	var wrong: Array = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.is_named:
			continue
		var archetype: ArchetypeData = Database.get_archetype(npc.archetype)
		var expected: String = str(REACTION_TO_ACTION.get(archetype.caught_reaction, ""))
		var ctx: Dictionary = NPCDirector.build_context(npc.id, NPCDirector.TRIGGER_BELIEF, {
			"certainty": DIRECT, "player_rank": LOW_RANK, "player_suspicion": 0.0,
			"player_reputation": 0.0, "belief_certainties": [DIRECT]})
		var action: String = str(UtilityAI.evaluate(npc, ctx)["action"])
		if action != expected:
			wrong.append("%s: %s ≠ %s" % [npc.id, action, expected])
	check(wrong.is_empty(), "every named NPC reacts like its archetype (Pearl tells her superior, "
			+ "Claudia and Ray keep it as leverage) %s" % str(wrong))


func _probe(archetype: ArchetypeData, traits: Dictionary) -> NPCRuntime:
	var npc: NPCRuntime = NPCRuntime.new()
	npc.id = "probe_" + archetype.id
	npc.archetype = archetype.id
	npc.traits = traits.duplicate()
	return npc


func _probe_context() -> Dictionary:
	return {"actions": UtilityAI.REACTION_ACTIONS, "belief_certainties": [DIRECT],
			"player_rank": LOW_RANK, "player_suspicion": 0.0, "player_reputation": 0.0}


## §7.5 «certeza_creencia_RELEVANTE»: una creencia positiva no suma al término de creencias; una
## negativa, sí.
func _check_positive_beliefs_do_not_count() -> void:
	var george: NPCRuntime = NPCDirector.get_npc(GEORGE)
	var before: float = _report_score(george)
	BeliefNet.create_belief(GEORGE, "player", "hard_worker", DIRECT, "direct", "wing_3b")
	check_near(_report_score(george), before, 1e-9,
			"a 'hard worker' belief does not change George's utility of reporting")
	var fact: String = "seen_partially:theft_small"
	BeliefNet.create_belief(GEORGE, "player", fact, PARTIAL, "direct", "wing_3b")
	var certainty: float = 0.0
	for belief: Belief in BeliefNet.get_beliefs_held_by(GEORGE):
		certainty += belief.certainty if belief.fact == fact else 0.0
	check(certainty > 0.0 and is_equal_approx(_report_score(george) - before,
			float(Database.get_balance("utilidad.report_to_security.creencia")) * certainty),
			"a negative belief adds weight × its certainty (%.2f) to it" % certainty)


## Medidores fijos: la creencia nueva también sube la sospecha real, que aquí no se mide.
func _report_score(george: NPCRuntime) -> float:
	var ctx: Dictionary = NPCDirector.build_context(GEORGE, NPCDirector.TRIGGER_BELIEF,
			{"certainty": DIRECT, "player_suspicion": 0.0, "player_reputation": 0.0})
	return UtilityAI.score_action("report_to_security", george, ctx)


## Disparo por eventos: belief_created → npc_decided + npc_reported_player (testigo directo 4,0).
func _check_event_trigger() -> void:
	if not check(PlayerState.get_rank() <= 10, "a fresh run starts with a low-rank player"):
		return
	_clear()
	var state_before: String = NPCDirector.get_npc(GEORGE).state
	EventBus.belief_created.emit("test_belief_direct", GEORGE, "player", DIRECT)
	check(_decided_action(GEORGE) == "report_to_security", "belief_created makes George decide")
	check_eq(NPCDirector.get_last_decision(GEORGE).get("action", ""), "report_to_security",
			"get_last_decision records it")
	check_eq(NPCDirector.get_npc(GEORGE).state, state_before,
			"a decision does not overwrite the routine state (%s)" % state_before)
	check_eq(_reported.size(), 1, "exactly one report reaches Security (no echo loop)")
	if _reported.size() == 1:
		check_eq(_reported[0].slice(0, 3), [GEORGE, "direct_witness",
				Database.get_balance_float("investigaciones.pesos_evidencia.testigo_directo")],
				"certainty ≥ 0.9 → direct witness weight 4.0")
	_clear()
	EventBus.belief_created.emit("test_belief_again", GEORGE, "player", DIRECT)
	check(_reported.is_empty(), "the same NPC does not report twice on the same day")
	_clear()
	EventBus.belief_created.emit("test_belief_other", GEORGE, "npc_nate_brackley", DIRECT)
	check(_decided.is_empty(), "beliefs about other subjects do not trigger evaluation")


func _check_partial_witness() -> void:
	_clear()
	EventBus.belief_created.emit("test_belief_partial", LUDMILA, "player", PARTIAL)
	check_eq(_decided_action(LUDMILA), "report_to_security", "Ludmila reports a partial sighting")
	if check_eq(_reported.size(), 1, "one partial report"):
		check_eq(_reported[0].slice(0, 3), [LUDMILA, "partial_witness",
				Database.get_balance_float("investigaciones.pesos_evidencia.testigo_parcial")],
				"certainty < 0.9 → partial witness weight 0.8")


## El rookie informa a su superior directo (§12.2 company_man: +10 y anotación): el canal viaja
## en la señal ("superior") para que BeliefNet anote el expediente y Security lo pondere.
func _check_superior_report() -> void:
	_clear()
	var factor: float = Database.get_balance_float("npc.factor_denuncia_superior")
	EventBus.belief_created.emit("test_belief_rookie", SONIA, "player", DIRECT)
	check_eq(_decided_action(SONIA), "report_to_superior", "rookie Sonia tells her superior")
	if check_eq(_reported.size(), 1, "one report through the hierarchy"):
		check_eq(_reported[0].slice(0, 2), [SONIA, "superior"], "report_type is the channel 'superior'")
		check_near(float(_reported[0][2]),
				Database.get_balance_float("investigaciones.pesos_evidencia.testigo_directo")
				* factor, 1e-6, "…weighing half a Security report")
		check_eq(BeliefNet.get_report_points("superior", float(_reported[0][2])), 10.0,
				"BeliefNet reads it as the §12.2 superior report (+10)")
	check_eq(str(_decided[0][2].get("channel", "")) if not _decided.is_empty() else "",
			"superior", "npc_decided carries the channel")
	check_eq(str(_decided[0][2].get("evidence_type", "")) if not _decided.is_empty() else "",
			"direct_witness", "…and the evidence type")
	_clear()
	EventBus.belief_created.emit("test_belief_pearl", PEARL, "player", PARTIAL)
	check_eq(_decided_action(PEARL), "report_to_superior", "company man Pearl tells her superior")
	if check_eq(_reported.size(), 1, "one partial report through the hierarchy"):
		check_eq(_reported[0].slice(0, 3), [PEARL, "partial_witness",
				Database.get_balance_float("investigaciones.pesos_evidencia.testigo_parcial")
				* factor], "a partial sighting told to the superior: partial piece × factor")


## El cobarde calla por temor y guarda material (§12.2); los hechos positivos no disparan nada.
func _check_silence_and_positive_facts() -> void:
	_clear()
	EventBus.belief_created.emit("test_belief_coward", ALVIN, "player", DIRECT)
	check_eq(_decided_action(ALVIN), "stay_silent", "coward Alvin keeps quiet")
	check(_reported.is_empty(), "silence means no report")
	var material: Array[Dictionary] = Blackmail.get_material(NPCDirector.get_npc(ALVIN))
	check(material.size() == 1 and material[0]["kind"] == Blackmail.KIND_SILENCE_MEMORY,
			"silence with memory becomes blackmail material")
	_clear()
	BeliefNet.create_belief(GEORGE, "player", "hard_worker", DIRECT, "direct", "wing_3b")
	check(_decided.is_empty(), "positive facts (hard worker) never trigger a report decision")


## Una denuncia por jornada cuente quien cuente la denuncia (CaughtHandler, Blackmail...); callar
## porque ya denunció no es «silencio con memoria».
func _check_cooldown_counts_other_reports() -> void:
	EventBus.npc_reported_player.emit(AMELIA, "security", 20.0, "wing_3b")
	_clear()
	EventBus.belief_created.emit("test_belief_amelia", AMELIA, "player", DIRECT)
	check(not _decided_action(AMELIA).is_empty() and _reported.is_empty(),
			"Amelia already reported today (through CaughtHandler): no second report")
	check(Blackmail.get_material(NPCDirector.get_npc(AMELIA)).is_empty(),
			"a silence forced by the cooldown keeps no blackmail material")


## §7.7: la deuda suprime la denuncia temporalmente; cada silencio consume deuda.
func _check_debt_suppression() -> void:
	new_run()
	EventBus.bribe_result.emit(GEORGE, true, "accepted")
	var debt: int = NPCDirector.get_debt(GEORGE)
	check_eq(debt, Database.get_balance_int("registro.deuda_por_soborno_aceptado"),
			"an accepted bribe leaves George in debt with the player")
	var consumed: int = Database.get_balance_int("registro.deuda_consumida_por_silencio")
	var silences: int = 0
	_clear()
	for i: int in ceili(float(debt) / consumed):
		EventBus.belief_created.emit("test_debt_%d" % i, GEORGE, "player", DIRECT)
		silences += 1 if _reported.is_empty() else 0
	check_eq(silences, ceili(float(debt) / consumed), "while in debt George never reports")
	check_eq(NPCDirector.get_debt(GEORGE), 0, "each suppressed report consumed debt")
	EventBus.belief_created.emit("test_debt_paid", GEORGE, "player", DIRECT)
	check_eq(_reported.size(), 1, "once the debt is spent, George reports again")


func _check_bribe_inclination() -> void:
	_clear()
	var favour: String = "look_away_once"
	EventBus.bribe_offered.emit(TOM, NPCDirector.get_fair_bribe_price(TOM, favour) * 2, favour)
	check_eq(_decided_action(TOM), "accept_bribe", "bribable Tom leans to accept a fair offer")
	EventBus.bribe_offered.emit(AMELIA, NPCDirector.get_fair_bribe_price(AMELIA, favour) * 2, favour)
	check_eq(_decided_action(AMELIA), "refuse_bribe", "incorruptible Amelia leans to refuse")
	var advisory: bool = _decided.size() == 2 and bool(_decided[0][2].get("advisory", false))
	check(advisory, "bribe decisions are advisory (Bribery resolves §8.2)")


## meters = [sospecha, reputación, creencias previas del testigo]; la disparadora es DIRECT.
func _context(npc_id: String, rank: int, meters: Array) -> Dictionary:
	var beliefs: Array = [DIRECT]
	beliefs.append_array(meters[2])
	return NPCDirector.build_context(npc_id, NPCDirector.TRIGGER_BELIEF, {
		"belief_id": "test_belief", "certainty": DIRECT, "location": "wing_3b",
		"player_rank": rank, "player_suspicion": meters[0], "player_reputation": meters[1],
		"belief_certainties": beliefs,
	})


## §7.2 percepción parcial acumulable: el refuerzo que CRUZA la certeza completa hace reevaluar al
## portador una sola vez (NPCDirector oye belief_decayed = «certeza cambiada»).
func _check_reinforcement_escalation() -> void:
	new_run()
	_clear()
	var room: String = NPCDirector.get_npc(AMELIA).home_room
	var id: String = BeliefNet.create_belief(AMELIA, "player", "seen_partially", PARTIAL, "direct", room)
	check_eq(_decisions_of(AMELIA), 1, "a partial sighting: one evaluation at birth")
	BeliefNet.reinforce_belief(id, 0.05)
	check_eq(_decisions_of(AMELIA), 1, "a reinforcement below full certainty: no new evaluation")
	BeliefNet.reinforce_belief(id, DIRECT)
	check(BeliefNet.get_belief(id).certainty >= DIRECT, "precondition: now at full certainty")
	check_eq(_decisions_of(AMELIA), 2, "crossing full certainty makes the holder re-evaluate")
	var last: Array = _decided.back()
	check(last[0] == AMELIA and float(last[2].get("certainty", 0.0)) >= DIRECT,
			"…with the reinforced certainty")
	BeliefNet.reinforce_belief(id, DIRECT)
	check_eq(_decisions_of(AMELIA), 2, "only once per belief")


func _decisions_of(npc_id: String) -> int:
	return _decided.filter(func(entry: Array) -> bool: return entry[0] == npc_id).size()


func _decided_action(npc_id: String) -> String:
	for entry: Array in _decided:
		if entry[0] == npc_id:
			return str(entry[1])
	return ""


func _clear() -> void:
	_decided.clear()
	_reported.clear()


func _on_decided(npc_id: String, action: String, context: Dictionary) -> void:
	_decided.append([npc_id, action, context])


func _on_reported(npc_id: String, report_type: String, weight: float, location: String) -> void:
	_reported.append([npc_id, report_type, weight, location])
