# tutorial_first_day.gd — Tercera parte del primer día (§13.8): tres tareas encadenadas que enseñan el bucle entero (contestar tres correos, ver a Claudia Reeves tener una idea y esconderse cuando pasa Bernard Lasker). El juego no dice que robes: te enseña que puedes.
# PROPIETARIO DE: la tarea en curso, el recuento de correos, el tiempo observando la idea, la ronda guionizada del jefe de ala y su figurante.
# ESCUCHA: nada (sondea DutySystem, IdeaPool, NPCLayer y el jugador en las esperas del director).
class_name TutorialFirstDay
extends RefCounted

## Nota de «tu primer día» (Tutorial.show_note) con las tres tareas; cada una se marca al cumplirse.
##  · Correos: unidades del deber de subtipo tutorial.tareas.subtipo_correo (DutySystem) desde que
##    empieza la tarea; el contador de la nota sigue a cada correo contestado en MAIL.
##  · Idea: cuando el jugador está cerca de Claudia Reeves (o pasa tutorial.tareas.espera_idea), se le
##    fuerza una idea (IdeaPool.generate_for_npc) y se la cuenta en voz alta al colega más cercano
##    (IdeaPool.share_idea: ventana real de «escuchar»). Se cumple observándola
##    tutorial.tareas.segundos_observar a tutorial.tareas.radio_observar_celdas. Queda en el cuaderno.
##  · Ronda: un colega avisa; el figurante de Bernard Lasker (percepción real) recorre la ruta de
##    tutorial.patrulla.ruta y se para junto al armario (tutorial.patrulla.escondite) a mirar el
##    cronómetro. Escondido mientras pasa cerca = cumplida. Visto (su cono le tiene
##    tutorial.patrulla.segundos_visto) = «¿Aclimatándonos?» y otra ronda; sin verle ni esconderse,
##    otra ronda. Presupuesto agotado: HR marca la casilla. Luego vuelve a su mesa y a su agenda.

const T_EMAILS := 0
const T_IDEA := 1
const T_HIDE := 2
const OUT_NONE := ""
const OUT_HIDDEN := "hidden"
const OUT_SPOTTED := "spotted"
const OUT_MISSED := "missed"
const POSE_WATCH := "check_watch"
const IDEA_NOTE_CATEGORY := "ideas"
const PERCENT := 100
const SWEEP_STEPS: Array[Vector2] = [Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT, Vector2.UP]

var bernard: TutorialActor = null
var _d: TutorialDirector = null
var _task: int = -1
var _email_base: int = 0
var _emails_shown: int = -1
var _observed: float = 0.0
var _observe_t: float = -1.0
var _observe_pct: int = -1
var _confidant: String = ""
var _seen_time: float = 0.0
var _outcome: String = OUT_NONE
var _outcomes: Array[String] = []


func _init(director: TutorialDirector) -> void:
	_d = director


func get_task() -> int:
	return _task


func get_confidant() -> String:
	return _confidant


## Resultados de cada ronda de Lasker (pruebas).
func get_patrol_outcomes() -> Array[String]:
	return _outcomes.duplicate()


func run() -> void:
	_d.ui.hide_speech()
	var target: int = int(_d.bal("tareas.correos"))
	_d.ui.show_note("TUT_DAY_TITLE", "TUT_DAY_FROM", [Tutorial.line("TUT_TASK_EMAILS", [0, target]),
			Tutorial.line("TUT_TASK_IDEA"), Tutorial.line("TUT_TASK_HIDE")])
	await _emails()
	await _breather()
	if not _d.is_ended():
		await _idea()
	await _breather()
	if not _d.is_ended():
		await _hide()
	if not _d.is_ended():
		await _farewell()


## Respiro entre tareas: el aviso de la anterior se lee antes de que empiece la siguiente.
func _breather() -> void:
	if not _d.is_ended():
		await _d.hold(_d.budget("tareas.pausa_entre_tareas"))


func _begin(index: int, step_id: String, hint: String, text: String = "") -> void:
	_task = index
	_d.set_step(step_id)
	_d.ui.set_task(index, Tutorial.STATE_ACTIVE, text)
	_d.ui.set_note_hint(hint)


func _complete(index: int, toast_key: String, args: Array = [], final_text: String = "") -> void:
	_d.ui.set_task(index, Tutorial.STATE_DONE, final_text)
	_d.ui.set_note_hint("")
	_d.toast(toast_key, args, ToastStack.KIND_GOOD)
	_d.sfx("ui_confirm")


# ─── 1. Correos ───────────────────────────────────────────────

func _emails() -> void:
	var target: int = int(_d.bal("tareas.correos"))
	var duty_id: String = email_duty()
	if duty_id.is_empty():
		_d.ui.set_task(T_EMAILS, Tutorial.STATE_DONE)
		return
	var touch: bool = _d.root.ui.is_touch_mode()
	var deadline: String = UITheme.format_hour(int(PlayerState.get_duty(duty_id).get(PlayerStateSystem.D_DEADLINE, 0)))
	_begin(T_EMAILS, "day_emails", Tutorial.line("TUT_TASK_EMAILS_HINT",
			[Tutorial.keycaps(["interact"], touch, "TUT_TOUCH_INTERACT"), deadline]))
	_email_base = email_units(duty_id)
	_emails_shown = -1
	var done: bool = await _d.wait_for(func() -> bool: return _emails_counted(duty_id, target), _d.budget("tareas.presupuesto.correos"))
	if _d.is_ended():
		return
	_complete(T_EMAILS, "TUT_TASK_EMAILS_DONE" if done else "TUT_TASK_TIMEOUT")


func _emails_counted(duty_id: String, target: int) -> bool:
	var n: int = clampi(email_units(duty_id) - _email_base, 0, target)
	if n != _emails_shown:
		_emails_shown = n
		_d.ui.set_task(T_EMAILS, Tutorial.STATE_ACTIVE, Tutorial.line("TUT_TASK_EMAILS", [n, target]))
		if n > 0:
			_d.sfx("ui_notify")
	return n >= target


## Deber de hoy de subtipo correo ("" si el puesto no lo tiene).
func email_duty() -> String:
	var subtype: String = str(_d.bal("tareas.subtipo_correo"))
	for duty: Dictionary in PlayerState.get_todays_duties():
		if str(duty.get(PlayerStateSystem.D_SUBTYPE, "")) == subtype:
			return str(duty.get(PlayerStateSystem.D_ID, ""))
	return ""


## Correos contestados de ese deber (sesión de DutySystem).
func email_units(duty_id: String) -> int:
	var duties: DutySystem = _d.root.sim_nodes.get("DutySystem") as DutySystem
	if duties == null:
		return 0
	return int(duties.get_session(duty_id).get("done", 0))


# ─── 2. La idea de Claudia ────────────────────────────────────

func _idea() -> void:
	var owner: String = str(_d.bal("tareas.idea_npc"))
	_begin(T_IDEA, "day_idea", Tutorial.line("TUT_TASK_IDEA_HINT"))
	await _d.wait_for(func() -> bool: return _near(owner), _d.budget("tareas.presupuesto.espera_idea"))
	if _d.is_ended():
		return
	_confidant = trigger_idea(owner)
	var who: String = _npc_first_name(_confidant)
	var line_key: String = "TUT_CLAUDIA_IDEA" if not who.is_empty() else "TUT_CLAUDIA_IDEA_ALONE"
	_d.speak(owner, Tutorial.line(line_key, [Tutorial.escape(who)] if not who.is_empty() else []))
	if not who.is_empty():
		_d.ui.set_note_hint(Tutorial.line("TUT_TASK_IDEA_FOLLOW", [Tutorial.escape(who)]))
	_d.set_step("day_idea_watch")
	_observed = 0.0
	_observe_t = -1.0
	_observe_pct = -1
	var done: bool = await _d.wait_for(func() -> bool: return _observing(owner), _d.budget("tareas.presupuesto.idea"))
	if _d.is_ended():
		return
	var name: String = _npc_name(_confidant)
	if not name.is_empty():
		EventBus.notebook_entry_added.emit(IDEA_NOTE_CATEGORY, "TUT_NOTE_IDEA", [name])
	var told: bool = done and not name.is_empty()
	_complete(T_IDEA, "TUT_TASK_IDEA_DONE" if told else "TUT_TASK_TIMEOUT", [name] if told else [], Tutorial.line("TUT_TASK_IDEA"))


## Fuerza la idea de `owner` y que se la cuente al colega más cercano. Devuelve el confidente ("" si nadie).
func trigger_idea(owner: String) -> String:
	var idea_id: String = IdeaPool.generate_for_npc(owner)
	if idea_id.is_empty():
		return ""
	var confidant: String = _pick_confidant(owner)
	if not confidant.is_empty():
		IdeaPool.share_idea(idea_id, confidant)
	if _d.root.npc_layer != null:
		_d.root.npc_layer.sync_now()
	return confidant


func _pick_confidant(owner: String) -> String:
	var owner_node: NPCNode = _d.root.npc_layer.get_node_for(owner) if _d.root.npc_layer != null else null
	if owner_node == null:
		return ""
	var best: String = ""
	var best_d: float = INF
	for node: NPCNode in _d.root.npc_layer.get_nodes():
		if node.npc_id == owner or node.npc_id == str(_d.bal("patrulla.npc")) or not _in_office(node):
			continue
		if SocialGraph.get_link_type(owner, node.npc_id) == NPCDirectorSystem.RIVAL_LINK_TYPE:
			continue
		var dist: float = node.global_position.distance_to(owner_node.global_position)
		if dist < best_d:
			best_d = dist
			best = node.npc_id
	return best


## El jugador en la oficina, sin ventana abierta y a tutorial.tareas.radio_observar_celdas de `npc_id`.
func _near(npc_id: String) -> bool:
	var node: NPCNode = _d.root.npc_layer.get_node_for(npc_id) if _d.root.npc_layer != null else null
	if node == null or _d.root.ui.has_modal() or _d.player_room() != _d.office_room():
		return false
	var reach: float = _d.bal_f("tareas.radio_observar_celdas") * _d.cell()
	return node.get_visual_position().distance_to(_d.root.player.global_position) <= reach


## Acumula el tiempo que el jugador la observa de cerca; la nota enseña el avance.
func _observing(owner: String) -> bool:
	var now: float = _d.get_elapsed()
	if _observe_t >= 0.0 and _near(owner):
		_observed += now - _observe_t
	_observe_t = now
	var need: float = maxf(_d.bal_f("tareas.segundos_observar"), 0.01)
	var pct: int = clampi(int(_observed / need * PERCENT), 0, PERCENT)
	if pct != _observe_pct:
		_observe_pct = pct
		_d.ui.set_task(T_IDEA, Tutorial.STATE_ACTIVE, Tutorial.line("TUT_TASK_IDEA_PROGRESS", [pct]))
	return _observed >= need


func _in_office(node: NPCNode) -> bool:
	return _d.root.streamer.get_room_at(node.global_position) == _d.office_room()


func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null
	return npc.name if npc != null else ""


func _npc_first_name(npc_id: String) -> String:
	return _npc_name(npc_id).get_slice(" ", 0)


# ─── 3. La ronda de Lasker ────────────────────────────────────

func _hide() -> void:
	var spot: HidingSpot = hiding_spot()
	if _d.office_room() != str(_d.bal("patrulla.sala")) or spot == null:
		_d.ui.set_task(T_HIDE, Tutorial.STATE_DONE)
		return
	var touch: bool = _d.root.ui.is_touch_mode()
	_begin(T_HIDE, "day_hide", Tutorial.line("TUT_TASK_HIDE_HINT", [Tutorial.keycaps(["interact"], touch, "TUT_TOUCH_INTERACT")]))
	_whisper()
	bernard = _take_over(str(_d.bal("patrulla.npc")))
	if bernard == null:
		_complete(T_HIDE, "TUT_TASK_TIMEOUT")
		return
	var until: float = _d.get_elapsed() + _d.budget("tareas.presupuesto.ronda")
	await _d.hold(_d.budget("patrulla.aviso_segundos"))
	var hidden: bool = false
	while not _d.is_ended() and not hidden and _d.get_elapsed() < until:
		var outcome: String = await patrol_once(until)
		if outcome == OUT_NONE:
			break
		_outcomes.append(outcome)
		hidden = outcome == OUT_HIDDEN
		if not hidden and not _d.is_ended():
			await _after_miss(outcome)
	if _d.is_ended():
		return
	_complete(T_HIDE, "TUT_TASK_HIDE_DONE" if hidden else "TUT_TASK_TIMEOUT")
	await _return_bernard()


func hiding_spot() -> HidingSpot:
	for spot: HidingSpot in _d.root.streamer.get_hiding_spots_in_room(_d.office_room()):
		if spot.interact_id == str(_d.bal("patrulla.escondite")):
			return spot
	return null


## Un colega avisa en voz baja (el más cercano al jugador en la oficina).
func _whisper() -> void:
	var best: String = ""
	var best_d: float = INF
	var skip: Array[String] = [str(_d.bal("tareas.idea_npc")), str(_d.bal("patrulla.npc"))]
	var nodes: Array[NPCNode] = _d.root.npc_layer.get_nodes() if _d.root.npc_layer != null else []
	for node: NPCNode in nodes:
		if skip.has(node.npc_id) or not _in_office(node):
			continue
		var dist: float = node.global_position.distance_to(_d.root.player.global_position)
		if dist < best_d:
			best_d = dist
			best = node.npc_id
	_d.speak(best, Tutorial.line("TUT_WHISPER_LASKER"), "TUT_WHISPERER_FALLBACK")
	_d.sfx("chatter")


## El figurante del jefe donde estaba su nodo (o en la puerta de la oficina) con su cono real.
func _take_over(npc_id: String) -> TutorialActor:
	var node: NPCNode = _d.root.npc_layer.get_node_for(npc_id) if _d.root.npc_layer != null else null
	var at: Vector2 = node.get_visual_position() if node != null else _d.root.streamer.get_spawn_point(_d.office_room())
	var actor: TutorialActor = _d.spawn_actor(npc_id, at, _d.bal_f("patrulla.velocidad_celdas"))
	if actor != null:
		actor.enable_perception()
	return actor


## Una vuelta: ruta, parada junto al armario mirando el cronómetro, barrido de cabeza. Se corta en
## `until` (tiempo activo del director).
func patrol_once(until: float = INF) -> String:
	_seen_time = 0.0
	var near_hidden: bool = false
	for point: Vector2 in _route_points():
		if bernard == null or not is_instance_valid(bernard):
			return OUT_NONE
		bernard.walk_to(point)
		while bernard.is_moving():
			await _d.get_tree().process_frame
			if _d.is_ended() or _d.get_elapsed() >= until:
				return OUT_NONE
			var seen: String = _judge()
			if seen == OUT_SPOTTED:
				return OUT_SPOTTED
			near_hidden = near_hidden or seen == OUT_HIDDEN
	var swept: String = await _sweep()
	if swept == OUT_SPOTTED:
		return OUT_SPOTTED
	return OUT_HIDDEN if near_hidden or swept == OUT_HIDDEN else OUT_MISSED


func _sweep() -> String:
	bernard.set_pose(POSE_WATCH)
	var result: String = OUT_NONE
	var step_s: float = _d.budget("patrulla.pausa_segundos") / float(SWEEP_STEPS.size())
	for dir: Vector2 in SWEEP_STEPS:
		bernard.look(dir)
		var t0: float = _d.get_elapsed()
		while _d.get_elapsed() - t0 < step_s and not _d.is_ended():
			await _d.get_tree().process_frame
			var seen: String = _judge()
			if seen == OUT_SPOTTED:
				bernard.set_pose("")
				return OUT_SPOTTED
			result = OUT_HIDDEN if seen == OUT_HIDDEN else result
	bernard.look(Vector2.ZERO)
	bernard.set_pose("")
	return result


## hidden: escondido con él a tutorial.patrulla.radio_paso_celdas; spotted: su cono le tiene el
## tiempo de tutorial.patrulla.segundos_visto (el indicador de detección llega a verse).
func _judge() -> String:
	var p: Player = _d.root.player
	var near: bool = p.global_position.distance_to(bernard.global_position) <= _d.bal_f("patrulla.radio_paso_celdas") * _d.cell()
	if p.is_hiding():
		_seen_time = 0.0
		return OUT_HIDDEN if near else OUT_NONE
	var sees: bool = bernard.perception != null and bernard.perception.sees_point(p.global_position)
	_seen_time = _seen_time + _d.get_process_delta_time() if sees else 0.0
	return OUT_SPOTTED if _seen_time >= _d.bal_f("patrulla.segundos_visto") else OUT_NONE


func _route_points() -> Array[Vector2]:
	var origin: Vector2 = _d.root.streamer.get_room_rect_px(_d.office_room()).position
	var out: Array[Vector2] = []
	for raw: Variant in _d.bal("patrulla.ruta"):
		var c: Array = raw
		var point: Vector2 = _d.root.streamer.nearest_walkable_point(origin + Vector2(float(c[0]), float(c[1])) * _d.cell())
		if point.is_finite():
			out.append(point)
	return out


func _after_miss(outcome: String) -> void:
	if outcome == OUT_SPOTTED:
		bernard.stop()
		bernard.face_point(_d.root.player.global_position)
		bernard.emote(NPCBubble.KIND_EXCLAIM, _d.budget("patrulla.reintento_segundos"))
		_d.speak(bernard.npc_id, Tutorial.line("TUT_LASKER_SPOTTED"))
		_d.sfx("ui_error")
	else:
		_d.toast("TUT_LASKER_MISSED", [], ToastStack.KIND_WARN)
	await _d.hold(_d.budget("patrulla.reintento_segundos"))
	_d.ui.set_note_hint(Tutorial.line("TUT_LASKER_AGAIN") + "\n" + Tutorial.line("TUT_TASK_HIDE_HINT",
			[Tutorial.keycaps(["interact"], _d.root.ui.is_touch_mode(), "TUT_TOUCH_INTERACT")]))


## Vuelve a su mesa y el personaje vuelve a su agenda (su nodo real reaparece; entonces se va el figurante).
func _return_bernard() -> void:
	if bernard == null or not is_instance_valid(bernard):
		return
	bernard.walk_to(_desk_of(bernard.npc_id))
	await _d.wait_for(func() -> bool: return not bernard.is_moving(), _d.budget("patrulla.segundos_vuelta"))
	_d.release_actor(bernard)
	bernard = null
	if _d.root.npc_layer != null:
		_d.root.npc_layer.sync_now()


func _desk_of(npc_id: String) -> Vector2:
	for seat: Dictionary in _d.root.streamer.get_seats_in_room(_d.office_room()):
		if str(seat.get("owner", "")) == npc_id:
			return seat["pos"]
	return _d.root.streamer.get_spawn_point(_d.office_room())


# ─── Despedida ────────────────────────────────────────────────

func _farewell() -> void:
	_task = -1
	_d.set_step("day_done")
	_d.ui.set_note_hint(Tutorial.line("TUT_DAY_DONE"))
	var guide: String = TutorialWalk.pick_guide()
	if not guide.is_empty():
		EventBus.phone_message_received.emit(guide, "TUT_PHONE_RATE", false)
	await _d.hold(_d.budget("tareas.presupuesto.despedida"))
