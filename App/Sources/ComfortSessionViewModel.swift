import AVFoundation
import Combine
import Foundation
import MotionComfortAudio
import MotionComfortCore
import MotionComfortVisual

private enum SessionLaunchTiming {
    static let loadingFeedbackDelay: Duration = .milliseconds(100)
    static let minimumLoadingVisibility: Duration = .milliseconds(200)
    static let deniedToastVisibility: Duration = .seconds(1.5)
}

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

struct AppShellSessionState: Equatable {
    var visualGuideStyle: VisualGuideStyle = .dynamic
    var audioMode: AudioMode = .melodic
    var isSessionPresented = false
}

struct DashboardSessionState: Equatable {
    var visualGuideStyle: VisualGuideStyle = .dynamic
    var audioMode: AudioMode = .melodic
    var sessionLaunchOverlayState: SessionLaunchOverlayState = .none
    var isLaunchInteractionLocked = false
    var isSessionPresented = false
}

@MainActor
final class SessionRenderState: ObservableObject {
    @Published private(set) var sample: MotionSample = .neutral

    func update(sample: MotionSample) {
        self.sample = sample
    }
}

@MainActor
final class SessionStateStore<State: Equatable>: ObservableObject {
    @Published private(set) var value: State

    init(_ value: State) {
        self.value = value
    }

    func update(_ nextValue: State) {
        guard nextValue != value else {
            return
        }

        value = nextValue
    }
}

// 会话中控：把界面、运动输入、视觉状态和音频状态串起来。
@MainActor
final class ComfortSessionViewModel: ObservableObject {
    @Published var visualGuideStyle: VisualGuideStyle = .dynamic {
        didSet {
            syncDerivedSessionState()
        }
    }
    @Published var motionInputMode: MotionInputMode = .realTime
    @Published var dynamicSpeedMultiplier = 2.0
    @Published var motionSensitivityFactor = 1.0
    @Published var audioMode: AudioMode = .melodic {
        didSet {
            syncDerivedSessionState()

            if audioMode != .off {
                audioEngine.prewarmResourcesIfNeeded()
            }

            guard isRunning else {
                return
            }

            audioEngine.setMode(audioMode)
        }
    }

    private(set) var sample: MotionSample = .neutral
    @Published private(set) var isRunning = false
    @Published private(set) var sessionLaunchState: SessionLaunchState = .idle {
        didSet {
            syncDerivedSessionState()
        }
    }
    @Published private(set) var sessionLaunchOverlayState: SessionLaunchOverlayState = .none {
        didSet {
            syncDerivedSessionState()
        }
    }

    let renderState = SessionRenderState()
    let appShellState = SessionStateStore(AppShellSessionState())
    let dashboardState = SessionStateStore(DashboardSessionState())
    private let motionManager = MotionManager()
    private let audioEngine = AudioComfortEngine()
    let liveViewCamera = LiveViewCameraModel()
    private var cancellables: Set<AnyCancellable> = []
    private var launchPreparationTask: Task<Void, Never>?
    private var launchPreparationToken = UUID()
    private var loadingFeedbackTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var deniedDismissTask: Task<Void, Never>?
    private var loadingVisibleAt: Date?

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
        motionManager.start(mode: motionInputMode)
    }

    func beginSessionLaunch(
        style: VisualGuideStyle,
        loadingFeedbackStart: Date? = nil
    ) {
        guard !isLaunchInteractionLocked else {
            return
        }

        cancelTransientLaunchTasks()
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        visualGuideStyle = style
        sessionLaunchState = .preparing(style: style)

        scheduleLoadingFeedback(startedAt: loadingFeedbackStart ?? Date())

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

        audioEngine.prewarmResourcesIfNeeded()
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
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        sessionLaunchState = .idle
    }

    // 把最新运动快照同步到页面和音频层。
    private func ingest(_ sample: MotionSample) {
        self.sample = sample
        renderState.update(sample: sample)

        if isRunning {
            audioEngine.update(with: sample)
        }
    }

    private func syncDerivedSessionState() {
        appShellState.update(
            AppShellSessionState(
                visualGuideStyle: visualGuideStyle,
                audioMode: audioMode,
                isSessionPresented: isSessionPresented
            )
        )
        dashboardState.update(
            DashboardSessionState(
                visualGuideStyle: visualGuideStyle,
                audioMode: audioMode,
                sessionLaunchOverlayState: sessionLaunchOverlayState,
                isLaunchInteractionLocked: isLaunchInteractionLocked,
                isSessionPresented: isSessionPresented
            )
        )
    }

    private func beginLiveViewLaunch() {
        startLaunchPreparationTask(for: .liveView) { [weak self] token in
            guard let self else {
                return
            }

            let status = await LiveViewCameraPreflight.ensureAuthorized()
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self.isCurrentLaunchPreparation(token, style: .liveView) else {
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
        startLaunchPreparationTask(for: .dynamic) { [weak self] token in
            guard let self else {
                return
            }

            await DynamicRenderPreheater.ensureReady()
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self.isCurrentLaunchPreparation(token, style: .dynamic) else {
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

    private func scheduleLoadingFeedback(startedAt: Date) {
        loadingFeedbackTask?.cancel()
        loadingFeedbackTask = Task { [weak self] in
            guard let self else {
                return
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            let remainingDelay = max(0.0, SessionLaunchTiming.loadingFeedbackDelay.timeInterval - elapsed)
            if remainingDelay > .zero {
                try? await Task.sleep(for: .seconds(remainingDelay))
            }
            await MainActor.run {
                guard case .preparing = self.sessionLaunchState else {
                    return
                }

                self.loadingVisibleAt = Date()
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

            try? await Task.sleep(for: SessionLaunchTiming.deniedToastVisibility)
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
        loadingVisibleAt = nil
        sessionLaunchState = .idle
        isRunning = false
    }

    private var remainingLoadingVisibility: Duration {
        guard sessionLaunchOverlayState == .loading, let loadingVisibleAt else {
            return .zero
        }

        let elapsed = Date().timeIntervalSince(loadingVisibleAt)
        let remaining = max(0.0, SessionLaunchTiming.minimumLoadingVisibility.timeInterval - elapsed)
        return .seconds(remaining)
    }

    private func cancelTransientLaunchTasks() {
        launchPreparationToken = UUID()
        launchPreparationTask?.cancel()
        launchPreparationTask = nil

        loadingFeedbackTask?.cancel()
        loadingFeedbackTask = nil

        presentationTask?.cancel()
        presentationTask = nil

        deniedDismissTask?.cancel()
        deniedDismissTask = nil
    }

    private func startLaunchPreparationTask(
        for style: VisualGuideStyle,
        operation: @escaping @Sendable (UUID) async -> Void
    ) {
        let token = UUID()
        launchPreparationTask?.cancel()
        launchPreparationToken = token
        launchPreparationTask = Task {
            await operation(token)
            await MainActor.run { [weak self] in
                guard let self, self.isCurrentLaunchPreparation(token, style: style) else {
                    return
                }

                self.launchPreparationTask = nil
            }
        }
    }

    private func isCurrentLaunchPreparation(_ token: UUID, style: VisualGuideStyle) -> Bool {
        guard launchPreparationToken == token else {
            return false
        }

        guard case .preparing(let currentStyle) = sessionLaunchState, currentStyle == style else {
            return false
        }

        return true
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
