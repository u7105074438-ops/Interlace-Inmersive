# day_summary.gd — Resumen de jornada al dormir: ingresos, gastos, medidores y deberes (§15.6).
# PROPIETARIO DE: la vista del resumen y el registro auxiliar de la jornada (DayTracker).
# ESCUCHA: DayTracker: money_changed, reputation_changed, suspicion_changed, duty_completed, duty_failed.
class_name DaySummary
extends PanelContainer

## Contrato de day_summary_ready(summary) (todas las claves opcionales; lo que falte lo completa
## el DayTracker de UIRoot con lo observado en el bus durante la jornada):
##   day: int · income: int · expenses: int
##   income_lines / expense_lines: Array[{reason: String | key: String, amount: int}]
##   reputation / suspicion: float (valor actual) · reputation_delta / suspicion_delta: float
##   missed_duties / completed_duties: Array de claves de nombre, ids o diccionarios de deber.
## Motivos de dinero conocidos → clave HUD_REASON_<MOTIVO>; el resto se agrupa en "Otros".

signal closed()

const REASON_KEY := "HUD_REASON_%s"
const REASON_OTHER := "HUD_REASON_OTHER"
const WEEKDAY_KEY := "HUD_WEEKDAY_%d"
const COLUMN_WIDTH_EMS := 13.0

var _summary: Dictionary = {}
var _body: HBoxContainer
var _title: Label
var _subtitle: Label


func _init() -> void:
	name = "DaySummary"
	theme_type_variation = UITheme.V_MODAL
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_child(UITheme.IconView.new("moon", "hazard", 1.6))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	_title = Label.new()
	_title.theme_type_variation = UITheme.V_TITLE
	titles.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = UITheme.V_SMALL
	titles.add_child(_subtitle)
	header.add_child(titles)
	column.add_child(header)
	column.add_child(HSeparator.new())
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 40)
	column.add_child(_body)
	column.add_child(_build_footer())


func _ready() -> void:
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func setup(summary: Dictionary) -> void:
	_summary = summary.duplicate(true)
	var day: int = int(_summary.get("day", GameClock.get_day()))
	var per_week: int = maxi(UITheme.tune_int("tiempo.jornadas_por_semana"), 1)
	_title.text = UITheme.trf("DAYSUM_TITLE", [day]).to_upper()
	_subtitle.text = UITheme.trf("DAYSUM_SUBTITLE", [UITheme.trf(WEEKDAY_KEY % posmod(day - 1, per_week))])
	for child: Node in _body.get_children():
		child.queue_free()
	_body.add_child(_money_column())
	_body.add_child(_meters_column())


func get_summary() -> Dictionary:
	return _summary.duplicate(true)


func request_close() -> void:
	closed.emit()


## Completa `summary` con lo observado por el tracker (sin pisar lo que ya trae).
static func merge(summary: Dictionary, tracked: Dictionary) -> Dictionary:
	var out: Dictionary = tracked.duplicate(true)
	for key: Variant in summary:
		out[key] = summary[key]
	return out


# ─── Columnas ──────────────────────────────────────────────────────

func _money_column() -> VBoxContainer:
	var col: VBoxContainer = _column()
	var income_lines: Array = _summary.get("income_lines", [])
	var expense_lines: Array = _summary.get("expense_lines", [])
	var income: int = int(_summary.get("income", _sum(income_lines)))
	var expenses: int = absi(int(_summary.get("expenses", _sum(expense_lines))))
	col.add_child(_caption("DAYSUM_INCOME"))
	_add_money_lines(col, income_lines, true)
	col.add_child(_caption("DAYSUM_EXPENSES"))
	_add_money_lines(col, expense_lines, false)
	col.add_child(HSeparator.new())
	col.add_child(_row(UITheme.trf("DAYSUM_NET"), UITheme.format_signed_money(income - expenses),
			"gain" if income >= expenses else "loss", UITheme.V_HEADING))
	return col


func _meters_column() -> VBoxContainer:
	var col: VBoxContainer = _column()
	col.add_child(_caption("DAYSUM_METERS"))
	col.add_child(_meter_row("shield", "rep", "HUD_REPUTATION", "reputation", true))
	col.add_child(_meter_row("eye", "sus", "HUD_SUSPICION", "suspicion", false))
	col.add_child(_caption("DAYSUM_DUTIES"))
	var missed: Array = _summary.get("missed_duties", [])
	var completed: Array = _summary.get("completed_duties", [])
	for duty: Variant in completed:
		col.add_child(_duty_row(duty, true))
	for duty: Variant in missed:
		col.add_child(_duty_row(duty, false))
	if missed.is_empty():
		var ok: Label = _label(UITheme.trf("DAYSUM_ALL_DUTIES_MET"), UITheme.V_SMALL)
		ok.add_theme_color_override("font_color", UITheme.color("gain"))
		col.add_child(ok)
	return col


func _add_money_lines(col: VBoxContainer, lines: Array, positive: bool) -> void:
	if lines.is_empty():
		col.add_child(_label(UITheme.trf("DAYSUM_NONE"), UITheme.V_SMALL))
		return
	for line: Variant in lines:
		if not line is Dictionary:
			continue
		var d: Dictionary = line
		var amount: int = absi(int(d.get("amount", 0)))
		var text: String = UITheme.trf(str(d["key"])) if d.has("key") else reason_text(str(d.get("reason", "")))
		col.add_child(_row(text, UITheme.format_signed_money(amount if positive else -amount),
				"gain" if positive else "loss", ""))


func _meter_row(icon: String, color_name: String, key: String, field: String, up_is_good: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(UITheme.IconView.new(icon, color_name))
	var name_label: Label = _label(UITheme.trf(key), "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_label(str(roundi(float(_summary.get(field, 0.0)))), UITheme.V_STRONG))
	var delta: float = float(_summary.get(field + "_delta", 0.0))
	var good: bool = (delta >= 0.0) == up_is_good
	var tone: String = "muted" if is_zero_approx(delta) else ("gain" if good else "loss")
	var arrow: UITheme.IconView = UITheme.IconView.new("chevron_up" if delta >= 0.0 else "chevron_down", tone, 0.8)
	arrow.visible = not is_zero_approx(delta)
	row.add_child(arrow)
	var delta_label: Label = _label("%+d" % roundi(delta), UITheme.V_STRONG)
	delta_label.add_theme_color_override("font_color", UITheme.color(tone))
	row.add_child(delta_label)
	return row


func _duty_row(duty: Variant, done: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(UITheme.IconView.new("check" if done else "cross", "gain" if done else "loss", 0.8))
	var label: UITheme.StrikeLabel = UITheme.StrikeLabel.new()
	label.text = _duty_name(duty)
	label.theme_type_variation = UITheme.V_SMALL
	if not done:
		label.add_theme_color_override("font_color", UITheme.color("loss"))
	row.add_child(label)
	return row


func _build_footer() -> HBoxContainer:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	var next: Button = Button.new()
	next.theme_type_variation = UITheme.V_PRIMARY
	next.text = UITheme.trf("DAYSUM_CONTINUE")
	next.pressed.connect(request_close)
	footer.add_child(next)
	next.ready.connect(next.grab_focus, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	return footer


# ─── Utilidades ────────────────────────────────────────────────────

## Texto de un motivo de dinero ("wage" → HUD_REASON_WAGE; desconocido → "Otros").
static func reason_text(reason: String) -> String:
	var key: String = REASON_KEY % reason.to_upper()
	var text: String = String(TranslationServer.translate(key))
	return text if text != key else String(TranslationServer.translate(REASON_OTHER))


static func _duty_name(duty: Variant) -> String:
	if duty is Dictionary:
		return UITheme.trf(str((duty as Dictionary).get("name_key", (duty as Dictionary).get("id", ""))))
	return UITheme.trf(str(duty))


static func _sum(lines: Array) -> int:
	var total: int = 0
	for line: Variant in lines:
		if line is Dictionary:
			total += absi(int((line as Dictionary).get("amount", 0)))
	return total


func _column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size.x = UITheme.base_font_size(UITheme.current_text_size) * COLUMN_WIDTH_EMS
	return col


func _caption(key: String) -> Label:
	return _label(UITheme.trf(key).to_upper(), UITheme.V_CAPTION)


func _row(left: String, right: String, tone: String, variation: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = _label(left, variation)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r: Label = _label(right, UITheme.V_STRONG if variation.is_empty() else variation)
	r.add_theme_color_override("font_color", UITheme.color(tone))
	row.add_child(r)
	return row


func _label(text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label


## Registro auxiliar de la jornada (UIRoot lo mantiene vivo y lo reinicia tras cada resumen).
class DayTracker extends RefCounted:
	var income: Dictionary = {}
	var expenses: Dictionary = {}
	var rep_start: float = 0.0
	var sus_start: float = 0.0
	var rep_now: float = 0.0
	var sus_now: float = 0.0
	var completed: Array[String] = []
	var missed: Array[String] = []

	func connect_bus() -> void:
		EventBus.money_changed.connect(_on_money)
		EventBus.reputation_changed.connect(_on_rep)
		EventBus.suspicion_changed.connect(_on_sus)
		EventBus.duty_completed.connect(_on_done)
		EventBus.duty_failed.connect(_on_failed)

	func reset(reputation: float, suspicion: float) -> void:
		income.clear()
		expenses.clear()
		completed.clear()
		missed.clear()
		rep_start = reputation
		rep_now = reputation
		sus_start = suspicion
		sus_now = suspicion

	func snapshot() -> Dictionary:
		return {
			"income_lines": _lines(income), "expense_lines": _lines(expenses),
			"reputation": rep_now, "suspicion": sus_now,
			"reputation_delta": rep_now - rep_start, "suspicion_delta": sus_now - sus_start,
			"completed_duties": completed.duplicate(), "missed_duties": missed.duplicate(),
		}

	func _lines(source: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for reason: Variant in source:
			out.append({"reason": str(reason), "amount": int(source[reason])})
		return out

	func _on_money(old_value: int, new_value: int, reason: String) -> void:
		var delta: int = new_value - old_value
		var bucket: Dictionary = income if delta >= 0 else expenses
		bucket[reason] = int(bucket.get(reason, 0)) + absi(delta)

	func _on_rep(_old_value: float, new_value: float) -> void:
		rep_now = new_value

	func _on_sus(_old_value: float, new_value: float) -> void:
		sus_now = new_value

	func _on_done(duty_id: String, _quality: float, _method: String) -> void:
		completed.append(_duty_key(duty_id))

	func _on_failed(duty_id: String, _consequence: String) -> void:
		missed.append(_duty_key(duty_id))

	func _duty_key(duty_id: String) -> String:
		for duty: Dictionary in PlayerState.get_todays_duties():
			if str(duty.get("id", "")) == duty_id:
				return str(duty.get("name_key", duty_id))
		for occ: OccupationData in Database.get_all_occupations():
			for duty: Dictionary in occ.duties:
				if str(duty.get("id", "")) == duty_id:
					return str(duty.get("name_key", duty_id))
		return duty_id
