import MotionComfortVisual
import MotionComfortAudio
import MotionComfortCore
import Foundation
import SwiftUI
import UIKit

private enum FullscreenTiming {
    static let hudAutoHideDelay: TimeInterval = 5.0
    static let hudRefreshThrottle: TimeInterval = 0.25
    static let hudAnimationDuration: TimeInterval = 0.24
    static let liveViewGuidanceToastDuration: Duration = .seconds(4.0)
}

// 全屏会话页：真正承载运行中的视觉引导效果。
struct FullscreenSessionView: View {
    @ObservedObject var model: ComfortSessionViewModel
    let renderState: SessionRenderState
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    var onMotionControlEditingEnded: () -> Void = {}
    var onClose: () -> Void

    @AppStorage("hasShownLiveViewGuidanceToast") private var hasShownLiveViewGuidanceToast = false
    @State private var areHUDControlsVisible = true
    @State private var hideHUDTask: Task<Void, Never>?
    @State private var hideHUDDeadline: Date?
    @State private var lastHUDRefreshAt: Date?
    @State private var isLiveViewGuidanceToastVisible = false
    @State private var liveViewGuidanceToastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            SessionBackground(visualStyle: model.visualGuideStyle)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleHUDVisibility()
                }

            SessionCueOverlay(
                renderState: renderState,
                visualStyle: model.visualGuideStyle,
                orientation: orientationObserver.orientation,
                dynamicSpeedMultiplier: model.dynamicSpeedMultiplier,
                motionSensitivityFactor: model.motionSensitivityFactor,
                liveViewCamera: model.liveViewCamera
            )
                .ignoresSafeArea()

            SessionHUDLayer(
                isVisible: areHUDControlsVisible,
                orientation: orientationObserver.orientation,
                onClose: onClose,
                onInteraction: {
                    registerFullscreenInteraction()
                }
            )

            SessionAudioControlLayer(
                isVisible: areHUDControlsVisible,
                orientation: orientationObserver.orientation,
                selection: $model.audioMode,
                onInteraction: {
                    registerFullscreenInteraction()
                }
            )

            MotionControlsLayer(
                isVisible: areHUDControlsVisible,
                visualStyle: model.visualGuideStyle,
                orientation: orientationObserver.orientation,
                motionSensitivityFactor: $model.motionSensitivityFactor,
                speedMultiplier: $model.dynamicSpeedMultiplier,
                onEditingBegan: beginMotionControlEditing,
                onInteraction: {
                    registerFullscreenInteraction()
                },
                onEditingEnded: finishMotionControlEditing
            )

            if isLiveViewGuidanceToastVisible {
                liveViewGuidanceToast
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(2.0)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .animation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration), value: areHUDControlsVisible)
        .animation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration), value: isLiveViewGuidanceToastVisible)
        .onAppear {
            model.startAudioIfNeeded()
            scheduleHUDHide()
            scheduleLiveViewGuidanceToastIfNeeded()
        }
        .onDisappear {
            cancelHUDHide()
            liveViewGuidanceToastTask?.cancel()
            isLiveViewGuidanceToastVisible = false
        }
        .onChange(of: model.visualGuideStyle) { _, _ in
            scheduleLiveViewGuidanceToastIfNeeded()
        }
        .onChange(of: orientationObserver.orientation) { _, newOrientation in
            guard isLiveViewGuidanceToastVisible else { return }
            guard newOrientation == .landscapeLeft || newOrientation == .landscapeRight else {
                return
            }

            liveViewGuidanceToastTask?.cancel()
            liveViewGuidanceToastTask = nil
            withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
                isLiveViewGuidanceToastVisible = false
            }
        }
    }

    private var liveViewGuidanceToast: some View {
        GlassEffectContainer(spacing: 0.0) {
            VStack(spacing: 8.0) {
                Image("LiveViewGuidanceIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 110.0, height: 60.0)
                    .opacity(0.75)

                Text("liveview.tip.first_entry")
                    .font(.system(size: 15.0, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12.0)
            .frame(width: 200.0, height: 150.0, alignment: .center)
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)),
                in: .rect(cornerRadius: 26.0)
            )
        }
    }

    private func registerFullscreenInteraction(forceHUDRefresh: Bool = false) {
        if !areHUDControlsVisible {
            withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
                areHUDControlsVisible = true
            }

            scheduleHUDHide(force: true)
            return
        }

        scheduleHUDHide(force: forceHUDRefresh)
    }

    private func finishMotionControlEditing() {
        registerFullscreenInteraction(forceHUDRefresh: true)
        onMotionControlEditingEnded()
    }

    private func beginMotionControlEditing() {
        if !areHUDControlsVisible {
            withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
                areHUDControlsVisible = true
            }
        }

        cancelHUDHide()
    }

    private func toggleHUDVisibility() {
        cancelHUDHide()

        withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
            areHUDControlsVisible.toggle()
        }

        if areHUDControlsVisible {
            scheduleHUDHide(force: true)
        }
    }

    private func scheduleHUDHide(force: Bool = false) {
        let now = Date()
        if !force,
           let lastHUDRefreshAt,
           now.timeIntervalSince(lastHUDRefreshAt) < FullscreenTiming.hudRefreshThrottle {
            return
        }

        lastHUDRefreshAt = now
        hideHUDDeadline = now.addingTimeInterval(FullscreenTiming.hudAutoHideDelay)
        guard hideHUDTask == nil else {
            return
        }

        hideHUDTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let deadline = hideHUDDeadline else {
                    hideHUDTask = nil
                    return
                }

                let remainingSeconds = deadline.timeIntervalSinceNow
                if remainingSeconds > 0.0 {
                    try? await Task.sleep(for: .milliseconds(Int(ceil(remainingSeconds * 1000.0))))
                    continue
                }

                withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
                    areHUDControlsVisible = false
                }
                hideHUDDeadline = nil
                hideHUDTask = nil
                return
            }
        }
    }

    private func cancelHUDHide() {
        lastHUDRefreshAt = nil
        hideHUDDeadline = nil
        hideHUDTask?.cancel()
        hideHUDTask = nil
    }

    private func scheduleLiveViewGuidanceToastIfNeeded() {
        liveViewGuidanceToastTask?.cancel()

        guard model.visualGuideStyle == .liveView, !hasShownLiveViewGuidanceToast else {
            isLiveViewGuidanceToastVisible = false
            return
        }

        hasShownLiveViewGuidanceToast = true
        isLiveViewGuidanceToastVisible = true

        liveViewGuidanceToastTask = Task {
            try? await Task.sleep(for: FullscreenTiming.liveViewGuidanceToastDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: FullscreenTiming.hudAnimationDuration)) {
                    isLiveViewGuidanceToastVisible = false
                }
                liveViewGuidanceToastTask = nil
            }
        }
    }
}

private struct SessionBackground: View {
    let visualStyle: VisualGuideStyle

    var body: some View {
        Group {
            switch visualStyle {
            case .minimal:
                Color.black
            case .dynamic:
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.07, blue: 0.10),
                        Color(red: 0.09, green: 0.11, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .liveView:
                Color(red: 0.05, green: 0.06, blue: 0.08)
            }
        }
        .ignoresSafeArea()
    }
}

private struct SessionHUDLayer: View {
    let isVisible: Bool
    let orientation: InterfaceRenderOrientation
    let onClose: () -> Void
    let onInteraction: () -> Void

    private let edgePadding: CGFloat = 18.0
    private let closeButtonSize: CGFloat = 42.0

    var body: some View {
        GeometryReader { proxy in
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, edgePadding)
            .padding(.top, closeButtonTopPadding(for: proxy.size))
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .allowsHitTesting(isVisible)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0.0)
                .onChanged { _ in
                    onInteraction()
                }
        )
    }

    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 16.0, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.92))
            .frame(width: closeButtonSize, height: closeButtonSize)
            .contentShape(Circle())
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .circle
            )
            .onTapGesture {
                onClose()
            }
    }

    private func closeButtonTopPadding(for size: CGSize) -> CGFloat {
        switch orientation {
        case .portrait:
            return edgePadding
        case .landscapeLeft, .landscapeRight:
            return max(edgePadding, (size.height * 0.20) - (closeButtonSize * 0.5))
        }
    }
}

private struct SessionAudioControlLayer: View {
    let isVisible: Bool
    let orientation: InterfaceRenderOrientation
    @Binding var selection: AudioMode
    let onInteraction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            AudioModeGlassControl(selection: $selection)
                .position(
                    x: proxy.size.width * 0.5,
                    y: proxy.size.height * audioControlVerticalPositionRatio
                )
        }
        .ignoresSafeArea()
        .opacity(isVisible ? 1.0 : 0.0)
        .allowsHitTesting(isVisible)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0.0)
                .onChanged { _ in
                    onInteraction()
                }
        )
    }

    private var audioControlVerticalPositionRatio: CGFloat {
        switch orientation {
        case .portrait:
            return 0.25
        case .landscapeLeft, .landscapeRight:
            return 0.20
        }
    }
}

private struct MotionControlsLayer: View {
    let isVisible: Bool
    let visualStyle: VisualGuideStyle
    let orientation: InterfaceRenderOrientation
    @Binding var motionSensitivityFactor: Double
    @Binding var speedMultiplier: Double
    let onEditingBegan: () -> Void
    let onInteraction: () -> Void
    let onEditingEnded: () -> Void

    private let sliderWidth: CGFloat = 178.0

    var body: some View {
        GeometryReader { proxy in
            controlCard
                .position(
                    x: proxy.size.width * 0.5,
                    y: proxy.size.height * controlVerticalPositionRatio
                )
        }
        .ignoresSafeArea()
        .opacity(isVisible ? 1.0 : 0.0)
        .allowsHitTesting(isVisible)
    }

    private var controlCard: some View {
        GlassEffectContainer(spacing: 10.0) {
            if visualStyle == .dynamic {
                dualControlCard
            } else {
                singleControlCard(
                    title: String(localized: "fullscreen.motion_sensitivity"),
                    value: motionSensitivitySliderPosition
                )
            }
        }
    }

    private var dualControlCard: some View {
        VStack(spacing: 0.0) {
            Spacer(minLength: 0.0)

            controlTitle(String(localized: "fullscreen.motion_sensitivity"))

            Spacer(minLength: 0.0)

            controlSlider(
                motionSensitivitySliderPosition,
                defaultPosition: sliderPosition(forMotionSensitivityFactor: 1.0)
            )

            Spacer(minLength: 0.0)

            controlTitle(String(localized: "fullscreen.cruise_speed"))

            Spacer(minLength: 0.0)

            controlSlider(
                dynamicSpeedSliderPosition,
                defaultPosition: sliderPosition(for: 2.0)
            )

            Spacer(minLength: 0.0)
        }
        .padding(.horizontal, 4.0)
        .padding(.vertical, 4.0)
        .frame(width: 210.0, height: 128.0)
        .glassEffect(
            .clear.tint(Color.black.opacity(0.36)).interactive(),
            in: .rect(cornerRadius: 26.0)
        )
    }

    private func singleControlCard(title: String, value: Binding<Double>) -> some View {
        ZStack {
            controlSlider(
                value,
                defaultPosition: sliderPosition(forMotionSensitivityFactor: 1.0)
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 7.0)

            controlTitle(title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 5.0)
        }
        .padding(.horizontal, 4.0)
        .padding(.vertical, 4.0)
        .frame(width: 210.0, height: 70.0)
        .glassEffect(
            .clear.tint(Color.black.opacity(0.36)).interactive(),
            in: .rect(cornerRadius: 26.0)
        )
    }

    private func controlTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.86))
    }

    private func controlSlider(_ value: Binding<Double>) -> some View {
        controlSlider(value, defaultPosition: nil)
    }

    private func controlSlider(_ value: Binding<Double>, defaultPosition: Double?) -> some View {
        NativeSnapSlider(
            value: value,
            defaultPosition: defaultPosition,
            onEditingBegan: onEditingBegan,
            onInteraction: onInteraction,
            onEditingEnded: onEditingEnded
        )
            .frame(width: sliderWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var controlVerticalPositionRatio: CGFloat {
        switch orientation {
        case .portrait:
            return 0.75
        case .landscapeLeft, .landscapeRight:
            return 0.75
        }
    }

    private var motionSensitivitySliderPosition: Binding<Double> {
        Binding(
            get: {
                sliderPosition(forMotionSensitivityFactor: motionSensitivityFactor)
            },
            set: { sliderPosition in
                motionSensitivityFactor = motionSensitivityFactor(for: sliderPosition)
            }
        )
    }

    private var dynamicSpeedSliderPosition: Binding<Double> {
        Binding(
            get: {
                sliderPosition(for: speedMultiplier)
            },
            set: { sliderPosition in
                speedMultiplier = speedMultiplier(for: sliderPosition)
            }
        )
    }

    private func sliderPosition(forMotionSensitivityFactor factor: Double) -> Double {
        let clampedFactor = min(max(factor, 2.0 / 3.0), 1.5)
        return (1.5 - clampedFactor) / (5.0 / 6.0)
    }

    private func motionSensitivityFactor(for sliderPosition: Double) -> Double {
        let clampedPosition = min(max(sliderPosition, 0.0), 1.0)
        return 1.5 - (clampedPosition * (5.0 / 6.0))
    }

    private func sliderPosition(for speedMultiplier: Double) -> Double {
        let clampedSpeed = min(max(speedMultiplier, 0.0), 6.0)
        return clampedSpeed / 6.0
    }

    private func speedMultiplier(for sliderPosition: Double) -> Double {
        let clampedPosition = min(max(sliderPosition, 0.0), 1.0)
        return clampedPosition * 6.0
    }
}

@MainActor
private struct NativeSnapSlider: UIViewRepresentable {
    @Binding var value: Double
    let defaultPosition: Double?
    let onEditingBegan: () -> Void
    let onInteraction: () -> Void
    let onEditingEnded: () -> Void

    private let snapThreshold: Double = 0.03
    private let valueStep: Double = 0.02
    private let valueCommitInterval: TimeInterval = 0.20
    private let tintColor = UIColor(red: 0.25, green: 0.72, blue: 1.0, alpha: 1.0)

    func makeCoordinator() -> Coordinator {
        Coordinator(
            value: $value,
            defaultPosition: defaultPosition,
            snapThreshold: snapThreshold,
            valueStep: valueStep,
            valueCommitInterval: valueCommitInterval,
            onEditingBegan: onEditingBegan,
            onInteraction: onInteraction,
            onEditingEnded: onEditingEnded
        )
    }

    func makeUIView(context: Context) -> SnapMarkedSlider {
        let slider = SnapMarkedSlider(frame: .zero)
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.minimumTrackTintColor = tintColor
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
        slider.defaultPosition = defaultPosition.map { CGFloat($0) }
        let doubleTapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTapped(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        slider.addGestureRecognizer(doubleTapRecognizer)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchBegan(_:)), for: [.touchDown])
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        slider.setValue(Float(value), animated: false)
        return slider
    }

    func updateUIView(_ uiView: SnapMarkedSlider, context: Context) {
        uiView.defaultPosition = defaultPosition.map { CGFloat($0) }
        if !uiView.isTracking, abs(Double(uiView.value) - value) > 0.0001 {
            uiView.setValue(Float(value), animated: false)
        }
        context.coordinator.defaultPosition = defaultPosition
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var value: Double
        var defaultPosition: Double?
        let snapThreshold: Double
        let valueStep: Double
        let valueCommitInterval: TimeInterval
        let onEditingBegan: () -> Void
        let onInteraction: () -> Void
        let onEditingEnded: () -> Void
        private var feedbackGenerator: UISelectionFeedbackGenerator?
        private var isInsideSnapZone = false
        private var pendingValue: Double?
        private var valueCommitTask: Task<Void, Never>?
        private var canCommitImmediately = true

        init(
            value: Binding<Double>,
            defaultPosition: Double?,
            snapThreshold: Double,
            valueStep: Double,
            valueCommitInterval: TimeInterval,
            onEditingBegan: @escaping () -> Void,
            onInteraction: @escaping () -> Void,
            onEditingEnded: @escaping () -> Void
        ) {
            self._value = value
            self.defaultPosition = defaultPosition
            self.snapThreshold = snapThreshold
            self.valueStep = valueStep
            self.valueCommitInterval = valueCommitInterval
            self.onEditingBegan = onEditingBegan
            self.onInteraction = onInteraction
            self.onEditingEnded = onEditingEnded
        }

        deinit {
            valueCommitTask?.cancel()
        }

        private func makeFeedbackGeneratorIfNeeded() -> UISelectionFeedbackGenerator {
            if let feedbackGenerator {
                return feedbackGenerator
            }

            let generator = UISelectionFeedbackGenerator()
            feedbackGenerator = generator
            return generator
        }

        @objc
        func touchBegan(_ sender: UISlider) {
            let feedbackGenerator = makeFeedbackGeneratorIfNeeded()
            feedbackGenerator.prepare()
            pendingValue = nil
            valueCommitTask?.cancel()
            valueCommitTask = nil
            canCommitImmediately = true
            onEditingBegan()
        }

        @objc
        func valueChanged(_ sender: UISlider) {
            let rawValue = Double(sender.value)
            guard let defaultPosition else {
                let nextValue = steppedValue(for: rawValue)
                sender.setValue(Float(nextValue), animated: false)
                enqueueValue(nextValue)
                return
            }

            let shouldSnap = abs(rawValue - defaultPosition) <= snapThreshold
            let nextValue: Double
            if shouldSnap {
                sender.setValue(Float(defaultPosition), animated: false)
                nextValue = defaultPosition

                if !isInsideSnapZone {
                    let feedbackGenerator = makeFeedbackGeneratorIfNeeded()
                    feedbackGenerator.selectionChanged()
                    feedbackGenerator.prepare()
                }
            } else {
                nextValue = steppedValue(for: rawValue)
                sender.setValue(Float(nextValue), animated: false)
            }

            isInsideSnapZone = shouldSnap
            enqueueValue(nextValue)
        }

        @objc
        func touchEnded(_ sender: UISlider) {
            valueChanged(sender)
            flushValue(Double(sender.value))
            onInteraction()
            onEditingEnded()
            isInsideSnapZone = false
        }

        @objc
        func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard
                recognizer.state == .ended,
                let defaultPosition,
                let slider = recognizer.view as? UISlider
            else {
                return
            }

            onInteraction()
            slider.setValue(Float(defaultPosition), animated: true)
            flushValue(defaultPosition)
            isInsideSnapZone = false
            onEditingEnded()

            let feedbackGenerator = makeFeedbackGeneratorIfNeeded()
            feedbackGenerator.selectionChanged()
            feedbackGenerator.prepare()
        }

        private func enqueueValue(_ nextValue: Double) {
            guard abs(value - nextValue) > 0.0001 else {
                return
            }

            if canCommitImmediately {
                canCommitImmediately = false
                commitValue(nextValue)
                schedulePendingCommitIfNeeded()
                return
            }

            pendingValue = nextValue
            schedulePendingCommitIfNeeded()
        }

        private func flushValue(_ nextValue: Double) {
            valueCommitTask?.cancel()
            valueCommitTask = nil
            pendingValue = nil
            canCommitImmediately = true
            commitValue(nextValue)
        }

        private func schedulePendingCommitIfNeeded() {
            guard valueCommitTask == nil else {
                return
            }

            valueCommitTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else {
                        return
                    }

                    try? await Task.sleep(for: .milliseconds(Int(valueCommitInterval * 1000.0)))
                    guard !Task.isCancelled else {
                        return
                    }

                    guard let nextValue = self.pendingValue else {
                        self.canCommitImmediately = true
                        self.valueCommitTask = nil
                        return
                    }

                    self.pendingValue = nil
                    self.commitValue(nextValue)
                }
            }
        }

        private func commitValue(_ nextValue: Double) {
            guard abs(value - nextValue) > 0.0001 else {
                return
            }
            value = nextValue
        }

        private func steppedValue(for rawValue: Double) -> Double {
            let clampedValue = min(max(rawValue, 0.0), 1.0)
            let steppedValue = (clampedValue / valueStep).rounded() * valueStep
            return min(max(steppedValue, 0.0), 1.0)
        }
    }
}

@MainActor
private final class SnapMarkedSlider: UISlider {
    var defaultPosition: CGFloat? {
        didSet {}
    }
}

private struct SessionCueOverlay: View {
    @ObservedObject var renderState: SessionRenderState
    let visualStyle: VisualGuideStyle
    let orientation: InterfaceRenderOrientation
    let dynamicSpeedMultiplier: Double
    let motionSensitivityFactor: Double
    let liveViewCamera: LiveViewCameraModel

    var body: some View {
        PeripheralCueOverlay(
            sample: renderState.sample,
            visualStyle: visualStyle,
            orientation: orientation,
            dynamicSpeedMultiplier: dynamicSpeedMultiplier,
            motionSensitivityFactor: motionSensitivityFactor,
            liveViewCamera: liveViewCamera
        )
    }
}

struct AudioModeGlassControl: View {
    @Binding var selection: AudioMode

    private let modes = AudioMode.allCases
    private let controlWidth: CGFloat?
    private let controlHeight: CGFloat
    private let innerPadding: CGFloat = 6.0
    private var controlCornerRadius: CGFloat {
        controlHeight * 0.5
    }

    init(selection: Binding<AudioMode>, controlWidth: CGFloat? = 280.0, controlHeight: CGFloat = 52.0) {
        self._selection = selection
        self.controlWidth = controlWidth
        self.controlHeight = controlHeight
    }

    var body: some View {
        GlassEffectContainer(spacing: 12.0) {
            ZStack(alignment: .leading) {
                selectionHighlight

                HStack(spacing: 0.0) {
                    ForEach(modes) { mode in
                        Text(mode.title)
                            .font(.system(size: 17.0, weight: .medium, design: .rounded))
                            .foregroundStyle(selection == mode ? Color.white : Color.white.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .frame(height: controlHeight - (innerPadding * 2.0))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = mode
                            }
                    }
                }
            }
            .padding(innerPadding)
            .frame(maxWidth: controlWidth ?? .infinity, minHeight: controlHeight, maxHeight: controlHeight)
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .rect(cornerRadius: controlCornerRadius)
            )
        }
    }

    private var selectionHighlight: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: controlCornerRadius - innerPadding, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(
                    width: segmentWidth(for: proxy.size.width),
                    height: controlHeight - (innerPadding * 2.0)
                )
                .offset(x: selectionOffset(for: proxy.size.width))
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: selection)
        }
        .allowsHitTesting(false)
    }

    private func segmentWidth(for totalWidth: CGFloat) -> CGFloat {
        totalWidth / CGFloat(max(modes.count, 1))
    }

    private func selectionOffset(for totalWidth: CGFloat) -> CGFloat {
        segmentWidth(for: totalWidth) * CGFloat(selectedIndex)
    }

    private var selectedIndex: Int {
        modes.firstIndex(of: selection) ?? 0
    }
}
