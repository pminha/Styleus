import AppKit
import Combine
import Network

final class MacModel: ObservableObject {
    @Published var status = "Not connected"
    @Published var listening = false
    @Published var connected = false
    @Published var accessible = false
    @Published var paired = false
    @Published var pairingCode: String?
    @Published var displays: [DisplayChoice] = []
    @Published var selectedDisplay: UInt32 = 0
    @Published var target = TargetDescription(name: "No display", rect: Rect(x: 0, y: 0, width: 1, height: 1))
    @Published var inputMode: InputMode = .trackpad
    @Published var dragActive = false
    @Published var error: String?
    // The iPad header replaces the cursor ring. A new preference namespace makes
    // the old default ring opt-in once, then remembers any deliberate re-enabling.
    @Published var cursorIndicatorStyle = CursorIndicatorStyle(
        saved: UserDefaults.standard.string(forKey: "optionalCursorIndicatorStyle")) {
        didSet {
            UserDefaults.standard.set(cursorIndicatorStyle.rawValue, forKey: "optionalCursorIndicatorStyle")
            cursorIndicator.style = cursorIndicatorStyle
        }
    }
    private var credential: PairingCredential?
    private var listener: NWListener?
    private var pending: [UUID: MessageChannel] = [:]
    private var channel: MessageChannel?
    private var activeConnection: ConnectionMode?
    private var gate: SessionGate?
    private var geometry: UInt64 = 1
    private var engine = InputState()
    private let output = MouseOutput()
    private let cursorIndicator = CursorIndicator()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObserver: NSObjectProtocol?
    private var ticks = 0
    private var regionPicker: RegionPicker?
    let pressureProbe = PressureProbe()

    init() {
        cursorIndicator.style = cursorIndicatorStyle
        ConnectionTrace.note("Mac app started")
        do { credential = try PairingStore.load(); paired = credential != nil }
        catch { self.error = error.localizedDescription }
        refreshDisplays()
        accessible = output.permitted
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() })
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                self?.stop("Mac interrupted. Start listening again when ready.")
            })
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                                           object: nil, queue: .main) { [weak self] _ in self?.stop("Mac locked") }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    func requestAccessibility() { output.requestPermission() }

    func refreshDisplays() {
        let current = DisplayChoice.current()
        guard current != displays else { return }
        displays = current
        engine.displays = current.map(\.bounds)
        if !current.contains(where: { $0.id == selectedDisplay }) { selectedDisplay = current.first?.id ?? 0 }
        useWholeDisplay()
    }

    func useWholeDisplay() {
        guard let display = displays.first(where: { $0.id == selectedDisplay }) else {
            stop("No display available"); return
        }
        setTarget(TargetDescription(name: display.name, rect: display.bounds))
    }

    func chooseRegion() {
        guard let display = displays.first(where: { $0.id == selectedDisplay }) else { return }
        let resumeListening = listening
        stop("Choosing target region; reconnect after selection")
        regionPicker = RegionPicker(display: display) { [weak self] rect in
            guard let self else { return }
            if let rect, display.bounds.contains(rect) {
                self.setTarget(TargetDescription(name: display.name + " — custom region", rect: rect))
            }
            self.regionPicker = nil
            if resumeListening { self.startListening() }
        }
        regionPicker?.show()
    }

    private func setTarget(_ target: TargetDescription) {
        pressureProbe.cancel()
        release()
        self.target = target; engine.target = target.rect
        geometry += 1; gate?.changeGeometry(geometry)
        sendState()
    }

    func newPairing() {
        stop()
        do {
            let newCredential = try PairingCredential.create()
            try PairingStore.save(newCredential)
            credential = newCredential; paired = true; pairingCode = newCredential.code
            startListening()
        } catch { self.error = error.localizedDescription }
    }

    func showPairing() { pairingCode = credential?.code; startListening() }

    func forgetPairing() {
        stop()
        do {
            try PairingStore.forget()
            credential = nil; paired = false; pairingCode = nil
        } catch { self.error = error.localizedDescription }
    }

    func startListening() {
        guard !pressureProbe.running else { status = "Stop the pressure experiment before listening."; return }
        guard listener == nil, let credential else { return }
        do {
            let listener = try NWListener(using: LocalTransport.listenerParameters(credential), on: .any)
            self.listener = listener
            listening = true
            listener.service = NWListener.Service(name: credential.serviceName, type: LocalTransport.serviceType, domain: "local.")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready:
                    ConnectionTrace.note("Mac listener ready")
                    self.listening = true; self.status = "Waiting for paired iPad · USB-C / wired or Wi-Fi"
                case .failed(let error): self.stop("Local connection failed: \(error.localizedDescription)")
                case .waiting: self.status = "Waiting for a local connection / Local Network permission"
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            status = "Starting local connections…"
            listener.start(queue: .main)
        } catch { self.error = error.localizedDescription }
    }

    private func accept(_ connection: NWConnection) {
        ConnectionTrace.note("Mac received connection candidate")
        guard channel == nil, pending.count < 4 else { connection.cancel(); return }
        let id = UUID()
        let candidate = MessageChannel(connection)
        pending[id] = candidate
        candidate.onClose = { [weak self] _ in self?.pending.removeValue(forKey: id) }
        candidate.onReady = { [weak self, weak candidate] in
            guard let self, let candidate else { return }
            guard self.channel == nil else { candidate.close(); return }
            guard let mode = LocalTransport.mode(for: candidate.connection.currentPath) else {
                candidate.close("Only local wired or Wi-Fi connections are supported."); return
            }
            self.pending.removeValue(forKey: id)
            let others = Array(self.pending.values); self.pending.removeAll()
            others.forEach { $0.close() }
            self.establish(candidate, mode: mode)
        }
        candidate.start()
    }

    private func establish(_ channel: MessageChannel, mode: ConnectionMode) {
        ConnectionTrace.note("Mac established authenticated session via \(mode.title)")
        release()
        engine = InputState(); engine.target = target.rect; engine.displays = displays.map(\.bounds)
        gate = SessionGate(geometry: geometry, now: ProcessInfo.processInfo.systemUptime)
        self.channel = channel; activeConnection = mode; connected = true; inputMode = .trackpad
        pairingCode = nil
        updateConnectedStatus()
        channel.onPathChange = { [weak self, weak channel] path in
            guard let self, self.channel === channel else { return }
            if LocalTransport.mode(for: path) != mode {
                self.disconnect("Connection route changed; held buttons released")
            }
        }
        channel.onMessage = { [weak self, weak channel] message in
            guard let self, self.channel === channel else { return }
            if case .ping(let probe) = message {
                if let reply = self.gate?.reply(to: probe, now: ProcessInfo.processInfo.systemUptime) {
                    channel?.send(.pong(reply))
                }
                return
            }
            guard case .input(let packet) = message else { self.disconnect("Invalid message from iPad"); return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.gate?.accept(packet, now: now) == true else {
                // Geometry changes intentionally invalidate queued frames; no frame may hold input afterward.
                self.release(); return
            }
            guard self.output.permitted || packet.action == .heartbeat else {
                self.release(); return
            }
            self.engine.syncCursor(self.output.location)
            let postedLocation = self.output.post(self.engine.apply(packet.action))
            switch packet.action {
            case .cancel, .mode: self.cursorIndicator.clear()
            default:
                if self.output.permitted {
                    self.cursorIndicator.receive(packet.pencilStatus, buttonHeld: self.engine.leftHeld,
                                                 postedLocation: postedLocation, at: now)
                } else { self.cursorIndicator.clear() }
            }
            if self.inputMode != self.engine.mode { self.inputMode = self.engine.mode }
            if self.dragActive != self.engine.dragActive { self.dragActive = self.engine.dragActive }
        }
        channel.onClose = { [weak self, weak channel] reason in
            guard let self, self.channel === channel else { return }
            self.channel = nil; self.gate = nil; self.activeConnection = nil; self.connected = false
            self.release()
            self.status = "\(reason). Tap Connect on iPad when ready."
        }
        sendState()
    }

    private func tick() {
        ticks += 1
        let now = ProcessInfo.processInfo.systemUptime
        if gate?.expired(now: now) == true { disconnect("Input timed out; held buttons released") }
        if ticks % 2 == 0 { sendState() }
        if ticks % 5 == 0 {
            let allowed = output.permitted
            if accessible && !allowed { disconnect("Accessibility permission was removed") }
            accessible = allowed
            if connected { updateConnectedStatus() }
        }
    }

    private func updateConnectedStatus() {
        status = accessible ? "Connected · encrypted \(activeConnection?.title ?? "local connection")" : "Connected · Accessibility permission needed"
    }

    private func sendState() {
        guard let channel, gate != nil else { return }
        let lease = gate!.issueLease(now: ProcessInfo.processInfo.systemUptime)
        channel.send(.state(ServerState(session: gate!.session, lease: lease, geometry: geometry,
                                        target: target, dragActive: engine.dragActive,
                                        acknowledgedSequence: gate!.lastSequence, inputAllowed: output.permitted)))
    }

    private func release() {
        cursorIndicator.clear()
        output.post(engine.release()); dragActive = false
    }

    func disconnect(_ reason: String = "Disconnected by Mac") {
        release()
        channel?.close(reason)
        channel = nil; gate = nil; activeConnection = nil; connected = false
        status = reason
    }

    func stop(_ reason: String = "Stopped") {
        pressureProbe.cancel()
        disconnect(reason)
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil; listening = false
        let candidates = Array(pending.values); pending.removeAll()
        candidates.forEach { $0.close() }
    }

    func runPressureProbe() {
        guard let display = displays.first(where: { $0.id == selectedDisplay }), target.rect != display.bounds else {
            error = "First select a custom rectangle entirely inside a disposable blank Notability note."; return
        }
        stop("Pressure experiment; reconnect afterward")
        pressureProbe.start(region: target.rect)
    }
}
