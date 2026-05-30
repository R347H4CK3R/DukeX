import UIKit

final class NativeMetalPresenterHost {
    private var window: NativeMetalPresenterWindow?
    private var rootController: NativeMetalPresenterViewController?
    private var presenterView: NativeMetalPresenterView?
    private var exitOverlayView: GameplayExitOverlayView?
    private var orientationObserver: NSObjectProtocol?
    private var geometryDisplayLink: CADisplayLink?
    private var lastLoggedGeometry: CGSize = .zero
    private var isSyncingGeometry = false

    func start(
        session: NativeMetalPresenterSession,
        onExitRequested: @escaping () -> Void,
        onRestartRequested: @escaping () -> Void
    ) -> UnsafeMutableRawPointer? {
        guard let scene = Self.activeWindowScene() else {
            NSLog("Native Metal presenter could not find a foreground UIWindowScene")
            return nil
        }

        let rootController = NativeMetalPresenterViewController()
        rootController.view.backgroundColor = .black
        rootController.onGeometryChanged = { [weak self] reason in
            self?.handleGeometryChange(reason: reason)
        }

        let presenterView = NativeMetalPresenterView(frame: scene.coordinateSpace.bounds)
        presenterView.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.addSubview(presenterView)
        let tapGesture = UITapGestureRecognizer()
        tapGesture.cancelsTouchesInView = false
        tapGesture.delaysTouchesBegan = false
        tapGesture.delaysTouchesEnded = false
        presenterView.addGestureRecognizer(tapGesture)
        NSLayoutConstraint.activate([
            presenterView.leadingAnchor.constraint(equalTo: rootController.view.leadingAnchor),
            presenterView.trailingAnchor.constraint(equalTo: rootController.view.trailingAnchor),
            presenterView.topAnchor.constraint(equalTo: rootController.view.topAnchor),
            presenterView.bottomAnchor.constraint(equalTo: rootController.view.bottomAnchor),
        ])

        let exitOverlayView = GameplayExitOverlayView(
            session: session,
            onExitRequested: onExitRequested,
            onRestartRequested: onRestartRequested
        )
        exitOverlayView.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.addSubview(exitOverlayView)
        NSLayoutConstraint.activate([
            exitOverlayView.leadingAnchor.constraint(equalTo: rootController.view.leadingAnchor),
            exitOverlayView.trailingAnchor.constraint(equalTo: rootController.view.trailingAnchor),
            exitOverlayView.topAnchor.constraint(equalTo: rootController.view.topAnchor),
            exitOverlayView.bottomAnchor.constraint(equalTo: rootController.view.bottomAnchor),
        ])
        tapGesture.addTarget(exitOverlayView, action: #selector(GameplayExitOverlayView.show))

        let window = NativeMetalPresenterWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = UIWindow.Level.alert
        window.backgroundColor = .black
        window.rootViewController = rootController
        window.exitOverlayView = exitOverlayView
        window.onGeometryChanged = { [weak self] reason in
            self?.schedulePresenterLayout(reason: reason)
        }
        window.makeKeyAndVisible()

        rootController.view.setNeedsLayout()
        rootController.view.layoutIfNeeded()

        self.window = window
        self.rootController = rootController
        self.presenterView = presenterView
        self.exitOverlayView = exitOverlayView
        observeOrientationChanges()
        startGeometryDisplayLink()
        forcePresenterLayout(reason: "start")

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

    private func observeOrientationChanges() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePresenterLayout(reason: "device-orientation")
        }
    }

    private func startGeometryDisplayLink() {
        guard geometryDisplayLink == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(handleGeometryDisplayLink(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 2, maximum: 10, preferred: 5)
        displayLink.add(to: .main, forMode: .common)
        geometryDisplayLink = displayLink
    }

    @objc private func handleGeometryDisplayLink(_ displayLink: CADisplayLink) {
        syncPresenterGeometry(reason: "display-link")
    }

    private func handleGeometryChange(reason: String) {
        switch reason {
        case "transition-start", "transition-end", "safe-area":
            schedulePresenterLayout(reason: reason)
        default:
            syncPresenterGeometry(reason: reason)
        }
    }

    private func schedulePresenterLayout(reason: String) {
        guard !isSyncingGeometry else {
            return
        }

        forcePresenterLayout(reason: reason)
        DispatchQueue.main.async { [weak self] in
            self?.forcePresenterLayout(reason: "\(reason)-async")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.forcePresenterLayout(reason: "\(reason)-settled")
        }
    }

    private func forcePresenterLayout(reason: String) {
        guard !isSyncingGeometry else {
            return
        }

        isSyncingGeometry = true
        defer {
            isSyncingGeometry = false
        }

        rootController?.view.setNeedsLayout()
        rootController?.view.layoutIfNeeded()
        syncPresenterGeometryLocked(reason: reason)
    }

    private func syncPresenterGeometry(reason: String) {
        guard !isSyncingGeometry else {
            return
        }

        isSyncingGeometry = true
        defer {
            isSyncingGeometry = false
        }

        syncPresenterGeometryLocked(reason: reason)
    }

    private func syncPresenterGeometryLocked(reason: String) {
        guard let window,
              let presenterView else {
            return
        }

        if let sceneBounds = window.windowScene?.coordinateSpace.bounds,
           !window.frame.isSameFrame(as: sceneBounds) {
            window.frame = sceneBounds
        }
        if window.isHidden || !window.isKeyWindow {
            window.makeKeyAndVisible()
        }

        window.setNeedsLayout()
        window.layoutIfNeeded()
        rootController?.view.setNeedsLayout()
        rootController?.view.layoutIfNeeded()
        presenterView.refreshDrawableSize()
        exitOverlayView?.refreshLayoutForGeometryChange()

        let layer = presenterView.metalLayer
        let geometry = CGSize(width: layer.bounds.width, height: layer.bounds.height)
        guard !geometry.isSameSize(as: lastLoggedGeometry) else {
            return
        }

        lastLoggedGeometry = geometry
        NSLog(
            "Native Metal presenter geometry %@ window=%.0fx%.0f root=%.0fx%.0f layer=%.0fx%.0f drawable=%.0fx%.0f scale=%.2f",
            reason,
            window.bounds.width,
            window.bounds.height,
            rootController?.view.bounds.width ?? 0,
            rootController?.view.bounds.height ?? 0,
            layer.bounds.width,
            layer.bounds.height,
            layer.drawableSize.width,
            layer.drawableSize.height,
            layer.contentsScale
        )
    }

    func stop() {
        geometryDisplayLink?.invalidate()
        geometryDisplayLink = nil
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        window?.isHidden = true
        window?.onGeometryChanged = nil
        window?.exitOverlayView = nil
        exitOverlayView?.removeFromSuperview()
        exitOverlayView = nil
        presenterView?.removeFromSuperview()
        presenterView = nil
        rootController = nil
        window = nil
        NSLog("Native Metal presenter stopped")
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ??
            scenes.first { $0.activationState == .foregroundInactive } ??
            scenes.first
    }
}

private final class NativeMetalPresenterWindow: UIWindow {
    var onGeometryChanged: ((String) -> Void)?
    weak var exitOverlayView: GameplayExitOverlayView?

    override func layoutSubviews() {
        super.layoutSubviews()
        onGeometryChanged?("window-layout")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onGeometryChanged?("window-safe-area")
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)

        guard event.type == .touches,
              exitOverlayView?.isMenuVisible == true else {
            return
        }

        _ = exitOverlayView?.handleRawTouchEnded(from: event)
    }
}

private extension CGRect {
    func isSameFrame(as other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5 &&
            abs(origin.y - other.origin.y) < 0.5 &&
            size.isSameSize(as: other.size)
    }
}

private extension CGSize {
    func isSameSize(as other: CGSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
