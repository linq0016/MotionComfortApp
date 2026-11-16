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
        let introBuffers: [AudioMode: PreparedAudioBuffer]
    }

    // 参数分为采样规格、播放音量和单音素材；素材振幅与播放音量分别作用于生成和播放阶段。
    private struct AudioComfortConfiguration: Sendable {
        var sampleRate: Double = 44_100.0
        var mixerOutputVolume: Float = 1.0
        var playbackVolumes: [AudioMode: Float] = [
            .off: 0.0,
            .monotone: 0.18,
            .melodic: 0.19
        ]
        // 停止或切换模式前，播放器音量降到 0 所用的秒数。
        var fadeOutDuration: Double = 0.2
        var monotoneAsset = MonotoneAssetConfiguration(
            frequency: 100.0,
            amplitude: 0.7,
            duration: 1.0,
            fadeInDuration: 0.5,
            cacheDirectoryName: "MotionComfortAudio"
        )
    }

    // fadeInDuration 是起播引子里音量从 0 升到满幅的秒数。
    private struct MonotoneAssetConfiguration: Sendable {
        var frequency: Double
        var amplitude: Float
        var duration: Double
        var fadeInDuration: Double
        var cacheDirectoryName: String
    }

    nonisolated private let configuration: AudioComfortConfiguration
    // 引擎与播放器的启停会阻塞调用线程，只在 sessionQueue 上操作。
    nonisolated private let engine: AVAudioEngine
    nonisolated private let player: AVAudioPlayerNode
    private let format: AVAudioFormat?
    private var buffers: [AudioMode: AVAudioPCMBuffer]
    // 起播时先播一次的淡入引子，随后无缝接上循环缓冲。
    private var introBuffers: [AudioMode: AVAudioPCMBuffer] = [:]
    private let melodicAssetURL: URL?
    private var prewarmTask: Task<Void, Never>?
    private var didFinishPrewarm = false
    private var pendingPlaybackMode: AudioMode?
    private var systemAudioEventObservers: Set<AnyCancellable> = []
    private var lastOutputWasBuiltIn = true

    // 会话激活停用、引擎与播放器启停都是同步阻塞调用，统一在该串行队列按调用顺序执行；
    // playbackRequestID 用于丢弃过期的起播结果。
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

    // 等待音频缓冲预热完成；尚未开始时先启动，已完成时立即返回。
    public func ensureAudioResourcesReady() async {
        prewarmResourcesIfNeeded()
        await prewarmTask?.value
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

        prewarmResourcesIfNeeded()

        guard !(isPlaying && activeMode == mode && buffers[mode] != nil && engine.isRunning) else {
            return
        }

        guard let buffer = buffers[mode] else {
            waitForPreparedBuffer(for: mode)
            return
        }

        playbackRequestID += 1
        let requestID = playbackRequestID
        let preparedBuffer = PreparedAudioBuffer(buffer: buffer)
        let preparedIntro = introBuffers[mode].map { PreparedAudioBuffer(buffer: $0) }
        let volume = configuration.playbackVolumes[mode] ?? 0.0
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            let didStart = Self.activatePlaybackSession()
                && self.startLoop(preparedBuffer, intro: preparedIntro, volume: volume)
            Task { @MainActor [weak self] in
                self?.finishPlaybackStart(mode, requestID: requestID, didStart: didStart)
            }
        }
    }

    // 在 sessionQueue 上启动引擎并循环播放缓冲区；有引子时先播一次引子。
    nonisolated private func startLoop(
        _ preparedBuffer: PreparedAudioBuffer,
        intro: PreparedAudioBuffer?,
        volume: Float
    ) -> Bool {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return false
        }

        fadeOutAndStopPlayer()
        if let intro {
            player.scheduleBuffer(intro.buffer, at: nil, options: [], completionHandler: nil)
        }
        player.scheduleBuffer(preparedBuffer.buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = volume
        player.play()
        return true
    }

    // 在 sessionQueue 上把混音器输出音量按余弦曲线降到 0 再停播，避免声音被瞬间切断。
    // 渐降作用在混音器输出上：它对音量变化做平滑过渡，播放器输入音量逐级变化时会带出杂音。
    nonisolated private func fadeOutAndStopPlayer(fadesOut: Bool = true) {
        let mixer = engine.mainMixerNode
        if fadesOut, player.isPlaying, engine.isRunning, configuration.fadeOutDuration > 0.0 {
            let stepInterval = 0.005
            let stepCount = max(Int(configuration.fadeOutDuration / stepInterval), 1)
            for step in 1...stepCount {
                let progress = Double(step) / Double(stepCount)
                mixer.outputVolume = configuration.mixerOutputVolume * Float(0.5 * (1.0 + cos(Double.pi * progress)))
                Thread.sleep(forTimeInterval: stepInterval)
            }
        }

        player.stop()
        player.reset()
        mixer.outputVolume = configuration.mixerOutputVolume
    }

    // 起播完成后记录播放状态；期间若已停止或换了模式，本次结果作废。
    private func finishPlaybackStart(_ mode: AudioMode, requestID: Int, didStart: Bool) {
        guard didStart, requestID == playbackRequestID else {
            return
        }

        activeMode = mode
        isPlaying = true
        lastOutputWasBuiltIn = isOutputBuiltIn
    }

    // 完整停止音频播放，并释放当前会话。
    public func stopPlayback() {
        pendingPlaybackMode = nil
        playbackRequestID += 1
        haltPlayback(deactivatingSession: true)
        activeMode = .off
        isPlaying = false
    }

    // 在 sessionQueue 上停播并暂停引擎，可选停用会话；fadesOut 为假时立即静音。
    private func haltPlayback(deactivatingSession: Bool, fadesOut: Bool = true) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.fadeOutAndStopPlayer(fadesOut: fadesOut)
            self.engine.pause()

            if deactivatingSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
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
            haltPlayback(deactivatingSession: false, fadesOut: false)
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

    private func installPreparedResources(_ resources: PreparedAudioResources) {
        for (mode, preparedBuffer) in resources.buffers {
            buffers[mode] = preparedBuffer.buffer
        }
        for (mode, preparedBuffer) in resources.introBuffers {
            introBuffers[mode] = preparedBuffer.buffer
        }
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
        haltPlayback(deactivatingSession: false)
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
            melodicAssetURL: melodicAssetURL
        ) {
            preparedBuffers[.monotone] = PreparedAudioBuffer(buffer: monotoneBuffer)
        }

        var preparedIntroBuffers: [AudioMode: PreparedAudioBuffer] = [:]
        if let monotoneBuffer = preparedBuffers[.monotone]?.buffer,
           let monotoneIntro = makeFadeInIntro(
               from: monotoneBuffer,
               duration: configuration.monotoneAsset.fadeInDuration
           ) {
            preparedIntroBuffers[.monotone] = PreparedAudioBuffer(buffer: monotoneIntro)
        }

        return PreparedAudioResources(
            buffers: preparedBuffers,
            introBuffers: preparedIntroBuffers
        )
    }

    nonisolated private static func makeBuffer(
        for mode: AudioMode,
        configuration: AudioComfortConfiguration,
        melodicAssetURL: URL?
    ) -> AVAudioPCMBuffer? {
        switch mode {
        case .off:
            return nil
        case .monotone:
            // 缓存文件读不出来或规格不符时删除并重建一次；仍失败则单音没有缓冲。
            let expectedFrameCount = AVAudioFrameCount(configuration.sampleRate * configuration.monotoneAsset.duration)
            for _ in 0..<2 {
                guard let url = prepareMonotoneAsset(configuration: configuration) else {
                    return nil
                }

                if let loaded = loadBuffer(from: url),
                   loaded.format.sampleRate == configuration.sampleRate,
                   loaded.format.channelCount == 2,
                   loaded.frameLength == expectedFrameCount {
                    return loaded
                }

                try? FileManager.default.removeItem(at: url)
            }

            return nil
        case .melodic:
            guard let url = melodicAssetURL else {
                return nil
            }

            return loadBuffer(from: url)
        }
    }

    // 复制循环缓冲，让开头 duration 秒按余弦曲线从 0 升到满幅（两端斜率为 0），作为起播引子。
    nonisolated private static func makeFadeInIntro(
        from source: AVAudioPCMBuffer,
        duration: Double
    ) -> AVAudioPCMBuffer? {
        guard duration > 0.0,
              let sourceChannels = source.floatChannelData,
              let intro = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
              let introChannels = intro.floatChannelData
        else {
            return nil
        }

        intro.frameLength = source.frameLength
        let frameCount = Int(source.frameLength)
        let fadeFrameCount = min(Int(duration * source.format.sampleRate), frameCount)

        for channel in 0..<Int(source.format.channelCount) {
            for frame in 0..<frameCount {
                let gain = frame < fadeFrameCount
                    ? Float(0.5 * (1.0 - cos(Double.pi * Double(frame) / Double(fadeFrameCount))))
                    : 1.0
                introChannels[channel][frame] = sourceChannels[channel][frame] * gain
            }
        }

        return intro
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

        // 文件名带上全部波形参数，参数变化后旧文件不再命中。
        let fileName = String(
            format: "monotone_%gHz_%g_%gs_%g.wav",
            configuration.monotoneAsset.frequency,
            Double(configuration.monotoneAsset.amplitude),
            configuration.monotoneAsset.duration,
            configuration.sampleRate
        )
        let url = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            return url
        }

        // 生成新文件前清掉目录里其他参数留下的旧文件。
        for staleURL in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? fileManager.removeItem(at: staleURL)
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
        if let url = Bundle.main.url(forResource: "GStringsFinal", withExtension: "m4a") {
            return url
        }

        return Bundle.main.url(
            forResource: "GStringsFinal",
            withExtension: "m4a",
            subdirectory: "Audio/Resources"
        )
    }
}
