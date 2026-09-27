# files_app.gd — FILES de StellarOS (§13.3, §11.1, PASO 25): archivos propios (informes, ideas, documentos), ajenos según el puesto (unidad compartida) y, por intrusión, los del dueño del equipo, con copia de ideas y documentos.
# PROPIETARIO DE: nada (los listados se derivan cada vez de PlayerState, DutySystem, IdeaPool, NPCDirector y data/rooms; aquí solo la carpeta y el archivo seleccionados).
# ESCUCHA: idea_acquired, inventory_changed, duty_completed (mientras está abierta, para refrescar).
class_name FilesApp
extends OSApp

## DECISIONES:
##  · Sesión propia: «Informes» (deberes cumplidos hoy + salidas de A.S.S.I.S.T. de
##    DutySystem.get_assist_log: el rastro digital también está aquí), «Ideas» (IdeaPool, en tu
##    poder), «Documentos» (documentos del inventario), «Unidad compartida» (ver abajo) y una
##    papelera de broma.
##  · «Según rango» (§13.3): la unidad compartida S:\ muestra archivos AJENOS de solo lectura. Con
##    el acceso especial others_computers (IT: técnico, jefe de equipo, director) ve todos los
##    ordenadores del edificio; desde el escalón ordenador.unidad_compartida_escalon_min, los de su
##    equipo (escalón inferior y mismo departamento). Lista los documentos de cada ordenador
##    (data/rooms, interactivo npc_computer) y los borradores de ideas vivas de sus dueños: es
##    información para planear una intrusión; copiar exige estar en el puesto del dueño (§11.1).
##  · Sesión de invitado (intrusión, StellarOS.open_intrusion): «Ideas» del dueño
##    (IdeaPool.get_ideas_by_owner, vivas), «Documentos» (contains del interactivo npc_computer
##    de data/rooms, o context.contains) y «Personal» (archivos de relleno, solo lectura).
##  · Copiar una idea = IdeaPool.acquire(id, "steal_file"): comprueba los requisitos de §11.1
##    (dueño fuera de su puesto, jugador en él) y ya emite idea_acquired y
##    crime_committed("file_copied") — el registro digital lo crean quienes escuchan. Aquí no se
##    vuelve a emitir el delito (sería doble).
##  · Copiar un documento = UNA copia NO apilable al inventario (el objeto del catálogo si el id
##    existe; si no, ordenador.objeto_copia_documento) con extra {document_id, source_npc,
##    name_key, stackable: false}: cada documento ocupa su hueco y conserva su identidad, y un
##    documento ya copiado no se vuelve a copiar (ni a denunciar). Emite
##    crime_committed("file_copied", sala, {document_id, owner, subject: "player", computer_id}) y
##    notebook_entry_added("files", NOTE_FILE_COPIED_DOC, [clave del nombre, dueño]).

const FOLDER_REPORTS := "reports"
const FOLDER_IDEAS := "ideas"
const FOLDER_DOCUMENTS := "documents"
const FOLDER_SHARED := "shared"
const FOLDER_TRASH := "trash"
const FOLDER_PERSONAL := "personal"
const OWN_FOLDERS: Array[String] = [FOLDER_REPORTS, FOLDER_IDEAS, FOLDER_DOCUMENTS, FOLDER_SHARED, FOLDER_TRASH]
const GUEST_FOLDERS: Array[String] = [FOLDER_IDEAS, FOLDER_DOCUMENTS, FOLDER_PERSONAL]
const FOLDER_ICONS: Dictionary = {
	FOLDER_REPORTS: "report", FOLDER_IDEAS: "idea", FOLDER_DOCUMENTS: "folder", FOLDER_TRASH: "trash",
	FOLDER_PERSONAL: "personal", FOLDER_SHARED: "shared",
}
const ACTION_COPY_IDEA := "copy_idea"
const ACTION_COPY_DOC := "copy_doc"
const METHOD_STEAL_FILE := "steal_file"
const CRIME_FILE_COPIED := "file_copied"
const B_COPY_ITEM := "ordenador.objeto_copia_documento"
const B_SHARED_TIER := "ordenador.unidad_compartida_escalon_min"
const B_DISK_MB := "ordenador.disco_mb_por_nivel"
const B_DISK_USED := "ordenador.disco_ocupado_por_nivel"
const ACCESS_OTHERS := "others_computers"
const SHARED_NONE := ""
const SHARED_ALL := "all"
const SHARED_TEAM := "team"
const GENERATED_OWNER := "generated"
const DEPARTMENT_KEY := "department"
const EXTRA_STACKABLE := "stackable"
const NOTE_CATEGORY := "files"
const NPC_COMPUTER := "npc_computer"
const KIND_DOCUMENT := "document"
const STATUS_COMPLETED := "completed"
const DOC_KEY_FORMAT := "FILES_DOC_%s"
const DOC_GENERIC_KEY := "FILES_DOC_GENERIC"
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
var _disk: FilesDiskGauge


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


## Indicador de disco al pie de las carpetas: el equipo barato siempre está lleno (§13.3: la
## mejora con el rango debe notarse); el del R33 no tiene límite.
class FilesDiskGauge extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var capacity_mb: float = 0.0
	var used: float = 0.0

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		custom_minimum_size = Vector2(0, base * 3.1)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var fs: int = roundi(base * OSTheme.RATIO_SMALL)
		var ink: Color = OSTheme.col(pal, "text")
		OSTheme.draw_icon(self, "disk", Rect2(Vector2(0, base * 0.1), Vector2(base * 1.3, base * 1.3)), pal)
		draw_string(f, Vector2(base * 1.6, base * 0.95), OSApp.t("FILES_DISK_LABEL"), HORIZONTAL_ALIGNMENT_LEFT,
				size.x - base * 1.6, fs, ink)
		var bar: Rect2 = Rect2(0, base * 1.5, size.x, base * 0.75)
		OSTheme.draw_bevel(self, bar, pal, true, base)
		var inner: Rect2 = bar.grow(-OSTheme.bevel_width(base) * 2.5)
		var fill: Color = OSTheme.col(pal, "bad") if used > 0.9 else OSTheme.col(pal, "select")
		if capacity_mb > 0.0:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(used, 0.0, 1.0), inner.size.y)), fill)
		draw_string(UITheme.font(UITheme.FONT_REGULAR), Vector2(0, base * 2.95), _caption(), HORIZONTAL_ALIGNMENT_LEFT,
				size.x, fs, OSTheme.col(pal, "muted"))

	func _caption() -> String:
		if capacity_mb <= 0.0:
			return OSApp.t("FILES_DISK_UNLIMITED")
		return OSApp.t("FILES_DISK_FREE", [String.num(capacity_mb * (1.0 - used), 1), String.num(capacity_mb, 0)])


# ─── Construcción ─────────────────────────────────────────────────

func build() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	col.add_child(_guest_header() if is_guest() else _address_bar())
	var h: HBoxContainer = HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(h)
	h.add_child(_folder_column())
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
	EventBus.idea_acquired.connect(request_refresh.unbind(2))
	EventBus.inventory_changed.connect(request_refresh.unbind(2))
	EventBus.duty_completed.connect(request_refresh.unbind(3))


func _folder_column() -> PanelContainer:
	var folders: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folders.size_flags_stretch_ratio = 0.5
	var col: VBoxContainer = VBoxContainer.new()
	folders.add_child(col)
	var fscroll: ScrollContainer = make_scroll_list()
	_folder_list = fscroll.get_child(0) as VBoxContainer
	col.add_child(fscroll)
	_disk = FilesDiskGauge.new(pal, base)
	col.add_child(_disk)
	return folders


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
	if not get_folders().has(_folder):
		_folder = get_folders()[0]
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
		_file_list.add_child(_empty_state())
	if _find(_selected).is_empty():
		_selected = str(_files[0]["id"]) if not _files.is_empty() else ""
	_show_preview(_find(_selected))
	if _address != null:
		_address.text = t("FILES_PATH", [t("FILES_FOLDER_" + _folder.to_upper())])
	_update_disk()


func get_folders() -> Array[String]:
	if is_guest():
		return GUEST_FOLDERS
	var out: Array[String] = OWN_FOLDERS.duplicate()
	if shared_access().is_empty():
		out.erase(FOLDER_SHARED)
	return out


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
		FOLDER_SHARED:
			return [] if is_guest() else _shared_files()
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


## Acceso a archivos ajenos por puesto: SHARED_ALL (others_computers), SHARED_TEAM (desde el
## escalón ordenador.unidad_compartida_escalon_min) o SHARED_NONE.
static func shared_access() -> String:
	var occ: OccupationData = PlayerState.get_occupation()
	if occ == null:
		return SHARED_NONE
	if occ.special_access.has(ACCESS_OTHERS):
		return SHARED_ALL
	var min_tier: int = Database.get_balance_int(B_SHARED_TIER)
	return SHARED_TEAM if min_tier > 0 and occ.tier >= min_tier else SHARED_NONE


## Ordenadores de data/rooms con documentos: [{computer_id, room_id, owner, contains}].
static func computers_with_documents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: RoomData in Database.get_all_rooms():
		for it: Dictionary in room.interactables:
			if str(it.get("type", "")) == NPC_COMPUTER and it.get("contains") is Array:
				out.append({"computer_id": str(it.get("id", "")), "room_id": room.id,
						"owner": str(it.get("owner", "")), "contains": it["contains"]})
	return out


# ─── Listados propios ─────────────────────────────────────────────

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
	var log_entries: Array[Dictionary] = ds.get_assist_log() if ds != null else []
	for i: int in range(log_entries.size() - 1, -1, -1):
		var e: Dictionary = log_entries[i]
		out.append(_file("assist_%d" % i, "doc", t("FILES_ASSIST_NAME", [int(e.get("day", 0)), int(e.get("hour", 0)), i + 1]),
				t("FILES_ASSIST_META", [AssistApp.task_name(str(e.get("task_type", ""))),
				t("ASSIST_BADGE_" + str(e.get("result", "")).to_upper())]), t("FILES_ASSIST_BODY")))
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
		var source: String = str(item.extra.get("source_npc", ""))
		var meta: String = t("FILES_DOC_META_HOT") if item.is_compromising() else t("FILES_DOC_META")
		if not source.is_empty():
			meta = t("FILES_DOC_META_SOURCE", [meta, npc_name(source)])
		var f: Dictionary = _file("item_%s_%d" % [item.id, out.size()], "doc", t(name_key), meta, t("FILES_DOC_PAPER"))
		if item.is_compromising():
			f["tag"] = t("FILES_TAG_CONFIDENTIAL")
			f["tag_color"] = c("bad")
		out.append(f)
	return out


## Unidad compartida (solo lectura): documentos y borradores de ideas de los ordenadores a los que
## el puesto da acceso.
func _shared_files() -> Array[Dictionary]:
	var access: String = shared_access()
	var out: Array[Dictionary] = []
	if access.is_empty():
		return out
	for pc: Dictionary in computers_with_documents():
		var owner: String = str(pc["owner"])
		if not _shares_with_player(owner, access):
			continue
		for doc: Variant in pc["contains"]:
			out.append(_shared_document(str(doc), owner, str(pc["room_id"])))
	for idea: Idea in IdeaPool.get_available_ideas():
		if _shares_with_player(idea.owner, access) and not idea.presented:
			out.append(_shared_idea(idea))
	return out


func _shared_document(doc_id: String, owner: String, room_id: String) -> Dictionary:
	var who: String = npc_name(owner) if owner != GENERATED_OWNER else t("FILES_SHARED_WORKSTATION")
	var f: Dictionary = _file("shared_%s_%s" % [owner, doc_id], "report", doc_display_name(doc_id),
			t("FILES_SHARED_META", [who, _room_name(room_id)]), t("FILES_SHARED_DOC_BODY", [who]))
	f["tag"] = t("FILES_TAG_READ_ONLY")
	return f


func _shared_idea(idea: Idea) -> Dictionary:
	var who: String = npc_name(idea.owner)
	var f: Dictionary = _file("shared_idea_" + idea.id, "idea", t("FILES_SHARED_IDEA_NAME", [_idea_label(idea)]),
			t("FILES_SHARED_IDEA_META", [who, idea.quality, idea.freshness]), t("FILES_SHARED_IDEA_BODY", [who]))
	f["tag"] = t("FILES_TAG_READ_ONLY")
	return f


## SHARED_ALL: cualquier ordenador; SHARED_TEAM: personajes activos de escalón inferior y del mismo
## departamento que el puesto del jugador.
func _shares_with_player(owner: String, access: String) -> bool:
	if access == SHARED_ALL:
		return owner != PLAYER_ID
	var npc: NPCRuntime = NPCDirector.get_npc(owner)
	var occ: OccupationData = PlayerState.get_occupation()
	if npc == null or not npc.alive or occ == null:
		return false
	return npc.tier < occ.tier and npc.department == str(occ.extra.get(DEPARTMENT_KEY, ""))


# ─── Listados del invitado ────────────────────────────────────────

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
		f["done"] = has_copy(doc_id)
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
	for pc: Dictionary in computers_with_documents():
		if str(pc["owner"]) == get_npc_id():
			return pc["contains"]
	return []


## true si el jugador ya lleva una copia de ese documento (por id de catálogo o por document_id).
static func has_copy(doc_id: String) -> bool:
	if PlayerState.is_carrying(doc_id):
		return true
	for item: ItemData in PlayerState.get_inventory():
		if str(item.extra.get("document_id", "")) == doc_id:
			return true
	return false


## Clave del nombre visible de un documento: la del catálogo de objetos, FILES_DOC_<ID> o la genérica.
static func doc_name_key(doc_id: String) -> String:
	var item: ItemData = Database.get_item(doc_id)
	if item != null:
		return item.name_key
	var key: String = DOC_KEY_FORMAT % doc_id.to_upper()
	return key if TranslationServer.translate(key) != key else DOC_GENERIC_KEY


static func doc_display_name(doc_id: String) -> String:
	return t(doc_name_key(doc_id))


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
	if has_copy(doc_id):
		refresh()
		return false
	var item: ItemData = make_document_copy(doc_id, get_npc_id())
	if item == null:
		return false
	if not PlayerState.add_item_data(item):
		post_status(t("FILES_STATUS_NO_SPACE"))
		return false
	var extra: Dictionary = context.get("extra", {}) as Dictionary
	EventBus.crime_committed.emit(CRIME_FILE_COPIED, _crime_room(), {"document_id": doc_id,
			"owner": get_npc_id(), "subject": PLAYER_ID, "computer_id": str(extra.get("computer_id", ""))})
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, "NOTE_FILE_COPIED_DOC", [doc_name_key(doc_id),
			npc_name(get_npc_id())])
	post_status(t("FILES_STATUS_DOC_COPIED", [str(f["name"])]))
	refresh()
	return true


## Copia física de un documento ajeno: el objeto del catálogo (si existe) o el genérico de balance,
## siempre NO apilable y con su identidad en extra. null si el catálogo no tiene ninguno.
static func make_document_copy(doc_id: String, owner: String) -> ItemData:
	var item: ItemData = Database.get_item(doc_id)
	var key: String = item.name_key if item != null else doc_name_key(doc_id)
	if item == null:
		item = Database.get_item(str(Database.get_balance(B_COPY_ITEM)))
	if item == null:
		return null
	item.extra[EXTRA_STACKABLE] = false
	item.extra["document_id"] = doc_id
	item.extra["source_npc"] = owner
	item.extra["name_key"] = key
	item.stack = 1
	return item


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


func _room_name(room_id: String) -> String:
	var room: RoomData = Database.get_room(room_id)
	return t(room.name_key) if room != null else room_id


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


## Carpeta vacía: icono grande y una frase de la casa (en vez de una línea suelta).
func _empty_state() -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = base * 14.0
	var art: OSApp.OSIcon = make_icon(str(FOLDER_ICONS.get(_folder, "folder")), 4.5)
	art.modulate.a = 0.45
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)
	var key: String = "FILES_EMPTY_%s%s" % [_folder.to_upper(), "_GUEST" if is_guest() else ""]
	var text: Label = make_label(t(key), OSTheme.V_MUTED, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	return box


func _update_disk() -> void:
	_disk.visible = not is_guest()
	_disk.capacity_mb = OSTheme.per_tier(B_DISK_MB, get_tier())
	_disk.used = OSTheme.per_tier(B_DISK_USED, get_tier())
	_disk.queue_redraw()


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
