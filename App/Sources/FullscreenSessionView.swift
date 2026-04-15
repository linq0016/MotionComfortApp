import MotionComfortVisual
import SwiftUI

// 全屏会话页：真正承载运行中的视觉引导效果。
struct FullscreenSessionView: View {
    @ObservedObject var model: ComfortSessionViewModel
    var onClose: () -> Void

    var body: some View {
        ZStack {
            sessionBackground

            if model.visualGuideStyle == .liveView || !model.visualGuideStyle.isImplemented || model.visualGuidesEnabled {
                PeripheralCueOverlay(
                    cueState: model.cueState,
                    sample: model.sample,
                    visualStyle: model.visualGuideStyle
                )
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 18.0)
            .padding(.top, 12.0)
            .padding(.bottom, 18.0)
        }
        .overlay(alignment: .bottomTrailing) {
            LiveMotionDebugOverlay(model: model)
                .padding(.trailing, 16.0)
                .padding(.bottom, 18.0)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
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
}
