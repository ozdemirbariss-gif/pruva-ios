import Foundation

public struct GeoCoordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Local east/north meters. Equirectangular projection on a mean-Earth sphere;
    /// intentionally unavailable above 85° latitude or beyond 100 km from origin.
    /// The longitude difference wraps across the antimeridian.
    public func projected(relativeTo origin: GeoCoordinate) -> Point? {
        guard isValid, origin.isValid, abs(latitude) < 85, abs(origin.latitude) < 85 else { return nil }
        let radius = 6_371_008.8
        let latitudeDelta = (latitude - origin.latitude) * .pi / 180
        let longitudeDelta = RaceEngine.signedAngle(longitude - origin.longitude) * .pi / 180
        let latitudeRadians = latitude * .pi / 180
        let originRadians = origin.latitude * .pi / 180
        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(latitudeRadians) * cos(originRadians) * pow(sin(longitudeDelta / 2), 2)
        let distance = 2 * radius * asin(sqrt(min(1, max(0, haversine))))
        guard distance <= 100_000 else { return nil }
        return Point(east: radius * longitudeDelta * cos(originRadians), north: radius * latitudeDelta)
    }
}

public struct TelemetrySample<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let value: Value
    /// Local receive time; receiving an unrelated sentence never changes this.
    public let timestamp: Date

    public init(value: Value, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    public func isFresh(at now: Date, maxAge: TimeInterval = 15) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age.isFinite && maxAge.isFinite && maxAge >= 0 && age >= 0 && age <= maxAge
    }
}

public struct WindObservation: Codable, Equatable, Sendable {
    /// Direction the wind comes FROM, degrees clockwise from true north.
    public let direction: Double
    /// Knots, retaining the instrument's theoretical/true-wind reference.
    public let speed: Double
    public let source: String

    public init(direction: Double, speed: Double, source: String) {
        self.direction = direction
        self.speed = speed
        self.source = source
    }
}

public struct RelativeWind: Codable, Equatable, Sendable {
    /// Degrees clockwise from the bow, [0, 360). Speed is in knots.
    public let angle: Double
    public let speed: Double

    public init(angle: Double, speed: Double) {
        self.angle = angle
        self.speed = speed
    }
}

/// Strict, checksum-checked NMEA 0183 reducer. A single configured instrument bus
/// supplies the samples; talker prefixes are accepted but are not sensor identities.
/// See https://gpsd.io/NMEA.html and the Furuno VR-5000 NMEA MWV description:
/// MWV(T) is theoretical wind relative to the BOW, not north; MWV(R) is apparent.
public struct MarineTelemetry: Sendable {
    public private(set) var position: TelemetrySample<GeoCoordinate>?
    public private(set) var speedOverGround: TelemetrySample<Double>?
    public private(set) var courseOverGround: TelemetrySample<Double>?
    public private(set) var trueHeading: TelemetrySample<Double>?
    public private(set) var speedThroughWater: TelemetrySample<Double>?
    public private(set) var apparentWind: TelemetrySample<RelativeWind>?
    public private(set) var acceptedSentenceCount = 0
    public private(set) var rejectedSentenceCount = 0

    private var directWind: TelemetrySample<WindObservation>?
    private var relativeTrueWind: TelemetrySample<RelativeWind>?
    private var headingSource = "HDT"
    // Invalidation timestamps also prevent delayed UDP observations resurrecting a fix.
    private var positionUpdate: Date?
    private var sogUpdate: Date?
    private var cogUpdate: Date?
    private var headingUpdate: Date?
    private var stwUpdate: Date?
    private var directWindUpdate: Date?
    private var trueWindUpdate: Date?
    private var apparentWindUpdate: Date?

    public init() {}

    public mutating func reset() { self = MarineTelemetry() }

    /// Returns true for a supported, valid sentence. A checksum-valid invalid-status
    /// sentence returns false AND immediately clears its associated observations.
    /// Corrupt/unsupported sentences do not mutate observations. Timestamp is receive time.
    @discardableResult
    public mutating func consume(_ sentence: String, at timestamp: Date = Date()) -> Bool {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite,
              let fields = Self.checkedFields(sentence) else {
            rejectedSentenceCount += 1
            return false
        }
        let accepted: Bool
        switch String(fields[0].suffix(3)) {
        case "RMC": accepted = consumeRMC(fields, at: timestamp)
        case "GGA": accepted = consumeGGA(fields, at: timestamp)
        case "VTG": accepted = consumeVTG(fields, at: timestamp)
        case "HDT": accepted = consumeHDT(fields, at: timestamp)
        case "VHW": accepted = consumeVHW(fields, at: timestamp)
        case "MWD": accepted = consumeMWD(fields, at: timestamp)
        case "MWV": accepted = consumeMWV(fields, at: timestamp)
        default: accepted = false
        }
        if accepted { acceptedSentenceCount += 1 } else { rejectedSentenceCount += 1 }
        return accepted
    }

    /// Fresh MWD true-north wind takes priority. Otherwise MWV(T) requires fresh
    /// true heading from HDT/VHW. COG is never treated as heading. Derivation uses
    /// the oldest component timestamp, so fresh heading cannot rejuvenate old wind.
    /// MWV(T) retains the instrument's water/ground reference; no current conversion.
    public func trueWind(at now: Date = Date()) -> TelemetrySample<WindObservation>? {
        if let directWind, directWind.isFresh(at: now) { return directWind }
        guard let relativeTrueWind, relativeTrueWind.isFresh(at: now),
              let trueHeading, trueHeading.isFresh(at: now) else { return nil }
        return TelemetrySample(
            value: WindObservation(
                direction: RaceEngine.normalizeDegrees(trueHeading.value + relativeTrueWind.value.angle),
                speed: relativeTrueWind.value.speed,
                source: "MWV(T) + \(headingSource)"
            ),
            timestamp: min(relativeTrueWind.timestamp, trueHeading.timestamp)
        )
    }

    private mutating func consumeRMC(_ f: [String], at time: Date) -> Bool {
        guard (10...14).contains(f.count) else { return false }
        let mode = f.count > 12 ? f[12] : ""
        let navigationStatus = f.count > 13 ? f[13] : ""
        guard f[2] == "A", Self.validMode(mode), Self.validNavigationStatus(navigationStatus) else {
            if f[2] == "V" || !Self.validMode(mode) || !Self.validNavigationStatus(navigationStatus) {
                invalidateGPS(at: time, includeMotion: true)
            }
            return false
        }
        guard let coordinate = Self.coordinate(latitude: f[3], northSouth: f[4], longitude: f[5], eastWest: f[6]),
              Self.validOptional(f[7], range: 0...100), Self.validOptionalAngle(f[8]) else { return false }
        Self.update(&position, lastUpdate: &positionUpdate, value: coordinate, at: time)
        Self.update(&speedOverGround, lastUpdate: &sogUpdate, value: Self.number(f[7], range: 0...100), at: time)
        Self.update(&courseOverGround, lastUpdate: &cogUpdate, value: Self.angle(f[8]), at: time)
        return true
    }

    private mutating func consumeGGA(_ f: [String], at time: Date) -> Bool {
        guard (7...16).contains(f.count), let quality = Int(f[6]), String(quality) == f[6] else { return false }
        guard (1...5).contains(quality) else {
            invalidateGPS(at: time, includeMotion: false)
            return false
        }
        guard let coordinate = Self.coordinate(latitude: f[2], northSouth: f[3], longitude: f[4], eastWest: f[5]) else {
            return false
        }
        Self.update(&position, lastUpdate: &positionUpdate, value: coordinate, at: time)
        return true
    }

    private mutating func consumeVTG(_ f: [String], at time: Date) -> Bool {
        guard (9...10).contains(f.count) else { return false }
        guard Self.validMode(f.count == 10 ? f[9] : "") else {
            Self.update(&speedOverGround, lastUpdate: &sogUpdate, value: nil, at: time)
            Self.update(&courseOverGround, lastUpdate: &cogUpdate, value: nil, at: time)
            return false
        }
        guard f[2] == "T", (f[4] == "M" || (f[3].isEmpty && f[4].isEmpty)), f[6] == "N", f[8] == "K",
              Self.validOptionalAngle(f[1]), Self.validOptionalAngle(f[3]), Self.validOptional(f[5], range: 0...100),
              Self.validOptional(f[7], range: 0...185.2),
              !f[1].isEmpty || !f[5].isEmpty || !f[7].isEmpty else { return false }
        let speed = Self.number(f[5], range: 0...100) ?? Self.number(f[7], range: 0...185.2).map { $0 / 1.852 }
        Self.update(&courseOverGround, lastUpdate: &cogUpdate, value: Self.angle(f[1]), at: time)
        Self.update(&speedOverGround, lastUpdate: &sogUpdate, value: speed, at: time)
        return true
    }

    private mutating func consumeHDT(_ f: [String], at time: Date) -> Bool {
        guard f.count == 3, f[2] == "T", let heading = Self.angle(f[1]) else { return false }
        updateHeading(heading, source: "HDT", at: time)
        return true
    }

    private mutating func consumeVHW(_ f: [String], at time: Date) -> Bool {
        guard f.count == 9, f[2] == "T", f[4] == "M", f[6] == "N", f[8] == "K",
              Self.validOptionalAngle(f[1]), Self.validOptionalAngle(f[3]), Self.validOptional(f[5], range: 0...100),
              Self.validOptional(f[7], range: 0...185.2),
              !f[1].isEmpty || !f[5].isEmpty || !f[7].isEmpty else { return false }
        // A water-speed-only VHW must not erase or refresh a separate HDT compass.
        if let heading = Self.angle(f[1]) { updateHeading(heading, source: "VHW", at: time) }
        let speed = Self.number(f[5], range: 0...100) ?? Self.number(f[7], range: 0...185.2).map { $0 / 1.852 }
        Self.update(&speedThroughWater, lastUpdate: &stwUpdate, value: speed, at: time)
        return true
    }

    private mutating func consumeMWD(_ f: [String], at time: Date) -> Bool {
        guard f.count == 9, f[2] == "T", f[4] == "M", f[6] == "N", f[8] == "M",
              let direction = Self.angle(f[1]), Self.validOptionalAngle(f[3]),
              Self.validOptional(f[5], range: 0...200), Self.validOptional(f[7], range: 0...(200 * 1.852 / 3.6)),
              let speed = Self.number(f[5], range: 0...200)
                ?? Self.number(f[7], range: 0...(200 * 1.852 / 3.6)).map({ $0 * 3.6 / 1.852 }) else { return false }
        let observation = WindObservation(direction: direction, speed: speed, source: "MWD")
        Self.update(&directWind, lastUpdate: &directWindUpdate, value: observation, at: time)
        return true
    }

    private mutating func consumeMWV(_ f: [String], at time: Date) -> Bool {
        guard (6...7).contains(f.count), f[2] == "R" || f[2] == "T" else { return false }
        let mode = f.count == 7 ? f[6] : ""
        guard f[5] == "A", Self.validMode(mode) else {
            if f[5] == "V" || !Self.validMode(mode) {
                if f[2] == "R" {
                    Self.update(&apparentWind, lastUpdate: &apparentWindUpdate, value: nil, at: time)
                } else {
                    Self.update(&relativeTrueWind, lastUpdate: &trueWindUpdate, value: nil, at: time)
                }
            }
            return false
        }
        guard let angle = Self.angle(f[1]), let speed = Self.windSpeed(f[3], unit: f[4]) else { return false }
        let observation = RelativeWind(angle: angle, speed: speed)
        if f[2] == "R" {
            Self.update(&apparentWind, lastUpdate: &apparentWindUpdate, value: observation, at: time)
        } else {
            Self.update(&relativeTrueWind, lastUpdate: &trueWindUpdate, value: observation, at: time)
        }
        return true
    }

    private mutating func invalidateGPS(at time: Date, includeMotion: Bool) {
        Self.update(&position, lastUpdate: &positionUpdate, value: nil, at: time)
        if includeMotion {
            Self.update(&speedOverGround, lastUpdate: &sogUpdate, value: nil, at: time)
            Self.update(&courseOverGround, lastUpdate: &cogUpdate, value: nil, at: time)
        }
    }

    private mutating func updateHeading(_ heading: Double, source: String, at time: Date) {
        if headingUpdate.map({ time >= $0 }) ?? true { headingSource = source }
        Self.update(&trueHeading, lastUpdate: &headingUpdate, value: heading, at: time)
    }

    private static func update<T>(_ sample: inout TelemetrySample<T>?, lastUpdate: inout Date?, value: T?, at time: Date) {
        guard lastUpdate.map({ time >= $0 }) ?? true else { return }
        sample = value.map { TelemetrySample(value: $0, timestamp: time) }
        lastUpdate = time
    }

    private static func checkedFields(_ sentence: String) -> [String]? {
        var bytes = Array(sentence.utf8)
        if bytes.last == 10 { bytes.removeLast() }
        if bytes.last == 13 { bytes.removeLast() }
        guard (10...512).contains(bytes.count), bytes.first == 36,
              bytes.allSatisfy({ (32...126).contains($0) }),
              let star = bytes.firstIndex(of: 42), star == bytes.count - 3,
              bytes[1..<star].allSatisfy({ $0 != 36 }),
              bytes[(star + 1)...].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let expected = UInt8(String(decoding: bytes[(star + 1)...], as: UTF8.self), radix: 16)
        else { return nil }
        let actual = bytes[1..<star].reduce(UInt8(0), ^)
        guard actual == expected else { return nil }
        let fields = String(decoding: bytes[1..<star], as: UTF8.self).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let header = fields.first, header.utf8.count == 5,
              header.utf8.allSatisfy({ (65...90).contains($0) }), fields.count > 1 else { return nil }
        return fields
    }

    private static func validMode(_ mode: String) -> Bool {
        // Legacy blank, autonomous, differential, RTK float/fixed, precise only.
        ["", "A", "D", "F", "R", "P"].contains(mode)
    }

    private static func validNavigationStatus(_ status: String) -> Bool {
        ["", "A", "D", "V"].contains(status)
    }

    private static func coordinate(latitude: String, northSouth: String, longitude: String, eastWest: String) -> GeoCoordinate? {
        guard ["N", "S"].contains(northSouth), ["E", "W"].contains(eastWest),
              let lat = coordinateAngle(latitude, degreeDigits: 2, maximum: 90),
              let lon = coordinateAngle(longitude, degreeDigits: 3, maximum: 180) else { return nil }
        return GeoCoordinate(latitude: northSouth == "S" ? -lat : lat, longitude: eastWest == "W" ? -lon : lon)
    }

    private static func coordinateAngle(_ raw: String, degreeDigits: Int, maximum: Double) -> Double? {
        let integerPart = raw.split(separator: ".", omittingEmptySubsequences: false).first ?? ""
        guard integerPart.count == degreeDigits + 2, let value = number(raw, range: 0...(maximum * 100)) else { return nil }
        let degrees = floor(value / 100)
        let minutes = value - degrees * 100
        guard minutes >= 0, minutes < 60, degrees <= maximum, degrees < maximum || minutes == 0 else { return nil }
        return degrees + minutes / 60
    }

    private static func number(_ raw: String, range: ClosedRange<Double>) -> Double? {
        // NMEA numeric fields are decimal, without exponents, whitespace, signs or NaN/Inf.
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              raw.utf8.filter({ $0 == 46 }).count <= 1, raw.first != ".", raw.last != ".",
              let value = Double(raw), value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func angle(_ raw: String) -> Double? {
        // 360 is not a valid NMEA [0,360) direction; reject rather than disguise a bad field.
        guard let value = number(raw, range: 0...360), value < 360 else { return nil }
        return value
    }
    private static func validOptional(_ raw: String, range: ClosedRange<Double>) -> Bool {
        raw.isEmpty || number(raw, range: range) != nil
    }
    private static func validOptionalAngle(_ raw: String) -> Bool { raw.isEmpty || angle(raw) != nil }

    private static func windSpeed(_ raw: String, unit: String) -> Double? {
        guard let speed = number(raw, range: 0...400) else { return nil }
        let knots: Double
        switch unit {
        case "N": knots = speed
        case "M": knots = speed * 3.6 / 1.852
        case "K": knots = speed / 1.852
        default: return nil
        }
        return knots <= 200 ? knots : nil
    }
}
