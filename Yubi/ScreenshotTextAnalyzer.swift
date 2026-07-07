import CoreGraphics
import Foundation
import os

struct ScreenshotImageAnalysis {
    let result: String
    let transcript: String
}

private let screenshotAnalyzerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "ScreenshotAnalyzer"
)

enum ScreenshotTextAnalyzer {
    static func analyzeImage(_ cgImage: CGImage, status: AIBackendClient.StatusHandler? = nil) async throws -> ScreenshotImageAnalysis {
        let targetLanguage = defaultOutputLanguagePromptName()
        let backend = AIBackendSettings.selectedBackend
        screenshotAnalyzerLogger.info("Starting image analysis; backend=\(backend.displayName, privacy: .public), targetLanguage=\(targetLanguage, privacy: .public)")
        let output = try await AIBackendClient.analyzeScreenshotImage(cgImage, targetLanguage: targetLanguage, status: status)
        screenshotAnalyzerLogger.info("Image analysis completed; outputCharacters=\(output.count, privacy: .public)")
        return ScreenshotImageAnalysis(
            result: output,
            transcript: section(named: "Transcript", in: output) ?? ""
        )
    }

    static func analyze(_ text: String, status: AIBackendClient.StatusHandler? = nil) async throws -> String {
        let targetLanguage = defaultOutputLanguagePromptName()
        let backend = AIBackendSettings.selectedBackend
        screenshotAnalyzerLogger.info("Starting text analysis; backend=\(backend.displayName, privacy: .public), targetLanguage=\(targetLanguage, privacy: .public)")

        do {
            let output = try await AIBackendClient.analyzeScreenshotText(text, targetLanguage: targetLanguage, status: status)
            screenshotAnalyzerLogger.info("Text analysis completed; outputCharacters=\(output.count, privacy: .public)")
            return output
        } catch {
            guard backend == .apple else {
                throw error
            }

            screenshotAnalyzerLogger.warning("Apple analysis unavailable; using fallback analysis")
            return fallbackAnalysis(for: text)
        }
    }

    private static func fallbackAnalysis(for text: String) -> String {
        "Detected text:\n\(text)"
    }
    private static func section(named name: String, in output: String) -> String? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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

    private static func lineStartsSection(_ line: String, named name: String) -> Bool {
        let pattern = #"^\s*\#(name)(\s*\([^)]+\))?:\s*"#
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func defaultOutputLanguagePromptName() -> String {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()

        if identifier.hasPrefix("ja") {
            return "Japanese"
        }

        if identifier.hasPrefix("ko") {
            return "Korean"
        }

        if identifier.hasPrefix("zh") {
            if identifier.contains("hant")
                || identifier.contains("-tw")
                || identifier.contains("_tw")
                || identifier.contains("-hk")
                || identifier.contains("_hk")
                || identifier.contains("-mo")
                || identifier.contains("_mo") {
                return "Traditional Chinese"
            }

            return "Simplified Chinese"
        }

        return "English"
    }
}

