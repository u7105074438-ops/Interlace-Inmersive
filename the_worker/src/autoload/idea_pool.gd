# idea_pool.gd — Las ideas vivas del mundo: generación, adquisición, presentación y caducidad.
# PROPIETARIO DE: las ideas vivas del mundo (§19.11).
# ESCUCHA: nada.
# STUB — implemented in PASO 23 (and PASO 24, sala Aurora). Firmas exactas de §19.11.
class_name IdeaPoolSystem
extends Node


func reset_for_new_run() -> void:
	pass


func generate_for_npc(npc_id: String) -> String:
	return ""


func get_idea(idea_id: String) -> Idea:
	return null


func get_ideas_by_owner(npc_id: String) -> Array[Idea]:
	return []


func get_available_ideas() -> Array[Idea]:
	return []


## De personajes eliminados.
func get_unclaimed_ideas() -> Array[Idea]:
	return []


func acquire(idea_id: String, method: String) -> bool:
	return false


## Devuelve { merit: int, contested: bool, contest_result: String }.
func present(idea_id: String) -> Dictionary:
	return {"merit": 0, "contested": false, "contest_result": ""}


func contest(idea_id: String, accuser: String) -> String:
	return ""


func expire_stale_ideas() -> int:
	return 0


func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
