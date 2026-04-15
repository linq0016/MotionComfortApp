import Foundation

// 原始运动快照：保存某一时刻的加速度和姿态数据。
public struct MotionSample: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var lateralAcceleration: Double
    public var longitudinalAcceleration: Double
    public var verticalAcceleration: Double
    public var pitch: Double
    public var roll: Double
    public var yawRate: Double

    public init(
        timestamp: TimeInterval,
        lateralAcceleration: Double,
        longitudinalAcceleration: Double,
        verticalAcceleration: Double,
        pitch: Double,
        roll: Double,
        yawRate: Double
    ) {
        self.timestamp = timestamp
        self.lateralAcceleration = lateralAcceleration
        self.longitudinalAcceleration = longitudinalAcceleration
        self.verticalAcceleration = verticalAcceleration
        self.pitch = pitch
        self.roll = roll
        self.yawRate = yawRate
    }

    public static let neutral = MotionSample(
        timestamp: 0.0,
        lateralAcceleration: 0.0,
        longitudinalAcceleration: 0.0,
        verticalAcceleration: 0.0,
        pitch: 0.0,
        roll: 0.0,
        yawRate: 0.0
    )

    // 用于界面和音频的简化强度值，不直接参与点阵所有细节。
    public var intensity: Double {
        let combined = abs(lateralAcceleration) + (abs(longitudinalAcceleration) * 0.8) + (abs(yawRate) * 0.12)
        return clamp(combined / 0.9, minimum: 0.0, maximum: 1.0)
    }
}
