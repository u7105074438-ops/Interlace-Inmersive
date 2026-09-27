# utility_ai.gd — Decisión por utilidad (§7.5, PASO 16): puntúa el repertorio y elige la acción.
# PROPIETARIO DE: nada (biblioteca pura; los pesos viven en balance.json → utilidad).
# ESCUCHA: nada (NPCDirector la invoca al recibir eventos; nunca por fotograma).
class_name UtilityAI
extends RefCounted

## Utilidad(acción) = sesgo
##     + Σ rasgos[r] × rasgo/100                       (seis rasgos, §7.4)
##     + creencia × Σ certeza de las creencias relevantes (sobre el jugador)
##     + animo × ánimo (−1..1)
##     + Σ relacion[k] × valor del registro (afecto, temor, deuda, agravios, favores; §7.9)
##     + rango × rango_jugador/33 + sospecha × sospecha/100 + reputacion × reputación/100
##     + oferta × ratio de oferta (solo sobornos, 0..1)
## No hay reglas del tipo «si el rango es bajo, denunciar»: el trato por rango emerge del término
## rango (§7.5). El contexto solo decide QUÉ acciones están disponibles (p. ej. aceptar un soborno
## exige que se haya ofrecido uno), nunca cuál gana.
##
## Contexto (todas las claves opcionales):
##   actions: Array[String] candidatas (por defecto, todo el repertorio con pesos)
##   belief_certainties: Array de float (certezas relevantes; se suman)
##   player_rank: int · player_suspicion: float 0-100 · player_reputation: float 0-100
##   ledger: Dictionary (§7.9; por defecto npc.ledger) · mood: float (por defecto npc.mood)
##   offer_ratio: float 0..1 · weights: Dictionary (caché de balance utilidad)
##   relation_scales: {agravios: float, favores: float} (caché de balance registro)
## evaluate() devuelve {action, score, scores: {acción: float}}; empate → primera candidata.

# ─── Repertorio (§7.5) ─────────────────────────────────────────
const WORK := "work"
const GOSSIP := "gossip"
const REPORT_TO_SECURITY := "report_to_security"
const CONFRONT_PLAYER := "confront_player"
const ACCEPT_BRIBE := "accept_bribe"
const REFUSE_BRIBE := "refuse_bribe"
const GENERATE_IDEA := "generate_idea"
const REST := "rest"
const FLEE := "flee"
const BLACKMAIL_PLAYER := "blackmail_player"
const SABOTAGE_RIVAL := "sabotage_rival"
## Extensiones: «informa a su superior directo» (§12.2) y «callar por temor» (§7.5).
const REPORT_TO_SUPERIOR := "report_to_superior"
const STAY_SILENT := "stay_silent"

const BASE_ACTIONS: Array[String] = [
	WORK, GOSSIP, REPORT_TO_SECURITY, CONFRONT_PLAYER, ACCEPT_BRIBE, REFUSE_BRIBE,
	GENERATE_IDEA, REST, FLEE, BLACKMAIL_PLAYER, SABOTAGE_RIVAL,
]
const ACTIONS: Array[String] = [
	WORK, GOSSIP, REPORT_TO_SECURITY, CONFRONT_PLAYER, ACCEPT_BRIBE, REFUSE_BRIBE,
	GENERATE_IDEA, REST, FLEE, BLACKMAIL_PLAYER, SABOTAGE_RIVAL, REPORT_TO_SUPERIOR, STAY_SILENT,
]
## Conjuntos por disparador (disponibilidad, no preferencia).
const REACTION_ACTIONS: Array[String] = [
	REPORT_TO_SECURITY, REPORT_TO_SUPERIOR, STAY_SILENT, GOSSIP, CONFRONT_PLAYER, WORK, FLEE,
]
const IDLE_ACTIONS: Array[String] = [
	WORK, REST, GOSSIP, GENERATE_IDEA, SABOTAGE_RIVAL, BLACKMAIL_PLAYER,
]
const BRIBE_ACTIONS: Array[String] = [ACCEPT_BRIBE, REFUSE_BRIBE]
const REPORT_ACTIONS: Array[String] = [REPORT_TO_SECURITY, REPORT_TO_SUPERIOR]

# ─── Claves de pesos (balance.json → utilidad.<acción>) ────────
const BALANCE_SECTION := "utilidad"
const W_TRAITS := "rasgos"
const W_BELIEF := "creencia"
const W_MOOD := "animo"
const W_RELATION := "relacion"
const W_RANK := "rango"
const W_SUSPICION := "sospecha"
const W_REPUTATION := "reputacion"
const W_OFFER := "oferta"
const W_BIAS := "sesgo"
const TERM_TOTAL := "total"
const REL_AFFECTION := "afecto"
const REL_FEAR := "temor"
const REL_DEBT := "deuda"
const REL_GRIEVANCES := "agravios"
const REL_FAVOURS := "favores"
const B_SCALE_GRIEVANCES := "registro.escala_utilidad_agravios"
const B_SCALE_FAVOURS := "registro.escala_utilidad_favores"

# ─── Claves de contexto ────────────────────────────────────────
const CTX_ACTIONS := "actions"
const CTX_BELIEFS := "belief_certainties"
const CTX_RANK := "player_rank"
const CTX_SUSPICION := "player_suspicion"
const CTX_REPUTATION := "player_reputation"
const CTX_LEDGER := "ledger"
const CTX_MOOD := "mood"
const CTX_OFFER := "offer_ratio"
const CTX_WEIGHTS := "weights"
const CTX_SCALES := "relation_scales"

## Escalas de los medidores (rangos del manual, no ajustes): sospecha y reputación 0-100 (§7.10),
## afecto −100..100 y temor 0-100 (§7.9), rango 0-33 (§6.1).
const METER_MAX := 100.0
const LEDGER_MAX := 100.0
## Nombre visible de una acción: tr("UTILITY_ACTION_<ACCIÓN>").
const ACTION_KEY_FORMAT := "UTILITY_ACTION_%s"


## Puntúa las candidatas del contexto y devuelve la de mayor utilidad.
static func evaluate(npc: NPCRuntime, context: Dictionary) -> Dictionary:
	var weights: Dictionary = _weights(context)
	var candidates: Array = context.get(CTX_ACTIONS, weights.keys())
	var scores: Dictionary = {}
	var best_action: String = ""
	var best_score: float = -INF
	for action: Variant in candidates:
		var action_id: String = str(action)
		if action_id.begins_with("_") or not weights.has(action_id):
			continue
		var value: float = score_action(action_id, npc, context)
		scores[action_id] = value
		if value > best_score:
			best_score = value
			best_action = action_id
	return {"action": best_action, "score": best_score if not best_action.is_empty() else 0.0,
			"scores": scores}


## Utilidad de una acción (suma de breakdown()).
static func score_action(action: String, npc: NPCRuntime, context: Dictionary) -> float:
	return float(breakdown(action, npc, context).get(TERM_TOTAL, 0.0))


## Desglose por término de la fórmula de §7.5 (panel de depuración y tests).
static func breakdown(action: String, npc: NPCRuntime, context: Dictionary) -> Dictionary:
	var w: Dictionary = _weights(context).get(action, {})
	var terms: Dictionary = {
		W_TRAITS: trait_term(w, npc.traits),
		W_BELIEF: _num(w, W_BELIEF) * _belief_sum(context),
		W_MOOD: _num(w, W_MOOD) * float(context.get(CTX_MOOD, npc.mood)),
		W_RELATION: relation_term(w, context.get(CTX_LEDGER, npc.ledger), _scales(context)),
		W_RANK: _num(w, W_RANK) * float(context.get(CTX_RANK, 0)) / OccupationData.MAX_RANK,
		W_SUSPICION: _num(w, W_SUSPICION) * float(context.get(CTX_SUSPICION, 0.0)) / METER_MAX,
		W_REPUTATION: _num(w, W_REPUTATION) * float(context.get(CTX_REPUTATION, 0.0)) / METER_MAX,
		W_OFFER: _num(w, W_OFFER) * float(context.get(CTX_OFFER, 0.0)),
		W_BIAS: _num(w, W_BIAS),
	}
	var total: float = 0.0
	for key: String in terms:
		total += float(terms[key])
	terms[TERM_TOTAL] = total
	return terms


## Σ peso_rasgo × rasgo/100.
static func trait_term(action_weights: Dictionary, traits: Dictionary) -> float:
	var trait_weights: Variant = action_weights.get(W_TRAITS, {})
	if not (trait_weights is Dictionary):
		return 0.0
	var total: float = 0.0
	for trait_name: Variant in trait_weights:
		var value: float = float(traits.get(trait_name, Validate.TRAIT_MIN))
		total += float(trait_weights[trait_name]) * value / Validate.TRAIT_MAX
	return total


## Σ peso_relación × valor normalizado del registro (§7.9).
static func relation_term(action_weights: Dictionary, ledger: Dictionary,
		scales: Dictionary) -> float:
	var rel_weights: Variant = action_weights.get(W_RELATION, {})
	if not (rel_weights is Dictionary):
		return 0.0
	var inputs: Dictionary = relation_inputs(ledger, scales)
	var total: float = 0.0
	for key: Variant in rel_weights:
		total += float(rel_weights[key]) * float(inputs.get(key, 0.0))
	return total


## Valores normalizados del registro: afecto/100, temor/100, deuda/100 (acotada a ±1),
## Σgravedad/escala_agravios, Σmagnitud/escala_favores.
static func relation_inputs(ledger: Dictionary, scales: Dictionary) -> Dictionary:
	var grievance_scale: float = maxf(float(scales.get(REL_GRIEVANCES, 1.0)), 1.0)
	var favour_scale: float = maxf(float(scales.get(REL_FAVOURS, 1.0)), 1.0)
	return {
		REL_AFFECTION: float(ledger.get("affection", 0)) / LEDGER_MAX,
		REL_FEAR: float(ledger.get("fear", 0)) / LEDGER_MAX,
		REL_DEBT: clampf(float(ledger.get("debt", 0)) / LEDGER_MAX, -1.0, 1.0),
		REL_GRIEVANCES: _entry_sum(ledger.get("grievances", []), "severity") / grievance_scale,
		REL_FAVOURS: _entry_sum(ledger.get("favours", []), "magnitude") / favour_scale,
	}


## Clave de strings.csv con el nombre visible de la acción (panel F1, expediente).
static func action_name_key(action: String) -> String:
	return ACTION_KEY_FORMAT % action.to_upper()


## Pesos de balance.json → utilidad (copia). Se recomienda pasarlos en el contexto (caché).
static func load_weights() -> Dictionary:
	var raw: Variant = Database.get_balance(BALANCE_SECTION)
	return raw if raw is Dictionary else {}


## Escalas de agravios/favores de balance.json → registro.
static func load_relation_scales() -> Dictionary:
	return {
		REL_GRIEVANCES: Database.get_balance_float(B_SCALE_GRIEVANCES),
		REL_FAVOURS: Database.get_balance_float(B_SCALE_FAVOURS),
	}


static func _weights(context: Dictionary) -> Dictionary:
	var cached: Variant = context.get(CTX_WEIGHTS)
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		return cached
	return load_weights()


static func _scales(context: Dictionary) -> Dictionary:
	var cached: Variant = context.get(CTX_SCALES)
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		return cached
	return load_relation_scales()


static func _belief_sum(context: Dictionary) -> float:
	var total: float = 0.0
	var certainties: Variant = context.get(CTX_BELIEFS, [])
	if certainties is Array:
		for c: Variant in certainties:
			total += float(c)
	return total


static func _entry_sum(entries: Variant, key: String) -> float:
	var total: float = 0.0
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				total += float((entry as Dictionary).get(key, 0))
	return total


static func _num(d: Dictionary, key: String) -> float:
	var value: Variant = d.get(key, 0.0)
	return float(value) if (value is float or value is int) else 0.0
