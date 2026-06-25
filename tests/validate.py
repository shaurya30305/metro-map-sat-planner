#!/usr/bin/env python3
# Validates a .metromap against its .city instance:
#  - each line starts at s_k, ends at e_k
#  - each line makes at most J turns
#  - no grid cell is used by more than one line
import sys

def main(base):
    with open(base + ".city") as f:
        lines = [l.strip() for l in f if l.strip()]
    scenario = int(lines[0]); p = list(map(int, lines[1].split()))
    N, M, K, J = p[0], p[1], p[2], p[3]
    metros = []
    for i in range(K):
        x1, y1, x2, y2 = map(int, lines[2 + i].split())
        metros.append(((x1, y1), (x2, y2)))

    with open(base + ".metromap") as f:
        rows = [l.strip() for l in f if l.strip()]
    if rows == ["0"]:
        print("  instance reported UNSAT"); return 0
    assert len(rows) == K, f"expected {K} lines, got {len(rows)}"

    delta = {"R": (1, 0), "L": (-1, 0), "U": (0, -1), "D": (0, 1)}
    used = {}
    for k, row in enumerate(rows):
        moves = [t for t in row.split() if t in delta]
        (sx, sy), (ex, ey) = metros[k]
        x, y = sx, sy
        cells = [(x, y)]
        turns, prev = 0, None
        for mv in moves:
            if prev is not None and mv != prev:
                turns += 1
            prev = mv
            dx, dy = delta[mv]; x += dx; y += dy
            cells.append((x, y))
        assert (x, y) == (ex, ey), f"line {k}: ends at {(x,y)}, expected {(ex,ey)}"
        assert turns <= J, f"line {k}: {turns} turns > J={J}"
        for c in cells:
            assert c not in used, f"cell {c} shared by lines {used[c]} and {k}"
            used[c] = k
        print(f"  line {k}: {(sx,sy)}->{(ex,ey)} OK ({turns} turns, {len(moves)} moves)")
    print("  ALL CONSTRAINTS SATISFIED")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
