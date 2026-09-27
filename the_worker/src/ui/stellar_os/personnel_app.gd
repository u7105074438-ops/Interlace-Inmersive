# personnel_app.gd — PERSONNEL de StellarOS: expedientes de personal escalados por acreditación N1–N7, búsqueda, filtros, objetivos, comparación, notas y estudio (§13.4, PASO 20).
# PROPIETARIO DE: el estado de la ventana (búsqueda, filtros, orden, selección, comparación) y, mientras PlayerState no los guarde, los expedientes completos anticipados, los objetivos marcados, las notas y los estudios de la sesión.
# ESCUCHA: nada (lee los autoloads al refrescar; emite notebook_entry_added).
class_name PersonnelApp
extends OSApp

## API pública (mapa, HUD, móvil, mundo y tests):
##   effective_level(npc_id) -> int · build_file(npc_id, level) -> {npc_id, level, exact,
##     sections: {identity, routine, …}, locked: [{id, level}]} · open_full_file(npc_id, reason)
##   set_marked(npc_id, on) / is_marked / get_marked_targets · add_note / get_notes
##   predict(npc_id, action) -> float · study(npc_id, action) -> {minutes, probability, word_key}
##   list_npcs(filters) -> Array[NPCRuntime] · open(host, context) -> PersonnelApp (ventana suelta)
## Ventana: aplicación de StellarOS (extiende OSApp). Desde la carcasa, context.extra puede traer
## {file_npc_id, compare_with} (p. ej. el mapa abre el expediente de alguien); suelta (open()), el
## context es {npc_id?, compare_with?} y dibuja su propia ventana con el aspecto del equipo.
## DECISIONES:
##  · La tabla N1–N7 vive en balance expedientes.nivel_seccion. N1 = identity {name, photo, post,
##    floor, wing}. Con N3–N4 los rasgos y vínculos van CUANTIZADOS (barra aproximada); las cifras
##    exactas (rasgos, fuerza de vínculo, afecto/temor/deuda) llegan con exact_figures (N5).
##    N6 = N7 (la tabla los agrupa). El arquetipo es parte de «carácter» (N2).
##  · Acceso completo anticipado = nivel máximo para ese personaje: puesto con special_access
##    personnel_files_full (RR. HH., permanente), agravio "blackmailed" en su registro (chantaje del
##    jugador) u open_full_file(id, "hr_intrusion") (intrusión en RR. HH.). Director de IT
##    (digital_records): sección extra de comunicaciones privadas (registro de chat de SocialGraph).
##  · Objetivos marcados: NPCDirector.force_full_lod(id, "marked_target") + lista. La lista y los
##    expedientes concedidos se delegan en PlayerState si expone mark_target/unmark_target/
##    get_marked_targets/grant_full_file/has_full_file; si no, y siempre para notas y estudios,
##    viven en esta clase durante la sesión (se vacían al cambiar la semilla de partida); las
##    notas y los estudios también van al cuaderno (notebook_entry_added), que los conserva.
##  · Filtros visibles solo con la información: arquetipo (N de «character»), sobornables y
##    peligrosos y orden por rasgos (N de «traits»); deudores (te deben) y objetivos siempre.
##  · Estudio: GameClock.advance_minutes(15–30, determinista por partida, jornada, personaje y
##    acción). Predicción: soborno = Bribery.acceptance_probability con el precio justo del favor
##    expedientes.estudio_favor_soborno; confrontar/denunciar = softmax (temperatura_estudio) de
##    las utilidades de UtilityAI ante una flagrancia hipotética (NPCDirector.build_context).

const APP_ID := "personnel"
const TITLE_KEY := "PERS_APP_TITLE"
const ICON := "personnel"

const S_IDENTITY := "identity"
const S_ROUTINE := "routine"
const S_CHARACTER := "character"
const S_TRAITS := "traits"
const S_LINKS := "links"
const S_WEAKNESS := "weakness"
const S_HISTORY := "history"
const S_EXACT := "exact_figures"
const S_DISCIPLINE := "discipline"
const S_BRIBE := "bribe_price"
const S_SECRETS := "secrets"
const S_HOME := "home"
const S_POLITICS := "politics"
const S_COMMS := "private_comms"
## Secciones escaladas, en el orden de la tabla §13.4.
const FILE_SECTIONS: Array[String] = [
	S_ROUTINE, S_CHARACTER, S_TRAITS, S_LINKS, S_WEAKNESS, S_HISTORY, S_EXACT, S_DISCIPLINE,
	S_BRIBE, S_SECRETS, S_HOME, S_POLITICS,
]
const IDENTITY_FIELDS: Array[String] = ["name", "photo", "post", "floor", "wing"]

const ACCESS_FULL_FILES := "personnel_files_full"
const ACCESS_DIGITAL := "digital_records"
const REASON_HR_INTRUSION := "hr_intrusion"
const REASON_HR_POST := "hr_post"
const REASON_BLACKMAIL := "blackmail"
const LOD_REASON_TARGET := "marked_target"

const STUDY_BRIBE := "bribe"
const STUDY_CONFRONT := "confront"
const STUDY_REPORT := "report"
const STUDY_ACTIONS: Array[String] = [STUDY_BRIBE, STUDY_CONFRONT, STUDY_REPORT]
const PROB_WORD_KEYS: Array[String] = [
	"PERS_PROB_VERY_UNLIKELY", "PERS_PROB_UNLIKELY", "PERS_PROB_UNCERTAIN", "PERS_PROB_LIKELY",
	"PERS_PROB_VERY_LIKELY",
]

const CAT_BRIBABLE := "bribable"
const CAT_DANGEROUS := "dangerous"
const CAT_DEBTORS := "debtors"
const CAT_TARGETS := "targets"
const SORT_NAME := "name"
const SORT_RANK := "rank"
const SORT_FLOOR := "floor"
const ANY_FLOOR := -1000
const ANY_TIER := 0

const NOTE_CAT_PERSONNEL := "personnel"
const NOTE_CAT_TARGETS := "targets"
const NOTE_CAT_STUDY := "study"

const PS_MARK := "mark_target"
const PS_UNMARK := "unmark_target"
const PS_TARGETS := "get_marked_targets"
const PS_GRANT := "grant_full_file"
const PS_HAS_FULL := "has_full_file"

const B_SECTION_LEVELS := "expedientes.nivel_seccion"
const B_MAX_LEVEL := "expedientes.nivel_maximo"
const B_MAIN_LINKS := "expedientes.vinculos_principales"
const B_STUDY_MIN := "expedientes.estudio_minutos_min"
const B_STUDY_MAX := "expedientes.estudio_minutos_max"
const B_STUDY_FAVOUR := "expedientes.estudio_favor_soborno"
const B_STUDY_CERTAINTY := "expedientes.certeza_estudio"
const B_STUDY_TEMPERATURE := "expedientes.temperatura_estudio"
const B_PROB_THRESHOLDS := "expedientes.umbrales_probabilidad"
const B_TRAIT_HIGH := "expedientes.rasgo_alto"
const B_TRAIT_LOW := "expedientes.rasgo_bajo"
const B_MAX_PHRASES := "expedientes.frases_caracter_max"
const B_DANGER_PERCEPTION := "expedientes.peligro_perspicacia_min"
const B_BRIBABLE_GREED := "expedientes.sobornable_codicia_min"
const B_PRICE_FAVOURS := "expedientes.favores_precio"
const B_AFFECTION_BAND := "expedientes.afecto_umbral"
const B_FEAR_BAND := "expedientes.temor_umbral"
const B_MAX_COMMS := "expedientes.max_comunicaciones"
const B_MAX_DISCIPLINE := "expedientes.max_disciplinario"
const B_DENOUNCE_COURAGE := "sobornos.umbral_denuncia_valentia"
const B_DENOUNCE_LOYALTY := "sobornos.umbral_denuncia_lealtad"
const B_FACTORY_FLOOR := "mundo.planta_fabrica"
const B_EXTERIOR_FLOOR := "mundo.planta_exterior"
const B_TRAIT_BUCKETS := "expedientes.tramos_valor_aproximado"
## Contenido: claves PERS_STREET_1..8 y números de portal del domicilio inventado.
const STREET_KEYS := 8
const HOUSE_NUMBER_MAX := 120

static var _store_seed: int = -1
static var _full_files: Dictionary = {}
static var _targets: Array[String] = []
static var _notes: Dictionary = {}
static var _studies: Dictionary = {}

var _standalone: bool = false
var _in_ui_root: bool = false
var _embedded: bool = false
var _filters: Dictionary = {
	"query": "", "floor": ANY_FLOOR, "tier": ANY_TIER, "archetype": "", "category": "",
	"sort": SORT_NAME,
}
var _selected: String = ""
var _compare_with: String = ""
var _picking_compare: bool = false
var _last_study: Dictionary = {}
var _window: OsWindow
var _search: LineEdit
var _floor_opt: OptionButton
var _tier_opt: OptionButton
var _arch_opt: OptionButton
var _cat_opt: OptionButton
var _sort_opt: OptionButton
var _count_label: Label
var _list_box: VBoxContainer
var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer
var _note_edit: LineEdit
var _mark_btn: Button
var _compare_btn: Button
var _built: bool = false


# ═══ Almacén de sesión (delegable en PlayerState) ══════════════════════

## Vacía el almacén de sesión (tests y partida nueva).
static func reset_session() -> void:
	_store_seed = GameClock.get_run_seed()
	_full_files.clear()
	_targets.clear()
	_notes.clear()
	_studies.clear()


static func _sync_store() -> void:
	if _store_seed != GameClock.get_run_seed():
		reset_session()


## Vías de acceso anticipado (§13.4): intrusión en RR. HH., chantaje… El expediente queda completo.
static func open_full_file(npc_id: String, reason: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return false
	_sync_store()
	if PlayerState.has_method(PS_GRANT):
		PlayerState.call(PS_GRANT, npc_id, reason)
	else:
		_full_files[npc_id] = reason
	EventBus.notebook_entry_added.emit(NOTE_CAT_PERSONNEL, "PERS_NOTE_FULL_FILE",
			[npc.name, UITheme.trf("PERS_REASON_" + reason.to_upper())])
	return true


## Motivo del acceso completo a ese expediente ("" si no lo hay).
static func full_file_reason(npc_id: String) -> String:
	_sync_store()
	if player_has_access(ACCESS_FULL_FILES):
		return REASON_HR_POST
	if PlayerState.has_method(PS_HAS_FULL) and bool(PlayerState.call(PS_HAS_FULL, npc_id)):
		return REASON_HR_INTRUSION
	if _full_files.has(npc_id):
		return str(_full_files[npc_id])
	for grievance: Variant in NPCDirector.get_ledger(npc_id).get("grievances", []):
		if grievance is Dictionary \
				and str(grievance.get("type", "")) == NPCDirectorSystem.GRIEVANCE_BLACKMAILED:
			return REASON_BLACKMAIL
	return ""


static func get_marked_targets() -> Array[String]:
	_sync_store()
	var out: Array[String] = []
	if PlayerState.has_method(PS_TARGETS):
		out.assign(PlayerState.call(PS_TARGETS))
	else:
		out.assign(_targets)
	return out


static func is_marked(npc_id: String) -> bool:
	return get_marked_targets().has(npc_id)


## Marca o desmarca un objetivo (§13.4): LOD completo, lista para mapa/HUD y nota en el cuaderno.
static func set_marked(npc_id: String, marked: bool) -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or marked == is_marked(npc_id):
		return
	if marked:
		if PlayerState.has_method(PS_MARK):
			PlayerState.call(PS_MARK, npc_id)
		else:
			_targets.append(npc_id)
		NPCDirector.force_full_lod(npc_id, LOD_REASON_TARGET)
	else:
		if PlayerState.has_method(PS_UNMARK):
			PlayerState.call(PS_UNMARK, npc_id)
		else:
			_targets.erase(npc_id)
		NPCDirector.release_full_lod(npc_id, LOD_REASON_TARGET)
	var key: String = "PERS_NOTE_TARGET_MARKED" if marked else "PERS_NOTE_TARGET_CLEARED"
	EventBus.notebook_entry_added.emit(NOTE_CAT_TARGETS, key, [npc.name])


## Nota del jugador vinculada al cuaderno. false si el texto está vacío.
static func add_note(npc_id: String, text: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var clean: String = text.strip_edges()
	if npc == null or clean.is_empty():
		return false
	_sync_store()
	if not _notes.has(npc_id):
		_notes[npc_id] = []
	(_notes[npc_id] as Array).append({"day": GameClock.get_day(),
			"time": GameClock.get_time_string(), "text": clean})
	EventBus.notebook_entry_added.emit(NOTE_CAT_PERSONNEL, "PERS_NOTE_ENTRY", [npc.name, clean])
	return true


static func get_notes(npc_id: String) -> Array[Dictionary]:
	_sync_store()
	var out: Array[Dictionary] = []
	out.assign(_notes.get(npc_id, []))
	return out


## Estudios hechos sobre el personaje: {acción: resultado de study()}.
static func get_studies(npc_id: String) -> Dictionary:
	_sync_store()
	return (_studies.get(npc_id, {}) as Dictionary).duplicate(true)


# ═══ Niveles y expediente (§13.4) ═════════════════════════════════════

static func max_level() -> int:
	return maxi(Database.get_balance_int(B_MAX_LEVEL), 1)


static func section_level(section: String) -> int:
	var table: Variant = Database.get_balance(B_SECTION_LEVELS)
	if table is Dictionary and (table as Dictionary).has(section):
		return int(table[section])
	return max_level()


## Nivel de expediente del puesto del jugador (N1–N7).
static func player_level() -> int:
	return clampi(PlayerState.get_personnel_file_level(), 1, max_level())


static func player_has_access(tag: String) -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation != null and occupation.special_access.has(tag)


static func effective_level(npc_id: String) -> int:
	return max_level() if not full_file_reason(npc_id).is_empty() else player_level()


static func can_see(npc_id: String, section: String) -> bool:
	return effective_level(npc_id) >= section_level(section)


## Expediente visible a ese nivel. {} si el personaje no existe.
static func build_file(npc_id: String, level: int) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return {}
	var lvl: int = clampi(level, 1, max_level())
	var exact: bool = lvl >= section_level(S_EXACT)
	var sections: Dictionary = {S_IDENTITY: identity_of(npc)}
	var locked: Array[Dictionary] = []
	for section: String in FILE_SECTIONS:
		var need: int = section_level(section)
		if lvl >= need:
			sections[section] = _section_data(npc, section, exact)
		else:
			locked.append({"id": section, "level": need})
	if player_has_access(ACCESS_DIGITAL):
		sections[S_COMMS] = comms_of(npc)
	return {"npc_id": npc_id, "level": lvl, "exact": exact, "sections": sections,
			"locked": locked, "full_reason": full_file_reason(npc_id)}


static func _section_data(npc: NPCRuntime, section: String, exact: bool) -> Variant:
	match section:
		S_ROUTINE:
			return routine_of(npc)
		S_CHARACTER:
			return character_of(npc)
		S_TRAITS:
			return traits_of(npc, exact)
		S_LINKS:
			return links_of(npc, exact)
		S_WEAKNESS:
			return weakness_of(npc)
		S_HISTORY:
			return history_of(npc, exact)
		S_DISCIPLINE:
			return discipline_of(npc)
		S_BRIBE:
			return bribe_of(npc)
		S_SECRETS:
			return secrets_of(npc)
		S_HOME:
			return home_of(npc)
		S_POLITICS:
			return politics_of(npc)
	return true


## N1: nombre, fotografía, puesto, planta y ala (el organigrama público).
static func identity_of(npc: NPCRuntime) -> Dictionary:
	var room: RoomData = Database.get_room(npc.home_room)
	var floor_number: int = npc.floor
	if room != null and room.floor != RoomData.TRANSVERSAL_FLOOR:
		floor_number = room.floor
	return {
		"name": npc.name, "photo": CharacterPainter.appearance_for_npc(npc),
		"post": post_text(npc), "floor": floor_text(floor_number),
		"wing": UITheme.trf(room.name_key) if room != null else UITheme.trf("PERS_WING_NONE"),
	}


static func post_text(npc: NPCRuntime) -> String:
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	if occupation != null:
		return UITheme.trf("PERS_POST_FMT", [UITheme.trf(occupation.name_key), occupation.rank])
	var role: Dictionary = Database.get_role(NPCDirector.get_role(npc.id))
	if not role.is_empty():
		return UITheme.trf(str(role.get("name_key", "")))
	return UITheme.trf("PERS_POST_UNKNOWN")


static func npc_rank(npc: NPCRuntime) -> int:
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	return occupation.rank if occupation != null else -1


static func npc_floor(npc: NPCRuntime) -> int:
	var room: RoomData = Database.get_room(npc.home_room)
	if room != null and room.floor != RoomData.TRANSVERSAL_FLOOR:
		return room.floor
	return npc.floor


static func floor_text(floor_number: int) -> String:
	if floor_number == Database.get_balance_int(B_FACTORY_FLOOR):
		return UITheme.trf("PERS_FLOOR_FACTORY")
	if floor_number == Database.get_balance_int(B_EXTERIOR_FLOOR):
		return UITheme.trf("PERS_FLOOR_OUTSIDE")
	if floor_number == 0:
		return UITheme.trf("PERS_FLOOR_GROUND")
	if floor_number < 0:
		return UITheme.trf("PERS_FLOOR_BASEMENT", [-floor_number])
	return UITheme.trf("PERS_FLOOR_N", [floor_number])


static func room_name(room_id: String) -> String:
	if room_id.is_empty():
		return UITheme.trf("PERS_ROUTINE_AWAY")
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		room = Database.get_room(DatabaseSystem.get_room_base_id(room_id))
	return UITheme.trf(room.name_key) if room != null else room_id


## N2: sala principal de cada franja de hoy.
static func routine_of(npc: NPCRuntime) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for band: String in GameClock.get_band_order():
		out.append({"band": band, "band_name": UITheme.trf(GameClock.get_band_name_key(band)),
				"place": room_name(NPCDirector.get_scheduled_location(npc.id, band))})
	return out


## N2: tipo (arquetipo) y descripción en lenguaje natural a partir de los rasgos.
static func character_of(npc: NPCRuntime) -> Dictionary:
	var archetype: ArchetypeData = Database.get_archetype(npc.archetype)
	var arch_name: String = UITheme.trf(archetype.name_key) if archetype != null else ""
	return {"archetype": npc.archetype, "archetype_name": arch_name,
			"lines": describe_traits(npc.traits)}


## Frases cortas por los rasgos más marcados («Habla mucho. Se fija en todo.»).
static func describe_traits(traits: Dictionary) -> Array[String]:
	var high: int = Database.get_balance_int(B_TRAIT_HIGH)
	var low: int = Database.get_balance_int(B_TRAIT_LOW)
	var ranked: Array[Array] = []
	for trait_name: String in Validate.TRAIT_NAMES:
		var value: int = int(traits.get(trait_name, 0))
		if value >= high:
			ranked.append([trait_name, "HIGH", value - high])
		elif value <= low:
			ranked.append([trait_name, "LOW", low - value])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	var out: Array[String] = []
	for entry: Array in ranked.slice(0, Database.get_balance_int(B_MAX_PHRASES)):
		out.append(UITheme.trf("PERS_DESC_%s_%s" % [str(entry[0]).to_upper(), entry[1]]))
	if out.is_empty():
		out.append(UITheme.trf("PERS_DESC_AVERAGE"))
	return out


## Valor mostrado: exacto con N5; si no, el centro de su tramo (barra aproximada).
static func shown_value(value: int, exact: bool) -> int:
	if exact:
		return value
	var buckets: int = maxi(Database.get_balance_int(B_TRAIT_BUCKETS), 1)
	var width: float = float(Validate.TRAIT_MAX) / buckets
	var bucket: int = clampi(floori(float(value) / width), 0, buckets - 1)
	return roundi(width * (bucket + 0.5))


## N3: los seis rasgos (barras). Palabra cualitativa siempre; cifra exacta solo con N5.
static func traits_of(npc: NPCRuntime, exact: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for trait_name: String in Validate.TRAIT_NAMES:
		var value: int = npc.get_trait(trait_name)
		out.append({"trait": trait_name, "name": UITheme.trf("PERS_TRAIT_" + trait_name.to_upper()),
				"value": shown_value(value, exact), "word": _level_word(value), "exact": exact})
	return out


static func _level_word(value: int) -> String:
	if value >= Database.get_balance_int(B_TRAIT_HIGH):
		return UITheme.trf("PERS_WORD_HIGH")
	if value <= Database.get_balance_int(B_TRAIT_LOW):
		return UITheme.trf("PERS_WORD_LOW")
	return UITheme.trf("PERS_WORD_MID")


## Nombre visible de otro extremo de un vínculo (personaje, jugador o id).
static func other_name(other_id: String) -> String:
	if other_id == PLAYER_ID:
		return UITheme.trf("PERS_YOU")
	var other: NPCRuntime = NPCDirector.get_npc(other_id)
	return other.name if other != null else other_id


static func _link_row(link: Dictionary, npc_id: String, exact: bool) -> Dictionary:
	var other: String = str(link.get("to", "")) if str(link.get("from", "")) == npc_id \
			else str(link.get("from", ""))
	var strength: float = float(link.get("strength", 0.0))
	var shown: float = strength if exact \
			else float(shown_value(roundi(strength * Validate.TRAIT_MAX), false)) / Validate.TRAIT_MAX
	var type_id: String = str(link.get("type", ""))
	return {"other_id": other, "name": other_name(other), "type": type_id,
			"type_name": UITheme.trf("LINK_" + type_id.to_upper()), "strength": shown,
			"outgoing": str(link.get("from", "")) == npc_id, "secret": bool(link.get("secret", false)),
			"directed": bool(link.get("directed", false)), "exact": exact}


static func _sorted_links(npc: NPCRuntime) -> Array[Dictionary]:
	var links: Array[Dictionary] = SocialGraph.get_links(npc.id)
	links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("strength", 0.0)) > float(b.get("strength", 0.0)))
	return links


## N3: vínculos principales (los más fuertes, sin los secretos).
static func links_of(npc: NPCRuntime, exact: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link: Dictionary in _sorted_links(npc):
		if bool(link.get("secret", false)):
			continue
		out.append(_link_row(link, npc.id, exact))
		if out.size() >= Database.get_balance_int(B_MAIN_LINKS):
			break
	return out


## N4: debilidad explotable (la del nominado o la de su arquetipo).
static func weakness_of(npc: NPCRuntime) -> String:
	if not npc.weakness_key.is_empty():
		return UITheme.trf(npc.weakness_key)
	return UITheme.trf("PERS_WEAK_ARCH_" + npc.archetype.to_upper())


## N4: historial con el jugador (agravios y favores); cifras de afecto/temor/deuda con N5.
static func history_of(npc: NPCRuntime, exact: bool) -> Dictionary:
	var ledger: Dictionary = NPCDirector.get_ledger(npc.id)
	var entries: Array[Dictionary] = []
	for g: Variant in ledger.get("grievances", []):
		if g is Dictionary:
			entries.append(_ledger_entry(g, true, exact))
	for f: Variant in ledger.get("favours", []):
		if f is Dictionary:
			entries.append(_ledger_entry(f, false, exact))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) > int(b["day"]))
	var out: Dictionary = {"entries": entries,
			"mood_word": _affection_word(int(ledger.get("affection", 0))),
			"fear_word": _fear_word(int(ledger.get("fear", 0))),
			"debt_word": _debt_word(int(ledger.get("debt", 0)))}
	if exact:
		for key: String in ["affection", "fear", "debt"]:
			out[key] = int(ledger.get(key, 0))
	return out


static func _ledger_entry(raw: Dictionary, grievance: bool, exact: bool) -> Dictionary:
	var type_id: String = str(raw.get("type", ""))
	var key: String = NPCDirectorSystem.grievance_name_key(type_id) if grievance \
			else NPCDirectorSystem.favour_name_key(type_id)
	var text: String = UITheme.trf(key)
	if text == key:
		text = UITheme.trf("PERS_HISTORY_GRIEVANCE" if grievance else "PERS_HISTORY_FAVOUR")
	var entry: Dictionary = {"grievance": grievance, "text": text, "day": int(raw.get("day", 0))}
	if exact:
		entry["amount"] = int(raw.get("severity" if grievance else "magnitude", 0))
	return entry


static func _affection_word(value: int) -> String:
	var band: int = Database.get_balance_int(B_AFFECTION_BAND)
	if value > band:
		return UITheme.trf("PERS_MOOD_WARM")
	if value < -band:
		return UITheme.trf("PERS_MOOD_COLD")
	return UITheme.trf("PERS_MOOD_NEUTRAL")


static func _fear_word(value: int) -> String:
	return UITheme.trf("PERS_FEAR_HIGH" if value >= Database.get_balance_int(B_FEAR_BAND) \
			else "PERS_FEAR_LOW")


static func _debt_word(value: int) -> String:
	if value > 0:
		return UITheme.trf("PERS_DEBT_OWES_YOU")
	if value < 0:
		return UITheme.trf("PERS_DEBT_YOU_OWE")
	return UITheme.trf("PERS_DEBT_NONE")


## N5: expediente disciplinario (casos de Seguridad, anotaciones y escaqueo).
static func discipline_of(npc: NPCRuntime) -> Array[String]:
	var out: Array[String] = []
	for case: Investigation in Security.get_all_investigations():
		var incident: String = UITheme.trf("INCIDENT_" + case.incident_type.to_upper())
		if case.culprit == npc.id:
			out.append(UITheme.trf("PERS_DISC_CONVICTED", [incident, case.opened_day]))
		elif case.suspects.has(npc.id):
			out.append(UITheme.trf("PERS_DISC_SUSPECT", [incident, case.opened_day]))
	for record: Belief in BeliefNet.get_records_about(npc.id):
		out.append(UITheme.trf("PERS_DISC_RECORD", [record.timestamp]))
	if npc.is_slacker:
		out.append(UITheme.trf("PERS_DISC_ABSENCES"))
	if out.is_empty():
		out.append(UITheme.trf("PERS_DISC_CLEAN"))
	return out.slice(0, Database.get_balance_int(B_MAX_DISCIPLINE))


## N5: precio estimado de soborno (Bribery.estimated_price) de los favores habituales.
static func bribe_of(npc: NPCRuntime) -> Dictionary:
	var prices: Array[Dictionary] = []
	var favours: Variant = Database.get_balance(B_PRICE_FAVOURS)
	for favour: Variant in (favours if favours is Array else []):
		var data: Dictionary = Database.get_bribe_favour(str(favour))
		if data.is_empty():
			continue
		prices.append({"favour": str(favour), "name": UITheme.trf(str(data.get("name_key", ""))),
				"price": Bribery.estimated_price(npc, str(favour))})
	return {"unbribable": Bribery.is_npc_unbribable(npc), "prices": prices}


## N6–N7: secretos personales (perfil del nominado y relaciones clandestinas).
static func secrets_of(npc: NPCRuntime) -> Array[String]:
	var out: Array[String] = []
	for key: Variant in NPCDirector.get_profile(npc.id).get("secrets", []):
		out.append(UITheme.trf(str(key)))
	for link: Dictionary in SocialGraph.get_links(npc.id):
		if bool(link.get("secret", false)):
			var row: Dictionary = _link_row(link, npc.id, true)
			out.append(UITheme.trf("PERS_SECRET_AFFAIR", [row["name"]]))
	if out.is_empty():
		out.append(UITheme.trf("PERS_SECRET_NONE"))
	return out


## N6–N7: domicilio (habilita las operaciones nocturnas). Calle y número deterministas.
static func home_of(npc: NPCRuntime) -> Dictionary:
	var house: RoomData = Database.get_room(npc.home_address)
	var seed_value: int = absi(hash(npc.id))
	var street: String = UITheme.trf("PERS_STREET_%d" % (seed_value % STREET_KEYS + 1))
	return {"room_id": npc.home_address,
			"address": UITheme.trf("PERS_ADDRESS_FMT", [seed_value % HOUSE_NUMBER_MAX + 1, street]),
			"kind": UITheme.trf(house.name_key) if house != null else ""}


## N6–N7: el mapa completo de su política interna (todos sus vínculos, secretos incluidos).
static func politics_of(npc: NPCRuntime) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link: Dictionary in _sorted_links(npc):
		out.append(_link_row(link, npc.id, true))
	return out


## Director de IT (digital_records): registro de chat legible donde aparece el personaje.
static func comms_of(npc: NPCRuntime) -> Array[String]:
	var out: Array[String] = []
	var chat_log: Array[Dictionary] = SocialGraph.get_chat_log()
	chat_log.reverse()
	for entry: Dictionary in chat_log:
		var from: String = str(entry.get("from", ""))
		var to: String = str(entry.get("to", ""))
		if from != npc.id and to != npc.id:
			continue
		out.append(UITheme.trf("PERS_COMMS_LINE", [int(entry.get("day", 0)),
				int(entry.get("hour", 0)), other_name(from), other_name(to),
				other_name(str(entry.get("subject", "")))]))
		if out.size() >= Database.get_balance_int(B_MAX_COMMS):
			break
	if out.is_empty():
		out.append(UITheme.trf("PERS_COMMS_NONE"))
	return out


# ═══ Búsqueda, filtros y orden ════════════════════════════════════════

static func list_npcs(filters: Dictionary) -> Array[NPCRuntime]:
	var out: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if matches(npc, filters):
			out.append(npc)
	sort_npcs(out, str(filters.get("sort", SORT_NAME)))
	return out


static func matches(npc: NPCRuntime, filters: Dictionary) -> bool:
	var query: String = str(filters.get("query", "")).strip_edges().to_lower()
	if not query.is_empty() and not npc.name.to_lower().contains(query):
		return false
	var floor_filter: int = int(filters.get("floor", ANY_FLOOR))
	if floor_filter != ANY_FLOOR and npc_floor(npc) != floor_filter:
		return false
	var tier_filter: int = int(filters.get("tier", ANY_TIER))
	if tier_filter != ANY_TIER and npc.tier != tier_filter:
		return false
	var archetype: String = str(filters.get("archetype", ""))
	if not archetype.is_empty() \
			and (npc.archetype != archetype or not can_see(npc.id, S_CHARACTER)):
		return false
	return matches_category(npc, str(filters.get("category", "")))


static func matches_category(npc: NPCRuntime, category: String) -> bool:
	match category:
		CAT_BRIBABLE:
			return can_see(npc.id, S_TRAITS) and not Bribery.is_npc_unbribable(npc) \
					and npc.get_trait("greed") >= Database.get_balance_int(B_BRIBABLE_GREED)
		CAT_DANGEROUS:
			return can_see(npc.id, S_TRAITS) and is_dangerous(npc)
		CAT_DEBTORS:
			return NPCDirector.get_debt(npc.id) > 0
		CAT_TARGETS:
			return is_marked(npc.id)
	return true


## Peligroso: perspicaz o de los que denuncian un soborno (umbrales de §8.2).
static func is_dangerous(npc: NPCRuntime) -> bool:
	return npc.get_trait("perception") >= Database.get_balance_int(B_DANGER_PERCEPTION) \
			or npc.get_trait("courage") > Database.get_balance_int(B_DENOUNCE_COURAGE) \
			or npc.get_trait("loyalty") > Database.get_balance_int(B_DENOUNCE_LOYALTY)


## Orden por nombre, rango, planta o un rasgo (los expedientes sin rasgos visibles, al final).
static func sort_npcs(list: Array[NPCRuntime], key: String) -> void:
	if Validate.TRAIT_NAMES.has(key):
		list.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool:
			return _trait_sort_value(a, key) > _trait_sort_value(b, key) \
					or (_trait_sort_value(a, key) == _trait_sort_value(b, key) and a.name < b.name))
	elif key == SORT_RANK:
		list.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool:
			return npc_rank(a) > npc_rank(b) or (npc_rank(a) == npc_rank(b) and a.name < b.name))
	elif key == SORT_FLOOR:
		list.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool:
			return npc_floor(a) < npc_floor(b) or (npc_floor(a) == npc_floor(b) and a.name < b.name))
	else:
		list.sort_custom(func(a: NPCRuntime, b: NPCRuntime) -> bool: return a.name < b.name)


static func _trait_sort_value(npc: NPCRuntime, trait_name: String) -> int:
	var level: int = effective_level(npc.id)
	if level < section_level(S_TRAITS):
		return -1
	return shown_value(npc.get_trait(trait_name), level >= section_level(S_EXACT))


# ═══ Estudio (§13.4) ══════════════════════════════════════════════════

## Minutos de juego que cuesta estudiar (determinista por partida, jornada, personaje y acción).
static func study_minutes(npc_id: String, action: String) -> int:
	var low: int = Database.get_balance_int(B_STUDY_MIN)
	var high: int = maxi(Database.get_balance_int(B_STUDY_MAX), low)
	var roll: int = absi(hash([GameClock.get_run_seed(), GameClock.get_day(), npc_id, action]))
	return low + roll % (high - low + 1)


## Probabilidad (0–1) de que el personaje acepte un soborno justo, te confronte o te denuncie.
static func predict(npc_id: String, action: String) -> float:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return 0.0
	match action:
		STUDY_BRIBE:
			var favour: String = str(Database.get_balance(B_STUDY_FAVOUR))
			return Bribery.acceptance_probability(npc, Bribery.fair_price(npc, favour), favour)
		STUDY_CONFRONT:
			return _reaction_share(npc, [UtilityAI.CONFRONT_PLAYER])
		STUDY_REPORT:
			return _reaction_share(npc, UtilityAI.REPORT_ACTIONS)
	return 0.0


## Softmax de las utilidades de reacción ante una flagrancia hipotética; suma de `actions`.
static func _reaction_share(npc: NPCRuntime, actions: Array[String]) -> float:
	var ctx: Dictionary = NPCDirector.build_context(npc.id, NPCDirectorSystem.TRIGGER_BELIEF,
			{"certainty": Database.get_balance_float(B_STUDY_CERTAINTY)})
	var scores: Dictionary = UtilityAI.evaluate(npc, ctx).get("scores", {})
	var temperature: float = maxf(Database.get_balance_float(B_STUDY_TEMPERATURE), 0.01)
	var top: float = -INF
	for value: Variant in scores.values():
		top = maxf(top, float(value))
	var total: float = 0.0
	var wanted: float = 0.0
	for action: Variant in scores:
		var weight: float = exp((float(scores[action]) - top) / temperature)
		total += weight
		if actions.has(str(action)):
			wanted += weight
	return wanted / total if total > 0.0 else 0.0


## Clave de la palabra difusa de una probabilidad («probable», «improbable»…).
static func probability_word_key(probability: float) -> String:
	var thresholds: Variant = Database.get_balance(B_PROB_THRESHOLDS)
	var index: int = 0
	for threshold: Variant in (thresholds if thresholds is Array else []):
		if probability >= float(threshold):
			index += 1
	return PROB_WORD_KEYS[clampi(index, 0, PROB_WORD_KEYS.size() - 1)]


## Estudia al personaje: consume tiempo de juego y devuelve la predicción en palabra difusa.
static func study(npc_id: String, action: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not STUDY_ACTIONS.has(action):
		return {}
	var minutes: int = study_minutes(npc_id, action)
	GameClock.advance_minutes(float(minutes))
	var probability: float = predict(npc_id, action)
	var result: Dictionary = {"npc_id": npc_id, "action": action, "minutes": minutes,
			"probability": probability, "word_key": probability_word_key(probability),
			"day": GameClock.get_day(), "time": GameClock.get_time_string()}
	_sync_store()
	if not _studies.has(npc_id):
		_studies[npc_id] = {}
	_studies[npc_id][action] = result
	EventBus.notebook_entry_added.emit(NOTE_CAT_STUDY, "PERS_NOTE_STUDY",
			[npc.name, UITheme.trf("PERS_STUDY_Q_" + action.to_upper()),
			UITheme.trf(str(result["word_key"]))])
	return result


# ═══ Ventana ══════════════════════════════════════════════════════════

## Abre la aplicación suelta (sin la carcasa StellarOS): en UIRoot como ventana modal; si no, como
## hija de `host` con su propio escritorio.
static func open(host: Node, context: Dictionary = {}) -> PersonnelApp:
	var app: PersonnelApp = PersonnelApp.new()
	app.set_standalone(true)
	app.setup(context)
	if host is UIRoot:
		app._in_ui_root = true
		(host as UIRoot).open_modal(app, false)
	elif host != null:
		host.add_child(app)
	return app


static func is_available() -> bool:
	return true


func get_title_key() -> String:
	return TITLE_KEY


func set_standalone(on: bool) -> void:
	_standalone = on


## La carcasa StellarOS aporta su propio marco: sin barra de título ni escritorio.
func set_embedded(on: bool) -> void:
	_embedded = on


func request_close() -> void:
	close_requested.emit()
	if _standalone and not _in_ui_root:
		queue_free()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	if not _built:
		setup(context)
	_refresh_status.call_deferred()


func _draw() -> void:
	if _standalone and not _embedded:
		OsKit.draw_desktop(self, Rect2(Vector2.ZERO, size))


## OSApp: construye la interfaz con la paleta y el tamaño base de la carcasa (o del equipo propio).
func build() -> void:
	OsKit.use(pal, int(context.get("base", 0)))
	theme = OsKit.build_theme()
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", OsKit.px(0.6))
	_frame().add_child(split)
	split.add_child(_build_sidebar())
	split.add_child(_build_detail())
	_built = true
	_refresh_filters()
	_refresh_list()
	_apply_context()


## OSApp: la carcasa la llama al traer la ventana al frente.
func refresh() -> void:
	if not _built:
		return
	_refresh_filters()
	_refresh_list()
	if is_comparing():
		compare(_selected, _compare_with)
	elif not _selected.is_empty():
		_render_file()


## Contenedor del contenido: la ventana propia (suelta) o un margen dentro de la de la carcasa.
func _frame() -> Control:
	if _standalone and not _embedded:
		_window = OsKit.make_window(self, tr(TITLE_KEY), ICON)
		_window.close_pressed.connect(request_close)
		return _window.body
	return OsKit.make_holder(self)


func _set_status(parts: Array) -> void:
	OsKit.show_status(self, _window, parts)


func _apply_context() -> void:
	var wanted: String = OsKit.requested(context, "npc_id", "file_npc_id")
	if wanted.is_empty() and _selected.is_empty():
		var list: Array[NPCRuntime] = list_npcs(_filters)
		wanted = list[0].id if not list.is_empty() else ""
	if not wanted.is_empty():
		select(wanted)
	var other: String = OsKit.requested(context, "compare_with", "compare_with")
	if not other.is_empty():
		compare(_selected, other)


func _build_sidebar() -> Control:
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size.x = OsKit.px(OsKit.SIDEBAR_EM)
	side.add_theme_constant_override("separation", OsKit.px(0.35))
	_search = LineEdit.new()
	_search.placeholder_text = tr("PERS_SEARCH_HINT")
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	side.add_child(_search)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", OsKit.px(0.4))
	grid.add_theme_constant_override("v_separation", OsKit.px(0.25))
	_floor_opt = _filter_row(grid, "PERS_FILTER_FLOOR")
	_tier_opt = _filter_row(grid, "PERS_FILTER_RANK")
	_arch_opt = _filter_row(grid, "PERS_FILTER_TYPE")
	_cat_opt = _filter_row(grid, "PERS_FILTER_CATEGORY")
	_sort_opt = _filter_row(grid, "PERS_FILTER_SORT")
	side.add_child(grid)
	_count_label = OsKit.label("", OsKit.V_SMALL)
	side.add_child(_count_label)
	side.add_child(_build_list())
	return side


func _filter_row(grid: GridContainer, key: String) -> OptionButton:
	grid.add_child(OsKit.label(tr(key), OsKit.V_SMALL))
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	option.item_selected.connect(_on_filter_changed.unbind(1))
	grid.add_child(option)
	return option


func _build_list() -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = OsKit.V_FIELD
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 0)
	scroll.add_child(_list_box)
	return frame


func _build_detail() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", OsKit.px(0.35))
	col.add_child(_build_toolbar())
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = OsKit.V_PAPER
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(frame)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", OsKit.px(0.7))
	_detail_scroll.add_child(_detail_box)
	return col


## Barra de acciones (fluida: en pantallas estrechas los botones pasan a otra línea).
func _build_toolbar() -> Control:
	var bar: HFlowContainer = HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", OsKit.px(0.35))
	bar.add_theme_constant_override("v_separation", OsKit.px(0.25))
	_mark_btn = OsKit.button(tr("PERS_ACT_MARK"), "target")
	_mark_btn.toggle_mode = true
	_mark_btn.toggled.connect(_on_mark_toggled)
	bar.add_child(_mark_btn)
	_compare_btn = OsKit.button(tr("PERS_ACT_COMPARE"), "eye")
	_compare_btn.toggle_mode = true
	_compare_btn.toggled.connect(_on_compare_toggled)
	bar.add_child(_compare_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var study: Label = OsKit.label(tr("PERS_STUDY_LABEL"), OsKit.V_HEADING)
	study.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(study)
	for action: String in STUDY_ACTIONS:
		var btn: Button = OsKit.button(tr("PERS_STUDY_BTN_" + action.to_upper()), "clock")
		btn.tooltip_text = tr("PERS_STUDY_TIP")
		btn.pressed.connect(_on_study_pressed.bind(action))
		bar.add_child(btn)
	return bar


# ─── Filtros ──────────────────────────────────────────────────────────

func _refresh_filters() -> void:
	_fill_option(_floor_opt, _floor_items(), _filters["floor"])
	_fill_option(_tier_opt, _tier_items(), _filters["tier"])
	var level: int = player_level()
	_arch_opt.disabled = level < section_level(S_CHARACTER)
	_fill_option(_arch_opt, _archetype_items(level), _filters["archetype"])
	_fill_option(_cat_opt, _category_items(level), _filters["category"])
	_fill_option(_sort_opt, _sort_items(level), _filters["sort"])


func _fill_option(option: OptionButton, items: Array[Array], current: Variant) -> void:
	option.clear()
	for item: Array in items:
		option.add_item(str(item[0]))
		option.set_item_metadata(option.item_count - 1, item[1])
		if typeof(item[1]) == typeof(current) and item[1] == current:
			option.select(option.item_count - 1)


func _floor_items() -> Array[Array]:
	var floors: Array[int] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not floors.has(npc_floor(npc)):
			floors.append(npc_floor(npc))
	floors.sort()
	var out: Array[Array] = [[tr("PERS_ALL"), ANY_FLOOR]]
	for f: int in floors:
		out.append([floor_text(f), f])
	return out


func _tier_items() -> Array[Array]:
	var out: Array[Array] = [[tr("PERS_ALL"), ANY_TIER]]
	for tier: int in range(OccupationData.MIN_TIER, OccupationData.MAX_TIER + 1):
		out.append([tr("PORTAL_TIER_%d" % tier), tier])
	return out


func _archetype_items(level: int) -> Array[Array]:
	var out: Array[Array] = [[tr("PERS_ALL") if level >= section_level(S_CHARACTER)
			else tr("PERS_CLASSIFIED"), ""]]
	if level < section_level(S_CHARACTER):
		return out
	for arch: ArchetypeData in Database.get_all_archetypes():
		out.append([tr(arch.name_key), arch.id])
	return out


func _category_items(level: int) -> Array[Array]:
	var out: Array[Array] = [[tr("PERS_ALL"), ""]]
	if level >= section_level(S_TRAITS):
		out.append([tr("PERS_CAT_BRIBABLE"), CAT_BRIBABLE])
		out.append([tr("PERS_CAT_DANGEROUS"), CAT_DANGEROUS])
	out.append([tr("PERS_CAT_DEBTORS"), CAT_DEBTORS])
	out.append([tr("PERS_CAT_TARGETS"), CAT_TARGETS])
	return out


func _sort_items(level: int) -> Array[Array]:
	var out: Array[Array] = [[tr("PERS_SORT_NAME"), SORT_NAME], [tr("PERS_SORT_RANK"), SORT_RANK],
			[tr("PERS_SORT_FLOOR"), SORT_FLOOR]]
	if level >= section_level(S_TRAITS):
		for trait_name: String in Validate.TRAIT_NAMES:
			out.append([tr("PERS_TRAIT_" + trait_name.to_upper()), trait_name])
	return out


func _on_search_changed(text: String) -> void:
	_filters["query"] = text
	_refresh_list()


func _on_filter_changed() -> void:
	for pair: Array in [[_floor_opt, "floor"], [_tier_opt, "tier"], [_arch_opt, "archetype"],
			[_cat_opt, "category"], [_sort_opt, "sort"]]:
		var option: OptionButton = pair[0]
		if option.selected >= 0:
			_filters[pair[1]] = option.get_item_metadata(option.selected)
	_refresh_list()


## Filtros de la ventana (tests y depuración): mismas claves que list_npcs().
func set_filters(values: Dictionary) -> void:
	_filters.merge(values, true)
	if _built:
		_refresh_filters()
		_refresh_list()


func get_visible_npc_ids() -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in list_npcs(_filters):
		out.append(npc.id)
	return out


# ─── Lista ────────────────────────────────────────────────────────────

func _refresh_list() -> void:
	for child: Node in _list_box.get_children():
		child.queue_free()
	var list: Array[NPCRuntime] = list_npcs(_filters)
	var targets: Array[String] = get_marked_targets()
	for i: int in list.size():
		_list_box.add_child(_make_row(list[i], i, targets))
	_count_label.text = tr("PERS_COUNT_FMT") % [list.size(), NPCDirector.get_all_npcs().size()]
	_refresh_status()


func _make_row(npc: NPCRuntime, index: int, targets: Array[String]) -> NpcRow:
	var row: NpcRow = NpcRow.new()
	row.npc_id = npc.id
	row.title = npc.name
	row.subtitle = post_text(npc)
	var rank: int = npc_rank(npc)
	row.chip = tr("PERS_RANK_CHIP") % rank if rank >= 0 else "—"
	row.floor_label = floor_text(npc_floor(npc))
	row.chip_color = UITheme.band_accent_for_floor(npc_floor(npc))
	row.marked = targets.has(npc.id)
	row.full_file = not full_file_reason(npc.id).is_empty()
	row.zebra = index % 2 == 1
	row.selected = npc.id == _selected or npc.id == _compare_with
	row.picked.connect(_on_row_picked)
	return row


func _on_row_picked(npc_id: String) -> void:
	if _picking_compare and npc_id != _selected:
		compare(_selected, npc_id)
	else:
		select(npc_id)


func _sync_row_selection() -> void:
	for child: Node in _list_box.get_children():
		var row: NpcRow = child as NpcRow
		if row != null:
			row.selected = row.npc_id == _selected or row.npc_id == _compare_with
			row.marked = is_marked(row.npc_id)
			row.queue_redraw()


# ─── Expediente ───────────────────────────────────────────────────────

## Muestra el expediente de un personaje (al nivel efectivo).
func select(npc_id: String) -> void:
	if NPCDirector.get_npc(npc_id) == null:
		return
	_selected = npc_id
	_compare_with = ""
	_picking_compare = false
	if _built:
		_compare_btn.set_pressed_no_signal(false)
		_render_file()
		_sync_row_selection()


func get_selected() -> String:
	return _selected


## Vista de comparación simultánea de dos personajes.
func compare(a_id: String, b_id: String) -> void:
	if NPCDirector.get_npc(a_id) == null or NPCDirector.get_npc(b_id) == null or a_id == b_id:
		return
	_selected = a_id
	_compare_with = b_id
	_picking_compare = false
	if not _built:
		return
	_compare_btn.set_pressed_no_signal(true)
	_clear_detail()
	var view: CompareView = CompareView.new()
	view.set_files(build_file(a_id, effective_level(a_id)), build_file(b_id, effective_level(b_id)),
			SocialGraph.get_link_type(a_id, b_id), SocialGraph.get_link_strength(a_id, b_id))
	_detail_box.add_child(view)
	_sync_row_selection()
	_refresh_status()


func is_comparing() -> bool:
	return not _compare_with.is_empty()


func _clear_detail() -> void:
	for child: Node in _detail_box.get_children():
		child.queue_free()


func _render_file() -> void:
	_clear_detail()
	var file: Dictionary = build_file(_selected, effective_level(_selected))
	if file.is_empty():
		return
	_mark_btn.set_pressed_no_signal(is_marked(_selected))
	_detail_box.add_child(_file_header(file))
	_detail_box.add_child(_notes_strip())
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", OsKit.px(1.0))
	var left: VBoxContainer = _column(columns)
	var right: VBoxContainer = _column(columns)
	_detail_box.add_child(columns)
	var sections: Dictionary = file["sections"]
	for section: String in [S_CHARACTER, S_TRAITS, S_LINKS, S_POLITICS, S_COMMS]:
		if sections.has(section):
			left.add_child(_section_block(section, sections[section], bool(file["exact"])))
	for section: String in [S_ROUTINE, S_WEAKNESS, S_BRIBE, S_HISTORY, S_SECRETS, S_HOME, S_DISCIPLINE]:
		if sections.has(section):
			right.add_child(_section_block(section, sections[section], bool(file["exact"])))
	var locked: Array = file["locked"]
	if not locked.is_empty():
		_detail_box.add_child(_locked_block(locked))
	_refresh_status()


func _column(parent: HBoxContainer) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", OsKit.px(0.8))
	parent.add_child(col)
	return col


func _file_header(file: Dictionary) -> Control:
	var identity: Dictionary = file["sections"][S_IDENTITY]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", OsKit.px(1.0))
	var photo: Photo = Photo.new()
	photo.appearance = identity["photo"]
	photo.badge = "%05d" % (absi(hash(file["npc_id"])) % 100000)
	photo.stamp = tr("PERS_STAMP_TARGET") if is_marked(file["npc_id"]) else ""
	photo.custom_minimum_size = Vector2(OsKit.px(8.5), OsKit.px(10.5))
	row.add_child(photo)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", OsKit.px(0.2))
	info.add_child(OsKit.label(tr("PERS_FILE_KICKER"), OsKit.V_HEADING))
	info.add_child(OsKit.label(str(identity["name"]), OsKit.V_BIG))
	for pair: Array in [["PERS_FIELD_POST", identity["post"]], ["PERS_FIELD_FLOOR", identity["floor"]],
			["PERS_FIELD_WING", identity["wing"]]]:
		info.add_child(OsKit.field_row(tr(pair[0]), str(pair[1])))
	row.add_child(info)
	row.add_child(_level_card(file))
	return row


func _level_card(file: Dictionary) -> Control:
	var card: LevelCard = LevelCard.new()
	card.level = int(file["level"])
	card.max_level = max_level()
	card.level_name = tr("PERS_LEVEL_NAME_%d" % card.level)
	var reason: String = str(file.get("full_reason", ""))
	card.note = tr("PERS_FULL_FILE_FMT") % tr("PERS_REASON_" + reason.to_upper()) if not reason.is_empty() else ""
	card.hint = tr("PERS_LEVEL_HINT")
	card.custom_minimum_size = Vector2(OsKit.px(12.0), OsKit.px(7.0))
	return card


func _notes_strip() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", OsKit.px(0.2))
	for note: Dictionary in get_notes(_selected):
		box.add_child(OsKit.label(tr("PERS_NOTE_LINE") % [int(note["day"]), str(note["time"]),
				str(note["text"])], OsKit.V_NOTE))
	var studies: Dictionary = get_studies(_selected)
	for action: String in STUDY_ACTIONS:
		if studies.has(action):
			box.add_child(_study_line(studies[action]))
	var input_row: HBoxContainer = HBoxContainer.new()
	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = tr("PERS_NOTE_HINT")
	_note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_edit.text_submitted.connect(_on_note_submitted)
	input_row.add_child(_note_edit)
	var add: Button = OsKit.button(tr("PERS_NOTE_ADD"), "plus")
	add.pressed.connect(func() -> void: _on_note_submitted(_note_edit.text))
	input_row.add_child(add)
	box.add_child(input_row)
	return box


func _study_line(result: Dictionary) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", OsKit.px(0.5))
	var text: String = tr("PERS_STUDY_RESULT") % [tr("PERS_STUDY_Q_" + str(result["action"]).to_upper()),
			int(result["minutes"])]
	line.add_child(OsKit.label(text, OsKit.V_NOTE))
	var chip: Chip = Chip.new()
	chip.text = tr(str(result["word_key"]))
	chip.color = OsKit.probability_color(float(result["probability"]))
	line.add_child(chip)
	return line


func _section_block(section: String, data: Variant, exact: bool) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", OsKit.px(0.25))
	var head: SectionHead = SectionHead.new()
	head.text = tr("PERS_SEC_" + section.to_upper())
	head.level = section_level(section) if section != S_COMMS else 0
	box.add_child(head)
	match section:
		S_ROUTINE:
			_add_routine(box, data)
		S_CHARACTER:
			_add_character(box, data)
		S_TRAITS:
			_add_traits(box, data, exact)
		S_LINKS, S_POLITICS:
			_add_links(box, data, section == S_POLITICS)
		S_HISTORY:
			_add_history(box, data, exact)
		S_BRIBE:
			_add_bribe(box, data)
		S_HOME:
			_add_home(box, data)
		S_WEAKNESS:
			box.add_child(OsKit.wrap_label(str(data), OsKit.V_QUOTE))
		_:
			for line: Variant in data:
				box.add_child(OsKit.wrap_label("• " + str(line), OsKit.V_BODY))
	return box


func _add_routine(box: VBoxContainer, rows: Array) -> void:
	for row: Dictionary in rows:
		box.add_child(OsKit.field_row(str(row["band_name"]), str(row["place"])))


func _add_character(box: VBoxContainer, data: Dictionary) -> void:
	box.add_child(OsKit.label(str(data["archetype_name"]), OsKit.V_STRONG))
	box.add_child(OsKit.wrap_label(" ".join(PackedStringArray(data["lines"])), OsKit.V_QUOTE))


func _add_traits(box: VBoxContainer, rows: Array, exact: bool) -> void:
	for row: Dictionary in rows:
		var bar: TraitBar = TraitBar.new()
		bar.caption = str(row["name"])
		bar.value = int(row["value"])
		bar.word = str(row["word"])
		bar.exact = exact
		box.add_child(bar)


func _add_links(box: VBoxContainer, rows: Array, full: bool) -> void:
	if rows.is_empty():
		box.add_child(OsKit.label(tr("PERS_LINKS_NONE"), OsKit.V_SMALL))
	for row: Dictionary in rows:
		var link: LinkRow = LinkRow.new()
		link.who = str(row["name"])
		link.kind = str(row["type_name"])
		link.strength = float(row["strength"])
		link.exact = bool(row["exact"])
		link.secret = bool(row["secret"])
		link.arrow = "→" if bool(row["directed"]) and bool(row["outgoing"]) \
				else ("←" if bool(row["directed"]) else "↔")
		link.show_arrow = full
		link.link_type = str(row["type"])
		box.add_child(link)


func _add_history(box: VBoxContainer, data: Dictionary, exact: bool) -> void:
	var rows: Array[Array] = [["LEDGER_AFFECTION", "mood_word", "affection", "%+d"],
			["LEDGER_FEAR", "fear_word", "fear", "%d"], ["LEDGER_DEBT", "debt_word", "debt", "%+d"]]
	for row: Array in rows:
		var value: String = str(data[row[1]])
		if exact:
			value += "  (" + (str(row[3]) % int(data[row[2]])) + ")"
		box.add_child(OsKit.field_row(tr(row[0]), value))
	var entries: Array = data["entries"]
	if entries.is_empty():
		box.add_child(OsKit.label(tr("PERS_HISTORY_NONE"), OsKit.V_SMALL))
	for entry: Dictionary in entries:
		var text: String = tr("PERS_HISTORY_LINE") % [int(entry["day"]), str(entry["text"])]
		if entry.has("amount"):
			text += " (%d)" % int(entry["amount"])
		box.add_child(OsKit.wrap_label(("▼ " if bool(entry["grievance"]) else "▲ ") + text,
				OsKit.V_BODY))


func _add_bribe(box: VBoxContainer, data: Dictionary) -> void:
	if bool(data["unbribable"]):
		var chip: Chip = Chip.new()
		chip.text = tr("PERS_BRIBE_UNBRIBABLE")
		chip.color = OsKit.red()
		box.add_child(chip)
	for row: Dictionary in data["prices"]:
		box.add_child(OsKit.field_row(str(row["name"]), UITheme.format_money(int(row["price"])),
				OsKit.V_STRONG))


func _add_home(box: VBoxContainer, data: Dictionary) -> void:
	box.add_child(OsKit.label(str(data["address"]), OsKit.V_STRONG))
	box.add_child(OsKit.label(str(data["kind"]), OsKit.V_SMALL))
	box.add_child(OsKit.wrap_label(tr("PERS_HOME_NIGHT_OPS"), OsKit.V_NOTE))


func _locked_block(locked: Array) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", OsKit.px(0.35))
	var head: SectionHead = SectionHead.new()
	head.text = tr("PERS_SEC_CLASSIFIED")
	box.add_child(head)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", OsKit.px(0.8))
	grid.add_theme_constant_override("v_separation", OsKit.px(0.4))
	for entry: Dictionary in locked:
		var redacted: Redacted = Redacted.new()
		redacted.caption = tr("PERS_SEC_" + str(entry["id"]).to_upper())
		redacted.level = int(entry["level"])
		redacted.seed_value = hash(entry["id"])
		redacted.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(redacted)
	box.add_child(grid)
	return box


# ─── Acciones ─────────────────────────────────────────────────────────

func _on_mark_toggled(on: bool) -> void:
	if _selected.is_empty():
		return
	set_marked(_selected, on)
	_render_file()
	_sync_row_selection()


func _on_compare_toggled(on: bool) -> void:
	if on:
		_picking_compare = true
		_compare_with = ""
		_clear_detail()
		var hint: Label = OsKit.wrap_label(tr("PERS_COMPARE_HINT") % other_name(_selected),
				OsKit.V_STRONG)
		_detail_box.add_child(hint)
		_refresh_status()
	else:
		select(_selected)


func _on_study_pressed(action: String) -> void:
	if _selected.is_empty():
		return
	_last_study = study(_selected, action)
	if is_comparing():
		compare(_selected, _compare_with)
	else:
		_render_file()


func get_last_study() -> Dictionary:
	return _last_study.duplicate()


func _on_note_submitted(text: String) -> void:
	if add_note(_selected, text):
		_render_file()


func _refresh_status() -> void:
	if not _built:
		return
	var level: int = player_level()
	_set_status([
		tr("PERS_STATUS_LEVEL") % [level, tr("PERS_LEVEL_NAME_%d" % level)],
		tr("PERS_STATUS_TARGETS") % get_marked_targets().size(),
		tr("PERS_STATUS_CLOCK") % [GameClock.get_day(), GameClock.get_time_string()],
	])


# ═══ Kit visual de las aplicaciones (sobre OSTheme; compartido por PORTAL y MARKET) ═════

## Adaptador sobre OSTheme: la paleta es la del equipo del jugador (el ordenador MEJORA CON EL RANGO:
## retro → classic → luna → sovereign; contrast con alto contraste) y el tamaño base el de la carcasa.
## Las aplicaciones llaman a use(paleta, base) al construirse; los dibujos propios leen los colores
## con face(), ink(), teal()… en el momento de pintar.
class OsKit extends RefCounted:
	const V_TITLE := "PnTitle"
	const V_BIG := "PnBig"
	const V_HEADING := "PnHeading"
	const V_SMALL := "PnSmall"
	const V_BODY := "PnBody"
	const V_STRONG := "PnStrong"
	const V_MONO := "PnMono"
	const V_NOTE := "PnNote"
	const V_QUOTE := "PnQuote"
	const V_FIELD := "PnField"
	const V_PAPER := "PnPaper"
	const V_INSET := "PnInset"
	const V_WINDOW := "PnWindow"
	const V_PRIMARY := OSTheme.V_PRIMARY
	const V_DANGER := OSTheme.V_DANGER
	const HAZARD := Color("#f2c230")
	## Proporciones de diseño respecto al tamaño base de la carcasa (maquetación, no balance).
	const RATIO_BODY := 0.78
	const SIDEBAR_EM := 21.0
	const DESKTOP_MARGIN := 1.4
	const BAND := 2

	static var pal: Dictionary = {}
	static var base: int = 0
	static var _themes: Dictionary = {}
	static var _textures: Dictionary = {}

	## Fija la paleta y el tamaño base (vacíos → equipo del jugador y tamaño de texto vigente).
	static func use(palette: Dictionary, base_px: int) -> void:
		pal = palette if not palette.is_empty() else player_palette()
		base = base_px if base_px > 0 else UITheme.base_font_size(UITheme.current_text_size)

	static func player_palette() -> Dictionary:
		var occupation: OccupationData = PlayerState.get_occupation()
		return OSTheme.palette_for_tier(occupation.computer_tier if occupation != null else 1)

	static func ensure() -> void:
		if pal.is_empty() or base <= 0:
			use(pal, base)

	static func c(key: String) -> Color:
		ensure()
		return OSTheme.col(pal, key)

	static func face() -> Color:
		return c("face")

	static func face_hi() -> Color:
		return c("light")

	static func face_mid() -> Color:
		return c("shadow")

	static func face_dark() -> Color:
		return c("dark")

	static func field() -> Color:
		return c("field")

	static func paper() -> Color:
		return c("field").lerp(c("face"), 0.18)

	static func zebra() -> Color:
		return c("field").lerp(c("face"), 0.4)

	static func ink() -> Color:
		return c("text")

	static func ink_soft() -> Color:
		return c("muted")

	static func soft() -> Color:
		return c("muted")

	static func is_contrast() -> bool:
		ensure()
		return pal.get("skin", "") == OSTheme.SKIN_CONTRAST

	## Color de marca de las aplicaciones (títulos, barras): el de la barra de título; en alto
	## contraste, el acento (amarillo sobre negro).
	static func teal() -> Color:
		return c("accent") if is_contrast() else c("title_a")

	static func teal_light() -> Color:
		return c("accent") if is_contrast() else c("title_b")

	static func title_ink() -> Color:
		return Color.BLACK if is_contrast() else c("title_text")

	static func select() -> Color:
		return c("select")

	static func select_ink() -> Color:
		return c("select_text")

	static func red() -> Color:
		return c("bad")

	static func amber() -> Color:
		return c("warn")

	static func green() -> Color:
		return c("good")

	static func blue() -> Color:
		return c("select")

	## Tinta de las notas del jugador: el color de selección, oscurecido si es claro (oro, amarillo).
	static func note_ink() -> Color:
		var sel: Color = select()
		if is_contrast():
			return sel
		return sel.darkened(0.35) if sel.get_luminance() > 0.35 else sel

	static func accent() -> Color:
		return c("accent")

	static func hazard() -> Color:
		return HAZARD

	## Tamaño de letra base de las aplicaciones (sigue el ajuste de tamaño de texto §13.10).
	static func base_size() -> int:
		ensure()
		return roundi(base * RATIO_BODY)

	static func px(em: float) -> int:
		return roundi(base_size() * em)

	static func font_regular() -> Font:
		return UITheme.font(UITheme.FONT_REGULAR)

	static func font_bold() -> Font:
		return UITheme.font(UITheme.FONT_SEMIBOLD)

	static func font_black() -> Font:
		return UITheme.font(UITheme.FONT_BOLD)

	static func font_mono() -> Font:
		return UITheme.font(UITheme.FONT_MONO)

	## Color de una probabilidad según su palabra difusa (umbrales de expedientes.umbrales_probabilidad).
	static func probability_color(p: float) -> Color:
		var index: int = PersonnelApp.PROB_WORD_KEYS.find(PersonnelApp.probability_word_key(p))
		var middle: int = floori(PersonnelApp.PROB_WORD_KEYS.size() / 2.0)
		if index > middle:
			return green()
		return amber() if index == middle else red()

	## Tema de OSTheme para la paleta vigente más las variantes propias de las aplicaciones.
	static func build_theme() -> Theme:
		ensure()
		var key: String = "%s_%s_%d" % [pal.get("skin", ""), pal.get("band", ""), base]
		if _themes.has(key):
			return _themes[key]
		var t: Theme = OSTheme.build(pal, base)
		_theme_labels(t)
		_theme_panels(t)
		_theme_extras(t)
		_themes[key] = t
		return t

	static func _theme_labels(t: Theme) -> void:
		var specs: Array[Array] = [
			[V_TITLE, font_black(), 1.5, ink()], [V_BIG, font_black(), 1.9, ink()],
			[V_HEADING, font_black(), 0.78, teal()], [V_SMALL, font_regular(), 0.84, soft()],
			[V_BODY, font_regular(), 1.0, ink()], [V_STRONG, font_bold(), 1.05, ink()],
			[V_MONO, font_mono(), 0.95, ink()], [V_NOTE, font_regular(), 0.92, note_ink()],
			[V_QUOTE, UITheme.italic(font_regular()), 1.05, ink()],
		]
		for spec: Array in specs:
			t.set_type_variation(spec[0], "Label")
			t.set_font("font", spec[0], spec[1])
			t.set_font_size("font_size", spec[0], px(float(spec[2])))
			t.set_color("font_color", spec[0], spec[3])

	static func _theme_panels(t: Theme) -> void:
		var variations: Array[Array] = [
			[V_FIELD, OSTheme.box(pal, "field", base, Vector2(px(0.15), px(0.15)))],
			[V_INSET, OSTheme.box(pal, "pressed", base, Vector2(px(0.5), px(0.3)))],
			[V_PAPER, OSTheme.box(pal, "field", base, Vector2(px(1.0), px(0.8)))],
			[V_WINDOW, OSTheme.box(pal, "window", base, Vector2(px(0.25), px(0.25)))],
		]
		for spec: Array in variations:
			t.set_type_variation(spec[0], "PanelContainer")
			t.set_stylebox("panel", spec[0], spec[1])

	static func _theme_extras(t: Theme) -> void:
		t.set_icon("arrow", "OptionButton", arrow_texture())
		t.set_constant("h_separation", "Button", px(0.4))
		t.set_stylebox("panel", "PopupMenu", OSTheme.box(pal, "window", base, Vector2(px(0.3), px(0.3))))
		t.set_stylebox("hover", "PopupMenu", flat_box(select(), 0))
		t.set_color("font_color", "PopupMenu", ink())
		t.set_color("font_hover_color", "PopupMenu", select_ink())
		t.set_font_size("font_size", "PopupMenu", px(0.95))
		t.set_icon("radio_unchecked", "PopupMenu", blank_texture(1))
		t.set_icon("radio_checked", "PopupMenu", blank_texture(1))
		t.set_stylebox("slider", "HSlider", OSTheme.box(pal, "field", base, Vector2(px(0.2), px(0.2))))
		t.set_stylebox("grabber_area", "HSlider", flat_box(teal_light(), 0))
		t.set_stylebox("grabber_area_highlight", "HSlider", flat_box(teal_light(), 0))

	static func flat_box(fill: Color, border: int, border_color: Color = Color.BLACK, pad: float = 0.0) -> StyleBoxFlat:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_border_width_all(border)
		sb.border_color = border_color
		sb.set_content_margin_all(px(pad))
		return sb

	## Textura transparente de `side` px (reserva el hueco del glifo en los botones).
	static func blank_texture(side: int) -> ImageTexture:
		var key: String = "blank_%d" % side
		if not _textures.has(key):
			var img: Image = Image.create(maxi(side, 1), maxi(side, 1), false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			_textures[key] = ImageTexture.create_from_image(img)
		return _textures[key]

	## Flecha de los desplegables en el color del texto de la paleta.
	static func arrow_texture() -> ImageTexture:
		var key: String = "arrow_%s_%d" % [ink().to_html(), base]
		if _textures.has(key):
			return _textures[key]
		var s: int = px(0.7)
		var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var top: int = roundi(s * 0.25)
		var bottom: int = roundi(s * 0.75)
		var mid: int = roundi(s * 0.5)
		for y: int in range(top, bottom):
			var half: int = roundi((bottom - y) * 0.66)
			for x: int in range(mid - half, mid + half + 1):
				img.set_pixel(clampi(x, 0, s - 1), y, ink())
		_textures[key] = ImageTexture.create_from_image(img)
		return _textures[key]

	static func label(text: String, variation: String) -> Label:
		var l: Label = Label.new()
		l.text = text
		l.theme_type_variation = variation
		return l

	static func wrap_label(text: String, variation: String) -> Label:
		var l: Label = label(text, variation)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = px(6.0)
		return l

	## Fila «Etiqueta ........ valor» de formulario.
	static func field_row(caption: String, value: String, variation: String = V_BODY) -> HBoxContainer:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", px(0.5))
		var cap: Label = label(caption, V_SMALL)
		cap.custom_minimum_size.x = px(7.5)
		row.add_child(cap)
		var val: Label = label(value, variation)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(val)
		return row

	static func button(text: String, icon_name: String = "", variation: String = "") -> Button:
		var b: GlyphButton = GlyphButton.new()
		b.text = text
		b.theme_type_variation = variation
		var glyph_color: Color = ink()
		if variation == V_PRIMARY:
			glyph_color = select_ink()
		elif variation == V_DANGER:
			glyph_color = Color.WHITE
		b.set_glyph(icon_name, glyph_color)
		return b

	## Color de la banda de arte de una planta (art_bands.json → accent).
	static func band_color(floor_number: int) -> Color:
		return Color(str(UITheme.band_palette_for_floor(floor_number).get("accent", "#6d7a5c")))

	static func text(ci: CanvasItem, pos: Vector2, value: String, font: Font, font_size: int,
			color: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var shown: String = fit(font, value, font_size, width) if width > 0.0 else value
		ci.draw_string(font, pos, shown, align, width, font_size, color)

	## Trunca con «…» para que quepa en `width`.
	static func fit(font: Font, value: String, font_size: int, width: float) -> String:
		if width <= 0.0 or font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return value
		var out: String = value
		while out.length() > 1 and font.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x > width:
			out = out.substr(0, out.length() - 1)
		return out + "…"

	## Ventana propia (modo suelto, sin carcasa) dentro de `app`, con el margen del escritorio.
	static func make_window(app: Control, title: String, icon: String) -> OsWindow:
		var window: OsWindow = OsWindow.new(title, icon)
		window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
				px(DESKTOP_MARGIN))
		app.add_child(window)
		return window

	## Margen interior dentro de la ventana de la carcasa (modo integrado).
	static func make_holder(app: Control) -> MarginContainer:
		var holder: MarginContainer = MarginContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			holder.add_theme_constant_override(side, px(0.35))
		app.add_child(holder)
		return holder

	## Barra de estado: la de la ventana propia o la de la carcasa (OSApp.status_posted).
	static func show_status(app: OSApp, window: OsWindow, parts: Array) -> void:
		if window != null:
			window.set_status(parts)
		else:
			app.post_status("   ·   ".join(PackedStringArray(parts)))

	## Valor pedido al abrir: de la carcasa en context.extra[extra_key]; suelta, en context[key].
	static func requested(ctx: Dictionary, key: String, extra_key: String) -> String:
		var extra: Variant = ctx.get("extra", {})
		if ctx.has("shell"):
			return str((extra as Dictionary).get(extra_key, "")) if extra is Dictionary else ""
		return str(ctx.get(key, ""))

	## Papel pintado del escritorio del aspecto vigente (modo suelto, sin carcasa).
	static func draw_desktop(ci: CanvasItem, rect: Rect2) -> void:
		ensure()
		OSTheme.draw_wallpaper(ci, rect, pal)

	## Rayas diagonales (vacantes, zonas vetadas).
	static func draw_hatch(ci: CanvasItem, rect: Rect2, color: Color, spacing: float, width: float) -> void:
		var x: float = rect.position.x - rect.size.y
		while x < rect.end.x:
			var clipped: PackedVector2Array = _clip_segment(Vector2(x, rect.end.y),
					Vector2(x + rect.size.y, rect.position.y), rect)
			if clipped.size() == 2:
				ci.draw_line(clipped[0], clipped[1], color, width)
			x += spacing

	static func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
		var p0: Vector2 = a
		var p1: Vector2 = b
		if p0.x < r.position.x:
			p0 = p0 + (p1 - p0) * ((r.position.x - p0.x) / (p1.x - p0.x))
		if p1.x > r.end.x:
			p1 = p0 + (p1 - p0) * ((r.end.x - p0.x) / (p1.x - p0.x))
		if p0.x > p1.x:
			return PackedVector2Array()
		return PackedVector2Array([p0, p1])

	## Marco con el estilo del aspecto (bisel en retro/classic; panel plano redondeado si no).
	static func draw_bevel(ci: CanvasItem, rect: Rect2, fill: Color, sunken: bool) -> void:
		ensure()
		if not bool(pal.get("bevel", false)):
			OSTheme.draw_panel(ci, rect, pal, fill)
			return
		var b: OSTheme.BevelBox = OSTheme.BevelBox.new()
		b.width = OSTheme.bevel_width(base)
		b.face = fill
		b.light = face().lerp(face_hi(), 0.55)
		b.hilite = face_hi()
		b.shadow = face_mid()
		b.dark = face_dark()
		b.sunken = sunken
		b.draw(ci.get_canvas_item(), rect)


## Botón con glifo vectorial de UITheme a la izquierda del texto (el hueco lo reserva un icono vacío).
class GlyphButton extends Button:
	var glyph: String = ""
	var glyph_color: Color = OsKit.ink()

	func set_glyph(icon_name: String, color: Color) -> void:
		glyph = icon_name
		glyph_color = color
		if glyph.is_empty():
			icon = null
			return
		icon = OsKit.blank_texture(OsKit.px(0.95))

	func _draw() -> void:
		if glyph.is_empty():
			return
		var box: StyleBox = get_theme_stylebox("normal")
		var s: float = float(OsKit.px(0.95))
		var r: Rect2 = Rect2(box.get_margin(SIDE_LEFT), (size.y - s) * 0.5, s, s)
		var color: Color = glyph_color if not disabled else Color(glyph_color, 0.45)
		UITheme.draw_icon(self, glyph, r, color, maxf(s * 0.1, 1.5))


## Ventana biselada con barra de título, cuerpo y barra de estado.
class OsWindow extends PanelContainer:
	signal close_pressed

	var body: MarginContainer
	var _title_bar: OsTitleBar
	var _status_row: HBoxContainer

	func _init(title: String, icon_name: String) -> void:
		theme_type_variation = OsKit.V_WINDOW
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", OsKit.px(0.3))
		add_child(col)
		_title_bar = OsTitleBar.new(title, icon_name)
		_title_bar.close_pressed.connect(func() -> void: close_pressed.emit())
		col.add_child(_title_bar)
		body = MarginContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			body.add_theme_constant_override(side, OsKit.px(0.35))
		col.add_child(body)
		_status_row = HBoxContainer.new()
		_status_row.add_theme_constant_override("separation", OsKit.px(0.2))
		col.add_child(_status_row)

	func set_title(title: String) -> void:
		_title_bar.title = title
		_title_bar.queue_redraw()

	func set_status(texts: Array) -> void:
		for child: Node in _status_row.get_children():
			child.queue_free()
		for i: int in texts.size():
			var cell: PanelContainer = PanelContainer.new()
			cell.theme_type_variation = OsKit.V_INSET
			if i == 0:
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(OsKit.label(str(texts[i]), OsKit.V_SMALL))
			_status_row.add_child(cell)


## Barra de título degradada (verde azulado) con icono, título y botones de ventana.
class OsTitleBar extends Control:
	signal close_pressed

	var title: String = ""
	var icon_name: String = ""
	var _close: Button

	func _init(title_text: String, glyph: String) -> void:
		title = title_text
		icon_name = glyph
		custom_minimum_size.y = OsKit.px(1.9)
		_close = OsKit.button("", "cross")
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var kind: String = "pressed" if state.ends_with("pressed") else ("hover" if state == "hover" else "raised")
			_close.add_theme_stylebox_override(state, OSTheme.box(OsKit.pal, kind, OsKit.base,
					Vector2(OsKit.px(0.18), OsKit.px(0.12))))
		_close.tooltip_text = TranslationServer.translate("OS_CLOSE")
		_close.pressed.connect(func() -> void: close_pressed.emit())
		add_child(_close)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and _close != null:
			var s: Vector2 = _close.get_combined_minimum_size()
			_close.size = s
			_close.position = Vector2(size.x - s.x - OsKit.px(0.25), (size.y - s.y) * 0.5)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OSTheme.draw_title_bar(self, r, OsKit.pal, true)
		var pad: float = float(OsKit.px(0.3))
		var box: Rect2 = Rect2(pad, pad, size.y - pad * 2.0, size.y - pad * 2.0)
		OSTheme.draw_icon(self, icon_name, box, OsKit.pal)
		var fsize: int = OsKit.px(1.0)
		var baseline: float = size.y * 0.5 + fsize * 0.36
		OsKit.text(self, Vector2(box.end.x + pad * 2.0, baseline), title, OsKit.font_black(), fsize,
				OsKit.title_ink(), size.x - box.end.x - OsKit.px(8.0))
		var deco: float = size.y - pad * 2.0
		var close_w: float = _close.get_combined_minimum_size().x + OsKit.px(0.5)
		for i: int in 2:
			var x: float = size.x - close_w - (deco * 1.2 + pad) * float(2 - i)
			var btn: Rect2 = Rect2(x, pad, deco * 1.2, deco)
			OsKit.draw_bevel(self, btn, OsKit.face(), false)
			var glyph: Rect2 = btn.grow(-deco * 0.3)
			if i == 0:
				draw_line(Vector2(glyph.position.x, glyph.end.y), glyph.end, OsKit.ink(), 2.0)
			else:
				draw_rect(glyph, OsKit.ink(), false, 2.0)


## Foto de expediente: polaroid con clip, número de ficha y sello opcional.
class Photo extends Control:
	## La foto es siempre una polaroid blanca: tinta fija, independiente del aspecto.
	const BADGE_INK := Color("#55524a")

	var appearance: Dictionary = {}
	var badge: String = ""
	var stamp: String = ""

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.2))
		draw_rect(r, Color.WHITE)
		draw_rect(r, OsKit.ink(), false, 2.0)
		var pad: float = size.x * 0.07
		var photo: Rect2 = Rect2(pad, pad, size.x - pad * 2.0, minf(size.x - pad * 2.0, size.y - pad * 4.0))
		if not appearance.is_empty():
			CharacterPainter.draw_portrait(self, appearance, photo)
		draw_rect(photo, OsKit.ink(), false, 1.5)
		var fsize: int = OsKit.px(0.8)
		OsKit.text(self, Vector2(pad, photo.end.y + (size.y - photo.end.y) * 0.5 + fsize * 0.35),
				TranslationServer.translate("PERS_BADGE_FMT") % badge, OsKit.font_mono(), fsize, BADGE_INK, photo.size.x)
		_draw_clip(Vector2(size.x * 0.7, -OsKit.px(0.45)))
		if not stamp.is_empty():
			_draw_stamp(photo)

	func _draw_clip(at: Vector2) -> void:
		var h: float = float(OsKit.px(1.9))
		var w: float = float(OsKit.px(0.55))
		var pts: PackedVector2Array = PackedVector2Array([at + Vector2(0, h), at, at + Vector2(w, 0),
				at + Vector2(w, h * 0.8), at + Vector2(w * 0.25, h * 0.8), at + Vector2(w * 0.25, h * 0.2)])
		draw_polyline(pts, OsKit.ink(), 4.0)
		draw_polyline(pts, Color("#b9bcc2"), 2.0)

	func _draw_stamp(photo: Rect2) -> void:
		var fsize: int = OsKit.px(1.05)
		var font: Font = OsKit.font_black()
		var w: float = font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + OsKit.px(0.8)
		draw_set_transform(photo.get_center() + Vector2(0, photo.size.y * 0.28), -0.22, Vector2.ONE)
		var box: Rect2 = Rect2(-w * 0.5, -fsize * 0.8, w, fsize * 1.4)
		draw_rect(box, Color(OsKit.red(), 0.12))
		draw_rect(box, OsKit.red(), false, 3.0)
		draw_string(font, Vector2(-w * 0.5, fsize * 0.35), stamp, HORIZONTAL_ALIGNMENT_CENTER, w, fsize, OsKit.red())
		draw_set_transform(Vector2.ZERO)


## Fila de la lista de personal: rango, nombre, puesto, planta y marcas.
class NpcRow extends Control:
	signal picked(npc_id: String)

	var npc_id: String = ""
	var title: String = ""
	var subtitle: String = ""
	var chip: String = ""
	var chip_color: Color = OsKit.teal()
	var floor_label: String = ""
	var marked: bool = false
	var full_file: bool = false
	var selected: bool = false
	var zebra: bool = false
	var _hover: bool = false

	func _init() -> void:
		custom_minimum_size.y = OsKit.px(2.55)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: _set_hover(true))
		mouse_exited.connect(func() -> void: _set_hover(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if UITheme.is_primary_press(event):
			picked.emit(npc_id)
			accept_event()

	func _draw() -> void:
		var bg: Color = OsKit.select() if selected else (OsKit.face_hi() if _hover
				else (OsKit.zebra() if zebra else OsKit.field()))
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		var ink: Color = OsKit.select_ink() if selected else OsKit.ink()
		var soft: Color = Color(OsKit.select_ink(), 0.75) if selected else OsKit.soft()
		var pad: float = float(OsKit.px(0.4))
		var chip_w: float = float(OsKit.px(2.3))
		var chip_r: Rect2 = Rect2(pad, size.y * 0.5 - OsKit.px(0.62), chip_w, OsKit.px(1.24))
		draw_rect(chip_r, chip_color)
		draw_rect(chip_r, OsKit.ink(), false, 1.5)
		OsKit.text(self, Vector2(chip_r.position.x, chip_r.get_center().y + OsKit.px(0.28)), chip,
				OsKit.font_black(), OsKit.px(0.75), UITheme.readable_on(chip_color), chip_w,
				HORIZONTAL_ALIGNMENT_CENTER)
		var x: float = chip_r.end.x + pad
		var right_w: float = float(OsKit.px(4.2))
		var text_w: float = size.x - x - right_w - pad
		OsKit.text(self, Vector2(x, size.y * 0.44), title, OsKit.font_bold(), OsKit.px(0.95), ink, text_w)
		OsKit.text(self, Vector2(x, size.y * 0.84), subtitle, OsKit.font_regular(), OsKit.px(0.78), soft, text_w)
		OsKit.text(self, Vector2(size.x - right_w - pad, size.y * 0.84), floor_label, OsKit.font_regular(),
				OsKit.px(0.72), soft, right_w, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_marks(ink)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(OsKit.face_mid(), 0.35), 1.0)

	func _draw_marks(ink: Color) -> void:
		var s: float = float(OsKit.px(0.95))
		var x: float = size.x - OsKit.px(0.4) - s
		if marked:
			UITheme.draw_icon(self, "target", Rect2(x, size.y * 0.1, s, s), OsKit.red(), s * 0.12)
			x -= s * 1.2
		if full_file:
			UITheme.draw_icon(self, "eye", Rect2(x, size.y * 0.1, s, s), ink, s * 0.1)


## Encabezado de sección: versalitas, filete y nivel requerido.
class SectionHead extends Control:
	var text: String = ""
	var level: int = 0

	func _init() -> void:
		custom_minimum_size.y = OsKit.px(1.45)

	func _draw() -> void:
		var fsize: int = OsKit.px(0.8)
		OsKit.text(self, Vector2(0, size.y - OsKit.px(0.45)), text.to_upper(), OsKit.font_black(), fsize,
				OsKit.teal(), size.x - OsKit.px(2.5))
		draw_line(Vector2(0, size.y - 2), Vector2(size.x, size.y - 2), OsKit.teal(), 2.0)
		if level > 0:
			OsKit.text(self, Vector2(size.x - OsKit.px(2.2), size.y - OsKit.px(0.45)), TranslationServer.translate("PERS_LEVEL_CHIP") % level,
					OsKit.font_mono(), OsKit.px(0.72), OsKit.ink_soft(), OsKit.px(2.2), HORIZONTAL_ALIGNMENT_RIGHT)


## Barra de rasgo: aproximada (tramo) hasta N5; exacta con cifra a partir de N5.
class TraitBar extends Control:
	var caption: String = ""
	var value: int = 0
	var word: String = ""
	var exact: bool = false

	func _init() -> void:
		custom_minimum_size.y = OsKit.px(1.35)

	func _draw() -> void:
		var cap_w: float = float(OsKit.px(6.5))
		var tail_w: float = float(OsKit.px(3.6))
		var fsize: int = OsKit.px(0.85)
		var mid: float = size.y * 0.5 + fsize * 0.35
		OsKit.text(self, Vector2(0, mid), caption, OsKit.font_regular(), fsize, OsKit.ink(), cap_w)
		var track: Rect2 = Rect2(cap_w, size.y * 0.22, size.x - cap_w - tail_w, size.y * 0.56)
		OsKit.draw_bevel(self, track, OsKit.field(), true)
		var inner: Rect2 = track.grow(-OsKit.BAND)
		var fill: Rect2 = Rect2(inner.position, Vector2(inner.size.x * clampf(value / 100.0, 0.0, 1.0), inner.size.y))
		var color: Color = OsKit.teal().lerp(OsKit.teal_light(), 0.4) if exact else Color(OsKit.teal_light(), 0.75)
		draw_rect(fill, color)
		if not exact:
			OsKit.draw_hatch(self, Rect2(fill.end.x - inner.size.x * 0.1, fill.position.y,
					inner.size.x * 0.1, fill.size.y), Color(OsKit.paper(), 0.7), 5.0, 2.0)
		for tick: int in [1, 2, 3]:
			var tx: float = inner.position.x + inner.size.x * tick * 0.25
			draw_line(Vector2(tx, inner.position.y), Vector2(tx, inner.end.y), Color(OsKit.ink(), 0.18), 1.0)
		var tail: String = str(value) if exact else "~ " + word
		OsKit.text(self, Vector2(track.end.x + OsKit.px(0.4), mid), tail,
				OsKit.font_mono() if exact else OsKit.font_regular(), fsize, OsKit.ink(), tail_w - OsKit.px(0.4))


## Vínculo social: tipo (color), persona, fuerza.
class LinkRow extends Control:
	const TYPE_COLORS: Dictionary = {
		"friendship": Color("#3a7a3e"), "couple": Color("#c0457a"), "rivalry": Color("#b23a2c"),
		"hierarchy": Color("#2b5b98"), "department": Color("#7a7466"), "debt": Color("#d4912a"),
		"nepotism": Color("#7b4aa0"),
	}
	var who: String = ""
	var kind: String = ""
	var link_type: String = ""
	var strength: float = 0.0
	var exact: bool = false
	var secret: bool = false
	var arrow: String = ""
	var show_arrow: bool = false

	func _init() -> void:
		custom_minimum_size.y = OsKit.px(1.35)

	func _draw() -> void:
		var fsize: int = OsKit.px(0.88)
		var mid: float = size.y * 0.5 + fsize * 0.35
		var color: Color = TYPE_COLORS.get(link_type, OsKit.ink_soft())
		draw_circle(Vector2(OsKit.px(0.4), size.y * 0.5), OsKit.px(0.3), color)
		draw_arc(Vector2(OsKit.px(0.4), size.y * 0.5), OsKit.px(0.3), 0, TAU, 16, OsKit.ink(), 1.5)
		var x: float = float(OsKit.px(1.0))
		var bar_w: float = float(OsKit.px(4.6))
		var name_w: float = (size.x - x - bar_w - OsKit.px(0.6)) * 0.55
		var label: String = (arrow + " " if show_arrow else "") + who
		OsKit.text(self, Vector2(x, mid), label, OsKit.font_bold(), fsize, OsKit.ink(), name_w)
		var kind_text: String = kind + ("  · " + TranslationServer.translate("PERS_SECRET_TAG") if secret else "")
		OsKit.text(self, Vector2(x + name_w + OsKit.px(0.3), mid), kind_text, OsKit.font_regular(),
				OsKit.px(0.8), OsKit.red() if secret else OsKit.soft(), size.x - x - name_w - bar_w - OsKit.px(0.6))
		var bar: Rect2 = Rect2(size.x - bar_w, size.y * 0.3, bar_w - (OsKit.px(2.1) if exact else 0.0), size.y * 0.4)
		OsKit.draw_bevel(self, bar, OsKit.field(), true)
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * strength, bar.size.y - 4)), color)
		if exact:
			OsKit.text(self, Vector2(bar.end.x + OsKit.px(0.25), mid), "%.2f" % strength, OsKit.font_mono(),
					OsKit.px(0.78), OsKit.ink(), OsKit.px(1.9))


## Etiqueta de color («PROBABLE», «INSOBORNABLE»).
class Chip extends Control:
	var text: String = ""
	var color: Color = OsKit.teal()

	func _ready() -> void:
		var fsize: int = OsKit.px(0.78)
		var w: float = OsKit.font_black().get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		custom_minimum_size = Vector2(w + OsKit.px(1.0), OsKit.px(1.3))
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_colored_polygon(UITheme.rounded_rect_points(r, OsKit.px(0.3)), color)
		var fsize: int = OsKit.px(0.78)
		OsKit.text(self, Vector2(0, size.y * 0.5 + fsize * 0.36), text.to_upper(), OsKit.font_black(), fsize,
				UITheme.readable_on(color), size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Sección clasificada: título, candado con el nivel necesario y tachones negros.
class Redacted extends Control:
	var caption: String = ""
	var level: int = 0
	var seed_value: int = 0

	func _init() -> void:
		custom_minimum_size.y = OsKit.px(3.1)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(OsKit.face(), 0.35))
		draw_dashed_line(r.position, Vector2(r.end.x, 0), OsKit.face_mid(), 1.5, 6.0)
		draw_dashed_line(Vector2(0, r.end.y - 1), r.end - Vector2(0, 1), OsKit.face_mid(), 1.5, 6.0)
		var fsize: int = OsKit.px(0.8)
		var pad: float = float(OsKit.px(0.4))
		OsKit.text(self, Vector2(pad, pad + fsize), caption.to_upper(), OsKit.font_black(), fsize,
				OsKit.ink_soft(), size.x - OsKit.px(4.0))
		var chip: Rect2 = Rect2(size.x - OsKit.px(3.3), pad * 0.6, OsKit.px(3.0), OsKit.px(1.15))
		draw_rect(chip, OsKit.face_dark())
		UITheme.draw_icon(self, "lock", Rect2(chip.position + Vector2(3, 2), Vector2(chip.size.y - 4, chip.size.y - 4)),
				OsKit.hazard(), 1.8)
		OsKit.text(self, Vector2(chip.position.x + chip.size.y, chip.get_center().y + fsize * 0.36), TranslationServer.translate("PERS_LEVEL_CHIP") % level,
				OsKit.font_black(), fsize, OsKit.hazard(), chip.size.x - chip.size.y, HORIZONTAL_ALIGNMENT_CENTER)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var y: float = pad * 1.6 + fsize
		var line_h: float = float(OsKit.px(0.55))
		while y + line_h < size.y - pad * 0.5:
			var x: float = pad
			while x < size.x - pad * 2.0:
				var w: float = minf(rng.randf_range(0.12, 0.38) * size.x, size.x - pad - x)
				draw_rect(Rect2(x, y, w, line_h), OsKit.ink())
				x += w + rng.randf_range(0.02, 0.05) * size.x
			y += line_h * 1.7


## Tarjeta de acreditación: nivel N1–N7 con pips y motivo del acceso completo.
class LevelCard extends Control:
	var level: int = 1
	var max_level: int = 7
	var level_name: String = ""
	var note: String = ""
	var hint: String = ""

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OsKit.draw_bevel(self, r, OsKit.face(), false)
		var inner: Rect2 = r.grow(-OsKit.px(0.35))
		draw_rect(inner, OsKit.teal(), false, 2.0)
		var pad: float = float(OsKit.px(0.5))
		var small: int = OsKit.px(0.72)
		OsKit.text(self, inner.position + Vector2(pad, pad + small), TranslationServer.translate("PERS_CLEARANCE").to_upper(),
				OsKit.font_black(), small, OsKit.teal(), inner.size.x - pad * 2.0)
		var big: int = OsKit.px(2.4)
		OsKit.text(self, inner.position + Vector2(pad, pad + small + big * 0.95), TranslationServer.translate("PERS_LEVEL_CHIP") % level, OsKit.font_black(),
				big, OsKit.ink(), inner.size.x * 0.45)
		var pip: float = (inner.size.x * 0.5 - pad) / float(max_level)
		for i: int in max_level:
			var p: Rect2 = Rect2(inner.position.x + inner.size.x * 0.5 + i * pip, inner.position.y + pad + small * 1.6,
					pip * 0.7, big * 0.6)
			draw_rect(p, OsKit.teal() if i < level else OsKit.field())
			draw_rect(p, OsKit.ink(), false, 1.0)
		var y: float = inner.position.y + pad + small + big * 1.35
		OsKit.text(self, Vector2(inner.position.x + pad, y), level_name, OsKit.font_bold(), OsKit.px(0.85),
				OsKit.ink(), inner.size.x - pad * 2.0)
		y += OsKit.px(1.1)
		if not note.is_empty():
			OsKit.text(self, Vector2(inner.position.x + pad, y), note, OsKit.font_bold(), small, OsKit.red(),
					inner.size.x - pad * 2.0)
			y += OsKit.px(1.0)
		draw_multiline_string(OsKit.font_regular(), Vector2(inner.position.x + pad, y), hint,
				HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - pad * 2.0, small, maxi(floori((inner.end.y - y) / (small * 1.25)), 0),
				OsKit.soft())


## Comparación de dos expedientes: cabeceras enfrentadas, rasgos en espejo y filas de datos.
## Lo que un expediente no muestra a su nivel aparece tachado («clasificado»).
class CompareView extends Control:
	const HEADER_EM := 9.0
	const ROW_EM := 1.85
	const LABEL_EM := 8.0
	const GAP_EM := 0.6

	var _a: Dictionary = {}
	var _b: Dictionary = {}
	var _link_type: String = ""
	var _link_strength: float = 0.0
	var _rows: Array[Array] = []

	func set_files(a: Dictionary, b: Dictionary, link_type: String, strength: float) -> void:
		_a = a
		_b = b
		_link_type = link_type
		_link_strength = strength
		_rows = [
			["PERS_CMP_TYPE", _value(a, S_CHARACTER_KEY, "archetype_name"), _value(b, S_CHARACTER_KEY, "archetype_name")],
			["PERS_CMP_ATTITUDE", _value(a, S_HISTORY_KEY, "mood_word"), _value(b, S_HISTORY_KEY, "mood_word")],
			["PERS_CMP_DEBT", _value(a, S_HISTORY_KEY, "debt_word"), _value(b, S_HISTORY_KEY, "debt_word")],
			["PERS_CMP_BRIBE", _bribe(a), _bribe(b)],
			["PERS_CMP_WEAKNESS", _plain(a, S_WEAKNESS_KEY), _plain(b, S_WEAKNESS_KEY)],
			["PERS_CMP_HOME", _value(a, S_HOME_KEY, "address"), _value(b, S_HOME_KEY, "address")],
		]
		var rows: int = Validate.TRAIT_NAMES.size() + _rows.size() + 2
		custom_minimum_size.y = OsKit.px(HEADER_EM + 1.5) + OsKit.px(ROW_EM) * rows
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		queue_redraw()

	const S_CHARACTER_KEY := "character"
	const S_HISTORY_KEY := "history"
	const S_WEAKNESS_KEY := "weakness"
	const S_HOME_KEY := "home"
	const S_TRAITS_KEY := "traits"
	const S_LINKS_KEY := "links"
	const S_BRIBE_KEY := "bribe_price"

	static func _value(file: Dictionary, section: String, field: String) -> String:
		var data: Variant = file.get("sections", {}).get(section)
		return str(data.get(field, "")) if data is Dictionary else ""

	static func _plain(file: Dictionary, section: String) -> String:
		var data: Variant = file.get("sections", {}).get(section)
		return str(data) if data is String else ""

	static func _bribe(file: Dictionary) -> String:
		var data: Variant = file.get("sections", {}).get(S_BRIBE_KEY)
		if not data is Dictionary:
			return ""
		if bool(data.get("unbribable", false)):
			return TranslationServer.translate("PERS_BRIBE_UNBRIBABLE")
		var prices: Array = data.get("prices", [])
		return UITheme.format_money(int(prices[0]["price"])) if not prices.is_empty() else ""

	func _draw() -> void:
		var mid: float = size.x * 0.5
		var head_h: float = float(OsKit.px(HEADER_EM))
		var gap: float = float(OsKit.px(2.8))
		_draw_head(_a, Rect2(0, 0, mid - gap, head_h), false)
		_draw_head(_b, Rect2(mid + gap, 0, mid - gap, head_h), true)
		_draw_vs(Vector2(mid, head_h * 0.42))
		var y: float = head_h + OsKit.px(0.8)
		_draw_caption(TranslationServer.translate("PERS_SEC_TRAITS"), y)
		y += OsKit.px(ROW_EM)
		for i: int in Validate.TRAIT_NAMES.size():
			_draw_trait_row(i, y)
			y += OsKit.px(ROW_EM)
		_draw_caption(TranslationServer.translate("PERS_CMP_FACTS"), y)
		y += OsKit.px(ROW_EM)
		for row: Array in _rows:
			_draw_text_row(row, y)
			y += OsKit.px(ROW_EM)

	func _draw_head(file: Dictionary, rect: Rect2, mirrored: bool) -> void:
		var identity: Dictionary = file["sections"]["identity"]
		var photo_w: float = rect.size.y * 0.86
		var photo: Rect2 = Rect2(rect.end.x - photo_w if mirrored else rect.position.x, rect.position.y,
				photo_w, photo_w)
		draw_rect(Rect2(photo.position + Vector2(4, 5), photo.size), Color(0, 0, 0, 0.18))
		draw_rect(photo, Color.WHITE)
		CharacterPainter.draw_portrait(self, identity["photo"], photo.grow(-photo_w * 0.06))
		draw_rect(photo, OsKit.ink(), false, 2.0)
		var pad: float = float(OsKit.px(0.8))
		var text_w: float = rect.size.x - photo_w - pad
		var x: float = rect.position.x if mirrored else photo.end.x + pad
		var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
		if mirrored:
			text_w = photo.position.x - pad - rect.position.x
		var y: float = rect.position.y + OsKit.px(1.6)
		OsKit.text(self, Vector2(x, y), str(identity["name"]), OsKit.font_black(), OsKit.px(1.3), OsKit.ink(),
				text_w, align)
		y += OsKit.px(1.5)
		for field: String in ["post", "floor", "wing"]:
			OsKit.text(self, Vector2(x, y), str(identity[field]), OsKit.font_regular(), OsKit.px(0.88),
					OsKit.soft(), text_w, align)
			y += OsKit.px(1.2)
		var level_text: String = TranslationServer.translate("PERS_CMP_LEVEL") % int(file["level"])
		OsKit.text(self, Vector2(x, y + OsKit.px(0.4)), level_text, OsKit.font_black(), OsKit.px(0.8),
				OsKit.teal(), text_w, align)

	func _draw_vs(center: Vector2) -> void:
		var r: float = float(OsKit.px(1.7))
		draw_circle(center + Vector2(3, 4), r, Color(0, 0, 0, 0.2))
		draw_circle(center, r, OsKit.teal())
		draw_arc(center, r, 0, TAU, 32, OsKit.ink(), 2.5)
		var fsize: int = OsKit.px(1.1)
		OsKit.text(self, Vector2(center.x - r, center.y + fsize * 0.36), TranslationServer.translate("PERS_CMP_VS"), OsKit.font_black(), fsize,
				OsKit.title_ink(), r * 2.0, HORIZONTAL_ALIGNMENT_CENTER)
		var link: String = TranslationServer.translate("PERS_CMP_NO_LINK")
		if not _link_type.is_empty() and (_a["sections"].has(S_LINKS_KEY) or _b["sections"].has(S_LINKS_KEY)):
			link = TranslationServer.translate("LINK_" + _link_type.to_upper())
		elif not _a["sections"].has(S_LINKS_KEY) and not _b["sections"].has(S_LINKS_KEY):
			link = TranslationServer.translate("PERS_CLASSIFIED")
		var w: float = float(OsKit.px(9.0))
		OsKit.text(self, Vector2(center.x - w * 0.5, center.y + r + OsKit.px(1.1)), link, OsKit.font_bold(),
				OsKit.px(0.8), OsKit.ink(), w, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_caption(text: String, y: float) -> void:
		OsKit.text(self, Vector2(0, y + OsKit.px(1.1)), text.to_upper(), OsKit.font_black(), OsKit.px(0.8),
				OsKit.teal(), size.x, HORIZONTAL_ALIGNMENT_CENTER)
		draw_line(Vector2(0, y + OsKit.px(1.5)), Vector2(size.x, y + OsKit.px(1.5)), Color(OsKit.teal(), 0.5), 1.5)

	func _draw_trait_row(i: int, y: float) -> void:
		var label_w: float = float(OsKit.px(LABEL_EM))
		var mid: float = size.x * 0.5
		var trait_label: String = TranslationServer.translate("PERS_TRAIT_" + Validate.TRAIT_NAMES[i].to_upper())
		var fsize: int = OsKit.px(0.88)
		var base: float = y + OsKit.px(ROW_EM) * 0.5 + fsize * 0.36
		OsKit.text(self, Vector2(mid - label_w * 0.5, base), trait_label, OsKit.font_bold(), fsize, OsKit.ink(), label_w,
				HORIZONTAL_ALIGNMENT_CENTER)
		var bar_w: float = mid - label_w * 0.5 - OsKit.px(3.2)
		var h: float = OsKit.px(ROW_EM) * 0.5
		var top: float = y + (OsKit.px(ROW_EM) - h) * 0.5
		_draw_side_bar(_a, i, Rect2(mid - label_w * 0.5 - bar_w, top, bar_w, h), true)
		_draw_side_bar(_b, i, Rect2(mid + label_w * 0.5, top, bar_w, h), false)

	func _draw_side_bar(file: Dictionary, i: int, track: Rect2, grows_left: bool) -> void:
		OsKit.draw_bevel(self, track, OsKit.field(), true)
		var traits: Variant = file["sections"].get(S_TRAITS_KEY)
		var inner: Rect2 = track.grow(-OsKit.BAND)
		if not traits is Array:
			OsKit.draw_hatch(self, inner, Color(OsKit.ink(), 0.55), 7.0, 2.0)
			return
		var row: Dictionary = traits[i]
		var fill_w: float = inner.size.x * clampf(int(row["value"]) / 100.0, 0.0, 1.0)
		var fill_x: float = inner.end.x - fill_w if grows_left else inner.position.x
		draw_rect(Rect2(fill_x, inner.position.y, fill_w, inner.size.y),
				OsKit.red().lerp(OsKit.amber(), 0.2) if grows_left else OsKit.blue())
		var tail: String = str(row["value"]) if bool(row["exact"]) else "~"
		var fsize: int = OsKit.px(0.82)
		var tx: float = track.position.x - OsKit.px(2.6) if grows_left else track.end.x + OsKit.px(0.3)
		OsKit.text(self, Vector2(tx, track.get_center().y + fsize * 0.36), tail, OsKit.font_mono(), fsize,
				OsKit.ink(), OsKit.px(2.3), HORIZONTAL_ALIGNMENT_RIGHT if grows_left else HORIZONTAL_ALIGNMENT_LEFT)

	func _draw_text_row(row: Array, y: float) -> void:
		var label_w: float = float(OsKit.px(LABEL_EM))
		var mid: float = size.x * 0.5
		var fsize: int = OsKit.px(0.88)
		var base: float = y + OsKit.px(ROW_EM) * 0.5 + fsize * 0.36
		OsKit.text(self, Vector2(mid - label_w * 0.5, base), TranslationServer.translate(str(row[0])),
				OsKit.font_bold(), fsize, OsKit.ink(), label_w, HORIZONTAL_ALIGNMENT_CENTER)
		var side_w: float = mid - label_w * 0.5 - OsKit.px(GAP_EM)
		_draw_side_text(str(row[1]), Rect2(0, y, side_w, OsKit.px(ROW_EM)), true, base)
		_draw_side_text(str(row[2]), Rect2(mid + label_w * 0.5 + OsKit.px(GAP_EM), y, side_w, OsKit.px(ROW_EM)),
				false, base)
		draw_line(Vector2(0, y + OsKit.px(ROW_EM) - 1), Vector2(size.x, y + OsKit.px(ROW_EM) - 1),
				Color(OsKit.face_mid(), 0.3), 1.0)

	func _draw_side_text(value: String, rect: Rect2, right_align: bool, base: float) -> void:
		if value.is_empty():
			var w: float = rect.size.x * 0.45
			var x: float = rect.end.x - w if right_align else rect.position.x
			draw_rect(Rect2(x, rect.position.y + rect.size.y * 0.3, w, rect.size.y * 0.4), OsKit.ink())
			return
		OsKit.text(self, Vector2(rect.position.x, base), value, OsKit.font_regular(), OsKit.px(0.88), OsKit.ink(),
				rect.size.x, HORIZONTAL_ALIGNMENT_RIGHT if right_align else HORIZONTAL_ALIGNMENT_LEFT)
