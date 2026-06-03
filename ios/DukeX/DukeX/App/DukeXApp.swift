import Darwin
import Foundation
import GameController
import SwiftUI
import UIKit

@main
struct DukeXApp: App {
    @UIApplicationDelegateAdaptor(DukeXApplicationDelegate.self) private var appDelegate
    @StateObject private var store = EmulatorFileStore()

    init() {
        MetalDiagnostics.configurePerformanceHUD()
        _ = GameControllerBootstrap.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.prepareAndRefresh()
                }
        }
    }
}

final class DukeXApplicationDelegate: NSObject, UIApplicationDelegate {
}

final class DukeXExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    private var rootController: NativeMetalExternalDisplayViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let rootController = NativeMetalExternalDisplayViewController()
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = rootController
        self.rootController = rootController
        self.window = window
        window.makeKeyAndVisible()
        NativeMetalPresenterHost.connectExternalDisplayScene(
            rootController: rootController,
            window: window,
            reason: "scene-connect"
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let rootController,
              let window else {
            return
        }

        NativeMetalPresenterHost.disconnectExternalDisplayScene(
            rootController: rootController,
            window: window,
            reason: "scene-disconnect"
        )
        window.isHidden = true
        window.rootViewController = nil
        self.rootController = nil
        self.window = nil
    }

    func sceneDidActivate(_ scene: UIScene) {
        guard let rootController,
              let window else {
            return
        }

        NativeMetalPresenterHost.connectExternalDisplayScene(
            rootController: rootController,
            window: window,
            reason: "scene-activate"
        )
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        guard let rootController,
              let window else {
            return
        }

        NativeMetalPresenterHost.connectExternalDisplayScene(
            rootController: rootController,
            window: window,
            reason: "scene-update"
        )
    }
}
