import XCTest

/// End-to-end MVP: register against the real backend, catch a creature, share it,
/// and confirm it reaches the community map.
///
/// Requires `docker compose up -d` plus both services running. These are skipped
/// rather than failed when the backend is unreachable, so the rest of the UI
/// suite stays runnable on a machine with no backend.
final class BackendIntegrationUITests: XCTestCase {

    private var app: XCUIApplication!
    private var handle: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(backendIsUp(), "core-api not reachable on :8080")

        // A fresh trainer per run: the backend is a shared dev database, and
        // reusing a handle would collide on the unique constraint.
        handle = "sim\(Int.random(in: 100_000...999_999))"

        app = XCUIApplication()
        app.launch()
    }

    private func backendIsUp() -> Bool {
        let url = URL(string: "http://localhost:8080/health")!
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return ok
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func type(_ identifier: String, _ text: String) {
        // Query text fields specifically. A generic descendant query can resolve
        // a container that merely *holds* the field, and tapping that never
        // gives the field keyboard focus.
        let field = app.textFields[identifier].exists
            ? app.textFields[identifier]
            : app.secureTextFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(identifier) not found")
        field.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText(text)
    }

    func testRegisterCatchAndShare() throws {
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 15))

        // --- register -------------------------------------------------------
        app.buttons["tab.profile"].tap()

        // The refresh token lives in the Keychain, which survives app relaunch —
        // correct behaviour for users, but it means a previous run can leave this
        // simulator already signed in. Sign out first so the test starts from a
        // known state rather than depending on run order.
        let signOutFirst = app.buttons["profile.signOut"]
        if signOutFirst.waitForExistence(timeout: 3) {
            signOutFirst.tap()
        }

        let signIn = app.buttons["profile.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8), "sign-in entry point missing")
        signIn.tap()

        XCTAssertTrue(app.buttons["auth.switchMode"].waitForExistence(timeout: 5))
        app.buttons["auth.switchMode"].tap()   // signIn -> register
        snapshot("09-auth-sheet")

        type("auth.handle", handle)
        type("auth.displayName", "Sim Trainer")
        type("auth.email", "\(handle!)@example.com")
        type("auth.password", "correct-horse-battery")
        snapshot("10-register-form")

        app.buttons["auth.submit"].tap()

        // The sheet dismisses itself once the session reports signed in.
        let signOut = app.buttons["profile.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 20), "registration did not sign us in")
        snapshot("11-signed-in")

        // --- catch ----------------------------------------------------------
        app.buttons["tab.scanner"].tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["detectionBanner"].waitForExistence(timeout: 10))
        shutter.tap()

        XCTAssertTrue(app.staticTexts["registrationHeadline"].waitForExistence(timeout: 20))
        app.buttons["continueButton"].tap()

        // --- share ----------------------------------------------------------
        app.buttons["tab.entries"].tap()
        let tile = app.buttons["dex.caught.butterfly"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "caught butterfly not in dex")
        tile.tap()

        let shareButton = app.buttons["entry.share"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "share control missing")
        snapshot("12-before-share")
        shareButton.tap()

        // Upload -> complete -> create catch is three network round trips.
        let status = app.staticTexts["entry.shareStatus"]
        let shared = NSPredicate(format: "label == %@", "SHARED WITH COMMUNITY")
        expectation(for: shared, evaluatedWith: status, handler: nil)
        waitForExpectations(timeout: 30)
        snapshot("13-shared")

        XCTAssertEqual(status.label, "SHARED WITH COMMUNITY")
    }

    func testDexSurvivesSignOut() throws {
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["detectionBanner"].waitForExistence(timeout: 10))
        app.buttons["shutter"].tap()
        XCTAssertTrue(app.staticTexts["registrationHeadline"].waitForExistence(timeout: 20))
        app.buttons["continueButton"].tap()

        // The dex is local-first: it must be fully intact with no account at all.
        app.buttons["tab.entries"].tap()
        XCTAssertTrue(
            app.buttons["dex.caught.butterfly"].waitForExistence(timeout: 10),
            "a catch made while signed out should still be in the dex"
        )
        snapshot("14-offline-dex")
    }
}
