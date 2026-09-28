# _office_terminals.gd — Terminales de puesto del módulo de oficina: nóminas y contabilidad (fraudes por cargo), prensa, bolsa, campañas y memoria de la fotocopiadora.
# PROPIETARIO DE: nada (estático; enfriamientos con banderas "office.*" de PlayerState; el dinero es de PlayerState, la prensa de NewsFeed, la reputación de PlayerState/NPCDirector).
# ESCUCHA: nada.
class_name OfficeTerminals
extends RefCounted

## · Fraudes por cargo (§23, §9.9): acciones del terminal = oficina.terminales.<tipo> ∪ data.action
##   ∪ data.actions; cada una (oficina.fraudes.<acción>: puestos, min, max, enfriamiento_dias) solo
##   para sus puestos: subirse el sueldo (payroll_clerk), empleados fantasma (payroll_manager),
##   inflar facturas (billing_clerk), falsear asientos (contables), mover capital (tesorería).
##   Confirmación (§13.7) → acto "fraud" → dinero (PlayerState.add_money) + crime_committed("fraud",
##   {value, company_loss}): Company apunta la pérdida y BeliefNet el asiento contable que aflora
##   a los 14 días (creencias.registros_por_delito.fraud). detect_fraud (contables): un superior de
##   tu departamento con las manos sucias → blackmail_file suyo (legal: es tu trabajo).
## · Prensa (§23 comms_director, §9.9): enterrar noticias (NewsFeed.bury), fabricar un escándalo
##   ajeno (NewsFeed.fabricate: emite "framing"), pieza favorable (fabricate("company")), filtrar a
##   periodistas (leak_story: el mismo escándalo, exclusivo del Director de Comunicación, §23 #40).
##   Puestos en oficina.prensa.<acción>.puestos (vacío = cualquiera que llegue); también vale si
##   el Director de Comunicación te debe un favor (soborno: consume una unidad de deuda).
## · Bolsa: cotización; "trade" abre MARKET si tu rango lo permite (Market.can_trade); los de
##   early_visibility enseñan las notas de prensa programadas.
## · Campañas (§23 marketing): autoelogio una vez al día; reputación × oficina.campana.escala_por_puesto
##   (el director de A10 a escala industrial) (+marca, eje silk) o, con prob_fracaso, un fracaso
##   público que la resta.
## · Fotocopiadora (§23 copy_operator: «visibilidad de todo documento reproducido»): el operario
##   lee oficina.copiadora.avisos_operario líneas de información temprana cuando quiera; el resto,
##   avisos_otros una vez al día por sala (copias sobrantes).

const B_FRAUD_DELAY := "creencias.registros_por_delito.fraud.retardo_dias"
const B_TERMINAL_ACTIONS := "oficina.terminales."
const B_FRAUD := "oficina.fraudes."
const B_PRESS := "oficina.prensa."
const B_PRESS_DEBT := "oficina.prensa.deuda_minima_soborno"
const B_PRESS_DAYS := "oficina.prensa.enfriamiento_escandalo_dias"
const B_TARGETS_MAX := "oficina.archivo.objetivos_max"
const B_CAMPAIGN := "oficina.campana."
const B_COPIER := "oficina.copiadora."
const DETECT_FRAUD := "detect_fraud"
const BURY := "bury_news"
const FABRICATE := "fabricate_scandal"
const LEAK := "leak_story"
const SHIFT := "shift_sentiment"
const CRIME_FRAUD := "fraud"
const CRIME_FRAMING := "framing"
const COMMS_POST := "comms_director"
const MODE_TRADE := "trade"
const APP_MARKET := "market"
const HEADLINE_SCANDAL := "NEWS_FABRICATED_SCANDAL"
const HEADLINE_PRAISE := "NEWS_FABRICATED_PRAISE"
const SUBJECT_COMPANY := "company"
const COPY_ACCESS := "copy_rooms"
const AXIS_SILK := "silk"
const NOTE_SECURITY := "security"
const LABEL_FORMAT := "OFFICE_ACTION_%s"
const DEPARTMENT_KEY := "department"


# ─── Acciones del terminal ────────────────────────────────────

static func terminal_actions(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = []
	var by_type: Variant = Database.get_balance(B_TERMINAL_ACTIONS + item.interact_type) \
			if Database.has_balance(B_TERMINAL_ACTIONS + item.interact_type) else []
	if by_type is Array:
		raw.append_array(by_type)
	var single: Variant = item.data.get("action", [])
	raw.append_array(single if single is Array else [single])
	raw.append_array(item.data.get("actions", []) as Array)
	for value: Variant in raw:
		if not str(value).is_empty() and not out.has(str(value)):
			out.append(str(value))
	return out


static func spec(prefix: String, action: String) -> Dictionary:
	var path: String = prefix + action
	return Database.get_balance(path) as Dictionary if Database.has_balance(path) else {}


static func label(action: String) -> String:
	return LABEL_FORMAT % action.to_upper()


# ─── Nóminas y contabilidad ───────────────────────────────────

## Acciones de fraude que el puesto del jugador puede hacer en este terminal.
static func fraud_actions(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	for action: String in terminal_actions(item):
		if OfficeKit.has_post(spec(B_FRAUD, action).get("puestos", [])):
			out.append(action)
	return out


static func use_fraud_terminal(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var actions: Array[String] = fraud_actions(item)
	if actions.is_empty():
		OfficeKit.refuse(ctx, "OFFICE_TERMINAL_NO_ACCESS")
		return
	var labels: Array = []
	for action: String in actions:
		labels.append(label(action))
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_TERMINAL_TITLE", "OFFICE_FRAUD_BODY", labels)
	if index < 0 or index >= actions.size():
		return
	if actions[index] == DETECT_FRAUD:
		detect_fraud(item.room_id, player, ctx)
	else:
		await run_fraud(actions[index], item.room_id, player, ctx)


## Un fraude del cargo: enfriamiento, confirmación, acto, dinero y delito. Devuelve el importe.
static func run_fraud(action: String, room: String, player: Node, ctx: Dictionary) -> int:
	var s: Dictionary = spec(B_FRAUD, action)
	var wait: int = int(s.get("enfriamiento_dias", 0)) - OfficeKit.days_since("fraud." + action)
	if wait > 0:
		OfficeKit.refuse(ctx, "OFFICE_FRAUD_TOO_SOON", [wait])
		return 0
	if not await OfficeKit.confirm(ctx, "OFFICE_TERMINAL_TITLE", "OFFICE_FRAUD_CONFIRM", "OFFICE_FRAUD_GO",
			[OfficeKit.tr_key(label(action)), Database.get_balance_int(B_FRAUD_DELAY)]):
		return 0
	if not await OfficeKit.run_act(ctx, player, CRIME_FRAUD, "fraude"):
		return 0
	var amount: int = OfficeKit.rng("fraud." + action).randi_range(int(s.get("min", 0)), int(s.get("max", 0)))
	PlayerState.add_money(amount, "fraud_" + action)
	OfficeKit.commit(CRIME_FRAUD, room, {"value": amount, "company_loss": amount, "action": action})
	OfficeKit.mark_today("fraud." + action)
	OfficeKit.spend_minutes("fraude")
	OfficeKit.note(NOTE_SECURITY, "OFFICE_NOTE_FRAUD", [OfficeKit.tr_key(label(action)), amount])
	OfficeKit.good(ctx, "OFFICE_FRAUD_DONE", [amount], OfficeKit.SFX_CASH)
	return amount


## Detectar el fraude de un superior de tu departamento (§22.10): material de chantaje.
static func detect_fraud(room: String, player: Node, ctx: Dictionary) -> String:
	var s: Dictionary = spec(B_FRAUD, DETECT_FRAUD)
	if OfficeKit.days_since("fraud." + DETECT_FRAUD) < int(s.get("enfriamiento_dias", 0)):
		OfficeKit.refuse(ctx, "OFFICE_FRAUD_TOO_SOON", [int(s.get("enfriamiento_dias", 0)) - OfficeKit.days_since("fraud." + DETECT_FRAUD)])
		return ""
	if not OfficeKit.can_take("blackmail_file"):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name("blackmail_file")])
		return ""
	OfficeKit.play(player, "type_intense")
	OfficeKit.spend_minutes("fraude")
	OfficeKit.mark_today("fraud." + DETECT_FRAUD)
	var target: String = _dirty_superior()
	if target.is_empty():
		OfficeKit.say(ctx, "OFFICE_FRAUD_CLEAN_BOOKS")
		return ""
	PlayerState.add_item_data(OfficeKit.item_copy("blackmail_file", {"npc_id": target, "kind": "fraud", "stackable": false}))
	OfficeKit.note(NOTE_SECURITY, "OFFICE_NOTE_DIRTY_BOOKS", [OfficeKit.npc_name(target)])
	OfficeKit.good(ctx, "OFFICE_FRAUD_FOUND", [OfficeKit.npc_name(target)])
	return target


## Un superior (escalón mayor) de tu departamento, al azar de la jornada.
static func _dirty_superior() -> String:
	var occ: OccupationData = PlayerState.get_occupation()
	var department: String = str(occ.extra.get(DEPARTMENT_KEY, "")) if occ != null else ""
	var candidates: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.is_active(npc.id) and npc.tier > PlayerState.get_tier() and npc.department == department:
			candidates.append(npc.id)
	if candidates.is_empty():
		return ""
	return candidates[OfficeKit.rng(DETECT_FRAUD).randi_range(0, candidates.size() - 1)]


# ─── Prensa ───────────────────────────────────────────────────

## Director de Comunicación sobornado (te debe algo): «o vía soborno».
static func comms_owes_you() -> String:
	var holder: String = Company.get_seat_holder(COMMS_POST)
	if holder.is_empty() or holder == OfficeKit.PLAYER_ID:
		return ""
	return holder if NPCDirector.get_debt(holder) >= Database.get_balance_int(B_PRESS_DEBT) else ""


static func press_allowed(action: String) -> bool:
	var posts: Array = spec(B_PRESS, action).get("puestos", []) as Array
	return posts.is_empty() or OfficeKit.has_post(posts) or not comms_owes_you().is_empty()


static func use_press(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var actions: Array[String] = []
	for action: String in terminal_actions(item):
		if press_allowed(action):
			actions.append(action)
	if actions.is_empty():
		OfficeKit.refuse(ctx, "OFFICE_PRESS_NO_ACCESS")
		return
	var labels: Array = []
	for action: String in actions:
		labels.append(label(action))
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_PRESS_TITLE", "OFFICE_PRESS_BODY", labels)
	if index < 0 or index >= actions.size():
		return
	var used: bool = false
	match actions[index]:
		BURY:
			used = await bury_news(ctx)
		SHIFT:
			used = shift_sentiment(ctx)
		_:
			used = await fabricate_scandal(item.room_id, player, ctx)
	_consume_bribe(actions[index], used)


static func _consume_bribe(action: String, used: bool) -> void:
	var posts: Array = spec(B_PRESS, action).get("puestos", []) as Array
	var holder: String = comms_owes_you()
	if used and not posts.is_empty() and not OfficeKit.has_post(posts) and not holder.is_empty():
		NPCDirector.add_debt(holder, -1)


static func bury_news(ctx: Dictionary) -> bool:
	var news: Array[Dictionary] = []
	for entry: Dictionary in NewsFeed.get_active_news():
		if (bool(entry.get("is_scandal", false)) or float(entry.get("sentiment", 0.0)) < 0.0) \
				and not bool(entry.get("consolidated", false)):
			news.append(entry)
	if news.is_empty():
		OfficeKit.say(ctx, "OFFICE_PRESS_NOTHING_TO_BURY")
		return false
	var labels: Array = []
	for entry: Dictionary in news:
		labels.append({"text_key": "OFFICE_PRESS_HEADLINE", "args": [OfficeKit.tr_key(str(entry.get("headline_id", "")))]})
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_PRESS_TITLE", "OFFICE_PRESS_BURY_BODY", labels)
	if index < 0 or index >= news.size() or not NewsFeed.bury(str(news[index].get("id", "")), OfficeKit.PLAYER_ID):
		return false
	OfficeKit.spend_minutes("prensa")
	OfficeKit.good(ctx, "OFFICE_PRESS_BURIED")
	return true


static func shift_sentiment(ctx: Dictionary) -> bool:
	if OfficeKit.used_today("press." + SHIFT):
		OfficeKit.say(ctx, "OFFICE_PRESS_DONE_TODAY")
		return false
	NewsFeed.fabricate(SUBJECT_COMPANY, HEADLINE_PRAISE)
	OfficeKit.mark_today("press." + SHIFT)
	OfficeKit.spend_minutes("prensa")
	OfficeKit.good(ctx, "OFFICE_PRESS_PRAISE")
	return true


## Escándalo fabricado (o filtrado) contra un objetivo: NewsFeed emite el delito "framing".
static func fabricate_scandal(room: String, player: Node, ctx: Dictionary) -> bool:
	var wait: int = Database.get_balance_int(B_PRESS_DAYS) - OfficeKit.days_since("press." + FABRICATE)
	if wait > 0:
		OfficeKit.refuse(ctx, "OFFICE_FRAUD_TOO_SOON", [wait])
		return false
	var targets: Array[String] = OfficeLoot.pick_targets(Database.get_balance_int(B_TARGETS_MAX))
	var labels: Array = []
	for npc_id: String in targets:
		labels.append({"text_key": "OFFICE_TARGET", "args": [OfficeKit.npc_name(npc_id)]})
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_PRESS_TITLE", "OFFICE_PRESS_TARGET_BODY", labels)
	if index < 0 or index >= targets.size():
		return false
	var target: String = targets[index]
	if not await OfficeKit.confirm(ctx, "OFFICE_PRESS_TITLE", "OFFICE_PRESS_CONFIRM", "OFFICE_PRESS_GO", [OfficeKit.npc_name(target)]):
		return false
	if not await OfficeKit.run_act(ctx, player, CRIME_FRAMING, "prensa"):
		return false
	NewsFeed.fabricate(target, HEADLINE_SCANDAL)
	OfficeKit.mark_today("press." + FABRICATE)
	OfficeKit.spend_minutes("prensa")
	OfficeKit.note(NOTE_SECURITY, "OFFICE_NOTE_SCANDAL", [OfficeKit.npc_name(target)])
	OfficeKit.good(ctx, "OFFICE_PRESS_FABRICATED", [OfficeKit.npc_name(target)])
	return true


# ─── Bolsa, campañas y fotocopiadora ──────────────────────────

static func use_trading(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var trade: bool = str(item.data.get("mode", "")) == MODE_TRADE
	if trade and Market.can_trade():
		var view: UIRoot = OfficeKit.ui(ctx)
		if view != null:
			view.open_computer({"app": APP_MARKET})
		return
	OfficeKit.play(player, "check_watch")
	OfficeKit.spend_minutes("lectura")
	var lines: Array[String] = [OfficeInfo.quote_line()]
	if bool(item.data.get("early_visibility", false)):
		lines.append_array(OfficeInfo.news_lines())
	if trade:
		lines.append(OfficeKit.tr_key("OFFICE_TRADING_LOCKED"))
	await OfficeKit.show_lines(ctx, "OFFICE_TRADING_TITLE", lines)


static func use_campaign(_item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not OfficeKit.has_post(Database.get_balance(B_CAMPAIGN + "puestos")):
		OfficeKit.refuse(ctx, "OFFICE_CAMPAIGN_NO_POST")
		return
	if OfficeKit.used_today("campaign"):
		OfficeKit.say(ctx, "OFFICE_CAMPAIGN_DONE_TODAY")
		return
	OfficeKit.play(player, "type_intense")
	OfficeKit.spend_minutes("campana")
	OfficeKit.mark_today("campaign")
	if OfficeKit.rng("campaign").randf() < Database.get_balance_float(B_CAMPAIGN + "prob_fracaso"):
		PlayerState.modify_reputation(Database.get_balance_float(B_CAMPAIGN + "reputacion_fracaso"), "campaign_flop")
		OfficeKit.refuse(ctx, "OFFICE_CAMPAIGN_FLOP")
		return
	var scale: float = float((Database.get_balance(B_CAMPAIGN + "escala_por_puesto") as Dictionary).get(
			PlayerState.get_occupation_id(), 1.0))
	PlayerState.modify_reputation(Database.get_balance_float(B_CAMPAIGN + "reputacion") * scale, "self_promotion")
	Company.modify_brand_strength(Database.get_balance_float(B_CAMPAIGN + "marca") * scale)
	PlayerState.add_tracking(AXIS_SILK, 1)
	OfficeKit.good(ctx, "OFFICE_CAMPAIGN_DONE")


static func is_copy_operator(item: Interactable) -> bool:
	return OfficeKit.has_access(COPY_ACCESS) or OfficeKit.is_own_room(item.room_id)


static func use_copier(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var operator: bool = is_copy_operator(item)
	var key: String = "copier." + OfficeKit.base_room(item.room_id)
	if not operator and OfficeKit.used_today(key):
		OfficeKit.say(ctx, "OFFICE_COPIER_DONE_TODAY")
		return
	OfficeKit.play(player, "check_watch")
	OfficeKit.spend_minutes("copiadora")
	OfficeKit.mark_today(key)
	var limit: int = Database.get_balance_int(B_COPIER + ("avisos_operario" if operator else "avisos_otros"))
	var lines: Array[String] = OfficeInfo.early_lines(limit, key)
	if lines.is_empty():
		lines.append(OfficeKit.tr_key("OFFICE_EARLY_NOTHING"))
	OfficeInfo.note_lines(lines)
	await OfficeKit.show_lines(ctx, "OFFICE_COPIER_TITLE", lines)
