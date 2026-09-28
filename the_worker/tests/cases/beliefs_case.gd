# beliefs_case.gd — Cuerpo de test_beliefs: certezas por origen, decaimiento, registros neutros e incriminatorios, sospecha, denuncias, rumores, moduladores, credibilidad real y guardado.
# PROPIETARIO DE: nada.
# ESCUCHA: belief_created, belief_decayed, belief_forgotten, record_created, record_destroyed, suspicion_changed (solo para comprobarlas).
extends TestCase

const EPS := 0.000001
const PLAYER := "player"
const ROOM := "wing_3b"
const CORRIDOR := "corridors_low@3"
## Sala con acreditación 5: vetada al puesto inicial (acreditación 1).
const RESTRICTED := "cfo_office"
const SERVER_ROOM := "server_room"
const MONITOR_ROOM := "monitor_room"
const THEFT := "caught_redhanded:theft_small"
const DIFFICULTY_KEY := "decaimiento_sospecha"
const DAY := 1
const WORK_HOUR := 10
const NIGHT_HOUR := 21
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const CLAUDIA := "npc_claudia_reeves"
# Números del manual que el balance y el sistema deben respetar (§7.2, §7.6, §12.2, §12.4, §31).
const MANUAL_PARTIAL := 0.35
const MANUAL_DIRECT := 0.90
const MANUAL_ORAL := 0.75
const MANUAL_AMPLIFICATION := 1.15
const MANUAL_DECAY := 0.08
const MANUAL_FORGET := 0.10
const MANUAL_BIRTH_MOD := -0.002
const MANUAL_CREDIBILITY_MOD := 0.003
const MANUAL_FOOTAGE := 4.5
const MANUAL_CARD := 2.5
const MANUAL_FORGED := 5.0
const MANUAL_ACCOUNTING := 3.0
const MANUAL_PARTIAL_WITNESS := 0.8
const MANUAL_DIRECT_WITNESS := 4.0
const MANUAL_SECURITY_REPORT := 20.0
const MANUAL_SUPERIOR_REPORT := 10.0
const MANUAL_INTERNO_DECAY := 1.4
const MANUAL_AUDITORIA_DECAY := 0.6
# Calibración documentada en balance (creencias.*): con la credibilidad por defecto
# (50 × 0,003 = 0,15) y el divisor 3, certeza × peso = 1 aporta 0,15 × 100 / 3 = 5 puntos.
const DOC_DEFAULT_REPUTATION := 50.0
const DOC_DEFAULT_CREDIBILITY := 0.15
const DOC_DIVISOR := 3.0
const DOC_EVIDENCE_POINTS := 5.0
const DOC_ANONYMOUS_REPORT := 10.0
const DOC_ANNOTATION_WEIGHT := 1.0
const SUSPICION_MAX := 100.0
const BREAKDOWN_KEYS: Array[String] = [
	"belief_id", "holder", "fact", "certainty", "credibility", "weight", "contribution",
]

var _created: Array = []
var _decayed: Array = []
var _forgotten: Array = []
var _records: Array = []
var _destroyed: Array = []
var _suspicion_events: Array = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	_listen()
	GameClock.set_time(DAY, WORK_HOUR, 0)
	_test_manual_numbers()
	_test_creation_by_source()
	_test_routine_sensor_records()
	_test_incriminating_records()
	_test_crime_upgrades_nearby_logs()
	_test_decay_after_days()
	_test_difficulty_presets()
	_test_records_never_decay_and_destroy()
	_test_footage_deletion()
	_test_digital_records_deleted()
	_test_crime_records()
	_test_forgery_verified_by_investigation()
	_test_suspicion_formula()
	_test_reports()
	_test_report_merge_and_clamp()
	_test_reputation_modulators()
	_test_reinforcement_and_merge()
	_test_forgetting_api()
	_test_witness_removed_and_body()
	_test_unknown_fact_is_neutral()
	_test_rumour_protocol()
	_test_save_load_round_trip()
	await _test_population_credibility()


# ─── Utilidades ───────────────────────────────────────────────

func _listen() -> void:
	EventBus.belief_created.connect(func(id: String, h: String, s: String, c: float) -> void:
		_created.append([id, h, s, c]))
	EventBus.belief_decayed.connect(func(id: String, c: float) -> void: _decayed.append([id, c]))
	EventBus.belief_forgotten.connect(func(id: String) -> void: _forgotten.append(id))
	EventBus.record_created.connect(func(id: String, t: String, w: float) -> void:
		_records.append([id, t, w]))
	EventBus.record_destroyed.connect(func(id: String, m: String) -> void:
		_destroyed.append([id, m]))
	EventBus.suspicion_changed.connect(func(o: float, n: float) -> void:
		_suspicion_events.append([o, n]))


## Red vacía y reputación del jugador fijada por señal (como la emitiría PlayerState).
## La prensa (NewsFeed, capa compartida §7.11) también pesa en la sospecha: se vacía con la red.
func _fresh(reputation: float = 0.0) -> void:
	NewsFeed.reset_for_new_run()
	BeliefNet.reset_for_new_run()
	EventBus.reputation_changed.emit(reputation, reputation)
	GameClock.set_time(DAY, WORK_HOUR, 0)
	for entries: Array in [_created, _decayed, _forgotten, _records, _destroyed, _suspicion_events]:
		entries.clear()


func _bal(path: String) -> float:
	return Database.get_balance_float(path)


func _cert(id: String) -> float:
	var b: Belief = BeliefNet.get_belief(id)
	return b.certainty if b != null else -1.0


func _suspicion() -> float:
	return BeliefNet.calculate_player_suspicion()


## PASO 13: BeliefNet publica cada recálculo en la caché de PlayerState.
func _check_cache(context: String) -> void:
	check_near(PlayerState.get_suspicion(), _suspicion(), EPS,
			"PlayerState caches the suspicion (%s)" % context)


func _check_last_change(expected_new: float, context: String) -> void:
	var ok: bool = not _suspicion_events.is_empty() \
			and absf(float(_suspicion_events.back()[1]) - expected_new) <= EPS
	check(ok, "suspicion_changed(old, %.2f) emitted (%s)" % [expected_new, context])


func _check_last_old(expected_old: float, context: String) -> void:
	var ok: bool = not _suspicion_events.is_empty() \
			and absf(float(_suspicion_events.back()[0]) - expected_old) <= EPS
	check(ok, "suspicion_changed(%.2f, new) emitted (%s)" % [expected_old, context])


## day_advanced real (lo oyen todos los sistemas). Security se vacía antes: sus investigaciones
## abiertas por los delitos de este caso no forman parte de lo que aquí se comprueba.
func _advance_day(day: int) -> void:
	Security.reset_for_new_run()
	EventBus.day_advanced.emit(day)


func _only(list: Array[Belief], msg: String) -> Belief:
	check_eq(list.size(), 1, msg)
	return list[0] if list.size() == 1 else Belief.new()


func _decay_days(days: int) -> void:
	for _i: int in days:
		BeliefNet.apply_daily_decay()


func _contribution_of(id: String) -> float:
	for entry: Dictionary in BeliefNet.get_suspicion_breakdown():
		if entry["belief_id"] == id:
			return float(entry["contribution"])
	return 0.0


func _records_of(subject: String, record_type: String) -> Array[Belief]:
	var out: Array[Belief] = []
	for b: Belief in BeliefNet.get_records_about(subject):
		if b.record_type == record_type:
			out.append(b)
	return out


# ─── Balance = manual + calibración documentada ───────────────

func _test_manual_numbers() -> void:
	check_near(_bal("creencias.certeza_parcial"), MANUAL_PARTIAL, EPS, "balance: partial 0.35")
	check_near(_bal("creencias.certeza_directa_completa"), MANUAL_DIRECT, EPS, "balance: 0.90")
	check_near(_bal("creencias.descuento_por_transmision"), MANUAL_ORAL, EPS, "balance: ×0.75")
	check_near(_bal("creencias.amplificacion_rumor_max"), MANUAL_AMPLIFICATION, EPS, "×1.15")
	check_near(_bal("creencias.decaimiento_diario"), MANUAL_DECAY, EPS, "balance: 0.08/day")
	check_near(_bal("creencias.umbral_olvido"), MANUAL_FORGET, EPS, "balance: forget < 0.10")
	check_near(_bal("investigaciones.pesos_evidencia.grabacion_camara"), MANUAL_FOOTAGE, EPS,
			"§12.4 footage 4.5")
	check_near(_bal("investigaciones.pesos_evidencia.registro_tarjeta"), MANUAL_CARD, EPS,
			"§12.4 card log 2.5")
	check_near(_bal("creencias.peso_tipo.seen_partially"), MANUAL_PARTIAL_WITNESS, EPS,
			"suspicion weight of a partial sighting = partial witness weight (0.8)")
	check_near(_bal("creencias.peso_tipo.caught_redhanded"), MANUAL_DIRECT_WITNESS, EPS,
			"suspicion weight of flagrancy = direct witness weight (4.0)")
	check_near(_bal("creencias.reputacion_portador_por_defecto"), DOC_DEFAULT_REPUTATION, EPS,
			"calibration: default holder reputation 50")
	check_near(_bal("creencias.divisor_normalizacion"), DOC_DIVISOR, EPS, "calibration: divisor 3")
	check_near(BeliefNet.get_default_credibility(), DOC_DEFAULT_CREDIBILITY, EPS,
			"calibration: default credibility 50 × 0.003 = 0.15")
	check_near(_bal("creencias.puntos_denuncia.security"),
			_bal("flagrancia.peso_denuncia_seguridad"), EPS, "report points = §12.2 flagrancy +20")
	check_near(_bal("creencias.puntos_denuncia.superior"),
			_bal("flagrancia.peso_denuncia_superior"), EPS, "report points = §12.2 superior +10")
	check_near(_bal("creencias.factor_registro_neutro"), 0.0, EPS, "routine records weigh 0")
	check_near(DOC_DEFAULT_CREDIBILITY * SUSPICION_MAX / DOC_DIVISOR, DOC_EVIDENCE_POINTS, EPS,
			"calibration: certainty × weight = 1 at default credibility → 5 points")
	check_near(_bal("creencias.puntos_por_peso_evidencia_denuncia") * MANUAL_DIRECT_WITNESS,
			MANUAL_SECURITY_REPORT, EPS, "a direct-witness report (evidence 4.0) → +20 (§12.2)")


# ─── Certezas iniciales por origen (§7.2) ─────────────────────

func _test_creation_by_source() -> void:
	_fresh()
	EventBus.player_seen_partially.emit("npc_t_debbie", _bal("creencias.certeza_parcial"), ROOM)
	var seen: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_debbie"), "partial -> 1 belief")
	check_near(seen.certainty, MANUAL_PARTIAL, EPS, "partial perception -> certainty 0.35")
	check_eq([seen.subject, seen.fact, seen.source, seen.location, seen.is_record],
			[PLAYER, "seen_partially", "direct", ROOM, false], "partial belief fields")
	check_eq(_created.back(), [seen.id, "npc_t_debbie", PLAYER, seen.certainty],
			"belief_created(id, holder, subject, certainty) emitted")
	EventBus.player_caught_redhanded.emit("npc_t_george", "theft_small", 0)
	var caught: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_george"), "flagrancy -> 1")
	check_near(caught.certainty, MANUAL_DIRECT, EPS, "full direct perception -> certainty 0.90")
	check_eq(caught.fact, THEFT, "flagrancy fact carries the crime type")
	var rumor: Belief = BeliefNet.get_belief(BeliefNet.transfer_belief(caught.id, "npc_t_rose",
			MANUAL_ORAL))
	check(rumor != null, "transfer_belief returns the copy's id")
	if rumor != null:
		check_near(rumor.certainty, MANUAL_DIRECT * MANUAL_ORAL, EPS, "oral: 0.90 × 0.75 = 0.675")
		check_eq([rumor.holder, rumor.source, rumor.fact], ["npc_t_rose", "rumor", THEFT],
				"the copy is a rumour held by the listener")
	var amp_id: String = BeliefNet.transfer_belief(seen.id, "npc_t_rose", 2.0)
	check_near(_cert(amp_id), MANUAL_PARTIAL * MANUAL_AMPLIFICATION, EPS,
			"amplification is capped at ×1.15 (0.35 → 0.4025)")
	check_eq(BeliefNet.transfer_belief(seen.id, "npc_t_debbie", MANUAL_ORAL), "", "no self-copy")
	var created_before: int = _created.size()
	EventBus.player_seen_partially.emit("npc_t_debbie", MANUAL_PARTIAL, ROOM)
	check_near(seen.certainty, 2.0 * MANUAL_PARTIAL, EPS, "partial perception accumulates (0.70)")
	check_eq(_created.size(), created_before, "accumulating does not create a new belief")
	check_eq(_decayed.back(), [seen.id, seen.certainty],
			"accumulating announces the new certainty (belief_decayed = certainty changed)")
	check_eq(BeliefNet.count_credible_beliefs_about(PLAYER, 0.5), 3,
			"credible (>= 0.5): 0.70, 0.90, 0.675 — not 0.4025")


# ─── Registros de sensores: rutinarios vs incriminatorios ─────

## Revisión: tres viajes en ascensor y ocho fichajes legítimos saturaban la sospecha a 100.
func _test_routine_sensor_records() -> void:
	_fresh()
	check(not BeliefNet.is_room_forbidden_for_player(CORRIDOR), "precondition: corridor allowed")
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, 12)
	var footage: Belief = _only(BeliefNet.get_records_about(PLAYER), "camera -> 1 record")
	check_eq([footage.is_record, footage.record_type, footage.source, footage.timestamp,
			footage.location, footage.holder], [true, "footage", "record", 12, CORRIDOR, "archive"],
			"footage record fields (day and room from the signal)")
	check_near(footage.certainty, 1.0, EPS, "documentary record -> certainty 1.00")
	check_near(footage.weight, MANUAL_FOOTAGE, EPS, "footage keeps its §12.4 evidence weight 4.5")
	check_eq(_records.back(), [footage.id, "footage", footage.weight], "record_created emitted")
	check_eq(BeliefNet.get_neutral_reason(footage.id), "routine", "an allowed corridor: routine")
	for ride: int in 3:
		EventBus.camera_recorded_player.emit("cam_elevator_%d" % ride, CORRIDOR, DAY)
		EventBus.card_reader_logged.emit("reader_elevator_1", PLAYER, DAY, WORK_HOUR)
	for swipe: int in 8:
		EventBus.card_reader_logged.emit("reader_door_%d" % swipe, PLAYER, DAY, WORK_HOUR)
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 15, "every reading is still recorded")
	check_near(_suspicion(), 0.0, EPS, "3 elevator rides + 8 own-card swipes: suspicion stays 0")
	_check_cache("routine records")
	check(BeliefNet.get_beliefs_about(PLAYER).is_empty(), "records are not listed as beliefs")
	EventBus.card_reader_logged.emit("reader_elevator_1", "npc_t_claudia", 12, 10)
	check_eq(BeliefNet.get_records_about("npc_t_claudia").size(), 1,
			"stolen card -> the log names the card owner (§5.3)")
	PlayerState.set_disguise("security_guard")
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, 12)
	PlayerState.set_disguise("")
	check_eq(BeliefNet.get_records_about("uniform:security_guard").size(), 1,
			"disguised: the camera records the uniform, not the identity (§5.3)")
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 15, "... so no new record on the player")


## Sala vetada a la acreditación y franja nocturna (§5.5, §5.6, PASO 27).
func _test_incriminating_records() -> void:
	_fresh()
	check(PlayerState.get_clearance() < Database.get_room(RESTRICTED).clearance_required
			and BeliefNet.is_room_forbidden_for_player(RESTRICTED),
			"precondition: the CFO office is beyond the starting clearance")
	EventBus.camera_recorded_player.emit("cam_cfo", RESTRICTED, DAY)
	var rec: Belief = _only(BeliefNet.get_records_about(PLAYER), "restricted -> 1 record")
	check(not BeliefNet.is_record_neutral(rec.id), "recorded beyond clearance: incriminating")
	check_near(_suspicion(), 22.5, EPS, "by hand: 1.0 × 0.15 × 4.5 × 100 / 3 = 22.5")
	_check_last_change(22.5, "restricted recording")
	EventBus.camera_recorded_player.emit("cam_cfo", RESTRICTED, DAY)
	check_near(_suspicion(), 22.5, EPS, "the same camera counts once per day")
	EventBus.camera_recorded_player.emit("cam_cfo_2", RESTRICTED, DAY)
	check_near(_suspicion(), 22.5, EPS, "a second camera of the same room in the same hour is the same event")
	_check_cache("restricted records")
	_fresh()
	GameClock.set_time(DAY, NIGHT_HOUR, 0)
	check_eq(GameClock.get_current_band(), "night", "precondition: 21:00 is the night band")
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, DAY)
	EventBus.card_reader_logged.emit("reader_elevator_1", PLAYER, DAY, NIGHT_HOUR)
	check_near(_suspicion(), 22.5 + 12.5, EPS, "at night: footage 22.5 + card log 2.5 × 5 = 35")
	_check_cache("night records")
	GameClock.set_time(DAY, WORK_HOUR, 0)


## Un delito visible en la sala vuelve incriminatorias sus lecturas a ±1 hora.
func _test_crime_upgrades_nearby_logs() -> void:
	_fresh()
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, DAY)
	EventBus.card_reader_logged.emit("reader_3b", PLAYER, DAY, WORK_HOUR)
	var footage: Belief = _records_of(PLAYER, "footage")[0]
	var card: Belief = _records_of(PLAYER, "card_log")[0]
	EventBus.crime_committed.emit("rumour_planted", CORRIDOR, {})
	check(BeliefNet.is_record_neutral(footage.id), "an invisible crime does not upgrade footage")
	EventBus.crime_committed.emit("theft_small", CORRIDOR, {})
	check(not BeliefNet.is_record_neutral(footage.id), "a theft in the corridor upgrades it")
	check(BeliefNet.is_record_neutral(card.id), "a log from another room stays routine")
	check_near(_suspicion(), 22.5, EPS, "the recording of the theft weighs 22.5")
	GameClock.set_time(DAY, WORK_HOUR + 1, 0)
	EventBus.camera_recorded_player.emit("cam_p03_2", CORRIDOR, DAY)
	check_near(_suspicion(), 45.0, EPS, "a recording 1 h after the theft is incriminating too")
	GameClock.set_time(DAY, WORK_HOUR + 3, 0)
	EventBus.camera_recorded_player.emit("cam_p03_3", CORRIDOR, DAY)
	check_near(_suspicion(), 45.0, EPS, "3 h later the corridor is routine again")
	_check_cache("crime window")
	GameClock.set_time(DAY, WORK_HOUR, 0)


# ─── Decaimiento y olvido (§7.6) ──────────────────────────────

func _test_decay_after_days() -> void:
	_fresh()
	var partial: String = BeliefNet.create_belief("npc_t_a", PLAYER, "seen_partially",
			MANUAL_PARTIAL, "direct", ROOM)
	var direct: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var about_npc: String = BeliefNet.create_belief("npc_t_c", "npc_t_x", THEFT, 0.5, "direct", "")
	check_near(Database.get_difficulty_modifier(DIFFICULTY_KEY), 1.0, EPS,
			"default preset: decaimiento_sospecha × 1.0")
	var before: float = _suspicion()
	BeliefNet.apply_daily_decay()
	check_near(_cert(partial), MANUAL_PARTIAL - MANUAL_DECAY, EPS, "day 1: 0.35 → 0.27")
	check(_decayed.has([partial, _cert(partial)]), "belief_decayed(id, new_certainty) emitted")
	check(_suspicion() < before, "suspicion falls with the decay")
	_check_last_change(_suspicion(), "after decay")
	_check_cache("after decay")
	_decay_days(2)
	check_near(_cert(partial), MANUAL_PARTIAL - 3.0 * MANUAL_DECAY, EPS, "day 3: 0.11, remembered")
	check(not _forgotten.has(partial), "no belief_forgotten while >= 0.10")
	BeliefNet.apply_daily_decay()
	check(BeliefNet.get_belief(partial) == null, "day 4: 0.03 < 0.10 → forgotten")
	check(_forgotten.has(partial), "belief_forgotten emitted")
	check_near(_cert(direct), MANUAL_DIRECT - 4.0 * MANUAL_DECAY, EPS, "direct after 4 days: 0.58")
	check_near(_cert(about_npc), 0.5 - 4.0 * MANUAL_DECAY, EPS, "belief about an NPC: 0.18")
	_advance_day(GameClock.get_day())
	check_near(_cert(direct), MANUAL_DIRECT - 5.0 * MANUAL_DECAY, EPS, "day_advanced decays (0.50)")


## El preset «decaimiento_sospecha» escala el decaimiento de TODAS las creencias ordinarias.
func _test_difficulty_presets() -> void:
	var default_preset: String = Database.get_difficulty_preset()
	for preset: Array in [["interno", MANUAL_INTERNO_DECAY], ["auditoria", MANUAL_AUDITORIA_DECAY]]:
		check(Database.set_difficulty_preset(preset[0]), "switch to the '%s' preset" % preset[0])
		check_near(Database.get_difficulty_modifier(DIFFICULTY_KEY), preset[1], EPS,
				"'%s': decaimiento_sospecha %.1f" % preset)
		_fresh()
		var mine: String = BeliefNet.create_belief("npc_t_a", PLAYER, THEFT, MANUAL_DIRECT,
				"direct", "")
		var other: String = BeliefNet.create_belief("npc_t_a", "npc_t_x", THEFT, MANUAL_DIRECT,
				"direct", "")
		var record: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
		BeliefNet.apply_daily_decay()
		var expected: float = MANUAL_DIRECT - MANUAL_DECAY * float(preset[1])
		check_near(_cert(mine), expected, EPS, "'%s': suspicion beliefs lose 0.08 × %.1f" % preset)
		check_near(_cert(other), expected, EPS, "'%s': beliefs about NPCs too" % preset[0])
		check_near(_cert(record), 1.0, EPS, "'%s': records never decay" % preset[0])
	Database.set_difficulty_preset(default_preset)


# ─── Registros (§7.6, §12.4) ──────────────────────────────────

func _test_records_never_decay_and_destroy() -> void:
	_fresh()
	var footage: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	var card: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	var ordinary: String = BeliefNet.create_belief("npc_t_a", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	_decay_days(30)
	check_near(_cert(footage), 1.0, EPS, "footage still 1.00 after 30 days")
	check_near(_cert(card), 1.0, EPS, "card log still 1.00 after 30 days")
	check(BeliefNet.get_belief(ordinary) == null, "while the ordinary belief was forgotten")
	check(not BeliefNet.is_record_neutral(footage), "create_record never makes a neutral record")
	var before: float = _suspicion()
	var part: float = _contribution_of(footage)
	check_near(part, 22.5, EPS, "the footage contributes 22.5")
	check(BeliefNet.destroy_record(footage, "deleted_in_monitor_room"), "destroy_record → true")
	check_eq(_destroyed.back(), [footage, "deleted_in_monitor_room"], "record_destroyed emitted")
	check(BeliefNet.get_belief(footage) == null, "the record is gone")
	check_near(_suspicion(), before - part, EPS, "suspicion drops by the record's contribution")
	_check_last_change(before - part, "after destroy_record")
	_check_cache("after destroy_record")
	check(not BeliefNet.destroy_record(footage, "again"), "destroying twice → false")
	var belief: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, 0.5, "direct", ROOM)
	check(not BeliefNet.destroy_record(belief, "x"), "destroy_record refuses ordinary beliefs")
	check(BeliefNet.get_belief(belief) != null, "... which survive")


## Security.delete_footage emite crime_committed("footage_deleted", …, {camera_id, room_id, day,
## footage_id, method}): se borra UNA copia por clip, no todas las de la cámara y el día.
func _test_footage_deletion() -> void:
	_fresh()
	EventBus.camera_recorded_player.emit("cam_a", RESTRICTED, 3)
	EventBus.camera_recorded_player.emit("cam_a", RESTRICTED, 3)
	EventBus.camera_recorded_player.emit("cam_b", CORRIDOR, 3)
	var clip: Dictionary = {"camera_id": "cam_a", "room_id": RESTRICTED, "day": 3,
			"footage_id": "cam_cfo_office_3_10_1", "method": "deleted_in_monitor_room"}
	EventBus.crime_committed.emit("footage_deleted", MONITOR_ROOM, clip)
	check_eq(_records_of(PLAYER, "footage").size(), 2, "one deleted clip → one record destroyed")
	check_eq(_destroyed.size(), 1, "record_destroyed fires once for BeliefNet's copy")
	check_near(_suspicion(), 22.5, EPS, "the other clip of cam_a still shows the player")
	clip["footage_id"] = "cam_cfo_office_3_10_2"
	EventBus.crime_committed.emit("footage_deleted", MONITOR_ROOM, clip)
	check_near(_suspicion(), 0.0, EPS, "both cam_a clips deleted → suspicion 0")
	_check_last_change(0.0, "after deleting the footage")
	EventBus.crime_committed.emit("footage_deleted", MONITOR_ROOM,
			{"camera_id": "cam_b", "hour": WORK_HOUR + 1})
	check_eq(_records_of(PLAYER, "footage").size(), 1, "an hour filter that does not match")
	EventBus.crime_committed.emit("footage_deleted", MONITOR_ROOM, {})
	check_eq(_records_of(PLAYER, "footage").size(), 1, "no selection → nothing erased")
	EventBus.crime_committed.emit("footage_deleted", MONITOR_ROOM, {"camera_id": "cam_b"})
	check(_records_of(PLAYER, "footage").is_empty(), "no footage_id: every cam_b record erased")
	_check_cache("after deletions")


## records_deleted (sala de servidores) borra registros de tarjeta y de chat, no grabaciones, y
## deja el acceso registrado en el propio servidor (§22 server_room).
func _test_digital_records_deleted() -> void:
	_fresh()
	var footage: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	var card: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	var chat: String = BeliefNet.create_record("chat_log", PLAYER, MANUAL_CARD, ROOM)
	EventBus.crime_committed.emit("records_deleted", SERVER_ROOM, {"subject": PLAYER})
	check(BeliefNet.get_belief(card) == null and BeliefNet.get_belief(chat) == null,
			"records_deleted erases card and chat logs about the player")
	check(BeliefNet.get_belief(footage) != null, "... but not the footage")
	var trace: Belief = _only(_records_of(PLAYER, "card_log"), "the server logs the access")
	check_eq([trace.location, trace.fact], [SERVER_ROOM, "card_log:server_room"], "trace fields")
	check(not BeliefNet.is_record_neutral(trace.id), "server room is beyond clearance: counts")
	check_near(_suspicion(), 22.5 + 12.5, EPS, "footage 22.5 + server access 12.5")


func _test_crime_records() -> void:
	_fresh()
	EventBus.crime_committed.emit("forgery", "c10_office", {})
	var stamped: Belief = _only(_records_of(PLAYER, "stamped_document"), "forgery -> document")
	check_near(stamped.weight, MANUAL_FORGED, EPS, "forged document evidence weight 5.0")
	check_eq(BeliefNet.get_neutral_reason(stamped.id), "unverified", "§5.3: pending verification")
	check_near(_suspicion(), 0.0, EPS, "an unverified forgery does not weigh yet")
	check(BeliefNet.confirm_record(stamped.id), "confirm_record verifies it")
	check_near(_suspicion(), 25.0, EPS, "verified: 1.0 × 0.15 × 5.0 × 100 / 3 = 25")
	check(not BeliefNet.confirm_record(stamped.id), "confirming twice → false")
	EventBus.crime_committed.emit("forgery", "c10_office", {"verified": true})
	check_near(_suspicion(), 50.0, EPS, "details.verified: the document counts at once")
	EventBus.crime_committed.emit("fraud", "accounting", {})
	var pending: Array[Dictionary] = BeliefNet.get_pending_records()
	check_eq(pending.size(), 1, "fraud: the accounting trail is delayed (§12.4)")
	var due: int = GameClock.get_day() \
			+ Database.get_balance_int("creencias.registros_por_delito.fraud.retardo_dias")
	check_eq(int(pending[0]["due_day"]) if pending.size() == 1 else -1, due, "due day")
	_advance_day(due - 1)
	check(_records_of(PLAYER, "accounting_entry").is_empty(), "not yet surfaced the day before")
	_advance_day(due)
	var entry: Belief = _only(_records_of(PLAYER, "accounting_entry"), "surfaces on its due day")
	check_near(entry.weight, MANUAL_ACCOUNTING, EPS, "accounting trail weight 3.0")
	check_eq(entry.timestamp, due, "stamped with the day it surfaces")
	check_near(_suspicion(), 65.0, EPS, "two forgeries 50 + accounting 3.0 × 5 = 65")
	check(BeliefNet.get_pending_records().is_empty(), "no pending records left")


## Una investigación que toma el documento como pieza lo verifica (evidence_added).
func _test_forgery_verified_by_investigation() -> void:
	_fresh()
	Security.reset_for_new_run()
	EventBus.crime_committed.emit("forgery", "c10_office", {})
	var stamped: Belief = _only(_records_of(PLAYER, "stamped_document"), "forged document")
	check(BeliefNet.is_record_neutral(stamped.id), "unverified before the investigation")
	var case_id: String = Security.report_incident("direct_witness_report", 0, "c10_office", true,
			{"record_id": stamped.id, "evidence_type": "forged_document", "subject": PLAYER,
			"weight": MANUAL_FORGED})
	check(not case_id.is_empty(), "precondition: the incident opened or joined a case")
	check(not BeliefNet.is_record_neutral(stamped.id), "evidence_added verified the document")
	check_near(_suspicion(), 25.0, EPS, "the verified forgery now weighs 25")
	_check_cache("after verification")
	Security.reset_for_new_run()


# ─── Sospecha (§7.2) ──────────────────────────────────────────

func _test_suspicion_formula() -> void:
	_fresh()
	BeliefNet.create_belief("npc_t_debbie", PLAYER, "seen_partially", MANUAL_PARTIAL, "direct",
			ROOM)
	var id2: String = BeliefNet.create_belief("npc_t_george", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var id3: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	var id4: String = BeliefNet.transfer_belief(id2, "npc_t_rose", MANUAL_ORAL)
	BeliefNet.create_belief("npc_t_debbie", PLAYER, "hard_worker", 0.8, "direct", ROOM)
	BeliefNet.create_belief("npc_t_george", "npc_t_x", THEFT, MANUAL_DIRECT, "direct", ROOM)
	var suspicion: float = _suspicion()
	check_near(suspicion, 55.4,
			EPS, "by hand: (0.35×0.15×0.8 + 0.9×0.15×4 + 1×0.15×4.5 + 0.675×0.15×4) × 100/3 = 55.4")
	_check_last_change(suspicion, "after the formula set-up")
	_check_cache("formula")
	var breakdown: Array[Dictionary] = BeliefNet.get_suspicion_breakdown()
	check_eq(breakdown.size(), 4, "breakdown: 4 entries (neutral fact and NPC subject excluded)")
	var total: float = 0.0
	var sorted_ok: bool = true
	for i: int in breakdown.size():
		total += float(breakdown[i]["contribution"])
		sorted_ok = sorted_ok and breakdown[i].has_all(BREAKDOWN_KEYS)
		if i > 0:
			var previous: float = breakdown[i - 1]["contribution"]
			sorted_ok = sorted_ok and previous >= float(breakdown[i]["contribution"])
	check(sorted_ok, "breakdown entries have all keys and are sorted by contribution")
	check_near(total, suspicion, EPS, "breakdown contributions add up to the suspicion")
	check_eq(breakdown[0]["belief_id"] if not breakdown.is_empty() else "", id3,
			"the footage is the heaviest piece (22.5)")
	check_near(_contribution_of(id4), 13.5, EPS,
			"a rumour weighs like its fact: 0.675 × 0.15 × 4.0 × 100/3 = 13.5 (no origin factor)")


## §12.2: Seguridad +20, superior +10 (con anotación en expediente); NPCDirector envía el peso de
## evidencia de §12.4 (testigo directo 4,0; ante el superior × 0,5; parcial 0,8).
func _test_reports() -> void:
	_fresh()
	var cases: Array = [
		["npc_t_sec", "security", MANUAL_SECURITY_REPORT, MANUAL_SECURITY_REPORT],
		["npc_t_sup", "superior", MANUAL_SUPERIOR_REPORT, MANUAL_SUPERIOR_REPORT],
		["npc_t_anon", "anonymous_tip", DOC_ANONYMOUS_REPORT, DOC_ANONYMOUS_REPORT],
		["npc_t_w1", "direct_witness", MANUAL_DIRECT_WITNESS, MANUAL_SECURITY_REPORT],
		["npc_t_w2", "direct_witness", MANUAL_DIRECT_WITNESS * 0.5, MANUAL_SUPERIOR_REPORT],
		["npc_t_w3", "partial_witness", MANUAL_PARTIAL_WITNESS, 4.0],
	]
	for c: Array in cases:
		var before: float = _suspicion()
		EventBus.npc_reported_player.emit(c[0], c[1], c[2], ROOM)
		var report: Belief = _only(BeliefNet.get_beliefs_held_by(c[0]), "%s report" % c[1])
		check_eq(report.fact, "reported:" + str(c[1]), "report fact for %s" % c[1])
		check_near(_suspicion() - before, c[3], EPS,
				"%s (weight %.1f) → +%.0f" % [c[1], c[2], c[3]])
	check_near(_suspicion(), 74.0, EPS, "20 + 10 + 10 + 20 + 10 + 4 = 74")
	_check_cache("reports")
	var notes: Array[Belief] = _records_of(PLAYER, "stamped_document")
	var note: Belief = _only(notes, "only the superior report leaves a file annotation")
	check_eq(note.fact, "stamped_document:file_annotation", "annotation fact")
	check_near(note.weight, DOC_ANNOTATION_WEIGHT, EPS, "annotation evidence weight 1.0")
	check_eq(BeliefNet.get_neutral_reason(note.id), "annotation", "§12.2 stays +10 exactly")


func _test_report_merge_and_clamp() -> void:
	_fresh()
	EventBus.npc_reported_player.emit("npc_t_m", "direct_witness", MANUAL_DIRECT_WITNESS * 0.5,
			ROOM)
	check_near(_suspicion(), MANUAL_SUPERIOR_REPORT, EPS, "first report (superior): +10")
	EventBus.npc_reported_player.emit("npc_t_m", "direct_witness", MANUAL_DIRECT_WITNESS, ROOM)
	check_eq(BeliefNet.get_beliefs_held_by("npc_t_m").size(), 1, "the second report merges")
	check_near(_suspicion(), MANUAL_SECURITY_REPORT, EPS,
			"a merge keeps the larger weight: suspicion 20 (not 10, not 30)")
	for _i: int in 20:
		BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	check_near(_suspicion(), SUSPICION_MAX, EPS, "clamped to 100")
	_check_cache("clamped")


# ─── Moduladores de reputación (§7.10, PASO 14) ───────────────

func _test_reputation_modulators() -> void:
	var rep: float = 80.0
	_fresh(rep)
	var birth: float = _bal("creencias.mod_certeza_inicial_por_reputacion_jugador")
	check_near(birth, MANUAL_BIRTH_MOD, EPS, "balance: −0.002 per reputation point")
	check_near(_bal("creencias.mod_credibilidad_por_reputacion"), MANUAL_CREDIBILITY_MOD, EPS,
			"balance: credibility 0.003 per reputation point")
	EventBus.player_seen_partially.emit("npc_t_a", MANUAL_PARTIAL, ROOM)
	var partial: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_a"), "partial at rep 80")
	check_near(partial.certainty, 0.19, EPS, "rep 80: 0.35 − 0.002 × 80 = 0.19")
	EventBus.player_caught_redhanded.emit("npc_t_b", "theft_small", 1)
	var caught: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_b"), "flagrancy at rep 80")
	check_near(caught.certainty, 0.74, EPS, "rep 80: 0.90 − 0.16 = 0.74")
	var neutral: String = BeliefNet.create_belief("npc_t_c", PLAYER, "hard_worker", 0.6,
			"direct", "")
	var other: String = BeliefNet.create_belief("npc_t_c", "npc_t_x", THEFT, 0.5, "direct", "")
	check_near(_cert(neutral), 0.6, EPS, "non-negative beliefs are born intact")
	check_near(_cert(other), 0.5, EPS, "beliefs about NPCs are born intact")
	var rumor: String = BeliefNet.transfer_belief(caught.id, "npc_t_d", MANUAL_ORAL)
	check_near(_cert(rumor), caught.certainty * MANUAL_ORAL, EPS, "a rumour is not reduced twice")
	var record: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	check_near(_cert(record), 1.0, EPS, "records are born at 1.00 regardless of reputation")
	var caught_before: float = caught.certainty
	var rumor_before: float = _cert(rumor)
	BeliefNet.apply_daily_decay()
	var fast: float = MANUAL_DECAY * (1.0 + _bal("creencias.mod_decaimiento_por_reputacion_jugador")
			* rep)
	check(fast > MANUAL_DECAY, "high reputation accelerates the decay of suspicion")
	check_near(caught.certainty, caught_before - fast, EPS, "rep 80: 0.74 − 0.08 × 1.8 = 0.596")
	check_near(_cert(rumor), rumor_before - fast, EPS, "rumours about the player decay faster too")
	check_near(_cert(neutral), 0.6 - MANUAL_DECAY, EPS, "non-negative beliefs: base decay")
	check_near(_cert(other), 0.5 - MANUAL_DECAY, EPS, "beliefs about NPCs: base decay")
	check(BeliefNet.get_belief(partial.id) == null, "rep 80: a partial sighting is gone in 1 day")
	check_near(_cert(record), 1.0, EPS, "records still never decay")


# ─── Refuerzo, fusión y olvido explícito ──────────────────────

func _test_reinforcement_and_merge() -> void:
	_fresh()
	var id: String = BeliefNet.create_belief("npc_t_a", PLAYER, "seen_partially", MANUAL_PARTIAL,
			"direct", ROOM)
	BeliefNet.apply_daily_decay()
	check_eq(BeliefNet.get_days_since_reinforced(id), 1, "decay clock: 1 day")
	BeliefNet.reinforce_belief(id, 0.2)
	check_near(_cert(id), MANUAL_PARTIAL + 0.2, EPS, "reinforcement restores 0.35 and adds 0.2")
	check_eq(_decayed.back(), [id, _cert(id)], "reinforcement announces the new certainty")
	check_eq(BeliefNet.get_days_since_reinforced(id), 0, "reinforcement restarts the decay clock")
	BeliefNet.apply_daily_decay()
	check_near(_cert(id), MANUAL_PARTIAL + 0.2 - MANUAL_DECAY, EPS, "decay resumes from 0.55")
	BeliefNet.reinforce_belief(id, -0.5)
	check(BeliefNet.get_belief(id) == null and _forgotten.has(id),
			"a negative reinforcement below 0.10 forgets the belief")
	var src: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var copy1: String = BeliefNet.transfer_belief(src, "npc_t_c", 0.5)
	var copy2: String = BeliefNet.transfer_belief(src, "npc_t_c", MANUAL_ORAL)
	check_eq(copy2, copy1, "hearing the same rumour again reuses the belief")
	check_near(_cert(copy1), MANUAL_DIRECT * MANUAL_ORAL, EPS, "rumours merge by maximum (0.675)")
	check_eq(_decayed.back(), [copy1, _cert(copy1)], "the raised rumour announces its certainty")
	var events: int = _decayed.size()
	check_eq(BeliefNet.transfer_belief(src, "npc_t_c", 0.5), copy1,
			"a weaker telling returns the listener's existing belief (documented)")
	check_near(_cert(copy1), MANUAL_DIRECT * MANUAL_ORAL, EPS, "... and does not lower it")
	check_eq(_decayed.size(), events, "... nor announces an unchanged certainty")
	check_eq(BeliefNet.transfer_belief(src, "npc_t_e", 0.1), "", "0.09 < 0.10: does not take hold")
	var rec: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	BeliefNet.reinforce_belief(rec, -1.0)
	check_near(_cert(rec), 1.0, EPS, "records ignore reinforcement")


func _test_forgetting_api() -> void:
	_fresh()
	var direct: String = BeliefNet.create_belief("npc_t_a", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var rumour1: String = BeliefNet.transfer_belief(direct, "npc_t_b", MANUAL_ORAL)
	var rumour2: String = BeliefNet.transfer_belief(direct, "npc_t_c", MANUAL_ORAL)
	var record: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	check_eq(BeliefNet.forget_rumours(THEFT), 2, "forget_rumours: both rumours of the fact")
	check(BeliefNet.get_belief(rumour1) == null and BeliefNet.get_belief(rumour2) == null
			and _forgotten.has(rumour1), "the rumours are forgotten (belief_forgotten)")
	check(BeliefNet.get_belief(direct) != null, "the direct belief survives forget_rumours")
	check(not BeliefNet.forget_belief(record), "forget_belief refuses records")
	check(BeliefNet.forget_belief(direct), "forget_belief → true")
	check(_forgotten.has(direct), "belief_forgotten emitted")
	check_near(_suspicion(), 22.5, EPS, "only the footage is left")
	_check_last_change(22.5, "after forget_belief")
	check(not BeliefNet.forget_belief(direct), "forgetting twice → false")


func _test_witness_removed_and_body() -> void:
	_fresh()
	var w1: String = BeliefNet.create_belief("npc_t_witness", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var w2: String = BeliefNet.create_belief("npc_t_witness", PLAYER, "seen_partially",
			MANUAL_PARTIAL, "direct", ROOM)
	var spread: String = BeliefNet.transfer_belief(w1, "npc_t_friend", MANUAL_ORAL)
	var rec: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	EventBus.npc_removed.emit("npc_t_witness", "expelled")
	check(BeliefNet.get_belief(w1) == null and BeliefNet.get_belief(w2) == null,
			"an expelled witness takes their beliefs away (§12.4)")
	check(_forgotten.has(w1) and _forgotten.has(w2), "belief_forgotten for each")
	check(BeliefNet.get_belief(spread) != null, "rumours already spread survive")
	check(BeliefNet.get_belief(rec) != null, "records survive")
	var signed: Belief = _only(BeliefNet.get_records_about("npc_t_witness"),
			"§7.6: the expulsion leaves a signed expulsion record")
	check_eq([signed.record_type, signed.weight], ["signed_expulsion", 0.0], "signed expulsion")
	EventBus.npc_removed.emit("npc_t_victim", "eliminated")
	check(BeliefNet.get_records_about("npc_t_victim").is_empty(), "an elimination signs nothing")
	var before: float = _suspicion()
	EventBus.body_discovered.emit("body_1", ROOM)
	var body: Belief = _only(BeliefNet.get_records_about("unknown"), "body found → record")
	check_eq(body.record_type, "body_found", "body record type")
	var press: float = _bal("noticias.sospecha_escandalo_general") \
			* _bal("creencias.factor_peso_social_noticias")
	check_near(BeliefNet.get_news_contribution(), press, EPS,
			"§7.11: the body is also a company scandal (general vigilance +%.1f)" % press)
	check_near(_suspicion() - press, before, EPS,
			"a body names nobody: the record adds no suspicion (only the press does)")


## Un tipo de hecho sin peso_tipo es neutro (revisión: "is_friendly" daba sospecha 4,5).
func _test_unknown_fact_is_neutral() -> void:
	_fresh(80.0)
	var id: String = BeliefNet.create_belief("npc_t_a", PLAYER, "is_friendly", 0.9, "direct", "")
	check(not BeliefNet.is_negative_fact("is_friendly"), "unknown fact: not negative")
	check_near(_suspicion(), 0.0, EPS, "unknown fact: no suspicion")
	check_near(_cert(id), 0.9, EPS, "unknown fact: not reduced at birth by reputation")
	BeliefNet.create_belief("npc_t_b", PLAYER, "debug_observed", 1.0, "direct", "")
	check(_suspicion() > 0.0, "the F1 debug belief type still counts")


# ─── Rumores (protocolo de social_graph.gd, PASO 15) ──────────

func _test_rumour_protocol() -> void:
	_fresh()
	SocialGraph.reset_for_new_run()
	var rumour_id: String = SocialGraph.inject_rumour_about(DEBBIE, PLAYER, THEFT, 0.8)
	var planted: Belief = _only(BeliefNet.get_beliefs_held_by(DEBBIE), "planted rumour → belief")
	check_eq([planted.subject, planted.fact, planted.source], [PLAYER, THEFT, "rumor"],
			"rumor_spread(player, Debbie, %s) creates the described rumour" % rumour_id)
	check_near(planted.certainty, 0.8, EPS, "with the planted certainty")
	check_near(_suspicion(), 16.0, EPS, "by hand: 0.8 × 0.15 × 4.0 × 100/3 = 16")
	SocialGraph.add_link(DEBBIE, GEORGE, "friendship", 0.7)
	var factor: float = SocialGraph.get_transfer_factor(DEBBIE, GEORGE, THEFT, PLAYER)
	check(factor > 0.0, "precondition: friendship propagates the fact")
	EventBus.rumor_spread.emit(DEBBIE, GEORGE, planted.id)
	var heard: Belief = _only(BeliefNet.get_beliefs_held_by(GEORGE), "a hop → George's copy")
	check_near(heard.certainty, 0.8 * factor, EPS, "copy = 0.8 × the link's transfer factor")
	EventBus.rumor_spread.emit(DEBBIE, "npc_t_stranger", planted.id)
	check(BeliefNet.get_beliefs_held_by("npc_t_stranger").is_empty(), "no link → nothing")
	var direct: String = BeliefNet.create_belief("npc_t_eye", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	SocialGraph.add_link(DEBBIE, CLAUDIA, "friendship", 0.7)
	SocialGraph.kill_rumour(THEFT)
	EventBus.rumor_spread.emit(DEBBIE, CLAUDIA, planted.id)
	check(BeliefNet.get_beliefs_held_by(CLAUDIA).is_empty(), "a buried fact does not take hold")
	BeliefNet.apply_daily_decay()
	check(BeliefNet.get_belief(planted.id) == null and BeliefNet.get_belief(heard.id) == null,
			"the daily decay forgets the rumours of a buried fact")
	check(BeliefNet.get_belief(direct) != null, "a direct belief of that fact survives")
	_check_cache("after burying the rumour")
	SocialGraph.reset_for_new_run()


# ─── Guardado y carga ─────────────────────────────────────────

func _test_save_load_round_trip() -> void:
	var state: Dictionary = _build_saved_state()
	var partial: String = state["partial"]
	var ids: Array = state["ids"]
	var text: String = JSON.stringify(BeliefNet.save_state())
	var suspicion: float = _suspicion()
	BeliefNet.reset_for_new_run()
	check(BeliefNet.get_beliefs_about(PLAYER).is_empty() and _suspicion() == 0.0,
			"reset_for_new_run empties the net")
	_check_last_old(suspicion, "reset: old value")
	_check_last_change(0.0, "reset: new value 0")
	_check_cache("after reset")
	Validate.clear_errors()
	BeliefNet.load_state(JSON.parse_string(text))
	check(not Validate.has_errors(), "the saved state validates on load")
	check_eq(JSON.stringify(BeliefNet.save_state()), text, "save → JSON → load → save is identical")
	check_near(_suspicion(), suspicion, EPS, "same suspicion after load")
	_check_last_old(0.0, "load: old value")
	_check_last_change(suspicion, "load: recomputed value")
	_check_cache("after load")
	check_eq(BeliefNet.get_neutral_reason(state["routine"]), "routine",
			"routine footage stays neutral")
	check_eq(BeliefNet.get_pending_records().size(), 1, "pending records survive")
	var fresh_id: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	check(not ids.has(fresh_id), "ids keep counting after load (no collisions)")
	GameClock.set_time(DAY, WORK_HOUR, 30)
	EventBus.camera_recorded_player.emit("cam_w", ROOM, DAY)
	check(not BeliefNet.is_record_neutral(_records_of(PLAYER, "footage").back().id),
			"the crime mark of the room survives the round trip")
	BeliefNet.reinforce_belief(partial, 0.0)
	check_near(_cert(partial), MANUAL_PARTIAL + MANUAL_BIRTH_MOD * 30.0, EPS,
			"the reinforcement reference (0.29) survives the round trip")


## Estado con todo lo que se guarda: creencias, rumor, registro rutinario, anotación, registro
## diferido, documento sin verificar y marca de delito. → {partial, routine, ids}
func _build_saved_state() -> Dictionary:
	_fresh(30.0)
	EventBus.player_seen_partially.emit("npc_t_a", MANUAL_PARTIAL, ROOM)
	var partial: String = BeliefNet.get_beliefs_held_by("npc_t_a")[0].id
	var caught: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", "")
	BeliefNet.transfer_belief(caught, "npc_t_c", MANUAL_ORAL)
	EventBus.camera_recorded_player.emit("cam_s", CORRIDOR, DAY)
	var routine: String = _records_of(PLAYER, "footage")[0].id
	EventBus.npc_reported_player.emit("npc_t_d", "superior", MANUAL_SUPERIOR_REPORT, ROOM)
	EventBus.crime_committed.emit("fraud", "accounting", {})
	EventBus.crime_committed.emit("forgery", "c10_office", {})
	EventBus.crime_committed.emit("theft_small", ROOM, {})
	BeliefNet.apply_daily_decay()
	var ids: Array[String] = []
	for b: Belief in BeliefNet.get_beliefs_about(PLAYER) + BeliefNet.get_records_about(PLAYER):
		ids.append(b.id)
	return {"partial": partial, "routine": routine, "ids": ids}


# ─── Credibilidad real de los portadores (población generada) ─

## §7.2: credibilidad_portador = reputación del personaje (NPCDirector) × 0,003.
func _test_population_credibility() -> void:
	check(new_run(DEFAULT_SEED, true), "fresh run with the generated population")
	_fresh()
	var other: String = _npc_with_other_reputation(DEBBIE)
	check(NPCDirector.get_npc(DEBBIE) != null and not other.is_empty(),
			"precondition: Debbie and a colleague with a different reputation exist")
	var rep_d: float = NPCDirector.get_npc_reputation(DEBBIE)
	var rep_o: float = NPCDirector.get_npc_reputation(other)
	print("[beliefs] reputation %s = %.2f, %s = %.2f" % [DEBBIE, rep_d, other, rep_o])
	var id_d: String = BeliefNet.create_belief(DEBBIE, PLAYER, THEFT, MANUAL_DIRECT, "direct", ROOM)
	var id_o: String = BeliefNet.create_belief(other, PLAYER, THEFT, MANUAL_DIRECT, "direct", ROOM)
	check_near(BeliefNet.get_credibility(DEBBIE), rep_d * 0.003, EPS, "credibility = rep × 0.003")
	check_near(_contribution_of(id_d), 0.9 * (rep_d * 0.003) * 4.0 * 100.0 / 3.0, EPS,
			"Debbie's belief: 0.9 × (rep × 0.003) × 4.0 × 100 / 3")
	check_near(_contribution_of(id_o), 0.9 * (rep_o * 0.003) * 4.0 * 100.0 / 3.0, EPS,
			"the colleague's belief uses the colleague's reputation")
	check(not is_equal_approx(_contribution_of(id_d), _contribution_of(id_o)),
			"two holders with different reputations contribute differently")
	check_near(BeliefNet.get_credibility("npc_t_not_a_character"), DOC_DEFAULT_CREDIBILITY, EPS,
			"a holder that is not a character uses the default credibility")
	await _check_grievance_refresh(id_d)


## Un agravio baja la reputación del portador: la caché de PlayerState se actualiza (diferido) y
## una reputación real de 0 da credibilidad 0, no la de por defecto.
func _check_grievance_refresh(debbie_belief: String) -> void:
	var before: float = PlayerState.get_suspicion()
	NPCDirector.add_grievance(DEBBIE, "test_grievance", 2)
	await wait_frames(2)
	check(PlayerState.get_suspicion() < before, "a grievance lowers the holder's weight")
	_check_cache("after grievance_added")
	NPCDirector.add_grievance(DEBBIE, "test_grievance", 1000)
	await wait_frames(2)
	check_near(NPCDirector.get_npc_reputation(DEBBIE), 0.0, EPS, "precondition: reputation 0")
	check_near(BeliefNet.get_credibility(DEBBIE), 0.0, EPS, "reputation 0 → credibility 0")
	check_near(_contribution_of(debbie_belief), 0.0, EPS, "... so her belief adds nothing")
	_check_cache("after reputation 0")


func _npc_with_other_reputation(npc_id: String) -> String:
	var reference: float = NPCDirector.get_npc_reputation(npc_id)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.id != npc_id and not is_equal_approx(NPCDirector.get_npc_reputation(npc.id),
				reference):
			return npc.id
	return ""
