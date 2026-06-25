# Metro Map Planner via SAT

Solves a metro-network routing problem by **encoding it as a Boolean satisfiability (CNF) instance**, solving it with [MiniSat](http://minisat.se/), and decoding the satisfying assignment back into concrete metro routes.

## Problem

A city is modelled as an `N × M` grid (columns `0..N-1`, rows `0..M-1`, origin top-left). `K` metro lines are proposed, each with a unique start `sₖ` and end `eₖ`. The task is to lay out a path for every line subject to:

1. **At most one** metro line passes through any grid cell.
2. Each line `k` is a connected path from `sₖ` to `eₖ`.
3. Each line makes **at most `J` turns** (`J` is small, e.g. 1–3).
4. *(Scenario 2)* A set of **popular cells** must each be covered by some line.

The entire problem is reduced to a **single** MiniSat call, with an encoding whose size is polynomial in the grid size.

### Input format (`<name>.city`)
```
1                # scenario: 1 = basic, 2 = with popular cells
8 6 2 1          # N M K J   (scenario 2 appends P, the number of popular cells)
0 0 5 2          # line 0: start (x,y)  end (x,y)
2 1 4 3          # line 1: ...
                 # scenario 2 only: a final line listing the P popular cells as x y pairs
```

### Output format (`<name>.metromap`)
One row per line, as a sequence of moves `L`/`R`/`U`/`D` (left/right/up/down) terminated by `0`. If the instance is unsatisfiable, the output is a single `0`.
```
R R R R R D D 0
R R D D 0
```

## Approach

The encoder reduces the constraints to CNF using compact cardinality/selection encodings:

- **Totalizer encoding** for the "at most `J` turns per line" cardinality constraint.
- **Commander encoding** for the "no two lines share a cell" mutual-exclusion constraint.
- Path connectivity enforced via flow-style constraints with cycle elimination.

The decoder reads MiniSat's variable assignment and reconstructs each line as a direction string, or emits `0` if unsatisfiable.

## Files

| File | Role |
|------|------|
| `encoder.sh` | Reads `<name>.city` and writes a DIMACS CNF to `<name>.satinput`. |
| `decoder.sh` | Reads `<name>.satoutput` and writes the reconstructed map to `<name>.metromap`. |

## Usage

Requires MiniSat (`apt-get install minisat` / `brew install minisat`).

```bash
bash encoder.sh tests/sample              # -> tests/sample.satinput
minisat tests/sample.satinput tests/sample.satoutput
bash decoder.sh tests/sample              # -> tests/sample.metromap
```

## Testing

`run_tests.sh` runs the full pipeline on a sample instance and then **validates the result against the constraints** — it simulates the decoded moves to confirm each line starts/ends at the right cells, makes ≤ `J` turns, and that no two lines share a cell:

```bash
./run_tests.sh
```

Expected output:

```
1) Encoding tests/sample.city -> CNF
2) Solving with MiniSat
3) Decoding model -> metro map
4) Validating solution against constraints
  line 0: (0, 0)->(5, 2) OK (1 turns, 7 moves)
  line 1: (2, 1)->(4, 3) OK (1 turns, 4 moves)
  ALL CONSTRAINTS SATISFIED

TEST PASSED
```

The sample instance is [`tests/sample.city`](tests/sample.city); the validator is [`tests/validate.py`](tests/validate.py).
