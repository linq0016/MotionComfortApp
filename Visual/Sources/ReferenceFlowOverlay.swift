import MotionComfortCore
import SwiftUI

// Minimal 当前的主视觉实现：黑底、白点、连续光流。
public struct MinimalFlowOverlay: View {
    public var sample: MotionSample
    public var orientation: InterfaceRenderOrientation

    @State private var phase = FlowGridPhase()

    public init(sample: MotionSample, orientation: InterfaceRenderOrientation = .portrait) {
        self.sample = sample
        self.orientation = orientation
    }

    public var body: some View {
        FlowGridOverlay(
            sample: sample,
            configuration: .minimal,
            phase: $phase,
            orientation: orientation
        )
    }
}

// 真正把点阵画到屏幕上的渲染层。
private struct FlowGridOverlay: View {
    var sample: MotionSample
    var configuration: FlowGridConfiguration
    @Binding var phase: FlowGridPhase
    var orientation: InterfaceRenderOrientation

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let timestamp = timeline.date.timeIntervalSinceReferenceDate
                let size = proxy.size
                let coreSafeRect = makeSafeRect(in: size, marginRatio: configuration.marginRatio)
                let orientedSample = sample.rotatedForDisplay(orientation)

                Canvas(opaque: true, rendersAsynchronously: true) { context, canvasSize in
                    context.fill(
                        Path(CGRect(origin: .zero, size: canvasSize)),
                        with: .color(configuration.backgroundColor)
                    )

                    let renderState = phase.renderState
                    let startX = flowWrappedOffset(renderState.offset.x, spacing: configuration.dotSpacing) - configuration.dotSpacing
                    let startY = flowWrappedOffset(renderState.offset.y, spacing: configuration.dotSpacing) - configuration.dotSpacing
                    let normA = min(renderState.smoothedMagnitude / configuration.maxAccelThreshold, 1.0)

                    for x in stride(from: startX, through: canvasSize.width + configuration.dotSpacing, by: configuration.dotSpacing) {
                        for y in stride(from: startY, through: canvasSize.height + configuration.dotSpacing, by: configuration.dotSpacing) {
                            let point = CGPoint(x: x, y: y)
                            if coreSafeRect.contains(point) {
                                continue
                            }

                            let gridX = Int(round((x - renderState.offset.x) / configuration.dotSpacing))
                            let gridY = Int(round((y - renderState.offset.y) / configuration.dotSpacing))
                            let hash = flowPseudoRandom(gridX: gridX, gridY: gridY)
                            let edgeWeight = edgeDistanceWeight(
                                point: point,
                                canvasSize: canvasSize,
                                safeRect: coreSafeRect
                            )

                            guard var appearance = flowDotAppearance(
                                hash: hash,
                                normA: normA,
                                configuration: configuration
                            ) else {
                                continue
                            }

                            appearance.radius += pow(edgeWeight, configuration.edgeRadiusCurve) * configuration.edgeRadiusBoost

                            guard appearance.alpha > configuration.minimumVisibleAlpha else {
                                continue
                            }

                            let rect = CGRect(
                                x: x - appearance.radius,
                                y: y - appearance.radius,
                                width: appearance.radius * 2.0,
                                height: appearance.radius * 2.0
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(.white.opacity(appearance.alpha))
                            )
                        }
                    }
                }
                .onAppear {
                    phase.reset(at: timestamp)
                }
                .onChange(of: timeline.date) { _, date in
                    phase.advance(
                        sample: orientedSample,
                        timestamp: date.timeIntervalSinceReferenceDate,
                        configuration: configuration
                    )
                }
                .onChange(of: orientation) { _, _ in
                    phase.reset(at: timestamp)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func makeSafeRect(in size: CGSize, marginRatio: CGFloat) -> CGRect {
        CGRect(
            x: size.width * marginRatio,
            y: size.height * marginRatio,
            width: size.width * (1.0 - (marginRatio * 2.0)),
            height: size.height * (1.0 - (marginRatio * 2.0))
        )
    }

    private func edgeDistanceWeight(point: CGPoint, canvasSize: CGSize, safeRect: CGRect) -> CGFloat {
        let safeDistanceX = max(safeRect.minX - point.x, 0.0, point.x - safeRect.maxX)
        let safeDistanceY = max(safeRect.minY - point.y, 0.0, point.y - safeRect.maxY)
        let distanceFromSafeZone = sqrt((safeDistanceX * safeDistanceX) + (safeDistanceY * safeDistanceY))

        let cornerDistances = [
            hypot(safeRect.minX, safeRect.minY),
            hypot(canvasSize.width - safeRect.maxX, safeRect.minY),
            hypot(safeRect.minX, canvasSize.height - safeRect.maxY),
            hypot(canvasSize.width - safeRect.maxX, canvasSize.height - safeRect.maxY)
        ]
        let maxDistance = max(cornerDistances.max() ?? 1.0, 1.0)
        let normalized = min(max(distanceFromSafeZone / maxDistance, 0.0), 1.0)
        return normalized
    }
}
