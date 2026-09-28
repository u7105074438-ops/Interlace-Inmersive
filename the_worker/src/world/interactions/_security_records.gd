# _security_records.gd — Registros del edificio (§5.5, §22.2, §12.4): consolas de monitores (ver y BORRAR grabaciones), terminales de servidor (ver y borrar rastros digitales) y cintas de copia de seguridad (sin destruirlas, lo borrado vuelve).
# PROPIETARIO DE: nada (las grabaciones son de Security, los registros de BeliefNet; la cola de restauración y el día de las cintas destruidas, banderas secops.* de PlayerState).
# ESCUCHA: nada (SecurityKeeper llama a restore_due() al cambiar de jornada).
class_name SecurityRecords
extends RefCounted

## DECISIONES:
##  · monitor_console: todas las consolas ENSEÑAN las grabaciones vigentes (Security.get_footage_list:
##    todas son del jugador, a cara descubierta o de uniforme). Solo en la sala de monitores
##    (seguridad.sala_monitores, §5.5) se borran: Security.delete_footage (registro destruido, delito
##    footage_deleted). Borrar es un acto visible (footage_deleted) y la sala tiene dos vigilantes:
##    si alguien mira, se avisa antes.
##  · server_terminal: mode "view_logs" (oficina de sistemas) solo lee; el de la sala de servidores
##    borra los registros DIGITALES de BeliefNet sobre el jugador (operativa.servidor.tipos_digitales:
##    card_log, chat_log) con crime_committed("records_deleted", sala, {record_ids}): BeliefNet los
##    destruye y deja en el propio servidor el registro de ese acceso (§22.2).
##  · backup_unit (modelo mínimo decidido): cada borrado del servidor queda en la cola de
##    restauración (banderas). Al cambiar de jornada la copia nocturna RESTAURA lo borrado
##    (BeliefNet.create_record; los registros neutros —lecturas rutinarias— no se restauran porque no
##    pesaban) salvo que antes se destruyan las cintas: destruirlas vacía la cola (los borrados quedan
##    firmes) y deja rastro (records_deleted en backup_room → registro de acceso). Las cintas nuevas
##    empiezan esa noche: un borrado posterior vuelve a estar en la cola.

const TYPES: Array[String] = ["monitor_console", "server_terminal", "backup_unit"]
const T_MONITOR := "monitor_console"
const T_SERVER := "server_terminal"
const T_BACKUP := "backup_unit"
const MODE_VIEW := "view_logs"
const CRIME_FOOTAGE := "footage_deleted"
const CRIME_RECORDS := "records_deleted"
const ACT_WRECK := "sabotage"
const METHOD_SERVER := "server_terminal"
const METHOD_BACKUPS := "backups_destroyed"
const F_QUEUE := "restore_queue"
const F_BACKUPS_DAY := "backups_day"
const B_MONITOR_ROOM := "seguridad.sala_monitores"
const OPT_REVIEW := 0
const OPT_WIPE := 1
const HOURS_PER_DAY := 24


static func handles(interact_type: String) -> bool:
	return TYPES.has(interact_type)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_MONITOR:
			await use_monitor(item, player, ctx)
		T_SERVER:
			await use_server(item, player, ctx)
		T_BACKUP:
			await use_backups(item, player, ctx)


static func prompt_key(item: Interactable) -> String:
	if item.interact_type == T_MONITOR and not in_monitor_room(item.room_id):
		return "SECOPS_PROMPT_VIEW_FOOTAGE"
	if item.interact_type == T_SERVER and is_view_only(item):
		return "SECOPS_PROMPT_VIEW_LOGS"
	return ""


# ─── Consola de monitores ─────────────────────────────────────

static func in_monitor_room(room_id: String) -> bool:
	return SecurityKit.base_room(room_id) == str(Database.get_balance(B_MONITOR_ROOM))


## Grabaciones vigentes, de la más reciente a la más antigua.
static func footage_sorted() -> Array[Dictionary]:
	var list: Array[Dictionary] = Security.get_footage_list()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["day"]) * HOURS_PER_DAY + int(a["hour"]) > int(b["day"]) * HOURS_PER_DAY + int(b["hour"]))
	return list


static func footage_label(entry: Dictionary) -> String:
	var subject: String = str(entry.get("subject", SecurityKit.PLAYER_ID))
	var who: String = TranslationServer.translate("SECOPS_WHO_YOU")
	if subject.begins_with(SecurityKit.UNIFORM_PREFIX):
		who = UITheme.trf("SECOPS_WHO_UNIFORM", [SecurityKit.item_name(subject.trim_prefix(SecurityKit.UNIFORM_PREFIX))])
	return UITheme.trf("SECOPS_FOOTAGE_LINE", [int(entry["day"]), UITheme.format_hour(int(entry["hour"])),
			SecurityKit.room_name(str(entry["room_id"])), who])


static func use_monitor(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var list: Array[Dictionary] = footage_sorted()
	var here: bool = in_monitor_room(item.room_id)
	var options: Array = [{"text_key": "SECOPS_MONITOR_REVIEW", "icon": "eye"},
			{"text_key": "SECOPS_MONITOR_WIPE", "args": [list.size()], "danger": true,
			"disabled": not here or list.is_empty()}, "UI_CANCEL"]
	var body: String = "SECOPS_MONITOR_BODY" if here else "SECOPS_MONITOR_BODY_VIEW"
	var choice: int = await SecurityKit.choose(ctx, "SECOPS_MONITOR_TITLE", body, options, [list.size()])
	if choice == OPT_REVIEW:
		await _review_footage(item, player, ctx, list, here)
	elif choice == OPT_WIPE:
		await wipe_footage(player, ctx, _ids_of(list))


static func _review_footage(item: Interactable, player: Node, ctx: Dictionary, list: Array[Dictionary], here: bool) -> void:
	if list.is_empty():
		SecurityKit.toast(ctx, "SECOPS_MONITOR_EMPTY", [], ToastStack.KIND_GOOD)
		return
	var labels: Array[String] = []
	for entry: Dictionary in list.slice(0, SecurityKit.bi("monitores.lista_max")):
		labels.append(footage_label(entry))
	var hint: String = TranslationServer.translate("SECOPS_MONITOR_LIST_HINT" if here else "SECOPS_MONITOR_LIST_VIEW")
	var index: int = await SecurityKit.pick(ctx, SecurityKit.room_name(item.room_id), hint, labels)
	if index < 0:
		return
	if not here:
		SecurityKit.toast(ctx, "SECOPS_MONITOR_WRONG_ROOM", [], ToastStack.KIND_WARN)
		return
	await wipe_footage(player, ctx, [str(list[index]["id"])])


## Borra grabaciones desde la sala de monitores (acto visible). Devuelve cuántas se borraron.
static func wipe_footage(player: Node, ctx: Dictionary, ids: Array[String]) -> int:
	if not in_monitor_room(PlayerState.get_room()):
		SecurityKit.toast(ctx, "SECOPS_MONITOR_WRONG_ROOM", [], ToastStack.KIND_WARN)
		return 0
	if ids.is_empty() or not await SecurityKit.watched_ok(ctx, player):
		return 0
	if not await SecurityKit.confirm(ctx, "SECOPS_MONITOR_CONFIRM_TITLE", "SECOPS_MONITOR_CONFIRM_BODY",
			"SECOPS_MONITOR_CONFIRM", [ids.size()]):
		return 0
	var seconds: float = minf(SecurityKit.bf("monitores.segundos_base") + SecurityKit.bf("monitores.segundos_por_grabacion") * ids.size(),
			SecurityKit.bf("monitores.segundos_max"))
	if not await SecurityKit.act(player, CRIME_FOOTAGE, seconds):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return 0
	var erased: int = 0
	for id: String in ids:
		if Security.delete_footage(id):
			erased += 1
	GameClock.advance_minutes(SecurityKit.bf("monitores.minutos"))
	SecurityKit.toast(ctx, "SECOPS_MONITOR_WIPED", [erased], ToastStack.KIND_GOOD)
	SecurityKit.sfx(player, "ui_confirm")
	return erased


static func _ids_of(list: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in list:
		out.append(str(entry["id"]))
	return out


# ─── Terminal del servidor ────────────────────────────────────

static func is_view_only(item: Interactable) -> bool:
	return str(item.data.get("mode", "")) == MODE_VIEW


## Registros digitales de BeliefNet sobre el jugador (tarjetas, archivos copiados, chats).
static func digital_traces() -> Array[Belief]:
	var kinds: Array = SecurityKit.barr("servidor.tipos_digitales")
	var out: Array[Belief] = []
	for b: Belief in BeliefNet.get_records_about(SecurityKit.PLAYER_ID):
		if kinds.has(b.record_type):
			out.append(b)
	out.sort_custom(func(a: Belief, c: Belief) -> bool: return a.timestamp > c.timestamp)
	return out


static func trace_label(b: Belief) -> String:
	var kind: String = TranslationServer.translate("SECOPS_TRACE_" + b.record_type.to_upper())
	return UITheme.trf("SECOPS_TRACE_LINE", [b.timestamp, kind, SecurityKit.room_name(b.location)])


static func use_server(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var traces: Array[Belief] = digital_traces()
	if is_view_only(item):
		await _view_logs(ctx, traces)
		return
	var options: Array = [{"text_key": "SECOPS_SERVER_REVIEW", "icon": "eye"},
			{"text_key": "SECOPS_SERVER_WIPE", "args": [traces.size()], "danger": true, "disabled": traces.is_empty()},
			"UI_CANCEL"]
	var choice: int = await SecurityKit.choose(ctx, "SECOPS_SERVER_TITLE", "SECOPS_SERVER_BODY", options, [traces.size()])
	if choice == OPT_WIPE:
		await wipe_traces(item, player, ctx, traces)
	elif choice == OPT_REVIEW and traces.is_empty():
		SecurityKit.toast(ctx, "SECOPS_SERVER_CLEAN", [], ToastStack.KIND_GOOD)
	elif choice == OPT_REVIEW:
		var labels: Array[String] = []
		for b: Belief in traces.slice(0, SecurityKit.bi("servidor.lista_max")):
			labels.append(trace_label(b))
		var index: int = await SecurityKit.pick(ctx, TranslationServer.translate("SECOPS_SERVER_TITLE"),
				TranslationServer.translate("SECOPS_SERVER_LIST_HINT"), labels)
		if index >= 0:
			await wipe_traces(item, player, ctx, [traces[index]])


static func _view_logs(ctx: Dictionary, traces: Array[Belief]) -> void:
	var cards: int = 0
	for b: Belief in traces:
		if b.record_type == BeliefNetSystem.RECORD_CARD_LOG:
			cards += 1
	var duty: DutySystem = SecurityKit.tree_of(null).get_first_node_in_group(DutySystem.GROUP) as DutySystem
	var assists: int = duty.get_assist_count() if duty != null else 0
	await SecurityKit.choose(ctx, "SECOPS_SERVER_VIEW_TITLE", "SECOPS_SERVER_VIEW_BODY", ["SECOPS_CLOSE"],
			[cards, traces.size() - cards, assists])


## Borra rastros digitales desde la sala de servidores. Devuelve cuántos se destruyeron.
static func wipe_traces(item: Interactable, player: Node, ctx: Dictionary, traces: Array[Belief]) -> int:
	if traces.is_empty() or not await SecurityKit.watched_ok(ctx, player):
		return 0
	if not await SecurityKit.confirm(ctx, "SECOPS_SERVER_CONFIRM_TITLE", "SECOPS_SERVER_CONFIRM_BODY",
			"SECOPS_SERVER_CONFIRM", [traces.size()]):
		return 0
	var seconds: float = minf(SecurityKit.bf("servidor.segundos_base") + SecurityKit.bf("servidor.segundos_por_registro") * traces.size(),
			SecurityKit.bf("servidor.segundos_max"))
	if not await SecurityKit.act(player, CRIME_RECORDS, seconds):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return 0
	var destroyed: int = delete_traces(traces, SecurityKit.base_room(item.room_id))
	GameClock.advance_minutes(SecurityKit.bf("servidor.minutos"))
	SecurityKit.toast(ctx, "SECOPS_SERVER_WIPED", [destroyed], ToastStack.KIND_GOOD)
	SecurityKit.sfx(player, "ui_confirm")
	return destroyed


## Destruye los registros (records_deleted) y los apunta en la cola de restauración.
static func delete_traces(traces: Array[Belief], room_id: String) -> int:
	var ids: Array[String] = []
	var queue: Array = SecurityKit.flag_array(F_QUEUE)
	for b: Belief in traces:
		ids.append(b.id)
		queue.append({"record_type": b.record_type, "subject": b.subject, "weight": b.weight,
				"location": b.location, "neutral": BeliefNet.is_record_neutral(b.id), "day": SecurityKit.today()})
	SecurityKit.set_flag(F_QUEUE, queue)
	EventBus.crime_committed.emit(CRIME_RECORDS, room_id, {"record_ids": ids, "method": METHOD_SERVER})
	var destroyed: int = 0
	for id: String in ids:
		if BeliefNet.get_belief(id) == null:
			destroyed += 1
	return destroyed


# ─── Copias de seguridad ──────────────────────────────────────

static func restore_queue() -> Array:
	return SecurityKit.flag_array(F_QUEUE)


static func backups_destroyed_today() -> bool:
	return int(SecurityKit.flag(F_BACKUPS_DAY, -1)) == SecurityKit.today()


static func use_backups(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var pending: int = restore_queue().size()
	var wrecked: bool = backups_destroyed_today()
	var body: String = "SECOPS_BACKUP_BODY_WRECKED" if wrecked else \
			("SECOPS_BACKUP_BODY_PENDING" if pending > 0 else "SECOPS_BACKUP_BODY_CLEAN")
	var options: Array = [{"text_key": "SECOPS_BACKUP_DESTROY", "danger": true, "disabled": wrecked}, "UI_CANCEL"]
	if await SecurityKit.choose(ctx, "SECOPS_BACKUP_TITLE", body, options, [pending]) == 0:
		await destroy_backups(item, player, ctx)


static func destroy_backups(item: Interactable, player: Node, ctx: Dictionary) -> bool:
	if not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.confirm(ctx, "SECOPS_BACKUP_TITLE", "SECOPS_BACKUP_CONFIRM_BODY", "SECOPS_BACKUP_CONFIRM"):
		return false
	if not await SecurityKit.act(player, ACT_WRECK, SecurityKit.bf("copias.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	var kept: int = wreck_backups(SecurityKit.base_room(item.room_id))
	GameClock.advance_minutes(SecurityKit.bf("copias.minutos"))
	SecurityKit.toast(ctx, "SECOPS_BACKUP_DESTROYED", [kept], ToastStack.KIND_GOOD)
	SecurityKit.sfx(player, "break_object")
	return true


## Cintas destruidas: los borrados pendientes quedan firmes (devuelve cuántos) y queda rastro.
static func wreck_backups(room_id: String) -> int:
	var kept: int = restore_queue().size()
	SecurityKit.set_flag(F_QUEUE, [])
	SecurityKit.set_flag(F_BACKUPS_DAY, SecurityKit.today())
	EventBus.crime_committed.emit(CRIME_RECORDS, room_id, {"method": METHOD_BACKUPS})
	return kept


## Copia nocturna: restaura los borrados de jornadas anteriores que siguen en la cola. Devuelve
## cuántos registros vuelven (los neutros no se restauran: no pesaban).
static func restore_due() -> int:
	var queue: Array = restore_queue()
	var still: Array = []
	var restored: int = 0
	for entry: Variant in queue:
		var e: Dictionary = entry as Dictionary
		if int(e.get("day", 0)) >= SecurityKit.today():
			still.append(e)
		elif not bool(e.get("neutral", false)):
			BeliefNet.create_record(str(e["record_type"]), str(e["subject"]), float(e["weight"]), str(e["location"]))
			restored += 1
	if still.size() != queue.size():
		SecurityKit.set_flag(F_QUEUE, still)
	return restored
