# security.gd — Módulo de interacciones de SEGURIDAD E INFRAESTRUCTURA (§5.3-§5.5, §11.3-§11.4, §12.2, §14.7, §22.1-§22.3): consolas y servidores, energía y alarmas, cerraduras, cajas, taquillas, escondites, cuerpos y la compactadora.
# PROPIETARIO DE: nada (módulo estático; el estado vive en PlayerState —banderas secops.*—, NPCDirector —cuerpos—, Security —grabaciones y registros— y en el nodo de escena SecurityKeeper).
# ESCUCHA: nada (al cargarse engancha SecurityKeeper a la escena de juego: SecurityKeeper.hook()).
class_name SecurityInteractions
extends RefCounted

## Contrato del InteractionRouter (BUILD_NOTES §15). Reparte por familia (archivos privados "_*"):
##   SecurityRecords  monitor_console · server_terminal · backup_unit
##   SecurityPower    electrical_breaker · alarm_panel · machine_controls · car_sabotage
##   SecurityLocks    lock_old · door_reader · safe · floor_safe · ceo_safe · repair_bench
##   SecurityGear     uniform_locker · cleaning_cart · tool_rack
##   SecurityBodies   body · hiding_spot · trash_chute
## Utilidades comunes: SecurityKit. Nodo de escena: SecurityKeeper (cuerpos, apagón, lectores).
## vent_hatch y freight_panel son de FloorTravel (módulo integrado): con un cuerpo a rastras solo el
## montacargas lo lleva a otra planta y SecurityKeeper lo acompaña. Tipos nuevos que crea este
## módulo en el mundo: "body" (BodyNode, src/entities/body.gd) y "door_reader" (puntos de lector).
## Reglas de la casa: todo delito pasa por player.begin_act + crime_committed; lo irreversible se
## confirma (opción peligrosa sin foco); si alguien mira al jugador se avisa con su nombre antes de
## un delito; cada acción termina en un aviso (toast) y, si procede, un sonido con subtítulo.


static func _static_init() -> void:
	if not Engine.is_editor_hint():
		SecurityKeeper.hook()


static func handled_types() -> Array[String]:
	var out: Array[String] = []
	for family: Array[String] in [SecurityRecords.TYPES, SecurityPower.TYPES, SecurityLocks.TYPES,
			SecurityGear.TYPES, SecurityBodies.TYPES]:
		out.append_array(family)
	return out


static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:
	SecurityKeeper.ensure(SecurityKit.tree_of(interactable))
	var kind: String = interactable.interact_type
	if SecurityRecords.handles(kind):
		await SecurityRecords.interact(interactable, player, ctx)
	elif SecurityPower.handles(kind):
		await SecurityPower.interact(interactable, player, ctx)
	elif SecurityLocks.handles(kind):
		await SecurityLocks.interact(interactable, player, ctx)
	elif SecurityGear.handles(kind):
		await SecurityGear.interact(interactable, player, ctx)
	elif SecurityBodies.handles(kind):
		await SecurityBodies.interact(interactable, player, ctx)


static func is_available(interactable: Interactable, player: Node) -> bool:
	match interactable.interact_type:
		SecurityLocks.T_READER:
			return SecurityLocks.reader_available(interactable)
		SecurityLocks.T_LOCK:
			return SecurityLocks.lock_available(interactable)
		SecurityBodies.T_SPOT:
			return SecurityBodies.spot_available(interactable, player)
	return true


static func prompt_key(interactable: Interactable) -> String:
	match interactable.interact_type:
		SecurityBodies.T_BODY:
			return SecurityBodies.body_prompt(interactable)
		SecurityBodies.T_SPOT:
			return SecurityBodies.spot_prompt(interactable)
		SecurityBodies.T_CHUTE:
			return SecurityBodies.chute_prompt(interactable)
		SecurityLocks.T_LOCK:
			return SecurityLocks.lock_prompt(interactable)
		SecurityLocks.T_READER:
			return "SECOPS_PROMPT_CARD"
		SecurityGear.T_CART:
			return "SECOPS_PROMPT_MASTER_KEYS"
		SecurityGear.T_LOCKER:
			return SecurityGear.locker_prompt(interactable)
		SecurityRecords.T_MONITOR, SecurityRecords.T_SERVER:
			return SecurityRecords.prompt_key(interactable)
	return ""
