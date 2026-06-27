import Foundation

enum XISOGameTitleReader {
    private static let sectorSize: UInt64 = 2_048
    private static let xboxMediaMagic = Data("MICROSOFT*XBOX*MEDIA".utf8)

    struct Metadata {
        let titleName: String?
        let titleID: String?
    }

    struct DirectoryEntry {
        let name: String
        let sector: UInt32
        let size: UInt32
    }

    struct VolumeDescriptor {
        let baseSector: UInt64
        let rootDirectorySector: UInt32
        let rootDirectorySize: UInt32
    }

    static func metadata(in url: URL) -> Metadata? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            guard let descriptor = try findVolumeDescriptor(in: handle),
                  let defaultXBE = try findDefaultXBE(in: handle, descriptor: descriptor) else {
                return nil
            }

            let xbeOffset = (descriptor.baseSector + UInt64(defaultXBE.sector)) * sectorSize
            let xbeHeaders = try readXBEHeaders(
                from: handle,
                offset: xbeOffset,
                fileSize: Int(defaultXBE.size)
            )
            return Metadata(
                titleName: titleName(fromXBEHeaders: xbeHeaders),
                titleID: titleID(fromXBEHeaders: xbeHeaders)
            )
        } catch {
            return nil
        }
    }

    static func titleName(in url: URL) -> String? {
        metadata(in: url)?.titleName
    }

    private static func findVolumeDescriptor(in handle: FileHandle) throws -> VolumeDescriptor? {
        if let descriptor = try readVolumeDescriptor(in: handle, sector: 32) {
            return descriptor
        }

        for sector in UInt64(0)..<512 where sector != 32 {
            if let descriptor = try readVolumeDescriptor(in: handle, sector: sector) {
                return descriptor
            }
        }

        return nil
    }

    private static func readVolumeDescriptor(in handle: FileHandle, sector: UInt64) throws -> VolumeDescriptor? {
        let data = try readData(from: handle, offset: sector * sectorSize, length: Int(sectorSize))
        guard data.count == Int(sectorSize) else {
            return nil
        }

        guard hasXboxMediaMagic(in: data),
              let rootSector = littleEndianUInt32(in: data, at: 20),
              let rootSize = littleEndianUInt32(in: data, at: 24),
              rootSector > 0,
              rootSize > 0,
              rootSize <= 16 * 1_024 * 1_024 else {
            return nil
        }

        return VolumeDescriptor(
            baseSector: sector >= 32 ? sector - 32 : 0,
            rootDirectorySector: rootSector,
            rootDirectorySize: rootSize
        )
    }

    private static func hasXboxMediaMagic(in data: Data) -> Bool {
        if data.starts(with: xboxMediaMagic) {
            return true
        }
        guard let trailerMagic = data[safeRange: 0x7EC..<(0x7EC + xboxMediaMagic.count)] else {
            return false
        }
        return trailerMagic == xboxMediaMagic
    }

    private static func findDefaultXBE(
        in handle: FileHandle,
        descriptor: VolumeDescriptor
    ) throws -> DirectoryEntry? {
        let rootOffset = (descriptor.baseSector + UInt64(descriptor.rootDirectorySector)) * sectorSize
        let rootLength = min(Int(descriptor.rootDirectorySize), 4 * 1_024 * 1_024)
        let data = try readData(from: handle, offset: rootOffset, length: rootLength)
        let entries = parseDirectoryEntries(data)

        return entries.first { entry in
            let name = entry.name.lowercased()
            return name == "default.xbe" || name == "default.xeb"
        }
    }

    private static func parseDirectoryEntries(_ data: Data) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        var offset = 0

        while offset + 14 <= data.count {
            guard let sector = littleEndianUInt32(in: data, at: offset + 4),
                  let size = littleEndianUInt32(in: data, at: offset + 8) else {
                break
            }

            let nameLength = Int(data[offset + 13])
            guard nameLength > 0, offset + 14 + nameLength <= data.count else {
                break
            }

            let nameData = data.subdata(in: (offset + 14)..<(offset + 14 + nameLength))
            if let name = String(data: nameData, encoding: .utf8) ??
                String(data: nameData, encoding: .ascii),
               !name.isEmpty {
                entries.append(DirectoryEntry(name: name, sector: sector, size: size))
            }

            let entryLength = (14 + nameLength + 3) & ~3
            guard entryLength > 0 else {
                break
            }
            offset += entryLength
        }

        return entries
    }

    private static func readXBEHeaders(
        from handle: FileHandle,
        offset: UInt64,
        fileSize: Int
    ) throws -> Data {
        let initialLength = min(max(fileSize, 0), 4_096)
        let initial = try readData(from: handle, offset: offset, length: initialLength)
        guard let headerSize = littleEndianUInt32(in: initial, at: 0x108),
              headerSize > 0,
              headerSize <= 512 * 1_024 else {
            return initial
        }

        let fullLength = min(Int(headerSize), max(fileSize, initial.count))
        guard fullLength > initial.count else {
            return initial
        }
        return try readData(from: handle, offset: offset, length: fullLength)
    }

    private static func titleName(fromXBEHeaders headers: Data) -> String? {
        guard littleEndianUInt32(in: headers, at: 0) == 0x4845_4258,
              let baseAddress = littleEndianUInt32(in: headers, at: 0x104),
              let certificateAddress = littleEndianUInt32(in: headers, at: 0x118) else {
            return nil
        }

        let candidateOffsets = [
            certificateOffset(certificateAddress, relativeTo: baseAddress),
            certificateOffset(certificateAddress, relativeTo: 0x0001_0000)
        ].compactMap { $0 }

        for certificateOffset in candidateOffsets where certificateOffset + 0x0C + 80 <= headers.count {
            let titleOffset = certificateOffset + 0x0C
            var units: [UInt16] = []

            for byteOffset in stride(from: titleOffset, to: titleOffset + 80, by: 2) {
                guard let value = littleEndianUInt16(in: headers, at: byteOffset),
                      value != 0 else {
                    break
                }
                units.append(value)
            }

            let title = String(decoding: units, as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }

        return nil
    }

    private static func titleID(fromXBEHeaders headers: Data) -> String? {
        guard littleEndianUInt32(in: headers, at: 0) == 0x4845_4258,
              let baseAddress = littleEndianUInt32(in: headers, at: 0x104),
              let certificateAddress = littleEndianUInt32(in: headers, at: 0x118) else {
            return nil
        }

        let candidateOffsets = [
            certificateOffset(certificateAddress, relativeTo: baseAddress),
            certificateOffset(certificateAddress, relativeTo: 0x0001_0000)
        ].compactMap { $0 }

        for certificateOffset in candidateOffsets where certificateOffset + 0x0C <= headers.count {
            guard let titleID = littleEndianUInt32(in: headers, at: certificateOffset + 0x08),
                  titleID != 0 else {
                continue
            }
            return String(format: "%08X", titleID)
        }

        return nil
    }

    private static func certificateOffset(_ address: UInt32, relativeTo base: UInt32) -> Int? {
        guard address >= base else {
            return nil
        }
        return Int(address - base)
    }

    private static func readData(from handle: FileHandle, offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else {
            return Data()
        }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length) ?? Data()
    }

    private static func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else {
            return nil
        }

        return UInt16(data[offset]) |
            UInt16(data[offset + 1]) << 8
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else {
            return nil
        }

        return UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}

private extension Data {
    subscript(safeRange range: Range<Int>) -> Data? {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            return nil
        }
        return subdata(in: range)
    }
}

extension FileManager {
    func copyItemIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        guard fileExists(atPath: sourceURL.path),
              !fileExists(atPath: destinationURL.path) else {
            return
        }
        try copyItem(at: sourceURL, to: destinationURL)
    }
}
