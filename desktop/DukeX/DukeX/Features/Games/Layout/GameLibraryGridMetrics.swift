import SwiftUI

enum GameLibraryGridMetrics {
    static let compactControlHeight: CGFloat = 43

    static func spacing(for columnCount: Int) -> CGFloat {
        switch columnCount {
        case 8:
            return 8
        case 6...7:
            return 10
        case 4...5:
            return 12
        case 3:
            return 10
        default:
            return 12
        }
    }

    static func columns(for columnCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing(for: columnCount)),
            count: columnCount
        )
    }

    static func tileWidth(for columnCount: Int, availableWidth: CGFloat) -> CGFloat {
        let safeColumnCount = max(columnCount, 1)
        let totalSpacing = CGFloat(max(safeColumnCount - 1, 0)) * spacing(for: safeColumnCount)
        let rawWidth = (availableWidth - totalSpacing) / CGFloat(safeColumnCount)
        return max(1, floor(rawWidth))
    }

    static func columns(for columnCount: Int, availableWidth: CGFloat) -> [GridItem] {
        let safeColumnCount = max(columnCount, 1)
        let width = tileWidth(for: safeColumnCount, availableWidth: availableWidth)
        return Array(
            repeating: GridItem(.fixed(width), spacing: spacing(for: safeColumnCount), alignment: .top),
            count: safeColumnCount
        )
    }
}
