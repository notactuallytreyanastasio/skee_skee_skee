# Physics

`simulateShot(_ launch: Launch, on table: Table) -> ShotResult` in
`Sources/SkeeCore/Physics/Simulator.swift`.

Units are metres, seconds and radians, sized like a real alley so the numbers
mean something. One fixed 240 Hz clock (`Table.dt`) for the whole shot. The
path is recorded at 60 Hz for the renderer.

## Phases

1. **Lane.** The ball starts at `start × half lane width`, speed
   `minSpeed + power × (maxSpeed − minSpeed)` (2 to 5 m/s), angled by
   `aim × 8°`. It decelerates on a 6° incline with rolling friction 0.02; side
   rails reflect at 0.6. If its forward speed reaches zero before the hinge, it
   is a **dud** and rolls back to the gutter.
2. **Over the hinge.** At the ridge the forward speed (× `hinge.carry`) leaves
   at the launch angle: 45° flat open, plus up to 20° with the device folded.
3. **Air.** Ballistic in board coordinates. The board is tilted 20°, so gravity
   splits into a pull down the board (`g sin 20°`) and onto it (`g cos 20°`).
   The backwall and side walls reflect. Coming down through lip height near a
   ring wall is a **lip hit**: bounce up at 0.3 and a sideways shove toward
   whichever side of the wall the ball's centre is on. That is the rattle.
4. **Board.** Rolling with friction. Ring walls block the ball while it is below
   lip height. It drops into the 50 hole or a pocket if it passes over one slowly
   enough. It goes to the gutter if it rolls off the bottom. Otherwise it settles
   against a ring wall and scores that ring.

## Board geometry

```
y (m)
1.00  ─────────── backwall ───────────
0.86     (100)                 (100)       pockets at x = ±0.20, r = 3.6 cm
0.62                 (50)                  50 hole: 4 cm above ring centre, r = 3 cm
0.58               ring centre
                   walls at r = 0.10 (40 cup), 0.16 (30), 0.22 (20), 0.29 (10)
0.29     ─ bottom of the 10 ring ─
0.00  ─────────── hinge / gutter ───────
       x from -0.31 to +0.31
```

## How the tuning got here

Each of these came from running the tools, not from reasoning alone.

1. **Balls walked along lip tops.** The first sweep showed balls bouncing from
   lip to lip down the board, fifty lip events in a shot. Every point on the
   board was within one ball radius of some wall: walls 6 cm apart, ball radius
   3.5 cm. Fixes: lip contact only within 0.6 radii of the wall line; a minimum
   fall speed of 0.6 m/s to bounce off a lip (slower balls just meet the wall
   face); landings keep only 35% of in-plane speed.
2. **The 50 was free.** With the hole at the centre of the 40 cup, balls rolling
   down through the cup fell in. The hole moved 4 cm up, so balls that land low
   in the cup roll away from it.
3. **Pockets were the best target.** `skee windows` showed the 100 pockets
   accepting 16% of the power range, against 7% for the 50. The side wall and
   backwall funnelled balls into the corners. After making pockets first-contact
   only, bots still sent 76% of their balls there. Pockets moved inward to ±0.20
   and now count only on a clean flight with no wall touch first. They now take
   about 2.5% of the power range.
4. **Slick Lane did nothing.** Cutting lane friction to 30% moved the 50 window
   by 0.03 power, about one standard deviation of a decent player's hand. Now
   the lane is frictionless and the hinge carries 4% extra: the 50 sits at power
   0.56 instead of 0.63.

## Forgiveness, measured

`skee windows` at ante 1 (widest contiguous power window per hole):

```
ring10       17.50%
ring20        5.00%
ring30        8.75%
ring40        5.00%
ring50        6.67%   at power 0.63, aim 0
pockets       2.50%   at power 0.77, aim ±0.25
```

`skee map` prints the full power × aim grid. The structure is easy to read:
gutter below power 0.4; bands of 10, 20, 30 and 40 climbing to a diamond of 5s
around power 0.6, aim 0; the upper halves of the rings above it; pocket bands
around power 0.77 to 0.80 at aim ±0.25; overshoot and gutter at the top.

## Determinism

Same `Launch`, same `Table`: identical `ShotResult`, compared with `==` in
tests. Mirrored launches give mirrored holes, tested across powers. Bits are
only guaranteed on the same platform and libm. The app and the CLI both run on
Apple's libm.
