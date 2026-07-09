import AppIntents
import os
import UIKit
import Vision

private let screenshotIntentLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yubi",
    category: "ScreenshotIntent"
)

public struct AnalyzeImageIntent: AppIntent {
    public static var title: LocalizedStringResource = "Analyze Image with Yubi"
    public static var description = IntentDescription("Extract text from an image, then summarize and translate it.")
    public static var openAppWhenRun = true

    @Parameter(
        title: "Image",
        description: "Screenshot or image to analyze",
        supportedTypeIdentifiers: ["public.image"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    public var image: IntentFile

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$image) with Yubi")
    }

    public func perform() async throws -> some IntentResult {
        screenshotIntentLogger.info("Analyze Image intent started; imageBytes=\(image.data.count, privacy: .public)")
        let analysisID = UUID()
        let imageFilename = ScreenshotAnalysisStore.saveImageData(image.data, for: analysisID)
        ScreenshotAnalysisStore.save(ScreenshotAnalysis(
            id: analysisID,
            date: Date(),
            detectedText: "",
            result: "",
            imageFilename: imageFilename,
            isComplete: false
        ))
        ScreenshotAnalysisStatusStore.markRunning("Reading screenshot", analysisID: analysisID)

        do {
            let backend = AIBackendSettings.selectedBackend
            let message = "\(backend.displayName) is analyzing the image..."

            if backend != .apple {
                ScreenshotAnalysisStatusStore.markRunning(message, analysisID: analysisID)
                screenshotIntentLogger.info("Analyze Image intent saved pending image for selected backend")
                return .result()
            }

            let detectedText = try recognizedText(from: image.data)
            ScreenshotAnalysisStore.save(ScreenshotAnalysis(
                id: analysisID,
                date: Date(),
                detectedText: detectedText,
                result: "",
                imageFilename: imageFilename,
                isComplete: false
            ))
            ScreenshotAnalysisStatusStore.markRunning(message, analysisID: analysisID)

            screenshotIntentLogger.info("Analyze Image intent saved pending result; detectedCharacters=\(detectedText.count, privacy: .public)")
            return .result()
        } catch {
            ScreenshotAnalysisStatusStore.markFailed("Analysis failed", analysisID: analysisID)
            screenshotIntentLogger.error("Analyze Image intent failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func recognizedText(from imageData: Data) throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage
        else {
            screenshotIntentLogger.error("OCR failed: invalid image data")
            throw ScreenshotAnalysisError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let text = request.results?
            .compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            screenshotIntentLogger.warning("OCR completed without text")
            throw ScreenshotAnalysisError.noTextFound
        }

        screenshotIntentLogger.info("OCR completed; detectedCharacters=\(text.count, privacy: .public), observations=\(request.results?.count ?? 0, privacy: .public)")
        return text
    }
}

public struct AnalyzeTextIntent: AppIntent {
    public static var title: LocalizedStringResource = "Analyze Text with Yubi"
    public static var description = IntentDescription("Summarize and translate text extracted from a screenshot.")
    public static var openAppWhenRun = true

    @Parameter(title: "Text", description: "Text extracted from a screenshot")
    public var text: String

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$text) with Yubi")
    }

    public func perform() async throws -> some IntentResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            screenshotIntentLogger.warning("Analyze Text intent ran without text")
            return .result()
        }

        screenshotIntentLogger.info("Analyze Text intent started; characters=\(trimmedText.count, privacy: .public)")
        let analysisID = UUID()
        ScreenshotAnalysisStore.save(ScreenshotAnalysis(
            id: analysisID,
            date: Date(),
            detectedText: trimmedText,
            result: "",
            isComplete: false
        ))
        let message = "\(AIBackendSettings.selectedBackend.displayName) is analyzing the text..."
        ScreenshotAnalysisStatusStore.markRunning(message, analysisID: analysisID)
        screenshotIntentLogger.info("Analyze Text intent saved pending result")
        return .result()
    }
}

private enum ScreenshotAnalysisError: Error, CustomLocalizedStringResourceConvertible {
    case invalidImage
    case noTextFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidImage:
            return "Yubi could not read that image."
        case .noTextFound:
            return "Yubi could not find text in that image."
        }
    }
}
