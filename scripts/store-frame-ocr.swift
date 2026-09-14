import AppKit
import Vision

// Reads back the visible text of a captured store frame so the screenshot set can be
// verified without opening the images. Usage: swift store-frame-ocr.swift frame.jpg ...
let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    print("usage: swift store-frame-ocr.swift <image>...")
    exit(2)
}

for path in paths {
    let name = URL(fileURLWithPath: path).lastPathComponent
    print("### " + name)
    guard let image = NSImage(contentsOfFile: path),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImage = bitmap.cgImage else {
        print("(unreadable)")
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("(ocr failed: " + error.localizedDescription + ")")
        continue
    }
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    print(lines.prefix(45).joined(separator: " / "))
}
