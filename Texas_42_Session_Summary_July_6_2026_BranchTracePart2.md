# Texas 42 — Session Summary (July 6, 2026): Phase 3 Branch Trace, Part 2 (#12–#28) — Trace Complete

*Purpose: same consolidation role as
`Texas_42_Session_Summary_July_6_2026_BranchTracePart1.md`, covering the
back half of the branch-by-branch trace against `Phase3_Objective_Audit.md`'s
table (#12–#28, completing the full 1–28 pass started in Part 1). Two
removals, one two-part new capability, one architectural finding, and one
deliberately-deferred item. Everything marked implemented in this doc has
already been committed and pushed — see the specific commits cited below,
not a to-do list this time.*

---

## Branch trace status (#12–#28 of 28)

**Confirmed clean, no action, matches `Phase3_Objective_Audit.md` exactly:**
**#12** (`PROTECT_PARTNER_WIN`, non-guaranteed-win case — its stale
condition-phrasing note, "no double" vs. the real `not guaranteed_win` gate,
was already corrected prior to this trace pass; not re-flagged here), **#15**
(`SECURE_FOR_PARTNER`, expert trump-only commit — the concrete anchor for the
still-open `cooperation_bias`/trust-naming question, no action), **#16**
(`SECURE_FOR_PARTNER`, standard trump-only commitment gate — fully rewritten
under BUG-005, confirmed matching current code), **#20** (`FORCE_A_VOID`,
opponent-leading, expert + knowledge-gated — confirmed correctly scoped; the
July 4 "highest vs. lowest into a void" judgment call is still unconfirmed by
playtest, worth checking next time it comes up), **#22**
(`LOCK_IN_COUNTER_LEAD` — explicitly checked against BUG-006 and confirmed
distinct: different role, `is_partner` vs. opponent, different rigor by
design, not a duplicate fix), **#23** (unnamed leading fallback), **#24**
(`PROTECT_PARTNER_WIN`, opponent mirror), **#26** (`CASH_COUNTERS`), **#27**
(`SECURE_FOR_PARTNER`-equivalent, opponent plain win), **#28** (`ESCAPE`,
opponent can't-win, duplicate pair with #17/#18).

**#18** (`ESCAPE`, standard/expert can't-win discard) is confirmed clean and
now also absorbs beginner's case — see the #17 removal below; #18's own row
in `Phase3_Objective_Audit.md` didn't need its own edit since #17's row
already documents the collapse.

**Confirmed clean but deliberately left as-is** despite visible asymmetry —
per Katy's standing position that opponents playing very slightly
sub-optimally is an acceptable, even desirable, subtle advantage for the
human, not a bug to fix:
- **#21** — opponent-side `CONTROL_TRUMP` never received the two upgrades #8
  got (double-aware threshold from BUG-003b, low-lead-to-draw-the-double
  technique from July 6). Flagged, consciously left alone.
- **#23** — opponent-leading fallback has no counter-protection tier the way
  partner's equivalent (#9/#10) does; can lead a counter straight into the
  highest-available pick. Flagged, consciously left alone.
- **#24** — opponent-side `PROTECT_PARTNER_WIN` has no guaranteed-win/
  dump-counters variant the way #11 gives the partner side. Flagged,
  consciously left alone.

**Confirmed clean, minor doc-accuracy note only, no code implication:**
**#14** — the "prefer non-trump winners" filter was traced in detail and
shown to be geometrically redundant with what `Trick.get_legal_moves()`'s
strict follow-suit enforcement already guarantees (`can_win` is provably
always either fully non-trump or fully trump, never a genuine mix —
confirmed against `trick.gd`). The branch still does necessary dispatch work
(routing follow-suit wins to their own reason string before falling into
#15/#16's trump-specific logic), so it's not dead code, but the comment's
"prefer non-trump... to save trump" framing describes a choice that
structurally never occurs. No behavior change needed or made.

---

## Findings this session — behavior removed (✓ implemented, committed, pushed)

### Branch #17 — beginner "discard highest first"

`decide_play()`, partner-following, can't-win discard block. Beginner
discarded the highest safe non-counter/non-trump tile first, stated
rationale "protect every pip we have." Traced and confirmed the rationale
doesn't hold: the pool it draws from (`safe_high`) already excludes counters
identically to the standard/expert pool (`non_counters_discard`) — the
choice of highest-vs-lowest within that pool has zero effect on counter
safety either way. Katy's read: not a believable skill gap, a reasoning
error — violates "goals change, not IQ."

**Status: removed entirely.** Beginner now shares #18's logic exactly. No
other code depended on the removed block — `safe_high` was locally scoped,
its reason string appeared nowhere else. Doc updates done in the same pass:
`Phase3_Objective_Audit.md` (row #17 struck and annotated, duplication-pairs
list, `AI_MODES` candidates table), `Difficulty_Feed_Points_Inventory.md`
(new item #8), `Phase2_Raw_Concept_Audit.md` §10 (split #13 from #17 — they
were never the same kind of thing).

### Branch #19 — beginner "never lead trump on opening trick"

`decide_play()`, opponent-leading, first check. Beginner unconditionally
avoided leading trump on trick one, even with genuine trump control (3+
trumps, possibly the double) — this had been the audit's own confirmed "one
true selection-level exception" to difficulty-invariant Selection. Katy's
sharpened framing this session: beginner AI opponents/partners should know
the game and play it soundly, just less thoroughly (no void-tracking, less
ruthless) — not apply categorical strategy overrides that ignore hand
quality. Same violation shape as #17.

**Status: removed entirely**, taking the `FEEL_OUT_THE_HAND` objective with
it. Beginner now goes straight into the void-targeting/trump-control logic
everyone else uses on trick one. `Phase3_Objective_Audit.md`'s row for #19
is corrected (the "confirmed: the one true selection-level exception" claim
retracted, not just struck), along with every other doc that named
`FEEL_OUT_THE_HAND` as a standing exception: `Phase2_Control_Layer_Audit.md`,
`Phase2_Raw_Concept_Audit.md` §16 (including the in-code "OPPONENT BEHAVIOR"
comment this section's correspondence list points at, which was itself
stale and has been fixed), and `Texas_42_Project_Onboarding.md`. The in-code
Trick Objectives header in `ai_player.gd` itself was also rewritten — this
doc's own "no genuine Neither-category exception remains standing" framing
is now the corrected, current state, not a pending correction.

---

## Findings this session — new capability, two-part gap (✓ implemented, committed, pushed)

### The gap

Traced against #20 (`FORCE_A_VOID`, opponent-leading, expert +
knowledge-gated), Katy asked whether an equivalent existed for
partner-leading. It didn't — the entire partner-leading block (#7–#10)
never consulted `PublicKnowledge` at any difficulty. Two distinct, related
capabilities were identified to close this, both now live in
`ai_player.gd`'s `is_partner and is_leading` block, in this execution order:
Spec 4's check first, then Spec 3's, then the existing trump-control check
(#8) continues unchanged below both.

### Spec 3 — partner-side void lead, self-assessed high/low (new branch 6b)

Mirrors #20 for the partner side: if the opposing team is known-void in a
suit (`public_knowledge.void_suits()` on the two non-partner seats), lead
into it. Unlike #20's opponent-side version, this adds a real strategic
wrinkle Katy identified: the choice of which tile to lead (highest vs.
lowest within the void suit) is a self-assessment gamble — "if I don't have
a strong lead of my own to keep, maybe the human does" — not
contract-margin-driven (the first candidate considered and rejected) and not
knowledge of the human's actual hand (never available). Self-assessment
signal settled as: does this seat have its own trump control (#8's
threshold) or a safe off-suit lead (#7's filter) available for next trick?
If yes, lead the highest void tile (keep the initiative). If no, lead the
lowest (pass the initiative — no cost if it doesn't work, either the human
takes it with something better, or it wins anyway by accident). Reason
strings: `"Leading a suit our opponents can't follow."` (strong case) /
`"Opponents are void - hoping you can take the lead."` (weak case).

**Correction made mid-session, also implemented:** this was originally
gated `difficulty == "expert"`, mirroring #20. Caught and corrected before
finalizing — see the Architectural Finding below. The gate is removed;
only `public_knowledge != null` remains. Katy's framing: partner should
always play its best cooperative game regardless of difficulty; the only
real limiter is knowledge availability, not the chosen difficulty tier.

### Spec 4 — free discard for a known-void partner (new branch 6a)

The mirror-image gap Katy raised in the same conversation: not "opponents
are void," but "the human is void" — a genuine opportunity to hand the
human a free discard (potentially a counter) on a trick they structurally
can't follow suit on. Explicitly **not** built to #11's full guaranteed-win
standard (double-or-provably-highest *and* trump-exhausted) — Katy's
real-table reasoning: real players take reasonable-confidence leads, not
just guarantees, and the downside risk here (an opponent trumping in, or
the human simply not having anything worth dumping) isn't something the
leading AI can know or is responsible for — it's only responsible for
creating the opening. Trigger: the double, or the currently-highest-
remaining-in-suit tile (`best_remaining_card_for_suit()`, reused from #11,
without #11's added trump-exhaustion requirement), in a suit the human is
known void in. No difficulty gate, same reasoning as Spec 3's correction.
Runs *before* Spec 3's check — a likely free discard for the human outranks
the more speculative keep/pass gamble on opponents when both conditions
happen to apply at once. Reason string: `"Giving you a free discard."`

**Naming, added during doc reconciliation:** given a name in
`Phase3_Objective_Audit.md`/`Texas_42_Project_Onboarding.md` —
`GIFT_A_VOID` — the mirror-image objective to `FORCE_A_VOID` (opening an
opportunity instead of forcing a cost), rather than left unnamed.

Doc updates for both specs, all done in the same pass: `Phase3_Objective_
Audit.md` (new rows 6a/6b, objective-vocabulary section, duplication-pairs
list now including `FORCE_A_VOID`: #20/6b), `Difficulty_Feed_Points_
Inventory.md` (explicit note that these deliberately never entered that
inventory — the difficulty gate was removed before shipping),
`Texas_42_Project_Onboarding.md` (Trick Objectives list, new Consumer 4
bullet), `Phase1_Cooperation_Audit.md` (pointer note explaining why these
weren't folded into that doc's own partner-leading table — out of its
stated Phase 1 scope), and the in-code Trick Objectives header in
`ai_player.gd` itself.

---

## Architectural finding — Partner/Opponent difficulty coupling

Confirmed a real, previously-flagged-but-unresolved issue while reviewing
Spec 3's gate: `game_settings.ai_difficulty` is a single value applied
uniformly to both partner and opponent AI. The July 1/2 session summaries
already named this as a long-term concern — partner difficulty should
affect judgment quality (cooperation intent stays constant, sharpness
varies); opponent difficulty should affect competitive intensity
(aggression, opportunism, awareness). Currently the same difficulty string
drives both.

Spec 3, as originally drafted this session, violated this by gating a
partner capability behind `difficulty == "expert"` — meaning a
beginner-difficulty game (chosen by the human for an easier experience
against opponents) would silently also give them a worse partner, which
contradicts the stated intent. Caught and corrected within the same session
(see Spec 3's amendment above — implemented). **This is not a full
resolution of the underlying architectural note** — that would mean
splitting `AI_MODES`/difficulty into separate partner and opponent parameter
sets, which remains a larger, not-yet-scheduled change. This session's fix
is local: no future partner-side knowledge-gated branch should default to
difficulty-gating without checking this note first.

---

## Deferred to a future session — not specced today

**`value_gate` (#25) needs the same table-scenario treatment `trust_gate`
(#16) got.** Already flagged as unvalidated in `Difficulty_Feed_Points_
Inventory.md` prior to this session ("hasn't gotten the #16 treatment yet").
Raised again this session: Katy asked whether beginner-only gating made
sense here, and the honest answer is nobody has checked — the gate
currently only weighs trick value already on the table
(`_estimate_trick_value`), never the cost of winning (what tile would need
to be spent). That's a likely reason it reads as beginner passivity rather
than genuine economy. Deliberately not tackled today — this needs the same
real-table-scenario process #16 got, not a quick patch, and deserves its own
session per the established scope-discipline principle (judgment-heavy
design work stays separate from trace/spec sessions). Good candidate for
next session's primary focus.

---

## Doc-update checklist — ✓ all done (July 6, 2026)

Every item is complete and pushed (commit `9b448e8`, "Remove branches
#17/#19; add GIFT_A_VOID and partner-side FORCE_A_VOID").

- [x] `ai_player.gd`: branches #17 and #19 deleted; branches 6a
      (`GIFT_A_VOID`) and 6b (`FORCE_A_VOID` partner mirror) added, both with
      the difficulty gate removed per the amendment; in-code Trick
      Objectives header rewritten (objective list, grain note, per-objective
      Phase 3 classification, "Net effect" paragraph); stale "OPPONENT
      BEHAVIOR" comment fixed.
- [x] `Phase3_Objective_Audit.md`: rows #17/#19 struck and annotated as
      removed; new rows 6a/6b inserted at their actual execution position;
      objective-vocabulary section, duplication-pairs list, and `AI_MODES`
      candidates table all updated; row #8's stale `#17` cross-reference
      fixed while in there.
- [x] `Difficulty_Feed_Points_Inventory.md`: item #1 (`FEEL_OUT_THE_HAND`)
      and new item #8 (branch #17) both marked removed; "why this isn't
      uniform" and "recommended next steps" sections updated; explicit note
      added that 6a/6b deliberately never entered this inventory.
- [x] `Phase2_Control_Layer_Audit.md`: Selection-category table's
      `FEEL_OUT_THE_HAND` row corrected.
- [x] `Phase2_Raw_Concept_Audit.md`: §10 split #13 from #17 (they were never
      the same kind of thing); §16's opponent-behavior correspondence list
      corrected.
- [x] `Texas_42_Project_Onboarding.md`: Trick Objectives list and
      "Architectural status" paragraph corrected for `FEEL_OUT_THE_HAND`'s
      removal; `GIFT_A_VOID` added; new Consumer 4 bullet for both new
      `PublicKnowledge` call sites; freshness date bumped.
- [x] `Phase1_Cooperation_Audit.md`: pointer note added explaining the scope
      boundary (lead-technique choice is Phase 2/3 territory, not folded
      into this doc's Phase 1 table).

---

## On the horizon

- **The full #1–#28 branch-by-branch trace is now complete** (Part 1 covered
  #1–#11, this document covers #12–#28). No branches remain untraced against
  `Phase3_Objective_Audit.md`.
- `value_gate` (#25) — needs its own real-table-scenario session, same
  format `trust_gate` (#16) got. Candidate for next session's primary focus.
- The Partner/Opponent difficulty-coupling architectural finding (above) —
  not scheduled, but flagged for whenever `AI_MODES`/difficulty splitting
  is next discussed.
- BUG-006 and BUG-007 (from Part 1) remain open, logged-not-implemented —
  unaffected by this session's work.
- Reason-string rewrite remains explicitly its own separate session, per
  Katy's standing call — not folded into trace work. `GIFT_A_VOID`/`FORCE_A_VOID`'s
  two new reason strings ("Giving you a free discard.", "Leading a suit our
  opponents can't follow.", "Opponents are void - hoping you can take the
  lead.") should go through that pass like every other string, not be
  treated as already-final just because they shipped this session.
