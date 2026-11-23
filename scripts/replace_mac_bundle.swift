import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: replace_mac_bundle.swift SOURCE_APP DESTINATION_APP\n".utf8))
    exit(2)
}

// Stage the entire signed bundle on the destination volume. Merging a Release
// build into a Debug app can leave old executable files inside the bundle.
let manager = FileManager.default
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let staged = destination.deletingLastPathComponent().appendingPathComponent(".styleus-\(UUID().uuidString).app")
do {
    defer { try? manager.removeItem(at: staged) }
    try manager.copyItem(at: source, to: staged)
    if manager.fileExists(atPath: destination.path) {
        _ = try manager.replaceItemAt(destination, withItemAt: staged, options: .usingNewMetadataOnly)
    } else {
        try manager.moveItem(at: staged, to: destination)
    }
} catch {
    FileHandle.standardError.write(Data("Could not install the Mac app at \(destination.path). \(error.localizedDescription)\n".utf8))
    exit(1)
}
