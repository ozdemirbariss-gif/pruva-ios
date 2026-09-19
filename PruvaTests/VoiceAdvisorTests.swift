import XCTest
import RaceCore
@testable import Pruva

@MainActor
final class VoiceAdvisorTests: XCTestCase {
    func testTurkishCommandsAndAdviceUseCurrentModel() {
        let analysis = RaceEngine.analyze(DemoScenario.longTack.input)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Rüzgâr açtı"), .windLift)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Layline'dayız"), .layline)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Komite pin"), .committeePin)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Pin starboard"), .committeePin)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Şamandıra port pin"), .portPin)
        XCTAssertEqual(VoiceAdvisor.intent(for: "Pin end"), .portPin)

        let wind = VoiceAdvisor.advice(for: "Rüzgâr açtı", analysis: analysis,
                                       readiness: nil, measuredShift: 7)
        XCTAssertTrue(wind.detail.contains("bildirildi"))
        XCTAssertTrue(wind.detail.contains("+7°"))
        XCTAssertTrue(wind.detail.contains(analysis.message))

        let missing = VoiceAdvisor.advice(for: "Layline'dayız", analysis: analysis,
                                          readiness: "Gerçek rüzgâr bekleniyor.", measuredShift: nil)
        XCTAssertEqual(missing.title, "ÖLÇÜM EKSİK")
        XCTAssertTrue(missing.spoken.contains("Gerçek rüzgâr bekleniyor"))
    }

    func testVoicePinCommandStillRequiresFreshBoatGPS() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("pruva-voice-\(UUID()).json")
        let store = RaceStore(storageURL: fileURL)
        let advice = store.respondToCommand("Komite pin")
        XCTAssertEqual(advice.title, "PIN ALINAMADI")
        XCTAssertNil(store.committeePinCoordinate)
        XCTAssertTrue(advice.spoken.contains("GPS konumu bekleniyor"))
    }
}
