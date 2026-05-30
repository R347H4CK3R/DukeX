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
        onGeometryChanged?("layout")
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        onGeometryChanged?("safe-area")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        onGeometryChanged?("transition-start")
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.onGeometryChanged?("transition-end")
        }
    }
}
