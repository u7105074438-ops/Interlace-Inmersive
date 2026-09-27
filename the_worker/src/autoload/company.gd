# company.gd — Sillas, promoción del jugador, fundamentales, cifras reportadas y descontento.
# PROPIETARIO DE: sillas, fundamentales, valores reportados y lógica de promoción (§19.8).
# ESCUCHA: nada.
# STUB — implemented in PASO 21 (sillas y promociones) and PASO 32 (fundamentales).
class_name CompanySystem
extends Node


func reset_for_new_run() -> void:
	pass


# Sillas
## "" si está vacante.
func get_seat_holder(occupation_id: String) -> String:
	return ""


func is_seat_vacant(occupation_id: String) -> bool:
	return false


func get_vacant_seats() -> Array[String]:
	return []


func vacate_seat(occupation_id: String, cause: String) -> void:
	pass


func fill_seat(occupation_id: String, npc_id: String) -> void:
	pass


func auto_fill_vacancies() -> void:
	pass


# Promoción del jugador
## Devuelve { allowed: bool, missing: Array[String] }; missing puede contener
## "reputation", "merit", "vacancy".
func can_player_promote_to(occupation_id: String) -> Dictionary:
	var missing: Array[String] = []
	return {"allowed": false, "missing": missing}


func get_available_promotions() -> Array[String]:
	return []


func promote_player(occupation_id: String) -> bool:
	return false


func demote_player(reason: String) -> void:
	pass


func register_merit(source: String, amount: int) -> void:
	pass


func get_recent_merit() -> int:
	return 0


# Fundamentales
## { revenue, costs, profit, growth_expectation, risk_factor }
func get_fundamentals() -> Dictionary:
	return {"revenue": 0.0, "costs": 0.0, "profit": 0.0, "growth_expectation": 0.0,
			"risk_factor": 0.0}


func get_reported_figures() -> Dictionary:
	return {}


## Solo cargos autorizados.
func set_reported_figures(figures: Dictionary) -> void:
	pass


func recalculate_fundamentals() -> void:
	pass


func add_theft_loss(amount: float) -> void:
	pass


func modify_product_quality(delta: float) -> void:
	pass


func modify_brand_strength(delta: float) -> void:
	pass


# Descontento
func get_discontent() -> int:
	return 0


func modify_discontent(delta: int, cause: String) -> void:
	pass


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
