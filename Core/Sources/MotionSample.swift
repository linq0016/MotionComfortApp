// 原始运动快照：保存某一时刻的加速度和姿态数据。
public struct MotionSample: Equatable, Sendable {
    public var lateralAcceleration: Double
    public var longitudinalAcceleration: Double
    public var verticalAcceleration: Double

    public init(
        lateralAcceleration: Double,
        longitudinalAcceleration: Double,
        verticalAcceleration: Double
    ) {
        self.lateralAcceleration = lateralAcceleration
        self.longitudinalAcceleration = longitudinalAcceleration
        self.verticalAcceleration = verticalAcceleration
    }

    public static let neutral = MotionSample(
        lateralAcceleration: 0.0,
        longitudinalAcceleration: 0.0,
        verticalAcceleration: 0.0
    )

}
