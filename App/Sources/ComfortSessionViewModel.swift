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
    @Published private(set) var liveViewCamera: LiveViewCameraModel?

    private let motionManager = MotionManager()
    private let audioEngine = AudioComfortEngine()
    private var cancellables: Set<AnyCancellable> = []
    private var liveViewCameraStateCancellable: AnyCancellable?
    private var loadingFeedbackTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var deniedDismissTask: Task<Void, Never>?
    private var liveViewTeardownTask: Task<Void, Never>?
    private var loadingVisibleAt: ContinuousClock.Instant?
    private var launchAttemptID: UInt64 = 0
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

    }

    // 启动当前选择的 motion 和 audio 模式。
    func start() {
        if visualGuideStyle == .dynamic {
            dynamicSpeedMultiplier = 1.0
        }

        motionManager.start(mode: motionInputMode)
    }

    func beginSessionLaunch(style: VisualGuideStyle) {
        guard !isLaunchInteractionLocked else {
            return
        }

        launchAttemptID &+= 1
        let attemptID = launchAttemptID
        cancelTransientLaunchTasks()
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        visualGuideStyle = style
        sessionLaunchState = .preparing(style: style)

        scheduleLoadingFeedback(attemptID: attemptID)

        if style == .liveView {
            beginLiveViewLaunch(attemptID: attemptID)
        } else if style == .dynamic {
            beginDynamicLaunch(attemptID: attemptID)
        } else {
            start()
            schedulePresentation(for: .minimal, attemptID: attemptID)
        }
    }

    func startAudioIfNeeded() {
        guard isRunning, audioMode != .off else {
            return
        }

        audioEngine.setMode(audioMode)
    }

    func completeSessionPresentation() {
        guard case .preparing(let style) = sessionLaunchState else {
            return
        }

        schedulePresentation(for: style, attemptID: launchAttemptID)
    }

    func cancelSessionLaunchIfNeeded() {
        launchAttemptID &+= 1
        cancelTransientLaunchTasks()

        if case .preparing(let style) = sessionLaunchState, style == .liveView {
            beginLiveViewTeardown()
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
        launchAttemptID &+= 1
        cancelTransientLaunchTasks()
        motionManager.stop()
        audioEngine.stopPlayback()
        dynamicSpeedMultiplier = 1.0
        sessionLaunchOverlayState = .none
        loadingVisibleAt = nil
        sessionLaunchState = .idle

        if liveViewCamera != nil {
            beginLiveViewTeardown()
        }
    }

    // 把最新运动快照同步到页面和音频层。
    private func ingest(_ sample: MotionSample) {
        self.sample = sample

        if isRunning {
            audioEngine.update(with: sample)
        }
    }

    private func beginLiveViewLaunch(attemptID: UInt64) {
        Task { [weak self] in
            guard let self else {
                return
            }

            let status = await LiveViewCameraPreflight.ensureAuthorized()
            #if DEBUG
            debugLiveViewLaunch("preflight result: \(String(describing: status))", attemptID: attemptID)
            #endif
            await MainActor.run {
                guard self.launchAttemptID == attemptID,
                      case .preparing(let style) = self.sessionLaunchState,
                      style == .liveView else {
                    return
                }

                switch status {
                case .authorized:
                    if let liveViewTeardownTask = self.liveViewTeardownTask {
                        #if DEBUG
                        self.debugLiveViewLaunch("waiting for previous teardown before relaunch", attemptID: attemptID)
                        #endif
                        Task { [weak self] in
                            await liveViewTeardownTask.value
                            await MainActor.run {
                                guard let self,
                                      self.launchAttemptID == attemptID,
                                      case .preparing(let style) = self.sessionLaunchState,
                                      style == .liveView else {
                                    return
                                }

                                self.beginLiveViewLaunch(attemptID: attemptID)
                            }
                        }
                        return
                    }

                    if let existingCamera = self.liveViewCamera {
                        #if DEBUG
                        self.debugLiveViewLaunch("reusing existing camera instance", attemptID: attemptID)
                        #endif
                        self.start()
                        existingCamera.start()
                        return
                    }

                    let camera = LiveViewCameraModel(launchAttemptID: attemptID)
                    self.setLiveViewCamera(camera)
                    self.start()
                    camera.start()
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

    private func beginDynamicLaunch(attemptID: UInt64) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await DynamicRenderPreheater.ensureReady()
            await MainActor.run {
                guard self.launchAttemptID == attemptID,
                      case .preparing(let style) = self.sessionLaunchState,
                      style == .dynamic else {
                    return
                }

                self.start()
                self.schedulePresentation(for: .dynamic, attemptID: attemptID)
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
            guard let liveViewCamera, liveViewCamera.canShowPreview else {
                return
            }
            schedulePresentation(for: .liveView, attemptID: launchAttemptID)
        }
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
            if previewState == .unavailable {
                resetLiveViewLaunchFailure()
                return
            }

            guard previewState == .ready, isRunning, self.isRunning else {
                return
            }

            schedulePresentation(for: .liveView, attemptID: launchAttemptID)
        case .notDetermined:
            return
        @unknown default:
            presentDeniedToast(for: .liveView)
        }
    }

    private func scheduleLoadingFeedback(attemptID: UInt64) {
        loadingFeedbackTask?.cancel()
        loadingFeedbackTask = Task { [weak self] in
            guard let self else {
                return
            }

            await Task.yield()
            try? await Task.sleep(for: loadingFeedbackDelay)
            await MainActor.run {
                guard self.launchAttemptID == attemptID,
                      case .preparing = self.sessionLaunchState else {
                    return
                }

                self.loadingVisibleAt = self.clock.now
                self.sessionLaunchOverlayState = .loading
            }
        }
    }

    private func schedulePresentation(for style: VisualGuideStyle, attemptID: UInt64) {
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
                guard self.launchAttemptID == attemptID,
                      case .preparing(let currentStyle) = self.sessionLaunchState,
                      currentStyle == style else {
                    return
                }

                self.sessionLaunchOverlayState = .none
                self.loadingVisibleAt = nil
                self.sessionLaunchState = .presenting(style: style)
            }
        }
    }

    private func presentDeniedToast(for style: VisualGuideStyle) {
        launchAttemptID &+= 1
        cancelTransientLaunchTasks()
        loadingVisibleAt = nil
        sessionLaunchState = .denied(style: style)
        sessionLaunchOverlayState = .denied

        beginLiveViewTeardown()

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

    private func resetLiveViewLaunchFailure() {
        launchAttemptID &+= 1
        cancelTransientLaunchTasks()
        loadingVisibleAt = nil
        sessionLaunchOverlayState = .none
        sessionLaunchState = .idle

        beginLiveViewTeardown()
    }

    func completeSessionFadeIn() {
        guard case .presenting = sessionLaunchState else {
            return
        }
    }

    func prepareForSessionDismiss() {
        launchAttemptID &+= 1
        cancelTransientLaunchTasks()
        sessionLaunchOverlayState = .none
        if visualGuideStyle == .liveView {
            beginLiveViewTeardown()
        }
    }

    func finishSessionDismiss() async {
        motionManager.stop()
        audioEngine.stopPlayback()
        if let liveViewTeardownTask {
            await liveViewTeardownTask.value
        } else {
            await teardownLiveViewCamera()
        }
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

    private func setLiveViewCamera(_ camera: LiveViewCameraModel?) {
        liveViewCameraStateCancellable?.cancel()
        liveViewCamera = camera

        guard let camera else {
            liveViewCameraStateCancellable = nil
            return
        }

        liveViewCameraStateCancellable = Publishers.CombineLatest3(
            camera.$status.removeDuplicates(),
            camera.$previewState.removeDuplicates(),
            camera.$isRunning.removeDuplicates()
        )
        .sink { [weak self] status, previewState, isRunning in
            self?.handleLiveViewCameraUpdate(
                status: status,
                previewState: previewState,
                isRunning: isRunning
            )
        }
    }

    private func beginLiveViewTeardown() {
        guard liveViewTeardownTask == nil else {
            return
        }

        guard liveViewCamera != nil else {
            return
        }

        liveViewTeardownTask = Task { [weak self] in
            guard let self else {
                return
            }

            if let camera = await MainActor.run(body: { self.liveViewCamera }) {
                await MainActor.run {
                    camera.detachPreviewForTeardown()
                }
            }

            await self.teardownLiveViewCamera()
            await MainActor.run {
                self.liveViewTeardownTask = nil
            }
        }
    }

    private func teardownLiveViewCamera() async {
        guard let camera = liveViewCamera else {
            setLiveViewCamera(nil)
            return
        }

        await camera.stopAndWait()
        guard liveViewCamera === camera else {
            return
        }
        setLiveViewCamera(nil)
    }

    #if DEBUG
    private func debugLiveViewLaunch(_ message: String, attemptID: UInt64) {
        print("[LiveView][attempt \(attemptID)] \(message)")
    }
    #endif
}
