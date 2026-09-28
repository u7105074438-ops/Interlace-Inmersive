# _social_deals.gd — Favores del módulo social: pedir un favor a cuenta de la deuda del registro (coartada, préstamo de acceso/uniforme, mirar hacia otro lado), la entrega en el mundo de los sobornos aceptados de esos favores y la delegación de deberes (§7.9, §8.2-§8.3, §10.5).
# PROPIETARIO DE: nada (estático; la deuda es de NPCDirector, las coartadas de Security, los objetos de PlayerState, la delegación de DutySystem).
# ESCUCHA: crime_committed (una sola conexión por proceso, hook(): sobornos aceptados de look_away_once / lend_access por cualquier canal).
class_name SocialDeals
extends RefCounted

## PEDIR UN FAVOR (§7.9: la deuda produce coartadas, avisos y silencios). Cuesta deuda
## (social.favor.coste_*; deuda = lo que el personaje te debe) salvo el préstamo de quien presta
## por una miseria (npcs_named special.lends_item: Frank Rudd, social.prestamo.precio_especial €).
##  · coartada: hace falta una investigación abierta; Security.provide_alibi(caso, él, false) en
##    cada caso activo (comprada: la verificación del interrogatorio puede tumbarla).
##  · préstamo: lo que su puesto le da (social.prestamo.objetos_por_herramienta: uniforme, llaves
##    maestras) o, si no, su tarjeta (tarjeta robada con su nombre: los lectores registran al
##    titular, §5.3). Un uniforme se pone en el acto (Disguise.wear); quitárselo = soltarlo.
##  · mirar hacia otro lado: deja su puesto hasta la próxima hora (override_routine de la franja a la
##    primera sala de social.mirar.salas de su planta; se anula en el siguiente hour_passed).
## SOBORNOS ENTREGADOS (hook): Bribery cobra y decide, pero nadie entregaba estos dos favores en el
## mundo: look_away_once → mirar hacia otro lado; lend_access → el préstamo (sin precio). El resto
## ya lo entregan sus dueños (praise_to_superior → Company; lie/bury → Security; la deuda que deja
## todo soborno aceptado ya suprime sus denuncias, NPCDirector).
## DELEGAR (§10.5): desde deberes.escalon_delegacion, solo en subordinados (DutySystem).

const FAVOUR_ALIBI := "alibi"
const FAVOUR_LEND := "lend"
const FAVOUR_LOOK := "look_away"
const FAVOURS: Array[String] = [FAVOUR_ALIBI, FAVOUR_LEND, FAVOUR_LOOK]
const COST_KEYS: Dictionary = {FAVOUR_ALIBI: "favor.coste_coartada", FAVOUR_LEND: "favor.coste_prestamo",
		FAVOUR_LOOK: "favor.coste_mirar"}
const LABEL_KEYS: Dictionary = {FAVOUR_ALIBI: "SOCIAL_FAVOUR_ALIBI", FAVOUR_LEND: "SOCIAL_FAVOUR_LEND",
		FAVOUR_LOOK: "SOCIAL_FAVOUR_LOOK"}
const BRIBE_LOOK := "look_away_once"
const BRIBE_LEND := "lend_access"
const CRIME_BRIBE := "bribe"
const CARD_OWNER_KEY := "owner"
const MONEY_REASON := "favour_loan"
const KIND_UNIFORM := "uniform"
const SPECIAL_LENDS := "lends_item"

static var _hooked: bool = false


static func hook() -> void:
	if _hooked or Engine.is_editor_hint():
		return
	_hooked = true
	EventBus.crime_committed.connect(_on_crime_committed)


# ─── Disponibilidad ───────────────────────────────────────────

static func cost(kind: String) -> int:
	return SocialKit.bi(str(COST_KEYS.get(kind, "")))


## "" si se puede pedir ahora; si no, la clave del motivo.
static func favour_block(npc_id: String, kind: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return "SOCIAL_REASON_GONE"
	if kind == FAVOUR_LEND:
		return _lend_block(npc)
	if NPCDirector.get_debt(npc_id) < cost(kind):
		return "SOCIAL_REASON_DEBT"
	if kind == FAVOUR_ALIBI and Security.get_active_investigations().is_empty():
		return "SOCIAL_REASON_NO_CASE"
	if kind == FAVOUR_LOOK and break_room_for(npc).is_empty():
		return "SOCIAL_REASON_NOWHERE"
	return ""


static func _lend_block(npc: NPCRuntime) -> String:
	var offer: Dictionary = lend_offer(npc)
	if PlayerState.has_item(str(offer["item"])) and not bool(offer["card"]):
		return "SOCIAL_REASON_HAVE_IT"
	if PlayerState.get_free_slots() <= 0:
		return "SOCIAL_REASON_FULL"
	var price: int = int(offer["price"])
	if price > 0:
		return "" if PlayerState.can_afford(price) else "SOCIAL_REASON_NO_MONEY"
	return "" if NPCDirector.get_debt(npc.id) >= cost(FAVOUR_LEND) else "SOCIAL_REASON_DEBT"


## Lista del submenú «Pedir un favor»: {id, label, enabled, reason}.
static func favour_choices(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	for kind: String in FAVOURS:
		var block: String = favour_block(npc_id, kind)
		var label: String = UITheme.trf(str(LABEL_KEYS[kind]), [cost(kind)])
		if kind == FAVOUR_LEND and npc != null:
			label = _lend_label(npc)
		out.append({"id": kind, "label": label, "enabled": block.is_empty(),
				"reason": UITheme.trf(block, [cost(kind)]) if not block.is_empty() else ""})
	return out


static func _lend_label(npc: NPCRuntime) -> String:
	var offer: Dictionary = lend_offer(npc)
	var what: String = SocialKit.item_name(str(offer["item"]))
	if int(offer["price"]) > 0:
		return UITheme.trf("SOCIAL_FAVOUR_LEND_PAID", [what, UITheme.format_money(int(offer["price"]))])
	return UITheme.trf("SOCIAL_FAVOUR_LEND_ITEM", [what, cost(FAVOUR_LEND)])


## Qué presta: {item, price (0 = a cuenta de la deuda), card (su tarjeta)}.
static func lend_offer(npc: NPCRuntime) -> Dictionary:
	var special: Variant = NPCDirector.get_profile(npc.id).get("special", {})
	var lends: String = str((special as Dictionary).get(SPECIAL_LENDS, "")) if special is Dictionary else ""
	if not lends.is_empty():
		return {"item": _lent_item_for(lends), "price": SocialKit.bi("prestamo.precio_especial"), "card": false}
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	var tools: Array[String] = occupation.tools if occupation != null else []
	var table: Dictionary = SocialKit.bdict("prestamo.objetos_por_herramienta")
	for tool: String in tools:
		if table.has(tool):
			return {"item": str(table[tool]), "price": 0, "card": false}
	return {"item": SocialKit.bs("prestamo.tarjeta"), "price": 0, "card": true}


static func _lent_item_for(tool: String) -> String:
	var table: Dictionary = SocialKit.bdict("prestamo.objetos_por_herramienta")
	if table.has(tool):
		return str(table[tool])
	var uniform: String = Disguise.canonical_uniform(tool)
	return uniform if not uniform.is_empty() else tool


# ─── Pedir el favor ───────────────────────────────────────────

static func ask_favour(npc_id: String, kind: String) -> Dictionary:
	var block: String = favour_block(npc_id, kind)
	if not block.is_empty():
		return SocialKit.refusal(block, [cost(kind)])
	match kind:
		FAVOUR_ALIBI:
			return _alibi(npc_id)
		FAVOUR_LEND:
			return _lend(npc_id)
		FAVOUR_LOOK:
			NPCDirector.add_debt(npc_id, -cost(kind))
			look_away(npc_id)
			return SocialKit.result(true, "SOCIAL_FAVOUR_LOOK_LINE", [], "SOCIAL_TOAST_LOOK_AWAY",
					[SocialKit.npc_name(npc_id)], ToastStack.KIND_GOOD)
	return SocialKit.refusal("SOCIAL_LINE_BUSY")


static func _alibi(npc_id: String) -> Dictionary:
	var cases: int = 0
	for inv: Investigation in Security.get_active_investigations():
		Security.provide_alibi(inv.id, npc_id, false)
		cases += 1
	NPCDirector.add_debt(npc_id, -cost(FAVOUR_ALIBI))
	SocialKit.spend_minutes(SocialKit.bi("minutos_accion"))
	return SocialKit.result(true, "SOCIAL_FAVOUR_ALIBI_LINE", [], "SOCIAL_TOAST_ALIBI",
			[SocialKit.npc_name(npc_id), cases], ToastStack.KIND_GOOD)


static func _lend(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var offer: Dictionary = lend_offer(npc)
	var price: int = int(offer["price"])
	if price > 0 and not PlayerState.spend_money(price, MONEY_REASON):
		return SocialKit.refusal("SOCIAL_REASON_NO_MONEY")
	if price <= 0:
		NPCDirector.add_debt(npc_id, -cost(FAVOUR_LEND))
	var item_id: String = deliver_loan(npc)
	if item_id.is_empty():
		return SocialKit.refusal("SOCIAL_REASON_FULL")
	var res: Dictionary = SocialKit.result(true, "SOCIAL_FAVOUR_LEND_LINE", [SocialKit.item_name(item_id)],
			lent_toast(offer), [npc.name, SocialKit.item_name(item_id)], ToastStack.KIND_GOOD)
	if price > 0:
		res["sfx"] = SocialKit.SFX_CASH
	return res


## Aviso del préstamo: con su tarjeta se avisa de que los lectores registrarán su nombre.
static func lent_toast(offer: Dictionary) -> String:
	return "SOCIAL_TOAST_LENT_CARD" if bool(offer.get("card", false)) else "SOCIAL_TOAST_LENT"


## Entrega el préstamo (tarjeta con su nombre, llaves o uniforme puesto). Id entregado o "".
static func deliver_loan(npc: NPCRuntime) -> String:
	var offer: Dictionary = lend_offer(npc)
	var item_id: String = str(offer["item"])
	if bool(offer["card"]):
		var card: ItemData = InventoryRules.make_item(item_id)
		var copy: ItemData = ItemData.make(card.id, card.name_key, card.category)
		copy.extra = card.extra.duplicate(true)
		copy.extra[CARD_OWNER_KEY] = npc.id
		return item_id if PlayerState.add_item_data(copy) else ""
	if not PlayerState.has_item(item_id) and not PlayerState.add_item(item_id):
		return ""
	if not Disguise.canonical_uniform(item_id).is_empty():
		Disguise.wear(item_id)
	return item_id


## Deja su puesto hasta la próxima hora (una pausa de café). false si no tiene adónde ir.
static func look_away(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var room: String = break_room_for(npc) if npc != null else ""
	if room.is_empty():
		return false
	var band: String = GameClock.get_current_band()
	var stamp: Array = [GameClock.get_run_seed(), GameClock.get_day()]
	NPCDirector.override_routine(npc_id, band, room)
	EventBus.hour_passed.connect(func(_hour: int, _day: int) -> void:
		if stamp == [GameClock.get_run_seed(), GameClock.get_day()] and NPCDirector.get_npc(npc_id) != null:
			NPCDirector.override_routine(npc_id, band, ""), CONNECT_ONE_SHOT)
	return true


## Primera sala de su planta cuyo id contiene un patrón de social.mirar.salas (no la suya); si no
## hay ninguna, un paseo por el pasillo de la planta.
static func break_room_for(npc: NPCRuntime) -> String:
	var here: String = NPCDirector.get_current_location(npc.id)
	if here.is_empty():
		return ""
	var plan: Dictionary = FloorLayout.compute(SocialKit.floor_of_room(here))
	var rooms: Array = (plan.get("rooms", {}) as Dictionary).keys()
	for pattern: Variant in SocialKit.barr("mirar.salas"):
		for room_id: Variant in rooms:
			if str(room_id).contains(str(pattern)) and str(room_id) != here:
				return str(room_id)
	var corridor: String = str(plan.get("corridor_id", ""))
	return corridor if corridor != here else ""


# ─── Sobornos aceptados: entrega en el mundo ──────────────────

static func _on_crime_committed(crime_type: String, _room_id: String, details: Dictionary) -> void:
	if crime_type != CRIME_BRIBE or not bool(details.get("accepted", false)):
		return
	var npc_id: String = str(details.get("npc_id", ""))
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not NPCDirector.is_active(npc_id):
		return
	match str(details.get("favour", "")):
		BRIBE_LOOK:
			if look_away(npc_id):
				SocialKit.toast("SOCIAL_TOAST_LOOK_AWAY", [npc.name], ToastStack.KIND_GOOD)
		BRIBE_LEND:
			var item_id: String = deliver_loan(npc)
			if not item_id.is_empty():
				SocialKit.toast(lent_toast(lend_offer(npc)), [npc.name, SocialKit.item_name(item_id)], ToastStack.KIND_GOOD)


# ─── Delegación (§10.5) ───────────────────────────────────────

static func duty_system() -> DutySystem:
	var tree: SceneTree = SocialKit.tree()
	return tree.get_first_node_in_group(DutySystem.GROUP) as DutySystem if tree != null else null


## ¿Se le enseña «Delegar»? (escalón y subordinado).
static func can_offer_delegation(npc_id: String) -> bool:
	var ds: DutySystem = duty_system()
	return ds != null and PlayerState.get_tier() >= Database.get_balance_int("deberes.escalon_delegacion") \
			and ds.is_subordinate(NPCDirector.get_npc(npc_id))


static func delegable_duties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ds: DutySystem = duty_system()
	if ds == null:
		return out
	for duty: Dictionary in PlayerState.get_pending_duties():
		var duty_id: String = str(duty.get("id", ""))
		if ds.can_delegate(duty_id).is_empty():
			out.append({"id": duty_id, "label": TranslationServer.translate(str(duty.get("name_key", duty_id))),
					"enabled": true, "reason": ""})
	return out


static func delegate(npc_id: String, duty_id: String) -> Dictionary:
	var ds: DutySystem = duty_system()
	if ds == null:
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	var out: Dictionary = ds.delegate(duty_id, npc_id)
	if not bool(out.get("ok", false)):
		return SocialKit.refusal(str(out.get("error_key", "SOCIAL_LINE_BUSY")))
	var name: String = SocialKit.npc_name(npc_id)
	if bool(out.get("failed", false)):
		return SocialKit.result(true, "SOCIAL_DELEGATE_LINE", [], "SOCIAL_TOAST_DELEGATE_FAILED", [name], ToastStack.KIND_BAD)
	return SocialKit.result(true, "SOCIAL_DELEGATE_LINE", [], "SOCIAL_TOAST_DELEGATED", [name], ToastStack.KIND_GOOD)
