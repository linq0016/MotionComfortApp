import AVFAudio
import Combine
import Foundation

// 音频层：准备单音与旋律资源，通过 AVAudioEngine 管理循环播放。
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

    // 参数分为采样规格、播放音量和声源合成；声源振幅与播放音量分别作用于生成和播放阶段。
    private struct AudioComfortConfiguration: Sendable {
        var sampleRate: Double = 44_100.0
        var mixerOutputVolume: Float = 1.0
        var playbackVolumes: [AudioMode: Float] = [
            .off: 0.0,
            .monotone: 0.18,
            .melodic: 0.19
        ]
        var silentLoop = LoopSynthesisConfiguration(
            duration: 1.0,
            layers: [(frequency: 220.0, amplitude: 0.0)],
            modulationFrequency: 0.0
        )
        var monotoneFallbackLoop = LoopSynthesisConfiguration(
            duration: 1.0,
            layers: [(frequency: 100.0, amplitude: 0.18)],
            modulationFrequency: 0.0
        )
        var monotoneAsset = MonotoneAssetConfiguration(
            frequency: 100.0,
            amplitude: 0.7,
            duration: 1.0,
            cacheDirectoryName: "MotionComfortAudio",
            fileName: "monotone_100hz.wav"
        )
    }

    // 合成时长以秒计、频率以 Hz 计，layers 定义各正弦波的频率与振幅。
    private struct LoopSynthesisConfiguration: Sendable {
        var duration: Double
        var layers: [(frequency: Double, amplitude: Double)]
        var modulationFrequency: Double
    }

    private struct MonotoneAssetConfiguration: Sendable {
        var frequency: Double
        var amplitude: Float
        var duration: Double
        var cacheDirectoryName: String
        var fileName: String
    }

    private let configuration: AudioComfortConfiguration
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat?
    private var buffers: [AudioMode: AVAudioPCMBuffer]
    private var monotoneAssetURL: URL?
    private let melodicAssetURL: URL?
    private var prewarmTask: Task<Void, Never>?
    private var didFinishPrewarm = false
    private var pendingPlaybackMode: AudioMode?
    private var systemAudioEventObservers: Set<AnyCancellable> = []
    private var lastOutputWasBuiltIn = true

    // 会话的激活与停用是同步阻塞调用，统一在该串行队列执行；playbackRequestID 用于丢弃过期的起播结果。
    private let sessionQueue = DispatchQueue(label: "com.motioncomfort.audio.session", qos: .userInitiated)
    private var playbackRequestID = 0

    public init(sampleRate: Double = 44_100.0) {
        var configuration = AudioComfortConfiguration()
        configuration.sampleRate = sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        self.configuration = configuration
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
        engine.mainMixerNode.outputVolume = configuration.mixerOutputVolume

        if format == nil {
            assertionFailure("Unable to create stereo audio format.")
        }

        observeSystemAudioEvents()
    }

    // 后台读取或生成音频缓冲区，完成后回到主 actor 安装资源并处理待播放模式。
    public func prewarmResourcesIfNeeded() {
        guard format != nil, prewarmTask == nil, !didFinishPrewarm else {
            return
        }

        let configuration = configuration
        let melodicAssetURL = melodicAssetURL
        prewarmTask = Task.detached(priority: .utility) { [weak self, configuration, melodicAssetURL] in
            let resources = Self.prepareAudioResources(
                configuration: configuration,
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
            stopPlayback()
            return
        }

        guard format != nil else {
            return
        }

        guard mode.isImplemented else {
            playbackRequestID += 1
            player.stop()
            player.reset()
            engine.pause()
            activeMode = mode
            isPlaying = false
            return
        }

        prewarmResourcesIfNeeded()

        guard !(isPlaying && activeMode == mode && buffers[mode] != nil && engine.isRunning) else {
            return
        }

        guard buffers[mode] != nil else {
            waitForPreparedBuffer(for: mode)
            return
        }

        playbackRequestID += 1
        let requestID = playbackRequestID
        sessionQueue.async { [weak self] in
            let didActivate = Self.activatePlaybackSession()
            Task { @MainActor [weak self] in
                self?.startPlayback(mode, requestID: requestID, didActivate: didActivate)
            }
        }
    }

    // 会话激活完成后启动引擎并起播；期间若已停止或换了模式，本次结果作废。
    private func startPlayback(_ mode: AudioMode, requestID: Int, didActivate: Bool) {
        guard didActivate, requestID == playbackRequestID, let buffer = buffers[mode] else {
            return
        }

        do {
            try startEngineIfNeeded()
        } catch {
            return
        }

        player.stop()
        player.reset()
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = configuration.playbackVolumes[mode] ?? 0.0
        player.play()

        activeMode = mode
        isPlaying = true
        lastOutputWasBuiltIn = isOutputBuiltIn
    }

    // 完整停止音频播放，并释放当前会话。
    public func stopPlayback() {
        pendingPlaybackMode = nil
        playbackRequestID += 1
        player.stop()
        player.reset()
        engine.pause()
        activeMode = .off
        isPlaying = false

        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // 系统通知可能来自任意线程，先转到主队列再读写播放状态。
    private func observeSystemAudioEvents() {
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &systemAudioEventObservers)

        // 换设备时路由变化与引擎配置变化的到达顺序不固定，两者走同一处理。
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
            .merge(with: NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleOutputHardwareChange()
            }
            .store(in: &systemAudioEventObservers)
    }

    // 中断开始时只记录已停止，保留 activeMode；系统建议恢复或 App 回到前台时从头重播。
    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            isPlaying = false
        case .ended:
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
                  activeMode != .off
            else {
                return
            }

            setMode(activeMode)
        @unknown default:
            break
        }
    }

    private var isOutputBuiltIn: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.allSatisfy {
            $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver
        }
    }

    // 耳机或蓝牙断开、输出落回内置扬声器时静音并保留 activeMode，回到前台或重选模式时重播；
    // 其余硬件变化若让引擎停止，则重新启动并重播。
    private func handleOutputHardwareChange() {
        let isBuiltIn = isOutputBuiltIn
        let lostExternalOutput = !lastOutputWasBuiltIn && isBuiltIn
        lastOutputWasBuiltIn = isBuiltIn

        guard isPlaying else {
            return
        }

        if lostExternalOutput {
            playbackRequestID += 1
            player.stop()
            engine.pause()
            isPlaying = false
        } else {
            setMode(activeMode)
        }
    }

    nonisolated private static func activatePlaybackSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
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
        playbackRequestID += 1
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
        configuration: AudioComfortConfiguration,
        melodicAssetURL: URL?
    ) -> PreparedAudioResources {
        var preparedBuffers: [AudioMode: PreparedAudioBuffer] = [:]
        var monotoneAssetURL: URL?

        if let melodicBuffer = makeBuffer(
            for: .melodic,
            configuration: configuration,
            melodicAssetURL: melodicAssetURL
        ) {
            preparedBuffers[.melodic] = PreparedAudioBuffer(buffer: melodicBuffer)
        }

        if let monotoneBuffer = makeBuffer(
            for: .monotone,
            configuration: configuration,
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
        configuration: AudioComfortConfiguration,
        melodicAssetURL: URL?,
        monotoneAssetURL: inout URL?
    ) -> AVAudioPCMBuffer? {
        switch mode {
        case .off:
            return makeLoopBuffer(
                sampleRate: configuration.sampleRate,
                configuration: configuration.silentLoop
            )
        case .monotone:
            monotoneAssetURL = prepareMonotoneAsset(configuration: configuration)

            if let url = monotoneAssetURL, let loaded = loadBuffer(from: url) {
                return loaded
            }

            return makeLoopBuffer(
                sampleRate: configuration.sampleRate,
                configuration: configuration.monotoneFallbackLoop
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
        configuration: AudioComfortConfiguration,
        melodicAssetURL: URL?
    ) -> AVAudioPCMBuffer? {
        var monotoneAssetURL: URL?
        return makeBuffer(
            for: mode,
            configuration: configuration,
            melodicAssetURL: melodicAssetURL,
            monotoneAssetURL: &monotoneAssetURL
        )
    }

    nonisolated private static func makeLoopBuffer(
        sampleRate: Double,
        configuration: LoopSynthesisConfiguration
    ) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        guard let format else {
            assertionFailure("Unable to create loop buffer without a valid audio format.")
            return nil
        }

        let frameCount = AVAudioFrameCount(format.sampleRate * configuration.duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            assertionFailure("Unable to create PCM buffer.")
            return nil
        }

        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]

            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / format.sampleRate
                let modulation = configuration.modulationFrequency > 0.0
                    ? 0.88 + (0.12 * sin(2.0 * Double.pi * configuration.modulationFrequency * time))
                    : 1.0
                var mixedValue = 0.0

                for layer in configuration.layers {
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

    nonisolated private static func prepareMonotoneAsset(configuration: AudioComfortConfiguration) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(configuration.monotoneAsset.cacheDirectoryName, isDirectory: true)

        guard let directory else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = directory.appendingPathComponent(configuration.monotoneAsset.fileName)
        if fileManager.fileExists(atPath: url.path) {
            return url
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: configuration.sampleRate, channels: 2) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(configuration.sampleRate * configuration.monotoneAsset.duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let amplitude = configuration.monotoneAsset.amplitude

        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / configuration.sampleRate
                samples[frame] = Float(sin(2.0 * Double.pi * configuration.monotoneAsset.frequency * time)) * amplitude
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
