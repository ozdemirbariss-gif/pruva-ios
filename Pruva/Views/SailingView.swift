import SwiftUI
import Charts
import RaceCore

struct SailingView: View {
    @Environment(RaceStore.self) private var store
    @State private var showLayers = false
    @State private var showPresets = false
    @State private var showReasons = false
    @State private var note = ""

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    title
                    if proxy.size.width > 760 {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 18) { instruments; map(height: 480); windCard }.frame(maxWidth: .infinity)
                            VStack(spacing: 18) { decision; navigatorCard; saveCard }.frame(width: 320)
                        }
                    } else {
                        instruments
                        map(height: 310)
                        decision
                        windCard
                        navigatorCard
                        saveCard
                    }
                    Text("Şematik parkur · Manuel veriler · Gerçek zamanlı sensör bağlantısı yok")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 26)
                    .frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
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
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Yarış karar asistanı")
                    Text("Bir sonraki hamleyi gör.")
                        .font(.system(size: 27, weight: .regular, design: .serif)).tracking(-0.6)
                        .minimumScaleFactor(0.85).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button { showPresets = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered").font(.system(size: 12))
                        Text(store.input.leg == .upwind ? "Orsa · Şamandıra 1" : "Pupa · Şamandıra 2").font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }.foregroundStyle(Palette.secondary)
                }.accessibilityLabel("Parkur seç")
                Spacer()
                HStack(spacing: 0) {
                    ForEach(CrewRole.allCases, id: \.self) { role in
                        Button { store.role = role } label: {
                            Text(role.rawValue).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .background(store.role == role ? .white : .clear, in: Capsule())
                                .foregroundStyle(store.role == role ? Palette.ink : Palette.secondary)
                        }.buttonStyle(.plain)
                    }
                }.padding(3).background(Palette.line.opacity(0.5), in: Capsule())
            }
        }
    }

    private var instruments: some View {
        Surface(padding: 18) {
            HStack(spacing: 14) {
                Metric(label: "Gerçek rüzgâr", value: decimal(store.input.windSpeed), unit: "kn")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: "Rüzgâr yönü", value: degrees(store.input.windDirection), unit: "")
                Rectangle().fill(Palette.line).frame(width: 1, height: 36)
                Metric(label: store.role == .tactician ? "VMG · rüzgâr" : "VMC · hedef", value: decimal(store.role == .tactician ? store.analysis.vmg : store.analysis.vmc), unit: "kn")
            }
        }
    }

    private func map(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parkur görünümü").font(.system(size: 15, weight: .semibold))
                    Text("\(store.scenarioName) · Şematik").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { showLayers = true } label: {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 18)).foregroundStyle(Palette.teal)
                        .frame(width: 38, height: 38).background(Palette.background, in: Circle())
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
                showLaylines: store.showLaylines, showTrail: store.showTrail,
                onBoatMove: { point in
                    store.isPlaying = false
                    store.input.boatPosition = Point(east: point.x, north: point.y)
                    store.savedFeedback = false
                    store.persist()
                }
            ).frame(height: height)
            HStack(spacing: 5) {
                Image(systemName: "hand.tap").font(.system(size: 10))
                Text("Tekneyi taşımak için parkura dokun").font(.system(size: 10))
                Spacer()
                Text("±\(Int(store.input.windUncertainty))° bant").font(.system(size: 10, weight: .medium))
            }.foregroundStyle(Palette.secondary).padding(.horizontal, 18).padding(.vertical, 12)
        }.background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var decision: some View {
        let a = store.analysis
        let isHold = a.recommendation == .hold
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isHold ? "arrow.up.right" : "arrow.triangle.turn.up.right.diamond")
                    Text("TAKTİK OKUMA").tracking(1.6)
                }.font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.teal)
                Spacer()
                Text("Model güveni: \(a.confidence.lowercased())").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Text(a.title).font(.system(size: 25, weight: .medium, design: .serif)).accessibilityIdentifier("decision-title")
            Text(store.role == .tactician ? a.message : navigatorMessage).font(.system(size: 13)).lineSpacing(4).foregroundStyle(Palette.ink.opacity(0.8))
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
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
            }.buttonStyle(.plain)
            if showReasons {
                ForEach(Array(a.reasons.enumerated()), id: \.offset) { _, reason in
                    Label(reason, systemImage: "circle.fill").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text("Model kazancı \(decimal(a.expectedGainSeconds)) sn · Ek manevra maliyeti \(decimal(a.costSeconds)) sn")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.teal)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.seafoam.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.teal.opacity(0.12), lineWidth: 1))
    }

    private var navigatorMessage: String {
        let a = store.analysis
        return "Hedefe \(Int(a.distanceToMark)) m. Yerdeki rota \(degrees(a.cog)), pruva \(degrees(a.heading)). \(a.isOverstood ? "Layline dışında; direkt yaklaşma açısını kontrol edin." : "Mevcut kontra payı \(duration(a.currentTackSeconds)), diğer kontra \(duration(a.otherTackSeconds)).")"
    }

    private var windCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: "Rüzgârın ritmi")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%+.0f°", store.relativeWind)).font(.system(size: 27, weight: .medium, design: .rounded))
                            Text("ortalamaya göre").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    Button { store.togglePlayback() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13))
                            .frame(width: 42, height: 42).background(Palette.seafoam, in: Circle())
                    }.accessibilityLabel(store.isPlaying ? "Simülasyonu duraklat" : "Rüzgâr simülasyonunu oynat")
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
                    Text("ÖRNEK GEÇMİŞİ").tracking(1)
                    Spacer()
                    Text("Referans \(degrees(store.input.meanWindDirection)) · Manuel")
                }.font(.system(size: 9)).foregroundStyle(Palette.secondary)
                Slider(value: Binding(get: { store.relativeWind }, set: { value in
                    store.isPlaying = false; store.relativeWind = value; store.recordWind(); store.savedFeedback = false
                }), in: -30...30, step: 1, onEditingChanged: { editing in if !editing { store.persist() } })
                    .accessibilityLabel("Rüzgâr sapması").accessibilityIdentifier("wind-slider")
                Text("Son ölçüme değil, ortalamaya bak. 10° açtıktan sonra 4°'ye dönmek hâlâ 4° açan kontradır.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
            }
        }
    }

    private var navigatorCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Eyebrow(text: "Navigatör paneli"); Spacer(); Image(systemName: "scope").foregroundStyle(Palette.teal) }
                HStack {
                    Metric(label: "Şamandıraya", value: "\(Int(store.analysis.distanceToMark))", unit: "m")
                    Metric(label: "Tahmini süre", value: duration(store.analysis.etaSeconds), unit: "")
                }
                Divider()
                detailRow("Mevcut kontra", store.input.tack == .starboard ? "Sancak" : "İskele")
                detailRow("Kontra payı", store.analysis.isLongTack ? "Uzun kontra" : "Kısa kontra")
                detailRow("Layline'a süre", duration(store.analysis.laylineSeconds))
                detailRow("Pruva / Yerdeki rota", "\(degrees(store.analysis.heading)) / \(degrees(store.analysis.cog))")
                Text("Süreler sabit hız ve rüzgâr varsayımıyla hesaplanır.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(Palette.secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.system(size: 12))
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ekibe bir not bırak…", text: $note, axis: .vertical)
                .font(.system(size: 13)).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("decision-note")
            ActionButton(title: store.savedFeedback ? "Seyir defterine kaydedildi" : "Kararı seyir defterine kaydet", icon: store.savedFeedback ? "checkmark" : "bookmark") {
                store.saveDecision(note: note); note = ""
            }.accessibilityIdentifier("save-decision")
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
