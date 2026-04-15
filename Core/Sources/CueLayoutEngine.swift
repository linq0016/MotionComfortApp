import CoreGraphics

public struct GuideDot: Identifiable, Equatable {
    public let id: String
    public let center: CGPoint
    public let diameter: CGFloat
    public let opacity: Double

    public init(id: String, center: CGPoint, diameter: CGFloat, opacity: Double) {
        self.id = id
        self.center = center
        self.diameter = diameter
        self.opacity = opacity
    }
}

public struct GuideLine: Equatable {
    public let start: CGPoint
    public let end: CGPoint
    public let opacity: Double

    public init(start: CGPoint, end: CGPoint, opacity: Double) {
        self.start = start
        self.end = end
        self.opacity = opacity
    }
}

public struct CueLayoutEngine {
    public var laneCount: Int
    public var dotsPerLane: Int
    public var edgeInset: CGFloat

    public init(laneCount: Int = 3, dotsPerLane: Int = 6, edgeInset: CGFloat = 24.0) {
        self.laneCount = laneCount
        self.dotsPerLane = dotsPerLane
        self.edgeInset = edgeInset
    }

    public func makeDots(in size: CGSize, cueState: CueState) -> [GuideDot] {
        guard size.width > 0.0, size.height > 0.0, laneCount > 0, dotsPerLane > 1 else {
            return []
        }

        let xTravel = cueState.lateralOffset
        let yTravel = cueState.longitudinalOffset
        var dots: [GuideDot] = []

        for lane in 0..<laneCount {
            let laneWeight = CGFloat(lane + 1) / CGFloat(laneCount)
            let laneInset = edgeInset + (CGFloat(lane) * 26.0)
            let width = max(size.width - (laneInset * 2.0), 1.0)
            let height = max(size.height - (laneInset * 2.0), 1.0)
            let diameter = 6.0 + (laneWeight * 4.0) + (CGFloat(cueState.severity) * 3.0)
            let opacity = cueState.glowOpacity * Double(0.64 + (laneWeight * 0.32))

            for index in 0..<dotsPerLane {
                let progress = CGFloat(index) / CGFloat(dotsPerLane - 1)
                let topX = laneInset + (progress * width) + (xTravel * 0.34)
                let topY = laneInset + (yTravel * 0.38 * laneWeight)
                dots.append(
                    GuideDot(
                        id: "top-\(lane)-\(index)",
                        center: CGPoint(x: topX, y: topY),
                        diameter: diameter,
                        opacity: opacity
                    )
                )

                let bottomX = laneInset + (progress * width) + (xTravel * 0.34)
                let bottomY = size.height - laneInset + (yTravel * 0.38 * laneWeight)
                dots.append(
                    GuideDot(
                        id: "bottom-\(lane)-\(index)",
                        center: CGPoint(x: bottomX, y: bottomY),
                        diameter: diameter,
                        opacity: opacity
                    )
                )

                let leftX = laneInset + (xTravel * 0.72 * laneWeight)
                let leftY = laneInset + (progress * height) + (yTravel * 0.26)
                dots.append(
                    GuideDot(
                        id: "left-\(lane)-\(index)",
                        center: CGPoint(x: leftX, y: leftY),
                        diameter: diameter,
                        opacity: opacity
                    )
                )

                let rightX = size.width - laneInset + (xTravel * 0.72 * laneWeight)
                let rightY = laneInset + (progress * height) + (yTravel * 0.26)
                dots.append(
                    GuideDot(
                        id: "right-\(lane)-\(index)",
                        center: CGPoint(x: rightX, y: rightY),
                        diameter: diameter,
                        opacity: opacity
                    )
                )
            }
        }

        return dots
    }

    public func makeHorizon(in size: CGSize, cueState: CueState) -> GuideLine {
        let centerY = (size.height * 0.5) + cueState.longitudinalOffset
        let tilt = cueState.horizonTilt

        return GuideLine(
            start: CGPoint(x: edgeInset * 2.0, y: centerY - tilt),
            end: CGPoint(x: size.width - (edgeInset * 2.0), y: centerY + tilt),
            opacity: 0.30 + (cueState.severity * 0.46)
        )
    }
}
