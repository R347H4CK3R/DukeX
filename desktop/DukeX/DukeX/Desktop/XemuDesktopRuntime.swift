#if os(macOS) || targetEnvironment(macCatalyst)
import Combine
import Darwin
import Foundation

@MainActor
final class XemuDesktopRuntime: ObservableObject {
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

    @Published private(set) var state: RunState

    private var processID: pid_t?
    private var currentExecutableURL: URL?
    private var currentLogURL: URL?

    init(bundle: Bundle = .main) {
        state = Self.resolveXemuExecutable(in: bundle).map(RunState.ready) ??
            .unavailable("Bundled xemu executable is not available.")
    }

    func refresh(bundle: Bundle = .main) {
        guard !state.isRunning else {
            return
        }
        state = Self.resolveXemuExecutable(in: bundle).map(RunState.ready) ??
            .unavailable("Bundled xemu executable is not available.")
    }

    func launch(plan: XemuDesktopLaunchPlan, bundle: Bundle = .main) {
        guard !state.isRunning else {
            return
        }

        guard let executableURL = Self.resolveXemuExecutable(in: bundle) else {
            state = .unavailable("Bundled xemu executable is not available.")
            return
        }

        do {
            let logURL = try Self.prepareRunLog(for: plan)
            var environment = ProcessInfo.processInfo.environment
            environment["XEMU_DESKTOP_FRONTEND"] = "DukeX"
            environment["XEMU_SPECIALACCESS"] = "xemu"
            environment["XEMU_SHADER_CACHE_PATH"] = plan.shaderCacheURL.path
            environment["XEMU_WINDOW_TITLE"] = plan.gameName

            let applicationURL = Self.resolveXemuApplication(for: executableURL)
            let launchPID = try Self.spawnXemu(
                executableURL: executableURL,
                applicationURL: applicationURL,
                arguments: Array(plan.arguments.dropFirst()),
                environment: environment,
                logURL: logURL
            )

            processID = launchPID
            currentExecutableURL = executableURL
            currentLogURL = logURL
            state = .running(plan.gameName)

            if let applicationURL {
                Self.activateSidecarApplication(at: applicationURL)
            }
            watchProcess(launchPID)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func prepareBeforeAutoJIT(coroutineReserve: CUnsignedInt = 640) throws {
        // Desktop xemu runs outside the iOS JIT sandbox, so there is no JIT
        // handoff or coroutine pre-prime step to perform.
    }

    func stop() {
        guard let processID else {
            return
        }

        if let currentExecutableURL {
            Self.signalProcesses(matching: currentExecutableURL.path)
        }
        kill(processID, SIGTERM)
    }

    var logURL: URL? {
        currentLogURL
    }

    private func watchProcess(_ pid: pid_t) {
        let runtime = self
        Task.detached { [runtime, pid] in
            let status = Self.waitForProcess(pid)
            await runtime.finishProcess(pid, status: status)
        }
    }

    private func finishProcess(_ pid: pid_t, status: Int32) {
        guard processID == pid else {
            return
        }
        processID = nil
        currentExecutableURL = nil
        state = .exited(status)
    }

    private static func resolveXemuExecutable(in bundle: Bundle) -> URL? {
        var candidates: [URL] = []
        if let overridePath = ProcessInfo.processInfo.environment["XEMU_DESKTOP_EXECUTABLE"],
           !overridePath.isEmpty {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        candidates += [
            bundle.bundleURL
                .appendingPathComponent("Contents/Library/Xemu/DukeX.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/DukeX", isDirectory: false),
            bundle.bundleURL
                .appendingPathComponent("Library/Xemu/DukeX.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/DukeX", isDirectory: false),
            bundle.bundleURL
                .appendingPathComponent("Contents/Library/Xemu/xemu.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/xemu", isDirectory: false),
            bundle.bundleURL
                .appendingPathComponent("Library/Xemu/xemu.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/xemu", isDirectory: false),
            bundle.url(forResource: "xemu", withExtension: nil),
            bundle.url(forResource: "DukeX", withExtension: nil, subdirectory: "DukeX.app/Contents/MacOS"),
            bundle.url(forResource: "xemu", withExtension: nil, subdirectory: "xemu.app/Contents/MacOS"),
            bundle.resourceURL?
                .appendingPathComponent("DukeX.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/DukeX", isDirectory: false),
            bundle.resourceURL?
                .appendingPathComponent("xemu.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/xemu", isDirectory: false),
            bundle.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("DukeX.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/DukeX", isDirectory: false),
            bundle.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("xemu.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/xemu", isDirectory: false)
        ].compactMap { $0 }

        return candidates.first { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    private static func spawnXemu(
        executableURL: URL,
        applicationURL: URL?,
        arguments: [String],
        environment: [String: String],
        logURL: URL
    ) throws -> pid_t {
        let launcherURL: URL
        let argv: [String]
        if let applicationURL {
            launcherURL = URL(fileURLWithPath: "/usr/bin/open")
            argv = [
                launcherURL.path,
                "-W",
                "-n",
                "-F",
                applicationURL.path,
                "--args"
            ] + arguments
        } else {
            launcherURL = executableURL
            argv = [executableURL.path] + arguments
        }

        var fileActions: posix_spawn_file_actions_t?
        let initResult = posix_spawn_file_actions_init(&fileActions)
        guard initResult == 0 else {
            throw DesktopLaunchError.fileAction("init", initResult)
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        let outputFlags = O_WRONLY | O_APPEND
        let outputMode: mode_t = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        let stdoutResult = logURL.path.withCString { path in
            posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, path, outputFlags, outputMode)
        }
        guard stdoutResult == 0 else {
            throw DesktopLaunchError.fileAction("stdout", stdoutResult)
        }

        let stderrResult = logURL.path.withCString { path in
            posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, path, outputFlags, outputMode)
        }
        guard stderrResult == 0 else {
            throw DesktopLaunchError.fileAction("stderr", stderrResult)
        }

        let envp = environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()

        var pid: pid_t = 0
        let spawnResult = launcherURL.path.withCString { executablePath in
            withMutableCStringArray(argv) { argvPointer in
                withMutableCStringArray(envp) { environmentPointer in
                    posix_spawn(&pid, executablePath, &fileActions, nil, argvPointer, environmentPointer)
                }
            }
        }

        guard spawnResult == 0 else {
            throw DesktopLaunchError.spawn(spawnResult)
        }
        return pid
    }

    nonisolated private static func activateSidecarApplication(at applicationURL: URL) {
        let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier

        Task.detached {
            for attempt in 1...16 {
                try? await Task.sleep(nanoseconds: attempt == 1 ? 250_000_000 : 200_000_000)

                let activated = Self.runSidecarActivationCommand(bundleIdentifier: bundleIdentifier)
                NSLog(
                    "DukeX desktop sidecar activation attempt %d bundle=%@ activated=%d",
                    attempt,
                    bundleIdentifier ?? "unknown",
                    activated ? 1 : 0
                )
                if activated {
                    return
                }
            }
        }
    }

    nonisolated private static func runSidecarActivationCommand(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return false
        }

        let escapedIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let activationScript = "tell application id \"\(escapedIdentifier)\" to activate"
        if runCommand(["/usr/bin/osascript", "-e", activationScript]) {
            return true
        }

        return runCommand(["/usr/bin/open", "-b", bundleIdentifier])
    }

    nonisolated private static func runCommand(_ argv: [String]) -> Bool {
        guard let executable = argv.first else {
            return false
        }

        var pid: pid_t = 0
        let spawnResult = executable.withCString { executablePath in
            withMutableCStringArray(argv) { argvPointer in
                posix_spawn(&pid, executablePath, nil, nil, argvPointer, nil)
            }
        }

        guard spawnResult == 0 else {
            return false
        }

        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        return status == 0
    }

    private static func resolveXemuApplication(for executableURL: URL) -> URL? {
        let macOSDirectory = executableURL.deletingLastPathComponent()
        guard macOSDirectory.lastPathComponent == "MacOS" else {
            return nil
        }

        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        guard contentsDirectory.lastPathComponent == "Contents" else {
            return nil
        }

        let applicationURL = contentsDirectory.deletingLastPathComponent()
        guard applicationURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: applicationURL.path) else {
            return nil
        }
        return applicationURL
    }

    private static func signalProcesses(matching executablePath: String) {
        let argv = ["/usr/bin/pkill", "-TERM", "-f", executablePath]
        var pid: pid_t = 0
        let spawnResult = argv[0].withCString { executablePath in
            withMutableCStringArray(argv) { argvPointer in
                posix_spawn(&pid, executablePath, nil, nil, argvPointer, nil)
            }
        }
        guard spawnResult == 0 else {
            return
        }
        _ = waitpid(pid, nil, 0)
    }

    nonisolated private static func waitForProcess(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        return status
    }

    private static func prepareRunLog(for plan: XemuDesktopLaunchPlan) throws -> URL {
        let logsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DukeXDesktopLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let safeName = plan.gameName
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logURL = logsDirectory.appendingPathComponent("\(safeName)-\(timestamp).log")

        let header = """
        DukeX desktop xemu launch
        Target: \(plan.gameName)
        Config: \(plan.configURL.path)
        Command: \(plan.commandLine)

        """
        try header.write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    nonisolated private static func withMutableCStringArray<Result>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) rethrows -> Result {
        let cStrings = strings.map { strdup($0) }
        defer {
            for pointer in cStrings {
                if let pointer {
                    free(pointer)
                }
            }
        }

        var pointers = cStrings
        pointers.append(nil)
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                fatalError("CString array unexpectedly has no base address.")
            }
            return try body(baseAddress)
        }
    }
}

private enum DesktopLaunchError: LocalizedError {
    case fileAction(String, Int32)
    case spawn(Int32)

    var errorDescription: String? {
        switch self {
        case let .fileAction(operation, code):
            return "xemu launch file action \(operation) failed: \(Self.message(for: code))"
        case let .spawn(code):
            return "xemu launch failed: \(Self.message(for: code))"
        }
    }

    private static func message(for code: Int32) -> String {
        guard let message = strerror(code) else {
            return "POSIX error \(code)"
        }
        return String(cString: message)
    }
}
#endif
