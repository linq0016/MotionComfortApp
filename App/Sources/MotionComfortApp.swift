import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

// App 入口：创建全局会话状态，并把首页挂到窗口里。
@main
struct MotionComfortApp: App {
    @StateObject private var model = ComfortSessionViewModel()
    @StateObject private var orientationObserver = InterfaceOrientationObserver()

    init() {
        NetworkAccessPolicy.install()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model, orientationObserver: orientationObserver)
        }
    }
}

private struct AppRootView: View {
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("quickStartEnabled") private var quickStartEnabled = false
    @AppStorage("backgroundAudioEnabled") private var backgroundAudioEnabled = true
    @AppStorage("lastVisualGuideStyle") private var lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
    @AppStorage("lastAudioMode") private var lastAudioMode = AudioMode.melodic.rawValue
    @AppStorage("hasShownLiveViewGuidanceToast") private var hasShownLiveViewGuidanceToast = false
    @State private var hasLoadedLaunchPreferences = false
    @State private var hasCompletedMinimumLaunchDisplay = false
    @State private var hasTransitionedFromLaunchPlaceholder = false
    @State private var isSessionOverlayMounted = false
    @State private var isSessionOverlayVisible = false
    @State private var sessionFadeTask: Task<Void, Never>?
    @State private var sessionDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            launchDestinationView
                .opacity(hasTransitionedFromLaunchPlaceholder ? 1.0 : 0.0)

            if hasLoadedLaunchPreferences && hasCompletedMinimumLaunchDisplay && isSessionOverlayMounted {
                FullscreenSessionView(model: model, orientationObserver: orientationObserver) {
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
        .task {
            await prepareLaunchState()
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.28), value: isSessionOverlayVisible)
        .onChange(of: model.visualGuideStyle) { _, style in
            guard hasLoadedLaunchPreferences else { return }
            lastVisualGuideStyle = style.rawValue
        }
        .onChange(of: model.audioMode) { _, mode in
            guard hasLoadedLaunchPreferences else { return }
            lastAudioMode = mode.rawValue
        }
        .onChange(of: backgroundAudioEnabled) { _, _ in
            syncBackgroundAudioPolicy(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, nextPhase in
            syncBackgroundAudioPolicy(for: nextPhase)
        }
        .onChange(of: model.isSessionPresented) { _, isPresented in
            handleSessionPresentationChanged(isPresented)
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
                    shouldAutoStartRememberedSession: quickStartEnabled
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

        try? await Task.sleep(for: .milliseconds(325))
        hasCompletedMinimumLaunchDisplay = true

        withAnimation(.easeInOut(duration: 0.265)) {
            hasTransitionedFromLaunchPlaceholder = true
        }
    }

    private func restorePersistedSessionSelection() {
        let restoredVisualStyle = VisualGuideStyle(rawValue: lastVisualGuideStyle) ?? .dynamic
        let restoredAudioMode = AudioMode(rawValue: lastAudioMode) ?? .melodic

        if VisualGuideStyle(rawValue: lastVisualGuideStyle) == nil {
            lastVisualGuideStyle = restoredVisualStyle.rawValue
        }

        if AudioMode(rawValue: lastAudioMode) == nil {
            lastAudioMode = restoredAudioMode.rawValue
        }

        model.visualGuideStyle = restoredVisualStyle
        model.audioMode = restoredAudioMode
    }

    private func resetAppStartupState() {
        hasCompletedWelcome = false
        quickStartEnabled = false
        hasShownLiveViewGuidanceToast = false
        lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
        lastAudioMode = AudioMode.melodic.rawValue
        model.visualGuideStyle = .dynamic
        model.audioMode = .melodic
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
            sessionDismissTask?.cancel()
            sessionDismissTask = nil
            sessionFadeTask?.cancel()

            isSessionOverlayMounted = true
            withAnimation(.easeInOut(duration: 0.28)) {
                isSessionOverlayVisible = true
            }

            sessionFadeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                if model.isSessionPresented {
                    model.completeSessionFadeIn()
                }
                sessionFadeTask = nil
            }
        } else if isSessionOverlayMounted {
            sessionFadeTask?.cancel()
            sessionFadeTask = nil
            withAnimation(.easeInOut(duration: 0.28)) {
                isSessionOverlayVisible = false
            }

            sessionDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                if !model.isSessionPresented {
                    isSessionOverlayMounted = false
                }
                sessionDismissTask = nil
            }
        }
    }

    private func dismissSessionOverlay() {
        sessionFadeTask?.cancel()
        sessionFadeTask = nil
        sessionDismissTask?.cancel()
        model.prepareForSessionDismiss()
        withAnimation(.easeInOut(duration: 0.28)) {
            isSessionOverlayVisible = false
        }

        sessionDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await model.finishSessionDismiss()
            isSessionOverlayMounted = false
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

enum NetworkAccessPolicy {
    static func install() {
        URLProtocol.registerClass(BlockAllNetworkRequestsProtocol.self)
    }
}

private final class BlockAllNetworkRequestsProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let error = URLError(.appTransportSecurityRequiresSecureConnection)
        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {
        // No-op: requests are rejected immediately.
    }
}
