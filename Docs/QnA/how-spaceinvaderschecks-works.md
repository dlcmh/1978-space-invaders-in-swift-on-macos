# How does SpaceInvadersChecks work, and how does it know which parts of SpaceInvadersCore to run?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**It does not know.** There is no discovery, no coverage feedback, and no
reflection. The executable links the whole `SpaceInvadersCore` module, then runs
the statements written in `Checks/main.swift` in order. The only thing that
"selects" core code is the public access boundary: the checks can call public
symbols and nothing else.

### What runs, in order

[`Package.swift`](../../Package.swift) — `SpaceInvadersChecks` is an
`executableTarget` that depends on `SpaceInvadersCore`.

[`main.swift`](../../Checks/main.swift) — `check` is the harness: increment a
counter, print the message and exit 1 on failure, otherwise return. Top-level
statements form the program body.

1. `swift run` (or the built binary) compiles the target and links the core
   module.
2. `import SpaceInvadersCore` makes every `public` symbol visible.
3. The first statement constructs a `SpaceInvadersGame`, and the rest follow in
   file order.
4. Helper functions `step` and `startPlaying` advance time in 1/60 s increments
   and assert the ready-to-playing transition.
5. Each scenario drives commands, reads read-only state, and calls `check`.
6. The last statement prints the total; the process exits 0.

### Three layers decide what executes

| Layer | Mechanism | What it selects |
| --- | --- | --- |
| Build | The target dependency in `Package.swift` | Everything: the whole module is compiled and linked |
| Access | `public` and `public private(set)` | The public surface; internals are unreachable |
| Source | The statements in `main.swift` | The exact subset that actually runs |

Only the third is a choice. Change the file and a different subset runs; nothing
else is consulted in between.

### It is black-box by construction

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `SpaceInvadersGame`
exposes commands (`requestStart`, `fire`, `setMovingLeft`, `setMovingRight`,
`togglePause`, `pause`, `update(dt:)`, `drainEvents`) and read-only properties.
There is no `@testable import` and no test-only mutation hook, so a scenario can
only do what a player can do: send commands and advance time.

That is also why scenarios do not interfere. Each one constructs a fresh game
object rather than resetting a shared fixture, and value types such as
[`Bunker`](../../Sources/SpaceInvadersCore/Bunker.swift) — `remainingCells` — are
copied, not shared.

### The scenario map

The order is manual but not arbitrary; each block targets one documented
behaviour and builds the state it needs.

| Block | Drives | Asserts on |
| --- | --- | --- |
| Playfield constants | Nothing | `Arena`, `AlienKind`, bunker count |
| Initial state | Constructor | `phase`, `lives`, `aliensRemaining`, high score |
| Movement | `setMovingLeft/Right`, `step` | Cannon `position`, rail limits |
| Firing | `fire`, `drainEvents` | One-shot rule, kill, score, explosion |
| Bunkers | `fire` after moving under a shield | `remainingCells`, no points awarded |
| Pause | `togglePause` | `isPaused`, frozen position and `formationSteps` |
| Mystery ship | `update` loop | `mysteryShip`, its value, departure |
| Death and game over | Long `update` loops | `phase`, `lives`, `gameOverReason` |
| Soak | 60 s of seeded random input | Finite positions, rails, bomb cap |
| Autopilot | Public API only | `waveComplete` / wave 2, restored bunkers |

### What it does not know

- **No coverage measurement.** Nothing reports which functions were entered.
- **No completeness check.** The suite calls seven of the nine public commands
  directly; `startNewGame` is reached through `requestStart`, but `pause()` is
  never called at all, so a regression that only affects `pause()` would pass.
- **No filtering.** You cannot run one scenario; the whole file runs.
- **No isolation framework.** A failure stops the run at the first bad
  assertion, so later blocks are unreported that round.
- **No performance assertions.** Wall time is not checked.

The compensating controls are review and the documented invariants in
[`AGENTS.md`](../../AGENTS.md#gameplay-invariants): when a rule changes, the
author is expected to add or update the scenario that asserts it.

### Adding a scenario

Append statements beside the block they belong to, or at the end before the
soak. Construct a fresh game, start it, drive it, assert with a message that
names the invariant:

```swift
let pauseApiGame = SpaceInvadersGame()
startPlaying(pauseApiGame)
pauseApiGame.setMovingLeft(true)
step(pauseApiGame, seconds: 0.2)
pauseApiGame.pause()
let stepsAtPause = pauseApiGame.formationSteps
let xAtPause = pauseApiGame.player.position.x
step(pauseApiGame, seconds: 0.6)
check(pauseApiGame.formationSteps == stepsAtPause, "pause() freezes the formation")
check(pauseApiGame.player.position.x == xAtPause, "pause() freezes the cannon")
```

Without the pause, both values would change; the assertions compare against state
captured at the moment of the call, not against zero.

[`Math.swift`](../../Sources/SpaceInvadersCore/Math.swift) — `SplitMix64` is the
only randomness involved, so any seeded scenario replays exactly.

### Verifying the suite itself

```bash
swift run SpaceInvadersChecks   # expect the two PASS lines
make check                      # the full gate
```

A failing `check` prints `FAIL: <message>` and exits 1. Because the message names
the behaviour, the failure identifies the scenario without a test name or line
number. If a change removes a public symbol the checks use, the build fails
before the suite runs, which is the one form of "knowing what to run" the
compiler does provide.
