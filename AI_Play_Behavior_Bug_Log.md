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

### ⚑ BUG-001 — Discard selection among doubles doesn't weigh relative counter-protection value

**File:** `ai_player.gd` — discard path when stuck holding only doubles and unable to follow suit (uses `_lowest_in()`, which ranks by `get_rank()`).

**Situation:** Hand is all doubles: 6:6, 3:3, 5:5, 2:2. Discarded 6:6; should have discarded 2:2 — each double's real value depends on whether its suit's counter tile is still live and could be captured by that double if led, which `_lowest_in()` has no concept of.

**Why this isn't a simple ranking bug:** this isn't a bug in existing logic so much as a heuristic the system doesn't have yet — `_lowest_in()` ranks purely by suit/trump rank, with no concept of "which of my doubles guards a counter that could still be led."

**Note:** Visible information (every player can see which counters have appeared), reasoned about identically regardless of difficulty — an Evaluation-shape addition once specced, not a knowledge or difficulty question.

**Status:** ⚑ Low priority, standalone. Doesn't block or get blocked by anything else in this log.

---

## Pattern D — `trust_gate` was gated on the wrong fact, and its fallback and reason string each described a different decision than the one actually needed

### ✓ BUG-005 — Partner's hold-vs-commit decision on a trump-only win was keyed to turn order, not to any factor that actually mattered

**Where:** `decide_play()`, branch #16 in `Phase3_Objective_Audit.md`'s table (partner following, trump-only can-win, inside `SECURE_FOR_PARTNER`) — the `trust_gate` check.

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

### ⏸→ BUG-007 — Branch #10 (forced counter lead) doesn't consult void/threat information at all — **reopened, needs its own design session (see Design Notes below)**

**Where:** `decide_play()`, partner-leading branch, final fallback when every legal tile is a counter (branch #10, `PROTECT_COUNTERS_WHILE_LEADING`, degraded).

**What happens:** When forced to lead a counter, the code always picks the highest available via `_highest_in(legal, ...)`, with no regard for which suit is safer to expose it into — even though `void_suits()` (the same query Expert's void-lead targeting already consumes) could inform the choice.

**History of the fix path:**
- Originally deferred (found alongside BUG-006, same branch-trace session) pending a design decision on whether "opponents void in this suit" alone is a strong enough safety signal, or whether it needs pairing with a trump-exhaustion check.
- **July 12, 2026:** believed resolved by BUG-009's ruling — reasonable-confidence counter leads are acceptable, provable safety is a refinement, not a gate. Marked "design-resolved, ready to spec" — but branch #10 itself was never actually touched (BUG-009's fix landed at branch #7 instead).
- **July 13, 2026:** today's design conversation found that BUG-009's ruling doesn't actually transfer cleanly here — see "Design notes — the two-path lead-safety model" below for why. Reopened.

**Status:** ⏸ Reopened. Not ready to spec — needs the same worked-hands treatment `trust_gate` got, jointly with BUG-012 below, since both depend on the same underlying safety model.

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

---

## Pattern H — `FORCE_A_VOID` treats partial opposing-team voidness as full safety

### ⏸→ BUG-012 — `void_leads` fires on "any opponent void," not "all opponents void" — **needs its own design session (see below)**

**Where:** `decide_play()`, two call sites sharing the identical filter shape: partner-leading branch 6b (partner-side `FORCE_A_VOID` mirror) and opponent-leading branch #20 (`FORCE_A_VOID` proper, expert-only via `vigilance == "full"`).

**What happens:** The `void_leads` filter checks `for opp in opposing_team: if public_knowledge.void_suits(opp).has(suit): return true` — this fires the moment **any single** opponent is void, not both. The reason string ("Leading a suit our opponents can't follow.") claims plural safety that was never actually verified.

**Flagged hand (July 12, 2026):** Player 2 led 4:6 (a live 10-count) believing it a safe void lead — player 1 had shown void in suit 6 back in trick 1, but player 3 had not, and was still holding two suit-6 tiles. Player 3 followed suit and took the trick — 15 points lost on a lead that was narrated as guaranteed-safe.

**Root cause:** the loop's `return true` fires on the first match found (`.any()` semantics); the claim being made needs `.all()` semantics — every element of `opposing_team`/`opponents` must satisfy `void_suits(opp).has(suit)`, not just one.

**Status:** ⏸ Reopened after design conversation, July 13, 2026 — see below. Not a simple any→all fix; the honest safety model turned out to be more nuanced than "how many opponents are void," and Katy has been clear the *gamble* version of this lead should stay available, not be eliminated.

---

## Design notes — the two-path lead-safety model (July 13, 2026, not yet blocking, governs BUG-007 and BUG-012's eventual fix)

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

**Open question, not yet resolved:** what decides whether to take the gamble on a given hand. This can't be a random opportunism-style roll — Partner's cooperative judgment is knowledge-limited only, never chance-limited, per standing doctrine. Likely shaped more like `trust_gate`'s contract-margin/lead-economy reasoning than a dice roll, but that's real design work, not a quick wire-up.

**BUG-007 is probably simpler than BUG-012 once this model exists**, for a reason worth naming: BUG-007 is *already forced* — every legal tile is a counter, there's no clean option, something's getting exposed regardless. That may mean the safe/gamble split matters less there than in BUG-012 (where a genuinely safe lead might be available instead) — possibly any void information at all is worth preferring among already-bad options, rather than needing the full two-path proof. Proposed as a starting point for discussion, not decided.

**Two older loose ends, carried forward from the pre-July-13 design notes — neither resolved by anything since, don't lose them when this section eventually gets specced:**
- **`own_suit_reversed` / Nello doubles-own-suit interaction** was never explicitly tested against `highest_remaining_trump()`/`best_remaining_card_for_suit()`. Flagged for playtest coverage back on July 6th, same as Fix 1's rollout was tracked then — still not verified.
- **Naming/architecture suggestion:** "locked-in trick" (double led / last to play / known-safe high trump) is a reusable concept worth a single named predicate — something like `_trick_is_decided()` — rather than separate ad hoc checks scattered across the partner and opponent branches. This predicate itself would be mostly knowledge-agnostic (most of its cases need no inference at all); only the high-trump case reaches into the knowledge layer. Whether and how each difficulty checks that predicate is a separate, Opportunism-axis question — never built, still just a suggestion.

**Next step:** treat BUG-007 and BUG-012 as one dedicated design session, worked through concrete table hands the way `trust_gate` was — before either gets specced or touched in code.

---

## Summary — suggested order of attack

1. ~~BUG-003/003b~~ ✓ Fixed July 5, 2026.
2. ~~BUG-002/002b~~ ✓ Fixed July 13, 2026 (via BUG-013's combined fix).
3. ~~BUG-004~~ ✓ Fixed July 13, 2026. Confirmed live.
4. **BUG-001** — ⚑ standalone, low priority, whenever there's room.
5. ~~BUG-005~~ ✓ Fixed July 5, 2026. Merged in from the standalone Pattern D addendum, July 13, 2026.
6. ~~BUG-006~~ ✓ Fixed July 9, 2026.
7. ~~BUG-009~~ ✓ Fixed July 12, 2026.
8. **BUG-007** — ⏸ reopened, needs a joint design session with BUG-012 (see design notes above). Do not spec in isolation.
9. ~~BUG-008~~ ✓ Fixed July 12/13, 2026.
10. ~~BUG-010~~ ✓ Fixed July 13, 2026. Confirmed live.
11. ~~BUG-011~~ ✓ Fixed July 12/13, 2026 (byproduct of BUG-008).
12. ~~BUG-013~~ ✓ Fixed July 13, 2026.
13. ~~BUG-014~~ ✓ Fixed July 13, 2026.
14. **BUG-012** — ⏸ reopened, needs a joint design session with BUG-007 (see design notes above). Do not spec in isolation.
