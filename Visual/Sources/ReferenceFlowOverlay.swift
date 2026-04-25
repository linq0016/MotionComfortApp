import MotionComfortCore
import SwiftUI

// Minimal 当前的主视觉实现：黑底、白点、连续光流。
public struct MinimalFlowOverlay: View {
    public var sample: MotionSample
    public var orientation: InterfaceRenderOrientation
    public var motionSensitivityFactor: Double

    @State private var phase = FlowGridPhase()

    public init(
        sample: MotionSample,
        orientation: InterfaceRenderOrientation = .portrait,
        motionSensitivityFactor: Double = 1.0
    ) {
        self.sample = sample
        self.orientation = orientation
        self.motionSensitivityFactor = motionSensitivityFactor
    }

    public var body: some View {
        FlowGridOverlay(
            sample: sample,
            configuration: .minimal,
            phase: $phase,
            orientation: orientation,
            motionSensitivityFactor: motionSensitivityFactor
        )
    }
}

// 真正把点阵画到屏幕上的渲染层。
private struct FlowGridOverlay: View {
    var sample: MotionSample
    var configuration: FlowGridConfiguration
    @Binding var phase: FlowGridPhase
    var orientation: InterfaceRenderOrientation
    var motionSensitivityFactor: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let timestamp = timeline.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let orientedSample = sample.rotatedForDisplay(orientation)
                let layout = FlowGridLayoutCache.shared.layout(
                    size: size,
                    configuration: configuration,
                    orientation: orientation
                )

                Canvas(opaque: true, rendersAsynchronously: true) { context, canvasSize in
                    context.fill(
                        Path(CGRect(origin: .zero, size: canvasSize)),
                        with: .color(configuration.layout.backgroundColor)
                    )

                    let renderState = phase.renderState
                    let normA = min(renderState.smoothedMagnitude / configuration.motion.maxAccelThreshold, 1.0)
                    let wrappedOffsetX = flowWrappedOffset(renderState.offset.x, spacing: configuration.layout.dotSpacing)
                    let wrappedOffsetY = flowWrappedOffset(renderState.offset.y, spacing: configuration.layout.dotSpacing)
                    let cellOffsetX = flowIntegralCellOffset(renderState.offset.x, spacing: configuration.layout.dotSpacing)
                    let cellOffsetY = flowIntegralCellOffset(renderState.offset.y, spacing: configuration.layout.dotSpacing)

                    for staticPoint in layout.points {
                        let point = CGPoint(
                            x: staticPoint.basePosition.x + wrappedOffsetX,
                            y: staticPoint.basePosition.y + wrappedOffsetY
                        )
                        if layout.safeRect.contains(point) {
                            continue
                        }

                        let hash = flowPseudoRandom(
                            gridX: staticPoint.gridX - cellOffsetX,
                            gridY: staticPoint.gridY - cellOffsetY
                        )
                        let edgeWeight = flowEdgeDistanceWeight(
                            point: point,
                            canvasSize: canvasSize,
                            safeRect: layout.safeRect
                        )

                        guard var appearance = flowDotAppearance(
                            hash: hash,
                            normA: normA,
                            configuration: configuration
                        ) else {
                            continue
                        }

                        appearance.radius += pow(edgeWeight, configuration.appearance.edgeRadiusCurve) * configuration.appearance.edgeRadiusBoost

                        guard appearance.alpha > configuration.appearance.minimumVisibleAlpha else {
                            continue
                        }

                        let rect = CGRect(
                            x: point.x - appearance.radius,
                            y: point.y - appearance.radius,
                            width: appearance.radius * 2.0,
                            height: appearance.radius * 2.0
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(appearance.alpha))
                        )
                    }
                }
                .onAppear {
                    phase.reset(at: timestamp)
                }
                .onChange(of: timeline.date) { _, date in
                    phase.advance(
                        sample: orientedSample,
                        timestamp: date.timeIntervalSinceReferenceDate,
                        configuration: configuration,
                        motionSensitivityFactor: motionSensitivityFactor
                    )
                }
                .onChange(of: orientation) { _, _ in
                    phase.reset(at: timestamp)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
