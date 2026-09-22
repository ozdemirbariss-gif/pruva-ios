import Foundation

/// Local race coordinates: east and north in meters. Not a geographic position.
public struct Point: Codable, Hashable, Sendable {
    public var east: Double
    public var north: Double

    public init(east: Double, north: Double) {
        self.east = east
        self.north = north
    }

    public static let zero = Point(east: 0, north: 0)
}

public enum RaceLeg: String, Codable, CaseIterable, Identifiable, Sendable {
    case upwind, downwind
    public var id: String { rawValue }
    public var title: String { self == .upwind ? "Orsa" : "Pupa" }
}

public enum Tack: String, Codable, CaseIterable, Identifiable, Sendable {
    case starboard, port
    public var id: String { rawValue }
    public var title: String { self == .starboard ? "Sancak" : "İskele" }
    public var opposite: Tack { self == .starboard ? .port : .starboard }
}

/// Knots for speeds/current, degrees for wind/angles, seconds for time.
/// Wind direction means the direction the wind comes FROM, clockwise from north.
/// `pressureAdvantage` is the estimated speed advantage (%) on the OTHER tack.
public struct RaceInput: Codable, Equatable, Sendable {
    public var leg: RaceLeg
    public var tack: Tack
    public var windDirection: Double
    public var meanWindDirection: Double
    public var windSpeed: Double
    public var boatSpeed: Double
    public var targetAngle: Double
    public var boatPosition: Point
    public var markPosition: Point
    public var currentEast: Double
    public var currentNorth: Double
    public var maneuverLossSeconds: Double
    public var additionalManeuvers: Int
    public var expectedShiftDuration: Double
    public var windUncertainty: Double
    public var pressureAdvantage: Double
    public var dirtyAir: Bool
    public var finalApproach: Bool

    public init(
        leg: RaceLeg = .upwind,
        tack: Tack = .starboard,
        windDirection: Double = 0,
        meanWindDirection: Double = 0,
        windSpeed: Double = 14,
        boatSpeed: Double = 6.4,
        targetAngle: Double? = nil,
        boatPosition: Point = .zero,
        markPosition: Point = Point(east: -450, north: 1800),
        currentEast: Double = 0,
        currentNorth: Double = 0,
        maneuverLossSeconds: Double = 12,
        additionalManeuvers: Int = 2,
        expectedShiftDuration: Double = 120,
        windUncertainty: Double = 3,
        pressureAdvantage: Double = 0,
        dirtyAir: Bool = false,
        finalApproach: Bool = false
    ) {
        self.leg = leg
        self.tack = tack
        self.windDirection = windDirection
        self.meanWindDirection = meanWindDirection
        self.windSpeed = windSpeed
        self.boatSpeed = boatSpeed
        self.targetAngle = targetAngle ?? (leg == .upwind ? 45 : 145)
        self.boatPosition = boatPosition
        self.markPosition = markPosition
        self.currentEast = currentEast
        self.currentNorth = currentNorth
        self.maneuverLossSeconds = maneuverLossSeconds
        self.additionalManeuvers = additionalManeuvers
        self.expectedShiftDuration = expectedShiftDuration
        self.windUncertainty = windUncertainty
        self.pressureAdvantage = pressureAdvantage
        self.dirtyAir = dirtyAir
        self.finalApproach = finalApproach
    }
}

public enum Recommendation: String, Codable, Sendable {
    case hold, prepare, maneuver
}

public struct RaceGeometry: Codable, Equatable, Sendable {
    public let boat: Point
    public let mark: Point
    /// Ground velocity in meters per second, including current.
    public let currentGroundVector: Point
    public let otherGroundVector: Point
    /// Projected constant-wind route, including the tack/gybe point when feasible.
    public let currentRoute: [Point]
    public let otherRoute: [Point]
    public let currentHeading: Double
    public let otherHeading: Double

    public init(boat: Point, mark: Point, currentGroundVector: Point, otherGroundVector: Point,
                currentRoute: [Point], otherRoute: [Point], currentHeading: Double, otherHeading: Double) {
        self.boat = boat
        self.mark = mark
        self.currentGroundVector = currentGroundVector
        self.otherGroundVector = otherGroundVector
        self.currentRoute = currentRoute
        self.otherRoute = otherRoute
        self.currentHeading = currentHeading
        self.otherHeading = otherHeading
    }
}

public struct RaceAnalysis: Codable, Equatable, Sendable {
    public let recommendation: Recommendation
    public let title: String
    public let message: String
    public let trigger: String
    /// Clockwise angular difference: instantaneous wind minus circular mean wind.
    public let signedShift: Double
    /// Positive is useful on the current tack: lifts upwind, headers downwind.
    public let favorableShift: Double
    public let heading: Double
    public let cog: Double
    /// Wind-axis VMG and mark-axis VMC, both in knots.
    public let vmg: Double
    public let vmc: Double
    public let distanceToMark: Double
    public let etaSeconds: Double?
    public let currentTackSeconds: Double?
    public let otherTackSeconds: Double?
    public let laylineSeconds: Double?
    public let isLongTack: Bool
    public let isOverstood: Bool
    /// Gross advantage of switching under a bounded hypothetical shift scenario.
    /// Positive favors switching; this is an estimate, not a weather forecast.
    public let expectedGainSeconds: Double
    public let costSeconds: Double
    public let reasons: [String]
    public let confidence: AnalysisConfidence
    public let geometry: RaceGeometry

    public init(recommendation: Recommendation, title: String, message: String, trigger: String,
                signedShift: Double, favorableShift: Double, heading: Double, cog: Double,
                vmg: Double, vmc: Double, distanceToMark: Double, etaSeconds: Double?,
                currentTackSeconds: Double?, otherTackSeconds: Double?, laylineSeconds: Double?,
                isLongTack: Bool, isOverstood: Bool, expectedGainSeconds: Double, costSeconds: Double,
                reasons: [String], confidence: AnalysisConfidence, geometry: RaceGeometry) {
        self.recommendation = recommendation
        self.title = title
        self.message = message
        self.trigger = trigger
        self.signedShift = signedShift
        self.favorableShift = favorableShift
        self.heading = heading
        self.cog = cog
        self.vmg = vmg
        self.vmc = vmc
        self.distanceToMark = distanceToMark
        self.etaSeconds = etaSeconds
        self.currentTackSeconds = currentTackSeconds
        self.otherTackSeconds = otherTackSeconds
        self.laylineSeconds = laylineSeconds
        self.isLongTack = isLongTack
        self.isOverstood = isOverstood
        self.expectedGainSeconds = expectedGainSeconds
        self.costSeconds = costSeconds
        self.reasons = reasons
        self.confidence = confidence
        self.geometry = geometry
    }
}

/// Model quality category, not a calibrated probability.
public enum AnalysisConfidence: String, Codable, CaseIterable, Sendable {
    case low = "Düşük", medium = "Orta", high = "Yüksek"
}
