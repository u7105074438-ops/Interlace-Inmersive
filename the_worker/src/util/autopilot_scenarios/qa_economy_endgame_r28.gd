# qa_economy_endgame_r28.gd (escenario) — QA adversarial de §9 (mercado, inversores, insider,
# presentación trimestral) y §11.5-11.7 (compradores, fábrica, huelgas) jugado desde R28.
# PROPIETARIO DE: nada (conduce el juego; saltos de QA: reloj y dinero).
# ESCUCHA: señales de EventBus (solo registro).
extends Node

## tools/screenshot.sh /tmp/qa_r28 qa_economy_endgame_r28 --force-rank=28 --seed=7 --skip-intro
## Capturas: r28_01_start · r28_02_market · r28_03_results_prep · r28_04_inflated · r28_05_present
##           r28_06_reaction · r28_07_strike · r28_08_q2_end

const SHORT := 8

var _pilot: Autopilot = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("QA Econ", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("qa_r28: no game scene")
		return
	await pilot.frames(SHORT * 3)
	_hook()
	_log("START rank=%d occ=%s money=%d" % [PlayerState.get_rank(), PlayerState.get_occupation_id(), PlayerState.get_money()])
	_state("start")
	await pilot.shot("r28_01_start")
	await _insider()
	await _buyers()
	await _run_days_to_results()
	await _results()
	await _strike()
	await _second_quarter()
	_state("end")
	_log("END")


func _hook() -> void:
	EventBus.insider_pattern_detected.connect(func(n: int) -> void: _log("SIG insider_pattern_detected ops=%d" % n))
	EventBus.game_over.connect(func(c: String, e: String, _t: Dictionary) -> void: _log("SIG GAME_OVER %s %s" % [c, e]))
	EventBus.occupation_changed.connect(func(a: String, b: String, r: String) -> void: _log("SIG occupation %s -> %s (%s)" % [a, b, r]))
	EventBus.strike_resolved.connect(func(r: String) -> void: _log("SIG strike_resolved %s" % r))
	EventBus.quarter_closed.connect(func(q: int) -> void: _log("SIG quarter_closed %d agg=%.1f target=%.1f streak=%d" % [q, Market.get_aggregate_confidence(), Market.get_quarterly_target(), Market.get_bad_quarters_streak()]))


	EventBus.suspicion_changed.connect(func(a: float, b: float) -> void:
		if absf(b - a) >= 5.0:
			_log("SIG suspicion %.1f -> %.1f day=%d stack=%s" % [a, b, GameClock.get_day(), str(get_stack().slice(1, 6))])
			for e: Dictionary in BeliefNet.get_suspicion_breakdown():
				_log("    SUSP_ENTRY %s" % str(e)))
	EventBus.investigation_opened.connect(func(c: String, t: String, sev: int) -> void: _log("SIG investigation_opened %s %s sev=%d" % [c, t, sev]))
	EventBus.investigation_resolved.connect(func(c: String, v: String, cu: String) -> void: _log("SIG investigation_resolved %s %s %s" % [c, v, cu]))
	EventBus.news_published.connect(func(h: String, d: float, sc: bool) -> void: _log("SIG news %s d=%.3f scandal=%s day=%d" % [h, d, sc, GameClock.get_day()]))
	EventBus.audit_triggered.connect(func(f: bool) -> void: _log("SIG audit_triggered found=%s day=%d" % [f, GameClock.get_day()]))
	EventBus.investor_confidence_changed.connect(func(i: String, a: int, b: int) -> void:
		if absi(b - a) >= 5:
			_log("SIG conf %s %d -> %d reason=%s day=%d" % [i, a, b, Market.get_last_confidence_reason(i), GameClock.get_day()]))
	EventBus.tracking_event_recorded.connect(func(ax: String, n: int, src: String) -> void: _log("SIG track %s +%d %s" % [ax, n, src]))
	EventBus.strike_started.connect(func() -> void: _log("SIG strike_started day=%d" % GameClock.get_day()))


func _state(tag: String) -> void:
	var f: Dictionary = Company.get_fundamentals()
	_log("STATE %s day=%d q=%d price=%.2f V=%.2f mult=%.2f sent=%.3f agg=%.1f target=%.1f disc=%d strike=%s money=%d susp=%.1f rep=%.1f fund=%s" % [
		tag, GameClock.get_day(), GameClock.get_quarter(), Market.get_price(), Market.get_intrinsic_value(),
		Market.get_valuation_multiple(), Market.get_sentiment(), Market.get_aggregate_confidence(),
		Market.get_quarterly_target(), Company.get_discontent(), Company.is_strike_active(),
		PlayerState.get_money(), PlayerState.get_suspicion(), PlayerState.get_reputation(), str(f)])
	for inv: InvestorData in Market.get_investors():
		_log("  INV %s strat=%s cap=%s conf=%d" % [inv.id, inv.strategy, str(inv.capital), Market.get_investor_confidence(inv.id)])
	_log("  TRACK %s dominant=%s ruin=%s" % [str(Tracking.get_all_axes()), Tracking.get_dominant_axis(), Tracking.get_ruin_tier()])


func _insider() -> void:
	PlayerState.add_money(200000, "qa")
	_log("INSIDER can_trade=%s upcoming=%s dirs=%s" % [Market.can_trade(), str(Market.get_upcoming_news(3)), str(Market.get_upcoming_news_directions(3))])
	_log("INSIDER schedule=%s" % NewsFeed.schedule_market_event("viral_moment", GameClock.get_day() + 1))
	_log("INSIDER schedule2=%s" % NewsFeed.schedule_market_event("celebrity_wears_brand", GameClock.get_day() + 2))
	_log("INSIDER after schedule upcoming=%s informed_buy=%s" % [str(Market.get_upcoming_news(3)), Market.is_trade_informed(Market.TRADE_BUY)])
	for i: int in 6:
		var ok: bool = MarketTrading.buy(200)
		_log("INSIDER buy#%d ok=%s shares=%d score=%.3f ops=%d detections=%d susp=%.1f" % [i, ok, Market.get_player_shares(), Market.get_insider_pattern_score(), Market.get_insider_operations_count(), Market.get_insider_detections(), PlayerState.get_suspicion()])
	var stake_price: int = Market.get_board_stake_price()
	_log("STAKE price=%d has=%s" % [stake_price, Market.has_board_stake()])
	await _open_os(MarketApp.APP_ID)
	await _pilot.shot("r28_02_market")
	_close_os()


func _buyers() -> void:
	var list: Array[Dictionary] = Company.get_buyers_today()
	_log("BUYERS today=%d visit_day=%s roster=%d" % [list.size(), Company.is_buyer_visit_day(GameClock.get_day()), Company.get_buyer_roster().size()])
	for b: Dictionary in Company.get_buyer_roster():
		_log("  BUYER %s" % str(b))
	var d: int = GameClock.get_day()
	while not Company.is_buyer_visit_day(d) and d < GameClock.get_day() + 10:
		d += 1
	_log("BUYERS next visit day=%d" % d)
	if not Company.get_buyer_roster().is_empty():
		var bid: String = str(Company.get_buyer_roster()[0].get("id", ""))
		Company.schedule_buyer_visit(bid, 20)
		for op: String in ["phantom", "overprice", "kickback", "honest"]:
			var r: Dictionary = Buyers.operate(bid, op, {})
			_log("  OP %s -> %s" % [op, str(r)])


func _run_days_to_results() -> void:
	var target: int = Market.get_presentation_day()
	_log("RESULTS day=%d room=%s" % [target, Market.get_presentation_room()])
	var guard: int = 0
	while GameClock.get_day() < target and guard < 40:
		guard += 1
		GameClock.advance_to_next_day()
		await _pilot.frames(2)
		_log("DAY %d price=%.2f agg=%.1f disc=%d susp=%.1f money=%d" % [GameClock.get_day(), Market.get_price(), Market.get_aggregate_confidence(), Company.get_discontent(), PlayerState.get_suspicion(), PlayerState.get_money()])
		if GameClock.get_day() % 5 == 0:
			_log("  INVENTORY reports=%d thefts=%d lastmonth=%s" % [Company.get_inventory_reports().size(), Company.get_factory_theft_count(), str(Company.get_last_month_report())])
	GameClock.set_time(GameClock.get_day(), 10, 0)
	_state("results_day")


func _results() -> void:
	_log("RESULTS can_present=%s" % Market.can_present_results())
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.open(self, GameClock.get_quarter())
	await _pilot.frames(SHORT)
	await _pilot.shot("r28_03_results_prep")
	_log("RESULTS audit_preview0=%s" % str(screen.audit_preview()))
	screen.choose_inflation(0.3)
	await _pilot.frames(4)
	_log("RESULTS audit_preview30=%s" % str(screen.audit_preview()))
	await _pilot.shot("r28_04_inflated")
	screen.request_lock_figures()
	screen.confirm_pending()
	_log("RESULTS levels=%s" % str(screen.available_levels()))
	screen.select_preparation("real_work")
	screen.select_preparation("assist")
	await _pilot.frames(4)
	await _pilot.shot("r28_05_present")
	var r: Dictionary = screen.present()
	await _pilot.frames(SHORT)
	_log("RESULTS outcome=%s" % str(r))
	await _pilot.shot("r28_06_reaction")
	screen.finish()
	await _pilot.frames(4)
	if is_instance_valid(screen):
		screen.queue_free()
	_log("FUSE %s" % str(Company.get_audit_fuse()))
	_state("after_results")


func _strike() -> void:
	Company.modify_discontent(80, "qa")
	_log("STRIKE status=%s can_lead=%s" % [str(Strike.get_status()), str(Strike.can_lead())])
	var price0: float = Market.get_price()
	_log("STRIKE lead=%s" % str(Strike.lead()))
	GameClock.advance_to_next_day()
	await _pilot.frames(2)
	_state("strike_day1")
	_log("STRIKE price %.2f -> %.2f" % [price0, Market.get_price()])
	await _pilot.shot("r28_07_strike")
	_log("STRIKE betray=%s" % str(Strike.betray()))
	_log("STRIKE after betray status=%s" % str(Strike.get_status()))


func _second_quarter() -> void:
	var guard: int = 0
	var q0: int = GameClock.get_quarter()
	while GameClock.get_quarter() < q0 + 2 and guard < 60:
		guard += 1
		GameClock.advance_to_next_day()
		await _pilot.frames(1)
		if PlayerState.get_rank() < 28:
			_log("DEMOTED day=%d rank=%d" % [GameClock.get_day(), PlayerState.get_rank()])
			break
	_state("q_end")
	await _pilot.shot("r28_08_q2_end")


var _os: StellarOS = null


func _open_os(app_id: String) -> Control:
	_os = StellarOS.new()
	_os.setup({"app": app_id, "instant": true})
	add_child(_os)
	for i: int in 60:
		await _pilot.frames(1)
		if _os.get_open_app_id() == app_id and _os.get_open_app() != null:
			break
	await _pilot.frames(6)
	return _os.get_open_app()


func _close_os() -> void:
	if is_instance_valid(_os):
		_os.queue_free()


func _log(s: String) -> void:
	print("[qa_r28] " + s)
