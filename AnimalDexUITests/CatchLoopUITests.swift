import XCTest

/// Drives the full game loop end to end in the Simulator and attaches a
/// screenshot at each stage.
///
/// This exists because the loop cannot otherwise be exercised without a physical
/// device: the Simulator has no camera (hence `SampleFrameSource`) and Vision's
/// classifier does not run there (hence `ScriptedRecognizer`). With both stubs in
/// place, everything downstream — gate, shutter, catch sequence, registration,
/// dex — is real code under test.
final class CatchLoopUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCatchRegistersNewEntryInDex() {
        // Boot sequence runs ~2.2s before the shell appears.
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15), "scanner never appeared")
        snapshot("01-scanner")

        // The gate should lock onto the first bundled sample.
        let banner = app.staticTexts["detectionBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "detection banner never fired")
        snapshot("02-detected")

        shutter.tap()

        let headline = app.staticTexts["registrationHeadline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 20), "catch sequence never registered")
        snapshot("03-registered")

        let cont = app.buttons["continueButton"]
        XCTAssertTrue(cont.waitForExistence(timeout: 15))
        cont.tap()

        // The entry must now be in the dex.
        app.buttons["tab.entries"].tap()
        snapshot("04-dex")

        // Completion counter should no longer read 000.
        XCTAssertFalse(
            app.staticTexts["000 / 137"].exists,
            "dex still shows zero registered species after a catch"
        )
    }

    func testDuplicateCatchTakesShortPath() {
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["detectionBanner"].waitForExistence(timeout: 10))

        for pass in 1...2 {
            shutter.tap()
            let headline = app.staticTexts["registrationHeadline"]
            XCTAssertTrue(headline.waitForExistence(timeout: 20), "pass \(pass) never registered")
            if pass == 2 {
                snapshot("05-duplicate")
                XCTAssertEqual(
                    headline.label, "ALREADY REGISTERED",
                    "second catch of the same species should take the duplicate path"
                )
            }
            app.buttons["continueButton"].tap()
            _ = shutter.waitForExistence(timeout: 10)
        }
    }

    func testAllTabsRender() {
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 15))
        for tab in ["entries", "map", "profile"] {
            app.buttons["tab.\(tab)"].tap()
            snapshot("tab-\(tab)")
        }
    }
}
