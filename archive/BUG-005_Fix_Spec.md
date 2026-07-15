# Spec: BUG-005 fix — `trust_gate` (branch #16) rebuilt on real factors

*Companion to `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md`. Scope: this
touches only the standard-difficulty half of branch #16 (partner following,
trump-only can-win). Expert's "no trust rule" line is untouched — that's a
separate, already-logged open question (see `Phase2_Control_Layer_Audit.md`).
`value_gate` (#25, opponent side) is a related but separate objective
(`CASH_COUNTERS`/contest vs. this branch's `SECURE_FOR_PARTNER`) and is not
touched by this spec — flagged as a candidate follow-up, not bundled in.*

---

## 1. Signature change — `ai_player.gd`, `decide_play()`

Two new trailing parameters, both default-safe — every existing call path
is unaffected.

```gdscript
static func decide_play(
    legal: Array[Domino], hand: Array[Domino], trick: RefCounted,
    player_id: int, partner_id: int, trump: int, reason_log: Array,
    difficulty: String = "standard", is_partner: bool = false,
    contract: int = -1, bidder_id: int = -1,
    public_knowledge: PublicKnowledge = null,
    team_points: Array = [],      # NEW — [team0_points, team1_points]
    bid_value: int = 0            # NEW — 0 means "no margin data available"
) -> Domino:
```

## 2. Call site — `game_table.gd`, `_ai_choose_domino()`

```gdscript
var chosen = AIPlayer.decide_play(
    legal, player.hand, game.current_trick,
    player.id, partner_id, game.trump, reason_log,
    game.settings.ai_difficulty,
    is_partner,
    game.variant,
    game.current_bid.player_id if game.current_bid != null else -1,
    knowledge,
    game.team_points,                                              # NEW
    game.current_bid.value if game.current_bid != null else 0      # NEW
)
```

## 3. New helper — `ai_player.gd`, HELPERS section

Deterministic only. Never estimates who holds what — only eliminates a
specific known domino as a threat when it's provably out of reach (already
played, in our own hand, or every remaining actor is known-void in the
suit it would need to follow).

```gdscript
# The five counting dominoes in standard 42.
const COUNTING_DOMINOES := [[5,0], [4,1], [3,2], [6,4], [5,5]]

# Is there still a live threat in `target_suit` that a remaining-to-act
# player could produce this trick? Returns the specific domino if so,
# null if the threat has been provably eliminated.
static func _live_counter_for_suit(
    target_suit: int, hand: Array[Domino], public_knowledge: PublicKnowledge,
    trump: int, lead_suit: int, remaining_ids: Array
) -> Domino:
    if public_knowledge == null or remaining_ids.is_empty():
        return null
    var all_void = true
    for pid in remaining_ids:
        if not public_knowledge.is_void_in(pid, target_suit):
            all_void = false
            break
    if all_void:
        return null
    var best: Domino = null
    for pair in COUNTING_DOMINOES:
        var d = Domino.new(pair[0], pair[1])
        if d.get_suit(trump, "high", lead_suit) != target_suit:
            continue
        if public_knowledge.has_been_played(d):
            continue
        var in_hand = false
        for h in hand:
            if h.left == d.left and h.right == d.right:
                in_hand = true
                break
        if in_hand:
            continue
        if best == null or d.pip_sum() > best.pip_sum():
            best = d
    return best
```

## 4. Branch replacement — standard-difficulty half of branch #16

Replaces everything from `# Only trump can win.` through the end of the old
`trust_gate` logic. The `if difficulty == "expert":` line above this is
unchanged and not reproduced here.

```gdscript
# Standard: evaluate whether this trick is worth spending trump on.
# Replaces the old turn-order-based check — see AI_Play_Behavior_Bug_Log.md,
# BUG-005, for why that version was gated on the wrong fact.

var acted_ids: Array = plays.map(func(p): return p["player"])
acted_ids.append(player_id)
var remaining_ids = [0, 1, 2, 3].filter(func(i): return not acted_ids.has(i))

# Deterministic worst-case addition: the one specific counter (if any)
# that could still land on THIS trick, capped at its own pip value —
# not a probability, a bound on a single already-identified domino.
var live_counter = _live_counter_for_suit(lead_suit, hand, public_knowledge, trump, lead_suit, remaining_ids)
var worst_case_addition = live_counter.pip_sum() if live_counter != null else 0
var trick_value_worst_case = _estimate_trick_value(plays, trump) + worst_case_addition

# Contract margin: can the side that needs bid_value still reach it, even
# after conceding this trick at its worst case? Symmetric for both roles —
# a 42-point hand is an exact zero-sum partition (25 counter points + 7
# trick points = 42, always), so "can bidder still reach bid_value" and
# "can defenders still hold bidder under bid_value" are the same reachable-
# pool check evaluated from each side's own target.
var margin_survivable = true  # default when bid_value == 0 (no margin data)
if bid_value > 0:
    var our_team = player_id % 2
    var bidder_team = bidder_id % 2 if bidder_id >= 0 else our_team
    var our_target = bid_value if our_team == bidder_team else (43 - bid_value)

    var other_team = 1 - our_team
    var our_points = team_points[our_team] if team_points.size() > our_team else 0
    var their_points = team_points[other_team] if team_points.size() > other_team else 0
    var needed = our_target - our_points

    # Total undecided points remaining after conceding this one trick at
    # its worst case. Not a running multi-trick projection — just this
    # trick's single-event bound subtracted from the fixed 42-point total.
    var remaining_pool = 42 - our_points - their_points - trick_value_worst_case
    margin_survivable = remaining_pool >= needed

if not margin_survivable:
    var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
    reason_log.append("We need this one — can't afford to risk it.")
    return chosen

# Margin is safe (or no data available) — lead economy decides whether
# taking the trick is free or costly.
var candidate = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
var hand_after_win: Array[Domino] = hand.duplicate()
hand_after_win.erase(candidate)
var safe_lead_exists = hand_after_win.any(func(d): return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)

if safe_lead_exists:
    reason_log.append("Trumping in — doesn't cost us anything and secures the trick.")
    return candidate

var safe_discard = legal.filter(func(d):
    return d.pip_sum() != 5 and d.pip_sum() != 10 and not d.is_trump(trump))
if safe_discard.size() > 0:
    var discard = _lowest_in(safe_discard, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
    reason_log.append("Holding back my trump — don't want to get stuck leading next.")
    return discard

# No safe way to hold back — trump in anyway.
reason_log.append("Trumping in to secure this trick for us.")
return candidate
```

---

## Verification checklist (recommended before considering this closed)

1. **The exact scenario that surfaced the original bug:** Trump=2, P0 leads
   5:1, P3 plays 5:0 (currently winning, trick value 6), P2 (partner) is
   void in the lead suit and holds trump-only winning options, P1 still to
   act. Confirm: `live_counter` finds 5:5 (still unplayed, not in P2's
   hand, P1 not known-void in the lead suit) → `worst_case_addition = 10`
   → `trick_value_worst_case = 16`, not 6. Confirm the margin check uses 16,
   not the naive on-table value.
2. **Defending-side margin, run through real numbers:** bidding team at 30,
   defenders at 3, bidder's team at 10 points, worst-case trick value 16 —
   confirm `our_target = 13`, `needed = 10`, `remaining_pool = 13`,
   `margin_survivable = true` (matches the hand-verified example from this
   session).
3. **Lead economy actually changes the outcome**, not just the reason
   string: construct a hand where margin is safe and winning would strip
   the AI's last safe non-trump/non-counter tile — confirm it holds back
   with a safe discard rather than trumping in "for free."
4. **No safe discard available, margin safe, lead economy bad:** confirm
   the final fallback still trumps in rather than crashing or looping —
   this is the one path with no truly good option, and it should degrade
   to committing, not fail silently.
5. **`bid_value == 0` (call site not yet threading real data, or a test
   harness):** confirm `margin_survivable` defaults `true` and the branch
   falls straight to lead economy, matching old-safe behavior rather than
   forcing a commit on missing input.
