import Foundation

// 原始运动快照：保存某一时刻的加速度和姿态数据。
public struct MotionSample: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var lateralAcceleration: Double
    public var longitudinalAcceleration: Double
    public var verticalAcceleration: Double

    public init(
        timestamp: TimeInterval,
        lateralAcceleration: Double,
        longitudinalAcceleration: Double,
        verticalAcceleration: Double
    ) {
        self.timestamp = timestamp
        self.lateralAcceleration = lateralAcceleration
        self.longitudinalAcceleration = longitudinalAcceleration
        self.verticalAcceleration = verticalAcceleration
    }

    public static let neutral = MotionSample(
        timestamp: 0.0,
        lateralAcceleration: 0.0,
        longitudinalAcceleration: 0.0,
        verticalAcceleration: 0.0
    )

}
