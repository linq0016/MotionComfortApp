import AVFoundation
import CoreMedia
import CoreVideo
import MotionComfortCore
import SwiftUI
#if DEBUG
import os
#endif

#if DEBUG
private let liveViewCameraLogger = Logger(
    subsystem: "com.motioncomfort.app",
    category: "LiveViewCamera"
)

private func liveViewCameraLog(_ message: String, attemptID: UInt64?) {
    let attemptDescription = attemptID.map(String.init) ?? "-"
    liveViewCameraLogger.debug("[attempt \(attemptDescription, privacy: .public)] \(message, privacy: .public)")
}
#endif

private func localized(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}

// Live View：全屏相机预览加四边光流。
public struct LiveViewOverlay: View {
    let sample: MotionSample
    let style: VisualGuideStyle
    let orientation: InterfaceRenderOrientation

    @ObservedObject private var camera: LiveViewCameraModel
    @State private var phase = FlowGridPhase()

    public init(
        sample: MotionSample,
        style: VisualGuideStyle = .liveView,
        orientation: InterfaceRenderOrientation = .portrait,
        camera: LiveViewCameraModel = LiveViewCameraModel()
    ) {
        self.sample = sample
        self.style = style
        self.orientation = orientation
        self._camera = ObservedObject(wrappedValue: camera)
    }

    public var body: some View {
        ZStack {
            if camera.status == .authorized,
               let previewSession = camera.previewSession {
                LiveViewCameraPreview(
                    session: previewSession,
                    orientation: orientation,
                    previewBridge: camera.previewBridge,
                    attemptID: camera.debugAttemptID
                )
                    .overlay {
                        if camera.canShowPreview {
                        LiveViewEdgeFlowOverlay(
                            sample: sample,
                            sceneAnalysis: camera.sceneAnalysis,
                            phase: $phase,
                            orientation: orientation
                        )
                        }
                    }
            }

            if camera.status != .authorized || camera.previewState == .unavailable {
                LiveViewUnavailableSurface(
                    style: style,
                    status: camera.status,
                    previewState: camera.previewState
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.updateOrientation(orientation)
        }
        .onChange(of: orientation) { _, nextOrientation in
            camera.updateOrientation(nextOrientation)
            phase.reset(at: Date().timeIntervalSinceReferenceDate)
        }
    }
}

enum LiveViewDotPolarity: Sendable {
    case light
    case dark

    var color: Color {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }
}

struct LiveViewSceneAnalysis: Sendable {
    var leadingBandLuminance: Double = 0.0
    var trailingBandLuminance: Double = 0.0
    var topBandLuminance: Double = 0.0
    var bottomBandLuminance: Double = 0.0
    var dominantDotPolarity: LiveViewDotPolarity = .light
}

public enum LiveViewPreviewState: String, Sendable {
    case idle
    case starting
    case ready
    case unavailable
}

private enum LiveViewCameraLifecycleState: Sendable {
    case idle
    case configuring
    case running
    case stopping
    case failed
}

private final class LiveViewPreviewBridge {
    private var unbindHandler: (() -> Void)?
    private(set) var isTeardownRequested = false

    func attach(unbindHandler: @escaping () -> Void) {
        self.unbindHandler = unbindHandler
        guard isTeardownRequested else {
            return
        }
        unbindHandler()
    }

    func detach() {
        unbindHandler = nil
    }

    func requestTeardown() {
        isTeardownRequested = true
        unbindHandler?()
    }

    func unbindSession() {
        unbindHandler?()
    }
}

public final class LiveViewCameraModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published public private(set) var status: AVAuthorizationStatus
    @Published public private(set) var isRunning = false
    @Published public private(set) var previewState: LiveViewPreviewState = .idle
    @Published public private(set) var previewSession: AVCaptureSession?
    @Published private(set) var sceneAnalysis = LiveViewSceneAnalysis()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.motioncomfort.liveview.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.motioncomfort.liveview.analysis", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var isConfigured = false
    private var latestSceneAnalysis = LiveViewSceneAnalysis()
    private var smoothedLuminance: Double?
    private var lastPolaritySwitchAt: TimeInterval?
    private var analysisOrientation: InterfaceRenderOrientation = .portrait
    private var connectionOrientation: InterfaceRenderOrientation = .portrait
    private var lifecycleState: LiveViewCameraLifecycleState = .idle
    private var stopContinuations: [CheckedContinuation<Void, Never>] = []

    private let luminanceEmaAlpha = 0.18
    private let polarityHoldDuration: TimeInterval = 0.45
    fileprivate let previewBridge = LiveViewPreviewBridge()
    fileprivate let debugAttemptID: UInt64?

    public init(launchAttemptID: UInt64? = nil) {
        self.debugAttemptID = launchAttemptID
        self.status = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
        self.previewSession = session
        #if DEBUG
        liveViewCameraLog("camera instance created", attemptID: debugAttemptID)
        #endif
    }

    public var canShowPreview: Bool {
        status == .authorized && previewState == .ready && isRunning
    }

    @MainActor
    public func detachPreviewForTeardown() {
        previewBridge.requestTeardown()
        previewSession = nil
        #if DEBUG
        liveViewCameraLog("preview detach requested", attemptID: debugAttemptID)
        #endif
    }

    public func start() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.status = currentStatus
            if currentStatus == .authorized {
                self.previewState = .starting
                if self.previewSession == nil {
                    self.previewSession = self.session
                }
            }
        }

        switch currentStatus {
        case .authorized:
            configureAndRunIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }

                DispatchQueue.main.async {
                    self.status = granted ? .authorized : .denied
                    self.previewState = granted ? .starting : .unavailable
                    if granted, self.previewSession == nil {
                        self.previewSession = self.session
                    }
                }

                if granted {
                    self.configureAndRunIfNeeded()
                } else {
                    self.stop()
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.previewState = .unavailable
            }
            stop()
        @unknown default:
            DispatchQueue.main.async {
                self.previewState = .unavailable
            }
            stop()
        }
    }

    public func stop() {
        Task {
            await stopAndWait()
        }
    }

    public func stopAndWait() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if self.lifecycleState == .stopping {
                    self.stopContinuations.append(continuation)
                    return
                }

                guard self.lifecycleState != .idle || self.session.isRunning || self.isConfigured else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.previewState = self.status == .authorized ? .idle : .unavailable
                        continuation.resume()
                    }
                    return
                }

                self.stopContinuations.append(continuation)
                self.performStopLocked()
            }
        }
    }

    func updateOrientation(_ orientation: InterfaceRenderOrientation) {
        analysisQueue.async { [weak self] in
            self?.analysisOrientation = orientation
        }

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.connectionOrientation = orientation
            self.applyOrientationToConnections(orientation)
        }
    }

    private func configureAndRunIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            switch self.lifecycleState {
            case .configuring, .running, .stopping:
                #if DEBUG
                liveViewCameraLog(
                    "start skipped while \(String(describing: self.lifecycleState))",
                    attemptID: self.debugAttemptID
                )
                #endif
                return
            case .idle, .failed:
                break
            }

            self.lifecycleState = .configuring
            #if DEBUG
            liveViewCameraLog("configure begin", attemptID: self.debugAttemptID)
            #endif
            if !self.isConfigured {
                guard self.configureSession() else {
                    self.lifecycleState = .failed
                    #if DEBUG
                    liveViewCameraLog("configure failed", attemptID: self.debugAttemptID)
                    #endif
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.previewState = .unavailable
                    }
                    return
                }
            }
            #if DEBUG
            liveViewCameraLog("configure end", attemptID: self.debugAttemptID)
            #endif

            self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
            self.applyOrientationToConnections(self.connectionOrientation)
            if !self.session.isRunning {
                #if DEBUG
                liveViewCameraLog("startRunning begin", attemptID: self.debugAttemptID)
                #endif
                self.session.startRunning()
                #if DEBUG
                liveViewCameraLog("startRunning end", attemptID: self.debugAttemptID)
                #endif
            }

            self.lifecycleState = .running
            DispatchQueue.main.async {
                self.isRunning = true
                self.previewState = .ready
            }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = makeCaptureDevice() else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            guard session.canAddInput(input) else {
                return false
            }
            session.addInput(input)

            configureVideoOutput()

            isConfigured = true
            return true
        } catch {
            return false
        }
    }

    private func makeCaptureDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func configureVideoOutput() {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput) else {
            return
        }

        session.addOutput(videoOutput)
    }

    private func performStopLocked() {
        lifecycleState = .stopping
        #if DEBUG
        liveViewCameraLog("stopRunning begin", attemptID: debugAttemptID)
        #endif

        videoOutput.setSampleBufferDelegate(nil, queue: nil)

        if session.isRunning {
            session.stopRunning()
        }

        if isConfigured {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            isConfigured = false
        }

        latestSceneAnalysis = LiveViewSceneAnalysis()
        smoothedLuminance = nil
        lastPolaritySwitchAt = nil
        lifecycleState = .idle

        let continuations = stopContinuations
        stopContinuations.removeAll()

        #if DEBUG
        liveViewCameraLog("stopRunning end", attemptID: debugAttemptID)
        #endif

        DispatchQueue.main.async {
            self.isRunning = false
            self.previewState = self.status == .authorized ? .idle : .unavailable
            #if DEBUG
            liveViewCameraLog("teardown finished", attemptID: self.debugAttemptID)
            #endif
            continuations.forEach { $0.resume() }
        }
    }

    private func applyOrientationToConnections(_ orientation: InterfaceRenderOrientation) {
        guard let connection = videoOutput.connection(with: .video) else {
            return
        }

        connection.applyVideoRotationAngle(orientation.videoRotationAngle)
    }

    private func analyze(pixelBuffer: CVPixelBuffer) -> LiveViewSceneAnalysis {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return latestSceneAnalysis
        }

        let bandWidth = max(Int(Double(width) * 0.18), 40)
        let bandHeight = max(Int(Double(height) * 0.14), 40)
        let strideX = max(width / 72, 6)
        let strideY = max(height / 72, 6)

        let leadingLuminance = averageLuminance(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            xRange: 0..<bandWidth,
            yRange: 0..<height,
            strideX: strideX,
            strideY: strideY
        )

        let trailingLuminance = averageLuminance(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            xRange: max(width - bandWidth, 0)..<width,
            yRange: 0..<height,
            strideX: strideX,
            strideY: strideY
        )

        let topLuminance = averageLuminance(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            xRange: 0..<width,
            yRange: 0..<bandHeight,
            strideX: strideX,
            strideY: strideY
        )

        let bottomLuminance = averageLuminance(
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            xRange: 0..<width,
            yRange: max(height - bandHeight, 0)..<height,
            strideX: strideX,
            strideY: strideY
        )

        let overallLuminance = (leadingLuminance + trailingLuminance + topLuminance + bottomLuminance) / 4.0
        let filteredLuminance = applyLuminanceSmoothing(overallLuminance)
        let timestamp = ProcessInfo.processInfo.systemUptime

        let rawAnalysis = LiveViewSceneAnalysis(
            leadingBandLuminance: leadingLuminance,
            trailingBandLuminance: trailingLuminance,
            topBandLuminance: topLuminance,
            bottomBandLuminance: bottomLuminance,
            dominantDotPolarity: updatedPolarity(
                for: filteredLuminance,
                previous: latestSceneAnalysis.dominantDotPolarity,
                timestamp: timestamp
            )
        )

        return rawAnalysis.rotatedForDisplay(analysisOrientation)
    }

    private func applyLuminanceSmoothing(_ luminance: Double) -> Double {
        guard let previous = smoothedLuminance else {
            smoothedLuminance = luminance
            return luminance
        }

        let filtered = (previous * (1.0 - luminanceEmaAlpha)) + (luminance * luminanceEmaAlpha)
        smoothedLuminance = filtered
        return filtered
    }

    private func averageLuminance(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        width: Int,
        height: Int,
        xRange: Range<Int>,
        yRange: Range<Int>,
        strideX: Int,
        strideY: Int
    ) -> Double {
        var sum = 0.0
        var count = 0.0

        let clampedXLower = max(xRange.lowerBound, 0)
        let clampedXUpper = min(xRange.upperBound, width)
        let clampedYLower = max(yRange.lowerBound, 0)
        let clampedYUpper = min(yRange.upperBound, height)

        guard clampedXLower < clampedXUpper, clampedYLower < clampedYUpper else {
            return 0.0
        }

        for y in stride(from: clampedYLower, to: clampedYUpper, by: strideY) {
            let row = baseAddress.advanced(by: y * bytesPerRow)

            for x in stride(from: clampedXLower, to: clampedXUpper, by: strideX) {
                let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                let blue = Double(pixel[0]) / 255.0
                let green = Double(pixel[1]) / 255.0
                let red = Double(pixel[2]) / 255.0
                let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                sum += luminance
                count += 1.0
            }
        }

        guard count > 0.0 else {
            return 0.0
        }

        return sum / count
    }

    private func updatedPolarity(
        for luminance: Double,
        previous: LiveViewDotPolarity,
        timestamp: TimeInterval
    ) -> LiveViewDotPolarity {
        let lightThreshold = 0.42
        let darkThreshold = 0.50

        if let lastSwitchAt = lastPolaritySwitchAt,
           timestamp - lastSwitchAt < polarityHoldDuration {
            return previous
        }

        let next: LiveViewDotPolarity
        switch previous {
        case .light:
            next = luminance > darkThreshold ? .dark : .light
        case .dark:
            next = luminance < lightThreshold ? .light : .dark
        }

        if next != previous {
            lastPolaritySwitchAt = timestamp
        }
        return next
    }
}

public enum LiveViewCameraPreflight {
    public static func ensureAuthorized() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized, .denied, .restricted:
            return status
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        @unknown default:
            return .restricted
        }
    }
}

extension LiveViewCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let nextAnalysis = analyze(pixelBuffer: pixelBuffer)
        latestSceneAnalysis = nextAnalysis

        DispatchQueue.main.async {
            self.sceneAnalysis = nextAnalysis
        }
    }
}

private struct LiveViewCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: InterfaceRenderOrientation
    let previewBridge: LiveViewPreviewBridge
    let attemptID: UInt64?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        previewBridge.attach {
            view.requestTeardownUnbind(attemptID: attemptID)
        }
        view.bindSessionIfNeeded(session, attemptID: attemptID)
        view.updateOrientation(orientation)
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        previewBridge.attach {
            uiView.requestTeardownUnbind(attemptID: attemptID)
        }

        if previewBridge.isTeardownRequested {
            uiView.requestTeardownUnbind(attemptID: attemptID)
            return
        }

        uiView.bindSessionIfNeeded(session, attemptID: attemptID)
        uiView.updateOrientation(orientation)
        uiView.previewLayer.videoGravity = .resizeAspectFill
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.requestTeardownUnbind(attemptID: uiView.attemptID)
        uiView.previewLayer.connection?.applyVideoRotationAngle(.zero)
    }

    final class PreviewView: UIView {
        var attemptID: UInt64?
        private var isBindingLocked = false

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func bindSessionIfNeeded(_ session: AVCaptureSession, attemptID: UInt64?) {
            if isBindingLocked {
                #if DEBUG
                liveViewCameraLog("preview bind skipped (teardown locked)", attemptID: attemptID)
                #endif
                return
            }

            guard previewLayer.session !== session else {
                return
            }
            self.attemptID = attemptID
            previewLayer.session = session
            #if DEBUG
            liveViewCameraLog("preview bind", attemptID: attemptID)
            #endif
        }

        func requestTeardownUnbind(attemptID: UInt64?) {
            isBindingLocked = true
            unbindSession(attemptID: attemptID)
        }

        func unbindSession(attemptID: UInt64?) {
            guard previewLayer.session != nil else {
                return
            }
            previewLayer.session = nil
            #if DEBUG
            liveViewCameraLog("preview unbind", attemptID: attemptID)
            #endif
        }

        func updateOrientation(_ orientation: InterfaceRenderOrientation) {
            previewLayer.connection?.applyVideoRotationAngle(orientation.videoRotationAngle)
        }
    }
}

// Live View 的四边点阵：复用 Minimal 的连续光流手感。
private struct LiveViewEdgeFlowOverlay: View {
    let sample: MotionSample
    let sceneAnalysis: LiveViewSceneAnalysis
    @Binding var phase: FlowGridPhase
    let orientation: InterfaceRenderOrientation

    private let configuration = FlowGridConfiguration.liveViewEdge
    private let safeZoneSoftRadiusAttenuation: CGFloat = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let timestamp = timeline.date.timeIntervalSinceReferenceDate
                let orientedSample = sample.rotatedForDisplay(orientation)

                Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                    let renderState = phase.renderState
                    let startX = flowWrappedOffset(renderState.offset.x, spacing: configuration.dotSpacing) - configuration.dotSpacing
                    let startY = flowWrappedOffset(renderState.offset.y, spacing: configuration.dotSpacing) - configuration.dotSpacing
                    let normA = min(renderState.smoothedMagnitude / configuration.maxAccelThreshold, 1.0)
                    let dotColor = sceneAnalysis.dominantDotPolarity.color
                    let coreSafeRect = makeSafeRect(
                        in: canvasSize,
                        horizontalMarginRatio: configuration.horizontalMarginRatio,
                        verticalMarginRatio: configuration.verticalMarginRatio,
                        orientation: orientation
                    )
                    let safeZoneCornerRadius = min(
                        configuration.safeZoneCornerRadius,
                        min(coreSafeRect.width, coreSafeRect.height) * 0.5
                    )

                    for x in stride(from: startX, through: canvasSize.width + configuration.dotSpacing, by: configuration.dotSpacing) {
                        for y in stride(from: startY, through: canvasSize.height + configuration.dotSpacing, by: configuration.dotSpacing) {
                            let point = CGPoint(x: x, y: y)
                            if roundedRectContains(
                                point: point,
                                rect: coreSafeRect,
                                cornerRadius: safeZoneCornerRadius
                            ) {
                                continue
                            }

                            let gridX = Int(round((x - renderState.offset.x) / configuration.dotSpacing))
                            let gridY = Int(round((y - renderState.offset.y) / configuration.dotSpacing))
                            let hash = flowPseudoRandom(gridX: gridX, gridY: gridY)
                            let edgeWeight = edgeDistanceWeight(
                                point: point,
                                canvasSize: canvasSize,
                                safeRect: coreSafeRect
                            )

                            guard var appearance = flowDotAppearance(
                                hash: hash,
                                normA: normA,
                                configuration: configuration
                            ) else {
                                continue
                            }

                            appearance.radius += pow(edgeWeight, configuration.edgeRadiusCurve) * configuration.edgeRadiusBoost
                            let softWeight = safeZoneSoftWeight(
                                point: point,
                                coreSafeRect: coreSafeRect,
                                cornerRadius: safeZoneCornerRadius,
                                featherWidth: configuration.safeZoneFeatherWidth
                            )
                            appearance.alpha *= Double(softWeight)
                            appearance.radius *= 1.0 - (safeZoneSoftRadiusAttenuation * (1.0 - softWeight))

                            guard appearance.alpha > configuration.minimumVisibleAlpha else {
                                continue
                            }

                            let rect = CGRect(
                                x: x - appearance.radius,
                                y: y - appearance.radius,
                                width: appearance.radius * 2.0,
                                height: appearance.radius * 2.0
                            )

                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(dotColor.opacity(appearance.alpha))
                            )
                        }
                    }
                }
                .onAppear {
                    phase.reset(at: timestamp)
                }
                .onChange(of: timeline.date) { _, date in
                    phase.advance(
                        sample: orientedSample,
                        timestamp: date.timeIntervalSinceReferenceDate,
                        configuration: configuration
                    )
                }
                .onChange(of: orientation) { _, _ in
                    phase.reset(at: timestamp)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func makeSafeRect(
        in size: CGSize,
        horizontalMarginRatio: CGFloat,
        verticalMarginRatio: CGFloat,
        orientation: InterfaceRenderOrientation
    ) -> CGRect {
        let effectiveHorizontalMarginRatio: CGFloat
        let effectiveVerticalMarginRatio: CGFloat

        switch orientation {
        case .portrait:
            effectiveHorizontalMarginRatio = horizontalMarginRatio
            effectiveVerticalMarginRatio = verticalMarginRatio
        case .landscapeLeft, .landscapeRight:
            effectiveHorizontalMarginRatio = verticalMarginRatio
            effectiveVerticalMarginRatio = horizontalMarginRatio
        }

        return CGRect(
            x: size.width * effectiveHorizontalMarginRatio,
            y: size.height * effectiveVerticalMarginRatio,
            width: size.width * (1.0 - (effectiveHorizontalMarginRatio * 2.0)),
            height: size.height * (1.0 - (effectiveVerticalMarginRatio * 2.0))
        )
    }

    private func safeZoneSoftWeight(
        point: CGPoint,
        coreSafeRect: CGRect,
        cornerRadius: CGFloat,
        featherWidth: CGFloat
    ) -> CGFloat {
        let distance = distanceToRoundedRect(
            point: point,
            rect: coreSafeRect,
            cornerRadius: cornerRadius
        )
        guard distance < featherWidth else {
            return 1.0
        }

        let normalized = min(max(distance / max(featherWidth, 1.0), 0.0), 1.0)
        return smootherstep(normalized)
    }

    private func roundedRectContains(point: CGPoint, rect: CGRect, cornerRadius: CGFloat) -> Bool {
        distanceToRoundedRect(point: point, rect: rect, cornerRadius: cornerRadius) <= 0.0
    }

    private func distanceToRoundedRect(
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

    private func smootherstep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0.0), 1.0)
        return clamped * clamped * clamped * (clamped * ((6.0 * clamped) - 15.0) + 10.0)
    }

    private func edgeDistanceWeight(point: CGPoint, canvasSize: CGSize, safeRect: CGRect) -> CGFloat {
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
}

private extension InterfaceRenderOrientation {
    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait:
            return 90
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        }
    }
}

private extension AVCaptureConnection {
    func applyVideoRotationAngle(_ angle: CGFloat) {
        if isVideoRotationAngleSupported(angle) {
            videoRotationAngle = angle
        }
    }
}

private extension LiveViewSceneAnalysis {
    func rotatedForDisplay(_ orientation: InterfaceRenderOrientation) -> LiveViewSceneAnalysis {
        switch orientation {
        case .portrait:
            return self
        case .landscapeLeft:
            return LiveViewSceneAnalysis(
                leadingBandLuminance: topBandLuminance,
                trailingBandLuminance: bottomBandLuminance,
                topBandLuminance: trailingBandLuminance,
                bottomBandLuminance: leadingBandLuminance,
                dominantDotPolarity: dominantDotPolarity
            )
        case .landscapeRight:
            return LiveViewSceneAnalysis(
                leadingBandLuminance: bottomBandLuminance,
                trailingBandLuminance: topBandLuminance,
                topBandLuminance: leadingBandLuminance,
                bottomBandLuminance: trailingBandLuminance,
                dominantDotPolarity: dominantDotPolarity
            )
        }
    }
}

private struct LiveViewUnavailableSurface: View {
    let style: VisualGuideStyle
    let status: AVAuthorizationStatus
    let previewState: LiveViewPreviewState

    var body: some View {
        ZStack {
            LiveViewChromeBackground()

            if shouldShowDeniedSurface {
                GlassEffectContainer(spacing: 16.0) {
                    VStack(spacing: 18.0) {
                        Text(style.title)
                            .font(.system(size: 28.0, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .multilineTextAlignment(.center)

                        Text(localized("liveview.status.denied.title"))
                            .font(.system(size: 20.0, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .frame(maxWidth: 420.0)
                        .padding(.horizontal, 22.0)
                        .padding(.vertical, 22.0)
                        .glassEffect(
                            .clear.tint(Color.black.opacity(0.36)),
                            in: .rect(cornerRadius: 30.0)
                        )
                }
                .padding(.horizontal, 24.0)
            }
        }
        .ignoresSafeArea()
    }

    private var shouldShowDeniedSurface: Bool {
        switch status {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorized:
            return false
        @unknown default:
            return false
        }
    }
}

private struct LiveViewChromeBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    Color(red: 0.012, green: 0.012, blue: 0.020)
                        .ignoresSafeArea()

                    blob(
                        color: Color(red: 0.00, green: 0.92, blue: 0.84).opacity(0.18),
                        size: width * 0.78,
                        blur: width * 0.17,
                        x: (-width * 0.12) + (sin(time * 0.17) * width * 0.06),
                        y: (-height * 0.05) + (cos(time * 0.13) * height * 0.05)
                    )

                    blob(
                        color: Color(red: 0.08, green: 0.28, blue: 1.00).opacity(0.18),
                        size: width * 0.82,
                        blur: width * 0.18,
                        x: (width * 0.14) + (cos(time * 0.14) * width * 0.06),
                        y: (height * 0.01) + (sin(time * 0.11) * height * 0.05)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.16, blue: 0.24).opacity(0.13),
                        size: width * 0.70,
                        blur: width * 0.16,
                        x: (-width * 0.02) + (sin(time * 0.16) * width * 0.05),
                        y: (height * 0.14) + (cos(time * 0.18) * height * 0.05)
                    )

                    blob(
                        color: Color.white.opacity(0.10),
                        size: width * 0.64,
                        blur: width * 0.14,
                        x: (width * 0.04) + (cos(time * 0.20) * width * 0.05),
                        y: (-height * 0.12) + (sin(time * 0.15) * height * 0.04)
                    )

                    blob(
                        color: Color(red: 1.00, green: 0.86, blue: 0.22).opacity(0.12),
                        size: width * 0.62,
                        blur: width * 0.14,
                        x: (width * 0.02) + (sin(time * 0.12) * width * 0.04),
                        y: (height * 0.26) + (cos(time * 0.14) * height * 0.04)
                    )

                    Rectangle()
                        .fill(Color.black.opacity(0.34))
                        .ignoresSafeArea()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func blob(
        color: Color,
        size: CGFloat,
        blur: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
            .blendMode(.screen)
            .offset(x: x, y: y)
    }
}
