import Foundation
import Network
import Observation
import RaceCore

enum NMEATransport: String, Codable, CaseIterable, Identifiable {
    case tcp, udp
    var id: String { rawValue }
}

struct NMEAConnectionSettings: Codable, Equatable {
    var transport: NMEATransport = .tcp
    var host: String = ""
    var port: Int = 10_110
}

/// An explicitly started, receive-only connection. TCP connects to the configured
/// gateway. UDP listens for unicast datagrams addressed to this device; `host` is
/// unused in UDP mode. No discovery, multicast membership, or instrument commands.
@MainActor
@Observable
final class NMEAConnection {
    private(set) var status = "Bağlı değil"
    private(set) var isRunning = false
    private(set) var receivedSentences = 0
    private(set) var lastError: String?
    var onSentence: ((String, Date) -> Void)?

    @ObservationIgnored private let networkQueue = DispatchQueue(label: "com.pruva.nmea", qos: .userInitiated)
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var tcpConnection: NWConnection?
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var peers: [UUID: UDPPeer] = [:]
    @ObservationIgnored private var tcpFramer = NMEAFramer()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var connectTimeoutTask: Task<Void, Never>?
    private let maximumPeers = 8

    func start(_ settings: NMEAConnectionSettings) {
        stop()
        receivedSentences = 0
        guard (1...65_535).contains(settings.port),
              let port = NWEndpoint.Port(rawValue: UInt16(settings.port)) else {
            fail("Port 1 ile 65535 arasında olmalı.")
            return
        }
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.transport != .tcp || !host.isEmpty else {
            fail("TCP için ağ geçidinin IP adresini veya adını girin.")
            return
        }
        isRunning = true
        lastError = nil
        let session = generation
        switch settings.transport {
        case .tcp:
            status = "TCP bağlanıyor…"
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            tcpConnection = connection
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session else { return }
                    self.handleTCP(state, connection: connection, session: session)
                }
            }
            connection.start(queue: networkQueue)
            startConnectionTimeout(session: session)
        case .udp:
            status = "UDP açılıyor…"
            do {
                let listener = try NWListener(using: .udp, on: port)
                self.listener = listener
                listener.newConnectionLimit = maximumPeers
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == session else { return }
                        self.handleListener(state)
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == session, self.isRunning else {
                            connection.cancel()
                            return
                        }
                        self.acceptPeer(connection, session: session)
                    }
                }
                listener.start(queue: networkQueue)
                startPeerExpiry(session: session)
                startConnectionTimeout(session: session)
            } catch {
                fail("UDP portu açılamadı: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        invalidateTransport()
        status = "Durduruldu"
        isRunning = false
        lastError = nil
    }

    private func invalidateTransport() {
        // Invalidate before cancelling: already queued callbacks cannot modify a
        // replacement session, emit old data, or clear its running state.
        generation = UUID()
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        tcpConnection?.stateUpdateHandler = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for peer in peers.values {
            peer.connection.stateUpdateHandler = nil
            peer.connection.cancel()
        }
        peers.removeAll()
        tcpFramer.reset()
    }

    private func fail(_ message: String) {
        invalidateTransport()
        isRunning = false
        status = "Bağlantı kesildi"
        lastError = message
    }

    private func handleTCP(_ state: NWConnection.State, connection: NWConnection, session: UUID) {
        switch state {
        case .ready:
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            status = "TCP bağlı · veri bekleniyor"
            receiveTCP(connection, session: session)
        case .waiting(let error), .failed(let error):
            fail("TCP bağlantısı kurulamadı veya kesildi: \(error.localizedDescription). Yeniden bağlanın.")
        case .cancelled:
            fail("TCP bağlantısı kapandı. Yeniden bağlanın.")
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func receiveTCP(_ connection: NWConnection, session: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            let receivedAt = Date()
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, self.isRunning else { return }
                if let data, !data.isEmpty {
                    let sentences = self.tcpFramer.append(data)
                    self.deliver(sentences, at: receivedAt, session: session, transport: .tcp)
                }
                // onSentence may itself stop or replace the connection.
                guard self.generation == session, self.isRunning else { return }
                if let error {
                    self.fail("TCP verisi alınamadı: \(error.localizedDescription). Yeniden bağlanın.")
                } else if isComplete {
                    self.fail("Ağ geçidi TCP bağlantısını kapattı. Yeniden bağlanın.")
                } else {
                    self.receiveTCP(connection, session: session)
                }
            }
        }
    }

    private func handleListener(_ state: NWListener.State) {
        switch state {
        case .ready:
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            status = "Dinleniyor · veri bekleniyor"
        case .waiting(let error), .failed(let error):
            fail("UDP dinleyicisi açılamadı veya durdu: \(error.localizedDescription). Yeniden başlatın.")
        case .cancelled:
            fail("UDP dinleyicisi kapandı. Yeniden başlatın.")
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func acceptPeer(_ connection: NWConnection, session: UUID) {
        removeExpiredPeers()
        guard peers.count < maximumPeers else {
            connection.cancel()
            return
        }
        let peerID = UUID()
        peers[peerID] = UDPPeer(connection: connection, lastReceived: Date())
        listener?.newConnectionLimit = maximumPeers - peers.count
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, self.peers[peerID] != nil else { return }
                switch state {
                case .ready:
                    self.receiveUDP(connection, peerID: peerID, session: session)
                case .failed, .waiting, .cancelled:
                    self.removePeer(peerID)
                default:
                    break
                }
            }
        }
        connection.start(queue: networkQueue)
    }

    private func receiveUDP(_ connection: NWConnection, peerID: UUID, session: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            let receivedAt = Date()
            Task { @MainActor [weak self] in
                guard let self, self.generation == session, self.isRunning, self.peers[peerID] != nil else { return }
                if let data, !data.isEmpty {
                    self.peers[peerID]?.lastReceived = receivedAt
                    let sentences = NMEAFramer.sentences(inDatagram: data)
                    self.deliver(sentences, at: receivedAt, session: session, transport: .udp)
                }
                guard self.generation == session, self.isRunning, self.peers[peerID] != nil else { return }
                if error != nil {
                    self.removePeer(peerID)
                } else {
                    // `isComplete` ends this datagram, not the UDP peer.
                    self.receiveUDP(connection, peerID: peerID, session: session)
                }
            }
        }
    }

    private func deliver(_ sentences: [String], at date: Date, session: UUID, transport: NMEATransport) {
        for sentence in sentences {
            guard generation == session, isRunning else { return }
            receivedSentences += 1
            status = transport == .tcp ? "TCP bağlı" : "UDP dinleniyor"
            onSentence?(sentence, date)
        }
    }

    private func removePeer(_ id: UUID) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        peer.connection.stateUpdateHandler = nil
        peer.connection.cancel()
        listener?.newConnectionLimit = maximumPeers - peers.count
    }

    private func removeExpiredPeers() {
        let cutoff = Date().addingTimeInterval(-60)
        for id in peers.compactMap({ $0.value.lastReceived < cutoff ? $0.key : nil }) {
            removePeer(id)
        }
    }

    private func startPeerExpiry(session: UUID) {
        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, self.generation == session, self.isRunning else { return }
                self.removeExpiredPeers()
            }
        }
    }

    private func startConnectionTimeout(session: UUID) {
        connectTimeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == session, self.isRunning else { return }
            self.fail("Bağlantı zaman aşımına uğradı. Ağ adresini ve yerel ağ iznini kontrol edip yeniden bağlanın.")
        }
    }
}

private struct UDPPeer {
    let connection: NWConnection
    var lastReceived: Date
}
