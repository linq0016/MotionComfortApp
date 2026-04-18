import Combine
import Foundation
import MotionComfortAudio
import MotionComfortCore
import MotionComfortVisual

// 会话中控：把界面、运动输入、视觉状态和音频状态串起来。
@MainActor
final class ComfortSessionViewModel: ObservableObject {
    @Published var visualGuideStyle: VisualGuideStyle = .minimal
    @Published var motionInputMode: MotionInputMode = .realTime
    @Published var audioMode: AudioMode = .off {
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

    var severityLabel: String {
        switch sample.intensity {
        case 0.0..<0.2:
            return "Stable"
        case 0.2..<0.45:
            return "Light motion"
        case 0.45..<0.75:
            return "Building motion"
        default:
            return "High motion"
        }
    }

    var comfortNote: String {
        if !visualGuideStyle.isImplemented {
            return "Dynamic keeps its own placeholder session so the visual routing and exit flow stay stable while that mode is still in parallel development."
        }

        if audioMode != .off {
            return "Visual guidance stays primary. Audio remains optional and conservative."
        }

        switch visualGuideStyle {
        case .minimal:
            return "Minimal stays the clearest baseline route and remains the safest default product mode."
        case .dynamic:
            return "Dynamic is still a placeholder route."
        case .liveView:
            return "Live View keeps the real camera route front and center, with edge cues only around the reading area."
        }
    }

    var motionModeLabel: String {
        motionInputMode.title
    }

    var motionModeNote: String {
        if motionInputMode == .realTime && !motionManager.isLiveMotionAvailable {
            return "Real-time motion is currently unavailable on this device session."
        }

        return motionInputMode.note
    }

    var visualGuideStyleNote: String {
        visualGuideStyle.note
    }

    // 启动当前选择的 motion 和 audio 模式。
    func start() {
        motionManager.start(mode: motionInputMode)

        if audioMode != .off {
            audioEngine.setMode(audioMode)
        }
    }

    // 停止会话，并把视觉状态收回到中性值。
    func stop() {
        motionManager.stop()
        audioEngine.stopPlayback()
    }

    // 把最新运动快照同步到页面和音频层。
    private func ingest(_ sample: MotionSample) {
        self.sample = sample

        if isRunning {
            audioEngine.update(with: sample)
        }
    }
}
