# Texas 42 — Project Onboarding

*Written as if introducing a new consultant to the codebase for the first time.*

## 1. What this project is

A Texas 42 domino game built in **Godot 4 (GDScript)**, mobile-first portrait layout with desktop as secondary, with an eye toward eventual publishing. Katy is the project owner and lead designer.

**Design philosophy — read this before touching AI code:**

- **Table behavior is design intent, not flavor text.** When Katy describes how a real player behaves at a 42 table, that description is the precise spec — not a mood board.
- **Authenticity beats intelligence.** The AI should feel like real people Katy has played 42 with — not discover clever-but-unrealistic optimizations. The north star: *"That partner plays just like my uncle."*
- **The first question on any judgment-heavy behavior is "does this belong in the existing system at all?"** — not "how do we tune it?" Sevens and Nello both turned out to need entirely separate code paths rather than tuned parameters, because they're structurally different games hiding inside the same trick-taking shell.
- **Partner cooperation intent is difficulty-invariant.** Difficulty changes judgment quality and awareness, never whether the partner is trying to help you. Opponents and partners will eventually get separate difficulty parameters, since they optimize for opposite goals.

## 2. Function containment & anti-hardcoding — a standing principle

This comes up constantly enough in review that it deserves its own section, separate from feature philosophy:

- **Each subsystem owns its own concern and nothing bleeds across the boundary.** `Trick` is purely mechanical (turn order, legality, resolving a winner) — it must never accumulate inference logic. `PublicKnowledge` is the *only* place inference about voids/played tiles/etc. lives — if any other file (including `AIPlayer` or `game_table.gd`) inspects `trick.plays` to reason about suit-following, that's the boundary being crossed, even for a one-line convenience check. Two implementations of the same inference is treated as a real bug class, not a style nit — it already happened once (the ranking split-brain, see §5) and cost a full audit-and-fix session.
- **Difficulty is not a library of special cases.** Before writing `if difficulty == "expert"`, the file's own doctrine requires classifying the difference as **Knowledge** (an information asymmetry — belongs behind `PublicKnowledge`), **Evaluation** (same information, different weighting — belongs in shared decision logic parameterized by `AI_MODES`), or genuinely **Neither** (a last-resort bare branch). `AI_MODES` is a single dict of named parameters (`risk_bias`, `max_overbid`, `opportunism`, `cooperation_bias`) — that's the intended place personality differences live, not scattered conditionals.
- **Avoid hardcoding wherever a computed/derived value will do**, especially anything affecting layout or game math: mobile tile sizes are computed proportionally from viewport width rather than fixed pixel constants (an established convention, not yet applied everywhere — font sizes are still hardcoded and flagged as future cleanup).
- **State lives in exactly one place.** `PublicKnowledge` is rebuilt fresh from a `PublicFrame` at every decision point rather than cached/mutated incrementally — deliberately, to avoid drift bugs between a stored dictionary and the history it's supposed to represent. `HandRecordWriter` holds only bookkeeping about *its own* job (has it persisted yet, under what filename) and is explicitly barred from holding a copy of hand data — there's a written guardrail: *"Any future extension must not introduce persistent cross-hand state outside `game.gd` or `HandRecordWriter`."*
- **When a spec's complexity starts cascading, that's a signal to shrink scope**, not push through — this has happened a couple of times and the response was always to simplify, not add machinery to compensate.

## 3. File inventory

### Core game logic
| File | Role |
|---|---|
| `game.gd` | The `Game` class — central game state. Owns players, shaker/turn tracking, bid state, `hand_history`, `deal_snapshot`, `bid_decisions`, `hand_result`, `flags`, and score tracking. Deals hands, drives bidding order, resolves tricks/hands, and assembles `build_hand_record()` for replay/export. |
| `ai_player.gd` | Static utility class — all AI bidding and play decisions. See deep dive below. |
| `game_table.gd` | The UI/orchestration layer — builds the entire UI programmatically, drives game flow (bidding sequence, trick execution, replay screen), and is the thing that calls into `AIPlayer`. See deep dive below. |
| `trick.gd` | `Trick` class — purely mechanical: tracks plays in the current trick, computes legal moves, determines the trick winner. Deliberately kept free of any inference/knowledge logic. |
| `trick_pile.gd` | Visual trick-pile widget (the stack of won tricks shown per team). |
| `bid.gd` | `Bid` class — bid types (Points, Marks, Nello, Sevens, Plunge, Splash, the still-partially-dead Follow Me) and validation (`is_valid()`). |
| `player.gd` | Lightweight `Player` data holder — id, hand, human/AI flag. |
| `deck.gd` | Builds and shuffles the 28-tile double-six set, deals hands. |
| `domino.gd` | `Domino` class — pip values, suit/rank logic (`is_trump`, `is_double`, `get_suit`, `get_rank`), mode-aware (trump, nello doubles-high/low, doubles-trump-reversed). |
| `domino_tile.gd` | Visual node for a single domino tile (rendering, selection state, `back_style` stub for future custom domino backs). |
| `game_settings.gd` | `GameSettings` — all configurable rules (bid direction, nello doubles mode, doubles-trump-reversed, sevens tie rule, etc.) and presets. Some settings are currently orphaned (saved/loaded but not consulted by game logic — flagged cleanup item). |

### AI inference layer (new, currently inert)
| File | Role |
|---|---|
| `public_frame.gd` | `PublicFrame` ("KnowledgeBox") — an immutable, plain data holder: completed `hand_history` plus the in-progress `current_trick`. Performs zero inference; it is *only* the raw material `PublicKnowledge` is built from. |
| `public_knowledge.gd` | `PublicKnowledge` — the sole inference layer for anything derivable from public play (void suits, played tiles, remaining counts). A vocabulary layer, not a decision layer: every query has one objective answer, never evaluates or recommends, and never varies by difficulty. Built fresh via `from_state()` at each decision point. |

### Replay / hand record
| File | Role |
|---|---|
| `hand_record_writer.gd` | `HandRecordWriter` — static, stateless-except-bookkeeping. Serializes `build_hand_record()` output (recursively converting `Domino`/`Bid` objects to JSON-safe primitives) and persists it — overwrite-on-every-flag on desktop, single-download-on-first-flag on web. |
| `marks_display.gd` | Visual marks-won display widget. |
| `drum_picker.gd` | Reusable scrolling number picker (used for points/marks bid entry). |

### Scaffolding / misc
| File | Role |
|---|---|
| `node_2d.gd` | Pre-AI test harness; rotates turns in the *opposite* direction from the game's real `(n+3)%4` convention. Harmless leftover, not live code. |
| `test.gd` | Minimal test stub. |
| `control.tscn`, `domino.tscn` | Godot scene files backing the above. |

### Tracking documents
| File | Role |
|---|---|
| `AI_Explanation_Bug_Log.md` | Logged issues with AI reasoning-string quality (tone, correctness relative to actual outcome), fixes applied and pending. |
| `AI_Play_Behavior_Bug_Log.md` | Logged issues with `decide_play()` decisions themselves (not the explanation text). |
| `AI_Bid_Behavior_Bug_Log.md` | Logged issues with `decide_bid()` decisions. |
| Session summary docs (multiple, dated) | Point-in-time handoff docs — what was reviewed/decided/implemented in each session. Treat the most recent as authoritative for current state. |

## 4. Deep dive: `ai_player.gd`

Static utility class, **no instances** — `AIPlayer` is called functionally from `game_table.gd`. It has two entry points:

**`decide_bid()`** — three-layer architecture, explicitly confirmed satisfactory and not slated for restructuring:
- **Layer 1 — Evaluation** (`evaluate_hand`, `best_trump`): objective hand truth. Estimates points/tricks the hand can capture, using an "Expected Capture Model" — `est_pts` is what the hand can realistically win, not a naive point-count. Trump strength is rank-scaled (`0.35 + (rank/6.0) * 0.50`) rather than a flat rate, so a rank-6 trump domino and a rank-1 trump domino no longer score identically. Do not modify without cause.
- **Layer 2 — Decision policy**: combines an EV signal, a control signal (trump count/double-trump structural confidence), and an auction-stance bias (`pressure_opener` / `solid_opener` / `competitive` / `defensive`) into one `final_score`, compared against a fixed threshold (28.0). `risk_bias` and `max_overbid` (from `AI_MODES`) inject personality here.
- **Layer 3 — Execution**: enforces auction legality only (respects current high bid, legal increments, `max_overbid` cap, minimum-bid floor). Never re-scores the hand.

Every AI bid decision is logged into `bid_decisions` (player id, difficulty, hand snapshot, eval snapshot, should_bid, target_bid) for later replay/export.

**`decide_play()`** — takes legal moves, hand, the current `Trick`, trump, contract type, and (as of the newest infrastructure) an optional `PublicKnowledge` snapshot. Structure:
- **Sevens and Nello exit immediately at the top**, bypassing all standard evaluation — they are treated as different games sharing the trick-taking shell, not variations of standard play. Sevens: always play closest-to-7. Nello: always play lowest legal (bidder trying to lose, opponents trying to force the bidder to win).
- **Marks/Plunge/Splash** share a "win every trick" objective (matching how `resolve_hand()` in `game.gd` scores them) and get their own early-return branch, distinct from normal counter/pip-protection logic.
- **Standard trick play** below that handles: leading (with trump-control and, as of the newest spec, known-void-targeting logic for Expert), following suit, and discard/counter-protection when unable to win, with different logic paths for partner vs. opponent.

**Currently the single most important open architectural thread:** the file has a documented "Knowledge vs. Evaluation vs. Neither" litmus test at its header, but six bare `difficulty ==` branches still exist that the doctrine says should eventually collapse into `AI_MODES` parameters. This is understood as **transitional** (Phase 3 not yet landed), not drift — but it's the first thing to look at when reasoning about why a particular branch is structured the way it is.

**Reasoning strings (`reason_log.append(...)`)** are produced at every decision point, always first-person, and always describe what the AI *believed*, never what the human *should have done*. A Phase 1 spec exists to rewrite all ~24 of these from debug-flavored strings (e.g. embedding `debug_string()` tile dumps) into clean table language — written but not yet applied.

## 5. Deep dive: `game_table.gd`

This is the largest file and the **only** place that talks to both `Game`/`AIPlayer` and the actual UI. It:

- Builds the entire UI tree programmatically in `_build_ui()` (no scene-file UI for the main table) — including proportional tile sizing computed from viewport width at build time.
- Drives the full game loop: bidding sequence (`_run_bidding_sequence()`, `_run_post_human_bids()`), trick execution (`_execute_play()`, `_ai_choose_domino()`), and hand resolution.
- Owns the **replay screen** — a fully separate UI mode that steps back through `hand_history` trick by trick, re-rendering each player's hand/plays/reasoning bubble as they were at that point, plus a "flag" panel (bidding/gameplay/explanation toggles + free-text note) that calls `game.flag_hand()`.
- Is the call site that will construct `PublicFrame.new(game.hand_history, game.current_trick)` and derive `PublicKnowledge.from_state(frame)` before calling `AIPlayer.decide_play()` — this wiring is specced but **not yet pasted into the codebase** (see §6).

Notable conventions baked into this file:
- Player-relative labels (`"Partner"`, `"Right Opponent"`, `"Left Opponent"`) are computed from `human_seat`, never hardcoded per seat index.
- `(n+1)%4` = right/clockwise, `(n+3)%4` = left/counter-clockwise — the correct seating direction convention for play order and shaker rotation. (`node_2d.gd`, the old test harness, uses the opposite direction and is known-harmless dead scaffolding.)
- A `DEBUG_FAST_MODE` flag exists to skip AI "thinking" pauses for faster testing — flagged to eventually become a real settings toggle.

## 6. Current focus systems

### Bidding
Architecture (Layers 1–3, above) is considered settled and satisfactory. Open gaps:
- AI cannot currently initiate special contracts (Nello, Sevens, Plunge, Splash) — `decide_bid()` only ever emits Points or Marks, even though `game.eligible_contracts()` and all the downstream routing already exist. Needs design discussion (how eagerly should personality bid Nello, etc.) before speccing.
- AI Phase 2 "Risk" axis is implemented on the bidding side only; the play side hasn't started.
- `cooperation_bias` is flagged for a rename to `trust_threshold` — not yet done, and there's an open question about what that parameter *should* mean once wired in (does an Expert partner's more aggressive play represent better judgment or reduced trust?).

### Gameplay decisions (`decide_play()`)
The big active thread is the **`PublicFrame` / `PublicKnowledge` inference layer** — fully designed, implemented, and verified, but currently **inert** (nothing calls it yet). Key guarantees:
- Mid-trick voids are visible the moment they happen, not just at trick boundary — this required unifying "completed history" and "in-progress trick" into one input concept (`PublicFrame`) rather than only consulting `hand_history`.
- `PublicKnowledge` is rebuilt fresh every time, never cached/mutated, so it can't drift from the state it represents.
- A recent full-codebase review caught and fixed a real bug (**ranking split-brain**): several `AIPlayer` helpers (`_beats`, `_highest_in`, `_lowest_in`, etc.) hardcoded `"high"` doubles-ranking and ignored `doubles_trump_reversed`, while `Trick` and `PublicKnowledge` had already been mode-aware. Fixed by threading the same two parameters through all affected helpers.
- The next concrete step (specced, not yet pasted in) is wiring `PublicKnowledge` into `decide_play()` as its first real consumer: Expert-only, lead the highest domino in a suit a known-void opponent can't follow. The choice of *highest* (vs. lowest) into a known void is explicitly flagged as the most likely thing to need revision after real playtesting.
- Void/suit tracking is the named Phase 4 capability this unlocks; deferred beyond it are ranking-dependent queries like "highest remaining trump," held back specifically until the ranking fix is playtest-confirmed.
- Also open: the MARKS "cardinal rule" branch (whether AI should steal a human partner's already-winning trick under a Marks contract) is deferred pending more concrete example hands from Katy.

### Replay explanations
Two-part system: reasoning strings generated live during play (`reason_log`), and the replay screen that plays them back trick-by-trick alongside a flagging/annotation tool.
- A running bug log (`AI_Explanation_Bug_Log.md`) tracks cases where the string didn't match the actual outcome or read with the wrong tone (e.g. a partner's cooperative counter-dump originally read as a reluctant concession — "but I had to let a counter go" vs. the corrected "Putting my points on your trick"). Several of these are fixed; the pattern of opponent-flavored vs. partner-flavored strings needing separate branches for the same decision code is expected to recur.
- The Phase 1 rewrite (all 24 strings, debug language → table language) is fully specced but not yet pasted into Claude Code.
- The **HandRecord/flagging system** (Phase B data layer + Phase C UI) is fully implemented and confirmed: every flag event rebuilds a fresh, complete record (`build_hand_record()` — trump, variant, winning bid, deal snapshot, bid decisions, hand history, hand result, flags) rather than holding a live mutable object, and `HandRecordWriter` persists it (platform-appropriate: live-updating file on desktop, single download on web). This is explicitly the foundation for future consumers like hand export/sharing or AI regression capture — none of those are built yet.

## 7. Suggested first questions for a new consultant to ask

- Read the most recent session summary doc in full before proposing anything — state drifts fast and each doc is written as an authoritative handoff.
- Before touching any judgment-heavy AI behavior: is this a Knowledge difference, an Evaluation difference, or genuinely Neither? Get comfortable with that litmus test — it's the actual review standard here.
- Anything touching ranking/comparison logic should go through the same canonical functions `Trick`/`AIPlayer` already use, never a locally re-derived comparison — this file's history contains one real bug from that exact mistake.
- Anything touching mobile layout should default to proportional/viewport-relative sizing, not fixed pixel constants.
