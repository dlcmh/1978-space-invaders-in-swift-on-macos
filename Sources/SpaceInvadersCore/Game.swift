import Foundation

/// The authoritative, headless Space Invaders simulation.
///
/// The class owns the invaders, the player cannon, both projectile streams,
/// the four destructible bunkers, the mystery ship, scoring, waves, and the
/// state machine. It imports only Foundation so `SpaceInvadersChecks` can run
/// thousands of deterministic assertions without a window or a GPU.
public final class SpaceInvadersGame {
    public private(set) var aliens: [Alien]
    public private(set) var bunkers: [Bunker]
    public private(set) var player: Cannon
    public private(set) var playerBullet: Projectile?
    public private(set) var enemyBombs: [Projectile]
    public private(set) var mysteryShip: MysteryShip?
    public private(set) var explosions: [Explosion] = []
    public private(set) var popups: [ScorePopup] = []

    public private(set) var phase: GamePhase = .attract
    public private(set) var score = 0
    public private(set) var highScore: Int
    public private(set) var wave = 1
    public private(set) var lives = 3
    public private(set) var elapsed = 0.0
    public private(set) var readyRemaining = 0.0
    public private(set) var deathFraction = 0.0
    public private(set) var waveClearFraction = 0.0
    public private(set) var isPaused = false
    public private(set) var gameOverReason: GameOverReason?
    public private(set) var marchDirection = 1.0
    public private(set) var animationFrame = 0
    public private(set) var formationSteps = 0

    private var events: [GameEvent] = []
    private var moveLeft = false
    private var moveRight = false
    private var marchTimer = 0.0
    private var bombTimer = 0.0
    private var mysteryTimer = 0.0
    private var deathElapsed = 0.0
    private var waveClearElapsed = 0.0
    private var nextExtraLife = Arena.extraLifeThreshold
    private var rng = SplitMix64(seed: 0x1978_5EED_1A2B_3C4D)

    private let deathDuration = 1.35
    private let waveClearDuration = 2.1
    private let playerSpeed = 100.0
    private let playerShotSpeed = 340.0
    private let mysteryShipSpeed = 38.0
    private let maximumBombs = 3

    public init(highScore: Int = 0) {
        self.highScore = max(0, highScore)
        self.aliens = Self.makeFormation()
        self.bunkers = Self.makeBunkers()
        self.player = Cannon(position: Self.centeredPlayerPosition())
        self.playerBullet = nil
        self.enemyBombs = []
        self.mysteryShip = nil
        self.marchTimer = 0.33
        self.bombTimer = 2.0
        self.mysteryTimer = 7.0
        self.marchDirection = 1.0
    }

    // MARK: - Public state

    public var aliensRemaining: Int {
        aliens.reduce(0) { $0 + ($1.alive ? 1 : 0) }
    }

    /// How long the formation waits between 2-pixel march steps. Fewer
    /// invaders mean less work for the original hardware, so the formation
    /// speeds up as it is thinned out; later waves start faster too.
    public var marchInterval: Double {
        let alive = Double(max(1, aliensRemaining))
        let load = 0.03 + 0.38 * alive / Double(Arena.alienCount)
        let waveFactor = max(0.55, 1.0 - Double(wave - 1) * 0.05)
        return max(0.09, load * waveFactor)
    }

    public var bombSpeed: Double {
        min(92, 46 + Double(wave) * 5)
    }

    /// Spare cannons shown in the lower-left corner; the one in play is not
    /// counted among the reserves.
    public var displayedLives: Int {
        max(0, lives - 1)
    }

    public var invasionLine: Double {
        Arena.invasionLine
    }

    public var playerDeathProgress: Double {
        deathFraction
    }

    // MARK: - Commands

    public func requestStart() {
        guard phase == .attract || phase == .gameOver else { return }
        startNewGame()
    }

    public func startNewGame() {
        score = 0
        wave = 1
        lives = 3
        nextExtraLife = Arena.extraLifeThreshold
        gameOverReason = nil
        isPaused = false
        elapsed = 0
        explosions.removeAll()
        popups.removeAll()
        events.removeAll()
        prepareWave(readyDuration: 1.8)
        events.append(.gameStart)
    }

    public func togglePause() {
        guard phase == .playing else { return }
        isPaused.toggle()
    }

    public func pause() {
        if phase == .playing {
            isPaused = true
        }
    }

    public func setMovingLeft(_ pressed: Bool) {
        moveLeft = pressed
    }

    public func setMovingRight(_ pressed: Bool) {
        moveRight = pressed
    }

    /// Fire one shot. The original cannon can have only one shot in flight.
    public func fire() {
        guard phase == .playing, !isPaused, playerBullet == nil else { return }
        let x = player.centerX - 0.5
        let y = player.position.y - 5
        playerBullet = Projectile(
            position: Vec2(x: x, y: y), width: 1, height: 5, velocityY: -playerShotSpeed)
        events.append(.playerShot)
    }

    public func drainEvents() -> [GameEvent] {
        let drained = events
        events.removeAll()
        return drained
    }

    // MARK: - Update loop

    public func update(dt rawDeltaTime: Double) {
        guard rawDeltaTime > 0, !isPaused else { return }
        let deltaTime = min(rawDeltaTime, 0.05)
        elapsed += deltaTime
        updateTimedEffects(deltaTime)

        switch phase {
        case .attract, .gameOver:
            break
        case .ready:
            readyRemaining -= deltaTime
            if readyRemaining <= 0 {
                readyRemaining = 0
                phase = .playing
                marchTimer = marchInterval
                bombTimer = 1.8
                mysteryTimer = 5.5 + rng.unitDouble() * 3.0
            }
        case .playing:
            updatePlaying(deltaTime)
        case .playerDying:
            deathElapsed += deltaTime
            deathFraction = min(1, deathElapsed / deathDuration)
            if deathElapsed >= deathDuration {
                finishDeath()
            }
        case .waveComplete:
            waveClearElapsed += deltaTime
            waveClearFraction = min(1, waveClearElapsed / waveClearDuration)
            if waveClearElapsed >= waveClearDuration {
                advanceWave()
            }
        }
    }

    private func updatePlaying(_ deltaTime: Double) {
        updateCannon(deltaTime)
        guard phase == .playing else { return }

        updatePlayerBullet(deltaTime)
        guard phase == .playing else { return }

        updateFormation(deltaTime)
        guard phase == .playing else { return }

        updateBombs(deltaTime)
        guard phase == .playing else { return }

        updateMysteryShip(deltaTime)
        guard phase == .playing else { return }

        updateBombTimer(deltaTime)
    }

    private func updateCannon(_ deltaTime: Double) {
        var horizontal = 0.0
        if moveLeft { horizontal -= 1 }
        if moveRight { horizontal += 1 }
        guard horizontal != 0 else { return }
        player.position.x = clamped(
            player.position.x + horizontal * playerSpeed * deltaTime,
            Arena.playerMinX,
            Arena.playerMaxX
        )
    }

    // MARK: - Player shot

    private func updatePlayerBullet(_ deltaTime: Double) {
        guard var bullet = playerBullet else { return }
        let previous = bullet.rect
        bullet.position.y += bullet.velocityY * deltaTime
        let swept = previous.union(bullet.rect)

        if let index = aliens.firstIndex(where: { $0.alive && swept.intersects($0.rect) }) {
            playerBullet = nil
            destroyAlien(at: index)
            return
        }

        if let ship = mysteryShip, swept.intersects(ship.rect) {
            playerBullet = nil
            hitMysteryShip(ship)
            return
        }

        if hitBunker(with: bullet) {
            playerBullet = nil
            events.append(.bunkerHit)
            return
        }

        if bullet.position.y + bullet.height < 20 {
            playerBullet = nil
            return
        }

        playerBullet = bullet
    }

    private func destroyAlien(at index: Int) {
        guard aliens.indices.contains(index), aliens[index].alive else { return }
        let alien = aliens[index]
        aliens[index].alive = false
        addScore(alien.kind.points)
        explosions.append(
            Explosion(position: alien.center, kind: .alien, duration: 0.38))
        events.append(.alienKilled(kind: alien.kind, points: alien.kind.points))

        if aliensRemaining == 0 {
            beginWaveComplete()
        }
    }

    // MARK: - Invader formation

    private func updateFormation(_ deltaTime: Double) {
        marchTimer -= deltaTime
        var steps = 0
        while marchTimer <= 0, steps < 4, phase == .playing {
            marchTimer += max(0.001, marchInterval)
            stepFormation()
            formationSteps += 1
            animationFrame = (animationFrame + 1) % 2
            events.append(.invaderStep)
            steps += 1
        }
    }

    private func stepFormation() {
        guard aliensRemaining > 0 else {
            beginWaveComplete()
            return
        }

        let living = aliens.filter(\.alive)
        let minX = living.map(\.rect.minX).min() ?? 0
        let maxX = living.map(\.rect.maxX).max() ?? 0
        let wouldCrossEdge =
            marchDirection > 0
            ? maxX + Arena.formationStep > Double(Arena.width - 8)
            : minX - Arena.formationStep < 8

        if wouldCrossEdge {
            for index in aliens.indices where aliens[index].alive {
                aliens[index].position.y += Arena.formationDrop
            }
            marchDirection *= -1
        } else {
            for index in aliens.indices where aliens[index].alive {
                aliens[index].position.x += marchDirection * Arena.formationStep
            }
        }

        eraseBunkersUnderInvaders()

        if aliens.contains(where: { $0.alive && $0.rect.maxY >= Arena.invasionLine }) {
            beginGameOver(reason: .invasion)
        }
    }

    private func eraseBunkersUnderInvaders() {
        for alien in aliens where alien.alive {
            let area = alien.rect
            for index in bunkers.indices where bunkers[index].rect.intersects(area) {
                bunkers[index].erase(overlapping: area)
            }
        }
    }

    // MARK: - Enemy bombs

    private func updateBombTimer(_ deltaTime: Double) {
        bombTimer -= deltaTime
        guard bombTimer <= 0 else { return }
        bombTimer = nextBombDelay()
        guard enemyBombs.count < maximumBombs else { return }
        dropBomb()
    }

    private func nextBombDelay() -> Double {
        let base = max(0.55, 1.62 - Double(wave) * 0.07)
        let pressure = 0.82 + 0.32 * (1 - Double(aliensRemaining) / Double(Arena.alienCount))
        return base * pressure * (0.72 + rng.unitDouble() * 0.72)
    }

    private func dropBomb() {
        var candidates: [Int] = []
        for column in 0..<Arena.alienColumns {
            var lowest: Int?
            for row in 0..<Arena.alienRows {
                let index = row * Arena.alienColumns + column
                if aliens[index].alive {
                    lowest = index
                }
            }
            if let lowest {
                candidates.append(lowest)
            }
        }
        guard !candidates.isEmpty else { return }

        let shooter = aliens[candidates[rng.index(upperBound: candidates.count)]]
        let position = Vec2(
            x: shooter.center.x - 1,
            y: shooter.rect.maxY
        )
        enemyBombs.append(
            Projectile(
                position: position, width: 2, height: 6, velocityY: bombSpeed))
    }

    private func updateBombs(_ deltaTime: Double) {
        var survivors: [Projectile] = []
        for var bomb in enemyBombs {
            bomb.position.y += bomb.velocityY * deltaTime

            if bomb.position.y > Arena.groundLine {
                continue
            }

            if hitBunker(with: bomb) {
                events.append(.bunkerHit)
                continue
            }

            if bomb.rect.intersects(player.rect) {
                beginPlayerDeath()
                return
            }

            survivors.append(bomb)
        }
        enemyBombs = survivors
    }

    private func hitBunker(with projectile: Projectile) -> Bool {
        for index in bunkers.indices where bunkers[index].rect.intersects(projectile.rect) {
            if bunkers[index].damage(at: projectile.tip, radius: 2) {
                return true
            }
        }
        return false
    }

    // MARK: - Mystery ship

    private func updateMysteryShip(_ deltaTime: Double) {
        if var ship = mysteryShip {
            ship.position.x += ship.direction * mysteryShipSpeed * deltaTime
            if ship.position.x < -MysteryShip.width - 4 || ship.position.x > Double(Arena.width) + 4
            {
                mysteryShip = nil
            } else {
                mysteryShip = ship
            }
            return
        }

        mysteryTimer -= deltaTime
        guard mysteryTimer <= 0, aliensRemaining > 0 else { return }
        spawnMysteryShip()
        mysteryTimer = 16.0 + rng.unitDouble() * 11.0
    }

    private func spawnMysteryShip() {
        let value = [50, 100, 150, 300][rng.index(upperBound: 4)]
        let fromLeft = rng.index(upperBound: 2) == 0
        let position = Vec2(
            x: fromLeft ? -MysteryShip.width : Double(Arena.width),
            y: 30
        )
        mysteryShip = MysteryShip(
            position: position, direction: fromLeft ? 1 : -1, points: value)
        events.append(.mysteryAppeared)
    }

    private func hitMysteryShip(_ ship: MysteryShip) {
        addScore(ship.points)
        explosions.append(
            Explosion(position: ship.rect.center, kind: .mystery, duration: 0.55))
        popups.append(
            ScorePopup(position: ship.rect.center, text: "\(ship.points)", duration: 1.5))
        events.append(.mysteryHit(points: ship.points))
        mysteryShip = nil
    }

    // MARK: - Phase changes

    private func beginPlayerDeath() {
        guard phase == .playing else { return }
        phase = .playerDying
        deathElapsed = 0
        deathFraction = 0
        playerBullet = nil
        enemyBombs.removeAll()
        mysteryShip = nil
        explosions.append(
            Explosion(position: player.rect.center, kind: .player, duration: deathDuration))
        events.append(.playerHit)
    }

    private func finishDeath() {
        deathFraction = 1
        lives -= 1
        playerBullet = nil
        enemyBombs.removeAll()
        mysteryShip = nil

        if lives <= 0 {
            lives = 0
            beginGameOver(reason: .livesExhausted)
            return
        }

        player = Cannon(position: Self.centeredPlayerPosition())
        moveLeft = false
        moveRight = false
        deathElapsed = 0
        deathFraction = 0
        marchTimer = marchInterval
        bombTimer = 2.0
        phase = .ready
        readyRemaining = 1.5
    }

    private func beginWaveComplete() {
        guard phase == .playing else { return }
        phase = .waveComplete
        waveClearElapsed = 0
        waveClearFraction = 0
        playerBullet = nil
        enemyBombs.removeAll()
        mysteryShip = nil
        events.append(.waveComplete)
    }

    private func advanceWave() {
        wave += 1
        prepareWave(readyDuration: 1.6)
    }

    private func beginGameOver(reason: GameOverReason) {
        guard phase != .gameOver else { return }
        phase = .gameOver
        gameOverReason = reason
        isPaused = false
        playerBullet = nil
        enemyBombs.removeAll()
        mysteryShip = nil
        events.append(.gameOver(reason: reason))
    }

    // MARK: - Setup

    private func prepareWave(readyDuration: Double) {
        aliens = Self.makeFormation()
        bunkers = Self.makeBunkers()
        player = Cannon(position: Self.centeredPlayerPosition())
        playerBullet = nil
        enemyBombs.removeAll()
        mysteryShip = nil

        marchDirection = 1
        animationFrame = 0
        formationSteps = 0
        marchTimer = marchInterval
        bombTimer = 1.8
        mysteryTimer = 7.0
        moveLeft = false
        moveRight = false
        deathElapsed = 0
        deathFraction = 0
        waveClearElapsed = 0
        waveClearFraction = 0
        gameOverReason = nil
        phase = .ready
        readyRemaining = readyDuration
    }

    private func addScore(_ points: Int) {
        score += points
        if score > highScore {
            highScore = score
        }
        while score >= nextExtraLife {
            lives += 1
            nextExtraLife += 5_000
            events.append(.extraLife)
        }
    }

    private func updateTimedEffects(_ deltaTime: Double) {
        for index in explosions.indices {
            explosions[index].remaining -= deltaTime
        }
        explosions.removeAll { $0.remaining <= 0 }

        for index in popups.indices {
            popups[index].remaining -= deltaTime
        }
        popups.removeAll { $0.remaining <= 0 }
    }

    private static func centeredPlayerPosition() -> Vec2 {
        Vec2(
            x: (Double(Arena.width) - Double(Arena.playerWidth)) * 0.5,
            y: Arena.playerTop
        )
    }

    private static func makeFormation() -> [Alien] {
        var formation: [Alien] = []
        formation.reserveCapacity(Arena.alienCount)
        for row in 0..<Arena.alienRows {
            let kind: AlienKind
            switch row {
            case 0: kind = .squid
            case 1, 2: kind = .crab
            default: kind = .octopus
            }
            for column in 0..<Arena.alienColumns {
                let centerX =
                    Arena.formationFirstCenterX + Double(column) * Arena.columnSpacing
                let topY = Arena.formationTop + Double(row) * Arena.rowSpacing
                formation.append(
                    Alien(
                        kind: kind,
                        position: Vec2(
                            x: centerX - Double(kind.width) * 0.5, y: topY)
                    )
                )
            }
        }
        return formation
    }

    private static func makeBunkers() -> [Bunker] {
        Arena.bunkerOrigins.map { Bunker(originX: $0, originY: Arena.bunkerTop) }
    }
}

extension PixelRect {
    fileprivate func union(_ other: PixelRect) -> PixelRect {
        let minX = Swift.min(self.minX, other.minX)
        let minY = Swift.min(self.minY, other.minY)
        let maxX = Swift.max(self.maxX, other.maxX)
        let maxY = Swift.max(self.maxY, other.maxY)
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
