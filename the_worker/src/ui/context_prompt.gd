# context_prompt.gd — Indicación contextual de acción en el centro inferior del HUD (§13.1).
# PROPIETARIO DE: la acción contextual mostrada (clave de texto, argumentos e icono).
# ESCUCHA: nada.
class_name ContextPrompt
extends PanelContainer

## Solo es visible cuando existe una acción disponible. En modo táctil se oculta la tecla
## (el botón contextual grande de VirtualControls lleva el icono).

const ACTION := "interact"

var _prompt_key: String = ""
var _icon_id: String = "target"
var _args: Array = []
var _touch_mode: bool = false
var _keycap: PanelContainer
var _key_label: Label
var _icon: UITheme.IconView
var _label: Label


func _init() -> void:
	name = "ContextPrompt"
	theme_type_variation = UITheme.V_PILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_keycap = PanelContainer.new()
	_keycap.theme_type_variation = UITheme.V_KEYCAP
	_keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_key_label = Label.new()
	_key_label.theme_type_variation = UITheme.V_STRONG
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keycap.add_child(_key_label)
	row.add_child(_keycap)
	_icon = UITheme.IconView.new("target", "paper", 0.95)
	row.add_child(_icon)
	_label = Label.new()
	_label.theme_type_variation = UITheme.V_STRONG
	row.add_child(_label)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _key_label != null:
		_key_label.add_theme_color_override("font_color", get_theme_color("ink", UITheme.HUD_TYPE))


## Muestra la acción `prompt_key` (clave de strings.csv, con %s opcionales) e icono `icon_id`.
func show_action(prompt_key: String, icon_id: String = "target", args: Array = []) -> void:
	var was_visible: bool = visible
	_prompt_key = prompt_key
	_icon_id = icon_id if not icon_id.is_empty() else "target"
	_args = args.duplicate()
	_key_label.text = key_text(ACTION)
	_icon.set_icon(_icon_id)
	_label.text = UITheme.trf(_prompt_key, _args)
	visible = not _prompt_key.is_empty()
	if visible and not was_visible:
		_animate_in()


func hide_action() -> void:
	_prompt_key = ""
	visible = false


func has_action() -> bool:
	return visible and not _prompt_key.is_empty()


func get_prompt_key() -> String:
	return _prompt_key


func get_icon_id() -> String:
	return _icon_id


func get_text() -> String:
	return _label.text


func set_touch_mode(on: bool) -> void:
	_touch_mode = on
	_keycap.visible = not on


## Texto de la primera tecla asignada a la acción ("E"); clave HUD_KEY_INTERACT si no hay ninguna.
static func key_text(action: String) -> String:
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var key_ev: InputEventKey = ev as InputEventKey
				if key_ev.physical_keycode != KEY_NONE:
					return key_ev.as_text_physical_keycode()
				return key_ev.as_text_keycode()
	return String(TranslationServer.translate("HUD_KEY_INTERACT"))


func _animate_in() -> void:
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, UITheme.tune("interfaz.animacion_panel_segundos"))
