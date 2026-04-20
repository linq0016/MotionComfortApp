import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

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
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("quickStartEnabled") private var quickStartEnabled = false
    @AppStorage("lastVisualGuideStyle") private var lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
    @AppStorage("lastAudioMode") private var lastAudioMode = AudioMode.melodic.rawValue
    @State private var hasLoadedLaunchPreferences = false
    @State private var hasCompletedMinimumLaunchDisplay = false
    @State private var hasTransitionedFromLaunchPlaceholder = false
    @State private var isSessionOverlayMounted = false
    @State private var isSessionOverlayVisible = false

    var body: some View {
        ZStack {
            launchDestinationView
                .opacity(hasTransitionedFromLaunchPlaceholder ? 1.0 : 0.0)

            if hasLoadedLaunchPreferences && hasCompletedMinimumLaunchDisplay && isSessionOverlayMounted {
                FullscreenSessionView(model: model, orientationObserver: orientationObserver) {
                    dismissSessionOverlay()
                }
                .opacity(isSessionOverlayVisible ? 1.0 : 0.0)
                .zIndex(1.0)
            }

            if !hasTransitionedFromLaunchPlaceholder {
                LaunchPlaceholderView()
                    .transition(.opacity)
                    .zIndex(2.0)
            }
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
                    shouldAutoStartRememberedSession: quickStartEnabled
                )
            } else {
                WelcomeIntroView {
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
        lastVisualGuideStyle = VisualGuideStyle.dynamic.rawValue
        lastAudioMode = AudioMode.melodic.rawValue
        model.visualGuideStyle = .dynamic
        model.audioMode = .melodic
    }

    private func handleSessionPresentationChanged(_ isPresented: Bool) {
        if isPresented {
            isSessionOverlayMounted = true
            withAnimation(.easeInOut(duration: 0.28)) {
                isSessionOverlayVisible = true
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                if model.isSessionPresented {
                    model.completeSessionFadeIn()
                }
            }
        } else if isSessionOverlayMounted {
            withAnimation(.easeInOut(duration: 0.28)) {
                isSessionOverlayVisible = false
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                if !model.isSessionPresented {
                    isSessionOverlayMounted = false
                }
            }
        }
    }

    private func dismissSessionOverlay() {
        model.prepareForSessionDismiss()
        withAnimation(.easeInOut(duration: 0.28)) {
            isSessionOverlayVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            isSessionOverlayMounted = false
            model.stop()
        }
    }
}

private struct LaunchPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("LaunchLogo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 132.0, height: 132.0)
                .compositingGroup()
        }
    }
}
