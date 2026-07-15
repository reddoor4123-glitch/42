# AI Play Behavior Bug Log

**Status key:** ✓ Fixed | → Ready to fix now | ⏸ Paused — reclassified, needs design pass | ⏳ Waiting on Phase 4 (void/played-tile tracking) | ⚑ Needs more examples before speccing

*Consolidated July 13, 2026, from three documents that had drifted apart: the pre-July-13 detailed log (full flagged-hand narratives, root-cause writeups, cross-references), the July 13 rewrite (newer statuses — BUG-002/002b, BUG-004, BUG-010, BUG-011, BUG-013 fixed; Pattern H/BUG-012 opened; BUG-007 reopened; the two-path lead-safety design notes), and the standalone `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` (BUG-005, never merged in). This is now the single authoritative copy — the other three should be archived or deleted once this is confirmed. Where the older document had a fuller narrative than the rewrite trimmed, that detail is restored here; where statuses conflicted, the most recent one wins, with the older status kept as history rather than silently dropped.*

---

## Pattern A — "Guaranteed trick" detection was too narrow

Three separate bugs (BUG-002, BUG-002b, BUG-004) share one underlying gap: the code only recognized a trick as **locked in** (safe to dump a counter onto, zero risk) in one specific case — *a double was led*. "Locked in" is actually a broader concept with at least three ways to arrive at it.

| Case | What makes it locked | How it's modeled |
|---|---|---|
| Double led | Doubles are structurally unbeatable | Always checked — original code |
| High trump, provably the best remaining | Only beatable card is gone/accounted for | Knowledge axis — `_is_guaranteed_win()` |
| Last-to-play position | No one left to act — outcome is arithmetic | Evaluation axis — `opportunism` roll |

### ✓ BUG-002 / BUG-002b — Partner didn't dump a counter on partner's guaranteed win via high trump

**Where:** `decide_play()`, `human_is_winning` block's `guaranteed_win` check, via the shared `_is_guaranteed_win()` helper. File: `ai_player.gd`.

**Situation (BUG-002):** P0 leads 0:6 (top remaining trump, not a double) — an effectively guaranteed win, since the trump double had already gone. P2 (partner) can't follow, holds 4:6 (counter). Plays 1:6 instead of dumping 4:6.

**Supporting example (BUG-002b):** Same root cause, confirmed independently — Trump=1, P0 leads 1:6 after 1:1 is already gone, P2 holds 0:5 counter, plays 0:6 instead. Same fix, same mechanism.

**What happened:** The dump-check only recognized a double as a guaranteed win. A bare high trump — the top remaining trump once the double had already fallen — was mechanically beatable-in-theory (by the double), so without knowing the double was gone, the AI held onto counters it should have cashed.

**History of the fix path — worth keeping, not just the ending:** Originally this was believed to be blocked on a whole missing Phase 4 knowledge/inference layer ("has the trump double already been played" as a new queryable fact). That framing turned out to be wrong: BUG-006 (Pattern E) solved a structurally similar "is this actually guaranteed" question using `PublicKnowledge.count_remaining_trump()` — a query that already existed — with no new infrastructure. That cross-reference (July 6, 2026) is what reopened BUG-002/002b as a near-term fix instead of a Phase-4-blocked one.

**Fix:** `_is_guaranteed_win()` gained a trump-suit branch, comparing `candidate` against `PublicKnowledge.highest_remaining_trump()`. This surfaced **BUG-013** (see Pattern F) during verification — the comparison had to be by rank, with an own-hand exception, not literal identity — and the combined fix closes both bugs at once, since they share the exact same call site.

**Status:** ✓ Fixed, July 13, 2026, as part of BUG-013's combined fix. See that entry for the full mechanism.

### ✓ BUG-004 — Opponent didn't dump a stranded counter when last to play, partner winning

**Where:** `decide_play()`, opponent-following branch, `partner_winning` path (branch #24), non-forced-overtake path — right after the `_beats(lowest, winning_domino)` check.

**Situation:** Trump=0. P3 has trumped in and is winning. P1 plays last, must follow suit 4, holds 3:4, 4:4, 4:6 (counter). Plays 3:4 (lowest) unconditionally — the 4:6 counter is stranded, carried forward into a future trick this side might not control.

**Reclassified (not a knowledge gap):** last-to-play is visible to everyone at the table — no inference needed. This is an Evaluation-axis question: does this seat *bother checking* for an exploitable locked-trick situation. Originally specced with a straight `difficulty == "expert"` gate, but per `ai_player.gd`'s own Knowledge/Evaluation litmus test, a bare difficulty check on a fact everyone can see is exactly the pattern to avoid — so it was paused instead, pending a full Opportunism design pass.

**Unblocked, July 12, 2026:** `Spec_Difficulty_Modes_TwoAxis_July12_2026.md` shipped `opportunism` as a real `0.0–1.0` roll via `_should_evaluate_tactically(mode)`, already wired into the can-win contest decision a few lines below this exact branch — but not into this specific case. This became the first real test case that migration's own author-intent pointed to.

**Design decision (Katy, July 13, 2026):** reuse the *same* opportunism roll as the can-win contest decision, not an independent one — "does this seat bother checking for exploitable table state" is one shared trait, not two.

**Spec (written July 13, 2026):** when not a forced overtake and the lowest legal tile doesn't accidentally win, check `_is_last_to_act(plays) and _should_evaluate_tactically(mode)`. If both hold, look among legal plays for a counter that doesn't beat the winning domino and play the highest one instead of the lowest, with a new reason string ("Nothing left to answer — may as well drop my count."). If the roll misses or no counter is available, behavior is unchanged.

**Reveals:** AVAILABLE — `_is_last_to_act()` and `_should_evaluate_tactically(mode)` both already exist and are already used a few lines below this branch.

**Status:** ✓ Fixed, July 13, 2026. Confirmed live in the current file — `_is_last_to_act(plays) and _should_evaluate_tactically(mode)` check in place, correct reason string firing.

---

## Pattern B — Lead-priority ordering: "safe suit" check short-circuited trump control

### ✓ BUG-003 / BUG-003b — Partner led off-suit instead of drawing trump with real trump control

**Where:** `decide_play()`, partner-leading block — the `off_safe` check and the `trumps.size() >= 3` trump-control check.

**Situation (BUG-003):** Partner holds 3 trumps including the double (full control). The off-safe check fires first (partner has non-trump non-counter tiles available) and returns immediately — the trump-control check is never reached. Partner leads a weak off-suit tile instead of the double trump; a counter is later lost to a ruff the double-lead would have prevented.

**Root cause:** The two checks were sequential with no priority logic between them. Whenever any off-suit non-counter tile existed, the function returned before trump control was ever evaluated — "full trump control" as a leading strategy was dead code whenever the hand also happened to hold a safe off-suit tile, which was most hands.

**Supporting example (BUG-003b):** Same root-cause confirmation with 4 trumps and no double — off-safe fires on one remaining off-suit tile before the trump count is checked; opponent trumps in and steals the lead. Flagged as the softer case — with 4 trumps and no double, this is the pivot point where drawing trump becomes correct, not as clear-cut as BUG-003's double-in-hand scenario. Needed its own threshold decision, not just the same fix copied over.

**Fix:** Reordered `decide_play()`'s partner-leading block so trump control is evaluated before the safe off-suit check. Threshold: 3+ trumps if the holding includes the double (the double supplies enough control on its own at the lower count), 4+ otherwise. This same rule resolved BUG-003b's softer-case question rather than needing separate handling.

**Status:** ✓ Fixed, July 5, 2026.

---

## Pattern C — Discard value isn't just "lowest rank" among unlike tiles

### ✓ BUG-001 — Discard selection among doubles doesn't weigh which double's suit still has life left in it (Partner only)

**File:** `ai_player.gd` — partner-side discard/yield call sites when the candidate pool is all doubles (uses `_lowest_in()`, which ranks by `get_rank()`).

**Situation:** Hand is all doubles: 6:6, 3:3, 5:5, 2:2. Discarded 6:6; should have discarded 2:2.

**Root cause:** `Domino.get_rank()` returns a flat `13` for every double regardless of pip value — correct for in-trick comparisons (any double beats any non-double), but it means `_lowest_in()`'s strict `<` comparison can never fire when every candidate in the pool is a double. `lowest` silently stays whichever tile happened to be first in the array — not a real decision, an unbroken tie masquerading as one.

**Reframed root cause, broader than the original write-up:** it's not only about guarding a live counter — a double's usefulness as a future lead/catch depends on whether its own suit still has *any* life left in it at all. A double whose suit is exhausted is dead weight; one whose suit still has unplayed tiles can still win a trick if that suit gets led. The original framing (protect a specific counter) is a special case of this broader one — a live counter is one reason a suit still has life, not the only one. `PublicKnowledge.remaining_count(suit)` already answers this directly.

**Fix (Katy, July 13, 2026):** a dedicated helper, `_pick_partner_discard()`, added alongside `_lowest_in()` rather than modifying it in place — `_lowest_in()`/`_highest_in()` are called from every kind of decision in the file (leading, following, winning), and a discard-shaped tiebreak doesn't obviously generalize to a leading decision, where a led double always wins its trick regardless of what else is out there. The new helper only intervenes when every candidate in the pool is a double (and `public_knowledge` is available): it discards the double whose suit has the fewest unplayed tiles remaining (`remaining_count(d.left)`), keeping the one most likely to still catch a trick later. Any pool with even one non-double, or a null `public_knowledge`, defers entirely to the untouched `_lowest_in()`. Applied at both partner-side call sites: the `human_is_winning`/not-guaranteed-win yield, and the "can't win either" discard path. No difficulty gate — matches existing partner doctrine (no gate on partner's `PublicKnowledge` access, this is visible-to-everyone information).

**Reveals:** AVAILABLE — `remaining_count(suit)` already existed with zero consumers anywhere in the codebase before this fix; this is its first real consumer.

**Verified:** direct helper test (suit with 1 tile remaining vs. suit with 5 remaining — the dead-suit double correctly chosen) plus two full `decide_play()` end-to-end runs, one through each call site, both selecting the exhausted-suit double over the live one. Mixed pool (double + non-double) and `public_knowledge == null` both confirmed to fall back to `_lowest_in()`'s exact prior behavior, unchanged.

**Flagged, not in scope — Opponent has the identical defect:** the opponent-following discard block (separate code, same `_lowest_in()` call pattern) has the exact same tie artifact. Deliberately not fixed in this pass (Katy, July 13, 2026). Before touching it, it needs its own decision: per existing precedent (e.g. the expert void-lead check, `_live_counter_for_suit()`), opponent-side knowledge-based logic is typically gated behind `vigilance == "full"` rather than applied unconditionally the way partner's is. Whether this specific fact (suit-liveness of a discard candidate) should follow that same gate, or is closer to "visible to everyone regardless of skill" the way BUG-014 was, is an open question worth its own short discussion before speccing — not a decision to make implicitly by copying the partner fix over. Logged here as a known candidate, not forgotten.

**Status:** ✓ Fixed (Partner only), July 13, 2026. Opponent-side mirror left open — see above.

---

## Pattern D — `trust_gate` was gated on the wrong fact, and its fallback and reason string each described a different decision than the one actually needed

### ✓ BUG-005 — Partner's hold-vs-commit decision on a trump-only win was keyed to turn order, not to any factor that actually mattered

**Where:** `decide_play()`, branch #16 in `Phase3_Objective_Audit_REWRITE_July14_2026.md`'s table (partner following, trump-only can-win, inside `SECURE_FOR_PARTNER`) — the `trust_gate` check.

**Old code:**
```gdscript
if difficulty == "expert":
    # Expert Partner: no trust rule — play optimally for the contract.
    ...
var human_play = _find_player_play(plays, partner_id)
var is_last_player = (plays.size() == 3)
if human_play != null and not is_last_player:
    var safe_discard = legal.filter(...)
    if safe_discard.size() > 0:
        reason_log.append("Saving my trump — there's still a chance someone else covers.")
        return discard
# Last player or no safe discard — trump in to secure the trick.
```

**Not one bug, three stacked mismatches, found through a design conversation, not code inspection alone:**

1. **The gate tested a fact that never mattered.** `human_play != null` checks whether the partner had already played this trick. With 4 fixed partnerships, once the partner's played, they can't act again that trick — so "has the human played yet" isn't actually a coverage question. Confirmed against real table reasoning: the factors a real partner weighs at this decision point are contract margin, counter status, and lead economy — turn order never entered it.
2. **The forced-commit fallback was also wrong, not just the gate.** No safe discard or last-to-act collapsed unconditionally into "trump in to secure the trick" — but a partner should be able to decline a winning trump play on contract margin alone, even with nobody left to act. Being last doesn't remove the decision, it just removes the "someone else might act" question, which per (1) was never the right question anyway.
3. **The reason string encoded a wrong belief model** ("someone else covers"), not just an imprecise correct one — a content problem, not a wording problem for the strings pass.

**Unifying root cause, not three unrelated symptoms:** all three trace back to one wrong axis — the branch was keyed to *turn-order state* (has the human played, am I last to act) when it should be keyed to *tactical evaluation state* (contract margin, counter status, lead economy). Any fix needed to replace the axis, not patch each symptom separately.

**What the decision should evaluate instead (confirmed via direct table-scenario walkthroughs):**
- **Contract margin** — can the team's current position absorb conceding this trick.
- **Counter status** — is the suit's risk-counter already played/void-eliminated (`PublicKnowledge.has_been_played()` / `is_void_in()` answers this deterministically — no hidden-information inference required).
- **Lead economy** — if this AI wins, is the resulting forced lead next trick good or bad, evaluable from its own hand and what's already been played.

**Explicitly out of scope for this pass:** "slide the trick to a partner positioned to win a future trick" — requires reasoning about tricks that haven't happened yet, agreed to be more speculative than the rest. Not lost — tracked as a parked concept in `Phase1_Control_Layer_Audit.md`, which is that concept's canonical home going forward, not this entry.

**Fix, implemented:** the gate, fallback, and reason string were all replaced together with the three deterministic factors above — contract margin, live-counter status via `_live_counter_for_suit()`, and lead economy — matching the "unifying root cause" diagnosis rather than patching each mismatch separately.

**Relationship to Phase 2 architecture:** this branch was the original source example for `trust_threshold` as a candidate `AI_MODES` Commitment-gate parameter. The candidate's *shape* (a scalar gating a fallback) is unaffected by this fix, but its *signal* can no longer be "trust in a partner" — there's no partner-trust content left in the corrected version. If rebuilt as a Commitment gate later, the scalar should be built from the three factors above, not the old turn-order check.

**Status:** ✓ Fixed, July 5, 2026. Specced in `BUG-005_Fix_Spec.md`, implemented, playtest-confirmed. Was tracked only in a standalone addendum file (`AI_Play_Behavior_Bug_Log_Addendum_PatternD.md`) that was never merged into this log — merged in here July 13, 2026, as part of this three-document consolidation. The addendum file is now fully superseded — safe to archive or delete.

---

## Pattern E — Guaranteed-lead detection didn't extend to trump exhaustion

### ✓ BUG-006 — Partner didn't lead a safe counter-double once trump was exhausted

**Where:** `decide_play()`, partner-leading branch, `off_safe` check (branch #7, `OPEN_SAFE_SUIT`).

**What happened:** `off_safe`'s filter excluded any tile where `pip_sum() == 5 or 10` unconditionally — so 5:5 was always filtered out of a safe lead, even once it couldn't possibly lose. Once every trump tile was accounted for (all played, or in this AI's own hand), 5:5 was a guaranteed-unbeatable lead within its own suit, and leading it immediately cashes 10 points the team already holds instead of delaying for no benefit.

**Fix shape:** `PublicKnowledge.count_remaining_trump()` already returns the count of trump tiles not yet played, across the whole game. Paired with the AI's own trump count in hand: if `count_remaining_trump() - own_trump_count_in_hand == 0`, every remaining trump is either already played or in this AI's own hand — none can be in an opponent's hand, so the counter-double is provably safe to lead. No new query, no new helper — a wiring/condition change inside branch #7 itself.

**Reveals:** AVAILABLE — the fact already existed and was correctly implemented; it simply wasn't consulted at this branch.

**Relationship to other bugs:** this simple count-based approach is what reopened BUG-002/002b (see Pattern A) — they'd been mischaracterized as blocked on a whole new Phase 4 knowledge layer, when the same technique used here applied there too.

**Status:** ✓ Fixed, July 9, 2026. `off_safe` now includes a counter-double once trump is provably exhausted. The reason string no longer unconditionally claims "opening a safe suit" — it distinguishes locking in a double, a lead confirmed unbeatable via `best_remaining_card_for_suit()`, and an ordinary suit-opening lead.

### ✓ BUG-009 — `OPEN_SAFE_SUIT` unconditionally excluded counters from lead candidates; 5:5 died as a forced discard instead of cashing itself as a lead

**Where:** Same branch as BUG-006.

**Flagged hand (July 11, 2026):** Trump 2, human bid 30. Partner wins trick 5 holding 5:5 / 1:5, leads the 1:5 ("Opening this suit for you to build on"), human is forced to trump it, and on trick 7 the partner discards the 5:5 onto a trick P1 wins with 4:4 — 10 points to the opponents, bid fails 26–30. Leading the 5:5 on trick 6 instead wins the trick outright (provably, in this hand — both opponents had shown void in trump by trick 2) and makes the bid comfortably.

**Root cause:** Counter exclusion at `OPEN_SAFE_SUIT` was a blanket rule with no exception for a counter that's the double of its own suit. The 5:5 as a lead loses only to a trump-in; as a held counter in a shrinking hand, it loses by default — it eventually gets discarded into an uncontrolled trick. The old policy optimized for not exposing the counter, with no concept of the counter capturing itself.

**Design ruling (Katy, July 11, 2026):** a counter-double is worth leading on *reasonable confidence*, not gated on provable safety — it loses only to a trump-in, and hiding it just delays an eventual forced discard into an uncontrolled trick. "The 5:5 is almost always worth the chance as a lead when the opportunity exists... taking that chance is better than holding it and handing it away on someone else's suit at the end." Provable safety (trump exhausted, or all opponents known trump-void) upgrades the confidence level for the reason string but is no longer required to lead it at all. No timing gate — default to "almost always," per the ruling, unless table testing said otherwise.

**Status:** ✓ Fixed, July 12, 2026. `off_safe` leads a counter-double on reasonable confidence. The reason string distinguishes three cases: a provably-unbeatable double ("nothing left to beat it"), a double led without proof ("cash it while I can"), and an ordinary suit-opening lead.

### ✓ BUG-007 — Branch #10 (forced counter lead) doesn't consult void/threat information at all

**Where:** `decide_play()`, partner-leading branch, final fallback when every legal tile is a counter (branch #10, `PROTECT_COUNTERS_WHILE_LEADING`, degraded).

**What happens:** When forced to lead a counter, the code always picks the highest available via `_highest_in(legal, ...)`, with no regard for which suit is safer to expose it into — even though `void_suits()` (the same query Expert's void-lead targeting already consumes) could inform the choice.

**History of the fix path:**
- Originally deferred (found alongside BUG-006, same branch-trace session) pending a design decision on whether "opponents void in this suit" alone is a strong enough safety signal, or whether it needs pairing with a trump-exhaustion check.
- **July 12, 2026:** believed resolved by BUG-009's ruling — reasonable-confidence counter leads are acceptable, provable safety is a refinement, not a gate. Marked "design-resolved, ready to spec" — but branch #10 itself was never actually touched (BUG-009's fix landed at branch #7 instead).
- **July 13, 2026:** design conversation found BUG-009's ruling didn't transfer cleanly here — see "Design notes — the two-path lead-safety model" below (now folded into the fix, not left as a standalone note). Reopened, then resolved same day via the Lead-Safety Priority Stack spec — see fix below.

**Fix (Katy + Claude, July 13, 2026):** folded into the same Lead-Safety Priority Stack spec that fixed BUG-012 (they share one root cause and one design session — see that entry for the full priority-stack shape). Branch #10 is retired as a standalone always-`_highest_in()` fallback; it's now step 6 of the partner-leading stack ("fully blind fallback," reached only when no void information exists on anything legal), and uses the new `_lowest_cost_in()` helper — the same cost-minimization mechanism as step 5's GAMBLE tier, just over the full legal pool instead of a void-informed subset. This is the actual behavior change: the old code led *highest* when forced (worst available choice, cost-blind); the new code leads lowest-cost (prefers a non-counter if the pool happens to contain one — e.g. a low non-counter trump tile that off_safe's trump exclusion left untouched — otherwise the lowest-ranked counter).

**Verified:** headless scenario with a non-counter trump mixed into an otherwise-counter-only pool correctly prefers the non-counter; an all-counter forced pool correctly falls back to lowest-rank via `_lowest_in()`.

**Status:** ✓ Fixed, July 13, 2026, jointly with BUG-012.

---

## Pattern F — Forced overtake, and the guaranteed-win helper it exposed

### ✓ BUG-008 — Forced overtake in `PROTECT_PARTNER_WIN` played a fragile minimal overtake instead of a secure winner

**Where:** `decide_play()`, partner-following branch, `partner_winning` path under standard contracts, and its opponent-side mirror (branch #24).

**Flagged hand (July 11, 2026):** Follow Me (no trump), human bid 31, team at 29 points after four tricks. Human leads 1:4 on trick 5. Partner holds 1:1 / 4:4 / 2:4; legal plays are 4:4 and 2:4, both of which beat the 1:4 — staying under partner is structurally impossible. Code plays 2:4 ("I've got this one"), P1 takes the trick with 4:5 plus the human's 5-count. Playing the 4:4 — the double of the led suit, unbeatable in no-trump — wins the trick and its 6 points instead, putting the team at 35 and making the bid on the spot.

**Root cause:** The `PROTECT_PARTNER_WIN` branch had a single unconditional policy: play `_lowest_in(legal)`. It never detected the forced-overtake sub-case — when no legal play stays under the partner's card, the branch's premise ("stay out of the way") is void, and lowest-legal becomes the worst available choice: it takes the trick from the partner and can't hold it.

**Fix, implemented:** Detects forced overtake (every candidate beats the current winning domino). When forced: escalate to a guaranteed winner if one is held (via the new shared `_is_guaranteed_win()` helper — see BUG-011), otherwise play lowest if last-to-act (nothing left to answer) or highest if not (make it stick). Mirrored at the opponent-side `partner_winning` path in the same pass (same structural gap, not in the original bug report — included anyway).

**String note (deferred to strings pass, per convention):** the old "I've got this one." fired on a card that then lost the trick, since the check only confirmed overtaking the partner, not holding the trick. The forced-overtake path now has its own honest strings ("Taking it with my double — nothing beats this.", "Had to take it — nobody left to answer.", "Had to take it — playing my strongest to make it stick.") that supersede the old overclaim for this case; the non-forced yield path's strings are untouched, still flagged for the strings-pass session.

**Reveals:** AVAILABLE — everything needed (current winning domino, `_beats()`, double-of-lead-suit detection) already existed at this branch.

**Documentation amendment made:** `Phase1_Control_Layer_Audit.md` finding #1 had stated the partner-winning decision space was fully closed ("there is no third option... 'Dump if guaranteed, protect if not' is the entire decision space"), silently assuming at least one legal play stays under the partner. The forced-overtake sub-case is the third option. Amended in place (July 11, 2026).

**Status:** ✓ Fixed, July 12/13, 2026. Verified via smoke tests, both partner- and opponent-side, forced and non-forced cases.

### ✓ BUG-011 — Partner treated any off-suit double as an automatic guaranteed win, even under a real trump contract

**Where:** Same `human_is_winning` block as BUG-002.

**What happened:** The old inline check (`winning_domino.is_double()`) had no trump-context distinction — correct by accident in Follow Me (where nothing beats a double, ever), silently wrong under real trump, where an opponent could still trump in and capture a dumped counter.

**Found via:** BUG-008's `_is_guaranteed_win()` refactor, as a natural consequence of generalizing the check, not a deliberate hunt. Confirmed via a constructed smoke test (partner facing a non-trump double as the current winner, holding both a counter and a safe non-counter, real trump active): the old logic would have dumped the counter; the new logic protects it instead.

**Documentation note:** the spec that shipped this fix described the `_is_guaranteed_win()` refactor as "behaviorally identical — same three-part test, now shared code." That claim was wrong for this exact case — worth recording here since no separate spec file exists to amend in place.

**Status:** ✓ Fixed, July 12/13, 2026 — same code as BUG-008's refactor, no separate patch needed.

### ✓ BUG-013 — `_is_guaranteed_win()` could never recognize a live winning tile as safe (self-exclusion)

**Where:** `_is_guaranteed_win()` helper itself — consumed by the `human_is_winning` dump-check and BUG-008's forced-overtake escalation.

**What happened:** `best_remaining_card_for_suit()`/`highest_remaining_trump()` both exclude already-played tiles from their search. The tile most commonly checked (`winning_domino`) is *already* recorded as played (it's sitting in the current trick), so it excludes itself from its own query's result — the old code required a literal self-match, which was structurally impossible. A `null` result (nothing else of that suit/trump remains anywhere) was being treated as *unsafe* when it's actually the clearest possible "safe" signal.

**Consequence:** the July 6 branch #11 generalization (dump counters onto a provably-highest non-double winner) and, by inheritance, BUG-008's forced-overtake escalation for non-trump/non-double candidates likely never actually fired for a real currently-winning tile despite being logged as implemented and playtest-confirmed. Correct-by-accident (falling through to the conservative path), not by design.

**Fix — two review passes, both needed:**
- **First pass** (reframed around "is there still a real outside threat," not literal self-match): null → safe; non-null → threat only if not sitting in the deciding player's own hand. Caught a real gap on review — no rank comparison at all, so a genuinely-harmless *lower-ranked* remaining tile would still be flagged as a threat just for not being in-hand.
- **Second pass** (rank-only correction): compare candidate's rank against the true highest remaining tile; only a strictly higher rank counts as a threat. Caught a real gap in return — no own-hand exception, so a genuinely-higher-ranked tile safely sitting in the deciding player's own hand would be wrongly called unsafe.
- **Combined fix:** rank checked first (does anything left actually outrank the candidate?); only when it does is the own-hand check consulted (safe if that tile is in the deciding player's own hand, since it can't be played against them this trick).

**Verified:** all four combinations tested directly against `_is_guaranteed_win()` (lower-rank/not-in-hand, higher-rank/not-in-hand, higher-rank/in-hand, nothing-remaining) — all four resolve correctly. Full regression suite (BUG-008/009 behavior, prior dead-code cleanup) unchanged.

**Documentation note:** the spec that shipped the trump-suit addition described it as touching only the trump case ("everything else is untouched"). That was accurate as written — the self-exclusion issue was pre-existing in the untouched non-trump logic too, not introduced by the trump addition. Worth recording as a case where "looks obviously right because it matches the existing pattern" wasn't a substitute for enumerating the actual case space — and where the first fix needed a second, externally-reviewed pass before it was actually correct.

**Status:** ✓ Fixed, July 13, 2026.

---

## Pattern G — Trump-lead technique doesn't exclude counters from consideration

### ✓ BUG-010 — Low-lead-to-draw-out-the-double technique could trade away a counter unnecessarily

**Where:** `decide_play()`, partner-leading branch, `CONTROL_TRUMP` (branch #8), the no-double sub-case — `_lowest_in(trumps, ...)`.

**What happens:** Picks the lowest-ranked trump with no exclusion for a trump tile that's also a counter. Example: holding 3:2 (counter), 3:4, 3:6 without the double — leads 3:2, trading a counter to a near-certain double capture, when 3:4 achieves the same draw-out purpose for free.

**Root cause:** `_lowest_in()` ranks purely by suit/trump rank; it has no concept of "this candidate is also worth 5 or 10 points, prefer a same-rank-tier non-counter instead." The technique's intent (draw out the double cheaply) and its execution (rank alone) weren't aligned.

**Design decision (Katy, July 13, 2026):** applies at every difficulty — matches how this branch already runs (no difficulty gate exists here since July 6), and this isn't a "does the AI bother to check" judgment call, it's information visible to everyone at the table.

**Fix:** filter `trumps` to non-counters first; use that pool for `_lowest_in()` if non-empty, falling back to the full `trumps` pool only if every candidate is a counter.

**Reveals:** AVAILABLE — one pip-sum filter, no new query needed.

**Status:** ✓ Fixed, July 13, 2026. Confirmed live in the current file — `non_counter_trumps`/`draw_out_pool` filter in place ahead of `_lowest_in()`, correct comment and reason string retained.

### ✓ BUG-014 — Low-lead technique kept firing after the double it was drawing out had already been played

**Where:** `decide_play()`, partner-leading branch, `CONTROL_TRUMP` (branch #8), the no-double sub-case — plus its sibling fallback, branch #9 (`non_counters_lead`).

**Flagged hand (July 13, 2026):** Trump 6. Partner leads 6:6 on trick 1 and wins it. On trick 2, partner still holds trump control (4 trumps remaining) but no longer holds the double — it fell to itself, one trick ago. Code falls into the no-double sub-case and leads 0:6 with the reason "Leading low trump to draw out the double first," even though the double is already gone and there's nothing left to draw out.

**Root cause:** `holds_double_trump` only asks "is the double in my hand right now" — never "has the double already been played by anyone this hand." Those are different facts, and the low-lead technique's entire justification (bait the double out of hiding) only holds when the answer to the second question is genuinely no. `PublicKnowledge.has_been_played()` already answers this; it just wasn't consulted at this branch. Same shape as BUG-006/BUG-002b: the fact was available, just unused at this decision point.

**Design decision (Katy, July 13, 2026):** the newly-correct highest-lead case reuses the existing "I have trump control — drawing out the opponents" reason string — the double being gone is exactly why nothing's left to bait, so leading highest is still the accurate description. Applies at every difficulty, same reasoning as BUG-010 (no difficulty gate on this branch, public information).

**Fix:** branch #8 now checks `double_accounted_for = holds_double_trump or has_been_played(double_tile)` before choosing between the highest-lead and low-lead paths. Branch #9 separately picked up the same provably-unbeatable upgrade its sibling branch #7 already had (`best_remaining_card_for_suit()` check, upgrading the reason string to "Nothing can beat this." when true) — a consistency fix, not a new technique; no design reason found for the asymmetry.

**Verified:** double played on trick 1 → trick 2 leads highest trump (5:6) with the control reason string; double never played → unchanged low-lead behavior (0:6, "Leading low trump to draw out the double first"); `public_knowledge == null` → safely falls back to the pre-fix hand-only condition, no crash.

**Reveals:** AVAILABLE for both parts — `has_been_played()` and `best_remaining_card_for_suit()` both already existed and were already proven consumers elsewhere in this same function (branches #7 and #11). No new query, no new helper, no new state.

**Status:** ✓ Fixed, July 13, 2026.

### ✓ BUG-016 — `CONTROL_TRUMP` eligibility was gated by trump count, not by whether the lead was actually safe or the objective already accomplished

**Where:** `decide_play()`, partner-leading branch, `CONTROL_TRUMP` (branch #8) — the eligibility gate itself, not the execution logic beneath it (`double_accounted_for`, highest-vs-low-trump lead, BUG-010's non-counter preference, BUG-014's has-been-played check — all untouched).

**Root cause:** `trump_control` had always been `(trumps.size() >= 3 and holds_double_trump) or trumps.size() >= 4` — a hand-count proxy for an objective (drawing out opponent trump) that count doesn't actually measure. Two hands with identical trump counts can have opposite real standing: top-ranked trumps that can't lose, versus low trumps while an opponent quietly holds the actual highest. This is the recurring root cause behind BUG-003/BUG-003b (count threshold placement), BUG-010 (count said nothing about counter-status), and BUG-014 (count said nothing about whether the double it was drawing out was already gone) — each landed a real fix without replacing the underlying proxy.

**Design session, July 13, 2026:** an initial proposal to replace the count check with a "keep leading while I hold `highest_remaining_trump()`" loop was considered and rejected — it would reintroduce persistent multi-trick state into an architecture (Selection/Commitment/Modulation) that's deliberately stateless, re-evaluated fresh on every `decide_play()` call. No loop needed: the natural re-invocation on each lead already provides "re-evaluate from scratch" for free. Further refinement distinguished the safety condition for pursuing the objective (is this lead provably safe right now) from the objective itself (has the opposing team's ability to trump in already been eliminated) — conflating them meant `CONTROL_TRUMP` could keep winning Selection even after both opponents were already confirmed void in trump, spending high trump on an already-accomplished goal.

**Fix:** `CONTROL_TRUMP` is now eligible only when both hold — **rank-safety** (our best trump equals `public_knowledge.highest_remaining_trump()`, i.e. this specific lead is provably unbeatable by anything remaining anywhere) **and objective-incomplete** (`not opposing_team.all(void_suits(opp).has(trump))` — the opposing team isn't already both confirmed void in trump). Both facts already existed in `PublicKnowledge`; no new query needed. `public_knowledge == null` makes rank-safety false unconditionally, so eligibility is false — same fallback shape as BUG-014's null-safety pattern.

**What this naturally reproduces with no explicit loop or state:** top three ranked trumps stay eligible three tricks running, stopping the moment either opponent shows void — even mid-run, even with more high trump still in hand. Top two ranked trumps, opponents not yet void: eligible twice, then rank-safety fails on the third lead once someone else holds the actual highest — a decision point opens naturally, resolved by whatever wins Selection next, not by a special case here.

**Verified:** the hand that prompted the investigation (trump 2, holding 2:4/0:2/2:3/2:2 at trick 1) now leads 2:2 first; a hand where partner leads the top two ranked trumps across two tricks correctly fails rank-safety on the third (reason string changes off the trump-control line, confirming the gate itself turned off — the tile happened to still get chosen via the blind-fallback tier's independent cost-minimization, which is a coincidence of that specific hand, not the gate firing); a hand where both opponents are confirmed void in trump after one lead correctly stays ineligible on the next lead even though rank-safety independently still holds, proving objective-incomplete is doing real gating work and not just riding along with rank-safety; `public_knowledge == null` correctly suppresses eligibility even when the old count threshold would have fired (4 trumps, no double).

**Explicitly out of scope, logged not forgotten:** objective-priority representation — whether `CONTROL_TRUMP`, once eligible, actually outranks other eligible objectives is still determined by physical position in the `if`/`elif` chain, the same mechanism behind BUG-003 and the SAFE-tier reorder earlier today (see Pattern H). Priority ordering itself still isn't formalized as an inspectable structure — flagged as its own future design session, the recurring cross-cutting version of a problem this session hit twice in two different objectives. (`CONTROL_TRUMP`'s specific position relative to SAFE tier was itself corrected the same night — see follow-up below — but the general architecture question remains open.)

**Status:** ✓ Fixed, July 13, 2026.

**Follow-up, same night — two regressions caught before this landed for real, both fixed as a stopgap, not the final architecture:**

1. **Position regression:** `CONTROL_TRUMP` still ran *after* the SAFE tier in the live file, so a fully-safe off-trump double (e.g. 5:5) could preempt an eligible trump-control lead — exactly backwards, since drawing trump when provably safe should outrank cashing an unrelated safe double. Reordered: `GIFT_A_VOID` → `CONTROL_TRUMP` → low-trump heuristic → `SAFE` tier → `GAMBLE` tier → off-suit → blind fallback.
2. **Dead-code regression:** the corrected rank-safety gate means a non-double trump holding essentially never qualifies this early (nothing beats the still-live double), so the old `trumps.size() >= 4` no-double case — leading low trump to draw the double out — had gone completely unreachable. Holding the double itself was never affected (the double is always top-ranked, so it already clears the new rank-safety gate on its own). Restored the no-double case as its own branch immediately after `CONTROL_TRUMP`, using the exact old count threshold (`>= 4`, no double), gated by the same objective-incomplete check and guarded by `not trump_control` to prevent overlap. Explicitly a stopgap — the real trump-evaluation model (quantity/ceiling/continuity/counter-cost), discussed the same session, is parked pending calibration against real hands, not built here.

**Verified (follow-up):** a hand with both an eligible trump-control lead and a fully-safe off-trump double available now correctly leads trump first (previously the double would have won); a 5-trump no-double hand now correctly leads the lowest non-counter trump with the restored "drawing out the double" string; the restored heuristic correctly stays silent when the trump objective is already complete (both opponents confirmed void in trump), matching `CONTROL_TRUMP`'s own objective-incomplete gate rather than reintroducing the count-only blind spot.

---

## Pattern H — `FORCE_A_VOID` treats partial opposing-team voidness as full safety

### ✓ BUG-012 — `void_leads` fired on "any opponent void," not "all opponents void"

**Where:** `decide_play()`, two call sites sharing the identical filter shape: partner-leading branch 6b (partner-side `FORCE_A_VOID` mirror) and opponent-leading branch #20 (`FORCE_A_VOID` proper, expert-only via `vigilance == "full"`).

**What happens:** The `void_leads` filter checked `for opp in opposing_team: if public_knowledge.void_suits(opp).has(suit): return true` — this fired the moment **any single** opponent was void, not both. The reason string ("Leading a suit our opponents can't follow.") claimed plural safety that was never actually verified.

**Flagged hand (July 12, 2026):** Player 2 led 4:6 (a live 10-count) believing it a safe void lead — player 1 had shown void in suit 6 back in trick 1, but player 3 had not, and was still holding two suit-6 tiles. Player 3 followed suit and took the trick — 15 points lost on a lead that was narrated as guaranteed-safe.

**Root cause:** the loop's `return true` fired on the first match found (`.any()` semantics); the claim being made needs `.all()` semantics — every element of `opposing_team`/`opponents` must satisfy the real safety test, not just show a void hit.

**Design session, July 13, 2026:** reopened rather than patched as a simple any→all swap, because a real safety test needed more than a vote count — see the two-path model below (now resolved into the fix, kept here for the reasoning it's built on rather than as a separate open item).

**Fix — the Lead-Safety Priority Stack (Katy + Claude, July 13, 2026):** a new shared two-path safety test, `_is_lead_safe_against_opponent()`/`_is_lead_fully_safe()` (`ai_player.gd`), replaces the vote-counting filter everywhere it appeared:
- **Partner-leading (6b) fix is the larger of the two:** the old single `void_leads` check with its `we_are_strong` self-assessment fork is retired outright (deleted, not repaired) and replaced with a full priority stack — GIFT_A_VOID (unchanged) → **SAFE tier** (new: any legal non-trump tile that's fully safe against both opponents via the two-path test, led with an honest "nothing can beat this"/"leading my double" string) → trump control (unchanged) → **GAMBLE tier** (new: the old void-hit pool, now cost-minimized via `_lowest_cost_in()` instead of the deleted self-assessment, honest reason string "Trying to force a decision — hoping this doesn't get trumped") → ordinary safe off-suit lead (unchanged mechanism, reason strings de-clawed of over-claiming now that SAFE tier owns the provable case) → fully blind fallback (this is BUG-007's fix — see that entry). `we_are_strong`'s two inputs (trump control, safe off-suit availability) are now checked upstream (trump control above; off-suit availability no longer gates GAMBLE at all, since off-suit is now just a fallback below it), making its old "lead highest, keep initiative" branch unreachable dead code under this order; its "lead lowest, pass initiative" branch survives in spirit as the GAMBLE tier's cost-minimized pick.
- **GAMBLE tier sits above the off-suit lead, not below it (corrected same day, July 13, 2026):** the first pass had these two reversed, which meant off-suit's unconditional "any non-trump non-counter" filter always claimed a non-counter before GAMBLE tier ever saw it — leaving GAMBLE's pool structurally guaranteed to be all-counters, and `_lowest_cost_in()`'s non-counter preference dead code at that tier. Swapped so GAMBLE (an actually void-informed pick) runs before off-suit (a generic "not a counter" catch-all with no safety claim behind it) — matches where the original 6b sat relative to #7, and means `_lowest_cost_in()` now does real work at the GAMBLE tier itself, not only at the blind fallback.
- **Opponent-leading (#20) fix is narrower, by design:** only the any→all defect is corrected (via the same `_is_lead_fully_safe()` test), with the reason string updated to "Leading a suit you can't beat." — no SAFE/GAMBLE tier split was added on the opponent side, and #20 was not reordered relative to the opponent's other lead checks. Keeps the existing asymmetry (opponents allowed to be a notch less thorough than Partner) intentional rather than accidental. Flagged by Katy as worth revisiting at the table if it doesn't feel right, not a closed question.

**Verified:** headless scenarios for all tiers — flagged 6:4-style hand now resolves at trump control before ever reaching a void check; both opponents void in suit AND trump correctly hits SAFE tier with an honest string (caught and fixed a real bug in this pass — the SAFE tier's reason-string logic initially mis-inferred "is a double" from `pip_sum() == 5 or 10`, which only holds inside the old `off_safe` pool's pre-filtered context, not the new SAFE tier's broader pool; fixed to check `is_double()` directly); a single void hit with the other opponent's status unresolved falls through to GAMBLE tier; a fully blind pool with a non-counter trump mixed into off-suit counters correctly prefers the non-counter at the blind-fallback tier; after the GAMBLE/off-suit swap, a hand with both a void-hit counter and a void-hit non-counter available now correctly picks the non-counter at GAMBLE tier itself, and a hand with no void information anywhere still correctly falls through to the off-suit tier.

**Confirmed before wiring in (per spec's own flag):** `void_suits(opponent).has(trump)` is tracked through the same general mechanism as any other suit — a trump-led trick a player can't follow appends `trump` to their void list exactly like any other lead suit — no special-casing needed in `_absorb_trick()`.

**Status:** ✓ Fixed, July 13, 2026, jointly with BUG-007.

---

## Design notes — the two-path lead-safety model (July 13, 2026 — resolved same day, see BUG-007/BUG-012 above for the implemented fix)

Surfaced while working through BUG-012 at the table (5:5 and 6:4 as worked examples).

**Partner has no knowledge limits, ever, at any difficulty.** Established doctrine, reconfirmed explicitly this session: Partner is modeled as a 60-year table veteran for whom void-tracking and public knowledge aren't calculated, they're second nature — full `PublicKnowledge` access, unconditionally, matching how 6a/6b were already built. This does **not** mean omniscience about hands that haven't shown themselves — `void_suits()` is still only what's been *proven*, not X-ray vision. Difficulty/skill variance belongs entirely to opponents and the human user; Partner always plays to the ceiling of what's knowable.

**A lead being unbeatable by a specific opponent has two independent paths, not one:**

| Opponent's situation | Can they beat the lead? |
|---|---|
| Not void in led suit (must follow) | Only if the lead is *not* provably the highest remaining tile in that suit. |
| Void in led suit, **not** void in trump | **Yes — the gamble zone.** Can trump in regardless of the lead's strength in its own suit. This is what the flagged hand hit. |
| Void in led suit **and** void in trump | No — nothing they hold can follow or trump in. |

Separately: a led tile that **is itself trump** and provably the highest remaining trump is safe against everyone regardless of any opponent's void status (existing `highest_remaining_trump()` mechanism, unaffected by any of this).

A lead is genuinely safe overall only when **both** opposing players independently land in a safe row — they don't need to land in the *same* row (one could be safe via "must follow, lead is provably highest," the other via "void in both suit and trump").

**This means `OPEN_SAFE_SUIT`/`_is_guaranteed_win()` and `FORCE_A_VOID` were never two separate mechanisms — they're two rows of one table.** `FORCE_A_VOID` was never really a safety mechanism at all; its own code comment says the point is to force a *decision* (trump in, spending a resource, or discard, possibly a counter) — a pressure play, not a guarantee, even before BUG-012's any/all defect.

**Katy's ruling on the gamble tier (July 13, 2026): keep it, deliberately.** A void-in-suit lead with trump status unknown or live is still often worth taking (5:5/0:0/6:4 example) — a real 60-year-player move, not a mistake to design away. The two-tier split is:
- **Safe tier** (void in suit AND void in trump, for every opponent still to act) — should probably just always fire when true, same as BUG-009's "don't hide a sure thing" logic.
- **Gamble tier** (void in suit, trump live/unknown) — worth taking sometimes, not always, and the reason string should say so honestly ("trying to force a decision," not "can't follow").

**Resolved, July 13, 2026 (same day):** the "what decides whether to take the gamble" question didn't end up needing a scalar or a roll — the fix simply always takes the GAMBLE tier when it's the best remaining option (SAFE/trump-control/off-suit all empty), cost-minimized rather than probability-gated. `we_are_strong`'s old self-assessment fork is what got retired here, not replaced with a smarter version of itself — see BUG-012's fix writeup above for the full priority stack.

**BUG-007 turned out to be exactly as simple as this note predicted:** it shares the GAMBLE tier's `_lowest_cost_in()` mechanism directly, just over the full legal pool instead of a void-informed subset (step 6, "fully blind fallback") — no separate proof needed, confirming the "already forced" framing above.

**Two older loose ends, carried forward from the pre-July-13 design notes — NOT resolved by this fix, explicitly out of scope for the Lead-Safety Priority Stack spec (Katy, July 13, 2026) — don't lose them:**
- **`own_suit_reversed` / Nello doubles-own-suit interaction** against the new two-path helper (`_is_lead_fully_safe()`) — still unverified, same unverified state it was in before this fix, not newly introduced by it. Flagged for playtest coverage.
- **Naming/architecture suggestion:** "locked-in trick" (double led / last to play / known-safe high trump) is a reusable concept worth a single named predicate — something like `_trick_is_decided()` — rather than separate ad hoc checks scattered across the partner and opponent branches. Still just a suggestion, not built.
- **New, same session — BUG-015 (log entry only, not specced):** the trump-control persistence issue — holding 6:6/6:5/6:4 plus another double, and switching leads to the other double before both opponents are proven void in trump. Explicitly out of scope for this spec; separate design session needed.

---

## Summary — suggested order of attack

1. ~~BUG-003/003b~~ ✓ Fixed July 5, 2026.
2. ~~BUG-002/002b~~ ✓ Fixed July 13, 2026 (via BUG-013's combined fix).
3. ~~BUG-004~~ ✓ Fixed July 13, 2026. Confirmed live.
4. ~~BUG-001~~ ✓ Fixed (Partner only) July 13, 2026. Opponent-side mirror left open — see Pattern C.
5. ~~BUG-005~~ ✓ Fixed July 5, 2026. Merged in from the standalone Pattern D addendum, July 13, 2026.
6. ~~BUG-006~~ ✓ Fixed July 9, 2026.
7. ~~BUG-009~~ ✓ Fixed July 12, 2026.
8. ~~BUG-007~~ ✓ Fixed July 13, 2026, jointly with BUG-012 (Lead-Safety Priority Stack — see Pattern H).
9. ~~BUG-008~~ ✓ Fixed July 12/13, 2026.
10. ~~BUG-010~~ ✓ Fixed July 13, 2026. Confirmed live.
11. ~~BUG-011~~ ✓ Fixed July 12/13, 2026 (byproduct of BUG-008).
12. ~~BUG-013~~ ✓ Fixed July 13, 2026.
13. ~~BUG-014~~ ✓ Fixed July 13, 2026.
14. ~~BUG-012~~ ✓ Fixed July 13, 2026, jointly with BUG-007 (Lead-Safety Priority Stack — see Pattern H).
15. **BUG-015** — ⚑ new, log entry only, holding 6:6/6:5/6:4 + another double switches leads before both opponents are proven void in trump. Needs its own design session.
16. ~~BUG-016~~ ✓ Fixed July 13, 2026 — `CONTROL_TRUMP` eligibility replaced with rank-safety + objective-incomplete, the root cause behind BUG-003/003b, BUG-010, and BUG-014.
