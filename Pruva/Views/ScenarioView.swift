import SwiftUI
import RaceCore

struct ScenarioView: View {
    @Environment(RaceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Senaryo seç")
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(DemoScenario.allCases.enumerated()), id: \.element.id) { index, scenario in
                            Button { store.load(scenario) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced))
                                        Spacer()
                                        Image(systemName: store.scenarioName == scenario.title ? "checkmark.circle.fill" : "arrow.up.right")
                                    }.foregroundStyle(Palette.teal)
                                    Text(scenario.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                                        .frame(minHeight: 42, alignment: .topLeading)
                                }.padding(18).frame(width: 190, height: 112, alignment: .topLeading)
                                    .background(store.scenarioName == scenario.title ? Palette.seafoam : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.scenarioName == scenario.title ? Palette.teal : Palette.line, lineWidth: 1))
                            }.buttonStyle(.plain).accessibilityIdentifier("scenario-\(scenario.rawValue)")
                        }
                    }
                }.scrollIndicators(.hidden).accessibilityIdentifier("scenario-carousel")

                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow(text: "Karar şimdi")
                        Text("Şamandıra · \(Int(store.analysis.distanceToMark)) m")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).accessibilityIdentifier("scenario-distance")
                        Text(store.analysis.title).font(.system(size: 23, weight: .semibold)).accessibilityIdentifier("scenario-decision")
                        Text(store.analysis.message).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(3)
                        HStack {
                            comparisonMetric("TAHMİNİ KAZANÇ", value: store.analysis.expectedGainSeconds)
                            Spacer()
                            comparisonMetric("MANEVRA MALİYETİ", value: store.analysis.costSeconds)
                        }
                    }
                }

                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        Eyebrow(text: "Rüzgâr & rota")
                        Picker("Bacak", selection: Binding(get: { store.input.leg }, set: { leg in
                            store.isPlaying = false
                            store.input.leg = leg
                            store.input.targetAngle = leg == .upwind ? 45 : 145
                            store.input.markPosition = Point(east: 0, north: store.input.boatPosition.north + (leg == .upwind ? 1500 : -1500))
                            store.scenarioName = "Özel senaryo"
                            store.persist()
                        })) {
                            Text("Orsa").tag(RaceLeg.upwind); Text("Pupa").tag(RaceLeg.downwind)
                        }.pickerStyle(.segmented)
                        Picker("Kontra", selection: $store.input.tack) {
                            Text("Sancak kontra").tag(Tack.starboard); Text("İskele kontra").tag(Tack.port)
                        }.pickerStyle(.segmented)
                        control("Ortalamaya göre shift", value: Binding(get: { store.relativeWind }, set: { store.isPlaying = false; store.relativeWind = $0; store.recordWind() }), range: -30...30, unit: "°", step: 1)
                        control("Ortalama rüzgâr yönü", value: $store.input.meanWindDirection, range: 0...359, unit: "°", step: 1)
                        control("Gerçek rüzgâr hızı", value: $store.input.windSpeed, range: 3...35, unit: "kn")
                        control("Tekne hızı · suya göre", value: $store.input.boatSpeed, range: 1...20, unit: "kn")
                        control("Hedef gerçek rüzgâr açısı", value: $store.input.targetAngle, range: store.input.leg == .upwind ? 30...65 : 110...175, unit: "°", step: 1)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        Eyebrow(text: "Manevra & belirsizlik")
                        control("Bir manevranın kaybı", value: $store.input.maneuverLossSeconds, range: 2...30, unit: "sn", step: 1)
                        Stepper("Ek manevra sayısı: \(store.input.additionalManeuvers)", value: $store.input.additionalManeuvers, in: 1...4)
                            .font(.system(size: 13))
                        control("Beklenen shift süresi", value: $store.input.expectedShiftDuration, range: 10...600, unit: "sn", step: 10)
                        control("Rüzgâr belirsizliği · ±", value: $store.input.windUncertainty, range: 0...15, unit: "°", step: 1)
                        control("Diğer kontrada hız avantajı", value: $store.input.pressureAdvantage, range: -20...30, unit: "%", step: 1)
                        Toggle("Mevcut kontrada kirli hava", isOn: $store.input.dirtyAir).font(.system(size: 13))
                        Toggle("Son yaklaşma üzerindeyiz", isOn: $store.input.finalApproach).font(.system(size: 13))
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        Eyebrow(text: "Akıntı · yer vektörü")
                        control("Doğu (+) / Batı (−)", value: $store.input.currentEast, range: -3...3, unit: "kn")
                        control("Kuzey (+) / Güney (−)", value: $store.input.currentNorth, range: -3...3, unit: "kn")
                    }
                }
                ActionButton(title: "Bu senaryoyu kaydet", icon: "bookmark") { store.saveDecision(note: "Taktik laboratuvarından kaydedildi.") }
                if store.savedFeedback { Label("Seyir defterine eklendi", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Palette.teal) }
            }.padding(22).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
            .onChange(of: store.input) { _, _ in store.savedFeedback = false; store.persist() }
    }

    private func comparisonMetric(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Palette.secondary)
            Text("\(decimal(value)) sn").font(.system(size: 24, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.teal)
        }
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double = 0.1) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(step >= 1 ? String(format: "%.0f", value.wrappedValue) : decimal(value.wrappedValue)) \(unit)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit().foregroundStyle(Palette.teal)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
