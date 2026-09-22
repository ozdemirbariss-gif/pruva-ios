import SwiftUI
import RaceCore

struct LogbookView: View {
    @Environment(RaceStore.self) private var store
    var onRestore: () -> Void
    @State private var briefing: [DecisionEntry] = []
    @State private var briefingMessage: String?
    @State private var briefingTask: Task<Void, Never>?
    @State private var preparingBriefing = false
    @State private var selected: DecisionEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("\(store.entries.count) KAYIT")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                if store.entries.isEmpty {
                    Surface(padding: 30) {
                        VStack(spacing: 20) {
                            Image(systemName: "book.pages").font(.system(.largeTitle, weight: .ultraLight)).foregroundStyle(Palette.teal)
                            Text("Henüz kayıt yok").font(.system(.title3, weight: .semibold))
                            Text("Seyir ekranından karar kaydedin.")
                                .font(.system(.footnote)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                        }.padding(.vertical, 35).frame(maxWidth: .infinity)
                    }
                } else {
                    ActionButton(title: preparingBriefing ? "İnceleme hazırlanıyor…" : "Cihazda inceleme özeti hazırla", icon: "text.book.closed") {
                        prepareBriefing()
                    }.disabled(preparingBriefing)
                    if let briefingMessage { Text(briefingMessage).font(.footnote) }
                    ForEach(briefing) { entry in
                        let analysis = RaceEngine.analyze(entry.input)
                        Surface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(journalDate(entry.date)).font(.caption)
                                Text(entry.liveContext == nil ? "Simülasyon kaydı" : "Canlı ölçüm kaydı").font(.caption)
                                Text(analysis.title).font(.headline)
                                Text(analysis.trigger).font(.body)
                                Text("Model güveni: \(analysis.confidence.rawValue)").font(.footnote)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(store.entries) { entry in
                        Button { selected = entry } label: {
                            Surface {
                                VStack(alignment: .leading, spacing: 13) {
                                    AdaptiveStack {
                                        Text(journalDate(entry.date)).font(.system(.caption2)).foregroundStyle(Palette.secondary)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").foregroundStyle(Palette.teal)
                                    }
                                    Text(entry.title).font(.system(.title3, weight: .semibold)).foregroundStyle(Palette.ink)
                                    if entry.liveContext != nil { Eyebrow(text: "Tekne NMEA kaydı") }
                                    AdaptiveStack(spacing: 16) {
                                        Label(degrees(entry.input.windDirection), systemImage: "wind")
                                        Text("\(decimal(entry.input.boatSpeed)) kn")
                                        Text(entry.input.leg == .upwind ? "Orsa" : "Pupa")
                                    }.font(.system(.caption)).foregroundStyle(Palette.teal)
                                    if !entry.note.isEmpty { Text(entry.note).font(.system(.caption)).foregroundStyle(Palette.secondary).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(22).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
            .onDisappear { briefingTask?.cancel() }
            .sheet(item: $selected) { entry in
                DecisionDetailView(entry: entry) {
                    store.restore(entry); selected = nil; onRestore()
                }
            }
    }
    private func prepareBriefing() {
        let advisor = OnDeviceLanguageAdvisor()
        guard advisor.unavailableReason == nil else { briefingMessage = advisor.unavailableReason; return }
        let snapshot = Array(store.entries.prefix(30))
        preparingBriefing = true
        briefing = []
        briefingMessage = nil
        briefingTask = Task {
            defer { preparingBriefing = false }
            do {
                let records = snapshot.map { entry in
                    let a = RaceEngine.analyze(entry.input)
                    return "\(entry.liveContext == nil ? "simulation" : "live") | \(a.title) | \(a.confidence.rawValue) | \(a.trigger)"
                }
                let indices = try await advisor.selectRecords(records)
                guard !Task.isCancelled else { return }
                briefing = indices.map { snapshot[$0] }
                briefingMessage = "Son \(snapshot.count) kayıttan cihaz içi modelin seçtiği inceleme noktaları. Metinler kayıtların motor hesabından gelir; yapılan manevrayı veya gerçekleşmiş zaman kaybını kanıtlamaz."
            } catch {
                guard !Task.isCancelled else { return }
                briefingMessage = "Cihaz içi özet hazırlanamadı. Kayıtları tek tek inceleyebilirsiniz."
            }
        }
    }

}

struct DecisionDetailView: View {
    @Environment(RaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: DecisionEntry
    let onRestore: () -> Void
    @State private var alternateShift = 0.0
    @State private var compare = false

    private var comparedInput: RaceInput {
        var input = entry.input
        if compare { input.windDirection = (input.windDirection + alternateShift + 360).truncatingRemainder(dividingBy: 360) }
        return input
    }

    var body: some View {
        let input = comparedInput
        let a = RaceEngine.analyze(input)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Eyebrow(text: journalDate(entry.date))
                    if let context = entry.liveContext {
                        Text("Tekne NMEA kaydı · SOG \(decimal(context.speedOverGround)) kn · \(context.windSource)")
                            .font(.system(.caption)).foregroundStyle(Palette.teal)
                    }
                    Text(a.title).font(.system(.title2, weight: .semibold))
                    TacticalMapView(boat: MapPoint(x: input.boatPosition.east, y: input.boatPosition.north), mark: MapPoint(x: input.markPosition.east, y: input.markPosition.north), windDirection: input.windDirection, meanWindDirection: input.meanWindDirection, targetAngle: input.targetAngle, isDownwind: input.leg == .downwind, isStarboard: input.tack == .starboard, currentEast: input.currentEast, currentNorth: input.currentNorth, boatSpeed: input.boatSpeed, uncertainty: input.windUncertainty, showLaylines: true, showTrail: true)
                        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 22))
                    Text(a.message).font(.system(.subheadline)).lineSpacing(4)
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Farklı rüzgârla karşılaştır", isOn: $compare).font(.system(.footnote, weight: .medium))
                            if compare {
                                Text("Kayıtlı rüzgârdan \(String(format: "%+.0f°", alternateShift))").font(.system(.footnote)).foregroundStyle(Palette.teal)
                                Slider(value: $alternateShift, in: -25...25, step: 1).accessibilityLabel("Karşılaştırma rüzgârı")
                                Text("Asıl kayıt korunur. Bu, alternatif bir senaryo hesabıdır.").font(.system(.caption2)).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    ForEach(Array(a.reasons.enumerated()), id: \.offset) { _, reason in
                        Text("• \(reason)").font(.system(.caption)).foregroundStyle(Palette.secondary)
                    }
                    if !entry.note.isEmpty {
                        Surface { VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "Ekip notu"); Text(entry.note).font(.system(.subheadline)) }.frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    ActionButton(title: "Kaydı parkurda aç", icon: "location.north.line", action: onRestore)
                    ShareLink(item: store.export(entry)) {
                        Label("Karar notunu paylaş", systemImage: "square.and.arrow.up").font(.system(.footnote, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(15)
                    }
                }.padding(22)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .navigationTitle("Karar incelemesi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
