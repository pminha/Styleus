import Foundation

struct Point: Codable, Equatable {
    var x: Double
    var y: Double
    var isFinite: Bool { x.isFinite && y.isFinite }
    static let zero = Point(x: 0, y: 0)
}

struct Rect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
    var aspect: Double { width / height }
    func contains(_ p: Point) -> Bool {
        isValid && p.isFinite && p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height
    }
    func clamped(_ p: Point) -> Point {
        Point(x: min(max(p.x, x), x + width - 0.001), y: min(max(p.y, y), y + height - 0.001))
    }
    func contains(_ other: Rect) -> Bool {
        other.isValid && contains(Point(x: other.x, y: other.y)) &&
        contains(Point(x: other.x + other.width, y: other.y + other.height))
    }
}

enum CoordinateMapping {
    /// Quartz is top-left/downward; AppKit is bottom-left/upward relative to the
    /// primary screen. Use the primary frame, not the screen containing the pointer.
    static func appKitPoint(fromQuartz point: Point, primaryFrame: Rect) -> Point? {
        guard point.isFinite, primaryFrame.isValid else { return nil }
        return Point(x: primaryFrame.x + point.x, y: primaryFrame.y + primaryFrame.height - point.y)
    }

    // Both input and Quartz desktop coordinates have a top-left origin and positive Y downward.
    static func fittedArea(surface: Rect, targetAspect: Double) -> Rect? {
        guard surface.isValid, targetAspect.isFinite, targetAspect > 0 else { return nil }
        let width = min(surface.width, surface.height * targetAspect)
        let height = width / targetAspect
        return Rect(x: surface.x + (surface.width - width) / 2,
                    y: surface.y + (surface.height - height) / 2, width: width, height: height)
    }

    static func normalized(_ p: Point, in area: Rect) -> Point? {
        guard area.contains(p) else { return nil }
        return Point(x: (p.x - area.x) / area.width, y: (p.y - area.y) / area.height)
    }

    static func absolute(_ p: Point, target: Rect) -> Point? {
        guard p.isFinite, target.isValid, (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        // The far edge lies just inside the display, not on an adjacent display.
        return target.clamped(Point(x: target.x + p.x * target.width, y: target.y + p.y * target.height))
    }

    static func constrainedToDisplays(_ p: Point, displays: [Rect]) -> Point {
        if displays.contains(where: { $0.contains(p) }) { return p }
        return displays.filter(\.isValid).map { $0.clamped(p) }.min {
            hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y)
        } ?? p
    }
}
