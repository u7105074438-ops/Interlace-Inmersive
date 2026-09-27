# fundamentals_case.gd — Cuerpo de test_fundamentals: fórmulas §9.2, ironía §9.10 (robo, talento, escándalo), mecha de auditoría y autorización de cifras reportadas.
# PROPIETARIO DE: nada.
# ESCUCHA: fundamentals_updated, audit_fuse_lit, audit_triggered (solo para comprobarlas).
extends TestCase

const EPS := 0.01
const RATIO_EPS := 0.000001
# Números del manual (§9.2) y de market.json starting_fundamentals.
const MANUAL_FUSE_BASE := 8.0
const MANUAL_FUSE_PER_DIVERGENCE := 6.0
const MANUAL_FUSE_MIN := 2
const MANUAL_FUSE_MAX := 8
const START_REVENUE := 2280000.0
const START_COSTS := 1066000.0
const START_PROFIT := 1214000.0
const DIVERGENCES: Array[float] = [0.0, 0.1, 0.25, 0.5, 0.75, 1.0, 1.5]
const AUTHORIZED: Array[String] = ["b10_director", "cfo", "ceo"]
const NOT_AUTHORIZED: Array[String] = ["email_worker_3b", "deputy_cfo", "c10_director",
		"chief_auditor"]
const INFLATION := 0.15
const THEFT := 25000.0
const MAX_AUDIT_ATTEMPTS := 60
const B10_FUSE_WEEKS := 2
const SIGNALS: Array[String] = ["fundamentals_updated", "audit_fuse_lit", "audit_triggered"]

var _log: Dictionary = {}


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	_test_starting_figures()
	_test_theft_losses()
	_test_talent_loss()
	_test_elimination_risk()
	_test_scandal()
	_test_turnover_and_staffing()
	_test_growth()
	_test_fuse_formula()
	_test_reported_authorization()
	_test_fuse_expiry_as_auditor()
	_test_detection_and_demotion()
	_test_daily_recalculation()
	_test_save_load()


# ─── Escenarios ────────────────────────────────────────────────

func _test_starting_figures() -> void:
	var f: Dictionary = Company.get_fundamentals()
	check_near(float(f["revenue"]), START_REVENUE, EPS, "revenue = 24,000 × 95 € × 1.0")
	check_near(float(f["costs"]), START_COSTS, EPS,
			"costs = materials + payroll + overheads + legal + theft + scandal")
	check_near(float(f["profit"]), START_PROFIT, EPS, "profit = revenue − costs")
	check_near(float(f["growth_expectation"]), 0.0, EPS, "no growth expectation on day 1")
	check_near(float(f["risk_factor"]), 0.0, EPS, "no risk on day 1")
	check_near(float(f["revenue"]),
			float(f["units"]) * float(f["avg_price"]) * float(f["brand_strength"]), EPS,
			"§9.2: revenue = units × average price × brand strength")
	check_eq(Company.get_reported_figures(), f, "honest company: reported = fundamentals")


## §9.10 / §11.6: el robo entra en los costes (ventana contable) y resta al beneficio.
func _test_theft_losses() -> void:
	_fresh()
	var before: Dictionary = Company.get_fundamentals()
	var window: int = Database.get_balance_int("empresa.jornadas_ventana_contable")
	Company.add_theft_loss(THEFT)
	var after: Dictionary = Company.get_fundamentals()
	check_near(float(after["theft_losses"]), THEFT / window, EPS,
			"theft losses component = stolen ÷ accounting window")
	check_near(float(after["costs"]) - float(before["costs"]), THEFT / window, EPS,
			"add_theft_loss raises the costs")
	check_near(float(before["profit"]) - float(after["profit"]), THEFT / window, EPS,
			"and lowers the profit by the same amount")
	check_eq(_calls("fundamentals_updated").size(), 1, "the loss is visible at once")
	check_near(Company.get_total_theft_losses(), THEFT, EPS, "total theft losses tracked")
	GameClock.set_time(GameClock.get_day() + window, 12, 0)
	Company.recalculate_fundamentals()
	check_near(float(Company.get_fundamentals()["theft_losses"]), 0.0, EPS,
			"after a full window the loss leaves the daily costs")


## §9.10: expulsar personal cualificado (escalón ≥ 3) reduce calidad e ideas.
func _test_talent_loss() -> void:
	_fresh()
	var quality: float = float(Company.get_fundamentals()["product_quality"])
	var revenue: float = float(Company.get_fundamentals()["revenue"])
	var ideas: float = Company.get_idea_generation_modifier()
	var clerk: String = Company.get_seat_holder("email_worker_3b")
	NPCDirector.remove_npc(clerk, "expelled")
	Company.recalculate_fundamentals()
	check_near(float(Company.get_fundamentals()["product_quality"]), quality, RATIO_EPS,
			"expelling a tier-1 clerk does not touch quality")
	var accountant: String = Company.get_seat_holder("senior_accountant")
	NPCDirector.remove_npc(accountant, "expelled")
	Company.recalculate_fundamentals()
	var loss: float = Database.get_balance_float("empresa.calidad_por_talento_perdido")
	var f: Dictionary = Company.get_fundamentals()
	check_near(float(f["product_quality"]), quality - loss, RATIO_EPS,
			"expelling qualified staff (tier 3) lowers product quality")
	check_near(float(f["revenue"]), revenue * (quality - loss) / quality, EPS,
			"lower quality → fewer units sold → lower revenue")
	check_near(Company.get_idea_generation_modifier(),
			ideas - Database.get_balance_float("empresa.ideas_por_talento_perdido"), RATIO_EPS,
			"and lowers idea generation")
	check_near(IdeaPool.get_generation_modifier(), Company.get_idea_generation_modifier(),
			RATIO_EPS, "IdeaPool reads Company's idea generation modifier")


func _test_elimination_risk() -> void:
	_fresh()
	var risk: float = float(Company.get_fundamentals()["risk_factor"])
	NPCDirector.remove_npc(Company.get_seat_holder("it_technician"), "eliminated")
	Company.recalculate_fundamentals()
	check_near(float(Company.get_fundamentals()["risk_factor"]) - risk,
			Database.get_balance_float("empresa.riesgo_por_eliminacion") + _open_case_risk(risk),
			RATIO_EPS, "an elimination raises the risk factor (§9.10)")


func _test_scandal() -> void:
	_fresh()
	var window: int = Database.get_balance_int("empresa.jornadas_ventana_contable")
	var risk: float = float(Company.get_fundamentals()["risk_factor"])
	EventBus.news_published.emit("TEST_SCANDAL", -0.2, true)
	Company.recalculate_fundamentals()
	var f: Dictionary = Company.get_fundamentals()
	check_near(float(f["risk_factor"]) - risk, _risk_weight("per_negative_news"), RATIO_EPS,
			"an unburied scandal raises the risk factor")
	check_near(float(f["scandal_costs"]),
			Database.get_balance_float("empresa.coste_por_escandalo") / window, EPS,
			"and adds scandal costs")
	EventBus.news_buried.emit("TEST_SCANDAL", "comms_director")
	Company.recalculate_fundamentals()
	f = Company.get_fundamentals()
	check_near(float(f["risk_factor"]), risk, RATIO_EPS, "burying the story removes its risk")
	check_near(float(f["scandal_costs"]), 0.0, EPS, "and its cost")


func _test_turnover_and_staffing() -> void:
	_fresh()
	var f: Dictionary = Company.get_fundamentals()
	Company.vacate_seat("b10_director", "expelled")
	Company.recalculate_fundamentals()
	var turnover: float = _risk_weight("per_executive_turnover")
	check_near(float(Company.get_fundamentals()["risk_factor"]) - float(f["risk_factor"]),
			turnover, RATIO_EPS, "executive turnover raises the risk factor")
	Company.auto_fill_vacancies()
	Company.recalculate_fundamentals()
	check_near(float(Company.get_fundamentals()["risk_factor"]) - float(f["risk_factor"]),
			turnover, RATIO_EPS, "the refill chain ('promoted') is not counted again")
	var factory_seats: int = _department_seats(["factory"])
	Company.vacate_seat("line_operator", "expelled")
	Company.recalculate_fundamentals()
	var weight: float = Database.get_balance_float("empresa.peso_vacantes_fabrica")
	check_near(float(Company.get_fundamentals()["units"]),
			float(f["units"]) * (1.0 - weight / factory_seats), EPS,
			"a factory vacancy lowers the effective efficiency and the units")


func _test_growth() -> void:
	_fresh()
	EventBus.idea_presented.emit("idea_test_1", "player", 10)
	Company.recalculate_fundamentals()
	var per_product: float = Database.get_balance_float("empresa.crecimiento_por_producto")
	check_near(float(Company.get_fundamentals()["growth_expectation"]), per_product, RATIO_EPS,
			"a presented idea is a product in development")
	var first: float = float(Company.get_fundamentals()["profit"])
	EventBus.quarter_closed.emit(1)
	Company.add_theft_loss(THEFT * 100.0)
	var second: float = float(Company.get_fundamentals()["profit"])
	EventBus.quarter_closed.emit(2)
	Company.recalculate_fundamentals()
	var trend: float = (second - first) / absf(first)
	check_near(float(Company.get_fundamentals()["growth_expectation"]),
			per_product + trend * Database.get_balance_float("empresa.peso_tendencia_crecimiento"),
			RATIO_EPS, "growth = trend of the last quarters + products in development")


## §9.2: semanas = 8 − 6 × divergencia, acotado a [2, 8].
func _test_fuse_formula() -> void:
	for d: float in DIVERGENCES:
		var weeks: float = MANUAL_FUSE_BASE - MANUAL_FUSE_PER_DIVERGENCE * minf(d, 1.0)
		var expected: int = clampi(roundi(weeks), MANUAL_FUSE_MIN, MANUAL_FUSE_MAX)
		check_eq(Company.compute_fuse_weeks(d), expected, "fuse for divergence %.2f" % d)
	var real: Dictionary = Company.get_fundamentals()
	var reported: Dictionary = _inflated(real)
	check_near(Company.compute_divergence(real, reported),
			(float(reported["profit"]) - float(real["profit"])) / float(real["profit"]), RATIO_EPS,
			"divergence = largest relative gap (profit here)")


func _test_reported_authorization() -> void:
	_fresh()
	var real: Dictionary = Company.get_fundamentals()
	for occupation_id: String in NOT_AUTHORIZED:
		_set_player(occupation_id)
		check(not Company.can_set_reported_figures(), "%s may not set figures" % occupation_id)
		Company.set_reported_figures(_inflated(real))
	check_near(float(Company.get_reported_figures()["revenue"]), float(real["revenue"]), EPS,
			"unauthorised posts cannot change the reported figures")
	check(_calls("audit_fuse_lit").is_empty(), "and light no fuse")
	for occupation_id: String in AUTHORIZED:
		_set_player(occupation_id)
		check(Company.can_set_reported_figures(), "%s may set figures" % occupation_id)
	Company.set_reported_figures(_inflated(real))
	check_near(float(Company.get_reported_figures()["revenue"]),
			float(real["revenue"]) * (1.0 + INFLATION), EPS, "the CEO's figures are reported")
	var divergence: float = Company.compute_divergence(real, _inflated(real))
	check_eq(_calls("audit_fuse_lit"), [[divergence, Company.compute_fuse_weeks(divergence)]],
			"any divergence lights the fuse: audit_fuse_lit(divergence, weeks)")
	_fresh()
	_set_player("b10_director")
	Company.set_reported_figures(_inflated(Company.get_fundamentals()))
	check_eq(_calls("audit_fuse_lit").back()[1],
			mini(Company.compute_fuse_weeks(divergence), B10_FUSE_WEEKS),
			"§9.9: the B10 director's sales figures carry a two-week fuse")


## El jugador como Auditor Jefe: probabilidad nula (§9.2).
func _test_fuse_expiry_as_auditor() -> void:
	_fresh()
	_set_player("cfo")
	Company.set_reported_figures(_inflated(Company.get_fundamentals()))
	var weeks: int = int(Company.get_audit_fuse()["weeks_left"])
	_set_player("chief_auditor")
	check_near(Company.get_audit_detection_probability(), 0.0, RATIO_EPS,
			"detection probability is zero when the player is Chief Auditor")
	for _i: int in weeks - 1:
		EventBus.week_closed.emit(1)
	check(_calls("audit_triggered").is_empty(), "no audit before the fuse burns out")
	EventBus.week_closed.emit(1)
	check_eq(_calls("audit_triggered"), [[false]], "audit_triggered(false) when the fuse expires")
	check(Company.get_audit_fuse().is_empty(), "the fuse is spent")


func _test_detection_and_demotion() -> void:
	_fresh()
	var auditor: String = Company.get_seat_holder("chief_auditor")
	var factor: float = Database.get_balance_float("empresa.factor_deteccion_auditoria")
	check_near(Company.get_audit_detection_probability(),
			NPCDirector.get_trait(auditor, "perception") / 100.0 * factor, RATIO_EPS,
			"probability ∝ the Chief Auditor's perception")
	_set_player("b10_director")
	var found: bool = false
	for _attempt: int in MAX_AUDIT_ATTEMPTS:
		Company.set_reported_figures(_inflated(Company.get_fundamentals()))
		while not Company.get_audit_fuse().is_empty():
			EventBus.week_closed.emit(1)
		found = bool(_calls("audit_triggered").back()[0])
		if found:
			break
	check(found, "the internal audit eventually finds the discrepancy")
	check_near(float(Company.get_last_audit()["divergence"]),
			Company.compute_divergence(Company.get_fundamentals(),
			_inflated(Company.get_fundamentals())), RATIO_EPS,
			"get_last_audit() keeps the audited divergence")
	check_eq(PlayerState.get_occupation().id, "purchasing_chief",
			"figures that surface demote the B10 director (§6.1)")
	var f: Dictionary = Company.get_fundamentals()
	check_near(float(Company.get_reported_figures()["revenue"]), float(f["revenue"]), EPS,
			"the figures are restated after the audit")


func _test_daily_recalculation() -> void:
	_fresh()
	GameClock.advance_to_next_day()
	check(_calls("fundamentals_updated").size() >= 1, "fundamentals are recalculated every day")
	var call: Array = _calls("fundamentals_updated").back()
	var f: Dictionary = Company.get_fundamentals()
	check_eq(call, [f["revenue"], f["costs"], f["risk_factor"]],
			"fundamentals_updated(revenue, costs, risk)")


func _test_save_load() -> void:
	_fresh()
	_set_player("cfo")
	Company.add_theft_loss(THEFT)
	Company.modify_brand_strength(0.1)
	NPCDirector.remove_npc(Company.get_seat_holder("senior_accountant"), "expelled")
	Company.recalculate_fundamentals()
	Company.set_reported_figures(_inflated(Company.get_fundamentals()))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	var fundamentals: Dictionary = Company.get_fundamentals()
	var reported: Dictionary = Company.get_reported_figures()
	var fuse: Dictionary = Company.get_audit_fuse()
	var ideas: float = Company.get_idea_generation_modifier()
	_fresh()
	Company.load_state(saved)
	check_eq(Company.get_fundamentals(), fundamentals, "fundamentals survive a JSON save/load")
	check_eq(Company.get_reported_figures(), reported, "reported figures survive")
	check_eq(Company.get_audit_fuse(), fuse, "the audit fuse survives")
	check_near(Company.get_idea_generation_modifier(), ideas, RATIO_EPS, "idea modifier survives")
	Company.recalculate_fundamentals()
	check_near(float(Company.get_fundamentals()["profit"]), float(fundamentals["profit"]), EPS,
			"recomputing after load gives the same profit")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


func _set_player(occupation_id: String) -> void:
	PlayerState.set_occupation(occupation_id, "test")


func _inflated(real: Dictionary) -> Dictionary:
	var out: Dictionary = real.duplicate()
	out["revenue"] = float(real["revenue"]) * (1.0 + INFLATION)
	out["profit"] = float(out["revenue"]) - float(real["costs"])
	return out


func _risk_weight(key: String) -> float:
	return float(Database.get_market_params()["risk_factor_weights"][key])


## Si Security abrió un caso por la eliminación, su peso también entra en el riesgo.
func _open_case_risk(_before: float) -> float:
	return _risk_weight("per_open_investigation") * Security.get_active_investigations().size()


func _department_seats(departments: Array[String]) -> int:
	var count: int = 0
	for seat: Dictionary in Company.get_all_seats():
		var occupation: OccupationData = Database.get_occupation(str(seat["occupation_id"]))
		if departments.has(str(occupation.extra.get("department", ""))):
			count += 1
	return count


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
