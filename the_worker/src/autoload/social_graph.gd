# social_graph.gd — Vínculos entre personajes y propagación de creencias en los corrillos.
# PROPIETARIO DE: los vínculos entre personajes y la propagación de creencias (§19.6).
# ESCUCHA: nada.
# STUB — implemented in PASO 15. Firmas exactas de §19.6; cuerpos con valores neutros.
class_name SocialGraphSystem
extends Node


## Vacía el grafo. build_initial_graph() lo (re)construye.
func reset_for_new_run() -> void:
	pass


func build_initial_graph() -> void:
	pass


func add_link(from_npc: String, to_npc: String, link_type: String, strength: float) -> void:
	pass


func remove_link(from_npc: String, to_npc: String) -> void:
	pass


func get_links(npc_id: String) -> Array[Dictionary]:
	return []


func get_link_strength(from_npc: String, to_npc: String) -> float:
	return 0.0


func get_neighbours(npc_id: String, min_strength: float) -> Array[String]:
	return []


## Devuelve nº de propagaciones.
func propagate_at_gathering(gathering_id: String) -> int:
	return 0


func inject_rumour(target_npc: String, fact: String, certainty: float) -> String:
	return ""


## Director de Comunicación.
func kill_rumour(belief_fact: String) -> int:
	return 0


func get_gathering_participants(gathering_id: String) -> Array[String]:
	return []


func is_isolated(npc_id: String) -> bool:
	return false


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
