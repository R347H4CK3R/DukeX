import Darwin
import Foundation
import Metal
import QuartzCore
import UIKit

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

private struct XemuIOSDisplayStats {
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

    func sample() -> XemuIOSDisplayStats? {
        if copyDisplayStats == nil {
            resolve()
        }

        guard let copyDisplayStats else {
            return nil
        }

        var stats = XemuIOSDisplayStats()
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

    func start() -> UnsafeMutableRawPointer? {
        guard let scene = Self.activeWindowScene() else {
            NSLog("Native Metal presenter could not find a foreground UIWindowScene")
            return nil
        }

        let rootController = NativeMetalPresenterViewController()
        rootController.view.backgroundColor = .black

        let presenterView = NativeMetalPresenterView(frame: scene.screen.bounds)
        presenterView.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.addSubview(presenterView)
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
