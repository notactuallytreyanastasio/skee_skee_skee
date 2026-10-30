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
             ┌──────────────────────────── SkeeRender (pure + CoreGraphics) ─────────────┐
             │ Presentation.enqueue(Step) / advance(dt)   -> beats, popups, reel spin  │
             │ Layout, Projection, Swipe.launch(in:fold:), intent(at:...) -> Intent    │
             │ Renderer.draw(Presentation, UIState, Layout, CGContext)                 │
             └───────────────────────────────────────────────────────────────────────────┘
                 │                                   │
        ┌────────┴──────── App (iOS) ────────┐   ┌──┴──────── skee (macOS CLI) ──────┐
        │ CADisplayLink -> advance(dt)       │   │ play / map / windows / balance   │
        │ Canvas -> Renderer.draw            │   │ render / film -> PNG             │
        │ DragGesture -> Swipe / intent      │   │ save file = seed + actions       │
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

`Pen` holds the per-style drawing primitives: fill, ink, glow, sphere, panel,
glyph, text. `SceneDrawer` composes a frame: background, board, hinge, lane,
power gauge, ball, HUD, tray, tally, popups, counter, banners. Style is data,
and `Palette.of(style)` holds every colour. The pixel era renders the whole
scene into a half-resolution bitmap with antialiasing off and scales it up with
nearest-neighbour sampling.

The context is y-down with a top-left origin. SwiftUI's Canvas already is; the
CLI flips its bitmap before calling.

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
- Render: style per ante, layout and projection invariants for every style
  (lane and board meet at the hinge), swipe mapping, presentation timing.

The work was test-first. Each module's tests were written and failed before the
implementation existed. Several tests started wrong and the history says so:
the straight-only crosswind check, and monotonic landing without wall-face
slack.
