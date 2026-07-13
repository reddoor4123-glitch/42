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

**Unblocked, July 12, 2026 — the Phase 3 design pass this was waiting on has now happened.** `Spec_Difficulty_Modes_TwoAxis_July12_2026.md` shipped `opportunism` as a real `0.0`-`1.0` `AI_MODES` axis (`_should_evaluate_tactically()`), rolled per-decision on the opponent side. That migration only wired opportunism into the opponent-following `can_win` contest-or-not decision (retiring the old `value_gate`) — it did not touch this specific "dump a counter when last-to-play and the trick is already locked" case. This is now the first real test case the migration's own author-intent pointed to: worth a session applying the same `_should_evaluate_tactically(mode)` check here (does this opponent bother checking for the locked-trick opportunity at all) rather than treating it as still blocked on missing design work.

**Note for whenever it resumes:** the "is this trick decided" check itself (double led / last to play / eventually the known-safe-high-trump case below) is knowledge-agnostic in its own right — worth eventually naming as a single shared predicate (see naming note at the bottom) rather than writing it inline once Phase 3 gating is designed.

### ⏳ BUG-002 — Partner doesn't dump counter on partner's guaranteed win via high trump
**File:** `ai_player.gd`, line ~505 (`winning_domino.is_double()` check)
**Situation:** P0 leads 0:6 (top remaining trump, not a double) — an effectively guaranteed win, since the double trump has already gone. P2 (partner) can't follow, holds 4:6 (counter). Plays 1:6 instead of dumping 4:6.
**Root cause:** The dump-check only fires on `is_double()`. A bare high trump is mechanically beatable by the double, so without knowing whether the double has already fallen, the conservative discard is *correct given the AI's actual information* — this isn't a logic bug so much as a missing input.
**Why this one *is* a knowledge gap (unlike BUG-004):** "has the trump double already been played" is not equally visible to every seat — it depends on tracking what's happened over the course of the hand. That's genuine information asymmetry, so unlike BUG-004 this one correctly belongs behind the project's knowledge/inference layer, not an evaluation axis.
**Depends on:** Phase 4 knowledge/inference layer — specifically, "has the trump double already been played" needs to become a queryable fact, then the `is_double()` check widens to `is_double() or is_known_safe_high_trump(winning_domino)`.
**Supporting example (BUG-002b):** Same root cause, confirmed independently — Trump=1, P0 leads 1:6 after 1:1 is already gone, P2 holds 0:5 counter, plays 0:6 instead. Same fix, same dependency.
**Cross-reference (BUG-006, added July 6, 2026):** the "Depends on Phase 4" framing above may not hold. BUG-006 solves a structurally similar "is this actually guaranteed" question using `PublicKnowledge.count_remaining_trump()` minus the AI's own trump count in hand — no new knowledge-layer query, no new helper. Worth revisiting BUG-002/002b with the same count-based check (does every remaining trump reduce to "already played or in my own hand"?) before assuming this needs new infrastructure that may already exist.

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

## Pattern E — Guaranteed-lead detection doesn't extend to trump exhaustion

*Named Pattern E rather than D since `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md`
(BUG-005) already reserves that letter for whenever it's merged into this file.*

### ✓ BUG-006 — Partner doesn't lead a safe counter-double once trump is exhausted

**Where:** `decide_play()`, partner-leading branch, `off_safe` check (branch #7, `OPEN_SAFE_SUIT`). File: `ai_player.gd`.

**What happens:** `off_safe`'s filter excludes any tile where `pip_sum() == 5 or 10` unconditionally — so 5:5 is always filtered out of a safe lead, even once it can't possibly lose. Once every trump tile is accounted for (all played, or in this AI's own hand), 5:5 is a guaranteed-unbeatable lead within its own suit, and leading it immediately cashes 10 points the team already holds instead of delaying for no benefit.

**Fix shape:** `PublicKnowledge.count_remaining_trump()` already returns the count of trump tiles not yet played, across the whole game. Pair it with the AI's own trump count in `hand` (already available locally, no query needed): if `count_remaining_trump() - own_trump_count_in_hand == 0`, every remaining trump is either already played or in this AI's own hand — none can be in an opponent's hand, so 5:5 (or any counter-double under trump) is provably safe to lead. No new `PublicKnowledge` query and no new `AIPlayer` helper are required; this is a wiring/condition change inside branch #7 itself.

**Reveals:** AVAILABLE — the fact (`count_remaining_trump()`) already exists and is correctly implemented; it simply wasn't consulted at this branch.

**Relationship to existing bugs:** BUG-002/002b (partner not dumping counters onto guaranteed winners for high non-double trumps) was previously described as blocked on "Phase 4 trump exhaustion tracking." Given this simpler count-based approach, that block may not be needed either — worth revisiting BUG-002/002b with the same `count_remaining_trump() - own_trump_count` check before assuming it needs new infrastructure.

**Status:** Fixed July 9, 2026. `off_safe`'s filter now includes a counter-double once `count_remaining_trump() - own_trump_count_in_hand == 0` confirms trump is provably exhausted — exactly the wiring described above, no new query or helper needed. Folded in as part of the same pass that made `off_safe` PublicKnowledge-aware more generally: the reason string no longer unconditionally claims "opening a safe suit" — it now distinguishes locking in a double, a lead confirmed unbeatable via `best_remaining_card_for_suit()`, and an ordinary suit-opening lead. See `ai_player.gd`, partner-leading block, `off_safe` check.

**Cross-reference (BUG-007, added July 6, 2026):** same "safe counter lead" family, found during the same branch-by-branch trace one branch later (#10 vs. #7). Not the same bug — BUG-007 is about void-awareness, not trump exhaustion — but now that BUG-006 has landed, BUG-007 can be revisited with a concrete worked example of the shared mental model (PublicKnowledge-aware safety, honest reason strings) rather than a hypothetical one.

### → BUG-007 — Branch #10 (forced counter lead) doesn't consult known-void suits

**Where:** `decide_play()`, partner-leading branch, final fallback when no non-counter tile is available (branch #10, `PROTECT_COUNTERS_WHILE_LEADING`, degraded). File: `ai_player.gd`.

**What happens:** When forced to lead a counter (every legal tile is a 5-count or 10-count), the current code always picks the highest available via `_highest_in(legal, ...)`, with no regard for which suit each candidate belongs to. If opponents are already known-void in one of the candidate counters' suits (via `PublicKnowledge.void_suits()`), leading into that suit is meaningfully safer than leading into a suit an opponent can still follow naturally — no opponent can beat it by following suit, though they could still trump in.

**Example:** Partner holds 6:4 and 4:1, both counters, and both are the only legal leads. If opponents are void in suit 4, leading 4:1 is safer than 6:4 (a live suit), because it can only be beaten by a trump-in, not by a natural follow.

**Fix shape (not yet decided, flagging the open question rather than prescribing it):** `PublicKnowledge.void_suits()` already exists and is the right query — same one Expert's void-lead targeting (branch #20) already consumes. The open design question is whether "opponents void in this suit" alone is a strong enough safety signal to act on, or whether it needs to be paired with a trump-exhaustion check (same shape as BUG-006) to be a true safety guarantee — since a void opponent can still trump in and beat the lead. This needs a decision before implementation, not just wiring.

**Reveals:** AVAILABLE — `void_suits()` already exists and is correctly implemented; it simply isn't consulted at this branch. (Note: if the eventual fix requires pairing it with trump-exhaustion tracking, that half would be a second AVAILABLE fact per BUG-006's resolution, not UNBUILT — worth confirming once BUG-006 is implemented, since the same `count_remaining_trump()`-based approach may apply here too.)

**Relationship to existing bugs:** Same family as BUG-006 (found during the same branch-by-branch trace, same "counter safety at a leading branch" shape) — not the same bug, but worth resolving both with a shared mental model of what "safe counter lead" means, once BUG-006 lands.

**Status:** → Design-resolved, not code-fixed (July 12, 2026). The blocking design question — does "opponents void in this suit" alone suffice, or does it need pairing with a trump-exhaustion check — is answered by BUG-009's ruling: reasonable-confidence counter leads are acceptable, provable safety is a refinement, not a gate. That resolves this branch's shape the same way. **But branch #10 itself (`_highest_in(legal, ...)` in the final forced-counter-lead fallback) has not been touched** — BUG-009's fix landed at a different branch (#7, `off_safe`). Ready to spec/implement now that the design question is closed; not open-ended anymore, but not to be conflated with "fixed."

### ✓ BUG-009 — OPEN_SAFE_SUIT unconditionally excludes counters from lead candidates; 5-5 dies as a forced discard instead of cashing itself as a lead

**Where:** `decide_play()`, partner-leading branch, `off_safe` candidate filter (branch #7, `OPEN_SAFE_SUIT`). File: `ai_player.gd`.

**What happens:** The `off_safe` filter (not trump, `pip_sum() != 5 and != 10`) removes all counters from lead consideration unconditionally. A partner holding the 5-5 late in the hand never considers leading it — it's "protected" until the AI runs out of safe tiles and is forced to discard it into a trick it doesn't control.

**Example (flagged hand, July 11, 2026):** Trump 2, human bid 30. Partner wins trick 5 holding 5-5 / 1-5, leads the 1-5 ("Opening this suit for you to build on"), human is forced to trump it, and on trick 7 the partner discards the 5-5 onto a trick P1 wins with 4-4 — 10 points to the opponents, bid fails 26–30. Leading the 5-5 on trick 6 wins the trick (in this hand, provably: both opponents had shown void in trump by trick 2, so the one outstanding trump could not be with either opponent) and makes the bid comfortably.

**Root cause:** Counter exclusion at `OPEN_SAFE_SUIT` is a blanket rule with no exception for a counter that is the double of its own suit. The 5-5 as a lead loses only to a trump-in; as a held counter in a shrinking hand, it loses by default — it will eventually be discarded into an uncontrolled trick. The current policy optimizes for not exposing the counter, with no concept of the counter capturing itself.

**Design decision (Katy, July 11, 2026 — this is the ruling, not an open question):** The 5-5 is almost always worth the chance as a lead when the opportunity exists. It might get trumped; opponents might have to follow suit — but taking that chance is better than holding it and handing it away on someone else's suit at the end. Provable safety (trump exhausted, or all opponents known trump-void via per-opponent `void_suits()` — the BUG-006/BUG-007 composition this log's design notes anticipated) is **not** required as a trigger. Where that knowledge is available it can inform *when* in the hand to cash it, but the base behavior is: leading the counter-double is preferred over hiding it.

**Scope notes for the spec discussion:**
- Applies to a counter that is the double of its led suit and not trump — in the standard deck this is the 5-5 only (4-6 and the 5-counts aren't doubles and aren't likely winners as leads; a trump 5-5 is `CONTROL_TRUMP` territory, branch #8).
- Open question: does this run as a new check before `OPEN_SAFE_SUIT`, or as a relaxation of the `OPEN_SAFE_SUIT` filter? Placement relative to `GIFT_A_VOID` (6a) and the `FORCE_A_VOID` mirror (6b) needs a decision.
- Open question: any timing gate at all (e.g., always vs. only once the hand is down to N tiles or once safe leads are exhausted)? Katy's ruling leans "almost always" — default to no gate unless table testing says otherwise.

**Reveals:** AVAILABLE — `void_suits()` and `count_remaining_trump()` exist for the optional knowledge-informed refinement; the base fix needs nothing new.

**Relationship to existing bugs:** Same "counter safety at a leading branch" family as BUG-006/BUG-007, and it resolves the direction of the open design question BUG-007 flagged — per Katy's ruling, reasonable-confidence counter leads are acceptable; provable safety is a refinement, not a gate. Cross-reference all three when specced.

**Status:** ✓ Fixed, July 12, 2026. `off_safe` no longer requires provable trump exhaustion before including a counter-double — it's included on reasonable confidence per Katy's ruling above. The reason string now distinguishes three cases: a provably-unbeatable double ("nothing left to beat it"), a double led without proof ("cash it while I can"), and an ordinary suit-opening lead. No timing gate added, per the ruling. See `ai_player.gd`, partner-leading block, `off_safe` filter.

---

## Pattern F — Forced overtake doesn't escalate to a secure winner

### ✓ BUG-008 — Forced overtake in PROTECT_PARTNER_WIN plays a fragile minimal overtake instead of a secure winner

**Where:** `decide_play()`, partner-following branch, `partner_winning` path under standard contracts (`PROTECT_PARTNER_WIN`). File: `ai_player.gd`.

**What happens:** When the human partner is currently winning a trick but every legal play the AI holds beats the human's card, the AI plays the lowest legal domino anyway. This is a minimal overtake — it steals the trick from the partner without securing it, and a later opponent can (and did) take it.

**Example (flagged hand, July 11, 2026):** Follow Me (no trump), human bid 31, team at 29 points after four tricks. Human leads 1-4 on trick 5. Partner holds 1-1 / 4-4 / 2-4; legal plays are 4-4 and 2-4, both of which beat the 1-4 — staying under partner is structurally impossible. Code plays 2-4 ("I've got this one"), P1 takes the trick with 4-5 plus the human's 5-count. Playing the 4-4 — the double of the led suit, unbeatable in no-trump — wins the trick and its 6 points, putting the team at 35 and making the bid on the spot.

**Root cause:** The `PROTECT_PARTNER_WIN` branch (standard-contract `partner_winning` path) has a single unconditional policy: play `_lowest_in(legal)`. It never detects the forced-overtake sub-case — when no legal play stays under the partner's card, the branch's premise ("stay out of the way") is void, and lowest-legal becomes the worst available choice: it takes the trick from the partner and can't hold it.

**Fix shape, implemented:** Within `PROTECT_PARTNER_WIN`, detects forced overtake (every candidate beats the current winning domino). When forced: escalate to a guaranteed winner if one is held (via the new shared `_is_guaranteed_win()` helper — see BUG-011 and the guaranteed-win generalization design notes below); otherwise, if last to act, fall back to lowest for economy (any winner wins outright, nothing left to answer it); otherwise play the *strongest* available overtake, on the design call that a stronger overtake is harder for a remaining opponent to beat back. Mirrored at the opponent-side `partner_winning` path (same structural gap, not in the original bug report — included in the same pass).

**String note (deferred to strings pass, per convention):** the old "I've got this one." fired on a card that then lost the trick, since the check (`_beats(lowest, winning_domino)`) only confirmed overtaking the partner, not holding the trick. The forced-overtake path now has its own honest strings ("Taking it with my double — nothing beats this.", "Had to take it — nobody left to answer.", "Had to take it — playing my strongest to make it stick.") that supersede the old overclaim for this case; the non-forced yield path's strings are untouched and still flagged for the strings-pass session.

**Reveals:** AVAILABLE — everything needed (current winning domino, `_beats()`, double-of-lead-suit detection) already existed at this branch. The general `_is_guaranteed_win()` predicate is now built — see BUG-011, found as a byproduct of generalizing this exact check.

**Documentation amendment made:** `Phase1_Control_Layer_Audit.md` finding #1 stated the partner-winning decision space is fully closed: "there is no third option... 'Dump if guaranteed, protect if not' is the entire decision space." That conclusion silently assumed at least one legal play stays under the partner. The forced-overtake sub-case is the third option. Amended in place (July 11, 2026) rather than left to contradict this bug; the "not yet specced" qualifier is now dropped from that amendment since this bug is fixed.

**Status:** ✓ Fixed, July 12/13, 2026. Verified via smoke tests: forced overtake with a guaranteed winner held, without one while last to act, and without one while not last to act, all produce the expected domino and reason string, both partner-side and opponent-side. The non-forced case is confirmed unchanged.

### ✓ BUG-011 — Partner treated any off-suit double as a guaranteed win, even under a real trump contract

**Where:** `decide_play()`, partner-following branch, `human_is_winning` block. File: `ai_player.gd`.

**What happens (found via, not fixed via, a separate spec):** the guaranteed-win check that decides whether to dump counters onto the human's currently-winning trick was `guaranteed_win = winning_domino.is_double()` — no trump-context check at all. Partner treated *any* double as an automatic guaranteed win, including an off-suit double under a real (non-Follow-Me) trump contract, even though a remaining opponent could still trump in and capture it.

**Symptom:** partner dumps a counter onto a trick led by an off-suit double, believing it unbeatable, when trump is still live and an opponent hasn't acted yet.

**Root cause:** `winning_domino.is_double()` was correct by accident in Follow Me (where nothing beats a double, ever) and silently wrong whenever a real trump suit was in play — the check never distinguished the two.

**Found via:** BUG-008's `_is_guaranteed_win()` refactor (see above), which needed to generalize this exact inline check for its own forced-overtake logic and, in doing so, added the missing trump/no-trump distinction as a natural consequence of generalizing — not a deliberate hunt for this bug. Confirmed via a constructed smoke test (partner facing a non-trump double as the current winner, holding both a counter and a safe non-counter, real trump active): the old logic would have dumped the counter; the new logic protects it instead.

**Fix:** Already live — no separate patch needed, it's the same code as BUG-008's Fix 1 (`_is_guaranteed_win()` requires `trump < 0 or c_suit == trump` before treating any double as automatically guaranteed; otherwise falls through to the existing trump-exhaustion check).

**Reveals:** AVAILABLE — the trump-context distinction the fix needed already existed elsewhere in the file (the same no-trump/trump-suit-double check other branches already use); this call site just hadn't been consulting it.

**Documentation note:** the spec that shipped this fix (`Spec_Difficulty_Modes_TwoAxis_July12_2026.md`'s follow-up, "Forced-Overtake Escalation + Reasonable-Confidence Counter-Double Leads") described the `_is_guaranteed_win()` refactor as "behaviorally identical — same three-part test, now shared code." That claim was wrong for this exact case; no separate spec file exists in the repo to amend in place, so the correction lives here instead.

**Status:** ✓ Fixed, July 12/13, 2026 (as a byproduct of the Fix 1 refactor in this session).

### ✓ BUG-013 — `_is_guaranteed_win()` could never recognize a live winning tile as safe (self-exclusion)

**Where:** `decide_play()`, `_is_guaranteed_win()` helper (used by the `human_is_winning` dump-check and BUG-008's forced-overtake escalation). File: `ai_player.gd`.

**What happens:** the paste-ready spec that added a trump-suit branch to `_is_guaranteed_win()` (comparing the candidate against `PublicKnowledge.highest_remaining_trump()`) surfaced during verification that neither the new trump check nor the pre-existing non-trump check (`best_remaining_card_for_suit()`, live since branch #11's July 6, 2026 generalization) could ever actually return `true` for the tile they're most commonly asked about — the currently-winning tile already on the table.

**Root cause:** `best_remaining_card_for_suit()`/`highest_remaining_trump()` both exclude already-played tiles from their search. The tile being checked (`candidate` — typically `winning_domino`, already recorded in the in-progress trick's plays) is therefore excluded from its own query's result set. The old code required a literal self-match (`best_in_suit.debug_string() == candidate.debug_string()`), which was structurally impossible once the candidate excludes itself. Confirmed via direct isolated calls to `_is_guaranteed_win()`: even in a hand where every other tile of a suit was accounted for, the query returned `null` (not the candidate), which the old code treated as *unsafe* rather than the maximally-safe signal it actually is.

**Consequence:** the "generalized beyond doubles" guaranteed-win detection documented as playtest-confirmed for branch #11 (and, by inheritance, BUG-008's forced-overtake escalation for non-trump/non-double candidates) may never have actually fired for a real currently-winning tile in real play — it silently fell through to the conservative "not guaranteed" path every time, correct-by-accident rather than by design.

**Fix, first pass (Claude Code):** reframed both checks around "is there still a threat outside this player's control?" instead of a literal self-match — a `null` result (nothing else of that suit/trump remains anywhere) treated as safe; a non-null result treated as a real threat only if it's *not* sitting in the deciding player's own hand. Caught by external review (Chat) before commit: this version never compared *rank* — since `best_remaining_card_for_suit()`/`highest_remaining_trump()` always return the true highest-ranked remaining tile (excluding the self-excluded candidate), that returned tile can legitimately be *lower*-ranked than candidate (e.g. candidate is the second-highest trump and only the already-played double outranked it) — in which case it's harmless regardless of whose hand it's in, but the first-pass fix would still have flagged it as a threat. Confirmed the flaw was real by re-checking an earlier "negative control" test: it had (unintentionally) picked a lower-ranked remaining tile and gotten `false` back, which was itself the bug, not a passing test.

**Fix, combined (final):** both checks now compare by **rank** first — if the true highest-ranked remaining tile (or, for the suit case, the best-in-suit tile) does not outrank `candidate`, it's safe regardless of whose hand it's in. Only when that tile *does* outrank `candidate` does the own-hand check apply — safe if it's sitting in the deciding player's own hand (can't be played against them this trick), a real threat otherwise. Chat's rank-only proposal was missing the own-hand half; Claude Code's own-hand-only fix was missing the rank half. Neither alone was correct; combined, both gaps close.

**Verified:** four scenarios via direct calls to `_is_guaranteed_win()` (bypassing `decide_play()`), isolating each combination — remaining tile lower-ranked than candidate and not in hand (true), higher-ranked and not in hand (false, genuine threat), higher-ranked and in own hand (true), and nothing remaining at all (true). Full regression suite re-run afterward (BUG-008's flagged-hand replay, forced-overtake with/without last-to-act, BUG-009's counter-double lead, and the discard-block dead-code cleanup from the prior session) — no behavior changes to any previously-passing case.

**Documentation note:** the spec that shipped the trump-suit addition described it as touching only the trump case ("Everything else... is untouched"). That was accurate as written — the self-exclusion issue was pre-existing in the untouched non-trump logic too, not introduced by the trump addition. Flagged during verification rather than assumed correct because it "matched the existing pattern" — and the first-pass fix itself needed a second, external-reviewed pass before it was actually correct. Two independent review passes, two different gaps caught — worth noting as a case where "looks obviously right" wasn't a substitute for enumerating the actual case space.

**Status:** ✓ Fixed, July 13, 2026.

---

## Pattern H — `FORCE_A_VOID`'s opposing-team check accepts partial voidness

### → BUG-012 — `void_leads` treats "any opponent void" as sufficient, when the safety claim requires "all opponents void"

**Where:** `decide_play()`, two call sites — partner-leading branch 6b (`FORCE_A_VOID`'s partner-leading mirror) and opponent-leading branch #20 (`FORCE_A_VOID`). File: `ai_player.gd`.

**What happens:** both `void_leads` filters loop over the opposing team (exactly two players, since partner-leading excludes self+partner and opponent-leading excludes self+partner symmetrically) and `return true` the moment **any one** of them is found void in the candidate's suit:
```gdscript
for opp in opposing_team:
    if public_knowledge.void_suits(opp).has(suit):
        return true
return false
```
But the safety claim these branches make — leading this suit is safe from a natural follow because the opposing team can't follow it — requires **all** opposing players to be void, not just one. If only one of two opponents is void, the other can still follow suit naturally and beat the lead.

**Example:** partner leads into a suit where the left opponent is void but the right opponent still holds it — the right opponent follows suit normally and takes the trick, while the reason string ("Leading a suit our opponents can't follow." / "Leading a suit I know you're out of.") claims a safety that only ever existed for one of the two opponents.

**Root cause:** the loop's `return true` fires on the first match found, which is `.any()` semantics; the claim being made needs `.all()` semantics — every element of `opposing_team`/`opponents` must satisfy `void_suits(opp).has(suit)`, not just one.

**Fix shape:** not yet specced. Likely a straightforward `.all()`-style rewrite (e.g. `opposing_team.all(func(opp): return public_knowledge.void_suits(opp).has(suit))`) at both call sites, since they share the identical shape.

**Reveals:** AVAILABLE — `void_suits()` already exists and is correctly implemented; this is a logic-shape defect in how the two call sites consume it, not a missing fact.

**Found during:** this session's review (July 13, 2026), confirmed still live in the current file, untouched by the `_is_guaranteed_win()` fix batch (BUG-013) or any other fix this session.

**Status:** Open, not specced.

---

## Pattern G — Trump-lead technique doesn't exclude counters from consideration

### → BUG-010 — Low-lead-to-draw-out-the-double technique can trade away a counter unnecessarily

**Where:** `decide_play()`, partner-leading branch, `CONTROL_TRUMP` (trump-control lead, branch #8), the low-lead-to-draw-out-the-double sub-case — `_lowest_in(trumps, ...)` when partner has trump control but doesn't hold the double.

**What happens:** The low-lead technique picks the lowest-ranked trump via `_lowest_in()`, with no exclusion for a trump tile that's also a counter (pip sum 5 or 10). Example: holding 3:2 (counter), 3:4, 3:6 without the double — leading 3:2 as "low" trades away a counter to a near-certain double capture, when 3:4 achieves the same draw-out purpose without that cost.

**Root cause:** `_lowest_in()` ranks purely by suit/trump rank; it has no concept of "this candidate is also worth 5 or 10 points, prefer a same-rank-tier non-counter instead." The technique's intent (draw out the double cheaply) and its execution (rank alone) aren't aligned — a counter and a non-counter of similar low rank are treated as interchangeable when they aren't.

**Found during:** Review of the Vigilance/Opportunism two-axis migration (`Spec_Difficulty_Modes_TwoAxis_July12_2026.md` and its line-823 follow-up), July 12, 2026 — surfaced once partner's trump-lead technique was confirmed to run identically at every difficulty (no difficulty branching left to obscure it). Present at every difficulty; not new behavior from that migration, just newly visible.

**Fix shape:** Not yet specced. Likely shape: prefer the lowest-ranked non-counter trump if one exists among the candidates that still achieves the draw-out; only fall back to a counter trump if every trump candidate is a counter. Needs its own worked examples before speccing, per project convention.

**Status:** Open, not specced. Logged per explicit instruction not to fold a fix into the line-823 follow-up spec.

---

## Design notes — guaranteed-win detection generalization (July 6, 2026, not blocking)

Logged alongside the branch #11 guaranteed-win generalization (see
`Phase3_Objective_Audit.md` branch #11 and `public_knowledge.gd`'s
`highest_remaining_trump()`/`best_remaining_card_for_suit()`). Not a bug —
design notes for future, deeper work in the same "guaranteed-safety
detection" family as BUG-006/BUG-007/BUG-009 (leading side) and now
BUG-008 (following side — the parked `_is_guaranteed_win` helper below is
directly what BUG-008's forced-overtake escalation needs).

- **Generalize beyond branch #11.** The same "provably highest remaining
  in suit + trump exhausted" predicate is a good candidate for a proper
  reusable `AIPlayer` helper (e.g. `_is_guaranteed_win(winning_domino, ...)`),
  reused at #11, the opponent-mirror branch (#24), BUG-008's forced-overtake
  escalation, and possibly future leading-side safety checks (BUG-006,
  BUG-007, BUG-009) instead of staying branch-local.
- **Compose with void-suit knowledge (BUG-007).** Currently the trump
  threat check is all-or-nothing (`count_remaining_trump() -
  own_trump_count == 0`). A partial-safety version — "opponents are void
  in the winning suit AND trump is provably exhausted or void for them
  specifically" — could recognize more guaranteed wins than the strict
  version above, at the cost of more complexity. Worth revisiting once
  BUG-007 itself is designed.
- **`own_suit_reversed` / Nello doubles-own-suit interaction.** Not
  explicitly tested against these two new queries yet — flag for
  playtest coverage the same way Fix 1's rollout was tracked in the July
  4 session.

**Status:** Design notes only, not blocking this fix.

---

## Summary — suggested order of attack

1. ~~**BUG-003 reorder** — real bug (unreachable branch), independent of Phase 4 and of the Phase 3 design pause, but needs the BUG-003b threshold question settled first so you don't fix it twice. This is now the cheapest fully-ready item in the log.~~ **✓ Fixed July 5, 2026** — see entry above.
2. **BUG-002 / BUG-002b** — correctly parked behind Phase 4; nothing to do until the knowledge/inference layer can answer "has the double for this suit been played."
3. ~~**BUG-004** — paused pending a full Phase 3 (Opportunism) design pass.~~ **Unblocked, July 12, 2026** — that design pass happened (`Spec_Difficulty_Modes_TwoAxis_July12_2026.md`). This specific case (dump a counter when last-to-play and the trick is already locked) wasn't itself touched by that migration — it's the first real test case for applying `_should_evaluate_tactically(mode)` here, per that migration's own reasoning. Ready to spec, not just unblocked.
4. **BUG-001** — standalone, low priority, whenever there's room for a new heuristic rather than a fix to an existing one.
5. ~~**BUG-006** — cheap and self-contained (AVAILABLE, no new infrastructure), and worth doing alongside a revisit of BUG-002/002b since the same `count_remaining_trump()`-based check may resolve both.~~ **✓ Fixed July 9, 2026** — see entry above. BUG-002/002b revisit with the same count-based check is still open, not yet done.
6. **BUG-007** — design question resolved (July 12, 2026, via BUG-009's ruling), but branch #10 itself is still untouched code — BUG-009's fix landed at a different branch (#7). Ready to spec/implement now; do not mark this fixed until branch #10 actually consults `void_suits()`.
7. ~~**BUG-009** — design decided (July 11, 2026): lead the counter-double on a reasonable-confidence basis, not gated on provable safety.~~ **✓ Fixed July 12, 2026** — see entry above.
8. ~~**BUG-008** — design direction agreed (July 11, 2026): detect forced overtake in `PROTECT_PARTNER_WIN`, escalate to a guaranteed winner when one is held.~~ **✓ Fixed July 12/13, 2026** — see entry above. Found the `_is_guaranteed_win()` helper it needed doubled as the fix for a latent, unrelated correctness bug — see BUG-011.
9. **BUG-010** — found July 12, 2026 during the difficulty-modes migration review: the `CONTROL_TRUMP` low-lead-to-draw-out-the-double technique doesn't exclude counters when picking "lowest," so it can trade away a counter unnecessarily. Not yet specced; needs its own worked examples first, per project convention.
10. **BUG-011** — found July 12/13, 2026 as a byproduct of BUG-008's fix: the old inline guaranteed-win check treated *any* double as an automatic guaranteed win with no trump-context distinction, wrong whenever real trump was in play (not just Follow Me). Already fixed — same code as BUG-008's `_is_guaranteed_win()` refactor. See its own entry above.
11. ~~**BUG-013** — `_is_guaranteed_win()`'s trump/suit checks could never return true for a live winning tile (self-exclusion — the candidate is already recorded as played, so it excludes itself from its own "highest remaining" query).~~ **✓ Fixed July 13, 2026** — see entry above. Retroactively fixes branch #11's non-trump guaranteed-win generalization too, which had the identical latent issue since July 6, 2026.
12. **BUG-012** — `FORCE_A_VOID`'s `void_leads` filters (branch 6b and branch #20) use "any opposing player void" when the safety claim requires "all opposing players void" — confirmed still live, untouched by this session's other fixes. Not yet specced; straightforward `.all()`-style fix at both call sites once scheduled.

**Naming note carried forward:** "locked-in trick" is a reusable concept (double led / last to play / known-safe high trump), and it's worth a single named predicate — something like `_trick_is_decided()` — rather than separate ad hoc checks scattered across the partner and opponent branches. This predicate itself would be knowledge-agnostic (most of its cases need no inference at all); only the high-trump case would reach into the knowledge/inference layer. Whether and how each difficulty *checks* that predicate is then a separate, Phase 3 Opportunism question — which is exactly the Knowledge/Evaluation split the new philosophy header in `ai_player.gd` describes. **Phase 3 (Opportunism) has now landed (July 12, 2026)** as the `vigilance`/`opportunism` `AI_MODES` axes — wiring this predicate up is no longer blocked on Opportunism not existing, only on Phase 4 (knowledge/inference) for the high-trump case, and on someone writing the shared predicate itself.
