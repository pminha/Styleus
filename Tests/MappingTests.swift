import XCTest
@testable import StyleusCore

final class MappingTests: XCTestCase {
    func testQuartzToAppKitIndicatorCoordinatesAcrossDisplays() {
        let primary = Rect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(CoordinateMapping.appKitPoint(fromQuartz: .zero, primaryFrame: primary), Point(x: 0, y: 982))
        XCTAssertEqual(CoordinateMapping.appKitPoint(fromQuartz: Point(x: 700, y: 500), primaryFrame: primary), Point(x: 700, y: 482))
        XCTAssertEqual(CoordinateMapping.appKitPoint(fromQuartz: Point(x: -1200, y: -300), primaryFrame: primary), Point(x: -1200, y: 1282))
        XCTAssertEqual(CoordinateMapping.appKitPoint(fromQuartz: Point(x: 2000, y: 1200), primaryFrame: primary), Point(x: 2000, y: -218))
        XCTAssertNil(CoordinateMapping.appKitPoint(fromQuartz: Point(x: .infinity, y: 0), primaryFrame: primary))
    }

    func testAspectFitDoesNotStretchAndMapsNegativeDisplayOrigin() throws {
        let surface = Rect(x: 0, y: 0, width: 1000, height: 700)
        let target = Rect(x: -1920, y: -200, width: 1920, height: 1080)
        let area = try XCTUnwrap(CoordinateMapping.fittedArea(surface: surface, targetAspect: target.aspect))
        XCTAssertEqual(area.width, 1000)
        XCTAssertEqual(area.height, 562.5)
        XCTAssertEqual(area.y, 68.75)
        let center = try XCTUnwrap(CoordinateMapping.normalized(Point(x: 500, y: 350), in: area))
        XCTAssertEqual(CoordinateMapping.absolute(center, target: target), Point(x: -960, y: 340))
        XCTAssertNil(CoordinateMapping.normalized(Point(x: 0, y: 0), in: area))
        // A circle retains its geometry: the same source step gives the same desktop step on both axes.
        let p1 = try XCTUnwrap(CoordinateMapping.normalized(Point(x: 510, y: 350), in: area))
        let p2 = try XCTUnwrap(CoordinateMapping.normalized(Point(x: 500, y: 360), in: area))
        XCTAssertEqual(try XCTUnwrap(CoordinateMapping.absolute(p1, target: target)).x + 960,
                       try XCTUnwrap(CoordinateMapping.absolute(p2, target: target)).y - 340, accuracy: 1e-8)
    }

    func testPortraitAndCustomRegion() throws {
        let area = try XCTUnwrap(CoordinateMapping.fittedArea(surface: Rect(x: 0, y: 0, width: 600, height: 1000), targetAspect: 2))
        XCTAssertEqual(area, Rect(x: 0, y: 350, width: 600, height: 300))
        let target = Rect(x: 100, y: 200, width: 800, height: 400)
        XCTAssertEqual(CoordinateMapping.absolute(.zero, target: target), Point(x: 100, y: 200))
        let edge = try XCTUnwrap(CoordinateMapping.absolute(Point(x: 1, y: 1), target: target))
        XCTAssertLessThan(edge.x, 900); XCTAssertLessThan(edge.y, 600)
    }

    func testInvalidCoordinatesAndDesktopGap() {
        XCTAssertNil(CoordinateMapping.fittedArea(surface: Rect(x: 0, y: 0, width: 0, height: 10), targetAspect: 1))
        XCTAssertNil(CoordinateMapping.absolute(Point(x: .nan, y: 0), target: Rect(x: 0, y: 0, width: 100, height: 100)))
        let displays = [Rect(x: 0, y: 0, width: 100, height: 100), Rect(x: 200, y: 0, width: 100, height: 100)]
        let constrained = CoordinateMapping.constrainedToDisplays(Point(x: 170, y: 20), displays: displays)
        XCTAssertEqual(constrained.x, 200)
    }
}
