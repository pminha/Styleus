#!/usr/bin/env swift
// Original Styleus vector artwork. Render SVG and PNG from the same geometry.
// Usage: swift scripts/render_branding.swift
import Foundation
import CoreGraphics
import ImageIO

private enum Command {
    case move(Double, Double), line(Double, Double)
    case quad(Double, Double, Double, Double)
    case close
    var svg: String {
        switch self {
        case .move(let x, let y): return "M \(x) \(y)"
        case .line(let x, let y): return "L \(x) \(y)"
        case .quad(let cx, let cy, let x, let y): return "Q \(cx) \(cy) \(x) \(y)"
        case .close: return "Z"
        }
    }
    func append(to path: CGMutablePath) {
        switch self {
        case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
        case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
        case .quad(let cx, let cy, let x, let y): path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
        case .close: path.closeSubpath()
        }
    }
}

private struct Shape {
    enum Geometry { case roundedRect(CGRect, Double), circle(Double, Double, Double), path([Command]) }
    let geometry: Geometry
    let fill: String
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1
    var strokeWidth: Double? = nil
    var svg: String {
        let paint = strokeWidth.map { "fill=\"none\" stroke=\"\(fill)\" stroke-width=\"\($0)\" stroke-linejoin=\"round\" stroke-linecap=\"butt\"" } ?? "fill=\"\(fill)\""
        let transform = "transform=\"translate(\(x) \(y)) scale(\(scale))\" \(paint)"
        switch geometry {
        case .roundedRect(let rect, let radius):
            return "<rect x=\"\(rect.minX)\" y=\"\(rect.minY)\" width=\"\(rect.width)\" height=\"\(rect.height)\" rx=\"\(radius)\" \(transform)/>"
        case .circle(let cx, let cy, let radius):
            return "<circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(radius)\" \(transform)/>"
        case .path(let commands):
            return "<path d=\"\(commands.map(\.svg).joined(separator: " "))\" \(transform)/>"
        }
    }
    func draw(in context: CGContext) {
        let path: CGPath
        switch geometry {
        case .roundedRect(let rect, let radius):
            path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .circle(let cx, let cy, let radius):
            path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        case .path(let commands):
            let p = CGMutablePath()
            commands.forEach { $0.append(to: p) }
            path = p
        }
        context.saveGState()
        context.translateBy(x: x, y: y)
        context.scaleBy(x: scale, y: scale)
        let rgb = UInt32(fill.dropFirst(), radix: 16)!
        let color = CGColor(red: CGFloat((rgb >> 16) & 255) / 255,
                            green: CGFloat((rgb >> 8) & 255) / 255,
                            blue: CGFloat(rgb & 255) / 255, alpha: 1)
        context.addPath(path)
        if let strokeWidth {
            context.setStrokeColor(color)
            context.setLineWidth(strokeWidth)
            context.setLineJoin(.round)
            context.setLineCap(.butt)
            context.strokePath()
        } else {
            context.setFillColor(color)
            context.fillPath()
        }
        context.restoreGState()
    }
}

private let ink = "#20211F"
private let paper = "#F3F2ED"
private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, radius: Double = 0, fill: String) -> Shape {
    Shape(geometry: .roundedRect(CGRect(x: x, y: y, width: w, height: h), radius), fill: fill)
}

// Reference-proportioned Pencil with a broad nib and a slightly wider cursor
// stem. The join uses one constant-width stroke rather than hand-offset edges.
private func pencilCursor(x: Double, y: Double, scale: Double) -> [Shape] {
    [Shape(geometry: .path([
        .move(311, 871), .line(945, 257),
        .quad(979, 223, 1013, 257), .quad(1047, 291, 1013, 325),
        .line(382, 941), .line(270, 1008),
        .quad(257, 1016, 249, 1007), .quad(242, 1000, 249, 987), .close,
    ]), fill: ink, x: x, y: y, scale: scale),
     Shape(geometry: .path([
        .move(308, 858), .line(342, 892), .line(362, 872),
        .line(380, 890), .line(360, 910), .line(399, 949),
    ]), fill: paper, x: x, y: y, scale: scale, strokeWidth: 9)]
}

private func artwork(_ platform: String) -> [Shape] {
    if platform == "ipad" {
        return [rect(0, 0, 1024, 1024, fill: paper),
                rect(202, 100, 620, 824, radius: 56, fill: ink),
                rect(218, 116, 588, 792, radius: 40, fill: paper)]
            + pencilCursor(x: 116.75, y: 122.95, scale: 0.62)
    }
    return [rect(112, 224, 800, 512, radius: 32, fill: ink),
            rect(128, 240, 768, 480, radius: 16, fill: paper),
            Shape(geometry: .path([
                .move(80, 736), .line(944, 736), .line(931, 753), .quad(928, 758, 920, 758),
                .line(104, 758), .quad(96, 758, 93, 753), .close,
            ]), fill: ink)]
        + pencilCursor(x: 218.75, y: 191.35, scale: 0.46)
}

private func renderPNG(_ shapes: [Shape], pixels: Int, opaque: Bool, to output: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else {
        throw NSError(domain: "StyleusArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon canvas."])
    }
    context.setAllowsAntialiasing(true)
    context.translateBy(x: 0, y: CGFloat(pixels))
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: -scale)
    shapes.forEach { $0.draw(in: context) }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "StyleusArtwork", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write icon PNG."])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "StyleusArtwork", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not finish icon PNG."])
    }
}

do {
    let publicDirectory = root.appendingPathComponent("media/branding")
    let previewDirectory = root.appendingPathComponent("build/branding-preview")
    try FileManager.default.createDirectory(at: publicDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    try renderPNG([rect(0, 0, 1024, 1024, fill: paper)] + pencilCursor(x: 0, y: 0, scale: 1024.0 / 1254.0), pixels: 512, opaque: true, to: previewDirectory.appendingPathComponent("pencil-reference-512.png"))
    for platform in ["ipad", "mac"] {
        let shapes = artwork(platform)
        let title = platform == "ipad" ? "Styleus iPad" : "Styleus Mac"
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">
          <title id="title">\(title): Pencil tip as cursor</title>
          \(shapes.map(\.svg).joined(separator: "\n  "))
        </svg>

        """
        try svg.write(to: publicDirectory.appendingPathComponent("styleus-\(platform).svg"), atomically: true, encoding: .utf8)
        try renderPNG(shapes, pixels: 1024, opaque: platform == "ipad", to: publicDirectory.appendingPathComponent("styleus-\(platform)-1024.png"))
        for pixels in [256, 32] {
            try renderPNG(shapes, pixels: pixels, opaque: platform == "ipad", to: previewDirectory.appendingPathComponent("styleus-\(platform)-\(pixels).png"))
        }
        print("Rendered original \(title) SVG and PNG master.")
    }
} catch {
    fputs("Brand artwork failed: \(error)\n", stderr)
    exit(1)
}
