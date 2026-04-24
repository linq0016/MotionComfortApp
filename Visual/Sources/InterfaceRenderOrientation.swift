import MotionComfortCore
import SwiftUI
import UIKit

// 屏幕渲染方向：只保留 app 真正支持的三个界面方向。
public enum InterfaceRenderOrientation: Sendable, Equatable, Hashable {
    case portrait
    case landscapeLeft
    case landscapeRight

    public init?(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        default:
            return nil
        }
    }
}

extension MotionSample {
    // 把竖屏基准下的 sample 旋转成当前屏幕坐标系里的 sample。
    func rotatedForDisplay(_ orientation: InterfaceRenderOrientation) -> MotionSample {
        switch orientation {
        case .portrait:
            return self
        case .landscapeLeft:
            return MotionSample(
                timestamp: timestamp,
                lateralAcceleration: -longitudinalAcceleration,
                longitudinalAcceleration: lateralAcceleration,
                verticalAcceleration: verticalAcceleration
            )
        case .landscapeRight:
            return MotionSample(
                timestamp: timestamp,
                lateralAcceleration: longitudinalAcceleration,
                longitudinalAcceleration: -lateralAcceleration,
                verticalAcceleration: verticalAcceleration
            )
        }
    }
}
