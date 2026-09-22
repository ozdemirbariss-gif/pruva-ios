import SwiftUI
import Charts
import RaceCore

struct SailingInstrumentsView: View {
    @Bindable var store: RaceStore

    var body: some View { instruments }

    private var instruments: some View {
        Surface(padding: 16) {
            AdaptiveStack(spacing: 10) {
                Metric(label: "Rüzgâr", value: store.isLiveMode ? store.liveWind.map { decimal($0.value.speed) } ?? "—" : decimal(store.input.windSpeed), unit: "kn")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: "Rüzgâr yönü", value: store.isLiveMode ? store.liveWind.map { degrees($0.value.direction) } ?? "—" : degrees(store.input.windDirection), unit: "")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: store.isLiveMode ? "GPS · SOG" : (store.role == .tactician ? "VMG · rüzgâr" : "VMC · hedef"), value: store.isLiveMode ? store.freshSOG.map { decimal($0.value) } ?? "—" : decimal(store.role == .tactician ? store.analysis.vmg : store.analysis.vmc), unit: "kn")
            }
        }
    }

}
