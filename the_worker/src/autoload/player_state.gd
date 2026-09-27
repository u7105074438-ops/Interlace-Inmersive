# player_state.gd — Estado del jugador: ocupación, capital, medidores, inventario, deberes, ejes.
# PROPIETARIO DE: ocupación, capital, reputación, inventario, deberes de la jornada, ejes (§19.3).
# ESCUCHA: nada.
# STUB — implemented in PASO 6. Firmas exactas de §19.3; cuerpos con valores neutros.
class_name PlayerStateSystem
extends Node


func reset_for_new_run() -> void:
	pass


# Ocupación
func get_occupation() -> OccupationData:
	return null


func get_rank() -> int:
	return 0


func get_tier() -> int:
	return 0


func get_clearance() -> int:
	return 0


func set_occupation(id: String, reason: String) -> void:
	pass


func get_personnel_file_level() -> int:
	return 0


# Capital
func get_money() -> int:
	return 0


func add_money(amount: int, source: String) -> void:
	pass


## false si es insuficiente.
func spend_money(amount: int, reason: String) -> bool:
	return false


func can_afford(amount: int) -> bool:
	return false


func get_daily_expenses() -> int:
	return 0


# Medidores
func get_reputation() -> float:
	return 0.0


func modify_reputation(delta: float, reason: String) -> void:
	pass


## Cacheado desde BeliefNet.
func get_suspicion() -> float:
	return 0.0


## Solo BeliefNet invoca.
func _set_suspicion_from_beliefnet(value: float) -> void:
	pass


# Inventario
func get_inventory() -> Array[ItemData]:
	return []


## false si está lleno.
func add_item(item_id: String) -> bool:
	return false


func remove_item(item_id: String) -> bool:
	return false


func has_item(item_id: String) -> bool:
	return false


func has_hot_items() -> bool:
	return false


func get_hot_item_count() -> int:
	return 0


func get_free_slots() -> int:
	return 0


# Deberes
func get_todays_duties() -> Array[Dictionary]:
	return []


func complete_duty(duty_id: String, quality: float, method: String) -> void:
	pass


func fail_duty(duty_id: String) -> void:
	pass


func get_pending_duties() -> Array[Dictionary]:
	return []


func get_consecutive_failures() -> int:
	return 0


# Seguimiento
## "blood" | "gold" | "silk" | "sweat" | "ruin"
func add_tracking(axis: String, amount: int) -> void:
	pass


func get_tracking(axis: String) -> int:
	return 0


func get_dominant_axis() -> String:
	return ""


# Persistencia
func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
