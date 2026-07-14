# Texas 42 — AI Bidding Structure Overview

*Prepared for outside review. Describes the current implementation as it exists in code today — not a proposal, not a wishlist. Known concerns are called out explicitly in their own section at the end.*

> **Update, July 12, 2026:** The evaluator sections below (§2.3, §2.4, §2.5,
> §3.1(B)) described the pre-fix state and are now corrected in place to
> match the "Bidding Evaluator Fixes #1-#4" package that landed the same
> day (`ai_player.gd`, `evaluate_hand()`/`decide_bid()`), validated against
> 20 real in-game hands. Findings #1 and #2 from the original "Open
> questions" section (§6) are resolved by that package; #3, #4, #5 are
> still open and untouched, exactly as this document originally described.
> See `AI_Bid_Behavior_Bug_Log.md` and `Texas_42_Session_Summary_July_12_2026_BiddingFixPackage.md`
> for the full before/after and the three newly-logged limitations that
> replaced findings #1/#2.

---

## 1. Context

This is a Godot/GDScript implementation of Texas 42 (family ruleset, house variant — not strict tournament rules). AI players decide whether and how much to bid via a single function, `decide_bid()`, which runs in three layers:

1. **Evaluation** — objective math on what the hand is worth
2. **Decision policy** — combines that math with personality into a go/no-go verdict and a bid amount
3. **Execution** — enforces legal-bid rules only (no re-scoring)

Three difficulty tiers exist — beginner, standard, expert — sharing one decision engine. Difficulty is meant to change *inputs* (personality parameters), never spawn separate logic paths.

**Live design concern driving this review:** across all three difficulty tiers, AI players are passing on a large majority of dealt hands (informal estimate: ~90%), which regularly forces the human player into opening bids on weak hands even when an AI partner is holding a hand a real player would act on. Real Texas 42 tables see meaningfully more bidding activity than this, including some deliberately speculative opening bids (30/31) that experienced players make because points are often easier to make than the raw hand strength suggests, especially with partner support. This document exists to lay the full mechanism out for an outside read on where that gap might be coming from.

---

## 2. Layer 1 — Hand Evaluation (`evaluate_hand`, `best_trump`)

This layer is considered "objective truth" in the codebase — nothing downstream is supposed to re-derive hand strength, only react to it.

### 2.1 Trump suit selection

`best_trump()` tries all 7 possible trump suits, scores the hand under each via `evaluate_hand()`, and picks whichever suit produces the highest score:

```
score = estimated_points + trump_count * 2.0
if has_double_trump: score += 3.0
```

The winning suit's full evaluation dictionary is what feeds everything downstream.

### 2.2 Trump strength scoring

Each domino held in the chosen trump suit contributes an individual "win probability" based on its rank within that suit (not a flat per-trump rate):

```
if domino is the double:          win_prob = 0.95
else:                              win_prob = 0.35 + (rank / 6.0) * 0.50
```

So the weakest trump (rank 0) contributes 0.35 of an expected trick; the strongest non-double trump (rank 6) contributes 0.85; the double contributes 0.95. These sum into `estimated_tricks`.

### 2.3 Off-suit scoring (updated July 12, 2026 — Fixes #1 and #4)

Non-trump dominoes ("off-suit") are grouped by suit. Non-double off-suit
tiles are scored by rank tier; off-suit doubles are collected separately
and scored as their own group:

```
# Non-double off-suit tiles:
elif rank >= 4 and count_in_that_suit >= 2:    + 0.4
elif rank >= 5:                                + 0.3
elif rank >= 4:                                + 0.2   # Fix #1 — was 0.0 before July 12
else:                                          + 0.0

# Off-suit doubles (Fix #4), scored as a group rather than a flat +0.5 each:
for each off-suit double, by pip value:
    win_prob = 0.55 + (pip_value / 6.0) * 0.25    # 0:0 = 0.55 .. 6:6 = 0.80
    + a compounding bonus for each additional double held: +0.3 / +0.5 / +0.7
    + a further +0.2 if the hand holds both 4:4 and 6:6 (brackets the 6:4 ten-count)
```

A lone rank-4 off-suit tile (e.g. a solo 4:6) that previously scored zero
now scores 0.2 (Fix #1). Off-suit doubles are now rank-scaled and compound
with each additional double held, rather than all scoring an identical
flat 0.5 regardless of which double or how many (Fix #4).

### 2.4 Capture model

```
expected_capture = estimated_tricks * 6.0
```

Every trick is treated as worth a flat 6 points on average (42 total points / 7 tricks), regardless of which specific dominoes are actually in play or held by other hands. This factor is untouched by the July 12 fixes and remains explicitly out of scope for future tuning passes.

### 2.5 Counter realization is now included (updated July 12, 2026 — Fix #2)

```
estimated_points = expected_capture + realization_bias   # full inclusion, no scaling factor
```

`realization_bias` (per-counter expected placement vs. the flat 6-per-trick
average — positive for protected counters like a trump 5:5, negative for
exposed ones like a naked 4:1) previously was computed and then explicitly
discarded. It's now folded into `estimated_points` directly, benchmark-verified
against 20 real in-game hands. This closes what the original version of this
document (below) listed as finding #2. `counter_points` remains diagnostic-only
and does not feed `estimated_points`.

---

## 3. Layer 2 — Decision Policy (inside `decide_bid`)

Layer 2 does not re-score the hand. It combines three independent signals into one number, then compares that number to a fixed threshold.

### 3.1 The three signals

**(A) EV signal** — Layer 1's value, shifted by personality:
```
ev_score = estimated_points + risk_bias * 4.0
```

**(B) Control signal** — structural confidence, separate from raw value:
```
control_score = estimated_tricks * 6.0 * 0.12
if has_double_trump:     control_score += 2.5
if trump_count >= 4:     control_score += 1.5
if trump_count >= 5:     control_score += 3.0   # was +1.0 before July 12 (Fix #3)
if trump_count >= 6:     control_score += 2.0   # new tier, July 12 (Fix #3)
```
Updated July 12, 2026 (Fix #3): holding 5 of 7 trump is majority control —
at most two trump outstanding across three other players — confirmed
qualitatively different from "one more trump" by a played-out 36-6 hand
(see `AI_Bid_Behavior_Bug_Log.md` finding #3). The old flat `+1.0` at 5+
undervalued this compared to the 4+ tier just above it.

**(C) Auction stance bias** — a classification of hand "shape" into one of four categories, each carrying its own flat bonus/penalty:

| Stance | Condition | Bias |
|---|---|---|
| `pressure_opener` | est_tricks ≥ 4.3 **and** holds double trump | +2.0 |
| `solid_opener` | est_tricks ≥ 4.0 **and** trump_count ≥ 4 | +1.0 |
| `competitive` | ev_score ≥ 24.0 (falls through both above) | 0.0 |
| `defensive` | none of the above | −1.5 |

### 3.2 Personality parameters (`AI_MODES`)

| Difficulty | `risk_bias` | `max_overbid` |
|---|---|---|
| beginner | −0.25 | 2 |
| standard | 0.0 | 4 |
| expert | +0.25 | 6 |

**Update, July 12, 2026:** `AI_MODES` also carries two play-side-only keys,
`vigilance` (`"none"`/`"full"`) and `opportunism` (now a real `0.0`-`1.0`
probability, not the inert string placeholder this document originally
described alongside a now-removed `cooperation_bias` key). Both are
read by `decide_play()`, not by anything in this document's bidding
pipeline — bidding's `risk_bias`/`max_overbid` are explicitly untouched
by that migration. See `Spec_Difficulty_Modes_TwoAxis_July12_2026.md`
if this table is being extended for bidding personality in the future.

### 3.3 The go/no-go gate

```
final_score = ev_score + control_score + stance_bias
should_bid = final_score >= 28.0
```

**This threshold (28.0) is a fixed constant.** It does not vary by difficulty. Difficulty only affects the inputs feeding into `final_score` (via `risk_bias`), not the bar itself.

### 3.4 The target bid amount

Separately from *whether* to bid, this formula decides *what number* to say:

```
target_bid = round(estimated_points + risk_bias * 3.0 + stance_bias)
target_bid = max(28, target_bid)
target_bid = min(target_bid, round(estimated_points) + max_overbid)
```

Note this uses `risk_bias * 3.0` here, versus `risk_bias * 4.0` in the go/no-go formula above — same personality knob, two different weights depending on which calculation it feeds.

Also note the floor here is 28, not the actual table minimum of 30 — a hand can produce a `target_bid` below the legal floor at this stage; that gets corrected in Layer 3.

---

## 4. Layer 3 — Execution (legality only, no re-scoring)

This layer enforces auction rules and does not touch the hand-strength math:

- **Forced-bid override** — if this player is last to act and everyone else has passed (and the ruleset allows forced bids), `should_bid` is forced true and `target_bid` is floored at 30.
- **Legal-minimum floor bump** — if `should_bid` is true but `target_bid` is below the actual legal minimum (30, or one above the current high bid), it gets raised to that minimum.
- **Marks-bid gate** — a separate fork, evaluated *before* the points-bid path returns:
  ```
  if trump_count >= 5 and has_double_trump
     and (holds an off-suit double OR trump_count >= 6)
     and (no marks bid currently on the table):
        → bid 1 mark
  ```
- **Points-bid finalization** — if none of the above diverted, and `should_bid` is true and points are still legally biddable:
  ```
  final_bid = clamp(target_bid, [legal_minimum, legal_minimum + max_overbid], ≤ 42)
  ```
- **Forced fallback** — if forced to bid and nothing above fired, bid a flat 30.
- **Pass** — the default outcome if none of the above triggered.

### Ruleset context (current default settings)

| Setting | Value |
|---|---|
| Minimum bid | 30 |
| Forced-bid minimum | 30 |
| Max open bid (marks) | 2 |
| Allow jump bids | true (family rule: "any amount up to one mark higher") |
| Plunge minimum doubles / marks | 4 / 4 |
| Splash | off by default in the family ruleset |

---

## 5. What the AI currently does *not* consider

For completeness, since these are common points of comparison to real-player bidding behavior:

- **Partner's hand** — there is no signal anywhere in this pipeline representing "my partner probably has something that covers my weak suits." Every bid is computed purely from the bidder's own 7 dominoes.
- **Opening special contracts** — `decide_bid()` only ever returns a POINTS or MARKS bid. The game engine already computes contract eligibility (`eligible_contracts()` checks Nello / Sevens / Plunge / Splash qualification), but the AI bidder never calls it — it cannot currently open one of these contracts on its own initiative.
- **Auction pressure / opponent modeling** — the bid doesn't change based on how the auction has gone so far beyond the mechanical "what's the current legal minimum" check (no bluffing, no reading opponents' bids as information).

---

## 6. Open questions this review is meant to surface

These are specific, unresolved points raised while walking through this structure — not yet decided one way or the other:

1. ~~**Off-suit sequential runs score zero.**~~ **Partially addressed July 12, 2026.** Fix #1 gives a lone rank-4 off-suit tile a nonzero score (0.2) instead of 0.0, and Fix #4's rank-scaled, compounding off-suit-doubles scoring covers the doubles-heavy version of this gap. The general *sequential run* case (e.g. four low trump plus 6-6/6-5/6-4 acting as a second trump-like suit) is still not modeled per se — see "Known limitations" item 1 in the July 12 fix package (fragile no-trump doubles hands over-bid; per-tile summation can't see set-risk) and item 2 (opening-control value not yet modeled) for the two specific successor gaps, both explicitly flagged as first targets for a future capabilities-layer, not this pass.
2. ~~**No partner-trust term.**~~ **Addressed indirectly, July 12, 2026.** Fix #2 (counter realization inclusion) and the trump-majority fix move several previously-cold real hands into bid territory — see the verification table in `Texas_42_Session_Summary_July_12_2026_BiddingFixPackage.md` (candidate agrees with the human on 10/11 decided real hands, vs. 0/20 before). Whether a dedicated partner-trust *term* is still needed on top of this, versus this package having absorbed most of that gap's practical effect, is open pending more played-out hands.
3. **Fixed go/no-go threshold across difficulty.** Still true, still untouched. Personality currently only shifts the *inputs* to the final score, never the 28.0 bar itself — explicitly out of scope for the July 12 package ("The 28.0 threshold — untouched by standing decision").
4. **Two different weights on the same personality knob** (`risk_bias * 3.0` vs `* 4.0`) between the target-bid formula and the go/no-go formula — still unresolved, untouched by the July 12 package.
5. **A dead stance value (`"anchor"`)** is initialized but structurally unreachable given the current if/elif chain — still flagged for later, explicitly out of scope for the July 12 package.

---

*Document originally reflected code state as of the session it was written. The July 12, 2026 update note at the top and the inline corrections above bring §2.3-2.5, §3.1(B), §3.2, and §6 up to date; §1, §2.1, §2.2, §3.1(A)/(C), §3.3-3.4, §4, and §5 are unchanged and still accurate.*
