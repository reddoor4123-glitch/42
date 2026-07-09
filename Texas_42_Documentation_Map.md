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
architecture doc. Refreshed July 5, 2026 — the previous "void-lead wiring
specced, not yet pasted in" staleness is fixed; it now reflects PublicKnowledge
as live with two real consumers, BUG-003/003b and BUG-005 as fixed, Own Suit
(Reversed), Sevens legal-move enforcement, and the four `ai_player.gd`
doctrine headers. Has its own "last verified" line — check that date before
trusting it blindly on a much later visit.

**`Phase3_Objective_Audit.md`**
The working document for the Phase 3 difficulty-branch collapse. Full
branch-by-branch table of every path in `decide_play()`, the objective
vocabulary (`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`,
`CONTEST_IF_WORTHWHILE`, `ESCAPE`, `CONTROL_TRUMP`, `FORCE_A_VOID`,
`OPEN_SAFE_SUIT`, `PROTECT_COUNTERS_WHILE_LEADING`), and the `COMMITMENT_GATE`
mechanism. **Open this whenever the conversation touches Phase 3,
`decide_play()` branch structure, or "why does this behave differently by
difficulty."** Branch #16 (`trust_gate`) and #4 (MARKS cardinal rule) both
carry July 5 correction notes — read those before trusting the original row
text for either. `trust_threshold`, one of the two candidate `AI_MODES`
parameters this doc surfaced, **no longer has a confirmed source branch**
post-BUG-005 — see the correction note after the candidate-parameters table.
For what to actually do next about the six bare-difficulty branches, see
`Difficulty_Feed_Points_Inventory.md` instead — it's the newer, more current
per-branch recommendation doc.

**`Phase2_Control_Layer_Audit.md`**
The locked structural model for Phase 2: exactly three control categories —
Selection, Commitment, Modulation — with the discriminator test that
resolves ambiguous cases (does a branch change which path executes, or
just a magnitude feeding one fixed path). Includes the rejected "Knowledge
as a fourth stage" alternative (with a watch condition) and the candidate
`AI_MODES` parameter tables. **Open this whenever the conversation touches
Phase 2, `AI_MODES` wiring, or Selection/Commitment/Modulation as a model.**
Two corrections applied July 5: the original "Phase 1's cardinal rule sits
above the pipeline" claim is retracted (see `Phase1_Control_Layer_Audit.md`),
and the `cooperation_bias`/`trust_threshold` Unresolved entry now reflects
that `trust_gate` (its intended source) has no trust content left post-BUG-005.
The "MARKS cardinal-rule override" Unresolved entry is also resolved — see
`Phase1_Control_Layer_Audit.md`.

**`Phase1_Control_Layer_Audit.md`**
The locked resolution for Phase 1: the cardinal rule is ordinary Selection
(`PROTECT_PARTNER_WIN`), not a hard invariant above the pipeline — corrects
a claim in `Phase2_Control_Layer_Audit.md`. Also resolves the MARKS
cardinal-rule override question (split into an ordinary-Selection half,
closed, and a separate long-horizon lead-control half, permanently parked)
and the opponent-mirror boundary question. Documents the one genuine
exception found (the long-horizon lead-control/"trick-sacrifice" concept —
doesn't fit Selection/Commitment/Modulation, unified with the BUG-005
aside in `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` and parked
indefinitely). **Open this whenever the conversation touches Phase 1,
the cardinal rule, or "why doesn't the partner take this obviously winning
trick."** Phase 1 is expected to be touched rarely after this document,
except BUG-003/003b (now fixed) and the parked concept (deliberately not
being built).

**`Phase1_Cooperation_Audit.md`**
The branch-by-branch Phase 1 audit `Phase1_Control_Layer_Audit.md` is the
locked resolution *of* — covers the same ground (cardinal rule, partner
leading logic, MARKS override question, reason-string debt tied to
cardinal-rule branches) with more code-level detail per item. Read this one
for the "what does the code actually look like at each of these branches"
detail; read `Phase1_Control_Layer_Audit.md` for the settled conclusions.
Both are current as of July 5 (BUG-003/003b and the MARKS question are
marked resolved in both).

**Raw concept audits — `Phase1_Raw_Concept_Audit.md`, `Phase2_Raw_Concept_Audit.md`**
Deliberately unlocked inventories: every place a Phase-1- or Phase-2-adjacent
concept appears in code/comments/docs, without unifying or classifying —
that step happens in the corresponding Control-Layer/Cooperation audit, not
here. Useful when you need the raw evidence a locked conclusion was built
from, or want to check whether a locked doc missed an occurrence. **Both
predate BUG-005 in places** — several entries in `Phase2_Raw_Concept_Audit.md`
(#5, #6, #8, #12) originally described `trust_gate` as pure turn-order
geometry; those have July 5 correction notes appended but the original text
is kept as the historical record of what the code looked like before the
fix. Don't mistake an uncorrected code snippet in either raw audit for
current code — check the Control-Layer audit or `ai_player.gd` itself first.

**`Difficulty_Feed_Points_Inventory.md`**
The current, evidence-based per-branch recommendation for the six historically-bare
`if difficulty == ...` branches — newer than and supersedes the "suggested
order" list in `Texas_42_Next_Session_Prep_July_5_2026.md` §3 for this
specific topic. Classifies each of the six individually (confirmed exception,
already-fixed, ready-to-test, needs-its-own-audit, or confirmed-deliberate-design)
rather than treating them as one pile. **Open this before touching any of
the six branches, or before resuming `trust_threshold`/`cooperation_bias`
design work** — it's the doc that reopened the Expert "no trust rule" bypass
as a concrete testable question post-BUG-005.

---

## Tier 2 — Dated session summaries (chronological)

| Date | Doc | Covers |
|---|---|---|
| Jul 1 | `Texas 42 — Session Summary (July 1 2026 v2).md` | Establishes the four-phase model (Cooperation/Risk/Opportunism/Awareness), Win Safety concept, counter-dumping bug (Phase 1), Points-vs-Marks gap, bidding Layers 1–3. Good doc for "why do we have four phases" and early Phase 1 gaps. (Note: this doc's actual filename uses spaces/em-dash/parens — earlier versions of this map cited an underscored filename that doesn't match any file on disk; corrected here.) |
| Jul 4 (RankingUnification) | `Texas_42_Session_Summary_July_4_2026_RankingUnification.md` | The ranking split-brain bug (fixed), MARKS/Plunge/Splash objective fix, the six `PublicKnowledge` queries confirmed implemented, the Nello-low playtest trace, and Finding 3 (orphaned settings, including the first flag on `nello_doubles_reversed`). **Good doc for ranking/comparison bugs and the orphaned-settings list.** |
| Jul 5 (Phase2Architecture) | `Texas_42_Session_Summary_July_5_2026_Phase2Architecture.md` | The session that produced `Phase2_Control_Layer_Audit.md` and found the original `trust_gate` bug (its reason string couldn't mean what its own condition tested) — this is where BUG-005 was first identified, before the fix spec existed. Good doc for the origin story of BUG-005 and the Selection/Commitment/Modulation model. |
| Jul 5 (prep, superseded in places) | `Texas_42_Next_Session_Prep_July_5_2026.md` | Written the night before as a prep doc, not a summary. Its Nello "Reversed" toggle bug write-up (§1) is retracted — that feature works correctly now. Its `trust_gate`/`trust_threshold` design-conversation framing (§3) is superseded by the same day's later BUG-005 fix and by `Difficulty_Feed_Points_Inventory.md` — both are marked with inline correction notes rather than removed, so read the corrections, not just the original prose. |
| Jul 6 (BranchTracePart1) | `Texas_42_Session_Summary_July_6_2026_BranchTracePart1.md` | First half (#1–#11 of 28) of the full branch-by-branch trace against `Phase3_Objective_Audit.md`. Covers BUG-006/BUG-007 (logged, not implemented), the branch #8 low-trump-lead fix, and branch #11's generalized guaranteed-win detection — all implemented and pushed. |
| Jul 6 (BranchTracePart2) | `Texas_42_Session_Summary_July_6_2026_BranchTracePart2.md` | Second half (#12–#28), completing the trace. Covers the removal of branches #17 and #19 (no legitimate strategic basis, same violation class), the new `GIFT_A_VOID`/partner-side `FORCE_A_VOID` capability (branches 6a/6b), and the Partner/Opponent difficulty-coupling architectural finding — all implemented and pushed. **Good doc for "why was branch X removed" or "why does the partner now know about void suits."** |

**Referenced but not present in this repo:** the original doc set (per earlier
drafts of this map and cross-references in other docs) also included
`Texas_42_Session_Summary_July_2_2026.md` (mobile layout), and three more
July 4 threads — `Texas_42_Session_Summary_July_4_2026.md` (HandRecord Phase
B), `Texas_42_Session_Summary_July_4_2026_PublicKnowledge.md` (PublicFrame/
PublicKnowledge origin story), and `Texas_42_Session_Summary_July_4_2026_PhaseC_HandRecordUI.md`
/ `..._TurnPacingAndSevens.md` (HandRecordWriter/flag UI, and arm-a-play/Sevens
legality). None of these five exist in this folder as of July 5. If you're
looking for the content they'd cover, check `Texas_42_Project_Onboarding.md`
§3/§5/§6 first — most of what they'd document is already reflected there
from the code side, even without the original session narrative.

---

## Tier 3 — Bug logs (living documents, not session-dated)

**`AI_Play_Behavior_Bug_Log.md`** — gameplay decision bugs, organized by
pattern. Pattern A ("guaranteed trick" detection too narrow — BUG-002/002b/004)
is unchanged: BUG-004 paused pending Phase 3 Opportunism design, BUG-002/002b
waiting on Phase 4. **Pattern B (BUG-003/003b, lead-priority ordering) is
fixed as of July 5, 2026** — marked ✓ in the doc. Status-keyed (✓ fixed / →
ready / ⏳ waiting on Phase 4 / ⚑ needs examples). **Check here before
assuming a play-decision oddity is new — it may already be a known,
categorized bug with a fix shape written.**

**`AI_Bid_Behavior_Bug_Log.md`** — same idea, bidding side. **Pattern A
(the Marks-bid-gate double defect) is fixed as of July 5, 2026.** Pattern B
(trump rank blindness) is marked "likely resolved already" pending an
actual verification pass against real hands — that verification hasn't
happened yet as far as this doc set shows.

**`AI_Explanation_Bug_Log.md`** — reason-string mismatches (wrong tone,
wrong actor, inaccurate belief state), example-numbered rather than
pattern-numbered. Added to this repo July 6, 2026 — a first-pass log (one
game context, Issues 1–7) written to find where structure was needed before
pausing to build that structure; the next testing pass will likely start a
fresh log rather than append here. Two entries (Issues 3/6) were marked ✓
at the time but the described fix had never actually been applied to the
code — caught during reconciliation and implemented for real the same day
(see `ai_player.gd`'s `human_is_winning` partner-following block). This is
the intake log the Phase 1 reason-string rewrite spec draws from, and where
the audit's `value_gate` reason-string gap (inaccurate "can't win this one"
on a branch that actually can win) should eventually land — still not
logged here as of this file's creation.

**`AI_Play_Behavior_Bug_Log_Addendum_PatternD.md`** — the original BUG-005
write-up (Pattern D: `trust_gate` gated on the wrong fact). Append-only
addendum to the main play bug log rather than merged into it. Already fixed
and confirmed (see `BUG-005_Fix_Spec.md`); kept as the record of the original
three-part diagnosis (wrong gate condition, wrong fallback, wrong reason
string) that motivated the fix. Includes a note pointing to
`Phase1_Control_Layer_Audit.md` as the canonical home for the "decline a
guaranteed win for future lead control" concept this write-up first
identified and set aside.

**`BUG-005_Fix_Spec.md`** — the implementation spec for the BUG-005 fix
(signature change, `_live_counter_for_suit()` helper, the branch replacement,
a verification checklist). Historical/executed — the fix is live in
`ai_player.gd`. Useful if you need the exact original spec shape rather than
reading it back out of the diff.

**`Texas_42_Bug_Log_Convention_Reveals_Field.md`** — process addendum, not a
code change. Defines a "Reveals" field (AVAILABLE / UNBUILT / ONE-OFF) for
all three bug logs, meant to classify *why* a reason-string bug exists
rather than just whether it's fixed — so a batch of individually-patched
strings can be recognized as one missing fact surfacing at several call
sites. Apply going forward; not required as a retroactive cleanup pass on
existing entries.

---

## Quick lookup: "I have a question about X, which doc do I open?"

- **"Why does the AI behave differently at different difficulties?"** →
  `Phase3_Objective_Audit.md` first (has the actual branch table), then
  Onboarding §4 for the Knowledge/Evaluation/Neither litmus test.
- **"What's PublicKnowledge allowed to do?"** → `PublicKnowledge`'s own file
  header (the vocabulary-layer contract lives there directly) and Onboarding
  §3/§6 for current consumer status. The session summary that originated it
  (Jul 4 PublicKnowledge) isn't in this repo — see the Tier 2 note above.
- **"Why did a ranking/doubles bug happen?"** → Jul 4 RankingUnification.
- **"How does hand flagging/export actually work?"** → Onboarding §5/§6 for
  current architecture (`HandRecordWriter`, the replay flag panel). The
  original design-arc session summaries (Jul 4 PhaseC, Jul 4 plain) aren't
  in this repo.
- **"Is this play/bid oddity a known bug?"** → the relevant bug log, by
  pattern name, before writing a new report.
- **"Why is a reason string worded oddly?"** → `AI_Explanation_Bug_Log.md`.
- **"What should happen to the six bare `difficulty ==` branches?"** →
  `Difficulty_Feed_Points_Inventory.md` — the current per-branch answer,
  newer than `Phase3_Objective_Audit.md`'s original framing of the same six.
- **"Does the MARKS cardinal rule still need a design decision?"** → No,
  resolved July 5 — see `Phase1_Control_Layer_Audit.md`.
- **"Is `trust_gate`/`trust_threshold` still about trust?"** → No. See
  BUG-005 in `AI_Play_Behavior_Bug_Log.md`, and the correction notes in
  `Phase3_Objective_Audit.md` and `Phase2_Control_Layer_Audit.md`.
- **"What's the overall four-phase roadmap?"** → Jul 1 summary (origin),
  Onboarding §6 (current state).

---

## Known documentation debt (not urgent, just tracked)

- **Five session summaries referenced by earlier drafts of this map don't
  exist in this repo**: `Texas_42_Session_Summary_July_2_2026.md`,
  `Texas_42_Session_Summary_July_4_2026.md` (plain/Phase B),
  `..._PublicKnowledge.md`, `..._PhaseC_HandRecordUI.md`, and
  `..._TurnPacingAndSevens.md`. If they turn up later (e.g. exported from
  wherever this doc set originally lived), add them back to the Tier 2
  table above. Until then, don't cite them as available — check Onboarding
  first for the code-side facts they'd have covered.
- **`AI_Bid_Behavior_Bug_Log.md` Pattern B** (trump rank blindness) is
  marked "likely resolved already" via hand-recomputation, not an actual
  playtest verification. Worth an explicit verification pass to close it
  out for real rather than leaving it as a confident guess.
- **The `value_gate` (#25) reason-string gap** (generic "can't win this one"
  on a branch that can actually win) is flagged as a candidate entry in at
  least three docs (`Phase3_Objective_Audit.md`, `Phase2_Raw_Concept_Audit.md`,
  `Texas_42_Next_Session_Prep_July_5_2026.md`) but doesn't appear to have
  actually been logged into `AI_Explanation_Bug_Log.md` yet.
- This map itself was significantly out of date until July 5-6, 2026 — nine
  of the eighteen `.md` files in the repo (as of July 5) weren't listed here
  at all, and several entries described pre-BUG-005/pre-BUG-003 states.
  `AI_Explanation_Bug_Log.md` (making it nineteen files) arrived July 6. If
  you're reading this after a substantial gap, do a fresh `find *.md`
  against this map's file list before trusting it fully.
