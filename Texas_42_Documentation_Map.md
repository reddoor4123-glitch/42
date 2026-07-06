# Texas 42 — Documentation Map

### Purpose of this doc
A map of the map. Not new information — a guide to which existing document
to open when a question comes up, so nobody has to re-read six files to find
one fact. Organized by what each doc is *for*, in rough chronological order
within each category. When in doubt: read `Texas_42_Project_Onboarding.md`
first, then the most recent dated session summary, then drill into the
specific doc below if more detail is needed.

---

## Tier 1 — Start here

**`Texas_42_Project_Onboarding.md`**
The standing reference. Design philosophy, function-containment principles,
full file inventory with roles, deep dives on `ai_player.gd` and
`game_table.gd`, and "current focus systems." Closest thing to a living
architecture doc. **Caveat as of July 5:** its `decide_play()` /
`PublicKnowledge` section describes the void-lead wiring as "specced, not
yet pasted in" — that's now stale; it's implemented and confirmed working
in real play. Worth a light refresh next time onboarding content is touched,
not urgent on its own.

**`Phase3_Objective_Audit.md`**
The working document for the Phase 3 difficulty-branch collapse. Full
branch-by-branch table of every path in `decide_play()`, the objective
vocabulary (`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`,
`CONTEST_IF_WORTHWHILE`, `ESCAPE`, `CONTROL_TRUMP`, `FORCE_A_VOID`,
`OPEN_SAFE_SUIT`, `PROTECT_COUNTERS_WHILE_LEADING`), the `COMMITMENT_GATE`
mechanism, and the candidate `AI_MODES` parameters (`trust_threshold`,
`contest_threshold`). **Open this whenever the conversation touches Phase 3,
`decide_play()` branch structure, or "why does this behave differently by
difficulty."**

**`Phase2_Control_Layer_Audit.md`**
The locked structural model for Phase 2: exactly three control categories —
Selection, Commitment, Modulation — with the discriminator test that
resolves ambiguous cases (does a branch change which path executes, or
just a magnitude feeding one fixed path). Includes the rejected "Knowledge
as a fourth stage" alternative (with a watch condition), the candidate
`AI_MODES` parameter tables, and the still-open `cooperation_bias` /
`trust_threshold` question. **Open this whenever the conversation touches
Phase 2, `AI_MODES` wiring, or Selection/Commitment/Modulation as a model.**
Note: its original "Phase 1 sits above the pipeline" claim has since been
corrected — see `Phase1_Control_Layer_Audit.md`.

**`Phase1_Control_Layer_Audit.md`**
The locked resolution for Phase 1: the cardinal rule is ordinary Selection
(`PROTECT_PARTNER_WIN`), not a hard invariant above the pipeline — corrects
a claim in `Phase2_Control_Layer_Audit.md`. Documents the one genuine
exception found (a long-horizon lead-control/"trick-sacrifice" concept that
doesn't fit Selection/Commitment/Modulation, unified with the BUG-005
aside in `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` and parked
indefinitely). **Open this whenever the conversation touches Phase 1,
the cardinal rule, or "why doesn't the partner take this obviously winning
trick."** Phase 1 is expected to be touched rarely after this document.

---

## Tier 2 — Dated session summaries (chronological)

| Date | Doc | Covers |
|---|---|---|
| Jul 1 | `Texas_42___Session_Summary__July_1_2026_v2_.md` | Establishes the four-phase model (Cooperation/Risk/Opportunism/Awareness), Win Safety concept, counter-dumping bug (Phase 1), Points-vs-Marks gap, bidding Layers 1–3. Good doc for "why do we have four phases" and early Phase 1 gaps. |
| Jul 2 | `Texas_42_Session_Summary_July_2_2026.md` | Mobile-layout constraints (proportional tile sizing, hardcoded fonts, portrait branch plan). Confirms Win-by-two popup, doubles-as-trump button, AI hand tile sizing shipped. Restates four-phase model. Good doc for mobile-layout questions. |
| Jul 4 (plain) | `Texas_42_Session_Summary_July_4_2026.md` | HandRecord Phase B design (data layer only) — the `hand_history` vs `build_hand_record()` distinction, why bid decisions needed capturing, the by-reference `hand` array bug caught during spec design. Good doc for "why does HandRecord work the way it does" at the data layer. |
| Jul 4 (PublicKnowledge) | `Texas_42_Session_Summary_July_4_2026_PublicKnowledge.md` | Origin story of `PublicFrame`/`PublicKnowledge` — why void tracking got reframed from "feature" to "inference layer," the three strict properties, the six query set and how the candidate list got cut down, the void-lead consumer spec (including the highest-vs-lowest flag). **Good doc for "why does PublicKnowledge look the way it does."** |
| Jul 4 (RankingUnification) | `Texas_42_Session_Summary_July_4_2026_RankingUnification.md` | The ranking split-brain bug (fixed), MARKS/Plunge/Splash objective fix, the six `PublicKnowledge` queries confirmed implemented, the Nello-low playtest trace, and Finding 3 (orphaned settings, including the first flag on `nello_doubles_reversed`). **Good doc for ranking/comparison bugs and the orphaned-settings list.** |
| Jul 4 (PhaseC) | `Texas_42_Session_Summary_July_4_2026_PhaseC_HandRecordUI.md` | HandRecordWriter + replay flag UI design arc, the platform-asymmetric persistence decision (desktop overwrite vs. web single-download), the reverted "live HandRecord object" idea. **Good doc for "why does flagging/export work the way it does."** |
| Jul 4 (TurnPacing) | `Texas_42_Session_Summary_July_4_2026_TurnPacingAndSevens.md` | Three shipped UI/feel fixes: removed post-bid pause, "arm a play" mechanic, Sevens legal-move enforcement. **Good doc for turn-pacing/feel questions and Sevens legality specifics.** |

**Note on redundancy:** the four July 4 docs are genuinely separate threads
(not drafts of each other) — PublicKnowledge, RankingUnification, PhaseC,
and TurnPacing were parallel or sequential conversations that each shipped
independently. If a July 4 question comes up, the table above should narrow
it to one doc quickly; if unsure, RankingUnification has the widest net
(full codebase review) and is a reasonable first check.

---

## Tier 3 — Bug logs (living documents, not session-dated)

**`AI_Play_Behavior_Bug_Log.md`** — gameplay decision bugs, organized by
pattern (e.g. Pattern A: "guaranteed trick" detection too narrow —
BUG-002/002b/004). Status-keyed (✓ fixed / → ready / ⏳ waiting on Phase 4 /
⚑ needs examples). **Check here before assuming a play-decision oddity is
new — it may already be a known, categorized bug with a fix shape written.**

**`AI_Bid_Behavior_Bug_Log.md`** — same idea, bidding side. E.g. Pattern A:
the Marks-bid-gate double defect in `decide_bid()`.

**`AI_Explanation_Bug_Log.md`** — reason-string mismatches (wrong tone,
wrong actor, inaccurate belief state), example-numbered rather than
pattern-numbered. This is the intake log the Phase 1 reason-string rewrite
spec draws from, and where the audit's new #25 (`value_gate`) finding
should eventually land.

---

## Quick lookup: "I have a question about X, which doc do I open?"

- **"Why does the AI behave differently at different difficulties?"** →
  `Phase3_Objective_Audit.md` first (has the actual branch table), then
  Onboarding §4 for the Knowledge/Evaluation/Neither litmus test.
- **"What's PublicKnowledge allowed to do?"** → Jul 4 PublicKnowledge summary
  for the origin/principles, Onboarding for the current file inventory.
- **"Why did a ranking/doubles bug happen?"** → Jul 4 RankingUnification.
- **"How does hand flagging/export actually work?"** → Jul 4 PhaseC summary
  + Jul 4 plain (Phase B) for the data-layer half.
- **"Is this play/bid oddity a known bug?"** → the relevant bug log, by
  pattern name, before writing a new report.
- **"Why is a reason string worded oddly?"** → `AI_Explanation_Bug_Log.md`.
- **"What's left in the mobile layout plan?"** → Jul 2 summary.
- **"What's the overall four-phase roadmap?"** → Jul 1 summary (origin),
  Onboarding §6 (current state).

---

## Known documentation debt (not urgent, just tracked)

- Onboarding's `decide_play()`/void-lead section is one step stale (says
  "not yet pasted in" — it's implemented and confirmed working).
- Any doc still listing "counter-dumping on guaranteed wins" and "Points vs.
  Marks distinction" as Phase 1's two open gaps is stale — both are
  implemented and confirmed correct (`Phase1_Cooperation_Audit.md`,
  `Phase1_Control_Layer_Audit.md`). **BUG-003/003b is also now fixed**
  (partner-leading trump control reordered ahead of the safe off-suit lead,
  with the double-aware 3-vs-4 threshold) — any doc still listing it as an
  open item is stale. Phase 1's only remaining open item is the parked
  long-horizon concept.
- No single doc yet states plainly that Phase C (HandRecordWriter + flag UI)
  is fully live and has been generating real JSON bug reports all day —
  that fact currently only exists in this conversation. Worth folding into
  Onboarding §6 next time that section gets touched.
