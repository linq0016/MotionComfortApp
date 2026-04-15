import SwiftUI

public struct MotionFlowStyle: Sendable {
    public var dotSpacing: CGFloat
    public var safeZoneWidthRatio: CGFloat
    public var safeZoneHeightRatio: CGFloat
    public var safeZoneCornerRadius: CGFloat
    public var baseDensity: Double
    public var densityBoost: Double
    public var baseOpacity: Double
    public var opacityBoost: Double
    public var baseRadius: CGFloat
    public var radiusBoost: CGFloat
    public var trailScale: CGFloat
    public var velocityGain: CGFloat
    public var response: CGFloat
    public var friction: CGFloat
    public var idleDrift: CGFloat
    public var tint: Color
    public var accent: Color
    public var glow: Color

    public init(
        dotSpacing: CGFloat,
        safeZoneWidthRatio: CGFloat,
        safeZoneHeightRatio: CGFloat,
        safeZoneCornerRadius: CGFloat,
        baseDensity: Double,
        densityBoost: Double,
        baseOpacity: Double,
        opacityBoost: Double,
        baseRadius: CGFloat,
        radiusBoost: CGFloat,
        trailScale: CGFloat,
        velocityGain: CGFloat,
        response: CGFloat,
        friction: CGFloat,
        idleDrift: CGFloat,
        tint: Color,
        accent: Color,
        glow: Color
    ) {
        self.dotSpacing = dotSpacing
        self.safeZoneWidthRatio = safeZoneWidthRatio
        self.safeZoneHeightRatio = safeZoneHeightRatio
        self.safeZoneCornerRadius = safeZoneCornerRadius
        self.baseDensity = baseDensity
        self.densityBoost = densityBoost
        self.baseOpacity = baseOpacity
        self.opacityBoost = opacityBoost
        self.baseRadius = baseRadius
        self.radiusBoost = radiusBoost
        self.trailScale = trailScale
        self.velocityGain = velocityGain
        self.response = response
        self.friction = friction
        self.idleDrift = idleDrift
        self.tint = tint
        self.accent = accent
        self.glow = glow
    }

    public static let hybridDynamic = MotionFlowStyle(
        dotSpacing: 34.0,
        safeZoneWidthRatio: 0.40,
        safeZoneHeightRatio: 0.40,
        safeZoneCornerRadius: 30.0,
        baseDensity: 0.18,
        densityBoost: 0.48,
        baseOpacity: 0.14,
        opacityBoost: 0.72,
        baseRadius: 1.9,
        radiusBoost: 4.6,
        trailScale: 13.0,
        velocityGain: 0.055,
        response: 0.18,
        friction: 0.08,
        idleDrift: 3.0,
        tint: Color(red: 0.82, green: 0.98, blue: 1.0),
        accent: Color(red: 0.42, green: 0.90, blue: 0.98),
        glow: Color(red: 0.95, green: 0.83, blue: 0.62)
    )
}
