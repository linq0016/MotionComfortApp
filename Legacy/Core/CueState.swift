import CoreGraphics

// 视觉中间状态：把原始运动数据整理成更适合渲染层消费的值。
public struct CueState: Equatable, Sendable {
    public var lateralOffset: CGFloat
    public var longitudinalOffset: CGFloat
    public var severity: Double
    public var glowOpacity: Double
    public var horizonTilt: CGFloat

    public init(
        lateralOffset: CGFloat,
        longitudinalOffset: CGFloat,
        severity: Double,
        glowOpacity: Double,
        horizonTilt: CGFloat
    ) {
        self.lateralOffset = lateralOffset
        self.longitudinalOffset = longitudinalOffset
        self.severity = severity
        self.glowOpacity = glowOpacity
        self.horizonTilt = horizonTilt
    }

    public static let neutral = CueState(
        lateralOffset: 0.0,
        longitudinalOffset: 0.0,
        severity: 0.0,
        glowOpacity: 0.28,
        horizonTilt: 0.0
    )

    // 把原始 MotionSample 映射成视觉层更容易使用的中间状态。
    public static func from(sample: MotionSample) -> CueState {
        let lateralOffset = clamp(CGFloat(sample.lateralAcceleration * 84.0), minimum: -64.0, maximum: 64.0)
        let longitudinalOffset = clamp(CGFloat(sample.longitudinalAcceleration * 62.0), minimum: -44.0, maximum: 44.0)
        let severity = sample.intensity
        let glowOpacity = clamp(0.34 + (severity * 0.46), minimum: 0.24, maximum: 0.92)
        let horizonTilt = clamp(CGFloat(sample.roll * 24.0), minimum: -28.0, maximum: 28.0)

        return CueState(
            lateralOffset: lateralOffset,
            longitudinalOffset: longitudinalOffset,
            severity: severity,
            glowOpacity: glowOpacity,
            horizonTilt: horizonTilt
        )
    }
}
