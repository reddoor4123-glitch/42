# Headless Harness Reference

### Purpose of this doc
Read this before writing any new headless Godot experiment script. It's
plumbing, not findings — copy the template, reuse the conventions, don't
re-derive any of this from `game_table.gd` or `ai_player.gd` again. Findings
from specific experiments (Job 2's ceiling/quantity result, Job 3's per-tile
profile, etc.) live in their own session docs, referenced at the bottom —
this file never grows a "results" section.

Compiled July 15, 2026 from Jobs 1–3. Update it when a new job finds a new
gotcha or changes the template; don't let it silently drift the way other
docs in this project have needed correction passes for.

---

## Where things live

Everything headless is under `headless/`, and nothing else is. If a file
`extends SceneTree` it belongs there; if it declares a `class_name` and the
game loads it, it belongs at the repo root. That split is the whole rule.

Consolidated July 30, 2026 — the `*_trace.gd` harnesses used to sit at the
repo root mixed in with the game's own scripts, while everything newer lived
in a folder called `scripts/`. Both were headless-only, so they became one
folder with a name that says what it holds.

`headless/*.json` is **gitignored**. Every JSON in there is written by a
script sitting beside it, so it is regenerable, and tracking it only produced
diff noise whenever a harness was re-run. Findings worth keeping go in a
session doc, not in a committed result file — the same rule this doc already
follows about not growing a results section. Add a `.gitignore` exception if
a hand-authored fixture ever needs to live there.

---

## Quickstart — copy/paste this first

```bash
GODOT="/c/Users/reddo/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
cd "/c/Users/reddo/Godot/42"
"$GODOT" --headless --path . --script res://headless/<your_script>.gd > /dev/null 2>/tmp/stderr.txt
echo "exit code: $?"
cat /tmp/stderr.txt
```

**The `.exe` is inside a folder that is itself named `....exe`** — the real
binary is `Godot_v4.6.3-stable_win64_console.exe` one level inside that
folder. Easy to lose ten minutes to this; don't re-search for it, this path
is confirmed current as of July 15, 2026. If it's ever missing, the folder
was `C:\Users\reddo\Downloads\Godot_v4.6.3-stable_win64.exe\`.

**Always redirect stdout to `/dev/null` (or a scratch file you don't read)
for batch runs, then read results from a JSON file the script writes
directly.** `game.gd`'s `resolve_trick()` prints two lines per trick
unconditionally — capturing that through any logging layer inflates wall
time ~8x at batch scale (I/O-bound, not compute-bound) and burns context for
nothing. Never `cat`/`Read` the raw stdout of a batch run.

Engine compute cost: ~2.7 ms/hand. 1000 hands ≈ a few seconds. Default to
N=1000, not N=100-then-maybe-more — it's cheap.

---

## Reusable template

Every job so far (`headless/headless_test_job1.gd`,
`headless/job2_ceiling_vs_quantity.gd`, `headless/job3_experiment.gd`) is a
variation on this skeleton. Start from this, not from a blank file.

```gdscript
extends SceneTree

const BidScript = preload("res://bid.gd")

const TRUMP_SUIT := 6          # whatever the experiment needs
const BID_VALUE := 30
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2        # (BIDDER_SEAT + 2) % 4
const N_TRIALS := 1000
const DIFFICULTY := "expert"   # see Difficulty & determinism below

func _build_full_deck() -> Array:
	var pool: Array = []
	for a in range(0, 7):
		for b in range(a, 7):
			pool.append(Domino.new(a, b))
	return pool

func _take(pool: Array, a: int, b: int) -> Domino:
	var lo = min(a, b); var hi = max(a, b)
	for i in range(pool.size()):
		var d: Domino = pool[i]
		if d.left == lo and d.right == hi:
			pool.remove_at(i)
			return d
	push_error("Tile %d:%d not found in pool" % [a, b])
	return null

func _setup_game() -> Game:
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()          # per-hand resets; hands overwritten below
	# ... build/assign game.players[i].hand per seat here (fixed tiles via
	# _take(), or a straight deal_hands() random deal if nothing needs pinning)
	return game

func _play_trial() -> Dictionary:
	var game = _setup_game()
	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
	game.current_bid = bid
	game.apply_bid_result(TRUMP_SUIT)

	var leader = BIDDER_SEAT
	for trick_num in range(7):
		game.start_trick(leader)
		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var is_partner = (player.id == PARTNER_SEAT)   # SEE GOTCHA #1
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				DIFFICULTY, is_partner, game.variant,
				game.current_bid.player_id, knowledge,
				game.team_points, game.current_bid.value
			)
			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4   # SEE GOTCHA #2
		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)  # SEE GOTCHA #3
		leader = winner_id

	var result = game.resolve_hand()
	return result   # pull whatever fields the experiment needs

func _init():
	var wins = 0
	for i in range(N_TRIALS):
		var r = _play_trial()
		# accumulate...
	# write results to a JSON file, NOT stdout — SEE GOTCHA #4
	var f = FileAccess.open("res://headless/results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({}, "\t"))
	f.close()
	quit(0)
```

---

## Gotchas — each one fails silently, not loudly

1. **`is_partner` has no auto-derivation.** `decide_play()`'s `is_partner`
   parameter (signature ~line 461) defaults to `false` and is never computed
   from `player_id`/`partner_id` internally. Forget to pass it per-seat and
   the intended Partner seat quietly runs Opponent logic instead — no
   crash, no warning, just a meaningless result you won't notice until the
   numbers look off. The live game computes it at `game_table.gd:1485` as
   `player.id == (human_seat + 2) % 4`; your script must do the equivalent
   explicitly.

2. **Turn order is `(current_player + 3) % 4`, i.e. -1 mod 4, not +1.**
   Confirmed against `game_table.gd:1631`. Not derivable from `game.gd`
   alone. Doesn't break outcome validity in experiments where both Opponent
   seats run identical logic (it's a mirror image), but there's no reason
   to re-derive it — just reuse it.

3. **`record_trick()`'s third argument must be `game.current_trick.plays`,
   not `[]`.** `game.gd`'s `record_trick(trick, winner_id,
   plays_with_reasons)` stores whatever you pass as `hand_history`'s
   `"plays"` field verbatim — it does NOT read `trick.plays` itself.
   `trick.plays` already holds `{"player":..., "domino":...}` per play, in
   order, which is exactly the right shape. Job 1 and Job 2 both passed
   `[]` here; it didn't matter for either (both only read final
   `team_points`/`resolve_hand()`, never `hand_history`), but **any
   experiment needing per-tile or per-trick detail must use the fix** or
   `hand_history[i]["plays"]` will silently be empty for every trick.

4. **`game.gd`'s `resolve_trick()` has unconditional `print()` calls baked
   into the file itself** — not a debug flag, can't be turned off without
   editing a live game file (out of scope for these experiments). Always
   redirect stdout to `/dev/null` for batch runs; write results to a JSON
   file via `FileAccess` directly instead of parsing stdout.

5. **`HandRecordWriter` looks like an autoload by name — it isn't one.**
   It's a static-func `RefCounted` class (`hand_record_writer.gd`). No
   registration needed, calls it directly (`HandRecordWriter.reset_for_new_hand()`
   etc., which `game.gd`'s `deal_hands()` already does for you). Don't go
   looking for an autoload config that doesn't exist.

6. **A brand-new `class_name`-declaring script can't resolve its own
   self-reference until one editor pass registers it.** Confirmed July 22,
   2026 with a fresh `player_profile.gd` (`class_name PlayerProfile`):
   calling `PlayerProfile.new()` inside one of the class's own static
   methods threw `Compile Error: Identifier not found: PlayerProfile` when
   loaded via plain `load()` in a headless script — even though the
   identical self-referential pattern (`GameSettings.new()` inside
   `GameSettings.from_dict()`) works fine, because `GameSettings` has
   already been registered in Godot's global class cache from prior runs.
   **Worse:** `load()` still returned a non-null `GDScript` object despite
   the failed compile — `script != null` is not proof the script actually
   compiled; the returned stub fails on the first real method call
   (`Invalid call. Nonexistent function '<name>' in base 'GDScript'`).
   Fix: run `"$GODOT" --headless --editor --quit --path .` once (same
   fix as the PNG-import-needs-one-pass gotcha, just for `class_name`
   registration instead of asset import) before trusting any headless
   test of a new `class_name` file. Watch the output for `Registering
   global classes... <YourClassName>` to confirm it actually registered.

---

## Seat convention (a choice, not a code requirement)

| Seat | Role | `is_partner` |
|---|---|---|
| 0 | Bidder | false |
| 1 | Opponent | false |
| 2 | Partner (bidder's teammate, `(0+2)%4`) | **true** |
| 3 | Opponent | false |

Free to change if an experiment needs a different arrangement (e.g. bidder
somewhere other than seat 0) — just be explicit about the new mapping in
the script's header comment, the same way this one is.

---

## Difficulty & determinism

**Two tiers as of July 29, 2026, not three.** `AI_MODES` is now
`casual`/`expert`. `casual` is the former `beginner` with identical numbers;
the former middle tier `standard` is retired. Anything written before that
date that names `"standard"` or `"beginner"` as a difficulty is stale —
`headless/bid_filter_trace.gd`, `headless/partner_overbid_gate_trace.gd`, and
`headless/trump_control_trace_v2.gd` were all updated in that pass.

- A retired name won't crash a *call* — `GameSettings.normalize_difficulty()`
  maps `"standard"` → `"expert"` at every persisted read site, and
  `AI_MODES.get(difficulty, AI_MODES["expert"])` catches anything that slips
  past. But it also won't warn you: your scenario silently runs Expert under
  whatever label you gave it.
- **A direct `AI_MODES["standard"]` subscript is a hard error, not a
  fallback.** Dictionary key access throws on a missing key, and it throws
  even when it appears as a `.get()` default argument, because GDScript
  evaluates default arguments eagerly on every call. This is what made
  removing the key a crash risk rather than a stale-data risk.
- `AI_MODES["casual"]` has `opportunism: 0.0` — never takes the tactical
  branch, so it's deterministic too, but for the opposite reason to Expert.
  The old middle tier's `0.6` (a real per-decision coin flip that tangled a
  second source of randomness into any batch) no longer exists.
- `AI_MODES["expert"]` has `opportunism: 1.0` — always evaluates tactically,
  no roll, fully deterministic given the same hand/trick state.
- Partner's own `decide_play()` logic has **zero difficulty branching at
  any setting** (confirmed, `ai_player.gd` ~line 568 — cooperative judgment
  is constant across difficulty). Expert vs. Standard makes no behavioral
  difference for a seat running Partner's logic specifically.
- Bidding (`decide_bid()`) has no roll at any difficulty either — it's a
  pure formula.
- **Default: use `"expert"` for all seats in any experiment that needs
  isolation from incidental AI randomness.** It pins the Opponent seats
  deterministic and costs nothing elsewhere (Partner/bidding are already
  deterministic regardless).

### Gotcha #7 — a scene added in `_init()` is never `_ready()`

Adding the main scene to the root from a `SceneTree` script's `_init()` gives
you a constructed-but-un-readied node: `_ready()` hasn't run, so every UI
member is still `null` and `get_viewport()` returns `null`. You get a pile of
"Cannot call method on a null value" errors that read like the UI is broken
rather than like you looked too early — and if the script then fails before
reaching `quit()`, the main loop runs until your shell timeout kills it.

Use `_initialize()` to build and `_process()` to test, returning `false` for
the first couple of frames and `true` to quit:

```gdscript
var _table: Node = null
var _frame := 0

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false    # let _ready()/_build_ui() finish
	_run_checks()
	return true         # quit
```

Only needed for tests that touch the live node tree. Pure-logic probes over
`Game`/`AIPlayer`/`GameSettings` (Jobs 1–3) still work fine from `_init()`.

### Gotcha #8 — `queue_free()` doesn't clear a container within one call

A `for c in node.get_children(): c.queue_free()` loop followed by
re-populating the same container leaves the old children parented until the
end of the frame, so a child count taken right after the rebuild reads
double. It's genuinely visible (one frame of doubled content) on any panel
that rebuilds in response to a button press rather than only on open.
`game_table.gd`'s `_clear_children()` detaches first, then frees.

The same frame-boundary rule bites when *measuring*. A Control's `size` only
catches up after a layout pass, so reading it in the frame you changed
something reports the old value. That can silently invalidate an assertion
rather than fail it: a before/after size comparison taken in one frame reads
the same stale number on both sides and passes no matter what the code does.
`get_combined_minimum_size()` is computed on demand and doesn't need the
wait — but it also won't catch a container that failed to *shrink*, since a
container tracks its child's minimum while leaving an already-larger `size`
alone. If the thing under test is whether something resized, put a frame
either side and assert on `size`.

### Gotcha #10 — `return true` from `_process()` always exits 0

In the `_initialize()`/`_process()` shape from gotcha #7, ending the loop by
returning `true` exits with status **0 regardless of what the suite found** —
a fully failing run reports as clean, and only the results JSON tells the
truth. Call `quit(1 if failures > 0 else 0)` before returning. Two harnesses
shipped with this before it was noticed.

Related: a harness that starts a real game (`_on_preset_chosen()` or similar)
will print `ObjectDB instances leaked at exit` on stderr. Bidding kicks off a
coroutine that parks on a 1-second timer — `DEBUG_FAST_MODE` is a `const`, so
it can't be shortened at runtime — and it is still suspended when the harness
exits. Benign, and `free()`ing the table doesn't clear it. For those scripts
judge the exit code and the JSON, not stderr.

### Gotcha #9 — headless tests write to the real `user://`

`user://` in a headless run is the same
`%APPDATA%/Godot/app_userdata/42/` the game uses. A test that exercises
persistence will overwrite real save data — `last_used.json` especially, which
carries `last_preset`, `ai_difficulty`, **and** Profiles' `seat_assignments`.
Back it up before the run and restore after.

---

## Fixing a contract without running a real auction

Skip `decide_bid()` across all four seats when bidding variance isn't what
the experiment tests: call `decide_bid()` once (or `AIPlayer.evaluate_hand()`
/`best_trump()` directly, if you're gating a hand for bid-worthiness rather
than issuing a real bid), take the `trump`/`target_bid` it produces, then
hardcode `current_bid` and call `apply_bid_result(trump)` directly for every
trial:

```gdscript
var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
game.current_bid = bid
game.apply_bid_result(TRUMP_SUIT)
```

This is what all three jobs so far did — bidding auction dynamics (raises,
passes, other seats bidding) have never been exercised by any of these
experiments.

`AIPlayer.evaluate_hand(hand, trump)` (returns `estimated_points`,
`trump_count`, `has_double_trump`, `estimated_tricks`, ...) is the right
tool for gating a candidate hand's plausibility before committing it to a
batch run — see Job 2's correction (it originally didn't gate Partner's
hand at all, produced a "strong hand beats weak hand" result mislabeled as
"ceiling beats quantity"). `AIPlayer.decide_bid()`'s own out-parameter
(`bid_decisions`, appended with `{hand, eval, should_bid, target_bid}` per
call) is the right tool when you need the *actual issued bid*, not just the
evaluator's raw number — see Job 3 Step 1.

---

## Script inventory

| Script | What it does |
|---|---|
| `headless/headless_test_job1.gd` | Single hand, verbose — the original viability check. Good template for a one-off debug rerun with full trick-by-trick output. |
| `headless/headless_timing_test.gd` | Batch timing probe, N configurable — use to re-benchmark if engine/hardware changes. |
| `headless/job2_ceiling_vs_quantity.gd` | Fixed-archetype Partner hand vs. random reshuffle of the other three seats; writes `job2_results.json`. |
| `headless/job2_hand_eval_probe.gd` | Throwaway iteration tool for testing candidate hands against `evaluate_hand()` before committing them to a batch — not itself a batch script. |
| `headless/job3_find_bidworthy_hand.gd` | Random-deal-until-clears-threshold search using `decide_bid()`; writes `job3_fixed_hand.json`. |
| `headless/job3_experiment.gd` | Fixed bidder hand vs. random reshuffle of the other three seats, with per-tile `hand_history` stats; writes `job3_results.json`. First script to use the Gotcha #3 fix. |
| `headless/menu_merge_verify.gd` | Assertion suite for the Menu/Rules/Settings merge: difficulty normalization at every read shape, `AI_MODES` shape, slot resolution isolation, slot-name independence, domino-back independence, `last_used.json` routing. Writes `menu_merge_verify_results.json` with a `failures` count; exits non-zero on any failure. First script to use the Gotcha #7 pattern. |
| `headless/menu_merge_ui_probe.gd` | Smoke-drives every screen that merge restructured (settings rebuild per slot, reset popup, rename popups, the Choose Rules "…" menu, difficulty screen, first-launch vs. returning routing) and reports node counts. Treat non-empty stderr as failure. |
| `headless/nello_laydown_verify.gd` | Assertion suite for `LaydownCheck.is_provable_nello_laydown()` — all four doubles modes, void discards, both ends of mixed tiles, the strand shape, and a full seven-trick position for cost (~450 ms). Pure logic, no scene, no `user://`. Exits non-zero on failure. |
| `headless/laydown_ends_hand_verify.gd` | Regression suite for "a decided hand stays playable underneath the result banner". Drives the real handlers — claims a lay-down mid-hand, then taps a tile the way a player would. Verified to fail without the fix. Expect the gotcha #10 stderr warning; judge the exit code. |
| `headless/tricks_expand_persist_verify.gd` | Regression suite for the trick lists keeping their expanded/collapsed state across hands, including that an open panel snaps back to the emptied pile's height instead of reopening at last hand's. Phased across layout frames — see the note in gotcha #8 about why `.size` needs one. Expect the gotcha #10 stderr warning. |
| `headless/node_leak_probe.gd` | Per-class node census before/after N rebuild cycles. Use when a leak *number* needs attributing to an actual class — a bare `OBJECT_NODE_COUNT` delta says "something grew", this says what. |
| `headless/menu_merge_screenshot.gd` | Renders the reset popup and both "…" menu variants to PNGs for eyeball review. Must run **without** `--headless`, same as `font_screenshot.gd`. |

None of these modify `ai_player.gd`, `game.gd`, or any other live game
file — every job so far has been read-only instrumentation on top of
existing `Game`/`AIPlayer` APIs.

---

## Open ideas parked, not built

- **Job 4** (repeat Job 3's method on 3–4 more independently-found
  qualifying hands) — checks whether "trump concentration beats individual
  tile rank" and "off-suit lead timing matters more than rank" generalize,
  or were specific to one hand.
- **Partner-strategy-stripped opening-lead sweep** — force Partner's first
  lead to specific candidate tiles, randomize all of Partner's other
  decisions among legal moves only (bidder and both Opponents keep real
  logic), compare outcomes across candidate leads. Requires writing a new,
  separate, experiment-only stand-in for Partner's decision function — a
  genuine step up in build effort from Jobs 1–3, not just new
  orchestration around existing code.
- **Role-bucket aggregation across many different hands** — instead of
  pooling stats by literal tile identity (which mixes different roles
  across hands with different trump suits), aggregate by hand-relative role
  (trump doubles, trump rank-≥4 non-doubles, off-suit doubles held
  alongside another double, etc.). Likely the more direct route toward real
  ground-truth data for the parked Capabilities-layer vocabulary
  (quantity/ceiling/continuity/counter-cost) than testing literal archetype
  hands.
- **Real-hand library** — an actual dealt hand from real play (logged
  during a July 15 session: `2:6, 0:3, 3:6, 5:5, 2:5, 2:3, 6:6`, bid to 30,
  Splash called, trump ended up Ones) is a candidate first entry for a
  small library of organically-dealt hands, for a "how robust is this real
  hand" study distinct from the controlled single-variable experiments
  above.

---

## Findings on file (detail lives in each job's own record, not here)

- **Job 2** (ceiling vs. quantity, matched for bid-worthiness via
  `evaluate_hand()`): Quantity (5 trump, 1 off-suit double, estimated_points
  26.81) beat Ceiling (2 trump concentrated at the top, 4 doubles,
  estimated_points 29.16) 94.0% to 66.2% win rate across 1000 trials each —
  despite Ceiling scoring higher on the evaluator's own yardstick. Connects
  to an already-open concern
  (`Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md`, §4)
  that the off-suit-doubles compounding bonus in `evaluate_hand()` may
  overvalue doubles-heavy hands relative to real trick-conversion — logged
  as corroborating evidence, not yet resolved.
- **Job 3** (one organically-found bid-worthy hand, per-tile profile over
  1000 trials): trump concentration (5 of 7 trump held) made even the
  weakest trump tile win 100% of the time played; two off-suit tiles of
  adjacent rank diverged sharply (66.2% vs. 3.4% win rate) due to an
  apparent lead-timing effect rather than a rank-quality difference.
