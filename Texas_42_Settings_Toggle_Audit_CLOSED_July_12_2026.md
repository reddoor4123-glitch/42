# Texas 42 — Settings/Toggle Audit: Closing Summary (July 12, 2026)

### Purpose of this doc
Final state of the settings/toggle audit that started with one question — "does Partner Sits
Out actually work?" — and grew into a full pass over all ~53 `GameSettings` variables across
several sessions. Everything below is verified directly against current project files, not
against what was specced. The audit is now closed: every setting in `GameSettings` either does
something real, or is deliberately parked with a stated reason.

---

## Built this session — features that went from broken/missing to working

| Feature | What it does now |
|---|---|
| **Force Trump on Opening Lead** | First trick of the hand only, contracts with a real trump suit only (Points/Marks/Plunge/Splash — Nello/Sevens/Follow Me/Low-No were always exempt). Leader's legal moves restrict to trump; falls back to full hand if none held. Applies identically to AI and human via the shared `get_legal_moves()` path. |
| **Doubles Trump Reversed** | Human-only choice at trump-selection time — a second button ("Doubles (Reversed)") sits alongside "Doubles (Trump Suit)" and "No Trump (Follow Me)" in one shared row. Flips ranking so 0-0 is high, 6-6 is low. AI never selects it. |
| **Allow Small-End Opening Lead** | A toggle button ("Open with Small End") appears only on the human's opening lead of trick 1, must be activated *before* tapping a domino. Gold when active, white when not. Leads a non-double, non-trump domino as its smaller-pip suit when on; doubles/trump ignore the toggle safely if tapped while active. |
| **Nello / Sevens — Only on Forced Bid** | New toggle for each. When on, that contract is only offered to the human when they're genuinely the forced bidder (dealer, all three others passed) — reuses the same `is_dealer`/`all_others_passed` context Low-No used to rely on. When off, behaves exactly as before (always available). |

---

## Deleted this session — confirmed dead, removed everywhere

**Settings-only cleanup (no logic anywhere, no UI beyond the dead checkbox where one existed):**
`reshake_if_all_pass`, `nello_all_four_play`, `nello_partner_sits_out`, `score_by_marks`,
`set_penalty`, `count_dominos_in_tricks`, `points_to_win`, `winning_trick_bonus`,
`allow_early_hand_end`, `stack_tricks_display`, `allow_renege_challenge`, `renege_penalty`,
`follow_me_doubles_mode`, `follow_me_allow_as_points_bid`, `sevens_require_minimum_bid`,
`sevens_minimum_bid`, `default_trump_if_undeclared`, `shuffle_style`, `allow_table_talk`,
`nello_minimum_bid`, `nello_bid_value`, `nello_count_as_marks`, `nello_failure_penalty`,
`nello_failure_fixed_points` — **23 settings**, all confirmed to have had zero effect on
gameplay before removal (either never read anywhere, or the behavior they claimed to gate was
hardcoded on regardless of their value). The SCORING and DISPLAY settings-menu sections are
gone entirely as a result.

**Full removal, not just settings (`Bid.Type.LOW_NO`):** the entire Low-No contract — enum
value, `to_mark_equivalent()` case, `is_valid()` block, `debug_string()` case, `apply_bid_result()`
case, `resolve_hand()` block, and its `_finish_bidding()`/`_copy_settings()` references — removed
across `bid.gd`, `game.gd`, and `game_table.gd`. Never reachable by any UI (no contract button
ever offered it), confirmed not part of Teel Rules, and its dealer-gating logic lives on in
shared infrastructure (`Game.bid_context()`), not lost by deleting Low-No itself.

---

## Hidden, not deleted — real features being delayed, settings kept intact

- **Nello Exchange** (`allow_nello_exchange`, `nello_exchange_bidder_gives`,
  `nello_exchange_partner_gives`) — checkbox removed from the Nello submenu; all three settings
  untouched, ready for whenever Exchange gets built.
- **Marks to Win** — UI spinbox removed; setting stays in `GameSettings`, locked at 7 across all
  four presets by deliberate choice (Lechner Hall's exception is handled separately via its
  win-by-two info popup, confirmed already shipped and working).

---

## What's left in `GameSettings` — everything accounted for

- **Working, real UI, real logic:** the vast majority of the file at this point — bidding rules,
  all four special contracts and their sub-options, trump/doubles rules, scoring essentials
  (`marks_to_win`, `win_by_two`), `ai_difficulty`.
- **Wired into logic, deliberately no UI:** `max_open_bid_marks` — locked at 2, confirmed
  satisfactory as-is, no spinbox wanted.
- **Parked by design, not orphaned by accident:** `nello_exchange_bidder_gives` /
  `nello_exchange_partner_gives` (waiting on Exchange), `nello_only_on_forced_bid` (now fully
  wired and working — no longer a placeholder).

No remaining ghost toggles. No remaining hardcoded-on toggles. No remaining settings that exist
in code with zero UI and zero logic. Every variable in `GameSettings` is either doing something,
or is intentionally waiting on a feature that hasn't been built yet.

---

## Session arc, start to finish

1. Full trace of all ~53 settings against UI and logic — found far more ghost toggles than the
   one that prompted the question (Nello Exchange, Force Trump on Opening Lead, Small-End
   Opening Lead, and — on a second, more careful pass — Score by Marks, Set Penalty, Count
   Dominoes in Tricks, Stack Trick Display, plus two "hardcoded-on" cases: Partner Sits Out and
   Allow Early Hand End).
2. Batch deletions across several specs, working section by section.
3. Three real features built from scratch: Force Trump on Opening Lead, Doubles Trump Reversed
   (with a trump-panel layout redesign along the way), and Small-End Opening Lead (redesigned
   once, from a two-button chooser to a pre-play toggle, based on actually seeing it in-game).
4. Nello/Sevens Only on Forced Bid built by reusing Low-No's dealer-gating pattern — after which
   Low-No itself was confirmed safe to remove entirely.
5. Final five-setting Nello scoring cluster traced and confirmed as leftover scaffolding from an
   earlier design direction that never made it into working code — removed.

**Audit status: closed.**
