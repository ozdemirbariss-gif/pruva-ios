import XCTest
@testable import Pruva

final class SailingAnnouncementTests: XCTestCase {
    func testWarningsDoNotRepeatUntilRearmedAndCooldownExpires() {
        var gate = SailingAnnouncementGate()
        let now = Date()
        let alert = SailingAlert(kind: .speed, title: "Hız düşüyor", detail: "STW")
        var messages: [String] = []
        func deliver(_ alerts: [SailingAlert], _ seconds: Double) {
            _ = gate.deliver(alerts: alerts, distance: nil, distanceSpeech: "", at: now.addingTimeInterval(seconds)) { messages.append($0); return true }
        }
        deliver([alert], 0); deliver([alert], 31)
        XCTAssertEqual(messages.count, 1)
        deliver([], 32); deliver([alert], 33)
        XCTAssertEqual(messages.count, 2)
        deliver([], 34); deliver([alert], 35)
        XCTAssertEqual(messages.count, 2)
    }

    func testBusyAudioRetriesAndDistanceNeedsTimeAndMovement() {
        var gate = SailingAnnouncementGate()
        let now = Date()
        var count = 0
        _ = gate.deliver(alerts: [], distance: 100, distanceSpeech: "100 metre", at: now) { _ in false }
        _ = gate.deliver(alerts: [], distance: 100, distanceSpeech: "100 metre", at: now) { _ in count += 1; return true }
        _ = gate.deliver(alerts: [], distance: 80, distanceSpeech: "80 metre", at: now.addingTimeInterval(10)) { _ in count += 1; return true }
        _ = gate.deliver(alerts: [], distance: 99, distanceSpeech: "99 metre", at: now.addingTimeInterval(20)) { _ in count += 1; return true }
        XCTAssertEqual(count, 1)
        _ = gate.deliver(alerts: [], distance: 80, distanceSpeech: "80 metre", at: now.addingTimeInterval(21)) { _ in count += 1; return true }
        XCTAssertEqual(count, 2)
    }
    func testStartAnnouncementSpeaksFullMetreUnitOnlyOnce() {
        var gate = SailingAnnouncementGate()
        let now = Date()
        let alert = SailingAlert(kind: .startLine, title: "Start hattı yakın", detail: "Hatta 20 m")
        var messages: [String] = []
        _ = gate.deliver(alerts: [alert], distance: 20, distanceSpeech: "Start hattına en kısa mesafe 20 metre.", at: now) { messages.append($0); return true }
        _ = gate.deliver(alerts: [alert], distance: 20, distanceSpeech: "Start hattına en kısa mesafe 20 metre.", at: now.addingTimeInterval(1)) { messages.append($0); return true }
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("20 metre"))
    }

}
