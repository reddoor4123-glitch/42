# Texas 42 — Project Onboarding

*Written as if introducing a new consultant to the codebase for the first time.*

*Last verified against code: July 5, 2026. This document is meant to be kept current — if you
land here after a session that changed AI behavior, wiring, or philosophy, update the relevant
section rather than leaving it to drift. For full navigation across every session summary, bug
log, and audit doc (there are now quite a few), start with `Texas_42_Documentation_Map.md` — this
doc stays focused on orientation and current architecture, that one is the index.*

## 1. What this project is

A Texas 42 domino game built in **Godot 4 (GDScript)**, mobile-first portrait layout with desktop as secondary, with an eye toward eventual publishing. Katy is the project owner and lead designer.

**Design philosophy — read this before touching AI code:**

- **Table behavior is design intent, not flavor text.** When Katy describes how a real player behaves at a 42 table, that description is the precise spec — not a mood board.
- **Authenticity beats intelligence.** The AI should feel like real people Katy has played 42 with — not discover clever-but-unrealistic optimizations. The north star: *"That partner plays just like my uncle."*
- **The first question on any judgment-heavy behavior is "does this belong in the existing system at all?"** — not "how do we tune it?" Sevens and Nello both turned out to need entirely separate code paths rather than tuned parameters, because they're structurally different games hiding inside the same trick-taking shell.
- **Partner cooperation intent is difficulty-invariant.** Difficulty changes judgment quality and awareness, never whether the partner is trying to help you. Opponents and partners will eventually get separate difficulty parameters, since they optimize for opposite goals.

## 2. Function containment & anti-hardcoding — a standing principle

This comes up constantly enough in review that it deserves its own section, separate from feature philosophy:

- **Each subsystem owns its own concern and nothing bleeds across the boundary.** `Trick` is purely mechanical (turn order, legality, resolving a winner) — it must never accumulate inference logic. `PublicKnowledge` is the *only* place inference about voids/played tiles/etc. lives — if any other file (including `AIPlayer` or `game_table.gd`) inspects `trick.plays` to reason about suit-following, that's the boundary being crossed, even for a one-line convenience check. Two implementations of the same inference is treated as a real bug class, not a style nit — it already happened once (the ranking split-brain, see §6) and cost a full audit-and-fix session.
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
| `domino.gd` | `Domino` class — pip values, suit/rank logic (`is_trump`, `is_double`, `get_suit`, `get_rank`), mode-aware across trump, Nello doubles-high/low/**own-suit** (including own-suit-reversed), and doubles-trump-reversed. |
| `domino_tile.gd` | Visual node for a single domino tile (rendering, selection/playable/armed state, `back_style` stub for future custom domino backs). |
| `game_settings.gd` | `GameSettings` — all configurable rules (bid direction, nello doubles mode, `nello_doubles_reversed`, doubles-trump-reversed, sevens tie rule, etc.) and presets. `nello_doubles_reversed` is now fully wired (settings checkbox → per-hand nello panel button → `game.active_nello_doubles_reversed` → ranking). A few other settings remain orphaned (saved/loaded but not consulted): `follow_me_doubles_mode`, `follow_me_allow_as_points_bid`, `allow_small_end_opening_lead`, `sevens_tie_rule` (stub, "earliest" only) — flagged cleanup items, see `Texas_42_Next_Session_Prep_July_5_2026.md` backlog. |

### AI inference layer
| File | Role |
|---|---|
| `public_frame.gd` | `PublicFrame` ("KnowledgeBox") — an immutable, plain data holder: completed `hand_history` plus the in-progress `current_trick`. Performs zero inference; it is *only* the raw material `PublicKnowledge` is built from. |
| `public_knowledge.gd` | `PublicKnowledge` — the sole inference layer for anything derivable from public play. A vocabulary layer, not a decision layer: every query has one objective answer, never evaluates or recommends, and never varies by difficulty (see the file's own header contract). Built fresh via `from_state()` at each decision point, never cached. Nine queries (corrected count — previously miscounted as six): `void_suits()`/`is_void_in()` and `has_been_played()` are consumers (Expert void-lead targeting, BUG-005's live-counter check); `count_remaining_trump()` and `best_remaining_card_for_suit()` (both new consumers July 6) drive branch #11's generalized guaranteed-win check. `remaining_count()`, `current_trick_plays()`, `trick_leader_so_far()`, and the newest `highest_remaining_trump()` are implemented and correct but still have no consumer. |

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
The doc set has grown enough that it gets its own index rather than a table here — see
`Texas_42_Documentation_Map.md` for the full list (bug logs, Phase 1/2/3 audits, dated session
summaries, standalone bug-fix specs) with guidance on which doc answers which kind of question.
Three worth knowing by name up front, since they're referenced throughout this document:
- `AI_Play_Behavior_Bug_Log.md` — logged issues with `decide_play()` decisions themselves.
- `AI_Bid_Behavior_Bug_Log.md` — logged issues with `decide_bid()` decisions.
- `AI_Explanation_Bug_Log.md` — logged issues with reasoning-string quality/tone, separate from
  whether the underlying decision was correct.
Check the relevant log's status key before assuming a play/bid oddity is new — it may already be
a categorized, specced, or even fixed bug (BUG-003/003b, BUG-005, and the Marks bid gate double
defect were all closed out this session; see §4 and §6 below).

## 4. Deep dive: `ai_player.gd`

Static utility class, **no instances** — `AIPlayer` is called functionally from `game_table.gd`. Four header blocks above `decide_bid()`/`decide_play()` now encode the project's design doctrine directly in the file, in this order — read them before proposing a change to either function:
1. **AI Design Philosophy** — the "Uncle Ed" north star and the four-phase model (Cooperation/Risk/Opportunism/Awareness).
2. **Decision Geometry** — names a third category of decision-relevant fact, distinct from Knowledge and Evaluation: directly observable structural properties of the current moment (e.g. "am I last to act," via `_is_last_to_act()`) that are the same for every seat regardless of difficulty. Includes an explicit warning against prematurely unifying these with knowledge-dependent "is this trick decided" checks — they're different subsystems that sometimes produce the same outcome.
3. **Difficulty Differences** — the Knowledge/Evaluation/Neither litmus test for any proposed `if difficulty == "..."` branch (see §2 above; this is where it actually lives in code).
4. **Trick Objectives** — names the missions `decide_play()`'s branch structure already implements (`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`, `CONTEST_IF_WORTHWHILE`, `ESCAPE`, `CONTROL_TRUMP`, `FORCE_A_VOID`, `FEEL_OUT_THE_HAND`), and classifies each as Evaluation-tuning within a shared objective vs. a genuine difficulty-level branch — the working map for the still-pending Phase 3 branch collapse. `Phase3_Objective_Audit.md` is the full branch-by-branch table this header summarizes; treat that doc, not this section, as the source of truth for any specific branch number.

**`decide_bid()`** — three-layer architecture, explicitly confirmed satisfactory and not slated for restructuring:
- **Layer 1 — Evaluation** (`evaluate_hand`, `best_trump`): objective hand truth. Estimates points/tricks the hand can capture, using an "Expected Capture Model" — `est_pts` is what the hand can realistically win, not a naive point-count. Trump strength is rank-scaled (`0.35 + (rank/6.0) * 0.50`) rather than a flat rate, so a rank-6 trump domino and a rank-1 trump domino no longer score identically. Do not modify without cause.
- **Layer 2 — Decision policy**: combines an EV signal, a control signal (trump count/double-trump structural confidence), and an auction-stance bias (`pressure_opener` / `solid_opener` / `competitive` / `defensive`) into one `final_score`, compared against a fixed threshold (28.0). `risk_bias` and `max_overbid` (from `AI_MODES`) inject personality here.
- **Layer 3 — Execution**: enforces auction legality only (respects current high bid, legal increments, `max_overbid` cap, minimum-bid floor). Never re-scores the hand.
- **Marks-bid gate** (evaluated right after Layer 3, before the points-bid return): fixed this session (`AI_Bid_Behavior_Bug_Log.md` Pattern A, two stacked defects). Marks is now checked *before* the points-branch return rather than after — it was previously unreachable on any hand strong enough to trigger `should_bid` — and requires off-suit viability (an off-suit double, or `trump_count >= 6` as a bypass) on top of the existing trump-control requirement, so it no longer fires on hands with strong trump but exposed off-suit risk.

Every AI bid decision is logged into `bid_decisions` (player id, difficulty, hand snapshot, eval snapshot, should_bid, target_bid) for later replay/export.

**`decide_play()`** — takes legal moves, hand, the current `Trick`, trump, contract type, an optional `PublicKnowledge` snapshot, and (added for the BUG-005 fix) `team_points`/`bid_value` for margin evaluation. Structure:
- **Sevens and Nello exit immediately at the top**, bypassing all standard evaluation — they are treated as different games sharing the trick-taking shell, not variations of standard play. Sevens: always play closest-to-7, and `Trick.get_legal_moves()` itself now enforces this (only the closest-to-7 domino(es) are legal, not the whole hand — previously the whole hand was offered as legal under Sevens). Nello: always play lowest legal (bidder trying to lose, opponents trying to force the bidder to win); Nello also now supports an "Own Suit (Reversed)" doubles mode (double-blank ranks highest within own-suit instead of double-six), threaded through `Domino.get_rank()`, `Trick`, and all six `AIPlayer` ranking helpers via a `own_suit_reversed` parameter alongside the existing `doubles_trump_reversed`.
- **Marks/Plunge/Splash** share a "win every trick" objective (matching how `resolve_hand()` in `game.gd` scores them) and get their own early-return branch, distinct from normal counter/pip-protection logic.
- **Standard trick play** below that handles: leading (with trump-control — reordered ahead of the safe off-suit check this session, see BUG-003/003b below — and Expert known-void-targeting logic), following suit, and discard/counter-protection when unable to win, with different logic paths for partner vs. opponent.
- **BUG-003/003b, fixed:** partner-leading trump control previously ran *after* the safe-off-suit check, making it unreachable on most hands (any hand with a safe off-suit tile never reached the trump-control branch at all). Now trump control is checked first, gated by a double-aware threshold: 3+ trumps if the holding includes the double trump, 4+ otherwise.
- **BUG-005, fixed:** the standard-difficulty partner "trump-only can-win" branch (previously `trust_gate`, gated on turn order — "has the human already played, am I last to act") is rebuilt on three real factors instead: a deterministic worst-case counter bound (`_live_counter_for_suit()` — never a probability, only rules out a specific counting domino once it's provably unreachable), a symmetric contract-margin reachability check (can our side still hit its target even conceding this trick at worst case), and lead economy (would winning strand us without a safe next lead). The name `trust_gate` is now a misnomer kept only for cross-reference continuity — there is no trust content left in this branch. Expert's own "no trust rule" line is untouched and is a separate open question.

**Architectural status, updated:** the six historically-bare `difficulty ==` branches in `decide_play()` are now fully classified (not just flagged) by the Trick Objectives header and `Phase3_Objective_Audit.md` — five are Evaluation-tuning within a shared, difficulty-invariant objective and belong as `AI_MODES` parameters once Phase 3 actually collapses them; only `FEEL_OUT_THE_HAND` is a genuine difficulty-level mission difference. The collapse itself hasn't happened yet — this is the map for it, not the fix. Separately: **`trust_threshold`** (the candidate `AI_MODES` parameter that branch #16/`trust_gate` was originally going to source) **no longer has a confirmed source branch** post-BUG-005 — the branch it was named for has no trust content anymore. Don't resume `trust_threshold` design work by default; that's now an open question, not a pending-design item (see `Phase3_Objective_Audit.md`'s post-BUG-005 correction).

**Reasoning strings (`reason_log.append(...)`)** are produced at every decision point, always first-person, and always describe what the AI *believed*, never what the human *should have done*. A Phase 1 spec exists to rewrite all ~24 of these from debug-flavored strings (e.g. embedding `debug_string()` tile dumps) into clean table language — written but not yet applied.

## 5. Deep dive: `game_table.gd`

This is the largest file and the **only** place that talks to both `Game`/`AIPlayer` and the actual UI. It:

- Builds the entire UI tree programmatically in `_build_ui()` (no scene-file UI for the main table) — including proportional tile sizing computed from viewport width at build time.
- Drives the full game loop: bidding sequence (`_run_bidding_sequence()`, `_run_post_human_bids()`), trick execution (`_execute_play()`, `_ai_choose_domino()`), and hand resolution.
- Owns the **replay screen** — a fully separate UI mode that steps back through `hand_history` trick by trick, re-rendering each player's hand/plays/reasoning bubble as they were at that point, plus a "flag" panel (bidding/gameplay/explanation toggles + free-text note) that calls `game.flag_hand()`. The flag panel resets on trick-advance and replay-exit so a half-filled panel never gets attributed to the wrong trick.
- Is the call site that constructs `PublicFrame.new(game.hand_history, game.current_trick)` and derives `PublicKnowledge.from_state(frame)` before calling `AIPlayer.decide_play()` — **this is live and playtest-confirmed**, not just specced.
- Implements **"arm a play"**: the human can tap a legal domino before the trick actually reaches them (once the trick is led, before they've played, and not during the Nello sit-out seat) to pre-select it — shown via `DominoTile.is_selected` — and it's played automatically the instant their turn arrives, with legality re-checked at both arm-time and consumption-time and a safe fallback to the normal tap-to-play prompt if it somehow became illegal in between.

Notable conventions baked into this file:
- Player-relative labels (`"Partner"`, `"Right Opponent"`, `"Left Opponent"`) are computed from `human_seat`, never hardcoded per seat index.
- `(n+1)%4` = right/clockwise, `(n+3)%4` = left/counter-clockwise — the correct seating direction convention for play order and shaker rotation. (`node_2d.gd`, the old test harness, uses the opposite direction and is known-harmless dead scaffolding.)
- A `DEBUG_FAST_MODE` flag exists to skip AI "thinking" pauses for faster testing — flagged to eventually become a real settings toggle.
- Console `print()` output for trick resolution and per-play reasoning is prefixed with the trick number (`[Trick N]`), and trick resolution additionally logs the active `nello_doubles`/`own_suit_reversed` or `doubles_trump_reversed` mode when relevant — makes console traces during manual testing much easier to follow trick-by-trick.
- The Nello doubles-mode panel has a fourth button, "Own Suit (Reversed)," gated behind a settings checkbox (`Allow Own Suit (Reversed)`) — pressing it sets both `game.active_nello_doubles_mode = "own_suit"` and `game.active_nello_doubles_reversed = true` in one step; that combined UI-layer string (`"own_suit_reversed"`) exists only in `_on_nello_mode_selected()` and is never seen by `Domino`/`Trick`/`AIPlayer`.

## 6. Current focus systems

### Bidding
Architecture (Layers 1–3, above) is considered settled and satisfactory. The Marks-bid gate double
defect (Pattern A) is fixed as of this session — see §4. Remaining open gaps:
- AI cannot currently initiate special contracts (Nello, Sevens, Plunge, Splash) — `decide_bid()` only ever emits Points or Marks, even though `game.eligible_contracts()` and all the downstream routing already exist. Needs design discussion (how eagerly should personality bid Nello, etc.) before speccing.
- AI Phase 2 "Risk" axis is implemented on the bidding side only; the play side hasn't started.
- `cooperation_bias` → `trust_threshold` rename: **the standing question this was blocked on is now moot in a different way.** The rename was blocked on "does Expert's no-trust-rule mean better judgment or reduced trust" — but post-BUG-005, the branch (`trust_gate`) that `trust_threshold` was going to source no longer has any trust content at all (see §4). `trust_threshold` currently has no confirmed source branch. Don't resume this rename by default; whether it should still exist as an `AI_MODES` parameter, and for what, is now the open question.

### Gameplay decisions (`decide_play()`)
The **`PublicFrame` / `PublicKnowledge` inference layer** is live and playtest-confirmed, not inert
— two real consumers exist today. Key guarantees and status:
- Mid-trick voids are visible the moment they happen, not just at trick boundary — this required unifying "completed history" and "in-progress trick" into one input concept (`PublicFrame`) rather than only consulting `hand_history`.
- `PublicKnowledge` is rebuilt fresh every time, never cached/mutated, so it can't drift from the state it represents. Nine queries exist total (see §3); five are consumed today.
- **Consumer 1 (Expert leading):** target a suit a known-void opponent can't follow, leading the highest domino in that suit — implemented, confirmed working in real play. The choice of *highest* (vs. lowest) is still flagged as the most likely thing to revisit after further playtesting.
- **Consumer 2 (BUG-005, partner following, standard difficulty):** the deterministic worst-case-counter check inside the rebuilt `trust_gate` commitment gate (see §4) — `is_void_in()`/`has_been_played()` determine whether a specific counting domino is still a live threat this trick.
- **Consumer 3 (branch #11, partner cardinal rule, all difficulties, added July 6, 2026):** guaranteed-win detection generalized beyond "winning tile is a double" — `best_remaining_card_for_suit()` plus a `count_remaining_trump()`-minus-own-hand check now also recognize a non-double, non-trump winner as safe once no opponent can still hold trump. Difficulty-invariant by explicit design decision (flagged for confirmation, not silently assumed) — treated as core cardinal-rule recognition, not a technique gap. See `Phase3_Objective_Audit.md` branch #11 and `AI_Play_Behavior_Bug_Log.md`'s design-notes entry for follow-on generalization ideas.
- The **ranking split-brain bug** (several `AIPlayer` helpers hardcoded `"high"` doubles-ranking and ignored `doubles_trump_reversed`, while `Trick`/`PublicKnowledge` were already mode-aware) is fixed and playtest-confirmed — all six ranking helpers now thread `nello_doubles`, `doubles_trump_reversed`, and `own_suit_reversed` uniformly.
- **BUG-003/003b, fixed this session:** partner-leading trump control was unreachable behind the safe off-suit check on most hands; now correctly reordered with a double-aware threshold. See §4.
- **New this session:** Nello "Own Suit (Reversed)" doubles mode (own-suit doubles rank double-blank highest instead of double-six), and Sevens now has real legal-move enforcement (`Trick.get_legal_moves()` restricts to the closest-to-7 domino(es), not the whole hand) — both feed the arm-a-play/highlight UI in `game_table.gd` for free, since that UI just trusts whatever `get_legal_moves()` returns.
- Ranking-dependent queries beyond void tracking — `remaining_count()`, `current_trick_plays()`, `trick_leader_so_far()`, and `highest_remaining_trump()` — are implemented and available now that the ranking fix is playtest-confirmed, but still have no consumer. `count_remaining_trump()` gained its first consumer July 6 (Consumer 3, above).
- Also open: the MARKS "cardinal rule" branch (whether AI should steal a human partner's already-winning trick under a Marks contract) is deferred pending more concrete example hands from Katy. A related but distinct concept — declining a guaranteed trick win to hand lead control to a better-positioned teammate for a *future* trick — was independently rediscovered twice (once during BUG-005, once during Phase 1 resolution) and is now permanently parked in `Phase1_Control_Layer_Audit.md`, deliberately not being built.

### Replay explanations
Two-part system: reasoning strings generated live during play (`reason_log`), and the replay screen that plays them back trick-by-trick alongside a flagging/annotation tool.
- A running bug log (`AI_Explanation_Bug_Log.md`) tracks cases where the string didn't match the actual outcome or read with the wrong tone (e.g. a partner's cooperative counter-dump originally read as a reluctant concession — "but I had to let a counter go" vs. the corrected "Putting my points on your trick"). Several of these are fixed; the pattern of opponent-flavored vs. partner-flavored strings needing separate branches for the same decision code is expected to recur.
- The Phase 1 rewrite (all 24 strings, debug language → table language) is fully specced but not yet pasted into Claude Code.
- The **HandRecord/flagging system** (Phase B data layer + Phase C UI) is fully implemented and confirmed: every flag event rebuilds a fresh, complete record (`build_hand_record()` — trump, variant, winning bid, deal snapshot, bid decisions, hand history, hand result, flags) rather than holding a live mutable object, and `HandRecordWriter` persists it (platform-appropriate: live-updating file on desktop, single download on web). This is explicitly the foundation for future consumers like hand export/sharing or AI regression capture — none of those are built yet.

## 7. Suggested first questions for a new consultant to ask

- Read the most recent session summary doc in full before proposing anything — state drifts fast and each doc is written as an authoritative handoff. Check `Texas_42_Documentation_Map.md` if unsure which doc that is.
- Before touching any judgment-heavy AI behavior: is this a Knowledge difference, an Evaluation difference, or genuinely Neither? Get comfortable with that litmus test — it's the actual review standard here. Also check whether it's actually **Decision Geometry** (a directly observable structural fact, same for every seat — see §4) rather than Knowledge or Evaluation at all; conflating the two was explicitly called out as a mistake to avoid once the concept was named.
- Anything touching ranking/comparison logic should go through the same canonical functions `Trick`/`AIPlayer` already use, never a locally re-derived comparison — this file's history contains one real bug from that exact mistake (the ranking split-brain, since fixed).
- Anything touching mobile layout should default to proportional/viewport-relative sizing, not fixed pixel constants.
- Before assuming a play/bid oddity is a new bug: check the relevant bug log's status key first (`AI_Play_Behavior_Bug_Log.md`, `AI_Bid_Behavior_Bug_Log.md`, `AI_Explanation_Bug_Log.md`) — it may already be categorized, specced, or fixed.
