import Foundation
import MetalKit
import SpaceInvadersCore
import simd

typealias Color = SIMD4<Float>

enum Palette {
    static let background = Color(0.003, 0.006, 0.016, 1)
    static let strip = Color(0.008, 0.014, 0.034, 1)
    static let screen = Color(0.005, 0.011, 0.027, 1)
    static let screenGlow = Color(0.05, 0.13, 0.28, 0.08)
    static let frame = Color(0.16, 0.36, 0.72, 0.55)
    static let frameFaint = Color(0.10, 0.22, 0.50, 0.30)
    static let hud = Color(0.38, 0.63, 0.92, 1)
    static let hudDim = Color(0.23, 0.42, 0.68, 1)
    static let hudFaint = Color(0.15, 0.28, 0.50, 1)
    static let white = Color(0.93, 0.98, 1.0, 1)
    static let squid = Color(1.0, 0.36, 0.72, 1)
    static let crab = Color(0.32, 0.93, 1.0, 1)
    static let octopus = Color(0.52, 1.0, 0.52, 1)
    static let player = Color(0.55, 1.0, 0.64, 1)
    static let bunker = Color(0.23, 0.88, 0.38, 1)
    static let bunkerGlow = Color(0.16, 0.72, 0.30, 0.20)
    static let ufo = Color(1.0, 0.48, 0.90, 1)
    static let bullet = Color(0.80, 1.0, 1.0, 1)
    static let bomb = Color(1.0, 0.56, 0.22, 1)
    static let red = Color(1.0, 0.24, 0.30, 1)
    static let yellow = Color(1.0, 0.88, 0.35, 1)
    static let star = Color(0.58, 0.76, 1.0, 1)
}

final class Renderer {
    static let designWidth: CGFloat = 896
    static let designHeight: CGFloat = 1120
    static let playfieldOrigin = CGPoint(x: 0, y: 48)
    static let unit: CGFloat = 4

    private struct Uniforms {
        var viewportSize: SIMD2<Float>
        var scale: SIMD2<Float>
        var offset: SIMD2<Float>
    }

    private struct Star {
        var position: CGPoint
        var size: CGFloat
        var phase: Double
        var alpha: Float
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let canvas = Canvas(reservedVertices: 140_000)
    private lazy var font = PixelFont(canvas: canvas)
    private var vertexBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    private var stars: [Star] = []

    var isMuted = false

    init(view: MTKView) throws {
        guard let device = view.device else {
            throw RendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.couldNotCreateCommandQueue
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalShaderSource.source, options: nil)
        } catch {
            print("Metal shader compilation failed:\n\(error)")
            throw RendererError.shaderCompilationFailed
        }
        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
            let fragmentFunction = library.makeFunction(name: "fragment_main")
        else {
            throw RendererError.shaderCompilationFailed
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Invaders 2D Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            throw RendererError.pipelineCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipeline

        let initialCapacity = 160_000 * Canvas.floatsPerVertex * MemoryLayout<Float>.stride
        for _ in 0..<3 {
            guard
                let buffer = device.makeBuffer(length: initialCapacity, options: .storageModeShared)
            else {
                throw RendererError.couldNotCreateVertexBuffer
            }
            vertexBuffers.append(buffer)
        }

        buildStarfield()
    }

    func render(game: SpaceInvadersGame, in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor
        else {
            return
        }

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.003, green: 0.006, blue: 0.016, alpha: 1.0)

        canvas.reset()
        drawBackdrop()
        drawStars(game: game)
        drawPlayfieldFrame()
        drawBunkers(game: game)
        drawAliens(game: game)
        drawMysteryShip(game: game)
        drawProjectiles(game: game)
        drawPlayer(game: game)
        drawExplosions(game: game)
        drawPopups(game: game)
        drawHUD(game: game)
        drawOverlays(game: game)
        drawScanlines()

        let vertexCount = canvas.vertexCount
        guard vertexCount > 0 else { return }

        inFlightSemaphore.wait()

        let byteCount = canvas.vertices.count * MemoryLayout<Float>.stride
        if byteCount > vertexBuffers[frameIndex].length {
            let newLength = max(byteCount, vertexBuffers[frameIndex].length * 2)
            guard
                let largerBuffer = device.makeBuffer(length: newLength, options: .storageModeShared)
            else {
                inFlightSemaphore.signal()
                return
            }
            vertexBuffers[frameIndex] = largerBuffer
        }
        let buffer = vertexBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % vertexBuffers.count

        canvas.vertices.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
            }
        }

        let drawableSize = view.drawableSize
        let scale = min(
            Float(drawableSize.width) / Float(Self.designWidth),
            Float(drawableSize.height) / Float(Self.designHeight))
        let offsetX = (Float(drawableSize.width) - Float(Self.designWidth) * scale) * 0.5
        let offsetY = (Float(drawableSize.height) - Float(Self.designHeight) * scale) * 0.5

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            scale: SIMD2<Float>(scale, scale),
            offset: SIMD2<Float>(offsetX, offsetY)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        encoder.label = "Invaders Frame"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Coordinate helpers

    private func screenPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(
            x: Self.playfieldOrigin.x + CGFloat(x) * Self.unit,
            y: Self.playfieldOrigin.y + CGFloat(y) * Self.unit)
    }

    private func screenPoint(_ point: Vec2) -> CGPoint {
        screenPoint(x: point.x, y: point.y)
    }

    private func screenRect(_ rect: PixelRect) -> CGRect {
        CGRect(
            x: Self.playfieldOrigin.x + CGFloat(rect.x) * Self.unit,
            y: Self.playfieldOrigin.y + CGFloat(rect.y) * Self.unit,
            width: CGFloat(rect.width) * Self.unit,
            height: CGFloat(rect.height) * Self.unit)
    }

    private func worldRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
        screenRect(PixelRect(x: x, y: y, width: width, height: height))
    }

    // MARK: - Background

    private func buildStarfield() {
        var rng = SplitMix64(seed: 0x57A2_F1E1_D197_8ABC)
        stars.reserveCapacity(110)
        for _ in 0..<110 {
            let x = CGFloat(8 + rng.index(upperBound: 880))
            let y = CGFloat(70 + rng.index(upperBound: 930))
            let size: CGFloat = rng.index(upperBound: 5) == 0 ? 2.5 : 1.4
            let phase = rng.unitDouble() * .pi * 2
            let alpha = Float(0.25 + rng.unitDouble() * 0.55)
            stars.append(
                Star(position: CGPoint(x: x, y: y), size: size, phase: phase, alpha: alpha))
        }
    }

    private func drawBackdrop() {
        canvas.addRect(
            x: 0, y: 0, width: Self.designWidth, height: Self.designHeight,
            color: Palette.background)
        canvas.addRect(
            x: 0, y: 0, width: Self.designWidth, height: 48, color: Palette.strip)
        canvas.addRect(
            x: 0, y: Self.designHeight - 48, width: Self.designWidth, height: 48,
            color: Palette.strip)
        canvas.addRect(
            x: Self.playfieldOrigin.x, y: Self.playfieldOrigin.y,
            width: Self.designWidth, height: CGFloat(Arena.height) * Self.unit,
            color: Palette.screen)

        // A soft instrument-panel glow behind the playfield.
        let center = CGPoint(
            x: Self.designWidth * 0.5,
            y: Self.playfieldOrigin.y + CGFloat(Arena.height) * Self.unit * 0.5)
        canvas.addCircle(center: center, radius: 420, color: Palette.screenGlow, segments: 40)
        canvas.addCircle(
            center: CGPoint(x: center.x, y: center.y - 180), radius: 240,
            color: Color(0.10, 0.25, 0.55, 0.035), segments: 32)
    }

    private func drawStars(game: SpaceInvadersGame) {
        for star in stars {
            let twinkle = 0.55 + 0.45 * abs(sin(game.elapsed * 0.8 + star.phase))
            var color = Palette.star
            color.w = star.alpha * Float(twinkle)
            canvas.addRect(
                x: star.position.x, y: star.position.y,
                width: star.size, height: star.size, color: color)
        }
    }

    private func drawPlayfieldFrame() {
        let top = Self.playfieldOrigin.y
        let bottom = top + CGFloat(Arena.height) * Self.unit
        canvas.addRect(
            x: 0, y: top - 1, width: Self.designWidth, height: 2, color: Palette.frame)
        canvas.addRect(
            x: 0, y: bottom - 1, width: Self.designWidth, height: 2, color: Palette.frame)
        canvas.addRect(
            x: 0, y: top + 220, width: 2, height: bottom - top - 440,
            color: Color(0.14, 0.30, 0.62, 0.20))
        canvas.addRect(
            x: Self.designWidth - 2, y: top + 220, width: 2, height: bottom - top - 440,
            color: Color(0.14, 0.30, 0.62, 0.20))

        let bracket: CGFloat = 34
        let inset: CGFloat = 12
        canvas.addLine(
            from: CGPoint(x: inset, y: top + inset),
            to: CGPoint(x: inset + bracket, y: top + inset),
            thickness: 2, color: Palette.frameFaint, rounded: false)
        canvas.addLine(
            from: CGPoint(x: inset, y: top + inset),
            to: CGPoint(x: inset, y: top + inset + bracket),
            thickness: 2, color: Palette.frameFaint, rounded: false)
        canvas.addLine(
            from: CGPoint(x: Self.designWidth - inset, y: top + inset),
            to: CGPoint(x: Self.designWidth - inset - bracket, y: top + inset),
            thickness: 2, color: Palette.frameFaint, rounded: false)
        canvas.addLine(
            from: CGPoint(x: Self.designWidth - inset, y: top + inset),
            to: CGPoint(x: Self.designWidth - inset, y: top + inset + bracket),
            thickness: 2, color: Palette.frameFaint, rounded: false)
    }

    // MARK: - Playfield objects

    private func drawBunkers(game: SpaceInvadersGame) {
        for bunker in game.bunkers {
            if !bunker.isDestroyed {
                let rect = screenRect(bunker.rect).insetBy(dx: -5, dy: -5)
                canvas.addRect(
                    x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                    color: Color(0.10, 0.50, 0.20, 0.025))
            }
            for row in 0..<Bunker.height {
                for column in 0..<Bunker.width {
                    guard bunker.isFilled(column: column, row: row) else { continue }
                    let rect = screenRect(bunker.cellRect(column: column, row: row))
                    canvas.addRect(
                        x: rect.minX, y: rect.minY,
                        width: rect.width + 0.2, height: rect.height + 0.2,
                        color: Palette.bunker)
                }
            }
            // Highlight the upper lip of the shield.
            for column in 0..<Bunker.width where bunker.isFilled(column: column, row: 1) {
                let rect = screenRect(bunker.cellRect(column: column, row: 1))
                canvas.addRect(
                    x: rect.minX, y: rect.minY, width: rect.width,
                    height: 1.2, color: Color(0.65, 1.0, 0.72, 0.65))
            }
        }
    }

    private func drawAliens(game: SpaceInvadersGame) {
        let frame: Int
        if game.phase == .attract || game.phase == .gameOver {
            frame = Int(game.elapsed * 2.2) % 2
        } else {
            frame = game.animationFrame
        }

        for alien in game.aliens where alien.alive {
            let color = color(for: alien.kind)
            let rows = SpriteArt.frames(for: alien.kind)[frame % 2]
            drawSprite(rows, at: screenPoint(alien.position), pixelSize: Self.unit, color: color)
        }
    }

    private func drawMysteryShip(game: SpaceInvadersGame) {
        guard let ship = game.mysteryShip else { return }
        let center = screenPoint(ship.rect.center)
        canvas.addCircle(
            center: center, radius: 32, color: Color(1.0, 0.40, 0.85, 0.09), segments: 22)
        drawSprite(
            SpriteArt.mysteryShip, at: screenPoint(ship.position), pixelSize: Self.unit,
            color: Palette.ufo)
        let blink = 0.55 + 0.45 * abs(sin(game.elapsed * 8))
        var light = Palette.white
        light.w = Float(blink)
        canvas.addRect(
            x: center.x - 2, y: center.y - 13, width: 4, height: 3, color: light)
    }

    private func drawProjectiles(game: SpaceInvadersGame) {
        if let bullet = game.playerBullet {
            let rect = screenRect(bullet.rect)
            canvas.addRect(
                x: rect.minX - 5, y: rect.minY - 6, width: rect.width + 10,
                height: rect.height + 10, color: Color(0.35, 1.0, 0.85, 0.11))
            canvas.addRect(
                x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                color: Palette.bullet)
            canvas.addRect(
                x: rect.minX - 2, y: rect.minY - 4, width: rect.width + 4, height: 6,
                color: Color(0.55, 1.0, 0.92, 0.38))
        }

        for bomb in game.enemyBombs {
            let rect = screenRect(bomb.rect)
            let centerX = rect.midX
            let phase = Int((game.elapsed * 22 + bomb.position.y * 0.3) * 10) % 2
            canvas.addRect(
                x: centerX - 8, y: rect.minY - 6, width: 16, height: rect.height + 12,
                color: Color(1.0, 0.35, 0.12, 0.08))
            for index in 0..<4 {
                let segY = rect.minY + CGFloat(index) * rect.height / 4
                let offset: CGFloat = (index + phase) % 2 == 0 ? -3 : 1
                canvas.addRect(
                    x: centerX + offset, y: segY, width: 4, height: rect.height / 3.2,
                    color: Palette.bomb)
                canvas.addRect(
                    x: centerX + offset - 2, y: segY + 1, width: 8, height: 2,
                    color: Color(1.0, 0.75, 0.40, 0.75))
            }
        }
    }

    private func drawPlayer(game: SpaceInvadersGame) {
        guard game.phase != .playerDying else { return }
        let origin = screenPoint(game.player.position)
        let center = screenPoint(game.player.rect.center)
        drawSprite(SpriteArt.cannon, at: origin, pixelSize: Self.unit, color: Palette.player)
        let flicker = 0.55 + 0.45 * abs(sin(game.elapsed * 9))
        var flame = Color(0.55, 1.0, 0.75, 0.65)
        flame.w *= Float(flicker)
        canvas.addRect(
            x: center.x - 5, y: origin.y + 34, width: 10, height: 3, color: flame)
    }

    private func drawExplosions(game: SpaceInvadersGame) {
        for explosion in game.explosions {
            let progress = CGFloat(explosion.progress)
            let center = screenPoint(explosion.position)
            let alpha = Float(max(0, 1 - progress))
            let radius: CGFloat
            switch explosion.kind {
            case .alien: radius = 5 + 22 * progress
            case .mystery: radius = 8 + 38 * progress
            case .player: radius = 10 + 58 * progress
            }
            let color: Color
            switch explosion.kind {
            case .alien: color = Palette.yellow
            case .mystery: color = Palette.ufo
            case .player: color = Palette.player
            }
            var faded = color
            faded.w = alpha

            let rays = explosion.kind == .player ? 16 : 8
            for index in 0..<rays {
                let angle =
                    CGFloat(index) / CGFloat(rays) * .pi * 2
                    + (explosion.kind == .player ? progress * 0.8 : 0)
                let inner = radius * 0.18
                let outer = radius * (index % 2 == 0 ? 1.0 : 0.62)
                canvas.addLine(
                    from: CGPoint(
                        x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner),
                    to: CGPoint(
                        x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer),
                    thickness: explosion.kind == .player ? 3.2 : 2.4,
                    color: faded,
                    rounded: false)
            }
            var core = Palette.white
            core.w = alpha * 0.85
            canvas.addCircle(
                center: center, radius: max(1, radius * 0.18), color: core, segments: 12)

            if explosion.kind == .player {
                for index in 0..<12 {
                    let angle = CGFloat(index) / 12 * .pi * 2 + 0.3
                    let distance = radius * (0.6 + CGFloat(index % 4) * 0.12)
                    var debris = index % 2 == 0 ? Palette.player : Palette.white
                    debris.w = alpha * 0.8
                    canvas.addRect(
                        x: center.x + cos(angle) * distance,
                        y: center.y + sin(angle) * distance,
                        width: 4 + CGFloat(index % 3) * 2,
                        height: 4 + CGFloat(index % 2) * 3,
                        color: debris)
                }
            }
        }
    }

    private func drawPopups(game: SpaceInvadersGame) {
        for popup in game.popups {
            let center = screenPoint(popup.position)
            var color = Palette.yellow
            color.w = Float(max(0, 1 - popup.progress))
            let y = center.y - 18 - CGFloat(popup.progress) * 24
            font.draw(
                popup.text, x: center.x, y: y, pixelSize: 2.2, color: color, alignment: .center)
        }
    }

    // MARK: - HUD

    private func drawHUD(game: SpaceInvadersGame) {
        font.draw(
            "SPACE INVADERS", x: 24, y: 15, pixelSize: 2.1, color: Palette.white)
        font.draw(
            "METAL ARCADE", x: Self.designWidth - 24, y: 15, pixelSize: 1.6,
            color: Palette.hudDim, alignment: .right)
        font.draw(
            "1978", x: Self.designWidth * 0.5, y: 17, pixelSize: 1.4,
            color: Palette.hudFaint, alignment: .center)

        let hudTop = Self.playfieldOrigin.y + 6 * Self.unit
        font.draw("SCORE", x: 48, y: hudTop, pixelSize: 1.55, color: Palette.hudDim)
        font.draw(
            paddedScore(game.score), x: 48, y: hudTop + 18, pixelSize: 2.75,
            color: Palette.white)
        font.draw(
            "HI-SCORE", x: Self.designWidth * 0.5, y: hudTop, pixelSize: 1.55,
            color: Palette.hudDim, alignment: .center)
        font.draw(
            paddedScore(game.highScore), x: Self.designWidth * 0.5, y: hudTop + 18,
            pixelSize: 2.75, color: Palette.yellow, alignment: .center)
        font.draw(
            "WAVE", x: Self.designWidth - 48, y: hudTop, pixelSize: 1.55,
            color: Palette.hudDim, alignment: .right)
        font.draw(
            String(format: "%02d", min(game.wave, 99)), x: Self.designWidth - 48,
            y: hudTop + 18, pixelSize: 2.75, color: Palette.white, alignment: .right)

        let groundY = Self.playfieldOrigin.y + CGFloat(Arena.groundLine) * Self.unit
        canvas.addRect(
            x: 24, y: groundY, width: Self.designWidth - 48, height: 2,
            color: Color(0.28, 0.68, 0.48, 0.70))
        canvas.addRect(
            x: 24, y: groundY + 3, width: Self.designWidth - 48, height: 1,
            color: Color(0.18, 0.48, 0.36, 0.35))

        font.draw(
            "LIVES", x: 28, y: groundY + 17, pixelSize: 1.3, color: Palette.hudDim)
        let shownLives = min(game.displayedLives, 5)
        for index in 0..<shownLives {
            let x = 84 + CGFloat(index) * 34
            drawSpriteScreen(
                SpriteArt.cannon, at: CGPoint(x: x, y: groundY + 12), pixelSize: 2,
                color: Palette.player)
        }
        if game.displayedLives > 5 {
            font.draw(
                "+\(game.displayedLives - 5)", x: 84 + 5 * 34, y: groundY + 18,
                pixelSize: 1.6, color: Palette.player)
        }

        font.draw(
            "CREDIT 1", x: Self.designWidth - 28, y: groundY + 18, pixelSize: 1.5,
            color: Palette.yellow, alignment: .right)
        font.draw(
            "WAVE \(game.wave)", x: Self.designWidth * 0.5, y: groundY + 18,
            pixelSize: 1.5, color: Palette.hudDim, alignment: .center)

        font.draw(
            "ARROWS / A D  MOVE     SPACE  FIRE     P  PAUSE     M  \(isMuted ? "SOUND OFF" : "MUTE")",
            x: Self.designWidth * 0.5, y: Self.designHeight - 28, pixelSize: 1.25,
            color: Palette.hudFaint, alignment: .center)
    }

    // MARK: - Overlays

    private func drawOverlays(game: SpaceInvadersGame) {
        switch game.phase {
        case .attract:
            drawAttractOverlay(game: game)
        case .ready:
            drawReadyOverlay(game: game)
        case .waveComplete:
            drawWaveClearOverlay(game: game)
        case .gameOver:
            drawGameOverOverlay(game: game)
        case .playing, .playerDying:
            break
        }

        if game.isPaused {
            drawPausedOverlay()
        }
    }

    private func drawAttractOverlay(game: SpaceInvadersGame) {
        canvas.addRect(
            x: 0, y: Self.playfieldOrigin.y, width: Self.designWidth,
            height: CGFloat(Arena.height) * Self.unit, color: Color(0, 0, 0, 0.68))

        let panel = CGRect(x: 104, y: 144, width: 688, height: 792)
        drawPanel(panel: panel, fillAlpha: 0.93, borderColor: Color(0.25, 0.58, 1.0, 0.62))

        drawLargeTitle("SPACE", centerX: Self.designWidth * 0.5, y: 178, color: Palette.white)
        drawLargeTitle("INVADERS", centerX: Self.designWidth * 0.5, y: 274, color: Palette.crab)

        font.draw(
            "A METAL TRIBUTE TO THE 1978 ARCADE", x: Self.designWidth * 0.5, y: 378,
            pixelSize: 1.5, color: Palette.hudDim, alignment: .center)
        canvas.addLine(
            from: CGPoint(x: 210, y: 410), to: CGPoint(x: 686, y: 410),
            thickness: 1, color: Color(0.32, 0.66, 1.0, 0.40), rounded: false)

        let table: [(AlienKind, String, Int, CGFloat)] = [
            (.squid, "SQUID", 30, 430),
            (.crab, "CRAB", 20, 500),
            (.octopus, "OCTOPUS", 10, 570),
        ]
        for (kind, name, points, y) in table {
            drawSpriteScreen(
                SpriteArt.frames(for: kind)[0], at: CGPoint(x: 288, y: y), pixelSize: 3.4,
                color: color(for: kind))
            font.draw(
                name, x: 382, y: y + 6, pixelSize: 2.2, color: Palette.white)
            font.draw(
                "= \(points) PTS", x: 610, y: y + 6, pixelSize: 2.2, color: Palette.yellow,
                alignment: .right)
        }

        drawSpriteScreen(
            SpriteArt.mysteryShip, at: CGPoint(x: 288, y: 648), pixelSize: 3.4,
            color: Palette.ufo)
        font.draw("MYSTERY SHIP", x: 382, y: 654, pixelSize: 2.2, color: Palette.white)
        font.draw(
            "50 - 300", x: 686, y: 654, pixelSize: 2.2, color: Palette.yellow,
            alignment: .right)

        let pulse = 0.66 + 0.34 * abs(sin(game.elapsed * 2.2))
        var prompt = Palette.white
        prompt.w = Float(pulse)
        font.drawGlow(
            "PRESS ENTER TO PLAY", x: Self.designWidth * 0.5, y: 740,
            pixelSize: 2.8, color: prompt, alignment: .center,
            glowColor: Color(0.35, 0.75, 1.0, Float(0.32 * pulse)))

        font.draw(
            "ARROWS / A D TO MOVE       SPACE TO FIRE", x: Self.designWidth * 0.5, y: 812,
            pixelSize: 1.55, color: Palette.hud, alignment: .center)
        font.draw(
            "P PAUSE      M MUTE      ESC PAUSE", x: Self.designWidth * 0.5, y: 842,
            pixelSize: 1.35, color: Palette.hudDim, alignment: .center)
        font.draw(
            "55 INVADERS. FOUR SHIELDS. ONE CANNON.", x: Self.designWidth * 0.5, y: 882,
            pixelSize: 1.25, color: Palette.hudFaint, alignment: .center)
        font.draw("1 CREDIT", x: 144, y: 902, pixelSize: 1.3, color: Palette.yellow)
    }

    private func drawReadyOverlay(game: SpaceInvadersGame) {
        let x = Self.designWidth * 0.5
        let y = Self.playfieldOrigin.y + 196 * Self.unit
        let pulse = 0.75 + 0.25 * abs(sin(game.elapsed * 4))
        var color = Palette.yellow
        color.w = Float(pulse)
        font.drawGlow(
            "READY", x: x, y: y, pixelSize: 3.5, color: color, alignment: .center,
            glowColor: Color(1.0, 0.55, 0.10, 0.30))
    }

    private func drawWaveClearOverlay(game: SpaceInvadersGame) {
        canvas.addRect(
            x: 0, y: Self.playfieldOrigin.y + 200, width: Self.designWidth, height: 220,
            color: Color(0, 0, 0, 0.48))
        font.drawGlow(
            "WAVE \(game.wave) CLEARED", x: Self.designWidth * 0.5, y: 392,
            pixelSize: 3.2, color: Palette.white, alignment: .center,
            glowColor: Color(0.30, 0.80, 1.0, 0.35))
        font.draw(
            "THE NEXT WAVE IS FASTER", x: Self.designWidth * 0.5, y: 470,
            pixelSize: 1.7, color: Palette.hud, alignment: .center)
    }

    private func drawGameOverOverlay(game: SpaceInvadersGame) {
        canvas.addRect(
            x: 0, y: Self.playfieldOrigin.y, width: Self.designWidth,
            height: CGFloat(Arena.height) * Self.unit, color: Color(0, 0, 0, 0.72))
        let panel = CGRect(x: 132, y: 334, width: 632, height: 390)
        drawPanel(panel: panel, fillAlpha: 0.95, borderColor: Color(0.90, 0.22, 0.34, 0.60))

        font.drawGlow(
            "GAME OVER", x: Self.designWidth * 0.5, y: 372, pixelSize: 5.4,
            color: Palette.red, alignment: .center,
            glowColor: Color(0.80, 0.06, 0.15, 0.35))

        let reason: String
        switch game.gameOverReason {
        case .invasion?:
            reason = "THE INVADERS HAVE LANDED"
        case .livesExhausted?:
            reason = "YOUR LAST CANNON IS LOST"
        case nil:
            reason = "MISSION FAILED"
        }
        font.draw(
            reason, x: Self.designWidth * 0.5, y: 462, pixelSize: 1.65,
            color: Palette.hud, alignment: .center)

        font.draw(
            "FINAL SCORE", x: Self.designWidth * 0.5, y: 512, pixelSize: 1.6,
            color: Palette.hudDim, alignment: .center)
        font.draw(
            paddedScore(game.score), x: Self.designWidth * 0.5, y: 536,
            pixelSize: 3.6, color: Palette.white, alignment: .center)
        font.draw(
            "HIGH SCORE  \(paddedScore(game.highScore))", x: Self.designWidth * 0.5, y: 590,
            pixelSize: 1.55, color: Palette.yellow, alignment: .center)
        font.draw(
            "WAVE \(game.wave)   INVADERS LEFT \(game.aliensRemaining)", x: Self.designWidth * 0.5,
            y: 624, pixelSize: 1.35, color: Palette.hudFaint, alignment: .center)

        let pulse = 0.66 + 0.34 * abs(sin(game.elapsed * 2.2))
        var prompt = Palette.white
        prompt.w = Float(pulse)
        font.draw(
            "PRESS ENTER TO PLAY AGAIN", x: Self.designWidth * 0.5, y: 676,
            pixelSize: 2.0, color: prompt, alignment: .center)
    }

    private func drawPausedOverlay() {
        canvas.addRect(
            x: 0, y: 0, width: Self.designWidth, height: Self.designHeight,
            color: Color(0.002, 0.004, 0.014, 0.74))
        let panel = CGRect(x: 222, y: 434, width: 452, height: 252)
        drawPanel(panel: panel, fillAlpha: 0.94, borderColor: Color(0.25, 0.65, 1.0, 0.65))
        font.drawGlow(
            "PAUSED", x: Self.designWidth * 0.5, y: 474, pixelSize: 4.8,
            color: Palette.crab, alignment: .center,
            glowColor: Color(0.15, 0.55, 1.0, 0.25))
        font.draw(
            "PRESS P TO RESUME", x: Self.designWidth * 0.5, y: 592,
            pixelSize: 2.0, color: Palette.white, alignment: .center)
        font.draw(
            "M TOGGLE SOUND", x: Self.designWidth * 0.5, y: 626,
            pixelSize: 1.45, color: Palette.hudDim, alignment: .center)
    }

    // MARK: - Drawing helpers

    private func drawSprite(
        _ rows: [String], at origin: CGPoint, pixelSize: CGFloat, color: Color
    ) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                canvas.addRect(
                    x: origin.x + CGFloat(column) * pixelSize,
                    y: origin.y + CGFloat(row) * pixelSize,
                    width: pixelSize + 0.06, height: pixelSize + 0.06,
                    color: color)
            }
        }
    }

    private func drawSpriteScreen(
        _ rows: [String], at origin: CGPoint, pixelSize: CGFloat, color: Color
    ) {
        drawSprite(rows, at: origin, pixelSize: pixelSize, color: color)
    }

    private func drawLargeTitle(_ text: String, centerX: CGFloat, y: CGFloat, color: Color) {
        font.draw(
            text, x: centerX + 5, y: y + 7, pixelSize: 8.2,
            color: Color(color.x * 0.35, color.y * 0.35, color.z * 0.55, 0.55),
            alignment: .center)
        font.draw(
            text, x: centerX + 2, y: y + 2, pixelSize: 8.2,
            color: Color(color.x, color.y, color.z, 0.30), alignment: .center)
        font.draw(text, x: centerX, y: y, pixelSize: 8.2, color: color, alignment: .center)
    }

    private func drawPanel(panel: CGRect, fillAlpha: Float, borderColor: Color) {
        canvas.addRect(
            x: panel.minX + 4, y: panel.minY + 6, width: panel.width, height: panel.height,
            color: Color(0, 0, 0, 0.55))
        canvas.addRect(
            x: panel.minX, y: panel.minY, width: panel.width, height: panel.height,
            color: Color(0.008, 0.018, 0.050, fillAlpha))
        strokeRect(panel, color: borderColor, thickness: 1.5)
        strokeRect(
            panel.insetBy(dx: 6, dy: 6), color: Color(0.14, 0.32, 0.75, 0.28), thickness: 1)
    }

    private func strokeRect(_ rect: CGRect, color: Color, thickness: CGFloat) {
        canvas.addLine(
            from: CGPoint(x: rect.minX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.minY),
            thickness: thickness, color: color, rounded: false)
        canvas.addLine(
            from: CGPoint(x: rect.maxX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            thickness: thickness, color: color, rounded: false)
        canvas.addLine(
            from: CGPoint(x: rect.maxX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.maxY),
            thickness: thickness, color: color, rounded: false)
        canvas.addLine(
            from: CGPoint(x: rect.minX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.minY),
            thickness: thickness, color: color, rounded: false)
    }

    private func drawScanlines() {
        var y: CGFloat = 0
        while y < Self.designHeight {
            canvas.addRect(
                x: 0, y: y, width: Self.designWidth, height: 1,
                color: Color(0, 0, 0, 0.045))
            y += 4
        }
    }

    private func color(for kind: AlienKind) -> Color {
        switch kind {
        case .squid: return Palette.squid
        case .crab: return Palette.crab
        case .octopus: return Palette.octopus
        }
    }

    private func paddedScore(_ value: Int) -> String {
        let clamped = max(0, min(value, 999_999))
        return String(format: "%06d", clamped)
    }
}

enum RendererError: Error {
    case noMetalDevice
    case couldNotCreateCommandQueue
    case shaderCompilationFailed
    case pipelineCreationFailed
    case couldNotCreateVertexBuffer
}
