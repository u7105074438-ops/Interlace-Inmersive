# factory_theft.gd — Robo en fábrica (§11.6): las tres escalas con sus requisitos, el producto robado como contrabando hasta su reventa, el recuento semanal que destapa el descuadre con retardo y los albaranes falsificados que lo desvían.
# PROPIETARIO DE: nada (robos sin recontar, albaranes de la semana, recuentos y lotes robados pendientes de reventa los guarda Company; dinero, inventario y registros, PlayerState/BeliefNet; los casos, Security).
# ESCUCHA: week_closed (conexión que cablea Company al arrancar, connect_calendar: entrega a Security el descuadre del recuento de esa semana).
class_name FactoryTheft
extends RefCounted

## Manual §11.3, §11.6, §9.4 («semanal: primera señal visible de los robos»), §9.10, §12.3; PASO 41;
## BUILD_NOTES §2 (manos), §12, §13.
## MANOS DEL MUNDO (InteractionRouter):
##  · product_shelf de la nave (goods_shelf_*: data.scale ⊂ pocket|box), goods_pallets y
##    dock_carrier_bay (pallet): check_requirements(escala, opciones) → {allowed, missing ⊂ scale|
##    location|rank|occupation|cart|accomplice|stock|limit|capacity} para el aviso
##    (get_missing_label_key) y steal(escala, opciones) para el acto. opciones: pairs (0 = sorteo en
##    el intervalo de la escala), cart (el jugador empuja un carrito), accomplice_id ("" = el mejor
##    transportista cómplice), room_id ("" = sala actual).
##  · product_shelf con data.accepts_stolen_product (store_display de flagship_store, PB): NO es un
##    robo: fence(sala) revende el producto robado que lleva el jugador (salas fabrica.salas_reventa).
##  · product_shelf de la nave con producto robado encima: return_goods(sala) lo devuelve antes
##    del recuento («inventario compensado», §12.3): el descuadre de la semana mengua.
##  · delivery_notes (fabrica.salas_albaranes): forge_delivery_notes(sala).
##  · connect_calendar() lo llama Company al arrancar (idempotente): las manos no tienen que hacerlo.
## DECISIONES:
##  · Requisitos (§11.6): sala de la nave (planta mundo.planta_fabrica); rango ≥ rango_min; palé:
##    ocupación capataz o director de fábrica; caja: carrito (fabrica.objetos_carro u opción cart) o
##    acreditación ≥ la de fabrica.sala_montacargas; palé: transportista cómplice (puesto o rol de
##    fabrica.puestos_transportista, en plantilla, con deuda ≥ deuda_minima_complice o afecto ≥
##    afecto_minimo_complice; el director de fábrica —fabrica.ocupaciones_contratan_complices—
##    «contrata» a cualquiera). «No un botón de generación de capital»: existencias
##    (Company.get_finished_goods_stock ≥ pares), tope semanal por escala (max_por_semana robos sin
##    recontar) y hueco en el inventario para el objeto de la escala.
##  · Contrabando (§11.3): bolsillo = objeto_por_par pares product_pair; caja = un product_box
##    (voluminoso); ambos comprometedores y se cobran AL REVENDERLOS (fence: lotes FIFO de Company,
##    ingreso = interpolación ingreso_min..max según los pares). Palé: el cómplice se lleva y vende la
##    carga en el acto (ingreso inmediato) y el jugador se queda la nota de carga
##    (product_pallet_note, documento comprometedor). El cómplice gasta deuda_por_pale de su deuda (o
##    afecto_por_pale de afecto) y es testigo: creencia hecho_complice con certeza_complice.
##  · crime_committed("theft_product", sala, {value: valor de reventa, quantity: pares, scale,
##    company_loss, loss_booked: true, leaves_record: false, accomplice, theft_id, item_id}): NADA se
##    detecta en el acto (ni incidente ni pérdida en costes); Tracking suma ORO y DutySystem descuenta
##    la cuota. Pérdida de la compañía = pares × precio medio × factor_coste_margenes de la escala
##    (palé: la carga desaparecida cuesta también reposición urgente, penalización y auditoría).
##  · RECUENTO SEMANAL (Company.run_inventory_count en week_closed; build_count_report es puro):
##    hasta fabrica.tolerancia_recuento_pares es merma absorbida; por encima, descuadre. Incidente
##    «inventory_mismatch» con el peso inicial de investigations.json (§12.3: 2,0, bajo el umbral de
##    3,0) × lotes: un lote por robo por encima de la tolerancia (mínimo 1) + lotes_por_semana_previa
##    por cada semana anterior seguida con descuadre (patrón). Una caja suelta queda pendiente en
##    Security; dos, o una segunda semana seguida, abren caso. Gravedad = la de la mayor escala +
##    gravedad_por_lote_extra por lote extra. Escalas de escalas_visibles_margenes (palé): pérdida
##    de un día entero en los márgenes y el CFO (ocupacion_cfo, si es un personaje) lo detecta: pieza
##    tipo_evidencia_cfo (rastro contable) con el CFO como testigo. subject: el superior de los
##    albaranes; si no, el jugador si responde del inventario (capataz); si no, nadie (la
##    investigación busca con sus procedimientos). Un descuadre solo se entrega en su semana. El
##    incidente lleva el día de la mayor sustracción (las cámaras de ese día): pendiente bajo el
##    umbral, caduca con seguridad.dias_acumulacion_incidentes; la acumulación entre semanas la
##    lleva Company (racha). «Inventario compensado» (§12.3): return_goods() antes del recuento.
##  · ALBARANES (§11.6 «incriminación», oportunidad exclusiva del capataz: fabrica.ocupaciones_
##    albaranes): el recuento de ESTA semana apunta al superior directo. crime_committed("forgery")
##    (BeliefNet: documento sin verificar contra él; SEDA) y ("framing"). Los albaranes de una
##    estación "traceable" (muelle) dejan registro card_log del jugador (peso_registro_albaran_
##    trazable). Al entregar: los albaranes documentan el desvío → el caso se abre siempre
##    (always_opens) con la pieza forged_document contra el superior (Security.plant_evidence) y un
##    registro de acceso del jugador a la sala del recuento: también tenía acceso.

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
const MISSING_STOCK := "stock"
const MISSING_LIMIT := "limit"
const MISSING_CAPACITY := "capacity"
const MISSING_LABEL_KEYS: Dictionary = {
	MISSING_SCALE: "FACTORY_MISSING_SCALE", MISSING_LOCATION: "FACTORY_MISSING_LOCATION",
	MISSING_RANK: "FACTORY_MISSING_RANK", MISSING_OCCUPATION: "FACTORY_MISSING_OCCUPATION",
	MISSING_CART: "FACTORY_MISSING_CART", MISSING_ACCOMPLICE: "FACTORY_MISSING_ACCOMPLICE",
	MISSING_STOCK: "FACTORY_MISSING_STOCK", MISSING_LIMIT: "FACTORY_MISSING_LIMIT",
	MISSING_CAPACITY: "FACTORY_MISSING_CAPACITY",
}
const REASON_REQUIREMENTS := "requirements"
const REASON_NOT_AT_NOTES := "not_at_delivery_notes"
const REASON_NOT_FOREMAN := "not_foreman"
const REASON_NO_SUPERIOR := "no_superior"
const REASON_NOT_AT_FENCE := "not_at_fence"
const REASON_NOTHING_TO_FENCE := "nothing_to_fence"
const REASON_NOT_IN_FACTORY := "not_in_factory"
const REASON_LABEL_KEYS: Dictionary = {
	REASON_NOT_AT_NOTES: "FACTORY_REASON_NOT_AT_NOTES",
	REASON_NOT_FOREMAN: "FACTORY_REASON_NOT_FOREMAN",
	REASON_NO_SUPERIOR: "FACTORY_REASON_NO_SUPERIOR",
	REASON_NOT_AT_FENCE: "FACTORY_REASON_NOT_AT_FENCE",
	REASON_NOTHING_TO_FENCE: "FACTORY_REASON_NOTHING_TO_FENCE",
	REASON_NOT_IN_FACTORY: "FACTORY_REASON_NOT_IN_FACTORY",
}

const CRIME_THEFT := "theft_product"
const CRIME_FORGERY := "forgery"
const CRIME_FRAMING := "framing"
const DOCUMENT_DELIVERY_NOTE := "delivery_note"
const FRAMING_METHOD := "delivery_notes"
const INCIDENT_TYPE := "inventory_mismatch"
const MONEY_REASON_FORMAT := "factory_theft_%s"
const MONEY_REASON_FENCE := "factory_fence"
const DISPOSE_SOLD := "sold"
const DISPOSE_RETURNED := "returned"
const NOTES_INTERACTABLE := "delivery_notes"
const TRACEABLE_KEY := "traceable"
const RNG_SALT := "factory_theft"
## Hora de incidente desconocida (Security revisa la jornada entera).
const NO_HOUR := -1
## Escalón «ninguno» para buscar el mínimo (por encima del máximo real).
const NO_TIER := OccupationData.MAX_TIER + 1
const NO_RANK := -1
const K_AVG_PRICE := "avg_price"
const K_HAS_SUBORDINATES := "has_subordinates"
const K_DEPARTMENT := "department"
const P_TRIGGERS := "incident_triggers"
const P_TRIGGER_WEIGHT := "initial_weight"
const P_EVIDENCE := "evidence_types"
const P_EVIDENCE_PATH := "balance_path"
const P_EVIDENCE_WEIGHT := "weight"
const P_SEVERITIES := "severity_levels"
const P_LEVEL := "level"

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
const C_STREAK := "mismatch_streak"

# Claves de un informe de recuento (Company.get_inventory_reports()).
const R_WEEK := "week"
const R_DAY := "day"
## Producción de la semana (pares fabricados y ya despachados): un flujo, NO comparable con
## expected/counted, que son el stock físico del almacén (QA §11.6: antes se llamaba "produced").
const R_PRODUCED := "week_output_shipped"
const R_EXPECTED := "expected"
const R_COUNTED := "counted"
const R_MISSING := "missing"
const R_LOSS := "loss"
const R_MARGIN_LOSS := "margin_loss"
const R_THEFTS := "thefts"
const R_MISMATCH := "mismatch"
const R_ABSORBED := "absorbed"
const R_SCALE := "scale"
const R_INCIDENT_DAY := "incident_day"
const R_ROOM := "room"
const R_POINTS_TO := "points_to"
const R_FRAMED_TO := "framed_to"
const R_CFO := "cfo_detected"
const R_CFO_ID := "cfo_id"
const R_LOTS := "lots"
const R_WEIGHT := "weight"
const R_SEVERITY := "severity"
const R_REPORTED := "reported"
const REPORT_INT_KEYS: Array[String] = [
	R_WEEK, R_PRODUCED, R_EXPECTED, R_COUNTED, R_MISSING, R_THEFTS, R_INCIDENT_DAY, R_SEVERITY,
	R_LOTS,
]

const B_SCALE := "fabrica.escalas.%s"
const B_TOLERANCE := "fabrica.tolerancia_recuento_pares"
const B_COUNT_ROOM := "fabrica.sala_recuento"
const B_NOTES_ROOMS := "fabrica.salas_albaranes"
const B_NOTES_POSTS := "fabrica.ocupaciones_albaranes"
const B_CART_ITEMS := "fabrica.objetos_carro"
const B_FREIGHT_ROOM := "fabrica.sala_montacargas"
const B_CARRIER_POSTS := "fabrica.puestos_transportista"
const B_HIRING_POSTS := "fabrica.ocupaciones_contratan_complices"
const B_ACCOMPLICE_DEBT := "fabrica.deuda_minima_complice"
const B_ACCOMPLICE_AFFECTION := "fabrica.afecto_minimo_complice"
const B_DEBT_PER_PALLET := "fabrica.deuda_por_pale"
const B_AFFECTION_PER_PALLET := "fabrica.afecto_por_pale"
const B_ACCOMPLICE_FACT := "fabrica.hecho_complice"
const B_ACCOMPLICE_CERTAINTY := "fabrica.certeza_complice"
const B_MARGIN_SCALES := "fabrica.escalas_visibles_margenes"
const B_CFO_EVIDENCE := "fabrica.tipo_evidencia_cfo"
const B_STREAK_LOTS := "fabrica.lotes_por_semana_previa"
const B_SEVERITY_PER_LOT := "fabrica.gravedad_por_lote_extra"
const B_NOTE_EVIDENCE := "fabrica.tipo_evidencia_albaran"
const B_ACCESS_RECORD := "fabrica.tipo_registro_acceso"
const B_ACCESS_WEIGHT := "fabrica.peso_registro_acceso"
const B_TRACE_WEIGHT := "fabrica.peso_registro_albaran_trazable"
const B_FENCE_ROOMS := "fabrica.salas_reventa"
const B_FENCE_ITEMS := "fabrica.objetos_reventa"
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
const S_SEVERITY := "gravedad"
const S_WEEKLY_MAX := "max_por_semana"
const S_ITEM := "objeto"
const S_ITEM_PER_PAIR := "objeto_por_par"
const S_PAID_AT_FENCE := "cobro_al_revender"
const S_MARGIN_FACTOR := "factor_coste_margenes"


# ─── Requisitos (§11.6) ───────────────────────────────────────

## Configuración de una escala ({} si no existe).
static func get_scale_config(scale: String) -> Dictionary:
	var path: String = B_SCALE % scale
	if not SCALES.has(scale) or not Database.has_balance(path):
		return {}
	var value: Variant = Database.get_balance(path)
	return value as Dictionary if value is Dictionary else {}


## {allowed: bool, missing: Array[String]} con missing ⊂ scale, location, rank, occupation, cart,
## accomplice, stock, limit, capacity (todas las condiciones que faltan, para el aviso).
static func check_requirements(scale: String, options: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = get_scale_config(scale)
	var missing: Array[String] = []
	if cfg.is_empty():
		missing.append(MISSING_SCALE)
	else:
		_check_access(cfg, options, missing)
		_check_goods(scale, cfg, options, missing)
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
## algo al jugador, le tiene suficiente afecto o el jugador contrata transportistas (director).
static func is_accomplice(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not NPCDirector.is_active(npc_id):
		return false
	var posts: Array[String] = _strings(Database.get_balance(B_CARRIER_POSTS))
	if not posts.has(npc.occupation_id) and not posts.has(NPCDirector.get_role(npc_id)):
		return false
	return hires_accomplices() or _owes_player(npc_id) \
			or NPCDirector.get_affection(npc_id) >= Database.get_balance_int(B_ACCOMPLICE_AFFECTION)


## «Contratación de transportistas cómplices» (§23.6): el puesto del jugador los contrata.
static func hires_accomplices() -> bool:
	return _strings(Database.get_balance(B_HIRING_POSTS)).has(PlayerState.get_occupation_id())


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
		if best.is_empty() or debt > best_debt \
				or (debt == best_debt and affection > best_affection):
			best = npc.id
			best_debt = debt
			best_affection = affection
	return best


## Robos de esa escala desde el último recuento (el tope semanal los cuenta).
static func weekly_count(scale: String) -> int:
	var count: int = 0
	for theft: Dictionary in Company.get_pending_factory_thefts():
		if str(theft.get(T_SCALE, "")) == scale:
			count += 1
	return count


## Cabe en el inventario (una pila ya empezada o una posición libre); "" = nada que llevar.
static func can_carry(item_id: String) -> bool:
	if item_id.is_empty():
		return true
	if InventoryRules.is_stackable(InventoryRules.make_item(item_id)) \
			and PlayerState.is_carrying(item_id):
		return true
	return PlayerState.get_free_slots() > 0


static func get_missing_label_key(missing: String) -> String:
	return str(MISSING_LABEL_KEYS.get(missing, ""))


static func get_scale_label_key(scale: String) -> String:
	return str(SCALE_LABEL_KEYS.get(scale, ""))


## Texto de los motivos de forge_delivery_notes y fence.
static func get_reason_label_key(reason: String) -> String:
	return str(REASON_LABEL_KEYS.get(reason, ""))


# ─── El acto ──────────────────────────────────────────────────

## Ejecuta el robo si se cumplen los requisitos. {ok, scale, pairs, income (cobrado ahora: solo el
## palé), resale_value, item_id, company_loss, theft_id, accomplice, reason, missing}. Nada se
## detecta ahora: aflora en el recuento semanal.
static func steal(scale: String, options: Dictionary = {}) -> Dictionary:
	var check: Dictionary = check_requirements(scale, options)
	if not bool(check["allowed"]):
		return {"ok": false, "scale": scale, "reason": REASON_REQUIREMENTS,
				"missing": check["missing"]}
	var cfg: Dictionary = get_scale_config(scale)
	var pairs: int = mini(_pairs_for(cfg, int(options.get("pairs", 0))),
			Company.get_finished_goods_stock())
	var value: int = income_for(scale, pairs)
	var loss: float = loss_for(scale, pairs)
	var room: String = _room_of(options)
	var accomplice: String = _accomplice_for(options) if bool(cfg.get(S_ACCOMPLICE, false)) else ""
	var theft_id: String = Company.register_factory_theft(scale, pairs, loss, room)
	var paid: int = _hand_over(scale, cfg, pairs, value)
	if not accomplice.is_empty():
		_use_accomplice(accomplice, room)
	var item_id: String = str(cfg.get(S_ITEM, ""))
	EventBus.crime_committed.emit(CRIME_THEFT, room, {
		"value": value, "quantity": pairs, "scale": scale, "company_loss": loss,
		"loss_booked": true, "leaves_record": false, "accomplice": accomplice,
		"theft_id": theft_id, "item_id": item_id,
	})
	return {"ok": true, "scale": scale, "pairs": pairs, "income": paid, "resale_value": value,
			"item_id": item_id, "company_loss": loss, "theft_id": theft_id,
			"accomplice": accomplice, "reason": "", "missing": []}


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


## Pérdida de la compañía por el robo: pares × precio medio × factor_coste_margenes de la escala.
static func loss_for(scale: String, pairs: int) -> float:
	var factor: float = float(get_scale_config(scale).get(S_MARGIN_FACTOR, 1.0))
	return pairs * unit_loss() * factor


## Sala de reventa del producto robado (fabrica.salas_reventa).
static func is_fence_room(room_id: String) -> bool:
	return _strings(Database.get_balance(B_FENCE_ROOMS)).has(InvestigationEngine.base_room(room_id))


## Revende todo el producto robado que lleva el jugador (fabrica.objetos_reventa): cada unidad al
## valor de su lote (Company, FIFO) o, sin lote, al de su escala. {ok, reason, income, units}.
static func fence(room_id: String = "") -> Dictionary:
	var room: String = room_id if not room_id.is_empty() else PlayerState.get_room()
	if not is_fence_room(room):
		return _fence_result(false, REASON_NOT_AT_FENCE, 0, 0)
	var goods: Dictionary = _fence_goods()
	var income: int = 0
	var units: int = 0
	for item_id: String in goods:
		var count: int = PlayerState.get_item_count(item_id)
		for i: int in count:
			PlayerState.dispose_item(item_id, DISPOSE_SOLD)
		if count > 0:
			income += _resale_income(item_id, str(goods[item_id]), count)
			units += count
	if units == 0:
		return _fence_result(false, REASON_NOTHING_TO_FENCE, 0, 0)
	PlayerState.add_money(income, MONEY_REASON_FENCE)
	return _fence_result(true, "", income, units)


## «Inventario compensado» (§12.3 palanca de fase 1): devolver a la nave el producto robado que
## se lleva encima; sus pares se restan de los robos sin recontar (el jugador renuncia a su
## reventa). {ok, reason, units, pairs (compensados)}.
static func return_goods(room_id: String = "") -> Dictionary:
	var room: String = room_id if not room_id.is_empty() else PlayerState.get_room()
	if not is_factory_room(room):
		return {"ok": false, "reason": REASON_NOT_IN_FACTORY, "units": 0, "pairs": 0}
	var goods: Dictionary = _fence_goods()
	var units: int = 0
	var pairs: int = 0
	for item_id: String in goods:
		var count: int = PlayerState.get_item_count(item_id)
		for i: int in count:
			PlayerState.dispose_item(item_id, DISPOSE_RETURNED)
		if count > 0:
			var taken: Dictionary = Company.take_stolen_goods(item_id, count)
			var uncovered: int = maxi(count - int(taken.get("units", 0)), 0)
			pairs += int(taken.get("pairs", 0)) + uncovered * _fallback_unit_pairs(str(goods[item_id]))
			units += count
	if units == 0:
		return {"ok": false, "reason": REASON_NOTHING_TO_FENCE, "units": 0, "pairs": 0}
	return {"ok": true, "reason": "", "units": units,
			"pairs": Company.compensate_factory_thefts(pairs)}


## Albaranes falsificados (§11.6 «incriminación»): el recuento de esta semana apunta al superior
## directo. Solo el capataz (fabrica.ocupaciones_albaranes). {ok, target, reason, traced}.
static func forge_delivery_notes(room_id: String = "") -> Dictionary:
	var room: String = room_id if not room_id.is_empty() else PlayerState.get_room()
	var reason: String = _forge_refusal(room)
	var target: String = find_direct_superior() if reason.is_empty() else ""
	if reason.is_empty() and target.is_empty():
		reason = REASON_NO_SUPERIOR
	if not reason.is_empty():
		return {"ok": false, "target": "", "reason": reason, "traced": false}
	Company.set_forged_delivery_target(target)
	EventBus.crime_committed.emit(CRIME_FORGERY, room, {"subject": target, "target": target,
			"document": DOCUMENT_DELIVERY_NOTE})
	EventBus.crime_committed.emit(CRIME_FRAMING, room, {"target": target,
			"method": FRAMING_METHOD})
	var traced: bool = is_traceable_notes(room)
	if traced:
		BeliefNet.create_record(str(Database.get_balance(B_ACCESS_RECORD)), PLAYER_ID,
				Database.get_balance_float(B_TRACE_WEIGHT), room)
	return {"ok": true, "target": target, "reason": "", "traced": traced}


## La estación de albaranes de esa sala deja constancia de quién los emite (data "traceable").
static func is_traceable_notes(room_id: String) -> bool:
	var room: RoomData = Database.get_room(InvestigationEngine.base_room(room_id))
	if room == null:
		return false
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) == NOTES_INTERACTABLE and bool(entry.get(TRACEABLE_KEY, false)):
			return true
	return false


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
## context = {week, day, stock, produced, forged_target, player_responsible, cfo_holder,
## mismatch_streak}.
static func build_count_report(thefts: Array[Dictionary], context: Dictionary) -> Dictionary:
	var tally: Dictionary = _tally(thefts)
	var stock: int = int(context.get(C_STOCK, 0))
	var missing: int = int(tally[R_MISSING])
	var mismatch: bool = missing > Database.get_balance_int(B_TOLERANCE)
	var report: Dictionary = {
		R_WEEK: int(context.get(C_WEEK, 0)), R_DAY: int(context.get(C_DAY, 0)),
		R_PRODUCED: int(context.get(C_PRODUCED, 0)), R_EXPECTED: stock,
		R_COUNTED: maxi(stock - missing, 0), R_MISSING: missing, R_LOSS: tally[R_LOSS],
		R_MARGIN_LOSS: tally[R_MARGIN_LOSS], R_THEFTS: thefts.size(), R_MISMATCH: mismatch,
		R_ABSORBED: missing > 0 and not mismatch, R_SCALE: tally[R_SCALE],
		R_INCIDENT_DAY: tally[R_INCIDENT_DAY], R_ROOM: str(Database.get_balance(B_COUNT_ROOM)),
		R_POINTS_TO: "", R_FRAMED_TO: "", R_CFO: false, R_CFO_ID: "", R_LOTS: 0, R_WEIGHT: 0.0,
		R_SEVERITY: 0, R_REPORTED: false,
	}
	if mismatch:
		_attribute(report, tally, context)
	return report


## Peso inicial del disparador «inventory_mismatch» (investigations.json, §12.3: 2,0).
static func incident_base_weight() -> float:
	var trigger: Dictionary = InvestigationEngine.find_by_id(
			Database.get_investigation_params().get(P_TRIGGERS, []), INCIDENT_TYPE)
	return float(trigger.get(P_TRIGGER_WEIGHT, 0.0))


## Peso de un tipo de pieza (investigations.json evidence_types, con su clave de balance).
static func evidence_weight(evidence_type: String) -> float:
	var entry: Dictionary = InvestigationEngine.find_by_id(
			Database.get_investigation_params().get(P_EVIDENCE, []), evidence_type)
	var path: String = str(entry.get(P_EVIDENCE_PATH, ""))
	if not path.is_empty() and Database.has_balance(path):
		return Database.get_balance_float(path)
	return float(entry.get(P_EVIDENCE_WEIGHT, 0.0))


## Pares, pérdidas (y las visibles en los márgenes), lotes y mayor escala de los robos.
static func _tally(thefts: Array[Dictionary]) -> Dictionary:
	var margin_scales: Array[String] = _strings(Database.get_balance(B_MARGIN_SCALES))
	var tolerance: int = Database.get_balance_int(B_TOLERANCE)
	var out: Dictionary = {R_MISSING: 0, R_LOSS: 0.0, R_MARGIN_LOSS: 0.0, R_LOTS: 0,
			R_SCALE: "", R_INCIDENT_DAY: 0}
	var top: int = NO_RANK
	for theft: Dictionary in thefts:
		var pairs: int = int(theft.get(T_PAIRS, 0))
		var loss: float = float(theft.get(T_LOSS, 0.0))
		var scale: String = str(theft.get(T_SCALE, ""))
		out[R_MISSING] = int(out[R_MISSING]) + pairs
		out[R_LOSS] = float(out[R_LOSS]) + loss
		if margin_scales.has(scale):
			out[R_MARGIN_LOSS] = float(out[R_MARGIN_LOSS]) + loss
		if pairs > tolerance:
			out[R_LOTS] = int(out[R_LOTS]) + 1
		if _scale_rank(scale) >= top:
			top = _scale_rank(scale)
			out[R_SCALE] = scale
			out[R_INCIDENT_DAY] = int(theft.get(T_DAY, 0))
	return out


## Lotes, peso y gravedad del incidente; CFO en los márgenes; a quién apunta.
static func _attribute(report: Dictionary, tally: Dictionary, context: Dictionary) -> void:
	var cfg: Dictionary = get_scale_config(str(report[R_SCALE]))
	var lots: int = maxi(int(tally[R_LOTS]), 1) \
			+ int(context.get(C_STREAK, 0)) * Database.get_balance_int(B_STREAK_LOTS)
	report[R_LOTS] = lots
	report[R_WEIGHT] = incident_base_weight() * lots
	report[R_SEVERITY] = mini(int(cfg.get(S_SEVERITY, 0))
			+ (lots - 1) * Database.get_balance_int(B_SEVERITY_PER_LOT), _max_severity())
	var cfo: String = str(context.get(C_CFO, ""))
	report[R_CFO] = float(tally[R_MARGIN_LOSS]) > 0.0 and not cfo.is_empty()
	report[R_CFO_ID] = cfo if bool(report[R_CFO]) else ""
	var forged: String = str(context.get(C_FORGED, ""))
	report[R_FRAMED_TO] = forged
	if not forged.is_empty():
		report[R_POINTS_TO] = forged
	elif bool(context.get(C_RESPONSIBLE, false)):
		report[R_POINTS_TO] = PLAYER_ID


# ─── Entrega a Security (week_closed) ────────────────────────

## Conecta la entrega a week_closed (idempotente). La llama Company al arrancar (autoload: existe
## en todo proceso), así que un descuadre nunca depende de que las manos la hayan llamado.
static func connect_calendar() -> void:
	var callback: Callable = FactoryTheft._on_week_closed
	if not EventBus.week_closed.is_connected(callback):
		EventBus.week_closed.connect(callback)


static func is_calendar_connected() -> bool:
	return EventBus.week_closed.is_connected(FactoryTheft._on_week_closed)


## Entrega a Security los descuadres que Company destapó y aún no entregó (week ≥ 0: solo los de
## esa semana; los atrasados caducan sin incidente). Devuelve los casos ("" = incidente
## pendiente bajo el umbral de apertura).
static func report_mismatches(week: int = -1) -> Array[String]:
	var cases: Array[String] = []
	for report: Dictionary in Company.take_unreported_mismatches():
		if week < 0 or int(report[R_WEEK]) == week:
			cases.append(_report_to_security(report))
	return cases


static func _report_to_security(report: Dictionary) -> String:
	var room: String = str(report[R_ROOM])
	var severity: int = int(report[R_SEVERITY])
	var framed: String = str(report[R_FRAMED_TO])
	var details: Dictionary = _incident_details(report)
	details["weight"] = float(report[R_WEIGHT])
	details["always_opens"] = not framed.is_empty()
	var case_id: String = Security.report_incident(INCIDENT_TYPE, severity, room, true, details)
	if bool(report[R_CFO]):
		var evidence: String = str(Database.get_balance(B_CFO_EVIDENCE))
		var seen: Dictionary = _incident_details(report)
		seen.merge({"evidence_type": evidence, "weight": evidence_weight(evidence),
				"witness": str(report[R_CFO_ID])}, true)
		var cfo_case: String = Security.report_incident(INCIDENT_TYPE, severity, room, true, seen)
		case_id = cfo_case if case_id.is_empty() else case_id
	if framed.is_empty():
		return case_id
	if not case_id.is_empty():
		Security.plant_evidence(case_id, framed, str(Database.get_balance(B_NOTE_EVIDENCE)))
	BeliefNet.create_record(str(Database.get_balance(B_ACCESS_RECORD)), PLAYER_ID,
			Database.get_balance_float(B_ACCESS_WEIGHT), room)
	return case_id


static func _incident_details(report: Dictionary) -> Dictionary:
	return {"subject": str(report[R_POINTS_TO]), "player_culprit": true,
			"day": int(report[R_INCIDENT_DAY]), "hour": NO_HOUR}


## week_closed: recuento (idempotente; Company ya lo hizo si oyó la señal antes) y entrega.
static func _on_week_closed(week_number: int) -> void:
	Company.run_inventory_count(week_number)
	report_mismatches(week_number)


# ─── Internos ─────────────────────────────────────────────────

static func _check_access(cfg: Dictionary, options: Dictionary, missing: Array[String]) -> void:
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


## Existencias, tope semanal de la escala y hueco para el objeto.
static func _check_goods(scale: String, cfg: Dictionary, options: Dictionary,
		missing: Array[String]) -> void:
	if Company.get_finished_goods_stock() < _pairs_needed(cfg, int(options.get("pairs", 0))):
		missing.append(MISSING_STOCK)
	if cfg.has(S_WEEKLY_MAX) and weekly_count(scale) >= int(cfg[S_WEEKLY_MAX]):
		missing.append(MISSING_LIMIT)
	if not can_carry(str(cfg.get(S_ITEM, ""))):
		missing.append(MISSING_CAPACITY)


## El producto pasa al inventario; se cobra al revenderlo (lote en Company) o, palé, ya.
static func _hand_over(scale: String, cfg: Dictionary, pairs: int, value: int) -> int:
	var item_id: String = str(cfg.get(S_ITEM, ""))
	var units: int = pairs if bool(cfg.get(S_ITEM_PER_PAIR, false)) else 1
	if not item_id.is_empty():
		var item: ItemData = InventoryRules.make_item(item_id)
		if InventoryRules.is_stackable(item):
			item.stack = units
			PlayerState.add_item_data(item)
		else:
			for i: int in units:
				PlayerState.add_item(item_id)
	if bool(cfg.get(S_PAID_AT_FENCE, false)) and not item_id.is_empty():
		Company.add_stolen_goods(item_id, units, pairs, value)
		return 0
	PlayerState.add_money(value, MONEY_REASON_FORMAT % scale)
	return value


## El cómplice cobra su parte (deuda o afecto; el contratado por el director, nada) y lo ha visto.
static func _use_accomplice(npc_id: String, room: String) -> void:
	if not hires_accomplices():
		if _owes_player(npc_id):
			NPCDirector.add_debt(npc_id, -Database.get_balance_int(B_DEBT_PER_PALLET))
		else:
			NPCDirector.add_affection(npc_id, -Database.get_balance_int(B_AFFECTION_PER_PALLET))
	BeliefNet.create_belief(npc_id, PLAYER_ID, str(Database.get_balance(B_ACCOMPLICE_FACT)),
			Database.get_balance_float(B_ACCOMPLICE_CERTAINTY), Belief.SOURCE_DIRECT, room)


static func _owes_player(npc_id: String) -> bool:
	return NPCDirector.get_debt(npc_id) >= Database.get_balance_int(B_ACCOMPLICE_DEBT)


static func _forge_refusal(room: String) -> String:
	if not _strings(Database.get_balance(B_NOTES_ROOMS)).has(InvestigationEngine.base_room(room)):
		return REASON_NOT_AT_NOTES
	if not _strings(Database.get_balance(B_NOTES_POSTS)).has(PlayerState.get_occupation_id()):
		return REASON_NOT_FOREMAN
	return ""


## {objeto: escala} de lo que se revende.
static func _fence_goods() -> Dictionary:
	var value: Variant = Database.get_balance(B_FENCE_ITEMS)
	return value as Dictionary if value is Dictionary else {}


## Ingreso de `count` unidades: sus lotes FIFO y, las que no tengan lote, al valor de su escala.
static func _resale_income(item_id: String, scale: String, count: int) -> int:
	var taken: Dictionary = Company.take_stolen_goods(item_id, count)
	var uncovered: int = maxi(count - int(taken.get("units", 0)), 0)
	return int(taken.get("income", 0)) + uncovered * _fallback_unit_income(scale)


## Una unidad sin lote: un par (escalas por par) o una caja de pares medios.
static func _fallback_unit_income(scale: String) -> int:
	var cfg: Dictionary = get_scale_config(scale)
	var low: int = maxi(int(cfg.get(S_PAIRS_MIN, 0)), 1)
	if bool(cfg.get(S_ITEM_PER_PAIR, false)):
		return roundi(float(income_for(scale, low)) / low)
	return income_for(scale, (low + int(cfg.get(S_PAIRS_MAX, low))) / 2)


## Pares de una unidad sin lote: uno (escalas por par) o una caja de pares medios.
static func _fallback_unit_pairs(scale: String) -> int:
	var cfg: Dictionary = get_scale_config(scale)
	var low: int = maxi(int(cfg.get(S_PAIRS_MIN, 0)), 1)
	return 1 if bool(cfg.get(S_ITEM_PER_PAIR, false)) \
			else (low + int(cfg.get(S_PAIRS_MAX, low))) / 2


static func _fence_result(ok: bool, reason: String, income: int, units: int) -> Dictionary:
	return {"ok": ok, "reason": reason, "income": income, "units": units}


static func _room_of(options: Dictionary) -> String:
	var room: String = str(options.get("room_id", ""))
	return room if not room.is_empty() else PlayerState.get_room()


static func _accomplice_for(options: Dictionary) -> String:
	var chosen: String = str(options.get("accomplice_id", ""))
	if not chosen.is_empty():
		return chosen if is_accomplice(chosen) else ""
	return find_accomplice()


static func _pairs_needed(cfg: Dictionary, requested: int) -> int:
	var low: int = int(cfg.get(S_PAIRS_MIN, 0))
	return clampi(requested, low, maxi(int(cfg.get(S_PAIRS_MAX, low)), low)) \
			if requested > 0 else low


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


## Gravedad máxima de investigations.json (severity_levels).
static func _max_severity() -> int:
	var top: int = 0
	for level: Variant in Database.get_investigation_params().get(P_SEVERITIES, []):
		if level is Dictionary:
			top = maxi(top, int((level as Dictionary).get(P_LEVEL, 0)))
	return top


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
