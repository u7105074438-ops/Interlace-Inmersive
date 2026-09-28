# _places_care.gd — Camas y enfermería: la cama del piso (dormir, resumen y guardado), la cama de la enfermería (descansar sin dejar registro, curar una quemadura) y el botiquín.
# PROPIETARIO DE: nada (el sueño es de WorldBridges/HomeCycle; la quemadura, bandera places.burn de PlacesKeeper; «ya hoy», banderas places.*).
# ESCUCHA: nada.
class_name PlacesCare
extends RefCounted

## · "bed" del piso (acción sleep_save o hogar.sala_domicilio): WorldBridges.request_sleep() —
##   confirmación, fundido, HomeCycle.sleep() (resumen, jornada nueva, GUARDADO, desayuno) y aviso
##   (el apaño de _default.gd, conservado). La cama de la enfermería (data.recovery): descansar
##   lugares.minutos.enfermeria sin registro ni veto de testigos (es tu derecho) y, si hay
##   quemadura del laboratorio, curarla (§22.4 «recuperación sin dejar registro»).
## · "medical_cabinet": con quemadura, curarla (lugares.minutos.curar); si no, un botiquín
##   (lugares.enfermeria.objeto_botiquin) una vez por jornada, legal.

const T_BED := "bed"
const T_CABINET := "medical_cabinet"
const TYPES: Array[String] = [T_BED, T_CABINET]
const K_ACTION := "action"
const K_RECOVERY := "recovery"
const SLEEP_ACTION := "sleep_save"
const B_HOME := "hogar.sala_domicilio"
const B_KIT := "lugares.enfermeria.objeto_botiquin"
const KIT_KEY := "first_aid"
const ANIM_REST := "yawn"
const ANIM_TREAT := "drawer"


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if item.interact_type == T_CABINET:
		cabinet(player, ctx)
		return
	if is_own_bed(item):
		var bridges: WorldBridges = WorldBridges.find(PlacesKit.tree_of(item))
		if bridges != null:
			await bridges.request_sleep()
		return
	if bool(item.data.get(K_RECOVERY, false)):
		await rest(player, ctx)
		return
	PlacesKit.say(ctx, "INTERACT_NOTHING_USEFUL")


static func prompt_key(item: Interactable) -> String:
	match item.interact_type:
		T_BED:
			if is_own_bed(item):
				return "UI_INTERACT_SLEEP"
			return "UI_INTERACT_REST" if bool(item.data.get(K_RECOVERY, false)) else "UI_INTERACT_EXAMINE"
		T_CABINET:
			return "UI_INTERACT_TREAT_BURN" if PlacesKeeper.is_burned() else ""
	return ""


static func is_own_bed(item: Interactable) -> bool:
	return str(item.data.get(K_ACTION, "")) == SLEEP_ACTION \
			or DatabaseSystem.get_room_base_id(item.room_id) == str(Database.get_balance(B_HOME))


## Enfermería: descansar (tiempo legal y sin registro) y curar la quemadura si la hay.
static func rest(player: Node, ctx: Dictionary) -> void:
	var minutes: int = roundi(PlacesKit.minutes("enfermeria"))
	var burned: bool = PlacesKeeper.is_burned()
	var body: String = "PLACES_REST_BODY_BURN" if burned else "PLACES_REST_BODY"
	var index: int = await PlacesKit.choose(ctx, "PLACES_REST_TITLE", body,
			[{"text_key": "PLACES_REST_GO", "args": [minutes]}, "PLACES_NOT_NOW"])
	if index != 0:
		return
	PlacesKit.play(player, ANIM_REST)
	GameClock.advance_minutes(float(minutes))
	if PlacesKeeper.cure_burn():
		PlacesKit.good(ctx, "PLACES_BURN_TREATED")
		return
	PlacesKit.good(ctx, "PLACES_RESTED", [minutes])


static func cabinet(player: Node, ctx: Dictionary) -> void:
	if PlacesKeeper.is_burned():
		PlacesKit.play(player, ANIM_TREAT)
		PlacesKit.spend_minutes("curar")
		PlacesKeeper.cure_burn()
		PlacesKit.good(ctx, "PLACES_BURN_TREATED")
		return
	if PlacesKit.used_today(KIT_KEY):
		PlacesKit.say(ctx, "PLACES_KIT_ALREADY")
		return
	var kit: String = str(Database.get_balance(B_KIT))
	if not PlacesKit.can_take(kit):
		PlacesKit.refuse(ctx, "PLACES_POCKETS_FULL")
		return
	PlacesKit.play(player, ANIM_TREAT)
	PlacesKit.spend_minutes("botiquin")
	PlayerState.add_item(kit)
	PlacesKit.mark_today(KIT_KEY)
	PlacesKit.good(ctx, "PLACES_KIT_TAKEN", [PlacesKit.item_name(kit)])
