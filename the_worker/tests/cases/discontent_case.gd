# discontent_case.gd — Cuerpo de test_discontent: factores de la tabla §11.7, término de ánimo, umbral de huelga y sus efectos en ambos cerebros.
# PROPIETARIO DE: nada.
# ESCUCHA: strike_discontent_changed, strike_started, news_published (solo para comprobarlas).
extends TestCase

const EPS := 0.01
const RATIO_EPS := 0.000001
# Tabla §11.7 del manual.
const MANUAL_UNJUST_DISMISSAL := 5
const MANUAL_EXCESSIVE_QUOTA := 2
const MANUAL_PAYROLL_DISCOVERED := 10
const MANUAL_DEGRADED_FACTORY := 3
const MANUAL_WAGE_CONCESSION := -15
const MANUAL_CULPRIT_DISMISSED := -10
const MANUAL_STRIKE_THRESHOLD := 70
const HIGH_QUOTA := 1.2
const COST_CUT := 0.1
const SIGNALS: Array[String] = [
	"strike_discontent_changed", "strike_started", "news_published",
]

var _log: Dictionary = {}


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	_test_manual_numbers()
	_test_labour_events()
	_test_dismissals()
	_test_daily_factors()
	_test_mood_term()
	_test_strike()
	_test_clamp_and_history()
	_test_save_load()


# ─── Escenarios ────────────────────────────────────────────────

func _test_manual_numbers() -> void:
	check_eq([_bi("descontento.por_despido_injusto"), _bi("descontento.por_cuota_excesiva_diaria"),
			_bi("descontento.por_manipulacion_nominas"), _bi("descontento.por_condiciones_fabrica"),
			_bi("descontento.reduccion_por_concesion"),
			_bi("descontento.reduccion_por_despedir_causante")],
			[MANUAL_UNJUST_DISMISSAL, MANUAL_EXCESSIVE_QUOTA, MANUAL_PAYROLL_DISCOVERED,
			MANUAL_DEGRADED_FACTORY, MANUAL_WAGE_CONCESSION, MANUAL_CULPRIT_DISMISSED],
			"§11.7 table: +5, +2/day, +10, +3/day, −15, −10")
	check_eq(_bi("descontento.umbral_huelga"), MANUAL_STRIKE_THRESHOLD, "strike threshold 70")
	check_eq(Company.get_discontent(), _bi("descontento.inicial"),
			"a run starts at the initial value")
	check(not Company.is_strike_active(), "no strike at the start")


func _test_labour_events() -> void:
	_fresh()
	var start: int = Company.get_discontent()
	var payroll: float = float(Company.get_fundamentals()["payroll"])
	var events: Array = [
		["unjust_dismissal", MANUAL_UNJUST_DISMISSAL],
		["payroll_manipulation_discovered", MANUAL_PAYROLL_DISCOVERED],
		["wage_concession", MANUAL_WAGE_CONCESSION],
		["culprit_dismissed", MANUAL_CULPRIT_DISMISSED],
	]
	var expected: int = start
	for e: Array in events:
		var old_value: int = Company.get_discontent()
		check_eq(Company.apply_labour_event(e[0]), e[1], "%s applies %d" % [e[0], e[1]])
		expected = clampi(expected + int(e[1]), 0, 100)
		check_eq(Company.get_discontent(), expected, "discontent after %s" % e[0])
		check_eq(_calls("strike_discontent_changed").back(), [old_value, expected],
				"strike_discontent_changed(old, new) for %s" % e[0])
	check_near(float(Company.get_fundamentals()["payroll"]),
			payroll * (1.0 + Database.get_balance_float("empresa.aumento_nomina_por_concesion")),
			EPS, "a wage concession has a direct economic cost (payroll)")


## Expulsión de escalón 1-3 = despido percibido como injusto; directivos y eliminaciones no.
func _test_dismissals() -> void:
	_fresh()
	var start: int = Company.get_discontent()
	NPCDirector.remove_npc(Company.get_seat_holder("email_worker_3b"), "expelled")
	check_eq(Company.get_discontent(), start + MANUAL_UNJUST_DISMISSAL,
			"expelling a tier-1 worker: +5")
	NPCDirector.remove_npc(Company.get_seat_holder("cfo"), "expelled")
	check_eq(Company.get_discontent(), start + MANUAL_UNJUST_DISMISSAL,
			"expelling a tier-7 executive does not upset the shop floor")
	NPCDirector.remove_npc(Company.get_seat_holder("order_filer"), "eliminated")
	check_eq(Company.get_discontent(), start + MANUAL_UNJUST_DISMISSAL,
			"an elimination is not a dismissal")


func _test_daily_factors() -> void:
	_fresh()
	var base: Dictionary = Company.get_fundamentals()
	Company.set_production_quota(HIGH_QUOTA)
	check(Company.is_quota_excessive(), "quota above what is reasonable")
	check_near(float(Company.get_fundamentals()["units"]), float(base["units"]) * HIGH_QUOTA, EPS,
			"the quota raises the units produced")
	check_eq(_day_delta(), MANUAL_EXCESSIVE_QUOTA + Company.get_mood_discontent_delta(),
			"excessive quota: +2 per day")
	Company.set_cost_cutting(COST_CUT)
	check(Company.is_factory_degraded(), "cost cutting degrades factory conditions")
	check_near(float(Company.get_fundamentals()["materials"]),
			float(base["materials"]) * HIGH_QUOTA * (1.0 - COST_CUT), EPS,
			"cost cutting lowers materials cost")
	check_eq(_day_delta(), MANUAL_EXCESSIVE_QUOTA + MANUAL_DEGRADED_FACTORY
			+ Company.get_mood_discontent_delta(), "degraded factory: +3 more per day")
	Company.set_production_quota(1.0)
	Company.set_cost_cutting(0.0)
	check_eq(_day_delta(), Company.get_mood_discontent_delta(),
			"reasonable quota and conditions: only the workforce mood remains")


## "Agrega el estado de ánimo de los escalones 1 a 3": término diario de ánimo.
func _test_mood_term() -> void:
	var mood: float = NPCDirector.get_average_mood(_bi("descontento.escalon_max_afectado"))
	check_eq(Company.get_mood_discontent_delta(),
			roundi(-mood * Database.get_balance_float("descontento.por_animo_diario")),
			"mood term = round(−average mood of tiers 1-3 × points per day)")


func _test_strike() -> void:
	_fresh()
	var base: Dictionary = Company.get_fundamentals()
	Company.modify_discontent(MANUAL_STRIKE_THRESHOLD - 1 - Company.get_discontent(), "test")
	check(_calls("strike_started").is_empty(), "69: no strike yet")
	Company.modify_discontent(1, "test")
	check_eq(_calls("strike_started").size(), 1, "reaching 70 starts the strike")
	check(Company.is_strike_active(), "strike active")
	Company.recalculate_fundamentals()
	var f: Dictionary = Company.get_fundamentals()
	var strike_units: float = Database.get_balance_float("empresa.factor_unidades_huelga")
	check_near(float(f["units"]), float(base["units"]) * strike_units, EPS,
			"production stops during the strike")
	var weights: Dictionary = Database.get_market_params()["risk_factor_weights"]
	check_near(float(f["risk_factor"]) - float(base["risk_factor"]),
			float(weights["strike_active"]) + float(weights["per_negative_news"]) * _bad_news(),
			RATIO_EPS, "the risk factor rises during the strike (and with its bad press)")
	Company.modify_discontent(5, "test")
	check_eq(_calls("strike_started").size(), 1, "no second strike while one is active")
	EventBus.strike_resolved.emit("concession")
	check(not Company.is_strike_active(), "strike_resolved ends it")
	Company.modify_discontent(1, "test")
	check_eq(_calls("strike_started").size(), 1, "staying above the threshold starts nothing new")
	Company.modify_discontent(-10, "test")
	Company.modify_discontent(10, "test")
	check_eq(_calls("strike_started").size(), 2, "crossing the threshold again starts a new strike")


func _test_clamp_and_history() -> void:
	_fresh()
	Company.modify_discontent(-500, "test_floor")
	check_eq(Company.get_discontent(), 0, "discontent never goes below 0")
	Company.modify_discontent(500, "test_ceiling")
	check_eq(Company.get_discontent(), 100, "nor above 100")
	var history: Array[Dictionary] = Company.get_discontent_history()
	check_eq(history.back()["cause"], "test_ceiling", "the history records the cause")


func _test_save_load() -> void:
	_fresh()
	Company.set_production_quota(HIGH_QUOTA)
	Company.modify_discontent(MANUAL_STRIKE_THRESHOLD - Company.get_discontent(), "test")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	var discontent: int = Company.get_discontent()
	_fresh()
	Company.load_state(saved)
	check_eq(Company.get_discontent(), discontent, "discontent survives a JSON save/load")
	check(Company.is_strike_active() and Company.is_quota_excessive(),
			"strike and production quota survive")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


## Avanza una jornada con el reloj real y devuelve el cambio de descontento.
func _day_delta() -> int:
	var before: int = Company.get_discontent()
	GameClock.advance_to_next_day()
	return Company.get_discontent() - before


## Titulares negativos publicados desde el último _clear() (la huelga es noticia, §11.7).
func _bad_news() -> int:
	var count: int = 0
	for call: Array in _calls("news_published"):
		if bool(call[2]) or float(call[1]) < 0.0:
			count += 1
	return count


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _connect_bus() -> void:
	for signal_name: String in SIGNALS:
		EventBus.connect(signal_name, _record.bind(signal_name))


func _record(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	if not _log.has(signal_name):
		_log[signal_name] = []
	_log[signal_name].append(args)


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()
