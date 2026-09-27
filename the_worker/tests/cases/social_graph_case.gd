# social_graph_case.gd — Cuerpo de test_social_graph: grafo inicial y §24.3 paso 5 (mínimos y máximos por tipo), novata aislada, los siete tipos de vínculo, sillas que cambian de titular, calendario y presencia de los corrillos, eco, kill_rumour, tope de amplificación y guardado.
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
const TOM := "npc_tom_iverson"
const FRANK := "npc_frank_rudd"
const CAFETERIA_CLAN := "cafeteria_clan"
const CHAT_3B := "chat_3b"
const SMOKERS := "smokers_circle"
const FOOSBALL := "foosball_circle"
const ACCOUNTING_COUPLE := "accounting_couple"
const WING_3B := "wing_3b"
const WING_CHIEF := "wing_3b_chief"
const CAFETERIA := "cafeteria"
const LUNCH := "lunch"
const NEGATIVE_FACT := "seen_partially"
const POSITIVE_FACT := "hard_worker"
const BURIED_FACT := "steals_ideas:npc_claudia_reeves"
const ROOKIE := "rookie"
const EPS := 0.000001
const OTHER_SEED := 777
const SOCIAL_TYPES: Array[String] = ["department", "friendship", "rivalry", "couple"]
const GENERATED_TYPES: Array[String] = ["department", "friendship", "rivalry"]
const PROPAGATING_NONE := "none"
# Números del manual (§7.2, §7.7, §31, §24.3).
const MANUAL_DEPARTMENT := 0.75
const MANUAL_FRIENDSHIP := 0.90
const MANUAL_COUPLE := 0.98
const MANUAL_RIVALRY := 1.15
const MANUAL_HIERARCHY := 0.85
const MANUAL_ORAL := 0.75
const MANUAL_RIVALRY_MAX := 0.7
const MANUAL_DEBT_MIN := 0.5
const MANUAL_CAFETERIA_MAX := 45
const MANUAL_SMOKER_HOURS: Array[int] = [10, 12, 14, 16, 18]
const DATA_ACCOUNTING_STRENGTH := 0.95
const DATA_ERNIE_IGGY_DEBT := 0.7
# Reloj.
const MORNING_MINUTES := 180.0
const HOUR_MINUTES := 60.0
const TEN_MINUTES := 10.0
const NINE := 9
const TEN := 10
const ELEVEN := 11
const TWELVE := 12
const THIRTEEN := 13
const FOURTEEN := 14
const LAST_SMOKERS_HOUR := 18
const DAY_END_HOUR := 19
const HALF_PAST_ONE := 30
const BEFORE_HOUR := 50
const NIGHT_HOUR := 22
const NIGHT_SESSION_HOUR := 23
const BEFORE_ROLLOVER_HOUR := 5
const SIGHTING_CERTAINTY := 0.5
const STRONG_CERTAINTY := 0.9
const WEAK_CERTAINTY := 0.12
const TEST_TYPE := "test_megaphone"
const TEST_DEGRADATION := 1.5

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
	_test_seat_changes()
	_test_reassignment_isolates()
	_test_schedule()
	_test_presence_gating()
	_test_raise_without_echo()
	_test_kill_rumour()
	_test_determinism_and_save()
	_test_amplification_cap()


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


## §24.3 paso 5 con npcs_generation.link_generation: cada personaje, contando sus propias aristas
## (reflejos incluidos), queda entre el mínimo y el máximo de cada tipo.
func _test_generated_links() -> void:
	var rules: Dictionary = Database.get_raw("npcs_generation")["link_generation"]
	var counts: Dictionary = _own_counts()
	var declared: Dictionary = _declared_counts()
	var over: Array[String] = []
	var short: Array[String] = []
	var checked: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.archetype == ROOKIE:
			continue
		for link_type: String in GENERATED_TYPES:
			var cap: int = int(rules[link_type + "_links_max"])
			if npc.is_named:
				cap = maxi(cap, int(declared.get(_count_key(npc.id, link_type), 0)))
			var own: int = int(counts.get(_count_key(npc.id, link_type), 0))
			if own > cap:
				over.append("%s %s=%d" % [npc.id, link_type, own])
		if npc.is_named:
			continue
		checked += 1
		var dept: int = int(counts.get(_count_key(npc.id, "department"), 0))
		if dept < mini(int(rules["department_links_min"]), _department_size(npc.department) - 1):
			short.append("%s department=%d" % [npc.id, dept])
	check(checked > 0, "generated characters were checked (%d)" % checked)
	check(over.is_empty(), "§24.3: nobody exceeds 5 department, 2 friendship, 1 rivalry %s" % [over])
	check(short.is_empty(), "§24.3: every generated character has >= 2 department links %s"
			% [short])
	_check_link_departments()
	_check_strength_ranges()
	_check_wing_hierarchy()


## Aristas salientes por (personaje, tipo), reflejos incluidos.
func _own_counts() -> Dictionary:
	var out: Dictionary = {}
	for link: Dictionary in SocialGraph.get_all_links():
		var key: String = _count_key(str(link["from"]), str(link["type"]))
		out[key] = int(out.get(key, 0)) + 1
	return out


## Aristas que npcs_named.json declara para cada nominado (ambos extremos de las no dirigidas).
func _declared_counts() -> Dictionary:
	var out: Dictionary = {}
	for named: NPCData in Database.get_all_named_npcs():
		for link: Dictionary in named.initial_links:
			var link_type: String = str(link["type"])
			for end: String in [named.id, str(link["to"])]:
				var key: String = _count_key(end, link_type)
				out[key] = int(out.get(key, 0)) + 1
	return out


static func _count_key(npc_id: String, link_type: String) -> String:
	return npc_id + "|" + link_type


func _check_link_departments() -> void:
	var wrong: int = 0
	for link: Dictionary in SocialGraph.get_all_links():
		var a: NPCRuntime = NPCDirector.get_npc(str(link["from"]))
		var b: NPCRuntime = NPCDirector.get_npc(str(link["to"]))
		if a == null or b == null or a.is_named or not SOCIAL_TYPES.has(link["type"]):
			continue
		if a.department != b.department:
			wrong += 1
	check_eq(wrong, 0, "generated department/friendship/rivalry/couple links stay in the department")


func _check_strength_ranges() -> void:
	var outside: Array[String] = []
	for link: Dictionary in SocialGraph.get_all_links():
		var spec: Dictionary = Database.get_social_link_type(link["type"])
		var s: float = float(link["strength"])
		if s < float(spec["strength_min"]) - EPS or s > float(spec["strength_max"]) + EPS:
			outside.append("%s→%s %s %.3f" % [link["from"], link["to"], link["type"], s])
	check(outside.is_empty(), "every link strength is inside its §31 range %s" % [outside])


func _check_wing_hierarchy() -> void:
	var missing: int = 0
	var checked: int = 0
	for npc_id: String in _generated_wing_staff():
		checked += 1
		if SocialGraph.get_link_type(npc_id, BERNARD) != "hierarchy":
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
	SocialGraph.add_link(GEORGE, PLAYER, "debt", rate)
	check_near(SocialGraph.get_link_strength(GEORGE, PLAYER), MANUAL_DEBT_MIN, EPS,
			"add_link clamps a debt to its §31 minimum 0.5")
	check(SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
			"a debt to the player silences George")
	check(not SocialGraph.get_neighbours(GEORGE, 0.0).has(PLAYER), "the player is not a neighbour")
	var days: int = ceili(MANUAL_DEBT_MIN / rate - EPS)
	var silent: bool = true
	for day: int in days:
		silent = silent and SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER)
		EventBus.day_advanced.emit(GameClock.get_day() + day + 1)
	check(silent, "George stayed silent for %d days (0.5 ÷ daily fade)" % days)
	check(not SocialGraph.is_denunciation_suppressed(GEORGE, PLAYER),
			"the debt faded: suppression was temporary")
	check_near(SocialGraph.get_link_strength(ERNIE, IGGY), DATA_ERNIE_IGGY_DEBT - rate * days,
			EPS, "Ernie's debt fades by the same rate")


## §7.7: pareja total; clandestina = material de chantaje; nula hacia fuera hasta que se descubre.
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
	var counts: Dictionary = _own_counts()
	check(int(counts.get(_count_key(a, "couple"), 0)) == 1
			and int(counts.get(_count_key(b, "couple"), 0)) == 1,
			"each accounting partner has exactly one couple link (no second random affair)")
	check_near(SocialGraph.get_link_strength(a, b), DATA_ACCOUNTING_STRENGTH, EPS, "strength 0.95")
	check(SocialGraph.is_blackmail_material(a, b), "a clandestine couple is blackmail material")
	check(not SocialGraph.get_blackmail_links(a).is_empty(),
			"the partner's blackmail links list it")
	check_near(SocialGraph.get_transfer_factor(a, b, NEGATIVE_FACT), MANUAL_COUPLE, EPS,
			"couples pass everything at ×0.98")
	check_eq(SocialGraph.get_gathering_amplification(ACCOUNTING_COUPLE), 0.0,
			"while secret, the accounting couple's gathering is null outward")
	_check_couple_gathering(a, b)
	check(SocialGraph.set_link_secret(a, b, false), "the affair comes out")
	check(not SocialGraph.is_blackmail_material(a, b), "a public couple is no longer leverage")
	check_near(SocialGraph.get_gathering_amplification(ACCOUNTING_COUPLE),
			Database.get_balance_float("grafo_social.amplificacion_secreto_descubierto"), EPS,
			"once discovered, the gathering talks outward again")
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
	check_eq(outsiders, 0, "nothing leaves the accounting couple (not even to their boss)")


func _test_add_remove_links() -> void:
	var strong: Array[String] = SocialGraph.get_neighbours(DEBBIE, 0.45)
	check(strong.has(CLAUDIA) and strong.has(BERNARD),
			"neighbours >= 0.45 include Claudia and Bernard")
	check(not strong.has(NATE), "Nate's 0.3 link is below 0.45")
	SocialGraph.add_link(GEORGE, CLAUDIA, "rivalry", 1.7)
	check_near(SocialGraph.get_link_strength(CLAUDIA, GEORGE), MANUAL_RIVALRY_MAX, EPS,
			"strength is clamped to the rivalry range (§31 max 0.7)")
	SocialGraph.add_link(GEORGE, CLAUDIA, "no_such_type", 0.5)
	check_eq(SocialGraph.get_link_type(GEORGE, CLAUDIA), "rivalry", "unknown types are ignored")
	SocialGraph.remove_link(CLAUDIA, GEORGE)
	check_eq(SocialGraph.get_link_type(GEORGE, CLAUDIA), "",
			"removing an undirected link removes both")
	_check_masked_mirror()
	SocialGraph.remove_link(DEBBIE, BERNARD)
	check_eq(SocialGraph.get_link_type(DEBBIE, BERNARD), "", "a directed link can be removed")
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "department", "other links survive")
	for other: String in SocialGraph.get_neighbours(DEBBIE, 0.0):
		SocialGraph.remove_link(DEBBIE, other)
	check(SocialGraph.is_isolated(DEBBIE), "without her links, Debbie is isolated")


## Un no dirigido nunca pisa un dirigido de sentido contrario; al quitar el dirigido vuelve el
## reflejo (sin aristas no dirigidas de un solo sentido).
func _check_masked_mirror() -> void:
	SocialGraph.add_link(BERNARD, RAY, "department", 0.4)
	check_eq(SocialGraph.get_link_type(BERNARD, RAY), "department", "Bernard → Ray: department")
	check_eq(SocialGraph.get_link_type(RAY, BERNARD), "hierarchy",
			"the mirror does not overwrite Ray's directed hierarchy link")
	SocialGraph.remove_link(RAY, BERNARD)
	check_eq(SocialGraph.get_link_type(RAY, BERNARD), "department",
			"removing the hierarchy restores the masked department mirror")
	SocialGraph.remove_link(BERNARD, RAY)
	check(SocialGraph.get_link_type(RAY, BERNARD) == ""
			and SocialGraph.get_link_type(BERNARD, RAY) == "", "then both directions go")
	SocialGraph.add_link(GEORGE, NATE, "department", 0.4)
	SocialGraph.add_link(GEORGE, NATE, "debt", 0.6)
	check(SocialGraph.get_link_type(GEORGE, NATE) == "debt"
			and SocialGraph.get_link_type(NATE, GEORGE) == "department",
			"a directed link over an undirected one keeps the other direction")
	SocialGraph.remove_link(GEORGE, NATE)
	check_eq(SocialGraph.get_link_type(GEORGE, NATE), "department",
			"removing the debt leaves the symmetric department link")


func _test_npc_removed() -> void:
	new_run()
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "department",
			"fresh run restores the graph")
	NPCDirector.remove_npc(GEORGE, "expelled")
	check(SocialGraph.get_links(GEORGE).is_empty(), "a removed NPC keeps no links")
	check(not SocialGraph.get_neighbours(DEBBIE, 0.0).has(GEORGE), "nor appears as a neighbour")
	_hops.clear()
	check_eq(SocialGraph.inject_rumour(GEORGE, BURIED_FACT, SIGHTING_CERTAINTY), "",
			"no rumour can be planted on an expelled character")
	check(_hops.is_empty(), "and nothing is emitted for it")


## §7.7 / §24.3: la jerarquía sigue a la silla. Bernard sale; quien ocupe la jefatura del ala
## hereda a los subordinados (nominados y generados).
func _test_seat_changes() -> void:
	new_run()
	var staff: Array[String] = _generated_wing_staff()
	NPCDirector.remove_npc(BERNARD, "expelled")
	check_eq(SocialGraph.get_link_type(DEBBIE, BERNARD), "", "nobody reports to an expelled chief")
	Company.auto_fill_vacancies()
	var chief: String = _holder_of(WING_CHIEF)
	check(not chief.is_empty() and chief != BERNARD, "Company filled the wing chief seat (%s)" % chief)
	var missing: Array[String] = []
	for npc_id: String in staff:
		if npc_id != chief and NPCDirector.is_active(npc_id) \
				and SocialGraph.get_link_type(npc_id, chief) != "hierarchy":
			missing.append(npc_id)
	check(missing.is_empty(), "every generated 3B subordinate now reports to %s %s"
			% [chief, missing])
	if chief != DEBBIE:
		check_eq(SocialGraph.get_link_type(DEBBIE, chief), "hierarchy",
				"Debbie's hierarchy link followed the seat to the new chief")
		check_near(SocialGraph.get_transfer_factor(DEBBIE, chief, NEGATIVE_FACT), MANUAL_HIERARCHY,
				EPS, "relevant 3B news rises to the new chief again (×0.85)")


## §7.7: reasignar a una víctima como jefe de ala reduce sus aristas (menos testigos efectivos).
func _test_reassignment_isolates() -> void:
	new_run()
	var before: int = _propagating_links(GEORGE)
	check(_type_count(GEORGE, "department") > 0, "George starts with department colleagues")
	Company.vacate_seat(WING_CHIEF, "reassigned")
	Company.fill_seat(WING_CHIEF, GEORGE)
	check_eq(_holder_of(WING_CHIEF), GEORGE, "George was reassigned as wing chief")
	check_eq(_type_count(GEORGE, "department"), 0, "the move left his department colleagues behind")
	check(_propagating_links(GEORGE) < before, "fewer propagating edges (%d → %d)"
			% [before, _propagating_links(GEORGE)])
	check_eq(SocialGraph.get_link_type(GEORGE, BERNARD), "", "George no longer reports to Bernard")
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "hierarchy",
			"Debbie now reports to George (the seat's subordinates followed it)")
	check_eq(SocialGraph.get_link_type(DEBBIE, BERNARD), "", "and no longer to Bernard")


## §7.7: fumadores cada 2 horas (10-18), futbolín en cada cambio de franja con quien pasó por la
## sala, cafetería al acabar la comida, chat también de noche.
func _test_schedule() -> void:
	new_run()
	var day: int = GameClock.get_day()
	GameClock.set_time(day, NINE, BEFORE_HOUR)
	GameClock.advance_minutes(TEN_MINUTES)
	var smokers: Dictionary = SocialGraph.get_last_session(SMOKERS)
	check_eq(smokers.get("hour", -1), TEN, "smokers met at 10:00")
	check(_participants(SMOKERS).has(RAY), "Ray (out at 10:00) joined the 10:00 smokers")
	check(not _participants(SMOKERS).has(TOM), "Tom (out at 10:30) was not at the 10:00 session")
	GameClock.advance_minutes(HOUR_MINUTES)
	check_eq(SocialGraph.get_last_session(SMOKERS).get("hour", -1), TEN, "no smokers at 11:00")
	GameClock.advance_minutes(HOUR_MINUTES)
	check_eq(SocialGraph.get_last_session(SMOKERS).get("hour", -1), TWELVE, "smokers met at 12:00")
	check(_participants(SMOKERS).has(TOM) and _participants(SMOKERS).has(FRANK),
			"Tom (10:30) and Frank (11:00) joined the 12:00 smokers")
	check(not _participants(SMOKERS).has(RAY), "Ray's 10:00 cigarette is not counted twice")
	GameClock.advance_minutes(HOUR_MINUTES)
	check_eq(SocialGraph.get_last_session(FOOSBALL).get("hour", -1), THIRTEEN,
			"foosball met at the 13:00 band change")
	check(_participants(FOOSBALL).has(NATE), "Nate (foosball at 11:30) joined the morning circle")
	check(SocialGraph.get_last_session(CAFETERIA_CLAN).is_empty(), "no cafeteria clan at 13:00")
	GameClock.advance_minutes(HOUR_MINUTES)
	check_eq(SocialGraph.get_last_session(CAFETERIA_CLAN).get("hour", -1), FOURTEEN,
			"the cafeteria clan met when lunch ended")
	check(not _participants(FOOSBALL).has(NATE),
			"Nate lunched in the cafeteria: not in the lunch-band foosball circle")
	_check_smoker_hours(day)


func _check_smoker_hours(day: int) -> void:
	var met: Array[int] = []
	GameClock.set_time(day, TEN, 0)
	for hour: int in range(ELEVEN, DAY_END_HOUR + 1):
		GameClock.advance_minutes(HOUR_MINUTES)
		var session_hour: int = int(SocialGraph.get_last_session(SMOKERS).get("hour", -1))
		if session_hour == hour:
			met.append(hour)
	var expected: Array[int] = []
	for hour: int in MANUAL_SMOKER_HOURS:
		if hour >= ELEVEN:
			expected.append(hour)
	check_eq(met, expected, "from 11:00 to 19:00 the smokers meet exactly at 12, 14, 16, 18")
	GameClock.set_time(day, NIGHT_HOUR, BEFORE_HOUR)
	GameClock.advance_minutes(TEN_MINUTES)
	check_eq(SocialGraph.get_last_session(CHAT_3B).get("hour", -1), NIGHT_SESSION_HOUR,
			"the 3B chat also meets at 23:00")
	check_eq(SocialGraph.get_last_session(SMOKERS).get("hour", -1), LAST_SMOKERS_HOUR,
			"no smokers at night")


## Un vínculo no jerárquico con alguien ausente no transmite en la cafetería; la jerarquía llega
## al superior ausente.
func _test_presence_gating() -> void:
	new_run()
	GameClock.set_time(GameClock.get_day(), THIRTEEN, HALF_PAST_ONE)
	SocialGraph.add_link(DEBBIE, FRANK, "friendship", MANUAL_FRIENDSHIP)
	BeliefNet.create_belief(DEBBIE, PLAYER, NEGATIVE_FACT, STRONG_CERTAINTY, Belief.SOURCE_DIRECT,
			WING_3B)
	_hops.clear()
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check(not _participants(CAFETERIA_CLAN).has(FRANK), "Frank does not lunch with the clan")
	check(not _hop_to(DEBBIE, FRANK), "Debbie's friend Frank, absent, hears nothing at lunch")
	check(_hop_to(DEBBIE, BERNARD), "hierarchy reaches Bernard although he eats at his desk")


## Una fuente más fiable eleva una creencia débil; nadie devuelve el rumor a quien se lo contó.
func _test_raise_without_echo() -> void:
	new_run()
	BeliefNet.create_belief(GEORGE, PLAYER, NEGATIVE_FACT, WEAK_CERTAINTY, Belief.SOURCE_RUMOR, "")
	BeliefNet.create_belief(DEBBIE, PLAYER, NEGATIVE_FACT, STRONG_CERTAINTY, Belief.SOURCE_DIRECT,
			"")
	var seen: float = _certainty(DEBBIE, PLAYER, NEGATIVE_FACT)
	_hops.clear()
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check_near(_certainty(GEORGE, PLAYER, NEGATIVE_FACT), seen * MANUAL_DEPARTMENT, EPS,
			"George's weak 0.12 belief was raised to Debbie's × 0.75")
	check(_hop_to(DEBBIE, CLAUDIA), "Debbie told her rival Claudia (×1.15)")
	check(not _hop_to(CLAUDIA, DEBBIE), "Claudia never tells it back to Debbie")
	check_near(_certainty(DEBBIE, PLAYER, NEGATIVE_FACT), seen, EPS,
			"no echo inflated Debbie's own certainty")


## kill_rumour entierra el rumor hasta el cambio de jornada: BeliefNet olvida sus copias y después
## los testigos de primera mano vuelven a contar lo que vieron.
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
	check_eq(_hops_of_fact(BURIED_FACT), 0, "the cafeteria no longer spreads the buried rumour")
	SocialGraph.inject_rumour(GEORGE, BURIED_FACT, SIGHTING_CERTAINTY)
	check(not SocialGraph.is_fact_killed(BURIED_FACT), "planting the fact again digs it up")
	_check_burial_ends_at_day_change()


func _check_burial_ends_at_day_change() -> void:
	new_run()
	var day: int = GameClock.get_day()
	BeliefNet.create_belief(DEBBIE, PLAYER, NEGATIVE_FACT, STRONG_CERTAINTY, Belief.SOURCE_DIRECT,
			"")
	BeliefNet.create_belief(NATE, PLAYER, NEGATIVE_FACT, SIGHTING_CERTAINTY, Belief.SOURCE_RUMOR,
			"")
	check_eq(SocialGraph.kill_rumour(NEGATIVE_FACT), 1, "only Nate's copy is a rumour")
	GameClock.set_time(day, BEFORE_ROLLOVER_HOUR, BEFORE_HOUR)
	GameClock.advance_minutes(TEN_MINUTES)
	check_eq(GameClock.get_day(), day + 1, "the day changed")
	check(not SocialGraph.is_fact_killed(NEGATIVE_FACT), "the burial ended with the day change")
	check(_certainty(NATE, PLAYER, NEGATIVE_FACT) < 0.0, "BeliefNet forgot the buried rumour")
	var seen: float = _certainty(DEBBIE, PLAYER, NEGATIVE_FACT)
	check(seen > 0.0, "Debbie still remembers what she saw herself")
	GameClock.set_time(day + 1, THIRTEEN, HALF_PAST_ONE)
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check_near(_certainty(GEORGE, PLAYER, NEGATIVE_FACT), seen * MANUAL_DEPARTMENT, EPS,
			"after the day change her first-hand sighting spreads again (no lasting veto)")


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
	NPCDirector.remove_npc(BERNARD, "expelled")
	var saved: Dictionary = SocialGraph.save_state()
	check(not (saved["seat_links"] as Dictionary).is_empty(),
			"the wing chief seat keeps its subordinates waiting (saved)")
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
	check_eq(SocialGraph.get_last_session(CHAT_3B).get("spreads", -1),
			(saved["sessions"] as Dictionary)[CHAT_3B]["spreads"], "sessions survive the round trip")


## El factor de un vínculo nunca pasa de creencias.amplificacion_rumor_max, aunque su tipo
## declare una degradación mayor (tipo de prueba cargado con Database.load_from_raw).
func _test_amplification_cap() -> void:
	new_run()
	var original: Dictionary = {}
	for file_id: String in Database.get_data_file_ids():
		original[file_id] = Database.get_raw(file_id)
	var raw: Dictionary = original.duplicate(true)
	(raw["social_graph"]["link_types"] as Array).append({
		"id": TEST_TYPE, "strength_min": STRONG_CERTAINTY, "strength_max": 1.0,
		"propagates": "all", "degradation": TEST_DEGRADATION, "directed": false,
		"name_key": "LINK_FRIENDSHIP",
	})
	check(Database.load_from_raw(raw), "Database accepts a test link type with degradation 1.5")
	SocialGraph.reset_for_new_run()
	SocialGraph.add_link(DEBBIE, GEORGE, TEST_TYPE, 1.0)
	check_near(SocialGraph.get_transfer_factor(DEBBIE, GEORGE, POSITIVE_FACT), MANUAL_RIVALRY, EPS,
			"a ×1.5 link is capped at creencias.amplificacion_rumor_max ×1.15")
	BeliefNet.create_belief(DEBBIE, CLAUDIA, POSITIVE_FACT, SIGHTING_CERTAINTY,
			Belief.SOURCE_RUMOR, "")
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check_near(_certainty(GEORGE, CLAUDIA, POSITIVE_FACT), SIGHTING_CERTAINTY * MANUAL_RIVALRY,
			EPS, "George receives 0.5 × 1.15, not 0.5 × 1.5")
	check(Database.load_from_raw(original), "the real data is restored")
	SocialGraph.reset_for_new_run()


# ─── Utilidades ───────────────────────────────────────────────

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


func _generated_wing_staff() -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.is_named and npc.archetype != ROOKIE and npc.home_room == WING_3B:
			out.append(npc.id)
	return out


func _holder_of(occupation_id: String) -> String:
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(occupation_id)
	return holder.id if holder != null else ""


func _type_count(npc_id: String, link_type: String) -> int:
	return int(_own_counts().get(_count_key(npc_id, link_type), 0))


func _propagating_links(npc_id: String) -> int:
	var count: int = 0
	for link: Dictionary in SocialGraph.get_all_links():
		var spec: Dictionary = Database.get_social_link_type(link["type"])
		if link["from"] == npc_id and link["to"] != PLAYER \
				and str(spec.get("propagates", "")) != PROPAGATING_NONE:
			count += 1
	return count


func _participants(gathering_id: String) -> Array:
	return SocialGraph.get_last_session(gathering_id).get("participants", [])


func _hop_to(from_npc: String, to_npc: String) -> bool:
	for hop: Dictionary in _hops:
		if hop["from"] == from_npc and hop["to"] == to_npc:
			return true
	return false


func _hops_of_fact(fact: String) -> int:
	var count: int = 0
	for hop: Dictionary in _hops:
		var b: Belief = BeliefNet.get_belief(hop["id"])
		if b != null and b.fact == fact:
			count += 1
	return count


func _certainty(holder: String, subject: String, fact: String) -> float:
	for b: Belief in BeliefNet.get_beliefs_held_by(holder):
		if b.subject == subject and b.fact == fact and not b.is_record:
			return b.certainty
	return -1.0
