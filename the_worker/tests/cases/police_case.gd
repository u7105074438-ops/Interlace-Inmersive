# police_case.gd — Cuerpo de test_police: testigos con y sin pasamontañas (creencia con identidad y registro en el edificio / sin sujeto), aviso consolidado y despacho desde la comisaría, tiempo de respuesta, llegada con el jugador en la escena, evasión por callejones, tramos que no se gastan antes de la llegada, cerco por quedarse o por agotar tramos, refugio, denuncias del mundo y persistencia (save_state en plena búsqueda y a través de SaveSystem).
# PROPIETARIO DE: nada (el nodo Police que crea vive solo durante el caso; su carpeta de guardado se borra al final).
# ESCUCHA: police_dispatched, police_arrived, police_evaded, game_over, subtitle_posted (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const EPS := 0.001
const HUMBLE := "npc_house_humble"
const MANSION := "npc_house_mansion"
const STREET := "street"
const ALLEYS := "alleys"
const FLAT := "player_flat"
const DAY := 2
const STORAGE_FORMAT := "user://test_police_%d"
const NIGHT_HOUR := 22
const WATCHED: Array[String] = ["police_dispatched", "police_arrived", "police_evaded", "game_over",
		"subtitle_posted"]

var _police: Police = null
var _log: Fixtures.SignalLog = null


func run_case() -> void:
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_police = Police.new()
	add_child(_police)
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_test_identified_witness()
	_test_masked_witness()
	_test_response_times()
	_test_arrest_on_scene()
	_test_alley_evasion()
	_test_alleys_not_spent_before_arrival()
	_test_cordon_staying()
	_test_cordon_out_of_alleys()
	_test_exposed_cordon()
	_test_refuge_rules()
	_test_world_reports_and_alarm()
	_test_alert_expires_and_save()
	_test_pursuit_save_load()
	_test_save_system_round_trip()
	_log.stop()
	_police.queue_free()
	await get_tree().process_frame


## Partida y persecución limpias, jugador en `room` de noche, sin pasamontañas.
func _fresh(room: String) -> void:
	new_run(DEFAULT_SEED)
	SaveSystem.reset_for_new_run()
	_police.reset_for_new_run()
	GameClock.set_time(DAY, NIGHT_HOUR, 0)
	PlayerState.set_disguise("")
	_move(room)
	_log.clear()


func _move(room: String) -> void:
	EventBus.room_entered.emit(room, true)


func _advance(minutes: float) -> void:
	GameClock.advance_minutes(minutes)
	_police.update()


func _role_npc(role: String) -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) == role:
			return npc.id
	return ""


func _records_at(location: String) -> int:
	var count: int = 0
	for rec: Belief in BeliefNet.get_records_about("player"):
		if rec.location == location and rec.record_type == BeliefNetSystem.RECORD_STAMPED_DOCUMENT:
			count += 1
	return count


func _belief_of(holder: String, subject: String) -> Belief:
	for b: Belief in BeliefNet.get_beliefs_held_by(holder):
		if b.subject == subject:
			return b
	return null


func _test_identified_witness() -> void:
	_fresh(HUMBLE)
	var neighbour: String = _role_npc("neighbour")
	check(not neighbour.is_empty(), "the exterior population has neighbours")
	var partial: float = Database.get_balance_float("creencias.certeza_parcial")
	var first: Dictionary = _police.witness_crime(neighbour, "burglary", HUMBLE, partial)
	check(bool(first["identified"]), "without a balaclava the witness recognises the player")
	var belief: Belief = _belief_of(neighbour, "player")
	check(belief != null and belief.fact == "seen_partially", "partial witness: seen_partially about the player")
	check_eq(_records_at(HUMBLE), 1, "the police report reaches the building as a record")
	check_eq(_police.get_state(), Police.STATE_ALERTED, "one partial witness does not consolidate")
	check_eq(_log.count("police_dispatched"), 0, "no unit dispatched yet")
	var resident: String = NPCDirector.get_all_npcs()[0].id
	_police.witness_crime(resident, "burglary", HUMBLE, -1.0)
	var direct: Belief = _belief_of(resident, "player")
	check(direct != null and direct.fact == "caught_redhanded:burglary", "direct witness: caught_redhanded")
	check_eq(_police.get_state(), Police.STATE_DISPATCHED, "direct witness consolidates the alert")
	check_eq(_log.count("police_dispatched"), 1, "police_dispatched emitted once")
	check_eq(_records_at(HUMBLE), 1, "one record per alert, not per witness")
	check(_police.is_identified(), "the alert knows who the player is")


func _test_masked_witness() -> void:
	_fresh(HUMBLE)
	PlayerState.add_item("balaclava")
	check(Disguise.wear("balaclava"), "balaclava on")
	var neighbour: String = _role_npc("neighbour")
	var result: Dictionary = _police.witness_crime(neighbour, "burglary", HUMBLE, -1.0)
	check(not bool(result["identified"]), "with a balaclava nobody is identified")
	check(_belief_of(neighbour, "player") == null, "no belief about the player")
	var unknown: Belief = _belief_of(neighbour, BeliefNetSystem.UNKNOWN_SUBJECT)
	check(unknown != null, "the belief has no determined subject")
	check_eq(_records_at(HUMBLE), 0, "nothing propagates to the building")
	check(bool(result["dispatched"]), "the police are still called")
	check(not _police.is_identified(), "the alert does not know who it was")


func _test_response_times() -> void:
	var base: float = Database.get_balance_float("policia.minutos_respuesta_base")
	check_near(Police.response_time_for(HUMBLE), base * 1.25, EPS, "humble house: slow response")
	check_near(Police.response_time_for(MANSION), base * 0.6, EPS, "mansion: priority response")
	check_near(Police.response_time_for("transport_stop"), base, EPS, "unlisted room: base time")
	_fresh(MANSION)
	_police.dispatch(MANSION)
	var args: Array = _log.last("police_dispatched")
	check(args.size() == 2 and str(args[0]) == MANSION, "police_dispatched(target)")
	check_eq(_police.get_origin(), Database.get_balance("policia.sala_comisaria"),
			"the unit leaves from the police station")
	check_near(float(args[1]), base * 0.6, EPS, "police_dispatched carries the response time (minutes)")
	_advance(base * 0.6 - 1.0)
	check_eq(_police.get_state(), Police.STATE_DISPATCHED, "still on the way one minute before")
	check_near(_police.get_eta(), 1.0, EPS, "eta counts down with game minutes")
	check_eq(_log.count("police_arrived"), 0, "not arrived yet")


func _test_arrest_on_scene() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_log.count_for("police_arrived", HUMBLE), 1, "police_arrived at the house")
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "the player was still inside: arrest")
	var over: Array = _log.last("game_over")
	check(over.size() == 3 and str(over[0]) == "arrested_by_police", "game_over(arrested_by_police)")
	check_eq(str(over[1]) if over.size() == 3 else "", "the_file", "arrest ends as THE FILE")


func _test_alley_evasion() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(STREET)
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_police.get_state(), Police.STATE_SEARCHING, "left the scene: the police search")
	check_eq(_log.count("game_over"), 0, "no arrest on arrival")
	_move(ALLEYS)
	check_eq(_police.get_alleys_left(), 2, "entering the alleys uses one stretch")
	_advance(10.0)
	check_near(_police.get_hidden_minutes(), 10.0, EPS, "hidden time accumulates in the alley")
	_police.enter_hiding("alley_dumpster_west")
	_advance(10.0)
	_police.enter_hiding("alley_dumpster_east")
	check_eq(_police.get_alleys_left(), 0, "three stretches used")
	_advance(9.0)
	check_eq(_log.count("police_evaded"), 0, "29 minutes hidden is not enough")
	_advance(2.0)
	check_eq(_log.count("police_evaded"), 1, "30 minutes hidden through the alleys: police_evaded")
	check_eq(_police.get_state(), Police.STATE_IDLE, "the alert is over")
	check_eq(_log.count("game_over"), 0, "evasion is not an arrest")


func _test_cordon_staying() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(ALLEYS)
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_police.get_state(), Police.STATE_SEARCHING, "hiding in the alley on arrival")
	_advance(Database.get_balance_float("policia.minutos_por_callejon") + 1.0)
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "staying too long in one alley: cordon")
	check_eq(_log.count_for("police_arrived", ALLEYS), 1, "the cordon closes on the alley")
	check_eq(str(_log.last("game_over")[0]), "arrested_by_police", "cordon = arrest")


func _test_cordon_out_of_alleys() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(STREET)
	_advance(Police.response_time_for(HUMBLE))
	_move(ALLEYS)
	_advance(5.0)
	_police.enter_hiding("alley_dumpster_west")
	_advance(5.0)
	_police.enter_hiding("alley_dumpster_east")
	_advance(5.0)
	check_eq(_police.get_alleys_left(), 0, "all stretches used after 15 minutes")
	_police.enter_hiding("alley_dumpster_west")
	_advance(1.0)
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "no alleys left: the cordon closes")


func _test_exposed_cordon() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(STREET)
	_advance(Police.response_time_for(HUMBLE))
	var cordon: float = Database.get_balance_float("policia.minutos_cerco")
	_advance(cordon - 1.0)
	check_eq(_police.get_state(), Police.STATE_SEARCHING, "exposed but not yet surrounded")
	_advance(1.5)
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "exposed in the street: cordon and arrest")
	check_eq(_log.count_for("police_arrived", STREET), 1, "police_arrived where the player is")


func _test_refuge_rules() -> void:
	_fresh(HUMBLE)
	PlayerState.add_item("balaclava")
	Disguise.wear("balaclava")
	_police.witness_crime(_role_npc("neighbour"), "burglary", HUMBLE, -1.0)
	_move(FLAT)
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_police.get_cover(), Police.COVER_REFUGE, "unknown identity: home is a refuge")
	_advance(Database.get_balance_float("policia.minutos_evasion") + 0.5)
	check_eq(_log.count("police_evaded"), 1, "masked and home: evaded")
	_fresh(HUMBLE)
	_police.witness_crime(_role_npc("neighbour"), "burglary", HUMBLE, -1.0)
	_move(FLAT)
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_police.get_cover(), Police.COVER_EXPOSED, "identified: they know where you live")
	_advance(Database.get_balance_float("policia.minutos_cerco") + 0.5)
	check_eq(_police.get_state(), Police.STATE_ARRESTED, "identified player arrested at home")


func _test_world_reports_and_alarm() -> void:
	_fresh(STREET)
	EventBus.npc_reported_player.emit(_role_npc("neighbour"), "partial_witness", 0.8, "wing_3b")
	check_eq(_police.get_state(), Police.STATE_IDLE, "a report inside the building is Security's")
	EventBus.npc_reported_player.emit(_role_npc("neighbour"), "direct_witness", 4.0, STREET)
	check_eq(_police.get_state(), Police.STATE_DISPATCHED, "a witness who decides to report outside calls the police")
	check(_police.is_identified(), "an unmasked player is recognised by the world witness")
	check_eq(_records_at(STREET), 1, "the identified world report reaches the building as a record")
	EventBus.npc_reported_player.emit(_role_npc("neighbour"), "partial_witness", 0.8, STREET)
	check_eq(_records_at(STREET), 1, "still one record per alert")
	_fresh(STREET)
	PlayerState.add_item("balaclava")
	Disguise.wear("balaclava")
	EventBus.npc_reported_player.emit(_role_npc("neighbour"), "direct_witness", 4.0, STREET)
	check(not _police.is_identified() and _records_at(STREET) == 0,
			"a masked player leaves no record from a world report")
	_fresh(MANSION)
	check(_police.report_alarm(MANSION), "an alarm dispatches at once")
	check_near(_police.get_eta(), Police.response_time_for(MANSION), EPS, "alarm response time")
	var subtitles: Array[String] = []
	for args: Array in _log.all("subtitle_posted"):
		subtitles.append(str(args[0]))
	check(subtitles.has(Police.SUB_ALARM) and subtitles.has(Police.SUB_SIREN), "alarm and siren subtitles")
	check(not _police.report_alarm(MANSION), "a second alarm does not dispatch twice")


func _test_alert_expires_and_save() -> void:
	_fresh(HUMBLE)
	_police.witness_crime(_role_npc("neighbour"), "burglary", HUMBLE, 0.35)
	var saved: Dictionary = _police.save_state()
	var copy: Police = Police.new()
	copy.load_state(saved)
	check_eq(copy.get_state(), Police.STATE_ALERTED, "save/load keeps the alert")
	check_near(copy.get_alert_certainty(), 0.35, EPS, "save/load keeps the certainty")
	copy.free()
	GameClock.advance_to_next_day()
	check_eq(_police.get_state(), Police.STATE_IDLE, "an unconsolidated alert expires overnight")


## PASO 39 / §22.16: los tramos de callejón se cuentan en la persecución, no mientras la unidad
## está en camino (pasearse por los callejones antes de la llegada no los gasta).
func _test_alleys_not_spent_before_arrival() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	for i: int in 3:
		_move(STREET)
		_advance(1.0)
		_move(ALLEYS)
		_police.enter_hiding("alley_dumpster_west")
		_advance(1.0)
	check_eq(_police.get_state(), Police.STATE_DISPATCHED, "the unit is still on its way")
	check_eq(_police.get_alleys_left(), Database.get_balance_int("policia.callejones"),
			"walking the alleys before arrival spends no stretch")
	_advance(Police.response_time_for(HUMBLE))
	check_eq(_police.get_state(), Police.STATE_SEARCHING, "arrival: the search starts")
	_advance(0.5)
	check_eq(_police.get_state(), Police.STATE_SEARCHING,
			"hiding in the alley right after arrival is no cordon")
	check_eq(_police.get_alleys_left(), Database.get_balance_int("policia.callejones") - 1,
			"the alley the player is in becomes the first stretch")


## save_state/load_state en plena búsqueda (tramos, cerco, ocultación, comisaría).
func _test_pursuit_save_load() -> void:
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(STREET)
	_advance(Police.response_time_for(HUMBLE))
	_advance(3.0)
	_move(ALLEYS)
	_advance(4.0)
	_police.enter_hiding("alley_dumpster_west")
	_advance(2.0)
	var saved: Dictionary = _police.save_state()
	var copy: Police = Police.new()
	copy.load_state(JSON.parse_string(JSON.stringify(saved)))
	check_eq(copy.get_state(), Police.STATE_SEARCHING, "mid-pursuit state survives")
	check_eq(copy.get_origin(), _police.get_origin(), "origin survives")
	check_near(copy.get_search_minutes_left(), _police.get_search_minutes_left(), EPS, "search left")
	check_near(copy.get_cordon_minutes_left(), _police.get_cordon_minutes_left(), EPS, "cordon left")
	check_near(copy.get_hidden_minutes(), _police.get_hidden_minutes(), EPS, "hidden minutes")
	check_eq(copy.get_alleys_left(), _police.get_alleys_left(), "stretches used")
	check_near(copy.get_alley_minutes_left(), _police.get_alley_minutes_left(), EPS, "stretch minutes")
	check_eq(copy.save_state(), saved, "identical after a JSON round trip")
	copy.free()


## La persecución viaja en run.json como "scene:Police" (SaveSystem).
func _test_save_system_round_trip() -> void:
	var dir: String = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(dir)
	_fresh(HUMBLE)
	_police.dispatch(HUMBLE)
	_move(STREET)
	_advance(Police.response_time_for(HUMBLE) + 2.0)
	var before: Dictionary = _police.save_state()
	check(SaveSystem.save_run(), "run saved during the search")
	_police.reset_for_new_run()
	check_eq(_police.get_state(), Police.STATE_IDLE, "reset clears the pursuit")
	check(SaveSystem.load_run(), "run loaded")
	GameClock.pause()
	check_eq(_police.get_state(), Police.STATE_SEARCHING, "SaveSystem hands the pursuit back")
	check_near(_police.get_cordon_minutes_left(), float(before["cordon_left"]), EPS,
			"with its cordon clock")
	SaveSystem.delete_run()
	DirAccess.remove_absolute(dir)
	SaveSystem.set_storage_dir("")
	SaveSystem.reset_for_new_run()
	check(not DirAccess.dir_exists_absolute(dir), "the case leaves no files behind")
