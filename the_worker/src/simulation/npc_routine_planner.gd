# npc_routine_planner.gd — Agenda diaria de un personaje a partir de su plantilla de rutina (§24.5).
# PROPIETARIO DE: nada (índices de salas de solo lectura; las agendas las guarda NPCDirector).
# ESCUCHA: nada.
class_name NPCRoutinePlanner
extends RefCounted

## Agenda = Array de intervalos {start, end (minutos del día, end exclusivo), room, activity,
## kind, priority}. Prioridades (mayor manda; a igualdad, el que empezó más tarde, §29):
##   segment 0 (plantilla) < via 1 (paso por torniquetes/vestuario) < event 2 (reuniones, rondas)
##   = modifier 2 (café, baño, fotocopiadora, fumadores) < slack 3 (escaqueo) < override 4
##   (routine_overrides del personaje). override_routine() de NPCDirector está por encima de todo.
## Una agenda es determinista: su azar se siembra con (semilla de partida, jornada, id).
## Los overrides con "condition" (p. ej. presentar en Aurora) no se programan aquí: el sistema que
## conoce la condición llama a NPCDirector.override_routine().
## room "" = fuera del edificio (ABSENT).

const ABSENT := ""
const KIND_SEGMENT := "segment"
const KIND_VIA := "via"
const KIND_EVENT := "event"
const KIND_MODIFIER := "modifier"
const KIND_SLACK := "slack"
const KIND_OVERRIDE := "override"
const PRIORITY: Dictionary = {
	KIND_SEGMENT: 0, KIND_VIA: 1, KIND_EVENT: 2, KIND_MODIFIER: 2, KIND_SLACK: 3,
	KIND_OVERRIDE: 4,
}
## Tipos breves que no cuentan para la ubicación «programada» de una franja.
const MINOR_KINDS: Array[String] = [KIND_VIA, KIND_MODIFIER, KIND_SLACK]
const ACTIVITY_SLACKING := "slacking"
const ACTIVITY_TRAVEL := "travel"
const ACTIVITY_SMOKE := "smoke"
const ACTIVITY_WORK := "work"

# Fichas de ubicación de npcs_generation.json (routine_templates._nota).
const LOC_HOME := "home_room"
const LOC_ABSENT := "absent"
const LOC_ZONE := "assigned_zone"
const LOC_ROUND := "assigned_round"
const LOC_OTHER_FLOOR := "other_floor"
const LOC_PANTRY := "floor_pantry"
const LOC_COPY := "floor_copyroom"
const TIER_TEMPLATE_PREFIX := "tier_"
const SEED_FORMAT := "%d|%d|%s"

const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440
const NO_FLOOR := -1000

const B_BAND_STARTS := "tiempo.franjas_hora_inicio"
const B_REPRESENTATIVE := "rutinas.hora_representativa_franja"
const B_VIA_MINUTES := "rutinas.minutos_paso"
const B_ZONE_MINUTES := "rutinas.minutos_por_sala_zona"
## Ficha floor_* → fragmento del id de sala (contenido en balance.json, no en código).
const B_ROOM_PATTERNS := "rutinas.patrones_sala"
const B_COPY_FALLBACK := "rutinas.sala_fotocopias_por_defecto"
const B_SMOKERS := "rutinas.corrillo_fumadores"
const B_FACTORY_FLOOR := "mundo.planta_fabrica"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"

var _templates: Dictionary = {}
var _modifiers: Dictionary = {}
## [[minuto_inicio, franja], ...] ordenado.
var _band_starts: Array = []
var _representative: Dictionary = {}
var _via_minutes: int = 0
var _zone_minutes: int = MINUTES_PER_HOUR
var _rooms_by_floor: Dictionary = {}
var _room_floor: Dictionary = {}
var _dept_rooms: Dictionary = {}
var _building_floors: Array[int] = []
var _room_patterns: Dictionary = {}
var _copy_fallback: String = ""
var _smokers_gathering: String = ""


func _init(generation_rules: Dictionary) -> void:
	_templates = generation_rules.get("routine_templates", {})
	_modifiers = generation_rules.get("routine_common_modifiers", {})
	for dep: Variant in generation_rules.get("departments", []):
		if dep is Dictionary:
			_dept_rooms[str(dep.get("id", ""))] = dep.get("rooms", [])
	_load_bands()
	_via_minutes = Database.get_balance_int(B_VIA_MINUTES)
	_zone_minutes = maxi(Database.get_balance_int(B_ZONE_MINUTES), 1)
	var patterns: Variant = Database.get_balance(B_ROOM_PATTERNS)
	_room_patterns = (patterns as Dictionary).duplicate() if patterns is Dictionary else {}
	_copy_fallback = str(Database.get_balance(B_COPY_FALLBACK))
	_smokers_gathering = str(Database.get_balance(B_SMOKERS))
	_index_rooms()


# ─── Consulta ─────────────────────────────────────────────────

## Intervalo vigente en `minute`; {} si ninguno. include_minor = false ignora paso, café, baño,
## fotocopiadora, fumadores y escaqueo (ubicación «programada» de la franja).
static func pick(plan: Array, minute: int, include_minor: bool) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in plan:
		var iv: Dictionary = entry
		if minute < int(iv["start"]) or minute >= int(iv["end"]):
			continue
		if not include_minor and MINOR_KINDS.has(str(iv["kind"])):
			continue
		if best.is_empty() or int(iv["priority"]) > int(best["priority"]) \
				or (int(iv["priority"]) == int(best["priority"])
				and int(iv["start"]) >= int(best["start"])):
			best = iv
	return best


func band_of_minute(minute: int) -> String:
	var band: String = str(_band_starts.back()[1]) if not _band_starts.is_empty() else ""
	for pair: Variant in _band_starts:
		if minute >= int(pair[0]):
			band = str(pair[1])
	return band


func band_start_minute(band: String) -> int:
	for pair: Variant in _band_starts:
		if str(pair[1]) == band:
			return int(pair[0])
	return 0


## Fin de la franja (inicio de la siguiente; la última acaba a medianoche).
func band_end_minute(band: String) -> int:
	for i: int in _band_starts.size():
		if str(_band_starts[i][1]) == band and i + 1 < _band_starts.size():
			return int(_band_starts[i + 1][0])
	return MINUTES_PER_DAY


func representative_minute(band: String) -> int:
	return int(_representative.get(band, band_start_minute(band)))


## Planta de una sala (copia transversal "id@3" → 3); NO_FLOOR si se desconoce.
func room_floor(room_id: String) -> int:
	if room_id.contains(DatabaseSystem.INSTANCE_SEPARATOR):
		return room_id.get_slice(DatabaseSystem.INSTANCE_SEPARATOR, 1).to_int()
	return int(_room_floor.get(room_id, NO_FLOOR))


## "HH:MM" → minutos del día; -1 si el formato no es válido.
static func parse_time(text: String) -> int:
	var parts: PackedStringArray = text.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	return parts[0].to_int() * MINUTES_PER_HOUR + parts[1].to_int()


# ─── Construcción de la agenda ────────────────────────────────

func build_plan(npc: NPCRuntime, profile: Dictionary, day: int, run_seed: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (SEED_FORMAT % [run_seed, day, npc.id]).hash()
	var ctx: Dictionary = {"npc": npc, "profile": profile, "rng": rng}
	var template: Dictionary = _templates.get(npc.routine_template, {})
	var plan: Array = []
	if rng.randf() < float(template.get("travel_day_probability", 0.0)):
		_add(plan, 0, MINUTES_PER_DAY, ABSENT, ACTIVITY_TRAVEL, KIND_SEGMENT)
		return plan
	_add_segments(plan, template, ctx)
	_add_events(plan, template.get("events", []), ctx)
	if npc.routine_template.begins_with(TIER_TEMPLATE_PREFIX):
		_add_modifiers(plan, ctx)
	if npc.is_slacker:
		_add_slacking(plan, ctx)
	for o: Dictionary in npc.routine_overrides:
		_add_override(plan, o, ctx)
	return plan


func _add_segments(plan: Array, template: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var segments: Array = template.get("segments", [])
	var starts: Array[int] = []
	for seg: Variant in segments:
		var start: int = parse_time(str(seg.get("start", "00:00")))
		start += rng.randi_range(0, int(seg.get("jitter_minutes", 0)))
		starts.append(maxi(start, int(starts.back()) if not starts.is_empty() else 0))
	for i: int in segments.size():
		var seg: Dictionary = segments[i]
		var end: int = starts[i + 1] if i + 1 < starts.size() else MINUTES_PER_DAY
		var token: String = _choose_token(seg, rng)
		_add_resolved(plan, starts[i], end, token, str(seg.get("activity", "")), KIND_SEGMENT,
				ctx, [])
		if i > 0 and seg.has("via") and _via_minutes > 0:
			_add(plan, starts[i], mini(starts[i] + _via_minutes, end), str(seg["via"]),
					str(seg.get("activity", "")), KIND_VIA)


func _add_events(plan: Array, events: Array, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	for ev: Variant in events:
		if not (ev is Dictionary):
			continue
		for start: int in _event_starts(ev, rng):
			var dur: Array = ev.get("duration_minutes", [0, 0])
			var length: int = rng.randi_range(int(dur[0]), int(dur[1]))
			var token: String = _choose_token(ev, rng)
			if _is_present(plan, start):
				_add_resolved(plan, start, start + length, token, str(ev.get("activity", "")),
						KIND_EVENT, ctx, [])


## Inicios de un evento: `count` [min, max] al azar o `every_minutes` dentro de start_window
## (una ventana cuyo final precede a su inicio cruza la medianoche).
func _event_starts(ev: Dictionary, rng: RandomNumberGenerator) -> Array[int]:
	var window: Array = ev.get("start_window", ["00:00", "23:59"])
	var from: int = parse_time(str(window[0]))
	var to: int = parse_time(str(window[1]))
	if to < from:
		to += MINUTES_PER_DAY
	var out: Array[int] = []
	if ev.has("every_minutes"):
		var t: int = from
		while t <= to:
			out.append(t % MINUTES_PER_DAY)
			t += maxi(int(ev["every_minutes"]), 1)
		return out
	var count: Array = ev.get("count", [0, 0])
	for _i: int in rng.randi_range(int(count[0]), int(count[1])):
		out.append(rng.randi_range(from, to) % MINUTES_PER_DAY)
	return out


## Modificadores comunes de §24.5 (solo plantillas tier_*): café 10:30 y 16:00, baño,
## fotocopiadora y corrillo de fumadores cada dos horas (miembros generados del corrillo).
func _add_modifiers(plan: Array, ctx: Dictionary) -> void:
	for brk: Variant in _modifiers.get("coffee_breaks", []):
		var start: int = parse_time(str(brk.get("time", "")))
		if start >= 0 and _is_present(plan, start):
			_add_resolved(plan, start, start + int(brk.get("duration_minutes", 0)),
					str(brk.get("location", LOC_PANTRY)), "coffee", KIND_MODIFIER, ctx, [])
	for key: String in ["toilet", "copier"]:
		_add_random_trips(plan, _modifiers.get(key, {}), key, ctx)
	var npc: NPCRuntime = ctx["npc"]
	if not npc.is_named and npc.gatherings.has(_smokers_gathering):
		_add_smoke_breaks(plan, _modifiers.get(_smokers_gathering, {}), ctx)


## Corrillo de fumadores (§7.7): cada interval_hours desde first_time mientras esté presente.
func _add_smoke_breaks(plan: Array, rule: Dictionary, ctx: Dictionary) -> void:
	var step: int = int(rule.get("interval_hours", 0)) * MINUTES_PER_HOUR
	var t: int = parse_time(str(rule.get("first_time", "")))
	if step <= 0:
		return
	while t >= 0 and t < MINUTES_PER_DAY:
		if _is_present(plan, t):
			_add_resolved(plan, t, t + int(rule.get("duration_minutes", 0)),
					str(rule.get("location", "")), ACTIVITY_SMOKE, KIND_MODIFIER, ctx, [])
		t += step


func _add_random_trips(plan: Array, rule: Dictionary, activity: String, ctx: Dictionary) -> void:
	if rule.is_empty():
		return
	var rng: RandomNumberGenerator = ctx["rng"]
	var work: Array[Vector2i] = _work_segments(plan)
	var count: Array = rule.get("count", [0, 0])
	var dur: Array = rule.get("duration_minutes", [0, 0])
	for _i: int in rng.randi_range(int(count[0]), int(count[1])):
		var length: int = rng.randi_range(int(dur[0]), int(dur[1]))
		var start: int = _random_work_start(work, length, rng)
		if start >= 0 and _is_present(plan, start):
			_add_resolved(plan, start, start + length, str(rule.get("location", "")), activity,
					KIND_MODIFIER, ctx, [])


## Escaqueo (§24.5): ausencias impredecibles del puesto hacia un escondite.
func _add_slacking(plan: Array, ctx: Dictionary) -> void:
	var rule: Dictionary = _modifiers.get("slacker", {})
	var rng: RandomNumberGenerator = ctx["rng"]
	var work: Array[Vector2i] = _work_segments(plan)
	var hideouts: Array = rule.get("hideouts", [])
	var per_day: Array = rule.get("absences_per_day", [0, 0])
	var minutes: Array = rule.get("absence_minutes", [0, 0])
	for _i: int in rng.randi_range(int(per_day[0]), int(per_day[1])):
		var length: int = rng.randi_range(int(minutes[0]), int(minutes[1]))
		var start: int = _random_work_start(work, length, rng)
		var room: String = str(hideouts[rng.randi_range(0, hideouts.size() - 1)]) \
				if not hideouts.is_empty() else ABSENT
		if start >= 0 and not room.is_empty() and _is_present(plan, start):
			_add(plan, start, start + length, room, ACTIVITY_SLACKING, KIND_SLACK)


## routine_overrides del personaje (§29): hora, retraso aleatorio, repetición y duración.
func _add_override(plan: Array, o: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var jitter: int = rng.randi_range(0, int(o.get("time_jitter_minutes", 0)))
	if o.has("condition"):
		return
	var band: String = str(o.get("band", ""))
	var start: int = parse_time(str(o.get("time", ""))) if o.has("time") \
			else band_start_minute(band)
	start += jitter
	var length: int = int(o.get("duration_minutes", band_end_minute(band) - start))
	var until: int = parse_time(str(o.get("until", ""))) if o.has("until") else start
	var every: int = int(o.get("repeat_every_minutes", 0))
	var location: String = str(o.get("location", ""))
	var token: String = location if not location.is_empty() else LOC_HOME
	var floors: Array = o.get("zone_floors", [])
	var t: int = start
	while t <= until:
		_add_resolved(plan, t, t + length, token, str(o.get("action", "")), KIND_OVERRIDE,
				ctx, floors)
		if every <= 0:
			break
		t += every


# ─── Intervalos y fichas de ubicación ─────────────────────────

## Añade el intervalo; una zona de limpieza o una ronda se trocea en salas de N minutos.
func _add_resolved(plan: Array, start: int, end: int, token: String, activity: String,
		kind: String, ctx: Dictionary, zone_floors: Array) -> void:
	if token != LOC_ZONE and token != LOC_ROUND:
		_add(plan, start, end, resolve_location(token, ctx, zone_floors), activity, kind)
		return
	var t: int = start
	while t < end:
		var chunk_end: int = mini(t + _zone_minutes, end)
		_add(plan, t, chunk_end, resolve_location(token, ctx, zone_floors), activity, kind)
		t = chunk_end


func _add(plan: Array, start: int, end: int, room: String, activity: String,
		kind: String) -> void:
	if end <= start:
		return
	var s: int = posmod(start, MINUTES_PER_DAY)
	var e: int = s + (end - start)
	plan.append(_interval(s, mini(e, MINUTES_PER_DAY), room, activity, kind))
	if e > MINUTES_PER_DAY:
		plan.append(_interval(0, mini(e - MINUTES_PER_DAY, MINUTES_PER_DAY), room, activity, kind))


static func _interval(start: int, end: int, room: String, activity: String,
		kind: String) -> Dictionary:
	return {"start": start, "end": end, "room": room, "activity": activity, "kind": kind,
			"priority": int(PRIORITY.get(kind, 0))}


func _choose_token(entry: Dictionary, rng: RandomNumberGenerator) -> String:
	var choices: Variant = entry.get("location_choices")
	if choices is Dictionary and not (choices as Dictionary).is_empty():
		var total: float = 0.0
		for key: Variant in choices:
			total += float(choices[key])
		var roll: float = rng.randf() * total
		for key: Variant in choices:
			roll -= float(choices[key])
			if roll < 0.0:
				return str(key)
		return str((choices as Dictionary).keys().back())
	return str(entry.get("location", LOC_HOME))


## Traduce una ficha (home_room, absent, assigned_zone, floor_toilets...) a un id de sala.
func resolve_location(token: String, ctx: Dictionary, zone_floors: Array) -> String:
	var npc: NPCRuntime = ctx["npc"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var home_floor: int = room_floor(npc.home_room)
	match token:
		LOC_HOME:
			return npc.home_room
		LOC_ABSENT:
			return ABSENT
		LOC_ZONE:
			var floors: Array = zone_floors if not zone_floors.is_empty() \
					else ctx["profile"].get("zone_floors", [])
			return _random_room_on(floors, rng, npc.home_room)
		LOC_ROUND:
			return _random_room_on(_building_floors, rng, npc.home_room)
		LOC_OTHER_FLOOR:
			return _other_floor_room(npc, home_floor, rng)
	var pattern: String = str(_room_patterns.get(token, ""))
	if not pattern.is_empty():
		var fallback: String = _copy_fallback if token == LOC_COPY else npc.home_room
		return _room_on_floor(home_floor, pattern, rng, fallback)
	return token


func _random_room_on(floors: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	var pool: Array = []
	for f: Variant in floors:
		pool.append_array(_rooms_by_floor.get(int(f), []))
	if pool.is_empty():
		return fallback
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func _room_on_floor(floor_number: int, pattern: String, rng: RandomNumberGenerator,
		fallback: String) -> String:
	var matches: Array = []
	for room_id: Variant in _rooms_by_floor.get(floor_number, []):
		if str(room_id).contains(pattern):
			matches.append(room_id)
	if matches.is_empty():
		return fallback
	return str(matches[rng.randi_range(0, matches.size() - 1)])


func _other_floor_room(npc: NPCRuntime, home_floor: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for room_id: Variant in _dept_rooms.get(npc.department, []):
		var f: int = room_floor(str(room_id))
		if f != home_floor and f != NO_FLOOR:
			pool.append(room_id)
	if pool.is_empty():
		return npc.home_room
	return str(pool[rng.randi_range(0, pool.size() - 1)])


## true si en `minute` el personaje está en el edificio según los tramos ya programados.
func _is_present(plan: Array, minute: int) -> bool:
	var iv: Dictionary = pick(plan, posmod(minute, MINUTES_PER_DAY), false)
	return not iv.is_empty() and not str(iv["room"]).is_empty()


## Tramos de trabajo de la plantilla (activity "work"): [inicio, fin) de cada uno.
func _work_segments(plan: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry: Variant in plan:
		var iv: Dictionary = entry
		if str(iv["kind"]) == KIND_SEGMENT and str(iv["activity"]) == ACTIVITY_WORK \
				and int(iv["end"]) > int(iv["start"]):
			out.append(Vector2i(int(iv["start"]), int(iv["end"])))
	return out


## Inicio al azar dentro de un tramo de trabajo para una salida de `length` minutos; -1 si no hay.
static func _random_work_start(work: Array[Vector2i], length: int,
		rng: RandomNumberGenerator) -> int:
	if work.is_empty():
		return -1
	var seg: Vector2i = work[rng.randi_range(0, work.size() - 1)]
	return rng.randi_range(seg.x, maxi(seg.x, seg.y - length))


# ─── Índices ──────────────────────────────────────────────────

func _load_bands() -> void:
	var starts: Variant = Database.get_balance(B_BAND_STARTS)
	_band_starts.clear()
	if starts is Dictionary:
		for band: Variant in starts:
			if not str(band).begins_with("_"):
				_band_starts.append([int(starts[band]) * MINUTES_PER_HOUR, str(band)])
	_band_starts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var reps: Variant = Database.get_balance(B_REPRESENTATIVE)
	if reps is Dictionary:
		for band: Variant in reps:
			if not str(band).begins_with("_"):
				_representative[str(band)] = parse_time(str(reps[band]))


func _index_rooms() -> void:
	var excluded: Array[int] = [Database.get_balance_int(B_FACTORY_FLOOR),
			Database.get_balance_int(B_EXTERIOR_FLOOR), RoomData.TRANSVERSAL_FLOOR]
	for room: RoomData in Database.get_all_rooms():
		_room_floor[room.id] = room.floor
		if room.is_transversal():
			continue
		if not _rooms_by_floor.has(room.floor):
			_rooms_by_floor[room.floor] = []
		(_rooms_by_floor[room.floor] as Array).append(room.id)
		if not excluded.has(room.floor) and not _building_floors.has(room.floor):
			_building_floors.append(room.floor)
	_building_floors.sort()
