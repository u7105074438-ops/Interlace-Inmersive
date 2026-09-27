# event_bus_case.gd — Cuerpo de test_event_bus: catálogo §18.2 completo, emisión y recepción.
# PROPIETARIO DE: nada.
# ESCUCHA: todas las señales de EventBus (conexión temporal para comprobar la recepción).
extends TestCase

## Catálogo exacto de §18.2: señal → ["parámetro:Tipo", ...].
const CATALOGUE: Dictionary = {
	# PERCEPCIÓN Y SIGILO
	"player_seen_partially": ["npc_id:String", "certainty:float", "location:String"],
	"player_caught_redhanded": ["npc_id:String", "crime_type:String", "witnesses:int"],
	"player_lost_from_sight": ["npc_id:String"],
	"noise_emitted": ["position:Vector2", "radius:float", "source:String"],
	"camera_recorded_player": ["camera_id:String", "room_id:String", "day:int"],
	"card_reader_logged": ["reader_id:String", "card_owner:String", "day:int", "hour:int"],
	# CREENCIAS Y SOCIAL
	"belief_created": ["belief_id:String", "holder:String", "subject:String", "certainty:float"],
	"belief_decayed": ["belief_id:String", "new_certainty:float"],
	"belief_forgotten": ["belief_id:String"],
	"record_created": ["record_id:String", "record_type:String", "weight:float"],
	"record_destroyed": ["record_id:String", "method:String"],
	"rumor_spread": ["from_npc:String", "to_npc:String", "belief_id:String"],
	"suspicion_changed": ["old_value:float", "new_value:float"],
	"reputation_changed": ["old_value:float", "new_value:float"],
	# SOBORNOS Y RELACIONES
	"bribe_offered": ["npc_id:String", "amount:int", "favour_type:String"],
	"bribe_result": ["npc_id:String", "accepted:bool", "outcome:String"],
	"grievance_added": ["npc_id:String", "grievance_type:String", "severity:int"],
	"favour_added": ["npc_id:String", "favour_type:String", "magnitude:int"],
	"blackmail_initiated": ["npc_id:String", "target:String", "leverage:String"],
	# IDEAS Y TRABAJO
	"idea_generated": ["idea_id:String", "owner:String", "quality:int", "department:String"],
	"idea_acquired": ["idea_id:String", "method:String"],
	"idea_expired": ["idea_id:String"],
	"idea_presented": ["idea_id:String", "presenter:String", "merit_gained:int"],
	"idea_contested": ["idea_id:String", "accuser:String", "result:String"],
	"duty_assigned": ["duty_id:String", "duty_type:String", "deadline_hour:int"],
	"duty_completed": ["duty_id:String", "quality:float", "method:String"],
	"duty_failed": ["duty_id:String", "consequence:String"],
	"assist_used": ["task_type:String", "result_quality:String"],
	# PROGRESIÓN
	"occupation_changed": ["old_id:String", "new_id:String", "reason:String"],
	"seat_vacated": ["occupation_id:String", "previous_holder:String", "cause:String"],
	"seat_filled": ["occupation_id:String", "new_holder:String"],
	"promotion_available": ["occupation_ids:Array"],
	"promotion_declined": ["occupation_id:String"],
	"merit_gained": ["source:String", "amount:int"],
	"clearance_changed": ["old_level:int", "new_level:int"],
	# SEGURIDAD E INVESTIGACIÓN
	"alert_level_changed": ["old_level:int", "new_level:int"],
	"investigation_opened": ["case_id:String", "incident_type:String", "severity:int"],
	"investigation_phase_advanced": ["case_id:String", "new_phase:int"],
	"evidence_added": ["case_id:String", "evidence_type:String", "weight:float",
			"points_to:String"],
	"suspect_list_formed": ["case_id:String", "suspects:Array"],
	"interrogation_started": ["case_id:String", "interrogator:String"],
	"investigation_resolved": ["case_id:String", "verdict:String", "culprit:String"],
	"case_went_cold": ["case_id:String"],
	"case_revived": ["case_id:String", "trigger:String"],
	"body_discovered": ["body_id:String", "room_id:String"],
	"police_dispatched": ["target_location:String", "response_time:float"],
	# ECONOMÍA Y NOTICIAS
	"news_published": ["headline_id:String", "sentiment_delta:float", "is_scandal:bool"],
	"news_buried": ["headline_id:String", "by_whom:String"],
	"fundamentals_updated": ["revenue:float", "costs:float", "risk:float"],
	"quarter_reported": ["real_figures:Dictionary", "reported_figures:Dictionary"],
	"audit_fuse_lit": ["discrepancy:float", "weeks_until_check:int"],
	"audit_triggered": ["discrepancy_found:bool"],
	"stock_price_updated": ["price:float", "delta_percent:float"],
	"investor_confidence_changed": ["investor_id:String", "old_value:int", "new_value:int"],
	"insider_pattern_detected": ["operations_count:int"],
	# MUNDO Y TIEMPO
	"day_advanced": ["day_number:int"],
	"time_band_changed": ["old_band:String", "new_band:String"],
	"week_closed": ["week_number:int"],
	"month_closed": ["month_number:int"],
	"quarter_closed": ["quarter_number:int"],
	"room_entered": ["room_id:String", "by_player:bool"],
	"room_exited": ["room_id:String", "by_player:bool"],
	"floor_changed": ["old_floor:int", "new_floor:int"],
	"strike_discontent_changed": ["old_value:int", "new_value:int"],
	"strike_started": [],
	"strike_resolved": ["resolution:String"],
	# FIN DE PARTIDA
	"ownership_documents_obtained": [],
	"ownership_notarised": [],
	"game_over": ["cause:String", "ending_id:String", "tracking_snapshot:Dictionary"],
}
const EXPECTED_SIGNAL_COUNT := 69

## Las 14 autoloads de BUILD_NOTES §2: nombre → class_name.
const AUTOLOADS: Dictionary = {
	"EventBus": "EventBusNode", "Database": "DatabaseSystem", "GameClock": "GameClockSystem",
	"PlayerState": "PlayerStateSystem", "BeliefNet": "BeliefNetSystem",
	"NPCDirector": "NPCDirectorSystem", "SocialGraph": "SocialGraphSystem",
	"Security": "SecuritySystem", "Company": "CompanySystem", "Market": "MarketSystem",
	"NewsFeed": "NewsFeedSystem", "IdeaPool": "IdeaPoolSystem", "Tracking": "TrackingSystem",
	"SaveSystem": "SaveSystemNode",
}

var _received: Array = []
var _receive_count: int = 0


func run_case() -> void:
	_check_autoloads()
	check_eq(CATALOGUE.size(), EXPECTED_SIGNAL_COUNT,
			"the §18.2 catalogue in this test is complete")
	var declared: Dictionary = _declared_signals()
	for signal_name: String in CATALOGUE:
		_check_signal(signal_name, declared)
	_report_extensions(declared)
	check(EventBusNode.DEBUG_SIGNALS == false, "DEBUG_SIGNALS exists and is false (§18.4)")
	check(EventBus.has_method("_log"), "EventBus has _log(signal_name, args) (§18.4)")
	await get_tree().process_frame


func _check_autoloads() -> void:
	var names: Array = AUTOLOADS.keys()
	for i: int in names.size():
		var node: Node = autoload(names[i])
		var expected_class: String = AUTOLOADS[names[i]]
		check(node != null, "autoload %s is registered" % names[i])
		if node == null or node.get_script() == null:
			continue
		check_eq(node.get_script().get_global_name(), StringName(expected_class),
				"autoload %s has class_name %s" % [names[i], expected_class])
		check_eq(node.get_index(), i, "autoload %s is registered in position %d" % [names[i], i])


func _declared_signals() -> Dictionary:
	var out: Dictionary = {}
	for info: Dictionary in EventBus.get_script().get_script_signal_list():
		out[info["name"]] = info
	return out


func _check_signal(signal_name: String, declared: Dictionary) -> void:
	if not check(declared.has(signal_name), "signal %s exists" % signal_name):
		return
	var expected: Array = CATALOGUE[signal_name]
	var args: Array = declared[signal_name]["args"]
	var actual: Array = []
	for arg: Dictionary in args:
		actual.append("%s:%s" % [arg["name"], type_string(arg["type"])])
	check_eq(actual, expected, "signal %s has the exact typed parameters" % signal_name)
	_check_emission(signal_name, expected)


func _check_emission(signal_name: String, expected: Array) -> void:
	var payload: Array = []
	for param: String in expected:
		payload.append(_dummy_value(param.get_slice(":", 1)))
	var receiver: Callable = func(...args: Array) -> void:
		_received = args
		_receive_count += 1
	_received = []
	_receive_count = 0
	EventBus.connect(signal_name, receiver)
	EventBus.callv("emit_signal", [signal_name] + payload)
	EventBus.disconnect(signal_name, receiver)
	check(_receive_count == 1 and _received == payload,
			"signal %s is emitted and received with its %d argument(s)" % [signal_name,
			payload.size()])


func _dummy_value(type_name: String) -> Variant:
	match type_name:
		"String":
			return "dummy"
		"int":
			return 7
		"float":
			return 0.25
		"bool":
			return true
		"Vector2":
			return Vector2(3.0, 4.0)
		"Array":
			return ["a", "b"]
		"Dictionary":
			return {"k": 1}
	return null


func _report_extensions(declared: Dictionary) -> void:
	for signal_name: String in declared:
		if not CATALOGUE.has(signal_name):
			print("INFO: EventBus extension signal (not in §18.2): %s" % signal_name)
