import Foundation
import Network
import Security

enum ConnectionTrace {
    /// Development diagnostics contain lifecycle events only, never keys, pairing codes, or input samples.
    static func note(_ message: String) {
        #if DEBUG
        let line = String(format: "[Styleus connection %.3f] %@\n", ProcessInfo.processInfo.systemUptime, message)
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
}

enum ConnectionMode: String, CaseIterable {
    case usb, wifi

    var title: String { self == .usb ? "USB-C / wired" : "Wi-Fi" }
    var interfaceType: NWInterface.InterfaceType { self == .usb ? .wiredEthernet : .wifi }
    var discoveryHelp: String {
        self == .usb
            ? "Connect a USB-C data cable, unlock the iPad, and start listening on the Mac. Allow Local Network access."
            : "Start listening on the Mac, allow Local Network access, and use the same Wi-Fi."
    }
}

enum LocalTransport {
    static let serviceType = "_styleus._tcp"

    private static func encryptedParameters(_ credential: PairingCredential) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        // PSK's public IANA cipher value is present in CipherSuite.h but not as a named Swift enum case.
        let cipher = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        sec_protocol_options_append_tls_ciphersuite(options, cipher)
        let key = credential.secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(credential.id.uuidString.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        parameters.acceptLocalOnly = true
        return parameters
    }

    static func parameters(_ credential: PairingCredential, mode: ConnectionMode) -> NWParameters {
        let parameters = encryptedParameters(credential)
        parameters.requiredInterfaceType = mode.interfaceType
        return parameters
    }

    static func listenerParameters(_ credential: PairingCredential) -> NWParameters {
        let parameters = encryptedParameters(credential)
        parameters.prohibitedInterfaceTypes = [.cellular, .other, .loopback]
        return parameters
    }

    static func browserParameters(mode: ConnectionMode) -> NWParameters {
        let parameters = NWParameters()
        parameters.requiredInterfaceType = mode.interfaceType
        parameters.includePeerToPeer = false
        return parameters
    }

    static func mode(for path: NWPath?) -> ConnectionMode? {
        guard let path, path.status == .satisfied else { return nil }
        let wired = path.usesInterfaceType(.wiredEthernet)
        let wifi = path.usesInterfaceType(.wifi)
        guard wired != wifi, !path.usesInterfaceType(.cellular), !path.usesInterfaceType(.loopback) else { return nil }
        return wired ? .usb : .wifi
    }
}

/// All methods and callbacks run on the main queue, including the bounded transmission queue.
final class MessageChannel {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((WireMessage) -> Void)?
    var onClose: ((String) -> Void)?
    var onPathChange: ((NWPath) -> Void)?
    private(set) var ready = false
    private(set) var closed = false
    private var decoder = FrameDecoder()
    private var pending: [(Data, TimeInterval)] = []
    private var sendingSince: TimeInterval?
    private let started = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        ConnectionTrace.note("Channel starting")
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                ConnectionTrace.note("TLS ready after \(ProcessInfo.processInfo.systemUptime - self.started) seconds")
                ConnectionTrace.note("Authenticated route: \(String(describing: self.connection.currentPath))")
                self.ready = true; self.onReady?(); self.receive()
            case .failed(let error): self.close("Connection failed: \(error.localizedDescription)")
            case .waiting: self.close("Connection unavailable. Check the selected connection and Local Network access, then reconnect.")
            case .cancelled: self.close("Disconnected")
            case .preparing: ConnectionTrace.note("Channel preparing: \(String(describing: self.connection.currentPath))")
            default: break
            }
        }
        connection.pathUpdateHandler = { [weak self] path in
            guard let self, self.ready, !self.closed else { return }
            self.onPathChange?(path)
        }
        connection.start(queue: .main)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkDeadline() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkDeadline() {
        let now = ProcessInfo.processInfo.systemUptime
        if !ready && now - started > 15 {
            ConnectionTrace.note("Startup path: \(String(describing: connection.currentPath))")
            close("Secure connection setup timed out. Check that the Mac is listening and the selected connection is available.")
        }
        if let sendingSince, now - sendingSince > 0.5 { close("Input delivery stalled. Reconnect to start safely.") }
        if let oldest = pending.first, now - oldest.1 > 0.5 { close("Input became stale. Reconnect to start safely.") }
    }

    func send(_ message: WireMessage) {
        guard ready, !closed else { return }
        do {
            let frame = try FrameDecoder.encode(message)
            guard pending.count < 64 else { close("Input queue filled. Reconnect to start safely."); return }
            pending.append((frame, ProcessInfo.processInfo.systemUptime))
            drain()
        } catch { close(error.localizedDescription) }
    }

    private func drain() {
        guard !closed, sendingSince == nil, !pending.isEmpty else { return }
        let frame = pending.removeFirst()
        guard ProcessInfo.processInfo.systemUptime - frame.1 <= 0.5 else {
            close("Input became stale. Reconnect to start safely."); return
        }
        sendingSince = frame.1
        connection.send(content: frame.0, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            if let error { self.close(error.localizedDescription); return }
            self.sendingSince = nil
            self.drain()
        })
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: FrameDecoder.limit) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            do {
                if let data {
                    for frame in try self.decoder.append(data) {
                        guard !self.closed else { return }
                        self.onMessage?(try JSONDecoder().decode(WireMessage.self, from: frame))
                    }
                }
            } catch { self.close(error.localizedDescription); return }
            if let error { self.close(error.localizedDescription) }
            else if complete { self.close("Disconnected") }
            else { self.receive() }
        }
    }

    func close(_ reason: String = "Disconnected") {
        guard !closed else { return }
        ConnectionTrace.note("Channel closed after \(ProcessInfo.processInfo.systemUptime - started) seconds: \(reason)")
        closed = true; ready = false
        pending.removeAll(); sendingSince = nil
        timer?.invalidate(); timer = nil
        connection.stateUpdateHandler = nil
        connection.pathUpdateHandler = nil
        connection.cancel()
        onClose?(reason)
        onClose = nil; onMessage = nil; onReady = nil; onPathChange = nil
    }
}
