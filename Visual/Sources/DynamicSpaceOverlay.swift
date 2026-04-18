import Metal
import MetalKit
import MotionComfortCore
import QuartzCore
import SwiftUI
import UIKit

public enum DynamicWarpMode: String, CaseIterable, Identifiable, Sendable {
    case cruise
    case warp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cruise:
            return "Cruise"
        case .warp:
            return "Warp"
        }
    }
}

public struct DynamicFlowOverlay: View {
    let sample: MotionSample
    let orientation: InterfaceRenderOrientation
    let warpMode: DynamicWarpMode

    public init(
        sample: MotionSample = .neutral,
        orientation: InterfaceRenderOrientation = .portrait,
        warpMode: DynamicWarpMode = .cruise
    ) {
        self.sample = sample
        self.orientation = orientation
        self.warpMode = warpMode
    }

    public var body: some View {
        GeometryReader { proxy in
            DynamicMetalView(
                sample: sample.rotatedForDisplay(orientation),
                warpMode: warpMode
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct DynamicMetalView: UIViewRepresentable {
    typealias UIViewType = DynamicRenderView

    let sample: MotionSample
    let warpMode: DynamicWarpMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DynamicRenderView {
        let device = MTLCreateSystemDefaultDevice()
        let view = DynamicRenderView(frame: .zero, device: device)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 1.0 / 255.0, green: 1.0 / 255.0, blue: 5.0 / 255.0, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = UIColor(red: 1.0 / 255.0, green: 1.0 / 255.0, blue: 5.0 / 255.0, alpha: 1.0)

        guard let device else {
            view.showFailure("Metal unavailable")
            return view
        }

        do {
            let renderer = try DynamicMetalRenderer(
                device: device,
                colorPixelFormat: view.colorPixelFormat,
                drawableSize: view.drawableSize
            )
            renderer.sample = sample
            renderer.warpMode = warpMode
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
        context.coordinator.renderer?.warpMode = warpMode
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
    let particleCount = 500
    let dustCount = 15000
    let minZ: Float = 0.2
    let maxZ: Float = 5.0
    let idleSpeed: Float = 0.005
    let warpSpeed: Float = 0.14
    let camSensX: Float = 0.045
    let camSensY: Float = 0.045
    let nebulaCloudCount = 15
    let nebulaBaseAlpha: Float = 0.45
    let sensorSmoothing: Float = 0.35
    let velocityFriction: Float = 0.08
    let brightnessDivisor: Float = 1.5
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
    var baseSize: Float
    var freqX1: Float
    var freqX2: Float
    var freqY1: Float
    var freqY2: Float
    var phaseX: Float
    var phaseY: Float
    var alphaFreq: Float
    var wanderRadiusX: Float
    var wanderRadiusY: Float
}

private struct DynamicSpaceSceneState {
    var particles: [DynamicParticle] = []
    var dusts: [DynamicDust] = []
    var nebulas: [DynamicNebula] = []
    var filteredAccel = SIMD2<Float>(repeating: 0.0)
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
}

private struct DynamicViewportUniforms {
    var viewportSize: SIMD2<Float>
}

private enum DynamicRendererSetupError: Error {
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

private final class DynamicMetalRenderer: NSObject, MTKViewDelegate {
    var sample: MotionSample = .neutral
    var warpMode: DynamicWarpMode = .cruise

    private let config = DynamicSpaceConfiguration()
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let additivePipeline: MTLRenderPipelineState
    private let screenPipeline: MTLRenderPipelineState

    private let blurTexture: MTLTexture
    private let sharpTexture: MTLTexture
    private let cloudTexture: MTLTexture
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

    init(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        drawableSize: CGSize
    ) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw DynamicRendererSetupError.missingCommandQueue
        }

        self.device = device
        self.commandQueue = commandQueue
        self.state = DynamicSpaceSceneState(config: config)

        let library: MTLLibrary
        let bundle = Bundle(for: DynamicBundleSentinel.self)
        if let url = bundle.url(forResource: "default", withExtension: "metallib") {
            do {
                library = try device.makeLibrary(URL: url)
            } catch {
                throw DynamicRendererSetupError.libraryLoad(error.localizedDescription)
            }
        } else if let fallback = device.makeDefaultLibrary() {
            library = fallback
        } else {
            throw DynamicRendererSetupError.missingLibrary
        }

        do {
            guard
                library.makeFunction(name: "dynamicSpriteVertex") != nil,
                library.makeFunction(name: "dynamicSpriteFragment") != nil
            else {
                throw DynamicRendererSetupError.invalidShaderFunctions
            }

            additivePipeline = try DynamicMetalRenderer.makePipeline(
                device: device,
                library: library,
                pixelFormat: colorPixelFormat,
                fragmentBlend: .additive
            )
            screenPipeline = try DynamicMetalRenderer.makePipeline(
                device: device,
                library: library,
                pixelFormat: colorPixelFormat,
                fragmentBlend: .screen
            )
        } catch let error as DynamicRendererSetupError {
            throw error
        } catch {
            throw DynamicRendererSetupError.pipelineCreation(error.localizedDescription)
        }

        do {
            blurTexture = try DynamicMetalRenderer.makeTexture(
                device: device,
                bitmap: DynamicTextureFactory.makeBlurBitmap(size: 128)
            )
            sharpTexture = try DynamicMetalRenderer.makeTexture(
                device: device,
                bitmap: DynamicTextureFactory.makeSharpBitmap(size: 32)
            )
            cloudTexture = try DynamicMetalRenderer.makeTexture(
                device: device,
                bitmap: DynamicTextureFactory.makeCloudBitmap(size: 256)
            )
            dustTexture = try DynamicMetalRenderer.makeTexture(
                device: device,
                bitmap: DynamicTextureFactory.makeDustBitmap(size: 8)
            )
        } catch {
            throw DynamicRendererSetupError.textureCreation(error.localizedDescription)
        }

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

        self.drawableSize = drawableSize
        rebuildScene(for: drawableSize)
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
            viewportSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height))
        )

        drawSprites(
            encoder: encoder,
            pipeline: screenPipeline,
            buffer: nebulaBuffer,
            count: nebulaCount,
            texture: cloudTexture,
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
        state.currentVelocity = .zero
        state.currentWarpSpeed = config.idleSpeed
        state.universeSpreadX = config.maxZ * 2.8
        state.universeSpreadY = state.universeSpreadX * max(1.0, Float(size.height / size.width))

        state.particles.removeAll(keepingCapacity: true)
        state.dusts.removeAll(keepingCapacity: true)
        state.nebulas.removeAll(keepingCapacity: true)

        for _ in 0..<config.particleCount {
            let isSharp = Float.random(in: 0.0...1.0) < 0.82
            let particle = DynamicParticle(
                x: 0.0,
                y: 0.0,
                z: 0.0,
                size: isSharp ? Float.random(in: 8.0...18.0) : Float.random(in: 36.0...104.0),
                colorIndex: Int32.random(in: 0..<Int32(DynamicPalette.colors.count)),
                isSharp: isSharp,
                baseAlpha: isSharp ? Float.random(in: 0.45...0.80) : Float.random(in: 0.20...0.50),
                phase: Float.random(in: 0.0...(Float.pi * 2.0)),
                currentAlpha: 0.0,
                currentScale: 1.0
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

        let screenMin = Float(min(size.width, size.height))
        for index in 0..<config.nebulaCloudCount {
            state.nebulas.append(
                DynamicNebula(
                    colorIndex: Int32(index % DynamicPalette.colors.count),
                    baseSize: screenMin * Float.random(in: 0.4...0.9),
                    freqX1: Float.random(in: 0.0002...0.0007),
                    freqX2: Float.random(in: 0.0003...0.0010),
                    freqY1: Float.random(in: 0.0002...0.0006),
                    freqY2: Float.random(in: 0.0003...0.0009),
                    phaseX: Float.random(in: 0.0...(Float.pi * 2.0)),
                    phaseY: Float.random(in: 0.0...(Float.pi * 2.0)),
                    alphaFreq: Float.random(in: 0.0005...0.0015),
                    wanderRadiusX: Float(size.width) * 0.12,
                    wanderRadiusY: Float(size.height) * 0.12
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
        let intensity = min(accelMagnitude / config.brightnessDivisor, 1.0)
        let activeBrightness = intensity * 0.8
        let activeHaloScale: Float = 1.0 + (intensity * 0.6)

        let targetWarpSpeed = warpMode == .warp ? config.warpSpeed : config.idleSpeed
        state.currentWarpSpeed += (targetWarpSpeed - state.currentWarpSpeed) * 0.05 * frameScale

        buildNebulas(timeMs: timeMs)
        buildDust(activeBrightness: activeBrightness, frameScale: frameScale)
        buildParticles(activeBrightness: activeBrightness, activeHaloScale: activeHaloScale, frameScale: frameScale)

        upload(nebulaVertices, count: nebulaCount, to: nebulaBuffer)
        upload(dustVertices, count: dustCount, to: dustBuffer)
        upload(haloVertices, count: haloCount, to: haloBuffer)
        upload(sharpVertices, count: sharpCount, to: sharpBuffer)
    }

    private func buildNebulas(timeMs: Float) {
        let centerX = Float(drawableSize.width) * 0.5
        let centerY = Float(drawableSize.height) * 0.5
        let parallaxX = -state.currentVelocity.x * 6.0
        let parallaxY = -state.currentVelocity.y * 6.0
        nebulaCount = 0

        for nebula in state.nebulas {
            let driftX = sin((timeMs * nebula.freqX1) + nebula.phaseX) * cos(timeMs * nebula.freqX2) * nebula.wanderRadiusX
            let driftY = cos((timeMs * nebula.freqY1) + nebula.phaseY) * sin(timeMs * nebula.freqY2) * nebula.wanderRadiusY
            let breathAlpha = sin(timeMs * nebula.alphaFreq) * 0.3 + 0.7
            let alpha = min(config.nebulaBaseAlpha * breathAlpha, 1.0)
            let color = DynamicPalette.colors[Int(nebula.colorIndex)]

            nebulaVertices[nebulaCount] = DynamicSpriteVertex(
                positionAndSize: SIMD4(centerX + driftX + parallaxX, centerY + driftY + parallaxY, nebula.baseSize, alpha),
                colorAndSoftness: SIMD4(color.x, color.y, color.z, 1.0)
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
            state.dusts[index].currentAlpha += (targetAlpha - state.dusts[index].currentAlpha) * 0.2 * frameScale

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

    private func buildParticles(activeBrightness: Float, activeHaloScale: Float, frameScale: Float) {
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
            let targetScale: Float = state.particles[index].isSharp ? 1.0 : activeHaloScale
            state.particles[index].currentScale += (targetScale - state.particles[index].currentScale) * 0.15 * frameScale
            let sizeBoost: Float = state.particles[index].isSharp ? 1.9 : 1.7
            let renderSize = max(state.particles[index].size * scale * state.particles[index].currentScale * sizeBoost, 2.2)
            let isVisible = screenX > -renderSize && screenX < Float(drawableSize.width) + renderSize && screenY > -renderSize && screenY < Float(drawableSize.height) + renderSize

            state.particles[index].phase += 0.03 * frameScale
            let breath = sin(state.particles[index].phase) * 0.15 + 0.85
            let depthAlpha = state.particles[index].z > config.maxZ - 1.2 ? (config.maxZ - state.particles[index].z) / 1.2 : 1.0
            let targetAlpha = min(state.particles[index].baseAlpha + 0.35 + activeBrightness * 1.25, 1.0) * breath * depthAlpha
            state.particles[index].currentAlpha += (targetAlpha - state.particles[index].currentAlpha) * 0.15 * frameScale

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
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
    }

    private static func makeTexture(device: MTLDevice, bitmap: DynamicTextureBitmap) throws -> MTLTexture {
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

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        fragmentBlend: DynamicBlendMode
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "dynamicSpriteVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "dynamicSpriteFragment")
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
            UIColor.white.setFill()
            context.fill(CGRect(x: 0.0, y: 0.0, width: CGFloat(size), height: CGFloat(size)))
        }
    }

    static func makeCloudBitmap(size: Int) -> DynamicTextureBitmap {
        makeBitmap(size: size) { cg, size in
            let rect = CGRect(x: 0.0, y: 0.0, width: CGFloat(size), height: CGFloat(size))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            let baseGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1.0, alpha: 0.5).cgColor,
                    UIColor(white: 1.0, alpha: 0.15).cgColor,
                    UIColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.5, 1.0]
            )!
            cg.drawRadialGradient(baseGradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: CGFloat(size) * 0.5, options: [.drawsAfterEndLocation])

            cg.setBlendMode(.plusLighter)
            for _ in 0..<4 {
                let blobRadius = CGFloat.random(in: 20.0...80.0)
                let blobCenter = CGPoint(
                    x: rect.midX + CGFloat.random(in: -40.0...40.0),
                    y: rect.midY + CGFloat.random(in: -40.0...40.0)
                )
                let blobGradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: [
                        UIColor(white: 1.0, alpha: 0.4).cgColor,
                        UIColor(white: 1.0, alpha: 0.0).cgColor
                    ] as CFArray,
                    locations: [0.0, 1.0]
                )!
                cg.drawRadialGradient(blobGradient, startCenter: blobCenter, startRadius: 0.0, endCenter: blobCenter, endRadius: blobRadius, options: [.drawsAfterEndLocation])
            }

            cg.setBlendMode(.plusLighter)
            for _ in 0..<400 {
                let radius = CGFloat(size) * 0.3125 * pow(CGFloat.random(in: 0.0...1.0), 2.0)
                let angle = CGFloat.random(in: 0.0...(CGFloat.pi * 2.0))
                let point = CGPoint(
                    x: rect.midX + cos(angle) * radius,
                    y: rect.midY + sin(angle) * radius
                )
                let edgeFade = 1.0 - (radius / (CGFloat(size) * 0.3125))
                let alpha = (CGFloat.random(in: 0.2...0.8)) * edgeFade
                let starSize = CGFloat.random(in: 0.2...0.7)
                cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: point.x, y: point.y, width: starSize, height: starSize))
            }

            cg.setBlendMode(.normal)
            let wrapGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1.0, alpha: 0.25).cgColor,
                    UIColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            cg.drawRadialGradient(wrapGradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: CGFloat(size) * 0.47, options: [.drawsAfterEndLocation])
        }
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
