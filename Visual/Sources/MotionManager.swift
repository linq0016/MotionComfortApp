import Combine
import CoreMotion
import Foundation
import MotionComfortCore

// 运动输入层：只负责真机传感器数据来源。
@MainActor
public final class MotionManager: ObservableObject {
    @Published public private(set) var sample: MotionSample
    @Published public private(set) var isRunning: Bool

    private let motionManager: CMMotionManager
    private var samplingTask: Task<Void, Never>?

    public init(motionManager: CMMotionManager = CMMotionManager()) {
        self.motionManager = motionManager
        self.sample = .neutral
        self.isRunning = false
    }

    public func start() {
        stop()
        startRealTimeMotion()
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        samplingTask?.cancel()
        samplingTask = nil
        isRunning = false
    }

    // 读取 deviceMotion 的实时数据，并持续产出 MotionSample。
    private func startRealTimeMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }

        // 三种视觉模式的渲染上限为 60 帧，采样与轮询间隔与其保持一致。
        let updateInterval = 1.0 / 60.0
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates()
        isRunning = true

        samplingTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if let motion = self.motionManager.deviceMotion {
                    let next = MotionSample(
                        lateralAcceleration: motion.userAcceleration.x,
                        longitudinalAcceleration: -motion.userAcceleration.y,
                        verticalAcceleration: motion.userAcceleration.z
                    )

                    self.sample = next
                }

                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}
