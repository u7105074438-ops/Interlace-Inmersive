# _security_bodies.gd — Cuerpos, escondites y bajante (§11.3, §12.2, §14.7, §22.3): arrastrar y soltar un cuerpo, esconderse, alijar y recuperar objetos, esconder o sacar un cuerpo de un escondite y la compactadora del muelle (definitiva).
# PROPIETARIO DE: nada (los cuerpos son de NPCDirector, los alijos de PlayerState, los nodos de SecurityKeeper; la lista de cuerpos triturados es la bandera secops.disposed).
# ESCUCHA: nada.
class_name SecurityBodies
extends RefCounted

## DECISIONES:
##  · body (BodyNode): E lo coge (acto "body_moved", unos segundos) y el jugador lo arrastra: paso
##    "drag" lento y ruidoso, la percepción lo trata como delito (Perception.assess_exposure). E lejos
##    de un destino lo suelta. Entre plantas solo por el montacargas (FloorTravel lo impone).
##  · settle(): cada vez que el cuerpo queda en un sitio nuevo → NPCDirector.move_body, body_hidden
##    si queda en un escondite (NPCDirector y Security lo marcan oculto; Tracking suma sangre una vez)
##    y crime_committed("body_moved", sala, {npc_id, body_id, room_id, spot_id, disposed}).
##  · hiding_spot (HidingSpot): esconderse (Player.set_hiding: la percepción no ve dentro; moverse
##    sale), alijar (inventario con hide_spot_id: PlayerState.stash_item), recuperar
##    (InventoryRules.retrieve_from_stash cobra los minutos de la ubicación), esconder un cuerpo si
##    can_hide_body (operativa.cuerpos.por_escondite como mucho) o sacarlo para seguir arrastrándolo.
##    Con una sola acción posible se hace sin menú.
##  · trash_chute: objetos → inventario con el escondite irreversible (confirmación de la interfaz);
##    un cuerpo arrastrado → confirmación irreversible, acto, body_hidden en la compactadora y
##    bandera "disposed": trash_dock es irrelevante para los registros (investigations.json), nunca
##    se encuentra ni se puede sacar.

const TYPES: Array[String] = ["body", "hiding_spot", "trash_chute"]
const T_BODY := "body"
const T_SPOT := "hiding_spot"
const T_CHUTE := "trash_chute"
const CRIME_MOVED := "body_moved"
const F_DISPOSED := "disposed"
const A_HIDE := "hide_self"
const A_STASH := "stash"
const A_RETRIEVE := "retrieve"
const A_HIDE_BODY := "hide_body"
const A_PULL_BODY := "pull_body"
const ACTION_KEYS: Dictionary = {
	A_HIDE: "SECOPS_SPOT_HIDE", A_STASH: "SECOPS_SPOT_STASH", A_RETRIEVE: "SECOPS_SPOT_RETRIEVE",
	A_HIDE_BODY: "SECOPS_SPOT_HIDE_BODY", A_PULL_BODY: "SECOPS_SPOT_PULL_BODY",
}
const NOISE_CHUTE := "compactor_break"


static func handles(interact_type: String) -> bool:
	return TYPES.has(interact_type)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_BODY:
			await use_body(item, player, ctx)
		T_SPOT:
			await use_spot(item as HidingSpot, player, ctx)
		T_CHUTE:
			await use_chute(item, player, ctx)


static func keeper_of(node: Node) -> SecurityKeeper:
	return SecurityKeeper.find(SecurityKit.tree_of(node))


static func dragging(node: Node) -> bool:
	var keeper: SecurityKeeper = keeper_of(node)
	return keeper != null and keeper.is_dragging()


# ─── Registro del cuerpo ──────────────────────────────────────

## El cuerpo queda en `room_id` (y en `spot_id` si no está vacío): registro, ocultación y delito.
static func settle(npc_id: String, room_id: String, spot_id: String, disposed: bool) -> void:
	var info: Dictionary = NPCDirector.get_body_info(npc_id)
	if info.is_empty():
		return
	var body_id: String = str(info.get("body_id", ""))
	NPCDirector.move_body(npc_id, room_id, spot_id)
	if not spot_id.is_empty():
		EventBus.body_hidden.emit(body_id, spot_id)
	if disposed:
		var gone: Array = SecurityKit.flag_array(F_DISPOSED)
		gone.append(npc_id)
		SecurityKit.set_flag(F_DISPOSED, gone)
	EventBus.crime_committed.emit(CRIME_MOVED, room_id, {"npc_id": npc_id, "body_id": body_id,
			"room_id": room_id, "spot_id": spot_id, "disposed": disposed})


static func is_disposed(npc_id: String) -> bool:
	return SecurityKit.flag_array(F_DISPOSED).has(npc_id)


## Cuerpos escondidos (no hallados ni triturados) en un escondite.
static func bodies_in(spot_id: String) -> Array[String]:
	var out: Array[String] = []
	for info: Dictionary in NPCDirector.get_all_bodies():
		if str(info.get("spot_id", "")) == spot_id and bool(info.get("hidden", false)) \
				and not bool(info.get("discovered", false)) and not is_disposed(str(info["npc_id"])):
			out.append(str(info["npc_id"]))
	return out


## ¿Destino útil para un cuerpo arrastrado? (el cuerpo le cede el foco).
static func is_body_target(item: Interactable) -> bool:
	if item.interact_type == T_CHUTE:
		return true
	if item is HidingSpot:
		return (item as HidingSpot).can_hide_body
	return FloorTravel.kind_of(item) == FloorLayout.TRANSIT_FREIGHT


# ─── Cuerpo ───────────────────────────────────────────────────

static func body_prompt(item: Interactable) -> String:
	var keeper: SecurityKeeper = keeper_of(item)
	if keeper != null and keeper.get_dragged() == str(item.data.get("npc_id", "")):
		return "SECOPS_PROMPT_BODY_DROP"
	return "SECOPS_PROMPT_BODY_DRAG"


static func use_body(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var keeper: SecurityKeeper = keeper_of(item)
	var npc_id: String = str(item.data.get("npc_id", ""))
	if keeper == null or npc_id.is_empty():
		return
	if keeper.get_dragged() == npc_id:
		keeper.drop_here()
		SecurityKit.toast(ctx, "SECOPS_BODY_DROPPED", [], ToastStack.KIND_INFO)
		SecurityKit.refresh_prompt(ctx, item, body_prompt(item))
		return
	if not await SecurityKit.act(player, CRIME_MOVED, SecurityKit.bf("cuerpos.segundos_coger")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	if keeper.start_drag(npc_id):
		SecurityKit.toast(ctx, "SECOPS_BODY_DRAGGING", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_WARN)
		SecurityKit.refresh_prompt(ctx, item, body_prompt(item))


# ─── Escondites ───────────────────────────────────────────────

static func spot_available(item: Interactable, player: Node) -> bool:
	var spot: HidingSpot = item as HidingSpot
	return spot == null or not dragging(player) or spot.can_hide_body


static func spot_prompt(item: Interactable) -> String:
	var spot: HidingSpot = item as HidingSpot
	if spot != null and is_player_hidden(item):
		return "SECOPS_PROMPT_COME_OUT"
	if spot != null and dragging(item):
		return "SECOPS_PROMPT_HIDE_BODY"
	if spot != null and spot_actions(spot, false).size() > 1:
		return "SECOPS_PROMPT_SPOT_MENU"
	return ""


## Acciones posibles en el escondite ahora (en orden de menú).
static func spot_actions(spot: HidingSpot, with_body: bool) -> Array[String]:
	var out: Array[String] = []
	if with_body:
		if spot.can_hide_body and bodies_in(spot.interact_id).size() < SecurityKit.bi("cuerpos.por_escondite"):
			out.append(A_HIDE_BODY)
		return out
	out.append(A_HIDE)
	if spot.capacity > 0 and not InventoryRules.find_spot(spot.room_id, spot.interact_id).is_empty():
		out.append(A_STASH)
	if not stashed_items(spot).is_empty():
		out.append(A_RETRIEVE)
	if not bodies_in(spot.interact_id).is_empty():
		out.append(A_PULL_BODY)
	return out


static func stashed_items(spot: HidingSpot) -> Array[String]:
	var out: Array[String] = []
	var stash: Dictionary = PlayerState.get_stashes().get(spot.interact_id, {})
	for record: Variant in stash.get("items", []):
		out.append(str((record as Dictionary).get("id", "")) if record is Dictionary else str(record))
	return out


static func is_player_hidden(node: Node) -> bool:
	var player: Node = SecurityKit.tree_of(node).get_first_node_in_group(Player.GROUP)
	return player != null and player.has_method("is_hiding") and bool(player.call("is_hiding"))


static func use_spot(spot: HidingSpot, player: Node, ctx: Dictionary) -> void:
	if spot == null:
		return
	if player.has_method("is_hiding") and bool(player.call("is_hiding")):
		player.call("set_hiding", false)
		SecurityKit.toast(ctx, "SECOPS_SPOT_OUT", [], ToastStack.KIND_INFO)
		SecurityKit.refresh_prompt(ctx, spot, spot_prompt(spot))
		return
	var with_body: bool = dragging(player)
	var actions: Array[String] = spot_actions(spot, with_body)
	if actions.is_empty():
		SecurityKit.toast(ctx, "SECOPS_SPOT_NO_ROOM" if with_body else "SECOPS_SPOT_NOTHING", [], ToastStack.KIND_WARN)
		return
	var action: String = actions[0]
	if actions.size() > 1:
		var options: Array = []
		for a: String in actions:
			options.append(ACTION_KEYS[a])
		options.append("UI_CANCEL")
		var i: int = await SecurityKit.choose(ctx, "SECOPS_SPOT_TITLE", "SECOPS_SPOT_BODY", options)
		if i < 0 or i >= actions.size():
			return
		action = actions[i]
	await spot_action(spot, player, ctx, action)


static func spot_action(spot: HidingSpot, player: Node, ctx: Dictionary, action: String) -> void:
	match action:
		A_HIDE:
			hide_player(spot, player, ctx)
		A_STASH:
			var ui: UIRoot = SecurityKit.ui(ctx)
			if ui != null:
				ui.open_inventory({"room_id": spot.room_id, "hide_spot_id": spot.interact_id})
		A_RETRIEVE:
			await retrieve(spot, ctx)
		A_HIDE_BODY:
			await hide_body(spot, player, ctx)
		A_PULL_BODY:
			await pull_body(spot, player, ctx)


## Se mete en el escondite y queda oculto hasta que se mueva (la percepción no ve dentro).
static func hide_player(spot: HidingSpot, player: Node, ctx: Dictionary) -> void:
	if not player.has_method("set_hiding"):
		return
	player.call("set_hiding", true)
	SecurityKit.toast(ctx, "SECOPS_SPOT_HIDDEN", [SecurityKit.room_name(spot.room_id)], ToastStack.KIND_INFO)
	SecurityKit.refresh_prompt(ctx, spot, "SECOPS_PROMPT_COME_OUT")


static func retrieve(spot: HidingSpot, ctx: Dictionary) -> void:
	var items: Array[String] = stashed_items(spot)
	var labels: Array[String] = []
	for id: String in items:
		labels.append(SecurityKit.item_name(id))
	var index: int = await SecurityKit.pick(ctx, TranslationServer.translate("SECOPS_SPOT_RETRIEVE"),
			TranslationServer.translate("SECOPS_SPOT_RETRIEVE_HINT"), labels)
	if index < 0:
		return
	var minutes: int = InventoryRules.retrieve_from_stash(spot.interact_id, items[index])
	if minutes == InventoryRules.RETRIEVE_FAILED:
		SecurityKit.toast(ctx, "SECOPS_INVENTORY_FULL", [], ToastStack.KIND_WARN)
		return
	SecurityKit.toast(ctx, "SECOPS_SPOT_RETRIEVED", [labels[index], minutes], ToastStack.KIND_GOOD)


static func hide_body(spot: HidingSpot, player: Node, ctx: Dictionary) -> bool:
	var keeper: SecurityKeeper = keeper_of(spot)
	if keeper == null or not keeper.is_dragging():
		return false
	if not await SecurityKit.act(player, CRIME_MOVED, SecurityKit.bf("cuerpos.segundos_esconder")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	var npc_id: String = keeper.release_body(spot.interact_id)
	settle(npc_id, spot.room_id, spot.interact_id, false)
	SecurityKit.toast(ctx, "SECOPS_BODY_HIDDEN", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_GOOD)
	return true


static func pull_body(spot: HidingSpot, player: Node, ctx: Dictionary) -> bool:
	var keeper: SecurityKeeper = keeper_of(spot)
	var inside: Array[String] = bodies_in(spot.interact_id)
	if keeper == null or inside.is_empty():
		return false
	if not await SecurityKit.act(player, CRIME_MOVED, SecurityKit.bf("cuerpos.segundos_coger")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	settle(inside[0], spot.room_id, "", false)
	keeper.spawn_body(inside[0], spot.global_position)
	keeper.start_drag(inside[0])
	SecurityKit.toast(ctx, "SECOPS_BODY_DRAGGING", [SecurityKit.npc_name(inside[0])], ToastStack.KIND_WARN)
	return true


# ─── Compactadora del muelle ──────────────────────────────────

static func chute_prompt(item: Interactable) -> String:
	return "SECOPS_PROMPT_CHUTE_BODY" if dragging(item) else ""


static func use_chute(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if dragging(player):
		await dispose_body(item, player, ctx)
		return
	var ui: UIRoot = SecurityKit.ui(ctx)
	if ui == null:
		return
	ui.open_inventory({"room_id": item.room_id, "hide_spot_id": item.interact_id})
	SecurityKit.toast(ctx, "SECOPS_CHUTE_HINT", [], ToastStack.KIND_INFO)


## Cuerpo a la compactadora: irreversible (confirmación), acto, ruido de la prensa y desaparece.
static func dispose_body(item: Interactable, player: Node, ctx: Dictionary) -> bool:
	var keeper: SecurityKeeper = keeper_of(item)
	var npc_id: String = keeper.get_dragged() if keeper != null else ""
	if npc_id.is_empty():
		return false
	if not await SecurityKit.confirm(ctx, "SECOPS_CHUTE_TITLE", "SECOPS_CHUTE_BODY_CONFIRM", "SECOPS_CHUTE_BODY_GO",
			[SecurityKit.npc_name(npc_id)]) or not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.act(player, CRIME_MOVED, SecurityKit.bf("cuerpos.segundos_triturar")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	keeper.release_body(item.interact_id)
	settle(npc_id, item.room_id, item.interact_id, true)
	SecurityKit.noise(item.global_position, SecurityKit.bf("cuerpos.radio_ruido_triturar"), NOISE_CHUTE)
	SecurityKit.toast(ctx, "SECOPS_CHUTE_BODY_DONE", [SecurityKit.npc_name(npc_id)], ToastStack.KIND_GOOD)
	return true
