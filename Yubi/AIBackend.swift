import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os
#if canImport(UIKit)
import UIKit
#endif

private let aiBackendAppGroupIdentifier = "group.com.justin.yubi"
private let aiBackendLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "AIBackend"
)

enum AIBackend: String, CaseIterable, Identifiable {
    case apple
    case openAI
    case claudeFable

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .openAI:
            return "OpenAI"
        case .claudeFable:
            return "Claude Fable 5"
        }
    }

    var detail: String {
        switch self {
        case .apple:
            return "weaker, but private and free"
        case .openAI:
            return "balanced"
        case .claudeFable:
            return "strongest, most expensive"
        }
    }

    var isAvailable: Bool {
        self != .apple
    }
}

enum AIBackendSettings {
    private static let backendKey = "YubiAIBackend"
    private static let openAIAPIKeyKey = "YubiOpenAIAPIKey"
    private static let claudeAPIKeyKey = "YubiClaudeAPIKey"

    static var selectedBackend: AIBackend {
        get {
            guard let rawValue = userDefaults.string(forKey: backendKey),
                  let backend = AIBackend(rawValue: rawValue),
                  backend.isAvailable
            else {
                return .openAI
            }

            return backend
        }
        set {
            userDefaults.set((newValue.isAvailable ? newValue : .openAI).rawValue, forKey: backendKey)
        }
    }

    static var openAIAPIKey: String {
        get {
            userDefaults.string(forKey: openAIAPIKeyKey) ?? ""
        }
        set {
            userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: openAIAPIKeyKey)
        }
    }

    static var claudeAPIKey: String {
        get {
            userDefaults.string(forKey: claudeAPIKeyKey) ?? ""
        }
        set {
            userDefaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: claudeAPIKeyKey)
        }
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: aiBackendAppGroupIdentifier) ?? .standard
    }
}

enum AIBackendClient {
    private static let openAIModel = "gpt-5.5"
    private static let claudeModel = "claude-fable-5-thinking-high"
    typealias StatusHandler = @Sendable (String) -> Void

    static func analyzeScreenshotText(_ text: String, targetLanguage: String, status: StatusHandler? = nil) async throws -> String {
        let instructions = """
        You analyze OCR text extracted from an iPhone screenshot. Correct obvious OCR noise, summarize what is on screen, and translate the meaningful text into natural \(targetLanguage). Return only the requested sections.
        """
        let prompt = """
        OCR text:
        \(text)

        Return:
        Summary: one short sentence.
        Translation (Markdown, \(targetLanguage)): fluent translated text in Markdown. Preserve names, numbers, URLs, UI labels, and useful structure. Use Markdown lists, emphasis, or tables only when they make the translation clearer.
        """

        return try await respond(instructions: instructions, prompt: prompt, status: status)
    }

    static func analyzeScreenshotImage(_ cgImage: CGImage, targetLanguage: String, status: StatusHandler? = nil) async throws -> String {
        let instructions = """
        You analyze iPhone screenshots from image input. Read visible text directly from the image. Infer the source language from the image. Summarize what is on screen and translate the meaningful visible text into natural \(targetLanguage). Return only the requested sections.
        """
        let prompt = """
        Analyze this screenshot.

        Return exactly:
        Summary: one short sentence.
        Translation (Markdown, \(targetLanguage)): fluent translated text in Markdown. Preserve names, numbers, URLs, UI labels, and useful structure. Use Markdown lists, emphasis, or tables only when they make the translation clearer.
        """

        switch AIBackendSettings.selectedBackend {
        case .apple:
            status?("Apple is analyzing the image...")
            return try await appleImageResponse(instructions: instructions, prompt: prompt, cgImage: cgImage)
        case .openAI:
            status?("Preparing image for OpenAI...")
            let image = try uploadImage(from: cgImage)
            status?("OpenAI is analyzing the image...")
            return try await openAIResponse(instructions: instructions, prompt: prompt, image: image, status: status)
        case .claudeFable:
            status?("Preparing image for Claude Fable 5...")
            let image = try uploadImage(from: cgImage)
            status?("Claude Fable 5 is analyzing the image...")
            return try await claudeResponse(instructions: instructions, prompt: prompt, image: image, status: status)
        }
    }

    static func translate(_ text: String, targetLanguage: String, toneInstruction: String?, status: StatusHandler? = nil) async throws -> String {
        let toneSentence = toneInstruction.map { " Use \($0)." } ?? ""
        let instructions = """
        Detect the source language and translate user-selected text into natural \(targetLanguage).\(toneSentence) Return only the translation, with no explanation, labels, or quotation marks.
        """
        let prompt = """
        Detect the source language and translate this text to \(targetLanguage).\(toneSentence) Preserve names, numbers, URLs, and line breaks where reasonable. Return only the translation:

        \(text)
        """

        return try await respond(instructions: instructions, prompt: prompt, status: status)
    }

    private static func respond(instructions: String, prompt: String, status: StatusHandler? = nil) async throws -> String {
        switch AIBackendSettings.selectedBackend {
        case .apple:
            status?("Apple is analyzing the text...")
            return try await appleTextResponse(instructions: instructions, prompt: prompt)
        case .openAI:
            status?("OpenAI is analyzing the text...")
            return try await openAIResponse(instructions: instructions, prompt: prompt, image: nil, status: status)
        case .claudeFable:
            status?("Claude Fable 5 is analyzing the text...")
            return try await claudeResponse(instructions: instructions, prompt: prompt, image: nil, status: status)
        }
    }

    private static func appleTextResponse(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AIBackendError.modelUnavailable
            }

            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt)
            return try nonEmptyCleanedOutput(response.content)
        }
        #endif

        throw AIBackendError.modelUnavailable
    }

    private static func appleImageResponse(instructions: String, prompt: String, cgImage: CGImage) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AIBackendError.modelUnavailable
            }

            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond {
                prompt
                Attachment(cgImage)
            }
            return try nonEmptyCleanedOutput(response.content)
        }
        #endif

        throw AIBackendError.modelUnavailable
    }

    private static func openAIResponse(instructions: String, prompt: String, image: UploadImage?, status: StatusHandler?) async throws -> String {
        let apiKey = AIBackendSettings.openAIAPIKey
        guard !apiKey.isEmpty else {
            throw AIBackendError.missingAPIKey("OpenAI")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        if let image {
            content.append([
                "type": "input_image",
                "image_url": image.dataURL
            ])
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": openAIModel,
            "instructions": instructions,
            "reasoning": [
                "effort": "high"
            ],
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ])

        let data = try await responseData(for: request, provider: "OpenAI", status: status)
        return try nonEmptyCleanedOutput(extractOpenAIText(from: data))
    }

    private static func claudeResponse(instructions: String, prompt: String, image: UploadImage?, status: StatusHandler?) async throws -> String {
        let apiKey = AIBackendSettings.claudeAPIKey
        guard !apiKey.isEmpty else {
            throw AIBackendError.missingAPIKey("Claude")
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var content: [[String: Any]] = []
        if let image {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mediaType,
                    "data": image.base64Data
                ]
            ])
        }
        content.append(["type": "text", "text": prompt])

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": claudeModel,
            "max_tokens": 4096,
            "system": instructions,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ])

        let data = try await responseData(for: request, provider: "Claude Fable 5", status: status)
        return try nonEmptyCleanedOutput(extractClaudeText(from: data))
    }

    private static func responseData(for request: URLRequest, provider: String, status: StatusHandler?) async throws -> Data {
        status?("Waiting for \(provider)...")
        aiBackendLogger.info("Starting \(provider, privacy: .public) request")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendError.invalidResponse
        }

        aiBackendLogger.info("\(provider, privacy: .public) request completed; status=\(httpResponse.statusCode, privacy: .public), bytes=\(data.count, privacy: .public)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIBackendError.requestFailed(errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)")
        }

        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        return String(data: data, encoding: .utf8)
    }

    private static func extractOpenAIText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIBackendError.invalidResponse
        }

        if let text = object["output_text"] as? String {
            return text
        }

        if let output = object["output"] as? [[String: Any]] {
            let chunks = output.flatMap { item -> [String] in
                guard let content = item["content"] as? [[String: Any]] else {
                    return []
                }

                return content.compactMap { contentItem in
                    if let text = contentItem["text"] as? String {
                        return text
                    }

                    return contentItem["output_text"] as? String
                }
            }

            if !chunks.isEmpty {
                return chunks.joined(separator: "\n")
            }
        }

        throw AIBackendError.invalidResponse
    }

    private static func extractClaudeText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]]
        else {
            throw AIBackendError.invalidResponse
        }

        let chunks = content.compactMap { item in
            item["text"] as? String
        }

        guard !chunks.isEmpty else {
            throw AIBackendError.invalidResponse
        }

        return chunks.joined(separator: "\n")
    }

    private static func nonEmptyCleanedOutput(_ output: String) throws -> String {
        let cleaned = cleanedModelOutput(output)
        guard !cleaned.isEmpty else {
            throw AIBackendError.emptyResponse
        }

        return cleaned
    }

    private static func cleanedModelOutput(_ output: String) -> String {
        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned.removeFirst()
            cleaned.removeLast()
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uploadImage(from cgImage: CGImage) throws -> UploadImage {
        #if canImport(UIKit)
        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let longestEdge = max(sourceSize.width, sourceSize.height)
        let maxUploadEdge: CGFloat = 1800
        let scale = longestEdge > maxUploadEdge ? maxUploadEdge / longestEdge : 1
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let image = UIImage(cgImage: cgImage)
        let renderedImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = renderedImage.jpegData(compressionQuality: 0.82) else {
            throw AIBackendError.invalidImage
        }

        return UploadImage(data: data, mediaType: "image/jpeg")
        #else
        throw AIBackendError.invalidImage
        #endif
    }
}

private struct UploadImage {
    let data: Data
    let mediaType: String

    var base64Data: String {
        data.base64EncodedString()
    }

    var dataURL: String {
        "data:\(mediaType);base64,\(base64Data)"
    }
}

enum AIBackendError: Error, LocalizedError {
    case emptyResponse
    case invalidImage
    case invalidResponse
    case missingAPIKey(String)
    case modelUnavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The AI backend returned an empty response."
        case .invalidImage:
            return "Yubi could not prepare the image for the selected backend."
        case .invalidResponse:
            return "The AI backend returned an unexpected response."
        case .missingAPIKey(let provider):
            return "\(provider) API key is missing."
        case .modelUnavailable:
            return "The Apple model is unavailable."
        case .requestFailed(let message):
            return message
        }
    }
}
