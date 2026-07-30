extends SceneTree
# Checks the bottom-left bid reminder names the winning bidder by the name shown
# on the table rather than a "P<seat>" index, for every seat including the human.
# Run WITHOUT --headless:
#   godot --path . --script res://headless/bid_reminder_name_probe.gd

const BidScript = preload("res://bid.gd")

func _init():
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame

	var game = table.game
	game.trump = 4
	var fail := 0
	print("human_seat = %d" % table.human_seat)
	for pid in range(4):
		game.current_bid = BidScript.new(BidScript.Type.POINTS, 30, pid)
		table._update_bid_reminder()
		var line1: String = table.bid_reminder_label.text.split("\n")[0]
		var seat_name: String = table._seat_label(pid)
		var ok: bool = line1.begins_with(seat_name) and not line1.begins_with("P%d" % pid)
		print("  seat %d -> %-28s (seat label \"%s\") %s" % [
			pid, "\"%s\"" % line1, seat_name, "ok" if ok else "WRONG"])
		if not ok:
			fail += 1

	# The reminder is a floating overlay at a fixed left edge, so a long name
	# must not run under the player's own hand.
	var longest := ""
	for pid in range(4):
		if table._seat_label(pid).length() > longest.length():
			longest = table._seat_label(pid)
	game.current_bid = BidScript.new(BidScript.Type.POINTS, 30, (table.human_seat + 1) % 4)
	table._update_bid_reminder()
	for i in range(4):
		await process_frame
	var rem: Rect2 = table.bid_reminder_label.get_global_rect()
	var hand_left := INF
	for c in table.player_hand_container.get_children():
		if c is Control:
			hand_left = min(hand_left, c.get_global_rect().position.x)
	print("")
	print("reminder x=%.1f..%.1f | leftmost hand tile x=%.1f | longest seat name \"%s\"" % [
		rem.position.x, rem.end.x, hand_left, longest])
	if rem.end.x > hand_left:
		print("FAIL: bid reminder runs under the player's hand")
		fail += 1
	else:
		print("PASS: bid reminder clears the player's hand")

	print("")
	print("=== %s (%d failures) ===" % ["OK" if fail == 0 else "FAILURES", fail])
	quit(0)
