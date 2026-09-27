# ui_root.gd — Raíz de la interfaz de juego (BUILD_NOTES §14): HUD, subtítulos, avisos, controles táctiles, pila modal, panel F1, ordenador/móvil/mapa/inventario, diálogos y resumen de jornada.
# PROPIETARIO DE: la pila modal, la pausa/ralentización del reloj por interfaz, el tema aplicado, el modo táctil, el interactivo enfocado (contexto del inventario), los avisos de deber dados hoy, el registro de la jornada (DayTracker) y el último resumen mostrado.
# ESCUCHA: day_summary_ready, duty_deadline_warned, hour_passed, day_advanced, inventory_changed, duty_completed, duty_failed, alert_level_changed, clearance_changed, run_started, run_loaded.
class_name UIRoot
extends CanvasLayer

## Protocolo de ventanas modales (open_modal):
##  · La ventana es un Control; UIRoot la añade, la atenúa detrás (meta "ui_dim" = false lo evita)
##    y la libera al cerrarla. pauses_clock → GameClock.pause() mientras alguna lo pida; al cerrar
##    solo reanuda si fue UIRoot quien pausó (no deshace la pausa de otro sistema).
##  · Si la ventana sale del árbol por su cuenta (queue_free propio, cambio de escena) se retira
##    de la pila; un diálogo pendiente resuelve con CANCEL.
##  · Mientras haya ventanas, el jugador (grupo "player") recibe set_input_locked(true).
##  · Si la ventana tiene señal close_requested o closed, UIRoot la cierra al emitirse.
##  · Esc: si la ventana superior tiene request_close() se le pide; si no, se cierra.
##  · Si tiene cancel(), se invoca al cerrarla desde fuera (los diálogos resuelven con -1).
##  · Si tiene setup(context: Dictionary), open_computer/open_phone/open_map se lo pasan.
## Teclas que atiende UIRoot: debug_panel (F1, solo compilaciones de depuración), inventory (I),
## map (Tab), phone (M), computer (C, solo en el despacho propio), pause_menu/ui_cancel (cerrar).

const GROUP := "ui_root"
const LAYER := 10
const STELLAR_OS_SCRIPT := "res://src/ui/stellar_os/stellar_os.gd"
const PHONE_SCRIPT := "res://src/ui/mobile/phone.gd"
const MAP_SCRIPT := "res://src/ui/map_view.gd"
const SETTINGS_SCRIPT := "res://src/ui/settings_menu.gd"
const KIND_COMPUTER := "computer"
const KIND_PHONE := "phone"
const KIND_MAP := "map"
const KIND_INVENTORY := "inventory"
const KIND_DIALOG := "dialog"
const KIND_SUMMARY := "day_summary"
const KIND_OTHER := "other"
const META_KIND := "ui_kind"
const META_DIM := "ui_dim"
const SUBTITLE_BOTTOM := 150
const TOAST_TOP := 108
const NORMAL_SPEED := 1.0
const DISPOSE_METHOD := "trash_dock"
## Método de item_disposed al tirar un objeto ordinario cuando el mundo no puede dejarlo en el suelo.
const DISCARD_METHOD := "discarded"
const MINUTES_PER_HOUR := 60.0
const ACT_CANCELLED := 0
const ACT_DONE := 1
const ACT_FAILED := 2

var _root: Control
var _hud: HUD
var _subtitles: SubtitleFeed
var _toasts: ToastStack
var _virtual: VirtualControls
var _modal_layer: Control
var _dim: ColorRect
var _debug: DebugPanel
var _stack: Array[Dictionary] = []
var _clock_paused_by_ui: bool = false
var _clock_was_paused: bool = false
var _computer_slowed: bool = false
var _speed_before_computer: float = NORMAL_SPEED
var _player_locked_by_ui: bool = false
var _touch_mode: bool = false
var _tracker: DaySummary.DayTracker = DaySummary.DayTracker.new()
var _warned_today: Dictionary = {}
var _generic_warned: bool = false
var _summary_day_shown: int = 0
var _last_snapshot: Dictionary = {}
var _focus_ref: WeakRef = null
var _text_size: int = UITheme.TEXT_MEDIUM
var _high_contrast: bool = false


func _init() -> void:
	name = "UIRoot"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _ready() -> void:
	add_to_group(GROUP)
	InputSetup.register_actions()
	apply_settings()
	_connect_bus()
	_tracker.connect_bus()
	_tracker.reset(PlayerState.get_reputation(), PlayerState.get_suspicion())
	_virtual.bar_action_requested.connect(_on_bar_action)
	_virtual.bar_toggled.connect(_hud.set_prompt_suppressed)
	set_touch_mode(detect_touch())


## Si UIRoot desaparece (cambio de escena) devuelve lo que tomó: pausa, velocidad y bloqueo.
func _exit_tree() -> void:
	if _clock_paused_by_ui:
		_clock_paused_by_ui = false
		_set_ui_pause(false)
	_apply_computer_speed(false)
	_lock_player(false)


## Primera UIRoot del árbol (o null).
static func find(tree: SceneTree) -> UIRoot:
	return tree.get_first_node_in_group(GROUP) as UIRoot


static func detect_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
			or Autopilot.get_arg("touch-ui") == "true"


# ─── Construcción ──────────────────────────────────────────────────

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_hud = HUD.new()
	_root.add_child(_hud)
	_virtual = VirtualControls.new()
	_virtual.visible = false
	_root.add_child(_virtual)
	_modal_layer = Control.new()
	_modal_layer.name = "Modals"
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_modal_layer)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_modal_layer.add_child(_dim)
	_build_feeds()
	_debug = DebugPanel.new()
	_root.add_child(_debug)


func _build_feeds() -> void:
	_subtitles = SubtitleFeed.new()
	_root.add_child(_subtitles)
	_subtitles.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_subtitles.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitles.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitles.offset_bottom = -SUBTITLE_BOTTOM
	_subtitles.offset_top = -SUBTITLE_BOTTOM
	UITheme.keep_fitted(_subtitles)
	_toasts = ToastStack.new()
	_root.add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.offset_top = TOAST_TOP
	_toasts.offset_bottom = TOAST_TOP
	UITheme.keep_fitted(_toasts)


# ─── Ventanas modales ──────────────────────────────────────────────

func open_modal(control: Control, pauses_clock: bool) -> void:
	if control == null or _index_of(control) >= 0:
		return
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	_stack.append({"control": control, "pauses": pauses_clock})
	control.tree_exiting.connect(_on_modal_exiting.bind(control), CONNECT_ONE_SHOT)
	_modal_layer.add_child(control)
	for signal_name: String in ["close_requested", "closed"]:
		if control.has_signal(signal_name):
			control.connect(signal_name, close_modal_control.bind(control), CONNECT_ONE_SHOT)
	if control.has_signal("setting_changed"):
		control.connect("setting_changed", _on_setting_changed)
	_refresh_modal_state()


## Cierra la ventana superior.
func close_modal() -> void:
	if not _stack.is_empty():
		close_modal_control(_stack.back()["control"])


## Cierra una ventana concreta de la pila (no hace nada si ya no está).
func close_modal_control(control: Control) -> void:
	var index: int = _index_of(control)
	if index < 0:
		return
	_stack.remove_at(index)
	if is_instance_valid(control):
		if control.has_method("cancel"):
			control.call("cancel")
		control.queue_free()
	_refresh_modal_state()


func has_modal() -> bool:
	return not _stack.is_empty()


func get_modal_count() -> int:
	return _stack.size()


func get_top_modal() -> Control:
	return _stack.back()["control"] if not _stack.is_empty() else null


func is_clock_paused_by_ui() -> bool:
	return _clock_paused_by_ui


## La ventana salió del árbol sin pasar por close_modal_control (se liberó sola o se va la escena).
func _on_modal_exiting(control: Control) -> void:
	var index: int = _index_of(control)
	if index < 0:
		return
	_stack.remove_at(index)
	if control.has_method("cancel"):
		control.call("cancel")
	if is_inside_tree() and not is_queued_for_deletion():
		_refresh_modal_state.call_deferred()


func _index_of(control: Control) -> int:
	for i: int in _stack.size():
		if _stack[i]["control"] == control:
			return i
	return -1


func _find_kind(kind: String) -> Control:
	for entry: Dictionary in _stack:
		var c: Control = entry["control"]
		if is_instance_valid(c) and str(c.get_meta(META_KIND, KIND_OTHER)) == kind:
			return c
	return null


func _refresh_modal_state() -> void:
	var top: Control = get_top_modal()
	_dim.visible = top != null and bool(top.get_meta(META_DIM, true))
	if top != null:
		_modal_layer.move_child(_dim, -1)
		_modal_layer.move_child(top, -1)
	var should_pause: bool = false
	for entry: Dictionary in _stack:
		should_pause = should_pause or bool(entry["pauses"])
	if should_pause != _clock_paused_by_ui:
		_clock_paused_by_ui = should_pause
		_set_ui_pause(should_pause)
	_apply_computer_speed(_find_kind(KIND_COMPUTER) != null)
	_lock_player(has_modal())
	_virtual.visible = _touch_mode and not has_modal()


## Pausa del reloj pedida por la interfaz: recuerda si ya estaba pausado para no reanudar lo ajeno.
func _set_ui_pause(on: bool) -> void:
	if on:
		_clock_was_paused = GameClock.is_paused()
		if not _clock_was_paused:
			GameClock.pause()
	elif not _clock_was_paused:
		GameClock.resume()


## Ralentización dentro del ordenador; al salir restaura el multiplicador que había.
func _apply_computer_speed(slow: bool) -> void:
	if slow == _computer_slowed:
		return
	_computer_slowed = slow
	if slow:
		_speed_before_computer = GameClock.get_speed_multiplier()
		GameClock.set_speed_multiplier(UITheme.tune("tiempo.velocidad_en_ordenador"))
	else:
		GameClock.set_speed_multiplier(_speed_before_computer)


## Solo actúa en las transiciones: no deshace un bloqueo impuesto por otro sistema.
func _lock_player(locked: bool) -> void:
	if locked == _player_locked_by_ui:
		return
	_player_locked_by_ui = locked
	var player: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", locked)


# ─── Avisos, diálogos y pantallas ──────────────────────────────────

func toast(text_key: String, args: Array = [], kind: String = ToastStack.KIND_INFO) -> void:
	_toasts.push(UITheme.trf(text_key, args), kind)


## Diálogo modal; devuelve el índice elegido o DialogBox.CANCEL (-1). Usar con await.
func show_dialog(title_key: String, body_key: String, options: Array, args: Array = [],
		pauses_clock: bool = true, cancellable: bool = true) -> int:
	var box: DialogBox = DialogBox.new()
	box.set_meta(META_KIND, KIND_DIALOG)
	box.setup(title_key, body_key, options, args, cancellable)
	open_modal(box, pauses_clock)
	var index: int = await box.chosen
	close_modal_control(box)
	return index


func open_computer(context: Dictionary = {}) -> void:
	if _toggle_existing(KIND_COMPUTER):
		return
	var node: Control = _instantiate(STELLAR_OS_SCRIPT, context)
	if node == null:
		toast("UI_COMPUTER_UNAVAILABLE", [], ToastStack.KIND_WARN)
		return
	node.set_meta(META_KIND, KIND_COMPUTER)
	open_modal(node, false)


## El móvil es una superposición: el reloj sigue y el jugador sigue expuesto (§13.5).
func open_phone(context: Dictionary = {}) -> void:
	if _toggle_existing(KIND_PHONE):
		return
	var node: Control = _instantiate(PHONE_SCRIPT, context)
	if node == null:
		toast("UI_PHONE_UNAVAILABLE", [], ToastStack.KIND_WARN)
		return
	node.set_meta(META_KIND, KIND_PHONE)
	node.set_meta(META_DIM, false)
	open_modal(node, false)


func open_map(context: Dictionary = {}) -> void:
	if _toggle_existing(KIND_MAP):
		return
	var node: Control = _instantiate(MAP_SCRIPT, context)
	if node == null:
		toast("UI_MAP_UNAVAILABLE", [], ToastStack.KIND_WARN)
		return
	node.set_meta(META_KIND, KIND_MAP)
	open_modal(node, true)


## Inventario (§11.3). context: {room_id?, hide_spot_id?}. Sin contexto (tecla I, barra táctil)
## se deduce del interactivo enfocado por el jugador (show_interactable): si es un escondite real de
## la sala, "Esconder" queda disponible.
func open_inventory(context: Dictionary = {}) -> void:
	if _toggle_existing(KIND_INVENTORY):
		return
	var inv: InventoryUI = InventoryUI.new()
	inv.set_meta(META_KIND, KIND_INVENTORY)
	inv.setup(context if not context.is_empty() else default_inventory_context())
	inv.action_requested.connect(_on_inventory_action)
	open_modal(inv, false)


## Contexto del inventario deducido: sala del jugador y escondite enfocado (si lo hay).
func default_inventory_context() -> Dictionary:
	var context: Dictionary = {"room_id": _player_room()}
	var focus: Node = get_focused_interactable()
	if focus == null:
		return context
	var room_id: String = str(focus.get("room_id")) if focus.get("room_id") != null else ""
	var spot_id: String = str(focus.get("interact_id")) if focus.get("interact_id") != null else ""
	if room_id.is_empty():
		room_id = str(context["room_id"])
	if not spot_id.is_empty() and not InventoryRules.find_spot(room_id, spot_id).is_empty():
		context["room_id"] = room_id
		context["hide_spot_id"] = spot_id
	return context


## Resumen de jornada (§15.6) completado con el DayTracker, que se reinicia para la jornada nueva.
## Si ya hay abierto uno del mismo día (el respaldo de day_advanced), el nuevo lo sustituye.
func show_day_summary(summary: Dictionary) -> DaySummary:
	var day: int = int(summary.get("day", GameClock.get_day()))
	var open_view: DaySummary = _find_kind(KIND_SUMMARY) as DaySummary
	var tracked: Dictionary = _tracker.snapshot()
	if open_view != null and int(open_view.get_summary().get("day", -1)) == day:
		tracked = _last_snapshot
		close_modal_control(open_view)
	var view: DaySummary = DaySummary.new()
	view.set_meta(META_KIND, KIND_SUMMARY)
	view.setup(DaySummary.merge(summary, tracked))
	open_modal(view, true)
	_last_snapshot = tracked
	_summary_day_shown = maxi(_summary_day_shown, day)
	_tracker.reset(_tracker.rep_now, _tracker.sus_now)
	return view


func _toggle_existing(kind: String) -> bool:
	var existing: Control = _find_kind(kind)
	if existing == null:
		return false
	if get_top_modal() == existing:
		close_modal_control(existing)
	return true


func _instantiate(path: String, context: Dictionary) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var obj: Object = script.new()
	var node: Control = obj as Control
	if node == null and obj is Node:
		node = Control.new()
		node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node.add_child(obj as Node)
	elif node == null:
		return null
	if obj.has_method("setup"):
		obj.call("setup", context)
	return node


# ─── Acción contextual, cámaras y ajustes ──────────────────────────

func set_context_action(prompt_key: String, icon_id: String = "target", args: Array = []) -> void:
	_hud.set_context_action(prompt_key, icon_id, args)
	_virtual.set_action(icon_id, not prompt_key.is_empty())


func clear_context_action() -> void:
	_hud.clear_context_action()
	_virtual.set_action("target", false)


## Atajo para el jugador: muestra la acción de un Interactable (o la oculta si es null/no disponible).
## Recuerda el interactivo enfocado (contexto por defecto del inventario).
func show_interactable(interactable: Node) -> void:
	if interactable == null or (interactable.has_method("is_available") and not interactable.call("is_available")):
		_focus_ref = null
		clear_context_action()
		return
	_focus_ref = weakref(interactable)
	var key: String = str(interactable.call("get_prompt_key")) if interactable.has_method("get_prompt_key") else ""
	set_context_action(key, UITheme.icon_for_interact_type(str(interactable.get("interact_type"))))


func get_focused_interactable() -> Node:
	var focus: Node = _focus_ref.get_ref() as Node if _focus_ref != null else null
	return focus if is_instance_valid(focus) and focus.is_inside_tree() else null


func set_camera_watch(camera_id: String, inside: bool) -> void:
	_hud.set_camera_watch(camera_id, inside)


## Relee text_size, high_contrast, subtitles y clock_speed (SettingsMenu/SaveSystem), reconstruye
## el tema y aplica el ritmo del reloj de accesibilidad (§13.10, GameClock.set_accessibility_speed).
func apply_settings() -> void:
	var size_value: Variant = _setting("text_size")
	var text_size: int = int(size_value) if (size_value is int or size_value is float) else UITheme.default_text_size()
	var contrast: Variant = _setting("high_contrast")
	set_text_options(text_size, contrast is bool and contrast)
	var subs: Variant = _setting("subtitles")
	_subtitles.set_enabled(not (subs is bool) or subs)
	var speed: Variant = _setting("clock_speed")
	if speed is int or speed is float:
		GameClock.set_accessibility_speed(float(speed))


func set_text_options(text_size: int, high_contrast: bool) -> void:
	_text_size = text_size
	_high_contrast = high_contrast
	UITheme.touch_scale_active = _touch_mode
	_root.theme = UITheme.build(text_size, high_contrast)
	_dim.color = UITheme.color("dim")
	if _touch_mode:
		_update_reserved_area.call_deferred()


func set_touch_mode(on: bool) -> void:
	var changed: bool = on != _touch_mode
	_touch_mode = on
	if changed:
		set_text_options(_text_size, _high_contrast)
	_hud.set_touch_layout(on)
	_virtual.visible = on and not has_modal()
	if on:
		_update_reserved_area.call_deferred()


func is_touch_mode() -> bool:
	return _touch_mode


func toggle_debug_panel() -> void:
	_debug.toggle()


func get_hud() -> HUD:
	return _hud


func get_subtitles() -> SubtitleFeed:
	return _subtitles


func get_toasts() -> ToastStack:
	return _toasts


func get_debug_panel() -> DebugPanel:
	return _debug


func get_virtual_controls() -> VirtualControls:
	return _virtual


func _update_reserved_area() -> void:
	_virtual.set_reserved_bottom_left(_hud.get_meters_rect().size.y + HUD.PANEL_GAP)


func _setting(key: String) -> Variant:
	if ResourceLoader.exists(SETTINGS_SCRIPT):
		var script: Script = load(SETTINGS_SCRIPT) as Script
		if script != null and script.has_method("get_value"):
			return script.call("get_value", key)
	return SaveSystem.get_setting(key)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in ["text_size", "high_contrast", "subtitles", "clock_speed"]:
		apply_settings()


# ─── Entrada ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if _pressed(event, "debug_panel") and OS.is_debug_build():
		toggle_debug_panel()
	elif has_modal() and (_pressed(event, "pause_menu") or _pressed(event, "ui_cancel")):
		_request_close_top()
	elif _pressed(event, "inventory"):
		_open_from_key(KIND_INVENTORY)
	elif _pressed(event, "map"):
		_open_from_key(KIND_MAP)
	elif _pressed(event, "phone"):
		_open_from_key(KIND_PHONE)
	elif _pressed(event, "computer"):
		_open_from_key(KIND_COMPUTER)
	else:
		return
	get_viewport().set_input_as_handled()


func _pressed(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _request_close_top() -> void:
	var top: Control = get_top_modal()
	if top != null and top.has_method("request_close"):
		top.call("request_close")
	else:
		close_modal()


func _open_from_key(kind: String) -> void:
	var top: Control = get_top_modal()
	if top != null and str(top.get_meta(META_KIND, KIND_OTHER)) != kind:
		return
	match kind:
		KIND_INVENTORY:
			open_inventory()
		KIND_MAP:
			open_map()
		KIND_PHONE:
			open_phone()
		KIND_COMPUTER:
			if top != null or _at_own_desk():
				open_computer()
			else:
				toast("UI_COMPUTER_ONLY_AT_DESK", [], ToastStack.KIND_WARN)


func _player_room() -> String:
	return str(PlayerState.call("get_room")) if PlayerState.has_method("get_room") else ""


func _at_own_desk() -> bool:
	var occ: OccupationData = PlayerState.get_occupation()
	var room: String = _player_room()
	if occ == null or occ.office_room.is_empty() or room.is_empty():
		return true
	return InventoryUI.base_room_id(room) == occ.office_room


func _on_bar_action(action: String) -> void:
	match action:
		KIND_MAP:
			open_map()
		KIND_COMPUTER:
			_open_from_key(KIND_COMPUTER)
		KIND_PHONE:
			open_phone()
		KIND_INVENTORY:
			open_inventory()


# ─── Inventario ────────────────────────────────────────────────────

## Ejecuta una acción del inventario. Toda acción irreversible pasa antes por un diálogo (§13.7).
func _on_inventory_action(action: String, item_id: String) -> void:
	var inv: InventoryUI = _find_kind(KIND_INVENTORY) as InventoryUI
	var context: Dictionary = inv.get_context() if inv != null else default_inventory_context()
	var item_name: String = _item_name(item_id)
	var result: int = ACT_FAILED
	var done_key: String = "INVUI_TOAST_%s" % action.to_upper()
	match action:
		InventoryUI.ACTION_DROP:
			var discard: bool = InventoryUI.find_drop_handler(get_tree()) == null
			done_key = "INVUI_TOAST_DISCARD" if discard else done_key
			result = await _drop_item(item_id)
		InventoryUI.ACTION_HIDE:
			result = await _hide_item(item_id, context)
		InventoryUI.ACTION_DISPOSE:
			result = await _dispose_item(item_id)
	if result == ACT_CANCELLED:
		return
	var ok: bool = result == ACT_DONE
	toast(done_key if ok else "INVUI_TOAST_FAILED", [item_name], ToastStack.KIND_INFO if ok else ToastStack.KIND_BAD)
	if ok and inv != null and is_instance_valid(inv):
		inv.note_unit_removed(item_id)


## Soltar: el mundo lo deja en el suelo si puede (grupo InventoryUI.DROP_HANDLER_GROUP); si no,
## solo se puede tirar un objeto ordinario, con confirmación. Lo comprometedor nunca desaparece así.
func _drop_item(item_id: String) -> int:
	var handler: Node = InventoryUI.find_drop_handler(get_tree())
	if handler != null:
		return ACT_DONE if bool(handler.call(InventoryUI.DROP_HANDLER_METHOD, item_id)) else ACT_FAILED
	if _is_hot_item(item_id):
		return ACT_FAILED
	if not await _confirm_irreversible("INVUI_DISCARD_TITLE", "INVUI_DISCARD_BODY", "INVUI_DISCARD", item_id):
		return ACT_CANCELLED
	return ACT_DONE if PlayerState.dispose_item(item_id, DISCARD_METHOD) else ACT_FAILED


## Esconder: si la ubicación del escondite es irreversible (bajante del muelle) se confirma antes.
func _hide_item(item_id: String, context: Dictionary) -> int:
	var spot_id: String = str(context.get("hide_spot_id", ""))
	var room_id: String = str(context.get("room_id", _player_room()))
	var spot: Dictionary = InventoryRules.find_spot(room_id, spot_id)
	if spot.is_empty():
		return ACT_FAILED
	if InventoryRules.is_irreversible(str(spot[InventoryRules.SPOT_LOCATION])):
		if not await _confirm_irreversible("INVUI_CONFIRM_TITLE", "INVUI_CONFIRM_BODY", "INVUI_DISPOSE", item_id):
			return ACT_CANCELLED
	return ACT_DONE if PlayerState.stash_item(item_id, spot_id, room_id) else ACT_FAILED


func _dispose_item(item_id: String) -> int:
	if not await _confirm_irreversible("INVUI_CONFIRM_TITLE", "INVUI_CONFIRM_BODY", "INVUI_DISPOSE", item_id):
		return ACT_CANCELLED
	return ACT_DONE if PlayerState.dispose_item(item_id, DISPOSE_METHOD) else ACT_FAILED


## Diálogo de confirmación: opción peligrosa primero pero el foco va a "Cancelar".
func _confirm_irreversible(title_key: String, body_key: String, confirm_key: String, item_id: String) -> bool:
	var options: Array = [{"text_key": confirm_key, "danger": true}, "UI_CANCEL"]
	return await show_dialog(title_key, body_key, options, [_item_name(item_id)]) == 0


## Comprometedor según PlayerState (lo entregado por el puesto actual cuenta como ordinario).
func _is_hot_item(item_id: String) -> bool:
	for item: ItemData in PlayerState.get_inventory():
		if item.id == item_id:
			return item.is_compromising()
	return InventoryRules.is_compromising(item_id)


func _item_name(item_id: String) -> String:
	for item: ItemData in PlayerState.get_inventory():
		if item.id == item_id:
			return UITheme.trf(item.name_key)
	var data: Variant = Database.call("get_item", item_id) if Database.has_method("get_item") else null
	return UITheme.trf((data as ItemData).name_key) if data is ItemData else item_id


# ─── Señales del bus ───────────────────────────────────────────────

func _connect_bus() -> void:
	EventBus.day_summary_ready.connect(_on_day_summary_ready)
	EventBus.duty_deadline_warned.connect(_on_duty_deadline_warned)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.duty_completed.connect(_on_duty_completed)
	EventBus.duty_failed.connect(_on_duty_failed)
	EventBus.alert_level_changed.connect(_on_alert_level_changed)
	EventBus.clearance_changed.connect(_on_clearance_changed)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_loaded.connect(_on_run_loaded)


func _on_day_summary_ready(summary: Dictionary) -> void:
	show_day_summary(summary)


func _on_duty_deadline_warned(duty_id: String, hours_left: float) -> void:
	if _warned_today.has(duty_id):
		return
	_warned_today[duty_id] = true
	toast("HUD_TOAST_DUTY_PENDING", [UITheme.trf(_duty_name_key(duty_id)), roundi(hours_left * MINUTES_PER_HOUR)],
			ToastStack.KIND_WARN)


## Respaldo de §15.6: aviso una hora antes del cierre por los deberes pendientes que ningún
## sistema haya avisado ya (duty_deadline_warned); una sola vez por jornada.
func _on_hour_passed(_hour: int, _day_number: int) -> void:
	var left: float = GameClock.hours_until_closing()
	if _generic_warned or left <= 0.0 or left > UITheme.tune("tiempo.aviso_deber_pendiente_horas_antes"):
		return
	var unwarned: int = 0
	for duty: Dictionary in PlayerState.get_pending_duties():
		if not _warned_today.has(str(duty.get("id", ""))):
			unwarned += 1
	if unwarned == 0:
		return
	_generic_warned = true
	toast("HUD_TOAST_DUTIES_PENDING", [unwarned], ToastStack.KIND_WARN)


## Respaldo de §15.6: si nadie emitió day_summary_ready para la jornada que acaba de cerrarse,
## el resumen se muestra igualmente con lo registrado por el DayTracker (al final del fotograma,
## para dar prioridad a un day_summary_ready emitido en el mismo fotograma).
func _on_day_advanced(day_number: int) -> void:
	_warned_today.clear()
	_generic_warned = false
	_show_fallback_summary.call_deferred(day_number - 1)


func _show_fallback_summary(day: int) -> void:
	if day < 1 or _summary_day_shown >= day or not is_inside_tree():
		return
	show_day_summary({"day": day})


func get_last_summary_day() -> int:
	return _summary_day_shown


func _on_inventory_changed(item_id: String, added: bool) -> void:
	if not added:
		return
	var data: Variant = Database.call("get_item", item_id) if Database.has_method("get_item") else null
	var hot: bool = data is ItemData and (data as ItemData).is_compromising()
	_toasts.push(UITheme.trf("HUD_TOAST_ITEM_ADDED", [_item_name(item_id)]),
			ToastStack.KIND_WARN if hot else ToastStack.KIND_INFO, "hazard" if hot else "bag")


func _on_duty_completed(duty_id: String, _quality: float, _method: String) -> void:
	toast("HUD_TOAST_DUTY_DONE", [UITheme.trf(_duty_name_key(duty_id))], ToastStack.KIND_GOOD)


func _on_duty_failed(duty_id: String, _consequence: String) -> void:
	toast("HUD_TOAST_DUTY_FAILED", [UITheme.trf(_duty_name_key(duty_id))], ToastStack.KIND_BAD)


func _on_alert_level_changed(old_level: int, new_level: int) -> void:
	if new_level > old_level:
		toast("HUD_TOAST_ALERT_UP", [new_level], ToastStack.KIND_WARN)


func _on_clearance_changed(old_level: int, new_level: int) -> void:
	if new_level > old_level:
		toast("HUD_TOAST_CLEARANCE_UP", [new_level], ToastStack.KIND_GOOD)


func _on_run_started(_run_seed: int) -> void:
	_reset_day_state(0)


func _on_run_loaded(day_number: int) -> void:
	_reset_day_state(day_number - 1)


func _reset_day_state(last_summary_day: int) -> void:
	_warned_today.clear()
	_generic_warned = false
	_summary_day_shown = last_summary_day
	_last_snapshot = {}
	_tracker.reset(PlayerState.get_reputation(), PlayerState.get_suspicion())


func _duty_name_key(duty_id: String) -> String:
	return _tracker.duty_name_key(duty_id)
