# _office_desk.gd — La mesa y las pantallas del módulo de oficina: mesa propia (ordenador, llaves y estampa, escondite), mesas ajenas, ordenadores de otros, terminales de sala, pizarras y lectores de tarjeta.
# PROPIETARIO DE: nada (estático; lo que se esconde lo guarda PlayerState, la sesión de ordenador es de StellarOS).
# ESCUCHA: nada.
class_name OfficeDesk
extends RefCounted

## · Mesa propia (§22.8 «escritorio propio: llaves, estampa, ordenador»; apaño de _default.gd
##   conservado): E abre un menú corto con el ordenador en primer lugar (Intro/1 = ordenador; la
##   tecla C lo abre directamente, UIRoot). Si la mesa guarda herramientas del puesto (data.contains ∩
##   occupation.tools) se pueden llevar encima o devolver: llevarlas ocupa hueco pero se conservan
##   si cambias de puesto (y entonces sí son comprometedoras, PlayerState). Si hay un escondite
##   bajo la mesa con capacidad (hiding_spots under_desk de la sala) se puede esconder algo
##   (inventario con ese escondite) o recuperar lo escondido (InventoryRules.retrieve_from_stash).
##   Sin más opciones que el ordenador, E lo abre sin menú.
## · Mesa ajena: «No es tu mesa» (apaño conservado).
## · npc_computer: con su dueño en la sala, aviso con su nombre; sin él, StellarOS.open_intrusion
##   (sesión de invitado: StellarOS pone al jugador en begin_act("file_copied") mientras dura y
##   FILES emite el delito solo si copia algo). Si alguien mira, se pregunta antes.
## · computer: con data.contains y sin personal que lo atienda → intrusión sin dueño; si no, una
##   ficha de lectura según data.shows (planificación, visitas, crisis, quejas...).
## · whiteboard: orden del día de Aurora. card_reader: DoorAccess.swipe de la puerta con lector
##   más cercana (el paso se registra al cruzarla).

const DESK_TYPE := "desk"
const UNDER_DESK := "under_desk"
const OWN_DESK_PROMPT := "UI_INTERACT_OWN_DESK"
const OWN_DESK_MENU_PROMPT := "UI_INTERACT_OWN_DESK_MENU"
const EXAMINE_PROMPT := "UI_INTERACT_EXAMINE"
const APP_PERSONNEL := "personnel"
const SHOWS_KEY_FORMAT := "OFFICE_SHOWS_%s"
const SHOWS_FLOOR_PLANNING := "floor_planning"
const SHOWS_VISITOR_LOG := "visitor_log"
const SHOWS_CRISIS := "crisis_dashboard"
const SFX_CARD := "card_beep"
const SFX_DENIED := "card_denied"
const SFX_CHAIR := "chair_creak"
## Un escondite «bajo la mesa» está en la celda de la mesa o en una contigua (geometría, no ajuste).
const STASH_REACH_CELLS := 1.5
const OPT_COMPUTER := "computer"
const OPT_TAKE_TOOLS := "take_tools"
const OPT_RETURN_TOOLS := "return_tools"
const OPT_HIDE := "hide"
const OPT_RETRIEVE := "retrieve"


# ─── Mesa ─────────────────────────────────────────────────────

static func is_own_desk(item: Interactable) -> bool:
	return OfficeKit.is_own_room(item.room_id)


## Indicación honesta: «Sentarse al ordenador» si E lo abre directamente; «Tu mesa» si abre el menú.
static func desk_prompt(item: Interactable) -> String:
	if not is_own_desk(item):
		return EXAMINE_PROMPT
	return OWN_DESK_PROMPT if desk_options(item).size() == 1 else OWN_DESK_MENU_PROMPT


static func use_desk(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not is_own_desk(item):
		OfficeKit.refuse(ctx, "INTERACT_NOT_YOUR_DESK")
		return
	var options: Array[String] = desk_options(item)
	if options.size() == 1:
		_open_computer(ctx)
		return
	var labels: Array = []
	for option: String in options:
		labels.append(_desk_label(option, item))
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_DESK_TITLE", "OFFICE_DESK_BODY", labels)
	if index < 0 or index >= options.size():
		return
	await _run_desk_option(options[index], item, player, ctx)


## Opciones de la mesa propia (el ordenador siempre primero).
static func desk_options(item: Interactable) -> Array[String]:
	var out: Array[String] = [OPT_COMPUTER]
	var tools: Array[String] = desk_tools(item)
	if not tools.is_empty():
		out.append(OPT_RETURN_TOOLS if carried_tools(item).size() == tools.size() else OPT_TAKE_TOOLS)
	var spot: Dictionary = stash_spot(item)
	if not spot.is_empty():
		out.append(OPT_HIDE)
		if not stashed_items(str(spot["id"])).is_empty():
			out.append(OPT_RETRIEVE)
	return out


static func _desk_label(option: String, item: Interactable) -> Variant:
	match option:
		OPT_TAKE_TOOLS:
			return {"text_key": "OFFICE_DESK_TAKE_TOOLS", "args": [_tool_names(desk_tools(item))]}
		OPT_RETURN_TOOLS:
			return {"text_key": "OFFICE_DESK_RETURN_TOOLS", "args": [_tool_names(desk_tools(item))]}
		OPT_HIDE:
			return "OFFICE_DESK_HIDE"
		OPT_RETRIEVE:
			return {"text_key": "OFFICE_DESK_RETRIEVE", "args": [stashed_items(str(stash_spot(item)["id"])).size()]}
	return "OFFICE_DESK_COMPUTER"


static func _run_desk_option(option: String, item: Interactable, player: Node, ctx: Dictionary) -> void:
	match option:
		OPT_COMPUTER:
			_open_computer(ctx)
		OPT_TAKE_TOOLS:
			take_tools(item, ctx)
		OPT_RETURN_TOOLS:
			return_tools(item, ctx)
		OPT_HIDE:
			var view: UIRoot = OfficeKit.ui(ctx)
			if view != null:
				view.open_inventory({"room_id": item.room_id, "hide_spot_id": str(stash_spot(item)["id"])})
		OPT_RETRIEVE:
			await _retrieve(str(stash_spot(item)["id"]), ctx)
	OfficeKit.play(player, "")


static func _open_computer(ctx: Dictionary) -> void:
	var view: UIRoot = OfficeKit.ui(ctx)
	if view != null:
		view.open_computer()
		OfficeKit.sfx(view, SFX_CHAIR)


## Herramientas del puesto que guarda esta mesa (keys_basic, stamp...).
static func desk_tools(item: Interactable) -> Array[String]:
	var occ: OccupationData = PlayerState.get_occupation()
	var out: Array[String] = []
	for raw: Variant in item.data.get("contains", []):
		var item_id: String = str(raw)
		if Database.has_item(item_id) and occ != null and occ.tools.has(item_id):
			out.append(item_id)
	return out


static func carried_tools(item: Interactable) -> Array[String]:
	var out: Array[String] = []
	for tool_id: String in desk_tools(item):
		if PlayerState.is_carrying(tool_id):
			out.append(tool_id)
	return out


static func take_tools(item: Interactable, ctx: Dictionary) -> int:
	var taken: int = 0
	for tool_id: String in desk_tools(item):
		if PlayerState.is_carrying(tool_id):
			continue
		if not PlayerState.add_item(tool_id):
			OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(tool_id)])
			return taken
		taken += 1
	OfficeKit.good(ctx, "OFFICE_DESK_TOOLS_TAKEN", [_tool_names(desk_tools(item))])
	return taken


static func return_tools(item: Interactable, ctx: Dictionary) -> int:
	var returned: int = 0
	for tool_id: String in carried_tools(item):
		if PlayerState.remove_item(tool_id):
			returned += 1
	OfficeKit.good(ctx, "OFFICE_DESK_TOOLS_RETURNED", [_tool_names(desk_tools(item))])
	return returned


static func _tool_names(tools: Array[String]) -> String:
	var names: PackedStringArray = []
	for tool_id: String in tools:
		names.append(OfficeKit.item_name(tool_id))
	return ", ".join(names)


## Escondite bajo la mesa: el under_desk con capacidad pegado a la mesa ({} si no hay).
static func stash_spot(item: Interactable) -> Dictionary:
	var room: RoomData = Database.get_room(item.room_id)
	if room == null:
		return {}
	var at: Vector2i = item.data.get("pos", Vector2i.ZERO) if item.data.get("pos") is Vector2i else Vector2i.ZERO
	var best: Dictionary = {}
	var best_d: float = STASH_REACH_CELLS
	for spot: Dictionary in room.hiding_spots:
		if str(spot.get("type", "")) != UNDER_DESK or int(spot.get("capacity", 0)) <= 0:
			continue
		var d: float = Vector2((spot.get("pos", at) as Vector2i) - at).length()
		if d <= best_d:
			best_d = d
			best = spot
	return best


static func stashed_items(spot_id: String) -> Array[String]:
	var out: Array[String] = []
	var stash: Dictionary = PlayerState.get_stashes().get(spot_id, {})
	for record: Variant in stash.get("items", []):
		if record is Dictionary:
			out.append(str((record as Dictionary).get("id", "")))
	return out


static func _retrieve(spot_id: String, ctx: Dictionary) -> void:
	var items: Array[String] = stashed_items(spot_id)
	var labels: Array = []
	for item_id: String in items:
		labels.append({"text_key": "OFFICE_TAKE_ITEM", "args": [OfficeKit.item_name(item_id)]})
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_DESK_TITLE", "OFFICE_DESK_STASH_BODY", labels)
	if index < 0 or index >= items.size():
		return
	if InventoryRules.retrieve_from_stash(spot_id, items[index]) < 0:
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(items[index])])
		return
	OfficeKit.good(ctx, "OFFICE_DESK_RETRIEVED", [OfficeKit.item_name(items[index])])


# ─── Ordenadores ──────────────────────────────────────────────

## Ordenador de un compañero (§11.1 copia de archivo): solo en su ausencia.
static func use_npc_computer(item: Interactable, _player: Node, ctx: Dictionary) -> void:
	var owner: String = OfficeKit.owner_of(item)
	if OfficeKit.is_present(owner, item.room_id):
		OfficeKit.refuse(ctx, "OFFICE_PC_OWNER_HERE", [OfficeKit.npc_name(owner)])
		return
	var intrusion: Dictionary = {"computer_id": item.interact_id, "room_id": item.room_id,
			"contains": item.data.get("contains", [])}
	if not await OfficeKit.confirm_if_watched(ctx):
		OfficeKit.say(ctx, "OFFICE_ACT_ABORTED")
		return
	if StellarOS.open_intrusion(owner, intrusion) == null:
		OfficeKit.refuse(ctx, "UI_COMPUTER_UNAVAILABLE")


## Terminal de sala: intrusión si guarda archivos y nadie lo atiende; si no, ficha de lectura.
static func use_computer(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var contains: Array = item.data.get("contains", [])
	var staffed: bool = not str(item.data.get("staffed_by", "")).is_empty() \
			and not NPCDirector.get_npcs_in_room(item.room_id).is_empty()
	if staffed:
		OfficeKit.refuse(ctx, "OFFICE_TERMINAL_STAFFED")
		return
	if not contains.is_empty():
		await use_npc_computer(item, player, ctx)
		return
	OfficeKit.play(player, "check_watch")
	OfficeKit.spend_minutes("lectura")
	await OfficeKit.show_lines(ctx, "OFFICE_TERMINAL_TITLE", terminal_lines(item))


## Qué muestra un terminal según data.shows (líneas ya traducidas).
static func terminal_lines(item: Interactable) -> Array[String]:
	var shows: String = str(item.data.get("shows", ""))
	var out: Array[String] = []
	match shows:
		SHOWS_FLOOR_PLANNING:
			out.append(OfficeInfo.meeting_line())
		SHOWS_VISITOR_LOG:
			out.append_array(OfficeInfo.buyer_lines())
		SHOWS_CRISIS:
			out.append(OfficeKit.tr_key("OFFICE_SHOWS_CRISIS_DASHBOARD") % NewsFeed.get_scandal_count(1))
	if out.is_empty():
		var key: String = SHOWS_KEY_FORMAT % shows.to_upper()
		out.append(OfficeKit.tr_key(key) if OfficeKit.tr_key(key) != key else OfficeKit.tr_key("OFFICE_SHOWS_GENERIC"))
	return out


# ─── Pizarra y lector ─────────────────────────────────────────

static func use_whiteboard(_item: Interactable, player: Node, ctx: Dictionary) -> void:
	OfficeKit.play(player, "check_watch")
	OfficeKit.spend_minutes("pizarra")
	var lines: Array[String] = [OfficeInfo.meeting_line()]
	OfficeInfo.note_lines(lines)
	await OfficeKit.show_lines(ctx, "OFFICE_WHITEBOARD_TITLE", lines)


## Pasar la tarjeta por el lector de la puerta más cercana (DoorAccess registra al cruzar).
static func use_card_reader(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var game: GameRoot = OfficeKit.root(ctx)
	var door: Door = _nearest_reader(item, ctx)
	if game == null or game.doors == null or door == null:
		OfficeKit.say(ctx, "INTERACT_NOTHING_USEFUL")
		return
	OfficeKit.play(player, "clock_in")
	if game.doors.swipe(door):
		OfficeKit.sfx(game.ui, SFX_CARD, door.global_position)
		OfficeKit.good(ctx, "OFFICE_CARD_OK", [], "")
		return
	OfficeKit.sfx(game.ui, SFX_DENIED, door.global_position)
	OfficeKit.refuse(ctx, "OFFICE_CARD_DENIED", [door.clearance])


static func _nearest_reader(item: Interactable, ctx: Dictionary) -> Door:
	var streamer: FloorStreamer = ctx.get("streamer") as FloorStreamer
	if streamer == null:
		return null
	var linked: Door = streamer.get_door_by_id(str(item.data.get("door_id", "")))
	if linked != null:
		return linked
	var best: Door = null
	for door: Door in streamer.get_doors():
		if door.kind != Door.KIND_READER or not (door.room_a == item.room_id or door.room_b == item.room_id):
			continue
		if best == null or door.global_position.distance_to(item.global_position) < best.global_position.distance_to(item.global_position):
			best = door
	return best
