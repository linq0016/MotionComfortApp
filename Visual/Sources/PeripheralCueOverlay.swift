import MotionComfortCore
import SwiftUI

// 视觉模式分发层：根据当前样式切到对应的渲染器。
public struct PeripheralCueOverlay: View {
    public var cueState: CueState
    public var sample: MotionSample
    public var visualStyle: VisualGuideStyle
    public var orientation: InterfaceRenderOrientation

    public init(
        cueState: CueState,
        sample: MotionSample = .neutral,
        visualStyle: VisualGuideStyle = .minimal,
        orientation: InterfaceRenderOrientation = .portrait
    ) {
        self.cueState = cueState
        self.sample = sample
        self.visualStyle = visualStyle
        self.orientation = orientation
    }

    public var body: some View {
        Group {
            switch visualStyle {
            case .minimal:
                MinimalFlowOverlay(sample: sample, orientation: orientation)
            case .dynamic:
                DynamicFlowOverlay(style: visualStyle)
            case .liveView:
                LiveViewOverlay(sample: sample, style: visualStyle, orientation: orientation)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct VisualPlaceholderCard: View {
    let style: VisualGuideStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            HStack {
                Text(style.title)
                    .font(.system(size: 26.0, weight: .bold, design: .rounded))

                Spacer(minLength: 0.0)

                Text(style.statusTitle.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .padding(.horizontal, 10.0)
                    .padding(.vertical, 6.0)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }

            Text(style.placeholderTitle)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))

            Text(style.placeholderNote)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420.0, alignment: .leading)
        .padding(24.0)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 30.0, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30.0, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
        )
        .padding(.horizontal, 24.0)
    }
}

public struct DynamicFlowOverlay: View {
    let style: VisualGuideStyle

    public init(style: VisualGuideStyle = .dynamic) {
        self.style = style
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.07, green: 0.09, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VisualPlaceholderCard(style: style)
        }
        .ignoresSafeArea()
    }
}
