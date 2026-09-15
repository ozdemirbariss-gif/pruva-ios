import Foundation
import Observation
import RaceCore

enum CrewRole: String, CaseIterable { case tactician = "Taktisyen", navigator = "Navigatör" }

struct DecisionEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var input: RaceInput
    var title: String
    var note: String
    var liveContext: LiveDecisionContext? = nil
}

struct LiveDecisionContext: Codable {
    var gps: GeoCoordinate
    var mark: GeoCoordinate
    var speedOverGround: Double
    var windSource: String
    var receivedAt: Date
}

@Observable
@MainActor
final class RaceStore {
    var input: RaceInput = DemoScenario.longTack.input
    var scenarioName = DemoScenario.longTack.title
    var role: CrewRole = .tactician
    var showLaylines = true
    var showTrail = true
    var isPlaying = false
    var entries: [DecisionEntry] = []
    var storageMessage: String?
    var savedFeedback = false
    let connection = NMEAConnection()
    var connectionSettings = NMEAConnectionSettings()
    var telemetry = MarineTelemetry()
    var isLiveMode = false
    var telemetryNow = Date()
    var markCoordinate: GeoCoordinate?
    var markName = "Yarış şamandırası"
    private var localOrigin: GeoCoordinate?
    private var simulationInput = DemoScenario.longTack.input
    private var simulationName = DemoScenario.longTack.title
    private var liveWindSamples: [TelemetrySample<Double>] = []
    private var windDirections: [Double] = []
    var windHistory: [Double] {
        windDirections.map { RaceEngine.signedAngle($0 - input.meanWindDirection) }
    }
    private var replayStep = 0
    private var replayBaseline = 0.0
    private let fileURL: URL

    var analysis: RaceAnalysis { RaceEngine.analyze(input) }
    var relativeWind: Double {
        get { (input.windDirection - input.meanWindDirection + 540).truncatingRemainder(dividingBy: 360) - 180 }
        set { input.windDirection = (input.meanWindDirection + newValue + 360).truncatingRemainder(dividingBy: 360) }
    }

    init(storageURL: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let directory = testing ? FileManager.default.temporaryDirectory : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = storageURL ?? directory.appendingPathComponent(testing ? "pruva-ui-state.json" : "pruva-state.json")
        windDirections = [input.windDirection]
        connection.onSentence = { [weak self] sentence, receivedAt in
            self?.receiveNMEA(sentence, at: receivedAt)
        }
        guard !testing, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedState.self, from: data)
            input = saved.input
            entries = saved.entries
            scenarioName = saved.scenarioName
            windDirections = [input.windDirection]
            connectionSettings = saved.connectionSettings ?? NMEAConnectionSettings()
            markCoordinate = saved.markCoordinate
            markName = saved.markName ?? "Yarış şamandırası"
        } catch { storageMessage = "Önceki oturum okunamadı. Örnek parkur açıldı." }
    }

    func load(_ scenario: DemoScenario) {
        leaveLiveMode()
        isPlaying = false
        input = scenario.input
        scenarioName = scenario.title
        windDirections = [input.windDirection]
        savedFeedback = false
        persist()
    }

    func togglePlayback() {
        guard !isLiveMode else { return }
        isPlaying.toggle()
        replayStep = 0
        replayBaseline = relativeWind
    }

    func tick() {
        telemetryNow = Date()
        if isLiveMode { updateLiveInput(); return }
        guard isPlaying else { return }
        replayStep += 1
        relativeWind = max(-30, min(30, replayBaseline + sin(Double(replayStep) * .pi / 18) * 12))
        recordWind()
    }

    func recordWind() {
        windDirections.append(input.windDirection)
        if windDirections.count > 45 { windDirections.removeFirst(windDirections.count - 45) }
    }

    func saveDecision(note: String = "") {
        guard !isLiveMode || liveReadinessMessage == nil else { return }
        var entry = DecisionEntry(input: input, title: analysis.title, note: note)
        if isLiveMode, let gps = freshPosition, let mark = markCoordinate, let wind = liveWind, let speed = freshSOG {
            entry.liveContext = LiveDecisionContext(gps: gps.value, mark: mark, speedOverGround: speed.value,
                                                   windSource: wind.value.source, receivedAt: gps.timestamp)
        }
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        savedFeedback = persist()
    }

    func restore(_ entry: DecisionEntry) {
        leaveLiveMode()
        isPlaying = false
        input = entry.input
        scenarioName = entry.liveContext == nil ? "Kayıtlı karar" : "Canlı kayıt · inceleme"
        windDirections = [input.windDirection]
        persist()
    }

    @discardableResult func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(SavedState(input: isLiveMode ? simulationInput : input, entries: entries,
                scenarioName: isLiveMode ? simulationName : scenarioName, connectionSettings: connectionSettings,
                markCoordinate: markCoordinate, markName: markName))
            try data.write(to: fileURL, options: .atomic)
            storageMessage = nil
            return true
        } catch {
            storageMessage = "Kayıt saklanamadı: \(error.localizedDescription)"
            return false
        }
    }

    func export(_ entry: DecisionEntry) -> String {
        let a = RaceEngine.analyze(entry.input)
        return """
        PRUVA · Karar notu
        \(entry.date.formatted(date: .abbreviated, time: .shortened))
        \(entry.liveContext == nil ? "SİMÜLASYON / MANUEL GİRDİ" : "TEKNE NMEA VERİSİ · KAYITLI KARAR")

        \(a.title)
        \(a.message)

        Kararı değiştirecek gözlem: \(a.trigger)
        Rüzgâr: \(degrees(entry.input.windDirection)) · \(decimal(entry.input.windSpeed)) kn
        Ortalama: \(degrees(entry.input.meanWindDirection))
        Şamandıra: \(Int(a.distanceToMark)) m
        Tahmini kazanç: \(decimal(a.expectedGainSeconds)) sn · Maliyet: \(decimal(a.costSeconds)) sn

        Ekip notu: \(entry.note.isEmpty ? "—" : entry.note)
        """
    }

    var freshPosition: TelemetrySample<GeoCoordinate>? { fresh(telemetry.position) }
    var freshSOG: TelemetrySample<Double>? { fresh(telemetry.speedOverGround) }
    var freshCOG: TelemetrySample<Double>? { fresh(telemetry.courseOverGround) }
    var freshHeading: TelemetrySample<Double>? { fresh(telemetry.trueHeading) }
    var freshWaterSpeed: TelemetrySample<Double>? { fresh(telemetry.speedThroughWater) }
    var liveWind: TelemetrySample<WindObservation>? {
        connection.isRunning ? telemetry.trueWind(at: telemetryNow) : nil
    }
    var measuredBoatHeading: Double? { freshHeading?.value ?? freshCOG?.value }
    var liveReadinessMessage: String? {
        guard connection.isRunning else { return "Tekne bağlantısı kapalı. TCP veya UDP bağlantısını başlatın." }
        guard let fix = freshPosition, freshSOG != nil else { return "Güncel GPS konumu ve yer hızı bekleniyor. 15 saniyeyi geçen veriler kullanılmaz." }
        guard liveWind != nil else { return "Gerçek rüzgâr bekleniyor. MWD veya MWV(T) ile gerçek pruva verisi gerekir." }
        guard freshHeading != nil else { return "Kontrayı belirlemek için gerçek pruva (HDT / VHW) bekleniyor. GPS rotası pruva yerine kullanılmaz." }
        guard freshWaterSpeed != nil else { return "Layline hesabı için suya göre hız (VHW) bekleniyor. GPS yer hızı ayrı gösterilir." }
        guard let mark = markCoordinate else { return "Gerçek parkur için şamandıranın koordinatını ekleyin." }
        guard fix.value.projected(relativeTo: mark) != nil else { return "Şamandıra bu yerel parkur hesabı için çok uzak veya koordinatı geçersiz." }
        return nil
    }

    private func fresh<T>(_ value: TelemetrySample<T>?) -> TelemetrySample<T>? {
        guard connection.isRunning, let value, value.isFresh(at: telemetryNow) else { return nil }
        return value
    }

    func connectBoat() {
        if !isLiveMode { simulationInput = input; simulationName = scenarioName }
        isLiveMode = true
        isPlaying = false
        telemetry.reset()
        localOrigin = nil
        liveWindSamples = []
        windDirections = []
        telemetryNow = Date()
        input = RaceInput(boatSpeed: 0, markPosition: .zero)
        scenarioName = markName
        connection.start(connectionSettings)
        savedFeedback = false
        persist()
    }

    func disconnectBoat() {
        connection.stop()
        telemetry.reset()
        liveWindSamples = []
        windDirections = []
        savedFeedback = false
    }

    func leaveLiveMode() {
        guard isLiveMode else { return }
        disconnectBoat()
        isLiveMode = false
        input = simulationInput
        scenarioName = simulationName
        windDirections = [input.windDirection]
    }

    func receiveNMEA(_ sentence: String, at date: Date) {
        guard isLiveMode, connection.isRunning else { return }
        telemetryNow = date
        if telemetry.consume(sentence, at: date) { updateLiveInput() }
    }

    func updateLiveInput() {
        if let fix = freshPosition {
            if localOrigin == nil { localOrigin = fix.value }
            if let origin = markCoordinate ?? localOrigin, let point = fix.value.projected(relativeTo: origin) {
                input.boatPosition = point
                input.markPosition = .zero
            }
        }
        input.boatSpeed = freshWaterSpeed?.value ?? 0
        if let wind = liveWind {
            input.windDirection = wind.value.direction
            input.windSpeed = wind.value.speed
            if liveWindSamples.last?.timestamp != wind.timestamp {
                liveWindSamples.append(TelemetrySample(value: wind.value.direction, timestamp: wind.timestamp))
            }
            liveWindSamples.removeAll { telemetryNow.timeIntervalSince($0.timestamp) > 120 }
            if liveWindSamples.count > 240 { liveWindSamples.removeFirst(liveWindSamples.count - 240) }
            windDirections = liveWindSamples.map(\.value)
            input.meanWindDirection = RaceEngine.circularMean(windDirections) ?? wind.value.direction
            if let heading = freshHeading {
                let relative = RaceEngine.signedAngle(wind.value.direction - heading.value)
                input.tack = relative >= 0 ? .starboard : .port
            }
        }
    }

    func setMark(_ coordinate: GeoCoordinate, name: String) {
        guard coordinate.isValid else { return }
        markCoordinate = coordinate
        markName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Yarış şamandırası" : name
        if isLiveMode { scenarioName = markName; updateLiveInput() }
        persist()
    }
}

private struct SavedState: Codable {
    let input: RaceInput
    let entries: [DecisionEntry]
    let scenarioName: String
    var connectionSettings: NMEAConnectionSettings? = nil
    var markCoordinate: GeoCoordinate? = nil
    var markName: String? = nil
}
