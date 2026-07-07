# Where Difficulty Feeds In (v1) — Inventory and Classification

*Written to answer a specific question: are we ready to strip or neutralize
hardcoded difficulty checks across the board? Short answer: not uniformly —
the six branches the project's own doctrine already flagged aren't all the
same kind of thing, and treating them as one pile risks undoing confirmed
design work alongside genuine scaffolding. This doc separates them.*

---

## The three places difficulty appears at all

**Modulation — clean, no action needed.** `decide_bid()` reads `risk_bias`
and `max_overbid` from `AI_MODES`, keyed by difficulty. Difficulty never
appears as a bare check inside the decision logic itself — only as a lookup
that selects which scalars get used. This is the target shape everything
else is supposed to converge toward.

**Selection and Commitment — the six bare `if difficulty ==` branches.**
Named as "transitional, not drift" in the file's own doctrine header and
repeated across `Texas_42_Session_Summary_July_4_2026_RankingUnification.md`
and `Phase3_Objective_Audit.md`. This is the inventory below.

---

## The branches, classified individually

*Originally six (the project doctrine's own count); #7 is a new addition
(July 6, 2026), found independently rather than part of the original
doctrine-flagged set — same execution-tier shape as #1/#6, added here for
consistency rather than opened as a separate inventory.*

| # | Branch | What it does | Classification | Recommendation |
|---|---|---|---|---|
| 1 | `FEEL_OUT_THE_HAND` | Beginner-only opening-trick objective | **Confirmed genuine exception.** The one case the doctrine itself says doesn't need to collapse — difficulty changes which mission is in play, not just execution quality. | Leave alone. Nothing to fix. |
| 2 | `FORCE_A_VOID` expert-only gate | Gates void-targeting behind `difficulty == "expert"` | **Correct behavior, imprecise form.** It's standing in for a Knowledge-access rule (only expert gets `PublicKnowledge` consulted here), and today that happens to be the right behavior — it's not an unexamined guess. The check tests difficulty directly rather than testing knowledge access, which is a form mismatch, not a behavior bug. | Leave behavior alone. Optional future cleanup: reframe as a knowledge-access check once/if knowledge access itself becomes difficulty-scoped in more than one place — not urgent, not a correctness issue. |
| 3 | `trust_gate` (#16) — expert's "no trust rule" bypass | Expert skips the hold-back check, always commits | **Live open question, now with real evidence.** BUG-005's fix proved the standard-difficulty logic underneath this bypass has no trust content — it's contract margin, live-counter status, and lead economy, all difficulty-agnostic in principle. That directly reopens whether expert needs a separate bypass at all. | **Ready to test now.** Try removing the bypass — let expert run the identical corrected logic — and see whether anything actually differs. This is the most concrete, evidence-backed item on this list. |
| 4 | `trust_gate` (#16) — standard branch itself | Was the original bare-check branch this session rebuilt | **Already substantially resolved.** No longer placeholder logic — replaced with deterministic margin/counter/lead-economy evaluation (BUG-005 fix, implemented and playtest-confirmed). | Nothing further needed here specifically — its remaining tie to difficulty is only the branch that decides whether expert bypasses it (see #3). |
| 5 | `value_gate` (#25) — beginner's `trick_pts >= 5` threshold | Beginner-only opponent contest threshold, hardcoded | **Genuinely unvalidated — hasn't gotten the #16 treatment yet.** Nobody has walked through real hands with this the way we just did for `trust_gate`. This session's core lesson was that "looks like placeholder" and "confirmed placeholder" aren't the same claim — this one hasn't been checked either way yet. | **Needs its own audit conversation before any decision** — same process #16 got (real table scenarios, not assumptions), not a blanket strip. |
| 6 | Beginner's "always secure the trick without second-guessing" (fork just above #16) | Beginner skips all economy/margin reasoning, always takes a winning trick | **Confirmed, deliberate design — not scaffolding.** This is the exact behavior Katy signed off on in `AI_Play_Behavior_Bug_Log.md`, BUG-004: *"a stranded counter behind a friendly trick is a believable Uncle Ed mistake."* A real decision, already made, just not yet expressed as a scalar. | Leave behavior alone. Same optional future note as #2 — eventually worth an `AI_MODES` parameter rather than a bare check, but not because the current behavior is wrong. |
| 7 | `CONTROL_TRUMP` (branch #8, partner leading) — highest-vs-lowest trump lead when control applies without the double | Beginner (and anyone holding the double) leads highest trump; standard/expert without the double lead lowest instead, to draw the double out of an opponent's hand first | **New (July 6, 2026), same shape as #1/#6 — execution-tier, not a new selection or knowledge concept.** The `trump_control` predicate itself stays difficulty-invariant Selection; only which trump gets led within that objective differs, and only in the no-double case. A real table technique a standard/expert player would apply and a beginner-level player realistically wouldn't know — models a genuine skill gap, not an artificial handicap. | Leave behavior alone. Same optional future note as #2/#6 — eventually worth an `AI_MODES` parameter (e.g. a shared "technique" axis with #6) rather than a bare `difficulty ==` check, but not because the current behavior is wrong. |

---

## Why this isn't a uniform "strip everything" situation

Four of the six (#1, #2, #4, #6) are either doctrine-confirmed exceptions,
already-fixed, or explicitly validated design decisions from real sessions
— not guesses that predate the current architecture. Neutralizing or
stripping these would erase real, checked work, not premature scaffolding.

Only two are live: **#3 has a concrete, evidence-backed test ready to run
right now** (does expert even need a separate path anymore), and **#5
needs the same kind of dedicated walkthrough #16 got** before any decision
is made about it — not because it's assumed to be wrong, but because it's
never actually been checked.

## Recommended next steps, in order

1. **Test removing `trust_gate`'s expert bypass (#3).** Cheapest, most
   concrete, and directly informed by this session's fix. If nothing
   changes, that's one of the six branches fully collapsed — a real win
   for the Phase 3 doctrine's goal, not a deferral.
2. **Give `value_gate` (#25) its own audit session**, same format as
   `trust_gate` got — real hands, Katy's table judgment, before touching
   the code. Likely candidate for the same `_live_counter_for_suit` helper
   applied to the contest-side objective, per the standing follow-up from
   last session.
3. **Leave #1, #2, #4, #6 untouched.** They're not part of the "we jumped
   the gun" concern — they're confirmed design, not unexamined defaults.
4. Once #3 and #5 are resolved one way or the other, the six-branch list
   from the original doctrine is genuinely closed out — worth a final
   pass through `ai_player.gd`'s difficulty-doctrine header at that point
   to update its own count and status.
