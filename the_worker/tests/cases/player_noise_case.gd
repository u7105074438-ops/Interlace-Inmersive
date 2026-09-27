# player_noise_case.gd — Cuerpo de test_player_noise: radios de ruido, cadencia, velocidades, esprint, agachado, actos.
# PROPIETARIO DE: nada.
# ESCUCHA: EventBus.noise_emitted (conexión temporal para contar pisadas).
extends TestCase

## Simula el Player a mano (step) con el stick virtual y comprueba:
##  · cada modo emite noise_emitted con el radio de balance.ruido y a cadencia de pisada;
##  · agachado y sigilo van más despacio que caminar; esprint más deprisa;
##  · TapDetector (doble pulsación) y CrouchInput (alternar / mantener);
##  · actos ilegales (begin_act/end_act), bloqueo de entrada, congelación al ser descubierto;
##  · stick analógico por acciones con intensidad (VirtualControls): inclinar poco = sigilo;
##  · doble clic quieto no arma el esprint; con la entrada bloqueada no se agacha;
##  · interacción: nunca a través de un muro (barrido en varias plantas reales) y sí en la sala;
##  · cámara: sigue en el paso físico sin interpolación;
##  · CharacterPainter: apariencias deterministas, combinaciones reservadas (también con la edad
##    por arquetipo), 23 nominados diseñados, sin vello facial en presentación "f", catálogo 8–12
##    fotogramas, tics de todos los arquetipos, caché de poses y dibujo de todas las poses.

const DT := 1.0 / 60.0
const SIM_STEPS := 180
const SPEED_EPS := 0.5
## Plantas del barrido de interacción (incluyen los casos del revisor: -2, -1, 3, 5, 10).
const SWEEP_FLOORS: Array[int] = [-2, -1, 3, 5, 10]
const SWEEP_STEP_CELLS := 0.4
const AGED_ROLLS := 3000
const AGED_ARCHETYPES: Array[String] = ["old_hand", "rookie", "burnout"]
const FEMININE_SAMPLE: Array[String] = ["Brenda Croft", "Diane Ashby", "Fiona Garrow", "Una Fenwick",
	"Irene Dunmore", "Wendy Jardine"]


## Lienzo de humo: dibuja todas las animaciones × escalones × direcciones × uniformes.
class PainterCanvas extends Node2D:
	var draws: int = 0

	func _draw() -> void:
		var dirs: Array[Vector2] = [Vector2.DOWN, Vector2(1, 1), Vector2.RIGHT, Vector2(1, -1), Vector2.UP]
		var uniforms: Array[String] = ["", "security", "cleaning", "maintenance", "factory"]
		var i: int = 0
		for anim: String in CharacterAnim.CATALOGUE:
			for tier: int in range(1, 9):
				var app: Dictionary = CharacterPainter.appearance_from_seed(i * 31 + tier, tier, false, "")
				app["uniform"] = uniforms[i % uniforms.size()]
				var pose: Dictionary = CharacterPainter.make_pose(anim, i % CharacterAnim.frame_count(anim),
						dirs[i % dirs.size()], {"tic": CharacterAnim.TICS[i % CharacterAnim.TICS.size()]})
				CharacterPainter.draw(self, app, tier, pose)
				i += 1
		for npc: NPCData in Database.get_all_named_npcs():
			var app2: Dictionary = CharacterPainter.appearance_for_named(npc, 1 + i % 8)
			CharacterPainter.draw(self, app2, 1 + i % 8, CharacterPainter.make_pose("walk", i % 8, dirs[i % 5]))
			CharacterPainter.draw_portrait(self, app2, Rect2(0, 0, 120, 140))
			i += 1
		draws += 1


var _noises: Array[Dictionary] = []


func run_case() -> void:
	check(new_run(), "database loaded")
	var player: Player = Player.new()
	player.with_camera = false
	add_child(player)
	player.set_physics_process(false)
	EventBus.noise_emitted.connect(_on_noise)
	_check_modes(player)
	_check_stick_sneak(player)
	_check_double_tap_input(player)
	_check_tap_detector()
	_check_crouch_input()
	_check_acts(player)
	_check_lock_and_caught(player)
	_check_stick_actions(player)
	_check_double_click(player)
	EventBus.noise_emitted.disconnect(_on_noise)
	player.queue_free()
	_check_appearances()
	_check_npc_appearances()
	_check_catalogue()
	await _check_drawing()
	_check_pose_cache()
	await _check_camera()
	await _check_wall_focus()


func _on_noise(position: Vector2, radius: float, source: String) -> void:
	_noises.append({"position": position, "radius": radius, "source": source})


## Deja al jugador quieto y sin estado de modo, en el origen.
func _reset(player: Player) -> void:
	player.set_virtual_input(Vector2.ZERO, false)
	player.set_sneak_held(false)
	player.set_crouching(false)
	player.set_dragging(false)
	player.set_input_locked(false)
	for i: int in 30:
		player.step(DT)
	player.position = Vector2.ZERO
	_noises.clear()


func _simulate(player: Player, steps: int) -> Array[float]:
	_noises.clear()
	for i: int in steps:
		player.step(DT)
	var radii: Array[float] = []
	for n: Dictionary in _noises:
		radii.append(float(n["radius"]))
	return radii


func _check_modes(player: Player) -> void:
	var expected: Dictionary = {
		"walk": Database.get_balance_float("ruido.radio_normal"),
		"sneak": Database.get_balance_float("ruido.radio_sigiloso"),
		"sprint": Database.get_balance_float("ruido.radio_esprint"),
		"crouch": Database.get_balance_float("ruido.radio_agachado"),
	}
	var counts: Dictionary = {}
	var speeds: Dictionary = {}
	for mode: String in expected:
		_reset(player)
		_enter_mode(player, mode)
		var radii: Array[float] = _simulate(player, SIM_STEPS)
		counts[mode] = radii.size()
		speeds[mode] = player.get_current_speed()
		check_eq(player.movement_mode(), mode, "movement_mode() reports '%s'" % mode)
		check(radii.size() > 0, "%s emits footstep noise" % mode)
		check(radii.size() < SIM_STEPS / 4, "%s noise at footstep cadence, not every frame (%d in %d frames)"
				% [mode, radii.size(), SIM_STEPS])
		check(radii.all(func(r: float) -> bool: return is_equal_approx(r, float(expected[mode]))),
				"%s noise radius = balance %.1f" % [mode, float(expected[mode])])
		check(_noises.all(func(n: Dictionary) -> bool: return n["source"] == Player.NOISE_SOURCE),
				"%s noise source is 'player'" % mode)
	_check_mode_relations(player, expected, counts, speeds)


func _enter_mode(player: Player, mode: String) -> void:
	match mode:
		"walk":
			player.set_virtual_input(Vector2.RIGHT, false)
		"sneak":
			player.set_sneak_held(true)
			player.set_virtual_input(Vector2.RIGHT, false)
		"sprint":
			player.set_virtual_input(Vector2.RIGHT, true)
		"crouch":
			player.set_crouching(true)
			player.set_virtual_input(Vector2.RIGHT, false)


func _check_mode_relations(player: Player, expected: Dictionary, counts: Dictionary, speeds: Dictionary) -> void:
	check(float(expected["sneak"]) < float(expected["walk"]) and float(expected["walk"]) < float(expected["sprint"]),
			"noise radii differ: sneak < walk < sprint")
	check(int(counts["sprint"]) > int(counts["walk"]) and int(counts["walk"]) > int(counts["sneak"]),
			"footstep cadence: sprint > walk > sneak")
	var cell: float = Database.get_balance_float("mundo.px_por_unidad")
	check_near(float(speeds["walk"]), Database.get_balance_float("jugador.velocidad_normal") * cell, SPEED_EPS,
			"walk speed = jugador.velocidad_normal cells/s")
	check_near(float(speeds["crouch"]), Database.get_balance_float("jugador.velocidad_agachado") * cell, SPEED_EPS,
			"crouch speed = jugador.velocidad_agachado cells/s")
	check(float(speeds["crouch"]) < float(speeds["walk"]), "crouching reduces speed")
	check(float(speeds["sneak"]) < float(speeds["walk"]), "sneaking is slower than walking")
	check(float(speeds["sprint"]) > float(speeds["walk"]), "sprinting is faster than walking")
	_reset(player)
	var still: Array[float] = _simulate(player, SIM_STEPS)
	check(still.is_empty() and player.is_still(), "standing still emits no noise")


func _check_stick_sneak(player: Player) -> void:
	_reset(player)
	player.set_virtual_input(Vector2.RIGHT * 0.3, false)
	_simulate(player, 30)
	check_eq(player.movement_mode(), Player.MODE_SNEAK, "a slightly tilted virtual stick sneaks (mobile)")
	_reset(player)
	player.set_dragging(true)
	player.set_virtual_input(Vector2.RIGHT, false)
	var radii: Array[float] = _simulate(player, SIM_STEPS)
	check(not radii.is_empty() and is_equal_approx(radii[0], Database.get_balance_float("ruido.radio_arrastre")),
			"dragging a body uses ruido.radio_arrastre")
	check(player.get_current_speed() < player.get_mode_speed(Player.MODE_WALK), "dragging a body is slow")


## Doble pulsación real a través de _unhandled_input + estado de Input.
func _check_double_tap_input(player: Player) -> void:
	_reset(player)
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "move_right"
	ev.pressed = true
	player._unhandled_input(ev)
	player.step(0.1)
	player._unhandled_input(ev)
	Input.action_press("move_right")
	_simulate(player, 30)
	check_eq(player.movement_mode(), Player.MODE_SPRINT, "double-tapping a direction sprints")
	Input.action_release("move_right")
	_simulate(player, 10)
	check(player.is_still(), "releasing the direction stops (and ends the sprint)")
	Input.action_press("move_right")
	_simulate(player, 30)
	check_eq(player.movement_mode(), Player.MODE_WALK, "after stopping, a single press walks again")
	Input.action_release("move_right")


## VirtualControls pulsa move_* con intensidad bruta ≥ su zona muerta: una sola zona muerta (la
## del jugador), respuesta monótona: poco = sigilo, mucho = caminar.
func _check_stick_actions(player: Player) -> void:
	var modes: Array[String] = []
	for strength: float in [0.2, 0.25, 0.35, 0.45, 0.8, 1.0]:
		_reset(player)
		Input.action_press("move_right", strength)
		_simulate(player, 20)
		modes.append(player.movement_mode())
		Input.action_release("move_right")
	check_eq(modes[1], Player.MODE_SNEAK, "Input.action_press(move_right, 0.25) sneaks (no double dead zone)")
	check(modes.slice(0, 4).all(func(m: String) -> bool: return m == Player.MODE_SNEAK),
			"light stick tilts 0.2-0.45 all sneak")
	check(modes[4] == Player.MODE_WALK and modes[5] == Player.MODE_WALK, "a full tilt walks (monotonic response)")
	_reset(player)


func _check_double_click(player: Player) -> void:
	_reset(player)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	player._unhandled_input(click)
	_simulate(player, 90)
	player.set_virtual_input(Vector2.RIGHT, false)
	_simulate(player, 20)
	check_eq(player.movement_mode(), Player.MODE_WALK, "a double-click while standing still does not arm a later sprint")
	player._unhandled_input(click)
	_simulate(player, 10)
	check_eq(player.movement_mode(), Player.MODE_SPRINT, "a double-click while moving sprints")
	_reset(player)
	player.set_input_locked(true)
	var ctrl: InputEventAction = InputEventAction.new()
	ctrl.action = "crouch"
	ctrl.pressed = true
	player._unhandled_input(ctrl)
	check(not player.is_crouching(), "Ctrl does not toggle crouch while input is locked (modal)")
	player.set_input_locked(false)
	_reset(player)


func _check_tap_detector() -> void:
	var window: float = Database.get_balance_float("jugador.ventana_doble_pulsacion")
	var taps: Player.TapDetector = Player.TapDetector.new(window)
	check(not taps.register("move_right", 0.0), "first tap is not a double tap")
	check(taps.register("move_right", window * 0.5), "second tap inside the window is a double tap")
	check(not taps.register("move_right", window * 0.6), "a third tap does not chain another double tap")
	check(not taps.register("move_left", 10.0), "new direction starts over")
	check(not taps.register("move_left", 10.0 + window * 1.5), "second tap outside the window is not a double tap")
	check(not taps.register("move_up", 20.0) and not taps.register("move_down", 20.0 + window * 0.2),
			"two different directions are not a double tap")


func _check_crouch_input() -> void:
	var hold: float = Database.get_balance_float("jugador.umbral_mantener_agachado")
	var crouch: Player.CrouchInput = Player.CrouchInput.new(hold)
	crouch.press(0.0)
	crouch.release(hold * 0.5)
	check(crouch.crouched, "short Ctrl press toggles crouch on")
	crouch.press(1.0)
	crouch.release(1.0 + hold * 0.5)
	check(not crouch.crouched, "second short press toggles crouch off")
	crouch.press(2.0)
	check(crouch.crouched, "holding Ctrl crouches")
	crouch.release(2.0 + hold * 2.0)
	check(not crouch.crouched, "releasing a held Ctrl stands up")


func _check_acts(player: Player) -> void:
	_reset(player)
	var finished: Array = []
	var on_finished: Callable = func(crime: String, completed: bool) -> void: finished.append([crime, completed])
	player.act_finished.connect(on_finished)
	player.begin_act("theft_small", 0.5)
	check_eq(player.current_act(), "theft_small", "current_act() during an act")
	_simulate(player, 20)
	check_eq(player.current_act(), "theft_small", "act still running before its duration")
	_simulate(player, 20)
	check_eq(player.current_act(), "", "timed act ends by itself")
	check(finished.size() == 1 and finished[0] == ["theft_small", true], "act_finished(theft_small, true)")
	player.begin_act("drawer_forced", 0.0)
	player.set_virtual_input(Vector2.RIGHT, false)
	_simulate(player, 5)
	check(player.current_act().is_empty() and finished.size() == 2 and finished[1] == ["drawer_forced", false],
			"moving interrupts an act (completed = false)")
	player.act_finished.disconnect(on_finished)


func _check_lock_and_caught(player: Player) -> void:
	_reset(player)
	player.set_input_locked(true)
	player.set_virtual_input(Vector2.RIGHT, true)
	var radii: Array[float] = _simulate(player, 60)
	check(radii.is_empty() and player.get_current_speed() == 0.0, "input lock (modal) stops movement and noise")
	player.set_input_locked(false)
	_reset(player)
	player.begin_act("theft_small", 5.0)
	EventBus.player_caught_redhanded.emit("npc_george_penn", "theft_small", 1)
	check_eq(player.current_act(), "", "being caught interrupts the act")
	player.set_virtual_input(Vector2.RIGHT, false)
	_simulate(player, 10)
	check(player.is_still(), "caught freeze keeps the player still")
	_reset(player)


func _check_appearances() -> void:
	var a: Dictionary = CharacterPainter.appearance_from_seed(777, 3, false, "")
	var b: Dictionary = CharacterPainter.appearance_from_seed(777, 3, false, "")
	check(a == b, "appearance_from_seed is deterministic")
	var ranges: Dictionary = {"build": 6, "head": 20, "hair": 25, "skin": 8, "palette": 12, "hair_color": 8}
	var ok: bool = true
	var reserved: Dictionary = {}
	for npc: NPCData in Database.get_all_named_npcs():
		var app: Dictionary = CharacterPainter.appearance_from_seed(npc.portrait_seed, 1, true, npc.unique_accessory)
		reserved["%d:%d:%d" % [app["head"], app["hair"], app["skin"]]] = true
	var clash: int = 0
	for seed: int in 600:
		var g: Dictionary = CharacterPainter.appearance_from_seed(seed * 13 + 5, 1 + seed % 8, false, "")
		for key: String in ranges:
			ok = ok and int(g[key]) >= 0 and int(g[key]) < int(ranges[key])
		ok = ok and CharacterStyle.ACCESSORIES.has(g["accessory"])
		if reserved.has("%d:%d:%d" % [g["head"], g["hair"], g["skin"]]):
			clash += 1
	check(ok, "every §14.4 layer stays inside its variant count")
	check_eq(clash, 0, "generic characters never reuse a named character's reserved combination")
	var harlan: NPCData = Database.get_named_npc("npc_harlan_voss")
	var big: Dictionary = CharacterPainter.appearance_for_named(harlan, 8)
	check(float(big["volume"]) > 1.0, "Harlan Voss has the largest silhouette volume")
	check_eq(CharacterPainter.uniform_for_disguise("uniform_cleaning"), "cleaning",
			"disguise id maps to the uniform layer")


## NPC en ejecución (NPCDirector): la edad por arquetipo nunca cae en una combinación reservada y
## los nombres de pila femeninos no llevan vello facial.
func _check_npc_appearances() -> void:
	var reserved: Dictionary = CharacterPainter.reserved_combos()
	var clash: int = 0
	var beards: int = 0
	for i: int in AGED_ROLLS:
		var npc: NPCRuntime = NPCRuntime.new()
		npc.portrait_seed = 100000 + i * 97
		npc.archetype = AGED_ARCHETYPES[i % AGED_ARCHETYPES.size()]
		npc.tier = 1 + i % 8
		npc.name = FEMININE_SAMPLE[i % FEMININE_SAMPLE.size()] if i % 2 == 0 else "Gordon Croft"
		var app: Dictionary = CharacterPainter.appearance_for_npc(npc)
		if reserved.has("%d:%d:%d" % [app["head"], app["hair"], app["skin"]]):
			clash += 1
		if i % 2 == 0 and not str(CharacterStyle.HAIRS[int(app["hair"])][1]).is_empty():
			beards += 1
	check_eq(clash, 0, "appearance_for_npc (aged generics) never reuses a named combination")
	check_eq(beards, 0, "generic NPCs with feminine first names never get facial hair")
	var designed: bool = true
	for npc_data: NPCData in Database.get_all_named_npcs():
		designed = designed and CharacterPainter.NAMED_LOOKS.has(npc_data.unique_accessory)
	check(designed and CharacterPainter.NAMED_LOOKS.size() == Database.get_all_named_npcs().size(),
			"all named NPCs have a designed look (NAMED_LOOKS)")
	var claudia: NPCData = Database.get_named_npc("npc_claudia_reeves")
	var look: Dictionary = CharacterPainter.appearance_for_named(claudia, 1)
	check(str(CharacterStyle.HAIRS[int(look["hair"])][1]).is_empty() and str(look["presentation"]) == "f",
			"Claudia Reeves has no beard")


func _check_catalogue() -> void:
	var ok: bool = true
	for anim: String in CharacterAnim.CATALOGUE:
		var n: int = CharacterAnim.frame_count(anim)
		ok = ok and n >= 8 and n <= 12
	check(ok, "every animation cycle has 8-12 key frames (§14.7)")
	var tics_ok: bool = true
	for arch: ArchetypeData in Database.get_all_archetypes():
		tics_ok = tics_ok and CharacterAnim.TICS.has(arch.visual_tic)
	check(tics_ok, "every archetype visual_tic has a painter hook (§14.6)")
	check(CharacterPainter.anim_fps("walk") > 0.0, "animation fps comes from balance (animacion.fps_base)")


## La segunda vez que se dibuja una pose no se vuelve a grabar (caché de CharacterPainter).
func _check_pose_cache() -> void:
	CharacterPainter.clear_cache()
	var app: Dictionary = CharacterPainter.appearance_from_seed(4242, 5, false, "")
	var pose: Dictionary = CharacterPainter.make_pose("walk", 3, Vector2(1, 0.2))
	var first: CharacterCanvas = CharacterPainter.pose_recording(app, 5, pose)
	var again: CharacterCanvas = CharacterPainter.pose_recording(app.duplicate(), 5, pose)
	check(first == again and CharacterPainter.cached_pose_count() == 1, "a repeated pose replays the cached recording")
	check(first.size() > 0, "a recorded pose has draw commands")
	var other: CharacterCanvas = CharacterPainter.pose_recording(app, 5, CharacterPainter.make_pose("walk", 4, Vector2.RIGHT))
	check(other != first and CharacterPainter.cached_pose_count() == 2, "a different key frame records its own pose")


func _check_camera() -> void:
	var holder: Node2D = Node2D.new()
	add_child(holder)
	var cam: PlayerCamera = PlayerCamera.new()
	holder.add_child(cam)
	await wait_frames(1)
	var interpolated: bool = get_tree().is_physics_interpolation_enabled()
	check(cam.is_physics_processing() != interpolated and cam.is_processing() == interpolated,
			"the camera follows on the physics tick (no jitter against move_and_slide)")
	holder.queue_free()


func _check_drawing() -> void:
	var canvas: PainterCanvas = PainterCanvas.new()
	add_child(canvas)
	canvas.queue_redraw()
	await wait_frames(3)
	check(canvas.draws > 0, "all poses x tiers x directions x uniforms + named + portraits draw without errors")
	canvas.queue_free()


# ─── Interacción a través de muros ─────────────────────────────

## Barrido en plantas reales: desde cualquier punto libre de muros, el objeto enfocado nunca
## tiene un muro (rectángulos de la capa 1) entre el jugador y él; y cada objeto se enfoca
## desde su propia sala.
func _check_wall_focus(floors: Array[int] = SWEEP_FLOORS) -> void:
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	var player: Player = Player.new()
	player.with_camera = false
	streamer.get_actor_layer().add_child(player)
	player.set_physics_process(false)
	var through: Array[String] = []
	var unreachable: Array[String] = []
	for floor_number: int in floors:
		streamer.load_floor(floor_number)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var walls: Array[Rect2] = _wall_rects(streamer)
		for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
			var item: Interactable = node as Interactable
			if item != null and item.is_available():
				_sweep_item(player, item, walls, through, unreachable)
	check(through.is_empty(), "no interactable is focused through a wall (%d found%s)"
			% [through.size(), "" if through.is_empty() else ": " + ", ".join(through.slice(0, 4))])
	check(unreachable.is_empty(), "every interactable can be focused from inside its own room (%d not%s)"
			% [unreachable.size(), "" if unreachable.is_empty() else ": " + ", ".join(unreachable.slice(0, 4))])
	player.queue_free()
	streamer.queue_free()


func _sweep_item(player: Player, item: Interactable, walls: Array[Rect2], through: Array[String],
		unreachable: Array[String]) -> void:
	var reach: float = Database.get_balance_float("mundo.radio_uso_interactivo") * item.cell_px
	var step: float = item.cell_px * SWEEP_STEP_CELLS
	var reached_inside: bool = false
	var n: int = int(reach / step)
	for gx: int in range(-n, n + 1):
		for gy: int in range(-n, n + 1):
			var p: Vector2 = item.global_position + Vector2(gx, gy) * step
			if p.distance_to(item.global_position) > reach * 0.98 or _inside_any(p, walls):
				continue
			player.global_position = p
			if player._pick_focus() != item:
				continue
			if _segment_hits(p, item.global_position, walls):
				through.append("%s@%s" % [item.interact_id, item.room_id])
				return
			reached_inside = reached_inside or FloorStreamer.find_in(get_tree()).get_room_at(p) == item.room_id
	if not reached_inside and not _focused_from_own_room(player, item):
		unreachable.append(item.interact_id)


## Desde la propia sala, pegado al objeto (hacia el centro de la sala), el objeto es enfocable
## salvo que otro esté aún más cerca.
func _focused_from_own_room(player: Player, item: Interactable) -> bool:
	var streamer: FloorStreamer = FloorStreamer.find_in(get_tree())
	var center: Vector2 = streamer.get_room_rect_px(item.room_id).get_center()
	player.global_position = item.global_position + (center - item.global_position).limit_length(item.cell_px * 0.3)
	var focus: Node2D = player._pick_focus()
	return focus == item or (focus != null and focus.global_position.distance_to(player.global_position)
			<= item.global_position.distance_to(player.global_position))


func _wall_rects(streamer: FloorStreamer) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for body: Node in streamer.find_children("Walls", "StaticBody2D", true, false):
		for shape_node: Node in body.get_children():
			var cs: CollisionShape2D = shape_node as CollisionShape2D
			if cs != null and cs.shape is RectangleShape2D:
				var size: Vector2 = (cs.shape as RectangleShape2D).size
				out.append(Rect2(cs.global_position - size * 0.5, size))
	return out


func _inside_any(p: Vector2, rects: Array[Rect2]) -> bool:
	for r: Rect2 in rects:
		if r.grow(2.0).has_point(p):
			return true
	return false


## ¿El segmento a→b cruza algún muro? (independiente del rayo físico que usa el jugador)
func _segment_hits(a: Vector2, b: Vector2, rects: Array[Rect2]) -> bool:
	for r: Rect2 in rects:
		var box: Rect2 = r.grow(-0.5)
		if box.has_point(a) or box.has_point(b):
			return true
		var corners: Array[Vector2] = [box.position, Vector2(box.end.x, box.position.y), box.end,
				Vector2(box.position.x, box.end.y)]
		for i: int in 4:
			if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
				return true
	return false
