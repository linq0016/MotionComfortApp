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
                metricsSection
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
        .overlay(alignment: .bottomTrailing) {
            LiveMotionDebugOverlay(model: model)
                .padding(.trailing, 16.0)
                .padding(.bottom, 16.0)
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

                Text("Three visual routes, three audio routes, one stable session architecture.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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

                Text("Live View now uses the real camera route. Dynamic and melodic still open into dedicated placeholders, so the final routing stays stable.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6.0)
        }
    }

    private var visualSection: some View {
        Section("Visual") {
            Toggle("Peripheral visual guidance", isOn: $model.visualGuidesEnabled)

            Picker("Visual mode", selection: $model.visualGuideStyle) {
                ForEach(VisualGuideStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)

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

    private var metricsSection: some View {
        Section("Live Motion") {
            LabeledContent("Lateral G", value: valueString(model.sample.lateralAcceleration))
            LabeledContent("Longitudinal G", value: valueString(model.sample.longitudinalAcceleration))
            LabeledContent("Yaw", value: valueString(model.sample.yawRate))
        }
    }

    private var safetySection: some View {
        Section("Safety") {
            Text("Passenger use only. Keep the volume low. Monotone remains a conservative 100 Hz signal path, and melodic is still a placeholder.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Real-time mode reads deviceMotion.userAcceleration directly. Live View now runs the real camera preview in a stable SDR path.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Recommended current setup: Minimal + Real-time Motion + Off or Monotone.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func valueString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
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

// 全局调试浮窗：在任意页面显示当前设备坐标系下的运动数据。
struct LiveMotionDebugOverlay: View {
    @ObservedObject var model: ComfortSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                Label("Live motion", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(.headline, design: .rounded).weight(.bold))

                Spacer(minLength: 0.0)

                Text(model.motionInputMode.title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text("Flat phone axes: X / Y / Z G")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))

            HStack(spacing: 8.0) {
                axisTile(
                    title: "X",
                    unit: "G",
                    value: valueString(model.sample.lateralAcceleration),
                    subtitle: "left/right"
                )
                axisTile(
                    title: "Y",
                    unit: "G",
                    value: valueString(-model.sample.longitudinalAcceleration),
                    subtitle: "top/bottom"
                )
                axisTile(
                    title: "Z",
                    unit: "G",
                    value: valueString(model.sample.verticalAcceleration),
                    subtitle: "out/in"
                )
            }

            Text("Raw X / Y / Z device axes stay here, while the main session can reinterpret them as vehicle-oriented cues.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 262.0, alignment: .leading)
        .padding(14.0)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22.0, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22.0, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.28), radius: 18.0, x: 0.0, y: 8.0)
        .allowsHitTesting(false)
    }

    private func axisTile(title: String, unit: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4.0) {
            HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))

            Text(subtitle)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10.0)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16.0, style: .continuous))
    }

    private func valueString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}
