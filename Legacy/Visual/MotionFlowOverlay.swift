import MotionComfortCore
import SwiftUI

public struct MotionFlowOverlay: View {
    public var cueState: CueState
    public var style: MotionFlowStyle

    @State private var phase = MotionFlowPhase()

    public init(cueState: CueState, style: MotionFlowStyle = .hybridDynamic) {
        self.cueState = cueState
        self.style = style
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let safeRect = makeSafeRect(in: size)
                let timestamp = timeline.date.timeIntervalSinceReferenceDate

                Canvas(rendersAsynchronously: true) { context, canvasSize in
                    draw(
                        in: &context,
                        size: canvasSize,
                        safeRect: safeRect,
                        timestamp: timestamp
                    )
                }
                .overlay {
                    safeZoneFrame(for: safeRect)
                }
                .onAppear {
                    phase.reset(at: timestamp)
                }
                .onChange(of: timeline.date) { _, date in
                    phase.advance(
                        to: date.timeIntervalSinceReferenceDate,
                        cueState: cueState,
                        style: style
                    )
                }
                .onChange(of: cueState) { _, _ in
                    phase.seed(from: cueState)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        safeRect: CGRect,
        timestamp: TimeInterval
    ) {
        let severity = cueState.severity
        let speed = sqrt((phase.velocity.dx * phase.velocity.dx) + (phase.velocity.dy * phase.velocity.dy))
        let trailLength = min(style.dotSpacing * 0.92, (speed * style.trailScale) + (CGFloat(severity) * 7.0))
        let heading = normalized(vector: phase.velocity)

        drawPeripheralGlow(in: &context, size: size, safeRect: safeRect, severity: severity)

        let startX = wrappedOffset(phase.offset.x, spacing: style.dotSpacing) - style.dotSpacing
        let startY = wrappedOffset(phase.offset.y, spacing: style.dotSpacing) - style.dotSpacing

        for x in stride(from: startX, through: size.width + style.dotSpacing, by: style.dotSpacing) {
            for y in stride(from: startY, through: size.height + style.dotSpacing, by: style.dotSpacing) {
                let point = CGPoint(x: x, y: y)

                if safeRect.contains(point) {
                    continue
                }

                let gridX = Int(round((x - phase.offset.x) / style.dotSpacing))
                let gridY = Int(round((y - phase.offset.y) / style.dotSpacing))
                let hash = pseudoRandom(gridX: gridX, gridY: gridY)
                let edgeWeight = peripheralWeight(for: point, in: size, safeRect: safeRect)
                let density = style.baseDensity + (severity * style.densityBoost) + (Double(edgeWeight) * 0.12)

                guard hash < density else {
                    continue
                }

                let opacity = min(
                    1.0,
                    style.baseOpacity
                        + (severity * style.opacityBoost)
                        + (Double(edgeWeight) * 0.16)
                        + ((1.0 - hash) * 0.10)
                )
                let radius = style.baseRadius
                    + (CGFloat(severity) * style.radiusBoost)
                    + (edgeWeight * 1.2)

                if trailLength > 2.5 {
                    let trailPath = Path { path in
                        path.move(
                            to: CGPoint(
                                x: point.x - (heading.dx * trailLength),
                                y: point.y - (heading.dy * trailLength)
                            )
                        )
                        path.addLine(to: point)
                    }

                    context.stroke(
                        trailPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                style.tint.opacity(0.0),
                                style.accent.opacity(opacity * 0.22),
                                style.glow.opacity(opacity * 0.86)
                            ]),
                            startPoint: CGPoint(
                                x: point.x - (heading.dx * trailLength),
                                y: point.y - (heading.dy * trailLength)
                            ),
                            endPoint: point
                        ),
                        style: StrokeStyle(lineWidth: radius * 0.9, lineCap: .round)
                    )
                }

                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2.0,
                    height: radius * 2.0
                )

                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [
                            style.glow.opacity(opacity),
                            style.accent.opacity(opacity * 0.56),
                            style.tint.opacity(0.0)
                        ]),
                        center: point,
                        startRadius: 0.8,
                        endRadius: radius * 2.2
                    )
                )
            }
        }

        let pulse = (sin(timestamp * 0.9) + 1.0) * 0.5
        let centerGlowOpacity = 0.05 + (severity * 0.10) + (pulse * 0.04)
        context.fill(
            Path(roundedRect: safeRect.insetBy(dx: -16.0, dy: -16.0), cornerRadius: style.safeZoneCornerRadius + 14.0),
            with: .radialGradient(
                Gradient(colors: [
                    .clear,
                    style.accent.opacity(centerGlowOpacity),
                    .clear
                ]),
                center: CGPoint(x: safeRect.midX, y: safeRect.midY),
                startRadius: max(safeRect.width, safeRect.height) * 0.26,
                endRadius: max(safeRect.width, safeRect.height) * 0.78
            )
        )
    }

    private func drawPeripheralGlow(
        in context: inout GraphicsContext,
        size: CGSize,
        safeRect: CGRect,
        severity: Double
    ) {
        let outerRect = CGRect(origin: .zero, size: size)
        let glowAlpha = 0.10 + (severity * 0.16)
        let ringRect = safeRect.insetBy(dx: -72.0, dy: -72.0)

        context.fill(
            Path(outerRect),
            with: .radialGradient(
                Gradient(colors: [
                    style.accent.opacity(glowAlpha * 0.58),
                    style.tint.opacity(glowAlpha * 0.18),
                    .clear
                ]),
                center: CGPoint(x: safeRect.midX, y: safeRect.midY),
                startRadius: max(safeRect.width, safeRect.height) * 0.48,
                endRadius: max(size.width, size.height) * 0.76
            )
        )

        context.stroke(
            Path(roundedRect: ringRect, cornerRadius: style.safeZoneCornerRadius + 18.0),
            with: .color(style.accent.opacity(0.08 + (severity * 0.14))),
            lineWidth: 1.0
        )
    }

    private func safeZoneFrame(for safeRect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: style.safeZoneCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        style.accent.opacity(0.22),
                        style.glow.opacity(0.14),
                        style.accent.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0
            )
            .background(
                RoundedRectangle(cornerRadius: style.safeZoneCornerRadius, style: .continuous)
                    .fill(.black.opacity(0.02))
            )
            .frame(width: safeRect.width, height: safeRect.height)
            .position(x: safeRect.midX, y: safeRect.midY)
            .blur(radius: 0.2)
    }

    private func makeSafeRect(in size: CGSize) -> CGRect {
        let width = size.width * style.safeZoneWidthRatio
        let height = size.height * style.safeZoneHeightRatio
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    private func wrappedOffset(_ offset: CGFloat, spacing: CGFloat) -> CGFloat {
        guard spacing > 0.0 else {
            return 0.0
        }

        let remainder = offset.truncatingRemainder(dividingBy: spacing)
        return remainder >= 0.0 ? remainder : remainder + spacing
    }

    private func peripheralWeight(for point: CGPoint, in size: CGSize, safeRect: CGRect) -> CGFloat {
        let dx = max(safeRect.minX - point.x, 0.0, point.x - safeRect.maxX)
        let dy = max(safeRect.minY - point.y, 0.0, point.y - safeRect.maxY)
        let distance = sqrt((dx * dx) + (dy * dy))
        let maxDistance = max(size.width, size.height) * 0.42
        let normalized = clamp(distance / maxDistance, minimum: 0.0, maximum: 1.0)
        return 1.0 - normalized
    }

    private func pseudoRandom(gridX: Int, gridY: Int) -> Double {
        let value = sin((Double(gridX) * 12.9898) + (Double(gridY) * 78.233)) * 43758.5453
        return abs(value).truncatingRemainder(dividingBy: 1.0)
    }

    private func normalized(vector: CGVector) -> CGVector {
        let magnitude = sqrt((vector.dx * vector.dx) + (vector.dy * vector.dy))
        guard magnitude > 0.0001 else {
            return CGVector(dx: 0.0, dy: -1.0)
        }

        return CGVector(dx: vector.dx / magnitude, dy: vector.dy / magnitude)
    }
}

private struct MotionFlowPhase {
    var offset: CGPoint = .zero
    var velocity: CGVector = .zero
    var lastTimestamp: TimeInterval?

    mutating func reset(at timestamp: TimeInterval) {
        offset = .zero
        velocity = .zero
        lastTimestamp = timestamp
    }

    mutating func seed(from cueState: CueState) {
        velocity.dx += (-cueState.lateralOffset * 0.0025)
        velocity.dy += (-cueState.longitudinalOffset * 0.0018)
    }

    mutating func advance(to timestamp: TimeInterval, cueState: CueState, style: MotionFlowStyle) {
        guard let lastTimestamp else {
            reset(at: timestamp)
            return
        }

        let delta = clamp(timestamp - lastTimestamp, minimum: 1.0 / 120.0, maximum: 1.0 / 18.0)
        self.lastTimestamp = timestamp

        let idleX = sin(timestamp * 0.33) * style.idleDrift
        let idleY = cos(timestamp * 0.27) * style.idleDrift * 0.72
        let severityGain = CGFloat(0.75 + (cueState.severity * 1.45))
        let targetVelocity = CGVector(
            dx: (-cueState.lateralOffset * style.velocityGain * severityGain) + idleX,
            dy: (-cueState.longitudinalOffset * style.velocityGain * severityGain * 0.86) + idleY
        )

        velocity.dx += (targetVelocity.dx - velocity.dx) * style.response
        velocity.dy += (targetVelocity.dy - velocity.dy) * style.response
        velocity.dx *= (1.0 - style.friction)
        velocity.dy *= (1.0 - style.friction)

        offset.x += velocity.dx * CGFloat(delta * 60.0)
        offset.y += velocity.dy * CGFloat(delta * 60.0)

        if abs(offset.x) > 100_000.0 {
            offset.x.formTruncatingRemainder(dividingBy: style.dotSpacing * 1000.0)
        }

        if abs(offset.y) > 100_000.0 {
            offset.y.formTruncatingRemainder(dividingBy: style.dotSpacing * 1000.0)
        }
    }
}
