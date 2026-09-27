# player_records.gd — Memoria externa del jugador (§13.3-§13.5): notas, bloc, registro del cuaderno, contactos, objetivos marcados, expedientes concedidos, estudios y banderas de misión.
# PROPIETARIO DE: nada global: es un contenedor de datos que PlayerState crea, guarda y consulta (BUILD_NOTES §12: el estado vive en el autoload dueño).
# ESCUCHA: nada (PlayerState le pasa los sucesos; este módulo no emite señales).
class_name PlayerRecords
extends RefCounted

## Todo lo que la interfaz necesita recordar entre sesiones y no puede guardar ella misma
## (BUILD_NOTES §10: la UI no tiene estado persistente oculto). Contrato de datos:
##   nota      {id: int, day, hour, minute, text, npc_id ("" = libre)}
##   entrada   {category, text_key, args: Array, day, hour, minute}   (notebook_entry_added)
##   contacto  {npc_id, source, day}   source ∈ SOURCES
## Sellos de tiempo {day, hour, minute}: los pasa PlayerState (GameClock). Topes: los pasa quien
## llama (balance). Sin aleatoriedad. to_dict()/from_dict() toleran el JSON (int llegan como float).

const SOURCE_PROXIMITY := "proximity"
const SOURCE_FAVOUR := "favour"
const SOURCE_HR := "hr"
const SOURCE_PURCHASE := "purchase"
const SOURCE_MESSAGED := "messaged"
## §13.5: «se obtienen trabajando en proximidad, mediante favores, desde RRHH o por compra»; más
## quien te escribe primero (chantaje, mensajes).
const SOURCES: Array[String] = [
	SOURCE_PROXIMITY, SOURCE_FAVOUR, SOURCE_HR, SOURCE_PURCHASE, SOURCE_MESSAGED,
]
## Sinónimos aceptados en add_contact (nombres de la pestaña CONTACTOS del móvil).
const SOURCE_ALIASES: Dictionary = {"colleague": SOURCE_PROXIMITY, "bought": SOURCE_PURCHASE}

const K_ID := "id"
const K_DAY := "day"
const K_HOUR := "hour"
const K_MINUTE := "minute"
const K_TEXT := "text"
const K_NPC := "npc_id"
const K_CATEGORY := "category"
const K_TEXT_KEY := "text_key"
const K_ARGS := "args"
const K_SOURCE := "source"
const STAMP_KEYS: Array[String] = [K_DAY, K_HOUR, K_MINUTE]
const NO_NOTE := -1
const FIRST_NOTE_ID := 1
const NOTE_INT_KEYS: Array[String] = [K_ID]
const NO_KEYS: Array[String] = []

const S_NOTES := "notes"
const S_NEXT_NOTE := "next_note_id"
const S_NOTEPAD := "notepad"
const S_LOG := "notebook_log"
const S_CONTACTS := "contacts"
const S_PROXIMITY := "proximity_hours"
const S_TARGETS := "marked_targets"
const S_FULL_FILES := "full_files"
const S_STUDIES := "studies"
const S_FLAGS := "flags"

var notes: Array[Dictionary] = []
var next_note_id: int = FIRST_NOTE_ID
var notepad: String = ""
var log_entries: Array[Dictionary] = []
## npc_id → {source, day}; el orden de inserción es el de adquisición.
var contacts: Dictionary = {}
## npc_id → horas de trabajo compartidas en la misma sala (vía proximidad).
var proximity_hours: Dictionary = {}
var targets: Array[String] = []
## npc_id → motivo del expediente completo anticipado (§13.4: "hr_intrusion"...).
var full_files: Dictionary = {}
## npc_id → {acción: resultado del estudio (§13.4)}.
var studies: Dictionary = {}
## Banderas de misión y del final (clave → valor serializable).
var flags: Dictionary = {}


func clear() -> void:
	notes.clear()
	next_note_id = FIRST_NOTE_ID
	notepad = ""
	log_entries.clear()
	contacts.clear()
	proximity_hours.clear()
	targets.clear()
	full_files.clear()
	studies.clear()
	flags.clear()


# ─── Notas ─────────────────────────────────────────────────────

## Devuelve el id de la nota o NO_NOTE si el texto queda vacío. `max_chars` recorta; con
## `max_notes` > 0 se descarta la más antigua al superarlo.
func add_note(text: String, npc_id: String, stamp: Dictionary, max_chars: int,
		max_notes: int) -> int:
	var clean: String = text.strip_edges()
	if max_chars > 0:
		clean = clean.left(max_chars)
	if clean.is_empty():
		return NO_NOTE
	var note: Dictionary = _stamped(stamp)
	note.merge({K_ID: next_note_id, K_TEXT: clean, K_NPC: npc_id})
	next_note_id += 1
	notes.append(note)
	while max_notes > 0 and notes.size() > max_notes:
		notes.remove_at(0)
	return int(note[K_ID])


func remove_note(note_id: int) -> bool:
	for index: int in notes.size():
		if int(notes[index][K_ID]) == note_id:
			notes.remove_at(index)
			return true
	return false


## Copias; con `npc_id` solo las vinculadas a ese personaje.
func get_notes(npc_id: String = "", only_npc: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for note: Dictionary in notes:
		if not only_npc or str(note[K_NPC]) == npc_id:
			out.append(note.duplicate(true))
	return out


# ─── Registro automático del cuaderno ──────────────────────────

## Apunta una entrada. Una entrada idéntica a la anterior en el mismo minuto de juego no se repite
## (dos emisores del mismo hecho). `cap` > 0 conserva solo las últimas. false si se descartó.
func log_entry(category: String, text_key: String, args: Array, stamp: Dictionary,
		cap: int) -> bool:
	var entry: Dictionary = _stamped(stamp)
	entry.merge({K_CATEGORY: category, K_TEXT_KEY: text_key, K_ARGS: args.duplicate(true)})
	if not log_entries.is_empty() and log_entries.back() == entry:
		return false
	log_entries.append(entry)
	while cap > 0 and log_entries.size() > cap:
		log_entries.remove_at(0)
	return true


func get_log() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in log_entries:
		out.append(entry.duplicate(true))
	return out


# ─── Contactos (§13.5) ─────────────────────────────────────────

## Fuente canónica ("" si no es válida).
static func canonical_source(source: String) -> String:
	var canonical: String = str(SOURCE_ALIASES.get(source, source))
	return canonical if SOURCES.has(canonical) else ""


## false si ya era contacto (conserva la primera fuente) o si la fuente no es válida.
func add_contact(npc_id: String, source: String, day: int) -> bool:
	var canonical: String = canonical_source(source)
	if npc_id.is_empty() or canonical.is_empty() or contacts.has(npc_id):
		return false
	contacts[npc_id] = {K_SOURCE: canonical, K_DAY: day}
	return true


func has_contact(npc_id: String) -> bool:
	return contacts.has(npc_id)


## [{npc_id, source, day}] en orden de adquisición.
func get_contacts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc_id: Variant in contacts:
		var entry: Dictionary = contacts[npc_id]
		out.append({K_NPC: str(npc_id), K_SOURCE: entry[K_SOURCE], K_DAY: entry[K_DAY]})
	return out


## Suma una hora compartida y devuelve el total.
func add_proximity_hour(npc_id: String) -> int:
	proximity_hours[npc_id] = int(proximity_hours.get(npc_id, 0)) + 1
	return int(proximity_hours[npc_id])


# ─── Objetivos, expedientes y estudios (§13.4) ─────────────────

func mark(npc_id: String) -> bool:
	if npc_id.is_empty() or targets.has(npc_id):
		return false
	targets.append(npc_id)
	return true


func unmark(npc_id: String) -> bool:
	if not targets.has(npc_id):
		return false
	targets.erase(npc_id)
	return true


func grant_full_file(npc_id: String, reason: String) -> bool:
	if npc_id.is_empty() or reason.is_empty() or full_files.has(npc_id):
		return false
	full_files[npc_id] = reason
	return true


func record_study(npc_id: String, action: String, result: Dictionary) -> void:
	if npc_id.is_empty() or action.is_empty():
		return
	if not studies.has(npc_id):
		studies[npc_id] = {}
	(studies[npc_id] as Dictionary)[action] = result.duplicate(true)


# ─── Persistencia ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		S_NOTES: get_notes(), S_NEXT_NOTE: next_note_id, S_NOTEPAD: notepad, S_LOG: get_log(),
		S_CONTACTS: contacts.duplicate(true), S_PROXIMITY: proximity_hours.duplicate(),
		S_TARGETS: targets.duplicate(), S_FULL_FILES: full_files.duplicate(),
		S_STUDIES: studies.duplicate(true), S_FLAGS: flags.duplicate(true),
	}


static func from_dict(data: Dictionary) -> PlayerRecords:
	var out: PlayerRecords = PlayerRecords.new()
	out.notes = _stamped_list(data.get(S_NOTES, []), NOTE_INT_KEYS)
	out.next_note_id = maxi(int(data.get(S_NEXT_NOTE, FIRST_NOTE_ID)), _max_note_id(out.notes) + 1)
	out.notepad = str(data.get(S_NOTEPAD, ""))
	out.log_entries = _stamped_list(data.get(S_LOG, []), NO_KEYS)
	out.contacts = _contact_map(data.get(S_CONTACTS, {}))
	out.proximity_hours = _int_map(data.get(S_PROXIMITY, {}))
	for npc_id: Variant in data.get(S_TARGETS, []):
		out.mark(str(npc_id))
	var files: Variant = data.get(S_FULL_FILES, {})
	if files is Dictionary:
		for npc_id: Variant in files:
			out.full_files[str(npc_id)] = str(files[npc_id])
	out.studies = _dict_of(data.get(S_STUDIES, {}))
	out.flags = _dict_of(data.get(S_FLAGS, {}))
	return out


# ─── Interno ───────────────────────────────────────────────────

static func _stamped(stamp: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in STAMP_KEYS:
		out[key] = int(stamp.get(key, 0))
	return out


static func _stamped_list(raw: Variant, extra_int_keys: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	for record: Variant in raw:
		if not record is Dictionary:
			continue
		var entry: Dictionary = (record as Dictionary).duplicate(true)
		for key: String in STAMP_KEYS + extra_int_keys:
			entry[key] = int(entry.get(key, 0))
		out.append(entry)
	return out


static func _max_note_id(list: Array[Dictionary]) -> int:
	var best: int = 0
	for note: Dictionary in list:
		best = maxi(best, int(note.get(K_ID, 0)))
	return best


static func _contact_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for npc_id: Variant in raw:
			var entry: Dictionary = raw[npc_id] if raw[npc_id] is Dictionary else {}
			var source: String = canonical_source(str(entry.get(K_SOURCE, "")))
			if not source.is_empty():
				out[str(npc_id)] = {K_SOURCE: source, K_DAY: int(entry.get(K_DAY, 0))}
	return out


static func _int_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			out[str(key)] = int(raw[key])
	return out


static func _dict_of(raw: Variant) -> Dictionary:
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
