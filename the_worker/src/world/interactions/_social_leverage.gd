# _social_leverage.gd — Presión y compraventa del módulo social: chantajear con material que tienes sobre él (dinero, silencio, apoyo para ascender) y sus ideas (cesión por deuda §11.1 o compra en persona).
# PROPIETARIO DE: nada (estático; material en el inventario / PERSONNEL / SocialGraph, registro en NPCDirector, ideas en IdeaPool, dinero en PlayerState).
# ESCUCHA: nada.
class_name SocialLeverage
extends RefCounted

## CHANTAJE (el jugador contra un personaje; el contrario es Blackmail/BlackmailDialog):
##  · Material: un blackmail_file suyo en el inventario (RR. HH., §11.3), un objeto comprometedor de
##    social.chantaje.objetos (objeto → personaje: notas de insider de Maurice Sandbell…), o lo que
##    su expediente te deja ver (PersonnelApp.can_see(S_SECRETS)): blackmail_secrets de su perfil o
##    una pareja clandestina (SocialGraph.get_blackmail_links, §7.7).
##  · Exigencias: dinero (salario × social.chantaje.multiplicador_dinero), silencio (olvida lo que
##    sabe de ti — sus creencias negativas — y queda en deuda: no te denuncia) o apoyo para ascender
##    (solo a quien está por encima: mérito de recomendación en Company).
##  · Cada intento emite blackmail_initiated("player", él, material): NPCDirector le suma temor y el
##    agravio "blackmailed" (§7.9). Cada social.chantaje.dias_entre jornadas por personaje.
##  · Se niega quien tiene valentía >= valentia_rechazo y temor < temor_cede: te denuncia a su
##    superior (NPCDirector.report_player_to_superior). Sus rasgos se leen en su expediente (N3).
## IDEAS (§11.1): cesión = IdeaPool.acquire(idea, "gifted") si su deuda llega a
## ideas.deuda_minima_cesion (la cesión salda esa deuda); compra = trato en persona: precio =
## salario × social.ideas.multiplicador_compra × calidad / calidad_referencia × registro ×
## dificultad × sospecha (generosa × factor_generoso), aceptación con la fórmula de §8.2
## (Bribery.probability_from; P = 0 si es insobornable) y una tirada por personaje, idea y jornada.
## Se anuncia como soborno (bribe_offered / crime_committed "bribe" / bribe_result, favor
## FAVOUR_IDEA): Tracking (oro), el registro y Security lo tratan como tal. Rechazo = rechazo neutro
## (creencia bribe_attempt:refused), nunca una denuncia: vender una idea no es un delito del otro.

const KIND_FILE := "file"
const KIND_ITEM := "item"
const KIND_SECRET := "secret"
const KIND_AFFAIR := "affair"
const DEMAND_MONEY := "money"
const DEMAND_SILENCE := "silence"
const DEMAND_PROMOTION := "promotion"
const DEMANDS: Array[String] = [DEMAND_MONEY, DEMAND_SILENCE, DEMAND_PROMOTION]
const DEMAND_KEYS: Dictionary = {DEMAND_MONEY: "SOCIAL_BM_DEMAND_MONEY",
		DEMAND_SILENCE: "SOCIAL_BM_DEMAND_SILENCE", DEMAND_PROMOTION: "SOCIAL_BM_DEMAND_PROMOTION"}
const BLACKMAIL_KIND := "blackmail"
const FILE_ITEM := "blackmail_file"
const FILE_NPC_KEY := "npc_id"
const SECRETS_KEY := "blackmail_secrets"
const LEVERAGE_FORMAT := "%s:%s"
const MONEY_REASON := "blackmail"
const MERIT_SOURCE := "blackmail_recommendation"
const B_RECOMMEND_MERIT := "empresa.merito_recomendacion"
const FAVOUR_IDEA := "idea_purchase"
const CHANNEL := "in_person"
const OUTCOME_ACCEPTED := "accepted"
const OUTCOME_REFUSED := "neutral_refusal"
const IDEA_MONEY_REASON := "idea_purchase"
const B_DEBT_CESSION := "ideas.deuda_minima_cesion"
const B_REFUSAL_CERTAINTY := "sobornos.certeza_rechazo_neutro"
const DIFFICULTY_KEY := "precio_soborno"


# ─── Material de chantaje ─────────────────────────────────────

## Lo que tienes sobre él: [{kind, leverage}] (vacío = no se le puede chantajear).
static func material_on(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: ItemData in PlayerState.get_inventory():
		if item.id == FILE_ITEM and str(item.extra.get(FILE_NPC_KEY, "")) == npc_id:
			out.append({"kind": KIND_FILE, "leverage": LEVERAGE_FORMAT % [KIND_FILE, item.id]})
	var objects: Dictionary = SocialKit.bdict("chantaje.objetos")
	for item_id: Variant in objects:
		if str(objects[item_id]) == npc_id and PlayerState.is_carrying(str(item_id)):
			out.append({"kind": KIND_ITEM, "leverage": LEVERAGE_FORMAT % [KIND_ITEM, str(item_id)]})
	if not PersonnelApp.can_see(npc_id, PersonnelApp.S_SECRETS):
		return out
	for key: Variant in NPCDirector.get_profile(npc_id).get(SECRETS_KEY, []):
		out.append({"kind": KIND_SECRET, "leverage": LEVERAGE_FORMAT % [KIND_SECRET, str(key)]})
	if not SocialGraph.get_blackmail_links(npc_id).is_empty():
		out.append({"kind": KIND_AFFAIR, "leverage": LEVERAGE_FORMAT % [KIND_AFFAIR, npc_id]})
	return out


static func blackmail_block(npc_id: String) -> String:
	if material_on(npc_id).is_empty():
		return "SOCIAL_REASON_NO_MATERIAL"
	if SocialKit.cooldown_left(BLACKMAIL_KIND, npc_id, SocialKit.bi("chantaje.dias_entre")) > 0:
		return "SOCIAL_REASON_BM_WAIT"
	return ""


static func demand_money(npc: NPCRuntime) -> int:
	return Bribery.npc_daily_wage(npc) * SocialKit.bi("chantaje.multiplicador_dinero")


## Submenú de exigencias: {id, label, enabled, reason}.
static func demand_choices(npc_id: String) -> Array[Dictionary]:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var out: Array[Dictionary] = []
	for demand: String in DEMANDS:
		var args: Array = [UITheme.format_money(demand_money(npc))] if demand == DEMAND_MONEY else []
		var enabled: bool = demand != DEMAND_PROMOTION or npc.tier > PlayerState.get_tier()
		out.append({"id": demand, "label": UITheme.trf(str(DEMAND_KEYS[demand]), args), "enabled": enabled,
				"reason": "" if enabled else TranslationServer.translate("SOCIAL_REASON_NOT_ABOVE")})
	return out


static func blackmail(npc_id: String, demand: String, room_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var block: String = blackmail_block(npc_id) if npc != null else "SOCIAL_REASON_GONE"
	if not block.is_empty():
		return SocialKit.refusal(block)
	SocialKit.mark(BLACKMAIL_KIND, npc_id)
	var refuses: bool = npc.get_trait("courage") >= SocialKit.bi("chantaje.valentia_rechazo") \
			and NPCDirector.get_fear(npc_id) < SocialKit.bi("chantaje.temor_cede")
	EventBus.blackmail_initiated.emit(SocialKit.PLAYER_ID, npc_id, str(material_on(npc_id)[0]["leverage"]))
	if refuses:
		NPCDirector.report_player_to_superior(npc_id, room_id)
		return SocialKit.result(false, "SOCIAL_BM_REFUSED", [], "SOCIAL_TOAST_BM_REPORTED", [npc.name], ToastStack.KIND_BAD)
	SocialKit.note(SocialKit.NOTE_BLACKMAIL, "SOCIAL_NOTE_BLACKMAIL", [npc.name, TranslationServer.translate(str(DEMAND_KEYS[demand]))])
	match demand:
		DEMAND_MONEY:
			var amount: int = demand_money(npc)
			PlayerState.add_money(amount, MONEY_REASON)
			var paid: Dictionary = SocialKit.result(true, "SOCIAL_BM_PAYS", [], "SOCIAL_TOAST_BM_MONEY",
					[npc.name, UITheme.format_money(amount)], ToastStack.KIND_GOOD)
			paid["sfx"] = SocialKit.SFX_CASH
			return paid
		DEMAND_SILENCE:
			var forgotten: int = _silence(npc_id)
			return SocialKit.result(true, "SOCIAL_BM_SILENCE", [], "SOCIAL_TOAST_BM_SILENCE", [npc.name, forgotten], ToastStack.KIND_GOOD)
	Company.register_merit(MERIT_SOURCE, Database.get_balance_int(B_RECOMMEND_MERIT))
	return SocialKit.result(true, "SOCIAL_BM_PROMOTION", [], "SOCIAL_TOAST_BM_PROMOTION", [npc.name], ToastStack.KIND_GOOD)


## Olvida lo que sabía de ti (creencias negativas) y queda en deuda (no denuncia). Devuelve cuántas.
static func _silence(npc_id: String) -> int:
	var count: int = 0
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject == SocialKit.PLAYER_ID and BeliefNet.is_negative_fact(belief.fact) \
				and BeliefNet.forget_belief(belief.id):
			count += 1
	NPCDirector.add_debt(npc_id, SocialKit.bi("chantaje.deuda_silencio"))
	return count


# ─── Ideas (§11.1) ────────────────────────────────────────────

## Su mejor idea todavía adquirible (null si no tiene).
static func idea_of(npc_id: String) -> Idea:
	var best: Idea = null
	for idea: Idea in IdeaPool.get_available_ideas():
		if idea.owner == npc_id and not idea.presented and (best == null or idea.quality > best.quality):
			best = idea
	return best


static func cede_block(npc_id: String) -> String:
	var idea: Idea = idea_of(npc_id)
	if idea == null:
		return "SOCIAL_REASON_NO_IDEA"
	var block: String = IdeaPool.get_acquisition_block(idea.id, IdeaPoolSystem.METHOD_GIFTED)
	return IdeaPool.acquisition_block_key(block) if not block.is_empty() else ""


static func cede_idea(npc_id: String) -> Dictionary:
	var block: String = cede_block(npc_id)
	if not block.is_empty():
		return SocialKit.refusal(block)
	var idea: Idea = idea_of(npc_id)
	if not IdeaPool.acquire(idea.id, IdeaPoolSystem.METHOD_GIFTED):
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	NPCDirector.add_debt(npc_id, -Database.get_balance_int(B_DEBT_CESSION))
	SocialKit.spend_minutes(SocialKit.bi("minutos_accion"))
	return SocialKit.result(true, "SOCIAL_IDEA_CEDED_LINE", [], "SOCIAL_TOAST_IDEA", [SocialKit.npc_name(npc_id), idea.quality], ToastStack.KIND_GOOD)


static func idea_price(npc: NPCRuntime, idea: Idea, generous: bool) -> int:
	var base: float = float(Bribery.npc_daily_wage(npc)) * SocialKit.bf("ideas.multiplicador_compra") \
			* float(idea.quality) / maxf(SocialKit.bf("ideas.calidad_referencia"), 1.0)
	base *= Bribery.ledger_price_modifier(npc) * Database.get_difficulty_modifier(DIFFICULTY_KEY) \
			* Bribery.suspicion_price_factor(PlayerState.get_suspicion())
	return maxi(roundi(base * (SocialKit.bf("ideas.factor_generoso") if generous else 1.0)), 1)


## Submenú de compra: precio justo y generoso.
static func purchase_choices(npc_id: String) -> Array[Dictionary]:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var idea: Idea = idea_of(npc_id)
	var out: Array[Dictionary] = []
	if npc == null or idea == null:
		return out
	for generous: bool in [false, true]:
		var price: int = idea_price(npc, idea, generous)
		var key: String = "SOCIAL_IDEA_OFFER_GENEROUS" if generous else "SOCIAL_IDEA_OFFER"
		var enabled: bool = PlayerState.can_afford(price)
		out.append({"id": "generous" if generous else "fair", "label": UITheme.trf(key, [UITheme.format_money(price), idea.quality]),
				"enabled": enabled, "reason": "" if enabled else TranslationServer.translate("SOCIAL_REASON_NO_MONEY")})
	return out


static func buy_idea(npc_id: String, generous: bool, room_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var idea: Idea = idea_of(npc_id)
	if npc == null or idea == null:
		return SocialKit.refusal("SOCIAL_REASON_NO_IDEA")
	var price: int = idea_price(npc, idea, generous)
	if not PlayerState.can_afford(price):
		return SocialKit.refusal("SOCIAL_REASON_NO_MONEY")
	EventBus.bribe_offered.emit(npc_id, price, FAVOUR_IDEA)
	var fair: int = idea_price(npc, idea, false)
	var p: float = 0.0 if Bribery.is_npc_unbribable(npc) else Bribery.probability_from(npc.traits, price, fair, Bribery.gather_inputs(npc, {}))
	var accepted: bool = Bribery.roll_for([npc_id, FAVOUR_IDEA, idea.id]) < p
	if accepted:
		PlayerState.spend_money(price, IDEA_MONEY_REASON)
		IdeaPool.acquire(idea.id, IdeaPoolSystem.METHOD_PURCHASE)
	else:
		BeliefNet.create_belief(npc_id, SocialKit.PLAYER_ID, Bribery.FACT_REFUSED,
				Database.get_balance_float(B_REFUSAL_CERTAINTY), Bribery.SOURCE_DIRECT, room_id)
	var outcome: String = OUTCOME_ACCEPTED if accepted else OUTCOME_REFUSED
	EventBus.crime_committed.emit(Bribery.CRIME_BRIBE, room_id, {"npc_id": npc_id, "amount": price,
			"paid": price if accepted else 0, "favour": FAVOUR_IDEA, "channel": CHANNEL, "accepted": accepted, "outcome": outcome})
	EventBus.bribe_result.emit(npc_id, accepted, outcome)
	if not accepted:
		return SocialKit.result(false, "SOCIAL_IDEA_REFUSED_LINE", [], "SOCIAL_TOAST_IDEA_REFUSED", [npc.name], ToastStack.KIND_WARN)
	var res: Dictionary = SocialKit.result(true, "SOCIAL_IDEA_SOLD_LINE", [], "SOCIAL_TOAST_IDEA_BOUGHT",
			[npc.name, UITheme.format_money(price)], ToastStack.KIND_GOOD)
	res["sfx"] = SocialKit.SFX_CASH
	return res
