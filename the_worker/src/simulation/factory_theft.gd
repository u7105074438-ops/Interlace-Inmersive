# factory_theft.gd — Robo en fábrica (§11.6): las tres escalas con sus requisitos, el recuento semanal que las destapa con retardo y los albaranes falsificados que desvían el descuadre.
# PROPIETARIO DE: nada (robos sin recontar, albaranes de la semana y recuentos los guarda Company; el dinero, PlayerState; los casos, Security).
# ESCUCHA: week_closed (solo tras connect_calendar(): entrega a Security los descuadres que Company destapó).
class_name FactoryTheft
extends RefCounted

## Manual §11.6, §9.4 («semanal: primera señal visible de los robos»), §9.10; PASO 41;
## BUILD_NOTES §2 (manos), §12, §13.
## MANOS DEL MUNDO (InteractionRouter):
##  · product_shelf (data.scale ⊂ pocket|box), goods_pallets / carrier_bay (pallet):
##    check_requirements(escala, opciones) → {allowed, missing ⊂ scale|location|rank|occupation|
##    cart|accomplice} para el aviso (get_missing_label_key) y steal(escala, opciones) para el acto.
##    opciones: pairs (0 = sorteo en el intervalo de la escala), cart (el jugador empuja un
##    carrito), accomplice_id ("" = el mejor transportista cómplice), room_id ("" = sala actual).
##  · delivery_notes (fabrica.salas_albaranes): forge_delivery_notes(sala).
##  · Al empezar o cargar la partida: connect_calendar() (idempotente; steal y forge también la
##    llaman). Sin ella, Company recuenta igual pero el descuadre no llega a Security.
## DECISIONES:
##  · Requisitos (§11.6): todas las escalas exigen estar en una sala de la nave (planta
##    mundo.planta_fabrica); rango ≥ rango_min; palé: ocupación capataz o director de fábrica;
##    caja: carrito (objeto de fabrica.objetos_carro u opción cart) o acceso al montacargas
##    (acreditación ≥ la de fabrica.sala_montacargas); palé: transportista cómplice (puesto o rol
##    de fabrica.puestos_transportista, en plantilla, con deuda ≥ deuda_minima_complice o afecto ≥
##    afecto_minimo_complice: sobornarlo le deja deuda).
##  · Ingreso = interpolación lineal ingreso_min..max según los pares (reventa inmediata: el
##    producto no entra en el inventario) → PlayerState.add_money(ingreso, "factory_theft_<escala>").
##    La compañía pierde pares × precio medio de los fundamentales.
##  · crime_committed("theft_product", sala, {value: ingreso, quantity: pares, scale,
##    company_loss, loss_booked: true, leaves_record: false, accomplice, theft_id}): NADA se detecta
##    en el acto (ni incidente de Security ni pérdida en costes); Tracking suma ORO y DutySystem
##    descuenta la cuota. El robo queda pendiente en Company (register_factory_theft).
##  · RECUENTO SEMANAL (Company.run_inventory_count en week_closed; build_count_report es puro):
##    pares que faltan desde el último recuento; hasta fabrica.tolerancia_recuento_pares es merma
##    absorbida (el bolsillo: «prácticamente ninguno»); la pérdida entra en theft_losses AL RECUENTO.
##    Un descuadre se entrega aquí (report_mismatches): Security.report_incident("inventory_mismatch",
##    gravedad de la mayor escala, fabrica.sala_recuento, provocado por el jugador, {weight de la
##    mayor escala (× factor_peso_cfo si el CFO, personaje, lo ve en los márgenes: escalas de
##    escalas_visibles_margenes), subject, player_culprit, day de la mayor sustracción, hour
##    desconocida}). subject: el superior de los albaranes falsificados; si no hay albaranes, el
##    jugador si ocupa un puesto responsable del inventario (capataz); si no, nadie (la
##    investigación busca con sus procedimientos: cámaras de ese día, testigos, accesos).
##  · ALBARANES: forge_delivery_notes() → el recuento de ESTA semana apunta al superior directo
##    (find_direct_superior: superior de la sala de trabajo del jugador; si no, su superior directo
##    según Bribery; si no, el superior más cercano de su departamento). Emite
##    crime_committed("forgery", sala, {subject, target, document}) (BeliefNet: documento sellado
##    sin verificar contra él; Tracking: SEDA) y crime_committed("framing", sala, {target, method})
##    (Tracking: SEDA si cae). Al entregar el descuadre: pieza forged_document contra él
##    (Security.plant_evidence: queda como incriminado; su condena libera la vacante) y registro de
##    acceso del jugador (BeliefNet.create_record): también tenía acceso, su sospecha sube.

const PLAYER_ID := "player"
const SCALE_POCKET := "pocket"
const SCALE_BOX := "box"
const SCALE_PALLET := "pallet"
## De menor a mayor: la mayor escala de la semana manda en el incidente.
const SCALES: Array[String] = [SCALE_POCKET, SCALE_BOX, SCALE_PALLET]
const SCALE_LABEL_KEYS: Dictionary = {
	SCALE_POCKET: "FACTORY_SCALE_POCKET", SCALE_BOX: "FACTORY_SCALE_BOX",
	SCALE_PALLET: "FACTORY_SCALE_PALLET",
}

const MISSING_SCALE := "scale"
const MISSING_LOCATION := "location"
const MISSING_RANK := "rank"
const MISSING_OCCUPATION := "occupation"
const MISSING_CART := "cart"
const MISSING_ACCOMPLICE := "accomplice"
const MISSING_LABEL_KEYS: Dictionary = {
	MISSING_SCALE: "FACTORY_MISSING_SCALE", MISSING_LOCATION: "FACTORY_MISSING_LOCATION",
	MISSING_RANK: "FACTORY_MISSING_RANK", MISSING_OCCUPATION: "FACTORY_MISSING_OCCUPATION",
	MISSING_CART: "FACTORY_MISSING_CART", MISSING_ACCOMPLICE: "FACTORY_MISSING_ACCOMPLICE",
}
const REASON_REQUIREMENTS := "requirements"
const REASON_NOT_AT_NOTES := "not_at_delivery_notes"
const REASON_NO_SUPERIOR := "no_superior"

const CRIME_THEFT := "theft_product"
const CRIME_FORGERY := "forgery"
const CRIME_FRAMING := "framing"
const DOCUMENT_DELIVERY_NOTE := "delivery_note"
const FRAMING_METHOD := "delivery_notes"
const INCIDENT_TYPE := "inventory_mismatch"
const MONEY_REASON_FORMAT := "factory_theft_%s"
const RNG_SALT := "factory_theft"
## Hora de incidente desconocida (Security revisa la jornada entera).
const NO_HOUR := -1
## Escalón «ninguno» para buscar el mínimo (por encima del máximo real).
const NO_TIER := OccupationData.MAX_TIER + 1
const K_AVG_PRICE := "avg_price"
const K_HAS_SUBORDINATES := "has_subordinates"
const K_DEPARTMENT := "department"

# Claves de un robo pendiente (Company) y del contexto del recuento.
const T_SCALE := "scale"
const T_PAIRS := "pairs"
const T_LOSS := "loss"
const T_ROOM := "room_id"
const T_DAY := "day"
const C_WEEK := "week"
const C_DAY := "day"
const C_STOCK := "stock"
const C_PRODUCED := "produced"
const C_FORGED := "forged_target"
const C_RESPONSIBLE := "player_responsible"
const C_CFO := "cfo_holder"

# Claves de un informe de recuento (Company.get_inventory_reports()).
const R_WEEK := "week"
const R_DAY := "day"
const R_PRODUCED := "produced"
const R_EXPECTED := "expected"
const R_COUNTED := "counted"
const R_MISSING := "missing"
const R_LOSS := "loss"
const R_THEFTS := "thefts"
const R_MISMATCH := "mismatch"
const R_ABSORBED := "absorbed"
const R_SCALE := "scale"
const R_INCIDENT_DAY := "incident_day"
const R_ROOM := "room"
const R_POINTS_TO := "points_to"
const R_FRAMED_TO := "framed_to"
const R_CFO := "cfo_detected"
const R_WEIGHT := "weight"
const R_SEVERITY := "severity"
const R_REPORTED := "reported"
const REPORT_INT_KEYS: Array[String] = [
	R_WEEK, R_PRODUCED, R_EXPECTED, R_COUNTED, R_MISSING, R_THEFTS, R_INCIDENT_DAY, R_SEVERITY,
]

const B_SCALE := "fabrica.escalas.%s"
const B_TOLERANCE := "fabrica.tolerancia_recuento_pares"
const B_COUNT_ROOM := "fabrica.sala_recuento"
const B_NOTES_ROOMS := "fabrica.salas_albaranes"
const B_CART_ITEMS := "fabrica.objetos_carro"
const B_FREIGHT_ROOM := "fabrica.sala_montacargas"
const B_CARRIER_POSTS := "fabrica.puestos_transportista"
const B_ACCOMPLICE_DEBT := "fabrica.deuda_minima_complice"
const B_ACCOMPLICE_AFFECTION := "fabrica.afecto_minimo_complice"
const B_MARGIN_SCALES := "fabrica.escalas_visibles_margenes"
const B_CFO_FACTOR := "fabrica.factor_peso_cfo"
const B_NOTE_EVIDENCE := "fabrica.tipo_evidencia_albaran"
const B_ACCESS_RECORD := "fabrica.tipo_registro_acceso"
const B_ACCESS_WEIGHT := "fabrica.peso_registro_acceso"
const B_FACTORY_FLOOR := "mundo.planta_fabrica"
# Claves de una escala (fabrica.escalas.<id>).
const S_PAIRS_MIN := "pares_min"
const S_PAIRS_MAX := "pares_max"
const S_INCOME_MIN := "ingreso_min"
const S_INCOME_MAX := "ingreso_max"
const S_RANK := "rango_min"
const S_POSTS := "ocupaciones"
const S_CART := "requiere_carro_o_montacargas"
const S_ACCOMPLICE := "requiere_complice"
const S_WEIGHT := "peso_incidente"
const S_SEVERITY := "gravedad"


# ─── Requisitos (§11.6) ───────────────────────────────────────

## Configuración de una escala ({} si no existe).
static func get_scale_config(scale: String) -> Dictionary:
	var path: String = B_SCALE % scale
	if not SCALES.has(scale) or not Database.has_balance(path):
		return {}
	var value: Variant = Database.get_balance(path)
	return value as Dictionary if value is Dictionary else {}


## {allowed: bool, missing: Array[String]} con missing ⊂ scale, location, rank, occupation, cart,
## accomplice (todas las condiciones que faltan, para el aviso de la interfaz).
static func check_requirements(scale: String, options: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = get_scale_config(scale)
	var missing: Array[String] = []
	if cfg.is_empty():
		missing.append(MISSING_SCALE)
		return {"allowed": false, "missing": missing}
	if not is_factory_room(_room_of(options)):
		missing.append(MISSING_LOCATION)
	if PlayerState.get_rank() < int(cfg.get(S_RANK, 0)):
		missing.append(MISSING_RANK)
	var posts: Array[String] = _strings(cfg.get(S_POSTS, []))
	if not posts.is_empty() and not posts.has(PlayerState.get_occupation_id()):
		missing.append(MISSING_OCCUPATION)
	if bool(cfg.get(S_CART, false)) and not has_cart_or_freight(options):
		missing.append(MISSING_CART)
	if bool(cfg.get(S_ACCOMPLICE, false)) and _accomplice_for(options).is_empty():
		missing.append(MISSING_ACCOMPLICE)
	return {"allowed": missing.is_empty(), "missing": missing}


## Sala de la nave (planta mundo.planta_fabrica).
static func is_factory_room(room_id: String) -> bool:
	var room: RoomData = Database.get_room(InvestigationEngine.base_room(room_id)) \
			if not room_id.is_empty() else null
	return room != null and room.floor == Database.get_balance_int(B_FACTORY_FLOOR)


## Caja (§11.6 «carrito o acceso al montacargas»): opción cart, un objeto de carrito o acreditación
## suficiente para la sala del montacargas.
static func has_cart_or_freight(options: Dictionary = {}) -> bool:
	if bool(options.get("cart", false)):
		return true
	for item_id: String in _strings(Database.get_balance(B_CART_ITEMS)):
		if PlayerState.has_item(item_id):
			return true
	var freight: RoomData = Database.get_room(str(Database.get_balance(B_FREIGHT_ROOM)))
	return freight != null and PlayerState.get_clearance() >= freight.clearance_required


## Transportista (puesto o rol de fabrica.puestos_transportista) en plantilla que colabora: le debe
## algo al jugador o le tiene suficiente afecto.
static func is_accomplice(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not NPCDirector.is_active(npc_id):
		return false
	var posts: Array[String] = _strings(Database.get_balance(B_CARRIER_POSTS))
	if not posts.has(npc.occupation_id) and not posts.has(NPCDirector.get_role(npc_id)):
		return false
	return NPCDirector.get_debt(npc_id) >= Database.get_balance_int(B_ACCOMPLICE_DEBT) \
			or NPCDirector.get_affection(npc_id) >= Database.get_balance_int(B_ACCOMPLICE_AFFECTION)


## El cómplice con más deuda (a igualdad, más afecto) de la plantilla; "" si no hay.
static func find_accomplice() -> String:
	var best: String = ""
	var best_debt: int = 0
	var best_affection: int = 0
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not is_accomplice(npc.id):
			continue
		var debt: int = NPCDirector.get_debt(npc.id)
		var affection: int = NPCDirector.get_affection(npc.id)
		if best.is_empty() or debt > best_debt or (debt == best_debt and affection > best_affection):
			best = npc.id
			best_debt = debt
			best_affection = affection
	return best


static func get_missing_label_key(missing: String) -> String:
	return str(MISSING_LABEL_KEYS.get(missing, ""))


static func get_scale_label_key(scale: String) -> String:
	return str(SCALE_LABEL_KEYS.get(scale, ""))


# ─── El acto ──────────────────────────────────────────────────

## Ejecuta el robo si se cumplen los requisitos. {ok, scale, pairs, income, company_loss, theft_id,
## accomplice, reason, missing}. Nada se detecta ahora: aflora en el recuento semanal.
static func steal(scale: String, options: Dictionary = {}) -> Dictionary:
	var check: Dictionary = check_requirements(scale, options)
	if not bool(check["allowed"]):
		return {"ok": false, "scale": scale, "reason": REASON_REQUIREMENTS,
				"missing": check["missing"]}
	var cfg: Dictionary = get_scale_config(scale)
	var pairs: int = _pairs_for(cfg, int(options.get("pairs", 0)))
	var income: int = income_for(scale, pairs)
	var loss: float = pairs * unit_loss()
	var room: String = _room_of(options)
	var accomplice: String = _accomplice_for(options) if bool(cfg.get(S_ACCOMPLICE, false)) else ""
	var theft_id: String = Company.register_factory_theft(scale, pairs, loss, room)
	PlayerState.add_money(income, MONEY_REASON_FORMAT % scale)
	EventBus.crime_committed.emit(CRIME_THEFT, room, {
		"value": income, "quantity": pairs, "scale": scale, "company_loss": loss,
		"loss_booked": true, "leaves_record": false, "accomplice": accomplice,
		"theft_id": theft_id,
	})
	connect_calendar()
	return {"ok": true, "scale": scale, "pairs": pairs, "income": income, "company_loss": loss,
			"theft_id": theft_id, "accomplice": accomplice, "reason": "", "missing": []}


## Ingreso del jugador (€): interpolación lineal ingreso_min..max según los pares (§11.6).
static func income_for(scale: String, pairs: int) -> int:
	var cfg: Dictionary = get_scale_config(scale)
	var low: int = int(cfg.get(S_PAIRS_MIN, 0))
	var high: int = int(cfg.get(S_PAIRS_MAX, low))
	var t: float = 0.0
	if high > low:
		t = clampf(float(pairs - low) / float(high - low), 0.0, 1.0)
	return roundi(lerpf(float(cfg.get(S_INCOME_MIN, 0)), float(cfg.get(S_INCOME_MAX, 0)), t))


## Pérdida de la compañía por par: el precio medio de los fundamentales (§9.10).
static func unit_loss() -> float:
	return float(Company.get_fundamentals().get(K_AVG_PRICE, 0.0))


## Albaranes falsificados (§11.6 «incriminación»): el recuento de esta semana apunta al superior
## directo. {ok, target, reason}.
static func forge_delivery_notes(room_id: String = "") -> Dictionary:
	var room: String = room_id if not room_id.is_empty() else PlayerState.get_room()
	if not _strings(Database.get_balance(B_NOTES_ROOMS)).has(InvestigationEngine.base_room(room)):
		return {"ok": false, "target": "", "reason": REASON_NOT_AT_NOTES}
	var target: String = find_direct_superior()
	if target.is_empty():
		return {"ok": false, "target": "", "reason": REASON_NO_SUPERIOR}
	Company.set_forged_delivery_target(target)
	EventBus.crime_committed.emit(CRIME_FORGERY, room, {"subject": target, "target": target,
			"document": DOCUMENT_DELIVERY_NOTE})
	EventBus.crime_committed.emit(CRIME_FRAMING, room, {"target": target,
			"method": FRAMING_METHOD})
	connect_calendar()
	return {"ok": true, "target": target, "reason": ""}


## Superior directo del jugador en plantilla: el de su sala de trabajo (jerarquía de generación),
## si no el superior directo de Bribery y, si no hay, el superior más cercano de su departamento.
static func find_direct_superior() -> String:
	var own: OccupationData = PlayerState.get_occupation()
	if own == null:
		return ""
	var by_room: String = _room_superior(own.office_room)
	if not by_room.is_empty():
		return by_room
	var direct: String = ""
	var nearest: String = ""
	var direct_tier: int = NO_TIER
	var nearest_tier: int = NO_TIER
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var boss: OccupationData = Database.get_occupation(npc.occupation_id)
		if boss == null or npc.id == PLAYER_ID:
			continue
		if Bribery.is_direct_superior(boss, own) and boss.tier < direct_tier:
			direct = npc.id
			direct_tier = boss.tier
		elif _same_line_superior(boss, own) and boss.tier < nearest_tier:
			nearest = npc.id
			nearest_tier = boss.tier
	return direct if not direct.is_empty() else nearest


# ─── Recuento semanal (puro; lo llama Company) ───────────────

## Informe del recuento: thefts = robos sin recontar [{id, day, scale, pairs, loss, room_id}];
## context = {week, day, stock, produced, forged_target, player_responsible, cfo_holder}.
static func build_count_report(thefts: Array[Dictionary], context: Dictionary) -> Dictionary:
	var missing: int = 0
	var loss: float = 0.0
	var top: Dictionary = {}
	for theft: Dictionary in thefts:
		missing += int(theft.get(T_PAIRS, 0))
		loss += float(theft.get(T_LOSS, 0.0))
		if top.is_empty() or _scale_rank(str(theft.get(T_SCALE, ""))) \
				>= _scale_rank(str(top.get(T_SCALE, ""))):
			top = theft
	var stock: int = int(context.get(C_STOCK, 0))
	var mismatch: bool = missing > Database.get_balance_int(B_TOLERANCE)
	var report: Dictionary = {
		R_WEEK: int(context.get(C_WEEK, 0)), R_DAY: int(context.get(C_DAY, 0)),
		R_PRODUCED: int(context.get(C_PRODUCED, 0)), R_EXPECTED: stock,
		R_COUNTED: maxi(stock - missing, 0), R_MISSING: missing, R_LOSS: loss,
		R_THEFTS: thefts.size(), R_MISMATCH: mismatch, R_ABSORBED: missing > 0 and not mismatch,
		R_SCALE: str(top.get(T_SCALE, "")), R_INCIDENT_DAY: int(top.get(T_DAY, 0)),
		R_ROOM: str(Database.get_balance(B_COUNT_ROOM)), R_POINTS_TO: "", R_FRAMED_TO: "",
		R_CFO: false, R_WEIGHT: 0.0, R_SEVERITY: 0, R_REPORTED: false,
	}
	if mismatch:
		_attribute(report, context)
	return report


## A quién apunta el descuadre, con qué peso y gravedad (mayor escala; CFO en los márgenes).
static func _attribute(report: Dictionary, context: Dictionary) -> void:
	var cfg: Dictionary = get_scale_config(str(report[R_SCALE]))
	var forged: String = str(context.get(C_FORGED, ""))
	var cfo: String = str(context.get(C_CFO, ""))
	var in_margins: bool = _strings(Database.get_balance(B_MARGIN_SCALES)) \
			.has(str(report[R_SCALE])) and not cfo.is_empty()
	var weight: float = float(cfg.get(S_WEIGHT, 0.0))
	if in_margins:
		weight *= Database.get_balance_float(B_CFO_FACTOR)
	report[R_WEIGHT] = weight
	report[R_SEVERITY] = int(cfg.get(S_SEVERITY, 0))
	report[R_CFO] = in_margins
	report[R_FRAMED_TO] = forged
	if not forged.is_empty():
		report[R_POINTS_TO] = forged
	elif bool(context.get(C_RESPONSIBLE, false)):
		report[R_POINTS_TO] = PLAYER_ID


# ─── Entrega a Security (manos, week_closed) ─────────────────

## Conecta el recuento a week_closed (idempotente). Las manos la llaman al empezar/cargar partida.
static func connect_calendar() -> void:
	var callback: Callable = FactoryTheft._on_week_closed
	if not EventBus.week_closed.is_connected(callback):
		EventBus.week_closed.connect(callback)


static func is_calendar_connected() -> bool:
	return EventBus.week_closed.is_connected(FactoryTheft._on_week_closed)


## Entrega a Security los descuadres que Company destapó y aún no entregó. Devuelve los casos
## ("" = incidente pendiente bajo el umbral de apertura).
static func report_mismatches() -> Array[String]:
	var cases: Array[String] = []
	for report: Dictionary in Company.take_unreported_mismatches():
		cases.append(_report_to_security(report))
	return cases


static func _report_to_security(report: Dictionary) -> String:
	var room: String = str(report[R_ROOM])
	var case_id: String = Security.report_incident(INCIDENT_TYPE, int(report[R_SEVERITY]), room,
			true, {"weight": float(report[R_WEIGHT]), "subject": str(report[R_POINTS_TO]),
			"player_culprit": true, "day": int(report[R_INCIDENT_DAY]), "hour": NO_HOUR})
	var framed: String = str(report[R_FRAMED_TO])
	if framed.is_empty():
		return case_id
	if not case_id.is_empty():
		Security.plant_evidence(case_id, framed, str(Database.get_balance(B_NOTE_EVIDENCE)))
	BeliefNet.create_record(str(Database.get_balance(B_ACCESS_RECORD)), PLAYER_ID,
			Database.get_balance_float(B_ACCESS_WEIGHT), room)
	return case_id


## week_closed: recuento (idempotente; Company ya lo hizo si oyó la señal antes) y entrega.
static func _on_week_closed(week_number: int) -> void:
	Company.run_inventory_count(week_number)
	report_mismatches()


# ─── Internos ─────────────────────────────────────────────────

static func _room_of(options: Dictionary) -> String:
	var room: String = str(options.get("room_id", ""))
	return room if not room.is_empty() else PlayerState.get_room()


static func _accomplice_for(options: Dictionary) -> String:
	var chosen: String = str(options.get("accomplice_id", ""))
	if not chosen.is_empty():
		return chosen if is_accomplice(chosen) else ""
	return find_accomplice()


## Pares pedidos (acotados a la escala) o sorteados con semilla de partida + jornada + nº de robo.
static func _pairs_for(cfg: Dictionary, requested: int) -> int:
	var low: int = int(cfg.get(S_PAIRS_MIN, 0))
	var high: int = maxi(int(cfg.get(S_PAIRS_MAX, low)), low)
	if requested > 0:
		return clampi(requested, low, high)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([RNG_SALT, GameClock.get_run_seed(), GameClock.get_day(),
			Company.get_factory_theft_count()])
	return rng.randi_range(low, high)


static func _scale_rank(scale: String) -> int:
	return SCALES.find(scale)


## Titular de la ocupación que manda en la sala de trabajo (npcs_generation superior_by_room),
## si es un personaje en plantilla distinto del jugador.
static func _room_superior(room_id: String) -> String:
	var occupation: String = Bribery.room_superior_occupation(room_id)
	if occupation.is_empty() or occupation == PlayerState.get_occupation_id():
		return ""
	var holder: String = Company.get_seat_holder(occupation)
	if holder.is_empty() or holder == PLAYER_ID or not NPCDirector.is_active(holder):
		return ""
	return holder


## Superior de su línea: con subordinados, escalón mayor y mismo departamento.
static func _same_line_superior(boss: OccupationData, own: OccupationData) -> bool:
	return bool(boss.extra.get(K_HAS_SUBORDINATES, false)) and boss.tier > own.tier \
			and str(boss.extra.get(K_DEPARTMENT, "")) == str(own.extra.get(K_DEPARTMENT, ""))


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out
