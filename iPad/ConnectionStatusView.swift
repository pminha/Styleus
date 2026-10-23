import SwiftUI

struct ConnectionStatusView: View {
    @ObservedObject var model: PadModel
    @State private var showingDetails = false

    var body: some View {
        let info = model.connectionPresentation
        HStack(spacing: 6) {
            Circle().fill(model.connected && model.inputAllowed ? Color.green : Color.orange)
                .frame(width: 8, height: 8).accessibilityHidden(true)
            Text(info.headerTitle).font(.callout).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Button {
                model.resetContact()
                showingDetails = true
            } label: {
                Image(systemName: "info.circle").font(.title3)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(info.isProblem ? "Connection problem details" : "Connection information")
            .accessibilityHint("Shows the full connection status and steps to take.")
            .popover(isPresented: $showingDetails, arrowEdge: .top) {
                ConnectionDetailsView(model: model) { showingDetails = false }
                    .presentationCompactAdaptation(.sheet)
            }
        }
    }
}

struct ConnectionDetailsView: View {
    @ObservedObject var model: PadModel
    let dismiss: () -> Void

    var body: some View {
        let info = model.connectionPresentation
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connection", systemImage: info.isProblem ? "exclamationmark.circle" : "info.circle")
                    .font(.headline)
                Spacer()
                Button("Done", action: dismiss).frame(minHeight: 44)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(info.headerTitle).font(.headline)
                    Text(info.detail).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if !info.steps.isEmpty {
                        Text(info.isProblem ? "What to check" : "Next steps").font(.subheadline.bold())
                        ForEach(Array(info.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).").foregroundStyle(.secondary)
                                Text(step).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Divider()
                    LabeledContent("Selected connection", value: model.connectionMode.title)
                    if let active = model.activeConnection {
                        LabeledContent("Active connection", value: active.title)
                    }
                    if let milliseconds = model.roundTripMilliseconds {
                        Text(String(format: "Recent median round trip: %.1f ms (%d samples).", milliseconds, model.timingSampleCount))
                            .font(.callout.monospacedDigit())
                        Text("Round trip measures communication to the Mac and back, not Pencil-to-screen delay.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.connected && model.inputAllowed {
                        Text("Your paired Mac is connected securely and has approved pointer input.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(idealWidth: 420, maxWidth: 460, idealHeight: 440, maxHeight: 560)
    }
}
