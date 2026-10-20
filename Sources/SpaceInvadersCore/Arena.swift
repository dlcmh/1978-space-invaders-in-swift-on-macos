import Foundation

/// Fixed dimensions and shared rules for the 1978 arcade playfield. The
/// simulation is expressed in the original 224 × 256 pixel coordinate space;
/// the renderer scales that space to the window.
public enum Arena {
    public static let width = 224
    public static let height = 256

    public static let playerWidth = 13
    public static let playerHeight = 8
    public static let playerTop = 224.0
    public static let playerMinX = 8.0
    public static let playerMaxX = 203.0

    public static let groundLine = 236.0
    public static let invasionLine = 216.0

    public static let bunkerCount = 4
    public static let bunkerTop = 188
    public static let bunkerOrigins = [24, 75, 126, 177]

    public static let alienRows = 5
    public static let alienColumns = 11
    public static let alienCount = alienRows * alienColumns
    public static let formationFirstCenterX = 34.0
    public static let formationTop = 44.0
    public static let columnSpacing = 16.0
    public static let rowSpacing = 14.0
    public static let formationStep = 2.0
    public static let formationDrop = 8.0

    public static let extraLifeThreshold = 1_000
}

public enum AlienKind: Int, CaseIterable, Sendable {
    case squid
    case crab
    case octopus

    /// Arcade point values: top-row squid, middle crab, bottom octopus.
    public var points: Int {
        switch self {
        case .squid: return 30
        case .crab: return 20
        case .octopus: return 10
        }
    }

    public var width: Int {
        switch self {
        case .squid: return 8
        case .crab: return 11
        case .octopus: return 12
        }
    }

    public var height: Int { 8 }

    public var displayName: String {
        switch self {
        case .squid: return "SQUID"
        case .crab: return "CRAB"
        case .octopus: return "OCTOPUS"
        }
    }
}

public struct Alien: Sendable {
    public var kind: AlienKind
    public var position: Vec2
    public var alive: Bool

    public init(kind: AlienKind, position: Vec2, alive: Bool = true) {
        self.kind = kind
        self.position = position
        self.alive = alive
    }

    public var rect: PixelRect {
        PixelRect(
            x: position.x, y: position.y,
            width: Double(kind.width), height: Double(kind.height))
    }

    public var center: Vec2 {
        Vec2(
            x: position.x + Double(kind.width) * 0.5,
            y: position.y + Double(kind.height) * 0.5)
    }
}

public struct Cannon: Sendable {
    public var position: Vec2

    public init(position: Vec2) {
        self.position = position
    }

    public var rect: PixelRect {
        PixelRect(
            x: position.x, y: position.y,
            width: Double(Arena.playerWidth), height: Double(Arena.playerHeight))
    }

    public var centerX: Double {
        position.x + Double(Arena.playerWidth) * 0.5
    }
}

public struct Projectile: Sendable {
    public var position: Vec2
    public var width: Double
    public var height: Double
    public var velocityY: Double

    public init(position: Vec2, width: Double, height: Double, velocityY: Double) {
        self.position = position
        self.width = width
        self.height = height
        self.velocityY = velocityY
    }

    public var rect: PixelRect {
        PixelRect(x: position.x, y: position.y, width: width, height: height)
    }

    /// The leading edge of the projectile in the direction of travel.
    public var tipY: Double {
        velocityY < 0 ? position.y : position.y + height
    }

    public var tip: Vec2 {
        Vec2(x: position.x + width * 0.5, y: tipY)
    }
}

public struct MysteryShip: Sendable {
    public var position: Vec2
    public var direction: Double
    public var points: Int

    public init(position: Vec2, direction: Double, points: Int) {
        self.position = position
        self.direction = direction
        self.points = points
    }

    public static let width = 16.0
    public static let height = 7.0

    public var rect: PixelRect {
        PixelRect(
            x: position.x, y: position.y, width: MysteryShip.width, height: MysteryShip.height)
    }
}

public enum ExplosionKind: Sendable {
    case alien
    case mystery
    case player
}

public struct Explosion: Sendable {
    public var position: Vec2
    public var kind: ExplosionKind
    public var remaining: Double
    public var duration: Double

    public init(position: Vec2, kind: ExplosionKind, duration: Double) {
        self.position = position
        self.kind = kind
        self.remaining = duration
        self.duration = duration
    }

    public var progress: Double {
        guard duration > 0 else { return 1 }
        return 1 - max(0, min(1, remaining / duration))
    }
}

public struct ScorePopup: Sendable {
    public var position: Vec2
    public var text: String
    public var remaining: Double
    public var duration: Double

    public init(position: Vec2, text: String, duration: Double) {
        self.position = position
        self.text = text
        self.remaining = duration
        self.duration = duration
    }

    public var progress: Double {
        guard duration > 0 else { return 1 }
        return 1 - max(0, min(1, remaining / duration))
    }
}

public enum GamePhase: Equatable, Sendable {
    case attract
    case ready
    case playing
    case playerDying
    case waveComplete
    case gameOver
}

public enum GameOverReason: Equatable, Sendable {
    case livesExhausted
    case invasion
}

public enum GameEvent: Equatable, Sendable {
    case gameStart
    case playerShot
    case invaderStep
    case alienKilled(kind: AlienKind, points: Int)
    case mysteryAppeared
    case mysteryHit(points: Int)
    case bunkerHit
    case playerHit
    case extraLife
    case waveComplete
    case gameOver(reason: GameOverReason)
}
