# AI Explanation Bug Log

*First-pass bug tracking, done to identify where structure was needed before
pausing to continue building that structure. This is currently the whole
file — the next testing pass will likely start a fresh log rather than
append to this one.*

**Status key:** ✓ Fixed | → Parked (needs future work) | ⏳ Waiting on dependency

**Example 1 — Game context:** Human (P0) won bid at 30, trump=5. Human team
won all 7 tricks. Beginner difficulty.

---

### ✓ Issue 2 — Partner explanation is opponent-flavored (Trick 3, Partner)
**Situation:** Human leads 4:4 (winning). Partner must follow suit, holds a
counter in the 4-suit, plays it into human's winning trick. Correct partner
behavior — give count to the winner.
**Was:** "You're winning, but I had to let a counter go."
**Now:** "Putting my points on your trick."
**Why it mattered:** "But" framed a correct, cooperative play as a reluctant
concession. Partners dump counters into guaranteed wins on purpose — the
string should reflect that.
**Architectural note:** First clean example of opponent vs. partner logic
needing different string branches for the same underlying decision code.
Will recur.
**Verified (July 6, 2026):** confirmed live at `ai_player.gd`'s forced-counter
path in the `human_is_winning` block — matches exactly.

---

### ✓ Issue 3 — Partner wins trick but explanation says human is winning (Trick 5)
**Situation:** Partner plays 5:6 into a trump-led trick and wins it.
**Was:** "You've got this one — staying out of your way."
**Now:** "I've got this one." (when partner's chosen tile beats the current
winner)
**Root cause:** Partner was in the `human_is_winning` branch, picked the
lowest non-counter to stay out of the way, but that tile happened to be
trump and therefore won the trick. The string was set at decision time
without checking whether the tile would actually win.
**Fix:** After picking the tile in the `human_is_winning` block, call
`_current_winning_domino()` and `_beats()` to detect whether the play will
win. Branch the string accordingly. Applied to both the non-counter path
and the forced-counter path.
**Correction (July 6, 2026):** this entry was marked ✓ at the time it was
written, but the described fix was never actually applied to the code — a
full-repo grep for `"I've got this one"` and `"Nice hand!"` (see Issue 6)
turned up zero matches prior to today. The *technique* itself was sound and
already precedented elsewhere (the opponent-following discard path already
does exactly this post-selection `_beats()` check), it just hadn't been
carried over to this branch. **Implemented today** at `ai_player.gd`'s
`human_is_winning` block, non-counter and forced-counter paths — matching
the original fix description exactly, including the double-lead branch
staying untouched (a double lead is structurally unbeatable there in the
normal case, so no check was needed or added).

---

### ✓ Issue 5 — Last trick: "discarding low" is irrelevant noise (Trick 7, Opponents)
**Situation:** Final trick. Opponents have one tile left and no path to win.
**Was:** "Can't win this one — discarding low."
**Now:** "No way to win this one." (when `hand.size() == 1`)
**Why it mattered:** On the last trick there is nothing to save for later —
mentioning a discard strategy is meaningless noise. The `hand.size() == 1`
check gates the new string; normal tricks keep the existing string.
**Verified (July 6, 2026):** confirmed live at both discard branches in the
opponent-following block — matches exactly.

---

### ✓ Issue 6 — Partner last trick should feel celebratory (Trick 7, Partner)
**Situation:** Last trick, human's team is winning the hand. Partner is
staying out of the way.
**Was:** "You've got this one — staying out of your way."
**Now:** "Nice hand!" (when `hand.size() == 1`)
**Implementation:** Folded into the Issue 3 fix — the `hand.size() == 1`
branch fires naturally inside the `human_is_winning` non-counter path. No
separate pass needed.
**Correction (July 6, 2026):** same discrepancy as Issue 3 — this depended
entirely on Issue 3's fix existing, which it didn't. **Implemented today**
alongside Issue 3; `"Nice hand!"` now fires when the win-check passes and
`hand.size() == 1`, in both the non-counter and forced-counter paths.

---

### → Issue 1 — Follow-suit + counter protection conflated (Trick 3, Left Opponent)
**Situation:** Human leads 4:4. Left Opponent holds 1:4 (counter) and 2:4
(non-counter), must follow suit. Correctly plays 2:4.
**Current string:** "Can't win this one — discarding low."
**Problem:** "Discarding low" implies a free choice. This was a forced
follow-suit play where the interesting decision was protecting the 1:4
counter. A new player won't understand why 1:4 wasn't played.
**Target tone:** "Had to follow suit — protecting my count." or similar.
**Parked because (original):** Requires knowing whether the play was
follow-suit-forced vs. a free discard. This context branches cleanly off
the discard path but intersects with the cross-cutting pattern below. Hold
until that pattern is addressed.
**Correction (July 6, 2026):** the blocking fact this was parked on
(forced-follow-suit vs. free discard) already exists in code and is already
used — `legal.size() == 1` gates a `"Had to follow suit."` string in the
opponent-following discard path today (both branches). That's a real,
already-shipped partial fix for exactly this complaint; it just predates
this log entry being written, or was never cross-referenced against it.
**Remaining scope, narrowed:** the specific "protecting my count" flavor
text isn't there — `"Had to follow suit."` doesn't say *what* was being
protected. That's a much smaller, no-longer-blocked refinement (checking
whether the forced tile, or a tile in the same legal set, was a counter is
local hand geometry, not a Phase 4 dependency) — not implemented today,
left for a future pass since it wasn't part of what was asked for this
session.

---

### → Issue 4 — Fewer tiles in hand = more nuanced discard reasoning (Tricks 5 & 6, Opponents)
**Situation:** Later in hand, opponents can't win but are choosing which
tile to part with. Left shielding count; Right holding a double.
**Current string:** "Can't win this one — discarding low."
**Problem:** By mid-to-late hand "discarding low" is too thin. What matters
is what they're protecting.
**Target tones (directional):**
- Protecting a counter: "Can't win — want to hold my count."
- Protecting a double: "Can't win — trying to hold onto my double."

**Parked because:** Depends on knowing what the AI is protecting — context
that intersects with void/suit tracking. These strings will need to evolve
again once tracking exists. Flag for revisit after Phase 4 scaffolding is
in place.
**Verified (July 6, 2026):** still accurate — the generic `"Can't win this
one — discarding low."` fallback is unchanged for the mid-hand, non-forced,
non-last-trick case. No counter/double-specific flavoring exists yet.

---

### → Issue 7 — Bland partner yield on non-counter discard (Trick 4)
**Situation:** Partner discards a low non-counter while human is winning.
Play is fine.
**Current string:** "You've got this one — staying out of your way."
**Problem:** Not wrong, just flat. When void tracking exists, this is the
place to say something like "That's the high 4, nice play!" — acknowledging
the human's lead tile.
**Parked until:** Void/suit tracking is implemented.
**Verified (July 6, 2026):** `PublicKnowledge` (the void/suit tracking
mechanism this was waiting on) now exists and is live elsewhere in the
codebase — but it isn't consulted anywhere in reason-string generation yet.
This narrows the blocker from "the infrastructure doesn't exist" to "the
infrastructure exists but isn't wired into strings" — a smaller, more
concrete follow-up than when this was written, still not done.

---

### ✓ Issue 8 — Forced-overtake plays "I've got this one" on a tile that then loses (Trick 5, Partner)
**Situation:** Human is winning, but every legal play beats the human's own
card — staying under is structurally impossible (BUG-008, `AI_Play_Behavior_Bug_Log.md`
Pattern F). The old code picked lowest-legal reflexively anyway.
**Was:** "I've got this one." — fired whenever the win-check (`_beats(lowest,
winning_domino)`) passed, without distinguishing "picked to win" from
"forced to overtake with the worst available tile, likely to lose it back."
**Now:** the forced-overtake path has its own honest strings instead of
falling through to the old check: "Taking it with my double — nothing beats
this." (a guaranteed winner is held), "Had to take it — nobody left to
answer." (last to act, any winner holds), "Had to take it — playing my
strongest to make it stick." (not last to act, no guaranteed winner —
escalates to the strongest overtake rather than the weakest).
**Root cause:** same shape as Issue 3 — a string set without checking
whether the specific situation (forced vs. free choice) it was firing in
actually supported the claim. Issue 3 was about a free choice tile that
happened to win; this is about a forced, structurally-unavoidable overtake
that had no "stay out of the way" option at all.
**Fixed as part of:** `AI_Play_Behavior_Bug_Log.md` BUG-008, July 12/13, 2026.
Both the partner-side and opponent-side (`partner_winning`) mirrors got the
new strings. The pre-existing non-forced yield strings ("I've got this
one.", "You've got this one — staying out of your way.") are untouched —
they still apply correctly whenever a real protect option exists.

---

## Cross-cutting pattern — the discard path

The opponent-following discard fallback (`"Can't win this one — discarding
low."`) was originally reached in at least three meaningfully different
situations:

1. Forced follow-suit with counter protection at stake (Issue 1)
2. Free discard mid-hand with a double to protect (Issue 4)
3. Last-trick forced play (Issue 5 — ✓ fixed)

**Status update (July 6, 2026):** two of the three context dimensions this
section called for are now implemented — forced-follow-suit vs. free
discard (`legal.size() == 1`, see Issue 1) and mid-hand vs. last-trick
(`hand.size() == 1`, see Issue 5). Only the third — counter-present vs. not,
and what specifically is being protected (Issues 1's "protecting my count"
flavor, Issue 4's counter-vs-double flavor) — remains unimplemented, and
notably does **not** require Phase 4 void tracking the way this was
originally framed; it only needs local hand geometry (what's in `legal`/
`hand` right now), the same as the two dimensions already done. Revisit
this section's "requires Phase 4" framing next time it's touched — it's
half stale.
