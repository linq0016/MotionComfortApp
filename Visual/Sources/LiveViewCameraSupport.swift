import AVFoundation
import CoreMedia
import CoreVideo
import MotionComfortCore
import SwiftUI

private func localized(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}

// Live View：全屏相机预览加四边光流。
public struct LiveViewOverlay: View {
    let sample: MotionSample
    let style: VisualGuideStyle
    let orientation: InterfaceRenderOrientation
    let motionSensitivityFactor: Double

    @ObservedObject private var camera: LiveViewCameraModel
    @State private var phase = FlowGridPhase()

    public init(
        sample: MotionSample,
        style: VisualGuideStyle = .liveView,
        orientation: InterfaceRenderOrientation = .portrait,
        motionSensitivityFactor: Double = 1.0,
        camera: LiveViewCameraModel = LiveViewCameraModel()
    ) {
        self.sample = sample
        self.style = style
        self.orientation = orientation
        self.motionSensitivityFactor = motionSensitivityFactor
        self._camera = ObservedObject(wrappedValue: camera)
    }

    public var body: some View {
        ZStack {
            if camera.canShowPreview {
                LiveViewPreviewSurface(session: camera.session, orientation: orientation)
                    .overlay {
                        LiveViewEdgeFlowOverlay(
                            sample: sample,
                            renderState: camera.overlayRenderState,
                            phase: $phase,
                            orientation: orientation,
                            motionSensitivityFactor: motionSensitivityFactor
                        )
                    }
            } else {
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

enum LiveViewDotPolarity: Sendable, Equatable {
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

struct LiveViewOverlayRenderState: Equatable, Sendable {
    var dominantDotPolarity: LiveViewDotPolarity = .light
}

public enum LiveViewPreviewState: String, Sendable {
    case idle
    case starting
    case ready
    case unavailable
}

public final class LiveViewCameraModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published public private(set) var status: AVAuthorizationStatus
    @Published public private(set) var isRunning = false
    @Published public private(set) var previewState: LiveViewPreviewState = .idle
    @Published private(set) var overlayRenderState = LiveViewOverlayRenderState()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.motioncomfort.liveview.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.motioncomfort.liveview.analysis", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var isConfigured = false
    private var latestSceneAnalysis = LiveViewSceneAnalysis()
    private var latestOverlayRenderState = LiveViewOverlayRenderState()
    private var smoothedLuminance: Double?
    private var lastPolaritySwitchAt: TimeInterval?
    private var currentOrientation: InterfaceRenderOrientation = .portrait

    private let luminanceEmaAlpha = 0.18
    private let polarityHoldDuration: TimeInterval = 0.45
    private let targetFrameDuration = CMTime(value: 1, timescale: 60)

    public override init() {
        self.status = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
    }

    public var canShowPreview: Bool {
        status == .authorized && previewState == .ready && isRunning
    }

    public func start() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.status = currentStatus
            if currentStatus == .authorized {
                self.previewState = .starting
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
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.latestSceneAnalysis = LiveViewSceneAnalysis()
            self.latestOverlayRenderState = LiveViewOverlayRenderState()
            self.smoothedLuminance = nil
            self.lastPolaritySwitchAt = nil
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.previewState = self.status == .authorized ? .idle : .unavailable
            self.overlayRenderState = LiveViewOverlayRenderState()
        }
    }

    func updateOrientation(_ orientation: InterfaceRenderOrientation) {
        analysisQueue.async { [weak self] in
            self?.currentOrientation = orientation
        }

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            let rotationAngle = orientation.videoRotationAngle
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }
    }

    private func configureAndRunIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if !self.isConfigured {
                guard self.configureSession() else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.previewState = .unavailable
                    }
                    return
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

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

        session.automaticallyConfiguresCaptureDeviceForWideColor = true

        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        } else if session.canSetSessionPreset(.hd1280x720) {
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
            try configureVideoDevice(on: device)
            let input = try AVCaptureDeviceInput(device: device)

            guard session.canAddInput(input) else {
                return false
            }
            session.addInput(input)

            configureVideoOutput()
            try applyTargetFrameDuration(on: device)

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

    private func configureVideoDevice(on device: AVCaptureDevice) throws {
        guard let selectedFormat = bestFormat(for: device) else {
            return
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = selectedFormat
        applyTargetFrameDurationOnLockedDevice(device)
    }

    private func applyTargetFrameDuration(on device: AVCaptureDevice) throws {
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 60.0 }) else {
            return
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        applyTargetFrameDurationOnLockedDevice(device)
    }

    private func applyTargetFrameDurationOnLockedDevice(_ device: AVCaptureDevice) {
        device.activeVideoMinFrameDuration = targetFrameDuration
        device.activeVideoMaxFrameDuration = targetFrameDuration
    }

    private func bestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let targetWidth = 1280
        let targetHeight = 720

        return device.formats.max { lhs, rhs in
            formatScore(lhs, targetWidth: targetWidth, targetHeight: targetHeight)
                < formatScore(rhs, targetWidth: targetWidth, targetHeight: targetHeight)
        }
    }

    private func formatScore(
        _ format: AVCaptureDevice.Format,
        targetWidth: Int,
        targetHeight: Int
    ) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let maxFrameRate = Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0)
        let supports60fps = maxFrameRate >= 60 ? 1 : 0
        let mediumResolution = (960...1920).contains(Int(dimensions.width)) ? 1 : 0
        let distancePenalty = abs(Int(dimensions.width) - targetWidth) + abs(Int(dimensions.height) - targetHeight)

        return (supports60fps * 1_000_000)
            + (mediumResolution * 100_000)
            + (maxFrameRate * 10)
            - distancePenalty
    }

    private func configureVideoOutput() {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)

        guard session.canAddOutput(videoOutput) else {
            return
        }

        session.addOutput(videoOutput)
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

        return rawAnalysis.rotatedForDisplay(currentOrientation)
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
        let nextRenderState = LiveViewOverlayRenderState(
            dominantDotPolarity: nextAnalysis.dominantDotPolarity
        )

        guard nextRenderState != latestOverlayRenderState else {
            return
        }

        latestOverlayRenderState = nextRenderState

        DispatchQueue.main.async {
            guard self.overlayRenderState != nextRenderState else {
                return
            }

            self.overlayRenderState = nextRenderState
        }
    }
}

private struct LiveViewPreviewSurface: View {
    let session: AVCaptureSession
    let orientation: InterfaceRenderOrientation

    var body: some View {
        LiveViewCameraPreview(session: session, orientation: orientation)
    }
}

private struct LiveViewCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: InterfaceRenderOrientation

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.configure(session: session, orientation: orientation)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.configure(session: session, orientation: orientation)
    }

    final class PreviewView: UIView {
        private weak var appliedSession: AVCaptureSession?
        private var appliedRotationAngle: CGFloat?

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        func configure(session: AVCaptureSession, orientation: InterfaceRenderOrientation) {
            let rotationAngle = orientation.videoRotationAngle

            if appliedSession === session,
               previewLayer.videoGravity == .resizeAspectFill,
               appliedRotationAngle == rotationAngle {
                return
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if appliedSession !== session {
                previewLayer.session = session
                appliedSession = session
            }

            if previewLayer.videoGravity != .resizeAspectFill {
                previewLayer.videoGravity = .resizeAspectFill
            }

            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(rotationAngle),
               appliedRotationAngle != rotationAngle {
                connection.videoRotationAngle = rotationAngle
                appliedRotationAngle = rotationAngle
            }

            CATransaction.commit()
        }
    }
}

// Live View 的四边点阵：复用 Minimal 的连续光流手感。
private struct LiveViewEdgeFlowOverlay: View {
    let sample: MotionSample
    let renderState: LiveViewOverlayRenderState
    @Binding var phase: FlowGridPhase
    let orientation: InterfaceRenderOrientation
    let motionSensitivityFactor: Double

    private let configuration = FlowGridConfiguration.liveViewEdge
    private let safeZoneSoftRadiusAttenuation: CGFloat = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let timestamp = timeline.date.timeIntervalSinceReferenceDate
                let orientedSample = sample.rotatedForDisplay(orientation)
                let layout = FlowGridLayoutCache.shared.layout(
                    size: proxy.size,
                    configuration: configuration,
                    orientation: orientation
                )

                Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                    let flowState = phase.renderState
                    let normA = min(flowState.smoothedMagnitude / configuration.maxAccelThreshold, 1.0)
                    let dotColor = renderState.dominantDotPolarity.color
                    let wrappedOffsetX = flowWrappedOffset(flowState.offset.x, spacing: configuration.dotSpacing)
                    let wrappedOffsetY = flowWrappedOffset(flowState.offset.y, spacing: configuration.dotSpacing)
                    let cellOffsetX = flowIntegralCellOffset(flowState.offset.x, spacing: configuration.dotSpacing)
                    let cellOffsetY = flowIntegralCellOffset(flowState.offset.y, spacing: configuration.dotSpacing)

                    for staticPoint in layout.points {
                        let point = CGPoint(
                            x: staticPoint.basePosition.x + wrappedOffsetX,
                            y: staticPoint.basePosition.y + wrappedOffsetY
                        )
                        if flowRoundedRectContains(
                            point: point,
                            rect: layout.safeRect,
                            cornerRadius: layout.safeZoneCornerRadius
                        ) {
                            continue
                        }

                        let hash = flowPseudoRandom(
                            gridX: staticPoint.gridX - cellOffsetX,
                            gridY: staticPoint.gridY - cellOffsetY
                        )
                        let edgeWeight = flowEdgeDistanceWeight(
                            point: point,
                            canvasSize: canvasSize,
                            safeRect: layout.safeRect
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
                            coreSafeRect: layout.safeRect,
                            cornerRadius: layout.safeZoneCornerRadius,
                            featherWidth: configuration.safeZoneFeatherWidth
                        )
                        appearance.alpha *= Double(softWeight)
                        appearance.radius *= 1.0 - (safeZoneSoftRadiusAttenuation * (1.0 - softWeight))

                        guard appearance.alpha > configuration.minimumVisibleAlpha else {
                            continue
                        }

                        let rect = CGRect(
                            x: point.x - appearance.radius,
                            y: point.y - appearance.radius,
                            width: appearance.radius * 2.0,
                            height: appearance.radius * 2.0
                        )

                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(dotColor.opacity(appearance.alpha))
                        )
                    }
                }
                .onAppear {
                    phase.reset(at: timestamp)
                }
                .onChange(of: timeline.date) { _, date in
                    phase.advance(
                        sample: orientedSample,
                        timestamp: date.timeIntervalSinceReferenceDate,
                        configuration: configuration,
                        motionSensitivityFactor: motionSensitivityFactor
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

    private func safeZoneSoftWeight(
        point: CGPoint,
        coreSafeRect: CGRect,
        cornerRadius: CGFloat,
        featherWidth: CGFloat
    ) -> CGFloat {
        let distance = flowDistanceToRoundedRect(
            point: point,
            rect: coreSafeRect,
            cornerRadius: cornerRadius
        )
        guard distance < featherWidth else {
            return 1.0
        }

        let normalized = min(max(distance / max(featherWidth, 1.0), 0.0), 1.0)
        return flowSmootherstep(normalized)
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
