import SwiftUI
import Combine
import RaceCore
import UIKit

enum AppTab: String, CaseIterable {
    case boat = "Tekne", sail = "Seyir", scenarios = "Senaryolar", log = "Seyir defteri"
    var shortLabel: String {
        switch self { case .boat: "Tekne"; case .sail: "Seyir"; case .scenarios: "Senaryo"; case .log: "Defter" }
    }
    var icon: String {
        switch self { case .boat: "antenna.radiowaves.left.and.right"; case .sail: "location.north.line"; case .scenarios: "slider.horizontal.3"; case .log: "book.closed" }
    }
}

struct RootView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(RaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.sail
    @State private var showAbout = false
    @State private var voice = VoiceCommandService()
    @State private var announcementGate = SailingAnnouncementGate()
    @State private var volumeShortcut = VolumePinShortcut()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text("pruva")
                    .font(.system(typeSize.isAccessibilitySize ? .headline : .largeTitle, weight: .bold)).tracking(-1.5)
                Spacer()
                if !typeSize.isAccessibilitySize { Button { tab = .boat } label: { AdaptiveStack(spacing: 5) {
                    Circle().fill(Palette.teal).frame(width: 5, height: 5)
                    Text(store.isLiveMode ? (store.freshPosition != nil && store.liveWind != nil ? "Canlı seyir" : "Veri bekleniyor") : "Tekneye bağlan")
                        .font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(0.5)
                }.foregroundStyle(Palette.teal).padding(.horizontal, 10).frame(minHeight: 44)
                    .background(Palette.seafoam, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Tekne bağlantısı").accessibilityIdentifier("boat-connection") }
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle").font(.system(.title3)).foregroundStyle(Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Uygulama hakkında")
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: 1200)

            if !store.sailingAlerts.isEmpty { SailingAlertBanner(alerts: store.sailingAlerts) }

            Group {
                switch tab {
                case .boat: BoatConnectionView(embedded: true)
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
            ScrollView(.horizontal) { HStack(spacing: 8) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { tab = item } } label: {
                        VStack(spacing: 6) {
                            if !typeSize.isAccessibilitySize { Image(systemName: item.icon).font(.system(.title3, weight: tab == item ? .semibold : .regular)) }
                            Text(item.shortLabel).font(.system(.caption2, weight: .semibold))
                        }.foregroundStyle(tab == item ? Palette.ink : Palette.secondary)
                            .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 10)
                            .background(tab == item ? Palette.background : .clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(item.rawValue)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                        .accessibilityIdentifier("tab-\(item.rawValue)")
                }
            }.frame(minWidth: 320) }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20).padding(.top, 9).padding(.bottom, 5)
                .frame(maxWidth: 800).background(Palette.surface)
                .frame(maxWidth: .infinity).background(Palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .overlay { if store.lineAlertActive && scenePhase == .active { LineWarningOverlay() } }
        .sheet(isPresented: $showAbout) { AboutView() }
        .onReceive(timer) { _ in store.tick(); syncVolumeShortcut(); announceSailingState() }
        .onAppear { syncVolumeShortcut() }
        .onChange(of: store.volumePinArmed) { _, _ in syncVolumeShortcut() }
        .onChange(of: store.isLiveMode) { _, _ in announcementGate.reset(); syncVolumeShortcut() }
        .onChange(of: store.committeePinCoordinate) { _, _ in announcementGate.reset() }
        .onChange(of: store.portPinCoordinate) { _, _ in announcementGate.reset() }
        .onChange(of: store.simulatedStartLine) { _, _ in announcementGate.reset() }
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

    private func announceSailingState() {
        guard scenePhase == .active, store.isLiveMode || store.simulatedStartLine != nil else { return }
        let newWarning = announcementGate.deliver(alerts: store.sailingAlerts,
            distance: store.startLineMeasurement?.distanceMeters, distanceSpeech: store.startDistanceSpeech,
            at: store.telemetryNow, speak: { voice.announce($0) })
        if newWarning { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    private func syncVolumeShortcut() {
        let enabled = scenePhase == .active && tab == .sail
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
                    Text("PRUVA").font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(Palette.ink)
                    Text("Yarış parkuru, ölçümler ve kararlar aynı ekranda.")
                        .font(.system(.subheadline)).foregroundStyle(Palette.secondary)
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
