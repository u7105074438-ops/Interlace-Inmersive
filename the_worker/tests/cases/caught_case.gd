# caught_case.gd — Cuerpo de test_caught: flagrancia (§12.2) con los doce arquetipos y la ventana de decisión.
# PROPIETARIO DE: nada.
# ESCUCHA: npc_reported_player, npc_decided, crime_committed, game_over, blackmail_demanded, bribe_offered, phone_message_received, subtitle_posted (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const CRIME := "drawer_forced"
const EPS := 0.000001
const SUSPICION_EPS := 0.001
## Tabla de inacción del manual §12.2: arquetipo → [acción, tipo de denuncia, sospecha].
## Los arquetipos que la tabla no nombra usan su caught_reaction de archetypes.json.
const EXPECTED: Dictionary = {
	"hardliner": ["report_to_security", "security", 20.0],
	"snitch": ["report_to_security", "security", 20.0],
	"incorruptible": ["report_to_security", "security", 20.0],
	"company_man": ["report_to_superior", "superior", 10.0],
	"rookie": ["report_to_superior", "superior", 10.0],
	"gossip": ["gossip", "", 0.0],
	"coward": ["stay_silent", "", 0.0],
	"burnout": ["ignore", "", 0.0],
	"oblivious": ["ignore", "", 0.0],
	"old_hand": ["remember", "", 0.0],
	"climber": ["keep_leverage", "", 0.0],
	"bribable": ["blackmail_player", "", 0.0],
}
const WATCHED: Array[String] = ["npc_reported_player", "npc_decided", "crime_committed",
		"game_over", "blackmail_demanded", "bribe_offered", "phone_message_received",
		"subtitle_posted"]

var _log: Fixtures.SignalLog = null
var _npcs: Dictionary = {}
var _handler: CaughtHandler = null
var _wallet: Fixtures.FakeWallet = null
var _window_log: Array[Array] = []
var _roll: float = 0.0
var _room: String = ""


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_room = PlayerState.get_room()
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_check_archetype_count()
	_setup_handler()
	for archetype: String in EXPECTED:
		_check_inaction(archetype)
	_check_indifference_is_a_chance()
	_check_real_reporter_credibility()
	_check_deadline_and_reputation()
	_check_debt_silences()
	_check_witnesses_block_elimination()
	_check_elimination_without_witnesses()
	_check_witness_ids()
	_check_insufficient_capital()
	_check_below_price()
	_check_accepted_bribe_keeps_belief()
	_check_bribe_refusals()
	_check_neutral_refusal_reacts()
	_check_counteroffer_window()
	_check_gossip_at_lunch()
	_check_gossip_cancelled()
	_check_queue()
	_check_removed_catcher()
	_check_game_over_closes()
	_check_time_restore()
	_check_save_load()
	_check_hesitation()
	_log.stop()
	_handler.queue_free()
	await get_tree().process_frame


func _npc(archetype: String) -> NPCRuntime:
	var npc_id: String = "test_" + archetype
	if not _npcs.has(npc_id):
		_npcs[npc_id] = Fixtures.synthetic(npc_id, archetype)
	return _npcs[npc_id]


## Creencias limpias (la sospecha no se satura entre comprobaciones).
func _fresh_beliefs() -> void:
	BeliefNet.reset_for_new_run()


func _suspicion() -> float:
	return BeliefNet.calculate_player_suspicion()


func _check_archetype_count() -> void:
	check_eq(Database.get_all_archetypes().size(), 12, "the twelve archetypes are loaded")
	for archetype: ArchetypeData in Database.get_all_archetypes():
		check(EXPECTED.has(archetype.id), "archetype %s has a documented reaction" % archetype.id)


func _setup_handler() -> void:
	_handler = CaughtHandler.new()
	_handler.npc_resolver = func(npc_id: String) -> NPCRuntime: return _npcs.get(npc_id)
	_handler.roll_source = func() -> float: return _roll
	_wallet = Fixtures.FakeWallet.new(5000)
	_handler.wallet = _wallet
	add_child(_handler)
	_handler.set_process(false)
	_handler.decision_window_opened.connect(
			func(npc_id: String, options: Dictionary) -> void: _window_log.append(["opened", npc_id, options]))
	_handler.decision_window_updated.connect(
			func(npc_id: String, options: Dictionary) -> void: _window_log.append(["updated", npc_id, options]))
	_handler.decision_window_closed.connect(
			func(npc_id: String, outcome: String) -> void: _window_log.append(["closed", npc_id, outcome]))
	for archetype: String in EXPECTED:
		_npc(archetype)


func _last_window(kind: String) -> Array:
	for i: int in range(_window_log.size() - 1, -1, -1):
		if _window_log[i][0] == kind:
			return _window_log[i]
	return []


func _catch(npc_id: String, witnesses: int) -> Dictionary:
	_log.clear()
	EventBus.player_caught_redhanded.emit(npc_id, CRIME, witnesses)
	return _handler.get_options()


## Deja correr el plazo entero (el testigo actúa solo).
func _timeout() -> void:
	_handler.advance_timer(float(_handler.get_options().get("seconds_left", 0.0)) + 0.01)


func _decided(npc_id: String) -> Array[Array]:
	var out: Array[Array] = []
	for args: Array in _log.all("npc_decided"):
		if str(args[0]) == npc_id:
			out.append(args)
	return out


## Cada arquetipo, por la vía real: player_caught_redhanded → ventana → plazo agotado.
func _check_inaction(archetype: String) -> void:
	_fresh_beliefs()
	var npc: NPCRuntime = _npc(archetype)
	var expected: Array = EXPECTED[archetype]
	_roll = 0.0
	_catch(npc.id, 1)
	check(_handler.is_window_open() and _last_window("opened")[1] == npc.id,
			"%s caught you: the decision window opens" % archetype)
	var before: float = _suspicion()
	_timeout()
	check_eq(_last_window("closed").slice(1), [npc.id, "inaction"],
			"%s: the deadline passes without a choice" % archetype)
	var decided: Array[Array] = _decided(npc.id)
	check(decided.size() == 1 and decided[0][1] == expected[0],
			"%s acts on its own: %s" % [archetype, expected[0]])
	var reports: Array[Array] = _log.all("npc_reported_player")
	if str(expected[1]).is_empty():
		check(reports.is_empty(), "%s does not report you" % archetype)
	else:
		check_eq(reports, [[npc.id, expected[1], expected[2], _room]],
				"%s reports to %s" % [archetype, expected[1]])
	check_near(_suspicion() - before, expected[2], SUSPICION_EPS,
			"%s: suspicion +%d (reporter of default credibility)" % [archetype, int(expected[2])])
	if not decided.is_empty():
		_check_reaction_extras(archetype, npc, decided[0][2])


func _check_reaction_extras(archetype: String, npc: NPCRuntime, context: Dictionary) -> void:
	match archetype:
		"company_man", "rookie":
			check(bool(context["file_annotation"]) and _has_file_annotation(),
					"%s: the report leaves an annotation in your file" % archetype)
		"gossip":
			var pending: Array[Dictionary] = _handler.get_pending_gossip()
			check(bool(context["amplified"]) and float(context["amplification"]) > 1.0
					and pending.size() == 1 and pending[0]["npc_id"] == npc.id,
					"gossip: marked for amplified spreading at lunch")
			check_eq(str(context["belief_id"]), _caught_belief_id(npc.id),
					"gossip: the marked belief is the flagrancy belief")
		"coward":
			var entry: Dictionary = Fixtures.material_of_kind(npc, Blackmail.KIND_WITNESSED)
			check(not entry.is_empty() and bool(entry["will_demand"]),
					"coward: keeps it quiet as blackmail material for later")
			check(int(entry.get("demand_day", 0)) > GameClock.get_day(),
					"coward: the demand comes later, not now")
		"climber":
			var leverage: Dictionary = Fixtures.material_of_kind(npc, Blackmail.KIND_LEVERAGE)
			check_eq(leverage.get("demand_type", ""), Blackmail.DEMAND_PROMOTION,
					"climber: keeps it as leverage for a promotion")
		"bribable":
			_check_bribable_asks(npc)
		"burnout", "oblivious", "old_hand":
			check(not Blackmail.has_material(npc), "%s: no blackmail material" % archetype)


func _check_bribable_asks(npc: NPCRuntime) -> void:
	check_eq(_log.last("blackmail_demanded"),
			[npc.id, Blackmail.DEMAND_MONEY, Bribery.npc_daily_wage(npc) * 20],
			"bribable: asks for money on the spot (wage × 20)")
	check(_log.last("subtitle_posted").slice(0, 1) == ["BLACKMAIL_FACE_MONEY"]
			and _log.count("phone_message_received") == 0,
			"bribable: the demand is face to face, not a phone chat")


func _has_file_annotation() -> bool:
	for record: Belief in BeliefNet.get_records_about("player"):
		if record.fact == "stamped_document:file_annotation" and BeliefNet.is_record_neutral(record.id):
			return true
	return false


func _caught_belief_id(holder: String) -> String:
	for belief: Belief in BeliefNet.get_beliefs_held_by(holder):
		if belief.fact == "caught_redhanded:" + CRIME:
			return belief.id
	return ""


func _check_indifference_is_a_chance() -> void:
	var chance: float = Database.get_balance_float("flagrancia.prob_indiferencia")
	check(chance >= 0.5 and chance < 1.0, "burnout/oblivious: significant (not certain) indifference")
	_roll = 0.99
	for archetype: String in ["burnout", "oblivious"]:
		var npc: NPCRuntime = _npc(archetype)
		_catch(npc.id, 1)
		_timeout()
		var decided: Array[Array] = _decided(npc.id)
		check(decided.size() == 1 and decided[0][1] == "remember"
				and _log.count("npc_reported_player") == 0,
				"%s not indifferent: remembers quietly, still no report" % archetype)
	_roll = 0.0


## §7.2: la subida es +20 con la credibilidad por defecto; un denunciante real la escala.
func _check_real_reporter_credibility() -> void:
	_fresh_beliefs()
	var george: String = "npc_george_penn"
	_catch(george, 1)
	var before: float = _suspicion()
	_timeout()
	check_eq(_log.last("npc_reported_player"), [george, "security", 20.0, _room],
			"George Penn (snitch) goes to Security with the +20 report")
	var scale: float = BeliefNet.get_credibility(george) / BeliefNet.get_default_credibility()
	check_near(_suspicion() - before, 20.0 * scale, SUSPICION_EPS,
			"…and BeliefNet weighs it by his credibility (+%.1f)" % (20.0 * scale))


## §7.10: con reputación alta el testigo duda más antes de actuar (el plazo se alarga).
func _check_deadline_and_reputation() -> void:
	var base: float = Database.get_balance_float("flagrancia.plazo_decision_segundos")
	var extra: float = Database.get_balance_float("flagrancia.plazo_extra_por_reputacion")
	check_near(CaughtHandler.decision_seconds(0.0), base, EPS, "reputation 0: the balance deadline")
	check_near(CaughtHandler.decision_seconds(100.0), base * (1.0 + extra), EPS,
			"reputation 100: the longest deadline")
	PlayerState.modify_reputation(60.0, "test")
	var options: Dictionary = _catch("test_hardliner", 1)
	check_near(float(options["deadline"]), base * (1.0 + extra * 0.6), EPS,
			"reputation 60 lengthens the window (%.1f s)" % float(options["deadline"]))
	_handler.advance_timer(base + 0.1)
	check(_handler.is_window_open(), "the hesitant witness has not acted yet at the base deadline")
	_handler.resolve_inaction(0.0)
	PlayerState.modify_reputation(-60.0, "test")


## §7.7: la deuda suprime la denuncia (registro o arista de deuda) y se consume al callar.
func _check_debt_silences() -> void:
	var debtor: NPCRuntime = Fixtures.synthetic("test_debtor", "hardliner")
	debtor.ledger["debt"] = 25
	_npcs[debtor.id] = debtor
	_catch(debtor.id, 1)
	_timeout()
	var decided: Array[Array] = _decided(debtor.id)
	check(_log.count("npc_reported_player") == 0 and decided.size() == 1
			and decided[0][1] == "stay_silent" and decided[0][2]["reaction"] == "silenced_by_debt",
			"a hardliner who owes you stays silent")
	check_eq(int(debtor.ledger["debt"]), 25 - Database.get_balance_int(
			"registro.deuda_consumida_por_silencio"), "keeping quiet consumes part of the debt")
	var george: String = "npc_george_penn"
	SocialGraph.add_link(george, "player", "debt", 0.5)
	check(NPCDirector.is_report_suppressed(george), "a debt link towards the player suppresses")
	_catch(george, 1)
	_timeout()
	check(_log.count("npc_reported_player") == 0 and _decided(george).size() == 1
			and _decided(george)[0][2]["reaction"] == "silenced_by_debt",
			"George Penn, in debt to you through the graph, does not go to Security")
	SocialGraph.remove_link(george, "player")


func _check_witnesses_block_elimination() -> void:
	_fresh_beliefs()
	var options: Dictionary = _catch("test_snitch", 2)
	check(_handler.is_window_open() and _last_window("opened")[1] == "test_snitch",
			"player_caught_redhanded opens the decision window")
	check(options.has("bribe") and options.has("eliminate"), "the window offers two options")
	check(_handler.is_time_slowed() and is_equal_approx(GameClock.get_speed_multiplier(),
			Database.get_balance_float("flagrancia.multiplicador_tiempo")),
			"time is slowed (GameClock speed multiplier) while the window is open")
	var eliminate: Dictionary = options["eliminate"]
	check(not bool(eliminate["enabled"]) and bool(eliminate["flagged_red"]),
			"with witnesses, elimination is disabled and flagged red")
	check_eq(eliminate["disabled_reason_key"], "UI_CAUGHT_ELIMINATE_WITNESSES",
			"the disabled option explains why")
	var suspicion: float = PlayerState.get_suspicion()
	var mod: float = Database.get_balance_float("sobornos.mod_precio_por_sospecha")
	check(suspicion > 0.0, "being caught already raised suspicion (%.1f)" % suspicion)
	check_eq(options["bribe"]["price"], roundi(600.0 * (1.0 + mod * suspicion / 100.0)),
			"the on-the-spot price is wage × 20 (30 × 20), dearer with suspicion (§7.10)")
	var attempt: Dictionary = _handler.choose_elimination()
	check(not bool(attempt["ok"]) and _log.count("crime_committed") == 0,
			"logic refuses elimination with witnesses: nothing happens")
	check(_handler.is_window_open(), "the window stays open after the refused elimination")
	check_eq(str(_handler.get_options().get("npc_id", "")), "test_snitch", "same window")
	_handler.resolve_inaction(0.0)
	check(not _handler.is_time_slowed() and is_equal_approx(GameClock.get_speed_multiplier(), 1.0),
			"time runs at its previous pace again")


func _check_elimination_without_witnesses() -> void:
	var victim: String = "npc_nate_brackley"
	var options: Dictionary = _catch(victim, 0)
	check(bool(options["eliminate"]["enabled"]) and not bool(options["eliminate"]["flagged_red"]),
			"with no witnesses, elimination is available")
	var result: Dictionary = _handler.choose_elimination()
	check(bool(result["ok"]), "elimination is carried out")
	var crime: Array = _log.last("crime_committed")
	check(not crime.is_empty() and crime[0] == "elimination" and crime[2]["npc_id"] == victim,
			"crime_committed('elimination') is emitted (Tracking: blood)")
	check_eq(_last_window("closed").slice(1), [victim, "eliminated"],
			"the window closes with the elimination")
	check(not NPCDirector.is_alive(victim) and not NPCDirector.get_body_info(victim).is_empty(),
			"NPCDirector removed the victim and created the body")


## Con los ids de Perception solo cuentan los testigos que siguen vivos.
func _check_witness_ids() -> void:
	var witness: NPCRuntime = Fixtures.synthetic("test_witness", "oblivious")
	_npcs[witness.id] = witness
	_catch("test_old_hand", 1)
	var ids: Array[String] = [witness.id]
	_handler.set_witness_ids("test_old_hand", ids)
	check(not bool(_handler.get_options()["eliminate"]["enabled"]), "a living witness blocks it")
	witness.alive = false
	check(bool(_handler.get_options()["eliminate"]["enabled"])
			and int(_handler.get_options()["witnesses"]) == 0,
			"once the only witness is gone, elimination becomes available")
	_handler.resolve_inaction(0.0)


func _check_insufficient_capital() -> void:
	_wallet.money = 100
	var options: Dictionary = _catch("test_coward", 1)
	check(not bool(options["bribe"]["enabled"]), "insufficient capital: the bribe is disabled")
	check_eq(options["bribe"]["disabled_reason_key"], "UI_CAUGHT_BRIBE_NO_FUNDS",
			"the disabled bribe explains why")
	var result: Dictionary = _handler.choose_bribe()
	check(not bool(result["ok"]) and result["outcome"] == Bribery.OUTCOME_NO_FUNDS,
			"a disabled bribe cannot be chosen")
	check(_wallet.money == 100 and _log.count("npc_decided") == 0 and _handler.is_window_open(),
			"nothing happens and the window stays open")
	_handler.resolve_inaction(0.0)
	_wallet.money = 5000


## Regresión: el soborno inmediato no admite menos del precio ×20 (ni 1 €).
func _check_below_price() -> void:
	_catch("test_gossip", 1)
	var result: Dictionary = _handler.choose_bribe(1)
	check(not bool(result["ok"]) and result["reason"] == CaughtHandler.REASON_BELOW_PRICE
			and _log.count("bribe_offered") == 0 and _handler.is_window_open(),
			"a 1 € envelope is refused before it is offered; the window stays open")
	_handler.reset_for_new_run()


func _check_accepted_bribe_keeps_belief() -> void:
	_fresh_beliefs()
	var frank: String = "npc_frank_rudd"
	var price: int = int(_catch(frank, 1)["bribe"]["price"])
	var belief: Belief = BeliefNet.get_belief(_caught_belief_id(frank))
	check(belief != null and is_equal_approx(belief.certainty,
			Database.get_balance_float("creencias.certeza_directa_completa")),
			"flagrancy: Frank Rudd holds the full-certainty caught_redhanded belief")
	var certainty_before: float = belief.certainty if belief != null else -1.0
	var money: int = _wallet.money
	var result: Dictionary = _handler.choose_bribe(-1, {"roll": 0.0})
	check_eq(result["outcome"], Bribery.OUTCOME_ACCEPTED, "Frank Rudd accepts the envelope")
	check_eq(_wallet.money, money - price, "the on-the-spot price was paid (%d)" % price)
	check_eq(_log.count_for("npc_reported_player", frank), 0, "accepted: he does NOT report")
	var after: Belief = BeliefNet.get_belief(_caught_belief_id(frank))
	check(after != null and is_equal_approx(after.certainty, certainty_before),
			"accepted: the belief is kept whole (buying silence is not buying oblivion)")
	check(not Fixtures.material_of_kind(NPCDirector.get_npc(frank),
			Blackmail.KIND_BRIBED_SILENCE).is_empty(), "accepted: he gains blackmail material")
	check_eq(_last_window("closed").slice(1), [frank, Bribery.OUTCOME_ACCEPTED],
			"the window closes with the accepted bribe")


func _check_bribe_refusals() -> void:
	_catch("test_hardliner", 1)
	var denounced: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(denounced["outcome"], Bribery.OUTCOME_DENOUNCED, "the hardliner refuses and reports")
	check_eq(_log.last("game_over").slice(0, 1), ["bribe_denounced"],
			"refused with report → immediate expulsion (game over)")
	check_eq(_last_window("closed").slice(1), ["test_hardliner", Bribery.OUTCOME_DENOUNCED],
			"the window closes on the game over")
	_catch("test_coward", 1)
	check(not _handler.is_window_open(), "after the game over no new window opens")
	_handler.reset_for_new_run()
	_catch("test_coward", 1)
	var silent: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(silent["outcome"], Bribery.OUTCOME_SILENCE, "the coward refuses silently")
	var memory: Dictionary = Fixtures.find_belief(silent, "test_coward", Bribery.FACT_REMEMBERED)
	check_near(float(memory.get("certainty", 0.0)), 0.9, EPS, "silent refusal: belief 0.9")
	check(not Fixtures.material_of_kind(_npcs["test_coward"],
			Blackmail.KIND_SILENCE_MEMORY).is_empty(), "silent refusal: future blackmail")
	check_eq(_log.count("npc_reported_player"), 0, "silent refusal: no report")


## Regresión: un rechazo neutro no compra nada: el testigo reacciona según su arquetipo.
func _check_neutral_refusal_reacts() -> void:
	_catch("test_rookie", 2)
	var result: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(result["outcome"], Bribery.OUTCOME_NEUTRAL, "the rookie refuses, neither loud nor silent")
	check_eq(_log.last("npc_reported_player"), ["test_rookie", "superior", 10.0, _room],
			"…and still reports to the superior (+10)")
	check(not _handler.is_window_open() and result["reaction"]["action"] == "report_to_superior",
			"the window closes with the archetype reaction")
	_catch("test_gossip", 1)
	_handler.choose_bribe(-1, {"roll": 0.99})
	check(_handler.get_pending_gossip().any(
			func(e: Dictionary) -> bool: return e["npc_id"] == "test_gossip"),
			"a refused gossip still spreads it at lunch")
	_handler.reset_for_new_run()


func _check_counteroffer_window() -> void:
	var options: Dictionary = _catch("test_bribable", 1)
	var original: int = int(options["bribe"]["price"])
	_handler.advance_timer(float(options["deadline"]) - 1.0)
	var first: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99, "counter_roll": 0.5})
	check_eq(first["outcome"], Bribery.OUTCOME_COUNTEROFFER, "the bribable asks for more")
	check(_handler.is_window_open(), "counteroffer: the window stays open")
	var updated: Array = _last_window("updated")
	check(not updated.is_empty() and updated[1] == "test_bribable", "the UI is told the new price")
	var now: Dictionary = _handler.get_options()
	check_near(float(now["seconds_left"]),
			Database.get_balance_float("flagrancia.plazo_minimo_contraoferta_segundos"), EPS,
			"the deadline is NOT restarted (only a short minimum to answer)")
	check_eq(now["bribe"]["price"], roundi(original * 1.55),
			"new price between 1.3 and 1.8 × the original (× 1.55)")
	check(bool(now["bribe"]["counteroffer"]), "the option is marked as a counteroffer")
	check(not Fixtures.find_belief(first, "test_bribable", Bribery.FACT_COUNTERED).is_empty(),
			"haggling in the flagrancy has a cost (belief)")
	var cheaper: Dictionary = _handler.choose_bribe(int(now["bribe"]["price"]) - 1)
	check(not bool(cheaper["ok"]) and _handler.is_window_open(),
			"less than the asked price is not even offered")
	var money: int = _wallet.money
	var second: Dictionary = _handler.choose_bribe()
	check_eq(second["outcome"], Bribery.OUTCOME_ACCEPTED, "paying the asked price is accepted")
	check_eq(_wallet.money, money - int(now["bribe"]["price"]), "the counteroffer price was paid")


## §12.2 cotilla: propagación amplificada en la comida, por la vía de la señal de franja.
func _check_gossip_at_lunch() -> void:
	_handler.reset_for_new_run()
	_fresh_beliefs()
	var gossips: Array[NPCRuntime] = _gossips_with_links()
	check(gossips.size() >= 3, "the population has gossips with social links")
	var band: String = CaughtHandler.gossip_band()
	check(GameClock.get_current_band() != band, "the flagrancy happens before lunch")
	var debbie: NPCRuntime = gossips[0]
	_catch(debbie.id, 1)
	_timeout()
	var belief: Belief = BeliefNet.get_belief(_caught_belief_id(debbie.id))
	check(_handler.get_pending_gossip().size() == 1 and belief != null,
			"%s will tell it at lunch" % debbie.name)
	check_eq(_holders_among(debbie.id, belief).size(), 0, "before lunch nobody else knows")
	var saved: Variant = JSON.parse_string(JSON.stringify(_handler.save_state()))
	_handler.reset_for_new_run()
	_handler.load_state(saved)
	check_eq(_handler.get_pending_gossip().size(), 1, "the pending gossip survives save/load")
	var before: float = _suspicion()
	EventBus.time_band_changed.emit("work_morning", band)
	var expected: Dictionary = _expected_spread(debbie.id, belief)
	var told: Array[String] = _holders_among(debbie.id, belief)
	check(expected.size() > 0 and told.size() == expected.size(),
			"at lunch the gossip tells every linked colleague (%d)" % told.size())
	check(_all_at_least(told, belief, expected),
			"with amplified certainty (link factor × amplification)")
	check(_handler.get_pending_gossip().is_empty() and _suspicion() > before,
			"the spread raises suspicion and clears the mark")
	var spread_event: Array = _decided(debbie.id).back() if not _decided(debbie.id).is_empty() else []
	check(not spread_event.is_empty() and spread_event[2].get("spread_to", []).size() == told.size(),
			"npc_decided(gossip) lists who heard it")
	_check_exact_spread(gossips[1])


## Llamada directa (sin el corrillo de la comida): certezas exactas.
func _check_exact_spread(gossip: NPCRuntime) -> void:
	_fresh_beliefs()
	_catch(gossip.id, 1)
	_timeout()
	var belief: Belief = BeliefNet.get_belief(_caught_belief_id(gossip.id))
	var expected: Dictionary = _expected_spread(gossip.id, belief)
	check_eq(_handler.process_gossip(), expected.size(), "process_gossip reaches every link")
	var exact: bool = true
	for neighbour: String in expected:
		exact = exact and is_equal_approx(_certainty_of(neighbour, belief), float(expected[neighbour]))
	check(exact and not expected.is_empty(),
			"certainty = source × min(link factor × %.2f, amplification max)"
			% Database.get_balance_float("flagrancia.amplificacion_cotilla"))


func _check_gossip_cancelled() -> void:
	var gossip: NPCRuntime = _gossips_with_links()[2]
	_catch(gossip.id, 1)
	_timeout()
	EventBus.bribe_result.emit(gossip.id, true, Bribery.OUTCOME_ACCEPTED)
	check(_handler.get_pending_gossip().is_empty(), "a gossip bought afterwards keeps quiet")
	_catch(gossip.id, 1)
	_timeout()
	NPCDirector.remove_npc(gossip.id, "expelled")
	check(_handler.get_pending_gossip().is_empty(), "an expelled gossip tells nobody at lunch")


func _all_at_least(holders: Array[String], belief: Belief, expected: Dictionary) -> bool:
	for holder: String in holders:
		if _certainty_of(holder, belief) + EPS < float(expected.get(holder, 2.0)):
			return false
	return true


func _gossips_with_links() -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_npcs_by_archetype("gossip"):
		if SocialGraph.get_neighbours(npc.id, 0.0).size() > 0:
			out.append(npc)
	return out


func _expected_spread(npc_id: String, belief: Belief) -> Dictionary:
	var out: Dictionary = {}
	var boost: float = Database.get_balance_float("flagrancia.amplificacion_cotilla")
	var cap: float = Database.get_balance_float("creencias.amplificacion_rumor_max")
	for neighbour: String in SocialGraph.get_neighbours(npc_id, 0.0):
		var factor: float = SocialGraph.get_transfer_factor(npc_id, neighbour, belief.fact,
				belief.subject)
		var certainty: float = minf(belief.certainty * clampf(factor * boost, 0.0, cap), 1.0)
		if factor > 0.0 and certainty >= Database.get_balance_float("creencias.umbral_olvido"):
			out[neighbour] = certainty
	return out


func _holders_among(npc_id: String, belief: Belief) -> Array[String]:
	var out: Array[String] = []
	for neighbour: String in SocialGraph.get_neighbours(npc_id, 0.0):
		if _certainty_of(neighbour, belief) > 0.0:
			out.append(neighbour)
	return out


func _certainty_of(holder: String, belief: Belief) -> float:
	for held: Belief in BeliefNet.get_beliefs_held_by(holder):
		if held.fact == belief.fact and held.subject == belief.subject:
			return held.certainty
	return 0.0


func _check_queue() -> void:
	_catch("test_old_hand", 1)
	EventBus.player_caught_redhanded.emit("test_climber", CRIME, 1)
	EventBus.player_caught_redhanded.emit("test_climber", CRIME, 1)
	check_eq(_handler.get_queue_size(), 1, "a second catch waits in the queue (once)")
	_handler.resolve_inaction(0.0)
	check(_handler.is_window_open() and _last_window("opened")[1] == "test_climber",
			"the queued catch opens when the first window closes")
	var reaction: Dictionary = _handler.resolve_inaction(0.0)
	check_eq(reaction.get("action", ""), "keep_leverage", "the climber keeps it as leverage")
	check(not _handler.is_window_open(), "no window left")


func _check_removed_catcher() -> void:
	_catch("test_old_hand", 1)
	EventBus.player_caught_redhanded.emit("test_rookie", CRIME, 1)
	EventBus.npc_removed.emit("test_rookie", "expelled")
	check_eq(_handler.get_queue_size(), 0, "a removed NPC leaves the queue")
	EventBus.npc_removed.emit("test_old_hand", "expelled")
	check(not _handler.is_window_open() and _last_window("closed")[2] == "void"
			and _decided("test_old_hand").is_empty(),
			"a catcher removed mid-window takes the flagrancy with them (no reaction)")
	var ghost: NPCRuntime = Fixtures.synthetic("test_ghost", "hardliner")
	_npcs[ghost.id] = ghost
	_catch(ghost.id, 1)
	ghost.alive = false
	_timeout()
	check(_log.count("npc_reported_player") == 0 and _last_window("closed")[2] == "void",
			"a dead catcher does not report when the deadline passes")


func _check_game_over_closes() -> void:
	_catch("test_old_hand", 1)
	EventBus.player_caught_redhanded.emit("test_climber", CRIME, 1)
	EventBus.game_over.emit("test_cause", "", {})
	check(not _handler.is_window_open() and _last_window("closed")[2] == "game_over"
			and _handler.get_queue_size() == 0 and _decided("test_old_hand").is_empty(),
			"another system's game over closes the window without a reaction")
	check(not _handler.is_time_slowed(), "…and gives the clock back")
	_handler.reset_for_new_run()


func _check_time_restore() -> void:
	GameClock.set_speed_multiplier(0.4)
	_catch("test_old_hand", 1)
	_handler.resolve_inaction(0.0)
	check(is_equal_approx(GameClock.get_speed_multiplier(), 0.4),
			"closing the window restores the previous pace (0.4 in the computer)")
	_catch("test_old_hand", 1)
	GameClock.set_speed_multiplier(1.0)
	_handler.reset_for_new_run()
	check(is_equal_approx(GameClock.get_speed_multiplier(), 1.0),
			"a new run does not overwrite the freshly reset clock with a stale pace")
	GameClock.set_speed_multiplier(1.0)


func _check_save_load() -> void:
	_catch("test_rookie", 1)
	_handler.advance_timer(1.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(_handler.save_state()))
	_handler.reset_for_new_run()
	check(not _handler.is_window_open(), "reset_for_new_run closes the window")
	_handler.load_state(saved)
	var options: Dictionary = _handler.get_options()
	check(_handler.is_window_open() and options.get("npc_id", "") == "test_rookie",
			"load_state restores the open window")
	check_near(float(options.get("seconds_left", 0.0)),
			float(options.get("deadline", 0.0)) - 1.0, EPS, "load_state restores the remaining time")
	check(_handler.is_time_slowed(), "the restored window slows the clock again")
	_log.clear()
	_handler.resolve_inaction(0.0)
	check_eq(_log.last("npc_reported_player"), ["test_rookie", "superior", 10.0, _room],
			"the restored window resolves normally at the crime scene (rookie → superior +10)")
	_handler.load_state({"window": null, "queue": null, "pending_gossip": "broken"})
	check(not _handler.is_window_open() and _handler.get_queue_size() == 0,
			"a damaged save loads as an empty state instead of crashing")


## §7.5/§7.9: rango del jugador, temor y afecto hacen dudar al testigo; la valentía lo atenúa.
func _check_hesitation() -> void:
	var snitch: NPCRuntime = _npc("snitch")
	var hardliner: NPCRuntime = _npc("hardliner")
	check_eq(CaughtHandler.hesitation_chance(snitch), 0.0,
			"first-rank player, clean ledger: the snitch never hesitates")
	var brave: float = 1.0 - snitch.get_trait("courage") / 100.0
	snitch.ledger["fear"] = 100
	check_near(CaughtHandler.hesitation_chance(snitch),
			Database.get_balance_float("flagrancia.duda_por_temor") * brave, EPS,
			"a frightened snitch may keep quiet (fear term × (1 − courage))")
	snitch.ledger["fear"] = 0
	PlayerState.set_occupation("ceo", "test")
	var doubt: float = Database.get_balance_float("flagrancia.duda_por_rango")
	check_near(CaughtHandler.hesitation_chance(snitch), doubt * brave, EPS,
			"facing the CEO the snitch hesitates (rank term)")
	check(CaughtHandler.hesitation_chance(hardliner) < 0.1,
			"the hardliner reports without hesitation (courage 90)")
	_roll = doubt * brave * 0.5
	_catch(snitch.id, 1)
	_timeout()
	check(_log.count("npc_reported_player") == 0 and _decided(snitch.id)[0][2]["reaction"]
			== "hesitated", "the snitch caught the CEO and, this time, kept quiet")
	_catch(hardliner.id, 1)
	_timeout()
	check_eq(_log.count("npc_reported_player"), 1, "the hardliner reports the CEO anyway")
	_roll = 0.0
