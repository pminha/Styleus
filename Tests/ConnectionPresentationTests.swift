import XCTest
@testable import StyleusCore

final class ConnectionPresentationTests: XCTestCase {
    func testSuccessfulConnectionClearsOldIssueAndReportsAuthenticatedTransport() {
        var progress = ConnectionProgress()
        progress.finish(issue: .notFound)
        progress.establish()
        XCTAssertNil(progress.issue)
        for mode in ConnectionMode.allCases {
            let info = progress.presentation(paired: true, inputAllowed: true, mode: mode, status: "Connected")
            XCTAssertEqual(info.headerTitle, "Connected · encrypted \(mode.title)")
            XCTAssertFalse(info.isProblem)
            XCTAssertTrue(info.steps.isEmpty)
        }
    }

    func testRetryAndOrdinaryDisconnectDoNotKeepPreviousFailure() {
        var progress = ConnectionProgress()
        progress.finish(issue: .connectionLost)
        progress.begin()
        XCTAssertNil(progress.issue)
        let finding = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: "Finding your Mac")
        XCTAssertEqual(finding.headerTitle, "Finding Mac…")
        XCTAssertFalse(finding.isProblem)
        progress.finish(issue: .setupFailed)
        progress.finish()
        let disconnected = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: "Disconnected")
        XCTAssertEqual(disconnected.headerTitle, "Not connected")
        XCTAssertFalse(disconnected.isProblem)
        XCTAssertNil(progress.issue)
    }

    func testConnectedWithoutInputPermissionExplainsMacAccessibilityApproval() {
        var progress = ConnectionProgress()
        progress.establish()
        let message = "Connected · enable Accessibility in the Mac app"
        let blocked = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: message)
        XCTAssertEqual(blocked.headerTitle, "Approval needed")
        XCTAssertEqual(blocked.detail, message)
        XCTAssertTrue(blocked.isProblem)
        XCTAssertTrue(blocked.steps.joined().contains("Privacy & Security → Accessibility"))
        XCTAssertTrue(blocked.steps.joined().contains("On your Mac"))
        let approved = progress.presentation(paired: true, inputAllowed: true, mode: .usb, status: "Connected")
        XCTAssertFalse(approved.isProblem)
        XCTAssertFalse(approved.steps.joined().contains("Accessibility"))
    }

    func testUnknownTransportErrorIsKeptVerbatimWithoutInventingACause() {
        var progress = ConnectionProgress()
        progress.finish(issue: .connectionLost)
        let reported = "Connection failed: Opaque transport error 52. Tap Connect to try again."
        let info = progress.presentation(paired: true, inputAllowed: false, mode: .wifi, status: reported)
        XCTAssertEqual(info.detail, reported)
        XCTAssertEqual(info.headerTitle, "Connection lost")
        XCTAssertTrue(info.isProblem)
        let copy = ([info.detail] + info.steps).joined(separator: " ").lowercased()
        XCTAssertFalse(copy.contains("password"))
        XCTAssertFalse(copy.contains("authentication failed"))
        XCTAssertFalse(copy.contains("permission denied"))
        XCTAssertFalse(copy.contains("firewall blocked"))
    }

    func testAdviceMatchesChosenTransportAndDoesNotSuggestAutomaticFallback() {
        var progress = ConnectionProgress()
        progress.finish(issue: .notFound)
        let wired = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: "Mac not found")
        let wireless = progress.presentation(paired: true, inputAllowed: false, mode: .wifi, status: "Mac not found")
        XCTAssertTrue(wired.steps.joined().contains("USB-C data cable"))
        XCTAssertTrue(wired.steps.joined().contains("does not switch to Wi-Fi automatically"))
        XCTAssertFalse(wireless.steps.joined().contains("data cable"))
        XCTAssertTrue(wireless.steps.joined().contains("same Wi-Fi network"))
        XCTAssertTrue(wired.steps.joined().contains("Local Network"))
        XCTAssertTrue(wireless.steps.joined().contains("Local Network"))
    }

    func testKnownConnectionStagesAndUnpairedStateHaveUsefulDetails() {
        var progress = ConnectionProgress()
        let unpaired = progress.presentation(paired: false, inputAllowed: false, mode: .usb, status: "Not connected")
        XCTAssertEqual(unpaired.headerTitle, "Pair your Mac")
        XCTAssertFalse(unpaired.isProblem)
        XCTAssertTrue(unpaired.steps.joined().contains("scan the code"))
        let stages: [(ConnectionStage, String, Bool)] = [
            (.authenticating, "Securing connection…", false),
            (.configuring, "Starting session…", false),
            (.waitingForNetwork, "Connection waiting…", true)
        ]
        for (stage, title, problem) in stages {
            progress.advance(to: stage)
            let info = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: "Original detail")
            XCTAssertEqual(info.headerTitle, title)
            XCTAssertEqual(info.detail, "Original detail")
            XCTAssertEqual(info.isProblem, problem)
        }
    }

    func testVersionMismatchProvidesUpdateAdviceInsteadOfNetworkDiagnosis() {
        var progress = ConnectionProgress()
        progress.finish(issue: .versionMismatch)
        let info = progress.presentation(paired: true, inputAllowed: false, mode: .usb, status: "App versions differ.")
        XCTAssertEqual(info.headerTitle, "Update needed")
        XCTAssertTrue(info.steps.joined().contains("Update both"))
        XCTAssertFalse(info.steps.joined().contains("Local Network"))
    }
}
