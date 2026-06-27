import SwiftUI

struct LiveStatusBadge: View {
    let status: GameLiveStatus

    var body: some View {
        HStack(spacing: 5) {
            Text("LIVE")
                .font(.system(size: 10.8, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.46),
                            Color(red: 1.0, green: 0.47, blue: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .fill(status.hasPlayersOnline ? Color.green : Color.secondary.opacity(0.55))
                .frame(width: 8.4, height: 8.4)
        }
        .padding(.horizontal, 8.5)
        .padding(.vertical, 5)
        .background(.black.opacity(0.78), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 2)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if status.hasPlayersOnline {
            return "Insignia Live, players online"
        }
        return "Insignia Live, no active players"
    }
}
