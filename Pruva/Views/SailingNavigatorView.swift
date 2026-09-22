import SwiftUI
import Charts
import RaceCore

struct SailingNavigatorView: View {
    @Bindable var store: RaceStore

    var body: some View { navigatorCard }

    @ViewBuilder private var navigatorCard: some View {
        if !store.isLiveMode || store.liveReadinessMessage == nil { navigatorContent }
    }

    private var navigatorContent: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                AdaptiveStack { Eyebrow(text: "Hedef"); Spacer(); Image(systemName: "scope").foregroundStyle(Palette.teal) }
                AdaptiveStack {
                    Metric(label: "Şamandıraya", value: "\(Int(store.analysis.distanceToMark))", unit: "m")
                    Metric(label: "Tahmini süre", value: duration(store.analysis.etaSeconds), unit: "")
                }
                Divider()
                detailRow("Mevcut kontra", store.input.tack == .starboard ? "Sancak" : "İskele")
                detailRow("Kontra payı", store.analysis.isLongTack ? "Uzun kontra" : "Kısa kontra")
                detailRow("Layline'a süre", duration(store.analysis.laylineSeconds))
                detailRow(store.isLiveMode ? "Model pruva / yer rotası" : "Pruva / Yerdeki rota", "\(degrees(store.analysis.heading)) / \(degrees(store.analysis.cog))")
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        AdaptiveStack { Text(title).foregroundStyle(Palette.secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.system(.caption))
    }

}
