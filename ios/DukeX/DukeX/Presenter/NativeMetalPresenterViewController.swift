import UIKit

final class NativeMetalPresenterViewController: UIViewController {
    var onGeometryChanged: ((String) -> Void)?

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        NativeMetalDiagnostics.log(
            "VC_LAYOUT",
            "bounds=\(NativeMetalDiagnostics.rect(view.bounds)) safe=\(NativeMetalDiagnostics.insets(view.safeAreaInsets))"
        )
        onGeometryChanged?("layout")
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        NativeMetalDiagnostics.log(
            "VC_SAFE_AREA",
            "bounds=\(NativeMetalDiagnostics.rect(view.bounds)) safe=\(NativeMetalDiagnostics.insets(view.safeAreaInsets))"
        )
        onGeometryChanged?("safe-area")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        NativeMetalDiagnostics.log(
            "VC_TRANSITION_START",
            "target=\(NativeMetalDiagnostics.rect(CGRect(origin: .zero, size: size))) current=\(NativeMetalDiagnostics.rect(view.bounds)) coordinatorAnimated=\(coordinator.isAnimated ? 1 : 0)"
        )
        onGeometryChanged?("transition-start")
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            if let self {
                NativeMetalDiagnostics.log(
                    "VC_TRANSITION_END",
                    "bounds=\(NativeMetalDiagnostics.rect(self.view.bounds)) safe=\(NativeMetalDiagnostics.insets(self.view.safeAreaInsets))"
                )
            }
            self?.onGeometryChanged?("transition-end")
        }
    }
}
