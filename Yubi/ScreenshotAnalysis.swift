import Foundation
import os
import UserNotifications

private let screenshotNotificationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "ScreenshotNotifications"
)

struct ScreenshotAnalysis: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let detectedText: String
    let result: String
    let imageFilename: String?
    let isComplete: Bool

    init(id: UUID = UUID(), date: Date, detectedText: String, result: String, imageFilename: String? = nil, isComplete: Bool = true) {
        self.id = id
        self.date = date
        self.detectedText = detectedText
        self.result = result
        self.imageFilename = imageFilename
        self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.detectedText = try container.decode(String.self, forKey: .detectedText)
        self.result = try container.decode(String.self, forKey: .result)
        self.imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        self.isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
    }

    var summary: String {
        section(named: "Summary") ?? result
    }

    var translation: String {
        section(named: "Translation") ?? result
    }

    var transcript: String {
        detectedText.isEmpty ? (section(named: "Transcript") ?? "") : detectedText
    }

    var translationPreview: String {
        let previewText = result.isEmpty ? detectedText : translation

        return previewText
            .split(whereSeparator: \.isNewline)
            .prefix(4)
            .joined(separator: "\n")
    }

    private func section(named name: String) -> String? {
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let startIndex = lines.firstIndex(where: { line in
            lineStartsSection(line, named: name)
        }) else {
            return nil
        }

        let firstLine = lines[startIndex]
            .replacingOccurrences(
                of: #"^\s*\#(name)(\s*\([^)]+\))?:\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        let followingLines = lines[(startIndex + 1)...].prefix { line in
            !lineStartsSection(line, named: "Summary")
                && !lineStartsSection(line, named: "Transcript")
                && !lineStartsSection(line, named: "Translation")
        }

        return ([firstLine] + followingLines)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lineStartsSection(_ line: String, named name: String) -> Bool {
        let pattern = #"^\s*\#(name)(\s*\([^)]+\))?:\s*"#
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum ScreenshotAnalysisStore {
    private static let key = "YubiLatestScreenshotAnalysis"
    private static let historyKey = "YubiScreenshotAnalysisHistory"
    private static let historyLimit = 20
    private static let lock = NSRecursiveLock()

    static func load() -> ScreenshotAnalysis? {
        loadHistory().first ?? loadLegacyLatest()
    }

    static func loadHistory() -> [ScreenshotAnalysis] {
        withLock {
            loadHistoryUnlocked()
        }
    }

    static func save(_ analysis: ScreenshotAnalysis) {
        withLock {
            var history = loadHistoryUnlocked()
            history.removeAll { $0.id == analysis.id }
            history.insert(analysis, at: 0)
            let removedAnalyses = Array(history.dropFirst(historyLimit))
            history = Array(history.prefix(historyLimit))

            if let data = try? JSONEncoder().encode(history) {
                UserDefaults.standard.set(data, forKey: historyKey)
            }

            for analysis in removedAnalyses {
                deleteImage(filename: analysis.imageFilename)
            }

            guard let data = try? JSONEncoder().encode(analysis) else {
                return
            }

            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadHistoryUnlocked() -> [ScreenshotAnalysis] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let analyses = try? JSONDecoder().decode([ScreenshotAnalysis].self, from: data)
        else {
            return loadLegacyLatest().map { [$0] } ?? []
        }

        return analyses
            .sorted { $0.date > $1.date }
            .prefix(historyLimit)
            .map { $0 }
    }

    static func saveImageData(_ data: Data, for id: UUID) -> String? {
        let filename = "\(id.uuidString).image"
        let url = imageDirectoryURL().appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: imageDirectoryURL(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            return filename
        } catch {
            return nil
        }
    }

    static func imageData(for analysis: ScreenshotAnalysis) -> Data? {
        guard let imageFilename = analysis.imageFilename else {
            return nil
        }

        return try? Data(contentsOf: imageDirectoryURL().appendingPathComponent(imageFilename))
    }

    private static func loadLegacyLatest() -> ScreenshotAnalysis? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(ScreenshotAnalysis.self, from: data)
    }

    private static func imageDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("ScreenshotImages", isDirectory: true)
    }

    private static func deleteImage(filename: String?) {
        guard let filename else {
            return
        }

        try? FileManager.default.removeItem(at: imageDirectoryURL().appendingPathComponent(filename))
    }

    private static func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }
}

struct ScreenshotAnalysisStatus: Codable, Equatable {
    enum Phase: String, Codable {
        case idle
        case running
        case completed
        case failed
    }

    let phase: Phase
    let analysisID: UUID?
    let startedAt: Date?
    let updatedAt: Date
    let message: String?

    init(phase: Phase, analysisID: UUID?, startedAt: Date?, updatedAt: Date, message: String?) {
        self.phase = phase
        self.analysisID = analysisID
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.phase = try container.decode(Phase.self, forKey: .phase)
        self.analysisID = try container.decodeIfPresent(UUID.self, forKey: .analysisID)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    static var idle: ScreenshotAnalysisStatus {
        ScreenshotAnalysisStatus(phase: .idle, analysisID: nil, startedAt: nil, updatedAt: Date(), message: nil)
    }
}

enum ScreenshotAnalysisStatusStore {
    private static let key = "YubiScreenshotAnalysisStatus"
    private static let runningTimeout: TimeInterval = 10 * 60

    static func load() -> ScreenshotAnalysisStatus {
        guard let data = UserDefaults.standard.data(forKey: key),
              let status = try? JSONDecoder().decode(ScreenshotAnalysisStatus.self, from: data)
        else {
            return .idle
        }

        if status.phase == .running,
           Date().timeIntervalSince(status.updatedAt) >= runningTimeout {
            let failedStatus = ScreenshotAnalysisStatus(
                phase: .failed,
                analysisID: status.analysisID,
                startedAt: nil,
                updatedAt: Date(),
                message: "The previous analysis did not finish. Try again."
            )
            save(failedStatus)
            return failedStatus
        }

        return status
    }

    static func markRunning(_ message: String, analysisID: UUID? = nil) {
        save(ScreenshotAnalysisStatus(
            phase: .running,
            analysisID: analysisID,
            startedAt: Date(),
            updatedAt: Date(),
            message: message
        ))
    }

    static func markCompleted(_ message: String, analysisID: UUID? = nil) {
        save(ScreenshotAnalysisStatus(
            phase: .completed,
            analysisID: analysisID,
            startedAt: nil,
            updatedAt: Date(),
            message: message
        ))
    }

    static func markFailed(_ message: String, analysisID: UUID? = nil) {
        save(ScreenshotAnalysisStatus(
            phase: .failed,
            analysisID: analysisID,
            startedAt: nil,
            updatedAt: Date(),
            message: message
        ))
    }

    private static func save(_ status: ScreenshotAnalysisStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}

enum ScreenshotAnalysisNotificationService {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            screenshotNotificationLogger.error("Could not request notification authorization: \(String(describing: error), privacy: .public)")
        }
    }

    static func notifyCompleted(analysisID: UUID) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Yubi"
        content.body = completionMessage
        content.sound = .default
        content.userInfo = ["analysisID": analysisID.uuidString]

        let request = UNNotificationRequest(
            identifier: "screenshot-analysis-\(analysisID.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            screenshotNotificationLogger.error("Could not schedule screenshot completion notification: \(String(describing: error), privacy: .public)")
        }
    }

    private static var completionMessage: String {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()

        if identifier.hasPrefix("ja") {
            return "スクリーンショットの翻訳が完了しました。"
        }

        if identifier.hasPrefix("ko") {
            return "스크린샷 번역이 완료되었습니다."
        }

        if identifier.hasPrefix("zh-hant")
            || identifier.contains("-tw")
            || identifier.contains("_tw")
            || identifier.contains("-hk")
            || identifier.contains("_hk")
            || identifier.contains("-mo")
            || identifier.contains("_mo") {
            return "螢幕截圖翻譯已完成。"
        }

        if identifier.hasPrefix("zh") {
            return "截图翻译已完成。"
        }

        return "Your screenshot translation is ready."
    }
}
