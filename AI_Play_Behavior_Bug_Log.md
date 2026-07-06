# AI Play Behavior Bug Log

**Status key:** ✓ Fixed | → Ready to fix now | ⏸ Paused — reclassified, needs design pass | ⏳ Waiting on Phase 4 (void/played-tile tracking) | ⚑ Needs more examples before speccing

---

## Pattern A — "Guaranteed trick" detection is too narrow

Three separate bugs (BUG-002, BUG-002b, BUG-004) are the same underlying gap: the code only recognizes a trick as **locked in** (safe to dump a counter onto, zero risk) in one specific case — *a double was led*. But "locked in" is actually a broader concept with at least three ways to arrive at it, and they don't all need the same kind of fix.

| Case | What makes it locked | How to model the difference |
|---|---|---|
| Double led (existing) | Doubles are structurally unbeatable | No difference to model — already implemented, always checked |
| **Last-to-play position** | No one left to act — outcome is arithmetic, not judgment | Evaluation axis — see below |
| High trump, but its pair-double is already known played | Only beatable card is gone | Knowledge axis — genuine information asymmetry |

### ⏸ BUG-004 — Opponent doesn't dump counter when last to play, partner winning
**File:** `ai_player.gd`, line ~646 (`partner_winning` branch, opponent following logic)
**Situation:** Trump=0. P3 has trumped in and is winning. P1 plays last, must follow suit 4, holds 3:4, 4:4, 4:6 (counter). Plays 3:4 — lowest, "saving my strength." 4:6 counter is stranded in hand.
**Problem:** The branch at line 646 plays lowest unconditionally, with no check for trick position. When a player is last to act, the trick result is already fixed — there is no risk left to hedge against.

**Reclassified — this is not a knowledge gap.** The fact that the trick is locked (last to play, outcome fixed) is visible to every seat at the table, human or AI, beginner or expert. There's no inference here and nothing a knowledge/inference layer needs to supply. Initially specced with a straight `difficulty == "expert"` gate, but per the new philosophy header in `ai_player.gd` (Knowledge/Evaluation litmus test), a bare difficulty check on a fact everyone can see is exactly the pattern to avoid.

**What kind of difference this actually is:** whether a player *bothers to check* for and *capitalize on* a locked trick sitting in plain sight is an Evaluation-axis question — specifically, it's a live instance of the still-unwired Phase 3 (Opportunism) axis in `AI_MODES`. It doesn't belong behind a difficulty string; it belongs behind however Opportunism ends up gating "does this player check for exploitable situations at all."

**Status:** Paused, not abandoned. Katy wants a fuller Phase 3 design pass before this gets a decision-logic change — this bug is the concrete case that surfaced the Phase 3 gap, but the fix shouldn't jump ahead of that design work. Revisit once Phase 3 (Opportunism) is actually specced, at which point this becomes one of its first real test cases rather than a standalone play-logic patch.

**Note for whenever it resumes:** the "is this trick decided" check itself (double led / last to play / eventually the known-safe-high-trump case below) is knowledge-agnostic in its own right — worth eventually naming as a single shared predicate (see naming note at the bottom) rather than writing it inline once Phase 3 gating is designed.

### ⏳ BUG-002 — Partner doesn't dump counter on partner's guaranteed win via high trump
**File:** `ai_player.gd`, line ~505 (`winning_domino.is_double()` check)
**Situation:** P0 leads 0:6 (top remaining trump, not a double) — an effectively guaranteed win, since the double trump has already gone. P2 (partner) can't follow, holds 4:6 (counter). Plays 1:6 instead of dumping 4:6.
**Root cause:** The dump-check only fires on `is_double()`. A bare high trump is mechanically beatable by the double, so without knowing whether the double has already fallen, the conservative discard is *correct given the AI's actual information* — this isn't a logic bug so much as a missing input.
**Why this one *is* a knowledge gap (unlike BUG-004):** "has the trump double already been played" is not equally visible to every seat — it depends on tracking what's happened over the course of the hand. That's genuine information asymmetry, so unlike BUG-004 this one correctly belongs behind the project's knowledge/inference layer, not an evaluation axis.
**Depends on:** Phase 4 knowledge/inference layer — specifically, "has the trump double already been played" needs to become a queryable fact, then the `is_double()` check widens to `is_double() or is_known_safe_high_trump(winning_domino)`.
**Supporting example (BUG-002b):** Same root cause, confirmed independently — Trump=1, P0 leads 1:6 after 1:1 is already gone, P2 holds 0:5 counter, plays 0:6 instead. Same fix, same dependency.

---

## Pattern B — Lead-priority ordering: "safe suit" check short-circuits trump control

### ✓ BUG-003 / BUG-003b — Partner leads off-suit instead of drawing trump with real trump control
**File:** `ai_player.gd`, lines 471–485 (partner leading block)
**Situation (BUG-003):** Partner holds 3 trumps including the double (full control). The off-safe check at line 473 fires first (partner has non-trump non-counter tiles available) and returns immediately — the `trumps.size() >= 3` check at line 481 is never reached. Partner leads 1:1 instead of the double trump; a counter is later lost to a ruff that the double-lead would have prevented.
**Root cause (confirmed in code):** The two checks are sequential with no priority logic between them. Whenever *any* off-suit non-counter tile exists, the function returns before trump control is ever evaluated — meaning "full trump control" as a leading strategy is currently dead code whenever the hand also happens to hold a safe off-suit tile, which is most hands.
**Fix shape:** Swap evaluation order — check trump control (3+ trumps, or 3+ trumps including the double) *before* the off-safe suit check, not after. The off-safe heuristic stays correct for weak trump holdings (1–2 trumps, no double); it should only run when the trump-control condition fails.
**Note:** This is a pure ordering fix, not a difficulty question — both checks already run identically for every difficulty and every seat. No knowledge/evaluation reclassification needed here.
**Supporting example (BUG-003b):** Same root-cause confirmation with 4 trumps and no double — off-safe fires on the one remaining off-suit tile (0:2) before the trump count is checked; opponent trumps in and steals the lead.
**Open judgment call (Katy, ⚑):** BUG-003b is flagged as the softer case — with 4 trumps and no double, this is the *pivot point* where drawing trump becomes correct, not a clear-cut case like BUG-003's double-in-hand scenario. Worth deciding the exact trump-count threshold (3? 4?) and whether "no double" changes the threshold, before finalizing the reordering — don't just move the double-trump fix over unchanged.

**✓ Fixed (July 5, 2026).** Reordered `decide_play()`'s partner-leading block so trump control is evaluated before the safe off-suit check. Threshold: 3+ trumps if the holding includes the double, 4+ otherwise (Katy's call — the double supplies enough control on its own at the lower count). BUG-003b's "softer case" question (does no-double change the threshold) is resolved by this same rule rather than needing separate handling. Status changed → to ✓.

---

## Pattern C — Discard value isn't just "lowest rank" among unlike tiles

### ⚑ BUG-001 — Discard selection among doubles doesn't weigh relative counter-protection value
**File:** `ai_player.gd` — discard path when stuck holding only doubles and unable to follow suit (uses `_lowest_in`, which ranks by `get_rank()`)
**Situation:** Stuck on trump, hand is all doubles: 6:6, 3:3, 5:5, 2:2. Discarded 6:6; should have discarded 2:2.
**Why this isn't a simple ranking bug:** `_lowest_in` ranks by suit/trump rank, which has no concept of "which of my doubles guards a counter that could still be led." The correct heuristic here is genuinely new: each double's value is a function of whether its suit's counter tile is still live and could be captured by that double if led. This isn't a bug in existing logic so much as a heuristic the system doesn't have yet.
**Note:** This is visible information (every player can see which counters have appeared) reasoned about identically regardless of difficulty — an Evaluation-shape addition to the shared decision logic once specced, not a knowledge or difficulty question.
**Status:** Low priority, standalone — doesn't block or get blocked by Phase 4. Worth speccing on its own whenever it reaches the top of the queue; not urgent to bundle with A or B above.

---

## Summary — suggested order of attack

1. ~~**BUG-003 reorder** — real bug (unreachable branch), independent of Phase 4 and of the Phase 3 design pause, but needs the BUG-003b threshold question settled first so you don't fix it twice. This is now the cheapest fully-ready item in the log.~~ **✓ Fixed July 5, 2026** — see entry above.
2. **BUG-002 / BUG-002b** — correctly parked behind Phase 4; nothing to do until the knowledge/inference layer can answer "has the double for this suit been played."
3. **BUG-004** — paused pending a full Phase 3 (Opportunism) design pass. Not abandoned; it's the case that surfaced the need for that design work in the first place, and should be one of its first test cases once that pass happens.
4. **BUG-001** — standalone, low priority, whenever there's room for a new heuristic rather than a fix to an existing one.

**Naming note carried forward:** "locked-in trick" is a reusable concept (double led / last to play / known-safe high trump), and it's worth a single named predicate — something like `_trick_is_decided()` — rather than separate ad hoc checks scattered across the partner and opponent branches. This predicate itself would be knowledge-agnostic (most of its cases need no inference at all); only the high-trump case would reach into the knowledge/inference layer. Whether and how each difficulty *checks* that predicate is then a separate, Phase 3 Opportunism question — which is exactly the Knowledge/Evaluation split the new philosophy header in `ai_player.gd` describes. Worth wiring up once both Phase 3 and Phase 4 have landed.
