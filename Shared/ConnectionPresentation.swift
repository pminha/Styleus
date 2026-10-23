/// User-facing connection information, kept separate from the input/session state.
struct ConnectionPresentation: Equatable {
    var headerTitle: String
    var detail: String
    var steps: [String]
    var isProblem: Bool
}

enum ConnectionStage: Equatable {
    case idle, finding, waitingForNetwork, authenticating, configuring, connected
}

/// Known failure sites, rather than guesses based on the wording of an error.
enum ConnectionIssue: Equatable {
    case discoveryFailed, notFound, setupFailed, versionMismatch
    case invalidMessage, invalidConfiguration, sessionChanged, connectionLost, stalled, interrupted
}

struct ConnectionProgress: Equatable {
    private(set) var stage: ConnectionStage = .idle
    private(set) var issue: ConnectionIssue?

    mutating func begin() { advance(to: .finding) }
    mutating func advance(to stage: ConnectionStage) {
        self.stage = stage
        issue = nil
    }
    mutating func establish() { advance(to: .connected) }
    mutating func finish(issue: ConnectionIssue? = nil) {
        stage = .idle
        self.issue = issue
    }

    func presentation(paired: Bool, inputAllowed: Bool, mode: ConnectionMode, status: String) -> ConnectionPresentation {
        if stage == .connected {
            if inputAllowed {
                return ConnectionPresentation(headerTitle: "Connected · encrypted \(mode.title)",
                                              detail: status, steps: [], isProblem: false)
            }
            return ConnectionPresentation(headerTitle: "Approval needed", detail: status, steps: [
                "On your Mac, open System Settings → Privacy & Security → Accessibility and enable Styleus.",
                "If Styleus is already enabled, quit and reopen the Mac companion, then reconnect the iPad."
            ], isProblem: true)
        }

        if let issue {
            let title: String
            let steps: [String]
            switch issue {
            case .discoveryFailed:
                title = "Discovery failed"
                steps = connectionChecks(mode)
            case .notFound:
                title = "Mac not found"
                steps = connectionChecks(mode)
            case .setupFailed:
                title = "Connection failed"
                steps = ["Disconnect and start listening again in the Mac companion."] + connectionChecks(mode)
            case .versionMismatch:
                title = "Update needed"
                steps = ["Update both Styleus apps, then quit and reopen the Mac companion.", "Start listening on the Mac, then tap Connect on the iPad."]
            case .invalidMessage, .invalidConfiguration:
                title = "Connection stopped"
                steps = ["Quit and reopen both Styleus apps. Check that both have the latest update.", "Start listening on the Mac, then tap Connect on the iPad."]
            case .sessionChanged:
                title = "Reconnect needed"
                steps = ["Keep the Mac companion listening, then tap Connect on the iPad to start a new session."]
            case .connectionLost:
                title = "Connection lost"
                steps = connectionChecks(mode)
            case .stalled:
                title = "Connection interrupted"
                steps = connectionChecks(mode)
            case .interrupted:
                title = "Not connected"
                steps = ["Return to Styleus, keep the Mac companion listening, then tap Connect to start a new session."]
            }
            // Keep the reported message verbatim. The checklist offers checks, not a diagnosis.
            return ConnectionPresentation(headerTitle: title, detail: status, steps: steps, isProblem: true)
        }

        switch stage {
        case .finding:
            return ConnectionPresentation(headerTitle: "Finding Mac…", detail: status,
                                          steps: connectionChecks(mode), isProblem: false)
        case .waitingForNetwork:
            return ConnectionPresentation(headerTitle: "Connection waiting…", detail: status,
                                          steps: connectionChecks(mode), isProblem: true)
        case .authenticating:
            return ConnectionPresentation(headerTitle: "Securing connection…", detail: status,
                                          steps: ["Keep the Mac companion open and listening while the paired devices authenticate."], isProblem: false)
        case .configuring:
            return ConnectionPresentation(headerTitle: "Starting session…", detail: status,
                                          steps: ["Waiting for the Mac companion to confirm the display target and input permission."], isProblem: false)
        case .idle:
            if !paired {
                return ConnectionPresentation(headerTitle: "Pair your Mac", detail: status, steps: [
                    "In the Mac companion, choose Pair iPad or Show Pairing Code.",
                    "Tap Pair Mac on this iPad and scan the code shown on your own Mac, or enter its text code."
                ], isProblem: false)
            }
            return ConnectionPresentation(headerTitle: "Not connected", detail: status,
                                          steps: connectionChecks(mode), isProblem: false)
        case .connected:
            preconditionFailure("Connected state handled above")
        }
    }

    private func connectionChecks(_ mode: ConnectionMode) -> [String] {
        let link = mode == .usb
            ? "Check the USB-C data cable and unlock the iPad. Wired mode does not switch to Wi-Fi automatically."
            : "Check that the iPad and Mac are on the same Wi-Fi network."
        return [
            "Open the Mac companion and choose Start Listening.",
            link,
            "Check that Styleus has Local Network access in Settings on the iPad and System Settings on the Mac.",
            "Tap Connect on the iPad when ready."
        ]
    }
}
