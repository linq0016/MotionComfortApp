import Foundation
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

struct FlowGridStaticPoint: Sendable {
    let basePosition: CGPoint
    let gridX: Int
    let gridY: Int
}

struct FlowGridStaticLayout: Sendable {
    let size: CGSize
    let safeRect: CGRect
    let safeZoneCornerRadius: CGFloat
    let points: [FlowGridStaticPoint]
}

final class FlowGridLayoutCache: @unchecked Sendable {
    static let shared = FlowGridLayoutCache()

    private let cache = NSCache<FlowGridLayoutCacheKey, FlowGridLayoutBox>()

    private init() {
        cache.countLimit = 24
    }

    func layout(
        size: CGSize,
        configuration: FlowGridConfiguration,
        orientation: InterfaceRenderOrientation
    ) -> FlowGridStaticLayout {
        let key = FlowGridLayoutCacheKey(
            size: size,
            configuration: configuration,
            orientation: orientation
        )
        if let cached = cache.object(forKey: key) {
            return cached.layout
        }

        let layout = makeLayout(
            size: size,
            configuration: configuration,
            orientation: orientation
        )
        cache.setObject(FlowGridLayoutBox(layout: layout), forKey: key)
        return layout
    }

    private func makeLayout(
        size: CGSize,
        configuration: FlowGridConfiguration,
        orientation: InterfaceRenderOrientation
    ) -> FlowGridStaticLayout {
        let safeRect = flowGridSafeRect(
            in: size,
            configuration: configuration,
            orientation: orientation
        )
        let safeZoneCornerRadius = min(
            configuration.safeZoneCornerRadius,
            min(safeRect.width, safeRect.height) * 0.5
        )

        guard size.width > 0.0, size.height > 0.0, configuration.dotSpacing > 0.0 else {
            return FlowGridStaticLayout(
                size: size,
                safeRect: safeRect,
                safeZoneCornerRadius: safeZoneCornerRadius,
                points: []
            )
        }

        let maxGridX = Int(floor((size.width + configuration.dotSpacing) / configuration.dotSpacing))
        let maxGridY = Int(floor((size.height + configuration.dotSpacing) / configuration.dotSpacing))
        var points: [FlowGridStaticPoint] = []
        points.reserveCapacity((maxGridX + 2) * (maxGridY + 2))

        for gridX in -1...maxGridX {
            let baseX = CGFloat(gridX) * configuration.dotSpacing

            for gridY in -1...maxGridY {
                let baseY = CGFloat(gridY) * configuration.dotSpacing
                points.append(
                    FlowGridStaticPoint(
                        basePosition: CGPoint(x: baseX, y: baseY),
                        gridX: gridX,
                        gridY: gridY
                    )
                )
            }
        }

        return FlowGridStaticLayout(
            size: size,
            safeRect: safeRect,
            safeZoneCornerRadius: safeZoneCornerRadius,
            points: points
        )
    }
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

private final class FlowGridLayoutCacheKey: NSObject {
    private let rawValue: String

    init(
        size: CGSize,
        configuration: FlowGridConfiguration,
        orientation: InterfaceRenderOrientation
    ) {
        rawValue = [
            flowGridCacheComponent(size.width),
            flowGridCacheComponent(size.height),
            flowGridCacheComponent(configuration.dotSpacing),
            flowGridCacheComponent(configuration.marginRatio),
            flowGridCacheComponent(configuration.horizontalMarginRatio),
            flowGridCacheComponent(configuration.verticalMarginRatio),
            flowGridCacheComponent(configuration.safeZoneCornerRadius),
            flowGridCacheComponent(configuration.safeZoneFeatherWidth),
            flowGridOrientationCacheComponent(orientation)
        ]
            .joined(separator: ":")
    }

    override var hash: Int {
        rawValue.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FlowGridLayoutCacheKey else {
            return false
        }

        return rawValue == other.rawValue
    }
}

private final class FlowGridLayoutBox: NSObject {
    let layout: FlowGridStaticLayout

    init(layout: FlowGridStaticLayout) {
        self.layout = layout
    }
}

func flowWrappedOffset(_ offset: CGFloat, spacing: CGFloat) -> CGFloat {
    guard spacing > 0.0 else {
        return 0.0
    }

    let remainder = offset.truncatingRemainder(dividingBy: spacing)
    return remainder >= 0.0 ? remainder : remainder + spacing
}

func flowIntegralCellOffset(_ offset: CGFloat, spacing: CGFloat) -> Int {
    guard spacing > 0.0 else {
        return 0
    }

    let wrappedOffset = flowWrappedOffset(offset, spacing: spacing)
    return Int(round((offset - wrappedOffset) / spacing))
}

func flowGridSafeRect(
    in size: CGSize,
    configuration: FlowGridConfiguration,
    orientation: InterfaceRenderOrientation
) -> CGRect {
    let baseHorizontalMargin = configuration.horizontalMarginRatio > 0.0
        ? configuration.horizontalMarginRatio
        : configuration.marginRatio
    let baseVerticalMargin = configuration.verticalMarginRatio > 0.0
        ? configuration.verticalMarginRatio
        : configuration.marginRatio

    let horizontalMarginRatio: CGFloat
    let verticalMarginRatio: CGFloat

    switch orientation {
    case .portrait:
        horizontalMarginRatio = baseHorizontalMargin
        verticalMarginRatio = baseVerticalMargin
    case .landscapeLeft, .landscapeRight:
        horizontalMarginRatio = baseVerticalMargin
        verticalMarginRatio = baseHorizontalMargin
    }

    return CGRect(
        x: size.width * horizontalMarginRatio,
        y: size.height * verticalMarginRatio,
        width: size.width * (1.0 - (horizontalMarginRatio * 2.0)),
        height: size.height * (1.0 - (verticalMarginRatio * 2.0))
    )
}

func flowEdgeDistanceWeight(point: CGPoint, canvasSize: CGSize, safeRect: CGRect) -> CGFloat {
    let safeDistanceX = max(safeRect.minX - point.x, 0.0, point.x - safeRect.maxX)
    let safeDistanceY = max(safeRect.minY - point.y, 0.0, point.y - safeRect.maxY)
    let distanceFromSafeZone = sqrt((safeDistanceX * safeDistanceX) + (safeDistanceY * safeDistanceY))

    let cornerDistances = [
        hypot(safeRect.minX, safeRect.minY),
        hypot(canvasSize.width - safeRect.maxX, safeRect.minY),
        hypot(safeRect.minX, canvasSize.height - safeRect.maxY),
        hypot(canvasSize.width - safeRect.maxX, canvasSize.height - safeRect.maxY)
    ]
    let maxDistance = max(cornerDistances.max() ?? 1.0, 1.0)
    let normalized = min(max(distanceFromSafeZone / maxDistance, 0.0), 1.0)
    return normalized
}

func flowRoundedRectContains(point: CGPoint, rect: CGRect, cornerRadius: CGFloat) -> Bool {
    flowDistanceToRoundedRect(point: point, rect: rect, cornerRadius: cornerRadius) <= 0.0
}

func flowDistanceToRoundedRect(
    point: CGPoint,
    rect: CGRect,
    cornerRadius: CGFloat
) -> CGFloat {
    let radius = min(cornerRadius, min(rect.width, rect.height) * 0.5)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let localX = abs(point.x - center.x)
    let localY = abs(point.y - center.y)
    let halfWidth = (rect.width * 0.5) - radius
    let halfHeight = (rect.height * 0.5) - radius
    let deltaX = localX - max(halfWidth, 0.0)
    let deltaY = localY - max(halfHeight, 0.0)
    let outsideDistance = hypot(max(deltaX, 0.0), max(deltaY, 0.0))
    let insideDistance = min(max(deltaX, deltaY), 0.0)
    return outsideDistance + insideDistance - radius
}

func flowSmootherstep(_ value: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0.0), 1.0)
    return clamped * clamped * clamped * (clamped * ((6.0 * clamped) - 15.0) + 10.0)
}

func flowPseudoRandom(gridX: Int, gridY: Int) -> Double {
    abs(sin((Double(gridX) * 12.9898) + (Double(gridY) * 78.233)) * 43758.5453)
        .truncatingRemainder(dividingBy: 1.0)
}

private func flowGridCacheComponent(_ value: CGFloat) -> String {
    String(Int((value * 1000.0).rounded()))
}

private func flowGridOrientationCacheComponent(_ orientation: InterfaceRenderOrientation) -> String {
    switch orientation {
    case .portrait:
        return "portrait"
    case .landscapeLeft:
        return "landscapeLeft"
    case .landscapeRight:
        return "landscapeRight"
    }
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
