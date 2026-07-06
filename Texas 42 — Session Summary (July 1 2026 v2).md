# Texas 42 — Session Summary (July 1 2026 — v2)

### Purpose of this doc
Full context handoff for a new Project chat. All `.gd` files should be current in Project knowledge. Items marked ✓ are confirmed implemented. Items marked → are next.

---

## Design philosophy (read first)

**Table behavior first.** Katy describes how people behave at a real 42 table. That description is the most compressed, most precise form of design intent — not flavor text. The correct first question when hearing table behavior is "does this belong in the existing system at all?" — not "how do we tune the existing system?" Sevens and Nello both turned out to need completely separate branches, not tuning of the standard logic.

**Authenticity over intelligence.** The AI should feel like people Katy has actually played with, not discover clever strategies that experienced players wouldn't use. When authenticity and optimization conflict, authenticity wins.

> *"That partner plays just like Uncle Ed."* — that's the target.

**New session protocol addition:** Before any spec work on judgment-heavy behavior, ask: *"Does this belong in the existing system at all?"*

---

## What was implemented (prior session — all confirmed working)

1. **Uncle Ed rename** — `ai_player.gd` line 22.
2. **Sevens AI + Nello opponent AI** — separate branches at top of `decide_play()`, completely bypass standard evaluation.
3. **Layer 1 evaluator fix** — Expected Capture Model. `est_pts` = expected value of what this hand can capture from the table (`estimated_tricks * 6.0`). `realization_bias` retained as diagnostic only.
4. **Layer 2 unified scoring + auction stance modifier** — combines EV score, control score, and stance bias. Stance classifies hand intent: `pressure_opener` / `solid_opener` / `competitive` / `defensive`.
5. **Layer 3 minimum bid floor fix** — when `should_bid=true` and `target_bid < min_points`, raises `target_bid = min_points` before comparison.

---

## What was specced this session

### ✓ Replay Explanations Phase 1 (spec written, not yet confirmed implemented)

Two-file change. Spec is complete and ready for Claude Code.

**`ai_player.gd`:** Rewrite all 24 `reason_log.append()` strings from debug/developer language into player-facing table language. Remove all `% chosen.debug_string()` / `% lowest.debug_string()` / `% discard.debug_string()` suffixes. Remove `%d trumps` format argument from trump-lead strings (lines 383, 496). Full replacement table is in the spec written during this session — retrieve from conversation history if needed.

**`game_table.gd` — Change A:** Remove live status explanation during active play. In the AI play chooser function (~line 1232), remove the `_set_status(...)` call that displays `reason_log[0]`. Keep `_last_play_reason = reason_log[-1]` — it feeds replay.

**`game_table.gd` — Change B:** Improve `_render_replay_trick()` winner annotation. Replace the existing `"\n✓ Won trick"` append with a version that calculates trick point value from `trick_record["plays"]` and appends `"\n✓ Won trick — N pts"` when any counter was in the trick, `"\n✓ Won trick"` for plain 1-point tricks.

---

## Pending work this session — not yet specced

### → Counter-dumping fix (Phase 1 Cooperation correctness)

**The bug:** In a Follow Me (no trump) contract, partner AI holds counters when the human leads the double of a suit — a guaranteed win — instead of dumping them into the trick. This caused a 30-point contract failure in a confirmed log: partner held 20 points across three counters (1:4, 4:6, 0:5) that were eventually captured by opponents.

**Root cause:** The `human_is_winning` branch in `decide_play()` has one unconditional policy: "play lowest non-counter, protect all counters." This is correct when the win is uncertain (might be overtrumped). It is wrong when the win is guaranteed, because protecting a counter that will eventually go to an opponent is strictly worse than dumping it now.

**Agreed fix scope:** When `trump == -1` (Follow Me) AND the current winning domino is the double of the lead suit (i.e., `winning_domino.is_double()` is true), reverse the counter policy: prefer playing counters into the trick over protecting them. This covers the follow-suit case (must follow, choose counter over non-counter). The free-discard case (can't follow, choose what to throw off) is a separate question — discuss scope before speccing.

**Not in scope yet:** Trust axis, Win Safety calculation, trump-game guaranteed wins. Those are Phase 2–4 territory.

**Also identified:** The Points vs Marks gap (see below). Decide whether to fold into this spec or separate ticket.

---

## Architecture: the four phases

The phases are **capability layers**, not difficulty labels. They represent what information and judgment the AI has access to. Each phase builds on the ones below it. A broken Phase 1 means Phase 2–4 are meaningless.

```
Phase 4 (Awareness)     — knows what's been played
    ↓  feeds
Phase 3 (Opportunism)   — recognizes exploitable openings
    ↓  feeds
Phase 2 (Risk / Trust)  — calibrates how aggressively to act
    ↓  feeds
Phase 1 (Cooperation)   — ensures the intent is always right
```

### Phase 1 — Cooperation ← YOU ARE HERE
*What it gives:* The partner knows whose side they're on and acts accordingly.

The foundation. Without it nothing else matters. Every other phase assumes Phase 1 is correct.

Current state: substantially implemented. Cardinal rules in place (never steal partner's winning trick, try to win for team, trust rule). Two known gaps:
- Counter-dumping on guaranteed wins (see above)
- Points vs Marks contract distinction (see below)

Phase 1 behavior should be identical at all difficulty levels — it's about *intent*, not *capability*. Partner is always cooperative. What changes with difficulty is how well that intent is executed (Phases 2–4).

### Phase 2 — Risk / Trust *(partially implemented in bidding only)*
*What it gives:* Personality. The AI knows how aggressively to act given its current read on the situation.

In bidding: `risk_bias` and `max_overbid` exist and work. In play: the `cooperation_bias` key in `AI_MODES` is the intended placeholder, currently read and immediately suppressed with `@warning_ignore`. Not yet wired to any behavior.

**Trust** lives here. Trust is a difficulty-scaled threshold that controls how aggressively the partner acts on *uncertain* Win Safety estimates. It answers: *"How confident do I need to be that this trick is safe before I dump a counter into it?"*

Key properties of Trust:
- **Bypassed at P=1.0** — guaranteed wins (Follow Me doubles) don't consult Trust. Dumping is correct at every difficulty level.
- **Bypassed by opportunity cost** — if this is clearly the best chance a counter will ever get (e.g., partner has been winning consistently and this is late in hand), a cooperative partner plays it regardless of Trust level.
- **Active in the uncertain middle** — trick 3, partner is currently ahead, no guarantee signal, counter could be played or saved. This is where Trust differentiates beginner from expert.
- **Applies to partner and opponents separately** — partner Trust governs when to dump counters into friendly wins; opponent Trust governs how aggressively to contest tricks against the bidding team.

Phase 2 also governs opponent play aggression — how hard they contest tricks, how much they push back under pressure.

### Phase 3 — Opportunism *(placeholder only)*
*What it gives:* Exploitation. The AI recognizes when something went wrong for the other side and capitalizes.

Examples: recognizing an opponent is void in a suit and leading into it; detecting the contract team is under pressure and contesting harder; partner recognizing trump is exhausted and a counter lead is now safe.

Phase 3 is about pattern-matching on observable signals, not full hand inference. That distinction keeps it implementable before Phase 4.

Current state: `opportunism` key exists in `AI_MODES` with "low"/"medium"/"high" values. Read and immediately suppressed. Two TODO comments mark where Phase 3 logic will eventually plug in (`ai_player.gd` lines 514, 525).

### Phase 4 — Awareness *(not started)*
*What it gives:* Information. The AI knows what's been played and can infer what's left.

Void tracking, suit depletion counts, trump remaining, probabilistic hand inference from bidding and play history. This is what makes Win Safety a real calculation — trick 6 after four sixes have appeared is fundamentally different from trick 2.

Phase 4 is the most complex and most dependent on everything below it being correct first. Not on the near-term roadmap.

---

## Win Safety concept (established this session)

Win Safety is the probability that a partner's current winning position will actually hold at trick resolution. It is separate from Trust — Win Safety is the input; Trust is the threshold that acts on it.

| Win Safety | Source | Trust needed? |
|---|---|---|
| 1.0 — guaranteed | Double of lead suit, no trump | No — always dump counter |
| ~0.8 — very likely | Later tricks, key suit nearly exhausted | Phase 4 needed to calculate |
| ~0.6 — probably | Mid-hand, few signals | Phase 4 needed |
| Unknown | Current state (no tracking) | Falls back to conservative |

The Phase 1 fix targets the 1.0 case. Phases 2–4 progressively handle the rest.

---

## Partner vs Opponents architectural note

Partner and opponents are trying to do opposite things, and difficulty should scale differently for each — but this distinction is not yet explicit in the code. Currently, the same `difficulty` string applies to both through the same `AI_MODES` dict.

**Partner:** difficulty affects *quality of judgment* — how accurately Win Safety is estimated, how well opportunity cost is calculated. Cooperation intent is constant; judgment sharpness varies.

**Opponents:** difficulty affects *intensity of competition* — how aggressively they try to set the contract, how much they capitalize on openings (Opportunism, Phase 3), how well they track what's been played (Awareness, Phase 4).

Long-term, `AI_MODES` may want separate partner and opponent parameter sets rather than one shared profile.

---

## Points vs Marks gap (identified this session, not yet specced)

`decide_play()` receives a `contract` parameter that can be `BidScript.Type.MARKS`, but there is no branch for it. SEVENS and NELLO have dedicated branches; MARKS falls through to standard logic, which means `pip_sum == 5/10` counter protection runs under Marks contracts exactly as it does under Points contracts.

This is wrong. Under a Marks contract, winning every trick is the only objective — counters have no special status, and the AI treating them as precious is incorrect behavior. The counter/non-counter distinction should be invisible to the play logic when `contract == BidScript.Type.MARKS`.

Fix scope: a dedicated Marks branch near the top of `decide_play()` (after SEVENS and NELLO), which instructs both partner and opponents to play to win every trick without counter special-casing. Not yet specced — decide whether to bundle with counter-dumping fix or separate ticket.

---

## Current AI bidding architecture (unchanged)

**Layer 1 — Evaluation** (`evaluate_hand` + `best_trump`): Objective truth. Do not modify.

**Layer 2 — Decision policy**: Combines EV signal + control signal + stance bias into `final_score`. Personality (`AI_MODES`) lives here via `risk_bias` and `max_overbid`.

**Layer 3 — Execution**: Enforces auction legality. Minimum bid floor fix lives here. Do not re-evaluate here.

Bidding behavior confirmed satisfactory. Parked for later: threshold retuning, AI Phase 2 Risk axis in bidding, auction pressure modeling.

---

## Roadmap status

- Rename/delete custom rulesets
- Win-by-two pop-up for Lechner Hall
- Doubles-as-trump UI button in trump panel
- → **Counter-dumping fix** (Phase 1 Cooperation correctness) — spec pending
- → **Points vs Marks play distinction** — identify as separate or bundle with above
- AI Phase 2 Risk / Trust axis — parked pending Phase 1 correctness
- AI Phase 3 Opportunism
- AI Phase 4 Awareness
- Special contract bidding for AI
- Named personality presets after observation
- Hand summary
- Nello refinements (domino exchange, visual sit-out, 3-domino trick pile)
- Sounds and animations (both with toggles)
- Debug/feedback tool pre-publish
- Low-No deprioritized indefinitely

---

## Key technical reminders

- `DOUBLES_TRUMP` sentinel is `7`
- Bid direction string values are `"shaker_left_first"` and `"shaker_right_first"` — never `"clockwise"`/`"counterclockwise"`
- Sevens strict less-than comparison for tie-breaking is correct, never change it
- Follow Me is not a bid type — it is the `-1` trump panel choice
- Always ask clarifying questions before assuming on direction/seating/ordering logic
- GPT is sometimes consulted for second opinions; evaluate honestly rather than dismiss — but the prior session included a GPT-generated bug report that misread bidding log output as play behavior and proposed incorrect 42 strategy. That report was rejected.

---

## Session start protocol

Greet Katy noting the pickup from the previous session, then immediately read current project files before doing anything else, so Katy can confirm the file-reading tool is working before any spec work begins. Before any spec work on judgment-heavy behavior, ask: *"Does this belong in the existing system at all?"*
