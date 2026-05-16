import Darwin
import Foundation

final class XemuDisplayStatsBridge {
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
