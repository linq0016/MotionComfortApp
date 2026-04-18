import AVFoundation
import CoreMedia
import CoreVideo
import MotionComfortCore
import SwiftUI

// Live View：全屏相机预览加四边光流。
public struct LiveViewOverlay: View {
    let sample: MotionSample
    let style: VisualGuideStyle
    let orientation: InterfaceRenderOrientation

    @StateObject private var camera = LiveViewCameraModel()
    @State private var phase = FlowGridPhase()

    public init(
        sample: MotionSample,
        style: VisualGuideStyle = .liveView,
        orientation: InterfaceRenderOrientation = .portrait
    ) {
        self.sample = sample
        self.style = style
        self.orientation = orientation
    }

    public var body: some View {
        ZStack {
            if camera.canShowPreview {
                LiveViewCameraPreview(session: camera.session, orientation: orientation)
                    .overlay {
                        LiveViewEdgeFlowOverlay(
                            sample: sample,
                            sceneAnalysis: camera.sceneAnalysis,
                            phase: $phase,
                            orientation: orientation
                        )
                    }
            } else {
                LiveViewUnavailableSurface(
                    style: style,
                    status: camera.status,
                    previewState: camera.previewState,
                    dynamicRangeState: camera.previewDynamicRangeState
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.start()
            camera.updateOrientation(orientation)
        }
        .onDisappear {
            camera.stop()
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

enum LiveViewPreviewState: String, Sendable {
    case idle
    case starting
    case ready
    case unavailable
}

enum LiveViewDynamicRangeState: Sendable {
    case pending
    case standard

    var statusTitle: String {
        switch self {
        case .pending:
            return "PREPARING"
        case .standard:
            return "SDR"
        }
    }

    var note: String {
        switch self {
        case .pending:
            return "Camera preview is still preparing its standard dynamic range pipeline."
        case .standard:
            return "Preview is running in standard dynamic range."
        }
    }
}

final class LiveViewCameraModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var status: AVAuthorizationStatus
    @Published private(set) var isRunning = false
    @Published private(set) var previewState: LiveViewPreviewState = .idle
    @Published private(set) var previewDynamicRangeState: LiveViewDynamicRangeState = .pending
    @Published private(set) var sceneAnalysis = LiveViewSceneAnalysis()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.motioncomfort.liveview.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.motioncomfort.liveview.analysis", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var isConfigured = false
    private var latestSceneAnalysis = LiveViewSceneAnalysis()
    private var smoothedLuminance: Double?
    private var lastPolaritySwitchAt: TimeInterval?
    private var currentOrientation: InterfaceRenderOrientation = .portrait

    private let luminanceEmaAlpha = 0.18
    private let polarityHoldDuration: TimeInterval = 0.45

    override init() {
        self.status = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
    }

    var canShowPreview: Bool {
        status == .authorized && previewState == .ready && isRunning
    }

    func start() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.status = currentStatus
            self.previewDynamicRangeState = .pending
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
                    self.previewDynamicRangeState = granted ? .pending : .standard
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

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.previewState = self.status == .authorized ? .idle : .unavailable
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
            try configureVideoDevice(on: device)
            let input = try AVCaptureDeviceInput(device: device)

            guard session.canAddInput(input) else {
                return false
            }
            session.addInput(input)

            configureVideoOutput()

            DispatchQueue.main.async {
                self.previewDynamicRangeState = .standard
            }

            isConfigured = true
            return true
        } catch {
            DispatchQueue.main.async {
                self.previewDynamicRangeState = .standard
            }
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

        let desiredDuration = CMTime(value: 1, timescale: 60)
        if selectedFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 60.0 }) {
            device.activeVideoMinFrameDuration = desiredDuration
            device.activeVideoMaxFrameDuration = desiredDuration
        }
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

extension LiveViewCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
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

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let rotationAngle = orientation.videoRotationAngle
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = .resizeAspectFill
        let rotationAngle = orientation.videoRotationAngle
        if let connection = uiView.previewLayer.connection,
           connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
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
    private let safeZoneSoftInset: CGFloat = 44.0
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
                        verticalMarginRatio: configuration.verticalMarginRatio
                    )
                    let softSafeRect = coreSafeRect.insetBy(dx: -safeZoneSoftInset, dy: -safeZoneSoftInset)

                    for x in stride(from: startX, through: canvasSize.width + configuration.dotSpacing, by: configuration.dotSpacing) {
                        for y in stride(from: startY, through: canvasSize.height + configuration.dotSpacing, by: configuration.dotSpacing) {
                            let point = CGPoint(x: x, y: y)
                            if coreSafeRect.contains(point) {
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
                            let softWeight = safeZoneSoftWeight(point: point, coreSafeRect: coreSafeRect, softSafeRect: softSafeRect)
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
        verticalMarginRatio: CGFloat
    ) -> CGRect {
        CGRect(
            x: size.width * horizontalMarginRatio,
            y: size.height * verticalMarginRatio,
            width: size.width * (1.0 - (horizontalMarginRatio * 2.0)),
            height: size.height * (1.0 - (verticalMarginRatio * 2.0))
        )
    }

    private func safeZoneSoftWeight(
        point: CGPoint,
        coreSafeRect: CGRect,
        softSafeRect: CGRect
    ) -> CGFloat {
        guard softSafeRect.contains(point) else {
            return 1.0
        }

        let distanceToCore = min(
            abs(point.x - coreSafeRect.minX),
            abs(point.x - coreSafeRect.maxX),
            abs(point.y - coreSafeRect.minY),
            abs(point.y - coreSafeRect.maxY)
        )
        let normalized = min(max(distanceToCore / max(safeZoneSoftInset, 1.0), 0.0), 1.0)
        return smoothstep(normalized)
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0.0), 1.0)
        // Use smootherstep so dots fade in/out more gradually around the safe-zone edge.
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
    let dynamicRangeState: LiveViewDynamicRangeState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.10),
                    Color(red: 0.10, green: 0.12, blue: 0.15),
                    Color(red: 0.05, green: 0.06, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12.0) {
                HStack {
                    Text(style.title)
                        .font(.system(size: 26.0, weight: .bold, design: .rounded))

                    Spacer(minLength: 0.0)

                    Text(statusTitle)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .padding(.horizontal, 10.0)
                        .padding(.vertical, 6.0)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }

                Text(statusHeadline)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Text(statusNote)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Text(dynamicRangeState.note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: 420.0, alignment: .leading)
            .padding(24.0)
            .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 30.0, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30.0, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
            )
            .padding(.horizontal, 24.0)
        }
    }

    private var statusTitle: String {
        switch (status, previewState) {
        case (.authorized, .starting):
            return "STARTING"
        case (.authorized, .ready):
            return dynamicRangeState.statusTitle
        case (.authorized, .idle):
            return "READY"
        case (.authorized, .unavailable):
            return "UNAVAILABLE"
        case (.notDetermined, _):
            return "REQUEST"
        case (.denied, _):
            return "DENIED"
        case (.restricted, _):
            return "RESTRICTED"
        @unknown default:
            return "UNAVAILABLE"
        }
    }

    private var statusHeadline: String {
        switch (status, previewState) {
        case (.authorized, .starting):
            return "Starting camera preview"
        case (.authorized, .ready):
            return "Camera preview live"
        case (.authorized, .idle):
            return "Camera preview ready"
        case (.authorized, .unavailable):
            return "Camera preview unavailable"
        case (.notDetermined, _):
            return "Camera permission pending"
        case (.denied, _):
            return "Camera access denied"
        case (.restricted, _):
            return "Camera unavailable"
        @unknown default:
            return "Camera unavailable"
        }
    }

    private var statusNote: String {
        switch (status, previewState) {
        case (.authorized, .starting):
            return "The session is authorized and is still preparing the live camera preview."
        case (.authorized, .ready):
            return "The live camera preview is active, and the edge overlays are adapting to the current scene brightness."
        case (.authorized, .idle):
            return "Camera access is authorized. The live-view session will switch into the real preview as soon as the session starts."
        case (.authorized, .unavailable):
            return "Camera access is authorized, but the current device session could not start a preview feed."
        case (.notDetermined, _):
            return "The app can request camera access now. Once granted, the live-view session will switch into the real camera preview."
        case (.denied, _):
            return "Camera access is currently denied, so the live-view session stays on this placeholder."
        case (.restricted, _):
            return "Camera access is restricted or unavailable on this device session."
        @unknown default:
            return "Camera access is unavailable."
        }
    }
}
