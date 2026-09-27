# tracking.gd — Los cinco ejes de seguimiento invisible y la evaluación de finales.
# PROPIETARIO DE: los cinco ejes y la evaluación de finales (§19.12).
# ESCUCHA: nada.
# STUB — implemented in PASO 31. Firmas exactas de §19.12; cuerpos con valores neutros.
class_name TrackingSystem
extends Node


func reset_for_new_run() -> void:
	pass


func add(axis: String, amount: int, source: String) -> void:
	pass


func get_axis(axis: String) -> int:
	return 0


func get_all_axes() -> Dictionary:
	return {}


func get_dominant_axis() -> String:
	return ""


func is_hybrid() -> bool:
	return false


## "empire" | "husk"
func get_ruin_tier() -> String:
	return ""


## Devuelve ending_id.
func evaluate_ending() -> String:
	return ""


func get_snapshot() -> Dictionary:
	return {}


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
