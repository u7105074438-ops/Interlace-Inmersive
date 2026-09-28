# _security_locks.gd — Cerraduras y cajas (§5.3, §11.8, §22.2, §22.11): candados antiguos (llave o forzar), lectores con tarjeta robada o clonada, cajas fuertes de oficina y de vivienda, la caja del consejero delegado y el banco de reparación (clonar tarjetas, accesos a ordenadores ajenos).
# PROPIETARIO DE: nada (las puertas son de FloorStreamer, los registros de Security, los documentos de Endgame; el contenido restante de cada caja y los candados vaciados son banderas secops.* de PlayerState).
# ESCUCHA: nada.
class_name SecurityLocks
extends RefCounted

## DECISIONES:
##  · lock_old (data: door_id que pone RoomBuilder, target, keys_basic_opens, forcible,
##    force_noise_radius, contains): con keys_basic (si keys_basic_opens) o una llave maestra
##    (operativa.cerraduras.llaves_maestras; no abren candados con keys_basic_opens = false) se abre
##    sin delito (gesto legítimo). Sin llave, con herramienta (operativa.cerraduras.herramientas) y
##    forcible (por defecto true): confirmación (avisa si la alarma nocturna de la planta está armada),
##    acto "lock_forced" con ruido (force_noise_radius o ruido.radio_forzar_cerradura, cada
##    intervalo_ruido s), crime_committed("lock_forced", sala, {target, tool}). Una puerta abierta
##    queda sin bloqueo hasta recargar la planta; un armario da su contenido.
##  · door_reader (puntos que crea SecurityKeeper): solo si la acreditación propia no abre y se lleva
##    una tarjeta ajena. La tarjeta (ItemData.extra.owner = personaje; si falta, extra.clearance y
##    extra.special_access) abre si su titular abriría. Robada: el registro lleva el NOMBRE DEL
##    TITULAR (Security.log_card_access, §5.3). Clonada: sin rastro inmediato.
##  · safe / floor_safe: requires key | combination | clearance (min_clearance). Métodos silenciosos
##    y de fuerza por requisito en operativa.cajas.metodos.<requires>. Abrir = acto visible
##    "theft_small"; forzar = acto "lock_forced" ruidoso + delito lock_forced (+ alarma si armada).
##    Toda apertura sin ruido se confirma (§13.7). logs_opening → registro de apertura ANÓNIMO
##    (titular operativa.cajas.titular_registro: una hora, no una identidad; con acreditación propia
##    lleva el nombre del jugador). El efectivo (kind "cash") no va al bolsillo como objeto: se abona
##    con PlayerState.add_money (value, o operativa.cajas.efectivo_sobre si vale 0). Botín:
##    contains al inventario (lo que no cabe se queda; la caja se repone en operativa.cajas.
##    dias_reposicion jornadas) y crime_committed("theft_small", sala, {value, items, company_loss}).
##    En una vivienda (NightOps.get_house_type) la caja es un contenedor de la operación nocturna:
##    NightOps.loot_container.
##  · ceo_safe: Endgame.open_safe() con la combinación (confirmada); si no, Endgame.work_on_safe() por tramos
##    (operativa.cajas.minutos_tramo_ceo) con los medios físicos; si no, se explica qué falta.
##  · repair_bench: clonar una tarjeta robada (acto "forgery" sin registro; +silk en Tracking) y, solo
##    puestos con acceso operativa.banco.acceso_intrusion (IT), abrir el ordenador de un objetivo
##    marcado en PERSONNEL (StellarOS.open_intrusion). «Todo acceso queda registrado»: log del banco.

const TYPES: Array[String] = ["lock_old", "door_reader", "safe", "floor_safe", "ceo_safe", "repair_bench"]
const T_LOCK := "lock_old"
const T_READER := "door_reader"
const T_SAFE := "safe"
const T_FLOOR_SAFE := "floor_safe"
const T_CEO := "ceo_safe"
const T_BENCH := "repair_bench"
const CRIME_FORCED := "lock_forced"
const CRIME_THEFT := "theft_small"
const CRIME_FORGERY := "forgery"
const CRIME_BURGLARY := "burglary"
const NOISE_FORCE := "lock_forced"
const TARGET_DOOR := "door"
const METHOD_OPEN := "open"
const METHOD_QUIET := "quiet"
const METHOD_FORCE := "force"
const F_LOCK_DONE := "lock_done"
const F_SAFE_LEFT := "safe_left"
const B_FORCE_RADIUS := "ruido.radio_forzar_cerradura"
const K_OWNER := "owner"


static func handles(interact_type: String) -> bool:
	return TYPES.has(interact_type)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_LOCK:
			await use_lock(item, player, ctx)
		T_READER:
			await use_reader(item, player, ctx)
		T_SAFE, T_FLOOR_SAFE:
			await use_safe(item, player, ctx)
		T_CEO:
			await use_ceo_safe(item, player, ctx)
		T_BENCH:
			await use_bench(item, player, ctx)


static func lock_prompt(item: Interactable) -> String:
	if not lock_key(item).is_empty():
		return "SECOPS_PROMPT_UNLOCK"
	return "SECOPS_PROMPT_FORCE" if not lock_tool(item).is_empty() else ""


## Un candado de puerta ya abierto (llave o forzado) deja de ofrecerse hasta que se recargue la planta.
static func lock_available(item: Interactable) -> bool:
	if not is_door_lock(item):
		return true
	var streamer: FloorStreamer = FloorStreamer.find_in(SecurityKit.tree_of(item))
	var door: Door = lock_door(item, {"streamer": streamer})
	return door == null or door.is_locked()


# ─── Candados antiguos ────────────────────────────────────────

static func lock_door(item: Interactable, ctx: Dictionary) -> Door:
	var streamer: FloorStreamer = SecurityKit.streamer(ctx)
	var door_id: String = str(item.data.get("door_id", ""))
	return streamer.get_door_by_id(door_id) if streamer != null and not door_id.is_empty() else null


static func is_door_lock(item: Interactable) -> bool:
	return str(item.data.get("target", TARGET_DOOR)).begins_with(TARGET_DOOR)


## Llave que abre el candado ("" si ninguna): keys_basic si lo admite, o una maestra.
static func lock_key(item: Interactable) -> String:
	if not bool(item.data.get("keys_basic_opens", true)):
		return ""
	var keys: Array = [SecurityKit.bs("cerraduras.llave_basica")]
	keys.append_array(SecurityKit.barr("cerraduras.llaves_maestras"))
	return SecurityKit.owned_of(keys)


static func lock_tool(item: Interactable) -> String:
	if not bool(item.data.get("forcible", true)):
		return ""
	return SecurityKit.carried_of(SecurityKit.barr("cerraduras.herramientas"))


static func use_lock(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var door: Door = lock_door(item, ctx)
	if is_door_lock(item) and door != null and not door.is_locked():
		door.open_for(SecurityKit.bf("cerraduras.apertura_s"))
		SecurityKit.toast(ctx, "SECOPS_LOCK_ALREADY", [], ToastStack.KIND_INFO)
		return
	if not is_door_lock(item) and int(SecurityKit.flag_dict(F_LOCK_DONE).get(item.interact_id, -1)) == SecurityKit.today():
		SecurityKit.toast(ctx, "SECOPS_LOCK_EMPTY", [], ToastStack.KIND_INFO)
		return
	var key: String = lock_key(item)
	if not key.is_empty():
		await SecurityKit.legit_pause(player, "drawer")
		SecurityKit.sfx(player, "drawer_open")
		open_lock(item, door, ctx)
		SecurityKit.toast(ctx, "SECOPS_LOCK_UNLOCKED", [SecurityKit.item_name(key)], ToastStack.KIND_GOOD)
		return
	var tool: String = lock_tool(item)
	if tool.is_empty():
		var key_ok: bool = bool(item.data.get("keys_basic_opens", true))
		SecurityKit.toast(ctx, "SECOPS_LOCK_NEED_KEY" if key_ok else "SECOPS_LOCK_NEED_TOOL",
				[SecurityKit.item_names(SecurityKit.barr("cerraduras.herramientas"))], ToastStack.KIND_WARN)
		SecurityKit.sfx(player, "ui_error")
		return
	await force_lock(item, player, ctx, door, tool)


static func force_lock(item: Interactable, player: Node, ctx: Dictionary, door: Door, tool: String) -> bool:
	var radius: float = float(item.data.get("force_noise_radius", Database.get_balance_float(B_FORCE_RADIUS)))
	var armed: bool = SecurityPower.alarm_armed(SecurityKit.floor_of_room(item.room_id))
	if not await SecurityKit.confirm(ctx, "SECOPS_FORCE_TITLE", "SECOPS_FORCE_BODY_ALARM" if armed else "SECOPS_FORCE_BODY",
			"SECOPS_FORCE_GO", [SecurityKit.item_name(tool), roundi(radius)]):
		return false
	if not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.noisy_act(player, CRIME_FORCED, SecurityKit.bf("cerraduras.segundos_forzar"), radius, NOISE_FORCE):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	EventBus.crime_committed.emit(CRIME_FORCED, item.room_id,
			{"target": str(item.data.get("door_id", item.interact_id)), "tool": tool})
	open_lock(item, door, ctx)
	SecurityKit.toast(ctx, "SECOPS_LOCK_FORCED", [SecurityKit.item_name(tool)], ToastStack.KIND_GOOD)
	if armed:
		SecurityPower.trip_alarm(ctx, player, item.room_id)
	return true


## Puerta: queda sin bloqueo (hasta recargar la planta) y abierta; armario: su contenido.
static func open_lock(item: Interactable, door: Door, ctx: Dictionary) -> void:
	if is_door_lock(item):
		if door != null:
			door.set_locked(false)
			door.open_for(SecurityKit.bf("cerraduras.apertura_s"))
		return
	var done: Dictionary = SecurityKit.flag_dict(F_LOCK_DONE)
	done[item.interact_id] = SecurityKit.today()
	SecurityKit.set_flag(F_LOCK_DONE, done)
	var got: Dictionary = SecurityKit.take_items(item.data.get("contains", []))
	if not (got["taken"] as Array).is_empty():
		SecurityKit.toast(ctx, "SECOPS_TAKEN", [SecurityKit.item_names(got["taken"])], ToastStack.KIND_GOOD)


# ─── Lectores con tarjeta ajena ───────────────────────────────

static func reader_door(item: Interactable) -> Door:
	var streamer: FloorStreamer = FloorStreamer.find_in(SecurityKit.tree_of(item))
	return streamer.get_door_by_id(str(item.data.get("door_id", ""))) if streamer != null else null


## Tarjetas ajenas encima (robada, clonada).
static func alt_cards() -> Array[ItemData]:
	var ids: Array[String] = [SecurityKit.bs("tarjetas.robada"), SecurityKit.bs("tarjetas.clonada")]
	var out: Array[ItemData] = []
	for item: ItemData in PlayerState.get_inventory():
		if ids.has(item.id):
			out.append(item)
	return out


static func reader_available(item: Interactable) -> bool:
	var door: Door = reader_door(item)
	return door != null and door.is_locked() and not DoorAccess.allows(door) and not alt_cards().is_empty()


static func card_owner(card: ItemData) -> String:
	return str(card.extra.get(K_OWNER, ""))


## ¿Abriría el titular de la tarjeta? (misma regla que DoorAccess.meets_door).
static func card_opens(door: Door, card: ItemData) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(card_owner(card))
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id) if npc != null else null
	var level: int = occupation.clearance if occupation != null else int(card.extra.get("clearance", SecurityKit.bi("tarjetas.acreditacion_defecto")))
	var specials: Array = occupation.special_access if occupation != null else card.extra.get("special_access", [])
	var level_ok: bool = level >= door.clearance
	if door.special_access.is_empty():
		return level_ok
	var special_ok: bool = false
	for tag: String in door.special_access:
		special_ok = special_ok or specials.has(tag)
	if door.special_mode == DoorAccess.MODE_OR:
		return level_ok or special_ok
	return level_ok and special_ok if door.special_mode == DoorAccess.MODE_AND else level_ok


static func use_reader(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var door: Door = reader_door(item)
	var cards: Array[ItemData] = alt_cards()
	if door == null or cards.is_empty():
		return
	var card: ItemData = cards[0]
	if cards.size() > 1:
		var options: Array = []
		for c: ItemData in cards:
			options.append({"text_key": "SECOPS_CARD_USE_" + c.id.to_upper(), "args": [SecurityKit.npc_name(card_owner(c))]})
		options.append("UI_CANCEL")
		var i: int = await SecurityKit.choose(ctx, "SECOPS_CARD_TITLE", "SECOPS_CARD_BODY", options)
		if i < 0 or i >= cards.size():
			return
		card = cards[i]
	swipe_card(door, card, ctx)


## Pasa una tarjeta ajena por el lector. true si abre.
static func swipe_card(door: Door, card: ItemData, ctx: Dictionary) -> bool:
	var owner_name: String = SecurityKit.npc_name(card_owner(card))
	if not card_opens(door, card):
		SecurityKit.sfx(door, "card_denied", door.global_position)
		SecurityKit.toast(ctx, "SECOPS_CARD_DENIED", [owner_name, door.clearance], ToastStack.KIND_WARN)
		return false
	door.open_for(SecurityKit.bf("tarjetas.apertura_s"))
	SecurityKit.sfx(door, "card_beep", door.global_position)
	if card.id == SecurityKit.bs("tarjetas.robada"):
		Security.log_card_access(door.door_id, card_owner(card), GameClock.get_day(), GameClock.get_hour(), door.room_b)
		SecurityKit.toast(ctx, "SECOPS_CARD_STOLEN_OK", [owner_name], ToastStack.KIND_GOOD)
	else:
		SecurityKit.toast(ctx, "SECOPS_CARD_CLONED_OK", [], ToastStack.KIND_GOOD)
	return true


# ─── Cajas fuertes ────────────────────────────────────────────

## Lo que queda dentro (se repone pasadas operativa.cajas.dias_reposicion jornadas).
static func safe_contents(item: Interactable) -> Array:
	var entry: Variant = SecurityKit.flag_dict(F_SAFE_LEFT).get(item.interact_id)
	if entry is Dictionary and SecurityKit.today() - int(entry.get("day", 0)) < SecurityKit.bi("cajas.dias_reposicion"):
		return (entry["items"] as Array).duplicate()
	return (item.data.get("contains", []) as Array).duplicate()


## {kind: open|quiet|force|"", tool}: cómo puede abrirla el jugador ahora.
static func safe_method(item: Interactable) -> Dictionary:
	var requires: String = str(item.data.get("requires", "key"))
	if requires == "clearance" and PlayerState.get_clearance() >= int(item.data.get("min_clearance", 0)):
		return {"kind": METHOD_OPEN, "tool": ""}
	var ways: Dictionary = SecurityKit.bdict("cajas.metodos." + requires)
	var quiet: String = SecurityKit.owned_of(ways.get("silencioso", []))
	if not quiet.is_empty():
		return {"kind": METHOD_QUIET, "tool": quiet}
	var force: String = SecurityKit.carried_of(ways.get("forzado", []))
	return {"kind": METHOD_FORCE if not force.is_empty() else "", "tool": force}


static func use_safe(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not NightOps.get_house_type(item.room_id).is_empty():
		await _loot_house_safe(item, player, ctx)
		return
	if safe_contents(item).is_empty():
		SecurityKit.toast(ctx, "SECOPS_SAFE_EMPTY", [], ToastStack.KIND_INFO)
		return
	var method: Dictionary = safe_method(item)
	var kind: String = str(method["kind"])
	if kind.is_empty():
		var requires: String = str(item.data.get("requires", "key"))
		SecurityKit.toast(ctx, "SECOPS_SAFE_NEEDS_" + requires.to_upper(), [int(item.data.get("min_clearance", 0))], ToastStack.KIND_WARN)
		SecurityKit.sfx(player, "ui_error")
		return
	if not await _safe_act(item, player, ctx, method):
		return
	loot_safe(item, ctx, kind == METHOD_FORCE, kind == METHOD_OPEN)


## Confirmación y acto de apertura (forzar: ruido y aviso de alarma). false = cancelado.
static func _safe_act(item: Interactable, player: Node, ctx: Dictionary, method: Dictionary) -> bool:
	var force: bool = str(method["kind"]) == METHOD_FORCE
	var armed: bool = force and SecurityPower.alarm_armed(SecurityKit.floor_of_room(item.room_id))
	if force and not await SecurityKit.confirm(ctx, "SECOPS_FORCE_TITLE", "SECOPS_FORCE_BODY_ALARM" if armed else "SECOPS_FORCE_BODY",
			"SECOPS_FORCE_GO", [SecurityKit.item_name(str(method["tool"])), SecurityKit.bi("cajas.radio_ruido_forzar")]):
		return false
	if not force and not await SecurityKit.confirm(ctx, "SECOPS_SAFE_TITLE", "SECOPS_SAFE_CONFIRM_BODY", "SECOPS_SAFE_CONFIRM",
			[SecurityKit.item_names(safe_contents(item))]):
		return false
	if not await SecurityKit.watched_ok(ctx, player):
		return false
	var ok: bool = false
	if force:
		ok = await SecurityKit.noisy_act(player, CRIME_FORCED, SecurityKit.bf("cajas.segundos_forzar"), SecurityKit.bf("cajas.radio_ruido_forzar"), NOISE_FORCE)
	else:
		ok = await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("cajas.segundos_abrir"))
	if not ok:
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	if force:
		EventBus.crime_committed.emit(CRIME_FORCED, item.room_id, {"target": item.interact_id, "tool": str(method["tool"])})
		if armed:
			SecurityPower.trip_alarm(ctx, player, item.room_id)
	return true


## Caja abierta: registro de apertura, botín y delito de robo. Devuelve lo que se llevó.
## `own_card`: se abrió con la acreditación propia (el registro lleva el nombre del jugador).
static func loot_safe(item: Interactable, ctx: Dictionary, forced: bool, own_card: bool = false) -> Array:
	if bool(item.data.get("logs_opening", false)):
		var holder: String = SecurityKit.PLAYER_ID if own_card else SecurityKit.bs("cajas.titular_registro")
		Security.log_card_access(item.interact_id, holder, GameClock.get_day(), GameClock.get_hour(), item.room_id)
	var cash: Dictionary = _take_cash(safe_contents(item))
	var got: Dictionary = SecurityKit.take_items(cash["rest"])
	var left: Dictionary = SecurityKit.flag_dict(F_SAFE_LEFT)
	left[item.interact_id] = {"day": SecurityKit.today(), "items": got["left"]}
	SecurityKit.set_flag(F_SAFE_LEFT, left)
	var taken: Array = (cash["taken"] as Array) + (got["taken"] as Array)
	var value: int = int(cash["money"]) + int(got["value"])
	if not taken.is_empty():
		EventBus.crime_committed.emit(CRIME_THEFT, item.room_id, {"value": value, "items": taken,
				"company_loss": value, "forced": forced})
		var key: String = "SECOPS_SAFE_TAKEN_CASH" if int(cash["money"]) > 0 else "SECOPS_SAFE_TAKEN"
		SecurityKit.toast(ctx, key, [SecurityKit.item_names(taken), int(cash["money"])], ToastStack.KIND_GOOD)
		SecurityKit.sfx(item, "cash")
	if not (got["left"] as Array).is_empty():
		SecurityKit.toast(ctx, "SECOPS_SAFE_FULL", [SecurityKit.item_names(got["left"])], ToastStack.KIND_WARN)
	return taken


## El efectivo de la caja se abona al dinero del jugador: {money, taken, rest (lo demás)}.
static func _take_cash(ids: Array) -> Dictionary:
	var money: int = 0
	var taken: Array[String] = []
	var rest: Array = []
	for id: Variant in ids:
		var data: ItemData = Database.get_item(str(id))
		if data == null or InventoryRules.get_kind(data) != InventoryRules.KIND_CASH:
			rest.append(id)
			continue
		var amount: int = data.value if data.value > 0 else SecurityKit.bi("cajas.efectivo_sobre")
		PlayerState.add_money(amount, CRIME_THEFT)
		money += amount
		taken.append(str(id))
	return {"money": money, "taken": taken, "rest": rest}


static func _loot_house_safe(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var ops: NightOps = SecurityKit.tree_of(item).get_first_node_in_group(NightOps.GROUP) as NightOps
	if ops == null or not ops.is_active():
		SecurityKit.toast(ctx, "SECOPS_SAFE_HOUSE_NO_OP", [], ToastStack.KIND_WARN)
		return
	if not await SecurityKit.act(player, CRIME_BURGLARY, SecurityKit.bf("cajas.segundos_abrir")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	var result: Dictionary = ops.loot_container(item.interact_id)
	if not bool(result.get("ok", false)):
		SecurityKit.toast(ctx, NightOps.reason_key(str(result.get("reason", ""))), [], ToastStack.KIND_WARN)
		return
	var items: Array = result.get("items", [])
	SecurityKit.toast(ctx, "SECOPS_SAFE_HOUSE_LOOT" if not items.is_empty() else "SECOPS_SAFE_EMPTY",
			[SecurityKit.item_names(items), int(result.get("value", 0))], ToastStack.KIND_GOOD)


# ─── Caja del consejero delegado (Endgame) ────────────────────

static func use_ceo_safe(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if Endgame.knows_combination():
		if not await SecurityKit.confirm(ctx, "SECOPS_CEO_TITLE", "SECOPS_CEO_OPEN_BODY", "SECOPS_CEO_OPEN_GO") \
				or not await SecurityKit.watched_ok(ctx, player):
			return
		if not await SecurityKit.act(player, CRIME_THEFT, SecurityKit.bf("cajas.segundos_abrir")):
			SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
			return
		_endgame_feedback(ctx, Endgame.open_safe(), item)
		return
	if not Endgame.has_physical_means():
		SecurityKit.toast(ctx, "SECOPS_CEO_LOCKED" if Endgame.is_objective_revealed() else "SECOPS_CEO_LOCKED_PLAIN", [], ToastStack.KIND_WARN)
		SecurityKit.sfx(player, "ui_error")
		return
	var minutes: int = SecurityKit.bi("cajas.minutos_tramo_ceo")
	if not await SecurityKit.confirm(ctx, "SECOPS_CEO_TITLE", "SECOPS_CEO_FORCE_BODY", "SECOPS_CEO_FORCE_GO", [minutes]) \
			or not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.noisy_act(player, CRIME_FORCED, SecurityKit.bf("cajas.segundos_forzar"), SecurityKit.bf("cajas.radio_ruido_forzar"), NOISE_FORCE):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	GameClock.advance_minutes(float(minutes))
	var pos: Vector2 = (player as Node2D).global_position if player is Node2D else Vector2.ZERO
	_endgame_feedback(ctx, Endgame.work_on_safe(minutes, pos), item)


static func _endgame_feedback(ctx: Dictionary, result: Dictionary, item: Interactable) -> void:
	if bool(result.get("ok", false)):
		SecurityKit.toast(ctx, "SECOPS_CEO_DOCUMENTS", [], ToastStack.KIND_GOOD)
		SecurityKit.sfx(item, "ui_confirm")
		return
	var reason: String = str(result.get("reason", ""))
	if result.has("progress"):
		SecurityKit.toast(ctx, "SECOPS_CEO_PROGRESS", [int(result["progress"]), int(result.get("required", 0))], ToastStack.KIND_INFO)
		return
	SecurityKit.toast(ctx, Endgame.reason_key(reason), [], ToastStack.KIND_WARN)


# ─── Banco de reparación ──────────────────────────────────────

static func stolen_card() -> ItemData:
	for item: ItemData in PlayerState.get_inventory():
		if item.id == SecurityKit.bs("tarjetas.robada"):
			return item
	return null


static func has_it_access() -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation != null and occupation.special_access.has(SecurityKit.bs("banco.acceso_intrusion"))


static func use_bench(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var card: ItemData = stolen_card()
	var options: Array = [{"text_key": "SECOPS_BENCH_CLONE", "disabled": card == null, "danger": true},
			{"text_key": "SECOPS_BENCH_BACKDOOR", "disabled": not has_it_access()}, "UI_CANCEL"]
	match await SecurityKit.choose(ctx, "SECOPS_BENCH_TITLE", "SECOPS_BENCH_BODY", options):
		0:
			await clone_card(item, player, ctx, card)
		1:
			await _backdoor(item, player, ctx)


static func clone_card(item: Interactable, player: Node, ctx: Dictionary, card: ItemData) -> bool:
	if card == null or not await SecurityKit.watched_ok(ctx, player):
		return false
	if not await SecurityKit.act(player, CRIME_FORGERY, SecurityKit.bf("banco.segundos_clonar")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return false
	var clone: ItemData = InventoryRules.make_item(SecurityKit.bs("tarjetas.clonada"))
	clone.extra = card.extra.duplicate(true)
	if not PlayerState.add_item_data(clone):
		SecurityKit.toast(ctx, "SECOPS_INVENTORY_FULL", [], ToastStack.KIND_WARN)
		return false
	GameClock.advance_minutes(SecurityKit.bf("banco.minutos_clonar"))
	EventBus.crime_committed.emit(CRIME_FORGERY, item.room_id, {"item_id": clone.id, "leaves_record": false})
	SecurityKit.toast(ctx, "SECOPS_BENCH_CLONED", [SecurityKit.npc_name(card_owner(card))], ToastStack.KIND_GOOD)
	return true


static func _backdoor(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var targets: Array[String] = []
	for npc_id: String in PlayerState.get_marked_targets():
		if NPCDirector.is_active(npc_id):
			targets.append(npc_id)
	if targets.is_empty():
		SecurityKit.toast(ctx, "SECOPS_BENCH_NO_TARGETS", [], ToastStack.KIND_INFO)
		return
	var labels: Array[String] = []
	for npc_id: String in targets:
		labels.append(SecurityKit.npc_name(npc_id))
	var index: int = await SecurityKit.pick(ctx, TranslationServer.translate("SECOPS_BENCH_TITLE"),
			TranslationServer.translate("SECOPS_BENCH_PICK_HINT"), labels)
	if index < 0:
		return
	await SecurityKit.legit_pause(player, "sit_type")
	Security.log_card_access(item.interact_id, SecurityKit.PLAYER_ID, GameClock.get_day(), GameClock.get_hour(), item.room_id)
	StellarOS.open_intrusion(targets[index], {"computer_id": "backdoor_" + targets[index], "room_id": item.room_id})
