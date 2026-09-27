# beliefs_case.gd — Cuerpo de test_beliefs: certezas por origen, decaimiento, registros, sospecha, moduladores y guardado.
# PROPIETARIO DE: nada.
# ESCUCHA: belief_created, belief_decayed, belief_forgotten, record_created, record_destroyed, suspicion_changed (solo para comprobarlas).
extends TestCase

const EPS := 0.000001
const PLAYER := "player"
const ROOM := "wing_3b"
const CORRIDOR := "corridors_low@3"
const THEFT := "caught_redhanded:theft_small"
const DIFFICULTY_KEY := "decaimiento_sospecha"
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
const MANUAL_REPORT_WEIGHT := 4.0
const MANUAL_REPORT_SUSPICION := 20.0
const MANUAL_INTERNO_DECAY := 1.4
# Calibración documentada en balance (creencias.*) para el cálculo a mano de la sospecha.
const DOC_DEFAULT_CREDIBILITY := 0.15
const DOC_DIVISOR := 3.0
const DOC_RUMOR_WEIGHT := 0.5
const DOC_HAND_SUSPICION := 48.65
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
	_test_manual_numbers()
	_test_creation_by_source()
	_test_records_from_signals()
	_test_decay_after_days()
	_test_difficulty_preset()
	_test_records_never_decay_and_destroy()
	_test_crime_records()
	_test_suspicion_formula()
	_test_report_and_clamp()
	_test_reputation_modulators()
	_test_reinforcement_and_merge()
	_test_witness_removed()
	_test_save_load_round_trip()


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
func _fresh(reputation: float = 0.0) -> void:
	BeliefNet.reset_for_new_run()
	EventBus.reputation_changed.emit(reputation, reputation)
	for entries: Array in [_created, _decayed, _forgotten, _records, _destroyed, _suspicion_events]:
		entries.clear()


func _bal(path: String) -> float:
	return Database.get_balance_float(path)


func _cert(id: String) -> float:
	var b: Belief = BeliefNet.get_belief(id)
	return b.certainty if b != null else -1.0


## Credibilidad esperada según §7.2 + BUILD_NOTES §13 (reputación de NPCDirector o 50 por defecto;
## el archivo de registros no es un personaje).
func _cred(holder: String) -> float:
	var rep: float = 0.0
	if holder != "archive" and NPCDirector.has_method("get_npc_reputation"):
		rep = float(NPCDirector.call("get_npc_reputation", holder))
	if rep <= 0.0:
		rep = _bal("creencias.reputacion_portador_por_defecto")
	return rep * _bal("creencias.mod_credibilidad_por_reputacion")


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


# ─── Balance = manual ─────────────────────────────────────────

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
	check_near(_bal("creencias.peso_tipo.seen_partially"),
			_bal("investigaciones.pesos_evidencia.testigo_parcial"), EPS,
			"suspicion weight of a partial sighting = partial witness weight (0.8)")
	check_near(_bal("creencias.peso_tipo.caught_redhanded"),
			_bal("investigaciones.pesos_evidencia.testigo_directo"), EPS,
			"suspicion weight of flagrancy = direct witness weight (4.0)")


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
			_bal("creencias.descuento_por_transmision")))
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
	check_eq(BeliefNet.get_beliefs_about(PLAYER).size(), 4, "4 ordinary beliefs about the player")
	check_eq(BeliefNet.count_credible_beliefs_about(PLAYER, 0.5), 3,
			"credible (>= 0.5): 0.70, 0.90, 0.675 — not 0.4025")


func _test_records_from_signals() -> void:
	_fresh()
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, 12)
	var footage: Belief = _only(BeliefNet.get_records_about(PLAYER), "camera -> 1 record")
	check_eq([footage.is_record, footage.record_type, footage.source, footage.timestamp,
			footage.location, footage.holder], [true, "footage", "record", 12, CORRIDOR, "archive"],
			"footage record fields (day and room from the signal)")
	check_near(footage.certainty, 1.0, EPS, "documentary record -> certainty 1.00")
	check_near(footage.weight, MANUAL_FOOTAGE, EPS, "footage weight 4.5")
	check_eq(_records.back(), [footage.id, "footage", footage.weight], "record_created emitted")
	check(BeliefNet.get_beliefs_about(PLAYER).is_empty(), "records are not listed as beliefs")
	EventBus.card_reader_logged.emit("reader_elevator_1", PLAYER, 12, 9)
	var records: Array[Belief] = BeliefNet.get_records_about(PLAYER)
	check_eq(records.size(), 2, "own card -> card_log record about the player")
	if records.size() == 2:
		check_eq(records[1].record_type, "card_log", "record type card_log")
		check_near(records[1].weight, MANUAL_CARD, EPS, "card log weight 2.5")
	EventBus.card_reader_logged.emit("reader_elevator_1", "npc_t_claudia", 12, 10)
	check_eq(BeliefNet.get_records_about("npc_t_claudia").size(), 1,
			"stolen card -> the log names the card owner (§5.3)")
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 2, "... and not the player")
	PlayerState.set_disguise("security_guard")
	EventBus.camera_recorded_player.emit("cam_p03_1", CORRIDOR, 12)
	PlayerState.set_disguise("")
	check_eq(BeliefNet.get_records_about("uniform:security_guard").size(), 1,
			"disguised: the camera records the uniform, not the identity (§5.3)")
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 2, "... so no new record on the player")


# ─── Decaimiento y olvido (§7.6) ──────────────────────────────

func _test_decay_after_days() -> void:
	_fresh()
	var partial: String = BeliefNet.create_belief("npc_t_a", PLAYER, "seen_partially",
			MANUAL_PARTIAL, "direct", ROOM)
	var direct: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var about_npc: String = BeliefNet.create_belief("npc_t_c", "npc_t_x", THEFT, 0.5, "direct", "")
	var difficulty: float = Database.get_difficulty_modifier(DIFFICULTY_KEY)
	check_near(difficulty, 1.0, EPS, "default preset: decaimiento_sospecha × 1.0")
	var rate: float = MANUAL_DECAY * difficulty
	BeliefNet.apply_daily_decay()
	check_near(_cert(partial), MANUAL_PARTIAL - rate, EPS, "day 1: 0.35 → 0.27")
	check(_decayed.has([partial, _cert(partial)]), "belief_decayed(id, new_certainty) emitted")
	_decay_days(2)
	check_near(_cert(partial), MANUAL_PARTIAL - 3.0 * rate, EPS, "day 3: 0.11, still remembered")
	check(not _forgotten.has(partial), "no belief_forgotten while >= 0.10")
	BeliefNet.apply_daily_decay()
	check(BeliefNet.get_belief(partial) == null, "day 4: 0.03 < 0.10 → forgotten")
	check(_forgotten.has(partial), "belief_forgotten emitted")
	check_near(_cert(direct), MANUAL_DIRECT - 4.0 * rate, EPS, "direct after 4 days: 0.58")
	check_near(_cert(about_npc), 0.5 - 4.0 * MANUAL_DECAY, EPS, "belief about an NPC: 0.18")
	EventBus.day_advanced.emit(GameClock.get_day())
	check_near(_cert(direct), MANUAL_DIRECT - 5.0 * rate, EPS, "day_advanced applies decay (0.50)")


func _test_difficulty_preset() -> void:
	var default_preset: String = str(Database.get_balance("presets_por_defecto"))
	check(Database.set_difficulty_preset("interno"), "switch to the 'interno' preset")
	_fresh()
	var mine: String = BeliefNet.create_belief("npc_t_a", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", "")
	var other: String = BeliefNet.create_belief("npc_t_a", "npc_t_x", THEFT, MANUAL_DIRECT,
			"direct", "")
	BeliefNet.apply_daily_decay()
	check_near(Database.get_difficulty_modifier(DIFFICULTY_KEY), MANUAL_INTERNO_DECAY, EPS,
			"'interno' preset: decaimiento_sospecha 1.4")
	check_near(_cert(mine), MANUAL_DIRECT - MANUAL_DECAY * MANUAL_INTERNO_DECAY, EPS,
			"'interno': suspicion beliefs lose 0.08 × 1.4 = 0.112 per day")
	check_near(_cert(other), MANUAL_DIRECT - MANUAL_DECAY, EPS, "beliefs about NPCs: base 0.08")
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
	var before: float = BeliefNet.calculate_player_suspicion()
	var part: float = _contribution_of(footage)
	check(part > 0.0, "the footage contributes to suspicion")
	check(BeliefNet.destroy_record(footage, "deleted_in_monitor_room"), "destroy_record → true")
	check_eq(_destroyed.back(), [footage, "deleted_in_monitor_room"], "record_destroyed emitted")
	check(BeliefNet.get_belief(footage) == null, "the record is gone")
	check_near(BeliefNet.calculate_player_suspicion(), before - part, EPS,
			"suspicion drops by exactly the record's contribution")
	check(not BeliefNet.destroy_record(footage, "again"), "destroying twice → false")
	var belief: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, 0.5, "direct", ROOM)
	check(not BeliefNet.destroy_record(belief, "x"), "destroy_record refuses ordinary beliefs")
	check(BeliefNet.get_belief(belief) != null, "... which survive")


func _test_crime_records() -> void:
	_fresh()
	EventBus.camera_recorded_player.emit("cam_a", CORRIDOR, 3)
	EventBus.camera_recorded_player.emit("cam_b", CORRIDOR, 3)
	EventBus.crime_committed.emit("footage_deleted", "monitor_room", {"camera_id": "cam_a"})
	var left: Array[Belief] = BeliefNet.get_records_about(PLAYER)
	check(left.size() == 1 and left[0].fact == "footage:cam_b", "footage_deleted erases cam_a only")
	EventBus.crime_committed.emit("footage_deleted", "monitor_room", {})
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 1, "no selection → nothing erased")
	_check_digital_records_deleted()
	EventBus.crime_committed.emit("forgery", "c10_office", {})
	var stamped: Array[Belief] = BeliefNet.get_records_about(PLAYER)
	check(stamped.size() == 2 and stamped[1].record_type == "stamped_document",
			"forgery leaves a stamped document record")
	if stamped.size() == 2:
		check_near(stamped[1].weight, MANUAL_FORGED, EPS, "forged document weight 5.0")
	EventBus.crime_committed.emit("fraud", "accounting", {})
	var pending: Array[Dictionary] = BeliefNet.get_pending_records()
	check_eq(pending.size(), 1, "fraud: the accounting trail is delayed (§12.4)")
	var delay: int = _bal_int("creencias.registros_por_delito.fraud.retardo_dias")
	var due: int = GameClock.get_day() + delay
	check_eq(int(pending[0]["due_day"]) if pending.size() == 1 else -1, due, "due day")
	EventBus.day_advanced.emit(due - 1)
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 2, "not yet surfaced the day before")
	EventBus.day_advanced.emit(due)
	var surfaced: Array[Belief] = BeliefNet.get_records_about(PLAYER)
	check(surfaced.size() == 3 and surfaced[2].record_type == "accounting_entry",
			"the accounting entry surfaces on its due day")
	if surfaced.size() == 3:
		check_near(surfaced[2].weight, MANUAL_ACCOUNTING, EPS, "accounting trail weight 3.0")
		check_eq(surfaced[2].timestamp, due, "stamped with the day it surfaces")
	check(BeliefNet.get_pending_records().is_empty(), "no pending records left")


## records_deleted (sala de servidores) borra registros de tarjeta y de chat, no grabaciones.
func _check_digital_records_deleted() -> void:
	var card: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	var chat: String = BeliefNet.create_record("chat_log", PLAYER, MANUAL_CARD, "wing_3b")
	EventBus.crime_committed.emit("records_deleted", "server_room", {"subject": PLAYER})
	check(BeliefNet.get_belief(card) == null and BeliefNet.get_belief(chat) == null,
			"records_deleted erases card and chat logs about the player")
	check_eq(BeliefNet.get_records_about(PLAYER).size(), 1, "... but not the footage")


func _bal_int(path: String) -> int:
	return Database.get_balance_int(path)


# ─── Sospecha (§7.2) ──────────────────────────────────────────

func _test_suspicion_formula() -> void:
	_fresh()
	var id1: String = BeliefNet.create_belief("npc_t_debbie", PLAYER, "seen_partially",
			MANUAL_PARTIAL, "direct", ROOM)
	var id2: String = BeliefNet.create_belief("npc_t_george", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", ROOM)
	var id3: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	var id4: String = BeliefNet.transfer_belief(id2, "npc_t_rose", MANUAL_ORAL)
	BeliefNet.create_belief("npc_t_debbie", PLAYER, "hard_worker", 0.8, "direct", ROOM)
	BeliefNet.create_belief("npc_t_george", "npc_t_x", THEFT, MANUAL_DIRECT, "direct", ROOM)
	var rumor_w: float = _bal("creencias.peso_origen.rumor")
	var raw: float = MANUAL_PARTIAL * _cred("npc_t_debbie") * MANUAL_PARTIAL_WITNESS \
			+ MANUAL_DIRECT * _cred("npc_t_george") * MANUAL_DIRECT_WITNESS \
			+ 1.0 * _cred("archive") * MANUAL_FOOTAGE \
			+ MANUAL_DIRECT * MANUAL_ORAL * _cred("npc_t_rose") * MANUAL_DIRECT_WITNESS * rumor_w
	var expected: float = raw * SUSPICION_MAX / _bal("creencias.divisor_normalizacion")
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	check_near(suspicion, expected, EPS, "Sospecha = Σ(certeza × credibilidad × peso) normalised")
	if _documented_calibration(["npc_t_debbie", "npc_t_george", "archive", "npc_t_rose"]):
		check_near(suspicion, DOC_HAND_SUSPICION, EPS,
				"by hand: (0.042 + 0.54 + 0.675 + 0.2025) × 100 / 3 = 48.65")
	check(not _suspicion_events.is_empty() and is_equal_approx(_suspicion_events.back()[1],
			suspicion), "suspicion_changed(old, new) carries the recomputed value")
	_check_breakdown(suspicion, id3, id4)
	check(id1 != "", "partial belief created")


func _check_breakdown(suspicion: float, footage_id: String, rumor_id: String) -> void:
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
	if _documented_calibration(["archive"]) and not breakdown.is_empty():
		check_eq(breakdown[0]["belief_id"], footage_id, "the footage is the heaviest piece (22.5)")
	var rumor_weight: float = MANUAL_DIRECT_WITNESS * _bal("creencias.peso_origen.rumor")
	for entry: Dictionary in breakdown:
		if entry["belief_id"] == rumor_id:
			check_near(float(entry["weight"]), rumor_weight, EPS,
					"a rumour weighs peso_tipo × peso_origen.rumor")


func _documented_calibration(holders: Array) -> bool:
	for holder: String in holders:
		if not is_equal_approx(_cred(holder), DOC_DEFAULT_CREDIBILITY):
			return false
	return is_equal_approx(_bal("creencias.divisor_normalizacion"), DOC_DIVISOR) \
			and is_equal_approx(_bal("creencias.peso_origen.rumor"), DOC_RUMOR_WEIGHT)


func _test_report_and_clamp() -> void:
	_fresh()
	var before: float = BeliefNet.calculate_player_suspicion()
	check_near(before, 0.0, EPS, "no beliefs → suspicion 0")
	EventBus.npc_reported_player.emit("npc_t_hardliner", "security", MANUAL_REPORT_SUSPICION, "p15")
	var report: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_hardliner"), "report belief")
	check_eq(report.fact, "reported:security", "report fact")
	var certainty: float = _bal("creencias.certeza_denuncia")
	var divisor: float = _bal("creencias.divisor_normalizacion")
	var default_cred: float = _bal("creencias.reputacion_portador_por_defecto") \
			* _bal("creencias.mod_credibilidad_por_reputacion")
	check_near(report.weight, MANUAL_REPORT_SUSPICION * divisor
			/ (SUSPICION_MAX * default_cred * certainty), EPS, "report points → belief weight")
	var delta: float = BeliefNet.calculate_player_suspicion() - before
	check_near(delta, certainty * _cred("npc_t_hardliner") * report.weight * SUSPICION_MAX
			/ divisor, EPS, "the report adds certainty × credibility × weight")
	if _documented_calibration(["npc_t_hardliner"]):
		check_near(delta, MANUAL_REPORT_SUSPICION, EPS, "§12.2: report to Security → suspicion +20")
		check_near(report.weight, MANUAL_REPORT_WEIGHT, EPS, "... = weight 4.0 (§12.3 report)")
	for _i: int in 20:
		BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	check_near(BeliefNet.calculate_player_suspicion(), SUSPICION_MAX, EPS, "clamped to 100")


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
	check_near(partial.certainty, MANUAL_PARTIAL + birth * rep, EPS, "rep 80: 0.35 − 0.16 = 0.19")
	EventBus.player_caught_redhanded.emit("npc_t_b", "theft_small", 1)
	var caught: Belief = _only(BeliefNet.get_beliefs_held_by("npc_t_b"), "flagrancy at rep 80")
	check_near(caught.certainty, MANUAL_DIRECT + birth * rep, EPS, "rep 80: 0.90 − 0.16 = 0.74")
	var neutral: String = BeliefNet.create_belief("npc_t_c", PLAYER, "hard_worker", 0.6,
			"direct", "")
	var other: String = BeliefNet.create_belief("npc_t_c", "npc_t_x", THEFT, 0.5, "direct", "")
	check_near(_cert(neutral), 0.6, EPS, "non-negative beliefs are born intact")
	check_near(_cert(other), 0.5, EPS, "beliefs about NPCs are born intact")
	var rumor: String = BeliefNet.transfer_belief(caught.id, "npc_t_d", MANUAL_ORAL)
	check_near(_cert(rumor), caught.certainty * MANUAL_ORAL, EPS, "a rumour is not reduced twice")
	var record: String = BeliefNet.create_record("footage", PLAYER, MANUAL_FOOTAGE, CORRIDOR)
	check_near(_cert(record), 1.0, EPS, "records are born at 1.00 regardless of reputation")
	var accel: float = _bal("creencias.mod_decaimiento_por_reputacion_jugador")
	var base: float = MANUAL_DECAY * Database.get_difficulty_modifier(DIFFICULTY_KEY)
	var fast: float = base * (1.0 + accel * rep)
	check(fast > base, "high reputation accelerates the decay of suspicion")
	var caught_before: float = caught.certainty
	var rumor_before: float = _cert(rumor)
	BeliefNet.apply_daily_decay()
	check_near(caught.certainty, caught_before - fast, EPS, "rep 80: 0.74 − 0.08 × 1.8 = 0.596")
	check_near(_cert(rumor), rumor_before - fast, EPS, "rumours about the player decay faster too")
	check_near(_cert(neutral), 0.6 - MANUAL_DECAY, EPS, "non-negative beliefs: base decay")
	check_near(_cert(other), 0.5 - MANUAL_DECAY, EPS, "beliefs about NPCs: base decay")
	check(BeliefNet.get_belief(partial.id) == null, "rep 80: a partial sighting is gone in 1 day")
	check_near(_cert(record), 1.0, EPS, "records still never decay")


# ─── Refuerzo y fusión ────────────────────────────────────────

func _test_reinforcement_and_merge() -> void:
	_fresh()
	var id: String = BeliefNet.create_belief("npc_t_a", PLAYER, "seen_partially", MANUAL_PARTIAL,
			"direct", ROOM)
	BeliefNet.apply_daily_decay()
	check_eq(BeliefNet.get_days_since_reinforced(id), 1, "decay clock: 1 day")
	BeliefNet.reinforce_belief(id, 0.2)
	check_near(_cert(id), MANUAL_PARTIAL + 0.2, EPS, "reinforcement restores 0.35 and adds 0.2")
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
	BeliefNet.transfer_belief(src, "npc_t_c", 0.5)
	check_near(_cert(copy1), MANUAL_DIRECT * MANUAL_ORAL, EPS, "a weaker telling does not lower it")
	check_eq(BeliefNet.transfer_belief(src, "npc_t_e", 0.1), "", "0.09 < 0.10: does not take hold")
	var rec: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	BeliefNet.reinforce_belief(rec, -1.0)
	check_near(_cert(rec), 1.0, EPS, "records ignore reinforcement")


func _test_witness_removed() -> void:
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


# ─── Guardado y carga ─────────────────────────────────────────

func _test_save_load_round_trip() -> void:
	_fresh(30.0)
	EventBus.player_seen_partially.emit("npc_t_a", MANUAL_PARTIAL, ROOM)
	var partial: String = BeliefNet.get_beliefs_held_by("npc_t_a")[0].id
	var caught: String = BeliefNet.create_belief("npc_t_b", PLAYER, THEFT, MANUAL_DIRECT,
			"direct", "")
	BeliefNet.transfer_belief(caught, "npc_t_c", MANUAL_ORAL)
	EventBus.camera_recorded_player.emit("cam_s", CORRIDOR, 7)
	EventBus.npc_reported_player.emit("npc_t_d", "superior", 10.0, ROOM)
	EventBus.crime_committed.emit("fraud", "accounting", {})
	BeliefNet.apply_daily_decay()
	var ids: Array[String] = []
	for b: Belief in BeliefNet.get_beliefs_about(PLAYER) + BeliefNet.get_records_about(PLAYER):
		ids.append(b.id)
	var text: String = JSON.stringify(BeliefNet.save_state())
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	BeliefNet.reset_for_new_run()
	check(BeliefNet.get_beliefs_about(PLAYER).is_empty()
			and BeliefNet.calculate_player_suspicion() == 0.0, "reset_for_new_run empties the net")
	Validate.clear_errors()
	BeliefNet.load_state(JSON.parse_string(text))
	check(not Validate.has_errors(), "the saved state validates on load")
	check_eq(JSON.stringify(BeliefNet.save_state()), text, "save → JSON → load → save is identical")
	check_near(BeliefNet.calculate_player_suspicion(), suspicion, EPS, "same suspicion after load")
	check_eq(BeliefNet.get_pending_records().size(), 1, "pending records survive")
	var fresh_id: String = BeliefNet.create_record("card_log", PLAYER, MANUAL_CARD, "lobby")
	check(not ids.has(fresh_id), "ids keep counting after load (no collisions)")
	BeliefNet.reinforce_belief(partial, 0.0)
	check_near(_cert(partial), MANUAL_PARTIAL + MANUAL_BIRTH_MOD * 30.0, EPS,
			"the reinforcement reference (0.29) survives the round trip")
