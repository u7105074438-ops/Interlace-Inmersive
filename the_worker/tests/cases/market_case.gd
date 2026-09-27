# market_case.gd — Cuerpo de test_market: fórmulas §9.3, paso horario (nunca por fotograma), trimestre con/sin escándalo, reversión por gravedad, calendario §9.4 y guardado.
# PROPIETARIO DE: nada.
# ESCUCHA: stock_price_updated, results_presentation_due (solo para comprobarlas).
extends TestCase

const EPS := 0.0001
# Números del manual (§9.3, §9.4, §20.2) que balance/market.json deben respetar.
const MANUAL_ALPHA := 0.05
const MANUAL_BETA := 0.30
const MANUAL_GAMMA := 0.15
const MANUAL_NOISE := 0.03
const MANUAL_BASE_MULTIPLE := 14.0
const MANUAL_GROWTH_MOD := 0.8
const MANUAL_RISK_MOD := -1.2
const MANUAL_MOMENTUM_DAYS := 5
const MANUAL_START_PRICE := 42.5
const MANUAL_SHARES := 40000000
const MANUAL_FISCAL_DAYS := 100
const OFFICE_HOURS := 11
const CALIBRATED_VALUE := 42.49
# Escenarios emparejados: mismas semillas → mismo ruido; la diferencia es el evento.
const PAIRED_SEEDS: Array[int] = [11, 22, 33, 44, 55, 66]
const GRAVITY_SEEDS: Array[int] = [7, 8, 9]
const QUARTER_DAYS := 25
const SCANDAL_DAY := 3
const MIN_MEAN_DEPRESSION := 0.04
const CLEAN_TOLERANCE := 0.05
const REVERSION_DAYS := 60
const MIN_MANIPULATION_GAIN := 0.05
const HALF_REVERTED := 0.5
const MOSTLY_REVERTED := 0.2
const EVENT_SCANDAL := "scandal"
const EVENT_PRAISE := "praise"
const PRAISE_HEADLINE := "NEWS_FABRICATED_PRAISE"
const NIGHT_HOUR := 3
const OPENING_HOUR := 8
const FIRST_TRADING_HOUR := 9
const NOISE_SAMPLE_DAYS := 120

var _price_updates: int = 0
var _due: Array[int] = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	EventBus.stock_price_updated.connect(_on_price_updated)
	EventBus.results_presentation_due.connect(_on_due)
	_test_manual_numbers()
	_test_intrinsic_value()
	_test_daily_formula()
	await _test_hourly_not_per_frame()
	_test_hour_wiring_and_day_close()
	_test_momentum_history()
	_test_scandal_quarter()
	_test_gravity_reverts_manipulation()
	_test_calendar()
	_test_save_load()


func _on_price_updated(_price: float, _delta_percent: float) -> void:
	_price_updates += 1


func _on_due(quarter_number: int) -> void:
	_due.append(quarter_number)


func _test_manual_numbers() -> void:
	check_near(Database.get_balance_float("mercado.alpha_gravedad"), MANUAL_ALPHA, EPS, "α = 0.05")
	check_near(Database.get_balance_float("mercado.beta_sentimiento"), MANUAL_BETA, EPS, "β = 0.30")
	check_near(Database.get_balance_float("mercado.gamma_momentum"), MANUAL_GAMMA, EPS, "γ = 0.15")
	check_near(Database.get_balance_float("mercado.ruido_diario_max"), MANUAL_NOISE, EPS,
			"noise ∈ [-0.03, 0.03] × P")
	check_eq(Database.get_balance_int("mercado.dias_momentum"), MANUAL_MOMENTUM_DAYS,
			"momentum over five days")
	check_near(Market.get_price(), MANUAL_START_PRICE, EPS, "a new run starts at the initial price")
	check_eq(Market.get_steps_per_day(), OFFICE_HOURS, "the daily step is split into 11 office hours")
	check_eq(Market.get_price_history(10).size(), 1, "history starts with the opening price only")


func _test_intrinsic_value() -> void:
	check_near(Market.compute_multiple(0.0, 0.0), MANUAL_BASE_MULTIPLE, EPS, "multiple = base 14")
	var growth: float = 0.5
	var risk: float = 1.0
	check_near(Market.compute_multiple(growth, risk),
			MANUAL_BASE_MULTIPLE + MANUAL_GROWTH_MOD * growth + MANUAL_RISK_MOD * risk, EPS,
			"multiple = base + 0.8 × growth − 1.2 × risk")
	var fundamentals: Dictionary = Company.get_fundamentals()
	var blank: bool = is_zero_approx(float(fundamentals.get("revenue", 0.0))) \
			and is_zero_approx(float(fundamentals.get("costs", 0.0)))
	if blank:
		var start: Dictionary = Database.get_market_params()["starting_fundamentals"]
		fundamentals = {"profit": float(start["profit_per_day"])}
	var expected: float = float(fundamentals["profit"]) * MANUAL_FISCAL_DAYS \
			* Market.get_valuation_multiple() / MANUAL_SHARES
	check_near(Market.get_intrinsic_value(), expected, EPS,
			"V = annual profit × multiple ÷ 40,000,000 shares")
	if blank:
		check_near(Market.get_intrinsic_value(), CALIBRATED_VALUE, 0.01,
				"starting fundamentals give V ≈ 42.49 (≈ opening price 42.50)")


func _test_daily_formula() -> void:
	var price: float = 40.0
	var value: float = 50.0
	var sentiment: float = 0.1
	var momentum: float = 0.2
	var noise: float = 0.01
	var expected: float = MANUAL_ALPHA * (value - price) + MANUAL_BETA * sentiment * price \
			+ MANUAL_GAMMA * momentum + noise * price
	check_near(Market.compute_daily_delta(price, value, sentiment, momentum, noise), expected, EPS,
			"daily step = α(V−P) + β·sentiment·P + γ·momentum + noise·P")
	check_near(Market.compute_daily_delta(price, price, 0.0, 0.0, 0.0), 0.0, EPS,
			"at V with no sentiment, momentum or noise the price does not move")
	var low: float = 1.0
	var high: float = -1.0
	for _i: int in NOISE_SAMPLE_DAYS:
		low = minf(low, Market.get_noise_today())
		high = maxf(high, Market.get_noise_today())
		Market.advance_day(Market.get_current_day() + 1)
	check(low >= -MANUAL_NOISE and high <= MANUAL_NOISE, "daily noise stays within ±3 % of P")
	check(low < -MANUAL_NOISE * HALF_REVERTED and high > MANUAL_NOISE * HALF_REVERTED,
			"daily noise uses the whole ±3 % band")


func _test_hourly_not_per_frame() -> void:
	new_run(DEFAULT_SEED, false)
	var start: float = Market.get_price()
	await wait_frames(20)
	check_eq(Market.get_price(), start, "the price does not change per frame")
	check(not Market.is_processing() and not Market.is_physics_processing(),
			"Market has no per-frame processing")
	var expected_step: float = Market.compute_daily_delta(start, Market.get_intrinsic_value(),
			Market.get_sentiment(), Market.get_momentum(), Market.get_noise_today()) / OFFICE_HOURS
	_price_updates = 0
	Market.tick_hourly()
	check_near(Market.get_price() - start, expected_step, 0.000001,
			"one hourly tick applies 1/11 of the daily formula")
	for _i: int in OFFICE_HOURS - 1:
		Market.tick_hourly()
	var closed: float = Market.get_price()
	Market.tick_hourly()
	check_eq(Market.get_price(), closed, "no more than 11 steps per trading day")
	check_eq(_price_updates, OFFICE_HOURS, "stock_price_updated once per hourly step")
	check_eq(Market.get_steps_done_today(), OFFICE_HOURS, "all 11 steps done")


func _test_hour_wiring_and_day_close() -> void:
	new_run(DEFAULT_SEED, false)
	var day: int = Market.get_current_day()
	var start: float = Market.get_price()
	EventBus.hour_passed.emit(NIGHT_HOUR, day)
	EventBus.hour_passed.emit(OPENING_HOUR, day)
	check_eq(Market.get_steps_done_today(), 0, "no trading step at night or at the 08:00 opening")
	EventBus.hour_passed.emit(FIRST_TRADING_HOUR, day)
	check_eq(Market.get_steps_done_today(), 1, "hour_passed(09:00) applies one trading step")
	check(Market.get_price() != start, "the hourly step moves the price")
	_price_updates = 0
	Market.advance_day(day + 1)
	check_eq(_price_updates, OFFICE_HOURS - 1, "day close applies the 10 skipped hourly steps")
	var history: Array[float] = Market.get_price_history(1)
	check_eq(history[0], Market.get_price(), "the day close is stored in the history")
	check_eq(Market.get_steps_done_today(), 0, "a new trading day starts with no steps")


func _test_momentum_history() -> void:
	new_run(DEFAULT_SEED, false)
	for _d: int in 8:
		_run_trading_day()
	var closes: Array[float] = Market.get_price_history(MANUAL_MOMENTUM_DAYS + 1)
	check_eq(closes.size(), MANUAL_MOMENTUM_DAYS + 1, "history returns the requested days")
	var expected: float = (closes[MANUAL_MOMENTUM_DAYS] - closes[0]) / MANUAL_MOMENTUM_DAYS
	check_near(Market.get_momentum(), expected, EPS,
			"momentum = mean daily change of the last five days")


func _test_scandal_quarter() -> void:
	var depression_sum: float = 0.0
	var clean_sum: float = 0.0
	var dirty_sum: float = 0.0
	var always_lower: bool = true
	for run_seed: int in PAIRED_SEEDS:
		var clean: Array[float] = _simulate(run_seed, QUARTER_DAYS, -1, "")
		var dirty: Array[float] = _simulate(run_seed, QUARTER_DAYS, SCANDAL_DAY, EVENT_SCANDAL)
		var clean_end: float = clean[QUARTER_DAYS - 1]
		var dirty_end: float = dirty[QUARTER_DAYS - 1]
		always_lower = always_lower and dirty_end < clean_end
		depression_sum += (clean_end - dirty_end) / clean_end
		clean_sum += clean_end
		dirty_sum += dirty_end
	var runs: float = float(PAIRED_SEEDS.size())
	check(always_lower, "with the same noise, a quarter with a scandal always closes lower")
	check(depression_sum / runs >= MIN_MEAN_DEPRESSION,
			"a scandal depresses the quarter close (mean %.1f %%)" % (depression_sum / runs * 100.0))
	check(clean_sum / runs >= MANUAL_START_PRICE * (1.0 - CLEAN_TOLERANCE),
			"a quarter without scandal is not depressed (mean close %.2f)" % (clean_sum / runs))
	check(dirty_sum / runs < MANUAL_START_PRICE * (1.0 - MIN_MEAN_DEPRESSION),
			"the scandal quarter closes below the opening price (mean %.2f)" % (dirty_sum / runs))


func _test_gravity_reverts_manipulation() -> void:
	var half_life: int = ceili(log(0.5) / log(1.0 - MANUAL_ALPHA))
	for run_seed: int in GRAVITY_SEEDS:
		var clean: Array[float] = _simulate(run_seed, REVERSION_DAYS, -1, "")
		var manipulated: Array[float] = _simulate(run_seed, REVERSION_DAYS, 1, EVENT_PRAISE)
		var peak: float = 0.0
		var peak_day: int = 0
		for d: int in REVERSION_DAYS:
			var diff: float = manipulated[d] - clean[d]
			if diff > peak:
				peak = diff
				peak_day = d
		var later: int = mini(peak_day + 2 * half_life, REVERSION_DAYS - 1)
		var tag: String = "seed %d" % run_seed
		check(peak >= MANUAL_START_PRICE * MIN_MANIPULATION_GAIN,
				"%s: fabricated praise buys a real rise (+%.2f)" % [tag, peak])
		check(manipulated[later] - clean[later] <= peak * HALF_REVERTED,
				"%s: gravity halves the gain within two half-lives (%d days)" % [tag, 2 * half_life])
		check(manipulated[REVERSION_DAYS - 1] - clean[REVERSION_DAYS - 1] <= peak * MOSTLY_REVERTED,
				"%s: after %d days at most 20 %% of the gain remains" % [tag, REVERSION_DAYS])


func _test_calendar() -> void:
	new_run(DEFAULT_SEED, false)
	var today: int = Market.get_current_day()
	var presentation_day: int = Market.get_presentation_day()
	check_eq(Market.day_in_quarter(presentation_day), 25, "results presentation on day 25 of the quarter")
	var periods: Dictionary = {}
	for entry: Dictionary in Market.get_calendar(MANUAL_FISCAL_DAYS - today):
		var days: Array = periods.get(entry["periodicity"], [])
		days.append(entry["day"])
		periods[entry["periodicity"]] = days
	check_eq((periods.get("daily", []) as Array).size(), MANUAL_FISCAL_DAYS - today + 1,
			"the share trades every day")
	check((periods.get("weekly", []) as Array).has(5), "weekly internal reports on day 5")
	check((periods.get("monthly", []) as Array).has(20), "monthly close on day 20")
	check((periods.get("quarterly", []) as Array).has(presentation_day), "quarterly results day")
	check((periods.get("annual", []) as Array) == [MANUAL_FISCAL_DAYS], "annual board on day 100")
	_due.clear()
	EventBus.hour_passed.emit(10, presentation_day)
	check(_due.is_empty(), "no presentation call before 11:00")
	EventBus.hour_passed.emit(11, presentation_day)
	EventBus.hour_passed.emit(11, presentation_day)
	check(_due.size() == 1 and _due[0] == 1,
			"results_presentation_due(1) emitted once at 11:00 of day 25")


func _test_save_load() -> void:
	new_run(DEFAULT_SEED, false)
	for _d: int in 3:
		_run_trading_day()
	Market.modify_investor_confidence("inv_neil_deming", -7, "test")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Market.save_state()))
	var original: Array[float] = _two_more_days()
	Market.load_state(saved)
	check_eq(Market.get_investor_confidence("inv_neil_deming"), 53, "confidence restored after load")
	var restored: Array[float] = _two_more_days()
	var same: bool = original.size() == restored.size()
	for i: int in original.size():
		same = same and absf(original[i] - restored[i]) < 0.000001
	check(same, "after load_state the price path (history, noise RNG) continues identically")


func _two_more_days() -> Array[float]:
	var prices: Array[float] = []
	for _d: int in 2:
		_run_trading_day()
		prices.append(Market.get_price())
	return prices


func _run_trading_day() -> void:
	for _h: int in Market.get_steps_per_day():
		Market.tick_hourly()
	Market.advance_day(Market.get_current_day() + 1)


## Partida nueva con semilla fija; `days` jornadas de mercado; el evento ocurre al abrir event_day.
func _simulate(run_seed: int, days: int, event_day: int, event_kind: String) -> Array[float]:
	new_run(run_seed, false)
	var closes: Array[float] = []
	for d: int in range(1, days + 1):
		if d == event_day:
			_apply_event(event_kind)
		_run_trading_day()
		NewsFeed.apply_daily_decay()
		closes.append(Market.get_price())
	return closes


func _apply_event(event_kind: String) -> void:
	if event_kind == EVENT_SCANDAL:
		NewsFeed.publish(NewsFeedSystem.HEADLINE_BODY_FOUND,
				Database.get_balance_float("noticias.sentimiento_cuerpo_hallado"), true)
	elif event_kind == EVENT_PRAISE:
		NewsFeed.fabricate(NewsFeedSystem.SUBJECT_COMPANY, PRAISE_HEADLINE)
