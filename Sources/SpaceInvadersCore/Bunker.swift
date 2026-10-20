import Foundation

/// One destructible defence bunker. The shield is stored as a 22 × 16 grid of
/// solid cells in arcade-pixel space, so a hit can remove a small, irregular
/// bite instead of deleting the whole bunker. The simulation owns the cells;
/// the renderer only displays them.
public struct Bunker: Sendable {
    public static let width = 22
    public static let height = 16
    public static let initialCellCount: Int = makeCells().reduce(0) { $0 + ($1 ? 1 : 0) }

    public let originX: Int
    public let originY: Int
    public private(set) var cells: [Bool]

    public init(originX: Int, originY: Int) {
        self.originX = originX
        self.originY = originY
        self.cells = Bunker.makeCells()
    }

    public var rect: PixelRect {
        PixelRect(
            x: Double(originX), y: Double(originY),
            width: Double(Bunker.width), height: Double(Bunker.height))
    }

    public var remainingCells: Int {
        cells.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    public var isIntact: Bool {
        remainingCells == Bunker.initialCellCount
    }

    public var isDestroyed: Bool {
        remainingCells == 0
    }

    public func isFilled(column: Int, row: Int) -> Bool {
        guard column >= 0, column < Bunker.width, row >= 0, row < Bunker.height else {
            return false
        }
        return cells[row * Bunker.width + column]
    }

    public func cellRect(column: Int, row: Int) -> PixelRect {
        PixelRect(
            x: Double(originX + column), y: Double(originY + row),
            width: 1, height: 1)
    }

    /// Remove every solid cell that overlaps `area`. Used both by projectiles
    /// and by invaders that march down through a bunker.
    @discardableResult
    public mutating func erase(overlapping area: PixelRect) -> Bool {
        var changed = false
        for row in 0..<Bunker.height {
            for column in 0..<Bunker.width {
                let index = row * Bunker.width + column
                guard cells[index] else { continue }
                guard cellRect(column: column, row: row).intersects(area) else { continue }
                cells[index] = false
                changed = true
            }
        }
        return changed
    }

    /// Bite a roughly circular hole around a projectile impact, with a little
    /// extra chipping above the centre so repeated shots do not leave a
    /// perfect tunnel.
    @discardableResult
    public mutating func damage(at point: Vec2, radius: Int = 2) -> Bool {
        let impactColumn = Int(floor(point.x)) - originX
        let impactRow = Int(floor(point.y)) - originY
        var changed = false

        for rowOffset in -radius...radius {
            for columnOffset in -radius...radius
            where
                columnOffset * columnOffset + rowOffset * rowOffset <= radius * radius
            {
                let column = impactColumn + columnOffset
                let row = impactRow + rowOffset
                let index = row * Bunker.width + column
                guard column >= 0, column < Bunker.width, row >= 0, row < Bunker.height else {
                    continue
                }
                if cells[index] {
                    cells[index] = false
                    changed = true
                }
            }
        }

        for (columnOffset, rowOffset) in [(-1, -radius - 1), (radius + 1, -1), (0, -radius - 1)] {
            let column = impactColumn + columnOffset
            let row = impactRow + rowOffset
            guard column >= 0, column < Bunker.width, row >= 0, row < Bunker.height else {
                continue
            }
            let index = row * Bunker.width + column
            if cells[index] {
                cells[index] = false
                changed = true
            }
        }

        return changed
    }

    private static func makeCells() -> [Bool] {
        let rows = [
            "..##################..",
            ".####################.",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "######################",
            "#########....#########",
            "#######........#######",
            "#####............#####",
        ]
        precondition(rows.count == height)
        precondition(rows.allSatisfy { $0.count == width })
        return rows.flatMap { row in row.map { $0 == "#" } }
    }
}
