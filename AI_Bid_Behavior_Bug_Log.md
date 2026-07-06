# AI Bid Behavior Observation Log — Reorganized

**Status key:** ✓ Already fixed in current code | → Live bug, ready to spec | ⚑ Needs a design decision first | ○ Not a bug — logged design boundary

---

## Pattern A — ✓ Marks bid gate: two separate defects in the same code block (Fixed July 5, 2026)

**File:** `ai_player.gd`, lines 266–282 (`decide_bid()`, points-branch return + marks-branch fallback)

Entries 1, 3, and 7 all point at the same seven lines, but they expose **two different problems**, and the order you fix them in matters — fixing one without the other makes things worse, not better.

```gdscript
if should_bid and points_still_legal:
    if min_points <= target_bid:
        ...
        return pts_bid              # ← exits here whenever should_bid is true

# Marks bid — strong hand requirement (unchanged)
if trump_count >= 5 and eval["has_double_trump"] and \
   (current_high == null or current_high.type != BidScript.Type.MARKS):
    ...
    return marks_bid                 # ← only reached when should_bid was false
```

**Defect 1 — Marks is a fallback, not a competing option (Entries 1, 3).**
Whenever `should_bid` is true, the function returns a points bid before the marks check is ever evaluated. Marks can currently only be bid on hands the AI *wouldn't* bid points on — meaning strong, confident hands (the kind that actually warrant marks) can never reach the marks branch at all.
- Entry 1: 5 trumps + double, `should_bid=true` → bid 32 points on a hand that swept all 7 tricks.
- Entry 3: 5 trumps + double + two trump counters, `should_bid=true` → bid 30 (floor) instead.

**Defect 2 — When marks *is* reached, its gate is incomplete (Entry 7).**
The marks check only looks at trump shape: `trump_count >= 5 and has_double_trump`. It has no way to see whether the off-suit tiles are safe. Entry 7 is the case where `should_bid` happened to be false, so marks *was* reached — and fired on a hand with strong trump but two exposed off-suit singletons and a live uncontrolled counter. The team was set.

**Why sequencing matters:** If you fix Defect 1 alone (promote the marks check to run before the points return) without also fixing Defect 2 (tightening what marks requires), you'd increase the number of hands reaching the marks branch — which means *more* Entry-7-style bad marks bids, not fewer. Defect 2 needs to be tightened first, or fixed in the same pass as Defect 1.

**Fix shape (per Entry 7's analysis):** Marks should require trump control *and* off-suit viability, not trump shape alone. Candidate second condition: at least one off-suit double, or a counter already secured in-suit, or near-complete trump control (trump_count >= 6) as an alternative path. This needs one more round of examples to pin down the exact threshold before speccing — flagging as ⚑ rather than →.

**Fix priority:** High — Entry 7 is a confirmed loss, not just a feel issue.

**✓ Fixed (July 5, 2026).** Both defects closed in one pass: the marks check now runs before the points-branch return (Defect 1), and gains an off-suit viability condition — an off-suit double, or trump_count >= 6 as an alternative path (Defect 2). Katy's calls: off-suit double and the trump_count >= 6 path; "counter already secured in-suit" was not adopted as a gating condition. Status changed → to ✓ for both defects.

---

## Pattern B — Trump rank blindness — appears to already be fixed

Entries 2, 4, 5, and 6 all trace back to the same root cause: `evaluate_hand()` scoring trump dominoes by count alone, blind to rank, so a hand of the top three trumps scored identically to the bottom three. This is exactly **Fix C** from your session notes — the flat rate was replaced with `win_prob = 0.35 + (rank/6.0) * 0.50` (0.95 for the double), already active in the current file (lines 78–85).

I recomputed the hands from these entries against the current formula by hand (not by running the actual game):

- **Entry 5** (three top blanks + two off-suit doubles): the old flat model gave every 3-trump holding the same `est_tricks=2.70` regardless of rank. Fix C's whole purpose is to break that tie — the current formula is exactly the fix Entry 5 is asking for.
- **Entry 6** (four top threes + double): recomputing with the current formula gives `est_tricks ≈ 4.05` — which now clears the `4.0` threshold for `solid_opener` stance. Under the *old* flat formula it landed at 3.75, one quarter-trick short, which is what dragged the whole hand into `defensive` stance and a floor bid. With Fix C active, that miscalculation shouldn't reproduce.
- **Entry 4** (off-suit accidental bonus picking the wrong trump suit): I recomputed both candidate suits under Fix C — suit=1 (the correct choice, top two trumps in suit) now scores marginally *higher* than suit=5 (the accidental pick), reversing the original bad outcome.
- **Entry 2** (beginner hand, top three sixes): same mechanism, same fix — evaluation is shared across difficulty levels, so this resolves at all three tiers at once.

**Status:** ✓ Likely resolved already. I'd treat this as **needs verification, not a new fix** — rerun these four exact hands through the current build and confirm the bid/stance output matches what Fix C should now produce, then close these four entries out. I'm reasonably confident in the recompute but haven't executed the actual code, so don't take this as a substitute for testing.

---

## Notes logged but not bugs (○)

**Entry 3 — "floor bid, not a confident bid."**
When `should_bid` is true but the computed `target_bid` lands below the legal minimum (e.g. 29 when 30 is required), the code mechanically bumps it to the floor. This is correct bidding logic — you can't legally bid below the minimum — the entry is really about *tone*: a hand that deserves confidence ends up looking identical to a marginal hand that just barely qualified. That's an explanation/presentation concern (same family as the string-flatness issues in `AI_Explanation_Bug_Log.md`), not a decision-logic bug. Worth a note for whenever bid explanation strings get their own pass, not a fix to `decide_bid()` itself.

**Entry 3 — "counter value is visible but ignored."**
`realization_bias` / `counter_points` are explicitly computed as diagnostic-only signals and deliberately excluded from `estimated_points` — the code comments say so directly, and your session notes tie this to the still-unbuilt Phase 2 risk axis. This is a scoped future feature, not an oversight. No action needed until Phase 2 risk is speced.

---

## Summary — suggested order of attack

1. **Verify Pattern B is actually closed** — rerun Entries 2, 4, 5, 6 against current code. If confirmed, that's four entries closed with zero new work.
2. ~~**Spec Pattern A as one combined fix**, not two sequential ones — tighten the marks gate's off-suit condition and reorder it ahead of the points return in the same pass, so you don't temporarily widen exposure to Entry-7-style bad marks bids in between.~~ **✓ Fixed July 5, 2026** — see Pattern A above.
3. Leave the two ○ items logged for later — one belongs with bid-explanation string work, the other is already correctly scoped to Phase 2.
