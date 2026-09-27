# floor_layout_case.gd — Cuerpo de test_floor_layout: planos deterministas, válidos y navegables.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Para cada planta de Database.get_floor_ids(): todas las salas colocadas, sin solapes, todas
## alcanzables por puertas desde el eje, cada par connects_to de la planta con puerta directa (o
## en la lista de excepciones), resultado determinista, find_path desde el ascensor (o el eje) hasta
## cada sala, todo asiento alcanzable, toda salida cerrada por su cristal, todo interactivo y
## escondite al alcance de una celda transitable, y ningún mueble tapando a quien se sienta.
## Además: puertas con control de acceso (Door), la compuerta de tornos de la planta baja como
## único paso a los ascensores, cámaras y seguimiento del jugador.

const DOOR_KINDS: Array[String] = ["normal", "reader", "service", "old_lock", "vent"]
const TRANSIT_KINDS: Array[String] = ["elevator", "stairs", "service_stairs", "freight", "vent_hatch", "exit"]
## Pares connects_to sin puerta directa aceptados (la sala se alcanza por otra vía del plano):
## la cafetería es pública (§5.2 N0) y se abre al vestíbulo, no al lado seguro de los tornos.
const LINK_EXCEPTIONS: Array[String] = ["cafeteria|turnstiles"]


func run_case() -> void:
	check(new_run(), "database loaded")
	var floors: Array[int] = Database.get_floor_ids()
	check(floors.size() >= 27, "all floors known (%d)" % floors.size())
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	for f: int in floors:
		var plan: Dictionary = FloorLayout.compute(f)
		_check_plan(f, plan)
		streamer.load_floor(f)
		check_eq(streamer.get_current_floor(), f, "F%d streamer loaded" % f)
		_check_paths(f, plan, streamer)
		_check_seats(f, plan, streamer)
		_check_reach(f, plan, streamer)
		_check_occlusion(f, plan, streamer)
		await wait_frames(1)
		await _check_exits(f, plan, streamer)
	_check_wing_3b(streamer)
	await _check_doors(streamer)
	_check_gate(streamer)
	await _check_player_tracking(streamer)
	await _check_camera(streamer)
	_check_transit_contract()
	_check_prompts()
	_check_furniture_art()
	streamer.queue_free()


func _check_plan(f: int, plan: Dictionary) -> void:
	var rooms: Dictionary = plan["rooms"]
	var missing: Array[String] = []
	for room: RoomData in Database.get_rooms_by_floor(f):
		if not bool(room.extra.get("virtual", false)) and not rooms.has(room.id):
			missing.append(room.id)
	check(missing.is_empty(), "F%d every room placed %s" % [f, str(missing)])
	check(rooms.has(plan["corridor_id"]), "F%d spine %s placed" % [f, plan["corridor_id"]])
	check(_overlaps(rooms).is_empty(), "F%d no overlapping rects %s" % [f, str(_overlaps(rooms))])
	check(_inside(plan), "F%d rooms inside plan size" % f)
	check(_doors_valid(plan), "F%d doors lie on shared walls with valid kinds" % f)
	var reach: Dictionary = _reachable(plan, "")
	var unreachable: Array[String] = []
	for id: String in rooms:
		if not reach.has(id):
			unreachable.append(id)
	check(unreachable.is_empty(), "F%d every room reachable from %s %s" % [f, plan["corridor_id"], str(unreachable)])
	var missing_links: Array[String] = _missing_links(f, plan)
	check(missing_links.is_empty(), "F%d every connects_to pair shares a door %s" % [f, str(missing_links)])
	var again: Dictionary = FloorLayout.compute(f)
	check(var_to_str(again) == var_to_str(plan), "F%d deterministic" % f)
	for t: Dictionary in plan["transit"]:
		if not TRANSIT_KINDS.has(str(t["kind"])) or not rooms.has(t["room_id"]):
			check(false, "F%d transit %s valid" % [f, t["id"]])


func _overlaps(rooms: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = rooms.keys()
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if (rooms[ids[i]] as Rect2i).intersects(rooms[ids[j]]):
				out.append("%s/%s" % [ids[i], ids[j]])
	return out


func _inside(plan: Dictionary) -> bool:
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, plan["size"])
	for r: Rect2i in plan["rooms"].values():
		if not bounds.encloses(r):
			return false
	return true


func _doors_valid(plan: Dictionary) -> bool:
	for door: Dictionary in plan["doors"]:
		if not DOOR_KINDS.has(str(door["kind"])):
			return false
		if not door["walkable"]:
			continue
		var wall: Dictionary = FloorLayout.shared_wall(plan["rooms"][door["a"]], plan["rooms"][door["b"]])
		if wall.is_empty() or wall["vertical"] != door["vertical"]:
			return false
		var along: int = (door["cell"] as Vector2i).y if door["vertical"] else (door["cell"] as Vector2i).x
		if along < int(wall["from"]) or along + int(door["width"]) > int(wall["from"]) + int(wall["length"]):
			return false
	return true


## Salas alcanzables desde el eje por puertas transitables (sin pasar por `blocked_room`).
func _reachable(plan: Dictionary, blocked_room: String) -> Dictionary:
	var seen: Dictionary = {plan["corridor_id"]: true}
	var queue: Array[String] = [plan["corridor_id"]]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for door: Dictionary in plan["doors"]:
			if not door["walkable"]:
				continue
			var other: String = str(door["b"]) if door["a"] == current else (str(door["a"]) if door["b"] == current else "")
			if not other.is_empty() and other != blocked_room and not seen.has(other):
				seen[other] = true
				queue.append(other)
	return seen


## Pares connects_to de la planta (sin los de conducto) sin puerta transitable directa.
func _missing_links(f: int, plan: Dictionary) -> Array[String]:
	var rooms: Dictionary = plan["rooms"]
	var out: Array[String] = []
	for id: String in rooms:
		var room: RoomData = Database.get_room(id)
		for ref: String in room.connects_to:
			var other: String = ref if rooms.has(ref) else DatabaseSystem.make_room_instance_id(ref, f)
			if not rooms.has(other) or other == id or _vent_link(room, ref):
				continue
			var pair: Array[String] = [FloorLayout.base_id(id), FloorLayout.base_id(other)]
			pair.sort()
			var key: String = "%s|%s" % pair
			if not _has_walkable_door(plan, id, other) and not LINK_EXCEPTIONS.has(key) and not out.has(key):
				out.append(key)
	return out


func _vent_link(room: RoomData, ref: String) -> bool:
	for entry: Dictionary in room.interactables:
		if str(entry["type"]) == "vent_hatch" and (entry.get("leads_to", []) as Array).has(ref):
			return true
	return false


func _has_walkable_door(plan: Dictionary, a: String, b: String) -> bool:
	for d: Dictionary in plan["doors"]:
		if d["walkable"] and ((d["a"] == a and d["b"] == b) or (d["a"] == b and d["b"] == a)):
			return true
	return false


func _check_paths(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	var start: Vector2 = streamer.get_spawn_point(_start_room(plan))
	var failed: Array[String] = []
	for id: String in plan["rooms"]:
		var path: PackedVector2Array = streamer.find_path(start, id)
		if path.is_empty() or streamer.get_room_at(path[path.size() - 1]) != id:
			failed.append(id)
	check(failed.is_empty(), "F%d find_path from %s reaches every room %s" % [f, _start_room(plan), str(failed)])


func _start_room(plan: Dictionary) -> String:
	for t: Dictionary in plan["transit"]:
		if t["kind"] == "elevator":
			return t["room_id"]
	return plan["corridor_id"]


## Todo asiento: dentro de su sala y con ruta desde el ascensor que acaba en su celda.
func _check_seats(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	var start: Vector2 = streamer.get_spawn_point(_start_room(plan))
	var bad: Array[String] = []
	var count: int = 0
	for id: String in plan["rooms"]:
		for seat: Dictionary in streamer.get_seats_in_room(id):
			count += 1
			var path: PackedVector2Array = streamer.find_path_to_point(start, seat["pos"])
			var ok: bool = streamer.get_room_at(seat["pos"]) == id and not path.is_empty() \
					and streamer.world_to_cell(path[path.size() - 1]) == seat["cell"]
			if not ok:
				bad.append("%s#%d" % [id, int(seat["furniture_index"])])
	check(bad.is_empty(), "F%d all %d seats inside their room and reachable %s" % [f, count, str(bad)])


## Todo interactivo y escondite tiene una celda transitable (conectada) a su radio de uso.
func _check_reach(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	var cell: float = RoomBuilder.cell_px()
	var radius: float = Database.get_balance_float("mundo.radio_uso_interactivo") * cell
	var bad: Array[String] = []
	for id: String in plan["rooms"]:
		for item: Interactable in streamer.get_interactables_in_room(id):
			var near: Vector2 = streamer.nearest_walkable_point(item.global_position)
			if near == Vector2.INF or near.distance_to(item.global_position) > radius:
				bad.append(item.interact_id)
	check(bad.is_empty(), "F%d every interactable and hiding spot within reach of a walkable cell %s" % [f, str(bad)])


## Nadie sentado queda tapado: ningún mueble (salvo mamparas laterales) que se ordene después del
## asiento dibuja sobre el cuerpo de quien se sienta (≈ media celda de ancho, casi una de alto).
func _check_occlusion(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	var cell: float = RoomBuilder.cell_px()
	var bad: Array[String] = []
	var props: Array[Node] = streamer.get_actor_layer().get_child(0).get_children()
	for id: String in plan["rooms"]:
		for seat: Dictionary in streamer.get_seats_in_room(id):
			var pos: Vector2 = seat["pos"]
			var body: Rect2 = Rect2(pos + Vector2(-cell * 0.25, -cell * 0.9), Vector2(cell * 0.5, cell * 0.9))
			for node: Node in props:
				var prop: RoomBuilder.Prop = node as RoomBuilder.Prop
				if prop == null or str(prop.entry.get("part", "")) == FurniturePainter.PART_SIDES:
					continue
				if prop.global_position.y > pos.y + 1.0 and _drawn_rect(prop, cell).intersects(body):
					bad.append("%s#%d" % [id, int(seat["furniture_index"])])
	check(bad.is_empty(), "F%d no furniture drawn over a seated actor %s" % [f, str(bad)])


## Zona que pinta un Prop (huella + extrusión; el fondo de un recinto, solo su fila del fondo).
func _drawn_rect(prop: RoomBuilder.Prop, cell: float) -> Rect2:
	var type: String = str(prop.entry["type"])
	var h: float = float(FurniturePainter.spec_of(type)[1]) * cell / FurniturePainter.REFERENCE_CELL
	var r: Rect2 = Rect2(prop.global_position + prop.footprint.position, prop.footprint.size)
	if str(prop.entry.get("part", "")) == FurniturePainter.PART_BACK:
		var row: int = FurniturePainter.back_row(prop.entry) - FurniturePainter.footprint(prop.entry).position.y
		r = Rect2(r.position.x, r.position.y + row * cell, r.size.x, cell)
	return Rect2(r.position.x, r.position.y - h, r.size.x, r.size.y + h).grow(-3.0)


## Cada salida al exterior está cerrada por su cristal (capa 1): solo se cruza con el interactivo.
func _check_exits(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	await get_tree().physics_frame
	var cell: float = RoomBuilder.cell_px()
	var open: Array[String] = []
	for t: Dictionary in plan["transit"]:
		if t["kind"] != "exit" or t["door_cell"] == Vector2i(-1, -1):
			continue
		var inside: Vector2 = streamer.cell_to_world(t["cell"])
		var door_mid: Vector2 = streamer.to_global(Vector2(t["door_cell"] as Vector2i) * cell) + \
				(Vector2(0, 1) if t["door_vertical"] else Vector2(1, 0)) * cell
		var outside: Vector2 = door_mid + (door_mid - inside).normalized() * cell * 1.5
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(inside, outside, 0b111)
		if streamer.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			open.append(str(t["id"]))
	check(open.is_empty(), "F%d every exit gap is closed by its glass doors %s" % [f, str(open)])


func _check_wing_3b(streamer: FloorStreamer) -> void:
	streamer.load_floor(3)
	var room: RoomData = Database.get_room("wing_3b")
	var cubicles: int = room.furniture.filter(func(e: Dictionary) -> bool: return e["type"] == "cubicle").size()
	check_eq(cubicles, 12, "wing_3b has twelve cubicles")
	check(streamer.get_room_node("wing_3b") != null, "wing_3b node built")
	check_eq(streamer.get_seats_in_room("wing_3b").size() >= 12, true, "wing_3b exposes its seats")
	var items: Array[Interactable] = streamer.get_interactables_in_room("wing_3b")
	check(items.size() >= room.interactables.size(), "wing_3b interactables instantiated")
	check(streamer.get_hiding_spots_in_room("wing_3b").size() == room.hiding_spots.size(), "wing_3b hiding spots")
	check(not streamer.get_door_between("wing_3b", "p3_pantry").is_empty(), "wing_3b ↔ p3_pantry internal door")
	check(streamer.get_room_at(streamer.get_room_rect_px("wing_3b").get_center()) == "wing_3b", "get_room_at")
	check(streamer.get_cameras().size() > 0, "corridor cameras on floor 3")
	var p2: Dictionary = FloorLayout.compute(2)
	var flipped: int = 0
	for entry: Dictionary in FloorLayout.room_furniture(Database.get_room("call_center")):
		if entry["type"] == "cubicle" and not FurniturePainter.opens_south(entry):
			flipped += 1
	check(flipped > 0 and p2["rooms"].has("call_center"), "stacked call-center cubicles face back to back (%d)" % flipped)


## Door: nodos para lector / cerradura antigua / servicio; bloqueada corta el paso y la vista; se
## abre con open_for y la política del jugador decide al acercarse.
func _check_doors(streamer: FloorStreamer) -> void:
	streamer.load_floor(0)
	var monitor: Door = streamer.get_door_node("turnstiles", "monitor_room")
	check(monitor != null and monitor.kind == "reader" and monitor.is_locked(), "monitor room has a locked reader door")
	if monitor == null:
		return
	check_eq(streamer.get_door_by_id(monitor.door_id), monitor, "get_door_by_id")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var a: Vector2 = monitor.to_global(monitor.gap_rect().get_center()) - _door_normal(monitor) * 40.0
	var b: Vector2 = monitor.to_global(monitor.gap_rect().get_center()) + _door_normal(monitor) * 40.0
	check(_ray_blocked(streamer, a, b, 1), "a locked door blocks movement and sight (layer 1)")
	monitor.open_for(2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(monitor.is_open() and not _ray_blocked(streamer, a, b, 1), "open_for() opens the door")
	monitor.close()
	monitor.set_locked(false)
	check(not monitor.is_locked(), "set_locked(false)")
	var orders: Dictionary = FloorLayout.compute(2)
	var old_lock: int = 0
	for door: Dictionary in orders["doors"]:
		if door["kind"] == "old_lock":
			old_lock += 1
	check(old_lock > 0, "old_lock doors exist on floor 2")
	streamer.load_floor(2)
	var lock_item: Interactable = null
	for item: Interactable in streamer.get_interactables_in_room("orders_archive"):
		if item.interact_type == "lock_old":
			lock_item = item
	check(lock_item != null and streamer.get_door_by_id(str(lock_item.data.get("door_id", ""))) != null,
			"lock_old interactable knows its Door (data.door_id)")


func _door_normal(door: Door) -> Vector2:
	return Vector2(1, 0) if door.vertical else Vector2(0, 1)


func _ray_blocked(streamer: FloorStreamer, a: Vector2, b: Vector2, mask: int) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, mask)
	return not streamer.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Planta baja: la compuerta de tornos es el único paso del vestíbulo a ascensores y escaleras.
func _check_gate(streamer: FloorStreamer) -> void:
	var plan: Dictionary = FloorLayout.compute(0)
	check_eq(plan["corridor_id"], "main_reception", "PB hub is main_reception")
	var gate: Rect2i = plan["rooms"]["turnstiles"]
	check_eq(gate.size, Database.get_room("turnstiles").size, "turnstiles keeps its data size")
	var without: Dictionary = _reachable(plan, "turnstiles")
	for id: String in ["main_elevator_1@0", "main_elevator_2@0", "main_stairs@0"]:
		check(plan["rooms"].has(id) and not without.has(id), "%s only reachable through the turnstiles" % id)
	for id: String in ["cafeteria", "flagship_store", "ground_toilets", "infirmary", "visitor_lounge"]:
		check(without.has(id), "%s is on the public side" % id)
	streamer.load_floor(0)
	var gates: int = 0
	for door: Door in streamer.get_doors():
		if door.kind == Door.KIND_TURNSTILE:
			gates += 1
	check_eq(gates, 4, "four turnstile gates")
	var row: int = gate.position.y + 3
	var crossings: int = 0
	for x: int in range(gate.position.x, gate.end.x):
		if not streamer.find_path_to_point(streamer.cell_to_world(Vector2i(x, row - 1)),
				streamer.cell_to_world(Vector2i(x, row + 1))).is_empty() and streamer.is_walkable_cell(Vector2i(x, row)):
			crossings += 1
	check_eq(crossings, 4, "the turnstile row can only be crossed at its four gates")


func _check_transit_contract() -> void:
	var p3: Dictionary = FloorLayout.compute(3)
	check(not FloorLayout.find_transit(p3, "main_elevator_1@3").is_empty(), "F3 elevator transit")
	check(not FloorLayout.find_transit(p3, "service_stairs@3").is_empty(), "F3 service stairs transit")
	var pb: Dictionary = FloorLayout.compute(0)
	check(not FloorLayout.find_arrival(pb, "street", "exit").is_empty(), "PB exit to the street")
	var street: Dictionary = FloorLayout.compute(Database.get_balance_int("mundo.planta_exterior"))
	check(not FloorLayout.find_arrival(street, "main_reception", "exit").is_empty(), "street entrance to reception")
	var elevator: Dictionary = FloorLayout.find_transit(p3, "main_elevator_1@3")
	check((elevator.get("targets", []) as Array).has(20), "elevator reaches floor 20")
	check(not (elevator.get("targets", []) as Array).has(3), "transit targets exclude the current floor")
	var empty: Dictionary = FloorLayout.compute(55)
	check((empty["rooms"] as Dictionary).is_empty() and empty.has("size"), "floor without rooms gives an empty plan")
	var vents: int = 0
	for t: Dictionary in p3["transit"]:
		if t["kind"] == "vent_hatch":
			vents += 1
	check(vents > 0, "vent hatches become transit points")


func _check_player_tracking(streamer: FloorStreamer) -> void:
	streamer.load_floor(3)
	var events: Array[String] = []
	var on_in: Callable = func(room: String, by_player: bool) -> void: events.append("in:%s:%s" % [room, by_player])
	var on_out: Callable = func(room: String, by_player: bool) -> void: events.append("out:%s:%s" % [room, by_player])
	var on_floor: Callable = func(old: int, new: int) -> void: events.append("floor:%d:%d" % [old, new])
	EventBus.room_entered.connect(on_in)
	EventBus.room_exited.connect(on_out)
	EventBus.floor_changed.connect(on_floor)
	streamer.position = Vector2(300, -120)
	var fake: Node2D = Node2D.new()
	fake.add_to_group("player")
	streamer.get_actor_layer().add_child(fake)
	fake.global_position = streamer.get_spawn_point("wing_3b")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(events.has("in:wing_3b:true"), "room_entered(wing_3b, true) for the player (streamer offset)")
	fake.global_position = streamer.get_spawn_point("corridors_low@3")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(events.has("out:wing_3b:true") and events.has("in:corridors_low@3:true"), "room change emits exit + enter")
	check_eq(streamer.get_player_room(), "corridors_low@3", "streamer tracks the player room")
	streamer.load_floor(4)
	check(events.has("floor:3:4"), "floor_changed(3, 4) on load_floor")
	check(events.has("out:corridors_low@3:true"), "room_exited on floor change")
	EventBus.room_entered.disconnect(on_in)
	EventBus.room_exited.disconnect(on_out)
	EventBus.floor_changed.disconnect(on_floor)
	fake.queue_free()
	streamer.position = Vector2.ZERO
	streamer.load_floor(3)


func _check_camera(streamer: FloorStreamer) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cam: SecurityCamera = null
	for c: SecurityCamera in streamer.get_cameras():
		if c.room_id == "corridors_low@3":
			cam = c
			break
	check(cam != null, "corridor camera exists")
	if cam == null:
		return
	var cell: float = RoomBuilder.cell_px()
	check(not cam.camera_id.is_empty() and cam.is_in_group("security_cameras"), "camera id and group")
	check(cam.is_player_in_view(cam.global_position + cam.get_facing() * cell * 2.0), "camera sees in front")
	check(not cam.is_player_in_view(cam.global_position - cam.get_facing() * cell * 2.0), "camera blind behind")
	var far: Vector2 = cam.global_position + cam.get_facing() * cell * 50.0
	check(not cam.is_player_in_view(far), "camera range limited")
	cam.set_active(false)
	check(not cam.is_player_in_view(cam.global_position + cam.get_facing() * cell * 2.0), "inactive camera sees nothing")
	cam.set_active(true)
	var target: Vector2 = cam.global_position + cam.get_facing() * cell * 3.0
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(cell * 2.0, cell * 2.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = cam.global_position + cam.get_facing() * cell * 1.6
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not cam.is_player_in_view(target), "walls (layer 1) block camera line of sight")
	wall.queue_free()


func _check_prompts() -> void:
	var missing: Array[String] = []
	for room: RoomData in Database.get_all_rooms():
		for entry: Dictionary in room.interactables:
			var key: String = Interactable.PROMPT_PREFIX + str(entry["type"]).to_upper()
			if tr(key) == key and not missing.has(key):
				missing.append(key)
	for key: String in ["UI_INTERACT_GENERIC", "UI_INTERACT_EXIT", HidingSpot.PROMPT_HIDE]:
		if tr(key) == key:
			missing.append(key)
	check(missing.is_empty(), "every interactable type has a localised prompt %s" % str(missing))


## Todo tipo de mueble usado en data/rooms tiene silueta propia (no la caja genérica).
func _check_furniture_art() -> void:
	var painter: FurniturePainter = FurniturePainter.new({"pal": {}, "cell": RoomBuilder.cell_px()})
	var missing: Array[String] = []
	for room: RoomData in Database.get_all_rooms():
		for entry: Dictionary in room.furniture:
			var type: String = str(entry["type"])
			if not painter.has_method("_draw_" + type) and not missing.has(type):
				missing.append(type)
			if not FurniturePainter.SPECS.has(type) and not missing.has(type):
				missing.append(type)
	check(missing.is_empty(), "every furniture type has a silhouette and a spec %s" % str(missing))
