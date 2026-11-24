# Pseudocode: coordination, planning and control algorithms (Deliverable 2, draft)

Draft, Nov 24 2026. The 9 behaviors from Deliverable 2, written for a swarm of N <= 4 UAVs running on
Aerostack2 and AERPAW.

## Shared setup (used by every algorithm)

```
N               number of UAVs (<= 4), ids i = 1..N
p_i, v_i        position and velocity of UAV i in ONE shared frame (ENU metres from a common origin;
                each drone's GPS converted to that frame, since local frames start at each takeoff point)
dt              coordinator step, 1-2 s (AERPAW: waypoints go out as DO_REPOSITION, so think in steps)
d_min           minimum separation, e.g. 5 m
A = [a_ij]      communication graph: a_ij = 1 if i hears j (all ones = fully connected)
N_i             neighbours of i: { j : a_ij = 1 }
send_target(i, q)     -> drone i's go_to behavior -> platform -> DO_REPOSITION (filter checks geofence)
send_velocity(i, u)   -> velocity setpoint (allowed by the filter, not yet enabled in our AERPAW mode)

procedure SAFE_SEND(targets q_1..q_N):
    for each pair (i, j):
        if |q_i - q_j| < d_min: shrink both steps toward current positions until separation holds
    clip each q_i to the geofence and to altitude 20-120 m
    for each i: send_target(i, q_i)
    log (time, p_i, q_i) for all i      # for formation error, min separation, completion time
```

Every algorithm below is a function `STEP(state) -> targets` called once per dt, followed by `SAFE_SEND`.
Centralized = one coordinator sees everyone. Distributed = each UAV runs its own copy using only N_i.

---

## 1. Leader-follower formation (centralized or distributed, hierarchical)

Leader flies a planned path; follower i keeps a fixed offset d_i in the leader's body frame.

```
input: leader path W = [w_1..w_K], offsets d_i (body frame), gain k in (0, 1]
loop every dt:
    leader target  q_L = next waypoint of W (advance when |p_L - w_k| < tol)
    psi_L = leader heading (yaw)
    for each follower i:
        slot_i = p_L + R(psi_L) * d_i              # where i should be
        q_i    = p_i + k * (slot_i - p_i)          # move part-way (smooth; k = 1 jumps to the slot)
    SAFE_SEND(q_L, q_1..q_N)
until leader reaches w_K
metric: formation error e_i = |p_i - (p_L + R(psi_L) d_i)|
```

## 2. Consensus formation (distributed)

Each UAV only knows neighbours. Agree on a common formation centre; shape is given by offsets d_i.

```
input: desired offsets d_i (shape around a centre), graph A, step size eps < 1 / max_degree
loop every dt, for each UAV i (in parallel):
    # (p_i - d_i) is UAV i's estimate of the formation centre; push it toward the neighbours' estimates
    u_i  = eps * sum_{j in N_i} a_ij * ((p_j - d_j) - (p_i - d_i))
    q_i  = p_i + u_i
    SAFE_SEND(q_i)
until max_i,j |(p_i - d_i) - (p_j - d_j)| < tol      # all agree on the centre
note: converges if the graph is connected; the centre ends at the average of initial (p_i - d_i).
```

## 3. Rendezvous / average consensus (distributed)

Same as 2 with all offsets d_i = 0: everyone meets at one point (the average start, at a common altitude).
For real drones, "meet" means "gather around a point", so stop at a ring of radius r instead of colliding.

```
input: graph A, eps < 1 / max_degree, gather radius r
loop every dt, for each UAV i:
    c_i = p_i + eps * sum_{j in N_i} (p_j - p_i)      # average consensus update
    if |c_i - p_i| < tol: hold position
    q_i = c_i
    SAFE_SEND(q_i)                                     # SAFE_SEND keeps them >= d_min apart
until max_i,j |p_i - p_j| < 2r + tol
variant (connectivity keeping): scale the step down if it would push |p_i - p_j| over comm range for j in N_i.
```

## 4. Formation reconfiguration (centralized, assignment + synchronized motion)

Switch from shape S_old to S_new (e.g. square -> line for a corridor), choosing who goes to which slot so the
total travel is minimal (for equal-weight points this is the optimal-transport problem = linear assignment).

```
input: new slots s_1..s_N (absolute, e.g. centre + new offsets), trigger (e.g. corridor width < shape width)
on trigger:
    C[i][k] = |p_i - s_k|^2                       # cost of UAV i taking slot k
    sigma   = HUNGARIAN(C)                        # UAV i -> slot sigma(i), min total squared distance
    T       = max_i |p_i - s_sigma(i)| / v_max    # all arrive together
    for t = dt, 2dt, ..., T:
        for each i: q_i = p_i(start) + (t / T) * (s_sigma(i) - p_i(start))    # straight-line, synchronized
        SAFE_SEND(q_1..q_N)
note: min-squared-distance assignment gives straight paths that do not cross in 2D; still keep SAFE_SEND.
```

## 5. Task allocation (centralized Hungarian, distributed greedy auction)

M tasks (points to visit) for N UAVs.

```
# 5a. Centralized optimal (one task per UAV)
C[i][m] = travel cost of UAV i to task m (distance, or time)
sigma   = HUNGARIAN(C)                            # minimizes total cost
for each i: send_target(i, task_sigma(i))

# 5b. Greedy sequential auction (works for M > N, each UAV builds a task list)
unassigned = all tasks; route_i = [] for all i
while unassigned not empty:
    for each i: for each m in unassigned:
        bid[i][m] = marginal cost of inserting m into route_i (extra travel)
    (i*, m*) = argmin bid
    insert m* into route_i*; remove m* from unassigned
each UAV flies its route (go_to each task in order)

# 5c. Distributed (CBBA idea): each UAV builds a bundle greedily with its own bids, then neighbours
#     exchange winning bids; a UAV drops a task (and everything after it in its bundle) if a neighbour bids
#     better; repeat until no bundle changes.
```

## 6. Area coverage: Lloyd / Voronoi (distributed)

Spread the UAVs over a polygon Q so each covers its nearest region; optionally sweep that region.

```
input: area Q (inside the geofence), density phi(x) (uniform = 1), gain k in (0, 1]
loop every dt:
    for each UAV i:
        V_i = { x in Q : |x - p_i| <= |x - p_j| for all j }      # Voronoi cell (only neighbours needed)
        M_i = integral over V_i of phi(x) dx
        C_i = (1 / M_i) * integral over V_i of x * phi(x) dx     # centroid (compute on a grid of Q)
        q_i = p_i + k * (C_i - p_i)
    SAFE_SEND(q_1..q_N)
until max_i |C_i - p_i| < tol                    # centroidal Voronoi configuration
then (optional sweep): each UAV flies a lawnmower path over its own V_i with line spacing = sensor footprint.
metric: coverage cost H = sum_i integral over V_i of |x - p_i|^2 phi(x) dx (should decrease each step)
```

## 7. Cooperative multi-UAV path planning: prioritized planning (centralized)

Plan collision-free paths one UAV at a time on a space-time grid; later UAVs avoid earlier ones.

```
input: grid G (cells inside the geofence, obstacles removed), starts s_i, goals g_i, priority order (e.g. longest path first)
reserved = {}                                     # set of (cell, time) and (edge, time) already taken
for i in priority order:
    path_i = SPACE_TIME_ASTAR(G, s_i, g_i, reserved)
    if path_i fails: re-order priorities (or raise i's priority) and restart
    for t, cell in path_i: reserved += (cell, t), plus neighbouring cells within d_min
    for each move (a -> b at t): reserved += edge (b -> a at t)      # no head-on swaps
    reserve (g_i, t >= arrival) so nobody passes through a parked UAV

SPACE_TIME_ASTAR: A* over states (cell, t); moves = 4/8 neighbours or wait; a state is invalid if in reserved;
                  heuristic = distance to goal / step length.
execution: at step t, q_i = path_i[t] (cell centre -> GPS); everyone advances in lockstep every dt.
```

## 8. Multi-UAV collision avoidance: ORCA (distributed, no communication)

Each UAV picks the velocity closest to its preferred one that cannot collide with any neighbour within tau seconds,
assuming each neighbour takes half of the avoidance responsibility.

```
input: preferred velocity v_pref_i (e.g. toward its goal, capped at v_max), radius r (= d_min / 2), horizon tau
loop every dt, for each UAV i:
    H = {}                                        # list of half-planes (half-spaces in 3D)
    for each neighbour j within sensing range:
        p = p_j - p_i ; v = v_i - v_j ; R = 2r
        VO = { v' : exists t in [0, tau] with |v' t - p| < R }   # velocity obstacle (truncated cone)
        if v in VO:
            u = vector from v to the closest point on the boundary of VO
            n = outward normal of VO at that point
            H += { v' : (v' - (v_i + u / 2)) . n >= 0 }         # i takes half of the correction
    v_new = argmin |v' - v_pref_i| subject to v' in H and |v'| <= v_max   # small LP (2D or 3D)
    if infeasible: choose the velocity that minimizes the largest violation (RVO2 3-D fallback)
    send_velocity(i, v_new)              # or q_i = p_i + v_new * dt with send_target
note: ORCA is velocity-based; on AERPAW it needs velocity setpoints enabled, or a short-step waypoint
      approximation (works, but dt of 1-2 s makes it far less reactive).
```

## 9. Cooperative exploration: frontier-based (centralized assignment)

UAVs explore an unknown area; a shared occupancy map is updated from their sensors; frontiers = boundary between
known-free and unknown.

```
input: map grid (unknown / free / occupied), sensor range rs, utility U0, discount radius rd
loop:
    merge all UAVs' scans into the shared map
    F = cells that are free and have an unknown neighbour
    clusters = group F into connected clusters; target f_c = centroid (or nearest frontier cell) of each cluster
    if F is empty: done (fully explored)
    U[c] = U0 for every cluster c
    for each UAV i in turn (e.g. closest to any frontier first):      # coordinated greedy (Burgard-style)
        c* = argmax_c ( U[c] - beta * pathcost(p_i, f_c) )
        assign f_c* to i
        for each cluster c within rd of f_c*: U[c] *= (1 - P_visible(c | f_c*))   # discount nearby frontiers
    SAFE_SEND(assigned frontiers)
    wait until each UAV reaches its frontier or dt * k elapsed, then repeat
note: AERPAW drones carry no mapping sensor we can use here, so the map and scans are simulated from known
      position (disc of radius rs around each UAV marks cells free); the coordination part is unchanged.
```

---

## Which ones map most easily to Aerostack2 + AERPAW now

| # | Algorithm | Command type | Fits waypoint steps (DO_REPOSITION)? | Comm needed |
|---|-----------|--------------|------------------------------|-------------|
| 1 | Leader-follower | position | yes | leader state to followers |
| 2 | Consensus formation | position | yes | neighbours' positions |
| 3 | Rendezvous | position | yes | neighbours' positions |
| 4 | Reconfiguration (Hungarian) | position | yes | central |
| 5 | Task allocation | position | yes | central (5a/5b) or bids (5c) |
| 6 | Voronoi coverage | position | yes | neighbours' positions |
| 7 | Prioritized planning | position, lockstep | yes | central, offline |
| 8 | ORCA | velocity | poorly (needs velocity setpoints) | none (sensing only) |
| 9 | Frontier exploration | position | yes | shared map |

Suggested first pair to compare (syllabus weeks 6-8 asks for at least two): leader-follower (1) vs consensus
formation (2), same square path, same metrics (formation error, min separation, completion time).
