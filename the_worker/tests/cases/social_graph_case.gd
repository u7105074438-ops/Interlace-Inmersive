# social_graph_case.gd — Cuerpo de test_social_graph: grafo inicial, novata aislada, vínculos generados y comportamiento de los siete tipos de vínculo.
# PROPIETARIO DE: nada.
# ESCUCHA: rumor_spread (solo para registrar los saltos).
extends TestCase

const PLAYER := "player"
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const NATE := "npc_nate_brackley"
const CLAUDIA := "npc_claudia_reeves"
const RAY := "npc_ray_cudmore"
const SONIA := "npc_sonia_vail"
const BERNARD := "npc_bernard_lasker"
const CONNIE := "npc_connie_marks"
const ERNIE := "npc_ernie_vaughn"
const IGGY := "npc_iggy_robbins"
const ALVIN := "npc_alvin_pyne"
const MAURICE := "npc_maurice_sandbell"
const BREE := "npc_bree_nash"
const PRESTON := "npc_preston_vaile"
const CAFETERIA_CLAN := "cafeteria_clan"
const CHAT_3B := "chat_3b"
const ACCOUNTING_COUPLE := "accounting_couple"
const WING_3B := "wing_3b"
const CAFETERIA := "cafeteria"
const LUNCH := "lunch"
const NEGATIVE_FACT := "seen_partially"
const POSITIVE_FACT := "hard_worker"
const BURIED_FACT := "steals_ideas:npc_claudia_reeves"
const ROOKIE := "rookie"
const EPS := 0.000001
const OTHER_SEED := 777
# Números del manual (§7.2, §7.7, §31).
const MANUAL_DEPARTMENT := 0.75
const MANUAL_FRIENDSHIP := 0.90
const MANUAL_COUPLE := 0.98
const MANUAL_RIVALRY := 1.15
const MANUAL_HIERARCHY := 0.85
const MANUAL_ORAL := 0.75
const MANUAL_CAFETERIA_MAX := 45
const DATA_ACCOUNTING_STRENGTH := 0.95
const DATA_ERNIE_IGGY_DEBT := 0.7
const SOCIAL_TYPES: Array[String] = ["department", "friendship", "rivalry", "couple"]
# Reloj: una mañana laborable con todo el mundo en el edificio.
const MORNING_MINUTES := 180.0
const SMALL_DEBT_DAYS := 2
const SIGHTING_CERTAINTY := 0.5

var _hops: Array[Dictionary] = []


func run_case() -> void:
	check(new_run(), "Database loaded and a fresh run was created")
	EventBus.rumor_spread.connect(func(f: String, t: String, id: String) -> void:
		_hops.append({"from": f, "to": t, "id": id}))
	_test_initial_graph()
	_test_rookie_isolated()
	_test_generated_links()
	_test_transfer_factors()
	_test_nepotism_backfire()
	_test_participants()
	_test_debt_suppression()
	_test_couple_blackmail()
	_test_add_remove_links()
	_test_npc_removed()
	_test_kill_rumour()
	_test_determinism_and_save()


func _test_initial_graph() -> void:
	check(not SocialGraph.get_all_links().is_empty(), "build_initial_graph created links")
	check_eq(SocialGraph.get_link_type(GEORGE, DEBBIE), "department",
			"undirected links are mirrored (George → Debbie)")
	check_eq(SocialGraph.get_link_type(DEBBIE, BERNARD), "hierarchy", "Debbie reports to Bernard")
	check_eq(SocialGraph.get_link_type(BERNARD, DEBBIE), "", "hierarchy is directed upward")
	var incoming: bool = false
	for link: Dictionary in SocialGraph.get_links(BERNARD):
		incoming = incoming or (link["from"] == DEBBIE and link["type"] == "hierarchy"
				and bool(link["directed"]))
	check(incoming, "get_links(Bernard) lists Debbie's incoming hierarchy link")
	check_eq(SocialGraph.get_link_type(ERNIE, IGGY), "debt", "Ernie owes Iggy (npcs_named.json)")
	check_eq(SocialGraph.get_link_type(IGGY, ERNIE), "", "debt is directed (debtor → creditor)")
	check_eq(SocialGraph.get_link_type(NATE, PRESTON), "nepotism", "nepotism is mirrored")


func _test_rookie_isolated() -> void:
	var declared: bool = false
	for link: Dictionary in Database.get_named_npc(DEBBIE).initial_links:
		declared = declared or link["to"] == SONIA
	check(declared, "npcs_named.json declares a Debbie–Sonia friendship")
	check(SocialGraph.get_links(SONIA).is_empty(), "§8.3: Sonia (rookie) has no social edges")
	check_eq(SocialGraph.get_link_type(DEBBIE, SONIA), "", "the declared friendship was dropped")
	check(SocialGraph.is_isolated(SONIA), "Sonia is isolated")
	check(not SocialGraph.is_isolated(DEBBIE), "Debbie is not isolated")
	check(not SocialGraph.get_neighbours(DEBBIE, 0.0).has(SONIA), "Sonia is not Debbie's neighbour")
	var linked_rookies: int = 0
	for npc: NPCRuntime in NPCDirector.get_npcs_by_archetype(ROOKIE):
		if not npc.gatherings.has(ACCOUNTING_COUPLE) \
				and not SocialGraph.get_links(npc.id).is_empty():
			linked_rookies += 1
	check_eq(linked_rookies, 0, "no rookie (named or generated) has social edges")


## §24.3 paso 5 con npcs_generation.link_generation.
func _test_generated_links() -> void:
	var rules: Dictionary = Database.get_raw("npcs_generation")["link_generation"]
	var dept_min: int = int(rules["department_links_min"])
	var population: Dictionary = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		population[npc.id] = npc
	var short: Array[String] = []
	var wrong_department: int = 0
	for npc: NPCRuntime in population.values():
		if npc.is_named or npc.archetype == ROOKIE:
			continue
		var peers: int = _department_size(npc.department) - 1
		var social: int = 0
		for link: Dictionary in SocialGraph.get_links(npc.id):
			if SOCIAL_TYPES.has(link["type"]) and link["from"] == npc.id:
				social += 1
				var other: NPCRuntime = population.get(link["to"])
				if other == null or other.department != npc.department:
					wrong_department += 1
		if social < mini(dept_min, peers):
			short.append(npc.id)
	check(short.is_empty(),
			"every generated NPC has >= department_links_min social links %s" % [short])
	check_eq(wrong_department, 0,
			"generated department/friendship/rivalry/couple links stay in the department")
	_check_strength_ranges()
	_check_wing_hierarchy(population)


func _check_strength_ranges() -> void:
	var outside: Array[String] = []
	for link: Dictionary in SocialGraph.get_all_links():
		var spec: Dictionary = Database.get_social_link_type(link["type"])
		var s: float = float(link["strength"])
		if s < float(spec["strength_min"]) - EPS or s > float(spec["strength_max"]) + EPS:
			outside.append("%s→%s %s %.3f" % [link["from"], link["to"], link["type"], s])
	check(outside.is_empty(), "every link strength is inside its §31 range %s" % [outside])


func _check_wing_hierarchy(population: Dictionary) -> void:
	var missing: int = 0
	var checked: int = 0
	for npc: NPCRuntime in population.values():
		if npc.is_named or npc.archetype == ROOKIE or npc.home_room != WING_3B:
			continue
		checked += 1
		if SocialGraph.get_link_type(npc.id, BERNARD) != "hierarchy":
			missing += 1
	check(checked > 0, "there are generated wing 3B staff (%d)" % checked)
	check_eq(missing, 0, "generated wing 3B staff report to Bernard (superior_by_room)")


## §7.7 / §31: degradación por tipo, rivalidad solo negativa y amplificada, jerarquía relevante.
func _test_transfer_factors() -> void:
	var max_amp: float = Database.get_balance_float("creencias.amplificacion_rumor_max")
	check_near(max_amp, MANUAL_RIVALRY, EPS, "balance: rumours amplify up to ×1.15")
	check_near(SocialGraph.get_transfer_factor(DEBBIE, GEORGE, POSITIVE_FACT), MANUAL_DEPARTMENT,
			EPS, "department passes everything at ×0.75")
	check_near(SocialGraph.get_transfer_factor(RAY, CONNIE, NEGATIVE_FACT), MANUAL_FRIENDSHIP, EPS,
			"friendship passes at ×0.90 (minimal loss)")
	check_near(SocialGraph.get_transfer_factor(DEBBIE, CLAUDIA, NEGATIVE_FACT), max_amp, EPS,
			"rivalry amplifies negative information to the maximum ×1.15")
	check_eq(SocialGraph.get_transfer_factor(DEBBIE, CLAUDIA, POSITIVE_FACT), 0.0,
			"rivalry never passes positive information")
	check_eq(SocialGraph.get_transfer_factor(ERNIE, IGGY, NEGATIVE_FACT), 0.0,
			"debt propagates nothing")
	check_near(SocialGraph.get_transfer_factor(DEBBIE, BERNARD, NEGATIVE_FACT, GEORGE),
			MANUAL_HIERARCHY, EPS, "hierarchy carries negative news upward at ×0.85")
	check_near(SocialGraph.get_transfer_factor(DEBBIE, BERNARD, POSITIVE_FACT, PLAYER),
			MANUAL_HIERARCHY, EPS, "hierarchy carries news about the player upward")
	check_eq(SocialGraph.get_transfer_factor(DEBBIE, BERNARD, POSITIVE_FACT, GEORGE), 0.0,
			"hierarchy drops irrelevant (positive, not about the player) gossip")
	check_eq(SocialGraph.get_transfer_factor(BERNARD, DEBBIE, NEGATIVE_FACT), 0.0,
			"hierarchy does not descend")
	check_near(SocialGraph.get_transfer_factor(PRESTON, NATE, NEGATIVE_FACT), MANUAL_ORAL, EPS,
			"nepotism uses the standard oral transmission ×0.75")
	check_eq(SocialGraph.get_transfer_factor(DEBBIE, SONIA, NEGATIVE_FACT), 0.0,
			"no link, no rumour")


func _test_nepotism_backfire() -> void:
	check(SocialGraph.accusation_backfires(PLAYER, NATE),
			"accusing Nate (Preston's protégé) backfires on the accuser")
	check(SocialGraph.accusation_backfires(GEORGE, NATE), "it backfires on any accuser")
	check(not SocialGraph.accusation_backfires(PRESTON, NATE), "except the patron himself")
	check(not SocialGraph.accusation_backfires(PLAYER, PRESTON), "the patron is not protected")
	check(not SocialGraph.accusation_backfires(PLAYER, GEORGE), "ordinary staff are not protected")


func _test_participants() -> void:
	var clan: Array[String] = SocialGraph.get_gathering_participants(CAFETERIA_CLAN)
	var cap: int = int(Database.get_gathering(CAFETERIA_CLAN)["max_participants"])
	check_eq(cap, MANUAL_CAFETERIA_MAX, "social_graph.json caps the cafeteria clan at 45")
	check(not clan.is_empty() and clan.size() <= cap, "clan size within the cap (%d)" % clan.size())
	check(not clan.is_empty() and clan[0] == DEBBIE, "named members come first (Debbie)")
	var elsewhere: int = 0
	for npc_id: String in clan:
		if NPCDirector.get_scheduled_location(npc_id, LUNCH) != CAFETERIA:
			elsewhere += 1
	check_eq(elsewhere, 0, "every clan participant is scheduled in the cafeteria at lunch")
	var chat: Array[String] = SocialGraph.get_gathering_participants(CHAT_3B)
	check(chat.has(DEBBIE) and chat.has(GEORGE) and chat.has(CLAUDIA), "3B chat members")
	check(not chat.has(RAY) and not chat.has(SONIA), "Ray and Sonia are not in the 3B chat")
	check(SocialGraph.get_gathering_participants("no_such_gathering").is_empty(),
			"unknown gathering: no participants")
	check_eq(SocialGraph.propagate_at_gathering("no_such_gathering"), 0,
			"unknown gathering: no propagation")


## §7.7: la deuda suprime la denuncia hacia el acreedor, temporalmente.
func _test_debt_suppression() -> void:
	check(SocialGraph.is_denunciation_suppressed(ERNIE, IGGY), "Ernie will not denounce Iggy")
	check(not SocialGraph.is_denunciation_suppressed(IGGY, ERNIE),
			"the creditor is free to denounce")
	check(SocialGraph.is_denunciation_suppressed(ALVIN, IGGY), "Alvin owes Iggy too")
	check(SocialGraph.is_denunciation_suppressed(MAURICE, BREE), "Maurice owes Bree")
	check(not SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
			"George owes the player nothing")
	var rate: float = Database.get_balance_float("grafo_social.deuda_decaimiento_diario")
	check(rate > 0.0, "debts fade (grafo_social.deuda_decaimiento_diario)")
	SocialGraph.add_link(GEORGE, PLAYER, "debt", rate * SMALL_DEBT_DAYS)
	check(SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
			"a debt to the player silences George")
	check(not SocialGraph.get_neighbours(GEORGE, 0.0).has(PLAYER), "the player is not a neighbour")
	for day: int in SMALL_DEBT_DAYS:
		check(SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
				"still silenced on day %d" % day)
		EventBus.day_advanced.emit(GameClock.get_day() + day + 1)
	check(not SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
			"the debt faded: suppression was temporary")
	check_near(SocialGraph.get_link_strength(ERNIE, IGGY),
			DATA_ERNIE_IGGY_DEBT - rate * SMALL_DEBT_DAYS, EPS,
					"Ernie's debt fades by the same rate")


## §7.7: pareja total; clandestina = material de chantaje; nula hacia fuera.
func _test_couple_blackmail() -> void:
	var couple: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.gatherings.has(ACCOUNTING_COUPLE):
			couple.append(npc.id)
	check_eq(couple.size(), 2, "the accounting couple has two members")
	if couple.size() != 2:
		return
	var a: String = couple[0]
	var b: String = couple[1]
	check_eq(SocialGraph.get_link_type(a, b), "couple", "the accounting pair is a couple")
	check_eq(SocialGraph.get_link_type(b, a), "couple", "couples are mirrored")
	check_near(SocialGraph.get_link_strength(a, b), DATA_ACCOUNTING_STRENGTH, EPS, "strength 0.95")
	check(SocialGraph.is_blackmail_material(a, b), "a clandestine couple is blackmail material")
	check(not SocialGraph.get_blackmail_links(a).is_empty(),
			"the partner's blackmail links list it")
	check_near(SocialGraph.get_transfer_factor(a, b, NEGATIVE_FACT), MANUAL_COUPLE, EPS,
			"couples pass everything at ×0.98")
	_check_couple_gathering(a, b)
	check(SocialGraph.set_link_secret(a, b, false), "the affair comes out")
	check(not SocialGraph.is_blackmail_material(a, b), "a public couple is no longer leverage")
	SocialGraph.add_link(GEORGE, NATE, "couple", DATA_ACCOUNTING_STRENGTH)
	check_eq(SocialGraph.get_link_type(NATE, GEORGE), "couple",
			"add_link replaces the department link")
	check(not SocialGraph.is_blackmail_material(GEORGE, NATE), "add_link couples are not secret")


## Amplificación 0 del corrillo: nada sale de la pareja, pero entre ellos la propagación es total.
func _check_couple_gathering(a: String, b: String) -> void:
	GameClock.advance_minutes(MORNING_MINUTES)
	BeliefNet.create_belief(a, PLAYER, NEGATIVE_FACT, SIGHTING_CERTAINTY, Belief.SOURCE_DIRECT, "")
	_hops.clear()
	var spreads: int = SocialGraph.propagate_at_gathering(ACCOUNTING_COUPLE)
	check(spreads >= 1, "the couple talks despite the gathering's amplification 0")
	var outsiders: int = 0
	for hop: Dictionary in _hops:
		if not ((hop["from"] == a and hop["to"] == b) or (hop["from"] == b and hop["to"] == a)):
			outsiders += 1
	check_eq(outsiders, 0, "nothing leaves the accounting couple")


func _test_add_remove_links() -> void:
	var strong: Array[String] = SocialGraph.get_neighbours(DEBBIE, 0.45)
	check(strong.has(CLAUDIA) and strong.has(BERNARD),
			"neighbours >= 0.45 include Claudia and Bernard")
	check(not strong.has(NATE), "Nate's 0.3 link is below 0.45")
	SocialGraph.add_link(GEORGE, CLAUDIA, "rivalry", 1.7)
	check_near(SocialGraph.get_link_strength(CLAUDIA, GEORGE), 1.0, EPS, "strength is clamped to 1")
	SocialGraph.add_link(GEORGE, CLAUDIA, "no_such_type", 0.5)
	check_eq(SocialGraph.get_link_type(GEORGE, CLAUDIA), "rivalry", "unknown types are ignored")
	SocialGraph.remove_link(CLAUDIA, GEORGE)
	check_eq(SocialGraph.get_link_type(GEORGE, CLAUDIA), "",
			"removing an undirected link removes both")
	SocialGraph.remove_link(DEBBIE, BERNARD)
	check_eq(SocialGraph.get_link_type(DEBBIE, BERNARD), "", "a directed link can be removed")
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "department", "other links survive")
	for other: String in SocialGraph.get_neighbours(DEBBIE, 0.0):
		SocialGraph.remove_link(DEBBIE, other)
	check(SocialGraph.is_isolated(DEBBIE), "without her links, Debbie is isolated")


func _test_npc_removed() -> void:
	new_run()
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "department",
			"fresh run restores the graph")
	EventBus.npc_removed.emit(GEORGE, "expelled")
	check(SocialGraph.get_links(GEORGE).is_empty(), "a removed NPC keeps no links")
	check(not SocialGraph.get_neighbours(DEBBIE, 0.0).has(GEORGE), "nor appears as a neighbour")


func _test_kill_rumour() -> void:
	new_run()
	for holder: String in [DEBBIE, NATE, RAY]:
		BeliefNet.create_belief(holder, CLAUDIA, BURIED_FACT, SIGHTING_CERTAINTY,
				Belief.SOURCE_RUMOR, "")
	check_eq(SocialGraph.kill_rumour(BURIED_FACT), 3, "kill_rumour counts the rumours it buries")
	check(SocialGraph.is_fact_killed(BURIED_FACT), "the fact is buried")
	check(SocialGraph.get_killed_facts().has(BURIED_FACT), "listed as buried")
	check_eq(SocialGraph.get_transfer_factor(DEBBIE, GEORGE, BURIED_FACT), 0.0,
			"buried facts do not travel")
	_hops.clear()
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	var leaked: int = 0
	for hop: Dictionary in _hops:
		var b: Belief = BeliefNet.get_belief(hop["id"])
		if b != null and b.fact == BURIED_FACT:
			leaked += 1
	check_eq(leaked, 0, "the cafeteria no longer spreads the buried rumour")
	var days: int = Database.get_balance_int("grafo_social.dias_rumor_enterrado")
	GameClock.set_time(GameClock.get_day() + days, GameClock.get_hour(), GameClock.get_minute())
	check(not SocialGraph.is_fact_killed(BURIED_FACT), "burial lasts dias_rumor_enterrado days")
	SocialGraph.kill_rumour(BURIED_FACT)
	SocialGraph.inject_rumour(GEORGE, BURIED_FACT, SIGHTING_CERTAINTY)
	check(not SocialGraph.is_fact_killed(BURIED_FACT), "planting the fact again digs it up")


func _test_determinism_and_save() -> void:
	new_run()
	var first: String = _state_text(true)
	new_run()
	check(_state_text(true) == first, "same seed → same graph (bit for bit)")
	new_run(OTHER_SEED)
	check(_state_text(true) != first, "another seed → another generated graph")
	SocialGraph.inject_rumour(DEBBIE, BURIED_FACT, SIGHTING_CERTAINTY)
	SocialGraph.kill_rumour(BURIED_FACT)
	BeliefNet.create_belief(DEBBIE, PLAYER, NEGATIVE_FACT, SIGHTING_CERTAINTY,
			Belief.SOURCE_DIRECT, WING_3B)
	check(SocialGraph.propagate_at_gathering(CHAT_3B) > 0, "the 3B chat spreads Debbie's sighting")
	check(not SocialGraph.get_chat_log().is_empty(), "the chat hops are logged")
	var saved: Dictionary = SocialGraph.save_state()
	var text: String = JSON.stringify(saved, "", true, true)
	SocialGraph.reset_for_new_run()
	check(SocialGraph.get_all_links().is_empty() and SocialGraph.get_injected_rumours().is_empty(),
			"reset_for_new_run empties the graph")
	SocialGraph.load_state(JSON.parse_string(text))
	var loaded: Dictionary = SocialGraph.save_state()
	# Godot's JSON parser may move a float by one ulp: compare at the default JSON precision.
	var expected: String = JSON.stringify(saved, "", true)
	var got: String = _state_text(false)
	check(got == expected, "save → JSON → load reproduces the state%s" % _difference(got, expected))
	check_eq(loaded["links"].size(), saved["links"].size(), "every link survives the round trip")
	check_eq(loaded["rng_state"], saved["rng_state"], "the propagation RNG resumes where it was")
	check(SocialGraph.is_fact_killed(BURIED_FACT), "buried facts survive the round trip")
	check(not SocialGraph.get_chat_log().is_empty(), "the IT chat log survives the round trip")
	check_eq(SocialGraph.get_injected_rumours().size(), 1, "planted rumours survive the round trip")


## "" si son iguales; si no, el contexto de la primera diferencia (mensajes de fallo cortos).
static func _difference(a: String, b: String) -> String:
	if a == b:
		return ""
	var i: int = 0
	while i < mini(a.length(), b.length()) and a[i] == b[i]:
		i += 1
	return " (differs at %d: got …%s… expected …%s…)" % [i, a.substr(maxi(i - 60, 0), 120),
			b.substr(maxi(i - 60, 0), 120)]


func _state_text(full_precision: bool) -> String:
	return JSON.stringify(SocialGraph.save_state(), "", true, full_precision)


func _department_size(department: String) -> int:
	var count: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.department == department and npc.archetype != ROOKIE:
			count += 1
	return count
