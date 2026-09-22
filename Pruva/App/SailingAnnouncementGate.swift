import Foundation

/// Called only in the foreground. Busy audio does not consume an announcement.
struct SailingAnnouncementGate {
    private var lastAlerts: [SailingAlert.Kind: Date] = [:]
    private var activeKinds: Set<SailingAlert.Kind> = []
    private var lastDistance: Double?
    private var lastDistanceDate: Date?

    mutating func reset() { self = Self() }

    mutating func deliver(alerts: [SailingAlert], distance: Double?, distanceSpeech: String,
                          at now: Date, speak: (String) -> Bool) -> Bool {
        let kinds = Set(alerts.map(\.kind))
        activeKinds.formIntersection(kinds)
        let newAlerts = alerts.filter {
            !activeKinds.contains($0.kind) && now.timeIntervalSince(lastAlerts[$0.kind] ?? .distantPast) >= 30
        }
        if !newAlerts.isEmpty {
            let text = newAlerts.map { alert in
                "\(alert.title). \(alert.kind == .startLine ? distanceSpeech : alert.detail)"
            }.joined(separator: " ")
            if speak(text) {
                for alert in newAlerts { lastAlerts[alert.kind] = now; activeKinds.insert(alert.kind) }
                if newAlerts.contains(where: { $0.kind == .startLine }) {
                    lastDistance = distance; lastDistanceDate = now
                }
                return true
            }
            return false
        }
        guard let distance else { lastDistance = nil; lastDistanceDate = nil; return false }
        if lastDistance == nil || (now.timeIntervalSince(lastDistanceDate ?? .distantPast) >= 20 && abs(distance - lastDistance!) >= 10) {
            if speak(distanceSpeech) { lastDistance = distance; lastDistanceDate = now }
        }
        return false
    }
}
