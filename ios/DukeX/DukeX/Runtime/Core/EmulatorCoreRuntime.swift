import Darwin
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Metal
import QuartzCore
import UniformTypeIdentifiers
import UIKit

private typealias XboxCameraFrameProvider = @convention(c) (
    UnsafeMutablePointer<UInt8>?,
    Int,
    UnsafeMutablePointer<UInt32>?,
    UnsafeMutablePointer<UInt32>?,
    UnsafeMutablePointer<UInt64>?
) -> Int
private typealias XemuSetXboxCameraFrameProvider = @convention(c) (XboxCameraFrameProvider?) -> Void

private let dukexXboxCameraFrameProvider: XboxCameraFrameProvider = { destination, capacity, width, height, sequence in
    XboxCameraFrameSource.shared.copyJPEGFrame(
        to: destination,
        capacity: capacity,
        width: width,
        height: height,
        sequence: sequence
    )
}

@MainActor
final class EmulatorCoreRuntime: ObservableObject {
    enum RunState: Equatable {
        case unavailable(String)
        case ready(URL)
        case running(String)
        case exited(Int32)
        case failed(String)

        var canLaunch: Bool {
            switch self {
            case .ready, .exited:
                return true
            default:
                return false
            }
        }

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }
    }

    private typealias XemuMain = @convention(c) (
        Int32,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias XemuPrimeCoroutines = @convention(c) (CUnsignedInt) -> Void
    private typealias XemuSetExternalMetalLayer = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias XemuRequestShutdown = @convention(c) () -> Void

    @Published private(set) var state: RunState

    private var handle: UnsafeMutableRawPointer?
    private var entryPoint: XemuMain?
    private var primeCoroutines: XemuPrimeCoroutines?
    private var setExternalMetalLayer: XemuSetExternalMetalLayer?
    private var requestShutdown: XemuRequestShutdown?
    private var setXboxCameraFrameProvider: XemuSetXboxCameraFrameProvider?

    init(bundle: Bundle = .main) {
        state = Self.resolveCoreURL(in: bundle).map(RunState.ready) ??
            .unavailable("libxemu-ios-core.dylib is not embedded.")
        NSLog("Xemu core runtime initialized: %@", String(describing: state))
    }

    func refresh(bundle: Bundle = .main) {
        guard !state.isRunning else {
            return
        }
        state = Self.resolveCoreURL(in: bundle).map(RunState.ready) ??
            .unavailable("libxemu-ios-core.dylib is not embedded.")
        NSLog("Xemu core runtime refreshed: %@", String(describing: state))
    }

    func launch(plan: XemuLaunchPlan) {
        guard !state.isRunning else {
            return
        }

        do {
            let entryPoint = try loadEntryPoint()
            let arguments = plan.arguments
            let jitMode = plan.jitMode
            let universalJITEnabled = plan.universalJITEnabled
            let xboxCameraEnabled = plan.xboxCameraEnabled
            let xboxHeadsetMicEnabled = plan.xboxHeadsetMicEnabled
            let setExternalMetalLayer = loadSetExternalMetalLayer()
            let requestShutdown = loadRequestShutdown()
            let setXboxCameraFrameProvider = loadSetXboxCameraFrameProvider()

            let logURL = Self.prepareRunLog(for: plan, arguments: arguments)
            state = .running(plan.gameName)
            NSLog("Launching Xemu core for %@", plan.gameName)
            if let logURL {
                NSLog("Xemu run log: %@", logURL.path)
            }
            GameControllerBootstrap.shared.logSnapshot(reason: "before core launch")

            Task { @MainActor in
                await XboxPeripheralPermissionPrimer.shared.prepareIfNeeded(
                    cameraEnabled: xboxCameraEnabled,
                    headsetMicEnabled: xboxHeadsetMicEnabled
                )
                if xboxCameraEnabled {
                    XboxCameraFrameSource.shared.start()
                    setXboxCameraFrameProvider?(dukexXboxCameraFrameProvider)
                } else {
                    setXboxCameraFrameProvider?(nil)
                }
                let status = Self.invoke(
                    entryPoint,
                    arguments: arguments,
                    jitMode: jitMode,
                    universalJITEnabled: universalJITEnabled,
                    xboxCameraEnabled: xboxCameraEnabled,
                    xboxHeadsetMicEnabled: xboxHeadsetMicEnabled,
                    setExternalMetalLayer: setExternalMetalLayer,
                    requestShutdown: requestShutdown,
                    session: NativeMetalPresenterSession(
                        title: plan.gameName,
                        isDashboard: plan.isDashboard
                    )
                )

                Task { @MainActor [weak self] in
                    NSLog("Xemu core exited with status %d", status)
                    self?.state = .exited(status)
                }
            }
        } catch {
            NSLog("Xemu core launch failed: %@", error.localizedDescription)
            state = .failed(error.localizedDescription)
        }
    }

    func prepareBeforeAutoJIT(coroutineReserve: CUnsignedInt = 640) throws {
        guard !state.isRunning else {
            return
        }

        guard coroutineReserve > 0 else {
            NSLog("Skipping pre-StikDebug coroutine prime")
            return
        }

        _ = try loadEntryPoint()
        let primeCoroutines = try loadPrimeCoroutines()
        NSLog("Pre-priming Xemu coroutine pool before StikDebug: %u", coroutineReserve)
        primeCoroutines(coroutineReserve)
    }

    private func loadEntryPoint() throws -> XemuMain {
        if let entryPoint {
            return entryPoint
        }

        guard let coreURL = Self.resolveCoreURL(in: .main) else {
            throw RuntimeError.missingCore
        }

        NSLog("Loading Xemu core dylib from %@", coreURL.path)
        let openFlags = RTLD_NOW | RTLD_LOCAL
        guard let handle = dlopen(coreURL.path, openFlags) else {
            throw RuntimeError.dynamicLoader(Self.dynamicLoaderError())
        }

        guard let symbol = dlsym(handle, "xemu_ios_main") else {
            throw RuntimeError.dynamicLoader(Self.dynamicLoaderError())
        }

        NSLog("Resolved xemu_ios_main")
        self.handle = handle
        let entryPoint = unsafeBitCast(symbol, to: XemuMain.self)
        self.entryPoint = entryPoint
        return entryPoint
    }

    private func loadPrimeCoroutines() throws -> XemuPrimeCoroutines {
        if let primeCoroutines {
            return primeCoroutines
        }

        _ = try loadEntryPoint()
        guard let handle else {
            throw RuntimeError.missingCore
        }

        guard let symbol = dlsym(handle, "xemu_ios_coroutine_prime_global_pool") else {
            throw RuntimeError.dynamicLoader(Self.dynamicLoaderError())
        }

        NSLog("Resolved xemu_ios_coroutine_prime_global_pool")
        let primeCoroutines = unsafeBitCast(symbol, to: XemuPrimeCoroutines.self)
        self.primeCoroutines = primeCoroutines
        return primeCoroutines
    }

    private func loadSetExternalMetalLayer() -> XemuSetExternalMetalLayer? {
        if let setExternalMetalLayer {
            return setExternalMetalLayer
        }

        guard let handle else {
            return nil
        }

        guard let symbol = dlsym(handle, "xemu_ios_set_external_metal_layer") else {
            NSLog("xemu_ios_set_external_metal_layer is not available; falling back to SDL Metal layer")
            return nil
        }

        NSLog("Resolved xemu_ios_set_external_metal_layer")
        let setter = unsafeBitCast(symbol, to: XemuSetExternalMetalLayer.self)
        setExternalMetalLayer = setter
        return setter
    }

    private func loadRequestShutdown() -> XemuRequestShutdown? {
        if let requestShutdown {
            return requestShutdown
        }

        guard let handle else {
            return nil
        }

        guard let symbol = dlsym(handle, "xemu_ios_request_shutdown") else {
            NSLog("xemu_ios_request_shutdown is not available")
            return nil
        }

        NSLog("Resolved xemu_ios_request_shutdown")
        let requestShutdown = unsafeBitCast(symbol, to: XemuRequestShutdown.self)
        self.requestShutdown = requestShutdown
        return requestShutdown
    }

    private func loadSetXboxCameraFrameProvider() -> XemuSetXboxCameraFrameProvider? {
        if let setXboxCameraFrameProvider {
            return setXboxCameraFrameProvider
        }

        guard let handle else {
            return nil
        }

        guard let symbol = dlsym(handle, "xemu_ios_set_xbox_camera_frame_provider") else {
            NSLog("xemu_ios_set_xbox_camera_frame_provider is not available")
            return nil
        }

        NSLog("Resolved xemu_ios_set_xbox_camera_frame_provider")
        let setter = unsafeBitCast(symbol, to: XemuSetXboxCameraFrameProvider.self)
        setXboxCameraFrameProvider = setter
        return setter
    }

    private static func prepareRunLog(
        for plan: XemuLaunchPlan,
        arguments: [String]
    ) -> URL? {
        do {
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            let logDirectoryURL = documentsURL.appendingPathComponent(
                "DukeXLogs",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: logDirectoryURL,
                withIntermediateDirectories: true
            )

            let logURL = logDirectoryURL.appendingPathComponent("latest.log")
            let header = """

            === DukeX Launch ===
            Date: \(ISO8601DateFormatter().string(from: Date()))
            Target: \(plan.gameName)
            JIT Path: \(plan.jitMode.title)
            JIT Handoff: \(plan.requiresJITHandoff ? "required" : "not required")
            Universal.js JIT: \(plan.universalJITEnabled ? "enabled" : "disabled")
            Xbox Video Chat Camera: \(plan.xboxCameraEnabled ? "enabled" : "disabled")
            Xbox Live Communicator: \(plan.xboxHeadsetMicEnabled ? "enabled" : "disabled")
            Config: \(plan.configURL.path)
            Arguments: \(arguments.joined(separator: " "))

            """

            try header.write(to: logURL, atomically: true, encoding: .utf8)
            freopen(logURL.path, "a", stdout)
            freopen(logURL.path, "a", stderr)
            setbuf(stdout, nil)
            setbuf(stderr, nil)
            return logURL
        } catch {
            NSLog("Unable to prepare DukeX run log: %@", error.localizedDescription)
            return nil
        }
    }

    private static func setEnvironment(_ values: [(String, String)]) {
        for (name, value) in values {
            setenv(name, value, 1)
        }
    }

    private static func unsetEnvironment(_ names: [String]) {
        for name in names {
            unsetenv(name)
        }
    }

    private static func invoke(
        _ entryPoint: XemuMain,
        arguments: [String],
        jitMode: RuntimeJITMode,
        universalJITEnabled: Bool,
        xboxCameraEnabled: Bool,
        xboxHeadsetMicEnabled: Bool,
        setExternalMetalLayer: XemuSetExternalMetalLayer?,
        requestShutdown: XemuRequestShutdown?,
        session: NativeMetalPresenterSession
    ) -> Int32 {
        MetalDiagnostics.configurePerformanceHUD()
        let bundleIdentifier = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        let useVulkanSwapchain = bundleIdentifier.hasPrefix("com.mafty.dukex")
        let presentPacingMode = PresentPacingMode.current
        let forceThirtyFPSLock =
            UserDefaults.standard.object(forKey: EmulatorFileStore.forceThirtyFPSLockEnabledKey) as? Bool ?? false
        let depthClampEnabled =
            UserDefaults.standard.object(forKey: EmulatorFileStore.depthClampEnabledKey) as? Bool ?? false
        let effectivePresentFPS = forceThirtyFPSLock ? "30" : presentPacingMode.presentFPS
        let effectivePresentMode = forceThirtyFPSLock ? "fifo" : presentPacingMode.vulkanPresentMode
        let effectiveDisplaySync = forceThirtyFPSLock ? true : presentPacingMode.displaySyncEnabled
        let effectiveNominalFPS = forceThirtyFPSLock ? "30" : presentPacingMode.nominalFramesPerSecond

        setEnvironment([
            ("XEMU_IOS_JIT_MODE", jitMode.environmentValue),
            ("XEMU_IOS_UNIVERSAL_JIT", universalJITEnabled ? "1" : "0"),
            ("XEMU_IOS_XBOX_CAMERA", xboxCameraEnabled ? "1" : "0"),
            ("XEMU_IOS_XBOX_HEADSET_MIC", xboxHeadsetMicEnabled ? "1" : "0"),
            ("XEMU_IOS_CAMERA_DEBUG", xboxCameraEnabled ? "1" : "0"),
            ("XEMU_IOS_VK_SWAPCHAIN", useVulkanSwapchain ? "1" : "0"),
            ("XEMU_IOS_NATIVE_METAL_PRESENTER", useVulkanSwapchain ? "1" : "0"),
            ("XEMU_IOS_PRESENTER_PORTRAIT_SCALE", "1.0"),
            ("XEMU_IOS_PRESENTER_PORTRAIT_ALIGN_X", "0.5"),
            ("XEMU_IOS_PRESENTER_PORTRAIT_ALIGN_Y", "0.5"),
            ("XEMU_IOS_PRESENTER_LANDSCAPE_SCALE", "1.0"),
            ("XEMU_IOS_PRESENTER_LANDSCAPE_ALIGN_X", "0.5"),
            ("XEMU_IOS_PRESENTER_LANDSCAPE_ALIGN_Y", "0.5"),
            ("XEMU_IOS_PRESENTER_ASPECT", "auto"),
            ("XEMU_IOS_PRESENTER_LINEAR_FILTER", "1"),
            ("XEMU_IOS_PRESENTER_FLIP_X", "0"),
            ("XEMU_IOS_PRESENTER_FLIP_Y", "1"),
            ("XEMU_IOS_VK_PRESENT_FPS", effectivePresentFPS),
            ("XEMU_IOS_VK_PRESENT_MODE", effectivePresentMode),
            ("XEMU_IOS_DISPLAY_SYNC", effectiveDisplaySync ? "1" : "0"),
            ("XEMU_IOS_NOMINAL_FPS", effectiveNominalFPS),
            ("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0"),
            ("XEMU_IOS_HOST_DEPTH_INTERPOLATION", "0"),
            ("XEMU_IOS_HOST_DEPTH_INTERPOLATION_MODE", "perspective"),
            ("XEMU_IOS_DEPTH_CLAMP", depthClampEnabled ? "1" : "0"),
            ("XEMU_IOS_STRICT_SURFACE_TEXTURE_FORMATS", "0"),
            ("XEMU_IOS_FALLBACK_GENERATION_FILTER", "1"),
            ("XEMU_IOS_SKIP_GL_FINISH", "1"),
            ("XEMU_IOS_TCG_WATCHDOG", "off"),
            ("XEMU_IOS_COROUTINE_PRIME_COUNT", "640")
        ])

        setEnvironment([
            ("XEMU_IOS_VK_SWAPCHAIN_TRACE", "0"),
            ("XEMU_IOS_DISPLAY_PERF_STATS", "0"),
            ("XEMU_IOS_SURFACE_STATS", "0"),
            ("XEMU_IOS_SURFACE_TEXTURE_TRACE", "0"),
            ("XEMU_IOS_TCG_TRACE", "0"),
            ("XEMU_IOS_IRQ_TRACE", "0"),
            ("XEMU_IOS_SYNC_DMA", "0"),
            ("XEMU_IOS_NV2A_READ_TRACE", "0"),
            ("XEMU_IOS_PCI_TRACE", "0"),
            ("XEMU_IOS_NV2A_WRITE_TRACE", "0"),
            ("XEMU_IOS_SYNC_RAW", "0"),
            ("XEMU_IOS_QCOW2_TRACE", "0"),
            ("XEMU_IOS_BLK_TRACE", "0"),
            ("XEMU_IOS_DMA_TRACE", "0"),
            ("XEMU_IOS_COROUTINE_TRACE", "0"),
            ("XEMU_IOS_VK_SUBMIT_TRACE", "0"),
            ("XEMU_IOS_RR_RETURN_TRACE", "0"),
            ("XEMU_IOS_IDE_TRACE", "0"),
            ("XEMU_IOS_PVIDEO_TRACE", "0"),
            ("XEMU_IOS_VK_RENDERER_TRACE", "0"),
            ("XEMU_IOS_VK_MEMORY_TRACE", "0"),
            ("XEMU_IOS_FRAMEBUFFER_TRACE", "0"),
            ("XEMU_IOS_VK_TEXTURE_TRACE", "0"),
            ("XEMU_IOS_RENDER_TRACE", "0"),
            ("XEMU_IOS_IO_TRACE", "0"),
            ("XEMU_IOS_TCG_EXIT_TRACE", "0"),
            ("XEMU_IOS_NET_TRACE", "0")
        ])

        unsetEnvironment([
            "XEMU_IOS_TCG_MAX_INSNS",
            "XEMU_IOS_TCG_IRQ_INSNS",
            "XEMU_IOS_TCG_NOCHAIN",
            "XEMU_IOS_DIRECT_RWX_COPY"
        ])
        NSLog("XEMU_IOS_JIT_MODE=%@", jitMode.environmentValue)
        NSLog("XEMU_IOS_UNIVERSAL_JIT=%@", universalJITEnabled ? "1" : "0")
        NSLog("XEMU_IOS_XBOX_CAMERA=%@", xboxCameraEnabled ? "1" : "0")
        NSLog("XEMU_IOS_XBOX_HEADSET_MIC=%@", xboxHeadsetMicEnabled ? "1" : "0")
        NSLog("XEMU_IOS_VK_SWAPCHAIN=%@", useVulkanSwapchain ? "1" : "0")
        NSLog(
            "XEMU_IOS_PRESENT_PACING=%@ force30=%@ mode=%@ displaySync=%@ nominalFPS=%@ presentFPS=%@",
            presentPacingMode.rawValue,
            forceThirtyFPSLock ? "1" : "0",
            effectivePresentMode,
            effectiveDisplaySync ? "1" : "0",
            effectiveNominalFPS,
            effectivePresentFPS
        )
        NSLog("XEMU_IOS_DEPTH_CLAMP=%@", depthClampEnabled ? "1" : "0")
        NSLog("Xemu core argv: %@", arguments.joined(separator: " "))

        let presenterHost = useVulkanSwapchain ? NativeMetalPresenterHost() : nil
        if let presenterHost {
            if let layerPointer = presenterHost.start(
                session: session,
                onExitRequested: {
                    NotificationCenter.default.post(name: .dukeXReturnToGamesRequested, object: nil)
                    requestShutdown?()
                }
            ) {
                setExternalMetalLayer?(layerPointer)
                NSLog(
                    "Native CAMetalLayer presenter active: 0x%llx",
                    UInt64(UInt(bitPattern: layerPointer))
                )
            } else {
                setExternalMetalLayer?(nil)
                NSLog("Native CAMetalLayer presenter unavailable; falling back to SDL Metal layer")
            }
        }
        defer {
            if useVulkanSwapchain {
                setExternalMetalLayer?(nil)
                presenterHost?.stop()
            }
        }

        let argv = arguments.map { strdup($0) } + [nil]
        defer {
            for arg in argv {
                free(arg)
            }
        }

        var mutableArgv = argv
        return mutableArgv.withUnsafeMutableBufferPointer { buffer in
            entryPoint(Int32(arguments.count), buffer.baseAddress)
        }
    }

    private static func resolveCoreURL(in bundle: Bundle) -> URL? {
        let frameworksURL = bundle.privateFrameworksURL
        let coreURL = frameworksURL?.appendingPathComponent("libxemu-ios-core.dylib")

        guard let coreURL, FileManager.default.fileExists(atPath: coreURL.path) else {
            return nil
        }
        return coreURL
    }

    private static func dynamicLoaderError() -> String {
        guard let error = dlerror() else {
            return "Unknown dynamic loader error."
        }
        return String(cString: error)
    }
}

private enum RuntimeError: LocalizedError {
    case missingCore
    case dynamicLoader(String)

    var errorDescription: String? {
        switch self {
        case .missingCore:
            return "libxemu-ios-core.dylib is not embedded."
        case .dynamicLoader(let message):
            return message
        }
    }
}

@MainActor
private final class XboxPeripheralPermissionPrimer {
    static let shared = XboxPeripheralPermissionPrimer()

    private var cameraPrepared = false
    private var microphonePrepared = false

    func prepareIfNeeded(cameraEnabled: Bool, headsetMicEnabled: Bool) async {
        guard cameraEnabled || headsetMicEnabled else {
            return
        }

        var cameraGranted = !cameraEnabled || cameraPrepared
        var microphoneGranted = !headsetMicEnabled || microphonePrepared

        if cameraEnabled && !cameraPrepared {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPrepared = cameraGranted
        }

        if headsetMicEnabled && !microphonePrepared {
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            microphonePrepared = microphoneGranted
        }

        NSLog(
            "Xbox peripheral permissions camera=%@ microphone=%@",
            cameraGranted ? "granted" : "denied",
            microphoneGranted ? "granted" : "denied"
        )

        guard cameraGranted else {
            return
        }

        if let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) {
            NSLog("Xbox camera host source prepared: %@", frontCamera.localizedName)
        } else {
            NSLog("Xbox camera host source unavailable: no front camera")
        }
    }
}

private final class XboxCameraFrameSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = XboxCameraFrameSource()

    private let sessionQueue = DispatchQueue(label: "DukeX.XboxCamera.Session")
    private let sampleQueue = DispatchQueue(label: "DukeX.XboxCamera.Sample")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()

    private var session: AVCaptureSession?
    private var isRunning = false
    private var latestJPEG = Data()
    private var latestWidth: UInt32 = 320
    private var latestHeight: UInt32 = 240
    private var latestSequence: UInt64 = 0
    private var lastFrameTime = 0.0

    private override init() {
        latestJPEG = Self.makePlaceholderJPEG()
        super.init()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isRunning else {
                return
            }

            let session = AVCaptureSession()
            session.beginConfiguration()
            if session.canSetSessionPreset(.low) {
                session.sessionPreset = .low
            }

            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ) else {
                NSLog("Xbox camera host source unavailable: no front camera")
                session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    NSLog("Xbox camera host source unavailable: cannot add input")
                    session.commitConfiguration()
                    return
                }
            } catch {
                NSLog("Xbox camera host source failed: %@", error.localizedDescription)
                session.commitConfiguration()
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.sampleQueue)

            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                NSLog("Xbox camera host source unavailable: cannot add output")
                session.commitConfiguration()
                return
            }

            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            session.commitConfiguration()
            self.session = session
            self.isRunning = true
            session.startRunning()
            NSLog("Xbox camera host source streaming: %@", camera.localizedName)
        }
    }

    func copyJPEGFrame(
        to destination: UnsafeMutablePointer<UInt8>?,
        capacity: Int,
        width: UnsafeMutablePointer<UInt32>?,
        height: UnsafeMutablePointer<UInt32>?,
        sequence: UnsafeMutablePointer<UInt64>?
    ) -> Int {
        guard let destination, capacity > 0 else {
            return 0
        }

        lock.lock()
        let jpeg = latestJPEG
        let frameWidth = latestWidth
        let frameHeight = latestHeight
        let frameSequence = latestSequence
        lock.unlock()

        guard !jpeg.isEmpty, jpeg.count <= capacity else {
            return 0
        }

        jpeg.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                memcpy(destination, baseAddress, jpeg.count)
            }
        }
        width?.pointee = frameWidth
        height?.pointee = frameHeight
        sequence?.pointee = frameSequence
        return jpeg.count
    }

    private static func makePlaceholderJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240))
        let image = renderer.image { context in
            UIColor(white: 0.02, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))

            UIColor(white: 0.18, alpha: 1.0).setFill()
            context.fill(CGRect(x: 0, y: 108, width: 320, height: 24))
        }

        return image.jpegData(compressionQuality: 0.55) ?? Data()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= 1.0 / 15.0 else {
            return
        }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = makeJPEG(from: pixelBuffer) else {
            return
        }

        lock.lock()
        latestJPEG = jpeg
        latestWidth = 320
        latestHeight = 240
        latestSequence &+= 1
        lock.unlock()
    }

    private func makeJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else {
            return nil
        }

        let targetSize = CGSize(width: 320, height: 240)
        let targetAspect = targetSize.width / targetSize.height
        var crop = sourceExtent
        let sourceAspect = sourceExtent.width / sourceExtent.height

        if sourceAspect > targetAspect {
            let croppedWidth = sourceExtent.height * targetAspect
            crop.origin.x += (sourceExtent.width - croppedWidth) * 0.5
            crop.size.width = croppedWidth
        } else if sourceAspect < targetAspect {
            let croppedHeight = sourceExtent.width / targetAspect
            crop.origin.y += (sourceExtent.height - croppedHeight) * 0.5
            crop.size.height = croppedHeight
        }

        let normalized = sourceImage
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let scaled = normalized.transformed(
            by: CGAffineTransform(
                scaleX: targetSize.width / crop.width,
                y: targetSize.height / crop.height
            )
        )
        let outputRect = CGRect(origin: .zero, size: targetSize)

        guard let cgImage = ciContext.createCGImage(scaled, from: outputRect) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options = [
            kCGImageDestinationLossyCompressionQuality: 0.55
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}
