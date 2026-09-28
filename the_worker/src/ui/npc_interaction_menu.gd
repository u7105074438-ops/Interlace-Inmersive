# npc_interaction_menu.gd — Menú compacto de conversación junto a un personaje (§8, §13.7): opciones con su motivo si están cerradas, submenús, soborno en persona con BribePanel, réplicas por escalón y la eliminación con confirmación; el mundo sigue en marcha.
# PROPIETARIO DE: el menú abierto (personaje, página, opción en curso, réplica mostrada, exposición medida, bloqueo de movimiento "social_menu").
# ESCUCHA: EventBus.player_caught_redhanded, game_over, npc_removed, floor_changed (se cierra); BribePanel.offer_resolved / close_requested.
class_name NPCInteractionMenu
extends PanelContainer

## NO es una ventana modal: va en la capa de UIRoot justo encima del HUD, fuera de la pila modal
## (sin atenuar, sin pausar el reloj; la percepción sigue: el jugador está expuesto mientras habla);
## diálogos, subtítulos y avisos quedan por encima. Bloquea solo el movimiento del jugador (dueño
## LOCK_OWNER) para que flechas y números sirvan al menú.
## Opciones y efectos: SocialRules (src/world/interactions/_social_rules.gd); el menú solo pinta,
## pregunta (confirmaciones con la opción peligrosa sin foco, §13.7) y enseña el resultado (réplica
## del personaje, aviso y sonido). La exposición (testigos, cámaras) se mide cada
## social.intervalo_refresco_segundos: «Eliminar» se enciende o se pone en rojo en vivo.
## Teclado: 1-9 y 0 eligen; flechas + Intro; Esc o Retroceso = volver/cerrar; E o moverse (WASD)
## = marcharse. Táctil/ratón: toque en las filas, «i» abre la ficha rápida, «Marcharse» cierra.
## Se cierra solo si el personaje se aleja más de social.distancia_charla_celdas, sale de la
## plantilla, cambia la planta, hay flagrancia o se abre otra ventana (móvil, mapa…).

signal closed

const GROUP := "npc_interaction_menu"
const LOCK_OWNER := "social_menu"
const PAGE_MAIN := "main"
const PAGE_CHOICES := "choices"
const PAGE_BRIBE := "bribe"
const MOVE_ACTIONS: Array[String] = ["move_up", "move_down", "move_left", "move_right"]
const NAV_ACTIONS: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
const BACK_ACTIONS: Array[String] = ["ui_cancel", "pause_menu"]
const INTERACT_ACTION := "interact"
const HOTKEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
const HOTKEY_LABELS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
const EMOTE_TALK := "talk"
const EMOTE_MONEY := "money"
const EMOTE_EXCLAIM := "exclaim"
const FOLLOW_SLACK := 2.0
const ANCHOR_LIFT := 1.1


## Fila de opción: botón con tecla, icono, título y línea de apoyo (motivo, deuda, precio). Button
## no ordena hijos: el contenido se coloca a mano y su altura mínima pasa a custom_minimum_size.
class OptionRow extends Button:
	const PAD := Vector2(8, 3)
	var content: HBoxContainer = HBoxContainer.new()

	func _init() -> void:
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(content)
		content.minimum_size_changed.connect(_refit, CONNECT_DEFERRED)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_READY:
			_refit()

	func _refit() -> void:
		if not is_inside_tree():
			return
		content.position = PAD
		content.size = Vector2(maxf(size.x - PAD.x * 2.0, 0.0), content.get_combined_minimum_size().y)
		var want: Vector2 = content.get_combined_minimum_size() + PAD * 2.0
		if not want.is_equal_approx(custom_minimum_size):
			custom_minimum_size = want


var npc_id: String = ""
var _player: Node2D = null
var _ui: UIRoot = null
var _env: Dictionary = {}
var _page: String = PAGE_MAIN
var _option: Dictionary = {}
var _rows: Array[Button] = []
var _entries: Array[Dictionary] = []
var _busy: bool = false
var _closing: bool = false
var _refresh_left: float = 0.0
var _anchor_screen: Vector2 = Vector2.INF
var _portrait: CharacterCard.Portrait = null
var _name_label: Label = null
var _post_label: Label = null
var _reply: Label = null
var _page_title: Label = null
var _list: VBoxContainer = null
var _exposure_label: Label = null
var _bribe: BribePanel = null


# ─── Apertura y cierre ────────────────────────────────────────

static func find(tree: SceneTree) -> NPCInteractionMenu:
	return tree.get_first_node_in_group(GROUP) as NPCInteractionMenu if tree != null else null


## Abre el menú de `p_npc_id` (cierra el que hubiera). null si no hay jugador o personaje.
static func open(ui: UIRoot, p_npc_id: String, player: Node2D) -> NPCInteractionMenu:
	if ui == null or player == null or NPCDirector.get_npc(p_npc_id) == null:
		return null
	var previous: NPCInteractionMenu = find(ui.get_tree())
	if previous != null:
		previous.close()
	var menu: NPCInteractionMenu = NPCInteractionMenu.new()
	menu.setup(p_npc_id, player, ui)
	_attach(ui, menu)
	return menu


## Encima del HUD y por debajo de los diálogos, los subtítulos y los avisos (que no lo tapen ni él a ellos).
static func _attach(ui: UIRoot, menu: NPCInteractionMenu) -> void:
	var hud: HUD = ui.get_hud()
	var layer: Node = hud.get_parent() if hud != null else null
	if layer == null:
		ui.add_child(menu)
		return
	layer.add_child(menu)
	layer.move_child(menu, hud.get_index() + 1)


func setup(p_npc_id: String, player: Node2D, ui: UIRoot) -> void:
	npc_id = p_npc_id
	_player = player
	_ui = ui
	name = "NPCInteractionMenu"
	theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
	theme_type_variation = UITheme.V_PANEL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var base: float = float(UITheme.base_font_size(UITheme.current_text_size))
	custom_minimum_size = Vector2(base * SocialKit.bf("menu.ancho_em"), 0.0)
	_build()


func _ready() -> void:
	add_to_group(GROUP)
	minimum_size_changed.connect(_place, CONNECT_DEFERRED)
	_player.call("set_input_locked", true, LOCK_OWNER)
	EventBus.player_caught_redhanded.connect(_on_caught)
	EventBus.game_over.connect(_on_game_over)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.floor_changed.connect(_on_floor_changed)
	_env = SocialWorld.exposure(_player, npc_id)
	_greet()
	show_main()
	_emote(EMOTE_TALK)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, UITheme.tune("interfaz.animacion_panel_segundos"))
	_place.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.call("set_input_locked", false, LOCK_OWNER)


## Cierra el menú (idempotente). `toast_key` opcional: por qué se cerró. Con una confirmación o una
## escena en curso solo se oculta: el flujo pendiente lo libera al volver (_finish_if_closed).
func close(toast_key: String = "", args: Array = []) -> void:
	if _closing:
		return
	_closing = true
	visible = false
	remove_from_group(GROUP)
	if is_instance_valid(_player):
		_player.call("set_input_locked", false, LOCK_OWNER)
	if not toast_key.is_empty() and _ui != null:
		_ui.toast(toast_key, args)
	closed.emit()
	if not _busy:
		queue_free()


## Tras un await: si alguien cerró el menú mientras tanto, se libera ahora. true = cerrado.
func _finish_if_closed() -> bool:
	if _closing:
		_busy = false
		queue_free()
		return true
	return false


func is_busy() -> bool:
	return _busy


func get_page() -> String:
	return _page


func get_reply_text() -> String:
	return _reply.text if _reply != null else ""


func get_exposure() -> Dictionary:
	return _env.duplicate(true)


func _on_npc_removed(id: String, _cause: String) -> void:
	if id == npc_id and not _busy:
		close()


func _on_caught(_npc: String, _crime: String, _witnesses: int) -> void:
	close()


func _on_game_over(_cause: String, _ending: String, _snapshot: Dictionary) -> void:
	close()


func _on_floor_changed(_old: int, _new: int) -> void:
	if not _busy:
		close()


# ─── Construcción ─────────────────────────────────────────────

func _build() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	column.add_child(_build_header())
	_reply = _label("", UITheme.V_SMALL)
	_reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reply.add_theme_color_override("font_color", UITheme.color("paper"))
	var quote: PanelContainer = PanelContainer.new()
	quote.theme_type_variation = UITheme.V_CARD
	quote.add_child(_reply)
	column.add_child(quote)
	_page_title = _label("", UITheme.V_CAPTION)
	column.add_child(_page_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	column.add_child(_list)
	_exposure_label = _label("", UITheme.V_CAPTION)
	_exposure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_exposure_label)
	column.add_child(_build_footer())


func _build_header() -> HBoxContainer:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var identity: Dictionary = PersonnelApp.identity_of(npc)
	var row: HBoxContainer = HBoxContainer.new()
	_portrait = CharacterCard.Portrait.new()
	_portrait.appearance = identity.get("photo", {})
	var side: float = float(UITheme.base_font_size(UITheme.current_text_size)) * SocialKit.bf("menu.retrato_em")
	_portrait.custom_minimum_size = Vector2(side, side)
	row.add_child(_portrait)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	_name_label = _label(str(identity.get("name", "")), UITheme.V_HEADING)
	info.add_child(_name_label)
	_post_label = _label(str(identity.get("post", "")), UITheme.V_CAPTION)
	info.add_child(_post_label)
	row.add_child(info)
	row.add_child(_icon_button("info", "SOCIAL_MENU_CARD", _open_card))
	row.add_child(_icon_button("cross", "SOCIAL_MENU_LEAVE", func() -> void: close()))
	return row


func _build_footer() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var hint: Label = _label(TranslationServer.translate("SOCIAL_MENU_KEYS"), UITheme.V_CAPTION)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.color("muted"))
	row.add_child(hint)
	var leave: Button = Button.new()
	leave.text = TranslationServer.translate("SOCIAL_MENU_LEAVE")
	leave.theme_type_variation = UITheme.V_FLAT
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func() -> void: close())
	row.add_child(leave)
	return row


func _icon_button(icon: String, tip_key: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = UITheme.V_FLAT
	button.tooltip_text = TranslationServer.translate(tip_key)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size = Vector2.ONE * float(UITheme.base_font_size(UITheme.current_text_size)) * 1.6
	var view: UITheme.IconView = UITheme.IconView.new(icon, "muted")
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(view)
	button.pressed.connect(action)
	return button


func _label(text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ─── Páginas ──────────────────────────────────────────────────

func show_main() -> void:
	_page = PAGE_MAIN
	_option = {}
	_free_bribe()
	_page_title.visible = false
	_fill(SocialRules.options(npc_id, _env), true)
	_refresh_exposure_text()


func _show_choices(option: Dictionary) -> void:
	var list: Array[Dictionary] = SocialRules.choices(str(option["id"]), npc_id)
	if list.is_empty():
		_say([["SOCIAL_LINE_NOTHING_TO_ADD", []]])
		return
	_page = PAGE_CHOICES
	_option = option
	_page_title.text = str(option["label"]).to_upper()
	_page_title.visible = true
	_fill(list, false)


func _fill(entries: Array[Dictionary], main: bool) -> void:
	_clear_list()
	_rows.clear()
	_entries = entries
	for i: int in entries.size():
		var row: Button = _make_row(i, entries[i], main)
		_list.add_child(row)
		_rows.append(row)
	if not main:
		var back: Button = _make_row(entries.size(), {"label": TranslationServer.translate("SOCIAL_MENU_BACK"),
				"icon": "arrow", "enabled": true}, false)
		back.pressed.connect(show_main)
		_list.add_child(back)
		_rows.append(back)
	_focus_first.call_deferred()
	_place.call_deferred()


## Vacía la lista en el acto (fuera del árbol ya no cuenta para el tamaño del menú).
func _clear_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	if _bribe != null and not is_instance_valid(_bribe):
		_bribe = null


func _make_row(index: int, entry: Dictionary, main: bool) -> Button:
	var row: OptionRow = OptionRow.new()
	row.theme_type_variation = UITheme.V_FLAT
	var enabled: bool = bool(entry.get("enabled", true))
	var red: bool = bool(entry.get("red", false))
	row.disabled = not enabled
	row.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	row.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	row.content.add_child(_keycap(HOTKEY_LABELS[index] if index < HOTKEY_LABELS.size() else ""))
	var tone: String = "danger" if red or bool(entry.get("danger", false)) else ("paper" if enabled else "faint")
	row.content.add_child(UITheme.IconView.new(str(entry.get("icon", "talk" if main else "arrow")), tone))
	var texts: VBoxContainer = VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title: Label = _label(str(entry.get("label", "")), UITheme.V_SMALL)
	title.add_theme_color_override("font_color", UITheme.color(tone))
	texts.add_child(title)
	var sub: String = str(entry.get("reason", "")) if not enabled else str(entry.get("hint", ""))
	if not sub.is_empty():
		var sub_label: Label = _label(sub, UITheme.V_CAPTION)
		sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_label.add_theme_color_override("font_color", UITheme.color("danger" if red else "muted"))
		texts.add_child(sub_label)
	row.content.add_child(texts)
	if index < _entries.size():
		row.pressed.connect(_on_row_pressed.bind(index))
	return row


func _keycap(text: String) -> Control:
	var cap: PanelContainer = PanelContainer.new()
	cap.theme_type_variation = UITheme.V_KEYCAP
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = _label(text, UITheme.V_CAPTION)
	label.add_theme_color_override("font_color", UITheme.color("hazard_ink"))
	cap.add_child(label)
	cap.visible = not text.is_empty() and not UITheme.touch_scale_active
	return cap


func _focus_first() -> void:
	for row: Button in _rows:
		if is_instance_valid(row) and not row.disabled and row.is_inside_tree():
			row.grab_focus()
			return


# ─── Acciones ─────────────────────────────────────────────────

func _on_row_pressed(index: int) -> void:
	if _busy or index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	if not bool(entry.get("enabled", true)):
		SocialKit.sfx(SocialKit.SFX_ERROR)
		return
	if _page == PAGE_MAIN:
		_run_option(entry)
	else:
		_run_choice(entry)


func _run_option(option: Dictionary) -> void:
	match str(option["flow"]):
		SocialRules.FLOW_CHOICES:
			_show_choices(option)
		SocialRules.FLOW_BRIBE:
			_show_bribe(option)
		SocialRules.FLOW_ELIMINATE:
			_eliminate()
		_:
			if await _confirmed(option.get("confirm", {})) and not _closing:
				_apply(SocialRules.perform(str(option["id"]), "", npc_id, _env))


func _run_choice(choice: Dictionary) -> void:
	if not await _confirmed(choice.get("confirm", {})) or _closing:
		return
	_apply(SocialRules.perform(str(_option.get("id", "")), str(choice["id"]), npc_id, _env))


## Confirmación §13.7 (la opción peligrosa va primero, el foco cae en Cancelar). Sin spec: true.
func _confirmed(spec: Dictionary) -> bool:
	if spec.is_empty() or _ui == null:
		return true
	_busy = true
	visible = false
	var options: Array = [{"text_key": str(spec["go_key"]), "danger": true}, "UI_CANCEL"]
	var choice: int = await _ui.show_dialog(str(spec["title_key"]), str(spec["body_key"]), options, spec.get("args", []), false)
	if _finish_if_closed():
		return false
	_busy = false
	visible = true
	return choice == 0


## Enseña el resultado: réplica, aviso, sonido y gesto; refresca o cierra.
func _apply(res: Dictionary) -> void:
	if not (res.get("lines", []) as Array).is_empty():
		_reply.text = UITheme.trf("SOCIAL_REPLY_FMT", [SocialKit.npc_name(npc_id), SocialKit.lines_text(res)])
	if _ui != null and not str(res.get("toast_key", "")).is_empty():
		_ui.toast(str(res["toast_key"]), res.get("toast_args", []), str(res.get("toast_kind", ToastStack.KIND_INFO)))
	for extra: Variant in res.get("more_toasts", []):
		if _ui != null:
			_ui.toast(str(extra[0]), extra[1] as Array, str(extra[2]))
	SocialKit.sfx(str(res.get("sfx", "")))
	_emote(EMOTE_MONEY if str(res.get("sfx", "")) == SocialKit.SFX_CASH else (EMOTE_TALK if bool(res.get("ok", false)) else EMOTE_EXCLAIM))
	if bool(res.get("close", false)):
		close()
		return
	_env = SocialWorld.exposure(_player, npc_id)
	show_main()


func _say(lines: Array) -> void:
	_apply({"ok": true, "lines": lines, "sfx": SocialKit.SFX_INFO})


func _greet() -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null:
		var hello: Array = SocialTalk.greeting(npc)
		_reply.text = UITheme.trf("SOCIAL_REPLY_FMT", [npc.name, UITheme.trf(str(hello[0]), hello[1] as Array)])


func _open_card() -> void:
	var layer: NPCLayer = NPCLayer.find(get_tree())
	if layer != null:
		layer.open_card(npc_id)
	else:
		CharacterCard.open_for(get_tree(), npc_id)


func _emote(kind: String) -> void:
	var node: NPCNode = SocialWorld.npc_node(get_tree(), npc_id) if is_inside_tree() else null
	if node != null:
		node.show_emote(kind)


# ─── Soborno en persona (§8.2: sin registro, con testigos y cámaras) ─

func _show_bribe(option: Dictionary) -> void:
	_page = PAGE_BRIBE
	_option = option
	_clear_list()
	_entries = []
	_page_title.text = str(option["label"]).to_upper()
	_page_title.visible = true
	_bribe = BribePanel.new()
	_bribe.service = PhoneOverlay.find_service(get_tree())
	_bribe.ctx_provider = func(_channel: String) -> Dictionary: return _bribe_ctx()
	_bribe.offer_resolved.connect(_on_bribe_resolved)
	_bribe.close_requested.connect(show_main)
	_list.add_child(_bribe)
	_bribe.setup_for(npc_id, Bribery.CHANNEL_IN_PERSON)
	_bribe.set_compact(true)
	if not str(option.get("favour", "")).is_empty():
		_bribe.select_favour(str(option["favour"]))
	_bribe.set_exposure({PhoneOverlay.EXPO_LISTENERS: _env.get("witnesses", [])})
	_refresh_exposure_text()
	_place.call_deferred()


func _bribe_ctx() -> Dictionary:
	_env = SocialWorld.exposure(_player, npc_id)
	return {"room_id": str(_env["room_id"]), "witnesses": _env["witnesses"], "cameras": _env["cameras"]}


func _on_bribe_resolved(result: Dictionary) -> void:
	var outcome: String = str(result.get("outcome", ""))
	_reply.text = UITheme.trf("SOCIAL_REPLY_FMT", [SocialKit.npc_name(npc_id), UITheme.trf("SOCIAL_BRIBE_LINE_%s" % outcome.to_upper())])
	_emote(EMOTE_MONEY if bool(result.get("accepted", false)) else EMOTE_EXCLAIM)
	SocialKit.sfx(SocialKit.SFX_CASH if bool(result.get("accepted", false)) else SocialKit.SFX_ERROR)


func _free_bribe() -> void:
	if _bribe != null and is_instance_valid(_bribe):
		if _bribe.get_parent() != null:
			_bribe.get_parent().remove_child(_bribe)
		_bribe.queue_free()
	_bribe = null


# ─── Eliminación (§12.2, §3.1) ────────────────────────────────

func _eliminate() -> void:
	_env = SocialWorld.exposure(_player, npc_id)
	if not SocialRules.can_eliminate(_env):
		show_main()
		return
	var spec: Dictionary = {"title_key": "SOCIAL_ELIM_CONFIRM_TITLE", "body_key": "SOCIAL_ELIM_CONFIRM_BODY",
			"go_key": "SOCIAL_ELIM_CONFIRM_GO", "args": [SocialKit.npc_name(npc_id)]}
	if not await _confirmed(spec):
		return
	_busy = true
	visible = false
	_player.call("set_input_locked", false, LOCK_OWNER)
	var done: bool = await SocialWorld.act(_player, SocialKit.bf("eliminar.segundos_acto"), npc_id)
	if _finish_if_closed():
		return
	_env = SocialWorld.exposure(_player, npc_id)
	if not done or not SocialRules.can_eliminate(_env) or not SocialWorld.in_range(_player, npc_id):
		_busy = false
		close(_elim_abort_key(done))
		return
	var outcome: Dictionary = {}
	var env: Dictionary = _env
	var victim: String = npc_id
	await SocialWorld.play_elimination(_player, victim, func() -> void: outcome.merge(SocialRules.eliminate(victim, env)))
	if _ui != null and not str(outcome.get("toast_key", "")).is_empty():
		_ui.toast(str(outcome["toast_key"]), outcome.get("toast_args", []), str(outcome.get("toast_kind", ToastStack.KIND_WARN)))
	if not _finish_if_closed():
		_busy = false
		close()


## Por qué se aborta la eliminación tras el acto: se movió, hay testigos o la víctima se fue.
func _elim_abort_key(done: bool) -> String:
	if not done:
		return "SOCIAL_ELIM_INTERRUPTED"
	if not SocialRules.can_eliminate(_env):
		return "SOCIAL_ELIM_ABORTED_WITNESS"
	return "SOCIAL_ELIM_ABORTED_RANGE"


# ─── Vigilancia continua ──────────────────────────────────────

func _process(delta: float) -> void:
	if _closing or _busy:
		return
	if not _still_valid():
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = SocialKit.bf("intervalo_refresco_segundos")
		_refresh_live()
	var node: NPCNode = SocialWorld.npc_node(get_tree(), npc_id)
	if node != null and _screen_of(node.get_visual_position()).distance_to(_anchor_screen) > FOLLOW_SLACK:
		_place()


## false (y se cierra con su aviso) si la conversación ya no puede seguir.
func _still_valid() -> bool:
	if _ui != null and _ui.has_modal():
		close()
		return false
	if not NPCDirector.is_active(npc_id) or not is_instance_valid(_player):
		close()
		return false
	if not SocialWorld.in_range(_player, npc_id):
		close("SOCIAL_TOAST_WALKED_OFF", [SocialKit.npc_name(npc_id)])
		return false
	return true


## Testigos y cámaras en vivo: la fila «Eliminar» y la línea de exposición cambian solas.
func _refresh_live() -> void:
	var fresh: Dictionary = SocialWorld.exposure(_player, npc_id)
	var changed: bool = fresh.get("witnesses", []) != _env.get("witnesses", []) or fresh.get("cameras", []) != _env.get("cameras", [])
	_env = fresh
	if not changed:
		return
	_refresh_exposure_text()
	if _page == PAGE_MAIN:
		_refresh_eliminate_row()
	elif _page == PAGE_BRIBE and _bribe != null:
		_bribe.set_exposure({PhoneOverlay.EXPO_LISTENERS: _env.get("witnesses", [])})


func _refresh_eliminate_row() -> void:
	for i: int in _entries.size():
		if str(_entries[i].get("id", "")) == SocialRules.OPT_ELIMINATE:
			_entries[i] = SocialRules.eliminate_option(_env)
			var row: Button = _make_row(i, _entries[i], true)
			var old: Button = _rows[i]
			_list.add_child(row)
			_list.move_child(row, old.get_index())
			_list.remove_child(old)
			old.queue_free()
			_rows[i] = row


func _refresh_exposure_text() -> void:
	var witnesses: Array = _env.get("witnesses", [])
	var cameras: Array = _env.get("cameras", [])
	var parts: PackedStringArray = []
	var names: PackedStringArray = []
	for id: Variant in witnesses.slice(0, SocialKit.bi("menu.max_nombres_testigos")):
		names.append(SocialKit.npc_name(str(id)))
	if witnesses.size() > names.size():
		names.append(UITheme.trf("SOCIAL_EXPO_MORE", [witnesses.size() - names.size()]))
	if not names.is_empty():
		parts.append(UITheme.trf("SOCIAL_EXPO_WATCHED", [", ".join(names)]))
	if not cameras.is_empty():
		parts.append(TranslationServer.translate("SOCIAL_EXPO_CAMERA"))
	var safe: bool = parts.is_empty()
	_exposure_label.text = TranslationServer.translate("SOCIAL_EXPO_ALONE") if safe else " · ".join(parts)
	_exposure_label.add_theme_color_override("font_color", UITheme.color("gain" if safe else "danger"))


# ─── Entrada ──────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _closing or _busy or not event.is_pressed() or event.is_echo():
		return
	if _is_any(event, BACK_ACTIONS) or (event is InputEventKey and (event as InputEventKey).keycode == KEY_BACKSPACE):
		_back()
	elif event.is_action_pressed(INTERACT_ACTION) or (_is_any(event, MOVE_ACTIONS) and not _is_any(event, NAV_ACTIONS)):
		close()
	elif event is InputEventKey and _page != PAGE_BRIBE and HOTKEYS.has((event as InputEventKey).keycode):
		_on_row_pressed(HOTKEYS.find((event as InputEventKey).keycode))
	else:
		return
	get_viewport().set_input_as_handled()


func _is_any(event: InputEvent, actions: Array[String]) -> bool:
	for action: String in actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


func _back() -> void:
	if _page == PAGE_MAIN:
		close()
	else:
		show_main()


## Pruebas y QA: pulsa la opción `option_id` de la página principal (true si existía y se pudo).
func press_option(option_id: String) -> bool:
	for i: int in _entries.size():
		if str(_entries[i].get("id", "")) == option_id and bool(_entries[i].get("enabled", true)):
			_on_row_pressed(i)
			return true
	return false


## Pruebas y QA: pulsa el elemento `choice_id` del submenú abierto.
func press_choice(choice_id: String) -> bool:
	return _page == PAGE_CHOICES and press_option(choice_id)


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func get_bribe_panel() -> BribePanel:
	return _bribe


# ─── Posición ─────────────────────────────────────────────────

## A la izquierda del personaje si cabe (la ficha rápida se abre a su derecha), dentro de pantalla.
## La columna central es de los avisos (arriba) y los subtítulos (abajo): si el menú la pisa, se
## queda entre social.menu.reserva_superior_px y reserva_inferior_px; si no cabe ahí, sale de la
## columna hacia el lado del personaje (nunca tapa lo que se oye ni lo que se avisa).
func _place() -> void:
	if not is_inside_tree():
		return
	reset_size()
	var view: Rect2 = get_viewport().get_visible_rect()
	var margin: float = SocialKit.bf("menu.margen_px")
	var target: Vector2 = _preferred_position(view, margin)
	if _hits_center_column(view, target.x):
		var band: Vector2 = Vector2(view.position.y + SocialKit.bf("menu.reserva_superior_px"),
				view.end.y - SocialKit.bf("menu.reserva_inferior_px"))
		if size.y <= band.y - band.x:
			target.y = clampf(target.y, band.x, band.y - size.y)
		else:
			target.x = _outside_column_x(view, margin, target.x)
	target.x = clampf(target.x, view.position.x + margin, maxf(view.end.x - size.x - margin, view.position.x + margin))
	target.y = clampf(target.y, view.position.y + margin, maxf(view.end.y - size.y - margin, view.position.y + margin))
	position = target


func _preferred_position(view: Rect2, margin: float) -> Vector2:
	var gap: float = SocialKit.bf("menu.separacion_personaje_px")
	var node: NPCNode = SocialWorld.npc_node(get_tree(), npc_id)
	if node == null:
		return Vector2(view.position.x + margin, (view.size.y - size.y) * 0.5)
	_anchor_screen = _screen_of(node.get_visual_position())
	var target: Vector2 = Vector2(_anchor_screen.x - gap - size.x, _anchor_screen.y - size.y * 0.5)
	if target.x < view.position.x + margin:
		target.x = _anchor_screen.x + gap
	return target


func _hits_center_column(view: Rect2, x: float) -> bool:
	var half: float = SocialKit.bf("menu.columna_central_px") * 0.5
	var center: float = view.get_center().x
	return x < center + half and x + size.x > center - half


func _outside_column_x(view: Rect2, margin: float, x: float) -> float:
	var half: float = SocialKit.bf("menu.columna_central_px") * 0.5
	var center: float = view.get_center().x
	if x + size.x * 0.5 < center:
		return maxf(center - half - size.x, view.position.x + margin)
	return minf(center + half, view.end.x - size.x - margin)


func _screen_of(world: Vector2) -> Vector2:
	var cell: float = Database.get_balance_float("mundo.px_por_unidad")
	return get_viewport().get_canvas_transform() * (world - Vector2(0.0, cell * ANCHOR_LIFT))
