# market.gd — Cotización (§9.3), calendario (§9.4), inversores (§9.6-9.7), presentación (§9.5), cartera (§9.11) e información privilegiada (§9.8).
# PROPIETARIO DE: cotización, histórico, sentimiento inversor propio, confianza de cada inversor, aliados/coaccionados y campañas activistas, racha de trimestres malos, cifras acumuladas del trimestre, cartera del jugador (acciones, cuenta de valores, dividendos), testaferros y patrón insider (§19.9).
# ESCUCHA: hour_passed, day_advanced, quarter_closed, news_published, audit_triggered, bribe_offered, bribe_result, blackmail_initiated, npc_removed
class_name MarketSystem
extends Node

## DECISIONES (BUILD_NOTES §6/§13; contrato para el resto de constructores):
## - PASO HORARIO. La fórmula DIARIA de §9.3 se aplica en N pasos de 1/N, N = hora_fin_jornada −
##   hora_inicio_jornada (11): un paso por `hour_passed` de hora de mercado (hora ∈ (inicio, fin]);
##   `day_advanced` completa los pasos que falten (cada jornada aplica exactamente un paso diario
##   completo aunque se salten horas). Nunca por fotograma (sin _process).
## - β·sentimiento se aplica como β × sentimiento × P (sentimiento adimensional acotado a
##   ±mercado.sentimiento_max = 0,5: como mucho ±15 % diario por sentimiento). Ruido ∈ ±3 % × P,
##   sorteado una vez por jornada con el RNG del sistema. Momentum = media de la variación diaria
##   (€) de los últimos cinco cierres. Sentimiento = NewsFeed.get_sentiment_contribution() +
##   sentimiento inversor propio (reacciones a la presentación, desbandadas), que decae a diario.
## - V usa los fundamentales REALES de Company (por jornada; beneficio anual = profit × jornadas del
##   año fiscal). Si Company aún no da cifras, usa market.json starting_fundamentals.
## - CIFRAS DEL TRIMESTRE. Market acumula el beneficio real de cada jornada al completar su último
##   paso de mercado. Reales del trimestre = acumulado + jornada abierta (+ proyección de las que
##   falten); reportadas = reales + (reportado − real de Company hoy) × jornadas del trimestre (el
##   CFO reexpresa el trimestre entero). quarter_reported(reales, reportadas) lleva esos TOTALES
##   {revenue, costs, profit, days}. La puntuación de cifras compara el beneficio reportado del
##   trimestre con lo esperado (lo reportado el trimestre anterior).
## - PRESENTACIÓN (§9.5). Una por trimestre y solo el día de resultados (can_present_results()).
##   resultado = 0,6 × calidad + 0,4 × cifras. Cada estrategia lo lee con su lente: el inversor de
##   VALOR solo ve las cifras (inmune al marketing); el resto oye la calidad con el peso
##   W = mín(1, 0,6 × Σcapital ÷ Σcapital de quienes la escuchan), de modo que la media ponderada
##   por capital de lo percibido es EXACTAMENTE 0,6 × calidad + 0,4 × cifras; el pasivo solo
##   reacciona si la desviación alcanza su reaction_threshold. allies_present se acota a los
##   inversores aliados de verdad este trimestre (sobornados con mercado.favor_pregunta_favorable o
##   chantajeados). Sin presentación del jugador, al cerrar el trimestre presenta un NPC (neutro)
##   o, si el jugador es R28+, cuenta como INCOMPARECENCIA (sin preparar, sin aliados).
## - VENALIDAD. Los inversores no son personajes de NPCDirector: ResultsPresentation.bribe_investor
##   soborna a un sustituto con Bribery (bribe_offered / crime_committed / bribe_result) y Market
##   marca el aliado al oír bribe_result. Chantaje: ResultsPresentation.blackmail_investor emite
##   blackmail_initiated(inversor, inversor, material); Market marca al inversor coaccionado
##   (aliado del trimestre; al activista coaccionado se le dirige con direct_activist()).
## - PRENSA: reaccionan según su estrategia (valor nunca; pasivo solo a desastres). Quien tiene
##   reaction_delay_hours (Tania Brekke, 3 h) reacciona al pasar esas horas de juego (hour_passed).
## - CAMPAÑA ACTIVISTA. Automática contra el jugador al perder la confianza, o dirigida contra un
##   rival. Dura mercado.dias_campana_activista jornadas o hasta que su objetivo sale (npc_removed).
##   Contra el jugador resta mercado.trimestres_perdonados_campana a los trimestres malos que
##   disparan la presión del consejo. NewsFeed la publica como escándalo sobre su objetivo.
## - Market es el ÚNICO emisor de `quarter_reported`. La degradación R28+ NO la ejecuta Market:
##   Company la aplica al oír quarter_reported y leer is_board_pressure_triggered().
## - DINERO. El efectivo es de PlayerState y Market (autoload) no lo toca. La cartera tiene una
##   CUENTA DE VALORES propia (get_broker_cash): comprar la carga; vender y los dividendos (junta
##   anual) la abonan. Las "manos" (MarketTrading, la UI) llevan el efectivo de PlayerState a la
##   cuenta y de vuelta (deposit_cash / withdraw_cash). Sin fondos en la cuenta, buy_shares falla.
## - INSIDER. Una operación del jugador es privilegiada si su SENTIDO coincide con el de una noticia
##   que ya conoce (comprar ante una positiva, vender ante una negativa). register_insider_operation
##   emite crime_committed("insider_trade"); quien llame no debe emitirlo otra vez. Operar mediante
##   un testaferro sobornado (favor mercado.favor_testaferro) no suma al patrón del jugador: emite
##   crime_committed con subject = testaferro (MarketTrading lo convierte en testigo). Enterrar la
##   noticia en la que se operó NO borra el patrón (el registro de la bolsa ya existe): la
##   contramedida "enterrar" actúa sobre el escándalo insider una vez publicado.

const PLAYER_ID := "player"
const RNG_SALT := "market"
## Punto medio de la escala [0, 1] de resultados: 0,5 = "según lo esperado" (estructural).
const OUTCOME_NEUTRAL := 0.5
## Escala 0-100 de reputación, sospecha y perspicacia (estructural).
const PERCENT_SCALE := 100.0
const NEUTRAL_MULTIPLIER := 1.0

const FACTOR_ABOVE := "results_above_expected"
const FACTOR_BELOW := "results_below_expected"
const FACTOR_PRESS := "favourable_press"
## Motivos (solo etiqueta) cuando la presentación lleva la reacción contra lo que dicen las cifras.
const REASON_PRESENTATION_ABOVE := "presentation_above_expected"
const REASON_PRESENTATION_BELOW := "presentation_below_expected"
const FACTOR_LOUNGE := "lounge_personal_contact"
const FACTOR_TIP := "insider_tip_to_hunter"
const FACTOR_SCANDAL := "public_scandal"
const FACTOR_FRAUD := "falsification_discovered"
const REASON_TREND := "price_trend"

const STRATEGY_MOMENTUM := "momentum"
const STRATEGY_ACTIVIST := "activist"
const BEHAVIOUR_CAMPAIGN := "campaign_against_management"
const LEVEL_NONE := "none"
const PRESENTER_PLAYER := "player"
const PRESENTER_NPC := "npc"
const PRESENTER_NO_SHOW := "no_show"

const INVESTORS_FILE := "investors"
const BRIBE_REFERENCE_KEY := "bribe_reference_daily"
const BRIBE_TIER_KEY := "bribe_price_tier"
const PAYS_FOR_TIPS_KEY := "pays_for_tips"
const SOCIAL_REACH_KEY := "social_reach"
const REACTION_DELAY_KEY := "reaction_delay_hours"
const MINUTES_PER_HOUR := 60.0

const CRIME_INSIDER := "insider_trade"
const DETAIL_VOLUME := "volume"
const DETAIL_PROXY := "proxy"
const DETAIL_SUBJECT := "subject"
const DETAIL_TIP := "tip_to"
const TRADE_BUY := 1
const TRADE_SELL := -1
const TRADE_ANY := 0

const HEADLINE_RESULTS_BEAT := "NEWS_RESULTS_BEAT"
const HEADLINE_RESULTS_MISS := "NEWS_RESULTS_MISS"
const HEADLINE_RESULTS_INLINE := "NEWS_RESULTS_INLINE"
const RESULTS_DIRECTIONS: Dictionary = {
	HEADLINE_RESULTS_BEAT: TRADE_BUY, HEADLINE_RESULTS_MISS: TRADE_SELL,
	HEADLINE_RESULTS_INLINE: TRADE_ANY,
}
const REVENUE_EFFECT := "revenue_multiplier"

const CAMPAIGN_INVESTOR := "investor_id"
const CAMPAIGN_TARGET := "target"
const CAMPAIGN_SINCE := "since_day"
const CAMPAIGN_UNTIL := "until_day"

const FIGURE_KEYS: Array[String] = ["revenue", "costs", "profit"]
const DAYS_KEY := "days"

const PERIOD_DAILY := "daily"
const PERIOD_WEEKLY := "weekly"
const PERIOD_MONTHLY := "monthly"
const PERIOD_QUARTERLY := "quarterly"
const PERIOD_ANNUAL := "annual"

## Claves que market.json duplica de balance.json (§32.5): deben coincidir (get_config_mismatches).
## Además, cada clave de market.json `simulation` debe coincidir con balance `mercado.<clave>`.
const SIMULATION_SECTION := "simulation"
const BALANCE_MARKET_SECTION := "mercado"
const DUPLICATED_KEYS: Dictionary = {
	"insider_detection.pattern_threshold": "mercado.umbral_patron_insider",
	"board_pressure.bad_quarters_to_degrade": "mercado.trimestres_malos_para_degradar",
	"presentation.weight_quality": "mercado.peso_presentacion_calidad",
	"presentation.weight_figures": "mercado.peso_presentacion_cifras",
	"shares.share_package_price": "economia.precio_paquete_accionarial",
	"calendar.days_per_week": "tiempo.jornadas_por_semana",
	"calendar.days_per_month": "tiempo.jornadas_por_mes",
	"calendar.days_per_quarter": "tiempo.jornadas_por_trimestre",
}

# ─── Datos estáticos (caché de Database; no se guardan) ───────────────
var _cfg: Dictionary = {}
var _strategies: Dictionary = {}
var _investors: Array[InvestorData] = []
var _starting_fundamentals: Dictionary = {}
var _bribe_references: Dictionary = {}

# ─── Estado propio (se guarda) ─────────────────────────────────────────
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _today: int = 0
var _price: float = 0.0
var _history: Array[float] = []
var _steps_today: int = 0
var _noise_today: float = 0.0
var _own_sentiment: float = 0.0
var _fraud_multiple_penalty: float = 0.0
var _confidence: Dictionary = {}
var _last_reason: Dictionary = {}
var _credibility_lost: bool = false
var _loss_spent: Dictionary = {}
var _campaigns: Dictionary = {}
var _allies: Dictionary = {}
var _coerced: Dictionary = {}
var _bad_quarters_streak: int = 0
var _presented_quarter: int = 0
var _due_emitted_quarter: int = 0
var _expected_quarter_profit: float = 0.0
## Beneficio diario esperado (§9.3): media exponencial de los beneficios diarios cerrados.
var _expected_daily_profit: float = 0.0
var _last_presentation: Dictionary = {}
var _q_real: Dictionary = {}
var _q_days: int = 0
var _q_last_day: int = 0
var _player_shares: int = 0
var _stake_shares: int = 0
var _invested: float = 0.0
var _broker_cash: int = 0
var _dividends_paid: int = 0
var _insider_ops: Array[Dictionary] = []
var _insider_detections: int = 0
var _proxies: Dictionary = {}
var _proxy_ops: Array[Dictionary] = []
## Reacciones a la prensa con retraso: [{investor_id, factor, severity, news_id, due_minute}].
var _pending_reactions: Array[Dictionary] = []
## Transitorio: favor del último bribe_offered por personaje (Bribery emite offered y result seguidos).
var _pending_bribes: Dictionary = {}


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.quarter_closed.connect(_on_quarter_closed)
	EventBus.news_published.connect(_on_news_published)
	EventBus.audit_triggered.connect(_on_audit_triggered)
	EventBus.bribe_offered.connect(_on_bribe_offered)
	EventBus.bribe_result.connect(_on_bribe_result)
	EventBus.blackmail_initiated.connect(_on_blackmail_initiated)
	EventBus.npc_removed.connect(_on_npc_removed)


func reset_for_new_run() -> void:
	_load_static_data()
	_rng.seed = GameClock.get_run_seed() ^ RNG_SALT.hash()
	_today = GameClock.get_day()
	_price = _bf("mercado.precio_inicial")
	_history = [_price]
	_steps_today = 0
	_own_sentiment = 0.0
	_fraud_multiple_penalty = 0.0
	_expected_daily_profit = float(_fundamentals().get("profit", 0.0))
	_roll_daily_noise()
	_reset_investors()
	_reset_quarter_state()
	_reset_portfolio()


# ═══ Cotización ═══════════════════════════════════════════════════════

func get_price() -> float:
	return _price


## V = (beneficio anual esperado × múltiplo) ÷ número de acciones (§9.3). El beneficio esperado es
## una media exponencial de los días cerrados más la jornada abierta con el mismo peso: una sola
## jornada anómala (huelga) no se valora como un año entero de pérdidas (§11.7).
func get_intrinsic_value() -> float:
	var annual: float = get_expected_daily_profit() * float(_days_per_year())
	var value: float = annual * get_valuation_multiple() / float(_share_count())
	return maxf(value, _bf("mercado.precio_minimo"))


## Múltiplo vigente: fórmula §9.3 × eventos de mercado activos − penalizaciones permanentes.
func get_valuation_multiple() -> float:
	var f: Dictionary = _fundamentals()
	var multiple: float = compute_multiple(float(f.get("growth_expectation", 0.0)),
			float(f.get("risk_factor", 0.0)))
	multiple *= NewsFeed.get_event_multiplier("multiple_multiplier")
	multiple -= get_permanent_multiple_penalty()
	return maxf(multiple, _bf("mercado.multiplo_minimo"))


## múltiplo = base + 0,8 × crecimiento − 1,2 × riesgo (coeficientes de balance.mercado).
func compute_multiple(growth: float, risk: float) -> float:
	return _bf("mercado.multiplo_base") + _bf("mercado.mod_multiplo_crecimiento") * growth \
			+ _bf("mercado.mod_multiplo_riesgo") * risk


## Escándalos consolidados sin enterrar (§9.10) + falsificaciones descubiertas.
func get_permanent_multiple_penalty() -> float:
	return _fraud_multiple_penalty + float(NewsFeed.get_settled_scandal_count()) \
			* _bf("mercado.penalizacion_multiplo_escandalo")


## Paso DIARIO completo de §9.3: α(V−P) + β·s·P + γ·momentum + ruido·P.
func compute_daily_delta(price: float, value: float, sentiment: float, momentum: float,
		noise_fraction: float) -> float:
	return _bf("mercado.alpha_gravedad") * (value - price) \
			+ _bf("mercado.beta_sentimiento") * sentiment * price \
			+ _bf("mercado.gamma_momentum") * momentum + noise_fraction * price


## Últimos `days` cierres diarios (el más reciente al final; no incluye la cotización en curso).
func get_price_history(days: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(maxi(_history.size() - days, 0), _history.size()):
		out.append(_history[i])
	return out


## Media de la variación diaria (€) de los últimos `dias_momentum` cierres.
func get_momentum() -> float:
	var count: int = mini(_bi("mercado.dias_momentum"), _history.size() - 1)
	if count <= 0:
		return 0.0
	return (_history[_history.size() - 1] - _history[_history.size() - 1 - count]) / float(count)


func get_sentiment() -> float:
	var cap: float = _bf("mercado.sentimiento_max")
	return clampf(NewsFeed.get_sentiment_contribution() + _own_sentiment, -cap, cap)


## Componente de sentimiento generado por los propios inversores (presentación, desbandadas).
func get_investor_sentiment() -> float:
	return _own_sentiment


## Aplica 1/N del paso diario. Como mucho N pasos por jornada; el último cierra las cifras del día.
func tick_hourly() -> void:
	var steps: int = get_steps_per_day()
	if _steps_today >= steps:
		return
	var delta: float = compute_daily_delta(_price, get_intrinsic_value(), get_sentiment(),
			get_momentum(), _noise_today)
	_price = maxf(_price + delta / float(steps), _bf("mercado.precio_minimo"))
	_steps_today += 1
	if _steps_today == steps:
		_accumulate_day(_today)
	EventBus.stock_price_updated.emit(_price, _percent_change(_last_close(), _price))


func get_steps_per_day() -> int:
	return maxi(_bi("tiempo.hora_fin_jornada") - _bi("tiempo.hora_inicio_jornada"), 1)


func get_steps_done_today() -> int:
	return _steps_today


## Fracción de ruido de la jornada en curso (sorteada al abrir la jornada).
func get_noise_today() -> float:
	return _noise_today


func get_current_day() -> int:
	return _today


## Cierra la jornada de mercado (completa los pasos pendientes) y abre `day_number`.
func advance_day(day_number: int) -> void:
	if day_number <= _today:
		return
	while _steps_today < get_steps_per_day():
		tick_hourly()
	_accumulate_day(_today)
	_push_close(_price)
	_apply_trend_drift()
	_own_sentiment *= _bf("mercado.decaimiento_sentimiento_inversor")
	_today = day_number
	_steps_today = 0
	_expire_campaigns()
	_prune_insider_ops()
	_roll_daily_noise()


## Coincidencia de las claves que market.json duplica de balance.json ([] = todo coincide).
func get_config_mismatches() -> Array[String]:
	var pairs: Dictionary = DUPLICATED_KEYS.duplicate()
	for key: Variant in _cfg_dict(SIMULATION_SECTION).keys():
		if not str(key).begins_with("_"):
			pairs[SIMULATION_SECTION + "." + str(key)] = BALANCE_MARKET_SECTION + "." + str(key)
	var out: Array[String] = []
	for market_key: Variant in pairs.keys():
		var local: Variant = _cfg_value(str(market_key))
		var balance_path: String = str(pairs[market_key])
		if not (local is float or local is int) or not Database.has_balance(balance_path):
			out.append("%s <> %s: missing" % [market_key, balance_path])
		elif not is_equal_approx(float(local), Database.get_balance_float(balance_path)):
			out.append("%s = %s <> %s = %s" % [market_key, str(local), balance_path,
					str(Database.get_balance(balance_path))])
	if _cfg_int("calendar.days_per_fiscal_year") != _days_per_year():
		out.append("calendar.days_per_fiscal_year <> days_per_quarter × quarters_per_year")
	return out


# ═══ Calendario (§9.4) ════════════════════════════════════════════════

## Eventos de calendario desde hoy hasta hoy + days_ahead: [{day, id, name_key, periodicity}].
func get_calendar(days_ahead: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offset: int in range(0, days_ahead + 1):
		var day: int = _today + offset
		for entry: Variant in _cfg_array("calendar.events"):
			var ev: Dictionary = entry as Dictionary
			if _calendar_event_on(str(ev.get("periodicity", "")), day):
				out.append({"day": day, "id": str(ev.get("id", "")),
						"name_key": str(ev.get("name_key", "")),
						"periodicity": str(ev.get("periodicity", ""))})
	return out


## Jornada absoluta de la presentación trimestral del trimestre en curso.
func get_presentation_day() -> int:
	var quarter: int = quarter_of(_today)
	return (quarter - 1) * _days_per_quarter() + _cfg_int("calendar.results_presentation.day_of_quarter")


func get_presentation_room() -> String:
	return _cfg_string("calendar.results_presentation.room")


@warning_ignore("integer_division")
func quarter_of(day_number: int) -> int:
	return maxi(day_number - 1, 0) / _days_per_quarter() + 1


func day_in_quarter(day_number: int) -> int:
	return maxi(day_number - 1, 0) % _days_per_quarter() + 1


# ═══ Inversores (§9.6, §9.7) ══════════════════════════════════════════

func get_investors() -> Array[InvestorData]:
	return _investors.duplicate()


func get_investor(investor_id: String) -> InvestorData:
	return _investor(investor_id)


func get_investor_confidence(investor_id: String) -> int:
	return int(_confidence.get(investor_id, 0))


func modify_investor_confidence(investor_id: String, delta: int, reason: String) -> void:
	if not _confidence.has(investor_id) or delta == 0:
		return
	var applied: int = delta
	if _credibility_lost and delta > 0:
		applied = floori(float(delta) * _bf("mercado.factor_credibilidad_perdida"))
	var old_value: int = int(_confidence[investor_id])
	var new_value: int = clampi(old_value + applied, InvestorData.MIN_CONFIDENCE,
			InvestorData.MAX_CONFIDENCE)
	if new_value == old_value:
		return
	_confidence[investor_id] = new_value
	_last_reason[investor_id] = reason
	EventBus.investor_confidence_changed.emit(investor_id, old_value, new_value)
	_check_confidence_loss(investor_id, old_value, new_value)


## true tras descubrirse una falsificación: los aumentos de confianza se reducen para siempre.
func is_credibility_lost() -> bool:
	return _credibility_lost


## Motivo del último cambio de confianza (id de factor de §9.7) para la UI.
func get_last_confidence_reason(investor_id: String) -> String:
	return str(_last_reason.get(investor_id, ""))


## Σ(confianza_i × capital_i) ÷ Σ capital_i (§9.7).
func get_aggregate_confidence() -> float:
	var weighted: float = 0.0
	var capital: float = 0.0
	for inv: InvestorData in _investors:
		weighted += float(get_investor_confidence(inv.id)) * float(inv.capital)
		capital += float(inv.capital)
	return weighted / capital if capital > 0.0 else 0.0


func get_quarterly_target() -> float:
	return get_target_for_quarter(quarter_of(_today))


func get_target_for_quarter(quarter_number: int) -> float:
	var targets: Array = _cfg_array("quarterly_confidence_targets")
	var index: int = quarter_number - 1
	if index >= 0 and index < targets.size():
		return float(targets[index])
	return _cfg_float("target_after_last_quarter")


func is_meeting_target() -> bool:
	return get_aggregate_confidence() >= get_quarterly_target()


## DECISIÓN: trimestres consecutivos bajo objetivo mientras el jugador es R28+ (§9.4).
func get_bad_quarters_streak() -> int:
	return _bad_quarters_streak


## Trimestres malos que disparan la presión del consejo (una campaña activista contra el jugador
## perdona mercado.trimestres_perdonados_campana; nunca menos de uno).
func get_required_bad_quarters() -> int:
	var required: int = _bi("mercado.trimestres_malos_para_degradar")
	if is_player_under_campaign():
		required -= _bi("mercado.trimestres_perdonados_campana")
	return maxi(required, 1)


## true si la racha alcanza get_required_bad_quarters(): degradación o expulsión (Company actúa).
func is_board_pressure_triggered() -> bool:
	return _bad_quarters_streak >= get_required_bad_quarters()


## Delta de la tabla §9.7 (market.json confidence_factors). severity ∈ [0,1] va del efecto
## leve (+8, −10, −15…) al severo (+15, −20, −30…). Los factores escalares ignoran severity.
func get_factor_delta(factor_id: String, severity: float) -> int:
	var raw: Variant = _cfg_value("confidence_factors." + factor_id)
	if raw is Array and (raw as Array).size() == 2:
		var low: float = float(raw[0])
		var high: float = float(raw[1])
		var mild: float = high if high <= 0.0 else low
		var severe: float = low if high <= 0.0 else high
		return roundi(lerpf(mild, severe, clampf(severity, 0.0, 1.0)))
	if raw is float or raw is int:
		return roundi(float(raw))
	return 0


## Aplica un factor de §9.7 a los inversores indicados. Devuelve {investor_id: delta aplicado}.
func apply_confidence_factor(factor_id: String, severity: float,
		investor_ids: Array[String]) -> Dictionary:
	var delta: int = get_factor_delta(factor_id, severity)
	var changes: Dictionary = {}
	for investor_id: String in investor_ids:
		var before: int = get_investor_confidence(investor_id)
		modify_investor_confidence(investor_id, delta, factor_id)
		changes[investor_id] = get_investor_confidence(investor_id) - before
	return changes


## Contacto personal en el lounge (+5). El gasto de representación lo cobra quien llama.
func record_lounge_contact(investor_id: String) -> int:
	if not _confidence.has(investor_id):
		return 0
	var ids: Array[String] = [investor_id]
	return int(apply_confidence_factor(FACTOR_LOUNGE, 1.0, ids).get(investor_id, 0))


## true si la estrategia del inversor compra soplos (cazador de información).
func accepts_tips(investor_id: String) -> bool:
	var inv: InvestorData = _investor(investor_id)
	return inv != null and _strategy_float(inv, "weight_tips") > 0.0


## Soplo privilegiado: +12 solo al cazador de información. Cada soplo es una prueba:
## emite crime_committed("insider_trade"). Devuelve el delta aplicado. El pago lo cobra
## MarketTrading.sell_tip (get_tip_payment).
func give_insider_tip(investor_id: String) -> int:
	if not accepts_tips(investor_id):
		return 0
	var ids: Array[String] = [investor_id]
	var delta: int = int(apply_confidence_factor(FACTOR_TIP, 1.0, ids).get(investor_id, 0))
	EventBus.crime_committed.emit(CRIME_INSIDER, "", {DETAIL_TIP: investor_id})
	return delta


## Lo que paga el inversor por un soplo (pays_for_tips en investors.json; 0 si no paga).
func get_tip_payment(investor_id: String) -> int:
	var inv: InvestorData = _investor(investor_id)
	if inv == null or not accepts_tips(investor_id) or not bool(inv.extra.get(PAYS_FOR_TIPS_KEY, false)):
		return 0
	return _bi("mercado.pago_por_soplo")


# ─── Venalidad (§9.5, §9.6, §24.4) ────────────────────────────────────

## Sobornable según investors.json (bribable y un bribe_price_tier con referencia > 0).
func is_investor_bribable(investor_id: String) -> bool:
	var inv: InvestorData = _investor(investor_id)
	return inv != null and inv.bribable and get_investor_bribe_reference(investor_id) > 0


func is_investor_blackmailable(investor_id: String) -> bool:
	var inv: InvestorData = _investor(investor_id)
	return inv != null and inv.blackmailable


## Referencia diaria del soborno (los inversores no tienen salario): bribe_reference_daily del tier.
func get_investor_bribe_reference(investor_id: String) -> int:
	var inv: InvestorData = _investor(investor_id)
	if inv == null:
		return 0
	return int(_bribe_references.get(str(inv.extra.get(BRIBE_TIER_KEY, "")), 0))


## §8.2 paso primero, sin modificadores: referencia diaria × multiplicador del favor (0 =
## insobornable). El precio justo aplicado (dificultad, sospecha) lo da Bribery vía
## ResultsPresentation.investor_bribe_price().
func get_investor_base_bribe_price(investor_id: String, favour_id: String) -> int:
	if not is_investor_bribable(investor_id):
		return 0
	var multiplier: float = float(Database.get_bribe_favour(favour_id).get("multiplier", 0.0))
	return roundi(float(get_investor_bribe_reference(investor_id)) * multiplier)


## Favor con el que un inversor sobornado formula una pregunta favorable en la presentación.
func get_favourable_question_favour() -> String:
	return str(Database.get_balance("mercado.favor_pregunta_favorable"))


## Inversores aliados en la sala de este trimestre (sobornados o chantajeados).
func get_investor_allies() -> Array[String]:
	var out: Array[String] = []
	var quarter: int = quarter_of(_today)
	for inv: InvestorData in _investors:
		if int(_allies.get(inv.id, 0)) == quarter:
			out.append(inv.id)
	return out


func is_investor_ally(investor_id: String) -> bool:
	return get_investor_allies().has(investor_id)


## Chantajeado este trimestre (blackmail_initiated sobre un inversor chantajeable).
func is_investor_coerced(investor_id: String) -> bool:
	return int(_coerced.get(investor_id, 0)) == quarter_of(_today)


# ─── Campañas activistas (§9.6) ───────────────────────────────────────

## Dirige al activista COACCIONADO contra un objetivo (id de rival o "player"). Devuelve si pudo.
func direct_activist(investor_id: String, target: String) -> bool:
	var inv: InvestorData = _investor(investor_id)
	if inv == null or inv.strategy != STRATEGY_ACTIVIST or target.is_empty() or target == investor_id:
		return false
	if not is_investor_coerced(investor_id):
		return false
	_start_campaign(investor_id, target)
	return true


func get_activist_target(investor_id: String) -> String:
	var campaign: Dictionary = _campaigns.get(investor_id, {})
	return str(campaign.get(CAMPAIGN_TARGET, ""))


## Campañas vivas: [{investor_id, target, since_day, until_day}] (copias).
func get_activist_campaigns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for investor_id: Variant in _campaigns.keys():
		out.append((_campaigns[investor_id] as Dictionary).duplicate())
	return out


func is_player_under_campaign() -> bool:
	for campaign: Dictionary in get_activist_campaigns():
		if str(campaign[CAMPAIGN_TARGET]) == PLAYER_ID:
			return true
	return false


# ═══ Presentación de resultados (§9.5) ════════════════════════════════

## Niveles de preparación de market.json: {none: 0.0, assist: 0.5, stolen_coo_report: 0.8, real_work: 1.0}.
func get_preparation_levels() -> Dictionary:
	return _cfg_dict("presentation.preparation_levels")


func get_allies_ratio(allies_present: int) -> float:
	if _investors.is_empty():
		return 0.0
	return clampf(float(allies_present) / float(_investors.size()), 0.0, 1.0)


## calidad = 0,4 × preparación + 0,3 × reputación/100 + 0,3 × proporción de aliados.
func compute_presentation_quality(preparation: float, allies_present: int) -> float:
	return _presentation_quality(preparation, allies_present, PlayerState.get_reputation())


## §9.5: la calidad pesa el 60 % y las cifras el 40 %.
func compute_presentation_outcome(quality: float, figures: float) -> float:
	return _bf("mercado.peso_presentacion_calidad") * quality \
			+ _bf("mercado.peso_presentacion_cifras") * figures


## Peso de la calidad en lo que percibe el inversor: 0 si su estrategia solo lee fundamentales
## (valor); si no, W = mín(tope, peso_calidad × Σcapital ÷ Σcapital de quienes escuchan). El tope
## (mercado.peso_presentacion_calidad_max_oyente) evita que un oyente ignore del todo las cifras.
func get_presentation_quality_share(investor_id: String) -> float:
	var inv: InvestorData = _investor(investor_id)
	if inv == null or not _listens_to_presentation(inv):
		return 0.0
	var total: float = 0.0
	var listeners: float = 0.0
	for other: InvestorData in _investors:
		total += float(other.capital)
		if _listens_to_presentation(other):
			listeners += float(other.capital)
	if listeners <= 0.0:
		return 0.0
	return minf(_bf("mercado.peso_presentacion_calidad") * total / listeners,
			clampf(_bf("mercado.peso_presentacion_calidad_max_oyente"), 0.0, 1.0))


## Resultado percibido [0,1] por un inversor: W × calidad + (1 − W) × cifras.
func get_perceived_outcome(investor_id: String, quality: float, figures: float) -> float:
	var share: float = get_presentation_quality_share(investor_id)
	return share * quality + (1.0 - share) * figures


## Reacción de cada inversor (§9.7, sin aplicarla): {investor_id: delta de confianza}.
func compute_presentation_reaction(quality: float, figures: float) -> Dictionary:
	var out: Dictionary = {}
	for inv: InvestorData in _investors:
		out[inv.id] = _outcome_delta(inv, get_perceived_outcome(inv.id, quality, figures))
	return out


## Puntuación [0,1] de las cifras reportadas del trimestre frente a lo esperado (0,5 = en línea).
func get_figures_score() -> float:
	return figures_score_for(float(get_quarter_reported_figures(true)["profit"]),
			_expected_quarter_profit)


func figures_score_for(reported_profit: float, expected_profit: float) -> float:
	var surprise: float = (reported_profit - expected_profit) / maxf(absf(expected_profit), 1.0)
	return clampf(OUTCOME_NEUTRAL + surprise * OUTCOME_NEUTRAL
			/ _bf("mercado.presentacion_rango_sorpresa"), 0.0, 1.0)


## Beneficio diario esperado: media exponencial (mercado.suavizado_beneficio_esperado) con la
## jornada en curso incluida.
func get_expected_daily_profit() -> float:
	var today: float = float(_fundamentals().get("profit", 0.0))
	return _expected_daily_profit + _profit_smoothing() * (today - _expected_daily_profit)


func _profit_smoothing() -> float:
	return clampf(_bf("mercado.suavizado_beneficio_esperado"), 0.0, 1.0)


func get_expected_quarter_profit() -> float:
	return _expected_quarter_profit


## Totales reales del trimestre: acumulado + jornada abierta; con `projected`, + las que falten.
func get_quarter_real_figures(projected: bool) -> Dictionary:
	var today: Dictionary = _fundamentals()
	var extra_days: int = 1 if _today > _q_last_day else 0
	if projected:
		extra_days = maxi(_days_per_quarter() - _q_days, 0)
	var out: Dictionary = {DAYS_KEY: _q_days + extra_days}
	for key: String in FIGURE_KEYS:
		out[key] = float(_q_real.get(key, 0.0)) + float(today.get(key, 0.0)) * float(extra_days)
	return out


## Totales reportados: reales + (reportado − real de hoy) × jornadas del trimestre.
func get_quarter_reported_figures(projected: bool) -> Dictionary:
	var out: Dictionary = get_quarter_real_figures(projected)
	var real: Dictionary = _fundamentals()
	var reported: Dictionary = _reported_figures()
	for key: String in FIGURE_KEYS:
		out[key] = float(out[key]) + (float(reported.get(key, 0.0)) - float(real.get(key, 0.0))) \
				* float(_days_per_quarter())
	return out


## Solo el día de resultados y una vez por trimestre.
func can_present_results() -> bool:
	return _presented_quarter != quarter_of(_today) \
			and day_in_quarter(_today) == _cfg_int("calendar.results_presentation.day_of_quarter")


## Devuelve { quality, confidence_changes, sentiment_delta } (+ outcome, figures_score,
## aggregate_before, aggregate_after, quarter, presenter, allies_counted), o {} si hoy no se
## puede presentar (can_present_results). allies_present se acota a get_investor_allies().
func conduct_quarterly_presentation(preparation: float, allies_present: int) -> Dictionary:
	if not can_present_results():
		return {}
	var allies: int = mini(maxi(allies_present, 0), get_investor_allies().size())
	_presented_quarter = quarter_of(_today)
	_run_presentation(compute_presentation_quality(preparation, allies), PRESENTER_PLAYER)
	_last_presentation["allies_counted"] = allies
	return _last_presentation.duplicate(true)


func has_presented_this_quarter() -> bool:
	return _presented_quarter == quarter_of(_today)


func get_last_presentation() -> Dictionary:
	return _last_presentation.duplicate(true)


# ═══ Cartera del jugador (§9.11) ══════════════════════════════════════

func get_player_shares() -> int:
	return _player_shares


func can_trade() -> bool:
	return PlayerState.get_rank() >= _cfg_int("shares.player_trading_min_rank")


## Efectivo en la cuenta de valores (lo mueven las manos con deposit_cash / withdraw_cash).
func get_broker_cash() -> int:
	return _broker_cash


func deposit_cash(amount: int) -> bool:
	if amount <= 0:
		return false
	_broker_cash += amount
	return true


func withdraw_cash(amount: int) -> bool:
	if amount <= 0 or amount > _broker_cash:
		return false
	_broker_cash -= amount
	return true


func get_buy_cost(quantity: int) -> int:
	return ceili(_price * float(maxi(quantity, 0)))


func get_sell_proceeds(quantity: int) -> int:
	return floori(_price * float(maxi(quantity, 0)))


## Compra con la cuenta de valores. Privilegiada si el jugador conoce una noticia positiva.
func buy_shares(quantity: int) -> bool:
	return _buy(quantity, "")


func sell_shares(quantity: int) -> bool:
	return _sell(quantity, "")


## R30: paquete accionarial por economia.precio_paquete_accionarial; concede voto en el consejo.
func buy_board_stake() -> bool:
	if has_board_stake() or PlayerState.get_rank() < _cfg_int("shares.share_package_min_rank"):
		return false
	var cost: int = get_board_stake_price()
	if cost > _broker_cash:
		return false
	var informed: bool = is_trade_informed(TRADE_BUY)
	var quantity: int = floori(float(cost) / _price)
	_add_shares(quantity, cost)
	_stake_shares = quantity
	if informed:
		register_insider_operation(cost)
	return true


func get_board_stake_price() -> int:
	return _bi("economia.precio_paquete_accionarial")


func has_board_stake() -> bool:
	return _stake_shares > 0


## §9.11: true si vender `quantity` acciones rompe el paquete accionarial (pierde voto y consejo).
## La UI lo confirma antes de ejecutar.
func sell_breaks_board_stake(quantity: int) -> bool:
	return _stake_shares > 0 and _player_shares - maxi(quantity, 0) < _stake_shares


func get_portfolio_value() -> float:
	return float(_player_shares) * _price


## Coste medio acumulado de la cartera (para la UI: plusvalía = valor − invertido).
func get_invested_capital() -> float:
	return _invested


## Dividendo anual previsto de la cartera: acciones × beneficio anual × payout ÷ acciones totales.
## Se abona en la cuenta de valores en la junta anual (§9.4).
func get_dividend_income() -> int:
	var annual: float = float(_fundamentals().get("profit", 0.0)) * float(_days_per_year())
	var per_share: float = annual * _cfg_float("shares.dividend_payout_ratio") / float(_share_count())
	return maxi(floori(per_share * float(_player_shares)), 0)


func get_dividends_paid() -> int:
	return _dividends_paid


## DECISIÓN (§9.11): el derecho de voto en el consejo lo da el paquete R30; sin paquete, 0 votos.
func get_board_votes() -> int:
	if not has_board_stake():
		return 0
	var per_vote: int = maxi(_cfg_int("shares.shares_per_board_vote"), 1)
	return maxi(floori(float(_player_shares) / float(per_vote)), _bi("mercado.votos_minimos_paquete"))


# ═══ Información privilegiada (§9.8) ══════════════════════════════════

## Registra una operación con información privilegiada (volumen en €). Emite crime_committed.
## Contramedidas: menos volumen, espaciar (ventana de jornadas), testaferros
## (register_proxy_operation), enterrar el escándalo, ser Auditor Jefe.
func register_insider_operation(volume: int) -> void:
	EventBus.crime_committed.emit(CRIME_INSIDER, "", {DETAIL_VOLUME: volume})
	if _insider_detection_disabled():
		return
	_insider_ops.append({"day": _today, "volume": maxi(volume, 0)})
	if get_insider_pattern_score() > _bf("mercado.umbral_patron_insider"):
		var count: int = _insider_ops.size()
		_insider_ops.clear()
		_insider_detections += 1
		EventBus.insider_pattern_detected.emit(count)


func get_insider_pattern_score() -> float:
	if _insider_ops.is_empty() or _insider_detection_disabled():
		return 0.0
	var total: float = 0.0
	for op: Dictionary in _insider_ops:
		total += float(op["volume"])
	return compute_insider_score(_insider_ops.size(), total / float(_insider_ops.size()),
			PlayerState.get_suspicion(), get_chief_auditor_perception())


## 0,05 × n + 0,10 × (volumen medio ÷ umbral) + 0,20 × sospecha/100 + 0,30 × perspicacia/100.
func compute_insider_score(operations: int, average_volume: float, suspicion: float,
		auditor_perception: float) -> float:
	var threshold: float = maxf(_cfg_float("insider_detection.volume_threshold"), 1.0)
	return _cfg_float("insider_detection.coef_operations") * float(operations) \
			+ _cfg_float("insider_detection.coef_volume") * (average_volume / threshold) \
			+ _cfg_float("insider_detection.coef_suspicion") * (suspicion / PERCENT_SCALE) \
			+ _cfg_float("insider_detection.coef_auditor_perception") \
			* (auditor_perception / PERCENT_SCALE)


func get_insider_operations_count() -> int:
	return _insider_ops.size()


func get_insider_detections() -> int:
	return _insider_detections


## Contramedida §9.8: operación a nombre de un testaferro sobornado. No suma al patrón del
## jugador; es delito con subject = testaferro (el rastro contable lo señala a él) y el testaferro
## pasa a ser testigo (MarketTrading crea su creencia).
func register_proxy_operation(npc_id: String, volume: int) -> void:
	EventBus.crime_committed.emit(CRIME_INSIDER, "",
			{DETAIL_VOLUME: volume, DETAIL_PROXY: npc_id, DETAIL_SUBJECT: npc_id})
	_proxy_ops.append({"day": _today, "npc_id": npc_id, "volume": maxi(volume, 0)})


## Personajes que aceptaron el soborno de testaferro (favor mercado.favor_testaferro).
func is_proxy(npc_id: String) -> bool:
	return _proxies.has(npc_id)


func get_proxy_operations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for op: Dictionary in _proxy_ops:
		out.append(op.duplicate())
	return out


func buy_shares_via_proxy(npc_id: String, quantity: int) -> bool:
	return is_proxy(npc_id) and not npc_id.is_empty() and _buy(quantity, npc_id)


func sell_shares_via_proxy(npc_id: String, quantity: int) -> bool:
	return is_proxy(npc_id) and not npc_id.is_empty() and _sell(quantity, npc_id)


## Perspicacia del ocupante de Auditoría Jefe (0 si vacante o si es el jugador).
func get_chief_auditor_perception() -> float:
	var auditor: String = _cfg_string("insider_detection.auditor_occupation")
	if _player_occupation_id() == auditor:
		return 0.0
	var holder: String = Company.get_seat_holder(auditor)
	if holder.is_empty() or holder == PLAYER_ID:
		return 0.0
	return float(NPCDirector.get_trait(holder, "perception"))


## Solo R25+: titulares programados que el jugador ya conoce (antelación 1-3 jornadas).
## R28+ ve además el sentido de los resultados del trimestre antes de la presentación.
func get_upcoming_news(days_ahead: int) -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in _known_upcoming(days_ahead):
		out.append(str(item["headline_id"]))
	return out


## Sentido de cada noticia conocida (+1 positiva, −1 negativa, 0 neutra), en el orden de arriba.
func get_upcoming_news_directions(days_ahead: int) -> Array[int]:
	var out: Array[int] = []
	for item: Dictionary in _known_upcoming(days_ahead):
		out.append(int(item["direction"]))
	return out


## true si operar ahora en `direction` (TRADE_BUY / TRADE_SELL; TRADE_ANY = cualquiera) sería
## aprovechar una noticia conocida de ese mismo sentido.
func is_trade_informed(direction: int = TRADE_ANY) -> bool:
	for known: int in get_upcoming_news_directions(_cfg_int("insider_detection.news_lead_days_max")):
		if known != TRADE_ANY and (direction == TRADE_ANY or known == direction):
			return true
	return false


# ═══ Persistencia ═════════════════════════════════════════════════════

func save_state() -> Dictionary:
	return {
		"today": _today, "price": _price, "history": _history.duplicate(),
		"steps_today": _steps_today, "noise_today": _noise_today,
		"own_sentiment": _own_sentiment, "fraud_penalty": _fraud_multiple_penalty,
		"confidence": _confidence.duplicate(), "last_reason": _last_reason.duplicate(),
		"credibility_lost": _credibility_lost, "loss_spent": _loss_spent.keys(),
		"campaigns": _campaigns.duplicate(true), "allies": _allies.duplicate(),
		"coerced": _coerced.duplicate(), "pending_reactions": _pending_reactions.duplicate(true),
		"bad_streak": _bad_quarters_streak, "presented_quarter": _presented_quarter,
		"due_emitted_quarter": _due_emitted_quarter, "expected_profit": _expected_quarter_profit,
		"expected_daily_profit": _expected_daily_profit,
		"last_presentation": _last_presentation.duplicate(true),
		"q_real": _q_real.duplicate(), "q_days": _q_days, "q_last_day": _q_last_day,
		"shares": _player_shares, "stake_shares": _stake_shares, "invested": _invested,
		"broker_cash": _broker_cash, "dividends_paid": _dividends_paid,
		"insider_ops": _insider_ops.duplicate(true), "insider_detections": _insider_detections,
		"proxies": _proxies.duplicate(), "proxy_ops": _proxy_ops.duplicate(true),
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	_load_static_data()
	_today = int(data.get("today", 0))
	_price = float(data.get("price", _bf("mercado.precio_inicial")))
	_history.clear()
	for value: Variant in data.get("history", []):
		_history.append(float(value))
	_steps_today = int(data.get("steps_today", 0))
	_noise_today = float(data.get("noise_today", 0.0))
	_own_sentiment = float(data.get("own_sentiment", 0.0))
	_fraud_multiple_penalty = float(data.get("fraud_penalty", 0.0))
	_pending_bribes.clear()
	_load_investor_state(data)
	_load_quarter_state(data)
	_load_portfolio_state(data)
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()


# ═══ Privado: datos ═══════════════════════════════════════════════════

func _load_static_data() -> void:
	_cfg = Database.get_market_params()
	_investors = Database.get_all_investors()
	_strategies.clear()
	for inv: InvestorData in _investors:
		if not _strategies.has(inv.strategy):
			_strategies[inv.strategy] = Database.get_investor_strategy(inv.strategy)
	_starting_fundamentals = _build_starting_fundamentals()
	var references: Variant = Database.get_raw(INVESTORS_FILE).get(BRIBE_REFERENCE_KEY, {})
	_bribe_references = (references as Dictionary).duplicate() if references is Dictionary else {}


func _build_starting_fundamentals() -> Dictionary:
	var sf: Dictionary = _cfg_dict("starting_fundamentals")
	var costs: float = 0.0
	var cost_items: Variant = sf.get("costs_per_day", {})
	if cost_items is Dictionary:
		for key: Variant in (cost_items as Dictionary).keys():
			if not str(key).begins_with("_"):
				costs += float((cost_items as Dictionary)[key])
	var revenue: float = float(sf.get("revenue_per_day", 0.0))
	return {"revenue": revenue, "costs": costs, "profit": revenue - costs,
			"growth_expectation": float(sf.get("growth_expectation", 0.0)),
			"risk_factor": float(sf.get("risk_factor", 0.0))}


func _cfg_value(path: String) -> Variant:
	var node: Variant = _cfg
	for key: String in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = (node as Dictionary)[key]
	return node


func _cfg_float(path: String) -> float:
	var v: Variant = _cfg_value(path)
	return float(v) if v is float or v is int else 0.0


func _cfg_int(path: String) -> int:
	var v: Variant = _cfg_value(path)
	return int(v) if v is float or v is int else 0


func _cfg_string(path: String) -> String:
	var v: Variant = _cfg_value(path)
	return str(v) if v != null else ""


func _cfg_bool(path: String) -> bool:
	var v: Variant = _cfg_value(path)
	return v is bool and v


func _cfg_array(path: String) -> Array:
	var v: Variant = _cfg_value(path)
	return v as Array if v is Array else []


func _cfg_dict(path: String) -> Dictionary:
	var v: Variant = _cfg_value(path)
	return v as Dictionary if v is Dictionary else {}


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _days_per_quarter() -> int:
	return maxi(_bi("tiempo.jornadas_por_trimestre"), 1)


func _days_per_year() -> int:
	return _days_per_quarter() * maxi(_cfg_int("calendar.quarters_per_year"), 1)


func _share_count() -> int:
	return maxi(_cfg_int("shares.share_count"), 1)


## Fundamentales reales de Company (por jornada); los de partida si Company aún no da cifras.
func _fundamentals() -> Dictionary:
	var f: Dictionary = Company.get_fundamentals()
	return _starting_fundamentals if _is_blank_figures(f) else f


func _is_blank_figures(f: Dictionary) -> bool:
	return is_zero_approx(float(f.get("revenue", 0.0))) and is_zero_approx(float(f.get("costs", 0.0)))


func _reported_figures() -> Dictionary:
	var reported: Dictionary = Company.get_reported_figures()
	return _fundamentals() if _is_blank_figures(reported) else reported


func _player_occupation_id() -> String:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation.id if occupation != null else ""


# ═══ Privado: cotización ══════════════════════════════════════════════

func _roll_daily_noise() -> void:
	var amplitude: float = _bf("mercado.ruido_diario_max")
	_noise_today = _rng.randf_range(-amplitude, amplitude)


func _last_close() -> float:
	return _history[_history.size() - 1] if not _history.is_empty() else _price


func _percent_change(from_value: float, to_value: float) -> float:
	if is_zero_approx(from_value):
		return 0.0
	return (to_value - from_value) / from_value * PERCENT_SCALE


func _push_close(value: float) -> void:
	_history.append(value)
	var keep: int = maxi(_bi("mercado.dias_historico"), _bi("mercado.dias_momentum") + 1)
	while _history.size() > keep:
		_history.remove_at(0)


## Estrategia momentum: sigue la tendencia reciente (§9.6).
func _apply_trend_drift() -> void:
	var trend: float = get_momentum() / maxf(_price, _bf("mercado.precio_minimo"))
	if absf(trend) < _bf("mercado.momentum_umbral_tendencia"):
		return
	var step: int = _bi("mercado.momentum_paso_confianza") * (1 if trend > 0.0 else -1)
	for inv: InvestorData in _investors:
		if inv.strategy == STRATEGY_MOMENTUM:
			modify_investor_confidence(inv.id, step, REASON_TREND)


func _on_hour_passed(hour: int, day_number: int) -> void:
	if hour > _bi("tiempo.hora_inicio_jornada") and hour <= _bi("tiempo.hora_fin_jornada"):
		tick_hourly()
	_apply_due_reactions()
	_check_presentation_due(hour, day_number)


func _on_day_advanced(day_number: int) -> void:
	advance_day(day_number)


## results_presentation_due una vez por trimestre (no si el jugador ya presentó).
func _check_presentation_due(hour: int, day_number: int) -> void:
	var quarter: int = quarter_of(day_number)
	if quarter == _due_emitted_quarter or quarter == _presented_quarter:
		return
	if hour != _cfg_int("calendar.results_presentation.hour"):
		return
	if day_in_quarter(day_number) != _cfg_int("calendar.results_presentation.day_of_quarter"):
		return
	_due_emitted_quarter = quarter
	EventBus.results_presentation_due.emit(quarter)


func _calendar_event_on(periodicity: String, day_number: int) -> bool:
	match periodicity:
		PERIOD_DAILY:
			return true
		PERIOD_WEEKLY:
			return day_number > 0 and day_number % maxi(_bi("tiempo.jornadas_por_semana"), 1) == 0
		PERIOD_MONTHLY:
			return day_number > 0 and day_number % maxi(_bi("tiempo.jornadas_por_mes"), 1) == 0
		PERIOD_QUARTERLY:
			return day_in_quarter(day_number) == _cfg_int("calendar.results_presentation.day_of_quarter")
		PERIOD_ANNUAL:
			return day_number > 0 and day_number % _days_per_year() == 0
	return false


# ═══ Privado: inversores ══════════════════════════════════════════════

func _reset_investors() -> void:
	_confidence.clear()
	_last_reason.clear()
	_campaigns.clear()
	_allies.clear()
	_coerced.clear()
	_loss_spent.clear()
	_pending_bribes.clear()
	_pending_reactions.clear()
	_credibility_lost = false
	for inv: InvestorData in _investors:
		_confidence[inv.id] = inv.initial_confidence


func _investor(investor_id: String) -> InvestorData:
	for inv: InvestorData in _investors:
		if inv.id == investor_id:
			return inv
	return null


func _all_investor_ids() -> Array[String]:
	var ids: Array[String] = []
	for inv: InvestorData in _investors:
		ids.append(inv.id)
	return ids


func _strategy_float(inv: InvestorData, key: String) -> float:
	var strategy: Dictionary = _strategies.get(inv.strategy, {})
	return float(strategy.get(key, 0.0))


## Atención no fundamental de la estrategia (sentimiento + dirección + soplos).
func _soft_weight(inv: InvestorData) -> float:
	return _strategy_float(inv, "weight_sentiment") + _strategy_float(inv, "weight_management") \
			+ _strategy_float(inv, "weight_tips")


## Escucha la presentación quien no lee SOLO fundamentales (el inversor de valor no).
func _listens_to_presentation(inv: InvestorData) -> bool:
	return _soft_weight(inv) > 0.0


## Quién reacciona a prensa (§9.6): valor ignora el sentimiento; momentum y cazador leen titulares;
## el activista reacciona a escándalos (dirección); el pasivo solo a desastres (≥ reaction_threshold).
func _reacts_to_press(inv: InvestorData, magnitude: float, is_scandal: bool) -> bool:
	var threshold: float = _strategy_float(inv, "reaction_threshold")
	if threshold > 0.0:
		return is_scandal and magnitude >= threshold
	if _strategy_float(inv, "weight_sentiment") >= _bf("mercado.umbral_reaccion_prensa"):
		return true
	return is_scandal and _strategy_float(inv, "weight_management") > 0.0


func _on_news_published(headline_id: String, sentiment_delta: float, is_scandal: bool) -> void:
	var item: Dictionary = NewsFeed.get_news(headline_id)
	var subject: String = str(item.get("subject", NewsFeedSystem.SUBJECT_COMPANY))
	if str(item.get("source", "")) == NewsFeedSystem.SOURCE_AUDIT:
		return
	if is_scandal and not NewsFeedSystem.is_corporate_subject(subject):
		return
	if not is_scandal and sentiment_delta <= 0.0:
		return
	var magnitude: float = absf(sentiment_delta)
	var factor: String = FACTOR_SCANDAL if is_scandal else FACTOR_PRESS
	var severity: float = clampf(magnitude / _bf("mercado.sentimiento_referencia_prensa"), 0.0, 1.0)
	var now: Array[String] = []
	for inv: InvestorData in _investors:
		if not _reacts_to_press(inv, magnitude, is_scandal):
			continue
		var delay: float = float(inv.extra.get(REACTION_DELAY_KEY, 0))
		if delay <= 0.0:
			now.append(inv.id)
			continue
		_pending_reactions.append({"investor_id": inv.id, "factor": factor, "severity": severity,
				"news_id": headline_id,
				"due_minute": GameClock.get_total_minutes() + delay * MINUTES_PER_HOUR})
	apply_confidence_factor(factor, severity, now)


## Reacciones pendientes cuyo plazo (reaction_delay_hours, §24.4 "reacciona en horas") ya venció.
## Si la noticia se enterró antes, no hay reacción (enterrar también llega a los inversores).
func _apply_due_reactions() -> void:
	var now: float = GameClock.get_total_minutes()
	var due: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for reaction: Dictionary in _pending_reactions:
		if float(reaction["due_minute"]) <= now:
			due.append(reaction)
		else:
			kept.append(reaction)
	_pending_reactions = kept
	for reaction: Dictionary in due:
		if bool(NewsFeed.get_news(str(reaction.get("news_id", ""))).get("buried", false)):
			continue
		var ids: Array[String] = [str(reaction["investor_id"])]
		apply_confidence_factor(str(reaction["factor"]), float(reaction["severity"]), ids)


func get_pending_reactions() -> Array[Dictionary]:
	return _pending_reactions.duplicate(true)


## Falsificación descubierta: −25 a −40 a todos, pérdida permanente de credibilidad y del múltiplo.
func _on_audit_triggered(discrepancy_found: bool) -> void:
	if not discrepancy_found:
		return
	apply_confidence_factor(FACTOR_FRAUD, _figures_divergence_severity(), _all_investor_ids())
	if _cfg_bool("confidence_factors.falsification_permanent_credibility_loss"):
		_credibility_lost = true
	_fraud_multiple_penalty += _bf("mercado.penalizacion_multiplo_fraude")


## Magnitud auditada (Company.get_last_audit; si no, reportado frente a real hoy) sobre el rango.
func _figures_divergence_severity() -> float:
	var audit: Dictionary = Company.get_last_audit()
	var divergence: float = float(audit.get("divergence", -1.0))
	if divergence < 0.0:
		var real: float = float(_fundamentals().get("profit", 0.0))
		var reported: float = float(_reported_figures().get("profit", 0.0))
		divergence = absf(reported - real) / maxf(absf(real), 1.0)
	return clampf(divergence / _bf("mercado.presentacion_rango_sorpresa"), 0.0, 1.0)


## Al cruzar a la baja umbral_perdida_confianza, el inversor ejecuta su on_confidence_loss:
## impulso de sentimiento (× social_reach) y, el activista, campaña contra la dirección. Se rearma
## al recuperar umbral + rearme_perdida_confianza (evita desbandadas repetidas en torno al umbral).
func _check_confidence_loss(investor_id: String, old_value: int, new_value: int) -> void:
	var threshold: int = _bi("mercado.umbral_perdida_confianza")
	if new_value >= threshold + _bi("mercado.rearme_perdida_confianza"):
		_loss_spent.erase(investor_id)
	if old_value < threshold or new_value >= threshold or _loss_spent.has(investor_id):
		return
	var inv: InvestorData = _investor(investor_id)
	if inv == null or inv.on_confidence_loss.is_empty():
		return
	_loss_spent[investor_id] = true
	var reach: float = float(inv.extra.get(SOCIAL_REACH_KEY, NEUTRAL_MULTIPLIER))
	var impulse: float = _bf("mercado.impulsos_perdida_confianza." + inv.on_confidence_loss)
	_add_own_sentiment(impulse * reach)
	if inv.on_confidence_loss == BEHAVIOUR_CAMPAIGN and get_activist_target(investor_id).is_empty():
		_start_campaign(investor_id, PLAYER_ID)


func _add_own_sentiment(delta: float) -> void:
	var cap: float = _bf("mercado.sentimiento_max")
	_own_sentiment = clampf(_own_sentiment + delta, -cap, cap)


func _start_campaign(investor_id: String, target: String) -> void:
	_campaigns[investor_id] = {
		CAMPAIGN_INVESTOR: investor_id, CAMPAIGN_TARGET: target, CAMPAIGN_SINCE: _today,
		CAMPAIGN_UNTIL: _today + _bi("mercado.dias_campana_activista"),
	}


func _expire_campaigns() -> void:
	for investor_id: Variant in _campaigns.keys():
		if int((_campaigns[investor_id] as Dictionary)[CAMPAIGN_UNTIL]) < _today:
			_campaigns.erase(investor_id)


func _on_bribe_offered(npc_id: String, _amount: int, favour_type: String) -> void:
	_pending_bribes[npc_id] = favour_type


## Soborno aceptado: el inversor con el favor de pregunta favorable es aliado del trimestre; un
## personaje con el favor de testaferro puede operar en nombre del jugador.
func _on_bribe_result(npc_id: String, accepted: bool, _outcome: String) -> void:
	var favour: String = str(_pending_bribes.get(npc_id, ""))
	_pending_bribes.erase(npc_id)
	if not accepted or favour.is_empty():
		return
	if _investor(npc_id) != null:
		if favour == get_favourable_question_favour() and is_investor_bribable(npc_id):
			_allies[npc_id] = quarter_of(_today)
	elif favour == str(Database.get_balance("mercado.favor_testaferro")):
		_proxies[npc_id] = _today


## El jugador chantajea a un inversor chantajeable: coaccionado y aliado este trimestre.
func _on_blackmail_initiated(npc_id: String, _target: String, _leverage: String) -> void:
	if not is_investor_blackmailable(npc_id):
		return
	var quarter: int = quarter_of(_today)
	_coerced[npc_id] = quarter
	_allies[npc_id] = quarter


## Un testaferro o el objetivo de una campaña que sale de la empresa.
func _on_npc_removed(npc_id: String, _cause: String) -> void:
	_proxies.erase(npc_id)
	for investor_id: Variant in _campaigns.keys():
		if str((_campaigns[investor_id] as Dictionary)[CAMPAIGN_TARGET]) == npc_id:
			_campaigns.erase(investor_id)


func _load_investor_state(data: Dictionary) -> void:
	_reset_investors()
	var saved: Variant = data.get("confidence", {})
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary).keys():
			if _confidence.has(str(key)):
				_confidence[str(key)] = int((saved as Dictionary)[key])
	_last_reason = _as_dict(data.get("last_reason", {}))
	for investor_id: Variant in data.get("loss_spent", []):
		_loss_spent[str(investor_id)] = true
	_credibility_lost = bool(data.get("credibility_lost", false))
	_allies = _int_values(data.get("allies", {}))
	_coerced = _int_values(data.get("coerced", {}))
	for entry: Variant in data.get("pending_reactions", []):
		var r: Dictionary = _as_dict(entry)
		_pending_reactions.append({"investor_id": str(r.get("investor_id", "")),
				"factor": str(r.get("factor", "")), "severity": float(r.get("severity", 0.0)),
				"news_id": str(r.get("news_id", "")), "due_minute": float(r.get("due_minute", 0.0))})
	_load_campaigns(_as_dict(data.get("campaigns", {})))


func _load_campaigns(campaigns: Dictionary) -> void:
	for investor_id: Variant in campaigns.keys():
		var c: Dictionary = _as_dict(campaigns[investor_id])
		_campaigns[str(investor_id)] = {
			CAMPAIGN_INVESTOR: str(investor_id), CAMPAIGN_TARGET: str(c.get(CAMPAIGN_TARGET, "")),
			CAMPAIGN_SINCE: int(c.get(CAMPAIGN_SINCE, 0)), CAMPAIGN_UNTIL: int(c.get(CAMPAIGN_UNTIL, 0)),
		}


static func _as_dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _int_values(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in _as_dict(value).keys():
		out[str(key)] = int((value as Dictionary)[key])
	return out


# ═══ Privado: presentación y trimestre ════════════════════════════════

func _reset_quarter_state() -> void:
	_bad_quarters_streak = 0
	_presented_quarter = 0
	_due_emitted_quarter = 0
	_last_presentation = {}
	_q_real = {}
	_q_days = 0
	_q_last_day = _today - 1
	_expected_quarter_profit = float(_fundamentals().get("profit", 0.0)) * float(_days_per_quarter())


func _presentation_quality(preparation: float, allies_present: int, reputation: float) -> float:
	return _cfg_float("presentation.weight_preparation") * clampf(preparation, 0.0, 1.0) \
			+ _cfg_float("presentation.weight_reputation") \
			* clampf(reputation / PERCENT_SCALE, 0.0, 1.0) \
			+ _cfg_float("presentation.weight_allies") * get_allies_ratio(allies_present)


## Fase de reacción: aplica compute_presentation_reaction y convierte el cambio en sentimiento.
func _run_presentation(quality: float, presenter: String) -> Dictionary:
	var figures: float = get_figures_score()
	var before: float = get_aggregate_confidence()
	var reaction: Dictionary = compute_presentation_reaction(quality, figures)
	var changes: Dictionary = {}
	for inv: InvestorData in _investors:
		var delta: int = int(reaction[inv.id])
		var old_value: int = get_investor_confidence(inv.id)
		modify_investor_confidence(inv.id, delta, _reaction_reason(delta, figures))
		changes[inv.id] = get_investor_confidence(inv.id) - old_value
	var sentiment_delta: float = _sentiment_from_changes(changes)
	_add_own_sentiment(sentiment_delta)
	_expected_quarter_profit = float(get_quarter_reported_figures(true)["profit"])
	_last_presentation = {
		"quality": quality, "confidence_changes": changes, "sentiment_delta": sentiment_delta,
		"outcome": compute_presentation_outcome(quality, figures), "figures_score": figures,
		"aggregate_before": before, "aggregate_after": get_aggregate_confidence(),
		"quarter": quarter_of(_today), "presenter": presenter,
	}
	return _last_presentation.duplicate(true)


## Motivo mostrado: si las cifras apuntan al lado contrario, la culpa (o el mérito) es de la
## presentación, no de los resultados.
func _reaction_reason(delta: int, figures: float) -> String:
	if delta > 0:
		return REASON_PRESENTATION_ABOVE if figures < OUTCOME_NEUTRAL else FACTOR_ABOVE
	return REASON_PRESENTATION_BELOW if figures > OUTCOME_NEUTRAL else FACTOR_BELOW


## Desviación del resultado percibido sobre 0,5: banda neutra, umbral propio (pasivo) y tabla §9.7.
func _outcome_delta(inv: InvestorData, perceived: float) -> int:
	var deviation: float = perceived - OUTCOME_NEUTRAL
	var magnitude: float = absf(deviation)
	var threshold: float = _strategy_float(inv, "reaction_threshold")
	var band: float = _bf("mercado.presentacion_banda_neutra")
	if (threshold > 0.0 and magnitude < threshold) or magnitude <= band:
		return 0
	var severity: float = (magnitude - band) / (OUTCOME_NEUTRAL - band)
	return get_factor_delta(FACTOR_ABOVE if deviation > 0.0 else FACTOR_BELOW, severity)


## Δsentimiento = Σ Δconfianza_i × voz_i ÷ 100 × sentimiento_por_confianza;
## voz_i = capital_i/Σcapital + (social_reach_i − 1) × peso_alcance_social.
func _sentiment_from_changes(changes: Dictionary) -> float:
	var capital: float = 0.0
	for inv: InvestorData in _investors:
		capital += float(inv.capital)
	if capital <= 0.0:
		return 0.0
	var total: float = 0.0
	for inv: InvestorData in _investors:
		var reach: float = float(inv.extra.get(SOCIAL_REACH_KEY, NEUTRAL_MULTIPLIER))
		var voice: float = float(inv.capital) / capital \
				+ (reach - NEUTRAL_MULTIPLIER) * _bf("mercado.peso_alcance_social")
		total += float(changes.get(inv.id, 0)) * voice
	return total / PERCENT_SCALE * _bf("mercado.sentimiento_por_confianza")


func _on_quarter_closed(quarter_number: int) -> void:
	if _presented_quarter != quarter_number:
		_present_without_player()
		_presented_quarter = quarter_number
	_update_bad_quarter_streak(quarter_number)
	if quarter_number % maxi(_cfg_int("calendar.quarters_per_year"), 1) == 0:
		_pay_dividends()
	var real: Dictionary = get_quarter_real_figures(false)
	var reported: Dictionary = get_quarter_reported_figures(false)
	_q_real = {}
	_q_days = 0
	_q_last_day = maxi(_q_last_day, _today)
	EventBus.quarter_reported.emit(real, reported)


## Sin presentación del jugador: un NPC presenta (neutro) o, si el jugador es R28+, incomparecencia.
func _present_without_player() -> void:
	if PlayerState.get_rank() >= _cfg_int("board_pressure.applies_from_rank"):
		var unprepared: float = float(get_preparation_levels().get(LEVEL_NONE, 0.0))
		_run_presentation(_presentation_quality(unprepared, 0, PlayerState.get_reputation()),
				PRESENTER_NO_SHOW)
		return
	_run_presentation(_presentation_quality(_bf("mercado.preparacion_presentador_npc"),
			_bi("mercado.aliados_presentador_npc"), _bf("mercado.reputacion_presentador_npc")),
			PRESENTER_NPC)


func _update_bad_quarter_streak(quarter_number: int) -> void:
	if PlayerState.get_rank() < _cfg_int("board_pressure.applies_from_rank"):
		_bad_quarters_streak = 0
	elif get_aggregate_confidence() >= get_target_for_quarter(quarter_number):
		_bad_quarters_streak = 0
	else:
		_bad_quarters_streak += 1


## Suma el beneficio real de la jornada a las cifras del trimestre (una vez por jornada).
func _accumulate_day(day_number: int) -> void:
	if day_number <= _q_last_day:
		return
	var f: Dictionary = _fundamentals()
	for key: String in FIGURE_KEYS:
		_q_real[key] = float(_q_real.get(key, 0.0)) + float(f.get(key, 0.0))
	_expected_daily_profit = get_expected_daily_profit()
	_q_days += 1
	_q_last_day = day_number


## Noticias conocidas por el jugador: [{headline_id, direction}] (R25 programadas; R28 resultados).
func _known_upcoming(days_ahead: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rank: int = PlayerState.get_rank()
	if rank < _cfg_int("insider_detection.upcoming_news_min_rank"):
		return out
	for item: Dictionary in NewsFeed.get_scheduled_news(days_ahead):
		if rank >= int(item.get("min_rank", 0)):
			out.append({"headline_id": str(item.get("headline_id", "")),
					"direction": _news_direction(item)})
	if rank >= _cfg_int("shares.insider_information_min_rank"):
		var preview: String = _results_preview(days_ahead)
		if not preview.is_empty():
			out.append({"headline_id": preview, "direction": int(RESULTS_DIRECTIONS[preview])})
	return out


## Sentido de una noticia programada: signo del sentimiento; si es neutro, del efecto en ingresos.
static func _news_direction(item: Dictionary) -> int:
	var sentiment: float = float(item.get("sentiment", 0.0))
	if not is_zero_approx(sentiment):
		return TRADE_BUY if sentiment > 0.0 else TRADE_SELL
	var effects: Variant = item.get("effects", {})
	var revenue: float = float((effects as Dictionary).get(REVENUE_EFFECT, NEUTRAL_MULTIPLIER)) \
			if effects is Dictionary else NEUTRAL_MULTIPLIER
	if is_equal_approx(revenue, NEUTRAL_MULTIPLIER):
		return TRADE_ANY
	return TRADE_BUY if revenue > NEUTRAL_MULTIPLIER else TRADE_SELL


## Titular del sentido de los resultados si la presentación está a la vista (R28+).
func _results_preview(days_ahead: int) -> String:
	var days_left: int = get_presentation_day() - _today
	var horizon: int = mini(days_ahead, _cfg_int("insider_detection.news_lead_days_max"))
	if days_left < 0 or days_left > horizon or _presented_quarter == quarter_of(_today):
		return ""
	var deviation: float = get_figures_score() - OUTCOME_NEUTRAL
	if absf(deviation) <= _bf("mercado.presentacion_banda_neutra"):
		return HEADLINE_RESULTS_INLINE
	return HEADLINE_RESULTS_BEAT if deviation > 0.0 else HEADLINE_RESULTS_MISS


func _load_quarter_state(data: Dictionary) -> void:
	_bad_quarters_streak = int(data.get("bad_streak", 0))
	_presented_quarter = int(data.get("presented_quarter", 0))
	_due_emitted_quarter = int(data.get("due_emitted_quarter", 0))
	_expected_quarter_profit = float(data.get("expected_profit", 0.0))
	_expected_daily_profit = float(data.get("expected_daily_profit",
			float(_fundamentals().get("profit", 0.0))))
	_last_presentation = _as_dict(data.get("last_presentation", {}))
	_q_real = {}
	var sums: Dictionary = _as_dict(data.get("q_real", {}))
	for key: String in FIGURE_KEYS:
		if sums.has(key):
			_q_real[key] = float(sums[key])
	_q_days = int(data.get("q_days", 0))
	_q_last_day = int(data.get("q_last_day", _today - 1))


# ═══ Privado: cartera e insider ═══════════════════════════════════════

func _reset_portfolio() -> void:
	_player_shares = 0
	_stake_shares = 0
	_invested = 0.0
	_broker_cash = 0
	_dividends_paid = 0
	_insider_ops.clear()
	_insider_detections = 0
	_proxies.clear()
	_proxy_ops.clear()


## Compra (proxy_id "" = a nombre del jugador). La operación informada se registra DESPUÉS de
## ejecutarse (el volumen es el coste).
func _buy(quantity: int, proxy_id: String) -> bool:
	if quantity <= 0 or not can_trade() or get_buy_cost(quantity) > _broker_cash:
		return false
	var cost: int = get_buy_cost(quantity)
	var informed: bool = is_trade_informed(TRADE_BUY)
	_add_shares(quantity, cost)
	if informed:
		_register_informed(cost, proxy_id)
	return true


func _sell(quantity: int, proxy_id: String) -> bool:
	if quantity <= 0 or quantity > _player_shares or not can_trade():
		return false
	var proceeds: int = get_sell_proceeds(quantity)
	var informed: bool = is_trade_informed(TRADE_SELL)
	_invested -= _invested * float(quantity) / float(_player_shares)
	_player_shares -= quantity
	if _player_shares < _stake_shares:
		_stake_shares = 0
	_broker_cash += proceeds
	if informed:
		_register_informed(proceeds, proxy_id)
	return true


func _add_shares(quantity: int, cost: int) -> void:
	_broker_cash -= cost
	_player_shares += quantity
	_invested += float(cost)


func _register_informed(volume: int, proxy_id: String) -> void:
	if proxy_id.is_empty():
		register_insider_operation(volume)
	else:
		register_proxy_operation(proxy_id, volume)


## Junta anual: el dividendo se abona en la cuenta de valores.
func _pay_dividends() -> void:
	var amount: int = get_dividend_income()
	if amount <= 0:
		return
	_dividends_paid += amount
	_broker_cash += amount


func _insider_detection_disabled() -> bool:
	return _cfg_bool("insider_detection.zero_if_player_is_auditor") \
			and _player_occupation_id() == _cfg_string("insider_detection.auditor_occupation")


## Espaciar las operaciones es una contramedida: solo cuentan las de la ventana de jornadas.
func _prune_insider_ops() -> void:
	var window: int = _bi("mercado.ventana_patron_insider_jornadas")
	var kept: Array[Dictionary] = []
	for op: Dictionary in _insider_ops:
		if _today - int(op["day"]) < window:
			kept.append(op)
	_insider_ops = kept


func _load_portfolio_state(data: Dictionary) -> void:
	_reset_portfolio()
	_player_shares = int(data.get("shares", 0))
	_stake_shares = int(data.get("stake_shares", 0))
	_invested = float(data.get("invested", 0.0))
	_broker_cash = int(data.get("broker_cash", 0))
	_dividends_paid = int(data.get("dividends_paid", 0))
	_insider_detections = int(data.get("insider_detections", 0))
	for entry: Variant in data.get("insider_ops", []):
		if entry is Dictionary:
			_insider_ops.append({"day": int((entry as Dictionary).get("day", 0)),
					"volume": int((entry as Dictionary).get("volume", 0))})
	_proxies = _int_values(data.get("proxies", {}))
	for entry: Variant in data.get("proxy_ops", []):
		if entry is Dictionary:
			var op: Dictionary = entry as Dictionary
			_proxy_ops.append({"day": int(op.get("day", 0)), "npc_id": str(op.get("npc_id", "")),
					"volume": int(op.get("volume", 0))})
