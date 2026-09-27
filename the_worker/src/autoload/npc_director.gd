# npc_director.gd — Estado completo de los personajes: población, rutinas, ánimo, registro, LOD.
# PROPIETARIO DE: personajes, rutinas, ánimo, registro de relaciones y nivel de detalle (§19.5).
# ESCUCHA: nada.
# STUB — implemented in PASO 9. Firmas exactas de §19.5; cuerpos con valores neutros.
class_name NPCDirectorSystem
extends Node


## Vacía la población. generate_population() la (re)crea.
func reset_for_new_run() -> void:
	pass


# Población
func generate_population() -> void:
	pass


func get_npc(id: String) -> NPCRuntime:
	return null


func get_all_npcs() -> Array[NPCRuntime]:
	return []


func get_npcs_in_room(room_id: String) -> Array[NPCRuntime]:
	return []


func get_npcs_by_archetype(archetype: String) -> Array[NPCRuntime]:
	return []


func get_npc_by_occupation(occupation_id: String) -> NPCRuntime:
	return null


# Rasgos
func get_trait(npc_id: String, trait_name: String) -> int:
	return 0


func get_all_traits(npc_id: String) -> Dictionary:
	return {}


## Modulado por sospecha.
func get_effective_perception(npc_id: String) -> int:
	return 0


# Registro de relaciones
func get_ledger(npc_id: String) -> Dictionary:
	return {}


func add_grievance(npc_id: String, type: String, severity: int) -> void:
	pass


func add_favour(npc_id: String, type: String, magnitude: int) -> void:
	pass


func get_affection(npc_id: String) -> int:
	return 0


func get_fear(npc_id: String) -> int:
	return 0


func get_debt(npc_id: String) -> int:
	return 0


# Rutinas y ubicación
func get_current_location(npc_id: String) -> String:
	return ""


func get_scheduled_location(npc_id: String, band: String) -> String:
	return ""


func override_routine(npc_id: String, band: String, location: String) -> void:
	pass


func is_slacker(npc_id: String) -> bool:
	return false


# Estado vital
## Expulsión o eliminación.
func remove_npc(npc_id: String, cause: String) -> void:
	pass


func is_alive(npc_id: String) -> bool:
	return false


# Nivel de detalle
## 0 completo, 1 medio, 2 estadístico.
func set_lod(npc_id: String, level: int) -> void:
	pass


func get_lod(npc_id: String) -> int:
	return 0


func force_full_lod(npc_id: String, reason: String) -> void:
	pass


# Persistencia
func save_state() -> Dictionary:
	return {}


func load_state(data: Dictionary) -> void:
	pass
