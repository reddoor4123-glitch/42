# AI Design Doctrine

*Extracted from `ai_player.gd`'s header block, July 15, 2026. This document
is meant to stay static — it states the principles that govern AI design
decisions, not the current implementation status of any specific branch.
For "what's true right now," see `Texas_42_Project_Onboarding.md` (project
state) and `Phase3_Objective_Audit_REWRITE_July14_2026.md` (exact current
`decide_play()` mechanics). If something here and one of those docs ever
disagree, the other docs win — this one is intentionally the slower-moving
of the two.*

---

## AI Design Philosophy

The goal is not technical perfection. The goal is emotional authenticity.

**The first question on any judgment-heavy behavior is "does this belong
in the existing system at all?" — not "how do we tune it?"** Sevens and
Nello both turned out to need entirely separate code paths rather than
tuned parameters, because they're structurally different games hiding
inside the same trick-taking shell. This is the same standing check the
"Reveals" bug-log convention (`Texas_42_Bug_Log_Convention_Reveals_Field.md`)
explicitly cites as already governing design decisions in this project —
this is that principle's canonical home.

Partner trusts the human player and plays for the team's contract.
Opponents play solid, honest 42 — not bloodthirsty, not stupid.

**Partner cooperation intent is difficulty-invariant.** Difficulty changes
judgment quality and awareness, never whether the partner is trying to
help you. Partner has zero difficulty branching anywhere in
`decide_play()` — `vigilance`/`opportunism` apply to opponents only.

Four conceptual decision axes:
- **Cooperation** — partner behavior, team-first decisions
- **Risk** — bidding personality and play aggression
- **Opportunism** — expert ability to capitalize on mistakes
- **Awareness** — inference, void tracking, pattern recognition

Future, not yet built: Confidence (decision certainty influencing play
selection); named personalities as presets over these axes; family-observed
behaviors as personality templates.

**"That partner plays like Uncle Ed."** — that's the target.

*(This is a conceptual model of the kinds of differences that should ever
exist between AI behaviors — not a project-status tracker. It does not
say which axis is "done" or "in progress"; that status changes constantly
and lives in Onboarding instead.)*

---

## Decision Geometry — visibly derivable structural facts

Some decision-relevant facts are neither hidden information nor behavioral
weighting — they are directly observable properties of the current decision
moment, true for every seat regardless of difficulty. Examples: is this
player last to act in the trick? How many legal moves exist? Is the partner
currently winning?

These are pure helper predicates over visible plays/legal state. They are
**not** part of `PublicKnowledge` (no hidden info, no inference, no
accumulation over `hand_history`) and they are **not** difficulty gates
(every seat computes the same answer to the same question).

**Important — do not prematurely unify these into a single "trick is
decided" predicate.** A trick can become locked for at least three
structurally different reasons — a double led (rule of tiles), last-to-act
(turn arithmetic), or a known-safe high trump whose only beater has already
fallen (hidden information — depends on `PublicKnowledge`/inference). They
are not branches of one concept; they are three different subsystems that
sometimes produce the same outcome. Don't write a unifying predicate until
all three cases can genuinely be supplied by one source.

---

## Difficulty Differences — the Knowledge/Evaluation litmus test

The goal is for different difficulties to arrive at different decisions for
understandable reasons — not because they run different games.

Difficulty is not a library of special-case plays. All difficulties share
one decision engine; they differ only in what a player knows and how they
weigh what they know. Before adding an `if difficulty == "..."` branch,
classify what's actually going on:

- **KNOWLEDGE** — What information is this player allowed to use? Genuine
  information asymmetry (inference, derived facts like voids, anything not
  equally available to every seat) belongs behind the project's
  knowledge/inference layer, not a difficulty string. That layer is
  `PublicKnowledge`.
- **EVALUATION** — Everyone can use the same information; difficulties
  differ only in whether they act on it, or how they weigh it. This belongs
  in the shared decision logic, parameterized by an `AI_MODES` axis
  (`vigilance`, `opportunism`, ...) — not a bare difficulty check.
- **NEITHER** — No information- or evaluation-based model fits. Only then
  is a direct difficulty branch acceptable, and it should be treated as a
  last resort, not a default.

If a proposed change starts with `if difficulty == ...`, stop first and
classify it as a Knowledge difference, an Evaluation difference, or a
genuine special case. The classification should drive the implementation —
not the other way around.

---

## Trick Objectives — naming what the branches already decide

Not a new subsystem. No `TrickObjective` enum, no class, no stored state.
It's a naming convention for something `decide_play()` already does
implicitly: before comparing any dominoes, the branch structure has
effectively already chosen a mission for the trick.

Two tiers, not to be conflated:

- **Contract-level intent** — decided once, for the whole hand, at the very
  top of `decide_play()`. Already fully explicit as the Sevens/Nello/Marks
  early-return branches.
- **Trick-level intent** — decided fresh every trick, inside standard play.
  Implicit in branch order; this naming convention is what makes it
  legible.

Objectives are read off decision geometry, not personality —
`partner_winning == true` is geometry; "protect partner" is the objective
that geometry implies. Evaluation (`AI_MODES`) then decides how well that
objective gets executed. Geometry → objective → evaluation is the intended
chain; personality never skips ahead to pick a different objective for the
same geometry.

Not every named concept here is the same grain: `PROTECT_PARTNER_WIN`,
`SECURE_FOR_PARTNER`, and `ESCAPE` are true objectives — what you're trying
to accomplish. `CONTROL_TRUMP`, `FORCE_A_VOID`, and `GIFT_A_VOID` are closer
to strategies/tactics in service of an objective that isn't separately
named. This is deliberate — forcing everything to one grain would be
taxonomy for its own sake.

**For the current, complete list of objectives that exist in the code
today, with their exact mechanics and branch order, see
`Phase3_Objective_Audit_REWRITE_July14_2026.md`'s "Objective vocabulary"
section — not this document.** Naming which objectives exist right now is
exactly the kind of fact that goes stale (this header block itself listed
`CONTEST_IF_WORTHWHILE` as current until this rewrite, well after it was
actually retired) — that's precisely why this doctrine document intentionally
doesn't repeat it.
