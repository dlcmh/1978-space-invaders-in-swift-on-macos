import Foundation

/// Immediate-mode triangle canvas. Every primitive is expanded into
/// triangles so the renderer can submit the whole frame in one draw call.
final class Canvas {
    static let floatsPerVertex = 6

    private(set) var vertices: [Float] = []

    init(reservedVertices: Int = 65_536) {
        vertices.reserveCapacity(reservedVertices * Canvas.floatsPerVertex)
    }

    var vertexCount: Int {
        vertices.count / Canvas.floatsPerVertex
    }

    func reset() {
        vertices.removeAll(keepingCapacity: true)
    }

    func addVertex(_ x: Float, _ y: Float, _ color: Color) {
        vertices.append(x)
        vertices.append(y)
        vertices.append(color.x)
        vertices.append(color.y)
        vertices.append(color.z)
        vertices.append(color.w)
    }

    func addTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, color: Color) {
        addVertex(Float(a.x), Float(a.y), color)
        addVertex(Float(b.x), Float(b.y), color)
        addVertex(Float(c.x), Float(c.y), color)
    }

    func addQuad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, color: Color) {
        addTriangle(a, b, c, color: color)
        addTriangle(a, c, d, color: color)
    }

    func addRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color) {
        guard width > 0, height > 0 else { return }
        let topLeft = CGPoint(x: x, y: y)
        let topRight = CGPoint(x: x + width, y: y)
        let bottomRight = CGPoint(x: x + width, y: y + height)
        let bottomLeft = CGPoint(x: x, y: y + height)
        addQuad(topLeft, topRight, bottomRight, bottomLeft, color: color)
    }

    func addCircle(center: CGPoint, radius: CGFloat, color: Color, segments: Int = 28) {
        guard radius > 0 else { return }
        let count = max(segments, 8)
        var previous = CGPoint(x: center.x + radius, y: center.y)
        for index in 1...count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let current = CGPoint(
                x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            addTriangle(center, previous, current, color: color)
            previous = current
        }
    }

    func addEllipse(
        center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, color: Color, segments: Int = 28
    ) {
        guard radiusX > 0, radiusY > 0 else { return }
        let count = max(segments, 8)
        var previous = CGPoint(x: center.x + radiusX, y: center.y)
        for index in 1...count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let current = CGPoint(
                x: center.x + cos(angle) * radiusX, y: center.y + sin(angle) * radiusY)
            addTriangle(center, previous, current, color: color)
            previous = current
        }
    }

    func addRing(
        center: CGPoint, radius: CGFloat, thickness: CGFloat, color: Color, segments: Int = 40
    ) {
        guard radius > 0, thickness > 0 else { return }
        let count = max(segments, 12)
        let inner = max(0, radius - thickness)
        var previousOuter = CGPoint(x: center.x + radius, y: center.y)
        var previousInner = CGPoint(x: center.x + inner, y: center.y)
        for index in 1...count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let c = cos(angle)
            let s = sin(angle)
            let currentOuter = CGPoint(x: center.x + c * radius, y: center.y + s * radius)
            let currentInner = CGPoint(x: center.x + c * inner, y: center.y + s * inner)
            addQuad(previousOuter, currentOuter, currentInner, previousInner, color: color)
            previousOuter = currentOuter
            previousInner = currentInner
        }
    }

    func addLine(
        from start: CGPoint, to end: CGPoint, thickness: CGFloat, color: Color, rounded: Bool = true
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.0001, thickness > 0 else { return }
        let nx = -dy / length * thickness * 0.5
        let ny = dx / length * thickness * 0.5

        let a = CGPoint(x: start.x + nx, y: start.y + ny)
        let b = CGPoint(x: end.x + nx, y: end.y + ny)
        let c = CGPoint(x: end.x - nx, y: end.y - ny)
        let d = CGPoint(x: start.x - nx, y: start.y - ny)
        addQuad(a, b, c, d, color: color)

        if rounded {
            addCircle(center: start, radius: thickness * 0.5, color: color, segments: 10)
            addCircle(center: end, radius: thickness * 0.5, color: color, segments: 10)
        }
    }

    func addPolyline(_ points: [CGPoint], thickness: CGFloat, color: Color) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            addLine(from: points[index], to: points[index + 1], thickness: thickness, color: color)
        }
    }

    /// Filled pie/wedge segment, used for Pac-Man's body.
    func addPie(
        center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, color: Color,
        segments: Int = 50
    ) {
        guard radius > 0, endAngle > startAngle else { return }
        let steps = max(segments, 6)
        var previous = CGPoint(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius)
        for index in 1...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let angle = startAngle + (endAngle - startAngle) * t
            let current = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius)
            addTriangle(center, previous, current, color: color)
            previous = current
        }
    }

    func addPolygon(points: [CGPoint], color: Color) {
        guard points.count >= 3 else { return }
        let center = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(
                x: partial.x + point.x / CGFloat(points.count),
                y: partial.y + point.y / CGFloat(points.count))
        }
        for index in 0..<points.count {
            let next = (index + 1) % points.count
            addTriangle(center, points[index], points[next], color: color)
        }
    }

    func addGlowCircle(center: CGPoint, radius: CGFloat, color: Color, layers: Int = 3) {
        for layer in 0..<layers {
            let factor = CGFloat(layer + 1) / CGFloat(layers)
            var faded = color
            faded.w *= Float(1.0 - factor * 0.55)
            addCircle(
                center: center, radius: radius * (1 + factor * 0.55), color: faded, segments: 24)
        }
    }
}
