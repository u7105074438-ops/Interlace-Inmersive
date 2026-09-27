# dialog_box.gd — Cuadro de diálogo modal con opciones (UIRoot.show_dialog, confirmaciones §13.7).
# PROPIETARIO DE: la elección en curso del diálogo.
# ESCUCHA: nada.
class_name DialogBox
extends PanelContainer

## options: Array de claves (String) o diccionarios {text_key, args?: Array, danger?: bool,
## disabled?: bool, icon?: String}. Emite chosen(índice) una sola vez; CANCEL (-1) si se cancela.
## Teclado: 1-9 eligen directamente; flechas + Intro; Esc cancela (si es cancelable).

signal chosen(index: int)

const CANCEL := -1
const WIDTH_EMS := 24.0
const MAX_NUMBER_KEYS := 9

var _buttons: Array[Button] = []
var _done: bool = false
var _cancellable: bool = true
var _title: Label
var _body: Label
var _options_box: VBoxContainer


func _init() -> void:
	name = "DialogBox"
	theme_type_variation = UITheme.V_MODAL
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = UITheme.V_TITLE
	column.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)
	_options_box = VBoxContainer.new()
	column.add_child(_options_box)


func _ready() -> void:
	_center()
	if not _buttons.is_empty():
		_focus_first.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _body != null:
		_body.custom_minimum_size.x = get_theme_constant("base", UITheme.HUD_TYPE) * WIDTH_EMS


func setup(title_key: String, body_key: String, options: Array, args: Array = [],
		cancellable: bool = true) -> void:
	_cancellable = cancellable
	_title.text = UITheme.trf(title_key, args) if not title_key.is_empty() else ""
	_title.visible = not title_key.is_empty()
	_body.text = UITheme.trf(body_key, args) if not body_key.is_empty() else ""
	_body.visible = not body_key.is_empty()
	for i: int in options.size():
		_add_option(i, options[i])


func choose(index: int) -> void:
	if _done:
		return
	if index != CANCEL and (index < 0 or index >= _buttons.size() or _buttons[index].disabled):
		return
	_done = true
	chosen.emit(index)


## Cierre externo (UIRoot.close_modal): resuelve con CANCEL si aún no se eligió.
func cancel() -> void:
	choose(CANCEL)


## Petición de cierre del jugador (Esc): solo si el diálogo es cancelable.
func request_close() -> void:
	if _cancellable:
		cancel()


func is_done() -> bool:
	return _done


func get_option_count() -> int:
	return _buttons.size()


func get_option_text(index: int) -> String:
	return _buttons[index].text if index >= 0 and index < _buttons.size() else ""


func _add_option(index: int, option: Variant) -> void:
	var spec: Dictionary = option if option is Dictionary else {"text_key": str(option)}
	var button: Button = Button.new()
	var label: String = UITheme.trf(str(spec.get("text_key", "")), spec.get("args", []))
	button.text = "%d   %s" % [index + 1, label] if index < MAX_NUMBER_KEYS else label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = bool(spec.get("disabled", false))
	if bool(spec.get("danger", false)):
		button.theme_type_variation = UITheme.V_DANGER
	button.pressed.connect(choose.bind(index))
	_options_box.add_child(button)
	_buttons.append(button)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or _done:
		return
	var number: int = key.physical_keycode - KEY_1
	if number >= 0 and number < mini(_buttons.size(), MAX_NUMBER_KEYS):
		get_viewport().set_input_as_handled()
		choose(number)


func _focus_first() -> void:
	for button: Button in _buttons:
		if not button.disabled and button.is_inside_tree():
			button.grab_focus()
			return


func _center() -> void:
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
