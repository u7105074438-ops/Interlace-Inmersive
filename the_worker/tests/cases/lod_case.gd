# lod_case.gd — Cuerpo de test_lod: asignación LOD 0/1/2, force_full_lod, tope configurable y evaluación por eventos.
# PROPIETARIO DE: nada.
# ESCUCHA: npc_decided (conexión temporal del escenario).
extends TestCase

const PLAYER_ROOM := "wing_3b"
const PLAYER_FLOOR := 3
const HARLAN := "npc_harlan_voss"
const CONNIE := "npc_connie_marks"
const MAURICE := "npc_maurice_sandbell"
const SMALL_BUDGET := 10
const PROFILE_BUDGET := 45
const IDLE_FRAMES := 5

var _decided: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	EventBus.npc_decided.connect(func(n: String, a: String, c: Dictionary) -> void:
		_decided.append([n, a, c]))
	_move_clock(10)
	EventBus.floor_changed.emit(0, PLAYER_FLOOR)
	EventBus.room_entered.emit(PLAYER_ROOM, true)
	check_eq(NPCDirector.get_player_room(), PLAYER_ROOM, "player room tracked from room_entered")
	_check_levels_by_location()
	_check_intervals()
	_check_forced_levels()
	_check_caps()
	await _check_event_driven()


func _move_clock(hour: int) -> void:
	GameClock.set_time(GameClock.get_day(), hour, 0)
	EventBus.hour_passed.emit(hour, GameClock.get_day())


## LOD 0 = sala del jugador + adyacentes (máx. 20); LOD 1 = misma planta (máx. 40); LOD 2 = resto.
func _check_levels_by_location() -> void:
	var near: Dictionary = _near(PLAYER_ROOM)
	var wrong: Array[String] = []
	var counts: Array[int] = [0, 0, 0]
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var expected: int = NPCRuntime.LOD_STATISTICAL
		if npc.floor == PLAYER_FLOOR and not npc.current_room.is_empty():
			var base: String = DatabaseSystem.get_room_base_id(npc.current_room)
			expected = NPCRuntime.LOD_FULL if near.has(base) else NPCRuntime.LOD_MEDIUM
		counts[npc.lod] += 1
		if npc.lod != expected:
			wrong.append(npc.id)
	check(wrong.is_empty(), "every NPC has the level its location dictates %s" % str(wrong))
	check(counts[0] > 0 and counts[0] <= Database.get_balance_int("lod.max_agentes_completo"),
			"LOD 0 populated and within its cap (%d)" % counts[0])
	check(counts[1] > 0 and counts[1] <= Database.get_balance_int("lod.max_agentes_medio"),
			"LOD 1 populated and within its cap (%d)" % counts[1])
	check_eq(NPCDirector.get_lod("npc_george_penn"),
			0 if NPCDirector.get_current_location("npc_george_penn") == PLAYER_ROOM else 1,
			"George (3B) is simulated in full when the player is in 3B")
	check_eq(NPCDirector.get_npcs_on_floor(PLAYER_FLOOR).size(), counts[0] + counts[1],
			"get_npcs_on_floor matches the floor population")
	for npc: NPCRuntime in NPCDirector.get_npcs_near(PLAYER_ROOM):
		check(near.has(DatabaseSystem.get_room_base_id(npc.current_room)) and npc.floor == PLAYER_FLOOR,
				"get_npcs_near(%s) returns %s in an adjacent room" % [PLAYER_ROOM, npc.id])


func _check_intervals() -> void:
	check_eq(NPCDirector.get_lod_update_interval(0), 0.0, "LOD 0 updates every frame")
	check_eq(NPCDirector.get_lod_update_interval(1),
			Database.get_balance_float("lod.intervalo_medio_segundos"), "LOD 1 every 0.5 s")
	check_eq(NPCDirector.get_lod_update_interval(2),
			Database.get_balance_float("lod.intervalo_estadistico_segundos"), "LOD 2 every 5 s")


## §20.2: los personajes de una trama activa ascienden a LOD 0 aunque estén lejos.
func _check_forced_levels() -> void:
	check_eq(NPCDirector.get_lod(HARLAN), 2, "Harlan (floor 20) starts statistical")
	NPCDirector.force_full_lod(HARLAN, "target")
	NPCDirector.refresh_lod()
	check_eq(NPCDirector.get_lod(HARLAN), 0, "marked target → LOD 0 regardless of distance")
	NPCDirector.release_full_lod(HARLAN, "target")
	check_eq(NPCDirector.get_lod(HARLAN), 2, "released → back to statistical")
	EventBus.suspect_list_formed.emit("case_lod", [CONNIE, "player"])
	check_eq(NPCDirector.get_lod(CONNIE), 0, "investigation shortlist → LOD 0")
	check(NPCDirector.get_full_lod_reasons(CONNIE).has("shortlist"), "reason recorded")
	EventBus.investigation_resolved.emit("case_lod", "cold", "")
	check(NPCDirector.get_full_lod_reasons(CONNIE).is_empty()
			and NPCDirector.get_lod(CONNIE) == NPCRuntime.LOD_STATISTICAL,
			"resolved case releases the shortlist (Connie is off-shift, far away)")
	NPCDirector.add_debt(MAURICE, 5)
	check_eq(NPCDirector.get_lod(MAURICE), 0, "debt with the player → LOD 0")
	NPCDirector.add_debt(MAURICE, -5)
	check_eq(NPCDirector.get_lod(MAURICE), 2, "debt settled → statistical again")


func _check_caps() -> void:
	check_eq(NPCDirector.get_max_agents(), _configured_max_agents(),
			"agent budget = profile max_agents or lod.max_agentes_total")
	NPCDirector.force_full_lod(HARLAN, "target")
	NPCDirector.refresh_lod(SMALL_BUDGET)
	var active: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		active += 1 if npc.lod <= NPCRuntime.LOD_MEDIUM else 0
	check_eq(active, SMALL_BUDGET, "a budget of %d caps LOD 0 + LOD 1" % SMALL_BUDGET)
	check_eq(NPCDirector.get_lod(HARLAN), 0, "forced NPCs keep LOD 0 under a small budget")
	NPCDirector.release_full_lod(HARLAN, "target")
	_move_clock(13)
	EventBus.floor_changed.emit(PLAYER_FLOOR, 0)
	EventBus.room_entered.emit("cafeteria", true)
	var full: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		full += 1 if npc.lod == NPCRuntime.LOD_FULL else 0
	check_eq(full, Database.get_balance_int("lod.max_agentes_completo"),
			"a crowded cafeteria fills LOD 0 exactly to its cap of 20")
	var previous: Variant = SaveSystem.get_setting("max_agents")
	if previous != null:
		SaveSystem.set_setting("max_agents", PROFILE_BUDGET)
		check_eq(NPCDirector.get_max_agents(), int(SaveSystem.get_setting("max_agents")),
				"the profile setting max_agents drives the budget")
		NPCDirector.refresh_lod()
		var simulated: int = 0
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			simulated += 1 if npc.lod <= NPCRuntime.LOD_MEDIUM else 0
		check(simulated <= NPCDirector.get_max_agents(), "LOD 0 + LOD 1 stay within the profile budget")
		SaveSystem.set_setting("max_agents", previous)


func _configured_max_agents() -> int:
	var setting: Variant = SaveSystem.get_setting("max_agents")
	if (setting is int or setting is float) and int(setting) > 0:
		return int(setting)
	return Database.get_balance_int("lod.max_agentes_total")


## Reevaluación por eventos (§7.5, §20.2): solo al cambiar de franja y solo LOD 0/1; nada por
## fotograma mientras el reloj está parado.
func _check_event_driven() -> void:
	_decided.clear()
	await wait_frames(IDLE_FRAMES)
	check(_decided.is_empty(), "no decisions happen per frame")
	GameClock.set_time(GameClock.get_day(), 14, 0)
	EventBus.time_band_changed.emit("lunch", "work_afternoon")
	var eligible: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		eligible += 1 if npc.lod <= 1 and not npc.current_room.is_empty() else 0
	var only_near: bool = true
	for entry: Array in _decided:
		only_near = only_near and NPCDirector.get_lod(entry[0]) <= 1 and entry[2]["trigger"] == "band"
	check(eligible > 0 and _decided.size() == eligible,
			"time_band_changed evaluates each present LOD 0/1 NPC once (%d)" % eligible)
	check(only_near, "LOD 2 NPCs never run the full utility evaluation")


## Salas a distancia ≤ lod.radio_salas_completo por connects_to (en ambos sentidos).
func _near(room_id: String) -> Dictionary:
	var out: Dictionary = {room_id: true}
	var frontier: Array = [room_id]
	for _step: int in Database.get_balance_int("lod.radio_salas_completo"):
		var next: Array = []
		for room: RoomData in Database.get_all_rooms():
			var links: Array = []
			if frontier.has(room.id):
				for other: String in room.connects_to:
					links.append(DatabaseSystem.get_room_base_id(other))
			for current: Variant in frontier:
				if room.connects_to.has(current):
					links.append(room.id)
			for linked: Variant in links:
				if not out.has(linked):
					out[linked] = true
					next.append(linked)
		frontier = next
	return out
