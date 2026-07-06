# Addendum to AI_Play_Behavior_Bug_Log.md — Pattern D

*New pattern, new entry. Append directly below the existing Pattern C
section, before the "Summary — suggested order of attack" list (that list
should get a new line item for BUG-005 once this is merged in).*

---

## Pattern D — `trust_gate` is gated on the wrong fact, and its fallback and reason string each describe a different decision than the one that's actually needed

### ⚑ BUG-005 — Partner's hold-vs-commit decision on a trump-only win is currently keyed to turn order, not to any of the factors that actually matter

**File:** `ai_player.gd`, `decide_play()`, branch #16 in `Phase3_Objective_Audit.md`'s table (partner following, trump-only can-win, standard difficulty — inside `SECURE_FOR_PARTNER`)

**Current code:**
```gdscript
if difficulty == "expert":
    # Expert Partner: no trust rule — play optimally for the contract.
    ...
var human_play = _find_player_play(plays, partner_id)
var is_last_player = (plays.size() == 3)
if human_play != null and not is_last_player:
    var safe_discard = legal.filter(...)
    if safe_discard.size() > 0:
        reason_log.append("Saving my trump — there's still a chance someone else covers.")
        return discard
# Last player or no safe discard — trump in to secure the trick.
```

**This is not one bug — it's three separate mismatches stacked on the same branch, surfaced through a design conversation, not through code inspection alone:**

**1. The gating condition tests a fact that never matters to the actual decision.** `human_play != null` checks whether the human (partner) has already played this trick. But with 4 players in fixed partnerships, once the partner has played, they cannot act again in that same trick — so a partner who has already acted is not meaningfully part of any remaining "coverage" decision in that trick. The condition is about turn-order state; the reasoning it's paired with is about coverage possibility — the two are already incompatible without needing a stronger claim than that. Confirmed directly against a concrete table scenario (Katy, this session): the actual factors a real partner weighs at this decision point are contract margin (can the team afford to concede the trick), counter status (is the specific risk-counter already accounted for), and lead economy (does winning force a bad lead next trick) — turn order/who's-already-played never entered the reasoning at all.

**2. The forced-commit fallback is also wrong, not just the gate.** When the gate doesn't fire (no safe discard, or last-to-act), the code forces a win unconditionally: *"Last player or no safe discard — trump in to secure the trick."* The fallback collapses every remaining case into forced commit, instead of re-evaluating based on contract margin and lead economy — confirmed this session that a partner should still be able to decline a winning trump play purely on contract margin, even with nobody left to act at all. Being last doesn't remove the decision; it just removes the "someone else might act" question, which per (1) was never the right question anyway.

**3. The reason string describes a mechanism ("someone else covers") that is separate from, and in this session's analysis more likely wrong than, what the branch should actually be evaluating.** This is not a wording issue for `AI_Explanation_Bug_Log.md` — the reason string encodes an incorrect belief model, not just a poorly phrased correct one.

**Unifying root cause, not three unrelated symptoms:** all three mismatches above trace back to the same conceptual error — the branch is keyed to *turn-order state* (has the human played yet, am I last to act) when it should be keyed to *tactical evaluation state* (contract margin, counter status, lead economy). The gate condition, the fallback, and the reason string are all downstream expressions of that one wrong axis, not three independent defects that happen to share a branch. Any fix should replace the axis, not patch each symptom separately.

**What the decision should probably evaluate instead (confirmed via direct table-scenario walkthroughs, not yet specced):**
- Contract margin — can the team's current position absorb conceding this trick.
- Counter status — is the suit's risk-counter already played/void-eliminated (`PublicKnowledge.has_been_played()` / `is_void_in()` can answer this deterministically; no hidden-information inference required).
- Lead economy — if this AI wins, is the resulting forced lead next trick good or bad, evaluable from its own hand and what's already been played.

**Explicitly out of scope for a first pass (Katy, this session):** "slide the trick to a partner positioned to win a future trick" — this requires reasoning about tricks that haven't happened yet and was agreed to be more speculative than the rest. Flagged here so it isn't silently lost, not because it should be built now.

**Update — canonical home found:** this concept (declining a guaranteed win to hand lead control to a better-positioned teammate) was independently rediscovered during the Phase 1 resolution session and is now tracked as the parked concept in `Phase1_Control_Layer_Audit.md`. That document, not this one, is the concept's canonical home going forward.

**Why this belongs in the bug log rather than staying a design note:** the mismatch between condition, fallback, and reason string was found and confirmed against real code, not just discussed in the abstract — it meets the same bar as BUG-003/004 (a demonstrable gap between what the code does and what it should do), it's just that the "should do" side needed a real player's table reasoning to pin down rather than a replay trace.

**Status:** ✓ Fixed (July 5, 2026). Specced in `BUG-005_Fix_Spec.md`, implemented in `ai_player.gd`,
and playtest-confirmed working. The three deterministic factors (contract margin, live-counter
status via `_live_counter_for_suit()`, lead economy) replace the turn-order gate, fallback, and
reason string described above — all three original mismatches are resolved together, matching
the "unifying root cause, not three unrelated symptoms" diagnosis. Originally marked ⚑; upgrading
to ✓ per the housekeeping note in `Texas_42_Session_Summary_July_5_2026_Phase2Architecture.md`.
This standalone addendum has not yet been merged into `AI_Play_Behavior_Bug_Log.md` proper — that
merge is still an open housekeeping item, tracked there, not done as part of this status update.

**Relationship to Phase 2 architecture work:** this branch was originally the primary source example for `trust_threshold` as a candidate `AI_MODES` Commitment-gate parameter (see `Phase2_Control_Layer_Audit.md`). That candidate parameter's *shape* (a scalar gating a fallback) is unaffected by this finding, but its *signal* can no longer be "some measure of trust in a partner" — there is no partner-trust content anywhere in the corrected version. If this gets rebuilt as a Commitment gate, the scalar it thresholds should be built from the three factors above, not from anything resembling the current turn-order check.
