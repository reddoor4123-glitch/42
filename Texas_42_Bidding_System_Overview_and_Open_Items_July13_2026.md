# Texas 42 AI Bidding System — Overview & Open Items
**Prepared July 13, 2026**

This document explains how the AI bidding system currently works, in enough
detail for someone unfamiliar with the codebase to reason about it, and
consolidates every open issue currently on record — including one new
finding from today, confirmed against the live evaluation code.

---

## 1. Context: what "bidding" means here

In Texas 42, before play begins, players bid for the right to name trump
and lead the hand. Whoever bids highest commits their team to reaching that
many points (out of 42 total per hand); if they fail, the bidding team is
"set" and the points go to the other side regardless of who actually won
tricks. Naming the right trump suit and bidding the right amount are both
high-stakes judgment calls — bid too low and you leave value on the table
or lose the bid to an opponent; bid too high and you set your own team.

The AI's bidding logic lives in `ai_player.gd` (the authoritative,
in-engine version) and is mirrored in a standalone Python file,
`harness.py`, used to test proposed formula changes against real hands
before they're ported into the actual game.

---

## 2. Architecture — three layers, cleanly separated

The system is deliberately split into three layers that don't talk back to
each other out of order:

- **Layer 1 — Hand Evaluation** (`evaluate_hand`, `best_trump`): "objective
  truth" about a hand's strength. Nothing downstream is allowed to
  re-derive hand strength — only react to what this layer already
  computed.
- **Layer 2 — Signal Combiner** (`decide_bid`'s scoring section): combines
  Layer 1's output with personality/risk parameters into a single
  bid/no-bid decision and a target bid amount.
- **Layer 3 — Execution** (auction legality): enforces table rules
  (minimum bids, raise increments, forced-bid rules) — it does not
  re-score the hand.

### 2.1 Layer 1 — `evaluate_hand(hand, trump)`

Given a hand and a candidate trump suit, this function splits the hand
into trump tiles and off-suit tiles and scores each group.

**Trump tiles** — each contributes an individual win probability based on
its rank within the suit:
```
if domino is the double:  win_prob = 0.95
else:                      win_prob = 0.35 + (rank / 6.0) * 0.50
```
So the weakest trump contributes 0.35 of an expected trick; the strongest
non-double trump contributes 0.85; the double contributes 0.95. These sum
into `estimated_tricks`.

**Off-suit tiles** — split into non-double and double groups, scored
differently:
- Non-double off-suit tiles score by rank tier (0, 0.2, 0.3, or 0.4
  depending on rank and how many tiles share that suit).
- Off-suit doubles are scored as a group: each contributes a rank-scaled
  base (`0.45 + (pip/6) × 0.25`), **plus a compounding bonus for each
  additional off-suit double held** (`+0.3` for the 2nd, `+0.5` for the
  3rd, `+0.7` for the 4th), plus a further `+0.2` if the hand holds both
  4:4 and 6:6 (a well-known pattern — those two doubles between them trap
  the 6:4 ten-count).

**Capture conversion:**
```
expected_capture = estimated_tricks * 6.0
```
Every trick is worth a flat 6 points on average (42 points / 7 tricks),
regardless of which specific dominoes are actually in play.

**Counter realization** (added July 12, 2026): counter tiles (pip_sum 5 or
10 — worth 5 or 10 points if won) get their own win-probability estimate
based on rank/trump status, compared against the hand's baseline trick
share. This produces `realization_bias`, which is now fully folded into
`estimated_points` (previously computed but discarded).

```
estimated_points = expected_capture + realization_bias
```

### 2.2 Trump suit selection — `best_trump(hand)`

Tries all 7 possible trump suits, scores the hand under each via
`evaluate_hand()`, and picks whichever produces the highest score:

```
score = estimated_points + trump_count * 2.0
if has_double_trump: score += 3.0
```

**This is a separate, simpler formula from Layer 2's final scoring** (see
2.3) — it does not include Layer 2's trump-count control bonuses. This
split is worth flagging on its own: suit *selection* and bid *strength*
are evaluated with two different formulas, which can disagree with each
other (see §4, today's finding).

### 2.3 Layer 2 — `decide_bid()`'s scoring section

Combines three independent signals, all additive, into one final score:

```
final_score = ev_score + control_score + stance_bias
should_bid = final_score >= 28.0
```

- **EV signal:** `ev_score = estimated_points + risk_bias * 4.0`
- **Control signal:** structural confidence — `estimated_tricks * 6.0 *
  0.12`, plus flat bonuses: `+2.5` if holding the trump double, `+1.5` at
  4+ trump, `+3.0` at 5+ trump, `+2.0` at 6+ trump (stacking).
- **Auction stance** — classifies the hand into one of four shapes, each
  with a fixed bias added to both the go/no-go score and the target bid:

  | Stance | Condition | Bias |
  |---|---|---|
  | `pressure_opener` | est_tricks ≥ 4.3 **and** holds the double | +2.0 |
  | `solid_opener` | est_tricks ≥ 4.0 **and** trump_count ≥ 4 | +1.0 |
  | `competitive` | ev_score ≥ 24.0 | 0.0 |
  | `defensive` | none of the above | −1.5 |

**Target bid amount** (separate from whether to bid at all):
```
target_bid = round(estimated_points + risk_bias * 3.0 + stance_bias)
target_bid = max(28, target_bid)
target_bid = min(target_bid, round(estimated_points) + max_overbid)
```

### 2.4 Personality (`AI_MODES`)

| Difficulty | `risk_bias` | `max_overbid` |
|---|---|---|
| beginner | −0.25 | 2 |
| standard | 0.0 | 4 |
| expert | +0.25 | 6 |

(`AI_MODES` also carries `vigilance`/`opportunism` keys, but those are
play-side only — consumed by `decide_play()`, not by any of the bidding
logic described here.)

### 2.5 Layer 3 — Execution

Enforces table legality only: respects the current high bid, legal raise
increments, forced-bid rules (must bid ≥30 if everyone else passed and the
ruleset requires it), and the `max_overbid` cap. Does not re-evaluate hand
strength.

---

## 3. Verification tooling — `harness.py`

A standalone Python mirror of the GDScript math, used to test proposed
formula changes against real hands before touching the actual game code.
It supports a `candidate` flag intended to distinguish "what's live today"
from "a proposed change being tested."

**Note as of today:** the harness's `candidate=False` ("current") branch
had drifted — it still reflected the pre-July-12 formula, before Fixes #1
and #4 shipped for real into `ai_player.gd`. A fix spec for this has been
written (`Harness_Fix_Spec_StaleCurrentBranch.md`) — until applied, anyone
using the harness's "current" mode is testing against stale behavior.

---

## 4. NEW — Trump suit selection can penalize choosing a hand's own strongest double as trump

**Found today, July 13, 2026, verified against `harness.py` (post-fix
formula, matching live `ai_player.gd` behavior).**

**Test hand:** 6:5, 4:4, 5:5, 6:2, 4:2, 3:3, 0:0 — four doubles out of
seven tiles.

Both candidate trump suits 2 and 5 offer exactly 2 trump tiles. Suit 5
additionally includes the double (5:5, a 10-count) — structurally the
stronger choice: guaranteed control of the suit, plus a secured 10 points.
The engine chose suit 2 anyway. Confirmed scores:

| Candidate trump | trump_count | has_double | estimated_tricks | estimated_points | selection score |
|---|---|---|---|---|---|
| suit 2 | 2 | No | 5.633 | 33.80 | **37.80** |
| suit 5 | 2 | Yes | 4.242 | 25.45 | 32.45 |

**Root cause:** the off-suit-doubles compounding bonus (§2.1) rewards
*how many doubles are held off-suit together*, independent of which suit
ends up as trump. Promoting 5:5 into trump shrinks the off-suit-doubles
group from 4 tiles down to 3, which drops the compounding bonus's top tier
entirely:

| | off-suit doubles | base sum | compounding bonus | total |
|---|---|---|---|---|
| trump = 2 | 4:4, 5:5, 3:3, 0:0 | 2.300 | 1.500 | **3.800** |
| trump = 5 | 4:4, 3:3, 0:0 | 1.642 | 0.800 | **2.442** |

The formula never accounts for the fact that one of those doubles could
instead be spent as the boss of trump — strictly better than probabilistic
off-suit credit, since it guarantees control of the entire suit rather
than just contributing to a group bonus.

**Why this matters in the specific flagged hand:** with 5:5 (a 10-count)
as trump, the correct table technique is available — pull trump with the
double (unbeatable), draw out the rest of the suit with 6:5, then run the
three remaining doubles (4:4, 3:3, 0:0) as bosses of their own suits. The
engine's chosen suit (2) forfeits this line entirely — the hand holds
neither 2:2 nor any special standing in that suit, just two ordinary trump
tiles.

**Structural implication, not just a one-hand fluke:** the more doubles a
hand holds, the more this formula penalizes choosing any one of those
doubles' suits as trump — backwards from real technique, since a
doubles-heavy hand is exactly when holding the boss of trump matters most.

**Status:** confirmed, reproducible, not yet spec'd. Recommend gathering
1-2 more example hands with this same shape (multiple doubles, one
candidate trump suit including a double vs. another that doesn't) before
finalizing a fix — per this project's established practice of not
speccing a bidding-evaluator change off a single hand.

---

## 5. Consolidated open items

### Confirmed still open (verified against live code today)

1. **Fixed 28.0 go/no-go threshold, uniform across all difficulties.**
   `risk_bias` shifts the inputs to `final_score`; the 28.0 bar itself
   never moves. Whether difficulty should also flex the bar itself is an
   open design question, not yet addressed.

2. **Same personality knob (`risk_bias`), two different weights.** The
   go/no-go formula uses `risk_bias * 4.0`; the target-bid formula uses
   `risk_bias * 3.0`. Unclear if this divergence is intentional.

3. **Dead `"anchor"` auction-stance value.** `auction_stance` initializes
   to `"anchor"`, but the following if/elif/else chain has no branch that
   can ever land back on it — structurally unreachable. Cosmetic/logging
   impact only, but worth either wiring a real case for it or removing it.

4. **Whether a dedicated partner-trust term is still needed** — the "World
   A / World B" question from the July 9, 2026 audit (carried forward here
   since that source doc is now archived): World A is a correctly-calibrated
   Layer 1 alone producing human-feeling bidding frequency with no
   partner-trust signal at all; World B is that such a signal turns out to
   be genuinely necessary. The July 12 fix package (counter realization +
   trump-majority scoring) closed most of the practical gap this was meant
   to cover — candidate matched real human bidding decisions on 10/11
   hands, versus 0/20 before the fix — but no hand has yet settled A vs. B
   either way. Only a hand where Layer 1's evaluation is already accurate
   and a human would still only bid on assumed partner support would
   settle this; not resolvable by code inspection alone.

5. **Set-risk in fragile no-trump-doubles hands, and unmodeled
   opening-control value.** Both logged as known limitations of the July
   12 fix package, and both flagged as first targets for a future
   "capabilities layer" (structured concepts like trump dominance,
   reliable-vs-hopeful winners, set-risk) rather than another round of
   flat per-tile tuning.

6. **NEW (today) — trump selection penalizes promoting a hand's own
   double to trump when other doubles are held.** See §4 above.

7. **Follow Me dead code** (carried forward from the now-archived Jul 1/2
   and RankingUnification session docs, still unresolved as of July 14,
   2026). The ratified convention is Follow Me = trump `-1` in the trump
   panel, but `Bid.Type.FOLLOW_ME` still carries full validation/scoring
   machinery in `bid.gd`, unreachable from `eligible_contracts()`. Needs
   one explicit decision — amend the convention to route through
   `Bid.Type.FOLLOW_ME` for real, or delete the dead branches — never made.
   The July 12 Settings/Toggle audit removed Low-No but didn't touch this.
   Small, bounded, not urgent.

### Resolved — safe to retire from tracking

- Off-suit sequential runs scoring zero — substantially addressed by
  Fixes #1 (singleton rank-4 tiles) and #4 (rank-scaled, compounding
  off-suit doubles).
- Counter value computed but discarded (`realization_bias`) — fixed
  July 12; now fully folded into `estimated_points`.
- Marks bid gate sequencing and missing off-suit-viability check — fixed
  July 5.

---

## 6. Suggested next steps

- Apply the `harness.py` stale-branch fix (spec already written) so
  future tuning work isn't accidentally validated against outdated
  behavior.
- Gather 1-2 more hands matching today's new finding's shape before
  speccing a fix — likely candidates: any hand where two candidate trump
  suits tie or nearly tie on `trump_count`, and only one of them includes
  a double the hand holds.
- Items 1-3 above (threshold, weight mismatch, dead stance value) are
  small, mechanical, and don't require more hand-gathering — they could
  be picked up independently whenever convenient.
- Item 4 (partner-trust term) and item 5 (capabilities layer) both remain
  correctly gated on more played-out hands / design conversation, per
  standing project practice — not ready to spec yet.
