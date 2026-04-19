import MotionComfortVisual
import SwiftUI

// 全屏会话页：真正承载运行中的视觉引导效果。
struct FullscreenSessionView: View {
    @ObservedObject var model: ComfortSessionViewModel
    @ObservedObject var orientationObserver: InterfaceOrientationObserver
    var onClose: () -> Void

    var body: some View {
        ZStack {
            sessionBackground

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

            if model.visualGuideStyle == .dynamic {
                GeometryReader { proxy in
                    dynamicSpeedControl
                        .position(
                            x: proxy.size.width * 0.5,
                            y: proxy.size.height * 0.75
                        )
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            model.startAudioIfNeeded()
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
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16.0, weight: .bold))
                .frame(width: 42.0, height: 42.0)
                .background(
                    Color(red: 0.10, green: 0.12, blue: 0.17).opacity(0.92),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .allowsHitTesting(false)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                        .allowsHitTesting(false)
                )
        }
        .buttonStyle(.plain)
    }

    private var dynamicSpeedControl: some View {
        GlassEffectContainer(spacing: 10.0) {
            ZStack {
                Slider(value: dynamicSpeedSliderPosition, in: 0.0...1.0)
                    .tint(Color(red: 0.25, green: 0.72, blue: 1.0))
                    .frame(width: dynamicSpeedSliderWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8.0)

                Text("Cruise Speed")
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
                .clear.tint(Color.black.opacity(0.24)).interactive(),
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
}
