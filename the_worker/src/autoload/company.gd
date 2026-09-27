# company.gd — Sillas, promoción del jugador, fundamentales, cifras reportadas, mecha de auditoría y descontento.
# PROPIETARIO DE: sillas y titulares (también la del jugador), Rookies contratados, mérito reciente del jugador, fundamentales y sus entradas (marca, calidad, eficiencia, cuota, recorte, nómina, pérdidas por robo, escándalos, prensa negativa, rotación directiva, eliminaciones, historial trimestral, productos en desarrollo), cifras reportadas, mecha de auditoría, descontento y huelga (§19.8).
# ESCUCHA: day_advanced, week_closed, quarter_closed, quarter_reported, npc_removed, occupation_changed, reputation_changed, news_published, news_buried, idea_presented, duty_completed, bribe_offered, bribe_result, strike_resolved.
class_name CompanySystem
extends Node

## Manual §6.1-§6.3, §9.2, §9.9, §9.10, §11.6, §11.7, §19.8; PASO 21 y PASO 32; BUILD_NOTES §2, §13.
## Emite: seat_vacated, seat_filled, occupation_changed, promotion_available, promotion_declined,
## merit_gained, fundamentals_updated, audit_fuse_lit, audit_triggered, strike_discontent_changed,
## strike_started, game_over, notebook_entry_added.
## DECISIONES (contrato para el resto de sistemas):
##  · SILLAS. Cada ocupación tiene una o varias sillas {occupation_id, seat_index, holder, temporary,
##    vacated_day, cause}; holder "" = vacante, "player" = el jugador. reset_for_new_run() las
##    construye con NPCDirector.get_all_npcs() (índice = NPCDirector.get_seat_index) más la silla del
##    jugador (índice siguiente de su ocupación). Una ocupación sin titulares al empezar no tiene
##    sillas (partidas sin población de los tests: ni vacantes ni contrataciones).
##    get_seat_holder(occ) = titular de la primera silla, o "" si ALGUNA silla de occ está vacante
##    (coherente con is_seat_vacant). vacate_seat(occ, causa) libera la primera silla ocupada por un
##    personaje (nunca la del jugador); vacate_npc_seat(id, causa) libera la de ese personaje.
##  · VACANTES (§6.3). Una vacante queda abierta empresa.jornadas_vacante_abierta jornadas (ventana
##    del jugador) y al empezar la jornada en que vence se repone en cadena: 1) sucesor designado
##    (perfil future_occupation de NPCDirector); 2) personaje activo cuya ocupación lleva la vacante
##    en promotes_to (rango ≥ empresa.rango_minimo_candidato: el becario eterno no asciende solo) con
##    mayor mérito × npc.puntuacion_ascenso_merito + ambición × npc.puntuacion_ascenso_ambicion;
##    3) si no hay, el mejor de los empresa.rangos_busqueda_ampliada rangos inferiores; 4) si nadie
##    cualifica, RR. HH. contrata un Rookie con id "npc_hire_NNN" (get_hires, is_hire). La silla que
##    deja quien asciende se libera con causa "promoted" y se repone en el acto: la cadena baja hasta
##    la contratación. auto_fill_vacancies() repone TODAS las vacantes ya, sin esperar.
##  · CONTRATACIÓN: Company acuña el id y emite seat_filled(occ, id); NPCDirector (dueño de los
##    personajes) crea el NPCRuntime Rookie al oír seat_filled de un id desconocido con is_hire(id).
##  · FAVOR Y AGRAVIO (§6.3): los apunta NPCDirector al oír las señales de silla (causas atribuibles
##    al jugador: expelled, expulsion, fired, framed, eliminated, elimination, demoted,
##    player_promoted, player_lateral). get_last_fill_context() detalla el último relleno:
##    {occupation_id, holder, kind: promotion|successor|hire|player|assigned, from_occupation,
##    vacancy_cause, player_caused, favour_to, grievance_to, day}.
##  · PROMOCIÓN DEL JUGADOR (§6.2): can_player_promote_to → missing ⊂ [path, reputation, merit,
##    vacancy] ("path", extra = no alcanzable desde el puesto actual). Destinos: promotes_to +
##    can_jump_to (tres condiciones) y lateral_to de rango ≤ actual (lateral: sin mérito). Mérito
##    mínimo por escalón de destino (empresa.merito_minimo_por_escalon); caduca a las
##    empresa.jornadas_caducidad_merito jornadas y un ascenso lo consume. Reputación ≥ mínima +
##    empresa.margen_reputacion_crear_puesto (escalón ≤ escalon_max_crear_puesto) "crea el puesto": no
##    hace falta vacante y se añade una silla temporal (desaparece cuando el jugador la deja).
##    promote_player emite seat_vacated(antigua, "player", player_promoted|player_lateral),
##    seat_filled(nueva, "player") y occupation_changed(antigua, nueva, promotion|lateral|
##    created_post): PlayerState adopta la ocupación al oír occupation_changed.
##    promotion_available(ids) se emite al empezar cada jornada si hay destinos permitidos y cuando la
##    lista cambia. decline_promotion(occ) emite promotion_declined y repone ya esa vacante.
##  · DESCENSOS (§6.1): demote_player(motivo) → primer demotes_to con vacante (si no, silla
##    temporal). En R0 → game_over("failed_at_r0"); en R33 por "board_pressure" → game_over(
##    "board_removal"). Company degrada por sí misma ante la presión del consejo (quarter_reported con
##    Market.is_board_pressure_triggered()) y las cifras afloradas por la auditoría (salvo
##    empresa.cargos_sin_descenso_por_cifras: ahí la consecuencia es la investigación de Security).
##  · occupation_changed ajeno (depuración, tutorial): la silla del jugador se sincroniza EN SILENCIO.
##  · MÉRITO DEL JUGADOR: register_merit (IdeaPresentation, DutySystem) + "éxito visible"
##    (duty_completed con calidad ≥ empresa.calidad_exito_visible y método en metodos_exito_visible)
##    + "recomendación" (soborno aceptado del favor empresa.favor_recomendacion; Bribery no la apunta).
##  · FUNDAMENTALES (§9.2), POR JORNADA. unidades = base × eficiencia efectiva × calidad × fuerza
##    comercial × cuota (× factor_unidades_huelga en huelga); ingresos = unidades × precio × marca;
##    costes = materiales (∝ unidades, × (1 − recorte)) + nóminas (× concesiones) + generales +
##    legales (+ por investigación abierta) + pérdidas por robo + escándalos (estos dos: suma de la
##    ventana empresa.jornadas_ventana_contable ÷ ventana); crecimiento = tendencia de los últimos
##    trimestres + productos en desarrollo (ideas presentadas en la ventana); riesgo = suma ponderada
##    (market.json risk_factor_weights) de investigaciones abiertas, prensa negativa viva, huelga y
##    rotación directiva (sillas de escalón ≥ escalon_directivo liberadas, salvo "promoted") +
##    eliminaciones × empresa.riesgo_por_eliminacion. Eficiencia y fuerza comercial bajan con las
##    vacantes de sus departamentos. Recalculo en cada day_advanced y al instante tras una llamada
##    directa (add_theft_loss, modify_*, palancas, concesión salarial); las señales esperan al día.
##  · IRONÍA (§9.10): add_theft_loss → costes; npc_removed (expulsión o eliminación) de escalón ≥
##    empresa.escalon_talento_cualificado → calidad y get_idea_generation_modifier() bajan;
##    escándalo (news_published is_scandal) → coste y riesgo (news_buried los retira). Company NO
##    escucha crime_committed: quien ejecuta el robo en fábrica llama a add_theft_loss.
##  · CIFRAS REPORTADAS: get_reported_figures() = fundamentales si no hay otras. set_reported_figures
##    solo con el jugador en empresa.cargos_cifras_reportadas. Divergencia = máx |reportado − real| ÷
##    |real| en revenue/costs/profit, acotada a [0, 1]; toda divergencia enciende la mecha: semanas =
##    audit_fuse de market.json (8 − 6 × divergencia) acotada a balance mercado.mecha_auditoria_*
##    y, por cargo, a empresa.mecha_max_semanas_por_cargo (B10: dos semanas, §9.9); una segunda
##    falsificación acorta la vigente. Cuenta atrás con week_closed; al expirar, probabilidad =
##    perspicacia del titular de Auditoría Jefe ÷ 100 × factor (0 si es el jugador o está vacante)
##    → audit_triggered(encontrada); get_last_audit() conserva la magnitud auditada. Las cifras
##    reportadas se retiran al oír quarter_reported (el trimestre ya se comunicó).
##  · DESCONTENTO (§11.7), 0-100: modify_discontent; apply_labour_event(id) aplica un factor de la
##    tabla (unjust_dismissal, payroll_manipulation_discovered, wage_concession, culprit_dismissed);
##    diarios: cuota > empresa.cuota_razonable_max y recorte de costes > 0; término de ánimo =
##    round(−ánimo medio de escalones ≤ descontento.escalon_max_afectado × por_animo_diario). Una
##    expulsión (npc_removed) de escalón ≤ ese máximo cuenta como despido injusto. Cruzar
##    umbral_huelga hacia arriba sin huelga activa → strike_started; strike_resolved la termina.
##    Agitar, apaciguar, liderar y traicionar son del módulo Strike (modify_discontent).

const PLAYER_ID := "player"
const HIRE_ID_FORMAT := "npc_hire_%03d"
const RNG_SALT := "company"
const SAVE_VERSION := 1
const NO_DAY := -1
const NO_RANK := -1
const NEUTRAL := 1.0
const PERCENT := 100.0
const EPSILON := 0.000001
## Una tendencia necesita al menos dos trimestres.
const MIN_TREND_POINTS := 2
const DISCONTENT_MIN := 0
const DISCONTENT_MAX := 100
const TRAIT_AMBITION := "ambition"
const TRAIT_PERCEPTION := "perception"
const DEPARTMENT_KEY := "department"
const LATERAL_KEY := "lateral_to"

# Claves de una silla.
const S_OCC := "occupation_id"
const S_INDEX := "seat_index"
const S_HOLDER := "holder"
const S_TEMP := "temporary"
const S_DAY := "vacated_day"
const S_CAUSE := "cause"

# Condiciones de promoción (§6.2).
const MISSING_PATH := "path"
const MISSING_REPUTATION := "reputation"
const MISSING_MERIT := "merit"
const MISSING_VACANCY := "vacancy"
const MISSING_LABEL_KEYS: Dictionary = {
	MISSING_PATH: "PROMO_MISSING_PATH", MISSING_REPUTATION: "PROMO_MISSING_REPUTATION",
	MISSING_MERIT: "PROMO_MISSING_MERIT", MISSING_VACANCY: "PROMO_MISSING_VACANCY",
}
const MOVE_NONE := ""
const MOVE_UP := "up"
const MOVE_LATERAL := "lateral"

# Causas de vacante que emite Company (las de npc_removed se reenvían tal cual).
const CAUSE_PROMOTED := "promoted"
const CAUSE_PLAYER_PROMOTED := "player_promoted"
const CAUSE_PLAYER_LATERAL := "player_lateral"
const CAUSE_DEMOTED := "demoted"
const CAUSE_RETIRED := "retired"
const CAUSE_REASSIGNED := "reassigned"
const DISMISSAL_CAUSES: Array[String] = ["expelled", "expulsion", "fired", "framed"]
const ELIMINATION_CAUSES: Array[String] = ["eliminated", "elimination"]
## Espejo de NPCDirector.PLAYER_CAUSED_VACANCIES (+ player_lateral): favor a quien ocupe la silla.
const PLAYER_CAUSES: Array[String] = [
	"expelled", "expulsion", "fired", "framed", "eliminated", "elimination", "demoted",
	"demotion", "player_promoted", "player_lateral", "displaced_by_player",
]

# Tipos de relleno (get_last_fill_context) y motivos de occupation_changed.
const FILL_PROMOTION := "promotion"
const FILL_SUCCESSOR := "successor"
const FILL_HIRE := "hire"
const FILL_PLAYER := "player"
const FILL_ASSIGNED := "assigned"
const REASON_PROMOTION := "promotion"
const REASON_LATERAL := "lateral"
const REASON_CREATED_POST := "created_post"
const REASON_DEMOTION := "demotion"
const REASON_ASSIGNED := "assigned"

# Descensos y fin de partida.
const DEMOTION_BOARD := "board_pressure"
const DEMOTION_FIGURES := "figures_surfaced"
const CAUSE_FAILED_AT_R0 := "failed_at_r0"
const CAUSE_BOARD_REMOVAL := "board_removal"
const MARKET_BOARD_GETTER := "is_board_pressure_triggered"

# Mérito.
const MERIT_DUTY := "duty_success"
const MERIT_RECOMMENDATION := "bribed_recommendation"

# Descontento: factores de la tabla §11.7.
const EVENT_UNJUST_DISMISSAL := "unjust_dismissal"
const EVENT_PAYROLL_DISCOVERED := "payroll_manipulation_discovered"
const EVENT_WAGE_CONCESSION := "wage_concession"
const EVENT_CULPRIT_DISMISSED := "culprit_dismissed"
const LABOUR_EVENTS: Dictionary = {
	EVENT_UNJUST_DISMISSAL: "descontento.por_despido_injusto",
	EVENT_PAYROLL_DISCOVERED: "descontento.por_manipulacion_nominas",
	EVENT_WAGE_CONCESSION: "descontento.reduccion_por_concesion",
	EVENT_CULPRIT_DISMISSED: "descontento.reduccion_por_despedir_causante",
}
const CAUSE_EXCESSIVE_QUOTA := "excessive_quota"
const CAUSE_DEGRADED_FACTORY := "degraded_factory"
const CAUSE_MOOD := "workforce_mood"

# Cuaderno.
const NOTE_CATEGORY := "career"
const NOTE_PROMOTION_AVAILABLE := "NOTE_PROMOTION_AVAILABLE"
const NOTE_BY_REASON: Dictionary = {
	REASON_PROMOTION: "NOTE_CAREER_PROMOTED", REASON_LATERAL: "NOTE_CAREER_LATERAL",
	REASON_CREATED_POST: "NOTE_CAREER_CREATED_POST", REASON_DEMOTION: "NOTE_CAREER_DEMOTED",
}
const NOTE_DECLINED := "NOTE_CAREER_DECLINED"
const NOTE_FUSE_LIT := "NOTE_AUDIT_FUSE_LIT"

# Fundamentales.
const FIGURE_KEYS: Array[String] = ["revenue", "costs", "profit"]
const COST_KEYS: Array[String] = [
	"materials", "payroll", "overheads", "legal", "theft_losses", "scandal_costs",
]
const K_MATERIALS := "materials"
const K_PAYROLL := "payroll"
const K_OVERHEADS := "overheads"
const K_LEGAL := "legal"
const K_THEFT := "theft_losses"
const K_SCANDAL := "scandal_costs"
const K_UNITS := "units"
const K_PRICE := "avg_price"
const K_BRAND := "brand_strength"
const K_QUALITY := "product_quality"
const K_GROWTH := "growth_expectation"
const K_RISK := "risk_factor"
const F_DIVERGENCE := "divergence"
const F_WEEKS := "weeks_left"
const F_DAY := "lit_day"
const L_DAY := "day"
const L_AMOUNT := "amount"
const L_ID := "id"
const CFG_START := "starting_fundamentals"
const CFG_COSTS := "costs_per_day"
const CFG_RISK := "risk_factor_weights"
const CFG_FUSE := "audit_fuse"
const CFG_INSIDER := "insider_detection"

# Rutas de balance.json.
const B_VACANCY_DAYS := "empresa.jornadas_vacante_abierta"
const B_MERIT_BY_TIER := "empresa.merito_minimo_por_escalon.%d"
const B_MERIT_DAYS := "empresa.jornadas_caducidad_merito"
const B_CREATE_MARGIN := "empresa.margen_reputacion_crear_puesto"
const B_CREATE_MAX_TIER := "empresa.escalon_max_crear_puesto"
const B_MIN_CANDIDATE_RANK := "empresa.rango_minimo_candidato"
const B_WIDEN_RANKS := "empresa.rangos_busqueda_ampliada"
const B_DUTY_MERIT := "empresa.merito_deber_exitoso"
const B_DUTY_QUALITY := "empresa.calidad_exito_visible"
const B_DUTY_METHODS := "empresa.metodos_exito_visible"
const B_RECOMMEND_FAVOUR := "empresa.favor_recomendacion"
const B_RECOMMEND_MERIT := "empresa.merito_recomendacion"
const B_REPORT_POSTS := "empresa.cargos_cifras_reportadas"
const B_NO_DEMOTION_POSTS := "empresa.cargos_sin_descenso_por_cifras"
const B_AUDIT_FACTOR := "empresa.factor_deteccion_auditoria"
const B_WINDOW := "empresa.jornadas_ventana_contable"
const B_SCANDAL_COST := "empresa.coste_por_escandalo"
const B_LEGAL_PER_CASE := "empresa.coste_legal_por_investigacion"
const B_RISK_ELIMINATION := "empresa.riesgo_por_eliminacion"
const B_EXEC_TIER := "empresa.escalon_directivo"
const B_TALENT_TIER := "empresa.escalon_talento_cualificado"
const B_QUALITY_LOSS := "empresa.calidad_por_talento_perdido"
const B_IDEAS_LOSS := "empresa.ideas_por_talento_perdido"
const B_IDEAS_MIN := "empresa.modificador_ideas_min"
const B_QUALITY_MIN := "empresa.calidad_min"
const B_QUALITY_MAX := "empresa.calidad_max"
const B_BRAND_MIN := "empresa.marca_min"
const B_BRAND_MAX := "empresa.marca_max"
const B_EFFICIENCY_MIN := "empresa.eficiencia_min"
const B_EFFICIENCY_MAX := "empresa.eficiencia_max"
const B_QUOTA_MIN := "empresa.cuota_min"
const B_QUOTA_MAX := "empresa.cuota_max"
const B_QUOTA_REASONABLE := "empresa.cuota_razonable_max"
const B_CUT_MAX := "empresa.recorte_costes_max"
const B_FACTORY_DEPTS := "empresa.departamentos_fabrica"
const B_FACTORY_WEIGHT := "empresa.peso_vacantes_fabrica"
const B_SALES_DEPTS := "empresa.departamentos_comerciales"
const B_SALES_WEIGHT := "empresa.peso_vacantes_comerciales"
const B_STRIKE_UNITS := "empresa.factor_unidades_huelga"
const B_GROWTH_PER_PRODUCT := "empresa.crecimiento_por_producto"
const B_TREND_WEIGHT := "empresa.peso_tendencia_crecimiento"
const B_TREND_QUARTERS := "empresa.trimestres_tendencia"
const B_CONCESSION_PAYROLL := "empresa.aumento_nomina_por_concesion"
const B_FUSE_MIN := "mercado.mecha_auditoria_min_semanas"
const B_FUSE_CAP_BY_POST := "empresa.mecha_max_semanas_por_cargo.%s"
const B_FUSE_MAX := "mercado.mecha_auditoria_max_semanas"
const B_SCORE_MERIT := "npc.puntuacion_ascenso_merito"
const B_SCORE_AMBITION := "npc.puntuacion_ascenso_ambicion"
const B_START_OCCUPATION := "jugador.ocupacion_inicial"
const B_DISCONTENT_START := "descontento.inicial"
const B_STRIKE_THRESHOLD := "descontento.umbral_huelga"
const B_QUOTA_DAILY := "descontento.por_cuota_excesiva_diaria"
const B_FACTORY_DAILY := "descontento.por_condiciones_fabrica"
const B_MOOD_DAILY := "descontento.por_animo_diario"
const B_AFFECTED_TIER := "descontento.escalon_max_afectado"
const B_HISTORY_MAX := "descontento.historial_max"

var _active: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Sillas y promoción.
var _seats: Array[Dictionary] = []
var _hire_count: int = 0
## [{npc_id, occupation_id, day}]
var _hires: Array[Dictionary] = []
var _last_fill: Dictionary = {}
## [{source, amount, day}]
var _merits: Array[Dictionary] = []
var _last_offer: Array[String] = []
## occupation_id → jornada del rechazo.
var _declined: Dictionary = {}
## npc_id de los sucesores con jornada fija ya procesados.
var _successions_done: Array[String] = []
## npc_id → favour_type del último soborno ofrecido (hasta bribe_result).
var _pending_bribes: Dictionary = {}
var _game_over_sent: bool = false
var _last_closed_quarter: int = 0
var _board_quarter: int = 0
var _moving_player: bool = false

# Fundamentales: entradas.
var _brand_strength: float = NEUTRAL
var _product_quality: float = NEUTRAL
var _factory_efficiency: float = NEUTRAL
var _production_quota: float = NEUTRAL
var _cost_cutting: float = 0.0
var _payroll_factor: float = NEUTRAL
var _idea_modifier: float = NEUTRAL
## Registros con ventana: [{day, amount[, id]}].
var _theft_log: Array[Dictionary] = []
var _theft_total: float = 0.0
var _scandal_log: Array[Dictionary] = []
## headline_id → jornada de publicación (prensa negativa viva).
var _negative_press: Dictionary = {}
var _turnover_log: Array[Dictionary] = []
var _elimination_log: Array[Dictionary] = []
var _product_log: Array[Dictionary] = []
var _quarter_profits: Array[float] = []
var _fundamentals: Dictionary = {}
var _reported: Dictionary = {}
var _fuse: Dictionary = {}
## Última auditoría: {divergence, found, day} ({} si no hubo).
var _last_audit: Dictionary = {}

# Descontento.
var _discontent: int = 0
var _strike_active: bool = false
## [{day, delta, cause}] (últimas descontento.historial_max entradas).
var _discontent_history: Array[Dictionary] = []

# Caché de datos (se reconstruye en reset/load; no se guarda).
var _base: Dictionary = {}
var _risk_weights: Dictionary = {}
var _fuse_cfg: Dictionary = {}
var _auditor_occupation: String = ""


func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.week_closed.connect(_on_week_closed)
	EventBus.quarter_closed.connect(_on_quarter_closed)
	EventBus.quarter_reported.connect(_on_quarter_reported)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.news_published.connect(_on_news_published)
	EventBus.news_buried.connect(_on_news_buried)
	EventBus.idea_presented.connect(_on_idea_presented)
	EventBus.duty_completed.connect(_on_duty_completed)
	EventBus.bribe_offered.connect(_on_bribe_offered)
	EventBus.bribe_result.connect(_on_bribe_result)
	EventBus.strike_resolved.connect(_on_strike_resolved)


## Partida nueva (BUILD_NOTES §2): tras PlayerState y NPCDirector. No emite señales.
func reset_for_new_run() -> void:
	_load_config()
	_clear_state()
	_rng.seed = hash(RNG_SALT) ^ GameClock.get_run_seed()
	_build_seats()
	_discontent = clampi(Database.get_balance_int(B_DISCONTENT_START), DISCONTENT_MIN,
			DISCONTENT_MAX)
	_active = true
	_fundamentals = _compute_fundamentals()


func _load_config() -> void:
	var params: Dictionary = Database.get_market_params()
	var start: Dictionary = _as_dict(params.get(CFG_START, {}))
	var costs: Dictionary = _as_dict(start.get(CFG_COSTS, {}))
	_base = {
		K_UNITS: float(start.get("units_per_day", 0.0)),
		K_PRICE: float(start.get(K_PRICE, 0.0)),
		K_BRAND: float(start.get(K_BRAND, NEUTRAL)),
		K_QUALITY: float(start.get(K_QUALITY, NEUTRAL)),
		K_GROWTH: float(start.get(K_GROWTH, 0.0)),
		K_RISK: float(start.get(K_RISK, 0.0)),
	}
	for key: String in COST_KEYS:
		_base[key] = float(costs.get(key, 0.0))
	_risk_weights = _as_dict(params.get(CFG_RISK, {}))
	_fuse_cfg = _as_dict(params.get(CFG_FUSE, {}))
	_auditor_occupation = str(_as_dict(params.get(CFG_INSIDER, {})).get("auditor_occupation", ""))


func _clear_state() -> void:
	_seats.clear()
	_hires.clear()
	_merits.clear()
	_last_offer.clear()
	_declined.clear()
	_successions_done.clear()
	_pending_bribes.clear()
	_hire_count = 0
	_last_fill = {}
	_game_over_sent = false
	_last_closed_quarter = 0
	_board_quarter = 0
	_moving_player = false
	_clear_fundamentals_state()
	_discontent = DISCONTENT_MIN
	_strike_active = false
	_discontent_history.clear()


func _clear_fundamentals_state() -> void:
	_brand_strength = float(_base.get(K_BRAND, NEUTRAL))
	_product_quality = float(_base.get(K_QUALITY, NEUTRAL))
	_factory_efficiency = NEUTRAL
	_production_quota = NEUTRAL
	_cost_cutting = 0.0
	_payroll_factor = NEUTRAL
	_idea_modifier = NEUTRAL
	_theft_log.clear()
	_theft_total = 0.0
	_scandal_log.clear()
	_negative_press.clear()
	_turnover_log.clear()
	_elimination_log.clear()
	_product_log.clear()
	_quarter_profits.clear()
	_fundamentals = {}
	_reported = {}
	_fuse = {}
	_last_audit = {}


# ═══ Sillas (§19.8) ═══════════════════════════════════════════════════

## Titular de la primera silla de la ocupación; "" si alguna de sus sillas está vacante.
func get_seat_holder(occupation_id: String) -> String:
	var seats: Array[Dictionary] = _seats_of(occupation_id)
	if seats.is_empty() or is_seat_vacant(occupation_id):
		return ""
	return str(seats[0][S_HOLDER])


func is_seat_vacant(occupation_id: String) -> bool:
	return not _vacant_seat(occupation_id).is_empty()


## Ocupaciones con al menos una silla vacante (sin repetir, en orden de escalera).
func get_vacant_seats() -> Array[String]:
	var out: Array[String] = []
	for seat: Dictionary in _seats:
		var occupation_id: String = str(seat[S_OCC])
		if _is_vacant(seat) and not out.has(occupation_id):
			out.append(occupation_id)
	return out


## Libera la primera silla ocupada por un personaje (nunca la del jugador).
func vacate_seat(occupation_id: String, cause: String) -> void:
	for seat: Dictionary in _seats_of(occupation_id):
		var holder: String = str(seat[S_HOLDER])
		if not holder.is_empty() and holder != PLAYER_ID:
			_vacate(seat, cause)
			_refresh_promotion_offer()
			return


## Extra: libera la silla de ese personaje. false si no ocupa ninguna.
func vacate_npc_seat(npc_id: String, cause: String) -> bool:
	var seat: Dictionary = _seat_of_holder(npc_id)
	if seat.is_empty() or npc_id == PLAYER_ID:
		return false
	_vacate(seat, cause)
	_refresh_promotion_offer()
	return true


## Ocupa la primera silla vacante con ese personaje (su silla anterior queda vacante, causa
## "reassigned"). "player" mueve al jugador sin comprobar condiciones (motivo "assigned").
func fill_seat(occupation_id: String, npc_id: String) -> void:
	if npc_id.is_empty() or _occupation(occupation_id) == null:
		return
	if npc_id == PLAYER_ID:
		_move_player(occupation_id, REASON_ASSIGNED, CAUSE_REASSIGNED)
		return
	var target: Dictionary = _vacant_seat(occupation_id)
	var current: Dictionary = _seat_of_holder(npc_id)
	if target.is_empty():
		push_warning("Company.fill_seat: '%s' no tiene sillas vacantes" % occupation_id)
		return
	if str(current.get(S_OCC, "")) == occupation_id:
		return
	var cause: String = str(target[S_CAUSE])
	if not current.is_empty():
		_vacate(current, CAUSE_REASSIGNED)
	_occupy(target, npc_id, _fill_context(FILL_ASSIGNED, target, npc_id,
			str(current.get(S_OCC, "")), cause))
	_refresh_promotion_offer()


## §6.3: repone ahora todas las vacantes (cadena ascendente hasta contratar un Rookie).
func auto_fill_vacancies() -> void:
	for seat: Dictionary in _seats.duplicate():
		if _is_vacant(seat):
			_fill_chain(seat)
	_refresh_promotion_offer()


## Extra (BUILD_NOTES §13): [{occupation_id, seat_index, holder, temporary, vacated_day, cause}].
func get_all_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat: Dictionary in _seats:
		out.append(seat.duplicate())
	return out


## Extra (BUILD_NOTES §13): la silla del jugador ({} si no tiene).
func get_player_seat() -> Dictionary:
	return _seat_of_holder(PLAYER_ID).duplicate()


## Extra (BUILD_NOTES §13).
func get_seat_count(occupation_id: String) -> int:
	return _seats_of(occupation_id).size()


## Extra: titulares de cada silla de la ocupación por índice ("" = vacante).
func get_seat_holders(occupation_id: String) -> Array[String]:
	var out: Array[String] = []
	for seat: Dictionary in _seats_of(occupation_id):
		out.append(str(seat[S_HOLDER]))
	return out


## Extra: silla del personaje ({} si no ocupa ninguna).
func get_npc_seat(npc_id: String) -> Dictionary:
	return _seat_of_holder(npc_id).duplicate()


## Extra: Rookies contratados por RR. HH. [{npc_id, occupation_id, day}].
func get_hires() -> Array[Dictionary]:
	return _hires.duplicate(true)


## Extra: true si el id es de un Rookie contratado por Company (NPCDirector debe crearlo).
func is_hire(npc_id: String) -> bool:
	for hire: Dictionary in _hires:
		if str(hire["npc_id"]) == npc_id:
			return true
	return false


## Extra: detalle del último seat_filled (ver cabecera).
func get_last_fill_context() -> Dictionary:
	return _last_fill.duplicate()


# ═══ Promoción del jugador (§6.1, §6.2) ═══════════════════════════════

## { allowed: bool, missing: Array[String] } con missing ⊂ path, reputation, merit, vacancy.
func can_player_promote_to(occupation_id: String) -> Dictionary:
	var missing: Array[String] = []
	var target: OccupationData = _occupation(occupation_id)
	var kind: String = _move_kind(occupation_id)
	if kind == MOVE_NONE:
		missing.append(MISSING_PATH)
	if target != null:
		if PlayerState.get_reputation() < target.min_reputation:
			missing.append(MISSING_REPUTATION)
		if kind != MOVE_LATERAL and get_recent_merit() < get_merit_threshold(target.tier):
			missing.append(MISSING_MERIT)
		if not is_seat_vacant(occupation_id) and not can_create_post(occupation_id):
			missing.append(MISSING_VACANCY)
	return {"allowed": missing.is_empty(), "missing": missing}


## Destinos del puesto actual que cumplen hoy todas sus condiciones (ascensos, saltos y laterales).
func get_available_promotions() -> Array[String]:
	var out: Array[String] = []
	for occupation_id: String in get_promotion_targets():
		if bool(can_player_promote_to(occupation_id)["allowed"]):
			out.append(occupation_id)
	return out


## Extra: promotes_to + can_jump_to + lateral_to (rango ≤ actual) del puesto actual, sin filtrar.
func get_promotion_targets() -> Array[String]:
	var out: Array[String] = []
	var current: OccupationData = _player_occupation()
	if current == null:
		return out
	for id: String in current.promotes_to + current.can_jump_to + _laterals(current):
		if not out.has(id) and _occupation(id) != null:
			out.append(id)
	return out


func promote_player(occupation_id: String) -> bool:
	if not _active or not bool(can_player_promote_to(occupation_id)["allowed"]):
		return false
	var lateral: bool = _move_kind(occupation_id) == MOVE_LATERAL
	var reason: String = REASON_LATERAL if lateral else REASON_PROMOTION
	if not lateral and not is_seat_vacant(occupation_id):
		reason = REASON_CREATED_POST
	if not lateral:
		_merits.clear()
	_declined.erase(occupation_id)
	_move_player(occupation_id, reason, CAUSE_PLAYER_LATERAL if lateral else CAUSE_PLAYER_PROMOTED)
	return true


## Extra (PASO 21): el jugador rechaza el puesto; la vacante se repone en el acto.
func decline_promotion(occupation_id: String) -> void:
	var target: OccupationData = _occupation(occupation_id)
	if not _active or target == null:
		return
	_declined[occupation_id] = GameClock.get_day()
	EventBus.promotion_declined.emit(occupation_id)
	_note(NOTE_DECLINED, [tr(target.name_key)])
	for seat: Dictionary in _seats_of(occupation_id):
		if _is_vacant(seat):
			_fill_chain(seat)
	_refresh_promotion_offer()


## §6.1: descenso al primer demotes_to con vacante (si no, silla temporal). R0 → failed_at_r0.
func demote_player(reason: String) -> void:
	var current: OccupationData = _player_occupation()
	if not _active or current == null or _game_over_sent:
		return
	if current.rank == OccupationData.MAX_RANK and reason == DEMOTION_BOARD:
		_declare_game_over(CAUSE_BOARD_REMOVAL)
		return
	var target: String = _demotion_target(current)
	if target.is_empty() and current.rank == OccupationData.MIN_RANK:
		_declare_game_over(CAUSE_FAILED_AT_R0)
	elif target.is_empty():
		push_warning("Company.demote_player: '%s' no tiene demotes_to válido" % current.id)
	else:
		_move_player(target, REASON_DEMOTION, CAUSE_DEMOTED)


func register_merit(source: String, amount: int) -> void:
	if amount <= 0:
		return
	_merits.append({"source": source, L_AMOUNT: amount, L_DAY: GameClock.get_day()})
	EventBus.merit_gained.emit(source, amount)
	_refresh_promotion_offer()


## Mérito registrado en las últimas empresa.jornadas_caducidad_merito jornadas.
func get_recent_merit() -> int:
	var total: int = 0
	var today: int = GameClock.get_day()
	var expiry: int = Database.get_balance_int(B_MERIT_DAYS)
	for entry: Dictionary in _merits:
		if today - int(entry[L_DAY]) < expiry:
			total += int(entry[L_AMOUNT])
	return total


## Extra: mérito reciente mínimo para ascender a un puesto de ese escalón.
func get_merit_threshold(tier: int) -> int:
	var path: String = B_MERIT_BY_TIER % tier
	return Database.get_balance_int(path) if Database.has_balance(path) else 0


## Extra (§6.2): la dirección crearía el puesto (reputación excepcional).
func can_create_post(occupation_id: String) -> bool:
	var target: OccupationData = _occupation(occupation_id)
	if target == null or target.tier > Database.get_balance_int(B_CREATE_MAX_TIER):
		return false
	return PlayerState.get_reputation() \
			>= target.min_reputation + Database.get_balance_float(B_CREATE_MARGIN)


## Extra: clave de texto de una condición que falta (PROMO_MISSING_*).
static func get_missing_label_key(missing: String) -> String:
	return str(MISSING_LABEL_KEYS.get(missing, ""))


# ═══ Fundamentales (§9.2, §9.10) ══════════════════════════════════════

## { revenue, costs, profit, growth_expectation, risk_factor } (por jornada) + desglose:
## units, avg_price, brand_strength, product_quality, factory_efficiency, sales_force y costes.
func get_fundamentals() -> Dictionary:
	return _fundamentals.duplicate()


## Las cifras comunicadas al mercado (los fundamentales si no hay otras).
func get_reported_figures() -> Dictionary:
	return get_fundamentals() if _reported.is_empty() else _reported.duplicate()


## Solo cargos autorizados (empresa.cargos_cifras_reportadas). Toda divergencia enciende la mecha.
func set_reported_figures(figures: Dictionary) -> void:
	if not _active or not can_set_reported_figures():
		return
	var real: Dictionary = get_fundamentals()
	var reported: Dictionary = _merge_figures(real, figures)
	var divergence: float = compute_divergence(real, reported)
	if divergence <= EPSILON:
		_reported = {}
		return
	_reported = reported
	_light_fuse(divergence)


func recalculate_fundamentals() -> void:
	if not _active:
		return
	_fundamentals = _compute_fundamentals()
	EventBus.fundamentals_updated.emit(float(_fundamentals["revenue"]),
			float(_fundamentals["costs"]), float(_fundamentals[K_RISK]))


## §11.6 / §9.10: la pérdida entra en la ventana contable y se refleja al instante.
func add_theft_loss(amount: float) -> void:
	if not _active or amount <= 0.0:
		return
	_theft_log.append({L_DAY: GameClock.get_day(), L_AMOUNT: amount})
	_theft_total += amount
	recalculate_fundamentals()


func modify_product_quality(delta: float) -> void:
	_product_quality = clampf(_product_quality + delta, _bf(B_QUALITY_MIN), _bf(B_QUALITY_MAX))
	recalculate_fundamentals()


func modify_brand_strength(delta: float) -> void:
	_brand_strength = clampf(_brand_strength + delta, _bf(B_BRAND_MIN), _bf(B_BRAND_MAX))
	recalculate_fundamentals()


## Extra (§9.9 capataz): eficiencia de fábrica.
func modify_factory_efficiency(delta: float) -> void:
	_factory_efficiency = clampf(_factory_efficiency + delta, _bf(B_EFFICIENCY_MIN),
			_bf(B_EFFICIENCY_MAX))
	recalculate_fundamentals()


## Extra (§9.9 capataz / director de fábrica, §11.7): multiplicador de la cuota de producción.
func set_production_quota(factor: float) -> void:
	_production_quota = clampf(factor, _bf(B_QUOTA_MIN), _bf(B_QUOTA_MAX))
	recalculate_fundamentals()


## Extra (§9.9 director de fábrica, §11.7): recorte de costes de materiales (0 = ninguno).
func set_cost_cutting(fraction: float) -> void:
	_cost_cutting = clampf(fraction, 0.0, _bf(B_CUT_MAX))
	recalculate_fundamentals()


## Extra: modificador global de generación de ideas (IdeaPool lo lee; §9.10).
func get_idea_generation_modifier() -> float:
	return _idea_modifier


## Extra: suma de todas las pérdidas por robo de la partida (€).
func get_total_theft_losses() -> float:
	return _theft_total


## Extra: el jugador ocupa un cargo autorizado a fijar las cifras reportadas.
func can_set_reported_figures() -> bool:
	return _string_list(Database.get_balance(B_REPORT_POSTS)).has(_player_occupation_id())


## Extra: máx |reportado − real| ÷ |real| en revenue, costs y profit, acotada a [0, 1].
static func compute_divergence(real: Dictionary, reported: Dictionary) -> float:
	var worst: float = 0.0
	for key: String in FIGURE_KEYS:
		if not reported.has(key):
			continue
		var value: float = float(real.get(key, 0.0))
		var gap: float = absf(float(reported[key]) - value) / maxf(absf(value), NEUTRAL)
		worst = maxf(worst, gap)
	return clampf(worst, 0.0, NEUTRAL)


## Extra (§9.2): semanas = 8 − 6 × divergencia, redondeado y acotado a [2, 8].
func compute_fuse_weeks(divergence: float) -> int:
	var base: float = float(_fuse_cfg.get("weeks_base", 0.0))
	var per_unit: float = float(_fuse_cfg.get("weeks_per_divergence", 0.0))
	var weeks: int = roundi(base - per_unit * clampf(divergence, 0.0, NEUTRAL))
	return clampi(weeks, Database.get_balance_int(B_FUSE_MIN), Database.get_balance_int(B_FUSE_MAX))


## Extra: {} si no hay mecha; si no, {divergence, weeks_left, lit_day}.
func get_audit_fuse() -> Dictionary:
	return _fuse.duplicate()


## Extra: la última auditoría {divergence, found, day} (magnitud de la falsificación auditada,
## útil para Market aunque las cifras reportadas ya se hayan retirado). {} si no hubo.
func get_last_audit() -> Dictionary:
	return _last_audit.duplicate()


## Extra (§9.2): perspicacia del Auditor Jefe ÷ 100 × factor; 0 si es el jugador o está vacante.
func get_audit_detection_probability() -> float:
	if _auditor_occupation.is_empty() or _player_occupation_id() == _auditor_occupation:
		return 0.0
	var holder: String = get_seat_holder(_auditor_occupation)
	if holder.is_empty() or holder == PLAYER_ID or NPCDirector.get_npc(holder) == null:
		return 0.0
	var perception: float = float(NPCDirector.get_trait(holder, TRAIT_PERCEPTION))
	return clampf(perception / PERCENT * _bf(B_AUDIT_FACTOR), 0.0, NEUTRAL)


# ═══ Descontento (§11.7) ══════════════════════════════════════════════

func get_discontent() -> int:
	return _discontent


func modify_discontent(delta: int, cause: String) -> void:
	if not _active or delta == 0:
		return
	var old_value: int = _discontent
	_discontent = clampi(old_value + delta, DISCONTENT_MIN, DISCONTENT_MAX)
	if _discontent == old_value:
		return
	_discontent_history.append({L_DAY: GameClock.get_day(), "delta": _discontent - old_value,
			"cause": cause})
	while _discontent_history.size() > Database.get_balance_int(B_HISTORY_MAX):
		_discontent_history.pop_front()
	EventBus.strike_discontent_changed.emit(old_value, _discontent)
	_check_strike(old_value)


## Extra: aplica un factor puntual de la tabla §11.7 y devuelve el cambio pedido.
func apply_labour_event(event_id: String) -> int:
	if not LABOUR_EVENTS.has(event_id):
		push_warning("Company: factor de descontento desconocido '%s'" % event_id)
		return 0
	var delta: int = Database.get_balance_int(str(LABOUR_EVENTS[event_id]))
	if event_id == EVENT_WAGE_CONCESSION:
		_payroll_factor *= NEUTRAL + _bf(B_CONCESSION_PAYROLL)
		recalculate_fundamentals()
	modify_discontent(delta, event_id)
	return delta


func is_strike_active() -> bool:
	return _strike_active


## Extra: cuota por encima de lo razonable (+2 diario, §11.7).
func is_quota_excessive() -> bool:
	return _production_quota > _bf(B_QUOTA_REASONABLE) + EPSILON


## Extra: condiciones de fábrica degradadas por el recorte de costes (+3 diario, §11.7).
func is_factory_degraded() -> bool:
	return _cost_cutting > EPSILON


## Extra: término diario del ánimo medio de los escalones 1-3 (ánimo negativo → más descontento).
func get_mood_discontent_delta() -> int:
	if not NPCDirector.has_method("get_average_mood"):
		return 0
	var mood: float = float(NPCDirector.call("get_average_mood",
			Database.get_balance_int(B_AFFECTED_TIER)))
	return roundi(-mood * _bf(B_MOOD_DAILY))


## Extra: [{day, delta, cause}] de los últimos cambios de descontento.
func get_discontent_history() -> Array[Dictionary]:
	return _discontent_history.duplicate(true)


# ═══ Persistencia ═════════════════════════════════════════════════════

func save_state() -> Dictionary:
	return {
		"version": SAVE_VERSION, "rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
		"seats": _seats.duplicate(true), "hire_count": _hire_count, "hires": _hires.duplicate(true),
		"last_fill": _last_fill.duplicate(), "merits": _merits.duplicate(true),
		"declined": _declined.duplicate(), "successions_done": _successions_done.duplicate(),
		"pending_bribes": _pending_bribes.duplicate(), "game_over_sent": _game_over_sent,
		"last_closed_quarter": _last_closed_quarter, "board_quarter": _board_quarter,
		"inputs": _save_inputs(), "logs": _save_logs(),
		"fundamentals": _fundamentals.duplicate(), "reported": _reported.duplicate(),
		"fuse": _fuse.duplicate(), "last_audit": _last_audit.duplicate(),
		"discontent": _discontent, "strike_active": _strike_active,
		"discontent_history": _discontent_history.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_load_config()
	_clear_state()
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()
	_load_seats(data)
	_load_inputs(_as_dict(data.get("inputs", {})))
	_load_logs(_as_dict(data.get("logs", {})))
	_fundamentals = _float_dict(_as_dict(data.get("fundamentals", {})))
	_reported = _float_dict(_as_dict(data.get("reported", {})))
	_fuse = _load_fuse(_as_dict(data.get("fuse", {})))
	_last_audit = _as_dict(data.get("last_audit", {})).duplicate()
	if _last_audit.has(L_DAY):
		_last_audit[L_DAY] = int(_last_audit[L_DAY])
	_discontent = clampi(int(data.get("discontent", 0)), DISCONTENT_MIN, DISCONTENT_MAX)
	_strike_active = bool(data.get("strike_active", false))
	_discontent_history = _entries(data.get("discontent_history", []), ["delta"])
	_active = true
	if _fundamentals.is_empty():
		_fundamentals = _compute_fundamentals()


# ═══ Privado: construcción y consulta de sillas ═══════════════════════

func _build_seats() -> void:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if _occupation(npc.occupation_id) != null and _seat_of_holder(npc.id).is_empty():
			_seats.append(_new_seat(npc.occupation_id, _npc_seat_index(npc), npc.id, false))
	var occupation: OccupationData = PlayerState.get_occupation()
	var occupation_id: String = occupation.id if occupation != null \
			else str(Database.get_balance(B_START_OCCUPATION))
	if _occupation(occupation_id) != null:
		var temporary: bool = occupation_id != str(Database.get_balance(B_START_OCCUPATION))
		_seats.append(_new_seat(occupation_id, _next_index(occupation_id), PLAYER_ID, temporary))
	_sort_seats()


func _npc_seat_index(npc: NPCRuntime) -> int:
	var index: int = -1
	if NPCDirector.has_method("get_seat_index"):
		index = int(NPCDirector.call("get_seat_index", npc.id))
	if index < 0 or _has_index(npc.occupation_id, index):
		index = _next_index(npc.occupation_id)
	return index


func _new_seat(occupation_id: String, index: int, holder: String, temporary: bool) -> Dictionary:
	return {S_OCC: occupation_id, S_INDEX: index, S_HOLDER: holder, S_TEMP: temporary,
			S_DAY: NO_DAY if not holder.is_empty() else GameClock.get_day(), S_CAUSE: ""}


func _has_index(occupation_id: String, index: int) -> bool:
	for seat: Dictionary in _seats:
		if str(seat[S_OCC]) == occupation_id and int(seat[S_INDEX]) == index:
			return true
	return false


func _next_index(occupation_id: String) -> int:
	var next: int = 0
	for seat: Dictionary in _seats:
		if str(seat[S_OCC]) == occupation_id:
			next = maxi(next, int(seat[S_INDEX]) + 1)
	return next


func _sort_seats() -> void:
	_seats.sort_custom(_seat_before)


func _seat_before(a: Dictionary, b: Dictionary) -> bool:
	var ra: int = _rank_of(str(a[S_OCC]))
	var rb: int = _rank_of(str(b[S_OCC]))
	if ra != rb:
		return ra < rb
	if str(a[S_OCC]) != str(b[S_OCC]):
		return str(a[S_OCC]) < str(b[S_OCC])
	return int(a[S_INDEX]) < int(b[S_INDEX])


## Referencias (no copias) a las sillas de la ocupación, por índice.
func _seats_of(occupation_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat: Dictionary in _seats:
		if str(seat[S_OCC]) == occupation_id:
			out.append(seat)
	return out


func _vacant_seat(occupation_id: String) -> Dictionary:
	for seat: Dictionary in _seats_of(occupation_id):
		if _is_vacant(seat):
			return seat
	return {}


func _seat_of_holder(holder: String) -> Dictionary:
	if holder.is_empty():
		return {}
	for seat: Dictionary in _seats:
		if str(seat[S_HOLDER]) == holder:
			return seat
	return {}


## titular → silla (referencias), para búsquedas de candidatos.
func _holder_map() -> Dictionary:
	var out: Dictionary = {}
	for seat: Dictionary in _seats:
		if not _is_vacant(seat):
			out[str(seat[S_HOLDER])] = seat
	return out


static func _is_vacant(seat: Dictionary) -> bool:
	return str(seat[S_HOLDER]).is_empty()


func _vacate(seat: Dictionary, cause: String) -> void:
	var holder: String = str(seat[S_HOLDER])
	var occupation_id: String = str(seat[S_OCC])
	seat[S_HOLDER] = ""
	seat[S_DAY] = GameClock.get_day()
	seat[S_CAUSE] = cause
	_note_turnover(occupation_id, cause)
	EventBus.seat_vacated.emit(occupation_id, holder, cause)


func _occupy(seat: Dictionary, holder: String, context: Dictionary) -> void:
	seat[S_HOLDER] = holder
	seat[S_DAY] = NO_DAY
	seat[S_CAUSE] = ""
	_last_fill = context
	EventBus.seat_filled.emit(str(seat[S_OCC]), holder)


func _fill_context(kind: String, seat: Dictionary, holder: String, from_occupation: String,
		vacancy_cause: String, passed_over: String = "") -> Dictionary:
	var player_caused: bool = PLAYER_CAUSES.has(vacancy_cause)
	return {
		"occupation_id": str(seat[S_OCC]), "holder": holder, "kind": kind,
		"from_occupation": from_occupation, "vacancy_cause": vacancy_cause,
		"player_caused": player_caused,
		"favour_to": holder if player_caused and holder != PLAYER_ID else "",
		"grievance_to": passed_over, L_DAY: GameClock.get_day(),
	}


func _note_turnover(occupation_id: String, cause: String) -> void:
	var occupation: OccupationData = _occupation(occupation_id)
	if occupation != null and occupation.tier >= Database.get_balance_int(B_EXEC_TIER) \
			and cause != CAUSE_PROMOTED:
		_turnover_log.append({L_DAY: GameClock.get_day(), L_ID: occupation_id})


# ═══ Privado: reposición en cadena (§6.3) ═════════════════════════════

func _auto_fill_expired(day: int) -> void:
	var grace: int = Database.get_balance_int(B_VACANCY_DAYS)
	for seat: Dictionary in _seats.duplicate():
		if _is_vacant(seat) and day - int(seat[S_DAY]) >= grace:
			_fill_chain(seat)


## Rellena la silla; la que deja quien asciende se rellena a continuación (la cadena baja).
func _fill_chain(start: Dictionary) -> void:
	var queue: Array[Dictionary] = [start]
	var guard: int = _seats.size() + 1
	while not queue.is_empty() and guard > 0:
		guard -= 1
		var seat: Dictionary = queue.pop_front()
		if not _is_vacant(seat):
			continue
		var freed: Dictionary = _fill_one(seat)
		if not freed.is_empty():
			queue.append(freed)


## Devuelve la silla que ha quedado libre al ascender el elegido ({} si no hay cadena).
func _fill_one(seat: Dictionary) -> Dictionary:
	var occupation_id: String = str(seat[S_OCC])
	var cause: String = str(seat[S_CAUSE])
	var kind: String = FILL_SUCCESSOR
	var npc_id: String = _designated_successor(occupation_id)
	if npc_id.is_empty():
		kind = FILL_PROMOTION
		npc_id = _best_candidate(occupation_id, true)
	if npc_id.is_empty():
		_hire_rookie(seat, cause)
		return {}
	var old_seat: Dictionary = _seat_of_holder(npc_id)
	var from_occupation: String = str(old_seat.get(S_OCC, ""))
	if not old_seat.is_empty():
		_vacate(old_seat, CAUSE_PROMOTED)
	_occupy(seat, npc_id, _fill_context(kind, seat, npc_id, from_occupation, cause))
	return old_seat


func _hire_rookie(seat: Dictionary, cause: String) -> void:
	_hire_count += 1
	var npc_id: String = HIRE_ID_FORMAT % _hire_count
	_hires.append({"npc_id": npc_id, S_OCC: str(seat[S_OCC]), L_DAY: GameClock.get_day()})
	_occupy(seat, npc_id, _fill_context(FILL_HIRE, seat, npc_id, "", cause))


## Sucesor preferente (perfil future_occupation de NPCDirector), activo y aún sin ese puesto.
func _designated_successor(occupation_id: String) -> String:
	if not NPCDirector.has_method("get_profile"):
		return ""
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var profile: Dictionary = _as_dict(NPCDirector.call("get_profile", npc.id))
		var current: String = str(_seat_of_holder(npc.id).get(S_OCC, ""))
		if str(profile.get("future_occupation", "")) == occupation_id \
				and _rank_of_or_none(current) < _rank_of(occupation_id):
			return npc.id
	return ""


## Mejor candidato del rango inferior (promotes_to); con widen, de los rangos cercanos.
func _best_candidate(occupation_id: String, widen: bool) -> String:
	var target: OccupationData = _occupation(occupation_id)
	if target == null:
		return ""
	var best: String = _best_among(_candidates(target, false))
	if best.is_empty() and widen:
		best = _best_among(_candidates(target, true))
	return best


func _candidates(target: OccupationData, widen: bool) -> Array[String]:
	var out: Array[String] = []
	var min_rank: int = Database.get_balance_int(B_MIN_CANDIDATE_RANK)
	var low_rank: int = target.rank - Database.get_balance_int(B_WIDEN_RANKS)
	var by_holder: Dictionary = _holder_map()
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var seat: Dictionary = _as_dict(by_holder.get(npc.id, {}))
		var current: OccupationData = _occupation(str(seat.get(S_OCC, "")))
		if current == null or current.rank < min_rank or current.rank >= target.rank:
			continue
		if (widen and current.rank >= low_rank) or current.promotes_to.has(target.id):
			out.append(npc.id)
	return out


## Mayor mérito × peso + ambición × peso (§6.3); empate: el primero en orden de plantilla.
func _best_among(ids: Array[String]) -> String:
	var best: String = ""
	var best_score: float = -INF
	var w_merit: float = _bf(B_SCORE_MERIT)
	var w_ambition: float = _bf(B_SCORE_AMBITION)
	for id: String in ids:
		var score: float = NPCDirector.get_merit(id) * w_merit \
				+ NPCDirector.get_trait(id, TRAIT_AMBITION) * w_ambition
		if score > best_score:
			best_score = score
			best = id
	return best


## Rose Miller (§7.13): en su jornada, el titular generado se jubila y ella ocupa la silla.
func _process_dated_successions(day: int) -> void:
	if not NPCDirector.has_method("get_profile"):
		return
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var profile: Dictionary = _as_dict(NPCDirector.call("get_profile", npc.id))
		var occupation_id: String = str(profile.get("future_occupation", ""))
		var due: int = int(profile.get("future_occupation_day", 0))
		if occupation_id.is_empty() or due <= 0 or day < due or _successions_done.has(npc.id):
			continue
		_successions_done.append(npc.id)
		_retire_for_successor(occupation_id, npc.id)


func _retire_for_successor(occupation_id: String, heir: String) -> void:
	if str(_seat_of_holder(heir).get(S_OCC, "")) == occupation_id:
		return
	var seat: Dictionary = _vacant_seat(occupation_id)
	if seat.is_empty():
		for candidate: Dictionary in _seats_of(occupation_id):
			if str(candidate[S_HOLDER]) != PLAYER_ID:
				seat = candidate
				_vacate(seat, CAUSE_RETIRED)
				break
	if not seat.is_empty():
		_fill_chain(seat)


# ═══ Privado: movimientos del jugador ═════════════════════════════════

func _move_kind(occupation_id: String) -> String:
	var current: OccupationData = _player_occupation()
	var target: OccupationData = _occupation(occupation_id)
	if current == null or target == null or target.id == current.id:
		return MOVE_NONE
	if current.promotes_to.has(occupation_id) or current.can_jump_to.has(occupation_id):
		return MOVE_UP
	if _laterals(current).has(occupation_id):
		return MOVE_LATERAL
	return MOVE_NONE


## lateral_to (extra de occupations.json) filtrado a rango ≤ actual (§6.1).
func _laterals(current: OccupationData) -> Array[String]:
	var out: Array[String] = []
	for id: String in _string_list(current.extra.get(LATERAL_KEY, [])):
		var target: OccupationData = _occupation(id)
		if target != null and target.rank <= current.rank:
			out.append(id)
	return out


func _demotion_target(current: OccupationData) -> String:
	var fallback: String = ""
	for id: String in current.demotes_to:
		if _occupation(id) == null:
			continue
		if is_seat_vacant(id):
			return id
		if fallback.is_empty():
			fallback = id
	return fallback


## Mueve la silla del jugador y emite seat_vacated, seat_filled y occupation_changed.
func _move_player(occupation_id: String, reason: String, cause: String) -> void:
	var old_seat: Dictionary = _seat_of_holder(PLAYER_ID)
	var old_id: String = str(old_seat.get(S_OCC, _player_occupation_id()))
	if old_id == occupation_id:
		return
	var passed_over: String = _best_candidate(occupation_id, false)
	var target: Dictionary = _vacant_seat(occupation_id)
	if target.is_empty():
		target = _add_temporary_seat(occupation_id)
	var vacancy_cause: String = str(target[S_CAUSE])
	_moving_player = true
	_release_player_seat(old_seat, cause, true)
	_occupy(target, PLAYER_ID, _fill_context(FILL_PLAYER, target, PLAYER_ID, old_id,
			vacancy_cause, passed_over))
	EventBus.occupation_changed.emit(old_id, occupation_id, reason)
	_moving_player = false
	_note_career(reason, occupation_id)
	_refresh_promotion_offer()


## occupation_changed ajeno: la silla del jugador sigue a su ocupación sin emitir señales.
func _sync_player_seat(occupation_id: String) -> void:
	_release_player_seat(_seat_of_holder(PLAYER_ID), CAUSE_REASSIGNED, false)
	var target: Dictionary = _vacant_seat(occupation_id)
	if target.is_empty():
		target = _add_temporary_seat(occupation_id)
	target[S_HOLDER] = PLAYER_ID
	target[S_DAY] = NO_DAY
	target[S_CAUSE] = ""


## Una silla temporal (puesto creado, descenso sin vacante) desaparece al dejarla.
func _release_player_seat(seat: Dictionary, cause: String, announce: bool) -> void:
	if seat.is_empty():
		return
	if bool(seat[S_TEMP]):
		_seats.erase(seat)
	elif announce:
		_vacate(seat, cause)
	else:
		seat[S_HOLDER] = ""
		seat[S_DAY] = GameClock.get_day()
		seat[S_CAUSE] = cause


func _add_temporary_seat(occupation_id: String) -> Dictionary:
	var seat: Dictionary = _new_seat(occupation_id, _next_index(occupation_id), "", true)
	_seats.append(seat)
	_sort_seats()
	return seat


func _refresh_promotion_offer() -> void:
	if not _active:
		return
	var offer: Array[String] = []
	var today: int = GameClock.get_day()
	for occupation_id: String in get_available_promotions():
		if int(_declined.get(occupation_id, NO_DAY)) != today:
			offer.append(occupation_id)
	if offer == _last_offer:
		return
	_last_offer = offer
	if offer.is_empty():
		return
	EventBus.promotion_available.emit(offer.duplicate())
	_note(NOTE_PROMOTION_AVAILABLE, [offer.size()])


func _declare_game_over(cause: String) -> void:
	_game_over_sent = true
	EventBus.game_over.emit(cause, Bribery.ending_for_cause(cause), Tracking.get_snapshot())


func _note_career(reason: String, occupation_id: String) -> void:
	var occupation: OccupationData = _occupation(occupation_id)
	if NOTE_BY_REASON.has(reason) and occupation != null:
		_note(str(NOTE_BY_REASON[reason]), [tr(occupation.name_key)])


func _note(text_key: String, args: Array) -> void:
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, text_key, args)


# ═══ Privado: fundamentales ═══════════════════════════════════════════

func _compute_fundamentals() -> Dictionary:
	var day: int = GameClock.get_day()
	var efficiency: float = _factory_efficiency * _staffing(B_FACTORY_DEPTS, B_FACTORY_WEIGHT)
	var sales_force: float = _staffing(B_SALES_DEPTS, B_SALES_WEIGHT)
	var units: float = float(_base.get(K_UNITS, 0.0)) * efficiency * _product_quality \
			* sales_force * _production_quota
	if _strike_active:
		units *= _bf(B_STRIKE_UNITS)
	var price: float = float(_base.get(K_PRICE, 0.0))
	var revenue: float = units * price * _brand_strength
	var out: Dictionary = _compute_costs(units, day)
	var costs: float = 0.0
	for key: String in COST_KEYS:
		costs += float(out[key])
	out.merge({
		"revenue": revenue, "costs": costs, "profit": revenue - costs,
		K_GROWTH: _compute_growth(day), K_RISK: _compute_risk(day), K_UNITS: units,
		K_PRICE: price, K_BRAND: _brand_strength, K_QUALITY: _product_quality,
		"factory_efficiency": efficiency, "sales_force": sales_force,
	})
	return out


func _compute_costs(units: float, day: int) -> Dictionary:
	var base_units: float = float(_base.get(K_UNITS, 0.0))
	var ratio: float = units / base_units if base_units > 0.0 else NEUTRAL
	var window: float = float(maxi(_window(), 1))
	return {
		K_MATERIALS: float(_base[K_MATERIALS]) * ratio * (NEUTRAL - _cost_cutting),
		K_PAYROLL: float(_base[K_PAYROLL]) * _payroll_factor,
		K_OVERHEADS: float(_base[K_OVERHEADS]),
		K_LEGAL: float(_base[K_LEGAL]) + _bf(B_LEGAL_PER_CASE) * _open_investigations(),
		K_THEFT: _window_sum(_theft_log, day) / window,
		K_SCANDAL: _window_sum(_scandal_log, day) / window,
	}


## Tendencia media de los últimos trimestres + productos en desarrollo (§9.2).
func _compute_growth(day: int) -> float:
	var trend: float = 0.0
	var count: int = _quarter_profits.size()
	if count >= MIN_TREND_POINTS:
		var first: float = _quarter_profits[0]
		trend = (_quarter_profits[count - 1] - first) / maxf(absf(first), NEUTRAL) / (count - 1)
	var products: int = _window_count(_product_log, day)
	return float(_base.get(K_GROWTH, 0.0)) + trend * _bf(B_TREND_WEIGHT) \
			+ products * _bf(B_GROWTH_PER_PRODUCT)


## Suma ponderada (§9.2): investigaciones, prensa negativa, huelga, rotación y eliminaciones.
func _compute_risk(day: int) -> float:
	var press: int = 0
	for headline: Variant in _negative_press:
		if day - int(_negative_press[headline]) < _window():
			press += 1
	var risk: float = float(_base.get(K_RISK, 0.0))
	risk += _weight("per_open_investigation") * _open_investigations()
	risk += _weight("per_negative_news") * press
	risk += _weight("strike_active") if _strike_active else 0.0
	risk += _weight("per_executive_turnover") * _window_count(_turnover_log, day)
	risk += _bf(B_RISK_ELIMINATION) * _window_count(_elimination_log, day)
	return risk


## 1 − peso × fracción de sillas vacantes de esos departamentos (1 si no hay sillas).
func _staffing(departments_path: String, weight_path: String) -> float:
	var departments: Array[String] = _string_list(Database.get_balance(departments_path))
	var total: int = 0
	var vacant: int = 0
	for seat: Dictionary in _seats:
		var occupation: OccupationData = _occupation(str(seat[S_OCC]))
		if occupation == null or not departments.has(str(occupation.extra.get(DEPARTMENT_KEY, ""))):
			continue
		total += 1
		vacant += 1 if _is_vacant(seat) else 0
	if total == 0:
		return NEUTRAL
	return NEUTRAL - _bf(weight_path) * float(vacant) / float(total)


func _open_investigations() -> int:
	return Security.get_active_investigations().size()


func _merge_figures(real: Dictionary, figures: Dictionary) -> Dictionary:
	var out: Dictionary = real.duplicate()
	for key: Variant in figures:
		var value: Variant = figures[key]
		if value is float or value is int:
			out[str(key)] = float(value)
	if not figures.has("profit") and (figures.has("revenue") or figures.has("costs")):
		out["profit"] = float(out["revenue"]) - float(out["costs"])
	return out


func _light_fuse(divergence: float) -> void:
	var weeks: int = compute_fuse_weeks(divergence)
	var cap_path: String = B_FUSE_CAP_BY_POST % _player_occupation_id()
	if Database.has_balance(cap_path):
		weeks = mini(weeks, Database.get_balance_int(cap_path))
	var magnitude: float = divergence
	if not _fuse.is_empty():
		weeks = mini(weeks, int(_fuse[F_WEEKS]))
		magnitude = maxf(divergence, float(_fuse[F_DIVERGENCE]))
	_fuse = {F_DIVERGENCE: magnitude, F_WEEKS: weeks, F_DAY: GameClock.get_day()}
	EventBus.audit_fuse_lit.emit(magnitude, weeks)
	_note(NOTE_FUSE_LIT, [weeks])


## §9.2: al expirar la mecha, la auditoría interna detecta con la perspicacia del Auditor Jefe.
func _run_audit() -> void:
	var found: bool = _rng.randf() < get_audit_detection_probability()
	_last_audit = {F_DIVERGENCE: float(_fuse[F_DIVERGENCE]), "found": found,
			L_DAY: GameClock.get_day()}
	_fuse = {}
	EventBus.audit_triggered.emit(found)
	if not found:
		return
	_reported = {}
	if not _string_list(Database.get_balance(B_NO_DEMOTION_POSTS)).has(_player_occupation_id()):
		demote_player(DEMOTION_FIGURES)


func _apply_talent_loss(tier: int, cause: String) -> void:
	if tier < Database.get_balance_int(B_TALENT_TIER):
		return
	if not DISMISSAL_CAUSES.has(cause) and not ELIMINATION_CAUSES.has(cause):
		return
	_product_quality = clampf(_product_quality - _bf(B_QUALITY_LOSS), _bf(B_QUALITY_MIN),
			_bf(B_QUALITY_MAX))
	_idea_modifier = maxf(_idea_modifier - _bf(B_IDEAS_LOSS), _bf(B_IDEAS_MIN))


# ═══ Privado: descontento ═════════════════════════════════════════════

func _check_strike(old_value: int) -> void:
	var threshold: int = Database.get_balance_int(B_STRIKE_THRESHOLD)
	if _strike_active or old_value >= threshold or _discontent < threshold:
		return
	_strike_active = true
	EventBus.strike_started.emit()


func _apply_daily_discontent() -> void:
	if is_quota_excessive():
		modify_discontent(Database.get_balance_int(B_QUOTA_DAILY), CAUSE_EXCESSIVE_QUOTA)
	if is_factory_degraded():
		modify_discontent(Database.get_balance_int(B_FACTORY_DAILY), CAUSE_DEGRADED_FACTORY)
	modify_discontent(get_mood_discontent_delta(), CAUSE_MOOD)


# ═══ Oyentes ══════════════════════════════════════════════════════════

func _on_day_advanced(day_number: int) -> void:
	if not _active:
		return
	_purge_logs(day_number)
	_process_dated_successions(day_number)
	_auto_fill_expired(day_number)
	_apply_daily_discontent()
	recalculate_fundamentals()
	_last_offer.clear()
	_refresh_promotion_offer()


func _on_week_closed(_week_number: int) -> void:
	if not _active or _fuse.is_empty():
		return
	_fuse[F_WEEKS] = int(_fuse[F_WEEKS]) - 1
	if int(_fuse[F_WEEKS]) <= 0:
		_run_audit()


func _on_quarter_closed(quarter_number: int) -> void:
	if not _active:
		return
	_last_closed_quarter = quarter_number
	_quarter_profits.append(float(_fundamentals.get("profit", 0.0)))
	while _quarter_profits.size() > maxi(Database.get_balance_int(B_TREND_QUARTERS), 1):
		_quarter_profits.pop_front()


## El trimestre ya se comunicó: las cifras reportadas se retiran. Presión del consejo (§6.1).
func _on_quarter_reported(_real_figures: Dictionary, _reported_figures: Dictionary) -> void:
	if not _active:
		return
	_reported = {}
	if not Market.has_method(MARKET_BOARD_GETTER) or not bool(Market.call(MARKET_BOARD_GETTER)):
		return
	if _board_quarter == _last_closed_quarter:
		return
	_board_quarter = _last_closed_quarter
	demote_player(DEMOTION_BOARD)


func _on_npc_removed(npc_id: String, cause: String) -> void:
	if not _active:
		return
	var seat: Dictionary = _seat_of_holder(npc_id)
	var tier: int = _tier_of(npc_id, seat)
	if not seat.is_empty() and npc_id != PLAYER_ID:
		_vacate(seat, cause)
	_apply_talent_loss(tier, cause)
	if ELIMINATION_CAUSES.has(cause):
		_elimination_log.append({L_DAY: GameClock.get_day(), L_ID: npc_id})
	if DISMISSAL_CAUSES.has(cause) and tier > 0 \
			and tier <= Database.get_balance_int(B_AFFECTED_TIER):
		apply_labour_event(EVENT_UNJUST_DISMISSAL)
	_refresh_promotion_offer()


func _on_occupation_changed(_old_id: String, new_id: String, _reason: String) -> void:
	if not _active or _moving_player or _occupation(new_id) == null:
		return
	if str(_seat_of_holder(PLAYER_ID).get(S_OCC, "")) != new_id:
		_sync_player_seat(new_id)
		_refresh_promotion_offer()


func _on_reputation_changed(_old_value: float, _new_value: float) -> void:
	_refresh_promotion_offer()


func _on_news_published(headline_id: String, sentiment_delta: float, is_scandal: bool) -> void:
	if not _active or (not is_scandal and sentiment_delta >= 0.0):
		return
	var day: int = GameClock.get_day()
	_negative_press[headline_id] = day
	if is_scandal:
		_scandal_log.append({L_DAY: day, L_AMOUNT: _bf(B_SCANDAL_COST), L_ID: headline_id})


func _on_news_buried(headline_id: String, _by_whom: String) -> void:
	_negative_press.erase(headline_id)
	for entry: Dictionary in _scandal_log.duplicate():
		if str(entry.get(L_ID, "")) == headline_id:
			_scandal_log.erase(entry)


func _on_idea_presented(idea_id: String, _presenter: String, _merit_gained: int) -> void:
	if not _active:
		return
	for entry: Dictionary in _product_log:
		if str(entry[L_ID]) == idea_id:
			return
	_product_log.append({L_DAY: GameClock.get_day(), L_ID: idea_id})


## "Éxito visible" (§6.2): deber cumplido con calidad alta por un método que se ve.
func _on_duty_completed(_duty_id: String, quality: float, method: String) -> void:
	if not _active or quality < _bf(B_DUTY_QUALITY):
		return
	if _string_list(Database.get_balance(B_DUTY_METHODS)).has(method):
		register_merit(MERIT_DUTY, Database.get_balance_int(B_DUTY_MERIT))


func _on_bribe_offered(npc_id: String, _amount: int, favour_type: String) -> void:
	if _active:
		_pending_bribes[npc_id] = favour_type


## "Recomendación adquirida mediante soborno" (§6.2).
func _on_bribe_result(npc_id: String, accepted: bool, _outcome: String) -> void:
	var favour: String = str(_pending_bribes.get(npc_id, ""))
	_pending_bribes.erase(npc_id)
	if _active and accepted and favour == str(Database.get_balance(B_RECOMMEND_FAVOUR)):
		register_merit(MERIT_RECOMMENDATION, Database.get_balance_int(B_RECOMMEND_MERIT))


func _on_strike_resolved(_resolution: String) -> void:
	_strike_active = false


# ═══ Privado: utilidades ══════════════════════════════════════════════

func _purge_logs(day: int) -> void:
	var expiry: int = Database.get_balance_int(B_MERIT_DAYS)
	for entry: Dictionary in _merits.duplicate():
		if day - int(entry[L_DAY]) >= expiry:
			_merits.erase(entry)
	for records: Array[Dictionary] in [_theft_log, _scandal_log, _turnover_log,
			_elimination_log, _product_log]:
		for entry: Dictionary in records.duplicate():
			if day - int(entry[L_DAY]) >= _window():
				records.erase(entry)
	for headline: Variant in _negative_press.keys():
		if day - int(_negative_press[headline]) >= _window():
			_negative_press.erase(headline)


func _window() -> int:
	return Database.get_balance_int(B_WINDOW)


func _window_sum(records: Array[Dictionary], day: int) -> float:
	var total: float = 0.0
	for entry: Dictionary in records:
		if day - int(entry[L_DAY]) < _window():
			total += float(entry[L_AMOUNT])
	return total


func _window_count(records: Array[Dictionary], day: int) -> int:
	var count: int = 0
	for entry: Dictionary in records:
		if day - int(entry[L_DAY]) < _window():
			count += 1
	return count


func _weight(key: String) -> float:
	return float(_risk_weights.get(key, 0.0))


func _occupation(occupation_id: String) -> OccupationData:
	if occupation_id.is_empty():
		return null
	return Database.get_occupation(occupation_id)


## Rango del puesto; -1 si no ocupa silla jugable (puestos de npcs_generation.roles).
func _rank_of_or_none(occupation_id: String) -> int:
	return _rank_of(occupation_id) if _occupation(occupation_id) != null else NO_RANK


func _rank_of(occupation_id: String) -> int:
	var occupation: OccupationData = _occupation(occupation_id)
	return occupation.rank if occupation != null else OccupationData.MAX_RANK + 1


## Escalón del puesto que ocupa (o el del personaje si no tiene silla).
func _tier_of(npc_id: String, seat: Dictionary) -> int:
	var occupation: OccupationData = _occupation(str(seat.get(S_OCC, "")))
	if occupation != null:
		return occupation.tier
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.tier if npc != null else 0


func _player_occupation() -> OccupationData:
	var seat: Dictionary = _seat_of_holder(PLAYER_ID)
	if not seat.is_empty():
		return _occupation(str(seat[S_OCC]))
	return PlayerState.get_occupation()


func _player_occupation_id() -> String:
	var occupation: OccupationData = _player_occupation()
	return occupation.id if occupation != null else ""


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


static func _as_dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out


static func _float_dict(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in source:
		var value: Variant = source[key]
		out[str(key)] = float(value) if (value is float or value is int) else value
	return out


# ═══ Privado: guardado ════════════════════════════════════════════════

func _save_inputs() -> Dictionary:
	return {
		K_BRAND: _brand_strength, K_QUALITY: _product_quality,
		"factory_efficiency": _factory_efficiency, "production_quota": _production_quota,
		"cost_cutting": _cost_cutting, "payroll_factor": _payroll_factor,
		"idea_modifier": _idea_modifier, "theft_total": _theft_total,
		"quarter_profits": _quarter_profits.duplicate(),
	}


func _save_logs() -> Dictionary:
	return {
		"theft": _theft_log.duplicate(true), "scandal": _scandal_log.duplicate(true),
		"negative_press": _negative_press.duplicate(), "turnover": _turnover_log.duplicate(true),
		"elimination": _elimination_log.duplicate(true), "product": _product_log.duplicate(true),
	}


func _load_seats(data: Dictionary) -> void:
	for raw: Variant in data.get("seats", []):
		var d: Dictionary = _as_dict(raw)
		if _occupation(str(d.get(S_OCC, ""))) == null:
			continue
		var seat: Dictionary = _new_seat(str(d[S_OCC]), int(d.get(S_INDEX, 0)),
				str(d.get(S_HOLDER, "")), bool(d.get(S_TEMP, false)))
		seat[S_DAY] = int(d.get(S_DAY, NO_DAY))
		seat[S_CAUSE] = str(d.get(S_CAUSE, ""))
		_seats.append(seat)
	_sort_seats()
	_hire_count = int(data.get("hire_count", 0))
	_hires = _entries(data.get("hires", []), [])
	_last_fill = _as_dict(data.get("last_fill", {})).duplicate()
	_merits = _entries(data.get("merits", []), [L_AMOUNT])
	_declined = _int_values(_as_dict(data.get("declined", {})))
	_successions_done = _string_list(data.get("successions_done", []))
	_pending_bribes = _as_dict(data.get("pending_bribes", {})).duplicate()
	_game_over_sent = bool(data.get("game_over_sent", false))
	_last_closed_quarter = int(data.get("last_closed_quarter", 0))
	_board_quarter = int(data.get("board_quarter", 0))


func _load_inputs(d: Dictionary) -> void:
	_brand_strength = float(d.get(K_BRAND, _brand_strength))
	_product_quality = float(d.get(K_QUALITY, _product_quality))
	_factory_efficiency = float(d.get("factory_efficiency", NEUTRAL))
	_production_quota = float(d.get("production_quota", NEUTRAL))
	_cost_cutting = float(d.get("cost_cutting", 0.0))
	_payroll_factor = float(d.get("payroll_factor", NEUTRAL))
	_idea_modifier = float(d.get("idea_modifier", NEUTRAL))
	_theft_total = float(d.get("theft_total", 0.0))
	_quarter_profits.clear()
	for value: Variant in d.get("quarter_profits", []):
		_quarter_profits.append(float(value))


func _load_logs(d: Dictionary) -> void:
	_theft_log = _entries(d.get("theft", []), [])
	_scandal_log = _entries(d.get("scandal", []), [])
	_turnover_log = _entries(d.get("turnover", []), [])
	_elimination_log = _entries(d.get("elimination", []), [])
	_product_log = _entries(d.get("product", []), [])
	_negative_press = _int_values(_as_dict(d.get("negative_press", {})))


func _load_fuse(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	return {F_DIVERGENCE: float(d.get(F_DIVERGENCE, 0.0)), F_WEEKS: int(d.get(F_WEEKS, 0)),
			F_DAY: int(d.get(F_DAY, 0))}


## Copia entradas {day, ...}: "day" y las claves int_keys vuelven a int (JSON las da en float).
static func _entries(raw: Variant, int_keys: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for item: Variant in raw:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = (item as Dictionary).duplicate()
		for key: Variant in [L_DAY] + int_keys:
			if entry.has(key):
				entry[key] = int(entry[key])
		out.append(entry)
	return out


static func _int_values(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in source:
		out[str(key)] = int(source[key])
	return out
