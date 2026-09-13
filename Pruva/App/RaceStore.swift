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

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let directory = testing ? FileManager.default.temporaryDirectory : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent(testing ? "pruva-ui-state.json" : "pruva-state.json")
        windDirections = [input.windDirection]
        guard !testing, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedState.self, from: data)
            input = saved.input
            entries = saved.entries
            scenarioName = saved.scenarioName
            windDirections = [input.windDirection]
        } catch { storageMessage = "Önceki oturum okunamadı. Örnek parkur açıldı." }
    }

    func load(_ scenario: DemoScenario) {
        isPlaying = false
        input = scenario.input
        scenarioName = scenario.title
        windDirections = [input.windDirection]
        savedFeedback = false
        persist()
    }

    func togglePlayback() {
        isPlaying.toggle()
        replayStep = 0
        replayBaseline = relativeWind
    }

    func tick() {
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
        let entry = DecisionEntry(input: input, title: analysis.title, note: note)
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        savedFeedback = persist()
    }

    func restore(_ entry: DecisionEntry) {
        isPlaying = false
        input = entry.input
        scenarioName = "Kayıtlı karar"
        windDirections = [input.windDirection]
        persist()
    }

    @discardableResult func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(SavedState(input: input, entries: entries, scenarioName: scenarioName))
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
        SİMÜLASYON / MANUEL GİRDİ

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
}

private struct SavedState: Codable {
    let input: RaceInput
    let entries: [DecisionEntry]
    let scenarioName: String
}
