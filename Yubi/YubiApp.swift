import Foundation
import os
import SwiftUI

private let appLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "App"
)

@main
struct YubiApp: App {
    init() {
        AppShortcutMetadataDiagnostics.logBundleState()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
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
