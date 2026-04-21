import MotionComfortVisual
import SwiftUI
import UIKit

// 全局方向观察器：把当前 scene 的界面方向同步给 SwiftUI。
@MainActor
final class InterfaceOrientationObserver: ObservableObject {
    @Published private(set) var orientation: InterfaceRenderOrientation = .portrait

    func update(from interfaceOrientation: UIInterfaceOrientation) {
        guard let next = InterfaceRenderOrientation(interfaceOrientation) else {
            return
        }

        if next != orientation {
            orientation = next
        }
    }
}

// 方向探针：从 UIWindowScene 持续读取当前 app 的界面方向。
struct InterfaceOrientationReader: UIViewControllerRepresentable {
    @ObservedObject var observer: InterfaceOrientationObserver

    func makeUIViewController(context: Context) -> OrientationReaderController {
        let controller = OrientationReaderController()
        controller.observer = observer
        return controller
    }

    func updateUIViewController(_ uiViewController: OrientationReaderController, context: Context) {
        uiViewController.observer = observer
        uiViewController.scheduleCurrentOrientationReport()
    }
}

final class OrientationReaderController: UIViewController {
    weak var observer: InterfaceOrientationObserver?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleCurrentOrientationReport()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        scheduleCurrentOrientationReport()

        coordinator.animate(alongsideTransition: nil) { _ in
            self.scheduleCurrentOrientationReport()
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        scheduleCurrentOrientationReport()
    }

    func scheduleCurrentOrientationReport() {
        guard let observer else {
            return
        }

        let sceneOrientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.effectiveGeometry.interfaceOrientation

        if let sceneOrientation {
            Task { @MainActor [weak observer] in
                guard let observer else { return }
                observer.update(from: sceneOrientation)
            }
        }
    }
}
