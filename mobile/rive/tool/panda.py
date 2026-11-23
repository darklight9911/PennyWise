"""Convert the panda SVG (assets/panda.svg) into Rive RML shapes.

The SVG is treated as plain data: only <g>, <path>, <ellipse> and <rect>
elements with fill/opacity styles and matrix transforms are read.
Paths are converted to absolute cubic segments, then to
CubicDetachedVertex lists for <PointsPath>.
"""
import math
import re
import xml.etree.ElementTree as ET

NS = "{http://www.w3.org/2000/svg}"
NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
TOK = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def parse_style(s):
    out = {}
    for part in (s or "").split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def parse_matrix(t):
    if not t:
        return (1, 0, 0, 1, 0, 0)
    m = re.match(r"\s*matrix\(([^)]*)\)", t)
    if not m:
        raise ValueError("unsupported transform " + t)
    v = [float(x) for x in NUM.findall(m.group(1))]
    return tuple(v)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def parse_path(d):
    """Return list of subpaths: (start, [(c1, c2, p)], closed)."""
    toks = TOK.findall(d)
    i = 0
    subs = []
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    segs = None
    cmd = None
    last_c2 = None
    last_q = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    while i < len(toks):
        t = toks[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if segs is not None:
                    subs.append((start, segs, True))
                    segs = None
                cur = start
                last_c2 = None
                continue
        elif cmd is None:
            raise ValueError("path data without command")
        rel = cmd.islower()
        C = cmd.upper()
        ox, oy = cur if rel else (0.0, 0.0)
        if C == "M":
            x, y = num() + ox, num() + oy
            if segs is not None:
                subs.append((start, segs, False))
            segs = []
            start = cur = (x, y)
            cmd = "l" if rel else "L"
            last_c2 = None
        elif C in "LHV":
            if C == "L":
                x, y = num() + ox, num() + oy
            elif C == "H":
                x, y = num() + ox, cur[1]
            else:
                x, y = cur[0], num() + oy
            segs.append((cur, (x, y), (x, y)))
            cur = (x, y)
            last_c2 = None
        elif C == "C":
            c1 = (num() + ox, num() + oy)
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            segs.append((c1, c2, p))
            cur = p
            last_c2 = c2
        elif C == "S":
            c1 = (2 * cur[0] - last_c2[0], 2 * cur[1] - last_c2[1]) if last_c2 else cur
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            segs.append((c1, c2, p))
            cur = p
            last_c2 = c2
        elif C == "Q":
            q = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            c1 = (cur[0] + 2 / 3 * (q[0] - cur[0]), cur[1] + 2 / 3 * (q[1] - cur[1]))
            c2 = (p[0] + 2 / 3 * (q[0] - p[0]), p[1] + 2 / 3 * (q[1] - p[1]))
            segs.append((c1, c2, p))
            cur = p
            last_c2 = None
        else:
            raise ValueError("unsupported path command " + cmd)
    if segs:
        subs.append((start, segs, False))
    return subs


def load(svg_path):
    root = ET.parse(svg_path).getroot()
    items = []  # dicts in SVG coordinates, in document order (back to front)

    def walk(el, opacity):
        for ch in el:
            tag = ch.tag.replace(NS, "")
            st = parse_style(ch.get("style"))
            op = opacity * float(st.get("opacity", 1))
            fill = st.get("fill", "#000000")
            if tag == "g":
                walk(ch, op)
            elif tag == "path":
                items.append({"kind": "path", "subs": parse_path(ch.get("d")), "fill": fill, "op": op})
            elif tag == "ellipse":
                m = parse_matrix(ch.get("transform"))
                cx, cy = float(ch.get("cx")), float(ch.get("cy"))
                rx, ry = float(ch.get("rx")), float(ch.get("ry"))
                px, py = apply(m, cx, cy)
                rot = math.atan2(m[1], m[0])
                sx = math.hypot(m[0], m[1])
                items.append({"kind": "ellipse", "x": px, "y": py, "rx": rx * sx, "ry": ry * sx,
                              "rot": rot, "fill": fill, "op": op})
            elif tag == "rect":
                items.append({"kind": "rect", "fill": fill, "op": op})

    walk(root, 1.0)
    return items


def bbox(items):
    xs, ys = [], []
    for it in items:
        if it["kind"] == "path":
            for start, segs, _ in it["subs"]:
                xs.append(start[0]); ys.append(start[1])
                for c1, c2, p in segs:
                    xs.append(p[0]); ys.append(p[1])
        elif it["kind"] == "ellipse":
            r = max(it["rx"], it["ry"])
            xs += [it["x"] - r, it["x"] + r]; ys += [it["y"] - r, it["y"] + r]
    return min(xs), min(ys), max(xs), max(ys)


def color(fill, op):
    h = fill.lstrip("#").upper()
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    a = max(0, min(255, round(op * 255)))
    return "%02X%s" % (a, h)


def f(v):
    s = "%.2f" % v
    return "0" if s in ("-0.00", "0.00") else s.rstrip("0").rstrip(".")


def vertices(start, segs, closed, tx):
    """Turn cubic segments into Rive vertices (local coordinates)."""
    pts = [start] + [s[2] for s in segs]
    outs = [s[0] for s in segs]
    ins = [s[1] for s in segs]
    n = len(segs)
    if closed and n and math.dist(pts[-1], pts[0]) < 0.01:
        # last segment ends on the start point: merge
        verts = []
        for k in range(n):
            p = pts[k]
            vin = ins[k - 1]  # segment k-1 ends at p (k=0 -> last seg)
            vout = outs[k]
            verts.append((p, vin, vout))
    else:
        verts = []
        for k in range(n + 1):
            p = pts[k]
            vin = ins[k - 1] if k > 0 else p
            vout = outs[k] if k < n else p
            verts.append((p, vin, vout))
    out = []
    for p, vin, vout in verts:
        P = tx(p); I = tx(vin); O = tx(vout)
        di = math.dist(P, I); do = math.dist(P, O)
        ri = math.atan2(I[1] - P[1], I[0] - P[0]) if di > 1e-4 else 0.0
        ro = math.atan2(O[1] - P[1], O[0] - P[0]) if do > 1e-4 else 0.0
        out.append((P, ri, di, ro, do))
    return out


def signed_area(vs):
    a = 0
    for k in range(len(vs)):
        x1, y1 = vs[k][0]; x2, y2 = vs[(k + 1) % len(vs)][0]
        a += x1 * y2 - x2 * y1
    return a / 2


class Panda:
    """Emits the panda as RML shapes sized to `height` px, centred on (0,0)."""

    def __init__(self, svg_path):
        items = load(svg_path)
        # drop the square background; keep everything else
        self.items = [it for it in items if it["kind"] != "rect"]
        x0, y0, x1, y1 = bbox(self.items)
        self.cx, self.cy = (x0 + x1) / 2, (y0 + y1) / 2
        self.w, self.h = x1 - x0, y1 - y0

    # Part groups by item index (found by listing the SVG parts' bounding boxes).
    PARTS = {
        "eyes": list(range(79, 85)),
        "head": list(range(53, 79)),
        "body": list(range(46, 53)) + list(range(36, 46)),
        "armR": [22, 8, 23] + list(range(24, 36)),
        "armL": [6, 7] + list(range(10, 22)),
        "back": [5, 9, 1, 2, 3, 4],
        "shadow": [0],
    }
    # pivots in units of panda height, relative to the panda centre
    PIVOTS = {"head": (0, -0.10), "eyes": (0, -0.242), "armL": (-0.06, -0.03), "armR": (0.06, -0.03)}

    def _shapes(self, idx, s, ox, oy, prefix, tint):
        """RML for the given item indices, front first, offset by (-ox,-oy)."""
        tx = lambda p: ((p[0] - self.cx) * s - ox, (p[1] - self.cy) * s - oy)
        out = []
        for k in sorted(idx):
            it = self.items[k]
            fill = it["fill"]
            if tint and fill.upper() in tint:
                fill = tint[fill.upper()]
            col = color(fill, it["op"])
            if it["kind"] == "ellipse":
                X, Y = tx((it["x"], it["y"]))
                out.append(
                    '<Shape x="%s" y="%s" rotation="%s" name="%s e%d">'
                    '<Ellipse width="%s" height="%s" name="P"/>'
                    '<Fill name="F"><SolidColor colorValue="%s" name="C"/></Fill></Shape>'
                    % (f(X), f(Y), f(it["rot"]), prefix, k, f(2 * it["rx"] * s), f(2 * it["ry"] * s), col))
            else:
                paths = []
                for start, segs, closed in it["subs"]:
                    if not segs:
                        continue
                    vs = vertices(start, segs, closed, tx)
                    cw = signed_area(vs) > 0
                    vx = "".join(
                        '<CubicDetachedVertex x="%s" y="%s" inRotation="%s" inDistance="%s" outRotation="%s" outDistance="%s"/>'
                        % (f(P[0]), f(P[1]), "%.4f" % ri, f(di), "%.4f" % ro, f(do))
                        for P, ri, di, ro, do in vs)
                    paths.append('<PointsPath isClosed="true" isClockwise="%s" name="p">%s</PointsPath>'
                                 % ("true" if cw else "false", vx))
                if paths:
                    out.append('<Shape name="%s s%d">%s<Fill name="F"><SolidColor colorValue="%s" name="C"/></Fill></Shape>'
                               % (prefix, k, "".join(paths), col))
        out.reverse()
        return "".join(out)

    def rig(self, height, new_id, prefix="Panda", tint=None, shadow=True, x=0, y=0, extra_front=""):
        """A rigged panda: returns (rml, ids) for root/head/eyes/armL/armR/body/restL/restR.

        armL/armR are the art's raised thumbs-up arms; restL/restR the drawn
        resting arms. Show one pair or the other per pose (opacity).

        The root node sits at (x, y) = the panda centre. Child nodes sit at
        their pivots so rotating them turns the part around the joint.
        """
        s = height / self.h
        ids = {k: new_id() for k in ("root", "head", "eyes", "armL", "armR", "body", "restL", "restR")}

        def pivot_node(part, inner):
            px, py = self.PIVOTS[part]
            px, py = px * height, py * height
            return ('<Node x="%s" y="%s" name="%s %s" id="%s">%s</Node>'
                    % (f(px), f(py), prefix, part, ids[part], inner))

        # eyes live inside the head; both are offset by their own pivot
        hx, hy = self.PIVOTS["head"]
        ex, ey = self.PIVOTS["eyes"]
        eyes_inner = self._shapes(self.PARTS["eyes"], s, ex * height, ey * height, prefix, tint)
        eyes = ('<Node x="%s" y="%s" name="%s eyes" id="%s">%s</Node>'
                % (f((ex - hx) * height), f((ey - hy) * height), prefix, ids["eyes"], eyes_inner))
        head = pivot_node("head", eyes + self._shapes(self.PARTS["head"], s, hx * height, hy * height, prefix, tint))
        armL = pivot_node("armL", self._shapes(self.PARTS["armL"], s, *(v * height for v in self.PIVOTS["armL"]), prefix, tint))
        armR = pivot_node("armR", self._shapes(self.PARTS["armR"], s, *(v * height for v in self.PIVOTS["armR"]), prefix, tint))
        body = '<Node name="%s body" id="%s">%s</Node>' % (prefix, ids["body"], self._shapes(self.PARTS["body"], s, 0, 0, prefix, tint))
        back = self._shapes(self.PARTS["back"], s, 0, 0, prefix, tint)
        rest = (self._rest_arm("R", height, ids["restR"], prefix, tint)
                + self._rest_arm("L", height, ids["restL"], prefix, tint))
        shad = self._shapes(self.PARTS["shadow"], s, 0, 0, prefix, tint) if shadow else ""
        rml = ('<Node x="%s" y="%s" name="%s" id="%s">%s%s%s%s%s%s%s</Node>'
               % (f(x), f(y), prefix, ids["root"], extra_front, head,
                  rest + body, armR, armL, back, shad))
        return rml, ids

    # Resting arms. The art only has raised thumbs-up arms; rotated down they
    # splay like flippers. These are drawn in the same style instead: a short
    # rounded teal arm with the dark outline and a shaded paw, hanging from
    # the shoulder in front of the body. Rotation 0 hangs straight down.
    REST_PIVOT = (0.098, -0.075)   # right shoulder; the left one is mirrored
    REST_SIZE = (0.075, 0.2)       # arm width, length (from the shoulder)

    def _rest_arm(self, side, height, nid, prefix, tint):
        def col(c):
            return color(tint.get(c, c) if tint else c, 1)
        fur, shade, line = col("#777781"), col("#626272"), col("#371B45")
        w, ln = (v * height for v in self.REST_SIZE)
        px, py = self.REST_PIVOT
        px *= -1 if side == "L" else 1
        t = 0.011 * height
        paw = ('<Shape x="0" y="%s" name="%s paw %s"><Ellipse width="%s" height="%s" name="P"/>'
               '<Fill name="F"><SolidColor colorValue="%s" name="C"/></Fill></Shape>'
               % (f(ln - w * 0.85), prefix, side, f(w * 0.72), f(w * 0.5), shade))
        arm = ('<Shape x="0" y="%s" name="%s arm %s"><Rectangle width="%s" height="%s" originX="0.5" originY="0" '
               'cornerRadiusTL="%s" name="P"/><Fill name="F"><SolidColor colorValue="%s" name="C"/></Fill>'
               '<Stroke thickness="%s" cap="round" join="round" name="S"><SolidColor colorValue="%s" name="C"/></Stroke></Shape>'
               % (f(-w / 2), prefix, side, f(w), f(ln), f(w / 2), fur, f(t), line))
        return ('<Node x="%s" y="%s" name="%s rest arm %s" id="%s">%s%s</Node>'
                % (f(px * height), f(py * height), prefix, side, nid, paw, arm))

    def shadow(self, height, prefix="Panda", tint=None):
        """The ground shadow alone, centred like the rig, so it can stay put."""
        return self._shapes(self.PARTS["shadow"], height / self.h, 0, 0, prefix, tint)
