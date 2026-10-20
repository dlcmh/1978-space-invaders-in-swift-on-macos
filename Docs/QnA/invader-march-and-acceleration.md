# How does the invader formation march, and why does it speed up?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

The formation is one coordinated object, not 55 independent agents. Every
`marchInterval` seconds, every living invader takes the same two-pixel step.

### The step

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `updateFormation`
counts down `marchTimer`. When the timer reaches zero it calls `stepFormation`,
increments `formationSteps`, flips `animationFrame`, and emits `.invaderStep`
so the app can play the next bass note.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `stepFormation`
computes the leftmost and rightmost edge of all living invaders. If another
two-pixel step would cross the eight-pixel side margin, it moves **every**
survivor down by `Arena.formationDrop` (8 pixels) and reverses `marchDirection`.
Otherwise it moves every survivor by `Arena.formationStep` (2 pixels).

After a step, `eraseBunkersUnderInvaders` removes any bunker cells the invaders
now overlap, and a survivor whose bottom reaches `Arena.invasionLine` triggers
game over with reason `invasion`.

### The acceleration

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `marchInterval` is
the whole speed model:

```text
load       = 0.03 + 0.38 × (living / 55)
waveFactor = max(0.55, 1 − 0.05 × (wave − 1))
interval   = max(0.09, load × waveFactor)
```

The first row shows the historical justification directly. Fewer living
invaders mean less sprite work, so the interval shrinks. The 0.09-second floor
keeps the late game legible and playable. `waveFactor` gives later waves a
faster starting tempo.

| Living invaders | Wave 1 interval |
| --- | --- |
| 55 | ≈ 0.41 s |
| 40 | ≈ 0.31 s |
| 20 | ≈ 0.17 s |
| 10 | ≈ 0.10 s |
| 1 | 0.09 s |

The check suite verifies that killing an invader shortens `marchInterval` and
that a full autopilot clear reaches wave 2 with a restored formation.

### Animation and presentation

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) —
`drawAliens` chooses `animationFrame` while playing, and uses a slower
time-based frame on the game-over screen. `render` skips the formation during
attract mode because the near-opaque attract panel would otherwise let slivers
of it show past the panel edges. The two frames come from `SpriteArt.frames`,
so the marching animation costs no sprite-sheet or texture work.
