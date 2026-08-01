extends SceneTree

# Verification for reopening a won bid before the contract is finalised.
#
# Real 42 lets the auction winner change their mind before play starts — win at
# 32 and decide you would rather play Nello. The old flow made you commit to
# Nello before you knew you had won.
#
# The thing this has to prove is that it is NOT a second bidding system. The
# panel reopens against the auction as it stood immediately BEFORE the player's
# own bid, so Bid.is_valid() runs unmodified and every floor and ceiling it
# consults is the one that applied when they bid. Two cases make or break that:
#
#   * re-selecting the same value must be legal. Validated against their own
#     bid it would not be — is_higher() is strictly greater.
#   * a 3-mark winner must still be able to keep 3. Validated against null it
#     would be refused for exceeding max_open_bid_marks.
#
# On top of that sits exactly one new rule: not below what you already won.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10) — this
# starts a real game. Judge the exit code and the results JSON.

const BidScript = preload("res://bid.gd")

const TOUCHED_PATHS := ["user://last_used.json", "user://display_prefs.json"]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _eq(name: String, got, want) -> void:
	_check(name, got == want, "got %s, want %s" % [got, want])

func _snapshot_user_files() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore_user_files() -> void:
	var ok := true
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			if FileAccess.file_exists(p): ok = false
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	_check("user:// save data restored", ok)

func _points(v: int, pid: int) -> Bid:
	return BidScript.new(BidScript.Type.POINTS, v, pid)

func _marks(v: int, pid: int) -> Bid:
	return BidScript.new(BidScript.Type.MARKS, v, pid)

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_table.main_menu_panel.visible = false
		_table._on_preset_chosen("standard")
		return false
	if _frame == 8:
		_table.bid_panel.visible = false
		_test_who_may_revisit()
		_test_points_floor()
		_test_marks_ceiling_and_floor()
		_test_cancel_is_inert()
		_test_switch_to_nello()
		_test_record_untouched()
		return false
	if _frame < 12:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/bid_revisit_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

# Puts the table in "you won the auction with `won`, after `before` was
# standing" and opens the trump screen, the way _finish_bidding() would.
func _win_with(won: Bid, before) -> void:
	var t = _table
	t._revisiting = false
	t._revisit_won_bid = null
	t.game.current_bid = won
	t._bid_before_human = before
	t._human_bid_position = 1
	t.game.trump = -1
	t.nello_panel.visible = false
	t._show_trump_panel()

func _drum_points() -> Array:
	return [] if _table._pts_picker == null else Array(_table._pts_picker.values)

func _drum_marks() -> Array:
	return [] if _table._marks_picker == null else Array(_table._marks_picker.values)

# ── Who is allowed to reopen it ──────────────────────────────────────
func _test_who_may_revisit() -> void:
	var t = _table
	_win_with(_points(32, t.human_seat), null)
	_check("winner sees Change Bid on the trump screen", t._trump_back_btn.visible)

	# Plunge and Splash hand the trump call to the winner's PARTNER. That seat is
	# calling trump on a contract it did not bid and must not be able to rewrite it.
	t.game.current_bid = BidScript.new(BidScript.Type.PLUNGE, 4, (t.human_seat + 1) % 4)
	t._show_trump_panel()
	_check("the bid winner's partner does not see Change Bid",
		not t._trump_back_btn.visible)
	_check("and _can_revisit_bid() agrees", not t._can_revisit_bid())

# ── Points: equal allowed, lower refused ─────────────────────────────
func _test_points_floor() -> void:
	var t = _table
	# Won at 32 over a standing 31.
	_win_with(_points(32, t.human_seat), _points(31, 1))
	t._open_bid_revisit("trump")

	_check("revisit opens the bid panel", t.bid_panel.visible and t._revisiting)
	_eq("trump screen closed behind it", t.trump_panel.visible, false)
	_eq("drum floors at the bid you won with, not one above",
		_drum_points(), range(32, 43))
	_eq("drum opens ON your own bid rather than making you find it",
		t._pts_picker.get_value(), 32)

	# Re-selecting the same value is the case a naive implementation gets wrong:
	# validated against your own bid, is_higher() refuses it.
	t._on_revisit_submitted(_points(32, t.human_seat))
	_check("re-selecting the bid you won with is accepted",
		t.game.current_bid != null and t.game.current_bid.value == 32
			and not t._revisiting,
		"bid=%s revisiting=%s" % [t.game.current_bid.debug_string(), t._revisiting])

	# Lower must be refused even if something contrives to submit it.
	_win_with(_points(32, t.human_seat), _points(31, 1))
	t._open_bid_revisit("trump")
	t._on_revisit_submitted(_points(31, t.human_seat))
	_eq("a lower points bid does not stand", t.game.current_bid.value, 32)
	_check("and the panel stays open", t.bid_panel.visible and t._revisiting)

	# Raising is fine.
	t._on_revisit_submitted(_points(35, t.human_seat))
	_eq("raising is accepted", t.game.current_bid.value, 35)

	# Passing on a bid you already won is meaningless — the slot says Cancel.
	_win_with(_points(32, t.human_seat), null)
	t._open_bid_revisit("trump")
	t._on_revisit_submitted(BidScript.new(BidScript.Type.PASS, 0, t.human_seat))
	_eq("you cannot pass on a bid you have already won",
		t.game.current_bid.value, 32)
	_check("panel still open after a refused pass", t._revisiting)
	t._on_revisit_cancelled()

# ── Marks: the ceiling has to come from the pre-bid auction ──────────
func _test_marks_ceiling_and_floor() -> void:
	var t = _table
	t.game.settings.allow_jump_bids = false
	t.game.settings.max_open_bid_marks = 2

	# Won at 3 marks over a standing 2. Validated against null this would be
	# refused for exceeding the opening cap of 2 — the pre-bid state is what
	# makes keeping 3 legal.
	_win_with(_marks(3, t.human_seat), _marks(2, 1))
	t._open_bid_revisit("trump")
	# [3] and not [3, 4]: reopening puts the player back in the position they bid
	# from, and with jump bids off the one-step rule capped them at one mark over
	# the standing 2. So a marks winner on this ruleset can keep their bid or
	# change contract type, but cannot step up another mark — the same ceiling
	# they faced the first time. Consequence of validating against the pre-bid
	# auction rather than against their own bid, and the reason keeping 3 is
	# legal at all.
	_eq("3-mark winner keeps 3, held to the ceiling they originally faced",
		_drum_marks(), [3])
	_eq("marks drum opens on the bid you won with",
		t._marks_picker.get_value(), 3)
	_check("no points option once you are at marks", t._pts_picker == null,
		"points drum offered %s" % [_drum_points()])

	t._on_revisit_submitted(_marks(3, t.human_seat))
	_check("re-selecting 3 marks is accepted",
		t.game.current_bid.type == BidScript.Type.MARKS
			and t.game.current_bid.value == 3 and not t._revisiting,
		"bid=%s" % t.game.current_bid.debug_string())

	# Dropping to 2 must be refused.
	_win_with(_marks(3, t.human_seat), _marks(2, 1))
	t._open_bid_revisit("trump")
	t._on_revisit_submitted(_marks(2, t.human_seat))
	_eq("dropping a mark does not stand", t.game.current_bid.value, 3)
	t._on_revisit_cancelled()

	# A points winner opening the marks drum still takes the OPENING cap, because
	# that is the situation they were in: a points bid is worth under one mark.
	_win_with(_points(32, t.human_seat), null)
	t._open_bid_revisit("trump")
	_eq("points winner switching to marks takes the opening cap",
		_drum_marks(), [1, 2])
	t._on_revisit_cancelled()

	# With jump bids on there is no one-step rule, so the same 3-mark winner can
	# climb — the contrast that shows the ceiling is the ruleset's and not
	# something the revisit invented.
	t.game.settings.allow_jump_bids = true
	_win_with(_marks(3, t.human_seat), _marks(2, 1))
	t._open_bid_revisit("trump")
	_eq("with jump bids on, a 3-mark winner may climb to 7",
		_drum_marks(), [3, 4, 5, 6, 7])
	t._on_revisit_submitted(_marks(6, t.human_seat))
	_eq("and the climb is accepted", t.game.current_bid.value, 6)
	t.game.settings.allow_jump_bids = false

# ── Cancel changes nothing ───────────────────────────────────────────
func _test_cancel_is_inert() -> void:
	var t = _table
	_win_with(_points(34, t.human_seat), _points(33, 1))
	var before = t.game.current_bid
	t._open_bid_revisit("trump")
	t._on_revisit_cancelled()
	_check("Cancel leaves the winning bid exactly as it was",
		t.game.current_bid == before and t.game.current_bid.value == 34,
		"bid=%s" % t.game.current_bid.debug_string())
	_eq("Cancel puts the trump screen back", t.trump_panel.visible, true)
	_eq("and closes the bid panel", t.bid_panel.visible, false)
	_check("revisit state is cleared", not t._revisiting and t._revisit_won_bid == null)

	# Cancelling from the Nello screen returns there, not to the trump screen.
	t.game.current_bid = BidScript.new(BidScript.Type.NELLO, 1, t.human_seat)
	t._bid_before_human = null
	t.trump_panel.visible = false
	t._show_nello_panel()
	_check("Nello screen offers Change Bid too", t._nello_back_btn.visible)
	t._open_bid_revisit("nello")
	_eq("Nello screen closed behind it", t.nello_panel.visible, false)
	t._on_revisit_cancelled()
	_eq("Cancel returns to the Nello screen", t.nello_panel.visible, true)
	_eq("not to the trump screen", t.trump_panel.visible, false)
	t.nello_panel.visible = false

# ── The scenario that motivated the whole thing ──────────────────────
func _test_switch_to_nello() -> void:
	var t = _table
	t.game.settings.allow_nello = true
	t.game.settings.nello_only_on_forced_bid = false
	_win_with(_points(32, t.human_seat), null)
	t._open_bid_revisit("trump")

	# Nello is worth a full mark, so it clears a 32-point floor comfortably.
	var nello = BidScript.new(BidScript.Type.NELLO, 1, t.human_seat)
	_check("Nello outranks a 32-point bid",
		BidScript.to_mark_equivalent(nello) >= BidScript.to_mark_equivalent(_points(32, 0)))
	t._on_revisit_submitted(nello)
	_eq("switching a won 32 to Nello is accepted",
		t.game.current_bid.type, BidScript.Type.NELLO)
	_check("revisit closed", not t._revisiting)

	# And the ruleset's own gate still applies — the revisit is not a back door.
	# tournament_rules() sets nello_only_on_forced_bid, where a normal win means
	# the others did not all pass and Nello is therefore not on offer.
	t.game.settings.nello_only_on_forced_bid = true
	_win_with(_points(32, t.human_seat), _points(31, 1))
	t._open_bid_revisit("trump")
	var ctx = t.game.bid_context_against(t.human_seat, 1, t._bid_before_human)
	_check("nello_only_on_forced_bid still blocks Nello on a normal win",
		not BidScript.is_valid(nello, t._bid_before_human, t.game.settings, ctx))
	t._on_revisit_submitted(nello)
	_eq("and the illegal switch does not stand",
		t.game.current_bid.type, BidScript.Type.POINTS)
	t._on_revisit_cancelled()
	t.game.settings.nello_only_on_forced_bid = false

# ── The auction record stays truthful ────────────────────────────────
func _test_record_untouched() -> void:
	var t = _table
	t.game.bid_decisions.clear()
	t.game.bid_decisions.append({
		"player_id": t.human_seat, "source": "human",
		"bid_type": BidScript.Type.POINTS, "bid_value": 32,
	})
	t.game.bid_decisions.append({
		"player_id": 1, "source": "ai",
		"bid_type": BidScript.Type.PASS, "bid_value": 0,
	})
	var before_size: int = t.game.bid_decisions.size()

	_win_with(_points(32, t.human_seat), null)
	t._open_bid_revisit("trump")
	t._on_revisit_submitted(_points(38, t.human_seat))

	_eq("no bid event is added for the change",
		t.game.bid_decisions.size(), before_size)
	_eq("and the original auction entry is left alone",
		t.game.bid_decisions[0]["bid_value"], 32)

	# The contract that gets played rides on winning_bid, which reads
	# current_bid — so it is already correct with no bookkeeping at all.
	var rec: Dictionary = t.game.build_hand_record()
	_eq("the hand record's winning_bid is the revised contract",
		rec["winning_bid"]["value"], 38)
	_eq("while its bid_decisions still show the auction as it happened",
		rec["bid_decisions"][0]["bid_value"], 32)
