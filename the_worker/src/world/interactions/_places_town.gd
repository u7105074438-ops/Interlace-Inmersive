# _places_town.gd — La ciudad (§4.2-§4.3, §22.16): mostradores de tiendas (comida, pasamontañas, traje ejecutivo, precio real en la tienda insignia), autobús entre casa, sede y viviendas, comisaría y puertas de las viviendas (allanamiento con NightOps).
# PROPIETARIO DE: nada (compras y trayecto de HomeCycle; la operación nocturna de NightOps; el traje, bandera de PlacesKeeper).
# ESCUCHA: nada.
class_name PlacesTown
extends RefCounted

## · "shop_counter": lo que vende el mostrador (HomeCycle.get_shop_items, precios de balance
##   economia.* vía price_keys) → HomeCycle.buy (cobra hogar.minutos_compra). Lo caro (desde
##   lugares.tienda.confirmar_desde) se confirma. El traje ejecutivo quita la penalización diaria de
##   reputación del estatus (PlacesKeeper.mark_suit_owned). Un mostrador price_reference (tienda
##   insignia) solo informa del precio real del par.
## · "bus_stop"/"transport_stop": tarifa lugares.autobus.tarifa y lugares.autobus.minutos. Destinos:
##   la sede (dentro de recepción, junto a su puerta; de noche el edificio está cerrado y te deja en
##   la calle), casa (dentro del piso), la otra parada (leads_to/destinations) y, desde la parada de
##   transporte, las viviendas cuyos residentes conoces (NightOps.visit_home: ese trayecto es el de
##   la operación y te deja en la calle ante su puerta).
## · "house_door" (PlacesKeeper, en la calle ante cada vivienda): sin operación, elegir a quién
##   visitar (domicilios conocidos) → NightOps.visit_home; con ella, pasamontañas (se ofrece
##   ponérselo) → entrada (illegitimate_entries: forzar la cerradura o la ventana) → confirmación →
##   acto visible "burglary" → NightOps.break_in → dentro. Salir andando cierra la operación.
## · "police_desk": nada útil; entregarse es un chiste (confirmado): lo corporativo es civil.

const T_SHOP := "shop_counter"
const T_BUS := "bus_stop"
const T_STOP := "transport_stop"
const T_POLICE := "police_desk"
const T_HOUSE := "house_door"
const TYPES: Array[String] = [T_SHOP, T_BUS, T_STOP, T_POLICE, T_HOUSE]
const K_PRICE_REFERENCE := "price_reference"
const K_LEADS_TO := "leads_to"
const K_DESTINATIONS := "destinations"
const K_HOUSE := "house"
const KIND_WORK := "work"
const KIND_HOME := "home"
const KIND_STOP := "stop"
const KIND_HOUSE := "house"
const NIGHT_BAND := "night"
const FARE_REASON := "bus"
const BUS_ICON := "door"
const ENTRY_FORMAT := "PLACES_ENTRY_%s"
const CRIME_BURGLARY := "burglary"
const SFX_ALARM := "alarm_exterior"
const B_SUIT := "lugares.traje.objeto"
const B_CONFIRM_PRICE := "lugares.tienda.confirmar_desde"
const B_FARE := "lugares.autobus.tarifa"
const B_BUS_MINUTES := "lugares.autobus.minutos"
const B_ENTRANCE := "viaje.trayecto.entrada_edificio"
const B_STREET := "viaje.trayecto.sala_calle"
const B_HOME := "hogar.sala_domicilio"
const B_EXTERIOR := "mundo.planta_exterior"
const B_ENTRY_MINUTES := "noche.minutos_entrada"
const B_TICKET_MIN := "lugares.comisaria.turno_min"
const B_TICKET_MAX := "lugares.comisaria.turno_max"
const MAX_RESIDENTS := 4


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_SHOP:
			await shop(item, ctx)
		T_BUS, T_STOP:
			await bus(item, ctx)
		T_POLICE:
			await police_desk(ctx)
		T_HOUSE:
			await house_door(item, player, ctx)


static func prompt_key(item: Interactable) -> String:
	if item.interact_type == T_HOUSE:
		var ops: NightOps = night_ops(null)
		var casing: bool = ops != null and ops.is_active() \
				and PlacesKit.base_room(str(ops.get_operation().get("house", ""))) == str(item.data.get(K_HOUSE, ""))
		return "UI_INTERACT_HOUSE_BREAK_IN" if casing else "UI_INTERACT_HOUSE_DOOR"
	if item.interact_type == T_STOP:
		return "UI_INTERACT_BUS_STOP"
	return ""


static func home_cycle(ctx: Dictionary) -> HomeCycle:
	return PlacesKit.sim(ctx, "HomeCycle", HomeCycle.GROUP) as HomeCycle


static func night_ops(ctx: Variant) -> NightOps:
	return PlacesKit.sim(ctx if ctx is Dictionary else {}, "NightOps", NightOps.GROUP) as NightOps


# ─── Tiendas ──────────────────────────────────────────────────

static func shop(item: Interactable, ctx: Dictionary) -> void:
	var home: HomeCycle = home_cycle(ctx)
	if home == null:
		return
	if bool(item.data.get(K_PRICE_REFERENCE, false)):
		PlacesKit.spend_minutes("precios")
		var price: float = float(Company.get_fundamentals().get("avg_price", 0.0))
		PlacesKit.say(ctx, "PLACES_STORE_PRICE", [roundi(price)])
		return
	var goods: Array[Dictionary] = home.get_shop_items(item.room_id)
	var options: Array = []
	for entry: Dictionary in goods:
		options.append({"text_key": "PLACES_SHOP_ITEM", "args": [PlacesKit.item_name(str(entry["item_id"])), int(entry["price"])],
				"disabled": not PlayerState.can_afford(int(entry["price"]))})
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_SHOP_TITLE", "PLACES_SHOP_BODY", options, [PlayerState.get_money()])
	if index >= 0 and index < goods.size():
		await buy(home, goods[index], item.room_id, ctx)


static func buy(home: HomeCycle, entry: Dictionary, room_id: String, ctx: Dictionary) -> void:
	var item_id: String = str(entry["item_id"])
	var price: int = int(entry["price"])
	var name: String = PlacesKit.item_name(item_id)
	if price >= Database.get_balance_int(B_CONFIRM_PRICE):
		if not await PlacesKit.confirm(ctx, "PLACES_SHOP_TITLE", "PLACES_SHOP_CONFIRM", "PLACES_SHOP_PAY", [name, price]):
			return
	var result: String = home.buy(item_id, room_id)
	if result != HomeCycle.OK:
		PlacesKit.refuse(ctx, HomeCycle.reason_key(result))
		return
	PlacesKit.good(ctx, "PLACES_SHOP_BOUGHT", [name, price], PlacesKit.SFX_CASH)
	if item_id == str(Database.get_balance(B_SUIT)):
		PlacesKeeper.mark_suit_owned()
		PlacesKit.good(ctx, "PLACES_SUIT_BOUGHT")
	elif item_id == Disguise.balaclava_id():
		PlacesKit.say(ctx, "PLACES_BALACLAVA_BOUGHT", [], ToastStack.KIND_WARN)


# ─── Autobús ──────────────────────────────────────────────────

static func bus(item: Interactable, ctx: Dictionary) -> void:
	var dests: Array[Dictionary] = bus_destinations(item)
	var options: Array = []
	for dest: Dictionary in dests:
		options.append(dest_option(dest))
	options.append("PLACES_CLOSE")
	var args: Array = [Database.get_balance_int(B_BUS_MINUTES), Database.get_balance_int(B_FARE)]
	var index: int = await PlacesKit.choose(ctx, "PLACES_BUS_TITLE", "PLACES_BUS_BODY", options, args)
	if index >= 0 and index < dests.size():
		await ride(ctx, dests[index])


## Destinos de la parada: sede, casa, la otra parada y viviendas conocidas (desde la de transporte).
static func bus_destinations(item: Interactable) -> Array[Dictionary]:
	var here: String = PlacesKit.base_room(item.room_id)
	var out: Array[Dictionary] = [{"kind": KIND_WORK, "room": str(Database.get_balance(B_ENTRANCE))},
			{"kind": KIND_HOME, "room": str(Database.get_balance(B_HOME))}]
	var rooms: Array[String] = PlacesKit.strings(item.data.get(K_LEADS_TO, []))
	rooms.append_array(PlacesKit.strings(item.data.get(K_DESTINATIONS, [])))
	for room_id: String in rooms:
		if NightOps.get_house_type(room_id).is_empty():
			if room_id != here:
				out.append({"kind": KIND_STOP, "room": room_id})
			continue
		for npc_id: String in known_residents(room_id):
			out.append({"kind": KIND_HOUSE, "room": room_id, "npc": npc_id})
	return out


static func dest_option(dest: Dictionary) -> Dictionary:
	match str(dest["kind"]):
		KIND_WORK:
			return {"text_key": "PLACES_BUS_TO_WORK", "disabled": GameClock.get_current_band() == NIGHT_BAND}
		KIND_HOME:
			return {"text_key": "PLACES_BUS_TO_HOME"}
		KIND_HOUSE:
			return {"text_key": "PLACES_BUS_TO_HOUSE", "args": [PlacesKit.npc_name(str(dest["npc"]))]}
	return {"text_key": "PLACES_BUS_TO_STOP", "args": [PlacesKit.room_name(str(dest["room"]))]}


## Residentes de esa vivienda cuyo domicilio conoce el jugador.
static func known_residents(house: String) -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if out.size() >= MAX_RESIDENTS:
			break
		if NPCDirector.is_active(npc.id) and PlacesKit.base_room(NPCDirector.get_home_address(npc.id)) == house \
				and NightOps.knows_home_address(npc.id):
			out.append(npc.id)
	return out


static func ride(ctx: Dictionary, dest: Dictionary) -> void:
	var kind: String = str(dest["kind"])
	if kind == KIND_HOUSE:
		await ride_to_house(ctx, str(dest["npc"]), str(dest["room"]))
		return
	var fare: int = Database.get_balance_int(B_FARE)
	if not PlayerState.spend_money(fare, FARE_REASON):
		PlacesKit.refuse(ctx, "PLACES_BUS_NO_MONEY", [fare])
		return
	var keeper: PlacesKeeper = PlacesKeeper.ensure(PlacesKit.tree_of(PlacesKit.ui(ctx)))
	if keeper == null:
		return
	var minutes: int = Database.get_balance_int(B_BUS_MINUTES)
	await keeper.fade_in(BUS_ICON, UITheme.trf("PLACES_BUS_CAPTION", [minutes]))
	GameClock.advance_minutes(float(minutes))
	var arrived: String = arrive(keeper, kind, str(dest["room"]))
	await keeper.fade_out()
	PlacesKit.say(ctx, arrived, [minutes, fare])


## Coloca al jugador en el destino; devuelve la clave del aviso de llegada.
static func arrive(keeper: PlacesKeeper, kind: String, room_id: String) -> String:
	var game: GameRoot = keeper.game()
	match kind:
		KIND_WORK:
			if GameClock.get_current_band() == NIGHT_BAND:
				game.travel.place_outside_building()
				return "PLACES_BUS_BUILDING_CLOSED"
			game.travel.teleport_to_room(room_id)
			game.travel.teleport(game.streamer.get_current_floor(), keeper.entrance_point())
		KIND_HOME:
			game.travel.teleport_to_room(room_id)
			game.travel.teleport(game.streamer.get_current_floor(), game.travel.home_door_point())
		_:
			game.travel.teleport_to_room(room_id)
			game.travel.teleport(game.streamer.get_current_floor(), keeper.stop_point(room_id))
	return "PLACES_BUS_ARRIVED"


## Desde la parada de transporte: el trayecto hasta la vivienda es el de NightOps.visit_home.
static func ride_to_house(ctx: Dictionary, npc_id: String, house: String) -> void:
	var ops: NightOps = night_ops(ctx)
	var keeper: PlacesKeeper = PlacesKeeper.ensure(PlacesKit.tree_of(PlacesKit.ui(ctx)))
	if ops == null or keeper == null:
		return
	var reason: String = ops.can_visit(npc_id)
	if not reason.is_empty():
		PlacesKit.refuse(ctx, NightOps.reason_key(reason))
		return
	if not PlayerState.spend_money(Database.get_balance_int(B_FARE), FARE_REASON):
		PlacesKit.refuse(ctx, "PLACES_BUS_NO_MONEY", [Database.get_balance_int(B_FARE)])
		return
	await keeper.fade_in(BUS_ICON, UITheme.trf("PLACES_HOUSE_CAPTION", [PlacesKit.npc_name(npc_id)]))
	var result: Dictionary = ops.visit_home(npc_id)
	if bool(result.get("ok", false)):
		keeper.place_at_house(house)
	await keeper.fade_out()
	announce_visit(ctx, npc_id, result)


static func announce_visit(ctx: Dictionary, npc_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, NightOps.reason_key(str(result.get("reason", ""))))
		return
	var key: String = "PLACES_HOUSE_RESIDENT_HOME" if bool(result.get("resident_home", false)) else "PLACES_HOUSE_RESIDENT_OUT"
	PlacesKit.say(ctx, key, [PlacesKit.npc_name(npc_id), int(result.get("minutes", 0))], ToastStack.KIND_WARN)


# ─── Viviendas (NightOps) ─────────────────────────────────────

static func house_door(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var ops: NightOps = night_ops(ctx)
	var house: String = str(item.data.get(K_HOUSE, ""))
	if ops == null or house.is_empty():
		return
	if ops.is_active() and PlacesKit.base_room(str(ops.get_operation().get("house", ""))) != house:
		PlacesKit.refuse(ctx, "PLACES_HOUSE_OTHER_JOB")
		return
	if not ops.is_active():
		var npc_id: String = await pick_resident(ctx, house)
		if npc_id.is_empty():
			return
		var result: Dictionary = ops.visit_home(npc_id)
		announce_visit(ctx, npc_id, result)
		if not bool(result.get("ok", false)):
			return
	await break_in(player, ctx, ops, house)


static func pick_resident(ctx: Dictionary, house: String) -> String:
	var residents: Array[String] = known_residents(house)
	if residents.is_empty():
		PlacesKit.refuse(ctx, "PLACES_HOUSE_UNKNOWN")
		return ""
	var options: Array = []
	for npc_id: String in residents:
		options.append({"text_key": "PLACES_HOUSE_WHOSE", "args": [PlacesKit.npc_name(npc_id)]})
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_HOUSE_TITLE", "PLACES_HOUSE_PICK_BODY", options)
	return residents[index] if index >= 0 and index < residents.size() else ""


## Pasamontañas → entrada → confirmación → acto visible → NightOps.break_in → dentro.
static func break_in(player: Node, ctx: Dictionary, ops: NightOps, house: String) -> void:
	if not await ensure_mask(ctx):
		return
	var method: String = await pick_entry(ctx, house)
	if method.is_empty():
		return
	if not await PlacesKit.run_act(ctx, player, CRIME_BURGLARY, "allanamiento"):
		return
	var result: Dictionary = ops.break_in(method)
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, NightOps.reason_key(str(result.get("reason", ""))))
		return
	var keeper: PlacesKeeper = PlacesKeeper.ensure(PlacesKit.tree_of(player))
	if keeper != null:
		keeper.place_in_house(house)
	PlacesKit.say(ctx, "PLACES_HOUSE_INSIDE", [], ToastStack.KIND_WARN)
	if bool(result.get("alarm", false)):
		PlacesKit.bad(ctx, "PLACES_HOUSE_ALARM")
		PlacesKit.sfx(player, SFX_ALARM)
	if not (result.get("witnesses", []) as Array).is_empty():
		PlacesKit.bad(ctx, "PLACES_HOUSE_SEEN", [(result["witnesses"] as Array).size()])


## Allanar exige el pasamontañas puesto: se ofrece ponérselo si se lleva. true = adelante.
static func ensure_mask(ctx: Dictionary) -> bool:
	if not NightOps.needs_balaclava():
		return true
	var mask: String = Disguise.balaclava_id()
	if not PlayerState.is_carrying(mask):
		PlacesKit.refuse(ctx, NightOps.reason_key(NightOps.ERR_NO_BALACLAVA))
		return false
	if not await PlacesKit.confirm(ctx, "PLACES_HOUSE_TITLE", "PLACES_HOUSE_MASK_BODY", "PLACES_HOUSE_MASK_GO"):
		return false
	Disguise.wear(mask)
	PlacesKit.say(ctx, "PLACES_HOUSE_MASK_ON")
	return true


static func pick_entry(ctx: Dictionary, house: String) -> String:
	var room: RoomData = Database.get_room(house)
	var methods: Array[String] = PlacesKit.strings(room.illegitimate_entries if room != null else [])
	var minutes: Variant = Database.get_balance(B_ENTRY_MINUTES)
	var options: Array = []
	for method: String in methods:
		var m: int = int((minutes as Dictionary).get(method, 0)) if minutes is Dictionary else 0
		options.append({"text_key": ENTRY_FORMAT % method.to_upper(), "args": [m], "danger": true})
	options.append("PLACES_NOT_NOW")
	var index: int = await PlacesKit.choose(ctx, "PLACES_HOUSE_TITLE", "PLACES_HOUSE_ENTRY_BODY", options)
	return methods[index] if index >= 0 and index < methods.size() else ""


## El jugador sale andando de la vivienda allanada: la operación se cierra (burglary).
static func finish_burglary(ctx: Dictionary, ops: NightOps) -> void:
	var result: Dictionary = ops.leave_house()
	if not bool(result.get("ok", false)):
		return
	PlacesKit.say(ctx, "PLACES_HOUSE_LEFT", [int(result.get("value", 0))], ToastStack.KIND_INFO, PlacesKit.SFX_CASH)
	if bool(result.get("identified", false)):
		PlacesKit.bad(ctx, "PLACES_HOUSE_IDENTIFIED")


# ─── Comisaría ────────────────────────────────────────────────

static func police_desk(ctx: Dictionary) -> void:
	var police: Police = PlacesKit.sim(ctx, "Police", Police.GROUP) as Police
	var body: String = "PLACES_POLICE_BODY_CHASE" if police != null and police.is_active() else "PLACES_POLICE_BODY"
	var options: Array = ["PLACES_POLICE_ASK", {"text_key": "PLACES_POLICE_CONFESS", "danger": true}, "PLACES_CLOSE"]
	var index: int = await PlacesKit.choose(ctx, "PLACES_POLICE_TITLE", body, options)
	if index == 0:
		PlacesKit.spend_minutes("comisaria")
		PlacesKit.say(ctx, "PLACES_POLICE_DIRECTIONS")
	elif index == 1:
		if await PlacesKit.confirm(ctx, "PLACES_POLICE_TITLE", "PLACES_POLICE_CONFESS_BODY", "PLACES_POLICE_CONFESS_GO"):
			PlacesKit.spend_minutes("comisaria")
			var ticket: int = PlacesKit.rng(T_POLICE).randi_range(Database.get_balance_int(B_TICKET_MIN),
					Database.get_balance_int(B_TICKET_MAX))
			PlacesKit.say(ctx, "PLACES_POLICE_CONFESSED", [ticket])
