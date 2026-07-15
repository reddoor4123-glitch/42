# Texas 42 — Project Onboarding

*Written as if introducing a new consultant to the codebase for the first
time. Last verified against code: July 15, 2026.*

*This document covers orientation, file roles, and standing engineering
principles only. It deliberately does not carry AI design philosophy (see
`AI_Design_Doctrine.md`), exact current `decide_bid()`/`decide_play()`
mechanics (see `Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md`
and `Phase3_Objective_Audit_REWRITE_July14_2026.md`), or a list of open
items (see `Backlog_Triage_Combined_July15_2026.md`). For full navigation,
see `Texas_42_Documentation_Map.md`.*

---

## 1. What this project is

A Texas 42 domino game built in Godot 4 (GDScript), a desktop build,
currently in Alpha testing (aziruar.itch.io/42), with an eye toward
eventual publishing. Katy is the project owner and lead designer. Mobile is a deliberately deferred target — see §2's proportional-
sizing convention and portrait-layout plan.

**Design philosophy — read `AI_Design_Doctrine.md` before touching AI
code.** In short: the goal is emotional authenticity, not technical
perfection — *"that partner plays just like my uncle."*

---

## 2. Standing engineering principles

- **Function containment.** Each subsystem owns its own concern; nothing
  bleeds across the boundary. `Trick` is purely mechanical (turn order,
  legality, resolving a winner) and must never accumulate inference logic.
  `PublicKnowledge` is the only place inference about voids/played tiles
  lives — if any other file inspects `trick.plays` to reason about
  suit-following, that's the boundary being crossed, even for a one-line
  convenience check. Two implementations of the same inference is a real
  bug class, not a style nit.
- **Difficulty is not a library of special cases.** Before writing
  `if difficulty == "expert"`, classify the difference as Knowledge,
  Evaluation, or genuinely Neither — the litmus test lives in
  `AI_Design_Doctrine.md`. `AI_MODES` is a single dict of named parameters;
  that's where personality differences belong, not scattered conditionals.
  Current shape: `risk_bias`/`max_overbid` (bidding), `vigilance`
  ("none"/"full") and `opportunism` (0.0–1.0, rolled fresh per eligible
  decision) (play). `decide_play()` has zero bare `if difficulty == ...`
  branches anywhere, partner included.
- **Avoid hardcoding wherever a computed/derived value will do**, especially
  for layout or game math. Mobile tile sizes are computed proportionally
  from viewport width (font sizes are still hardcoded — flagged future
  cleanup). Mobile portrait layout is planned, not built: when picked up,
  detect aspect ratio at startup and branch `_build_ui()` into
  `_build_ui_landscape()`/`_build_ui_portrait()`; menu panels' fixed 480px
  minimum width will need relaxing for narrow screens. Game logic is
  already fully decoupled from layout, so this split should be
  straightforward when the time comes.
- **State lives in exactly one place.** `PublicKnowledge` is rebuilt fresh
  from a `PublicFrame` at every decision point rather than cached or
  mutated incrementally — deliberately, to avoid drift between a stored
  dictionary and the history it's supposed to represent. `HandRecordWriter`
  holds only bookkeeping about its own job and is explicitly barred from
  holding a copy of hand data: *"Any future extension must not introduce
  persistent cross-hand state outside `game.gd` or `HandRecordWriter`."*
- **When a spec's complexity starts cascading, shrink scope — don't push
  through.** Add clarity, not machinery, when something feels like it's
  getting away from you.

---

## 3. File inventory

### Core game logic
| File | Role |
|---|---|
| `game.gd` | The `Game` class — central game state. Owns players, shaker/turn tracking, bid state, `hand_history`, `deal_snapshot`, `bid_decisions`, `hand_result`, `flags`, and score tracking. Deals hands, drives bidding order, resolves tricks/hands, and assembles `build_hand_record()` for replay/export. |
| `ai_player.gd` | Static utility class — all AI bidding and play decisions. See §4. |
| `game_table.gd` | The UI/orchestration layer — builds the entire UI programmatically, drives game flow, and is the thing that calls into `AIPlayer`. See §5. |
| `trick.gd` | `Trick` class — purely mechanical: tracks plays, computes legal moves, determines the trick winner. Deliberately free of any inference logic. |
| `trick_pile.gd` | Visual trick-pile widget. |
| `bid.gd` | `Bid` class — bid types and validation (`is_valid()`). |
| `player.gd` | Lightweight `Player` data holder. |
| `deck.gd` | Builds and shuffles the 28-tile double-six set, deals hands. |
| `domino.gd` | `Domino` class — pip values, suit/rank logic, mode-aware across trump, Nello doubles-high/low/own-suit (including own-suit-reversed), and doubles-trump-reversed. |
| `domino_tile.gd` | Visual node for a single domino tile. |
| `game_settings.gd` | `GameSettings` — all configurable rules and presets. Settings/toggle audit is closed: every setting is confirmed either live or deliberately parked with a stated reason; no dead/ghost settings remain. |

### AI inference layer
| File | Role |
|---|---|
| `public_frame.gd` | `PublicFrame` — an immutable, plain data holder: completed `hand_history` plus the in-progress `current_trick`. Performs zero inference; the raw material `PublicKnowledge` is built from. |
| `public_knowledge.gd` | `PublicKnowledge` — the sole inference layer for anything derivable from public play. A vocabulary layer, not a decision layer: every query has one objective answer, never evaluates or recommends, never varies by difficulty (see the file's own header contract). Built fresh via `from_state()` at each decision point, never cached. See the file header for the full query list. |

### Replay / hand record
| File | Role |
|---|---|
| `hand_record_writer.gd` | `HandRecordWriter` — static, stateless except bookkeeping. Serializes `build_hand_record()` output and persists it (overwrite-on-every-flag on desktop, single-download-on-first-flag on web). |
| `marks_display.gd` | Visual marks-won display widget. |
| `drum_picker.gd` | Reusable scrolling number picker. |

### Scaffolding / misc
| File | Role |
|---|---|
| `node_2d.gd` | Pre-AI test harness; rotates turns the *opposite* direction from the game's real convention. Harmless leftover, not live code. |
| `test.gd` | Minimal test stub. |
| `control.tscn`, `domino.tscn` | Godot scene files backing the above. |

---

## 4. AI decision-making — current architecture, in brief

Full mechanics and open items live in the dedicated docs linked at the top
of this file. This section is only the map, not the territory.

- **`decide_bid()`** — three layers: Evaluation (`evaluate_hand`,
  `best_trump` — objective hand truth), Decision policy (combines EV,
  a control signal, and auction-stance bias into one score), Execution
  (auction legality only, never re-scores). Settled architecture, not
  slated for restructuring. → `Bidding_System_Overview`
- **`decide_play()`** — Sevens and Nello bypass all standard evaluation
  entirely (different games sharing the trick-taking shell, not variations
  of standard play). Everything else: geometry → objective (Selection) →
  optional commitment gate → execution. → `Phase3_Objective_Audit_REWRITE`
- **Reasoning strings** (`reason_log.append(...)`) are produced at every
  decision point, always first-person, always describing what the AI
  *believed* — never what the human should have done. Tone/accuracy issues
  are tracked separately. → `AI_Explanation_Bug_Log.md`
- **The HandRecord/flagging system** is fully implemented: every flag event
  rebuilds a fresh, complete record (`build_hand_record()`) rather than
  holding a live mutable object, and `HandRecordWriter` persists it. This
  is the foundation for future consumers (hand export/sharing, AI
  regression capture) — none of those are built yet.

---

## 5. Deep dive: `game_table.gd`

This is the largest file and the **only** place that talks to both
`Game`/`AIPlayer` and the actual UI. It:

- Builds the entire UI tree programmatically in `_build_ui()` — including
  proportional tile sizing computed from viewport width at build time.
- Drives the full game loop: bidding sequence, trick execution, and hand
  resolution.
- Owns the replay screen — steps back through `hand_history` trick by
  trick, re-rendering each player's hand/plays/reasoning as they were at
  that point, plus a flag panel (bidding/gameplay/explanation toggles +
  free-text note) calling `game.flag_hand()`.
- Is the call site that constructs `PublicFrame`/`PublicKnowledge` and
  calls `AIPlayer.decide_play()` — live and playtest-confirmed.
- Implements "arm a play": the human can tap a legal domino before the
  trick reaches them to pre-select it; it plays automatically the instant
  their turn arrives, with legality re-checked at both arm-time and
  consumption-time.

Notable conventions:
- Player-relative labels ("Partner", "Right Opponent", "Left Opponent")
  are computed from `human_seat`, never hardcoded per seat index.
- `(n+1)%4` = right/clockwise, `(n+3)%4` = left/counter-clockwise — the
  correct seating/play-order convention. (`node_2d.gd` uses the opposite
  direction and is known-harmless dead scaffolding.)
- `DEBUG_FAST_MODE` skips AI "thinking" pauses for faster testing —
  flagged to eventually become a real settings toggle.
- Console `print()` output for trick resolution is prefixed with the trick
  number (`[Trick N]`) and logs the active ranking mode when relevant —
  makes manual-testing traces easy to follow.

---

## 6. Where to find what's currently open

This document intentionally doesn't track open bugs, design questions, or
future ideas — that's `Backlog_Triage_Combined_July15_2026.md`'s job,
sorted by urgency (Alpha Blocker / Quality / Future Architecture /
Research), with pointers back to the three bug logs for full detail on any
given item.

---

## 7. Suggested first questions for a new consultant to ask

- Before touching any judgment-heavy AI behavior: is this a Knowledge
  difference, an Evaluation difference, or genuinely Neither? (See
  `AI_Design_Doctrine.md`.) Also check whether it's actually **Decision
  Geometry** (a directly observable structural fact, same for every seat)
  rather than Knowledge or Evaluation at all.
- Anything touching ranking/comparison logic should go through the same
  canonical functions `Trick`/`AIPlayer` already use, never a locally
  re-derived comparison.
- Anything touching mobile layout should default to proportional/
  viewport-relative sizing, not fixed pixel constants.
- Before assuming a play/bid oddity is a new bug: check the relevant bug
  log's status key first (`AI_Play_Behavior_Bug_Log.md`,
  `AI_Bid_Behavior_Bug_Log.md`, `AI_Explanation_Bug_Log.md`) — it may
  already be categorized, specced, or fixed.
