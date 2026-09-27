# ideas_case.gd — Cuerpo de test_ideas: fórmula y frecuencia real de generación, calidad, señal, caducidad y las cinco vías con sus requisitos y rastros (§11.1).
# PROPIETARIO DE: nada.
# ESCUCHA: idea_generated, idea_acquired, idea_expired, idea_presented, player_seen_partially, crime_committed (conexiones del caso).
extends TestCase

const CLAUDIA := "npc_claudia_reeves"
const GEORGE := "npc_george_penn"
const SONIA := "npc_sonia_vail"
const NATE := "npc_nate_brackley"
const DEBBIE := "npc_debbie_foyle"
const RAY := "npc_ray_cudmore"
## Posibles confidentes (el primero que aún no conozca la idea).
const CONFIDANTS: Array[String] = ["npc_bernard_lasker", "npc_amelia_cole", "npc_tom_iverson",
	"npc_connie_marks"]
const ELSEWHERE := "cafeteria"
const TRIALS := 4000
## 3σ de una proporción p≈0,5 con 4000 ensayos ≈ 0,024.
const FREQ_TOLERANCE := 0.025
## Jornadas simuladas por el camino diario real; 3σ de p≈0,5 con 400 jornadas ≈ 0,075.
const DAILY_DAYS := 400
const DAILY_TOLERANCE := 0.075
## Toda la plantilla: miles de tiradas, la suma real no se aparta más de un 5 % de la esperada.
const TOTAL_TOLERANCE := 0.05
const QUALITY_SAMPLES := 300
const EPS := 0.000001

var _generated: Array = []
var _acquired: Array = []
var _expired: Array = []
var _presented: Array = []
var _seen: Array = []
var _crimes: Array = []


func run_case() -> void:
	check(new_run(), "Database loads the data files")
	GameClock.set_time(1, 10, 0)
	_connect_signals()
	_check_probability_formula()
	_check_generation_frequency()
	_check_quality_and_freshness()
	_check_named_quality_range()
	_check_signalling()
	_check_expiry()
	_check_acquisition_methods()
	_check_owner_presents_first()
	_check_save_load()
	_check_daily_generation_path()


func _connect_signals() -> void:
	EventBus.idea_generated.connect(func(id: String, owner: String, q: int, dept: String) -> void:
		_generated.append([id, owner, q, dept, GameClock.get_hour()]))
	EventBus.idea_acquired.connect(func(id: String, method: String) -> void:
		_acquired.append([id, method]))
	EventBus.idea_expired.connect(func(id: String) -> void: _expired.append(id))
	EventBus.idea_presented.connect(func(id: String, who: String, merit: int) -> void:
		_presented.append([id, who, merit]))
	EventBus.player_seen_partially.connect(func(npc: String, c: float, loc: String) -> void:
		_seen.append([npc, c, loc]))
	EventBus.crime_committed.connect(func(crime: String, room: String, d: Dictionary) -> void:
		_crimes.append([crime, room, d]))


# ─── Ayudas: situar personajes y jugador (el caso hace de «manos») ──────

func _player_to(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)


## Sala actual del personaje (si no tiene, se le sienta en su puesto).
func _room_of(npc_id: String) -> String:
	var room: String = NPCDirector.get_current_location(npc_id)
	if room.is_empty():
		room = NPCDirector.get_npc(npc_id).home_room
		NPCDirector.set_current_location(npc_id, room)
	return room


## Confidente que todavía no conoce la idea (al nacer pudo contársela ya a alguien).
func _new_confidant(idea_id: String) -> String:
	for npc_id: String in CONFIDANTS:
		if not IdeaPool.get_idea(idea_id).known_by.has(npc_id):
			return npc_id
	return ""


## Escucha legítima: el propietario se la cuenta a un confidente con el jugador en la sala.
func _overhear(idea_id: String) -> bool:
	var owner: String = IdeaPool.get_idea(idea_id).owner
	IdeaPool.share_idea(idea_id, _new_confidant(idea_id))
	_player_to(_room_of(owner))
	return IdeaPool.acquire(idea_id, IdeaPool.METHOD_OVERHEAR)


func _records_with_fact(fact: String) -> int:
	var count: int = 0
	for record: Belief in BeliefNet.get_records_about("player"):
		if record.fact == fact:
			count += 1
	return count


# ─── Generación ─────────────────────────────────────────────────────────

func _check_probability_formula() -> void:
	var modifier: float = IdeaPool.get_generation_modifier()
	for ambition: int in [0, 40, 50, 94, 100]:
		check_near(IdeaPool.get_generation_probability(ambition),
				(0.12 + 0.004 * ambition) * modifier, EPS,
				"p = (0.12 + 0.004 x ambition) x modifier for ambition %d" % ambition)
	check(not IdeaPool.is_ambitious_enough(30), "low ambition (30) never generates ideas")
	check(IdeaPool.is_ambitious_enough(40), "medium ambition (40) generates ideas")
	check(IdeaPool.is_ambitious_enough(94), "high ambition (94, Claudia) generates ideas")


func _check_generation_frequency() -> void:
	for ambition: int in [50, 94]:
		IdeaPool.reset_for_new_run()
		var hits: int = 0
		for i: int in TRIALS:
			if IdeaPool.roll_generation(ambition):
				hits += 1
		var expected: float = IdeaPool.get_generation_probability(ambition)
		check_near(float(hits) / TRIALS, expected, FREQ_TOLERANCE,
				"daily roll frequency over %d trials matches p for ambition %d"
				% [TRIALS, ambition])
	check_eq(_count_hits(500), _count_hits(500), "same run seed -> same generation sequence")


func _count_hits(days: int) -> int:
	IdeaPool.reset_for_new_run()
	var hits: int = 0
	for i: int in days:
		if IdeaPool.roll_generation(70):
			hits += 1
	return hits


## El camino real (process_new_day tira, process_hour suelta la idea a su hora) sobre muchas
## jornadas: la frecuencia de Claudia y la de toda la plantilla siguen la fórmula (sin topes).
func _check_daily_generation_path() -> void:
	new_run()
	var expected_total: float = 0.0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if IdeaPool.is_ambitious_enough(npc.get_trait("ambition")):
			expected_total += IdeaPool.get_generation_probability(npc.get_trait("ambition"))
	_generated.clear()
	var first_day: int = GameClock.get_day() + 1
	for offset: int in DAILY_DAYS:
		_simulate_day(first_day + offset)
	var claudia: int = 0
	var hours_ok: bool = true
	for entry: Array in _generated:
		claudia += 1 if entry[1] == CLAUDIA else 0
		hours_ok = hours_ok and int(entry[4]) >= 9 and int(entry[4]) <= 17
	var p: float = IdeaPool.get_generation_probability(94)
	check_near(float(claudia) / DAILY_DAYS, p, DAILY_TOLERANCE,
			"Claudia (ambition 94) generates %.3f ideas/day through the daily path (p = %.3f)"
			% [float(claudia) / DAILY_DAYS, p])
	check_near(float(_generated.size()) / (expected_total * DAILY_DAYS), 1.0, TOTAL_TOLERANCE,
			"whole staff: %d ideas vs %.0f expected by the formula (no live-idea cap)"
			% [_generated.size(), expected_total * DAILY_DAYS])
	check(hours_ok, "ideas are born during working hours (9-17)")


func _simulate_day(day: int) -> void:
	GameClock.set_time(day, 6, 0)
	IdeaPool.process_new_day(day)
	for hour: int in range(Database.get_balance_int("ideas.hora_generacion_min"),
			Database.get_balance_int("ideas.hora_generacion_max") + 1):
		GameClock.set_time(day, hour, 0)
		IdeaPool.process_hour(hour, day)


func _check_quality_and_freshness() -> void:
	IdeaPool.reset_for_new_run()
	var template: Dictionary = Database.get_idea_template("design")
	check_eq(int(template["quality_min"]), 50, "design template quality_min 50 (§32.3)")
	check_eq(int(template["quality_max"]), 100, "design template quality_max 100 (§32.3)")
	var in_range: bool = true
	var fresh_ok: bool = true
	var total: int = 0
	var fresh_seen: Dictionary = {}
	for i: int in QUALITY_SAMPLES:
		var idea: Idea = IdeaPool.get_idea(IdeaPool.generate_idea(GEORGE, "design"))
		in_range = in_range and idea.quality >= 50 and idea.quality <= 100
		fresh_ok = fresh_ok and idea.freshness >= 3 and idea.freshness <= 10
		fresh_seen[idea.freshness] = true
		total += idea.quality
	check(in_range, "20 + rand(0,80) projected onto the design range stays in [50, 100]")
	check(fresh_ok, "freshness = rand(3, 10) days")
	check(fresh_seen.has(3) and fresh_seen.has(10), "freshness reaches both 3 and 10")
	check_near(float(total) / QUALITY_SAMPLES, 75.0, 5.0, "design quality averages ~75")
	check_eq(IdeaPool.resolve_template_department("junior_shoe_designer", "specialists"),
			"design", "shoe designer -> design ideas")
	check_eq(IdeaPool.resolve_template_department("email_worker_3b", "base"), "general",
			"wing 3B clerk -> general ideas")
	check_eq(IdeaPool.resolve_template_department("", "sales_marketing"), "marketing",
			"sales & marketing department -> marketing ideas")


func _check_named_quality_range() -> void:
	IdeaPool.reset_for_new_run()
	var ok: bool = true
	for i: int in 60:
		var id: String = IdeaPool.generate_for_npc(CLAUDIA)
		var idea: Idea = IdeaPool.get_idea(id)
		ok = ok and idea != null and idea.quality >= 60 and idea.quality <= 90
	check(ok, "Claudia Reeves' ideas have quality 60-90 (npcs_named special range)")
	var last: Array = _generated.back()
	check_eq(last[1], CLAUDIA, "idea_generated carries the owner")
	check_eq(last[3], "general", "idea_generated carries the template department")
	check_eq(IdeaPool.generate_for_npc("npc_nobody_at_all"), "", "unknown NPC generates nothing")


func _check_signalling() -> void:
	IdeaPool.reset_for_new_run()
	var id: String = IdeaPool.generate_for_npc(CLAUDIA)
	var signals: Array[Dictionary] = IdeaPool.get_signalling_npcs()
	check_eq(signals.size(), 1, "a generated idea shows its owner's indicator")
	var entry: Dictionary = signals[0] if not signals.is_empty() else {}
	check_eq(entry.get("npc_id", ""), CLAUDIA, "indicator over the owner")
	check_eq(entry.get("idea_id", ""), id, "indicator points at the new idea")
	check([IdeaPool.BEHAVIOUR_AGITATION, IdeaPool.BEHAVIOUR_TO_COMPUTER, IdeaPool.BEHAVIOUR_TELL]
			.has(entry.get("behaviour", "")), "an observable behaviour change is chosen")
	IdeaPool.process_hour(int(entry.get("until_hour", 0)), GameClock.get_day())
	check(IdeaPool.get_signalling_npcs().is_empty(), "the indicator fades after ideas.horas_senal")
	check(not IdeaPool.is_being_told(id), "no telling once the signal is over")
	check(IdeaPool.share_idea(id, NATE), "the owner tells a colleague")
	check(IdeaPool.is_being_told(id), "telling a colleague opens the overhearing window")
	check_eq(IdeaPool.get_signalling_npcs()[0].get("behaviour", ""), IdeaPool.BEHAVIOUR_TELL,
			"the owner is seen walking over to tell someone")
	check(IdeaPool.get_idea(id).known_by.has(NATE), "the confidant now knows whose idea it is")


func _check_expiry() -> void:
	IdeaPool.reset_for_new_run()
	var id: String = IdeaPool.generate_idea(GEORGE, "general")
	var freshness: int = IdeaPool.get_idea(id).freshness
	var day: int = GameClock.get_day()
	_expired.clear()
	for i: int in freshness - 1:
		day += 1
		IdeaPool.process_new_day(day)
	check(IdeaPool.get_idea(id) != null, "idea alive until its last day")
	check_eq(IdeaPool.get_idea(id).freshness, 1, "freshness drops by one per day")
	check(not _expired.has(id), "no idea_expired before freshness runs out")
	IdeaPool.process_new_day(day + 1)
	check(_expired.has(id), "idea_expired when freshness reaches 0")
	check(IdeaPool.get_idea(id) == null, "expired idea leaves the pool")
	check_eq(IdeaPool.expire_stale_ideas(), 0, "nothing else is stale")


# ─── Las cinco vías (§11.1): requisito y rastro ─────────────────────────

func _check_acquisition_methods() -> void:
	new_run()
	GameClock.set_time(1, 10, 0)
	_acquired.clear()
	_check_overhear()
	_check_steal_file()
	_check_inherit()
	_check_purchase()
	_check_gifted()
	var bogus: String = IdeaPool.generate_idea(GEORGE, "general")
	check(not IdeaPool.acquire(bogus, "telepathy"), "unknown acquisition method is rejected")
	check_eq(_acquired.size(), 5, "idea_acquired once per successful method")
	check_eq(IdeaPool.get_player_ideas().size(), 5, "the player holds the five ideas")
	check(IdeaPool.get_available_ideas().has(IdeaPool.get_idea(bogus)),
			"unacquired ideas stay available")


func _check_overhear() -> void:
	var id: String = IdeaPool.generate_idea(GEORGE, "general")
	var owner_room: String = _room_of(GEORGE)
	IdeaPool.process_hour(GameClock.get_hour() + Database.get_balance_int("ideas.horas_senal"),
			GameClock.get_day())
	_player_to(owner_room)
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_OVERHEAR),
			IdeaPool.BLOCK_NOT_TELLING, "overhear needs the owner to be telling someone")
	check(IdeaPool.share_idea(id, _new_confidant(id)), "George tells a colleague")
	_player_to(ELSEWHERE)
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_OVERHEAR),
			IdeaPool.BLOCK_TOO_FAR, "overhear needs proximity (same room)")
	_player_to(owner_room)
	_seen.clear()
	_crimes.clear()
	check(IdeaPool.acquire(id, IdeaPool.METHOD_OVERHEAR), "overhear acquires the idea")
	check_eq(_acquired.back(), [id, "overhear"], "idea_acquired(id, overhear)")
	check_eq(_seen.size(), 1, "overhear: the owner knows you were present")
	if not _seen.is_empty():
		check_eq(_seen[0][0], GEORGE, "presence trace held by the owner")
		check_near(float(_seen[0][1]), Database.get_balance_float("creencias.certeza_parcial"),
				EPS, "presence trace has partial-perception certainty")
	check(_crimes.is_empty(), "overhear leaves no digital record")
	check(IdeaPool.get_idea(id).known_by.has("player"), "the player now knows the idea")
	check_eq(IdeaPool.get_acquisition_trace(id), "owner_knows_presence", "overhear trace")
	check(not IdeaPool.acquire(id, IdeaPool.METHOD_GIFTED), "an idea cannot be acquired twice")


func _check_steal_file() -> void:
	var id: String = IdeaPool.generate_idea(SONIA, "general")
	var desk: String = NPCDirector.get_npc(SONIA).home_room
	NPCDirector.set_current_location(SONIA, desk)
	_player_to(desk)
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_STEAL_FILE),
			IdeaPool.BLOCK_OWNER_AT_DESK, "steal_file: not while the owner sits at the computer")
	NPCDirector.set_current_location(SONIA, ELSEWHERE)
	_player_to(ELSEWHERE)
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_STEAL_FILE),
			IdeaPool.BLOCK_NOT_AT_DESK, "steal_file: you must be at the owner's computer")
	_player_to(desk)
	_seen.clear()
	_crimes.clear()
	var records_before: int = _records_with_fact("chat_log:file_copied")
	check(IdeaPool.acquire(id, IdeaPool.METHOD_STEAL_FILE), "steal_file acquires the idea")
	check_eq(_crimes.size(), 1, "steal_file emits one crime")
	if not _crimes.is_empty():
		check_eq(_crimes[0][0], "file_copied", "steal_file is a file_copied crime")
		check_eq(_crimes[0][1], desk, "the copy happens at the owner's desk")
		check_eq((_crimes[0][2] as Dictionary).get("idea_id", ""), id, "crime names the idea")
	check_eq(_records_with_fact("chat_log:file_copied"), records_before + 1,
			"BeliefNet keeps a digital record about the player (readable by IT)")
	check(_seen.is_empty(), "steal_file: the owner does not see you")
	check_eq(IdeaPool.get_acquisition_trace(id), "digital_record", "steal_file trace")


func _check_inherit() -> void:
	var id: String = IdeaPool.generate_idea(NATE, "general")
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_INHERIT),
			IdeaPool.BLOCK_OWNER_PRESENT, "no inheritance while owner is here")
	EventBus.npc_removed.emit(NATE, "expelled")
	check(IdeaPool.is_owner_gone(NATE), "npc_removed marks the owner as gone")
	check(IdeaPool.get_unclaimed_ideas().has(IdeaPool.get_idea(id)), "orphan idea is unclaimed")
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_OVERHEAR),
			IdeaPool.BLOCK_OWNER_GONE, "nobody left to overhear")
	_seen.clear()
	_crimes.clear()
	check(IdeaPool.acquire(id, IdeaPool.METHOD_INHERIT), "inherit acquires the orphan idea")
	check(_seen.is_empty() and _crimes.is_empty(), "inherit leaves no trace for the idea")
	check_eq(IdeaPool.get_acquisition_trace(id), "none_for_idea", "inherit trace")
	check(IdeaPool.get_unclaimed_ideas().is_empty(), "inherited idea is no longer unclaimed")


func _check_purchase() -> void:
	var id: String = IdeaPool.generate_idea(DEBBIE, "general")
	_seen.clear()
	_crimes.clear()
	check(IdeaPool.acquire(id, IdeaPool.METHOD_PURCHASE), "purchase acquires the idea")
	check(_seen.is_empty() and _crimes.is_empty(), "purchase leaves no documentary trace")
	check(IdeaPool.get_idea(id).known_by.has(DEBBIE), "purchase: the owner keeps full knowledge")
	check_eq(IdeaPool.get_acquisition_trace(id), "owner_knows_all", "purchase trace")


func _check_gifted() -> void:
	var id: String = IdeaPool.generate_idea(RAY, "general")
	var needed: int = Database.get_balance_int("ideas.deuda_minima_cesion")
	check_eq(IdeaPool.get_acquisition_block(id, IdeaPool.METHOD_GIFTED), IdeaPool.BLOCK_LOW_DEBT,
			"gifted needs a high debt towards the player")
	check_eq(IdeaPool.acquisition_block_key(IdeaPool.BLOCK_LOW_DEBT), "IDEA_BLOCK_LOW_DEBT",
			"block reasons have a text key")
	NPCDirector.add_debt(RAY, needed - 1 - NPCDirector.get_debt(RAY))
	check(not IdeaPool.acquire(id, IdeaPool.METHOD_GIFTED), "one point short: no gift")
	NPCDirector.add_debt(RAY, 1)
	_seen.clear()
	_crimes.clear()
	check(IdeaPool.acquire(id, IdeaPool.METHOD_GIFTED), "a debtor gives the idea away")
	check(_seen.is_empty() and _crimes.is_empty(), "gifted leaves no trace at all")
	check_eq(IdeaPool.get_acquisition_trace(id), "none", "gifted trace")


func _check_owner_presents_first() -> void:
	IdeaPool.reset_for_new_run()
	var id: String = IdeaPool.generate_idea(GEORGE, "design")
	check(_overhear(id), "the player overhears George's idea")
	_presented.clear()
	var merit: int = IdeaPool.present_for_owner(id)
	check(merit > 0, "the owner earns merit presenting their own idea")
	check_eq(_presented.back(), [id, GEORGE, merit], "idea_presented by the owner")
	IdeaPool.start_meeting()
	check(not IdeaPool.stage_presentation(id), "a spent idea cannot even be staged")
	var result: Dictionary = IdeaPool.present(id)
	check_eq(result["status"], IdeaPool.STATUS_ALREADY_PRESENTED, "owner presented first")
	check_eq(result["merit"], 0, "an idea presented by its owner is worth nothing to the player")
	var fresh: String = IdeaPool.generate_idea(SONIA, "design")
	check(_overhear(fresh), "the player overhears Sonia's idea")
	var raw: Dictionary = IdeaPool.present(fresh)
	check_eq(raw["status"], IdeaPool.STATUS_NOT_STAGED,
			"§19 present() without the Aurora scene does not resolve anything")
	check(not IdeaPool.get_idea(fresh).presented and IdeaPool.get_player_ideas().has(
			IdeaPool.get_idea(fresh)), "... and the idea is not wasted")
	check_eq(IdeaPool.contest(fresh, SONIA), "", "no clash outside a staged presentation")
	IdeaPool.close_meeting()


func _check_save_load() -> void:
	IdeaPool.reset_for_new_run()
	var a: String = IdeaPool.generate_idea(GEORGE, "marketing")
	var b: String = IdeaPool.generate_idea(SONIA, "legal")
	_overhear(b)
	var saved: Variant = JSON.parse_string(JSON.stringify(IdeaPool.save_state()))
	var before: Array[int] = _quality_sequence()
	var dump_a: Dictionary = IdeaPool.get_idea(a).to_dict()
	var dump_b: Dictionary = IdeaPool.get_idea(b).to_dict()
	var signals: Array[Dictionary] = IdeaPool.get_signalling_npcs()
	IdeaPool.reset_for_new_run()
	IdeaPool.load_state(saved as Dictionary)
	check_eq(IdeaPool.get_idea(a).to_dict(), dump_a, "save/load restores idea A exactly")
	check_eq(IdeaPool.get_idea(b).to_dict(), dump_b, "save/load restores idea B exactly")
	check_eq(IdeaPool.get_signalling_npcs().size(), signals.size(), "save/load restores signals")
	check_eq(_quality_sequence(), before, "save/load restores the RNG stream")
	check(IdeaPool.generate_idea(GEORGE, "general") == "idea_3", "id counter restored")


func _quality_sequence() -> Array[int]:
	var out: Array[int] = []
	for i: int in 5:
		out.append(IdeaPool.roll_quality(0, 100))
	return out
