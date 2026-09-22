import SwiftUI
import RaceCore

struct StatusChip: View {
    let title: String
    let symbol: String
    var color = Palette.teal
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.09), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SailingAlertBanner: View {
    let alerts: [SailingAlert]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.symbol).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.title).font(.headline)
                        Text(alert.detail).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sailing-alert-\(alert.kind.rawValue)")
            }
        }.foregroundStyle(Palette.alert)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.alert.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.alert.opacity(0.3)))
            .padding(.horizontal, 18).padding(.bottom, 8)
    }
}

/// A gentle 2-second red pulse, with a static equivalent when Reduce Motion is on.
struct LineWarningOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0.5 : (sin(context.date.timeIntervalSinceReferenceDate * .pi) + 1) / 2
            ZStack {
                Palette.alert.opacity(0.03 + 0.09 * phase)
                RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.alert.opacity(0.4 + 0.5 * phase), lineWidth: 5)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            .accessibilityIdentifier("line-warning-overlay")
    }
}

struct SailingStartCard: View {
    @Bindable var store: RaceStore
    @Environment(VoiceCommandService.self) private var voice
    var body: some View {
        if store.isLiveMode || store.simulatedStartLine != nil {
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    AdaptiveStack {
                        Label("START HATTI", systemImage: "flag.checkered").font(.caption.weight(.bold))
                        Spacer()
                        StatusChip(title: store.isLiveMode
                                   ? (store.startLineMeasurement == nil ? "GPS / pin bekleniyor" : "GPS güncel")
                                   : "SİMÜLASYON",
                                   symbol: store.isLiveMode ? (store.startLineMeasurement == nil ? "clock" : "location.fill") : "play.circle")
                    }
                    AdaptiveStack(alignment: .firstTextBaseline) {
                        Metric(label: "Starta mesafe", value: store.startLineMeasurement.map { "\(Int($0.distanceMeters.rounded()))" } ?? "—", unit: "m")
                        Metric(label: "Hat uzunluğu", value: store.startLineLengthMeters.map { "\(Int($0.rounded()))" } ?? "—", unit: "m")
                    }
                    Text(store.startLineMeasurement?.isBeyondEndpoint == true
                         ? "Hat uzantısı · En yakın pine olan mesafe gösterilir."
                         : "İki pin arasındaki hatta en kısa mesafe. Yarış tarafı / erken start kararı değildir.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Button { voice.speak(store.startDistanceSpeech) } label: {
                        Label("Mesafeyi söyle", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.disabled(store.startLineMeasurement == nil).accessibilityIdentifier("speak-start-distance")
                }
            }.accessibilityIdentifier("start-distance-card")
        }
    }
}
