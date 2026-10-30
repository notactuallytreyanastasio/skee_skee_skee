# Architecture

## Functional core, imperative shell

```
             ┌──────────────────────────── SkeeCore (pure) ─────────────────────────────┐
 Launch ───▶ │ simulateShot(Launch, Table) -> ShotResult                                │
             │ scoreFrame([BallRecord], ScoringContext) -> FrameScore                   │
 Action ───▶ │ apply(Action, RunState) -> Result<Step, ActionError>                     │
             │ table(for: RunState) -> Table      difficultyTable(ante:)   Boss.modify  │
             │ AimBook, Skill, playBotRun          (bots for balance)                   │
             └──────────────────────────────────────────────────────────────────────────┘
                     │ Step { state, events }
             ┌── SkeeRender (pure): Presentation.enqueue(Step, releaseAlong) / advance(dt)
             ├── SkeeScene (SceneKit): Cabinet, toon kit, World mapping, CameraRig fit,
             │                         ScenePresenter.update(Presentation, held:)
             └── SkeeHUD (SwiftUI): HUDState.make(Presentation) -> HUDView
                 │                                   │
        ┌────────┴──────── App (iOS) ────────┐   ┌──┴──────── skee (macOS CLI) ──────┐
        │ CADisplayLink -> advance(dt)       │   │ play / map / windows / balance   │
        │ SCNView + HUDView overlay          │   │ scene / scenefilm / frame -> PNG │
        │ ThrowPad -> analyzeStroke          │   │ save file = seed + actions       │
        │ UIHingeInteraction -> fold         │   └──────────────────────────────────┘
        │ haptics, save file                 │
        └────────────────────────────────────┘
```

Rules for the core:

- No clocks, no system randomness, no I/O. Randomness is a `SplitMix64` value
  inside `RunState`.
- Everything is a value type (`struct`/`enum`), `Hashable`, `Codable`, `Sendable`.
- One mutator: `apply`. Illegal actions return a typed `ActionError` and the input
  state is untouched.
- A run is fully described by `(seed, [Action])`. The app saves exactly that,
  and the CLI's `play` command does too.

## Types that carry the design

| Type | Why it exists |
|------|---------------|
| `Launch` | Everything a player controls, normalised and clamped (power, aim, start, fold). The core never sees points or radians from UIKit. |
| `Table` (`LaneSpec`, `HingeSpec`, `BoardSpec`) | The physical machine. Difficulty, bosses and power-ups are functions `Table -> Table`. |
| `ShotResult` | Hole, ordered `ShotEvent`s, and a recorded `PathSample` path. The app replays the path; it never runs physics per frame. |
| `Hole`, `Symbol`, `Payline` | Board and slot vocabulary. |
| `BoardSetup` | Each hole's reel strip plus gilds: what the player builds. |
| `BallRecord` → `FrameScore` | Scoring sees no physics: just hole, symbol, chips, rattles, fold. |
| `ScoreStep` | Every change to chips or mult with its source. The total is the fold of the steps, and the UI plays them back. A test checks the two agree. |
| `RunState`, `Phase`, `Action`, `GameEvent` | The whole run as a value; the state machine; the input; what happened, in order. |
| `Presentation`, `Beat` | What the screen shows versus what is true. The reducer resolves a throw instantly; the presentation plays it out as beats (roll, tally, spin, banner, restyle, commit). Also pure. |
| `UIState`, `Intent`, `Rects` | Interaction state as a value; what a tap means; one set of rectangles shared by renderer and hit tester so they can't disagree. |

## Why the presentation is separate

The reducer answers "what happened" in microseconds. Players need three seconds
of ball flight, a counted-up score and spinning reels. Putting that timing in
`Presentation` keeps it out of the rules and testable without a screen. For
example, `PresentationTests.tallyScoreStaysOnScreenUntilCommit` pins a bug
found by looking at a contact sheet: the HUD score dropped back between the
tally and the state commit.

## Rendering

`SkeeScene` builds the cabinet from toon parts (`ToonKit.part` over shared
rounded primitives). `World` maps physics coordinates to scene coordinates;
the lane is drawn at 0.42 of its length and the board at 1.55x so the target
reads on a phone, and every position goes through the same mapping. The
camera is not hand-placed: `Cabinet.fit` searches eye height, distance, aim
and lens so that the hump lands at 50% of the screen height (the crease).

`ScenePresenter` reads a `Presentation` each frame. It places and rolls the
ball, sinks it into its hole, flips reel plates while they spin, and counts
the balls left in the tray. `SkeeHUD` turns the same presentation into a
`HUDState` and draws it in SwiftUI.

The CLI renders identical frames headless: `SCNRenderer` for the scene,
`ImageRenderer` for the HUD.

## Testing

- `make test` runs both suites in release with `-enable-testing`. The bot and
  difficulty tests play whole games and are about 20x slower in debug.
- Physics: determinism, mirror symmetry, monotonic flight, every hole reachable,
  lips rattle, termination, input clamping.
- Scoring and charms: each charm's effect, left-to-right order, steps that fold
  to the total.
- Run: round flow, counter, purchases, stamps, purges, reels, Hold, fever,
  replay exactness, winning and losing.
- Difficulty: "never impossible" for every boss at ante 8.
- Bots: determinism, aim book coverage, skill matters.
- Input: stroke analysis on synthetic strokes (clean slide, hitches, curve,
  crease crossing, tap, pull back).
- Presentation timing, including the roll trimmed to the release point.

The work was test-first. Each module's tests were written and failed before the
implementation existed. Several tests started wrong and the history says so:
the straight-only crosswind check, and monotonic landing without wall-face
slack.
