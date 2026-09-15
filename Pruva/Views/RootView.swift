import SwiftUI
import Combine
import RaceCore
import UIKit

enum AppTab: String, CaseIterable {
    case sail = "Seyir", scenarios = "Senaryolar", log = "Seyir defteri"
    var shortLabel: String {
        switch self { case .sail: "Seyir"; case .scenarios: "Senaryo"; case .log: "Defter" }
    }
    var icon: String {
        switch self { case .sail: "location.north.line"; case .scenarios: "slider.horizontal.3"; case .log: "book.closed" }
    }
}

struct RootView: View {
    @Environment(RaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.sail
    @State private var showAbout = false
    @State private var showConnection = false
    @State private var voice = VoiceCommandService()
    @State private var volumeShortcut = VolumePinShortcut()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(tab.shortLabel.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                Spacer()
                Button { showConnection = true } label: { HStack(spacing: 5) {
                    Circle().fill(Palette.teal).frame(width: 5, height: 5)
                    Text(store.isLiveMode ? (store.freshPosition != nil && store.liveWind != nil ? "NMEA · CANLI" : "VERİ BEKLENİYOR") : "NMEA BAĞLAN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5)
                }.foregroundStyle(Palette.teal).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Palette.seafoam, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Tekne bağlantısı").accessibilityIdentifier("boat-connection")
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 20)).foregroundStyle(Palette.secondary)
                        .frame(width: 36, height: 44)
                }.accessibilityLabel("Uygulama hakkında")
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: 1200)

            Group {
                switch tab {
                case .sail: SailingView().environment(voice)
                case .scenarios:
                    if store.isLiveMode {
                        ContentUnavailableView {
                            Label("Canlı seyir açık", systemImage: "antenna.radiowaves.left.and.right")
                        } description: {
                            Text("Senaryolarla çalışmak için tekne bağlantısını kapatıp simülasyona geçin.")
                        } actions: {
                            Button("Simülasyona geç") { store.leaveLiveMode() }.buttonStyle(.borderedProminent)
                        }
                    } else { ScenarioView() }
                case .log: LogbookView(onRestore: { tab = .sail })
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.background)
        .tint(Palette.teal)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { tab = item } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 20, weight: tab == item ? .semibold : .regular))
                            Text(item.shortLabel).font(.system(size: 10, weight: .semibold))
                        }.foregroundStyle(tab == item ? Palette.teal : Palette.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(tab == item ? Palette.seafoam : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(item.rawValue)")
                }
            }.padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 5)
                .frame(maxWidth: 800).background(Palette.surface)
                .frame(maxWidth: .infinity).background(Palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showConnection) { BoatConnectionView() }
        .onReceive(timer) { _ in store.tick(); syncVolumeShortcut() }
        .onAppear { syncVolumeShortcut() }
        .onChange(of: store.volumePinArmed) { _, _ in syncVolumeShortcut() }
        .onChange(of: store.isLiveMode) { _, _ in syncVolumeShortcut() }
        .onChange(of: showConnection) { _, _ in syncVolumeShortcut() }
        .onChange(of: tab) { _, _ in syncVolumeShortcut() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                voice.stop(); volumeShortcut.stop()
                store.isPlaying = false; store.disconnectBoat(); store.persist()
            } else { syncVolumeShortcut() }
        }
        .alert("Saklama bilgisi", isPresented: Binding(get: { store.storageMessage != nil }, set: { if !$0 { store.storageMessage = nil } })) {
            Button("Tamam") { store.storageMessage = nil }
        } message: { Text(store.storageMessage ?? "") }
    }

    private func syncVolumeShortcut() {
        let enabled = scenePhase == .active && tab == .sail && !showConnection
            && UIDevice.current.userInterfaceIdiom == .phone
            && store.isLiveMode && store.connection.isRunning && store.volumePinArmed
        guard enabled else { volumeShortcut.stop(); return }
        volumeShortcut.onEndpoint = { endpoint in
            let advice = store.respondToCommand(endpoint == .committee ? "komite pin" : "port pin")
            voice.speak(advice.spoken)
        }
        volumeShortcut.start()
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("PRUVA").font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(Palette.ink)
                    Text("Yarış parkuru, ölçümler ve kararlar aynı ekranda.")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "Bu sürüm")
                            Label("Çevrimdışı senaryo ve manuel girdiler", systemImage: "checkmark.circle")
                            Label("Tekne GPS / rüzgâr · NMEA TCP ve UDP", systemImage: "checkmark.circle")
                            Label("Hareketli layline ve akıntı geometrisi", systemImage: "checkmark.circle")
                            Label("Cihazda saklanan karar defteri", systemImage: "checkmark.circle")
                        }.font(.subheadline)
                    }
                    Text("Tekne bağlantısı NMEA 0183 Wi-Fi ağ geçidinden GPS ve rüzgâr alır. Harita şematiktir; deniz haritası veya parkurun tümüne yayılmış bir hava tahmini değildir. Ölçüm teknenin bulunduğu noktaya aittir. Kazanç ve güven model tahminidir. Trafik, yarış kuralları ve manevra emniyeti ekip tarafından değerlendirilir.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    Link("Karar mantığının kaynağı ↗", destination: URL(string: "https://chatgpt.com/share/6aa68eb3-a6ec-83eb-b5ba-6226bfed7c7d")!)
                }.padding(24)
            }.background(Palette.background)
                .navigationTitle("Pruva hakkında").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
