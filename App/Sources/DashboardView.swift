import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    let resetWelcomeAndReturnToIntro: () -> Void

    @State private var isSessionPresented = false
    @State private var isSettingsPresented = false
    @State private var hasAnimatedIn = false

    var body: some View {
        ZStack {
            SharedChromeBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24.0) {
                    headerSection
                    modeCardsSection
                    audioSection
                    settingsSection
                }
                .padding(.horizontal, 22.0)
                .padding(.top, 34.0)
                .padding(.bottom, 34.0)
                .opacity(hasAnimatedIn ? 1.0 : 0.0)
                .offset(y: hasAnimatedIn ? 0.0 : 18.0)
            }
        }
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsPanel(
                resetWelcomeAndReturnToIntro: {
                    isSettingsPresented = false
                    resetWelcomeAndReturnToIntro()
                }
            )
            .presentationDetents([.fraction(0.36), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(34.0)
            .presentationBackground {
                SettingsSheetBackground()
            }
        }
        .onChange(of: model.isRunning) { _, isRunning in
            if !isRunning {
                isSessionPresented = false
            }
        }
        .task {
            DynamicRenderPreheater.prewarm()
        }
        .onAppear {
            guard !hasAnimatedIn else { return }
            withAnimation(.easeOut(duration: 1.35).delay(0.10)) {
                hasAnimatedIn = true
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            Text("MotionComfort")
                .font(.system(size: 36.0, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Choose a visual mode to start the exact fullscreen session experience you already tuned.")
                .font(.system(size: 16.0, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeCardsSection: some View {
        VStack(spacing: 16.0) {
            ModeLaunchCard(
                title: "Minimal",
                subtitle: "Stable peripheral guidance with a clean and lightweight fullscreen session.",
                action: {
                    startSession(style: .minimal)
                }
            )

            ModeLaunchCard(
                title: "Dynamic",
                subtitle: "Richer motion cues with the current dynamic fullscreen visuals unchanged.",
                action: {
                    startSession(style: .dynamic)
                }
            )

            ModeLaunchCard(
                title: "Live View",
                subtitle: "Launch the existing camera-based fullscreen guidance without changing its behavior.",
                action: {
                    startSession(style: .liveView)
                }
            )
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            Text("Audio Mode")
                .font(.system(size: 15.0, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))

            AudioModeGlassControl(selection: $model.audioMode)
        }
    }

    private var settingsSection: some View {
        Button(action: {
            isSettingsPresented = true
        }) {
            Text("More Settings")
                .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56.0)
                .glassEffect(
                    .clear.tint(Color.black.opacity(0.36)).interactive(),
                    in: .rect(cornerRadius: 28.0)
                )
        }
        .buttonStyle(.plain)
    }

    private func startSession(style: VisualGuideStyle) {
        guard !isSessionPresented else {
            return
        }

        model.visualGuideStyle = style
        model.start()
        isSessionPresented = true
    }

    private func handleSessionDismiss() {
        if model.isRunning {
            model.stop()
        }
    }
}

private struct ModeLaunchCard: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10.0) {
                Text(title)
                    .font(.system(size: 28.0, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 15.0, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22.0)
            .padding(.vertical, 24.0)
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .rect(cornerRadius: 30.0)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPanel: View {
    let resetWelcomeAndReturnToIntro: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22.0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 24.0, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14.0, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38.0, height: 38.0)
                        .glassEffect(
                            .clear.tint(Color.black.opacity(0.36)).interactive(),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: resetWelcomeAndReturnToIntro) {
                Text("Reset Welcome Screen")
                    .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54.0)
                    .glassEffect(
                        .clear.tint(Color.black.opacity(0.36)).interactive(),
                        in: .rect(cornerRadius: 27.0)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0.0)
        }
        .padding(.horizontal, 22.0)
        .padding(.top, 22.0)
        .padding(.bottom, 12.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

private struct SettingsSheetBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Color.black.opacity(0.30)
        }
        .ignoresSafeArea()
    }
}

struct WelcomeIntroView: View {
    let enterApp: () -> Void

    @State private var showLogo = false
    @State private var showLineOne = false
    @State private var showLineTwo = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            SharedChromeBackground()

            VStack(spacing: 18.0) {
                Spacer()

                logoBlock
                    .opacity(showLogo ? 1.0 : 0.0)
                    .offset(y: showLogo ? 0.0 : 14.0)

                Text("Placeholder headline for welcome intro")
                    .font(.system(size: 34.0, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showLineOne ? 1.0 : 0.0)
                    .offset(y: showLineOne ? 0.0 : 14.0)

                Text("Placeholder supporting copy for the first-launch MotionComfort experience.")
                    .font(.system(size: 17.0, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320.0)
                    .opacity(showLineTwo ? 1.0 : 0.0)
                    .offset(y: showLineTwo ? 0.0 : 14.0)

                Spacer()

                Button(action: enterApp) {
                    Text("Experience")
                        .font(.system(size: 18.0, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58.0)
                        .glassEffect(
                            .clear.tint(Color.black.opacity(0.36)).interactive(),
                            in: .rect(cornerRadius: 29.0)
                        )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 320.0)
                .opacity(showButton ? 1.0 : 0.0)
                .offset(y: showButton ? 0.0 : 14.0)
                .padding(.bottom, 56.0)
            }
            .padding(.horizontal, 24.0)
        }
        .task {
            withAnimation(.easeOut(duration: 2.10).delay(3.0)) {
                showLogo = true
            }
            withAnimation(.easeOut(duration: 2.10).delay(6.0)) {
                showLineOne = true
            }
            withAnimation(.easeOut(duration: 2.10).delay(9.0)) {
                showLineTwo = true
            }
            withAnimation(.easeOut(duration: 2.10).delay(12.0)) {
                showButton = true
            }
        }
    }

    private var logoBlock: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.09, green: 0.80, blue: 0.92).opacity(0.16))
                .frame(width: 168.0, height: 168.0)
                .blur(radius: 26.0)

            Image(systemName: "wave.3.forward.circle.fill")
                .font(.system(size: 72.0, weight: .medium))
                .foregroundStyle(Color(red: 0.11, green: 0.84, blue: 0.95))
        }
    }
}

struct SharedChromeBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    Color(red: 0.012, green: 0.012, blue: 0.020)
                        .ignoresSafeArea()

                    blob(
                        color: Color(red: 0.00, green: 0.92, blue: 0.84).opacity(0.18),
                        size: width * 0.78,
                        blur: width * 0.17,
                        x: (-width * 0.12) + (sin(time * 0.17) * width * 0.06),
                        y: (-height * 0.05) + (cos(time * 0.13) * height * 0.05)
                    )

                    blob(
                        color: Color(red: 0.08, green: 0.28, blue: 1.00).opacity(0.18),
                        size: width * 0.82,
                        blur: width * 0.18,
                        x: (width * 0.14) + (cos(time * 0.14) * width * 0.06),
                        y: (height * 0.01) + (sin(time * 0.11) * height * 0.05)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.16, blue: 0.24).opacity(0.13),
                        size: width * 0.70,
                        blur: width * 0.16,
                        x: (-width * 0.02) + (sin(time * 0.16) * width * 0.05),
                        y: (height * 0.14) + (cos(time * 0.18) * height * 0.05)
                    )

                    blob(
                        color: Color.white.opacity(0.10),
                        size: width * 0.64,
                        blur: width * 0.14,
                        x: (width * 0.04) + (cos(time * 0.20) * width * 0.05),
                        y: (-height * 0.12) + (sin(time * 0.15) * height * 0.04)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.86, blue: 0.22).opacity(0.12),
                        size: width * 0.62,
                        blur: width * 0.14,
                        x: (width * 0.02) + (sin(time * 0.12) * width * 0.04),
                        y: (height * 0.26) + (cos(time * 0.14) * height * 0.04)
                    )

                    Rectangle()
                        .fill(Color.black.opacity(0.34))
                        .ignoresSafeArea()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func blob(
        color: Color,
        size: CGFloat,
        blur: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .blendMode(.screen)
            .offset(x: x, y: y)
    }
}
