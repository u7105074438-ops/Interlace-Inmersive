# _office_break.gd — La vida de pasillo del módulo de oficina: café y fuente de agua (charla y contactos), escuchas, máquina expendedora, neveras, cocina y mostradores de comida.
# PROPIETARIO DE: nada (estático; «ya hoy» con banderas "office.*"; la comida y los gastos son de HomeCycle/PlayerState, los contactos de PlayerState, el afecto de NPCDirector).
# ESCUCHA: nada.
class_name OfficeBreak
extends RefCounted

## · Café / fuente de agua: legal y rápido (oficina.minutos.cafe). Si hay alguien cerca en la sala
##   (oficina.cafe.radio_charla_celdas), un momento de charla: +afecto (una vez al día por persona)
##   y su número (PlayerState.add_contact(id, "proximity"), §13.5).
## · Escucha (§11.1 vía «escucha», §7.7): si en la sala alguien está contando su idea, se oye
##   (IdeaPool.acquire(id, "overhear"): el dueño sabe que estabas); si no, lo que mide el punto
##   (descontento de fábrica, confianza de inversores) o un rumor de alguien de la sala (BeliefNet).
## · Máquina expendedora y mostrador de pago: compra al valor del objeto (PlayerState.spend_money
##   "food"). Comida gratis (bufé ejecutivo, bar de inversores): legal si la sala no te está vetada;
##   si lo está, es un theft_small.
## · Neveras y cocina ajenas: acto theft_small + HomeCycle.steal_food(sala) (§22.4, §22.8: elimina
##   el gasto de esa comida). La nevera de tu piso: comer (HomeCycle.eat) el desayuno o la cena.

const B_CHAT_RADIUS := "oficina.cafe.radio_charla_celdas"
const B_AFFECTION := "oficina.cafe.afecto"
const B_CHAT_LINES := "oficina.cafe.frases"
const B_FOOD_LUXURY := "oficina.comida.objeto_lujo"
const B_FOOD_BASIC := "oficina.comida.objeto_basico"
const B_VENDING := "oficina.comida.objeto_maquina"
const B_MIDDAY := "oficina.comida.hora_cambio_comida"
const CONTACT_PROXIMITY := "proximity"
const TELL := "tell_colleague"
const METHOD_OVERHEAR := "overhear"
const CRIME_THEFT := "theft_small"
const OWNER_PLAYER := "player"
const QUALITY_LUXURY := "luxury"
const MEAL_BREAKFAST := "breakfast"
const MEAL_DINNER := "dinner"
const MEASURES_DISCONTENT := "discontent"
const TARGETS_INVESTORS := "investors"
const CHAT_LINE_FORMAT := "OFFICE_CHAT_LINE_%d"
const REASON_FOOD := "food"


# ─── Café y fuente ────────────────────────────────────────────

static func use_coffee(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var partner: String = chat_partner(item, player, ctx)
	OfficeKit.spend_minutes("cafe")
	if partner.is_empty():
		OfficeKit.play(player, "check_watch")
		OfficeKit.good(ctx, "OFFICE_COFFEE_ALONE")
		return
	OfficeKit.play(player, "chat")
	var name: String = OfficeKit.npc_name(partner)
	var line: int = OfficeKit.rng("chat." + partner).randi_range(1, maxi(Database.get_balance_int(B_CHAT_LINES), 1))
	var key: String = "coffee." + partner
	if not OfficeKit.used_today(key):
		NPCDirector.add_affection(partner, Database.get_balance_int(B_AFFECTION))
		OfficeKit.mark_today(key)
	var text: String = OfficeKit.tr_key(CHAT_LINE_FORMAT % line) % name
	if PlayerState.add_contact(partner, CONTACT_PROXIMITY):
		OfficeKit.good(ctx, "OFFICE_COFFEE_CONTACT", [text, name], OfficeKit.SFX_CHAT)
		return
	OfficeKit.good(ctx, "OFFICE_COFFEE_CHAT", [text], OfficeKit.SFX_CHAT)


## El personaje activo más cercano en la misma sala y dentro del radio de charla ("" si nadie).
static func chat_partner(item: Interactable, player: Node, ctx: Dictionary) -> String:
	var game: GameRoot = OfficeKit.root(ctx)
	if game == null or game.npc_layer == null:
		return ""
	var at: Vector2 = OfficeKit.pos_of(player) if player is Node2D else item.global_position
	var radius: float = Database.get_balance_float(B_CHAT_RADIUS) * RoomBuilder.cell_px()
	var best: String = ""
	var best_d: float = radius
	for node: NPCNode in game.npc_layer.get_nodes():
		var d: float = node.global_position.distance_to(at)
		if d <= best_d and NPCDirector.is_active(node.npc_id) and OfficeKit.is_present(node.npc_id, item.room_id):
			best_d = d
			best = node.npc_id
	return best


# ─── Escucha ──────────────────────────────────────────────────

static func use_eavesdrop(item: Interactable, player: Node, ctx: Dictionary) -> void:
	OfficeKit.play(player, "phone")
	OfficeKit.spend_minutes("escucha")
	var overheard: String = overhear_idea(item.room_id)
	if not overheard.is_empty():
		var idea: Idea = IdeaPool.get_idea(overheard)
		OfficeKit.note("ideas", "OFFICE_NOTE_OVERHEARD", [OfficeKit.npc_name(idea.owner)])
		OfficeKit.good(ctx, "OFFICE_EAVESDROP_IDEA", [OfficeKit.npc_name(idea.owner), OfficeKit.tr_key(idea.text_key)])
		return
	var lines: Array[String] = eavesdrop_lines(item)
	if lines.is_empty():
		OfficeKit.say(ctx, "OFFICE_EAVESDROP_NOTHING")
		return
	OfficeInfo.note_lines(lines)
	await OfficeKit.show_lines(ctx, "OFFICE_EAVESDROP_TITLE", lines)


## Idea que alguien de la sala está contando ahora: se adquiere por escucha. Devuelve su id o "".
static func overhear_idea(room_id: String) -> String:
	for signal_entry: Dictionary in IdeaPool.get_signalling_npcs():
		var idea_id: String = str(signal_entry.get("idea_id", ""))
		var owner: String = str(signal_entry.get("npc_id", ""))
		if str(signal_entry.get("behaviour", "")) != TELL or not OfficeKit.is_present(owner, room_id):
			continue
		if IdeaPool.acquire(idea_id, METHOD_OVERHEAR):
			return idea_id
	return ""


static func eavesdrop_lines(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	if str(item.data.get("measures", "")) == MEASURES_DISCONTENT:
		out.append(OfficeKit.tr_key("OFFICE_EAVESDROP_DISCONTENT") % [Company.get_discontent(), Company.get_strike_threshold()])
	if str(item.data.get("targets", "")) == TARGETS_INVESTORS:
		out.append_array(OfficeInfo.investor_lines())
	var gossip: String = OfficeInfo.gossip_line(item.room_id, "gossip." + item.interact_id)
	if not gossip.is_empty():
		out.append(gossip)
	return out


# ─── Comprar ──────────────────────────────────────────────────

static func use_vending(item: Interactable, _player: Node, ctx: Dictionary) -> void:
	var sells: Array = item.data.get("sells", [])
	var item_id: String = str(sells[0]) if not sells.is_empty() else str(Database.get_balance(B_VENDING))
	if sells.size() > 1:
		var labels: Array = []
		for raw: Variant in sells:
			labels.append({"text_key": "OFFICE_BUY_ITEM", "args": [OfficeKit.item_name(str(raw)), OfficeKit.item_value(str(raw))]})
		labels.append("OFFICE_CLOSE")
		var index: int = await OfficeKit.choose(ctx, "OFFICE_VENDING_TITLE", "OFFICE_VENDING_BODY", labels)
		if index < 0 or index >= sells.size():
			return
		item_id = str(sells[index])
	buy(item_id, "maquina", ctx)


## Compra una unidad al valor del objeto. true si se compró.
static func buy(item_id: String, minutes_kind: String, ctx: Dictionary) -> bool:
	var price: int = OfficeKit.item_value(item_id)
	if not OfficeKit.can_take(item_id):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(item_id)])
		return false
	if not PlayerState.spend_money(price, REASON_FOOD):
		OfficeKit.refuse(ctx, "OFFICE_NO_MONEY", [price])
		return false
	PlayerState.add_item(item_id)
	OfficeKit.spend_minutes(minutes_kind)
	OfficeKit.good(ctx, "OFFICE_BOUGHT", [OfficeKit.item_name(item_id), price], OfficeKit.SFX_CASH)
	return true


# ─── Comida ───────────────────────────────────────────────────

static func is_free_food(item: Interactable) -> bool:
	return bool(item.data.get("free", false))


static func free_food_item(item: Interactable) -> String:
	return str(Database.get_balance(B_FOOD_LUXURY if str(item.data.get("quality", "")) == QUALITY_LUXURY else B_FOOD_BASIC))


static func use_lunch_counter(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if is_free_food(item):
		await take_free_food(item, player, ctx)
		return
	var sells: Array = item.data.get("sells", [])
	buy(str(sells[0]) if not sells.is_empty() else str(Database.get_balance(B_FOOD_BASIC)), "comida", ctx)


static func use_kitchen(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if is_free_food(item):
		await take_free_food(item, player, ctx)
		return
	await steal_food(item, player, ctx)


static func use_fridge(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if str(item.data.get("owner", "")) == OWNER_PLAYER:
		eat_at_home(ctx)
		return
	await steal_food(item, player, ctx)


## Comida gratis del bufé: legal si puedes estar en la sala; si no, theft_small.
static func take_free_food(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var key: String = "free_food." + item.interact_id
	var item_id: String = free_food_item(item)
	if OfficeKit.used_today(key):
		OfficeKit.say(ctx, "OFFICE_FOOD_DONE_TODAY")
		return
	if not OfficeKit.can_take(item_id):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(item_id)])
		return
	var room: String = item.room_id
	var forbidden: bool = BeliefNet.is_room_forbidden_for_player(room)
	if forbidden and not await OfficeKit.run_act(ctx, player, CRIME_THEFT, "comida"):
		return
	PlayerState.add_item(item_id)
	OfficeKit.mark_today(key)
	if forbidden:
		OfficeKit.commit(CRIME_THEFT, room, {"value": OfficeKit.item_value(item_id), "item_id": item_id, "food": true})
	OfficeKit.spend_minutes("comida_libre")
	OfficeKit.good(ctx, "OFFICE_FOOD_FREE", [OfficeKit.item_name(item_id)])


## Nevera o cocina ajena: acto y HomeCycle.steal_food (emite el theft_small de comida).
static func steal_food(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var home: HomeCycle = OfficeKit.sim(ctx, "HomeCycle", HomeCycle.GROUP) as HomeCycle
	var room: String = item.room_id
	if home == null:
		OfficeKit.say(ctx, "INTERACT_NOTHING_USEFUL")
		return
	if PlayerState.get_free_slots() <= 0 and not PlayerState.is_carrying(str(Database.get_balance(B_FOOD_BASIC))):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(str(Database.get_balance(B_FOOD_BASIC)))])
		return
	if not await OfficeKit.run_act(ctx, player, CRIME_THEFT, "comida"):
		return
	var result: String = home.steal_food(room)
	if result != HomeCycle.OK:
		OfficeKit.refuse(ctx, HomeCycle.reason_key(result))
		return
	OfficeKit.good(ctx, "OFFICE_FOOD_STOLEN")


## La nevera de casa: el desayuno por la mañana, la cena después (HomeCycle.eat).
static func eat_at_home(ctx: Dictionary) -> void:
	var home: HomeCycle = OfficeKit.sim(ctx, "HomeCycle", HomeCycle.GROUP) as HomeCycle
	if home == null:
		OfficeKit.say(ctx, "INTERACT_NOTHING_USEFUL")
		return
	var meal: String = MEAL_BREAKFAST if GameClock.get_hour() < Database.get_balance_int(B_MIDDAY) else MEAL_DINNER
	if home.has_eaten(meal):
		OfficeKit.say(ctx, "OFFICE_MEAL_ALREADY", [OfficeKit.tr_key("OFFICE_MEAL_" + meal.to_upper())])
		return
	var result: Dictionary = home.eat(meal)
	if not bool(result.get("eaten", false)):
		OfficeKit.refuse(ctx, "OFFICE_MEAL_NONE")
		return
	OfficeKit.good(ctx, "OFFICE_MEAL_EATEN", [OfficeKit.tr_key("OFFICE_MEAL_" + meal.to_upper()), int(result.get("cost", 0))])
