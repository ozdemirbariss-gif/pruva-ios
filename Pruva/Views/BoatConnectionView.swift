import SwiftUI
import RaceCore
import UIKit

struct BoatConnectionView: View {
    @Environment(RaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var port = "10110"
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var markName = "Yarış şamandırası"
    @State private var markMessage: String?
    @State private var startMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Label("Teknenin Wi-Fi ağına bağlanın", systemImage: "wifi")
                    Text("GPS ve rüzgâr ölçümleri teknenin NMEA 0183 ağ geçidinden alınır. Telefonun GPS'i kullanılmaz.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
                Section("NMEA bağlantısı") {
                    Picker("Bağlantı", selection: $store.connectionSettings.transport) {
                        Text("TCP istemci").tag(NMEATransport.tcp)
                        Text("UDP dinle").tag(NMEATransport.udp)
                    }.disabled(store.connection.isRunning)
                    if store.connectionSettings.transport == .tcp {
                        TextField("Ağ geçidi IP / hostname", text: $store.connectionSettings.host)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("nmea-host").disabled(store.connection.isRunning)
                    }
                    TextField(store.connectionSettings.transport == .tcp ? "Sunucu portu" : "Dinlenecek port", text: $port)
                        .keyboardType(.numberPad).accessibilityIdentifier("nmea-port").disabled(store.connection.isRunning)
                    Text(store.connectionSettings.transport == .tcp
                         ? "IP ve portu ağ geçidinizin ayarlarından alın. 10110 yaygın bir başlangıç değeridir; cihazınızın ayarı esas alınır."
                         : "Ağ geçidini verileri bu iPhone/iPad'in Wi-Fi IP adresine ve seçtiğiniz porta unicast gönderecek şekilde ayarlayın. Broadcast / multicast bu bağlantıda desteklenmez.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    if store.connection.isRunning {
                        Button("Bağlantıyı kes", role: .destructive) { store.disconnectBoat() }
                    } else {
                        Button("Tekneye bağlan") {
                            store.connectionSettings.port = Int(port) ?? 0
                            store.connectBoat()
                        }.accessibilityIdentifier("connect-boat")
                    }
                    Label(store.connection.status, systemImage: store.connection.isRunning ? "antenna.radiowaves.left.and.right" : "cable.connector.slash")
                        .font(.subheadline).accessibilityIdentifier("connection-status")
                    if let error = store.connection.lastError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if store.isLiveMode {
                        Text("\(store.telemetry.acceptedSentenceCount) geçerli · \(store.telemetry.rejectedSentenceCount) reddedilen cümle")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
                if store.isLiveMode {
                    Section("Ölçümler") { LiveInstrumentStatusView() }
                }
                Section("Parkurun hedefi") {
                    TextField("Şamandıra adı", text: $markName)
                    TextField("Enlem · ondalık derece", text: $latitude).keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("mark-latitude")
                    TextField("Boylam · ondalık derece", text: $longitude).keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("mark-longitude")
                    Button("Şamandırayı kaydet") { saveMark() }.accessibilityIdentifier("save-mark")
                    Button("Şu anki GPS konumunu şamandıra yap") {
                        guard let fix = store.freshPosition else { return }
                        latitude = String(fix.value.latitude); longitude = String(fix.value.longitude)
                        saveMark()
                    }.disabled(store.freshPosition == nil)
                    if let markMessage { Text(markMessage).font(.footnote).foregroundStyle(Palette.teal) }
                    Text("Kuzey/doğu pozitif, güney/batı negatif. Harita yerel ölçekte çizilir; gerçek hedef girmeden layline önerilmez.")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
                if store.isLiveMode || store.committeePinCoordinate != nil || store.portPinCoordinate != nil {
                    Section("Start hattı") {
                        Button("Komite · starboard pin al") {
                            startMessage = store.captureStartPin(.committee)
                        }.disabled(store.freshPosition == nil).accessibilityIdentifier("connection-start-committee")
                        Button("Şamandıra · port pin al") {
                            startMessage = store.captureStartPin(.port)
                        }.disabled(store.freshPosition == nil).accessibilityIdentifier("connection-start-port")
                        Text(store.startLineLengthMeters.map { "Start hattı · \(Int($0)) m" }
                             ?? (store.committeePinCoordinate != nil || store.portPinCoordinate != nil ? "Bir pin alındı" : "İki pin bekleniyor"))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.teal)
                        if let startMessage { Text(startMessage).font(.footnote).foregroundStyle(Palette.secondary) }
                        if store.isLiveMode && UIDevice.current.userInterfaceIdiom == .phone {
                            Toggle("Ses tuşlarıyla start pini", isOn: $store.volumePinArmed)
                                .accessibilityIdentifier("volume-pin-mode")
                            Text("Pin modunda ses açma komite/starboard, ses azaltma port ucunu alır. Ses seviyesi de değişir; sınırda tuş algılanmaz. Kontrol Merkezi gibi diğer ses değişimleri de pin alabilir. Haritadaki düğmeleri yedek olarak kullanın.")
                                .font(.footnote).foregroundStyle(Palette.secondary)
                        }
                        if store.committeePinCoordinate != nil || store.portPinCoordinate != nil {
                            Button("Start pinlerini temizle", role: .destructive) {
                                store.clearStartLine(); startMessage = nil
                            }
                        }
                    }
                }
                if store.isLiveMode {
                    Section("Yarış modeli") {
                        Picker("Bacak", selection: Binding(get: { store.input.leg }, set: { leg in
                            store.input.leg = leg; store.input.targetAngle = leg == .upwind ? 45 : 145
                        })) {
                            Text("Orsa").tag(RaceLeg.upwind); Text("Pupa").tag(RaceLeg.downwind)
                        }
                        HStack { Text("Hedef rüzgâr açısı"); Spacer(); Text("\(Int(store.input.targetAngle))°") }
                        Slider(value: $store.input.targetAngle, in: store.input.leg == .upwind ? 30...65 : 110...175, step: 1)
                        Text("Layline için hedef açı teknenizin polarına göre seçilir. Bu modelde akıntı sıfır varsayılır; yer hızı (SOG) suya göre hızın (STW) yerine geçirilmez.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Section {
                        Button("Simülasyona dön") { store.leaveLiveMode(); dismiss() }
                    }
                }
            }
            .tint(Palette.teal)
            .navigationTitle("Tekne bağlantısı").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .onAppear {
                port = String(store.connectionSettings.port)
                markName = store.markName
                if let mark = store.markCoordinate { latitude = String(mark.latitude); longitude = String(mark.longitude) }
            }
        }
    }

    private func saveMark() {
        guard let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(longitude.replacingOccurrences(of: ",", with: ".")) else {
            markMessage = "Geçerli enlem ve boylam girin."; return
        }
        let coordinate = GeoCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else { markMessage = "Enlem −90…90, boylam −180…180 aralığında olmalı."; return }
        store.setMark(coordinate, name: markName)
        markMessage = "Şamandıra kaydedildi."
    }
}

struct LiveInstrumentStatusView: View {
    @Environment(RaceStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            status("GPS konumu", value: store.freshPosition.map { String(format: "%.6f, %.6f", $0.value.latitude, $0.value.longitude) }, at: store.freshPosition?.timestamp)
            status("Yer hızı · SOG", value: store.freshSOG.map { "\(decimal($0.value)) kn" }, at: store.freshSOG?.timestamp)
            status("Yer rotası · COG", value: store.freshCOG.map { degrees($0.value) }, at: store.freshCOG?.timestamp)
            status("Gerçek pruva", value: store.freshHeading.map { degrees($0.value) }, at: store.freshHeading?.timestamp)
            status("Suya göre hız · STW", value: store.freshWaterSpeed.map { "\(decimal($0.value)) kn" }, at: store.freshWaterSpeed?.timestamp)
            status("Gerçek rüzgâr", value: store.liveWind.map { "\(degrees($0.value.direction)) · \(decimal($0.value.speed)) kn" }, at: store.liveWind?.timestamp)
            if let wind = store.liveWind {
                Text("Rüzgâr kaynağı: \(wind.value.source)").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            } else if let apparent = store.telemetry.apparentWind, apparent.isFresh(at: store.telemetryNow), store.connection.isRunning {
                Text("Görünen rüzgâr: \(degrees(apparent.value.angle)) · \(decimal(apparent.value.speed)) kn. Gerçek rüzgâr yönü olarak kullanılmaz.")
                    .font(.system(size: 11)).foregroundStyle(Palette.gold)
            }
            Text("Güncellik sınırı 15 sn · Veriler bu cihazda işlenir")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }
    }

    private func status(_ name: String, value: String?, at date: Date?) -> some View {
        HStack(alignment: .top) {
            Circle().fill(value == nil ? Palette.gold : Palette.teal).frame(width: 5, height: 5).padding(.top, 5)
            Text(name).foregroundStyle(Palette.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value ?? "Veri bekleniyor").foregroundStyle(value == nil ? Palette.gold : Palette.ink)
                    .monospacedDigit().accessibilityIdentifier("live-\(name)")
                if let date { Text("\(max(0, Int(store.telemetryNow.timeIntervalSince(date)))) sn önce").font(.system(size: 9)).foregroundStyle(Palette.secondary) }
            }
        }.font(.system(size: 12))
    }
}
