import SwiftUI

public struct CloudVisualStyle: Sendable {
    public struct Blob: Sendable {
        public var anchorX: CGFloat
        public var anchorY: CGFloat
        public var widthRatio: CGFloat
        public var heightRatio: CGFloat
        public var driftX: CGFloat
        public var driftY: CGFloat
        public var rotation: Double
        public var blurRadius: CGFloat
        public var opacityMultiplier: Double

        public init(
            anchorX: CGFloat,
            anchorY: CGFloat,
            widthRatio: CGFloat,
            heightRatio: CGFloat,
            driftX: CGFloat,
            driftY: CGFloat,
            rotation: Double,
            blurRadius: CGFloat,
            opacityMultiplier: Double
        ) {
            self.anchorX = anchorX
            self.anchorY = anchorY
            self.widthRatio = widthRatio
            self.heightRatio = heightRatio
            self.driftX = driftX
            self.driftY = driftY
            self.rotation = rotation
            self.blurRadius = blurRadius
            self.opacityMultiplier = opacityMultiplier
        }
    }

    public var baseColors: [Color]
    public var blobColors: [Color]
    public var highlightColor: Color
    public var blobs: [Blob]
    public var baseOpacity: Double

    public init(
        baseColors: [Color],
        blobColors: [Color],
        highlightColor: Color,
        blobs: [Blob],
        baseOpacity: Double
    ) {
        self.baseColors = baseColors
        self.blobColors = blobColors
        self.highlightColor = highlightColor
        self.blobs = blobs
        self.baseOpacity = baseOpacity
    }

    public static let calmAurora = CloudVisualStyle(
        baseColors: [
            Color(red: 0.06, green: 0.14, blue: 0.20),
            Color(red: 0.04, green: 0.18, blue: 0.24),
            Color(red: 0.10, green: 0.12, blue: 0.18)
        ],
        blobColors: [
            Color(red: 0.19, green: 0.78, blue: 0.73),
            Color(red: 0.22, green: 0.48, blue: 0.88),
            Color(red: 0.93, green: 0.67, blue: 0.36),
            Color(red: 0.31, green: 0.82, blue: 0.88)
        ],
        highlightColor: Color(red: 0.97, green: 0.82, blue: 0.63),
        blobs: [
            Blob(anchorX: 0.18, anchorY: 0.22, widthRatio: 0.50, heightRatio: 0.24, driftX: 36.0, driftY: 18.0, rotation: -14.0, blurRadius: 58.0, opacityMultiplier: 0.92),
            Blob(anchorX: 0.76, anchorY: 0.24, widthRatio: 0.48, heightRatio: 0.22, driftX: -32.0, driftY: 16.0, rotation: 18.0, blurRadius: 62.0, opacityMultiplier: 0.86),
            Blob(anchorX: 0.26, anchorY: 0.78, widthRatio: 0.56, heightRatio: 0.26, driftX: 28.0, driftY: -20.0, rotation: 8.0, blurRadius: 72.0, opacityMultiplier: 0.82),
            Blob(anchorX: 0.78, anchorY: 0.72, widthRatio: 0.42, heightRatio: 0.20, driftX: -22.0, driftY: -18.0, rotation: -10.0, blurRadius: 54.0, opacityMultiplier: 0.76)
        ],
        baseOpacity: 0.24
    )
}
