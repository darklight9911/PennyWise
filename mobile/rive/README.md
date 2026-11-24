# Penny, the pennyWise panda (Rive)

`assets/rive/penny.riv` is built from the files here with the
[Rive CLI](https://rive.app/cli).

| Path | What it is |
|---|---|
| `art/panda.svg` | The panda artwork the mascot is made from |
| `tool/panda.py` | Turns the SVG into Rive shapes, split into head, eyes and body so they can move, and draws Penny's jointed arms in the same style: shoulder, elbow, wrist and four fingers that spread and curl |
| `tool/gen_penny.py` | Writes `penny/scene.rml`: the artboard, the animations, the state machine and the view model |
| `penny/` | The Rive project (`rive.yaml` + generated `scene.rml`) |

## The file's contract

Artboard **Penny** (400 x 400, transparent), state machine **Mascot**,
view model **Mascot**:

| Property | Type | Meaning |
|---|---|---|
| `mood` | number | 0 idle, 1 wave, 2 happy, 3 celebrate, 4 worried, 5 thinking, 6 sleeping |
| `tap` | trigger | A short giggle. Tapping Penny fires it too |

`PandaMood` in `lib/core/widgets/panda_mascot.dart` uses the same order.

Each mood also sets a hand pose: relaxed paws (idle), an open waving hand
(wave), swinging open hands (happy), fists (celebrate), fidgeting fingers at
the chest (worried), a finger tapping at the chin (thinking) and loose
half-curled paws (sleeping).

## Rebuild

```bash
python3 -I rive/tool/gen_penny.py
rive rive/penny --verify
rive inspect rive/penny --summary        # "problems" should be []
rive rive/penny --screenshot=/tmp/penny.png --data=mood=3 --advance=30
rive rive/penny --publish --output-dir=../../assets/rive   # needs `rive login`
```

`--publish` needs a Rive account. On the Free plan the published file carries
the Rive splash watermark; a paid plan removes it.
