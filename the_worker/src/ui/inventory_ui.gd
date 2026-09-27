# inventory_ui.gd — Inventario de ocho posiciones con distinción ordinario / comprometedor (§11.3).
# PROPIETARIO DE: la selección y la vista del inventario abierto (el inventario es de PlayerState).
# ESCUCHA: EventBus.inventory_changed (mientras está abierto).
class_name InventoryUI
extends PanelContainer

## Comprometedor = color (rojo/ámbar) Y forma (marco de cinta de peligro + triángulo de aviso).
## Acciones según contexto: soltar (siempre), esconder (si hay escondite al alcance, context
## "hide_spot_id"), deshacerse (solo en el muelle de basuras, irreversible → UIRoot pide confirmación).
## setup(context): {room_id?: String, hide_spot_id?: String}. Emite action_requested(acción, item_id);
## UIRoot ejecuta la acción sobre PlayerState. set_items() sustituye la lectura de PlayerState.

signal action_requested(action: String, item_id: String)
signal close_requested()

const SLOTS := 8
const COLUMNS := 4
const DISPOSAL_ROOM := "trash_dock"
const ACTION_DROP := "drop"
const ACTION_HIDE := "hide"
const ACTION_DISPOSE := "dispose"
const DETAIL_WIDTH_EMS := 15.0

var _items: Array[ItemData] = []
var _injected: bool = false
var _context: Dictionary = {}
var _selected: int = -1
var _slots: Array[ItemSlot] = []
var _count_label: Label
var _name_label: Label
var _category_icon: UITheme.IconView
var _category_label: Label
var _desc_label: Label
var _value_label: Label
var _drop_button: Button
var _hide_button: Button
var _dispose_button: Button
var _hint_label: Label
var _warning_row: HBoxContainer
var _warning_label: Label
var _detail_box: VBoxContainer


func _init() -> void:
	name = "InventoryUI"
	theme_type_variation = UITheme.V_MODAL
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	column.add_child(_build_header())
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	column.add_child(body)
	body.add_child(_build_grid())
	body.add_child(_build_details())
	column.add_child(_build_warning())


func _ready() -> void:
	EventBus.inventory_changed.connect(_on_inventory_changed)
	if not _injected:
		_items = PlayerState.get_inventory()
	_refresh()
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_focus_first.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _detail_box != null:
		_detail_box.custom_minimum_size.x = get_theme_constant("base", UITheme.HUD_TYPE) * DETAIL_WIDTH_EMS


func setup(context: Dictionary) -> void:
	_context = context.duplicate()
	if is_inside_tree():
		_refresh()


## Sustituye el contenido (pruebas, capturas y vistas previas).
func set_items(items: Array[ItemData]) -> void:
	_items = items.duplicate()
	_injected = true
	if is_inside_tree():
		_refresh()


func get_items() -> Array[ItemData]:
	return _items.duplicate()


func get_slot_count() -> int:
	return _slots.size()


func is_slot_compromising(index: int) -> bool:
	return index >= 0 and index < _items.size() and _items[index].is_compromising()


func select_slot(index: int) -> void:
	_selected = index if index >= 0 and index < _items.size() else -1
	for i: int in _slots.size():
		_slots[i].set_selected(i == _selected)
	_refresh_details()


func get_selected_item_id() -> String:
	return _items[_selected].id if _selected >= 0 and _selected < _items.size() else ""


func can_hide() -> bool:
	return not str(_context.get("hide_spot_id", "")).is_empty()


func can_dispose() -> bool:
	return _base_room(str(_context.get("room_id", _player_room()))) == DISPOSAL_ROOM


## Esc: pide el cierre a UIRoot.
func request_close() -> void:
	close_requested.emit()


# ─── Construcción ──────────────────────────────────────────────────

func _build_header() -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.add_child(UITheme.IconView.new("bag", "paper", 1.3))
	var title: Label = Label.new()
	title.theme_type_variation = UITheme.V_TITLE
	title.text = UITheme.trf("INVUI_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_count_label = Label.new()
	_count_label.theme_type_variation = UITheme.V_HEADING
	header.add_child(_count_label)
	var close: Button = Button.new()
	close.theme_type_variation = UITheme.V_FLAT
	close.text = UITheme.trf("UI_CLOSE")
	close.pressed.connect(request_close)
	header.add_child(close)
	return header


func _build_grid() -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for i: int in SLOTS:
		var slot: ItemSlot = ItemSlot.new()
		slot.pressed.connect(select_slot.bind(i))
		slot.focus_entered.connect(select_slot.bind(i))
		grid.add_child(slot)
		_slots.append(slot)
	return grid


func _build_details() -> VBoxContainer:
	_detail_box = VBoxContainer.new()
	_name_label = _mk_label(UITheme.V_HEADING)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_name_label)
	var cat_row: HBoxContainer = HBoxContainer.new()
	_category_icon = UITheme.IconView.new("check", "gain", 0.9)
	cat_row.add_child(_category_icon)
	_category_label = _mk_label(UITheme.V_STRONG)
	cat_row.add_child(_category_label)
	_detail_box.add_child(cat_row)
	_desc_label = _mk_label(UITheme.V_SMALL)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_desc_label)
	_value_label = _mk_label(UITheme.V_CAPTION)
	_detail_box.add_child(_value_label)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(spacer)
	_detail_box.add_child(_build_actions())
	_hint_label = _mk_label(UITheme.V_SMALL)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(_hint_label)
	return _detail_box


func _build_actions() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	_drop_button = _action_button("INVUI_DROP", ACTION_DROP, "")
	row.add_child(_drop_button)
	_hide_button = _action_button("INVUI_HIDE", ACTION_HIDE, "")
	row.add_child(_hide_button)
	_dispose_button = _action_button("INVUI_DISPOSE", ACTION_DISPOSE, UITheme.V_DANGER)
	row.add_child(_dispose_button)
	return row


func _build_warning() -> HBoxContainer:
	_warning_row = HBoxContainer.new()
	_warning_row.add_child(UITheme.IconView.new("hazard", "warn"))
	_warning_label = _mk_label(UITheme.V_STRONG)
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warning_row.add_child(_warning_label)
	return _warning_row


func _action_button(key: String, action: String, variation: String) -> Button:
	var button: Button = Button.new()
	button.text = UITheme.trf(key)
	if not variation.is_empty():
		button.theme_type_variation = variation
	button.pressed.connect(_on_action.bind(action))
	return button


func _mk_label(variation: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	return label


# ─── Estado ────────────────────────────────────────────────────────

func _refresh() -> void:
	for i: int in _slots.size():
		_slots[i].set_item(_items[i] if i < _items.size() else null, _kind_of(_items[i]) if i < _items.size() else "")
	_count_label.text = UITheme.trf("INVUI_COUNT", [_items.size(), SLOTS])
	if _selected >= _items.size():
		_selected = _items.size() - 1
	if _selected < 0 and not _items.is_empty():
		_selected = 0
	select_slot(_selected)
	_refresh_warning()


func _refresh_details() -> void:
	var item: ItemData = _items[_selected] if _selected >= 0 and _selected < _items.size() else null
	_detail_box.modulate.a = 1.0 if item != null else 0.5
	if item == null:
		_name_label.text = UITheme.trf("INVUI_EMPTY")
		_category_label.text = ""
		_category_icon.visible = false
		_desc_label.text = UITheme.trf("INVUI_EMPTY_HINT")
		_value_label.text = ""
		_set_actions_enabled(false)
		return
	var hot: bool = item.is_compromising()
	_name_label.text = UITheme.trf(item.name_key)
	_category_icon.visible = true
	_category_icon.set_icon("hazard" if hot else "check")
	_category_icon.set_color_name("warn" if hot else "gain")
	_category_label.text = UITheme.trf("INVUI_CAT_COMPROMISING" if hot else "INVUI_CAT_ORDINARY").to_upper()
	_category_label.add_theme_color_override("font_color", UITheme.color("warn" if hot else "gain"))
	_desc_label.text = UITheme.trf("INVUI_COMPROMISING_DESC" if hot else "INVUI_ORDINARY_DESC")
	_value_label.text = _value_text(item)
	_set_actions_enabled(true)


func _value_text(item: ItemData) -> String:
	var parts: Array[String] = []
	if item.value > 0:
		parts.append(UITheme.trf("INVUI_VALUE", [UITheme.format_money(item.value)]))
	if item.stack > 1:
		parts.append(UITheme.trf("INVUI_STACK", [item.stack]))
	return " · ".join(parts).to_upper()


func _set_actions_enabled(has_item: bool) -> void:
	_drop_button.disabled = not has_item
	_hide_button.disabled = not (has_item and can_hide())
	_dispose_button.disabled = not (has_item and can_dispose())
	var hints: Array[String] = []
	if has_item and not can_hide():
		hints.append(UITheme.trf("INVUI_HINT_NO_SPOT"))
	if has_item and not can_dispose():
		hints.append(UITheme.trf("INVUI_HINT_DISPOSE_ONLY_DOCK"))
	_hint_label.text = "\n".join(hints)


func _refresh_warning() -> void:
	var hot: int = 0
	for item: ItemData in _items:
		if item.is_compromising():
			hot += 1
	_warning_row.visible = hot > 0
	var searchable: bool = Security.can_search_player()
	var key: String = "INVUI_WARNING_SEARCH" if searchable else "INVUI_WARNING_HOT"
	_warning_label.text = UITheme.trf(key, [hot])
	_warning_label.add_theme_color_override("font_color", UITheme.color("danger" if searchable else "warn"))


func _kind_of(item: ItemData) -> String:
	if item.extra.has("kind"):
		return str(item.extra["kind"])
	if Database.has_method("get_item"):
		var data: Variant = Database.call("get_item", item.id)
		if data is ItemData and (data as ItemData).extra.has("kind"):
			return str((data as ItemData).extra["kind"])
	return ""


func _on_action(action: String) -> void:
	var item_id: String = get_selected_item_id()
	if not item_id.is_empty():
		action_requested.emit(action, item_id)


func _on_inventory_changed(_item_id: String, _added: bool) -> void:
	if not _injected:
		_items = PlayerState.get_inventory()
		_refresh()


## Quita un objeto de la vista (modo inyectado, tras una acción confirmada).
func remove_local(item_id: String) -> void:
	for i: int in _items.size():
		if _items[i].id == item_id:
			_items.remove_at(i)
			break
	_refresh()


func get_context() -> Dictionary:
	return _context.duplicate()


func _focus_first() -> void:
	if not _slots.is_empty() and _slots[0].is_inside_tree():
		_slots[maxi(_selected, 0)].grab_focus()


func _player_room() -> String:
	return str(PlayerState.call("get_room")) if PlayerState.has_method("get_room") else ""


static func _base_room(room_id: String) -> String:
	var at: int = room_id.find("@")
	return room_id.substr(0, at) if at >= 0 else room_id


## Una posición del inventario dibujada por código (tarjeta plana con contorno).
class ItemSlot extends Control:
	signal pressed()

	var item: ItemData = null
	var kind: String = ""
	var selected: bool = false

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			var s: float = get_theme_constant("slot", UITheme.HUD_TYPE)
			custom_minimum_size = Vector2(s, s)
			queue_redraw()
		elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()

	func set_item(p_item: ItemData, p_kind: String) -> void:
		item = p_item
		kind = p_kind
		tooltip_text = UITheme.trf(item.name_key) if item != null else ""
		queue_redraw()

	func set_selected(on: bool) -> void:
		selected = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		var tap: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
		if click or tap or event.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var radius: float = size.x * 0.14
		if item == null:
			_draw_empty(r, radius)
		elif item.is_compromising():
			_draw_hot(r, radius)
		else:
			_draw_ordinary(r, radius)
		if item != null and item.stack > 1:
			_draw_stack(r)
		if selected or has_focus():
			var ring: PackedVector2Array = UITheme.rounded_rect_points(r.grow(4), radius + 4)
			ring.append(ring[0])
			draw_polyline(ring, get_theme_color("focus", UITheme.HUD_TYPE), 3.0, true)

	func _draw_empty(r: Rect2, radius: float) -> void:
		draw_colored_polygon(UITheme.rounded_rect_points(r, radius), Color(get_theme_color("slot", UITheme.HUD_TYPE), 0.5))
		var pts: PackedVector2Array = UITheme.rounded_rect_points(r.grow(-1), radius)
		for i: int in range(0, pts.size() - 1, 2):
			draw_line(pts[i], pts[i + 1], get_theme_color("faint", UITheme.HUD_TYPE), 2.0, true)

	func _draw_ordinary(r: Rect2, radius: float) -> void:
		var outline: Color = get_theme_color("line", UITheme.HUD_TYPE)
		draw_colored_polygon(UITheme.rounded_rect_points(r, radius), outline)
		draw_colored_polygon(UITheme.rounded_rect_points(r.grow(-2), radius - 2), get_theme_color("slot", UITheme.HUD_TYPE))
		_draw_item_icon(r, get_theme_color("paper", UITheme.HUD_TYPE))

	func _draw_hot(r: Rect2, radius: float) -> void:
		var outer: PackedVector2Array = UITheme.rounded_rect_points(r, radius)
		draw_colored_polygon(outer, get_theme_color("hazard_ink", UITheme.HUD_TYPE))
		UITheme.draw_stripes(self, outer, r, get_theme_color("hazard", UITheme.HUD_TYPE), size.x * 0.16)
		var ring_w: float = maxf(size.x * 0.075, 5.0)
		draw_colored_polygon(UITheme.rounded_rect_points(r.grow(-ring_w), radius - ring_w * 0.5),
				get_theme_color("slot_hot", UITheme.HUD_TYPE))
		_draw_item_icon(r, get_theme_color("warn", UITheme.HUD_TYPE))
		var badge: float = size.x * 0.34
		UITheme.draw_hazard_badge(self, Rect2(Vector2(size.x - badge * 0.92, -badge * 0.12), Vector2(badge, badge)),
				get_theme_color("hazard", UITheme.HUD_TYPE), get_theme_color("hazard_ink", UITheme.HUD_TYPE))

	func _draw_item_icon(r: Rect2, col: Color) -> void:
		var side: float = size.x * 0.52
		var icon_rect: Rect2 = Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
		UITheme.draw_icon(self, UITheme.icon_for_item_kind(kind), icon_rect, col, maxf(side * 0.09, 2.0))

	func _draw_stack(r: Rect2) -> void:
		var f: Font = get_theme_font("font", UITheme.V_STRONG)
		var fs: int = roundi(get_theme_font_size("font_size", UITheme.V_STRONG) * 0.8)
		var text: String = "×%d" % item.stack
		var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos: Vector2 = Vector2(r.end.x - w - size.x * 0.1, r.end.y - size.y * 0.1)
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, get_theme_color("ink", UITheme.HUD_TYPE))
		draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, get_theme_color("paper", UITheme.HUD_TYPE))
