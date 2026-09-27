# caught_case.gd — Cuerpo de test_caught: flagrancia (§12.2) con los doce arquetipos y la ventana de decisión.
# PROPIETARIO DE: nada.
# ESCUCHA: npc_reported_player, npc_decided, crime_committed, game_over, blackmail_demanded (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const CRIME := "drawer_forced"
const ROOM := "wing_3b"
const EPS := 0.000001
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
		"game_over", "blackmail_demanded"]

var _log: Fixtures.SignalLog = null
var _npcs: Dictionary = {}
var _handler: CaughtHandler = null
var _wallet: Fixtures.FakeWallet = null
var _window_log: Array[Array] = []


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_check_archetype_count()
	for archetype: String in EXPECTED:
		_check_inaction(archetype)
	_check_indifference_is_a_chance()
	_setup_handler()
	_check_witnesses_block_elimination()
	_check_elimination_without_witnesses()
	_check_insufficient_capital()
	_check_accepted_bribe_keeps_belief()
	_check_bribe_refusals()
	_check_counteroffer_window()
	_check_queue()
	_check_save_load()
	_log.stop()
	await get_tree().process_frame


func _npc(archetype: String) -> NPCRuntime:
	var npc_id: String = "test_" + archetype
	if not _npcs.has(npc_id):
		_npcs[npc_id] = Fixtures.synthetic(npc_id, archetype)
	return _npcs[npc_id]


func _check_archetype_count() -> void:
	check_eq(Database.get_all_archetypes().size(), 12, "the twelve archetypes are loaded")
	for archetype: ArchetypeData in Database.get_all_archetypes():
		check(EXPECTED.has(archetype.id), "archetype %s has a documented reaction" % archetype.id)


func _check_inaction(archetype: String) -> void:
	var npc: NPCRuntime = Fixtures.synthetic("inaction_" + archetype, archetype)
	var expected: Array = EXPECTED[archetype]
	_log.clear()
	var out: Dictionary = CaughtHandler.apply_caught_reaction(npc, CRIME, ROOM, 0.0)
	check_eq(out["action"], expected[0], "%s caught you: %s" % [archetype, expected[0]])
	check_eq(_log.count_for("npc_decided", npc.id), 1, "%s: the decision is published" % archetype)
	var reports: Array[Array] = _log.all("npc_reported_player")
	if str(expected[1]).is_empty():
		check(reports.is_empty(), "%s does not report you" % archetype)
	else:
		check_eq(reports, [[npc.id, expected[1], expected[2], ROOM]],
				"%s reports to %s: suspicion +%d" % [archetype, expected[1], int(expected[2])])
	_check_reaction_extras(archetype, npc, out)


func _check_reaction_extras(archetype: String, npc: NPCRuntime, out: Dictionary) -> void:
	match archetype:
		"company_man", "rookie":
			check(bool(out["file_annotation"]), "%s: the report goes to your file" % archetype)
		"gossip":
			check(bool(out["amplified"]) and float(out["amplification"]) > 1.0,
					"gossip: spreads it at lunch with amplified propagation")
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
			check_eq(_log.last("blackmail_demanded"),
					[npc.id, Blackmail.DEMAND_MONEY, Bribery.npc_daily_wage(npc) * 20],
					"bribable: asks for money on the spot (wage × 20)")
		"burnout", "oblivious", "old_hand":
			check(not Blackmail.has_material(npc), "%s: no blackmail material" % archetype)


func _check_indifference_is_a_chance() -> void:
	var chance: float = Database.get_balance_float("flagrancia.prob_indiferencia")
	check(chance >= 0.5 and chance < 1.0, "burnout/oblivious: significant (not certain) indifference")
	for archetype: String in ["burnout", "oblivious"]:
		var npc: NPCRuntime = Fixtures.synthetic("chance_" + archetype, archetype)
		_log.clear()
		var out: Dictionary = CaughtHandler.apply_caught_reaction(npc, CRIME, ROOM, 0.99)
		check(out["action"] == "remember" and _log.count("npc_reported_player") == 0,
				"%s not indifferent: remembers quietly, still no report" % archetype)


func _setup_handler() -> void:
	_handler = CaughtHandler.new()
	_handler.npc_resolver = func(npc_id: String) -> NPCRuntime: return _npcs.get(npc_id)
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
	_npcs["npc_frank_rudd"] = Fixtures.named("npc_frank_rudd")


func _last_window(kind: String) -> Array:
	for i: int in range(_window_log.size() - 1, -1, -1):
		if _window_log[i][0] == kind:
			return _window_log[i]
	return []


func _catch(npc_id: String, witnesses: int) -> Dictionary:
	_log.clear()
	EventBus.player_caught_redhanded.emit(npc_id, CRIME, witnesses)
	return _handler.get_options()


func _check_witnesses_block_elimination() -> void:
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
	check_eq(options["bribe"]["price"], 600, "the on-the-spot price is wage × 20 (30 × 20)")
	var attempt: Dictionary = _handler.choose_elimination()
	check(not bool(attempt["ok"]) and _log.count("crime_committed") == 0,
			"logic refuses elimination with witnesses: nothing happens")
	check(_handler.is_window_open(), "the window stays open after the refused elimination")
	var deadline: float = Database.get_balance_float("flagrancia.plazo_decision_segundos")
	_handler.advance_timer(deadline - 0.5)
	check(_handler.is_window_open(), "before the deadline the NPC waits")
	_handler.advance_timer(1.0)
	check(not _handler.is_window_open() and _last_window("closed")[2] == "inaction",
			"after the deadline the NPC acts on its own")
	check_eq(_log.last("npc_reported_player"), ["test_snitch", "security", 20.0, ROOM],
			"the snitch goes to Security (+20)")
	check(not _handler.is_time_slowed() and is_equal_approx(GameClock.get_speed_multiplier(), 1.0),
			"time runs at its previous pace again")


## Con NPCDirector ya poblado se elimina a un personaje real (crea el cuerpo); si no, a uno sintético.
func _check_elimination_without_witnesses() -> void:
	var victim: String = "npc_nate_brackley" if NPCDirector.get_npc("npc_nate_brackley") != null \
			else "test_burnout"
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
	if victim != "test_burnout":
		check(not NPCDirector.is_alive(victim), "NPCDirector removed the victim (body created)")


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


func _check_accepted_bribe_keeps_belief() -> void:
	var frank: NPCRuntime = _npcs["npc_frank_rudd"]
	_catch(frank.id, 1)
	var beliefs_before: int = BeliefNet.get_beliefs_held_by(frank.id).size()
	var certainty_before: float = _max_certainty(frank.id)
	var result: Dictionary = _handler.choose_bribe(-1, {"roll": 0.0})
	check_eq(result["outcome"], Bribery.OUTCOME_ACCEPTED, "Frank Rudd accepts the envelope")
	check_eq(_wallet.money, 5000 - 1120, "the on-the-spot price was paid (56 × 20 = 1120)")
	check_eq(_log.count_for("npc_reported_player", frank.id), 0, "accepted: he does NOT report")
	check_eq(BeliefNet.get_beliefs_held_by(frank.id).size(), beliefs_before,
			"accepted: the belief is kept, not erased")
	check_near(_max_certainty(frank.id), certainty_before, EPS, "accepted: the belief stays whole")
	check(not Fixtures.material_of_kind(frank, Blackmail.KIND_BRIBED_SILENCE).is_empty(),
			"accepted: he gains blackmail material (buying silence is not buying oblivion)")
	check_eq(_last_window("closed").slice(1), [frank.id, Bribery.OUTCOME_ACCEPTED],
			"the window closes with the accepted bribe")


func _max_certainty(holder: String) -> float:
	var best: float = 0.0
	for belief: Belief in BeliefNet.get_beliefs_held_by(holder):
		best = maxf(best, belief.certainty)
	return best


func _check_bribe_refusals() -> void:
	_catch("test_hardliner", 1)
	var denounced: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(denounced["outcome"], Bribery.OUTCOME_DENOUNCED, "the hardliner refuses and reports")
	check_eq(_log.last("game_over").slice(0, 1), ["bribe_denounced"],
			"refused with report → immediate expulsion (game over)")
	check(not _handler.is_window_open(), "the window closes on the game over")
	_catch("test_coward", 1)
	var silent: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(silent["outcome"], Bribery.OUTCOME_SILENCE, "the coward refuses silently")
	var memory: Dictionary = Fixtures.find_belief(silent, "test_coward", Bribery.FACT_REMEMBERED)
	check_near(float(memory.get("certainty", 0.0)), 0.9, EPS, "silent refusal: belief 0.9")
	check(not Fixtures.material_of_kind(_npcs["test_coward"],
			Blackmail.KIND_SILENCE_MEMORY).is_empty(), "silent refusal: future blackmail")
	check_eq(_log.count("npc_reported_player"), 0, "silent refusal: no report")


func _check_counteroffer_window() -> void:
	_catch("test_bribable", 1)
	var first: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99, "counter_roll": 0.5})
	check_eq(first["outcome"], Bribery.OUTCOME_COUNTEROFFER, "the bribable asks for more")
	check(_handler.is_window_open(), "counteroffer: the window stays open")
	var updated: Array = _last_window("updated")
	check(not updated.is_empty() and updated[1] == "test_bribable", "the UI is told the new price")
	var bribe: Dictionary = _handler.get_options()["bribe"]
	check_eq(bribe["price"], 930, "new price between 1.3 and 1.8 × the original (600 × 1.55)")
	check(bool(bribe["counteroffer"]), "the option is marked as a counteroffer")
	var money: int = _wallet.money
	var second: Dictionary = _handler.choose_bribe(-1, {"roll": 0.99})
	check_eq(second["outcome"], Bribery.OUTCOME_ACCEPTED, "paying the asked price is accepted")
	check_eq(_wallet.money, money - 930, "the counteroffer price was paid")


func _check_queue() -> void:
	_catch("test_old_hand", 1)
	EventBus.player_caught_redhanded.emit("test_gossip", CRIME, 1)
	EventBus.player_caught_redhanded.emit("test_gossip", CRIME, 1)
	check_eq(_handler.get_queue_size(), 1, "a second catch waits in the queue (once)")
	_handler.resolve_inaction(0.0)
	check(_handler.is_window_open() and _last_window("opened")[1] == "test_gossip",
			"the queued catch opens when the first window closes")
	var reaction: Dictionary = _handler.resolve_inaction(0.0)
	check_eq(reaction.get("action", ""), "gossip", "the gossip spreads it at lunch")
	check(not _handler.is_window_open(), "no window left")


func _check_save_load() -> void:
	_catch("test_rookie", 1)
	_handler.advance_timer(1.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(_handler.save_state()))
	_handler.reset_for_new_run()
	check(not _handler.is_window_open(), "reset_for_new_run closes the window")
	_handler.load_state(saved)
	check(_handler.is_window_open() and _handler.get_options()["npc_id"] == "test_rookie",
			"load_state restores the open window")
	var left: float = Database.get_balance_float("flagrancia.plazo_decision_segundos") - 1.0
	check_near(float(_handler.get_options()["seconds_left"]), left, EPS,
			"load_state restores the remaining time")
	_log.clear()
	_handler.resolve_inaction(0.0)
	check_eq(_log.last("npc_reported_player").slice(0, 3), ["test_rookie", "superior", 10.0],
			"the restored window resolves normally (rookie → superior +10)")
