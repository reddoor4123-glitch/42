# Ruleset Slots & Persistence

### Purpose of this doc
The five-questions answer sheet for the ruleset/settings system: what slots
exist, where each kind of saved state lives, and which function decides what.
Written July 30, 2026, after the Menu/Rules/Settings merge, because the answers
genuinely span two scripts and five files — everything else about this system is
documented at its definition site instead.

**This doc points; it does not restate.** Anything describing *how* a rule
behaves belongs in a comment next to the code. If you find yourself about to
copy a list of field names or a branch condition in here, don't — link the
function and let the code stay the single source of truth. That's how
`Texas_42_Documentation_Map.md` describes the other docs in this project going
stale, and this one is a prime candidate.

---

## 1. What slots exist?

Five, fixed. `game_table.gd`'s `SLOT_KEYS`.

| Key | Ships with rules? | Renameable? | Reset to Default? |
|---|---|---|---|
| `teel` | yes (`GameSettings.teel_rules()`) | yes | yes |
| `standard` | yes (`standard_42()`) | yes | yes |
| `tournament` | yes (`tournament_rules()`) | yes | yes |
| `lechner` | yes (`lechner_hall()`) | yes | yes |
| `custom:Custom` | no — seeded from Standard 42 once | yes | no |

The first four are also `BUILTIN_PRESET_KEYS`, which is what gates the Reset
button. GDScript won't let one const be derived from the other (no array
concatenation in a const expression), so `scripts/menu_merge_verify.gd` asserts
`SLOT_KEYS == BUILTIN_PRESET_KEYS + [CUSTOM_SLOT_KEY]` instead. If you add a
slot, that test tells you which companion dictionaries you forgot.

**Why Custom's key is `"custom:Custom"` and not `"custom"`.** The pre-merge code
supported an arbitrary list of user rulesets keyed `"custom:<name>"`, and told
them apart from built-ins with `key.begins_with("custom:")`. Keeping that prefix
means the one remaining custom slot reuses that existing branch and the existing
`custom_rulesets/` directory, rather than introducing a third storage location —
and it stays out of `BUILTIN_PRESET_KEYS` for free, which is exactly the
behavior Reset needs.

---

## 2. What persistence files exist, and who owns what?

Five files, one concern each. The authoritative list is the **PERSISTENCE
LAYOUT** const block at the top of `game_table.gd`; nothing outside it should
hardcode a path.

| File | Owns | Must NOT contain |
|---|---|---|
| `last_used.json` | session + player state: `last_preset`, `ai_difficulty`, Profiles' `seat_assignments` | rules, presentation |
| `slot_names.json` | presentation: slot key → display name | rules, anything functional |
| `display_prefs.json` | visual preferences: currently `domino_back` | rules, player state |
| `preset_overrides/<key>.json` | rule content for a built-in slot | difficulty, names, identity |
| `custom_rulesets/<name>.json` | rule content for a custom slot | same |

Two consequences worth knowing before you touch any of it:

- **`last_used.json` is shared with Player Profiles.** Never delete or rewrite
  it wholesale — `seat_assignments` lives in there. Edit specific keys. A "reset
  my rules" feature that unlinks this file would silently un-name the AI
  opponents.
- **Its existence is not evidence of saved rules.** A player who names their
  opponents before ever choosing a ruleset has the file with no `last_preset`.
  `_last_used_preset_key()` is the correct "do we have saved rules?" test; it
  validates against `SLOT_KEYS`, which also retires any pre-merge
  `custom:<name>` key that no screen can reach any more.

---

## 3. Which settings are global vs. per-ruleset?

| Setting | Scope | Where it lives |
|---|---|---|
| Every rule field on `GameSettings` | per-slot | that slot's rules file |
| `ai_difficulty` | player-global; slot supplies a first-run **seed** only | `last_used.json` |
| Domino back | table-global | `display_prefs.json` |
| Slot display name | per-slot, presentation | `slot_names.json` |
| `preset_id` | runtime identity, never serialized | stamped by the resolver |

`ai_difficulty` is the one that reads oddly. It's declared on `GameSettings` and
each preset function sets it, but `to_dict()` doesn't write it and `from_dict()`
doesn't read it — the value on a preset is a **seed**, not stored rule content.
See §5.

The domino back used to be inferred from `preset_id == "teel"`, which meant
switching rulesets silently changed the tile art and most combinations were
unreachable. It's a stored preference now.

---

## 4. How is a slot resolved into settings?

One function: `game_table.gd`'s `_resolve_settings_for_slot(key)`. Every entry
point goes through it — the Settings slot buttons, Choose Rules' instant-apply,
Play resuming a saved slot, and Reset to Default after it deletes the override.

It always returns a **new** object and always re-stamps `preset_id`. Both are
load-bearing:

- Building fresh is what stops one slot's tweaks bleeding into the next when you
  click along the slot buttons.
- Re-stamping is required because `to_dict()` deliberately omits `preset_id`
  (identity isn't content), so anything loaded from disk arrives with
  `preset_id == ""`. An unstamped object makes `_persist_preset_tweaks()` a
  no-op and hides the Reset button — which is why that function now
  `push_error()`s instead of returning quietly. `Game`'s constructor
  (`game.gd`) still falls back to a bare `GameSettings.new()` when handed no
  settings, so unstamped objects remain constructible; that's the path to watch.

Supporting single-source-of-truth helpers, all in `game_table.gd`:

| Helper | Sole owner of |
|---|---|
| `_slot_file_path(key)` | the built-in vs. custom storage split |
| `_ensure_slot_dir(key)` | creating a slot's directory before first write |
| `_hardcoded_defaults_for_slot(key)` | key → preset-function mapping |
| `_last_used_preset_key()` | "do we have resumable saved rules?" |
| `_last_used_difficulty()` | reading committed difficulty (normalized) |

### Where rename and reset are reachable from

| Action | Settings screen | Choose Rules |
|---|---|---|
| Rename | — | "…" → Rename |
| Reset | "Reset to Default" button | "…" → Reset |

Both screens raise the same `_show_reset_confirm_popup(key, parent, on_reset)`,
which does the file work and then calls back so each screen can refresh itself.
Reset appears only for `BUILTIN_PRESET_KEYS`, in both places — the Custom slot's
saved file is its default, so there's nothing to restore.

Two UI notes that cost real debugging time, in case they resurface:

- **These popups are not `ConfirmationDialog`s.** `AcceptDialog` positions its own
  `dialog_text` label and does not re-flow for children added via `add_child()`,
  so the reset confirmation's "Also reset the name" checkbox drew directly on top
  of the message. `_make_modal_popup()` builds the project's own themed shell
  instead.
- **The "…" drop-down is `set_as_top_level(true)`.** `preset_panel` is a
  `PanelContainer`, which would otherwise stretch the menu across the whole
  panel; top-level also makes it ignore the parent transform, so its `position`
  is plain global coordinates. The first attempt positioned it relative to a
  full-rect holder instead and landed 32px right and 40px low — a freshly-added
  child reports the panel's *outer* rect until layout runs, after which
  `PanelContainer` insets it by its content margins. The arithmetic was correct;
  the frame of reference moved a frame later.

---

## 5. Difficulty: why it lives where it does

Difficulty behaves like player state in every observable way — its own main-menu
screen, commits the instant it's clicked (unlike every other settings field,
which waits for Play), stored in `last_used.json`, and survives rule changes.
Rulesets only supply a default.

So resolution is two steps, both in `_resolve_settings_for_slot()`:

1. the slot's shipped default is the **seed** (Teel/Standard → Casual,
   Tournament/Lechner → Expert), which is what a player who has never chosen
   gets, even when a saved override exists for that slot;
2. an explicit choice **overrides** it — otherwise setting Expert and then
   tapping a Casual-defaulting slot would silently downgrade the opponents.

`ai_difficulty` remains a field on `GameSettings` because that's what threads it
to `AIPlayer.decide_bid()`/`decide_play()` and what the preset functions use to
express their seed. It is not part of a ruleset's serialized content. If it ever
grows companions (per-seat difficulty, handicaps), the honest move is a separate
`PlayerPrefs`-shaped object and `GameSettings` losing the field — nothing
depends on it living there today beyond convenience.

### Two tiers, not three

`AIPlayer.AI_MODES` is `casual`/`expert`. `casual` is the former `beginner`,
numbers unchanged; the middle tier `standard` was retired July 29, 2026.

Migration is deliberately two independent mechanisms, because one wasn't enough:

- `GameSettings.normalize_difficulty()` maps `"standard"` → `"expert"` and is
  applied at each site that reads a *persisted* difficulty. Note that
  `last_used.json` is not a serialized `GameSettings`, so `from_dict()` never
  sees it — that file's reads normalize explicitly.
- `AI_MODES.get(difficulty, AI_MODES["expert"])` catches anything unnormalized.
  This second half is not belt-and-braces: GDScript evaluates default arguments
  **eagerly on every call**, so a `AI_MODES["standard"]` subscript throws the
  moment the key is gone, regardless of what `difficulty` holds. Removing a tier
  is a crash risk, not just a stale-data risk.

---

## Tests

| Script | Covers |
|---|---|
| `scripts/menu_merge_verify.gd` | Assertion suite: normalization, `AI_MODES` shape, slot isolation and re-stamping, file ownership, name independence, routing, plus a 12-cycle UI leak check. Exits non-zero on failure. |
| `scripts/menu_merge_ui_probe.gd` | Smoke-drives every screen including the "…" menu and the reset popup's real layout; treat non-empty stderr as failure. |
| `scripts/node_leak_probe.gd` | Per-class node census across rebuild cycles, for when a leak number needs attributing. |
| `scripts/menu_merge_screenshot.gd` | Renders the reset popup and both "…" menu variants to PNGs. Must run **without** `--headless`. |

Two of these need frame-boundary discipline: anything asking "where is this
control" or "did that get freed" must wait a frame or two, because Godot lays
containers out and processes `queue_free()` at frame boundaries. Measured in the
same frame, the reset popup reports every row at y=0 (reading as overlapping) and
closed menus still count as open. See `Headless_Harness_Reference.md` gotchas
#7–#8.

All three snapshot and restore the `user://` paths they touch — see
`Headless_Harness_Reference.md` gotcha #9 for why that isn't optional.
