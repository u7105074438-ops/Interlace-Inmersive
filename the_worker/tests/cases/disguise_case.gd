# disguise_case.gd — Cuerpo de test_disguise: umbrales de distancia, reconocimiento (compañeros y perspicacia > 70), limpiador invisible a las 20:00 y sospechoso a las 14:00 (verificación PASO 38), coherencia de los tres uniformes (despachos del vigilante), exterior, pasamontañas, cámaras (también el cruce real de Security en fase 2), robo de uniforme visto (evidencia definitiva) y disfraz perdido con el objeto.
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
const CEO_OFFICE := "ceo_office"
const CLEANING_LOCKERS := "cleaning_locker_room"
const SECURITY_LOCKERS := "security_locker_room"

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
	_test_office_coherence()
	_test_disguise_lost_with_item()
	_test_security_cross_check()
	_test_witnessed_uniform_theft()
	_test_tables_and_short_circuit()


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
	check(not Disguise.take_uniform(CLEANING, SECURITY_LOCKERS), "only from a locker of that uniform")
	check(not Disguise.take_uniform(MAINTENANCE, P16_ROOM), "no uniform lockers in the investor lounge")
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
	check(Disguise.wear(CLEANING), "the cleaner puts on the post-issued uniform")
	check_eq(Disguise.camera_subject(), "player", "cameras identify a cleaner in their own uniform")
	PlayerState.set_disguise("cleaning_uniform")
	check_eq(Disguise.camera_subject(), "player", "the tool alias of one's own uniform is no disguise")
	check(not Disguise.is_own_uniform(""), "an empty id is never one's own uniform")
	Disguise.take_off()


## §5.2 «no permanecer en despachos»: el uniforme de vigilante es incoherente en los despachos en
## horario de oficina; su ronda nocturna sí los cubre.
func _test_office_coherence() -> void:
	PlayerState.set_occupation("email_worker_3b", "test")
	check(Disguise.is_office(CEO_OFFICE) and not Disguise.is_office(P16_ROOM), "disfraz.despachos")
	var office_day: Dictionary = Disguise.evaluate(SECURITY_UNIFORM, 14, CEO_OFFICE, FAR, null)
	check(bool(office_day["suspicious"]) and float(office_day["suspicion_multiplier"]) > 1.0,
			"a guard lingering in the CEO's office at 14:00 is out of place")
	var office_night: Dictionary = Disguise.evaluate(SECURITY_UNIFORM, 22, CEO_OFFICE, FAR, null)
	check(bool(office_night["coherent"]), "the night round covers the offices")
	check(bool(Disguise.evaluate(SECURITY_UNIFORM, 14, P16_ROOM, FAR, null)["coherent"]),
			"a guard in the investor lounge at 14:00 blends in")
	check(Disguise.is_coherent(SECURITY_UNIFORM, 14, 20), "without a room only hour and floor count")
	check(not Disguise.is_coherent(SECURITY_UNIFORM, 14, 20, CEO_OFFICE), "with the room: office excluded")
	check(bool(Disguise.evaluate(CLEANING, 20, CEO_OFFICE, FAR, null)["coherent"]),
			"cleaners do clean offices at 20:00")


## Quitar el objeto quita el disfraz (vendido, escondido, requisado, puesto perdido).
func _test_disguise_lost_with_item() -> void:
	PlayerState.set_occupation("email_worker_3b", "test")
	while PlayerState.remove_item(CLEANING):
		pass
	PlayerState.add_item(CLEANING)
	PlayerState.add_item(CLEANING)
	check(Disguise.wear(CLEANING), "cleaning uniform on (two copies carried)")
	PlayerState.remove_item(CLEANING)
	check_eq(PlayerState.get_disguise(), CLEANING, "still wearing it while a copy is carried")
	PlayerState.remove_item(CLEANING)
	check_eq(PlayerState.get_disguise(), "", "removing the uniform takes the disguise off")
	GameClock.set_time(DAY, 20, 0)
	check_near(Disguise.detection_factor("", FAR, P16_ROOM), 1.0, EPS,
			"no longer invisible at 20:00 once the uniform is gone")
	PlayerState.add_item(Disguise.BALACLAVA)
	check(Disguise.wear(Disguise.BALACLAVA), "balaclava on")
	PlayerState.confiscate_hot_items()
	check(not Disguise.is_masked() and not PlayerState.is_carrying(Disguise.BALACLAVA),
			"a confiscated balaclava no longer hides the player")
	check_eq(Disguise.camera_subject(), "player", "cameras see the player again")
	PlayerState.add_item(MAINTENANCE)
	Disguise.wear(MAINTENANCE)
	check(PlayerState.dispose_item(MAINTENANCE, "trash_dock") and PlayerState.get_disguise() == "",
			"disposing of the worn uniform takes it off")
	PlayerState.set_occupation("cleaner", "test")
	check(not PlayerState.is_carrying(CLEANING) and Disguise.wear(CLEANING),
			"the cleaner wears the post-issued uniform")
	PlayerState.set_occupation("email_worker_3b", "test")
	check_eq(PlayerState.get_disguise(), "", "losing the post loses its uniform")
	PlayerState.add_item(CLEANING)
	PlayerState.add_item(SECURITY_UNIFORM)
	Disguise.wear(SECURITY_UNIFORM)
	PlayerState.remove_item(CLEANING)
	check_eq(PlayerState.get_disguise(), SECURITY_UNIFORM, "removing another item keeps the disguise")
	Disguise.take_off()
	PlayerState.remove_item(SECURITY_UNIFORM)


## El cruce REAL de Security en la fase 2 (procedimiento review_footage), no solo la réplica.
func _test_security_cross_check() -> void:
	check_eq(_footage_piece(false)["points_to"], "uniform:" + CLEANING,
			"Security phase 2 without the player's card that day: the uniform")
	var crossed: Dictionary = _footage_piece(true)
	check_eq(str(crossed.get("points_to", "")), "player",
			"Security phase 2 crosses the access log with the roster: the player")
	check_near(float(crossed.get("certainty", 0.0)), _b("seguridad.certeza_cruce_uniforme"), EPS,
			"with the cross-check certainty")


## Pieza camera_footage de un caso en la sala de la grabación tras la fase 2 ({} si no hay).
func _footage_piece(card_logged: bool) -> Dictionary:
	new_run(DEFAULT_SEED)
	PlayerState.set_disguise(CLEANING)
	var footage_id: String = Security.register_camera_footage(P16_ROOM, DAY, 20)
	PlayerState.set_disguise("")
	if card_logged:
		Security.log_card_access("reader_test", "", DAY, 8, "turnstiles")
	var case_id: String = Security.report_incident("object_missing", 0, P16_ROOM, true,
			{"day": DAY, "hour": 20, "always_opens": true})
	Security.advance_phase(case_id)
	Security.advance_phase(case_id)
	var inv: Investigation = Security.get_investigation(case_id)
	check(inv != null and inv.phase >= Disguise.evidence_phase(), "the case went through phase 2")
	if inv == null:
		return {"points_to": ""}
	for piece: Dictionary in inv.evidence:
		if str(piece["type"]) == "camera_footage" and str(piece["record_id"]) == footage_id:
			return piece
	return {"points_to": ""}


## §22.3: ser visto sacando un uniforme es evidencia definitiva (pieza compromising_item).
func _test_witnessed_uniform_theft() -> void:
	new_run(DEFAULT_SEED)
	check(Disguise.take_uniform(CLEANING, CLEANING_LOCKERS), "an unseen theft")
	check_eq(_definitive_pieces(CLEANING_LOCKERS).size(), 0, "unseen: no definitive piece")
	var witness: String = "npc_tom_iverson"
	var ids: Array[String] = [witness]
	check(Disguise.take_uniform(SECURITY_UNIFORM, SECURITY_LOCKERS, ids), "a theft in front of a guard")
	var pieces: Array[Dictionary] = _definitive_pieces(SECURITY_LOCKERS)
	check_eq(pieces.size(), 1, "seen: one definitive piece in the room's case")
	if pieces.is_empty():
		return
	check_near(float(pieces[0]["weight"]),
			_b("investigaciones.pesos_evidencia.objeto_comprometedor"), EPS, "weight 10 (§11.3)")
	check_eq(str(pieces[0]["points_to"]), "player", "against the player")
	var belief: Belief = null
	for b: Belief in BeliefNet.get_beliefs_held_by(witness):
		if b.subject == "player" and b.fact == "caught_redhanded:theft_small":
			belief = b
	check(belief != null and str(pieces[0]["record_id"]) == belief.id,
			"tied to the witness's red-handed belief (silencing them drops it)")
	var late: String = Disguise.on_uniform_theft_witnessed("npc_ludmila_petrova", SECURITY_LOCKERS)
	check(not late.is_empty() and _definitive_pieces(SECURITY_LOCKERS).size() == 2,
			"a flagrancy detected later adds its own definitive piece")
	check_eq(Disguise.on_uniform_theft_witnessed("", SECURITY_LOCKERS), "", "no witness, nothing")


func _definitive_pieces(room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inv: Investigation in Security.get_active_investigations():
		if inv.location != room_id:
			continue
		for piece: Dictionary in inv.evidence:
			if str(piece["type"]) == "compromising_item":
				out.append(piece)
	return out


func _test_tables_and_short_circuit() -> void:
	check_eq(Disguise.balaclava_id(), Database.get_balance("disfraz.pasamontanas"),
			"the balaclava id comes from balance")
	PlayerState.set_disguise("")
	check_near(Disguise.detection_factor("", NEAR, P16_ROOM), 1.0, EPS, "no disguise: neutral")
	check(bool(Disguise.evaluate("", 14, P16_ROOM, NEAR, null)["coherent"]), "empty id: neutral result")
	Disguise.clear_cache()
	check_eq(Disguise.canonical_uniform("guard_uniform"), SECURITY_UNIFORM, "tables reload after clear_cache")
	check_eq(Disguise.get_uniform_ids().size(), 3, "three uniforms")
