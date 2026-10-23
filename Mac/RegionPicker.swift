import AppKit
import SwiftUI

final class RegionPicker {
    private let display: DisplayChoice
    private let completion: (Rect?) -> Void
    private var window: NSWindow?
    init(display: DisplayChoice, completion: @escaping (Rect?) -> Void) {
        self.display = display; self.completion = completion
    }

    func show() {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
        }) else { completion(nil); return }
        let window = RegionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RegionOverlay { [weak self] selected, size in
            guard let self else { return }
            self.window?.close(); self.window = nil
            guard let selected, size.width > 0, size.height > 0 else { self.completion(nil); return }
            let bounds = self.display.bounds
            let rect = Rect(x: bounds.x + selected.minX / size.width * bounds.width,
                            y: bounds.y + selected.minY / size.height * bounds.height,
                            width: selected.width / size.width * bounds.width,
                            height: selected.height / size.height * bounds.height)
            self.completion(rect)
        })
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class RegionWindow: NSWindow { override var canBecomeKey: Bool { true } }

private struct RegionOverlay: View {
    let completion: (CGRect?, CGSize) -> Void
    @State private var start: CGPoint?
    @State private var selection = CGRect.zero
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.17)
                if selection.width > 0 {
                    Rectangle().fill(Color.accentColor.opacity(0.15))
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                        .frame(width: selection.width, height: selection.height)
                        .position(x: selection.midX, y: selection.midY)
                }
                HStack {
                    Text("Drag a rectangle around your Mac annotation area").font(.headline)
                    Button("Cancel (Esc)") { completion(nil, geometry.size) }.keyboardShortcut(.cancelAction)
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(24)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                if start == nil { start = value.startLocation }
                let a = start!
                let b = CGPoint(x: min(max(value.location.x, 0), geometry.size.width),
                                y: min(max(value.location.y, 0), geometry.size.height))
                selection = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            }.onEnded { _ in
                if selection.width >= 32 && selection.height >= 32 { completion(selection, geometry.size) }
                else { start = nil; selection = .zero }
            })
        }.ignoresSafeArea()
    }
}
