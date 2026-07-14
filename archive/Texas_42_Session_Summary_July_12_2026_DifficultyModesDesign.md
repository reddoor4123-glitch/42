# Texas 42 — Session Summary (July 12, 2026)
## Topic: Difficulty Modes — Table Feel Design Session

### Status: Design complete, documented, **not specced, not implemented**

Katy is deliberately holding off on implementation. This document exists so
the design is fully recorded and ready to pick up whenever she's ready to
move to a spec. Nothing in `ai_player.gd` should be assumed changed by this
session.

---

## Starting point

This was the deferred "Beginner mode gets its own session" work first
flagged July 6 and never scheduled. It also resolves the open question
from that same session about whether Partner/Opponent difficulty coupling
needed rethinking.

Katy came in believing the existing plan — "tweak what a player knows by
restricting `PublicKnowledge` access" — would map cleanly onto the three
difficulty tiers. Tracing the five surviving bare `if difficulty ==`
branches against that plan surfaced that it doesn't: some of those branches
aren't knowledge differences at all, and one (#13) turned out to have no
real design intent behind it — checked against the archive, Katy's only
comment on it at the time was "understood. #14," i.e. it was never actually
decided, just carried forward.

---

## The core reframe

Difficulty is not "smart AI vs. dumb AI." It's **table feel** — who is
allowed to notice things, and who is allowed to act on what they notice —
and critically, **it's scoped by seat role, not by one global knob.**

**Beginner table:** modeled on a young/new player's first time at the table
on their own. Everyone else already knows how to play — they aren't going
to make incorrect moves or obvious mistakes — but they're playing "gently."
Opponents are distracted: playing for the trick in front of them, not
tracking voids, not looking ahead, not capitalizing on every minute
opportunity. Overbidding is fine, even good — "sometimes it's a relief to
be overbid, sometimes it's just the way it goes, and if you get overbid
with a good hand it teaches you to make a stronger opening next time."
(Bidding-side tuning for beginner is explicitly parked — see Deferred
Items below.)

**Standard table:** "game night at the senior center, or adults-only game
night." Everyone is competent, everyone plays well, but styles and
priorities differ a little. Katy's read: current gameplay is already close
to a believable standard table.

**Expert table:** tournament-level. Everyone is focused and playing to win.
Katy named several concrete asymmetries she's noticed that don't yet match
this — playing high trump without the double instead of low to draw it out,
putting count on a partner's already-winning hand, "winning" a forced trick
with the lowest available domino instead of the strongest. These are
explicitly **not** to be fixed today — they're the evidence that motivated
this session, not today's work item. They should fall out naturally once
the mechanism below is built.

**Partner is not a difficulty-scaled role at all.** A good partner protects
the new player and helps them win — and does this at every difficulty.
Partner should never play a cruder game. This one call resolves several
previously-open questions at once (see below).

---

## Two-axis model for opponents

Once "partner never varies" was settled, the five bare-`if difficulty`
opponent-adjacent branches stopped looking like five separate problems and
collapsed into two named axes.

### Vigilance — knowledge access (tiered, stable, never random)

Whether an opponent consults `PublicKnowledge` at all for a given decision.
This is a **fact-visibility** gate, not a reasoning gate — and it must
never violate `PublicKnowledge`'s own header contract: *the same query
always returns the same answer regardless of who's asking; different AIs
may ignore a fact, but must never be given different facts.* Vigilance
controls whether an opponent *asks the question*, never what the answer is
or whether the answer is fabricated/randomized per-opponent.

Currently exactly one real consumer exists: `FORCE_A_VOID`'s opponent-side
void-exploitation (branch #20). A second, smaller consumer exists inside
the shared hold-back evaluation itself (see below) — the live-counter bound
that queries `is_void_in()`/`has_been_played()` for a provably-safe read.

**Open, deliberately unresolved:** whether vigilance needs a middle tier
("partial") or should stay binary (none/full) until a second fully
independent knowledge-gated behavior exists to justify the middle state.
Katy's lean: fine to build the lookup as a tier from day one, but don't
invent what "partial" means without a real second consumer to define it.

### Opportunism — whether the tactical evaluation runs at all (probability, not threshold)

This is the axis that took the most iteration to land correctly, and the
final shape is meaningfully different from where it started.

**What it is not:** a value threshold ("only bother if the trick is worth
≥5"). That was the old `value_gate` (#25) shape, and tracing it against
real table behavior revealed it had the *direction backwards* — passing on
a cheap trick is actually the disciplined, vigilant move (resource-conscious,
serving a plan), not the distracted one. A genuinely distracted player is
more likely to grab a trick reflexively "just because they can," wasting a
resource (like a spare trump) that would've served the team better held for
later.

**What it actually is:** whether the opponent runs the same **hold-back /
lead-economy evaluation partner already runs** (the corrected BUG-005
logic — contract margin, live-counter status, lead economy) before
committing to a winnable trick, versus committing reflexively with no
accounting. Critically, this evaluation was found to already be written
**symmetrically** — it computes `our_target` based on whether the acting
player's team is the bidding or defending side, and checks reachability
from either direction. It was never actually partner-specific logic. This
means opponents don't need new evaluation logic; they need permission to
call the existing one with their own team's context.

Because the evaluation is the same one partner uses, and lead-economy
reasoning was already built to answer "is the resulting forced lead good or
bad," opportunism naturally comes out **bidirectional** rather than a
simple contest/decline switch — confirmed via a direct table scenario:
holding four doubles, an opponent should sometimes *aggressively take* an
otherwise-worthless trick specifically to seize the lead and set up those
doubles, exactly the same mechanism that lets a different opponent *decline*
a trump-only win it doesn't need. One evaluation, both directions, no new
rule required for either.

**Randomization — the piece that makes standard feel alive:** Katy raised
an idea about randomizing which `PublicKnowledge` facts a standard opponent
gets access to, per hand or per session, to keep the table feeling fresh.
Reality-checked against the project's own locked invariant (`PublicKnowledge`
must never return different facts to different AIs) — direct fact
randomization was rejected as a design, since it would reopen the exact
split-brain problem the ranking-unification fix closed. But the underlying
want was real, and it maps cleanly onto opportunism instead: rather than a
flat on/off per difficulty, **opportunism is a probability, rolled once per
eligible tactical decision** (per decision point, not per hand or per
game — this is what produces "some tricks sharp, some reflexive" texture
within a single hand, matching Katy's own framing of standard: "everyone
knows how to play and plays well but the styles and priorities are a little
different"). Vigilance stays completely stable and un-randomized; only
*whether the evaluation runs* varies.

---

## Four-configuration stress test (vigilance × opportunism, boolean form)

Run to check whether both axes are independently meaningful before locking
the model in, using: opponent leading, holding a double trump and a strong
off-suit tile, human opponent known void in suit 3.

| Vigilance | Opportunism | Result |
|---|---|---|
| off | off | Reflexive lead, no plan. Pure distracted-player feel. |
| off | on | Evaluates lead-economy/margin (doesn't need `PublicKnowledge` for that), but the live-counter bound falls back to worst-case instead of a confirmed-safe read, since the void fact isn't visible. Real, distinct state: strategic but conservative. |
| on | off | **Collapses to the off/off case.** Knows the void, but nothing decides to act on it — vigilance supplies a fact, opportunism is what turns a fact into a decision. Confirmed not a flaw in the model: it's accurate information that we currently have exactly one vigilance-gated consumer, and that consumer inherently needs both axes together to produce any behavior. Worth remembering as a real (if currently empty) cell, not deleting from the design — a future knowledge-gated behavior that doesn't require deliberate targeting could populate it. |
| on | on | `FORCE_A_VOID` exactly as built today. |

**Second stress test — forced overtake, contract on the line** (opponent
last to act, must win, could escalate to a secure winner instead of a
minimal one): confirmed the same shape holds. Opportunism-off plays lowest
legal, no escalation (this is BUG-008's pattern, now understood as
intentional opponent-side behavior at low opportunism rather than a bug to
patch in isolation). Opportunism-on without vigilance evaluates margin and
picks a stronger winner from hand-visible information alone. Opportunism-on
with vigilance picks the provably safest winner. No new mechanism needed —
this confirms the counter-dump and overtake-escalation asymmetries Katy
flagged (see Expert table notes above) are downstream consequences of this
same two-axis model, not separate fixes.

**Conclusion:** the two axes are not fully orthogonal — vigilance is the
substrate (what facts exist to reason with), opportunism is what turns a
fact into a decision — but both are independently necessary and every
non-degenerate behavior change wants some combination of both. Model holds.

---

## Branch migration (design-level, not yet specced)

| Branch | Today | Proposed |
|---|---|---|
| #13 (beginner partner "secure without second-guessing") | `if difficulty == "beginner"` on partner | **Relocated, not deleted.** No design intent ever existed for this on partner ("understood. #14" was the entirety of the original decision). Its actual shape — skip trump economy, skip the hold-back check, win reflexively — is exactly opportunism-off opponent behavior. Moves to opponents; deleted from partner entirely. |
| #16 partner side (hold-back/lead-economy check) | Already runs for partner, standard only | Runs for partner always, no gate — matches "partner never varies." |
| #16 expert bypass ("no trust rule") | `if difficulty == "expert"` skips the check on partner | Deleted outright — partner never skips this check at any difficulty. |
| #16 on opponents | Doesn't exist today (partner-only) | New: opponents call the same shared evaluation, gated by `_should_evaluate_tactically()` (opportunism roll), using their own team's context — enabled by the evaluation already being symmetric. |
| #20 `FORCE_A_VOID` (opponent void-targeting) | `if difficulty == "expert"` | `if vigilance == "full"` |
| #25 `value_gate` (beginner `trick_pts >= 5`) | Standalone hardcoded threshold, beginner-only | **Retired, not migrated.** Superseded entirely by the opportunism roll on the shared evaluation — a separate value threshold is no longer needed and was modeling the wrong direction regardless. |
| 6a/6b (partner-side `GIFT_A_VOID`, `FORCE_A_VOID` mirror) | Already uniform, no difficulty gate | Untouched — already matches the "partner never varies" principle these were built under. |

Two-axis config table for `AI_MODES` (**illustrative shape, numbers are
placeholders, not tuned**):

```gdscript
const AI_MODES := {
    "beginner": {
        "risk_bias":        -0.25,   # bidding, unchanged, out of scope today
        "max_overbid":      2,       # bidding, unchanged, out of scope today
        "vigilance":        "none",
        "opportunism":      0.0,
    },
    "standard": {
        "risk_bias":        0.0,
        "max_overbid":      4,
        "vigilance":        "none",   # open — see Vigilance section
        "opportunism":      0.6,      # placeholder, needs harness-style tuning
    },
    "expert": {
        "risk_bias":        0.25,
        "max_overbid":      6,
        "vigilance":        "full",
        "opportunism":      1.0,
    },
}
```

`cooperation_bias` and the old string-valued `opportunism` key are both
retired outright — confirmed dead reads, no longer even correctly
placeholder-shaped for where the project landed.

Proposed call-site shape:

```gdscript
func _should_evaluate_tactically(mode: Dictionary) -> bool:
    return randf() < mode["opportunism"]
```

Naming note (see Deferred Items): deliberately named as a question
("should I evaluate") rather than tied to the word "opportunism," so a
future second evaluation-type doesn't require renaming call sites — see
below for why a full `EvaluationType` dispatch enum was considered and
rejected for now.

---

## Deferred / explicitly not decided today

- **Vigilance's second tier.** Binary (none/full) for now; revisit once a
  second real knowledge-gated opponent behavior exists to define what
  "partial" means. Don't invent it speculatively.
- **Opportunism's real numbers.** `0.6` for standard above is a placeholder
  for illustration only. Wants the same harness-style validation-against-
  real-hands treatment the bidding fix package got, once this reaches spec
  stage.
- **`_should_evaluate_tactically()` as a generalized decision point.** Katy
  raised whether the function should be a dispatch (`AIBehavior.should_evaluate(mode, EvaluationType.TACTICAL)`)
  to future-proof against other future evaluation contexts (contract on the
  line, final trick, marks vs. points, replay/debug mode, future personality
  traits). Assessed and **explicitly not adopted now** — an enum with one
  real member can't tell us the shape a second member needs, and guessing
  ahead of a real second case is exactly the trap `cooperation_bias`/
  `trust_threshold` already fell into (a slot invented before any branch
  needed it, sitting inert for weeks). The cheap, real win was kept instead:
  name the function as a question rather than a mechanism, so it doesn't
  need renaming later. Full dispatch generalization stays parked until a
  second real evaluation type shows up to define its own shape.
- **Beginner-mode bidding tuning (`risk_bias` sign, overbid tolerance).**
  Explicitly left alone — being handled independently in the ongoing
  bidding-evaluator work in another session. Katy's current read has also
  shifted since the original January design: overbidding a beginner is now
  considered acceptable-to-good ("sometimes it's a relief to be overbid...
  it teaches you to make a stronger opening next time"), not something to
  actively prevent — but no change is being made to `risk_bias`/`max_overbid`
  today.
- **The specific Expert-table asymmetries Katy named** (high trump lead
  without the double, counting onto partner's winning hand, minimal
  overtake instead of secure winner) — not fixed today. Expected to resolve
  naturally once opportunism/vigilance are actually wired in, since all
  three are opportunism-shaped gaps (see stress test above), not separate
  bugs.

---

## Next session entry points

- Decide whether to move straight to a Claude Code spec for the branch
  migration table above, or do another design pass first (vigilance's
  second tier, opportunism's real numbers).
- If speccing: `value_gate` (#25) can be marked **closed by design
  supersession** rather than needing its own dedicated table-scenario
  audit session (previously flagged as owed one) — this session's
  opportunism model replaces it outright.
- Any new reason strings this produces (opponent-side hold-back/lead-
  economy commit strings, once opponents actually reach that branch) go
  through the dedicated strings-pass convention, not bundled into the
  behavior spec.
- Standing items unchanged and untouched by this session: capabilities-
  layer bidding work, `SHED_A_SUIT`, long-horizon lead-control sequencing,
  closed-set suit-depletion deduction, AI special contract bidding, mobile
  layout pass.
