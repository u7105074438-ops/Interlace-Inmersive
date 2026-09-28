# hud_case.gd — Cuerpo de test_hud: HUD por señales, deberes tachados, halo, subtítulos, avisos, pila modal, inventario, resumen y diálogos.
# PROPIETARIO DE: nada (actúa también como manejador de "soltar" del mundo para la prueba).
# ESCUCHA: nada.
extends TestCase

const HIGH_ROOM_CLEARANCE := 5
const FOOD := "food_basic"
const HOT_ITEM := "lockpick"
const SLOW_CLOCK := 0.5

var _ui: UIRoot
var _dropped: Array[String] = []


func run_case() -> void:
	var db_ok: bool = new_run()
	_ui = UIRoot.new()
	get_tree().root.add_child(_ui)
	await wait_frames(2)
	check(_ui.is_in_group(UIRoot.GROUP), "UIRoot joins group ui_root")
	check(UIRoot.find(get_tree()) == _ui, "UIRoot.find locates the root")
	_check_meters()
	_check_band_and_day()
	_check_occupation(db_ok)
	_check_duties()
	_check_zone_rule()
	_check_zone_signals(db_ok)
	_check_camera()
	await _check_subtitles()
	_check_toasts()
	_check_context_prompt()
	_check_modal_stack()
	await _check_dialog()
	await _check_dialog_cancel()
	await _check_foreign_pause()
	await _check_dialog_freed()
	await _check_touch_header()
	_check_inventory()
	await _check_hide_from_focus(db_ok)
	await _check_stack_actions(db_ok)
	await _check_drop_rules(db_ok)
	_check_clock_speed_setting()
	await _check_summary_fallback()
	_check_day_summary()
	await _check_subtitle_shapes()
	_check_bar_hides_prompt()
	_check_interact_icons(db_ok)
	_check_theme()
	_ui.queue_free()
	await wait_frames(1)


## Manejador de "soltar" del mundo (grupo InventoryUI.DROP_HANDLER_GROUP) para la prueba.
func drop_player_item(item_id: String) -> bool:
	_dropped.append(item_id)
	return PlayerState.remove_item(item_id)


## Lanza show_dialog en segundo plano; devuelve [resultado] (-2 mientras no resuelve) y el cuadro.
func _open_dialog(options: Array) -> Array:
	var result: Array[int] = [-2]
	var runner: Callable = func() -> void:
		result[0] = await _ui.show_dialog("INVUI_CONFIRM_TITLE", "", options)
	runner.call()
	await wait_frames(1)
	return [result, _ui.get_top_modal() as DialogBox]


func _check_meters() -> void:
	var hud: HUD = _ui.get_hud()
	EventBus.money_changed.emit(0, 1240, "wage")
	check_eq(hud.get_money_text(), UITheme.format_money(1240), "money label follows money_changed")
	check(hud.get_money_text().contains("1"), "money label shows the amount")
	EventBus.reputation_changed.emit(0.0, 62.0)
	check_near(hud.get_reputation_shown(), 62.0, 0.01, "reputation bar follows reputation_changed")
	EventBus.suspicion_changed.emit(0.0, 18.5)
	check_near(hud.get_suspicion_shown(), 18.5, 0.01, "suspicion bar follows suspicion_changed")
	EventBus.suspicion_changed.emit(18.5, 250.0)
	check_near(hud.get_suspicion_shown(), 100.0, 0.01, "suspicion bar clamps to 100")


func _check_band_and_day() -> void:
	var hud: HUD = _ui.get_hud()
	EventBus.time_band_changed.emit("arrival", "work_morning")
	check_eq(hud.get_band_text(), tr("HUD_TIMEBAND_WORK_MORNING"), "band label follows time_band_changed")
	hud.freeze_clock(13, 42, 3)
	check_eq(hud.get_clock_text(), "13:42", "frozen clock shows HH:MM")
	check(hud.get_day_text().contains("3"), "day label shows the day number")
	check(hud.get_day_text().contains(tr("HUD_WEEKDAY_2")), "day 3 is the third weekday")
	hud.unfreeze_clock()


func _check_occupation(db_ok: bool) -> void:
	var hud: HUD = _ui.get_hud()
	if not db_ok:
		check(true, "occupation check skipped (Database not loaded)")
		return
	var occ: OccupationData = Database.get_occupations_by_rank(1)[0]
	EventBus.occupation_changed.emit("", occ.id, "test")
	check_eq(hud.get_rank_text(), "R1", "rank chip follows occupation_changed")
	check_eq(hud.get_occupation_text(), tr(occ.name_key), "occupation name follows occupation_changed")


func _check_duties() -> void:
	var hud: HUD = _ui.get_hud()
	var duties: Array[Dictionary] = [
		{"id": "d_mail", "name_key": "DUTY_EMAILS_R1", "type": "volume", "amount": 8, "deadline_hour": 18},
		{"id": "d_copy", "name_key": "DUTY_COPIES_R2", "type": "volume", "amount": 3, "deadline_hour": 18},
		{"id": "d_done", "name_key": "DUTY_ORDERS_R2", "type": "volume", "completed": true},
	]
	hud.set_duties(duties)
	check(not hud.is_duty_struck("d_mail"), "pending duty is not struck")
	check(hud.is_duty_struck("d_done"), "duty flagged completed by PlayerState is struck")
	EventBus.duty_completed.emit("d_mail", 1.0, "honest")
	check(hud.is_duty_struck("d_mail"), "duty struck after duty_completed")
	check_eq(hud.get_duty_status("d_mail"), HUD.STATUS_DONE, "completed duty status")
	EventBus.duty_failed.emit("d_copy", "warning")
	check_eq(hud.get_duty_status("d_copy"), HUD.STATUS_FAILED, "failed duty status after duty_failed")
	check(not hud.is_duty_struck("d_copy"), "a failed duty is not struck like a completed one")
	hud.set_duties_collapsed(true)
	check(hud.is_duties_collapsed(), "duties list collapses")
	hud.set_duties_collapsed(false)


func _check_zone_rule() -> void:
	check(HUD.is_zone_forbidden(3, 1, [], []), "clearance 1 in a clearance-3 room is forbidden")
	check(not HUD.is_zone_forbidden(3, 3, [], []), "matching clearance is allowed")
	check(not HUD.is_zone_forbidden(3, 1, ["cleaning"], ["cleaning"]), "special access tag grants entry")


func _check_zone_signals(db_ok: bool) -> void:
	var hud: HUD = _ui.get_hud()
	var high: RoomData = null
	var low: RoomData = null
	if db_ok:
		for room: RoomData in Database.get_all_rooms():
			if room.special_access.is_empty() and room.clearance_required >= HIGH_ROOM_CLEARANCE and high == null:
				high = room
			if room.clearance_required <= 1 and low == null:
				low = room
	if high == null or low == null:
		hud.set_zone_restricted(true, HIGH_ROOM_CLEARANCE)
		check(hud.is_zone_restricted(), "halo toggles on (no room data)")
		hud.set_zone_restricted(false)
		check(not hud.is_zone_restricted(), "halo toggles off (no room data)")
		return
	EventBus.clearance_changed.emit(0, 1)
	EventBus.room_entered.emit(high.id, true)
	check(hud.is_zone_restricted(), "halo on in a room the clearance does not cover (%s)" % high.id)
	EventBus.room_entered.emit(low.id, false)
	check(hud.is_zone_restricted(), "NPC room_entered does not affect the halo")
	EventBus.room_entered.emit(low.id, true)
	check(not hud.is_zone_restricted(), "halo off in a covered room")
	EventBus.room_entered.emit(high.id, true)
	EventBus.clearance_changed.emit(1, OccupationData.MAX_CLEARANCE)
	check(not hud.is_zone_restricted(), "halo off after clearance rises")


func _check_camera() -> void:
	var hud: HUD = _ui.get_hud()
	check(not hud.is_camera_icon_visible(), "camera icon hidden by default")
	_ui.set_camera_watch("cam_1", true)
	check(hud.is_camera_icon_visible(), "camera icon while inside a camera field")
	_ui.set_camera_watch("cam_1", false)
	check(not hud.is_camera_icon_visible(), "camera icon hidden after leaving the field")
	EventBus.camera_recorded_player.emit("cam_2", "room", 1)
	check(hud.is_camera_icon_visible(), "camera icon pulses on camera_recorded_player")


func _check_subtitles() -> void:
	var feed: SubtitleFeed = _ui.get_subtitles()
	feed.clear_lines()
	EventBus.subtitle_posted.emit("HUDQA_SUB_FOOTSTEPS", Vector2.INF, 1)
	await wait_frames(1)
	check_eq(feed.get_line_count(), 1, "subtitle feed receives subtitle_posted")
	check(feed.get_line_text(0).contains(tr("HUDQA_SUB_FOOTSTEPS")), "subtitle shows the translated text")
	EventBus.subtitle_posted.emit("HUDQA_SUB_FOOTSTEPS", Vector2(100, 100), 1)
	check_eq(feed.get_line_count(), 1, "repeated subtitle is grouped")
	check(feed.get_line_text(0).contains("2"), "grouped subtitle shows the count")
	EventBus.subtitle_posted.emit("HUDQA_SUB_RADIO", Vector2.INF, 2)
	check_eq(feed.get_line_count(), 2, "different subtitle adds a line")
	feed.set_enabled(false)
	EventBus.subtitle_posted.emit("HUDQA_SUB_ELEVATOR", Vector2.INF, 0)
	check_eq(feed.get_line_count(), 0, "disabled subtitles show nothing")
	feed.set_enabled(true)


func _check_toasts() -> void:
	var stack: ToastStack = _ui.get_toasts()
	stack.clear()
	_ui.toast("HUD_TOAST_DUTY_DONE", ["X"], ToastStack.KIND_GOOD)
	check_eq(stack.get_toast_count(), 1, "toast() adds a toast")
	check(stack.get_toast_text(0).contains("X"), "toast formats its arguments")
	for i: int in 10:
		_ui.toast("HUD_TOAST_DUTY_DONE", [str(i)])
	check(stack.get_toast_count() <= UITheme.tune_int("interfaz.toast_max_visibles"), "toast stack is capped")


func _check_context_prompt() -> void:
	var prompt: ContextPrompt = _ui.get_hud().get_context_prompt()
	check(not prompt.has_action(), "no context prompt without an action")
	_ui.set_context_action("HUDQA_PROMPT_DRAWER", "take")
	check(prompt.has_action(), "context prompt appears when an action exists")
	check_eq(prompt.get_text(), tr("HUDQA_PROMPT_DRAWER"), "context prompt shows the action text")
	_ui.clear_context_action()
	check(not prompt.has_action(), "context prompt hides when the action disappears")


func _check_modal_stack() -> void:
	check(not _ui.has_modal(), "no modal at start")
	var first: PanelContainer = PanelContainer.new()
	var second: PanelContainer = PanelContainer.new()
	_ui.open_modal(first, true)
	check(_ui.has_modal(), "has_modal after open_modal")
	check(_ui.is_clock_paused_by_ui(), "pausing modal pauses the clock")
	_ui.open_modal(second, false)
	check_eq(_ui.get_modal_count(), 2, "modals stack")
	check(_ui.get_top_modal() == second, "last opened modal is on top")
	_ui.close_modal()
	check(_ui.get_top_modal() == first, "close_modal pops the top modal")
	check(_ui.is_clock_paused_by_ui(), "clock stays paused while a pausing modal remains")
	_ui.close_modal()
	check(not _ui.has_modal(), "stack empty after closing all")
	check(not _ui.is_clock_paused_by_ui(), "clock resumes when no pausing modal remains")


func _check_dialog() -> void:
	var result: Array[int] = [-2]
	var runner: Callable = func() -> void:
		result[0] = await _ui.show_dialog("INVUI_CONFIRM_TITLE", "INVUI_CONFIRM_BODY", ["UI_CANCEL", "INVUI_DROP", "INVUI_HIDE"], ["X"])
	runner.call()
	await wait_frames(2)
	var box: DialogBox = _ui.get_top_modal() as DialogBox
	check(box != null, "show_dialog opens a DialogBox")
	if box == null:
		return
	check_eq(box.get_option_count(), 3, "dialog shows every option")
	box.choose(2)
	await wait_frames(1)
	check_eq(result[0], 2, "show_dialog returns the chosen index")
	check(not _ui.has_modal(), "dialog closes after choosing")


func _check_dialog_cancel() -> void:
	var result: Array[int] = [-2]
	var runner: Callable = func() -> void:
		result[0] = await _ui.show_dialog("INVUI_CONFIRM_TITLE", "", ["UI_CANCEL"])
	runner.call()
	await wait_frames(1)
	_ui.close_modal()
	await wait_frames(1)
	check_eq(result[0], DialogBox.CANCEL, "closing a dialog from outside resolves with CANCEL")


func _check_inventory() -> void:
	_ui.open_inventory({"room_id": "trash_dock"})
	var inv: InventoryUI = _ui.get_top_modal() as InventoryUI
	check(inv != null, "open_inventory opens InventoryUI")
	if inv == null:
		return
	var items: Array[ItemData] = [
		ItemData.make("phone", "ITEM_PHONE", ItemData.CATEGORY_ORDINARY),
		ItemData.make("lockpick", "ITEM_LOCKPICK", ItemData.CATEGORY_COMPROMISING),
	]
	inv.set_items(items)
	check_eq(inv.get_slot_count(), InventoryUI.SLOTS, "inventory has eight slots")
	check(not inv.is_slot_compromising(0) and inv.is_slot_compromising(1), "compromising items are flagged")
	check(inv.can_dispose(), "disposal allowed at the trash dock")
	check(not inv.can_hide(), "hide disabled without a hiding spot")
	_ui.open_inventory()
	check(not _ui.has_modal(), "inventory key toggles the inventory closed")


func _check_day_summary() -> void:
	EventBus.day_summary_ready.emit({"day": 2, "income_lines": [{"reason": "wage", "amount": 35}],
			"expense_lines": [{"reason": "rent", "amount": 7}], "missed_duties": ["DUTY_COPIES_R2"]})
	var view: DaySummary = _ui.get_top_modal() as DaySummary
	check(view != null, "day_summary_ready opens the day summary")
	if view == null:
		return
	check_eq(int(view.get_summary().get("day", 0)), 2, "summary keeps the provided day")
	check(view.get_summary().has("reputation_delta"), "summary is completed by the day tracker")
	view.request_close()
	check(not _ui.has_modal(), "summary closes with its continue action")


func _check_theme() -> void:
	var small: Theme = UITheme.build(UITheme.TEXT_SMALL, false)
	var large: Theme = UITheme.build(UITheme.TEXT_LARGE, true)
	check(large.default_font_size > small.default_font_size, "large text level has a bigger base font")
	check(UITheme.current_high_contrast, "high contrast flag recorded")
	check(large.get_color("paper", UITheme.HUD_TYPE) != small.get_color("paper", UITheme.HUD_TYPE)
			or large.get_color("panel", UITheme.HUD_TYPE) != small.get_color("panel", UITheme.HUD_TYPE),
			"high contrast palette differs")
	_ui.set_text_options(UITheme.TEXT_MEDIUM, false)
	check(not UITheme.current_high_contrast, "set_text_options restores normal contrast")


func _check_foreign_pause() -> void:
	GameClock.pause()
	var opened: Array = await _open_dialog(["UI_CANCEL", "INVUI_DROP"])
	var box: DialogBox = opened[1]
	check(box != null, "dialog opens while another system holds the pause")
	if box != null:
		box.choose(1)
	await wait_frames(1)
	check_eq(int((opened[0] as Array)[0]), 1, "dialog still returns the chosen index")
	check(GameClock.is_paused(), "closing a dialog keeps a pause set by another system")
	GameClock.resume()
	_ui.open_modal(PanelContainer.new(), true)
	check(GameClock.is_paused(), "a pausing modal pauses a running clock")
	_ui.close_modal()
	check(not GameClock.is_paused(), "UIRoot resumes only the pause it set itself")
	GameClock.pause()


func _check_dialog_freed() -> void:
	var opened: Array = await _open_dialog([{"text_key": "INVUI_DISPOSE", "danger": true}, "UI_CANCEL"])
	var box: DialogBox = opened[1]
	check(box != null and box.get_default_index() == 1, "focus starts on the safe option, not the danger one")
	if box == null:
		return
	box.queue_free()
	await wait_frames(2)
	check_eq(int((opened[0] as Array)[0]), DialogBox.CANCEL, "a dialog freed without a choice resolves CANCEL")
	check(not _ui.has_modal(), "a freed dialog leaves the modal stack")


## Un toque llega como InputEventScreenTouch y como clic emulado: la lista debe alternar una vez.
func _check_touch_header() -> void:
	var hud: HUD = _ui.get_hud()
	hud.set_duties_collapsed(true)
	await wait_frames(2)
	var pos: Vector2 = hud.get_duties_header().get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.position = pos
		touch.pressed = pressed
		get_viewport().push_input(touch, true)
		if UITheme.touch_emulates_mouse():
			var click: InputEventMouseButton = InputEventMouseButton.new()
			click.device = InputEvent.DEVICE_ID_EMULATION
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = pos
			click.global_position = pos
			get_viewport().push_input(click, true)
	await wait_frames(1)
	check(not hud.is_duties_collapsed(), "one tap (touch + emulated click) expands the duties list")
	hud.set_duties_collapsed(false)


func _hiding_spot_sample() -> Array[String]:
	for room: RoomData in Database.get_all_rooms():
		for spot: Dictionary in room.hiding_spots:
			var found: Dictionary = InventoryRules.find_spot(room.id, str(spot.get("id", "")))
			if not found.is_empty() and not InventoryRules.is_irreversible(str(found[InventoryRules.SPOT_LOCATION])):
				return [room.id, str(spot["id"])]
	return []


func _check_hide_from_focus(db_ok: bool) -> void:
	var sample: Array[String] = _hiding_spot_sample() if db_ok else []
	if sample.is_empty():
		check(true, "hide-from-focus check skipped (no hiding spot data)")
		return
	var spot: HidingSpot = HidingSpot.new()
	spot.setup_spot({"id": sample[1], "type": "under_desk", "capacity": 1}, sample[0], 48.0, Vector2.ZERO)
	get_tree().root.add_child(spot)
	_ui.show_interactable(spot)
	_ui.open_inventory()
	var inv: InventoryUI = _ui.get_top_modal() as InventoryUI
	check(inv != null and inv.can_hide(), "I key next to a focused hiding spot enables Hide")
	_ui.close_modal()
	_ui.show_interactable(null)
	_ui.open_inventory()
	inv = _ui.get_top_modal() as InventoryUI
	check(inv != null and not inv.can_hide(), "without a focused hiding spot Hide stays disabled")
	_ui.close_modal()
	spot.queue_free()
	await wait_frames(1)


## Tres unidades apiladas: una acción retira una unidad y la vista sigue mostrando las otras dos.
func _check_stack_actions(db_ok: bool) -> void:
	if not db_ok:
		check(true, "stack check skipped (Database not loaded)")
		return
	for _i: int in 3:
		PlayerState.add_item(FOOD)
	_ui.open_inventory({"room_id": InventoryUI.DISPOSAL_ROOM})
	var inv: InventoryUI = _ui.get_top_modal() as InventoryUI
	await wait_frames(1)
	inv.action_requested.emit(InventoryUI.ACTION_DISPOSE, FOOD)
	await wait_frames(1)
	var box: DialogBox = _ui.get_top_modal() as DialogBox
	check(box != null, "disposing asks for confirmation first")
	if box != null:
		box.choose(0)
	await wait_frames(1)
	check_eq(PlayerState.get_item_count(FOOD), 2, "dispose removes exactly one unit")
	check_eq(_view_count(inv, FOOD), 2, "the inventory view keeps the rest of the stack")
	var injected: Array[ItemData] = [ItemData.make(FOOD, "ITEM_FOOD_BASIC", ItemData.CATEGORY_ORDINARY)]
	injected[0].stack = 3
	inv.set_items(injected)
	inv.note_unit_removed(FOOD)
	check_eq(_view_count(inv, FOOD), 2, "injected view discounts one unit, not the whole stack")
	_ui.close_modal()


func _view_count(inv: InventoryUI, item_id: String) -> int:
	for item: ItemData in inv.get_items():
		if item.id == item_id:
			return item.stack
	return 0


func _check_drop_rules(db_ok: bool) -> void:
	if not db_ok:
		check(true, "drop check skipped (Database not loaded)")
		return
	PlayerState.add_item(HOT_ITEM)
	_ui.open_inventory({"room_id": "reception"})
	var inv: InventoryUI = _ui.get_top_modal() as InventoryUI
	var hot: ItemData = ItemData.make(HOT_ITEM, "ITEM_LOCKPICK", ItemData.CATEGORY_COMPROMISING)
	check(not inv.can_drop_item(hot), "without a world drop handler a compromising item cannot be dropped")
	await _discard_food(inv)
	add_to_group(InventoryUI.DROP_HANDLER_GROUP)
	check(inv.can_drop_item(hot), "a world drop handler allows dropping compromising items")
	inv.action_requested.emit(InventoryUI.ACTION_DROP, HOT_ITEM)
	await wait_frames(1)
	check(_dropped.has(HOT_ITEM) and not _ui.get_top_modal() is DialogBox, "drop goes to the world handler")
	remove_from_group(InventoryUI.DROP_HANDLER_GROUP)
	_ui.close_modal()


## Sin manejador, tirar un objeto ordinario pide confirmación y deja rastro (item_disposed).
func _discard_food(inv: InventoryUI) -> void:
	var before: int = PlayerState.get_item_count(FOOD)
	var methods: Array[String] = []
	var spy: Callable = func(_id: String, method: String) -> void: methods.append(method)
	EventBus.item_disposed.connect(spy)
	inv.action_requested.emit(InventoryUI.ACTION_DROP, FOOD)
	await wait_frames(1)
	var box: DialogBox = _ui.get_top_modal() as DialogBox
	check(box != null, "throwing away an ordinary item asks for confirmation")
	if box != null:
		box.choose(1)
	await wait_frames(1)
	check_eq(PlayerState.get_item_count(FOOD), before, "cancelling keeps the item")
	inv.action_requested.emit(InventoryUI.ACTION_DROP, FOOD)
	await wait_frames(1)
	box = _ui.get_top_modal() as DialogBox
	if box != null:
		box.choose(0)
	await wait_frames(1)
	EventBus.item_disposed.disconnect(spy)
	check_eq(PlayerState.get_item_count(FOOD), before - 1, "confirming throws one unit away")
	check(methods.has(UIRoot.DISCARD_METHOD), "throwing away leaves a trace (item_disposed)")


## El perfil (SaveSystem) es la fuente que leen SettingsMenu.get_value y UIRoot.
func _check_clock_speed_setting() -> void:
	SaveSystem.set_setting("clock_speed", SLOW_CLOCK)
	_ui.apply_settings()
	check_near(GameClock.get_accessibility_speed(), SLOW_CLOCK, 0.001, "clock_speed setting reaches GameClock")
	SaveSystem.set_setting("clock_speed", 1.0)
	_ui.apply_settings()


func _check_summary_fallback() -> void:
	var day: int = GameClock.get_day()
	GameClock.advance_to_next_day()
	await wait_frames(2)
	var view: DaySummary = _ui.get_top_modal() as DaySummary
	check(view != null, "a day change without day_summary_ready still shows the summary")
	if view != null:
		check_eq(int(view.get_summary().get("day", 0)), day, "fallback summary covers the closed day")
		view.request_close()
	EventBus.day_summary_ready.emit({"day": GameClock.get_day()})
	GameClock.advance_to_next_day()
	await wait_frames(2)
	check_eq(_ui.get_modal_count(), 1, "no duplicate summary when day_summary_ready already came")
	while _ui.has_modal():
		_ui.close_modal()


func _check_subtitle_shapes() -> void:
	var feed: SubtitleFeed = _ui.get_subtitles()
	feed.clear_lines()
	EventBus.subtitle_posted.emit("HUDQA_SUB_HUM", Vector2.INF, 0)
	EventBus.subtitle_posted.emit("HUDQA_SUB_RADIO", Vector2.INF, 2)
	check(not feed.line_has_hazard_glyph(0) and feed.line_has_hazard_glyph(1), "danger subtitles carry a hazard glyph")
	TranslationServer.set_locale("es")
	await wait_frames(2)
	check(feed.get_line_text(0).contains(tr("HUDQA_SUB_HUM")), "visible subtitles are retranslated")
	TranslationServer.set_locale("en")
	await wait_frames(2)
	feed.clear_lines()


func _check_bar_hides_prompt() -> void:
	var prompt: ContextPrompt = _ui.get_hud().get_context_prompt()
	_ui.set_touch_mode(true)
	_ui.set_context_action("HUDQA_PROMPT_DRAWER", "take")
	_ui.get_virtual_controls().set_bar_open(true)
	check(prompt.has_action() and not prompt.is_shown(), "open bottom bar hides the context prompt")
	_ui.get_virtual_controls().set_bar_open(false)
	check(prompt.is_shown(), "closing the bar brings the prompt back")
	_ui.clear_context_action()
	_ui.set_touch_mode(false)


func _check_interact_icons(db_ok: bool) -> void:
	check_eq(UITheme.icon_for_interact_type("ceo_safe"), "safe", "safes get the safe glyph")
	check_eq(UITheme.icon_for_interact_type("eavesdrop_point"), "ear", "eavesdrop points get the ear glyph")
	check_eq(UITheme.icon_for_interact_type("payroll_terminal"), "computer", "*_terminal maps to the computer")
	if not db_ok:
		return
	var generic: Array[String] = []
	for room: RoomData in Database.get_all_rooms():
		for entry: Dictionary in room.interactables:
			if UITheme.icon_for_interact_type(str(entry.get("type", ""))) == "target":
				generic.append(str(entry.get("type", "")))
	check(generic.is_empty(), "every interactable type in the data has its own glyph %s" % [generic])
