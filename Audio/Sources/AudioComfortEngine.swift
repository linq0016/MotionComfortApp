import AVFAudio
import Foundation
import MotionComfortCore

// 可选音频层：负责生成循环声，不承担主防晕视觉逻辑。
@MainActor
public final class AudioComfortEngine: ObservableObject {
    @Published public private(set) var isPlaying: Bool
    @Published public private(set) var activeMode: AudioMode

    private struct PreparedAudioBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    private struct PreparedAudioResources: @unchecked Sendable {
        let buffers: [AudioMode: PreparedAudioBuffer]
        let monotoneAssetURL: URL?
    }

    private let sampleRate: Double
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat?
    private var buffers: [AudioMode: AVAudioPCMBuffer]
    private var monotoneAssetURL: URL?
    private let melodicAssetURL: URL?
    private var prewarmTask: Task<Void, Never>?
    private var didFinishPrewarm = false
    private var pendingPlaybackMode: AudioMode?

    public init(sampleRate: Double = 44_100.0) {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        self.sampleRate = sampleRate
        self.engine = AVAudioEngine()
        self.player = AVAudioPlayerNode()
        self.format = format
        self.isPlaying = false
        self.activeMode = .off
        self.buffers = [:]
        self.monotoneAssetURL = nil
        self.melodicAssetURL = Self.findMelodicAsset()
        self.prewarmTask = nil

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0

        if format == nil {
            assertionFailure("Unable to create stereo audio format.")
        }
    }

    public func prewarmResourcesIfNeeded() {
        guard format != nil, prewarmTask == nil, !didFinishPrewarm else {
            return
        }

        let sampleRate = sampleRate
        let melodicAssetURL = melodicAssetURL
        prewarmTask = Task.detached(priority: .utility) { [weak self, sampleRate, melodicAssetURL] in
            let resources = Self.prepareAudioResources(
                sampleRate: sampleRate,
                melodicAssetURL: melodicAssetURL
            )
            guard !Task.isCancelled else {
                return
            }

            await self?.installPreparedResources(resources)
        }
    }

    // 切换到指定音频模式，并开始循环播放。
    public func setMode(_ mode: AudioMode) {
        guard mode != .off else {
            pendingPlaybackMode = nil
            stopPlayback()
            return
        }

        guard format != nil else {
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

        prewarmResourcesIfNeeded()

        guard !(isPlaying && activeMode == mode && buffers[mode] != nil) else {
            return
        }

        guard let buffer = buffers[mode] else {
            waitForPreparedBuffer(for: mode)
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
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = playbackVolume(for: mode)
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

    // 目前 Monotone 走固定音量，不再跟随 motion 强度变化。
    public func update(with sample: MotionSample) {
        _ = sample
        guard activeMode == .monotone else {
            return
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func playbackVolume(for mode: AudioMode) -> Float {
        switch mode {
        case .off:
            return 0.0
        case .monotone:
            return 0.18
        case .melodic:
            return 0.19
        }
    }

    private func installPreparedResources(_ resources: PreparedAudioResources) {
        for (mode, preparedBuffer) in resources.buffers {
            buffers[mode] = preparedBuffer.buffer
        }
        monotoneAssetURL = resources.monotoneAssetURL ?? monotoneAssetURL
        didFinishPrewarm = true
        prewarmTask = nil

        guard let pendingPlaybackMode else {
            return
        }

        self.pendingPlaybackMode = nil
        setMode(pendingPlaybackMode)
    }

    private func waitForPreparedBuffer(for mode: AudioMode) {
        pendingPlaybackMode = mode
        player.stop()
        player.reset()
        engine.pause()
        activeMode = mode
        isPlaying = false

        if didFinishPrewarm {
            pendingPlaybackMode = nil
        }
    }

    nonisolated private static func prepareAudioResources(
        sampleRate: Double,
        melodicAssetURL: URL?
    ) -> PreparedAudioResources {
        var preparedBuffers: [AudioMode: PreparedAudioBuffer] = [:]
        var monotoneAssetURL: URL?

        if let melodicBuffer = makeBuffer(
            for: .melodic,
            sampleRate: sampleRate,
            melodicAssetURL: melodicAssetURL
        ) {
            preparedBuffers[.melodic] = PreparedAudioBuffer(buffer: melodicBuffer)
        }

        if let monotoneBuffer = makeBuffer(
            for: .monotone,
            sampleRate: sampleRate,
            melodicAssetURL: melodicAssetURL,
            monotoneAssetURL: &monotoneAssetURL
        ) {
            preparedBuffers[.monotone] = PreparedAudioBuffer(buffer: monotoneBuffer)
        }

        return PreparedAudioResources(
            buffers: preparedBuffers,
            monotoneAssetURL: monotoneAssetURL
        )
    }

    nonisolated private static func makeBuffer(
        for mode: AudioMode,
        sampleRate: Double,
        melodicAssetURL: URL?,
        monotoneAssetURL: inout URL?
    ) -> AVAudioPCMBuffer? {
        switch mode {
        case .off:
            return makeLoopBuffer(
                sampleRate: sampleRate,
                duration: 1.0,
                layers: [(220.0, 0.0)],
                modulationFrequency: 0.0
            )
        case .monotone:
            monotoneAssetURL = prepareMonotoneAsset(sampleRate: sampleRate)

            if let url = monotoneAssetURL, let loaded = loadBuffer(from: url) {
                return loaded
            }

            return makeLoopBuffer(
                sampleRate: sampleRate,
                duration: 1.0,
                layers: [(100.0, 0.18)],
                modulationFrequency: 0.0
            )
        case .melodic:
            guard let url = melodicAssetURL else {
                return nil
            }

            return loadBuffer(from: url)
        }
    }

    nonisolated private static func makeBuffer(
        for mode: AudioMode,
        sampleRate: Double,
        melodicAssetURL: URL?
    ) -> AVAudioPCMBuffer? {
        var monotoneAssetURL: URL?
        return makeBuffer(
            for: mode,
            sampleRate: sampleRate,
            melodicAssetURL: melodicAssetURL,
            monotoneAssetURL: &monotoneAssetURL
        )
    }

    nonisolated private static func makeLoopBuffer(
        sampleRate: Double,
        duration: Double,
        layers: [(frequency: Double, amplitude: Double)],
        modulationFrequency: Double
    ) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        guard let format else {
            assertionFailure("Unable to create loop buffer without a valid audio format.")
            return nil
        }

        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            assertionFailure("Unable to create PCM buffer.")
            return nil
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

    nonisolated private static func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
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

    nonisolated private static func prepareMonotoneAsset(sampleRate: Double) -> URL? {
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

    nonisolated private static func findMelodicAsset() -> URL? {
        if let url = Bundle.main.url(forResource: "GStringsFinal", withExtension: "wav") {
            return url
        }

        return Bundle.main.url(
            forResource: "GStringsFinal",
            withExtension: "wav",
            subdirectory: "Audio/Resources"
        )
    }
}
