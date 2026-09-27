# save_system.gd — Persistencia: partida en curso (run.json) y perfil (profile.json).
# PROPIETARIO DE: los dos archivos de persistencia (§19.13).
# ESCUCHA: nada.
# STUB — implemented in PASO 31. Firmas exactas de §19.13; cuerpos con valores neutros.
class_name SaveSystemNode
extends Node

const RUN_PATH := "user://run.json"
const PROFILE_PATH := "user://profile.json"
const SAVE_VERSION := 1


func reset_for_new_run() -> void:
	pass


## Escritura atómica: run.json.tmp → verificar → renombrar.
func save_run() -> bool:
	return false


func load_run() -> bool:
	return false


## Al perder la partida.
func delete_run() -> void:
	pass


func run_exists() -> bool:
	return false


func save_profile() -> bool:
	return false


func load_profile() -> bool:
	return false


func unlock_ending(ending_id: String) -> void:
	pass


func get_unlocked_endings() -> Array[String]:
	return []


func get_setting(key: String) -> Variant:
	return null


func set_setting(key: String, value: Variant) -> void:
	pass
