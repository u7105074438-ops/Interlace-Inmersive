# floor_layout_case.gd — Cuerpo de test_floor_layout: planos deterministas, válidos y navegables.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Para cada planta de Database.get_floor_ids(): todas las salas colocadas, sin solapes, todas
## alcanzables por puertas desde el eje, pares connects_to con puerta o alcanzables, resultado
## determinista, y find_path desde el ascensor (o el eje) hasta cada sala. Además construye los
## nodos de cada planta con FloorStreamer (sin errores de script) y comprueba el caso de wing_3b.

const DOOR_KINDS: Array[String] = ["normal", "reader", "service", "old_lock", "vent"]
const TRANSIT_KINDS: Array[String] = ["elevator", "stairs", "service_stairs", "freight", "vent_hatch", "exit"]


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
		await wait_frames(1)
	_check_wing_3b(streamer)
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
	var reach: Dictionary = _reachable(plan)
	var unreachable: Array[String] = []
	for id: String in rooms:
		if not reach.has(id):
			unreachable.append(id)
	check(unreachable.is_empty(), "F%d every room reachable from %s %s" % [f, plan["corridor_id"], str(unreachable)])
	check(_connects_ok(f, plan, reach), "F%d connects_to pairs share a door or are reachable" % f)
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


func _reachable(plan: Dictionary) -> Dictionary:
	var seen: Dictionary = {plan["corridor_id"]: true}
	var queue: Array[String] = [plan["corridor_id"]]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for door: Dictionary in plan["doors"]:
			if not door["walkable"]:
				continue
			var other: String = ""
			if door["a"] == current:
				other = door["b"]
			elif door["b"] == current:
				other = door["a"]
			if not other.is_empty() and not seen.has(other):
				seen[other] = true
				queue.append(other)
	return seen


func _connects_ok(f: int, plan: Dictionary, reach: Dictionary) -> bool:
	var rooms: Dictionary = plan["rooms"]
	for id: String in rooms:
		var room: RoomData = Database.get_room(id)
		for ref: String in room.connects_to:
			var other: String = ref if rooms.has(ref) else DatabaseSystem.make_room_instance_id(ref, f)
			if not rooms.has(other):
				continue
			var door: bool = false
			for d: Dictionary in plan["doors"]:
				if (d["a"] == id and d["b"] == other) or (d["a"] == other and d["b"] == id):
					door = true
			if not door and not (reach.has(id) and reach.has(other)):
				return false
	return true


func _check_paths(f: int, plan: Dictionary, streamer: FloorStreamer) -> void:
	var start_room: String = plan["corridor_id"]
	for t: Dictionary in plan["transit"]:
		if t["kind"] == "elevator":
			start_room = t["room_id"]
			break
	var start: Vector2 = streamer.get_spawn_point(start_room)
	var failed: Array[String] = []
	for id: String in plan["rooms"]:
		var path: PackedVector2Array = streamer.find_path(start, id)
		if path.is_empty() or streamer.get_room_at(path[path.size() - 1]) != id:
			failed.append(id)
	check(failed.is_empty(), "F%d find_path from %s reaches every room %s" % [f, start_room, str(failed)])


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
	var seat: Dictionary = streamer.get_seats_in_room("wing_3b")[0]
	var path: PackedVector2Array = streamer.find_path_to_point(streamer.get_spawn_point("corridors_low@3"), seat["pos"])
	check(not path.is_empty() and path[path.size() - 1].distance_to(seat["pos"]) < 1.0, "NPC can walk to a cubicle seat")
	check(not streamer.get_door_between("wing_3b", "p3_pantry").is_empty(), "wing_3b ↔ p3_pantry internal door")
	check(streamer.get_room_at(streamer.get_room_rect_px("wing_3b").get_center()) == "wing_3b", "get_room_at")
	check(streamer.get_cameras().size() > 0, "corridor cameras on floor 3")


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
	var events: Array[String] = []
	var on_in: Callable = func(room: String, by_player: bool) -> void: events.append("in:%s:%s" % [room, by_player])
	var on_out: Callable = func(room: String, by_player: bool) -> void: events.append("out:%s:%s" % [room, by_player])
	var on_floor: Callable = func(old: int, new: int) -> void: events.append("floor:%d:%d" % [old, new])
	EventBus.room_entered.connect(on_in)
	EventBus.room_exited.connect(on_out)
	EventBus.floor_changed.connect(on_floor)
	var fake: Node2D = Node2D.new()
	fake.add_to_group("player")
	streamer.get_actor_layer().add_child(fake)
	fake.global_position = streamer.get_spawn_point("wing_3b")
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(events.has("in:wing_3b:true"), "room_entered(wing_3b, true) for the player")
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
