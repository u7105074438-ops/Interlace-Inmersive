# mail_app.gd — MAIL de StellarOS (§10.2 volumen, §10.6, §13.3, PASO 22): la bandeja de correo absurdo de la jornada; contestar ES el deber de volumen de los rangos base.
# PROPIETARIO DE: nada (la sesión del deber es de DutySystem y su estado oficial de PlayerState; aquí solo la selección visible).
# ESCUCHA: duty_completed, duty_failed, day_advanced (mientras está abierta, para refrescar la bandeja).
class_name MailApp
extends OSApp

## DECISIONES:
##  · La bandeja tiene tantos correos como `amount` del deber cuyo subtipo alimenta
##    duties.json content.email_templates (deberes.contenido_por_subtipo; R1: 8 correos). El
##    correo i es la plantilla (content_offset + i) de la sesión de DutySystem, así que la bandeja
##    coincide con la unidad que DutySystem evalúa.
##  · Política 7.3.1: se contestan por orden de llegada (DutySystem evalúa la unidad actual). Los
##    posteriores se pueden leer, no contestar; los contestados quedan marcados.
##  · Contestar = DutySystem.submit_unit(deber, respuesta): avanza el reloj su parte de
##    time_cost_minutes (8 correos → 45 min exactos) y la calidad sigue a las respuestas correctas.
##    Además, una respuesta errónea cuesta ordenador.correo_reputacion_respuesta_erronea de
##    reputación (PlayerState.modify_reputation, motivo "mail_wrong_reply").
##  · El tachado en el HUD lo produce PlayerState (duty_completed) al terminar el deber.

const CONTENT_KEY := "email_templates"
const B_CONTENT_BY_SUBTYPE := "deberes.contenido_por_subtipo"
const B_WRONG_REPUTATION := "ordenador.correo_reputacion_respuesta_erronea"
const REASON_WRONG := "mail_wrong_reply"
const STATUS_PENDING := "pending"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
## Contenido (no ajustes): reacciones MAIL_REACT_OK_<n> y MAIL_REACT_BAD_<n>.
const REACTION_COUNT := 4
const REPLY_COUNT := 3
const SENDER_COLORS: Array[String] = ["#2f6db5", "#c8553d", "#2e7d32", "#8a5cc2", "#b8860b", "#0f4c5c", "#b3261e"]

var _duty_id: String = ""
var _selected: int = -1
var _last_answer: Dictionary = {}
var _header_title: Label
var _header_sub: Label
var _progress: MailProgress
var _list: VBoxContainer
var _rows: Array[OSApp.OSRow] = []
var _reader: VBoxContainer
var _empty: VBoxContainer


## Barra segmentada: un bloque por correo, los contestados rellenos.
class MailProgress extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var amount: int = 0
	var done: int = 0

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		custom_minimum_size = Vector2(base * 11.0, base * 1.1)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OSTheme.draw_bevel(self, r, pal, true, base)
		if amount <= 0:
			return
		var inner: Rect2 = r.grow(-OSTheme.bevel_width(base) * 2.5)
		var gap: float = maxf(2.0, base * 0.12)
		var w: float = (inner.size.x - gap * (amount - 1)) / float(amount)
		for i: int in amount:
			var cell: Rect2 = Rect2(inner.position + Vector2(i * (w + gap), 0), Vector2(w, inner.size.y))
			draw_rect(cell, OSTheme.col(pal, "good") if i < done else Color(OSTheme.col(pal, "shadow"), 0.25))


## Cuadro con la inicial del remitente (color estable por remitente).
class MailSenderBadge extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var letter: String = ""
	var fill: Color = Color.GRAY

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		custom_minimum_size = Vector2(base * 2.4, base * 2.4)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OSTheme.draw_panel(self, r, pal, fill)
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(size.y * 0.55)
		draw_string(f, Vector2(0, size.y * 0.5 + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)


# ─── Consultas estáticas (escritorio, pruebas) ─────────────────────

## Id del deber de hoy que se cumple contestando correos ("" si no hay).
static func find_mail_duty() -> String:
	var by_subtype: Variant = Database.get_balance(B_CONTENT_BY_SUBTYPE)
	if not by_subtype is Dictionary:
		return ""
	for duty: Dictionary in PlayerState.get_todays_duties():
		if str((by_subtype as Dictionary).get(str(duty.get("subtype", "")), "")) == CONTENT_KEY:
			return str(duty.get("id", ""))
	return ""


static func templates() -> Array:
	var items: Variant = Database.get_duty_content().get(CONTENT_KEY, [])
	return items if items is Array else []


## Correos sin contestar del deber de hoy (insignia del icono del escritorio).
static func pending_count(ds: DutySystem) -> int:
	var duty_id: String = find_mail_duty()
	if duty_id.is_empty() or ds == null or not ds.register_duty(duty_id):
		return 0
	var s: Dictionary = ds.get_session(duty_id)
	if str(s.get("status", "")) in [STATUS_COMPLETED, STATUS_FAILED]:
		return 0
	return maxi(int(s.get("amount", 0)) - int(s.get("done", 0)), 0)


## Bandeja: [{index, template, replied, current}] en el orden en que DutySystem las evaluará.
static func build_inbox(ds: DutySystem, duty_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var items: Array = templates()
	if duty_id.is_empty() or ds == null or items.is_empty() or not ds.register_duty(duty_id):
		return out
	var s: Dictionary = ds.get_session(duty_id)
	var done: int = int(s.get("done", 0))
	var resolved: bool = str(s.get("status", "")) in [STATUS_COMPLETED, STATUS_FAILED]
	for i: int in int(s.get("amount", 0)):
		var template: Dictionary = items[(int(s.get("content_offset", 0)) + i) % items.size()]
		out.append({"index": i, "template": template, "replied": i < done,
				"current": i == done and not resolved})
	return out


# ─── Construcción ─────────────────────────────────────────────────

func build() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	col.add_child(_build_header())
	var split: HBoxContainer = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	var left: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	var scroll: ScrollContainer = make_scroll_list()
	_list = scroll.get_child(0) as VBoxContainer
	left.add_child(scroll)
	split.add_child(left)
	var right: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.45
	split.add_child(right)
	var inner: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, roundi(base * 0.5))
	right.add_child(inner)
	var reader_scroll: ScrollContainer = make_scroll_list()
	_reader = reader_scroll.get_child(0) as VBoxContainer
	_reader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reader.add_theme_constant_override("separation", roundi(base * 0.3))
	inner.add_child(reader_scroll)
	_empty = _build_empty()
	inner.add_child(_empty)
	EventBus.duty_completed.connect(_on_duty_event.unbind(3))
	EventBus.duty_failed.connect(_on_duty_event.unbind(2))
	EventBus.day_advanced.connect(_on_duty_event.unbind(1))


func _build_header() -> PanelContainer:
	var head: PanelContainer = make_panel(OSTheme.V_RAISED)
	var h: HBoxContainer = HBoxContainer.new()
	head.add_child(h)
	h.add_child(make_icon("mail", 2.2))
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	h.add_child(texts)
	_header_title = make_label("", OSTheme.V_TITLE, false, true)
	texts.add_child(_header_title)
	_header_sub = make_label("", OSTheme.V_MUTED, false, true)
	texts.add_child(_header_sub)
	_progress = MailProgress.new(pal, base)
	h.add_child(_progress)
	return head


func _build_empty() -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var art: OSApp.OSIcon = make_icon("mail", 6.0)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)
	var head: Label = make_label("", OSTheme.V_BIG, true)
	head.name = "EmptyTitle"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var body: Label = make_label("", OSTheme.V_MUTED, true)
	body.name = "EmptyBody"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	box.visible = false
	return box


func _ready() -> void:
	refresh()


func get_title_key() -> String:
	return "MAIL_WINDOW_TITLE"


# ─── Estado ───────────────────────────────────────────────────────

func refresh() -> void:
	_duty_id = find_mail_duty()
	var inbox: Array[Dictionary] = build_inbox(duty_system(), _duty_id)
	_refresh_header(inbox)
	_fill_list(inbox)
	if inbox.is_empty():
		_show_empty("MAIL_EMPTY_TITLE", "MAIL_EMPTY_BODY")
		return
	if _selected < 0 or _selected >= inbox.size():
		_selected = _current_index(inbox)
	_show_mail(inbox, _selected)


func get_duty_id() -> String:
	return _duty_id


func get_selected() -> int:
	return _selected


func get_inbox() -> Array[Dictionary]:
	return build_inbox(duty_system(), _duty_id)


func select_mail(index: int) -> void:
	_selected = index
	refresh()


## Contesta el correo seleccionado con la respuesta `choice` (0..2). Devuelve el resultado de
## DutySystem.submit_unit más {correct, reputation_delta}; {ok: false, error} si no procede.
func answer(choice: int) -> Dictionary:
	var inbox: Array[Dictionary] = get_inbox()
	if _selected < 0 or _selected >= inbox.size() or not bool(inbox[_selected]["current"]):
		return {"ok": false, "error": "not_current"}
	var template: Dictionary = inbox[_selected]["template"]
	await wait_lag(0.5)
	var result: Dictionary = duty_system().submit_unit(_duty_id, choice)
	if not bool(result.get("ok", false)):
		post_status(t(str(result.get("error_key", ""))))
		refresh()
		return result
	var correct: bool = choice == int(template.get("correct_reply", -1))
	result["correct"] = correct
	result["reputation_delta"] = 0.0 if correct else Database.get_balance_float(B_WRONG_REPUTATION)
	if not correct:
		PlayerState.modify_reputation(float(result["reputation_delta"]), REASON_WRONG)
	_last_answer = {"index": _selected, "correct": correct, "choice": choice}
	_report(result)
	_selected = -1
	refresh()
	return result


## Atajo (pruebas, escenarios): selecciona el correo pendiente y lo contesta.
func answer_current(choice: int) -> Dictionary:
	_selected = _current_index(get_inbox())
	return await answer(choice)


## Respuesta correcta del correo pendiente (−1 si no hay).
func current_correct_reply() -> int:
	var inbox: Array[Dictionary] = get_inbox()
	var i: int = _current_index(inbox)
	if i < 0 or i >= inbox.size() or not bool(inbox[i]["current"]):
		return -1
	return int((inbox[i]["template"] as Dictionary).get("correct_reply", -1))


func _current_index(inbox: Array[Dictionary]) -> int:
	for entry: Dictionary in inbox:
		if bool(entry["current"]):
			return int(entry["index"])
	return inbox.size() - 1 if not inbox.is_empty() else -1


func _report(result: Dictionary) -> void:
	var serial: int = int(result.get("done", 0))
	var key: String = "MAIL_REACT_OK_%d" if bool(result["correct"]) else "MAIL_REACT_BAD_%d"
	var text: String = t("MAIL_STATUS_SENT", [int(result.get("minutes", 0))]) + "  " \
			+ t(key % (serial % REACTION_COUNT + 1))
	if not bool(result["correct"]):
		text += "  " + t("MAIL_STATUS_REPUTATION", [str(snappedf(float(result["reputation_delta"]), 0.1))])
	if bool(result.get("completed", false)):
		text = t("MAIL_STATUS_DONE")
	post_status(text)


# ─── Vista ────────────────────────────────────────────────────────

func _refresh_header(inbox: Array[Dictionary]) -> void:
	var duty: Dictionary = PlayerState.get_duty(_duty_id) if not _duty_id.is_empty() else {}
	var done: int = 0
	for entry: Dictionary in inbox:
		done += 1 if bool(entry["replied"]) else 0
	_progress.amount = inbox.size()
	_progress.done = done
	_progress.queue_redraw()
	_progress.visible = not inbox.is_empty()
	if duty.is_empty():
		_header_title.text = t("MAIL_HEADER_NO_DUTY")
		_header_sub.text = t("MAIL_HEADER_NO_DUTY_SUB")
		return
	_header_title.text = t("MAIL_HEADER_DUTY", [t(str(duty.get("name_key", ""))), inbox.size()])
	var per_mail: int = roundi(float(duty_system().get_honest_minutes(_duty_id)) / float(maxi(inbox.size(), 1)))
	var deadline: String = UITheme.format_hour(int(duty.get("deadline_hour", 0)))
	_header_sub.text = t("MAIL_HEADER_SUB", [done, inbox.size(), deadline, per_mail])
	if str(duty.get("status", "")) == STATUS_COMPLETED:
		_header_sub.text = t("MAIL_HEADER_DONE")
	elif str(duty.get("status", "")) == STATUS_FAILED:
		_header_sub.text = t("MAIL_HEADER_FAILED")


func _fill_list(inbox: Array[Dictionary]) -> void:
	OSApp.clear_children(_list)
	_rows.clear()
	for entry: Dictionary in inbox:
		var tpl: Dictionary = entry["template"]
		var replied: bool = bool(entry["replied"])
		var tag: String = t("MAIL_TAG_REPLIED") if replied else (t("MAIL_TAG_NEXT") if bool(entry["current"]) else "")
		var row: OSApp.OSRow = make_row("check" if replied else "mail", t(str(tpl.get("sender_key", ""))),
				t(str(tpl.get("subject_key", ""))), tag)
		row.set_tag_color(c("good") if replied else c("accent"))
		row.set_title_variation(OSTheme.V_SMALL if replied else OSTheme.V_HEADING)
		row.set_selected(int(entry["index"]) == _selected)
		row.pressed.connect(select_mail.bind(int(entry["index"])))
		_list.add_child(row)
		_rows.append(row)


func _show_empty(title_key: String, body_key: String) -> void:
	_reader.get_parent().visible = false
	_empty.visible = true
	(_empty.find_child("EmptyTitle", true, false) as Label).text = t(title_key)
	(_empty.find_child("EmptyBody", true, false) as Label).text = t(body_key)


func _show_mail(inbox: Array[Dictionary], index: int) -> void:
	_empty.visible = false
	(_reader.get_parent() as Control).visible = true
	OSApp.clear_children(_reader)
	var entry: Dictionary = inbox[clampi(index, 0, inbox.size() - 1)]
	var tpl: Dictionary = entry["template"]
	_reader.add_child(_from_line(tpl))
	var subject: Label = make_label(t(str(tpl.get("subject_key", ""))), OSTheme.V_TITLE, true)
	_reader.add_child(subject)
	_reader.add_child(HSeparator.new())
	var body: Label = make_label(t(str(tpl.get("body_key", ""))), "", true)
	_reader.add_child(body)
	var footer: Label = make_label(t("MAIL_FOOTER"), OSTheme.V_MUTED, true)
	footer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reader.add_child(footer)
	_reader.add_child(_reply_block(entry))


func _from_line(tpl: Dictionary) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	var sender: String = t(str(tpl.get("sender_key", "")))
	var badge: MailSenderBadge = MailSenderBadge.new(pal, base)
	badge.letter = sender.substr(0, 1).to_upper()
	badge.fill = Color(SENDER_COLORS[absi(hash(str(tpl.get("sender_key", "")))) % SENDER_COLORS.size()])
	h.add_child(badge)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(make_label(t("MAIL_FROM", [sender]), OSTheme.V_HEADING, false, true))
	col.add_child(make_label(t("MAIL_TO"), OSTheme.V_MUTED, false, true))
	h.add_child(col)
	return h


func _reply_block(entry: Dictionary) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	var tpl: Dictionary = entry["template"]
	var index: int = int(entry["index"])
	if bool(entry["replied"]):
		box.add_child(_verdict_line(index))
		if int(_last_answer.get("index", -1)) == index:
			var keys_sent: Array = tpl.get("replies_keys", []) as Array
			var choice: int = int(_last_answer.get("choice", -1))
			if choice >= 0 and choice < keys_sent.size():
				box.add_child(make_label(t("MAIL_YOU_SENT", [t(str(keys_sent[choice]))]), OSTheme.V_MUTED, true))
		return box
	box.add_child(make_section(t("MAIL_REPLY_WITH")))
	var keys: Array = tpl.get("replies_keys", []) as Array
	for i: int in mini(keys.size(), REPLY_COUNT):
		var b: Button = make_button("%d.  %s" % [i + 1, t(str(keys[i]))], _on_reply.bind(i))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(entry["current"])
		box.add_child(b)
	if not bool(entry["current"]):
		var note: Label = make_label(t("MAIL_POLICY_ORDER"), OSTheme.V_MUTED, true)
		box.add_child(note)
	return box


func _verdict_line(index: int) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	var fresh: bool = int(_last_answer.get("index", -1)) == index
	var correct: bool = bool(_last_answer.get("correct", true))
	h.add_child(make_icon("check" if not fresh or correct else "cross", 1.4))
	var key: String = "MAIL_VERDICT_REPLIED"
	if fresh:
		key = "MAIL_VERDICT_GOOD" if correct else "MAIL_VERDICT_BAD"
	var l: Label = make_label(t(key), OSTheme.V_HEADING, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _on_reply(choice: int) -> void:
	await answer(choice)


func _on_duty_event() -> void:
	if is_inside_tree():
		refresh.call_deferred()
