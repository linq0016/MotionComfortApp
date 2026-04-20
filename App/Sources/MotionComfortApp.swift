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

    var body: some View {
        Group {
            if hasCompletedWelcome {
                DashboardView(
                    model: model,
                    orientationObserver: orientationObserver,
                    resetWelcomeAndReturnToIntro: {
                        hasCompletedWelcome = false
                    }
                )
            } else {
                WelcomeIntroView {
                    hasCompletedWelcome = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
