import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Vision

struct MapDetectionResult {
    let isOpen: Bool
    let confidence: Double
    let evidence: [String]
}

struct MapOpenDetector {
    static func score(recognizedText text: [String]) -> MapDetectionResult {
        let normalized = text.map { $0.lowercased() }
        let strong = ["waypoints", "show party", "place marker", "remove marker", "map"]
        let supporting = ["journal", "camp", "legend", "quest", "fast travel"]
        let strongHits = strong.filter { needle in normalized.contains(where: { $0.contains(needle) }) }
        let supportingHits = supporting.filter { needle in normalized.contains(where: { $0.contains(needle) }) }
        let score = min(1.0, Double(strongHits.count) * 0.48 + Double(supportingHits.count) * 0.16)
        return MapDetectionResult(isOpen: !strongHits.isEmpty && score >= 0.48, confidence: score, evidence: strongHits + supportingHits)
    }

    func detect(jpegData: Data) async -> MapDetectionResult {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return MapDetectionResult(isOpen: false, confidence: 0, evidence: ["Image decode failed"])
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil else {
                    continuation.resume(returning: MapDetectionResult(isOpen: false, confidence: 0, evidence: [error!.localizedDescription]))
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: Self.score(recognizedText: text))
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .utility).async {
                do { try handler.perform([request]) }
                catch { continuation.resume(returning: MapDetectionResult(isOpen: false, confidence: 0, evidence: [error.localizedDescription])) }
            }
        }
    }
}
