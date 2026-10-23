import Foundation
import Combine
import Network
import UIKit

final class PadModel: ObservableObject {
    @Published var status = "Not connected"
    @Published var connected = false
    @Published var connecting = false
    @Published var inputAllowed = false
    @Published var zoomAvailable = false
    @Published var paired = false
    @Published var mode: InputMode = .trackpad
    @Published var dragActive = false
    @Published var target: TargetDescription?
    @Published var inputRevision: UInt64 = 0
    @Published var error: String?
    @Published private(set) var connectionMode = ConnectionMode(rawValue: UserDefaults.standard.string(forKey: "connectionMode") ?? "") ?? .usb
    @Published private(set) var activeConnection: ConnectionMode?
    @Published private(set) var roundTripMilliseconds: Double?
    @Published private(set) var timingSampleCount = 0
    @Published private var connectionProgress = ConnectionProgress()
    var connectionPresentation: ConnectionPresentation {
        connectionProgress.presentation(paired: paired, inputAllowed: inputAllowed,
                                        mode: activeConnection ?? connectionMode, status: status)
    }
    private var credential: PairingCredential?
    private var browser: NWBrowser?
    private var channel: MessageChannel?
    private var candidates: [UUID: MessageChannel] = [:]
    private var attemptedInterfaces: Set<Int> = []
    private var state: ServerState?
    private var sequence: UInt64 = 0
    private var lastStateAt: TimeInterval = 0
    private var attemptAt: TimeInterval = 0
    private var pendingDrag: (UInt64, Bool)?
    private var timer: Timer?
    private var statusTimer: Timer?
    private var pencilStatus = PencilStatusRelay()
    private var ticks = 0
    private var timing: RoundTripMeasurement?

    init() {
        ConnectionTrace.note("iPad app started")
        do { credential = try PairingStore.load(); paired = credential != nil }
        catch { self.error = error.localizedDescription }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    @discardableResult
    func pair(_ code: String) -> Bool {
        do {
            let credential = try PairingCredential.parse(code)
            disconnect()
            try PairingStore.save(credential)
            self.credential = credential; paired = true; status = "Paired. Tap Connect when the Mac is listening."
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func forget() {
        disconnect()
        do {
            try PairingStore.forget(); credential = nil; paired = false
        } catch { self.error = error.localizedDescription }
    }

    func connect() {
        guard !connected, !connecting, let credential else { return }
        let requestedMode = connectionMode
        inputRevision += 1; sequence = 0; state = nil; dragActive = false
        attemptedInterfaces.removeAll()
        attemptAt = ProcessInfo.processInfo.systemUptime
        connecting = true; connectionProgress.begin()
        status = "Finding your Mac · \(requestedMode.title)…"
        ConnectionTrace.note("Discovering paired Mac via \(requestedMode.title)")
        let browser = NWBrowser(for: .bonjour(type: LocalTransport.serviceType, domain: "local."),
                                using: LocalTransport.browserParameters(mode: requestedMode))
        self.browser = browser
        browser.stateUpdateHandler = { [weak self, weak browser] newState in
            guard let self, self.browser === browser else { return }
            switch newState {
            case .failed(let error): self.disconnect("Discovery failed: \(error.localizedDescription)", issue: .discoveryFailed)
            case .waiting(let error):
                self.connectionProgress.advance(to: .waitingForNetwork)
                self.status = "Discovery is waiting: \(error.localizedDescription)"
            case .ready:
                if self.connectionProgress.stage == .waitingForNetwork {
                    self.connectionProgress.advance(to: .finding)
                    self.status = "Finding your Mac · \(requestedMode.title)…"
                }
            default: break
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, self.browser === browser, self.channel == nil else { return }
            guard let found = results.first(where: {
                if case .service(let name, _, let domain, _) = $0.endpoint {
                    return name == credential.serviceName && (domain == "local." || domain == "local")
                        && $0.interfaces.contains(where: { $0.type == requestedMode.interfaceType })
                }
                return false
            }) else { return }
            ConnectionTrace.note("Paired Mac discovered after \(ProcessInfo.processInfo.systemUptime - self.attemptAt) seconds")
            guard case .service(let name, let type, let domain, _) = found.endpoint else { return }
            ConnectionTrace.note("Discovery interfaces: \(found.interfaces.map { "\($0.name):\($0.type)" }.joined(separator: ", "))")
            // Bonjour can report more than one wired interface. Scope each bounded candidate
            // explicitly; unscoped resolution can stall even with a satisfied generic path.
            for interface in found.interfaces where interface.type == requestedMode.interfaceType {
                guard self.candidates.count < 4, !self.attemptedInterfaces.contains(interface.index) else { continue }
                self.attemptedInterfaces.insert(interface.index)
                ConnectionTrace.note("Trying service on \(interface.name):\(interface.type)")
                let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: interface)
                self.open(endpoint, credential: credential, mode: requestedMode)
            }
        }
        browser.start(queue: .main)
    }

    private func open(_ endpoint: NWEndpoint, credential: PairingCredential, mode: ConnectionMode) {
        attemptAt = ProcessInfo.processInfo.systemUptime
        connectionProgress.advance(to: .authenticating)
        status = "Authenticating paired Mac…"
        let channel = MessageChannel(NWConnection(to: endpoint, using: LocalTransport.parameters(credential, mode: mode)))
        let candidateID = UUID()
        candidates[candidateID] = channel
        channel.onReady = { [weak self, weak channel] in
            guard let self, let channel, self.candidates[candidateID] === channel else { return }
            guard LocalTransport.mode(for: channel.connection.currentPath) == mode else {
                channel.close("The selected connection is unavailable. \(mode.discoveryHelp)"); return
            }
            self.connectionProgress.advance(to: .configuring)
            self.status = "Secure connection open; waiting for Mac configuration…"
        }
        channel.onPathChange = { [weak self, weak channel] path in
            guard let self, let channel, self.channel === channel || self.candidates[candidateID] === channel else { return }
            if LocalTransport.mode(for: path) != mode {
                channel.close("The selected connection was lost. Tap Connect when ready.")
            }
        }
        channel.onMessage = { [weak self, weak channel] message in
            guard let self, let channel, self.channel === channel || self.candidates[candidateID] === channel else { return }
            if case .pong(let probe) = message {
                guard self.channel === channel else { return }
                if let sample = self.timing?.accept(probe, now: ProcessInfo.processInfo.systemUptime) {
                    self.roundTripMilliseconds = self.timing?.median
                    self.timingSampleCount = self.timing?.milliseconds.count ?? 0
                    ConnectionTrace.note(String(format: "%@ round trip %.1f ms; recent median %.1f ms (%d samples)",
                        mode.title, sample, self.roundTripMilliseconds ?? sample, self.timingSampleCount))
                }
                return
            }
            guard case .state(let received) = message else {
                self.disconnect("The Mac sent an unsupported message.", issue: .invalidMessage); return
            }
            guard received.version == WireProtocol.version else {
                self.disconnect("App versions differ. Update both apps, then quit and reopen the Mac companion.", issue: .versionMismatch); return
            }
            guard received.target.rect.isValid,
                  received.target.rect.width <= 100000, received.target.rect.height <= 100000 else {
                self.disconnect("The Mac sent an unsupported configuration.", issue: .invalidConfiguration); return
            }
            if let current = self.state, current.session != received.session {
                self.disconnect("The Mac session changed. Tap Connect to start safely.", issue: .sessionChanged); return
            }
            let first = self.state == nil
            if first {
                // The first authenticated configuration wins, not the first client TLS callback:
                // the Mac may admit a different candidate when handshakes finish together.
                self.candidates.removeValue(forKey: candidateID)
                self.channel = channel; self.activeConnection = mode
                self.closeCandidates()
                self.browser?.cancel(); self.browser = nil
                ConnectionTrace.note("First Mac configuration received")
                self.timing = RoundTripMeasurement(session: received.session)
            }
            let changedGeometry = self.state?.geometry != received.geometry
            let permissionChanged = self.state?.inputAllowed != received.inputAllowed
            let zoomChanged = self.state?.zoomAvailable != received.zoomAvailable
            self.state = received
            self.lastStateAt = ProcessInfo.processInfo.systemUptime
            self.target = received.target
            if changedGeometry || permissionChanged || zoomChanged { self.inputRevision += 1 }
            self.connected = true; self.connecting = false
            self.connectionProgress.establish()
            self.inputAllowed = received.inputAllowed
            self.zoomAvailable = received.zoomAvailable
            self.status = received.inputAllowed ? "Connected · encrypted \(mode.title)" : "Connected · enable Accessibility in the Mac app"
            if let pending = self.pendingDrag, received.acknowledgedSequence < pending.0 {
                self.dragActive = pending.1
            } else {
                self.pendingDrag = nil; self.dragActive = received.dragActive
            }
            if first || changedGeometry || permissionChanged || zoomChanged {
                self.send(.cancel)
                self.send(.mode(self.mode))
            }
            if first { self.sendTimingProbe(); self.startStatusTimer() }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        channel.onClose = { [weak self, weak channel] reason in
            guard let self, let channel else { return }
            if self.channel === channel {
                self.channel = nil; self.clearSession(reason + " Tap Connect to try again.", issue: .connectionLost)
            } else if self.candidates.removeValue(forKey: candidateID) != nil,
                      self.channel == nil, self.candidates.isEmpty {
                self.clearSession(reason + " Tap Connect to try again.", issue: .setupFailed)
            }
        }
        channel.start()
    }

    func send(_ action: InputAction) {
        switch action {
        case .cancel, .mode: pencilStatus.update(.inactive)
        default: break
        }
        guard connected, let state, let channel, !channel.closed else { return }
        // Never stamp old queued actions with a new lease: input is sent immediately or the session closes.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastStateAt <= SessionGate.leaseLifetime else {
            disconnect("Connection stalled; input stopped.", issue: .stalled); return
        }
        sequence += 1
        if case .drag(let held) = action { pendingDrag = (sequence, held); dragActive = held }
        if action == .cancel { pendingDrag = (sequence, false); dragActive = false }
        channel.send(.input(InputPacket(session: state.session, lease: state.lease, geometry: state.geometry,
                                        sequence: sequence, action: action, pencilStatus: pencilStatus.latest)))
        pencilStatus.markSent(at: now)
    }

    func updatePencilStatus(_ status: PencilStatus, revision: UInt64) {
        guard connected, inputAllowed, revision == inputRevision else { return }
        pencilStatus.update(status)
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        let timer = Timer(timeInterval: PencilStatusRelay.interval, repeats: true) { [weak self] _ in
            guard let self, self.connected,
                  self.pencilStatus.needsUpdate(at: ProcessInfo.processInfo.systemUptime) else { return }
            self.send(.heartbeat)
        }
        RunLoop.main.add(timer, forMode: .common); statusTimer = timer
    }

    func sendSurface(_ action: InputAction, revision: UInt64) {
        // A UIKit view may briefly outlive a SwiftUI configuration update. Reject its old callbacks.
        guard revision == inputRevision else { return }
        send(action)
    }

    func changeMode(_ value: InputMode) {
        guard mode != value else { return }
        send(.cancel); mode = value; inputRevision += 1
        send(.mode(value))
    }

    func resetContact() { send(.cancel); inputRevision += 1 }

    func changeConnectionMode(_ mode: ConnectionMode) {
        guard connectionMode != mode else { return }
        disconnect("\(mode.title) selected. Tap Connect when ready.")
        connectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "connectionMode")
    }

    private func sendTimingProbe() {
        guard connected, let probe = timing?.begin(now: ProcessInfo.processInfo.systemUptime) else { return }
        channel?.send(.ping(probe))
    }

    private func tick() {
        ticks += 1
        let now = ProcessInfo.processInfo.systemUptime
        if connected && now - lastStateAt > SessionGate.leaseLifetime { disconnect("Mac stopped responding; input stopped.", issue: .stalled) }
        if connecting && now - attemptAt > (candidates.isEmpty ? 12 : 20) {
            disconnect(candidates.isEmpty
                ? "Mac not found. \(connectionMode.discoveryHelp)"
                : "The Mac did not finish connection setup. Disconnect and start listening again on the Mac.",
                issue: candidates.isEmpty ? .notFound : .setupFailed)
        }
        if connected && ticks % 2 == 0 { send(.heartbeat) }
        if connected && ticks % 10 == 0 { sendTimingProbe() }
    }

    func disconnect(_ reason: String = "Disconnected", issue: ConnectionIssue? = nil) {
        sendCancelBeforeClosing()
        browser?.stateUpdateHandler = nil; browser?.browseResultsChangedHandler = nil
        browser?.cancel(); browser = nil
        let old = channel; channel = nil
        old?.close(reason)
        closeCandidates()
        clearSession(reason, issue: issue)
    }

    private func sendCancelBeforeClosing() {
        pencilStatus.update(.inactive)
        guard let state, let channel, connected else { return }
        sequence += 1
        channel.send(.input(InputPacket(session: state.session, lease: state.lease, geometry: state.geometry,
                                        sequence: sequence, action: .cancel)))
    }

    private func clearSession(_ reason: String, issue: ConnectionIssue? = nil) {
        statusTimer?.invalidate(); statusTimer = nil; pencilStatus = PencilStatusRelay()
        ConnectionTrace.note("iPad session cleared: \(reason)")
        browser?.stateUpdateHandler = nil; browser?.browseResultsChangedHandler = nil
        browser?.cancel(); browser = nil
        closeCandidates(); attemptedInterfaces.removeAll()
        state = nil; sequence = 0; pendingDrag = nil; target = nil
        timing = nil; roundTripMilliseconds = nil; timingSampleCount = 0; activeConnection = nil
        connected = false; connecting = false; inputAllowed = false; zoomAvailable = false; dragActive = false; status = reason
        connectionProgress.finish(issue: issue)
        inputRevision += 1; UIApplication.shared.isIdleTimerDisabled = false
    }

    private func closeCandidates() {
        let old = Array(candidates.values)
        candidates.removeAll()
        old.forEach { $0.close() }
    }
}
