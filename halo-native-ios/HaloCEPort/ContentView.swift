import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameFolder: GameFolderStore
    @State private var importMode: ImportMode?

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
                    importMode = .folder
                } label: {
                    Label(gameFolder.folderURL == nil ? "Choose Halo_extracted Folder" : "Choose Different Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    importMode = .defaultXBE
                } label: {
                    Label("Select default.xbe Instead", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("If iOS will not let you select the folder itself, choose default.xbe inside Halo_extracted. The app will use its parent folder automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

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
            }
            .padding()
            .navigationTitle("Halo CE Port")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $importMode) { mode in
                FolderPicker(
                    mode: mode,
                    onPick: { url in
                        importMode = nil
                        switch mode {
                        case .folder:
                            gameFolder.select(folder: url)
                        case .defaultXBE:
                            gameFolder.select(defaultXBE: url)
                        }
                    },
                    onCancel: {
                        importMode = nil
                    }
                )
            }
        }
    }
}
