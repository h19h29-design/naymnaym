import AppKit
import Vision

// Reads back the visible text of a captured store frame so the screenshot set can be
// verified without opening the images. Usage: swift store-frame-ocr.swift frame.jpg ...
let paths = Array(CommandLine.arguments.dropFirst())
var showBoxes = false
var targets: [String] = []
for argument in paths {
    if argument == "--boxes" {
        showBoxes = true
    } else {
        targets.append(argument)
    }
}
guard !targets.isEmpty else {
    print("usage: swift store-frame-ocr.swift [--boxes] <image>...")
    exit(2)
}

for path in targets {
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
    if showBoxes, let width = cgImage.width as Int?, let height = cgImage.height as Int? {
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let box = observation.boundingBox
            let x = Int(box.origin.x * CGFloat(width))
            let y = Int((1 - box.origin.y - box.height) * CGFloat(height))
            let w = Int(box.width * CGFloat(width))
            let h = Int(box.height * CGFloat(height))
            let centreX = x + w / 2
            let centreY = y + h / 2
            print("  " + text + " @ " + String(centreX) + "," + String(centreY))
        }
    }
}
