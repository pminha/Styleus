import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

final class StyleusAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: MacModel?
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop("App quit"); ScrollDiagnostics.shared.finish()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct StyleusMacApp: App {
    @NSApplicationDelegateAdaptor(StyleusAppDelegate.self) var delegate
    @StateObject private var model = MacModel()
    var body: some Scene {
        WindowGroup("Styleus", id: "main") {
            MacContentView(model: model).onAppear { delegate.model = model }
        }.defaultSize(width: 640, height: 620)
        MenuBarExtra("Styleus", systemImage: model.connected ? "cursorarrow.rays" : "cursorarrow") { StyleusMenu(model: model) }
    }
}

struct MacContentView: View {
    @ObservedObject var model: MacModel
    @State private var confirmReplacement = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "cursorarrow.motionlines").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Styleus").font(.largeTitle.bold())
                    Text("Your iPad, your Mac trackpad and annotation tablet").foregroundStyle(.secondary)
                }
            }
            HStack {
                Circle().fill(model.connected ? .green : .orange).frame(width: 9, height: 9)
                Text(model.status).font(.callout)
                Spacer()
                if model.listening || model.connected { Button("Disconnect & Stop", role: .destructive) { model.stop() } }
                else if model.paired { Button("Start Listening") { model.startListening() }.buttonStyle(.borderedProminent) }
            }
            GroupBox("1 · Allow Mac control") {
                HStack {
                    Label(model.accessible ? "Accessibility enabled" : "Accessibility approval required",
                          systemImage: model.accessible ? "checkmark.circle.fill" : "hand.raised")
                    Spacer()
                    Button("Open Accessibility Settings") {
                        model.requestAccessibility()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }.padding(6)
            }
            GroupBox("2 · Pair your iPad") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Open Styleus on the iPad and connect by USB-C, or select Wi-Fi on the same network. Only the paired iPad can control this Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.paired ? "Show Pairing Code" : "Pair iPad") {
                            if model.paired { model.showPairing() } else { model.newPairing() }
                        }.buttonStyle(.borderedProminent)
                        if model.paired {
                            Button("Replace Pairing…") { confirmReplacement = true }
                            Button("Forget Pairing", role: .destructive) { model.forgetPairing() }
                        }
                    }
                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("3 · Drawing-tablet target") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Display", selection: $model.selectedDisplay) {
                        ForEach(model.displays) { Text($0.name).tag($0.id) }
                    }.onChange(of: model.selectedDisplay) { _, _ in model.useWholeDisplay() }
                    HStack {
                        Button("Use Whole Display") { model.useWholeDisplay() }
                        Button("Select Region on Display…") { model.chooseRegion() }
                    }
                    Text("\(model.target.name) · \(Int(model.target.rect.width)) × \(Int(model.target.rect.height))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Basic drawing — mouse emulation. Select a pen/ink tool in Zotero or Notability. Pencil pressure starts and ends strokes; it does not control ink width.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(6)
            }
            Text("Trackpad mode controls the Mac across all connected displays. Keep the iPad app open; this companion may stay in the background. Use the menu bar to stop at any time.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.dragActive { Label("Pressure drag active", systemImage: "hand.draw.fill").foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 5) {
                Picker("Cursor indicator", selection: $model.cursorIndicatorStyle) {
                    ForEach(CursorIndicatorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Text("Pressure feedback is at the top of the iPad screen. The optional Mac cursor ring is off by default; Dragging only and Pressure and dragging enable it here.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Test Scrolling…") { ScrollDiagnostics.shared.show() }
            PressureProbePanel(probe: model.pressureProbe, permitted: model.accessible, run: model.runPressureProbe)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(minWidth: 590, minHeight: 600)
        .sheet(isPresented: Binding(get: { model.pairingCode != nil }, set: { if !$0 { model.pairingCode = nil } })) {
            PairingSheet(code: model.pairingCode ?? "") { model.pairingCode = nil }
        }
        .confirmationDialog("Replace the approved iPad?", isPresented: $confirmReplacement) {
            Button("Revoke Old Pairing and Create New Code", role: .destructive) { model.newPairing() }
        } message: { Text("The previous pairing will stop working immediately.") }
        .alert("Styleus", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private struct StyleusMenu: View {
    @ObservedObject var model: MacModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Button("Show Styleus") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Picker("Cursor indicator", selection: $model.cursorIndicatorStyle) {
            ForEach(CursorIndicatorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Button("Test Scrolling…") { ScrollDiagnostics.shared.show() }
        Button("Disconnect and stop") { model.stop() }
        Divider()
        Button("Quit Styleus") { model.stop(); NSApp.terminate(nil) }
    }
}

private struct PressureProbePanel: View {
    @ObservedObject var probe: PressureProbe
    let permitted: Bool
    let run: () -> Void
    @State private var confirm = false
    var body: some View {
        DisclosureGroup("Experimental Notability pressure test") {
            VStack(alignment: .leading, spacing: 10) {
                Text("A compatibility experiment only. Prepare a disposable blank Notability note, select its pen tool, and select a custom region entirely inside the note. This adds two test strokes; it does not enable pressure from the iPad.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Text(probe.status).font(.caption).fixedSize(horizontal: false, vertical: true)
                if probe.running { Button("Stop Test") { probe.cancel() } }
                else { Button("Run in Prepared Test Note…") { confirm = true }.disabled(!permitted) }
            }.padding(.top, 8)
        }.confirmationDialog("Write two test strokes to the selected Notability region?", isPresented: $confirm) {
            Button("Run Test in Disposable Note", action: run)
        } message: { Text("The first stroke uses constant pressure; the second varies pressure and tilt at the same speed. Only your inspection of the resulting ink can establish whether Notability uses them. Remote control will stop during the test.") }
    }
}

private struct PairingSheet: View {
    let code: String
    let done: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Scan with Styleus on your iPad").font(.title2.bold())
            if let image = qrImage {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 260, height: 260).padding(12).background(.white)
            }
            Text("This code grants control of your Mac. Keep it private.").font(.callout)
            DisclosureGroup("Text-code fallback") {
                Text(code).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(8)
            }
            Button("Done", action: done).keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 440)
    }
    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(code.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
