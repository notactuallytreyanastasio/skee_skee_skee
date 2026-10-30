# Skee Skee Skee

A skee-ball roguelike for the iPhone Duo. You flick the ball up the lane on the
bottom half of the screen; it rolls over the hinge, which is the ramp, and
flies into the rings on the top half. Each hole carries a slot-machine reel.
Every three balls read as a payline. Score chips times mult, beat the target,
spend tickets at the prize counter, and go on to the next machine.

Half-fold the phone into a little cabinet and the ramp gets steeper.

```
swift test -c release -Xswiftc -enable-testing   # or: make test   (89 tests)
swift build -c release && .build/release/skee     # the terminal tools
cd App && xcodegen generate && open SkeeSkeeSkee.xcodeproj
```

## What's here

| Path | What it is |
|------|------------|
| `Sources/SkeeCore` | The functional core. Physics, scoring, run rules, bots. Value types and pure functions only. |
| `Sources/SkeeRender` | Pure layout, animation timeline, hit testing, and a CoreGraphics renderer with four art styles. Shared by the app and the CLI. |
| `Sources/skee` | Terminal shell: play a run, map the physics, balance with bots, render PNGs. |
| `App/` | iOS shell: SwiftUI Canvas, gestures, `UIHingeInteraction`, haptics, save file. |
| `Tests/` | Swift Testing suites for both libraries. |
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
- four procedural art eras with an iris transition between them
- the app builds and runs in the iPhone Duo simulator (iOS 27.1)

Not done, or not verified:
- **The unfolded inner display has never been seen running.** The simulator
  boots folded, `simctl` has no fold command, and the Simulator GUI could not be
  scripted here. The 669×951 layout is verified only via `skee render`, which
  uses the same renderer at the same size.
- **The hinge angle mapping is a guess.** `UIHingeInteraction` reports radians;
  the code assumes π is flat open. Unconfirmed on hardware.
- **Swipe-to-power calibration is untested by a human thumb.** The constants in
  `Swipe` (400 to 3400 pt/s) are a first guess.
- No sound.
- Balance is a first pass: close rounds are rare (about 4%) and The Miser kills
  too many 50-heavy builds. See [docs/BALANCE.md](docs/BALANCE.md).
- Changing a rule changes how old saves replay, because a save is just a seed
  plus actions. There is no rules version stamped in saves yet.
