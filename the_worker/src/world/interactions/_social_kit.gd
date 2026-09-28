# _social_kit.gd — Utilidades compartidas del módulo social (social.gd): balance social.*, marcas por jornada en PlayerState, nombres, avisos con sonido y resultados de acción.
# PROPIETARIO DE: nada (estático; lo que se recuerda vive en PlayerState como banderas "social.*").
# ESCUCHA: nada.
class_name SocialKit
extends RefCounted

## Archivo privado ("_"): el InteractionRouter no lo trata como módulo.
## RESULTADO de una acción social (lo que el menú enseña, SocialRules.perform lo devuelve):
##   {ok: bool, lines: [[clave, args], ...] (réplica del personaje, en orden), toast_key,
##    toast_args, toast_kind, more_toasts ([[clave, args, tipo]], opcional), sfx, close (el menú
##    se cierra), refresh (las opciones cambian)}.
## Marcas «una vez por jornada / cada N jornadas»: bandera social.<tipo> = {npc_id: jornada}.

const B := "social."
const FLAG := "social."
const NO_DAY := -1000000
const PLAYER_ID := "player"
const NOTE_PERSONNEL := "personnel"
const NOTE_BLACKMAIL := "blackmail"
const SFX_OK := "ui_confirm"
const SFX_ERROR := "ui_error"
const SFX_INFO := "ui_notify"
const SFX_CASH := "cash"
const SFX_CHAT := "chatter"

## QA y pruebas: los actos sociales (eliminar) duran un fotograma y la escena no espera.
static var qa_instant: bool = false


# ─── Balance ──────────────────────────────────────────────────

static func bf(path: String) -> float:
	return Database.get_balance_float(B + path)


static func bi(path: String) -> int:
	return Database.get_balance_int(B + path)


static func bs(path: String) -> String:
	return str(Database.get_balance(B + path))


static func barr(path: String) -> Array:
	var value: Variant = Database.get_balance(B + path)
	return value if value is Array else []


static func bdict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(B + path)
	return value if value is Dictionary else {}


# ─── Marcas por jornada (PlayerState, se guardan) ─────────────

static func last_day(kind: String, npc_id: String) -> int:
	var marks: Variant = PlayerState.get_flag(FLAG + kind, {})
	return int((marks as Dictionary).get(npc_id, NO_DAY)) if marks is Dictionary else NO_DAY


static func mark(kind: String, npc_id: String) -> void:
	var marks: Variant = PlayerState.get_flag(FLAG + kind, {})
	var copy: Dictionary = (marks as Dictionary).duplicate() if marks is Dictionary else {}
	copy[npc_id] = GameClock.get_day()
	PlayerState.set_flag(FLAG + kind, copy)


static func done_today(kind: String, npc_id: String) -> bool:
	return last_day(kind, npc_id) == GameClock.get_day()


## Jornadas que faltan para poder repetirlo (0 = ya se puede).
static func cooldown_left(kind: String, npc_id: String, days: int) -> int:
	return maxi(last_day(kind, npc_id) + days - GameClock.get_day(), 0)


static func counter(key: String) -> int:
	return int(PlayerState.get_flag(FLAG + key, 0))


static func set_counter(key: String, value: int) -> void:
	PlayerState.set_flag(FLAG + key, value)


# ─── Nombres ──────────────────────────────────────────────────

static func npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null
	return npc.name if npc != null else TranslationServer.translate("SOCIAL_SOMEONE")


static func room_name(room_id: String) -> String:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id)) if not room_id.is_empty() else null
	return TranslationServer.translate(room.name_key) if room != null else TranslationServer.translate("SOCIAL_NOWHERE")


static func item_name(item_id: String) -> String:
	var item: ItemData = Database.get_item(item_id)
	return TranslationServer.translate(item.name_key) if item != null else item_id


## Planta de una sala (las transversales llevan "@planta").
static func floor_of_room(room_id: String) -> int:
	if room_id.contains("@"):
		return int(room_id.get_slice("@", 1))
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id))
	return room.floor if room != null else PlayerState.get_floor()


static func place_text(room_id: String) -> String:
	if room_id.is_empty():
		return TranslationServer.translate("SOCIAL_OUTSIDE")
	return UITheme.trf("SOCIAL_PLACE_FMT", [room_name(room_id), MapView.floor_label_short(floor_of_room(room_id))])


# ─── Resultados y avisos ──────────────────────────────────────

static func result(ok: bool, line_key: String, line_args: Array = [], toast_key: String = "",
		toast_args: Array = [], kind: String = ToastStack.KIND_INFO) -> Dictionary:
	var lines: Array = [[line_key, line_args]] if not line_key.is_empty() else []
	return {"ok": ok, "lines": lines, "toast_key": toast_key, "toast_args": toast_args,
			"toast_kind": kind, "sfx": SFX_OK if ok else SFX_ERROR, "close": false, "refresh": ok}


## Aviso adicional: el primero va en toast_key; los siguientes, en more_toasts (el menú los enseña todos).
static func add_toast(res: Dictionary, key: String, args: Array = [], kind: String = ToastStack.KIND_INFO) -> void:
	if str(res.get("toast_key", "")).is_empty():
		res["toast_key"] = key
		res["toast_args"] = args
		res["toast_kind"] = kind
		return
	if not res.has("more_toasts"):
		res["more_toasts"] = []
	(res["more_toasts"] as Array).append([key, args, kind])


static func add_line(res: Dictionary, key: String, args: Array = []) -> void:
	if not key.is_empty():
		(res["lines"] as Array).append([key, args])


## Texto de la réplica (líneas traducidas, una por renglón).
static func lines_text(res: Dictionary) -> String:
	var parts: PackedStringArray = []
	for entry: Variant in res.get("lines", []):
		var pair: Array = entry
		parts.append(UITheme.trf(str(pair[0]), pair[1] as Array))
	return "\n".join(parts)


## Rechazo sin efectos: solo la réplica (y el pitido de error).
static func refusal(line_key: String, line_args: Array = []) -> Dictionary:
	return result(false, line_key, line_args)


static func note(category: String, text_key: String, args: Array = []) -> void:
	EventBus.notebook_entry_added.emit(category, text_key, args)


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func sfx(id: String, pos: Vector2 = Vector2.INF) -> void:
	var audio: AudioDirector = AudioDirector.find(tree())
	if audio == null or id.is_empty():
		return
	if pos.is_finite():
		audio.play_sfx(id, pos)
	else:
		audio.play_sfx(id)


static func toast(key: String, args: Array = [], kind: String = ToastStack.KIND_INFO) -> void:
	var ui: UIRoot = UIRoot.find(tree())
	if ui != null and not key.is_empty():
		ui.toast(key, args, kind)


## Minutos de reloj de una conversación o gestión (nunca con el reloj parado por otro).
static func spend_minutes(minutes: int) -> void:
	if minutes > 0:
		GameClock.advance_minutes(float(minutes))
