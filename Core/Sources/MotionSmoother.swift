import Foundation

public struct MotionSmoother {
    public var responseFactor: Double
    private var lastSample: MotionSample

    public init(responseFactor: Double = 0.22, seed: MotionSample = .neutral) {
        self.responseFactor = responseFactor
        self.lastSample = seed
    }

    public mutating func consume(_ sample: MotionSample) -> MotionSample {
        let factor = clamp(responseFactor, minimum: 0.05, maximum: 0.95)

        let blended = MotionSample(
            timestamp: sample.timestamp,
            lateralAcceleration: lerp(lastSample.lateralAcceleration, sample.lateralAcceleration, amount: factor),
            longitudinalAcceleration: lerp(lastSample.longitudinalAcceleration, sample.longitudinalAcceleration, amount: factor),
            verticalAcceleration: lerp(lastSample.verticalAcceleration, sample.verticalAcceleration, amount: factor),
            pitch: lerp(lastSample.pitch, sample.pitch, amount: factor),
            roll: lerp(lastSample.roll, sample.roll, amount: factor),
            yawRate: lerp(lastSample.yawRate, sample.yawRate, amount: factor)
        )

        lastSample = blended
        return blended
    }
}
