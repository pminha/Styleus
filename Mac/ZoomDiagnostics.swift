import AppKit
import WebKit

/// An explicitly started test of Styleus's own event output in disposable content.
/// The local monitor observes tagged magnify events without consuming them.
final class ZoomDiagnostics: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let shared = ZoomDiagnostics()
    static let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("Styleus-direct-zoom.csv")
    private let output = MouseOutput()
    private var window: NSWindow?
    private var web: WKWebView?
    private var monitor: Any?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObserver: NSObjectProtocol?
    private var prepareToRun: (() -> Void)?
    private var inputIsStopped: (() -> Bool)?
    private var ready = false
    private var running = false
    private var gestureOpen = false
    private var startedAt = 0.0
    private var previousTick = 0.0
    private var endedAt: TimeInterval?
    private var sentChanges = 0
    private var received = 0
    private var initialScale = 1.0
    private var latestPhase = "none"
    private var originalPointer: CGPoint?
    private var rows: [String] = []
    private var status = NSTextField(labelWithString: "Loading local test page…")
    private var readout = NSTextField(labelWithString: "Received 0 events · phase none · scale 1.0000")
    private var runButton = NSButton()
    private var stopButton = NSButton()

    func show(prepareToRun: @escaping () -> Void, inputIsStopped: @escaping () -> Bool) {
        self.prepareToRun = prepareToRun
        self.inputIsStopped = inputIsStopped
        if let window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Styleus — Native Pinch Zoom Test"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        let root = NSView()
        window.contentView = root
        let instructions = NSTextField(wrappingLabelWithString: "Run a half-second native zoom sequence in this disposable page. Remote iPad control stops first. Keep this window in front; changing focus or closing it cancels the test. No keyboard shortcuts or external helper are used.")
        runButton = NSButton(title: "Run Native Zoom Test", target: self, action: #selector(startTest))
        runButton.isEnabled = false
        stopButton = NSButton(title: "Stop Test", target: self, action: #selector(stopTest))
        stopButton.isEnabled = false
        let buttons = NSStackView(views: [runButton, stopButton])
        buttons.orientation = .horizontal; buttons.spacing = 12
        status = NSTextField(wrappingLabelWithString: "Loading local test page…")
        readout = NSTextField(labelWithString: "Received 0 events · phase none · scale 1.0000")
        readout.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.allowsMagnification = true
        web.navigationDelegate = self
        self.web = web
        for view in [instructions, buttons, readout, status, web] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            instructions.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            instructions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            instructions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
            buttons.leadingAnchor.constraint(equalTo: instructions.leadingAnchor),
            readout.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 12),
            readout.leadingAnchor.constraint(equalTo: instructions.leadingAnchor),
            readout.trailingAnchor.constraint(equalTo: instructions.trailingAnchor),
            status.topAnchor.constraint(equalTo: readout.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: instructions.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: instructions.trailingAnchor),
            web.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.running, self.window?.isKeyWindow == true,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ZoomEventEncoder.eventTag else { return event }
            self.received += 1
            self.latestPhase = Self.phaseName(event.phase)
            self.record("received", phase: self.latestPhase, magnification: Double(event.magnification))
            self.updateReadout()
            return event // WebKit must handle the native event itself.
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.complete("Window changed; test cancelled", cancel: true)
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.complete("App lost focus; test cancelled", cancel: true)
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.complete("Mac interrupted; test cancelled", cancel: true)
            })
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                                           object: nil, queue: .main) { [weak self] _ in
            self?.complete("Mac locked; test cancelled", cancel: true)
        }
        web.loadHTMLString(Self.page, baseURL: nil)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func startTest() {
        guard !running, ready, let window, let web else { return }
        prepareToRun?()
        guard inputIsStopped?() == true else { status.stringValue = "Stop remote input before running this test."; return }
        guard output.permitted else { status.stringValue = "Enable Accessibility for this copy of Styleus, then try again."; return }
        guard output.zoomAvailable else { status.stringValue = "Native zoom construction is unavailable on this Mac."; return }
        guard ownsFocus else { status.stringValue = "Bring this test window to the front before running."; return }
        window.makeFirstResponder(web)
        let center = window.convertPoint(toScreen: web.convert(NSPoint(x: web.bounds.midX, y: web.bounds.midY), to: nil))
        guard let top = NSScreen.screens.first?.frame.maxY,
              let pointer = CGEvent(source: nil)?.location else { status.stringValue = "Could not locate the test page."; return }
        originalPointer = pointer
        guard CGWarpMouseCursorPosition(CGPoint(x: center.x, y: top - center.y)) == .success else {
            originalPointer = nil; status.stringValue = "Could not place the pointer over the test page."; return
        }
        startedAt = ProcessInfo.processInfo.systemUptime; previousTick = startedAt
        endedAt = nil; sentChanges = 0; received = 0; latestPhase = "none"
        initialScale = web.magnification
        rows = ["kind,elapsed,phase,magnification,scale"]
        running = true; gestureOpen = true
        runButton.isEnabled = false; stopButton.isEnabled = true
        status.stringValue = "Testing native delivery. Keep this window in front."
        post(ZoomSample(phase: .began))
        updateReadout()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    private var ownsFocus: Bool {
        NSApp.isActive && window?.isKeyWindow == true &&
            NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard ownsFocus, inputIsStopped?() == true, output.permitted else {
            complete("Focus, permission or remote-input state changed; test cancelled", cancel: true); return
        }
        guard now - previousTick <= 0.15, now - startedAt <= 3 else {
            complete("Test scheduling interrupted; test cancelled", cancel: true); return
        }
        previousTick = now
        if sentChanges < 30 {
            post(ZoomSample(magnification: 0.022, phase: .changed))
            sentChanges += 1
        } else if endedAt == nil {
            post(ZoomSample(phase: .ended)); gestureOpen = false; endedAt = now
        }
        record("observed", phase: latestPhase)
        updateReadout()
        if let endedAt, now - endedAt >= 0.5 {
            let changed = abs((web.map { Double($0.magnification) } ?? initialScale) - initialScale) > 0.00001
            complete(changed ? "WebKit magnification changed" : "No WebKit magnification change observed", cancel: false)
        }
    }

    private func post(_ sample: ZoomSample) {
        record("posted", phase: sample.phase.rawValue, magnification: sample.magnification)
        output.post([.zoom(sample)])
    }

    private func record(_ kind: String, phase: String, magnification: Double = 0) {
        guard running, rows.count < 1000 else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let scale = web.map { Double($0.magnification) } ?? initialScale
        guard elapsed.isFinite, magnification.isFinite, scale.isFinite else { return }
        rows.append([kind, String(format: "%.6f", elapsed), phase,
                     String(format: "%.9f", magnification), String(format: "%.9f", scale)].joined(separator: ","))
    }

    private func updateReadout() {
        readout.stringValue = "Received \(received) events · phase \(latestPhase) · scale \(String(format: "%.4f", web?.magnification ?? 1))"
    }

    @objc private func stopTest() { complete("Stopped by user", cancel: true) }

    private func complete(_ message: String, cancel: Bool) {
        guard running else { return }
        timer?.invalidate(); timer = nil
        if gestureOpen { post(ZoomSample(phase: .cancelled)); gestureOpen = false }
        record("result", phase: cancel ? "cancelled" : "completed")
        running = false
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        originalPointer = nil
        runButton.isEnabled = ready; stopButton.isEnabled = false
        updateReadout()
        do {
            try (rows.joined(separator: "\n") + "\n").write(to: Self.reportURL, atomically: true, encoding: .utf8)
            status.stringValue = "\(message). Saved \(received) received events to Styleus-direct-zoom.csv."
        } catch { status.stringValue = "\(message). Could not save the diagnostic report." }
    }

    func finish() {
        complete("Test window closed", cancel: true)
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers.removeAll()
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }; lockObserver = nil
        web?.navigationDelegate = nil
        window?.delegate = nil
        web = nil; window = nil; prepareToRun = nil; inputIsStopped = nil; ready = false
    }

    func windowWillClose(_ notification: Notification) { finish() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true; runButton.isEnabled = true
        status.stringValue = "Ready. Each run zooms from the current scale; close and reopen for a fresh page."
        updateReadout()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }

    private static func phaseName(_ phase: NSEvent.Phase) -> String {
        if phase.contains(.cancelled) { return "cancelled" }
        if phase.contains(.ended) { return "ended" }
        if phase.contains(.began) { return "began" }
        if phase.contains(.changed) { return "changed" }
        return "none"
    }

    private static let page = """
    <!doctype html><meta charset="utf-8"><title>Styleus native zoom test</title>
    <style>
    html { color-scheme: light dark; font: 22px system-ui; }
    body { margin: 0; width: 1800px; min-height: 1400px;
      background: repeating-linear-gradient(0deg, #80808018 0 1px, transparent 1px 48px),
                  repeating-linear-gradient(90deg, #80808018 0 1px, transparent 1px 48px); }
    main { padding: 70px; max-width: 900px; }
    h1 { font-size: 56px; } p { line-height: 1.6; }
    .shape { width: 200px; height: 200px; border: 10px solid #458c9d; border-radius: 50%; margin-top: 60px; }
    </style><main><h1>Styleus native zoom</h1><p>This is disposable local content.
    The grid and circle should grow when WebKit receives native magnification events.
    No script changes the page scale.</p><div class="shape"></div></main>
    """
}
