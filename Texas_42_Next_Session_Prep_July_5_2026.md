# Texas 42 — Next Session Prep (written July 5, 2026)

### Purpose of this doc
Not a session summary — a prep doc written the night before, so tomorrow's
session can start straight into the work instead of re-deriving where things
stand. Order below is deliberate: start with the confirmed bug (cheap,
bounded, no open design questions), then move into the two connected design
conversations.

---

> **⚠ Superseded on trust_gate/trust_threshold, same day.** This prep doc
> was written before `Texas_42_Session_Summary_July_5_2026_Phase2Architecture.md`
> landed (also dated July 5). That session summary documents that
> BUG-005's fix to branch #16 (`trust_gate`) is already implemented and
> playtest-confirmed — the branch now runs on contract margin, live
> counter status, and lead economy, with no trust or turn-order content
> left. Any item below that assumes `trust_gate` is still turn-order-based
> or that `trust_threshold` is a live open design item should be re-read
> against that summary first, not against this doc's original framing.
> Items unrelated to trust_gate (Nello Reversed toggle, etc.) are
> unaffected and still accurate.

---

## 1. Start here — Nello "Reversed" toggle: real fix needed

Confirmed via code trace, not guesswork: this is genuinely broken, in two
independent ways, and Katy's "I can't find it in the menu" report is exactly
what the code predicts.

**Bug A — the button can never appear through normal play.**
In `game_table.gd`:
```gdscript
_nello_reversed_btn.visible = false                              # at creation
...
_nello_reversed_btn.visible = game.settings.nello_doubles_reversed  # _show_nello_panel()
```
Visibility is gated on `game.settings.nello_doubles_reversed` — but nothing
in the UI ever sets that flag to `true`. Every assignment site is either a
hardcoded `false` or a load from a save file. It's circular: you'd need the
flag already on to make the control that's supposed to turn it on appear.

**Bug B — even if it appeared, it wouldn't do the right thing.**
Pressing the button calls `_on_nello_mode_selected("reversed")`, which sets
`game.active_nello_doubles_mode = "reversed"` — a **string** value that
`Domino.get_suit()` / `get_rank()` don't recognize, so it would silently
fall back to `"high"` behavior. Note this is a different variable from the
`nello_doubles_reversed` bool in Bug A — the button conflates two things
that were never actually wired to each other.

**What "Reversed" is supposed to mean:** per the code comment,
`nello_doubles_reversed` is scoped specifically to **own_suit mode** —
"within own_suit mode, double-blank is highest" (i.e., a within-mode
inversion, not a fourth top-level doubles mode). That's worth confirming
out loud before respeccing: should the button only be reachable/visible when
`"own_suit"` is the selected doubles mode, rather than sitting in the same
row as High/Low/Own Suit as a fourth equal option?

**Suggested approach for tomorrow:** treat this as a small, bounded, two-part
fix — (1) real UI control that actually sets the bool (probably nested under
Own Suit rather than a sibling button), (2) thread that bool into the
ranking calls the same way `doubles_trump_reversed` already is, rather than
routing it through the unrelated string-mode variable. Should be quick once
scoped — good warm-up before the bigger design conversation.

**Update (confirmed July 5, 2026):** The two-bug diagnosis above (button
never reachable / button sets an unrecognized string) does not match
current code. Tested directly: the settings-screen checkbox ("Allow Own
Suit (Reversed)") correctly gates the per-hand button's visibility, and
both "Own Suit" and "Own-Suit Reversed" play correctly. Closed — no code
changes needed. The doc's diagnosis was either stale by the time it was
written or already fixed in the same session; not chasing which.

---

## 2. Design conversation — what does "highest vs. lowest" into a known void actually depend on?

This is the reframe from tonight, worth writing down precisely before it's
lost to memory: **this was never a single fact to resolve.** `FORCE_A_VOID`
is currently written as one fixed execution (always lead highest, always
maximize pressure) — but the real behavior at a table isn't "always
aggressive," it's **intent-dependent**: sometimes you want to maintain
control, sometimes you want to pass the lead safely, and which one applies
isn't visible from the geometry alone (a known void) — it needs a second
signal.

That makes this structurally the same shape as `COMMITMENT_GATE` from the
Phase 3 audit — a geometrically-valid objective that needs an additional
signal before committing to a specific execution. Worth asking directly
tomorrow: **is `FORCE_A_VOID`'s aggressive/conservative fork actually a
third instance of the commitment-gate pattern**, sitting on the same
mechanism as `trust_threshold` / `contest_threshold`? If so, it's not a
Phase 4 loose end sitting next to Phase 3 — it's *inside* Phase 3's
commitment-gate work, and should be designed alongside it, not separately.

Candidate signals to consider for what decides the fork (none committed to
yet):
- Contract math — is the hand already numerically safe enough to spend
  resources being aggressive, or does it need to conserve?
- What's already in the current trick.
- Something from the trust/commitment layer already being scoped for
  `trust_threshold`.

Not something to resolve alone overnight — flagged explicitly as a
conversation to have together, not a spec to write blind.

---

## 3. Phase 3 `AI_MODES` collapse — the audit is the working document

`Phase3_Objective_Audit.md` is the reference for this entire conversation —
it already has the branch table, the two confirmed commitment-gate
instances (#16 `trust_gate`, #25 `value_gate`), and the surfaced
`AI_MODES` candidates (`trust_threshold`, `contest_threshold`).

**Superseded (July 5, 2026, same day).** `trust_gate` (#16) was rebuilt under BUG-005 the same
day this prep doc was written for — see `AI_Play_Behavior_Bug_Log.md` and
`Phase3_Objective_Audit.md`. It no longer has any trust content, which changes both items below:

1. ~~Revisit whether `trust_gate` and the void-lead fork (from §2) really do
   share one mechanism — if so, design it as one thing with multiple
   inputs, not two unrelated parameters.~~ Moot as originally framed — `trust_gate` isn't a trust
   mechanism anymore, so there's nothing of that shape left to share with the void-lead fork. The
   void-lead aggressive/conservative fork itself (§2) is still open on its own merits.
2. ~~Settle the still-open Expert-partner trust question from the Ranking
   Unification session: does the Expert partner's "no trust rule" represent
   *better judgment* or *reduced trust*? This has to be answered before
   `cooperation_bias` → `trust_threshold` can be renamed correctly, since
   the rename's meaning depends on the answer.~~ Reframed by `Difficulty_Feed_Points_Inventory.md`
   as a concrete, testable question instead: does Expert still need a separate bypass at all, now
   that the branch it bypasses has no trust content? Recommended as the next thing to try, not
   yet tested. `trust_threshold` currently has no confirmed source branch regardless of the
   answer — don't resume that rename by default.
3. Only after 1–2: start actually collapsing the six bare `difficulty ==`
   branches into named `AI_MODES` parameters, branch by branch, using the
   audit's Knowledge/Evaluation/Neither classification per branch. See
   `Difficulty_Feed_Points_Inventory.md` for the current per-branch breakdown of which of the six
   are ready to leave alone, ready to test, or still need their own audit session.

**Small flagged item to fold in whenever convenient (not urgent, not
blocking):** branch #25 (`value_gate`)'s failure path currently reuses a
generic "can't win" reason string, which is inaccurate — the AI *can* win
there, it's choosing not to contest. Candidate line item for the Phase 1
reason-string rewrite, not something to fix in isolation.

---

## Backlog — unchanged, no urgency

- ~~MARKS cardinal-rule branch (stealing a partner's already-winning trick
  under Marks) — deferred pending concrete example hands from Katy.~~
  **Resolved July 5, 2026** (same day, later session) — this turned out not to be a Marks-specific
  question at all. It's the long-horizon lead-control concept, now permanently parked in
  `Phase1_Control_Layer_Audit.md`: not blocked on more examples, deliberately not being built.
- Phase 1 reason-string rewrite (~24 strings, fully specced, not applied).
- Orphaned settings sweep beyond `nello_doubles_reversed`:
  `follow_me_doubles_mode`, `follow_me_allow_as_points_bid`,
  `allow_small_end_opening_lead`. (~~`sevens_tie_rule`~~ — verified genuinely
  orphaned, never consulted anywhere, no UI control existed for it either;
  deleted entirely July 6, 2026 rather than wired up.)
- Follow Me dead-code decision (amend convention vs. delete dead branches).
- AI special contract bidding (Nello/Sevens/Plunge/Splash initiation).
- Mobile portrait layout pass; hardcoded font sizes.
- Replay scene v2 (after reason strings are settled).
- Custom domino backs per ruleset (`back_style` stub already on `DominoTile`).

---

## Session start protocol (unchanged)

Greet Katy noting the pickup from the previous session, then immediately
read current project files before doing anything else. Before any spec work
on judgment-heavy behavior, ask: *"Does this belong in the existing system
at all?"* — directly relevant tomorrow for both the Reversed toggle (is this
a UI bug or a ranking-logic bug?) and the void-lead fork (is this really a
new mechanism, or does it already belong inside commitment-gate?).
