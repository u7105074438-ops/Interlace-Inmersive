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
