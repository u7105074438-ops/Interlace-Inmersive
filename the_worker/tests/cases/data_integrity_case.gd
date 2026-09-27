# data_integrity_case.gd — Cuerpo de test_data_integrity: recuentos, rangos, balance y referencias.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Manual §21 y PASO 4: 50 ocupaciones sin ids repetidos, 12 arquetipos, R0..R33 completos,
## balance.json leído correctamente, 23 nominados, 6 inversores, 9 finales, 166 salas con ids
## únicos entre archivos y todas las referencias cruzadas válidas (Database sin errores ni avisos).

const EXPECTED_OCCUPATIONS := 50
const EXPECTED_ARCHETYPES := 12
const EXPECTED_NAMED_NPCS := 23
const EXPECTED_INVESTORS := 6
const EXPECTED_ENDINGS := 9
const EXPECTED_ROOMS := 166
const MIN_RANK := 0
const MAX_RANK := 33
const MAX_PRINTED_PROBLEMS := 60
const ROOMS_DIR := "res://data/rooms/%s.json"
## Valores literales de §25 para comprobar la lectura por ruta con puntos.
const BALANCE_SPOT_CHECKS: Dictionary = {
	"percepcion.cono_angulo_base": 75.0,
	"percepcion.umbral_parcial": 0.45,
	"investigaciones.pesos_evidencia.cuerpo_hallado": 12.0,
	"investigaciones.umbral_condena_grave": 10.0,
	"economia.dinero_inicial": 120,
	"economia.estatus_por_escalon.8": 120,
	"tiempo.minutos_reales_por_jornada": 11.0,
	"ruido.radio_esprint": 9.0,
	"creencias.decaimiento_diario": 0.08,
	"sobornos.probabilidad_maxima": 0.95,
	"mercado.precio_inicial": 42.5,
	"ideas.umbral_diferencia_choque": 20,
	"deberes.fallos_para_expulsion": 5,
	"descontento.umbral_huelga": 70,
	"seguimiento.umbral_ruina_cascaron": 150,
	"lod.max_agentes_total": 150,
	"dificultad.auditoria.precio_soborno": 1.25,
	"dificultad.interno.decaimiento_sospecha": 1.4,
}
## Objetos que exige el contrato de PASO 4 (§11.3) → categoría.
const REQUIRED_ITEMS: Dictionary = {
	"keys_basic": "ordinary", "stamp": "ordinary", "phone": "ordinary", "own_card": "ordinary",
	"food_basic": "ordinary", "food_premium": "ordinary", "office_supplies": "ordinary",
	"executive_suit": "ordinary",
	"product_pair": "compromising", "product_box": "compromising",
	"product_pallet_note": "compromising", "foreign_document": "compromising",
	"stolen_card": "compromising", "cloned_card": "compromising",
	"uniform_security": "compromising", "uniform_cleaning": "compromising",
	"uniform_maintenance": "compromising", "balaclava": "compromising",
	"ownership_documents": "compromising", "forged_authorization": "compromising",
	"lockpick": "compromising", "cutting_tools": "compromising", "master_keys": "compromising",
	"idea_copy": "compromising", "cash_envelope": "compromising",
	"delivery_note_forged": "compromising", "safe_combination_note": "compromising",
	"blackmail_file": "compromising", "footage_copy": "compromising",
	"sabotage_chemicals": "compromising",
}


func run_case() -> void:
	var ok: bool = Database.load_all()
	_print_problems()
	check(ok, "Database.load_all() succeeds")
	check_eq(Database.get_load_errors().size(), 0, "no load errors: every cross-reference valid")
	check_eq(Database.get_load_warnings().size(), 0,
			"no load warnings (item catalogue, access tags, leads_to, endings order)")
	check(Database.load_all(), "load_all() is idempotent (cached result)")
	_check_occupations()
	_check_rank_coverage()
	_check_archetypes()
	_check_balance()
	_check_people()
	_check_room_files()
	_check_room_ids()
	_check_references()
	_check_items()


func _print_problems() -> void:
	var errors: Array[String] = Database.get_load_errors()
	var warnings: Array[String] = Database.get_load_warnings()
	print("[data] %d error(s), %d warning(s)" % [errors.size(), warnings.size()])
	for i: int in mini(errors.size(), MAX_PRINTED_PROBLEMS):
		print("  ERROR: %s" % errors[i])
	for i: int in mini(warnings.size(), MAX_PRINTED_PROBLEMS):
		print("  WARNING: %s" % warnings[i])


func _check_occupations() -> void:
	var raw: Array = Database.get_raw("occupations").get("occupations", [])
	check_eq(raw.size(), EXPECTED_OCCUPATIONS, "occupations.json lists 50 occupations")
	var seen: Dictionary = {}
	var duplicates: Array[String] = []
	for entry: Variant in raw:
		var id: String = str((entry as Dictionary).get("id", ""))
		if seen.has(id):
			duplicates.append(id)
		seen[id] = true
	check(duplicates.is_empty(), "occupation ids are unique (duplicates: %s)" % str(duplicates))
	check_eq(Database.get_all_occupations().size(), EXPECTED_OCCUPATIONS,
			"Database exposes 50 occupations")


func _check_rank_coverage() -> void:
	var missing: Array[int] = []
	for rank: int in range(MIN_RANK, MAX_RANK + 1):
		if Database.get_occupations_by_rank(rank).is_empty():
			missing.append(rank)
	check(missing.is_empty(), "ranks R0..R33 all covered (missing: %s)" % str(missing))
	var top: Array[OccupationData] = Database.get_occupations_by_rank(MAX_RANK)
	check_eq(top[0].id if not top.is_empty() else "", "ceo", "R33 is the CEO")


func _check_archetypes() -> void:
	check_eq(Database.get_all_archetypes().size(), EXPECTED_ARCHETYPES, "12 archetypes")
	check_eq(Database.get_raw("archetypes").get("archetypes", []).size(), EXPECTED_ARCHETYPES,
			"archetypes.json lists 12 archetypes")
	check(Database.get_archetype("gossip") != null, "archetype 'gossip' exists")


func _check_balance() -> void:
	for path: String in BALANCE_SPOT_CHECKS:
		check_near(Database.get_balance_float(path), float(BALANCE_SPOT_CHECKS[path]), 0.0001,
				"balance '%s' == §25 value" % path)
	check_eq(Database.get_balance_int("economia.dinero_inicial"), 120, "balance int read")
	check_eq(Database.get_balance("presets_por_defecto"), "estandar", "default difficulty preset")
	check_eq(Database.get_balance_int("mundo.px_por_unidad"), 48, "BUILD_NOTES mundo section")


func _check_people() -> void:
	check_eq(Database.get_all_named_npcs().size(), EXPECTED_NAMED_NPCS, "23 named NPCs")
	check_eq(Database.get_all_investors().size(), EXPECTED_INVESTORS, "6 investors")
	check_eq(Database.get_all_endings().size(), EXPECTED_ENDINGS, "9 endings")


## 166 salas cuando existen los 27 archivos de rooms/; si falta alguno, lo nombra.
func _check_room_files() -> void:
	var missing: Array[String] = []
	for file: String in DatabaseSystem.ROOM_FILES:
		if not FileAccess.file_exists(ROOMS_DIR % file):
			missing.append("rooms/%s.json" % file)
	check(missing.is_empty(), "all floor files present (missing: %s)" % ", ".join(missing))
	var count: int = Database.get_all_rooms().size()
	if missing.is_empty():
		check_eq(count, EXPECTED_ROOMS, "166 rooms across data/rooms/*.json")
	else:
		check(false, "only %d rooms loaded (expected 166): missing floor files %s"
				% [count, ", ".join(missing)])


## Ids únicos entre todos los archivos de salas (recuento independiente del crudo).
func _check_room_ids() -> void:
	var owner: Dictionary = {}
	var duplicates: Array[String] = []
	for file: String in DatabaseSystem.ROOM_FILES:
		for entry: Variant in Database.get_raw("rooms/" + file).get("rooms", []):
			var id: String = str((entry as Dictionary).get("id", ""))
			if owner.has(id):
				duplicates.append("%s (%s, %s)" % [id, owner[id], file])
			owner[id] = file
	check(duplicates.is_empty(), "room ids unique across files (duplicates: %s)" % str(duplicates))


## Segunda línea, independiente de DataCrossCheck: referencias principales de §17.1.
func _check_references() -> void:
	var broken: Array[String] = []
	for occupation: OccupationData in Database.get_all_occupations():
		for target: String in occupation.promotes_to + occupation.can_jump_to + occupation.demotes_to:
			if Database.get_occupation(target) == null:
				broken.append("%s → %s" % [occupation.id, target])
		if not occupation.office_room.is_empty() and Database.get_room(occupation.office_room) == null:
			broken.append("%s office %s" % [occupation.id, occupation.office_room])
	for npc: NPCData in Database.get_all_named_npcs():
		if not npc.occupation.is_empty() and Database.get_occupation(npc.occupation) == null:
			broken.append("%s occupation %s" % [npc.id, npc.occupation])
		for link: Dictionary in npc.initial_links:
			if Database.get_named_npc(str(link["to"])) == null:
				broken.append("%s link %s" % [npc.id, link["to"]])
	for room: RoomData in Database.get_all_rooms():
		for target: String in room.connects_to:
			if Database.get_room(target) == null and target != "exterior":
				broken.append("%s connects_to %s" % [room.id, target])
		if Database.get_art_band(room.art_band).is_empty():
			broken.append("%s art_band %s" % [room.id, room.art_band])
	check(broken.is_empty(), "independent cross-reference scan clean (%s)" % str(broken))


func _check_items() -> void:
	var wrong: Array[String] = []
	for id: String in REQUIRED_ITEMS:
		var item: ItemData = Database.get_item(id)
		if item == null or item.category != REQUIRED_ITEMS[id]:
			wrong.append(id)
	check(wrong.is_empty(), "required item catalogue present with categories (%s)" % str(wrong))
	for item: ItemData in Database.get_all_items():
		if tr(item.name_key) == item.name_key:
			wrong.append(item.name_key)
	check(wrong.is_empty(), "every item name_key is localised (%s)" % str(wrong))
