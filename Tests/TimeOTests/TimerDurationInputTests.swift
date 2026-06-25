import XCTest
@testable import TimeO

final class TimerDurationInputTests: XCTestCase {
    func testPlainNumberIsParsedAsMinutes() {
        XCTAssertEqual(TimerDurationInput.parseSeconds("12"), 12 * 60)
    }

    func testMinutesAndSecondsFormat() {
        XCTAssertEqual(TimerDurationInput.parseSeconds("12:12"), 12 * 60 + 12)
        XCTAssertEqual(TimerDurationInput.parseSeconds("0:30"), 30)
        XCTAssertEqual(TimerDurationInput.parseSeconds("01:30:15"), 90 * 60 + 15)
    }

    func testInvalidFormatsAreRejected() {
        XCTAssertNil(TimerDurationInput.parseSeconds(""))
        XCTAssertNil(TimerDurationInput.parseSeconds("12:60"))
        XCTAssertNil(TimerDurationInput.parseSeconds("1:60:03"))
        XCTAssertNil(TimerDurationInput.parseSeconds("1:2:3:4"))
    }

    func testDurationIsLimitedToTwentyFourHours() {
        XCTAssertEqual(TimerDurationInput.parseSeconds("2000"), 24 * 60 * 60)
        XCTAssertEqual(TimerDurationInput.parseSeconds("1440:30"), 24 * 60 * 60)
    }

    func testEditableClockTextIsLimitedToHoursMinutesAndSeconds() {
        XCTAssertEqual(TimerDurationInput.limitedClockText("12:34:56"), "12:34:56")
        XCTAssertEqual(TimerDurationInput.limitedClockText("123:456:789"), "12:45:78")
        XCTAssertEqual(TimerDurationInput.limitedClockText("12:34:56:78"), "12:34:56")
        XCTAssertEqual(TimerDurationInput.limitedClockText("ab12::34"), "12::34")
    }

    func testRunningTimerRemainingTimeCanBeEdited() {
        let model = TimerModel()
        model.isRunning = true
        model.isPaused = true
        model.remainingSeconds = 9 * 60 + 36
        model.totalSeconds = 10 * 60

        model.updateRemaining(seconds: 19 * 60 + 36)

        XCTAssertEqual(model.remainingSeconds, 19 * 60 + 36)
        XCTAssertEqual(model.totalSeconds, 20 * 60)
    }

    func testEditedRemainingTimeCannotExceedTwentyFourHours() {
        let model = TimerModel()
        model.isRunning = true
        model.isPaused = true
        model.remainingSeconds = TimerDurationInput.maximumSeconds - 30
        model.totalSeconds = TimerDurationInput.maximumSeconds - 30

        model.updateRemaining(seconds: TimerDurationInput.maximumSeconds + 600)

        XCTAssertEqual(model.remainingSeconds, TimerDurationInput.maximumSeconds)
        XCTAssertEqual(model.totalSeconds, TimerDurationInput.maximumSeconds)
    }
}
