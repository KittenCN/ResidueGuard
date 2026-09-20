import XCTest

@MainActor
final class MinimumWindowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    func testMinimumWindowDoubleConfirmationRemainsReachableAndEscapeCancels() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        func shrink() throws {
            let frame = window.frame
            guard !frame.isEmpty, [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else {
                XCTFail("Cannot resize without a finite observed window")
                throw NSError(domain: "MinimumWindowGeometry", code: 1)
            }
            let corner = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.width - 2, dy: frame.height - 2))
            let target = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 250, dy: 200))
            corner.click(forDuration: 0.2, thenDragTo: target)
        }
        let original = window.frame
        try shrink()
        let minimum = window.frame
        try shrink()
        let second = window.frame
        XCTAssertLessThanOrEqual(minimum.width, original.width + 2)
        XCTAssertEqual(second.width, minimum.width, accuracy: 2)
        XCTAssertEqual(second.height, minimum.height, accuracy: 2)
        XCTAssertGreaterThanOrEqual(minimum.width, 980)
        XCTAssertGreaterThanOrEqual(minimum.height, 640)
        XCTAssertLessThanOrEqual(minimum.width, 982)
        // Allow window chrome above the specified 640-point content minimum.
        XCTAssertLessThanOrEqual(minimum.height, 720)
        print("Minimum-window observation: \(minimum.width)x\(minimum.height) points")

        app.buttons["demo.load"].click()
        XCTAssertTrue(app.buttons["demo.exit"].waitForExistence(timeout: 5))
        let agents = app.staticTexts["page.用户启动代理"]
        XCTAssertTrue(agents.isHittable)
        agents.click()
        let selected = app.checkBoxes["select.demo.present"]
        XCTAssertTrue(selected.isHittable)
        selected.click()
        let open = app.buttons["review.open"]
        XCTAssertTrue(open.isEnabled && open.isHittable)
        open.click()
        let approve = app.buttons["review.approveImpact"]
        XCTAssertTrue(approve.waitForExistence(timeout: 3))
        XCTAssertTrue(approve.isHittable)
        approve.click()
        let first = app.buttons["review.confirmFirst"]
        XCTAssertTrue(first.isEnabled && first.isHittable)
        first.click()
        let secondConfirmation = app.buttons["review.confirmSecond"]
        XCTAssertTrue(secondConfirmation.waitForExistence(timeout: 3))
        XCTAssertFalse(secondConfirmation.isEnabled)
        XCTAssertTrue(app.buttons["review.cancel"].isHittable)
        let phrase = app.textFields["review.riskPhrase"]
        XCTAssertTrue(phrase.isHittable)
        phrase.click(); phrase.typeText("清理仍安装软件的设置")
        XCTAssertTrue(secondConfirmation.isEnabled && secondConfirmation.isHittable)
        // Escape cancels even after the second confirmation becomes actionable.
        phrase.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(secondConfirmation.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["预演确认流程完成"].exists)
        XCTAssertTrue(open.isEnabled && open.isHittable)
        open.click()
        XCTAssertTrue(approve.waitForExistence(timeout: 3))
        XCTAssertTrue(approve.isHittable)
        XCTAssertFalse(secondConfirmation.exists)
        app.buttons["review.cancel"].click()
    }
}
