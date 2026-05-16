import SwiftUI
import UIKit

struct ProfileHeaderRow: View {
    let gamertag: String
    let lastRefreshed: String
    let profileImage: UIImage?
    let changeProfileImage: () -> Void
    let clearProfileImage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            avatar
                .contextMenu {
                    Button(action: changeProfileImage) {
                        Label("Change Profile Picture", systemImage: "photo")
                    }

                    if profileImage != nil {
                        Button(role: .destructive, action: clearProfileImage) {
                            Label("Remove Profile Picture", systemImage: "trash")
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(gamertag)
                    .font(.headline)
                Text("Last refresh: \(lastRefreshed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 72)
    }

    @ViewBuilder
    private var avatar: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Text(initial)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)
        }
    }

    private var initial: String {
        String(gamertag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

struct ProfileInfoRow: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String

    init(title: String, value: String, detail: String? = nil, systemImage: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 44)
    }
}

struct ProfileEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }
}
