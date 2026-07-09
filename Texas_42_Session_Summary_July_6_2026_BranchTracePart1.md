# Texas 42 — Session Summary (July 6, 2026): Phase 3 Branch Trace, Part 1 (#1–#11)

*Purpose: consolidate everything produced this session — a full branch-by-branch
trace against `Phase3_Objective_Audit.md`'s table, two code specs, two bug-log
entries, and one prior doc-reconciliation pass — into a single handoff so
nothing gets lost across the several specs generated. Doc-update obligations
below are the authoritative list; the individual specs each mention a subset,
this section is the consolidated version.*

---

## Doc reconciliation (completed earlier this session, in a separate chat)

The MARKS cardinal-rule "open question" tag was stale in three docs
(`Phase3_Objective_Audit.md` branch #4 row, `Phase1_Raw_Concept_Audit.md`
§3/§10, `Phase2_Control_Layer_Audit.md`'s unresolved-items list). Katy ran a
full reconciliation pass; verified clean this session — all three now
correctly point to `Phase1_Control_Layer_Audit.md` as the resolution source,
with the trick-protection half closed and the long-horizon lead-control half
correctly parked there instead. Two adjacent stale claims ("sits above the
pipeline," opponent-mirror symmetry question) were caught and corrected in
the same pass. **No further action needed on this thread.**

---

## Branch trace status (#1–#11 of 28)

Confirmed clean, no action, matches `Phase3_Objective_Audit.md` exactly:
**#1** (SEVENS), **#2** (NELLO), **#3** (MARKS leading — noted as a good
future strategy candidate, sufficient as-is for now), **#4** (MARKS
partner-winning — doc-only, see reconciliation above), **#5/#6** (MARKS
can-win / can't-win), **#9** (partner-leading counter-safe fallback).

Findings requiring specs or bug-log entries, detailed below: **#7, #8, #10,
#11**.

---

## Findings this session

### Branch #8 — low-trump lead to pull the double (✓ IMPLEMENTED July 6, 2026)

`CONTROL_TRUMP` (partner leading) always led highest trump, even when the
partner didn't hold the double — risking it to an opponent's double for no
reason. Real technique: lead low to draw the double out first when you don't
hold it yourself.

**Design decision:** Execution-tier, not a new `AI_MODES` parameter — same
shape as existing beginner branches #13/#17. Beginner keeps naive
always-highest (authentic skill-gap modeling, not an artificial handicap);
standard/expert get the correct low-lead technique when they don't hold the
double.

**Implemented and pushed** — `ai_player.gd`'s `trump_control` branch now
checks `difficulty == "beginner" or holds_double_trump` to decide
highest-vs-lowest, with a distinct reason string ("Leading low trump to
draw out the double first.") for the new low-lead case. All doc-update
items below are also done — see the checklist section.

### Branch #7 → BUG-006 (LOGGED July 6, 2026; fix not yet implemented)

`off_safe` unconditionally filters out counters (5:5, etc.) from safe leads
— even once every trump tile is accounted for (played, or in the AI's own
hand), at which point a counter-double is a guaranteed-safe lead that cashes
points for free. Classified **AVAILABLE** — `count_remaining_trump()`
already exists; fix is arithmetic (`count_remaining_trump() -
own_trump_count_in_hand == 0`), no new query needed.

**Bonus finding:** this same count-based check likely also resolves
BUG-002/002b (previously blocked on "Phase 4 trump exhaustion tracking" as
if it needed new infrastructure) — flagged as a cross-reference, not yet
verified against BUG-002/002b's exact shape.

**Status: this is a bug-log entry, not a code fix — that distinction
matters here.** The entry itself is confirmed added to
`AI_Play_Behavior_Bug_Log.md` (new Pattern E), with the BUG-002/002b
cross-reference in place. The actual `off_safe` fix described above has
**not** been implemented in `ai_player.gd` — still open, tracked in the
log, ready whenever it's picked up.

### Branch #10 → BUG-007 (LOGGED, deliberately deferred)

Same branch family as BUG-006 (forced counter lead, no alternative) —
doesn't consult `void_suits()` to check whether the counter's suit is
already known-void for opponents, which would make it a safer lead than one
in a live suit. Classified **AVAILABLE** (`void_suits()` exists, unused
here) but explicitly **not specced for implementation** — the real question
(does void-in-suit alone constitute safety, or does it need pairing with
trump-exhaustion the way BUG-006 does, since a void opponent can still trump
in) needs a design decision first, not just wiring.

**Status: confirmed added.** The entry is in `AI_Play_Behavior_Bug_Log.md`
immediately after BUG-006, cross-referenced both directions (BUG-006 points
forward to BUG-007, BUG-007 points back). Still correctly just a log entry
— no code change was intended or made here, per the deliberate-deferral
above.

### Branch #11 — generalized guaranteed-win detection (✓ IMPLEMENTED July 6, 2026)

The cardinal rule's dump-counters case only recognized a guaranteed win when
the winning tile was a double. Real gap: a non-double tile can also be
provably unbeatable (e.g., 6:5 once 6:6 has already fallen), and the current
code doesn't dump counters onto those wins either.

**This triggered pulling two deferred `PublicKnowledge` queries off the
shelf** — `highest_remaining_trump()` and `best_remaining_card_for_suit()` —
which were held back in the July 4 RankingUnification session pending
playtest confidence in the ranking-unification fix. That confidence has
since arrived (the Nello doubles-low live trace), so the hold was lifted
this session.

**Design decision:** the generalized check is difficulty-invariant, matching
the existing `is_double()` case (which already applies at all difficulty
levels). Implemented as specced — flagged in the code as a decision, not a
silently-assumed default, in case it needs revisiting.

**Implemented and pushed**: both `PublicKnowledge` queries are live
(following the exact `remaining_count()`/`count_remaining_trump()` pattern
— fresh `Deck`, filter played tiles, delegate all ranking through
`Domino.get_rank()`/`get_suit()`), and branch #11 in `ai_player.gd` now sets
`guaranteed_win = winning_domino.is_double()` and extends it via
`best_remaining_card_for_suit()` plus BUG-006's trump-exhaustion arithmetic
for the non-double case. The reason string still says "double" — left as a
`# TODO: reason string assumes double` comment for the dedicated
reason-string pass rather than retuned here, per the spec's own instruction
not to preempt that session.

**Bonus fix found while implementing, not in the original spec:**
`PublicKnowledge` never tracked `own_suit_reversed` at all (only
`doubles_trump_reversed`) — a real pre-existing gap, since both new queries
call `Domino.get_rank()`, which needs it. Would have silently produced wrong
rankings under Nello Own Suit (Reversed) specifically. Fixed alongside this
spec: `_own_suit_reversed` added to `PublicKnowledge`'s state, threaded
through `from_state()`, and `game.gd`'s `record_trick()` — which likewise
never stored `own_suit_reversed` in `hand_history` entries — fixed too, so
completed-trick reconstruction gets the real value instead of always
defaulting to `false`.

**Also caught while updating docs:** the onboarding doc's `PublicKnowledge`
query count was already wrong before today (said "six," there were seven
even before these two additions) — corrected to nine, with the consumer
list (five now, up from two) accurate against the current file.

**Deeper work explicitly flagged, not in this spec — still open:**
generalizing the guaranteed-win predicate into a reusable `AIPlayer` helper
(reused at #11, the opponent-mirror #24, and future leading-side checks);
composing with BUG-007's void-suit signal for a partial-safety version;
`own_suit_reversed` / Nello doubles-own-suit interaction untested against
the two new queries in live play (the code path is correct now, but
untested — see design-notes entry in `AI_Play_Behavior_Bug_Log.md`).

---

## Consolidated doc-update checklist — ✓ all done (July 6, 2026)

Every item below is complete. Originally written as a to-do list for
whichever session pasted the specs in; that turned out to be the same
session, so this is now a record of what was done rather than a pending
list.

- [x] `AI_Play_Behavior_Bug_Log.md`: BUG-006 added, BUG-007 added
      immediately after it, cross-referenced both to each other and to
      BUG-002/002b. A third entry ("Design notes — guaranteed-win detection
      generalization") added for branch #11's flagged future work
      (generalization beyond #11, void+trump composition, own_suit_reversed
      coverage) — status "design notes only, not blocking."
- [x] `Phase3_Objective_Audit.md`: branch #8's row updated (difficulty now
      affects *which* trump is led; Selection predicate stays
      difficulty-invariant, only Execution differs). Branch #11's row
      updated (guaranteed-win predicate no longer double-only, with a
      pointer to the design-notes entry above for follow-on ideas).
- [x] `Difficulty_Feed_Points_Inventory.md`: branch #8's difficulty-
      differentiated execution added as item #7 in that doc's own
      inventory (same tagging as #1/#6 — execution-tier, no `AI_MODES`
      parameter planned), with a note that it's a new finding rather than
      part of the original doctrine-flagged six.
- [x] `Texas_42_Session_Summary_July_4_2026_RankingUnification.md`:
      `highest_remaining_trump()` and `best_remaining_card_for_suit()`
      marked implemented, both in the Finding itself and in the "on the
      horizon" list. `lowest_remaining_in_suit()` correctly left as still
      deferred — no consumer identified for it.
- [x] `Texas_42_Project_Onboarding.md`: `PublicKnowledge` consumer table
      updated — both new queries live, `count_remaining_trump()` credited
      with its first real consumer (branch #11). Also corrected an
      unrelated pre-existing error found in the same pass: the doc said
      "six queries" when there were nine after today's additions (seven
      even before them) — fixed to the real count.

---

## On the horizon

- ~~Resume the branch-by-branch trace at **#12** (next session or continuation
  of this one).~~ **Done, same session** — see
  `Texas_42_Session_Summary_July_6_2026_BranchTracePart2.md`, which covers
  #12–#28 and completes the full trace.
- Reason-string rewrite remains explicitly its own separate session, per
  Katy's call earlier this session — not folded into trace work.
- Once BUG-006 lands, revisit BUG-002/002b to confirm whether the same
  count-based check resolves it without needing separately-built trump-
  exhaustion infrastructure.
- BUG-007's design question (void-suit-alone vs. void+trump-exhaustion
  composite) needs a decision before it's specced — flagged, not scheduled.
