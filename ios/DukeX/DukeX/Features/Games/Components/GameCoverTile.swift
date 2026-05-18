import SwiftUI
import UIKit

struct GameCoverTile: View {
    let game: LibraryFile
    let canLaunch: Bool
    let liveStatus: GameLiveStatus?
    let isFavorite: Bool
    let launch: () -> Void
    let addCover: () -> Void
    let importConfig: () -> Void
    let clearShaderCache: () -> Void
    let toggleFavorite: () -> Void
    let requestRemoveGame: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: launch) {
                coverWithLiveStatus
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)

            Button(action: launch) {
                Text(game.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
            }
            .buttonStyle(.plain)
            .disabled(!canLaunch)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .opacity(canLaunch ? 1 : 0.55)
        .contextMenu {
            Button(action: addCover) {
                Label("Add Cover", systemImage: "photo")
            }

            Button(action: importConfig) {
                Label(game.customConfigURL == nil ? "Import Config" : "Replace Config",
                      systemImage: "gearshape")
            }

            Button(action: clearShaderCache) {
                Label("Clear Shader Cache", systemImage: "xmark.bin")
            }

            Button(action: toggleFavorite) {
                Label(
                    isFavorite ? "Remove Favorite" : "Add to Favorites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }

            Button(role: .destructive, action: requestRemoveGame) {
                Label("Remove Game", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var coverWithLiveStatus: some View {
        ZStack(alignment: .topTrailing) {
            cover

            if let liveStatus {
                LiveStatusBadge(status: liveStatus)
                    .padding(7)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(0.70, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverURL = game.coverURL,
           let image = UIImage(contentsOfFile: coverURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.16))

                VStack(spacing: 10) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 42, weight: .regular))
                    Text(game.fallbackDisplayName)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
