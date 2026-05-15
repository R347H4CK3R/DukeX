import Darwin
import Foundation
import Metal
import QuartzCore
import UIKit

extension Notification.Name {
    static let dukeXReturnToGamesRequested = Notification.Name("DukeXReturnToGamesRequested")
}

struct NativeMetalPresenterSession {
    let title: String
    let isDashboard: Bool
}

private final class NativeMetalPresenterViewController: UIViewController {
    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }
}

private struct DukeXDisplayStats {
    var sampleID: UInt64 = 0
    var presenterFPS: Double = 0
    var nv2aFPS: UInt32 = 0
    var mspf: Int32 = 0
    var frames: UInt64 = 0
    var presentReadyFrames: UInt64 = 0
    var presentMissedFrames: UInt64 = 0
    var nativePresentFrames: UInt64 = 0
    var pvideoFrames: UInt64 = 0
    var surfaceUploadPendingFrames: UInt64 = 0
    var finishPresentingFrames: UInt64 = 0
    var avgTotalUS: Int64 = 0
    var avgWaitPresentUS: Int64 = 0
    var avgSubmitUS: Int64 = 0
    var avgPresentUS: Int64 = 0
    var queueSubmits: Int32 = 0
    var auxSubmits: Int32 = 0
    var displaySubmits: Int32 = 0
    var shaderBinds: Int32 = 0
    var surfaceDownloads: Int32 = 0
    var surfaceToTexture: Int32 = 0
    var geometryUpdates: Int32 = 0
    var geometryRAMUpdates: Int32 = 0
    var geometryIndexUpdates: Int32 = 0
    var geometryInlineUpdates: Int32 = 0
    var pipelineGenerations: Int32 = 0
    var shaderGenerations: Int32 = 0
    var textureUploads: Int32 = 0
    var surfaceUploads: Int32 = 0
}

private final class XemuDisplayStatsBridge {
    static let shared = XemuDisplayStatsBridge()

    private typealias CopyDisplayStats = @convention(c) (UnsafeMutableRawPointer?) -> CInt
    private var copyDisplayStats: CopyDisplayStats?

    func sample() -> DukeXDisplayStats? {
        if copyDisplayStats == nil {
            resolve()
        }

        guard let copyDisplayStats else {
            return nil
        }

        var stats = DukeXDisplayStats()
        let copied = withUnsafeMutablePointer(to: &stats) { pointer in
            copyDisplayStats(UnsafeMutableRawPointer(pointer))
        }
        guard copied != 0 else {
            return nil
        }
        return stats
    }

    private func resolve() {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            return
        }

        let coreURL = frameworksURL.appendingPathComponent("libxemu-ios-core.dylib")
        guard let handle = dlopen(coreURL.path, RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "xemu_ios_copy_display_stats") else {
            return
        }

        copyDisplayStats = unsafeBitCast(symbol, to: CopyDisplayStats.self)
    }
}

private struct AppResourceStats {
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let thermalState: ProcessInfo.ThermalState
}

private final class AppResourceMonitor {
    static let shared = AppResourceMonitor()

    func sample() -> AppResourceStats {
        AppResourceStats(
            cpuPercent: currentCPUPercent(),
            residentMemoryBytes: currentResidentMemoryBytes(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let task = mach_task_self_

        guard task_threads(task, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList else {
            return 0
        }

        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(task, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var totalCPU = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        $0,
                        &count
                    )
                }
            }

            guard result == KERN_SUCCESS,
                  (info.flags & TH_FLAGS_IDLE) == 0 else {
                continue
            }

            totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }

        return totalCPU
    }

    private func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return UInt64(info.resident_size)
    }
}

private final class StatsHUDView: UIVisualEffectView {
    private let fpsLabel = UILabel()
    private let systemLabel = UILabel()
    private let geometryLabel = UILabel()
    private let detailLabel = UILabel()
    private var displayLink: CADisplayLink?
    private var lastRefreshTimestamp: CFTimeInterval = 0

    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [fpsLabel, systemLabel, geometryLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])

        configure(label: fpsLabel, size: 13, weight: .semibold, color: .white)
        configure(label: systemLabel, size: 11, weight: .medium, color: UIColor.white.withAlphaComponent(0.86))
        configure(label: geometryLabel, size: 10, weight: .regular, color: UIColor.white.withAlphaComponent(0.72))
        configure(label: detailLabel, size: 10, weight: .regular, color: UIColor.white.withAlphaComponent(0.62))
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else {
            start()
        }
    }

    private func configure(label: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
        label.font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func start() {
        guard displayLink == nil else {
            return
        }

        let displayLink = CADisplayLink(target: self, selector: #selector(refresh(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 10)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func refresh(_ displayLink: CADisplayLink) {
        guard displayLink.timestamp - lastRefreshTimestamp >= 0.5 else {
            return
        }

        lastRefreshTimestamp = displayLink.timestamp
        updateContent()
    }

    private func updateContent() {
        let resources = AppResourceMonitor.shared.sample()
        let displayStats = XemuDisplayStatsBridge.shared.sample()

        if let displayStats {
            fpsLabel.text = String(
                format: "FPS %.1f  NV2A %u  %d ms",
                displayStats.presenterFPS,
                displayStats.nv2aFPS,
                displayStats.mspf
            )
            geometryLabel.text = String(
                format: "geom %d  ram/idx/inl %d/%d/%d",
                displayStats.geometryUpdates,
                displayStats.geometryRAMUpdates,
                displayStats.geometryIndexUpdates,
                displayStats.geometryInlineUpdates
            )
            detailLabel.text = String(
                format: "miss %llu  surf dl/up/to %d/%d/%d  pipe/shd/tex %d/%d/%d",
                displayStats.presentMissedFrames,
                displayStats.surfaceDownloads,
                displayStats.surfaceUploads,
                displayStats.surfaceToTexture,
                displayStats.pipelineGenerations,
                displayStats.shaderGenerations,
                displayStats.textureUploads
            )
        } else {
            fpsLabel.text = "FPS --  NV2A --"
            geometryLabel.text = "geom --"
            detailLabel.text = "waiting for renderer"
        }

        systemLabel.text = String(
            format: "CPU %.0f%%  RAM %@  %@",
            resources.cpuPercent,
            Self.memoryFormatter.string(fromByteCount: Int64(resources.residentMemoryBytes)),
            Self.thermalLabel(resources.thermalState)
        )
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter
    }()

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Thermal nominal"
        case .fair:
            return "Thermal fair"
        case .serious:
            return "Thermal serious"
        case .critical:
            return "Thermal critical"
        @unknown default:
            return "Thermal unknown"
        }
    }
}

private final class GameplayExitOverlayView: UIView {
    private let session: NativeMetalPresenterSession
    private let onExitRequested: () -> Void
    private let panelView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let exitButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var exitHasBeenRequested = false

    init(session: NativeMetalPresenterSession, onExitRequested: @escaping () -> Void) {
        self.session = session
        self.onExitRequested = onExitRequested
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func toggle() {
        isVisible ? hide() : show()
    }

    @objc func show() {
        guard !isVisible else {
            return
        }

        isHidden = false
        isUserInteractionEnabled = true
        accessibilityViewIsModal = true
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
        }
    }

    @objc func hide() {
        guard isVisible, !exitHasBeenRequested else {
            return
        }

        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
            self.isUserInteractionEnabled = false
            self.accessibilityViewIsModal = false
        }
    }

    private var isVisible: Bool {
        !isHidden && alpha > 0
    }

    private func configure() {
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.42)

        let dismissButton = UIButton(type: .custom)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(hide), for: .touchUpInside)
        addSubview(dismissButton)

        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.layer.cornerRadius = 22
        panelView.layer.cornerCurve = .continuous
        panelView.layer.masksToBounds = true
        addSubview(panelView)

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, exitButton, cancelButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(stack)

        titleLabel.text = session.isDashboard ? "Exit Dashboard?" : "Exit Gameplay?"
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title3).withWeight(.bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        messageLabel.text = session.isDashboard ?
            "DukeX will stop the dashboard and return to the Games tab." :
            "DukeX will stop \(session.displayTitle) and return to the Games tab. Unsaved progress may be lost."
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        exitButton.configuration = primaryButtonConfiguration(
            title: session.isDashboard ? "Exit Dashboard" : "Exit Game",
            color: .systemRed
        )
        exitButton.addTarget(self, action: #selector(confirmExit), for: .touchUpInside)

        cancelButton.configuration = secondaryButtonConfiguration(title: "Cancel")
        cancelButton.addTarget(self, action: #selector(hide), for: .touchUpInside)

        NSLayoutConstraint.activate([
            dismissButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            panelView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            panelView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            panelView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, constant: -36),
            panelView.widthAnchor.constraint(lessThanOrEqualToConstant: 390),

            stack.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panelView.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor, constant: -18),
            exitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        accessibilityLabel = session.isDashboard ? "Exit Dashboard Menu" : "Exit Gameplay Menu"
    }

    @objc private func confirmExit() {
        guard !exitHasBeenRequested else {
            return
        }

        exitHasBeenRequested = true
        exitButton.isEnabled = false
        cancelButton.isEnabled = false
        titleLabel.text = "Exiting..."
        messageLabel.text = session.isDashboard ?
            "Stopping the dashboard and returning to Games." :
            "Stopping \(session.displayTitle) and returning to Games."
        exitButton.configuration = primaryButtonConfiguration(title: "Exiting", color: .systemGray)
        onExitRequested()
    }

    private func primaryButtonConfiguration(title: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        return configuration
    }

    private func secondaryButtonConfiguration(title: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        return configuration
    }
}

private extension NativeMetalPresenterSession {
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "the running game" : trimmedTitle
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: weight]
        let descriptor = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private final class NativeMetalPresenterView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFit
        configureMetalLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = true
        backgroundColor = .black
        contentMode = .scaleAspectFit
        configureMetalLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    func configureMetalLayer() {
        let layer = metalLayer
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.presentsWithTransaction = false
        layer.allowsNextDrawableTimeout = true
        layer.contentsGravity = .resizeAspect
        MetalHUDLayerConfigurator.apply(to: layer)
        PresentPacingLayerConfigurator.apply(to: layer)
        updateDrawableSize()
    }

    func updateDrawableSize() {
        let scale = window?.windowScene?.screen.scale ?? max(traitCollection.displayScale, 1)
        contentScaleFactor = scale
        metalLayer.contentsScale = scale

        let width = max(1.0, bounds.width * scale)
        let height = max(1.0, bounds.height * scale)
        metalLayer.drawableSize = CGSize(width: width, height: height)
    }
}

private enum MetalHUDLayerConfigurator {
    static func apply(to layer: CAMetalLayer) {
        guard MetalDiagnostics.performanceHUDRequested else {
            layer.developerHUDProperties = [
                "mode": "disabled",
                "logging": "disabled",
            ]
            return
        }

        layer.developerHUDProperties = [
            "mode": "main",
            "logging": "default",
            "positionX": 12,
            "positionY": 12,
            "MTL_HUD_ENABLED": 1,
            "MTL_HUD_LOG_ENABLED": 1,
            "MTL_HUD_LOG_SHADER_ENABLED": 1,
            "MTL_HUD_ENCODER_TIMING_ENABLED": 1,
            "MTL_HUD_SHOW_ZERO_METRICS": 1,
            "MTL_HUD_OPACITY": 1.0,
        ]
        NSLog("Metal HUD developer properties applied to CAMetalLayer")
    }
}

private enum PresentPacingLayerConfigurator {
    static func apply(to layer: CAMetalLayer) {
        let mode = PresentPacingMode.current
        let forceThirtyFPSLock =
            UserDefaults.standard.object(forKey: "DukeXForceThirtyFPSLockEnabled") as? Bool ?? false
        let displaySyncEnabled = forceThirtyFPSLock ? true : mode.displaySyncEnabled
        let nominalFPS = forceThirtyFPSLock ? 30 : mode.nominalFramesPerSecondValue
        layer.setBoolWithSelector("setDisplaySyncEnabled:", value: displaySyncEnabled)
        layer.setIntWithSelector("setNominalFramesPerSecond:", value: nominalFPS)
        NSLog(
            "Native Metal presenter pacing applied: %@ force30=%@ displaySync=%@ nominalFPS=%d",
            mode.rawValue,
            forceThirtyFPSLock ? "1" : "0",
            displaySyncEnabled ? "1" : "0",
            nominalFPS
        )
    }
}

private extension NSObject {
    func setBoolWithSelector(_ selectorName: String, value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = method(for: selector) else {
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(implementation, to: Setter.self)(self, selector, value)
    }

    func setIntWithSelector(_ selectorName: String, value: Int) {
        let selector = NSSelectorFromString(selectorName)
        guard responds(to: selector),
              let implementation = method(for: selector) else {
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(implementation, to: Setter.self)(self, selector, value)
    }
}

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
