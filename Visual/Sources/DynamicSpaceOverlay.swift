import Metal
import MetalKit
import MotionComfortCore
import QuartzCore
import SwiftUI
import UIKit

public struct DynamicFlowOverlay: View {
    let sample: MotionSample
    let orientation: InterfaceRenderOrientation
    let speedMultiplier: Double

    public init(
        sample: MotionSample = .neutral,
        orientation: InterfaceRenderOrientation = .portrait,
        speedMultiplier: Double = 1.0
    ) {
        self.sample = sample
        self.orientation = orientation
        self.speedMultiplier = speedMultiplier
    }

    public var body: some View {
        GeometryReader { proxy in
            DynamicMetalView(
                sample: sample.rotatedForDisplay(orientation),
                speedMultiplier: speedMultiplier
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

public enum DynamicRenderPreheater {
    public static func prewarm() {
        DynamicRenderResourceCache.shared.prewarmIfNeeded()
    }

    public static func ensureReady() async {
        await DynamicRenderResourceCache.shared.ensureReady()
    }
}

private struct DynamicMetalView: UIViewRepresentable {
    typealias UIViewType = DynamicRenderView

    let sample: MotionSample
    let speedMultiplier: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DynamicRenderView {
        let view = DynamicRenderView(
            frame: .zero,
            device: DynamicRenderResourceCache.shared.preferredDevice()
        )
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 1.0 / 255.0, green: 1.0 / 255.0, blue: 5.0 / 255.0, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = UIColor(red: 1.0 / 255.0, green: 1.0 / 255.0, blue: 5.0 / 255.0, alpha: 1.0)

        do {
            let resources = try DynamicRenderResourceCache.shared.resources(
                pixelFormat: view.colorPixelFormat
            )
            view.device = resources.device
            let renderer = try DynamicMetalRenderer(mtkView: view, resources: resources)
            renderer.sample = sample
            renderer.speedMultiplier = Float(speedMultiplier)
            context.coordinator.renderer = renderer
            view.delegate = renderer
            view.clearFailure()
        } catch {
            view.showFailure(error.localizedDescription)
        }

        return view
    }

    func updateUIView(_ uiView: DynamicRenderView, context: Context) {
        uiView.updateDrawableSizeIfNeeded()
        context.coordinator.renderer?.sample = sample
        context.coordinator.renderer?.speedMultiplier = Float(speedMultiplier)
    }

    final class Coordinator {
        var renderer: DynamicMetalRenderer?
    }
}

private final class DynamicRenderView: MTKView {
    private let failureLabel = UILabel()

    override init(frame frameRect: CGRect, device: (any MTLDevice)?) {
        super.init(frame: frameRect, device: device)
        configureFailureLabel()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSizeIfNeeded()
        failureLabel.frame = bounds.insetBy(dx: 24.0, dy: 24.0)
    }

    func updateDrawableSizeIfNeeded() {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let nextSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if nextSize.width > 0.0, nextSize.height > 0.0, drawableSize != nextSize {
            drawableSize = nextSize
        }
    }

    func showFailure(_ message: String) {
        failureLabel.text = message
        failureLabel.isHidden = false
    }

    func clearFailure() {
        failureLabel.isHidden = true
    }

    private func configureFailureLabel() {
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 0
        failureLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        failureLabel.font = .systemFont(ofSize: 16.0, weight: .semibold)
        failureLabel.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        failureLabel.layer.cornerRadius = 18.0
        failureLabel.layer.masksToBounds = true
        failureLabel.isHidden = true
        addSubview(failureLabel)
    }
}

private struct DynamicSpaceConfiguration {
    let particleCount = 800
    let baseParticleCount = 400
    let dustCount = 15000
    let minZ: Float = 0.2
    let maxZ: Float = 5.0
    let idleSpeed: Float = 0.005
    let camSensX: Float = 0.060
    let camSensY: Float = 0.060
    let nebulaCloudCount = 12
    let nebulaAtlasColumns = 4
    let nebulaAtlasRows = 3
    let nebulaBaseAlpha: Float = 0.54
    let sensorSmoothing: Float = 0.42
    let velocityFriction: Float = 0.11
    let brightnessDivisor: Float = 1.2
}

private struct DynamicParticle {
    var x: Float
    var y: Float
    var z: Float
    var size: Float
    var colorIndex: Int32
    var isSharp: Bool
    var baseAlpha: Float
    var phase: Float
    var currentAlpha: Float
    var currentScale: Float
    var isReserve: Bool
}

private struct DynamicDust {
    var x: Float
    var y: Float
    var z: Float
    var baseSize: Float
    var baseAlpha: Float
    var currentAlpha: Float
}

private struct DynamicNebula {
    var colorIndex: Int32
    var atlasIndex: Int32
    var baseSize: Float
    var brightnessScale: Float
    var anchorX: Float
    var anchorY: Float
    var anchorZ: Float
    var driftPhaseX: Float
    var driftPhaseY: Float
    var driftSpeedX: Float
    var driftSpeedY: Float
    var alphaFreq: Float
    var wanderRadiusX: Float
    var wanderRadiusY: Float
    var rotationPhase: Float
    var rotationSpeed: Float
}

private struct DynamicSpaceSceneState {
    var particles: [DynamicParticle] = []
    var dusts: [DynamicDust] = []
    var nebulas: [DynamicNebula] = []
    var filteredAccel = SIMD2<Float>(repeating: 0.0)
    var motionEnvelope: Float = 0.0
    var currentVelocity = SIMD2<Float>(repeating: 0.0)
    var camX: Float = 0.0
    var camY: Float = 0.0
    var currentWarpSpeed: Float
    var universeSpreadX: Float = 0.0
    var universeSpreadY: Float = 0.0
    var timeOffset: Float

    init(config: DynamicSpaceConfiguration) {
        currentWarpSpeed = config.idleSpeed
        timeOffset = Float.random(in: 0.0...1000.0)
    }
}

private struct DynamicSpriteVertex {
    var positionAndSize: SIMD4<Float> = .zero
    var colorAndSoftness: SIMD4<Float> = .zero
    var rotationAndMisc: SIMD4<Float> = .zero
}

private struct DynamicViewportUniforms {
    var viewportSize: SIMD2<Float>
    var atlasGrid: SIMD2<Float>
}

private enum DynamicRendererSetupError: Error {
    case missingDevice
    case missingCommandQueue
    case missingLibrary
    case invalidShaderFunctions
    case libraryLoad(String)
    case pipelineCreation(String)
    case textureCreation(String)
    case bufferCreation
}

extension DynamicRendererSetupError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingDevice:
            return "Dynamic renderer failed: Metal device unavailable"
        case .missingCommandQueue:
            return "Dynamic renderer failed: command queue unavailable"
        case .missingLibrary:
            return "Dynamic renderer failed: default.metallib missing"
        case .invalidShaderFunctions:
            return "Dynamic renderer failed: shader functions missing"
        case let .libraryLoad(reason):
            return "Dynamic renderer failed: metallib load error\n\(reason)"
        case let .pipelineCreation(reason):
            return "Dynamic renderer failed: pipeline creation error\n\(reason)"
        case let .textureCreation(reason):
            return "Dynamic renderer failed: texture creation error\n\(reason)"
        case .bufferCreation:
            return "Dynamic renderer failed: buffer allocation error"
        }
    }
}

private struct DynamicRenderResources {
    let device: MTLDevice
    let pixelFormat: MTLPixelFormat
    let library: MTLLibrary
    let additivePipeline: MTLRenderPipelineState
    let screenPipeline: MTLRenderPipelineState
    let blurTexture: MTLTexture
    let sharpTexture: MTLTexture
    let cloudAtlasTexture: MTLTexture
    let dustTexture: MTLTexture

    static func make(pixelFormat: MTLPixelFormat) throws -> DynamicRenderResources {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw DynamicRendererSetupError.missingDevice
        }

        let library = try DynamicMetalRenderer.makeLibrary(device: device)
        let additivePipeline = try DynamicMetalRenderer.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            fragmentBlend: .additive
        )
        let screenPipeline = try DynamicMetalRenderer.makePipeline(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            fragmentBlend: .screen,
            fragmentName: "dynamicNebulaFragment"
        )
        let blurTexture = try DynamicMetalRenderer.makeTexture(
            device: device,
            bitmap: DynamicTextureFactory.makeBlurBitmap(size: 128)
        )
        let sharpTexture = try DynamicMetalRenderer.makeTexture(
            device: device,
            bitmap: DynamicTextureFactory.makeSharpBitmap(size: 32)
        )
        let cloudAtlasTexture = try DynamicMetalRenderer.makeTexture(
            device: device,
            bitmap: DynamicTextureFactory.makeCloudAtlasBitmap(
                tileSize: 640,
                nominalTileSize: 320,
                columns: DynamicSpaceConfiguration().nebulaAtlasColumns,
                rows: DynamicSpaceConfiguration().nebulaAtlasRows
            )
        )
        let dustTexture = try DynamicMetalRenderer.makeTexture(
            device: device,
            bitmap: DynamicTextureFactory.makeDustBitmap(size: 8)
        )

        return DynamicRenderResources(
            device: device,
            pixelFormat: pixelFormat,
            library: library,
            additivePipeline: additivePipeline,
            screenPipeline: screenPipeline,
            blurTexture: blurTexture,
            sharpTexture: sharpTexture,
            cloudAtlasTexture: cloudAtlasTexture,
            dustTexture: dustTexture
        )
    }
}

private final class DynamicRenderResourceCache: @unchecked Sendable {
    static let shared = DynamicRenderResourceCache()

    private let lock = NSLock()
    private var cachedResources: DynamicRenderResources?
    private var isPrewarming = false

    private init() {}

    func preferredDevice() -> MTLDevice? {
        lock.lock()
        let device = cachedResources?.device
        lock.unlock()
        return device ?? MTLCreateSystemDefaultDevice()
    }

    func prewarmIfNeeded(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        lock.lock()
        let hasMatchingResources = cachedResources?.pixelFormat == pixelFormat
        if hasMatchingResources || isPrewarming {
            lock.unlock()
            return
        }
        isPrewarming = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            let preparedResources = try? DynamicRenderResources.make(pixelFormat: pixelFormat)

            self.lock.lock()
            if let preparedResources {
                self.cachedResources = preparedResources
            }
            self.isPrewarming = false
            self.lock.unlock()
        }
    }

    func ensureReady(pixelFormat: MTLPixelFormat = .bgra8Unorm) async {
        if hasCachedResources(pixelFormat: pixelFormat) {
            return
        }

        await Task.detached(priority: .userInitiated) {
            _ = try? self.resources(pixelFormat: pixelFormat)
        }.value
    }

    private func hasCachedResources(pixelFormat: MTLPixelFormat) -> Bool {
        lock.lock()
        let hasMatchingResources = cachedResources?.pixelFormat == pixelFormat
        lock.unlock()
        return hasMatchingResources
    }

    func resources(pixelFormat: MTLPixelFormat) throws -> DynamicRenderResources {
        lock.lock()
        if let cachedResources, cachedResources.pixelFormat == pixelFormat {
            lock.unlock()
            return cachedResources
        }
        lock.unlock()

        let preparedResources = try DynamicRenderResources.make(pixelFormat: pixelFormat)

        lock.lock()
        if cachedResources == nil || cachedResources?.pixelFormat != pixelFormat {
            cachedResources = preparedResources
        }
        let resolvedResources = cachedResources ?? preparedResources
        isPrewarming = false
        lock.unlock()
        return resolvedResources
    }
}

@MainActor
private final class DynamicMetalRenderer: NSObject, MTKViewDelegate {
    var sample: MotionSample = .neutral
    var speedMultiplier: Float = 1.0

    private let config = DynamicSpaceConfiguration()
    private let commandQueue: MTLCommandQueue
    private let additivePipeline: MTLRenderPipelineState
    private let screenPipeline: MTLRenderPipelineState

    private let blurTexture: MTLTexture
    private let sharpTexture: MTLTexture
    private let cloudAtlasTexture: MTLTexture
    private let dustTexture: MTLTexture

    private var state: DynamicSpaceSceneState
    private var lastUpdateTime: CFTimeInterval?
    private var drawableSize: CGSize = .zero

    private var nebulaVertices: [DynamicSpriteVertex]
    private var dustVertices: [DynamicSpriteVertex]
    private var haloVertices: [DynamicSpriteVertex]
    private var sharpVertices: [DynamicSpriteVertex]

    private let nebulaBuffer: MTLBuffer
    private let dustBuffer: MTLBuffer
    private let haloBuffer: MTLBuffer
    private let sharpBuffer: MTLBuffer

    private var nebulaCount = 0
    private var dustCount = 0
    private var haloCount = 0
    private var sharpCount = 0

    init(mtkView: MTKView, resources: DynamicRenderResources) throws {
        let device = resources.device
        mtkView.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw DynamicRendererSetupError.missingCommandQueue
        }

        self.commandQueue = commandQueue
        self.additivePipeline = resources.additivePipeline
        self.screenPipeline = resources.screenPipeline
        self.blurTexture = resources.blurTexture
        self.sharpTexture = resources.sharpTexture
        self.cloudAtlasTexture = resources.cloudAtlasTexture
        self.dustTexture = resources.dustTexture
        self.state = DynamicSpaceSceneState(config: config)

        let nebulaStride = MemoryLayout<DynamicSpriteVertex>.stride * config.nebulaCloudCount
        let dustStride = MemoryLayout<DynamicSpriteVertex>.stride * config.dustCount
        let particleStride = MemoryLayout<DynamicSpriteVertex>.stride * config.particleCount

        guard
            let nebulaBuffer = device.makeBuffer(length: nebulaStride, options: [.storageModeShared]),
            let dustBuffer = device.makeBuffer(length: dustStride, options: [.storageModeShared]),
            let haloBuffer = device.makeBuffer(length: particleStride, options: [.storageModeShared]),
            let sharpBuffer = device.makeBuffer(length: particleStride, options: [.storageModeShared])
        else {
            throw DynamicRendererSetupError.bufferCreation
        }

        self.nebulaBuffer = nebulaBuffer
        self.dustBuffer = dustBuffer
        self.haloBuffer = haloBuffer
        self.sharpBuffer = sharpBuffer

        self.nebulaVertices = Array(repeating: DynamicSpriteVertex(), count: config.nebulaCloudCount)
        self.dustVertices = Array(repeating: DynamicSpriteVertex(), count: config.dustCount)
        self.haloVertices = Array(repeating: DynamicSpriteVertex(), count: config.particleCount)
        self.sharpVertices = Array(repeating: DynamicSpriteVertex(), count: config.particleCount)

        super.init()

        drawableSize = mtkView.drawableSize
        rebuildScene(for: mtkView.drawableSize)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
        rebuildScene(for: size)
    }

    func draw(in view: MTKView) {
        guard
            drawableSize.width > 0.0,
            drawableSize.height > 0.0,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime: Float
        if let lastUpdateTime {
            deltaTime = Float(min(max(now - lastUpdateTime, 1.0 / 120.0), 1.0 / 30.0))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastUpdateTime = now

        updateScene(deltaTime: deltaTime, timeMs: Float(now * 1000.0) + state.timeOffset)

        var uniforms = DynamicViewportUniforms(
            viewportSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
            atlasGrid: SIMD2(Float(config.nebulaAtlasColumns), Float(config.nebulaAtlasRows))
        )

        drawSprites(
            encoder: encoder,
            pipeline: screenPipeline,
            buffer: nebulaBuffer,
            count: nebulaCount,
            texture: cloudAtlasTexture,
            uniforms: &uniforms
        )
        drawSprites(
            encoder: encoder,
            pipeline: additivePipeline,
            buffer: dustBuffer,
            count: dustCount,
            texture: sharpTexture,
            uniforms: &uniforms
        )
        drawSprites(
            encoder: encoder,
            pipeline: additivePipeline,
            buffer: haloBuffer,
            count: haloCount,
            texture: blurTexture,
            uniforms: &uniforms
        )
        drawSprites(
            encoder: encoder,
            pipeline: additivePipeline,
            buffer: sharpBuffer,
            count: sharpCount,
            texture: sharpTexture,
            uniforms: &uniforms
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func rebuildScene(for size: CGSize) {
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }

        state.camX = 0.0
        state.camY = 0.0
        state.filteredAccel = .zero
        state.motionEnvelope = 0.0
        state.currentVelocity = .zero
        state.currentWarpSpeed = config.idleSpeed
        state.universeSpreadX = config.maxZ * 2.8
        state.universeSpreadY = state.universeSpreadX * max(1.0, Float(size.height / size.width))

        state.particles.removeAll(keepingCapacity: true)
        state.dusts.removeAll(keepingCapacity: true)
        state.nebulas.removeAll(keepingCapacity: true)

        for _ in 0..<config.particleCount {
            let index = state.particles.count
            let isSharp = Float.random(in: 0.0...1.0) < 0.80
            let particle = DynamicParticle(
                x: 0.0,
                y: 0.0,
                z: 0.0,
                size: isSharp ? Float.random(in: 12.0...24.0) : Float.random(in: 40.0...80.0),
                colorIndex: Int32.random(in: 0..<Int32(DynamicPalette.colors.count)),
                isSharp: isSharp,
                baseAlpha: isSharp ? Float.random(in: 0.48...0.82) : Float.random(in: 0.32...0.58),
                phase: Float.random(in: 0.0...(Float.pi * 2.0)),
                currentAlpha: 0.0,
                currentScale: 1.0,
                isReserve: index >= config.baseParticleCount
            )
            state.particles.append(spawnedParticle(from: particle, randomDepth: true))
        }

        for _ in 0..<config.dustCount {
            let dust = DynamicDust(
                x: 0.0,
                y: 0.0,
                z: 0.0,
                baseSize: Float.random(in: 1.4...4.0),
                baseAlpha: Float.random(in: 0.35...0.85),
                currentAlpha: 0.0
            )
            state.dusts.append(spawnedDust(from: dust, randomDepth: true))
        }

        let atlasCount = max(config.nebulaAtlasColumns * config.nebulaAtlasRows, 1)
        let uniqueAtlasIndices = Array(0..<atlasCount).shuffled()

        for index in 0..<config.nebulaCloudCount {
            state.nebulas.append(
                DynamicNebula(
                    colorIndex: Int32.random(in: 0..<Int32(DynamicPalette.colors.count)),
                    atlasIndex: Int32(uniqueAtlasIndices[index % uniqueAtlasIndices.count]),
                    baseSize: Float(min(size.width, size.height)) * Float.random(in: 3.10...5.80),
                    brightnessScale: Float.random(in: 0.66...1.00),
                    anchorX: Float.random(in: -0.14...0.14),
                    anchorY: Float.random(in: -0.14...0.14),
                    anchorZ: Float.random(in: config.minZ + 0.9...config.maxZ - 1.1),
                    driftPhaseX: Float.random(in: 0.0...(Float.pi * 2.0)),
                    driftPhaseY: Float.random(in: 0.0...(Float.pi * 2.0)),
                    driftSpeedX: Float.random(in: 0.00016...0.00046),
                    driftSpeedY: Float.random(in: 0.00016...0.00046),
                    alphaFreq: Float.random(in: 0.00025...0.00075),
                    wanderRadiusX: Float.random(in: 0.08...0.30),
                    wanderRadiusY: Float.random(in: 0.08...0.30),
                    rotationPhase: Float.random(in: 0.0...(Float.pi * 2.0)),
                    rotationSpeed: Float.random(in: 0.0001...0.00015) * (Bool.random() ? 1.0 : -1.0)
                )
            )
        }
    }

    private func updateScene(deltaTime: Float, timeMs: Float) {
        let frameScale = deltaTime * 60.0
        let accel = SIMD2<Float>(
            Float(sample.lateralAcceleration),
            Float(sample.longitudinalAcceleration)
        )
        state.filteredAccel = (accel * config.sensorSmoothing) + (state.filteredAccel * (1.0 - config.sensorSmoothing))

        state.currentVelocity.x += ((-state.filteredAccel.x * 3.0) - state.currentVelocity.x) * config.velocityFriction
        state.currentVelocity.y += ((-state.filteredAccel.y * 3.0) - state.currentVelocity.y) * config.velocityFriction

        state.camX += state.currentVelocity.x * config.camSensX * frameScale
        state.camY += state.currentVelocity.y * config.camSensY * frameScale

        let accelMagnitude = simd_length(state.filteredAccel)
        let rawIntensity = min(accelMagnitude / config.brightnessDivisor, 1.0)
        let targetIntensity = pow(rawIntensity, 0.82)
        let attackRate: Float = 0.24
        let releaseRate: Float = 0.045
        if targetIntensity > state.motionEnvelope {
            state.motionEnvelope += (targetIntensity - state.motionEnvelope) * attackRate * frameScale
        } else {
            state.motionEnvelope += (targetIntensity - state.motionEnvelope) * releaseRate * frameScale
        }
        let reserveRaw = max((state.motionEnvelope - 0.18) / 0.82, 0.0)
        let reserveIntensity = reserveRaw * reserveRaw * (3.0 - 2.0 * reserveRaw)
        let activeBrightness = state.motionEnvelope * 1.05
        let activeHaloScale: Float = 1.0 + (state.motionEnvelope * 0.85)

        let clampedMultiplier = min(max(speedMultiplier, 0.0), 6.0)
        let targetWarpSpeed = config.idleSpeed * clampedMultiplier
        state.currentWarpSpeed += (targetWarpSpeed - state.currentWarpSpeed) * 0.05 * frameScale

        buildNebulas(timeMs: timeMs)
        buildDust(activeBrightness: activeBrightness, frameScale: frameScale)
        buildParticles(
            activeBrightness: activeBrightness,
            activeHaloScale: activeHaloScale,
            accelIntensity: state.motionEnvelope,
            reserveIntensity: reserveIntensity,
            frameScale: frameScale
        )

        upload(nebulaVertices, count: nebulaCount, to: nebulaBuffer)
        upload(dustVertices, count: dustCount, to: dustBuffer)
        upload(haloVertices, count: haloCount, to: haloBuffer)
        upload(sharpVertices, count: sharpCount, to: sharpBuffer)
    }

    private func buildNebulas(timeMs: Float) {
        let centerX = Float(drawableSize.width) * 0.5
        let centerY = Float(drawableSize.height) * 0.5
        let clusterRadiusX = Float(drawableSize.width) * 0.35
        let clusterRadiusY = Float(drawableSize.height) * 0.30
        nebulaCount = 0

        for nebula in state.nebulas {
            let lissajousX = sin((timeMs * nebula.driftSpeedX) + nebula.driftPhaseX)
            let lissajousY = sin((timeMs * nebula.driftSpeedY * 1.37) + nebula.driftPhaseY)
            let breathAlpha = sin(timeMs * nebula.alphaFreq) * 0.3 + 0.7
            let alpha = min(config.nebulaBaseAlpha * breathAlpha * nebula.brightnessScale, 1.0)
            let color = DynamicPalette.colors[Int(nebula.colorIndex)]
            let relX = (nebula.anchorX + lissajousX * nebula.wanderRadiusX) * clusterRadiusX
            let relY = (nebula.anchorY + lissajousY * nebula.wanderRadiusY) * clusterRadiusY
            let scale = 1.0 / max(nebula.anchorZ, config.minZ)
            let screenX = centerX + relX
            let screenY = centerY + relY
            let renderSize = nebula.baseSize * (1.52 + scale * 1.92)
            let rotation = nebula.rotationPhase + timeMs * nebula.rotationSpeed
            let isVisible = screenX > -renderSize && screenX < Float(drawableSize.width) + renderSize && screenY > -renderSize && screenY < Float(drawableSize.height) + renderSize
            guard isVisible else {
                continue
            }
            nebulaVertices[nebulaCount] = DynamicSpriteVertex(
                positionAndSize: SIMD4(screenX, screenY, renderSize, alpha),
                colorAndSoftness: SIMD4(color.x, color.y, color.z, Float(nebula.atlasIndex)),
                rotationAndMisc: SIMD4(rotation, 0.0, 0.0, 0.0)
            )
            nebulaCount += 1
        }
    }

    private func buildDust(activeBrightness: Float, frameScale: Float) {
        let centerX = Float(drawableSize.width) * 0.5
        let centerY = Float(drawableSize.height) * 0.5
        let halfX = state.universeSpreadX * 0.5
        let halfY = state.universeSpreadY * 0.5
        dustCount = 0

        for index in state.dusts.indices {
            state.dusts[index].z -= state.currentWarpSpeed * frameScale

            var relX = state.dusts[index].x - state.camX
            var relY = state.dusts[index].y - state.camY
            var hasWrapped = false

            if relX > halfX {
                state.dusts[index].x -= state.universeSpreadX
                hasWrapped = true
            } else if relX < -halfX {
                state.dusts[index].x += state.universeSpreadX
                hasWrapped = true
            }

            if relY > halfY {
                state.dusts[index].y -= state.universeSpreadY
                hasWrapped = true
            } else if relY < -halfY {
                state.dusts[index].y += state.universeSpreadY
                hasWrapped = true
            }

            if hasWrapped {
                relX = state.dusts[index].x - state.camX
                relY = state.dusts[index].y - state.camY
                state.dusts[index].currentAlpha = 0.0
            }

            if state.dusts[index].z < config.minZ {
                state.dusts[index] = spawnedDust(from: state.dusts[index], randomDepth: false)
                relX = state.dusts[index].x - state.camX
                relY = state.dusts[index].y - state.camY
            }

            let scale = 1.0 / state.dusts[index].z
            let screenX = centerX + relX * (Float(drawableSize.width) * 0.5) * scale
            let screenY = centerY + relY * (Float(drawableSize.width) * 0.5) * scale
            let renderSize = max(state.dusts[index].baseSize * scale * 1.35, 1.8)
            let isVisible = screenX > 0.0 && screenX < Float(drawableSize.width) && screenY > 0.0 && screenY < Float(drawableSize.height)
            let depthAlpha = state.dusts[index].z > config.maxZ - 1.2 ? (config.maxZ - state.dusts[index].z) / 1.2 : 1.0
            let targetAlpha = min(state.dusts[index].baseAlpha + 0.28 + activeBrightness * 0.85, 0.98) * depthAlpha
            let dustAlphaRate: Float = targetAlpha > state.dusts[index].currentAlpha ? 0.2 : 0.08
            state.dusts[index].currentAlpha += (targetAlpha - state.dusts[index].currentAlpha) * dustAlphaRate * frameScale

            if state.dusts[index].currentAlpha > 0.01 && isVisible {
                let color = SIMD3<Float>(repeating: 1.0)
                dustVertices[dustCount] = DynamicSpriteVertex(
                    positionAndSize: SIMD4(screenX, screenY, renderSize, min(state.dusts[index].currentAlpha, 1.0)),
                    colorAndSoftness: SIMD4(color.x, color.y, color.z, 1.0)
                )
                dustCount += 1
            }
        }

    }

    private func buildParticles(
        activeBrightness: Float,
        activeHaloScale: Float,
        accelIntensity: Float,
        reserveIntensity: Float,
        frameScale: Float
    ) {
        let centerX = Float(drawableSize.width) * 0.5
        let centerY = Float(drawableSize.height) * 0.5
        let halfX = state.universeSpreadX * 0.5
        let halfY = state.universeSpreadY * 0.5
        haloCount = 0
        sharpCount = 0

        for index in state.particles.indices {
            state.particles[index].z -= state.currentWarpSpeed * frameScale

            var relX = state.particles[index].x - state.camX
            var relY = state.particles[index].y - state.camY
            var hasWrapped = false

            if relX > halfX {
                state.particles[index].x -= state.universeSpreadX
                hasWrapped = true
            } else if relX < -halfX {
                state.particles[index].x += state.universeSpreadX
                hasWrapped = true
            }

            if relY > halfY {
                state.particles[index].y -= state.universeSpreadY
                hasWrapped = true
            } else if relY < -halfY {
                state.particles[index].y += state.universeSpreadY
                hasWrapped = true
            }

            if hasWrapped {
                relX = state.particles[index].x - state.camX
                relY = state.particles[index].y - state.camY
                state.particles[index].currentAlpha = 0.0
            }

            if state.particles[index].z < config.minZ {
                state.particles[index] = spawnedParticle(from: state.particles[index], randomDepth: false)
                relX = state.particles[index].x - state.camX
                relY = state.particles[index].y - state.camY
            }

            let scale = 1.0 / state.particles[index].z
            let screenX = centerX + relX * (Float(drawableSize.width) * 0.5) * scale
            let screenY = centerY + relY * (Float(drawableSize.width) * 0.5) * scale
            let reserveScaleBoost: Float = state.particles[index].isReserve ? (1.0 + reserveIntensity * 0.28) : 1.0
            let targetScale: Float = (state.particles[index].isSharp ? (1.0 + accelIntensity * 0.22) : activeHaloScale) * reserveScaleBoost
            let scaleRate: Float = targetScale > state.particles[index].currentScale ? 0.15 : 0.06
            state.particles[index].currentScale += (targetScale - state.particles[index].currentScale) * scaleRate * frameScale
            let sizeBoost: Float = state.particles[index].isSharp ? 2.18 : 2.00
            let renderSize = max(state.particles[index].size * scale * state.particles[index].currentScale * sizeBoost, 2.2)
            let isVisible = screenX > -renderSize && screenX < Float(drawableSize.width) + renderSize && screenY > -renderSize && screenY < Float(drawableSize.height) + renderSize

            state.particles[index].phase += 0.03 * frameScale
            let breath = sin(state.particles[index].phase) * 0.15 + 0.85
            let depthAlpha = state.particles[index].z > config.maxZ - 1.2 ? (config.maxZ - state.particles[index].z) / 1.2 : 1.0
            let alphaFloor: Float = state.particles[index].isSharp ? 0.44 : 0.52
            let alphaGain: Float = state.particles[index].isSharp ? 1.45 : 1.70
            let reserveAlphaBoost: Float = state.particles[index].isReserve ? reserveIntensity : 1.0
            let targetAlpha = min(state.particles[index].baseAlpha + alphaFloor + activeBrightness * alphaGain, 1.0) * breath * depthAlpha * reserveAlphaBoost
            let particleAlphaRate: Float = targetAlpha > state.particles[index].currentAlpha ? 0.15 : 0.055
            state.particles[index].currentAlpha += (targetAlpha - state.particles[index].currentAlpha) * particleAlphaRate * frameScale

            if state.particles[index].currentAlpha > 0.001 && isVisible {
                let color = DynamicPalette.colors[Int(state.particles[index].colorIndex)]
                let sprite = DynamicSpriteVertex(
                    positionAndSize: SIMD4(screenX, screenY, renderSize, min(state.particles[index].currentAlpha, 1.0)),
                    colorAndSoftness: SIMD4(color.x, color.y, color.z, state.particles[index].isSharp ? 0.5 : 1.0)
                )
                if state.particles[index].isSharp {
                    sharpVertices[sharpCount] = sprite
                    sharpCount += 1
                } else {
                    haloVertices[haloCount] = sprite
                    haloCount += 1
                }
            }
        }
    }

    private func spawnedParticle(from particle: DynamicParticle, randomDepth: Bool) -> DynamicParticle {
        var next = particle
        next.z = randomDepth ? Float.random(in: config.minZ...config.maxZ) : config.maxZ
        next.x = state.camX + Float.random(in: -0.5...0.5) * state.universeSpreadX
        next.y = state.camY + Float.random(in: -0.5...0.5) * state.universeSpreadY
        next.currentAlpha = 0.0
        next.currentScale = 1.0
        return next
    }

    private func spawnedDust(from dust: DynamicDust, randomDepth: Bool) -> DynamicDust {
        var next = dust
        next.z = randomDepth ? Float.random(in: config.minZ...config.maxZ) : config.maxZ
        if !randomDepth {
            next.currentAlpha = 0.0
            return next
        }

        next.x = Float.random(in: -0.5...0.5) * state.universeSpreadX
        next.y = Float.random(in: -0.5...0.5) * state.universeSpreadY
        next.currentAlpha = 0.0
        return next
    }

    private func upload(_ vertices: [DynamicSpriteVertex], count: Int, to buffer: MTLBuffer) {
        guard count > 0 else { return }
        vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            memcpy(buffer.contents(), baseAddress, count * MemoryLayout<DynamicSpriteVertex>.stride)
        }
    }

    private func drawSprites(
        encoder: MTLRenderCommandEncoder,
        pipeline: MTLRenderPipelineState,
        buffer: MTLBuffer,
        count: Int,
        texture: MTLTexture,
        uniforms: inout DynamicViewportUniforms
    ) {
        guard count > 0 else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DynamicViewportUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DynamicViewportUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
    }

    nonisolated fileprivate static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        let bundle = Bundle(for: DynamicBundleSentinel.self)
        if let url = bundle.url(forResource: "default", withExtension: "metallib") {
            do {
                let library = try device.makeLibrary(URL: url)
                guard
                    library.makeFunction(name: "dynamicSpriteVertex") != nil,
                    library.makeFunction(name: "dynamicSpriteFragment") != nil,
                    library.makeFunction(name: "dynamicNebulaFragment") != nil
                else {
                    throw DynamicRendererSetupError.invalidShaderFunctions
                }
                return library
            } catch let error as DynamicRendererSetupError {
                throw error
            } catch {
                throw DynamicRendererSetupError.libraryLoad(error.localizedDescription)
            }
        }

        if let fallback = device.makeDefaultLibrary() {
            guard
                fallback.makeFunction(name: "dynamicSpriteVertex") != nil,
                fallback.makeFunction(name: "dynamicSpriteFragment") != nil,
                fallback.makeFunction(name: "dynamicNebulaFragment") != nil
            else {
                throw DynamicRendererSetupError.invalidShaderFunctions
            }
            return fallback
        }

        throw DynamicRendererSetupError.missingLibrary
    }

    nonisolated fileprivate static func makeTexture(device: MTLDevice, bitmap: DynamicTextureBitmap) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: bitmap.width,
            height: bitmap.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DynamicRendererSetupError.textureCreation("MTLTexture allocation failed")
        }

        bitmap.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            texture.replace(
                region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bitmap.bytesPerRow
            )
        }

        return texture
    }

    nonisolated fileprivate static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        fragmentBlend: DynamicBlendMode,
        fragmentName: String = "dynamicSpriteFragment"
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "dynamicSpriteVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragmentName)
        descriptor.inputPrimitiveTopology = .point
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add

        switch fragmentBlend {
        case .additive:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        case .screen:
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceColor
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

private enum DynamicBlendMode {
    case additive
    case screen
}

private enum DynamicPalette {
    static let colors: [SIMD3<Float>] = [
        SIMD3(0.0 / 255.0, 242.0 / 255.0, 254.0 / 255.0),
        SIMD3(112.0 / 255.0, 0.0 / 255.0, 255.0 / 255.0),
        SIMD3(255.0 / 255.0, 42.0 / 255.0, 133.0 / 255.0),
        SIMD3(0.0 / 255.0, 255.0 / 255.0, 140.0 / 255.0),
        SIMD3(255.0 / 255.0, 170.0 / 255.0, 0.0 / 255.0),
        SIMD3(100.0 / 255.0, 220.0 / 255.0, 255.0 / 255.0)
    ]
}

private enum DynamicTextureFactory {
    static func makeBlurBitmap(size: Int) -> DynamicTextureBitmap {
        makeBitmap(size: size) { context, size in
            let colors = [
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 0.5).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.2, 0.6, 1.0]
            let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.5)
            let radius = CGFloat(size) * 0.5
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        }
    }

    static func makeSharpBitmap(size: Int) -> DynamicTextureBitmap {
        makeBitmap(size: size) { context, size in
            let colors = [
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.5)
            let radius = CGFloat(size) * 0.5
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)!
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        }
    }

    static func makeDustBitmap(size: Int) -> DynamicTextureBitmap {
        makeBitmap(size: size) { context, size in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0.0, y: 0.0, width: CGFloat(size), height: CGFloat(size)))
        }
    }

    static func makeCloudAtlasBitmap(
        tileSize: Int,
        nominalTileSize: Int,
        columns: Int,
        rows: Int
    ) -> DynamicTextureBitmap {
        guard columns > 0, rows > 0 else {
            return DynamicTextureBitmap(width: 0, height: 0, bytesPerRow: 0, data: [])
        }
        let width = tileSize * columns
        let height = tileSize * rows
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let tileCount = columns * rows
        let tiles = (0..<tileCount).map { index in
            makeCloudTileBitmap(
                tileSize: tileSize,
                nominalTileSize: nominalTileSize,
                safeInsetRatio: 0.18,
                tileIndex: index
            )
        }
        var atlasData = [UInt8](repeating: 0, count: height * bytesPerRow)

        atlasData.withUnsafeMutableBytes { atlasBuffer in
            for index in 0..<tiles.count {
                let tile = tiles[index]
                let row = index / columns
                let column = index % columns
                let destinationX = column * tileSize
                let destinationY = row * tileSize

                tile.data.withUnsafeBytes { tileBuffer in
                    for y in 0..<tile.height {
                        let destinationOffset = (destinationY + y) * bytesPerRow + destinationX * bytesPerPixel
                        let sourceOffset = y * tile.bytesPerRow
                        atlasBuffer.baseAddress!.advanced(by: destinationOffset)
                            .copyMemory(from: tileBuffer.baseAddress!.advanced(by: sourceOffset), byteCount: tile.bytesPerRow)
                    }
                }
            }
        }

        return DynamicTextureBitmap(width: width, height: height, bytesPerRow: bytesPerRow, data: atlasData)
    }

    private static func makeCloudTileBitmap(
        tileSize: Int,
        nominalTileSize: Int,
        safeInsetRatio: CGFloat,
        tileIndex: Int
    ) -> DynamicTextureBitmap {
        let bitmap = makeBitmap(size: tileSize) { context, size in
            context.interpolationQuality = .high
            context.setAllowsAntialiasing(true)
            let layout = makeCloudTileLayout(
                canvasSize: size,
                nominalTileSize: nominalTileSize,
                safeInsetRatio: safeInsetRatio
            )
            drawCloudTile(in: context, layout: layout, tileIndex: tileIndex)
        }
        return applyCloudTileBoundaryFade(bitmap, fadeWidthRatio: 0.14)
    }

    private static func makeCloudTileLayout(
        canvasSize: Int,
        nominalTileSize: Int,
        safeInsetRatio: CGFloat
    ) -> CloudTileLayout {
        let canvasSide = CGFloat(canvasSize)
        let canvasRect = CGRect(x: 0.0, y: 0.0, width: canvasSide, height: canvasSide)
        let nominalSide = CGFloat(nominalTileSize)
        let safeInset = nominalSide * max(0.0, min(safeInsetRatio, 0.45))
        let contentSide = max(nominalSide - safeInset * 2.0, nominalSide * 0.10)
        let contentRect = CGRect(
            x: canvasRect.midX - contentSide * 0.5,
            y: canvasRect.midY - contentSide * 0.5,
            width: contentSide,
            height: contentSide
        )
        return CloudTileLayout(canvasRect: canvasRect, safeInset: safeInset, contentRect: contentRect)
    }

    private static func drawCloudTile(in cg: CGContext, layout: CloudTileLayout, tileIndex: Int) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        cg.setBlendMode(.plusLighter)
        let contentRect = layout.contentRect
        let innerCenter = CGPoint(x: contentRect.midX, y: contentRect.midY)

        let variantOffsets: [CGPoint] = [
            CGPoint(x: -0.16, y: -0.12),
            CGPoint(x: 0.18, y: -0.10),
            CGPoint(x: -0.10, y: 0.16),
            CGPoint(x: 0.12, y: 0.18),
            CGPoint(x: -0.18, y: 0.00),
            CGPoint(x: 0.20, y: 0.02),
            CGPoint(x: 0.00, y: -0.18),
            CGPoint(x: 0.02, y: 0.20),
            CGPoint(x: -0.22, y: -0.02),
            CGPoint(x: 0.22, y: 0.08),
            CGPoint(x: -0.06, y: -0.22),
            CGPoint(x: 0.08, y: 0.24)
        ]
        let variantIndex = tileIndex % variantOffsets.count
        let variantAngleBias = CGFloat(variantIndex) * (.pi / 6.0)
        let variantBlobRanges: [(Int, Int)] = [
            (10, 13), (12, 16), (9, 12), (13, 17),
            (11, 15), (8, 11), (12, 14), (14, 18),
            (9, 13), (15, 19), (10, 12), (13, 16)
        ]
        let variantFilamentRanges: [(Int, Int)] = [
            (5, 7), (6, 9), (7, 10), (4, 6),
            (8, 10), (5, 8), (6, 8), (7, 10),
            (4, 7), (8, 11), (5, 7), (6, 9)
        ]
        let variantFlowFactors: [CGFloat] = [
            1.45, 1.69, 1.93, 1.57,
            1.81, 1.33, 1.72, 2.04,
            1.24, 2.18, 1.52, 1.88
        ]
        let variantDarkLaneFlags: [Bool] = [
            true, false, true, false,
            true, true, false, true,
            false, true, false, true
        ]
        let baseAlpha = CGFloat.random(in: 0.32...0.58)
        let coreRadius = contentRect.width * CGFloat.random(in: 0.58...0.98)
        let variantOffset = variantOffsets[variantIndex]
        let coreOffset = CGPoint(
            x: (variantOffset.x + CGFloat.random(in: -0.05...0.05)) * contentRect.width,
            y: (variantOffset.y + CGFloat.random(in: -0.05...0.05)) * contentRect.height
        )

        let coreGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                UIColor(white: 1.0, alpha: baseAlpha).cgColor,
                UIColor(white: 1.0, alpha: baseAlpha * 0.44).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray,
            locations: [0.0, 0.30, 1.0]
        )!
        cg.drawRadialGradient(
            coreGradient,
            startCenter: CGPoint(x: innerCenter.x + coreOffset.x, y: innerCenter.y + coreOffset.y),
            startRadius: 0.0,
            endCenter: CGPoint(x: innerCenter.x + coreOffset.x, y: innerCenter.y + coreOffset.y),
            endRadius: coreRadius,
            options: [.drawsAfterEndLocation]
        )

        // Keep a stable luminous nucleus so erosion can soften the tile without hollowing the center.
        let nucleusGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                UIColor(white: 1.0, alpha: baseAlpha * 0.72).cgColor,
                UIColor(white: 1.0, alpha: baseAlpha * 0.26).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray,
            locations: [0.0, 0.42, 1.0]
        )!
        cg.drawRadialGradient(
            nucleusGradient,
            startCenter: innerCenter,
            startRadius: 0.0,
            endCenter: innerCenter,
            endRadius: contentRect.width * 0.24,
            options: [.drawsAfterEndLocation]
        )

        let blobRange = variantBlobRanges[variantIndex]
        let blobCount = Int.random(in: blobRange.0...blobRange.1)
        for blobIndex in 0..<blobCount {
            let bias = CGFloat(blobIndex) / CGFloat(max(blobCount - 1, 1))
            let flowAngle = (bias * CGFloat.pi * variantFlowFactors[variantIndex]) + variantAngleBias + CGFloat.random(in: -0.48...0.48)
            let flowDirection = CGPoint(x: cos(flowAngle), y: sin(flowAngle))
            let asymmetry = CGFloat.random(in: 0.30...0.90)
            let blobCenter = CGPoint(
                x: innerCenter.x + coreOffset.x + flowDirection.x * coreRadius * asymmetry + CGFloat.random(in: -contentRect.width * 0.10...contentRect.width * 0.10),
                y: innerCenter.y + coreOffset.y + flowDirection.y * coreRadius * asymmetry + CGFloat.random(in: -contentRect.height * 0.10...contentRect.height * 0.10)
            )
            let blobRadius = CGFloat.random(in: contentRect.width * 0.30...contentRect.width * 0.76)
            let blobAlpha = CGFloat.random(in: 0.16...0.38)
            let stretch = CGFloat.random(in: 1.00...1.58)
            let blobGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1.0, alpha: blobAlpha).cgColor,
                    UIColor(white: 1.0, alpha: blobAlpha * 0.34).cgColor,
                    UIColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.40, 1.0]
            )!
            cg.saveGState()
            cg.translateBy(x: blobCenter.x, y: blobCenter.y)
            cg.rotate(by: CGFloat.random(in: 0.0...(CGFloat.pi * 2.0)))
            cg.scaleBy(x: stretch, y: CGFloat.random(in: 0.50...0.96))
            cg.drawRadialGradient(
                blobGradient,
                startCenter: .zero,
                startRadius: 0.0,
                endCenter: .zero,
                endRadius: blobRadius,
                options: [.drawsAfterEndLocation]
            )
            cg.restoreGState()
        }

        let hazeCount = Int.random(in: 8...14)
        for _ in 0..<hazeCount {
            let hazeAngle = CGFloat.random(in: 0.0...(CGFloat.pi * 2.0))
            let hazeDistance = CGFloat.random(in: contentRect.width * 0.18...contentRect.width * 0.42)
            let hazeCenter = CGPoint(
                x: innerCenter.x + coreOffset.x * CGFloat.random(in: 0.30...0.70) + cos(hazeAngle) * hazeDistance,
                y: innerCenter.y + coreOffset.y * CGFloat.random(in: 0.30...0.70) + sin(hazeAngle) * hazeDistance
            )
            let hazeRadius = CGFloat.random(in: contentRect.width * 0.22...contentRect.width * 0.48)
            let hazeAlpha = CGFloat.random(in: 0.04...0.12)
            let hazeGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1.0, alpha: hazeAlpha).cgColor,
                    UIColor(white: 1.0, alpha: hazeAlpha * 0.30).cgColor,
                    UIColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.55, 1.0]
            )!
            cg.drawRadialGradient(
                hazeGradient,
                startCenter: hazeCenter,
                startRadius: 0.0,
                endCenter: hazeCenter,
                endRadius: hazeRadius,
                options: [.drawsAfterEndLocation]
            )
        }

        let filamentRange = variantFilamentRanges[variantIndex]
        let softenedFilamentMin = max(2, filamentRange.0 - 3)
        let softenedFilamentMax = max(softenedFilamentMin, filamentRange.1 - 3)
        let filamentCount = Int.random(in: softenedFilamentMin...softenedFilamentMax)
        for _ in 0..<filamentCount {
            let filamentAngle = variantAngleBias + CGFloat.random(in: -0.90...0.90)
            let filamentLength = CGFloat.random(in: contentRect.width * 0.42...contentRect.width * 0.88)
            let filamentWidth = CGFloat.random(in: 18.0...46.0)
            let filamentAlpha = CGFloat.random(in: 0.025...0.075)
            let direction = CGPoint(x: cos(filamentAngle), y: sin(filamentAngle))
            let perpendicular = CGPoint(x: -direction.y, y: direction.x)
            let segments = Int.random(in: 16...28)

            for segment in 0..<segments {
                let t = CGFloat(segment) / CGFloat(max(segments - 1, 1))
                let along = (t - 0.5) * filamentLength
                let wobble = sin(t * CGFloat.pi * CGFloat.random(in: 1.1...2.6)) * CGFloat.random(in: -16.0...16.0)
                let point = CGPoint(
                    x: innerCenter.x + coreOffset.x + direction.x * along + perpendicular.x * wobble,
                    y: innerCenter.y + coreOffset.y + direction.y * along + perpendicular.y * wobble
                )
                let alpha = filamentAlpha * (1.0 - abs(t - 0.5) * 0.78)
                cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(
                    x: point.x - filamentWidth * 0.5,
                    y: point.y - filamentWidth * 0.5,
                    width: filamentWidth,
                    height: filamentWidth
                ))
            }
        }

        let dustCount = Int.random(in: 380...760)
        for _ in 0..<dustCount {
            let radius = contentRect.width * CGFloat.random(in: 0.10...0.48) * pow(CGFloat.random(in: 0.0...1.0), 1.45)
            let angle = CGFloat.random(in: 0.0...(CGFloat.pi * 2.0))
            let point = CGPoint(
                x: innerCenter.x + coreOffset.x + cos(angle) * radius + CGFloat.random(in: -18.0...18.0),
                y: innerCenter.y + coreOffset.y + sin(angle) * radius + CGFloat.random(in: -18.0...18.0)
            )
            let edgeFade = 1.0 - min(radius / (contentRect.width * 0.50), 1.0)
            let alpha = CGFloat.random(in: 0.04...0.18) * edgeFade
            let starSize = CGFloat.random(in: 0.24...1.12)
            cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
            cg.fillEllipse(in: CGRect(x: point.x, y: point.y, width: starSize, height: starSize))
        }

        // Erode smooth radial overlap with random soft cutouts to avoid visible circular stacks.
        cg.setBlendMode(.destinationOut)
        let erosionCount = Int.random(in: 70...136)
        for _ in 0..<erosionCount {
            let edgeBandStart = contentRect.width * 0.30
            let edgeBandEnd = contentRect.width * 0.48
            let erosionAngle = CGFloat.random(in: 0.0...(CGFloat.pi * 2.0))
            let erosionDistance = CGFloat.random(in: edgeBandStart...edgeBandEnd)
            let erosionCenter = CGPoint(
                x: innerCenter.x + cos(erosionAngle) * erosionDistance + CGFloat.random(in: -contentRect.width * 0.05...contentRect.width * 0.05),
                y: innerCenter.y + sin(erosionAngle) * erosionDistance + CGFloat.random(in: -contentRect.height * 0.05...contentRect.height * 0.05)
            )
            let erosionRadius = CGFloat.random(in: contentRect.width * 0.06...contentRect.width * 0.18)
            let erosionAlpha = CGFloat.random(in: 0.05...0.14)
            let erosionGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1.0, alpha: erosionAlpha).cgColor,
                    UIColor(white: 1.0, alpha: erosionAlpha * 0.22).cgColor,
                    UIColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.78, 1.0]
            )!
            cg.drawRadialGradient(
                erosionGradient,
                startCenter: erosionCenter,
                startRadius: 0.0,
                endCenter: erosionCenter,
                endRadius: erosionRadius,
                options: [.drawsAfterEndLocation]
            )
        }

        let laneCount = Int.random(in: 2...4)
        for _ in 0..<laneCount {
            let laneAngle = CGFloat.random(in: 0.0...(CGFloat.pi * 2.0))
            let laneLength = CGFloat.random(in: contentRect.width * 0.34...contentRect.width * 0.70)
            let laneWidth = CGFloat.random(in: 12.0...28.0)
            let laneAlpha = CGFloat.random(in: 0.025...0.07)
            let direction = CGPoint(x: cos(laneAngle), y: sin(laneAngle))
            let perpendicular = CGPoint(x: -direction.y, y: direction.x)
            let segments = Int.random(in: 12...22)
            for segment in 0..<segments {
                let t = CGFloat(segment) / CGFloat(max(segments - 1, 1))
                let along = (t - 0.5) * laneLength
                let wobble = sin(t * CGFloat.pi * CGFloat.random(in: 1.1...2.1)) * CGFloat.random(in: -8.0...8.0)
                let point = CGPoint(
                    x: innerCenter.x + direction.x * along + perpendicular.x * wobble,
                    y: innerCenter.y + direction.y * along + perpendicular.y * wobble
                )
                let alpha = laneAlpha * (1.0 - abs(t - 0.5) * 0.8)
                cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(
                    x: point.x - laneWidth * 0.5,
                    y: point.y - laneWidth * 0.5,
                    width: laneWidth,
                    height: laneWidth
                ))
            }
        }

        cg.setBlendMode(.plusLighter)
        let grainCount = Int.random(in: 900...1600)
        for _ in 0..<grainCount {
            let point = CGPoint(
                x: CGFloat.random(in: contentRect.minX...contentRect.maxX),
                y: CGFloat.random(in: contentRect.minY...contentRect.maxY)
            )
            let alpha = CGFloat.random(in: 0.004...0.022)
            let dotSize = CGFloat.random(in: 0.12...0.42)
            cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
            cg.fillEllipse(in: CGRect(x: point.x, y: point.y, width: dotSize, height: dotSize))
        }

        if variantDarkLaneFlags[variantIndex] {
            let darkLaneGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 0.0, alpha: 0.30).cgColor,
                    UIColor(white: 0.0, alpha: 0.12).cgColor,
                    UIColor(white: 0.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.58, 1.0]
            )!
            cg.setBlendMode(.normal)
            cg.drawRadialGradient(
                darkLaneGradient,
                startCenter: CGPoint(x: innerCenter.x + coreOffset.x * 0.5, y: innerCenter.y + coreOffset.y * 0.5),
                startRadius: 0.0,
                endCenter: CGPoint(x: innerCenter.x + coreOffset.x * 0.5, y: innerCenter.y + coreOffset.y * 0.5),
                endRadius: contentRect.width * CGFloat.random(in: 0.26...0.44),
                options: [.drawsAfterEndLocation]
            )
            cg.setBlendMode(.plusLighter)
        }
    }

    private static func applyCloudTileBoundaryFade(
        _ bitmap: DynamicTextureBitmap,
        fadeWidthRatio: CGFloat
    ) -> DynamicTextureBitmap {
        guard bitmap.width > 0, bitmap.height > 0 else {
            return bitmap
        }

        var data = bitmap.data
        let width = bitmap.width
        let height = bitmap.height
        let fadeWidth = max(16.0, CGFloat(min(width, height)) * max(0.02, min(fadeWidthRatio, 0.25)))
        let maxIndex = max(width - 1, height - 1)

        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            for y in 0..<height {
                for x in 0..<width {
                    let edgeDistance = min(
                        CGFloat(x),
                        CGFloat(y),
                        CGFloat(maxIndex - x),
                        CGFloat(maxIndex - y)
                    )
                    let t = max(0.0, min(edgeDistance / fadeWidth, 1.0))
                    let fade = t * t * (3.0 - (2.0 * t))
                    let pixelOffset = (y * bitmap.bytesPerRow) + (x * 4)
                    let pixel = baseAddress.advanced(by: pixelOffset).assumingMemoryBound(to: UInt8.self)
                    pixel[0] = UInt8(CGFloat(pixel[0]) * fade)
                    pixel[1] = UInt8(CGFloat(pixel[1]) * fade)
                    pixel[2] = UInt8(CGFloat(pixel[2]) * fade)
                    pixel[3] = UInt8(CGFloat(pixel[3]) * fade)
                }
            }
        }

        return DynamicTextureBitmap(
            width: bitmap.width,
            height: bitmap.height,
            bytesPerRow: bitmap.bytesPerRow,
            data: data
        )
    }

    private static func makeBitmap(
        size: Int,
        draw: (CGContext, Int) -> Void
    ) -> DynamicTextureBitmap {
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        draw(context, size)
        return DynamicTextureBitmap(width: width, height: height, bytesPerRow: bytesPerRow, data: data)
    }
}

private final class DynamicBundleSentinel {}

private struct DynamicTextureBitmap {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]
}

private struct CloudTileLayout {
    let canvasRect: CGRect
    let safeInset: CGFloat
    let contentRect: CGRect
}
