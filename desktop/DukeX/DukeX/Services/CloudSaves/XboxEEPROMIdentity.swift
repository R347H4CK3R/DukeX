import Foundation

struct XboxEEPROMIdentity {
    let eepromData: Data
    let serial: String
    let hddKeyHex: String

    init(fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        guard data.count == 256 else {
            throw XboxEEPROMIdentityError.invalidSize(data.count)
        }

        let bytes = [UInt8](data)
        let decryptedSecurity = try Self.decryptSecuritySection(bytes)
        let hddKey = Array(decryptedSecurity[8..<24])

        eepromData = data
        serial = Self.serial(from: bytes)
        hddKeyHex = hddKey.map { String(format: "%02X", $0) }.joined()
    }

    private static func serial(from bytes: [UInt8]) -> String {
        let raw = bytes[0x34..<(0x34 + 12)]
        let printable = raw.prefix { byte in
            byte >= 0x20 && byte <= 0x7E
        }
        return String(bytes: printable, encoding: .ascii) ?? ""
    }

    private static func decryptSecuritySection(_ bytes: [UInt8]) throws -> [UInt8] {
        let originalHash = Array(bytes[0..<20])
        for version in XboxEEPROMVersion.allCases {
            var rc4 = XboxRC4(seed: XboxEEPROMHMACSHA1.compute(version: version, data: originalHash))
            var decrypted = Array(bytes[0x14..<0x30])
            rc4.crypt(&decrypted)

            if XboxEEPROMHMACSHA1.compute(version: version, data: decrypted) == originalHash {
                return decrypted
            }
        }

        throw XboxEEPROMIdentityError.unsupportedVersion
    }
}

enum XboxEEPROMIdentityError: LocalizedError {
    case missing
    case invalidSize(Int)
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .missing:
            return "Import a 256-byte Xbox EEPROM.bin before using cloud save sync."
        case .invalidSize(let size):
            return "The imported EEPROM must be 256 bytes. DukeX found \(size) bytes."
        case .unsupportedVersion:
            return "DukeX could not decrypt the imported Xbox EEPROM security section."
        }
    }
}

private enum XboxEEPROMVersion: CaseIterable {
    case debug
    case retailFirst
    case retailMiddle
    case retailLast

    var firstInitialHash: (UInt32, UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .debug:
            return (0x85F9E51A, 0xE04613D2, 0x6D86A50C, 0x77C32E3C, 0x4BD717A4)
        case .retailFirst:
            return (0x72127625, 0x336472B9, 0xBE609BEA, 0xF55E226B, 0x99958DAC)
        case .retailMiddle:
            return (0x39B06E79, 0xC9BD25E8, 0xDBC6B498, 0x40B4389D, 0x86BBD7ED)
        case .retailLast:
            return (0x8058763A, 0xF97D4E0E, 0x865A9762, 0x8A3D920D, 0x08995B2C)
        }
    }

    var secondInitialHash: (UInt32, UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .debug:
            return (0x5D7A9C6B, 0xE1922BEB, 0xB82CCDBC, 0x3137AB34, 0x486B52B3)
        case .retailFirst:
            return (0x76441D41, 0x4DE82659, 0x2E8EF85E, 0xB256FACA, 0xC4FE2DE8)
        case .retailMiddle:
            return (0x9B49BED3, 0x84B430FC, 0x6B8749CD, 0xEBFE5FE5, 0xD96E7393)
        case .retailLast:
            return (0x01075307, 0xA2F1E037, 0x1186EEEA, 0x88DA9992, 0x168A5609)
        }
    }
}

private struct XboxEEPROMHMACSHA1 {
    static func compute(version: XboxEEPROMVersion, data: [UInt8]) -> [UInt8] {
        var first = XboxSHA1(initialHash: version.firstInitialHash, initialBitLength: 512)
        first.input(data)

        var second = XboxSHA1(initialHash: version.secondInitialHash, initialBitLength: 512)
        second.input(first.result())
        return second.result()
    }
}

private struct XboxSHA1 {
    private var hash: [UInt32]
    private var messageBlock = Array(repeating: UInt8(0), count: 64)
    private var bitLength: UInt32
    private var messageBlockIndex = 0
    private var computedResult: [UInt8]?

    init(initialHash: (UInt32, UInt32, UInt32, UInt32, UInt32), initialBitLength: UInt32) {
        hash = [
            initialHash.0,
            initialHash.1,
            initialHash.2,
            initialHash.3,
            initialHash.4
        ]
        bitLength = initialBitLength
    }

    mutating func input(_ data: [UInt8]) {
        precondition(computedResult == nil)

        for byte in data {
            messageBlock[messageBlockIndex] = byte
            messageBlockIndex += 1
            bitLength &+= 8

            if messageBlockIndex == 64 {
                processMessageBlock()
            }
        }
    }

    mutating func result() -> [UInt8] {
        if let computedResult {
            return computedResult
        }

        pad()
        bitLength = 0

        var output: [UInt8] = []
        output.reserveCapacity(20)
        for word in hash {
            output.append(UInt8((word >> 24) & 0xFF))
            output.append(UInt8((word >> 16) & 0xFF))
            output.append(UInt8((word >> 8) & 0xFF))
            output.append(UInt8(word & 0xFF))
        }

        computedResult = output
        return output
    }

    private mutating func pad() {
        if messageBlockIndex > 55 {
            messageBlock[messageBlockIndex] = 0x80
            messageBlockIndex += 1
            while messageBlockIndex < 64 {
                messageBlock[messageBlockIndex] = 0
                messageBlockIndex += 1
            }
            processMessageBlock()

            while messageBlockIndex < 56 {
                messageBlock[messageBlockIndex] = 0
                messageBlockIndex += 1
            }
        } else {
            messageBlock[messageBlockIndex] = 0x80
            messageBlockIndex += 1
            while messageBlockIndex < 56 {
                messageBlock[messageBlockIndex] = 0
                messageBlockIndex += 1
            }
        }

        messageBlock[56] = 0
        messageBlock[57] = 0
        messageBlock[58] = 0
        messageBlock[59] = 0
        messageBlock[60] = UInt8((bitLength >> 24) & 0xFF)
        messageBlock[61] = UInt8((bitLength >> 16) & 0xFF)
        messageBlock[62] = UInt8((bitLength >> 8) & 0xFF)
        messageBlock[63] = UInt8(bitLength & 0xFF)

        processMessageBlock()
    }

    private mutating func processMessageBlock() {
        let constants: [UInt32] = [0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xCA62C1D6]
        var words = Array(repeating: UInt32(0), count: 80)

        for index in 0..<16 {
            let base = index * 4
            words[index] = (UInt32(messageBlock[base]) << 24) |
                (UInt32(messageBlock[base + 1]) << 16) |
                (UInt32(messageBlock[base + 2]) << 8) |
                UInt32(messageBlock[base + 3])
        }

        for index in 16..<80 {
            words[index] = Self.rotateLeft(
                words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16],
                by: 1
            )
        }

        var a = hash[0]
        var b = hash[1]
        var c = hash[2]
        var d = hash[3]
        var e = hash[4]

        for index in 0..<80 {
            let round = index / 20
            let function: UInt32
            switch round {
            case 0:
                function = (b & c) | ((~b) & d)
            case 1, 3:
                function = b ^ c ^ d
            default:
                function = (b & c) | (b & d) | (c & d)
            }

            let temp = Self.rotateLeft(a, by: 5)
                &+ function
                &+ e
                &+ words[index]
                &+ constants[round]
            e = d
            d = c
            c = Self.rotateLeft(b, by: 30)
            b = a
            a = temp
        }

        hash[0] &+= a
        hash[1] &+= b
        hash[2] &+= c
        hash[3] &+= d
        hash[4] &+= e
        messageBlockIndex = 0
    }

    private static func rotateLeft(_ value: UInt32, by bits: Int) -> UInt32 {
        (value << bits) | (value >> (32 - bits))
    }
}

private struct XboxRC4 {
    private var state = Array(repeating: UInt8(0), count: 256)
    private var x = 0
    private var y = 0

    init(seed: [UInt8]) {
        for index in 0..<state.count {
            state[index] = UInt8(index)
        }

        var seedIndex = 0
        var swapIndex = 0
        for index in 0..<state.count {
            swapIndex = (Int(seed[seedIndex]) + Int(state[index]) + swapIndex) % state.count
            seedIndex = (seedIndex + 1) % seed.count
            state.swapAt(index, swapIndex)
        }
    }

    mutating func crypt(_ data: inout [UInt8]) {
        for index in data.indices {
            x = (x + 1) % state.count
            y = (Int(state[x]) + y) % state.count
            state.swapAt(x, y)
            data[index] ^= state[(Int(state[x]) + Int(state[y])) % state.count]
        }
    }
}
