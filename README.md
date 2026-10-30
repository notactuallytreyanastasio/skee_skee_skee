# Skee Skee Skee

A skee-ball roguelike for the iPhone Duo. You slide the ball up the lane with
your thumb and let go before the crease; it rolls over the hinge, which is the
ramp, and flies into the rings on the top half. Touch past the crease and it's
a foul. Each hole carries a slot-machine reel.
Every three balls read as a payline. Score chips times mult, beat the target,
spend tickets at the prize counter, and go on to the next machine.

Half-fold the phone into a little cabinet and the ramp gets steeper.

```
swift test -c release -Xswiftc -enable-testing   # or: make test   (98 tests)
swift build -c release && .build/release/skee     # the terminal tools
cd App && xcodegen generate && open SkeeSkeeSkee.xcodeproj
```

## What's here

| Path | What it is |
|------|------------|
| `Sources/SkeeCore` | The functional core. Physics, scoring, run rules, bots. Value types and pure functions only. |
| `Sources/SkeeRender` | The pure animation timeline (`Presentation`). |
| `Sources/SkeeScene` | The 3D cel-shaded cabinet (SceneKit), toon kit ported from whats_going_through_your_mind. |
| `Sources/SkeeHUD` | The SwiftUI HUD, prize counter, title and game over. |
| `Sources/skee` | Terminal shell: play a run, map the physics, balance with bots, render PNGs. |
| `App/` | iOS shell: SCNView + HUD overlay, thumb touch layer, `UIHingeInteraction`, haptics, save file. |
| `Tests/` | Swift Testing suites for the core and the presentation timeline. |
| `docs/` | Design, architecture, physics, tools, balance, playtest notes. |

## Documentation

- [docs/DESIGN.md](docs/DESIGN.md): the game, and where each mechanic came from
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): functional core / imperative shell, data flow, testing
- [docs/PHYSICS.md](docs/PHYSICS.md): the shot model, units, and how the tuning got here
- [docs/TOOLS.md](docs/TOOLS.md): the `skee` command and how to use it to judge changes
- [docs/BALANCE.md](docs/BALANCE.md): bot methodology, current numbers, open problems
- [docs/PLAYTEST.md](docs/PLAYTEST.md): a run played by hand, and what it changed

## Status

Works:
- the full run: 8 antes × 3 rounds, 7 boss machines, 15 charms, 5 specialty
  balls, stamps, gilds and purges, ticket economy, fever meter
- deterministic physics with a tested "never impossible" guarantee
- 3D cel-shaded cabinet with a hole in every ring, a ball that rolls, and the
  hump on the crease
- thumb-slide throw with spin, skid and fouls
- the app builds, runs in the iPhone Duo simulator (iOS 27.1), and is installed
  on a physical Duo

Not done, or not verified:
- **The unfolded inner display has not been seen by me running.** The simulator
  boots folded and `simctl` cannot unfold it; the build is on a real Duo, but I
  cannot see its screen. The unfolded frame is verified via `skee frame`, which
  renders the same scene and HUD at the same size.
- **The hinge angle mapping is a guess.** `UIHingeInteraction` reports radians;
  the code assumes π is flat open. Unconfirmed on hardware.
- **The thumb stroke is untested by a human thumb.** `StrokeTuning` (250 to
  2600 pt/s for power, the hitch allowance for skid) is a first guess.
- Only one art style (cel). The several-styles-across-levels idea is not
  rebuilt in 3D yet.
- No sound.
- Balance is a first pass: close rounds are rare (about 4%) and The Miser kills
  too many 50-heavy builds. See [docs/BALANCE.md](docs/BALANCE.md).
- Changing a rule changes how old saves replay, because a save is just a seed
  plus actions. There is no rules version stamped in saves yet.
