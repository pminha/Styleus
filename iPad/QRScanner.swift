import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    var completion: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(completion: completion) }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: ScannerController, coordinator: ()) { uiViewController.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Styleus.camera")
    private let completion: (Result<String, Error>) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    init(completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                if allowed { self.configure() }
                else { self.finish(.failure(ScannerError.permission)) }
            }
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { finish(.failure(ScannerError.unavailable)); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { finish(.failure(ScannerError.unavailable)); return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview); self.preview = preview; preview.frame = view.bounds
        queue.async { [session] in session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        finish(.success(code))
    }
    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        stop(); completion(result)
    }
    func stop() { finished = true; queue.async { [session] in session.stopRunning() } }
}

enum ScannerError: LocalizedError {
    case permission, unavailable
    var errorDescription: String? {
        switch self {
        case .permission: return "Camera access is disabled. Allow Camera access for Styleus in Settings, or use the text-code fallback."
        case .unavailable: return "Camera unavailable. Use the text-code fallback."
        }
    }
}
