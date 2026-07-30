extends SceneTree
# Verification for the Nunito/Rye font work.
# Run with: godot --headless --script res://scripts/font_verify.gd
#
# Checks the two things that can't be eyeballed from the spec alone:
#   1. wght 815 actually samples heavier than wght 400 off the variable font.
#   2. The symbol/emoji fallback chain still resolves the glyphs the UI uses.

const GLYPHS := {
	"●  filled circle (pip dots)":  "●",
	"⚙  gear (settings btn)":       "⚙",
	"✕  multiply (replay close)":   "✕",
	"⌂  house (Menu btn)":          "⌂",
	"★  star (custom ruleset)":     "★",
	"▶  right triangle (section)":  "▶",
	"▼  down triangle (section)":   "▼",
	"◀  left triangle (drum)":      "◀",
	"▾  small down (More)":         "▾",
	"←  left arrow (Back)":         "←",
	"→  right arrow (Continue)":    "→",
	"‹  single quote-left (Back)":  "‹",
	"✓  check (replay bubble)":     "✓",
	"—  em dash (status text)":     "—",
	"…  ellipsis (opts btn)":       "…",
	"🚩 flag emoji (Flag btn)":      "🚩",
	"🎉 party emoji (win banner)":   "🎉",
}

# Mirrors game_table._make_variation() exactly, including the integer-tag form
# that variation_opentype requires (a string "wght" key is a silent no-op).
func _make_variation(base: FontFile, fallbacks: Array[Font], weight: int) -> FontVariation:
	var fv = FontVariation.new()
	fv.base_font = base
	if weight > 0:
		var wght_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
		fv.variation_opentype = {wght_tag: weight}
	fv.fallbacks = fallbacks
	return fv

func _init():
	var fail := 0

	var nunito_base: FontFile = load("res://fonts/Nunito-VariableFont_wght.ttf")
	var rye_base: FontFile = load("res://fonts/Rye-Regular.ttf")
	print("Nunito loaded: %s" % (nunito_base != null))
	print("Rye loaded:    %s" % (rye_base != null))
	if nunito_base == null or rye_base == null:
		print("FAIL: font file did not load")
		quit(1)
		return

	var fallbacks: Array[Font] = [
		load("res://fonts/NotoSansSymbols.ttf"),
		load("res://fonts/NotoSansSymbols2.ttf"),
		load("res://fonts/NotoEmoji.ttf"),
	]

	var regular := _make_variation(nunito_base, fallbacks, 400)
	var heavy   := _make_variation(nunito_base, fallbacks, 815)
	var rye     := _make_variation(rye_base, fallbacks, 0)

	# ── 1. Does 815 actually render heavier than 400? ────────────────────────
	print("\n--- WEIGHT AXIS ---")
	var sample := "The National Game of Texas"
	var size := 40
	var w_bare  = nunito_base.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w_400   = regular.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w_815   = heavy.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	print("width @ default instance (no wght set) : %.2f" % w_bare)
	print("width @ wght 400                       : %.2f" % w_400)
	print("width @ wght 815                       : %.2f" % w_815)

	if w_815 > w_400:
		print("PASS: wght 815 is wider than 400 by %.2fpx (%.1f%%) — axis is live" % [
			w_815 - w_400, (w_815 / w_400 - 1.0) * 100.0])
	else:
		print("FAIL: wght 815 is NOT heavier than 400 — variation_opentype not applied")
		fail += 1

	if abs(w_bare - w_400) < 0.01:
		print("NOTE: default instance == wght 400 (spec's assumption would have held)")
	else:
		print("PASS: default instance (%.2f) != wght 400 (%.2f) — confirms Nunito's" % [w_bare, w_400])
		print("      fvar default is 200/ExtraLight, so explicit wght 400 was required")

	# Guard against silently regressing to the string-key form.
	var noop := FontVariation.new()
	noop.base_font = nunito_base
	noop.variation_opentype = {"wght": 815}
	var w_noop = noop.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if abs(w_noop - w_bare) < 0.01:
		print("PASS: string-key {\"wght\": 815} confirmed a no-op (%.2f == default %.2f)" % [w_noop, w_bare])
		print("      — integer tag via name_to_tag() is mandatory, as used above")
	else:
		print("NOTE: string-key form now appears to work (%.2f); integer tag still correct" % w_noop)

	# ── 2. Fallback chain coverage ───────────────────────────────────────────
	print("\n--- FALLBACK COVERAGE ---")
	print("%-34s %-10s %-10s %s" % ["glyph", "nunito", "w/chain", "verdict"])
	for desc in GLYPHS:
		var ch: String = GLYPHS[desc]
		var cp := ch.unicode_at(0)
		var bare_has := nunito_base.has_char(cp)
		var chain_has := regular.has_char(cp)
		var verdict := ""
		if chain_has:
			verdict = "ok" if bare_has else "ok (via fallback)"
		else:
			verdict = "MISSING -> tofu"
			fail += 1
		print("%-34s %-10s %-10s %s" % [desc, str(bare_has), str(chain_has), verdict])

	var rye_missing := 0
	for desc in GLYPHS:
		if not rye.has_char(GLYPHS[desc].unicode_at(0)):
			rye_missing += 1
	print("\nRye + chain: %d/%d glyphs resolvable" % [GLYPHS.size() - rye_missing, GLYPHS.size()])
	# Rye only carries the menu "42" and the hand banner. The banner text
	# includes 🎉, so that one specifically must resolve.
	var party := "🎉".unicode_at(0)
	if rye.has_char(party):
		print("PASS: banner emoji 🎉 resolves under Rye (needed by 'YOU WIN THIS HAND! 🎉')")
	else:
		print("FAIL: banner emoji 🎉 does NOT resolve under Rye — banner would show tofu")
		fail += 1
	for d in "0123456789":
		pass
	if rye.has_char("4".unicode_at(0)) and rye.has_char("2".unicode_at(0)):
		print("PASS: Rye carries '4' and '2' for the menu title")
	else:
		print("FAIL: Rye missing digits for the '42' menu title")
		fail += 1

	# ── 3. Diamond geometry sanity ───────────────────────────────────────────
	print("\n--- DIAMOND OFFSETS (human_seat=0, TILE_FULL=64x128) ---")
	var tile := Vector2(64, 128)
	var bias := 0.4
	var human := 0
	for pid in range(4):
		var dx = tile.x * bias
		var dy = tile.y * bias * 0.5
		var off: Vector2
		var who: String
		if pid == human:
			off = Vector2(0, dy);   who = "you (bottom)"
		elif pid == (human + 2) % 4:
			off = Vector2(0, -dy);  who = "partner (top)"
		elif pid == (human + 1) % 4:
			off = Vector2(dx, 0);   who = "right opp"
		else:
			off = Vector2(-dx, 0);  who = "left opp"
		print("  P%d %-16s offset (%6.1f, %6.1f)" % [pid, who, off.x, off.y])
	print("  container min height: %.0f (TILE_FULL.y + 80)" % (tile.y + 80))

	print("\n=== %s (%d failure%s) ===" % [
		"ALL CHECKS PASSED" if fail == 0 else "FAILURES PRESENT",
		fail, "" if fail == 1 else "s"])
	quit(0 if fail == 0 else 1)
