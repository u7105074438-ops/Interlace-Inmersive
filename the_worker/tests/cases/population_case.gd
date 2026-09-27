# population_case.gd — Cuerpo de test_population: generación de la plantilla, rutinas, cuerpos y guardado.
# PROPIETARIO DE: nada.
# ESCUCHA: body_created, body_discovered, npc_removed (conexiones temporales del escenario).
extends TestCase

## Tabla §24.2 del manual: id → [ambición, lealtad, codicia, valentía, perspicacia, sociabilidad].
const NAMED_TRAITS: Dictionary = {
	"npc_debbie_foyle": [42, 40, 48, 38, 72, 96], "npc_george_penn": [55, 88, 18, 48, 84, 68],
	"npc_nate_brackley": [22, 48, 42, 28, 12, 40], "npc_claudia_reeves": [94, 28, 58, 62, 74, 58],
	"npc_ray_cudmore": [12, 62, 28, 78, 92, 48], "npc_sonia_vail": [58, 72, 32, 28, 32, 30],
	"npc_bernard_lasker": [52, 72, 22, 92, 58, 38], "npc_amelia_cole": [32, 94, 8, 78, 76, 42],
	"npc_tom_iverson": [50, 18, 92, 32, 48, 52], "npc_ludmila_petrova": [48, 74, 20, 94, 82, 36],
	"npc_connie_marks": [14, 58, 34, 72, 90, 54], "npc_frank_rudd": [8, 14, 58, 22, 38, 28],
	"npc_ernie_vaughn": [88, 32, 64, 58, 66, 56], "npc_diana_sedgwick": [92, 26, 62, 56, 68, 72],
	"npc_iggy_robbins": [58, 24, 78, 40, 62, 60], "npc_rose_miller": [34, 92, 4, 82, 84, 44],
	"npc_alvin_pyne": [44, 52, 62, 8, 64, 48], "npc_bree_nash": [62, 34, 84, 44, 70, 66],
	"npc_maurice_sandbell": [90, 22, 76, 54, 72, 50],
	"npc_lorna_vickers": [56, 42, 58, 46, 68, 94], "npc_preston_vaile": [88, 42, 48, 88, 74, 52],
	"npc_harlan_voss": [78, 0, 68, 82, 95, 58], "npc_pearl_osgood": [28, 96, 6, 74, 78, 46],
}
const TRAIT_ORDER: Array[String] = [
	"ambition", "loyalty", "greed", "courage", "perception", "sociability",
]
## Semillas para las distribuciones agregadas (≈ 20 × 127 sorteos).
const DISTRIBUTION_SEEDS := 20
const SIGMAS := 3.0
const SAMPLE_SEED := 777

var _events: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	_check_totals()
	_check_named()
	_check_generated_rules()
	_check_reproducibility()
	_check_distributions()
	new_run()
	_check_routines()
	_check_removal_and_bodies()
	_check_hire()
	_check_save_load()


func _check_totals() -> void:
	var rules: Dictionary = Database.get_raw("npcs_generation")
	var all: Array[NPCRuntime] = NPCDirector.get_all_npcs()
	check_eq(all.size(), int(rules["total_population_target"]),
			"population = 23 named + 127 generated = 150 (§24.3)")
	var named: int = 0
	var names: Dictionary = {}
	for npc: NPCRuntime in all:
		named += 1 if npc.is_named else 0
		names[npc.name] = true
	check_eq(named, 23, "exactly 23 named characters (§24.2)")
	check_eq(names.size(), all.size(), "no first+last name combination is repeated")
	for dep: Dictionary in rules["departments"]:
		var count: int = 0
		for npc: NPCRuntime in all:
			count += 1 if npc.department == str(dep["id"]) else 0
		var own: int = int(dep.get("own_population", dep["population"]))
		check_eq(count, own, "department %s has its population (§24.3)" % dep["id"])


func _check_named() -> void:
	for id: String in NAMED_TRAITS:
		var npc: NPCRuntime = NPCDirector.get_npc(id)
		if not check(npc != null and npc.is_named, "%s exists and is named" % id):
			continue
		var expected: Array = NAMED_TRAITS[id]
		var actual: Array = []
		for trait_name: String in TRAIT_ORDER:
			actual.append(NPCDirector.get_trait(id, trait_name))
		check_eq(actual, expected, "%s has the exact §24.2 traits" % id)
	check_eq(NPCDirector.get_npc_by_occupation("ceo").id, "npc_harlan_voss", "CEO is Harlan Voss")
	check_eq(NPCDirector.get_npc_by_occupation("wing_3b_chief").id, "npc_bernard_lasker",
			"wing 3B chief is Bernard Lasker")
	var rose: NPCRuntime = NPCDirector.get_npc("npc_rose_miller")
	check(rose.occupation_id.is_empty() and NPCDirector.get_role(rose.id) == "auditor"
			and rose.tier == 3, "Rose Miller: auditor role (no playable seat), tier 3")
	check_eq(NPCDirector.get_profile(rose.id).get("future_occupation"), "chief_auditor",
			"Rose's future occupation is chief_auditor (§7.13)")
	check_eq(NPCDirector.get_npc("npc_pearl_osgood").tier, 5, "Pearl Osgood: CEO secretary, tier 5")
	check(NPCDirector.is_slacker("npc_nate_brackley") and NPCDirector.is_slacker("npc_frank_rudd")
			and not NPCDirector.is_slacker("npc_george_penn"), "named slackers come from data")
	check_eq(NPCDirector.get_shift("npc_ludmila_petrova"), "night", "Ludmila is the night guard")
	var ratio: float = Database.get_balance_float("percepcion.mod_sospecha_por_punto") \
			/ Database.get_balance_float("percepcion.mod_perspicacia_por_punto")
	var expected_perception: int = clampi(roundi(84 + PlayerState.get_suspicion() * ratio
			+ Security.get_alert_level() * Database.get_balance_int(
			"percepcion.perspicacia_por_nivel_alerta")), 0, 150)
	check_eq(NPCDirector.get_effective_perception("npc_george_penn"), expected_perception,
			"effective perception = perception + suspicion × 0.005/0.01 (+ alert)")
	check_eq(NPCDirector.get_daily_wage("npc_amelia_cole"),
			Database.get_occupation("hr_assistant").daily_wage, "wage comes from the occupation")


func _check_generated_rules() -> void:
	var variation: int = Database.get_archetype_variation_range()
	var bad_traits: int = 0
	var bad_template: int = 0
	var seed_range: Array = Database.get_raw("npcs_generation")["portrait_seed_range"]
	var bad_seed: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.is_named:
			continue
		var base: ArchetypeData = Database.get_archetype(npc.archetype)
		for trait_name: String in TRAIT_ORDER:
			var v: int = npc.get_trait(trait_name)
			if v < 0 or v > 100 or absi(v - base.get_trait(trait_name)) > variation:
				bad_traits += 1
		if npc.routine_template != _expected_template(npc):
			bad_template += 1
		if npc.portrait_seed < int(seed_range[0]) or npc.portrait_seed > int(seed_range[1]):
			bad_seed += 1
	check_eq(bad_traits, 0, "generated traits = archetype base ± %d, clamped 0-100" % variation)
	check_eq(bad_template, 0, "routine template by slot, occupation (guards/cleaners) or tier")
	check_eq(bad_seed, 0, "portrait seeds inside portrait_seed_range")
	var police: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) == "police_officer":
			police += 1
			check_eq(npc.archetype, "hardliner", "police officer %s is a hardliner" % npc.id)
	check_eq(police, 2, "two police officers outside")
	_check_gatherings()


func _expected_template(npc: NPCRuntime) -> String:
	var rules: Dictionary = Database.get_raw("npcs_generation")
	for dep: Dictionary in rules["departments"]:
		for slot: Dictionary in dep["slots"]:
			if str(slot.get("room", "")) == npc.home_room and slot.has("routine_template") \
					and str(slot.get("occupation", "")) == npc.occupation_id \
					and str(slot.get("shift", "")) == NPCDirector.get_shift(npc.id):
				return str(slot["routine_template"])
	return str(rules["tier_to_routine_template"].get(str(npc.tier), ""))


func _check_gatherings() -> void:
	var couple: int = 0
	var chat_ok: bool = true
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		couple += 1 if npc.gatherings.has("accounting_couple") else 0
		if not npc.is_named and npc.home_room == "wing_3b" and not npc.gatherings.has("chat_3b"):
			chat_ok = false
	check_eq(couple, 2, "exactly two accounting employees share the secret couple gathering")
	check(chat_ok, "every generated wing 3B employee is in the 3B chat")


func _check_reproducibility() -> void:
	var first: Dictionary = _snapshot()
	new_run(DEFAULT_SEED)
	check_eq(_snapshot(), first, "same run seed → identical population")
	new_run(SAMPLE_SEED)
	check(_snapshot() != first, "different run seed → different generated staff")


func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		out[npc.id] = [npc.name, npc.archetype, npc.traits, npc.is_slacker, npc.portrait_seed]
	return out


## Distribución de arquetipos por departamento y proporción de slackers, agregadas sobre varias
## semillas y comparadas con las probabilidades declaradas (tolerancia de 3 desviaciones).
func _check_distributions() -> void:
	var counts: Dictionary = {}
	var totals: Dictionary = {}
	var slackers: int = 0
	var eligible: int = 0
	var bad_slackers: int = 0
	for i: int in DISTRIBUTION_SEEDS:
		new_run(SAMPLE_SEED + i)
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			if npc.is_named:
				continue
			var key: String = npc.department
			totals[key] = int(totals.get(key, 0)) + 1
			var per_dep: Dictionary = counts.get(key, {})
			per_dep[npc.archetype] = int(per_dep.get(npc.archetype, 0)) + 1
			counts[key] = per_dep
			var external: bool = bool(NPCDirector.get_profile(npc.id).get("external", false))
			if npc.is_slacker and (npc.tier > 3 or external):
				bad_slackers += 1
			if npc.tier <= 3 and not external:
				eligible += 1
				slackers += 1 if npc.is_slacker else 0
	_compare_bags(counts, totals)
	check_eq(bad_slackers, 0, "slackers are only tier 1-3 non-external staff (§24.3 step 6)")
	var p: float = float(Database.get_raw("npcs_generation")["slacker_probability_tier_1_3"])
	check_near(float(slackers) / eligible, p, SIGMAS * sqrt(p * (1.0 - p) / eligible),
			"≈15%% of tier 1-3 staff are slackers (%d/%d)" % [slackers, eligible])


func _compare_bags(counts: Dictionary, totals: Dictionary) -> void:
	for dep: Dictionary in Database.get_raw("npcs_generation")["departments"]:
		var id: String = str(dep["id"])
		var n: int = int(totals.get(id, 0))
		var bag: Dictionary = NPCPopulationGenerator.free_bag(dep["archetype_bag"], dep["slots"])
		var forced: int = _forced_count(dep)
		var free_n: int = n - forced * DISTRIBUTION_SEEDS
		for archetype: String in bag:
			var p: float = float(bag[archetype])
			var observed: float = float(counts.get(id, {}).get(archetype, 0)) / free_n
			check_near(observed, p, SIGMAS * sqrt(p * (1.0 - p) / free_n) + 0.01,
					"%s: %s frequency matches its bag" % [id, archetype])


func _forced_count(dep: Dictionary) -> int:
	var forced: int = 0
	for slot: Dictionary in dep["slots"]:
		if not str(slot.get("archetype", "")).is_empty():
			forced += int(slot.get("count", 0))
	return forced


func _check_routines() -> void:
	var debbie: String = "npc_debbie_foyle"
	check_eq(NPCDirector.get_scheduled_location(debbie, "work_morning"), "wing_3b",
			"Debbie works at her 3B desk in the morning")
	check_eq(NPCDirector.get_scheduled_location(debbie, "lunch"), "cafeteria",
			"Debbie lunches in the cafeteria (§24.5 tier 1-2)")
	check_eq(NPCDirector.get_scheduled_location(debbie, "night"), "", "Debbie is away at night")
	check_eq(NPCDirector.get_location_at(debbie, 10, 35), "p3_pantry",
			"Debbie's 10:30 coffee override takes her to the pantry")
	check_eq(NPCDirector.get_scheduled_location("npc_ludmila_petrova", "night"), "monitor_room",
			"night guard watches the monitor room at night")
	check_eq(NPCDirector.get_scheduled_location("npc_ludmila_petrova", "work_morning"), "",
			"night guard is absent in the morning")
	check_eq(NPCDirector.get_scheduled_location("npc_diana_sedgwick", "work_afternoon"),
			"meeting_12a", "Diana's long meeting empties her office (§24.5 tier 5-6)")
	check_eq(NPCDirector.get_scheduled_location("npc_pearl_osgood", "work_morning"),
			"ceo_secretariat", "Pearl guards the CEO secretariat")
	var zone: String = NPCDirector.get_scheduled_location("npc_connie_marks", "night")
	var zone_floor: int = Database.get_room(zone).floor if Database.get_room(zone) != null else -1
	check(zone_floor >= 1 and zone_floor <= 12, "Connie cleans her zone (floors 1-12) at night")
	NPCDirector.override_routine(debbie, "lunch", "p3_pantry")
	check_eq(NPCDirector.get_scheduled_location(debbie, "lunch"), "p3_pantry",
			"override_routine replaces the band location")
	NPCDirector.override_routine(debbie, "lunch", "")
	_check_band_movement()
	_check_slacking()


## Al empezar la comida los nominados del 3B se desplazan a la cafetería (verificación PASO 9).
func _check_band_movement() -> void:
	GameClock.set_time(GameClock.get_day(), 13, 0)
	EventBus.time_band_changed.emit("work_morning", "lunch")
	var in_cafeteria: int = 0
	for id: String in ["npc_debbie_foyle", "npc_nate_brackley", "npc_claudia_reeves",
			"npc_ray_cudmore", "npc_sonia_vail", "npc_george_penn"]:
		in_cafeteria += 1 if NPCDirector.get_current_location(id) == "cafeteria" else 0
	check_eq(in_cafeteria, 6, "at 13:00 the 3B staff move to the cafeteria")
	check(NPCDirector.get_npcs_in_room("cafeteria").size() >= 6, "get_npcs_in_room sees them")
	check_eq(NPCDirector.get_current_location("npc_bernard_lasker"), "wing_3b",
			"Bernard eats at his desk reviewing figures")


func _check_slacking() -> void:
	var slacks: int = 0
	var hideouts: Array = Database.get_raw("npcs_generation")["routine_common_modifiers"][
			"slacker"]["hideouts"]
	var ok: bool = true
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		for iv: Dictionary in NPCDirector.get_day_plan(npc.id):
			if str(iv["activity"]) == "slacking":
				slacks += 1
				ok = ok and npc.is_slacker and hideouts.has(iv["room"])
	check(slacks > 0 and ok, "only slackers leave their post, towards §24.5 hideouts")


func _check_removal_and_bodies() -> void:
	_events.clear()
	EventBus.body_created.connect(_on_event.bind("body_created"))
	EventBus.body_discovered.connect(_on_event.bind("body_discovered"))
	EventBus.npc_removed.connect(_on_event.bind("npc_removed"))
	var total: int = NPCDirector.get_all_npcs().size()
	NPCDirector.remove_npc("npc_sonia_vail", "expelled")
	check(NPCDirector.is_alive("npc_sonia_vail") and not NPCDirector.is_active("npc_sonia_vail"),
			"an expelled NPC is alive but no longer on staff")
	check_eq(NPCDirector.get_all_npcs().size(), total - 1, "expelled NPC leaves get_all_npcs()")
	check(NPCDirector.get_body_info("npc_sonia_vail").is_empty(), "expulsion leaves no body")
	GameClock.set_time(GameClock.get_day(), 10, 0)
	EventBus.hour_passed.emit(10, GameClock.get_day())
	NPCDirector.remove_npc("npc_nate_brackley", "eliminated")
	var body: Dictionary = NPCDirector.get_body_info("npc_nate_brackley")
	check(not NPCDirector.is_alive("npc_nate_brackley") and not body.is_empty(),
			"elimination creates a body record")
	check_eq(_events.slice(-2).map(func(e: Array) -> String: return e[0]),
			["body_created", "npc_removed"], "body_created precedes npc_removed")
	NPCDirector.move_body("npc_nate_brackley", "wing_3b", "")
	EventBus.hour_passed.emit(11, GameClock.get_day())
	check(_has_event("body_discovered"), "an unhidden body in an occupied room is discovered")
	NPCDirector.remove_npc("npc_frank_rudd", "eliminated")
	NPCDirector.move_body("npc_frank_rudd", "wing_3b", "filing_cabinet")
	EventBus.hour_passed.emit(12, GameClock.get_day())
	check(not bool(NPCDirector.get_body_info("npc_frank_rudd")["discovered"]),
			"a hidden body is not discovered by routine passers-by")


## §6.3 paso 2: si nadie cualifica, RR. HH. contrata un Rookie; NPCDirector lo crea al oír
## seat_filled de un id que Company declara contratado.
func _check_hire() -> void:
	if not Company.has_method("is_hire"):
		return
	var intern: NPCRuntime = NPCDirector.get_npc_by_occupation("eternal_intern")
	var names: Dictionary = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		names[npc.name] = true
	Company.vacate_seat("eternal_intern", "fired")
	Company.auto_fill_vacancies()
	var hired: NPCRuntime = NPCDirector.get_npc_by_occupation("eternal_intern")
	if not check(hired != null and hired.id != intern.id, "the vacant intern seat is filled"):
		return
	check(bool(Company.call("is_hire", hired.id)) and hired.archetype == "rookie"
			and hired.gatherings.is_empty(), "HR hires a Rookie with no social ties (§6.3, §8.1)")
	check(not names.has(hired.name), "the hire gets an unused first+last name")
	check_eq(hired.home_room, Database.get_occupation("eternal_intern").office_room,
			"the hire works at the seat's office")


func _check_save_load() -> void:
	NPCDirector.add_grievance("npc_george_penn", "seat_lost", 7)
	NPCDirector.force_full_lod("npc_harlan_voss", "target")
	var saved: Dictionary = NPCDirector.save_state()
	var json: Variant = JSON.parse_string(JSON.stringify(saved))
	NPCDirector.reset_for_new_run()
	check(NPCDirector.get_all_npcs().is_empty(), "reset empties the population")
	NPCDirector.load_state(json)
	check_eq(JSON.parse_string(JSON.stringify(NPCDirector.save_state())), json,
			"save → JSON → load → save reproduces the exact state")
	check_eq(NPCDirector.get_lod("npc_harlan_voss"), 0, "forced LOD survives the round trip")
	check_eq(NPCDirector.get_grievance_total("npc_george_penn"), 7, "ledger survives the round trip")


## Receptor genérico: bind() añade la etiqueta como último argumento.
func _on_event(...args: Array) -> void:
	_events.append([args.back()] + args.slice(0, args.size() - 1))


func _has_event(tag: String) -> bool:
	for e: Array in _events:
		if e[0] == tag:
			return true
	return false
