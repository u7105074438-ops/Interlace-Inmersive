# _security_gear.gd — Equipo robable (§11.4, §22.1, §22.3): taquillas de uniformes (coger, ponérselo, devolverlo; ser visto es evidencia definitiva), el carrito de limpieza con las llaves maestras y los armeros de herramientas de forzado.
# PROPIETARIO DE: nada (el inventario y el disfraz son de PlayerState; lo que ya se sacó hoy de una taquilla o del carrito, banderas secops.*).
# ESCUCHA: nada.
class_name SecurityGear
extends RefCounted

## DECISIONES:
##  · uniform_locker (data uniform, owner, contains): sin el uniforme → «Coger y ponérselo»: acto
##    visible theft_small; quien lo vea al terminar (Perception.witnesses_of) pasa a
##    Disguise.take_uniform como testigo (§22.3: evidencia definitiva, caso abierto con pieza de 10).
##    Después Disguise.wear → PlayerState.set_disguise → disguise_changed (el jugador cambia de
##    ropa). Con él encima: ponérselo / devolverlo (se quita el disfraz). El uniforme del propio
##    puesto no es un disfraz (Disguise.is_own_uniform): la taquilla solo lo dice. Otros objetos de
##    la taquilla (guard_keys) se cogen aparte (theft_small).
##  · cleaning_cart: las llaves maestras (operativa.carrito.llaves) una vez por jornada (theft_small).
##  · tool_rack: una herramienta de contains cada vez (theft_small); son comprometedoras.

const TYPES: Array[String] = ["uniform_locker", "cleaning_cart", "tool_rack"]
const T_LOCKER := "uniform_locker"
const T_CART := "cleaning_cart"
const T_RACK := "tool_rack"
const CRIME_THEFT := "theft_small"
const ACT_TAKE := "take"
const ACT_WEAR := "wear"
const ACT_RETURN := "return"
const ACT_ITEM := "item:"
const F_TAKEN := "taken"


static func handles(interact_type: String) -> bool:
	return TYPES.has(interact_type)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_LOCKER:
			await use_locker(item, player, ctx)
		T_CART:
			await use_cart(item, player, ctx)
		T_RACK:
			await use_rack(item, player, ctx)


static func locker_prompt(item: Interactable) -> String:
	var uniform: String = str(item.data.get("uniform", ""))
	return "SECOPS_PROMPT_LOCKER_RETURN" if PlayerState.get_disguise() == uniform and not uniform.is_empty() else ""


# ─── Taquillas de uniformes ───────────────────────────────────

## Acciones disponibles y sus etiquetas: {actions: Array[String], options: Array}.
static func locker_menu(item: Interactable) -> Dictionary:
	var uniform: String = str(item.data.get("uniform", ""))
	var actions: Array[String] = []
	var options: Array = []
	if PlayerState.get_disguise() == uniform:
		actions.append(ACT_RETURN)
		options.append("SECOPS_LOCKER_RETURN")
	elif PlayerState.is_carrying(uniform):
		actions.append_array([ACT_WEAR, ACT_RETURN])
		options.append_array(["SECOPS_LOCKER_WEAR", "SECOPS_LOCKER_PUT_BACK"])
	else:
		actions.append(ACT_TAKE)
		options.append({"text_key": "SECOPS_LOCKER_TAKE", "args": [SecurityKit.item_name(uniform)], "danger": true})
	for extra: String in locker_extras(item):
		actions.append(ACT_ITEM + extra)
		options.append({"text_key": "SECOPS_LOCKER_TAKE_ITEM", "args": [SecurityKit.item_name(extra)]})
	options.append("UI_CANCEL")
	return {"actions": actions, "options": options}


## Objetos de la taquilla (contains) que no se llevan encima ni se sacaron hoy.
static func locker_extras(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	var taken: Dictionary = SecurityKit.flag_dict(F_TAKEN)
	for id: Variant in item.data.get("contains", []):
		var key: String = item.interact_id + "|" + str(id)
		if not PlayerState.is_carrying(str(id)) and int(taken.get(key, -1)) != SecurityKit.today():
			out.append(str(id))
	return out


static func use_locker(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var uniform: String = str(item.data.get("uniform", ""))
	if Disguise.is_own_uniform(uniform):
		SecurityKit.toast(ctx, "SECOPS_LOCKER_OWN", [SecurityKit.item_name(uniform)], ToastStack.KIND_INFO)
		return
	var menu: Dictionary = locker_menu(item)
	var actions: Array[String] = menu["actions"]
	var i: int = await SecurityKit.choose(ctx, "SECOPS_LOCKER_TITLE", "SECOPS_LOCKER_BODY", menu["options"],
			[SecurityKit.item_name(uniform)])
	if i < 0 or i >= actions.size():
		return
	match actions[i]:
		ACT_TAKE:
			await take_uniform(item, player, ctx)
		ACT_WEAR:
			Disguise.wear(uniform)
			SecurityKit.toast(ctx, "SECOPS_LOCKER_WORN", [SecurityKit.item_name(uniform)], ToastStack.KIND_GOOD)
		ACT_RETURN:
			PlayerState.remove_item(uniform)
			SecurityKit.toast(ctx, "SECOPS_LOCKER_RETURNED", [SecurityKit.item_name(uniform)], ToastStack.KIND_INFO)
		_:
			await take_extra(item, player, ctx, actions[i].trim_prefix(ACT_ITEM))


## Coge el uniforme (acto visible) y se lo pone. true si lo lleva puesto al terminar.
static func take_uniform(item: Interactable, player: Node, ctx: Dictionary) -> bool:
	var uniform: String = str(item.data.get("uniform", ""))
	if not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("taquillas.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	var seen: Array[String] = SecurityKit.witnesses(player)
	if not Disguise.take_uniform(uniform, item.room_id, seen):
		SecurityKit.toast(ctx, "SECOPS_INVENTORY_FULL", [], ToastStack.KIND_WARN)
		return false
	Disguise.wear(uniform)
	SecurityKit.toast(ctx, "SECOPS_LOCKER_WORN", [SecurityKit.item_name(uniform)], ToastStack.KIND_GOOD)
	if not seen.is_empty():
		SecurityKit.toast(ctx, "SECOPS_LOCKER_SEEN", [SecurityKit.npc_name(seen[0])], ToastStack.KIND_BAD)
	return true


static func take_extra(item: Interactable, player: Node, ctx: Dictionary, item_id: String) -> bool:
	if not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("taquillas.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	return _steal(item, ctx, item_id)


## Objeto al inventario + delito de robo + marca del día. false si no cabe.
static func _steal(item: Interactable, ctx: Dictionary, item_id: String) -> bool:
	if not PlayerState.add_item(item_id):
		SecurityKit.toast(ctx, "SECOPS_INVENTORY_FULL", [], ToastStack.KIND_WARN)
		return false
	var data: ItemData = Database.get_item(item_id)
	var value: int = data.value if data != null else 0
	EventBus.crime_committed.emit(CRIME_THEFT, item.room_id, {"item_id": item_id, "value": value})
	var taken: Dictionary = SecurityKit.flag_dict(F_TAKEN)
	taken[item.interact_id + "|" + item_id] = SecurityKit.today()
	SecurityKit.set_flag(F_TAKEN, taken)
	SecurityKit.toast(ctx, "SECOPS_TAKEN_HOT", [SecurityKit.item_name(item_id)], ToastStack.KIND_GOOD)
	return true


# ─── Carrito de limpieza ──────────────────────────────────────

## Indicación del carrito: coger las llaves solo si siguen ahí y no las llevas ("" = la genérica).
static func cart_prompt(item: Interactable) -> String:
	var keys: String = SecurityKit.bs("carrito.llaves")
	var gone: bool = int(SecurityKit.flag_dict(F_TAKEN).get(item.interact_id + "|" + keys, -1)) == SecurityKit.today()
	return "" if gone or PlayerState.has_item(keys) else "SECOPS_PROMPT_MASTER_KEYS"


static func use_cart(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var keys: String = SecurityKit.bs("carrito.llaves")
	if PlayerState.has_item(keys):
		SecurityKit.toast(ctx, "SECOPS_CART_HAVE", [SecurityKit.item_name(keys)], ToastStack.KIND_INFO)
		return
	var taken: Dictionary = SecurityKit.flag_dict(F_TAKEN)
	if int(taken.get(item.interact_id + "|" + keys, -1)) == SecurityKit.today():
		SecurityKit.toast(ctx, "SECOPS_CART_GONE", [SecurityKit.npc_name(str(item.data.get("owner", "")))], ToastStack.KIND_INFO)
		return
	if not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("carrito.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	_steal(item, ctx, keys)


# ─── Armero de herramientas ───────────────────────────────────

static func rack_tools(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in item.data.get("contains", []):
		if not PlayerState.is_carrying(str(id)):
			out.append(str(id))
	return out


static func use_rack(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var tools: Array[String] = rack_tools(item)
	if tools.is_empty():
		SecurityKit.toast(ctx, "SECOPS_RACK_EMPTY", [], ToastStack.KIND_INFO)
		return
	var options: Array = []
	for id: String in tools:
		options.append({"text_key": "SECOPS_RACK_TAKE", "args": [SecurityKit.item_name(id)], "danger": true})
	options.append("UI_CANCEL")
	var i: int = await SecurityKit.choose(ctx, "SECOPS_RACK_TITLE", "SECOPS_RACK_BODY", options)
	if i < 0 or i >= tools.size() or not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("herramientas.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	_steal(item, ctx, tools[i])
