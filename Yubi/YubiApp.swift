import Foundation
import os
import SwiftUI
import UIKit

private let appLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "App"
)

@main
struct YubiApp: App {
    init() {
        AppShortcutMetadataDiagnostics.logBundleState()
        ResumeCoverController.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Replaces the live UI before iOS snapshots so app switcher / Action Button
/// resume shows a blank Yubi screen instead of the previous tab.
@MainActor
final class ResumeCoverController {
    static let shared = ResumeCoverController()

    private var coverWindow: UIWindow?
    private var resignObserver: NSObjectProtocol?

    func start() {
        guard resignObserver == nil else {
            return
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.show()
            }
        }
    }

    func show() {
        guard coverWindow == nil else {
            return
        }

        guard let scene = Self.windowScene() else {
            return
        }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .systemBackground

        let rootViewController = UIViewController()
        rootViewController.view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Yubi"
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        rootViewController.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: rootViewController.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: rootViewController.view.centerYAnchor),
        ])

        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        coverWindow = window
    }

    func hide() {
        guard let window = coverWindow else {
            return
        }

        if window.isKeyWindow {
            sceneWindows(for: window)
                .first { $0 !== window && !$0.isHidden }?
                .makeKey()
        }

        window.isHidden = true
        window.rootViewController = nil
        coverWindow = nil
    }

    private static func windowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        } ?? scenes.first
    }

    private func sceneWindows(for window: UIWindow) -> [UIWindow] {
        window.windowScene?.windows ?? []
    }
}

private enum AppShortcutMetadataDiagnostics {
    static func logBundleState() {
        appLogger.info("App bundle identifier: \(Bundle.main.bundleIdentifier ?? "nil", privacy: .public)")

        guard let metadataURL = Bundle.main.url(
            forResource: "extract",
            withExtension: "actionsdata",
            subdirectory: "Metadata.appintents"
        ) else {
            appLogger.error("App Intents metadata file is missing from the installed app bundle")
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let providerName = json?["autoShortcutProviderMangledName"] as? String
            let actionCount = (json?["actions"] as? [String: Any])?.count ?? 0
            let shortcutCount = (json?["autoShortcuts"] as? [[String: Any]])?.count ?? 0

            appLogger.info("App Intents metadata loaded; providerPresent=\(providerName != nil, privacy: .public), actions=\(actionCount, privacy: .public), appShortcuts=\(shortcutCount, privacy: .public)")

            if let providerName {
                appLogger.info("App Shortcuts provider mangled name: \(providerName, privacy: .public)")
            }
        } catch {
            appLogger.error("Failed to read App Intents metadata: \(String(describing: error), privacy: .public)")
        }
    }
}
