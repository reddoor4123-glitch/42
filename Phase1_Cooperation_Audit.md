# Phase 1 — Cooperation Audit

*Companion to `Phase3_Objective_Audit.md` and `Phase2_Control_Layer_Audit.md`.
Where those audits mapped Selection (objective choice) and Commitment/Modulation
(how confidently an objective is acted on), this audit covers the layer beneath
both: does the partner's code correctly encode *whose side it's on*? Per the
four-phase model, a broken Phase 1 makes every other phase's tuning meaningless
— so this audit treats correctness here as a precondition, not a preference.*

**Status key:** ✓ Confirmed correct | → Confirmed bug, ready to fix | ⚑ Design
question, not a bug | ⏳ Blocked on a later phase

---

## Scope

Phase 1 lives in exactly two places in `ai_player.gd`'s `decide_play()`:

1. **The cardinal rule** — the `human_is_winning` branch under `is_partner`,
   following logic. This is the rule: *never steal a trick the human is
   already winning.*
2. **Partner leading logic** — the `is_leading` branch under `is_partner`.
   This is the rule's proactive half: *lead in a way that helps the human,
   not just avoid hurting them.*

Everything downstream of "is this objective the right one for a cooperative
partner" — how confidently it's pursued, whether it's re-evaluated under
uncertainty — is Phase 2/3 territory and out of scope here, even where the
same branch contains both kinds of logic (noted explicitly where that
happens, since it's a common source of miscategorized bugs in this codebase).

---

## 1. Cardinal rule — partner following, `human_is_winning == true`

| Sub-case | Condition | Current behavior | Status |
|---|---|---|---|
| Guaranteed win (double led) | `winning_domino.is_double()` | Dump highest counter if one is legal; else lowest tile | ✓ Correct — this is the fixed version of the old "Gap 1" (see §4) |
| Uncertain win, counter available | not a double, non-counters exist | Play lowest non-counter — protect all counters | ✓ Correct as the general case |
| Uncertain win, forced to burn a counter | not a double, only counters legal | Play lowest counter | ✓ Correct — forced case, no better option exists |

**Read on this branch:** this is the one part of Phase 1 that's actually in
good shape. The double-led guaranteed-win case correctly overrides counter
protection, and the fallback correctly restores protection once the win is
uncertain again. No open bugs here.

**One adjacent item, not a bug:** the guaranteed-win detection is currently
*only* the double-led case. Two other ways a trick can be "locked in" —
last-to-play position, and a known-safe high trump — are tracked separately
in `AI_Play_Behavior_Bug_Log.md` (Pattern A, BUG-002/002b/004). Those are
real gaps, but they're opponent-side and Phase-4-blocked respectively, not
partner cardinal-rule bugs — flagged here only so the "guaranteed win" concept
doesn't get treated as fully solved just because the partner-double case is.

---

## 2. Partner leading logic

Current code, in evaluation order:

```gdscript
if is_leading:
    # 1. Safe off-suit lead
    var off_safe = legal.filter(not trump, not counter)
    if off_safe.size() > 0: return highest(off_safe)   # "Opening a safe suit..."

    # 2. Trump control
    var trumps = legal.filter(is_trump)
    if trumps.size() >= 3: return highest(trumps)      # "I have trump control..."

    # 3. Counter-safe lead
    var non_counters_lead = legal.filter(not counter)
    if non_counters_lead.size() > 0: return highest(non_counters_lead)

    # 4. Forced counter lead
    return highest(legal)
```

| Sub-case | Status | Notes |
|---|---|---|
| Safe off-suit lead (#1) | ✓ Correct | Sound default: give the human something safe to follow |
| Trump control (#2) | ✓ **Fixed — BUG-003/003b (July 5, 2026)** | See below |
| Counter-safe lead (#3) | ✓ Correct as a fallback | Only reachable when #1 and #2 both fail |
| Forced counter lead (#4) | ✓ Correct | Genuinely forced, no better option |

### ✓ BUG-003 / BUG-003b belongs to Phase 1, not just "a play bug" (Fixed July 5, 2026)

This is already tracked in `AI_Play_Behavior_Bug_Log.md` Pattern B, but it's
worth stating plainly here: **this is a Phase 1 correctness bug**, not a
tuning issue. Trump control is a cooperative leading strategy — drawing out
opponents' trump to clear the way for the team — and the current code makes
it unreachable dead logic whenever the partner also happens to hold any safe
off-suit tile, which is most hands. The intent ("lead in a way that helps
the human") is present in the code but structurally can't fire. That's
exactly the kind of gap this audit exists to catch: not a missing feature,
a correct rule that's silently unreachable.

**Fix shape (unchanged from the bug log):** evaluate trump control (#2)
before the safe off-suit check (#1) whenever trump count clears the
control threshold; the exact threshold (3 vs. 4, and whether "no double"
changes it) is the one open judgment call, flagged ⚑ in the bug log pending
more examples — that sub-question is Katy's to settle, not blocking the
reordering itself.

**✓ Fixed (July 5, 2026).** Trump control now runs before the safe off-suit
check, with a double-aware threshold: 3+ trumps if the holding includes
the double, 4+ otherwise. This also settles the threshold judgment call
above rather than leaving it open.

---

## 3. MARKS / PLUNGE / SPLASH — cardinal rule override question

The dedicated MARKS/PLUNGE/SPLASH block (added since the original "Gap 2"
was identified — see §4) currently preserves the cardinal rule as a safe
default:

```gdscript
if is_partner and human_winning_marks:
    return lowest(legal)   # "You've got it — saving my strength."
```

**Status: ⚑ open design question, not a bug.** Under Marks/Plunge/Splash,
every trick matters — there's no "give count, doesn't matter which trick
wins it" slack the way there is under a points contract. The question this
audit surfaces (matching `Phase2_Control_Layer_Audit.md`'s framing) is
whether a cooperative partner should ever *contribute a stronger tile than
strictly necessary* to a trick the human is already winning, purely to make
that specific trick more secure against a late overtrump — as opposed to
always yielding lowest. This is currently deferred pending concrete example
hands from Katy, and this audit doesn't resolve it — it's flagged here
because it's squarely a Phase 1 question (intent), not Phase 2/3.

---

## 4. Verification of the two originally-tracked Phase 1 gaps

Both gaps named in the July 1–2 session summaries as "the two known bugs"
are now implemented and confirmed correct in current code:

- **Gap 1 (counter-dumping on guaranteed win)** — ✓ implemented. Confirmed
  in §1 above: the `winning_domino.is_double()` branch now dumps counters
  instead of protecting them.
- **Gap 2 (Points vs. Marks distinction)** — ✓ implemented. Confirmed in §3
  above: a dedicated `BidScript.Type.MARKS`/`PLUNGE`/`SPLASH` block now
  exists near the top of `decide_play()`, separate from standard counter
  logic.

**These should be marked closed** in whatever roadmap doc still lists them
as open (`Texas_42_Documentation_Map.md` / onboarding). The only piece of
Gap 2 still genuinely open is the cardinal-rule-under-Marks question in §3,
which is a new, narrower question — not the original gap.

---

## 5. Reason-string debt that's specifically Phase-1-shaped

Three entries in `AI_Explanation_Bug_Log.md` sit directly on cardinal-rule
code paths and are worth calling out as a Phase 1 subset of that rewrite,
not generic polish:

- **Issue 1** — a forced follow-suit counter-protection play reads as a free
  "discarding low" choice. This misrepresents the cardinal rule's cost as
  optional when it wasn't.
- **Issue 7** — bland yield string on the cardinal rule's non-counter path
  (`"staying out of your way"`). Not wrong, just doesn't reflect that this
  is the partner *choosing* team-first play, which is the entire point of
  Phase 1 as a design pillar.
- The **MARKS cardinal-rule branch (§3)**, once resolved, will need its own
  string — currently it borrows the standard-contract yield string verbatim,
  which will misstate intent if the resolution in §3 changes the underlying
  behavior.

These are already captured in the general Phase 1 reason-string rewrite
(~24 strings, specced, not yet applied) — flagged here only so that rewrite
pass treats the cardinal-rule strings as highest priority, since they're the
lines a new player is most likely to read as "the AI explaining what kind of
partner it's being."

---

## Summary — suggested order of attack

1. **Close out Gaps 1 and 2 in tracking docs** — zero code work, just
   correcting stale status in the Documentation Map / Onboarding doc.
2. ~~**Fix BUG-003/003b (trump-control lead ordering)** — the one confirmed,
   in-scope Phase 1 bug. Needs the trump-count threshold judgment call
   settled first (⚑), but the reordering fix shape itself is agreed.~~
   **✓ Fixed July 5, 2026** — see §2 above.
3. **Decide the MARKS cardinal-rule override question (§3)** — needs
   example hands from Katy before it can be specced either direction.
4. **Fold the three Phase-1-specific strings into the reason-string
   rewrite pass** when that work is picked back up, prioritized ahead of
   the other ~21 strings in that spec.

Net read: **Phase 1 is closer to done than the "two known bugs" framing
suggested** — both original gaps are fixed, and BUG-003/003b (the
lead-ordering bug) is now fixed too (July 5, 2026). What's left is one open
design question (needs Katy's examples), not a broad correctness problem.
