"""Generate mobile/rive/penny/scene.rml: Penny, the pennyWise panda mascot.

    python3 -I mobile/rive/tool/gen_penny.py
    rive mobile/rive/penny --verify

One transparent 400x400 artboard, "Penny", bound to the "Mascot" view model:

    mood  number  0 idle, 1 wave, 2 happy, 3 celebrate, 4 worried,
                  5 thinking, 6 sleeping  (lib/core/widgets/panda_mascot.dart)
    tap   trigger a short giggle; also fired by tapping the panda

The panda art comes from art/panda.svg through panda.py. Effects use the app
palette from PLAN.md section 7b.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import panda as pandalib  # noqa: E402

OUT = os.path.join(HERE, "..", "penny", "scene.rml")
PANDA = pandalib.Panda(os.path.join(HERE, "..", "art", "panda.svg"))

SIZE = 400
PH = 300            # panda height
CX, CY = 200, 214   # panda centre
MOODS = ["idle", "wave", "happy", "celebrate", "worried", "thinking", "sleeping"]

# palette (PLAN.md 7b) plus a coin gold for celebrations
PRIMARY, SECONDARY, OUTLINE = "FF2C706E", "FF729D99", "FFD9D2C5"
GOLD, GOLD_DARK, SWEAT, BLUSH = "FFF2B544", "FFC98A1B", "FF9FD4F0", "66EE7A7C"
# Recolour the art to the app theme: the black fur becomes the secondary
# teal, its shading a deeper teal, the dark outlines and pupils a dark
# teal (close to primary), and the cool-grey shading on white a light teal.
TINT = {
    "#777781": "#729D99",  # fur (ears, arms, legs, eye patches) -> secondary
    "#626272": "#5C8884",  # fur shading
    "#371B45": "#1E4A48",  # outlines, pupils, brows
    "#D3DDEA": "#DCE9E6",  # shading on the white belly and face
    "#A5A5F2": "#D9D2C5",  # ground shadow -> app outline colour
}


def f(v):
    s = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


class Ids:
    n = 100

    def __call__(self):
        Ids.n += 1
        return "0:%d" % Ids.n


new_id = Ids()


# ------------------------------------------------------------------ drawing
def fill(c):
    return '<Fill name="F"><SolidColor colorValue="%s" name="C"/></Fill>' % c


def stroke(c, t):
    return ('<Stroke thickness="%s" cap="round" join="round" name="S"><SolidColor colorValue="%s" name="C"/></Stroke>'
            % (f(t), c))


def ellipse(x, y, w, h, paint, name="Ellipse"):
    return ('<Shape x="%s" y="%s" name="%s"><Ellipse width="%s" height="%s" name="P"/>%s</Shape>'
            % (f(x), f(y), name, f(w), f(h), paint))


def rrect(x, y, w, h, r, paint, name="Rect"):
    return ('<Shape x="%s" y="%s" name="%s"><Rectangle width="%s" height="%s" cornerRadiusTL="%s" name="P"/>%s</Shape>'
            % (f(x), f(y), name, f(w), f(h), f(r), paint))


def star(x, y, r, c, name="Sparkle"):
    return ('<Shape x="%s" y="%s" name="%s"><Star width="%s" height="%s" points="4" innerRadius="0.35" name="P"/>%s</Shape>'
            % (f(x), f(y), name, f(2 * r), f(2 * r), fill(c)))


def heart(x, y, s, c, name="Heart"):
    """A heart from two cubic segments: top dip -> right lobe -> tip -> left lobe."""
    import math

    def v(px, py, ix, iy, ox, oy):
        px, py, ix, iy, ox, oy = (k * s for k in (px, py, ix, iy, ox, oy))
        return ('<CubicDetachedVertex x="%s" y="%s" inRotation="%.4f" inDistance="%s" outRotation="%.4f" outDistance="%s"/>'
                % (f(px), f(py), math.atan2(iy - py, ix - px), f(math.hypot(ix - px, iy - py)),
                   math.atan2(oy - py, ox - px), f(math.hypot(ox - px, oy - py))))
    verts = v(0, -0.18, -0.3, -0.62, 0.3, -0.62) + v(0, 0.5, 0.9, -0.15, -0.9, -0.15)
    return ('<Shape x="%s" y="%s" name="%s"><PointsPath isClosed="true" name="P">%s</PointsPath>%s</Shape>'
            % (f(x), f(y), name, verts, fill(c)))


def zed(x, y, s, c, name="Z"):
    pts = [(-s, -s), (s, -s), (-s, s), (s, s)]
    v = "".join('<StraightVertex x="%s" y="%s"/>' % (f(px), f(py)) for px, py in pts)
    return ('<Shape x="%s" y="%s" name="%s"><PointsPath isClosed="false" name="P">%s</PointsPath>%s</Shape>'
            % (f(x), f(y), name, v, stroke(c, max(2.5, s * 0.35))))


def coin(s):
    return (ellipse(0, 0, s * 0.45, s * 0.45, stroke(GOLD_DARK, s * 0.07), name="Coin mark")
            + ellipse(0, 0, s, s, fill(GOLD) + stroke(GOLD_DARK, s * 0.08), name="Coin face"))


def node(inner, name, nid, x=0, y=0, attrs=""):
    return '<Node x="%s" y="%s" name="%s" id="%s"%s>%s</Node>' % (f(x), f(y), name, nid, attrs, inner)


# ------------------------------------------------------------------ animation
def kf(value, frame, interp):
    if interp == "ease":
        return ('<KeyFrameDouble value="%s" frame="%d" interpolationType="cubic">'
                '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/></KeyFrameDouble>' % (f(value), frame))
    if interp == "out":
        return ('<KeyFrameDouble value="%s" frame="%d" interpolationType="cubic">'
                '<CubicEaseInterpolator x1="0.2" y1="0.9" x2="0.3" y2="1"/></KeyFrameDouble>' % (f(value), frame))
    return '<KeyFrameDouble value="%s" frame="%d" interpolationType="%s"/>' % (f(value), frame, interp)


ANIMS = []


def anim(name, duration, tracks, loop="loop"):
    """tracks: {(object id, property): [(frame, value, interp?)]}"""
    aid = new_id()
    objs = {}
    for (oid, prop), keys in tracks.items():
        objs.setdefault(oid, []).append(
            '<KeyedProperty property="%s">%s</KeyedProperty>'
            % (prop, "".join(kf(k[1], k[0], k[2] if len(k) > 2 else "linear") for k in keys)))
    body = "".join('<KeyedObject objectId="%s">%s</KeyedObject>' % (o, "".join(p)) for o, p in objs.items())
    ANIMS.append('<LinearAnimation loopValue="%s" duration="%d" name="%s" id="%s">%s</LinearAnimation>'
                 % (loop, duration, name, aid, body))
    return aid


# ------------------------------------------------------------------ the scene
VM, VMI, P_MOOD, P_TAP = new_id(), new_id(), new_id(), new_id()
AB, STYLE, SM = new_id(), new_id(), new_id()

body, R = PANDA.rig(PH, new_id, prefix="Penny", tint=TINT, shadow=False, x=0, y=0)
FX = {k: new_id() for k in ("hearts", "sweat", "dots", "zzz", "coins", "sparkles", "blush", "shadow", "bounce")}
COINS = [new_id() for _ in range(3)]
DOTS = [new_id() for _ in range(3)]
ZEDS = [new_id() for _ in range(3)]
HIT = new_id()

hs = PH  # effect sizes scale with the panda
effects = (
    node(heart(-0.2 * hs, 0, 0.11 * hs, "FFE0566A") + heart(0.21 * hs, -0.07 * hs, 0.08 * hs, "FFF08A9A"),
         "Hearts", FX["hearts"], y=-0.45 * hs, attrs=' opacity="0"')
    + node(ellipse(0, 0, 0.045 * hs, 0.07 * hs, fill(SWEAT)), "Sweat", FX["sweat"], x=0.19 * hs, y=-0.36 * hs, attrs=' opacity="0"')
    + node("".join(node(ellipse(0, 0, 0.05 * hs, 0.05 * hs, fill(PRIMARY)), "Dot", d, x=(k - 1) * 0.075 * hs)
                   for k, d in enumerate(DOTS))
           + ellipse(0, 0, 0.3 * hs, 0.13 * hs, fill("FFFBF9F5") + stroke(OUTLINE, 2), name="Bubble")
           + ellipse(-0.13 * hs, 0.1 * hs, 0.05 * hs, 0.05 * hs, fill("FFFBF9F5") + stroke(OUTLINE, 2), name="Bubble tail"),
           "Thought", FX["dots"], x=0.24 * hs, y=-0.5 * hs, attrs=' opacity="0"')
    + node("".join(node(zed(0, 0, (0.02 + 0.008 * k) * hs, SECONDARY), "Zed", z, x=(0.2 + 0.06 * k) * hs, y=-(0.36 + 0.07 * k) * hs)
                   for k, z in enumerate(ZEDS)), "Sleep", FX["zzz"], attrs=' opacity="0"')
)
celebrate = (
    node("".join(node(coin(0.1 * hs), "Coin", c, x=(k - 1) * 0.26 * hs, y=-0.45 * hs) for k, c in enumerate(COINS)),
         "Coins", FX["coins"], attrs=' opacity="0"')
    + node(star(-0.3 * hs, -0.3 * hs, 0.035 * hs, GOLD) + star(0.32 * hs, -0.22 * hs, 0.028 * hs, SECONDARY)
           + star(0.27 * hs, -0.43 * hs, 0.022 * hs, GOLD) + star(-0.26 * hs, -0.48 * hs, 0.025 * hs, SECONDARY),
           "Sparkles", FX["sparkles"], attrs=' opacity="0"')
)
blush = node(ellipse(-0.105 * hs, -0.19 * hs, 0.06 * hs, 0.03 * hs, fill(BLUSH))
             + ellipse(0.105 * hs, -0.19 * hs, 0.06 * hs, 0.03 * hs, fill(BLUSH)), "Blush", FX["blush"], attrs=' opacity="0"')

# Bounce (tap layer) wraps the mood-animated rig, so the two layers never key
# the same property.
penny = node(effects + celebrate + node(blush + body, "Mood", new_id()), "Bounce", FX["bounce"], x=CX, y=CY)
shadow = node(PANDA.shadow(PH, prefix="Penny", tint=TINT), "Shadow", FX["shadow"], x=CX, y=CY)
hit = ('<Shape x="%s" y="%s" name="Tap area" id="%s"><Ellipse width="%s" height="%s" name="P"/>'
       '<Fill name="F"><SolidColor colorValue="00000000" name="C"/></Fill></Shape>' % (f(CX), f(CY - 10), HIT, f(0.62 * PH), f(0.95 * PH)))

# ------------------------------------------------------------------ moods
y0 = 0
# Arms: restL/restR are the drawn resting arms (0 hangs straight down,
# + swings the left one out, - the right one). armL/armR are the art's
# raised thumbs-up arms, shown only for thumbs-up and celebrate. HANG
# is the relaxed outward angle.
HANG = 0.16


def base():
    t = {
        (R["root"], "x"): 0, (R["root"], "y"): y0, (R["root"], "rotation"): 0,
        (R["root"], "scaleX"): 1, (R["root"], "scaleY"): 1,
        (R["head"], "rotation"): 0, (R["eyes"], "scaleX"): 1, (R["eyes"], "scaleY"): 1,
        (R["eyes"], "y"): PANDA.PIVOTS["eyes"][1] * PH - PANDA.PIVOTS["head"][1] * PH, (R["eyes"], "x"): 0,
        (R["armL"], "rotation"): 0, (R["armR"], "rotation"): 0, (R["armL"], "opacity"): 0, (R["armR"], "opacity"): 0,
        (R["restL"], "rotation"): HANG, (R["restR"], "rotation"): -HANG, (R["restL"], "opacity"): 1, (R["restR"], "opacity"): 1,
        (FX["blush"], "opacity"): 0, (FX["shadow"], "scaleX"): 1, (FX["shadow"], "scaleY"): 1,
    }
    for k in ("hearts", "sweat", "dots", "zzz", "coins", "sparkles"):
        t[(FX[k], "opacity")] = 0
    return t


EYE_Y = PANDA.PIVOTS["eyes"][1] * PH - PANDA.PIVOTS["head"][1] * PH


def mood(name, duration, keys, loop="loop"):
    t = {k: [(0, v, "hold")] for k, v in base().items()}
    look = dict(R)
    look.update(FX)
    for (part, prop), ks in keys.items():
        t[(look.get(part, part), prop)] = ks
    return anim(name, duration, t, loop)


E = "ease"
A = {}
A["idle"] = mood("Idle", 180, {
    ("root", "scaleY"): [(0, 1, E), (90, 1.015, E), (180, 1)],
    ("root", "scaleX"): [(0, 1, E), (90, 0.992, E), (180, 1)],
    ("head", "rotation"): [(0, -0.03, E), (90, 0.03, E), (180, -0.03)],
    ("eyes", "scaleY"): [(0, 1, "hold"), (140, 1), (145, 0.1), (150, 1), (180, 1)],
    ("restL", "rotation"): [(0, HANG, E), (90, HANG + 0.05, E), (180, HANG)],
    ("restR", "rotation"): [(0, -HANG, E), (90, -HANG - 0.05, E), (180, -HANG)],
})
A["wave"] = mood("Wave", 60, {
    ("restL", "rotation"): [(0, HANG, "hold")],
    ("restR", "rotation"): [(0, -1.85, E), (15, -2.3, E), (30, -1.85, E), (45, -2.3, E), (60, -1.85)],
    ("head", "rotation"): [(0, 0.06, E), (30, 0.1, E), (60, 0.06)],
    ("root", "rotation"): [(0, 0.02, E), (30, 0.04, E), (60, 0.02)],
    ("eyes", "scaleY"): [(0, 0.85, "hold")],
    ("blush", "opacity"): [(0, 1, "hold")],
})
A["happy"] = mood("Happy", 48, {
    ("root", "y"): [(0, 0, E), (24, -0.035 * PH, E), (48, 0)],
    ("root", "scaleY"): [(0, 0.98, E), (24, 1.02, E), (48, 0.98)],
    ("head", "rotation"): [(0, -0.06, E), (24, 0.06, E), (48, -0.06)],
    ("eyes", "scaleY"): [(0, 0.6, "hold")],
    ("restL", "rotation"): [(0, HANG, E), (24, HANG + 0.12, E), (48, HANG)],
    ("restR", "opacity"): [(0, 0, "hold")], ("armR", "opacity"): [(0, 1, "hold")],
    ("armR", "rotation"): [(0, 0.05, E), (24, -0.08, E), (48, 0.05)],
    ("blush", "opacity"): [(0, 1, "hold")],
    ("hearts", "opacity"): [(0, 0.9, "hold")],
    ("shadow", "scaleX"): [(0, 1, E), (24, 0.92, E), (48, 1)],
})
coin_tracks = {}
for k, c in enumerate(COINS):
    o = k * 10
    coin_tracks[(c, "y")] = [(0, -0.42 * PH), (o, -0.42 * PH, "out"), (o + 30, -0.6 * PH), (60, -0.6 * PH)]
    coin_tracks[(c, "rotation")] = [(0, 0), (60, 6.283 * (1 if k % 2 else -1))]
    coin_tracks[(c, "scaleX")] = [(0, 1, E), (15, 0.2, E), (30, 1, E), (45, 0.2, E), (60, 1)]
A["celebrate"] = mood("Celebrate", 60, dict({
    ("root", "y"): [(0, 0, E), (20, -0.12 * PH, E), (40, 0, E), (60, 0)],
    ("root", "scaleY"): [(0, 0.93, E), (8, 1.05, E), (36, 1.02, E), (44, 0.93, E), (60, 0.93)],
    ("root", "scaleX"): [(0, 1.05, E), (8, 0.97, E), (36, 0.98, E), (44, 1.05, E), (60, 1.05)],
    ("restL", "opacity"): [(0, 0, "hold")], ("restR", "opacity"): [(0, 0, "hold")],
    ("armL", "opacity"): [(0, 1, "hold")], ("armR", "opacity"): [(0, 1, "hold")],
    ("armL", "rotation"): [(0, 0.1, E), (20, -0.3, E), (40, 0.1, E), (60, 0.1)],
    ("armR", "rotation"): [(0, -0.1, E), (20, 0.3, E), (40, -0.1, E), (60, -0.1)],
    ("eyes", "scaleY"): [(0, 0.55, "hold")],
    ("blush", "opacity"): [(0, 1, "hold")],
    ("coins", "opacity"): [(0, 1, "hold")],
    ("sparkles", "opacity"): [(0, 1), (15, 0.3), (30, 1), (45, 0.3), (60, 1)],
    ("shadow", "scaleX"): [(0, 1, E), (20, 0.75, E), (40, 1), (60, 1)],
    ("shadow", "scaleY"): [(0, 1, E), (20, 0.75, E), (40, 1), (60, 1)],
} | coin_tracks))
A["worried"] = mood("Worried", 90, {
    ("root", "x"): [(0, -1.5), (6, 1.5), (12, -1.5), (18, 1.5), (24, 0), (90, 0)],
    ("head", "rotation"): [(0, -0.1, E), (45, -0.14, E), (90, -0.1)],
    ("eyes", "scaleX"): [(0, 1.15, "hold")], ("eyes", "scaleY"): [(0, 1.2, "hold")],
    ("restL", "rotation"): [(0, -0.35, "hold")], ("restR", "rotation"): [(0, 0.35, "hold")],
    ("sweat", "opacity"): [(0, 0), (20, 1), (70, 1), (90, 0)],
})
A["thinking"] = mood("Thinking", 90, dict({
    ("head", "rotation"): [(0, 0.12, E), (45, 0.16, E), (90, 0.12)],
    ("eyes", "y"): [(0, EYE_Y - 0.012 * PH, "hold")],
    ("eyes", "x"): [(0, 0.01 * PH, "hold")],
    ("restL", "rotation"): [(0, HANG, "hold")],
    ("restR", "rotation"): [(0, 0.38, E), (45, 0.32, E), (90, 0.38)],
    ("dots", "opacity"): [(0, 1, "hold")],
} | {(d, "y"): [(0, 0), (k * 12, 0, E), (k * 12 + 12, -0.03 * PH, E), (k * 12 + 24, 0), (90, 0)] for k, d in enumerate(DOTS)}))
A["sleeping"] = mood("Sleeping", 150, dict({
    ("root", "scaleY"): [(0, 0.99, E), (75, 1.025, E), (150, 0.99)],
    ("head", "rotation"): [(0, 0.18, "hold")],
    ("eyes", "scaleY"): [(0, 0.08, "hold")],
    ("restL", "rotation"): [(0, 0.05, "hold")], ("restR", "rotation"): [(0, -0.05, "hold")],
    ("zzz", "opacity"): [(0, 1, "hold")],
} | {k2: v for k, z in enumerate(ZEDS) for k2, v in {
    (z, "opacity"): [(0, 0), (k * 40, 0), (k * 40 + 20, 1), (k * 40 + 70, 0), (150, 0)],
    (z, "y"): [(0, -(0.36 + 0.07 * k) * PH), (k * 40, -(0.36 + 0.07 * k) * PH), (k * 40 + 70, -(0.46 + 0.07 * k) * PH), (150, -(0.46 + 0.07 * k) * PH)],
}.items()}))
A_REST = anim("Tap rest", 1, {(FX["bounce"], "scaleX"): [(0, 1, "hold")], (FX["bounce"], "scaleY"): [(0, 1, "hold")],
                              (FX["bounce"], "y"): [(0, CY, "hold")]}, loop="oneShot")
A_TAP = anim("Tap giggle", 30, {
    (FX["bounce"], "scaleX"): [(0, 1.08, "out"), (8, 0.94, E), (18, 1.03, E), (30, 1)],
    (FX["bounce"], "scaleY"): [(0, 0.9, "out"), (8, 1.06, E), (18, 0.98, E), (30, 1)],
    (FX["bounce"], "y"): [(0, CY), (8, CY - 0.05 * PH, E), (18, CY, E), (30, CY)],
}, loop="oneShot")


# ------------------------------------------------------------------ state machine
def bind(prop, key, write=False):
    return '<DataBindContext sourcePathIds="%s-%s" propertyKey="%d"%s/>' % (VM, prop, key, ' direction="true"' if write else "")


def mood_is(k):
    return ('<TransitionViewModelCondition><TransitionPropertyViewModelComparator><BindablePropertyNumber>%s'
            '</BindablePropertyNumber></TransitionPropertyViewModelComparator><TransitionValueNumberComparator value="%d"/>'
            '</TransitionViewModelCondition>' % (bind(P_MOOD, 636), k))


TAP_COND = ('<TransitionViewModelCondition><TransitionPropertyViewModelComparator><BindablePropertyTrigger>%s'
            '</BindablePropertyTrigger></TransitionPropertyViewModelComparator><TransitionValueTriggerComparator/>'
            '</TransitionViewModelCondition>' % bind(P_TAP, 686))

state_ids = [new_id() for _ in MOODS]
states = []
for k, m in enumerate(MOODS):
    ts = "".join('<StateTransition stateToId="%s" duration="250" enableEarlyExit="true">%s</StateTransition>'
                 % (state_ids[j], mood_is(j)) for j in range(len(MOODS)) if j != k)
    states.append('<AnimationState x="%d" y="%d" animationId="%s" id="%s">%s</AnimationState>'
                  % (160 + 200 * k, 160 * (k % 2), A[m], state_ids[k], ts))
mood_layer = ('<StateMachineLayer name="Mood" id="%s"><AnyState x="160" y="-160"/><ExitState x="1600" y="-160"/>'
              '<EntryState x="0" y="0"><StateTransition stateToId="%s"/></EntryState>%s</StateMachineLayer>'
              % (new_id(), state_ids[0], "".join(states)))
s_rest, s_tap = new_id(), new_id()
tap_layer = ('<StateMachineLayer name="Tap" id="%s"><AnyState x="160" y="-160">'
             '<StateTransition stateToId="%s" duration="0">%s</StateTransition></AnyState><ExitState x="600" y="-160"/>'
             '<EntryState x="0" y="0"><StateTransition stateToId="%s"/></EntryState>'
             '<AnimationState x="160" y="0" animationId="%s" id="%s"/>'
             '<AnimationState x="360" y="0" animationId="%s" reset="true" id="%s">'
             '<StateTransition stateToId="%s" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/></AnimationState>'
             '</StateMachineLayer>' % (new_id(), s_tap, TAP_COND, s_rest, A_REST, s_rest, A_TAP, s_tap, s_rest))
listener = ('<StateMachineListenerSingle targetId="%s" listenerTypeValue="click" name="Tap"><ListenerViewModelChange>'
            '<BindablePropertyTrigger propertyValue="1">%s</BindablePropertyTrigger></ListenerViewModelChange>'
            '</StateMachineListenerSingle>' % (HIT, bind(P_TAP, 686, write=True)))
machine = '<StateMachine name="Mascot" id="%s">%s%s%s</StateMachine>' % (SM, mood_layer, tap_layer, listener)

doc = (
    '<Rive version="1" kind="fragment">\n'
    '<Artboard defaultStateMachineId="%s" viewModelId="%s" viewModelInstanceId="%s" styleId="%s" '
    'width="%d" height="%d" name="Penny" id="%s"><LayoutComponentStyle name="Style" id="%s"/>%s%s%s%s%s</Artboard>\n'
    '<ViewModel defaultInstanceId="%s" name="Mascot" id="%s">'
    '<ViewModelPropertyNumber name="mood" id="%s"/><ViewModelPropertyTrigger name="tap" id="%s"/>'
    '<ViewModelInstance exports="true" name="Default" id="%s">'
    '<ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="%s"/></ViewModelInstance></ViewModel>\n'
    '</Rive>\n'
    % (SM, VM, VMI, STYLE, SIZE, SIZE, AB, STYLE, machine, hit, penny, shadow, "".join(ANIMS),
       VMI, VM, P_MOOD, P_TAP, VMI, P_MOOD))
with open(OUT, "w") as fh:
    fh.write(doc)
print("wrote %s (%d bytes)" % (os.path.relpath(OUT), len(doc)))
