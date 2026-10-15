import Foundation
import Vision

/// On-device OCR using Apple's Vision framework (same engine as Live Text).
enum TextRecognizer {
    static func recognize(imageAt url: URL, completion: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(url: url, options: [:])
            var text = ""
            do {
                try handler.perform([request])
                text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            } catch {
                NSLog("Marquee: OCR failed: \(error)")
            }
            Task { @MainActor in completion(text) }
        }
    }
}
