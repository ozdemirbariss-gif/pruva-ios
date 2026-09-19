import SwiftUI

/// Local race coordinates, in meters: x points east and y points north.
struct MapPoint: Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A north-up race diagram. Wind is FROM true degrees; all speeds are in knots.
/// Downwind angles may be an absolute TWA (145°) or the angle off dead downwind (35°).
struct TacticalMapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var boat: MapPoint
    var mark: MapPoint
    var windDirection: Double
    var meanWindDirection: Double
    var targetAngle: Double
    var isDownwind: Bool
    var isStarboard: Bool
    var currentEast: Double
    var currentNorth: Double
    var boatSpeed: Double
    var uncertainty: Double
    var showLaylines: Bool
    var showTrail: Bool
    var onBoatMove: ((MapPoint) -> Void)?
    var measuredHeading: Double?
    var windSpeed: Double?
    var sensorMode: Bool
    var windAvailable: Bool
    var boatAvailable: Bool
    var showMark: Bool
    var startCommittee: MapPoint?
    var startPort: MapPoint?

    @State private var trail: [MapPoint] = []

    init(
        boat: MapPoint,
        mark: MapPoint,
        windDirection: Double,
        meanWindDirection: Double,
        targetAngle: Double,
        isDownwind: Bool,
        isStarboard: Bool,
        currentEast: Double,
        currentNorth: Double,
        boatSpeed: Double,
        uncertainty: Double,
        showLaylines: Bool,
        showTrail: Bool,
        onBoatMove: ((MapPoint) -> Void)? = nil,
        measuredHeading: Double? = nil,
        windSpeed: Double? = nil,
        sensorMode: Bool = false,
        windAvailable: Bool = true,
        boatAvailable: Bool = true,
        showMark: Bool = true,
        startCommittee: MapPoint? = nil,
        startPort: MapPoint? = nil
    ) {
        self.boat = boat
        self.mark = mark
        self.windDirection = windDirection
        self.meanWindDirection = meanWindDirection
        self.targetAngle = targetAngle
        self.isDownwind = isDownwind
        self.isStarboard = isStarboard
        self.currentEast = currentEast
        self.currentNorth = currentNorth
        self.boatSpeed = boatSpeed
        self.uncertainty = uncertainty
        self.showLaylines = showLaylines
        self.showTrail = showTrail
        self.onBoatMove = onBoatMove
        self.measuredHeading = measuredHeading
        self.windSpeed = windSpeed
        self.sensorMode = sensorMode
        self.windAvailable = windAvailable
        self.boatAvailable = boatAvailable
        self.showMark = showMark
        self.startCommittee = startCommittee
        self.startPort = startPort
    }

    var body: some View {
        GeometryReader { geometry in
            let chart = ChartProjection(size: geometry.size, points: framingPoints)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.clip(to: Path(CGRect(origin: .zero, size: size)))
                    drawWater(context: &context, size: size)
                    drawGrid(context: &context, chart: chart)
                    if showMark && windAvailable { drawCourse(context: &context, chart: chart) }
                    if showLaylines && windAvailable && showMark {
                        drawLaylines(context: &context, chart: chart)
                        drawRoutes(context: &context, chart: chart)
                    }
                    if showTrail { drawTrail(context: &context, chart: chart) }
                    drawStartLine(context: &context, chart: chart)
                    if showMark { drawMark(context: &context, point: chart.screen(mark)) }
                    if boatAvailable { drawBoat(context: &context, point: chart.screen(boat)) }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in
                    onBoatMove?(chart.world(event.location))
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kuzey yukarı yarış şeması")
                .accessibilityValue(sensorMode
                    ? "\(boatAvailable ? "Güncel GPS konumu" : "GPS bekleniyor"). \(windAvailable ? "Rüzgâr \(Int(normalized(windDirection))) derece" : "Rüzgâr bekleniyor"). \(showMark ? "Şamandıra tanımlı" : "Şamandıra ekleyin"). \(startCommittee != nil && startPort != nil ? "Start hattı tanımlı" : "Start hattı eksik")."
                    : "Şamandıraya \(Int(distanceToMark)) metre. \(isStarboard ? "Sancak" : "İskele") kontra. Rüzgâr \(Int(normalized(windDirection))) derece.")

                Group {
                    if windAvailable { windBadge }
                    else { Text("RÜZGÂR BEKLENİYOR").font(.system(size: 9, weight: .semibold)).foregroundStyle(MapPalette.slate) }
                }
                    .padding(.leading, 19)
                    .padding(.top, 18)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        northIndicator
                    }
                    Spacer()
                    mapFooter(chart: chart)
                }
                .padding(18)
                .allowsHitTesting(false)
            }
            .background(MapPalette.water)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MapPalette.slate.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { remember(boat) }
        .onChange(of: boat) { _, newPoint in remember(newPoint) }
    }

    private var sailingAngle: Double {
        let angle = min(max(targetAngle.isFinite ? targetAngle : 45, 1), 179)
        return isDownwind && angle < 90 ? 180 - angle : angle
    }

    private var distanceToMark: Double { hypot(mark.x - boat.x, mark.y - boat.y) }

    private func heading(starboard: Bool, wind: Double? = nil) -> Double {
        (wind ?? windDirection) + (starboard ? -sailingAngle : sailingAngle)
    }

    private func groundVector(starboard: Bool, wind: Double? = nil) -> Vector {
        let radians = heading(starboard: starboard, wind: wind) * .pi / 180
        let speed = max(boatSpeed, 0)
        return Vector(
            x: sin(radians) * speed + currentEast,
            y: cos(radians) * speed + currentNorth
        )
    }

    private var route: TackRoute? {
        let starboard = groundVector(starboard: true).unit
        let port = groundVector(starboard: false).unit
        guard starboard.length > 0, port.length > 0 else { return nil }
        let displacement = Vector(x: mark.x - boat.x, y: mark.y - boat.y)
        let determinant = starboard.x * port.y - starboard.y * port.x
        guard abs(determinant) > 0.0001 else { return nil }
        let starboardLength = (displacement.x * port.y - displacement.y * port.x) / determinant
        let portLength = (starboard.x * displacement.y - starboard.y * displacement.x) / determinant
        guard starboardLength >= 0, portLength >= 0,
              starboardLength + portLength < max(distanceToMark, 100) * 8 else { return nil }
        return TackRoute(
            starboardTurn: boat.offset(starboard, distance: starboardLength),
            portTurn: boat.offset(port, distance: portLength),
            starboardLength: starboardLength,
            portLength: portLength
        )
    }

    private var framingPoints: [MapPoint] {
        var result = boatAvailable ? [boat] : []
        if showMark { result.append(mark) }
        if let startCommittee { result.append(startCommittee) }
        if let startPort { result.append(startPort) }
        if result.isEmpty || (!showMark && result.count == 1) {
            return [MapPoint(x: boat.x - 500, y: boat.y - 500), MapPoint(x: boat.x + 500, y: boat.y + 500)]
        }
        if showMark && showLaylines, let route {
            result.append(route.starboardTurn)
            result.append(route.portTurn)
        }
        return result
    }

    private func drawStartLine(context: inout GraphicsContext, chart: ChartProjection) {
        let committeePoint = startCommittee.map(chart.screen)
        let portPoint = startPort.map(chart.screen)
        if let startCommittee, let startPort {
            var line = Path()
            line.move(to: chart.screen(startCommittee))
            line.addLine(to: chart.screen(startPort))
            context.stroke(line, with: .color(MapPalette.gold),
                           style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
        let labelsSideBySide = abs((committeePoint?.y ?? 0) - (portPoint?.y ?? 100)) < 16
        if let committeePoint {
            let offset: CGFloat = labelsSideBySide || committeePoint.y < (portPoint?.y ?? .infinity) ? -24 : 24
            drawStartPin(context: &context, point: committeePoint,
                         color: MapPalette.teal, label: "KOMİTE · STBD", labelOffset: offset)
        }
        if let portPoint {
            let offset: CGFloat = labelsSideBySide || portPoint.y > (committeePoint?.y ?? -.infinity) ? 24 : -24
            let labelX = min(max(portPoint.x + 45, 60), chart.size.width - 60)
            drawStartPin(context: &context, point: portPoint,
                         color: MapPalette.gold, label: "PIN · PORT", labelOffset: offset,
                         labelX: labelX)
        }
    }

    private func drawStartPin(context: inout GraphicsContext, point: CGPoint, color: Color,
                              label: String, labelOffset: CGFloat, labelX: CGFloat? = nil) {
        let halo = Path(ellipseIn: CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30))
        context.fill(halo, with: .color(color.opacity(0.23)))
        let pin = Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        context.fill(pin, with: .color(color))
        context.stroke(pin, with: .color(.white), lineWidth: 2)
        drawPill(text: label, at: CGPoint(x: labelX ?? point.x, y: point.y + labelOffset), context: &context)
    }

    private var windBadge: some View {
        HStack(spacing: 10) {
            WindArrow()
                .fill(MapPalette.teal)
                .frame(width: 15, height: 30)
                .rotationEffect(.degrees(windDirection))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: windDirection)
                .frame(width: 32, height: 32)
                .background(Palette.surface.opacity(0.9), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("RÜZGÂR")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(MapPalette.slate.opacity(0.5))
                Text(String(format: "%03.0f°", normalized(windDirection)))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(MapPalette.slate)
                if let windSpeed { Text(String(format: "%.1f kn", windSpeed)).font(.system(size: 10, weight: .medium)).foregroundStyle(MapPalette.teal) }
            }
        }
    }

    private var northIndicator: some View {
        VStack(spacing: 3) {
            Text("N")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
            Image(systemName: "location.north.fill")
                .font(.system(size: 14, weight: .regular))
        }
        .foregroundStyle(MapPalette.slate.opacity(0.5))
        .frame(width: 22, height: 37)
    }

    private func mapFooter(chart: ChartProjection) -> some View {
        let meters = scaleDistance(for: chart.scale)
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(meters)) m")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                ScaleBar()
                    .stroke(MapPalette.slate.opacity(0.42), lineWidth: 1)
                    .frame(width: meters * chart.scale, height: 5)
            }
            .foregroundStyle(MapPalette.slate.opacity(0.5))
            Spacer(minLength: 0)
            if showLaylines && windAvailable && showMark {
                HStack(spacing: 11) {
                    legend("Sancak", color: MapPalette.teal)
                    legend("İskele", color: MapPalette.port)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color.opacity(0.7)).frame(width: 12, height: 2)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MapPalette.slate.opacity(0.6))
        }
    }

    private func drawWater(context: inout GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [MapPalette.water, Color(red: 0.84, green: 0.91, blue: 0.89)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)
            )
        )
    }

    private func drawGrid(context: inout GraphicsContext, chart: ChartProjection) {
        let spacing = scaleDistance(for: chart.scale) / 2
        let minimum = chart.world(CGPoint(x: 0, y: chart.size.height))
        let maximum = chart.world(CGPoint(x: chart.size.width, y: 0))
        var path = Path()
        var x = floor(minimum.x / spacing) * spacing
        while x <= maximum.x {
            path.move(to: chart.screen(MapPoint(x: x, y: minimum.y)))
            path.addLine(to: chart.screen(MapPoint(x: x, y: maximum.y)))
            x += spacing
        }
        var y = floor(minimum.y / spacing) * spacing
        while y <= maximum.y {
            path.move(to: chart.screen(MapPoint(x: minimum.x, y: y)))
            path.addLine(to: chart.screen(MapPoint(x: maximum.x, y: y)))
            y += spacing
        }
        context.stroke(path, with: .color(MapPalette.slate.opacity(0.12)), lineWidth: 0.8)
    }

    private func drawCourse(context: inout GraphicsContext, chart: ChartProjection) {
        var centerline = Path()
        centerline.move(to: chart.screen(boat))
        centerline.addLine(to: chart.screen(mark))
        context.stroke(centerline, with: .color(MapPalette.slate.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
        // The mean-wind reference makes a shift visible without implying a geographic bearing line.
        let angle = (meanWindDirection + (isDownwind ? 180 : 0)) * .pi / 180
        let mean = Vector(x: sin(angle), y: cos(angle))
        let start = chart.screen(mark.offset(mean, distance: -45 / chart.scale))
        let end = chart.screen(mark.offset(mean, distance: 24 / chart.scale))
        var windReference = Path()
        windReference.move(to: start)
        windReference.addLine(to: end)
        context.stroke(windReference, with: .color(MapPalette.gold.opacity(0.38)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    private func drawLaylines(context: inout GraphicsContext, chart: ChartProjection) {
        let rayLength = hypot(chart.size.width, chart.size.height) / chart.scale * 1.4
        for starboard in [true, false] {
            let color = starboard ? MapPalette.teal : MapPalette.port
            let vector = groundVector(starboard: starboard).unit
            guard vector.length > 0 else { continue }
            let uncertaintyAngle = min(max(uncertainty, 0), 35)
            if uncertaintyAngle > 0 {
                let left = groundVector(starboard: starboard, wind: windDirection - uncertaintyAngle).unit
                let right = groundVector(starboard: starboard, wind: windDirection + uncertaintyAngle).unit
                var band = Path()
                band.move(to: chart.screen(mark))
                band.addLine(to: chart.screen(mark.offset(left, distance: -rayLength)))
                band.addLine(to: chart.screen(mark.offset(right, distance: -rayLength)))
                band.closeSubpath()
                context.fill(band, with: .color(color.opacity(0.075)))
            }
            var ray = Path()
            ray.move(to: chart.screen(mark))
            ray.addLine(to: chart.screen(mark.offset(vector, distance: -rayLength)))
            context.stroke(ray, with: .color(color.opacity(0.66)), style: StrokeStyle(lineWidth: 1.6, dash: starboard ? [9, 5] : [3, 5]))
        }
    }

    private func drawRoutes(context: inout GraphicsContext, chart: ChartProjection) {
        guard let route else { return }
        let activeTurn = isStarboard ? route.starboardTurn : route.portTurn
        let alternateTurn = isStarboard ? route.portTurn : route.starboardTurn
        var alternate = Path()
        alternate.move(to: chart.screen(boat))
        alternate.addLine(to: chart.screen(alternateTurn))
        alternate.addLine(to: chart.screen(mark))
        context.stroke(alternate, with: .color(MapPalette.slate.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

        var firstLeg = Path()
        firstLeg.move(to: chart.screen(boat))
        firstLeg.addLine(to: chart.screen(activeTurn))
        context.stroke(firstLeg, with: .color(MapPalette.teal.opacity(0.65)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var secondLeg = Path()
        secondLeg.move(to: chart.screen(activeTurn))
        secondLeg.addLine(to: chart.screen(mark))
        context.stroke(secondLeg, with: .color(MapPalette.teal.opacity(0.42)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5]))

        let turn = chart.screen(activeTurn)
        if hypot(turn.x - chart.screen(boat).x, turn.y - chart.screen(boat).y) > 24,
           hypot(turn.x - chart.screen(mark).x, turn.y - chart.screen(mark).y) > 24 {
            let ring = Path(ellipseIn: CGRect(x: turn.x - 4, y: turn.y - 4, width: 8, height: 8))
            context.fill(ring, with: .color(.white))
            context.stroke(ring, with: .color(MapPalette.teal.opacity(0.7)), lineWidth: 1.5)
        }
    }

    private func drawTrail(context: inout GraphicsContext, chart: ChartProjection) {
        guard trail.count > 1 else { return }
        var path = Path()
        path.move(to: chart.screen(trail[0]))
        for point in trail.dropFirst() { path.addLine(to: chart.screen(point)) }
        context.stroke(path, with: .color(MapPalette.slate.opacity(0.2)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func drawMark(context: inout GraphicsContext, point: CGPoint) {
        let halo = Path(ellipseIn: CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56))
        context.fill(halo, with: .color(MapPalette.gold.opacity(0.17)))
        let ring = Path(ellipseIn: CGRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36))
        context.stroke(ring, with: .color(MapPalette.gold.opacity(0.75)), lineWidth: 2)
        let buoy = Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        context.fill(buoy, with: .color(MapPalette.gold))
        context.stroke(buoy, with: .color(.white), lineWidth: 3)
        context.draw(
            Text(isDownwind ? "2" : "1").font(.system(size: 11, weight: .bold)).foregroundColor(.white),
            at: point
        )
        drawPill(
            text: isDownwind ? "ALT ŞAMANDIRA" : "ÜST ŞAMANDIRA",
            at: CGPoint(x: point.x, y: point.y - 39),
            context: &context
        )
    }

    private func drawBoat(context: inout GraphicsContext, point: CGPoint) {
        if sensorMode && measuredHeading == nil {
            let dot = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            context.fill(dot, with: .color(MapPalette.teal))
            context.stroke(dot, with: .color(.white), lineWidth: 2)
            return
        }
        var local = context
        local.translateBy(x: point.x, y: point.y)
        local.rotate(by: .degrees(measuredHeading ?? heading(starboard: isStarboard)))
        var wake = Path()
        wake.move(to: CGPoint(x: -4, y: 12))
        wake.addQuadCurve(to: CGPoint(x: -11, y: 35), control: CGPoint(x: -7, y: 24))
        wake.move(to: CGPoint(x: 4, y: 12))
        wake.addQuadCurve(to: CGPoint(x: 11, y: 35), control: CGPoint(x: 7, y: 24))
        local.stroke(wake, with: .color(MapPalette.teal.opacity(0.19)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        var hull = Path()
        hull.move(to: CGPoint(x: 0, y: -17))
        hull.addCurve(to: CGPoint(x: 7, y: 11), control1: CGPoint(x: 7, y: -8), control2: CGPoint(x: 8, y: 4))
        hull.addQuadCurve(to: CGPoint(x: -7, y: 11), control: CGPoint(x: 0, y: 14))
        hull.addCurve(to: CGPoint(x: 0, y: -17), control1: CGPoint(x: -8, y: 4), control2: CGPoint(x: -7, y: -8))
        hull.closeSubpath()
        local.addFilter(.shadow(color: MapPalette.slate.opacity(0.17), radius: 4, x: 0, y: 3))
        local.fill(hull, with: .color(Palette.ink))
        local.stroke(hull, with: .color(.white), lineWidth: 1.5)
        var deck = Path()
        deck.move(to: CGPoint(x: 0, y: -10))
        deck.addLine(to: CGPoint(x: 0, y: 6))
        local.stroke(deck, with: .color(Color.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        let cockpit = Path(roundedRect: CGRect(x: -2.5, y: 3, width: 5, height: 6), cornerRadius: 1)
        local.fill(cockpit, with: .color(MapPalette.teal))
    }

    private func drawPill(text: String, at point: CGPoint, context: inout GraphicsContext) {
        let label = context.resolve(
            Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundColor(MapPalette.slate.opacity(0.7))
        )
        let measured = label.measure(in: CGSize(width: 170, height: 20))
        let bounds = CGRect(x: point.x - measured.width / 2 - 8, y: point.y - 10, width: measured.width + 16, height: 20)
        context.fill(Path(roundedRect: bounds, cornerRadius: 7), with: .color(Palette.surface.opacity(0.95)))
        context.draw(label, at: point)
    }

    private func remember(_ point: MapPoint) {
        guard trail.last != point else { return }
        trail.append(point)
        if trail.count > 120 { trail.removeFirst(trail.count - 120) }
    }

    private func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    private func scaleDistance(for scale: Double) -> Double {
        let target = 50 / max(scale, 0.0001)
        let magnitude = pow(10, floor(log10(target)))
        let normalized = target / magnitude
        return (normalized >= 5 ? 5 : normalized >= 2 ? 2 : 1) * magnitude
    }
}

private enum MapPalette {
    static let water = Color(red: 0.91, green: 0.95, blue: 0.94)
    static let teal = Palette.teal
    static let slate = Palette.ink
    static let port = Color(red: 0.34, green: 0.43, blue: 0.64)
    static let gold = Palette.gold
}

private struct Vector {
    var x: Double
    var y: Double
    var length: Double { hypot(x, y) }
    var unit: Vector { length > 0.00001 ? Vector(x: x / length, y: y / length) : Vector(x: 0, y: 0) }
}

private extension MapPoint {
    func offset(_ vector: Vector, distance: Double) -> MapPoint {
        MapPoint(x: x + vector.x * distance, y: y + vector.y * distance)
    }
}

private struct TackRoute {
    var starboardTurn: MapPoint
    var portTurn: MapPoint
    var starboardLength: Double
    var portLength: Double
}

private struct ChartProjection {
    let size: CGSize
    let center: MapPoint
    let origin: CGPoint
    let scale: Double

    init(size: CGSize, points: [MapPoint]) {
        self.size = size
        let minX = points.map(\.x).min() ?? -100
        let maxX = points.map(\.x).max() ?? 100
        let minY = points.map(\.y).min() ?? -100
        let maxY = points.map(\.y).max() ?? 100
        center = MapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let availableWidth = max(size.width - 82, 40)
        let availableHeight = max(size.height - 150, 40)
        let worldWidth = max(maxX - minX, 160)
        let worldHeight = max(maxY - minY, 160)
        scale = min(availableWidth / worldWidth, availableHeight / worldHeight)
        origin = CGPoint(x: size.width / 2, y: 84 + availableHeight / 2)
    }

    func screen(_ point: MapPoint) -> CGPoint {
        CGPoint(x: origin.x + (point.x - center.x) * scale, y: origin.y - (point.y - center.y) * scale)
    }

    func world(_ point: CGPoint) -> MapPoint {
        MapPoint(x: center.x + (point.x - origin.x) / scale, y: center.y - (point.y - origin.y) / scale)
    }
}

private struct WindArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middle = rect.midX
        path.move(to: CGPoint(x: middle - 1.3, y: 0))
        path.addLine(to: CGPoint(x: middle + 1.3, y: 0))
        path.addLine(to: CGPoint(x: middle + 1.3, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.49))
        path.addLine(to: CGPoint(x: middle, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.49))
        path.addLine(to: CGPoint(x: middle - 1.3, y: rect.height * 0.58))
        path.closeSubpath()
        return path
    }
}

private struct ScaleBar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        return path
    }
}
