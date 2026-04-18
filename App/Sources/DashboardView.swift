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
                heroSection
                visualSection
                motionSection
                audioSection
                sessionSection
                safetySection
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

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12.0) {
                Text("MotionComfort")
                    .font(.system(size: 34.0, weight: .bold, design: .rounded))

                Text("Choose a visual route first, then layer motion input and optional audio on top of it.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Current focus: \(model.visualGuideStyle.title)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Text(model.comfortNote)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6.0)
        }
    }

    private var visualSection: some View {
        Section("Visual Mode") {
            Picker("Visual mode", selection: $model.visualGuideStyle) {
                ForEach(VisualGuideStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Status", value: model.visualGuideStyle.statusTitle)

            Text(model.visualGuideStyleNote)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var motionSection: some View {
        Section("Motion Input") {
            Picker("Motion input", selection: $model.motionInputMode) {
                ForEach(MotionInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(model.motionModeNote)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Picker("Audio mode", selection: $model.audioMode) {
                ForEach(AudioMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(model.audioMode.note)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionSection: some View {
        Section("Session") {
            LabeledContent("Visual route", value: model.visualGuideStyle.title)
            LabeledContent("Motion input", value: model.motionModeLabel)
            LabeledContent("Audio route", value: model.audioMode.title)

            Text(model.comfortNote)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: startSession) {
                Label("Start fullscreen session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.74, blue: 0.85))

            Text("Minimal and Live View are live routes. Dynamic still enters its own placeholder session, and melodic now loops the bundled asset.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var safetySection: some View {
        Section("Safety") {
            Text("Passenger use only. Keep the volume low. Monotone remains a conservative 100 Hz signal path, and melodic loops the bundled music asset.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Real-time mode reads deviceMotion.userAcceleration directly. Live View runs the real camera preview in a stable SDR path.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Recommended current setup: Minimal + Real-time Motion + Off or Monotone.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
