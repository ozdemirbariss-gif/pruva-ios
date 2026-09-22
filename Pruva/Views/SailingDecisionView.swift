import SwiftUI
import Charts
import RaceCore

struct SailingDecisionView: View {
    @Bindable var store: RaceStore
    @State private var showReasons = false

    var body: some View { decision }

    @ViewBuilder private var decision: some View {
        if store.isLiveMode, let reason = store.liveReadinessMessage {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Veri bekleniyor", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(.title3, weight: .semibold))
                    Text(reason).font(.system(.footnote)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else { decisionContent }
    }

    private var decisionContent: some View {
        let a = store.analysis
        let isHold = a.recommendation == .hold
        return VStack(alignment: .leading, spacing: 15) {
            AdaptiveStack {
                AdaptiveStack(spacing: 6) {
                    Image(systemName: isHold ? "arrow.up.right" : "arrow.triangle.turn.up.right.diamond")
                    Text("ŞİMDİ NE YAPMALI?").tracking(1)
                }.font(.system(.caption2, weight: .bold)).foregroundStyle(Palette.teal)
                Spacer()
                StatusChip(title: "\(a.confidence.rawValue) güven", symbol: "chart.bar.fill", color: a.confidence == .low ? Palette.gold : Palette.teal)
            }
            StatusChip(title: isHold ? "Kontrayı koru" : "Manevraya hazırlan", symbol: isHold ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
            Text(a.title).font(.system(.title, weight: .bold)).tracking(-0.6).accessibilityIdentifier("decision-title")
            Text(store.role == .tactician ? a.message : navigatorMessage).font(.system(.subheadline)).lineSpacing(4).foregroundStyle(Palette.ink.opacity(0.8))
            Rectangle().fill(Palette.teal.opacity(0.14)).frame(height: 1)
            AdaptiveStack(alignment: .top, spacing: 9) {
                Image(systemName: "eye").font(.system(.subheadline)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Kararı ne değiştirir?").font(.system(.caption, weight: .semibold))
                    Text(a.trigger).font(.system(.caption)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }.foregroundStyle(Palette.teal)
            Button { withAnimation { showReasons.toggle() } } label: {
                AdaptiveStack {
                    Text(showReasons ? "Gerekçeleri gizle" : "Kararın arkasındaki hesap")
                    Spacer()
                    Image(systemName: showReasons ? "chevron.up" : "chevron.down")
                }.font(.system(.footnote, weight: .medium)).foregroundStyle(Palette.secondary).frame(minHeight: 44)
            }.buttonStyle(.plain)
            if showReasons {
                ForEach(Array(a.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill").font(.system(.caption)).foregroundStyle(Palette.secondary)
                }
                Text("Model kazancı \(decimal(a.expectedGainSeconds)) sn · Ek manevra maliyeti \(decimal(a.costSeconds)) sn")
                    .font(.system(.caption, weight: .medium)).foregroundStyle(Palette.teal)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
    }

    private var navigatorMessage: String {
        let a = store.analysis
        if store.isLiveMode {
            return "Hedefe \(Int(a.distanceToMark)) m. GPS rotası \(store.freshCOG.map { degrees($0.value) } ?? "—"), gerçek pruva \(store.freshHeading.map { degrees($0.value) } ?? "—"). Layline ve kalan süre ölçülen STW ile hedef seyir açısına göre modellenir."
        }
        return "Hedefe \(Int(a.distanceToMark)) m. Yerdeki rota \(degrees(a.cog)), pruva \(degrees(a.heading)). \(a.isOverstood ? "Layline dışında; direkt yaklaşma açısını kontrol edin." : "Mevcut kontra payı \(duration(a.currentTackSeconds)), diğer kontra \(duration(a.otherTackSeconds)).")"
    }

}
