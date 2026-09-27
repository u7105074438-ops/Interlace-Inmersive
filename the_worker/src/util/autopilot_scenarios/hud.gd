# hud.gd (escenario) — Capturas del HUD, panel F1, inventario, resumen, diálogo, alto contraste y móvil.
# PROPIETARIO DE: nada (monta un fondo de oficina de muestra y una UIRoot con datos de ejemplo).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_hud hud
## Datos de muestra inyectados por señales del bus (los sistemas pueden seguir en stub).

const START_FLOOR := 3
const PHONE_WINDOW := Vector2i(1170, 540)
const SAMPLE_RANK := 1

var _ui: UIRoot
var _player: Node2D


func run(pilot: Autopilot) -> void:
	Database.load_all()
	_build_world()
	_ui = UIRoot.new()
	add_child(_ui)
	await pilot.frames(3)
	_apply_sample_state()
	await pilot.frames(6)
	await pilot.shot("hud_desktop")
	await _shot_clean(pilot)
	await _shot_debug(pilot)
	await _shot_inventory(pilot)
	await _shot_summary(pilot)
	await _shot_dialog(pilot)
	await _shot_contrast(pilot)
	await _shot_spanish(pilot)
	await _shot_glyphs(pilot)
	await _shot_phone(pilot)


func _build_world() -> void:
	var backdrop: OfficeBackdrop = OfficeBackdrop.new()
	add_child(backdrop)
	_player = Node2D.new()
	_player.name = "PreviewPlayer"
	_player.add_to_group("player")
	_player.position = Vector2(960, 560)
	add_child(_player)


func _apply_sample_state() -> void:
	var hud: HUD = _ui.get_hud()
	var occs: Array[OccupationData] = Database.get_occupations_by_rank(SAMPLE_RANK)
	if not occs.is_empty():
		EventBus.occupation_changed.emit("", occs[0].id, "preview")
	EventBus.floor_changed.emit(0, START_FLOOR)
	EventBus.money_changed.emit(1205, 1240, "wage")
	EventBus.reputation_changed.emit(0.0, 62.0)
	EventBus.suspicion_changed.emit(0.0, 38.0)
	EventBus.time_band_changed.emit("arrival", "work_morning")
	hud.freeze_clock(10, 42, 3)
	hud.set_duties(_sample_duties())
	hud.mark_duty("d_mail", HUD.STATUS_DONE)
	EventBus.duty_progressed.emit("d_copy", 0.4)
	_ui.set_context_action("HUDQA_PROMPT_DRAWER", "take")
	hud.set_zone_restricted(true, 3)
	_ui.set_camera_watch("cam_preview", true)
	EventBus.subtitle_posted.emit("HUDQA_SUB_FOOTSTEPS", _player.position + Vector2(-400, 80), 1)
	EventBus.subtitle_posted.emit("HUDQA_SUB_RADIO", _player.position + Vector2(300, -250), 2)
	EventBus.subtitle_posted.emit("HUDQA_SUB_HUM", Vector2.INF, 0)
	_ui.toast("HUD_TOAST_DUTY_DONE", [tr("DUTY_EMAILS_R1")], ToastStack.KIND_GOOD)


func _sample_duties() -> Array[Dictionary]:
	return [
		{"id": "d_mail", "name_key": "DUTY_EMAILS_R1", "type": "volume", "amount": 8, "deadline_hour": 18},
		{"id": "d_copy", "name_key": "DUTY_COPIES_R2", "type": "volume", "amount": 5, "deadline_hour": 17},
		{"id": "d_orders", "name_key": "DUTY_ORDERS_R2", "type": "volume", "amount": 3, "deadline_hour": 18},
		{"id": "d_mailround", "name_key": "DUTY_MAIL_ROUND_R4", "type": "round", "failed": true},
	]


func _shot_clean(pilot: Autopilot) -> void:
	var hud: HUD = _ui.get_hud()
	hud.set_zone_restricted(false)
	_ui.set_camera_watch("cam_preview", false)
	_ui.get_toasts().clear()
	_ui.get_subtitles().clear_lines()
	await pilot.seconds(2.0)
	await pilot.shot("hud_clean")


func _shot_debug(pilot: Autopilot) -> void:
	_ui.toggle_debug_panel()
	await pilot.frames(6)
	await pilot.shot("hud_debug")
	_ui.toggle_debug_panel()


## Dos capturas: junto a un escondite (tirar/esconder) y en el muelle (deshacerse de lo comprometedor).
func _shot_inventory(pilot: Autopilot) -> void:
	_ui.clear_context_action()
	_ui.open_inventory(_desk_spot_context())
	var inv: InventoryUI = _ui.get_top_modal() as InventoryUI
	inv.set_items(_sample_items())
	inv.select_slot(2)
	await pilot.frames(6)
	await pilot.shot("hud_inventory")
	_ui.close_modal()
	_ui.open_inventory({"room_id": InventoryUI.DISPOSAL_ROOM})
	inv = _ui.get_top_modal() as InventoryUI
	inv.set_items(_sample_items())
	inv.select_slot(3)
	await pilot.frames(6)
	await pilot.shot("hud_inventory_dock")
	_ui.close_modal()


## Primer escondite reversible de los datos (bajo mesa, taquilla…) como contexto del inventario.
func _desk_spot_context() -> Dictionary:
	for room: RoomData in Database.get_all_rooms():
		for spot: Dictionary in room.hiding_spots:
			var found: Dictionary = InventoryRules.find_spot(room.id, str(spot.get("id", "")))
			if not found.is_empty() and not InventoryRules.is_irreversible(str(found[InventoryRules.SPOT_LOCATION])):
				return {"room_id": room.id, "hide_spot_id": str(spot["id"])}
	return {}


func _sample_items() -> Array[ItemData]:
	var specs: Array[Array] = [
		["phone", 1], ["own_card", 1], ["food_basic", 3], ["lockpick", 1],
		["foreign_document", 2], ["product_pair", 4], ["cash_small", 1],
	]
	var items: Array[ItemData] = []
	for spec: Array in specs:
		var item: ItemData = Database.get_item(str(spec[0]))
		if item == null:
			item = ItemData.make(str(spec[0]), "ITEM_PHONE", ItemData.CATEGORY_ORDINARY)
		item.stack = int(spec[1])
		items.append(item)
	return items


func _shot_summary(pilot: Autopilot) -> void:
	EventBus.day_summary_ready.emit({
		"day": 3, "reputation": 62.0, "reputation_delta": 4.0, "suspicion": 38.0, "suspicion_delta": 11.0,
		"income_lines": [{"reason": "wage", "amount": 35}, {"reason": "sale", "amount": 120}],
		"expense_lines": [{"reason": "rent", "amount": 7}, {"reason": "breakfast", "amount": 5},
				{"reason": "dinner", "amount": 10}],
		"completed_duties": ["DUTY_EMAILS_R1", "DUTY_ORDERS_R2"], "missed_duties": ["DUTY_MAIL_ROUND_R4"],
	})
	await pilot.frames(6)
	await pilot.shot("hud_day_summary")
	_ui.close_modal()


func _shot_dialog(pilot: Autopilot) -> void:
	var options: Array = [{"text_key": "INVUI_DISPOSE", "danger": true}, "UI_CANCEL"]
	_ui.show_dialog("INVUI_CONFIRM_TITLE", "INVUI_CONFIRM_BODY", options, [tr("ITEM_LOCKPICK")])
	await pilot.frames(6)
	await pilot.shot("hud_dialog")
	_ui.close_modal()


func _shot_contrast(pilot: Autopilot) -> void:
	_ui.set_text_options(UITheme.TEXT_LARGE, true)
	_ui.get_hud().set_zone_restricted(true, 3)
	_ui.set_camera_watch("cam_preview", true)
	_ui.set_context_action("HUDQA_PROMPT_DRAWER", "take")
	EventBus.subtitle_posted.emit("HUDQA_SUB_FOOTSTEPS", _player.position + Vector2(-400, 80), 1)
	await pilot.frames(6)
	await pilot.shot("hud_contrast_large")


func _shot_spanish(pilot: Autopilot) -> void:
	TranslationServer.set_locale("es")
	_ui.set_text_options(UITheme.TEXT_MEDIUM, false)
	await pilot.frames(6)
	await pilot.shot("hud_spanish")
	TranslationServer.set_locale("en")


func _shot_phone(pilot: Autopilot) -> void:
	get_window().size = PHONE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	_ui.get_subtitles().clear_lines()
	_ui.set_context_action("HUDQA_PROMPT_DRAWER", UITheme.icon_for_interact_type("drawer"))
	await pilot.frames(10)
	await pilot.shot("hud_phone")
	_ui.get_virtual_controls().set_bar_open(true)
	await pilot.seconds(0.6)
	await pilot.shot("hud_phone_bar")
	_ui.get_virtual_controls().set_bar_open(false)
	_ui.set_context_action("UI_INTERACT_EAVESDROP_POINT", UITheme.icon_for_interact_type("eavesdrop_point"))
	_press_toggle(VirtualControls.SNEAK_ACTION)
	await pilot.seconds(0.6)
	await pilot.shot("hud_phone_sneak")


## Hoja de glifos del botón de acción (todos los tipos de interactivo) y de los conmutadores táctiles.
func _shot_glyphs(pilot: Autopilot) -> void:
	var sheet: GlyphSheet = GlyphSheet.new()
	_ui.open_modal(sheet, false)
	await pilot.frames(4)
	await pilot.shot("hud_glyphs")
	_ui.close_modal()


## Pulsa un conmutador táctil como lo haría un dedo (evento de toque en su centro).
func _press_toggle(action: String) -> void:
	var vc: VirtualControls = _ui.get_virtual_controls()
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = vc.get_toggle_center(action)
	touch.pressed = true
	vc.get_viewport().push_input(touch, true)


## Fondo de muestra: planta de oficina de la banda the_pit dibujada por código.
class OfficeBackdrop extends Node2D:
	const CELL := 48

	func _draw() -> void:
		var pal: Dictionary = UITheme.band_palette_for_floor(START_FLOOR)
		var outline: Color = Color(str(pal.get("outline", "#2c2f28")))
		draw_rect(Rect2(0, 0, 2400, 1400), Color(str(pal.get("carpet", "#7b8266"))))
		for x: int in range(0, 2400, CELL):
			draw_line(Vector2(x, 0), Vector2(x, 1400), Color(outline, 0.08), 1.0)
		for y: int in range(0, 1400, CELL):
			draw_line(Vector2(0, y), Vector2(2400, y), Color(outline, 0.08), 1.0)
		var corridor: Rect2 = Rect2(0, 470, 2400, 190)
		draw_rect(corridor, Color(str(pal.get("floor", "#8a8f7d"))))
		draw_rect(Rect2(0, 440, 2400, 30), Color(str(pal.get("wall", "#b5b8a8"))))
		draw_rect(Rect2(0, 440, 2400, 30), outline, false, 3.0)
		for i: int in 12:
			_desk(Vector2(140 + i * 190, 170), pal, outline)
			_desk(Vector2(140 + i * 190, 800), pal, outline)

	func _desk(pos: Vector2, pal: Dictionary, outline: Color) -> void:
		var top: Rect2 = Rect2(pos, Vector2(130, 70))
		draw_rect(top.grow(2), outline)
		draw_rect(top, Color(str(pal.get("furniture", "#d3c7a4"))))
		draw_rect(Rect2(pos + Vector2(40, 8), Vector2(50, 26)), outline)
		draw_rect(Rect2(pos + Vector2(44, 11), Vector2(42, 19)), Color(str(pal.get("window", "#a3b5a9"))))
		draw_circle(pos + Vector2(65, 105), 22, outline)
		draw_circle(pos + Vector2(65, 105), 19, Color(str(pal.get("accent", "#6d7a5c"))))


## Rejilla de glifos grandes en fichas planas (inspección visual del conjunto de iconos).
class GlyphSheet extends Control:
	const TILE := 96.0
	const GAP := 14.0
	const COLUMNS := 10

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _glyphs() -> Array[String]:
		var out: Array[String] = ["sneak", "crouch", "sprint", "hazard", "target"]
		for value: Variant in UITheme.INTERACT_ICONS.values():
			if not out.has(str(value)):
				out.append(str(value))
		return out

	func _draw() -> void:
		var glyphs: Array[String] = _glyphs()
		var rows: int = ceili(float(glyphs.size()) / COLUMNS)
		var total: Vector2 = Vector2(COLUMNS * (TILE + GAP) - GAP, rows * (TILE + GAP) - GAP)
		var origin: Vector2 = (size - total) * 0.5
		for i: int in glyphs.size():
			var cell: Vector2 = origin + Vector2(i % COLUMNS, i / COLUMNS) * (TILE + GAP)
			var tile: Rect2 = Rect2(cell, Vector2(TILE, TILE))
			draw_colored_polygon(UITheme.rounded_rect_points(tile, 16.0), UITheme.color("ink"))
			var inner: Rect2 = tile.grow(-TILE * 0.2)
			UITheme.draw_icon(self, glyphs[i], inner, UITheme.color("paper"), TILE * 0.05)
