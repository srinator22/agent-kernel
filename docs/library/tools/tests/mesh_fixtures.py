"""Synthetic meshes for the mesh-to-CAD tests: exact shapes whose true dimensions are known.

Every generator returns triangles ((x,y,z),(x,y,z),(x,y,z)) wound outward. Curves are tessellated
with vertices on the true curve, as a CAD exporter does, so fitted radii can be checked against
the design value. `roundtrip` writes and reads a binary STL to add the float32 noise of a real file.
"""

from __future__ import annotations

import math
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import mesh_core as mc  # noqa: E402


def rounded_rect(w, h, r, n_arc=8, x0=0.0, y0=0.0):
    """CCW outline of a w x h rectangle with corner radius r (vertices on the true arcs)."""
    pts = []
    corners = [(x0 + w - r, y0 + r, -90), (x0 + w - r, y0 + h - r, 0), (x0 + r, y0 + h - r, 90), (x0 + r, y0 + r, 180)]
    for cx, cy, a0 in corners:
        for k in range(n_arc + 1):
            a = math.radians(a0 + 90 * k / n_arc)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def circle(cx, cy, r, n=32, cw=False):
    pts = [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)]
    return pts[::-1] if cw else pts


def extrude(outer, holes, z0, z1):
    """Closed prism: outer CCW, holes any orientation."""
    if mc.polygon_area(outer) < 0:
        outer = outer[::-1]
    holes = [h[::-1] if mc.polygon_area(h) > 0 else h for h in holes]
    pts = list(outer) + [p for h in holes for p in h]
    cap = mc.triangulate(outer, holes)
    # face by face in connected order, as CAD exporters write: walls, top cap, bottom cap
    tris = []
    for ring in [outer] + holes:
        for i in range(len(ring)):
            p, q = ring[i], ring[(i + 1) % len(ring)]
            a0, b0, b1, a1 = (*p, z0), (*q, z0), (*q, z1), (*p, z1)
            tris += [(a0, b0, b1), (a0, b1, a1)]
    tris += [((*pts[a], z1), (*pts[b], z1), (*pts[c], z1)) for a, b, c in cap]
    tris += [((*pts[a], z0), (*pts[c], z0), (*pts[b], z0)) for a, b, c in cap]
    return tris


def box(lo, hi):
    return extrude([(lo[0], lo[1]), (hi[0], lo[1]), (hi[0], hi[1]), (lo[0], hi[1])], [], lo[2], hi[2])


def stepped(big, small, z0, z1, z2):
    """One closed body: a big square slab z0..z1 with a small square boss z1..z2 on top."""
    lower = [t for t in extrude(big, [], z0, z1) if not all(abs(p[2] - z1) < 1e-12 for p in t)]
    upper = [t for t in extrude(small, [], z1, z2) if not all(abs(p[2] - z1) < 1e-12 for p in t)]
    pts = list(big) + list(small[::-1])
    ring = [((*pts[a], z1), (*pts[b], z1), (*pts[c], z1)) for a, b, c in mc.triangulate(big, [small[::-1]])]
    return lower + upper + ring


def frustum(base, top, h):
    """Square frustum centred on the origin: not a prism along any axis, not a revolve."""
    b, t = base / 2, top / 2
    lo = [(-b, -b, 0.0), (b, -b, 0.0), (b, b, 0.0), (-b, b, 0.0)]
    hi = [(-t, -t, h), (t, -t, h), (t, t, h), (-t, t, h)]
    tris = [(lo[0], lo[2], lo[1]), (lo[0], lo[3], lo[2]), (hi[0], hi[1], hi[2]), (hi[0], hi[2], hi[3])]
    for i in range(4):
        j = (i + 1) % 4
        tris += [(lo[i], lo[j], hi[j]), (lo[i], hi[j], hi[i])]
    return tris


def revolve(profile, n=48, cx=0.0, cy=0.0):
    """Revolve a closed CCW (r, z) profile about the z axis through (cx, cy). Points with r = 0
    collapse to the axis."""
    tris = []
    m = len(profile)
    for j in range(m):
        (r0, z0), (r1, z1) = profile[j], profile[(j + 1) % m]
        for k in range(n):
            a, b = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n

            def P(r, z, t):
                return (cx + r * math.cos(t), cy + r * math.sin(t), z)

            p00, p01, p10, p11 = P(r0, z0, a), P(r0, z0, b), P(r1, z1, a), P(r1, z1, b)
            # profile CCW in (r, z) -> outward normals with this winding
            if r0 > 0:
                tris.append((p00, p01, p10))
            if r1 > 0:
                tris.append((p01, p11, p10))
    return [t for t in tris if len({tuple(round(c, 9) for c in p) for p in t}) == 3]


def cup_profile(R=1.6, H=0.8, wall=0.1, fillet=0.05, n_f=10):
    """(r, z) profile of a cup: outer radius R, height H, open top of radius R - wall, base
    thickness wall, outer bottom edge filleted with radius `fillet`."""
    pts = [(0.0, 0.0)]
    cx, cz = R - fillet, fillet
    for k in range(n_f + 1):
        a = math.radians(-90 + 90 * k / n_f)
        pts.append((cx + fillet * math.cos(a), cz + fillet * math.sin(a)))
    pts += [(R, H), (R - wall, H), (R - wall, wall), (0.0, wall)]
    return pts


def sheet(lo, hi, z, twins=True):
    a, b, c, d = (lo[0], lo[1], z), (hi[0], lo[1], z), (hi[0], hi[1], z), (lo[0], hi[1], z)
    tris = [(a, b, c), (a, c, d)]
    if twins:
        tris += [(a, c, b), (a, d, c)]
    return tris


def _orient(tri, outward):
    n = mc.cross(mc.sub(tri[1], tri[0]), mc.sub(tri[2], tri[0]))
    return tri if mc.dot(n, outward) > 0 else (tri[0], tri[2], tri[1])


def pinched_pocket():
    """4 x 4 x 1 slab with a 0.5 deep diamond pocket whose corner touches the x = 4 wall, so the
    shell touches itself along the vertical edge x = 4, y = 2, z 0.5..1 (four faces on one edge):
    the defect an exporter left in a connector shell. Volume 16 - 2 * 0.5 = 15."""
    A, B, P, C, D = (0.0, 0.0), (4.0, 0.0), (4.0, 2.0), (4.0, 4.0), (0.0, 4.0)
    dia = [P, (3.0, 3.0), (2.0, 2.0), (3.0, 1.0)]
    outer = [A, B, P, C, D]
    pts = outer + dia
    tris = []
    for a, b, c in mc.triangulate(outer, [dia]):
        tris.append(_orient(((*pts[a], 1.0), (*pts[b], 1.0), (*pts[c], 1.0)), (0, 0, 1)))
    for a, b, c in mc.triangulate(outer, []):
        tris.append(_orient(((*outer[a], 0.0), (*outer[b], 0.0), (*outer[c], 0.0)), (0, 0, -1)))
    for a, b, c in mc.triangulate(dia, []):
        tris.append(_orient(((*dia[a], 0.5), (*dia[b], 0.5), (*dia[c], 0.5)), (0, 0, 1)))
    cx, cy = 3.0, 2.0
    for i in range(4):
        p, q = dia[i], dia[(i + 1) % 4]
        out = (cx - (p[0] + q[0]) / 2, cy - (p[1] + q[1]) / 2, 0.0)
        a0, b0, b1, a1 = (*p, 0.5), (*q, 0.5), (*q, 1.0), (*p, 1.0)
        tris += [_orient((a0, b0, b1), out), _orient((a0, b1, a1), out)]
    P05 = (4.0, 2.0, 0.5)
    for p, q, out in ((A, B, (0, -1, 0)), (C, D, (0, 1, 0)), (D, A, (-1, 0, 0))):
        a0, b0, b1, a1 = (*p, 0.0), (*q, 0.0), (*q, 1.0), (*p, 1.0)
        tris += [_orient((a0, b0, b1), out), _orient((a0, b1, a1), out)]
    # the x = 4 wall is split at P05 so its edges match the pocket corner edge
    B0, B1, P0, P1, C0, C1 = (4.0, 0.0, 0.0), (4.0, 0.0, 1.0), (4.0, 2.0, 0.0), (4.0, 2.0, 1.0), (4.0, 4.0, 0.0), (4.0, 4.0, 1.0)
    for t in ((B0, P0, P05), (B0, P05, P1), (B0, P1, B1), (P0, C0, C1), (P0, C1, P05), (P05, C1, P1)):
        tris.append(_orient(t, (1, 0, 0)))
    return tris


def roundtrip(tris):
    fd, path = tempfile.mkstemp(suffix=".stl")
    os.close(fd)
    try:
        mc.write_stl(path, tris)
        return mc.read_stl(path)
    finally:
        os.remove(path)
