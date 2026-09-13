import SwiftUI
import Combine
import RaceCore

enum AppTab: String, CaseIterable {
    case sail = "Seyir", scenarios = "Senaryolar", log = "Seyir defteri"
    var icon: String {
        switch self { case .sail: "location.north.line"; case .scenarios: "slider.horizontal.3"; case .log: "book.closed" }
    }
}

struct RootView: View {
    @Environment(RaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.sail
    @State private var showAbout = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "sailboat.fill").font(.system(size: 24)).foregroundStyle(Palette.teal)
                Text("pruva").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-1)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Palette.teal).frame(width: 5, height: 5)
                    Text("SİMÜLASYON").font(.system(size: 9, weight: .bold)).tracking(1.2)
                }.foregroundStyle(Palette.teal).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Palette.seafoam, in: Capsule())
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 20)).foregroundStyle(Palette.secondary)
                        .frame(width: 36, height: 44)
                }.accessibilityLabel("Uygulama hakkında")
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 14)
                .frame(maxWidth: 1200)

            Group {
                switch tab {
                case .sail: SailingView()
                case .scenarios: ScenarioView()
                case .log: LogbookView(onRestore: { tab = .sail })
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { tab = item } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 20, weight: tab == item ? .semibold : .regular))
                            Text(item.rawValue).font(.system(size: 10, weight: .semibold))
                        }.foregroundStyle(tab == item ? Palette.teal : Palette.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(tab == item ? Palette.seafoam.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(item.rawValue)")
                }
            }.padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 5)
                .frame(maxWidth: 800).background(.white)
                .frame(maxWidth: .infinity).background(.white)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .onReceive(timer) { _ in store.tick() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.isPlaying = false; store.persist() }
        }
        .alert("Saklama bilgisi", isPresented: Binding(get: { store.storageMessage != nil }, set: { if !$0 { store.storageMessage = nil } })) {
            Button("Tamam") { store.storageMessage = nil }
        } message: { Text(store.storageMessage ?? "") }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sailboat.fill").font(.system(size: 48)).foregroundStyle(Palette.teal)
                    Text("Daha net gör.\nBirlikte karar ver.").font(.system(size: 32, weight: .medium, design: .serif))
                    Text("Pruva, taktisyen ve navigatörün aynı parkur resmi üzerinden konuşması için tasarlandı. Her öneri, gerekçesini ve kararı değiştirecek gözlemi birlikte gösterir.")
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "Bu sürüm")
                            Label("Çevrimdışı senaryo ve manuel girdiler", systemImage: "checkmark.circle")
                            Label("Hareketli layline ve akıntı geometrisi", systemImage: "checkmark.circle")
                            Label("Cihazda saklanan karar defteri", systemImage: "checkmark.circle")
                        }.font(.subheadline)
                    }
                    Text("Harita şematiktir; deniz haritası değildir. Rüzgâr, GPS, AIS veya tekne sensörü bağlantısı yoktur. Kazanç ve güven değerleri girdi varsayımlarına dayalı model tahminleridir. Trafik, yarış kuralları ve manevra emniyeti ekip tarafından değerlendirilir.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Link("Karar mantığının kaynağı ↗", destination: URL(string: "https://chatgpt.com/share/6aa68eb3-a6ec-83eb-b5ba-6226bfed7c7d")!)
                }.padding(24)
            }.background(Palette.background)
                .navigationTitle("Pruva hakkında").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
