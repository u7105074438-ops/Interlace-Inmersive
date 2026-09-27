# call_tab.gd — Pestaña LLAMADA del móvil (§13.5): voz sin registro escrito, pero quien esté cerca la oye.
# PROPIETARIO DE: la llamada en curso de esta apertura del móvil (con quién, si contesta, cuánto dura) y su último resultado (estado de vista).
# ESCUCHA: nada (PhoneOverlay le pasa la exposición).
class_name PhoneCallTab
extends VBoxContainer

## La privacidad la calcula PhoneOverlay (listeners_in_range / is_call_safe_room) y llega por
## set_exposure(). Un trato por llamada lo ejecuta BribePanel con Bribery.offer(…, "phone_call",
## {listeners}): cada oyente recibe la creencia "bribe_attempt:overheard". Sin trato no se dice nada
## comprometedor: colgar no deja rastro. Un directivo que te ignora no contesta (PhoneContactsTab.will_answer).
## La lista de números solo se construye al mostrar la pestaña (filas reutilizadas, PhoneContactsTab.RowCache).
## Modo compacto (móvil apaisado): cabecera en fila con foto pequeña y colgar como botón redondo.

signal deal_requested(npc_id: String)
signal call_state_changed(npc_id: String, active: bool)

const SECONDS_PER_MINUTE := 60
const PHOTO_EMS := 5.5
const PHOTO_EMS_COMPACT := 2.4
const ROW_PHOTO_EMS := 1.7

var _active: String = ""
var _answered: bool = false
var _elapsed: float = 0.0
var _exposure: Dictionary = {}
var _compact: bool = false
var _idle_view: VBoxContainer
var _call_view: VBoxContainer
var _contacts: VBoxContainer
var _empty: Label
var _cache: PhoneContactsTab.RowCache
var _privacy_cards: Array[Dictionary] = []
var _hero: BoxContainer
var _hero_text: VBoxContainer
var _photo: PhoneOverlay.Portrait
var _who: Label
var _status: Label
var _outcome: Label
var _buttons: BoxContainer
var _deal_button: PhoneOverlay.IconButton
var _hang_button: PhoneOverlay.IconButton


func _init() -> void:
	name = "Call"
	_idle_view = VBoxContainer.new()
	_idle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_idle_view)
	_idle_view.add_child(PhoneOverlay.label(tr("PHONE_CALL_TITLE"), UITheme.V_HEADING))
	_idle_view.add_child(_build_privacy_card())
	_empty = PhoneOverlay.label(tr("PHONE_CONTACTS_EMPTY"), UITheme.V_SMALL, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	_idle_view.add_child(_empty)
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_contacts = parts["list"]
	_idle_view.add_child(parts["scroll"])
	_cache = PhoneContactsTab.RowCache.new(_contacts, _contact_row, func(_r: Control, _e: Dictionary) -> void: pass)
	_call_view = VBoxContainer.new()
	_call_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_call_view)
	_build_call_view()
	_call_view.visible = false
	set_process(false)


func _build_privacy_card() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var row: HBoxContainer = HBoxContainer.new()
	panel.add_child(row)
	var icon: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("ear", "paper", 1.4)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	var parts: Dictionary = PhoneOverlay.scroll_list()
	var body: VBoxContainer = parts["list"]
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_call_view.add_child(parts["scroll"])
	_hero = BoxContainer.new()
	_hero.vertical = true
	body.add_child(_hero)
	_photo = PhoneOverlay.Portrait.new(PHOTO_EMS)
	_photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_photo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hero.add_child(_photo)
	_hero_text = VBoxContainer.new()
	_hero_text.add_theme_constant_override("separation", 0)
	_hero_text.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.add_child(_hero_text)
	_who = PhoneOverlay.label("", UITheme.V_TITLE)
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_text.add_child(_who)
	_status = PhoneOverlay.label("", UITheme.V_CAPTION)
	_hero_text.add_child(_status)
	body.add_child(_build_privacy_card())
	_outcome = PhoneOverlay.label("", UITheme.V_SMALL, true)
	_outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_outcome)
	_call_view.add_child(_build_call_buttons())
	_apply_compact()


func _build_call_buttons() -> Control:
	_buttons = BoxContainer.new()
	_buttons.vertical = true
	_deal_button = PhoneOverlay.IconButton.new(tr("PHONE_CALL_PROPOSE"), "coin", UITheme.V_PRIMARY)
	_deal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deal_button.pressed.connect(func() -> void: deal_requested.emit(_active))
	_buttons.add_child(_deal_button)
	_hang_button = PhoneOverlay.IconButton.new(tr("PHONE_CALL_HANG_UP"), "hangup", UITheme.V_DANGER)
	_hang_button.tooltip_text = tr("PHONE_CALL_HANG_UP")
	_hang_button.pressed.connect(hang_up)
	_buttons.add_child(_hang_button)
	return _buttons


## Construye las filas pendientes de la lista y lleva el cronómetro de la llamada en curso.
func _process(delta: float) -> void:
	var building: bool = not _cache.pending.is_empty() \
			and _cache.build_some(PhoneOverlay.tune_i(PhoneContactsTab.B_ROWS_PER_FRAME))
	var talking: bool = not _active.is_empty() and _answered
	if not building and not talking:
		set_process(false)
	if not talking:
		return
	_elapsed += delta
	var seconds: int = int(_elapsed)
	_status.text = UITheme.trf("PHONE_CALL_CONNECTED", ["%02d:%02d" % [floori(float(seconds) / SECONDS_PER_MINUTE),
			seconds % SECONDS_PER_MINUTE]]).to_upper()


# ─── API ───────────────────────────────────────────────────────────

func refresh() -> void:
	var rows: Array[Dictionary] = PhoneContactsTab.list_contacts()
	_empty.visible = rows.is_empty()
	_cache.sync(rows)
	var building: bool = _cache.build_some(PhoneOverlay.tune_i(PhoneContactsTab.B_ROWS_PER_FRAME))
	set_process(building or (not _active.is_empty() and _answered))
	_show_privacy()


## Aprieta la vista de llamada: foto pequeña al lado del nombre y colgar como botón redondo.
func set_compact(on: bool) -> void:
	_compact = on
	_apply_compact()


func _apply_compact() -> void:
	_hero.vertical = not _compact
	_photo.set_ems(PHOTO_EMS_COMPACT if _compact else PHOTO_EMS)
	var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT if _compact else HORIZONTAL_ALIGNMENT_CENTER
	_who.horizontal_alignment = align
	_status.horizontal_alignment = align
	_who.theme_type_variation = UITheme.V_HEADING if _compact else UITheme.V_TITLE
	_buttons.vertical = not _compact
	_hang_button.size_flags_horizontal = Control.SIZE_FILL if _compact else Control.SIZE_EXPAND_FILL
	_hang_button.set_label("" if _compact else tr("PHONE_CALL_HANG_UP"))


func is_compact() -> bool:
	return _compact


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
	set_process(true)
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


## Texto de la tarjeta de privacidad (pruebas y capturas).
func get_privacy_text() -> String:
	return (_privacy_cards[0]["body"] as Label).text if not _privacy_cards.is_empty() else ""


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
	elif listeners.is_empty():
		body += " " + tr("PHONE_PRIVACY_SAFE_SPOT")
	var col: Color = UITheme.color(tone)
	for card: Dictionary in _privacy_cards:
		(card["panel"] as PanelContainer).add_theme_stylebox_override("panel",
				PhoneOverlay.box(Color(col.darkened(0.65), 0.95), col, 10, 10.0, 6.0, 2))
		(card["icon"] as PhoneOverlay.Glyph).set_glyph("lock" if listeners.is_empty() else "ear",
				col.lightened(0.2))
		(card["title"] as Label).text = title.to_upper()
		(card["title"] as Label).add_theme_color_override("font_color", col.lightened(0.3))
		(card["body"] as Label).text = body


func _contact_row(entry: Dictionary) -> Control:
	var npc_id: String = str(entry["npc_id"])
	var row: HBoxContainer = HBoxContainer.new()
	var photo: PhoneOverlay.Portrait = PhoneOverlay.Portrait.new(ROW_PHOTO_EMS)
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
