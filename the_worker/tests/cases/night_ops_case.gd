# night_ops_case.gd — Cuerpo de test_night_ops: domicilio conocido (N6-N7 / puesto de RR. HH. / intrusión / chantaje), seguimiento solo a quien sale, residente en casa, pasamontañas exigido, allanamiento, botín y reposición por personaje, lo que no cabe se queda, tablas de las tres tipologías, alarma y seguridad privada de la mansión (solo ve al jugador dentro), testigos (vecino parcial, residente directo), cierre con crime_committed("burglary"), eliminación en casa y persistencia (también a través de SaveSystem).
# PROPIETARIO DE: nada (los nodos Police y NightOps que crea viven solo durante el caso; su carpeta de guardado se borra al final).
# ESCUCHA: crime_committed, police_dispatched, subtitle_posted, game_over (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const EPS := 0.001
const HUMBLE_NPC := "npc_george_penn"
const SEMI_NPC := "npc_bernard_lasker"
const MANSION_NPC := "npc_alvin_pyne"
const NIGHT_GUARD := "npc_ludmila_petrova"
const HUMBLE := "npc_house_humble"
const SEMI := "npc_house_semi"
const MANSION := "npc_house_mansion"
const DAY := 2
const NIGHT_HOUR := 22
const TRIALS := 12
const STORAGE_FORMAT := "user://test_night_ops_%d"
const WATCHED: Array[String] = ["crime_committed", "police_dispatched", "subtitle_posted", "game_over"]

var _police: Police = null
var _ops: NightOps = null
var _log: Fixtures.SignalLog = null


func run_case() -> void:
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_police = Police.new()
	add_child(_police)
	_ops = NightOps.new()
	add_child(_ops)
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_test_home_address_and_timing()
	_test_address_routes()
	_test_follow_needs_leaving()
	_test_balaclava_required()
	_test_humble_burglary()
	_test_loot_overflow()
	_test_house_tables()
	_test_mansion_alarm_and_security()
	_test_private_security_needs_player_inside()
	_test_witness_rolls()
	_test_elimination_at_home()
	_test_day_change_and_save()
	_test_save_system_round_trip()
	_log.stop()
	_ops.queue_free()
	_police.queue_free()
	await get_tree().process_frame


func _fresh() -> void:
	new_run(DEFAULT_SEED)
	SaveSystem.reset_for_new_run()
	_police.reset_for_new_run()
	_ops.reset_for_new_run()
	GameClock.set_time(DAY, NIGHT_HOUR, 0)
	PlayerState.add_item("balaclava")
	Disguise.wear("balaclava")
	_log.clear()


## Jornada, domicilio conocido y operación empezada con el jugador en la vivienda (siguiéndolo o
## yendo por cuenta propia).
func _start(npc_id: String, follow: bool = true) -> Dictionary:
	PlayerState.grant_full_file(npc_id, "hr_intrusion")
	var result: Dictionary = _ops.follow_home(npc_id) if follow else _ops.visit_home(npc_id)
	EventBus.room_entered.emit(str(result.get("house", "")), true)
	return result


func _test_home_address_and_timing() -> void:
	_fresh()
	check_eq(NPCDirector.get_home_address(HUMBLE_NPC), HUMBLE, "tier-1 staff live in humble homes")
	check(PlayerState.get_personnel_file_level() < 6, "the R1 file level does not show addresses")
	check(not NightOps.knows_home_address(HUMBLE_NPC), "address unknown at N1")
	check_eq(_ops.can_follow(HUMBLE_NPC), NightOps.ERR_ADDRESS_UNKNOWN, "cannot follow without the address")
	PlayerState.grant_full_file(HUMBLE_NPC, "hr_intrusion")
	check(NightOps.knows_home_address(HUMBLE_NPC), "an HR intrusion reveals the address")
	check_eq(_ops.can_follow(HUMBLE_NPC), "", "followable at night")
	check(NPCDirector.is_at_home(HUMBLE_NPC), "an office worker is home at 22:00")
	check(not NPCDirector.is_at_home(NIGHT_GUARD), "a night guard is at work at 22:00")
	GameClock.set_time(DAY, 10, 0)
	check(not NPCDirector.is_at_home(HUMBLE_NPC), "at 10:00 the worker is at the office")
	check_eq(_ops.can_follow(HUMBLE_NPC), NightOps.ERR_WRONG_TIME, "cannot follow during the workday")
	PlayerState.set_occupation("cfo", "test")
	check(NightOps.knows_home_address(SEMI_NPC), "an N6 personnel file shows every address")
	check_eq(NightOps.reason_key(NightOps.ERR_WRONG_TIME), "NIGHT_ERR_WRONG_TIME", "reason keys")


func _test_humble_burglary() -> void:
	_fresh()
	var before: float = GameClock.get_total_minutes()
	var start: Dictionary = _start(HUMBLE_NPC)
	check(bool(start["ok"]) and str(start["house"]) == HUMBLE, "followed George home")
	check(bool(start["resident_home"]), "the resident is at home")
	check_near(GameClock.get_total_minutes() - before, Database.get_balance_float("noche.minutos_seguimiento"),
			EPS, "following costs game time")
	check_eq(str(_ops.break_in("forced_lock")["reason"]), NightOps.ERR_NO_TOOL, "forcing a lock needs a tool")
	check_eq(str(_ops.break_in("door")["reason"]), NightOps.ERR_BAD_ENTRY, "only the house's entries")
	var entry: Dictionary = _ops.break_in("window")
	check(bool(entry["ok"]) and not bool(entry["alarm"]), "in through the window, no alarm in a flat")
	check_eq(str(_ops.break_in("window")["reason"]), NightOps.ERR_ALREADY_INSIDE, "already inside")
	var money: int = PlayerState.get_money()
	var loot: Dictionary = _ops.loot_container("humble_wardrobe_drawer")
	check(bool(loot["ok"]), "wardrobe drawer looted")
	var allowed: Array[String] = ["cash_small", "jewellery_cheap", "phone_highend"]
	var cash: int = 0
	for item_id: String in loot["items"]:
		check(allowed.has(item_id), "humble loot comes from its table (%s)" % item_id)
		if item_id.begins_with("cash"):
			cash += Database.get_item(item_id).value
	check_eq(PlayerState.get_money() - money, cash, "cash goes straight to capital")
	check_eq(str(_ops.loot_container("humble_wardrobe_drawer")["reason"]), NightOps.ERR_EMPTY,
			"a looted container is empty")
	check(NPCDirector.is_house_container_looted(HUMBLE_NPC, "humble_wardrobe_drawer"),
			"NPCDirector keeps the loot state of George's house")
	check(not NPCDirector.is_house_container_looted("npc_nate_brackley", "humble_wardrobe_drawer"),
			"another humble house is untouched (state per NPC)")
	check_eq(int(NPCDirector.get_house_loot_state(HUMBLE_NPC)["burglaries"]), 1, "one burglary counted")
	_check_leave(int(loot["value"]))
	GameClock.set_time(DAY + Database.get_balance_int("noche.dias_reposicion_botin"), NIGHT_HOUR, 0)
	check(not NPCDirector.is_house_container_looted(HUMBLE_NPC, "humble_wardrobe_drawer"),
			"the house is restocked after noche.dias_reposicion_botin days")


func _check_leave(value: int) -> void:
	var stolen: int = Tracking.get_total("theft")
	_log.clear()
	var result: Dictionary = _ops.leave_house()
	check(bool(result["ok"]) and not _ops.is_active(), "leaving the house ends the operation")
	var crimes: Array[Array] = _log.all("crime_committed")
	check(crimes.size() == 1 and str(crimes[0][0]) == "burglary", "one crime_committed(burglary)")
	if crimes.size() == 1:
		var details: Dictionary = crimes[0][2]
		check_eq(int(details["value"]), value, "the burglary carries the looted value")
		check(not bool(details["leaves_record"]), "masked: the building gets no record")
	check_eq(Tracking.get_total("theft") - stolen, value, "Tracking adds the stolen value")


## Tablas de botín de balance: el valor esperado crece de piso a adosado a mansión.
func _test_house_tables() -> void:
	check_eq(NightOps.get_house_type(HUMBLE), "humble", "humble type")
	check_eq(NightOps.get_house_type(SEMI), "semi", "semi type")
	check_eq(NightOps.get_house_type(MANSION), "mansion", "mansion type")
	check_eq(NightOps.get_house_type("street"), "", "the street is not a house")
	var humble: float = _expected_value(HUMBLE)
	var semi: float = _expected_value(SEMI)
	var mansion: float = _expected_value(MANSION)
	check(humble < semi and semi < mansion, "expected loot grows: %.0f < %.0f < %.0f"
			% [humble, semi, mansion])
	check(bool(NightOps.house_params(MANSION)["alarma"]) and not bool(NightOps.house_params(HUMBLE)["alarma"]),
			"only the mansion has an alarm")
	check(bool(NightOps.house_params(MANSION)["seguridad_privada"]), "and private security")
	_fresh()
	_start(SEMI_NPC)
	_ops.break_in("window")
	check_eq(str(_ops.loot_container("semi_safe")["reason"]), NightOps.ERR_LOCKED, "a safe needs a tool")
	PlayerState.add_item("lockpick")
	var safe: Dictionary = _ops.loot_container("semi_safe")
	check(bool(safe["ok"]), "the lockpick opens the key safe")
	for item_id: String in safe["items"]:
		check(["cash_savings", "laptop_highend", "jewellery"].has(item_id), "semi loot from its table (%s)" % item_id)
	_ops.leave_house()


func _expected_value(house: String) -> float:
	var params: Dictionary = NightOps.house_params(house)
	var total: float = 0.0
	for container: Dictionary in Database.get_room(house).interactables:
		if not (container.get("contains", []) as Array).is_empty():
			for item_id: Variant in container["contains"]:
				total += float(Database.get_item(str(item_id)).value) * float(params["prob_objeto"])
			for extra: Dictionary in params["botin_extra"]:
				total += float(Database.get_item(str(extra["objeto"])).value) * float(extra["prob"])
	return total


func _test_mansion_alarm_and_security() -> void:
	_fresh()
	_start(MANSION_NPC)
	var entry: Dictionary = _ops.break_in("window")
	check(bool(entry["alarm"]), "breaking into a mansion trips the alarm")
	check_eq(_police.get_state(), Police.STATE_DISPATCHED, "the alarm dispatches the police at once")
	check_eq(str(_log.last("police_dispatched")[0]), MANSION, "to the mansion")
	var loot: Dictionary = _ops.loot_container("mansion_master_drawer")
	check(bool(loot["ok"]), "master bedroom drawer looted before the police arrive")
	var guard: String = ""
	for witness: String in loot["witnesses"]:
		if NPCDirector.get_role(witness) == "private_security":
			guard = witness
	check(not guard.is_empty(), "private security walks in after minutos_seguridad_privada")
	check(BeliefNet.get_beliefs_held_by(guard).size() > 0, "the guard is a witness (belief)")
	check_eq(str(_ops.eliminate_resident([])["reason"]), NightOps.ERR_WITNESSES,
			"no elimination with private security inside")
	_log.clear()
	_ops.loot_container("mansion_guest_drawer")
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "a second drawer takes longer than the police")
	check_eq(str(_log.last("game_over")[0]), "arrested_by_police", "arrested inside the mansion")
	check(not _ops.is_active(), "the operation ends with the game")


## Tiradas con semilla sobre varias viviendas humildes: vecinos (testigo parcial) y residentes
## que despiertan (testigo directo, aviso consolidado).
func _test_witness_rolls() -> void:
	_fresh()
	var neighbours: int = 0
	var wakes: int = 0
	for npc_id: String in _humble_targets(TRIALS):
		_police.reset_for_new_run()
		_start(npc_id)
		var witnesses: Array[String] = []
		witnesses.append_array(_ops.break_in("window")["witnesses"])
		witnesses.append_array(_ops.loot_container("humble_kitchen_drawer")["witnesses"])
		for witness: String in witnesses:
			if witness == npc_id:
				wakes += 1
				check_eq(_police.get_state(), Police.STATE_DISPATCHED, "a resident who wakes calls the police")
			elif NPCDirector.get_role(witness) == "neighbour":
				neighbours += 1
		_ops.leave_house()
	check(neighbours > 0, "neighbours notice some window entries (%d)" % neighbours)
	check(wakes > 0, "some residents wake up (%d)" % wakes)


func _humble_targets(count: int) -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.home_address == HUMBLE and NPCDirector.is_at_home(npc.id) and out.size() < count:
			out.append(npc.id)
	return out


func _test_elimination_at_home() -> void:
	_fresh()
	check(bool(_start(NIGHT_GUARD, false)["ok"]), "the night guard's home can be visited")
	check(not _ops.is_resident_home(), "a night guard's house is empty at night")
	_ops.break_in("window")
	check_eq(str(_ops.eliminate_resident([])["reason"]), NightOps.ERR_NOT_HOME, "nobody to eliminate")
	_ops.leave_house()
	_start(HUMBLE_NPC)
	check_eq(str(_ops.eliminate_resident([])["reason"]), NightOps.ERR_NOT_INSIDE, "get inside first")
	_ops.break_in("window")
	var witness: Array[String] = ["npc_nate_brackley"]
	check_eq(str(_ops.eliminate_resident(witness)["reason"]), NightOps.ERR_WITNESSES,
			"disabled with a witness in line of sight (§12.2)")
	_log.clear()
	check(bool(_ops.eliminate_resident([])["ok"]), "resident eliminated at home")
	check(not NPCDirector.is_alive(HUMBLE_NPC), "George is dead")
	check_eq(str(NPCDirector.get_body_info(HUMBLE_NPC).get("room_id", "")), HUMBLE, "the body lies in the house")
	check_eq(_log.count_for("crime_committed", "elimination"), 1, "crime_committed(elimination)")
	_ops.leave_house()


func _test_day_change_and_save() -> void:
	_fresh()
	_start(SEMI_NPC)
	_ops.break_in("window")
	var saved: Dictionary = _ops.save_state()
	var copy: NightOps = NightOps.new()
	copy.load_state(saved)
	check(copy.is_active() and str(copy.get_operation()["house"]) == SEMI, "save/load keeps the operation")
	copy.free()
	_log.clear()
	GameClock.advance_to_next_day()
	check(not _ops.is_active(), "an operation still open at dawn is closed")
	check_eq(_log.count_for("crime_committed", "burglary"), 1, "and its burglary is reported")
	var state: Dictionary = NPCDirector.save_state()
	NPCDirector.mark_house_container_looted(SEMI_NPC, "semi_wardrobe_drawer")
	NPCDirector.load_state(state)
	check(not NPCDirector.is_house_container_looted(SEMI_NPC, "semi_wardrobe_drawer"),
			"NPCDirector restores the saved loot state")


## §13.4 / §23: las mismas vías que PERSONNEL dan el domicilio (puesto de RR. HH., chantaje).
func _test_address_routes() -> void:
	_fresh()
	check(not NightOps.knows_home_address(HUMBLE_NPC), "R1: address unknown")
	PlayerState.set_occupation("hr_assistant", "test")
	check(PlayerState.get_personnel_file_level() < Database.get_balance_int("expedientes.nivel_seccion.home"),
			"the HR assistant's file level is below N6")
	check_eq(PlayerState.get_full_file_access_reason(HUMBLE_NPC), "hr_post", "full files by post")
	check(NightOps.knows_home_address(HUMBLE_NPC), "§23 hr_assistant: every address")
	check_eq(_ops.can_follow(HUMBLE_NPC), "", "so the HR assistant can follow anyone home")
	PlayerState.set_occupation("email_worker_3b", "test")
	check(not NightOps.knows_home_address(SEMI_NPC), "back at R1: unknown again")
	NPCDirector.add_grievance(SEMI_NPC, NPCDirectorSystem.GRIEVANCE_BLACKMAILED, 3)
	check_eq(PlayerState.get_full_file_access_reason(SEMI_NPC), "blackmail", "blackmail opens the file")
	check(NightOps.knows_home_address(SEMI_NPC), "a blackmailed victim's address is known")


## §4.3 «seguimiento de un trabajador hasta su domicilio»: solo a quien sale o ya está fuera.
func _test_follow_needs_leaving() -> void:
	_fresh()
	PlayerState.grant_full_file(NIGHT_GUARD, "hr_intrusion")
	check(not NightOps.is_leaving(NIGHT_GUARD), "the night guard is at work at 22:00")
	check_eq(_ops.can_follow(NIGHT_GUARD), NightOps.ERR_NOT_LEAVING, "cannot follow someone at work")
	var result: Dictionary = _ops.follow_home(NIGHT_GUARD)
	check(not bool(result["ok"]) and not _ops.is_active(), "follow_home refuses")
	check_eq(_ops.can_visit(NIGHT_GUARD), "", "but the house can be visited")
	check(NightOps.is_leaving(HUMBLE_NPC), "an office worker is out at 22:00")
	var turnstile: String = ""
	GameClock.set_time(DAY, 18, 30)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if turnstile.is_empty() and NPCDirector.get_location_at(npc.id, 18, 30) == "turnstiles":
			turnstile = npc.id
	check(not turnstile.is_empty() and NightOps.is_leaving(turnstile), "at the turnstiles = leaving")
	check(not NightOps.is_leaving("npc_bernard_lasker"), "still at the desk at 18:30")
	check_eq(NightOps.reason_key(NightOps.ERR_NOT_LEAVING), "NIGHT_ERR_NOT_LEAVING", "reason key")


## §4.3 «Exige el uso de pasamontañas»: allanar y eliminar exigen llevarlo puesto.
func _test_balaclava_required() -> void:
	_fresh()
	check(bool(Database.get_balance("noche.exige_pasamontanas")), "balance flag on")
	Disguise.take_off()
	_start(HUMBLE_NPC)
	check_eq(str(_ops.break_in("window")["reason"]), NightOps.ERR_NO_BALACLAVA, "no break-in bare-faced")
	Disguise.wear("balaclava")
	check(bool(_ops.break_in("window")["ok"]), "masked: in")
	Disguise.take_off()
	check_eq(str(_ops.eliminate_resident([])["reason"]), NightOps.ERR_NO_BALACLAVA,
			"no elimination bare-faced")
	check_eq(NightOps.reason_key(NightOps.ERR_NO_BALACLAVA), "NIGHT_ERR_NO_BALACLAVA", "reason key")
	_ops.leave_house()


## Lo que no cabe se queda en el contenedor (no se destruye ni lo deja «vacío»).
func _test_loot_overflow() -> void:
	_fresh()
	var junk: Array[String] = _fill_inventory()
	check_eq(PlayerState.get_free_slots(), 0, "inventory full")
	var found: Dictionary = {}
	var victim: String = ""
	for npc_id: String in _house_targets("npc_house_semi", TRIALS):
		_start(npc_id)
		_ops.break_in("window")
		var loot: Dictionary = _ops.loot_container("semi_wardrobe_drawer")
		if not (loot["left"] as Array).is_empty():
			found = loot
			victim = npc_id
			break
		_ops.leave_house()
	check(not victim.is_empty(), "a full inventory leaves something behind")
	if victim.is_empty():
		return
	check(not NPCDirector.is_house_container_looted(victim, "semi_wardrobe_drawer"),
			"the container is not marked empty while something is left")
	check_eq(int(_container_info("semi_wardrobe_drawer")["left"]), (found["left"] as Array).size(),
			"get_containers reports what is left")
	for i: int in (found["left"] as Array).size():
		PlayerState.remove_item(junk[i])
	var second: Dictionary = _ops.loot_container("semi_wardrobe_drawer")
	check(bool(second["ok"]) and second["items"] == found["left"], "looting again takes what was left")
	check(NPCDirector.is_house_container_looted(victim, "semi_wardrobe_drawer"), "now it is empty")
	check_eq(str(_ops.loot_container("semi_wardrobe_drawer")["reason"]), NightOps.ERR_EMPTY, "empty")
	_ops.leave_house()


func _fill_inventory() -> Array[String]:
	var added: Array[String] = []
	for item: ItemData in Database.get_all_items():
		if PlayerState.get_free_slots() == 0:
			break
		if InventoryRules.is_stackable(item) or InventoryRules.is_pocket_cash(item) \
				or PlayerState.is_carrying(item.id):
			continue
		if PlayerState.add_item(item.id):
			added.append(item.id)
	return added


func _container_info(container_id: String) -> Dictionary:
	for entry: Dictionary in _ops.get_containers():
		if str(entry["id"]) == container_id:
			return entry
	return {}


func _house_targets(house: String, count: int) -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.home_address == house and NPCDirector.is_at_home(npc.id) and out.size() < count:
			out.append(npc.id)
	return out


## La seguridad privada solo ve al jugador si está dentro; si no, espera en la casa.
func _test_private_security_needs_player_inside() -> void:
	_fresh()
	_start(MANSION_NPC)
	_ops.break_in("window")
	EventBus.room_entered.emit("street", true)
	var wait: float = float(NightOps.house_params(MANSION)["minutos_seguridad_privada"])
	GameClock.advance_minutes(wait + 1.0)
	_ops.update()
	check((_ops.get_operation()["inside_witnesses"] as Array).is_empty(),
			"the guard arrives but the player is out in the street")
	check_eq(_log.count("game_over"), 0, "nobody saw the player")
	EventBus.room_entered.emit(MANSION, true)
	_ops.update()
	var inside: Array = _ops.get_operation()["inside_witnesses"]
	check(inside.size() == 1 and NPCDirector.get_role(str(inside[0])) == "private_security",
			"back inside: the waiting guard sees the player")
	_ops.leave_house()


## La operación viaja en run.json como "scene:NightOps" (SaveSystem).
func _test_save_system_round_trip() -> void:
	var dir: String = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(dir)
	_fresh()
	_start(SEMI_NPC)
	_ops.break_in("window")
	check(SaveSystem.save_run(), "run saved inside the house")
	_ops.reset_for_new_run()
	check(not _ops.is_active(), "reset clears the operation")
	check(SaveSystem.load_run(), "run loaded")
	GameClock.pause()
	check(_ops.is_active() and str(_ops.get_operation()["house"]) == SEMI,
			"SaveSystem hands the operation back")
	check(bool(_ops.get_operation()["entered"]), "still inside")
	_ops.leave_house()
	SaveSystem.delete_run()
	DirAccess.remove_absolute(dir)
	SaveSystem.set_storage_dir("")
	SaveSystem.reset_for_new_run()
	check(not DirAccess.dir_exists_absolute(dir), "the case leaves no files behind")
