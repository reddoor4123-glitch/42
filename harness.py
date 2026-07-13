"""
Texas 42 Bidding Harness
========================
Faithful Python replica of ai_player.gd's bidding math (Layer 1 + Layer 2),
in two versions:

  CURRENT   — exactly what's in the game today. As of July 13, 2026 this
              includes Fixes #1 and #4 (off-suit singleton/double scoring
              in evaluate_hand()) — both shipped into ai_player.gd on
              July 12, 2026 and no longer distinguish CURRENT/CANDIDATE.
  CANDIDATE — CURRENT plus whatever's still being tuned. As of July 13,
              2026 that's only Fix #3 (fix3_tc5_bonus/fix3_tc6_bonus in
              decide()'s trump-majority control signal) — still a
              STARTING GUESS, not yet approved.

Every weight means one thing: "what fraction of the time does this tile
win a trick." Nothing here is mysterious — change a dial, rerun, see how
the hands re-rank.

Input format (hands.txt), one hand per line:
  6:6 6:5 6:4 6:0 4:2 3:2 1:0 | BID      <- your verdict: BID / PASS / BORDER
Anything after # is a comment. Tile order doesn't matter.
"""

# ── DIALS ──
# Fix #1 and Fix #4 are live in both CURRENT and CANDIDATE — they ship in
# ai_player.gd as of July 12, 2026 and are no longer a tuning question.
# Fix #3 (tc5/tc6 bonus) is CANDIDATE-only — still the one open, untuned
# dial; tune these against Katy's verdicts.
DIALS = {
    # Fix #1 — lone high off-suit tile (rank 4 singleton, e.g. lone 4:6).
    # Table read: third-highest in its suit, wins maybe 1 trick in 5.
    "fix1_singleton_rank4": 0.20,

    # Fix #4 — off-suit doubles. Base corrected to 0.55 to match
    # ai_player.gd:195 (harness previously had 0.45 — a stale value that
    # never matched what shipped; found via this file's own verification
    # step, July 13, 2026).
    # per-double: 0.55 + (pip/6)*0.25   -> 0:0=0.55 ... 6:6=0.80
    "fix4_double_base": 0.55,
    "fix4_double_pip_scale": 0.25,
    # compounding bonus for 2nd/3rd/4th off-suit double held
    "fix4_compound": [0.0, 0.3, 0.5, 0.7],
    # holding both 4:4 and 6:6 traps the 6:4 ten-count
    "fix4_bracket_44_66": 0.20,

    # Fix #3 — trump-suit majority control (Layer 2 control signal).
    # Live: tc>=5 adds a flat +1.0 on top of the tc>=4 +1.5.
    # Candidate: majority of the suit is qualitatively different.
    # STARTING GUESS ONLY — this is the least-settled dial.
    "fix3_tc5_bonus": 3.0,     # was 1.0
    "fix3_tc6_bonus": 2.0,     # additional at 6+ (was nothing)
}

THRESHOLD = 28.0
RISK_BIAS = {"beginner": -0.25, "standard": 0.0, "expert": 0.25}


# ── Domino (mirrors domino.gd exactly for the standard-contract case) ──
class Domino:
    def __init__(self, a, b):
        self.left, self.right = min(a, b), max(a, b)

    def is_double(self):
        return self.left == self.right

    def pip_sum(self):
        return self.left + self.right

    def is_trump(self, trump):
        return self.left == trump or self.right == trump

    def get_suit(self, trump):
        if trump >= 0 and self.is_trump(trump):
            return trump
        if self.is_double():
            return self.left
        return max(self.left, self.right)

    def get_rank(self, trump):
        if trump >= 0 and self.is_trump(trump):
            if self.is_double():
                return 13
            return self.left if self.right == trump else self.right
        if self.is_double():
            return 13
        suit = self.get_suit(trump)
        return self.left if self.right == suit else self.right

    def __repr__(self):
        return f"{self.left}:{self.right}"


# ── Layer 1: evaluate_hand ──
def evaluate_hand(hand, trump, candidate=False):
    trump_dominos = [d for d in hand if d.is_trump(trump)]
    off_dominos = [d for d in hand if not d.is_trump(trump)]
    est_tricks = 0.0
    has_double_trump = any(d.is_double() for d in trump_dominos)

    # Trump scoring — identical in both versions (Fix C, already live)
    for d in trump_dominos:
        if d.is_double():
            est_tricks += 0.95
        else:
            est_tricks += 0.35 + (d.get_rank(trump) / 6.0) * 0.50

    suit_counts = {}
    for d in off_dominos:
        s = d.get_suit(trump)
        suit_counts[s] = suit_counts.get(s, 0) + 1

    # Off-suit scoring — live in the game as of July 12, 2026 (Fix #1 +
    # Fix #4), identical regardless of `candidate`. The CURRENT/CANDIDATE
    # split only remains in decide()'s Fix #3 control bonus below, the one
    # dial still unsettled.
    off_doubles = []
    for d in off_dominos:
        rank = d.get_rank(trump)
        cnt = suit_counts[d.get_suit(trump)]
        if d.is_double():
            off_doubles.append(d)
        elif rank >= 4 and cnt >= 2:
            est_tricks += 0.4
        elif rank >= 5:
            est_tricks += 0.3
        elif rank >= 4:                       # Fix #1
            est_tricks += DIALS["fix1_singleton_rank4"]

    for i, d in enumerate(off_doubles):       # Fix #4
        est_tricks += (DIALS["fix4_double_base"]
                       + (d.left / 6.0) * DIALS["fix4_double_pip_scale"])
        if i < len(DIALS["fix4_compound"]):
            est_tricks += DIALS["fix4_compound"][i]
    pips = {(d.left, d.right) for d in off_doubles}
    if (4, 4) in pips and (6, 6) in pips:
        est_tricks += DIALS["fix4_bracket_44_66"]

    expected_capture = est_tricks * 6.0
    return {
        "trump": trump,
        "trump_count": len(trump_dominos),
        "has_double_trump": has_double_trump,
        "estimated_tricks": est_tricks,
        "estimated_points": expected_capture,
    }


def best_trump(hand, candidate=False):
    best_eval, best_score = None, -1.0
    for suit in range(7):
        ev = evaluate_hand(hand, suit, candidate)
        score = ev["estimated_points"] + ev["trump_count"] * 2.0
        if ev["has_double_trump"]:
            score += 3.0
        if score > best_score:
            best_score, best_eval = score, ev
    return best_eval


# ── Layer 2: signal combiner ──
def decide(hand, difficulty="standard", candidate=False):
    ev = best_trump(hand, candidate)
    est_pts = ev["estimated_points"]
    est_tricks = ev["estimated_tricks"]
    tc = ev["trump_count"]
    risk = RISK_BIAS[difficulty]

    ev_score = est_pts + risk * 4.0

    control = est_tricks * 6.0 * 0.12
    if ev["has_double_trump"]:
        control += 2.5
    if tc >= 4:
        control += 1.5
    if tc >= 5:
        control += DIALS["fix3_tc5_bonus"] if candidate else 1.0   # Fix #3
    if candidate and tc >= 6:
        control += DIALS["fix3_tc6_bonus"]                          # Fix #3

    if est_tricks >= 4.3 and ev["has_double_trump"]:
        stance, bias = "pressure_opener", 2.0
    elif est_tricks >= 4.0 and tc >= 4:
        stance, bias = "solid_opener", 1.0
    elif ev_score >= 24.0:
        stance, bias = "competitive", 0.0
    else:
        stance, bias = "defensive", -1.5

    final = ev_score + control + bias
    return {
        "trump": ev["trump"], "tc": tc, "dbl": ev["has_double_trump"],
        "tricks": est_tricks, "pts": est_pts, "stance": stance,
        "final": final, "bids": final >= THRESHOLD,
    }


# ── Runner ──
def parse_hand(line):
    if "#" in line:
        line = line.split("#")[0]
    line = line.strip()
    if not line:
        return None
    verdict = ""
    if "|" in line:
        line, verdict = [p.strip() for p in line.split("|", 1)]
    tiles = []
    for tok in line.split():
        a, b = tok.split(":")
        tiles.append(Domino(int(a), int(b)))
    if len(tiles) != 7:
        raise ValueError(f"Expected 7 tiles, got {len(tiles)}: {line}")
    return tiles, verdict.upper()


def run(path, difficulty="standard"):
    rows = []
    with open(path) as f:
        for line in f:
            parsed = parse_hand(line)
            if parsed is None:
                continue
            hand, verdict = parsed
            old = decide(hand, difficulty, candidate=False)
            new = decide(hand, difficulty, candidate=True)
            rows.append((hand, verdict, old, new))

    hdr = (f"{'HAND':<30} {'KATY':<7} "
           f"{'OLD final':>9} {'OLD?':>5} {'NEW final':>9} {'NEW?':>5}  "
           f"{'trump/tc':<9} MATCH")
    print(hdr)
    print("-" * len(hdr))
    agree = total = 0
    for hand, verdict, old, new in rows:
        hs = " ".join(map(str, hand))
        ob = "BID" if old["bids"] else "pass"
        nb = "BID" if new["bids"] else "pass"
        match = ""
        if verdict in ("BID", "PASS"):
            total += 1
            ok = (verdict == "BID") == new["bids"]
            agree += ok
            match = "yes" if ok else "** NO **"
        print(f"{hs:<30} {verdict:<7} {old['final']:>9.1f} {ob:>5} "
              f"{new['final']:>9.1f} {nb:>5}  "
              f"{new['trump']}/{new['tc']:<7} {match}")
    if total:
        print(f"\nCandidate agrees with Katy on {agree}/{total} decided hands.")


if __name__ == "__main__":
    import sys
    run(sys.argv[1] if len(sys.argv) > 1 else "hands.txt")
