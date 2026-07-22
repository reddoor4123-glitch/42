# Alpha Roadmap

*One living document for backlog status and the session history behind
it, replacing the `Texas_42_Session_Summary_July_X_2026_Topic.md`
convention going forward. Each item below gets a session log appended
as work happens on it — the goal is enough context to avoid re-deriving
old reasoning, without the file-per-session sprawl that's made past docs
hard to tell apart at a glance. Does not replace the three pattern-
tracked bug logs (`AI_Play_Behavior_Bug_Log.md`,
`AI_Bid_Behavior_Bug_Log.md`, `AI_Explanation_Bug_Log.md`) — those keep
their own job and their own names.*

---

## Guardrails

Principles earned by real sessions, not abstract rules — kept here so
they don't get orphaned in a retrospective doc nobody reopens.

- **"Every satisfying explanation deserves one more attempt to disprove
  it before becoming architecture."** Earned July 20, 2026 — the trump-
  control investigation went through five rounds of "this explains it,"
  each surviving roughly one more test before needing correction. The
  eventual fix was bigger and more correct than the first three
  explanations would have produced.
- **Premature abstraction, not bad reasoning, is the recurring failure
  mode.** (July 13, 2026.) If a design conversation is producing a new
  vocabulary word every round instead of a converging decision, that's
  the signal to stop and ship the minimal fix.
- **Any time a predicate gets tightened toward correctness, ask what
  looser behavior might have been sheltering inside the old version.**
  (July 13, 2026, from the CONTROL_TRUMP rank-safety tightening — the
  old count threshold was quietly serving as a stopgap for a case the
  tightened version no longer covered.)

---

## Status

| Item | State | Section |
|---|---|---|
| Trump-control (Partner/Opponent unification) | **Done, verified** | [below](#trump-control-unification) |
| Special-contract bidding (Nello/Sevens/Plunge) | Confirmed gap — **tabled with warnings**, see section | [below](#special-contract-bidding) |
| Nello exchange | **Done, verified** | [below](#nello-exchange) |
| "Can't Be Caught" / lay-down | **Done, verified** | [below](#cant-be-caught) |
| Hand-ends-early for Points bids | **Done, verified** | [below](#hand-ends-early) |
| Set-vs-make risk model | **Done, verified** | [below](#set-vs-make) |
| Weekend bidding observations (partner overbid threshold, pressure bidding) | **Both done & verified** | [below](#bidding-observations) |
| Custom AI / difficulty-personality foundation | Just raised, foundation discussion in progress | [below](#custom-ai) |

**Recommended next session:** Nello Exchange, "Can't Be Caught," Hand-
Ends-Early, and Set-vs-Make are all now fully closed out, alongside
Bidding Observations. Special-contract bidding remains the next real
item, still tabled with its warnings intact — see its section. Custom
AI / difficulty-personality foundation is also open, though nothing
currently blocks on it. Smaller, self-contained options also on the
board: the symmetric Opponent-side `partner_winning` consumer of
`is_defending` (see Set-vs-Make section — low-risk, same shape as the
Partner-side consumer already shipped), and the small `CONTROL_TRUMP`
vs. `GIFT_A_VOID` reorder noted below under Trump-Control Unification's
parked items — likely a one-line fix analogous to the SAFE-tier
reorder, but not yet harness-confirmed.

---

## Trump-Control Unification

**Status: Done, verified.** Partner and Opponent (at full vigilance)
now share one trump-control mechanism instead of two independently
maintained ones.

**July 20, 2026 — investigation, fix, and verification.**

Started from a one-sentence family complaint ("the AI doesn't call in
trump") and a static-code read that wrongly concluded it was probably
already fixed. Five rounds of harness-based correction followed:

1. Static read of Partner's `CONTROL_TRUMP` looked correct →
   wrongly assumed fixed. The real gap was in an entirely separate,
   cruder Opponent-side branch not yet traced.
2. First harness (easy-double hand) found Opponent preempted by its
   SAFE tier, leading `0:0` over trump — real finding, but the hand
   handed SAFE tier a free win (any double auto-passes
   `_is_lead_fully_safe()` on trick 1, since doubles always rank highest
   in their own suit).
3. Hardened hand (no free-pass doubles) confirmed the SAFE-tier
   preemption was real regardless, *and* revealed `trumps.size() >= 3`
   is a one-shot, non-persistent check — later "trump leads" were
   landing by accident via the counter-scoring branch and the blind
   highest-tile fallback, not real trump logic.
4. Vigilance/difficulty tested as an independent variable and ruled
   out — Expert/Standard/Beginner converged once the double-crutch was
   removed.
5. Fix: extended Partner's actual rank-safe/persistent mechanism
   (`rank_safe` AND `objective_incomplete`, plus BUG-010's low-trump/
   non-counter preference) to Opponent at full vigilance, via two new
   shared functions in `ai_player.gd` — `_control_trump_lead()` and
   `_control_trump_heuristic_fallback()`. Beginner/Standard untouched
   (unreachable without `vigilance == "full"`).

**Verified, not just labeled:** final regression run showed
`rank_safe: true` / `opposing_team_all_void_in_trump: true` /
`control_trump_eligible: false` together on the trick where the
objective correctly stood down — confirming the stopping mechanism
directly, not by label alone. A new top-2-trump hand (both old `>=3`
and `>=4` thresholds false) confirmed the fix adds real capability, not
just reordering — `rank_safe` alone made it fire. Regression scripts:
`trump_control_trace.gd`, `trump_control_trace_v2.gd`,
`trump_control_trace_v3.gd` (kept in-repo as living tests for this
mechanism).

**On the deliberate-asymmetry question:**
`Phase3_Objective_Audit_REWRITE_July14_2026.md` documented Opponent's
cruder treatment as an *intentional* asymmetry, not a gap — opponents
allowed to be a notch less thorough, to give the human team a subtle
edge. Today's fix narrows that principle rather than reversing it: the
old version wasn't "a notch less thorough," it was structurally unable
to produce the behavior at all, for reasons unrelated to difficulty.
Beginner/Standard keeps the original, genuinely simpler heuristic,
preserving the actual intent behind the original choice.

**Explicitly not resolved by this fix — still parked:**
- Step 3's ultimate fate (stopgap vs. real trump-evaluation model).
- The general trump-evaluation vocabulary (quantity/ceiling/continuity/
  counter-cost).
- Beginner/Standard Opponent tuning.
- `CONTROL_TRUMP` vs. `GIFT_A_VOID` priority ordering. **Mechanism
  identified July 20-21, 2026 (design discussion, not yet harness-
  traced):** `GIFT_A_VOID` (`ai_player.gd:716-730`) is checked before
  `CONTROL_TRUMP` and explicitly excludes trump tiles
  (`if d.is_trump(trump): return false`), so it can't hijack a trump
  lead directly — but it *can* preempt reaching `CONTROL_TRUMP`'s check
  at all, costing a trick of an in-progress, still-eligible
  (rank-safe + objective-incomplete) trump-control run whenever the
  partner happens to be void in some other suit that trick. Same shape
  as the SAFE-tier reorder (BUG-016) — a heuristic, opportunistic
  objective sitting ahead of a provable one in file position, with no
  principled reason for the ordering. Suspected to be the actual root
  cause behind the informally-logged BUG-015 ("switches to the other
  double before both opponents are proven void"). Likely fix: move
  `CONTROL_TRUMP`'s eligibility check ahead of `GIFT_A_VOID`, mirroring
  BUG-016's reorder — small, but needs a harness trace to confirm the
  theory before treating it as done.
- Selection priority as an inspectable structure vs. file position.

**Close the loop with the family:** the original complaint likely came
from a mix of seats/difficulties. This fix specifically addresses
Opponent seats (P1/P3) at full vigilance (Expert) — Partner was already
correct. Worth a specific re-test on opponent seats across difficulties
to confirm this closes the real-world report, rather than assuming it
does because the harness evidence is strong.

---

## Special-Contract Bidding

**Status: Confirmed gap, not started. Tabled — see warnings below.**
`AIPlayer.decide_bid()` (`ai_player.gd:208-350`) only ever constructs
`MARKS`, `POINTS`, or `PASS`. It never touches `NELLO`, `SEVENS`,
`PLUNGE`, or `SPLASH`. Blocks the entire Nello-exchange and
doubles-own-suit-discard work, since AI can't currently bid into either.

**Cautions and flags, raised before any design work — read these again
before this item is picked back up:**

- **This is not "add a branch to `decide_bid()`."** The existing
  pipeline (Layer 1 `evaluate_hand`/`best_trump` → Layer 2 signal
  combiner → Layer 3 execution) is built entirely around one idea:
  estimate how many points a hand is worth, then decide whether to
  announce it. Nello, Sevens, Plunge, and Splash don't have "points" in
  that sense — Nello wins by losing every trick, Sevens by proximity to
  7, Plunge/Splash by sweeping all 7. None of them reduce to
  `estimated_points` the way the current pipeline assumes. The real
  design problem is how a fundamentally different evaluation shape
  competes in the *same auction* as the already-tuned, already-trusted
  points/marks logic — not a simple additive feature.
- **Toggles are a first-class requirement from line one, not a
  retrofit.** `game_settings.gd` already has `allow_nello`/
  `allow_sevens`/`allow_plunge`/`allow_splash` — but those gate whether
  a contract exists *at all* for anyone, human included. What's needed
  is a second, independent axis: whether AI specifically may bid a
  contract that's otherwise legal in the game (e.g. a new
  `ai_may_bid_nello`, separate from `allow_nello`, defaulting to off).
  This needs to be designed in from the start, not added after the AI
  already knows how to bid these hands.
- **Katy's read, and Claude's independent agreement:** this is scoped
  correctly as real work, but it's large enough and risky enough to the
  bidding system as a whole that it deserves its own careful,
  dedicated session — not a bolt-on to whatever's being worked next.
  Explicitly tabled rather than sequenced immediately.

**Sequencing decision (July 20, 2026):** Bidding Observations (below)
will be worked first, one at a time. Special-contract bidding stays
tabled, warnings intact, until that work closes out.

---

## Nello Exchange

**Status: Done, verified (July 21, 2026).** Implements the family's
"unusually lenient" house rule: once the human declares Nello and picks
a doubles mode, they may blindly exchange exactly one domino with their
sitting-out partner (bidder P0 ↔ partner P2 in the current single-
human-seat setup) — fully optional per hand via the existing
`allow_nello_exchange` toggle, plus a new per-hand "Don't Trade" decline
that cancels the whole exchange if pressed.

**Spec written and built same-day, no drift.** The prior session's
scaffold-only assessment held — `allow_nello_exchange`,
`nello_exchange_bidder_gives`, `nello_exchange_partner_gives`
(`game_settings.gd`) existed but had zero consumers. Katy walked through
the actual family strategy directly (not inferred from the settings
strings, which turned out to describe a different, unused shape); that
strategy became a tiered give-selection algorithm, one tier order per
doubles-mode variant (high / low / own_suit / own_suit-reversed), since
which doubles are dangerous to hold flips depending on the mode. Two new
functions:
- `AIPlayer.select_nello_exchange_give(hand, doubles_mode, doubles_reversed)`
  (`ai_player.gd`) — deliberately seat-agnostic, not hardcoded to the
  partner seat, per Katy's request for whenever AI Nello bidding exists
  (it doesn't yet — `decide_bid()` never constructs `Type.NELLO`).
- `Game.apply_nello_exchange(bidder_give, partner_give)` (`game.gd`) —
  pure swap; both gives are decided independently (blind) beforehand.
Wired into `game_table.gd`'s `_on_nello_mode_selected()`, between
`apply_bid_result()` and `_begin_play()`.

**Verified, not just labeled.** `nello_exchange_trace.gd` (headless,
`--script`) covers all four doubles-mode variants with hands engineered
to force each tier of the priority stack in turn, plus swap correctness
(both hands stay at 7 tiles, correct tile moves each direction).
`nello_exchange_trace_results.json`: **0 failures across 23 checks.**
Does not cover the UI panel itself or the `allow_nello_exchange = false`
skip path — those need an interactive session, not a headless
`SceneTree`, and weren't re-verified against the trace.

**Nice side effect:** `game.nello_solo_player` (`game.gd:16/58/160`) —
computed since the trump-control work but flagged twice as having zero
consumers anywhere — finally has one. Not a coincidence; this feature
is exactly what it was sitting there for.

**Also shipped in the same session/commit, not separately tracked
elsewhere on this roadmap** (smaller UI/settings items, a few worked
out directly in the editor with Claude Code rather than fully spec'd in
advance):
- Bottom-left persistent bid reminder (`bid_reminder_label` /
  `_update_bid_reminder()` in `game_table.gd`) — trump/contract/value
  stays visible through the hand, refreshed at every point a contract
  finalizes (both human panels and the inline AI branches in
  `_finish_bidding()`).
- Teel Rules custom domino back — `DominoTile.custom_back_texture`
  (static, shared across tiles) plus `_update_domino_back_texture()`,
  gated on a new `preset_id` field on `GameSettings`; every other preset
  still falls back to the existing procedural back pattern.
- Playable-tile highlight changed from green to orange
  (`COLOR_PLAYABLE` in `domino_tile.gd`) — green was blending into the
  felt background.
- Hand display now refreshes after every individual play
  (`_execute_play()` → `_refresh_all_hands()`), not just at trick
  boundaries.

---

## "Can't Be Caught" / Lay Down

**Status: Done, verified (July 21-22, 2026).** Digital version of the
real-table custom — a player holding a guaranteed-unbeatable remaining
hand can claim it, all hands reveal face-up, and a wrong claim forfeits
the contract just as surely as a correct one wins it.

**Rule, as confirmed with Katy:** punishment/reward is universal and
symmetric regardless of who claims (bidder, partner, or defender) — a
correct claim wins the contract immediately at its stated value; an
incorrect one forfeits it to the other side, same value, no trick/point
simulation either way. Human seat only for now (AI claiming is real
future scope, not built). Lead-only trigger — not just a UX choice: the
whole proof is only valid because winning trick N under this precondition
guarantees leading (and therefore being able to re-prove safety for)
trick N+1, by induction. Two sub-modes under one settings toggle:
**Assisted** (button only appears once a claim is already provably
correct — zero risk) and **Authentic** (available anytime on your lead,
self-judged, verified silently on press, wrong claim really forfeits).

**The verification algorithm — `laydown_check.gd`:** a domino is safe if
nothing that could beat it remains unaccounted for, where "accounted for"
means either already played, or currently sitting in the claimant's own
hand (a tile you hold can't simultaneously be with an opponent — directly
from Katy's own table example: holding 6:6 makes 6:5 provably safe even
before 6:6 is officially played). Static per-tile check, no trick-by-trick
simulation needed. Verified via `laydown_check_trace.gd`: **9/9 passing**
(`laydown_check_trace_results.json`), including a genuine played-tile-
dependency case Claude Code caught was missing on the first pass, plus its
negative contrast.

**Two supporting `game.gd` functions, verified via
`laydown_game_functions_trace.gd`: 21/21 passing**
(`laydown_game_functions_trace_results.json`):
- `resolve_hand_via_laydown(claimant_id, claim_correct)` — flat mark
  award (1 for Points, `current_bid.value` otherwise) to whichever team
  the claimant belongs to, matching how a "set" already awards marks
  elsewhere. `team_points` deliberately left untouched.
- `is_contract_already_lost(claimant_id)` — a correct remaining-hand proof
  isn't sufficient by itself for all-tricks contracts (Marks/Sevens/
  Plunge/Splash) if an earlier trick was already lost. **Real, pre-
  existing gap found and closed along the way:** `_is_bid_mathematically_set()`
  only ever covered Marks/Sevens/Nello — Plunge and Splash were never
  included despite needing all 7 tricks too, so a hand could reach a
  later trick already irrecoverable and the game just kept playing. This
  function closes that gap generally, not just for lay-down claims.

**UI wiring (`game_table.gd`, `game_settings.gd`) — confirmed both in
source and by an actual played hand:** `allow_laydown`/`laydown_mode`
settings fields; a bottom-right "Lay Down" button, visible only on a
fresh trick lead (`game.current_trick.plays.size() == 0`), with Assisted
mode additionally gating on live provability; face-up reveal reusing the
existing `_populate_hand_container()` helper with `face=true` — no new
rendering code needed; `_resolve_hand()` refactored into a shared
`_show_hand_result()` so both normal and lay-down resolution paths use
the same result-display code. One bug found and fixed outside the
original spec: nothing reset `laydown_btn.visible` at hand start, so it
could linger visible into the next hand's dealing/bidding UI.

**Domino-suit corrections learned this session, worth keeping on
record since they apply beyond this feature:** a non-double domino's
suit, when it's the one being led, is always its high end (`Domino.get_suit()`'s
`return max(left, right)` fallback) — 0:2 leads as twos, not blanks.
Blanks as a led suit can only ever be established by 0:0 itself, since
it's the only domino whose high end is 0.

**Explicitly tabled, not forgotten:** Nello lay-down claims — inverted
safety condition (lowest-in-suit, not highest), no trump, and the bidder
only ever leads trick 1 (loses it on purpose), which breaks the lead-only
trigger assumption this whole build depends on. Corrections already on
record in `Laydown_Session_Handoff_July21_2026.md` so this doesn't get
re-derived wrong later. Sevens explicitly not needed per Katy's read —
too unpredictable/late-deciding to sensibly lay down. The void-suits
strengthening (inferring an untraced tile must be with partner when both
opponents are proven void in its suit) remains a named, unbuilt v2
candidate.

---

## Hand-Ends-Early

**Status: Done, verified (July 22, 2026).** Closes out both halves of
the original ask — extend early-stopping to Points bids, and add a
toggle for the cases that already did this unconditionally — plus a
real, pre-existing Plunge/Splash gap found and closed along the way,
plus Follow Me confirmed to need no special handling at all.

**Consolidated onto one function instead of two parallel copies of the
same idea.** The old `_is_bid_mathematically_set()` (`game_table.gd`)
covered Marks/Sevens/Nello only, fired unconditionally, and — traced
fresh this session — never covered Plunge/Splash despite them also
needing all 7 tricks per `resolve_hand()`'s own logic. Rather than patch
it twice (add Plunge/Splash, add a toggle), it was retired in favor of
`game.is_contract_already_lost()` — the function built for last night's
lay-down work, which already covered all five all-tricks contract types
correctly. One function, one new toggle (`hand_ends_early_set`,
defaults **true** to match prior behavior), closes the gap and adds the
toggle in the same move.

**Points bids — genuinely new, and simpler than it looked.** New
`game.is_points_bid_decided()`, gated by `hand_ends_early_points`
(defaults **false**). Checks both directions — already mathematically
achieved (points can't be taken back once banked) or already
mathematically unreachable — using one fact that made this far easier
than the lay-down work: total points across any hand are always exactly
42 (seven 1-point tricks plus three 5-count and two 10-count dominoes —
a fixed property of the domino set, confirmed against
`Trick.calculate_points()`, independent of trump/contract/doubles mode).
"Points remaining" is just `42 - team_points[0] - team_points[1]` — no
per-tile inspection needed, unlike lay-down's tile-by-tile proof.

**Follow Me — traced end to end, needed zero new code.** Initially
misdiagnosed (see below) as having a different, majority-based win
condition; actually confirmed to fall through to the ordinary POINTS (or
MARKS) branch of `resolve_hand()`; the "No Trump (Follow Me)" button is
a trump-selection choice shown *after* winning an ordinary Points/Marks
bid, not a separately-constructed bid type — `Bid.Type.FOLLOW_ME` is
confirmed dead code, never reached from the live bidding flow (already
logged, `Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md`,
item 7 — not touched in this pass). So a "30 points, Follow Me" hand has
`current_bid.type == POINTS` under the hood, same as any other Points
bid; `is_points_bid_decided()` covers it with no special-casing at all,
confirmed directly in the trace (identical result with `trump = -1`).

**Correction to an answer given earlier this session:** Claude was asked
directly whether Follow Me was already scored as a real points target
and initially said no, based on reading `resolve_hand()`'s
`FOLLOW_ME, PLUNGE, SPLASH` match arm without checking whether `variant`
could actually equal `FOLLOW_ME` in reachable play. It can't. Katy's
pushback was correct; the dead-code note above was already sitting in
the docs and should have been checked first.

**Verified two ways, not just one.** `hand_ends_early_points_trace.gd`:
11/11 passing, including both exact-boundary cases (hitting the target
exactly counts as achieved via `>=`; landing exactly on the remaining-
points threshold does *not* count as set, via strict `<`) and a bidder-
on-team-1 case confirming the team math isn't hardcoded. Re-ran the
existing `laydown_game_functions_trace.gd` as a regression check since
its neighboring function's comment was edited — still 21/21, unchanged.
Playtested live (July 22, 2026) — Katy confirmed satisfied, including
the toggle-off paths and the actual Plunge/Splash early-stop the whole
consolidation was built to close.

**Retired, not deleted:** `_is_bid_mathematically_set()` is commented
out in place, with a note explaining why, pending one literal
repo-wide `grep` (explicitly requested before any edits this session)
as final confirmation before real deletion in a later pass — the
semantic-search-based trace found exactly one call site, but Katy asked
for a literal grep as the final word given how load-bearing retiring it
is.

---

## Set-vs-Make Risk Model

**Status: Done, verified (July 22, 2026).** Introduces a Set-vs-Make
policy axis into `decide_play()` — a team defending against a contract
now accepts a narrower, non-global safety proof to throw counters in,
where a team making its own contract still requires the strict,
unconditional guarantee. Grew directly out of the concrete traced
instance below, logged the prior session: sister's team didn't hold the
bid; sister led a winning off-suit double; P2 (her AI partner) declined
to throw count in, "still playing cautiously around remaining trump" —
traced to `_is_guaranteed_win()`'s off-suit-double path requiring *every*
remaining trump to be provably in P2's own hand, a threshold fixed
regardless of who held the bid.

**Architecture:** `is_defending` (`ai_player.gd:706`) is established once
as shared context near the top of `decide_play()`, alongside the
pre-existing `mode` lookup — not inlined per-branch. A new evaluation
function, `_is_win_safe_against_remaining_actors()` (`ai_player.gd:1349`),
sits beside `_is_guaranteed_win()` without modifying it, reusing the
existing BUG-007/012 two-path safety test
(`_is_lead_fully_safe()`/`_is_lead_safe_against_opponent()`) restricted
to players still left to act this specific trick — not a global proof,
a narrower one. Policy widens the acceptance threshold when defending;
it never bypasses evaluation, and the threshold is answered by a real
fact-check every time, not skipped for `is_defending` alone.

**First consumer:** the Partner counter-dump decision in the
`human_is_winning` branch (`ai_player.gd:867` on) — the exact incident
above. `win_safe_against_remaining` (`ai_player.gd:883`) only engages
when `is_defending` is true AND `guaranteed_win` is false, so it's
strictly additive to the existing gate, never a replacement for it. A
real ordering bug was caught and fixed before shipping: the reason-
string logic originally checked `guaranteed_via_double` before
`guaranteed_win`, which would have let a defending-only, risk-accepted
win misreport as a certain one ("Good double — putting my points on
your trick.") whenever the winning tile happened to be a double.
Corrected to check `guaranteed_win` first (`ai_player.gd:906-908`) — a
defending-only win now correctly logs "We're defending — taking the
chance to add these points." instead.

**Verified four ways, all run against live `decide_play()`, not
inferred** (`set_vs_make_trace.gd`, `set_vs_make_path_b_trace.gd`,
`set_vs_make_path_a_negative_trace.gd`, plus their `*_results.json`):
- **Path A positive** (double lead, opponent not void in suit) — SET
  dumps the counter with the corrected reason string; MAKE is
  unaffected, identical to pre-change behavior.
- **Path B positive** (opponent proven void in both suit and trump, via
  real prior-trick history, not asserted) — SET dumps with the new
  reason string; MAKE falls through to the pre-existing, unmodified
  forced-overtake fallback.
- **Path B negative** (opponent void in suit only, trump status
  genuinely unestablished) — MAKE and SET produce identical output;
  `is_defending` does not override an unproven trump threat.
- **Path A negative** (opponent genuinely not void, tile not a double, a
  higher tile in the suit sitting outside Partner's hand) — MAKE and SET
  again identical; `is_defending` does not override a genuine same-suit
  threat.

The two negative cases are the actual safety property under test:
lowering the acceptance threshold while defending must never substitute
for evaluation saying "unsafe" — confirmed by MAKE/SET producing
byte-identical chosen tiles and reason strings in both negative
scenarios.

**Not yet extended:** the symmetric Opponent-side `partner_winning`
branch (`ai_player.gd:1154` on) — `is_defending` is in scope there too
(computed once at function top), just not yet consumed; that branch
still only has the old save-strength/forced-overtake logic. Flagged as
a natural, low-risk follow-up, not attempted this session.

**Also noted, unchanged and out of scope:** a pre-existing reason-string
quirk in the forced-overtake fallback shared by both branches —
`"Taking it with my double — nothing beats this."` (`ai_player.gd:930`,
`1165`) fires whenever `_is_guaranteed_win()` succeeds per-candidate,
regardless of whether the actual tile is a double. Predates this
session; not introduced by it; not touched.

---

## Bidding Observations

**Status: Both items done and verified (July 20, 2026).**

1. **Partner-relationship-aware overbid threshold — done, verified
   (July 20, 2026).** Shipped as a gate inside `decide_bid()`:
   `partner_id` computed inline (`(player_id + 2) % 4`, no new
   parameter), gated by a new `human_seat` parameter. When
   `current_high.player_id == partner_id AND partner_id == human_seat`
   (i.e., specifically P2 overbidding P0), requires
   `target_bid >= min_points + PARTNER_OVERBID_MARGIN` (named constant,
   currently `3`) instead of just `target_bid >= min_points`.
   `_announced_points_bid()` still receives the real `min_points`, not
   the elevated bar — composition with the announced-bid filter
   verified via independent recomputation, not a hardcoded expected
   value (so future tuning of the announcement formula won't spuriously
   break this test). Marks bids explicitly out of scope — the Marks
   branch is a categorical gate, not a numeric target, and would need
   its own mechanism if ever extended to cover partner-courtesy. Scope
   deliberately narrow: P1/P3 overbidding each other untouched, per the
   "only the human feels this" reasoning. Verified via
   `partner_overbid_gate_trace.gd`, 6 cases including a deliberate
   two-condition-necessity test (Case 4) and a statelessness check
   (Case 6, confirming a conservative announcement doesn't cap a later
   re-evaluation of the same hand). All passing; sibling
   `bid_filter_trace.gd` regression-checked afterward with no changes.
2. **Lowest-legal-bid filter (a.k.a. Announced-Bid Filter) — done,
   verified (July 20, 2026).** Two-part rule, both unconditional, no
   personality/difficulty gating, applies to opens, raises, and forced
   bids alike (confirmed by construction — all three flow through the
   same Layer 3 block):
   - **Shaker override:** if this seat is the shaker (definitionally
     the last bidder — nothing left to pressure), announce the legal
     minimum, full stop, regardless of hand strength.
   - **Two-tier margin (everyone else):** announce `min_points` if the
     private `target_bid` is marginal (`<= min_points + 1`), else
     `min_points + 1` — one point of insurance, ceiling withheld either
     way.
   Shipped as `_announced_points_bid(target_bid, min_points, player_id, shaker, max_overbid)`
   in `ai_player.gd`, called from Layer 3 in place of the old clamp.
   `bid_order()` (`game.gd:79-85`) confirmed to unconditionally append
   `shaker` last, so `player_id == shaker` needed no new plumbing.
   Layer 1/2 (hand-truth, private confidence) untouched by design — see
   `Spec_Announced_Bid_Filter_July20_2026.md` for the full spec.
   **Old `max_overbid` clamp kept active, not deleted** — verified as a
   no-op today (`max_overbid` is 2/4/6 across beginner/standard/expert,
   always ≥ 1) but retained as a real safety bound against a future
   Custom-AI case where `max_overbid` could be independently tuned
   below 1, which would otherwise let the two-tier margin silently
   violate a hyper-conservative custom AI's own setting. Verified via
   `bid_filter_trace.gd`: 5 spec cases plus a forced-bid check, all
   passing against the real `decide_bid()`, including a direct isolated
   call to the safety clamp with a synthetic `max_overbid=0` to prove
   it engages even though no current preset can reach that value.
   Structurally enforced pass/fail (non-empty `failures` array fails
   the run), not just a printed summary.

**Correction to earlier framing in this doc:** previously assumed both
observations shared a bid-position-threading prerequisite
(`bid_order()`/`bid_context()`). That doesn't hold now that both
mechanisms are precisely specified — Observation 1 only needs
`partner_id` passed into `decide_bid()` (mirroring the parameter
`decide_play()` already has) compared against `current_high.player_id`;
Observation 2 only needs `shaker` (or an equivalent
`player_id == shaker` check). Neither needs bid-order/position data.
Bid-position threading may still matter for other future bidding work,
but isn't a prerequisite for either of these two.

**Sequencing (decided July 20, 2026):** these two go first, one at a
time, ahead of special-contract bidding — see that section for why it's
tabled.

---

## Custom AI / Difficulty-Personality Foundation

**Status: Just raised (July 20, 2026), foundation discussion in
progress, not yet decided.** Originally part of the family bug report
("Custom AI" — name opponents, set intelligence level, choose which
contracts each may bid). Resurfaced directly out of the bidding-
observations discussion: designing Observations 1 and 2 correctly
requires knowing which axis of the AI's behavior each one belongs to,
and that axis structure doesn't fully exist yet.

**Current truth:** `AI_MODES` (`ai_player.gd:25-44`) bundles three
different kinds of things under one difficulty string, confirmed
distinct on inspection:
- `vigilance` (none/full) — a hard capability gate: does this seat get
  `PublicKnowledge` access at all. Not a dial.
- `opportunism` (0.0–1.0, rolled per-decision) — closer to consistency/
  attentiveness than boldness: does this seat reliably act on what it
  can see, or commit reflexively.
- `risk_bias`/`max_overbid` — the one that's actually personality in
  the aggression sense.

Selecting a difficulty preset today bundles all three together
indivisibly. The existing `AI_Design_Doctrine.md` Knowledge/Evaluation/
Neither litmus test already exists for judging whether a given
behavioral difference should vary by difficulty at all — Partner's
cooperative logic is a confirmed "Neither" case (zero difficulty
branching, by design). That litmus is the right tool to keep reusing
here rather than inventing new classification from scratch.

**Katy's direction (July 20, 2026):** personality should become an
independently tunable layer, separate from difficulty — difficulty
presets seed personality defaults, but a future Custom AI should be able
to override any one axis without dragging the others along. Explicit
goal: a solid, minimal foundation now, not the full Custom AI feature —
avoid exploding scope.

**Resolved this session (July 20, 2026):**
- **Observation 1:** scoped to P2-over-P0 specifically, not a general
  seat-agnostic mechanism — reasoning is experiential (only the human
  feels this cost), not a personality/difficulty axis question at all
  for pass 1. Margin value still needs calibration.
- **Observation 2:** absolute, unconditional rule (shaker bids the
  legal minimum, regardless of forced/chosen), not personality- or
  difficulty-gated. Belongs in Layer 3 (execution), not Layer 1.

Neither observation ended up needing a personality/difficulty axis
assignment — both are unconditional rules for pass 1. The
Knowledge/Evaluation/Neither litmus and the vigilance/opportunism/
risk_bias breakdown remain the right tools for *future* parameters
where variation-by-difficulty is actually in question — this session's
two items just didn't turn out to be that kind of parameter.

**Not yet touched:** the naming/UI parts of the original Custom AI
request (renaming opponents, per-seat contract-bidding permissions —
the latter already flagged under Special-Contract Bidding's toggle
requirement). This section is currently scoped to the underlying
axis/parameter architecture question only.
