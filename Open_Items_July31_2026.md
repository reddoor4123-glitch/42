# Open Items — July 31, 2026

Everything left loose after the July 30–31 sessions (audit fixes, replay layout,
settings architecture review). Written so none of it lives only in a chat log.

**Status key:** `OPEN` needs work · `BLOCKED` waiting on a decision ·
`PARKED` deliberately deferred · `DECIDED` resolved, recorded for the reasoning ·
`DROPPED` considered and rejected

---

## 1. Product / UX — only Katy can answer these

These are not engineering questions. Nothing below can be derived from the code.

| # | Question | Status |
|---|---|---|
| 1.1 | **What is the Settings screen FOR?** Proposed requirement: *"to help players recognise 42 is customisable without making them feel obligated to customise it."* If that is right, the screen is an onboarding surface, not a config form, and most of §2 follows from it. | BLOCKED |
| 1.2 | Should **rulesets be the hero** of the screen, with rule toggles demoted to "want to customise?" — teaching that different tables play differently before showing 33 checkboxes? | BLOCKED |
| 1.3 | Should the **Play button change label by context**? "Play" on first launch (nothing to restart), "Restart with Changes" mid-game. Same action, different words, because the situation differs. | BLOCKED |
| 1.4 | Does **Cancel** still make sense on a first-launch screen? Cancel to where? It reads fine mid-game and oddly on a welcome screen. | BLOCKED |
| 1.5 | Should **domino back be reversible with Cancel**, or is it obviously a personal preference that commits on click? Currently immediate. | BLOCKED |
| 1.6 | Where should **AI difficulty** sit in the UI? It behaves like a preference, but players may expect it near game setup. Placement is a design call, not an architecture one. | BLOCKED |
| 1.7 | If you change difficulty mid-game, do you **expect the current opponents** to change immediately? Currently they do. | BLOCKED |

**The reframe worth keeping:** the screen is currently answering four different
questions at once — *who are you* (difficulty, backs), *how do you play 42*
(rules), *what game should start* (ruleset), *what do you want to do now*
(Play/Cancel/Menu) — without telling the player that. That is an onboarding
problem, not a code-structure problem.

---

## 2. Settings architecture — conclusions reached

| # | Item | Status |
|---|---|---|
| 2.1 | **Transactional vs. immediate split is correct.** Rules are transactional; display preferences and difficulty are immediate. | DECIDED |
| 2.2 | **The boundary is `GameSettings.to_dict()` membership**, not "does it invalidate game history". 35 declared fields, 33 serialized; the 2 excluded are `preset_id` (identity) and `ai_difficulty`. Classifies 100% of fields today with no per-field judgement, and is mechanically testable. | DECIDED |
| 2.3 | "Invalidates game history" is the **rationale** for where the boundary sits, not the test. It under-classifies six fields (see 3.1). | DECIDED |
| 2.4 | **Carrying is not owning.** Player Prefs owns `ai_difficulty`; `GameSettings.ai_difficulty` stays as the delivery slot AIPlayer reads. Do not move the field off `GameSettings` — it changes AIPlayer's read path for no gain today. | DECIDED |
| 2.5 | **Rendering principle:** a control should update itself, or whatever it directly affects, rather than destroying and recreating the screen it lives on. First applied in the domino-back fix. | DECIDED |
| 2.6 | **`is_dirty()`** — a baseline copy plus a comparison over rule fields only. The single genuinely new capability. Enables: precise Play confirmation, honest Cancel, warning on slot-switch with unsaved edits. | OPEN |
| 2.7 | **Ruleset Library extraction** — justified as "testability", which was wrong: `menu_merge_verify.gd` already tests slot resolution with 87 assertions. What it actually buys is a smaller file, and file size is not the problem. | DROPPED |
| 2.8 | **Form Kit extraction** (checkbox/spinbox/option/section row builders). No concrete problem today. | DROPPED |
| 2.9 | **Write a test asserting the 2.2 boundary** so a future field added to the wrong side fails loudly. Open question: is `to_dict()` correct today by design, or by careful hand-curation? If the latter, the test is what makes it a rule. | OPEN |

---

## 3. Known defects and gaps

| # | Item | Status |
|---|---|---|
| 3.1 | **Six fields sit on the wrong side of the "invalidates history" rationale**: `marks_to_win`, `win_by_two`, `hand_ends_early_set`, `hand_ends_early_points`, `allow_laydown`, `laydown_mode`. All are transactional (correctly, per 2.2) but none invalidates history — they change the goal or the available actions. No action needed under the `to_dict()` boundary; recorded so the reasoning is not rediscovered. | DECIDED |
| 3.2 | **Domino-back swatch row sits below the fold.** At 1280×800 the centres are at y=782 with the scroll viewport ending at y=756 — reachable only after scrolling. The click bug is fixed; the placement is not. Deferred because moving it is a layout decision on a screen getting a design pass (§1). | OPEN |
| 3.3 | **`sevens_require_seven_in_hand` is a serialized field that is no longer a setting.** `from_dict()` forces it `true` regardless of the file and its UI toggle was removed. Dead weight inside the ruleset agreement. | OPEN |
| 3.4 | **Cancel does not cancel everything.** It discards `_pending_settings` only; difficulty and domino back have already committed. Correct under 2.1, but the UI does not say so. Fix is a UI cue, blocked on 1.4/1.5. | BLOCKED |
| 3.5 | **Marks auctions are one-and-done.** `decide_bid()` builds marks bids only at value 1 and only when none is standing, so no AI ever raises a marks auction. Legal, just timid. Largest remaining item from the July 30 audit. | OPEN |
| 3.6 | **Opponent counter-lead has no safety check.** `ai_player.gd:1123-1128` — bare `rank >= 4`, returns the first match in hand order (player-reorderable), no `_highest_in`. Sits directly below a tier that demands provable safety. | OPEN |
| 3.7 | **`PublicKnowledge` allocation cost.** `Deck.new()` + `build_deck()` (28 allocations) at four query sites, called from inside `.filter()` lambdas; `void_suits()` duplicates on every call; `_highest_in`/`_lowest_in` recompute the incumbent's rank each iteration. The Android prerequisite. | OPEN |
| 3.8 | **`from_dict()` performs no validation.** Ruleset JSON is user-reachable; `nello_doubles_mode: "banana"` silently produces wrong ranking all hand. | OPEN |
| 3.9 | **`_absorb_trick`'s `lead_suit < 0` guard swallows `-2`.** Under Nello own-suit a led double sets `lead_suit = -2` and the trick is skipped for void detection. Latent — no consumer today. Needs `variant` added to `record_trick()` first. | OPEN |
| 3.10 | **AI Nello branch never sets `active_nello_doubles_reversed`.** Latent behind "AI cannot bid Nello". | OPEN |
| 3.11 | **Play decisions are not difficulty-stamped.** `bid_decisions` records `difficulty` per AI bid; play decisions record reasons only. A mid-hand difficulty change leaves plays unattributed. Matters only if difficulty becomes a research variable. | OPEN |

---

## 4. Replay screen

| # | Item | Status |
|---|---|---|
| 4.1 | **Vertical diamond spread capped at `REPLAY_SPREAD_Y = 0.9`**; the markup asked for ~1.4. Measured at 1280×800: 1.1 overflows into a scrollbar, 1.0 fills 99.0%, 0.9 lands at 95.3% with ~28px margin. The restored "You played this" row (~48px) is most of the gap — the two requests compete for the same pixels. Lever if wanted: shrink played tiles ~15%. | OPEN |
| 4.2 | **Partner's and your reason rows change height** when text wraps to two lines, shifting content below as you click through tricks. Holding both at two lines costs ~78px — more than the remaining margin. | OPEN |
| 4.3 | Watermark ("42 / Texas Dominos") bleeds through the replay panel; it is 95% opaque. Pre-existing. | OPEN |

---

## 5. Parked deliberately

| # | Item | Why |
|---|---|---|
| 5.1 | **Settings screen redesign** (§1) | Needs the product answer first, and Katy's full attention rather than a corner of a bug-fix session. |
| 5.2 | **`game_table.gd` organisation** — 4,400 lines, 153 functions | The expensive version (extraction) is dropped per 2.7. The cheap version — section banner comments dividing it into regions — is ~20 minutes, zero risk, and makes the file navigable. Offered, not started. |
| 5.3 | **`RankContext` extraction** in `ai_player.gd` | The 5-argument ranking tail across 60+ call sites. Worth doing *before* the Profile system or special-contract bidding, since both add call sites. Not urgent. |
| 5.4 | **Nello play is a stub** | Every seat plays lowest legal, no seat-order awareness. Known design gap. |
| 5.5 | **Set-vs-Make margin is partner-only** | Opponents never compute whether conceding a trick loses the set. Scope question, not a defect. |

---

## 6. Branch state at time of writing

```
main                 2b6ae9e   replay layout merged and pushed
settings-bugfixes    84ef4f9   domino-back click + Play confirmation  (UNPUSHED)
replay-layout        2b6ae9e   merged, can be deleted
audit-fixes-july30   dcaf0fa   merged, can be deleted
ui-table-layout-pass 2e5c479   merged, can be deleted
```

Verification baseline: **224 assertions across 7 suites, 0 failures.**

Suites: `session_lifetime_verify` · `bid_minimums_verify` · `jump_bids_verify` ·
`menu_merge_verify` · `nello_laydown_verify` · `laydown_ends_hand_verify` ·
`tricks_expand_persist_verify`

Probes (diagnostic, not pass/fail): `domino_back_click_probe` ·
`replay_layout_probe`
