# qa_economy_endgame_trade.gd (escenario) — QA adversarial de §11.5 (compradores) y §11.6 (robo en
# fábrica, inventario semanal, cierre mensual) y de su reflejo en §9.2 (costes/pérdidas) y §12.8 (ORO/RUINA).
# PROPIETARIO DE: nada (conduce el juego; saltos de QA: teletransporte, reloj, ocupación).
# ESCUCHA: señales de EventBus (solo registro).
extends Node

## tools/screenshot.sh /tmp/qa_trade qa_economy_endgame_trade --force-rank=28 --seed=7 --skip-intro
## Capturas: trade_01_demo_room · trade_02_after_ops · trade_03_factory · trade_04_month_close

const SHORT := 8

var _pilot: Autopilot = null
var _game: GameRoot = null
var _ops: Node = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("QA Trade", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("qa_trade: no game scene")
		return
	await pilot.frames(SHORT * 3)
	_game = GameRoot.find(get_tree())
	_ops = (load("res://src/util/autopilot_scenarios/social_ops.gd") as GDScript).new()
	add_child(_ops)
	_ops.set("_pilot", pilot)
	_ops.set("_game", _game)
	EventBus.game_over.connect(func(c: String, e: String, _t: Dictionary) -> void: _log("SIG GAME_OVER %s %s" % [c, e]))
	EventBus.tracking_event_recorded.connect(func(ax: String, n: int, src: String) -> void: _log("SIG track %s +%d %s" % [ax, n, src]))
	EventBus.investigation_opened.connect(func(c: String, t: String, sev: int) -> void: _log("SIG investigation_opened %s %s sev=%d day=%d" % [c, t, sev, GameClock.get_day()]))
	EventBus.suspicion_changed.connect(func(a: float, b: float) -> void:
		if absf(b - a) >= 3.0:
			_log("SIG suspicion %.1f -> %.1f day=%d" % [a, b, GameClock.get_day()]))
	await _buyers()
	await _factory()
	await _month()
	_log("END money=%d susp=%.1f axes=%s losses=%.0f" % [PlayerState.get_money(), PlayerState.get_suspicion(), str(Tracking.get_all_axes()), Company.get_total_theft_losses()])


func _buyers() -> void:
	PlayerState.set_occupation("senior_sales", "qa")
	GameClock.advance_to_next_day()
	await _pilot.frames(4)
	GameClock.advance_minutes(maxf(16.0 * 60.0 + 10.0 - GameClock.get_day_minutes(), 0.0))
	var visits: Array[Dictionary] = Company.get_buyers_today()
	_log("BUYERS day=%d visits=%s" % [GameClock.get_day(), str(visits)])
	await _ops.call("_go", "buyer_demo_room")
	await _pilot.shot("trade_01_demo_room")
	var plan: Array[String] = [Buyers.OP_PHANTOM, Buyers.OP_OVERPRICE]
	var money0: int = PlayerState.get_money()
	for i: int in visits.size():
		var bid: String = str(visits[i].get("buyer_id", ""))
		_log("  VISIT %s traits=%s can=%s" % [bid, str(Company.get_buyer(bid).get("traits", {})), str(Buyers.can_operate(bid))])
		var r: Dictionary = Buyers.operate(bid, plan[i % plan.size()], {})
		_log("  OP %s -> %s" % [plan[i % plan.size()], str(r)])
	# Extra visit to exercise the other two operations.
	var roster: Array[Dictionary] = Company.get_buyer_roster()
	for op: String in [Buyers.OP_KICKBACK, Buyers.OP_HONEST]:
		for b: Dictionary in roster:
			if Company.schedule_buyer_visit(str(b["id"]), 100):
				_log("  OP %s (%s) -> %s" % [op, b["id"], str(Buyers.operate(str(b["id"]), op, {}))])
				break
	_log("BUYERS money %d -> %d claims=%s frauds=%s" % [money0, PlayerState.get_money(), str(Company.get_pending_buyer_claims()), str(Company.get_pending_sales_frauds())])
	await _pilot.frames(SHORT)
	await _pilot.shot("trade_02_after_ops")


func _factory() -> void:
	for scale: String in ["pocket", "box", "pallet"]:
		_log("FACTORY req %s (away) = %s" % [scale, str(FactoryTheft.check_requirements(scale))])
	PlayerState.set_occupation("factory_foreman" if Database.get_occupation("factory_foreman") != null else PlayerState.get_occupation_id(), "qa")
	await _ops.call("_go", "finished_goods")
	_log("FACTORY room=%s" % PlayerState.get_room())
	for scale: String in ["pocket", "box", "pallet"]:
		_log("FACTORY req %s = %s" % [scale, str(FactoryTheft.check_requirements(scale, {"cart": true}))])
		_log("FACTORY steal %s = %s" % [scale, str(FactoryTheft.steal(scale, {"cart": true}))])
	await _pilot.shot("trade_03_factory")


func _month() -> void:
	var guard: int = 0
	while GameClock.get_day() < 21 and guard < 30:
		guard += 1
		GameClock.advance_to_next_day()
		await _pilot.frames(2)
		if GameClock.get_day() % 5 == 1:
			_log("WEEK day=%d reports=%s" % [GameClock.get_day(), str(Company.get_inventory_reports().back() if not Company.get_inventory_reports().is_empty() else {})])
	_log("MONTH report=%s demands=%s" % [str(Company.get_last_month_report()), str(Company.get_buyer_demands())])
	_log("FUND %s" % str(Company.get_fundamentals()))
	await _pilot.shot("trade_04_month_close")


func _log(s: String) -> void:
	print("[qa_trade] " + s)
