import XCTest
@testable import RaceCore

final class SailingAlertsTests: XCTestCase {
    func testFiniteStartSegmentDistanceAndReversedPins() throws {
        let a = Point.zero, b = Point(east: 100, north: 0)
        let inside = try XCTUnwrap(StartLineMeasurement.measure(boat: Point(east: 50, north: 30), committee: a, port: b))
        XCTAssertEqual(inside.distanceMeters, 30, accuracy: 0.001)
        XCTAssertFalse(inside.isBeyondEndpoint)
        XCTAssertEqual(StartLineMeasurement.measure(boat: Point(east: 50, north: 30), committee: b, port: a), inside)
        let outside = try XCTUnwrap(StartLineMeasurement.measure(boat: Point(east: 130, north: 40), committee: a, port: b))
        XCTAssertEqual(outside.distanceMeters, 50, accuracy: 0.001)
        XCTAssertTrue(outside.isBeyondEndpoint)
        XCTAssertEqual(StartLineMeasurement.measure(boat: a, committee: a, port: b)?.distanceMeters, 0)
    }

    func testInvalidAndDegenerateLinesAreUnavailable() {
        XCTAssertNil(StartLineMeasurement.measure(boat: .zero, committee: .zero, port: .zero))
        XCTAssertNil(StartLineMeasurement.measure(boat: .zero, committee: .zero, port: Point(east: 10001, north: 0)))
        XCTAssertNil(StartLineMeasurement.measure(boat: Point(east: .nan, north: 0), committee: .zero, port: Point(east: 100, north: 0)))
    }

    func testProximityHysteresisAndStaleReset() {
        var latch = ProximityLatch()
        latch.update(31, enter: 30, exit: 40); XCTAssertFalse(latch.isNear)
        latch.update(30, enter: 30, exit: 40); XCTAssertTrue(latch.isNear)
        latch.update(39, enter: 30, exit: 40); XCTAssertTrue(latch.isNear)
        latch.update(41, enter: 30, exit: 40); XCTAssertFalse(latch.isNear)
        latch.update(0, enter: 30, exit: 40); XCTAssertTrue(latch.isNear)
        latch.update(nil, enter: 30, exit: 40); XCTAssertFalse(latch.isNear)
        latch.update(-1, enter: 30, exit: 40); XCTAssertFalse(latch.isNear)
    }

    private let start = Date(timeIntervalSince1970: 1000)
    private func sample(_ value: Double, _ second: Int) -> TelemetrySample<Double> {
        TelemetrySample(value: value, timestamp: start.addingTimeInterval(Double(second)))
    }
    private func warmedMonitor() -> SpeedDropMonitor {
        var monitor = SpeedDropMonitor()
        for second in 0...10 { monitor.record(sample(6, second), reference: .water, at: sample(6, second).timestamp) }
        return monitor
    }

    func testSustainedLossTriggersAndRecoveryClears() throws {
        var monitor = warmedMonitor()
        for second in 11...15 { monitor.record(sample(4.5, second), reference: .water, at: sample(4.5, second).timestamp) }
        XCTAssertNil(monitor.warning)
        monitor.record(sample(4.5, 16), reference: .water, at: sample(4.5, 16).timestamp)
        XCTAssertEqual(try XCTUnwrap(monitor.warning).baselineKnots, 6, accuracy: 0.001)
        for second in 17...60 { monitor.record(sample(4.5, second), reference: .water, at: sample(4.5, second).timestamp) }
        XCTAssertNotNil(monitor.warning)
        monitor.record(sample(6, 61), reference: .water, at: sample(6, 61).timestamp)
        XCTAssertNil(monitor.warning)
    }

    func testTransientLossAndNoiseDoNotTrigger() {
        var monitor = warmedMonitor()
        for second in 11...14 { monitor.record(sample(4, second), reference: .water, at: sample(4, second).timestamp) }
        monitor.record(sample(6, 15), reference: .water, at: sample(6, 15).timestamp)
        for second in 16...40 { monitor.record(sample(5.8, second), reference: .water, at: sample(5.8, second).timestamp) }
        XCTAssertNil(monitor.warning)
    }

    func testRepeatedSamplesDoNotCountAndStaleDataResets() {
        var monitor = warmedMonitor()
        let firstDrop = sample(4, 11)
        monitor.record(firstDrop, reference: .water, at: firstDrop.timestamp)
        monitor.record(firstDrop, reference: .water, at: start.addingTimeInterval(20))
        XCTAssertNil(monitor.warning)
        monitor.record(firstDrop, reference: .water, at: start.addingTimeInterval(27))
        monitor.record(sample(4, 28), reference: .water, at: start.addingTimeInterval(28))
        XCTAssertNil(monitor.warning)
    }

    func testChangingSourceOrLosingSamplesRequiresNewBaseline() {
        var monitor = warmedMonitor()
        for second in 11...16 { monitor.record(sample(4, second), reference: .ground, at: sample(4, second).timestamp) }
        XCTAssertNil(monitor.warning)
        monitor = warmedMonitor()
        for second in 20...25 { monitor.record(sample(4, second), reference: .water, at: sample(4, second).timestamp) }
        XCTAssertNil(monitor.warning)
    }
}
