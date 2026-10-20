# How do the four bunkers take damage?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

Each bunker is a real 22 × 16 grid of solid arcade pixels, not a drawn sprite
with a health bar. That choice is what makes holes look chipped rather than
uniformly shrunk.

### The shape

[`Bunker.swift`](../../Sources/SpaceInvadersCore/Bunker.swift) — `Bunker`
stores a `cells` array of `Bool`. `makeCells` parses the shield silhouette:
rounded upper corners and a widening arch cut out of the bottom. The initial
shape contains 322 solid cells, exposed as `initialCellCount`; `isIntact` means
none of them have been removed.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `makeBunkers`
places four shields at x = 24, 75, 126, and 177, with their tops at
`Arena.bunkerTop` (188).

### Projectile impacts

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `hitBunker` tests
the projectile rectangle against each bunker rectangle, then asks the bunker to
`damage(at:radius:)` at the projectile's leading tip. A player shot uses the top
edge; a bomb uses the bottom edge. The method removes a roughly circular bite of
radius 2 plus a few extra cells above the impact. If no solid cell was touched
(the projectile passed through an existing hole), the projectile keeps moving.

Both the player shot and enemy bombs call `hitBunker` **before** they are
allowed to hit the cannon, which is why a shield can absorb a bomb.

### Invader erosion

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — after every
formation step, `eraseBunkersUnderInvaders` calls `erase(overlapping:)` for any
invader that now overlaps a shield. Cells disappear wherever the sprite touches
them, reproducing the original's shields being eaten away as the formation
descends.

### Drawing and restoration

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) —
`drawBunkers` asks `isFilled` for every cell and emits one four-pixel quad per
solid cell. Damage is therefore visible immediately, with no separate damage
texture to keep in sync.

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `prepareWave`
rebuilds all four bunkers with `makeBunkers`. Starting a new game and advancing
to the next wave both restore the full 322-cell shields.
