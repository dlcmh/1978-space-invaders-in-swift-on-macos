import Foundation
import SpaceInvadersCore

var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        print("FAIL: \(message)")
        exit(1)
    }
}

func step(_ game: SpaceInvadersGame, seconds: Double) {
    var elapsed = 0.0
    while elapsed < seconds {
        game.update(dt: 1.0 / 60.0)
        elapsed += 1.0 / 60.0
    }
}

func startPlaying(_ game: SpaceInvadersGame) {
    game.requestStart()
    check(game.phase == .ready, "starting a game enters READY")
    step(game, seconds: 1.9)
    check(game.phase == .playing, "READY reaches PLAYING")
}

// Arena, invaders, and bunker integrity.
check(Arena.width == 224 && Arena.height == 256, "arcade playfield is 224 x 256")
check(Arena.alienCount == 55, "the formation contains 55 invaders")
check(Arena.alienRows == 5 && Arena.alienColumns == 11, "five rows of eleven invaders")
check(Arena.bunkerCount == 4, "there are four defence bunkers")

let initialGame = SpaceInvadersGame(highScore: 1_234)
check(initialGame.phase == .attract, "starts in attract mode")
check(initialGame.aliensRemaining == 55, "starts with all 55 invaders")
check(initialGame.aliens.count == 55, "the alien array has 55 entries")
check(initialGame.lives == 3, "starts with three cannons")
check(initialGame.highScore == 1_234, "loads the supplied high score")
check(initialGame.bunkers.count == 4, "starts with four bunkers")
check(
    initialGame.bunkers.allSatisfy { $0.isIntact && $0.remainingCells > 0 }, "bunkers start intact")
check(
    initialGame.aliens.allSatisfy { $0.rect.minX >= 0 && $0.rect.maxX <= Double(Arena.width) },
    "all invaders start inside the playfield"
)

let kinds = initialGame.aliens.reduce(into: [AlienKind: Int]()) { counts, alien in
    counts[alien.kind, default: 0] += 1
}
check(kinds[.squid] == 11, "eleven squid in the top row")
check(kinds[.crab] == 22, "twenty-two crabs in the middle rows")
check(kinds[.octopus] == 22, "twenty-two octopus in the bottom rows")
check(AlienKind.squid.points == 30, "squid are worth 30 points")
check(AlienKind.crab.points == 20, "crab are worth 20 points")
check(AlienKind.octopus.points == 10, "octopus are worth 10 points")

// Player movement is continuous and clamped to the cannon rails.
let movementGame = SpaceInvadersGame()
startPlaying(movementGame)
let initialPlayerX = movementGame.player.position.x
movementGame.setMovingLeft(true)
step(movementGame, seconds: 0.25)
check(movementGame.player.position.x < initialPlayerX, "holding left moves the cannon left")
movementGame.setMovingLeft(false)
step(movementGame, seconds: 0.1)
let releasedPlayerX = movementGame.player.position.x
step(movementGame, seconds: 0.25)
check(
    movementGame.player.position.x == releasedPlayerX,
    "releasing left stops the cannon immediately")
movementGame.setMovingLeft(true)
step(movementGame, seconds: 1.2)
check(movementGame.player.position.x == Arena.playerMinX, "the cannon stops at the left rail")
movementGame.setMovingLeft(false)

let rightRailGame = SpaceInvadersGame()
startPlaying(rightRailGame)
rightRailGame.setMovingRight(true)
step(rightRailGame, seconds: 1.3)
check(rightRailGame.player.position.x == Arena.playerMaxX, "the cannon stops at the right rail")
rightRailGame.setMovingRight(false)

// Firing, a one-shot limit, an invader kill, and score.
let killGame = SpaceInvadersGame()
startPlaying(killGame)
let intervalBeforeKill = killGame.marchInterval
killGame.fire()
check(killGame.playerBullet != nil, "fire creates a player shot")
check(killGame.drainEvents().contains(.playerShot), "firing emits a playerShot event")
killGame.fire()
check(killGame.playerBullet != nil, "a second shot is refused while one is in flight")

var stepsToHit = 0
while killGame.aliensRemaining == 55, stepsToHit < 120, killGame.phase == .playing {
    killGame.update(dt: 1.0 / 60.0)
    stepsToHit += 1
}
check(killGame.phase == .playing, "the game is still playing after a shot")
check(killGame.aliensRemaining == 54, "the player shot destroys one invader")
check(killGame.playerBullet == nil, "the shot is consumed by the hit")
check(killGame.score >= 10, "destroying an invader awards points")
check(killGame.highScore >= killGame.score, "high score tracks the score")
check(killGame.explosions.isEmpty == false, "an invader kill creates an explosion effect")
check(killGame.marchInterval < intervalBeforeKill, "the formation speeds up as invaders die")

// The bunkers are destructible and absorb player shots.
let bunkerGame = SpaceInvadersGame()
startPlaying(bunkerGame)
bunkerGame.setMovingLeft(true)
step(bunkerGame, seconds: 0.8)
bunkerGame.setMovingLeft(false)
let cellsBefore = bunkerGame.bunkers[0].remainingCells
bunkerGame.fire()
step(bunkerGame, seconds: 0.4)
check(bunkerGame.bunkers[0].remainingCells < cellsBefore, "a shot chips the first bunker")
check(bunkerGame.score == 0, "a bunker hit does not award points")

// Pause freezes the simulation.
let pauseGame = SpaceInvadersGame()
startPlaying(pauseGame)
pauseGame.setMovingLeft(true)
step(pauseGame, seconds: 0.2)
let pausedX = pauseGame.player.position.x
pauseGame.togglePause()
check(pauseGame.isPaused, "pause flag set")
let pausedSteps = pauseGame.formationSteps
step(pauseGame, seconds: 0.6)
check(pauseGame.player.position.x == pausedX, "pause freezes cannon movement")
check(pauseGame.formationSteps == pausedSteps, "pause freezes the formation")
pauseGame.togglePause()
check(!pauseGame.isPaused, "resume clears the pause flag")
step(pauseGame, seconds: 0.15)
check(pauseGame.player.position.x < pausedX, "movement resumes after unpausing")

// Mystery ship appearance, value, and departure.
let mysteryGame = SpaceInvadersGame()
startPlaying(mysteryGame)
var mysteryWait = 0
while mysteryGame.mysteryShip == nil, mysteryWait < 60 * 30, mysteryGame.phase != .gameOver {
    mysteryGame.update(dt: 1.0 / 60.0)
    mysteryWait += 1
}
check(
    mysteryGame.mysteryShip != nil,
    "a mystery ship eventually crosses the top of the screen")
if let ship = mysteryGame.mysteryShip {
    check([50, 100, 150, 300].contains(ship.points), "the mystery ship carries a valid value")
    check(ship.position.y == 30, "the mystery ship crosses above the formation")
    check(
        ship.position.x < 0 || ship.position.x >= Double(Arena.width)
            || ship.direction == 1 || ship.direction == -1,
        "the mystery ship travels horizontally")
}
var departureWait = 0
while mysteryGame.mysteryShip != nil, departureWait < 60 * 20,
    mysteryGame.phase != .gameOver
{
    mysteryGame.update(dt: 1.0 / 60.0)
    departureWait += 1
}
check(mysteryGame.mysteryShip == nil, "the mystery ship leaves the playfield")

// Enemy bombs eventually kill an idle cannon, and lives are deducted after the
// death animation.
let deathGame = SpaceInvadersGame()
startPlaying(deathGame)
var deathWait = 0
while deathGame.phase == .playing, deathWait < 60 * 60 {
    deathGame.update(dt: 1.0 / 60.0)
    deathWait += 1
}
check(deathGame.phase == .playerDying, "an invader bomb can hit the cannon")
step(deathGame, seconds: 1.6)
check(deathGame.lives == 2, "a lost cannon is deducted after the death animation")
check(deathGame.phase == .ready || deathGame.phase == .playing, "play resumes after a death")

// A long idle simulation must reach a terminal game-over state. Depending on
// the random bomb stream, the invaders may overrun the line first.
var overWait = 0
while deathGame.phase != .gameOver, overWait < 60 * 300 {
    deathGame.update(dt: 1.0 / 60.0)
    overWait += 1
}
check(deathGame.phase == .gameOver, "an idle game eventually ends")
check(deathGame.gameOverReason != nil, "game over records its reason")
check(deathGame.lives == 0 || deathGame.gameOverReason == .invasion, "game over is consistent")
deathGame.requestStart()
check(deathGame.phase == .ready && deathGame.lives == 3, "game over can be restarted")

// A 60-second soak test with random movement and firing catches non-finite
// positions, stuck bullets, and state-machine crashes.
let soak = SpaceInvadersGame()
startPlaying(soak)
var rng = SplitMix64(seed: 0xA11CE_5EED)
var soakElapsed = 0.0
while soakElapsed < 60.0 {
    if Int(soakElapsed * 60) % 40 == 0 {
        soak.setMovingLeft(rng.index(upperBound: 2) == 0)
        soak.setMovingRight(rng.index(upperBound: 2) == 0)
        soak.fire()
    }
    soak.update(dt: 1.0 / 60.0)
    soakElapsed += 1.0 / 60.0
    check(soak.player.position.x.isFinite, "cannon x remains finite")
    check(soak.player.position.y.isFinite, "cannon y remains finite")
    check(
        soak.player.position.x >= Arena.playerMinX - 0.001
            && soak.player.position.x <= Arena.playerMaxX + 0.001,
        "cannon remains on its rails")
    check(soak.aliens.allSatisfy { $0.position.x.isFinite }, "invader x remains finite")
    check(soak.enemyBombs.count <= 3, "at most three enemy bombs are in flight")
    for bomb in soak.enemyBombs {
        check(bomb.position.y.isFinite, "bomb y remains finite")
    }
    if let bullet = soak.playerBullet {
        check(bullet.position.y.isFinite, "player bullet y remains finite")
    }
}
check(soak.phase != .attract, "soak simulation started")

print("PASS: \(checks) checks")

// Wave-clear autopilot. It uses only public state and the public input API:
// it steers under the nearest living invader, fires whenever the shot is
// aligned, and lets the destructible bunkers erode the way they do in play.
let sweep = SpaceInvadersGame()
startPlaying(sweep)
var sweepTicks = 0
while sweep.wave == 1, sweep.phase != .gameOver, sweepTicks < 60 * 150 {
    if sweep.phase == .playing {
        let playerCenter = sweep.player.centerX
        let playerTop = sweep.player.rect.minY
        let threat = sweep.enemyBombs
            .filter { bomb in
                let verticalGap = playerTop - bomb.rect.maxY
                return verticalGap > 0 && verticalGap < 62
                    && abs(bomb.rect.center.x - playerCenter) < 13
            }
            .min(by: {
                abs($0.rect.center.x - playerCenter) < abs($1.rect.center.x - playerCenter)
            })
        if let threat {
            if threat.rect.center.x <= playerCenter {
                sweep.setMovingLeft(false)
                sweep.setMovingRight(true)
            } else {
                sweep.setMovingLeft(true)
                sweep.setMovingRight(false)
            }
        } else if let target = sweep.aliens.filter({ $0.alive }).min(by: {
            abs($0.center.x - playerCenter) < abs($1.center.x - playerCenter)
        }) {
            let delta = target.center.x - playerCenter
            sweep.setMovingLeft(delta < -0.3)
            sweep.setMovingRight(delta > 0.3)
            if abs(delta) < 1.2 {
                sweep.fire()
            }
        }
    } else {
        sweep.setMovingLeft(false)
        sweep.setMovingRight(false)
    }
    sweep.update(dt: 1.0 / 60.0)
    sweepTicks += 1
}
check(
    sweep.phase == .waveComplete || sweep.wave > 1,
    "an autopilot can clear all 55 invaders and complete a wave")
if sweep.phase == .waveComplete || sweep.wave > 1 {
    let ticksUsed = Double(sweepTicks) / 60.0
    check(ticksUsed < 150, "the wave is clearable within the invasion window")
    step(sweep, seconds: 3.8)
    check(sweep.wave == 2, "clearing a wave advances to wave 2")
    check(sweep.aliensRemaining == 55, "wave 2 restores the full formation")
    check(sweep.bunkers.allSatisfy { $0.isIntact }, "wave 2 restores the bunkers")
}
print("PASS: \(checks) checks (including wave-clear autopilot)")
