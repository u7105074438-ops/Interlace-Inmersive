# blackmail_case.gd — Cuerpo de test_blackmail: material de chantaje, exigencias posteriores, pagar y negarse.
# PROPIETARIO DE: nada.
# ESCUCHA: blackmail_demanded, blackmail_initiated, phone_message_received, npc_reported_player (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const CRIME := "theft_small"
const DAY := 1
const WATCHED: Array[String] = ["blackmail_demanded", "blackmail_initiated",
		"phone_message_received", "npc_reported_player"]

var _log: Fixtures.SignalLog = null


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_check_coward_demands_later()
	_check_money_demand_cycle()
	_check_refusal_by_brave_npc()
	_check_non_money_demands()
	_check_dead_npc_is_silent()
	_check_material_survives_save()
	_check_handler_day_hook()
	_log.stop()
	await get_tree().process_frame


func _population(npc: NPCRuntime) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = [npc]
	return out


func _check_coward_demands_later() -> void:
	var coward: NPCRuntime = Fixtures.synthetic("bm_coward", "coward")
	CaughtHandler.apply_caught_reaction(coward, CRIME, "wing_3b", 0.0)
	var entry: Dictionary = Fixtures.material_of_kind(coward, Blackmail.KIND_WITNESSED)
	var due: int = int(entry.get("demand_day", 0))
	var wait_min: int = Database.get_balance_int("chantaje.dias_espera_min")
	var wait_max: int = Database.get_balance_int("chantaje.dias_espera_max")
	var today: int = int(entry.get("day", 0))
	check(due >= today + wait_min and due <= today + wait_max,
			"the coward waits %d–%d days before demanding (due day %d)" % [wait_min, wait_max, due])
	_log.clear()
	check(Blackmail.process_day(due - 1, _population(coward)).is_empty() \
			and _log.count("blackmail_demanded") == 0, "no demand before the due day")
	var events: Array[Dictionary] = Blackmail.process_day(due, _population(coward))
	check_eq(events.size(), 1, "on the due day the coward demands")
	var demanded: Array = _log.last("blackmail_demanded")
	check(not demanded.is_empty() and demanded[0] == coward.id
			and Blackmail.DEMAND_TYPES.has(demanded[1]),
			"blackmail_demanded(npc, money|promotion|favour, amount) is emitted")
	check_eq(_log.last("blackmail_initiated"), [coward.id, "player", Blackmail.KIND_WITNESSED],
			"the first demand initiates the blackmail")
	var message: Array = _log.last("phone_message_received")
	check(not message.is_empty() and message[0] == coward.id and bool(message[2]),
			"the demand arrives as a phone chat message")
	check(Blackmail.process_day(due, _population(coward)).is_empty(),
			"one open demand at a time")


func _money_npc(npc_id: String, archetype: String, overrides: Dictionary) -> NPCRuntime:
	var npc: NPCRuntime = Fixtures.synthetic(npc_id, archetype, overrides)
	Blackmail.add_material(npc, Blackmail.KIND_WITNESSED, CRIME, DAY, Blackmail.DEMAND_MONEY, 0)
	return npc


func _check_money_demand_cycle() -> void:
	var npc: NPCRuntime = _money_npc("bm_money", "coward", {})
	var wallet: Fixtures.FakeWallet = Fixtures.FakeWallet.new(1000)
	Blackmail.process_day(DAY, _population(npc))
	check_eq(Blackmail.get_open_demand(npc).get("amount", 0), 600,
			"money demand = wage × chantaje.multiplicador (30 × 20 = 600)")
	var listed: Array[Dictionary] = Blackmail.get_open_demands(_population(npc))
	check(listed.size() == 1 and listed[0]["npc_id"] == npc.id and listed[0]["amount"] == 600,
			"open demands are listed for the phone")
	var paid: Dictionary = Blackmail.pay(npc, {"wallet": wallet, "day": DAY})
	check(bool(paid["ok"]) and wallet.money == 400, "paying hands over the money (1000 − 600)")
	check_eq(paid["status"], Blackmail.STATUS_HELD, "paying buys time, not oblivion")
	var next_day: int = int(paid["next_demand_day"])
	check(next_day > DAY, "the blackmailer will come back (day %d)" % next_day)
	Blackmail.process_day(next_day, _population(npc))
	check_eq(Blackmail.get_open_demand(npc).get("amount", 0), 900,
			"the second demand escalates × 1.5 (900)")
	var broke: Dictionary = Blackmail.pay(npc, {"wallet": wallet, "day": next_day})
	check(not bool(broke["ok"]) and broke["reason"] == Blackmail.REASON_NO_FUNDS,
			"without enough money the demand cannot be paid")
	check(not Blackmail.get_open_demand(npc).is_empty(), "the unpaid demand stays open")
	var deadline: int = int(Blackmail.get_open_demand(npc)["deadline_day"])
	_log.clear()
	check(Blackmail.process_day(deadline, _population(npc)).is_empty(), "the deadline day is still valid")
	var ignored: Array[Dictionary] = Blackmail.process_day(deadline + 1, _population(npc))
	check(ignored.size() == 1 and ignored[0]["event"] == Blackmail.EVENT_IGNORED,
			"ignoring the demand past its deadline counts as refusing")
	check_eq(_log.last("npc_reported_player"), [npc.id, "anonymous_tip", 10.0, "wing_3b"],
			"a refused coward leaks an anonymous tip (weight 10)")
	check_eq(Blackmail.get_material(npc)[0]["status"], Blackmail.STATUS_USED,
			"the material has been used")


func _check_refusal_by_brave_npc() -> void:
	var npc: NPCRuntime = _money_npc("bm_brave", "bribable", {"courage": 40})
	Blackmail.process_day(DAY, _population(npc))
	_log.clear()
	var refused: Dictionary = Blackmail.refuse(npc)
	check(bool(refused["ok"]) and refused["report_type"] == "security",
			"refusing a braver blackmailer sends them to Security")
	check_eq(_log.last("npc_reported_player").slice(0, 3), [npc.id, "security", 20.0],
			"the refused blackmailer reports you (+20)")
	check_eq(Blackmail.refuse(npc)["reason"], Blackmail.REASON_NO_DEMAND,
			"nothing left to refuse")


func _check_non_money_demands() -> void:
	var climber: NPCRuntime = Fixtures.synthetic("bm_climber", "climber")
	CaughtHandler.apply_caught_reaction(climber, CRIME, "wing_3b", 0.0)
	var entry: Dictionary = Blackmail.get_material(climber)[0]
	Blackmail.process_day(int(entry["demand_day"]), _population(climber))
	check_eq(_log.last("blackmail_demanded"), [climber.id, Blackmail.DEMAND_PROMOTION, 0],
			"the climber demands a promotion, not money")
	var paid: Dictionary = Blackmail.pay(climber, {"day": int(entry["demand_day"])})
	check(bool(paid["ok"]) and float(paid["reputation_cost"]) == 5.0 \
			and int(paid["favour_magnitude"]) == 5,
			"backing their promotion costs reputation (5) and owes them a favour (5)")
	var max_demands: int = Database.get_balance_int("chantaje.max_exigencias")
	for i: int in range(1, max_demands):
		Blackmail.process_day(int(entry["demand_day"]), _population(climber))
		paid = Blackmail.pay(climber, {"day": int(entry["demand_day"])})
	check_eq(paid["status"], Blackmail.STATUS_SETTLED,
			"after %d satisfied demands the blackmailer is settled" % max_demands)
	check(Blackmail.process_day(int(entry["demand_day"]) + 30, _population(climber)).is_empty(),
			"a settled blackmailer never asks again")


func _check_dead_npc_is_silent() -> void:
	var npc: NPCRuntime = _money_npc("bm_dead", "coward", {})
	npc.alive = false
	check(Blackmail.process_day(DAY, _population(npc)).is_empty(), "the dead do not blackmail")


func _check_material_survives_save() -> void:
	var npc: NPCRuntime = Fixtures.synthetic("bm_saved", "coward")
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_BRIBED_SILENCE, CRIME, DAY,
			Blackmail.DEMAND_MONEY, 2)
	var restored: NPCRuntime = NPCRuntime.from_dict(
			JSON.parse_string(JSON.stringify(npc.to_dict())), "save")
	check(Blackmail.has_material(restored), "material is saved with the NPC (NPCDirector save)")
	check(Blackmail.process_day(DAY + 1, _population(restored)).is_empty(),
			"restored material keeps its due day")
	var events: Array[Dictionary] = Blackmail.process_day(int(entry["demand_day"]),
			_population(restored))
	check(events.size() == 1 and int(events[0]["amount"]) == 600,
			"restored material demands normally (600)")


func _check_handler_day_hook() -> void:
	var handler: CaughtHandler = CaughtHandler.new()
	var npc: NPCRuntime = _money_npc("bm_hook", "coward", {})
	handler.population_source = func() -> Array[NPCRuntime]: return _population(npc)
	add_child(handler)
	handler.set_process(false)
	check(EventBus.day_advanced.is_connected(Callable(handler, "_on_day_advanced")),
			"CaughtHandler listens to day_advanced")
	_log.clear()
	handler.process_blackmail_day(DAY)
	check_eq(_log.count_for("blackmail_demanded", npc.id), 1,
			"the daily tick issues due blackmail demands")
	handler.queue_free()
