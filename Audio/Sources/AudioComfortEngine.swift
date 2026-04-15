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

    public init(sampleRate: Double = 22_050.0) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            fatalError("Unable to create stereo audio format.")
        }

        self.engine = AVAudioEngine()
        self.player = AVAudioPlayerNode()
        self.format = format
        self.isPlaying = false
        self.activeMode = .off
        self.buffers = [:]

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
        player.volume = 0.05
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

        let baseVolume: Double = activeMode == .monotone ? 0.04 : 0.06
        let dynamicGain = sample.intensity * 0.12
        player.volume = Float(clamp(baseVolume + dynamicGain, minimum: 0.02, maximum: 0.18))
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
            return makeLoopBuffer(
                duration: 2.0,
                layers: [(100.0, 0.10), (200.0, 0.03)],
                modulationFrequency: 0.10
            )
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
        let phaseOffset = Double.pi / 3.0

        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]

            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / format.sampleRate
                let modulation = 0.72 + (0.28 * sin((2.0 * Double.pi * modulationFrequency * time) + (channel == 0 ? 0.0 : phaseOffset)))
                let stereoShift = channel == 0 ? 0.98 : 1.02
                var mixedValue = 0.0

                for layer in layers {
                    mixedValue += sin((2.0 * Double.pi * layer.frequency * time) + (Double(channel) * 0.02)) * layer.amplitude
                }

                samples[frame] = Float(mixedValue * modulation * stereoShift)
            }
        }

        return buffer
    }
}
