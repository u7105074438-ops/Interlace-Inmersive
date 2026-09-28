# THE WORKER — Build notes (shared contract for every builder)

The single source of truth for *what* to build is `../docs/THE_WORKER_MANUAL_MAESTRO.md`
(the "manual"). This file fixes the cross-cutting *how* decisions the manual leaves open, so
that pieces written in parallel by different builders fit together. When this file and the
manual disagree on something the manual marks **[C]**, the manual wins.

## 0. Engine, tooling, commands

- Godot **4.7.2** (`godot` is on PATH). Project root: this directory (`the_worker/`).
- Renderer: `gl_compatibility` (runs on desktop, Android and our virtual display).
- Run one validation scenario: `tools/run_test.sh test_name` (exit 0 = pass). It re-imports the
  project first (required so `class_name` globals and `locale/strings.csv` are registered).
- Run everything: `tools/run_all_tests.sh`.
- Screenshots of the real game: `tools/screenshot.sh <out_dir> <scenario> [--force-rank=28 ...]`
  (virtual display; scenarios live in `src/util/autopilot.gd`). Look at the PNGs with the Read tool.
- Add/modify tunables: `tools/balance_add.py section.key '<json>' ...` (never hand-edit
  `data/balance.json` while others work: the tool is file-locked).
- Add visible text: `tools/loc_add.py KEY "English" "Español" ...` or `tools/loc_add.py --file x.csv`
  (file-locked upsert into `locale/strings.csv`, columns `keys,en,es`).
- Never run `git` commands that change history/branches; the orchestrator commits.

## 1. Directory layout (manual §17.2) — do not invent new top-level dirs

```
data/            16 JSON files + data/rooms/*.json      (content only)
src/autoload/    the 14 global systems                 (one file each)
src/core/        typed data classes (class_name, static from_dict)
src/simulation/  perception, utility AI, bribery, investigation, market helpers, etc.
src/entities/    player.gd, npc.gd, interactables, body, camera_device...
src/world/       room_builder.gd, floor_layout.gd, floor_streamer.gd, game_root.gd, navigation
src/ui/          hud, detection indicator, stellar_os/*, mobile/*, map, dialogs, menus, audio/*
src/util/        validate.gd, loc helpers, input_setup.gd, autopilot.gd, rng helpers
scenes/world|ui|cinematics   thin .tscn wrappers (root node + script). Prefer building node trees in code.
tests/           test_<name>.gd launchers + tests/cases/<name>_case.gd bodies
locale/strings.csv
tools/           shell/python helpers (not part of the game)
```

## 2. The 14 autoloads (names are fixed; registered in project.godot from the start)

| Autoload name | class_name | File |
|---|---|---|
| EventBus | EventBusNode | src/autoload/event_bus.gd |
| Database | DatabaseSystem | src/autoload/database.gd |
| GameClock | GameClockSystem | src/autoload/game_clock.gd |
| PlayerState | PlayerStateSystem | src/autoload/player_state.gd |
| BeliefNet | BeliefNetSystem | src/autoload/belief_net.gd |
| NPCDirector | NPCDirectorSystem | src/autoload/npc_director.gd |
| SocialGraph | SocialGraphSystem | src/autoload/social_graph.gd |
| Security | SecuritySystem | src/autoload/security.gd |
| Company | CompanySystem | src/autoload/company.gd |
| Market | MarketSystem | src/autoload/market.gd |
| NewsFeed | NewsFeedSystem | src/autoload/news_feed.gd |
| IdeaPool | IdeaPoolSystem | src/autoload/idea_pool.gd |
| Tracking | TrackingSystem | src/autoload/tracking.gd |
| SaveSystem | SaveSystemNode | src/autoload/save_system.gd |

Autoload order in project.godot = the order above (EventBus, then Database, then the rest).
Every public signature in manual §19 must exist exactly (name, parameter types, return type).
Extra public methods are allowed; removing/renaming specified ones is not.

### Rule of communication (manual §17.1, pragmatic reading)
- An **autoload never calls a mutating method of another autoload.** It reacts to EventBus
  signals. It MAY call *read-only getters* of other autoloads (e.g. `PlayerState.get_rank()`).
- Code outside `src/autoload/` (simulation modules, entities, UI, world) is the "hands" of the
  game: it may call any autoload's public API (read or write) and emit EventBus signals.
- Signals are past tense. Adding a new EventBus signal: only if the §18.2 catalogue truly lacks
  it; add it at the end of the matching section with a `# EXT:` comment.
- Every system owns its state exclusively (§17.1 third principle).

### Game-session lifecycle (all autoloads)
Autoloads start **empty**. A new run is created by `game_root.gd` calling, in order:
`Database.load_all()` (once per process) → `GameClock.reset_for_new_run()` →
`PlayerState.reset_for_new_run()` → `NPCDirector.generate_population()` →
`SocialGraph.build_initial_graph()` → every other system's `reset_for_new_run()`.
Each autoload therefore exposes `func reset_for_new_run() -> void` (extra method, allowed).
Loading a saved run: `SaveSystem.load_run()` calls each system's `load_state()`.
Tests call these directly to set up state.
- **Run seed order:** `GameClock.set_run_seed(seed)` goes BEFORE the resets (every system seeds its
  RNG from `GameClock.get_run_seed()` inside `reset_for_new_run()`; `reset_for_new_run()` never
  changes the seed). A saved run restores its seed in `GameClock.load_state()`.
- **Resume rule:** `reset_for_new_run()` and `load_state()` leave the clock PAUSED. The world
  emits `run_started(seed)` (new run) or SaveSystem emits `run_loaded(day)` (after `load_run()`)
  once the world is built; GameClock resumes itself on either. Tests never emit them, so they do
  not depend on the real-time clock. `run_started` also makes SaveSystem delete a previous
  character's `run.json` (unless the run came from `load_run()`).
- **Scene nodes with run state** (CaughtHandler, DutySystem — not autoloads) join the group
  `SaveSystemNode.SCENE_GROUP` and are saved inside run.json as `"scene:<get_save_key()>"`.
  `load_run()` hands each state to the node already in the tree; a node created later calls
  `SaveSystem.claim_scene_state(key)` in its `_ready` (both handlers already do). game_root only
  has to add the nodes. `Database` saves the active difficulty preset (§15.7) the same way as
  any autoload (it loads first, so every other `load_state` sees the run's modifiers).

## 3. Units, space, floors

- 1 manual "metre" (perception distances, noise radii) = 1 room grid cell = `mundo.px_por_unidad`
  pixels (balance.json, default 48). Room `size` and furniture `pos` are in cells.
- Floor numbers (int): S3=-3, S2=-2, S1=-1, PB=0, P1..P20 = 1..20, roof = 21,
  factory = `mundo.planta_fabrica` (100), exterior = `mundo.planta_exterior` (200).
- Transversal spaces (§22.15) live in `data/rooms/transversal.json` with `"floor": -99` and
  `"floors": [min, max]`. FloorLayout instantiates the per-floor pieces (corridor strip, elevator
  bank, main stairs, service stairs, cleaning closet, vent hatches) on every floor they span.
  Their room ids get a floor suffix at runtime: `corridors_low@3`, `service_stairs@3`.
- Only ONE floor is instantiated at a time (FloorStreamer). Rooms of that floor are placed by
  `src/world/floor_layout.gd` (deterministic): a horizontal corridor strip through the middle,
  rooms above and below it from left to right, each room with a door onto the corridor; rooms
  whose `connects_to` lists another room of the floor but not the corridor are placed adjacent to
  that room with an internal door. Elevator bank + main stairs at the left end, service stairs +
  cleaning closet at the right end. The same algorithm must produce a stable result for the map.
- Travel between floors: interact with elevator / stairs / freight elevator / vent hatch →
  floor-select dialog → `floor_changed` emitted, streamer rebuilds. Elevators emit
  `card_reader_logged` + `camera_recorded_player`; service stairs emit nothing but cost more time.
- NPCs off the current floor are simulated statistically by NPCDirector (schedule → room id).
  NPC nodes (`src/entities/npc.gd`) exist only for the current floor (LOD 0/1).

## 4. Data classes (src/core) and data files

- Every data class: `class_name X extends RefCounted`, static typed fields, `static func
  from_dict(d: Dictionary, source: String) -> X` that validates with `Validate` and collects
  errors into `Validate.errors` (static Array[String]) instead of crashing.
- Runtime classes (Belief, Idea, Investigation, NPCRuntime, ItemData) also expose
  `to_dict() -> Dictionary` for saving.
- JSON keys starting with `_` are comments and are ignored by validators.
- Error format (exact): `"ARCHIVO → entrada N → campo 'clave': PROBLEMA (esperado X, recibido Y)"`.
- Ids are snake_case. All displayed strings are keys (`OCC_*`, `ROOM_*`, `UI_*`, `NPC_*`...).

## 5. Localisation

- Base language English, shipped localisation Spanish (`keys,en,es`). The language is a
  setting (SaveSystem profile `language`, default `en`); `TranslationServer.set_locale()`.
- UI code shows text with `tr("KEY")` (and `tr("KEY") % [args]`). NPC names are proper nouns
  and are the only literal names allowed (they come from data files).
- Every key you use must exist in strings.csv with both columns filled (use tools/loc_add.py).

## 6. Code conventions (manual §17.3 + §45) — reviewers will check these

- Static typing everywhere (`var x: int`, `-> void`, typed arrays). Avoid `Variant` unless the
  manual's signature uses it.
- Functions ≤ 40 lines. Three-line header in every .gd file:
  ```
  # file.gd — what it does.
  # PROPIETARIO DE: state it owns (or "nada").
  # ESCUCHA: signals it subscribes to (or "nada").
  ```
- No tunable numeric literals in code: read them from `Database.get_balance_*("section.key")`.
  (0, 1, -1, array indices, pixel paddings in UI layout and colours from data are fine.)
- Signals past tense. Private members start with `_`. Constants UPPER_SNAKE.
- Randomness: use a `RandomNumberGenerator` owned by the system, seeded from the run seed
  (`GameClock.get_run_seed()`), so runs are reproducible in tests.
- Never block the main thread with long loops per frame; heavy work happens on events or on the
  hourly/daily ticks (§20.2).

## 7. Tests (manual §21)

Godot compiles a `--script` file before autoloads exist, so autoload globals cannot be used in it.
Pattern (the harness `tests/test_base.gd` is provided by the foundation step):

```
# tests/test_beliefs.gd
extends "res://tests/test_base.gd"
func case_path() -> String:
	return "res://tests/cases/beliefs_case.gd"
```
```
# tests/cases/beliefs_case.gd  (extends TestCase; may use autoload globals freely)
extends TestCase
func run_case() -> void:
	check(BeliefNet.calculate_player_suspicion() == 0.0, "no beliefs -> zero suspicion")
	...  # `await` is allowed
```
`TestCase` provides `check(cond, msg)`, `check_eq(a, b, msg)`, `check_near(a, b, eps, msg)`,
`new_run()` (fresh run with a fixed seed) and prints `PASS/FAIL` lines. Exit code = failures.
Each test must finish in < 60 s. Tests must not depend on the real-time clock.

## 8. Presentation

- Flat vector style drawn by code (`_draw()`, Polygon2D, Line2D) with outlines; colours come
  from `data/art_bands.json` palettes. No external art is required.
- Cenital 3/4: rooms seen from above; characters drawn with head+shoulders offset upwards; the
  silhouette communicates tier (§14.5). Character layers per §14.4 selected by `portrait_seed`.
- UI is built in code (Control nodes) with a shared theme from `src/ui/ui_theme.gd`
  (text size setting: 3 levels; high-contrast setting). Base resolution 1920×1080,
  stretch `canvas_items` / `expand`.
- Audio is synthesised in code (AudioStreamGenerator / AudioStreamWAV built at runtime) — the
  corporate muzak (§14.9) and SFX. Every informative sound also pushes a subtitle
  (`src/ui/audio/` + HUD subtitle feed) — accessibility requirement §13.10.
- Input actions are registered in code by `src/util/input_setup.gd` (called at boot):
  `move_up/down/left/right` (WASD + arrows), `sneak` (Shift), `crouch` (Ctrl), `interact` (E),
  `map` (Tab), `computer` (C), `phone` (M), `debug_panel` (F1), `pause_menu` (Esc),
  `inventory` (I), `ui_confirm` (Enter). Sprint = double-tap a direction or double-click.

## 9. Debug & QA hooks

- F1 debug panel (§14) also offers cheats for verification: force rank, add money, set
  suspicion inputs, jump to hour/day, teleport to floor.
- Command-line user args (after `--`): `--autopilot=<scenario>`, `--shots=<dir>`,
  `--force-rank=<n>`, `--seed=<n>`, `--skip-intro`. Parsed by `src/util/autopilot.gd`.

## 10. Working rules for builders

- Touch only the files your task assigns you (plus tools/loc_add.py and tools/balance_add.py).
  If you need something from a file owned by someone else, write it in your final report under
  "REQUESTS FOR OTHER FILES" instead of editing it.
- Before finishing: run your tests with `tools/run_test.sh`, and make sure
  `godot --headless --path . --import` shows no `SCRIPT ERROR`/`Parse Error` for your files.
- If a test fails because of a parse error in a file you do not own, wait a minute and retry
  (another builder is mid-edit); report it if it persists.

## 11. Shared EXT signals (already declared in event_bus.gd — use them, don't redeclare)

`run_started(run_seed)`, `run_loaded(day)`, `hour_passed(hour, day)` (GameClock, every game hour), `tracking_event_recorded(axis, amount, source)` (only for tracking-worthy events that have no domain signal of their own), `day_summary_ready(summary)`, `time_skipped(from_hour, to_hour)`,
`crime_committed(crime_type, room_id, details)` — emitted by whoever executes an illegal act
(crime types: theft_small, theft_product, drawer_forced, lock_forced, file_copied, trespass,
bribe, forgery, sabotage, elimination, body_moved, footage_deleted, records_deleted, fraud,
insider_trade, rumour_planted, idea_stolen, framing, power_cut, burglary),
`money_changed(old, new, reason)`, `inventory_changed(item_id, added)`, `item_hidden(item_id, spot_id)`,
`item_disposed(item_id, method)`, `player_searched(found_hot_items, outcome)`, `disguise_changed(uniform_id)`,
`duty_progressed(duty_id, progress)`, `duty_deadline_warned(duty_id, hours_left)`,
`npc_decided(npc_id, action, context)` — the outcome of a utility-AI evaluation (NPCDirector emits it),
`npc_reported_player(npc_id, report_type, weight, location)` — an NPC went to Security / a superior,
`npc_removed(npc_id, cause)`, `body_created(body_id, npc_id, room_id)`, `body_hidden(body_id, spot_id)`,
`blackmail_demanded(npc_id, demand_type, amount)`, `phone_message_received(from_id, text_key, is_chat)`,
`aurora_meeting_started(meeting_id)`, `results_presentation_due(quarter)`,
`interrogation_answered(case_id, evidence_index, answer, outcome)`, `police_arrived(location)`, `police_evaded()`,
`subtitle_posted(text_key, source_position, importance)`, `notebook_entry_added(category, text_key, args)`.
If you need yet another signal, do NOT edit event_bus.gd: list it under REQUESTS FOR OTHER FILES.

## 12. Library modules vs systems
`src/simulation/*.gd` are libraries/helpers (class_name, usually RefCounted or static funcs), not
global systems. Autoloads MAY call these pure helpers (e.g. NPCDirector uses UtilityAI to score
actions; Security uses InvestigationEngine). Helpers never hold global state of their own unless
their owner autoload passes it in; state lives in the owning autoload (and is saved there).

## 13. Cross-system decisions (fixed by the orchestrator — builders implement their side)

- **Ownership conflicts in §19 resolved:**
  - Tracking axes: `Tracking` owns the five axes and increments them by *subscribing to domain
    signals* (§12.8 table: bribe_result → gold, idea_acquired → silk, duty_completed honest → sweat,
    npc_removed/elimination → blood, body_hidden → blood, crime_committed theft/fraud/forgery/framing/
    rumour_planted → gold/silk, news_published scandal not buried → ruin, seat_vacated by talent
    expulsion → ruin, Company theft loss → ruin...). `PlayerState.add_tracking()` only emits
    `tracking_event_recorded`; `PlayerState.get_tracking()` / `get_dominant_axis()` read Tracking.
  - Suspicion: BeliefNet computes, PlayerState caches (as the manual says).
  - Hidden items ("stashes") are owned by PlayerState (`stash_item(item_id, spot_id, room_id) -> bool`,
    `retrieve_item(spot_id, item_id) -> bool`, `get_stashes() -> Dictionary`,
    `dispose_item(item_id, method) -> bool`).
  - Bodies are owned by NPCDirector (a removed NPC with cause "eliminated" has a body record:
    `get_body_info(npc_id) -> Dictionary {room_id, spot_id, hidden, discovered, day}`,
    `move_body(npc_id, room_id, spot_id)`).
  - NPC occupation/seat changes: Company owns seats and emits `seat_vacated` / `seat_filled`;
    NPCDirector listens and updates the NPC's `occupation_id` (and ledger favour/grievance, §6.3).
  - NPC merit/ideas-generation mood live in NPCDirector; the player's merit lives in Company.
- **Extra public getters (add them in the owner; others may call them):**
  - NPCDirector: `get_npc_reputation(npc_id) -> float` (0-100, from tier + merit − grievances; used as
    "credibilidad_portador" and "reputación_acusador"), `get_npcs_on_floor(floor) -> Array[NPCRuntime]`,
    `knows_player(npc_id) -> bool` (same department/room colleagues + anyone with a belief/ledger entry),
    `get_merit(npc_id) -> int`, `get_body_info`, `move_body`, `get_player_room() -> String`
    (tracked from `room_entered(room, true)`), `get_npcs_near(room_id) -> Array[NPCRuntime]`.
  - Company: `get_all_seats() -> Array[Dictionary]` ({occupation_id, seat_index, holder}),
    `get_player_seat() -> Dictionary`, `get_seat_count(occupation_id) -> int`.
  - PlayerState: `get_room() -> String`, `get_floor() -> int` (updated from room_entered/floor_changed),
    `get_disguise() -> String` ("" = none), `set_disguise(uniform_id)`, `get_player_name() -> String`
    / `set_player_name(name)` (`get_name()` cannot be overridden on a Node: it is `get_player_name()`).
  - PlayerState **external memory** (§13.3-§13.5; the UI keeps NO persistent state of its own, all
    of this is saved with PlayerState): notes `get_notes() -> Array[Dictionary]` ({id, day, hour,
    minute, text, npc_id}), `add_note(text, npc_id := "") -> int`, `remove_note(id) -> bool`,
    `get_notes_about(npc_id)`; free notepad `get_notepad()/set_notepad(text)`; notebook log
    `get_notebook_entries()` (every `notebook_entry_added` of the run: {category, text_key, args,
    day, hour, minute}); phone contacts `get_contacts() -> Array[Dictionary]` ({npc_id, source,
    day}), `add_contact(npc_id, source) -> bool` (source: proximity | favour | hr | purchase |
    messaged; UI aliases colleague/bought accepted), `has_contact(npc_id)`, `get_contact_source`,
    `contact_source_key(source)` (CONTACT_SOURCE_*) — automatic: N working hours in the same room
    (`movil.horas_proximidad_contacto`), favour_added, blackmail_demanded, phone_message_received,
    `grant_full_file(id, "hr_intrusion")`, and every number while working in HR; marked targets
    `mark_target/unmark_target/get_marked_targets/is_marked` (they emit `notebook_entry_added
    ("targets", PERS_NOTE_TARGET_MARKED|_CLEARED, [name])`; NPCDirector listens and keeps the
    target at LOD 0 with reason "marked_target"); `grant_full_file/has_full_file/
    get_full_file_reason`; `record_study/get_studies`; mission flags `get_flag(key, default)`,
    `set_flag(key, value)` (null clears), `has_flag(key)`.
  - GameClock: `get_run_seed()`, `set_run_seed()`, `set_observer_check(callable: Callable)` — the
    world registers a function returning true when observers are near (used by advance_to_band).
    Pause has two layers: `pause()/resume()` (general switch, run lifecycle) and ownership-counted
    `pause_by(owner)/resume_by(owner)` (+ `is_paused_by`, `get_pause_owners`, `clear_pause_owners`)
    for modals/menus/cinematics: nobody unpauses on top of another owner; `is_paused()` is true if
    the general pause OR any owner holds it.
  - Security: `get_footage_list() -> Array[Dictionary]`, `get_access_log() -> Array[Dictionary]`.
- **Perception terms:** `NPCDirector.get_effective_perception(npc_id)` = trait + suspicion term +
  `Security.get_guard_perception_bonus()` for guards (occupations in `npc.ocupaciones_vigilancia`).
  **Security owns the guard bonus** (alert level, §7.10); NPCDirector only applies it there.
  Perception must use that value and never add the suspicion or alert terms again.
- **Shared news layer (§7.11):** BeliefNet adds `NewsFeed.get_suspicion_contribution()` ×
  `creencias.factor_peso_social_noticias` to the player's suspicion (a synthetic `news_coverage`
  entry in `get_suspicion_breakdown()`), recomputed on news_published / news_buried / day_advanced:
  one scandal raises suspicion AND depresses the price; burying it lowers both. News about an NPC
  (fabricated scandal, activist campaign) lowers that NPC's `get_npc_reputation` (and credibility)
  by `NewsFeed.get_suspicion_about(id)` × `npc.reputacion_por_peso_prensa`.
- **Market events on fundamentals (§9.12):** Company applies the active events of
  `NewsFeed.get_active_market_events()` (production/revenue/costs multipliers, brand add, legal
  costs, growth factor, risk add) except the "strike" event (Company models strikes itself).
  NewsFeed activates an event before emitting its news, so Company recalculates at once.
- **Verdict "player_minor":** Company demotes the player (`demote_player("credible_accusation")`;
  clearance follows the new occupation); Security only marks max effective suspicion for some
  weeks. Game-over emitters use `Tracking.evaluate_ending_for_cause(cause)` and
  `Tracking.get_snapshot_for_cause(cause)` (the cause is only registered when game_over is heard).
- **Full-certainty escalation:** a belief about the player reinforced past
  `creencias.certeza_directa_completa` (§7.2 partial sightings adding up) makes its holder
  re-evaluate once (NPCDirector listens to `belief_decayed` = "certainty changed"; no new signal).
- **SocialGraph departures from the manual (documented in its header):** Sonia Vail's
  `initial_links` in npcs_named.json are dropped at build time (§8.3 isolation); `kill_rumour`
  buries a fact until the next day change (BeliefNet forgets its rumour beliefs then; use
  `BeliefNet.forget_rumours(fact)` for an immediate effect); `get_neighbours()` includes every link
  type (rivals too) — "allies" = friendship/couple (`NPCDirectorSystem.ALLY_LINK_TYPES`); SocialGraph
  does not rewire links on `seat_filled` except department links of an NPC who changes post.
- **Helper libraries (src/simulation, class_name, static or RefCounted):** UtilityAI
  (`static func evaluate(npc: NPCRuntime, context: Dictionary) -> Dictionary` returning
  {action, score, scores}), Bribery, CaughtHandler, InvestigationEngine, Interrogation,
  IdeaPresentation, DutySystem, InventoryRules, Disguise, Police, FactoryTheft, Buyers, Strike,
  Endgame, Perception (Perception is a Node attached to NPC nodes — World phase), PlayerRecords
  (pure data container of PlayerState's external memory; PlayerState owns and saves it).
- **Localisation check:** `tools/check_locale.py` (`--sim` = only simulation layer + data decide
  the exit code) verifies that every key used by data (`*_key`, `*_keys`, ALL_CAPS values) and code
  (ALL_CAPS literals, the dynamic key families of the simulation layer expanded from their real
  domains, other `"X_%s"` formats / `"X_" +` prefixes) exists in strings.csv with EN and ES.

## 14. World & presentation contract (World phase)

- **FloorLayout** (`src/world/floor_layout.gd`, class_name FloorLayout, static, pure, deterministic):
  `static func compute(floor: int) -> Dictionary` returning a FloorPlan:
  `{floor, size: Vector2i (cells), rooms: {room_id: Rect2i}, doors: [{a, b, cell: Vector2i, vertical: bool,
  kind: "normal"|"reader"|"service"|"old_lock"|"vent"}], transit: [{id, kind: "elevator"|"stairs"|
  "service_stairs"|"freight"|"vent_hatch"|"exit", room_id, cell: Vector2i, targets: Array}], corridor_id}`.
  Used by FloorStreamer, the map (Tab) and NPC pathing. Same input → same output.
- **RoomBuilder** (`src/world/room_builder.gd`): builds the node tree of one RoomData at a cell offset:
  floor/walls/doors drawn by code with the band palette, furniture visuals, collisions, Interactable
  nodes, hiding spots, SecurityCamera nodes. **Physics layers**: 1 walls, 2 tall furniture (blocks
  movement AND line of sight), 3 low furniture (blocks movement, *partial* LOS obstruction ×0.4),
  4 player, 5 NPCs, 6 interactables/areas. Pixel size of a cell = balance `mundo.px_por_unidad`.
- **FloorStreamer** (`src/world/floor_streamer.gd`, Node2D in the game scene): `load_floor(floor)`,
  `get_current_floor()`, `get_room_at(world_pos) -> String`, `get_room_rect_px(room_id) -> Rect2`,
  `cell_to_world(floor_cell) -> Vector2`, `find_path(from_px, to_room_id) -> PackedVector2Array`
  (room graph + door points; NPCs walk it), `get_spawn_point(room_id) -> Vector2`,
  `get_interactables_in_room(room_id)`. Emits `room_entered/room_exited(room, by_player)` for the
  player; emits `floor_changed` when it loads a different floor.
- **Interactable** (`src/entities/interactable.gd`, class_name Interactable extends Area2D, group
  "interactables"): `interact_id, interact_type, room_id, data: Dictionary`, `get_prompt_key() -> String`,
  `is_available() -> bool`. The player picks the nearest one in range; actions are dispatched by
  `src/world/interaction_router.gd` (class_name InteractionRouter) — one handler per type.
- **Player** (`src/entities/player.gd`, CharacterBody2D, group "player"): `movement_mode() -> String`
  ("sneak"|"walk"|"sprint"|"crouch"|"still"), `is_crouching()`, `is_sprinting()`, `is_still()`,
  `current_act() -> String` (crime type being performed or ""), `begin_act(crime_type, seconds)`,
  `end_act()`, `set_input_locked(bool)`, `get_facing() -> Vector2`, `play_anim(name)`.
- **NPC node** (`src/entities/npc.gd`, CharacterBody2D, group "npcs"): `npc_id`, reads NPCRuntime from
  NPCDirector, walks FloorStreamer paths to its scheduled room/desk, shows archetype tics, carries a
  Perception child (`src/simulation/perception.gd`, vision cone + hearing) and a DetectionIndicator.
- **CharacterPainter** (`src/entities/character_painter.gd`, static): `appearance_from_seed(seed: int,
  tier: int, is_named: bool, accessory: String) -> Dictionary` (the §14.4 layers) and
  `draw(canvas: CanvasItem, appearance: Dictionary, tier: int, pose: Dictionary)` — shared by player,
  NPCs, portraits in PERSONNEL and the menus. Silhouette by tier (§14.5), 8-12 frame limited animation.
- **UIRoot** (`src/ui/ui_root.gd`, CanvasLayer, group "ui_root"): `open_modal(control, pauses_clock: bool)`,
  `close_modal()`, `has_modal()`, `toast(text_key, args := [])`, `open_computer()`, `open_phone()`,
  `open_map()`, `open_inventory()`, `show_dialog(title_key, body_key, options: Array) -> int` (awaitable).
  HUD, subtitles, detection overlays are children. Theme from `src/ui/ui_theme.gd` (`UITheme.build(text_size, high_contrast) -> Theme`).
- **Game scene**: `scenes/world/game.tscn` → `src/world/game_root.gd` owns FloorStreamer, the Player,
  the NPC layer, UIRoot, CaughtHandler, DutySystem, AudioDirector (`src/ui/audio/audio_director.gd`).
  Boot flow: `scenes/boot.tscn` → main menu (`src/ui/main_menu.gd`) → opening cinematic → tutorial →
  game. `src/util/autopilot.gd` drives scripted runs for screenshots/QA.

## 15. Game session & interaction modules (Phase 4 — game root)

- **Game scene** `scenes/world/game.tscn` → `GameRoot` (`src/world/game_root.gd`, group `game_root`,
  `GameRoot.find(tree)`). Public members: `streamer`, `player`, `npc_layer`, `ui`, `audio`, `travel`
  (FloorTravel), `bridges` (WorldBridges), `promotion` (PromotionFlow), `time_skip` (TimeSkip),
  `sim_nodes` {CaughtHandler, DutySystem, HomeCycle, Police, NightOps, Endgame}; `get_mode()` ("new"|"load"),
  `observers_present()` (registered as `GameClock.set_observer_check`), `open_pause_menu()`,
  `end_run(cause, ending_id)` (WorldBridges calls it on `game_over`: stops the world → EpilogueScreen → menu).
  Lifecycle: `GameSession` (`src/world/game_session.gd`) — `read_request()` (GameLaunch + `--seed`,
  `--force-rank`, `--skip-intro`), `begin_new_run(request)` (§2 order; also stores the name-entry portrait seed
  in `PlayerState` flag `Player.PORTRAIT_FLAG`), `load_saved_run()`. New run: player at `partida.sala_inicio`
  (turnstiles, PB) at 08:00, then `run_started`. Continue: `SaveSystem.load_run()` then the player wakes in
  `hogar.sala_domicilio`. **Tutorial hook**: `GameRoot.tutorial_hook = func(root: GameRoot) -> void` — when set
  and `GameSession.wants_tutorial(request)`, the new run starts in `partida.sala_tutorial` and the hook is
  called right after `run_started`.
- **Placing the player / changing floor from code**: never call `streamer.load_floor` + move the player by hand;
  use `GameRoot.travel.teleport_to_room(room_id, cells := (-1,-1))` or `teleport(floor, point)` (loads the floor,
  snaps to a walkable cell, refreshes camera bounds). Interactables of the old floor are FREED by a floor
  change: never keep references to them across an `await` that may travel.
- **InteractionRouter** (`src/world/interaction_router.gd`, static): the player's E / action button calls
  `InteractionRouter.interact(focus, player)`. It dispatches on `Interactable.interact_type` to ONE module.
  Module = a script in `res://src/world/interactions/<family>.gd` (files starting with `_` are private; the
  router scans the folder once, alphabetically; built-ins first: `floor_travel.gd`, `world_bridges.gd`).
  A type claimed twice → the first wins (push_warning). Unknown type → `_default.gd` (toast
  `INTERACT_NOTHING_USEFUL`; type `"npc"` opens the NPC quick card until `social.gd` claims it).
  Contract (all **static**, the module holds no state; keep state in the owning autoload or a scene node):
  ```
  # src/world/interactions/office.gd — Interacciones de oficina: cajones, ordenadores ajenos, archivos...
  # PROPIETARIO DE: nada.
  # ESCUCHA: nada.
  extends RefCounted

  static func handled_types() -> Array[String]:                 # required
      return ["drawer", "npc_computer"]

  static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:   # required, may await
      var ui: UIRoot = ctx["ui_root"]                           # ctx = {game_root, ui_root, streamer, room_id, floor}
      match interactable.interact_type:
          "drawer":
              player.begin_act("theft_small", 2.0)              # visible act → Perception can catch it
              var r: Array = await player.act_finished          # [crime_type, completed]
              if not r[1]: return                               # moved away = cancelled
              EventBus.crime_committed.emit("theft_small", interactable.room_id, {"value": 12})
              ui.toast("OFFICE_DRAWER_LOOTED", [12], ToastStack.KIND_GOOD)
          "npc_computer":
              StellarOS.open_intrusion(str(interactable.data.get("owner", "")), {"computer_id": interactable.interact_id,
                      "room_id": interactable.room_id, "contains": interactable.data.get("contains", [])})

  static func is_available(interactable: Interactable, player: Node) -> bool:   # optional (default true)
      return interactable.interact_type != "npc_computer" or not _owner_present(interactable)

  static func prompt_key(interactable: Interactable) -> String:                 # optional ("" = UI_INTERACT_<TYPE>)
      return "UI_INTERACT_DRAWER_FORCE" if interactable.data.get("locked", false) else ""
  ```
  Rules for modules: every action gives feedback (toast / subtitle via AudioDirector.play_sfx / animation);
  irreversible actions use `await ctx.ui_root.show_dialog(...)` with the danger option not focused (§13.7);
  crimes go through `player.begin_act(crime, seconds)` + `EventBus.crime_committed` (details per
  docs_integration_todo); time costs via `GameClock.advance_minutes`; never emit `floor_changed`/`room_entered`.
  Tests may inject a module with `InteractionRouter.register_module(script)`; `InteractionRouter.reset()` rescans.
  `InteractionRouter.handled_types_map()` lists type → module for debugging.
- **NPC interactable**: every `NPCNode` carries a hidden `Interactable` child `Interact` of type `"npc"`,
  `data = {npc_id}`, `room_id` kept current. The social module claims `"npc"`.
- **Types already owned by the game root**: `elevator_panel`, `stairs_door`, `service_stairs_door`,
  `freight_panel`, `vent_hatch`, `roof_ledge`, `exit` → `FloorTravel` (rules in its header, balance `viaje.*`);
  `dropped_item` → `WorldBridges` (items the player drops through the inventory: group `item_drop_handlers`).
- **Scene glue already wired** (WorldBridges / PromotionFlow / TimeSkip): game over → epilogue → menu;
  `aurora_meeting_started` → `IdeaPresentation.summon_attendees()`; denied doors → `card_denied` + toast;
  `interrogation_started` (player in shortlist) → summons dialog → interrogation room → `InterrogationScene`;
  home ↔ work commute (`HomeCycle.commute()`); own computer → player sits (`sit_type`); promotions (toast on
  `promotion_available`, accept/decline with confirmation from the pause menu, `PromotionScreen` on
  `occupation_changed`, new desk); time skip (key **T** or pause menu, §15.6, balance `salto_tiempo.*`).
