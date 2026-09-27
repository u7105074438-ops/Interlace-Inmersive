# disguise_case.gd — Cuerpo de test_disguise: umbrales de distancia, reconocimiento (compañeros y perspicacia > 70), limpiador invisible a las 20:00 y sospechoso a las 14:00 (verificación PASO 38), coherencia de los tres uniformes, exterior, pasamontañas, cámaras y cruce con el registro de accesos.
# PROPIETARIO DE: nada.
# ESCUCHA: crime_committed (conexión temporal, para comprobarla).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const EPS := 0.0001
const CLEANING := "uniform_cleaning"
const MAINTENANCE := "uniform_maintenance"
const SECURITY_UNIFORM := "uniform_security"
const P16_ROOM := "investor_lounge"
const P5_ROOM := "accounting"
const BASEMENT_ROOM := "general_warehouse"
const STREET := "street"
const FAR := 8.0
const MID := 4.5
const NEAR := 2.0
const DAY := 3

var _crimes: Array[Array] = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_test_distance_thresholds()
	_test_recognition_by_perception()
	_test_colleagues_recognise()
	_test_paso38_cleaner()
	_test_uniform_windows()
	_test_exterior_and_balaclava()
	_test_camera_identity()
	_test_uniform_theft_and_wearing()
	_test_access_and_subjects()
	_test_own_uniform()


func _stranger(perception: int) -> NPCRuntime:
	return Fixtures.synthetic("test_observer_%d" % perception, "oblivious", {"perception": perception})


func _b(path: String) -> float:
	return Database.get_balance_float(path)


func _test_distance_thresholds() -> void:
	var stranger: NPCRuntime = _stranger(40)
	var far: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, FAR, stranger)
	check(bool(far["identity_hidden"]), "> 6 m: classified by the uniform (identity hidden)")
	check_near(float(far["suspicion_multiplier"]), _b("disfraz.factor_lejos_coherente"), EPS,
			"> 6 m: coherent uniform uses the far factor")
	check(not bool(far["recognised"]), "> 6 m: nobody is recognised")
	var at_six: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, 6.0, stranger)
	check_near(float(at_six["suspicion_multiplier"]), _b("disfraz.factor_lejos_coherente"), EPS,
			"exactly 6 m joins the far factor (continuous)")
	var mid: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, MID, stranger)
	var expected_mid: float = lerpf(_b("disfraz.factor_cerca_coherente"),
			_b("disfraz.factor_lejos_coherente"), (MID - 3.0) / 3.0)
	check_near(float(mid["suspicion_multiplier"]), expected_mid, EPS,
			"between 3 and 6 m the factor is interpolated")
	var near: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, NEAR, stranger)
	check(bool(near["identity_hidden"]) and not bool(near["recognised"]),
			"< 3 m: a stranger with low perception is still fooled")
	check_near(float(near["suspicion_multiplier"]), _b("disfraz.factor_cerca_coherente"), EPS,
			"< 3 m: stranger uses the near factor")
	check_eq(_b("percepcion.distancia_clasificacion_uniforme"), 6.0, "classification distance 6 m")
	check_eq(_b("percepcion.distancia_reconocimiento_disfraz"), 3.0, "recognition distance 3 m")


func _test_recognition_by_perception() -> void:
	var sharp: NPCRuntime = _stranger(80)
	var near: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, NEAR, sharp)
	check(bool(near["recognised"]) and not bool(near["identity_hidden"]),
			"perception > 70 recognises the player under 3 m")
	check_near(float(near["suspicion_multiplier"]), _b("disfraz.factor_reconocido"), EPS,
			"recognised: the disguise does nothing")
	var mid: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, MID, sharp)
	check(not bool(mid["recognised"]) and bool(mid["identity_hidden"]),
			"perception > 70 does not recognise from 4.5 m")
	var far: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, FAR, sharp)
	check(not bool(far["recognised"]), "perception > 70 does not recognise from 8 m")
	var borderline: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, NEAR, _stranger(70))
	check(not bool(borderline["recognised"]), "perception exactly 70 is not enough (> 70)")


func _test_colleagues_recognise() -> void:
	var colleague: NPCRuntime = null
	var stranger: NPCRuntime = null
	var limit: int = Database.get_balance_int("disfraz.perspicacia_reconocimiento")
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_effective_perception(npc.id) > limit:
			continue
		if colleague == null and NPCDirector.knows_player(npc.id):
			colleague = npc
		elif stranger == null and not NPCDirector.knows_player(npc.id):
			stranger = npc
	check(colleague != null and stranger != null, "found a colleague and a stranger (perception <= 70)")
	if colleague == null or stranger == null:
		return
	var near: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, NEAR, colleague)
	check(bool(near["recognised"]), "a colleague who knows the player recognises them under 3 m")
	var far: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, FAR, colleague)
	check(bool(far["identity_hidden"]) and not bool(far["recognised"]),
			"the same colleague classifies by uniform from 8 m")
	var other: Dictionary = Disguise.evaluate(CLEANING, 20, P16_ROOM, NEAR, stranger)
	check(not bool(other["recognised"]), "someone who does not know the player is fooled under 3 m")


## Verificación de PASO 38: con el uniforme de limpieza puesto, a las 20:00 nadie reacciona; a
## las 14:00 sí (más que sin disfraz).
func _test_paso38_cleaner() -> void:
	PlayerState.add_item(CLEANING)
	check(Disguise.wear(CLEANING), "the player puts the cleaning uniform on")
	GameClock.set_time(DAY, 20, 0)
	var evening: float = Disguise.detection_factor("", FAR, P16_ROOM)
	check_near(evening, 0.0, EPS, "cleaner on P16 at 20:00 from 8 m: functionally invisible")
	var perceived: Dictionary = Perception.disguise_effect("", FAR, P16_ROOM)
	check_near(float(perceived["factor"]), 0.0, EPS, "Perception's hook reads the same factor")
	check(not bool(perceived["suspicious"]), "Perception: nothing noteworthy at 20:00")
	GameClock.set_time(DAY, 14, 0)
	var noon: float = Disguise.detection_factor("", FAR, P16_ROOM)
	var plain: float = float(Disguise.evaluate("", 14, P16_ROOM, FAR, null)["suspicion_multiplier"])
	check(noon > plain, "cleaner on P16 at 14:00 is MORE suspicious than no disguise (%.2f > %.2f)"
			% [noon, plain])
	var result: Dictionary = Disguise.evaluate(CLEANING, 14, P16_ROOM, FAR, null)
	check(bool(result["suspicious"]) and not bool(result["coherent"]), "14:00 is incoherent")
	check(bool(Perception.disguise_effect("", FAR, P16_ROOM)["suspicious"]),
			"Perception: the incoherent uniform makes the player noteworthy")
	var sharp: Dictionary = Disguise.evaluate(CLEANING, 14, P16_ROOM, NEAR, _stranger(90))
	check(bool(sharp["recognised"]) and float(sharp["suspicion_multiplier"]) > 1.0,
			"recognised AND out of place keeps the incoherence penalty")
	Disguise.take_off()
	check_eq(PlayerState.get_disguise(), "", "take_off clears the disguise")


func _test_uniform_windows() -> void:
	check(Disguise.is_coherent(CLEANING, 17, 16), "cleaning from 17:00")
	check(not Disguise.is_coherent(CLEANING, 23, 16), "cleaning ends at 23:00")
	check(not Disguise.is_coherent(CLEANING, 9, -1), "cleaning at 09:00 in the basement")
	check(Disguise.is_coherent(MAINTENANCE, 10, 5), "maintenance on P5 at 10:00")
	check(not Disguise.is_coherent(MAINTENANCE, 23, 5), "maintenance on P5 at 23:00")
	check(Disguise.is_coherent(MAINTENANCE, 21, -2), "maintenance in S2 at 21:00")
	check(Disguise.is_coherent(SECURITY_UNIFORM, 3, 12), "security at 03:00 on P12")
	check(Disguise.is_coherent("guard_uniform", 3, 12), "post-tool alias resolves to the uniform")
	check(not Disguise.is_coherent(SECURITY_UNIFORM, 3, 200), "no uniform window outdoors")
	check_eq(Disguise.canonical_uniform("jewellery"), "", "non-uniform items are not disguises")
	var p5: Dictionary = Disguise.evaluate(MAINTENANCE, 10, P5_ROOM, FAR, null)
	check(bool(p5["coherent"]) and float(p5["suspicion_multiplier"]) < 1.0,
			"a maintenance worker on P5 at 10:00 blends in")
	var basement: Dictionary = Disguise.evaluate(CLEANING, 9, BASEMENT_ROOM, FAR, null)
	check(bool(basement["suspicious"]), "a cleaner in S1 at 09:00 draws attention")


func _test_exterior_and_balaclava() -> void:
	var outside: Dictionary = Disguise.evaluate(CLEANING, 22, STREET, NEAR, _stranger(90))
	check(not bool(outside["identity_hidden"]), "outdoors a uniform hides nothing")
	check_near(float(outside["suspicion_multiplier"]), 1.0, EPS, "outdoors a uniform is neutral")
	var mask_out: Dictionary = Disguise.evaluate(Disguise.BALACLAVA, 23, STREET, NEAR, _stranger(95))
	check(bool(mask_out["identity_hidden"]) and not bool(mask_out["recognised"]),
			"balaclava: not even a sharp observer at 2 m recognises the player")
	check_near(float(mask_out["suspicion_multiplier"]),
			_b("disfraz.factor_pasamontanas_exterior"), EPS, "balaclava outdoors factor")
	var mask_in: Dictionary = Disguise.evaluate(Disguise.BALACLAVA, 23, P16_ROOM, FAR, null)
	check(bool(mask_in["suspicious"]) and float(mask_in["suspicion_multiplier"]) > 1.0,
			"a balaclava inside the building is alarming")
	check(not Disguise.wear(Disguise.BALACLAVA), "cannot wear a balaclava one does not carry")
	PlayerState.add_item(Disguise.BALACLAVA)
	check(Disguise.wear(Disguise.BALACLAVA) and Disguise.is_masked(), "balaclava worn")
	Disguise.take_off()


func _test_camera_identity() -> void:
	PlayerState.set_disguise(CLEANING)
	check_eq(Disguise.camera_subject(), "uniform:" + CLEANING, "cameras record the uniform")
	var footage_id: String = Security.register_camera_footage(P16_ROOM, DAY, 20)
	var entry: Dictionary = {}
	for f: Dictionary in Security.get_footage_list():
		if str(f["id"]) == footage_id:
			entry = f
	check_eq(str(entry.get("subject", "")), "uniform:" + CLEANING, "Security stores the uniform")
	check(BeliefNet.get_records_about("uniform:" + CLEANING).size() > 0,
			"BeliefNet's footage record points to the uniform")
	var phase1: Dictionary = Disguise.resolve_footage_identity(entry, 1)
	check_eq(str(phase1["subject"]), "uniform:" + CLEANING, "phase 1: no cross-check yet")
	var no_card: Dictionary = Disguise.resolve_footage_identity(entry, 2)
	check(not bool(no_card["crossed"]), "phase 2 without the player's card that day: uniform")
	Security.log_card_access("reader_test", "", DAY + 1, 9)
	check(not bool(Disguise.resolve_footage_identity(entry, 2)["crossed"]),
			"a card read on another day does not cross")
	Security.log_card_access("reader_test", "", DAY, 8)
	var crossed: Dictionary = Disguise.resolve_footage_identity(entry, 2)
	check(bool(crossed["crossed"]) and str(crossed["subject"]) == "player",
			"phase 2 access log × shift roster: the footage points to the player")
	check_near(float(crossed["certainty"]), _b("seguridad.certeza_cruce_uniforme"), EPS,
			"cross-check certainty from balance")
	PlayerState.set_disguise("")


func _test_uniform_theft_and_wearing() -> void:
	PlayerState.remove_item(CLEANING)
	EventBus.crime_committed.connect(_on_crime)
	check(Disguise.take_uniform(CLEANING, "cleaning_locker_room"), "uniform taken from its locker")
	EventBus.crime_committed.disconnect(_on_crime)
	check(PlayerState.is_carrying(CLEANING), "the uniform is in the inventory")
	check(not _crimes.is_empty() and str(_crimes.back()[0]) == "theft_small"
			and bool((_crimes.back()[2] as Dictionary).get("uniform", false)),
			"taking it is a theft (crime_committed theft_small, uniform: true)")
	check(PlayerState.has_hot_items(), "a stolen uniform is compromising (definitive if searched)")
	check(not Disguise.take_uniform("jewellery", "cleaning_locker_room"), "only uniforms")
	check(not Disguise.wear(SECURITY_UNIFORM), "cannot wear a uniform one does not have")


func _on_crime(crime_type: String, room_id: String, details: Dictionary) -> void:
	_crimes.append([crime_type, room_id, details])


func _test_access_and_subjects() -> void:
	check(Disguise.grants_access(CLEANING, "cleaning_locker_room"), "cleaning uniform: cleaning rooms")
	check(not Disguise.grants_access(CLEANING, "security_locker_room"), "but not the guards' room")
	check(Disguise.grants_access(MAINTENANCE, BASEMENT_ROOM), "maintenance: basements tag")
	PlayerState.set_disguise(CLEANING)
	GameClock.set_time(DAY, 20, 0)
	check_eq(Disguise.sighting_subject("", FAR, P16_ROOM), "uniform:" + CLEANING,
			"a far sighting has no identity, only the uniform")
	PlayerState.set_disguise(Disguise.BALACLAVA)
	check_eq(Disguise.sighting_subject("", NEAR, STREET), BeliefNetSystem.UNKNOWN_SUBJECT,
			"a masked sighting has no subject")
	PlayerState.set_disguise("")
	check_eq(Disguise.sighting_subject("", NEAR, P16_ROOM), "player", "no disguise: the player")


func _test_own_uniform() -> void:
	PlayerState.set_occupation("cleaner", "test")
	var own: Dictionary = Disguise.evaluate(CLEANING, 14, P16_ROOM, FAR, null)
	check(not bool(own["identity_hidden"]) and is_equal_approx(float(own["suspicion_multiplier"]), 1.0),
			"the cleaner's own uniform is not a disguise")
	check(Disguise.is_own_uniform(CLEANING), "is_own_uniform for the cleaner")
