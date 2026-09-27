# notebook_app.gd — NOTEBOOK de StellarOS (§13.3, PASO 25): notas libres del jugador y registro automático de objetivos marcados, favores pendientes, casos abiertos, ideas vigiladas y avisos.
# PROPIETARIO DE: nada (el bloc, las anotaciones, los objetivos y el registro viven en PlayerState; lo demás se deriva de sus dueños). Solo la pestaña visible.
# ESCUCHA: notebook_entry_added, favour_added, grievance_added, investigation_opened, investigation_resolved, idea_acquired (mientras está abierta, para refrescar).
class_name NotebookApp
extends OSApp

## DECISIONES:
##  · «La memoria externa del jugador en una partida de veinte horas»: todo lo automático se
##    DERIVA de los sistemas dueños en cada apertura (sin estado oculto):
##      objetivos   → PlayerState.get_marked_targets() (los marca PERSONNEL);
##      favores     → registro de NPCDirector (deuda ≠ 0: quién te debe y a quién debes);
##      casos       → Security (activos y fríos; «lista corta» si el jugador figura en ella);
##      ideas       → IdeaPool (ideas en tu poder y personajes con la señal de idea);
##      avisos      → PlayerState.get_notebook_entries() (todo notebook_entry_added de la partida);
##      anotaciones → PlayerState.get_notes() (las notas sobre personajes que escribe PERSONNEL).
##  · Bloc libre: PlayerState.get_notepad()/set_notepad(text), guardado con su save_state en cada
##    pulsación (sobrevive a cerrar el ordenador y a guardar/cargar).
##  · Tope de texto: ordenador.cuaderno_max_caracteres (PlayerState lo aplica también); entradas por
##    pestaña: ordenador.cuaderno_max_entradas.

const TAB_TARGETS := 0
const TAB_FAVOURS := 1
const TAB_CASES := 2
const TAB_IDEAS := 3
const TAB_LOG := 4
const TAB_PEOPLE := 5
const TAB_KEYS: Array[String] = ["NOTEBOOK_TAB_TARGETS", "NOTEBOOK_TAB_FAVOURS", "NOTEBOOK_TAB_CASES",
		"NOTEBOOK_TAB_IDEAS", "NOTEBOOK_TAB_LOG", "NOTEBOOK_TAB_PEOPLE"]
const B_MAX_CHARS := "ordenador.cuaderno_max_caracteres"
const B_MAX_ENTRIES := "ordenador.cuaderno_max_entradas"
const INCIDENT_KEY_FORMAT := "INCIDENT_%s"
const INCIDENT_UNKNOWN_KEY := "NOTEBOOK_INCIDENT_UNKNOWN"
const SEVERITY_KEY_FORMAT := "INV_SEVERITY_%d"
const NOTE_TEXT := "text"
const NOTE_NPC := "npc_id"
const CATEGORY_ICONS: Dictionary = {
	"duties": "report", "ideas": "idea", "files": "folder", "career": "portal", "security": "warning",
	"stash": "lock", "blackmail": "personal", "market": "market", "targets": "user",
	"personnel": "personnel", "study": "personnel",
}

var _paper: TextEdit
var _pad: NotebookLegalPad
var _saved: Label
var _tabs: TabBar
var _list: VBoxContainer
var _hint: Label
var _tab: int = TAB_TARGETS


## Bloc de notas amarillo con renglones y margen rojo (el TextEdit escribe encima).
class NotebookLegalPad extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var editor: TextEdit = null

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var contrast: bool = pal.get("skin") == OSTheme.SKIN_CONTRAST
		draw_rect(r, OSTheme.col(pal, "paper"))
		var strip: float = base * 0.9
		draw_rect(Rect2(0, 0, size.x, strip), Color("#8c2f2f") if not contrast else Color.WHITE)
		for i: int in 3:
			draw_circle(Vector2(size.x * (0.25 + i * 0.25), strip * 0.5), strip * 0.18, Color(0, 0, 0, 0.35))
		var step: float = editor.get_line_height() if editor != null else base * 1.4
		var top: float = editor.position.y + editor.get_theme_stylebox("normal").content_margin_top if editor != null else strip
		var y: float = top + step
		var line: Color = Color("#8fb0dc") if not contrast else Color(1, 1, 1, 0.4)
		while y < size.y:
			draw_rect(Rect2(0, roundf(y) - 1.0, size.x, 2.0), line)
			y += step
		draw_line(Vector2(base * 1.8, strip), Vector2(base * 1.8, size.y), Color("#e0645a"), 1.5)
		draw_rect(r, OSTheme.col(pal, "shadow"), false, 1.5)


# ─── Construcción ─────────────────────────────────────────────────

func build() -> void:
	var h: HBoxContainer = HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)
	h.add_child(_notes_column())
	h.add_child(_log_column())
	EventBus.notebook_entry_added.connect(request_refresh.unbind(3))
	EventBus.favour_added.connect(request_refresh.unbind(3))
	EventBus.grievance_added.connect(request_refresh.unbind(3))
	EventBus.investigation_opened.connect(request_refresh.unbind(3))
	EventBus.investigation_resolved.connect(request_refresh.unbind(3))
	EventBus.idea_acquired.connect(request_refresh.unbind(2))


func _notes_column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.9
	col.add_child(make_section(t("NOTEBOOK_MY_NOTES")))
	_pad = NotebookLegalPad.new(pal, base)
	col.add_child(_pad)
	_paper = TextEdit.new()
	_paper.theme_type_variation = "OSPaperEdit"
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paper.offset_top = base * 1.0
	_paper.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_paper.placeholder_text = t("NOTEBOOK_PLACEHOLDER")
	_paper.add_theme_font_override("font", UITheme.font(UITheme.FONT_SEMIBOLD))
	_paper.text_changed.connect(_on_text_changed)
	_pad.editor = _paper
	_pad.add_child(_paper)
	_paper.resized.connect(_pad.queue_redraw)
	_saved = make_label("", OSTheme.V_MUTED, true)
	col.add_child(_saved)
	return col


func _log_column() -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.1
	col.add_child(make_section(t("NOTEBOOK_AUTO_LOG")))
	_tabs = TabBar.new()
	_tabs.clip_tabs = true
	for key: String in TAB_KEYS:
		_tabs.add_tab(t(key))
	_tabs.tab_changed.connect(select_tab)
	col.add_child(_tabs)
	var panel: PanelContainer = make_panel(OSTheme.V_SUNKEN)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = make_scroll_list()
	_list = scroll.get_child(0) as VBoxContainer
	panel.add_child(scroll)
	col.add_child(panel)
	_hint = make_label("", OSTheme.V_MUTED, true)
	col.add_child(_hint)
	return col


func _ready() -> void:
	_paper.text = PlayerState.get_notepad()
	_update_saved_label()
	refresh()


func get_title_key() -> String:
	return "NOTEBOOK_WINDOW_TITLE"


func on_closing() -> void:
	save_notes()


# ─── API ──────────────────────────────────────────────────────────

func refresh() -> void:
	var sections: Array = _sections()
	for i: int in TAB_KEYS.size():
		_tabs.set_tab_title(i, t("NOTEBOOK_TAB_COUNT", [t(TAB_KEYS[i]), (sections[i] as Array).size()]))
	_tabs.current_tab = _tab
	_fill(sections[_tab] as Array)
	_hint.text = t("NOTEBOOK_HINT_%d" % _tab)


func select_tab(index: int) -> void:
	_tab = clampi(index, TAB_TARGETS, TAB_KEYS.size() - 1)
	refresh()


func get_tab() -> int:
	return _tab


func get_notes_text() -> String:
	return _paper.text


func set_notes_text(text: String) -> void:
	_paper.text = text
	_on_text_changed()


## Guarda el bloc en PlayerState (set_notepad; se guarda con la partida).
func save_notes() -> void:
	PlayerState.set_notepad(_paper.text)
	_update_saved_label()


## Filas visibles de la pestaña actual: [{icon, title, sub, tag, tag_color}].
func get_rows() -> Array:
	return _sections()[_tab]


func _sections() -> Array:
	return [targets(), favours(), cases(), ideas(), log_entries(), annotations()]


# ─── Secciones derivadas ──────────────────────────────────────────

func targets() -> Array:
	var out: Array = []
	for npc_id: String in PlayerState.get_marked_targets():
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		if npc == null:
			continue
		var occ: OccupationData = Database.get_occupation(npc.occupation_id)
		var where: String = _room_name(NPCDirector.get_current_location(npc.id))
		out.append(_entry("user", npc.name, t("NOTEBOOK_TARGET_SUB", [t(occ.name_key) if occ != null else "", where]),
				"" if npc.alive else t("NOTEBOOK_TAG_GONE"), c("bad")))
	return _capped(out)


func favours() -> Array:
	var rows: Array = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var debt: int = NPCDirector.get_debt(npc.id)
		if debt == 0:
			continue
		var owes_you: bool = debt > 0
		var title: String = t("NOTEBOOK_OWES_YOU" if owes_you else "NOTEBOOK_YOU_OWE", [npc.name, absi(debt)])
		rows.append({"abs": absi(debt), "row": _entry("personal" if owes_you else "warning", title,
				_last_favour(npc.id), t("NOTEBOOK_TAG_ASSET") if owes_you else t("NOTEBOOK_TAG_DEBT"),
				c("good") if owes_you else c("warn"))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["abs"]) > int(b["abs"]))
	var out: Array = []
	for r: Dictionary in rows:
		out.append(r["row"])
	return _capped(out)


func cases() -> Array:
	var out: Array = []
	var all: Array[Investigation] = Security.get_active_investigations()
	all.append_array(Security.get_cold_cases())
	for inv: Investigation in all:
		var cold: bool = inv.status == Investigation.STATUS_COLD
		var listed: bool = Security.is_player_in_shortlist(inv.id)
		var tag: String = t("NOTEBOOK_TAG_SHORTLIST") if listed else (t("NOTEBOOK_TAG_COLD") if cold else "")
		out.append(_entry("warning" if listed else "report", t("NOTEBOOK_CASE", [_incident_name(inv.incident_type)]),
				t("NOTEBOOK_CASE_SUB", [_phase_name(inv.phase), t(SEVERITY_KEY_FORMAT % clampi(inv.severity, 1, 5)),
				inv.opened_day, _room_name(inv.location)]), tag, c("bad") if listed else c("muted")))
	return _capped(out)


func ideas() -> Array:
	var out: Array = []
	for idea: Idea in IdeaPool.get_player_ideas():
		out.append(_entry("idea", t(idea.text_key), t("NOTEBOOK_IDEA_HELD", [npc_name(idea.owner), idea.quality,
				idea.freshness]), t("NOTEBOOK_TAG_YOURS"), c("good")))
	for sig: Dictionary in IdeaPool.get_signalling_npcs():
		var owner: String = str(sig.get("npc_id", ""))
		out.append(_entry("star", t("NOTEBOOK_IDEA_SIGNAL", [npc_name(owner)]),
				t("NOTEBOOK_IDEA_SIGNAL_SUB", [_room_name(NPCDirector.get_current_location(owner)),
				UITheme.format_hour(int(sig.get("until_hour", 0)))]), t("NOTEBOOK_TAG_WATCH"), c("accent")))
	return _capped(out)


## Avisos del cuaderno, del más reciente al más antiguo.
func log_entries() -> Array:
	var raw: Array[Dictionary] = PlayerState.get_notebook_entries()
	var out: Array = []
	for i: int in range(raw.size() - 1, -1, -1):
		var e: Dictionary = raw[i]
		var args: Array = []
		for a: Variant in e.get("args", []):
			args.append(tr(str(a)) if a is String else a)
		var category: String = str(e.get("category", ""))
		out.append(_entry(str(CATEGORY_ICONS.get(category, "doc")), t(str(e.get("text_key", "")), args),
				t("NOTEBOOK_LOG_WHEN", [int(e.get("day", 0)), UITheme.format_hour(int(e.get("hour", 0)),
				int(e.get("minute", 0)))]), "", c("muted")))
	return _capped(out)


## Anotaciones sobre personajes (PERSONNEL → PlayerState.add_note), de la más reciente a la más antigua.
func annotations() -> Array:
	var notes: Array[Dictionary] = PlayerState.get_notes()
	var out: Array = []
	for i: int in range(notes.size() - 1, -1, -1):
		var note: Dictionary = notes[i]
		var npc_id: String = str(note.get(NOTE_NPC, ""))
		var when: String = t("NOTEBOOK_LOG_WHEN", [int(note.get("day", 0)), UITheme.format_hour(int(note.get("hour", 0)),
				int(note.get("minute", 0)))])
		var sub: String = t("NOTEBOOK_NOTE_ABOUT", [npc_name(npc_id), when]) if not npc_id.is_empty() else when
		out.append(_entry("personnel" if not npc_id.is_empty() else "notebook", str(note.get(NOTE_TEXT, "")), sub,
				"", c("muted")))
	return _capped(out)


# ─── Vista ────────────────────────────────────────────────────────

func _fill(entries: Array) -> void:
	OSApp.clear_children(_list)
	for e: Dictionary in entries:
		var row: OSApp.OSRow = make_row(str(e["icon"]), str(e["title"]), str(e["sub"]), str(e["tag"]))
		row.set_tag_color(e["tag_color"])
		row.mouse_default_cursor_shape = Control.CURSOR_ARROW
		_list.add_child(row)
	if entries.is_empty():
		var empty: Label = make_label(t("NOTEBOOK_EMPTY_%d" % _tab), OSTheme.V_MUTED, true)
		_list.add_child(empty)


func _entry(icon: String, title: String, sub: String, tag: String, tag_color: Color) -> Dictionary:
	return {"icon": icon, "title": title, "sub": sub, "tag": tag, "tag_color": tag_color}


func _capped(entries: Array) -> Array:
	var cap: int = UITheme.tune_int(B_MAX_ENTRIES)
	return entries.slice(0, cap) if cap > 0 else entries


func _last_favour(npc_id: String) -> String:
	var ledger: Dictionary = NPCDirector.get_ledger(npc_id)
	var favours_list: Array = ledger.get("favours", []) as Array
	if favours_list.is_empty():
		return ""
	var last: Dictionary = favours_list.back()
	return t("NOTEBOOK_FAVOUR_LAST", [t(NPCDirectorSystem.favour_name_key(str(last.get("type", "")))),
			int(last.get("day", 0))])


func _incident_name(incident_type: String) -> String:
	var key: String = INCIDENT_KEY_FORMAT % incident_type.to_upper()
	var text: String = tr(key)
	return text if text != key else t(INCIDENT_UNKNOWN_KEY)


func _phase_name(phase: int) -> String:
	for entry: Variant in Database.get_investigation_params().get("phases", []):
		if entry is Dictionary and int((entry as Dictionary).get("number", -1)) == phase:
			return t(str(entry.get("name_key", "")))
	return str(phase)


func _room_name(room_id: String) -> String:
	if room_id.is_empty():
		return t("NOTEBOOK_UNKNOWN_PLACE")
	var room: RoomData = Database.get_room(room_id)
	return t(room.name_key) if room != null else room_id


func _update_saved_label() -> void:
	_saved.text = t("NOTEBOOK_SAVED_COUNT", [_paper.text.length(), UITheme.tune_int(B_MAX_CHARS)])


func _on_text_changed() -> void:
	var cap: int = UITheme.tune_int(B_MAX_CHARS)
	if cap > 0 and _paper.text.length() > cap:
		_paper.text = _paper.text.substr(0, cap)
		_paper.set_caret_line(_paper.get_line_count() - 1)
		_paper.set_caret_column(_paper.get_line(_paper.get_line_count() - 1).length())
		post_status(t("NOTEBOOK_FULL"))
	save_notes()


