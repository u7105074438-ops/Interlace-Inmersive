# security_case.gd — Cuerpo de test_security: alerta, grabaciones permanentes, sala de monitores, lectores, registro corporal y persistencia (PASO 27).
# PROPIETARIO DE: nada.
# ESCUCHA: alert_level_changed, camera_recorded_player, card_reader_logged, record_destroyed, crime_committed (vía SignalLog).
extends TestCase

const Fx := preload("res://tests/cases/security_fixtures.gd")

var _log: Fx.SignalLog


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "database loaded")
	_log = Fx.SignalLog.new().watch(["alert_level_changed", "camera_recorded_player",
			"card_reader_logged", "record_destroyed", "crime_committed"])
	_test_alert_from_suspicion()
	_test_alert_from_incidents()
	_test_alert_effects()
	_test_footage_is_permanent()
	_test_delete_only_in_monitor_room()
	_test_disguised_footage()
	_test_card_reader_log()
	_test_can_search_player()
	_test_day_signal_wiring()
	_test_restash_can_be_found_again()
	_test_save_load_round_trip()
	_log.stop()


func _test_alert_from_suspicion() -> void:
	check_eq(Security.get_alert_level(), 0, "new run: alert level 0")
	var per_level: float = Fx.bal("seguridad.alerta_sospecha_por_nivel")
	Fx.set_suspicion(per_level * 2.0 + 1.0)
	check_eq(Security.get_alert_level(), 2, "suspicion 41 → alert 2 (⌊s / 20⌋)")
	var change: Array = _log.last("alert_level_changed")
	check(change.size() == 2 and change[0] == 0 and change[1] == 2,
			"alert_level_changed(0, 2) emitted")
	check_eq(Security.get_alert_level_key(), "ALERT_LEVEL_2", "HUD text key of the alert level")
	Fx.set_suspicion(100.0)
	check_eq(Security.get_alert_level(), 5, "suspicion 100 → alert 5 (maximum)")
	Fx.set_suspicion(0.0)
	check_eq(Security.get_alert_level(), 0, "suspicion back to 0 → alert 0")


func _test_alert_from_incidents() -> void:
	var incidents_per_level: int = Database.get_balance_int("seguridad.alerta_incidentes_por_nivel")
	for i: int in incidents_per_level:
		Security.report_incident("object_missing", 0, Fx.SEALED_ROOM, true)
	check_eq(Security.get_alert_level(), 1, "two recent incidents → alert +1")
	Fx.advance_days(Database.get_balance_int("seguridad.alerta_dias_incidente_reciente"))
	check_eq(Security.get_alert_level(), 0, "incidents older than the window no longer count")


func _test_alert_effects() -> void:
	Fx.set_suspicion(60.0)
	var level: int = Security.get_alert_level()
	check_eq(level, 3, "suspicion 60 → alert 3")
	check_near(Security.get_guard_round_frequency(), Fx.bal("seguridad.rondas_base_por_hora")
			+ Fx.bal("seguridad.rondas_extra_por_nivel") * level, 0.001,
			"guard rounds per hour grow with the alert level")
	check_eq(Security.get_guard_perception_bonus(),
			Database.get_balance_int("seguridad.perspicacia_vigilantes_por_nivel") * level,
			"guard perception bonus grows with the alert level")
	var review: float = Security.get_footage_review_probability()
	check_near(review, Fx.bal("seguridad.prob_revision_grabaciones_base")
			+ Fx.bal("seguridad.prob_revision_grabaciones_por_nivel") * level, 0.001,
			"footage review probability grows with the alert level")
	Fx.set_suspicion(100.0)
	check(Security.get_footage_review_probability() > review
			and Security.get_footage_review_probability() <= 1.0, "review probability capped at 1")
	Fx.set_suspicion(0.0)


func _test_footage_is_permanent() -> void:
	var day: int = Security.get_current_day()
	var id: String = Security.register_camera_footage("turnstiles", day, 9)
	check(not id.is_empty(), "register_camera_footage returns a record id")
	var emitted: Array = _log.last("camera_recorded_player")
	check(emitted.size() == 3 and emitted[1] == "turnstiles" and emitted[2] == day,
			"camera_recorded_player(camera, room, day) emitted")
	check(Security.get_footage_for_room("turnstiles", day).has(id), "footage listed for room/day")
	check(Security.get_footage_for_room("turnstiles", day + 1).is_empty(), "not for another day")
	Fx.advance_days(30)
	check(Security.get_footage_for_room("turnstiles", day).has(id),
			"footage is a permanent record: still there 30 days later")


func _test_delete_only_in_monitor_room() -> void:
	var day: int = Security.get_current_day()
	var id: String = Security.register_camera_footage("floor_safe", day, 14)
	Fx.enter_room("wing_3b")
	check(not Security.delete_footage(id), "delete_footage refused outside monitor_room")
	check(Security.get_footage_for_room("floor_safe", day).has(id), "footage survives the attempt")
	Fx.enter_room("monitor_room")
	_log.clear()
	check(Security.delete_footage(id), "delete_footage works from monitor_room")
	check(Security.get_footage_for_room("floor_safe", day).is_empty(), "footage gone")
	var destroyed: Array[String] = []
	for args: Array in _log.of("record_destroyed"):
		destroyed.append(str(args[0]))
	check(destroyed.has(id), "record_destroyed(footage id) emitted")
	var crime: Array = _log.last("crime_committed")
	check(crime.size() == 3 and crime[0] == "footage_deleted"
			and (crime[2] as Dictionary).get("camera_id") == id,
			"crime_committed(footage_deleted) carries the camera id for BeliefNet")
	check(not Security.delete_footage(id), "deleting twice fails")


func _test_disguised_footage() -> void:
	Fx.wear("uniform_cleaning")
	var day: int = Security.get_current_day()
	var id: String = Security.register_camera_footage("turnstiles", day, 10)
	var subject: String = ""
	for entry: Dictionary in Security.get_footage_list():
		if entry["id"] == id:
			subject = str(entry["subject"])
	check_eq(subject, "uniform:uniform_cleaning", "camera records the uniform, not the identity")
	Fx.wear("")


func _test_card_reader_log() -> void:
	var day: int = Security.get_current_day()
	var before: int = Security.get_access_log().size()
	Security.log_card_access("reader_floor_safe", "npc_amelia_cole", day, 11, "floor_safe")
	var emitted: Array = _log.last("card_reader_logged")
	check(emitted == ["reader_floor_safe", "npc_amelia_cole", day, 11],
			"card_reader_logged(reader, owner, day, hour) emitted")
	var log: Array[Dictionary] = Security.get_access_log()
	check_eq(log.size(), before + 1, "access log grew by one")
	var entry: Dictionary = log[log.size() - 1]
	check(entry["reader_id"] == "reader_floor_safe" and entry["card_owner"] == "npc_amelia_cole"
			and entry["room_id"] == "floor_safe" and entry["hour"] == 11,
			"access log keeps reader, card owner, room and hour")
	EventBus.card_reader_logged.emit("elevator_reader@3", "player", day, 12)
	check_eq(Security.get_access_log().size(), before + 2,
			"card reads emitted by the world (elevators) are logged too")


## Umbral de investigations.json body_search (única fuente; «supera» → estricto).
func _test_can_search_player() -> void:
	var rules: Dictionary = Database.get_investigation_params()["body_search"]
	var threshold: float = float(rules["suspicion_threshold"])
	check(is_equal_approx(threshold, 60.0) and bool(rules["if_player_in_shortlist"]),
			"body search: suspicion above 60, or player shortlisted (investigations.json)")
	Fx.set_suspicion(threshold)
	check(not Security.can_search_player(), "suspicion = threshold → no body search")
	Fx.set_suspicion(threshold + 1.0)
	check(Security.can_search_player(), "suspicion above threshold → body search allowed")
	Fx.set_suspicion(0.0)
	check(not Security.can_search_player(), "low suspicion and no case → no body search")
	var case_id: String = Fx.open_witness_case(Fx.OPEN_ROOM, 10)
	Fx.push_to_phase(case_id, InvestigationEngine.PHASE_SHORTLIST)
	check(Security.is_player_in_shortlist(case_id), "witness 4.0 + access 2.0 → player shortlisted")
	check(Security.can_search_player(), "player in an open case's shortlist → body search allowed")


func _test_day_signal_wiring() -> void:
	var day: int = Security.get_current_day()
	EventBus.day_advanced.emit(day + 1)
	check_eq(Security.get_current_day(), day + 1, "day_advanced drives Security's daily tick")


## Un objeto incautado en un escondite y vuelto a esconder allí puede encontrarse de nuevo.
func _test_restash_can_be_found_again() -> void:
	Fx.enter_room("wing_3b")
	EventBus.item_hidden.emit("product_box", "hide_restash")
	var first: String = Security.report_incident("object_missing", 1, "wing_3b", true,
			{"weight": 3.5})
	Fx.push_to_phase(first, InvestigationEngine.PHASE_SHORTLIST)
	var found: int = Security.get_found_items().size()
	check(found >= 1, "the stashed hot item is found in the player's desk")
	Security.resolve_investigation(first, "cold", "")
	Fx.advance_days(Database.get_balance_int("investigaciones.jornadas_respiro_minimo"))
	EventBus.item_hidden.emit("product_box", "hide_restash")
	var second: String = Security.report_incident("inventory_mismatch", 1, "wing_3b", true,
			{"weight": 3.5})
	Fx.push_to_phase(second, InvestigationEngine.PHASE_SHORTLIST)
	check_eq(Security.get_found_items().size(), found + 1,
			"hidden again in the same spot, it can be found by the next search")


func _test_save_load_round_trip() -> void:
	var saved: Dictionary = Security.save_state()
	var text: String = JSON.stringify(saved)
	var footage: int = Security.get_footage_list().size()
	var cases: int = Security.get_all_investigations().size()
	Security.reset_for_new_run()
	check_eq(Security.get_all_investigations().size(), 0, "reset empties the cases")
	Security.load_state(JSON.parse_string(text))
	check_eq(_normalized(Security.save_state()), _normalized(saved),
			"save → JSON → load reproduces the exact state")
	check_eq(Security.get_footage_list().size(), footage, "footage restored")
	check_eq(Security.get_all_investigations().size(), cases, "cases restored")
	var case_id: String = Security.get_all_investigations()[cases - 1].id
	check(Security.is_player_in_shortlist(case_id), "restored case keeps its shortlist")


func _normalized(state: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(state)), "", true)
