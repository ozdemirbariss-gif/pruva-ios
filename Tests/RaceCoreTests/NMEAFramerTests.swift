import XCTest
@testable import RaceCore

final class NMEAFramerTests: XCTestCase {
    private let first = "$WIMWV,45.0,R,12.0,N,A*00"
    private let second = "$IIVHW,30.0,T,,M,6.2,N,,K*00"

    func testTCPHandlesSplitSentencesAndSeveralLines() {
        var framer = NMEAFramer()
        XCTAssertEqual(framer.append(Data("$WIMWV,45.0,".utf8)), [])
        XCTAssertEqual(framer.append(Data("R,12.0,N,A*00\r\n\(second)\r\n".utf8)), [first, second])
        XCTAssertEqual(framer.bufferedByteCount, 0)
    }

    func testChecksumEnvelopeMayFinishWithoutNewlineAndAcrossReads() {
        var framer = NMEAFramer()
        XCTAssertEqual(framer.append(Data(first.dropLast().utf8)), [])
        XCTAssertEqual(framer.append(Data("0".utf8)), [first])
        XCTAssertEqual(framer.append(Data("\r\n".utf8)), [])
    }

    func testUDPDoesNotJoinDatagramsOrSenders() {
        XCTAssertEqual(NMEAFramer.sentences(inDatagram: Data("$WIMWV,45.0,".utf8)), [])
        XCTAssertEqual(NMEAFramer.sentences(inDatagram: Data("R,12.0,N,A*00".utf8)), [])
        XCTAssertEqual(NMEAFramer.sentences(inDatagram: Data(first.utf8)), [first])
        XCTAssertEqual(NMEAFramer.sentences(inDatagram: Data("\(first)\r\n\(second)".utf8)), [first, second])
    }

    func testInvalidUTF8ResetsPendingBytes() {
        var framer = NMEAFramer()
        _ = framer.append(Data("$WIMWV,".utf8))
        XCTAssertEqual(framer.append(Data([0xFF, 0xC0])), [])
        XCTAssertEqual(framer.bufferedByteCount, 0)
        XCTAssertEqual(framer.append(Data("45.0,R,12.0,N,A*00\r\n".utf8)), [])
        XCTAssertEqual(framer.append(Data(first.utf8)), [first])
    }

    func testOversizedSentenceHasBoundedMemoryAndResynchronizes() {
        var framer = NMEAFramer()
        XCTAssertEqual(framer.append(Data(("$" + String(repeating: "x", count: 20_000)).utf8)), [])
        XCTAssertLessThanOrEqual(framer.bufferedByteCount, NMEAFramer.maximumSentenceBytes)
        XCTAssertEqual(framer.append(Data("\r\n\(first)\r\n".utf8)), [first])
    }

    func testLineFramingLeavesValidationToParser() {
        var framer = NMEAFramer()
        XCTAssertEqual(framer.append(Data("garbage\r\n$WIMWV,bad*ZZ\r\n".utf8)), ["$WIMWV,bad*ZZ"])
        XCTAssertEqual(framer.append(Data("$WIMWV,missing checksum\n".utf8)), ["$WIMWV,missing checksum"])
    }

    func testTrailingDataIsNotSilentlyStrippedFromCompleteLine() {
        var framer = NMEAFramer()
        XCTAssertEqual(framer.append(Data("\(first)junk\r\n".utf8)), [first + "junk"])
    }

    func testResetPreventsCrossConnectionConcatenation() {
        var framer = NMEAFramer()
        _ = framer.append(Data("$WIMWV,".utf8))
        framer.reset()
        XCTAssertEqual(framer.append(Data("45.0,R,12.0,N,A*00\r\n".utf8)), [])
    }
}
