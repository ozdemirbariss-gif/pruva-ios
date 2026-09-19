import Foundation

/// Bounded, ASCII NMEA framing; checksum and field validation belong to the parser.
/// A TCP instance persists between reads. Each UDP datagram uses a fresh instance,
/// so truncated datagrams and different senders can never form one sentence.
public struct NMEAFramer: Sendable {
    public static let maximumSentenceBytes = 4_096
    public private(set) var bufferedByteCount = 0
    private var bytes: [UInt8] = []

    public init() {}

    public mutating func reset() {
        bytes.removeAll(keepingCapacity: true)
        bufferedByteCount = 0
    }

    public mutating func append(_ data: Data) -> [String] {
        // NMEA is ASCII. Reject an invalid or non-ASCII chunk atomically, rather
        // than accidentally attaching its surviving suffix to an earlier read.
        guard data.allSatisfy({ $0 < 128 }) else {
            reset()
            return []
        }
        var sentences: [String] = []
        for byte in data {
            if byte == 36 || byte == 33 { // $ or ! starts/resynchronizes a sentence.
                bytes = [byte]
            } else if byte == 10 || byte == 13 {
                if !bytes.isEmpty { sentences.append(String(decoding: bytes, as: UTF8.self)) }
                bytes.removeAll(keepingCapacity: true)
            } else if byte < 32 || byte == 127 {
                bytes.removeAll(keepingCapacity: true)
            } else if !bytes.isEmpty {
                if bytes.count < Self.maximumSentenceBytes {
                    bytes.append(byte)
                } else {
                    bytes.removeAll(keepingCapacity: true)
                }
            }
        }

        // Some gateways omit CR/LF. At a read boundary, *HH is sufficient to
        // frame a complete envelope; the parser still verifies the checksum.
        if bytes.count >= 5,
           bytes[bytes.count - 3] == 42,
           Self.isHex(bytes[bytes.count - 2]), Self.isHex(bytes[bytes.count - 1]) {
            sentences.append(String(decoding: bytes, as: UTF8.self))
            bytes.removeAll(keepingCapacity: true)
        }
        bufferedByteCount = bytes.count
        return sentences
    }

    /// UDP preserves message boundaries; partial trailing sentences are dropped.
    public static func sentences(inDatagram data: Data) -> [String] {
        guard data.count <= 65_507 else { return [] }
        var framer = NMEAFramer()
        return framer.append(data)
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }
}
