import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var gameFolder: GameFolderStore
    @State private var showingXBEImporter = false
    @State private var importerError: String?

    private static let xbeType = UTType(filenameExtension: "xbe") ?? .data

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: gameFolder.status.isValid ? "checkmark.seal.fill" : "externaldrive.fill")
                    .font(.system(size: 58))
                    .accessibilityHidden(true)

                Text("Halo CE").font(.largeTitle.bold())
                Text(gameFolder.status.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let importerError {
                    Text(importerError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let folder = gameFolder.folderURL {
                    Text(folder.lastPathComponent)
                        .font(.footnote.monospaced())
                        .lineLimit(2)
                }

                Button {
                    importerError = nil
                    showingXBEImporter = true
                } label: {
                    Label("Choose default.xbe", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Open Halo_extracted, tap default.xbe, then tap Open. The app will automatically use the folder containing that file and validate the maps directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if gameFolder.folderURL != nil {
                    Button("Recheck Game Files") { gameFolder.revalidate() }
                        .buttonStyle(.bordered)
                    Button("Forget Game Files", role: .destructive) { gameFolder.forgetFolder() }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Halo CE Port")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showingXBEImporter,
            allowedContentTypes: [Self.xbeType, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    importerError = "Files did not return a selected file."
                    return
                }
                guard url.lastPathComponent.lowercased() == "default.xbe" else {
                    importerError = "Select the file named default.xbe."
                    return
                }
                gameFolder.select(defaultXBE: url)
            case .failure(let error):
                importerError = "Could not import default.xbe: \(error.localizedDescription)"
            }
        }
    }
}
