# npc_listener.gd — Oído sobre los NPCs de la planta: pasos con dirección, silla, radios de vigilante.
# PROPIETARIO DE: el seguimiento acústico por NPC (posición previa, tiempo quieto/sentado, cadencia de pasos, próxima radio).
# ESCUCHA: nada (AudioDirector le pasa los nodos del grupo "npcs" y la posición del oyente).
class_name NpcListener
extends RefCounted

## §14.10 categoría 2: "aprender a escuchar constituye una habilidad real del jugador".
## scan() es determinista (semilla propia) y devuelve lo que debe sonar; no reproduce nada.
## Cada evento: {sfx: String, position: Vector2, subtitle: String ("" = el del efecto), importance: int}.
## Sondas (set_probes): `seated(node) -> bool` — la silla solo cruje si el NPC estaba SENTADO (no
## basta con estar quieto: la fuente de agua, un corrillo, un vigilante de puesto); sin sonda, no
## cruje nunca. `in_view(pos) -> bool` — pasos que se acercan FUERA DE LA VISTA (otra sala o fuera
## de cámara) = aviso (importancia 2); a la vista = "pasos cerca" (0), con su propia clave para que
## su enfriamiento no tape un aviso real. Sin sonda de vista, todo cuenta como fuera de la vista.
## AudioDirector no llama a scan() con el reloj o el árbol en pausa (el tiempo quieto no corre).

const APPROACH_KEY := "SUB_STEPS_APPROACHING"
const NEARBY_KEY := "SUB_STEPS_NEARBY"
const RECEDE_KEY := "SUB_STEPS_RECEDING"
const STEP_SFX := "npc_step"
const CHAIR_SFX := "chair_creak"
const RADIO_SFX := "guard_radio"
const NO_SUBTITLE := "-"

var _cfg: Dictionary = {}
var _state: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seated_probe: Callable = Callable()
var _view_probe: Callable = Callable()


## cfg: hear_px, npc_min_speed, npc_step_s, seated_s, approach_px, radio_interval (Vector2),
## max_steps, radio_occupations (Array).
func setup(cfg: Dictionary, rng_seed: int) -> void:
	_cfg = cfg
	_rng.seed = rng_seed
	_state.clear()


## seated: func(node: Node2D) -> bool · in_view: func(world_pos: Vector2) -> bool.
func set_probes(seated: Callable, in_view: Callable) -> void:
	_seated_probe = seated
	_view_probe = in_view


func reset(rng_seed: int) -> void:
	_rng.seed = rng_seed
	_state.clear()


func tracked_count() -> int:
	return _state.size()


## Analiza los nodos NPC (Node2D) de la planta durante `dt` segundos y devuelve los sonidos a emitir.
func scan(nodes: Array[Node], listener: Vector2, dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var steps_left: int = int(_cfg.get("max_steps", 0))
	for node: Node in nodes:
		if not node is Node2D:
			continue
		var id: String = npc_key(node)
		seen[id] = true
		steps_left = _scan_one(node as Node2D, id, listener, dt, steps_left, out)
	for id: String in _state.keys():
		if not seen.has(id):
			_state.erase(id)
	return out


## Nodo seguido para un npc_id (null si no está en la planta).
func node_for(npc_id: String) -> Node2D:
	var node: Variant = (_state.get(npc_id, {}) as Dictionary).get("node")
	if node is Node2D and is_instance_valid(node):
		return node as Node2D
	return null


## Posición del vigilante seguido más cercano al oyente (Vector2.INF si no hay).
func nearest_guard(listener: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	for id: String in _state.keys():
		var st: Dictionary = _state[id]
		var p: Vector2 = st["pos"]
		if bool(st["guard"]) and (not best.is_finite() or p.distance_to(listener) < best.distance_to(listener)):
			best = p
	return best


static func npc_key(node: Node) -> String:
	var id: Variant = node.get("npc_id")
	return str(id) if id != null and not str(id).is_empty() else str(node.get_instance_id())


func _scan_one(node: Node2D, id: String, listener: Vector2, dt: float, steps_left: int,
		out: Array[Dictionary]) -> int:
	var pos: Vector2 = node.global_position
	var dist: float = pos.distance_to(listener)
	if not _state.has(id):
		_state[id] = {"node": node, "pos": pos, "dist": dist, "still": 0.0, "seated": false, "step": 0.0,
				"radio": _next_radio_delay(), "guard": _is_guard(node, id)}
		return steps_left
	var st: Dictionary = _state[id]
	var audible: bool = dist <= float(_cfg["hear_px"])
	var speed: float = pos.distance_to(st["pos"]) / maxf(dt, SynthDSP.DENORMAL_GUARD)
	if speed >= float(_cfg["npc_min_speed"]):
		if bool(st["seated"]) and audible:
			out.append(_event(CHAIR_SFX, pos, "", SfxBank.importance(CHAIR_SFX)))
		st["still"] = 0.0
		st["seated"] = false
		st["step"] = float(st["step"]) + dt
		if audible and steps_left > 0 and float(st["step"]) >= float(_cfg["npc_step_s"]):
			st["step"] = 0.0
			steps_left -= 1
			out.append(_step_event(float(st["dist"]), dist, pos))
	else:
		_tick_still(st, node, dt)
	_tick_radio(st, pos, audible, dt, out)
	st["pos"] = pos
	st["dist"] = dist
	return steps_left


## Quieto: al cumplir `seated_s` pregunta una vez si está sentado (y lo recuerda hasta que se mueva).
func _tick_still(st: Dictionary, node: Node2D, dt: float) -> void:
	var before: float = float(st["still"])
	st["still"] = before + dt
	var threshold: float = float(_cfg["seated_s"])
	if before < threshold and float(st["still"]) >= threshold and _seated_probe.is_valid():
		st["seated"] = bool(_seated_probe.call(node))


## Paso con subtítulo de dirección: se acerca fuera de la vista (aviso), a la vista, o se aleja.
func _step_event(previous: float, dist: float, pos: Vector2) -> Dictionary:
	var margin: float = float(_cfg["approach_px"])
	if dist < previous - margin:
		var seen: bool = _view_probe.is_valid() and bool(_view_probe.call(pos))
		if seen:
			return _event(STEP_SFX, pos, NEARBY_KEY, SfxBank.IMPORTANCE_AMBIENT)
		return _event(STEP_SFX, pos, APPROACH_KEY, SfxBank.IMPORTANCE_DANGER)
	if dist > previous + margin:
		return _event(STEP_SFX, pos, RECEDE_KEY, SfxBank.IMPORTANCE_AMBIENT)
	return _event(STEP_SFX, pos, NO_SUBTITLE, SfxBank.IMPORTANCE_AMBIENT)


func _tick_radio(st: Dictionary, pos: Vector2, audible: bool, dt: float, out: Array[Dictionary]) -> void:
	if not bool(st["guard"]):
		return
	st["radio"] = float(st["radio"]) - dt
	if float(st["radio"]) <= 0.0:
		st["radio"] = _next_radio_delay()
		if audible:
			out.append(_event(RADIO_SFX, pos, "", SfxBank.importance(RADIO_SFX)))


func _event(sfx: String, pos: Vector2, subtitle: String, importance: int) -> Dictionary:
	return {"sfx": sfx, "position": pos, "subtitle": subtitle, "importance": importance}


func _next_radio_delay() -> float:
	var r: Vector2 = _cfg.get("radio_interval", Vector2.ZERO)
	return _rng.randf_range(r.x, maxf(r.x, r.y))


func _is_guard(node: Node, id: String) -> bool:
	var occupation: String = str(node.get("occupation_id")) if node.get("occupation_id") != null else ""
	var director: Node = AudioTuning.autoload("NPCDirector")
	if occupation.is_empty() and director != null and director.has_method("get_npc"):
		var npc: Object = director.call("get_npc", id)
		if npc is NPCRuntime:
			occupation = (npc as NPCRuntime).occupation_id
	return (_cfg.get("radio_occupations", []) as Array).has(occupation)
