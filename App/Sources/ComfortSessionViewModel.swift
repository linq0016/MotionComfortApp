import Combine
import Foundation
import MotionComfortAudio
import MotionComfortCore
import MotionComfortVisual

// 会话中控：把界面、运动输入、视觉状态和音频状态串起来。
@MainActor
final class ComfortSessionViewModel: ObservableObject {
    @Published var visualGuideStyle: VisualGuideStyle = .dynamic
    @Published var motionInputMode: MotionInputMode = .realTime
    @Published var dynamicSpeedMultiplier = 1.0
    @Published var audioMode: AudioMode = .melodic {
        didSet {
            guard isRunning else {
                return
            }

            audioEngine.setMode(audioMode)
        }
    }

    @Published private(set) var sample: MotionSample = .neutral
    @Published private(set) var isRunning = false

    private let motionManager = MotionManager()
    private let audioEngine = AudioComfortEngine()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        motionManager.$sample
            .sink { [weak self] sample in
                self?.ingest(sample)
            }
            .store(in: &cancellables)

        motionManager.$isRunning
            .sink { [weak self] running in
                self?.isRunning = running
            }
            .store(in: &cancellables)
    }

    // 启动当前选择的 motion 和 audio 模式。
    func start() {
        if visualGuideStyle == .dynamic {
            dynamicSpeedMultiplier = 1.0
        }

        motionManager.start(mode: motionInputMode)
    }

    func startAudioIfNeeded() {
        guard isRunning, audioMode != .off else {
            return
        }

        audioEngine.setMode(audioMode)
    }

    // 停止会话，并把视觉状态收回到中性值。
    func stop() {
        motionManager.stop()
        audioEngine.stopPlayback()
        dynamicSpeedMultiplier = 1.0
    }

    // 把最新运动快照同步到页面和音频层。
    private func ingest(_ sample: MotionSample) {
        self.sample = sample

        if isRunning {
            audioEngine.update(with: sample)
        }
    }
}
