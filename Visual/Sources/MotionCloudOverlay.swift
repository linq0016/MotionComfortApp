import MotionComfortCore
import SwiftUI

public struct MotionCloudOverlay: View {
    public var cueState: CueState
    public var style: CloudVisualStyle

    public init(cueState: CueState, style: CloudVisualStyle = .calmAurora) {
        self.cueState = cueState
        self.style = style
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let severity = cueState.severity
                let driftX = cueState.lateralOffset * 0.28
                let driftY = cueState.longitudinalOffset * 0.18

                ZStack {
                    LinearGradient(
                        colors: style.baseColors.map { $0.opacity(style.baseOpacity + (severity * 0.12)) },
                        startPoint: UnitPoint(
                            x: 0.25 + Double(cueState.lateralOffset / 280.0),
                            y: 0.10
                        ),
                        endPoint: UnitPoint(
                            x: 0.85,
                            y: 0.92 + Double(cueState.longitudinalOffset / 460.0)
                        )
                    )
                    .overlay {
                        AngularGradient(
                            colors: [
                                style.blobColors[0].opacity(0.06 + (severity * 0.10)),
                                style.blobColors[1].opacity(0.03 + (severity * 0.08)),
                                style.blobColors[2].opacity(0.06 + (severity * 0.10)),
                                style.blobColors[3].opacity(0.03 + (severity * 0.08)),
                                style.blobColors[0].opacity(0.06 + (severity * 0.10))
                            ],
                            center: .center
                        )
                        .blur(radius: 68.0)
                        .blendMode(.screen)
                    }

                    ForEach(Array(style.blobs.enumerated()), id: \.offset) { index, blob in
                        cloudBlob(
                            index: index,
                            blob: blob,
                            size: proxy.size,
                            phase: phase
                        )
                    }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    style.blobColors[1].opacity(0.0),
                                    style.blobColors[0].opacity(0.10 + (severity * 0.12)),
                                    style.highlightColor.opacity(0.12 + (severity * 0.14)),
                                    style.blobColors[3].opacity(0.08 + (severity * 0.10)),
                                    style.blobColors[1].opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: proxy.size.width * (0.72 + (severity * 0.12)),
                            height: proxy.size.height * 0.14
                        )
                        .rotationEffect(.degrees(Double(cueState.horizonTilt * 0.24)))
                        .offset(x: driftX * 0.42, y: driftY - 36.0)
                        .blur(radius: 34.0)
                        .blendMode(.screen)

                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    style.highlightColor.opacity(0.16 + (severity * 0.18)),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 12.0,
                                endRadius: max(proxy.size.width, proxy.size.height) * 0.46
                            )
                        )
                        .frame(
                            width: proxy.size.width * 0.82,
                            height: proxy.size.height * 0.52
                        )
                        .offset(
                            x: driftX,
                            y: driftY
                        )
                        .blur(radius: 30.0)
                        .blendMode(.screen)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cloudBlob(index: Int, blob: CloudVisualStyle.Blob, size: CGSize, phase: TimeInterval) -> some View {
        let driftPhase = phase * (0.09 + (Double(index) * 0.015))
        let severity = cueState.severity
        let x = (size.width * blob.anchorX)
            + (sin(driftPhase) * blob.driftX)
            + (cueState.lateralOffset * (0.58 + (CGFloat(index) * 0.10)))
        let y = (size.height * blob.anchorY)
            + (cos(driftPhase * 1.12) * blob.driftY)
            + (cueState.longitudinalOffset * (0.32 + (CGFloat(index) * 0.08)))
        let width = size.width * blob.widthRatio * (1.0 + (severity * 0.14))
        let height = size.height * blob.heightRatio * (1.0 + (severity * 0.12))
        let opacity = (0.16 + (severity * 0.20)) * blob.opacityMultiplier
        let primary = style.blobColors[index % style.blobColors.count]
        let secondary = style.blobColors[(index + 1) % style.blobColors.count]

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            primary.opacity(opacity),
                            secondary.opacity(opacity * 0.64),
                            .clear
                        ],
                        center: .center,
                        startRadius: 16.0,
                        endRadius: width * 0.52
                    )
                )
                .frame(width: width, height: height)
                .rotationEffect(.degrees(blob.rotation + (sin(driftPhase * 0.8) * 10.0)))
                .offset(x: x, y: y)
                .blur(radius: blob.blurRadius + (severity * 22.0))

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            secondary.opacity(opacity * 0.62),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10.0,
                        endRadius: width * 0.34
                    )
                )
                .frame(width: width * 0.68, height: height * 0.54)
                .rotationEffect(.degrees((-blob.rotation * 0.8) + (cos(driftPhase) * 8.0)))
                .offset(
                    x: x + (cueState.lateralOffset * 0.08) - (width * 0.08),
                    y: y - (height * 0.06)
                )
                .blur(radius: blob.blurRadius * 0.66)
        }
        .blendMode(.screen)
    }
}
