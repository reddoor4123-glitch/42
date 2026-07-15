# Backlog Triage — Combined (Pass 1: bug logs, Pass 2: unlogged threads)
*July 15, 2026. Sort, don't solve — nothing below is a decision, only a
placement. Point, don't duplicate — each entry is one line plus its real
home; go there for the actual detail.*

**Note on sourcing:** `AI_Play_Behavior_Bug_Log.md`'s own "Summary" section
was treated as more authoritative than `Documentation_Map.md`'s description
of it — the Map currently says BUG-002/002b and Pattern H/BUG-012 are still
open; the log itself says both were fixed July 13. Flagging this as the
same drift Code just found in the Phase3 citations — worth folding into
that same repointing pass rather than a separate one.

---

## Alpha Blocker
*(actively wrong behavior a playtester would notice today)*

**None found.** Worth stating plainly rather than forcing something into
this bucket — the July 12-13 marathon appears to have cleared everything
that qualified. If a playtest surfaces something new, it starts here; the
bucket is empty, not skipped.

---

## Quality
*(correct behavior, rough edges — tone, small tuning, small cleanup)*

- **Pattern B verification (trump rank blindness)** — believed already
  fixed as a side effect of later work, never actually confirmed against a
  live playtest, only hand-recomputed. Cheapest item on this list to close.
  → `AI_Bid_Behavior_Bug_Log.md`
- **Entry 3 — floor bid reads identical to a confident bid** — correct
  logic, flat tone. Parked for the strings pass. → `AI_Bid_Behavior_Bug_Log.md`
- **Issue 1 — follow-suit vs. counter-protection string** — narrower than
  originally scoped: the forced-follow fact already exists and is already
  used (`legal.size() == 1`); only the "protecting my count" flavor text is
  still missing. → `AI_Explanation_Bug_Log.md`
- **Issue 4 — discard reasoning too thin mid-hand** — still marked blocked
  on void/suit tracking as of its last check. Worth a quick recheck rather
  than assumed-stale, since Issue 7 (below) got a narrowing update that this
  entry didn't. → `AI_Explanation_Bug_Log.md`
- **Issue 7 — bland partner yield string** — narrower than originally
  scoped: `PublicKnowledge` (the thing this was waiting on) now exists and
  is live elsewhere; it just isn't consulted by reason-string generation
  yet. → `AI_Explanation_Bug_Log.md`
- **Phase 1 reason-string rewrite (~24 strings)** — fully specced, not yet
  pasted into Claude Code. Arguably the single most "ready to just go do
  it" item in this whole list. → `Texas_42_Project_Onboarding.md` §4
- **`own_suit_reversed`/Nello doubles-own-suit interaction** against
  `_is_lead_fully_safe()` — unverified, flagged for playtest coverage, not
  newly broken by anything recent. → `AI_Play_Behavior_Bug_Log.md`
- **Opponent-side (`#20`) highest-vs-lowest-into-a-known-void** — still
  unconfirmed by playtest; the partner-side mirror of this same fork did
  get resolved. → `AI_Play_Behavior_Bug_Log.md` (via Branch Trace history)
- **Follow Me dead-code decision** — `Bid.Type.FOLLOW_ME` still carries
  unreachable validation/scoring machinery. One decision needed: amend the
  convention or delete it. → carried into `Bidding_System_Overview` §5
- **Extreme double-count overbidding risk** — logged as a watch item during
  playtesting, not a confirmed bug; a compounding cap is the likely remedy
  if it actually misbehaves at the table. → `AI_Bid_Behavior_Bug_Log.md`

---

## Future Architecture
*(a real design direction, not yet specced)*

- **BUG-015 — trump-control persistence gap** — switching leads between two
  doubles before both opponents are proven void in trump. New, log entry
  only, needs its own design session. → `AI_Play_Behavior_Bug_Log.md`
- **Objective priority as an inspectable structure**, instead of physical
  position in an `if`/`elif` chain — the recurring root cause behind
  several bugs now (BUG-003, the SAFE-tier reorder). → `Phase3_Objective_Audit_REWRITE_July14_2026.md`
- **"Locked-in trick" as a named, reusable predicate** — suggested, not
  built. → `AI_Play_Behavior_Bug_Log.md`
- **World A/B question** — does a correctly-calibrated Layer 1 alone
  produce human-feeling bidding frequency, or is an explicit partner-trust
  signal actually necessary. No hand has settled this either way. →
  `Bidding_System_Overview` §5
- **Capabilities-layer target #1 — fragile no-trump-doubles hands** can
  still overbid; per-tile summation can't see set-risk. →
  `AI_Bid_Behavior_Bug_Log.md`
- **Capabilities-layer target #2 — opening-control value** isn't modeled;
  one flagged real hand still misses by 0.7. → `AI_Bid_Behavior_Bug_Log.md`
- **MARKS cardinal-rule branch** (should the AI ever steal a human
  partner's already-winning trick under Marks) — deferred, waiting on more
  concrete example hands from Katy specifically, not a design gap on our
  end. → `Texas_42_Project_Onboarding.md`

---

## Research
*(validated as worth doing eventually, explicitly gated behind other work)*

- **Monte Carlo hand laboratory** — gated behind the Partner-only harness
  work (today's other conversation).
- **Full trump-identity/evaluation vocabulary** (quantity, ceiling/control,
  continuity, counter-cost) — needs calibration against real flagged
  hands before it's more than a sketch.

---

## Pass 2 — unlogged conceptual threads
*(don't live in any bug log — design ideas, discussed but not written down
as tracked items)*

### Future Architecture
- **Capabilities layer** — descriptive vocabulary for hand *shape* (trump
  dominance, reliable-vs-hopeful winners, set-risk, opening momentum,
  partner dependence) instead of summing per-tile values. Plan is to
  prototype one descriptor at a time in `harness.py` before any GDScript.
  Directly feeds both capabilities-layer targets already listed under
  Pass 1 Quality (fragile no-trump-doubles hands, opening-control value) —
  not a separate item from those, their shared parent.
- **Partner-only play harness** — today's other conversation. → `Handoff_PartnerHarness_Session_Start_July14_2026.md`
- **Mobile portrait layout** — planned, not built. Detect aspect ratio at
  startup, branch `_build_ui()`. → `Texas_42_Project_Onboarding.md` §2
- *(Objective priority as inspectable structure, and the World A/B
  question, are cross-referenced here but already listed once under
  Pass 1 — not duplicated.)*

### Research
- *(Monte Carlo hand laboratory and the full trump-identity vocabulary are
  already listed under Pass 1 Research — this pass didn't surface anything
  new in this bucket.)*

### Quality — longer-term, low urgency
- **Drag-to-reorder hand tiles** — implemented, available at any time;
  restricting to pre-bid only is a small rollback if it turns out to feel
  wrong in practice. Not broken, just worth knowing it's adjustable.
- **Nello domino exchange, named AI personalities, sounds/animations** —
  longer-term deferred, no urgency, no design work started.

---

## Housekeeping note, not a backlog item
`Documentation_Map.md`'s bug-status descriptions have drifted from the logs
they're describing (see sourcing note above) — same repointing pass as the
Phase3 citations Code already flagged, not a new, separate task.
