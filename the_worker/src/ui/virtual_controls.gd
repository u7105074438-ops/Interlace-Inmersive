# virtual_controls.gd — Controles táctiles de Android (§13.7): stick izquierdo flotante (doble toque = esprint), botón contextual grande abajo a la derecha, sigilo/agacharse y barra inferior deslizable.
# PROPIETARIO DE: el estado de los toques activos y la simulación de las acciones de entrada.
# ESCUCHA: nada.
class_name VirtualControls
extends Control

## Traduce toques a las acciones de InputSetup (move_*, sneak, crouch, interact) con
## Input.action_press(acción, intensidad) para el stick analógico e InputEventAction para
## "interact". El esprint se expone como acción "sprint" (se registra si no existe) mientras el
## stick se mantiene tras un doble toque. La barra inferior emite bar_action_requested(id) y
## bar_toggled(abierta) (UIRoot oculta la indicación contextual mientras está abierta).
## Multitáctil: se procesa en _input por índice de toque (sin depender del foco de la GUI).
## Solo procesa por fotograma mientras la barra se desliza.

signal bar_action_requested(action: String)
signal bar_toggled(open: bool)

const MOVE_AXES: Dictionary = {
	"move_left": Vector2.LEFT, "move_right": Vector2.RIGHT, "move_up": Vector2.UP, "move_down": Vector2.DOWN,
}
const SPRINT_ACTION := "sprint"
const INTERACT_ACTION := "interact"
const SNEAK_ACTION := "sneak"
const CROUCH_ACTION := "crouch"
const BAR_ITEMS: Array[Array] = [
	["map", "map", "VC_MAP"], ["computer", "computer", "VC_COMPUTER"],
	["phone", "phone", "VC_PHONE"], ["inventory", "bag", "VC_INVENTORY"],
]
const MARGIN := 36
const NO_TOUCH := -1
const MOUSE_TOUCH := 0
const STICK_ZONE := Rect2(0.0, 0.3, 0.45, 0.7)
const HANDLE_H := 26.0
const BAR_ITEM_W_RADII := 1.35
const BAR_H_RADII := 1.15
## Botones de sigilo / agacharse: radio (en radios de stick, ≥ 0,5 → ≥ 48 dp a 2340×1080) y posición.
const TOGGLE_RADII := 0.5
const SNEAK_OFFSET_RADII := Vector2(-1.8, -0.15)
const CROUCH_OFFSET_RADII := Vector2(-0.55, -1.75)
const TOGGLE_LABELS: Dictionary = {"sneak": "VC_SNEAK", "crouch": "VC_CROUCH"}
const MSEC_PER_SEC := 1000.0

var _stick_touch: int = NO_TOUCH
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vec: Vector2 = Vector2.ZERO
var _last_stick_tap: float = -1000.0
var _sprinting: bool = false
var _action_touch: int = NO_TOUCH
var _action_icon: String = "target"
var _action_available: bool = false
var _sneak_on: bool = false
var _crouch_on: bool = false
var _bar_open: bool = false
var _bar_t: float = 0.0
var _reserved_bottom_left: float = 0.0


func _init() -> void:
	name = "VirtualControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if not InputMap.has_action(SPRINT_ACTION):
		InputMap.add_action(SPRINT_ACTION)
	set_process(false)


## Icono de la acción contextual disponible ("" o available=false → botón atenuado).
func set_action(icon_id: String, available: bool) -> void:
	_action_icon = icon_id if not icon_id.is_empty() else "target"
	_action_available = available
	queue_redraw()


## Altura ocupada por el panel inferior izquierdo del HUD (el stick en reposo se dibuja encima).
func set_reserved_bottom_left(height: float) -> void:
	_reserved_bottom_left = height
	queue_redraw()


func is_bar_open() -> bool:
	return _bar_open


func set_bar_open(open: bool) -> void:
	var changed: bool = open != _bar_open
	_bar_open = open
	set_process(true)
	if changed:
		bar_toggled.emit(open)


## Fracción desplegada de la barra (0 cerrada … 1 abierta).
func get_bar_fraction() -> float:
	return _bar_t


func is_processing_frames() -> bool:
	return is_processing()


func release_all() -> void:
	_end_stick()
	if _action_touch != NO_TOUCH:
		_send_action(INTERACT_ACTION, false)
		_action_touch = NO_TOUCH
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()
	elif what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _process(delta: float) -> void:
	var target: float = 1.0 if _bar_open else 0.0
	var speed: float = delta / maxf(UITheme.tune("interfaz.barra_inferior_segundos"), 0.01)
	_bar_t = move_toward(_bar_t, target, speed)
	queue_redraw()
	if is_equal_approx(_bar_t, target):
		_bar_t = target
		set_process(false)


# ─── Geometría ─────────────────────────────────────────────────────

func _radius() -> float:
	return UITheme.tune("interfaz.stick_radio")


func _rest_center() -> Vector2:
	var r: float = _radius()
	return Vector2(MARGIN + r * 1.2, size.y - MARGIN - r * 1.2 - _reserved_bottom_left)


func _action_center() -> Vector2:
	var r: float = _radius()
	return Vector2(size.x - MARGIN - r * 0.95, size.y - MARGIN - r * 0.95)


## Centro (coordenadas locales) del conmutador SNEAK_ACTION / CROUCH_ACTION.
func get_toggle_center(which: String) -> Vector2:
	return _toggle_center(which)


func _toggle_center(which: String) -> Vector2:
	var offset: Vector2 = SNEAK_OFFSET_RADII if which == SNEAK_ACTION else CROUCH_OFFSET_RADII
	return _action_center() + offset * _radius()


func _handle_rect() -> Rect2:
	var r: float = _radius()
	var bar_h: float = r * BAR_H_RADII * _bar_t
	return Rect2(size.x * 0.5 - r * 0.7, size.y - HANDLE_H - bar_h, r * 1.4, HANDLE_H)


func _bar_rect() -> Rect2:
	var r: float = _radius()
	var w: float = r * BAR_ITEM_W_RADII * BAR_ITEMS.size()
	var h: float = r * BAR_H_RADII
	return Rect2(size.x * 0.5 - w * 0.5, size.y - h * _bar_t, w, h)


func _bar_item_at(pos: Vector2) -> String:
	var bar: Rect2 = _bar_rect()
	if _bar_t < 1.0 or not bar.has_point(pos):
		return ""
	var index: int = clampi(int((pos.x - bar.position.x) / (bar.size.x / BAR_ITEMS.size())), 0, BAR_ITEMS.size() - 1)
	return str(BAR_ITEMS[index][0])


# ─── Entrada ───────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var handled: bool = false
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		handled = _on_touch(touch.index, touch.position, touch.pressed)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		handled = _on_drag(drag.index, drag.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			handled = _on_touch(MOUSE_TOUCH, mb.position, mb.pressed)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		handled = _stick_touch == MOUSE_TOUCH and _on_drag(MOUSE_TOUCH, (event as InputEventMouseMotion).position)
	if handled:
		get_viewport().set_input_as_handled()


func _on_touch(index: int, pos: Vector2, pressed: bool) -> bool:
	if not pressed:
		return _on_release(index)
	var bar_item: String = _bar_item_at(pos)
	if not bar_item.is_empty():
		set_bar_open(false)
		bar_action_requested.emit(bar_item)
		return true
	if pos.distance_to(_action_center()) <= _radius() * 0.85:
		_action_touch = index
		_send_action(INTERACT_ACTION, true)
		queue_redraw()
		return true
	if _try_toggles(pos):
		return true
	if _handle_rect().grow(12).has_point(pos):
		set_bar_open(not _bar_open)
		return true
	return _try_start_stick(index, pos)


func _try_toggles(pos: Vector2) -> bool:
	var r: float = _radius() * TOGGLE_RADII
	if pos.distance_to(_toggle_center(SNEAK_ACTION)) <= r:
		_sneak_on = not _sneak_on
		_set_held(SNEAK_ACTION, _sneak_on, 1.0)
		queue_redraw()
		return true
	if pos.distance_to(_toggle_center(CROUCH_ACTION)) <= r:
		_crouch_on = not _crouch_on
		_set_held(CROUCH_ACTION, _crouch_on, 1.0)
		queue_redraw()
		return true
	return false


func _try_start_stick(index: int, pos: Vector2) -> bool:
	var zone: Rect2 = Rect2(STICK_ZONE.position * size, STICK_ZONE.size * size)
	if _stick_touch != NO_TOUCH or not zone.has_point(pos):
		return false
	_stick_touch = index
	var r: float = _radius()
	_stick_origin = Vector2(clampf(pos.x, r, size.x - r), clampf(pos.y, r, size.y - r))
	var now: float = Time.get_ticks_msec() / MSEC_PER_SEC
	_sprinting = now - _last_stick_tap <= UITheme.tune("interfaz.doble_toque_segundos")
	_last_stick_tap = now
	_set_held(SPRINT_ACTION, _sprinting, 1.0)
	_on_drag(index, pos)
	return true


func _on_drag(index: int, pos: Vector2) -> bool:
	if index != _stick_touch:
		return false
	var v: Vector2 = (pos - _stick_origin) / maxf(_radius(), 1.0)
	_stick_vec = v.limit_length(1.0)
	var effective: Vector2 = _stick_vec if _stick_vec.length() >= UITheme.tune("interfaz.stick_zona_muerta") else Vector2.ZERO
	for action: String in MOVE_AXES:
		_set_held(action, true, maxf(effective.dot(MOVE_AXES[action]), 0.0))
	queue_redraw()
	return true


func _on_release(index: int) -> bool:
	if index == _stick_touch:
		_end_stick()
		return true
	if index == _action_touch:
		_action_touch = NO_TOUCH
		_send_action(INTERACT_ACTION, false)
		queue_redraw()
		return true
	return false


func _end_stick() -> void:
	_stick_touch = NO_TOUCH
	_stick_vec = Vector2.ZERO
	_sprinting = false
	for action: String in MOVE_AXES:
		_set_held(action, false, 0.0)
	_set_held(SPRINT_ACTION, false, 0.0)
	queue_redraw()


func _set_held(action: String, on: bool, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if on and strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _send_action(action: String, pressed: bool) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


# ─── Dibujo ────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_stick()
	_draw_action_button()
	_draw_toggle(SNEAK_ACTION, "sneak", _sneak_on)
	_draw_toggle(CROUCH_ACTION, "crouch", _crouch_on)
	_draw_bar()


func _col(color_name: String, alpha: float = 1.0) -> Color:
	return Color(get_theme_color(color_name, UITheme.HUD_TYPE), alpha)


func _disc(center: Vector2, radius: float, fill: Color, outline: Color, width: float) -> void:
	draw_circle(center, radius, fill, true, -1.0, true)
	draw_arc(center, radius, 0.0, TAU, 48, outline, width, true)


func _draw_stick() -> void:
	var r: float = _radius()
	var active: bool = _stick_touch != NO_TOUCH
	var center: Vector2 = _stick_origin if active else _rest_center()
	var alpha: float = 1.0 if active else 0.55
	_disc(center, r, _col("ink", 0.35 * alpha), _col("paper", 0.5 * alpha), 3.0)
	for k: int in 4:
		var dir: Vector2 = Vector2.RIGHT.rotated(k * PI * 0.5)
		var tip: Vector2 = center + dir * r * 0.82
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 14 + dir.orthogonal() * 10,
				tip - dir * 14 - dir.orthogonal() * 10]), _col("paper", 0.45 * alpha))
	var knob: Vector2 = center + _stick_vec * r * 0.6
	var knob_fill: Color = _col("warn", 0.95) if _sprinting else _col("paper", 0.85 * alpha)
	_disc(knob, r * 0.42, knob_fill, _col("ink", 0.9), 3.0)
	if _sprinting:
		var s: float = r * 0.42
		UITheme.draw_icon(self, "sprint", Rect2(knob - Vector2(s, s) * 0.5, Vector2(s, s)), _col("ink"), 4.0)


func _draw_action_button() -> void:
	var r: float = _radius() * 0.8 * (0.94 if _action_touch != NO_TOUCH else 1.0)
	var c: Vector2 = _action_center()
	var fill: Color = _col("paper", 0.92) if _action_available else _col("ink", 0.45)
	_disc(c, r, fill, _col("ink", 0.9) if _action_available else _col("paper", 0.35), 4.0)
	var s: float = r * 1.0
	var icon_col: Color = _col("ink") if _action_available else _col("paper", 0.4)
	UITheme.draw_icon(self, _action_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), icon_col, maxf(s * 0.09, 3.0))


## Botón conmutador con glifo de figura y rótulo debajo (forma + texto + color al activarse).
func _draw_toggle(action: String, icon: String, on: bool) -> void:
	var r: float = _radius() * TOGGLE_RADII
	var c: Vector2 = _toggle_center(action)
	_disc(c, r, _col("warn", 0.95) if on else _col("ink", 0.62), _col("ink", 0.9) if on else _col("paper", 0.7), 3.0)
	var s: float = r * 1.25
	UITheme.draw_icon(self, icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)),
			_col("ink") if on else _col("paper", 0.95), maxf(s * 0.08, 3.0))
	var f: Font = get_theme_font("font", UITheme.V_CAPTION)
	var fs: int = get_theme_font_size("font_size", UITheme.V_CAPTION)
	var text: String = UITheme.trf(str(TOGGLE_LABELS.get(icon, ""))).to_upper()
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base: Vector2 = Vector2(c.x - tw * 0.5, c.y + r + fs * 1.05)
	draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, _col("ink", 0.85))
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _col("warn") if on else _col("paper"))


func _draw_bar() -> void:
	var handle: Rect2 = _handle_rect()
	draw_colored_polygon(UITheme.rounded_rect_points(handle, HANDLE_H * 0.5), _col("ink", 0.7))
	var icon_s: float = HANDLE_H * 0.9
	var icon_name: String = "chevron_down" if _bar_open else "chevron_up"
	UITheme.draw_icon(self, icon_name, Rect2(handle.get_center() - Vector2(icon_s, icon_s) * 0.5,
			Vector2(icon_s, icon_s)), _col("paper"), 3.0)
	if _bar_t <= 0.0:
		return
	var bar: Rect2 = _bar_rect()
	draw_colored_polygon(UITheme.rounded_rect_points(bar, 18.0), _col("ink", 0.9))
	var item_w: float = bar.size.x / BAR_ITEMS.size()
	var f: Font = get_theme_font("font", UITheme.V_CAPTION)
	var fs: int = get_theme_font_size("font_size", UITheme.V_CAPTION)
	for i: int in BAR_ITEMS.size():
		var cell_center: Vector2 = Vector2(bar.position.x + item_w * (i + 0.5), bar.position.y + bar.size.y * 0.42)
		var s: float = bar.size.y * 0.42
		UITheme.draw_icon(self, str(BAR_ITEMS[i][1]), Rect2(cell_center - Vector2(s, s) * 0.5, Vector2(s, s)),
				_col("paper"), 3.0)
		var text: String = UITheme.trf(str(BAR_ITEMS[i][2])).to_upper()
		var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(cell_center.x - tw * 0.5, bar.end.y - fs * 0.6), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _col("muted"))
