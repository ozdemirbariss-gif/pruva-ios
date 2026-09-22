import Foundation

public enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case longTack, persistentHeader, nearLayline, downwind, finalApproach, startApproach

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .longTack: "Uzun kontra"
        case .persistentHeader: "Süren kafalama"
        case .nearLayline: "Layline eşiği"
        case .downwind: "Pupa kararı"
        case .finalApproach: "Son yaklaşım"
        case .startApproach: "Start provası"
        }
    }

    public var subtitle: String {
        switch self {
        case .longTack: "Küçük kayma, pahalı manevra"
        case .persistentHeader: "Süreklilik kazancı değiştirir"
        case .nearLayline: "Rüzgâr değişir, dönüş hattı taşınır"
        case .downwind: "Pupada kısanı kullan"
        case .finalApproach: "Şamandıraya odaklan"
        case .startApproach: "Hat mesafesi ve hız düşüşünü dene"
        }
    }

    public var input: RaceInput {
        switch self {
        case .longTack:
            RaceInput(windDirection: 357, meanWindDirection: 0,
                      markPosition: Point(east: -650, north: 1850),
                      currentEast: 0.3, maneuverLossSeconds: 15,
                      expectedShiftDuration: 75, windUncertainty: 3)
        case .persistentHeader:
            RaceInput(windDirection: 346, meanWindDirection: 0,
                      markPosition: Point(east: -450, north: 2200),
                      currentEast: 0.2, maneuverLossSeconds: 11,
                      expectedShiftDuration: 180, windUncertainty: 3,
                      pressureAdvantage: 4)
        case .nearLayline:
            RaceInput(windDirection: 5, meanWindDirection: 0,
                      markPosition: Point(east: 712, north: 660),
                      maneuverLossSeconds: 12, expectedShiftDuration: 90,
                      windUncertainty: 2)
        case .downwind:
            RaceInput(leg: .downwind, tack: .starboard,
                      windDirection: 350, meanWindDirection: 0,
                      windSpeed: 17, boatSpeed: 8.2,
                      markPosition: Point(east: -550, north: -1800),
                      currentEast: 0.25, maneuverLossSeconds: 18,
                      expectedShiftDuration: 120, windUncertainty: 3)
        case .finalApproach:
            RaceInput(windDirection: 2, meanWindDirection: 0,
                      markPosition: Point(east: -205, north: 210),
                      maneuverLossSeconds: 15, expectedShiftDuration: 60,
                      windUncertainty: 3, finalApproach: true)
        case .startApproach:
            RaceInput(windDirection: 0, meanWindDirection: 0,
                      boatSpeed: 6.4, boatPosition: Point(east: 0, north: -120),
                      markPosition: Point(east: 0, north: 650),
                      maneuverLossSeconds: 12, expectedShiftDuration: 90,
                      windUncertainty: 2)
        }
    }
}
