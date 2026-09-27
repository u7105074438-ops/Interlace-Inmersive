# market_trading.gd — "Manos" de la cartera (§9.11) y del bucle insider (§9.8): mueve el efectivo entre PlayerState y la cuenta de valores de Market, cobra los soplos y opera mediante testaferros.
# PROPIETARIO DE: nada (librería sin estado: el efectivo es de PlayerState; acciones y cuenta de valores, de Market).
# ESCUCHA: nada.
class_name MarketTrading
extends RefCounted

## La UI (aplicación MARKET de StellarOS, lounge de inversores) usa ESTAS funciones, no las de
## Market directamente: Market (autoload) no puede tocar el dinero de PlayerState (BUILD_NOTES §2).
##   buy(n) / sell(n) / buy_board_stake(): ingresan en la cuenta lo que falte y operan; la venta
##          devuelve el importe al bolsillo. Si la operación falla, lo ingresado vuelve.
##   collect_broker_cash(): retira todo lo de la cuenta (dividendos de la junta anual incluidos).
##   sell_tip(investor_id): soplo al cazador (+12, prueba de delito) y cobro de su pago.
##   recruit_proxy(npc_id, importe, canal): soborno con el favor mercado.favor_testaferro.
##   buy_via_proxy / sell_via_proxy: no suman al patrón del jugador; si la operación es
##          privilegiada, el testaferro pasa a ser testigo (creencia directa sobre el jugador).

const PLAYER_ID := "player"
const REASON_DEPOSIT := "broker_deposit"
const REASON_WITHDRAW := "broker_withdrawal"
const REASON_TIP := "insider_tip_payment"
const FACT_PROXY_WITNESS := "caught_redhanded:insider_trade"
const SOURCE_DIRECT := "direct"


## Compra `quantity` acciones pagando con el efectivo del jugador.
static func buy(quantity: int) -> bool:
	if quantity <= 0 or not Market.can_trade():
		return false
	var deposited: int = _fund(Market.get_buy_cost(quantity))
	if deposited < 0:
		return false
	if Market.buy_shares(quantity):
		return true
	_refund(deposited)
	return false


## Vende y devuelve el importe al bolsillo del jugador.
static func sell(quantity: int) -> bool:
	var proceeds: int = Market.get_sell_proceeds(quantity)
	if not Market.sell_shares(quantity):
		return false
	_refund(proceeds)
	return true


## R30: el paquete accionarial (~250.000 €) con voto en el consejo.
static func buy_board_stake() -> bool:
	if Market.has_board_stake():
		return false
	var deposited: int = _fund(Market.get_board_stake_price())
	if deposited < 0:
		return false
	if Market.buy_board_stake():
		return true
	_refund(deposited)
	return false


static func deposit(amount: int) -> bool:
	if amount <= 0 or not PlayerState.spend_money(amount, REASON_DEPOSIT):
		return false
	return Market.deposit_cash(amount)


static func withdraw(amount: int) -> bool:
	if not Market.withdraw_cash(amount):
		return false
	PlayerState.add_money(amount, REASON_WITHDRAW)
	return true


## Retira todo el efectivo de la cuenta de valores (p. ej. los dividendos). Devuelve el importe.
static func collect_broker_cash() -> int:
	var amount: int = Market.get_broker_cash()
	return amount if withdraw(amount) else 0


## Vende un soplo privilegiado: {ok, delta (confianza), paid (€)}.
static func sell_tip(investor_id: String) -> Dictionary:
	if not Market.accepts_tips(investor_id):
		return {"ok": false, "delta": 0, "paid": 0}
	var delta: int = Market.give_insider_tip(investor_id)
	var paid: int = Market.get_tip_payment(investor_id)
	if paid > 0:
		PlayerState.add_money(paid, REASON_TIP)
	return {"ok": true, "delta": delta, "paid": paid}


## Contramedida §9.8: recluta un testaferro sobornándolo (Market lo registra al oír bribe_result).
static func recruit_proxy(npc_id: String, amount: int, channel_id: String,
		ctx: Dictionary = {}) -> Dictionary:
	return Bribery.offer_to(npc_id, amount,
			str(Database.get_balance("mercado.favor_testaferro")), channel_id, ctx)


static func buy_via_proxy(npc_id: String, quantity: int) -> bool:
	if quantity <= 0 or not Market.is_proxy(npc_id) or not Market.can_trade():
		return false
	var informed: bool = Market.is_trade_informed(MarketSystem.TRADE_BUY)
	var deposited: int = _fund(Market.get_buy_cost(quantity))
	if deposited < 0:
		return false
	if not Market.buy_shares_via_proxy(npc_id, quantity):
		_refund(deposited)
		return false
	if informed:
		_make_witness(npc_id)
	return true


static func sell_via_proxy(npc_id: String, quantity: int) -> bool:
	var informed: bool = Market.is_trade_informed(MarketSystem.TRADE_SELL)
	var proceeds: int = Market.get_sell_proceeds(quantity)
	if not Market.sell_shares_via_proxy(npc_id, quantity):
		return false
	_refund(proceeds)
	if informed:
		_make_witness(npc_id)
	return true


## Ingresa en la cuenta lo que falte para `cost`. Devuelve lo ingresado (−1 si no hay fondos).
static func _fund(cost: int) -> int:
	var shortfall: int = maxi(cost - Market.get_broker_cash(), 0)
	if shortfall == 0:
		return 0
	if not PlayerState.can_afford(shortfall) or not deposit(shortfall):
		return -1
	return shortfall


static func _refund(amount: int) -> void:
	if amount > 0:
		withdraw(amount)


## "Operar mediante terceros sobornados, que pasan a ser testigos con registro" (§9.8).
static func _make_witness(npc_id: String) -> void:
	BeliefNet.create_belief(npc_id, PLAYER_ID, FACT_PROXY_WITNESS,
			Database.get_balance_float("mercado.certeza_testigo_testaferro"), SOURCE_DIRECT,
			PlayerState.get_room())
