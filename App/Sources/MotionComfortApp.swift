import SwiftUI

// App 入口：创建全局会话状态，并把首页挂到窗口里。
@main
struct MotionComfortApp: App {
    @StateObject private var model = ComfortSessionViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
        }
    }
}
