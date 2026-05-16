import UIKit

final class NativeMetalPresenterHost {
    private var window: UIWindow?
    private var rootController: NativeMetalPresenterViewController?
    private var presenterView: NativeMetalPresenterView?
    private var statsHUDView: StatsHUDView?
    private var exitOverlayView: GameplayExitOverlayView?

    func start(
        session: NativeMetalPresenterSession,
        onExitRequested: @escaping () -> Void
    ) -> UnsafeMutableRawPointer? {
        guard let scene = Self.activeWindowScene() else {
            NSLog("Native Metal presenter could not find a foreground UIWindowScene")
            return nil
        }

        let rootController = NativeMetalPresenterViewController()
        rootController.view.backgroundColor = .black

        let presenterView = NativeMetalPresenterView(frame: scene.screen.bounds)
        presenterView.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.addSubview(presenterView)
        let tapGesture = UITapGestureRecognizer()
        presenterView.addGestureRecognizer(tapGesture)
        NSLayoutConstraint.activate([
            presenterView.leadingAnchor.constraint(equalTo: rootController.view.leadingAnchor),
            presenterView.trailingAnchor.constraint(equalTo: rootController.view.trailingAnchor),
            presenterView.topAnchor.constraint(equalTo: rootController.view.topAnchor),
            presenterView.bottomAnchor.constraint(equalTo: rootController.view.bottomAnchor),
        ])

        if Self.statsHUDEnabled {
            let statsHUDView = StatsHUDView()
            statsHUDView.translatesAutoresizingMaskIntoConstraints = false
            rootController.view.addSubview(statsHUDView)
            NSLayoutConstraint.activate([
                statsHUDView.leadingAnchor.constraint(equalTo: rootController.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                statsHUDView.topAnchor.constraint(equalTo: rootController.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            ])
            self.statsHUDView = statsHUDView
        }

        let exitOverlayView = GameplayExitOverlayView(
            session: session,
            onExitRequested: onExitRequested
        )
        exitOverlayView.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.addSubview(exitOverlayView)
        NSLayoutConstraint.activate([
            exitOverlayView.leadingAnchor.constraint(equalTo: rootController.view.leadingAnchor),
            exitOverlayView.trailingAnchor.constraint(equalTo: rootController.view.trailingAnchor),
            exitOverlayView.topAnchor.constraint(equalTo: rootController.view.topAnchor),
            exitOverlayView.bottomAnchor.constraint(equalTo: rootController.view.bottomAnchor),
        ])
        tapGesture.addTarget(exitOverlayView, action: #selector(GameplayExitOverlayView.toggle))
        self.exitOverlayView = exitOverlayView

        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = UIWindow.Level(UIWindow.Level.alert.rawValue - 1)
        window.backgroundColor = .black
        window.rootViewController = rootController
        window.isHidden = false
        window.makeKeyAndVisible()

        rootController.view.setNeedsLayout()
        rootController.view.layoutIfNeeded()
        presenterView.configureMetalLayer()

        self.window = window
        self.rootController = rootController
        self.presenterView = presenterView

        let layer = presenterView.metalLayer
        NSLog(
            "Native Metal presenter layer=0x%llx drawable=%.0fx%.0f bounds=%.0fx%.0f scale=%.2f device=%@",
            UInt64(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque())),
            layer.drawableSize.width,
            layer.drawableSize.height,
            layer.bounds.width,
            layer.bounds.height,
            layer.contentsScale,
            layer.device?.name ?? "(nil)"
        )
        return Unmanaged.passUnretained(layer).toOpaque()
    }

    func stop() {
        window?.isHidden = true
        exitOverlayView?.removeFromSuperview()
        exitOverlayView = nil
        statsHUDView?.removeFromSuperview()
        statsHUDView = nil
        presenterView?.removeFromSuperview()
        presenterView = nil
        rootController = nil
        window = nil
        NSLog("Native Metal presenter stopped")
    }

    private static var statsHUDEnabled: Bool {
        UserDefaults.standard.object(forKey: "DukeXStatsHUDEnabled") as? Bool ?? true
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ??
            scenes.first { $0.activationState == .foregroundInactive } ??
            scenes.first
    }
}
