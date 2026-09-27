# contacts_tab.gd — Pestaña CONTACTOS del móvil (§13.5): números disponibles, cómo se consiguieron y quién responde.
# PROPIETARIO DE: la lista mostrada y el contacto seleccionado (estado de vista, no se guarda).
# ESCUCHA: nada (PhoneOverlay la refresca).
class_name PhoneContactsTab
extends VBoxContainer

## Contactos: PlayerState.get_contacts() si existe (ids o {npc_id, source}); si no, se derivan del
## estado ya existente, sin guardar nada propio (ver REQUESTS: compra de números, intrusión en RRHH):
##   messaged  — tiene una exigencia de chantaje abierta o te ha escrito en esta sesión;
##   favour    — su registro tiene favores o deuda, o afecto >= movil.afecto_minimo_contacto;
##   colleague — trabaja en tu sala (home_room == office_room de tu ocupación): proximidad laboral;
##   hr        — tu ocupación es de movil.departamento_rrhh: RRHH tiene todos los números.
## will_answer(): un directivo (escalón >= movil.escalon_directivo) no responde a un jugador que esté
## movil.brecha_escalon_sin_respuesta escalones o más por debajo (§13.5).

signal action_chosen(npc_id: String, action: String)

const SOURCE_MESSAGED := "messaged"
const SOURCE_FAVOUR := "favour"
const SOURCE_COLLEAGUE := "colleague"
const SOURCE_HR := "hr"
const SOURCE_BOUGHT := "bought"
const SOURCE_ORDER: Array[String] = [SOURCE_MESSAGED, SOURCE_FAVOUR, SOURCE_COLLEAGUE, SOURCE_BOUGHT,
		SOURCE_HR]
const SOURCE_KEYS: Dictionary = {
	SOURCE_MESSAGED: "PHONE_SOURCE_MESSAGED", SOURCE_FAVOUR: "PHONE_SOURCE_FAVOUR",
	SOURCE_COLLEAGUE: "PHONE_SOURCE_COLLEAGUE", SOURCE_HR: "PHONE_SOURCE_HR",
	SOURCE_BOUGHT: "PHONE_SOURCE_BOUGHT",
}
const B_DIRECTOR_TIER := "movil.escalon_directivo"
const B_TIER_GAP := "movil.brecha_escalon_sin_respuesta"
const B_AFFECTION := "movil.afecto_minimo_contacto"
const B_HR := "movil.departamento_rrhh"

var _title_count: Label
var _list: VBoxContainer
var _empty: Label
var _actions: PanelContainer
var _action_name: Label
var _action_note: Label
var _chat_button: PhoneOverlay.IconButton
var _call_button: PhoneOverlay.IconButton
var _deal_button: PhoneOverlay.IconButton
var _rows: Array[Dictionary] = []
var _selected: String = ""


func _init() -> void:
	name = "Contacts"
	add_theme_constant_override("separation", 8)
	var header: HBoxContainer = HBoxContainer.new()
	var title: Label = PhoneOverlay.label(tr("PHONE_CONTACTS_TITLE"), UITheme.V_HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_title_count = PhoneOverlay.label("", UITheme.V_CAPTION)
	header.add_child(_title_count)
	add_child(header)
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_list = parts["list"]
	add_child(parts["scroll"])
	_empty = PhoneOverlay.label(tr("PHONE_CONTACTS_EMPTY"), UITheme.V_SMALL, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(_empty)
	add_child(_build_actions())


func _build_actions() -> PanelContainer:
	_actions = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"))
	var column: VBoxContainer = VBoxContainer.new()
	_actions.add_child(column)
	_action_name = PhoneOverlay.label("", UITheme.V_STRONG)
	_action_name.clip_text = true
	column.add_child(_action_name)
	_action_note = PhoneOverlay.label(tr("PHONE_CONTACT_IGNORES"), UITheme.V_SMALL, true)
	_action_note.add_theme_color_override("font_color", UITheme.color("loss"))
	column.add_child(_action_note)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_chat_button = PhoneOverlay.IconButton.new(tr("PHONE_ACTION_CHAT"), "talk")
	_call_button = PhoneOverlay.IconButton.new(tr("PHONE_ACTION_CALL"), "phone")
	_deal_button = PhoneOverlay.IconButton.new(tr("PHONE_ACTION_DEAL"), "coin", UITheme.V_PRIMARY)
	for pair: Array in [[_chat_button, PhoneOverlay.ACTION_CHAT], [_call_button, PhoneOverlay.ACTION_CALL],
			[_deal_button, PhoneOverlay.ACTION_DEAL]]:
		var button: PhoneOverlay.IconButton = pair[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_emit_action.bind(str(pair[1])))
		row.add_child(button)
	_actions.visible = false
	return _actions


# ─── API ───────────────────────────────────────────────────────────

func refresh() -> void:
	_rows = list_contacts()
	PhoneOverlay.clear_children(_list)
	_empty = PhoneOverlay.label(tr("PHONE_CONTACTS_EMPTY"), UITheme.V_SMALL, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = _rows.is_empty()
	_list.add_child(_empty)
	for entry: Dictionary in _rows:
		_list.add_child(_make_row(entry))
	_title_count.text = str(_rows.size())
	if not has_contact(_selected):
		_selected = ""
	_update_actions()


func get_rows() -> Array[Dictionary]:
	return _rows.duplicate(true)


func has_contact(npc_id: String) -> bool:
	for entry: Dictionary in _rows:
		if str(entry["npc_id"]) == npc_id:
			return true
	return false


func select(npc_id: String) -> void:
	_selected = npc_id if has_contact(npc_id) else ""
	for row: Node in _list.get_children():
		if row.has_meta("npc_id"):
			_style_row(row as PanelContainer, str(row.get_meta("npc_id")) == _selected)
	_update_actions()


func get_selected() -> String:
	return _selected


## Acción sobre el contacto elegido; un directivo que te ignora no acepta llamadas ni tratos.
func choose_action(action: String) -> bool:
	if _selected.is_empty():
		return false
	var answers: bool = will_answer(NPCDirector.get_npc(_selected))
	if not answers and action != PhoneOverlay.ACTION_CHAT:
		return false
	action_chosen.emit(_selected, action)
	return true


# ─── Filas ─────────────────────────────────────────────────────────

func _make_row(entry: Dictionary) -> PanelContainer:
	var npc: NPCRuntime = NPCDirector.get_npc(str(entry["npc_id"]))
	var row: PanelContainer = PanelContainer.new()
	row.set_meta("npc_id", str(entry["npc_id"]))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_row_input.bind(str(entry["npc_id"])))
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var photo: PhoneOverlay.Portrait = PhoneOverlay.Portrait.new(2.1)
	photo.set_npc(npc)
	line.add_child(photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(text)
	var name_label: Label = PhoneOverlay.label(str(entry["name"]), UITheme.V_STRONG)
	name_label.clip_text = true
	text.add_child(name_label)
	var job: Label = PhoneOverlay.label(PhoneOverlay.job_text(npc), UITheme.V_SMALL)
	job.clip_text = true
	text.add_child(job)
	text.add_child(_source_chip(entry))
	_style_row(row, str(entry["npc_id"]) == _selected)
	return row


func _source_chip(entry: Dictionary) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var answers: bool = bool(entry["answers"])
	var dot: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("check" if answers else "no_entry",
			"gain" if answers else "loss", 0.7)
	line.add_child(dot)
	var text: String = tr(str(SOURCE_KEYS.get(entry["source"], "PHONE_SOURCE_COLLEAGUE")))
	if not answers:
		text = tr("PHONE_CONTACT_IGNORES_SHORT")
	var chip: Label = PhoneOverlay.label(text.to_upper(), UITheme.V_CAPTION)
	chip.add_theme_color_override("font_color", UITheme.color("muted" if answers else "loss"))
	line.add_child(chip)
	return line


func _style_row(row: PanelContainer, selected: bool) -> void:
	var accent: Color = PhoneOverlay.accent_color()
	var bg: Color = UITheme.color("button_hover") if selected else UITheme.color("slot")
	var sb: StyleBoxFlat = PhoneOverlay.box(bg, accent if selected else Color(0, 0, 0, 0), 8, 8.0, 6.0,
			2 if selected else 0)
	row.add_theme_stylebox_override("panel", sb)


func _on_row_input(event: InputEvent, npc_id: String) -> void:
	if UITheme.is_primary_press(event):
		select(npc_id)


func _update_actions() -> void:
	_actions.visible = not _selected.is_empty()
	if _selected.is_empty():
		return
	var answers: bool = will_answer(NPCDirector.get_npc(_selected))
	_action_name.text = PhoneOverlay.npc_name(_selected)
	_action_note.visible = not answers
	_call_button.disabled = not answers
	_deal_button.disabled = not answers


func _emit_action(action: String) -> void:
	choose_action(action)


# ─── Contactos (estático, sin estado propio) ───────────────────────

## [{npc_id, name, tier, source, answers}] ordenados por origen y nombre.
static func list_contacts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if PlayerState.has_method("get_contacts"):
		out = _from_player_state(PlayerState.call("get_contacts"))
	else:
		var occupation: OccupationData = PlayerState.get_occupation()
		for npc: NPCRuntime in NPCDirector.get_all_npcs():
			var source: String = contact_source(npc, occupation)
			if not source.is_empty():
				out.append(_entry(npc, source))
	out.sort_custom(_before)
	return out


static func contact_source(npc: NPCRuntime, occupation: OccupationData) -> String:
	if npc == null or not npc.alive:
		return ""
	if not Blackmail.get_open_demand(npc).is_empty() or _has_messaged(npc.id):
		return SOURCE_MESSAGED
	if _owes_or_likes(npc.ledger):
		return SOURCE_FAVOUR
	if occupation == null:
		return ""
	if not occupation.office_room.is_empty() and npc.home_room == occupation.office_room:
		return SOURCE_COLLEAGUE
	if str(occupation.extra.get("department", "")) == str(Database.get_balance(B_HR)):
		return SOURCE_HR
	return ""


static func is_contact(npc_id: String) -> bool:
	for entry: Dictionary in list_contacts():
		if str(entry["npc_id"]) == npc_id:
			return true
	return false


## §13.5: «Un directivo no responde a un jugador de rango muy inferior».
static func will_answer(npc: NPCRuntime) -> bool:
	if npc == null or not npc.alive:
		return false
	if npc.tier < PhoneOverlay.tune_i(B_DIRECTOR_TIER):
		return true
	return npc.tier - PlayerState.get_tier() < PhoneOverlay.tune_i(B_TIER_GAP)


static func _entry(npc: NPCRuntime, source: String) -> Dictionary:
	return {"npc_id": npc.id, "name": npc.name, "tier": npc.tier, "source": source,
			"answers": will_answer(npc)}


static func _from_player_state(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	for item: Variant in raw:
		var npc_id: String = str((item as Dictionary).get("npc_id", "")) if item is Dictionary else str(item)
		var source: String = str((item as Dictionary).get("source", SOURCE_BOUGHT)) if item is Dictionary \
				else SOURCE_BOUGHT
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		if npc != null and npc.alive:
			out.append(_entry(npc, source))
	return out


static func _owes_or_likes(ledger: Dictionary) -> bool:
	var favours: Variant = ledger.get("favours", [])
	if favours is Array and not (favours as Array).is_empty():
		return true
	if int(ledger.get("debt", 0)) != 0:
		return true
	return int(ledger.get("affection", 0)) >= PhoneOverlay.tune_i(B_AFFECTION)


static func _has_messaged(npc_id: String) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var service: PhoneOverlay.Service = PhoneOverlay.find_service(tree)
	return service != null and not service.messages_from(npc_id).is_empty()


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ia: int = SOURCE_ORDER.find(str(a["source"]))
	var ib: int = SOURCE_ORDER.find(str(b["source"]))
	if ia != ib:
		return ia < ib
	if bool(a["answers"]) != bool(b["answers"]):
		return bool(a["answers"])
	return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
