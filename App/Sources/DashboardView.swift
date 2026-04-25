import MotionComfortAudio
import MotionComfortVisual
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.locale) private var locale
    let model: ComfortSessionViewModel
    @ObservedObject private var dashboardState: SessionStateStore<DashboardSessionState>
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    let resetWelcomeAndReturnToIntro: () -> Void
    @Binding var quickStartEnabled: Bool
    @Binding var backgroundAudioEnabled: Bool
    let shouldAutoStartRememberedSession: Bool
    var isChromeActive: Bool = true

    @State private var isSettingsPresented = false
    @State private var showHeaderSection = false
    @State private var showModeCardsSection = false
    @State private var showAudioSection = false
    @State private var showSettingsSection = false
    @State private var didAttemptAutoStart = false
    @State private var isLaunchDimVisible = false
    @State private var launchDimDismissTask: Task<Void, Never>?
    @State private var settingsCompactHeight: CGFloat = 360.0
    @State private var settingsSheetDetent: PresentationDetent = .height(360.0)

    init(
        model: ComfortSessionViewModel,
        orientationObserver: InterfaceOrientationObserver,
        resetWelcomeAndReturnToIntro: @escaping () -> Void,
        quickStartEnabled: Binding<Bool>,
        backgroundAudioEnabled: Binding<Bool>,
        shouldAutoStartRememberedSession: Bool,
        isChromeActive: Bool = true
    ) {
        self.model = model
        self._dashboardState = ObservedObject(wrappedValue: model.dashboardState)
        self.orientationObserver = orientationObserver
        self.resetWelcomeAndReturnToIntro = resetWelcomeAndReturnToIntro
        self._quickStartEnabled = quickStartEnabled
        self._backgroundAudioEnabled = backgroundAudioEnabled
        self.shouldAutoStartRememberedSession = shouldAutoStartRememberedSession
        self.isChromeActive = isChromeActive
    }

    var body: some View {
        ZStack {
            SharedChromeBackground(
                orientation: orientationObserver.orientation,
                isActive: isChromeActive
            )

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
                .padding(.horizontal, 24.0)
                .padding(.top, 48.0)
                .padding(.bottom, 62.0)
            }
            .allowsHitTesting(!dashboardState.value.isLaunchInteractionLocked)

            if isLaunchDimVisible || dashboardState.value.sessionLaunchOverlayState != .none {
                SessionLaunchOverlay(
                    overlayState: dashboardState.value.sessionLaunchOverlayState,
                    showDim: isLaunchDimVisible
                )
                    .transition(.opacity)
            }

        }
        .allowsHitTesting(!dashboardState.value.isSessionPresented)
        .animation(.easeInOut(duration: 0.18), value: dashboardState.value.sessionLaunchOverlayState)
        .animation(.easeInOut(duration: 0.18), value: isLaunchDimVisible)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsPanel(
                quickStartEnabled: $quickStartEnabled,
                backgroundAudioEnabled: $backgroundAudioEnabled,
                shouldRenderAboutSection: isLandscapeInterface || settingsSheetDetent == .large,
                onCompactHeightChange: { height in
                    updateSettingsCompactHeight(height)
                },
                resetWelcomeAndReturnToIntro: {
                    isSettingsPresented = false
                    resetWelcomeAndReturnToIntro()
                }
            )
            .presentationDetents([settingsCompactDetent, .large], selection: $settingsSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(54.0)
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
                launchSession(style: dashboardState.value.visualGuideStyle)
            }
        }
        .onChange(of: dashboardState.value.sessionLaunchOverlayState) { _, newValue in
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

            JustifiedParagraphText(
                text: String(localized: "dashboard.subtitle"),
                fontSize: 16.0,
                weight: .regular,
                color: UIColor.white.withAlphaComponent(0.72)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modeCardsSection: some View {
        VStack(spacing: 16.0) {
            ModeLaunchCard(
                iconName: "MinimalModeIcon",
                title: String(localized: "visual_mode.minimal"),
                subtitle: localizedModeCardSubtitle(
                    key: "dashboard.mode.minimal.subtitle"
                ),
                action: {
                    launchSession(style: .minimal)
                }
            )

            ModeLaunchCard(
                iconName: "InterstellarModeIcon",
                title: String(localized: "visual_mode.dynamic"),
                subtitle: localizedModeCardSubtitle(
                    key: "dashboard.mode.dynamic.subtitle"
                ),
                action: {
                    launchSession(style: .dynamic)
                }
            )

            ModeLaunchCard(
                iconName: "LiveViewModeIcon",
                title: String(localized: "visual_mode.live_view"),
                subtitle: localizedModeCardSubtitle(
                    key: "dashboard.mode.live_view.subtitle"
                ),
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

                JustifiedParagraphText(
                    text: String(localized: "dashboard.audio_mode.supporting_copy"),
                    fontSize: 14.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.64)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AudioModeGlassControl(selection: audioModeBinding, controlWidth: nil, controlHeight: 60.0)
                .frame(maxWidth: .infinity)
                .frame(height: 60.0)

            JustifiedParagraphText(
                text: String(localized: audioModeDetailLocalizationValue),
                fontSize: 15.0,
                weight: .regular,
                color: UIColor.white.withAlphaComponent(0.72)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsSection: some View {
        ReliableGlassButton(
            action: {
                settingsSheetDetent = settingsCompactDetent
                isSettingsPresented = true
            },
            shape: .rounded(28.0),
            tintOpacity: 0.36
        ) {
            Text("dashboard.more_settings")
                .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56.0)
        }
    }

    private var settingsCompactDetent: PresentationDetent {
        .height(max(settingsCompactHeight, 1.0))
    }

    private func updateSettingsCompactHeight(_ height: CGFloat) {
        let roundedHeight = ceil(height)
        guard abs(settingsCompactHeight - roundedHeight) > 0.5 else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            settingsCompactHeight = roundedHeight
            if settingsSheetDetent != .large {
                settingsSheetDetent = .height(roundedHeight)
            }
        }
    }

    private func launchSession(style: VisualGuideStyle) {
        model.beginSessionLaunch(
            style: style,
            loadingFeedbackStart: Date()
        )
    }

    private var audioModeBinding: Binding<AudioMode> {
        Binding(
            get: { dashboardState.value.audioMode },
            set: { model.audioMode = $0 }
        )
    }

    private var audioModeDetailText: LocalizedStringKey {
        switch dashboardState.value.audioMode {
        case .melodic:
            return "dashboard.audio_mode.detail.melodic"
        case .monotone:
            return "dashboard.audio_mode.detail.mono"
        case .off:
            return "dashboard.audio_mode.detail.off"
        }
    }

    private var audioModeDetailLocalizationValue: String.LocalizationValue {
        switch dashboardState.value.audioMode {
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

    private var isChineseInterface: Bool {
        locale.language.languageCode?.identifier == "zh"
    }

    private var isLandscapeInterface: Bool {
        switch orientationObserver.orientation {
        case .portrait:
            false
        case .landscapeLeft, .landscapeRight:
            true
        }
    }

    private func localizedModeCardSubtitle(key: String) -> String {
        let subtitle = String(localized: String.LocalizationValue(key))

        guard isChineseInterface, isLandscapeInterface else {
            return subtitle
        }

        return subtitle.replacingOccurrences(of: "\n", with: "")
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
                .clear.tint(Color.black.opacity(0.24)),
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

private enum ReliableGlassButtonShape: Shape {
    case rounded(CGFloat)
    case circle

    func path(in rect: CGRect) -> Path {
        switch self {
        case .rounded(let cornerRadius):
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }
}

private struct ReliableGlassButtonStyle: ButtonStyle {
    let shape: ReliableGlassButtonShape
    let tintOpacity: Double
    let strokeOpacity: Double?
    let strokeLineWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            .glassEffect(
                .clear.tint(Color.black.opacity(tintOpacity)).interactive(),
                in: shape
            )
            .overlay {
                if let strokeOpacity {
                    shape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: strokeLineWidth)
                        .blendMode(.screen)
                }
            }
    }
}

private struct ReliableGlassButton<Label: View>: View {
    let action: () -> Void
    let shape: ReliableGlassButtonShape
    let tintOpacity: Double
    var strokeOpacity: Double? = nil
    var strokeLineWidth: CGFloat = 0.8
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(
            ReliableGlassButtonStyle(
                shape: shape,
                tintOpacity: tintOpacity,
                strokeOpacity: strokeOpacity,
                strokeLineWidth: strokeLineWidth
            )
        )
    }
}

private struct ModeLaunchCard: View {
    let iconName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10.0) {
                HStack(alignment: .center, spacing: 10.0) {
                    Image(iconName)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 36.0, height: 36.0)
                        .opacity(0.75)

                    Text(title)
                        .font(.system(size: 26.0, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                JustifiedParagraphText(
                    text: subtitle,
                    fontSize: 14.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.72),
                    fallbackToNaturalForManualBreaks: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22.0)
            .padding(.vertical, 24.0)
        }
        .buttonStyle(ModeLaunchCardButtonStyle())
    }
}

private struct ModeLaunchCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 38.0, style: .continuous))
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .rect(cornerRadius: 38.0)
            )
            .scaleEffect(configuration.isPressed ? 1.012 : 1.0)
            .animation(
                .spring(response: 0.24, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}

private struct SettingsPanel: View {
    @Binding var quickStartEnabled: Bool
    @Binding var backgroundAudioEnabled: Bool
    let shouldRenderAboutSection: Bool
    let onCompactHeightChange: (CGFloat) -> Void
    let resetWelcomeAndReturnToIntro: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer(spacing: 18.0) {
            VStack(alignment: .leading, spacing: 22.0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18.0) {
                        compactSettingsControls

                        if shouldRenderAboutSection {
                            settingsAboutSection
                                .padding(.top, 8.0)
                        }
                    }
                    .padding(.bottom, 30.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24.0)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background { compactHeightMeasurement }
        .onPreferenceChange(SettingsPanelCompactHeightPreferenceKey.self) { height in
            onCompactHeightChange(height)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var compactSettingsControls: some View {
        settingsToggleSection(
            titleKey: "settings.express_startup",
            supportingCopyKey: "settings.express_startup.supporting_copy",
            isOn: $quickStartEnabled
        )

        settingsToggleSection(
            titleKey: "settings.background_audio",
            supportingCopyKey: "settings.background_audio.supporting_copy",
            isOn: $backgroundAudioEnabled
        )

        resetStellarButton
    }

    private var resetStellarButton: some View {
        ReliableGlassButton(
            action: resetWelcomeAndReturnToIntro,
            shape: .rounded(26.0),
            tintOpacity: 0.24,
            strokeOpacity: 0.15
        ) {
            Text("settings.reset_stellar")
                .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52.0)
        }
        .padding(.horizontal, 2.0)
    }

    private var compactHeightMeasurement: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 22.0) {
                headerMeasurement

                VStack(alignment: .leading, spacing: 18.0) {
                    compactSettingsMeasurementControls
                }
                .padding(.bottom, 30.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24.0)
            .frame(width: proxy.size.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .background {
                GeometryReader { measurementProxy in
                    Color.clear.preference(
                        key: SettingsPanelCompactHeightPreferenceKey.self,
                        value: measurementProxy.size.height
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var compactSettingsMeasurementControls: some View {
        settingsToggleMeasurementSection(
            titleKey: "settings.express_startup",
            supportingCopyKey: "settings.express_startup.supporting_copy"
        )

        settingsToggleMeasurementSection(
            titleKey: "settings.background_audio",
            supportingCopyKey: "settings.background_audio.supporting_copy"
        )

        resetStellarButtonMeasurement
    }

    private var header: some View {
        HStack {
            Text("settings.title")
                .font(.system(size: 24.0, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            ReliableGlassButton(
                action: {
                    dismiss()
                },
                shape: .circle,
                tintOpacity: 0.24,
                strokeOpacity: 0.16
            ) {
                Image(systemName: "xmark")
                    .font(.system(size: 14.0, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38.0, height: 38.0)
            }
        }
        .offset(y: 1.0)
    }

    private var headerMeasurement: some View {
        HStack {
            Text("settings.title")
                .font(.system(size: 24.0, weight: .bold, design: .rounded))

            Spacer()

            Color.clear
                .frame(width: 38.0, height: 38.0)
        }
        .offset(y: 1.0)
    }

    private func settingsToggleSection(
        titleKey: LocalizedStringKey,
        supportingCopyKey: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Toggle(isOn: isOn) {
                Text(titleKey)
                    .font(.system(size: 17.0, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            JustifiedParagraphText(
                text: String(localized: supportingCopyLocalizationValue(for: supportingCopyKey)),
                fontSize: 13.0,
                weight: .regular,
                color: UIColor.white.withAlphaComponent(0.62)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4.0)
    }

    private func settingsToggleMeasurementSection(
        titleKey: LocalizedStringKey,
        supportingCopyKey: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack {
                Text(titleKey)
                    .font(.system(size: 17.0, weight: .semibold, design: .rounded))

                Spacer()

                Color.clear
                    .frame(width: 51.0, height: 31.0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(localized: supportingCopyLocalizationValue(for: supportingCopyKey)))
                .font(.system(size: 13.0, weight: .regular, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4.0)
    }

    private var resetStellarButtonMeasurement: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 52.0)
            .padding(.horizontal, 2.0)
    }

    private var settingsAboutSection: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            HStack(alignment: .firstTextBaseline, spacing: 12.0) {
                Text("settings.about.title")
                    .font(.system(size: 13.0, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.50))

                Spacer(minLength: 12.0)

                Link(destination: privacyPolicyURL) {
                    Text("settings.about.privacy_policy")
                        .underline()
                        .font(.system(size: 12.0, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.44))
                }
            }

            VStack(alignment: .leading, spacing: 8.0) {
                JustifiedParagraphText(
                    text: String(localized: "settings.about.1"),
                    fontSize: 12.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.44)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4.0) {
                    JustifiedParagraphText(
                        text: String(localized: "settings.about.2"),
                        fontSize: 12.0,
                        weight: .regular,
                        color: UIColor.white.withAlphaComponent(0.44)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Link(destination: aboutDetailsURL) {
                        Text("settings.about.link_label")
                            .underline()
                            .font(.system(size: 12.0, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.44))
                    }
                }
                JustifiedParagraphText(
                    text: String(localized: "settings.about.3"),
                    fontSize: 12.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.44)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                JustifiedParagraphText(
                    text: String(localized: "settings.about.4"),
                    fontSize: 12.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.44)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                JustifiedParagraphText(
                    text: String(localized: "settings.about.5"),
                    fontSize: 12.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.44)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                JustifiedParagraphText(
                    text: String(localized: "settings.about.6"),
                    fontSize: 12.0,
                    weight: .regular,
                    color: UIColor.white.withAlphaComponent(0.44)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8.0)
    }

    private func supportingCopyLocalizationValue(for key: LocalizedStringKey) -> String.LocalizationValue {
        switch key {
        case "settings.express_startup.supporting_copy":
            return "settings.express_startup.supporting_copy"
        case "settings.background_audio.supporting_copy":
            return "settings.background_audio.supporting_copy"
        default:
            return ""
        }
    }

    private var aboutDetailsURL: URL {
        URL(string: "https://pubmed.ncbi.nlm.nih.gov/40128952/")!
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://linq0016.github.io/Stellar-Privacy-Policy/")!
    }
}

private struct SettingsPanelCompactHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct JustifiedParagraphText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let weight: UIFont.Weight
    let color: UIColor
    var fallbackToNaturalForManualBreaks: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        applyTextIfNeeded(to: label, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        applyTextIfNeeded(to: uiView, coordinator: context.coordinator)
        let targetWidth = proposal.width ?? uiView.bounds.width.nonZeroOrFallback(320.0)
        uiView.preferredMaxLayoutWidth = targetWidth
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: targetWidth, height: ceil(fittingSize.height))
    }

    private func applyTextIfNeeded(to label: UILabel, coordinator: Coordinator) {
        let signature = TextRenderSignature(
            text: text,
            fontSize: fontSize,
            weightRawValue: weight.rawValue,
            color: color,
            alignment: paragraphAlignment
        )

        guard coordinator.lastSignature != signature || label.attributedText == nil else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = signature.alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: roundedFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        label.attributedText = NSAttributedString(string: text, attributes: attributes)
        coordinator.lastSignature = signature
    }

    private var paragraphAlignment: NSTextAlignment {
        if fallbackToNaturalForManualBreaks && text.contains("\n") {
            return .natural
        }
        return .justified
    }

    private var roundedFont: UIFont {
        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: weight)
        guard let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) else {
            return baseFont
        }
        return UIFont(descriptor: roundedDescriptor, size: fontSize)
    }

    final class Coordinator {
        var lastSignature: TextRenderSignature?
    }

    struct TextRenderSignature: Equatable {
        let text: String
        let fontSize: CGFloat
        let weightRawValue: CGFloat
        let color: UIColor
        let alignment: NSTextAlignment

        static func == (lhs: TextRenderSignature, rhs: TextRenderSignature) -> Bool {
            lhs.text == rhs.text
                && lhs.fontSize == rhs.fontSize
                && lhs.weightRawValue == rhs.weightRawValue
                && lhs.color.isEqual(rhs.color)
                && lhs.alignment == rhs.alignment
        }
    }
}

private extension CGFloat {
    func nonZeroOrFallback(_ fallback: CGFloat) -> CGFloat {
        self > 0.0 ? self : fallback
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
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
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
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                SharedChromeBackground(orientation: orientationObserver.orientation)

                if step == .intro {
                    introPage(isLandscape: isLandscape, size: proxy.size)
                        .transition(.identity)
                } else {
                    audioTipsPage(isLandscape: isLandscape, size: proxy.size)
                        .transition(.identity)
                }
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

    @ViewBuilder
    private func introPage(isLandscape: Bool, size: CGSize) -> some View {
        let horizontalPadding = isLandscape ? 62.0 : 24.0
        let bottomPadding = isLandscape ? 24.0 : 62.0
        let logoSize = isLandscape ? 144.0 : 160.0
        let logoCenterY = isLandscape ? size.height * 0.25 : size.height / 3.0
        let introCopyTopOffset = (logoSize / 2.0) + 18.0
        let textWidth = max(160.0, size.width - (horizontalPadding * 2.0))

        if isLandscape {
            ZStack {
                centeredWelcomeStack(
                    iconCenterY: logoCenterY,
                    iconVisualHeight: logoSize,
                    contentTopOffset: introCopyTopOffset
                ) {
                    logoBlock(size: logoSize)
                        .opacity(showLogo ? 1.0 : 0.0)
                        .offset(y: showLogo ? 0.0 : 14.0)
                } content: {
                    introCopyBlock(maxWidth: textWidth)
                        .padding(.horizontal, horizontalPadding)
                }

                welcomeActionButton(
                    titleKey: "welcome.cta",
                    width: landscapeWelcomeButtonWidth(for: size),
                    action: advanceToAudioTips
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, bottomPadding)
                .opacity(showButton ? 1.0 : 0.0)
                .offset(y: showButton ? 0.0 : 14.0)
            }
            .padding(.horizontal, horizontalPadding)
        } else {
            ZStack {
                centeredWelcomeStack(
                    iconCenterY: logoCenterY,
                    iconVisualHeight: logoSize,
                    contentTopOffset: introCopyTopOffset
                ) {
                    logoBlock(size: logoSize)
                        .opacity(showLogo ? 1.0 : 0.0)
                        .offset(y: showLogo ? 0.0 : 14.0)
                } content: {
                    introCopyBlock(maxWidth: textWidth)
                        .padding(.horizontal, horizontalPadding)
                }

                welcomeActionButton(titleKey: "welcome.cta", action: advanceToAudioTips)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, bottomPadding)
                    .opacity(showButton ? 1.0 : 0.0)
                    .offset(y: showButton ? 0.0 : 14.0)
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private func audioTipsPage(isLandscape: Bool, size: CGSize) -> some View {
        let horizontalPadding = isLandscape ? 62.0 : 24.0
        let bottomPadding = isLandscape ? 24.0 : 62.0
        let topQuarterCenterY = size.height * 0.25
        let upperThirdCenterY = size.height / 3.0
        let middleCenterY = size.height * 0.5
        let tipCopyTopOffset = 67.0

        if isLandscape {
            ZStack {
                centeredWelcomeStack(
                    centerX: size.width / 3.0,
                    screenWidth: size.width,
                    iconCenterY: upperThirdCenterY,
                    iconVisualHeight: 98.0,
                    contentTopOffset: tipCopyTopOffset
                ) {
                    headphonesTipIcon()
                } content: {
                    welcomeTipText("welcome.audio_tip.headphones")
                }

                centeredWelcomeStack(
                    centerX: size.width * (2.0 / 3.0),
                    screenWidth: size.width,
                    iconCenterY: upperThirdCenterY,
                    iconVisualHeight: 86.0,
                    contentTopOffset: tipCopyTopOffset
                ) {
                    transparencyTipIcon()
                } content: {
                    welcomeTipText("welcome.audio_tip.transparency")
                }

                welcomeActionButton(
                    titleKey: "welcome.cta.experience",
                    width: landscapeWelcomeButtonWidth(for: size),
                    action: enterApp
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
            }
            .opacity(showSecondPage ? 1.0 : 0.0)
            .offset(y: showSecondPage ? 0.0 : 14.0)
        } else {
            ZStack {
                centeredWelcomeStack(
                    iconCenterY: topQuarterCenterY,
                    iconVisualHeight: 98.0,
                    contentTopOffset: tipCopyTopOffset
                ) {
                    headphonesTipIcon()
                } content: {
                    welcomeTipText("welcome.audio_tip.headphones")
                        .padding(.horizontal, 24.0)
                }

                centeredWelcomeStack(
                    iconCenterY: middleCenterY,
                    iconVisualHeight: 86.0,
                    contentTopOffset: tipCopyTopOffset
                ) {
                    transparencyTipIcon()
                } content: {
                    welcomeTipText("welcome.audio_tip.transparency")
                        .padding(.horizontal, 24.0)
                }

                welcomeActionButton(titleKey: "welcome.cta.experience", action: enterApp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, bottomPadding)
            }
            .padding(.horizontal, horizontalPadding)
            .opacity(showSecondPage ? 1.0 : 0.0)
            .offset(y: showSecondPage ? 0.0 : 14.0)
        }
    }

    private func centeredWelcomeStack<Icon: View, Content: View>(
        centerX: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        iconCenterY: CGFloat,
        iconVisualHeight: CGFloat,
        contentTopOffset: CGFloat,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            icon()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: iconCenterY - (iconVisualHeight / 2.0))

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: iconCenterY + contentTopOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: horizontalOffset(centerX: centerX, screenWidth: screenWidth))
    }

    private func introCopyBlock(maxWidth: CGFloat) -> some View {
        VStack(spacing: 14.0) {
            Text("welcome.headline")
                .font(.system(size: 34.0, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .opacity(showLineOne ? 1.0 : 0.0)
                .offset(y: showLineOne ? 0.0 : 14.0)

            Text("welcome.supporting_copy")
                .font(.system(size: 17.0, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                .opacity(showLineTwo ? 1.0 : 0.0)
                .offset(y: showLineTwo ? 0.0 : 14.0)
        }
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
    }

    private func welcomeTipText(_ textKey: LocalizedStringKey) -> some View {
        Text(textKey)
            .font(.system(size: 18.0, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.78))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func horizontalOffset(centerX: CGFloat?, screenWidth: CGFloat?) -> CGFloat {
        guard let centerX, let screenWidth else {
            return 0.0
        }

        return centerX - (screenWidth / 2.0)
    }

    private func headphonesTipIcon() -> some View {
        Image("HeadphonesIcon")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .opacity(0.75)
            .frame(width: 126.0, height: 98.0)
    }

    private func transparencyTipIcon() -> some View {
        Image("TransparencyModeIcon")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: 74.25, height: 85.8)
            .opacity(0.75)
            .frame(width: 110.0, height: 86.0)
    }

    private func landscapeWelcomeButtonWidth(for size: CGSize) -> CGFloat {
        min(size.width - 124.0, 360.0)
    }

    private func welcomeActionButton(
        titleKey: LocalizedStringKey,
        width: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        ReliableGlassButton(
            action: action,
            shape: .rounded(29.0),
            tintOpacity: 0.36
        ) {
            Text(titleKey)
                .font(.system(size: 18.0, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58.0)
        }
        .disabled(isTransitioning)
        .frame(width: width)
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

    private func logoBlock(size: CGFloat) -> some View {
        MotionComfortLogoImage(
            size: size
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
    var orientation: InterfaceRenderOrientation = .portrait
    var isActive = true

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    chrome(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                chrome(time: 0.0)
            }
        }
        .allowsHitTesting(false)
    }

    private func chrome(time: TimeInterval) -> some View {
        GeometryReader { proxy in
            let shortSide = min(proxy.size.width, proxy.size.height)
            let longSide = max(proxy.size.width, proxy.size.height)

            ZStack {
                Color(red: 0.012, green: 0.012, blue: 0.020)
                    .ignoresSafeArea()

                ZStack {
                    blob(
                        color: Color(red: 0.00, green: 0.94, blue: 0.84).opacity(0.22),
                        size: shortSide * 0.82,
                        blur: shortSide * 0.16,
                        x: (-shortSide * 0.17) + (sin(time * 1.0 + 0.8) * shortSide * 0.11),
                        y: (-longSide * 0.10) + (cos(time * 1.0 + 1.9) * longSide * 0.09)
                    )

                    blob(
                        color: Color(red: 0.10, green: 0.42, blue: 1.00).opacity(0.22),
                        size: shortSide * 0.86,
                        blur: shortSide * 0.17,
                        x: (shortSide * 0.22) + (cos(time * 1.0 + 2.4) * shortSide * 0.11),
                        y: (longSide * 0.00) + (sin(time * 1.0 + 0.5) * longSide * 0.09)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.18, blue: 0.24).opacity(0.18),
                        size: shortSide * 0.72,
                        blur: shortSide * 0.15,
                        x: (-shortSide * 0.03) + (sin(time * 1.0 + 1.4) * shortSide * 0.10),
                        y: (longSide * 0.18) + (cos(time * 1.0 + 2.7) * longSide * 0.09)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.98, blue: 0.94).opacity(0.12),
                        size: shortSide * 0.60,
                        blur: shortSide * 0.13,
                        x: (shortSide * 0.08) + (cos(time * 1.0 + 3.1) * shortSide * 0.09),
                        y: (-longSide * 0.18) + (sin(time * 1.0 + 2.2) * longSide * 0.07)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.84, blue: 0.18).opacity(0.17),
                        size: shortSide * 0.64,
                        blur: shortSide * 0.13,
                        x: (shortSide * 0.06) + (sin(time * 1.0 + 0.2) * shortSide * 0.09),
                        y: (longSide * 0.30) + (cos(time * 1.0 + 1.1) * longSide * 0.08)
                    )

                    blob(
                        color: Color(red: 0.34, green: 1.00, blue: 0.40).opacity(0.12),
                        size: shortSide * 0.52,
                        blur: shortSide * 0.12,
                        x: (-shortSide * 0.24) + (cos(time * 1.0 + 1.7) * shortSide * 0.08),
                        y: (longSide * 0.20) + (sin(time * 1.0 + 3.0) * longSide * 0.09)
                    )
                }
                .frame(width: shortSide, height: longSide)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                .rotationEffect(counterRotationAngle)

                Rectangle()
                    .fill(Color.black.opacity(0.30))
                    .ignoresSafeArea()
            }
        }
    }

    private var counterRotationAngle: Angle {
        switch orientation {
        case .portrait:
            return .zero
        case .landscapeLeft:
            return .degrees(90.0)
        case .landscapeRight:
            return .degrees(-90.0)
        }
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
