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

    func testContractsTabRenders() {
        let app = XCUIApplication()
        app.launch()
        // Tap the Contracts tab.
        app.tabBars.buttons["Contracts"].tap()
        // Either the empty state or the list shows up; the navigation title
        // is the cheapest invariant to assert on.
        XCTAssertTrue(app.navigationBars["Contracts"].waitForExistence(timeout: 5))
    }
}
