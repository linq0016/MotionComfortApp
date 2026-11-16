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

// Y 平面的读取方式：每个样本的字节数、有效位右移量，以及黑白电平。
private struct LiveViewLumaLayout {
    let bytesPerSample: Int
    let shift: UInt16
    let blackLevel: Double
    let whiteLevel: Double

    // 可直接按像素读取 Y 平面的格式，不含压缩格式。
    static let supportedPixelFormatTypes: [OSType] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarFullRange
    ]

    static func layout(for pixelFormatType: OSType) -> LiveViewLumaLayout? {
        switch pixelFormatType {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return LiveViewLumaLayout(bytesPerSample: 1, shift: 0, blackLevel: 16.0, whiteLevel: 235.0)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return LiveViewLumaLayout(bytesPerSample: 1, shift: 0, blackLevel: 0.0, whiteLevel: 255.0)
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange:
            return LiveViewLumaLayout(bytesPerSample: 2, shift: 6, blackLevel: 64.0, whiteLevel: 940.0)
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange, kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
            return LiveViewLumaLayout(bytesPerSample: 2, shift: 6, blackLevel: 0.0, whiteLevel: 1023.0)
        default:
            return nil
        }
    }
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

// 相机参数分为采集规格和亮度分析两组；分析结果决定叠加点阵使用明点还是暗点。
private struct LiveViewCameraConfiguration: Sendable {
    var capture = LiveViewCaptureConfiguration()
    var analysis = LiveViewAnalysisConfiguration()
}

private struct LiveViewFormatProfile: Sendable {
    var width: Int
    var height: Int
    var colorSpace: AVCaptureColorSpace
}

// 采集参数包含目标帧率、首选与备用格式、session preset；格式指定分辨率与色域。
private struct LiveViewCaptureConfiguration: Sendable {
    var targetFrameDuration = CMTime(value: 1, timescale: 60)
    var preferredFormatProfile = LiveViewFormatProfile(
        width: 1920,
        height: 1080,
        colorSpace: .HLG_BT2020
    )
    var fallbackFormatProfile = LiveViewFormatProfile(
        width: 1280,
        height: 720,
        colorSpace: .P3_D65
    )
    var fallbackPresets: [AVCaptureSession.Preset] = [.inputPriority, .hd1280x720, .high]
}

private struct LiveViewAnalysisConfiguration: Sendable {
    var luminanceEmaAlpha = 0.18
    var polarityHoldDuration: TimeInterval = 0.45
    var horizontalBandRatio = 0.18
    var verticalBandRatio = 0.14
    var minimumBandSize = 40
    var strideDivisor = 72
    var minimumStride = 6
    var lightThreshold = 0.42
    var darkThreshold = 0.50
}

public final class LiveViewCameraModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published public private(set) var status: AVAuthorizationStatus
    @Published public private(set) var isRunning = false
    @Published public private(set) var previewState: LiveViewPreviewState = .idle
    @Published private(set) var overlayRenderState = LiveViewOverlayRenderState()

    let session = AVCaptureSession()

    // 采集配置与启停在 sessionQueue 调度；视频帧分析回调与分析状态的读写都在 analysisQueue 执行。
    private let sessionQueue = DispatchQueue(label: "com.motioncomfort.liveview.session", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "com.motioncomfort.liveview.analysis", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var isConfigured = false
    private var latestOverlayRenderState = LiveViewOverlayRenderState()
    private var smoothedLuminance: Double?
    private var lastPolaritySwitchAt: TimeInterval?
    private var sessionStartReferenceTime: TimeInterval?
    private var currentOrientation: InterfaceRenderOrientation = .portrait

    private let configuration = LiveViewCameraConfiguration()

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

            self.analysisQueue.async {
                self.sessionStartReferenceTime = nil
                self.latestOverlayRenderState = LiveViewOverlayRenderState()
                self.smoothedLuminance = nil
                self.lastPolaritySwitchAt = nil
            }
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.previewState = self.status == .authorized ? .idle : .unavailable
            self.overlayRenderState = LiveViewOverlayRenderState()
        }
    }

    // 分析用的视频帧保持传感器原始方向；方向只用于换算亮度条带，预览的旋转由预览层自己处理。
    func updateOrientation(_ orientation: InterfaceRenderOrientation) {
        analysisQueue.async { [weak self] in
            self?.currentOrientation = orientation
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

            let startReferenceTime = Date().timeIntervalSinceReferenceDate
            self.analysisQueue.async {
                self.sessionStartReferenceTime = startReferenceTime
                self.lastPolaritySwitchAt = nil
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

        session.automaticallyConfiguresCaptureDeviceForWideColor = false

        if let preset = configuration.capture.fallbackPresets.first(where: { session.canSetSessionPreset($0) }) {
            session.sessionPreset = preset
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

            configureVideoOutput(for: device)
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
        guard let selection = bestFormat(for: device) else {
            return
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = selection.format
        configureHDRPreviewOnLockedDevice(device, matchedProfile: selection.matchedProfile)
        applyTargetFrameDurationOnLockedDevice(device)
    }

    private func configureHDRPreviewOnLockedDevice(
        _ device: AVCaptureDevice,
        matchedProfile: LiveViewFormatProfile?
    ) {
        guard let matchedProfile else {
            return
        }

        // HLG 格式的高动态范围始终开启，没有 EDR 开关；对不支持 EDR 的格式设置 isVideoHDREnabled 会抛异常。
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = true
        }

        if device.activeFormat.supportedColorSpaces.contains(matchedProfile.colorSpace) {
            device.activeColorSpace = matchedProfile.colorSpace
        }
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
        device.activeVideoMinFrameDuration = configuration.capture.targetFrameDuration
        device.activeVideoMaxFrameDuration = configuration.capture.targetFrameDuration
    }

    private func bestFormat(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, matchedProfile: LiveViewFormatProfile?)? {
        if let selectedFormat = format(for: configuration.capture.preferredFormatProfile, device: device) {
            return (selectedFormat, configuration.capture.preferredFormatProfile)
        }

        if let selectedFormat = format(for: configuration.capture.fallbackFormatProfile, device: device) {
            return (selectedFormat, configuration.capture.fallbackFormatProfile)
        }

        return legacyBestFormat(for: device).map { ($0, nil) }
    }

    private func format(
        for profile: LiveViewFormatProfile,
        device: AVCaptureDevice
    ) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
            // HLG 10-bit 格式自带高动态范围，系统对它的 isVideoHDRSupported 恒为 false；其余色域才要求支持 EDR。
            let supportsProfileDynamicRange = profile.colorSpace == .HLG_BT2020 || format.isVideoHDRSupported
            return Int(dimensions.width) == profile.width
                && Int(dimensions.height) == profile.height
                && maxFrameRate >= 60.0
                && supportsProfileDynamicRange
                && format.supportedColorSpaces.contains(profile.colorSpace)
                && format.isVideoStabilizationModeSupported(.previewOptimized)
        }

        return candidates.min { lhs, rhs in
            frameRateDistance(fromTarget: lhs) < frameRateDistance(fromTarget: rhs)
        }
    }

    private func legacyBestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
            return dimensions.width == 1280
                && dimensions.height == 720
                && maxFrameRate >= 60.0
        }

        return candidates.min { lhs, rhs in
            frameRateDistance(fromTarget: lhs) < frameRateDistance(fromTarget: rhs)
        }
    }

    private func frameRateDistance(fromTarget format: AVCaptureDevice.Format) -> Double {
        let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
        return abs(maxFrameRate - 60.0)
    }

    private func configureVideoOutput(for device: AVCaptureDevice) {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)

        guard session.canAddOutput(videoOutput) else {
            return
        }

        session.addOutput(videoOutput)
        // 这一路只用于亮度分析，不设防抖；防抖设在预览连接上。
        applyAnalysisPixelFormat(for: device)
    }

    // 亮度分析直接读取 Y 平面：相机原生格式可直读时用原生格式，系统不做整帧转换。
    private func applyAnalysisPixelFormat(for device: AVCaptureDevice) {
        let nativeType = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
        let availableTypes = videoOutput.availableVideoPixelFormatTypes
        let supportedTypes = LiveViewLumaLayout.supportedPixelFormatTypes
        let pixelFormatType = ([nativeType] + supportedTypes).first { type in
            supportedTypes.contains(type) && availableTypes.contains(type)
        }

        guard let pixelFormatType else {
            return
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormatType
        ]
    }

    // 统计画面四边的平均亮度，返回点阵应使用的明暗模式。
    private func analyze(pixelBuffer: CVPixelBuffer) -> LiveViewDotPolarity {
        let previousPolarity = latestOverlayRenderState.dominantDotPolarity

        guard let lumaLayout = LiveViewLumaLayout.layout(for: CVPixelBufferGetPixelFormatType(pixelBuffer)) else {
            return previousPolarity
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return previousPolarity
        }

        // 视频帧是横向的传感器原始方向：竖屏显示时，屏幕左右两边对应帧的上下两边，条带比例随之互换。
        let isPortrait = currentOrientation == .portrait
        let bandRatioX = isPortrait ? configuration.analysis.verticalBandRatio : configuration.analysis.horizontalBandRatio
        let bandRatioY = isPortrait ? configuration.analysis.horizontalBandRatio : configuration.analysis.verticalBandRatio
        let bandWidth = max(Int(Double(width) * bandRatioX), configuration.analysis.minimumBandSize)
        let bandHeight = max(Int(Double(height) * bandRatioY), configuration.analysis.minimumBandSize)
        let strideX = max(width / configuration.analysis.strideDivisor, configuration.analysis.minimumStride)
        let strideY = max(height / configuration.analysis.strideDivisor, configuration.analysis.minimumStride)

        let leadingLuminance = averageLuminance(
            baseAddress: baseAddress,
            lumaLayout: lumaLayout,
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
            lumaLayout: lumaLayout,
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
            lumaLayout: lumaLayout,
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
            lumaLayout: lumaLayout,
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

        return updatedPolarity(
            for: filteredLuminance,
            previous: previousPolarity,
            timestamp: sessionRelativeTimestamp()
        )
    }

    private func applyLuminanceSmoothing(_ luminance: Double) -> Double {
        guard let previous = smoothedLuminance else {
            smoothedLuminance = luminance
            return luminance
        }

        let filtered = (previous * (1.0 - configuration.analysis.luminanceEmaAlpha)) + (luminance * configuration.analysis.luminanceEmaAlpha)
        smoothedLuminance = filtered
        return filtered
    }

    private func averageLuminance(
        baseAddress: UnsafeMutableRawPointer,
        lumaLayout: LiveViewLumaLayout,
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
                let sample = row.advanced(by: x * lumaLayout.bytesPerSample)
                if lumaLayout.bytesPerSample == 1 {
                    sum += Double(sample.load(as: UInt8.self))
                } else {
                    sum += Double(sample.loadUnaligned(as: UInt16.self) >> lumaLayout.shift)
                }
                count += 1.0
            }
        }

        guard count > 0.0 else {
            return 0.0
        }

        // 按格式的黑白电平归一化到 0...1。
        let normalized = ((sum / count) - lumaLayout.blackLevel) / (lumaLayout.whiteLevel - lumaLayout.blackLevel)
        return min(max(normalized, 0.0), 1.0)
    }

    private func sessionRelativeTimestamp() -> TimeInterval {
        guard let sessionStartReferenceTime else {
            return 0.0
        }

        return Date().timeIntervalSinceReferenceDate - sessionStartReferenceTime
    }

    private func updatedPolarity(
        for luminance: Double,
        previous: LiveViewDotPolarity,
        timestamp: TimeInterval
    ) -> LiveViewDotPolarity {
        if let lastSwitchAt = lastPolaritySwitchAt,
           timestamp - lastSwitchAt < configuration.analysis.polarityHoldDuration {
            return previous
        }

        let next: LiveViewDotPolarity
        switch previous {
        case .light:
            next = luminance > configuration.analysis.darkThreshold ? .dark : .light
        case .dark:
            next = luminance < configuration.analysis.lightThreshold ? .light : .dark
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

// 从视频帧提取场景亮度，点阵明暗模式变化时发布给主线程界面。
extension LiveViewCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let nextRenderState = LiveViewOverlayRenderState(
            dominantDotPolarity: analyze(pixelBuffer: pixelBuffer)
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

// 将 AVCaptureVideoPreviewLayer 嵌入 SwiftUI，并同步预览方向、防抖与动态范围。
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
        private var hasAppliedStabilization = false
        private var appliedDynamicRange: CALayer.DynamicRange?
        private let preferredPreviewDynamicRange: CALayer.DynamicRange = .constrainedHigh

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
               appliedRotationAngle == rotationAngle,
               hasAppliedStabilization,
               appliedDynamicRange == preferredPreviewDynamicRange {
                return
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if appliedSession !== session {
                previewLayer.session = session
                appliedSession = session
                hasAppliedStabilization = false
            }

            if previewLayer.videoGravity != .resizeAspectFill {
                previewLayer.videoGravity = .resizeAspectFill
            }

            if appliedDynamicRange != preferredPreviewDynamicRange {
                previewLayer.preferredDynamicRange = preferredPreviewDynamicRange
                appliedDynamicRange = preferredPreviewDynamicRange
            }

            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(rotationAngle),
               appliedRotationAngle != rotationAngle {
                connection.videoRotationAngle = rotationAngle
                appliedRotationAngle = rotationAngle
            }

            // 防抖作用在用户看到的预览上。预览连接只接受 preview 级，电影级在这条连接上不生效。
            if let connection = previewLayer.connection, !hasAppliedStabilization {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .previewOptimized
                }
                hasAppliedStabilization = true
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
                    let normA = min(flowState.smoothedMagnitude / configuration.motion.maxAccelThreshold, 1.0)
                    let dotColor = renderState.dominantDotPolarity.color
                    let wrappedOffsetX = flowWrappedOffset(flowState.offset.x, spacing: configuration.layout.dotSpacing)
                    let wrappedOffsetY = flowWrappedOffset(flowState.offset.y, spacing: configuration.layout.dotSpacing)
                    let cellOffsetX = flowIntegralCellOffset(flowState.offset.x, spacing: configuration.layout.dotSpacing)
                    let cellOffsetY = flowIntegralCellOffset(flowState.offset.y, spacing: configuration.layout.dotSpacing)

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

                        appearance.radius += pow(edgeWeight, configuration.appearance.edgeRadiusCurve) * configuration.appearance.edgeRadiusBoost
                        let softWeight = safeZoneSoftWeight(
                            point: point,
                            coreSafeRect: layout.safeRect,
                            cornerRadius: layout.safeZoneCornerRadius,
                            featherWidth: configuration.safeZone.featherWidth
                        )
                        appearance.alpha *= Double(softWeight)
                        appearance.radius *= 1.0 - (safeZoneSoftRadiusAttenuation * (1.0 - softWeight))

                        guard appearance.alpha > configuration.appearance.minimumVisibleAlpha else {
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
