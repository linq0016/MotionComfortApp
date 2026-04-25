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
    var layout: FlowGridLayoutConfiguration
    var motion: FlowGridMotionConfiguration
    var appearance: FlowGridAppearanceConfiguration
    var safeZone: FlowGridSafeZoneConfiguration

    static let minimal = FlowGridConfiguration(
        layout: FlowGridLayoutConfiguration(
            backgroundColor: Color.black,
            dotSpacing: 35.0
        ),
        motion: FlowGridMotionConfiguration(
            sensorSmoothing: 0.08,
            verticalSensitivity: 1.2,
            velocityMultiplier: 10.0,
            velocityFriction: 0.15,
            magnitudeSmoothing: 0.9,
            magnitudeDecaySmoothing: 0.94,
            maxAccelThreshold: 0.6,
            motionDeadzone: 0.006,
            invertHorizontalFlow: true,
            invertVerticalFlow: true
        ),
        appearance: FlowGridAppearanceConfiguration(
            baseDensity: 0.20,
            extraDensityRange: 0.60,
            baseOpacity: 0.12,
            baseRadius: 1.6,
            maxExtraRadius: 3.5,
            edgeRadiusBoost: 4.0,
            edgeRadiusCurve: 1.75,
            minimumVisibleAlpha: 0.018,
            maxAlpha: 0.76,
            fadeMultiplier: 1.45,
            alphaVariation: 0.50
        ),
        safeZone: FlowGridSafeZoneConfiguration(
            marginRatio: 0.25,
            horizontalMarginRatio: 0.25,
            verticalMarginRatio: 0.25,
            cornerRadius: 0.0,
            featherWidth: 0.0
        )
    )

    static let liveViewEdge = FlowGridConfiguration(
        layout: FlowGridLayoutConfiguration(
            backgroundColor: Color.clear,
            dotSpacing: 32.0
        ),
        motion: FlowGridMotionConfiguration(
            sensorSmoothing: 0.08,
            verticalSensitivity: 1.2,
            velocityMultiplier: 10.0,
            velocityFriction: 0.15,
            magnitudeSmoothing: 0.9,
            magnitudeDecaySmoothing: 0.94,
            maxAccelThreshold: 0.6,
            motionDeadzone: 0.006,
            invertHorizontalFlow: true,
            invertVerticalFlow: true
        ),
        appearance: FlowGridAppearanceConfiguration(
            baseDensity: 0.20,
            extraDensityRange: 0.64,
            baseOpacity: 0.21,
            baseRadius: 1.6,
            maxExtraRadius: 3.5,
            edgeRadiusBoost: 4.0,
            edgeRadiusCurve: 1.75,
            minimumVisibleAlpha: 0.03,
            maxAlpha: 0.86,
            fadeMultiplier: 1.55,
            alphaVariation: 0.50
        ),
        safeZone: FlowGridSafeZoneConfiguration(
            marginRatio: 0.24,
            horizontalMarginRatio: 0.26,
            verticalMarginRatio: 0.20,
            cornerRadius: 40.0,
            featherWidth: 88.0
        )
    )
}

struct FlowGridLayoutConfiguration: Sendable {
    var backgroundColor: Color
    var dotSpacing: CGFloat
}

struct FlowGridMotionConfiguration: Sendable {
    var sensorSmoothing: Double
    var verticalSensitivity: Double
    var velocityMultiplier: Double
    var velocityFriction: Double
    var magnitudeSmoothing: Double
    var magnitudeDecaySmoothing: Double
    var maxAccelThreshold: Double
    var motionDeadzone: Double
    var invertHorizontalFlow: Bool
    var invertVerticalFlow: Bool
}

struct FlowGridAppearanceConfiguration: Sendable {
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
}

struct FlowGridSafeZoneConfiguration: Sendable {
    var marginRatio: CGFloat
    var horizontalMarginRatio: CGFloat
    var verticalMarginRatio: CGFloat
    var cornerRadius: CGFloat
    var featherWidth: CGFloat
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
            configuration.safeZone.cornerRadius,
            min(safeRect.width, safeRect.height) * 0.5
        )
        guard size.width > 0.0, size.height > 0.0, configuration.layout.dotSpacing > 0.0 else {
            return FlowGridStaticLayout(
                size: size,
                safeRect: safeRect,
                safeZoneCornerRadius: safeZoneCornerRadius,
                points: []
            )
        }

        let maxGridX = Int(floor((size.width + configuration.layout.dotSpacing) / configuration.layout.dotSpacing))
        let maxGridY = Int(floor((size.height + configuration.layout.dotSpacing) / configuration.layout.dotSpacing))
        var points: [FlowGridStaticPoint] = []
        points.reserveCapacity((maxGridX + 2) * (maxGridY + 2))

        for gridX in -1...maxGridX {
            let baseX = CGFloat(gridX) * configuration.layout.dotSpacing

            for gridY in -1...maxGridY {
                let baseY = CGFloat(gridY) * configuration.layout.dotSpacing
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
    mutating func advance(
        sample: MotionSample,
        timestamp: TimeInterval,
        configuration: FlowGridConfiguration,
        motionSensitivityFactor: Double = 1.0
    ) {
        guard lastTimestamp != nil else {
            reset(at: timestamp)
            return
        }

        lastTimestamp = timestamp

        filteredAcceleration.dx = (configuration.motion.sensorSmoothing * sample.lateralAcceleration)
            + ((1.0 - configuration.motion.sensorSmoothing) * filteredAcceleration.dx)
        filteredAcceleration.dy = (configuration.motion.sensorSmoothing * sample.longitudinalAcceleration)
            + ((1.0 - configuration.motion.sensorSmoothing) * filteredAcceleration.dy)
        filteredVerticalAcceleration = (configuration.motion.sensorSmoothing * sample.verticalAcceleration)
            + ((1.0 - configuration.motion.sensorSmoothing) * filteredVerticalAcceleration)
        let sensitivityFactor = min(max(motionSensitivityFactor, 2.0 / 3.0), 1.5)
        let adjustedLateralAcceleration = filteredAcceleration.dx / sensitivityFactor
        let adjustedLongitudinalAcceleration = filteredAcceleration.dy / sensitivityFactor
        let adjustedVerticalAcceleration = filteredVerticalAcceleration
            * configuration.motion.verticalSensitivity
            / sensitivityFactor

        let rawMagnitude = sqrt(
            (adjustedLateralAcceleration * adjustedLateralAcceleration)
                + (adjustedLongitudinalAcceleration * adjustedLongitudinalAcceleration)
                + (adjustedVerticalAcceleration * adjustedVerticalAcceleration)
        )

        if rawMagnitude >= smoothedMagnitude {
            smoothedMagnitude = (smoothedMagnitude * configuration.motion.magnitudeSmoothing)
                + (rawMagnitude * (1.0 - configuration.motion.magnitudeSmoothing))
        } else {
            smoothedMagnitude = (smoothedMagnitude * configuration.motion.magnitudeDecaySmoothing)
                + (rawMagnitude * (1.0 - configuration.motion.magnitudeDecaySmoothing))
        }

        let horizontalDirection = configuration.motion.invertHorizontalFlow ? 1.0 : -1.0
        let targetVelocityX = rawMagnitude > configuration.motion.motionDeadzone
            ? (adjustedLateralAcceleration * configuration.motion.velocityMultiplier * horizontalDirection)
            : 0.0
        let verticalDirection = configuration.motion.invertVerticalFlow ? 1.0 : -1.0
        let targetVelocityY = rawMagnitude > configuration.motion.motionDeadzone
            ? ((adjustedLongitudinalAcceleration + adjustedVerticalAcceleration)
                * configuration.motion.velocityMultiplier
                * verticalDirection)
            : 0.0

        currentVelocity.dx += (targetVelocityX - currentVelocity.dx) * configuration.motion.velocityFriction
        currentVelocity.dy += (targetVelocityY - currentVelocity.dy) * configuration.motion.velocityFriction

        currentOffset.x += currentVelocity.dx
        currentOffset.y += currentVelocity.dy

        if abs(currentOffset.x) > 100_000.0 {
            currentOffset.x.formTruncatingRemainder(dividingBy: configuration.layout.dotSpacing * 1000.0)
        }

        if abs(currentOffset.y) > 100_000.0 {
            currentOffset.y.formTruncatingRemainder(dividingBy: configuration.layout.dotSpacing * 1000.0)
        }
    }
}

private final class FlowGridLayoutCacheKey: NSObject {
    private let widthKey: Int
    private let heightKey: Int
    private let dotSpacingKey: Int
    private let marginRatioKey: Int
    private let horizontalMarginRatioKey: Int
    private let verticalMarginRatioKey: Int
    private let safeZoneCornerRadiusKey: Int
    private let safeZoneFeatherWidthKey: Int
    private let orientation: InterfaceRenderOrientation
    private let cachedHash: Int

    init(
        size: CGSize,
        configuration: FlowGridConfiguration,
        orientation: InterfaceRenderOrientation
    ) {
        widthKey = flowGridCacheComponent(size.width)
        heightKey = flowGridCacheComponent(size.height)
        dotSpacingKey = flowGridCacheComponent(configuration.layout.dotSpacing)
        marginRatioKey = flowGridCacheComponent(configuration.safeZone.marginRatio)
        horizontalMarginRatioKey = flowGridCacheComponent(configuration.safeZone.horizontalMarginRatio)
        verticalMarginRatioKey = flowGridCacheComponent(configuration.safeZone.verticalMarginRatio)
        safeZoneCornerRadiusKey = flowGridCacheComponent(configuration.safeZone.cornerRadius)
        safeZoneFeatherWidthKey = flowGridCacheComponent(configuration.safeZone.featherWidth)
        self.orientation = orientation

        var hasher = Hasher()
        hasher.combine(widthKey)
        hasher.combine(heightKey)
        hasher.combine(dotSpacingKey)
        hasher.combine(marginRatioKey)
        hasher.combine(horizontalMarginRatioKey)
        hasher.combine(verticalMarginRatioKey)
        hasher.combine(safeZoneCornerRadiusKey)
        hasher.combine(safeZoneFeatherWidthKey)
        hasher.combine(orientation)
        cachedHash = hasher.finalize()
    }

    override var hash: Int {
        cachedHash
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FlowGridLayoutCacheKey else {
            return false
        }

        return widthKey == other.widthKey
            && heightKey == other.heightKey
            && dotSpacingKey == other.dotSpacingKey
            && marginRatioKey == other.marginRatioKey
            && horizontalMarginRatioKey == other.horizontalMarginRatioKey
            && verticalMarginRatioKey == other.verticalMarginRatioKey
            && safeZoneCornerRadiusKey == other.safeZoneCornerRadiusKey
            && safeZoneFeatherWidthKey == other.safeZoneFeatherWidthKey
            && orientation == other.orientation
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
    let baseHorizontalMargin = configuration.safeZone.horizontalMarginRatio > 0.0
        ? configuration.safeZone.horizontalMarginRatio
        : configuration.safeZone.marginRatio
    let baseVerticalMargin = configuration.safeZone.verticalMarginRatio > 0.0
        ? configuration.safeZone.verticalMarginRatio
        : configuration.safeZone.marginRatio

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

    let horizontalReach: CGFloat
    if point.x < safeRect.minX {
        horizontalReach = max(safeRect.minX, 1.0)
    } else if point.x > safeRect.maxX {
        horizontalReach = max(canvasSize.width - safeRect.maxX, 1.0)
    } else {
        horizontalReach = 1.0
    }

    let verticalReach: CGFloat
    if point.y < safeRect.minY {
        verticalReach = max(safeRect.minY, 1.0)
    } else if point.y > safeRect.maxY {
        verticalReach = max(canvasSize.height - safeRect.maxY, 1.0)
    } else {
        verticalReach = 1.0
    }

    let normalizedX = safeDistanceX / horizontalReach
    let normalizedY = safeDistanceY / verticalReach
    return min(max(max(normalizedX, normalizedY), 0.0), 1.0)
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

private func flowGridCacheComponent(_ value: CGFloat) -> Int {
    Int((value * 1000.0).rounded())
}

func flowDotAppearance(
    hash: Double,
    normA: Double,
    configuration: FlowGridConfiguration
) -> (alpha: Double, radius: CGFloat)? {
    var alpha = 0.0
    var radius = configuration.appearance.baseRadius

    if hash < configuration.appearance.baseDensity {
        alpha = configuration.appearance.baseOpacity + (normA * (1.0 - configuration.appearance.baseOpacity))
        radius = configuration.appearance.baseRadius + (normA * configuration.appearance.maxExtraRadius)
    } else if hash < configuration.appearance.baseDensity + (normA * configuration.appearance.extraDensityRange) {
        let fadeProgress = (normA * configuration.appearance.extraDensityRange) - (hash - configuration.appearance.baseDensity)
        alpha = min(fadeProgress * configuration.appearance.fadeMultiplier, configuration.appearance.maxAlpha)
        radius = configuration.appearance.baseRadius + (normA * configuration.appearance.maxExtraRadius)
    }

    if configuration.appearance.alphaVariation > 0.0 {
        let variationRange = configuration.appearance.alphaVariation * (0.90 + (0.70 * normA))
        let variation = 1.0 - (variationRange * 0.5) + (hash * variationRange)
        alpha *= variation
    }

    guard alpha > configuration.appearance.minimumVisibleAlpha else {
        return nil
    }

    return (alpha, radius)
}
