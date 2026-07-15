# Phase 3 Objective Audit — `decide_play()` (v2, rewritten for clarity)

*Companion to the "TRICK OBJECTIVES" header block in `ai_player.gd`. Rewritten
July 14, 2026 to reflect the current, live branch structure directly —
the previous version (v1) had accumulated a year's worth of layered
"superseded"/"correction" notes on top of a branch numbering that no longer
matches the code, particularly in partner-leading, which was substantially
rebuilt July 13, 2026 (the Lead-Safety Priority Stack). v1 is archived, not
deleted — it's the historical record of how each finding was reached, which
this rewrite deliberately does not repeat. If you want the "why," the bug
logs (`AI_Play_Behavior_Bug_Log.md` in particular) are the place; this
document is the "what, right now."*

**Verification note:** the partner-leading, partner-following, and
opponent-following sections below are confirmed against direct quotes of
the current `ai_player.gd` source, re-checked in this rewrite pass. The
opponent-leading section (branch 20-23 area) is confirmed only via a
cross-reference in `Texas_42_Project_Onboarding.md` stating it received the
narrower any→all safety fix without being restructured — treat that one
section as reliable-but-not-freshly-quoted if it matters for a future spec.

---

## System model (unchanged from v1 — still accurate)

```
SYSTEM ROUTER
├── Mechanical override — no geometry interpreted, decide_play() is
│   fully bypassed (SEVENS, NELLO)
│
└── Geometry-driven objective system — everything else
      geometry → objective (Selection) → commitment gate (optional) → execution
```

- **Selection** — which objective applies, decided from decision geometry
  (`partner_winning`, `can_win`, void state, trump count). Difficulty-invariant
  in every case except the two mechanical overrides.
- **Commitment gate** — a costlier objective is geometrically reachable but
  needs a scalar/deterministic check to pass before committing. On failure,
  falls back to `ESCAPE`'s action — never a different objective. One
  confirmed instance today: branch #16 (`SECURE_FOR_PARTNER`, trump-only).
- **Execution** — same objective, same selection; only play quality differs
  (e.g. which trump to lead, non-trump preference).

**`ESCAPE` meaning constraint (unchanged):** describes a no-winning-state
belief, not a generic discard action. A commitment-gate failure may reuse
`ESCAPE`'s action logic but does not inherit its belief — the AI at a
failed gate believes it *could* win and is choosing not to.

---

## Objective vocabulary (current)

`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`, `ESCAPE`,
`CONTROL_TRUMP`, `FORCE_A_VOID`, `GIFT_A_VOID`, `OPEN_SAFE_SUIT`.

**Retired since v1, confirmed gone from the code:** `FEEL_OUT_THE_HAND`
(no legitimate strategic basis, removed), `CONTEST_IF_WORTHWHILE`/`value_gate`
(retired — see Opponent Following below), the old `we_are_strong`
self-assessment fork inside partner-leading (retired — see below),
`PROTECT_COUNTERS_WHILE_LEADING` as a distinct name (folded into the
priority stack's off-suit and blind-fallback tiers).

**New since v1:** `LOCK_IN_COUNTER_LEAD` (opponent leading, unchanged from
v1). The partner-leading stack's SAFE and GAMBLE tiers aren't separately
named objectives — they're execution tiers within `CONTROL_TRUMP`/
`FORCE_A_VOID`'s successor logic; see below.

---

## Mechanical overrides (unchanged)

SEVENS and NELLO bypass `decide_play()` entirely — no geometry interpreted.

## MARKS / PLUNGE / SPLASH (unchanged since v1)

One shared block, since all three contracts answer "win every trick,
counters irrelevant" identically:
- Leading: `CONTROL_TRUMP`-adjacent, unconditional (no trump-count threshold,
  stricter than standard `CONTROL_TRUMP`).
- Partner winning: yield lowest — same `PROTECT_PARTNER_WIN` objective as
  the standard-contract cardinal rule, reimplemented in this block rather
  than shared code.
- Can-win: `SECURE_FOR_PARTNER`, economy/trust stripped (correct for Marks).
- Can't-win: `ESCAPE`, no pip filtering (counters are irrelevant here).

---

## Partner leading — the Lead-Safety Priority Stack (rebuilt July 13, 2026)

Replaces v1's branches 6a/6b/7/8/9/10 entirely. Runs in this order, each
step returning immediately if it fires:

**Step 1 — `GIFT_A_VOID`.** If the human is known void in a suit
(`PublicKnowledge`), lead the double or the currently-highest-remaining
tile in it — a good-confidence (not guaranteed) free discard. Unchanged
from v1. No difficulty gate.

**Step 2 — `CONTROL_TRUMP`.** Eligible only when **both** hold: rank-safety
(our best trump equals `highest_remaining_trump()` — this specific lead is
provably unbeatable) **and** objective-incomplete (the opposing team isn't
already both confirmed void in trump). Replaces the old
`trumps.size() >= 3/4` count proxy (BUG-016) — count never actually proved
either fact it was standing in for. Once eligible: if the double is
accounted for (held, or already played), lead highest; otherwise lead low
(non-counter preferred) to draw the double out first.

**Step 3 — temporary stopgap, not final architecture.** The old
`trumps.size() >= 4` no-double threshold, reinstated as its own step
(gated the same way Step 2 is, `not trump_control` guarded to avoid
overlap) because Step 2's new rank-safety requirement essentially never
holds for a non-double holding this early in a hand — the old low-lead
technique had gone dead without this. Explicitly **not** the real fix; a
proper trump-evaluation model (quantity/ceiling/continuity/counter-cost)
is designed-not-built, pending calibration against real hands.

**Step 4 — SAFE tier.** Any non-trump tile that's fully safe against
*both* opponents independently (`_is_lead_fully_safe()` — each opponent
must clear either "must follow suit and this is provably highest in it" or
"void in both the suit and trump"). Free points, led with full confidence.

**Step 5 — GAMBLE tier.** Reached only if Steps 2-4 found nothing. The
opposing team has a known void hit on a suit, but at least one void
opponent's trump status is live or unknown — not provably safe, a
deliberate gamble. Cost-minimized (`_lowest_cost_in()` — prefers a
non-counter if one exists in the pool). Retires the old `we_are_strong`
self-assessment fork outright, not a smarter version of it — its two old
inputs (own trump control, safe off-suit availability) are now checked
upstream instead.

**Step 6 — ordinary safe off-suit lead.** Reached only once nothing above
fired — meaning nothing legal has any void information at all. A generic
"not a counter" catch-all, not a safety claim (a counter-double of a
non-trump suit is still led on reasonable confidence here, per the BUG-009
ruling — hiding it only delays an eventual forced discard).

**Step 7 — fully blind fallback.** Reached only when no void information
exists on anything legal and no off-suit non-counter/double is available
either. Cost-minimized the same way as Step 5, over the full legal pool.

**Still open, logged not forgotten:** BUG-015 (a trump-control-persistence
gap — switching leads between two doubles before both opponents are
proven void in trump) needs its own design session. The general question
of whether objective priority should be an inspectable structure rather
than physical position in an `if`/`elif` chain is also still open — this
stack's own step-ordering bugs (found twice in one evening) are the
concrete evidence for why that question keeps recurring.

---

## Partner following

**`human_is_winning` (the cardinal rule):**
- Guaranteed win (double led, **or** provably-highest-remaining-in-suit
  with trump exhausted) → dump highest counter if legal, else lowest.
- Not guaranteed → play lowest non-counter to protect counters; if forced
  (only counters legal), play lowest counter.

**Not winning, `can_win`:** Partner always prefers a non-trump winner first
— no difficulty branching. If only trump can win, partner always runs the
same evaluation regardless of difficulty (contract margin → live counter
status via `_live_counter_for_suit()` → lead economy; the old expert bypass
and the old beginner "skip economy" shortcut are both gone — one
unconditional path now). This is branch #16 from v1, since BUG-005's
rewrite the only commitment gate left in the file.

**Can't win:** discard lowest safe tile (`_pick_partner_discard()` — breaks
the all-doubles tie by discarding the one whose suit has the least life
left). One shared path at every difficulty; the old beginner
"discard-highest-first" variant was removed (no valid strategic basis).

---

## Opponent leading

**Expert void-lead (`FORCE_A_VOID`, knowledge-gated on `vigilance == "full"`,
today only Expert sets that):** target a suit the opposing team is known
void in. Got the same any→all safety correction as partner's stack, but
was **not** restructured into SAFE/GAMBLE tiers — deliberately left at its
original, narrower scope. Worth revisiting at the table if it stops feeling
right; not currently a design gap, an accepted asymmetry (opponents allowed
to be a notch less thorough than partner).

**Trump control, strong-counter lead, fallback:** unchanged from v1 —
duplicate pair with partner's `CONTROL_TRUMP`/off-suit logic, not yet given
the same priority-stack treatment.

---

## Opponent following

**Partner winning (opponent's own partner):** mirrors the cardinal rule.
Forced overtake escalates to a guaranteed winner if held, otherwise the
strongest available if not last to act, or lowest if last to act (nothing
left to answer). Not forced: play lowest; if that happens to win, say so.
If last to act and the opportunism roll (`_should_evaluate_tactically()`)
hits, drop a stranded counter that can't affect the outcome (BUG-004).

**`can_win`:** if the opportunism roll misses, commit reflexively — lowest
legal tile, no accounting (this is the old beginner "secure without
second-guessing" shape, relocated here from partner, where it never
belonged). If the roll hits, prefer a counter win, otherwise lowest that
still wins. **`value_gate`/`CASH_COUNTERS`'s old separate threshold is
gone entirely** — the opportunism roll replaced it, since the old
threshold had the direction backwards (passing on a cheap trick is the
disciplined move, not the distracted one).

**Can't win:** discard lowest safe tile. Three unreachable dead-code
fragments left over from before `value_gate`'s retirement were found and
removed in the same cleanup pass that confirmed this.

---

## `AI_MODES` — current shape (v1's `trust_threshold`/`contest_threshold` are both dead ends, not pending)

```gdscript
"vigilance":   "none" | "full"   # knowledge-access gate, tiered, stable
"opportunism": 0.0 - 1.0          # rolled fresh per eligible decision
```

Neither parameter varies by difficulty for partner — partner has zero
difficulty branching anywhere in `decide_play()`. Both apply to opponents
only. `trust_threshold` never had a real source branch once BUG-005
rewrote #16 without trust content, and `contest_threshold` was superseded
by the opportunism roll rather than built as a scalar — neither is a
pending design item.

---

## Confirmed duplication pairs (still true, unchanged from v1)

- `PROTECT_PARTNER_WIN`: MARKS block / partner-following cardinal rule /
  opponent-following mirror
- `CONTROL_TRUMP`: partner-leading Step 2 / opponent-leading
- `FORCE_A_VOID`: opponent-leading (knowledge-gated, expert-only) /
  partner-leading Step 1's `GIFT_A_VOID` is the mirror-image concept, not
  a duplicate — different target, different purpose (opportunity vs.
  pressure)
