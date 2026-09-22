import Foundation

/// Shortest distance to the finite committee–port segment, not its extension.
public struct StartLineMeasurement: Equatable, Sendable {
    public let distanceMeters: Double
    public let isBeyondEndpoint: Bool

    public static func measure(boat: Point, committee: Point, port: Point) -> Self? {
        guard [boat.east, boat.north, committee.east, committee.north, port.east, port.north].allSatisfy(\.isFinite) else { return nil }
        let dx = port.east - committee.east, dy = port.north - committee.north
        let length = hypot(dx, dy)
        guard (1...10_000).contains(length) else { return nil }
        let t = ((boat.east - committee.east) * dx + (boat.north - committee.north) * dy) / (length * length)
        let clamped = min(1, max(0, t))
        let distance = hypot(boat.east - committee.east - clamped * dx, boat.north - committee.north - clamped * dy)
        guard distance.isFinite else { return nil }
        return Self(distanceMeters: distance, isBeyondEndpoint: t < 0 || t > 1)
    }
}

public enum SpeedReference: String, Sendable { case water = "STW", ground = "SOG", simulated = "SİM" }

public struct SpeedDrop: Equatable, Sendable {
    public let currentKnots: Double
    public let baselineKnots: Double
    public let reference: SpeedReference
}

/// Deterministic observation filter, independent of tactical recommendations.
/// Warm up for 10 seconds / 5 samples; require a >=15% and >=0.5 kn loss for
/// 5 seconds. Freeze the reference during a candidate so a sustained drop cannot
/// erase itself. Repeated timestamps never count as new evidence.
public struct SpeedDropMonitor: Sendable {
    public private(set) var warning: SpeedDrop?
    private var history: [TelemetrySample<Double>] = []
    private var source: SpeedReference?
    private var lastDate: Date?
    private var candidateSince: Date?
    private var candidateBaseline: Double?
    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func record(_ sample: TelemetrySample<Double>?, reference: SpeedReference, at now: Date) {
        guard let sample, sample.isFresh(at: now), sample.value.isFinite, sample.value >= 0 else { reset(); return }
        if source != reference { reset(); source = reference }
        if let lastDate {
            guard sample.timestamp > lastDate else { return }
            if sample.timestamp.timeIntervalSince(lastDate) > 5 { reset(); source = reference }
        }
        lastDate = sample.timestamp
        history.removeAll { sample.timestamp.timeIntervalSince($0.timestamp) > 30 }
        let warmedUp = history.count >= 5 && sample.timestamp.timeIntervalSince(history[0].timestamp) >= 10
        let baseline = candidateBaseline ?? (warmedUp ? history.map(\.value).reduce(0, +) / Double(history.count) : nil)
        if let baseline, baseline >= 1, baseline - sample.value >= max(0.5, baseline * 0.15) {
            if candidateSince == nil { candidateSince = sample.timestamp; candidateBaseline = baseline }
            if sample.timestamp.timeIntervalSince(candidateSince!) >= 5 {
                warning = SpeedDrop(currentKnots: sample.value, baselineKnots: baseline, reference: reference)
            }
            return
        }
        if candidateSince != nil { history = [] }
        warning = nil; candidateSince = nil; candidateBaseline = nil
        history.append(sample)
        if history.count > 300 { history.removeFirst(history.count - 300) }
    }
}

/// A wider exit threshold prevents border jitter from repeatedly rearming alerts.
public struct ProximityLatch: Sendable {
    public private(set) var isNear = false
    public init() {}
    public mutating func update(_ value: Double?, enter: Double, exit: Double) {
        guard let value, value.isFinite, value >= 0 else { isNear = false; return }
        isNear = value <= (isNear ? exit : enter)
    }
}
