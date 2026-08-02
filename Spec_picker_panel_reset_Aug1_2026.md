# Spec — Picker panels must not survive a hand restart

**Status:** Implemented August 1, 2026 — both §3.1 and §3.2. Diagnosis verified
against source and reproduced headlessly before the fix. §3 records what actually
shipped, which differs from the first draft in one place; see §3.1.

**Reported by:** Katy's dad, after Nello exchange shipped. Photo shows the Call
Trump screen on-screen above the Nello exchange, with the exchange's interactive
row (the seven tiles + "Don't Trade") pushed below the bottom of the window. Only
the cosmetic face-down partner tile was visible, so the exchange looked broken and
unresponsive. Not reproducible on Katy's own device.

---

## 1. Verified diagnosis

All line numbers are `game_table.gd` as of this commit.

**The four picker panels are siblings in one `VBoxContainer`, in a fixed order.**
`play_vbox` receives them at 1031 (`bid_panel`), 1054 (`trump_panel`), 1150
(`nello_panel`), 1193 (`nello_exchange_panel`) — after `trump_indicator_label`
(969), `play_area_container` (985), `se_holder` (1003) and `status_label` (1026).
A `VBoxContainer` stacks visible children in add order, so a visible `trump_panel`
always renders *above* `nello_exchange_panel` and pushes it down.

**Every panel is opened and closed only by its own handlers.** Complete list of
non-initialiser visibility writes:

| Panel | set `true` | set `false` |
|---|---|---|
| `bid_panel` | 2233 | 2275, 2339 |
| `trump_panel` | 2515 | 2322, 2580 |
| `nello_panel` | 2602 | 2323, 2606 |
| `nello_exchange_panel` | 2635 | 2662, 2669 |

2322/2323 and 2339 belong to the bid-revisit flow (`_open_bid_revisit` /
`_close_bid_revisit`), which is a specific transition, not a general reset. There
is no function anywhere that closes all pickers.

**Neither restart path clears them.** `_start_hand()` (1847–1886) resets
`_hand_over`, `_armed_domino`, `_small_end_active`, the small-end toggle, the
lay-down button, `main_menu_panel`, `preset_panel`, the replay/continue/new-game
buttons and `replay_panel` — and touches none of the four pickers, nor
`waiting_for_bid` / `waiting_for_trump` / `waiting_for_nello_mode`.
`_restart_game_with_settings()` (4112–4122) hides only `settings_panel` and
`preset_panel` before delegating to `_start_hand()`.

**The gear button is unconditional.** Built at 1241–1248 as a child of `root` with
no state gate, so Settings is reachable mid-decision. Its Play button runs
`_commit_settings_and_restart()` (3962) → `_restart_game_with_settings()` →
`_start_hand()`.

**`_start_bidding()` already defends against this exact class of leak — for state,
not for panels.** At 1901–1910 it clears `_trump_preview` and the revisit fields,
commented "a hand abandoned with the panel open must not carry its floor into the
next one." The panel visibility flags were simply missed by the same reasoning.

**The layout failure mode is already documented.** The comment at 3292–3300 on
`_play_area_reserves_height()` records that leaving the diamond's height reserved
while a picker is up "pushed the player's own hand clean off the bottom of the
screen." Two pickers up at once reproduces that overflow.

### Reproduction (run, not inferred)

`headless/picker_panel_leak_probe.gd` drives the real handlers:

```
pickers open after _show_trump_panel     [trump_panel]
waiting_for_trump                        True
  → _restart_game_with_settings(...)     (exactly what Settings' Play calls)
pickers open in the NEW hand             [trump_panel]      ← leaked
trump_panel.visible after restart        True
waiting_for_trump after restart          True
pickers open once exchange opens         [trump_panel, nello_exchange_panel]
```

The state leak is unconditional. The *visible* symptom is viewport-dependent —
sweeping window heights with and without the leak:

| window_h | visible_h | trump leaked | tile row bottom | off-screen |
|---|---|---|---|---|
| 520 | 832 | **yes** | 897 | **YES** |
| 520 | 832 | no | 696 | no |
| 600 | 959 | yes | 897 | no |
| 680+ | 1088+ | either | fits | no |

So the leak always happens; it only becomes *visible* on a short window, which is
why it reproduced on his device and not on Katy's. This resolves the "I can't
reproduce it" half of the report — it is not device-specific behaviour, it is a
device-specific *consequence* of a universal state bug.

### Where the original diagnosis needed correcting

Substance was right; three details were stale or slightly off, none load-bearing:

* Line numbers were from an older copy (it cited 883–885 / 906–908 / 981–983 /
  1016–1018 for panel construction; actual is 1029–1193).
* It claimed `trump_panel` is cleared in exactly one place and `waiting_for_trump`
  set false in exactly one place. Both now have two, because the bid-revisit
  feature added a second. The conclusion is unaffected — neither is a reset.
* There is **no** `waiting_for_nello_exchange` flag. Only three exist (393–395),
  so "reset the `waiting_for_*` flags" means three, not four.

The proposed fix location is correct and I am adopting it.

---

## 2. Scope

`_start_hand()` is the sole chokepoint: it is the only entry to a fresh hand, and
every route reaches it — initial deal (1845), the post-hand path (2418),
`_restart_game_with_settings()` (4122) and `_on_hand_continue()` (4970). Closing
the pickers there covers gear→Play, the end-of-hand New Game button, Next Hand,
and the main menu, with one edit.

Explicitly **not** in scope: gating the gear button on `waiting_for_*`. Blocking
Settings mid-bid would be a worse experience than the bug, the "The game in
progress will be lost" confirmation (3949–3953) already covers intent, and the
reset path is the correct layer.

---

## 3. Implementation

### 3.1 Required — one owner for "close every picker"

Two list literals of the four panels already exist (1225, 3298). Adding a third
invites drift, so the helper lives next to `_play_area_reserves_height()` and owns
the list.

**Deviation from the first draft.** That draft had one `_close_all_pickers()` that
cleared all three `waiting_for_*` flags wholesale, and §3.2 would have called it
from every `_show_*_panel()`. That combination is broken: `_show_bid_panel()` has
five callers, and three of them (2094, 2207, 2228) are the panel **redrawing
itself** when the player taps "More" or a contract type. Those callers do not set
`waiting_for_bid` first, because it is already true. A wholesale clear at the top
of `_show_bid_panel()` would therefore end the human's bid turn on every redraw.

So the primitive is parameterised by the panel being kept, and clears each flag
only alongside the panel it belongs to:

```gdscript
func _close_pickers_except(keep: Control) -> void:
	if is_instance_valid(bid_panel) and bid_panel != keep:
		bid_panel.visible = false
		waiting_for_bid = false
	if is_instance_valid(trump_panel) and trump_panel != keep:
		trump_panel.visible = false
		waiting_for_trump = false
	if is_instance_valid(nello_panel) and nello_panel != keep:
		nello_panel.visible = false
		waiting_for_nello_mode = false
	# The exchange has no waiting_for_* flag; visibility is the whole of its state.
	if is_instance_valid(nello_exchange_panel) and nello_exchange_panel != keep:
		nello_exchange_panel.visible = false

func _close_all_pickers() -> void:
	_close_pickers_except(null)
```

`_close_all_pickers()` is called at the **top** of `_start_hand()`, so a fresh hand
can never inherit a picker. It must precede `_start_bidding()`, which legitimately
re-opens `bid_panel`.

Panels are already `visible = false` at build time (1030, 1053, 1149, 1192), and
Godot only emits `visibility_changed` on an actual change, so the existing
`_refresh_play_area_reservation` hook (1226) is not spuriously fired.

### 3.2 Recommended — make exclusivity an invariant, not a convention

3.1 closes the one reachable hole. It does not stop a *future* flow from
abandoning a picker somewhere other than a hand boundary. Since the four
decisions are strictly sequential — `_on_nello_mode_selected()` (2606) closes
`nello_panel` before `_start_nello_exchange()` opens the exchange, and every other
transition follows the same shape — "at most one picker is open" is a real
invariant and can be enforced at the open sites:

`_show_bid_panel()`, `_show_trump_panel()`, `_show_nello_panel()` and
`_show_nello_exchange_panel()` each open with `_close_pickers_except(<own panel>)`.
Verified safe against the one flow that already hand-rolls this:
`_open_bid_revisit()` (2322–2323) closes trump/nello then calls
`_show_bid_panel()`, and `_on_revisit_cancelled()` reopens via
`_show_nello_panel()`/`_show_trump_panel()` after `_close_bid_revisit()` has
cleared `bid_panel` — both become redundant rather than wrong.

Note this cannot replace 3.1: closing others on open only helps when something
opens next. A hand abandoned at Call Trump and restarted into a hand the human
loses opens no picker at all, and the stale panel would sit there for the whole
hand. Ship 3.1 regardless; 3.2 is defence in depth.

---

## 4. Verification

Promote the probe to a regression suite, `headless/picker_panel_reset_verify.gd`,
following `Headless_Harness_Reference.md` (snapshot/restore `user://`, results to
JSON, `quit()` carries the exit code, expect the benign ObjectDB leak line).

Required checks:

1. `_show_trump_panel()` → `_restart_game_with_settings(game.settings)` → no
   picker is visible and all three `waiting_for_*` are false. *(fails pre-fix)*
2. Same for a leak started from `_show_bid_panel()` and from
   `_show_nello_panel()` — the hole is not Nello-specific.
3. `_on_hand_continue()` path gets the same reset.
4. Regression: a normal hand still opens `bid_panel` after `_start_hand()`, so
   the reset does not fight `_start_bidding()`.
5. Regression: the bid-revisit flow still works — `_open_bid_revisit()` then
   `_on_revisit_cancelled()` returns to the screen it came from.
6. With 3.2 implemented: opening any picker leaves exactly one visible.

Confirm the suite **fails against the pre-fix code** before accepting it — a reset
test that passes either way proves nothing.

### Result

`headless/picker_panel_reset_verify.gd`: **29 checks, 0 failures.** Against the
pre-fix code (fix stashed, file restored byte-for-byte afterwards) the leak checks
fail as required, and show the panels piling up across successive restarts:

```
FAIL  trump via Settings->Play: does not survive the restart   open=["trump"]
FAIL  nello via Settings->Play: does not survive the restart   open=["trump","nello"]
FAIL  exchange via Settings->Play: does not survive           open=["trump","nello","exchange"]
FAIL  trump via Next Hand: does not survive the restart       open=["trump","nello","exchange"]
```

That three-panel stack is the reported photo. Note the pre-fix run stops at 18 of
29 checks: the later sections call `_close_all_pickers()`, which does not exist
pre-fix, so `_run()` aborts there. The discriminating checks all execute first.

One caveat worth keeping: every check runs in a **single frame**, deliberately.
Panel visibility is synchronous, but `_run_bidding_sequence()` parks on real-time
timers, so letting frames elapse would let an AI bid land mid-suite and open a
picker for legitimate reasons. Leak checks also never assert on `bid_panel`, since
a restart may legitimately reopen it when the human bids first.

Also re-run green after the change: `drag_ghost_cancel_verify`,
`laydown_ends_hand_verify`, `menu_merge_verify`.

---

## 5. Files touched

* `game_table.gd` — add `_close_all_pickers()`, call from `_start_hand()`; 3.2
  edits the four `_show_*_panel()` functions.
* `headless/picker_panel_reset_verify.gd` — new.
* `headless/picker_panel_leak_probe.gd` — the diagnostic that produced §1; keep.
