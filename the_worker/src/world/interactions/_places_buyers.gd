# _places_buyers.gd — Los compradores (§11.5, §22.4): la mesa de la sala de demostraciones de P11 (su ficha y las cuatro operaciones: venta honesta, sobreprecio, venta fantasma, descuento con mordida) y el sofá de la sala de espera de la PB donde se les escucha antes de su reunión.
# PROPIETARIO DE: nada (la agenda y la cartera son de Company; la resolución, de Buyers; el dinero, de PlayerState).
# ESCUCHA: nada.
class_name PlacesBuyers
extends RefCounted

## Flujo: lista de visitas de hoy (hora, pedido, estado) → Buyers.can_operate (el motivo si no:
## no ha llegado, ya atendido, tu puesto no vende...) → ficha con los rasgos si los conoces (si no,
## se recuerda cómo conocerlos: escuchar en la sala de espera antes de su hora o leer el archivo de
## clientes VIP) → operación → las fraudulentas se confirman (§13.7) → Buyers.operate → aviso con
## el resultado y lo cobrado. Sin compradores hoy, se dice qué días vienen.

## · "buyer_lounge" (PlacesKeeper, sofá de visitor_lounge; solo se ofrece con compradores esperando
##   su hora): escuchar (lugares.minutos.escucha_compradores) revela sus rasgos
##   (Buyers.overhear_buyers) con una ficha y una nota en el cuaderno.

const T_DEMO := "demo_table"
const T_LOUNGE := "buyer_lounge"
const TYPES: Array[String] = [T_DEMO, T_LOUNGE]
const OP_KEYS: Array[String] = [Buyers.OP_HONEST, Buyers.OP_OVERPRICE, Buyers.OP_PHANTOM, Buyers.OP_KICKBACK]
const TRAIT_PERCEPTION := "perception"
const TRAIT_GREED := "greed"
const TRAIT_LOYALTY := "loyalty"
const STATUS_WAITING := "waiting"
const B_VISIT_DAYS := "compradores.dias_visita_semana"
const ANIM_LISTEN := "phone"
const NOTE_CATEGORY := "buyers"


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if item.interact_type == T_LOUNGE:
		await lounge(item, player, ctx)
		return
	await demo_table(ctx)


static func is_available(item: Interactable) -> bool:
	return item.interact_type != T_LOUNGE or not waiting_buyers().is_empty()


## Visitas de hoy que aún esperan su hora (se les puede escuchar en la sala de espera).
static func waiting_buyers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for visit: Dictionary in Company.get_buyers_today():
		if str(visit.get("status", "")) == STATUS_WAITING and GameClock.get_hour() < int(visit.get("hour", 0)):
			out.append(visit)
	return out


## Sala de espera: escuchar a los compradores antes de su reunión revela sus rasgos.
static func lounge(item: Interactable, player: Node, ctx: Dictionary) -> void:
	PlacesKit.play(player, ANIM_LISTEN)
	PlacesKit.spend_minutes("escucha_compradores")
	var result: Dictionary = Buyers.overhear_buyers(item.room_id)
	var revealed: Array = result.get("revealed", [])
	if revealed.is_empty():
		PlacesKit.refuse(ctx, Buyers.get_reason_label_key(str(result.get("reason", ""))))
		return
	var lines: Array[String] = []
	for buyer_id: Variant in revealed:
		var visit: Dictionary = Company.get_buyer_visit(str(buyer_id))
		var line: String = PlacesKit.tr_key("PLACES_BUYER_OVERHEARD") % [str(visit.get("name", "")), traits_text(visit)]
		lines.append(line)
		PlacesKit.note(NOTE_CATEGORY, "PLACES_NOTE_BUYER", [line])
	await PlacesKit.show_lines(ctx, "PLACES_BUYER_LOUNGE_TITLE", lines)


static func demo_table(ctx: Dictionary) -> void:
	var visits: Array[Dictionary] = Company.get_buyers_today()
	if visits.is_empty():
		PlacesKit.say(ctx, "PLACES_BUYERS_NONE", [visit_days_text()])
		return
	var options: Array = []
	for visit: Dictionary in visits:
		options.append(visit_option(visit))
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_BUYERS_TITLE", "PLACES_BUYERS_BODY", options, [visits.size()])
	if index < 0 or index >= visits.size():
		return
	await deal(ctx, visits[index])


static func visit_option(visit: Dictionary) -> Dictionary:
	var waiting: bool = str(visit.get("status", "")) == STATUS_WAITING
	var status: String = PlacesKit.tr_key("PLACES_BUYER_WAITING") if waiting \
			else PlacesKit.tr_key(Buyers.get_outcome_label_key(str(visit.get("outcome", ""))))
	return {"text_key": "PLACES_BUYER_VISIT", "disabled": not waiting, "args": [str(visit.get("name", "")),
			PlacesKit.tr_key(str(visit.get("firm_key", ""))), int(visit.get("pairs", 0)),
			int(visit.get("order_value", 0)), UITheme.format_hour(int(visit.get("hour", 0))), status]}


## Días de la semana con visitas (1 = primera jornada de la semana), para el aviso.
static func visit_days_text() -> String:
	var days: PackedStringArray = PackedStringArray()
	for day: String in PlacesKit.bal_strings(B_VISIT_DAYS):
		days.append(day)
	return PlacesKit.NAME_JOIN.join(days)


static func deal(ctx: Dictionary, visit: Dictionary) -> void:
	var buyer_id: String = str(visit.get("buyer_id", ""))
	var check: Dictionary = Buyers.can_operate(buyer_id)
	if not bool(check.get("allowed", false)):
		PlacesKit.refuse(ctx, Buyers.get_reason_label_key(str(check.get("reason", ""))))
		return
	var operation: String = await pick_operation(ctx, visit)
	if operation.is_empty():
		return
	var label: String = PlacesKit.tr_key(Buyers.get_operation_label_key(operation))
	if operation != Buyers.OP_HONEST and not await PlacesKit.confirm(ctx, "PLACES_BUYERS_TITLE",
			"PLACES_BUYERS_CONFIRM", "PLACES_BUYERS_GO", [label, str(visit.get("name", ""))]):
		return
	report(ctx, Buyers.operate(buyer_id, operation))


static func pick_operation(ctx: Dictionary, visit: Dictionary) -> String:
	var options: Array = []
	for operation: String in OP_KEYS:
		options.append(Buyers.get_operation_label_key(operation))
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_BUYERS_TITLE", "PLACES_BUYER_CARD", options,
			[str(visit.get("name", "")), traits_text(visit)])
	return OP_KEYS[index] if index >= 0 and index < OP_KEYS.size() else ""


## Rasgos del comprador si el jugador los conoce; si no, cómo conocerlos.
static func traits_text(visit: Dictionary) -> String:
	var traits: Dictionary = visit.get("traits", {}) if visit.get("traits", {}) is Dictionary else {}
	if not bool(visit.get("traits_known", false)) or traits.is_empty():
		return PlacesKit.tr_key("PLACES_BUYER_TRAITS_UNKNOWN") % UITheme.format_hour(int(visit.get("hour", 0)))
	return PlacesKit.tr_key("PLACES_BUYER_TRAITS") % [int(traits.get(TRAIT_PERCEPTION, 0)),
			int(traits.get(TRAIT_GREED, 0)), int(traits.get(TRAIT_LOYALTY, 0))]


static func report(ctx: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, Buyers.get_reason_label_key(str(result.get("reason", ""))))
		return
	var outcome: String = PlacesKit.tr_key(Buyers.get_outcome_label_key(str(result.get("outcome", ""))))
	if str(result.get("outcome", "")) == Buyers.OUTCOME_SOLD:
		PlacesKit.good(ctx, "PLACES_BUYERS_DONE", [outcome, int(result.get("income", 0))], PlacesKit.SFX_CASH)
	else:
		PlacesKit.bad(ctx, "PLACES_BUYERS_FAILED", [outcome])
