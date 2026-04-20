import MotionComfortVisual
import MotionComfortAudio
import SwiftUI

// 全屏会话页：真正承载运行中的视觉引导效果。
struct FullscreenSessionView: View {
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    var onClose: () -> Void

    @State private var areHUDControlsVisible = true
    @State private var hideHUDTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            sessionBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleHUDVisibility()
                }

            PeripheralCueOverlay(
                sample: model.sample,
                visualStyle: model.visualGuideStyle,
                orientation: orientationObserver.orientation,
                dynamicSpeedMultiplier: model.dynamicSpeedMultiplier
            )
                .ignoresSafeArea()

            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 18.0)
            .padding(.top, 12.0)
            .opacity(areHUDControlsVisible ? 1.0 : 0.0)
            .allowsHitTesting(areHUDControlsVisible)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0.0)
                    .onChanged { _ in
                        registerFullscreenInteraction()
                    }
            )

            GeometryReader { proxy in
                fullscreenAudioModeControl
                    .position(
                        x: proxy.size.width * 0.5,
                        y: proxy.size.height * 0.25
                    )
            }
            .ignoresSafeArea()
            .opacity(areHUDControlsVisible ? 1.0 : 0.0)
            .allowsHitTesting(areHUDControlsVisible)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0.0)
                    .onChanged { _ in
                        registerFullscreenInteraction()
                    }
            )

            if model.visualGuideStyle == .dynamic {
                GeometryReader { proxy in
                    dynamicSpeedControl
                        .position(
                            x: proxy.size.width * 0.5,
                            y: proxy.size.height * 0.75
                        )
                }
                .ignoresSafeArea()
                .opacity(areHUDControlsVisible ? 1.0 : 0.0)
                .allowsHitTesting(areHUDControlsVisible)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0.0)
                        .onChanged { _ in
                            registerFullscreenInteraction()
                        }
                )
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.24), value: areHUDControlsVisible)
        .onAppear {
            model.startAudioIfNeeded()
            scheduleHUDHide()
        }
        .onDisappear {
            hideHUDTask?.cancel()
        }
    }

    private var sessionBackground: some View {
        Group {
            switch model.visualGuideStyle {
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

    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 16.0, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.92))
            .frame(width: 42.0, height: 42.0)
            .contentShape(Circle())
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .circle
            )
            .onTapGesture {
                onClose()
            }
    }

    private var fullscreenAudioModeControl: some View {
        AudioModeGlassControl(selection: $model.audioMode)
    }

    private var dynamicSpeedControl: some View {
        GlassEffectContainer(spacing: 10.0) {
            ZStack {
                Slider(value: dynamicSpeedSliderPosition, in: 0.0...1.0)
                    .tint(Color(red: 0.25, green: 0.72, blue: 1.0))
                    .frame(width: dynamicSpeedSliderWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8.0)

                Text("fullscreen.cruise_speed")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6.0)
            }
            .padding(.horizontal, 12.0)
            .padding(.vertical, 4.0)
            .frame(height: 76.0)
            .frame(width: 280.0)
            .glassEffect(
                .clear.tint(Color.black.opacity(0.36)).interactive(),
                in: .rect(cornerRadius: 26.0)
            )
        }
    }

    private var dynamicSpeedSliderWidth: CGFloat { 240.0 }

    private var dynamicSpeedSliderPosition: Binding<Double> {
        Binding(
            get: {
                sliderPosition(for: model.dynamicSpeedMultiplier)
            },
            set: { sliderPosition in
                model.dynamicSpeedMultiplier = speedMultiplier(for: sliderPosition)
            }
        )
    }

    private func sliderPosition(for speedMultiplier: Double) -> Double {
        let clampedSpeed = min(max(speedMultiplier, 0.0), 6.0)
        return clampedSpeed / 6.0
    }

    private func speedMultiplier(for sliderPosition: Double) -> Double {
        let clampedPosition = min(max(sliderPosition, 0.0), 1.0)
        return clampedPosition * 6.0
    }

    private func registerFullscreenInteraction() {
        if !areHUDControlsVisible {
            withAnimation(.easeInOut(duration: 0.24)) {
                areHUDControlsVisible = true
            }
        }
        scheduleHUDHide()
    }

    private func toggleHUDVisibility() {
        hideHUDTask?.cancel()

        withAnimation(.easeInOut(duration: 0.24)) {
            areHUDControlsVisible.toggle()
        }

        if areHUDControlsVisible {
            scheduleHUDHide()
        }
    }

    private func scheduleHUDHide() {
        hideHUDTask?.cancel()
        hideHUDTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.24)) {
                    areHUDControlsVisible = false
                }
            }
        }
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

    init(selection: Binding<AudioMode>, controlWidth: CGFloat? = 276.0, controlHeight: CGFloat = 52.0) {
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
