# player.gd — El jugador: 8 direcciones, sigilo/esprint/agachado, pasos que hacen ruido, interacción y actos.
# PROPIETARIO DE: el estado de desplazamiento del jugador (modo, orientación, acto en curso, bloqueo, animación).
# ESCUCHA: EventBus.occupation_changed, EventBus.disguise_changed, EventBus.player_caught_redhanded, EventBus.floor_changed, EventBus.run_started, EventBus.run_loaded.
class_name Player
extends CharacterBody2D

## Manual PASO 8, §13.7, §14.5, §14.7; contrato BUILD_NOTES §14 (Player).
## · Velocidades en celdas/s (jugador.velocidad_*) × mundo.px_por_unidad.
## · Ruido: cada pisada emite EventBus.noise_emitted(posición en px, radio en METROS = celdas de
##   ruido.radio_*, "player"). La reducción por máscara acústica la aplica quien escucha.
## · Esprint = doble pulsación de una dirección dentro de jugador.ventana_doble_pulsacion o doble
##   clic (ratón real, no el emulado desde el táctil) con una dirección pulsada; dura mientras haya
##   movimiento. Agacharse (Ctrl): pulsación corta alterna, mantener agacha. Con la entrada
##   bloqueada (modal) no se leen pulsaciones.
## · Móvil: set_virtual_input(dir, sprint) o las acciones move_* con intensidad (VirtualControls);
##   inclinar poco el stick (< jugador.umbral_stick_sigilo) es desplazamiento sigiloso.
## · Interacción (E): el Interactable más cercano dentro de su radio de uso y sin muro de por
##   medio (misma sala según FloorStreamer, o un rayo a la capa física 1 despejado).

signal interaction_focus_changed(interactable: Node, prompt_key: String)
signal act_finished(crime_type: String, completed: bool)
signal footstep_taken(mode: String, radius: float)
signal hiding_changed(hidden: bool)

const MODE_STILL := "still"
## Tipo de interactivo de un personaje (prioridad de foco sobre muebles).
const NPC_INTERACT_TYPE := "npc"
const MODE_WALK := "walk"
const MODE_SNEAK := "sneak"
const MODE_SPRINT := "sprint"
const MODE_CROUCH := "crouch"
const GAIT_DRAG := "drag"
const NOISE_SOURCE := "player"
const GROUP := "player"
const INTERACTABLE_GROUP := "interactables"
const UI_GROUP := "ui_root"
const ROUTER_GROUP := "interaction_router"
const ROUTER_SCRIPT := "res://src/world/interaction_router.gd"
const ROUTER_METHOD := "interact"
const SPRINT_ACTION := "sprint"
const LAYER_PLAYER := 4
const LAYER_WALLS := 1
const MASK_LAYERS: Array[int] = [1, 2, 3]
## Tope de la caché de radios de uso (se vacía al cambiar de planta o al llenarse).
const REACH_CACHE_MAX := 2048
## get_vector sin zona muerta propia: la aplica el jugador (jugador.zona_muerta_stick) una sola vez.
const RAW_DEADZONE := 0.0
const MOVE_ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
const CELL_PATH := "mundo.px_por_unidad"
const SEED_PATH := "jugador.semilla_apariencia"
const PORTRAIT_FLAG := "player.portrait_seed"
const SPEED_PATHS: Dictionary = {
	"walk": "jugador.velocidad_normal", "sneak": "jugador.velocidad_sigilo",
	"sprint": "jugador.velocidad_esprint", "crouch": "jugador.velocidad_agachado",
	"drag": "jugador.velocidad_arrastre",
}
const STEP_PATHS: Dictionary = {
	"walk": "jugador.intervalo_paso_normal", "sneak": "jugador.intervalo_paso_sigilo",
	"sprint": "jugador.intervalo_paso_esprint", "crouch": "jugador.intervalo_paso_agachado",
	"drag": "jugador.intervalo_paso_arrastre",
}
const NOISE_PATHS: Dictionary = {
	"walk": "ruido.radio_normal", "sneak": "ruido.radio_sigiloso", "sprint": "ruido.radio_esprint",
	"crouch": "ruido.radio_agachado", "drag": "ruido.radio_arrastre",
}
## Animación de cada acto ilegal (crime types de BUILD_NOTES §11). Por defecto: "drawer".
const ACT_ANIMS: Dictionary = {
	"theft_small": "steal", "theft_product": "steal", "burglary": "steal", "framing": "steal",
	"idea_stolen": "steal", "drawer_forced": "drawer", "lock_forced": "drawer",
	"sabotage": "drawer", "power_cut": "drawer", "file_copied": "sit_type", "forgery": "sit_type",
	"footage_deleted": "sit_type", "records_deleted": "sit_type", "fraud": "sit_type",
	"insider_trade": "phone", "rumour_planted": "chat", "bribe": "bribe", "body_moved": "drag",
	"trespass": "sneak", "elimination": "drawer",
}
const DEFAULT_ACT_ANIM := "drawer"
## Presentación: transparencia al esconderse; la primera pisada llega a media cadencia.
const HIDDEN_ALPHA := 0.6
const FIRST_STEP_PHASE := 0.5
const MOVE_ANIMS: Dictionary = {
	"walk": "walk", "sneak": "sneak", "sprint": "sprint", "crouch": "crouch", "drag": "drag",
}


## Detección de doble pulsación de una misma dirección (esprint, §13.7).
class TapDetector extends RefCounted:
	var window: float = 0.0
	var _last_action: String = ""
	var _last_time: float = 0.0

	func _init(window_seconds: float) -> void:
		window = window_seconds

	## Registra una pulsación en el instante `time`; true si completa una doble pulsación.
	func register(action: String, time: float) -> bool:
		var is_double: bool = action == _last_action and time - _last_time <= window
		_last_action = "" if is_double else action
		_last_time = time
		return is_double


## Ctrl: una pulsación corta alterna; mantenerla más de `hold_threshold` agacha solo mientras dure.
class CrouchInput extends RefCounted:
	var hold_threshold: float = 0.0
	var crouched: bool = false
	var _pressed_at: float = -1.0

	func _init(threshold: float) -> void:
		hold_threshold = threshold

	func press(time: float) -> void:
		if crouched:
			crouched = false
			_pressed_at = -1.0
			return
		crouched = true
		_pressed_at = time

	func release(time: float) -> void:
		if _pressed_at >= 0.0 and time - _pressed_at > hold_threshold:
			crouched = false
		_pressed_at = -1.0


## Indicación contextual flotante ("[E] Abrir cajón") si UIRoot no ofrece la suya.
class PromptBubble extends Node2D:
	const FONT_SIZE := 15
	const PAD := Vector2(8, 5)
	const KEY_GAP := 6.0
	var text: String = ""
	var key_label: String = ""

	func _draw() -> void:
		if text.is_empty():
			return
		var font: Font = ThemeDB.fallback_font
		var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var key_w: float = 0.0 if key_label.is_empty() else \
				font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD.x * 2.0
		var size: Vector2 = Vector2(text_w + key_w + PAD.x * 2.0 + (KEY_GAP if key_w > 0.0 else 0.0),
				FONT_SIZE + PAD.y * 2.0)
		var box: Rect2 = Rect2(Vector2(-size.x * 0.5, -size.y), size)
		draw_rect(box.grow(2.0), CharacterStyle.OUTLINE)
		draw_rect(box, Color("#fbfbf7"))
		var x: float = box.position.x + PAD.x
		if key_w > 0.0:
			draw_rect(Rect2(Vector2(x, box.position.y + 3.0), Vector2(key_w, size.y - 6.0)), CharacterStyle.OUTLINE)
			draw_string(font, Vector2(x + PAD.x, box.end.y - PAD.y - 2.0), key_label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
			x += key_w + KEY_GAP
		draw_string(font, Vector2(x, box.end.y - PAD.y - 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				FONT_SIZE, CharacterStyle.OUTLINE)


## Si es false, el Player no crea su PlayerCamera (la escena de juego pone la suya).
@export var with_camera: bool = true

var _appearance: Dictionary = {}
var _tier: int = 1
var _disguise: String = ""
var _mode: String = MODE_STILL
var _facing: Vector2 = Vector2.DOWN
var _clock: float = 0.0
var _taps: TapDetector = null
var _crouch: CrouchInput = null
var _sprint_latched: bool = false
var _sprint_latched_at: float = 0.0
var _sneak_held: bool = false
var _virtual_dir: Vector2 = Vector2.ZERO
var _virtual_sprint: bool = false
var _input_locked: bool = false
## Integración (game_root): dueños del bloqueo de entrada (UIRoot = "", trayectos, sueño, fin de
## partida). Cerrar una ventana durante un trayecto ya no desbloquea al jugador antes de tiempo.
var _lock_owners: Dictionary = {}
var _dragging: bool = false
var _hiding: bool = false
var _freeze_left: float = 0.0
var _act: String = ""
var _act_left: float = 0.0
var _act_timed: bool = false
## Blanco del acto (npc_id): su propia percepción no lo cuenta como testigo (p. ej. eliminar).
var _act_target: String = ""
var _anim: String = "idle"
var _override_anim: String = ""
var _frame: int = 0
var _anim_clock: float = 0.0
var _step_clock: float = 0.0
var _step_count: int = 0
var _focus: Node2D = null
var _reach_cache: Dictionary = {}
var _bubble: PromptBubble = null
var _camera: PlayerCamera = null
var _cell: float = 0.0
var _tun: Dictionary = {}
static var _router_script: Script = null


func _ready() -> void:
	add_to_group(GROUP)
	InputSetup.register_actions()
	_load_tunables()
	_setup_physics()
	_setup_children()
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.disguise_changed.connect(_on_disguise_changed)
	EventBus.player_caught_redhanded.connect(_on_caught)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.run_started.connect(func(_seed: int) -> void: _refresh_appearance())
	EventBus.run_loaded.connect(func(_day: int) -> void: _refresh_appearance())
	_refresh_appearance()


func _load_tunables() -> void:
	_cell = Database.get_balance_float(CELL_PATH)
	for key: String in SPEED_PATHS:
		_tun["speed_" + key] = Database.get_balance_float(SPEED_PATHS[key]) * _cell
		_tun["step_" + key] = Database.get_balance_float(STEP_PATHS[key])
		_tun["noise_" + key] = Database.get_balance_float(NOISE_PATHS[key])
	_tun["accel"] = Database.get_balance_float("jugador.aceleracion") * _cell
	_tun["stick_sneak"] = Database.get_balance_float("jugador.umbral_stick_sigilo")
	_tun["dead_zone"] = Database.get_balance_float("jugador.zona_muerta_stick")
	_tun["reach"] = Database.get_balance_float("jugador.radio_interaccion") * _cell
	_tun["freeze"] = Database.get_balance_float("jugador.duracion_congelacion")
	_tun["tap_window"] = Database.get_balance_float("jugador.ventana_doble_pulsacion")
	_tun["use_radius"] = Database.get_balance_float("mundo.radio_uso_interactivo")
	_taps = TapDetector.new(float(_tun["tap_window"]))
	_crouch = CrouchInput.new(Database.get_balance_float("jugador.umbral_mantener_agachado"))


func _setup_physics() -> void:
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(LAYER_PLAYER, true)
	for layer: int in MASK_LAYERS:
		set_collision_mask_value(layer, true)
	motion_mode = MOTION_MODE_FLOATING
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = Database.get_balance_float("jugador.radio_colision") * _cell
	shape.shape = circle
	shape.name = "Collision"
	add_child(shape)


func _setup_children() -> void:
	_bubble = PromptBubble.new()
	_bubble.name = "PromptBubble"
	_bubble.top_level = true
	_bubble.z_as_relative = false
	_bubble.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	add_child(_bubble)
	if with_camera:
		_camera = PlayerCamera.new()
		_camera.name = "Camera"
		_camera.target = self
		add_child(_camera)


# ─── API pública (BUILD_NOTES §14) ─────────────────────────────

## "sneak" | "walk" | "sprint" | "crouch" | "still" (arrastrando un cuerpo cuenta como "walk").
func movement_mode() -> String:
	return _mode


## Ctrl alternado/mantenido (CrouchInput) o el botón táctil que mantiene la acción "crouch".
func is_crouching() -> bool:
	if _crouch == null:
		return false
	return _crouch.crouched or (InputMap.has_action("crouch") and Input.is_action_pressed("crouch"))


func is_sprinting() -> bool:
	return _mode == MODE_SPRINT


func is_sneaking() -> bool:
	return _mode == MODE_SNEAK


func is_still() -> bool:
	return _mode == MODE_STILL


func is_dragging() -> bool:
	return _dragging


func is_hiding() -> bool:
	return _hiding


## Tipo de delito que se está ejecutando ("" si ninguno). Lo consulta Perception (flagrancia).
func current_act() -> String:
	return _act


## npc_id del blanco del acto en curso ("" si ninguno). Perception lo ignora como observador.
func current_act_target() -> String:
	return _act_target


## Empieza un acto ilegal: inmoviliza al jugador y reproduce su animación. `seconds` <= 0 =
## hasta end_act(). Moverse lo interrumpe (act_finished(crime_type, false)). `target` = npc_id blanco.
func begin_act(crime_type: String, seconds: float, target: String = "") -> void:
	if not _act.is_empty():
		_finish_act(false)
	_act = crime_type
	_act_target = target
	_act_timed = seconds > 0.0
	_act_left = seconds
	velocity = Vector2.ZERO
	play_anim(str(ACT_ANIMS.get(crime_type, DEFAULT_ACT_ANIM)))


## Termina el acto en curso con éxito (act_finished(crime_type, true)).
func end_act() -> void:
	_finish_act(true)


## `owner` (integración): cada sistema bloquea con su nombre; la entrada vuelve cuando nadie bloquea.
func set_input_locked(locked: bool, owner: String = "") -> void:
	if locked:
		_lock_owners[owner] = true
	else:
		_lock_owners.erase(owner)
	_input_locked = not _lock_owners.is_empty()
	if _input_locked:
		velocity = Vector2.ZERO
		_sprint_latched = false
		_virtual_dir = Vector2.ZERO


func is_input_locked() -> bool:
	return _input_locked


## Dirección de mirada (8 direcciones, normalizada).
func get_facing() -> Vector2:
	return _facing


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() > 0.0:
		_facing = _snap8(dir)
		queue_redraw()


## Reproduce una animación del catálogo §14.7 ("" vuelve a la locomoción). Las de un solo ciclo
## terminan solas; "caught" y las de `hold` se quedan en su última pose hasta otra orden.
func play_anim(anim_name: String) -> void:
	_override_anim = anim_name if CharacterAnim.has_anim(anim_name) else ""
	_set_anim(_override_anim if not _override_anim.is_empty() else _base_anim())


## Stick virtual de Android (UI móvil). `dir` con módulo 0..1; `sprint` = doble toque del stick.
func set_virtual_input(dir: Vector2, sprint: bool) -> void:
	_virtual_dir = dir.limit_length(1.0)
	_virtual_sprint = sprint


## Botón de sigilo (tests y controles táctiles).
func set_sneak_held(held: bool) -> void:
	_sneak_held = held


## Agacharse/levantarse directamente (botón táctil, tests).
func set_crouching(crouched: bool) -> void:
	_crouch.crouched = crouched
	queue_redraw()


func set_dragging(dragging: bool) -> void:
	_dragging = dragging


## Escondido en un escondite: el InteractionRouter lo activa; moverse lo desactiva.
func set_hiding(hidden: bool) -> void:
	if _hiding == hidden:
		return
	_hiding = hidden
	velocity = Vector2.ZERO
	modulate.a = HIDDEN_ALPHA if hidden else 1.0
	_set_anim(_base_anim())
	hiding_changed.emit(hidden)


func get_focused_interactable() -> Node2D:
	return _focus if is_instance_valid(_focus) else null


## Interactúa con el objeto enfocado (tecla E o botón contextual). true si se despachó.
func try_interact() -> bool:
	if not _can_act() or _focus == null or not is_instance_valid(_focus):
		return false
	var router: Object = _find_router()
	if router != null:
		router.call(ROUTER_METHOD, _focus, self)
		return true
	if _focus.has_method(ROUTER_METHOD):
		_focus.call(ROUTER_METHOD, self)
		return true
	return false


func get_tier() -> int:
	return _tier


func get_appearance() -> Dictionary:
	return _appearance.duplicate()


## Velocidad actual en px/s.
func get_current_speed() -> float:
	return velocity.length()


## Velocidad objetivo (px/s) de un modo o paso ("walk", "sneak", "sprint", "crouch", "drag").
func get_mode_speed(gait: String) -> float:
	return float(_tun.get("speed_" + gait, 0.0))


## Radio de ruido (metros) de una pisada en ese modo o paso.
func get_mode_noise(gait: String) -> float:
	return float(_tun.get("noise_" + gait, 0.0))


# ─── Entrada ───────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _can_move():
		if event.is_action_released("crouch"):
			_crouch.release(_clock)
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		var real_mouse: bool = mouse.device != InputEvent.DEVICE_ID_EMULATION
		if real_mouse and mouse.double_click and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed \
				and _read_direction() != Vector2.ZERO:
			_latch_sprint()
		return
	if event.is_echo():
		return
	for action: String in MOVE_ACTIONS:
		if event.is_action_pressed(action) and _taps.register(action, _clock):
			_latch_sprint()
	if event.is_action_pressed("crouch"):
		_crouch.press(_clock)
	elif event.is_action_released("crouch"):
		_crouch.release(_clock)
	if event.is_action_pressed("interact") and try_interact():
		get_viewport().set_input_as_handled()


## El esprint armado caduca si no empieza a moverse dentro de la ventana de doble pulsación.
func _latch_sprint() -> void:
	_sprint_latched = true
	_sprint_latched_at = _clock


## Stick virtual, o teclas/stick por acciones move_* con su intensidad bruta (una sola zona muerta).
func _read_direction() -> Vector2:
	var dead: float = float(_tun["dead_zone"])
	if _virtual_dir.length() > dead:
		return _virtual_dir
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down", RAW_DEADZONE)
	return dir if dir.length() > dead else Vector2.ZERO


## Shift o botón de sigilo; con stick analógico (táctil o mando), inclinarlo poco también.
func _wants_sneak(dir: Vector2) -> bool:
	if _sneak_held or Input.is_action_pressed("sneak"):
		return true
	return dir.length() > float(_tun["dead_zone"]) and dir.length() < float(_tun["stick_sneak"])


## Esprint: doble pulsación/doble clic, stick virtual o la acción "sprint" de VirtualControls.
func _wants_sprint() -> bool:
	if _sprint_latched or _virtual_sprint:
		return true
	return InputMap.has_action(SPRINT_ACTION) and Input.is_action_pressed(SPRINT_ACTION)


# ─── Simulación ────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	step(delta)


## Un paso de simulación de `delta` segundos (lo llama _physics_process; los tests, a mano).
func step(delta: float) -> void:
	_clock += delta
	_tick_timers(delta)
	var dir: Vector2 = _read_direction() if _can_move() else Vector2.ZERO
	if dir != Vector2.ZERO and (_hiding or not _act.is_empty()):
		set_hiding(false)
		_finish_act(false)
	if not _act.is_empty() or _freeze_left > 0.0:
		dir = Vector2.ZERO
	_update_mode(dir)
	_apply_velocity(dir, delta)
	_update_footsteps(delta)
	_update_animation(delta)
	_update_focus()


func _tick_timers(delta: float) -> void:
	_freeze_left = maxf(0.0, _freeze_left - delta)
	if _act_timed and not _act.is_empty():
		_act_left -= delta
		if _act_left <= 0.0:
			_finish_act(true)


func _can_move() -> bool:
	return not _input_locked and not _ui_blocks_input()


func _can_act() -> bool:
	return _can_move() and _act.is_empty() and _freeze_left <= 0.0


func _ui_blocks_input() -> bool:
	var ui: Node = get_tree().get_first_node_in_group(UI_GROUP)
	return ui != null and ui.has_method("has_modal") and bool(ui.call("has_modal"))


func _update_mode(dir: Vector2) -> void:
	var was_moving: bool = _mode != MODE_STILL
	if dir == Vector2.ZERO:
		_mode = MODE_STILL
		if was_moving or _clock - _sprint_latched_at > float(_tun["tap_window"]):
			_sprint_latched = false
		return
	_facing = _snap8(dir)
	if is_crouching():
		_mode = MODE_CROUCH
	elif _dragging:
		_mode = MODE_WALK
	elif _wants_sneak(dir):
		_mode = MODE_SNEAK
	elif _wants_sprint():
		_mode = MODE_SPRINT
	else:
		_mode = MODE_WALK
	if not was_moving:
		_step_clock = _step_interval() * FIRST_STEP_PHASE
		_step_count = 0


## Modo de paso para velocidad, cadencia, ruido y animación ("drag" al arrastrar un cuerpo).
func _gait() -> String:
	if _dragging and _mode != MODE_CROUCH and _mode != MODE_STILL:
		return GAIT_DRAG
	return _mode


func _apply_velocity(dir: Vector2, delta: float) -> void:
	var target: Vector2 = Vector2.ZERO
	if _mode != MODE_STILL:
		target = dir.normalized() * float(_tun["speed_" + _gait()])
	velocity = velocity.move_toward(target, float(_tun["accel"]) * delta)
	if velocity != Vector2.ZERO and is_inside_tree():
		move_and_slide()


func _step_interval() -> float:
	return maxf(float(_tun.get("step_" + _gait(), 0.0)), 0.01)


## Pisadas a la cadencia del modo (no cada fotograma): cada una emite noise_emitted.
func _update_footsteps(delta: float) -> void:
	if _mode == MODE_STILL:
		_step_clock = 0.0
		return
	_step_clock += delta
	var interval: float = _step_interval()
	if _step_clock < interval:
		return
	_step_clock -= interval
	_step_count += 1
	var gait: String = _gait()
	var radius: float = float(_tun["noise_" + gait])
	EventBus.noise_emitted.emit(global_position, radius, NOISE_SOURCE)
	footstep_taken.emit(gait, radius)


# ─── Animación y dibujo ────────────────────────────────────────

func _base_anim() -> String:
	if _hiding:
		return "hide"
	if _mode != MODE_STILL:
		return str(MOVE_ANIMS[_gait()])
	if is_crouching():
		return "crouch_idle"
	return "idle"


func _set_anim(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	_frame = 0
	_anim_clock = 0.0
	queue_redraw()


func _update_animation(delta: float) -> void:
	if _mode != MODE_STILL and _act.is_empty():
		_override_anim = ""
	_set_anim(_override_anim if not _override_anim.is_empty() else _base_anim())
	var previous: int = _frame
	if CharacterAnim.is_locomotion(_anim) and _mode != MODE_STILL:
		_frame = _locomotion_frame()
	else:
		_advance_clip(delta)
	if _frame != previous:
		queue_redraw()


## Fotograma sincronizado con las pisadas: cada pisada cae en un fotograma de contacto.
func _locomotion_frame() -> int:
	var n: int = CharacterAnim.frame_count(_anim)
	var contacts: Array = CharacterAnim.contact_frames(_anim)
	var first: int = int(contacts[0]) if not contacts.is_empty() else 0
	var phase: float = (float(_step_count % 2) + _step_clock / _step_interval()) * 0.5
	return (int(phase * float(n)) + first) % n


func _advance_clip(delta: float) -> void:
	var fps: float = CharacterPainter.anim_fps(_anim)
	if fps <= 0.0:
		return
	_anim_clock += delta
	while _anim_clock >= 1.0 / fps:
		_anim_clock -= 1.0 / fps
		var next: int = CharacterAnim.next_frame(_anim, _frame)
		if next < 0:
			_override_anim = ""
			_set_anim(_base_anim())
			return
		_frame = next


func _draw() -> void:
	var pose: Dictionary = CharacterPainter.make_pose(_anim, _frame, _facing)
	CharacterPainter.draw(self, _appearance, _tier, pose)


static func _snap8(dir: Vector2) -> Vector2:
	var octant: float = roundf(dir.angle() / (PI / 4.0))
	return Vector2.from_angle(octant * PI / 4.0)


# ─── Interacción ───────────────────────────────────────────────

func _update_focus() -> void:
	if not is_instance_valid(_focus):
		_focus = null
	var best: Node2D = _pick_focus() if _can_act() else null
	if best != _focus:
		_set_focus_flag(_focus, false)
		_focus = best
		_set_focus_flag(_focus, true)
		_refresh_prompt()


## El más cercano dentro de su radio de uso y sin muro de por medio (solo se lanza un rayo
## para los candidatos que mejorarían el actual).
func _pick_focus() -> Node2D:
	var here: String = _current_room()
	var best: Node2D = null
	var best_d: float = INF
	var best_tier: int = -1
	for node: Node in get_tree().get_nodes_in_group(INTERACTABLE_GROUP):
		var item: Node2D = node as Node2D
		if item == null:
			continue
		# Prioridad: trayecto (salida, torniquete, ascensor…) > personaje > resto. Un personaje gana
		# a cajones y objetos (E para hablar nunca fuerza un cajón por accidente), pero la multitud
		# de la hora punta no tapa la puerta (§5.6): quien está en la salida sale.
		var tier: int = _focus_tier(item)
		var d: float = global_position.distance_to(item.global_position)
		if tier < best_tier or (tier == best_tier and d >= best_d):
			continue
		if d > _reach_of(item) or not _is_available(item) or not _no_wall_between(item, here):
			continue
		best = item
		best_d = d
		best_tier = tier
	return best


func _focus_tier(item: Node2D) -> int:
	var interactable: Interactable = item as Interactable
	if interactable == null:
		return 0
	if interactable.interact_type == FloorTravel.COMMUTE_TYPE \
			or (FloorTravel.TYPE_KINDS.has(interactable.interact_type)
				and not FloorTravel.ACT_KINDS.has(FloorTravel.kind_of(interactable))) \
			or interactable.interact_type.contains("turnstile"):
		return 2
	return 1 if interactable.interact_type == NPC_INTERACT_TYPE else 0


func _is_npc_item(item: Node2D) -> bool:
	var interactable: Interactable = item as Interactable
	return interactable != null and interactable.interact_type == NPC_INTERACT_TYPE


func _is_available(item: Node2D) -> bool:
	var interactable: Interactable = item as Interactable
	if interactable != null:
		return interactable.is_available() and InteractionRouter.is_available_for(interactable, self)
	return not item.has_method("is_available") or bool(item.call("is_available"))


## Sala del jugador según FloorStreamer ("" si no hay planta cargada).
func _current_room() -> String:
	var streamer: FloorStreamer = FloorStreamer.find_in(get_tree())
	return streamer.get_room_at(global_position) if streamer != null else ""


## Misma sala que el jugador, o un rayo del jugador al objeto sin tocar muros (capa 1).
func _no_wall_between(item: Node2D, here: String) -> bool:
	var interactable: Interactable = item as Interactable
	if interactable != null and not here.is_empty() and interactable.room_id == here:
		return true
	if not is_inside_tree():
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			global_position, item.global_position, 1 << (LAYER_WALLS - 1), [get_rid()])
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Radio de uso del Interactable (mundo.radio_uso_interactivo × su celda), en caché por nodo.
func _reach_of(item: Node2D) -> float:
	var id: int = item.get_instance_id()
	if _reach_cache.has(id):
		return float(_reach_cache[id])
	var interactable: Interactable = item as Interactable
	var reach: float = float(_tun["reach"])
	if interactable != null:
		reach = float(_tun["use_radius"]) * interactable.cell_px
	elif item.has_method("get_use_radius"):
		reach = float(item.call("get_use_radius"))
	if _reach_cache.size() >= REACH_CACHE_MAX:
		_reach_cache.clear()
	_reach_cache[id] = reach
	return reach


func _set_focus_flag(item: Node2D, focused: bool) -> void:
	if item != null and is_instance_valid(item) and item.has_method("set_focused"):
		item.call("set_focused", focused)


## Indicación contextual: UIRoot.show_interactable() (HUD + botón táctil) o la burbuja propia.
func _refresh_prompt() -> void:
	var key: String = InteractionRouter.prompt_key_for(_focus) if _focus != null else ""
	var custom: bool = not key.is_empty()
	if not custom and _focus != null and _focus.has_method("get_prompt_key"):
		key = str(_focus.call("get_prompt_key"))
	interaction_focus_changed.emit(_focus, key)
	var ui: Node = get_tree().get_first_node_in_group(UI_GROUP)
	if ui != null and ui.has_method("show_interactable"):
		ui.call("show_interactable", _focus)
		if custom and ui.has_method("set_context_action"):
			ui.call("set_context_action", key, UITheme.icon_for_interact_type(str(_focus.get("interact_type"))))
		key = ""
	_bubble.text = tr(key) if not key.is_empty() else ""
	_bubble.key_label = _interact_key_label()
	if _focus != null:
		_bubble.global_position = _focus.global_position + Vector2(0.0, -_cell)
	_bubble.queue_redraw()


func _interact_key_label() -> String:
	if OS.has_feature("mobile"):
		return ""
	for event: InputEvent in InputMap.action_get_events("interact"):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return ""


## InteractionRouter (otro constructor): nodo del grupo "interaction_router" o script con
## `static func interact(target, player)`. null si todavía no existe.
func _find_router() -> Object:
	var node: Node = get_tree().get_first_node_in_group(ROUTER_GROUP)
	if node != null and node.has_method(ROUTER_METHOD):
		return node
	if _router_script == null and ResourceLoader.exists(ROUTER_SCRIPT):
		_router_script = load(ROUTER_SCRIPT) as Script
	if _router_script == null:
		return null
	for method: Dictionary in _router_script.get_script_method_list():
		if method["name"] == ROUTER_METHOD and int(method["flags"]) & METHOD_FLAG_STATIC:
			return _router_script
	return null


# ─── Actos, apariencia y reacciones ────────────────────────────

func _finish_act(completed: bool) -> void:
	if _act.is_empty():
		return
	var crime: String = _act
	_act = ""
	_act_target = ""
	_act_timed = false
	_act_left = 0.0
	if _override_anim != "caught":
		_override_anim = ""
	act_finished.emit(crime, completed)


func _refresh_appearance() -> void:
	_tier = maxi(1, PlayerState.get_tier())
	if PlayerState.has_method("get_disguise"):
		_disguise = str(PlayerState.call("get_disguise"))
	_appearance = CharacterPainter.appearance_from_seed(appearance_seed(), _tier, false, "")
	_appearance["uniform"] = CharacterPainter.uniform_for_disguise(_disguise)
	queue_redraw()


## Semilla de apariencia: la del alta (GameLaunch.portrait_seed, guardada por GameSession en la
## bandera PORTRAIT_FLAG de PlayerState) o, sin ella, la de balance jugador.semilla_apariencia.
func appearance_seed() -> int:
	var stored: Variant = PlayerState.get_flag(PORTRAIT_FLAG, 0)
	if (stored is int or stored is float) and int(stored) != 0:
		return int(stored)
	return Database.get_balance_int(SEED_PATH)


func _on_occupation_changed(_old_id: String, _new_id: String, _reason: String) -> void:
	_refresh_appearance()


func _on_floor_changed(_old_floor: int, _new_floor: int) -> void:
	_reach_cache.clear()


func _on_disguise_changed(uniform_id: String) -> void:
	_disguise = uniform_id
	_appearance["uniform"] = CharacterPainter.uniform_for_disguise(uniform_id)
	queue_redraw()


## Flagrancia (§7.3): el acto se corta y el jugador se congela en la pose "descubierto".
func _on_caught(_npc_id: String, _crime_type: String, _witnesses: int) -> void:
	_finish_act(false)
	velocity = Vector2.ZERO
	_freeze_left = float(_tun["freeze"])
	play_anim("caught")
