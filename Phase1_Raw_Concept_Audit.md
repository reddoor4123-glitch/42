# Phase 1 Raw Concept Audit

**Purpose of this document:** collect every place in the project where a Phase-1-adjacent
concept (cooperation, cardinal rule, intent, "whose side you're on," partner protection) appears
— in code, comments, bug logs, or design docs — without unifying, renaming, or locking a
classification. That step comes after this document, not inside it. Same method as
`Phase2_Raw_Concept_Audit.md`; this is its Phase 1 counterpart.

Each entry answers: Where / What it looks at / What info it uses / What decision it makes / What
behavior changes / Candidate layer (using the now-locked Selection/Commitment/Modulation model,
where a guess is possible) / Status.

**One difference from the Phase 2 raw audit, worth naming up front:** when the Phase 2 raw audit
was written, Selection/Commitment/Modulation didn't exist yet, so it couldn't tag layers with any
confidence. That model is locked now. So below, where a concept obviously already fits, I've
tagged a *candidate* layer — but candidate only. This document doesn't lock anything; it's here
so the follow-up classification pass has the full inventory in front of it, the same discipline
Phase 2's raw audit held to.

---

## 1. THE cardinal rule — double-led guaranteed win (branch #11)

**Where:** `ai_player.gd`, `decide_play()`, partner-following block. Actual code:
```gdscript
if human_is_winning:
    var winning_domino = _current_winning_domino(...)
    if winning_domino.is_double():
        var counters_to_dump = legal.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
        if counters_to_dump.size() > 0:
            reason_log.append("That double's safe — putting my points on your trick.")
            return chosen
        ...
```
**What it looks at:** `partner_is_winning` (geometry) and `winning_domino.is_double()` (geometry).

**What info it uses:** Public trick state only — no hidden information.

**What decision it makes:** Whether to dump counters into a trick the human is winning (double
led = guaranteed, no risk) vs. protect them (uncertain win).

**Behavior change:** Partner secures maximum points when the win is locked in.

**Candidate layer:** Selection. `Phase3_Objective_Audit.md` already names this `PROTECT_PARTNER_WIN`
and classifies it geometric, difficulty-NONE — same shape as every other Selection objective in
the file.

**Status:** Active code, correct. Originally tracked as "Gap 1" in the July 1/2 session
summaries ("counter-dumping fix") — implemented since.

---

## 2. THE cardinal rule — uncertain win, protect counters (branch #12)

**Where:** Same block, `else` path (not a double).
```gdscript
var non_counters_follow = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
if non_counters_follow.size() > 0:
    reason_log.append("You've got this one — staying out of your way.")
    return lowest
```
**What it looks at:** Same geometry as #1, minus the `is_double()` fact.

**What decision it makes:** Play lowest non-counter; protect all counters since the win isn't
locked yet.

**Candidate layer:** Selection — same objective (`PROTECT_PARTNER_WIN`) as #1, different
geometric sub-case, not a different objective. `Phase3_Objective_Audit.md` table entry #12 says
exactly this ("duplicate pair with #4").

**Status:** Active code, correct.

---

## 3. MARKS variant of the cardinal rule (branch #4)

**Where:** `decide_play()`, MARKS/PLUNGE/SPLASH block.
```gdscript
if is_partner and human_winning_marks:
    var lowest = _lowest_in(legal, ...)
    reason_log.append("You've got it — saving my strength.")
    return lowest
```
**What it looks at:** Same `partner_is_winning` geometry as #1/#2, but under contract-type MARKS.

**What decision it makes:** Always yield lowest — no double-led exception exists here, because
under Marks every trick matters equally (there's no "safe to dump, this one's already secure"
concept the way there is under a points contract).

**Candidate layer:** Selection — `Phase3_Objective_Audit.md` names this the same
`PROTECT_PARTNER_WIN` objective, explicitly flagged **"duplicate of #11 — reimplemented, not
shared."**

**Status:** Active code. The open MARKS question this entry pointed to (#10 below) is now resolved
— see `Phase1_Control_Layer_Audit.md`: this branch (trick-protection under Marks) is ordinary
Selection, closed. The harder half of what #10 was actually asking about turned out to be a
separate, non-Marks-specific concept, now permanently parked there instead.

---

## 4. Partner leading — safe off-suit lead (branch #7)

**Where:** `decide_play()`, `is_partner and is_leading` block, first check.
```gdscript
var off_safe = legal.filter(func(d): return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)
if off_safe.size() > 0:
    reason_log.append("Opening a safe suit for you to follow.")
    return best
```
**What it looks at:** Trump membership and counter status of legal tiles — geometry only.

**What decision it makes:** Give the human a safe suit to follow without burning trump or
exposing a counter.

**Candidate layer:** Selection. Named `OPEN_SAFE_SUIT` in `Phase3_Objective_Audit.md`.

**Status:** Active code, correct, no known issues.

---

## 5. Partner leading — trump control (branch #8)

**Where:** Same block, second check.
```gdscript
var trumps = legal.filter(func(d): return d.is_trump(trump))
if trumps.size() >= 3:
    reason_log.append("I have trump control — drawing out the opponents.")
    return best
```
**What it looks at:** Trump count in hand — geometry only.

**What decision it makes:** Draw out opponents' trump when holding enough to control the suit.

**Behavior change:** Previously unreachable whenever #4 (off-safe) also fired, which was most
hands. Tracked as BUG-003/BUG-003b in `AI_Play_Behavior_Bug_Log.md` — now fixed (July 5, 2026):
this check runs before #4, with a double-aware threshold (3+ trumps with the double, 4+ otherwise).

**Candidate layer:** Selection. Named `CONTROL_TRUMP`. The bug was a sequencing defect within
Selection (branch order), not evidence this concept sits outside Selection.

**Status:** ✓ Fixed (July 5, 2026) — reordered ahead of #7, double-aware threshold resolved the
previously-open judgment call.

---

## 6. Partner leading — counter-safe fallback (branches #9/#10)

**Where:** Same block, remaining checks.
```gdscript
var non_counters_lead = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
if non_counters_lead.size() > 0:
    reason_log.append("Leading strong to set up a good trick for us.")
    return best
...
reason_log.append("Keeping my counts safe — leading what I can.")
return best
```
**What it looks at:** Counter status of remaining legal tiles.

**What decision it makes:** Prefer any non-counter lead over exposing points; forced counter lead
only as last resort.

**Candidate layer:** Selection. Named `PROTECT_COUNTERS_WHILE_LEADING`.

**Status:** Active code, correct, no known issues.

---

## 7. MARKS leading variant (branch #3)

**Where:** MARKS/PLUNGE/SPLASH block, `is_leading`.
```gdscript
if is_leading:
    var best = _highest_in(legal, ...)
    reason_log.append("Going for the trick.")
    return best
```
**What it looks at:** Nothing beyond legality — no trump-count threshold, no counter filtering.

**What decision it makes:** Always lead highest. Stricter than standard `CONTROL_TRUMP` (#8) —
no minimum trump count gates it, because under Marks winning every trick is the only goal and
counters are irrelevant.

**Candidate layer:** Selection, `CONTROL_TRUMP`-adjacent per the Phase 3 table, but unconditional
rather than gated.

**Status:** Active code, correct as far as it's been examined; not flagged as buggy anywhere.

---

## 8. "Cooperation intent is difficulty-invariant" — doctrine header

**Where:** `ai_player.gd`, the permanent doctrine block above `decide_play()`
("DIFFICULTY DIFFERENCES — THE KNOWLEDGE/EVALUATION LITMUS TEST"):
```
# The goal is for different difficulties to arrive at different decisions
# for understandable reasons — not because they run different games.
```
And, per the onboarding doc and July 1/2 summaries, restated specifically for Phase 1: partner
cooperation intent should be identical at every difficulty; only *execution* should vary.

**What it actually claims:** A structural guarantee — that Selection (which objective fires) is
difficulty-invariant for cooperative branches, and only Evaluation/Modulation-level execution
should differ by difficulty.

**Tension, now resolved:** BUG-003 (#5 above) was a live counter-example to this claim as
previously *implemented*, though not as *intended* — trump-control leading is supposed to be
difficulty-invariant Selection, but branch ordering made it unreachable behind a different
objective for every difficulty, not just some. That was a bug, not evidence the doctrine was
wrong, and it's now fixed (July 5, 2026) — the doctrine no longer overstates what the code
guarantees.

**Candidate layer:** N/A — this is a constraint *on* the pipeline (a property Selection is
supposed to have), not an objective, gate, or scalar itself. Doesn't obviously fit any of the
three categories as a "thing," which may mean it's descriptive doctrine rather than a mechanism
— worth deciding whether it needs its own status in the locked model or whether it's just restated
Selection behavior with no separate existence.

**Status:** Doctrine/comment. Was partially contradicted by current code (BUG-003); no longer, as
of the July 5, 2026 fix.

---

## 9. `cooperation_bias` — naming collision with Phase 1 itself

**Where:** `AI_MODES` const, values `"high"` / `"medium"` / `"medium"`. Read in `decide_play()`
and immediately discarded (`@warning_ignore("unused_variable")`), inline-commented `# Phase 3`.

**What it looks at / decides / changes:** Nothing — dead read, already fully covered in
`Phase2_Raw_Concept_Audit.md` entry 3.

**Why it belongs in this document too:** the string is literally named after Phase 1's own
concept ("cooperation"), yet the code comment tags it Phase 3 and every session summary before
the Phase 2 lock called it the Phase 2 placeholder. Three different phase numbers have been
associated with one dead variable at different points, and none of them is Phase 1 — despite the
name. Worth deciding explicitly whether this key should be renamed away from "cooperation"
entirely (to `trust_threshold`, per the standing proposal) specifically *because* leaving it named
`cooperation_bias` invites exactly this confusion with actual Phase 1 concepts like the cardinal
rule.

**Candidate layer:** Commitment, if renamed to `trust_threshold` per the standing proposal
(unchanged from the Phase 2 audit's read).

**Status:** Placeholder, inert. Cross-referenced, not re-litigated here.

---

## 10. MARKS cardinal-rule override — design question, no code beyond #3 (the stub)

**Where:** Design-doc only. Comment in code (above branch #4):
```
# NOTE: The cardinal rule (never steal a trick the human is already winning)
# is preserved here as a safe default. This needs revisit once examples of
# when partner should override it under Marks are collected.
```
Also carried in `Phase2_Control_Layer_Audit.md`'s Unresolved section and
`Texas_42_Next_Session_Prep_July_5_2026.md`'s backlog.

**What it's actually asking:** Should a partner ever contribute more than the strict minimum to
a trick the human is already winning, under a contract where every trick matters? Currently
answered with the same yield-lowest behavior as the standard-contract case (#3 above), carried
over unexamined rather than deliberately designed.

**Reframe worth testing against the locked model:** this was previously discussed as "should we
violate the cardinal rule under Marks" — language that implies Phase 1 has some special immunity
to being questioned. But #3 is already on record as an ordinary (if duplicated) `PROTECT_PARTNER_WIN`
Selection branch. Every other objective already gets its own Marks-specific execution
(`CONTROL_TRUMP` at #7 vs #8, `ESCAPE`'s Marks variant at #6). So the honest version of this
question may just be: *what should `PROTECT_PARTNER_WIN`'s execution look like under Marks* —
same kind of question already answered for three other objectives, not a special Phase 1
carve-out.

**Candidate layer:** Selection (execution variant), not a new category.

**Status:** ✓ Resolved (July 5, 2026), during the Phase 1 resolution session —
see `Phase1_Control_Layer_Audit.md`. What this entry was asking turned out to split in two:
whether `PROTECT_PARTNER_WIN`'s execution needs anything Marks-specific (answered: no, ordinary
Selection, same as the standard case), and a separate, harder concept — declining a guaranteed
win to hand lead control to a better-positioned teammate for a future trick, which isn't actually
Marks-specific either — now permanently parked in that document, deliberately not being built.

---

## 11. "Sits above the pipeline" — a claim about Phase 1, not a mechanism in it

**Where:** `Phase2_Control_Layer_Audit.md`:
> Phase 1's cardinal rule sits **above** this entire pipeline as a hard invariant. It is not a
> category the pipeline resolves into — it can suppress the whole pipeline outright.

**What this actually is:** Not code, not a comment — a design-doc characterization of entries
#1/#2/#3 above, written during the Phase 2 lock session as an aside, not stress-tested against
the branch table the way every other claim in that document was.

**Tension already surfaced (previous conversation turn):** `Phase3_Objective_Audit.md`, written
earlier and equally "locked," already classifies the same code as ordinary Selection
(`PROTECT_PARTNER_WIN`, ranked geometric/NONE, sitting in the same numbered table as every other
objective, including a duplicate pair reference to #4). The two documents disagree about the same
code, and only one of them ran it through the discriminator test.

**Candidate layer:** None as written — this entry exists to flag that a claim about layering,
not a behavior, needs to be reconciled or retracted once the Phase 1 classification pass runs.

**Status:** ✓ Resolved (July 5, 2026), by the Phase 1 classification pass this entry called for.
`Phase1_Control_Layer_Audit.md` confirms the "sits above the pipeline" claim was wrong: the
cardinal rule is ordinary Selection (`PROTECT_PARTNER_WIN`), the same shape as every other
objective — not a hard invariant sitting above the pipeline. `Phase2_Control_Layer_Audit.md` has
been corrected to remove that framing.

---

## 12. Onboarding/roadmap narrative description of Phase 1

**Where:** `Texas_42_Project_Onboarding.md` and the July 1/2 session summaries:
> *What it gives:* The partner knows whose side they're on and acts accordingly. The foundation.
> Without it nothing else matters.

**What this actually maps to in code:** Entries #1–#7 above, plus the doctrine header (#8) — no
code beyond what's already inventoried elsewhere in this document.

**Worth checking during classification:** whether this narrative framing ("the foundation without
which nothing else matters") is doing real architectural work, or whether it's a motivating
story that was true when the four phases were sequenced as build order, and is no longer a claim
about code structure now that Phase 1 turns out to be mostly ordinary Selection content like
Phase 2 was.

**Candidate layer:** N/A — narrative/motivational framing, not a mechanism.

**Status:** Descriptive only; likely needs updating once the classification pass lands, the same
way Phase 2's roadmap language ("Risk/Trust... calibrates how aggressively to act") turned out to
describe Commitment/Modulation rather than a distinct phase.

---

## 13. Reason-string entries tied specifically to cardinal-rule branches

**Where:** `AI_Explanation_Bug_Log.md`.

- **Issue 1** (→, open) — forced follow-suit counter protection under the cardinal rule reads as
  a free "discarding low" choice. Misrepresents a forced cooperative cost as an arbitrary one.
- **Issue 3 / Issue 6** (✓, fixed) — partner's tile unexpectedly winning under the
  `human_is_winning` branch now gets a "I've got this one" / "Nice hand!" string instead of the
  stale "staying out of your way."
- **Issue 7** (→, open) — non-counter yield under the cardinal rule reads as flat/generic; parked
  pending void tracking for a richer string.

**What these have in common:** all four sit directly on entries #1–#3 above. None require new
mechanism — they're presentation debt on already-classified Selection branches.

**Candidate layer:** N/A — presentation, not mechanism.

**Status:** → / ✓ mixed, per the explanation bug log. Two still open, both low-complexity once
picked up.

---

## 14. Opponent-side mirror of the cardinal rule (branch #24)

**Where:** `decide_play()`, opponent-following block.
```gdscript
# mirrors #11/#12 for the other team
```
per `Phase3_Objective_Audit.md`'s branch table — opponents protect *their own* partner's winning
trick using the same `PROTECT_PARTNER_WIN` objective and the same geometry, just evaluated from
the opposing team's seats.

**Boundary question this raises:** Phase 1 has always been described (onboarding, session
summaries) as "the human's partner knows whose side they're on" — framed around the human's
partner specifically. But the underlying objective, `PROTECT_PARTNER_WIN`, is symmetric — it
governs *every* seat's loyalty to *their own* partner, human-partnered or not. Is "Phase 1" the
narrow human-partner-facing cardinal rule, or the general team-loyalty objective that happens to
also run for the opposing team? This wasn't a live question when Phase 1 was scoped originally
(the human's partner was the only cooperative behavior anyone cared about getting right first),
but it matters now if `PROTECT_PARTNER_WIN` is going to be classified as one unified Selection
objective rather than a partner-only special case.

**Candidate layer:** Selection — same objective as #1/#2/#3, different seat.

**Status:** ✓ Resolved (July 5, 2026). `Phase1_Control_Layer_Audit.md`'s resolution session tested
this directly: "Confirmed symmetric — opponents protecting their own partner's winning trick run
the identical objective from the other side of the table. No separate concept." `PROTECT_PARTNER_WIN`
is one unified Selection objective covering every seat, not a partner-only special case.

---

## 15. "Trust rule" — named alongside the cardinal rule in early docs, already reclassified

**Where:** July 1/2 session summaries list Phase 1's cardinal rules as: *"never steal partner's
winning trick, try to win for team, trust rule."*

**What this actually is:** The "trust rule" clause refers to `trust_gate` (branch #16), which the
Phase 2/3 work has since firmly classified as **Commitment**, not Phase 1 — and which turned out,
via BUG-005, to not even be about trust at all (turn-order state, not partner-confidence state).

**Why it belongs in this raw audit:** it's a concrete example of the exact drift Katy suspected —
something originally bundled into "Phase 1 cardinal rules" that has already fully migrated out
and been correctly resolved elsewhere. No action needed; listed here only so the historical
Phase-1 scope (as originally written) is fully accounted for, including the part that already
left.

**Candidate layer:** Commitment (already resolved, cross-referenced only).

**Status:** Already reclassified and fixed under Phase 2/3 work. Not live Phase 1 content.

---

## Summary — what's actually left once duplicates and cross-references are set aside

Distinct, still-open Phase 1 items after this inventory:

1. ~~**BUG-003/003b** (#5) — real bug, agreed fix shape, one threshold judgment call outstanding.~~
   **✓ Fixed July 5, 2026** — see #5 above.
2. ~~**MARKS cardinal-rule override** (#10) — design question, needs Katy's example hands,
   reframed above as an ordinary Selection execution-variant question.~~
   **✓ Resolved July 5, 2026** — see #10 above and `Phase1_Control_Layer_Audit.md`.
3. ~~**The "sits above the pipeline" claim** (#11) — needs reconciliation against
   `Phase3_Objective_Audit.md`'s existing classification.~~ **✓ Resolved July 5, 2026** — see #11
   above and `Phase1_Control_Layer_Audit.md`.
4. ~~**The opponent-mirror boundary question** (#14) — newly raised, not previously scoped.~~
   **✓ Resolved July 5, 2026** — see #14 above and `Phase1_Control_Layer_Audit.md`.
5. **Two open reason-string entries** (#13, Issues 1 and 7) — presentation debt, low complexity.
6. ~~**The doctrine header's overstatement relative to BUG-003** (#8) — resolves itself once #5 is
   fixed; no separate action.~~ **✓ Resolved July 5, 2026** — #5 is fixed, see #8 above.

Everything else in the original Phase 1 scope (#1, #2, #3, #4, #6, #7) is already correctly
functioning ordinary Selection content — the same outcome the Phase 2 raw audit reached for most
of its own inventory.
