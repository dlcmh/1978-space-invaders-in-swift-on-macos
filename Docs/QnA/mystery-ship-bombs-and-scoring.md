# How do the mystery ship, bombs, and scoring work?

- **Project:** SPACE INVADERS — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

### The mystery ship

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `updateMysteryShip`
moves an active ship horizontally at 38 px/s. When no ship is active it counts
down `mysteryTimer`; once that expires, `spawnMysteryShip` chooses a direction,
starts just outside the playfield at y = 30, and picks a value from
50, 100, 150, or 300 using `SplitMix64`. The first crossing begins roughly
5.5–8.5 seconds after play starts, then the timer is reset to 16–27 seconds.

`hitMysteryShip` awards the value, queues an explosion and score popup, emits
`.mysteryHit`, and clears the ship. The renderer draws the ship from
`SpriteArt.mysteryShip` and floats the popup upward in `drawPopups`.

### Enemy bombs

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `updateBombTimer`
spawns bombs while fewer than three are in flight. `dropBomb` finds the lowest
living invader in each column, picks one of those shooters at random, and emits a
2 × 6 projectile from its underside. `nextBombDelay` shortens the delay on later
waves and applies a deterministic random jitter.

`updateBombs` moves each bomb downward, checks bunkers first, then checks the
cannon. A cannon hit calls `beginPlayerDeath`; a bunker hit removes the bomb and
emits `.bunkerHit`.

### Scoring

[`Game.swift`](../../Sources/SpaceInvadersCore/Game.swift) — `addScore` is the
only score path. It updates `score`, raises `highScore`, and awards extra
cannons. `AlienKind.points` supplies 30/20/10; the mystery ship supplies its
chosen value.

`destroyAlien` also creates an explosion and a `.alienKilled` event. The cannon
starts with three lives and the HUD shows the two reserves through
`displayedLives`.

The extra-life schedule is explicit: `nextExtraLife` starts at 1,000 and adds
5,000 after each award, so the thresholds are 1,000, 6,000, 11,000, and so on.
Each award emits `.extraLife`, which the app turns into the ascending jingle.

### Score and high-score display

[`Renderer.swift`](../../Sources/SpaceInvadersArcade/Renderer.swift) —
`drawHUD` formats both scores with `paddedScore`, draws the wave number, and
shows reserve cannons in the lower-left. The high score is loaded and saved by
`GameView` under the `SpaceInvadersArcadeHighScore` preference key.
