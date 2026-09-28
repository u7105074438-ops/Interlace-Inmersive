# _social_rules.gd — Reglas del menú social: qué opciones ofrece un personaje ahora (con su motivo si están cerradas), sus submenús, la ejecución de cada una, el rumor dirigido y la eliminación sin testigos (§8.3, §12.2).
# PROPIETARIO DE: nada (estático; lo usa NPCInteractionMenu y las pruebas sin escena).
# ESCUCHA: nada.
class_name SocialRules
extends RefCounted

## OPCIÓN = {id, icon, flow, enabled, reason (texto si está cerrada), hint (texto de apoyo),
##   danger (se pinta en rojo), red (cerrada por testigos: roja y sin foco), favour (flujo bribe),
##   confirm ({title_key, body_key, go_key, args}: se confirma antes, §13.7)}.
## flow: "perform" (se ejecuta), "choices" (submenú de choices()), "bribe" (panel de soborno en
## persona), "eliminate" (acto + escena). Las opciones que no vienen al caso no se listan (idea
## sin idea, chantaje sin material, delegar sin subordinado); las que existen siempre (charla,
## indicaciones, rumor, favor, soborno, eliminar) salen cerradas con su motivo.
## env = {room_id, witnesses: Array[String], cameras: Array[String]} (SocialWorld.exposure).
## RUMOR: sobre un compañero → SocialGraph.inject_rumour(él, "<rumor.hecho_colega>:<sujeto>",
##   rumor.certeza) (emite crime_committed "rumour_planted": seda +3 en Tracking); sobre la
##   dirección → Strike.plant_rumour (sus límites y su descontento). Uno por personaje y jornada.
##   Un difusor (sociabilidad >= rumor.sociabilidad_difusor, Debbie §8.3) lo reparte por todo el
##   edificio en sus corrillos; un rookie sin vínculos no lo cuenta a nadie (se avisa).
## ELIMINAR (§12.2, misma regla que la flagrancia): solo si env no tiene testigos ni cámaras; si
##   no, cerrada y en rojo. eliminate() vuelve a comprobarlo: NPCDirector.remove_npc(él,
##   "eliminated") (cuerpo: body_created) + crime_committed("elimination", sala, {npc_id,
##   witnesses: testigos + cámaras de env, 0 al pasar la regla}).

const OPT_CHAT := "chat"
const OPT_DIRECTIONS := "directions"
const OPT_RUMOUR := "rumour"
const OPT_AGITATE := "agitate"
const OPT_CREDIT := "credit"
const OPT_FAVOUR := "favour"
const OPT_LOOK := "look_away"
const OPT_BRIBE := "bribe"
const OPT_PRAISE := "praise"
const OPT_BLACKMAIL := "blackmail"
const OPT_DELEGATE := "delegate"
const OPT_CEDE := "cede_idea"
const OPT_BUY := "buy_idea"
const OPT_ELIMINATE := "eliminate"
const FLOW_PERFORM := "perform"
const FLOW_CHOICES := "choices"
const FLOW_BRIBE := "bribe"
const FLOW_ELIMINATE := "eliminate"
const LABEL_FORMAT := "SOCIAL_OPT_%s"
const RUMOUR_KIND := "rumour"
const RUMOUR_MANAGEMENT := "management"
const REMOVAL_CAUSE := "eliminated"
const CRIME_ELIMINATION := "elimination"
const FAVOUR_LOOK := "look_away_once"
const FAVOUR_PRAISE := "praise_to_superior"
const SPECIAL_NO_CASH := "accepts_cash_bribes"
const ROOKIE := "rookie"
const B_BRIBE_STEP := "movil.soborno_paso"
## Quejarse de la dirección solo desde abajo (el jugador es uno de los escalones afectados, §11.7).
const B_WORKER_TIER := "descontento.escalon_max_afectado"


# ─── Opciones ─────────────────────────────────────────────────

static func options(npc_id: String, env: Dictionary) -> Array[Dictionary]:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var out: Array[Dictionary] = []
	if npc == null or not NPCDirector.is_active(npc_id):
		return out
	out.append(_opt(OPT_CHAT, "talk", FLOW_PERFORM, SocialTalk.can_chat(npc_id)))
	out.append(_opt(OPT_DIRECTIONS, "map", FLOW_CHOICES, ""))
	out.append(_opt(OPT_RUMOUR, "ear", FLOW_CHOICES, rumour_block(npc_id)))
	_social_extras(npc, out)
	out.append(_favour_option(npc_id))
	_money_options(npc, out)
	_leverage_options(npc, out)
	out.append(eliminate_option(env))
	return out


static func _social_extras(npc: NPCRuntime, out: Array[Dictionary]) -> void:
	if PlayerState.get_tier() <= Database.get_balance_int(B_WORKER_TIER) and bool(Strike.can_agitate(npc.id).get("allowed", false)):
		out.append(_opt(OPT_AGITATE, "talk", FLOW_PERFORM, ""))
	if SocialTalk.wants_credit(npc):
		var credit: Dictionary = _opt(OPT_CREDIT, "star", FLOW_PERFORM, SocialTalk.can_give_credit(npc.id))
		credit["confirm"] = {"title_key": "SOCIAL_CONFIRM_CREDIT_TITLE", "body_key": "SOCIAL_CONFIRM_CREDIT_BODY",
				"go_key": "SOCIAL_CONFIRM_CREDIT_GO", "args": [npc.name, SocialKit.bf("credito.coste_reputacion")]}
		out.append(credit)


static func _favour_option(npc_id: String) -> Dictionary:
	var opt: Dictionary = _opt(OPT_FAVOUR, "clipboard", FLOW_CHOICES, "")
	var debt: int = NPCDirector.get_debt(npc_id)
	opt["hint"] = UITheme.trf("SOCIAL_HINT_DEBT", [debt]) if debt > 0 else TranslationServer.translate("SOCIAL_HINT_NO_DEBT")
	return opt


static func _money_options(npc: NPCRuntime, out: Array[Dictionary]) -> void:
	var block: String = bribe_block(npc)
	if NPCDirector.is_guard(npc.id):
		var look: Dictionary = _opt(OPT_LOOK, "eye", FLOW_BRIBE, block)
		look["favour"] = FAVOUR_LOOK
		out.append(look)
	out.append(_opt(OPT_BRIBE, "coin", FLOW_BRIBE, block))
	if npc.tier >= PlayerState.get_tier():
		var praise: Dictionary = _opt(OPT_PRAISE, "star", FLOW_BRIBE, block)
		praise["favour"] = FAVOUR_PRAISE
		out.append(praise)


static func _leverage_options(npc: NPCRuntime, out: Array[Dictionary]) -> void:
	if not SocialLeverage.material_on(npc.id).is_empty():
		out.append(_opt(OPT_BLACKMAIL, "hazard", FLOW_CHOICES, SocialLeverage.blackmail_block(npc.id)))
	if SocialDeals.can_offer_delegation(npc.id):
		var none: bool = SocialDeals.delegable_duties().is_empty()
		out.append(_opt(OPT_DELEGATE, "clipboard", FLOW_CHOICES, "SOCIAL_REASON_NO_DUTY" if none else ""))
	if SocialLeverage.idea_of(npc.id) != null:
		out.append(_opt(OPT_CEDE, "star", FLOW_PERFORM, SocialLeverage.cede_block(npc.id)))
		out.append(_opt(OPT_BUY, "coin", FLOW_CHOICES, ""))


## Eliminar: cerrada y en rojo con testigos o cámaras (§12.2).
static func eliminate_option(env: Dictionary) -> Dictionary:
	var witnesses: Array = env.get("witnesses", [])
	var cameras: Array = env.get("cameras", [])
	var block: String = ""
	var args: Array = []
	if not witnesses.is_empty():
		block = "SOCIAL_REASON_WITNESSES"
		args = [SocialKit.npc_name(str(witnesses[0])), witnesses.size()]
	elif not cameras.is_empty():
		block = "SOCIAL_REASON_CAMERA"
	var opt: Dictionary = _opt(OPT_ELIMINATE, "cross", FLOW_ELIMINATE, block, args)
	opt["danger"] = true
	opt["red"] = not block.is_empty()
	return opt


static func _opt(id: String, icon: String, flow: String, block: String, args: Array = []) -> Dictionary:
	return {"id": id, "icon": icon, "flow": flow, "label": TranslationServer.translate(LABEL_FORMAT % id.to_upper()),
			"enabled": block.is_empty(), "reason": UITheme.trf(block, args) if not block.is_empty() else "",
			"hint": "", "danger": false, "red": false, "favour": "", "confirm": {}}


## Motivo por el que no se puede sobornar ahora ("" = se puede; el resto lo decide Bribery).
static func bribe_block(npc: NPCRuntime) -> String:
	var special: Variant = NPCDirector.get_profile(npc.id).get("special", {})
	if special is Dictionary and (special as Dictionary).has(SPECIAL_NO_CASH) and not bool(special[SPECIAL_NO_CASH]):
		return "SOCIAL_REASON_NO_CASH"
	if not PhoneContactsTab.will_answer(npc):
		return "SOCIAL_REASON_RANK_GAP"
	if PlayerState.get_money() < maxi(Database.get_balance_int(B_BRIBE_STEP), 1):
		return "SOCIAL_REASON_NO_MONEY"
	return ""


# ─── Submenús ─────────────────────────────────────────────────

## {id, label, enabled, reason, confirm?} de la opción `option_id`.
static func choices(option_id: String, npc_id: String) -> Array[Dictionary]:
	match option_id:
		OPT_DIRECTIONS:
			var topics: Array[Dictionary] = SocialTalk.direction_topics(npc_id)
			for topic: Dictionary in topics:
				topic.merge({"enabled": true, "reason": ""})
			return topics
		OPT_RUMOUR:
			return rumour_choices(npc_id)
		OPT_FAVOUR:
			return SocialDeals.favour_choices(npc_id)
		OPT_BLACKMAIL:
			return _with_confirm(SocialLeverage.demand_choices(npc_id), npc_id, "SOCIAL_CONFIRM_BM_TITLE", "SOCIAL_CONFIRM_BM_BODY", "SOCIAL_CONFIRM_BM_GO")
		OPT_DELEGATE:
			return SocialDeals.delegable_duties()
		OPT_BUY:
			return SocialLeverage.purchase_choices(npc_id)
	return []


static func _with_confirm(list: Array[Dictionary], npc_id: String, title: String, body: String, go: String) -> Array[Dictionary]:
	for entry: Dictionary in list:
		entry["confirm"] = {"title_key": title, "body_key": body, "go_key": go, "args": [SocialKit.npc_name(npc_id), entry["label"]]}
	return list


# ─── Ejecución ────────────────────────────────────────────────

static func perform(option_id: String, choice_id: String, npc_id: String, env: Dictionary) -> Dictionary:
	var room: String = str(env.get("room_id", PlayerState.get_room()))
	match option_id:
		OPT_CHAT:
			return SocialTalk.chat(npc_id)
		OPT_DIRECTIONS:
			return SocialTalk.directions(npc_id, choice_id)
		OPT_RUMOUR:
			return plant_rumour(npc_id, choice_id)
		OPT_AGITATE:
			return agitate(npc_id)
		OPT_CREDIT:
			return SocialTalk.give_credit(npc_id)
		OPT_FAVOUR:
			return SocialDeals.ask_favour(npc_id, choice_id)
		OPT_BLACKMAIL:
			return SocialLeverage.blackmail(npc_id, choice_id, room)
		OPT_DELEGATE:
			return SocialDeals.delegate(npc_id, choice_id)
		OPT_CEDE:
			return SocialLeverage.cede_idea(npc_id)
		OPT_BUY:
			return SocialLeverage.buy_idea(npc_id, choice_id == "generous", room)
		OPT_ELIMINATE:
			return eliminate(npc_id, env)
	return SocialKit.refusal("SOCIAL_LINE_BUSY")


# ─── Rumores (§7.7, §8.3) ─────────────────────────────────────

static func rumour_block(npc_id: String) -> String:
	return "SOCIAL_REASON_RUMOURED" if SocialKit.done_today(RUMOUR_KIND, npc_id) else ""


## De quién se puede hablar: objetivos marcados, sus vínculos y quien comparte su sala.
static func rumour_subjects(npc_id: String) -> Array[String]:
	var pool: Array[String] = []
	pool.append_array(PlayerState.get_marked_targets())
	pool.append_array(SocialGraph.get_neighbours(npc_id, 0.0))
	for other: NPCRuntime in NPCDirector.get_npcs_in_room(NPCDirector.get_current_location(npc_id)):
		pool.append(other.id)
	var out: Array[String] = []
	for id: String in pool:
		if out.size() >= SocialKit.bi("rumor.max_sujetos"):
			break
		if id != npc_id and id != SocialKit.PLAYER_ID and not out.has(id) and NPCDirector.is_active(id):
			out.append(id)
	return out


static func rumour_choices(npc_id: String) -> Array[Dictionary]:
	var check: Dictionary = Strike.can_plant_rumour(npc_id)
	var allowed: bool = bool(check.get("allowed", false))
	var out: Array[Dictionary] = [{"id": RUMOUR_MANAGEMENT, "label": TranslationServer.translate("SOCIAL_RUMOUR_MANAGEMENT"),
			"enabled": allowed, "reason": "" if allowed else TranslationServer.translate(Strike.get_reason_label_key(str(check.get("reason", ""))))}]
	for subject: String in rumour_subjects(npc_id):
		out.append({"id": subject, "label": UITheme.trf("SOCIAL_RUMOUR_ABOUT", [SocialKit.npc_name(subject)]),
				"enabled": true, "reason": ""})
	return out


static func is_spreader(npc: NPCRuntime) -> bool:
	return npc.get_trait("sociability") >= SocialKit.bi("rumor.sociabilidad_difusor")


static func plant_rumour(npc_id: String, subject: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not rumour_block(npc_id).is_empty():
		return SocialKit.refusal("SOCIAL_REASON_RUMOURED")
	var planted: bool = false
	if subject == RUMOUR_MANAGEMENT:
		var strike: Dictionary = Strike.plant_rumour(npc_id)
		if not bool(strike.get("ok", false)):
			return SocialKit.refusal(Strike.get_reason_label_key(str(strike.get("reason", ""))))
		planted = true
	else:
		var fact: String = "%s:%s" % [SocialKit.bs("rumor.hecho_colega"), subject]
		planted = not SocialGraph.inject_rumour(npc_id, fact, SocialKit.bf("rumor.certeza")).is_empty()
	if not planted:
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	SocialKit.mark(RUMOUR_KIND, npc_id)
	SocialKit.spend_minutes(SocialKit.bi("minutos_accion"))
	return _rumour_result(npc, subject)


static func _rumour_result(npc: NPCRuntime, subject: String) -> Dictionary:
	var about: String = TranslationServer.translate("SOCIAL_RUMOUR_THE_BOSSES") if subject == RUMOUR_MANAGEMENT else SocialKit.npc_name(subject)
	if is_spreader(npc):
		return SocialKit.result(true, "SOCIAL_RUMOUR_LINE_SPREADER", [], "SOCIAL_TOAST_RUMOUR_SPREAD", [npc.name, about], ToastStack.KIND_GOOD)
	if npc.archetype == ROOKIE or SocialGraph.is_isolated(npc.id):
		return SocialKit.result(true, "SOCIAL_RUMOUR_LINE_ISOLATED", [], "SOCIAL_TOAST_RUMOUR_DEAD", [npc.name], ToastStack.KIND_WARN)
	return SocialKit.result(true, "SOCIAL_RUMOUR_LINE", [], "SOCIAL_TOAST_RUMOUR", [npc.name, about], ToastStack.KIND_INFO)


## Quejarse de la dirección con un descontento (Strike.agitate, §11.7).
static func agitate(npc_id: String) -> Dictionary:
	var out: Dictionary = Strike.agitate(npc_id)
	if not bool(out.get("ok", false)):
		return SocialKit.refusal(Strike.get_reason_label_key(str(out.get("reason", ""))))
	SocialKit.spend_minutes(SocialKit.bi("minutos_charla"))
	return SocialKit.result(true, "SOCIAL_AGITATE_LINE", [], "SOCIAL_TOAST_AGITATE", [SocialKit.npc_name(npc_id)], ToastStack.KIND_INFO)


# ─── Eliminación (§12.2) ──────────────────────────────────────

static func can_eliminate(env: Dictionary) -> bool:
	return (env.get("witnesses", []) as Array).is_empty() and (env.get("cameras", []) as Array).is_empty()


static func eliminate(npc_id: String, env: Dictionary) -> Dictionary:
	if not can_eliminate(env) or not NPCDirector.is_active(npc_id):
		return SocialKit.refusal("SOCIAL_ELIM_ABORTED")
	var name: String = SocialKit.npc_name(npc_id)
	NPCDirector.remove_npc(npc_id, REMOVAL_CAUSE)
	EventBus.crime_committed.emit(CRIME_ELIMINATION, str(env.get("room_id", PlayerState.get_room())),
			{"npc_id": npc_id, "witnesses": (env.get("witnesses", []) as Array).size()
				+ (env.get("cameras", []) as Array).size()})
	var res: Dictionary = SocialKit.result(true, "", [], "SOCIAL_TOAST_ELIMINATED", [name], ToastStack.KIND_WARN)
	res["close"] = true
	return res
