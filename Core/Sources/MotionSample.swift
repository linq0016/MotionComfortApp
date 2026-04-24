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

    // 用于界面和音频的简化强度值，不直接参与点阵所有细节。
    public var intensity: Double {
        let combined = abs(lateralAcceleration) + (abs(longitudinalAcceleration) * 0.8)
        return clamp(combined / 0.9, minimum: 0.0, maximum: 1.0)
    }
}
