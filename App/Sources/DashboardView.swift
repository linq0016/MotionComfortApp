import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

// 首页配置页：负责模式选择、状态查看和进入全屏会话。
struct DashboardView: View {
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    @State private var isSessionPresented = false

    var body: some View {
        ZStack {
            backgroundLayer

            List {
                DashboardTitleSection()

                DashboardPickerSection(title: "Visual Mode") {
                    Picker("Visual mode", selection: $model.visualGuideStyle) {
                        ForEach(VisualGuideStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                DashboardPickerSection(title: "Motion Input") {
                    Picker("Motion input", selection: $model.motionInputMode) {
                        ForEach(MotionInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                DashboardPickerSection(title: "Audio") {
                    Picker("Audio mode", selection: $model.audioMode) {
                        ForEach(AudioMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                DashboardSessionSection(
                    visualTitle: model.visualGuideStyle.title,
                    motionTitle: model.motionInputMode.title,
                    audioTitle: model.audioMode.title,
                    startSession: startSession
                )
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .preferredColorScheme(.dark)
        .background {
            InterfaceOrientationReader(observer: orientationObserver)
                .frame(width: 0.0, height: 0.0)
        }
        .fullScreenCover(isPresented: $isSessionPresented, onDismiss: handleSessionDismiss) {
            FullscreenSessionView(model: model, orientationObserver: orientationObserver) {
                isSessionPresented = false
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: model.isRunning) { _, isRunning in
            if !isRunning {
                isSessionPresented = false
            }
        }
        .task {
            DynamicRenderPreheater.prewarm()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.20, green: 0.75, blue: 0.82).opacity(0.18))
                .frame(width: 360.0, height: 280.0)
                .blur(radius: 92.0)
                .offset(x: -180.0, y: -250.0)

            Circle()
                .fill(Color(red: 0.16, green: 0.32, blue: 0.72).opacity(0.16))
                .frame(width: 320.0, height: 260.0)
                .blur(radius: 104.0)
                .offset(x: 180.0, y: 330.0)
        }
        .allowsHitTesting(false)
    }

    private func startSession() {
        guard !isSessionPresented else {
            return
        }

        model.start()
        isSessionPresented = true
    }

    private func handleSessionDismiss() {
        if model.isRunning {
            model.stop()
        }
    }
}

private struct DashboardTitleSection: View {
    var body: some View {
        Section {
            Text("MotionComfort")
                .font(.system(size: 34.0, weight: .bold, design: .rounded))
                .padding(.vertical, 6.0)
        }
    }
}

private struct DashboardPickerSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section(title) {
            content
        }
    }
}

private struct DashboardSessionSection: View {
    let visualTitle: String
    let motionTitle: String
    let audioTitle: String
    let startSession: () -> Void

    var body: some View {
        Section("Session") {
            LabeledContent("Visual", value: visualTitle)
            LabeledContent("Motion", value: motionTitle)
            LabeledContent("Audio", value: audioTitle)

            Button(action: startSession) {
                Label("Start fullscreen session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.74, blue: 0.85))
        }
    }
}
