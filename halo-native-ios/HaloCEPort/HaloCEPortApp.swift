import SwiftUI

@main
struct HaloCEPortApp: App {
    @StateObject private var gameFolder = GameFolderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameFolder)
        }
    }
}
