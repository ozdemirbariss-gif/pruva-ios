import SwiftUI
import Charts
import RaceCore

struct SailingView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(RaceStore.self) private var store
    @Environment(VoiceCommandService.self) private var voice
    @State private var showMarkEditor = false
    @State private var showLayers = false
    @State private var showPresets = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    title
                    SailingStartCard(store: store)
                    if typeSize.isAccessibilitySize { SailingVoiceView(store: store) }
                    if store.isLiveMode {
                        AdaptiveStack(spacing: 7) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text(store.freshPosition.map { String(format: "GPS  %.5f, %.5f", $0.value.latitude, $0.value.longitude) } ?? "GPS konumu bekleniyor")
                                .monospacedDigit()
                            Spacer()
                        }.font(.system(.caption)).foregroundStyle(store.freshPosition == nil ? Palette.gold : Palette.teal)
                    }
                    if proxy.size.width > 760 && !typeSize.isAccessibilitySize {
                        AdaptiveStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 18) { SailingInstrumentsView(store: store); map(height: 480); SailingWindView(store: store) }.frame(maxWidth: .infinity)
                            VStack(spacing: 18) { SailingDecisionView(store: store); SailingNavigatorView(store: store); SailingSaveView(store: store) }.frame(width: 320)
                        }
                    } else {
                        SailingInstrumentsView(store: store)
                        map(height: 240)
                        SailingDecisionView(store: store)
                        SailingWindView(store: store)
                        SailingNavigatorView(store: store)
                        SailingSaveView(store: store)
                    }
                }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 26)
                    .frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize { SailingVoiceView(store: store).padding(.horizontal, 18).padding(.vertical, 8)
                .frame(maxWidth: 800).frame(maxWidth: .infinity)
                .background(.regularMaterial) }
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

    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdaptiveStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Şimdi · Taktik öneri")
                    Text(store.isLiveMode && store.liveReadinessMessage != nil ? "Parkuru hazırla" : store.analysis.title)
                        .font(.system(.title2, weight: .bold)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(store.isLiveMode ? "CANLI" : "SİMÜLASYON")
                    .font(.system(.caption2, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Palette.teal).padding(8)
                    .background(Palette.seafoam, in: Capsule())
            }
            AdaptiveStack(spacing: 12) {
                Button { showPresets = true } label: {
                    Label("Parkur seç", systemImage: "flag.checkered")
                        .font(.system(.footnote, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityLabel("Parkur seç").disabled(store.isLiveMode)
                Spacer(minLength: 0)
                AdaptiveStack(spacing: 2) {
                    ForEach(CrewRole.allCases, id: \.self) { role in
                        Button { store.role = role } label: {
                            Text(role.rawValue).font(.system(.caption, weight: .semibold))
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

    private func map(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            AdaptiveStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.input.leg == .upwind ? "Orsa parkuru" : "Pupa parkuru").font(.system(.title3, weight: .bold))
                    Text(store.isLiveMode ? startLineStatus : "\(store.scenarioName) · \(Int(store.analysis.distanceToMark)) m")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { showMarkEditor = true } label: {
                    Label("Şamandıra", systemImage: "plus.circle.fill")
                        .font(.system(.footnote, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityIdentifier("edit-course-target")
                Button { showLayers = true } label: {
                    Image(systemName: "square.3.layers.3d").font(.system(.title3)).foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44).background(Palette.background, in: Circle())
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
                AdaptiveStack(spacing: 8) {
                    startPinButton("KOMİTE · STARBOARD", endpoint: .committee,
                                   captured: store.committeePinCoordinate != nil, identifier: "capture-start-committee")
                    startPinButton("PIN · PORT", endpoint: .port,
                                   captured: store.portPinCoordinate != nil, identifier: "capture-start-port")
                }.padding(.horizontal, 12).padding(.top, 12)
                if let message = store.pinFeedback {
                    Text(message).font(.system(.caption)).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18)
                }
            }
            AdaptiveStack {
                Text(store.isLiveMode ? "GPS konumu · Şematik parkur" : "Şematik parkur · Dokun, tekneyi taşı")
                Spacer()
                Text("Belirsizlik ±\(Int(store.input.windUncertainty))°")
            }.font(.system(.caption2, design: .monospaced, weight: .medium))
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
            AdaptiveStack(spacing: 5) {
                Image(systemName: captured ? "checkmark.circle.fill" : "location.circle")
                Text(title).fixedSize(horizontal: false, vertical: true)
            }.font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(captured ? Palette.background : Palette.teal)
                .frame(maxWidth: .infinity).frame(minHeight: 44).padding(.vertical, 8)
                .background(captured ? Palette.teal : Palette.seafoam,
                            in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(store.freshPosition == nil)
            .accessibilityIdentifier(identifier)
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
                        Image(systemName: "mappin.and.ellipse").font(.system(.largeTitle)).foregroundStyle(Palette.teal)
                        Text("Bir sonraki hedef.").font(.system(.largeTitle, weight: .bold)).tracking(-0.8)
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
            AdaptiveStack {
                TextField(hint, text: value).keyboardType(.numbersAndPunctuation)
                    .focused($focused, equals: field).font(.system(.title2, weight: .semibold)).monospacedDigit()
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
