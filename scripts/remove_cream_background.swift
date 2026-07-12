import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("usage: remove_cream_background input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("failed to read input image\n", stderr)
    exit(3)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(4)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

let reference = (r: 255.0, g: 249.0, b: 238.0)
let distanceLimit = 74.0
var visited = [Bool](repeating: false, count: width * height)
var queue = [Int]()
queue.reserveCapacity(width * 4 + height * 4)

func isBackgroundCandidate(_ pixelIndex: Int) -> Bool {
    let offset = pixelIndex * bytesPerPixel
    let red = Double(pixels[offset])
    let green = Double(pixels[offset + 1])
    let blue = Double(pixels[offset + 2])
    let distance = sqrt(
        pow(red - reference.r, 2) +
        pow(green - reference.g, 2) +
        pow(blue - reference.b, 2)
    )
    let brightness = (red + green + blue) / 3
    return distance <= distanceLimit && brightness >= 205
}

func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let index = y * width + x
    guard !visited[index], isBackgroundCandidate(index) else { return }
    visited[index] = true
    queue.append(index)
}

for x in 0..<width {
    enqueue(x, 0)
    enqueue(x, height - 1)
}
for y in 0..<height {
    enqueue(0, y)
    enqueue(width - 1, y)
}

var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]
    cursor += 1
    let x = index % width
    let y = index / width
    enqueue(x - 1, y)
    enqueue(x + 1, y)
    enqueue(x, y - 1)
    enqueue(x, y + 1)
}

for index in queue {
    let offset = index * bytesPerPixel
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
}

guard let outputImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fputs("failed to create output image\n", stderr)
    exit(5)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("failed to write output image\n", stderr)
    exit(6)
}
