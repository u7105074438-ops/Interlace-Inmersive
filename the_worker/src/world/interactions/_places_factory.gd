# _places_factory.gd — La nave (§11.6, §22.5): estantes de producto terminado (robo en tres escalas, devolver), el muelle del transportista, la reventa en la tienda insignia, sabotaje de moldes, informes de defectos contra el capataz, albaranes falsificados y el sabotaje químico con apariencia de accidente.
# PROPIETARIO DE: nada (robos, recuento y albaranes de FactoryTheft/Company; calidad y eficiencia de Company; reputación y agravios de NPCDirector; la quemadura, bandera de PlacesKeeper; los informes y el último defecto, banderas places.*).
# ESCUCHA: nada.
class_name PlacesFactory
extends RefCounted

## · "product_shelf" de la nave (data.scale) y "carrier_bay" (palé con transportista cómplice): cada
##   escala con sus requisitos (FactoryTheft.check_requirements: la que falta se dice); acto visible
##   theft_product (lugares.segundos_acto.robo_<escala>) → FactoryTheft.steal (nada se detecta ahora:
##   el recuento semanal). Con producto robado encima, «devolverlo» (FactoryTheft.return_goods).
##   El expositor de la tienda insignia (accepts_stolen_product) revende lo robado (FactoryTheft.
##   fence, acto visible) o, sin nada que vender, enseña el precio real.
## · "mold_station": sabotaje de moldes (acto sabotage, una vez por jornada): la calidad del producto
##   baja (lugares.moldes.perdida_calidad) y durante lugares.moldes.dias_defecto jornadas control de
##   calidad encuentra defectos reales.
## · "qc_terminal": informe de defectos contra el capataz (data.target o el titular de
##   lugares.calidad.ocupacion_capataz), uno por jornada. Con defectos reales (moldes saboteados o
##   calidad < umbral_calidad) es legal y pesa más; sin ellos es un informe falso (acto y delito
##   framing). Lleva tu firma: agravio del capataz. informes_despido informes en dias_ventana
##   jornadas le cuestan el puesto (NPCDirector.remove_npc "fired"/"framed": su silla queda libre).
## · "delivery_notes": solo el capataz (fabrica.ocupaciones_albaranes); acto forgery →
##   FactoryTheft.forge_delivery_notes (el descuadre de la semana apunta al superior directo).
## · "chemical_station": sabotaje «accidental» (acto, una vez por jornada): eficiencia de la nave −,
##   descontento +, pérdida para la compañía, la reputación del capataz −. Con probabilidad de error
##   (menor con protección: lugares.quimico.protecciones) te quemas: registro del laboratorio y
##   quemadura visible (PlacesKeeper) hasta que la cure la enfermería.

const T_SHELF := "product_shelf"
const T_BAY := "carrier_bay"
const T_MOLD := "mold_station"
const T_QC := "qc_terminal"
const T_NOTES := "delivery_notes"
const T_CHEM := "chemical_station"
const TYPES: Array[String] = [T_SHELF, T_BAY, T_MOLD, T_QC, T_NOTES, T_CHEM]
const K_SCALE := "scale"
const K_FENCE := "accepts_stolen_product"
const K_TARGET := "target"
const CRIME_THEFT := "theft_product"
const CRIME_SABOTAGE := "sabotage"
const CRIME_FRAMING := "framing"
const CRIME_FORGERY := "forgery"
const CAUSE_FIRED := "fired"
const CAUSE_FRAMED := "framed"
const GRIEVANCE_REPORT := "defect_report"
const PLAYER_ID := "player"
const MOLD_KEY := "molds"
const QC_KEY := "qc_report"
const CHEM_KEY := "chemicals"
const F_DEFECT_DAY := "places.defect_day"
const F_REPORTS := "places.qc_reports"
const ACT_PREFIX := "robo_"
const PERCENT := 100.0
const NO_DAY := -1
const B_FENCE_ITEMS := "fabrica.objetos_reventa"
const B_NOTE_POSTS := "fabrica.ocupaciones_albaranes"
const B_QUALITY_LOSS := "lugares.moldes.perdida_calidad"
const B_DEFECT_DAYS := "lugares.moldes.dias_defecto"
const B_FOREMAN := "lugares.calidad.ocupacion_capataz"
const B_REP_REAL := "lugares.calidad.reputacion_real"
const B_REP_FAKE := "lugares.calidad.reputacion_falso"
const B_REPORT_GRIEVANCE := "lugares.calidad.gravedad_agravio"
const B_REPORTS_NEEDED := "lugares.calidad.informes_despido"
const B_REPORT_WINDOW := "lugares.calidad.dias_ventana"
const B_QUALITY_FLOOR := "lugares.calidad.umbral_calidad"
const B_CHEM_ERROR := "lugares.quimico.prob_error"
const B_CHEM_ERROR_SAFE := "lugares.quimico.prob_error_protegido"
const B_CHEM_GEAR := "lugares.quimico.protecciones"
const B_CHEM_WEIGHT := "lugares.quimico.peso_evidencia"
const B_CHEM_EFFICIENCY := "lugares.quimico.perdida_eficiencia"
const B_CHEM_LOSS := "lugares.quimico.perdida_empresa"
const B_CHEM_REPUTATION := "lugares.quimico.perdida_reputacion_capataz"
const B_CHEM_DISCONTENT := "lugares.quimico.descontento"


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	match item.interact_type:
		T_SHELF, T_BAY:
			await shelf(item, player, ctx)
		T_MOLD:
			await molds(item, player, ctx)
		T_QC:
			await qc(item, player, ctx)
		T_NOTES:
			await notes(item, player, ctx)
		T_CHEM:
			await chemicals(item, player, ctx)


# ─── Producto terminado ───────────────────────────────────────

static func shelf(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if bool(item.data.get(K_FENCE, false)):
		await fence(item, player, ctx)
		return
	var scales: Array[String] = scales_of(item)
	var options: Array = []
	for scale: String in scales:
		options.append(scale_option(scale, FactoryTheft.check_requirements(scale, {"room_id": item.room_id})))
	var carrying: bool = carries_stolen_goods()
	if carrying:
		options.append("PLACES_FACTORY_RETURN")
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_FACTORY_TITLE", "PLACES_FACTORY_BODY", options,
			[Company.get_finished_goods_stock()])
	if index >= 0 and index < scales.size():
		await steal(item, player, ctx, scales[index])
	elif carrying and index == scales.size():
		return_goods(item, ctx)


static func scales_of(item: Interactable) -> Array[String]:
	var raw: Variant = item.data.get(K_SCALE, [])
	if raw is String:
		var single: Array[String] = [str(raw)]
		return single
	return PlacesKit.strings(raw)


static func scale_option(scale: String, check: Dictionary) -> Dictionary:
	var label: String = PlacesKit.tr_key(FactoryTheft.get_scale_label_key(scale))
	var missing: Array = check.get("missing", [])
	if bool(check.get("allowed", false)) or missing.is_empty():
		return {"text_key": "PLACES_FACTORY_TAKE", "args": [label], "danger": true}
	var why: String = PlacesKit.tr_key(FactoryTheft.get_missing_label_key(str(missing[0])))
	return {"text_key": "PLACES_FACTORY_BLOCKED", "args": [label, why], "disabled": true}


static func carries_stolen_goods() -> bool:
	var goods: Variant = Database.get_balance(B_FENCE_ITEMS)
	if goods is Dictionary:
		for item_id: Variant in goods:
			if PlayerState.is_carrying(str(item_id)):
				return true
	return false


static func steal(item: Interactable, player: Node, ctx: Dictionary, scale: String) -> void:
	if not await PlacesKit.run_act(ctx, player, CRIME_THEFT, ACT_PREFIX + scale):
		return
	var result: Dictionary = FactoryTheft.steal(scale, {"room_id": item.room_id})
	if not bool(result.get("ok", false)):
		var missing: Array = result.get("missing", [])
		PlacesKit.refuse(ctx, FactoryTheft.get_missing_label_key(str(missing[0])) if not missing.is_empty() else "PLACES_FACTORY_NOTHING")
		return
	if not str(result.get("accomplice", "")).is_empty():
		PlacesKit.good(ctx, "PLACES_FACTORY_PALLET", [int(result["pairs"]), int(result["income"]),
				PlacesKit.npc_name(str(result["accomplice"]))], PlacesKit.SFX_CASH)
		return
	PlacesKit.good(ctx, "PLACES_FACTORY_STOLEN", [int(result["pairs"]), PlacesKit.item_name(str(result["item_id"])),
			int(result["resale_value"])])


static func return_goods(item: Interactable, ctx: Dictionary) -> void:
	var result: Dictionary = FactoryTheft.return_goods(item.room_id)
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, FactoryTheft.get_reason_label_key(str(result.get("reason", ""))))
		return
	PlacesKit.good(ctx, "PLACES_FACTORY_RETURNED", [int(result["units"]), int(result["pairs"])])


## Tienda insignia: revender lo robado (acto) o, sin nada, el precio real del par.
static func fence(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not carries_stolen_goods():
		PlacesKit.say(ctx, "PLACES_STORE_PRICE", [roundi(float(Company.get_fundamentals().get("avg_price", 0.0)))])
		return
	if not await PlacesKit.run_act(ctx, player, CRIME_THEFT, ACT_PREFIX + FactoryTheft.SCALE_POCKET):
		return
	var result: Dictionary = FactoryTheft.fence(item.room_id)
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, FactoryTheft.get_reason_label_key(str(result.get("reason", ""))))
		return
	PlacesKit.good(ctx, "PLACES_FACTORY_FENCED", [int(result.get("units", 0)), int(result.get("income", 0))], PlacesKit.SFX_CASH)


# ─── Sabotaje de moldes ───────────────────────────────────────

static func molds(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if PlacesKit.used_today(MOLD_KEY):
		PlacesKit.say(ctx, "PLACES_MOLDS_ALREADY")
		return
	var index: int = await PlacesKit.choose(ctx, "PLACES_MOLDS_TITLE", "PLACES_MOLDS_BODY",
			[{"text_key": "PLACES_MOLDS_SABOTAGE", "danger": true}, "PLACES_CLOSE"])
	if index != 0 or not await PlacesKit.run_act(ctx, player, CRIME_SABOTAGE, "moldes"):
		return
	PlacesKit.spend_minutes("moldes")
	PlacesKit.mark_today(MOLD_KEY)
	PlayerState.set_flag(F_DEFECT_DAY, GameClock.get_day())
	Company.modify_product_quality(-Database.get_balance_float(B_QUALITY_LOSS))
	PlacesKit.commit(CRIME_SABOTAGE, item.room_id, {"kind": "mold_quality", K_TARGET: foreman_of(item), "leaves_record": false})
	PlacesKit.good(ctx, "PLACES_MOLDS_DONE")


# ─── Control de calidad ───────────────────────────────────────

## Capataz al que apuntan los informes: data.target si sigue en plantilla o el titular del puesto.
static func foreman_of(item: Interactable) -> String:
	var own: String = str(item.data.get(K_TARGET, ""))
	if NPCDirector.is_active(own):
		return own
	var holder: String = Company.get_seat_holder(str(Database.get_balance(B_FOREMAN)))
	return holder if NPCDirector.is_active(holder) else ""


## Hay defectos reales: moldes saboteados hace poco o calidad por debajo del umbral.
static func defects_real() -> bool:
	var raw: Variant = PlayerState.get_flag(F_DEFECT_DAY, NO_DAY)
	var day: int = int(raw) if raw is int or raw is float else NO_DAY
	if day != NO_DAY and GameClock.get_day() - day <= Database.get_balance_int(B_DEFECT_DAYS):
		return true
	return float(Company.get_fundamentals().get("product_quality", CompanySystem.NEUTRAL)) < Database.get_balance_float(B_QUALITY_FLOOR)


static func qc(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var target: String = foreman_of(item)
	var real: bool = defects_real()
	var quality: int = roundi(float(Company.get_fundamentals().get("product_quality", CompanySystem.NEUTRAL)) * PERCENT)
	var option: Dictionary = {"text_key": "PLACES_QC_REPORT_REAL" if real else "PLACES_QC_REPORT_FAKE",
			"args": [PlacesKit.npc_name(target)], "danger": not real,
			"disabled": target.is_empty() or PlacesKit.used_today(QC_KEY)}
	var body: String = "PLACES_QC_BODY_DEFECTS" if real else "PLACES_QC_BODY_CLEAN"
	var index: int = await PlacesKit.choose(ctx, "PLACES_QC_TITLE", body, [option, "PLACES_CLOSE"],
			[quality, report_count(), Database.get_balance_int(B_REPORTS_NEEDED)])
	if index != 0 or target.is_empty():
		return
	if not real and not await PlacesKit.run_act(ctx, player, CRIME_FRAMING, "informe_falso"):
		return
	file_report(ctx, item.room_id, target, real)


## Informes contra el capataz en la ventana (lugares.calidad.dias_ventana).
static func report_days() -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = PlayerState.get_flag(F_REPORTS, [])
	for value: Variant in (raw if raw is Array else []):
		if GameClock.get_day() - int(value) < Database.get_balance_int(B_REPORT_WINDOW):
			out.append(int(value))
	return out


static func report_count() -> int:
	return report_days().size()


static func file_report(ctx: Dictionary, room_id: String, target: String, real: bool) -> void:
	PlacesKit.spend_minutes("informe_calidad")
	PlacesKit.mark_today(QC_KEY)
	var loss: float = Database.get_balance_float(B_REP_REAL if real else B_REP_FAKE)
	NPCDirector.modify_npc_reputation(target, -loss, GRIEVANCE_REPORT)
	NPCDirector.add_grievance(target, GRIEVANCE_REPORT, Database.get_balance_int(B_REPORT_GRIEVANCE))
	if not real:
		PlacesKit.commit(CRIME_FRAMING, room_id, {K_TARGET: target, "method": GRIEVANCE_REPORT})
	var days: Array[int] = report_days()
	days.append(GameClock.get_day())
	var name: String = PlacesKit.npc_name(target)
	if days.size() >= Database.get_balance_int(B_REPORTS_NEEDED):
		PlayerState.set_flag(F_REPORTS, null)
		NPCDirector.remove_npc(target, CAUSE_FIRED if real else CAUSE_FRAMED)
		PlacesKit.good(ctx, "PLACES_QC_FOREMAN_OUT", [name])
		return
	PlayerState.set_flag(F_REPORTS, days)
	PlacesKit.good(ctx, "PLACES_QC_FILED", [name, days.size(), Database.get_balance_int(B_REPORTS_NEEDED)])


# ─── Albaranes ────────────────────────────────────────────────

static func notes(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not PlacesKit.bal_strings(B_NOTE_POSTS).has(PlayerState.get_occupation_id()):
		PlacesKit.refuse(ctx, FactoryTheft.get_reason_label_key(FactoryTheft.REASON_NOT_FOREMAN))
		return
	var superior: String = FactoryTheft.find_direct_superior()
	var index: int = await PlacesKit.choose(ctx, "PLACES_NOTES_TITLE", "PLACES_NOTES_BODY",
			[{"text_key": "PLACES_NOTES_FORGE", "danger": true}, "PLACES_CLOSE"], [PlacesKit.npc_name(superior)])
	if index != 0 or not await PlacesKit.run_act(ctx, player, CRIME_FORGERY, "albaranes"):
		return
	var result: Dictionary = FactoryTheft.forge_delivery_notes(item.room_id)
	if not bool(result.get("ok", false)):
		PlacesKit.refuse(ctx, FactoryTheft.get_reason_label_key(str(result.get("reason", ""))))
		return
	PlacesKit.good(ctx, "PLACES_NOTES_FORGED", [PlacesKit.npc_name(str(result.get("target", "")))])
	if bool(result.get("traced", false)):
		PlacesKit.say(ctx, "PLACES_NOTES_TRACED", [], ToastStack.KIND_WARN)


# ─── Laboratorio de tintes ────────────────────────────────────

static func chemical_error_chance() -> float:
	for gear: String in PlacesKit.bal_strings(B_CHEM_GEAR):
		if PlayerState.get_disguise() == gear or PlayerState.has_item(gear):
			return Database.get_balance_float(B_CHEM_ERROR_SAFE)
	return Database.get_balance_float(B_CHEM_ERROR)


static func chemicals(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if PlacesKit.used_today(CHEM_KEY):
		PlacesKit.say(ctx, "PLACES_CHEM_ALREADY")
		return
	var chance: float = chemical_error_chance()
	var index: int = await PlacesKit.choose(ctx, "PLACES_CHEM_TITLE", "PLACES_CHEM_BODY",
			[{"text_key": "PLACES_CHEM_SABOTAGE", "danger": true}, "PLACES_CLOSE"], [roundi(chance * PERCENT)])
	if index != 0 or not await PlacesKit.run_act(ctx, player, CRIME_SABOTAGE, "quimico"):
		return
	PlacesKit.spend_minutes("quimico")
	PlacesKit.mark_today(CHEM_KEY)
	var foreman: String = foreman_of(item)
	Company.modify_factory_efficiency(-Database.get_balance_float(B_CHEM_EFFICIENCY))
	Company.modify_discontent(Database.get_balance_int(B_CHEM_DISCONTENT), CHEM_KEY)
	if not foreman.is_empty():
		NPCDirector.modify_npc_reputation(foreman, -Database.get_balance_float(B_CHEM_REPUTATION), CHEM_KEY)
	PlacesKit.commit(CRIME_SABOTAGE, item.room_id, {"kind": "chemical_accident", K_TARGET: foreman,
			"company_loss": Database.get_balance_float(B_CHEM_LOSS), "leaves_record": false})
	if PlacesKit.rng(CHEM_KEY + item.interact_id).randf() < chance:
		BeliefNet.create_record(BeliefNetSystem.RECORD_STAMPED_DOCUMENT, PLAYER_ID, Database.get_balance_float(B_CHEM_WEIGHT), item.room_id)
		PlacesKeeper.set_burn(item.room_id)
		PlacesKit.bad(ctx, "PLACES_CHEM_ERROR")
		return
	PlacesKit.good(ctx, "PLACES_CHEM_DONE")
