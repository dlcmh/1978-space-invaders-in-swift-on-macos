import AVFoundation
import Foundation

enum SoundEffect {
    case shoot
    case alienKilled
    case bunkerHit
    case playerHit
    case mysteryAppeared
    case mysteryHit
    case extraLife
    case waveComplete
    case gameOver
    case start
}

/// A tiny procedural chiptune engine. Every effect, including the four-note
/// marching bass loop, is synthesized at launch, so the game has no external
/// audio assets. The mixer is local; nothing is streamed or downloaded.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var marchIndex = 0
    private var lastMarchTime = 0.0
    private var audioAvailable = false

    var isMuted = false {
        didSet {
            engine.mainMixerNode.outputVolume = isMuted ? 0 : 0.55
        }
    }

    init() {
        engine.mainMixerNode.outputVolume = 0.55

        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        buildBuffers()

        do {
            engine.prepare()
            try engine.start()
            audioAvailable = true
            for player in players {
                player.play()
            }
        } catch {
            audioAvailable = false
        }
    }

    func play(_ effect: SoundEffect) {
        guard audioAvailable, !isMuted else { return }

        let key: String
        switch effect {
        case .shoot: key = "shoot"
        case .alienKilled: key = "alien"
        case .bunkerHit: key = "bunker"
        case .playerHit: key = "playerHit"
        case .mysteryAppeared: key = "ufo"
        case .mysteryHit: key = "ufoHit"
        case .extraLife: key = "extraLife"
        case .waveComplete: key = "wave"
        case .gameOver: key = "gameOver"
        case .start: key = "start"
        }

        playBuffer(named: key)
    }

    /// The original cabinet's four descending bass notes accompany each
    /// formation step. Rapid late-game steps are throttled so the mixer does
    /// not turn into a buzz.
    func playMarch() {
        guard audioAvailable, !isMuted else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMarchTime > 0.055 else { return }
        lastMarchTime = now
        playBuffer(named: "march\(marchIndex)")
        marchIndex = (marchIndex + 1) % 4
    }

    private func playBuffer(named key: String) {
        guard let buffer = buffers[key] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func stopAll() {
        for player in players {
            player.stop()
        }
    }

    // MARK: - Synthesis

    private func buildBuffers() {
        buffers["shoot"] = makeBuffer(duration: 0.16) { t in
            let progress = min(1, t / 0.16)
            let frequency = 920.0 - 720.0 * progress
            return self.square(time: t, frequency: frequency) * Float(0.15 * (1 - progress))
        }

        buffers["alien"] = makeBuffer(duration: 0.2) { t in
            let progress = min(1, t / 0.2)
            let noise = sin(t * 2 * .pi * 1730) * sin(t * 2 * .pi * 2710)
            return Float(0.16 * noise * (1 - progress))
        }

        buffers["bunker"] = makeBuffer(duration: 0.07) { t in
            let progress = min(1, t / 0.07)
            let noise = sin(t * 2 * .pi * 3110) * sin(t * 2 * .pi * 1210)
            return Float(0.10 * noise * (1 - progress))
        }

        buffers["playerHit"] = makeBuffer(duration: 1.25) { t in
            let progress = min(1, t / 1.25)
            let frequency = 620.0 * pow(0.10, progress) + sin(t * 2 * .pi * 11) * 12
            let noise = sin(t * 2 * .pi * 1970) * 0.45
            return
                (self.square(time: t, frequency: frequency) * 0.17
                + Float(noise * 0.10 * (1 - progress)))
                * Float(1 - progress)
        }

        buffers["ufo"] = makeBuffer(duration: 0.9) { t in
            let progress = min(1, t / 0.9)
            let wobble = sin(t * 2 * .pi * 13) * 70
            return self.triangle(time: t, frequency: 640 + wobble) * Float(0.10 * (1 - progress))
        }

        buffers["ufoHit"] = makeBuffer(duration: 0.42) { t in
            let progress = min(1, t / 0.42)
            let notes = [523.25, 783.99, 1046.5, 1567.98]
            let index = min(Int(progress * 4), 3)
            return self.square(time: t, frequency: notes[index]) * Float(0.16 * (1 - progress))
        }

        buffers["extraLife"] = makeBuffer(duration: 0.7) { t in
            let noteLength = 0.1
            let notes = [783.99, 987.77, 1174.66, 1567.98, 1318.51, 1567.98]
            let index = min(Int(t / noteLength), notes.count - 1)
            let progress = min(1, t / 0.7)
            let noteProgress = (t - Double(index) * noteLength) / noteLength
            return self.square(time: t, frequency: notes[index])
                * Float(0.15 * max(0, 1 - noteProgress) * (1 - progress * 0.4))
        }

        buffers["wave"] = makeBuffer(duration: 0.9) { t in
            let noteLength = 0.14
            let notes = [523.25, 659.25, 783.99, 1046.5, 1318.51]
            let index = min(Int(t / noteLength), notes.count - 1)
            let progress = min(1, t / 0.9)
            let noteProgress = (t - Double(index) * noteLength) / noteLength
            return self.triangle(time: t, frequency: notes[index])
                * Float(0.20 * max(0, 1 - noteProgress) * (1 - progress * 0.25))
        }

        buffers["gameOver"] = makeBuffer(duration: 1.1) { t in
            let progress = min(1, t / 1.1)
            let frequency = 330.0 * pow(0.22, progress)
            return self.square(time: t, frequency: frequency) * Float(0.15 * (1 - progress))
        }

        buffers["start"] = makeBuffer(duration: 1.2) { t in
            let noteLength = 0.115
            let notes = [261.63, 329.63, 392.0, 523.25, 392.0, 523.25, 659.25, 783.99, 1046.5]
            let index = min(Int(t / noteLength), notes.count - 1)
            let progress = min(1, t / 1.2)
            let noteProgress = (t - Double(index) * noteLength) / noteLength
            return self.square(time: t, frequency: notes[index])
                * Float(0.14 * max(0, 1 - noteProgress * 0.8) * (1 - progress * 0.35))
        }

        let marchNotes = [110.0, 98.0, 87.31, 82.41]
        for (index, frequency) in marchNotes.enumerated() {
            buffers["march\(index)"] = makeBuffer(duration: 0.1) { t in
                let progress = min(1, t / 0.1)
                return self.triangle(time: t, frequency: frequency)
                    * Float(0.11 * (1 - progress))
            }
        }
    }

    private func makeBuffer(duration: Double, generator: (Double) -> Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData
        else {
            return nil
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            channelData[0][frame] = generator(Double(frame) / sampleRate)
        }
        return buffer
    }

    private func square(time: Double, frequency: Double) -> Float {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        return phase < 0.5 ? 1 : -1
    }

    private func triangle(time: Double, frequency: Double) -> Float {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        return Float(4 * abs(phase - 0.5) - 1)
    }
}
