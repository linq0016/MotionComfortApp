import MotionComfortCore
import SwiftUI

// 共享光流状态：给 Minimal 和 Live View 复用同一套运动手感。
struct FlowGridRenderState {
    var offset: CGPoint = .zero
    var smoothedMagnitude: Double = 0.0
}

// 共享参数表：集中控制点阵的速度、密度、亮度和尺寸。
struct FlowGridConfiguration: Sendable {
    var backgroundColor: Color
    var dotSpacing: CGFloat
    var marginRatio: CGFloat
    var horizontalMarginRatio: CGFloat
    var verticalMarginRatio: CGFloat
    var safeZoneCornerRadius: CGFloat
    var safeZoneFeatherWidth: CGFloat
    var sensorSmoothing: Double
    var velocityMultiplier: Double
    var velocityFriction: Double
    var magnitudeSmoothing: Double
    var magnitudeDecaySmoothing: Double
    var maxAccelThreshold: Double
    var motionDeadzone: Double
    var baseDensity: Double
    var extraDensityRange: Double
    var baseOpacity: Double
    var baseRadius: CGFloat
    var maxExtraRadius: CGFloat
    var edgeRadiusBoost: CGFloat
    var edgeRadiusCurve: CGFloat
    var minimumVisibleAlpha: Double
    var maxAlpha: Double
    var fadeMultiplier: Double
    var alphaVariation: Double
    var invertHorizontalFlow: Bool
    var invertVerticalFlow: Bool

    static let minimal = FlowGridConfiguration(
        backgroundColor: Color.black,
        dotSpacing: 35.0,
        marginRatio: 0.25,
        horizontalMarginRatio: 0.25,
        verticalMarginRatio: 0.25,
        safeZoneCornerRadius: 0.0,
        safeZoneFeatherWidth: 0.0,
        sensorSmoothing: 0.08,
        velocityMultiplier: 25.0 * (2.0 / 3.0),
        velocityFriction: 0.15,
        magnitudeSmoothing: 0.9,
        magnitudeDecaySmoothing: 0.94,
        maxAccelThreshold: 0.33,
        motionDeadzone: 0.006,
        baseDensity: 0.20,
        extraDensityRange: 0.60,
        baseOpacity: 0.12,
        baseRadius: 1.6,
        maxExtraRadius: 3.5,
        edgeRadiusBoost: 5.0,
        edgeRadiusCurve: 1.85,
        minimumVisibleAlpha: 0.018,
        maxAlpha: 0.76,
        fadeMultiplier: 1.45,
        alphaVariation: 0.50,
        invertHorizontalFlow: true,
        invertVerticalFlow: true
    )

    static let liveViewEdge = FlowGridConfiguration(
        backgroundColor: Color.clear,
        dotSpacing: 32.0,
        marginRatio: 0.24,
        horizontalMarginRatio: 0.26,
        verticalMarginRatio: 0.20,
        safeZoneCornerRadius: 40.0,
        safeZoneFeatherWidth: 88.0,
        sensorSmoothing: 0.08,
        velocityMultiplier: 25.0 * (2.0 / 3.0),
        velocityFriction: 0.15,
        magnitudeSmoothing: 0.9,
        magnitudeDecaySmoothing: 0.94,
        maxAccelThreshold: 0.33,
        motionDeadzone: 0.006,
        baseDensity: 0.20,
        extraDensityRange: 0.64,
        baseOpacity: 0.21,
        baseRadius: 1.8,
        maxExtraRadius: 3.5,
        edgeRadiusBoost: 4.2,
        edgeRadiusCurve: 1.72,
        minimumVisibleAlpha: 0.03,
        maxAlpha: 0.86,
        fadeMultiplier: 1.55,
        alphaVariation: 0.50,
        invertHorizontalFlow: true,
        invertVerticalFlow: true
    )
}

// 共享相位：把传感器输入积分成连续滚动的点阵状态。
struct FlowGridPhase {
    var filteredAcceleration: CGVector = .zero
    var filteredVerticalAcceleration: Double = 0.0
    var currentVelocity: CGVector = .zero
    var currentOffset: CGPoint = .zero
    var smoothedMagnitude: Double = 0.0
    var lastTimestamp: TimeInterval?

    var renderState: FlowGridRenderState {
        FlowGridRenderState(offset: currentOffset, smoothedMagnitude: smoothedMagnitude)
    }

    mutating func reset(at timestamp: TimeInterval) {
        filteredAcceleration = .zero
        filteredVerticalAcceleration = 0.0
        currentVelocity = .zero
        currentOffset = .zero
        smoothedMagnitude = 0.0
        lastTimestamp = timestamp
    }

    // 这里是核心：把传感器数据变成点阵的位移、大小和亮度状态。
    mutating func advance(sample: MotionSample, timestamp: TimeInterval, configuration: FlowGridConfiguration) {
        guard lastTimestamp != nil else {
            reset(at: timestamp)
            return
        }

        lastTimestamp = timestamp

        filteredAcceleration.dx = (configuration.sensorSmoothing * sample.lateralAcceleration)
            + ((1.0 - configuration.sensorSmoothing) * filteredAcceleration.dx)
        filteredAcceleration.dy = (configuration.sensorSmoothing * sample.longitudinalAcceleration)
            + ((1.0 - configuration.sensorSmoothing) * filteredAcceleration.dy)
        filteredVerticalAcceleration = (configuration.sensorSmoothing * sample.verticalAcceleration)
            + ((1.0 - configuration.sensorSmoothing) * filteredVerticalAcceleration)

        let rawMagnitude = sqrt(
            (filteredAcceleration.dx * filteredAcceleration.dx)
                + (filteredAcceleration.dy * filteredAcceleration.dy)
                + (filteredVerticalAcceleration * filteredVerticalAcceleration)
        )

        if rawMagnitude >= smoothedMagnitude {
            smoothedMagnitude = (smoothedMagnitude * configuration.magnitudeSmoothing)
                + (rawMagnitude * (1.0 - configuration.magnitudeSmoothing))
        } else {
            smoothedMagnitude = (smoothedMagnitude * configuration.magnitudeDecaySmoothing)
                + (rawMagnitude * (1.0 - configuration.magnitudeDecaySmoothing))
        }

        let horizontalDirection = configuration.invertHorizontalFlow ? 1.0 : -1.0
        let targetVelocityX = rawMagnitude > configuration.motionDeadzone
            ? (filteredAcceleration.dx * configuration.velocityMultiplier * horizontalDirection)
            : 0.0
        let verticalDirection = configuration.invertVerticalFlow ? 1.0 : -1.0
        let targetVelocityY = rawMagnitude > configuration.motionDeadzone
            ? ((filteredAcceleration.dy + filteredVerticalAcceleration) * configuration.velocityMultiplier * verticalDirection)
            : 0.0

        currentVelocity.dx += (targetVelocityX - currentVelocity.dx) * configuration.velocityFriction
        currentVelocity.dy += (targetVelocityY - currentVelocity.dy) * configuration.velocityFriction

        currentOffset.x += currentVelocity.dx
        currentOffset.y += currentVelocity.dy

        if abs(currentOffset.x) > 100_000.0 {
            currentOffset.x.formTruncatingRemainder(dividingBy: configuration.dotSpacing * 1000.0)
        }

        if abs(currentOffset.y) > 100_000.0 {
            currentOffset.y.formTruncatingRemainder(dividingBy: configuration.dotSpacing * 1000.0)
        }
    }
}

func flowWrappedOffset(_ offset: CGFloat, spacing: CGFloat) -> CGFloat {
    guard spacing > 0.0 else {
        return 0.0
    }

    let remainder = offset.truncatingRemainder(dividingBy: spacing)
    return remainder >= 0.0 ? remainder : remainder + spacing
}

func flowPseudoRandom(gridX: Int, gridY: Int) -> Double {
    abs(sin((Double(gridX) * 12.9898) + (Double(gridY) * 78.233)) * 43758.5453)
        .truncatingRemainder(dividingBy: 1.0)
}

func flowDotAppearance(
    hash: Double,
    normA: Double,
    configuration: FlowGridConfiguration
) -> (alpha: Double, radius: CGFloat)? {
    var alpha = 0.0
    var radius = configuration.baseRadius

    if hash < configuration.baseDensity {
        alpha = configuration.baseOpacity + (normA * (1.0 - configuration.baseOpacity))
        radius = configuration.baseRadius + (normA * configuration.maxExtraRadius)
    } else if hash < configuration.baseDensity + (normA * configuration.extraDensityRange) {
        let fadeProgress = (normA * configuration.extraDensityRange) - (hash - configuration.baseDensity)
        alpha = min(fadeProgress * configuration.fadeMultiplier, configuration.maxAlpha)
        radius = configuration.baseRadius + (normA * configuration.maxExtraRadius)
    }

    if configuration.alphaVariation > 0.0 {
        let variationRange = configuration.alphaVariation * (0.90 + (0.70 * normA))
        let variation = 1.0 - (variationRange * 0.5) + (hash * variationRange)
        alpha *= variation
    }

    guard alpha > configuration.minimumVisibleAlpha else {
        return nil
    }

    return (alpha, radius)
}
