# How is SpaceInvadersCore structured, and why is the simulation headless?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

`SpaceInvadersCore` is a Foundation-only Swift target. It knows nothing about
AppKit, Metal, windows, keyboards, or audio. That boundary is what lets the
`SpaceInvadersChecks` executable run tens of thousands of deterministic
assertions without a GPU or a drawable.

### The authoritative object

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) —
`SpaceInvadersGame` owns every gameplay fact: the alien array, the player
cannon, both projectile streams, the bunkers, the mystery ship, the phase,
score, lives, wave, timers, explosions, and score popups. The app never writes
those properties directly.

[`Arena.swift`](../../Sources/SpaceInvadersCore/Arena.swift) — `Arena` holds the
224 × 256 playfield dimensions and shared tuning constants. `Alien`,
`AlienKind`, `Cannon`, `Projectile`, `MysteryShip`, `GamePhase`, and
`GameEvent` are value types defined beside it. `Bunker` lives in its own file.

[`Bunker.swift`](../../Sources/SpaceInvadersCore/Bunker.swift) — `Bunker` is a
value type containing a 22 × 16 cell grid. Because it is a value, the game can
hand a copy to the renderer without exposing a mutable reference.

### Commands in, read-only state out

The public input surface is deliberately small:

- `requestStart` — leave attract or game-over mode for a new game.
- `fire` — request one shot; the core enforces the one-shot rule.
- `setMovingLeft` and `setMovingRight` — hold or release a rail direction.
- `togglePause` and `pause` — pause only while playing.
- `drainEvents` — consume the sound and presentation events produced by the
  last simulation steps.

Everything else is `public private(set)`. Checks drive the same commands a
keyboard does, which means there are no test-only mutation hooks.

### The fixed-step heartbeat

[`GameView.swift`](../../Sources/SpaceInvadersArcade/GameView.swift) — `draw(in:)`
accumulates display time and calls `update(dt:)` in fixed 1/60-second steps,
with a bounded catch-up loop. `Renderer.render` then receives an already
resolved game state and only reads it.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `update` advances
timers, applies the current phase, and clamps incoming `dt` to 0.05 seconds.
The simulation therefore behaves the same at 60 Hz, 120 Hz, or during a hitch.

### Phase machine

`GamePhase` has six states: `attract`, `ready`, `playing`, `playerDying`,
`waveComplete`, and `gameOver`. `update` switches on the phase; only `playing`
runs the cannon, formation, bombs, mystery ship, and collision resolution.
Transitions are explicit methods such as `beginPlayerDeath`,
`beginWaveComplete`, `advanceWave`, and `beginGameOver`.

### Determinism

[`Math.swift`](../../Sources/SpaceInvadersCore/Math.swift) — `SplitMix64` is the
only source of randomness. Bomb columns, bomb delays, mystery-ship direction,
and mystery-ship value all draw from it. The seed is fixed per game object, so a
check that repeats the same inputs sees the same sequence.

The checks import only `Foundation` and `SpaceInvadersCore`, then assert the
public state after driving the public commands. The result is fast, repeatable,
and independent of the window server.
