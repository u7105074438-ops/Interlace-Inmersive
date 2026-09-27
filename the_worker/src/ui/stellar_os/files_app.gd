# files_app.gd — FILES de StellarOS (§13.3, §11.1, PASO 25): archivos propios (informes, ideas, documentos) y, por intrusión, los del dueño del equipo, con copia de ideas y documentos.
# PROPIETARIO DE: nada (los listados se derivan cada vez de PlayerState, DutySystem, IdeaPool y data/rooms; aquí solo la carpeta y el archivo seleccionados).
# ESCUCHA: idea_acquired, inventory_changed, duty_completed (mientras está abierta, para refrescar).
class_name FilesApp
extends OSApp

## DECISIONES:
##  · Sesión propia: «Informes» (deberes cumplidos hoy + salidas de A.S.S.I.S.T. de
##    DutySystem.get_assist_log: el rastro digital también está aquí), «Ideas» (IdeaPool, en tu
##    poder), «Documentos» (documentos del inventario) y una papelera de broma.
##  · Sesión de invitado (intrusión, StellarOS.open_intrusion): «Ideas» del dueño
##    (IdeaPool.get_ideas_by_owner, vivas), «Documentos» (contains del interactivo npc_computer
##    de data/rooms, o context.contains) y «Personal» (archivos de relleno, solo lectura).
##  · Copiar una idea = IdeaPool.acquire(id, "steal_file"): comprueba los requisitos de §11.1
##    (dueño fuera de su puesto, jugador en él) y ya emite idea_acquired y
##    crime_committed("file_copied") — el registro digital lo crean quienes escuchan. Aquí no se
##    vuelve a emitir el delito (sería doble).
##  · Copiar un documento = una copia al inventario (el objeto del catálogo si el id existe; si no,
##    ordenador.objeto_copia_documento con extra {document_id, source_npc, name_key}) +
##    crime_committed("file_copied", sala, {document_id, owner, subject: "player", computer_id}) +
##    notebook_entry_added("files", ...).

const FOLDER_REPORTS := "reports"
const FOLDER_IDEAS := "ideas"
const FOLDER_DOCUMENTS := "documents"
const FOLDER_TRASH := "trash"
const FOLDER_PERSONAL := "personal"
const OWN_FOLDERS: Array[String] = [FOLDER_REPORTS, FOLDER_IDEAS, FOLDER_DOCUMENTS, FOLDER_TRASH]
const GUEST_FOLDERS: Array[String] = [FOLDER_IDEAS, FOLDER_DOCUMENTS, FOLDER_PERSONAL]
const FOLDER_ICONS: Dictionary = {
	FOLDER_REPORTS: "report", FOLDER_IDEAS: "idea", FOLDER_DOCUMENTS: "folder", FOLDER_TRASH: "trash",
	FOLDER_PERSONAL: "personal",
}
const ACTION_COPY_IDEA := "copy_idea"
const ACTION_COPY_DOC := "copy_doc"
const METHOD_STEAL_FILE := "steal_file"
const CRIME_FILE_COPIED := "file_copied"
const B_COPY_ITEM := "ordenador.objeto_copia_documento"
const NOTE_CATEGORY := "files"
const NPC_COMPUTER := "npc_computer"
const KIND_DOCUMENT := "document"
const STATUS_COMPLETED := "completed"
const DOC_KEY_FORMAT := "FILES_DOC_%s"
## Contenido (no ajustes): archivos de relleno traducidos.
const PERSONAL_COUNT := 10
const PERSONAL_SHOWN := 4
const TRASH_COUNT := 3
const PERCENT := 100.0

var _folder: String = ""
var _selected: String = ""
var _files: Array[Dictionary] = []
var _folder_list: VBoxContainer
var _file_list: VBoxContainer
var _preview_icon: OSApp.OSIcon
var _preview_title: Label
var _preview_meta: Label
var _preview_body: Label
var _action: Button
var _address: Label


## Foto del dueño del equipo (sesión de invitado).
class FilesPortraitView extends Control:
	var pal: Dictionary = {}
	var appearance: Dictionary = {}

	func _init(p: Dictionary, side: float, app: Dictionary) -> void:
		pal = p
		appearance = app
		custom_minimum_size = Vector2(side, side)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, OSTheme.col(pal, "field"))
		if appearance.is_empty():
			OSTheme.draw_icon(self, "user", r, pal)
		else:
			CharacterPainter.draw_portrait(self, appearance, r)
		draw_rect(r, OSTheme.col(pal, "dark"), false, 2.0)


# ─── Construcción ─────────────────────────────────────────────────

func build() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	col.add_child(_guest_header() if is_guest() else _address_bar())
	var h: HBoxContainer = HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(h)
	var folders: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folders.size_flags_stretch_ratio = 0.5
	var fscroll: ScrollContainer = make_scroll_list()
	_folder_list = fscroll.get_child(0) as VBoxContainer
	folders.add_child(fscroll)
	h.add_child(folders)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.5
	h.add_child(right)
	var files: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = make_scroll_list()
	_file_list = scroll.get_child(0) as VBoxContainer
	files.add_child(scroll)
	right.add_child(files)
	right.add_child(_preview_panel())
	_folder = GUEST_FOLDERS[0] if is_guest() else OWN_FOLDERS[0]
	EventBus.idea_acquired.connect(_on_world_changed.unbind(2))
	EventBus.inventory_changed.connect(_on_world_changed.unbind(2))
	EventBus.duty_completed.connect(_on_world_changed.unbind(3))


func _address_bar() -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_child(make_label(t("FILES_ADDRESS"), OSTheme.V_HEADING))
	var field: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address = make_label("", OSTheme.V_MONO, false, true)
	field.add_child(_address)
	h.add_child(field)
	return h


func _guest_header() -> PanelContainer:
	var panel: PanelContainer = make_panel(OSTheme.V_RAISED)
	var h: HBoxContainer = HBoxContainer.new()
	panel.add_child(h)
	var npc: NPCRuntime = NPCDirector.get_npc(get_npc_id())
	h.add_child(FilesPortraitView.new(pal, base * 3.6, CharacterPainter.appearance_for_npc(npc) if npc != null else {}))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	col.add_child(make_label(t("FILES_GUEST_TITLE", [npc_name(get_npc_id())]), OSTheme.V_TITLE, false, true))
	var occ: OccupationData = Database.get_occupation(npc.occupation_id) if npc != null else null
	var post: String = t(occ.name_key) if occ != null else ""
	var room: String = _room_label()
	var sub: String = post if room.is_empty() or post.contains(room) else t("FILES_GUEST_SUB", [post, room])
	col.add_child(make_label(sub, OSTheme.V_MUTED, true))
	var warn: Label = make_label(t("FILES_GUEST_WARNING"), OSTheme.V_SMALL, true)
	warn.add_theme_color_override("font_color", c("bad"))
	col.add_child(warn)
	_address = null
	return panel


func _preview_panel() -> PanelContainer:
	var panel: PanelContainer = make_panel(OSTheme.V_RAISED)
	panel.custom_minimum_size.y = base * 9.0
	var h: HBoxContainer = HBoxContainer.new()
	panel.add_child(h)
	_preview_icon = make_icon("doc", 4.0)
	_preview_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(_preview_icon)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", roundi(base * 0.15))
	h.add_child(col)
	_preview_title = make_label("", OSTheme.V_TITLE, true)
	col.add_child(_preview_title)
	_preview_meta = make_label("", OSTheme.V_MUTED, true)
	col.add_child(_preview_meta)
	_preview_body = make_label("", "", true)
	col.add_child(_preview_body)
	_action = make_button("", _on_action, OSTheme.V_DANGER if is_guest() else OSTheme.V_PRIMARY)
	_action.size_flags_vertical = Control.SIZE_SHRINK_END
	_action.custom_minimum_size.x = base * 9.0
	h.add_child(_action)
	return panel


func _ready() -> void:
	refresh()


func get_title_key() -> String:
	return "FILES_WINDOW_TITLE_GUEST" if is_guest() else "FILES_WINDOW_TITLE"


# ─── API ──────────────────────────────────────────────────────────

func refresh() -> void:
	_fill_folders()
	_files = list_files(_folder)
	OSApp.clear_children(_file_list)
	for f: Dictionary in _files:
		var row: OSApp.OSRow = make_row(str(f["icon"]), str(f["name"]), str(f["meta"]), str(f.get("tag", "")))
		row.set_tag_color(f.get("tag_color", c("muted")))
		row.set_selected(str(f["id"]) == _selected)
		row.pressed.connect(select_file.bind(str(f["id"])))
		_file_list.add_child(row)
	if _files.is_empty():
		_file_list.add_child(make_label(t("FILES_EMPTY_FOLDER"), OSTheme.V_MUTED, true))
	if _find(_selected).is_empty():
		_selected = str(_files[0]["id"]) if not _files.is_empty() else ""
	_show_preview(_find(_selected))
	if _address != null:
		_address.text = t("FILES_PATH", [t("FILES_FOLDER_" + _folder.to_upper())])


func get_folders() -> Array[String]:
	return GUEST_FOLDERS if is_guest() else OWN_FOLDERS


func open_folder(folder: String) -> void:
	if get_folders().has(folder):
		_folder = folder
		_selected = ""
	refresh()


func get_folder() -> String:
	return _folder


func select_file(file_id: String) -> void:
	_selected = file_id
	refresh()


func get_selected() -> String:
	return _selected


## Archivos de una carpeta: [{id, icon, name, meta, body, action, idea_id, doc_id, done, tag, tag_color}].
func list_files(folder: String) -> Array[Dictionary]:
	match folder:
		FOLDER_REPORTS:
			return _reports()
		FOLDER_IDEAS:
			return _guest_ideas() if is_guest() else _own_ideas()
		FOLDER_DOCUMENTS:
			return _guest_documents() if is_guest() else _own_documents()
		FOLDER_PERSONAL:
			return _personal_files()
		FOLDER_TRASH:
			return _trash_files()
	return []


## Copia el archivo (idea o documento ajeno). Devuelve true si se copió. Usar con await.
func copy_file(file_id: String) -> bool:
	var f: Dictionary = _find(file_id)
	if f.is_empty() or bool(f.get("done", false)):
		return false
	match str(f.get("action", "")):
		ACTION_COPY_IDEA:
			return await _copy_idea(f)
		ACTION_COPY_DOC:
			return await _copy_document(f)
	return false


# ─── Listados ─────────────────────────────────────────────────────

func _reports() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = 0
	for duty: Dictionary in PlayerState.get_todays_duties():
		if str(duty.get("status", "")) != STATUS_COMPLETED:
			continue
		n += 1
		var method: String = str(duty.get("method", ""))
		out.append(_file("report_%s" % duty.get("id", ""), "report", t("FILES_REPORT_NAME", [GameClock.get_day(), n]),
				t("FILES_REPORT_META", [t(str(duty.get("name_key", ""))), roundi(float(duty.get("quality", 0.0)) * PERCENT)]),
				t("FILES_REPORT_BODY_" + method.to_upper()) if not method.is_empty() else ""))
	var ds: DutySystem = duty_system()
	var log_entries: Array[Dictionary] = []
	if ds != null:
		log_entries = ds.get_assist_log()
	for i: int in range(log_entries.size() - 1, -1, -1):
		var e: Dictionary = log_entries[i]
		out.append(_file("assist_%d" % i, "doc", t("FILES_ASSIST_NAME", [int(e.get("day", 0)), int(e.get("hour", 0)), i + 1]),
				t("FILES_ASSIST_META", [str(e.get("task_type", "")), t("ASSIST_BADGE_" + str(e.get("result", "")).to_upper())]),
				t("FILES_ASSIST_BODY")))
	return out


func _own_ideas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for idea: Idea in IdeaPool.get_player_ideas():
		var method_key: String = "IDEA_METHOD_" + idea.acquisition_method.to_upper()
		var f: Dictionary = _file("idea_" + idea.id, "idea", t("FILES_IDEA_NAME", [_idea_label(idea)]),
				t("FILES_IDEA_META", [idea.quality, idea.freshness]),
				t(idea.text_key) + "\n" + t("FILES_IDEA_ORIGIN", [npc_name(idea.owner), t(method_key)]))
		out.append(f)
	return out


func _own_documents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: ItemData in PlayerState.get_inventory():
		if str(item.extra.get("kind", "")) != KIND_DOCUMENT:
			continue
		var name_key: String = str(item.extra.get("name_key", item.name_key))
		var f: Dictionary = _file("item_%s_%d" % [item.id, out.size()], "doc", t(name_key),
				t("FILES_DOC_META_HOT") if item.is_compromising() else t("FILES_DOC_META"), t("FILES_DOC_PAPER"))
		if item.is_compromising():
			f["tag"] = t("FILES_TAG_CONFIDENTIAL")
			f["tag_color"] = c("bad")
		out.append(f)
	return out


func _guest_ideas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for idea: Idea in IdeaPool.get_ideas_by_owner(get_npc_id()):
		if idea.is_expired() or idea.presented:
			continue
		var f: Dictionary = _file("idea_" + idea.id, "idea", t("FILES_IDEA_NAME", [_idea_label(idea)]),
				t("FILES_IDEA_META", [idea.quality, idea.freshness]), t(idea.text_key))
		f["action"] = ACTION_COPY_IDEA
		f["idea_id"] = idea.id
		f["done"] = idea.acquired_by == PLAYER_ID
		f["block"] = IdeaPool.get_acquisition_block(idea.id, METHOD_STEAL_FILE)
		_tag_copyable(f)
		out.append(f)
	return out


func _guest_documents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for doc: Variant in computer_documents():
		var doc_id: String = str(doc)
		var f: Dictionary = _file("doc_" + doc_id, "report", doc_display_name(doc_id), t("FILES_DOC_META_HOT"),
				t("FILES_DOC_GUEST_BODY"))
		f["action"] = ACTION_COPY_DOC
		f["doc_id"] = doc_id
		f["done"] = _has_copy(doc_id)
		_tag_copyable(f)
		out.append(f)
	return out


func _personal_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var first: int = absi(hash(get_npc_id())) % PERSONAL_COUNT
	for k: int in PERSONAL_SHOWN:
		var i: int = (first + k * 3) % PERSONAL_COUNT + 1
		out.append(_file("personal_%d" % i, "personal", t("FILES_PERSONAL_%d" % i),
				t("FILES_PERSONAL_META"), t("FILES_PERSONAL_%d_BODY" % i)))
	return out


func _trash_files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(1, TRASH_COUNT + 1):
		out.append(_file("trash_%d" % i, "trash", t("FILES_TRASH_%d" % i), t("FILES_TRASH_META"),
				t("FILES_TRASH_%d_BODY" % i)))
	return out


## Documentos que guarda el ordenador intervenido (context.contains o data/rooms npc_computer).
func computer_documents() -> Array:
	var extra: Dictionary = context.get("extra", {}) as Dictionary
	if extra.get("contains") is Array:
		return extra["contains"]
	var npc_id: String = get_npc_id()
	for room: RoomData in Database.get_all_rooms():
		for it: Dictionary in room.interactables:
			if str(it.get("type", "")) == NPC_COMPUTER and str(it.get("owner", "")) == npc_id:
				return it.get("contains", []) if it.get("contains") is Array else []
	return []


## Nombre visible de un documento: el del catálogo de objetos o FILES_DOC_<ID>.
static func doc_display_name(doc_id: String) -> String:
	var item: ItemData = Database.get_item(doc_id)
	if item != null:
		return t(item.name_key)
	var key: String = DOC_KEY_FORMAT % doc_id.to_upper()
	var text: String = TranslationServer.translate(key)
	return text if text != key else t("FILES_DOC_GENERIC")


## Sufijo del nombre de archivo de una idea (su número, sin el prefijo del id).
static func _idea_label(idea: Idea) -> String:
	var parts: PackedStringArray = idea.id.split("_")
	return parts[parts.size() - 1] if not parts.is_empty() else idea.id


func _file(id: String, icon: String, file_name: String, meta: String, body: String) -> Dictionary:
	return {"id": id, "icon": icon, "name": file_name, "meta": meta, "body": body, "action": "",
			"done": false, "tag": "", "tag_color": c("muted")}


func _tag_copyable(f: Dictionary) -> void:
	if bool(f["done"]):
		f["tag"] = t("FILES_TAG_COPIED")
		f["tag_color"] = c("good")
	elif not str(f.get("block", "")).is_empty():
		f["tag"] = t("FILES_TAG_LOCKED")
		f["tag_color"] = c("warn")
	else:
		f["tag"] = t("FILES_TAG_VALUABLE")
		f["tag_color"] = c("accent")


func _find(file_id: String) -> Dictionary:
	for f: Dictionary in _files:
		if str(f["id"]) == file_id:
			return f
	return {}


func _has_copy(doc_id: String) -> bool:
	if PlayerState.is_carrying(doc_id):
		return true
	for item: ItemData in PlayerState.get_inventory():
		if str(item.extra.get("document_id", "")) == doc_id:
			return true
	return false


# ─── Copias ───────────────────────────────────────────────────────

func _copy_idea(f: Dictionary) -> bool:
	var idea_id: String = str(f["idea_id"])
	var block: String = IdeaPool.get_acquisition_block(idea_id, METHOD_STEAL_FILE)
	if not block.is_empty():
		post_status(t(IdeaPool.acquisition_block_key(block)))
		return false
	await wait_action(StellarOS.ACTION_COPY)
	var ok: bool = IdeaPool.acquire(idea_id, METHOD_STEAL_FILE)
	if ok:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, "NOTE_FILE_COPIED_IDEA", [npc_name(get_npc_id())])
		post_status(t("FILES_STATUS_IDEA_COPIED"))
	else:
		post_status(t(IdeaPool.acquisition_block_key(IdeaPool.get_acquisition_block(idea_id, METHOD_STEAL_FILE))))
	refresh()
	return ok


func _copy_document(f: Dictionary) -> bool:
	var doc_id: String = str(f["doc_id"])
	await wait_action(StellarOS.ACTION_COPY)
	var item: ItemData = Database.get_item(doc_id)
	if item == null:
		item = Database.get_item(str(Database.get_balance(B_COPY_ITEM)))
		if item == null:
			return false
		item.extra["document_id"] = doc_id
		item.extra["source_npc"] = get_npc_id()
		item.extra["name_key"] = DOC_KEY_FORMAT % doc_id.to_upper()
	if not PlayerState.add_item_data(item):
		post_status(t("FILES_STATUS_NO_SPACE"))
		return false
	var extra: Dictionary = context.get("extra", {}) as Dictionary
	EventBus.crime_committed.emit(CRIME_FILE_COPIED, _crime_room(), {"document_id": doc_id,
			"owner": get_npc_id(), "subject": PLAYER_ID, "computer_id": str(extra.get("computer_id", ""))})
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, "NOTE_FILE_COPIED_DOC", [str(f["name"]), npc_name(get_npc_id())])
	post_status(t("FILES_STATUS_DOC_COPIED", [str(f["name"])]))
	refresh()
	return true


func _crime_room() -> String:
	var extra: Dictionary = context.get("extra", {}) as Dictionary
	var room: String = str(extra.get("room_id", ""))
	if room.is_empty():
		room = PlayerState.get_room()
	if room.is_empty():
		var npc: NPCRuntime = NPCDirector.get_npc(get_npc_id())
		room = npc.home_room if npc != null else ""
	return room


func _room_label() -> String:
	var room: RoomData = Database.get_room(_crime_room())
	return t(room.name_key) if room != null else ""


# ─── Vista ────────────────────────────────────────────────────────

func _fill_folders() -> void:
	OSApp.clear_children(_folder_list)
	for folder: String in get_folders():
		var count: int = list_files(folder).size()
		var row: OSApp.OSRow = make_row(str(FOLDER_ICONS.get(folder, "folder")), t("FILES_FOLDER_" + folder.to_upper()),
				t("FILES_FOLDER_COUNT", [count]))
		row.set_selected(folder == _folder)
		row.pressed.connect(open_folder.bind(folder))
		_folder_list.add_child(row)


func _show_preview(f: Dictionary) -> void:
	_preview_icon.icon_id = str(f.get("icon", "doc"))
	_preview_icon.queue_redraw()
	_preview_title.text = str(f.get("name", t("FILES_NO_SELECTION")))
	_preview_meta.text = str(f.get("meta", ""))
	_preview_body.text = str(f.get("body", ""))
	var action: String = str(f.get("action", ""))
	_action.visible = not action.is_empty()
	_action.disabled = bool(f.get("done", false))
	_action.text = t("FILES_ACTION_COPIED") if bool(f.get("done", false)) else t("FILES_ACTION_COPY")
	var block: String = str(f.get("block", ""))
	if not block.is_empty() and not bool(f.get("done", false)):
		_preview_meta.text += "  ·  " + t(IdeaPool.acquisition_block_key(block))


func _on_action() -> void:
	if not _selected.is_empty():
		await copy_file(_selected)


func _on_world_changed() -> void:
	if is_inside_tree():
		refresh.call_deferred()
