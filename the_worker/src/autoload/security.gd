# security.gd — Nivel de alerta, cámaras, investigaciones activas y casos fríos.
# PROPIETARIO DE: nivel de alerta, cámaras, investigaciones activas y casos fríos (§19.7).
# ESCUCHA: nada.
# STUB — implemented in PASO 27 (vigilancia) and PASO 28/30 (investigaciones, casos fríos).
class_name SecuritySystem
extends Node


func reset_for_new_run() -> void:
	pass


# Alerta
## 0 a 5.
func get_alert_level() -> int:
	return 0


func recalculate_alert_level() -> void:
	pass


# Cámaras y registros
func register_camera_footage(room_id: String, day: int, hour: int) -> String:
	return ""


## Solo desde sala de monitores.
func delete_footage(footage_id: String) -> bool:
	return false


func get_footage_for_room(room_id: String, day: int) -> Array[String]:
	return []


# Investigaciones
func open_investigation(incident_type: String, severity: int, location: String) -> String:
	return ""


func get_investigation(case_id: String) -> Investigation:
	return null


func get_active_investigations() -> Array[Investigation]:
	return []


func get_cold_cases() -> Array[Investigation]:
	return []


func add_evidence(case_id: String, evidence_type: String, weight: float, points_to: String) -> void:
	pass


func advance_phase(case_id: String) -> void:
	pass


func resolve_investigation(case_id: String, verdict: String, culprit: String) -> void:
	pass


func revive_cold_case(case_id: String, trigger: String) -> void:
	pass


## Solo Auditor Jefe.
func close_case_permanently(case_id: String) -> bool:
	return false


# Consulta de riesgo
func get_case_weight_against(subject: String, case_id: String) -> float:
	return 0.0


func is_player_in_shortlist(case_id: String) -> bool:
	return false


func can_search_player() -> bool:
	return false


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
