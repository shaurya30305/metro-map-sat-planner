#!/bin/bash
set -euo pipefail

# run2.sh: write a temporary sat_decoder.py, execute it with same args, then delete it

TMP=$(mktemp /tmp/sat_decoder.XXXXXX.py)
cat > "$TMP" <<'PY'
#!/usr/bin/env python3
"""
Decoder for Flow-based SAT Encoder (Metro Map Planning)
Reads <basename>.satoutput and reconstructs metro paths to <basename>.metromap
"""

import sys

def read_city_file(filename):
    with open(filename) as f:
        lines = [line.strip() for line in f if line.strip()]
    scenario = int(lines[0])
    params = list(map(int, lines[1].split()))
    if scenario == 1:
        N, M, K, J = params
        P = 0
        start_line = 2
    else:
        N, M, K, J, P = params
        start_line = 2
    metro_lines = []
    for i in range(K):
        x1, y1, x2, y2 = map(int, lines[start_line + i].split())
        metro_lines.append(((x1, y1), (x2, y2)))
    return N, M, K, J, metro_lines

def parse_model(satoutput_path):
    with open(satoutput_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if lines[0] != "SAT":
        return None
    model = []
    for l in lines[1:]:
        if l.startswith('v ') or l.startswith('V '):
            l = l[2:]
        model.extend(l.split())
    vals = set(int(v) for v in model if int(v) > 0)
    return vals

def get_next_cell(x, y, direction):
    """Get the next cell in given direction"""
    if direction == 'N':
        return x, y + 1
    elif direction == 'S':
        return x, y - 1
    elif direction == 'E':
        return x + 1, y
    elif direction == 'W':
        return x - 1, y
    return None

def create_flow_var_map(N, M, K):
    """
    Recreate the variable mapping from the encoder.
    Must match exactly with the encoder's variable creation.
    """
    vars_map = {}
    next_var = 1
    
    # Flow variables: match encoder's order exactly
    for k in range(K):
        for x in range(N):
            for y in range(M):
                # Only create flow vars for valid directions
                if y < M - 1:  # Can go North
                    vars_map[('flow', k, x, y, 'N')] = next_var
                    next_var += 1
                if y > 0:  # Can go South
                    vars_map[('flow', k, x, y, 'S')] = next_var
                    next_var += 1
                if x < N - 1:  # Can go East
                    vars_map[('flow', k, x, y, 'E')] = next_var
                    next_var += 1
                if x > 0:  # Can go West
                    vars_map[('flow', k, x, y, 'W')] = next_var
                    next_var += 1
    
    # Turn variables: match encoder's order exactly
    for k in range(K):
        for x in range(N):
            for y in range(M):
                vars_map[('turn', k, x, y)] = next_var
                next_var += 1
    
    return vars_map

def reconstruct_path_from_flow(model, vars_map, k, start, end, N, M):
    """
    Reconstruct the path for line k by following the flow variables.
    """
    path = [start]
    current = start
    visited = {start}
    
    while current != end:
        x, y = current
        found_next = False
        
        # Check all outgoing flows from current cell
        for direction in ['N', 'S', 'E', 'W']:
            flow_var = vars_map.get(('flow', k, x, y, direction))
            if flow_var and flow_var in model:
                # This flow is active, follow it
                next_cell = get_next_cell(x, y, direction)
                if next_cell and next_cell not in visited:
                    path.append(next_cell)
                    visited.add(next_cell)
                    current = next_cell
                    found_next = True
                    break
        
        if not found_next:
            # Dead end - this shouldn't happen in a valid solution
            print(f"Warning: Dead end at {current} for line {k}")
            break
        
        # Safety check to prevent infinite loops
        if len(path) > N * M:
            print(f"Warning: Path too long for line {k}, stopping")
            break
    
    return path

def coordinates_to_directions(path):
    """Convert a path of coordinates to R/L/U/D directions"""
    if len(path) <= 1:
        return []
    
    directions = []
    for i in range(len(path) - 1):
        x1, y1 = path[i]
        x2, y2 = path[i + 1]
        
        if x2 > x1:  # Moving right (East)
            directions.append('R')
        elif x2 < x1:  # Moving left (West)
            directions.append('L')
        elif y2 > y1:  # Moving down (North - y increases)
            directions.append('D')
        elif y2 < y1:  # Moving up (South - y decreases)
            directions.append('U')
    
    return directions

def decode_solution(model, N, M, K, metro_lines, basename):
    vars_map = create_flow_var_map(N, M, K)
    metro_paths = []
    
    # Reconstruct path for each metro line
    for k in range(K):
        start, end = metro_lines[k]
        path = reconstruct_path_from_flow(model, vars_map, k, start, end, N, M)
        metro_paths.append(path)
        
        # Print the path cells for debugging
        print(f"Line {k}: {' -> '.join(str(cell) for cell in path)}")
    
    # Write to .metromap in the required format
    out_file = f"{basename}.metromap"
    with open(out_file, "w") as f:
        if not metro_paths or all(len(p) == 0 for p in metro_paths):
            f.write("0\n")
            print("Problem is UNSAT - outputting single 0")
            return
        
        for path in metro_paths:
            if len(path) <= 1:
                # If path is empty or has only start point, output empty path
                f.write("0\n")
            else:
                directions = coordinates_to_directions(path)
                # Write directions separated by spaces, ending with 0
                f.write(" ".join(directions) + " 0\n")
    
    print(f"\nDecoded {len(metro_paths)} paths to {out_file}")
    
    # Also write a detailed debug file with cell coordinates
    debug_file = f"{basename}.paths_debug"
    with open(debug_file, "w") as f:
        f.write(f"Metro Paths (Cell Coordinates)\n")
        f.write(f"=" * 50 + "\n\n")
        for k, path in enumerate(metro_paths):
            f.write(f"Line {k} (from {metro_lines[k][0]} to {metro_lines[k][1]}):\n")
            if len(path) > 1:
                for i, cell in enumerate(path):
                    f.write(f"  Step {i}: {cell}\n")
                f.write(f"  Total cells: {len(path)}\n")
            else:
                f.write(f"  Empty or invalid path\n")
            f.write("\n")
    
    print(f"Detailed path coordinates written to {debug_file}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 flow_decoder.py <basename>")
        sys.exit(1)
    
    base = sys.argv[1]
    city_file = f"{base}.city"
    satoutput_file = f"{base}.satoutput"
    
    N, M, K, J, metro_lines = read_city_file(city_file)
    model = parse_model(satoutput_file)
    
    if model is None:
        with open(f"{base}.metromap", "w") as f:
            f.write("0\n")
        print("UNSATISFIABLE — wrote single 0.")
    else:
        print(f"Grid: {N}x{M}, Lines: {K}, Max turns per line: {J}")
        print(f"Model has {len(model)} true variables\n")
        decode_solution(model, N, M, K, metro_lines, base)

if __name__ == "__main__":
    main()
PY

chmod +x "$TMP"
python3 "$TMP" "$@"
status=$?
rm -f "$TMP"
exit $status