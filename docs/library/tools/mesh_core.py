#!/usr/bin/env python3
"""Mesh-to-CAD core: read an STL, split it into bodies, and plan exact features (stdlib only).

Purpose: the geometry that does not need a CAD kernel, so it is tested in any Python. Splits a
triangle mesh into the bodies the exporter wrote, sorts each into closed solid parts and
zero-thickness sheets, and fits each prismatic or revolved body with true lines, arcs and circles.
The records it writes are what mesh_brep.py builds and inventor_build.py sketches.
Inputs: binary or ASCII STL in mm (any unit works; tolerances below assume mm).
Outputs: Python values; the CLI writes JSON (`inventory`, `plan`).
Exit codes (PASS, FAIL, CANNOT): 0 pass, 1 check failed, 2 could not run.
Dependencies: Python 3.10+ standard library.
Assumptions:
  - STL coordinates are float32, so vertex noise is about 1e-6 of the coordinate size; welding
    uses a 1e-5 grid and body joining a 1e-4 grid, both well above that noise and below any
    real feature of a CAD export in mm.
  - CAD exporters (Autodesk, SolidWorks, KiCad and others seen) write each body's triangles as
    one contiguous run. Segmentation starts from those runs and joins open runs that share
    boundary edges, so touching bodies stay separate even where their faces coincide.
  - Tessellated curves are chords: mesh vertices lie on the true surface, chord midpoints do not.
    Arcs are fitted through vertices, never through section points between vertices, where it
    matters (revolve profiles are refitted to vertices).
Origin: ported from a one-off conversion of a populated circuit board (155k triangles, 236 bodies)
to STEP and Inventor; generalised (body names, colours and repairs are inputs, not code).
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from collections import Counter, defaultdict

PASS, FAIL, CANNOT = 0, 1, 2

AX = {"x": 0, "y": 1, "z": 2}
# in-plane (u, v) axes per extrusion axis, right-handed with the extrusion axis as normal
UV = {"z": (0, 1), "x": (1, 2), "y": (2, 0)}
WELD = 1e-5  # mm, vertex weld grid
JOIN = 1e-4  # mm, grid for matching boundary edges between triangle runs
GRID = 1e-4  # snap fitted values to this grid when within SNAP_TOL (design values are round)
SNAP_TOL = 6e-6
COLLINEAR_TOL = 2e-5  # mm, point-to-chord distance below which a vertex is dropped
ARC_TOL = 1.5e-4  # mm, max radial residual for an arc run
MAX_TURN = math.radians(12)
ZERO_VOLUME = 1e-9  # mm3; a closed part below this is a double-sided sheet, not a solid


class CannotRun(Exception):
    """Bad argument or unreadable input; the CLI exits 2."""


# ---------------------------------------------------------------- small vector helpers
def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    return math.sqrt(dot(a, a))


def snap(x: float) -> float:
    s = round(x / GRID) * GRID
    return s if abs(s - x) < SNAP_TOL else x


def snap2(p):
    return (snap(p[0]), snap(p[1]))


# ---------------------------------------------------------------- STL
def read_stl(path: str) -> list[tuple]:
    """Triangles as ((x,y,z),(x,y,z),(x,y,z)). Binary when the size matches the header count."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError as e:
        raise CannotRun(f"cannot read {path}: {e}") from e
    if len(data) >= 84:
        n = struct.unpack_from("<I", data, 80)[0]
        if len(data) == 84 + 50 * n:
            tris = []
            for k in range(n):
                v = struct.unpack_from("<12f", data, 84 + 50 * k)
                tris.append(((v[3], v[4], v[5]), (v[6], v[7], v[8]), (v[9], v[10], v[11])))
            return tris
    text = data.decode("ascii", errors="replace")
    if not text.lstrip().lower().startswith("solid"):
        raise CannotRun(f"{path}: neither a binary STL (size mismatch) nor an ASCII STL")
    pts = []
    for line in text.splitlines():
        w = line.split()
        if w and w[0] == "vertex":
            pts.append((float(w[1]), float(w[2]), float(w[3])))
    if len(pts) % 3:
        raise CannotRun(f"{path}: ASCII STL vertex count {len(pts)} is not a multiple of 3")
    return [tuple(pts[k : k + 3]) for k in range(0, len(pts), 3)]


def write_stl(path: str, tris) -> None:
    """Binary STL (used by tests and for exporting a body)."""
    with open(path, "wb") as fh:
        fh.write(b"mesh_core".ljust(80, b" "))
        fh.write(struct.pack("<I", len(tris)))
        for t in tris:
            n = cross(sub(t[1], t[0]), sub(t[2], t[0]))
            ln = norm(n) or 1.0
            fh.write(struct.pack("<12fH", n[0] / ln, n[1] / ln, n[2] / ln, *t[0], *t[1], *t[2], 0))


# ---------------------------------------------------------------- welded mesh
def _key(p, grid):
    return (round(p[0] / grid), round(p[1] / grid), round(p[2] / grid))


class Mesh:
    """Welded triangle mesh: vertices (tuples) and faces (vertex index triples)."""

    def __init__(self, tris, grid: float = WELD):
        index: dict = {}
        self.vertices: list[tuple] = []
        self.faces: list[tuple[int, int, int]] = []
        for t in tris:
            ids = []
            for p in t:
                k = _key(p, grid)
                if k not in index:
                    index[k] = len(self.vertices)
                    self.vertices.append(tuple(float(c) for c in p))
                ids.append(index[k])
            if len(set(ids)) == 3:
                self.faces.append((ids[0], ids[1], ids[2]))

    def triangles(self) -> list[tuple]:
        v = self.vertices
        return [(v[a], v[b], v[c]) for a, b, c in self.faces]

    def edge_counts(self) -> Counter:
        c: Counter = Counter()
        for a, b, cc in self.faces:
            for e in ((a, b), (b, cc), (cc, a)):
                c[(min(e), max(e))] += 1
        return c

    def is_watertight(self) -> bool:
        c = self.edge_counts()
        return bool(c) and all(n == 2 for n in c.values())

    def volume(self) -> float:
        v = self.vertices
        return sum(dot(v[a], cross(v[b], v[c])) for a, b, c in self.faces) / 6.0

    def area(self) -> float:
        v = self.vertices
        return sum(norm(cross(sub(v[b], v[a]), sub(v[c], v[a]))) for a, b, c in self.faces) / 2.0

    def bounds(self):
        xs = list(zip(*self.vertices))
        return tuple(min(c) for c in xs), tuple(max(c) for c in xs)

    def normal(self, f) -> tuple:
        a, b, c = (self.vertices[i] for i in self.faces[f])
        n = cross(sub(b, a), sub(c, a))
        ln = norm(n)
        return (0.0, 0.0, 0.0) if ln == 0 else (n[0] / ln, n[1] / ln, n[2] / ln)

    def components(self) -> list[list[tuple]]:
        """Connected parts through edges shared by exactly two faces (as trimesh's split): twin
        triangles of a double-sided sheet meet at edges used four times, so each twin pair is its own
        part and is recognised as zero volume."""
        by_edge = defaultdict(list)
        for f, (a, b, c) in enumerate(self.faces):
            for e in ((a, b), (b, c), (c, a)):
                by_edge[(min(e), max(e))].append(f)
        parent = list(range(len(self.faces)))

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for fs in by_edge.values():
            if len(fs) == 2:
                parent[find(fs[0])] = find(fs[1])
        groups = defaultdict(list)
        for f in range(len(self.faces)):
            groups[find(f)].append(f)
        v = self.vertices
        return [[(v[self.faces[f][0]], v[self.faces[f][1]], v[self.faces[f][2]]) for f in g] for g in groups.values()]


# ---------------------------------------------------------------- bodies
def segment_bodies(tris, mode: str = "order") -> list[list[int]]:
    """Triangle index groups, one per source body.

    mode "order" (default, for CAD exports): contiguous runs of triangles that share vertices,
    cut where the run is already a closed shell, then open runs joined where they share boundary
    edges (a body split across runs). Touching bodies stay apart even where faces coincide.
    mode "connectivity" (for exporters that interleave bodies): parts connected through edges
    used by exactly two triangles. Coincident faces of touching bodies can split a body here, so
    check the inventory: every solid body should be closed."""
    if mode == "connectivity":
        return _segment_connectivity(tris)
    if mode != "order":
        raise CannotRun(f"unknown segmentation mode {mode!r}")
    keys = [[_key(p, JOIN) for p in t] for t in tris]
    runs = []
    cur: set = set()
    edges: Counter = Counter()
    open_edges = 0
    start = 0
    for i, ks in enumerate(keys):
        s = set(ks)
        # a new run starts when the triangle touches nothing so far, or when the run so far is
        # already a closed shell (a touching body can share vertices with the previous one)
        if i > start and (not (s & cur) or open_edges == 0):
            runs.append((start, i))
            cur = set()
            edges = Counter()
            open_edges = 0
            start = i
        cur |= s
        a, b, c = ks
        for e in ((a, b), (b, c), (c, a)):
            e = (min(e), max(e))
            n = edges[e]
            open_edges += 1 if n == 0 else -1 if n == 1 else 0
            edges[e] = n + 1
    if tris:
        runs.append((start, len(tris)))

    def boundary(lo, hi):
        c: Counter = Counter()
        for i in range(lo, hi):
            a, b, cc = keys[i]
            for e in ((a, b), (b, cc), (cc, a)):
                c[(min(e), max(e))] += 1
        return {e for e, n in c.items() if n == 1}

    parent = list(range(len(runs)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    owner = defaultdict(list)
    for k, (lo, hi) in enumerate(runs):
        for e in boundary(lo, hi):
            owner[e].append(k)
    for ks in owner.values():
        for k in ks[1:]:
            parent[find(k)] = find(ks[0])
    groups = defaultdict(list)
    for k in range(len(runs)):
        groups[find(k)].append(k)
    out = []
    for g in sorted(groups.values()):
        idx = []
        for k in sorted(g):
            idx.extend(range(*runs[k]))
        out.append(idx)
    return out


def _segment_connectivity(tris) -> list[list[int]]:
    keys = [[_key(p, JOIN) for p in t] for t in tris]
    by_edge = defaultdict(list)
    for i, (a, b, c) in enumerate(keys):
        if len({a, b, c}) < 3:
            continue
        for e in ((a, b), (b, c), (c, a)):
            by_edge[(min(e), max(e))].append(i)
    parent = list(range(len(tris)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for fs in by_edge.values():
        if len(fs) == 2:
            parent[find(fs[0])] = find(fs[1])
    groups = defaultdict(list)
    for i in range(len(tris)):
        groups[find(i)].append(i)
    return sorted(groups.values())


def dedup_twins(tris) -> list[tuple]:
    """Drop triangles whose vertex set repeats an earlier one (the back side of a double-sided sheet)."""
    seen = set()
    out = []
    for t in tris:
        k = tuple(sorted(_key(p, WELD) for p in t))
        if k in seen:
            continue
        seen.add(k)
        out.append(t)
    return out


def split_parts(tris):
    """(solid_parts, sheet_tris): closed parts with volume, and every other triangle (twins removed).
    A part with no boundary edge counts as closed even where a shell touches itself along an edge
    (edges used four times); mesh_brep repairs the face that this pinch makes invalid."""
    solids, rest = [], []
    for part in Mesh(tris).components():
        m = Mesh(part)
        if all(n >= 2 for n in m.edge_counts().values()) and abs(m.volume()) > ZERO_VOLUME:
            solids.append(part)
        else:
            rest.extend(part)
    return solids, dedup_twins(rest)


def axis_class(m: Mesh, tol: float = 1e-4) -> str:
    """Axes whose direction every face normal is parallel or perpendicular to ('' if none)."""
    out = ""
    ns = [m.normal(f) for f in range(len(m.faces))]
    for name, k in AX.items():
        if all(abs(n[k]) > 1 - tol or abs(n[k]) < tol for n in ns):
            out += name
    return out


def inventory(tris) -> list[dict]:
    rows = []
    for i, idx in enumerate(segment_bodies(tris)):
        part = [tris[k] for k in idx]
        m = Mesh(part)
        lo, hi = m.bounds()
        closed = m.is_watertight()
        vol = m.volume() if closed else None
        solids, sheets = split_parts(part)
        rows.append(
            dict(
                id=i,
                triangles=len(idx),
                closed=closed,
                volume=vol,
                area=m.area(),
                bmin=list(lo),
                bmax=list(hi),
                axes=axis_class(m),
                solid_parts=len(solids),
                sheet_triangles=len(sheets),
                kind=("solid" if closed and vol is not None and abs(vol) > ZERO_VOLUME else "sheet" if not solids else "mixed"),
            )
        )
    return rows


# ---------------------------------------------------------------- distances
def closest_on_triangle(p, a, b, c):
    """Closest point to p on triangle abc (Ericson, Real-Time Collision Detection, 5.1.5)."""
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return a
    bp = sub(p, b)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return b
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        t = d1 / (d1 - d3)
        return (a[0] + t * ab[0], a[1] + t * ab[1], a[2] + t * ab[2])
    cp = sub(p, c)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return c
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        t = d2 / (d2 - d6)
        return (a[0] + t * ac[0], a[1] + t * ac[1], a[2] + t * ac[2])
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        t = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return (b[0] + t * (c[0] - b[0]), b[1] + t * (c[1] - b[1]), b[2] + t * (c[2] - b[2]))
    den = va + vb + vc
    if den == 0:
        return a
    v, w = vb / den, vc / den
    return (a[0] + ab[0] * v + ac[0] * w, a[1] + ab[1] * v + ac[1] * w, a[2] + ab[2] * v + ac[2] * w)


class TriIndex:
    """Uniform-grid index over triangles for exact nearest-surface distance queries."""

    def __init__(self, tris):
        self.tris = [tuple(tuple(float(c) for c in p) for p in t) for t in tris]
        if not self.tris:
            raise ValueError("no triangles to index")
        lo = [min(p[k] for t in self.tris for p in t) for k in range(3)]
        hi = [max(p[k] for t in self.tris for p in t) for k in range(3)]
        diag = math.sqrt(sum((hi[k] - lo[k]) ** 2 for k in range(3))) or 1.0
        self.h = max(diag / max(len(self.tris) ** (1 / 3), 1.0), 1e-9)
        self.cells: dict = defaultdict(list)
        for i, t in enumerate(self.tris):
            a = [math.floor(min(p[k] for p in t) / self.h) for k in range(3)]
            b = [math.floor(max(p[k] for p in t) / self.h) for k in range(3)]
            for x in range(a[0], b[0] + 1):
                for y in range(a[1], b[1] + 1):
                    for z in range(a[2], b[2] + 1):
                        self.cells[(x, y, z)].append(i)
        self.lo, self.hi = lo, hi

    def distance(self, p) -> float:
        c = [math.floor(p[k] / self.h) for k in range(3)]
        best = math.inf
        seen: set = set()
        r = 0
        rmax = int(math.ceil(max(abs(p[k] - self.lo[k]) + abs(p[k] - self.hi[k]) for k in range(3)) / self.h)) + 1
        while r <= rmax:
            for x in range(c[0] - r, c[0] + r + 1):
                for y in range(c[1] - r, c[1] + r + 1):
                    for z in range(c[2] - r, c[2] + r + 1):
                        if max(abs(x - c[0]), abs(y - c[1]), abs(z - c[2])) != r:
                            continue
                        for i in self.cells.get((x, y, z), ()):
                            if i in seen:
                                continue
                            seen.add(i)
                            q = closest_on_triangle(p, *self.tris[i])
                            d = norm(sub(p, q))
                            if d < best:
                                best = d
            # every triangle closer than r * h has been seen once ring r is done
            if best <= r * self.h:
                return best
            r += 1
        return best


def sample_points(tris) -> list[tuple]:
    """Deterministic surface samples: vertices, edge midpoints and centroids of every triangle."""
    out = []
    for a, b, c in tris:
        out += [a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)]
        out.append(((a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3))
    return out


# ---------------------------------------------------------------- holes
def boundary_loops(m: Mesh) -> list[list[int]]:
    """Boundary loops as vertex index lists, ordered so a cap face following the list keeps the
    winding consistent with the mesh. Loops that pass a vertex twice (pinched) are not returned."""
    directed = set()
    for a, b, c in m.faces:
        directed |= {(a, b), (b, c), (c, a)}
    cnt = m.edge_counts()
    nxt: dict = {}
    pinched = set()
    for a, b in directed:
        if cnt[(min(a, b), max(a, b))] == 1:
            # the cap runs the boundary edge backwards: b -> a
            if b in nxt:
                pinched.add(b)
            nxt[b] = a
    loops, seen = [], set()
    for s in list(nxt):
        if s in seen:
            continue
        loop, v = [], s
        while v not in seen and v in nxt:
            seen.add(v)
            loop.append(v)
            v = nxt[v]
        if v == s and len(loop) >= 3 and not (set(loop) & pinched):
            loops.append(loop)
    return loops


def plane_fit(pts):
    """(centroid, unit normal, max distance) of the best plane through pts (power iteration on the
    covariance for the smallest eigenvector)."""
    n = len(pts)
    c = tuple(sum(p[k] for p in pts) / n for k in range(3))
    # Newell normal is robust for a closed polygon loop
    nx = ny = nz = 0.0
    for a, b in zip(pts, pts[1:] + pts[:1]):
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    nn = (nx, ny, nz)
    ln = norm(nn)
    if ln == 0:
        return c, (0.0, 0.0, 1.0), float("inf")
    nn = (nx / ln, ny / ln, nz / ln)
    dmax = max(abs(dot(sub(p, c), nn)) for p in pts)
    return c, nn, dmax


def zip_cracks(tris, tol: float = 1e-4, max_rounds: int = 20):
    """Close T-junction cracks: where a boundary vertex lies on a boundary edge (within tol, strictly
    between its ends), split the triangle owning that edge at the vertex. Exporters leave such
    zero-area slits where a face was tessellated against a finer neighbour. Returns (tris, splits)."""
    m = Mesh(tris)
    V = m.vertices
    faces = list(m.faces)
    splits = 0
    # first merge boundary vertices that lie within tol of each other: splitting at a vertex next
    # to another leaves a sliver edge shared by four faces, which no shell orientation survives
    cnt0: Counter = Counter()
    for a, b, c in faces:
        for e in ((a, b), (b, c), (c, a)):
            cnt0[(min(e), max(e))] += 1
    bv = sorted({v for e, n in cnt0.items() if n == 1 for v in e})
    rep = {v: v for v in bv}
    for i, a in enumerate(bv):
        for b in bv[i + 1 :]:
            if rep[b] == b and rep[a] == a and norm(sub(V[a], V[b])) < tol:
                rep[b] = a
                splits += 1
    if any(rep[v] != v for v in bv):
        faces = [tuple(rep.get(x, x) for x in f) for f in faces]
        faces = [f for f in faces if len(set(f)) == 3]
    for _ in range(max_rounds):
        cnt: Counter = Counter()
        for a, b, c in faces:
            for e in ((a, b), (b, c), (c, a)):
                cnt[(min(e), max(e))] += 1
        bedges = [e for e, n in cnt.items() if n == 1]
        if not bedges:
            break
        bverts = {v for e in bedges for v in e}
        owner = {}
        for f, (a, b, c) in enumerate(faces):
            for e, opp in (((a, b), c), ((b, c), a), ((c, a), b)):
                key = (min(e), max(e))
                if cnt[key] == 1:
                    owner[key] = (f, e, opp)
        done = set()
        new_faces = []
        changed = False
        for key in bedges:
            f, (a, b), c = owner[key]
            if f in done:
                continue
            ab = sub(V[b], V[a])
            L2 = dot(ab, ab)
            if L2 == 0:
                continue
            best = None
            for v in bverts:
                if v in (a, b, c):
                    continue
                t = dot(sub(V[v], V[a]), ab) / L2
                if 1e-9 < t < 1 - 1e-9:
                    q = (V[a][0] + t * ab[0], V[a][1] + t * ab[1], V[a][2] + t * ab[2])
                    d = norm(sub(V[v], q))
                    if d < tol and (best is None or t < best[0]):
                        best = (t, v)
            if best is None:
                continue
            v = best[1]
            done.add(f)
            new_faces += [(a, v, c), (v, b, c)]
            splits += 1
            changed = True
        if not changed:
            break
        faces = [fc for k, fc in enumerate(faces) if k not in done] + new_faces
    return [(V[a], V[b], V[c]) for a, b, c in faces], splits


def fill_planar_holes(tris, max_area: float, plane_tol: float = 1e-6):
    """Close boundary loops that are planar (within plane_tol) and enclose at most max_area with
    triangulated caps, oriented to match the mesh. Returns (new_tris, filled_loop_count). Meant for
    exporter cracks (a slit a fraction of a micron wide), not for missing faces."""
    m = Mesh(tris)
    added = []
    filled = 0
    for loop in boundary_loops(m):
        pts = [m.vertices[i] for i in loop]
        c, n, dmax = plane_fit(pts)
        if dmax > plane_tol:
            continue
        u, v = _plane_basis(n)
        poly = [(dot(sub(p, c), u), dot(sub(p, c), v)) for p in pts]
        if abs(polygon_area(poly)) > max_area:
            continue
        try:
            tri_ids = triangulate(poly, [])
        except ValueError:
            continue
        ccw = polygon_area(poly) > 0
        for a, b, cc in tri_ids:
            # the loop order is the cap's winding; triangulate returns CCW in (u, v)
            added.append((pts[a], pts[b], pts[cc]) if ccw else (pts[a], pts[cc], pts[b]))
        filled += 1
    return list(tris) + added, filled


def _plane_basis(n):
    a = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
    u = cross(n, a)
    lu = norm(u)
    u = (u[0] / lu, u[1] / lu, u[2] / lu)
    return u, cross(n, u)


# ---------------------------------------------------------------- 2D polygons
def polygon_area(P) -> float:
    return 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(P, P[1:] + P[:1]))


def _orient(a, b, c) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def point_in_polygon(p, P, edge_tol: float = 1e-7) -> bool:
    """Even-odd test; points within edge_tol of an edge count as inside."""
    inside = False
    n = len(P)
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        ab = (b[0] - a[0], b[1] - a[1])
        L2 = ab[0] ** 2 + ab[1] ** 2
        if L2 > 0:
            t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / L2))
            if math.hypot(p[0] - a[0] - t * ab[0], p[1] - a[1] - t * ab[1]) < edge_tol:
                return True
        if (a[1] > p[1]) != (b[1] > p[1]):
            x = a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if x > p[0]:
                inside = not inside
    return inside


def nest(loops) -> list[tuple[int, list[int]]]:
    """Even-odd nesting of closed loops -> [(outer index, [inner indices])]."""
    areas = [abs(polygon_area(L)) for L in loops]
    order = sorted(range(len(loops)), key=lambda k: -areas[k])

    def inside(a, b):
        hits = sum(point_in_polygon(p, loops[b]) for p in loops[a])
        return hits * 2 > len(loops[a])

    depth, parent = {}, {}
    for a in order:
        d, par = 0, None
        for b in order:
            if b == a or areas[b] <= areas[a]:
                continue
            if inside(a, b):
                d += 1
                if par is None or areas[b] < areas[par]:
                    par = b
        depth[a], parent[a] = d, par
    return [(a, [b for b in order if parent[b] == a and depth[b] == depth[a] + 1]) for a in order if depth[a] % 2 == 0]


def triangulate(outer, holes) -> list[tuple[int, int, int]]:
    """Ear clipping with hole bridging. outer and holes are lists of (x, y); returns index triples
    into outer + holes concatenated, each counter-clockwise. Holes may touch the outer boundary or
    be slits (two vertices). Raises ValueError when no ear can be found (self-intersecting input)."""
    pts = list(outer) + [p for h in holes for p in h]
    ring = list(range(len(outer)))
    if polygon_area([pts[i] for i in ring]) < 0:
        ring.reverse()
    off = len(outer)
    hole_rings = []
    for h in holes:
        r = list(range(off, off + len(h)))
        off += len(h)
        if len(h) >= 3 and polygon_area([pts[i] for i in r]) > 0:
            r.reverse()
        hole_rings.append(r)
    for r in sorted(hole_rings, key=lambda r: -max(pts[i][0] for i in r)):
        ring = _bridge(pts, ring, r)
    return _earclip(pts, ring)


def _bridge(pts, ring, hole):
    """Join a hole ring into the outer ring at a mutually visible vertex pair (Eberly)."""
    # a hole vertex coincident with a ring vertex (a hole touching the boundary): splice there with
    # no bridge edge; the ring then passes that point twice (weakly simple)
    where = {(round(pts[i][0], 12), round(pts[i][1], 12)): k for k, i in enumerate(ring)}
    for h, j in enumerate(hole):
        k = where.get((round(pts[j][0], 12), round(pts[j][1], 12)))
        if k is not None:
            seq = hole[h:] + hole[:h]
            return ring[: k + 1] + seq[1:] + [seq[0]] + ring[k + 1 :]
    m = max(range(len(hole)), key=lambda k: (pts[hole[k]][0], pts[hole[k]][1]))
    M = pts[hole[m]]
    hole_seq = hole[m:] + hole[:m]
    best, best_x, best_k = None, math.inf, None
    n = len(ring)
    for k in range(n):
        a, b = pts[ring[k]], pts[ring[(k + 1) % n]]
        if (a[1] - M[1]) * (b[1] - M[1]) > 0 or a[1] == b[1]:
            continue
        x = a[0] + (M[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
        if M[0] - 1e-12 <= x < best_x:
            best_x, best_k = x, k
    if best_k is None:
        raise ValueError("hole is not inside the outer ring")
    a_i, b_i = ring[best_k], ring[(best_k + 1) % n]
    cand = a_i if pts[a_i][0] > pts[b_i][0] else b_i
    Ipt = (best_x, M[1])
    P = pts[cand]
    best = cand
    best_ang = math.inf
    for i in ring:
        q = pts[i]
        if i == cand:
            continue
        if _in_tri(q, M, Ipt, P) and q[0] >= M[0]:
            ang = abs(math.atan2(q[1] - M[1], q[0] - M[0]))
            if ang < best_ang:
                best, best_ang = i, ang
    k = ring.index(best)
    return ring[: k + 1] + hole_seq + [hole_seq[0], best] + ring[k + 1 :]


def _in_tri(p, a, b, c, eps=1e-15):
    d1, d2, d3 = _orient(a, b, p), _orient(b, c, p), _orient(c, a, p)
    neg = d1 < -eps or d2 < -eps or d3 < -eps
    pos = d1 > eps or d2 > eps or d3 > eps
    return not (neg and pos)


def _earclip(pts, ring):
    tris = []
    ring = list(ring)
    guard = 0
    while len(ring) > 3:
        n = len(ring)
        cut = False
        for k in range(n):
            ia, ib, ic = ring[k - 1], ring[k], ring[(k + 1) % n]
            a, b, c = pts[ia], pts[ib], pts[ic]
            if a == c:  # spike from a slit or bridge: drop the tip and one copy of its base
                ring.pop(k)
                ring.pop(k - 1 if k > 0 else len(ring) - 1)
                cut = True
                break
            if _orient(a, b, c) <= 1e-18:
                continue
            ok = True
            for j in ring:
                q = pts[j]
                if q == a or q == b or q == c:
                    continue
                if _in_tri(q, a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((ia, ib, ic))
                ring.pop(k)
                cut = True
                break
        if not cut:
            raise ValueError("no ear found: polygon self-intersects")
        guard += 1
        if guard > 100000:
            raise ValueError("triangulation did not converge")
    if len(ring) == 3 and _orient(pts[ring[0]], pts[ring[1]], pts[ring[2]]) > 1e-18:
        tris.append(tuple(ring))
    return tris


# ---------------------------------------------------------------- sections and loop fitting
def section(tris, axis: str, level: float) -> list[list[tuple]]:
    """Loops where the plane (axis coordinate = level) cuts the mesh, in that plane's (u, v).
    Section points are keyed by the welded mesh edge they lie on, so chaining is exact. A vertex
    lying on the plane counts as above it (consistently for every triangle that uses it)."""
    m = Mesh(tris)
    k = AX[axis]
    u, v = UV[axis]
    V = m.vertices
    d = [p[k] - level if abs(p[k] - level) > 1e-12 else 1e-12 for p in V]
    point = {}
    segs = []
    for f in m.faces:
        hits = []
        for i in range(3):
            a, b = f[i], f[(i + 1) % 3]
            if (d[a] > 0) != (d[b] > 0):
                e = (min(a, b), max(a, b))
                if e not in point:
                    s = d[e[0]] / (d[e[0]] - d[e[1]])
                    pa, pb = V[e[0]], V[e[1]]
                    point[e] = (pa[u] + s * (pb[u] - pa[u]), pa[v] + s * (pb[v] - pa[v]))
                hits.append(e)
        if len(hits) == 2:
            segs.append((hits[0], hits[1]))
    return [[point[e] for e in loop] for loop in chain(segs)]


def chain(segs) -> list[list]:
    """Join segments (pairs of hashable keys) into closed loops of keys."""
    adj = defaultdict(list)
    for i, (a, b) in enumerate(segs):
        adj[a].append(i)
        adj[b].append(i)
    used = [False] * len(segs)
    loops = []
    for s in range(len(segs)):
        if used[s]:
            continue
        used[s] = True
        a, cur = segs[s]
        loop = [a]
        while cur != a:
            nxt = [i for i in adj[cur] if not used[i]]
            if not nxt:
                break
            i = nxt[0]
            used[i] = True
            loop.append(cur)
            p, q = segs[i]
            cur = q if p == cur else p
        if cur == a and len(loop) >= 3:
            loops.append(loop)
    return loops


def drop_collinear(P):
    P = list(P)
    changed = True
    while changed and len(P) > 3:
        changed = False
        keep = [True] * len(P)
        n = len(P)
        for i in range(n):
            if not keep[(i - 1) % n]:
                continue
            a, b, c = P[(i - 1) % n], P[i], P[(i + 1) % n]
            ac = (c[0] - a[0], c[1] - a[1])
            L = math.hypot(*ac)
            if L < 1e-12:
                keep[i] = False
                changed = True
                continue
            d = abs(ac[0] * (b[1] - a[1]) - ac[1] * (b[0] - a[0])) / L
            t = ((b[0] - a[0]) * ac[0] + (b[1] - a[1]) * ac[1]) / L**2
            if d < COLLINEAR_TOL and 0 < t < 1:
                keep[i] = False
                changed = True
        P = [p for p, k in zip(P, keep) if k]
    return P


def _solve(A, b):
    """Gaussian elimination with partial pivoting for a small dense system."""
    n = len(b)
    M = [list(A[i]) + [b[i]] for i in range(n)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c]))
        if abs(M[p][c]) < 1e-300:
            raise ValueError("singular system")
        M[c], M[p] = M[p], M[c]
        for r in range(c + 1, n):
            f = M[r][c] / M[c][c]
            for j in range(c, n + 1):
                M[r][j] -= f * M[c][j]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (M[r][n] - sum(M[r][j] * x[j] for j in range(r + 1, n))) / M[r][r]
    return x


def fit_circle(P):
    """Algebraic (Kasa) circle fit -> (centre, radius, max radial residual)."""
    mx = sum(p[0] for p in P) / len(P)
    my = sum(p[1] for p in P) / len(P)
    Q = [(p[0] - mx, p[1] - my) for p in P]
    A = [[0.0] * 3 for _ in range(3)]
    b = [0.0] * 3
    for x, y in Q:
        row = (2 * x, 2 * y, 1.0)
        rhs = x * x + y * y
        for i in range(3):
            b[i] += row[i] * rhs
            for j in range(3):
                A[i][j] += row[i] * row[j]
    try:
        cx, cy, c2 = _solve(A, b)
    except ValueError:
        return (mx, my), math.inf, math.inf
    r = math.sqrt(max(c2 + cx * cx + cy * cy, 0.0))
    res = max(abs(math.hypot(x - cx, y - cy) - r) for x, y in Q)
    return (cx + mx, cy + my), r, res


def turn_angles(P):
    n = len(P)
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        d1 = (b[0] - a[0], b[1] - a[1])
        d2 = (c[0] - b[0], c[1] - b[1])
        out.append(math.atan2(d1[0] * d2[1] - d1[1] * d2[0], d1[0] * d2[0] + d1[1] * d2[1]))
    return out


def _sign(x):
    return (x > 0) - (x < 0)


def fit_loop(P):
    """Closed polyline -> segments ['L', p0, p1] / ['A', p0, pm, p1, c, r] / ['C', c, r]."""
    P = drop_collinear(P)
    n = len(P)
    if n < 3:
        return None
    ta = turn_angles(P)
    # start where no arc run can wrap the start point: the sharpest corner, or with no corner
    # (every turn below MAX_TURN) the start of the longest edge, which is a line where lines exist
    start = max(range(n), key=lambda i: abs(ta[i]))
    if abs(ta[start]) < MAX_TURN:
        start = max(range(n), key=lambda i: math.hypot(P[(i + 1) % n][0] - P[i][0], P[(i + 1) % n][1] - P[i][1]))
    P = P[start:] + P[:start]
    ta = ta[start:] + ta[:start]
    if n >= 8 and all(abs(t) < MAX_TURN for t in ta) and all(_sign(t) == _sign(ta[0]) for t in ta):
        c, r, res = fit_circle(P)
        if res < ARC_TOL:
            return [["C", snap2(c), snap(r)]]
    segs = []
    i = 0
    while i < n:
        best = None
        j = i + 3
        while j <= n:
            Q = [P[t % n] for t in range(i, j + 1)]
            inner = [ta[t % n] for t in range(i + 1, j)]
            if any(abs(t) > MAX_TURN for t in inner) or not all(_sign(t) == _sign(inner[0]) for t in inner):
                break
            c, r, res = fit_circle(Q)
            if res > ARC_TOL:
                break
            # tessellated arcs have near-uniform chords; a long straight edge next to a fillet must
            # not be absorbed into a huge-radius arc
            ch = [math.hypot(Q[k + 1][0] - Q[k][0], Q[k + 1][1] - Q[k][1]) for k in range(len(Q) - 1)]
            if max(ch) > 2.5 * min(ch):
                break
            best = (j, c, r)
            j += 1
        if best is not None:
            j, c, r = best
            c, r = snap2(c), snap(r)
            Q = [P[t % n] for t in range(i, j + 1)]

            def proj(p, c=c, r=r):
                d = math.hypot(p[0] - c[0], p[1] - c[1])
                return (c[0] + r * (p[0] - c[0]) / d, c[1] + r * (p[1] - c[1]) / d)

            segs.append(["A", proj(Q[0]), proj(Q[(j - i) // 2]), proj(Q[-1]), c, r])
            i = j
        else:
            segs.append(["L", P[i % n], P[(i + 1) % n]])
            i += 1
    # shared vertices identical: a line end takes the neighbouring arc end
    for k in range(len(segs)):
        a, b = segs[k], segs[(k + 1) % len(segs)]
        end_a = a[2] if a[0] == "L" else a[3]
        if b[0] == "A":
            pt = b[1]
        elif a[0] == "A":
            pt = end_a
        else:
            pt = snap2(end_a)
        if a[0] == "L":
            a[2] = pt
        else:
            a[3] = pt
        b[1] = pt
    return segs


def loop_area(segs) -> float:
    """Signed area enclosed by fitted segments (circular segments added to the chord polygon)."""
    if segs[0][0] == "C":
        return math.pi * segs[0][2] ** 2
    poly = [s[1] for s in segs]
    area = polygon_area(poly)
    for s in segs:
        if s[0] != "A":
            continue
        p0, pm, p1, r = s[1], s[2], s[3], s[5]
        c = s[4]
        chord = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        theta = 2 * math.asin(max(-1.0, min(1.0, chord / (2 * r))))
        if _orient(p0, p1, pm) * _orient(p0, p1, c) > 0:
            theta = 2 * math.pi - theta  # major arc: the centre is on the bulge side of the chord
        seg_area = 0.5 * r * r * (theta - math.sin(theta))
        # bulge to the right of the travel direction adds area for a CCW loop
        area += seg_area if _orient(p0, p1, pm) < 0 else -seg_area
    return area


# ---------------------------------------------------------------- prism plan
def prism_axes(m: Mesh) -> list[str]:
    return list(axis_class(m))


def cap_levels(m: Mesh, axis: str, tol: float = 1e-4) -> list[float]:
    k = AX[axis]
    lv = set()
    for f in range(len(m.faces)):
        if abs(m.normal(f)[k]) > 1 - tol:
            for i in m.faces[f]:
                lv.add(round(m.vertices[i][k], 5))
    return sorted(snap(x) for x in lv)


def plan_prism(tris, axis: str) -> dict:
    """Stacked-prism record: every slab between consecutive cap levels has a constant section,
    fitted at mid-height. Raises ValueError when a loop cannot be fitted."""
    m = Mesh(tris)
    lv = cap_levels(m, axis)
    slabs = []
    for a, b in zip(lv[:-1], lv[1:]):
        if b - a < 1e-6:
            continue
        loops = section(tris, axis, 0.5 * (a + b))
        if not loops:
            continue
        fitted = [fit_loop(L) for L in loops]
        if any(f is None for f in fitted):
            raise ValueError("degenerate loop")
        for oi, inn in nest(loops):
            slabs.append(dict(z0=a, z1=b, outer=fitted[oi], inner=[fitted[i] for i in inn]))
    if not slabs:
        raise ValueError("no slabs")
    return dict(kind="prism", axis=axis, slabs=slabs)


def prism_volume(rec) -> float:
    return sum(
        (s["z1"] - s["z0"]) * (abs(loop_area(s["outer"])) - sum(abs(loop_area(i)) for i in s["inner"])) for s in rec["slabs"]
    )


def _arcs(rec):
    for s in rec["slabs"]:
        for loop in [s["outer"]] + s["inner"]:
            for seg in loop:
                if seg[0] == "C":
                    yield seg[2], 2 * math.pi, s["z1"] - s["z0"]
                elif seg[0] == "A":
                    p0, pm, p1, c, r = seg[1], seg[2], seg[3], seg[4], seg[5]
                    phi = 2 * math.asin(max(-1.0, min(1.0, math.hypot(p1[0] - p0[0], p1[1] - p0[1]) / (2 * r))))
                    if _orient(p0, p1, pm) * _orient(p0, p1, c) > 0:
                        phi = 2 * math.pi - phi
                    yield r, phi, s["z1"] - s["z0"]


def chord_bounds(rec) -> tuple[float, float]:
    """(max sag, volume bound) of a tessellation whose chords turn at most MAX_TURN, the limit
    fit_loop accepts for an arc: the farthest a fitted arc can lie from the mesh facets, and the
    most volume the chords can cut off (or add, for holes) across all arcs of the plan."""
    sag = vol = 0.0
    t = MAX_TURN
    for r, phi, h in _arcs(rec):
        sag = max(sag, r * (1 - math.cos(t / 2)))
        vol += h * 0.5 * r * r * phi * (1 - math.sin(t) / t)
    return sag, vol


# ---------------------------------------------------------------- revolve plan
def _clip_right(P, x0=0.0):
    """Sutherland-Hodgman clip of a polygon to x >= x0."""
    out = []
    n = len(P)
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        ia, ib = a[0] >= x0, b[0] >= x0
        if ia:
            out.append(a)
        if ia != ib:
            t = (x0 - a[0]) / (b[0] - a[0])
            out.append((x0, a[1] + t * (b[1] - a[1])))
    return out


def _line_fit(pts):
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - cx) ** 2 for p in pts)
    syy = sum((p[1] - cy) ** 2 for p in pts)
    sxy = sum((p[0] - cx) * (p[1] - cy) for p in pts)
    ang = 0.5 * math.atan2(2 * sxy, sxx - syy)
    return (cx, cy), (math.cos(ang), math.sin(ang))


def _golden(f, lo, hi, tol=1e-10):
    g = (math.sqrt(5) - 1) / 2
    a, b = lo, hi
    c, d = b - g * (b - a), a + g * (b - a)
    fc, fd = f(c), f(d)
    while b - a > tol:
        if fc < fd:
            b, d, fd = d, c, fc
            c = b - g * (b - a)
            fc = f(c)
        else:
            a, c, fc = c, d, fd
            d = a + g * (b - a)
            fd = f(d)
    return 0.5 * (a + b)


def refine_profile(segs, RZ, tol: float = 3e-4):
    """Section points of a revolve profile lie between vertices (on chords). Refit each line and arc
    to the mesh vertices in (r, h) that lie on it, constrain fillets tangent to both neighbours, and
    rebuild corners as intersections."""
    RZ = sorted({(round(r, 7), round(h, 7)) for r, h in RZ})
    prims = []
    for s in segs:
        if s[0] == "L":
            p0, p1 = s[1], s[2]
            d = (p1[0] - p0[0], p1[1] - p0[1])
            L = math.hypot(*d)
            if L < 1e-12:
                raise ValueError("zero-length line in the revolve profile")
            u = (d[0] / L, d[1] / L)
            nrm = (-u[1], u[0])
            if abs(p0[0]) < 1e-9 and abs(p1[0]) < 1e-9:
                prims.append(("L", (0.0, 0.0), (0.0, 1.0)))  # the axis itself
                continue
            sel = [
                q
                for q in RZ
                if abs((q[0] - p0[0]) * nrm[0] + (q[1] - p0[1]) * nrm[1]) < tol
                and -tol < (q[0] - p0[0]) * u[0] + (q[1] - p0[1]) * u[1] < L + tol
            ]
            if len(sel) >= 2:
                cen, dirn = _line_fit(sel)
                if abs(dirn[0]) < 1e-6:
                    dirn = (0.0, 1.0)
                if abs(dirn[1]) < 1e-6:
                    dirn = (1.0, 0.0)
                prims.append(("L", cen, dirn))
            else:
                prims.append(("L", p0, u))
        else:
            cc, rr = s[4], s[5]
            sel = [q for q in RZ if abs(math.hypot(q[0] - cc[0], q[1] - cc[1]) - rr) < tol]
            a0, am, a1 = (math.atan2(s[k][1] - cc[1], s[k][0] - cc[0]) for k in (1, 2, 3))
            two = 2 * math.pi
            ccw = (am - a0) % two < (a1 - a0) % two

            def within(a, a0=a0, a1=a1, ccw=ccw):
                if ccw:
                    return (a - a0) % two <= (a1 - a0) % two + 1e-3 or (a0 - a) % two < 1e-3
                return (a0 - a) % two <= (a0 - a1) % two + 1e-3 or (a - a0) % two < 1e-3

            sel = [q for q in sel if within(math.atan2(q[1] - cc[1], q[0] - cc[0]))]
            if len(sel) >= 4:
                cc, rr, _ = fit_circle(sel)
            prims.append(("A", cc, rr, s[2]))

    fillet_pts = {}
    for k, p in enumerate(prims):
        if p[0] != "A":
            continue
        la, lb = prims[k - 1], prims[(k + 1) % len(prims)]
        if la[0] != "L" or lb[0] != "L" or abs(la[2][0] * lb[2][0] + la[2][1] * lb[2][1]) > 0.999:
            continue
        c0 = p[1]

        def off_line(ln, c0=c0):
            nr = (-ln[2][1], ln[2][0])
            if (c0[0] - ln[1][0]) * nr[0] + (c0[1] - ln[1][1]) * nr[1] < 0:
                nr = (-nr[0], -nr[1])
            return ln[1], ln[2], nr

        (pa, ua, na), (pb, ub, nb) = off_line(la), off_line(lb)

        def centre(R, pa=pa, ua=ua, na=na, pb=pb, ub=ub, nb=nb):
            rhs = (pb[0] + R * nb[0] - pa[0] - R * na[0], pb[1] + R * nb[1] - pa[1] - R * na[1])
            t = _solve([[ua[0], -ub[0]], [ua[1], -ub[1]]], [rhs[0], rhs[1]])
            return (pa[0] + R * na[0] + t[0] * ua[0], pa[1] + R * na[1] + t[0] * ua[1])

        sel = [q for q in RZ if abs(math.hypot(q[0] - p[1][0], q[1] - p[1][1]) - p[2]) < tol]
        if len(sel) < 3:
            continue

        def cost(R, sel=sel, centre=centre):
            c = centre(R)
            return sum((math.hypot(q[0] - c[0], q[1] - c[1]) - R) ** 2 for q in sel)

        R = _golden(cost, 0.5 * p[2], 1.5 * p[2])
        if abs(snap(R) - R) < 2e-5:
            R = snap(R)
        c = centre(R)
        prims[k] = ("A", c, R, p[3])
        fillet_pts[k] = ((c[0] - R * na[0], c[1] - R * na[1]), (c[0] - R * nb[0], c[1] - R * nb[1]))

    def inter(a, b, guess):
        if a[0] == "L" and b[0] == "L":
            try:
                t = _solve([[a[2][0], -b[2][0]], [a[2][1], -b[2][1]]], [b[1][0] - a[1][0], b[1][1] - a[1][1]])
            except ValueError:
                return guess
            return (a[1][0] + t[0] * a[2][0], a[1][1] + t[0] * a[2][1])
        if a[0] == "A" and b[0] == "A":
            (c1, r1), (c2, r2) = (a[1], a[2]), (b[1], b[2])
            d = math.hypot(c2[0] - c1[0], c2[1] - c1[1])
            if d < 1e-12:
                return guess
            x = (d * d + r1 * r1 - r2 * r2) / (2 * d)
            h2 = r1 * r1 - x * x
            if h2 < 0:
                return guess
            e = ((c2[0] - c1[0]) / d, (c2[1] - c1[1]) / d)
            base = (c1[0] + x * e[0], c1[1] + x * e[1])
            h = math.sqrt(h2)
            cand = [(base[0] - s * h * e[1], base[1] + s * h * e[0]) for s in (1, -1)]
        else:
            ln, ar = (a, b) if a[0] == "L" else (b, a)
            p, u = ln[1], ln[2]
            c, r = ar[1], ar[2]
            f = (p[0] - c[0], p[1] - c[1])
            B = 2 * (f[0] * u[0] + f[1] * u[1])
            C = f[0] ** 2 + f[1] ** 2 - r * r
            D = B * B - 4 * C
            if D < 0:
                return guess
            cand = [(p[0] + (-B + s * math.sqrt(D)) / 2 * u[0], p[1] + (-B + s * math.sqrt(D)) / 2 * u[1]) for s in (1, -1)]
        return min(cand, key=lambda q: math.hypot(q[0] - guess[0], q[1] - guess[1]))

    n = len(segs)
    corners = []
    for k in range(n):
        guess = segs[k][2] if segs[k][0] == "L" else segs[k][3]
        if k in fillet_pts:
            corners.append(fillet_pts[k][1])
            continue
        if (k + 1) % n in fillet_pts:
            corners.append(fillet_pts[(k + 1) % n][0])
            continue
        q = inter(prims[k], prims[(k + 1) % n], guess)
        if math.hypot(q[0] - guess[0], q[1] - guess[1]) > 2e-3:
            q = guess  # refit disagreed with the section: keep the section point
        corners.append(q)
    out = []
    for k in range(n):
        p0, p1 = corners[k - 1], corners[k]
        p0 = (0.0 if abs(p0[0]) < 1e-9 else p0[0], p0[1])
        p1 = (0.0 if abs(p1[0]) < 1e-9 else p1[0], p1[1])
        if prims[k][0] == "L":
            out.append(["L", p0, p1])
        else:
            c, r, mid = prims[k][1], prims[k][2], prims[k][3]
            dm = math.hypot(mid[0] - c[0], mid[1] - c[1])
            mid = (c[0] + r * (mid[0] - c[0]) / dm, c[1] + r * (mid[1] - c[1]) / dm)
            out.append(["A", p0, mid, p1, c, r])
    return out


def plan_revolve(tris, axis: str) -> dict:
    """Full-revolve record about an axis parallel to x, y or z: the axis position comes from a
    circle fit to the outermost-radius vertices (they lie on the true rim); the profile is the
    section through the axis, clipped to r >= 0 and refitted to the vertices."""
    m = Mesh(tris)
    k = AX[axis]
    u, v = UV[axis]
    lo, hi = m.bounds()
    c0 = ((lo[u] + hi[u]) / 2, (lo[v] + hi[v]) / 2)
    rv = [math.hypot(p[u] - c0[0], p[v] - c0[1]) for p in m.vertices]
    rmax = max(rv)
    rim = [(p[u], p[v]) for p, r in zip(m.vertices, rv) if r > rmax - 1e-4]
    if len(rim) < 3:
        raise ValueError("no rim")
    c, _, _ = fit_circle(rim)
    # section through the axis: plane v = c[1]; profile coordinates (r, h) = (p_u - c_u, p_k)
    vplane = {0: "x", 1: "y", 2: "z"}[v]
    loops = section(tris, vplane, c[1])
    if not loops:
        raise ValueError("no section through the axis")
    # section() returns (u', v') of the plane's own UV; rebuild (r, h) from 3D order
    pu, pv = UV[vplane]

    def rh(q):
        p = [0.0, 0.0, 0.0]
        p[pu], p[pv] = q
        return (p[u] - c[0], p[k])

    loops = [[rh(q) for q in L] for L in loops]
    right = [L for L in loops if min(q[0] for q in L) >= -1e-6]
    crossing = [L for L in loops if min(q[0] for q in L) < -1e-6 < max(q[0] for q in L)]
    if crossing and not right:
        outer = max(crossing, key=lambda L: abs(polygon_area(L)))
        ring = _clip_right(outer)
        others = [L for L in crossing if L is not outer]
        if others:
            raise ValueError("revolve profile with holes is not supported")
    elif len(right) == 1 and not crossing:
        ring = right[0]
    else:
        raise ValueError("revolve profile is not a single loop")
    segs = fit_loop(ring)
    if segs is None or segs[0][0] == "C":
        raise ValueError("revolve profile did not fit")
    RZ = [(math.hypot(p[u] - c[0], p[v] - c[1]), p[k]) for p in m.vertices]
    segs = refine_profile(segs, RZ)
    # a revolve is only right if every vertex, at whatever angle, lies on the profile
    worst = max(profile_distance(q, segs) for q in RZ)
    if worst > 1e-4:
        raise ValueError(f"vertices off the revolve profile by {worst:.2e}")
    # chord sag around the axis: the widest angular gap between rim vertices
    ang = sorted(math.atan2(p[1] - c[1], p[0] - c[0]) for p in rim)
    gap = max([b - a for a, b in zip(ang, ang[1:])] + [ang[0] + 2 * math.pi - ang[-1]])
    rmax = max(math.hypot(p[0] - c[0], p[1] - c[1]) for p in rim)
    # on a doubly curved face a flat facet sags in both directions: add the two bounds
    sag = rmax * (1 - math.cos(gap / 2)) + max([s[5] * (1 - math.cos(MAX_TURN / 2)) for s in segs if s[0] == "A"] + [0.0])
    return dict(kind="revolve", axis=axis, centre=[c[0], c[1]], profile=segs, max_vertex_offset=worst, chord_limit=sag)


def profile_distance(q, segs) -> float:
    """Distance from a 2D point to the nearest line segment or arc of a fitted loop."""
    best = math.inf
    for s in segs:
        if s[0] == "C":
            best = min(best, abs(math.hypot(q[0] - s[1][0], q[1] - s[1][1]) - s[2]))
            continue
        if s[0] == "L":
            a, b = s[1], s[2]
            ab = (b[0] - a[0], b[1] - a[1])
            L2 = ab[0] ** 2 + ab[1] ** 2
            t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((q[0] - a[0]) * ab[0] + (q[1] - a[1]) * ab[1]) / L2))
            best = min(best, math.hypot(q[0] - a[0] - t * ab[0], q[1] - a[1] - t * ab[1]))
            continue
        p0, pm, p1, c, r = s[1], s[2], s[3], s[4], s[5]
        on_arc = (_orient(p0, p1, q) > 0) == (_orient(p0, p1, pm) > 0)
        if on_arc and math.hypot(q[0] - c[0], q[1] - c[1]) > 0:
            best = min(best, abs(math.hypot(q[0] - c[0], q[1] - c[1]) - r))
        best = min(best, math.hypot(q[0] - p0[0], q[1] - p0[1]), math.hypot(q[0] - p1[0], q[1] - p1[1]))
    return best


def revolve_candidates(m: Mesh, rel: float = 1e-3) -> list[str]:
    """Axes whose two perpendicular extents are equal (a cheap filter before plan_revolve)."""
    lo, hi = m.bounds()
    out = []
    for axis, (u, v) in UV.items():
        eu, ev = hi[u] - lo[u], hi[v] - lo[v]
        if max(eu, ev) > 0 and abs(eu - ev) <= rel * max(eu, ev):
            out.append(axis)
    return out


def plan_body(tris) -> dict | None:
    """The best exact plan for a closed body: stacked prism (fewest slabs first), else revolve.
    Accepted only when the planned volume matches the mesh within 1e-3; None means faceted."""
    m = Mesh(tris)
    if not m.is_watertight():
        return None
    vol = abs(m.volume())
    if vol <= ZERO_VOLUME:
        return None
    for ax in sorted(prism_axes(m), key=lambda a: (len(cap_levels(m, a)), "zxy".index(a))):
        try:
            rec = plan_prism(tris, ax)
        except ValueError:
            continue
        sag, dvol = chord_bounds(rec)
        if abs(prism_volume(rec) - vol) <= 1e-3 * vol + dvol:
            rec["chord_limit"] = sag
            return rec
    if not prism_axes(m):
        for ax in revolve_candidates(m):
            try:
                return plan_revolve(tris, ax)
            except (ValueError, ZeroDivisionError):
                continue
    return None


# ---------------------------------------------------------------- CLI
def _jsonable(o):
    if isinstance(o, tuple):
        return list(o)
    raise TypeError(type(o))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sp = ap.add_subparsers(dest="cmd", required=True)
    a = sp.add_parser("inventory", help="one JSON row per source body")
    a.add_argument("stl")
    a.add_argument("--out", required=True)
    b = sp.add_parser("plan", help="exact feature plan per body (prism, revolve or null = faceted)")
    b.add_argument("stl")
    b.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    try:
        tris = read_stl(args.stl)
    except CannotRun as e:
        print(f"CANNOT: {e}", file=sys.stderr)
        return CANNOT
    if args.cmd == "inventory":
        rows = inventory(tris)
        with open(args.out, "w") as fh:
            json.dump(rows, fh, indent=1, default=_jsonable)
        print(f"bodies {len(rows)}; " + ", ".join(f"{k} {v}" for k, v in Counter(r["kind"] for r in rows).items()))
        return PASS
    plans = []
    for i, idx in enumerate(segment_bodies(tris)):
        solids, _ = split_parts([tris[k] for k in idx])
        plans.append(dict(id=i, plan=plan_body(solids[0]) if len(solids) == 1 else None))
    with open(args.out, "w") as fh:
        json.dump(plans, fh, default=_jsonable)
    print(f"bodies {len(plans)}; " + ", ".join(f"{k} {v}" for k, v in Counter((p["plan"] or {}).get("kind", "faceted") for p in plans).items()))
    return PASS


if __name__ == "__main__":
    sys.exit(main())
