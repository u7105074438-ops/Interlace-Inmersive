# news_feed.gd — Capa compartida de noticias y sentimiento.
# PROPIETARIO DE: la capa compartida de noticias y sentimiento (§19.10).
# ESCUCHA: nada.
# STUB — implemented in PASO 35. Firmas exactas de §19.10; cuerpos con valores neutros.
class_name NewsFeedSystem
extends Node


func reset_for_new_run() -> void:
	pass


func publish(headline_id: String, sentiment_delta: float, is_scandal: bool) -> String:
	return ""


## Director de Comunicación.
func bury(news_id: String, by_whom: String) -> bool:
	return false


func fabricate(target: String, headline_id: String) -> String:
	return ""


func get_active_news() -> Array[Dictionary]:
	return []


func get_sentiment_contribution() -> float:
	return 0.0


func get_scandal_count(days: int) -> int:
	return 0


func apply_daily_decay() -> void:
	pass


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
