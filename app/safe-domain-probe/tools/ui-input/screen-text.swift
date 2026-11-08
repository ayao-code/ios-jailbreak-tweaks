import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: image)
try handler.perform([request])
let results: [[String: Any]] = (request.results ?? []).compactMap { observation in
    guard let candidate = observation.topCandidates(1).first else {
        return nil
    }
    let bounds = observation.boundingBox
    return ["text": candidate.string, "confidence": candidate.confidence,
            "x": bounds.midX, "y": 1 - bounds.midY,
            "left": bounds.minX, "top": 1 - bounds.maxY,
            "width": bounds.width, "height": bounds.height]
}
let output = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
FileHandle.standardOutput.write(output)
