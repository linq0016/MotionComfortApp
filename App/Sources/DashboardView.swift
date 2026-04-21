import MotionComfortAudio
import MotionComfortVisual
import SwiftUI

struct DashboardView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    let resetWelcomeAndReturnToIntro: () -> Void
    @Binding var quickStartEnabled: Bool
    let shouldAutoStartRememberedSession: Bool

    @State private var isSettingsPresented = false
    @State private var showHeaderSection = false
    @State private var showModeCardsSection = false
    @State private var showAudioSection = false
    @State private var showSettingsSection = false
    @State private var didAttemptAutoStart = false
    @State private var isLaunchDimVisible = false
    @State private var launchDimDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            SharedChromeBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24.0) {
                    headerSection
                        .opacity(showHeaderSection ? 1.0 : 0.0)
                        .offset(y: showHeaderSection ? 0.0 : 14.0)

                    modeCardsSection
                        .opacity(showModeCardsSection ? 1.0 : 0.0)
                        .offset(y: showModeCardsSection ? 0.0 : 14.0)

                    audioSection
                        .opacity(showAudioSection ? 1.0 : 0.0)
                        .offset(y: showAudioSection ? 0.0 : 14.0)

                    settingsSection
                        .opacity(showSettingsSection ? 1.0 : 0.0)
                        .offset(y: showSettingsSection ? 0.0 : 14.0)
                }
                .padding(.horizontal, 22.0)
                .padding(.top, 34.0)
                .padding(.bottom, 34.0)
            }
            .allowsHitTesting(!model.isLaunchInteractionLocked)

            if isLaunchDimVisible || model.sessionLaunchOverlayState != .none {
                SessionLaunchOverlay(
                    overlayState: model.sessionLaunchOverlayState,
                    showDim: isLaunchDimVisible
                )
                    .transition(.opacity)
            }

        }
        .allowsHitTesting(!model.isSessionPresented)
        .animation(.easeInOut(duration: 0.18), value: model.sessionLaunchOverlayState)
        .animation(.easeInOut(duration: 0.18), value: isLaunchDimVisible)
        .background {
            InterfaceOrientationReader(observer: orientationObserver)
                .frame(width: 0.0, height: 0.0)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsPanel(
                quickStartEnabled: $quickStartEnabled,
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
        .task {
            DynamicRenderPreheater.prewarm()
        }
        .onAppear {
            playDashboardEntranceAnimation()

            guard shouldAutoStartRememberedSession, !didAttemptAutoStart else { return }
            didAttemptAutoStart = true

            Task { @MainActor in
                launchSession(style: model.visualGuideStyle)
            }
        }
        .onChange(of: model.sessionLaunchOverlayState) { _, newValue in
            handleLaunchOverlayStateChange(newValue)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            HStack(alignment: .center, spacing: 10.0) {
                Image("WelcomeLogo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: isEnglishInterface ? 72.0 : 48.0, height: isEnglishInterface ? 72.0 : 48.0)

                if isEnglishInterface {
                    VStack(alignment: .leading, spacing: 0.0) {
                        Text("Stellar:")
                            .font(.system(size: 32.0, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Motion Comfort")
                            .font(.system(size: 24.0, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .multilineTextAlignment(.leading)
                } else {
                    Text("dashboard.title")
                        .font(.system(size: 32.0, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
            }

            Text("dashboard.subtitle")
                .font(.system(size: 16.0, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeCardsSection: some View {
        VStack(spacing: 16.0) {
            ModeLaunchCard(
                title: String(localized: "visual_mode.minimal"),
                subtitle: String(localized: "dashboard.mode.minimal.subtitle"),
                action: {
                    launchSession(style: .minimal)
                }
            )

            ModeLaunchCard(
                title: String(localized: "visual_mode.dynamic"),
                subtitle: String(localized: "dashboard.mode.dynamic.subtitle"),
                action: {
                    launchSession(style: .dynamic)
                }
            )

            ModeLaunchCard(
                title: String(localized: "visual_mode.live_view"),
                subtitle: String(localized: "dashboard.mode.live_view.subtitle"),
                action: {
                    launchSession(style: .liveView)
                }
            )
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                Text("dashboard.audio_mode")
                    .font(.system(size: 24.0, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))

                Text("dashboard.audio_mode.supporting_copy")
                    .font(.system(size: 14.0, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            AudioModeGlassControl(selection: $model.audioMode, controlWidth: nil, controlHeight: 60.0)
                .frame(maxWidth: .infinity)
                .frame(height: 60.0)

            Text(audioModeDetailText)
                .font(.system(size: 15.0, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsSection: some View {
        Button(action: {
            isSettingsPresented = true
        }) {
            Text("dashboard.more_settings")
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

    private func launchSession(style: VisualGuideStyle) {
        model.beginSessionLaunch(style: style)
    }

    private var audioModeDetailText: LocalizedStringKey {
        switch model.audioMode {
        case .melodic:
            return "dashboard.audio_mode.detail.melodic"
        case .monotone:
            return "dashboard.audio_mode.detail.mono"
        case .off:
            return "dashboard.audio_mode.detail.off"
        }
    }

    private var isEnglishInterface: Bool {
        locale.language.languageCode?.identifier == "en"
    }

    private func playDashboardEntranceAnimation() {
        showHeaderSection = false
        showModeCardsSection = false
        showAudioSection = false
        showSettingsSection = false

        withAnimation(.easeOut(duration: 0.30)) {
            showHeaderSection = true
        }

        withAnimation(.easeOut(duration: 0.30).delay(0.30)) {
            showModeCardsSection = true
        }

        withAnimation(.easeOut(duration: 0.30).delay(0.60)) {
            showAudioSection = true
        }

        withAnimation(.easeOut(duration: 0.30).delay(0.90)) {
            showSettingsSection = true
        }
    }

    private func handleLaunchOverlayStateChange(_ newValue: SessionLaunchOverlayState) {
        launchDimDismissTask?.cancel()
        launchDimDismissTask = nil

        if newValue != .none {
            isLaunchDimVisible = true
            return
        }

        launchDimDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            isLaunchDimVisible = false
            launchDimDismissTask = nil
        }
    }
}

private struct SessionLaunchOverlay: View {
    let overlayState: SessionLaunchOverlayState
    let showDim: Bool

    var body: some View {
        ZStack {
            if showDim {
                Color.black
                    .opacity(0.12)
                    .ignoresSafeArea()
            }

            if overlayState != .none {
                SessionLaunchToast(overlayState: overlayState)
                    .padding(.horizontal, 24.0)
            }
        }
    }
}

private struct SessionLaunchToast: View {
    let overlayState: SessionLaunchOverlayState

    var body: some View {
        GlassEffectContainer(spacing: 14.0) {
            HStack(spacing: 14.0) {
                if overlayState == .loading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 18.0, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                }

                Text(messageKey)
                    .font(.system(size: 18.0, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20.0)
            .padding(.vertical, 16.0)
            .glassEffect(
                .clear.tint(Color.black.opacity(0.56)),
                in: .rect(cornerRadius: 28.0)
            )
        }
    }

    private var messageKey: LocalizedStringKey {
        switch overlayState {
        case .loading:
            return "session.loading.title"
        case .denied:
            return "session.camera_access_denied.title"
        case .none:
            return "session.loading.title"
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
    @Binding var quickStartEnabled: Bool
    let resetWelcomeAndReturnToIntro: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer(spacing: 18.0) {
            VStack(alignment: .leading, spacing: 22.0) {
                HStack {
                    Text("settings.title")
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
                                .clear.tint(Color.black.opacity(0.24)).interactive(),
                                in: .circle
                            )
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                                    .blendMode(.screen)
                            }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 18.0) {
                    VStack(alignment: .leading, spacing: 8.0) {
                        Toggle(isOn: $quickStartEnabled) {
                            Text("settings.express_startup")
                                .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Text("settings.express_startup.supporting_copy")
                            .font(.system(size: 13.0, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: resetWelcomeAndReturnToIntro) {
                        Text("settings.reset_welcome")
                            .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54.0)
                            .glassEffect(
                                .clear.tint(Color.black.opacity(0.24)).interactive(),
                                in: .rect(cornerRadius: 27.0)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 27.0, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                                    .blendMode(.screen)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0.0)
            }
            .padding(.horizontal, 22.0)
            .padding(.top, 22.0)
            .padding(.bottom, 12.0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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

    private enum OnboardingStep {
        case intro
        case audioTips
    }

    @State private var step: OnboardingStep = .intro
    @State private var showLogo = false
    @State private var showLineOne = false
    @State private var showLineTwo = false
    @State private var showButton = false
    @State private var showSecondPage = false
    @State private var isTransitioning = false

    var body: some View {
        ZStack {
            SharedChromeBackground()

            if step == .intro {
                introPage
                    .transition(.identity)
            } else {
                audioTipsPage
                    .transition(.identity)
            }
        }
        .task {
            guard step == .intro else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                showLogo = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(1.0)) {
                showLineOne = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(2.0)) {
                showLineTwo = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(3.0)) {
                showButton = true
            }
        }
    }

    private var introPage: some View {
        VStack(spacing: 18.0) {
            Spacer()

            logoBlock
                .opacity(showLogo ? 1.0 : 0.0)
                .offset(y: showLogo ? 0.0 : 14.0)

            Text("welcome.headline")
                .font(.system(size: 34.0, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(showLineOne ? 1.0 : 0.0)
                .offset(y: showLineOne ? 0.0 : 14.0)

            Text("welcome.supporting_copy")
                .font(.system(size: 17.0, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320.0)
                .opacity(showLineTwo ? 1.0 : 0.0)
                .offset(y: showLineTwo ? 0.0 : 14.0)

            Spacer()

            welcomeActionButton(titleKey: "welcome.cta", action: advanceToAudioTips)
                .opacity(showButton ? 1.0 : 0.0)
                .offset(y: showButton ? 0.0 : 14.0)
                .padding(.bottom, 56.0)
        }
        .padding(.horizontal, 24.0)
    }

    private var audioTipsPage: some View {
        VStack(spacing: 0.0) {
            Spacer()

            VStack(spacing: 18.0) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 60.0, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.75))

                Text("welcome.audio_tip.headphones")
                    .font(.system(size: 18.0, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                Spacer()
                    .frame(height: 24.0)

                Image("TransparencyModeIcon")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 74.25, height: 85.8)
                    .opacity(0.75)

                Text("welcome.audio_tip.transparency")
                    .font(.system(size: 18.0, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320.0)
            }

            Spacer()

            welcomeActionButton(titleKey: "welcome.cta.experience", action: enterApp)
                .padding(.bottom, 56.0)
        }
        .padding(.horizontal, 24.0)
        .opacity(showSecondPage ? 1.0 : 0.0)
        .offset(y: showSecondPage ? 0.0 : 14.0)
    }

    private func welcomeActionButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey)
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
        .disabled(isTransitioning)
        .frame(maxWidth: 320.0)
    }

    private func advanceToAudioTips() {
        guard !isTransitioning else { return }

        isTransitioning = true

        withAnimation(.easeInOut(duration: 0.45)) {
            showLogo = false
            showLineOne = false
            showLineTwo = false
            showButton = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(460))
            step = .audioTips

            withAnimation(.easeInOut(duration: 0.45)) {
                showSecondPage = true
            }

            isTransitioning = false
        }
    }

    private var logoBlock: some View {
        MotionComfortLogoImage(
            size: 154.0
        )
    }
}

struct MotionComfortLogoImage: View {
    let size: CGFloat

    var body: some View {
        Image("WelcomeLogo")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .compositingGroup()
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
