import Foundation

@MainActor
final class GameFolderStore: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var status: Status = .notSelected

    enum Status: Equatable {
        case notSelected
        case valid(mapCount: Int, hasBink: Bool, hasXDemos: Bool)
        case invalid(String)

        var message: String {
            switch self {
            case .notSelected:
                return "Select the Halo_extracted folder stored on this device."
            case let .valid(mapCount, hasBink, hasXDemos):
                var details = "Valid Halo folder • \(mapCount) map file\(mapCount == 1 ? "" : "s")"
                if hasBink { details += " • bink" }
                if hasXDemos { details += " • xdemos" }
                return details
            case let .invalid(reason):
                return reason
            }
        }

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    private let bookmarkKey = "HaloCEPort.GameFolderBookmark.v1"
    private var securityScopedURL: URL?

    init() {
        restoreBookmark()
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    func select(folder url: URL) {
        stopCurrentAccess()
        guard url.startAccessingSecurityScopedResource() else {
            status = .invalid("iOS did not grant access to that folder. Select it again from Files.")
            return
        }

        securityScopedURL = url
        folderURL = url
        persistBookmark(for: url)
        validate(url)
    }

    func forgetFolder() {
        stopCurrentAccess()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderURL = nil
        status = .notSelected
    }

    func revalidate() {
        guard let folderURL else {
            status = .notSelected
            return
        }
        validate(folderURL)
    }

    private func validate(_ root: URL) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            status = .invalid("The selected item is not a folder.")
            return
        }

        let xbe = root.appendingPathComponent("default.xbe", isDirectory: false)
        guard fm.fileExists(atPath: xbe.path) else {
            status = .invalid("default.xbe is missing. Select the top-level Halo_extracted folder.")
            return
        }

        do {
            let handle = try FileHandle(forReadingFrom: xbe)
            defer { try? handle.close() }
            let magic = try handle.read(upToCount: 4) ?? Data()
            guard magic == Data([0x58, 0x42, 0x45, 0x48]) else {
                status = .invalid("default.xbe does not have a valid XBEH header.")
                return
            }
        } catch {
            status = .invalid("default.xbe could not be read: \(error.localizedDescription)")
            return
        }

        let maps = root.appendingPathComponent("maps", isDirectory: true)
        var mapsIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: maps.path, isDirectory: &mapsIsDirectory), mapsIsDirectory.boolValue else {
            status = .invalid("The maps folder is missing.")
            return
        }

        let mapCount: Int
        do {
            let entries = try fm.contentsOfDirectory(at: maps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            mapCount = entries.filter { $0.pathExtension.lowercased() == "map" }.count
        } catch {
            status = .invalid("The maps folder could not be read: \(error.localizedDescription)")
            return
        }

        guard mapCount > 0 else {
            status = .invalid("No .map files were found in the maps folder.")
            return
        }

        let bink = root.appendingPathComponent("bink", isDirectory: true)
        let xdemos = root.appendingPathComponent("xdemos", isDirectory: true)
        var binkIsDirectory: ObjCBool = false
        var xdemosIsDirectory: ObjCBool = false
        let hasBink = fm.fileExists(atPath: bink.path, isDirectory: &binkIsDirectory) && binkIsDirectory.boolValue
        let hasXDemos = fm.fileExists(atPath: xdemos.path, isDirectory: &xdemosIsDirectory) && xdemosIsDirectory.boolValue

        status = .valid(mapCount: mapCount, hasBink: hasBink, hasXDemos: hasXDemos)
    }

    private func persistBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            status = .invalid("Folder access works for this launch, but iOS could not save it for next time: \(error.localizedDescription)")
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return
            }
            securityScopedURL = url
            folderURL = url
            if stale { persistBookmark(for: url) }
            validate(url)
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            status = .notSelected
        }
    }

    private func stopCurrentAccess() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
