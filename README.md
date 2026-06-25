# Metro Map Planner via SAT

Solves a metro-network routing problem by **encoding it as a Boolean satisfiability (CNF) instance**, solving it with [MiniSat](http://minisat.se/), and decoding the satisfying assignment back into concrete metro routes.

Given a city modelled as an `N × M` grid and `K` metro lines (each with a start and end cell), the planner finds non-overlapping paths subject to:

1. **At most one** metro line through any grid cell.
2. Each line `k` forms a valid connected path from its start `sₖ` to its end `eₖ`.
3. **At most `J` turns** per line.
4. *(Scenario 2)* Designated **popular cells** must be covered by some line.

The whole problem is reduced to a single MiniSat call; the encoding is polynomial in the grid size.

## Approach

The encoder builds the CNF using cardinality/constraint encodings chosen for compactness:

- **Totalizer encoding** for the "at most `J` turns per line" constraint.
- **Commander encoding** for the "no two lines share a cell" (mutual-exclusion) constraint.
- Connectivity enforced via path/flow constraints with cycle elimination.

The decoder reads MiniSat's variable assignment and reconstructs each line as a direction string (`L`/`R`/`U`/`D`), or reports `0` if the instance is unsatisfiable.

## Files

| File | Role |
|------|------|
| `encoder.sh` | Reads a city instance and emits a DIMACS CNF for MiniSat (Totalizer + Commander encodings). |
| `decoder.sh` | Reads MiniSat's output and reconstructs the metro map. |
| `docs/assignment.pdf` | Full problem specification (input/output formats, both scenarios). |

## Usage

```bash
# 1. Encode the instance to CNF
./encoder.sh city.txt          # -> city.cnf (or <basename>.satinput)

# 2. Solve with MiniSat
minisat city.cnf city.satoutput

# 3. Decode the assignment into a metro map
./decoder.sh city.txt          # reads city.satoutput -> city.metromap
```

### Input format
```
1                # scenario (1 = basic, 2 = with popular cells)
8 6 2 1          # N M K J   (scenario 2 adds P)
0 0 5 2          # line 0: start (x,y)  end (x,y)
2 1 4 3          # line 1: ...
```
See `docs/assignment.pdf` for the exact grammar and the Scenario-2 extension.
