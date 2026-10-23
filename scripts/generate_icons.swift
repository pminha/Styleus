#!/usr/bin/env swift
// Resize the checked-in icon masters with macOS's sips and regenerate native catalogs.
// Usage (from any directory): swift scripts/generate_icons.swift
import Foundation
import CoreGraphics
import ImageIO

enum IconError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

struct IconSlot {
    let idiom: String
    let points: String
    let scale: Int
    var pixels: Int { Int(Double(points)! * Double(scale)) }
    var filename: String { "\(idiom)-\(points)@\(scale)x.png" }
    var metadata: [String: String] {
        ["idiom": idiom, "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename]
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let metadata: [String: Any] = ["author": "xcode", "version": 1]
let ipadSlots = ["20", "29", "40", "76"].flatMap { points in
    [1, 2].map { IconSlot(idiom: "ipad", points: points, scale: $0) }
} + [IconSlot(idiom: "ipad", points: "83.5", scale: 2),
     IconSlot(idiom: "ios-marketing", points: "1024", scale: 1)]
let macSlots = ["16", "32", "128", "256", "512"].flatMap { points in
    [1, 2].map { IconSlot(idiom: "mac", points: points, scale: $0) }
}

func writeJSON(_ value: [String: Any], to url: URL) throws {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    data.append(0x0a)
    try data.write(to: url, options: .atomic)
}

func validateMaster(_ url: URL, opaque: Bool) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetType(source) as String? == "public.png",
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == 1024, image.height == 1024 else {
        throw IconError.invalid("Expected a 1024×1024 PNG: \(url.lastPathComponent)")
    }
    let noAlpha = [CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    guard !opaque || noAlpha else {
        throw IconError.invalid("iPad icon master must have no alpha channel: \(url.lastPathComponent)")
    }
}

func resize(_ source: URL, pixels: Int, to destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["--resampleHeightWidth", "\(pixels)", "\(pixels)", source.path, "--out", destination.path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let message = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconError.invalid(String(data: message, encoding: .utf8) ?? "Icon resizing failed.")
    }
}

func generate(folder: String, masterName: String, slots: [IconSlot]) throws {
    let master = root.appendingPathComponent("media/branding/\(masterName)")
    try validateMaster(master, opaque: folder == "iPad")
    let catalog = root.appendingPathComponent("\(folder)/Assets.xcassets")
    let icon = catalog.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
    for slot in slots {
        try resize(master, pixels: slot.pixels, to: icon.appendingPathComponent(slot.filename))
    }
    try writeJSON(["info": metadata], to: catalog.appendingPathComponent("Contents.json"))
    try writeJSON(["info": metadata, "images": slots.map(\.metadata)], to: icon.appendingPathComponent("Contents.json"))
    print("Generated \(folder)/Assets.xcassets/AppIcon.appiconset (\(slots.count) slots)")
}

do {
    guard CommandLine.arguments.count == 1 else {
        throw IconError.invalid("Usage: swift scripts/generate_icons.swift (uses media/branding/*-1024.png)")
    }
    // Validate both inputs before replacing either catalog's images.
    try validateMaster(root.appendingPathComponent("media/branding/styleus-ipad-1024.png"), opaque: true)
    try validateMaster(root.appendingPathComponent("media/branding/styleus-mac-1024.png"), opaque: false)
    try generate(folder: "iPad", masterName: "styleus-ipad-1024.png", slots: ipadSlots)
    try generate(folder: "Mac", masterName: "styleus-mac-1024.png", slots: macSlots)
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
