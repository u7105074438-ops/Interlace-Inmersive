# portal_app.gd — PORTAL de StellarOS: organigrama de las cincuenta ocupaciones con titulares y vacantes, condiciones y solicitud de ascenso (con confirmación), calendario Aurora y agendas de dirección (§13.3, §6.2, §11.8, PASO 25).
# PROPIETARIO DE: el estado de la ventana (ocupación seleccionada y solicitud de ascenso pendiente de confirmar).
# ESCUCHA: seat_vacated, seat_filled, occupation_changed (solo mientras está abierta, para refrescar).
class_name PortalApp
extends OSApp

## API pública: build_org_chart() -> [{tier, name, occupations: [entrada]}] (escalón 8 arriba);
## entrada = {id, name, rank, tier, floor, office, seats: [{index, holder, name, vacant, player,
## temporary, cause, day}], vacant, player_here}. vacancy_count(), promotion_status(occ),
## agenda_for(npc_id), week_calendar(). Ventana: select_occupation(occ), request_promotion(occ)
## (abre la confirmación: §13.7, nada irreversible con una sola pulsación), confirm_pending(),
## cancel_pending(), has_pending_confirmation().
## DECISIONES: el organigrama se lee de Company.get_all_seats() agrupado por ocupación; las
## vacantes (holder "") se resaltan con rayado y sello. La agenda del titular (escalón ≥
## portal.escalon_agenda_min) se muestrea con NPCDirector.get_location_at cada
## portal.minutos_muestra_agenda minutos de la jornada laboral y se agrupa en bloques (el horario
## de despacho de Voss, §11.8, sale así de su rutina).

const APP_ID := "portal"
const TITLE_KEY := "PORTAL_APP_TITLE"
const ICON := "portal"
const CONDITIONS: Array[String] = ["path", "reputation", "merit", "vacancy"]
const B_AGENDA_TIER := "portal.escalon_agenda_min"
const B_AGENDA_STEP := "portal.minutos_muestra_agenda"
const B_DAY_START := "tiempo.hora_inicio_jornada"
const B_DAY_END := "tiempo.hora_fin_jornada"
const B_DAYS_PER_WEEK := "tiempo.jornadas_por_semana"
const MINUTES_PER_HOUR := 60
const DETAIL_EM := 20.0
const Kit := PersonnelApp.OsKit

var _standalone: bool = false
var _in_ui_root: bool = false
var _embedded: bool = false
var _selected: String = ""
var _pending: String = ""
var _built: bool = false
var _dirty: bool = false
var _window: PersonnelApp.OsWindow
var _chart: OrgChart
var _week: WeekStrip
var _summary: SeatSummary
var _detail_box: VBoxContainer
var _confirm: Control


# ═══ Datos ════════════════════════════════════════════════════════════

## Organigrama completo por escalones (8 arriba), con las sillas de cada ocupación.
static func build_org_chart() -> Array[Dictionary]:
	var seats_by_occ: Dictionary = {}
	for seat: Dictionary in Company.get_all_seats():
		var occ_id: String = str(seat.get("occupation_id", ""))
		if not seats_by_occ.has(occ_id):
			seats_by_occ[occ_id] = []
		(seats_by_occ[occ_id] as Array).append(seat)
	var tiers: Array[Dictionary] = []
	for tier: int in range(OccupationData.MAX_TIER, OccupationData.MIN_TIER - 1, -1):
		var entries: Array[Dictionary] = []
		for occ: OccupationData in Database.get_occupations_by_tier(tier):
			entries.append(occupation_entry(occ, seats_by_occ.get(occ.id, [])))
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rank"]) < int(b["rank"]))
		tiers.append({"tier": tier, "name": UITheme.trf("PORTAL_TIER_%d" % tier), "occupations": entries})
	return tiers


static func occupation_entry(occ: OccupationData, seats: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var vacant: int = 0
	var player_here: bool = false
	for seat: Variant in seats:
		var row: Dictionary = seat_row(seat as Dictionary)
		vacant += 1 if bool(row["vacant"]) else 0
		player_here = player_here or bool(row["player"])
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	var room: RoomData = Database.get_room(occ.office_room)
	var floor_number: int = room.floor if room != null else 0
	return {"id": occ.id, "name": UITheme.trf(occ.name_key), "rank": occ.rank, "tier": occ.tier,
			"clearance": occ.clearance, "floor": floor_number,
			"office": UITheme.trf(room.name_key) if room != null else "", "seats": rows,
			"vacant": vacant, "player_here": player_here}


static func seat_row(seat: Dictionary) -> Dictionary:
	var holder: String = str(seat.get("holder", ""))
	var shown: String = ""
	if holder == PLAYER_ID:
		shown = UITheme.trf("PORTAL_YOU_FMT", [PlayerState.get_player_name()])
	elif not holder.is_empty():
		shown = PersonnelApp.other_name(holder)
	return {"index": int(seat.get("seat_index", 0)), "holder": holder, "name": shown,
			"vacant": holder.is_empty(), "player": holder == PLAYER_ID,
			"temporary": bool(seat.get("temporary", false)), "cause": str(seat.get("cause", "")),
			"day": int(seat.get("vacated_day", -1))}


## Sillas vacantes en toda la empresa.
static func vacancy_count() -> int:
	var count: int = 0
	for seat: Dictionary in Company.get_all_seats():
		if str(seat.get("holder", "")).is_empty():
			count += 1
	return count


static func occupation_count() -> int:
	var count: int = 0
	for tier: Dictionary in build_org_chart():
		count += (tier["occupations"] as Array).size()
	return count


## Condiciones de ascenso (§6.2): {allowed, missing, is_current, is_target, rows: [{id, ok, text}]}.
static func promotion_status(occupation_id: String) -> Dictionary:
	var result: Dictionary = Company.can_player_promote_to(occupation_id)
	var missing: Array = result.get("missing", [])
	var rows: Array[Dictionary] = []
	for condition: String in CONDITIONS:
		var ok: bool = not missing.has(condition)
		var key: String = ("PORTAL_COND_OK_" + condition.to_upper()) if ok \
				else CompanySystem.get_missing_label_key(condition)
		rows.append({"id": condition, "ok": ok, "text": UITheme.trf(key)})
	return {"allowed": bool(result.get("allowed", false)), "missing": missing, "rows": rows,
			"is_current": PlayerState.get_occupation_id() == occupation_id,
			"is_target": Company.get_promotion_targets().has(occupation_id)}


## Agenda de hoy del personaje en bloques [{from, to, place, room}] (horario laboral).
static func agenda_for(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var step: int = maxi(Database.get_balance_int(B_AGENDA_STEP), 1)
	var start: int = Database.get_balance_int(B_DAY_START) * MINUTES_PER_HOUR
	var end: int = Database.get_balance_int(B_DAY_END) * MINUTES_PER_HOUR
	for minute: int in range(start, end, step):
		var room: String = NPCDirector.get_location_at(npc_id, floori(float(minute) / MINUTES_PER_HOUR),
				minute % MINUTES_PER_HOUR)
		if not out.is_empty() and str(out.back()["room"]) == room:
			out.back()["to"] = minute + step
			continue
		out.append({"from": minute, "to": minute + step, "room": room})
	for block: Dictionary in out:
		block["place"] = PersonnelApp.room_name(str(block["room"]))
		block["label"] = "%s–%s" % [_clock(int(block["from"])), _clock(int(block["to"]))]
	return out


static func _clock(minute_of_day: int) -> String:
	return UITheme.format_hour(floori(float(minute_of_day) / MINUTES_PER_HOUR), minute_of_day % MINUTES_PER_HOUR)


static func shows_agenda(occupation_id: String) -> bool:
	var occ: OccupationData = Database.get_occupation(occupation_id)
	return occ != null and occ.tier >= Database.get_balance_int(B_AGENDA_TIER)


## Semana en curso: [{day, weekday, today, aurora, results}] (reunión Aurora §11.2, resultados §9.4).
static func week_calendar() -> Array[Dictionary]:
	var per_week: int = maxi(Database.get_balance_int(B_DAYS_PER_WEEK), 1)
	var today: int = maxi(GameClock.get_day(), 1)
	var first: int = today - posmod(today - 1, per_week)
	var out: Array[Dictionary] = []
	for offset: int in per_week:
		var day: int = first + offset
		out.append({"day": day, "weekday": UITheme.trf("HUD_WEEKDAY_%d" % offset), "today": day == today,
				"aurora": IdeaPool.is_meeting_day(day), "results": Market.get_presentation_day() == day})
	return out


# ═══ Ventana ══════════════════════════════════════════════════════════

static func open(host: Node, context: Dictionary = {}) -> PortalApp:
	var app: PortalApp = PortalApp.new()
	app.set_standalone(true)
	app.setup(context)
	if host is UIRoot:
		app._in_ui_root = true
		(host as UIRoot).open_modal(app, false)
	elif host != null:
		host.add_child(app)
	return app


static func is_available() -> bool:
	return true


func get_title_key() -> String:
	return TITLE_KEY


func set_standalone(on: bool) -> void:
	_standalone = on


func set_embedded(on: bool) -> void:
	_embedded = on


func request_close() -> void:
	close_requested.emit()
	if _standalone and not _in_ui_root:
		queue_free()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if not _built:
		setup(context)
	refresh.call_deferred()
	EventBus.seat_vacated.connect(_on_seat_vacated)
	EventBus.seat_filled.connect(_on_seat_filled)
	EventBus.occupation_changed.connect(_on_occupation_changed)


func _draw() -> void:
	if _standalone and not _embedded:
		Kit.draw_desktop(self, Rect2(Vector2.ZERO, size))


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		refresh()


func _on_seat_vacated(_occupation_id: String, _holder: String, _cause: String) -> void:
	_dirty = true


func _on_seat_filled(_occupation_id: String, _holder: String) -> void:
	_dirty = true


func _on_occupation_changed(_old_id: String, _new_id: String, _reason: String) -> void:
	_dirty = true


## OSApp: construye la interfaz. context (suelta) o context.extra (carcasa): {occupation_id?}.
func build() -> void:
	Kit.use(pal, int(context.get("base", 0)))
	theme = Kit.build_theme()
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(0.4))
	_frame().add_child(col)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", Kit.px(0.5))
	_week = WeekStrip.new()
	_week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_week)
	_summary = SeatSummary.new()
	_summary.custom_minimum_size = Vector2(Kit.px(DETAIL_EM), Kit.px(4.6))
	top.add_child(_summary)
	col.add_child(top)
	var main: HBoxContainer = HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", Kit.px(0.5))
	main.add_child(_build_chart())
	main.add_child(_build_detail())
	col.add_child(main)
	_built = true
	var wanted: String = Kit.requested(context, "occupation_id", "occupation_id")
	refresh()
	select_occupation(wanted if not wanted.is_empty() else PlayerState.get_occupation_id())


func _frame() -> Control:
	if _standalone and not _embedded:
		_window = Kit.make_window(self, tr(TITLE_KEY), ICON)
		_window.close_pressed.connect(request_close)
		return _window.body
	return Kit.make_holder(self)


func _build_chart() -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = Kit.V_FIELD
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	frame.add_child(scroll)
	_chart = OrgChart.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.picked.connect(select_occupation)
	scroll.add_child(_chart)
	return frame


func _build_detail() -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = Kit.V_PAPER
	frame.custom_minimum_size.x = Kit.px(DETAIL_EM)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", Kit.px(0.35))
	scroll.add_child(_detail_box)
	return frame


## Vuelve a leer Company y repinta organigrama, calendario, resumen y detalle.
func refresh() -> void:
	if not _built:
		return
	var tiers: Array[Dictionary] = build_org_chart()
	_chart.set_data(tiers, _selected, _targets_of(_selected))
	_week.days = week_calendar()
	_week.schedule = IdeaPool.get_meeting_schedule()
	_week.ideas_in_hand = IdeaPool.get_player_ideas().size()
	_week.queue_redraw()
	_summary.post = UITheme.trf("PERS_POST_FMT", [tr(PlayerState.get_occupation().name_key),
			PlayerState.get_rank()]) if PlayerState.get_occupation() != null else ""
	_summary.vacancies = vacancy_count()
	_summary.queue_redraw()
	_render_detail()
	Kit.show_status(self, _window, [tr("PORTAL_STATUS_SEATS") % [Company.get_all_seats().size(), occupation_count()],
			tr("PORTAL_STATUS_VACANT") % vacancy_count(),
			tr("PERS_STATUS_CLOCK") % [GameClock.get_day(), GameClock.get_time_string()]])


func _targets_of(occupation_id: String) -> Array[String]:
	var out: Array[String] = []
	var occ: OccupationData = Database.get_occupation(occupation_id)
	if occ != null:
		out.assign(occ.promotes_to + occ.can_jump_to)
	return out


func select_occupation(occupation_id: String) -> void:
	if Database.get_occupation(occupation_id) == null:
		return
	_selected = occupation_id
	if _built:
		_chart.set_selected(_selected, _targets_of(_selected))
		_render_detail()


func get_selected() -> String:
	return _selected


func _entry(occupation_id: String) -> Dictionary:
	var occ: OccupationData = Database.get_occupation(occupation_id)
	var seats: Array = []
	for seat: Dictionary in Company.get_all_seats():
		if str(seat.get("occupation_id", "")) == occupation_id:
			seats.append(seat)
	return occupation_entry(occ, seats)


func _render_detail() -> void:
	for child: Node in _detail_box.get_children():
		child.queue_free()
	if _selected.is_empty():
		return
	var entry: Dictionary = _entry(_selected)
	_detail_box.add_child(Kit.label(tr("PORTAL_DETAIL_KICKER"), Kit.V_HEADING))
	_detail_box.add_child(Kit.wrap_label(str(entry["name"]), Kit.V_TITLE))
	_detail_box.add_child(Kit.field_row(tr("PORTAL_FIELD_RANK"), tr("PORTAL_RANK_FMT") % [int(entry["rank"]),
			int(entry["tier"]), int(entry["clearance"])]))
	_detail_box.add_child(Kit.field_row(tr("PORTAL_FIELD_OFFICE"), "%s · %s" % [
			PersonnelApp.floor_text(int(entry["floor"])), str(entry["office"])]))
	_add_seats(entry)
	_add_promotion(entry)
	_add_agenda(entry)


func _heading(key: String) -> void:
	var head: PersonnelApp.SectionHead = PersonnelApp.SectionHead.new()
	head.text = tr(key)
	_detail_box.add_child(head)


func _add_seats(entry: Dictionary) -> void:
	_heading("PORTAL_SEC_SEATS")
	for seat: Dictionary in entry["seats"]:
		var text: String = str(seat["name"])
		var variation: String = Kit.V_BODY
		if bool(seat["vacant"]):
			text = tr("PORTAL_VACANT_SINCE") % [int(seat["day"]), _cause_text(str(seat["cause"]))]
			variation = Kit.V_STRONG
		var row: HBoxContainer = Kit.field_row(tr("PORTAL_SEAT_FMT") % (int(seat["index"]) + 1), text, variation)
		if bool(seat["vacant"]):
			(row.get_child(1) as Label).add_theme_color_override("font_color", Kit.red())
		elif bool(seat["player"]):
			(row.get_child(1) as Label).add_theme_color_override("font_color", Kit.teal())
		_detail_box.add_child(row)


func _cause_text(cause: String) -> String:
	if cause.is_empty():
		return tr("PORTAL_CAUSE_OTHER")
	var key: String = "PORTAL_CAUSE_" + cause.to_upper()
	var text: String = tr(key)
	return text if text != key else tr("PORTAL_CAUSE_OTHER")


func _add_promotion(entry: Dictionary) -> void:
	_heading("PORTAL_SEC_PROMOTION")
	var status: Dictionary = promotion_status(str(entry["id"]))
	if bool(status["is_current"]):
		_detail_box.add_child(Kit.wrap_label(tr("PORTAL_YOUR_CHAIR"), Kit.V_STRONG))
		return
	for row: Dictionary in status["rows"]:
		var line: PersonnelApp.Chip = PersonnelApp.Chip.new()
		var check: HBoxContainer = HBoxContainer.new()
		check.add_theme_constant_override("separation", Kit.px(0.4))
		line.text = "✓" if bool(row["ok"]) else "✗"
		line.color = Kit.green() if bool(row["ok"]) else Kit.red()
		check.add_child(line)
		check.add_child(Kit.wrap_label(str(row["text"]), Kit.V_BODY))
		_detail_box.add_child(check)
	var btn: Button = Kit.button(tr("PORTAL_REQUEST"), "star", Kit.V_PRIMARY)
	btn.disabled = not bool(status["allowed"])
	btn.pressed.connect(request_promotion.bind(str(entry["id"])))
	_detail_box.add_child(btn)


func _add_agenda(entry: Dictionary) -> void:
	if not shows_agenda(str(entry["id"])):
		return
	for seat: Dictionary in entry["seats"]:
		if bool(seat["vacant"]) or bool(seat["player"]):
			continue
		_heading("PORTAL_SEC_AGENDA")
		_detail_box.add_child(Kit.label(tr("PORTAL_AGENDA_OF") % str(seat["name"]), Kit.V_SMALL))
		for block: Dictionary in agenda_for(str(seat["holder"])):
			_detail_box.add_child(Kit.field_row(str(block["label"]), str(block["place"]), Kit.V_BODY))
		return


# ─── Ascenso con confirmación (§13.7) ─────────────────────────────────

## Pide el ascenso: nunca se ejecuta aquí; abre la confirmación explícita.
func request_promotion(occupation_id: String) -> void:
	if not bool(promotion_status(occupation_id)["allowed"]):
		return
	_pending = occupation_id
	_show_confirm()


func has_pending_confirmation() -> bool:
	return not _pending.is_empty()


## Ejecuta la solicitud confirmada (Company.promote_player). true si se ascendió.
func confirm_pending() -> bool:
	if _pending.is_empty():
		return false
	var target: String = _pending
	_pending = ""
	_hide_confirm()
	var ok: bool = Company.promote_player(target)
	refresh()
	return ok


func cancel_pending() -> void:
	_pending = ""
	_hide_confirm()


func _show_confirm() -> void:
	_hide_confirm()
	var target: OccupationData = Database.get_occupation(_pending)
	var current: OccupationData = PlayerState.get_occupation()
	var body: String = tr("PORTAL_CONFIRM_BODY") % [tr(target.name_key),
			tr(current.name_key) if current != null else "—"]
	_confirm = ConfirmOverlay.make(tr("PORTAL_CONFIRM_TITLE"), body, tr("PORTAL_CONFIRM_YES"), tr("UI_CANCEL"))
	_confirm.connect("answered", func(yes: bool) -> void:
		if yes:
			confirm_pending()
		else:
			cancel_pending())
	add_child(_confirm)


func _hide_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null


# ═══ Piezas dibujadas ═════════════════════════════════════════════════

## Organigrama: una franja por escalón (8 arriba) con tarjetas de ocupación; vacantes rayadas.
class OrgChart extends Control:
	signal picked(occupation_id: String)

	const CARD_W := 7.7
	const CARD_MIN_W := 6.2
	const CARD_H := 4.3
	const GAP := 0.4
	const ROW_GAP := 0.75
	const LABEL_W := 4.6
	const PAD := 0.5

	var tiers: Array[Dictionary] = []
	var selected: String = ""
	var targets: Array[String] = []
	var _rects: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_data(data: Array[Dictionary], sel: String, promo: Array[String]) -> void:
		tiers = data
		selected = sel
		targets = promo
		custom_minimum_size = Vector2(Kit.px(LABEL_W + PAD * 2.0) + _widest() * Kit.px(CARD_MIN_W + GAP),
				tiers.size() * Kit.px(CARD_H + ROW_GAP) + Kit.px(PAD))
		queue_redraw()

	func _widest() -> int:
		var widest: int = 1
		for tier: Dictionary in tiers:
			widest = maxi(widest, (tier["occupations"] as Array).size())
		return widest

	## Ancho de tarjeta que llena el espacio disponible (entre el mínimo y el de diseño).
	func _card_w() -> float:
		var avail: float = size.x - Kit.px(LABEL_W + PAD * 2.0)
		var fit_w: float = avail / float(_widest()) - Kit.px(GAP)
		return clampf(fit_w, Kit.px(CARD_MIN_W), Kit.px(CARD_W))

	func set_selected(sel: String, promo: Array[String]) -> void:
		selected = sel
		targets = promo
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not UITheme.is_primary_press(event):
			return
		var pos: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton \
				else (event as InputEventScreenTouch).position
		for occ_id: String in _rects:
			if (_rects[occ_id] as Rect2).has_point(pos):
				picked.emit(occ_id)
				accept_event()
				return

	func _layout() -> void:
		_rects.clear()
		var left: float = float(Kit.px(LABEL_W + PAD))
		var avail: float = size.x - left - Kit.px(PAD)
		var card_w: float = _card_w()
		var step: float = card_w + Kit.px(GAP)
		for i: int in tiers.size():
			var entries: Array = tiers[i]["occupations"]
			var row_w: float = entries.size() * step - Kit.px(GAP)
			var x: float = left + maxf((avail - row_w) * 0.5, 0.0)
			var y: float = Kit.px(PAD) + i * Kit.px(CARD_H + ROW_GAP)
			for entry: Dictionary in entries:
				_rects[str(entry["id"])] = Rect2(x, y, card_w, Kit.px(CARD_H))
				x += step

	func _draw() -> void:
		_layout()
		for i: int in tiers.size():
			_draw_band(i, tiers[i])
		_draw_links()
		for tier: Dictionary in tiers:
			for entry: Dictionary in tier["occupations"]:
				_draw_card(entry, _rects[str(entry["id"])])

	func _draw_band(i: int, tier: Dictionary) -> void:
		var y: float = Kit.px(PAD * 0.5) + i * Kit.px(CARD_H + ROW_GAP)
		var band: Rect2 = Rect2(0, y, size.x, Kit.px(CARD_H + PAD))
		if i % 2 == 0:
			draw_rect(band, Color(Kit.face(), 0.28))
		var label: Rect2 = Rect2(Kit.px(PAD * 0.5), y + Kit.px(PAD * 0.5), Kit.px(LABEL_W), Kit.px(CARD_H))
		draw_rect(label, Kit.teal())
		var parts: PackedStringArray = str(tier["name"]).split(" · ")
		Kit.text(self, label.position + Vector2(Kit.px(0.35), Kit.px(1.55)), parts[0], Kit.font_black(), Kit.px(1.35),
				Kit.title_ink(), label.size.x - Kit.px(0.7))
		var rest: String = parts[1] if parts.size() > 1 else ""
		var line_y: float = label.position.y + Kit.px(2.45)
		for line: String in _wrap(rest, Kit.font_bold(), Kit.px(0.66), label.size.x - Kit.px(0.7)):
			Kit.text(self, Vector2(label.position.x + Kit.px(0.35), line_y), line, Kit.font_bold(), Kit.px(0.66),
					Kit.title_ink(), label.size.x - Kit.px(0.7))
			line_y += Kit.px(0.75)

	func _draw_links() -> void:
		if not _rects.has(selected):
			return
		var from: Rect2 = _rects[selected]
		for target: String in targets:
			if not _rects.has(target):
				continue
			var to: Rect2 = _rects[target]
			var a: Vector2 = Vector2(from.get_center().x, from.position.y)
			var b: Vector2 = Vector2(to.get_center().x, to.end.y)
			var mid_y: float = (a.y + b.y) * 0.5
			if is_equal_approx(from.position.y, to.position.y):
				b = Vector2(to.get_center().x, to.position.y)
				mid_y = a.y - Kit.px(ROW_GAP * 0.45)
			var pts: PackedVector2Array = PackedVector2Array([a, Vector2(a.x, mid_y), Vector2(b.x, mid_y), b])
			draw_polyline(pts, Kit.face_hi(), 7.0)
			draw_polyline(pts, Kit.teal_light(), 3.5)
			draw_circle(b, 5.0, Kit.teal())

	func _draw_card(entry: Dictionary, r: Rect2) -> void:
		var vacant: bool = int(entry["vacant"]) > 0
		var is_sel: bool = str(entry["id"]) == selected
		draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.22 if is_sel else 0.12))
		draw_rect(r, Kit.field())
		var strip: Rect2 = Rect2(r.position, Vector2(r.size.x, Kit.px(0.42)))
		draw_rect(strip, Kit.hazard() if vacant else Kit.band_color(int(entry["floor"])))
		if vacant:
			Kit.draw_hatch(self, strip, Kit.ink(), 12.0, 4.0)
			draw_rect(r.grow(-2), Color(Kit.hazard(), 0.14))
		_draw_card_text(entry, r, vacant)
		_draw_pips(entry["seats"], r)
		var border: Color = Kit.select() if is_sel else (Kit.red() if vacant else (Kit.teal() if bool(entry["player_here"])
				else Kit.ink()))
		draw_rect(r, border, false, 3.5 if is_sel or bool(entry["player_here"]) else 2.0)
		if bool(entry["player_here"]):
			_draw_tag(r, TranslationServer.translate("PORTAL_TAG_YOU"), Kit.teal())
		elif targets.has(str(entry["id"])):
			_draw_tag(r, TranslationServer.translate("PORTAL_TAG_NEXT"), Kit.teal_light())

	func _draw_card_text(entry: Dictionary, r: Rect2, vacant: bool) -> void:
		var pad: float = float(Kit.px(0.35))
		var fsize: int = Kit.px(0.74)
		var lines: Array[String] = _wrap(str(entry["name"]), Kit.font_bold(), fsize, r.size.x - pad * 2.0)
		var y: float = r.position.y + Kit.px(0.42) + fsize * 1.15
		for line: String in lines:
			Kit.text(self, Vector2(r.position.x + pad, y), line, Kit.font_bold(), fsize, Kit.ink(), r.size.x - pad * 2.0)
			y += fsize * 1.12
		var holder: String = _holder_line(entry)
		Kit.text(self, Vector2(r.position.x + pad, r.end.y - Kit.px(1.2)), holder,
				Kit.font_black() if vacant else Kit.font_regular(), Kit.px(0.72), Kit.red() if vacant else Kit.soft(),
				r.size.x - pad * 2.0)
		Kit.text(self, Vector2(r.position.x + pad, r.end.y - Kit.px(0.3)), TranslationServer.translate("PERS_RANK_CHIP") % int(entry["rank"]),
				Kit.font_mono(), Kit.px(0.68), Kit.ink(), Kit.px(2.0))

	func _holder_line(entry: Dictionary) -> String:
		var seats: Array = entry["seats"]
		if int(entry["vacant"]) > 0:
			return TranslationServer.translate("PORTAL_VACANT").to_upper() if seats.size() == 1 \
					else TranslationServer.translate("PORTAL_VACANT_N") % int(entry["vacant"])
		if seats.is_empty():
			return "—"
		var first: String = str(seats[0]["name"])
		for seat: Dictionary in seats:
			if bool(seat["player"]):
				first = str(seat["name"])
		return first if seats.size() == 1 else "%s +%d" % [first, seats.size() - 1]

	func _draw_pips(seats: Array, r: Rect2) -> void:
		var radius: float = float(Kit.px(0.17))
		var shown: int = mini(seats.size(), 8)
		var x: float = r.end.x - Kit.px(0.4) - radius
		var y: float = r.end.y - Kit.px(0.35)
		for i: int in shown:
			var seat: Dictionary = seats[seats.size() - 1 - i]
			var c: Vector2 = Vector2(x - i * radius * 2.6, y - radius * 0.8)
			if bool(seat["vacant"]):
				draw_arc(c, radius, 0, TAU, 12, Kit.red(), 2.0)
			else:
				draw_circle(c, radius, Kit.teal() if bool(seat["player"]) else Kit.ink())

	func _draw_tag(r: Rect2, text: String, color: Color) -> void:
		var fsize: int = Kit.px(0.62)
		var w: float = Kit.font_black().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + Kit.px(0.6)
		var tag: Rect2 = Rect2(r.end.x - w - Kit.px(0.2), r.position.y - fsize * 0.7, w, fsize * 1.4)
		draw_rect(tag, color)
		draw_rect(tag, Kit.ink(), false, 1.5)
		Kit.text(self, Vector2(tag.position.x, tag.get_center().y + fsize * 0.36), text, Kit.font_black(), fsize,
				Kit.title_ink(), w, HORIZONTAL_ALIGNMENT_CENTER)

	static func _wrap(text: String, font: Font, fsize: int, width: float) -> Array[String]:
		var out: Array[String] = []
		var line: String = ""
		for word: String in text.split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= width or line.is_empty():
				line = candidate
			else:
				out.append(line)
				line = word
		if not line.is_empty():
			out.append(line)
		if out.size() > 2:
			var rest: String = " ".join(PackedStringArray(out.slice(1)))
			out = [out[0], Kit.fit(font, rest, fsize, width)]
		return out


## Tira de la semana: jornadas, hoy, reunión Aurora y presentación de resultados.
class WeekStrip extends Control:
	var days: Array[Dictionary] = []
	var schedule: Dictionary = {}
	var ideas_in_hand: int = 0

	func _init() -> void:
		custom_minimum_size.y = Kit.px(4.6)

	func _draw() -> void:
		Kit.draw_bevel(self, Rect2(Vector2.ZERO, size), Kit.face(), true)
		var label_w: float = float(Kit.px(6.2))
		Kit.text(self, Vector2(Kit.px(0.5), Kit.px(1.5)), TranslationServer.translate("PORTAL_WEEK"), Kit.font_black(),
				Kit.px(0.8), Kit.teal(), label_w - Kit.px(0.8))
		Kit.text(self, Vector2(Kit.px(0.5), Kit.px(2.8)), TranslationServer.translate("PORTAL_WEEK_SUB"),
				Kit.font_regular(), Kit.px(0.68), Kit.soft(), label_w - Kit.px(0.8))
		if days.is_empty():
			return
		var w: float = (size.x - label_w - Kit.px(0.6)) / float(days.size())
		for i: int in days.size():
			_draw_day(days[i], Rect2(label_w + i * w, Kit.px(0.3), w - Kit.px(0.3), size.y - Kit.px(0.6)))

	func _draw_day(day: Dictionary, r: Rect2) -> void:
		var today: bool = bool(day["today"])
		draw_rect(r, Kit.field() if not today else Kit.face_hi())
		draw_rect(r, Kit.select() if today else Kit.face_mid(), false, 3.0 if today else 1.5)
		var pad: float = float(Kit.px(0.35))
		Kit.text(self, r.position + Vector2(pad, Kit.px(1.0)), str(day["weekday"]).to_upper(), Kit.font_black(),
				Kit.px(0.7), Kit.select() if today else Kit.ink(), r.size.x * 0.6)
		Kit.text(self, Vector2(r.position.x, r.position.y + Kit.px(1.0)), TranslationServer.translate("PORTAL_DAY_FMT")
				% int(day["day"]), Kit.font_mono(), Kit.px(0.68), Kit.soft(), r.size.x - pad, HORIZONTAL_ALIGNMENT_RIGHT)
		var y: float = r.position.y + Kit.px(1.55)
		if bool(day["aurora"]):
			_event(Rect2(r.position.x + pad, y, r.size.x - pad * 2.0, Kit.px(1.0)), "star", Kit.amber(),
					TranslationServer.translate("PORTAL_AURORA_FMT") % UITheme.format_hour(int(schedule.get("hour", 0))))
			y += Kit.px(1.15)
			if ideas_in_hand > 0:
				Kit.text(self, Vector2(r.position.x + pad, y + Kit.px(0.6)),
						TranslationServer.translate("PORTAL_IDEAS_FMT") % ideas_in_hand, Kit.font_bold(), Kit.px(0.62),
						Kit.ink(), r.size.x - pad * 2.0)
				y += Kit.px(0.9)
		if bool(day["results"]):
			_event(Rect2(r.position.x + pad, y, r.size.x - pad * 2.0, Kit.px(1.0)), "coin", Kit.green(),
					TranslationServer.translate("PORTAL_RESULTS_DAY"))

	func _event(r: Rect2, glyph: String, color: Color, label: String) -> void:
		draw_rect(r, color)
		UITheme.draw_icon(self, glyph, Rect2(r.position + Vector2(3, 2), Vector2(r.size.y - 4, r.size.y - 4)),
				Kit.ink(), 1.6)
		Kit.text(self, Vector2(r.position.x + r.size.y + 2, r.get_center().y + Kit.px(0.24)), label, Kit.font_bold(),
				Kit.px(0.64), Kit.ink(), r.size.x - r.size.y - 4)


## Tarjeta «tu silla / vacantes».
class SeatSummary extends Control:
	var post: String = ""
	var vacancies: int = 0

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		Kit.draw_bevel(self, r, Kit.face(), false)
		var count_w: float = float(Kit.px(6.0))
		var count: Rect2 = Rect2(size.x - count_w - Kit.px(0.3), Kit.px(0.3), count_w, size.y - Kit.px(0.6))
		draw_rect(count, Kit.hazard() if vacancies > 0 else Kit.field())
		if vacancies > 0:
			Kit.draw_hatch(self, Rect2(count.position, Vector2(count.size.x, Kit.px(0.45))), Kit.ink(), 10.0, 3.0)
		draw_rect(count, Kit.ink(), false, 2.0)
		Kit.text(self, Vector2(count.position.x, count.position.y + Kit.px(2.6)), str(vacancies), Kit.font_black(),
				Kit.px(2.0), Kit.ink(), count.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		Kit.text(self, Vector2(count.position.x, count.end.y - Kit.px(0.35)),
				TranslationServer.translate("PORTAL_VACANCIES").to_upper(), Kit.font_black(), Kit.px(0.62), Kit.ink(),
				count.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		var text_w: float = count.position.x - Kit.px(0.8)
		Kit.text(self, Vector2(Kit.px(0.5), Kit.px(1.5)), TranslationServer.translate("PORTAL_YOUR_SEAT").to_upper(),
				Kit.font_black(), Kit.px(0.72), Kit.teal(), text_w)
		Kit.text(self, Vector2(Kit.px(0.5), Kit.px(2.8)), post, Kit.font_bold(), Kit.px(0.9), Kit.ink(), text_w)
		Kit.text(self, Vector2(Kit.px(0.5), Kit.px(3.9)), TranslationServer.translate("PORTAL_HINT"), Kit.font_regular(),
				Kit.px(0.66), Kit.soft(), text_w)


## Diálogo de confirmación dentro de la ventana (acciones irreversibles, §13.7).
class ConfirmOverlay extends Control:
	signal answered(yes: bool)

	static func make(title: String, body: String, yes_text: String, no_text: String) -> ConfirmOverlay:
		var overlay: ConfirmOverlay = ConfirmOverlay.new()
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var center: CenterContainer = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(center)
		var window: PersonnelApp.OsWindow = PersonnelApp.OsWindow.new(title, "warning")
		window.custom_minimum_size.x = Kit.px(26.0)
		window.close_pressed.connect(func() -> void: overlay.answered.emit(false))
		center.add_child(window)
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", Kit.px(0.8))
		window.body.add_child(col)
		col.add_child(Kit.wrap_label(body, Kit.V_BODY))
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_END
		buttons.add_theme_constant_override("separation", Kit.px(0.5))
		var no: Button = Kit.button(no_text, "cross")
		no.pressed.connect(func() -> void: overlay.answered.emit(false))
		var yes: Button = Kit.button(yes_text, "check", Kit.V_DANGER)
		yes.pressed.connect(func() -> void: overlay.answered.emit(true))
		buttons.add_child(no)
		buttons.add_child(yes)
		col.add_child(buttons)
		window.set_status([TranslationServer.translate("OS_IRREVERSIBLE")])
		return overlay

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.08, 0.45))
