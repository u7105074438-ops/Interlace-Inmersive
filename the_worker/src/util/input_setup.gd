# input_setup.gd — Registra en InputMap las acciones de juego (BUILD_NOTES §8, manual §13.7).
# PROPIETARIO DE: nada (escribe en el InputMap global solo las acciones que falten).
# ESCUCHA: nada.
class_name InputSetup
extends RefCounted

## Se invoca al arrancar (boot.gd / game_root.gd). Idempotente: una acción ya existente
## (por ejemplo, definida en project.godot o remapeada por el jugador) no se toca.
## El esprint no es una acción: doble pulsación de una dirección o doble clic.

const KEY_BINDINGS: Dictionary = {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sneak": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"map": [KEY_TAB],
	"computer": [KEY_C],
	"phone": [KEY_M],
	"debug_panel": [KEY_F1],
	"pause_menu": [KEY_ESCAPE],
	"inventory": [KEY_I],
	"ui_confirm": [KEY_ENTER, KEY_KP_ENTER],
}


static func register_actions() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: int in KEY_BINDINGS[action]:
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = keycode as Key
			InputMap.action_add_event(action, event)


## Nombres de todas las acciones que gestiona este módulo.
static func get_action_names() -> Array[String]:
	var out: Array[String] = []
	for action: String in KEY_BINDINGS:
		out.append(action)
	return out
