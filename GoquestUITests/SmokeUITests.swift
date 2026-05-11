import XCTest

final class SmokeUITests: XCTestCase {
    func testLaunchShowsLoginOrInbox() {
        let app = XCUIApplication()
        app.launch()
        // App should reach a sign-in CTA (logged-out) or the Inbox tab (logged-in).
        let cta = app.buttons["Sign in with ZITADEL"]
        let inboxTab = app.tabBars.buttons["Inbox"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5) || inboxTab.waitForExistence(timeout: 5))
    }
}
