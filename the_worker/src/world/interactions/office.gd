# office.gd — Interacciones de oficina (BUILD_NOTES §15): mesa propia, ordenadores y terminales, cajones y archivos, expedientes, material, correo, fotocopiadora, café, escuchas y comida.
# PROPIETARIO DE: nada (módulo estático del InteractionRouter; lo que haya que recordar vive en PlayerState —banderas "office.*"— y en los sistemas dueños).
# ESCUCHA: nada.
extends RefCounted

## Contrato de módulo del InteractionRouter (handled_types / interact / prompt_key). Cada familia
## vive en un archivo privado de esta carpeta ("_", el router no los trata como módulos):
##   _office_kit.gd (OfficeKit): contexto, avisos con sonido, actos ilegales vigilados, marcas.
##   _office_desk.gd (OfficeDesk): desk, computer, npc_computer, whiteboard, card_reader.
##   _office_loot.gd (OfficeLoot): drawer, archive_files, filing_cabinet, personnel_files,
##       supply_shelf, mail_sorting, design_archive, forgery_station.
##   _office_terminals.gd (OfficeTerminals): payroll_terminal, accounting_terminal, press_terminal,
##       trading_terminal, campaign_terminal, copier_memory, photocopier.
##   _office_break.gd (OfficeBreak): coffee_machine_use, water_cooler, eavesdrop_point, vending,
##       food_fridge, kitchen_food, lunch_counter.
##   _office_info.gd (OfficeInfo): información temprana y cotilleo (solo lecturas).
## Apaño de _default.gd que este módulo conserva al reclamar "desk": la mesa del despacho propio
## abre el ordenador (UI_INTERACT_OWN_DESK) y una ajena responde «No es tu mesa».
## Reglas (§15): toda acción responde (aviso + sonido/animación); los delitos pasan por
## player.begin_act + crime_committed; lo grave se confirma con la opción segura enfocada (§13.7);
## el tiempo se cobra con GameClock.advance_minutes; nunca se emiten floor_changed/room_entered.
## Tipos sin mueble interactivo en los datos todavía (filing_cabinet, photocopier, water_cooler,
## whiteboard, card_reader) quedan reclamados para cuando el mundo los cree.

const TYPES: Array[String] = [
	"desk", "computer", "npc_computer", "whiteboard", "card_reader",
	"drawer", "archive_files", "filing_cabinet", "personnel_files", "supply_shelf", "mail_sorting",
	"design_archive", "forgery_station",
	"payroll_terminal", "accounting_terminal", "press_terminal", "trading_terminal",
	"campaign_terminal", "copier_memory", "photocopier",
	"coffee_machine_use", "water_cooler", "eavesdrop_point", "vending", "food_fridge", "kitchen_food",
	"lunch_counter",
]
const FREE_FOOD_PROMPT := "UI_INTERACT_FREE_FOOD"
const EAT_HOME_PROMPT := "UI_INTERACT_EAT_HOME"
const OWNER_PLAYER := "player"
const STEAL_FOOD_PROMPT := "UI_INTERACT_FOOD_STEAL"
const FORBIDDEN_FOOD_PROMPT := "UI_INTERACT_FOOD_FORBIDDEN"
const DRAWER_PROMPT := "UI_INTERACT_DRAWER_RUMMAGE"


static func handled_types() -> Array[String]:
	return TYPES.duplicate()


static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:
	match interactable.interact_type:
		"desk", "computer", "npc_computer", "whiteboard", "card_reader":
			await _desk_family(interactable, player, ctx)
		"drawer", "archive_files", "filing_cabinet", "personnel_files", "supply_shelf", "mail_sorting", \
				"design_archive", "forgery_station":
			await _loot_family(interactable, player, ctx)
		"payroll_terminal", "accounting_terminal", "press_terminal", "trading_terminal", \
				"campaign_terminal", "copier_memory", "photocopier":
			await _terminal_family(interactable, player, ctx)
		_:
			await _break_family(interactable, player, ctx)


static func prompt_key(interactable: Interactable) -> String:
	match interactable.interact_type:
		"desk":
			return OfficeDesk.desk_prompt(interactable)
		"lunch_counter", "kitchen_food":
			return _food_prompt(interactable)
		"food_fridge":
			return EAT_HOME_PROMPT if str(interactable.data.get("owner", "")) == OWNER_PLAYER else STEAL_FOOD_PROMPT
		"drawer":
			return DRAWER_PROMPT
	return ""


## Los prompts avisan cuando la acción es un delito (§13.7): comida ajena o bufé vetado.
static func _food_prompt(item: Interactable) -> String:
	if not OfficeBreak.is_free_food(item):
		return STEAL_FOOD_PROMPT if item.interact_type == "kitchen_food" else ""
	return FORBIDDEN_FOOD_PROMPT if BeliefNet.is_room_forbidden_for_player(item.room_id) else FREE_FOOD_PROMPT


static func _desk_family(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		"desk":
			await OfficeDesk.use_desk(item, player, ctx)
		"computer":
			await OfficeDesk.use_computer(item, player, ctx)
		"npc_computer":
			await OfficeDesk.use_npc_computer(item, player, ctx)
		"whiteboard":
			await OfficeDesk.use_whiteboard(item, player, ctx)
		_:
			OfficeDesk.use_card_reader(item, player, ctx)


static func _loot_family(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		"drawer":
			await OfficeLoot.use_drawer(item, player, ctx)
		"personnel_files":
			await OfficeLoot.use_personnel(item, player, ctx)
		"supply_shelf":
			await OfficeLoot.use_supplies(item, player, ctx)
		"mail_sorting":
			await OfficeLoot.use_mail(item, player, ctx)
		"design_archive":
			await OfficeLoot.use_design_archive(item, player, ctx)
		"forgery_station":
			await OfficeLoot.use_forgery(item, player, ctx)
		_:
			await OfficeLoot.use_archive(item, player, ctx)


static func _terminal_family(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		"payroll_terminal", "accounting_terminal":
			await OfficeTerminals.use_fraud_terminal(item, player, ctx)
		"press_terminal":
			await OfficeTerminals.use_press(item, player, ctx)
		"trading_terminal":
			await OfficeTerminals.use_trading(item, player, ctx)
		"campaign_terminal":
			OfficeTerminals.use_campaign(item, player, ctx)
		_:
			await OfficeTerminals.use_copier(item, player, ctx)


static func _break_family(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		"coffee_machine_use", "water_cooler":
			OfficeBreak.use_coffee(item, player, ctx)
		"eavesdrop_point":
			await OfficeBreak.use_eavesdrop(item, player, ctx)
		"vending":
			await OfficeBreak.use_vending(item, player, ctx)
		"food_fridge":
			await OfficeBreak.use_fridge(item, player, ctx)
		"kitchen_food":
			await OfficeBreak.use_kitchen(item, player, ctx)
		"lunch_counter":
			await OfficeBreak.use_lunch_counter(item, player, ctx)
