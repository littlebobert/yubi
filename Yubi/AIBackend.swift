import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os
import Security
#if canImport(UIKit)
import UIKit
#endif

private let aiBackendAppGroupIdentifier = "group.com.justin.yubi"
private let aiBackendLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "AIBackend"
)

enum AIBackend: String, CaseIterable, Identifiable {
    case applePCC
    case openAI
    case claudeFable

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .applePCC:
            return "Apple Private Cloud Compute"
        case .openAI:
            return "OpenAI"
        case .claudeFable:
            return "Claude Fable 5"
        }
    }

    var detail: String {
        switch self {
        case .applePCC:
            return "private and free, with a daily limit"
        case .openAI:
            return "balanced"
        case .claudeFable:
            return "strongest, most expensive"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .applePCC:
            return AIBackendClient.isPrivateCloudComputeSupported
        case .openAI, .claudeFable:
            return true
        }
    }
}

enum AIBackendSettings {
    private static let backendKey = "YubiAIBackend"
    private static let legacyOpenAIAPIKeyKey = "YubiOpenAIAPIKey"
    private static let legacyClaudeAPIKeyKey = "YubiClaudeAPIKey"

    static var selectedBackend: AIBackend {
        get {
            guard let rawValue = userDefaults.string(forKey: backendKey),
                  let backend = AIBackend(rawValue: rawValue),
                  backend.isAvailable
            else {
                return defaultBackend
            }

            return backend
        }
        set {
            userDefaults.set((newValue.isAvailable ? newValue : defaultBackend).rawValue, forKey: backendKey)
        }
    }

    private static var defaultBackend: AIBackend {
        AIBackend.applePCC.isAvailable ? .applePCC : .openAI
    }

    static var openAIAPIKey: String {
        get {
            removeLegacyAPIKey(forKey: legacyOpenAIAPIKeyKey)
            return AIBackendCredentialStore.read(account: "openai")
        }
        set {
            removeLegacyAPIKey(forKey: legacyOpenAIAPIKeyKey)
            AIBackendCredentialStore.write(newValue, account: "openai")
        }
    }

    static var claudeAPIKey: String {
        get {
            removeLegacyAPIKey(forKey: legacyClaudeAPIKeyKey)
            return AIBackendCredentialStore.read(account: "claude")
        }
        set {
            removeLegacyAPIKey(forKey: legacyClaudeAPIKeyKey)
            AIBackendCredentialStore.write(newValue, account: "claude")
        }
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: aiBackendAppGroupIdentifier) ?? .standard
    }

    private static func removeLegacyAPIKey(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}

private enum AIBackendCredentialStore {
    private static let service = "com.justin.yubi.ai-backend"
    private static let accessGroupInfoKey = "YubiKeychainAccessGroup"

    static func read(account: String) -> String {
        guard var query = baseQuery(account: account) else {
            return ""
        }

        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return ""
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            aiBackendLogger.error("Could not read \(account, privacy: .public) API key from Keychain; status=\(status, privacy: .public)")
            return ""
        }

        return value
    }

    static func write(_ value: String, account: String) {
        guard let query = baseQuery(account: account) else {
            return
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                aiBackendLogger.error("Could not remove \(account, privacy: .public) API key from Keychain; status=\(status, privacy: .public)")
            }
            return
        }

        let data = Data(trimmedValue.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            aiBackendLogger.error("Could not update \(account, privacy: .public) API key in Keychain; status=\(updateStatus, privacy: .public)")
            return
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            aiBackendLogger.error("Could not save \(account, privacy: .public) API key in Keychain; status=\(addStatus, privacy: .public)")
        }
    }

    private static func baseQuery(account: String) -> [CFString: Any]? {
        guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoKey) as? String,
              !accessGroup.isEmpty,
              !accessGroup.contains("$(")
        else {
            aiBackendLogger.error("Shared Keychain access group is missing from Info.plist")
            return nil
        }

        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: accessGroup
        ]
    }
}

enum AIBackendClient {
    private static let openAIModel = "gpt-5.6-sol"
    private static let claudeModel = "claude-fable-5-thinking-high"
    typealias StatusHandler = @Sendable (String) -> Void
    typealias PartialResultHandler = @Sendable (String) async -> Void

    static func analyzeScreenshotText(
        _ text: String,
        targetLanguage: String,
        status: StatusHandler? = nil,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
        // TEMP: food-label experiment. PCC gets a nutrition prompt instead of summary + translation.
        if AIBackendSettings.selectedBackend == .applePCC {
            return try await analyzeFoodLabelText(text, targetLanguage: targetLanguage, status: status, partialResult: partialResult)
        }

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

        return try await respond(
            instructions: instructions,
            prompt: prompt,
            status: status,
            partialResult: partialResult
        )
    }

    // TEMP: food-label experiment for the PCC backend.
    private static func foodLabelInstructions(targetLanguage: String) -> String {
        """
        You are a nutrition expert. You read photos or screenshots of food, food packaging, and nutrition labels. Use your general knowledge of foods, brands, ingredients, and nutrition to interpret what you see and fill gaps, and say when you are estimating. Reply in plain text only, with no Markdown, in \(targetLanguage).
        """
    }

    private static let foodLabelRequestedLines = """
    Identify the food, then return exactly these three lines:
    Protein: grams per serving and per 100 g if available (mark estimates as estimated)
    Sugar: grams per serving and per 100 g if available, including added sugar if listed (mark estimates as estimated)
    Health grade: one letter from A, B, C, D, E, or F (A is healthiest, F is worst), followed by a short reason
    """

    private static func analyzeFoodLabelText(
        _ text: String,
        targetLanguage: String,
        status: StatusHandler?,
        partialResult: PartialResultHandler?
    ) async throws -> String {
        let prompt = """
        OCR text from a food label (may be noisy or incomplete):
        \(text)

        \(foodLabelRequestedLines)
        """

        status?("Apple Private Cloud Compute is analyzing the food label...")
        return try await privateCloudComputeResponse(
            instructions: foodLabelInstructions(targetLanguage: targetLanguage),
            prompt: prompt,
            image: nil,
            reasoningLevel: .deep,
            partialResult: partialResult
        )
    }

    private static func analyzeFoodLabelImage(
        _ cgImage: CGImage,
        targetLanguage: String,
        status: StatusHandler?,
        partialResult: PartialResultHandler?
    ) async throws -> String {
        let prompt = """
        Analyze the food in this image.

        \(foodLabelRequestedLines)
        """

        status?("Apple Private Cloud Compute is analyzing the image...")
        return try await privateCloudComputeResponse(
            instructions: foodLabelInstructions(targetLanguage: targetLanguage),
            prompt: prompt,
            image: cgImage,
            reasoningLevel: .deep,
            partialResult: partialResult
        )
    }

    static func analyzeScreenshotImage(
        _ cgImage: CGImage,
        targetLanguage: String,
        status: StatusHandler? = nil,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
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
        case .applePCC:
            // TEMP: food-label experiment.
            return try await analyzeFoodLabelImage(
                cgImage,
                targetLanguage: targetLanguage,
                status: status,
                partialResult: partialResult
            )
        case .openAI:
            status?("Preparing image for OpenAI...")
            let image = try uploadImage(from: cgImage)
            status?("OpenAI is analyzing the image...")
            return try await openAIResponse(
                instructions: instructions,
                prompt: prompt,
                image: image,
                status: status,
                partialResult: partialResult
            )
        case .claudeFable:
            status?("Preparing image for Claude Fable 5...")
            let image = try uploadImage(from: cgImage)
            status?("Claude Fable 5 is analyzing the image...")
            return try await claudeResponse(
                instructions: instructions,
                prompt: prompt,
                image: image,
                status: status,
                partialResult: partialResult
            )
        }
    }

    static func translate(
        _ text: String,
        targetLanguage: String,
        toneInstruction: String?,
        status: StatusHandler? = nil,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
        let toneSentence = toneInstruction.map { " Use \($0)." } ?? ""
        let instructions = """
        Detect the source language and translate user-selected text into natural \(targetLanguage).\(toneSentence) Return only the translation, with no explanation, labels, or quotation marks.
        """
        let prompt = """
        Detect the source language and translate this text to \(targetLanguage).\(toneSentence) Preserve names, numbers, URLs, and line breaks where reasonable. Return only the translation:

        \(text)
        """

        return try await respond(
            instructions: instructions,
            prompt: prompt,
            status: status,
            partialResult: partialResult
        )
    }

    private static func respond(
        instructions: String,
        prompt: String,
        status: StatusHandler? = nil,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
        switch AIBackendSettings.selectedBackend {
        case .applePCC:
            status?("Apple Private Cloud Compute is analyzing the text...")
            return try await privateCloudComputeResponse(
                instructions: instructions,
                prompt: prompt,
                image: nil,
                reasoningLevel: nil,
                partialResult: partialResult
            )
        case .openAI:
            status?("OpenAI is analyzing the text...")
            return try await openAIResponse(
                instructions: instructions,
                prompt: prompt,
                image: nil,
                status: status,
                partialResult: partialResult
            )
        case .claudeFable:
            status?("Claude Fable 5 is analyzing the text...")
            return try await claudeResponse(
                instructions: instructions,
                prompt: prompt,
                image: nil,
                status: status,
                partialResult: partialResult
            )
        }
    }

    // PrivateCloudComputeLanguageModel ships in the iOS 27 SDK (Swift 6.4). Older stable
    // toolchains compile this out and the backend shows as unavailable.
    static var isPrivateCloudComputeSupported: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    enum PCCReasoningLevel {
        case light
        case moderate
        case deep
    }

    private static func privateCloudComputeResponse(
        instructions: String,
        prompt: String,
        image: CGImage?,
        reasoningLevel: PCCReasoningLevel?,
        partialResult: PartialResultHandler?
    ) async throws -> String {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            switch model.availability {
            case .available:
                break
            case .unavailable(let reason):
                aiBackendLogger.error("Private Cloud Compute unavailable; reason=\(String(describing: reason), privacy: .public)")
                throw AIBackendError.privateCloudComputeUnavailable
            }

            if image != nil, !model.capabilities.contains(.vision) {
                throw AIBackendError.imageInputUnsupported
            }

            let request = Prompt {
                prompt
                if let image {
                    Attachment(image)
                }
            }

            let contextOptions: ContextOptions
            switch reasoningLevel {
            case .light:
                contextOptions = ContextOptions(reasoningLevel: .light)
            case .moderate:
                contextOptions = ContextOptions(reasoningLevel: .moderate)
            case .deep:
                contextOptions = ContextOptions(reasoningLevel: .deep)
            case nil:
                contextOptions = ContextOptions()
            }

            let session = LanguageModelSession(model: model, instructions: instructions)
            do {
                guard let partialResult else {
                    let response = try await session.respond(to: request, contextOptions: contextOptions)
                    return try nonEmptyCleanedOutput(response.content)
                }

                var latestOutput = ""
                for try await snapshot in session.streamResponse(to: request, contextOptions: contextOptions) {
                    try Task.checkCancellation()
                    latestOutput = snapshot.content
                    await partialResult(latestOutput)
                }
                return try nonEmptyCleanedOutput(latestOutput)
            } catch let error as PrivateCloudComputeLanguageModel.Error {
                aiBackendLogger.error("Private Cloud Compute request failed; error=\(String(describing: error), privacy: .public)")
                switch error {
                case .quotaLimitReached:
                    throw AIBackendError.dailyLimitReached
                case .networkFailure, .serviceUnavailable:
                    throw AIBackendError.privateCloudComputeUnavailable
                @unknown default:
                    throw AIBackendError.requestFailed(String(describing: error))
                }
            }
        }
        #else
        _ = (instructions, prompt, image, reasoningLevel, partialResult)
        #endif

        throw AIBackendError.privateCloudComputeUnavailable
    }

    private static func openAIResponse(
        instructions: String,
        prompt: String,
        image: UploadImage?,
        status: StatusHandler?,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
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
            "service_tier": "fast",
            "stream": partialResult != nil,
            "instructions": instructions,
            "reasoning": [
                "effort": "medium"
            ],
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ])

        guard let partialResult else {
            let data = try await responseData(for: request, provider: "OpenAI", status: status)
            return try nonEmptyCleanedOutput(extractOpenAIText(from: data))
        }

        return try await streamedResponse(
            for: request,
            provider: "OpenAI",
            status: status,
            partialResult: partialResult
        ) { event in
            guard event["type"] as? String == "response.output_text.delta" else {
                return nil
            }
            return event["delta"] as? String
        }
    }

    private static func claudeResponse(
        instructions: String,
        prompt: String,
        image: UploadImage?,
        status: StatusHandler?,
        partialResult: PartialResultHandler? = nil
    ) async throws -> String {
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
            "stream": partialResult != nil,
            "system": instructions,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ])

        guard let partialResult else {
            let data = try await responseData(for: request, provider: "Claude Fable 5", status: status)
            return try nonEmptyCleanedOutput(extractClaudeText(from: data))
        }

        return try await streamedResponse(
            for: request,
            provider: "Claude Fable 5",
            status: status,
            partialResult: partialResult
        ) { event in
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta"
            else {
                return nil
            }
            return delta["text"] as? String
        }
    }

    private static func streamedResponse(
        for request: URLRequest,
        provider: String,
        status: StatusHandler?,
        partialResult: PartialResultHandler,
        extractDelta: ([String: Any]) -> String?
    ) async throws -> String {
        status?("Waiting for \(provider)...")
        aiBackendLogger.info("Starting streaming \(provider, privacy: .public) request")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            throw AIBackendError.requestFailed(
                errorMessage(from: errorData) ?? "HTTP \(httpResponse.statusCode)"
            )
        }

        var accumulatedOutput = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else {
                continue
            }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = extractDelta(event),
                  !delta.isEmpty
            else {
                continue
            }

            accumulatedOutput += delta
            await partialResult(accumulatedOutput)
        }

        aiBackendLogger.info("Streaming \(provider, privacy: .public) request completed; characters=\(accumulatedOutput.count, privacy: .public)")
        return try nonEmptyCleanedOutput(accumulatedOutput)
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
    case privateCloudComputeUnavailable
    case imageInputUnsupported
    case dailyLimitReached
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
        case .privateCloudComputeUnavailable:
            return "Apple Private Cloud Compute is unavailable. It needs iOS 27, an Apple Intelligence device, and a network connection."
        case .imageInputUnsupported:
            return "The selected model can't read images."
        case .dailyLimitReached:
            return "You've reached today's Apple Private Cloud Compute limit. Try again tomorrow or choose another backend."
        case .requestFailed(let message):
            return message
        }
    }
}
