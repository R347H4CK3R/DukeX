import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var gameFolder: GameFolderStore
    @State private var showingFolderImporter = false
    @State private var showingXBEImporter = false
    @State private var importerError: String?

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
                    Text(importerError).font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                if let folder = gameFolder.folderURL {
                    Text(folder.lastPathComponent).font(.footnote.monospaced()).lineLimit(2)
                }

                Button { importerError = nil; showingFolderImporter = true } label: {
                    Label(gameFolder.folderURL == nil ? "Choose Halo_extracted Folder" : "Choose Different Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)

                Button { importerError = nil; showingXBEImporter = true } label: {
                    Label("Select default.xbe Instead", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)

                Text("Native iOS Files import. If folder selection is unavailable, select default.xbe inside Halo_extracted.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)

                if gameFolder.folderURL != nil {
                    Button("Recheck Game Files") { gameFolder.revalidate() }.buttonStyle(.bordered)
                    Button("Forget Folder", role: .destructive) { gameFolder.forgetFolder() }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Halo CE Port")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(isPresented: $showingFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { importerError = "No folder was returned by Files."; return }
                gameFolder.select(folder: url)
            case .failure(let error): importerError = "Folder picker failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showingXBEImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { importerError = "No file was returned by Files."; return }
                gameFolder.select(defaultXBE: url)
            case .failure(let error): importerError = "File picker failed: \(error.localizedDescription)"
            }
        }
    }
}
