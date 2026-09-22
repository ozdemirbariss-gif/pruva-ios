import Foundation

/// Deterministic, offline decision support. The horizon is a user-supplied scenario,
/// not a prediction. Constant boat speed and current replace a full polar/forecast model.
public enum RaceEngine {
    public static let metersPerSecondPerKnot = 0.514444

    /// A circular mean avoids the 359°/1° → 180° error. Antipodal or empty input is undefined.
    public static func circularMean(_ samples: [Double]) -> Double? {
        let angles = samples.filter(\.isFinite)
        guard !angles.isEmpty else { return nil }
        let east = angles.reduce(0) { $0 + sin(radians(normalizeDegrees($1))) }
        let north = angles.reduce(0) { $0 + cos(radians(normalizeDegrees($1))) }
        guard hypot(east, north) / Double(angles.count) > 1e-10 else { return nil }
        return normalizeDegrees(atan2(east, north) * 180 / .pi)
    }

    public static func normalizeDegrees(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let value = angle.truncatingRemainder(dividingBy: 360)
        let normalized = value < 0 ? value + 360 : value
        return normalized >= 360 - 1e-10 ? 0 : normalized
    }

    /// The shortest signed turn in [-180, 180).
    public static func signedAngle(_ angle: Double) -> Double {
        normalizeDegrees(angle + 180) - 180
    }

    public static func heading(windDirection: Double, targetAngle: Double, tack: Tack) -> Double {
        normalizeDegrees(windDirection + (tack == .starboard ? -targetAngle : targetAngle))
    }

    public static func groundVector(heading: Double, speed: Double,
                                    currentEast: Double = 0, currentNorth: Double = 0) -> Point {
        let waterSpeed = bounded(speed, fallback: 0, in: 0...60) * metersPerSecondPerKnot
        let current = Point(
            east: bounded(currentEast, fallback: 0, in: -20...20) * metersPerSecondPerKnot,
            north: bounded(currentNorth, fallback: 0, in: -20...20) * metersPerSecondPerKnot
        )
        return direction(heading) * waterSpeed + current
    }

    public static func analyze(_ rawInput: RaceInput) -> RaceAnalysis {
        let input = sanitized(rawInput)
        let valid = rawInput == input
        let course = solve(input, from: input.boatPosition, wind: input.windDirection)
        let currentHeading = heading(windDirection: input.windDirection,
                                     targetAngle: input.targetAngle, tack: input.tack)
        let otherHeading = heading(windDirection: input.windDirection,
                                   targetAngle: input.targetAngle, tack: input.tack.opposite)
        let velocity = groundVector(heading: currentHeading, speed: input.boatSpeed,
                                    currentEast: input.currentEast, currentNorth: input.currentNorth)
        let otherVelocity = groundVector(heading: otherHeading, speed: input.boatSpeed,
                                         currentEast: input.currentEast, currentNorth: input.currentNorth)
        let delta = input.markPosition - input.boatPosition
        let distance = delta.length
        let signedShift = signedAngle(input.windDirection - input.meanWindDirection)
        let tackSign = input.tack == .starboard ? 1.0 : -1.0
        let legSign = input.leg == .upwind ? 1.0 : -1.0
        let favorableShift = signedShift * tackSign * legSign
        let windAxis = direction(input.windDirection + (input.leg == .upwind ? 0 : 180))
        let cog = velocity.length > 1e-9 ? bearing(velocity) : currentHeading
        let vmg = velocity.dot(windAxis) / metersPerSecondPerKnot
        let vmc = distance > 1e-9 ? velocity.dot(delta / distance) / metersPerSecondPerKnot : 0
        let feasible = course.currentSeconds != nil && course.otherSeconds != nil
        let isOverstood = (course.rawCurrentSeconds.map { $0 < -2 } ?? false)
            || (course.rawOtherSeconds.map { $0 < -2 } ?? false)
        let isLongTack = (course.currentSeconds ?? 0) >= (course.otherSeconds ?? 0) && feasible
        let cost = input.maneuverLossSeconds * Double(input.additionalManeuvers)
        // Once both candidates reach the mark, continuing the scenario cannot create a benefit.
        let horizon = min(input.expectedShiftDuration, 600, course.eta ?? 600)
        let routeGain = scenarioGain(input, course: course, horizon: horizon)
        // Both candidates eventually sail the other tack. Only their difference
        // in exposure before the scenario ends is attributable to switching now.
        let otherTime = course.otherSeconds ?? 0
        let switchExposure = min(horizon, otherTime)
        let holdExposure = min(otherTime, max(0, horizon - (course.currentSeconds ?? horizon)))
        let pressureExposure = switchExposure - holdExposure
        let pressureGain = pressureExposure * input.pressureAdvantage / 100
        let gain = (routeGain ?? 0) + pressureGain
        let shiftResolved = abs(signedShift) > input.windUncertainty
        let uncertaintyMargin = 3 + horizon * sin(radians(input.windUncertainty))
        let layline = course.currentSeconds
        let maneuver = input.leg == .upwind ? "Tramola" : "Kavança"
        let maneuverLower = input.leg == .upwind ? "tramola" : "kavança"
        let robustGain = routeGain != nil && gain > cost + uncertaintyMargin
        let routeToCurrent = course.plan(first: .current).map { path($0, from: input.boatPosition) } ?? [input.boatPosition]
        let routeToOther = course.plan(first: .other).map { path($0, from: input.boatPosition) } ?? [input.boatPosition]
        var reasons: [String] = []
        var recommendation: Recommendation = .hold
        var title = "Kontranı koru"
        var message = "Mevcut kazanç, ek manevra kaybını karşılamıyor. Rüzgârın ortalamaya göre hareketini izle."
        var trigger = "Kayma kalıcılaşır ve net kazanç artarsa yeniden değerlendir."

        if feasible {
            reasons.append(isLongTack
                ? "Uzun kontradasın; şamandıraya kalan sürenin daha büyük kısmı bu kontrada."
                : "Kısa kontradasın; uzun kontraya dönüş için layline ve basıncı birlikte izle.")
        }
        if abs(signedShift) <= input.windUncertainty {
            reasons.append("Rüzgâr kayması ±\(number(input.windUncertainty))° belirsizlik bandında; tek örnek manevra gerekçesi değil.")
        } else {
            let shiftName = signedShift * tackSign > 0 ? "açan" : "kısan"
            let use = favorableShift > 0 ? "mevcut kontrayı destekliyor" : "diğer kontrayı değerlendirmeyi gerektiriyor"
            reasons.append("Ortalamaya göre \(number(abs(signedShift)))° \(shiftName), \(input.leg.title.lowercased()) seyirde \(use).")
        }
        reasons.append("Senaryo kazancı \(number(gain)) sn; \(input.additionalManeuvers) ek manevranın kaybı \(number(cost)) sn.")
        if input.pressureAdvantage != 0 {
            reasons.append("Diğer kontradaki %\(number(input.pressureAdvantage)) hız farkı kullanıcı tahminidir; basınç katkısı yaklaşık \(number(pressureGain)) sn.")
        }
        if input.dirtyAir {
            reasons.append("Kirli hava işaretli: temiz hava koridorunu ve rakipleri görsel olarak doğrula.")
        }
        if input.currentEast != 0 || input.currentNorth != 0 {
            reasons.append("Layline, COG ve süreler akıntı eklenmiş yer hızından hesaplandı.")
        }

        if !valid {
            title = "Veriyi doğrula"
            message = "Bazı değerler geçersiz veya model sınırlarının dışında. Hesap güvenli aralıklara alındı; manevra önerisi durduruldu."
            trigger = "Rüzgâr, hız, açı ve konum değerlerini kontrol et."
            reasons.append("Girişler normalleştirildi; düzeltilmiş verilerle yeniden hesapla.")
        } else if distance <= 5 {
            title = "Şamandıra bölgesi"
            message = "Hedefe ulaştın. Bir sonraki bacak ve şamandıra dönüşüne odaklan."
            trigger = "Yeni bacağın hedefini seç."
        } else if input.boatSpeed < 0.2 || course.eta == nil {
            title = "Hızı ve rotayı doğrula"
            message = "Mevcut hız ve akıntıyla güvenilir ileri rota hesaplanamıyor."
            trigger = "Tekne hızı ve akıntı ölçümünü kontrol et."
        } else if let current = course.rawCurrentSeconds, current < -2 {
            recommendation = .maneuver
            title = "Layline geride kaldı"
            message = "Mevcut kontra şamandıradan uzaklaştırıyor. \(maneuver) sonrası doğrudan yaklaşım açısını kontrol et."
            trigger = "Manevra koridoru açıksa \(maneuverLower) hazırla."
            reasons.append("Bu bir geometri düzeltmesi; kaymayı kovalama önerisi değil.")
        } else if let current = course.currentSeconds, let other = course.otherSeconds,
                  current <= 8, other > 8 {
            recommendation = .maneuver
            title = "Layline'a geldin"
            message = "\(maneuver) sonrası hedefe giden son kontra başlıyor. Rüzgâr ve akıntıyı tekrar kontrol et."
            trigger = "Hedef açısı ve manevra koridoru doğrulanınca dön."
        } else if input.finalApproach, let other = course.otherSeconds, other > 8 {
            recommendation = .prepare
            title = "Hedef artık yatmıyor"
            message = "Son yaklaşımda şamandırayı tutmak için yaklaşık \(number(other)) sn karşı kontra gerekiyor. Tekneyi aşırı sıkmadan düzeltme manevrasını planla."
            trigger = "Kafalama sürüyorsa temiz alanda düzelt; son tekne boylarına bırakma."
        } else if input.finalApproach {
            title = "Son yaklaşımı koru"
            message = "Şamandıra yaklaşımında küçük kaymalar için ek manevra açma. Hedef açısı, trafik ve hız öncelikli."
            trigger = "Hedef artık yatmıyorsa veya koridor kapanırsa yeniden değerlendir."
            reasons.append("Son yaklaşım seçili; yalnızca zorunlu geometri düzeltmeleri manevra tetikler.")
        } else if let other = course.rawOtherSeconds, other < -2 {
            title = "Şamandıraya açıl"
            message = "Mevcut kontra yönünde layline dışındasın. Sabit hedef açı yerine şamandıraya doğrudan yaklaşımı değerlendir."
            trigger = "Başını şamandıraya ayarlarken hızını ve trafiği koru."
            reasons.append("Doğrudan rota süresi sabit tekne hızı varsayar; apaz poları içermez.")
        } else if let current = layline, let other = course.otherSeconds,
                  current <= 40, other > 8 {
            recommendation = .prepare
            title = "Layline yaklaşıyor"
            message = "Mevcut rüzgâr ve akıntı sabit kalırsa yaklaşık \(number(current)) sn sonra dönüş hattındasın."
            trigger = "Ekibi hazırla; layline'ı her yeni rüzgâr örneğinde doğrula."
        } else if robustGain, horizon >= 30,
                  shiftResolved || input.pressureAdvantage > 0 {
            recommendation = .maneuver
            title = "\(maneuver) avantajlı"
            message = "Bu senaryoda diğer kontra, ek manevra kaybından sonra yaklaşık \(number(gain - cost)) sn kazandırıyor."
            trigger = "Kaymanın sürekliliğini ve temiz hava koridorunu doğrulayarak dön."
        } else if input.dirtyAir {
            recommendation = .prepare
            title = "Temiz hava koridoru ara"
            message = "Kirli hava hızını etkileyebilir. Rakip geometrisini ve açık koridoru görmeden otomatik manevra yapma."
            trigger = "Temiz hava için rota veya kontra seçeneğini doğrula."
        } else if gain > cost || (favorableShift < -input.windUncertainty && gain > cost * 0.5) {
            recommendation = .prepare
            title = "Kaymayı doğrula"
            message = "Diğer kontra umut veriyor; kazanç henüz belirsizlik payını güvenle aşmıyor."
            trigger = "Yeni ölçümde kayma sürer ve kazanç maliyeti aşarsa dön."
        } else if favorableShift > input.windUncertainty {
            title = input.leg == .upwind ? "Açanı kullan" : "Kısanı kullan"
            message = "Rüzgâr kayması mevcut kontrayı destekliyor. Hızını koru, layline'a kalan süreyi izle."
        }

        let confidence: AnalysisConfidence
        if !valid || course.eta == nil || !shiftResolved || horizon < 30 {
            confidence = .low
        } else if abs(signedShift) > 2 * input.windUncertainty + 2 && horizon >= 90 && feasible {
            confidence = .high
        } else {
            confidence = .medium
        }
        return RaceAnalysis(
            recommendation: recommendation, title: title, message: message, trigger: trigger,
            signedShift: signedShift, favorableShift: favorableShift, heading: currentHeading,
            cog: cog, vmg: vmg, vmc: vmc, distanceToMark: distance, etaSeconds: course.eta,
            currentTackSeconds: course.currentSeconds, otherTackSeconds: course.otherSeconds,
            laylineSeconds: layline, isLongTack: isLongTack, isOverstood: isOverstood,
            expectedGainSeconds: gain, costSeconds: cost, reasons: reasons, confidence: confidence,
            geometry: RaceGeometry(boat: input.boatPosition, mark: input.markPosition,
                                   currentGroundVector: velocity, otherGroundVector: otherVelocity,
                                   currentRoute: routeToCurrent, otherRoute: routeToOther,
                                   currentHeading: currentHeading, otherHeading: otherHeading)
        )
    }

    private enum FirstTack { case current, other }
    private struct Segment {
        let velocity: Point
        let seconds: Double
    }
    private struct Course {
        var rawCurrentSeconds: Double?
        var rawOtherSeconds: Double?
        var currentSeconds: Double?
        var otherSeconds: Double?
        var currentVelocity: Point
        var otherVelocity: Point
        var direct: Segment?

        var eta: Double? {
            if let currentSeconds, let otherSeconds { return currentSeconds + otherSeconds }
            return direct?.seconds
        }

        func plan(first: FirstTack) -> [Segment]? {
            if let currentSeconds, let otherSeconds {
                let current = Segment(velocity: currentVelocity, seconds: currentSeconds)
                let other = Segment(velocity: otherVelocity, seconds: otherSeconds)
                return first == .current ? [current, other] : [other, current]
            }
            return direct.map { [$0] }
        }
    }

    private static func solve(_ input: RaceInput, from boat: Point, wind: Double) -> Course {
        let v1 = groundVector(heading: heading(windDirection: wind, targetAngle: input.targetAngle, tack: input.tack),
                              speed: input.boatSpeed, currentEast: input.currentEast, currentNorth: input.currentNorth)
        let v2 = groundVector(heading: heading(windDirection: wind, targetAngle: input.targetAngle, tack: input.tack.opposite),
                              speed: input.boatSpeed, currentEast: input.currentEast, currentNorth: input.currentNorth)
        let delta = input.markPosition - boat
        var result = Course(currentVelocity: v1, otherVelocity: v2)
        if delta.length <= 1e-7 {
            result.currentSeconds = 0
            result.otherSeconds = 0
            return result
        }
        let determinant = v1.cross(v2)
        let relativeThreshold = max(1e-10, v1.length * v2.length * 1e-8)
        if abs(determinant) > relativeThreshold {
            let current = delta.cross(v2) / determinant
            let other = v1.cross(delta) / determinant
            if current.isFinite && other.isFinite {
                result.rawCurrentSeconds = current
                result.rawOtherSeconds = other
                if current >= -1e-7 && other >= -1e-7 {
                    result.currentSeconds = max(0, current)
                    result.otherSeconds = max(0, other)
                }
            }
        }
        // A negative leg is not a valid two-tack route. An outside-layline mark
        // can instead be reached with a current-compensated direct course.
        if result.currentSeconds == nil {
            result.direct = directReach(input, delta: delta, wind: wind)
        }
        return result
    }

    private static func directReach(_ input: RaceInput, delta: Point, wind: Double) -> Segment? {
        let unit = delta / delta.length
        let current = Point(east: input.currentEast, north: input.currentNorth) * metersPerSecondPerKnot
        let speed = input.boatSpeed * metersPerSecondPerKnot
        let alongCurrent = current.dot(unit)
        let acrossSquared = max(0, current.dot(current) - alongCurrent * alongCurrent)
        let discriminant = speed * speed - acrossSquared
        guard discriminant >= 0 else { return nil }
        let groundSpeed = alongCurrent + sqrt(discriminant)
        guard groundSpeed > 1e-7 else { return nil }
        let ground = unit * groundSpeed
        let waterHeading = bearing(ground - current)
        let windAngle = abs(signedAngle(waterHeading - wind))
        // Upwind target is a no-go boundary; downwind reaching is allowed only
        // on its reaching side, at >=45° true wind angle. No dead-downwind polar.
        let sailable = input.leg == .upwind
            ? windAngle + 1e-7 >= input.targetAngle
            : windAngle >= 45 && windAngle <= input.targetAngle + 1e-7
        guard sailable else { return nil }
        return Segment(velocity: ground, seconds: delta.length / groundSpeed)
    }

    private static func scenarioGain(_ input: RaceInput, course: Course, horizon: Double) -> Double? {
        guard horizon > 0,
              course.currentSeconds != nil, course.otherSeconds != nil,
              let hold = course.plan(first: .current), let change = course.plan(first: .other)
        else { return horizon == 0 ? 0 : nil }
        func elapsedToMark(_ plan: [Segment]) -> Double? {
            let elapsed = min(horizon, course.eta ?? horizon)
            let position = advance(plan, from: input.boatPosition, seconds: elapsed)
            let remainder = solve(input, from: position, wind: input.meanWindDirection)
            return remainder.eta.map { elapsed + $0 }
        }
        guard let holdTime = elapsedToMark(hold), let changeTime = elapsedToMark(change) else { return nil }
        return holdTime - changeTime
    }

    private static func path(_ plan: [Segment], from boat: Point) -> [Point] {
        var result = [boat]
        var position = boat
        for segment in plan where segment.seconds > 1e-7 {
            position = position + segment.velocity * segment.seconds
            result.append(position)
        }
        return result
    }

    private static func advance(_ plan: [Segment], from boat: Point, seconds: Double) -> Point {
        var position = boat
        var remaining = seconds
        for segment in plan {
            let elapsed = min(remaining, segment.seconds)
            position = position + segment.velocity * elapsed
            remaining -= elapsed
            if remaining <= 0 { break }
        }
        return position
    }

    private static func sanitized(_ input: RaceInput) -> RaceInput {
        var result = input
        result.windDirection = normalizeDegrees(input.windDirection)
        result.meanWindDirection = normalizeDegrees(input.meanWindDirection)
        result.windSpeed = bounded(input.windSpeed, fallback: 14, in: 0...100)
        result.boatSpeed = bounded(input.boatSpeed, fallback: 0, in: 0...60)
        result.targetAngle = bounded(input.targetAngle, fallback: input.leg == .upwind ? 45 : 145,
                                     in: input.leg == .upwind ? 20...85 : 95...175)
        result.boatPosition = boundedPoint(input.boatPosition)
        result.markPosition = boundedPoint(input.markPosition)
        result.currentEast = bounded(input.currentEast, fallback: 0, in: -20...20)
        result.currentNorth = bounded(input.currentNorth, fallback: 0, in: -20...20)
        result.maneuverLossSeconds = bounded(input.maneuverLossSeconds, fallback: 12, in: 0...600)
        result.additionalManeuvers = min(10, max(0, input.additionalManeuvers))
        result.expectedShiftDuration = bounded(input.expectedShiftDuration, fallback: 0, in: 0...3600)
        result.windUncertainty = bounded(input.windUncertainty, fallback: 5, in: 0...60)
        result.pressureAdvantage = bounded(input.pressureAdvantage, fallback: 0, in: -50...50)
        return result
    }

    private static func boundedPoint(_ point: Point) -> Point {
        Point(east: bounded(point.east, fallback: 0, in: -10_000_000...10_000_000),
              north: bounded(point.north, fallback: 0, in: -10_000_000...10_000_000))
    }

    private static func bounded(_ value: Double, fallback: Double, in range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    private static func direction(_ angle: Double) -> Point {
        let rad = radians(normalizeDegrees(angle))
        return Point(east: sin(rad), north: cos(rad))
    }
    private static func radians(_ angle: Double) -> Double { angle * .pi / 180 }
    private static func bearing(_ vector: Point) -> Double {
        normalizeDegrees(atan2(vector.east, vector.north) * 180 / .pi)
    }
    private static func number(_ number: Double) -> String { String(format: "%.0f", number) }
}

private extension Point {
    var length: Double { hypot(east, north) }
    func dot(_ other: Point) -> Double { east * other.east + north * other.north }
    func cross(_ other: Point) -> Double { east * other.north - north * other.east }
    static func + (lhs: Point, rhs: Point) -> Point { Point(east: lhs.east + rhs.east, north: lhs.north + rhs.north) }
    static func - (lhs: Point, rhs: Point) -> Point { Point(east: lhs.east - rhs.east, north: lhs.north - rhs.north) }
    static func * (lhs: Point, rhs: Double) -> Point { Point(east: lhs.east * rhs, north: lhs.north * rhs) }
    static func / (lhs: Point, rhs: Double) -> Point { Point(east: lhs.east / rhs, north: lhs.north / rhs) }
}
