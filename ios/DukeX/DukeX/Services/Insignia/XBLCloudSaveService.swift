import Foundation

struct XBLCloudSaveSyncResult {
    let uploadedCount: Int
    let skippedCount: Int
    let downloadedCount: Int
    let existingCount: Int
    let oversizedCount: Int
    let xboxLiveProfileCount: Int
    let directoryName: String

    static func push(uploaded: Int, skipped: Int, oversized: Int, xboxLiveProfiles: Int, directoryName: String) -> XBLCloudSaveSyncResult {
        XBLCloudSaveSyncResult(
            uploadedCount: uploaded,
            skippedCount: skipped,
            downloadedCount: 0,
            existingCount: 0,
            oversizedCount: oversized,
            xboxLiveProfileCount: xboxLiveProfiles,
            directoryName: directoryName
        )
    }

    static func pull(downloaded: Int, existing: Int, directoryName: String) -> XBLCloudSaveSyncResult {
        XBLCloudSaveSyncResult(
            uploadedCount: 0,
            skippedCount: 0,
            downloadedCount: downloaded,
            existingCount: existing,
            oversizedCount: 0,
            xboxLiveProfileCount: 0,
            directoryName: directoryName
        )
    }

    var pushDetail: String {
        var parts = [
            "\(uploadedCount) uploaded",
            "\(skippedCount) already current"
        ]
        if oversizedCount > 0 {
            parts.append("\(oversizedCount) over size limit")
        }
        if xboxLiveProfileCount > 0 {
            parts.append("\(xboxLiveProfileCount) Xbox Live profile\(xboxLiveProfileCount == 1 ? "" : "s") uploaded")
        }
        return "\(parts.joined(separator: ", ")). Local archives are read from \(directoryName)."
    }

    var pullDetail: String {
        "\(downloadedCount) downloaded, \(existingCount) already local. Pulled archives are stored in \(directoryName)."
    }
}

struct XBLCloudSaveService {
    private static let baseURL = URL(string: "https://xb.live/api/me/xbox-saves")!
    private static let accountBaseURL = URL(string: "https://xb.live/api/me/xbox-account")!
    private static let uploadMaxBytes: Int64 = 32 * 1024 * 1024

    func pushLocalSaves(
        sessionKey: String,
        hdd: LibraryFile?,
        eeprom: LibraryFile?,
        cloudSavesDirectoryURL: URL,
        games: [LibraryFile]
    ) async throws -> XBLCloudSaveSyncResult {
        guard let hdd else {
            throw CloudSaveError.missingHDD
        }
        guard let eeprom else {
            throw XboxEEPROMIdentityError.missing
        }

        let identity = try XboxEEPROMIdentity(fileURL: eeprom.url)

        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DukeXCloudSavePush-\(UUID().uuidString)", isDirectory: true)
        let hddStore = FATXHDDCloudSaveStore(hddURL: hdd.url)
        let archives = try hddStore.exportArchives(to: scratchURL, games: games)
        guard !archives.isEmpty else {
            throw CloudSaveError.noLocalArchives(directoryName: "Xbox HDD UDATA")
        }

        let consoleID = try await uploadConsoleData(identity, sessionKey: sessionKey)
        let xboxLiveProfileCount = await uploadXboxLiveProfilesIfEnabled(
            sessionKey: sessionKey,
            consoleID: consoleID,
            hddStore: hddStore
        )
        let manifest = try await fetchManifest(sessionKey: sessionKey)
        var uploaded = 0
        var skipped = 0
        var oversized = 0

        for archive in archives {
            if archive.size > Self.uploadMaxBytes {
                oversized += 1
                continue
            }

            if manifest.contains(titleID: archive.titleID, consoleID: consoleID, fingerprint: archive.fingerprint) {
                skipped += 1
                continue
            }

            try await upload(archive, sessionKey: sessionKey, consoleID: consoleID, hddKeyHex: identity.hddKeyHex)
            uploaded += 1
        }

        return .push(
            uploaded: uploaded,
            skipped: skipped,
            oversized: oversized,
            xboxLiveProfiles: xboxLiveProfileCount,
            directoryName: "Xbox HDD UDATA"
        )
    }

    func pullRemoteSaves(
        sessionKey: String,
        hdd: LibraryFile?,
        eeprom: LibraryFile?,
        cloudSavesDirectoryURL: URL
    ) async throws -> XBLCloudSaveSyncResult {
        guard let hdd else {
            throw CloudSaveError.missingHDD
        }
        guard let eeprom else {
            throw XboxEEPROMIdentityError.missing
        }
        let identity = try XboxEEPROMIdentity(fileURL: eeprom.url)

        try FileManager.default.createDirectory(
            at: cloudSavesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let hddStore = FATXHDDCloudSaveStore(hddURL: hdd.url)
        let localTitleIDs = try hddStore.localTitleIDs()
        let manifest = try await fetchManifest(sessionKey: sessionKey)
        var entries = manifest.remoteEntries
        if entries.isEmpty {
            entries = try await fetchListedRemoteEntries(sessionKey: sessionKey)
        }
        guard !entries.isEmpty else {
            throw CloudSaveError.noRemoteArchives
        }

        let consoleID = try await uploadConsoleData(identity, sessionKey: sessionKey)
        var downloaded = 0
        var existing = 0
        var handledTitleIDs = Set<String>()

        for entry in entries {
            guard handledTitleIDs.insert(entry.titleID).inserted else {
                continue
            }

            if localTitleIDs.contains(entry.titleID) {
                existing += 1
                continue
            }

            let destination = cloudSavesDirectoryURL.appendingPathComponent("\(entry.titleID).dukex")
            let temporaryURL = try await download(
                titleID: entry.titleID,
                sourceConsoleID: entry.consoleID,
                sourceProfile: entry.profile,
                targetConsoleID: consoleID,
                sessionKey: sessionKey
            )
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: temporaryURL, to: destination)
            }
            if try hddStore.importArchive(temporaryURL, titleID: entry.titleID) {
                downloaded += 1
            } else {
                existing += 1
            }
        }

        return .pull(
            downloaded: downloaded,
            existing: existing,
            directoryName: cloudSavesDirectoryURL.lastPathComponent
        )
    }

    private func uploadConsoleData(_ identity: XboxEEPROMIdentity, sessionKey: String) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("console-data"))
        request.httpMethod = "POST"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "sessionKey": sessionKey,
                "serial": identity.serial,
                "hdd_key_hex": identity.hddKeyHex,
                "eeprom_base64": identity.eepromData.base64EncodedString()
            ],
            options: []
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        if let response = try? JSONDecoder().decode(ConsoleDataResponse.self, from: data),
           let consoleID = response.consoleID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !consoleID.isEmpty {
            return consoleID
        }

        return "unknown"
    }

    private func fetchManifest(sessionKey: String) async throws -> CloudSaveManifest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("manifest"))
        request.httpMethod = "GET"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let body = String(data: data, encoding: .utf8) ?? ""
        return CloudSaveManifest(body)
    }

    private func fetchListedRemoteEntries(sessionKey: String) async throws -> [CloudSaveRemoteEntry] {
        var request = URLRequest(url: Self.baseURL)
        request.httpMethod = "GET"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return CloudSaveListParser.remoteEntries(from: object)
    }

    private func upload(
        _ archive: XBLCloudSaveArchive,
        sessionKey: String,
        consoleID: String,
        hddKeyHex: String
    ) async throws {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("game"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title_id", value: archive.titleID),
            URLQueryItem(name: "console_id", value: consoleID),
            URLQueryItem(name: "hdd_key_hex", value: hddKeyHex),
            URLQueryItem(name: "profile", value: ""),
            URLQueryItem(name: "save_count", value: "\(archive.saveCount)"),
            URLQueryItem(name: "total_bytes", value: "\(archive.totalBytes)"),
            URLQueryItem(name: "fingerprint", value: archive.fingerprint),
            URLQueryItem(name: "save_modified", value: "\(archive.modifiedUnixTime)")
        ]

        guard let url = components?.url else {
            throw CloudSaveError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Data(archive.titleName.utf8).base64EncodedString(), forHTTPHeaderField: "X-Title-Name-B64")
        request.setValue(archive.manifestBase64, forHTTPHeaderField: "X-Manifest-B64")

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: archive.url)
        try validate(response: response, data: data)
    }

    private func download(
        titleID: String,
        sourceConsoleID: String?,
        sourceProfile: String?,
        targetConsoleID: String,
        sessionKey: String
    ) async throws -> URL {
        var components = URLComponents(
            url: Self.baseURL
                .appendingPathComponent("download")
                .appendingPathComponent(titleID),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "console_id", value: sourceConsoleID ?? "legacy"),
            URLQueryItem(name: "target_console_id", value: targetConsoleID),
            URLQueryItem(name: "profile", value: sourceProfile ?? "")
        ]

        guard let url = components?.url else {
            throw CloudSaveError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validate(response: response, data: nil)
        return temporaryURL
    }

    private func uploadXboxLiveProfilesIfEnabled(
        sessionKey: String,
        consoleID: String,
        hddStore: FATXHDDCloudSaveStore
    ) async -> Int {
        do {
            let accountSet = try hddStore.xboxLiveAccountSet()
            guard !accountSet.accounts.isEmpty else {
                return 0
            }

            guard try await xboxLiveProfileSyncEnabled(sessionKey: sessionKey) else {
                return 0
            }

            try await uploadXboxLiveProfiles(accountSet, sessionKey: sessionKey, consoleID: consoleID)
            return accountSet.accounts.count
        } catch {
            NSLog("DukeX Xbox Live profile cloud upload skipped: %@", error.localizedDescription)
            return 0
        }
    }

    private func xboxLiveProfileSyncEnabled(sessionKey: String) async throws -> Bool {
        var components = URLComponents(url: Self.accountBaseURL.appendingPathComponent("settings"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sessionKey", value: sessionKey)
        ]

        guard let url = components?.url else {
            throw CloudSaveError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return false
        }

        return CloudSaveListParser.boolValue(dictionary["enabled"]) == true
    }

    private func uploadXboxLiveProfiles(
        _ accountSet: XboxLiveAccountSet,
        sessionKey: String,
        consoleID: String
    ) async throws {
        var request = URLRequest(url: Self.accountBaseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue(sessionKey, forHTTPHeaderField: "X-Session-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let accounts = accountSet.accounts.map { account -> [String: Any] in
            [
                "xuid": account.xuidHex,
                "gamertag": account.gamertag,
                "blob_base64": account.recordData.base64EncodedString()
            ]
        }

        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "sessionKey": sessionKey,
                "console_id": consoleID,
                "source_partition": accountSet.partition,
                "accounts": accounts
            ],
            options: []
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func localArchives(in directoryURL: URL, games: [LibraryFile]) throws -> [XBLCloudSaveArchive] {
        let titleNamesByID = Dictionary(
            uniqueKeysWithValues: games.compactMap { game -> (String, String)? in
                guard let titleID = normalizedTitleID(game.titleID) else {
                    return nil
                }
                return (titleID, game.displayName)
            }
        )

        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("dukex") == .orderedSame,
                  let titleID = normalizedTitleID(url.deletingPathExtension().lastPathComponent) else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }

            let size = Int64(values.fileSize ?? 0)
            let modifiedDate = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let titleName = titleNamesByID[titleID] ?? titleID
            return XBLCloudSaveArchive(
                url: url,
                titleID: titleID,
                titleName: titleName,
                size: size,
                modifiedDate: modifiedDate,
                fingerprint: try fingerprint(for: url, size: size, modifiedDate: modifiedDate)
            )
        }
        .sorted {
            $0.titleID.localizedStandardCompare($1.titleID) == .orderedAscending
        }
    }

    private func normalizedTitleID(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 8,
              normalized.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return normalized
    }

    private func fingerprint(for url: URL, size: Int64, modifiedDate: Date) throws -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        updateHash(&hash, value: UInt64(bitPattern: size))
        updateHash(&hash, value: UInt64(modifiedDate.timeIntervalSince1970))

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            updateHash(&hash, data: chunk)
        }

        return String(format: "%016llx", hash)
    }

    private func updateHash(_ hash: inout UInt64, value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
    }

    private func updateHash(_ hash: inout UInt64, data: Data) {
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudSaveError.unavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            throw CloudSaveError.server(statusCode: httpResponse.statusCode, message: body)
        }
    }
}

private struct ConsoleDataResponse: Decodable {
    let consoleID: String?

    enum CodingKeys: String, CodingKey {
        case consoleID = "console_id"
    }
}

struct XBLCloudSaveArchive {
    let url: URL
    let titleID: String
    let titleName: String
    let size: Int64
    let modifiedDate: Date
    let fingerprint: String
    let saveCount: Int
    let totalBytes: Int64
    let saveModifiedDate: Date
    private let manifestData: Data

    init(
        url: URL,
        titleID: String,
        titleName: String,
        size: Int64,
        modifiedDate: Date,
        fingerprint: String,
        saveCount: Int = 0,
        totalBytes: Int64? = nil,
        saveModifiedDate: Date? = nil,
        manifestData: Data? = nil
    ) {
        self.url = url
        self.titleID = titleID
        self.titleName = titleName
        self.size = size
        self.modifiedDate = modifiedDate
        self.fingerprint = fingerprint
        self.saveCount = saveCount
        self.totalBytes = totalBytes ?? size
        self.saveModifiedDate = saveModifiedDate ?? modifiedDate
        self.manifestData = manifestData ?? Self.defaultManifestData(titleID: titleID, titleName: titleName)
    }

    var modifiedUnixTime: Int {
        Int(saveModifiedDate.timeIntervalSince1970)
    }

    var manifestBase64: String {
        manifestData.base64EncodedString()
    }

    private static func defaultManifestData(titleID: String, titleName: String) -> Data {
        let manifest: [String: Any] = [
            "title_id": titleID,
            "title_name": titleName,
            "saves": []
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [])) ?? Data()
    }
}

private struct CloudSaveManifest {
    let entries: [Entry]

    init(_ body: String) {
        entries = body
            .split(whereSeparator: \.isNewline)
            .compactMap { Entry(String($0)) }
    }

    func contains(titleID: String, consoleID: String, fingerprint: String) -> Bool {
        entries.contains { entry in
            entry.titleID == titleID &&
            (entry.consoleID == nil || entry.consoleID == consoleID) &&
            (entry.profile?.isEmpty ?? true) &&
            entry.fingerprint == fingerprint
        }
    }

    var remoteEntries: [CloudSaveRemoteEntry] {
        entries
            .filter { !$0.noSync }
            .map { CloudSaveRemoteEntry(consoleID: $0.consoleID, profile: $0.profile, titleID: $0.titleID, noSync: $0.noSync) }
    }

    struct Entry {
        let consoleID: String?
        let profile: String?
        let titleID: String
        let fingerprint: String
        let noSync: Bool

        init?(_ line: String) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                return nil
            }

            let rawKey = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let keyParts = rawKey.split(separator: ":", omittingEmptySubsequences: false)

            let possibleConsoleID: String?
            let possibleProfile: String?
            let possibleTitleID: String
            if keyParts.count >= 3 {
                possibleConsoleID = String(keyParts[0])
                let profileParts = keyParts.dropFirst().dropLast()
                possibleProfile = profileParts.isEmpty ? nil : profileParts.joined(separator: ":")
                possibleTitleID = String(keyParts[keyParts.count - 1])
            } else if keyParts.count == 2 {
                possibleConsoleID = String(keyParts[0])
                possibleProfile = nil
                possibleTitleID = String(keyParts[1])
            } else {
                possibleConsoleID = nil
                possibleProfile = nil
                possibleTitleID = rawKey
            }

            let normalizedTitleID = possibleTitleID.uppercased()
            guard normalizedTitleID.count == 8,
                  normalizedTitleID.allSatisfy({ $0.isHexDigit }) else {
                return nil
            }

            let valueParts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
            let parsedFingerprint = valueParts.first.map(String.init) ?? ""
            guard !parsedFingerprint.isEmpty else {
                return nil
            }

            consoleID = possibleConsoleID?.isEmpty == true ? nil : possibleConsoleID
            profile = possibleProfile
            titleID = normalizedTitleID
            fingerprint = parsedFingerprint
            noSync = valueParts.dropFirst().contains { $0.caseInsensitiveCompare("nosync") == .orderedSame }
        }
    }
}

private struct CloudSaveRemoteEntry: Hashable {
    let consoleID: String?
    let profile: String?
    let titleID: String
    let noSync: Bool
}

private enum CloudSaveListParser {
    private static let titleIDKeys: Set<String> = [
        "title_id", "titleid", "title_id_hex", "titleidhex", "game_title_id", "gametitleid"
    ]
    private static let consoleIDKeys: Set<String> = [
        "console_id", "consoleid", "source_console_id", "sourceconsoleid", "console"
    ]
    private static let noSyncKeys: Set<String> = [
        "no_sync", "nosync", "no_sync_back", "nosyncback"
    ]
    private static let profileKeys: Set<String> = [
        "profile", "profile_key", "profilekey", "source_profile", "sourceprofile"
    ]
    private static let syncBackEnabledKeys: Set<String> = [
        "sync_back_enabled", "syncbackenabled", "sync_enabled", "syncenabled"
    ]

    static func remoteEntries(from object: Any) -> [CloudSaveRemoteEntry] {
        var entries: [CloudSaveRemoteEntry] = []
        collectEntries(from: object, inheritedConsoleID: nil, entries: &entries)

        var seen = Set<String>()
        return entries.filter { entry in
            guard !entry.noSync else {
                return false
            }

            let key = "\(entry.consoleID ?? "legacy"):\(entry.profile ?? ""):\(entry.titleID)"
            return seen.insert(key).inserted
        }
    }

    private static func collectEntries(
        from object: Any,
        inheritedConsoleID: String?,
        entries: inout [CloudSaveRemoteEntry]
    ) {
        if let dictionary = object as? [String: Any] {
            let consoleID = normalizedString(from: dictionary, keys: consoleIDKeys) ?? inheritedConsoleID
            let profile = normalizedString(from: dictionary, keys: profileKeys)
            let noSync = noSyncFlag(in: dictionary)

            if let titleID = normalizedTitleID(from: dictionary) {
                entries.append(CloudSaveRemoteEntry(consoleID: consoleID, profile: profile, titleID: titleID, noSync: noSync))
            }

            for (key, value) in dictionary {
                if let titleID = normalizedTitleID(key) {
                    entries.append(CloudSaveRemoteEntry(consoleID: consoleID, profile: profile, titleID: titleID, noSync: noSync))
                }

                collectEntries(from: value, inheritedConsoleID: consoleID, entries: &entries)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectEntries(from: value, inheritedConsoleID: inheritedConsoleID, entries: &entries)
            }
        }
    }

    private static func normalizedTitleID(from dictionary: [String: Any]) -> String? {
        normalizedString(from: dictionary, keys: titleIDKeys).flatMap(normalizedTitleID)
    }

    private static func normalizedString(from dictionary: [String: Any], keys: Set<String>) -> String? {
        for (key, value) in dictionary where keys.contains(normalizedKey(key)) {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func noSyncFlag(in dictionary: [String: Any]) -> Bool {
        for (key, value) in dictionary {
            let normalizedKey = normalizedKey(key)
            if noSyncKeys.contains(normalizedKey), boolValue(value) == true {
                return true
            }
            if syncBackEnabledKeys.contains(normalizedKey), boolValue(value) == false {
                return true
            }
        }
        return false
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let value else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1", "nosync":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func normalizedTitleID(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 8,
              normalized.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return normalized
    }

    private static func normalizedKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

private enum CloudSaveError: LocalizedError {
    case invalidRequest
    case missingHDD
    case noLocalArchives(directoryName: String)
    case noRemoteArchives
    case unavailable
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The xb.live cloud save request could not be created."
        case .missingHDD:
            return "Import an Xbox HDD image before using cloud save sync."
        case .noLocalArchives(let directoryName):
            return "No .dukex save archives were found in \(directoryName)."
        case .noRemoteArchives:
            return "No cloud save archives are available for this xb.live account."
        case .unavailable:
            return "The xb.live cloud save service is unavailable."
        case .server(let statusCode, let message):
            let trimmedMessage = message?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedMessage, !trimmedMessage.isEmpty {
                return trimmedMessage
            }
            return "xb.live returned HTTP \(statusCode)."
        }
    }
}
