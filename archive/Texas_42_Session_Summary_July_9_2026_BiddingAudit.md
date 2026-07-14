# Texas 42 — Session Summary (July 9, 2026)
## Topic: AI Bidding Under-Frequency Investigation

### Starting point

Attempted to run a full branch-style trace of `decide_bid()`, mirroring the `decide_play()` branch audit format. Got three decision points in (auction stance classification, should-bid threshold, target-bid formula) before the format broke down — Katy flagged the real, live problem: AI players are passing on the large majority of dealt hands across all three difficulty tiers, regularly forcing the human into weak opening bids even when an AI partner holds something biddable. This is a calibration problem, not a branch-logic problem, so the trace format was set aside in favor of a different method.

### Method that replaced the trace

Produced a full descriptive document (`Texas_42_AI_Bidding_Structure_Overview.md`) covering Layer 1 (evaluation), Layer 2 (scoring/threshold), Layer 3 (legality), current settings, and open questions — shared with an outside consultant (GPT) for a second opinion.

GPT's independent read converged on the same core hypothesis already suspected: the evaluator answers "can I personally capture enough tricks" rather than "can my side make the bid," and flagged the discarded `counter_points`/`realization_bias` fields as suspicious. GPT also cautioned against touching the 28.0 threshold before fixing the underlying evaluator, which matches the project's standing "surgical, minimal changes" principle — noted as correct and left alone.

From there, the work shifted to pulling real hands from `bid_decisions` logs (already-instrumented, no new tooling needed) and hand-verifying the per-domino math against what a real player would expect from the same hand. This is the same table-scenario-narration method used throughout the project, just fed by logged hands instead of hypothetical ones.

### Confirmed findings (each traced to exact code lines, not theory)

**1. Isolated strong off-suit dominoes score zero.**
`evaluate_hand()`'s off-suit scoring only credits a high domino if it's paired with another in the same suit (2+) or independently very high (rank ≥5). A domino like a lone 4:6 — decent rank, but alone in its suit — contributes exactly 0.0 expected tricks. Confirmed via hand-traced example (Player 1, `Session_Summary` conversation): a 4-trump hand with double trump and this exact pattern evaluated to 2.92 tricks / 17.5 points where the hand-feel suggested closer to 3.6–4.0 tricks.

**2. `counter_points` / `realization_bias` are computed accurately and then discarded.**
Confirmed via a hand holding both 10-count dominoes (5:5 as double trump, plus 4:6) — the two most valuable tiles in the deck. The model correctly computed `counter_points=15.0` and `realization_bias=6.71` (both far above any other logged hand), reflecting genuine, high-confidence counter-capture potential. None of that reached `estimated_points` (17.4) — the hand evaluated worse than a hand with `counter_points=1.5` three seats over. Per existing project notes, this exclusion was deliberate (reserved for an unbuilt Phase 2 risk axis), not an oversight — but this hand is a concrete case for pulling that work forward rather than leaving it parked indefinitely.

**3. Trump-suit majority control is undervalued relative to its real structural power.**
Confirmed via a played-out hand: Player 1 held 5 of 7 dominoes in trump (missing only the double), evaluated at 3.58 tricks / 21.5 points — below bidding threshold, only bid because forced. The actual play-out: player 1's side held 6 of 7 trump total; the opponents' only trump (the double) was spent in trick 1, after which player 1 was completely uncontested. Final result: 36–6. The current model treats trump_count ≥5 as one more small linear step (+1.0 flat bonus) rather than recognizing that holding a majority of the suit is a qualitatively different, near-guaranteed-control situation, not just "a bit more likely to win tricks."

### Explicitly not yet resolved

- **World A / World B question (from GPT's follow-up, agreed as a useful distinction):** none of the three findings above prove that a partner-trust term is *necessary* — only that it's currently *absent*. It's possible a correctly calibrated Layer 1 (with all three findings addressed) produces human-feeling bidding frequency on its own, without ever needing a "my partner probably covers me" signal. Only a hand where Layer 1's evaluation is already accurate, and a human would still only bid because of assumed partner support, would settle this. No such hand has been found yet — worth specifically watching for going forward.
- **What value a lone strong off-suit domino should actually receive** is explicitly not decided. GPT's caution against a flat "singleton highs = 0.4" fix was noted as reasonable — the true value likely depends on factors the model can't currently see (whether trump gets drawn, whether partner has already forced that suit), which ties back to Phase 4 (`PublicKnowledge`/void-tracking) rather than being a pure Layer 1 evaluation fix. Parallel in shape to the still-open `BUG-007` question.
- **No specs have been written yet** for any of the three findings. Per Katy's explicit call at end of session, next step is to keep gathering hands looking for genuinely new patterns (not repeats of these three) before shaping any of this into a spec.

### Threads intentionally not touched this session

- `Bid.is_valid()` legality rules — flagged at the start as a different kind of check (deterministic rule enforcement, not judgment), set aside.
- The known gap that `decide_bid()` never opens special contracts (Nello/Sevens/Plunge/Splash) despite `eligible_contracts()` already existing — reconfirmed as out of scope, per its own standing parked status.
- The dead `"anchor"` auction-stance value — parked pending more clarity on how the underlying evaluation numbers are derived (Katy's call, session's first decision point).

### Suggested next session entry point

Continue hand-gathering from `bid_decisions` logs, specifically screening for:
- A hand testing the World A/B question (accurate Layer 1 eval, human would still only bid on partner-trust grounds)
- Any pattern that isn't one of the three findings above

Once a few more genuinely new (or confirming/repeating) hands are in, move to shaping findings #1–#3 into spec-ready form — likely as local, additive changes to `evaluate_hand()`'s off-suit scoring and/or a Layer 2 term drawing on `realization_bias`, rather than any change to the 28.0 threshold or the tricks→points conversion (both explicitly ruled out as the wrong place to intervene).
