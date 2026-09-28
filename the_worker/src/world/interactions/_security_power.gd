# _security_power.gd — Infraestructura (§22.1, §22.3, §22.5, §23): cuadro eléctrico (apagón por planta con retardo), panel de alarmas por zona, controles de la maquinaria (cierre del vigilante o parada de emergencia) y sabotaje de coches del garaje.
# PROPIETARIO DE: nada (el apagón programado, las zonas de alarma desactivadas, la parada de la línea y los sabotajes pendientes son banderas secops.* de PlayerState).
# ESCUCHA: nada (SecurityKeeper llama a update_blackout() y a apply_car_sabotage()).
class_name SecurityPower
extends RefCounted

## DECISIONES:
##  · APAGÓN (§22.1 «corte por plantas: desactiva cámaras 5 min · todo apagón genera investigación
##    automática»): el cuadro corta UNA planta (operativa.apagon.plantas) ahora o con un retardo
##    (operativa.apagon.retardos, para llegar a tiempo). Dura operativa.apagon.minutos de juego desde
##    que se produce. Al producirse: crime_committed("power_cut", sala del cuadro, {floor}) →
##    Security abre SIEMPRE el caso power_cut (seguridad.incidentes_apertura_automatica). En la
##    planta a oscuras (SecurityKeeper): cámaras inactivas y lectores sin bloqueo (fallo seguro).
##  · ALARMA: de noche (franja night) cada zona (planta) está armada. Forzar una cerradura o una
##    caja en una planta armada la dispara (trip_alarm): ruido, megafonía y Security abre caso
##    (operativa.alarma.incidente) en la sala. Desactivar una zona en la central (acto «sabotage»)
##    vale hasta el cambio de jornada. Antes de forzar, el módulo avisa si la zona está armada.
##  · MAQUINARIA: con ronda de cierre (vigilante, Dir. de Seguridad) y desde la hora de cierre, apagar
##    la línea es legítimo (DutySystem.visit_room cuenta la parada). Sin ese puesto es una parada de
##    emergencia: sabotage con company_loss (operativa.maquinaria.perdida_parada €). Una por jornada.
##  · COCHE (garaje): con herramienta (operativa.coche.herramientas), acto sabotage. Al día siguiente
##    el directivo pasa sus primeras franjas (operativa.coche.franjas) en el garaje con la avería
##    (NPCDirector.override_routine): su despacho queda vacío esa mañana. Uno por coche y jornada.

const TYPES: Array[String] = ["electrical_breaker", "alarm_panel", "machine_controls", "car_sabotage"]
const T_BREAKER := "electrical_breaker"
const T_ALARM := "alarm_panel"
const T_MACHINE := "machine_controls"
const T_CAR := "car_sabotage"
const CRIME_POWER := "power_cut"
const CRIME_SABOTAGE := "sabotage"
const BLACKOUT_STARTED := "started"
const BLACKOUT_ENDED := "ended"
const NIGHT_BAND := "night"
const F_BLACKOUT := "blackout"
const F_ALARM_OFF := "alarm_off"
const F_MACHINE_DAY := "machinery_day"
const F_CAR_PENDING := "car_pending"
const F_CAR_DONE := "car_done"
const NOISE_ALARM := "alarm_bell"
const SFX_ALARM := "pa_chime"


static func handles(interact_type: String) -> bool:
	return TYPES.has(interact_type)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_BREAKER:
			await use_breaker(item, player, ctx)
		T_ALARM:
			await use_alarm(item, player, ctx)
		T_MACHINE:
			await use_machine(item, player, ctx)
		T_CAR:
			await use_car(item, player, ctx)


# ─── Apagón ───────────────────────────────────────────────────

static func blackout() -> Dictionary:
	return SecurityKit.flag_dict(F_BLACKOUT)


static func is_blackout_on(floor_number: int) -> bool:
	var b: Dictionary = blackout()
	return not b.is_empty() and bool(b.get("started", false)) and int(b["floor"]) == floor_number \
			and GameClock.get_total_minutes() < float(b["end"])


## Programa el corte (retardo en minutos de juego). Con retardo 0 se produce en el acto.
static func schedule_blackout(floor_number: int, delay_minutes: float, room_id: String) -> void:
	var start: float = GameClock.get_total_minutes() + delay_minutes
	SecurityKit.set_flag(F_BLACKOUT, {"floor": floor_number, "start": start,
			"end": start + SecurityKit.bf("apagon.minutos"), "room": room_id, "started": false})
	if delay_minutes <= 0.0:
		update_blackout()


## Avanza el apagón programado: {change: started|ended, floor} o {} si no cambió nada.
static func update_blackout() -> Dictionary:
	var b: Dictionary = blackout()
	if b.is_empty():
		return {}
	var now: float = GameClock.get_total_minutes()
	if not bool(b.get("started", false)) and now >= float(b["start"]):
		b["started"] = true
		b["end"] = maxf(float(b["end"]), now + SecurityKit.bf("apagon.minutos"))
		SecurityKit.set_flag(F_BLACKOUT, b)
		EventBus.crime_committed.emit(CRIME_POWER, str(b["room"]), {"floor": int(b["floor"])})
		return {"change": BLACKOUT_STARTED, "floor": int(b["floor"])}
	if bool(b.get("started", false)) and now >= float(b["end"]):
		SecurityKit.set_flag(F_BLACKOUT, null)
		return {"change": BLACKOUT_ENDED, "floor": int(b["floor"])}
	return {}


static func use_breaker(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not blackout().is_empty():
		SecurityKit.toast(ctx, "SECOPS_BREAKER_BUSY", [MapView.floor_label_short(int(blackout()["floor"]))], ToastStack.KIND_WARN)
		return
	var floors: Array[int] = SecurityKit.floor_range("apagon.plantas")
	var index: int = await SecurityKit.pick(ctx, TranslationServer.translate("SECOPS_BREAKER_TITLE"),
			UITheme.trf("SECOPS_BREAKER_HINT", [SecurityKit.bi("apagon.minutos")]), SecurityKit.floor_labels(floors), true, floors)
	if index < 0:
		return
	var delay: float = await _pick_delay(ctx, floors[index])
	if delay < 0.0 or not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_POWER, SecurityKit.bf("apagon.segundos_acto")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	schedule_blackout(floors[index], delay, SecurityKit.base_room(item.room_id))
	SecurityKit.sfx(player, "ui_confirm")
	var label: String = MapView.floor_label_short(floors[index])
	if delay > 0.0:
		SecurityKit.toast(ctx, "SECOPS_BREAKER_SET", [label, roundi(delay)], ToastStack.KIND_INFO)
	var keeper: SecurityKeeper = SecurityKeeper.find(SecurityKit.tree_of(player))
	if keeper != null:
		keeper.apply_blackout()
	if delay <= 0.0:
		SecurityKit.toast(ctx, "SECOPS_BLACKOUT_ON", [label, SecurityKit.bi("apagon.minutos")], ToastStack.KIND_WARN)


## Retardo elegido en minutos (-1 = cancelado).
static func _pick_delay(ctx: Dictionary, floor_number: int) -> float:
	var delays: Array = SecurityKit.barr("apagon.retardos")
	var options: Array = []
	for d: Variant in delays:
		options.append("SECOPS_BREAKER_NOW" if float(d) <= 0.0 else {"text_key": "SECOPS_BREAKER_DELAY", "args": [int(d)]})
	options.append("UI_CANCEL")
	var i: int = await SecurityKit.choose(ctx, "SECOPS_BREAKER_TITLE", "SECOPS_BREAKER_WHEN",
			options, [MapView.floor_label_short(floor_number), SecurityKit.bi("apagon.minutos")])
	return float(delays[i]) if i >= 0 and i < delays.size() else -1.0


# ─── Alarma ───────────────────────────────────────────────────

static func alarm_armed(floor_number: int) -> bool:
	if GameClock.get_current_band() != NIGHT_BAND:
		return false
	return int(SecurityKit.flag_dict(F_ALARM_OFF).get(str(floor_number), -1)) != SecurityKit.today()


## La zona armada salta: ruido, megafonía, aviso y caso abierto en la sala.
static func trip_alarm(ctx: Dictionary, player: Node, room_id: String) -> String:
	if player is Node2D:
		SecurityKit.noise((player as Node2D).global_position, SecurityKit.bf("alarma.radio_ruido"), NOISE_ALARM)
	SecurityKit.sfx(player, SFX_ALARM)
	SecurityKit.toast(ctx, "SECOPS_ALARM_TRIPPED", [SecurityKit.room_name(room_id)], ToastStack.KIND_BAD)
	SecurityKit.note("SECOPS_NOTE_ALARM", [SecurityKit.room_name(room_id)])
	return Security.open_investigation(SecurityKit.bs("alarma.incidente"), SecurityKit.bi("alarma.gravedad"), room_id)


static func use_alarm(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var floors: Array[int] = SecurityKit.floor_range("alarma.plantas")
	var off: Dictionary = SecurityKit.flag_dict(F_ALARM_OFF)
	var labels: Array[String] = []
	for f: int in floors:
		var tag: bool = int(off.get(str(f), -1)) == SecurityKit.today()
		labels.append(MapView.floor_label_short(f) + ("\n" + TranslationServer.translate("SECOPS_ALARM_OFF_TAG") if tag else ""))
	var index: int = await SecurityKit.pick(ctx, TranslationServer.translate("SECOPS_ALARM_TITLE"),
			TranslationServer.translate("SECOPS_ALARM_HINT"), labels, true, floors)
	if index < 0:
		return
	var label: String = MapView.floor_label_short(floors[index])
	if int(off.get(str(floors[index]), -1)) == SecurityKit.today():
		SecurityKit.toast(ctx, "SECOPS_ALARM_ALREADY", [label], ToastStack.KIND_INFO)
		return
	if not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_SABOTAGE, SecurityKit.bf("alarma.segundos_acto")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	disable_alarm_zone(floors[index], SecurityKit.base_room(item.room_id))
	SecurityKit.toast(ctx, "SECOPS_ALARM_DISABLED", [label], ToastStack.KIND_GOOD)
	SecurityKit.sfx(player, "ui_confirm")


static func disable_alarm_zone(floor_number: int, room_id: String) -> void:
	var off: Dictionary = SecurityKit.flag_dict(F_ALARM_OFF)
	off[str(floor_number)] = SecurityKit.today()
	SecurityKit.set_flag(F_ALARM_OFF, off)
	EventBus.crime_committed.emit(CRIME_SABOTAGE, room_id, {"target": "alarm_zone", "floor": floor_number})


# ─── Maquinaria ───────────────────────────────────────────────

static func use_machine(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if int(SecurityKit.flag(F_MACHINE_DAY, -1)) == SecurityKit.today():
		SecurityKit.toast(ctx, "SECOPS_MACHINE_ALREADY", [], ToastStack.KIND_INFO)
		return
	if ClosingTime.has_closing_duty():
		await _closing_shutdown(item, player, ctx)
		return
	var options: Array = [{"text_key": "SECOPS_MACHINE_STOP", "danger": true}, "UI_CANCEL"]
	if await SecurityKit.choose(ctx, "SECOPS_MACHINE_TITLE", "SECOPS_MACHINE_BODY", options,
			[SecurityKit.bi("maquinaria.perdida_parada")]) != 0 or not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_SABOTAGE, SecurityKit.bf("maquinaria.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	SecurityKit.set_flag(F_MACHINE_DAY, SecurityKit.today())
	var loss: int = SecurityKit.bi("maquinaria.perdida_parada")
	EventBus.crime_committed.emit(CRIME_SABOTAGE, SecurityKit.base_room(item.room_id),
			{"target": str(item.data.get("shuts_down", "")), "company_loss": loss})
	SecurityKit.sfx(player, "ui_notify")
	SecurityKit.toast(ctx, "SECOPS_MACHINE_STOPPED", [loss], ToastStack.KIND_WARN)


## Ronda de cierre: legítimo desde la hora de cierre; cuenta como parada de la ronda.
static func _closing_shutdown(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var duty: DutySystem = SecurityKit.tree_of(player).get_first_node_in_group(DutySystem.GROUP) as DutySystem
	var open: bool = duty.is_closing_open() if duty != null else GameClock.get_hour() >= Database.get_balance_int("tiempo.hora_fin_jornada")
	if not open:
		SecurityKit.toast(ctx, "SECOPS_MACHINE_TOO_EARLY", [Database.get_balance_int("tiempo.hora_fin_jornada")], ToastStack.KIND_INFO)
		return
	await SecurityKit.legit_pause(player, "drawer")
	SecurityKit.set_flag(F_MACHINE_DAY, SecurityKit.today())
	if duty != null:
		duty.visit_room(item.room_id)
	SecurityKit.sfx(player, "ui_confirm")
	SecurityKit.toast(ctx, "SECOPS_MACHINE_SHUT", [], ToastStack.KIND_GOOD)


# ─── Coches del garaje ────────────────────────────────────────

static func use_car(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var owner: String = str(item.data.get("owner", ""))
	if owner.is_empty() or not NPCDirector.is_active(owner):
		SecurityKit.toast(ctx, "SECOPS_CAR_NOBODY", [], ToastStack.KIND_INFO)
		return
	if int(SecurityKit.flag_dict(F_CAR_DONE).get(item.interact_id, -1)) == SecurityKit.today():
		SecurityKit.toast(ctx, "SECOPS_CAR_ALREADY", [SecurityKit.npc_name(owner)], ToastStack.KIND_INFO)
		return
	var tool: String = SecurityKit.owned_of(SecurityKit.barr("coche.herramientas"))
	if tool.is_empty():
		SecurityKit.toast(ctx, "SECOPS_CAR_NEED_TOOL", [SecurityKit.npc_name(owner)], ToastStack.KIND_WARN)
		return
	var options: Array = [{"text_key": "SECOPS_CAR_GO", "danger": true}, "UI_CANCEL"]
	if await SecurityKit.choose(ctx, "SECOPS_CAR_TITLE", "SECOPS_CAR_BODY", options,
			[SecurityKit.npc_name(owner), SecurityKit.item_name(tool)]) != 0 or not await SecurityKit.watched_ok(ctx, player):
		return
	if not await SecurityKit.act(player, CRIME_SABOTAGE, SecurityKit.bf("coche.segundos")):
		SecurityKit.toast(ctx, "SECOPS_INTERRUPTED", [], ToastStack.KIND_WARN)
		return
	sabotage_car(item.interact_id, owner, SecurityKit.base_room(item.room_id))
	SecurityKit.toast(ctx, "SECOPS_CAR_DONE", [SecurityKit.npc_name(owner)], ToastStack.KIND_GOOD)


static func sabotage_car(car_id: String, owner: String, room_id: String) -> void:
	var done: Dictionary = SecurityKit.flag_dict(F_CAR_DONE)
	done[car_id] = SecurityKit.today()
	SecurityKit.set_flag(F_CAR_DONE, done)
	var pending: Array = SecurityKit.flag_array(F_CAR_PENDING)
	pending.append({"owner": owner, "day": SecurityKit.today()})
	SecurityKit.set_flag(F_CAR_PENDING, pending)
	EventBus.crime_committed.emit(CRIME_SABOTAGE, room_id, {"target": owner})


## Jornada nueva: los coches saboteados se averían en el trayecto; sus dueños pasan las primeras
## franjas en el garaje. Devuelve a quién le pasó.
static func apply_car_sabotage(day_number: int) -> Array[String]:
	var out: Array[String] = []
	var still: Array = []
	for entry: Variant in SecurityKit.flag_array(F_CAR_PENDING):
		var e: Dictionary = entry as Dictionary
		if int(e.get("day", 0)) >= day_number:
			still.append(e)
			continue
		var owner: String = str(e.get("owner", ""))
		if not NPCDirector.is_active(owner):
			continue
		for band: Variant in SecurityKit.barr("coche.franjas"):
			NPCDirector.override_routine(owner, str(band), SecurityKit.bs("coche.sala"))
		out.append(owner)
	SecurityKit.set_flag(F_CAR_PENDING, still)
	return out
