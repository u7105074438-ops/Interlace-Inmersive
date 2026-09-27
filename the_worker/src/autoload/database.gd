# database.gd — Carga, valida y expone en solo lectura todos los datos estáticos de data/.
# PROPIETARIO DE: la totalidad de los datos estáticos cargados desde data/ (§19.1).
# ESCUCHA: nada.
# STUB — implemented in PASO 4. Firmas exactas de §19.1; cuerpos con valores neutros.
class_name DatabaseSystem
extends Node


func reset_for_new_run() -> void:
	pass


# Carga y validación al arrancar
func load_all() -> bool:
	return false


func get_load_errors() -> Array[String]:
	return []


# Acceso a ocupaciones
func get_occupation(id: String) -> OccupationData:
	return null


func get_occupations_by_rank(rank: int) -> Array[OccupationData]:
	return []


func get_occupations_by_tier(tier: int) -> Array[OccupationData]:
	return []


func get_all_occupations() -> Array[OccupationData]:
	return []


# Acceso a salas
func get_room(id: String) -> RoomData:
	return null


@warning_ignore("shadowed_global_identifier")
func get_rooms_by_floor(floor: int) -> Array[RoomData]:
	return []


func get_rooms_by_clearance(max_clearance: int) -> Array[RoomData]:
	return []


func get_all_rooms() -> Array[RoomData]:
	return []


# Acceso a personajes y arquetipos
func get_archetype(id: String) -> ArchetypeData:
	return null


func get_named_npc(id: String) -> NPCData:
	return null


func get_all_named_npcs() -> Array[NPCData]:
	return []


func get_generation_rules(department: String) -> Dictionary:
	return {}


# Acceso a inversores, deberes e ideas
func get_investor(id: String) -> InvestorData:
	return null


func get_all_investors() -> Array[InvestorData]:
	return []


func get_duty_definition(duty_type: String) -> Dictionary:
	return {}


func get_idea_template(department: String) -> Dictionary:
	return {}


# Acceso al balance mediante ruta con puntos
func get_balance(path: String) -> Variant:
	return null


func get_balance_int(path: String) -> int:
	return 0


func get_balance_float(path: String) -> float:
	return 0.0


func get_difficulty_modifier(key: String) -> float:
	return 1.0
