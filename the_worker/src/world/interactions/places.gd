# places.gd — Módulo de interacciones de LUGARES Y ESCENAS (BUILD_NOTES §15): tornos, salas con escena (Aurora, interrogatorio, resultados, consejo, notaría, compradores, formación), la nave, camas y enfermería, tiendas, autobús, comisaría, viviendas y corrillos.
# PROPIETARIO DE: nada (módulo estático; lo persistente vive en PlayerState —banderas places.*— y en los sistemas dueños; el nodo de escena PlacesKeeper pone los interactivos propios del módulo).
# ESCUCHA: nada (al cargarse engancha PlacesKeeper a la escena de juego: PlacesKeeper.hook()).
class_name PlacesInteractions
extends RefCounted

## Contrato del InteractionRouter (BUILD_NOTES §15). Reparte por familia (archivos privados "_*"):
##   PlacesGate     turnstile · turnstile_queue (fichar o colarse, §5.6)
##   PlacesScenes   aurora_podium · interrogation_table · results_stage · board_table · notary_desk ·
##                  training_screen (PlacesScenes.training_hook)
##   PlacesBuyers   demo_table · buyer_lounge (compradores de P11 y la sala de espera de la PB)
##   PlacesFactory  product_shelf · carrier_bay · mold_station · qc_terminal · delivery_notes ·
##                  chemical_station
##   PlacesTown     shop_counter · bus_stop · transport_stop · police_desk · house_door
##   PlacesCare     bed · medical_cabinet
##   PlacesSocial   smoking_spot · foosball_table · clan_table
## Utilidades: PlacesKit. Nodo de escena: PlacesKeeper (mesas del clan y del futbolín, sofá de los
## compradores, cola de los tornos y puertas de viviendas; colarse; citación ineludible; avisos;
## traje; quemaduras).
## Apaños de _default.gd que este módulo conserva al reclamar sus tipos: "bed" del piso → dormir
## (WorldBridges.request_sleep); "turnstile" → pasar la tarjeta (DoorAccess.swipe).
## Reglas de la casa: todo delito pasa por player.begin_act + crime_committed; lo irreversible se
## confirma con la opción segura enfocada; si alguien mira se avisa con su nombre antes de un delito;
## cada acción termina en un aviso (toast) con sonido y, si procede, una animación.


static func _static_init() -> void:
	if not Engine.is_editor_hint():
		PlacesKeeper.hook()


static func handled_types() -> Array[String]:
	var out: Array[String] = []
	for family: Array[String] in [PlacesGate.TYPES, PlacesScenes.TYPES, PlacesBuyers.TYPES, PlacesFactory.TYPES,
			PlacesTown.TYPES, PlacesCare.TYPES, PlacesSocial.TYPES]:
		out.append_array(family)
	return out


static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:
	PlacesKeeper.ensure(PlacesKit.tree_of(interactable))
	var kind: String = interactable.interact_type
	if PlacesGate.handles(kind):
		await PlacesGate.interact(interactable, player, ctx)
	elif PlacesScenes.handles(kind):
		await PlacesScenes.interact(interactable, player, ctx)
	elif PlacesBuyers.handles(kind):
		await PlacesBuyers.interact(interactable, player, ctx)
	elif PlacesFactory.handles(kind):
		await PlacesFactory.interact(interactable, player, ctx)
	elif PlacesTown.handles(kind):
		await PlacesTown.interact(interactable, player, ctx)
	elif PlacesCare.handles(kind):
		await PlacesCare.interact(interactable, player, ctx)
	elif PlacesSocial.handles(kind):
		await PlacesSocial.interact(interactable, player, ctx)


static func is_available(interactable: Interactable, _player: Node) -> bool:
	return PlacesGate.is_available(interactable) and PlacesBuyers.is_available(interactable)


static func prompt_key(interactable: Interactable) -> String:
	var kind: String = interactable.interact_type
	if PlacesCare.handles(kind):
		return PlacesCare.prompt_key(interactable)
	if PlacesTown.handles(kind):
		return PlacesTown.prompt_key(interactable)
	return ""
