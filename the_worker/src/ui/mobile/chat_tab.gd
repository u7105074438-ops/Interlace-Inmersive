# chat_tab.gd — Pestaña CHAT del móvil (§13.5): conversaciones escritas; todo lo escrito deja registro digital permanente.
# PROPIETARIO DE: la conversación abierta y las notas de trato de esta apertura del móvil (estado de vista, no se guarda).
# ESCUCHA: nada (PhoneOverlay le pasa los mensajes que llegan).
class_name PhoneChatTab
extends VBoxContainer

## Mensajes de una conversación: los de la bandeja de la sesión (PhoneOverlay.Service), la exigencia
## de chantaje abierta del contacto (Blackmail.get_open_demand) y las notas de los tratos hechos en
## esta apertura. Un trato por chat lo ejecuta BribePanel con Bribery.offer(…, "mobile_chat"): el
## registro chat_log permanente (legible por el Director de IT) lo crea Bribery.
## El aviso de registro muestra cuántos registros chat_log sobre el jugador hay ya en el servidor.

signal deal_requested(npc_id: String)
signal blackmail_requested(npc_id: String)
signal thread_changed(npc_id: String)

const DIR_IN := "in"
const DIR_OUT := "out"
const DIR_NOTE := "note"
const DIR_LOG := "log"
const DEMAND_CHIP_KEYS: Dictionary = {
	Blackmail.DEMAND_MONEY: "PHONE_DEMAND_CHIP_MONEY",
	Blackmail.DEMAND_PROMOTION: "PHONE_DEMAND_CHIP_PROMOTION",
	Blackmail.DEMAND_FAVOUR: "PHONE_DEMAND_CHIP_FAVOUR",
}

var service: PhoneOverlay.Service = null
var _thread: String = ""
var _notes: Array[Dictionary] = []
var _list_view: VBoxContainer
var _threads: VBoxContainer
var _thread_view: VBoxContainer
var _head_photo: PhoneOverlay.Portrait
var _head_name: Label
var _head_job: Label
var _record_count: Label
var _bubbles: VBoxContainer
var _bubble_scroll: ScrollContainer
var _deal_button: PhoneOverlay.IconButton
var _demand_button: PhoneOverlay.IconButton
var _ignored_note: Label


func _init() -> void:
	name = "Chat"
	add_theme_constant_override("separation", 0)
	_list_view = VBoxContainer.new()
	_list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list_view)
	_list_view.add_child(PhoneOverlay.label(tr("PHONE_CHAT_TITLE"), UITheme.V_HEADING))
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_threads = parts["list"]
	_list_view.add_child(parts["scroll"])
	_thread_view = VBoxContainer.new()
	_thread_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_thread_view)
	_thread_view.add_child(_build_header())
	_thread_view.add_child(_build_record_banner())
	_bubble_scroll = ScrollContainer.new()
	_bubble_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bubble_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bubbles = VBoxContainer.new()
	_bubbles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubbles.add_theme_constant_override("separation", 8)
	_bubble_scroll.add_child(_bubbles)
	_thread_view.add_child(_bubble_scroll)
	_thread_view.add_child(_build_composer())
	_thread_view.visible = false


func _build_header() -> Control:
	var head: HBoxContainer = HBoxContainer.new()
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "back", UITheme.V_FLAT)
	back.tooltip_text = tr("PHONE_BACK")
	back.pressed.connect(close_thread)
	head.add_child(back)
	_head_photo = PhoneOverlay.Portrait.new(1.7)
	head.add_child(_head_photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	_head_name = PhoneOverlay.label("", UITheme.V_STRONG)
	_head_name.clip_text = true
	text.add_child(_head_name)
	_head_job = PhoneOverlay.label("", UITheme.V_SMALL)
	_head_job.clip_text = true
	text.add_child(_head_job)
	return head


## Aviso diegético: el chat vive en el servidor de la empresa y lo lee IT.
func _build_record_banner() -> Control:
	var warn: Color = UITheme.color("warn")
	var banner: PanelContainer = PhoneOverlay.card(Color(warn.darkened(0.7), 0.95), warn.darkened(0.2), 8, 10.0, 6.0)
	var row: HBoxContainer = HBoxContainer.new()
	banner.add_child(row)
	var icon: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("server", "warn", 1.0)
	row.add_child(icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var body: Label = PhoneOverlay.label(tr("PHONE_CHAT_RECORD_WARNING"), UITheme.V_SMALL, true)
	body.add_theme_color_override("font_color", warn.lightened(0.35))
	text.add_child(body)
	_record_count = PhoneOverlay.label("", UITheme.V_CAPTION)
	_record_count.add_theme_color_override("font_color", warn)
	text.add_child(_record_count)
	return banner


func _build_composer() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	_ignored_note = PhoneOverlay.label(tr("PHONE_CHAT_IGNORED"), UITheme.V_SMALL, true)
	_ignored_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_ignored_note)
	_demand_button = PhoneOverlay.IconButton.new(tr("PHONE_CHAT_ANSWER_DEMAND"), "hazard", UITheme.V_DANGER)
	_demand_button.pressed.connect(func() -> void: blackmail_requested.emit(_thread))
	column.add_child(_demand_button)
	_deal_button = PhoneOverlay.IconButton.new(tr("PHONE_CHAT_OFFER_DEAL"), "coin", UITheme.V_PRIMARY)
	_deal_button.pressed.connect(func() -> void: deal_requested.emit(_thread))
	column.add_child(_deal_button)
	return column


# ─── API ───────────────────────────────────────────────────────────

func refresh() -> void:
	if _thread.is_empty():
		_rebuild_threads()
	else:
		_rebuild_thread()


func open_thread(npc_id: String) -> void:
	_thread = npc_id
	_list_view.visible = false
	_thread_view.visible = true
	if service != null:
		service.mark_read(npc_id)
	_rebuild_thread()
	thread_changed.emit(npc_id)


func close_thread() -> void:
	_thread = ""
	_thread_view.visible = false
	_list_view.visible = true
	_rebuild_threads()
	thread_changed.emit("")


func get_thread() -> String:
	return _thread


## Mensajes de la conversación: [{dir, text, time, chip}].
func messages_for(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shown_demand: bool = false
	if service != null:
		for entry: Dictionary in service.messages_from(npc_id):
			var key: String = str(entry["text_key"])
			shown_demand = shown_demand or Blackmail.PHONE_KEYS.values().has(key)
			out.append({"dir": DIR_IN, "text": tr(key), "time": str(entry["time"]), "chip": ""})
	var demand: Dictionary = _open_demand(npc_id)
	if not demand.is_empty():
		var chip: String = demand_chip(demand)
		if shown_demand:
			out[out.size() - 1]["chip"] = chip
		else:
			out.append({"dir": DIR_IN, "text": tr(str(Blackmail.PHONE_KEYS.get(demand["demand_type"], ""))),
					"time": "", "chip": chip})
	for note: Dictionary in _notes:
		if str(note["npc_id"]) == npc_id:
			out.append(note)
	return out


func unread_total() -> int:
	return service.unread_count() if service != null else 0


## Nota del trato hecho por chat: la oferta, la respuesta y el aviso de registro.
func note_offer(result: Dictionary) -> void:
	var npc_id: String = str(result.get("npc_id", _thread))
	var favour: Dictionary = Database.get_bribe_favour(str(result.get("favour", "")))
	var offer_text: String = UITheme.trf("PHONE_CHAT_OFFER_TEXT", [
			UITheme.format_money(int(result.get("amount", 0))), tr(str(favour.get("name_key", "")))])
	var time: String = GameClock.get_time_string()
	_notes.append({"npc_id": npc_id, "dir": DIR_OUT, "text": offer_text, "time": time, "chip": ""})
	_notes.append({"npc_id": npc_id, "dir": DIR_NOTE, "text": tr(str(result.get("text_key", ""))),
			"time": time, "chip": ""})
	if not str(result.get("record_id", "")).is_empty():
		_notes.append({"npc_id": npc_id, "dir": DIR_LOG, "text": tr("PHONE_CHAT_LOGGED"), "time": "",
				"chip": ""})
	if npc_id == _thread:
		_rebuild_thread()


func on_message_arrived(from_id: String) -> void:
	if from_id == _thread and visible and service != null:
		service.mark_read(from_id)
	refresh()


## Registros chat_log sobre el jugador que ya guarda el servidor (los lee el Director de IT).
static func server_record_count() -> int:
	var total: int = 0
	for rec: Belief in BeliefNet.get_records_about(Bribery.PLAYER_ID):
		if rec.record_type == BeliefNetSystem.RECORD_CHAT_LOG:
			total += 1
	return total


static func demand_chip(demand: Dictionary) -> String:
	var demand_type: String = str(demand.get("demand_type", ""))
	var key: String = str(DEMAND_CHIP_KEYS.get(demand_type, "PHONE_DEMAND_CHIP_FAVOUR"))
	if demand_type == Blackmail.DEMAND_MONEY:
		return UITheme.trf(key, [UITheme.format_money(int(demand.get("amount", 0)))])
	return tr_static(key)


static func tr_static(key: String) -> String:
	return String(TranslationServer.translate(key))


# ─── Construcción de vistas ────────────────────────────────────────

func _rebuild_threads() -> void:
	PhoneOverlay.clear_children(_threads)
	var ids: Array[String] = _thread_ids()
	if ids.is_empty():
		var empty: Label = PhoneOverlay.label(tr("PHONE_CHAT_EMPTY"), UITheme.V_SMALL, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_threads.add_child(empty)
	for npc_id: String in ids:
		_threads.add_child(_thread_row(npc_id))


func _thread_ids() -> Array[String]:
	var ids: Array[String] = []
	if service != null:
		ids = service.thread_ids()
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not ids.has(npc.id) and not Blackmail.get_open_demand(npc).is_empty():
			ids.append(npc.id)
	for note: Dictionary in _notes:
		if not ids.has(str(note["npc_id"])):
			ids.append(str(note["npc_id"]))
	return ids


func _thread_row(npc_id: String) -> Control:
	var row: PanelContainer = PhoneOverlay.card(UITheme.color("slot"), Color(0, 0, 0, 0), 8, 8.0, 6.0)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_thread_input.bind(npc_id))
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var photo: PhoneOverlay.Portrait = PhoneOverlay.Portrait.new(2.0)
	photo.set_npc(NPCDirector.get_npc(npc_id))
	line.add_child(photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var messages: Array[Dictionary] = messages_for(npc_id)
	var unread: int = service.unread_count(npc_id) if service != null else 0
	var who: Label = PhoneOverlay.label(PhoneOverlay.npc_name(npc_id), UITheme.V_STRONG)
	who.clip_text = true
	text.add_child(who)
	var last: Label = PhoneOverlay.label(str(messages.back()["text"]) if not messages.is_empty() else "",
			UITheme.V_STRONG if unread > 0 else UITheme.V_SMALL)
	last.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	last.clip_text = true
	text.add_child(last)
	if unread > 0:
		line.add_child(_unread_pill(unread))
	return row


func _on_thread_input(event: InputEvent, npc_id: String) -> void:
	if UITheme.is_primary_press(event):
		open_thread(npc_id)


func _unread_pill(count: int) -> Control:
	var pill: PanelContainer = PhoneOverlay.card(UITheme.color("danger"), Color(0, 0, 0, 0), 12, 8.0, 1.0)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(PhoneOverlay.label(str(count), UITheme.V_STRONG))
	return pill


func _rebuild_thread() -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(_thread)
	_head_photo.set_npc(npc)
	_head_name.text = PhoneOverlay.npc_name(_thread)
	_head_job.text = PhoneOverlay.job_text(npc)
	_record_count.text = UITheme.trf("PHONE_CHAT_RECORD_COUNT", [server_record_count()]).to_upper()
	PhoneOverlay.clear_children(_bubbles)
	for message: Dictionary in messages_for(_thread):
		_bubbles.add_child(_bubble(message))
	var answers: bool = PhoneContactsTab.will_answer(npc)
	_ignored_note.visible = not answers
	_deal_button.visible = answers
	_demand_button.visible = not _open_demand(_thread).is_empty()
	_scroll_to_end.call_deferred()


func _bubble(message: Dictionary) -> Control:
	var dir: String = str(message["dir"])
	if dir == DIR_NOTE or dir == DIR_LOG:
		return _note(str(message["text"]), dir == DIR_LOG)
	var outgoing: bool = dir == DIR_OUT
	var accent: Color = PhoneOverlay.accent_color()
	var bg: Color = accent.darkened(0.45) if outgoing else UITheme.color("slot")
	var bubble: PanelContainer = PhoneOverlay.card(bg, accent.darkened(0.1) if outgoing else UITheme.color("line"),
			12, 11.0, 7.0)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if outgoing else Control.SIZE_SHRINK_BEGIN
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	bubble.add_child(column)
	var body: Label = PhoneOverlay.label(str(message["text"]), "", true)
	body.custom_minimum_size.x = _bubble_width()
	column.add_child(body)
	if not str(message["chip"]).is_empty():
		column.add_child(_chip(str(message["chip"])))
	if not str(message["time"]).is_empty():
		var time: Label = PhoneOverlay.label(str(message["time"]), UITheme.V_CAPTION)
		time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		column.add_child(time)
	return bubble


## Narración (qué hizo el contacto) en cursiva, o aviso de registro en el servidor en versalitas.
func _note(text: String, log_line: bool) -> Control:
	var note: Label = PhoneOverlay.label(text.to_upper() if log_line else text,
			UITheme.V_CAPTION if log_line else UITheme.V_SMALL, true)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if log_line:
		note.add_theme_color_override("font_color", UITheme.color("warn"))
	else:
		note.add_theme_font_override("font", UITheme.italic(UITheme.font(UITheme.FONT_REGULAR)))
	return note


func _chip(text: String) -> Control:
	var danger: Color = UITheme.color("danger")
	var chip: PanelContainer = PhoneOverlay.card(danger.darkened(0.5), danger, 6, 8.0, 2.0)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_child(PhoneOverlay.label(text, UITheme.V_STRONG))
	return chip


func _bubble_width() -> float:
	var width: float = size.x if size.x > 0.0 else get_parent_area_size().x
	return maxf(width * 0.72, 40.0)


func _scroll_to_end() -> void:
	if is_inside_tree():
		_bubble_scroll.scroll_vertical = int(_bubble_scroll.get_v_scroll_bar().max_value)


func _open_demand(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return Blackmail.get_open_demand(npc) if npc != null else {}
