import SwiftUI
import RaceCore

struct LogbookView: View {
    @Environment(RaceStore.self) private var store
    var onRestore: () -> Void
    @State private var selected: DecisionEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "Her karar bir öğrenme")
                    Text("Seyir defteri").font(.system(size: 32, weight: .regular, design: .serif))
                    Text("\(store.entries.count) kayıt · Bu cihazda saklanır").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                if store.entries.isEmpty {
                    Surface(padding: 30) {
                        VStack(spacing: 20) {
                            Image(systemName: "book.pages").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Palette.teal)
                            Text("Yarış biter. İçgörü kalır.").font(.system(size: 24, weight: .regular, design: .serif))
                            Text("Seyir ekranında bir kararı notunla kaydet. Rüzgârı, konumunu ve kararın gerekçesini yeniden incele; ekibinle paylaş.")
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
                        }.padding(.vertical, 35).frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(store.entries) { entry in
                        Button { selected = entry } label: {
                            Surface {
                                VStack(alignment: .leading, spacing: 13) {
                                    HStack {
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").foregroundStyle(Palette.teal)
                                    }
                                    Text(entry.title).font(.system(size: 23, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                                    HStack(spacing: 16) {
                                        Label(degrees(entry.input.windDirection), systemImage: "wind")
                                        Text("\(decimal(entry.input.boatSpeed)) kn")
                                        Text(entry.input.leg == .upwind ? "Orsa" : "Pupa")
                                    }.font(.system(size: 11)).foregroundStyle(Palette.teal)
                                    if !entry.note.isEmpty { Text(entry.note).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(22).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
            .sheet(item: $selected) { entry in
                DecisionDetailView(entry: entry) {
                    store.restore(entry); selected = nil; onRestore()
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
                    Eyebrow(text: entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text(a.title).font(.system(size: 29, weight: .regular, design: .serif))
                    TacticalMapView(boat: MapPoint(x: input.boatPosition.east, y: input.boatPosition.north), mark: MapPoint(x: input.markPosition.east, y: input.markPosition.north), windDirection: input.windDirection, meanWindDirection: input.meanWindDirection, targetAngle: input.targetAngle, isDownwind: input.leg == .downwind, isStarboard: input.tack == .starboard, currentEast: input.currentEast, currentNorth: input.currentNorth, boatSpeed: input.boatSpeed, uncertainty: input.windUncertainty, showLaylines: true, showTrail: true)
                        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 22))
                    Text(a.message).font(.system(size: 14)).lineSpacing(4)
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Farklı rüzgârla karşılaştır", isOn: $compare).font(.system(size: 13, weight: .medium))
                            if compare {
                                Text("Kayıtlı rüzgârdan \(String(format: "%+.0f°", alternateShift))").font(.system(size: 13)).foregroundStyle(Palette.teal)
                                Slider(value: $alternateShift, in: -25...25, step: 1).accessibilityLabel("Karşılaştırma rüzgârı")
                                Text("Asıl kayıt korunur. Bu, alternatif bir senaryo hesabıdır.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    ForEach(Array(a.reasons.enumerated()), id: \.offset) { _, reason in
                        Text("• \(reason)").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    if !entry.note.isEmpty {
                        Surface { VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "Ekip notu"); Text(entry.note).font(.system(size: 14)) }.frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    ActionButton(title: "Kaydı parkurda aç", icon: "location.north.line", action: onRestore)
                    ShareLink(item: store.export(entry)) {
                        Label("Karar notunu paylaş", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(15)
                    }
                }.padding(22)
            }.background(Palette.background).foregroundStyle(Palette.ink)
                .navigationTitle("Karar incelemesi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
