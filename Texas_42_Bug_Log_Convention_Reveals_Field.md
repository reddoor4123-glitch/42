# Texas 42 — Bug Log Convention: The "Reveals" Field

### Purpose of this doc
A process addendum, not a code change. Establishes a new convention for all three bug logs (`AI_Explanation_Bug_Log.md`, `AI_Play_Behavior_Bug_Log.md`, `AI_Bid_Behavior_Bug_Log.md`) going forward. Grew out of reviewing a batch of reason-string findings and noticing the logs were only answering "patch or defer?" when the more useful question is "what does this tell us about the system?"

---

## The problem this fixes

The existing status key — `✓ Fixed | → Parked | ⏳ Waiting on dependency` — only tracks disposition. It doesn't capture *why* an entry was parked, or whether several parked entries are actually waiting on the same missing thing. Read individually, six string bugs look like six unrelated one-off fixes. Read for pattern, several of them are usually the same missing fact surfacing at different call sites.

This matters especially for reason-string bugs, where the temptation is always to patch the words at the call site rather than ask whether a fact is missing from the system that would make the right words fall out naturally everywhere at once.

---

## The fix: a "Reveals" field, logged before Status

Every bug log entry gets one new field, sitting between the symptom and the status:

- **Symptom** — the wrong string or behavior (unchanged from current logging).
- **Reveals** — classify as exactly one of:
  - **AVAILABLE** — the fact this call site needed already exists somewhere in the codebase (a helper like `_beats()`, `legal.size()`, `hand.size()`, `_find_player_play()`, or a `PublicKnowledge` query) but this particular call site never consulted it. Safe to patch now, using the existing fact — no new architecture required.
  - **UNBUILT** — the fact doesn't exist anywhere yet (e.g. void-tracking-derived context, a "high-probability vs. certain" distinction, forced-follow vs. free-discard state). Park it, and name *which future piece* it's waiting on — same as the informal notes already attached to Issues 4 and 7, just made a required field instead of optional prose. **An UNBUILT entry identifies the missing fact, not the implementation.** "Needs to know whether the trump double has already been played" belongs in the log; "add `highest_remaining_trump()` to PublicKnowledge" belongs in a spec, written later, once the pattern across entries justifies it.
  - **ONE-OFF** — no fact model fits; it's just a wrong word or wrong tense with no architectural implication. Patch now, nothing to learn from it.
- **Status** — same ✓ / → / ⏳ key as today. Now it's a *consequence* of Reveals rather than an independent judgment call.

**Every entry gets exactly one Reveals category — never more than one.** If an entry seems to fit multiple categories, that's a signal the diagnosis isn't finished, not a reason to tag it twice. Keep refining until one clearly dominates. The goal is to classify the underlying missing fact, not enumerate every symptom it happened to produce — this is precisely how a batch of five separate-looking string bugs turns out to be one missing query surfacing five times, or vice versa.

## Why this earns its keep

The point isn't the taxonomy for its own sake — it's the aggregation it enables. Once entries are tagged this way:

- Several **AVAILABLE** entries pointing at the same missing call (e.g. "post-selection `_beats()` check missing at N sites") collapse into a single spec item instead of N separate patches.
- Several **UNBUILT** entries pointing at the same missing fact (e.g. multiple strings all needing "is there still a counter in hand" or "is this the last trick, seat-agnostic") become direct evidence that fact belongs in decision geometry or `PublicKnowledge` — the pattern itself is the trigger for building it, the same way "does this belong in the existing system?" already gates other design decisions in this project.
- **ONE-OFF** entries stay exactly as cheap as they are today — this convention adds no overhead to the bugs that were never going to teach us anything.

## How this fits the project's existing conventions

This isn't a new idea, just an existing one applied one level up. `ai_player.gd` already runs difficulty branches through a KNOWLEDGE / EVALUATION / NEITHER litmus test before allowing a new `if difficulty == ...` branch. Reveals is the same discipline applied to *strings* instead of *decisions*: before patching a call site, classify whether the missing piece is already available (AVAILABLE), not yet built (UNBUILT), or genuinely doesn't need to exist (ONE-OFF) — and let that classification, not a case-by-case judgment call, decide whether the right move is a patch or a parked architectural note. One doctrine classifies new behavior; this one classifies new bugs. They reinforce the same architectural habit from opposite directions.

## Applying this retroactively

Not required as a cleanup pass. Apply going forward on new entries; backfill existing parked entries (Issues 1, 4, 7, and others) opportunistically if revisited, but there's no need to stop and retag the full existing logs before continuing other work.

---

## Worked example (from this session's review)

**Symptom:** Partner assumes a double-lead is a guaranteed win and dumps a counter onto it, regardless of whether that double is trump.

**Reveals:** Initially misclassified as UNBUILT (a missing "is this actually a guaranteed win" fact) — this was wrong. `evaluate_hand()` already scores all doubles at a flat high win probability regardless of suit; the "dump count on a double" trigger is intentional, established evaluative design, not a decision-logic gap. The actual gap is narrower: the word "safe" / "guaranteed" in the reason string and code comment overclaims a high-probability bet as a certainty. Correctly reclassified as **ONE-OFF** — a wording fix only, no trigger-condition change, no architectural implication.

**Status:** Patch the string only (soften "safe"/"guaranteed" language); leave the `is_double()` trigger untouched.

This is exactly the kind of misfire the Reveals field is meant to catch early — the first classification pass called something UNBUILT that a second look showed was ONE-OFF, and having to commit to one of the three labels is what surfaced the correction.
