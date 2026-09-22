import Foundation
import RaceCore

struct SailingAlert: Identifiable, Equatable {
    enum Kind: String { case layline, startLine, speed }
    let kind: Kind
    let title: String
    let detail: String
    var id: Kind { kind }
    var symbol: String { kind == .speed ? "speedometer" : "exclamationmark.triangle.fill" }
}

extension RaceStore {
    var startLineMeasurement: StartLineMeasurement? {
        guard isLiveMode, let fix = freshPosition, let committee = committeePinCoordinate,
              let port = portPinCoordinate, let boatPoint = fix.value.projected(relativeTo: committee),
              let portPoint = port.projected(relativeTo: committee) else { return nil }
        return StartLineMeasurement.measure(boat: boatPoint, committee: .zero, port: portPoint)
    }

    var startDistanceSpeech: String {
        guard let measurement = startLineMeasurement else { return "Start mesafesi için iki pin ve güncel tekne GPS konumu gerekli." }
        return "Start hattına en kısa mesafe \(Int(measurement.distanceMeters.rounded())) metre."
            + (measurement.isBeyondEndpoint ? " Hat uzantısındasınız; mesafe en yakın pine ölçülüyor." : "")
    }

    var sailingAlerts: [SailingAlert] {
        var result: [SailingAlert] = []
        if laylineProximity.isNear, !isLiveMode || liveReadinessMessage == nil {
            result.append(SailingAlert(kind: .layline, title: "Layline yakın",
                detail: "Yaklaşık \(Int(max(0, analysis.laylineSeconds ?? 0))) saniye · Hattı ve manevra alanını kontrol edin."))
        }
        if startProximity.isNear, let measurement = startLineMeasurement {
            result.append(SailingAlert(kind: .startLine, title: "Start hattı yakın",
                detail: "Hatta \(Int(measurement.distanceMeters.rounded())) m · \(measurement.isBeyondEndpoint ? "En yakın pine mesafe" : "İki pin arasındaki hatta mesafe")"))
        }
        if let drop = speedDropMonitor.warning, !isLiveMode || connection.isRunning {
            result.append(SailingAlert(kind: .speed, title: "Hız düşüyor",
                detail: String(format: "%.1f → %.1f kn · %@ · Yelken trimini ve çevreyi kontrol edin.", drop.baselineKnots, drop.currentKnots, drop.reference.rawValue)))
        }
        return result
    }

    var lineAlertActive: Bool { sailingAlerts.contains { $0.kind != .speed } }

    func updateSailingAlerts() {
        laylineProximity.update(!isLiveMode || liveReadinessMessage == nil ? analysis.laylineSeconds : nil, enter: 30, exit: 45)
        startProximity.update(startLineMeasurement?.distanceMeters, enter: 30, exit: 40)
        guard isLiveMode else {
            speedDropMonitor.record(TelemetrySample(value: input.boatSpeed, timestamp: telemetryNow), reference: .simulated, at: telemetryNow)
            return
        }
        if let water = freshWaterSpeed {
            speedDropMonitor.record(water, reference: .water, at: telemetryNow)
        } else {
            speedDropMonitor.record(freshSOG, reference: .ground, at: telemetryNow)
        }
    }

    func resetSailingAlerts() {
        speedDropMonitor.reset()
        laylineProximity = ProximityLatch()
        startProximity = ProximityLatch()
    }
}
