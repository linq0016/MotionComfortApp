import AVFAudio
import Foundation
import MotionComfortCore

// 可选音频层：负责生成循环声，不承担主防晕视觉逻辑。
@MainActor
public final class AudioComfortEngine: ObservableObject {
    @Published public private(set) var isPlaying: Bool
    @Published public private(set) var activeMode: AudioMode

    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat
    private var buffers: [AudioMode: AVAudioPCMBuffer]
    private let monotoneAssetURL: URL?

    public init(sampleRate: Double = 44_100.0) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            fatalError("Unable to create stereo audio format.")
        }

        self.engine = AVAudioEngine()
        self.player = AVAudioPlayerNode()
        self.format = format
        self.isPlaying = false
        self.activeMode = .off
        self.buffers = [:]
        self.monotoneAssetURL = Self.prepareMonotoneAsset(sampleRate: sampleRate)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
    }

    // 切换到指定音频模式，并开始循环播放。
    public func setMode(_ mode: AudioMode) {
        guard mode != .off else {
            stopPlayback()
            return
        }

        guard mode.isImplemented else {
            player.stop()
            player.reset()
            engine.pause()
            activeMode = mode
            isPlaying = false
            return
        }

        do {
            try configureAudioSession()
            try startEngineIfNeeded()
        } catch {
            return
        }

        player.stop()
        player.reset()
        player.scheduleBuffer(buffer(for: mode), at: nil, options: [.loops], completionHandler: nil)
        player.volume = 0.14
        player.play()

        activeMode = mode
        isPlaying = true
    }

    // 完整停止音频播放，并释放当前会话。
    public func stopPlayback() {
        player.stop()
        player.reset()
        engine.pause()
        activeMode = .off
        isPlaying = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
        }
    }

    // 用运动强度轻微调节音量，保持音频只做辅助。
    public func update(with sample: MotionSample) {
        guard activeMode != .off, activeMode.isImplemented else {
            return
        }

        let baseVolume: Double = activeMode == .monotone ? 0.10 : 0.12
        let dynamicGain = sample.intensity * 0.16
        player.volume = Float(clamp(baseVolume + dynamicGain, minimum: 0.06, maximum: 0.28))
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func buffer(for mode: AudioMode) -> AVAudioPCMBuffer {
        if let existing = buffers[mode] {
            return existing
        }

        let created = makeBuffer(for: mode)
        buffers[mode] = created
        return created
    }

    private func makeBuffer(for mode: AudioMode) -> AVAudioPCMBuffer {
        switch mode {
        case .off:
            return makeLoopBuffer(duration: 1.0, layers: [(220.0, 0.0)], modulationFrequency: 0.0)
        case .monotone:
            if let url = monotoneAssetURL, let loaded = loadBuffer(from: url) {
                return loaded
            }

            return makeLoopBuffer(duration: 1.0, layers: [(100.0, 0.18)], modulationFrequency: 0.0)
        case .melodic:
            return makeLoopBuffer(duration: 1.0, layers: [(220.0, 0.0)], modulationFrequency: 0.0)
        }
    }

    private func makeLoopBuffer(
        duration: Double,
        layers: [(frequency: Double, amplitude: Double)],
        modulationFrequency: Double
    ) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            fatalError("Unable to create PCM buffer.")
        }

        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]

            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / format.sampleRate
                let modulation = modulationFrequency > 0.0
                    ? 0.88 + (0.12 * sin(2.0 * Double.pi * modulationFrequency * time))
                    : 1.0
                var mixedValue = 0.0

                for layer in layers {
                    mixedValue += sin(2.0 * Double.pi * layer.frequency * time) * layer.amplitude
                }

                samples[frame] = Float(mixedValue * modulation)
            }
        }

        return buffer
    }

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                return nil
            }

            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    private static func prepareMonotoneAsset(sampleRate: Double) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MotionComfortAudio", isDirectory: true)

        guard let directory else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = directory.appendingPathComponent("monotone_100hz.wav")
        if fileManager.fileExists(atPath: url.path) {
            return url
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let amplitude: Float = 0.7

        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / sampleRate
                samples[frame] = Float(sin(2.0 * Double.pi * 100.0 * time)) * amplitude
            }
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            return nil
        }
    }
}
