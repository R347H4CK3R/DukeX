import Foundation

enum ImportMode: String, Identifiable {
    case folder
    case defaultXBE

    var id: String { rawValue }
}
