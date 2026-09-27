# hud.gd — HUD mínimo de §13.1 (reloj, capital, rango + reputación/sospecha, deberes, acción)
#          y superposiciones de §13.2 (halo rojo de zona no acreditada, icono de cámara).
# PROPIETARIO DE: la presentación del HUD, el estado plegado de deberes y las marcas de deber del día.
# ESCUCHA: money_changed, reputation_changed, suspicion_changed, occupation_changed, clearance_changed,
#          time_band_changed, day_advanced, duty_assigned/completed/failed/progressed, room_entered,
#          floor_changed, disguise_changed, camera_recorded_player, run_started, run_loaded.
class_name HUD
extends Control

## Lee getters de PlayerState/GameClock/Database al refrescar y usa los valores de las señales
## en cuanto llegan (trabajo por fotograma: solo comparar hora/minuto del reloj).
## Posiciones (§13.1): sup. izq. reloj+jornada · sup. der. capital · inf. izq. rango + barra doble
## (reputación AZUL lisa / sospecha ROJA rayada) · inf. der. deberes plegables (tachados al
## cumplirse) · centro inf. acción contextual (solo si existe).

const STATUS_PENDING := "pending"
const STATUS_DONE := "completed"
const STATUS_FAILED := "failed"
const MARGIN := 28
const ACCENT_BAR_W := 5
const PANEL_GAP := 10
const TOUCH_DUTIES_LIFT_RADII := 2.9
const WEEKDAY_KEY := "HUD_WEEKDAY_%d"
const BAND_KEY := "HUD_TIMEBAND_%s"
const PLAYER_ID := "player"

var _money: int = 0
var _reputation: float = 0.0
var _suspicion: float = 0.0
var _band: String = ""
var _day: int = 0
var _hour: int = -1
var _minute: int = -1
var _clock_frozen: bool = false
var _occupation_id: String = ""
var _clearance: int = 0
var _room_id: String = ""
var _floor: int = 0
var _accent: Color = Color.WHITE
var _duties: Array[Dictionary] = []
var _duty_marks: Dictionary = {}
var _duty_progress: Dictionary = {}
var _duties_collapsed: bool = false
var _restricted: bool = false
var _required_clearance: int = 0
var _watching_cameras: Dictionary = {}
var _camera_pulse: float = 0.0
var _blink: float = 0.0
var _touch_layout: bool = false

var _clock_label: Label
var _day_label: Label
var _band_label: Label
var _accent_bar: ColorRect
var _clock_panel: PanelContainer
var _money_panel: PanelContainer
var _money_label: Label
var _money_delta: Label
var _meters_panel: PanelContainer
var _rank_chip: PanelContainer
var _rank_label: Label
var _occ_label: Label
var _rep_bar: UITheme.MeterBar
var _rep_value: Label
var _sus_bar: UITheme.MeterBar
var _sus_value: Label
var _duties_panel: PanelContainer
var _duties_header: HBoxContainer
var _duties_count: Label
var _duties_chevron: UITheme.IconView
var _duties_list: VBoxContainer
var _prompt: ContextPrompt
var _halo: HaloOverlay
var _status_row: HBoxContainer
var _restricted_pill: PanelContainer
var _restricted_detail: Label
var _camera_pill: PanelContainer
var _camera_dot: UITheme.IconView


func _init() -> void:
	name = "HUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_halo = HaloOverlay.new()
	add_child(_halo)
	_build_clock()
	_build_money()
	_build_meters()
	_build_duties()
	_build_status()
	_prompt = ContextPrompt.new()
	_place(_prompt, Control.PRESET_CENTER_BOTTOM)


func _ready() -> void:
	_connect_bus()
	refresh_all()


# ─── API pública ───────────────────────────────────────────────────

## Vuelve a leer todo el estado de los sistemas (inicio o carga de partida).
func refresh_all() -> void:
	set_money(PlayerState.get_money())
	set_reputation(PlayerState.get_reputation())
	set_suspicion(PlayerState.get_suspicion())
	var occ: OccupationData = PlayerState.get_occupation()
	set_occupation(occ.id if occ != null else "")
	_clearance = _current_clearance()
	set_time_band(GameClock.get_current_band())
	set_day(GameClock.get_day())
	_hour = -1
	_room_id = str(_call_or(PlayerState, "get_room", ""))
	set_floor(int(_call_or(PlayerState, "get_floor", _floor)))
	set_duties(PlayerState.get_todays_duties())
	_evaluate_zone()


func set_money(value: int) -> void:
	_money = value
	_money_label.text = UITheme.format_money(value)


func set_reputation(value: float) -> void:
	_reputation = value
	_rep_bar.set_value(value)
	_rep_value.text = str(roundi(value))


func set_suspicion(value: float) -> void:
	_suspicion = value
	_sus_bar.set_value(value)
	_sus_value.text = str(roundi(value))


func set_time_band(band: String) -> void:
	_band = band
	_band_label.text = UITheme.trf(BAND_KEY % band.to_upper()).to_upper() if not band.is_empty() else ""
	_band_label.visible = not band.is_empty()


func set_day(day: int) -> void:
	_day = day
	var per_week: int = maxi(UITheme.tune_int("tiempo.jornadas_por_semana"), 1)
	var weekday: String = UITheme.trf(WEEKDAY_KEY % posmod(day - 1, per_week))
	_day_label.text = UITheme.trf("HUD_DAY_FMT", [day, weekday]).to_upper()


## Ocupación mostrada (rango y nombre del puesto) a partir de su id de occupations.json.
func set_occupation(occupation_id: String) -> void:
	_occupation_id = occupation_id
	var occ: OccupationData = Database.get_occupation(occupation_id) if not occupation_id.is_empty() else null
	var rank: int = occ.rank if occ != null else PlayerState.get_rank()
	_rank_label.text = UITheme.trf("HUD_RANK_FMT", [rank])
	_occ_label.text = UITheme.trf(occ.name_key).to_upper() if occ != null else ""
	_occ_label.visible = occ != null


func set_floor(floor_number: int) -> void:
	_floor = floor_number
	_accent = UITheme.band_accent_for_floor(floor_number)
	_accent_bar.color = _accent
	_style_rank_chip()


## Congela el reloj en una hora dada (vistas previas y capturas); unfreeze_clock() lo libera.
func freeze_clock(hour: int, minute: int, day: int) -> void:
	_clock_frozen = true
	_clock_label.text = UITheme.format_hour(hour, minute)
	set_day(day)


func unfreeze_clock() -> void:
	_clock_frozen = false
	_hour = -1


func set_duties(duties: Array[Dictionary]) -> void:
	_duties = duties.duplicate(true)
	_rebuild_duties()


## Marca local de estado de un deber: STATUS_DONE / STATUS_FAILED / STATUS_PENDING.
func mark_duty(duty_id: String, status: String) -> void:
	_duty_marks[duty_id] = status
	_rebuild_duties()


func get_duty_status(duty_id: String) -> String:
	if _duty_marks.has(duty_id):
		return str(_duty_marks[duty_id])
	for duty: Dictionary in _duties:
		if str(duty.get("id", "")) == duty_id:
			return duty_status(duty)
	return ""


func is_duty_struck(duty_id: String) -> bool:
	var status: String = get_duty_status(duty_id)
	return status == STATUS_DONE or status == STATUS_FAILED


func set_duties_collapsed(collapsed: bool) -> void:
	_duties_collapsed = collapsed
	_duties_list.visible = not collapsed
	_duties_chevron.set_icon("chevron_up" if collapsed else "chevron_down")


func is_duties_collapsed() -> bool:
	return _duties_collapsed


func set_context_action(prompt_key: String, icon_id: String = "target", args: Array = []) -> void:
	_prompt.show_action(prompt_key, icon_id, args)


func clear_context_action() -> void:
	_prompt.hide_action()


func get_context_prompt() -> ContextPrompt:
	return _prompt


## Halo rojo perimetral + distintivo "zona restringida" (forma y color, §13.2/§13.10).
func set_zone_restricted(active: bool, required_clearance: int = 0) -> void:
	_restricted = active
	_required_clearance = required_clearance
	_halo.set_active(active)
	_restricted_pill.visible = active
	_restricted_detail.text = UITheme.trf("HUD_CLEARANCE_REQUIRED", [required_clearance])


func is_zone_restricted() -> bool:
	return _restricted


## Una cámara informa de que el jugador entra (true) o sale (false) de su campo.
func set_camera_watch(camera_id: String, inside: bool) -> void:
	if inside:
		_watching_cameras[camera_id] = true
	else:
		_watching_cameras.erase(camera_id)
	_refresh_camera_pill()


func is_camera_icon_visible() -> bool:
	return _camera_pill.visible


## Disposición táctil: los deberes suben por encima del grupo de botones de VirtualControls.
func set_touch_layout(on: bool) -> void:
	_touch_layout = on
	_prompt.set_touch_mode(on)
	var lift: float = UITheme.tune("interfaz.stick_radio") * TOUCH_DUTIES_LIFT_RADII if on else 0.0
	_duties_panel.offset_bottom = -MARGIN - lift
	_duties_panel.offset_top = _duties_panel.offset_bottom - _duties_panel.get_combined_minimum_size().y
	if on:
		set_duties_collapsed(true)


func get_meters_rect() -> Rect2:
	return _meters_panel.get_rect()


# Lectura para pruebas y herramientas.
func get_money_text() -> String:
	return _money_label.text


func get_clock_text() -> String:
	return _clock_label.text


func get_day_text() -> String:
	return _day_label.text


func get_band_text() -> String:
	return _band_label.text


func get_rank_text() -> String:
	return _rank_label.text


func get_occupation_text() -> String:
	return _occ_label.text


func get_reputation_shown() -> float:
	return _rep_bar.value


func get_suspicion_shown() -> float:
	return _sus_bar.value


## Estado de un diccionario de deber de PlayerState (tolerante a varias convenciones).
static func duty_status(duty: Dictionary) -> String:
	var status: String = str(duty.get("status", ""))
	if status == STATUS_FAILED or bool(duty.get("failed", false)):
		return STATUS_FAILED
	if status == STATUS_DONE or status == "done" or bool(duty.get("completed", false)):
		return STATUS_DONE
	return STATUS_PENDING


## Regla del halo: la acreditación no cubre la sala y ninguna etiqueta de acceso especial coincide.
static func is_zone_forbidden(required: int, clearance: int, room_access: Array, player_access: Array) -> bool:
	if required <= clearance:
		return false
	for tag: Variant in room_access:
		if player_access.has(tag):
			return false
	return true


# ─── Construcción ──────────────────────────────────────────────────

func _place(ctrl: Control, preset: Control.LayoutPreset) -> void:
	add_child(ctrl)
	ctrl.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, MARGIN)
	var right: bool = preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT
	var center: bool = preset == Control.PRESET_CENTER_TOP or preset == Control.PRESET_CENTER_BOTTOM
	var bottom: bool = preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_CENTER_BOTTOM]
	ctrl.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else (
			Control.GROW_DIRECTION_BOTH if center else Control.GROW_DIRECTION_END)
	ctrl.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END


func _panel(variation: String = UITheme.V_PANEL) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _label(variation: String, text: String = "") -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_clock() -> void:
	_clock_panel = _panel()
	var row: HBoxContainer = HBoxContainer.new()
	_clock_panel.add_child(row)
	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(ACCENT_BAR_W, 0)
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_accent_bar)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	_clock_label = _label(UITheme.V_CLOCK, UITheme.format_hour(0, 0))
	column.add_child(_clock_label)
	_day_label = _label(UITheme.V_CAPTION)
	column.add_child(_day_label)
	_band_label = _label(UITheme.V_CAPTION)
	column.add_child(_band_label)
	_place(_clock_panel, Control.PRESET_TOP_LEFT)


func _build_money() -> void:
	_money_panel = _panel()
	var row: HBoxContainer = HBoxContainer.new()
	_money_panel.add_child(row)
	row.add_child(UITheme.IconView.new("coin", "hazard", 1.3))
	_money_label = _label(UITheme.V_NUMBER, UITheme.format_money(0))
	row.add_child(_money_label)
	_place(_money_panel, Control.PRESET_TOP_RIGHT)
	_money_delta = _label(UITheme.V_STRONG)
	_money_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_delta.modulate.a = 0.0
	_place(_money_delta, Control.PRESET_TOP_RIGHT)


func _build_meters() -> void:
	_meters_panel = _panel()
	var column: VBoxContainer = VBoxContainer.new()
	_meters_panel.add_child(column)
	var head: HBoxContainer = HBoxContainer.new()
	column.add_child(head)
	_rank_chip = _panel(UITheme.V_PILL)
	_rank_label = _label(UITheme.V_STRONG)
	_rank_chip.add_child(_rank_label)
	head.add_child(_rank_chip)
	_occ_label = _label(UITheme.V_CAPTION)
	_occ_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_occ_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	column.add_child(grid)
	_rep_bar = UITheme.MeterBar.new("rep", "rep_track", false)
	_rep_value = _meter_row(grid, "shield", "rep", "HUD_REPUTATION", _rep_bar)
	_sus_bar = UITheme.MeterBar.new("sus", "sus_track", true)
	_sus_value = _meter_row(grid, "eye", "sus", "HUD_SUSPICION", _sus_bar)
	_place(_meters_panel, Control.PRESET_BOTTOM_LEFT)


func _meter_row(grid: GridContainer, icon: String, color_name: String, key: String,
		bar: UITheme.MeterBar) -> Label:
	grid.add_child(UITheme.IconView.new(icon, color_name))
	var caption: Label = _label(UITheme.V_CAPTION, UITheme.trf(key).to_upper())
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(caption)
	grid.add_child(bar)
	var value: Label = _label(UITheme.V_STRONG, "0")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size.x = 44
	grid.add_child(value)
	return value


func _build_duties() -> void:
	_duties_panel = _panel()
	_duties_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var column: VBoxContainer = VBoxContainer.new()
	_duties_panel.add_child(column)
	_duties_header = HBoxContainer.new()
	_duties_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_duties_header.gui_input.connect(_on_duties_header_input)
	column.add_child(_duties_header)
	_duties_header.add_child(UITheme.IconView.new("clipboard", "paper"))
	var title: Label = _label(UITheme.V_CAPTION, UITheme.trf("HUD_DUTIES").to_upper())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duties_header.add_child(title)
	_duties_count = _label(UITheme.V_STRONG)
	_duties_header.add_child(_duties_count)
	_duties_chevron = UITheme.IconView.new("chevron_down", "muted", 0.8)
	_duties_header.add_child(_duties_chevron)
	_duties_list = VBoxContainer.new()
	_duties_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_duties_list)
	_place(_duties_panel, Control.PRESET_BOTTOM_RIGHT)


func _build_status() -> void:
	_status_row = HBoxContainer.new()
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_restricted_pill = _panel(UITheme.V_DANGER_PILL)
	var row: HBoxContainer = HBoxContainer.new()
	_restricted_pill.add_child(row)
	row.add_child(UITheme.IconView.new("no_entry", "paper"))
	row.add_child(_label(UITheme.V_STRONG, UITheme.trf("HUD_RESTRICTED").to_upper()))
	_restricted_detail = _label(UITheme.V_SMALL)
	_restricted_detail.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(_restricted_detail)
	_restricted_pill.visible = false
	_status_row.add_child(_restricted_pill)
	_camera_pill = _panel(UITheme.V_PILL)
	var cam_row: HBoxContainer = HBoxContainer.new()
	_camera_pill.add_child(cam_row)
	cam_row.add_child(UITheme.IconView.new("camera", "paper"))
	_camera_dot = UITheme.IconView.new("target", "danger", 0.55)
	cam_row.add_child(_camera_dot)
	cam_row.add_child(_label(UITheme.V_STRONG, UITheme.trf("HUD_ON_CAMERA").to_upper()))
	_camera_pill.visible = false
	_status_row.add_child(_camera_pill)
	_place(_status_row, Control.PRESET_CENTER_TOP)


# ─── Deberes ───────────────────────────────────────────────────────

func _rebuild_duties() -> void:
	for child: Node in _duties_list.get_children():
		child.queue_free()
	var done: int = 0
	for duty: Dictionary in _duties:
		var status: String = get_duty_status(str(duty.get("id", "")))
		if status == STATUS_DONE:
			done += 1
		_duties_list.add_child(_duty_row(duty, status))
	if _duties.is_empty():
		_duties_list.add_child(_label(UITheme.V_SMALL, UITheme.trf("HUD_NO_DUTIES")))
	_duties_count.text = "%d/%d" % [done, _duties.size()]


func _duty_row(duty: Dictionary, status: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icons: Dictionary = {STATUS_DONE: "check", STATUS_FAILED: "cross", STATUS_PENDING: "box"}
	var colors: Dictionary = {STATUS_DONE: "gain", STATUS_FAILED: "loss", STATUS_PENDING: "paper"}
	row.add_child(UITheme.IconView.new(str(icons[status]), str(colors[status]), 0.85))
	var name_label: UITheme.StrikeLabel = UITheme.StrikeLabel.new()
	name_label.text = UITheme.trf(str(duty.get("name_key", duty.get("id", ""))))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.set_meta("duty_id", str(duty.get("id", "")))
	if status != STATUS_PENDING:
		name_label.add_theme_color_override("font_color", UITheme.color("muted"))
		name_label.set_struck(true, "muted" if status == STATUS_DONE else "loss")
	row.add_child(name_label)
	var detail: String = _duty_detail(duty, status)
	if not detail.is_empty():
		row.add_child(_label(UITheme.V_SMALL, detail))
	return row


func _duty_detail(duty: Dictionary, status: String) -> String:
	if status != STATUS_PENDING:
		return ""
	var id: String = str(duty.get("id", ""))
	var amount: int = int(duty.get("amount", 0))
	var progress: float = float(_duty_progress.get(id, duty.get("progress", 0.0)))
	if amount > 1 and progress > 0.0:
		return "%d/%d" % [roundi(progress * amount), amount]
	if duty.has("deadline_hour"):
		return UITheme.format_hour(int(duty["deadline_hour"]))
	return ""


func _on_duties_header_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if tap or click:
		set_duties_collapsed(not _duties_collapsed)
		_duties_header.accept_event()


# ─── Señales ───────────────────────────────────────────────────────

func _connect_bus() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.suspicion_changed.connect(_on_suspicion_changed)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.clearance_changed.connect(_on_clearance_changed)
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.duty_assigned.connect(_on_duty_assigned)
	EventBus.duty_completed.connect(_on_duty_completed)
	EventBus.duty_failed.connect(_on_duty_failed)
	EventBus.duty_progressed.connect(_on_duty_progressed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.disguise_changed.connect(_on_disguise_changed)
	EventBus.camera_recorded_player.connect(_on_camera_recorded)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_loaded.connect(_on_run_loaded)


func _on_money_changed(old_value: int, new_value: int, _reason: String) -> void:
	set_money(new_value)
	_show_money_delta(new_value - old_value)


func _on_reputation_changed(_old_value: float, new_value: float) -> void:
	set_reputation(new_value)


func _on_suspicion_changed(_old_value: float, new_value: float) -> void:
	set_suspicion(new_value)


func _on_occupation_changed(_old_id: String, new_id: String, _reason: String) -> void:
	set_occupation(new_id)
	_clearance = _current_clearance()
	var fresh: Array[Dictionary] = PlayerState.get_todays_duties()
	if not fresh.is_empty():
		set_duties(fresh)
	_evaluate_zone()


func _on_clearance_changed(_old_level: int, new_level: int) -> void:
	_clearance = new_level
	_evaluate_zone()


func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	set_time_band(new_band)


func _on_day_advanced(day_number: int) -> void:
	set_day(day_number)
	_duty_marks.clear()
	_duty_progress.clear()
	set_duties(PlayerState.get_todays_duties())


func _on_duty_assigned(_duty_id: String, _duty_type: String, _deadline_hour: int) -> void:
	var fresh: Array[Dictionary] = PlayerState.get_todays_duties()
	if not fresh.is_empty():
		set_duties(fresh)


func _on_duty_completed(duty_id: String, _quality: float, _method: String) -> void:
	mark_duty(duty_id, STATUS_DONE)


func _on_duty_failed(duty_id: String, _consequence: String) -> void:
	mark_duty(duty_id, STATUS_FAILED)


func _on_duty_progressed(duty_id: String, progress: float) -> void:
	_duty_progress[duty_id] = progress
	_rebuild_duties()


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		_room_id = room_id
		_evaluate_zone()


func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	set_floor(new_floor)


func _on_disguise_changed(_uniform_id: String) -> void:
	_evaluate_zone()


func _on_camera_recorded(_camera_id: String, _room_id: String, _day: int) -> void:
	_camera_pulse = UITheme.tune("interfaz.camara_icono_segundos")
	_refresh_camera_pill()


func _on_run_started(_run_seed: int) -> void:
	_duty_marks.clear()
	_duty_progress.clear()
	refresh_all()


func _on_run_loaded(_day_number: int) -> void:
	refresh_all()


# ─── Zona, cámara y reloj ──────────────────────────────────────────

func _evaluate_zone() -> void:
	var room: RoomData = Database.get_room(_room_id) if not _room_id.is_empty() else null
	if room == null:
		set_zone_restricted(false)
		return
	var occ: OccupationData = Database.get_occupation(_occupation_id) if not _occupation_id.is_empty() else null
	var player_access: Array = occ.special_access if occ != null else []
	var forbidden: bool = is_zone_forbidden(room.clearance_required, _clearance, room.special_access, player_access)
	set_zone_restricted(forbidden, room.clearance_required)


func _refresh_camera_pill() -> void:
	_camera_pill.visible = not _watching_cameras.is_empty() or _camera_pulse > 0.0


func _process(delta: float) -> void:
	if not _clock_frozen:
		_poll_clock()
	if _camera_pulse > 0.0:
		_camera_pulse -= delta
		if _camera_pulse <= 0.0:
			_refresh_camera_pill()
	if _camera_pill.visible:
		_blink += delta
		_camera_dot.modulate.a = 1.0 if fmod(_blink, 1.0) < 0.6 else 0.15


func _poll_clock() -> void:
	var h: int = GameClock.get_hour()
	var m: int = GameClock.get_minute()
	if h == _hour and m == _minute:
		return
	_hour = h
	_minute = m
	_clock_label.text = UITheme.format_hour(h, m)


func _show_money_delta(delta: int) -> void:
	if delta == 0:
		return
	_money_delta.text = UITheme.format_signed_money(delta)
	_money_delta.add_theme_color_override("font_color", UITheme.color("gain" if delta > 0 else "loss"))
	_money_delta.offset_top = _money_panel.offset_bottom + PANEL_GAP
	_money_delta.offset_bottom = _money_delta.offset_top + _money_delta.get_combined_minimum_size().y
	_money_delta.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(UITheme.tune("interfaz.dinero_delta_segundos") * 0.6)
	tween.tween_property(_money_delta, "modulate:a", 0.0, UITheme.tune("interfaz.dinero_delta_segundos") * 0.4)


func _style_rank_chip() -> void:
	var base_box: StyleBox = _rank_chip.get_theme_stylebox("panel", UITheme.V_PILL) if is_inside_tree() else null
	if not base_box is StyleBoxFlat:
		return
	var sb: StyleBoxFlat = (base_box as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.bg_color = _accent
	sb.shadow_size = 0
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_rank_chip.add_theme_stylebox_override("panel", sb)
	_rank_label.add_theme_color_override("font_color", UITheme.readable_on(_accent))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _rank_chip != null:
		_accent = UITheme.band_accent_for_floor(_floor)
		if _accent_bar != null:
			_accent_bar.color = _accent
		_style_rank_chip()
		if _duties_list != null:
			_rebuild_duties()


## Acreditación del jugador: la de PlayerState, nunca inferior a la de su ocupación.
func _current_clearance() -> int:
	var occ: OccupationData = Database.get_occupation(_occupation_id) if not _occupation_id.is_empty() else null
	return maxi(PlayerState.get_clearance(), occ.clearance if occ != null else 0)


static func _call_or(target: Object, method: String, fallback: Variant) -> Variant:
	if target != null and target.has_method(method):
		return target.call(method)
	return fallback


## Halo rojo en el perímetro de la pantalla, con pulso suave (solo procesa mientras está activo).
class HaloOverlay extends Control:
	var active: bool = false
	var _t: float = 0.0

	func _init() -> void:
		name = "Halo"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false
		set_process(false)

	func set_active(on: bool) -> void:
		active = on
		visible = on
		set_process(on)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var hz: float = UITheme.tune("interfaz.halo_pulso_hz")
		var pulse: float = 0.5 + 0.5 * sin(_t * TAU * hz)
		var alpha: float = lerpf(UITheme.tune("interfaz.halo_alfa_min"), UITheme.tune("interfaz.halo_alfa_max"), pulse)
		var col: Color = get_theme_color("danger", UITheme.HUD_TYPE)
		var outer: Color = Color(col, alpha)
		var inner: Color = Color(col, 0.0)
		var th: float = minf(size.x, size.y) * UITheme.tune("interfaz.halo_grosor_fraccion")
		var tl: Vector2 = Vector2.ZERO
		var tr: Vector2 = Vector2(size.x, 0)
		var br: Vector2 = size
		var bl: Vector2 = Vector2(0, size.y)
		var d: Vector2 = Vector2(th, th)
		var dx: Vector2 = Vector2(-th, th)
		_edge([tl, tr, tr + dx, tl + d], outer, inner)
		_edge([tr, br, br - d, tr + dx], outer, inner)
		_edge([br, bl, bl - dx, br - d], outer, inner)
		_edge([bl, tl, tl + d, bl - dx], outer, inner)

	func _edge(pts: Array[Vector2], outer: Color, inner: Color) -> void:
		draw_polygon(PackedVector2Array(pts), PackedColorArray([outer, outer, inner, inner]))
