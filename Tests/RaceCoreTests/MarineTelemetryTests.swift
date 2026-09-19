import Foundation
import XCTest
@testable import RaceCore

final class MarineTelemetryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_789_376_400)

    private func sentence(_ payload: String) -> String {
        let checksum = payload.utf8.reduce(UInt8(0)) { $0 ^ $1 }
        return "$\(payload)*\(String(format: "%02X", checksum))"
    }

    private var rmc: String { "GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W" }

    func testKnownRMCChecksumAndCoordinateUnits() throws {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A\r\n", at: epoch))
        let position = try XCTUnwrap(telemetry.position)
        XCTAssertEqual(position.value.latitude, 48.1173, accuracy: 1e-8)
        XCTAssertEqual(position.value.longitude, 11.5166666667, accuracy: 1e-8)
        XCTAssertEqual(position.timestamp, epoch)
        XCTAssertEqual(telemetry.speedOverGround?.value, 22.4)
        XCTAssertEqual(telemetry.courseOverGround?.value, 84.4)
        XCTAssertNil(telemetry.trueHeading)
        XCTAssertNil(telemetry.speedThroughWater)
    }

    func testSouthWestHemisphereAndDifferentTalker() throws {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume(sentence("GNRMC,123519,A,3351.000,S,15112.000,W,6.4,350,140926,,,A"), at: epoch))
        let coordinate = try XCTUnwrap(telemetry.position?.value)
        XCTAssertEqual(coordinate.latitude, -33.85, accuracy: 1e-9)
        XCTAssertEqual(coordinate.longitude, -151.2, accuracy: 1e-9)
    }

    func testCorruptChecksumCannotInvalidateExistingFix() {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume(sentence(rmc), at: epoch))
        let initial = telemetry.position
        XCTAssertFalse(telemetry.consume("$GPRMC,123519,V,,,,,,,,,*00", at: epoch.addingTimeInterval(1)))
        XCTAssertEqual(telemetry.position, initial)
        XCTAssertEqual(telemetry.acceptedSentenceCount, 1)
        XCTAssertEqual(telemetry.rejectedSentenceCount, 1)
    }

    func testStrictFramingHeaderAndUnsupportedSentences() {
        var telemetry = MarineTelemetry()
        let invalid = [
            "HCHDT,45,T", "\n" + sentence("HCHDT,45,T"),
            sentence("HCHDT,45,T") + "junk", sentence("HCHDT,45,T") + "\n\n",
            sentence("HDT,45,T"), sentence("HCCHDT,45,T"), sentence("hchdt,45,T"),
            sentence("HCHDT,45,Ü"), sentence("HCHDT,45,*T"), sentence("HCHDT,45,$T"),
            sentence("GPGLL,4916.45,N,12311.12,W,225444,A")
        ]
        for value in invalid { XCTAssertFalse(telemetry.consume(value, at: epoch), value) }
        XCTAssertEqual(telemetry.rejectedSentenceCount, invalid.count)
        XCTAssertNil(telemetry.trueHeading)
    }

    func testInvalidLatitudeMinutesLongitudeAndHemisphereAreRejected() {
        let coordinates = [
            "4860.000,N,01131.000,E", "9000.001,N,01131.000,E", "9100.000,N,01131.000,E",
            "4807.000,N,18000.001,E", "4807.000,N,18100.000,E", "4807.000,N,01160.000,E",
            "4807.000,E,01131.000,E", "4807.000,N,01131.000,N", "487.000,N,1131.000,E"
        ]
        for coordinate in coordinates {
            var telemetry = MarineTelemetry()
            XCTAssertFalse(telemetry.consume(sentence("GPRMC,123519,A,\(coordinate),6,45,140926,,,A"), at: epoch), coordinate)
            XCTAssertNil(telemetry.position)
        }
    }

    func testStatusVoidImmediatelyClearsGPSButNotWind() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        telemetry.consume(sentence("WIMWD,300,T,295,M,12,N,6.1733,M"), at: epoch)
        XCTAssertFalse(telemetry.consume(sentence("GPRMC,123520,V,,,,,,,230394,,,N"), at: epoch.addingTimeInterval(1)))
        XCTAssertNil(telemetry.position)
        XCTAssertNil(telemetry.speedOverGround)
        XCTAssertNil(telemetry.courseOverGround)
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(1))?.value.direction, 300)
    }

    func testEstimatedInvalidManualAndSimulatedModesInvalidateLiveFix() {
        for mode in ["E", "N", "M", "S", "U", "X"] {
            var telemetry = MarineTelemetry()
            telemetry.consume(sentence(rmc), at: epoch)
            XCTAssertFalse(telemetry.consume(sentence(rmc + "," + mode), at: epoch.addingTimeInterval(1)), mode)
            XCTAssertNil(telemetry.position, mode)
            XCTAssertNil(telemetry.speedOverGround, mode)
        }
        for mode in ["A", "D", "F", "R", "P"] {
            var telemetry = MarineTelemetry()
            XCTAssertTrue(telemetry.consume(sentence(rmc + "," + mode), at: epoch), mode)
        }
    }

    func testGGAOnlyRefreshesPositionAndRejectsEstimatedQuality() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        let next = epoch.addingTimeInterval(10)
        XCTAssertTrue(telemetry.consume(sentence("GPGGA,123529,4807.040,N,01131.002,E,1,08,0.9,545.4,M,46.9,M,,"), at: next))
        XCTAssertEqual(telemetry.position?.timestamp, next)
        XCTAssertEqual(telemetry.speedOverGround?.timestamp, epoch)
        for quality in [0, 6, 7, 8] {
            XCTAssertFalse(telemetry.consume(sentence("GPGGA,123530,4807.040,N,01131.002,E,\(quality),08,0.9,545.4,M,46.9,M,,"), at: next))
            XCTAssertNil(telemetry.position)
        }
        XCTAssertEqual(telemetry.speedOverGround?.timestamp, epoch)
    }

    func testVTGUsesKnotsAndDoesNotCreateHeadingOrWaterSpeed() {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume(sentence("GPVTG,220.86,T,,M,2.550,N,4.724,K,A"), at: epoch))
        XCTAssertEqual(telemetry.speedOverGround?.value, 2.55)
        XCTAssertEqual(telemetry.courseOverGround?.value, 220.86)
        XCTAssertNil(telemetry.trueHeading)
        XCTAssertNil(telemetry.speedThroughWater)
        XCTAssertTrue(telemetry.consume(sentence("GPVTG,90,T,,M,,N,18.52,K,A"), at: epoch))
        XCTAssertEqual(telemetry.speedOverGround?.value, 10)
    }

    func testInvalidVTGModeClearsMotionButPreservesPosition() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        XCTAssertFalse(telemetry.consume(sentence("GPVTG,220.86,T,,M,2.550,N,4.724,K,E"), at: epoch))
        XCTAssertNil(telemetry.speedOverGround)
        XCTAssertNil(telemetry.courseOverGround)
        XCTAssertNotNil(telemetry.position)
    }

    func testVHWDistinguishesWaterSpeedAndTrueHeading() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        XCTAssertTrue(telemetry.consume(sentence("IIVHW,25,T,19,M,6.1,N,11.2972,K"), at: epoch))
        XCTAssertEqual(telemetry.trueHeading?.value, 25)
        XCTAssertEqual(telemetry.speedThroughWater?.value, 6.1)
        XCTAssertEqual(telemetry.speedOverGround?.value, 22.4)
        XCTAssertEqual(telemetry.courseOverGround?.value, 84.4)
    }

    func testWaterSpeedOnlyVHWDoesNotRejuvenateCompass() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch)
        XCTAssertTrue(telemetry.consume(sentence("IIVHW,,T,,M,7.1,N,13.1492,K"), at: epoch.addingTimeInterval(10)))
        XCTAssertEqual(telemetry.trueHeading?.timestamp, epoch)
        XCTAssertEqual(telemetry.trueHeading?.value, 350)
        XCTAssertEqual(telemetry.speedThroughWater?.timestamp, epoch.addingTimeInterval(10))
    }

    func testTrueHeadingRejectsMagneticReference() {
        var telemetry = MarineTelemetry()
        XCTAssertFalse(telemetry.consume(sentence("HCHDT,25,M"), at: epoch))
        XCTAssertNil(telemetry.trueHeading)
    }

    func testMWDTrueNorthAndMetersPerSecondFallback() throws {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume(sentence("WIMWD,302.4,T,289.6,M,10.5,N,5.4,M"), at: epoch))
        let first = try XCTUnwrap(telemetry.trueWind(at: epoch))
        XCTAssertEqual(first.value.direction, 302.4)
        XCTAssertEqual(first.value.speed, 10.5)
        XCTAssertEqual(first.value.source, "MWD")
        XCTAssertTrue(telemetry.consume(sentence("WIMWD,301,T,,M,,N,5.1444444444,M"), at: epoch))
        XCTAssertEqual(try XCTUnwrap(telemetry.trueWind(at: epoch)?.value.speed), 10, accuracy: 1e-8)
        XCTAssertFalse(telemetry.consume(sentence("WIMWD,301,M,,T,10,N,5.1,M"), at: epoch))
        XCTAssertFalse(telemetry.consume(sentence("WIMWD,301,T,,M,10,K,5.1,M"), at: epoch))
    }

    func testMWVTrueNeedsHeadingNeverCOG() throws {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        XCTAssertTrue(telemetry.consume(sentence("WIMWV,25,T,12,N,A"), at: epoch))
        XCTAssertNil(telemetry.trueWind(at: epoch))
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch)
        let wind = try XCTUnwrap(telemetry.trueWind(at: epoch))
        XCTAssertEqual(wind.value.direction, 15)
        XCTAssertEqual(wind.value.speed, 12)
        XCTAssertEqual(wind.value.source, "MWV(T) + HDT")
    }

    func testApparentWindIsNeverSilentlyPromotedToTrueWind() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch)
        telemetry.consume(sentence(rmc), at: epoch)
        telemetry.consume(sentence("IIVHW,350,T,344,M,6.1,N,11.2972,K"), at: epoch)
        XCTAssertTrue(telemetry.consume(sentence("WIMWV,25,R,12,N,A"), at: epoch))
        XCTAssertEqual(telemetry.apparentWind?.value.angle, 25)
        XCTAssertEqual(telemetry.apparentWind?.value.speed, 12)
        XCTAssertNil(telemetry.trueWind(at: epoch))
    }

    func testMWVUnitsAndUnsupportedUnit() throws {
        var telemetry = MarineTelemetry()
        XCTAssertTrue(telemetry.consume(sentence("WIMWV,25,R,18.52,K,A"), at: epoch))
        XCTAssertEqual(telemetry.apparentWind?.value.speed, 10)
        XCTAssertTrue(telemetry.consume(sentence("WIMWV,25,R,5.1444444444,M,A"), at: epoch))
        XCTAssertEqual(try XCTUnwrap(telemetry.apparentWind?.value.speed), 10, accuracy: 1e-8)
        XCTAssertFalse(telemetry.consume(sentence("WIMWV,25,R,10,X,A"), at: epoch))
    }

    func testDerivedWindRetainsOldestComponentAge() throws {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("WIMWV,25,T,12,N,A"), at: epoch)
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch.addingTimeInterval(5))
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(5))?.timestamp, epoch)
        telemetry.consume(sentence("HCHDT,355,T"), at: epoch.addingTimeInterval(14))
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(14))?.timestamp, epoch)
        XCTAssertNil(telemetry.trueWind(at: epoch.addingTimeInterval(16)))
        telemetry.consume(sentence("WIMWV,25,T,12,N,A"), at: epoch.addingTimeInterval(18))
        let derived = try XCTUnwrap(telemetry.trueWind(at: epoch.addingTimeInterval(18)))
        XCTAssertEqual(derived.timestamp, epoch.addingTimeInterval(14))
        XCTAssertEqual(derived.value.direction, 20)
        XCTAssertNil(telemetry.trueWind(at: epoch.addingTimeInterval(30)))
    }

    func testFreshGPSCannotRefreshOldWind() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("WIMWD,300,T,295,M,12,N,6.1733,M"), at: epoch)
        telemetry.consume(sentence(rmc), at: epoch.addingTimeInterval(14))
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(14))?.timestamp, epoch)
        telemetry.consume(sentence(rmc), at: epoch.addingTimeInterval(16))
        XCTAssertNil(telemetry.trueWind(at: epoch.addingTimeInterval(16)))
        XCTAssertTrue(telemetry.position?.isFresh(at: epoch.addingTimeInterval(16)) ?? false)
    }

    func testDirectWindPriorityThenFreshDerivedFallback() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("WIMWD,300,T,295,M,12,N,6.1733,M"), at: epoch)
        telemetry.consume(sentence("WIMWV,25,T,14,N,A"), at: epoch.addingTimeInterval(10))
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch.addingTimeInterval(10))
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(12))?.value.source, "MWD")
        XCTAssertEqual(telemetry.trueWind(at: epoch.addingTimeInterval(16))?.value.source, "MWV(T) + HDT")
    }

    func testInvalidWindStatusImmediatelyClearsOnlyAssociatedReference() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence("HCHDT,350,T"), at: epoch)
        telemetry.consume(sentence("WIMWV,25,T,12,N,A"), at: epoch)
        telemetry.consume(sentence("WIMWV,30,R,16,N,A"), at: epoch)
        XCTAssertFalse(telemetry.consume(sentence("WIMWV,,T,,N,V"), at: epoch))
        XCTAssertNil(telemetry.trueWind(at: epoch))
        XCTAssertNotNil(telemetry.apparentWind)
        XCTAssertFalse(telemetry.consume(sentence("WIMWV,,R,,N,V"), at: epoch))
        XCTAssertNil(telemetry.apparentWind)
    }

    func testNonFiniteOutOfRangeAndMalformedNumbersAreRejected() {
        for number in ["NaN", "inf", "-1", "360", "1e2", " 45", "+45", "45.", ".5", "4.5.6"] {
            var telemetry = MarineTelemetry()
            XCTAssertFalse(telemetry.consume(sentence("HCHDT,\(number),T"), at: epoch), number)
            XCTAssertNil(telemetry.trueHeading)
        }
        var telemetry = MarineTelemetry()
        XCTAssertFalse(telemetry.consume(sentence("WIMWV,25,R,201,N,A"), at: epoch))
        XCTAssertFalse(telemetry.consume(sentence("GPVTG,90,T,,M,101,N,187.052,K,A"), at: epoch))
        XCTAssertFalse(telemetry.consume(sentence("HCHDT,25,T"), at: Date(timeIntervalSinceReferenceDate: .infinity)))
        XCTAssertFalse(telemetry.consume(sentence("IIVHW,25,T,NaN,M,6.1,N,11.2972,K"), at: epoch))
        XCTAssertFalse(telemetry.consume(sentence("WIMWD,301,T,inf,M,10,N,5.1,M"), at: epoch))
        XCTAssertFalse(telemetry.consume(sentence("GPVTG,90,T,45,T,10,N,18.52,K,A"), at: epoch))
    }

    func testChecksumMustContainExactlyTwoHexDigits() {
        // HDT 10 has checksum 06; '+6' must not be parsed as hexadecimal 6.
        var telemetry = MarineTelemetry()
        let payload = "HCHDT,10,T"
        let valid = sentence(payload)
        XCTAssertEqual(String(valid.suffix(2)), "06")
        XCTAssertTrue(telemetry.consume(valid, at: epoch))
        let malformed = String(valid.dropLast(2)) + "+" + String(valid.suffix(1))
        XCTAssertFalse(telemetry.consume(malformed, at: epoch))
        XCTAssertFalse(telemetry.consume(valid + "0", at: epoch))
    }

    func testDelayedObservationCannotUndoNewerInvalidation() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        telemetry.consume(sentence("GPRMC,123520,V,,,,,,,230394,,,N"), at: epoch.addingTimeInterval(10))
        XCTAssertTrue(telemetry.consume(sentence(rmc), at: epoch.addingTimeInterval(5)))
        XCTAssertNil(telemetry.position)
        XCTAssertNil(telemetry.speedOverGround)
        telemetry.consume(sentence(rmc), at: epoch.addingTimeInterval(11))
        XCTAssertNotNil(telemetry.position)
    }

    func testSampleFreshnessBoundaryFutureAndInvalidMaximumAge() throws {
        let sample = TelemetrySample(value: 12.5, timestamp: epoch)
        XCTAssertTrue(sample.isFresh(at: epoch))
        XCTAssertTrue(sample.isFresh(at: epoch.addingTimeInterval(15)))
        XCTAssertFalse(sample.isFresh(at: epoch.addingTimeInterval(15.001)))
        XCTAssertFalse(sample.isFresh(at: epoch.addingTimeInterval(-1)))
        XCTAssertFalse(sample.isFresh(at: epoch, maxAge: -1))
        XCTAssertFalse(sample.isFresh(at: epoch, maxAge: .infinity))
        XCTAssertEqual(try JSONDecoder().decode(TelemetrySample<Double>.self, from: JSONEncoder().encode(sample)), sample)
    }

    func testLocalProjectionOriginDirectionsAndAntimeridian() throws {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(origin.projected(relativeTo: origin), .zero)
        let north = try XCTUnwrap(GeoCoordinate(latitude: 0.001, longitude: 0).projected(relativeTo: origin))
        XCTAssertEqual(north.north, 111.1950802, accuracy: 1e-5)
        XCTAssertEqual(north.east, 0)
        let across = try XCTUnwrap(GeoCoordinate(latitude: 0, longitude: -179.999).projected(relativeTo: GeoCoordinate(latitude: 0, longitude: 179.999)))
        XCTAssertEqual(across.east, 222.3901604, accuracy: 1e-5)
        XCTAssertEqual(across.north, 0)
        let reverse = try XCTUnwrap(GeoCoordinate(latitude: 0, longitude: 179.999).projected(relativeTo: GeoCoordinate(latitude: 0, longitude: -179.999)))
        XCTAssertEqual(reverse.east, -across.east, accuracy: 1e-5)
    }

    func testGeographicLimitsRejectPolesLongDistancesAndInvalidCoordinates() {
        let origin = GeoCoordinate(latitude: 40, longitude: 29)
        XCTAssertNil(GeoCoordinate(latitude: 41, longitude: 29).projected(relativeTo: origin))
        XCTAssertNil(GeoCoordinate(latitude: 85, longitude: 0).projected(relativeTo: GeoCoordinate(latitude: 85, longitude: 0)))
        for coordinate in [GeoCoordinate(latitude: 91, longitude: 0), GeoCoordinate(latitude: 0, longitude: 181),
                           GeoCoordinate(latitude: .nan, longitude: 0), GeoCoordinate(latitude: 0, longitude: .infinity)] {
            XCTAssertFalse(coordinate.isValid)
            XCTAssertNil(coordinate.projected(relativeTo: origin))
            XCTAssertNil(origin.projected(relativeTo: coordinate))
        }
        XCTAssertTrue(GeoCoordinate(latitude: 90, longitude: 180).isValid)
    }

    func testResetClearsSamplesAndCounters() {
        var telemetry = MarineTelemetry()
        telemetry.consume(sentence(rmc), at: epoch)
        telemetry.consume("broken", at: epoch)
        telemetry.reset()
        XCTAssertNil(telemetry.position)
        XCTAssertNil(telemetry.speedOverGround)
        XCTAssertNil(telemetry.trueWind(at: epoch))
        XCTAssertEqual(telemetry.acceptedSentenceCount, 0)
        XCTAssertEqual(telemetry.rejectedSentenceCount, 0)
    }
}
