# market.gd — Cotización, histórico, inversores, confianza agregada y cartera del jugador.
# PROPIETARIO DE: cotización, histórico, inversores, confianza agregada, cartera (§19.9).
# ESCUCHA: nada.
# STUB — implemented in PASO 33 (cotización) and PASO 34 (inversores y presentación).
class_name MarketSystem
extends Node


func reset_for_new_run() -> void:
	pass


# Cotización
func get_price() -> float:
	return 0.0


func get_intrinsic_value() -> float:
	return 0.0


func get_price_history(days: int) -> Array[float]:
	return []


func get_momentum() -> float:
	return 0.0


func get_sentiment() -> float:
	return 0.0


func tick_hourly() -> void:
	pass


# Inversores
func get_investor_confidence(investor_id: String) -> int:
	return 0


func modify_investor_confidence(investor_id: String, delta: int, reason: String) -> void:
	pass


func get_aggregate_confidence() -> float:
	return 0.0


func get_quarterly_target() -> float:
	return 0.0


func is_meeting_target() -> bool:
	return false


# Presentación de resultados
## Devuelve { quality: float, confidence_changes: Dictionary, sentiment_delta: float }.
func conduct_quarterly_presentation(preparation: float, allies_present: int) -> Dictionary:
	return {"quality": 0.0, "confidence_changes": {}, "sentiment_delta": 0.0}


# Cartera del jugador
func get_player_shares() -> int:
	return 0


func buy_shares(quantity: int) -> bool:
	return false


func sell_shares(quantity: int) -> bool:
	return false


func get_portfolio_value() -> float:
	return 0.0


func get_dividend_income() -> int:
	return 0


func get_board_votes() -> int:
	return 0


# Información privilegiada
func register_insider_operation(volume: int) -> void:
	pass


func get_insider_pattern_score() -> float:
	return 0.0


## Solo R25+.
func get_upcoming_news(days_ahead: int) -> Array[String]:
	return []


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
