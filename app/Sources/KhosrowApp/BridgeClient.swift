#if canImport(AppKit)
import Foundation
import KhosrowKit
#if canImport(Network)
import Network
#endif

/// Reads normalized pet state produced by the Claude Code hook bridge.
///
/// Two convergent inputs, both optional and both feeding `onState`:
///   1. **State file** (default, always on): polls `~/.claude-pet/state.json`,
///      an atomically-written minimal payload. Bulletproof for short-lived hook
///      processes.
///   2. **Localhost HTTP** (preferred, low-latency, best-effort): a tiny
///      `127.0.0.1` listener hooks may POST to for instant updates.
///
/// Only ``PetBridgeState`` (state / toolCategory / timestamp / success) ever
/// crosses this boundary — never prompts, code, commands, or secrets.
final class BridgeClient {

    /// Default state-file location, override with `KHOSROW_PET_STATE_FILE`.
    static var defaultStateFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["KHOSROW_PET_STATE_FILE"] {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude-pet/state.json")
    }

    var onState: ((PetBridgeState) -> Void)?

    private let stateFileURL: URL
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var lastPayload: PetBridgeState?
    private var lastModified: Date?

    #if canImport(Network)
    private var listener: NWListener?
    #endif

    init(stateFileURL: URL = BridgeClient.defaultStateFileURL,
         pollInterval: TimeInterval = 0.4) {
        self.stateFileURL = stateFileURL
        self.pollInterval = pollInterval
    }

    // MARK: File polling

    func startFilePolling() {
        stopFilePolling()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollFile()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        pollFile()
    }

    func stopFilePolling() {
        timer?.invalidate()
        timer = nil
    }

    private func pollFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stateFileURL.path) else { return }
        // Skip unchanged files cheaply via mtime.
        if let attrs = try? fm.attributesOfItem(atPath: stateFileURL.path),
           let mod = attrs[.modificationDate] as? Date {
            if let last = lastModified, mod <= last { return }
            lastModified = mod
        }
        guard let data = try? Data(contentsOf: stateFileURL),
              let payload = try? PetBridgeState.decode(from: data) else { return }
        deliver(payload)
    }

    private func deliver(_ payload: PetBridgeState) {
        guard payload != lastPayload else { return }
        lastPayload = payload
        DispatchQueue.main.async { [weak self] in
            self?.onState?(payload)
        }
    }

    // MARK: Localhost HTTP (best-effort, preferred low-latency path)

    /// Start a minimal HTTP listener bound to loopback. Silently no-ops if the
    /// port is unavailable — the file path still works.
    func startHTTPListener(port: UInt16 = 51763) {
        #if canImport(Network)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: nwPort) else { return }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        listener.start(queue: .main)
        self.listener = listener
        #endif
    }

    func stopHTTPListener() {
        #if canImport(Network)
        listener?.cancel()
        listener = nil
        #endif
    }

    #if canImport(Network)
    private func handle(connection conn: NWConnection) {
        conn.start(queue: .main)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var acc = buffer
            if let data { acc.append(data) }

            if let body = Self.extractHTTPBody(acc) {
                if let payload = try? PetBridgeState.decode(from: body) {
                    self.deliver(payload)
                }
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                })
                return
            }

            if isComplete || error != nil || acc.count > 128 * 1024 {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: acc)
            }
        }
    }

    /// Return the request body once headers + full Content-Length are present.
    static func extractHTTPBody(_ data: Data) -> Data? {
        let sep = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: sep) else { return nil }
        let header = String(decoding: data[..<range.lowerBound], as: UTF8.self)
        let body = data[range.upperBound...]
        var contentLength = 0
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard body.count >= contentLength else { return nil }
        return Data(body.prefix(contentLength))
    }
    #endif
}
#endif
