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
The standing reference — **rewritten as v2, July 15, 2026** (the original
had grown cluttered as it accumulated a year's worth of AI-behavior and
bug-fix narrative that now belongs elsewhere). Scope is deliberately
narrower now: orientation, file inventory with roles, standing engineering
principles, and a brief architectural map of `ai_player.gd`/`game_table.gd`.
It explicitly does not carry AI design philosophy (`AI_Design_Doctrine.md`),
exact `decide_bid()`/`decide_play()` mechanics
(`Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md`,
`Phase3_Objective_Audit_REWRITE_July14_2026.md`), or open items
(`Backlog_Triage_Combined_July15_2026.md`) — each of those has its own doc
now instead of living here. v1 is archived, not deleted, if you need the
old bug-fix-narrative version. Has its own "last verified" line — check
that date before trusting it blindly on a much later visit.

**`Headless_Harness_Reference.md`**
Plumbing reference for headless `godot --headless` experiment scripts
(Jobs 1–3, July 15, 2026) — turn-order/`is_partner`/stdout-suppression
conventions, a copy-paste orchestration template, a gotchas list (each one
a silent-failure mode, not a crash), the Godot binary's actual path on this
machine, and a script inventory. Deliberately carries no findings of its
own — those stay in each job's own results. **Open this before writing any
new headless experiment script**, and update it if a new job finds a new
gotcha or changes the template.

**`Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md`**
Current, from-scratch technical description of `decide_bid()`'s three-layer
architecture plus a single consolidated open-items list for bidding —
supersedes `Texas_42_AI_Bidding_Structure_Overview.md` (now archived, see
below). **Open this for the most detailed walkthrough of the bidding math
itself**, and as the first place to check before logging a new bidding
open item — more implementation detail than Onboarding §4 has room for.

**`Texas_42_AI_Bidding_Structure_Overview.md`** — **ARCHIVED July 14, 2026**,
moved to `archive/`. Fully superseded by
`Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md` above.
Historical text below kept for the record, not current: a from-scratch
technical description of `decide_bid()`'s three-layer architecture,
corrected in place July 12, 2026 to reflect the four evaluator fixes.

**`Phase3_Objective_Audit_REWRITE_July14_2026.md`**
Current, from-scratch branch-by-branch reference for `decide_play()` —
supersedes `Phase3_Objective_Audit.md` (now archived, see below), which had
accumulated a year's worth of layered correction notes on top of a branch
numbering that no longer matched the code, particularly in partner-leading
after the July 13 Lead-Safety Priority Stack rebuild. Companion to
`AI_Design_Doctrine.md`'s Trick Objectives section — the doctrine doc
covers the naming *concept*, this doc covers the exact, current objective
list and mechanics. **Open this whenever the conversation touches Phase 3,
`decide_play()` branch structure, or "why does this behave differently by
difficulty."** v1 is kept archived, not deleted, as the historical record
of how each finding was reached — if you want the "why" behind a given
objective rather than the current "what," the bug logs (particularly
`AI_Play_Behavior_Bug_Log.md`) are the better source than v1 itself.

**`Phase3_Objective_Audit.md`** (v1) — **ARCHIVED July 14, 2026**, moved to
`archive/`. Fully superseded by
`Phase3_Objective_Audit_REWRITE_July14_2026.md` above. Historical record
only — its branch numbering no longer matches the current code.

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
`Phase1_Control_Layer_Audit.md`. **Further resolved July 12, 2026:** the
`cooperation_bias`/`trust_threshold` Unresolved entry is now fully closed,
not just reframed — `cooperation_bias` is deleted from `AI_MODES` and the
branch it might have gated (#16's expert bypass) no longer exists. See the
entry's own July 12 correction note.

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
— **ARCHIVED July 14, 2026**, moved to `archive/`. Fully superseded by
`Phase1_Control_Layer_Audit.md` and `Phase2_Control_Layer_Audit.md`
respectively, their explicitly-named successors. Historical description
below kept for the record: deliberately unlocked inventories: every place a Phase-1- or Phase-2-adjacent
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

**`Difficulty_Feed_Points_Inventory.md`** — **CLOSED, July 12, 2026; ARCHIVED
July 14, 2026,** moved to `archive/`.
Was the current, evidence-based per-branch recommendation for the six historically-bare
`if difficulty == ...` branches. Every remaining open item it tracked (the Expert
"no trust rule" bypass, `value_gate`, the beginner reflexive-win shortcut, the
`CONTROL_TRUMP` high-vs-low technique, the `FORCE_A_VOID` expert gate) has now
been resolved by `Spec_Difficulty_Modes_TwoAxis_July12_2026.md`'s Vigilance/
Opportunism migration — see the doc's own closing note at the top for the
per-item disposition. `decide_play()` now has zero bare `if difficulty ==
...` checks anywhere. Kept as the historical record of the reasoning; no
longer a live recommendation doc.

---

## Tier 2 — Dated session summaries (chronological) — **ARCHIVED July 14, 2026**

Every doc in this tier has been moved to `archive/` (same filename). Fully
superseded by Onboarding + the current Tier 1 docs above; kept here for
historical reference only — one exception worth flagging: `archive/Texas_42_Session_Summary_July_12_2026_DifficultyModesDesign.md`
carries high-value stress-test tables behind the Vigilance/Opportunism
design that would be expensive to reconstruct, so it's worth keeping easy
to find even though archived.

| Date | Doc | Covers |
|---|---|---|
| Jul 1 | `Texas 42 — Session Summary (July 1 2026 v2).md` | Establishes the four-phase model (Cooperation/Risk/Opportunism/Awareness), Win Safety concept, counter-dumping bug (Phase 1), Points-vs-Marks gap, bidding Layers 1–3. Good doc for "why do we have four phases" and early Phase 1 gaps. (Note: this doc's actual filename uses spaces/em-dash/parens — earlier versions of this map cited an underscored filename that doesn't match any file on disk; corrected here.) |
| Jul 4 (RankingUnification) | `Texas_42_Session_Summary_July_4_2026_RankingUnification.md` | The ranking split-brain bug (fixed), MARKS/Plunge/Splash objective fix, the six `PublicKnowledge` queries confirmed implemented, the Nello-low playtest trace, and Finding 3 (orphaned settings, including the first flag on `nello_doubles_reversed`). **Good doc for ranking/comparison bugs and the orphaned-settings list.** |
| Jul 5 (Phase2Architecture) | `Texas_42_Session_Summary_July_5_2026_Phase2Architecture.md` | The session that produced `Phase2_Control_Layer_Audit.md` and found the original `trust_gate` bug (its reason string couldn't mean what its own condition tested) — this is where BUG-005 was first identified, before the fix spec existed. Good doc for the origin story of BUG-005 and the Selection/Commitment/Modulation model. |
| Jul 5 (prep, superseded in places) | `Texas_42_Next_Session_Prep_July_5_2026.md` | Written the night before as a prep doc, not a summary. Its Nello "Reversed" toggle bug write-up (§1) is retracted — that feature works correctly now. Its `trust_gate`/`trust_threshold` design-conversation framing (§3) is superseded by the same day's later BUG-005 fix and by `Difficulty_Feed_Points_Inventory.md` — both are marked with inline correction notes rather than removed, so read the corrections, not just the original prose. |
| Jul 6 (BranchTracePart1) | `Texas_42_Session_Summary_July_6_2026_BranchTracePart1.md` | First half (#1–#11 of 28) of the full branch-by-branch trace against `Phase3_Objective_Audit.md`. Covers BUG-006/BUG-007 (logged at the time, not yet implemented — **BUG-006 has since been fixed July 9, 2026**, see `AI_Play_Behavior_Bug_Log.md`; BUG-007 is still open), the branch #8 low-trump-lead fix, and branch #11's generalized guaranteed-win detection — all implemented and pushed. |
| Jul 6 (BranchTracePart2) | `Texas_42_Session_Summary_July_6_2026_BranchTracePart2.md` | Second half (#12–#28), completing the trace. Covers the removal of branches #17 and #19 (no legitimate strategic basis, same violation class), the new `GIFT_A_VOID`/partner-side `FORCE_A_VOID` capability (branches 6a/6b), and the Partner/Opponent difficulty-coupling architectural finding — all implemented and pushed. **Good doc for "why was branch X removed" or "why does the partner now know about void suits."** |
| Jul 9 (BiddingAudit) | `Texas_42_Session_Summary_July_9_2026_BiddingAudit.md` | The bidding audit that measured `evaluate_hand()`/`decide_bid()` against 20 real in-game hands with Katy's verdicts and found it bid 0 of 20. Origin of the four evaluator findings (#1–#4) fixed July 12 — see `AI_Bid_Behavior_Bug_Log.md` Pattern C and `Texas_42_AI_Bidding_Structure_Overview.md`. Good doc for the "why did we retune the evaluator" origin story. |
| Jul 12 (BiddingFixPackage) | `Texas_42_Session_Summary_July_12_2026_BiddingFixPackage.md` | The spec and verification table for the four-fix bidding evaluator package (off-suit rank floor, off-suit-doubles compounding, trump-majority control, counter-realization inclusion), implemented the same day. Good doc for the exact before/after numbers on the spot-check hands. |
| Jul 12 (DifficultyModesDesign) | `Texas_42_Session_Summary_July_12_2026_DifficultyModesDesign.md` | The design reasoning behind the Vigilance/Opportunism two-axis model that replaced every remaining bare `if difficulty == ...` branch in `decide_play()`, implemented the same day. Good doc for "why vigilance and opportunism specifically, not some other axis shape." |
| Jul 12 (SettingsToggleAudit, CLOSED) | `Texas_42_Settings_Toggle_Audit_CLOSED_July_12_2026.md` | Closing summary of a settings/toggle audit that grew from one question ("does Partner Sits Out actually work?") into a full pass over all ~53 `GameSettings` variables. Three real features built (Force Trump on Opening Lead, Doubles Trump Reversed, Small-End Opening Lead, Nello/Sevens Only on Forced Bid), ~23 dead settings deleted, and the entire Low-No contract removed. Good doc for "does setting X actually do anything" — audit is closed, every setting is accounted for. |

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
pattern. **Corrected July 15, 2026** — this entry had drifted from the
log's own Summary section on three points (BUG-002/002b, BUG-007, and
BUG-012 were all still shown here as open when the log itself had already
marked them fixed); see `Backlog_Triage_Combined_July15_2026.md`'s sourcing
note, which is what caught it. Pattern A ("guaranteed trick" detection too
narrow — BUG-002/002b/004): **all three fixed as of July 13, 2026**
(BUG-002/002b via BUG-013's combined fix; BUG-004 drops a stranded counter
when last-to-act on an already-decided trick, gated by the same
opportunism roll as the can-win contest decision).
**Pattern B (BUG-003/003b, lead-priority ordering) is fixed as of July 5,
2026.** **Pattern E (BUG-006/BUG-007/BUG-009, counter safety at leading
branches): all three fixed** (BUG-006 July 9, BUG-009 July 12 — leads a
counter-double on reasonable confidence instead of gating on provable
safety — and BUG-007 July 13, jointly with BUG-012 via the Lead-Safety
Priority Stack, see Pattern H).
**Pattern F (BUG-008, forced overtake; BUG-011, a latent guaranteed-win
bug BUG-008's own refactor surfaced; and BUG-013, a self-exclusion bug in
`_is_guaranteed_win()` that retroactively affects branch #11 too) are all
fixed as of July 12/13, 2026.** **Pattern G (BUG-010, low-lead technique
doesn't exclude counters; BUG-014, the same low-lead technique kept
firing after the double it was drawing out had already been played) are
both fixed as of July 13, 2026.** **Pattern H (BUG-012, `FORCE_A_VOID`'s
`void_leads` accepted partial opposing-team voidness instead of requiring
all) is fixed as of July 13, 2026**, jointly with BUG-007, via the new
Lead-Safety Priority Stack. **Currently open:** BUG-015 (new, log entry
only — switching leads between two doubles before both opponents are
proven void in trump, needs its own design session) and Pattern C's
opponent-side mirror of BUG-001 (Partner side fixed July 13, 2026;
opponent-side discard block has the identical defect, deliberately left
open pending a vigilance-gating decision). Status-keyed
(✓ fixed / → ready / ⏳ waiting on Phase 4 / ⚑ needs examples). **Check here
before assuming a play-decision oddity is new — it may already be a known,
categorized bug with a fix shape written.**

**`AI_Bid_Behavior_Bug_Log.md`** — same idea, bidding side. **Pattern A
(the Marks-bid-gate double defect) is fixed as of July 5, 2026.** **Pattern
C (four evaluator findings from the July 9, 2026 bidding audit — off-suit
rank floor, off-suit-doubles compounding, trump-majority control, counter-
realization inclusion) is fixed as of July 12, 2026**, with three logged
known limitations flagged for a future capabilities-layer pass, not a
re-tune. Pattern B (trump rank blindness) is marked "likely resolved already" pending an
actual verification pass against real hands — that verification hasn't
happened yet as far as this doc set shows.

**`AI_Explanation_Bug_Log.md`** — reason-string mismatches (wrong tone,
wrong actor, inaccurate belief state), example-numbered rather than
pattern-numbered. Added to this repo July 6, 2026 — a first-pass log (one
game context, originally Issues 1–7, now through Issue 9) written to find
where structure was needed before pausing to build that structure; the next
testing pass will likely start a fresh log rather than append here. Two
entries (Issues 3/6) were marked ✓ at the time but the described fix had
never actually been applied to the code — caught during reconciliation and
implemented for real the same day (see `ai_player.gd`'s `human_is_winning`
partner-following block). This is the intake log the Phase 1 reason-string
rewrite spec draws from. **Issue 8 (added July 13, 2026)** covers the new
forced-overtake strings from BUG-008's fix. **Issue 9 (added July 13,
2026)** finally logs the `value_gate` reason-string gap flagged in three
other docs — resolved by retirement, not a string patch, since the code
path that produced the inaccurate string no longer exists. Also caught, and
**cleaned up the same day**, three unreachable dead-code fragments in the
opponent-following discard block left over from that retirement.

**`Backlog_Triage_Combined_July15_2026.md`** — a cross-cutting index over
the three bug logs above plus unlogged design threads (capabilities layer,
Monte Carlo lab, priority-ordering, mobile layout), sorted into Alpha
Blocker / Quality / Future Architecture / Research. Deliberately has no
symptom/fix detail of its own — every line points back to its real home.
Snapshot, not a living structure — will drift the same way anything else
does if left unrevisited after bugs get fixed.

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
  `Phase3_Objective_Audit_REWRITE_July14_2026.md` first (has the actual
  branch table), then `AI_Design_Doctrine.md` for the Knowledge/Evaluation/
  Neither litmus test (moved out of Onboarding §4 into the doctrine doc,
  July 14, 2026).
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
- **"What's still open right now, sorted by what actually needs doing
  first?"** → `Backlog_Triage_Combined_July15_2026.md` — check the
  relevant bug log for the actual detail behind any given line.
- **"Why is a reason string worded oddly?"** → `AI_Explanation_Bug_Log.md`.
- **"What should happen to the six bare `difficulty ==` branches?"** →
  Nothing — already resolved. `decide_play()` has zero bare `if difficulty
  == ...` branches left as of the July 12, 2026 Vigilance/Opportunism
  migration (see Onboarding §4). `Difficulty_Feed_Points_Inventory.md`
  (archived) has the per-branch disposition if you need the history.
- **"Does the MARKS cardinal rule still need a design decision?"** → No,
  resolved July 5 — see `Phase1_Control_Layer_Audit.md`.
- **"Is `trust_gate`/`trust_threshold` still about trust?"** → No. See
  BUG-005 in `AI_Play_Behavior_Bug_Log.md`, and the correction notes in
  `Phase3_Objective_Audit_REWRITE_July14_2026.md` and
  `Phase2_Control_Layer_Audit.md`.
- **"What's the overall four-phase roadmap?"** → Jul 1 summary (origin),
  Onboarding §6 (current state).
- **"How do I run a headless Monte-Carlo-style experiment against the AI?"**
  → `Headless_Harness_Reference.md` — conventions, template, gotchas, all in
  one place. Don't re-derive turn order or `is_partner` wiring from
  `game_table.gd` again.

---

## Known documentation debt (not urgent, just tracked)

- **Closed, July 14, 2026** — five session summaries referenced by earlier
  drafts of this map (`Texas_42_Session_Summary_July_2_2026.md`,
  `Texas_42_Session_Summary_July_4_2026.md` plain/Phase B,
  `..._PublicKnowledge.md`, `..._PhaseC_HandRecordUI.md`, and
  `..._TurnPacingAndSevens.md`) were confirmed genuinely absent from this
  repo, not a listing error — they were archived elsewhere by Katy before
  this doc set's current form existed. Not documentation debt; don't add
  them back or search for them. Check Onboarding first for the code-side
  facts they'd have covered.
- **`AI_Bid_Behavior_Bug_Log.md` Pattern B** (trump rank blindness) is
  marked "likely resolved already" via hand-recomputation, not an actual
  playtest verification. Worth an explicit verification pass to close it
  out for real rather than leaving it as a confident guess.
- ~~**The `value_gate` (#25) reason-string gap**~~ **Moot, July 12, 2026** —
  `value_gate`/branch #25 no longer exists; retired entirely by the
  Vigilance/Opportunism migration rather than fixed. The reflexive path
  that replaced it has its own new placeholder string ("Taking this one."),
  itself flagged for the strings-pass session — a new entry, not the old gap.
- This map itself was significantly out of date until July 5-6, 2026 — nine
  of the eighteen `.md` files in the repo (as of July 5) weren't listed here
  at all, and several entries described pre-BUG-005/pre-BUG-003 states.
  `AI_Explanation_Bug_Log.md` (making it nineteen files) arrived July 6. If
  you're reading this after a substantial gap, do a fresh `find *.md`
  against this map's file list before trusting it fully.
