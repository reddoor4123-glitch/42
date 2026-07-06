# Texas 42 — Session Summary (July 4, 2026): Ranking Unification & PublicKnowledge Vocabulary Principle

### Purpose of this doc
Handoff for the next session. Covers: a full codebase review, two implemented fixes (ranking unification, MARKS/Plunge/Splash objective), and a ratified architectural principle for `PublicKnowledge` going forward. All `.gd` files should be current in Project knowledge before continuing this thread.

---

## What this session was about

Started with a full-codebase review (all `.gd` files, all three bug logs, all session summaries) producing six findings. The review was itself debated — a second pass reframed the findings into "real structural risk" vs. "bounded cleanup," which held up. Two of the findings were promoted to specs, implemented, and verified this session. A separate, previously-stalled Phase 4 discussion was also resolved: what `PublicKnowledge` is and is not.

---

## Review findings (status as of end of session)

1. **Ranking split-brain (real, fixed this session).** `Trick._determine_winner_standard()` was fully mode-aware (threaded `nello_doubles`/`doubles_trump_reversed`); `PublicKnowledge._absorb_trick()` was already correct; but `AIPlayer._beats()`, `_highest_in()`, `_lowest_in()`, and related helpers hardcoded `"high"` and never passed `doubles_trump_reversed`. Live bug under Nello doubles-low (reachable in normal play) and doubles-trump-reversed. **Fixed — see below.**
2. **Plunge/Splash objective gap (real, fixed this session).** `resolve_hand()` in `game.gd` already scores Plunge/Splash as win-all-7, same as Marks, but `decide_play()` had no branch for them — they fell through to counter-protection logic. **Fixed — see below.**
3. **Orphaned settings (real, not yet addressed).** `nello_doubles_reversed` is the serious one — the settings flag renders a "Reversed" button that sets a string value `Domino.get_suit()/get_rank()` don't recognize, silently behaving as "high." `follow_me_doubles_mode`, `follow_me_allow_as_points_bid`, and `allow_small_end_opening_lead` are saved/loaded but never consulted by game logic. `sevens_tie_rule` is a documented stub (only "earliest" implemented, not player-exposed). Flagged as pre-alpha-build cleanup; not scheduled this session.
4. **Follow Me dead code (real, bounded, not yet addressed).** The ratified convention is Follow Me = trump `-1` in the trump panel. `Bid.Type.FOLLOW_ME` still has full validation/scoring machinery, unreachable from `eligible_contracts()`. Needs an explicit decision (amend the convention, or delete the dead branches) — not urgent.
5. **Difficulty doctrine vs. implementation gap (transitional, not a contradiction).** `decide_play()` has six bare `difficulty ==` branches that the file's own doctrine says should eventually be `AI_MODES` parameters. This is Phase 3 not yet landing, not drift. One open design question flagged for later: whether the Expert partner's "no trust rule" branch represents better judgment or reduced trust — matters for what `trust_threshold` should mean when it's wired in.
6. **Smaller loose ends (real, low priority).** `_is_last_to_act()` defined and unused (scaffolding for BUG-004). `_log_bid_decision()` recomputes Layer 2 scoring instead of receiving it. `node_2d.gd` rotates turns the opposite direction from the game's `(n+3)%4` convention (pre-AI test harness, harmless). One doc/logic mismatch in `_absorb_trick()`'s Sevens-only comment (harmless, undersells what the guard does).

---

## Fix 1 — Ranking unification (implemented, verified in code this session)

**Problem:** `_beats()`, `_highest_in()`, `_lowest_in()`, `_partner_is_winning()`, `_current_winning_domino()`, and `_find_current_winner_id()` all called `Domino.get_rank()`/`get_suit()` with a hardcoded `"high"` and never passed `doubles_trump_reversed` — diverging from `Trick`'s and `PublicKnowledge`'s mode-aware ranking. Notably, this bug had already reached the brand-new Expert void-lead branch: it correctly identified suit (via `trick.nello_doubles`) but picked the "highest" domino in that suit using the broken ranking.

**Fix:** All six helpers gained two new trailing parameters (`nello_doubles: String = "high"`, `doubles_trump_reversed: bool = false`, defaults preserve old behavior for any caller that doesn't pass them). Every call site inside `decide_play()` — Nello, MARKS/Plunge/Splash, partner leading/following, opponent leading/following, the strong-counter-lead threshold check, and the void-lead branch — now threads `trick.nello_doubles, trick.doubles_trump_reversed`. `trick` was already a `decide_play()` parameter, so nothing new needed to be plumbed in from outside `ai_player.gd`.

**Status: implemented, verified against project files.** No behavior change under standard settings; only Nello-low, Nello-own-suit, and doubles-trump-reversed hands are affected.

**Reason strings:** checked all of them — none needed rewording. They're written at the intent level ("Playing low to avoid taking this trick," "I have trump control") rather than describing ranking mechanics, so they stay accurate regardless of which domino the corrected logic picks. Two spots flagged for extra attention in playtest, since *behavior* changes even though *wording* doesn't: the Nello branch under doubles-low/own-suit settings, and the opponent strong-counter-lead check (`get_rank(...) >= 4`) under `doubles_trump_reversed`, since that one gates on a numeric threshold rather than pure intent.

---

## Fix 2 — MARKS / Plunge / Splash share one objective (implemented, verified in code this session)

**Design resolution:** two separate questions were identified — (1) *what is the objective of this contract?* and (2) *how does a player pursue that objective?* Marks, Plunge, and Splash all answer (1) identically: win every trick, counters irrelevant. Whether Plunge play should differ from Marks play in *how* it's pursued is (2), deliberately deferred — "can wait years if necessary."

**Fix:** The MARKS-only branch's condition widened to `contract == BidScript.Type.MARKS or contract == BidScript.Type.PLUNGE or contract == BidScript.Type.SPLASH`, and the section header/comment renamed to `MARKS / PLUNGE / SPLASH` with a note that this just brings play in line with what `resolve_hand()` already scores. No other logic in that block changed — the existing cardinal-rule caveat (partner never steals a trick the human is winning, pending a ruling on override cases) now also governs Plunge/Splash for free, correctly, since it's the same open question either way.

**Status: implemented, verified against project files.**

---

## Architectural principle ratified this session — `PublicKnowledge` is a vocabulary layer, not a decision layer

Resolves a previously-stalled Phase 4 discussion about whether "void/suit tracking is significant architecture." Landed on: Phase 4 is not a new decision system or AI capability layer — it's an inert vocabulary of objective, publicly-derivable facts. `void_suits()` is already exactly this shape; the principle is "keep building things shaped like `void_suits()`."

**Three strict properties:**
1. Every query has exactly one correct answer, derivable entirely from `PublicFrame`.
2. It never evaluates those facts, assigns meaning, or recommends a play.
3. It returns the same answer regardless of AI difficulty or personality — different AIs may ignore a fact, but must never receive different facts.

**Two locked constraints:**
- **No re-introduced split-brain.** Any ranking-dependent query (e.g. a future `highest_remaining_trump()`) must delegate to the same canonical comparison functions `Trick` and `AIPlayer` use (`Domino.get_rank`/`get_suit`, `AIPlayer._beats`) — never re-derive comparison logic locally. Stated as: *"PublicKnowledge may compare values, but it must never define what those values mean."*
- **Non-applicable domains handled explicitly.** Queries with no meaning under a given contract (e.g. "trump remaining" under Sevens) must return a defined sentinel/null/empty result, never a silently-computed but meaningless number.

**Sequencing rule:** the candidate query set splits into two categories before any implementation — ranking-free queries (existence checks, void suits, played-tile counts) are safe to build any time; ranking-dependent queries (anything relying on ordering, like highest/lowest remaining) wait until Fix 1 above is confirmed correct via playtest, to avoid rebuilding the exact same divergence this session just closed.

---

## Headers — implemented and verified

Two header additions, both confirmed live in project files this session:

- **`public_knowledge.gd`**: full three-paragraph addition to the existing file header, stating the vocabulary-layer contract, the "may compare values but never define what they mean" rule, and the non-applicable-domain rule. Cross-references `ai_player.gd`'s ranking-unification fix by name.
- **`ai_player.gd`**: one-line addition to the existing KNOWLEDGE bullet in the Knowledge/Evaluation litmus-test doctrine block, pointing back to `public_knowledge.gd`'s header rather than restating the contract.

**Status: implemented, verified against project files.**

---

## PublicKnowledge query set — candidate list refined, then implemented and verified this session

Following the header work, the session moved into scoping a concrete initial query set for the vocabulary layer, then specced and confirmed all six queries live in `public_knowledge.gd`.

**Refinement process (worth preserving for future query additions):** an initial nine-query candidate list was tightened through several passes:
- `trick_leader_so_far()` was reclassified from "ranking-free" to "ranking-dependent-but-safe" — determining a winner is inherently comparative, but since `Trick.determine_winner()` already exists and was never part of the ranking split-brain, this query is a pure delegate with no new comparison logic, so it didn't need to wait on Fix 1 like the other ranking-dependent queries do.
- `current_trick_plays()` was explicitly labeled a **snapshot accessor**, a third category distinct from fact-derivation queries — pure frame passthrough, no inference, kept in `PublicKnowledge` only so callers have one door rather than reaching into `frame.current_trick` directly.
- `legal_follow_options(player)` and `player_has_seen_all_trumps()` were **cut**, not deferred: the former requires private hand knowledge (already correctly handled by `Trick.get_legal_moves()`/`game.get_legal_moves()`, which take the hand as an explicit argument); the latter is either redundant with `count_remaining_trump() == 0` or ill-defined depending on reading.
- `trump_control_state()` and `safe_lead_suits(player)` were reclassified from "deferred" to "doesn't belong in this file" — both are evaluative ("control," "safe") or depend on a specific player's hand, and belong in `AIPlayer` as derived judgments built from `PublicKnowledge` facts, not as facts themselves.
- `highest_remaining_trump()`, `lowest_remaining_in_suit()`, `best_remaining_card_for_suit()` remain genuinely deferred — not blocked by any code dependency (they'd call `Domino.get_rank()`/`get_suit()` directly, which were never buggy), but held back until Fix 1 has been playtest-confirmed, as a confidence gate rather than a technical one.

**Final safe-now set, specced and implemented this session:**
- `has_been_played(tile: Domino) -> bool` — tile-identity lookup via `debug_string()`, keyed across all completed and in-progress plays.
- `is_void_in(player_id, suit) -> bool` — thin wrapper over the existing `void_suits()`.
- `remaining_count(suit: int) -> int` — counts unplayed dominoes by suit, delegating suit classification through `Domino.get_suit(trump, nello_doubles)` rather than assuming static pip-based suit membership (suit depends on trump/mode, not just pip values). Returns `-1` under Sevens (no suit concept).
- `count_remaining_trump() -> int` — same Sevens guard; correctly returns `0` (not a sentinel) under Follow Me, since "no trump" is a real answer there, not a missing one.
- `current_trick_plays() -> Array` — snapshot accessor, `duplicate(true)` on the way out, matching the duplication discipline already used everywhere else public state leaves its owner.
- `trick_leader_so_far() -> int` — pure delegate to `Trick.determine_winner()`; returns `-1` if no trick is in progress or no one has led yet; inherits correct Sevens handling for free since `Trick` already branches on its own `variant`.

**Implementation notes locked into the spec, worth remembering for future queries:**
- New fields added to `PublicKnowledge`: `_played_tiles` (populated by a new `_record_played()` pass, deliberately separate from `_absorb_trick()`'s void-detection loop since "has this been played" has no leader exemption), plus `_current_trick`, `_trump`, `_nello_doubles`, `_doubles_trump_reversed`, `_variant` — all sourced from the in-progress trick when present, falling back to the most recent `hand_history` record otherwise.
- `remaining_count()`/`count_remaining_trump()` reuse `Deck.build_deck()` for the canonical 28-tile set rather than hardcoding pip ranges — one more instance of delegating to existing code instead of re-deriving it.

**Status: implemented, verified against project files.** Not yet wired into `AIPlayer` or `decide_play()` anywhere — intentionally inert, matching the "vocabulary before consumers" sequencing agreed earlier in the thread.

---

## Fix 1 — playtest confirmation (Nello doubles-low, live trace)

A real Nello doubles-low hand was traced against the log this session. Trick 1: `P0:0:0 P3:0:1 P1:2:2`, won by P3. P0 led `0:0` (a double, lead suit 0); P3's `0:1` followed suit at rank 1; under doubles-low, `0:0` should rank *below* `0:1` — and it did, P3's non-double beat the leading double. Under the pre-fix bug (hardcoded `"high"`), the double would have ranked highest and P0 would have won instead. **This is genuine, positive evidence that Fix 1 is behaving correctly in real play, not just in code review.**

**Gap identified from this trace:** the log had no way to confirm *which* `nello_doubles` mode was active without reverse-engineering it from trick outcomes the way the above analysis did — trump-suit hands get this for free via the existing `[trump=N]` tag, Nello/doubles-trump hands didn't have an equivalent. Fixed this session.

**Fix (implemented, verified in code):** `game.gd::resolve_trick()`'s existing print line extended with a conditional `mode_str` — appends `nello_doubles=<mode>` under Nello, `doubles_trump_reversed=<bool>` under doubles-as-trump, nothing extra otherwise. One print line changed, no decision logic touched, no risk to Fix 1 or anything else. Scoped to the trick-resolution line only (once per trick), not the per-play line — the mode doesn't change trick-to-trick within a hand, so repeating it on every play would be noise rather than new information.

**Known future interaction, not a new bug:** once this is live, testing the Nello "Reversed" doubles button (Finding 3's orphaned `nello_doubles_reversed` setting) will show the log printing `nello_doubles=reversed` while the AI still behaves as `"high"`, since `Domino.get_suit()`/`get_rank()` don't recognize that string. That's the existing orphaned-setting bug becoming *visible* in the log, not something this logging change introduced.

**Status: implemented, verified against project files.**

---

## On the horizon (next steps, in order)

1. **Continue playtesting Fix 1** beyond the one confirmed Nello-low trace — Nello-own-suit and doubles-trump-reversed hands haven't been traced yet, and the two reason-string spots flagged earlier in this doc (Nello branch, strong-counter-lead threshold) are still worth a specific look.
2. **Playtest the still-open Expert void-lead judgment call** (highest vs. lowest lead into a known void) — this predates this session and remains unresolved; it's the gate on building the next `PublicKnowledge` consumer.
3. Once Fix 1 has broader playtest coverage, revisit the deferred ranking-dependent queries (`highest_remaining_trump()`, `lowest_remaining_in_suit()`, `best_remaining_card_for_suit()`) — same delegation rule applies (must go through `Domino.get_rank()`/`get_suit()`, never re-derive comparison logic).
4. Sweep orphaned settings (Finding 3) before the family alpha build — `nello_doubles_reversed`'s lying button first; the new trick-log mode string will now surface this bug directly if/when it's tested.
5. Decide the Follow Me dead-code question (Finding 4) and the Expert-partner trust question (Finding 5) — the latter should be settled before `cooperation_bias` → `trust_threshold` renaming.
6. Whenever `trump_control_state()`/`safe_lead_suits()`-shaped judgments are actually needed, build them in `AIPlayer` as evaluations layered on top of `PublicKnowledge` facts (e.g. `count_remaining_trump()`, `void_suits()`), not as new `PublicKnowledge` queries.

---

## Session closed — handoff note for next session

This thread covered, in order: a full codebase review (six findings), two implemented behavioral fixes (ranking unification, MARKS/Plunge/Splash objective), the `PublicKnowledge` vocabulary-layer principle (ratified and documented in both file headers), six new `PublicKnowledge` queries (implemented, unwired), and a playtest-confirmed verification of Fix 1 with a follow-up logging improvement. Katy is moving to a new chat for the next session — per the session-start protocol below, greet her noting the pickup, then read current project files before any spec work, so the file-reading tool's status is confirmed before continuing.
