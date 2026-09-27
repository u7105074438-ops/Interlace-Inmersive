# floor_layout.gd — Plano determinista de cada planta: salas, puertas, tránsitos y cámaras (§3, §14).
# PROPIETARIO DE: nada (cálculo puro; la caché de planos vive en FloorStreamer).
# ESCUCHA: nada.
class_name FloorLayout
extends RefCounted

## Contrato (BUILD_NOTES §14): compute(floor) → FloorPlan. Misma entrada → misma salida.
## Coordenadas en celdas de planta (1 celda = mundo.px_por_unidad px), origen arriba-izquierda.
##   rooms:  {room_id: Rect2i}  (ids de copia transversal "corridors_low@3"; orden = colocación)
##   doors:  [{a, b, cell, vertical, kind, width, clearance, special_access, walkable}]
##           vertical=false → muro horizontal en la línea y=cell.y, hueco x∈[cell.x, cell.x+width)
##           vertical=true  → muro vertical en la línea x=cell.x, hueco y∈[cell.y, cell.y+width)
##           a = sala desde la que se llega (eje o sala madre), b = sala a la que se entra.
##           kind "vent": conducto entre salas (walkable=false, cell = celda de la trampilla).
##   transit: [{id, kind, room_id, cell, targets: Array[int], target_room, door_cell, door_vertical}]
##           kind: elevator|stairs|service_stairs|freight|vent_hatch|exit; cell = celda de uso.
##   cameras: [{id, room_id, cell, rotation}] (grados en sentido horario, 0 = mira al sur; una
##           cámara de datos sin rotación, o con 0, apunta al centro de su sala).
##   corridor_id: sala eje de la planta (pasillo, calle, túnel o sala núcleo).
##   Extra: floor, size, band, order, landmarks [{id, rect}], links {id: [ids]},
##          decor {room_id: [muebles generados]} (pasillos y escondites sin mueble; ver furniture_of).

const SIDE_TOP := 0
const SIDE_BOTTOM := 1
const SIDE_LEFT := 2
const SIDE_RIGHT := 3
const HUB_SIDES: Array[int] = [SIDE_BOTTOM, SIDE_RIGHT, SIDE_TOP, SIDE_LEFT]
const EXIT_SIDES_HUB: Array[int] = [SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT, SIDE_TOP]
const EXIT_SIDES_SPINE: Array[int] = [SIDE_LEFT, SIDE_RIGHT, SIDE_BOTTOM, SIDE_TOP]
const DOOR_NORMAL := "normal"
const DOOR_READER := "reader"
const DOOR_SERVICE := "service"
const DOOR_OLD_LOCK := "old_lock"
const DOOR_VENT := "vent"
const TRANSIT_ELEVATOR := "elevator"
const TRANSIT_STAIRS := "stairs"
const TRANSIT_SERVICE_STAIRS := "service_stairs"
const TRANSIT_FREIGHT := "freight"
const TRANSIT_VENT := "vent_hatch"
const TRANSIT_EXIT := "exit"
const TRANSIT_BY_INTERACTABLE: Dictionary = {
	"elevator_panel": TRANSIT_ELEVATOR, "stairs_door": TRANSIT_STAIRS,
	"service_stairs_door": TRANSIT_SERVICE_STAIRS, "freight_panel": TRANSIT_FREIGHT,
	"vent_hatch": TRANSIT_VENT,
}
## Tránsitos que se colocan en el extremo izquierdo del eje; el resto, en el derecho.
const LEFT_CAP_KINDS: Array[String] = [TRANSIT_ELEVATOR, TRANSIT_STAIRS]
## Sala núcleo de las plantas sin pasillo (§22): la circulación nace de ella.
const HUB_ROOMS: Dictionary = {
	-3: "service_tunnel", -2: "dead_archive", -1: "service_stairs", 0: "turnstiles",
	21: "rooftop_terrace", 100: "assembly_line", 200: "street",
}
## Núcleos que se estiran como eje aunque no sean alargados: el control de torniquetes de la planta
## baja es el vestíbulo de ascensores (recepción, tienda y cafetería se abren a él). Si el eje es
## una sala de tránsito (escalera), su tramo ocupa el arranque del eje (ancho de datos).
## En S1 el rellano de la escalera de servicio hace de pasillo técnico (garaje, vestuarios, taller).
const STRETCHED_HUBS: Array[String] = ["turnstiles", "service_stairs"]
const KEY_FULL_WIDTH := "full_floor_width"
const KEY_VIRTUAL := "virtual"
const KEY_BASE_ID := "base_id"
const KEY_EXTRA_FLOORS := "extra_floors"
const KEY_STOPS := "stops"
const KEY_CAMERA_SPACING := "camera_spacing"
const KEY_LEADS_TO := "leads_to"
const LOCK_TYPE := "lock_old"
const LOCK_TARGET_DOOR := "door"
const LOCK_TARGET_PREFIX := "door:"
const READER_MIN_CLEARANCE := 2
const EXIT_ID_FORMAT := "exit_%s_%s"
const CORRIDOR_CAMERA_FORMAT := "%s_cam_%d"
const HUGE_SCORE := 1.0e18
const CENTER_WEIGHT := 4.0
## Decoración de pasillo por banda (contra los muros, entre puertas): [tipo, ancho en celdas].
const DECOR_BY_BAND: Dictionary = {
	"the_pit": [["plant", 1], ["water_cooler", 1], ["trash_bin", 1], ["plant", 1], ["vending_machine", 1]],
	"the_specialists": [["plant", 1], ["bench", 2], ["water_cooler", 1], ["planter_box", 2]],
	"the_power": [["planter_box", 2], ["statue", 1], ["sofa", 3], ["plant", 1]],
	"the_throne": [["statue", 1], ["planter_box", 2], ["plant", 1], ["sofa", 3]],
	"exterior": [["street_lamp", 1], ["bench", 2], ["trash_bin", 1], ["street_lamp", 1], ["planter_box", 2]],
	"the_guts": [["crate", 1], ["electrical_panel", 1], ["crate", 1]],
	"factory": [["crate", 1], ["pallet_stack", 2]],
}
## Tipo de escondite → mueble generado cuando no hay mueble en su celda.
const HIDING_FIXTURES: Dictionary = {"supply_closet": "wardrobe", "curtain": "curtain"}
const DECOR_DOOR_CLEARANCE := 1
## Muebles que son puesto de trabajo cuando tienen dueño (asientos para NPC y jugador).
const SEAT_TYPES: Array[String] = ["cubicle", "desk", "executive_desk", "counter", "reception_desk", "workbench"]
const CHAIR_TYPE := "chair"
const NO_CELL := Vector2i(-1, -1)

static var _vent_floors_cache: Array[int] = []
static var _furniture_cache: Dictionary = {}


class Ctx extends RefCounted:
	var floor_number: int = 0
	var decor: Dictionary = {}
	var defs: Dictionary = {}
	var ids: Array[String] = []
	var links: Dictionary = {}
	var vent_pairs: Array[Dictionary] = []
	var cross: Array[Dictionary] = []
	var spine: String = ""
	var rects: Dictionary = {}
	var parent: Dictionary = {}
	var reserved: Array[Rect2i] = []
	var landmarks: Array[Dictionary] = []
	var facade_exits: Array[Dictionary] = []
	var doors: Array[Dictionary] = []
	var transit: Array[Dictionary] = []
	var cameras: Array[Dictionary] = []
	var door_width: int = 2
	var corner: int = 1
	var min_overlap: int = 4


# ─── API pública ──────────────────────────────────────────────

## Plano completo de la planta. Pura y determinista (solo lee Database).
@warning_ignore("shadowed_global_identifier")
static func compute(floor: int) -> Dictionary:
	var ctx: Ctx = _make_context(floor)
	if ctx.ids.is_empty():
		return _finish_plan(ctx)
	if _is_spine_floor(ctx):
		_layout_spine(ctx)
	else:
		_layout_hub(ctx)
	_place_remaining(ctx)
	_build_doors(ctx)
	_build_transit(ctx)
	_build_cameras(ctx)
	_build_decor(ctx)
	return _finish_plan(ctx)


## Salas físicas de la planta (sin las virtuales, como vent_network), en orden de datos.
@warning_ignore("shadowed_global_identifier")
static func rooms_on_floor(floor: int) -> Array[RoomData]:
	var out: Array[RoomData] = []
	for room: RoomData in Database.get_rooms_by_floor(floor):
		if not bool(room.extra.get(KEY_VIRTUAL, false)):
			out.append(room)
	return out


## Id base de una sala (quita el sufijo de copia transversal "@planta").
static func base_id(room_id: String) -> String:
	return DatabaseSystem.get_room_base_id(room_id)


## Tránsito del plano con ese id o cuya sala coincide ({} si no hay).
static func find_transit(plan: Dictionary, transit_or_room_id: String) -> Dictionary:
	for t: Dictionary in plan.get("transit", []):
		if t["id"] == transit_or_room_id or t["room_id"] == transit_or_room_id:
			return t
	return {}


## Punto de llegada en `plan` para quien viene de la sala `source_room` de otra planta:
## la salida cuya target_room es source_room, o el tránsito del mismo tipo/sala base.
static func find_arrival(plan: Dictionary, source_room: String, kind: String) -> Dictionary:
	var source_base: String = base_id(source_room)
	for t: Dictionary in plan.get("transit", []):
		if kind == TRANSIT_EXIT and t["kind"] == TRANSIT_EXIT and t["target_room"] == source_room:
			return t
		if kind != TRANSIT_EXIT and t["kind"] == kind and base_id(t["room_id"]) == source_base:
			return t
	for t: Dictionary in plan.get("transit", []):
		if t["kind"] == kind:
			return t
	return {}


## Mobiliario completo de una sala en el plano: el de datos (orientación efectiva, ver
## room_furniture) más la decoración generada (pasillos, escondites, vestido de salas).
static func furniture_of(plan: Dictionary, room: RoomData) -> Array[Dictionary]:
	var out: Array[Dictionary] = room_furniture(room).duplicate()
	for entry: Dictionary in plan.get("decor", {}).get(room.id, []):
		out.append(entry)
	return out


## Mobiliario de datos con su orientación efectiva: un recinto (cubículo, cabina) cuya entrada queda
## tapada por otro mueble o por el muro se gira 180º (filas apiladas → puestos espalda con espalda).
## Mismo orden e índices que room.furniture (furniture_index de los asientos). No modificar.
static func room_furniture(room: RoomData) -> Array[Dictionary]:
	var key: int = room.get_instance_id()
	if _furniture_cache.has(key):
		return _furniture_cache[key]
	var out: Array[Dictionary] = []
	for entry: Dictionary in room.furniture:
		out.append(entry.duplicate())
	for i: int in out.size():
		if not FurniturePainter.is_enclosure(str(out[i]["type"])) or _entrance_clear(out, i, out[i], room.size):
			continue
		var flipped: Dictionary = out[i].duplicate()
		flipped["rotation"] = fmod(float(out[i].get("rotation", 0.0)) + 180.0, 360.0)
		if _entrance_clear(out, i, flipped, room.size):
			out[i] = flipped
	_furniture_cache[key] = out
	return out


## Alguna celda delante del lado abierto de `entry` (sustituto del mueble i) está libre y dentro.
static func _entrance_clear(list: Array[Dictionary], index: int, entry: Dictionary, size: Vector2i) -> bool:
	var blocked: Dictionary = {}
	for i: int in list.size():
		if i != index:
			for c: Vector2i in FurniturePainter.blocked_cells(list[i]):
				blocked[c] = true
	for c: Vector2i in FurniturePainter.front_cells(entry):
		if Rect2i(Vector2i.ZERO, size).has_point(c) and not blocked.has(c):
			return true
	return false


## Celdas de mobiliario que bloquean el paso, en coordenadas de planta (+ decoración opcional).
static func blocked_cells(room: RoomData, rect: Rect2i, extra: Array = []) -> Dictionary:
	var out: Dictionary = {}
	var entries: Array = room_furniture(room).duplicate()
	entries.append_array(extra)
	for entry: Dictionary in entries:
		if FurniturePainter.blocking_of(str(entry["type"])) == FurniturePainter.BLOCK_NONE:
			continue
		for cell: Vector2i in FurniturePainter.blocked_cells(entry):
			out[rect.position + cell] = true
	return out


## Puestos de trabajo (muebles de SEAT_TYPES con dueño) en celdas locales de sala:
## [{index, owner, type, cell: Vector2i, chair: Vector2 (celdas; punto exacto de la silla), facing}].
## El asiento es la silla de datos contigua si la hay; si no, la celda libre dentro de la sala
## detrás de la mesa, delante o a los lados (los recintos: su fila abierta, bajo la silla dibujada).
static func seats_of(room: RoomData) -> Array[Dictionary]:
	var furniture: Array[Dictionary] = room_furniture(room)
	var blocked: Dictionary = blocked_cells(room, Rect2i(Vector2i.ZERO, room.size))
	var claimed: Dictionary = {}
	var out: Array[Dictionary] = []
	for i: int in furniture.size():
		var entry: Dictionary = furniture[i]
		if not SEAT_TYPES.has(str(entry["type"])) or not entry.has("owner"):
			continue
		var seat: Dictionary = _enclosure_seat(entry) if FurniturePainter.is_enclosure(str(entry["type"])) \
				else _desk_seat(entry, furniture, room.size, blocked, claimed)
		claimed[seat["cell"]] = true
		seat.merge({"index": i, "owner": str(entry["owner"]), "type": str(entry["type"])})
		out.append(seat)
	return out


static func _enclosure_seat(entry: Dictionary) -> Dictionary:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	var chair: Vector2 = FurniturePainter.chair_point(entry, Rect2(Vector2(fp.position), Vector2(fp.size)))
	var cell: Vector2i = Vector2i(clampi(floori(chair.x), fp.position.x, fp.end.x - 1), FurniturePainter.open_row(entry))
	var facing: Vector2 = Vector2.UP if FurniturePainter.opens_south(entry) else Vector2.DOWN
	return {"cell": cell, "chair": chair, "facing": facing}


static func _desk_seat(entry: Dictionary, furniture: Array[Dictionary], size: Vector2i, blocked: Dictionary,
		claimed: Dictionary) -> Dictionary:
	var fp: Rect2i = FurniturePainter.footprint(entry)
	var behind: Vector2i = FurniturePainter.seat_cell(entry)
	var cell: Vector2i = _adjacent_chair(fp, behind, furniture, size, blocked, claimed)
	if cell == NO_CELL:
		cell = _free_side_cell(entry, fp, size, blocked, claimed)
	var target: Vector2 = Vector2(clampi(cell.x, fp.position.x, fp.end.x - 1), clampi(cell.y, fp.position.y, fp.end.y - 1))
	return {"cell": cell, "chair": Vector2(cell) + Vector2(0.5, 0.5), "facing": (target - Vector2(cell)).normalized()}


## Silla de datos pegada a un lado de la huella, libre, dentro de la sala y sin reclamar; primero
## las del lado del puesto (`behind`, detrás de la mesa según su rotación), después cualquiera.
static func _adjacent_chair(fp: Rect2i, behind: Vector2i, furniture: Array[Dictionary], size: Vector2i,
		blocked: Dictionary, claimed: Dictionary) -> Vector2i:
	for same_side: bool in [true, false]:
		for entry: Dictionary in furniture:
			var c: Vector2i = entry.get("pos", NO_CELL)
			if str(entry["type"]) != CHAIR_TYPE or not fp.grow(1).has_point(c) or fp.has_point(c):
				continue
			var edge: bool = (c.x >= fp.position.x and c.x < fp.end.x) or (c.y >= fp.position.y and c.y < fp.end.y)
			var side_ok: bool = not same_side or (c.y == behind.y if behind.y < fp.position.y or behind.y >= fp.end.y
					else c.x == behind.x)
			if edge and side_ok and _seat_ok(c, size, blocked, claimed):
				return c
	return NO_CELL


## Primera celda libre junto a la mesa: detrás (convención de datos), delante y a los lados.
static func _free_side_cell(entry: Dictionary, fp: Rect2i, size: Vector2i, blocked: Dictionary,
		claimed: Dictionary) -> Vector2i:
	var behind: Vector2i = FurniturePainter.seat_cell(entry)
	var mid: Vector2i = Vector2i(fp.position.x + fp.size.x / 2, fp.position.y + fp.size.y / 2)
	var candidates: Array[Vector2i] = [behind, Vector2i(mid.x, fp.end.y), Vector2i(mid.x, fp.position.y - 1),
			Vector2i(fp.position.x - 1, mid.y), Vector2i(fp.end.x, mid.y)]
	for c: Vector2i in candidates:
		if _seat_ok(c, size, blocked, claimed):
			return c
	return behind


static func _seat_ok(c: Vector2i, size: Vector2i, blocked: Dictionary, claimed: Dictionary) -> bool:
	return Rect2i(Vector2i.ZERO, size).has_point(c) and not blocked.has(c) and not claimed.has(c)


# ─── Contexto ─────────────────────────────────────────────────

static func _make_context(floor_number: int) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.floor_number = floor_number
	ctx.door_width = maxi(1, Database.get_balance_int("mundo.ancho_puerta"))
	ctx.corner = maxi(0, Database.get_balance_int("mundo.margen_esquina_puerta"))
	ctx.min_overlap = ctx.door_width + 2 * ctx.corner
	for room: RoomData in rooms_on_floor(floor_number):
		ctx.defs[room.id] = room
		ctx.ids.append(room.id)
		ctx.links[room.id] = [] as Array[String]
	for id: String in ctx.ids:
		_read_links(ctx, ctx.defs[id])
	ctx.spine = _choose_spine(ctx)
	return ctx


static func _read_links(ctx: Ctx, room: RoomData) -> void:
	for ref: String in room.connects_to:
		var other: String = _resolve(ctx, ref)
		if other.is_empty():
			_note_cross(ctx, room.id, ref)
		elif other != room.id and not _is_vent_only(ctx, room, other):
			_add_link(ctx, room.id, other)
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) != TRANSIT_VENT:
			continue
		for ref: Variant in entry.get(KEY_LEADS_TO, []):
			var other: String = _resolve(ctx, str(ref))
			if not other.is_empty() and other != room.id:
				ctx.vent_pairs.append({"a": room.id, "b": other, "pos": entry["pos"]})


static func _resolve(ctx: Ctx, ref: String) -> String:
	if ctx.defs.has(ref):
		return ref
	var instance: String = DatabaseSystem.make_room_instance_id(ref, ctx.floor_number)
	return instance if ctx.defs.has(instance) else ""


static func _note_cross(ctx: Ctx, room_id: String, ref: String) -> void:
	var target: RoomData = Database.get_room(ref)
	if target == null or target.is_transversal() or target.floor == ctx.floor_number:
		return
	ctx.cross.append({"room": room_id, "target_room": ref, "target_floor": target.floor})


## Un enlace es solo de conducto si una trampilla de la sala lleva a la otra y la sala tiene
## además otra conexión transitable (p. ej. RRHH ↔ baños de planta 1, §22.6).
static func _is_vent_only(ctx: Ctx, room: RoomData, other: String) -> bool:
	var via_vent: bool = false
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) == TRANSIT_VENT and _leads_to_room(ctx, entry, other):
			via_vent = true
	if not via_vent:
		return false
	for ref: String in room.connects_to:
		var resolved: String = _resolve(ctx, ref)
		if not resolved.is_empty() and resolved != other:
			return true
	return false


static func _leads_to_room(ctx: Ctx, entry: Dictionary, other: String) -> bool:
	for ref: Variant in entry.get(KEY_LEADS_TO, []):
		if _resolve(ctx, str(ref)) == other:
			return true
	return false


static func _add_link(ctx: Ctx, a: String, b: String) -> void:
	var la: Array[String] = ctx.links[a]
	var lb: Array[String] = ctx.links[b]
	if not la.has(b):
		la.append(b)
	if not lb.has(a):
		lb.append(a)


static func _choose_spine(ctx: Ctx) -> String:
	if ctx.ids.is_empty():
		return ""
	for id: String in ctx.ids:
		if bool((ctx.defs[id] as RoomData).extra.get(KEY_FULL_WIDTH, false)):
			return id
	var hub: String = _resolve(ctx, str(HUB_ROOMS.get(ctx.floor_number, "")))
	if not hub.is_empty():
		return hub
	var best: String = ctx.ids[0]
	for id: String in ctx.ids:
		if _hub_score(ctx, id) > _hub_score(ctx, best):
			best = id
	return best


static func _hub_score(ctx: Ctx, id: String) -> int:
	var room: RoomData = ctx.defs[id]
	return (ctx.links[id] as Array).size() * 100000 + room.size.x * room.size.y


static func _is_transversal(ctx: Ctx, id: String) -> bool:
	return (ctx.defs[id] as RoomData).extra.has(KEY_BASE_ID)


static func _is_spine_floor(ctx: Ctx) -> bool:
	var room: RoomData = ctx.defs[ctx.spine]
	if room.size.x == 0 or bool(room.extra.get(KEY_FULL_WIDTH, false)) or STRETCHED_HUBS.has(base_id(ctx.spine)):
		return true
	var aspect: float = float(room.size.x) / float(maxi(1, room.size.y))
	return aspect >= Database.get_balance_float("mundo.aspecto_minimo_eje")


## Tipo de tránsito de una sala (por su interactivo de tránsito), "" si no es de tránsito.
static func transit_kind_of(room: RoomData) -> String:
	for entry: Dictionary in room.interactables:
		var kind: String = str(TRANSIT_BY_INTERACTABLE.get(str(entry["type"]), ""))
		if not kind.is_empty() and kind != TRANSIT_VENT:
			return kind
	return ""


# ─── Disposición con eje (pasillo, calle, túnel) ──────────────

static func _layout_spine(ctx: Ctx) -> void:
	var spine_def: RoomData = ctx.defs[ctx.spine]
	var height: int = maxi(1, spine_def.size.y)
	ctx.rects[ctx.spine] = Rect2i(0, 0, maxi(1, spine_def.size.x), height)
	var left: Array[String] = []
	var right: Array[String] = []
	_split_caps(ctx, left, right)
	var head: int = spine_head(spine_def)
	var start_x: int = head + _cap_width(ctx, left, false)
	var cursors: Array[int] = [start_x, start_x]
	cursors[SIDE_TOP] = _reserve_facade(ctx, start_x)
	for id: String in _spine_primaries(ctx):
		var side: int = SIDE_TOP if cursors[SIDE_TOP] <= cursors[SIDE_BOTTOM] else SIDE_BOTTOM
		cursors[side] = _place_chain(ctx, _cluster_chain(ctx, id), side, cursors[side], height)
	var used: int = maxi(cursors[SIDE_TOP], cursors[SIDE_BOTTOM]) + _cap_width(ctx, right, true)
	var length: int = maxi(used, spine_def.size.x)
	ctx.rects[ctx.spine] = Rect2i(0, 0, length, height)
	_place_left_cap(ctx, left, height, head)
	_place_right_cap(ctx, right, length, height)


## Celdas del arranque del eje reservadas al tramo de escalera cuando el eje es un tránsito.
static func spine_head(spine_def: RoomData) -> int:
	return spine_def.size.x if not transit_kind_of(spine_def).is_empty() else 0


## Tránsitos transversales no enlazados por ninguna sala concreta → extremos del eje.
static func _split_caps(ctx: Ctx, left: Array[String], right: Array[String]) -> void:
	for id: String in ctx.ids:
		if id == ctx.spine or not _is_transversal(ctx, id):
			continue
		if LEFT_CAP_KINDS.has(transit_kind_of(ctx.defs[id])):
			left.append(id)
		else:
			right.append(id)


## Ancho reservado en un extremo: salas arriba/abajo alternas (las escaleras van al costado).
static func _cap_width(ctx: Ctx, cap: Array[String], is_right: bool) -> int:
	var widths: Array[int] = [0, 0]
	var index: int = 0
	for id: String in cap:
		if _is_side_cap(ctx, id, is_right):
			continue
		widths[index % 2] += (ctx.defs[id] as RoomData).size.x
		index += 1
	return maxi(widths[0], widths[1])


static func _is_side_cap(ctx: Ctx, id: String, is_right: bool) -> bool:
	var kind: String = transit_kind_of(ctx.defs[id])
	return (kind == TRANSIT_STAIRS and not is_right) or (kind == TRANSIT_SERVICE_STAIRS and is_right)


## En el exterior, la fachada de la sede ocupa el arranque del lado norte de la calle.
static func _reserve_facade(ctx: Ctx, start_x: int) -> int:
	var exits: Array[Dictionary] = []
	for link: Dictionary in ctx.cross:
		if link["room"] == ctx.spine:
			exits.append(link)
	if ctx.floor_number != Database.get_balance_int("mundo.planta_exterior") or exits.is_empty():
		return start_x
	var per_exit: int = Database.get_balance_int("mundo.fachada_ancho_por_entrada")
	var tall: int = Database.get_balance_int("mundo.fachada_alto")
	var rect: Rect2i = Rect2i(start_x, -tall, per_exit * exits.size(), tall)
	ctx.landmarks.append({"id": "hq_facade", "rect": rect})
	ctx.reserved.append(rect)
	for i: int in exits.size():
		var slot: Dictionary = exits[i].duplicate()
		slot["x"] = start_x + per_exit * i + (per_exit - ctx.door_width) / 2
		ctx.facade_exits.append(slot)
	return rect.end.x


## Salas enlazadas directamente con el eje (no transversales): primero las que enlazan con un
## tránsito del extremo izquierdo, al final las que enlazan con uno del derecho (orden estable).
static func _spine_primaries(ctx: Ctx) -> Array[String]:
	var buckets: Array = [[], [], []]
	for id: String in ctx.links[ctx.spine]:
		if _is_transversal(ctx, id) or ctx.rects.has(id):
			continue
		var bucket: int = 1
		for other: String in ctx.links[id]:
			if other != ctx.spine and _is_transversal(ctx, other):
				bucket = 0 if LEFT_CAP_KINDS.has(transit_kind_of(ctx.defs[other])) else 2
		(buckets[bucket] as Array).append(id)
	var out: Array[String] = []
	for bucket: Array in buckets:
		out.append_array(bucket)
	return out


## Cadena horizontal de un racimo: [subárbol izquierdo…, sala, subárbol derecho…].
## El primer hijo va a la derecha y el segundo a la izquierda; el resto se coloca después.
static func _cluster_chain(ctx: Ctx, root: String) -> Array[String]:
	var kids: Array[String] = _cluster_children(ctx, root)
	var chain: Array[String] = []
	if kids.size() > 1:
		chain.append_array(_side_chain(ctx, kids[1], true))
	chain.append(root)
	if kids.size() > 0:
		chain.append_array(_side_chain(ctx, kids[0], false))
	for id: String in chain:
		if id != root and not ctx.parent.has(id):
			ctx.parent[id] = root
	return chain


static func _side_chain(ctx: Ctx, id: String, mirrored: bool) -> Array[String]:
	var out: Array[String] = [id]
	var current: String = id
	while true:
		var kids: Array[String] = _cluster_children(ctx, current)
		if kids.is_empty():
			break
		ctx.parent[kids[0]] = current
		if mirrored:
			out.push_front(kids[0])
		else:
			out.append(kids[0])
		current = kids[0]
	return out


## Hijos de racimo: salas enlazadas no colocadas, no transversales y no enlazadas al eje.
static func _cluster_children(ctx: Ctx, id: String) -> Array[String]:
	var out: Array[String] = []
	for other: String in ctx.links[id]:
		if other == ctx.spine or ctx.rects.has(other) or _is_transversal(ctx, other):
			continue
		if (ctx.links[ctx.spine] as Array).has(other) or ctx.parent.has(other):
			continue
		out.append(other)
		ctx.rects[other] = Rect2i()
	return out


static func _place_chain(ctx: Ctx, chain: Array[String], side: int, x: int, height: int) -> int:
	for id: String in chain:
		var size: Vector2i = (ctx.defs[id] as RoomData).size
		var y: int = -size.y if side == SIDE_TOP else height
		ctx.rects[id] = Rect2i(x, y, size.x, size.y)
		if not ctx.parent.has(id):
			ctx.parent[id] = ctx.spine
		_reserve_exit_apron(ctx, id, side)
		x += size.x
	return x


static func _place_left_cap(ctx: Ctx, cap: Array[String], height: int, head: int) -> void:
	var cursors: Array[int] = [head, head]
	var index: int = 0
	for id: String in cap:
		var size: Vector2i = (ctx.defs[id] as RoomData).size
		if _is_side_cap(ctx, id, false):
			ctx.rects[id] = Rect2i(-size.x, (height - size.y) / 2, size.x, size.y)
		else:
			var side: int = index % 2
			var y: int = -size.y if side == SIDE_TOP else height
			ctx.rects[id] = Rect2i(cursors[side], y, size.x, size.y)
			cursors[side] += size.x
			index += 1
		ctx.parent[id] = ctx.spine


static func _place_right_cap(ctx: Ctx, cap: Array[String], length: int, height: int) -> void:
	var cursors: Array[int] = [length, length]
	var index: int = 0
	for id: String in cap:
		var size: Vector2i = (ctx.defs[id] as RoomData).size
		if _is_side_cap(ctx, id, true):
			ctx.rects[id] = Rect2i(length, (height - size.y) / 2, size.x, size.y)
		else:
			var side: int = index % 2
			cursors[side] -= size.x
			var y: int = -size.y if side == SIDE_TOP else height
			ctx.rects[id] = Rect2i(cursors[side], y, size.x, size.y)
			index += 1
		ctx.parent[id] = ctx.spine


# ─── Disposición con sala núcleo (planta baja, fábrica, sótanos, azotea) ──

static func _layout_hub(ctx: Ctx) -> void:
	var hub_def: RoomData = ctx.defs[ctx.spine]
	ctx.rects[ctx.spine] = Rect2i(Vector2i.ZERO, hub_def.size)
	_reserve_exit_apron(ctx, ctx.spine, SIDE_BOTTOM)
	var queue: Array[String] = [ctx.spine]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for other: String in _by_area_desc(ctx, ctx.links[current]):
			if ctx.rects.has(other):
				continue
			if _attach(ctx, other, current):
				queue.append(other)


## Orden estable por área descendente: las salas grandes eligen hueco antes que las pequeñas.
static func _by_area_desc(ctx: Ctx, ids: Array[String]) -> Array[String]:
	var out: Array[String] = ids.duplicate()
	var order: Dictionary = {}
	for i: int in out.size():
		order[out[i]] = i
	out.sort_custom(func(a: String, b: String) -> bool:
		var area_a: int = (ctx.defs[a] as RoomData).size.x * (ctx.defs[a] as RoomData).size.y
		var area_b: int = (ctx.defs[b] as RoomData).size.x * (ctx.defs[b] as RoomData).size.y
		return area_a > area_b or (area_a == area_b and int(order[a]) < int(order[b])))
	return out


## Coloca `id` adosada a `parent_id` (búsqueda de huecos determinista). false si no cabe.
static func _attach(ctx: Ctx, id: String, parent_id: String) -> bool:
	var size: Vector2i = (ctx.defs[id] as RoomData).size
	var rect: Rect2i = _find_adjacent(ctx, size, ctx.rects[parent_id], ctx.min_overlap)
	if rect.size == Vector2i.ZERO:
		rect = _find_adjacent(ctx, size, ctx.rects[parent_id], ctx.door_width)
	if rect.size == Vector2i.ZERO:
		return false
	ctx.rects[id] = rect
	ctx.parent[id] = parent_id
	if _has_cross(ctx, id):
		_reserve_exit_apron(ctx, id, _outward_side(rect, ctx.rects[parent_id]))
	return true


static func _has_cross(ctx: Ctx, id: String) -> bool:
	for link: Dictionary in ctx.cross:
		if link["room"] == id:
			return true
	return false


static func _outward_side(rect: Rect2i, parent_rect: Rect2i) -> int:
	if rect.position.y >= parent_rect.end.y:
		return SIDE_BOTTOM
	if rect.end.y <= parent_rect.position.y:
		return SIDE_TOP
	return SIDE_RIGHT if rect.position.x >= parent_rect.end.x else SIDE_LEFT


## Reserva una franja fuera del muro para que la salida al exterior quede libre.
static func _reserve_exit_apron(ctx: Ctx, id: String, side: int) -> void:
	if not _has_cross(ctx, id):
		return
	var r: Rect2i = ctx.rects[id]
	var span: int = ctx.min_overlap
	match side:
		SIDE_BOTTOM:
			ctx.reserved.append(Rect2i(r.get_center().x - span / 2, r.end.y, span, 1))
		SIDE_TOP:
			ctx.reserved.append(Rect2i(r.get_center().x - span / 2, r.position.y - 1, span, 1))
		SIDE_LEFT:
			ctx.reserved.append(Rect2i(r.position.x - 1, r.get_center().y - span / 2, 1, span))
		_:
			ctx.reserved.append(Rect2i(r.end.x, r.get_center().y - span / 2, 1, span))


## Salas aún sin colocar: junto a una sala ya colocada con la que enlazan, o junto al eje.
static func _place_remaining(ctx: Ctx) -> void:
	var progress: bool = true
	while progress:
		progress = false
		for id: String in ctx.ids:
			if ctx.rects.has(id) and ctx.rects[id] != Rect2i():
				continue
			for other: String in ctx.links[id]:
				if _is_placed(ctx, other) and _attach(ctx, id, other):
					progress = true
					break
	for id: String in ctx.ids:
		if not _is_placed(ctx, id) and not _attach(ctx, id, ctx.spine):
			_attach_anywhere(ctx, id)


## Último recurso: junto a cualquier sala colocada (con puerta), para no dejar salas fuera.
static func _attach_anywhere(ctx: Ctx, id: String) -> void:
	for other: String in ctx.rects.keys():
		if other != id and _is_placed(ctx, other) and _attach(ctx, id, other):
			push_warning("FloorLayout: %s placed next to %s (no space near its links)" % [id, other])
			return
	push_error("FloorLayout: no space for %s on floor %d" % [id, ctx.floor_number])


static func _is_placed(ctx: Ctx, id: String) -> bool:
	return ctx.rects.has(id) and (ctx.rects[id] as Rect2i).size != Vector2i.ZERO


## Mejor posición adosada: minimiza el área del contorno total y el descentrado.
static func _find_adjacent(ctx: Ctx, size: Vector2i, parent_rect: Rect2i, min_overlap: int) -> Rect2i:
	var best: Rect2i = Rect2i()
	var best_score: float = HUGE_SCORE
	var bounds: Rect2i = _bounds(ctx)
	## Proporción de contorno buscada (pantalla 16:9): plantas compactas y legibles.
	var aspect: float = maxf(0.1, Database.get_balance_float("mundo.proporcion_planta"))
	for side: int in HUB_SIDES:
		var along_len: int = parent_rect.size.x if side <= SIDE_BOTTOM else parent_rect.size.y
		var own_len: int = size.x if side <= SIDE_BOTTOM else size.y
		for offset: int in range(min_overlap - own_len, along_len - min_overlap + 1):
			var rect: Rect2i = _adjacent_rect(parent_rect, size, side, offset)
			if _collides(ctx, rect):
				continue
			var grown: Rect2i = bounds.merge(rect)
			var centre_off: float = absf(float(offset) + own_len * 0.5 - along_len * 0.5)
			var side_len: float = maxf(grown.size.x / aspect, float(grown.size.y))
			var score: float = side_len * side_len + float(grown.get_area()) * 0.25 + centre_off * CENTER_WEIGHT
			if score < best_score:
				best_score = score
				best = rect
	return best


static func _adjacent_rect(parent_rect: Rect2i, size: Vector2i, side: int, offset: int) -> Rect2i:
	match side:
		SIDE_TOP:
			return Rect2i(parent_rect.position.x + offset, parent_rect.position.y - size.y, size.x, size.y)
		SIDE_BOTTOM:
			return Rect2i(parent_rect.position.x + offset, parent_rect.end.y, size.x, size.y)
		SIDE_LEFT:
			return Rect2i(parent_rect.position.x - size.x, parent_rect.position.y + offset, size.x, size.y)
		_:
			return Rect2i(parent_rect.end.x, parent_rect.position.y + offset, size.x, size.y)


static func _collides(ctx: Ctx, rect: Rect2i) -> bool:
	for other: Rect2i in ctx.rects.values():
		if other.size != Vector2i.ZERO and rect.intersects(other):
			return true
	for other: Rect2i in ctx.reserved:
		if rect.intersects(other):
			return true
	return false


static func _bounds(ctx: Ctx) -> Rect2i:
	var out: Rect2i = Rect2i()
	var first: bool = true
	for rect: Rect2i in ctx.rects.values():
		if rect.size == Vector2i.ZERO:
			continue
		out = rect if first else out.merge(rect)
		first = false
	for mark: Dictionary in ctx.landmarks:
		out = out.merge(mark["rect"])
	return out


# ─── Puertas ──────────────────────────────────────────────────

static func _build_doors(ctx: Ctx) -> void:
	for id: String in ctx.rects:
		if ctx.parent.has(id) and _is_placed(ctx, id):
			_add_door(ctx, str(ctx.parent[id]), id)
	for a: String in ctx.ids:
		for b: String in ctx.links[a]:
			if a < b and _is_placed(ctx, a) and _is_placed(ctx, b) and not _has_door(ctx, a, b):
				_add_door(ctx, a, b)
	for pair: Dictionary in ctx.vent_pairs:
		if _is_placed(ctx, pair["a"]) and _is_placed(ctx, pair["b"]):
			_add_vent_door(ctx, pair)


static func _has_door(ctx: Ctx, a: String, b: String) -> bool:
	for door: Dictionary in ctx.doors:
		if (door["a"] == a and door["b"] == b) or (door["a"] == b and door["b"] == a):
			return door["walkable"]
	return false


## Puerta en el muro compartido, lo más centrada posible y sin muebles delante.
static func _add_door(ctx: Ctx, a: String, b: String) -> void:
	var wall: Dictionary = shared_wall(ctx.rects[a], ctx.rects[b])
	if wall.is_empty() or int(wall["length"]) < ctx.door_width:
		return
	var start: int = _door_start(ctx, a, b, wall)
	var vertical: bool = wall["vertical"]
	var cell: Vector2i = Vector2i(int(wall["line"]), start) if vertical \
			else Vector2i(start, int(wall["line"]))
	var entered: RoomData = ctx.defs[b]
	ctx.doors.append({
		"a": a, "b": b, "cell": cell, "vertical": vertical, "width": ctx.door_width,
		"kind": _door_kind(ctx, a, b), "clearance": entered.clearance_required,
		"special_access": entered.special_access.duplicate(), "walkable": true,
	})


## Muro común entre dos rectángulos que se tocan: {vertical, line, from, length} o {}.
static func shared_wall(r1: Rect2i, r2: Rect2i) -> Dictionary:
	var vertical_line: int = r1.end.x if r1.end.x == r2.position.x else \
			(r1.position.x if r2.end.x == r1.position.x else -2147483647)
	if vertical_line != -2147483647:
		var from_y: int = maxi(r1.position.y, r2.position.y)
		var to_y: int = mini(r1.end.y, r2.end.y)
		if to_y > from_y:
			return {"vertical": true, "line": vertical_line, "from": from_y, "length": to_y - from_y}
	var horizontal_line: int = r1.end.y if r1.end.y == r2.position.y else \
			(r1.position.y if r2.end.y == r1.position.y else -2147483647)
	if horizontal_line != -2147483647:
		var from_x: int = maxi(r1.position.x, r2.position.x)
		var to_x: int = mini(r1.end.x, r2.end.x)
		if to_x > from_x:
			return {"vertical": false, "line": horizontal_line, "from": from_x, "length": to_x - from_x}
	return {}


static func _door_start(ctx: Ctx, a: String, b: String, wall: Dictionary) -> int:
	var lo: int = int(wall["from"]) + ctx.corner
	var hi: int = int(wall["from"]) + int(wall["length"]) - ctx.corner - ctx.door_width
	if hi < lo:
		lo = int(wall["from"])
		hi = int(wall["from"]) + int(wall["length"]) - ctx.door_width
	var centre: int = (lo + hi) / 2
	var blocked: Dictionary = blocked_cells(ctx.defs[a], ctx.rects[a])
	blocked.merge(blocked_cells(ctx.defs[b], ctx.rects[b]))
	for step: int in range(0, hi - lo + 1):
		for candidate: int in [centre - step, centre + step]:
			if candidate >= lo and candidate <= hi and _door_clear(ctx, wall, candidate, blocked):
				return candidate
	return centre


static func _door_clear(ctx: Ctx, wall: Dictionary, start: int, blocked: Dictionary) -> bool:
	var line: int = int(wall["line"])
	for i: int in ctx.door_width:
		var along: int = start + i
		var a: Vector2i = Vector2i(line, along) if wall["vertical"] else Vector2i(along, line)
		var b: Vector2i = Vector2i(line - 1, along) if wall["vertical"] else Vector2i(along, line - 1)
		if blocked.has(a) or blocked.has(b):
			return false
	return true


static func _door_kind(ctx: Ctx, a: String, b: String) -> String:
	var entered: RoomData = ctx.defs[b]
	if _has_old_lock(entered, ctx.defs[a]) or _has_old_lock_to(ctx.defs[a], b):
		return DOOR_OLD_LOCK
	if _is_transversal(ctx, b) and not LEFT_CAP_KINDS.has(transit_kind_of(entered)):
		return DOOR_SERVICE
	if entered.clearance_required >= READER_MIN_CLEARANCE or not entered.special_access.is_empty():
		return DOOR_READER
	return DOOR_NORMAL


## La sala tiene un candado antiguo en "door" (su puerta) o en "door:<la otra sala>".
static func _has_old_lock(room: RoomData, other: RoomData) -> bool:
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) != LOCK_TYPE:
			continue
		var target: String = str(entry.get("target", ""))
		if target == LOCK_TARGET_DOOR or target == LOCK_TARGET_PREFIX + other.id:
			return true
	return false


static func _has_old_lock_to(room: RoomData, other_id: String) -> bool:
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) == LOCK_TYPE and str(entry.get("target", "")) == LOCK_TARGET_PREFIX + other_id:
			return true
	return false


static func _add_vent_door(ctx: Ctx, pair: Dictionary) -> void:
	var rect: Rect2i = ctx.rects[pair["a"]]
	ctx.doors.append({
		"a": pair["a"], "b": pair["b"], "cell": rect.position + (pair["pos"] as Vector2i),
		"vertical": false, "width": 1, "kind": DOOR_VENT, "clearance": 0,
		"special_access": [], "walkable": false,
	})


# ─── Tránsitos ────────────────────────────────────────────────

static func _build_transit(ctx: Ctx) -> void:
	for id: String in ctx.rects:
		if not _is_placed(ctx, id):
			continue
		var room: RoomData = ctx.defs[id]
		for entry: Dictionary in room.interactables:
			var kind: String = str(TRANSIT_BY_INTERACTABLE.get(str(entry["type"]), ""))
			if not kind.is_empty():
				ctx.transit.append(_transit_entry(ctx, id, entry, kind))
	for link: Dictionary in ctx.cross:
		if _is_placed(ctx, str(link["room"])):
			ctx.transit.append(_exit_entry(ctx, link))


static func _transit_entry(ctx: Ctx, room_id: String, entry: Dictionary, kind: String) -> Dictionary:
	var rect: Rect2i = ctx.rects[room_id]
	return {
		"id": str(entry["id"]), "kind": kind, "room_id": room_id,
		"cell": rect.position + (entry["pos"] as Vector2i),
		"targets": _transit_targets(ctx, ctx.defs[room_id], entry, kind),
		"target_room": "", "door_cell": Vector2i(-1, -1), "door_vertical": false,
	}


static func _transit_targets(ctx: Ctx, room: RoomData, entry: Dictionary, kind: String) -> Array[int]:
	var floors: Array[int] = []
	if kind == TRANSIT_VENT:
		floors = vent_floors()
	elif entry.has(KEY_STOPS):
		for value: Variant in entry[KEY_STOPS]:
			floors.append(int(value))
	elif kind == TRANSIT_FREIGHT:
		floors = _freight_stops()
	else:
		floors = _span_of(Database.get_room(base_id(room.id)))
	floors.erase(ctx.floor_number)
	return floors


static func _span_of(room: RoomData) -> Array[int]:
	var out: Array[int] = []
	if room == null or not room.is_transversal():
		return out
	for f: int in range(room.floors[0], room.floors[1] + 1):
		out.append(f)
	for value: Variant in room.extra.get(KEY_EXTRA_FLOORS, []):
		if not out.has(int(value)):
			out.append(int(value))
	return out


static func _freight_stops() -> Array[int]:
	for room: RoomData in Database.get_all_rooms():
		if room.is_transversal() and transit_kind_of(room) == TRANSIT_FREIGHT:
			var stops: Array[int] = []
			for value: Variant in room.extra.get(KEY_STOPS, _span_of(room)):
				stops.append(int(value))
			return stops
	return []


## Plantas con trampillas de conducto dentro del intervalo de la red de conductos.
static func vent_floors() -> Array[int]:
	if not _vent_floors_cache.is_empty():
		return _vent_floors_cache.duplicate()
	var out: Array[int] = []
	for room: RoomData in Database.get_all_rooms():
		if room.is_transversal():
			continue
		for entry: Dictionary in room.interactables:
			if str(entry["type"]) == TRANSIT_VENT and not out.has(room.floor):
				out.append(room.floor)
	out.sort()
	_vent_floors_cache = out
	return out.duplicate()


## Salida hacia otra planta (edificio ↔ calle, muelle ↔ fábrica…): puerta en un muro libre.
static func _exit_entry(ctx: Ctx, link: Dictionary) -> Dictionary:
	var room_id: String = str(link["room"])
	var targets: Array[int] = [int(link["target_floor"])]
	var out: Dictionary = {
		"id": EXIT_ID_FORMAT % [room_id, str(link["target_room"])], "kind": TRANSIT_EXIT,
		"room_id": room_id, "targets": targets, "target_room": str(link["target_room"]),
	}
	var slot: Dictionary = _facade_slot(ctx, link)
	var wall: Dictionary = slot if not slot.is_empty() else _free_wall(ctx, room_id)
	if wall.is_empty():
		out["cell"] = (ctx.rects[room_id] as Rect2i).get_center()
		out["door_cell"] = Vector2i(-1, -1)
		out["door_vertical"] = false
		return out
	out["door_cell"] = wall["door_cell"]
	out["door_vertical"] = wall["vertical"]
	out["cell"] = wall["inside"]
	return out


static func _facade_slot(ctx: Ctx, link: Dictionary) -> Dictionary:
	for slot: Dictionary in ctx.facade_exits:
		if slot["target_room"] == link["target_room"]:
			var x: int = int(slot["x"])
			return {"door_cell": Vector2i(x, 0), "vertical": false, "inside": Vector2i(x, 0)}
	return {}


## Primer tramo de muro exterior libre (sin sala al otro lado ni otra puerta) de la sala.
static func _free_wall(ctx: Ctx, room_id: String) -> Dictionary:
	var rect: Rect2i = ctx.rects[room_id]
	var sides: Array[int] = EXIT_SIDES_SPINE.duplicate() if room_id == ctx.spine else EXIT_SIDES_HUB.duplicate()
	if ctx.parent.has(room_id) and _is_placed(ctx, str(ctx.parent[room_id])):
		var outward: int = _outward_side(rect, ctx.rects[ctx.parent[room_id]])
		sides.erase(outward)
		sides.push_front(outward)
	for side: int in sides:
		var along_len: int = rect.size.x if side <= SIDE_BOTTOM else rect.size.y
		var centre: int = (along_len - ctx.door_width) / 2
		for step: int in range(0, along_len):
			for offset: int in [centre - step, centre + step]:
				var found: Dictionary = _exit_at(ctx, room_id, rect, side, offset)
				if not found.is_empty():
					return found
	return {}


static func _exit_at(ctx: Ctx, room_id: String, rect: Rect2i, side: int, offset: int) -> Dictionary:
	var along_len: int = rect.size.x if side <= SIDE_BOTTOM else rect.size.y
	if offset < ctx.corner or offset + ctx.door_width > along_len - ctx.corner:
		return {}
	var probe: Rect2i = _adjacent_rect(rect, Vector2i(ctx.door_width, 1) if side <= SIDE_BOTTOM \
			else Vector2i(1, ctx.door_width), side, offset)
	for other_id: String in ctx.rects:
		if other_id != room_id and probe.intersects(ctx.rects[other_id]):
			return {}
	for t: Dictionary in ctx.transit:
		if t["kind"] == TRANSIT_EXIT and t["door_cell"] != Vector2i(-1, -1) \
				and Rect2i(t["door_cell"], Vector2i.ONE).grow(ctx.door_width + 1).intersects(probe):
			return {}
	var vertical: bool = side >= SIDE_LEFT
	var line_cell: Vector2i
	var inside: Vector2i
	match side:
		SIDE_TOP:
			line_cell = Vector2i(rect.position.x + offset, rect.position.y)
			inside = line_cell
		SIDE_BOTTOM:
			line_cell = Vector2i(rect.position.x + offset, rect.end.y)
			inside = line_cell - Vector2i(0, 1)
		SIDE_LEFT:
			line_cell = Vector2i(rect.position.x, rect.position.y + offset)
			inside = line_cell
		_:
			line_cell = Vector2i(rect.end.x, rect.position.y + offset)
			inside = line_cell - Vector2i(1, 0)
	return {"door_cell": line_cell, "vertical": vertical, "inside": inside}


# ─── Cámaras ──────────────────────────────────────────────────

static func _build_cameras(ctx: Ctx) -> void:
	for id: String in ctx.rects:
		if not _is_placed(ctx, id):
			continue
		var room: RoomData = ctx.defs[id]
		var rect: Rect2i = ctx.rects[id]
		for cam: Dictionary in room.camera_positions:
			var cell: Vector2i = rect.position + (cam["pos"] as Vector2i)
			var rotation: float = float(cam.get("rotation", 0.0))
			if is_zero_approx(rotation):
				rotation = aim_rotation(Vector2(cell) + Vector2(0.5, 0.5), Vector2(rect.get_center()))
			ctx.cameras.append({"id": str(cam["id"]), "room_id": id, "cell": cell, "rotation": rotation})
		if room.has_cameras and room.camera_positions.is_empty() and id == ctx.spine:
			_corridor_cameras(ctx, room, rect)


## Cámaras del pasillo cada camera_spacing celdas, alternando muro norte y sur.
static func _corridor_cameras(ctx: Ctx, room: RoomData, rect: Rect2i) -> void:
	var spacing: int = int(room.extra.get(KEY_CAMERA_SPACING,
			Database.get_balance_int("camaras.espaciado_por_defecto")))
	spacing = maxi(1, spacing)
	var index: int = 0
	var x: int = rect.position.x + spacing / 2
	while x < rect.end.x:
		var top: bool = index % 2 == 0
		var cell: Vector2i = Vector2i(x, rect.position.y if top else rect.end.y - 1)
		ctx.cameras.append({
			"id": CORRIDOR_CAMERA_FORMAT % [room.id, index], "room_id": room.id,
			"cell": cell, "rotation": 0.0 if top else 180.0,
		})
		index += 1
		x += spacing


## Rotación (grados horario, 0 = sur) que apunta de `from` a `to`.
static func aim_rotation(from: Vector2, to: Vector2) -> float:
	var dir: Vector2 = to - from
	if dir.length_squared() < 0.0001:
		return 0.0
	return snappedf(rad_to_deg(Vector2.DOWN.angle_to(dir)), 1.0)


# ─── Resultado ────────────────────────────────────────────────

static func _finish_plan(ctx: Ctx) -> Dictionary:
	var margin: int = Database.get_balance_int("mundo.margen_planta")
	var bounds: Rect2i = _bounds(ctx)
	var shift: Vector2i = Vector2i(margin, margin) - bounds.position
	var rooms: Dictionary = {}
	var order: Array[String] = []
	for id: String in ctx.rects:
		if _is_placed(ctx, id):
			rooms[id] = Rect2i((ctx.rects[id] as Rect2i).position + shift, (ctx.rects[id] as Rect2i).size)
			order.append(id)
	return {
		"floor": ctx.floor_number, "size": bounds.size + Vector2i(margin, margin) * 2,
		"rooms": rooms, "order": order, "corridor_id": ctx.spine,
		"doors": _shift_list(ctx.doors, shift, ["cell"]),
		"transit": _shift_list(ctx.transit, shift, ["cell", "door_cell"]),
		"cameras": _shift_list(ctx.cameras, shift, ["cell"]),
		"landmarks": _shift_landmarks(ctx.landmarks, shift),
		"links": ctx.links.duplicate(true), "band": _band_id(ctx.floor_number),
		"decor": ctx.decor.duplicate(true),
	}


static func _shift_list(entries: Array[Dictionary], shift: Vector2i, keys: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var copy: Dictionary = entry.duplicate(true)
		for key: String in keys:
			if copy.has(key) and copy[key] != Vector2i(-1, -1):
				copy[key] = (copy[key] as Vector2i) + shift
		out.append(copy)
	return out


static func _shift_landmarks(marks: Array[Dictionary], shift: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mark: Dictionary in marks:
		var rect: Rect2i = mark["rect"]
		out.append({"id": mark["id"], "rect": Rect2i(rect.position + shift, rect.size)})
	return out


static func _band_id(floor_number: int) -> String:
	return str(Database.get_art_band_for_floor(floor_number).get("id", ""))


# ─── Decoración de pasillo ────────────────────────────────────

## Muebles decorativos contra los muros norte y sur del eje, entre puertas (deterministas).
static func _build_decor(ctx: Ctx) -> void:
	_hiding_fixtures(ctx)
	var kit: Array = DECOR_BY_BAND.get(_band_id(ctx.floor_number), [])
	var rect: Rect2i = ctx.rects[ctx.spine]
	if kit.is_empty() or rect.size.y < 3:
		return
	var busy: Dictionary = _spine_busy_cells(ctx, rect)
	var spacing: int = maxi(1, Database.get_balance_int("mundo.espaciado_decoracion_pasillo"))
	var out: Array[Dictionary] = []
	var index: int = 0
	for row: int in [0, rect.size.y - 1]:
		var x: int = spacing / 2
		while x < rect.size.x - 1:
			var item: Array = kit[index % kit.size()]
			if _run_free(busy, Vector2i(x, row), int(item[1])):
				out.append({"type": str(item[0]), "pos": Vector2i(x, row), "size": [int(item[1]), 1],
						"rotation": 0.0 if row == 0 else 180.0, "decor": true})
				index += 1
			x += spacing
	ctx.decor[ctx.spine] = out


## Escondites sin mueble propio: armario de material (alto) o cortinas (planas) en su celda.
static func _hiding_fixtures(ctx: Ctx) -> void:
	for id: String in ctx.rects:
		if not _is_placed(ctx, id) or _is_transversal(ctx, id):
			continue
		var room: RoomData = ctx.defs[id]
		var occupied: Dictionary = _furniture_cells(room)
		var out: Array[Dictionary] = []
		for spot: Dictionary in room.hiding_spots:
			var type: String = str(HIDING_FIXTURES.get(str(spot["type"]), ""))
			if type.is_empty() or occupied.has(spot["pos"]) or _near_door(ctx, id, spot["pos"]):
				continue
			out.append({"type": type, "pos": spot["pos"], "rotation": 0.0, "decor": true})
		if not out.is_empty():
			ctx.decor[id] = out


static func _furniture_cells(room: RoomData) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in room.furniture:
		var fp: Rect2i = FurniturePainter.footprint(entry)
		for y: int in range(fp.position.y, fp.end.y):
			for x: int in range(fp.position.x, fp.end.x):
				out[Vector2i(x, y)] = true
	return out


static func _near_door(ctx: Ctx, room_id: String, local: Vector2i) -> bool:
	var cell: Vector2i = (ctx.rects[room_id] as Rect2i).position + local
	for door: Dictionary in ctx.doors:
		if door["walkable"] and (door["a"] == room_id or door["b"] == room_id):
			var span: Rect2i = Rect2i(door["cell"], Vector2i(1, int(door["width"])) if door["vertical"]
					else Vector2i(int(door["width"]), 1)).grow(DECOR_DOOR_CLEARANCE + 1)
			if span.has_point(cell):
				return true
	return false


## Celdas locales del eje que deben quedar libres: frente a puertas, tránsitos y extremos.
static func _spine_busy_cells(ctx: Ctx, rect: Rect2i) -> Dictionary:
	var busy: Dictionary = blocked_cells(ctx.defs[ctx.spine], Rect2i(Vector2i.ZERO, rect.size))
	var openings: Array[Dictionary] = []
	for door: Dictionary in ctx.doors:
		if door["a"] == ctx.spine or door["b"] == ctx.spine:
			openings.append({"cell": door["cell"], "vertical": door["vertical"], "width": door["width"]})
	for t: Dictionary in ctx.transit:
		if t["room_id"] == ctx.spine:
			openings.append({"cell": t["cell"], "vertical": false, "width": 1})
	for o: Dictionary in openings:
		var c: Vector2i = (o["cell"] as Vector2i) - rect.position
		for k: int in range(-DECOR_DOOR_CLEARANCE, int(o["width"]) + DECOR_DOOR_CLEARANCE):
			for d: int in range(-1, 2):
				busy[c + (Vector2i(d, k) if o["vertical"] else Vector2i(k, d))] = true
	for y: int in rect.size.y:
		busy[Vector2i(0, y)] = true
		busy[Vector2i(rect.size.x - 1, y)] = true
	return busy


static func _run_free(busy: Dictionary, start: Vector2i, width: int) -> bool:
	for k: int in width:
		if busy.has(start + Vector2i(k, 0)):
			return false
	return true
