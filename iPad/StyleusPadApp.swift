import SwiftUI

@main
struct StyleusPadApp: App {
    @StateObject private var model = PadModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { PadContentView(model: model) }
            .onChange(of: phase) { _, phase in
                if phase != .active { model.disconnect("iPad interrupted. Tap Connect when ready.", issue: .interrupted) }
            }
    }
}

struct PadContentView: View {
    @ObservedObject var model: PadModel
    @AppStorage("sensitivity") private var sensitivity = 1.5
    // Preserve the previous combined direction setting until each axis is changed.
    @AppStorage("reverseVerticalScroll") private var reverseVerticalScroll = !(UserDefaults.standard.object(forKey: "naturalScroll") as? Bool ?? true)
    @AppStorage("reverseHorizontalScroll") private var reverseHorizontalScroll = !(UserDefaults.standard.object(forKey: "naturalScroll") as? Bool ?? true)
    @AppStorage("scrollSensitivity") private var scrollSensitivity = 1.0
    @AppStorage("experimentalPinchZoom") private var experimentalPinchZoom = false
    @AppStorage("pressureThreshold") private var pressureThreshold = 0.2
    @State private var pairing = false
    @State private var settings = false
    @State private var pencilFeedback = PencilFeedbackRelay()
    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    identityAndStatus
                    Spacer(minLength: 16)
                    headerControls
                }
                VStack(alignment: .leading, spacing: 6) {
                    identityAndStatus
                    HStack { Spacer(minLength: 0); headerControls }
                }
            }
            HStack(spacing: 8) {
                PencilPressureMeter(feedback: pencilFeedback)
                    .frame(width: 28)
                    .allowsHitTesting(false)
                InputSurface(mode: model.mode, sensitivity: sensitivity, pressureThreshold: pressureThreshold,
                             reverseVerticalScroll: reverseVerticalScroll, reverseHorizontalScroll: reverseHorizontalScroll,
                             scrollSensitivity: scrollSensitivity,
                             pinchZoomEnabled: experimentalPinchZoom && model.zoomAvailable,
                             targetAspect: model.target?.rect.aspect ?? 16.0 / 10,
                             revision: model.inputRevision, enabled: model.connected && model.inputAllowed,
                             feedback: pencilFeedback,
                             action: { [revision = model.inputRevision] in model.sendSurface($0, revision: revision) },
                             pencilStatus: { [revision = model.inputRevision] in model.updatePencilStatus($0, revision: revision) })
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if model.mode == .drawing {
                HStack {
                    Text("\(model.target?.name ?? "Select a region on your Mac") · basic mouse ink · margins are inactive")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Release Input") { model.resetContact() }.buttonStyle(.bordered)
                }
            }
        }
        .padding(16).background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: pressureThreshold) { _, _ in model.resetContact() }
        .onChange(of: reverseVerticalScroll) { _, _ in model.resetContact() }
        .onChange(of: reverseHorizontalScroll) { _, _ in model.resetContact() }
        .onChange(of: scrollSensitivity) { _, _ in model.resetContact() }
        .onChange(of: experimentalPinchZoom) { _, _ in model.resetContact() }
        .sheet(isPresented: $pairing) { PairMacSheet(model: model) }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Section("Connection") {
                        Picker("Connect using", selection: Binding(get: { model.connectionMode }, set: { model.changeConnectionMode($0) })) {
                            ForEach(ConnectionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        Text("USB-C / wired is the default. Connect a data cable to your Mac, or select Wi-Fi to use the same wireless network. Allow Local Network access for either choice. Switching connections releases input and requires Connect again.")
                        Text("Cable mode requires a wired network link and never switches to Wi-Fi automatically. A compatible Ethernet connection also counts as wired.")
                        if let milliseconds = model.roundTripMilliseconds {
                            Text(String(format: "Recent median round trip: %.1f ms (%d samples).", milliseconds, model.timingSampleCount))
                        }
                        Text("Round trip measures a message sent to the Mac and back, including app scheduling. It does not measure the full delay from Pencil movement to the Mac screen.")
                        Button("Pair or Replace Mac") { settings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pairing = true } }
                        Button("Forget Pairing", role: .destructive) { model.forget() }
                    }
                    Section("Trackpad") {
                        HStack { Text("Sensitivity"); Spacer(); Text(String(format: "%.1f×", sensitivity)) }
                        Slider(value: $sensitivity, in: 0.2...4, step: 0.1)
                        Text("Use Apple Pencil to move the pointer. Tap for a left click, tap twice quickly for a double click, or hold still for half a second and lift for a right click. Press more firmly while moving to drag. Easing pressure or lifting releases the drag.")
                        Text("Slide two fingers anywhere in the main area to scroll vertically or horizontally in either mode. A flick glides to a stop; touching down again stops the glide. Fingers never move or click the pointer. Scrolling pauses while the Pencil touches the screen; lift all fingers before starting a new scroll gesture afterward.")
                    }
                    Section("Scrolling") {
                        HStack { Text("Scrolling speed"); Spacer(); Text(String(format: "%.2g×", scrollSensitivity)) }
                        Slider(value: $scrollSensitivity, in: 0.25...4, step: 0.25)
                        Text("Slow slides give fine control; faster swipes travel farther. This setting scales scrolling and the following glide together. Pencil pointer sensitivity is separate.")
                        Toggle("Reverse vertical scrolling", isOn: $reverseVerticalScroll)
                        Text(reverseVerticalScroll ? "Pull down to reveal text below." : "Pull down to reveal text above.")
                        Toggle("Reverse horizontal scrolling", isOn: $reverseHorizontalScroll)
                        Text(reverseHorizontalScroll ? "Pull right to reveal content to the right." : "Pull right to reveal content to the left.")
                        Text("Each direction changes independently. Changing a setting stops any ongoing scroll.")
                    }
                    Section("Pinch to zoom") {
                        Toggle("Experimental pinch zoom", isOn: $experimentalPinchZoom)
                        Text("Spread two fingers to zoom in, or pinch them together to zoom out. Slide them together to scroll. Each gesture stays with the action it starts; lift both fingers before switching.")
                        Text("Built into Styleus; no extra app is needed. Support varies by Mac app and macOS version. Some browsers require a larger pinch before zoom begins. Turn this off to use the original scrolling behavior.")
                        if model.connected && !model.zoomAvailable {
                            Text("Experimental zoom is unavailable on this Mac. Scrolling remains active.").foregroundStyle(.secondary)
                        }
                    }
                    Section("Pencil pressure") {
                        HStack { Text("Pressure needed"); Spacer(); Text("\(Int(pressureThreshold * 100))%") }
                        Slider(value: $pressureThreshold, in: 0.05...0.8, step: 0.025)
                        Text("Lower values need a lighter press. This threshold starts a drag while moving in Trackpad, or starts ink in Drawing tablet. Release happens at a slightly lighter pressure to avoid flickering near the threshold.")
                        Text("Single taps and long presses do not need firm pressure. Pressure controls the mouse button, not ink width in the Mac app.")
                        Text("The left meter fills upward with Pencil pressure. Its mark shows the activation level; orange means a drag or drawing stroke is active. It responds on the iPad without waiting for a Mac reply.")
                    }
                    Section("Drawing") {
                        Text("Basic mouse emulation. Light Pencil contact positions the pointer; pressing starts a stroke. Pressure-dependent ink width and tilt are not enabled in Zotero or Notability. No Pencil hover is required.")
                    }
                }.navigationTitle("Styleus Settings")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } }
            }
        }
        .alert("Styleus", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var identityAndStatus: some View {
        HStack(spacing: 12) {
            Text("Styleus").font(.title.bold()).fixedSize()
            ConnectionStatusView(model: model)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.changeMode($0) })) {
                Text("Trackpad").tag(InputMode.trackpad)
                Text("Drawing tablet").tag(InputMode.drawing)
            }
            .pickerStyle(.menu).labelsHidden().accessibilityLabel("Mode")
            .fixedSize().frame(minHeight: 44)
            Button { model.resetContact(); settings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel("Settings")
            if model.connected || model.connecting {
                Button("Disconnect", role: .destructive) { model.disconnect() }
                    .buttonStyle(.bordered).frame(minHeight: 44).fixedSize()
            } else {
                Button(model.paired ? "Connect" : "Pair Mac") {
                    if model.paired { model.connect() } else { pairing = true }
                }.buttonStyle(.borderedProminent).frame(minHeight: 44).fixedSize()
            }
        }
    }
}

private struct PairMacSheet: View {
    @ObservedObject var model: PadModel
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var code = ""
    @State private var pairingError: String?
    var body: some View {
        NavigationStack {
            Form {
                if let pairingError {
                    Section { Text(pairingError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
                Section {
                    Text("On your Mac, open Styleus and choose Pair iPad or Show Pairing Code. Scan only the code on your own Mac.")
                    Button("Scan Mac QR Code") { scanning = true }.buttonStyle(.borderedProminent)
                }
                Section("Text-code fallback") {
                    TextField("styleus:1:…", text: $code, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save Pairing") { save(code) }.disabled(code.isEmpty)
                }
            }.navigationTitle("Pair Your Mac")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(isPresented: $scanning) {
                    VStack {
                        HStack { Text("Scan the code on your Mac").font(.headline); Spacer(); Button("Cancel") { scanning = false } }.padding()
                        QRScanner { result in
                            scanning = false
                            switch result {
                            case .success(let code): save(code)
                            case .failure(let error): pairingError = error.localizedDescription
                            }
                        }
                    }
                }
        }
    }
    private func save(_ code: String) {
        if model.pair(code) { dismiss() }
        else { pairingError = model.error; model.error = nil }
    }
}
