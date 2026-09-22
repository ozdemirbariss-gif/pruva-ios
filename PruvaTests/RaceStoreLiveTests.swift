import XCTest
import RaceCore
@testable import Pruva

@MainActor
final class RaceStoreLiveTests: XCTestCase {
    private func makeStore() -> RaceStore {
        let store = RaceStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("pruva-test-\(UUID()).json"))
        store.connectionSettings = NMEAConnectionSettings(transport: .udp, host: "", port: Int.random(in: 40_000...60_000))
        return store
    }

    private func sentence(_ body: String) -> String {
        "$" + body + String(format: "*%02X", body.utf8.reduce(UInt8(0), ^))
    }

    private func sendFix(_ store: RaceStore, at date: Date, longitudeMinutes: String = "15.000") {
        store.receiveNMEA(sentence("GPRMC,120000,A,3650.000,N,028\(longitudeMinutes),E,7.2,315.0,140926,,,A"), at: date)
    }

    private func sendComplete(_ store: RaceStore, at date: Date) {
        sendFix(store, at: date)
        store.receiveNMEA(sentence("IIHDT,315.0,T"), at: date)
        store.receiveNMEA(sentence("IIVHW,315.0,T,,M,6.0,N,11.112,K"), at: date)
        store.receiveNMEA(sentence("WIMWD,0.0,T,,M,14.0,N,7.2022,M"), at: date)
    }

    func testVesselPositionAndGroundSpeedNeverReplaceWaterSpeed() throws {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.setMark(GeoCoordinate(latitude: 36.84, longitude: 28.25), name: "Orsa 1")
        store.connectBoat()
        sendComplete(store, at: Date())
        XCTAssertNil(store.liveReadinessMessage)
        XCTAssertEqual(try XCTUnwrap(store.freshPosition).value.latitude, 36 + 50.0 / 60, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(store.freshSOG).value, 7.2)
        XCTAssertEqual(store.input.boatSpeed, 6)
        XCTAssertEqual(store.input.currentEast, 0)
        XCTAssertEqual(store.input.currentNorth, 0)
        XCTAssertEqual(store.input.markPosition, .zero)
        XCTAssertLessThan(store.input.boatPosition.north, -700)
        XCTAssertEqual(store.input.tack, .starboard)
        XCTAssertEqual(store.measuredBoatHeading, 315)
    }

    func testMissingWaterSpeedBlocksAdviceButKeepsGPSAndWindVisible() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let date = Date()
        sendFix(store, at: date)
        store.receiveNMEA(sentence("IIHDT,315,T"), at: date)
        store.receiveNMEA(sentence("WIMWD,0,T,,M,14,N,,M"), at: date)
        XCTAssertNotNil(store.freshSOG)
        XCTAssertNotNil(store.liveWind)
        XCTAssertEqual(store.input.boatSpeed, 0)
        XCTAssertTrue(store.liveReadinessMessage?.contains("VHW") == true)
        store.saveDecision()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testGPSUpdatesCannotKeepOldWindFresh() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let start = Date()
        sendComplete(store, at: start)
        XCTAssertNotNil(store.liveWind)
        sendFix(store, at: start.addingTimeInterval(16))
        XCTAssertNotNil(store.freshPosition)
        XCTAssertNil(store.liveWind)
        XCTAssertNotNil(store.liveReadinessMessage)
        store.saveDecision()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testInvalidFixImmediatelySuppressesAdviceAndMarker() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let date = Date()
        sendComplete(store, at: date)
        store.receiveNMEA(sentence("GPRMC,120001,V,,,,,,,140926,,,N"), at: date.addingTimeInterval(1))
        XCTAssertNil(store.freshPosition)
        XCTAssertNil(store.freshSOG)
        XCTAssertNotNil(store.liveReadinessMessage)
    }

    func testRestartAndSimulationSwitchDoNotRecycleLiveSamples() {
        let store = makeStore()
        let original = store.input
        store.connectBoat()
        sendComplete(store, at: Date())
        store.connectBoat()
        XCTAssertNil(store.freshPosition)
        XCTAssertNil(store.liveWind)
        XCTAssertTrue(store.windHistory.isEmpty)
        store.leaveLiveMode()
        XCTAssertFalse(store.isLiveMode)
        XCTAssertFalse(store.connection.isRunning)
        XCTAssertEqual(store.input, original)
    }

    func testWindMeanWrapsNorthAndUsesOnlyLiveSamples() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let date = Date()
        store.receiveNMEA(sentence("WIMWD,359,T,,M,14,N,,M"), at: date)
        store.receiveNMEA(sentence("WIMWD,1,T,,M,14,N,,M"), at: date.addingTimeInterval(1))
        XCTAssertEqual(store.input.meanWindDirection, 0, accuracy: 0.001)
        XCTAssertEqual(store.windHistory.count, 2)
        XCTAssertEqual(store.windHistory[0], -1, accuracy: 0.001)
    }

    func testLiveDecisionKeepsProvenanceAndCannotReopenAsLiveConnection() throws {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.setMark(GeoCoordinate(latitude: 36.84, longitude: 28.25), name: "1")
        store.connectBoat()
        sendComplete(store, at: Date())
        store.saveDecision(note: "Test notu")
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertNotNil(entry.liveContext)
        XCTAssertTrue(store.export(entry).contains("TEKNE NMEA VERİSİ"))
        store.restore(entry)
        XCTAssertFalse(store.connection.isRunning)
        XCTAssertFalse(store.isLiveMode)
        XCTAssertEqual(store.input, entry.input)
        XCTAssertEqual(store.scenarioName, "Canlı kayıt · inceleme")
    }

    func testGPSWithoutConfiguredMarkDoesNotInventRaceCourse() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        sendComplete(store, at: Date())
        XCTAssertNil(store.markCoordinate)
        XCTAssertTrue(store.liveReadinessMessage?.contains("şamandıranın koordinatını") == true)
    }

    func testStartPinsUseTwoDistinctLiveFixesAndSurviveReload() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("pruva-start-\(UUID()).json")
        let store = RaceStore(storageURL: fileURL)
        store.connectionSettings = NMEAConnectionSettings(transport: .udp, host: "", port: Int.random(in: 40_000...60_000))
        defer { store.disconnectBoat() }
        store.setMark(GeoCoordinate(latitude: 36.84, longitude: 28.25), name: "Orsa 1")
        store.connectBoat()
        let now = Date()
        sendFix(store, at: now)

        XCTAssertTrue(store.captureStartPin(.committee).succeeded)
        XCTAssertNil(store.startLineLengthMeters)
        XCTAssertTrue(store.captureStartPin(.port).message.contains("aynı konumda"))
        XCTAssertNil(store.portPinCoordinate)

        sendFix(store, at: now.addingTimeInterval(1), longitudeMinutes: "15.060")
        XCTAssertTrue(store.captureStartPin(.port).succeeded)
        let length = try XCTUnwrap(store.startLineLengthMeters)
        XCTAssertGreaterThan(length, 80)
        XCTAssertLessThan(length, 100)
        XCTAssertNotNil(store.projectedCommitteePin)
        XCTAssertNotNil(store.projectedPortPin)

        let reloaded = RaceStore(storageURL: fileURL)
        XCTAssertEqual(reloaded.committeePinCoordinate, store.committeePinCoordinate)
        XCTAssertEqual(reloaded.portPinCoordinate, store.portPinCoordinate)
        XCTAssertEqual(reloaded.startLineLengthMeters, length)

        store.clearStartLine()
        XCTAssertNil(store.committeePinCoordinate)
        XCTAssertNil(store.portPinCoordinate)
        XCTAssertNil(store.startLineLengthMeters)
    }

    func testStartPinCaptureRequiresFreshBoatGPS() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        XCTAssertNil(store.committeePinCoordinate)
        XCTAssertTrue(store.captureStartPin(.committee).message.contains("GPS konumu bekleniyor"))
        store.connectBoat()
        XCTAssertTrue(store.captureStartPin(.committee).message.contains("GPS konumu bekleniyor"))
        let now = Date()
        sendFix(store, at: now)
        XCTAssertTrue(store.captureStartPin(.committee).succeeded)
        store.telemetryNow = now.addingTimeInterval(16)
        XCTAssertTrue(store.captureStartPin(.port).message.contains("GPS konumu bekleniyor"))
        XCTAssertNil(store.portPinCoordinate)
    }
    func testPersistenceRestoresSimulationAndSettingsWithoutOpeningNetwork() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("persist-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RaceStore(storageURL: url)
        store.input.windSpeed = 21
        store.scenarioName = "Özel parkur"
        store.connectionSettings = NMEAConnectionSettings(transport: .tcp, host: "127.0.0.1", port: 10110)
        store.saveDecision(note: "Ekip notu")
        let savedInput = store.input
        store.connectBoat()
        store.input.windSpeed = 4
        XCTAssertTrue(store.persist())
        store.disconnectBoat()
        let restored = RaceStore(storageURL: url)
        XCTAssertEqual(restored.input, savedInput)
        XCTAssertEqual(restored.scenarioName, "Özel parkur")
        XCTAssertEqual(restored.connectionSettings, store.connectionSettings)
        XCTAssertEqual(restored.entries.first?.note, "Ekip notu")
        XCTAssertFalse(restored.isLiveMode)
        XCTAssertFalse(restored.connection.isRunning)
    }

    func testCorruptStorageFallsBackAndWriteFailureIsVisible() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        let store = RaceStore(storageURL: url)
        XCTAssertNotNil(store.storageMessage)
        XCTAssertEqual(store.input, DemoScenario.longTack.input)
        let invalid = RaceStore(storageURL: url.appendingPathComponent("missing.json"))
        invalid.saveDecision()
        XCTAssertFalse(invalid.savedFeedback)
        XCTAssertNotNil(invalid.storageMessage)
    }

    func testPinDistanceBoundsDoNotReplaceExistingEndpoint() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let now = Date()
        sendFix(store, at: now)
        XCTAssertTrue(store.captureStartPin(.committee).succeeded)
        sendFix(store, at: now.addingTimeInterval(1), longitudeMinutes: "15.060")
        XCTAssertTrue(store.captureStartPin(.port).succeeded)
        let original = store.portPinCoordinate
        sendFix(store, at: now.addingTimeInterval(2), longitudeMinutes: "15.000")
        XCTAssertFalse(store.captureStartPin(.port).succeeded)
        XCTAssertEqual(store.portPinCoordinate, original)
        sendFix(store, at: now.addingTimeInterval(3), longitudeMinutes: "25.000")
        XCTAssertFalse(store.captureStartPin(.port).succeeded)
        XCTAssertEqual(store.portPinCoordinate, original)
    }

    func testDisconnectSuppressesLiveAdviceAndPlaybackUntilExplicitSimulation() {
        let store = makeStore()
        store.togglePlayback()
        store.connectBoat()
        XCTAssertFalse(store.isPlaying)
        sendComplete(store, at: Date())
        store.disconnectBoat()
        XCTAssertTrue(store.isLiveMode)
        XCTAssertNil(store.freshPosition)
        XCTAssertNil(store.liveWind)
        store.togglePlayback()
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.respondToCommand("durum").title, "ÖLÇÜM EKSİK")
        store.leaveLiveMode()
        store.togglePlayback()
        XCTAssertTrue(store.isPlaying)
    }

    func testStartDistanceNeedsOnlyPinsAndFreshGPSAndExpires() throws {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let now = Date()
        sendFix(store, at: now)
        XCTAssertTrue(store.captureStartPin(.committee).succeeded)
        XCTAssertNil(store.startLineMeasurement)
        sendFix(store, at: now.addingTimeInterval(1), longitudeMinutes: "15.060")
        XCTAssertTrue(store.captureStartPin(.port).succeeded)
        XCTAssertEqual(try XCTUnwrap(store.startLineMeasurement).distanceMeters, 0, accuracy: 0.01)
        XCTAssertNotNil(store.liveReadinessMessage) // no wind/heading/course required for distance
        XCTAssertTrue(store.lineAlertActive)
        XCTAssertTrue(store.respondToCommand("start mesafesi").spoken.contains("0 metre"))
        store.telemetryNow = now.addingTimeInterval(17)
        store.updateSailingAlerts()
        XCTAssertNil(store.startLineMeasurement)
        XCTAssertFalse(store.lineAlertActive)
        XCTAssertTrue(store.respondToCommand("start mesafesi").spoken.contains("güncel"))
        store.disconnectBoat()
        XCTAssertTrue(store.sailingAlerts.isEmpty)
    }

    func testLiveSpeedDropIsDetectedAndDisconnectClearsIt() {
        let store = makeStore()
        defer { store.disconnectBoat() }
        store.connectBoat()
        let now = Date()
        for second in 0...16 {
            let speed = second <= 10 ? "6.0" : "4.0"
            store.receiveNMEA(sentence("IIVHW,315.0,T,,M,\(speed),N,,K"), at: now.addingTimeInterval(Double(second)))
        }
        XCTAssertTrue(store.sailingAlerts.contains { $0.kind == .speed })
        store.disconnectBoat()
        XCTAssertFalse(store.sailingAlerts.contains { $0.kind == .speed })
    }

    func testSimulatedSpeedDeclineWarnsOnlyAfterWarmupAndClearsOnScenarioChange() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1000)
        for second in 0...10 { store.telemetryNow = now.addingTimeInterval(Double(second)); store.updateSailingAlerts() }
        store.input.boatSpeed = 4
        for second in 11...16 { store.telemetryNow = now.addingTimeInterval(Double(second)); store.updateSailingAlerts() }
        XCTAssertTrue(store.sailingAlerts.contains { $0.kind == .speed && $0.detail.contains("SİM") })
        store.load(.downwind)
        XCTAssertFalse(store.sailingAlerts.contains { $0.kind == .speed })
    }

    func testStartPracticeUsesLocalLineWithoutLivePins() throws {
        let store = makeStore()
        store.load(.startApproach)
        XCTAssertFalse(store.isLiveMode)
        XCTAssertNil(store.committeePinCoordinate)
        XCTAssertNil(store.portPinCoordinate)
        XCTAssertEqual(try XCTUnwrap(store.startLineLengthMeters), 120, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(store.startLineMeasurement).distanceMeters, 120, accuracy: 0.001)
        XCTAssertTrue(store.startDistanceSpeech.contains("Simülasyon"))

        store.input.boatPosition = Point(east: 0, north: -25)
        store.updateSailingAlerts()
        XCTAssertTrue(store.sailingAlerts.contains { $0.kind == .startLine })
        store.input.boatPosition = Point(east: 0, north: -50)
        store.updateSailingAlerts()
        XCTAssertFalse(store.sailingAlerts.contains { $0.kind == .startLine })

        store.connectBoat()
        XCTAssertNil(store.startLineMeasurement)
        store.leaveLiveMode()
        XCTAssertEqual(try XCTUnwrap(store.startLineMeasurement).distanceMeters, 50, accuracy: 0.001)
        XCTAssertNil(store.committeePinCoordinate)
        XCTAssertNil(store.portPinCoordinate)
    }

    func testSpeedPracticeReachesWarningAndCanReset() {
        let store = makeStore()
        store.load(.startApproach)
        let now = Date(timeIntervalSince1970: 1000)
        store.startSpeedDrill(at: now)
        for second in 1...15 { store.tick(at: now.addingTimeInterval(Double(second))) }
        XCTAssertFalse(store.sailingAlerts.contains { $0.kind == .speed })
        store.tick(at: now.addingTimeInterval(16))
        XCTAssertTrue(store.sailingAlerts.contains { $0.kind == .speed && $0.detail.contains("SİM") })
        XCTAssertEqual(store.input.boatSpeed, 4.8, accuracy: 0.001)
        store.resetSpeedDrill()
        XCTAssertFalse(store.sailingAlerts.contains { $0.kind == .speed })
        XCTAssertEqual(store.input.boatSpeed, 6.4, accuracy: 0.001)
    }

}
