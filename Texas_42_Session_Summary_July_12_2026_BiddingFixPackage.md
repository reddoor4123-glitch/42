# Texas 42 — Session Summary (July 12, 2026)
## Topic: Bidding Fix Package (#1–#4) — Tuned, Validated, Shipped

### Outcome in one line

All three July 9 bidding findings plus the off-suit doubles fix were tuned
as a single package against real hands, spec'd, implemented by Claude Code,
and verified in-game — the "AI passes on ~90% of hands" problem is
addressed, with known limitations logged.

### Session-start note (process learning)

The session opened with a memory-lag failure: Claude did not recognize the
already-approved off-suit doubles spec (finding #4) when Katy pasted it,
because Claude's cross-session memory had not yet caught up to that design
session. Standing practice going forward: **treat Claude's memory as
lagging by default at session start; pasting recent specs/decisions in
(as Katy did) is the correct move**, and Claude should verify against
pasted documents before commenting.

### Method: the bidding harness

A Python replica of the full bidding math (Layer 1 `evaluate_hand()`,
trump selection, Layer 2 signal combiner) was built in-session
(`harness.py`, delivered to Katy). It runs any set of hands through both
the current and candidate evaluators side by side, scored against human
verdicts. **After implementation, all five spec spot-check hands matched
the in-game evaluator to within rounding — the harness is now a verified
twin of the game's bidding math**, and should be the first stop for any
future bidding change (including capabilities-layer work) before GDScript
is written. Katy holds the file; adding it to project knowledge would make
it available in future sessions.

Test data used:
- 26 valid synthetic benchmark hands from GPT (10 bid / 9 pass / 7
  borderline). Note: GPT originally supplied 30, but **4 contained
  duplicate tiles (physically impossible hands)** and were discarded —
  the harness now dup-checks all input.
- **20 real in-game hands collected and verdict-labeled by Katy**
  (July 12) — the decisive validation set.

### The shipped package (see `Spec_Bidding_Fixes_1_2_3_4_Tuned_Package.md`)

1. **Fix #1 — lone high off-suit tiles:** new `elif rank >= 4: +0.2` tier
   at the end of the off-suit elif chain. Rank-4 singletons (e.g. lone
   4:6) no longer score 0.0; rank ≤ 3 singletons still do.
2. **Fix #4 — off-suit doubles:** the previously approved doubles spec
   with one tuned amendment: per-double base **0.45 → 0.55** (so 0:0=0.55
   up to 6:6=0.80). Pip scale 0.25, compounding 0.3/0.5/0.7, and the
   4:4+6:6 bracket +0.2 all unchanged from the approved spec.
3. **Fix #3 — trump majority control:** Layer 2 control bonus at 5+ trump
   raised **+1.0 → +3.0**, new additional **+2.0 at 6+**. Mirrored in
   `_log_bid_decision()`.
4. **Fix #2 — counters count:** `estimated_points := expected_capture +
   realization_bias` — full inclusion, no scaling. The Phase-2 parking of
   this term was lifted by design call after Katy pushed back on shipping
   without it (the 5:5-as-trump "guaranteed 11 toward the contract"
   argument). This fix **captured the one benchmark hand dial-tuning
   couldn't reach honestly, and warmed up the borderline hands** —
   previously flagged as a structural gap. Intended side effect: counter
   placement now influences trump selection via `best_trump()` (a 5:5
   hand leans toward calling fives) — correct table behavior.

### Validation results

- Synthetic benchmark: 10/10 bid hands bid, 0/9 pass hands flip.
- **Real hands: current evaluator bid 0 of 20 (including all three of
  Katy's clear bids). Candidate agreed with Katy on 10 of 11 decided
  hands, with 0/8 pass flips** — including a forced bid that actually
  failed in-game (scores 23.4, safely under). Borderline hands spread
  ~16–33 around the 28 threshold instead of sitting uniformly cold.
- Trump selection spot-validated (called fives on the 5:5 hand; called
  suit 1 on the five-double hand — the human's actual winning call).
- In-game verification by Claude Code: all five spec spot-check hands
  matched expected finals to rounding. Implemented and parsing clean.

### Known limitations (logged in spec — accepted, not blockers)

1. **Fragile no-trump doubles hands over-bid** (`6:5 6:6 0:0 2:0 1:1 1:0
   4:1` bids at 31.2; Katy leans pass — "possible to be trump set").
   Per-tile summation cannot see set-risk.
2. **One real bid hand missed by 0.7** (`1:0 5:0 6:6 2:1 2:2 5:2 3:2` at
   27.3) — opening-control value not modeled.
3. **Extreme double counts run hot** (five-double hand scores 42.2 —
   bids correctly, but may inflate target bids). Watch during play; a
   compounding cap is the likely remedy.

### New design direction opened: the capabilities layer

Katy proposed (and the real-hand misses independently support) an
intermediate descriptor layer: cards → capabilities (trump dominance,
reliable winners vs. hopeful ones, recovery/entries, opening momentum,
partner dependence, variance) → bid decision — rather than compressing
all intuition into one per-tile sum. Assessment: philosophically
continuous with the existing describe/decide architecture
(PublicKnowledge principle); Layer 2's `control_score`, stance system,
and `realization_bias` are its embryos. Agreed approach: **evolution,
not rip-out** — prototype descriptors one at a time in the harness,
tested against the 20-real-hand library plus benchmark, before any
GDScript. First two targets are the two limitation classes above:
**set-risk/trump control** and **reliable-vs-hopeful winners**.

### World A/B question — first real evidence

Two of Katy's real examples (Example 2's successful bid-on-partner's-hand
play-out; Example 4 P0 declining to overbid a partner's rare bid despite
a decent hand) are the first concrete World-B evidence: both are
**auction-context** reasoning, not hand-evaluation. Partner dependence
is a candidate third descriptor, deferred to its own session per the
July 9 note.

### Next session entry points

- Katy playtests the shipped package; flags hands as usual (watch
  especially: overbid targets on double-heavy hands, and any bid on a
  fragile no-trump hand).
- Open the capabilities-layer design session: set-risk descriptor first,
  table-scenario narration before any formula.
- Standing items unchanged: ghost toggle cleanup,
  `allow_small_end_opening_lead` spec, all-four-play Nello,
  MARKS/PLUNGE/SPLASH deeper pass, `value_gate` (#25) session, bid
  explanation strings (note: new bid behavior may need new reason
  strings — separate session by convention).
