# What do "simulation" and "presentation" mean?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

They name the two halves of the program, split by **who owns a fact** rather
than by which file happens to draw it.

**Simulation** is the authoritative model of the game world: every fact that
decides what happens next, advanced in fixed steps, with no knowledge of
pixels, windows, keyboards, or speakers.

**Presentation** is everything that turns that state into what the player
perceives, and everything that turns what the player does into commands the
simulation accepts.

| | Simulation | Presentation |
| --- | --- | --- |
| Owns | What is true and what happens next | What it looks and sounds like, and how input maps to commands |
| Lives in | `Sources/SpaceInvadersCore/` | `Sources/SpaceInvadersArcade/` |
| Depends on | `Foundation` only | AppKit, Metal, AVFoundation, `SpaceInvadersCore` |
| Runs | Fixed 1/60 s steps | Once per displayed frame |
| Answers | "Where is this alien? Is the cannon dead? What is the score?" | "Which triangles, what colour, what sound, which key?" |
| Verified by | `SpaceInvadersChecks` | Launching the app |

### Where the line is

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `SpaceInvadersGame`
holds the alien array, cannon, both projectile streams, bunkers, mystery ship,
phase, score, lives, wave, timers, explosions, and score popups. All of it is
`public private(set)`; the app cannot write any of it.

[`GameView.swift`](../../Sources/SpaceInvadersArcade/GameView.swift) — `draw(in:)`
pumps the fixed-step loop, converts key events into commands, and hands the
resolved state to the renderer. It writes only `UserDefaults` and sound state,
never gameplay state.

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) — `render`
takes a `SpaceInvadersGame` and reads it. There is no path by which a draw call
changes a position, a timer, or a score.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `drainEvents`
returns the `GameEvent` queue (`gameStart`, `alienKilled`, `playerHit`, …). That
queue is the only push channel out of the core; presentation turns each event
into a sound.

### It is not MVC, and not "the view"

Presentation is deliberately broader than rendering. It also owns window
creation, keyboard handling, audio synthesis and playback, and the two stored
preferences.

[`AppDelegate.swift`](../../Sources/SpaceInvadersArcade/AppDelegate.swift) —
`createWindow` sizes and letterboxes the window.

[`SoundEngine.swift`](../../Sources/SpaceInvadersArcade/SoundEngine.swift) —
`play` mixes the synthesised effect selected by an event.

[`PixelFont.swift`](../../Sources/SpaceInvadersArcade/PixelFont.swift) —
`PixelFont` describes glyph shapes.

[`SpriteArt.swift`](../../Sources/SpaceInvadersArcade/SpriteArt.swift) —
`frames` describes invader shapes.

Both are presentation data: the simulation knows a squid is worth 30 points,
not what it looks like.

Input crosses the boundary in one direction only, as commands: `setMovingLeft`,
`setMovingRight`, `fire`, `requestStart`, `togglePause`. The core decides what
they are allowed to do — for example, `fire` is ignored while a shot is already
in flight.

### Cases that look ambiguous

| Fact | Side | Why |
| --- | --- | --- |
| Bunker cell grid | Simulation | `Bunker` damage decides what a later shot hits |
| Explosion and popup lifetimes | Simulation | `updateTimedEffects` removes them, so they are timed state |
| Starfield positions and twinkle | Presentation | `buildStarfield` runs once and nothing reads it back |
| Background glow and scanlines | Presentation | Pure decoration in `Canvas` |
| High score value | Simulation | `SpaceInvadersGame` owns and updates it |
| High score storage, mute flag | Presentation | `UserDefaults`, written by `GameView` |
| Fixed 1/60 s step | Simulation | Determines outcomes and must be deterministic |
| Frames per second and catch-up | Presentation | `preferredFramesPerSecond` and the accumulator only decide how often to step |
| `SPACEINVADERS_*` environment variables | Presentation | Development aids for captures, not gameplay rules |

Note that presentation may reuse core *code* without owning a gameplay fact:
`buildStarfield` draws from the core's `SplitMix64` with its own fixed seed, yet
the generated stars never feed back into the game.

### How to classify a change

1. If it changes what can happen, or when, it is simulation. It needs a check in
   [`Checks/main.swift`](../../Checks/main.swift) — `check` — and must stay
   frame-rate independent.
2. If it changes what the player sees, hears, or how their input is translated,
   it is presentation. It needs a launch, not a check.
3. If it does both, split it: the rule goes in the core as state or a command,
   and the app only reads the result.

### Why the split is enforced

- `SpaceInvadersChecks` can link the core and assert 23,000+ behaviours with no
  GPU, window, or audio device.
- Randomness has one door, `SplitMix64`, so a fixed seed replays the same game.
- Bug triage is mechanical: a wrong position is a simulation bug, a wrong colour
  is a presentation bug.
- Cost is attributable. Rendering runs every frame regardless of phase, so most
  CPU is presentation; see
  [How do I tell whether the game's CPU and memory use is acceptable?](judging-cpu-and-memory-use.md).

The rule itself is architectural policy, stated in
[`AGENTS.md`](../../AGENTS.md#non-negotiable-architecture) and enforced by review
and by the import boundary: the core compiles without AppKit or Metal.
