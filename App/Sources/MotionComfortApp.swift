import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

private enum AppShellTiming {
    static let minimumLaunchPlaceholderDuration: Duration = .milliseconds(325)
    static let launchPlaceholderFadeDuration: TimeInterval = 0.265
    static let sessionOverlayFadeDuration: TimeInterval = 0.20
    static let sessionOverlayFadeDelay: Duration = .milliseconds(200)
}

// App 入口：创建全局会话状态，并把首页挂到窗口里。
@main
struct MotionComfortApp: App {
    @StateObject private var model = ComfortSessionViewModel()
    @StateObject private var orientationObserver = InterfaceOrientationObserver()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model, orientationObserver: orientationObserver)
        }
    }
}

private struct AppRootView: View {
    let model: ComfortSessionViewModel
    @ObservedObject private var appShellState: SessionStateStore<AppShellSessionState>
    let orientationObserver: InterfaceOrientationObserver
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("quickStartEnabled") private var quickStartEnabled = false
    @AppStorage("backgroundAudioEnabled") private var backgroundAudioEnabled = false
    @AppStorage("lastVisualGuideStyle") private var lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
    @AppStorage("lastAudioMode") private var lastAudioMode = AudioMode.melodic.rawValue
    @AppStorage("lastDynamicSpeedMultiplier") private var lastDynamicSpeedMultiplier = 2.0
    @AppStorage("lastMotionSensitivityFactor") private var lastMotionSensitivityFactor = 1.0
    @AppStorage("hasShownLiveViewGuidanceToast") private var hasShownLiveViewGuidanceToast = false
    @State private var hasLoadedLaunchPreferences = false
    @State private var hasCompletedMinimumLaunchDisplay = false
    @State private var hasTransitionedFromLaunchPlaceholder = false
    @State private var isSessionOverlayMounted = false
    @State private var isSessionOverlayVisible = false
    @State private var isDashboardChromeActive = true
    @State private var sessionFadeTask: Task<Void, Never>?
    @State private var sessionFadeTaskToken = UUID()
    @State private var sessionDismissTask: Task<Void, Never>?
    @State private var sessionDismissTaskToken = UUID()

    init(model: ComfortSessionViewModel, orientationObserver: InterfaceOrientationObserver) {
        self.model = model
        self._appShellState = ObservedObject(wrappedValue: model.appShellState)
        self.orientationObserver = orientationObserver
    }

    var body: some View {
        ZStack {
            launchDestinationView
                .opacity(hasTransitionedFromLaunchPlaceholder ? 1.0 : 0.0)

            if hasLoadedLaunchPreferences && hasCompletedMinimumLaunchDisplay && isSessionOverlayMounted {
                FullscreenSessionView(
                    model: model,
                    renderState: model.renderState,
                    orientationObserver: orientationObserver,
                    onMotionControlEditingEnded: persistMotionControlPreferencesImmediately
                ) {
                    dismissSessionOverlay()
                }
                .opacity(isSessionOverlayVisible ? 1.0 : 0.0)
                .allowsHitTesting(isSessionOverlayVisible)
                .zIndex(1.0)
            }

            LaunchPlaceholderView()
                .opacity(hasTransitionedFromLaunchPlaceholder ? 0.0 : 1.0)
                .allowsHitTesting(!hasTransitionedFromLaunchPlaceholder)
                .zIndex(2.0)
        }
        .background {
            InterfaceOrientationReader(observer: orientationObserver)
                .frame(width: 0.0, height: 0.0)
        }
        .task {
            await prepareLaunchState()
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: AppShellTiming.sessionOverlayFadeDuration), value: isSessionOverlayVisible)
        .onChange(of: appShellState.value.visualGuideStyle) { _, style in
            guard hasLoadedLaunchPreferences else { return }
            lastVisualGuideStyle = style.rawValue
        }
        .onChange(of: appShellState.value.audioMode) { _, mode in
            guard hasLoadedLaunchPreferences else { return }
            lastAudioMode = mode.rawValue
        }
        .onChange(of: backgroundAudioEnabled) { _, _ in
            syncBackgroundAudioPolicy(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, nextPhase in
            syncBackgroundAudioPolicy(for: nextPhase)
            if nextPhase != .active {
                persistMotionControlPreferencesImmediately()
            }
        }
        .onChange(of: appShellState.value.isSessionPresented) { _, isPresented in
            handleSessionPresentationChanged(isPresented)
        }
        .onDisappear {
            cancelSessionFadeTask()
            cancelSessionDismissTask()
            persistMotionControlPreferencesImmediately()
        }
    }

    @ViewBuilder
    private var launchDestinationView: some View {
        if hasLoadedLaunchPreferences && hasCompletedMinimumLaunchDisplay {
            if hasCompletedWelcome {
                DashboardView(
                    model: model,
                    orientationObserver: orientationObserver,
                    resetWelcomeAndReturnToIntro: resetAppStartupState,
                    quickStartEnabled: $quickStartEnabled,
                    backgroundAudioEnabled: $backgroundAudioEnabled,
                    shouldAutoStartRememberedSession: quickStartEnabled,
                    isChromeActive: isDashboardChromeActive
                )
            } else {
                WelcomeIntroView(orientationObserver: orientationObserver) {
                    hasCompletedWelcome = true
                }
            }
        }
    }

    private func prepareLaunchState() async {
        guard !hasTransitionedFromLaunchPlaceholder else { return }

        if !hasLoadedLaunchPreferences {
            restorePersistedSessionSelection()
            hasLoadedLaunchPreferences = true
        }

        try? await Task.sleep(for: AppShellTiming.minimumLaunchPlaceholderDuration)
        hasCompletedMinimumLaunchDisplay = true

        withAnimation(.easeInOut(duration: AppShellTiming.launchPlaceholderFadeDuration)) {
            hasTransitionedFromLaunchPlaceholder = true
        }
    }

    private func restorePersistedSessionSelection() {
        let restoredVisualStyle = VisualGuideStyle(rawValue: lastVisualGuideStyle) ?? .dynamic
        let restoredAudioMode = AudioMode(rawValue: lastAudioMode) ?? .melodic
        let restoredDynamicSpeedMultiplier = min(max(lastDynamicSpeedMultiplier, 0.0), 6.0)
        let restoredMotionSensitivityFactor = min(max(lastMotionSensitivityFactor, 2.0 / 3.0), 1.5)

        if VisualGuideStyle(rawValue: lastVisualGuideStyle) == nil {
            lastVisualGuideStyle = restoredVisualStyle.rawValue
        }

        if AudioMode(rawValue: lastAudioMode) == nil {
            lastAudioMode = restoredAudioMode.rawValue
        }

        lastDynamicSpeedMultiplier = restoredDynamicSpeedMultiplier
        lastMotionSensitivityFactor = restoredMotionSensitivityFactor
        model.visualGuideStyle = restoredVisualStyle
        model.audioMode = restoredAudioMode
        model.dynamicSpeedMultiplier = restoredDynamicSpeedMultiplier
        model.motionSensitivityFactor = restoredMotionSensitivityFactor
    }

    private func resetAppStartupState() {
        hasCompletedWelcome = false
        quickStartEnabled = false
        hasShownLiveViewGuidanceToast = false
        lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
        lastAudioMode = AudioMode.melodic.rawValue
        lastDynamicSpeedMultiplier = 2.0
        lastMotionSensitivityFactor = 1.0
        model.visualGuideStyle = .dynamic
        model.audioMode = .melodic
        model.dynamicSpeedMultiplier = 2.0
        model.motionSensitivityFactor = 1.0
    }

    private func persistMotionControlPreferencesImmediately() {
        guard hasLoadedLaunchPreferences else { return }
        lastDynamicSpeedMultiplier = model.dynamicSpeedMultiplier
        lastMotionSensitivityFactor = model.motionSensitivityFactor
    }

    private func syncBackgroundAudioPolicy(for phase: ScenePhase) {
        guard model.audioMode != .off else {
            return
        }

        switch phase {
        case .active:
            model.startAudioIfNeeded()
        case .inactive, .background:
            if !backgroundAudioEnabled {
                model.stopAudioPlayback()
            }
        @unknown default:
            break
        }
    }

    private func handleSessionPresentationChanged(_ isPresented: Bool) {
        if isPresented {
            cancelSessionDismissTask()
            cancelSessionFadeTask()

            isDashboardChromeActive = false
            isSessionOverlayMounted = true
            withAnimation(.easeInOut(duration: AppShellTiming.sessionOverlayFadeDuration)) {
                isSessionOverlayVisible = true
            }

            scheduleSessionFadeCompletion()
        } else if isSessionOverlayMounted {
            cancelSessionFadeTask()
            isDashboardChromeActive = true
            withAnimation(.easeInOut(duration: AppShellTiming.sessionOverlayFadeDuration)) {
                isSessionOverlayVisible = false
            }

            scheduleSessionDismissCompletion(finishesSession: false)
        }
    }

    private func dismissSessionOverlay() {
        cancelSessionFadeTask()
        cancelSessionDismissTask()
        isDashboardChromeActive = true
        model.prepareForSessionDismiss()
        withAnimation(.easeInOut(duration: AppShellTiming.sessionOverlayFadeDuration)) {
            isSessionOverlayVisible = false
        }

        scheduleSessionDismissCompletion(finishesSession: true)
    }

    private func cancelSessionFadeTask() {
        sessionFadeTaskToken = UUID()
        sessionFadeTask?.cancel()
        sessionFadeTask = nil
    }

    private func cancelSessionDismissTask() {
        sessionDismissTaskToken = UUID()
        sessionDismissTask?.cancel()
        sessionDismissTask = nil
    }

    private func scheduleSessionFadeCompletion() {
        let token = UUID()
        cancelSessionFadeTask()
        sessionFadeTaskToken = token
        sessionFadeTask = Task { @MainActor in
            try? await Task.sleep(for: AppShellTiming.sessionOverlayFadeDelay)
            guard !Task.isCancelled else { return }
            guard sessionFadeTaskToken == token else { return }
            guard model.isSessionPresented, isSessionOverlayMounted, isSessionOverlayVisible else {
                return
            }

            model.completeSessionFadeIn()
            isDashboardChromeActive = false

            guard sessionFadeTaskToken == token else { return }
            sessionFadeTask = nil
        }
    }

    private func scheduleSessionDismissCompletion(finishesSession: Bool) {
        let token = UUID()
        cancelSessionDismissTask()
        sessionDismissTaskToken = token
        sessionDismissTask = Task { @MainActor in
            try? await Task.sleep(for: AppShellTiming.sessionOverlayFadeDelay)
            guard !Task.isCancelled else { return }
            guard sessionDismissTaskToken == token else { return }
            guard isSessionOverlayMounted, !isSessionOverlayVisible else {
                return
            }

            if finishesSession {
                await model.finishSessionDismiss()
                guard !Task.isCancelled else { return }
                guard sessionDismissTaskToken == token else { return }
                guard isSessionOverlayMounted, !isSessionOverlayVisible else {
                    return
                }
            } else if model.isSessionPresented {
                return
            }

            isSessionOverlayMounted = false

            guard sessionDismissTaskToken == token else { return }
            sessionDismissTask = nil
        }
    }
}

private struct LaunchPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("WelcomeLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 160.0, height: 160.0)
        }
    }
}
