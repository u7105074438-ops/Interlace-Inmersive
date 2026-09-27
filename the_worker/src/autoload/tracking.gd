# tracking.gd — Los cinco ejes del seguimiento invisible (§12.8), la evaluación de los nueve finales (§12.9) y el texto del epílogo.
# PROPIETARIO DE: los cinco ejes y su desglose por fuente, los acumulados que los alimentan (sobornos pagados, valor robado), los escándalos y puntos de pérdidas ya convertidos en RUINA, sobornos pendientes, cuerpos ocultados, víctimas, incriminados y cabezas de turco, marca de notaría, causa terminal y caso concluyente (§19.12).
# ESCUCHA: npc_removed, body_hidden, crime_committed, bribe_offered, bribe_result, idea_acquired, idea_presented, investigation_resolved, duty_completed, seat_vacated, day_advanced, tracking_event_recorded, ownership_notarised, game_over.
class_name TrackingSystem
extends Node

## Manual §12.7-§12.9, §19.12, §32.8, PASO 31; BUILD_NOTES §2, §11, §13. Emite: nada.
## Incrementos exactos de §12.8 (balance.seguimiento), derivados de señales de dominio:
##  SANGRE +10 npc_removed(causa "eliminated"|"elimination") · +5 body_hidden (una vez por cuerpo)
##         · +3 violencia sin muerte: crime_committed con details.violent = true (no "elimination").
##  ORO    +1 por cada 1.000 € de sobornos ACEPTADOS: bribe_offered(npc, importe) deja la oferta
##         pendiente; crime_committed("bribe", {npc_id, paid}) la corrige con lo pagado de verdad;
##         bribe_result(npc, true) la suma al acumulado de la partida (los tramos se cuentan sobre
##         el acumulado: 600 € + 400 € = +1) · +1 por cada 2.000 € robados: crime_committed
##         theft_small | theft_product | burglary (details.value, acumulado) · +5 crime_committed
##         "fraud".
##  SEDA   +8 idea_acquired con método overhear | steal_file | inherit (robada, no regalada ni
##         comprada) · +5 incriminación exitosa: cae (investigation_resolved "other_guilty" o
##         seat_vacated por expulsión) un personaje incriminado por el jugador (crime_committed
##         "framing" {target} o cabeza de turco del expediente de Security); una vez por personaje
##         · +3 crime_committed "rumour_planted" · +5 crime_committed "forgery".
##  SUDOR  +2 duty_completed con método "honest" · +10 si ese deber es de tipo "delivery" (informe
##         real) · +5 si es de tipo "presentation" (presentación preparada); ambos sustituyen a los
##         +2 · +5 presentación preparada: idea_presented del jugador con preparación "real"
##         (IdeaPool.get_preparation) o tracking_event_recorded de ResultsPresentation.
##  RUINA  +1 por punto de pérdidas: 1 punto = seguimiento.euros_por_punto_perdidas € de
##         Company.get_total_theft_losses() (la única cifra de pérdidas por robo: Company la apunta
##         al oír crime_committed theft_product / details.company_loss y con add_theft_loss; Tracking
##         no la reconstruye) · +5 seat_vacated por expulsión (expelled |
##         expulsion | fired | framed) de un puesto de escalón ≥ empresa.escalon_talento_cualificado
##         (talento cualificado, como Company §9.10) · +10 por escándalo no enterrado: cada escándalo
##         que NewsFeed consolida (get_settled_scandal_count).
##         Pérdidas y escándalos son cifras de Company y NewsFeed: los getters las incluyen al leer
##         (puros, sin efectos) y los puntos se anotan en el desglose al oír day_advanced y game_over.
##  tracking_event_recorded(eje, cantidad, fuente): hechos sin señal de dominio propia
##  (PlayerState.add_tracking, ResultsPresentation). add() suma y no emite (sin eco).
## DECISIONES:
##  · Estilo dominante = mayor de los cuatro primeros ejes; empate → endings.json
##    dominant_tie_break (sudor, seda, oro, sangre): con todo a 0 domina el sudor.
##  · Híbrido (endings.json hybrid_rule): suma > 0 y ningún eje supera max_axis_share de la suma.
##  · Variante de ruina: "husk" si RUINA ≥ seguimiento.umbral_ruina_cascaron (150); si no "empire".
##  · Finales: endings.json evaluation_order; gana el primero cuyas condiciones se cumplen (rank
##    exacto, rank_max, has_ownership_documents, notarised, hybrid, dominant_axis, cause). Ninguno →
##    fallback_ending. Documentos = el jugador lleva o tiene escondido "ownership_documents"
##    (PlayerState) o ya los ha notariado. `cause: ["any"]` = cualquier causa terminal (no vale
##    "sin causa": mientras la partida sigue no hay final parcial). `has_ownership_documents: false`
##    (THE FIGUREHEAD) se lee como "sin documentos NOTARIADOS" (endings.json _nota_figurehead): un
##    R33 con papeles sin notariar cesado por el consejo o al agotar su mandato es THE FIGUREHEAD.
##  · Causa: evaluate_ending() usa la causa terminal ya registrada (game_over), si no
##    "ownership_notarised" tras ownership_notarised, si no ninguna. Quien declare el fin de partida
##    debe pedir evaluate_ending_for_cause(causa) y get_snapshot_for_cause(causa) ANTES de emitir
##    game_over (get_snapshot() lleva la causa ya registrada, "" antes del game_over).
##  · get_epilogue(final, contexto): tr(epilogue_key) + párrafo + tr(variante de ruina), rellenados
##    con String.format: contexto > datos de la partida > UI_EPILOGUE_REDACTED. Capitalización =
##    Market.get_price() × market.json shares.share_count.

const AXIS_BLOOD := "blood"
const AXIS_GOLD := "gold"
const AXIS_SILK := "silk"
const AXIS_SWEAT := "sweat"
const AXIS_RUIN := "ruin"
const STYLE_AXES: Array[String] = [AXIS_BLOOD, AXIS_GOLD, AXIS_SILK, AXIS_SWEAT]
const ALL_AXES: Array[String] = [AXIS_BLOOD, AXIS_GOLD, AXIS_SILK, AXIS_SWEAT, AXIS_RUIN]
const TIER_EMPIRE := "empire"
const TIER_HUSK := "husk"
const RUIN_TIERS: Array[String] = [TIER_EMPIRE, TIER_HUSK]
const PLAYER_ID := "player"
const OWNERSHIP_ITEM := "ownership_documents"
const CAUSE_NOTARISED := "ownership_notarised"
const CAUSE_ANY := "any"
const VERDICT_OTHER := "other_guilty"
const VERDICT_PLAYER_MAJOR := "player_major"
const METHOD_HONEST := "honest"
const DUTY_DELIVERY := "delivery"
const DUTY_PRESENTATION := "presentation"
const PREPARATION_REAL := "real"
const ELIMINATION_CAUSES: Array[String] = ["eliminated", "elimination"]
const EXPULSION_CAUSES: Array[String] = ["expelled", "expulsion", "fired", "framed"]
const STOLEN_IDEA_METHODS: Array[String] = ["overhear", "steal_file", "inherit"]
const THEFT_CRIMES: Array[String] = ["theft_small", "theft_product", "burglary"]
const CRIME_ELIMINATION := "elimination"
const CRIME_BRIBE := "bribe"
const CRIME_FRAMING := "framing"
const D_VALUE := "value"
const D_PAID := "paid"
const D_NPC := "npc_id"
const D_TARGET := "target"
const D_VIOLENT := "violent"
const D_CASE := "case_id"
const STASH_ITEMS := "items"
const ITEM_ID := "id"
const DUTY_TYPE := "type"
const DUTY_ID := "id"
const REPORT_INNOCENT := "culprit_innocent"
const NEWS_SETTLED_GETTER := "get_settled_scandal_count"
const COMPANY_LOSSES_GETTER := "get_total_theft_losses"

# Fuentes (desglose) de los incrementos derivados de señales de dominio.
const SRC_ELIMINATION := "elimination"
const SRC_BODY_HIDDEN := "body_hidden"
const SRC_VIOLENCE := "violence"
const SRC_BRIBES := "bribes"
const SRC_THEFT := "theft"
const SRC_FRAUD := "fraud"
const SRC_IDEA := "idea_stolen"
const SRC_FRAMING := "framing"
const SRC_RUMOUR := "rumour_planted"
const SRC_FORGERY := "forgery"
const SRC_HONEST_DUTY := "honest_duty"
const SRC_REAL_REPORT := "real_report"
const SRC_PRESENTATION := "presentation_prepared"
const SRC_LOSSES := "company_losses"
const SRC_TALENT := "talent_expelled"
const SRC_SCANDAL := "scandal_not_buried"
## Incrementos fijos: fuente → [eje, ruta de balance].
const FIXED_INCREMENTS: Dictionary = {
	SRC_ELIMINATION: [AXIS_BLOOD, "seguimiento.sangre_por_eliminacion"],
	SRC_BODY_HIDDEN: [AXIS_BLOOD, "seguimiento.sangre_por_cuerpo_ocultado"],
	SRC_VIOLENCE: [AXIS_BLOOD, "seguimiento.sangre_por_violencia"],
	SRC_FRAUD: [AXIS_GOLD, "seguimiento.oro_por_fraude"],
	SRC_IDEA: [AXIS_SILK, "seguimiento.seda_por_idea_robada"],
	SRC_FRAMING: [AXIS_SILK, "seguimiento.seda_por_incriminacion"],
	SRC_RUMOUR: [AXIS_SILK, "seguimiento.seda_por_rumor_plantado"],
	SRC_FORGERY: [AXIS_SILK, "seguimiento.seda_por_falsificacion"],
	SRC_HONEST_DUTY: [AXIS_SWEAT, "seguimiento.sudor_por_deber_honesto"],
	SRC_REAL_REPORT: [AXIS_SWEAT, "seguimiento.sudor_por_informe_real"],
	SRC_PRESENTATION: [AXIS_SWEAT, "seguimiento.sudor_por_presentacion_preparada"],
	SRC_TALENT: [AXIS_RUIN, "seguimiento.ruina_por_talento_expulsado"],
	SRC_SCANDAL: [AXIS_RUIN, "seguimiento.ruina_por_escandalo"],
	SRC_LOSSES: [AXIS_RUIN, "seguimiento.ruina_por_punto_perdidas"],
}
## Incrementos por tramos de un acumulado en €: fuente → [eje, ruta del incremento, ruta del tramo].
const STEP_INCREMENTS: Dictionary = {
	SRC_BRIBES: [AXIS_GOLD, "seguimiento.oro_por_mil_en_sobornos", "seguimiento.euros_tramo_sobornos"],
	SRC_THEFT: [AXIS_GOLD, "seguimiento.oro_por_dos_mil_robados", "seguimiento.euros_tramo_robo"],
}
## Deber honesto por tipo (occupations.json) → fuente; el resto, SRC_HONEST_DUTY.
const DUTY_SOURCES: Dictionary = {DUTY_DELIVERY: SRC_REAL_REPORT, DUTY_PRESENTATION: SRC_PRESENTATION}
## Delitos con incremento fijo propio: crime_type → fuente.
const CRIME_SOURCES: Dictionary = {
	"fraud": SRC_FRAUD, "rumour_planted": SRC_RUMOUR, "forgery": SRC_FORGERY,
}
const B_HUSK_THRESHOLD := "seguimiento.umbral_ruina_cascaron"
const B_LOSS_STEP := "seguimiento.euros_por_punto_perdidas"
const B_TALENT_TIER := "empresa.escalon_talento_cualificado"
const MARKET_SHARES := "shares"
const MARKET_SHARE_COUNT := "share_count"

# endings.json (§32.8).
const ENDINGS_FILE := "endings"
const E_ORDER := "evaluation_order"
const E_FALLBACK := "fallback_ending"
const E_HYBRID_RULE := "hybrid_rule"
const E_MAX_SHARE := "max_axis_share"
const E_TIE_BREAK := "dominant_tie_break"
const E_CONDITIONS := "conditions"
const E_EPILOGUE := "epilogue_key"
const E_HAS_VARIANTS := "has_ruin_variants"
const E_VARIANTS := "epilogue_variants"
const E_PLACEHOLDERS := "placeholders"
const C_RANK := "rank"
const C_RANK_MAX := "rank_max"
const C_DOCS := "has_ownership_documents"
const C_NOTARISED := "notarised"
const C_HYBRID := "hybrid"
const C_DOMINANT := "dominant_axis"
const C_CAUSE := "cause"
const BOOL_CONDITIONS: Array[String] = [C_NOTARISED, C_HYBRID]
const COMMENT_PREFIX := "_"
const HYBRID_EPSILON := 0.000001

# Epílogo.
const P_NAME := "name"
const P_DAYS := "days"
const P_VICTIMS := "victims"
const P_SCAPEGOATS := "scapegoats"
const P_BRIBES := "bribes_total"
const P_COMPANY_VALUE := "company_value"
const P_SHARE_PRICE := "share_price"
const P_INVESTIGATOR := "investigator"
const P_CASE := "case_id"
const P_EVIDENCE := "evidence_count"
const P_SUCCESSOR := "successor"
const CTX_RUIN_TIER := "ruin_tier"
const REDACTED_KEY := "UI_EPILOGUE_REDACTED"
const MONEY_FMT_KEY := "UI_MONEY_FMT"
const THOUSANDS_SEP_KEY := "UI_THOUSANDS_SEP"
const DECIMAL_SEP_KEY := "UI_DECIMAL_SEP"
const LIST_SEP_KEY := "UI_LIST_SEPARATOR"
const PARAGRAPH := "\n\n"
const PRICE_FORMAT := "%.2f"
const DECIMAL_POINT := "."
const FULL_NAME_FORMAT := "%s %s"
const DIGIT_GROUP := 3
const NAMES_FILE := "npcs_generation"
const NAME_BANK := "name_bank"
const FIRST_NAMES := "first_names"
const LAST_NAMES := "last_names"
const RNG_SALT := "tracking"
const WARN_AXIS := "Tracking: eje desconocido '%s' (fuente '%s')"
const WARN_CONDITION := "Tracking: condición de final desconocida '%s'"

# Claves de save_state().
const S_AXES := "axes"
const S_BREAKDOWN := "breakdown"
const S_TOTALS := "totals"
const S_PENDING := "pending_bribes"
const S_BODIES := "hidden_bodies"
const S_VICTIMS := "victims"
const S_FRAMED := "framed"
const S_CREDITED := "framing_credited"
const S_SCAPEGOATS := "scapegoats"
const S_NOTARISED := "notarised"
const S_CAUSE := "cause"
const S_CASE := "final_case_id"
const S_SETTLED := "settled_seen"
const S_LOSS_POINTS := "loss_points_seen"

## eje → puntos anotados (sin lo pendiente de NewsFeed y Company, que se suma al leer).
var _axes: Dictionary = {}
## fuente → {eje → puntos} (depuración y pruebas).
var _breakdown: Dictionary = {}
## SRC_BRIBES / SRC_THEFT → € acumulados en la partida.
var _totals: Dictionary = {}
## npc_id → € ofrecidos (o pagados) a la espera de bribe_result.
var _pending_bribes: Dictionary = {}
var _hidden_bodies: Array[String] = []
var _victims: Array[String] = []
var _framed: Array[String] = []
var _framing_credited: Array[String] = []
var _scapegoats: Array[String] = []
var _notarised: bool = false
var _cause: String = ""
var _final_case_id: String = ""
## Escándalos consolidados de NewsFeed ya anotados como RUINA.
var _settled_seen: int = 0
## Puntos de pérdidas (Company) ya anotados como RUINA.
var _loss_points_seen: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Caché de endings.json (datos estáticos, no estado de partida).
var _rules: Dictionary = {}


func _ready() -> void:
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.body_hidden.connect(_on_body_hidden)
	EventBus.crime_committed.connect(_on_crime_committed)
	EventBus.bribe_offered.connect(_on_bribe_offered)
	EventBus.bribe_result.connect(_on_bribe_result)
	EventBus.idea_acquired.connect(_on_idea_acquired)
	EventBus.idea_presented.connect(_on_idea_presented)
	EventBus.investigation_resolved.connect(_on_investigation_resolved)
	EventBus.duty_completed.connect(_on_duty_completed)
	EventBus.seat_vacated.connect(_on_seat_vacated)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.tracking_event_recorded.connect(_on_tracking_event_recorded)
	EventBus.ownership_notarised.connect(_on_ownership_notarised)
	EventBus.game_over.connect(_on_game_over)


## Tras Company y NewsFeed (BUILD_NOTES §2): lo que ya tengan no es de esta partida.
func reset_for_new_run() -> void:
	_clear()
	_settled_seen = _settled_count()
	_loss_points_seen = _loss_points_now()
	_rng.seed = _run_rng_seed()


# ═══ Interfaz §19.12 ══════════════════════════════════════════════════

## Suma `amount` (> 0) al eje. No emite señales: tracking_event_recorded es la entrada, no la salida.
func add(axis: String, amount: int, source: String) -> void:
	if not ALL_AXES.has(axis):
		push_warning(WARN_AXIS % [axis, source])
		return
	if amount <= 0:
		return
	_axes[axis] = int(_axes.get(axis, 0)) + amount
	_add_points(_breakdown, source, axis, amount)


## Puro: incluye la RUINA pendiente de NewsFeed y Company.
func get_axis(axis: String) -> int:
	var pending: int = _pending_ruin() if axis == AXIS_RUIN else 0
	return int(_axes.get(axis, 0)) + pending


## {blood, gold, silk, sweat, ruin} (copia).
func get_all_axes() -> Dictionary:
	var out: Dictionary = {}
	for axis: String in ALL_AXES:
		out[axis] = get_axis(axis)
	return out


## Mayor de los cuatro ejes de estilo; empates por endings.json dominant_tie_break.
func get_dominant_axis() -> String:
	var best: String = ""
	for axis: String in _tie_break_order():
		if best.is_empty() or int(_axes.get(axis, 0)) > int(_axes.get(best, 0)):
			best = axis
	return best


## Ningún eje de estilo supera hybrid_rule.max_axis_share de la suma de los cuatro (suma > 0).
func is_hybrid() -> bool:
	var total: int = 0
	var top: int = 0
	for axis: String in STYLE_AXES:
		var value: int = int(_axes.get(axis, 0))
		total += value
		top = maxi(top, value)
	if total <= 0:
		return false
	return float(top) <= _max_axis_share() * float(total) + HYBRID_EPSILON


## "empire" | "husk"
func get_ruin_tier() -> String:
	if get_axis(AXIS_RUIN) >= Database.get_balance_int(B_HUSK_THRESHOLD):
		return TIER_HUSK
	return TIER_EMPIRE


## Devuelve ending_id (causa terminal registrada; ver get_terminal_cause()).
func evaluate_ending() -> String:
	return evaluate_ending_for_cause(get_terminal_cause())


## Con la causa terminal registrada ("" mientras la partida sigue).
func get_snapshot() -> Dictionary:
	return get_snapshot_for_cause(get_terminal_cause())


func save_state() -> Dictionary:
	return {
		S_AXES: _axes.duplicate(), S_BREAKDOWN: _breakdown.duplicate(true),
		S_TOTALS: _totals.duplicate(), S_PENDING: _pending_bribes.duplicate(),
		S_BODIES: _hidden_bodies.duplicate(), S_VICTIMS: _victims.duplicate(),
		S_FRAMED: _framed.duplicate(), S_CREDITED: _framing_credited.duplicate(),
		S_SCAPEGOATS: _scapegoats.duplicate(), S_NOTARISED: _notarised, S_CAUSE: _cause,
		S_CASE: _final_case_id, S_SETTLED: _settled_seen, S_LOSS_POINTS: _loss_points_seen,
	}


## Tolera el JSON (números como float, claves como texto): todo se normaliza a su tipo.
func load_state(data: Dictionary) -> void:
	_clear()
	var axes: Dictionary = _int_dict(data.get(S_AXES, {}))
	for axis: String in ALL_AXES:
		_axes[axis] = int(axes.get(axis, 0))
	for source: Variant in _dict(data.get(S_BREAKDOWN, {})):
		_breakdown[str(source)] = _int_dict(data[S_BREAKDOWN][source])
	_totals = _int_dict(data.get(S_TOTALS, {}))
	_pending_bribes = _int_dict(data.get(S_PENDING, {}))
	_hidden_bodies = _strings(data.get(S_BODIES, []))
	_victims = _strings(data.get(S_VICTIMS, []))
	_framed = _strings(data.get(S_FRAMED, []))
	_framing_credited = _strings(data.get(S_CREDITED, []))
	_scapegoats = _strings(data.get(S_SCAPEGOATS, []))
	_notarised = bool(data.get(S_NOTARISED, false))
	_cause = str(data.get(S_CAUSE, ""))
	_final_case_id = str(data.get(S_CASE, ""))
	_settled_seen = int(data.get(S_SETTLED, 0))
	_loss_points_seen = int(data.get(S_LOSS_POINTS, 0))
	_rng.seed = _run_rng_seed()


# ═══ Extensiones públicas ═════════════════════════════════════════════

## Final para una causa terminal concreta (Bribery, DutySystem, Security... antes de game_over).
func evaluate_ending_for_cause(cause: String) -> String:
	var facts: Dictionary = _facts(cause)
	var rules: Dictionary = _endings_rules()
	for ending_id: Variant in rules.get(E_ORDER, []):
		var ending: Dictionary = Database.get_ending(str(ending_id))
		if not ending.is_empty() and _conditions_met(ending.get(E_CONDITIONS, {}), facts):
			return str(ending_id)
	return str(rules.get(E_FALLBACK, ""))


## Instantánea para el payload de game_over: la emite quien declara el fin, con SU causa (la
## registrada solo llega al oír game_over). "ending_id" = evaluate_ending_for_cause(cause).
func get_snapshot_for_cause(cause: String) -> Dictionary:
	return {
		"axes": get_all_axes(), "dominant_axis": get_dominant_axis(), "hybrid": is_hybrid(),
		"ruin_tier": get_ruin_tier(), "rank": PlayerState.get_rank(), "day": GameClock.get_day(),
		"has_ownership_documents": has_ownership_documents(), "notarised": _notarised,
		"cause": cause, "ending_id": evaluate_ending_for_cause(cause), "case_id": _final_case_id,
		"victims": _victims.duplicate(), "scapegoats": _scapegoats.duplicate(),
		"bribes_total": get_total(SRC_BRIBES), "stolen_total": get_total(SRC_THEFT),
		"company_losses": get_total(SRC_LOSSES),
	}


## Causa con la que evaluate_ending() evalúa: la de game_over, "ownership_notarised" tras
## ownership_notarised, o "" mientras la partida sigue.
func get_terminal_cause() -> String:
	if not _cause.is_empty():
		return _cause
	return CAUSE_NOTARISED if _notarised else ""


## Documentos de propiedad: en el inventario, en un escondite del jugador o ya notariados.
func has_ownership_documents() -> bool:
	if _notarised or PlayerState.has_item(OWNERSHIP_ITEM):
		return true
	for record: Variant in PlayerState.get_stashes().values():
		for item: Variant in _dict(record).get(STASH_ITEMS, []):
			if item is Dictionary and str((item as Dictionary).get(ITEM_ID, "")) == OWNERSHIP_ITEM:
				return true
	return false


func is_notarised() -> bool:
	return _notarised


## € acumulados de SRC_BRIBES ("bribes") y SRC_THEFT ("theft"); SRC_LOSSES ("company_losses") =
## Company.get_total_theft_losses() redondeado.
func get_total(source: String) -> int:
	if source == SRC_LOSSES:
		return roundi(_company_losses())
	return int(_totals.get(source, 0))


## {fuente → {eje → puntos}} (copia; incluye la RUINA pendiente de NewsFeed y Company).
func get_breakdown() -> Dictionary:
	var out: Dictionary = _breakdown.duplicate(true)
	_add_points(out, SRC_SCANDAL, AXIS_RUIN, _pending_scandals() * _increment(SRC_SCANDAL))
	_add_points(out, SRC_LOSSES, AXIS_RUIN, _pending_loss_points() * _increment(SRC_LOSSES))
	return out


## npc_id de los eliminados, en orden.
func get_victims() -> Array[String]:
	return _victims.duplicate()


## npc_id de quienes cargaron con culpas del jugador.
func get_scapegoats() -> Array[String]:
	return _scapegoats.duplicate()


## Texto del epílogo: tr(epilogue_key) [+ párrafo + variante de ruina], marcadores rellenados.
## context (opcional): valores ya formateados para los marcadores y ruin_tier ("empire"|"husk").
func get_epilogue(ending_id: String, context: Dictionary = {}) -> String:
	var ending: Dictionary = Database.get_ending(ending_id)
	if ending.is_empty():
		return ""
	var values: Dictionary = _placeholder_values(ending, context)
	var text: String = tr(str(ending.get(E_EPILOGUE, ""))).format(values)
	if not bool(ending.get(E_HAS_VARIANTS, false)):
		return text
	var variants: Dictionary = _dict(ending.get(E_VARIANTS, {}))
	var tier: String = str(context.get(CTX_RUIN_TIER, ""))
	if not RUIN_TIERS.has(tier):
		tier = get_ruin_tier()
	if variants.has(tier):
		text += PARAGRAPH + tr(str(variants[tier])).format(values)
	return text


# ═══ Evaluación de finales ════════════════════════════════════════════

func _facts(cause: String) -> Dictionary:
	return {
		C_RANK: PlayerState.get_rank(), C_DOCS: has_ownership_documents(),
		C_NOTARISED: _notarised, C_HYBRID: is_hybrid(), C_DOMINANT: get_dominant_axis(),
		C_CAUSE: cause,
	}


func _conditions_met(conditions: Dictionary, facts: Dictionary) -> bool:
	for key: Variant in conditions:
		if str(key).begins_with(COMMENT_PREFIX):
			continue
		if not _condition_met(str(key), conditions[key], facts):
			return false
	return true


func _condition_met(key: String, value: Variant, facts: Dictionary) -> bool:
	if BOOL_CONDITIONS.has(key):
		return bool(facts[key]) == bool(value)
	match key:
		C_DOCS:
			# false = sin documentos NOTARIADOS (THE FIGUREHEAD, endings.json _nota_figurehead).
			return bool(facts[C_DOCS]) if bool(value) else not bool(facts[C_NOTARISED])
		C_RANK:
			return int(facts[C_RANK]) == int(value)
		C_RANK_MAX:
			return int(facts[C_RANK]) <= int(value)
		C_DOMINANT:
			return str(facts[C_DOMINANT]) == str(value)
		C_CAUSE:
			var cause: String = str(facts[C_CAUSE])
			var causes: Array = value if value is Array else []
			return not cause.is_empty() and (causes.has(CAUSE_ANY) or causes.has(cause))
	push_warning(WARN_CONDITION % key)
	return false


func _tie_break_order() -> Array[String]:
	var order: Array[String] = []
	for axis: Variant in _endings_rules().get(E_TIE_BREAK, []):
		if STYLE_AXES.has(str(axis)) and not order.has(str(axis)):
			order.append(str(axis))
	for axis: String in STYLE_AXES:
		if not order.has(axis):
			order.append(axis)
	return order


func _max_axis_share() -> float:
	return float(_dict(_endings_rules().get(E_HYBRID_RULE, {})).get(E_MAX_SHARE, 0.0))


func _endings_rules() -> Dictionary:
	if _rules.is_empty():
		_rules = Database.get_raw(ENDINGS_FILE)
	return _rules


# ═══ Incrementos ══════════════════════════════════════════════════════

func _award(source: String) -> void:
	var spec: Array = FIXED_INCREMENTS[source]
	add(str(spec[0]), Database.get_balance_int(str(spec[1])), source)


func _increment(source: String) -> int:
	return Database.get_balance_int(str((FIXED_INCREMENTS[source] as Array)[1]))


## Suma € al acumulado de `source` y concede el incremento por cada tramo completo nuevo.
func _accumulate(source: String, amount: int) -> void:
	if amount <= 0:
		return
	var spec: Array = STEP_INCREMENTS[source]
	var step: float = float(Database.get_balance_int(str(spec[2])))
	var before: int = get_total(source)
	_totals[source] = before + amount
	if step <= 0.0:
		return
	var steps: int = floori(float(before + amount) / step) - floori(float(before) / step)
	add(str(spec[0]), steps * Database.get_balance_int(str(spec[1])), source)


func _credit_framing(npc_id: String) -> void:
	if not _framed.has(npc_id) or _framing_credited.has(npc_id):
		return
	_framing_credited.append(npc_id)
	_append_unique(_scapegoats, npc_id)
	_award(SRC_FRAMING)


## Anota como RUINA lo pendiente de NewsFeed y Company (solo desde oyentes: los getters son puros).
func _sync_external() -> void:
	add(AXIS_RUIN, _pending_scandals() * _increment(SRC_SCANDAL), SRC_SCANDAL)
	_settled_seen = _settled_count()
	add(AXIS_RUIN, _pending_loss_points() * _increment(SRC_LOSSES), SRC_LOSSES)
	_loss_points_seen = _loss_points_now()


## RUINA que NewsFeed y Company ya justifican y aún no está anotada.
func _pending_ruin() -> int:
	return _pending_scandals() * _increment(SRC_SCANDAL) \
			+ _pending_loss_points() * _increment(SRC_LOSSES)


func _pending_scandals() -> int:
	return maxi(_settled_count() - _settled_seen, 0)


func _pending_loss_points() -> int:
	return maxi(_loss_points_now() - _loss_points_seen, 0)


func _settled_count() -> int:
	if NewsFeed.has_method(NEWS_SETTLED_GETTER):
		return int(NewsFeed.call(NEWS_SETTLED_GETTER))
	return 0


func _company_losses() -> float:
	if Company.has_method(COMPANY_LOSSES_GETTER):
		return float(Company.call(COMPANY_LOSSES_GETTER))
	return 0.0


## Puntos de pérdidas completos de la partida según Company (1 punto = euros_por_punto_perdidas €).
func _loss_points_now() -> int:
	var step: float = Database.get_balance_float(B_LOSS_STEP)
	return floori(_company_losses() / step) if step > 0.0 else 0


## Talento cualificado (§9.10, como Company): escalón del puesto ≥ escalon_talento_cualificado.
func _is_qualified_talent(occupation_id: String, npc_id: String) -> bool:
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id) if occupation == null else null
	var tier: int = occupation.tier if occupation != null else (npc.tier if npc != null else 0)
	return tier >= Database.get_balance_int(B_TALENT_TIER)


## Tipo del deber ("delivery", "volume"...): el de la jornada (PlayerState) o el de occupations.json.
func _duty_type(duty_id: String) -> String:
	var duty: Dictionary = PlayerState.get_duty(duty_id)
	if duty.has(DUTY_TYPE):
		return str(duty[DUTY_TYPE])
	for occupation: OccupationData in Database.get_all_occupations():
		for definition: Dictionary in occupation.duties:
			if str(definition.get(DUTY_ID, "")) == duty_id:
				return str(definition.get(DUTY_TYPE, ""))
	return ""


func _case_report(case_id: String) -> Dictionary:
	if case_id.is_empty() or not Security.has_method("get_case_report"):
		return {}
	return Security.get_case_report(case_id)


# ═══ Epílogo ══════════════════════════════════════════════════════════

func _placeholder_values(ending: Dictionary, context: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var redacted: String = tr(REDACTED_KEY)
	for key: Variant in ending.get(E_PLACEHOLDERS, []):
		var value: Variant = context.get(str(key))
		var text: String = str(value) if value != null else ""
		if text.is_empty():
			text = _run_placeholder(str(key), context)
		values[str(key)] = text if not text.is_empty() else redacted
	return values


## Valor de un marcador a partir de la partida ("" si no se conoce).
func _run_placeholder(key: String, context: Dictionary) -> String:
	var case_id: String = str(context.get(P_CASE, _final_case_id))
	match key:
		P_NAME:
			return PlayerState.get_player_name()
		P_DAYS:
			return str(GameClock.get_day())
		P_VICTIMS:
			return _names(_victims)
		P_SCAPEGOATS:
			return _names(_scapegoats)
		P_BRIBES:
			return _format_money(get_total(SRC_BRIBES))
		P_COMPANY_VALUE:
			return _format_money(roundi(Market.get_price() * float(_share_count())))
		P_SHARE_PRICE:
			return _format_price(Market.get_price())
		P_CASE:
			return case_id
		P_INVESTIGATOR:
			return _npc_name(str(_case_report(case_id).get(P_INVESTIGATOR, "")))
		P_EVIDENCE:
			var report: Dictionary = _case_report(case_id)
			return str(int(report[P_EVIDENCE])) if report.has(P_EVIDENCE) else ""
		P_SUCCESSOR:
			return _successor_name()
	return ""


## Acciones en circulación: la misma cifra que usa Market (market.json shares.share_count).
func _share_count() -> int:
	var shares: Dictionary = _dict(Database.get_market_params().get(MARKET_SHARES, {}))
	return int(shares.get(MARKET_SHARE_COUNT, 0))


func _names(ids: Array[String]) -> String:
	var names: PackedStringArray = PackedStringArray()
	for npc_id: String in ids:
		names.append(_npc_name(npc_id))
	return tr(LIST_SEP_KEY).join(names)


func _npc_name(npc_id: String) -> String:
	if npc_id.is_empty():
		return ""
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.name.is_empty():
		return npc.name
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.name if named != null else npc_id


## El recién titulado que ocupa la mesa (THE GAP): nombre del banco, fijo para la semilla.
func _successor_name() -> String:
	var bank: Dictionary = _dict(Database.get_raw(NAMES_FILE).get(NAME_BANK, {}))
	var firsts: Array = bank.get(FIRST_NAMES, [])
	var lasts: Array = bank.get(LAST_NAMES, [])
	if firsts.is_empty() or lasts.is_empty():
		return ""
	_rng.seed = _run_rng_seed()
	var first: String = str(firsts[_rng.randi_range(0, firsts.size() - 1)])
	return FULL_NAME_FORMAT % [first, str(lasts[_rng.randi_range(0, lasts.size() - 1)])]


func _format_money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var grouped: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % DIGIT_GROUP == 0:
			grouped += tr(THOUSANDS_SEP_KEY)
		grouped += digits[i]
	var text: String = tr(MONEY_FMT_KEY) % grouped
	return ("-" + text) if amount < 0 else text


func _format_price(price: float) -> String:
	return tr(MONEY_FMT_KEY) % (PRICE_FORMAT % price).replace(DECIMAL_POINT, tr(DECIMAL_SEP_KEY))


# ═══ Oyentes ══════════════════════════════════════════════════════════

func _on_npc_removed(npc_id: String, cause: String) -> void:
	if ELIMINATION_CAUSES.has(cause) and not _victims.has(npc_id):
		_victims.append(npc_id)
		_award(SRC_ELIMINATION)


func _on_body_hidden(body_id: String, _spot_id: String) -> void:
	if body_id.is_empty() or _hidden_bodies.has(body_id):
		return
	_hidden_bodies.append(body_id)
	_award(SRC_BODY_HIDDEN)


func _on_crime_committed(crime_type: String, _room_id: String, details: Dictionary) -> void:
	if bool(details.get(D_VIOLENT, false)) and crime_type != CRIME_ELIMINATION:
		_award(SRC_VIOLENCE)
	if THEFT_CRIMES.has(crime_type):
		_accumulate(SRC_THEFT, int(details.get(D_VALUE, 0)))
	if CRIME_SOURCES.has(crime_type):
		_award(str(CRIME_SOURCES[crime_type]))
	elif crime_type == CRIME_BRIBE:
		var npc_id: String = str(details.get(D_NPC, ""))
		if _pending_bribes.has(npc_id) and details.has(D_PAID):
			_pending_bribes[npc_id] = maxi(int(details[D_PAID]), 0)
	elif crime_type == CRIME_FRAMING:
		var target: String = str(details.get(D_TARGET, ""))
		if not target.is_empty() and target != PLAYER_ID:
			_append_unique(_framed, target)


func _on_bribe_offered(npc_id: String, amount: int, _favour_type: String) -> void:
	_pending_bribes[npc_id] = maxi(amount, 0)


func _on_bribe_result(npc_id: String, accepted: bool, _outcome: String) -> void:
	var amount: int = int(_pending_bribes.get(npc_id, 0))
	_pending_bribes.erase(npc_id)
	if accepted:
		_accumulate(SRC_BRIBES, amount)


func _on_idea_acquired(_idea_id: String, method: String) -> void:
	if STOLEN_IDEA_METHODS.has(method):
		_award(SRC_IDEA)


func _on_idea_presented(idea_id: String, presenter: String, _merit_gained: int) -> void:
	if presenter == PLAYER_ID and IdeaPool.get_preparation(idea_id) == PREPARATION_REAL:
		_award(SRC_PRESENTATION)


func _on_investigation_resolved(case_id: String, verdict: String, culprit: String) -> void:
	if verdict == VERDICT_PLAYER_MAJOR:
		_final_case_id = case_id
		return
	if verdict != VERDICT_OTHER or culprit.is_empty() or culprit == PLAYER_ID:
		return
	var report: Dictionary = _case_report(case_id)
	if (report.get(P_SCAPEGOATS, []) as Array).has(culprit):
		_append_unique(_framed, culprit)
	if bool(report.get(REPORT_INNOCENT, false)):
		_append_unique(_scapegoats, culprit)
	_credit_framing(culprit)


## Honesto: informe real (delivery) +10, presentación preparada (presentation) +5, resto +2.
func _on_duty_completed(duty_id: String, _quality: float, method: String) -> void:
	if method == METHOD_HONEST:
		_award(str(DUTY_SOURCES.get(_duty_type(duty_id), SRC_HONEST_DUTY)))


func _on_seat_vacated(occupation_id: String, previous_holder: String, cause: String) -> void:
	if previous_holder.is_empty() or previous_holder == PLAYER_ID \
			or not EXPULSION_CAUSES.has(cause):
		return
	if _is_qualified_talent(occupation_id, previous_holder):
		_award(SRC_TALENT)
	_credit_framing(previous_holder)


## NewsFeed (autoload anterior) ya consolidó los escándalos de la jornada al oír day_advanced.
func _on_day_advanced(_day_number: int) -> void:
	_sync_external()


func _on_tracking_event_recorded(axis: String, amount: int, source: String) -> void:
	add(axis, amount, source)


func _on_ownership_notarised() -> void:
	_notarised = true


func _on_game_over(cause: String, _ending_id: String, tracking_snapshot: Dictionary) -> void:
	_sync_external()
	_cause = cause
	var case_id: String = str(tracking_snapshot.get(D_CASE, ""))
	if _final_case_id.is_empty() and not case_id.is_empty():
		_final_case_id = case_id


# ═══ Utilidades ═══════════════════════════════════════════════════════

func _clear() -> void:
	_axes.clear()
	for axis: String in ALL_AXES:
		_axes[axis] = 0
	_breakdown.clear()
	_totals.clear()
	_pending_bribes.clear()
	_hidden_bodies.clear()
	_victims.clear()
	_framed.clear()
	_framing_credited.clear()
	_scapegoats.clear()
	_notarised = false
	_cause = ""
	_final_case_id = ""
	_settled_seen = 0
	_loss_points_seen = 0


func _run_rng_seed() -> int:
	return GameClock.get_run_seed() ^ RNG_SALT.hash()


static func _add_points(breakdown: Dictionary, source: String, axis: String, amount: int) -> void:
	if amount <= 0:
		return
	var per_source: Dictionary = breakdown.get(source, {})
	per_source[axis] = int(per_source.get(axis, 0)) + amount
	breakdown[source] = per_source


static func _append_unique(list: Array[String], value: String) -> void:
	if not list.has(value):
		list.append(value)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _int_dict(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in _dict(value):
		out[str(key)] = int(value[key])
	return out


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out
