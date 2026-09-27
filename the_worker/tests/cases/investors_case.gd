# investors_case.gd — Cuerpo de test_investors: agregado §9.7, tabla de factores, estrategias §9.6, regla 60/40 y reacción de la presentación §9.5 (una por trimestre, aliados sobornados o chantajeados, A.S.S.I.S.T., incomparecencia), campañas activistas, racha R28+, cartera con efectivo, dividendos y paquete R30 §9.11.
# PROPIETARIO DE: nada.
# ESCUCHA: investor_confidence_changed, quarter_reported, crime_committed, tracking_event_recorded, assist_used, results_presentation_due, bribe_result (solo para comprobarlas).
extends TestCase

const EPS := 0.0001
const HOWARD := "inv_howard_grange"
const TANIA := "inv_tania_brekke"
const VICTOR := "inv_victor_sallow"
const MARGARET := "inv_margaret_ash"
const NEIL := "inv_neil_deming"
const BOBBY := "inv_bobby_kerr"
const RIVAL := "npc_rival_x"
# §24.4: confianza inicial de los seis inversores.
const MANUAL_CONFIDENCE: Dictionary = {
	HOWARD: 50, TANIA: 50, VICTOR: 40, MARGARET: 45, NEIL: 60, BOBBY: 30,
}
# §9.7: [efecto leve, efecto severo] por factor.
const MANUAL_FACTORS: Dictionary = {
	"results_above_expected": [8, 15], "favourable_press": [3, 6],
	"lounge_personal_contact": [5, 5], "insider_tip_to_hunter": [12, 12],
	"results_below_expected": [-10, -20], "public_scandal": [-15, -30],
	"falsification_discovered": [-25, -40],
}
# §9.5: niveles de preparación y pesos de la calidad.
const MANUAL_LEVELS: Dictionary = {
	"none": 0.0, "assist": 0.5, "stolen_coo_report": 0.8, "real_work": 1.0,
}
const W_PREP := 0.4
const W_REP := 0.3
const W_ALLIES := 0.3
const W_QUALITY := 0.6
const W_FIGURES := 0.4
const NEUTRAL := 0.5
# Capital (M€) de investors.json. El inversor de valor no escucha la presentación, así que los
# demás la oyen con W = 0,6 × 16,6 ÷ 12,1 = 0,82314 (la media ponderada por capital oye 60/40).
const CAPITAL_M: Dictionary = {
	HOWARD: 4.5, TANIA: 2.75, VICTOR: 1.2, MARGARET: 3.0, NEIL: 5.0, BOBBY: 0.15,
}
const QUALITY_SHARE := 0.6 * 16.6 / 12.1
# Reacciones calculadas a mano con la tabla §9.7 (banda neutra 0,05; umbral del pasivo 0,25):
#  calidad 1,0 · cifras 0,5 → oyentes perciben 0,9116: +14; el de valor ve 0,5: 0.
#  calidad 0,5 · cifras 1,0 → oyentes 0,5884: +9 (el pasivo no llega a su umbral); valor 1,0: +15.
#  calidad 0,0 · cifras 0,5 → oyentes 0,0884: −18; valor 0.
#  calidad 0,9 · cifras 0,5 → oyentes 0,8293: +12; valor 0.
const REACTION_QUALITY_UP: Dictionary = {
	HOWARD: 0, TANIA: 14, VICTOR: 14, MARGARET: 14, NEIL: 14, BOBBY: 14,
}
const REACTION_FIGURES_UP: Dictionary = {
	HOWARD: 15, TANIA: 9, VICTOR: 9, MARGARET: 9, NEIL: 0, BOBBY: 9,
}
const REACTION_QUALITY_DOWN: Dictionary = {
	HOWARD: 0, TANIA: -18, VICTOR: -18, MARGARET: -18, NEIL: -18, BOBBY: -18,
}
const REACTION_BRILLIANT: Dictionary = {
	HOWARD: 0, TANIA: 12, VICTOR: 12, MARGARET: 12, NEIL: 12, BOBBY: 12,
}
# Respuesta agregada (Σ capital × Δ ÷ Σ capital) de las dos primeras filas: 10,205 y 7,916.
const AGG_QUALITY_UP := 12.1 * 14.0 / 16.6
const AGG_FIGURES_UP := (4.5 * 15.0 + 7.1 * 9.0) / 16.6
# Δsentimiento de REACTION_BRILLIANT: 12 × 12,1/16,6 + 12 × (3 − 1) × 0,05 = 9,947 → ÷ 100.
const BRILLIANT_SENTIMENT := (12.0 * 12.1 / 16.6 + 12.0 * 2.0 * 0.05) / 100.0
const Q1_TARGET := 52.0
const R25_OCCUPATION := "comms_director"
const R24_OCCUPATION := "security_director"
const R28_OCCUPATION := "cfo"
const R30_OCCUPATION := "board_investor"
const STAKE_PRICE := 250000
const SHARES_PER_VOTE := 5000
const PAYOUT := 0.3
const TOTAL_SHARES := 40000000.0
const FISCAL_DAYS := 100.0
const TIP_PAYMENT := 2000
const QUESTION_FAVOUR := "praise_to_superior"
# §8.2 con la referencia diaria de investors.json × 15 (elogiarte ante un superior).
const MANUAL_BRIBE_PRICES: Dictionary = {TANIA: 37500, VICTOR: 6000, BOBBY: 900}
const CHANNEL := "phone_call"
const FORCED_ACCEPT: Dictionary = {"roll": 0.0}
const LEVERAGE := "photos_from_the_lounge"
const ASSIST_PENALTY := -6.0
const TANIA_DELAY_HOURS := 3
const MINUTES_PER_HOUR := 60.0
const START_REPUTATION := 50.0

var _conf_events: Array = []
var _reported: Array = []
var _crimes: Array = []
var _tracking: Array = []
var _assists: Array = []
var _due: Array[int] = []
var _bribes: Array = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	_connect_listeners()
	_test_roster_and_aggregate()
	_test_factor_table()
	_test_press_by_strategy()
	_test_burial_beats_the_slow_reader()
	_test_trend_follows_momentum()
	_test_tip_and_lounge()
	await _test_falsification_discovered()
	_test_presentation_quality_formula()
	_test_sixty_forty_rule()
	_test_venality()
	_test_presentation_once_per_quarter()
	_test_assist_presentation()
	_test_results_presentation_phases()
	_test_no_show_and_npc_presenter()
	_test_quarter_streak_and_board_pressure()
	_test_activist_campaigns()
	_test_portfolio_cash_and_board_stake()
	_test_save_load_owned_state()
	check(Market.get_config_mismatches().is_empty(),
			"market.json duplicates match balance.json %s" % str(Market.get_config_mismatches()))


func _connect_listeners() -> void:
	EventBus.investor_confidence_changed.connect(
			func(id: String, o: int, n: int) -> void: _conf_events.append([id, o, n]))
	EventBus.quarter_reported.connect(
			func(real: Dictionary, rep: Dictionary) -> void: _reported.append([real, rep]))
	EventBus.crime_committed.connect(
			func(t: String, _r: String, d: Dictionary) -> void: _crimes.append([t, d]))
	EventBus.tracking_event_recorded.connect(
			func(a: String, n: int, s: String) -> void: _tracking.append([a, n, s]))
	EventBus.assist_used.connect(func(t: String, r: String) -> void: _assists.append([t, r]))
	EventBus.results_presentation_due.connect(func(q: int) -> void: _due.append(q))
	EventBus.bribe_result.connect(
			func(id: String, ok: bool, o: String) -> void: _bribes.append([id, ok, o]))


func _test_roster_and_aggregate() -> void:
	check_eq(Market.get_investors().size(), 6, "six named investors")
	var weighted: float = 0.0
	var capital: float = 0.0
	for inv: InvestorData in Market.get_investors():
		check_eq(Market.get_investor_confidence(inv.id), MANUAL_CONFIDENCE[inv.id],
				"%s starts at the §24.4 confidence" % inv.name)
		weighted += float(MANUAL_CONFIDENCE[inv.id]) * float(inv.capital)
		capital += float(inv.capital)
	check_near(Market.get_aggregate_confidence(), weighted / capital, EPS,
			"aggregate = Σ(confidence × capital) ÷ Σ capital")
	check_near(Market.get_aggregate_confidence(), 850.0 / 16.6, 0.001, "starting aggregate ≈ 51.20")
	check_near(Market.get_quarterly_target(), Q1_TARGET, EPS, "Q1 target from market.json = 52")
	check(not Market.is_meeting_target(), "51.2 < 52: the company starts below target")
	check_near(Market.get_target_for_quarter(3), 58.0, EPS, "Q3 target = 58")
	check_near(Market.get_target_for_quarter(12), 68.0, EPS, "after the last quarter the target stays 68")
	_conf_events.clear()
	var before: float = Market.get_aggregate_confidence()
	Market.modify_investor_confidence(NEIL, 10, "test")
	check_near(Market.get_aggregate_confidence() - before, 10.0 * 5000000.0 / capital, EPS,
			"+10 on Neil Deming moves the aggregate by 10 × his capital share")
	check(_conf_events.size() == 1 and _conf_events[0] == [NEIL, 60, 70],
			"investor_confidence_changed(neil, 60, 70)")
	Market.modify_investor_confidence(NEIL, 500, "test")
	check_eq(Market.get_investor_confidence(NEIL), 100, "confidence clamps at 100")


func _test_factor_table() -> void:
	for factor: String in MANUAL_FACTORS:
		var bounds: Array = MANUAL_FACTORS[factor]
		check_eq(Market.get_factor_delta(factor, 0.0), bounds[0], "%s mild = %d" % [factor, bounds[0]])
		check_eq(Market.get_factor_delta(factor, 1.0), bounds[1], "%s severe = %d" % [factor, bounds[1]])


## Valor ignora el sentimiento; momentum y cazador leen titulares; el activista reacciona a
## escándalos; el pasivo solo a desastres.
func _test_press_by_strategy() -> void:
	new_run(DEFAULT_SEED, false)
	NewsFeed.publish("NEWS_FABRICATED_PRAISE", 0.1, false)
	check_eq(Market.get_investor_confidence(TANIA), MANUAL_CONFIDENCE[TANIA],
			"Tania Brekke has not reacted yet (reaction_delay_hours = 3)")
	_let_hours_pass(TANIA_DELAY_HOURS)
	_expect_changes({HOWARD: 0, TANIA: 4, VICTOR: 4, MARGARET: 0, NEIL: 0, BOBBY: 4},
			"favourable press +0.1 (a third of the 0.3 reference → +4 in 3..6)")
	var snapshot: Dictionary = _confidences()
	NewsFeed.publish("NEWS_INVESTIGATION_OPENED", -0.1, true)
	_let_hours_pass(TANIA_DELAY_HOURS)
	_expect_changes_from(snapshot, {HOWARD: 0, TANIA: -20, VICTOR: -20, MARGARET: -20,
			NEIL: 0, BOBBY: -20}, "minor scandal −0.1 → −20 in −15..−30")
	snapshot = _confidences()
	NewsFeed.publish("NEWS_BODY_FOUND", -0.3, true)
	check_eq(Market.get_investor_confidence(NEIL) - int(snapshot[NEIL]), -30,
			"the passive fund reacts only to a disaster (−0.3 ≥ 0.25): −30")
	check_eq(Market.get_investor_confidence(HOWARD), int(snapshot[HOWARD]),
			"the value investor ignores even a disaster headline")
	_let_hours_pass(TANIA_DELAY_HOURS)
	snapshot = _confidences()
	NewsFeed.fabricate(RIVAL, "NEWS_FABRICATED_SCANDAL")
	_let_hours_pass(TANIA_DELAY_HOURS)
	check_eq(_confidences(), snapshot, "a scandal about one employee does not move investors")


## Enterrar a tiempo también llega a los inversores: quien reacciona en horas ya no reacciona.
func _test_burial_beats_the_slow_reader() -> void:
	new_run(DEFAULT_SEED, false)
	var buried: String = NewsFeed.publish("NEWS_INVESTIGATION_OPENED", -0.1, true)
	check_eq(Market.get_investor_confidence(BOBBY), int(MANUAL_CONFIDENCE[BOBBY]) - 20,
			"Bobby reacts to the scandal at once")
	NewsFeed.bury(buried, "npc_bree_nash")
	_let_hours_pass(TANIA_DELAY_HOURS)
	check_eq(Market.get_investor_confidence(TANIA), MANUAL_CONFIDENCE[TANIA],
			"buried within three hours, the scandal never reaches Tania Brekke")


func _test_trend_follows_momentum() -> void:
	new_run(DEFAULT_SEED, false)
	NewsFeed.publish("NEWS_EVENT_RECESSION", -0.6, false)
	for _d: int in 6:
		_run_trading_day()
	check(Market.get_momentum() < 0.0, "the crash creates negative momentum")
	check(Market.get_investor_confidence(TANIA) < int(MANUAL_CONFIDENCE[TANIA]),
			"the momentum investor follows the falling trend")
	check_eq(Market.get_investor_confidence(HOWARD), MANUAL_CONFIDENCE[HOWARD],
			"the value investor ignores the trend")
	check_eq(Market.get_investor_confidence(NEIL), MANUAL_CONFIDENCE[NEIL],
			"the passive fund ignores a non-scandal slide")


func _test_tip_and_lounge() -> void:
	new_run(DEFAULT_SEED, false)
	_crimes.clear()
	var money: int = PlayerState.get_money()
	var sold: Dictionary = MarketTrading.sell_tip(VICTOR)
	check(bool(sold["ok"]) and int(sold["delta"]) == 12, "a tip gives +12 to the information hunter")
	check_eq(PlayerState.get_money(), money + TIP_PAYMENT, "Victor pays for the tip (2,000 €)")
	check(_crimes.size() == 1 and _crimes[0][0] == "insider_trade", "every tip is evidence (crime_committed)")
	check(not bool(MarketTrading.sell_tip(HOWARD)["ok"]), "only the hunter buys tips")
	check_eq(PlayerState.get_money(), money + TIP_PAYMENT, "…and nobody else pays for one")
	check_eq(Market.record_lounge_contact(HOWARD), 5, "lounge personal contact +5")


func _test_falsification_discovered() -> void:
	new_run(DEFAULT_SEED, false)
	var snapshot: Dictionary = _confidences()
	var sentiment_before: float = Market.get_investor_sentiment()
	EventBus.audit_triggered.emit(true)
	await wait_frames(2)
	var all_hit: bool = true
	for id: String in snapshot:
		var delta: int = Market.get_investor_confidence(id) - int(snapshot[id])
		var clamped: bool = Market.get_investor_confidence(id) == 0
		all_hit = all_hit and ((delta <= -25 and delta >= -40) or clamped)
	check(all_hit, "falsification discovered: −25 to −40 for every investor")
	check_eq(Market.get_investor_confidence(TANIA), int(snapshot[TANIA]) - 25,
			"the fraud headline is not counted a second time as a public scandal")
	check(Market.is_credibility_lost(), "permanent loss of credibility")
	check_eq(Market.record_lounge_contact(HOWARD), 2, "after the fraud, +5 only yields +2")
	check(Market.get_permanent_multiple_penalty() >= Database.get_balance_float(
			"mercado.penalizacion_multiplo_fraude"), "the fraud permanently cuts the multiple")
	check(Market.get_investor_sentiment() < sentiment_before,
			"investors falling below 25 dump shares (negative sentiment impulse)")


func _test_presentation_quality_formula() -> void:
	new_run(DEFAULT_SEED, false)
	check_eq(Market.get_preparation_levels(), MANUAL_LEVELS, "four preparation levels 0/0.5/0.8/1.0")
	var reputation: float = PlayerState.get_reputation()
	var ok: bool = true
	for level: String in MANUAL_LEVELS:
		for allies: int in [0, 2, 6, 9]:
			var expected: float = W_PREP * float(MANUAL_LEVELS[level]) + W_REP * reputation / 100.0 \
					+ W_ALLIES * minf(float(allies) / 6.0, 1.0)
			ok = ok and absf(Market.compute_presentation_quality(MANUAL_LEVELS[level], allies)
					- expected) < EPS
	check(ok, "quality = 0.4 × preparation + 0.3 × reputation/100 + 0.3 × allies ratio")
	check_near(Market.figures_score_for(110.0, 100.0), 0.75, EPS, "+10 % vs expected → 0.75")
	check_near(Market.figures_score_for(100.0, 100.0), NEUTRAL, EPS, "in line → 0.5")
	check_near(Market.figures_score_for(80.0, 100.0), 0.0, EPS, "−20 % → 0.0")
	check_near(Market.figures_score_for(130.0, 100.0), 1.0, EPS, "clamped at 1.0")


## §9.5: "la calidad pesa el sesenta por ciento y las cifras el cuarenta", con la lente de cada
## estrategia (el de valor solo ve cifras) y el agregado por capital fiel a 60/40.
func _test_sixty_forty_rule() -> void:
	new_run(DEFAULT_SEED, false)
	check_near(Market.compute_presentation_outcome(1.0, 0.0), W_QUALITY, EPS, "outcome: quality weighs 0.6")
	check_near(Market.compute_presentation_outcome(0.0, 1.0), W_FIGURES, EPS, "outcome: figures weigh 0.4")
	check_near(Market.get_presentation_quality_share(HOWARD), 0.0, EPS,
			"the value investor is immune to the presentation (figures only)")
	check_near(Market.get_presentation_quality_share(TANIA), QUALITY_SHARE, EPS,
			"the others hear the quality with W = 0.6 × 16.6 ÷ 12.1 = 0.823")
	var linear_ok: bool = true
	for pair: Array in [[1.0, 0.5], [0.2, 0.9], [0.7, 0.1], [0.0, 1.0]]:
		var weighted: float = 0.0
		for id: String in CAPITAL_M:
			weighted += float(CAPITAL_M[id]) * Market.get_perceived_outcome(id, pair[0], pair[1])
		linear_ok = linear_ok and absf(weighted / 16.6 - (W_QUALITY * pair[0] + W_FIGURES * pair[1])) < EPS
	check(linear_ok, "capital-weighted perceived outcome = exactly 0.6 × quality + 0.4 × figures")
	check_eq(Market.compute_presentation_reaction(1.0, 0.5), REACTION_QUALITY_UP,
			"quality 1.0 with neutral figures: +14 each, the value investor unmoved")
	check_eq(Market.compute_presentation_reaction(0.5, 1.0), REACTION_FIGURES_UP,
			"great figures with an average show: value +15, others +9, passive below its threshold")
	check_eq(Market.compute_presentation_reaction(0.0, 0.5), REACTION_QUALITY_DOWN,
			"an unprepared presentation: −18 for everyone who listens")
	check_eq(Market.compute_presentation_reaction(0.5, 0.5).values(), [0, 0, 0, 0, 0, 0],
			"an average presentation of in-line figures moves nobody")
	var agg_quality: float = _aggregate_of(Market.compute_presentation_reaction(1.0, 0.5))
	var agg_figures: float = _aggregate_of(Market.compute_presentation_reaction(0.5, 1.0))
	check_near(agg_quality, AGG_QUALITY_UP, 0.001, "aggregate response to quality alone = 10.2")
	check_near(agg_figures, AGG_FIGURES_UP, 0.001, "aggregate response to figures alone = 7.9")
	var share: float = agg_quality / (agg_quality + agg_figures)
	check(share > 0.5 and share < 0.65,
			"the presentation drives the aggregate more than the figures (%.0f/%.0f, manual 60/40)"
			% [share * 100.0, (1.0 - share) * 100.0])


func _test_venality() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.add_money(200000, "test")
	for id: String in [HOWARD, NEIL, MARGARET]:
		check(not Market.is_investor_bribable(id), "%s cannot be bribed (§24.4)" % id)
	for id: String in MANUAL_BRIBE_PRICES:
		check_eq(Market.get_investor_base_bribe_price(id, QUESTION_FAVOUR), MANUAL_BRIBE_PRICES[id],
				"%s: §8.2 base price = daily reference × 15" % id)
	_bribes.clear()
	var money: int = PlayerState.get_money()
	var refused: Dictionary = ResultsPresentation.bribe_investor(HOWARD, 90000, CHANNEL, FORCED_ACCEPT)
	check(not bool(refused["ok"]) and _bribes.is_empty() and PlayerState.get_money() == money,
			"an unbribable investor is never offered anything (no signals, no money)")
	var paid: int = 0
	for id: String in MANUAL_BRIBE_PRICES:
		var price: int = ResultsPresentation.investor_bribe_price(id)
		check(price >= int(MANUAL_BRIBE_PRICES[id]), "%s: fair price %d ≥ base price" % [id, price])
		var result: Dictionary = ResultsPresentation.bribe_investor(id, price, CHANNEL, FORCED_ACCEPT)
		check(bool(result.get("accepted", false)), "%s accepts to ask a favourable question" % id)
		paid += price
	check_eq(PlayerState.get_money(), money - paid, "the bribes are paid in cash")
	var allies: Array[String] = [TANIA, VICTOR, BOBBY]
	check_eq(Market.get_investor_allies(), allies, "bribed investors become allies in the room")
	check(not ResultsPresentation.blackmail_investor(HOWARD, LEVERAGE), "Howard cannot be blackmailed")
	check(not ResultsPresentation.blackmail_investor(MARGARET, ""), "blackmail needs material")
	check(ResultsPresentation.blackmail_investor(MARGARET, LEVERAGE), "Margaret Ash can be blackmailed")
	check(Market.is_investor_coerced(MARGARET) and Market.is_investor_ally(MARGARET),
			"the blackmailed activist is coerced and counts as an ally")
	check_eq(ResultsPresentation.new(1).get_allies_present(), 4, "four allies for this quarter")


## Aliados de verdad, una presentación por trimestre y solo el día de resultados.
func _test_presentation_once_per_quarter() -> void:
	check(Market.conduct_quarterly_presentation(1.0, 6).is_empty() and not Market.can_present_results(),
			"no presentation before the results day")
	_goto_presentation_day()
	PlayerState.modify_reputation(100.0, "test")
	var before: Dictionary = _confidences()
	var result: Dictionary = Market.conduct_quarterly_presentation(1.0, 6)
	check_eq(int(result.get("allies_counted", -1)), 4, "allies_present is capped at the real allies")
	check_near(float(result.get("quality", 0.0)), 0.9, EPS, "quality = 0.4 + 0.3 + 0.3 × 4/6 = 0.9")
	var changes: Dictionary = result.get("confidence_changes", {})
	var all_match: bool = true
	for id: String in REACTION_BRILLIANT:
		var expected: int = clampi(int(before[id]) + int(REACTION_BRILLIANT[id]), 0, 100) - int(before[id])
		all_match = all_match and int(changes.get(id, 99)) == expected
	check(all_match, "a brilliant presentation: +12 for every listener, the value investor unmoved")
	check_near(float(result["sentiment_delta"]), BRILLIANT_SENTIMENT, 0.0005,
			"capital-weighted confidence change (+ Bobby's reach) becomes market sentiment ≈ +0.0995")
	var aggregate: float = Market.get_aggregate_confidence()
	check(Market.conduct_quarterly_presentation(1.0, 6).is_empty(), "a second presentation is refused")
	check_near(Market.get_aggregate_confidence(), aggregate, EPS, "…and changes nothing")
	_due.clear()
	EventBus.hour_passed.emit(11, Market.get_current_day())
	check(_due.is_empty(), "no results_presentation_due once the player has presented")


func _test_assist_presentation() -> void:
	check_eq(ResultsPresentation.roll_assist_outcome(0.10), "evident_failure", "A.S.S.I.S.T. 15 % failure")
	check_eq(ResultsPresentation.roll_assist_outcome(0.30), "excellent", "25 % excellent")
	check_eq(ResultsPresentation.roll_assist_outcome(0.60), "acceptable", "60 % acceptable")
	new_run(DEFAULT_SEED, false)
	_goto_presentation_day()
	PlayerState.modify_reputation(START_REPUTATION, "test")
	var p: ResultsPresentation = ResultsPresentation.new(1)
	p.keep_real_figures()
	p.confirm_figures()
	check(p.select_preparation("assist"), "A.S.S.I.S.T. level selected")
	p.force_assist_outcome("evident_failure")
	_assists.clear()
	var result: Dictionary = p.present()
	check(_assists.size() == 1 and _assists[0] == ["results_presentation", "evident_failure"],
			"using A.S.S.I.S.T. emits assist_used (digital record for IT)")
	var perceptive: Array[String] = [HOWARD, VICTOR, MARGARET]
	check_eq(result["assist_detected_by"], perceptive,
			"investors with perception > 60 spot the invented figures")
	check_near(PlayerState.get_reputation(), START_REPUTATION + ASSIST_PENALTY, EPS,
			"detected: reputation −6")
	check_near(float(result["quality"]), W_REP * (START_REPUTATION + ASSIST_PENALTY) / 100.0, EPS,
			"an evident failure counts as no preparation")


func _test_results_presentation_phases() -> void:
	new_run(DEFAULT_SEED, false)
	var inflated: Dictionary = ResultsPresentation.inflate_figures(
			{"revenue": 100.0, "costs": 60.0, "profit": 40.0}, 0.1)
	check(is_equal_approx(float(inflated["revenue"]), 110.0)
			and is_equal_approx(float(inflated["profit"]), 50.0),
			"inflating revenue 10 % raises reported profit to revenue − real costs")
	var p: ResultsPresentation = ResultsPresentation.new(1)
	check(not p.select_preparation("real_work"), "phase 1 must be confirmed first")
	p.keep_real_figures()
	p.confirm_figures()
	check_eq(p.phase, ResultsPresentation.Phase.PRESENTATION, "phase 2: presentation")
	check(not p.select_preparation("bogus_level"), "unknown preparation level rejected")
	check(p.select_preparation("real_work"), "real work selected")
	check(p.present().is_empty() and p.phase == ResultsPresentation.Phase.PRESENTATION,
			"presenting on a normal day is refused")
	_goto_presentation_day()
	check_near(p.get_quality_preview(), Market.compute_presentation_quality(1.0, 0), EPS,
			"quality preview uses Market's formula and the real allies (none)")
	_tracking.clear()
	var result: Dictionary = p.present()
	check(result.has("quality") and result.has("confidence_changes") and result.has("sentiment_delta"),
			"present() returns {quality, confidence_changes, sentiment_delta}")
	check_eq(p.phase, ResultsPresentation.Phase.REACTION, "phase 3: reaction")
	check(_tracking.size() == 1 and _tracking[0] == ["sweat", 5, "presentation_prepared"],
			"a presentation prepared with real work records +5 SWEAT")
	var rows: Array[Dictionary] = p.get_reaction_rows()
	var consistent: bool = rows.size() == 6
	for row: Dictionary in rows:
		consistent = consistent and int(row["delta"]) == int(row["after"]) - int(row["before"]) \
				and int(row["delta"]) == int((result["confidence_changes"] as Dictionary)[row["investor_id"]])
	check(consistent, "one reaction row per investor, matching the confidence changes")
	check(p.get_summary().has("meeting_target"), "summary includes the quarterly target check")
	p.finish()
	check_eq(p.phase, ResultsPresentation.Phase.FINISHED, "presentation closed")


## R28+ que no presenta: incomparecencia (sin preparar, sin aliados). Por debajo, presenta un NPC.
func _test_no_show_and_npc_presenter() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(R28_OCCUPATION, "test")
	var before: Dictionary = _confidences()
	EventBus.quarter_closed.emit(1)
	var last: Dictionary = Market.get_last_presentation()
	check_eq(last.get("presenter", ""), "no_show", "the R28 player skipped the results: a no-show")
	check_near(float(last.get("quality", 1.0)), 0.0, EPS, "no preparation, no reputation, no allies")
	_expect_changes_from(before, REACTION_QUALITY_DOWN, "no-show")
	new_run(DEFAULT_SEED, false)
	EventBus.quarter_closed.emit(1)
	last = Market.get_last_presentation()
	check(last.get("presenter", "") == "npc" and _confidences() == MANUAL_CONFIDENCE,
			"below R28 an NPC presents: a neutral quarter")


func _test_quarter_streak_and_board_pressure() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(R28_OCCUPATION, "test")
	check_eq(PlayerState.get_rank(), 28, "player promoted to CFO (R28) for the test")
	_reported.clear()
	EventBus.quarter_closed.emit(1)
	check_eq(_reported.size(), 1, "Market emits quarter_reported once at the quarter close")
	check_eq(Market.get_bad_quarters_streak(), 1, "first quarter below target")
	check(not Market.is_player_under_campaign(), "Margaret (27) has not turned against the player")
	check(not Market.is_board_pressure_triggered(), "one bad quarter is not enough")
	EventBus.quarter_closed.emit(2)
	check_eq(Market.get_bad_quarters_streak(), 2, "second consecutive quarter below target")
	check(Market.is_board_pressure_triggered(), "two bad quarters at R28+ → demotion or expulsion")
	check(PlayerState.get_rank() < 28, "Company acts on quarter_reported: the CFO is demoted")
	PlayerState.set_occupation(R28_OCCUPATION, "test")
	for inv: InvestorData in Market.get_investors():
		Market.modify_investor_confidence(inv.id, 100, "test")
	EventBus.quarter_closed.emit(3)
	check_eq(Market.get_bad_quarters_streak(), 0, "meeting the target resets the streak")
	new_run(DEFAULT_SEED, false)
	EventBus.quarter_closed.emit(1)
	check_eq(Market.get_bad_quarters_streak(), 0, "below R28 bad quarters do not count")


func _test_activist_campaigns() -> void:
	new_run(DEFAULT_SEED, false)
	check(not Market.direct_activist(MARGARET, RIVAL), "the activist cannot be steered without leverage")
	ResultsPresentation.blackmail_investor(MARGARET, LEVERAGE)
	check(not Market.direct_activist(TANIA, RIVAL), "only the activist runs campaigns")
	check(Market.direct_activist(MARGARET, RIVAL) and Market.get_activist_target(MARGARET) == RIVAL,
			"the blackmailed activist is steered against a rival")
	var before: Dictionary = _confidences()
	check_eq(NewsFeed.publish_campaign_news().size(), 1, "the campaign reaches the press once")
	check(NewsFeed.publish_campaign_news().is_empty(), "…and is not announced twice")
	check_near(NewsFeed.get_suspicion_about(RIVAL),
			Database.get_balance_float("noticias.sospecha_fabricado_objetivo"), EPS,
			"the campaign reaches the press as a scandal about the rival")
	check_eq(_confidences(), before, "a campaign against one executive does not move investors")
	EventBus.npc_removed.emit(RIVAL, "expelled")
	check(Market.get_activist_campaigns().is_empty(), "the campaign ends when its target leaves")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(R28_OCCUPATION, "test")
	Market.modify_investor_confidence(MARGARET, -30, "test")
	check(Market.is_player_under_campaign(), "losing confidence, the activist campaigns against the player")
	check_eq(Market.get_required_bad_quarters(), 1, "under campaign one bad quarter is enough")
	var tania: int = Market.get_investor_confidence(TANIA)
	NewsFeed.publish_campaign_news()
	_let_hours_pass(TANIA_DELAY_HOURS)
	check(NewsFeed.get_suspicion_about("player") > 0.0 and Market.get_investor_confidence(TANIA) < tania,
			"the campaign is a public scandal about the player: vigilance up, momentum investors down")
	EventBus.quarter_closed.emit(1)
	check(Market.get_bad_quarters_streak() == 1 and Market.is_board_pressure_triggered(),
			"one bad quarter under an activist campaign triggers board pressure")
	for _d: int in Database.get_balance_int("mercado.dias_campana_activista") + 1:
		Market.advance_day(Market.get_current_day() + 1)
	check(not Market.is_player_under_campaign(), "the campaign expires")


func _test_portfolio_cash_and_board_stake() -> void:
	new_run(DEFAULT_SEED, false)
	var money: int = PlayerState.get_money()
	check(not MarketTrading.buy(10) and PlayerState.get_money() == money, "no trading below R25")
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	PlayerState.add_money(100000, "test")
	money = PlayerState.get_money()
	check(MarketTrading.buy(100), "R25 buys 100 shares from the computer")
	check_eq(PlayerState.get_money(), money - 4250, "100 × 42.50 € = 4,250 € leave the player's pocket")
	check(not Market.buy_shares(1000) and Market.get_player_shares() == 100,
			"Market alone never hands out free shares (the broker account is empty)")
	check_near(Market.get_portfolio_value(), 100.0 * Market.get_price(), EPS, "value = shares × price")
	money = PlayerState.get_money()
	check(MarketTrading.sell(40) and PlayerState.get_money() == money + 1700,
			"selling 40 shares pays 1,700 €")
	check(not MarketTrading.sell(100), "cannot sell more than owned")
	PlayerState.add_money(600000, "test")
	money = PlayerState.get_money()
	check(not MarketTrading.buy_board_stake() and PlayerState.get_money() == money,
			"the board stake needs R30 (nothing is charged)")
	PlayerState.set_occupation(R24_OCCUPATION, "test")
	check(not MarketTrading.buy(1), "R24 cannot trade")
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	check(MarketTrading.buy(6000) and Market.get_board_votes() == 0,
			"6,000 ordinary shares give no board vote without the R30 stake")
	PlayerState.set_occupation(R30_OCCUPATION, "test")
	money = PlayerState.get_money()
	check(MarketTrading.buy_board_stake(), "R30 buys the ~250,000 € board stake")
	check_eq(PlayerState.get_money(), money - STAKE_PRICE, "the stake is paid in cash")
	var shares: int = 6060 + floori(float(STAKE_PRICE) / Market.get_price())
	check_eq(Market.get_player_shares(), shares, "the stake adds 250,000 ÷ price shares")
	check(Market.has_board_stake() and not MarketTrading.buy_board_stake(), "only one stake")
	check_eq(Market.get_board_votes(), floori(float(shares) / SHARES_PER_VOTE), "the stake grants board votes")
	_test_dividends(shares)


func _test_dividends(shares: int) -> void:
	var expected: int = floori(_annual_profit() * PAYOUT / TOTAL_SHARES * shares)
	check_eq(Market.get_dividend_income(), expected, "dividend = shares × annual profit × 30 % ÷ 40 M")
	EventBus.quarter_closed.emit(4)
	check_eq(Market.get_dividends_paid(), expected, "dividends paid at the annual board (Q4)")
	check_eq(Market.get_broker_cash(), expected, "…into the broker account")
	var money: int = PlayerState.get_money()
	check(MarketTrading.collect_broker_cash() == expected and PlayerState.get_money() == money + expected,
			"the player collects the dividends in cash")


## save_state/load_state conserva aliados, coacción, campañas, reacciones pendientes, cuenta de
## valores, cartera y cifras acumuladas del trimestre.
func _test_save_load_owned_state() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	PlayerState.add_money(100000, "test")
	MarketTrading.buy(100)
	Market.deposit_cash(777)
	ResultsPresentation.blackmail_investor(MARGARET, LEVERAGE)
	Market.direct_activist(MARGARET, RIVAL)
	NewsFeed.publish("NEWS_FABRICATED_PRAISE", 0.1, false)
	for _d: int in 2:
		_run_trading_day()
	var before: Dictionary = _market_snapshot()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Market.save_state()))
	Market.reset_for_new_run()
	check(_market_snapshot() != before, "a reset clears the owned state")
	Market.load_state(saved)
	var after: Dictionary = _market_snapshot()
	for key: String in before:
		check(str(after[key]) == str(before[key]), "load_state restores %s" % key)


func _market_snapshot() -> Dictionary:
	return {
		"shares": Market.get_player_shares(), "broker_cash": Market.get_broker_cash(),
		"allies": Market.get_investor_allies(), "coerced": Market.is_investor_coerced(MARGARET),
		"campaigns": Market.get_activist_campaigns(), "pending": Market.get_pending_reactions().size(),
		"quarter": Market.get_quarter_real_figures(false), "invested": Market.get_invested_capital(),
		"expected": Market.get_expected_quarter_profit(), "price": Market.get_price(),
	}


## Mueve el reloj real (hour_passed): las reacciones con retraso vencen.
func _let_hours_pass(hours: int) -> void:
	GameClock.advance_minutes(float(hours) * MINUTES_PER_HOUR)


func _goto_presentation_day() -> void:
	while Market.get_current_day() < Market.get_presentation_day():
		Market.advance_day(Market.get_current_day() + 1)


func _run_trading_day() -> void:
	for _h: int in Market.get_steps_per_day():
		Market.tick_hourly()
	Market.advance_day(Market.get_current_day() + 1)


func _annual_profit() -> float:
	return float(Company.get_fundamentals().get("profit", 0.0)) * FISCAL_DAYS


func _aggregate_of(changes: Dictionary) -> float:
	var total: float = 0.0
	for id: String in CAPITAL_M:
		total += float(CAPITAL_M[id]) * float(changes[id])
	return total / 16.6


func _confidences() -> Dictionary:
	var out: Dictionary = {}
	for inv: InvestorData in Market.get_investors():
		out[inv.id] = Market.get_investor_confidence(inv.id)
	return out


func _expect_changes(deltas: Dictionary, label: String) -> void:
	_expect_changes_from(MANUAL_CONFIDENCE.duplicate(), deltas, label)


func _expect_changes_from(start: Dictionary, deltas: Dictionary, label: String) -> void:
	for id: String in deltas:
		var expected: int = clampi(int(start[id]) + int(deltas[id]), 0, 100)
		check_eq(Market.get_investor_confidence(id), expected, "%s: %s %+d" % [label, id, deltas[id]])
