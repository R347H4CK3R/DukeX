import Foundation

struct FATXHDDCloudSaveStore {
    let hddURL: URL

    func exportArchives(to directoryURL: URL, games: [LibraryFile]) throws -> [XBLCloudSaveArchive] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        let volume = try openVolume(readOnly: true)
        let titleNamesByID = Dictionary(
            uniqueKeysWithValues: games.compactMap { game -> (String, String)? in
                guard let titleID = GameLaunchLink.normalizedTitleID(game.titleID),
                      titleID.count == 8 else {
                    return nil
                }
                return (titleID, game.displayName)
            }
        )

        let udata = try volume.directory(named: "UDATA", in: volume.rootDirectoryCluster)
        let titleDirectories = try volume.directoryEntries(in: udata.startCluster)
            .filter { $0.isDirectory && Self.isTitleID($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !titleDirectories.isEmpty else {
            throw FATXCloudSaveError.noSaveArchives(try volume.cloudSaveScanReport())
        }

        return try titleDirectories.map { titleDirectory in
            let titleID = titleDirectory.name.uppercased()
            let titleScratchURL = directoryURL
                .appendingPathComponent("fatx-\(titleID)-\(UUID().uuidString)", isDirectory: true)
            let archiveURL = directoryURL.appendingPathComponent("\(titleID).dukex")

            try FileManager.default.createDirectory(at: titleScratchURL, withIntermediateDirectories: true, attributes: nil)

            try volume.extractDirectory(cluster: titleDirectory.startCluster, to: titleScratchURL)

            do {
                try DukeXZipArchive.createArchive(atPath: archiveURL.path, fromDirectory: titleScratchURL.path)
            } catch {
                throw error
            }

            let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values.fileSize ?? 0)
            let modifiedDate = values.contentModificationDate ?? Date()
            let metadata = try volume.archiveMetadata(
                forTitleDirectory: titleDirectory,
                fallbackTitleName: titleNamesByID[titleID] ?? titleID
            )
            let titleName = metadata.titleName ??
                titleNamesByID[titleID] ??
                titleID

            return XBLCloudSaveArchive(
                url: archiveURL,
                titleID: titleID,
                titleName: titleName,
                size: size,
                modifiedDate: modifiedDate,
                fingerprint: metadata.fingerprint,
                saveCount: metadata.saveCount,
                totalBytes: Int64(metadata.totalSize),
                saveModifiedDate: metadata.latestSaveModifiedDate,
                manifestData: metadata.manifestData
            )
        }
    }

    func localTitleIDs() throws -> Set<String> {
        let volume = try openVolume(readOnly: true)
        guard let udata = try? volume.directory(named: "UDATA", in: volume.rootDirectoryCluster) else {
            return []
        }

        let titleIDs = try volume.directoryEntries(in: udata.startCluster)
            .filter { $0.isDirectory && Self.isTitleID($0.name) }
            .map { $0.name.uppercased() }
        return Set(titleIDs)
    }

    func importArchive(_ archiveURL: URL, titleID: String) throws -> Bool {
        let normalizedTitleID = titleID.uppercased()
        guard Self.isTitleID(normalizedTitleID) else {
            throw FATXCloudSaveError.invalidTitleID(titleID)
        }

        let volume = try openVolume(readOnly: false)
        let udata = try volume.ensureDirectory(named: "UDATA", in: volume.rootDirectoryCluster)
        if (try? volume.directory(named: normalizedTitleID, in: udata.startCluster)) != nil {
            return false
        }

        let extractURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DukeXCloudSaveImport-\(normalizedTitleID)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true, attributes: nil)

        do {
            try DukeXZipArchive.extractArchive(atPath: archiveURL.path, toDirectory: extractURL.path)
        } catch {
            throw error
        }

        try volume.importDirectory(from: extractURL, named: normalizedTitleID, into: udata.startCluster)
        return true
    }

    func xboxLiveAccountSet() throws -> XboxLiveAccountSet {
        let image = try XboxDiskImageFactory.open(url: hddURL, readOnly: true)
        return try XboxLiveAccountSet.read(from: image)
    }

    private func openVolume(readOnly: Bool) throws -> FATXVolume {
        let image = try XboxDiskImageFactory.open(url: hddURL, readOnly: readOnly)
        return try FATXVolume.findEPartition(on: image)
    }

    static func isTitleID(_ value: String) -> Bool {
        value.count == 8 && value.allSatisfy { $0.isHexDigit }
    }

    static func fingerprint(for url: URL, size: Int64, modifiedDate: Date) throws -> String {
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

    private static func updateHash(_ hash: inout UInt64, value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
    }

    private static func updateHash(_ hash: inout UInt64, data: Data) {
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
    }
}

struct FATXCloudSaveScanReport {
    let partitionOffset: UInt64
    let rootDirectoryNames: [String]
    let udataDirectoryNames: [String]
    let udataTitleDirectoryNames: [String]
    let tdataDirectoryNames: [String]

    var noSaveArchiveMessage: String {
        var parts = [
            "DukeX found the Xbox E partition at \(Self.hex(partitionOffset)), but E:\\UDATA has no 8-character TitleID save folders to upload."
        ]

        if rootDirectoryNames.isEmpty {
            parts.append("No root folders were visible on the partition.")
        } else {
            parts.append("Root folders found: \(sample(rootDirectoryNames)).")
        }

        if udataDirectoryNames.isEmpty {
            parts.append("E:\\UDATA is empty. Launch a game and create a save first, then try Push Saves to Cloud again.")
        } else {
            parts.append("E:\\UDATA folders found: \(sample(udataDirectoryNames)).")
            parts.append("None of those folders matched the Xbox save TitleID format.")
        }

        if !tdataDirectoryNames.isEmpty {
            parts.append("E:\\TDATA has \(tdataDirectoryNames.count) title-data folder(s), but TDATA is used for title data, DLC, and cache rather than game saves.")
        }

        return parts.joined(separator: " ")
    }

    private func sample(_ values: [String]) -> String {
        let visible = values.prefix(8).joined(separator: ", ")
        if values.count > 8 {
            return "\(visible), +\(values.count - 8) more"
        }
        return visible
    }

    private static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }
}

private final class FATXVolume {
    private static let fatxSignature = Data([0x46, 0x41, 0x54, 0x58])
    private static let sectorSize: UInt64 = 512
    private static let superblockSize: UInt64 = 4096
    private static let cachePartitionSize: UInt64 = 0x2EE00000
    private static let systemPartitionSize: UInt64 = 0x1F400000
    private static let ePartitionOffset: UInt64 = 0xABE80000
    private static let ePartitionSize: UInt64 = 0x131F00000

    let image: XboxDiskImage
    let partitionStart: UInt64
    let partitionSize: UInt64
    let sectorsPerCluster: UInt32
    let rootDirectoryCluster: UInt32
    let entrySize: UInt64
    let clusterSize: UInt64
    let fatStart: UInt64
    let dataStart: UInt64
    let clusterCount: UInt32

    static func findEPartition(on image: XboxDiskImage) throws -> FATXVolume {
        var fallback: FATXVolume?
        for candidate in partitionCandidates(for: image) where candidate.size >= superblockSize {
            let header = try image.read(at: candidate.offset, count: Int(superblockSize))
            guard header.prefix(4) == fatxSignature else {
                continue
            }

            let volume = try FATXVolume(
                image: image,
                partitionStart: candidate.offset,
                partitionSize: candidate.size,
                header: header
            )

            if candidate.isPreferredEPartition {
                return volume
            }

            if fallback == nil || (try? volume.directory(named: "UDATA", in: volume.rootDirectoryCluster)) != nil {
                fallback = volume
            }
        }

        if let fallback {
            return fallback
        }

        throw FATXCloudSaveError.fatxPartitionMissing
    }

    private static func partitionCandidates(for image: XboxDiskImage) -> [FATXPartitionCandidate] {
        let standard: [FATXPartitionCandidate] = [
            FATXPartitionCandidate(offset: ePartitionOffset, size: ePartitionSize, isPreferredEPartition: true),
            FATXPartitionCandidate(offset: 0, size: image.virtualSize, isPreferredEPartition: false),
            FATXPartitionCandidate(offset: 0x00080000, size: cachePartitionSize, isPreferredEPartition: false),
            FATXPartitionCandidate(offset: 0x2EE80000, size: cachePartitionSize, isPreferredEPartition: false),
            FATXPartitionCandidate(offset: 0x5DC80000, size: cachePartitionSize, isPreferredEPartition: false),
            FATXPartitionCandidate(offset: 0x8CA80000, size: systemPartitionSize, isPreferredEPartition: false)
        ]

        return standard.compactMap { candidate in
            guard candidate.offset < image.virtualSize else {
                return nil
            }

            let maximumSize = image.virtualSize - candidate.offset
            guard maximumSize >= superblockSize else {
                return nil
            }

            return FATXPartitionCandidate(
                offset: candidate.offset,
                size: min(candidate.size, maximumSize),
                isPreferredEPartition: candidate.isPreferredEPartition
            )
        }
    }

    init(image: XboxDiskImage, partitionStart: UInt64, partitionSize: UInt64, header: Data) throws {
        self.image = image
        self.partitionStart = partitionStart
        self.partitionSize = partitionSize
        sectorsPerCluster = header.uint32LE(at: 8)
        rootDirectoryCluster = header.uint32LE(at: 12)
        guard sectorsPerCluster > 0, rootDirectoryCluster > 0 else {
            throw FATXCloudSaveError.invalidFATXVolume
        }

        clusterSize = UInt64(sectorsPerCluster) * Self.sectorSize
        let type = Self.layoutType(partitionSize: partitionSize, clusterSize: clusterSize)
        entrySize = type.entrySize
        clusterCount = type.clusterCount
        fatStart = partitionStart + Self.superblockSize
        dataStart = partitionStart + Self.superblockSize + type.fatSize
    }

    private static func layoutType(partitionSize: UInt64, clusterSize: UInt64) -> (entrySize: UInt64, clusterCount: UInt32, fatSize: UInt64) {
        for entrySize in [UInt64(2), UInt64(4)] {
            let estimated = (partitionSize - superblockSize) / (clusterSize + entrySize)
            let fatBytes = roundUp(max(estimated, 1) * entrySize, to: superblockSize)
            let clusters = (partitionSize - superblockSize - fatBytes) / clusterSize
            if (entrySize == 2 && clusters < 65_525) || (entrySize == 4 && clusters >= 65_525) {
                return (entrySize, UInt32(clusters), roundUp(clusters * entrySize, to: superblockSize))
            }
        }

        let clusters = (partitionSize - superblockSize) / (clusterSize + 4)
        return (4, UInt32(clusters), roundUp(clusters * 4, to: superblockSize))
    }

    func directory(named name: String, in parentCluster: UInt32) throws -> FATXDirectoryEntry {
        guard let entry = try directoryEntries(in: parentCluster)
            .first(where: { $0.isDirectory && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw FATXCloudSaveError.pathMissing(name)
        }
        return entry
    }

    func cloudSaveScanReport() throws -> FATXCloudSaveScanReport {
        let rootDirectories = try directoryEntries(in: rootDirectoryCluster)
            .filter(\.isDirectory)
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let udataDirectoryNames = childDirectoryNames(named: "UDATA")
        let tdataDirectoryNames = childDirectoryNames(named: "TDATA")

        return FATXCloudSaveScanReport(
            partitionOffset: partitionStart,
            rootDirectoryNames: rootDirectories,
            udataDirectoryNames: udataDirectoryNames,
            udataTitleDirectoryNames: udataDirectoryNames.filter(FATXHDDCloudSaveStore.isTitleID),
            tdataDirectoryNames: tdataDirectoryNames
        )
    }

    func ensureDirectory(named name: String, in parentCluster: UInt32) throws -> FATXDirectoryEntry {
        if let existing = try? directory(named: name, in: parentCluster) {
            return existing
        }

        let cluster = try allocateClusters(count: 1)[0]
        try writeDirectoryEntry(
            FATXDirectoryEntry(name: name, attributes: 0x10, size: 0, startCluster: cluster, entryOffset: 0),
            in: parentCluster
        )
        return FATXDirectoryEntry(name: name, attributes: 0x10, size: 0, startCluster: cluster, entryOffset: 0)
    }

    func directoryEntries(in cluster: UInt32) throws -> [FATXDirectoryEntry] {
        var entries: [FATXDirectoryEntry] = []
        for directoryCluster in try clusterChain(startingAt: cluster) {
            let clusterOffset = dataOffset(for: directoryCluster)
            let data = try image.read(at: clusterOffset, count: Int(clusterSize))
            let count = Int(clusterSize / 64)
            for index in 0..<count {
                let offset = index * 64
                let nameLength = data[offset]
                if nameLength == 0x00 {
                    continue
                }
                if nameLength == 0xE5 || nameLength == 0xFF {
                    continue
                }
                guard nameLength <= 42 else {
                    continue
                }

                let nameData = data.subdata(in: (offset + 2)..<(offset + 2 + Int(nameLength)))
                guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                    continue
                }

                entries.append(
                    FATXDirectoryEntry(
                        name: name,
                        attributes: data[offset + 1],
                        size: data.uint32LE(at: offset + 48),
                        startCluster: data.uint32LE(at: offset + 44),
                        entryOffset: clusterOffset + UInt64(offset),
                        modifiedDate: Self.date(
                            fromFATDate: data.uint16LE(at: offset + 56),
                            time: data.uint16LE(at: offset + 58)
                        )
                    )
                )
            }
        }
        return entries
    }

    private func childDirectoryNames(named name: String) -> [String] {
        guard let directory = try? directory(named: name, in: rootDirectoryCluster),
              let entries = try? directoryEntries(in: directory.startCluster) else {
            return []
        }

        return entries
            .filter(\.isDirectory)
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func extractDirectory(cluster: UInt32, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        for entry in try directoryEntries(in: cluster) {
            let childURL = destinationURL.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
            if entry.isDirectory {
                try extractDirectory(cluster: entry.startCluster, to: childURL)
            } else {
                try readFile(entry).write(to: childURL, options: .atomic)
            }
        }
    }

    func importDirectory(from sourceURL: URL, named name: String, into parentCluster: UInt32) throws {
        let destination = try ensureDirectory(named: name, in: parentCluster)
        try importChildren(from: sourceURL, into: destination.startCluster)
    }

    func titleName(forTitleDirectory entry: FATXDirectoryEntry) throws -> String? {
        guard let titleMeta = try? directoryEntries(in: entry.startCluster)
            .first(where: { !$0.isDirectory && $0.name.caseInsensitiveCompare("TitleMeta.xbx") == .orderedSame }) else {
            return nil
        }

        let data = try readFile(titleMeta)
        return Self.metadataValue(named: "TitleName", in: data)
    }

    func archiveMetadata(forTitleDirectory entry: FATXDirectoryEntry, fallbackTitleName: String) throws -> FATXTitleArchiveMetadata {
        let entries = try directoryEntries(in: entry.startCluster)
        let titleMeta = entries.first(where: { !$0.isDirectory && $0.name.caseInsensitiveCompare("TitleMeta.xbx") == .orderedSame })
        let titleName = try titleMeta.flatMap { Self.metadataValue(named: "TitleName", in: try readFile($0)) } ??
            fallbackTitleName
        let stats = try directoryStats(cluster: entry.startCluster)
        let saves = try entries
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { saveEntry in
                let saveStats = try directoryStats(cluster: saveEntry.startCluster)
                let saveEntries = try directoryEntries(in: saveEntry.startCluster)
                let saveMeta = saveEntries.first(where: { !$0.isDirectory && $0.name.caseInsensitiveCompare("SaveMeta.xbx") == .orderedSame })
                let saveName = try saveMeta.flatMap { Self.metadataValue(named: "Name", in: try readFile($0)) } ??
                    "<corrupted save>"
                return FATXSaveArchiveMetadata(
                    folderName: saveEntry.name,
                    saveName: saveName,
                    fileCount: saveStats.fileCount,
                    totalSize: saveStats.totalSize,
                    modifiedDate: saveEntry.modifiedDate
                )
            }

        return FATXTitleArchiveMetadata(
            titleID: entry.name.uppercased(),
            titleName: titleName,
            fileCount: stats.fileCount,
            totalSize: stats.totalSize,
            saves: saves
        )
    }

    private func importChildren(from sourceURL: URL, into directoryCluster: UInt32) throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let name = child.lastPathComponent
            guard !name.isEmpty, Data(name.utf8).count <= 42 else {
                continue
            }

            if values.isDirectory == true {
                let entry = try ensureDirectory(named: name, in: directoryCluster)
                try importChildren(from: child, into: entry.startCluster)
            } else {
                let data = try Data(contentsOf: child)
                try writeFile(named: name, data: data, into: directoryCluster)
            }
        }
    }

    private func directoryStats(cluster: UInt32) throws -> (fileCount: Int, totalSize: UInt64) {
        var fileCount = 0
        var totalSize: UInt64 = 0
        for entry in try directoryEntries(in: cluster) {
            if entry.isDirectory {
                let child = try directoryStats(cluster: entry.startCluster)
                fileCount += child.fileCount
                totalSize += child.totalSize
            } else {
                fileCount += 1
                totalSize += UInt64(entry.size)
            }
        }
        return (fileCount, totalSize)
    }

    private func readFile(_ entry: FATXDirectoryEntry) throws -> Data {
        guard entry.size > 0, entry.startCluster > 0 else {
            return Data()
        }

        var remaining = Int(entry.size)
        var output = Data()
        for cluster in try clusterChain(startingAt: entry.startCluster) {
            let count = min(remaining, Int(clusterSize))
            output.append(try image.read(at: dataOffset(for: cluster), count: count))
            remaining -= count
            if remaining <= 0 {
                break
            }
        }
        return output
    }

    private func writeFile(named name: String, data: Data, into directoryCluster: UInt32) throws {
        let clustersNeeded = max(1, Int((UInt64(data.count) + clusterSize - 1) / clusterSize))
        let clusters = try allocateClusters(count: clustersNeeded)

        var cursor = 0
        for cluster in clusters {
            var chunk = Data(repeating: 0, count: Int(clusterSize))
            let count = min(data.count - cursor, Int(clusterSize))
            if count > 0 {
                chunk.replaceSubrange(0..<count, with: data[cursor..<(cursor + count)])
            }
            try image.write(at: dataOffset(for: cluster), data: chunk)
            cursor += count
        }

        try writeDirectoryEntry(
            FATXDirectoryEntry(
                name: name,
                attributes: 0x20,
                size: UInt32(data.count),
                startCluster: clusters[0],
                entryOffset: 0
            ),
            in: directoryCluster
        )
    }

    private func writeDirectoryEntry(_ entry: FATXDirectoryEntry, in directoryCluster: UInt32) throws {
        if let existing = try directoryEntries(in: directoryCluster)
            .first(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
            throw FATXCloudSaveError.pathAlreadyExists(existing.name)
        }

        let slot = try freeDirectorySlot(in: directoryCluster)
        var data = Data(repeating: 0xFF, count: 64)
        let nameData = Data(entry.name.utf8).prefix(42)
        data[0] = UInt8(nameData.count)
        data[1] = entry.attributes
        data.replaceSubrange(2..<(2 + nameData.count), with: nameData)
        data.writeUInt32LE(entry.startCluster, at: 44)
        data.writeUInt32LE(entry.size, at: 48)
        let timestamp = Self.fatTimestamp()
        data.writeUInt16LE(timestamp.date, at: 52)
        data.writeUInt16LE(timestamp.time, at: 54)
        data.writeUInt16LE(timestamp.date, at: 56)
        data.writeUInt16LE(timestamp.time, at: 58)
        data.writeUInt16LE(timestamp.date, at: 60)
        data.writeUInt16LE(timestamp.time, at: 62)
        try image.write(at: slot, data: data)
    }

    private func freeDirectorySlot(in directoryCluster: UInt32) throws -> UInt64 {
        let chain = try clusterChain(startingAt: directoryCluster)
        for cluster in chain {
            let clusterOffset = dataOffset(for: cluster)
            let data = try image.read(at: clusterOffset, count: Int(clusterSize))
            let count = Int(clusterSize / 64)
            for index in 0..<count {
                let nameLength = data[index * 64]
                if nameLength == 0x00 || nameLength == 0xE5 || nameLength == 0xFF {
                    return clusterOffset + UInt64(index * 64)
                }
            }
        }

        let newCluster = try appendCluster(toChainStartingAt: directoryCluster)
        return dataOffset(for: newCluster)
    }

    private func clusterChain(startingAt cluster: UInt32) throws -> [UInt32] {
        guard cluster > 0 else {
            return []
        }

        var chain: [UInt32] = []
        var seen = Set<UInt32>()
        var current = cluster
        while current > 0, current <= clusterCount, seen.insert(current).inserted {
            chain.append(current)
            let next = try readFAT(cluster: current)
            if isEndOfChain(next) {
                break
            }
            current = next
        }
        return chain
    }

    private func allocateClusters(count: Int) throws -> [UInt32] {
        guard count > 0 else {
            return []
        }

        var clusters: [UInt32] = []
        var cluster: UInt32 = 1
        while cluster <= clusterCount && clusters.count < count {
            if try readFAT(cluster: cluster) == 0 {
                clusters.append(cluster)
            }
            cluster += 1
        }

        guard clusters.count == count else {
            throw FATXCloudSaveError.volumeFull
        }

        for (index, cluster) in clusters.enumerated() {
            let next = index == clusters.count - 1 ? endOfChainValue : clusters[index + 1]
            try writeFAT(cluster: cluster, value: next)
            try image.write(at: dataOffset(for: cluster), data: Data(repeating: 0, count: Int(clusterSize)))
        }

        return clusters
    }

    private func appendCluster(toChainStartingAt startCluster: UInt32) throws -> UInt32 {
        let chain = try clusterChain(startingAt: startCluster)
        guard let last = chain.last else {
            throw FATXCloudSaveError.invalidFATXVolume
        }

        let newCluster = try allocateClusters(count: 1)[0]
        try writeFAT(cluster: last, value: newCluster)
        try writeFAT(cluster: newCluster, value: endOfChainValue)
        return newCluster
    }

    private func readFAT(cluster: UInt32) throws -> UInt32 {
        let offset = fatStart + UInt64(cluster - 1) * entrySize
        let data = try image.read(at: offset, count: Int(entrySize))
        if entrySize == 2 {
            return UInt32(data.uint16LE(at: 0))
        }
        return data.uint32LE(at: 0)
    }

    private func writeFAT(cluster: UInt32, value: UInt32) throws {
        let offset = fatStart + UInt64(cluster - 1) * entrySize
        var data = Data(repeating: 0, count: Int(entrySize))
        if entrySize == 2 {
            data.writeUInt16LE(UInt16(truncatingIfNeeded: value), at: 0)
        } else {
            data.writeUInt32LE(value, at: 0)
        }
        try image.write(at: offset, data: data)
    }

    private var endOfChainValue: UInt32 {
        entrySize == 2 ? 0xFFF8 : 0xFFFFFFF8
    }

    private func isEndOfChain(_ value: UInt32) -> Bool {
        entrySize == 2 ? value >= 0xFFF8 : value >= 0xFFFFFFF8
    }

    private func dataOffset(for cluster: UInt32) -> UInt64 {
        dataStart + UInt64(cluster - 1) * clusterSize
    }

    private static func metadataValue(named key: String, in data: Data) -> String? {
        let text: String?
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            text = String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian)
        } else {
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        }

        guard let text else {
            return nil
        }

        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(key) == .orderedSame else {
                continue
            }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func fatTimestamp() -> (date: UInt16, time: UInt16) {
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, components.year ?? 1980)
        let date = UInt16(((year - 1980) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        let time = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        return (date, time)
    }

    private static func date(fromFATDate date: UInt16, time: UInt16) -> Date? {
        let year = 1980 + Int((date >> 9) & 0x7F)
        let month = Int((date >> 5) & 0x0F)
        let day = Int(date & 0x1F)
        let hour = Int((time >> 11) & 0x1F)
        let minute = Int((time >> 5) & 0x3F)
        let second = Int(time & 0x1F) * 2

        guard (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }

    fileprivate static func roundUp(_ value: UInt64, to alignment: UInt64) -> UInt64 {
        ((value + alignment - 1) / alignment) * alignment
    }
}

private struct FATXDirectoryEntry {
    let name: String
    let attributes: UInt8
    let size: UInt32
    let startCluster: UInt32
    let entryOffset: UInt64
    let modifiedDate: Date?

    init(
        name: String,
        attributes: UInt8,
        size: UInt32,
        startCluster: UInt32,
        entryOffset: UInt64,
        modifiedDate: Date? = nil
    ) {
        self.name = name
        self.attributes = attributes
        self.size = size
        self.startCluster = startCluster
        self.entryOffset = entryOffset
        self.modifiedDate = modifiedDate
    }

    var isDirectory: Bool {
        attributes & 0x10 != 0
    }
}

private struct FATXTitleArchiveMetadata {
    let titleID: String
    let titleName: String?
    let fileCount: Int
    let totalSize: UInt64
    let saves: [FATXSaveArchiveMetadata]

    var saveCount: Int {
        saves.count
    }

    var latestSaveModifiedDate: Date {
        saves.compactMap(\.modifiedDate).max() ?? Date(timeIntervalSince1970: 0)
    }

    var manifestData: Data {
        let saveObjects = saves.map { save -> [String: Any] in
            [
                "folder": save.folderName,
                "name": save.saveName,
                "files": save.fileCount,
                "bytes": Int64(clamping: save.totalSize),
                "modified": Int(save.modifiedDate?.timeIntervalSince1970 ?? 0)
            ]
        }
        let manifest: [String: Any] = [
            "title_id": titleID,
            "title_name": titleName ?? titleID,
            "saves": saveObjects
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [])) ?? Data()
    }

    var fingerprint: String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        Self.updateHash(&hash, value: Int32(clamping: fileCount))
        Self.updateHash(&hash, value: totalSize)
        for save in saves {
            Self.updateHash(&hash, data: Data(save.folderName.utf8))
            Self.updateHash(&hash, value: Int32(clamping: save.fileCount))
            Self.updateHash(&hash, value: save.totalSize)
            Self.updateHash(&hash, value: save.windowsFileTime)
        }
        return String(format: "%016llx", hash)
    }

    private static func updateHash(_ hash: inout UInt64, value: Int32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { updateHash(&hash, bytes: $0) }
    }

    private static func updateHash(_ hash: inout UInt64, value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { updateHash(&hash, bytes: $0) }
    }

    private static func updateHash(_ hash: inout UInt64, data: Data) {
        data.withUnsafeBytes { updateHash(&hash, bytes: $0) }
    }

    private static func updateHash(_ hash: inout UInt64, bytes: UnsafeRawBufferPointer) {
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
    }
}

private struct FATXSaveArchiveMetadata {
    let folderName: String
    let saveName: String
    let fileCount: Int
    let totalSize: UInt64
    let modifiedDate: Date?

    var windowsFileTime: UInt64 {
        guard let modifiedDate else {
            return 0
        }
        let ticks = max(0, modifiedDate.timeIntervalSince1970) * 10_000_000
        return 116_444_736_000_000_000 + UInt64(ticks.rounded())
    }
}

private struct FATXPartitionCandidate {
    let offset: UInt64
    let size: UInt64
    let isPreferredEPartition: Bool
}

struct XboxLiveAccountSet {
    fileprivate static let accountRecordLength = 0x6C
    private static let maxAccountCount = 8
    private static let sectorSize = 512
    private static let firstAccountSector = 12
    private static let accountOffsetInSector = 0x0C
    private static let configHeader: UInt32 = 0x79132568

    let partition: Int
    let accounts: [XboxLiveAccount]

    fileprivate static func read(from image: XboxDiskImage) throws -> XboxLiveAccountSet {
        let byteOffset = UInt64(firstAccountSector * sectorSize)
        let sectors = try image.read(at: byteOffset, count: maxAccountCount * sectorSize)
        let accounts = (0..<maxAccountCount).compactMap { slot -> XboxLiveAccount? in
            let sectorOffset = slot * sectorSize
            guard sectorOffset + sectorSize <= sectors.count,
                  sectors.uint32LE(at: sectorOffset) == configHeader else {
                return nil
            }

            let recordStart = sectorOffset + accountOffsetInSector
            let recordEnd = recordStart + accountRecordLength
            guard recordEnd <= sectors.count else {
                return nil
            }

            let record = sectors.subdata(in: recordStart..<recordEnd)
            guard accountRecordIsPresent(record) else {
                return nil
            }

            return XboxLiveAccount(
                slot: slot,
                gamertag: gamertag(from: record),
                xuidHex: String(format: "%016llX", record.uint64LE(at: 0)),
                recordData: record
            )
        }

        return XboxLiveAccountSet(partition: 0, accounts: accounts)
    }

    private static func accountRecordIsPresent(_ record: Data) -> Bool {
        guard record.count >= accountRecordLength else {
            return false
        }

        let firstGamertagByte = record[0x0C]
        guard firstGamertagByte >= 0x20, firstGamertagByte <= 0x7E else {
            return false
        }

        let xuid = record.uint64LE(at: 0)
        return xuid != 0 && xuid != UInt64.max
    }

    private static func gamertag(from record: Data) -> String {
        var bytes: [UInt8] = []
        for offset in 0x0C..<(0x0C + 15) {
            let byte = record[offset]
            if byte == 0 {
                break
            }
            bytes.append((byte >= 0x20 && byte < 0x7F) ? byte : UInt8(ascii: "?"))
        }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

struct XboxLiveAccount {
    let slot: Int
    let gamertag: String
    let xuidHex: String
    let recordData: Data
}

fileprivate protocol XboxDiskImage: AnyObject {
    var virtualSize: UInt64 { get }
    func read(at offset: UInt64, count: Int) throws -> Data
    func write(at offset: UInt64, data: Data) throws
}

private enum XboxDiskImageFactory {
    static func open(url: URL, readOnly: Bool) throws -> XboxDiskImage {
        let headerHandle = try FileHandle(forReadingFrom: url)
        let magic = try headerHandle.read(upToCount: 4) ?? Data()
        try? headerHandle.close()
        if magic == Data([0x51, 0x46, 0x49, 0xFB]) {
            return try Qcow2DiskImage(url: url, readOnly: readOnly)
        }
        return try RawDiskImage(url: url, readOnly: readOnly)
    }
}

private final class RawDiskImage: XboxDiskImage {
    private let handle: FileHandle
    let virtualSize: UInt64
    private let readOnly: Bool

    init(url: URL, readOnly: Bool) throws {
        self.readOnly = readOnly
        handle = readOnly ? try FileHandle(forReadingFrom: url) : try FileHandle(forUpdating: url)
        virtualSize = try handle.seekToEnd()
    }

    func read(at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        if data.count < count {
            return data + Data(repeating: 0, count: count - data.count)
        }
        return data
    }

    func write(at offset: UInt64, data: Data) throws {
        guard !readOnly else {
            throw FATXCloudSaveError.readOnlyImage
        }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }
}

private final class Qcow2DiskImage: XboxDiskImage {
    private static let copiedFlag: UInt64 = 1 << 63
    private static let compressedFlag: UInt64 = 1 << 62
    private static let offsetMask: UInt64 = 0x00FF_FFFF_FFFF_FE00

    private let handle: FileHandle
    private let readOnly: Bool
    private let clusterBits: UInt32
    private let clusterSize: UInt64
    private let l2Entries: UInt64
    private let l1TableOffset: UInt64
    private let l1Size: UInt32
    private let refcountTableOffset: UInt64
    private let refcountTableClusters: UInt32
    private var l1Table: [UInt64]
    let virtualSize: UInt64

    init(url: URL, readOnly: Bool) throws {
        self.readOnly = readOnly
        handle = readOnly ? try FileHandle(forReadingFrom: url) : try FileHandle(forUpdating: url)

        let header = try Self.read(from: handle, at: 0, count: 104)
        guard header.uint32BE(at: 0) == 0x514649FB else {
            throw FATXCloudSaveError.unsupportedHDDFormat("The HDD image is not qcow2.")
        }

        let version = header.uint32BE(at: 4)
        guard version == 2 || version == 3 else {
            throw FATXCloudSaveError.unsupportedHDDFormat("Unsupported qcow2 version \(version).")
        }
        guard header.uint32BE(at: 32) == 0 else {
            throw FATXCloudSaveError.unsupportedHDDFormat("Encrypted qcow2 HDD images are not supported.")
        }

        let incompatibleFeatures = version >= 3 ? header.uint64BE(at: 72) : 0
        guard incompatibleFeatures & ~UInt64(1) == 0 else {
            throw FATXCloudSaveError.unsupportedHDDFormat("This qcow2 HDD uses unsupported incompatible features.")
        }

        virtualSize = header.uint64BE(at: 24)
        clusterBits = header.uint32BE(at: 20)
        clusterSize = UInt64(1) << clusterBits
        l2Entries = clusterSize / 8
        l1Size = header.uint32BE(at: 36)
        l1TableOffset = header.uint64BE(at: 40)
        refcountTableOffset = header.uint64BE(at: 48)
        refcountTableClusters = header.uint32BE(at: 56)

        let l1Data = try Self.read(from: handle, at: l1TableOffset, count: Int(l1Size) * 8)
        l1Table = (0..<Int(l1Size)).map { l1Data.uint64BE(at: $0 * 8) }
    }

    func read(at offset: UInt64, count: Int) throws -> Data {
        var output = Data()
        var cursor = offset
        var remaining = count
        while remaining > 0 {
            let offsetInCluster = cursor % clusterSize
            let chunkCount = min(remaining, Int(clusterSize - offsetInCluster))
            if let physical = try physicalOffset(forGuestOffset: cursor, allocate: false) {
                output.append(try Self.read(from: handle, at: physical + offsetInCluster, count: chunkCount))
            } else {
                output.append(Data(repeating: 0, count: chunkCount))
            }
            cursor += UInt64(chunkCount)
            remaining -= chunkCount
        }
        return output
    }

    func write(at offset: UInt64, data: Data) throws {
        guard !readOnly else {
            throw FATXCloudSaveError.readOnlyImage
        }

        var cursor = offset
        var dataOffset = 0
        var remaining = data.count
        while remaining > 0 {
            let offsetInCluster = cursor % clusterSize
            let chunkCount = min(remaining, Int(clusterSize - offsetInCluster))
            guard let physical = try physicalOffset(forGuestOffset: cursor, allocate: true) else {
                throw FATXCloudSaveError.unsupportedHDDFormat("Could not allocate qcow2 storage.")
            }
            try handle.seek(toOffset: physical + offsetInCluster)
            try handle.write(contentsOf: data.subdata(in: dataOffset..<(dataOffset + chunkCount)))
            cursor += UInt64(chunkCount)
            dataOffset += chunkCount
            remaining -= chunkCount
        }
    }

    private func physicalOffset(forGuestOffset guestOffset: UInt64, allocate: Bool) throws -> UInt64? {
        let guestCluster = guestOffset / clusterSize
        let l1Index = Int(guestCluster / l2Entries)
        let l2Index = Int(guestCluster % l2Entries)
        guard l1Index < l1Table.count else {
            return nil
        }

        var l2Offset = l1Table[l1Index] & Self.offsetMask
        if l2Offset == 0 {
            guard allocate else {
                return nil
            }
            l2Offset = try allocateHostCluster()
            l1Table[l1Index] = l2Offset | Self.copiedFlag
            try writeUInt64BE(l1Table[l1Index], at: l1TableOffset + UInt64(l1Index) * 8)
        }

        let entryOffset = l2Offset + UInt64(l2Index) * 8
        var l2Entry = try Self.read(from: handle, at: entryOffset, count: 8).uint64BE(at: 0)
        guard l2Entry & Self.compressedFlag == 0 else {
            throw FATXCloudSaveError.unsupportedHDDFormat("Compressed qcow2 clusters are not supported for save sync.")
        }

        var physical = l2Entry & Self.offsetMask
        if physical == 0 {
            guard allocate else {
                return nil
            }
            physical = try allocateHostCluster()
            l2Entry = physical | Self.copiedFlag
            try writeUInt64BE(l2Entry, at: entryOffset)
        }

        return physical
    }

    private func allocateHostCluster() throws -> UInt64 {
        var end = try handle.seekToEnd()
        end = FATXVolume.roundUp(end, to: clusterSize)
        try handle.seek(toOffset: end)
        try handle.write(contentsOf: Data(repeating: 0, count: Int(clusterSize)))
        try setRefcount(forHostOffset: end, value: 1)
        return end
    }

    private func setRefcount(forHostOffset hostOffset: UInt64, value: UInt16) throws {
        let hostCluster = hostOffset / clusterSize
        let entriesPerBlock = clusterSize / 2
        let blockIndex = hostCluster / entriesPerBlock
        let entryIndex = hostCluster % entriesPerBlock
        let tableEntries = UInt64(refcountTableClusters) * clusterSize / 8
        guard blockIndex < tableEntries else {
            throw FATXCloudSaveError.unsupportedHDDFormat("The qcow2 refcount table needs to grow before save import can continue.")
        }

        let tableEntryOffset = refcountTableOffset + blockIndex * 8
        var blockOffset = try Self.read(from: handle, at: tableEntryOffset, count: 8).uint64BE(at: 0) & Self.offsetMask
        if blockOffset == 0 {
            blockOffset = FATXVolume.roundUp(try handle.seekToEnd(), to: clusterSize)
            try handle.seek(toOffset: blockOffset)
            try handle.write(contentsOf: Data(repeating: 0, count: Int(clusterSize)))
            try writeUInt64BE(blockOffset, at: tableEntryOffset)
            try setRefcount(forHostOffset: blockOffset, value: 1)
        }

        var data = Data(repeating: 0, count: 2)
        data.writeUInt16BE(value, at: 0)
        try handle.seek(toOffset: blockOffset + entryIndex * 2)
        try handle.write(contentsOf: data)
    }

    private func writeUInt64BE(_ value: UInt64, at offset: UInt64) throws {
        var data = Data(repeating: 0, count: 8)
        data.writeUInt64BE(value, at: 0)
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }

    private static func read(from handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        if data.count < count {
            return data + Data(repeating: 0, count: count - data.count)
        }
        return data
    }
}

enum FATXCloudSaveError: LocalizedError {
    case archiveCreationFailed(String)
    case archiveExtractionFailed(String)
    case fatxPartitionMissing
    case invalidFATXVolume
    case invalidTitleID(String)
    case noSaveArchives(FATXCloudSaveScanReport)
    case pathAlreadyExists(String)
    case pathMissing(String)
    case readOnlyImage
    case unsupportedHDDFormat(String)
    case volumeFull

    var errorDescription: String? {
        switch self {
        case .archiveCreationFailed(let titleID):
            return "Could not create the .dukex archive for \(titleID)."
        case .archiveExtractionFailed(let titleID):
            return "Could not extract the .dukex archive for \(titleID)."
        case .fatxPartitionMissing:
            return "DukeX could not find the FATX E partition in the selected HDD image."
        case .invalidFATXVolume:
            return "The FATX volume metadata is invalid."
        case .invalidTitleID(let value):
            return "\(value) is not a valid Xbox TitleID."
        case .noSaveArchives(let report):
            return report.noSaveArchiveMessage
        case .pathAlreadyExists(let name):
            return "\(name) already exists on the Xbox HDD."
        case .pathMissing(let name):
            return "\(name) was not found on the Xbox HDD."
        case .readOnlyImage:
            return "The HDD image is open read-only."
        case .unsupportedHDDFormat(let message):
            return message
        case .volumeFull:
            return "The Xbox HDD does not have enough free FATX clusters."
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(uint16LE(at: offset)) | (UInt32(uint16LE(at: offset + 2)) << 16)
    }

    func uint32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) |
            (UInt32(self[offset + 1]) << 16) |
            (UInt32(self[offset + 2]) << 8) |
            UInt32(self[offset + 3])
    }

    func uint64LE(at offset: Int) -> UInt64 {
        UInt64(uint32LE(at: offset)) | (UInt64(uint32LE(at: offset + 4)) << 32)
    }

    func uint64BE(at offset: Int) -> UInt64 {
        (UInt64(uint32BE(at: offset)) << 32) | UInt64(uint32BE(at: offset + 4))
    }

    mutating func writeUInt16LE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    mutating func writeUInt16BE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        writeUInt16LE(UInt16(value & 0xFFFF), at: offset)
        writeUInt16LE(UInt16((value >> 16) & 0xFFFF), at: offset + 2)
    }

    mutating func writeUInt64BE(_ value: UInt64, at offset: Int) {
        self[offset] = UInt8((value >> 56) & 0xFF)
        self[offset + 1] = UInt8((value >> 48) & 0xFF)
        self[offset + 2] = UInt8((value >> 40) & 0xFF)
        self[offset + 3] = UInt8((value >> 32) & 0xFF)
        self[offset + 4] = UInt8((value >> 24) & 0xFF)
        self[offset + 5] = UInt8((value >> 16) & 0xFF)
        self[offset + 6] = UInt8((value >> 8) & 0xFF)
        self[offset + 7] = UInt8(value & 0xFF)
    }
}
