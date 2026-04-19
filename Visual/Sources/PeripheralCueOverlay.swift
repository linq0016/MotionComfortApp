import MotionComfortCore
import SwiftUI

// 视觉模式分发层：根据当前样式切到对应的渲染器。
public struct PeripheralCueOverlay: View {
    public var sample: MotionSample
    public var visualStyle: VisualGuideStyle
    public var orientation: InterfaceRenderOrientation
    public var dynamicSpeedMultiplier: Double

    public init(
        sample: MotionSample = .neutral,
        visualStyle: VisualGuideStyle = .minimal,
        orientation: InterfaceRenderOrientation = .portrait,
        dynamicSpeedMultiplier: Double = 1.0
    ) {
        self.sample = sample
        self.visualStyle = visualStyle
        self.orientation = orientation
        self.dynamicSpeedMultiplier = dynamicSpeedMultiplier
    }

    public var body: some View {
        Group {
            switch visualStyle {
            case .minimal:
                MinimalFlowOverlay(sample: sample, orientation: orientation)
            case .dynamic:
                DynamicFlowOverlay(
                    sample: sample,
                    orientation: orientation,
                    speedMultiplier: dynamicSpeedMultiplier
                )
            case .liveView:
                LiveViewOverlay(sample: sample, style: visualStyle, orientation: orientation)
            }
        }
        .allowsHitTesting(false)
    }
}
