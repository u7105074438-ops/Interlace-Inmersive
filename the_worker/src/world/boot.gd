# boot.gd — Arranque: acciones de entrada, perfil y ajustes, carga de datos, error explícito o menú principal.
# PROPIETARIO DE: nada (monta la pantalla de error o el MainMenu; el QA lo lanza Autopilot).
# ESCUCHA: nada.
class_name BootScreen
extends Control

## Flujo (PASO 46 / §13.9): InputSetup → SettingsMenu.load_and_apply() (perfil: idioma, volúmenes)
## → GameLaunch.ensure_database() (Database.load_all() una vez por proceso). Si falla, se detiene
## el arranque con la lista de errores (PASO 4). Si no, MainMenu.
## Autopilot: con --autopilot=<escenario> se lanza el escenario; salvo "boot", el escenario monta
## sus propias pantallas y el arranque no muestra el menú (ni su música).

const BOOT_SCENARIO := "boot"


func _ready() -> void:
	InputSetup.register_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	SettingsMenu.load_and_apply()
	var data_ok: bool = GameLaunch.ensure_database()
	if Autopilot.is_requested():
		Autopilot.launch(get_tree())
		if Autopilot.get_arg("autopilot") != BOOT_SCENARIO:
			return
	if data_ok:
		add_child(MainMenu.new())
	else:
		add_child(build_error_screen(_load_errors()))


func _load_errors() -> Array[String]:
	var errors: Array[String] = Database.get_load_errors()
	if errors.is_empty():
		errors.append(tr("UI_BOOT_ERROR_UNKNOWN"))
	return errors


## Pantalla de error de datos: detiene el arranque y lista los errores de validación.
static func build_error_screen(errors: Array[String]) -> Control:
	var root: Control = Control.new()
	root.name = "BootError"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuKit.build_theme()
	var bg: ColorRect = ColorRect.new()
	bg.color = MenuKit.color("night")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var frame: Dictionary = MenuKit.memo_frame(TranslationServer.translate("UI_BOOT_ERROR_TITLE"),
			TranslationServer.translate("UI_BOOT_ERROR_KICKER"))
	root.add_child(frame["root"])
	var quit: Button = frame["back"]
	quit.text = TranslationServer.translate("UI_MENU_QUIT")
	quit.pressed.connect(func() -> void: root.get_tree().quit(1))
	var body: VBoxContainer = frame["body"]
	body.add_child(MenuKit.label(TranslationServer.translate("UI_BOOT_ERROR_BODY"), "", true))
	for line: String in errors:
		var item: Label = MenuKit.label("• " + line, "TWSmall", true)
		item.add_theme_font_override("font", MenuKit.font("mono"))
		body.add_child(item)
	if OS.is_debug_build():
		var go_on: Button = MenuKit.button(TranslationServer.translate("UI_BOOT_ERROR_CONTINUE"))
		go_on.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		go_on.pressed.connect(func() -> void: _continue_anyway(root))
		body.add_child(go_on)
	quit.grab_focus.call_deferred()
	return root


## Solo en compilaciones de depuración: seguir al menú pese a los errores (desarrollo en paralelo).
static func _continue_anyway(error_root: Control) -> void:
	var parent: Node = error_root.get_parent()
	error_root.queue_free()
	if parent != null:
		parent.add_child(MainMenu.new())
