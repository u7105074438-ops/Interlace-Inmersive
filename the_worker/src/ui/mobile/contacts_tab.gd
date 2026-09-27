# contacts_tab.gd — Pestaña CONTACTOS del móvil (§13.5): números disponibles, cómo se consiguieron y quién responde.
# PROPIETARIO DE: la lista mostrada (filas reutilizadas por personaje) y el contacto seleccionado (estado de vista, no se guarda).
# ESCUCHA: nada (PhoneOverlay la refresca).
class_name PhoneContactsTab
extends VBoxContainer

## Contactos: PlayerState.get_contacts() ({npc_id, source, day}; fuentes proximity | favour | hr |
## purchase | messaged, que PlayerState adquiere y guarda). Si PlayerState no lo expone, se derivan del
## estado existente sin guardar nada propio:
##   messaged  — tiene una exigencia de chantaje abierta o te ha escrito en esta sesión;
##   favour    — su registro tiene favores o deuda, o afecto >= movil.afecto_minimo_contacto;
##   proximity — trabaja en tu sala (home_room == office_room de tu ocupación);
##   hr        — tu ocupación es de movil.departamento_rrhh: RRHH tiene todos los números.
## will_answer(): un directivo (escalón >= movil.escalon_directivo) no responde a un jugador que esté
## movil.brecha_escalon_sin_respuesta escalones o más por debajo (§13.5).
## Rendimiento: las filas se reutilizan por personaje (RowCache) y las nuevas se construyen a razón de
## movil.filas_contactos_por_fotograma por fotograma (en RR. HH. hay un número por empleado).

signal action_chosen(npc_id: String, action: String)

const SOURCE_MESSAGED := "messaged"
const SOURCE_FAVOUR := "favour"
const SOURCE_COLLEAGUE := "proximity"
const SOURCE_HR := "hr"
const SOURCE_BOUGHT := "purchase"
const SOURCE_ORDER: Array[String] = [SOURCE_MESSAGED, SOURCE_FAVOUR, SOURCE_COLLEAGUE, SOURCE_BOUGHT,
		SOURCE_HR]
const SOURCE_KEYS: Dictionary = {
	SOURCE_MESSAGED: "PHONE_SOURCE_MESSAGED", SOURCE_FAVOUR: "PHONE_SOURCE_FAVOUR",
	SOURCE_COLLEAGUE: "PHONE_SOURCE_COLLEAGUE", SOURCE_HR: "PHONE_SOURCE_HR",
	SOURCE_BOUGHT: "PHONE_SOURCE_BOUGHT",
}
## Nombres de la pestaña que PlayerState también acepta como sinónimos.
const SOURCE_ALIASES: Dictionary = {"colleague": SOURCE_COLLEAGUE, "bought": SOURCE_BOUGHT}
const B_DIRECTOR_TIER := "movil.escalon_directivo"
const B_TIER_GAP := "movil.brecha_escalon_sin_respuesta"
const B_AFFECTION := "movil.afecto_minimo_contacto"
const B_HR := "movil.departamento_rrhh"
const B_ROWS_PER_FRAME := "movil.filas_contactos_por_fotograma"
const META_NPC := "npc_id"
const PORTRAIT_EMS := 2.1
const PORTRAIT_EMS_COMPACT := 1.7


## Filas de una lista por personaje: reutiliza las que ya existen, borra las que sobran y construye las
## nuevas poco a poco (build_some) para no congelar el fotograma con cientos de retratos.
class RowCache extends RefCounted:
	var list: VBoxContainer
	var factory: Callable
	var updater: Callable
	var rows: Dictionary = {}
	var order: Array[String] = []
	var pending: Array[Dictionary] = []

	func _init(p_list: VBoxContainer, p_factory: Callable, p_updater: Callable) -> void:
		list = p_list
		factory = p_factory
		updater = p_updater

	## entries: [{npc_id, …}] en el orden en que se muestran.
	func sync(entries: Array[Dictionary]) -> void:
		var wanted: Dictionary = {}
		order.clear()
		pending.clear()
		for entry: Dictionary in entries:
			var npc_id: String = str(entry["npc_id"])
			wanted[npc_id] = true
			order.append(npc_id)
			if rows.has(npc_id):
				updater.call(rows[npc_id], entry)
			else:
				pending.append(entry)
		for npc_id: String in rows.keys():
			if not wanted.has(npc_id):
				var row: Control = rows[npc_id]
				rows.erase(npc_id)
				list.remove_child(row)
				row.queue_free()

	## Construye hasta `budget` filas pendientes y reordena. Devuelve si aún quedan.
	func build_some(budget: int) -> bool:
		var built: int = 0
		while not pending.is_empty() and built < maxi(budget, 1):
			var entry: Dictionary = pending.pop_front()
			var row: Control = factory.call(entry)
			rows[str(entry["npc_id"])] = row
			list.add_child(row)
			built += 1
		var index: int = 0
		for npc_id: String in order:
			if rows.has(npc_id):
				list.move_child(rows[npc_id], index)
				index += 1
		return not pending.is_empty()

	func get_row(npc_id: String) -> Control:
		return rows.get(npc_id) as Control

	func row_count() -> int:
		return rows.size()


var _title_count: Label
var _list: VBoxContainer
var _empty: Label
var _actions: PanelContainer
var _action_name: Label
var _action_note: Label
var _chat_button: PhoneOverlay.ActionTile
var _call_button: PhoneOverlay.ActionTile
var _deal_button: PhoneOverlay.ActionTile
var _rows: Array[Dictionary] = []
var _cache: RowCache
var _selected: String = ""
var _compact: bool = false


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
	_empty = PhoneOverlay.label(tr("PHONE_CONTACTS_EMPTY"), UITheme.V_SMALL, true)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	add_child(_empty)
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_list = parts["list"]
	add_child(parts["scroll"])
	_cache = RowCache.new(_list, _make_row, _update_row)
	add_child(_build_actions())
	set_process(false)


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
	_chat_button = PhoneOverlay.ActionTile.new(tr("PHONE_ACTION_CHAT"), "talk")
	_call_button = PhoneOverlay.ActionTile.new(tr("PHONE_ACTION_CALL"), "phone")
	_deal_button = PhoneOverlay.ActionTile.new(tr("PHONE_ACTION_DEAL"), "coin", true)
	for pair: Array in [[_chat_button, PhoneOverlay.ACTION_CHAT], [_call_button, PhoneOverlay.ACTION_CALL],
			[_deal_button, PhoneOverlay.ACTION_DEAL]]:
		var button: PhoneOverlay.ActionTile = pair[0]
		button.pressed.connect(_emit_action.bind(str(pair[1])))
		row.add_child(button)
	_actions.visible = false
	return _actions


func _process(_delta: float) -> void:
	if not _cache.build_some(PhoneOverlay.tune_i(B_ROWS_PER_FRAME)):
		set_process(false)


# ─── API ───────────────────────────────────────────────────────────

func refresh() -> void:
	_rows = list_contacts()
	_cache.sync(_rows)
	set_process(_cache.build_some(PhoneOverlay.tune_i(B_ROWS_PER_FRAME)))
	_empty.visible = _rows.is_empty()
	_title_count.text = str(_rows.size())
	if not has_contact(_selected):
		_selected = ""
	_update_actions()


## Construye ya todas las filas pendientes (pruebas y capturas).
func flush_rows() -> void:
	while _cache.build_some(_rows.size()):
		pass
	set_process(false)


func get_row_count() -> int:
	return _cache.row_count()


func get_row_node(npc_id: String) -> Control:
	return _cache.get_row(npc_id)


func is_building() -> bool:
	return is_processing()


func set_compact(on: bool) -> void:
	_compact = on
	for npc_id: String in _cache.rows:
		var photo: PhoneOverlay.Portrait = (_cache.rows[npc_id] as Control).get_meta("photo") as PhoneOverlay.Portrait
		photo.set_ems(PORTRAIT_EMS_COMPACT if on else PORTRAIT_EMS)


func get_rows() -> Array[Dictionary]:
	return _rows.duplicate(true)


func has_contact(npc_id: String) -> bool:
	for entry: Dictionary in _rows:
		if str(entry["npc_id"]) == npc_id:
			return true
	return false


func select(npc_id: String) -> void:
	_selected = npc_id if has_contact(npc_id) else ""
	for id: String in _cache.rows:
		_style_row(_cache.rows[id] as PanelContainer, id == _selected)
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
	var npc_id: String = str(entry["npc_id"])
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var row: PanelContainer = PanelContainer.new()
	row.set_meta(META_NPC, npc_id)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_row_input.bind(npc_id))
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var photo: PhoneOverlay.Portrait = PhoneOverlay.Portrait.new(PORTRAIT_EMS_COMPACT if _compact else PORTRAIT_EMS)
	photo.set_npc(npc)
	line.add_child(photo)
	row.set_meta("photo", photo)
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
	text.add_child(_source_chip(row))
	_update_row(row, entry)
	return row


## Chip de origen («Compañero», «Favores»…) o «Te ignora» si es un directivo fuera de alcance.
func _source_chip(row: PanelContainer) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("check", "gain", 0.7)
	line.add_child(dot)
	var chip: Label = PhoneOverlay.label("", UITheme.V_CAPTION)
	line.add_child(chip)
	row.set_meta("dot", dot)
	row.set_meta("chip", chip)
	return line


func _update_row(row: PanelContainer, entry: Dictionary) -> void:
	var answers: bool = bool(entry["answers"])
	var dot: PhoneOverlay.Glyph = row.get_meta("dot") as PhoneOverlay.Glyph
	var chip: Label = row.get_meta("chip") as Label
	dot.set_glyph("check" if answers else "no_entry", UITheme.color("gain" if answers else "loss"))
	var text: String = tr(str(SOURCE_KEYS.get(str(entry["source"]), "PHONE_SOURCE_COLLEAGUE")))
	chip.text = (text if answers else tr("PHONE_CONTACT_IGNORES_SHORT")).to_upper()
	chip.add_theme_color_override("font_color", UITheme.color("muted" if answers else "loss"))
	_style_row(row, str(entry["npc_id"]) == _selected)


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
	_call_button.queue_redraw()
	_deal_button.queue_redraw()


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


## Origen derivado del estado existente (respaldo si PlayerState no guarda contactos).
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


static func canonical_source(source: String) -> String:
	return str(SOURCE_ALIASES.get(source, source))


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
	return {"npc_id": npc.id, "name": npc.name, "tier": npc.tier, "source": canonical_source(source),
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
