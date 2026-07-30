extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# jump_bids_trace.gd
#
# Traces what settings.allow_jump_bids / settings.max_open_bid_marks
# actually do at runtime, versus what they are written to do.
#
# Intended rule (Katy, July 30 2026):
#   * jump bids ON  — any player may bid as high as they like at any
#     point, including opening at 4 marks.
#   * jump bids OFF — an opening marks bid is capped at
#     max_open_bid_marks (normally 2), and a raise may only go one
#     mark above the current marks bid.
#   * Special contracts with their own minimums are exempt: Plunge
#     sits at plunge_minimum_bid_marks, Splash at splash_bid_marks.
#
# Diagnostic only — reports and asserts nothing. Section C starts a real
# game to inspect the bid panel, which writes last_used.json, so the file
# is snapshotted and restored (gotcha #9). Writes
# headless/jump_bids_trace_results.json.
#
# Run:
#   "$GODOT" --headless --path . --script res://headless/jump_bids_trace.gd
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")

const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://display_prefs.json",
	"user://preset_overrides/standard.json",
]
var _snapshot: Dictionary = {}

var _log: Array = []
var _findings: Array = []
var _table: Node = null
var _frame := 0

func _snapshot_user_files() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore_user_files() -> void:
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	_note("user:// restored")

func _note(s: String) -> void:
	_log.append(s)
	print(s)

func _finding(id: String, summary: String, evidence: String) -> void:
	_findings.append({"id": id, "summary": summary, "evidence": evidence})

func _settings(jump: bool) -> GameSettings:
	var s = GameSettingsScript.standard_42()
	s.allow_jump_bids = jump
	s.max_open_bid_marks = 2
	s.allow_plunge = true
	s.plunge_minimum_bid_marks = 4
	s.plunge_minimum_doubles = 4
	s.allow_splash = true
	s.splash_bid_marks = 2
	s.splash_minimum_doubles = 3
	return s

func _marks(v: int) -> Bid:
	return BidScript.new(BidScript.Type.MARKS, v, 0)

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false

	_snapshot_user_files()
	_section_a_rule_layer()
	_section_b_live_path()
	_section_c_human_ui()
	_section_d_ai()
	_restore_user_files()

	var f = FileAccess.open("res://headless/jump_bids_trace_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"findings": _findings, "log": _log}, "\t"))
		f.close()
	_note("\nResults written to res://headless/jump_bids_trace_results.json")
	quit(0)
	return true

# ── A. Does the rule layer itself implement the rule? ────────────────
func _section_a_rule_layer() -> void:
	_note("\n═══ A. Bid.is_valid() — the rule layer ═══")
	for jump in [false, true]:
		var s = _settings(jump)
		var opening: Array = []
		for v in range(1, 8):
			if BidScript.is_valid(_marks(v), null, s):
				opening.append(v)
		_note("  jump=%s  legal OPENING marks: %s" % [jump, opening])

		var over_one: Array = []
		for v in range(2, 8):
			if BidScript.is_valid(_marks(v), _marks(1), s):
				over_one.append(v)
		_note("  jump=%s  legal raises over 1 mark: %s" % [jump, over_one])

		var over_two: Array = []
		for v in range(3, 8):
			if BidScript.is_valid(_marks(v), _marks(2), s):
				over_two.append(v)
		_note("  jump=%s  legal raises over 2 marks: %s" % [jump, over_two])

		# A marks bid arriving over a POINTS bid is the first marks bid of the
		# auction, so the opening cap ought to apply to it.
		var pts = BidScript.new(BidScript.Type.POINTS, 35, 1)
		var over_points: Array = []
		for v in range(1, 8):
			if BidScript.is_valid(_marks(v), pts, s):
				over_points.append(v)
		_note("  jump=%s  legal marks over a 35-point bid: %s" % [jump, over_points])
		if not jump and over_points.size() > 2:
			_finding("A1",
				"Bid.is_valid() applies the opening cap only when current_high is null, "
				+ "so the first marks bid over a POINTS bid escapes it.",
				"jump=false, high=35 points: legal marks %s, expected [1, 2]" % [over_points])

		# Special contracts must keep their own minimums regardless.
		var ctx := {"hand_doubles_count": 4}
		var plunge_ok = BidScript.is_valid(BidScript.new(BidScript.Type.PLUNGE, 4, 0), _marks(1), s, ctx)
		var splash_ok = BidScript.is_valid(BidScript.new(BidScript.Type.SPLASH, 2, 0), null, s, ctx)
		_note("  jump=%s  Plunge 4 over 1 mark: %s   Splash 2 opening: %s"
			% [jump, plunge_ok, splash_ok])

# ── B. Is the rule layer on the live path at all? ────────────────────
func _section_b_live_path() -> void:
	_note("\n═══ B. Does the live game route through it? ═══")
	var s = _settings(false)
	var g = Game.new(s)
	g.setup_players(0)
	g.deal_hands()

	# The validating entry point.
	var accepted_via_submit = g.submit_bid(_marks(7), 0)
	_note("  game.submit_bid(7 marks, jump=false) -> %s   current_bid=%s"
		% [accepted_via_submit, "null" if g.current_bid == null else g.current_bid.debug_string()])

	# What game_table.gd actually does at its four bid sites.
	var g2 = Game.new(_settings(false))
	g2.setup_players(0)
	g2.deal_hands()
	g2.current_bid = _marks(7)
	_note("  direct assignment (what game_table.gd does) -> current_bid=%s"
		% g2.current_bid.debug_string())

	if not accepted_via_submit and g2.current_bid != null:
		_finding("B1",
			"submit_bid() correctly rejects an illegal bid, but game_table.gd never "
			+ "calls it — all four bid sites assign game.current_bid directly, so "
			+ "Bid.is_valid() never runs during a real auction.",
			"submit_bid(7 marks)=false, yet direct assignment yields %s"
				% g2.current_bid.debug_string())

# ── C. What does the human's bid panel actually offer? ───────────────
func _section_c_human_ui() -> void:
	_note("\n═══ C. Human bid panel — the marks drum ═══")
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("standard")
	if t.game == null:
		_note("  (could not start a game; skipping)")
		return
	t.game.settings.allow_jump_bids = false
	t.game.settings.max_open_bid_marks = 2
	t._human_bid_position = 1
	t._bid_panel_expanded = false

	# Opening: nothing bid yet.
	t.game.current_bid = null
	t._show_bid_panel()
	var opening: Array = [] if t._marks_picker == null else Array(t._marks_picker.values)
	_note("  jump=false, opening      -> drum offers %s   (rule: [1, 2])" % [opening])

	# Raising over a 2-mark bid.
	t.game.current_bid = _marks(2)
	t._show_bid_panel()
	var over_two: Array = [] if t._marks_picker == null else Array(t._marks_picker.values)
	_note("  jump=false, over 2 marks -> drum offers %s   (rule: [3])" % [over_two])

	if opening.size() > 2 or over_two.size() > 1:
		_finding("C1",
			"The marks drum is built as range(marks_floor, 8) with no ceiling, so it "
			+ "offers every value up to 7 regardless of allow_jump_bids or "
			+ "max_open_bid_marks. Nothing rejects the bid afterwards either (see B1), "
			+ "so the human can simply pick an illegal bid and it stands.",
			"opening offered %s (expected [1, 2]); over 2 marks offered %s (expected [3])"
				% [opening, over_two])

	# Special-contract floors, tested through _contract_floor() directly rather
	# than through the panel: the panel silently reverts to MARKS when the hand
	# isn't eligible for the contract, which makes a panel-based reading of this
	# depend on the deal and prove nothing.
	t.game.current_bid = null
	var pf_open: int = t._contract_floor(BidScript.Type.PLUNGE, 1)
	var pf_over3: int = t._contract_floor(BidScript.Type.PLUNGE, 4)
	var sf_open: int = t._contract_floor(BidScript.Type.SPLASH, 1)
	_note("  _contract_floor Plunge (opening)      -> %d   (plunge_minimum_bid_marks=%d)"
		% [pf_open, t.game.settings.plunge_minimum_bid_marks])
	_note("  _contract_floor Plunge (auction at 4) -> %d   (must not drop below the auction)" % pf_over3)
	_note("  _contract_floor Splash (opening)      -> %d   (splash_bid_marks=%d)"
		% [sf_open, t.game.settings.splash_bid_marks])
	if pf_open == t.game.settings.plunge_minimum_bid_marks and sf_open == t.game.settings.splash_bid_marks:
		_note("  -> special-contract floors are already correct; they need no change.")

# ── D. Can the AI produce or answer a jump bid? ──────────────────────
func _section_d_ai() -> void:
	_note("\n═══ D. AI marks bidding ═══")
	var highest_seen := 0
	var marks_bids := 0
	var raises_over_marks := 0
	for i in range(400):
		var g = Game.new(_settings(true))   # jump bids ALLOWED
		g.setup_players(0)
		g.deal_hands()
		var decisions: Array = []
		var b = AIPlayer.decide_bid(g.players[1].hand, 1, null, g.settings, false,
			"expert", decisions, 0, 0)
		if b != null and b.type == BidScript.Type.MARKS:
			marks_bids += 1
			highest_seen = max(highest_seen, b.value)
		# And when a marks bid is already standing, will it ever raise?
		var b2 = AIPlayer.decide_bid(g.players[2].hand, 2, _marks(2), g.settings, false,
			"expert", decisions, 0, 0)
		if b2 != null and b2.type == BidScript.Type.MARKS:
			raises_over_marks += 1
	_note("  400 deals, jump bids ALLOWED:")
	_note("    opening marks bids issued: %d   highest value seen: %d" % [marks_bids, highest_seen])
	_note("    marks bids issued over a standing 2-mark bid: %d" % raises_over_marks)
	if highest_seen <= 1:
		_finding("D1",
			"AIPlayer.decide_bid() only ever constructs MARKS bids at a hardcoded value "
			+ "of 1 (ai_player.gd's sole BidScript.Type.MARKS construction). It can "
			+ "therefore never open high when jump bids are enabled, and never raises a "
			+ "standing marks bid at all — enabling the setting changes no AI behaviour.",
			"400 deals: highest AI marks bid = %d; raises over a 2-mark bid = %d"
				% [highest_seen, raises_over_marks])
