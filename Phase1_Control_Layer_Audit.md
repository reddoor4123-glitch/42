# Phase 1 Control-Layer Audit (v1, locked)

*Companion to `Phase3_Objective_Audit_REWRITE_July14_2026.md` and `Phase2_Control_Layer_Audit.md`, and successor to
`Phase1_Raw_Concept_Audit.md`. Where the raw audit inventoried every Phase-1-labeled concept as
found, this document is the settled resolution — arrived at the same way Phase 2's was: not by
re-deriving the branch table, but by narrating real table scenarios until the underlying shape
became visible. Nothing in this document required new code except where explicitly noted below.*

*Purpose: this is the permanent reference for what "Phase 1 — Cooperation" actually is, going
forward. Phase 1 is expected to be touched rarely after this — this document exists so that when
it is touched again, the reasoning doesn't have to be redone.*

---

## The core finding

Old Phase 1 — "the partner knows whose side they're on" — has resolved almost entirely into
ordinary Selection, the same outcome Phase 2 reached. The cardinal rule is not a hard invariant
sitting above the pipeline; it's `PROTECT_PARTNER_WIN`, an ordinary Selection objective, confirmed
by direct table-scenario testing (see "How this was resolved," below). BUG-003/003b, the one real
bug identified during this audit, has since been fixed (July 5, 2026 — see below). One open
naming question remains (unchanged from Phase 2), and one genuinely new
concept was found that belongs to neither old Phase 1 nor the Selection/Commitment/Modulation
pipeline — see "The parked concept" below, which is now Phase 1's sole live occupant.

**Correction to a prior locked document:** `Phase2_Control_Layer_Audit.md` states that "Phase 1's
cardinal rule sits above this entire pipeline as a hard invariant... it is not a category the
pipeline resolves into." That claim is now confirmed wrong. The Phase 3 branch table already had
it right — `PROTECT_PARTNER_WIN` is ordinary Selection, geometric, difficulty-invariant, the same
shape as every other objective (see `Phase3_Objective_Audit_REWRITE_July14_2026.md`'s objective
vocabulary; the specific branch numbers this line originally cited — #4/#11/#12 — were v1's
numbering and aren't confirmed to still apply after the July 14, 2026 rewrite). `Phase2_Control_Layer_
Audit.md` should be corrected to remove the "above the pipeline" framing; this document is the
record of why.

---

## How this was resolved

Three scenarios were narrated directly (not abstractly reasoned about) to test whether the
cardinal rule behaves like an invariant or like an ordinary objective with room for variation:

1. **Standard contract, partner already winning, following.** Confirmed: there is no third
   option. If you play higher than necessary you steal the trick from your own partner — the
   opposite of the objective. "Dump if guaranteed (double led), protect if not" is the entire
   decision space, not a partial description of something larger. This closes both cardinal-rule
   sub-cases (`Phase1_Raw_Concept_Audit.md` #1/#2) as fully resolved, ordinary Selection.

   **Amendment (July 11, 2026, BUG-008; fixed July 12/13, 2026):** the paragraph above silently
   assumed at least one legal play stays under the partner's card. `AI_Play_Behavior_Bug_Log.md`'s
   BUG-008 found the case where that assumption fails — every legal play beats the partner's
   winning card, so staying out of the way is structurally impossible. That's a third option this
   finding didn't account for: a forced overtake, which needs its own policy (escalate to a
   guaranteed winner if one is held) rather than falling through to "protect if not" and playing
   lowest-legal regardless. "Dump if guaranteed, protect if not" is the entire decision space only
   when a protect option actually exists — **now implemented, see BUG-008 (✓ fixed) for the shipped
   policy.** The refactor this fix required also surfaced and fixed a separate latent bug
   (BUG-011) in how "guaranteed" itself was being detected — see that entry.

2. **Marks contract, partner already winning, following, trump-only endgame.** This is where it
   got interesting. Under Marks — no counters, no partial value, only "did we lose this trick or
   not" — a real, live decision surfaced: sometimes take the trick from your own already-winning
   partner on purpose, to hold trump control for a future trick, rather than let them win it.
   This is not "protect the trick harder." It's deciding *which teammate should hold the lead*,
   based on tricks that haven't happened yet.

3. **Opponent side.** Confirmed symmetric — opponents protecting their own partner's winning
   trick run the identical objective from the other side of the table. No separate concept; this
   closes `Phase1_Raw_Concept_Audit.md` #14.

Scenario 2 is the one that mattered. It doesn't fit Selection (it doesn't choose an objective from
current geometry — it declines an already-guaranteed one). It doesn't fit Commitment (Commitment
gates decline an objective based on a *current* signal; this decision explicitly reasons about
future tricks). It doesn't fit Modulation (no fixed path is being scored — the winning seat itself
changes). All three categories are, by construction, about the trick in front of you. This
decision isn't.

---

## The parked concept: long-horizon lead-control sequencing ("trick-sacrifice")

**What it is:** Declining a guaranteed trick win — even one your own partner already has locked
up — because a teammate holding the lead into the *next* trick is worth more to the team than
securing this one. Requires reasoning across tricks, not within one.

**This has now been found twice, independently:**

- During the `trust_gate` (BUG-005) fix, explicitly named and set aside: *"slide the trick to a
  partner positioned to win a future trick... more speculative than the rest. Flagged here so it
  isn't silently lost, not because it should be built now."* (`AI_Play_Behavior_Bug_Log_Addendum_
  PatternD.md`)
- During this Phase 1 resolution, via the Marks trump-control example above — arrived at from a
  completely unrelated direction (Marks contract mechanics, not trust/turn-order).

Two independent discoveries converging on the same missing mechanism is a real signal, not a
coincidence. **This is one concept, not two.** From here forward it has one home: this document.

**Why it's parked, not built:** Per Katy's assessment — this is advanced-abstract cooperative
judgment that even strong real-table players wouldn't reliably employ. It's not core to
authentic "Uncle Ed" play at any difficulty currently modeled. Development is not ruled out
permanently, just indefinitely deferred.

**Why it belongs to Phase 1, and why that's actually a better home than its origin suggests:**
old Phase 1 was scoped as the *beginner*-level floor of cooperation (don't steal your partner's
trick). This concept is the opposite end of the same idea — advanced, abstract teamwork judgment,
not table manners. "Cooperation" turns out to be broad enough to hold both the floor and the
ceiling; Phase 1 is a better permanent address for this than either the trust_gate bug log or a
new, unscoped "Phase 5" would have been.

**What "collecting evidence" means going forward:** any future finding that has this shape — a
decision that requires weighing which teammate should hold the lead across tricks, rather than
how to handle the trick currently in play — gets logged here, not re-discovered as new. This
section should be treated as a running list, not a closed one.

---

## Everything else, status as of this resolution

| Item | Resolution |
|---|---|
| Cardinal rule, standard contract (both sub-cases) | ✓ Ordinary Selection (`PROTECT_PARTNER_WIN`). Closed. |
| Cardinal rule, MARKS variant | ✓ Ordinary Selection *for the trick-protection half*. The other half was the parked concept above — not a Marks-specific override at all. |
| Partner leading — `OPEN_SAFE_SUIT`, `PROTECT_COUNTERS_WHILE_LEADING` | ✓ Already ordinary Selection, untouched by this resolution. |
| Partner leading — `CONTROL_TRUMP` (BUG-003/003b) | ✓ Fixed (July 5, 2026). Trump-control check now runs before the safe-off-suit check, with a double-aware threshold (3+ with the double, 4+ otherwise). Unrelated to anything resolved here otherwise. |
| Opponent-mirror of the cardinal rule | ✓ Confirmed symmetric, same objective. Closed. |
| "Sits above the pipeline" claim | ✓ Corrected — see above. `Phase2_Control_Layer_Audit.md` should have that line removed on next edit. |
| `cooperation_bias` naming collision | ✓ Moot, July 12, 2026 — `cooperation_bias` is deleted from `AI_MODES`, and the Expert "no trust rule" branch it collided with is removed entirely (partner runs identical logic at every difficulty now). No naming collision left to track. See `Phase2_Control_Layer_Audit.md`'s Unresolved section (now resolved) and `Spec_Difficulty_Modes_TwoAxis_July12_2026.md`. |
| Reason-string debt (Explanation Bug Log Issues 1, 7) | Unchanged — presentation debt on already-resolved branches, no new complexity introduced by this document. |

**Net effect: Phase 1 is closed as an active work item.** BUG-003/003b is now fixed (July 5, 2026);
the parked concept above remains the only open item, deliberately not being built now. Nothing
here should require revisiting Phase 1 again until a third independent sighting of the
lead-control-sequencing concept shows up.

---

## Housekeeping to apply next time each file is opened

- **`Phase2_Control_Layer_Audit.md`** — remove the "Phase 1's cardinal rule sits above this entire
  pipeline" line; replace with a pointer to this document.
- **`AI_Play_Behavior_Bug_Log_Addendum_PatternD.md`** — leave the original BUG-005 session note
  intact (it's an accurate record of what was and wasn't fixed that session), but add one line
  pointing to this document as the concept's permanent home, so the two write-ups don't drift
  apart if either is edited independently in the future. Suggested addition, placed directly below
  the existing "Explicitly out of scope for a first pass" paragraph:

  > *This concept (declining a guaranteed win to hand lead control to a better-positioned
  > teammate) was independently rediscovered during the Phase 1 resolution session and is now
  > tracked as the parked concept in `Phase1_Control_Layer_Audit.md`. That document, not this one,
  > is the concept's canonical home going forward.*

- **`Texas_42_Documentation_Map.md`** — add this document alongside the
  `Phase3_Objective_Audit_REWRITE_July14_2026.md` / `Phase2_Control_Layer_Audit.md` entries in the
  Tier-1-adjacent lookup table (already done — this document has its own Tier 1 entry as of the
  July 5-6, 2026 map refresh).
