import AppKit
import WebKit

/// Opt-in diagnostics for this app's disposable test page. No global event
/// monitor, keyboard capture, external page content, or additional permissions.
final class ScrollDiagnostics: NSObject, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = ScrollDiagnostics()
    static let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("styleus-scroll-diagnostics.csv")
    private static let columns = ["kind", "time", "event_time", "tag", "source_pid", "phase", "momentum", "precise",
                                  "dx", "dy", "line_x", "line_y", "fixed_x", "fixed_y", "point_x", "point_y",
                                  "page_x", "page_y", "wheel_mode"]
    private var window: NSWindow?
    private var web: WKWebView?
    private var monitor: Any?
    private var timer: Timer?
    private var recording = false
    private var startedAt = 0.0
    private var serial: Int64 = 0
    private var rows: [String] = []
    private var status = NSTextField(labelWithString: "Ready")
    private var recordButton = NSButton()

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Styleus — Scrolling Test"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        let root = NSView()
        window.contentView = root
        let instructions = NSTextField(wrappingLabelWithString: "Click Start Recording. Scroll the page below with the iPad: a slow slide, then a fast flick. Repeat with the Mac trackpad, then click Stop Recording. Only this test's scroll timing and movement are saved.")
        recordButton = NSButton(title: "Start Recording", target: self, action: #selector(toggleRecording))
        status = NSTextField(labelWithString: "Loading test page…")
        status.lineBreakMode = .byTruncatingMiddle
        let header = NSStackView(views: [recordButton, status])
        header.orientation = .horizontal; header.spacing = 12
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "scrollTrace")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        self.web = web
        for view in [instructions, header, web] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            instructions.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            instructions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            instructions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: instructions.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: instructions.trailingAnchor),
            web.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.recording, event.window === self.window else { return event }
            self.record(event: event, kind: "app-received")
            return event
        }
        web.loadHTMLString(Self.page, baseURL: nil)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func willPost(_ sample: ScrollSample, event: CGEvent) {
        guard recording else { return }
        serial += 1
        let tag = 0x5354594C00000000 | serial
        event.setIntegerValueField(.eventSourceUserData, value: tag)
        append("input", ["tag": String(tag), "phase": sample.phase.rawValue,
                         "dx": String(sample.delta.x), "dy": String(sample.delta.y)])
        if let native = NSEvent(cgEvent: event) { record(event: native, kind: "posted") }
    }

    private func record(event: NSEvent, kind: String) {
        var fields = ["event_time": String(event.timestamp), "phase": String(event.phase.rawValue),
                      "momentum": String(event.momentumPhase.rawValue), "precise": event.hasPreciseScrollingDeltas ? "1" : "0",
                      "dx": String(Double(event.scrollingDeltaX)), "dy": String(Double(event.scrollingDeltaY))]
        if let cg = event.cgEvent {
            for (name, field): (String, CGEventField) in [
                ("tag", .eventSourceUserData), ("source_pid", .eventSourceUnixProcessID),
                ("line_x", .scrollWheelEventDeltaAxis2), ("line_y", .scrollWheelEventDeltaAxis1),
                ("point_x", .scrollWheelEventPointDeltaAxis2), ("point_y", .scrollWheelEventPointDeltaAxis1)
            ] { fields[name] = String(cg.getIntegerValueField(field)) }
            fields["fixed_x"] = String(cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
            fields["fixed_y"] = String(cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        }
        append(kind, fields)
    }

    private func append(_ kind: String, _ fields: [String: String]) {
        guard recording else { return }
        guard rows.count < 20000 else { finish(); return }
        var fields = fields
        fields["kind"] = kind
        fields["time"] = String(ProcessInfo.processInfo.systemUptime)
        // All values are fixed labels or numeric strings, never page/user content.
        rows.append(Self.columns.map { fields[$0] ?? "" }.joined(separator: ","))
    }

    @objc private func toggleRecording() {
        if recording { finish(); return }
        rows = [Self.columns.joined(separator: ",")]
        serial = 0; startedAt = ProcessInfo.processInfo.systemUptime; recording = true
        recordButton.title = "Stop Recording"
        status.stringValue = "Recording · scroll below with the iPad, then the Mac trackpad"
        web?.evaluateJavaScript("window.scrollTo(1000, 10000)")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.startedAt
            if elapsed >= 60 { self.finish() }
            else { self.status.stringValue = "Recording · \(Int(elapsed)) seconds · \(self.rows.count - 1) samples" }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    func finish() {
        guard recording else { return }
        recording = false; timer?.invalidate(); timer = nil
        recordButton.title = "Start Recording"
        do {
            try (rows.joined(separator: "\n") + "\n").write(to: Self.reportURL, atomically: true, encoding: .utf8)
            status.stringValue = "Saved \(rows.count - 1) samples. You can close this test window."
        } catch { status.stringValue = "Could not save the test: \(error.localizedDescription)" }
    }

    func windowWillClose(_ notification: Notification) {
        finish()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "scrollTrace")
        web?.navigationDelegate = nil; web = nil; window = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status.stringValue = "Ready · pointer over the striped page when scrolling"
        webView.evaluateJavaScript("window.scrollTo(1000, 10000)")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard recording, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let kind = body["kind"] as? String,
              kind == "web-wheel" || kind == "web-scroll" else { return }
        var fields: [String: String] = [:]
        for name in ["event_time", "dx", "dy", "page_x", "page_y", "wheel_mode"] {
            if let number = body[name] as? NSNumber, number.doubleValue.isFinite {
                fields[name] = String(number.doubleValue)
            }
        }
        append(kind, fields)
    }

    private static let page = """
    <!doctype html><meta charset="utf-8"><title>Styleus scrolling test</title>
    <style>
    html { scroll-behavior: auto; color-scheme: light dark; }
    body { margin: 0; width: 3200px; font: 18px system-ui; }
    .row { height: 100px; box-sizing: border-box; border-bottom: 1px solid #888; padding: 35px 20px; }
    .row:nth-child(even) { background: #80808022; }
    .row span { display: inline-block; width: 400px; }
    </style><main id="page"></main>
    <script>
    const page = document.getElementById('page');
    for (let row = 0; row < 400; row++) {
      const line = document.createElement('div'); line.className = 'row';
      for (let column = 0; column < 8; column++) {
        const cell = document.createElement('span');
        cell.textContent = `Row ${row + 1} · Column ${column + 1}`; line.appendChild(cell);
      }
      page.appendChild(line);
    }
    function report(kind, event) {
      window.webkit.messageHandlers.scrollTrace.postMessage({kind,
        event_time: event.timeStamp / 1000, dx: event.deltaX || 0, dy: event.deltaY || 0,
        wheel_mode: event.deltaMode || 0, page_x: window.scrollX, page_y: window.scrollY});
    }
    window.addEventListener('wheel', e => report('web-wheel', e), {passive: true});
    window.addEventListener('scroll', e => report('web-scroll', e), {passive: true});
    </script>
    """
}
