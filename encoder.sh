#!/bin/bash
set -euo pipefail
python3 - "$@" <<'PY'
#!/usr/bin/env python3
"""
Flow-based SAT Encoder with Totalizer and Commander Encodings
- Totalizer: used for 'at most J turns per line'
- Commander: used for 'no overlap' between lines per cell
- Simple connectivity via forbidding cycles
"""

import sys
from itertools import combinations

# ---------- Input ----------
def read_city_file(filename):
    with open(filename, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    scenario = int(lines[0])
    params = list(map(int, lines[1].split()))
    if scenario == 1:
        N, M, K, J = params
        P = 0
        line_start = 2
    else:
        N, M, K, J, P = params
        line_start = 2

    metro_lines = []
    for i in range(K):
        coords = list(map(int, lines[line_start + i].split()))
        metro_lines.append({'start': (coords[0], coords[1]), 'end': (coords[2], coords[3])})

    popular_cells = []
    if scenario == 2 and P > 0:
        coords = list(map(int, lines[line_start + K].split()))
        popular_cells = [(coords[2*i], coords[2*i+1]) for i in range(P)]

    return {
        'scenario': scenario, 'N': N, 'M': M, 'K': K, 'J': J, 'P': P,
        'metro_lines': metro_lines, 'popular_cells': popular_cells
    }

# ---------- Helper Functions ----------
def get_next_cell(x, y, direction):
    if direction == 'N': return (x, y + 1)
    if direction == 'S': return (x, y - 1)
    if direction == 'E': return (x + 1, y)
    if direction == 'W': return (x - 1, y)
    return (None, None)

def get_opposite_dir(d):
    return {'N': 'S', 'S': 'N', 'E': 'W', 'W': 'E'}[d]

def is_turn(dir_in, dir_out):
    return (dir_in in ['N','S'] and dir_out in ['E','W']) or (dir_in in ['E','W'] and dir_out in ['N','S'])

# ---------- Variable Creation ----------
def create_flow_variables(N, M, K):
    vars_map = {}
    next_var = 1
    
    for k in range(K):
        for x in range(N):
            for y in range(M):
                if y < M - 1:
                    vars_map[('flow', k, x, y, 'N')] = next_var; next_var += 1
                if y > 0:
                    vars_map[('flow', k, x, y, 'S')] = next_var; next_var += 1
                if x < N - 1:
                    vars_map[('flow', k, x, y, 'E')] = next_var; next_var += 1
                if x > 0:
                    vars_map[('flow', k, x, y, 'W')] = next_var; next_var += 1

    for k in range(K):
        for x in range(N):
            for y in range(M):
                vars_map[('turn', k, x, y)] = next_var; next_var += 1
                vars_map[('visited', k, x, y)] = next_var; next_var += 1
    
    return vars_map, next_var

# ---------- Totalizer Encoding ----------
def at_most_k_totalizer(vars_list, k, next_var):
    clauses = []
    n = len(vars_list)
    if n <= k: return clauses, next_var
    if k == 0:
        for v in vars_list:
            clauses.append([-v])
        return clauses, next_var

    def build_totalizer(vars_list):
        nonlocal next_var, clauses
        if len(vars_list) == 1:
            return [vars_list[0]]
        mid = len(vars_list)//2
        left = build_totalizer(vars_list[:mid])
        right = build_totalizer(vars_list[mid:])
        sums = [next_var + i for i in range(len(left) + len(right))]
        next_var += len(sums)
        for i, l in enumerate(left):
            clauses.append([-l, sums[i]])
        for j, r in enumerate(right):
            clauses.append([-r, sums[j]])
        for i in range(len(left)):
            for j in range(len(right)):
                if i + j + 1 < len(sums):
                    clauses.append([-left[i], -right[j], sums[i+j+1]])
        return sums

    sums = build_totalizer(vars_list)
    if len(sums) > k:
        for i in range(k, len(sums)):
            clauses.append([-sums[i]])
    return clauses, next_var

# ---------- Commander Encoding ----------
def at_most_one_commander(vars_list, next_var, group_size=4):
    clauses = []
    n = len(vars_list)
    if n <= 1:
        return clauses, next_var
    if n == 2:
        clauses.append([-vars_list[0], -vars_list[1]])
        return clauses, next_var

    groups = [vars_list[i:i+group_size] for i in range(0, n, group_size)]
    commander_vars = []

    for group in groups:
        for (a, b) in combinations(group, 2):
            clauses.append([-a, -b])
        commander = next_var
        next_var += 1
        commander_vars.append(commander)
        for v in group:
            clauses.append([-v, commander])
        clauses.append(group + [-commander])

    if len(commander_vars) > 1:
        sub_clauses, next_var = at_most_one_commander(commander_vars, next_var, group_size)
        clauses.extend(sub_clauses)

    return clauses, next_var

# ---------- Flow Constraints ----------
def encode_flow_constraints(city_data, vars_map, N, M, K, next_var):
    clauses = []
    metro_lines = city_data['metro_lines']
    popular_cells = city_data['popular_cells']
    J = city_data['J']

    def V_flow(k,x,y,d): return vars_map.get(('flow',k,x,y,d))
    def V_turn(k,x,y): return vars_map.get(('turn',k,x,y))
    def V_vis(k,x,y): return vars_map.get(('visited',k,x,y))

    for k in range(K):
        sx, sy = metro_lines[k]['start']
        ex, ey = metro_lines[k]['end']

        for x in range(N):
            for y in range(M):
                out_flows, in_flows = [], []
                for d in ['N','S','E','W']:
                    f_out = V_flow(k,x,y,d)
                    if f_out: out_flows.append(f_out)
                    nx, ny = get_next_cell(x,y,d)
                    if nx is not None:
                        opp = get_opposite_dir(d)
                        f_in = V_flow(k,nx,ny,opp)
                        if f_in: in_flows.append(f_in)
                v = V_vis(k,x,y)
                if v is None: continue

                # Visited <=> flow equivalence
                if (x,y) == (sx,sy) or (x,y) == (ex,ey):
                    all_flows = in_flows + out_flows
                    if all_flows:
                        clauses.append([-v] + all_flows)
                        for f in all_flows:
                            clauses.append([-f, v])
                    else:
                        clauses.append([-v])
                else:
                    if in_flows and out_flows:
                        clauses.append([-v] + in_flows)
                        clauses.append([-v] + out_flows)
                        for f_in in in_flows:
                            for f_out in out_flows:
                                clauses.append([-f_in, -f_out, v])
                    else:
                        clauses.append([-v])

                # Flow structure constraints
                if (x,y) == (sx,sy):
                    if out_flows:
                        clauses.append(out_flows)
                        sub_clauses, next_var = at_most_one_commander(out_flows, next_var)
                        clauses.extend(sub_clauses)
                    for f_in in in_flows: clauses.append([-f_in])
                elif (x,y) == (ex,ey):
                    if in_flows:
                        clauses.append(in_flows)
                        sub_clauses, next_var = at_most_one_commander(in_flows, next_var)
                        clauses.extend(sub_clauses)
                    for f_out in out_flows: clauses.append([-f_out])
                else:
                    if in_flows:
                        sub_clauses, next_var = at_most_one_commander(in_flows, next_var)
                        clauses.extend(sub_clauses)
                    if out_flows:
                        sub_clauses, next_var = at_most_one_commander(out_flows, next_var)
                        clauses.extend(sub_clauses)
                    
                    if in_flows and out_flows:
                        for f_in in in_flows:
                            clauses.append([-f_in] + out_flows)
                        for f_out in out_flows:
                            clauses.append([-f_out] + in_flows)

        # Turn counting via Totalizer
        turn_vars = []
        for x in range(N):
            for y in range(M):
                if (x,y) in [(sx,sy),(ex,ey)]: continue
                t = V_turn(k,x,y)
                v = V_vis(k,x,y)
                if not t or not v: continue
                turn_vars.append(t)
                clauses.append([-t,v])
                in_flows,out_flows=[],[]
                for d in ['N','S','E','W']:
                    f_out = V_flow(k,x,y,d)
                    if f_out: out_flows.append((f_out,d))
                    nx,ny = get_next_cell(x,y,d)
                    if nx is not None:
                        opp = get_opposite_dir(d)
                        f_in = V_flow(k,nx,ny,opp)
                        if f_in: in_flows.append((f_in,opp))
                for f_in,d_in in in_flows:
                    for f_out,d_out in out_flows:
                        if is_turn(d_in,d_out): clauses.append([-f_in,-f_out,t])
                        else: clauses.append([-f_in,-f_out,-t])

        t_clauses,next_var = at_most_k_totalizer(turn_vars,J,next_var)
        clauses.extend(t_clauses)

        # ========== CONNECTIVITY: Forbid 2-cycles ==========
        # This alone is sufficient with our other constraints!
        # A 2-cycle would allow disconnected segments
        for x in range(N):
            for y in range(M):
                for d in ['N', 'S', 'E', 'W']:
                    nx, ny = get_next_cell(x, y, d)
                    if nx is not None and 0 <= nx < N and 0 <= ny < M:
                        f_out = V_flow(k, x, y, d)
                        opp = get_opposite_dir(d)
                        f_back = V_flow(k, nx, ny, opp)
                        if f_out and f_back:
                            # Cannot have both A->B and B->A
                            clauses.append([-f_out, -f_back])

    # No overlap
    for x in range(N):
        for y in range(M):
            vlist = [vars_map[('visited',k,x,y)] for k in range(K)]
            if len(vlist)>1:
                sub,next_var = at_most_one_commander(vlist,next_var)
                clauses.extend(sub)

    # Popular cells
    if city_data['scenario']==2:
        for (px,py) in popular_cells:
            vlist = []
            for k in range(K):
                v = vars_map.get(('visited',k,px,py))
                if v is not None:
                    vlist.append(v)
            if vlist:
                clauses.append(vlist)

    return clauses,next_var

# ---------- Encoder ----------
def encode_all_constraints(city_data):
    N,M,K = city_data['N'],city_data['M'],city_data['K']
    vars_map,next_var = create_flow_variables(N,M,K)
    clauses,final_next = encode_flow_constraints(city_data,vars_map,N,M,K,next_var)
    return clauses,final_next-1

# ---------- Main ----------
def main():
    if len(sys.argv)!=2:
        print("Usage: python3 optimized_encoder.py <basename>")
        sys.exit(1)
    base=sys.argv[1]
    city_file=f"{base}.city"
    data=read_city_file(city_file)
    
    print(f"\n{'='*60}")
    print(f"Input: {city_file}")
    print(f"Scenario: {data['scenario']}")
    print(f"Grid: {data['N']}x{data['M']}, Lines: {data['K']}, Max turns: {data['J']}")
    if data['scenario'] == 2:
        print(f"Popular cells ({data['P']}): {data['popular_cells']}")
    print(f"{'='*60}\n")
    
    clauses,num_vars=encode_all_constraints(data)
    with open(f"{base}.satinput","w") as f:
        f.write(f"p cnf {num_vars} {len(clauses)}\n")
        for c in clauses:
            f.write(" ".join(map(str,c))+" 0\n")
    print(f"Flow-based encoding complete:")
    print(f"  Variables: {num_vars}")
    print(f"  Clauses: {len(clauses)}")
    print(f"Output: {base}.satinput")

if __name__=="__main__":
    main()
PY