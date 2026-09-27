# belief_net.gd — Almacena y gestiona todas las creencias del mundo.
# PROPIETARIO DE: el conjunto de creencias, su decaimiento, los registros y el cálculo de sospecha.
# ESCUCHA: nada.
# STUB — implemented in PASO 13. Firmas exactas de §19.4; cuerpos con valores neutros.
class_name BeliefNetSystem
extends Node


func reset_for_new_run() -> void:
	pass


# Creación
func create_belief(holder: String, subject: String, fact: String,
		certainty: float, source: String, location: String) -> String:
	return ""


func create_record(record_type: String, subject: String,
		weight: float, location: String) -> String:
	return ""


# Consulta
func get_beliefs_about(subject: String) -> Array[Belief]:
	return []


func get_beliefs_held_by(holder: String) -> Array[Belief]:
	return []


func get_belief(id: String) -> Belief:
	return null


func get_records_about(subject: String) -> Array[Belief]:
	return []


func count_credible_beliefs_about(subject: String, min_certainty: float) -> int:
	return 0


# Modificación
func reinforce_belief(id: String, additional_certainty: float) -> void:
	pass


func destroy_record(id: String, method: String) -> bool:
	return false


func transfer_belief(id: String, to_holder: String, degradation: float) -> String:
	return ""


# Sospecha
func calculate_player_suspicion() -> float:
	return 0.0


## Para el panel de depuración.
func get_suspicion_breakdown() -> Array[Dictionary]:
	return []


# Mantenimiento
## Invocado por day_advanced.
func apply_daily_decay() -> void:
	pass


# Persistencia
func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
