# ai_player.gd — Function Map

Reference table of every function in `ai_player.gd`, one line each. Line numbers as of July 14, 2026.

| Line | Function | What it does |
|---|---|---|
| 119 | `evaluate_hand` | Layer 1: scores a hand for a candidate trump suit → estimated tricks/points, trump count, has-double flag |
| 261 | `best_trump` | Runs `evaluate_hand` across all 7 suits, picks the best candidate trump |
| 277 | `decide_bid` | Layer 2: combines EV + control score + auction stance into bid/no-bid and target amount |
| 425 | `_log_bid_decision` | Records a bid decision's full detail into `bid_decisions` for replay/hand history |
| 636 | `decide_play` | The core trick-decision engine — all Selection/Commitment branches for every contract type and role |
| 1289 | `_is_guaranteed_win` | Two-pass check: is a candidate tile a provable guaranteed winner of remaining tricks in its suit |
| 1342 | `_is_lead_safe_against_opponent` | Single-opponent lead-safety check (rank-provably-highest, or opponent void in suit+trump) |
| 1361 | `_is_lead_fully_safe` | Same check, extended to require safety against the whole opposing team |
| 1375 | `_live_counter_for_suit` | Deterministically checks whether a suit's risk-counter (5/10) is still live, via `PublicKnowledge` |
| 1410 | `_worst_case_counter_pip_estimate` | Conservative fallback (always 10) when vigilance can't confirm a live counter |
| 1413 | `_highest_in` | Returns the highest-ranked domino in a pool (mode-aware: nello doubles, trump-reversed, etc.) |
| 1424 | `_closest_to_seven` | Returns the domino closest to pip-sum 7 — Sevens contract only |
| 1434 | `_lowest_in` | Returns the lowest-ranked domino in a pool |
| 1448 | `_lowest_cost_in` | Like `_lowest_in`, but prefers a non-counter tile when one exists (gamble/blind-lead tiers) |
| 1462 | `_pick_partner_discard` | Breaks the all-doubles tie in `_lowest_in` by discarding the double whose suit has least life left |
| 1490 | `_should_evaluate_tactically` | Opportunism roll — decides if an opponent runs real tactical evaluation this decision, or plays reflexively |
| 1493 | `_partner_is_winning` | Geometry check: is the partner currently winning the trick |
| 1499 | `_current_winning_domino` | Returns the domino currently winning the trick |
| 1509 | `_find_current_winner_id` | Returns the player_id currently winning the trick |
| 1524 | `_find_player_play` | Returns a given player's play in the current trick, or null |
| 1534 | `_is_last_to_act` | Geometry check: is this player 4th to act this trick |
| 1540 | `_estimate_trick_value` | Base 1 point + any counter pips already on the table |
| 1548 | `_beats` | Core comparison: does one domino beat another under trump/lead-suit/mode rules |

**Scale notes:** `decide_play` (~653 lines) is over a third of the entire file by itself. `_log_bid_decision` (~211 lines) and `decide_bid` (~148 lines) are the next largest. Everything else is a small, focused helper.

**Comment ratio, measured July 14, 2026:** 1,564 total lines — 632 standalone comment lines (~40%), 119 blank (~8%), ~813 code (~52%). The top header block (lines 1–114) is 76% comment (philosophy/doctrine essay) — the clear extraction candidate. Function bodies alone are ~37.6% comment — more mixed, some legitimate local "why," some bug-history narration that could move to the bug logs instead.
