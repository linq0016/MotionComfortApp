import Combine
import CoreMotion
import Foundation
import MotionComfortCore

// 运动输入层：只负责真机传感器和 demo 两种数据来源。
@MainActor
public final class MotionManager: ObservableObject {
    @Published public private(set) var sample: MotionSample
    @Published public private(set) var isRunning: Bool
    @Published public private(set) var activeMode: MotionInputMode?
    @Published public private(set) var isLiveMotionAvailable: Bool

    private let motionManager: CMMotionManager
    private var samplingTask: Task<Void, Never>?
    private var demoStartTime: TimeInterval?

    public init(motionManager: CMMotionManager = CMMotionManager()) {
        self.motionManager = motionManager
        self.sample = .neutral
        self.isRunning = false
        self.activeMode = nil
        self.isLiveMotionAvailable = motionManager.isDeviceMotionAvailable
    }

    public func start(mode: MotionInputMode) {
        stop()
        activeMode = mode
        isLiveMotionAvailable = motionManager.isDeviceMotionAvailable

        switch mode {
        case .realTime:
            startRealTimeMotion()
        case .demo:
            startDemoMode()
        }
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        samplingTask?.cancel()
        samplingTask = nil
        demoStartTime = nil
        activeMode = nil
        isRunning = false
    }

    // 读取 deviceMotion 的实时数据，并持续产出 MotionSample。
    private func startRealTimeMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
        isRunning = true

        samplingTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.activeMode == .realTime {
                if let motion = self.motionManager.deviceMotion {
                    let next = MotionSample(
                        timestamp: Date().timeIntervalSince1970,
                        lateralAcceleration: motion.userAcceleration.x,
                        longitudinalAcceleration: -motion.userAcceleration.y,
                        verticalAcceleration: motion.userAcceleration.z,
                        pitch: motion.attitude.pitch,
                        roll: motion.attitude.roll,
                        yawRate: motion.rotationRate.z
                    )

                    self.sample = next
                }

                try? await Task.sleep(for: .seconds(1.0 / 60.0))
            }
        }
    }

    // 生成内置的模拟运动数据，方便演示和调参。
    private func startDemoMode() {
        samplingTask?.cancel()
        samplingTask = nil
        demoStartTime = Date().timeIntervalSince1970
        isRunning = true

        samplingTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.activeMode == .demo {
                guard let start = self.demoStartTime else {
                    return
                }

                let elapsed = Date().timeIntervalSince1970 - start
                let next = MotionSample(
                    timestamp: Date().timeIntervalSince1970,
                    lateralAcceleration: sin(elapsed * 1.35) * 0.34,
                    longitudinalAcceleration: cos(elapsed * 0.92) * 0.22,
                    verticalAcceleration: sin(elapsed * 2.1) * 0.08,
                    pitch: sin(elapsed * 0.40) * 0.14,
                    roll: cos(elapsed * 0.52) * 0.24,
                    yawRate: sin(elapsed * 1.15) * 1.0
                )

                self.sample = next
                try? await Task.sleep(for: .seconds(1.0 / 30.0))
            }
        }
    }
}
