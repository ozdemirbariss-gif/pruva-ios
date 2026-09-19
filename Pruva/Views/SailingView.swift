import SwiftUI
import Charts
import RaceCore

struct SailingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(RaceStore.self) private var store
    @Environment(VoiceCommandService.self) private var voice
    @State private var showMarkEditor = false
    @State private var showLayers = false
    @State private var showPresets = false
    @State private var showReasons = false
    @State private var note = ""
    @State private var typedCommand = ""
    @FocusState private var commandFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    title
                    if store.isLiveMode {
                        HStack(spacing: 7) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text(store.freshPosition.map { String(format: "GPS  %.5f, %.5f", $0.value.latitude, $0.value.longitude) } ?? "GPS konumu bekleniyor")
                                .monospacedDigit()
                            Spacer()
                        }.font(.system(size: 11)).foregroundStyle(store.freshPosition == nil ? Palette.gold : Palette.teal)
                    }
                    if proxy.size.width > 760 {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 18) { instruments; map(height: 480); windCard }.frame(maxWidth: .infinity)
                            VStack(spacing: 18) { decision; navigatorCard; saveCard }.frame(width: 320)
                        }
                    } else {
                        instruments
                        map(height: 240)
                        decision
                        windCard
                        navigatorCard
                        saveCard
                    }
                }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 26)
                    .frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            voiceCard.padding(.horizontal, 18).padding(.vertical, 8)
                .frame(maxWidth: 800).frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
        .sheet(isPresented: $showMarkEditor) { CourseTargetView() }
        .sheet(isPresented: $showLayers) { layers }
        .sheet(isPresented: $showPresets) {
            NavigationStack {
                List(DemoScenario.allCases) { scenario in
                    Button { store.load(scenario); showPresets = false } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scenario.title).font(.headline).foregroundStyle(Palette.ink)
                            Text(scenario.subtitle).font(.subheadline).foregroundStyle(Palette.secondary)
                        }.padding(.vertical, 8)
                    }
                }.navigationTitle("Bir parkur seç")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showPresets = false } } }
            }.presentationDetents([.medium, .large])
        }
        .onAppear {
            voice.onCommand = { [weak voice] command in
                let advice = store.respondToCommand(command)
                voice?.speak(advice.spoken)
            }
        }
        .onDisappear { voice.stop(); voice.onCommand = nil }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Şimdi · Taktik öneri")
                    Text(store.isLiveMode && store.liveReadinessMessage != nil ? "Parkuru hazırla" : store.analysis.title)
                        .font(.system(size: 24, weight: .bold)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(store.isLiveMode ? "CANLI" : "SİMÜLASYON")
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Palette.teal).padding(8)
                    .background(Palette.seafoam, in: Capsule())
            }
            HStack(spacing: 12) {
                Button { showPresets = true } label: {
                    Label("Parkur seç", systemImage: "flag.checkered")
                        .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityLabel("Parkur seç").disabled(store.isLiveMode)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(CrewRole.allCases, id: \.self) { role in
                        Button { store.role = role } label: {
                            Text(role.rawValue).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(store.role == role ? Palette.ink : .clear, in: Capsule())
                                .foregroundStyle(store.role == role ? .white : Palette.secondary)
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(store.role == role ? .isSelected : [])
                    }
                }.padding(3).background(Palette.surface, in: Capsule())
            }
        }
    }

    private var instruments: some View {
        Surface(padding: 16) {
            HStack(spacing: 10) {
                Metric(label: "Rüzgâr", value: store.isLiveMode ? store.liveWind.map { decimal($0.value.speed) } ?? "—" : decimal(store.input.windSpeed), unit: "kn")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: "Rüzgâr yönü", value: store.isLiveMode ? store.liveWind.map { degrees($0.value.direction) } ?? "—" : degrees(store.input.windDirection), unit: "")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: store.isLiveMode ? "GPS · SOG" : (store.role == .tactician ? "VMG · rüzgâr" : "VMC · hedef"), value: store.isLiveMode ? store.freshSOG.map { decimal($0.value) } ?? "—" : decimal(store.role == .tactician ? store.analysis.vmg : store.analysis.vmc), unit: "kn")
            }
        }
    }

    private func map(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.input.leg == .upwind ? "Orsa parkuru" : "Pupa parkuru").font(.system(size: 18, weight: .bold))
                    Text(store.isLiveMode ? startLineStatus : "\(store.scenarioName) · \(Int(store.analysis.distanceToMark)) m")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { showMarkEditor = true } label: {
                    Label("Şamandıra", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityIdentifier("edit-course-target")
                Button { showLayers = true } label: {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 18)).foregroundStyle(Palette.teal)
                        .frame(width: 44, height: 44).background(Palette.background, in: Circle())
                }.accessibilityLabel("Harita katmanları")
            }.padding(.horizontal, 18).padding(.top, 17).padding(.bottom, 8)
            TacticalMapView(
                boat: MapPoint(x: store.input.boatPosition.east, y: store.input.boatPosition.north),
                mark: MapPoint(x: store.input.markPosition.east, y: store.input.markPosition.north),
                windDirection: store.input.windDirection, meanWindDirection: store.input.meanWindDirection,
                targetAngle: store.input.targetAngle, isDownwind: store.input.leg == .downwind,
                isStarboard: store.input.tack == .starboard,
                currentEast: store.input.currentEast, currentNorth: store.input.currentNorth,
                boatSpeed: store.input.boatSpeed, uncertainty: store.input.windUncertainty,
                showLaylines: store.showLaylines && (!store.isLiveMode || store.liveReadinessMessage == nil), showTrail: store.showTrail,
                onBoatMove: { point in
                    guard !store.isLiveMode else { return }
                    store.isPlaying = false
                    store.input.boatPosition = Point(east: point.x, north: point.y)
                    store.savedFeedback = false
                    store.persist()
                }, measuredHeading: store.measuredBoatHeading,
                windSpeed: store.isLiveMode ? store.liveWind?.value.speed : store.input.windSpeed,
                sensorMode: store.isLiveMode, windAvailable: !store.isLiveMode || store.liveWind != nil,
                boatAvailable: !store.isLiveMode || store.freshPosition != nil,
                showMark: !store.isLiveMode || store.markCoordinate != nil,
                startCommittee: store.projectedCommitteePin.map { MapPoint(x: $0.east, y: $0.north) },
                startPort: store.projectedPortPin.map { MapPoint(x: $0.east, y: $0.north) }
            ).frame(height: height)
                .id("\(store.isLiveMode)-\(store.markCoordinate?.latitude ?? 0)-\(store.markCoordinate?.longitude ?? 0)")
            if store.isLiveMode {
                HStack(spacing: 8) {
                    startPinButton("KOMİTE · STARBOARD", endpoint: .committee,
                                   captured: store.committeePinCoordinate != nil, identifier: "capture-start-committee")
                    startPinButton("PIN · PORT", endpoint: .port,
                                   captured: store.portPinCoordinate != nil, identifier: "capture-start-port")
                }.padding(.horizontal, 12).padding(.top, 12)
                if let message = store.pinFeedback {
                    Text(message).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                }
            }
            HStack {
                Text(store.isLiveMode ? "GPS konumu · Şematik parkur" : "Şematik parkur · Dokun, tekneyi taşı")
                Spacer()
                Text("Belirsizlik ±\(Int(store.input.windUncertainty))°")
            }.font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.secondary).padding(.horizontal, 18).padding(.vertical, 10)
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var startLineStatus: String {
        if let length = store.startLineLengthMeters { return "START HATTI · \(Int(length)) m" }
        if store.committeePinCoordinate != nil || store.portPinCoordinate != nil { return "START HATTI · 1/2 PIN" }
        return "NMEA · START PINLERİ BEKLENİYOR"
    }

    private func startPinButton(_ title: String, endpoint: StartEndpoint,
                                captured: Bool, identifier: String) -> some View {
        Button { store.captureStartPin(endpoint) } label: {
            HStack(spacing: 5) {
                Image(systemName: captured ? "checkmark.circle.fill" : "location.circle")
                Text(title).lineLimit(1).minimumScaleFactor(0.75)
            }.font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(captured ? Palette.background : Palette.teal)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(captured ? Palette.teal : Palette.seafoam,
                            in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(store.freshPosition == nil)
            .accessibilityIdentifier(identifier)
    }

    private var voiceCard: some View {
        Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(voice.isListening ? Palette.gold : Palette.teal)
                        .symbolEffect(.pulse, options: .repeating, isActive: voice.isListening && !reduceMotion)
                    TextField("Taktiğe sor · Rüzgâr açtı…", text: $typedCommand)
                        .font(.system(size: 15)).textInputAutocapitalization(.sentences)
                        .focused($commandFocused)
                        .submitLabel(.send).onSubmit(sendTypedCommand)
                        .accessibilityIdentifier("voice-command-input")
                    Button(action: sendTypedCommand) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).frame(width: 44, height: 44)
                    }.disabled(typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Komutu değerlendir").accessibilityIdentifier("voice-submit")
                    Button {
                        commandFocused = false
                        if voice.isListening { voice.finish() }
                        else { Task { await voice.start() } }
                    } label: {
                        Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30)).frame(width: 44, height: 44)
                    }.disabled(voice.isStarting)
                        .accessibilityLabel(voice.isStarting ? "Mikrofon hazırlanıyor" : voice.isListening ? "Dinlemeyi bitir" : "Sesli komut ver")
                        .accessibilityIdentifier("voice-listen")
                }.foregroundStyle(Palette.teal)
                if voice.isStarting || voice.isListening {
                    Text(voice.isStarting ? "MİKROFON HAZIRLANIYOR" : voice.transcript.isEmpty ? "DİNLİYOR" : voice.transcript)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.gold)
                }
                if let error = voice.errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.gold)
                }
                if let advice = store.voiceAdvice {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: advice.symbol).font(.system(size: 23))

                            .frame(width: 35, height: 35)
                            .background(cueColor(advice.tone).opacity(0.17), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(advice.title).font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                            Text(advice.detail).font(.system(size: 12)).foregroundStyle(Palette.ink)
                        }
                        Spacer(minLength: 0)
                        Button { voice.speak(advice.spoken) } label: { Image(systemName: "speaker.wave.2") }
                            .accessibilityLabel("Yanıtı tekrar seslendir")
                    }.foregroundStyle(cueColor(advice.tone))
                        .padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("voice-advice")
                }
            }
        }
    }

    private func sendTypedCommand() {
        let command = typedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        typedCommand = ""
        commandFocused = false
        let advice = store.respondToCommand(command)
        voice.speak(advice.spoken)
    }

    private func cueColor(_ tone: VoiceTone) -> Color {
        switch tone {
        case .information: Palette.teal
        case .caution, .action: Palette.gold
        }
    }

    @ViewBuilder private var decision: some View {
        if store.isLiveMode, let reason = store.liveReadinessMessage {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Veri bekleniyor", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 18, weight: .semibold))
                    Text(reason).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else { decisionContent }
    }

    private var decisionContent: some View {
        let a = store.analysis
        let isHold = a.recommendation == .hold
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isHold ? "arrow.up.right" : "arrow.triangle.turn.up.right.diamond")
                    Text("ŞİMDİ NE YAPMALI?").tracking(1)
                }.font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.teal)
                Spacer()
                Text("Model güveni: \(a.confidence.lowercased())").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Text(a.title).font(.system(size: 27, weight: .bold)).tracking(-0.6).accessibilityIdentifier("decision-title")
            Text(store.role == .tactician ? a.message : navigatorMessage).font(.system(size: 15)).lineSpacing(4).foregroundStyle(Palette.ink.opacity(0.8))
            Rectangle().fill(Palette.teal.opacity(0.14)).frame(height: 1)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "eye").font(.system(size: 14)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Kararı ne değiştirir?").font(.system(size: 11, weight: .semibold))
                    Text(a.trigger).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }.foregroundStyle(Palette.teal)
            Button { withAnimation { showReasons.toggle() } } label: {
                HStack {
                    Text(showReasons ? "Gerekçeleri gizle" : "Kararın arkasındaki hesap")
                    Spacer()
                    Image(systemName: showReasons ? "chevron.up" : "chevron.down")
                }.font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary).frame(minHeight: 44)
            }.buttonStyle(.plain)
            if showReasons {
                ForEach(Array(a.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text("Model kazancı \(decimal(a.expectedGainSeconds)) sn · Ek manevra maliyeti \(decimal(a.costSeconds)) sn")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.teal)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.seafoam, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
    }

    private var navigatorMessage: String {
        let a = store.analysis
        if store.isLiveMode {
            return "Hedefe \(Int(a.distanceToMark)) m. GPS rotası \(store.freshCOG.map { degrees($0.value) } ?? "—"), gerçek pruva \(store.freshHeading.map { degrees($0.value) } ?? "—"). Layline ve kalan süre ölçülen STW ile hedef seyir açısına göre modellenir."
        }
        return "Hedefe \(Int(a.distanceToMark)) m. Yerdeki rota \(degrees(a.cog)), pruva \(degrees(a.heading)). \(a.isOverstood ? "Layline dışında; direkt yaklaşma açısını kontrol edin." : "Mevcut kontra payı \(duration(a.currentTackSeconds)), diğer kontra \(duration(a.otherTackSeconds)).")"
    }

    private var windCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Rüzgâr sapması")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%+.0f°", store.relativeWind)).font(.system(size: 27, weight: .semibold, design: .monospaced))
                        }
                    }
                    Spacer()
                    Button { store.togglePlayback() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13))
                            .frame(width: 42, height: 42).background(Palette.seafoam, in: Circle())
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
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)°").font(.system(size: 9)) } }
                    } }.frame(height: 85)
                    .accessibilityLabel("Simülasyon rüzgâr sapmaları. Son değer \(Int(store.relativeWind)) derece.")
                HStack {
                Text(store.isLiveMode ? "SON 2 DAKİKA · NMEA" : "ÖRNEK GEÇMİŞİ").tracking(1)
                    Spacer()
                    Text("Referans \(degrees(store.input.meanWindDirection)) · \(store.isLiveMode ? "Dairesel ortalama" : "Manuel")")
                }.font(.system(size: 9)).foregroundStyle(Palette.secondary)
                if !store.isLiveMode { Slider(value: Binding(get: { store.relativeWind }, set: { value in
                    store.isPlaying = false; store.relativeWind = value; store.recordWind(); store.savedFeedback = false
                }), in: -30...30, step: 1, onEditingChanged: { editing in if !editing { store.persist() } })
                    .accessibilityLabel("Rüzgâr sapması").accessibilityIdentifier("wind-slider") }
                if store.isLiveMode, store.liveWind == nil {
                    Text("Rüzgâr güncel değil. Önceki ölçümler yalnızca geçmiş olarak gösterilir.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.gold)
                }
            }
        }
    }

    @ViewBuilder private var navigatorCard: some View {
        if !store.isLiveMode || store.liveReadinessMessage == nil { navigatorContent }
    }

    private var navigatorContent: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Eyebrow(text: "Hedef"); Spacer(); Image(systemName: "scope").foregroundStyle(Palette.teal) }
                HStack {
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
        HStack { Text(title).foregroundStyle(Palette.secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.system(size: 12))
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ekibe bir not bırak…", text: $note, axis: .vertical)
                .font(.system(size: 13)).padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("decision-note")
            ActionButton(title: store.savedFeedback ? "Seyir defterine kaydedildi" : "Kararı seyir defterine kaydet", icon: store.savedFeedback ? "checkmark" : "bookmark") {
                store.saveDecision(note: note); note = ""
            }.accessibilityIdentifier("save-decision").disabled(store.isLiveMode && store.liveReadinessMessage != nil)
        }
    }

    private var layers: some View {
        @Bindable var store = store
        return NavigationStack {
            Form {
                Section("Parkur katmanları") {
                    Toggle("Layline ve belirsizlik bandı", isOn: $store.showLaylines)
                    Toggle("Örnek yaklaşma izi", isOn: $store.showTrail)
                }
                Section { Text("Kesikli çizgiler mevcut rüzgâr ve akıntı için teorik sınırları gösterir. Belirsizlik bandı, belirlediğiniz ± rüzgâr açısıdır; ölçülmüş olasılık değildir.").font(.footnote) }
            }.navigationTitle("Harita katmanları").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showLayers = false } } }
        }.presentationDetents([.medium])
    }
}

/// A focused target editor, reachable without entering connection settings.
struct CourseTargetView: View {
    @Environment(RaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var first = ""
    @State private var second = ""
    @State private var leg = RaceLeg.upwind
    @State private var error: String?
    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, first, second }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 32)).foregroundStyle(Palette.teal)
                        Text("Bir sonraki hedef.").font(.system(size: 30, weight: .bold)).tracking(-0.8)
                        Text(store.isLiveMode ? "Şamandırayı ekle. Parkur ve taktik hesapları güncellensin." : "Simülasyon hedefini tekneye göre yön ve mesafeyle belirle.")
                            .font(.body).foregroundStyle(Palette.secondary)
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "Şamandıra adı")
                                TextField("Örn. Orsa şamandırası", text: $name)
                                    .focused($focused, equals: .name).submitLabel(.next)
                                    .onSubmit { focused = .first }.accessibilityIdentifier("target-name")
                            }
                            Divider()
                            Picker("Parkur bacağı", selection: $leg) {
                                Text("Orsa").tag(RaceLeg.upwind)
                                Text("Pupa").tag(RaceLeg.downwind)
                            }.pickerStyle(.segmented)
                            coordinateField(store.isLiveMode ? "Enlem" : "Hedef yönü", hint: store.isLiveMode ? "Örn. 40,9750" : "0–359", unit: "°", value: $first, field: .first)
                            coordinateField(store.isLiveMode ? "Boylam" : "Mesafe", hint: store.isLiveMode ? "Örn. 29,0350" : "Örn. 1500", unit: store.isLiveMode ? "°" : "m", value: $second, field: .second)
                        }
                    }
                    if store.isLiveMode {
                        ActionButton(title: "Teknenin konumunu kullan", icon: "location.fill", filled: false) {
                            guard let fix = store.freshPosition else { return }
                            first = String(fix.value.latitude); second = String(fix.value.longitude)
                            focused = nil
                        }.disabled(store.freshPosition == nil)
                        Text(store.freshPosition == nil ? "Konumla eklemek için güncel tekne GPS verisi gerekli. Koordinatları elle girebilirsin." : "Kuzey ve doğu pozitif; güney ve batı negatif. Ondalık derece kullan.")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Palette.gold).accessibilityIdentifier("target-error")
                    }
                }.padding(22).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background(Palette.background)
                .navigationTitle("Şamandıra").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Bitti") { focused = nil } }
                }
                .safeAreaInset(edge: .bottom) {
                    ActionButton(title: "Hedefi kaydet", icon: "arrow.right", action: save)
                        .accessibilityIdentifier("save-course-target")
                        .padding(20).background(.regularMaterial)
                }
                .onAppear {
                    leg = store.input.leg
                    name = store.isLiveMode ? store.markName : store.scenarioName
                    if store.isLiveMode {
                        if let mark = store.markCoordinate { first = String(mark.latitude); second = String(mark.longitude) }
                    } else {
                        let dx = store.input.markPosition.east - store.input.boatPosition.east
                        let dy = store.input.markPosition.north - store.input.boatPosition.north
                        first = String(format: "%.1f", (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
                        second = String(format: "%.0f", hypot(dx, dy))
                    }
                }
        }.tint(Palette.teal).presentationDragIndicator(.visible)
    }

    private func coordinateField(_ title: String, hint: String, unit: String, value: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            HStack {
                TextField(hint, text: value).keyboardType(.numbersAndPunctuation)
                    .focused($focused, equals: field).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                    .accessibilityLabel(title).accessibilityIdentifier(field == .first ? "target-first" : "target-second")
                Text(unit).foregroundStyle(Palette.secondary)
            }.padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        guard let a = number(first), let b = number(second), a.isFinite, b.isFinite else {
            error = "Her iki alana da geçerli bir sayı gir."; return
        }
        if store.isLiveMode {
            let coordinate = GeoCoordinate(latitude: a, longitude: b)
            guard coordinate.isValid else { error = "Enlem −90…90, boylam −180…180 arasında olmalı."; return }
            updateLeg()
            store.setMark(coordinate, name: name)
        } else {
            guard (0..<360).contains(a), (1...100_000).contains(b) else {
                error = "Yön 0–359°, mesafe 1–100.000 m arasında olmalı."; return
            }
            store.isPlaying = false
            updateLeg()
            store.input.markPosition = Point(east: store.input.boatPosition.east + sin(a * .pi / 180) * b,
                                             north: store.input.boatPosition.north + cos(a * .pi / 180) * b)
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            store.scenarioName = cleanName.isEmpty ? "Özel parkur" : cleanName
            store.savedFeedback = false
            store.persist()
        }
        dismiss()
    }

    private func updateLeg() {
        if store.input.leg != leg {
            store.input.leg = leg
            store.input.targetAngle = leg == .upwind ? 45 : 145
        }
    }
}
