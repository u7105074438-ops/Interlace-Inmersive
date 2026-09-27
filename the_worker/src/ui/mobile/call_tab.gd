# call_tab.gd — Pestaña LLAMADA del móvil (§13.5): voz sin registro escrito, pero quien esté cerca la oye.
# PROPIETARIO DE: la llamada en curso de esta apertura del móvil (con quién, si contesta, cuánto dura) y su último resultado (estado de vista).
# ESCUCHA: nada (PhoneOverlay le pasa la exposición).
class_name PhoneCallTab
extends VBoxContainer

## La privacidad la calcula PhoneOverlay (listeners_in_range / is_call_safe_room) y llega por
## set_exposure(). Un trato por llamada lo ejecuta BribePanel con Bribery.offer(…, "phone_call",
## {listeners}): cada oyente recibe la creencia "bribe_attempt:overheard". Sin trato no se dice nada
## comprometedor: colgar no deja rastro. Un directivo que te ignora no contesta (PhoneContactsTab.will_answer).

signal deal_requested(npc_id: String)
signal call_state_changed(npc_id: String, active: bool)

const SECONDS_PER_MINUTE := 60

var _active: String = ""
var _answered: bool = false
var _elapsed: float = 0.0
var _exposure: Dictionary = {}
var _idle_view: VBoxContainer
var _call_view: VBoxContainer
var _contacts: VBoxContainer
var _privacy_cards: Array[Dictionary] = []
var _photo: PhoneOverlay.Portrait
var _who: Label
var _status: Label
var _outcome: Label
var _deal_button: PhoneOverlay.IconButton


func _init() -> void:
	name = "Call"
	_idle_view = VBoxContainer.new()
	_idle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_idle_view)
	_idle_view.add_child(PhoneOverlay.label(tr("PHONE_CALL_TITLE"), UITheme.V_HEADING))
	_idle_view.add_child(_build_privacy_card())
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_contacts = parts["list"]
	_idle_view.add_child(parts["scroll"])
	_call_view = VBoxContainer.new()
	_call_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_call_view.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_call_view)
	_build_call_view()
	_call_view.visible = false


func _build_privacy_card() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var row: HBoxContainer = HBoxContainer.new()
	panel.add_child(row)
	var icon: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("ear", "paper", 1.4)
	row.add_child(icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title: Label = PhoneOverlay.label("", UITheme.V_STRONG)
	text.add_child(title)
	var body: Label = PhoneOverlay.label("", UITheme.V_SMALL, true)
	text.add_child(body)
	_privacy_cards.append({"panel": panel, "icon": icon, "title": title, "body": body})
	return panel


func _build_call_view() -> void:
	_photo = PhoneOverlay.Portrait.new(6.5)
	_photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_call_view.add_child(_photo)
	_who = PhoneOverlay.label("", UITheme.V_TITLE)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_call_view.add_child(_who)
	_status = PhoneOverlay.label("", UITheme.V_CAPTION)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_view.add_child(_status)
	_call_view.add_child(_build_privacy_card())
	_outcome = PhoneOverlay.label("", UITheme.V_SMALL, true)
	_outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_view.add_child(_outcome)
	_deal_button = PhoneOverlay.IconButton.new(tr("PHONE_CALL_PROPOSE"), "coin", UITheme.V_PRIMARY)
	_deal_button.pressed.connect(func() -> void: deal_requested.emit(_active))
	_call_view.add_child(_deal_button)
	var hang: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_CALL_HANG_UP"), "hangup",
			UITheme.V_DANGER)
	hang.pressed.connect(hang_up)
	_call_view.add_child(hang)


func _process(delta: float) -> void:
	if _active.is_empty() or not _answered:
		return
	_elapsed += delta
	var seconds: int = int(_elapsed)
	_status.text = UITheme.trf("PHONE_CALL_CONNECTED", ["%02d:%02d" % [floori(float(seconds) / SECONDS_PER_MINUTE),
			seconds % SECONDS_PER_MINUTE]]).to_upper()


# ─── API ───────────────────────────────────────────────────────────

func refresh() -> void:
	PhoneOverlay.clear_children(_contacts)
	var rows: Array[Dictionary] = PhoneContactsTab.list_contacts()
	if rows.is_empty():
		var empty: Label = PhoneOverlay.label(tr("PHONE_CONTACTS_EMPTY"), UITheme.V_SMALL, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_contacts.add_child(empty)
	for entry: Dictionary in rows:
		_contacts.add_child(_contact_row(entry))
	_show_privacy()


## Llama al contacto. Devuelve si contesta (un directivo no contesta a quien está muy por debajo).
func start_call(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	_active = npc_id
	_answered = PhoneContactsTab.will_answer(npc)
	_elapsed = 0.0
	_photo.set_npc(npc)
	_who.text = PhoneOverlay.npc_name(npc_id)
	_status.text = tr("PHONE_CALL_RINGING").to_upper() if _answered else tr("PHONE_CALL_NO_ANSWER").to_upper()
	_outcome.text = "" if _answered else tr("PHONE_CALL_IGNORED")
	_deal_button.visible = _answered
	_idle_view.visible = false
	_call_view.visible = true
	_show_privacy()
	call_state_changed.emit(npc_id, true)
	return _answered


func hang_up() -> void:
	var was: String = _active
	_active = ""
	_answered = false
	_call_view.visible = false
	_idle_view.visible = true
	refresh()
	if not was.is_empty():
		call_state_changed.emit(was, false)


func get_active_call() -> String:
	return _active


func is_answered() -> bool:
	return _answered


func set_exposure(exposure: Dictionary) -> void:
	_exposure = exposure
	_show_privacy()


func note_offer(result: Dictionary) -> void:
	var text: String = tr(str(result.get("text_key", "")))
	var overheard: int = 0
	for belief: Variant in result.get("beliefs", []):
		if belief is Dictionary and str(belief.get("fact", "")) == Bribery.FACT_OVERHEARD:
			overheard += 1
	if overheard > 0:
		text += "\n" + UITheme.trf("PHONE_CALL_OVERHEARD", [overheard])
	_outcome.text = text


# ─── Privacidad ────────────────────────────────────────────────────

func _show_privacy() -> void:
	var listeners: Array = _exposure.get(PhoneOverlay.EXPO_LISTENERS, [])
	var safe: bool = bool(_exposure.get(PhoneOverlay.EXPO_SAFE, false))
	var tone: String = "gain" if listeners.is_empty() else "danger"
	var title: String = tr("PHONE_PRIVACY_PRIVATE") if listeners.is_empty() else tr("PHONE_PRIVACY_EXPOSED")
	var body: String = tr("PHONE_PRIVACY_NOBODY") if listeners.is_empty() \
			else UITheme.trf("PHONE_PRIVACY_LISTENERS", [listeners.size()])
	if not safe:
		body += " " + tr("PHONE_PRIVACY_HINT")
	var col: Color = UITheme.color(tone)
	for card: Dictionary in _privacy_cards:
		(card["panel"] as PanelContainer).add_theme_stylebox_override("panel",
				PhoneOverlay.box(Color(col.darkened(0.65), 0.95), col, 10, 12.0, 8.0, 2))
		(card["icon"] as PhoneOverlay.Glyph).set_glyph("lock" if listeners.is_empty() else "ear",
				col.lightened(0.2))
		(card["title"] as Label).text = title.to_upper()
		(card["title"] as Label).add_theme_color_override("font_color", col.lightened(0.3))
		(card["body"] as Label).text = body


func _contact_row(entry: Dictionary) -> Control:
	var npc_id: String = str(entry["npc_id"])
	var row: HBoxContainer = HBoxContainer.new()
	var photo: PhoneOverlay.Portrait = PhoneOverlay.Portrait.new(1.7)
	photo.set_npc(NPCDirector.get_npc(npc_id))
	row.add_child(photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var who: Label = PhoneOverlay.label(str(entry["name"]), UITheme.V_STRONG)
	who.clip_text = true
	text.add_child(who)
	var job: Label = PhoneOverlay.label(PhoneOverlay.job_text(NPCDirector.get_npc(npc_id)), UITheme.V_SMALL)
	job.clip_text = true
	text.add_child(job)
	var dial: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "phone", UITheme.V_PRIMARY)
	dial.tooltip_text = tr("PHONE_ACTION_CALL")
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dial.pressed.connect(start_call.bind(npc_id))
	row.add_child(dial)
	return row
