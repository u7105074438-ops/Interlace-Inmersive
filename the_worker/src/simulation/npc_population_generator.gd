# npc_population_generator.gd — Crea la plantilla inicial: 23 nominados + generados (§24.3, PASO 44.2).
# PROPIETARIO DE: nada (NPCDirector recibe los NPCRuntime y los perfiles y los custodia).
# ESCUCHA: nada.
class_name NPCPopulationGenerator
extends RefCounted

## Procedimiento de siete pasos de §24.3 sobre data/npcs_generation.json (esquema §30):
##  1. nombre del banco sin repetir la combinación nombre-apellido (tampoco con los nominados);
##  2. arquetipo sorteado con la bolsa del departamento (las plazas con arquetipo forzado consumen
##     su cuota: se retira de la bolsa y el resto se renormaliza);
##  3. rasgos = base del arquetipo ± variation_range (archetypes.json), acotados a 0-100;
##  4. plantilla de rutina por plaza, ocupación (vigilantes por turno, limpieza) o escalón;
##  5. los vínculos los construye SocialGraph; aquí solo se asignan los corrillos (gatherings);
##  6. slacker con slacker_probability_tier_1_3 en escalones 1-3 (sin puestos externos);
##  7. semilla de retrato en portrait_seed_range.
## Perfil (NPCDirector.get_profile) por personaje: role, seat_index, shift, daily_wage, clearance,
## future_occupation, future_occupation_day, zone_floors, external, secrets, blackmail_secrets,
## knows_safe_combination, special.
## Todo el azar sale del RandomNumberGenerator recibido (sembrado con la semilla de partida).

const GENERATED_ID_FORMAT := "npc_gen_%03d"
const NAME_FORMAT := "%s %s"
const KEY_DEPARTMENTS := "departments"
const KEY_SLOTS := "slots"
const KEY_NOTE := "_nota"
## Escalón máximo con indicador slacker (§24.3 paso 6: escalones 1 a 3).
const SLACKER_MAX_TIER := 3

var npcs: Array[NPCRuntime] = []
## npc_id → perfil (ver cabecera).
var profiles: Dictionary = {}

var _rng: RandomNumberGenerator
var _rules: Dictionary = {}
var _used_names: Dictionary = {}
var _seat_next: Dictionary = {}
var _generated_count: int = 0


func _init(rng: RandomNumberGenerator, generation_rules: Dictionary) -> void:
	_rng = rng
	_rules = generation_rules


## Nominados primero (orden del archivo) y después los generados, departamento a departamento.
func generate() -> void:
	npcs.clear()
	profiles.clear()
	_used_names.clear()
	_seat_next.clear()
	_generated_count = 0
	for named: NPCData in Database.get_all_named_npcs():
		_add_named(named)
	for dep: Variant in _rules.get(KEY_DEPARTMENTS, []):
		if dep is Dictionary:
			_generate_department(dep)
	_apply_fixed_link_gatherings()


# ─── Nominados ────────────────────────────────────────────────

func _add_named(data: NPCData) -> void:
	var npc: NPCRuntime = NPCRuntime.from_named(data)
	var extra: Dictionary = data.extra
	var job: Dictionary = job_info(data.occupation, str(extra.get("role", "")))
	npc.tier = int(extra.get("tier", job.get("tier", npc.tier)))
	npc.department = str(extra.get("department", job.get("department", "")))
	npc.home_address = str(extra.get("home_address", _home_address_for(npc.tier)))
	var special: Dictionary = extra.get("special", {}) if extra.get("special") is Dictionary else {}
	var profile: Dictionary = _base_profile(job, extra)
	if extra.has("seat_index"):
		profile["seat_index"] = int(extra["seat_index"])
	else:
		profile["seat_index"] = _next_seat(data.occupation)
	profile["zone_floors"] = _int_array(special.get("cleaning_zone_floors", []))
	profile["special"] = special.duplicate(true)
	for key: String in ["secrets", "blackmail_secrets"]:
		profile[key] = _string_array(extra.get(key, []))
	profile["knows_safe_combination"] = bool(extra.get("knows_safe_combination", false))
	_used_names[npc.name] = true
	_reserve_seat(data.occupation, int(profile["seat_index"]))
	npcs.append(npc)
	profiles[npc.id] = profile


## Datos del puesto: ocupación jugable (occupations.json) o puesto no jugable (roles).
static func job_info(occupation_id: String, role_id: String) -> Dictionary:
	if not occupation_id.is_empty():
		var occ: OccupationData = Database.get_occupation(occupation_id)
		if occ != null:
			return {"tier": occ.tier, "clearance": occ.clearance, "daily_wage": occ.daily_wage,
					"department": str(occ.extra.get("department", "")), "external": false,
					"office_room": occ.office_room}
	var role: Dictionary = Database.get_role(role_id) if not role_id.is_empty() else {}
	return {"tier": int(role.get("tier", OccupationData.MIN_TIER)),
			"clearance": int(role.get("clearance", 0)),
			"daily_wage": int(role.get("daily_wage", 0)), "department": "",
			"external": bool(role.get("external", false)), "office_room": ""}


func _base_profile(job: Dictionary, extra: Dictionary) -> Dictionary:
	return {
		"role": str(extra.get("role", "")), "shift": str(extra.get("shift", "")),
		"daily_wage": int(extra.get("daily_wage", job.get("daily_wage", 0))),
		"clearance": int(extra.get("clearance", job.get("clearance", 0))),
		"future_occupation": str(extra.get("future_occupation", "")),
		"future_occupation_day": int(extra.get("future_occupation_day", 0)),
		"external": bool(job.get("external", false)), "zone_floors": [], "secrets": [],
		"blackmail_secrets": [], "knows_safe_combination": false, "special": {},
	}


# ─── Generados ────────────────────────────────────────────────

func _generate_department(dep: Dictionary) -> void:
	var slots: Array = dep.get(KEY_SLOTS, [])
	var bag: Dictionary = free_bag(dep.get("archetype_bag", {}), slots)
	for slot: Variant in slots:
		if not (slot is Dictionary):
			continue
		for i: int in int(slot.get("count", 0)):
			var forced: String = str(slot.get("archetype", ""))
			var archetype: String = forced if not forced.is_empty() else pick_weighted(bag)
			_create_generated(dep, slot, i, archetype)


## Bolsa sin los arquetipos forzados por alguna plaza, renormalizada (suma 1).
static func free_bag(bag: Dictionary, slots: Array) -> Dictionary:
	var forced: Dictionary = {}
	for slot: Variant in slots:
		if slot is Dictionary and not str(slot.get("archetype", "")).is_empty():
			forced[str(slot["archetype"])] = true
	var out: Dictionary = {}
	var total: float = 0.0
	for key: Variant in bag:
		if str(key).begins_with("_") or forced.has(str(key)):
			continue
		out[str(key)] = float(bag[key])
		total += float(bag[key])
	if total > 0.0:
		for key: String in out:
			out[key] = float(out[key]) / total
	return out


func pick_weighted(weights: Dictionary) -> String:
	var total: float = 0.0
	for key: Variant in weights:
		total += float(weights[key])
	var roll: float = _rng.randf() * total
	var last: String = ""
	for key: Variant in weights:
		last = str(key)
		roll -= float(weights[key])
		if roll < 0.0:
			return last
	return last


func _create_generated(dep: Dictionary, slot: Dictionary, index: int, archetype: String) -> void:
	_generated_count += 1
	var npc: NPCRuntime = NPCRuntime.new()
	npc.id = GENERATED_ID_FORMAT % _generated_count
	npc.name = _pick_name()
	npc.archetype = archetype
	npc.traits = roll_traits(archetype)
	npc.occupation_id = str(slot.get("occupation", ""))
	var role: String = str(slot.get("role", ""))
	var job: Dictionary = job_info(npc.occupation_id, role)
	npc.tier = int(job.get("tier", npc.tier))
	npc.department = str(dep.get("id", ""))
	npc.home_room = str(slot.get("room", ""))
	npc.current_room = npc.home_room
	npc.desk_position = _desk_for(slot, index)
	npc.routine_template = _routine_for(npc.occupation_id, slot, npc.tier)
	npc.home_address = _home_address_for(npc.tier)
	var profile: Dictionary = _base_profile(job, {"role": role, "shift": slot.get("shift", "")})
	profile["seat_index"] = _slot_seat(npc.occupation_id, slot, index)
	profile["zone_floors"] = _int_array(slot.get("cleaning_zone_floors", []))
	npc.is_slacker = _roll_slacker(npc.tier, bool(profile["external"]))
	npc.gatherings = _roll_gatherings(npc)
	npc.portrait_seed = _roll_portrait_seed()
	npcs.append(npc)
	profiles[npc.id] = profile


## Rasgos = base del arquetipo + desviación uniforme en [−v, +v], acotados a [0, 100].
func roll_traits(archetype: String) -> Dictionary:
	var data: ArchetypeData = Database.get_archetype(archetype)
	var variation: int = Database.get_archetype_variation_range()
	var out: Dictionary = Validate.default_traits()
	for trait_name: String in Validate.TRAIT_NAMES:
		var base: int = data.get_trait(trait_name) if data != null else Validate.TRAIT_MIN
		out[trait_name] = clampi(base + _rng.randi_range(-variation, variation),
				Validate.TRAIT_MIN, Validate.TRAIT_MAX)
	return out


func _pick_name() -> String:
	var bank: Dictionary = _rules.get("name_bank", {})
	var firsts: Array = bank.get("first_names", [])
	var lasts: Array = bank.get("last_names", [])
	if firsts.is_empty() or lasts.is_empty():
		return GENERATED_ID_FORMAT % _generated_count
	for _attempt: int in firsts.size() * lasts.size():
		var candidate: String = NAME_FORMAT % [firsts[_rng.randi_range(0, firsts.size() - 1)],
				lasts[_rng.randi_range(0, lasts.size() - 1)]]
		if not _used_names.has(candidate):
			_used_names[candidate] = true
			return candidate
	return _first_free_name(firsts, lasts)


func _first_free_name(firsts: Array, lasts: Array) -> String:
	for first: Variant in firsts:
		for last: Variant in lasts:
			var candidate: String = NAME_FORMAT % [first, last]
			if not _used_names.has(candidate):
				_used_names[candidate] = true
				return candidate
	return GENERATED_ID_FORMAT % _generated_count


func _routine_for(occupation_id: String, slot: Dictionary, tier: int) -> String:
	var explicit: String = str(slot.get("routine_template", ""))
	if not explicit.is_empty():
		return explicit
	var by_occupation: Variant = _rules.get("occupation_routine_template", {}).get(occupation_id)
	if by_occupation is String:
		return by_occupation
	if by_occupation is Dictionary:
		return str((by_occupation as Dictionary).get(str(slot.get("shift", "")), ""))
	return str(_rules.get("tier_to_routine_template", {}).get(str(tier), ""))


func _home_address_for(tier: int) -> String:
	return str(_rules.get("tier_to_home_address", {}).get(str(tier), ""))


func _roll_slacker(tier: int, external: bool) -> bool:
	var probability: float = float(_rules.get("slacker_probability_tier_1_3", 0.0))
	var roll: float = _rng.randf()
	if tier > SLACKER_MAX_TIER:
		return false
	if external and bool(_rules.get("slacker_excludes_external", true)):
		return false
	return roll < probability



func _roll_gatherings(npc: NPCRuntime) -> Array[String]:
	var out: Array[String] = []
	var membership: Dictionary = _rules.get("gathering_membership", {})
	for gathering: Variant in membership:
		var rule: Variant = membership[gathering]
		if str(gathering) == KEY_NOTE or not (rule is Dictionary) or rule.has("fixed_link"):
			continue
		var roll: float = _rng.randf()
		if _gathering_applies(rule, npc) and roll < float(rule.get("probability", 0.0)):
			out.append(str(gathering))
	return out


static func _gathering_applies(rule: Dictionary, npc: NPCRuntime) -> bool:
	if rule.has("home_rooms"):
		return (rule["home_rooms"] as Array).has(npc.home_room)
	if rule.has("departments") and not (rule["departments"] as Array).has(npc.department):
		return false
	return not rule.has("max_tier") or npc.tier <= int(rule["max_tier"])


func _roll_portrait_seed() -> int:
	var seed_range: Array = _rules.get("portrait_seed_range", [])
	if seed_range.size() < 2:
		return _rng.randi()
	return _rng.randi_range(int(seed_range[0]), int(seed_range[1]))


## Pareja clandestina de contabilidad (§7.7): los primeros `count` generados de su sala reciben el
## corrillo; SocialGraph crea la arista de pareja entre quienes lo comparten.
func _apply_fixed_link_gatherings() -> void:
	for link: Variant in _rules.get("fixed_generated_links", []):
		if not (link is Dictionary):
			continue
		var remaining: int = int(link.get("count", 0))
		for npc: NPCRuntime in npcs:
			if remaining <= 0:
				break
			if not npc.is_named and npc.department == str(link.get("department", "")) \
					and npc.home_room == str(link.get("room", "")):
				npc.gatherings.append(str(link.get("gathering", link.get("id", ""))))
				remaining -= 1


# ─── Sillas y escritorios ─────────────────────────────────────

func _slot_seat(occupation_id: String, slot: Dictionary, index: int) -> int:
	if occupation_id.is_empty():
		return -1
	if slot.has("first_seat_index"):
		var seat: int = int(slot["first_seat_index"]) + index
		_reserve_seat(occupation_id, seat)
		return seat
	return _next_seat(occupation_id)


func _next_seat(occupation_id: String) -> int:
	if occupation_id.is_empty():
		return -1
	var seat: int = int(_seat_next.get(occupation_id, 0))
	_seat_next[occupation_id] = seat + 1
	return seat


func _reserve_seat(occupation_id: String, seat: int) -> void:
	if occupation_id.is_empty() or seat < 0:
		return
	_seat_next[occupation_id] = maxi(int(_seat_next.get(occupation_id, 0)), seat + 1)


static func _desk_for(slot: Dictionary, index: int) -> Vector2i:
	var desks: Variant = slot.get("desk_positions", [])
	if desks is Array and index < (desks as Array).size():
		var pos: Variant = desks[index]
		if pos is Array and (pos as Array).size() >= 2:
			return Vector2i(int(pos[0]), int(pos[1]))
	return NPCRuntime.NO_DESK


static func _int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if raw is Array:
		for v: Variant in raw:
			out.append(int(v))
	return out


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for v: Variant in raw:
			out.append(str(v))
	return out
