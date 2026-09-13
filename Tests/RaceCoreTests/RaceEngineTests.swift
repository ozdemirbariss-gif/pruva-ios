import XCTest
@testable import RaceCore

final class RaceEngineTests: XCTestCase {
    func testCircularMeanWrapsNorth() throws {
        XCTAssertEqual(try XCTUnwrap(RaceEngine.circularMean([359, 1])), 0, accuracy: 0.001)
        XCTAssertNil(RaceEngine.circularMean([0, 180]))
        XCTAssertNil(RaceEngine.circularMean([]))
    }

    func testLiftUsesMeanRatherThanPreviousReading() {
        var input = RaceInput(windDirection: 10, windUncertainty: 1)
        XCTAssertEqual(RaceEngine.analyze(input).favorableShift, 10)
        input.windDirection = 4
        let analysis = RaceEngine.analyze(input)
        XCTAssertEqual(analysis.favorableShift, 4)
        XCTAssertEqual(analysis.recommendation, .hold)
    }

    func testPortTackReversesLiftSign() {
        let a = RaceEngine.analyze(RaceInput(tack: .port, windDirection: 10))
        XCTAssertEqual(a.favorableShift, -10)
    }

    func testDownwindPrefersHeader() {
        let a = RaceEngine.analyze(DemoScenario.downwind.input)
        XCTAssertEqual(a.favorableShift, 10)
        XCTAssertEqual(a.recommendation, .hold)
        XCTAssertGreaterThan(a.vmg, 0)
    }

    func testSymmetricGeometryAndUnits() throws {
        let a = RaceEngine.analyze(RaceInput(boatSpeed: 6, markPosition: Point(east: 0, north: 1000)))
        let expected = 1000 / (6 * RaceEngine.metersPerSecondPerKnot * cos(.pi / 4))
        XCTAssertEqual(try XCTUnwrap(a.etaSeconds), expected, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(a.currentTackSeconds), expected / 2, accuracy: 0.001)
        XCTAssertEqual(a.vmg, 6 * cos(.pi / 4), accuracy: 0.001)
        XCTAssertEqual(a.vmc, a.vmg, accuracy: 0.001)
    }

    func testSteadyWindTackOrderHasIdenticalDistance() {
        let a = RaceEngine.analyze(RaceInput(markPosition: Point(east: -300, north: 1000)))
        func length(_ route: [Point]) -> Double {
            zip(route, route.dropFirst()).reduce(0) { $0 + hypot($1.1.east - $1.0.east, $1.1.north - $1.0.north) }
        }
        XCTAssertEqual(length(a.geometry.currentRoute), length(a.geometry.otherRoute), accuracy: 0.001)
        XCTAssertEqual(a.expectedGainSeconds, 0, accuracy: 0.001)
    }

    func testManeuverCostIncludesEveryAdditionalManeuver() {
        let a = RaceEngine.analyze(RaceInput(maneuverLossSeconds: 8, additionalManeuvers: 2))
        XCTAssertEqual(a.costSeconds, 16)
        XCTAssertEqual(a.recommendation, .hold)
    }

    func testSmallHeaderOnLongTackIsHeld() {
        let a = RaceEngine.analyze(DemoScenario.longTack.input)
        XCTAssertTrue(a.isLongTack)
        XCTAssertEqual(a.recommendation, .hold)
    }

    func testSustainedHeaderCanPayForTack() {
        let a = RaceEngine.analyze(DemoScenario.persistentHeader.input)
        XCTAssertGreaterThan(a.expectedGainSeconds, a.costSeconds)
        XCTAssertEqual(a.recommendation, .maneuver)
    }

    func testVeryBriefHeaderDoesNotPayForTwoTacks() {
        var input = DemoScenario.persistentHeader.input
        input.expectedShiftDuration = 5
        input.pressureAdvantage = 0
        let a = RaceEngine.analyze(input)
        XCTAssertEqual(a.recommendation, .hold)
        XCTAssertLessThan(a.expectedGainSeconds, a.costSeconds)
    }

    func testLaylineProximityTriggersPreparation() throws {
        let a = RaceEngine.analyze(DemoScenario.nearLayline.input)
        XCTAssertLessThan(try XCTUnwrap(a.laylineSeconds), 40)
        XCTAssertEqual(a.recommendation, .prepare)
    }

    func testOverstoodOutwardTackRequiresCorrection() {
        let a = RaceEngine.analyze(RaceInput(markPosition: Point(east: 1100, north: 1000)))
        XCTAssertTrue(a.isOverstood)
        XCTAssertEqual(a.recommendation, .maneuver)
        XCTAssertNil(a.currentTackSeconds)
        XCTAssertNotNil(a.etaSeconds)
    }

    func testOverstoodOnFinalTackReachesDirectlyWithoutExtraTack() {
        let a = RaceEngine.analyze(RaceInput(markPosition: Point(east: -1100, north: 1000), finalApproach: true))
        XCTAssertTrue(a.isOverstood)
        XCTAssertEqual(a.recommendation, .hold)
        XCTAssertNotNil(a.etaSeconds)
    }

    func testFinalApproachHeaderNeedsCorrection() {
        let a = RaceEngine.analyze(RaceInput(markPosition: Point(east: -800, north: 1000), finalApproach: true))
        XCTAssertEqual(a.recommendation, .prepare)
        XCTAssertEqual(a.title, "Hedef artık yatmıyor")
    }

    func testFinalApproachPresetHolds() {
        XCTAssertEqual(RaceEngine.analyze(DemoScenario.finalApproach.input).recommendation, .hold)
    }

    func testCurrentChangesCOGAndLaylineNotHeading() throws {
        let still = RaceEngine.analyze(RaceInput())
        let flowing = RaceEngine.analyze(RaceInput(currentEast: 1))
        XCTAssertEqual(still.heading, flowing.heading)
        XCTAssertNotEqual(still.cog, flowing.cog)
        XCTAssertNotEqual(try XCTUnwrap(still.currentTackSeconds), try XCTUnwrap(flowing.currentTackSeconds))
        let vector = RaceEngine.groundVector(heading: 0, speed: 6, currentEast: 1)
        XCTAssertEqual(vector.east, RaceEngine.metersPerSecondPerKnot, accuracy: 0.000001)
    }

    func testZeroSpeedProducesNoManeuverAdvice() {
        let a = RaceEngine.analyze(RaceInput(boatSpeed: 0))
        XCTAssertNil(a.etaSeconds)
        XCTAssertEqual(a.recommendation, .hold)
        XCTAssertEqual(a.title, "Hızı ve rotayı doğrula")
    }

    func testArrivalAndNonFiniteValuesRemainFinite() {
        let arrived = RaceEngine.analyze(RaceInput(markPosition: .zero))
        XCTAssertEqual(arrived.title, "Şamandıra bölgesi")
        let invalid = RaceEngine.analyze(RaceInput(windDirection: .nan, boatSpeed: .infinity))
        XCTAssertTrue(invalid.vmg.isFinite)
        XCTAssertTrue(invalid.expectedGainSeconds.isFinite)
        XCTAssertEqual(invalid.title, "Veriyi doğrula")
        XCTAssertEqual(invalid.recommendation, .hold)
    }

    func testHorizonCannotInventBenefitAfterFinish() {
        let input = RaceInput(windDirection: 350, boatSpeed: 6, markPosition: Point(east: 0, north: 40), expectedShiftDuration: 600, windUncertainty: 1)
        let a = RaceEngine.analyze(input)
        XCTAssertEqual(a.expectedGainSeconds, 0, accuracy: 0.001)
    }

    func testInputRoundTripsForJournal() throws {
        for scenario in DemoScenario.allCases {
            let data = try JSONEncoder().encode(scenario.input)
            XCTAssertEqual(try JSONDecoder().decode(RaceInput.self, from: data), scenario.input)
        }
    }

    func testPressureGainCountsDifferenceBetweenBothCandidateRoutes() {
        let input = RaceInput(boatSpeed: 6, markPosition: Point(east: 0, north: 400), maneuverLossSeconds: 8,
                              expectedShiftDuration: 600, windUncertainty: 0, pressureAdvantage: 50)
        let a = RaceEngine.analyze(input)
        XCTAssertEqual(a.expectedGainSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(a.recommendation, .hold)
    }
}
