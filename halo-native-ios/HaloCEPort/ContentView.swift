import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameFolder: GameFolderStore
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: gameFolder.status.isValid ? "checkmark.seal.fill" : "externaldrive.fill")
                    .font(.system(size: 58))
                    .accessibilityHidden(true)

                Text("Halo CE")
                    .font(.largeTitle.bold())

                Text(gameFolder.status.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let folder = gameFolder.folderURL {
                    Text(folder.lastPathComponent)
                        .font(.footnote.monospaced())
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    showingPicker = true
                } label: {
                    Label(gameFolder.folderURL == nil ? "Choose Halo_extracted" : "Choose Different Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if gameFolder.folderURL != nil {
                    Button("Recheck Game Files") {
                        gameFolder.revalidate()
                    }
                    .buttonStyle(.bordered)

                    Button("Forget Folder", role: .destructive) {
                        gameFolder.forgetFolder()
                    }
                }

                Spacer()

                Text("This launcher keeps the game data outside the IPA and stores permission to the folder you choose in Files. It validates default.xbe and the maps directory without copying your game data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Halo CE Port")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPicker) {
                FolderPicker(
                    onPick: { url in
                        showingPicker = false
                        gameFolder.select(folder: url)
                    },
                    onCancel: {
                        showingPicker = false
                    }
                )
            }
        }
    }
}
