import SwiftUI
import Charts
import RaceCore

struct SailingWindView: View {
    @Bindable var store: RaceStore

    var body: some View { windCard }

    private var windCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                AdaptiveStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Rüzgâr sapması")
                        AdaptiveStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%+.0f°", store.relativeWind)).font(.system(.title, design: .monospaced, weight: .semibold))
                        }
                    }
                    Spacer()
                    Button { store.togglePlayback() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(.footnote))
                            .frame(minWidth: 44, minHeight: 44).background(Palette.seafoam, in: Circle())
                    }.accessibilityLabel(store.isPlaying ? "Simülasyonu duraklat" : "Rüzgâr simülasyonunu oynat").disabled(store.isLiveMode)
                }
                Chart {
                    RuleMark(y: .value("Ortalama", 0)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Palette.secondary.opacity(0.45))
                    ForEach(Array(store.windHistory.enumerated()), id: \.offset) { index, wind in
                        AreaMark(x: .value("Örnek", index), yStart: .value("Ortalama", 0), yEnd: .value("Shift", wind))
                            .interpolationMethod(.catmullRom).foregroundStyle(Palette.teal.opacity(0.07))
                        LineMark(x: .value("Örnek", index), y: .value("Shift", wind))
                            .interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.2)).foregroundStyle(Palette.teal)
                        if index == store.windHistory.count - 1 {
                            PointMark(x: .value("Örnek", index), y: .value("Shift", wind))
                                .symbolSize(22).foregroundStyle(Palette.teal)
                        }
                    }
                }.chartYScale(domain: -30...30).chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(values: [-20, 0, 20]) { value in
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)°").font(.system(.caption2)) } }
                    } }.frame(height: 85)
                    .accessibilityLabel(store.isLiveMode ? "Ölçülen rüzgâr sapması geçmişi" : "Simülasyon rüzgâr sapması geçmişi")
                    .accessibilityValue(store.windHistory.last.map { "Son değer \(Int($0)) derece" } ?? "Örnek yok")
                AdaptiveStack {
                Text(store.isLiveMode ? "SON 2 DAKİKA · NMEA" : "ÖRNEK GEÇMİŞİ").tracking(1)
                    Spacer()
                    Text("Referans \(degrees(store.input.meanWindDirection)) · \(store.isLiveMode ? "Dairesel ortalama" : "Manuel")")
                }.font(.system(.caption2)).foregroundStyle(Palette.secondary)
                if !store.isLiveMode { Slider(value: Binding(get: { store.relativeWind }, set: { value in
                    store.isPlaying = false; store.relativeWind = value; store.recordWind(); store.savedFeedback = false
                }), in: -30...30, step: 1, onEditingChanged: { editing in if !editing { store.persist() } })
                    .accessibilityLabel("Rüzgâr sapması").accessibilityValue("\(Int(store.relativeWind)) derece").accessibilityIdentifier("wind-slider") }
                if store.isLiveMode, store.liveWind == nil {
                    Text("Rüzgâr güncel değil. Önceki ölçümler yalnızca geçmiş olarak gösterilir.")
                        .font(.system(.caption, weight: .medium)).foregroundStyle(Palette.gold)
                }
            }
        }
    }

}
