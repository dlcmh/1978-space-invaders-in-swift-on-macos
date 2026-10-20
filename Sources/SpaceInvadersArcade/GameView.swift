import AppKit
import MetalKit
import QuartzCore
import SpaceInvadersCore

final class GameView: MTKView, MTKViewDelegate {
    private(set) var game: SpaceInvadersGame
    private var renderer: Renderer!
    private let sound = SoundEngine()

    private var lastFrameTime: CFTimeInterval = 0
    private var accumulator: Double = 0
    private var lastSavedHighScore: Int
    private var lastHighScoreSaveTime: CFTimeInterval = 0
    private var resignObserver: NSObjectProtocol?
    private let autoPauseOnResign: Bool
    private let autoFire: Bool
    private var autoFireAccumulator = 0.0

    private let highScoreKey = "SpaceInvadersArcadeHighScore"
    private let mutedKey = "SpaceInvadersArcadeMuted"
    private let fixedTimeStep = 1.0 / 60.0

    init(arcadeFrame frame: CGRect) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }

        let savedHighScore = UserDefaults.standard.integer(forKey: "SpaceInvadersArcadeHighScore")
        lastSavedHighScore = savedHighScore
        autoPauseOnResign = ProcessInfo.processInfo.environment["SPACEINVADERS_AUTOPAUSE"] != "0"
        autoFire = ProcessInfo.processInfo.environment["SPACEINVADERS_AUTOFIRE"] == "1"
        game = SpaceInvadersGame(highScore: savedHighScore)

        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        clearColor = MTLClearColor(red: 0.003, green: 0.006, blue: 0.016, alpha: 1.0)
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        renderer = try Renderer(view: self)
        delegate = self
        wantsLayer = true

        sound.isMuted = UserDefaults.standard.bool(forKey: mutedKey)
        renderer.isMuted = sound.isMuted

        if ProcessInfo.processInfo.environment["SPACEINVADERS_AUTOSTART"] == "1" {
            game.startNewGame()
        }

        if autoPauseOnResign {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.game.pause()
                self?.clearMovement()
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        saveHighScore()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.backgroundColor = .black
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The renderer derives its letterbox transform from the drawable size.
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if lastFrameTime == 0 {
            lastFrameTime = now
        }
        let frameDelta = min(max(now - lastFrameTime, 0), 0.1)
        lastFrameTime = now
        accumulator += frameDelta

        if autoFire, game.phase == .playing {
            autoFireAccumulator += frameDelta
            if autoFireAccumulator >= 0.65 {
                autoFireAccumulator = 0
                game.fire()
            }
        }

        var steps = 0
        while accumulator >= fixedTimeStep, steps < 8 {
            game.update(dt: fixedTimeStep)
            processEvents()
            accumulator -= fixedTimeStep
            steps += 1
        }
        if steps == 8 {
            accumulator = 0
        }

        renderer.isMuted = sound.isMuted
        renderer.render(game: game, in: view)

        if game.highScore != lastSavedHighScore {
            let current = CACurrentMediaTime()
            if game.phase == .gameOver || current - lastHighScoreSaveTime > 1.5 {
                lastHighScoreSaveTime = current
                saveHighScore()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123, 0:
            game.setMovingLeft(true)
        case 124, 2:
            game.setMovingRight(true)
        case 36, 49, 76:
            if game.phase == .attract || game.phase == .gameOver {
                game.requestStart()
            } else {
                game.fire()
            }
        case 3:
            if !event.isARepeat {
                toggleFullscreen()
            }
        case 35:
            game.togglePause()
            clearMovement()
        case 46:
            toggleMute()
        case 53:
            if isFullScreen {
                if !event.isARepeat {
                    toggleFullscreen()
                }
            } else {
                game.pause()
                clearMovement()
            }
        default:
            guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
                return
            }
            if characters == "p" {
                game.togglePause()
                clearMovement()
            } else if characters == "m" {
                toggleMute()
            } else if characters == "a" {
                game.setMovingLeft(true)
            } else if characters == "d" {
                game.setMovingRight(true)
            } else if characters == " " || characters == "\r" {
                if game.phase == .attract || game.phase == .gameOver {
                    game.requestStart()
                } else {
                    game.fire()
                }
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 123, 0:
            game.setMovingLeft(false)
        case 124, 2:
            game.setMovingRight(false)
        default:
            if let characters = event.charactersIgnoringModifiers?.lowercased() {
                if characters == "a" {
                    game.setMovingLeft(false)
                } else if characters == "d" {
                    game.setMovingRight(false)
                }
            }
        }
    }

    private func clearMovement() {
        game.setMovingLeft(false)
        game.setMovingRight(false)
    }

    private var isFullScreen: Bool {
        window?.styleMask.contains(.fullScreen) ?? false
    }

    /// Enter or leave full screen without changing the game phase. The renderer
    /// letterboxes to the new drawable size, so the arcade aspect is preserved.
    private func toggleFullscreen() {
        guard let window else { return }
        clearMovement()
        window.toggleFullScreen(nil)
    }

    func saveHighScore() {
        if game.highScore > lastSavedHighScore {
            UserDefaults.standard.set(game.highScore, forKey: highScoreKey)
            lastSavedHighScore = game.highScore
        }
    }

    func toggleMute() {
        sound.isMuted.toggle()
        renderer.isMuted = sound.isMuted
        UserDefaults.standard.set(sound.isMuted, forKey: mutedKey)
        if !sound.isMuted {
            sound.play(.mysteryAppeared)
        }
    }

    private func processEvents() {
        for event in game.drainEvents() {
            switch event {
            case .gameStart:
                sound.play(.start)
            case .playerShot:
                sound.play(.shoot)
            case .invaderStep:
                sound.playMarch()
            case .alienKilled:
                sound.play(.alienKilled)
            case .mysteryAppeared:
                sound.play(.mysteryAppeared)
            case .mysteryHit:
                sound.play(.mysteryHit)
            case .bunkerHit:
                sound.play(.bunkerHit)
            case .playerHit:
                sound.play(.playerHit)
            case .extraLife:
                sound.play(.extraLife)
            case .waveComplete:
                sound.play(.waveComplete)
            case .gameOver:
                sound.play(.gameOver)
                saveHighScore()
            }
        }
    }
}
