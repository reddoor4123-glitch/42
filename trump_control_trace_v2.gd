extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# trump_control_trace_v2.gd
#
# Follow-up to trump_control_trace.gd. That script's Scenario B gave P1
# four LOW DOUBLES (0:0, 1:1, 2:2, 3:3) as filler alongside its top-3
# trump. That was a hand-design artifact, not a neutral test: a double
# is unconditionally "safe" under _is_lead_safe_against_opponent()
# (ai_player.gd:1195-1209) whenever the opponent isn't already void in
# that suit — doubles rank highest (13) in their own suit by
# construction (domino.gd:59-60), so nothing can beat one while
# following suit. On trick 1, nobody is void in anything yet, so EVERY
# double a player holds passes for free. P1 leading 0:0 over its own
# top trump wasn't really "the AI chose a double over trump" — it was
# "the AI was handed a free pass and took it."
#
# This script removes that crutch and adds a second independent
# variable: difficulty. AI_MODES (ai_player.gd:25-44) shows
# beginner/standard have vigilance:"none", expert has vigilance:"full".
# The safe-lead check that ran before P1's trump lead is gated by
# `if mode["vigilance"] == "full" and public_knowledge != null:`
# (ai_player.gd ~970). At vigilance:"none" that whole check is skipped
# — meaning lower difficulties may go STRAIGHT to the trumps.size()>=3
# check, with no safe-lead preemption possible at all, regardless of
# hand. That's a testable, counterintuitive claim: "smarter" (expert)
# opponents may be LESS quick to call in trump than beginner/standard
# ones, purely because only expert opponents run the safe-lead check
# that can outrank it.
#
# Confirmed NOT a source of nondeterminism across difficulties: the
# opponent-leading block (ai_player.gd ~960-1022) never calls
# _should_evaluate_tactically()/randf() — that only appears in the
# FOLLOWING-as-opponent section further down (~1056, ~1071). Vigilance
# is a plain string compare, so all three difficulties are fully
# deterministic here.
#
# Four scenarios, same P1-holds-top-3-trump shape throughout, only
# P1's four filler tiles and/or difficulty changed:
#   B_original_expert   — original easy-double filler, expert   (reference rerun)
#   B_hardened_expert   — no-double filler, expert               (isolates the crutch)
#   B_hardened_standard — no-double filler, standard              (isolates vigilance)
#   B_hardened_beginner — no-double filler, beginner              (isolates vigilance)
#
# Conventions per Headless_Harness_Reference.md: is_partner computed
# explicitly per seat, turn order (current_player + 3) % 4,
# record_trick() passed current_trick.plays, results written to JSON.
#
# Run:
#   "$GODOT" --headless --path . --script res://trump_control_trace_v2.gd
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const TRUMP_SUIT := 6
const BID_VALUE := 30
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2
const AI_MODES := {
	"beginner": {"vigilance": "none"},
	"standard": {"vigilance": "none"},
	"expert":   {"vigilance": "full"},
}

var trace_lines: Array = []

func _log(s: String):
	trace_lines.append(s)
	print(s)

func _hand_from_pairs(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

func _validate_full_deck(all_hands: Array) -> void:
	var seen := {}
	var count := 0
	for hand in all_hands:
		for d in hand:
			var key = "%d:%d" % [d.left, d.right]
			if seen.has(key):
				push_error("DUPLICATE TILE IN HAND SETUP: %s" % key)
			seen[key] = true
			count += 1
	if count != 28:
		push_error("Hand setup does not total 28 tiles (got %d)" % count)

# ── Original Scenario B hands (kept for direct side-by-side rerun) ──
# P1 filler = 0:0, 1:1, 2:2, 3:3 — all doubles, all free passes on trick 1.
func _hands_original() -> Array:
	var p0 = _hand_from_pairs([[0,1],[0,2],[0,3],[0,4],[0,5],[1,2],[3,6]])
	var p1 = _hand_from_pairs([[0,0],[1,1],[2,2],[3,3],[4,6],[5,6],[6,6]])
	var p2 = _hand_from_pairs([[1,3],[1,4],[1,5],[2,3],[2,4],[2,5],[2,6]])
	var p3 = _hand_from_pairs([[3,4],[3,5],[4,4],[4,5],[5,5],[0,6],[1,6]])
	return [p0, p1, p2, p3]

# ── Hardened hands ────────────────────────────────────────────────
# P1 filler = 1:2, 1:4, 2:3, 3:5 — all non-doubles. None is the top
# remaining tile of its suit on trick 1 (the double of every suit
# P1's filler touches — 1:1, 2:2, 3:3, 4:4, 5:5 — is held by P2 or
# P3, not P1), so best_remaining_card_for_suit() can never equal
# P1's tile. Every candidate should fail _is_lead_safe_against_opponent()
# against a non-void opponent by construction. Verified by hand below
# via the diagnostic function, not just asserted in this comment.
func _hands_hardened() -> Array:
	var p0 = _hand_from_pairs([[0,0],[0,1],[0,2],[0,3],[0,4],[0,5],[3,6]])
	var p1 = _hand_from_pairs([[1,2],[1,4],[2,3],[3,5],[4,6],[5,6],[6,6]])
	var p2 = _hand_from_pairs([[1,1],[1,3],[1,5],[2,2],[2,4],[2,5],[2,6]])
	var p3 = _hand_from_pairs([[3,3],[3,4],[4,4],[4,5],[5,5],[0,6],[1,6]])
	return [p0, p1, p2, p3]

func _setup_game(hands: Array) -> Game:
	_validate_full_deck(hands)
	var game = Game.new()
	game.setup_players(0)
	for i in range(4):
		game.players[i].hand.clear()
		game.players[i].reset_round()
		for d in hands[i]:
			game.players[i].hand.append(d)
	game.team_points[0] = 0
	game.team_points[1] = 0
	game.tricks_played = 0
	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
	game.current_bid = bid
	game.apply_bid_result(TRUMP_SUIT)
	return game

# ── Diagnostics — mirrors _is_lead_safe_against_opponent() exactly,
# using only public PublicKnowledge methods (no private-func reliance).
func _compute_opponent_lead_diagnostics(legal: Array, trump: int, player_id: int, partner_id: int, mode: Dictionary, knowledge: PublicKnowledge) -> Dictionary:
	var opposing_team = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)
	var trumps = legal.filter(func(d): return d.is_trump(trump))
	var non_trump = legal.filter(func(d): return not d.is_trump(trump))

	var per_tile: Array = []
	for d in non_trump:
		var suit = d.get_suit(trump)
		var per_opponent: Array = []
		for opp in opposing_team:
			var opp_void_in_suit = knowledge.void_suits(opp).has(suit)
			var safe: bool
			if not opp_void_in_suit:
				if d.is_double():
					safe = true
				else:
					var best = knowledge.best_remaining_card_for_suit(suit)
					safe = best != null and best.debug_string() == d.debug_string()
			else:
				safe = knowledge.void_suits(opp).has(trump)
			per_opponent.append({"opponent": opp, "void_in_suit": opp_void_in_suit, "safe_against": safe})
		var fully_safe = per_opponent.all(func(x): return x["safe_against"])
		per_tile.append({"tile": d.debug_string(), "suit": suit, "is_double": d.is_double(), "fully_safe": fully_safe, "per_opponent": per_opponent})

	var vigilance_open = mode["vigilance"] == "full"
	var safe_candidates = per_tile.filter(func(x): return x["fully_safe"])

	# rank_safe / opposing_team_all_void_in_trump — mirrors
	# _compute_partner_diagnostics() in trump_control_trace.gd exactly, so
	# CONTROL_TRUMP's actual stopping condition is visible here too, not
	# just inferable from hand construction after the fact.
	var rank_safe = false
	var best_trump_candidate_str = "none"
	var top_remaining_str = "none"
	if trumps.size() > 0:
		var best_trump_candidate: Domino = trumps[0]
		for d in trumps:
			if d.get_rank(trump) > best_trump_candidate.get_rank(trump):
				best_trump_candidate = d
		best_trump_candidate_str = best_trump_candidate.debug_string()
		var top_remaining = knowledge.highest_remaining_trump()
		if top_remaining != null:
			top_remaining_str = top_remaining.debug_string()
			rank_safe = top_remaining.debug_string() == best_trump_candidate.debug_string()
	var opposing_team_all_void_in_trump = opposing_team.all(func(opp): return knowledge.void_suits(opp).has(trump))

	return {
		"vigilance": mode["vigilance"],
		"vigilance_gate_open": vigilance_open,
		"opposing_team": opposing_team,
		"trumps_held": trumps.size(),
		"trumps_size_gte_3": trumps.size() >= 3,
		"best_trump_candidate": best_trump_candidate_str,
		"highest_remaining_trump": top_remaining_str,
		"rank_safe": rank_safe,
		"opposing_team_all_void_in_trump": opposing_team_all_void_in_trump,
		"control_trump_eligible": vigilance_open and rank_safe and not opposing_team_all_void_in_trump,
		"per_tile_safety": per_tile,
		"safe_lead_candidates": safe_candidates.map(func(x): return x["tile"]),
		"safe_tier_would_fire": vigilance_open and safe_candidates.size() > 0,
	}

func _label_objective(reason: String) -> String:
	match reason:
		# Added post-fix (Unified Trump-Control Lead Decision, July 20 2026) —
		# these two reason strings were previously Partner-only; the fix makes
		# them reachable from full-vigilance Opponent too, via the same
		# _control_trump_lead()/_control_trump_heuristic_fallback() shared
		# functions in ai_player.gd. Without these cases they'd fall through
		# to UNMAPPED even though the behavior is correct.
		"I have trump control — drawing out the opponents.": return "CONTROL_TRUMP"
		"Leading low trump to draw out the double first.": return "CONTROL_TRUMP_HEURISTIC_FALLBACK"
		"Leading a suit you can't beat.": return "OPPONENT_SAFE_LEAD"
		"Drawing out trumps.": return "OPPONENT_TRUMP_LEAD (trumps.size() >= 3)"
		"Leading my strong count to lock in the points.": return "OPPONENT_STRONG_COUNTER"
		"Last domino.", "Leading my double.", "Leading my best domino.": return "FALLBACK_BEST"
		_: return "UNMAPPED: " + reason

func _sorted_hand_str(hand: Array, trump: int) -> String:
	var copy = hand.duplicate()
	copy.sort_custom(func(a, b): return a.get_rank(trump) > b.get_rank(trump))
	var parts: Array = []
	for d in copy:
		parts.append(d.debug_string())
	return ", ".join(parts)

func _run_scenario(name: String, hands: Array, target_seat: int, difficulty: String) -> Dictionary:
	var mode = AI_MODES[difficulty]
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("SCENARIO %s — target P%d, difficulty=%s, vigilance=%s" % [name, target_seat, difficulty, mode["vigilance"]])
	_log("═══════════════════════════════════════════════════════════")

	var game = _setup_game(hands)
	var leader = target_seat
	var stop_reason = "completed all 7 tricks without stopping"
	var trick_records: Array = []

	for trick_num in range(7):
		game.start_trick(leader)
		_log("")
		_log("── Trick %d — leader P%d ──" % [trick_num + 1, leader])

		var this_trick_record = {"trick": trick_num + 1, "leader": leader}

		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var is_partner_seat = (player.id == PARTNER_SEAT)
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var is_leading_this_play = (game.current_trick.plays.size() == 0)

			var diag = {}
			if player.id == target_seat and is_leading_this_play:
				_log("  P%d hand (sorted by trump rank): %s" % [player.id, _sorted_hand_str(player.hand, game.trump)])
				diag = _compute_opponent_lead_diagnostics(legal, game.trump, player.id, partner_id, mode, knowledge)
				_log("  vigilance=%s (gate open: %s)" % [diag["vigilance"], diag["vigilance_gate_open"]])
				for t in diag["per_tile_safety"]:
					_log("    candidate %s (suit %d%s): fully_safe=%s  %s" % [
						t["tile"], t["suit"], " DOUBLE" if t["is_double"] else "",
						t["fully_safe"],
						t["per_opponent"]
					])
				_log("  safe_lead_candidates: %s" % [diag["safe_lead_candidates"]])
				_log("  SAFE-tier would fire (vigilance open AND a candidate is fully safe): %s" % diag["safe_tier_would_fire"])
				_log("  trumps held: %d   (trumps.size() >= 3 -> %s)" % [diag["trumps_held"], diag["trumps_size_gte_3"]])
				_log("  best trump in hand: %s   highest_remaining_trump(): %s   rank_safe: %s" % [diag["best_trump_candidate"], diag["highest_remaining_trump"], diag["rank_safe"]])
				_log("  opposing_team %s all void in trump: %s" % [diag["opposing_team"], diag["opposing_team_all_void_in_trump"]])
				_log("  CONTROL_TRUMP eligible (vigilance open AND rank_safe AND not-all-void): %s" % diag["control_trump_eligible"])

			# NOTE: "difficulty" string passed to decide_play() must match a
			# real AI_MODES key in ai_player.gd (beginner/standard/expert) —
			# our local AI_MODES here is diagnostic-only and mirrors the
			# vigilance field; decide_play() reads its own copy internally.
			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				difficulty, is_partner_seat, game.variant,
				game.current_bid.player_id, knowledge,
				game.team_points, game.current_bid.value
			)

			if player.id == target_seat and is_leading_this_play:
				var reason = reason_log[-1] if reason_log.size() > 0 else "(no reason logged)"
				var label = _label_objective(reason)
				_log("  >>> CHOSE: %s   objective: %s" % [chosen.debug_string(), label])
				_log("  >>> reason_log: \"%s\"" % reason)
				this_trick_record["target_diagnostics"] = diag
				this_trick_record["target_chosen"] = chosen.debug_string()
				this_trick_record["target_reason"] = reason
				this_trick_record["target_objective_label"] = label
				this_trick_record["target_led_trump"] = chosen.is_trump(game.trump)

			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4

		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
		_log("  Trick winner: P%d" % winner_id)
		this_trick_record["winner"] = winner_id
		trick_records.append(this_trick_record)

		var target_hand_after = game.players[target_seat].hand
		var target_still_has_trump = target_hand_after.any(func(d): return d.is_trump(game.trump))

		if not target_still_has_trump:
			stop_reason = "target seat P%d has no trump remaining after trick %d" % [target_seat, trick_num + 1]
			_log("  >>> STOP: %s" % stop_reason)
			break

		if winner_id != target_seat:
			stop_reason = "target seat P%d lost the lead after trick %d (winner was P%d)" % [target_seat, trick_num + 1, winner_id]
			_log("  >>> STOP: %s" % stop_reason)
			break

		leader = winner_id

	_log("")
	_log("SCENARIO %s RESULT: %s" % [name, stop_reason])
	return {"scenario": name, "difficulty": difficulty, "target_seat": target_seat, "stop_reason": stop_reason, "tricks": trick_records}

func _init():
	trace_lines.clear()

	var results := {}
	results["B_original_expert"] = _run_scenario("B_original_expert", _hands_original(), 1, "expert")
	results["B_hardened_expert"] = _run_scenario("B_hardened_expert", _hands_hardened(), 1, "expert")
	results["B_hardened_standard"] = _run_scenario("B_hardened_standard", _hands_hardened(), 1, "standard")
	results["B_hardened_beginner"] = _run_scenario("B_hardened_beginner", _hands_hardened(), 1, "beginner")

	results["full_log"] = trace_lines

	var f = FileAccess.open("res://trump_control_trace_v2_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()

	print("")
	print("Results written to res://trump_control_trace_v2_results.json")
	quit(0)
