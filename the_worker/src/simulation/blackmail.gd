# blackmail.gd — Material de chantaje que los personajes guardan contra el jugador y sus exigencias.
# PROPIETARIO DE: nada (el material vive en NPCRuntime.blackmail_material, que guarda NPCDirector con cada personaje).
# ESCUCHA: nada (CaughtHandler llama a process_day() con cada day_advanced).
class_name Blackmail
extends RefCounted

## Una entrada de material contra el jugador es un Dictionary dentro de npc.blackmail_material
## con target == "player" (el resto de entradas de ese Array no son de este módulo):
##   {target, holder, kind, crime_type, day, demand_day, deadline_day, demand_type, amount,
##    demands_made, will_demand, status}
## Ciclo: held → (demand_day) demanded → pay(): held otra vez (volverá a pedir, con escalada)
## o settled (cupo de exigencias cubierto: calla para siempre) · refuse() o plazo vencido: used
## (lo cuenta: denuncia en Seguridad o chivatazo anónimo según su valentía).
## Comprar silencio no es comprar olvido (§12.2): el material no borra ninguna creencia.
## Exigencias: por chat del móvil (phone_message_received, PHONE_BLACKMAIL_*) salvo la del
## sobornable en plena flagrancia, que es cara a cara (subtitle_posted, BLACKMAIL_FACE_*).
## Pagar: dinero (Bribery.Wallet de ctx, por defecto PlayerState); promoción → cuesta reputación,
## deja un favor en su registro y le da mérito de recomendación (empresa.merito_recomendacion,
## que pesa en la vacante, §6.3/§7.8); favor → reputación y favor en su registro.
## El tick diario lo dispara CaughtHandler (day_advanced); el estado vive en NPCDirector.

const TARGET_PLAYER := "player"
const KIND_WITNESSED := "witnessed_crime"
const KIND_BRIBED_SILENCE := "bribed_silence"
const KIND_SILENCE_MEMORY := "silence_with_memory"
const KIND_LEVERAGE := "leverage"
const KIND_ASKED_MONEY := "asked_money"

const DEMAND_MONEY := "money"
const DEMAND_PROMOTION := "promotion"
const DEMAND_FAVOUR := "favour"
const DEMAND_TYPES: Array[String] = [DEMAND_MONEY, DEMAND_PROMOTION, DEMAND_FAVOUR]
const DEMAND_WEIGHT_KEYS: Dictionary = {
	DEMAND_MONEY: "chantaje.peso_exigencia_dinero",
	DEMAND_PROMOTION: "chantaje.peso_exigencia_promocion",
	DEMAND_FAVOUR: "chantaje.peso_exigencia_favor",
}
const REPUTATION_COST_KEYS: Dictionary = {
	DEMAND_PROMOTION: "chantaje.coste_reputacion_promocion",
	DEMAND_FAVOUR: "chantaje.coste_reputacion_favor",
}
const FAVOUR_MAGNITUDE_KEYS: Dictionary = {
	DEMAND_PROMOTION: "chantaje.magnitud_favor_promocion",
	DEMAND_FAVOUR: "chantaje.magnitud_favor_favor",
}
const PHONE_KEYS: Dictionary = {
	DEMAND_MONEY: "PHONE_BLACKMAIL_MONEY", DEMAND_PROMOTION: "PHONE_BLACKMAIL_PROMOTION",
	DEMAND_FAVOUR: "PHONE_BLACKMAIL_FAVOUR",
}
const FACE_KEYS: Dictionary = {
	DEMAND_MONEY: "BLACKMAIL_FACE_MONEY", DEMAND_PROMOTION: "BLACKMAIL_FACE_PROMOTION",
	DEMAND_FAVOUR: "BLACKMAIL_FACE_FAVOUR",
}
## Nivel de importancia del subtítulo (0 ambiente · 1 normal · 2 crítico), no un ajuste.
const SUBTITLE_IMPORTANCE := 2
const B_PROMOTION_MERIT := "empresa.merito_recomendacion"

const STATUS_HELD := "held"
const STATUS_DEMANDED := "demanded"
const STATUS_SETTLED := "settled"
const STATUS_USED := "used"

const EVENT_DEMANDED := "demanded"
const EVENT_PAID := "paid"
const EVENT_REFUSED := "refused"
const EVENT_IGNORED := "ignored"
const REASON_NO_DEMAND := "no_demand"
const REASON_NO_FUNDS := "insufficient_funds"
const REPORT_SECURITY := "security"
const REPORT_ANONYMOUS := "anonymous_tip"
const MONEY_REASON := "blackmail"
const REPUTATION_REASON := "blackmail"
const FAVOUR_TYPE_FORMAT := "blackmail_%s"
const GRIEVANCE_REFUSED := "blackmail_refused"
const TEXT_PAID := "BLACKMAIL_PAID"
const TEXT_REFUSED := "BLACKMAIL_REFUSED"
const TEXT_SETTLED := "BLACKMAIL_SETTLED"


## Añade material contra el jugador. demand_type "" = se sortea al exigir; delay_days < 0 =
## espera aleatoria (chantaje.dias_espera_*). Devuelve la entrada (misma referencia guardada).
static func add_material(npc: NPCRuntime, kind: String, crime_type: String, day: int = -1,
		demand_type: String = "", delay_days: int = -1) -> Dictionary:
	var today: int = day if day >= 0 else GameClock.get_day()
	var delay: int = delay_days if delay_days >= 0 else _random_days(npc.id, today, kind,
			"chantaje.dias_espera_min", "chantaje.dias_espera_max")
	var entry: Dictionary = {
		"target": TARGET_PLAYER, "holder": npc.id, "kind": kind, "crime_type": crime_type,
		"day": today, "demand_day": today + delay, "deadline_day": 0,
		"demand_type": demand_type, "amount": 0, "demands_made": 0,
		"will_demand": _will_demand(npc, demand_type), "status": STATUS_HELD,
	}
	npc.blackmail_material.append(entry)
	return entry


static func get_material(npc: NPCRuntime) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in npc.blackmail_material:
		if entry is Dictionary and entry.get("target", "") == TARGET_PLAYER:
			out.append(entry)
	return out


static func has_material(npc: NPCRuntime) -> bool:
	return not get_material(npc).is_empty()


## La exigencia abierta del personaje ({} si no hay).
static func get_open_demand(npc: NPCRuntime) -> Dictionary:
	for entry: Dictionary in get_material(npc):
		if entry.get("status", "") == STATUS_DEMANDED:
			return entry
	return {}


## Exigencias abiertas de la población (para el móvil): [{npc_id, demand_type, amount,
## deadline_day, kind}]. npcs vacío = NPCDirector.get_all_npcs().
static func get_open_demands(npcs: Array[NPCRuntime] = []) -> Array[Dictionary]:
	var population: Array[NPCRuntime] = npcs if not npcs.is_empty() else NPCDirector.get_all_npcs()
	var out: Array[Dictionary] = []
	for npc: NPCRuntime in population:
		var entry: Dictionary = get_open_demand(npc) if npc != null and npc.alive else {}
		if not entry.is_empty():
			out.append({"npc_id": npc.id, "demand_type": entry["demand_type"],
					"amount": int(entry["amount"]), "deadline_day": int(entry["deadline_day"]),
					"kind": entry["kind"]})
	return out


## Avance diario: emite las exigencias que tocan y da por rechazadas las que vencen.
## npcs vacío = NPCDirector.get_all_npcs(). Devuelve los sucesos producidos.
static func process_day(day: int, npcs: Array[NPCRuntime] = []) -> Array[Dictionary]:
	var population: Array[NPCRuntime] = npcs if not npcs.is_empty() else NPCDirector.get_all_npcs()
	var events: Array[Dictionary] = []
	for npc: NPCRuntime in population:
		if npc == null or not npc.alive:
			continue
		for entry: Dictionary in get_material(npc):
			var event: Dictionary = _step(npc, entry, day)
			if not event.is_empty():
				events.append(event)
	return events


## Emite la exigencia: blackmail_initiated (la primera vez), blackmail_demanded y el mensaje:
## chat del móvil o, cara a cara (face_to_face), un subtítulo. Devuelve el suceso con text_key.
static func issue_demand(npc: NPCRuntime, entry: Dictionary, day: int,
		face_to_face: bool = false) -> Dictionary:
	var demand_type: String = str(entry.get("demand_type", ""))
	if not DEMAND_TYPES.has(demand_type):
		demand_type = _pick_demand_type(npc.id, day)
	entry["demand_type"] = demand_type
	entry["amount"] = demand_amount(npc, entry)
	entry["deadline_day"] = day + Bribery.tunable_int("chantaje.plazo_respuesta_dias")
	entry["status"] = STATUS_DEMANDED
	if int(entry.get("demands_made", 0)) == 0:
		EventBus.blackmail_initiated.emit(npc.id, TARGET_PLAYER, str(entry.get("kind", "")))
	EventBus.blackmail_demanded.emit(npc.id, demand_type, int(entry["amount"]))
	var text_key: String = str((FACE_KEYS if face_to_face else PHONE_KEYS)[demand_type])
	if face_to_face:
		EventBus.subtitle_posted.emit(text_key, Vector2.INF, SUBTITLE_IMPORTANCE)
	else:
		EventBus.phone_message_received.emit(npc.id, text_key, true)
	return {"npc_id": npc.id, "event": EVENT_DEMANDED, "demand_type": demand_type,
			"amount": entry["amount"], "deadline_day": entry["deadline_day"],
			"text_key": text_key}


## Dinero: salario diario × multiplicador × escalada^exigencias ya pagadas. Resto: 0.
static func demand_amount(npc: NPCRuntime, entry: Dictionary) -> int:
	if entry.get("demand_type", "") != DEMAND_MONEY:
		return 0
	var escalation: float = pow(Bribery.tunable("chantaje.factor_escalada"),
			int(entry.get("demands_made", 0)))
	return roundi(Bribery.npc_daily_wage(npc)
			* Bribery.tunable("chantaje.multiplicador_exigencia_dinero") * escalation)


## Cumplir la exigencia abierta. Dinero: se cobra de ctx.wallet (PlayerState por defecto).
## Promoción / favor: cuesta reputación y deja un favor en el registro del personaje.
static func pay(npc: NPCRuntime, ctx: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = get_open_demand(npc)
	if entry.is_empty():
		return {"ok": false, "reason": REASON_NO_DEMAND}
	var result: Dictionary = _pay_cost(npc, entry, ctx)
	if not bool(result["ok"]):
		return result
	var day: int = int(ctx.get("day", GameClock.get_day()))
	entry["demands_made"] = int(entry.get("demands_made", 0)) + 1
	if int(entry["demands_made"]) >= Bribery.tunable_int("chantaje.max_exigencias"):
		entry["status"] = STATUS_SETTLED
		result["text_key"] = TEXT_SETTLED
	else:
		entry["status"] = STATUS_HELD
		entry["demand_day"] = day + _random_days(npc.id, day, EVENT_PAID,
				"chantaje.dias_entre_exigencias_min", "chantaje.dias_entre_exigencias_max")
	result.merge({"npc_id": npc.id, "event": EVENT_PAID, "status": entry["status"],
			"next_demand_day": entry["demand_day"]}, true)
	return result


## Negarse a la exigencia abierta: el personaje lo cuenta y guarda el agravio.
static func refuse(npc: NPCRuntime, ctx: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = get_open_demand(npc)
	if entry.is_empty():
		return {"ok": false, "reason": REASON_NO_DEMAND}
	return _refuse_entry(npc, entry, EVENT_REFUSED, ctx)


static func _step(npc: NPCRuntime, entry: Dictionary, day: int) -> Dictionary:
	var status: String = str(entry.get("status", ""))
	if status == STATUS_HELD and bool(entry.get("will_demand", false)) \
			and day >= int(entry.get("demand_day", 0)) and get_open_demand(npc).is_empty():
		return issue_demand(npc, entry, day)
	if status == STATUS_DEMANDED and day > int(entry.get("deadline_day", 0)):
		return _refuse_entry(npc, entry, EVENT_IGNORED, {})
	return {}


static func _pay_cost(npc: NPCRuntime, entry: Dictionary, ctx: Dictionary) -> Dictionary:
	var demand_type: String = str(entry.get("demand_type", ""))
	var result: Dictionary = {"ok": true, "demand_type": demand_type, "amount": 0,
			"reputation_cost": 0.0, "favour_magnitude": 0, "text_key": TEXT_PAID}
	if demand_type == DEMAND_MONEY:
		var amount: int = int(entry.get("amount", 0))
		if not Bribery.wallet_from(ctx).spend_money(amount, MONEY_REASON):
			return {"ok": false, "reason": REASON_NO_FUNDS, "amount": amount}
		result["amount"] = amount
		return result
	var cost: float = Bribery.tunable(str(REPUTATION_COST_KEYS[demand_type]))
	var magnitude: int = Bribery.tunable_int(str(FAVOUR_MAGNITUDE_KEYS[demand_type]))
	PlayerState.modify_reputation(-cost, REPUTATION_REASON)
	if Bribery.is_managed(npc):
		NPCDirector.add_favour(npc.id, FAVOUR_TYPE_FORMAT % demand_type, magnitude)
	result["reputation_cost"] = cost
	result["favour_magnitude"] = magnitude
	if demand_type == DEMAND_PROMOTION:
		result["merit_given"] = _back_promotion(npc)
	return result


## Respaldar su ascenso: mérito de recomendación que cuenta en la próxima vacante.
static func _back_promotion(npc: NPCRuntime) -> int:
	var merit: int = Bribery.tunable_int(B_PROMOTION_MERIT)
	if Bribery.is_managed(npc):
		NPCDirector.add_merit(npc.id, merit)
	else:
		npc.merit += merit
	return merit


static func _refuse_entry(npc: NPCRuntime, entry: Dictionary, event: String,
		ctx: Dictionary) -> Dictionary:
	entry["status"] = STATUS_USED
	var brave: bool = npc.get_trait("courage") \
			>= Bribery.tunable_int("chantaje.umbral_valentia_denuncia")
	var report_type: String = REPORT_SECURITY if brave else REPORT_ANONYMOUS
	var weight: float = Bribery.tunable("chantaje.peso_denuncia_rechazo" if brave
			else "chantaje.peso_chivatazo_anonimo")
	var location: String = str(ctx["room_id"]) if ctx.has("room_id") else Bribery.npc_location(npc)
	EventBus.npc_reported_player.emit(npc.id, report_type, weight, location)
	if Bribery.is_managed(npc):
		NPCDirector.add_grievance(npc.id, GRIEVANCE_REFUSED,
				Bribery.tunable_int("chantaje.gravedad_agravio_rechazo"))
	return {"ok": true, "npc_id": npc.id, "event": event, "report_type": report_type,
			"weight": weight, "text_key": TEXT_REFUSED}


## Exigirá si el tipo viene forzado, si es cobarde (valentía < umbral de silencio) o si su
## codicia alcanza chantaje.umbral_codicia_exigir.
static func _will_demand(npc: NPCRuntime, demand_type: String) -> bool:
	if not demand_type.is_empty():
		return true
	if npc.get_trait("courage") < Bribery.tunable_int("sobornos.umbral_silencio_valentia"):
		return true
	return npc.get_trait("greed") >= Bribery.tunable_int("chantaje.umbral_codicia_exigir")


static func _pick_demand_type(npc_id: String, day: int) -> String:
	var total: float = 0.0
	for demand_type: String in DEMAND_TYPES:
		total += Bribery.tunable(str(DEMAND_WEIGHT_KEYS[demand_type]))
	var target: float = Bribery.roll_for([npc_id, day, EVENT_DEMANDED]) * total
	for demand_type: String in DEMAND_TYPES:
		target -= Bribery.tunable(str(DEMAND_WEIGHT_KEYS[demand_type]))
		if target < 0.0:
			return demand_type
	return DEMAND_TYPES[DEMAND_TYPES.size() - 1]


static func _random_days(npc_id: String, day: int, salt: String, min_key: String,
		max_key: String) -> int:
	var low: int = Bribery.tunable_int(min_key)
	var high: int = Bribery.tunable_int(max_key)
	var roll: float = Bribery.roll_for([npc_id, day, salt])
	return clampi(low + floori(roll * (high - low + 1)), low, high)
