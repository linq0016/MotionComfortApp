import AVFoundation
import Combine
import Foundation
import MotionComfortAudio
import MotionComfortCore
import MotionComfortVisual

enum SessionLaunchState: Equatable {
    case idle
    case preparing(style: VisualGuideStyle)
    case denied(style: VisualGuideStyle)
    case presenting(style: VisualGuideStyle)
}

enum SessionLaunchOverlayState: Equatable {
    case none
    case loading
    case denied
}

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
    @Published private(set) var sessionLaunchState: SessionLaunchState = .idle
    @Published private(set) var sessionLaunchOverlayState: SessionLaunchOverlayState = .none

    private let motionManager = MotionManager()
    private let audioEngine = AudioComfortEngine()
    let liveViewCamera = LiveViewCameraModel()
    private var cancellables: Set<AnyCancellable> = []
    private var loadingFeedbackTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var deniedDismissTask: Task<Void, Never>?
    private var loadingVisibleAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private let loadingFeedbackDelay: Duration = .milliseconds(150)
    private let minimumLoadingVisibility: Duration = .milliseconds(300)
    private let deniedToastVisibility: Duration = .seconds(1.5)

    init() {
        motionManager.$sample
            .sink { [weak self] sample in
                self?.ingest(sample)
            }
            .store(in: &cancellables)

        motionManager.$isRunning
            .sink { [weak self] running in
                self?.handleMotionRunningChanged(running)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            liveViewCamera.$status.removeDuplicates(),
            liveViewCamera.$previewState.removeDuplicates(),
            liveViewCamera.$isRunning.removeDuplicates()
        )
            .sink { [weak self] status, previewState, isRunning in
                self?.handleLiveViewCameraUpdate(
                    status: status,
                    previewState: previewState,
                    isRunning: isRunning
                )
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

    func beginSessionLaunch(
        style: VisualGuideStyle,
        loadingFeedbackStart: ContinuousClock.Instant? = nil
    ) {
        guard !isLaunchInteractionLocked else {
            return
        }

        cancelTransientLaunchTasks()
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        visualGuideStyle = style
        sessionLaunchState = .preparing(style: style)

        scheduleLoadingFeedback(startedAt: loadingFeedbackStart ?? clock.now)

        if style == .liveView {
            beginLiveViewLaunch()
        } else if style == .dynamic {
            beginDynamicLaunch()
        } else {
            start()
        }
    }

    func startAudioIfNeeded() {
        guard isRunning, audioMode != .off else {
            return
        }

        audioEngine.setMode(audioMode)
    }

    func stopAudioPlayback() {
        audioEngine.stopPlayback()
    }

    func completeSessionPresentation() {
        guard case .preparing(let style) = sessionLaunchState else {
            return
        }

        schedulePresentation(for: style)
    }

    func cancelSessionLaunchIfNeeded() {
        cancelTransientLaunchTasks()

        if case .preparing(let style) = sessionLaunchState, style == .liveView {
            liveViewCamera.stop()
        }

        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        sessionLaunchState = .idle
    }

    var isLaunchInteractionLocked: Bool {
        switch sessionLaunchState {
        case .idle, .denied:
            return false
        case .preparing, .presenting:
            return true
        }
    }

    var isSessionPresented: Bool {
        if case .presenting = sessionLaunchState {
            return true
        }
        return false
    }

    // 停止会话，并把视觉状态收回到中性值。
    func stop() {
        cancelTransientLaunchTasks()
        motionManager.stop()
        audioEngine.stopPlayback()
        liveViewCamera.stop()
        dynamicSpeedMultiplier = 1.0
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        sessionLaunchState = .idle
    }

    // 把最新运动快照同步到页面和音频层。
    private func ingest(_ sample: MotionSample) {
        self.sample = sample

        if isRunning {
            audioEngine.update(with: sample)
        }
    }

    private func beginLiveViewLaunch() {
        Task { [weak self] in
            guard let self else {
                return
            }

            let status = await LiveViewCameraPreflight.ensureAuthorized()
            await MainActor.run {
                guard case .preparing(let style) = self.sessionLaunchState, style == .liveView else {
                    return
                }

                switch status {
                case .authorized:
                    self.start()
                    self.liveViewCamera.start()
                case .denied, .restricted:
                    self.presentDeniedToast(for: .liveView)
                case .notDetermined:
                    self.sessionLaunchOverlayState = .loading
                @unknown default:
                    self.presentDeniedToast(for: .liveView)
                }
            }
        }
    }

    private func beginDynamicLaunch() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await DynamicRenderPreheater.ensureReady()
            await MainActor.run {
                guard case .preparing(let style) = self.sessionLaunchState, style == .dynamic else {
                    return
                }

                self.start()
            }
        }
    }

    private func handleMotionRunningChanged(_ running: Bool) {
        isRunning = running

        guard running else {
            if case .presenting = sessionLaunchState {
                sessionLaunchState = .idle
            }
            return
        }

        guard case .preparing(let style) = sessionLaunchState else {
            return
        }

        if style == .liveView {
            guard liveViewCamera.canShowPreview else {
                return
            }
        }

        schedulePresentation(for: style)
    }

    private func handleLiveViewCameraUpdate(
        status: AVAuthorizationStatus,
        previewState: LiveViewPreviewState,
        isRunning: Bool
    ) {
        guard case .preparing(let style) = sessionLaunchState, style == .liveView else {
            return
        }

        switch status {
        case .denied, .restricted:
            presentDeniedToast(for: .liveView)
        case .authorized:
            guard previewState == .ready, isRunning, self.isRunning else {
                return
            }

            schedulePresentation(for: .liveView)
        case .notDetermined:
            return
        @unknown default:
            presentDeniedToast(for: .liveView)
        }
    }

    private func scheduleLoadingFeedback(startedAt: ContinuousClock.Instant) {
        loadingFeedbackTask?.cancel()
        loadingFeedbackTask = Task { [weak self] in
            guard let self else {
                return
            }

            let elapsed = startedAt.duration(to: clock.now)
            let remainingDelay = elapsed < loadingFeedbackDelay ? loadingFeedbackDelay - elapsed : .zero
            if remainingDelay > .zero {
                try? await Task.sleep(for: remainingDelay)
            }
            await MainActor.run {
                guard case .preparing = self.sessionLaunchState else {
                    return
                }

                self.loadingVisibleAt = self.clock.now
                self.sessionLaunchOverlayState = .loading
            }
        }
    }

    private func schedulePresentation(for style: VisualGuideStyle) {
        presentationTask?.cancel()
        loadingFeedbackTask?.cancel()
        let remainingDelay = remainingLoadingVisibility
        presentationTask = Task { [weak self] in
            guard let self else {
                return
            }

            if remainingDelay > .zero {
                try? await Task.sleep(for: remainingDelay)
            }

            await MainActor.run {
                guard case .preparing(let currentStyle) = self.sessionLaunchState, currentStyle == style else {
                    return
                }

                self.sessionLaunchOverlayState = .none
                self.loadingVisibleAt = nil
                self.sessionLaunchState = .presenting(style: style)
            }
        }
    }

    private func presentDeniedToast(for style: VisualGuideStyle) {
        cancelTransientLaunchTasks()
        liveViewCamera.stop()
        loadingVisibleAt = nil
        sessionLaunchState = .denied(style: style)
        sessionLaunchOverlayState = .denied

        deniedDismissTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: deniedToastVisibility)
            await MainActor.run {
                guard case .denied(let deniedStyle) = self.sessionLaunchState, deniedStyle == style else {
                    return
                }

                self.sessionLaunchOverlayState = .none
                self.sessionLaunchState = .idle
            }
        }
    }

    func completeSessionFadeIn() {
        guard case .presenting = sessionLaunchState else {
            return
        }
    }

    func prepareForSessionDismiss() {
        sessionLaunchOverlayState = .none
    }

    func finishSessionDismiss() async {
        motionManager.stop()
        audioEngine.stopPlayback()
        liveViewCamera.stop()
        dynamicSpeedMultiplier = 1.0
        loadingVisibleAt = nil
        sessionLaunchState = .idle
        isRunning = false
    }

    private var remainingLoadingVisibility: Duration {
        guard sessionLaunchOverlayState == .loading, let loadingVisibleAt else {
            return .zero
        }

        let elapsed = loadingVisibleAt.duration(to: clock.now)
        return elapsed < minimumLoadingVisibility ? minimumLoadingVisibility - elapsed : .zero
    }

    private func cancelTransientLaunchTasks() {
        loadingFeedbackTask?.cancel()
        loadingFeedbackTask = nil

        presentationTask?.cancel()
        presentationTask = nil

        deniedDismissTask?.cancel()
        deniedDismissTask = nil
    }
}
