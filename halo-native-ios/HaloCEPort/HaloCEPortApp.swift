import SwiftUI
import UniformTypeIdentifiers

@main
struct HaloCEPortApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var importing = false
    @State private var status = "Choose an original Halo CE Xbox .map file."

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Halo CE Native")
                    .font(.largeTitle.bold())

                Text(status)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Button("Choose .map") {
                    importing = true
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
                        status = "Selected: \(url.lastPathComponent)\nSize: \(size) bytes\nNative Halo port bootstrap is running."
                    } catch {
                        status = "Map read failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    status = "File picker failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
