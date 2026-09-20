import XCTest

@MainActor
final class RetentionRuleUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    private func waitEnabled(_ element: XCUIElement, _ enabled: Bool) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == %@", NSNumber(value: enabled)), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
    private func navigate(to page: String) {
        let sidebar = app.descendants(matching: .any)["workspace.sidebar"].firstMatch
        let target = app.staticTexts["page.\(page)"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        // SwiftUI may restore sidebar scroll position across processes. Existence
        // alone does not make an offscreen, zero-frame row safe to click.
        let delta: CGFloat = page == "忽略规则" ? -600 : 600
        for _ in 0..<8 {
            if target.isHittable { break }
            sidebar.scroll(byDeltaX: 0, deltaY: delta)
        }
        XCTAssertTrue(target.isHittable, "Sidebar target remains offscreen: \(page)")
        target.click()
    }
    private func assertNothingSelected() {
        // SwiftUI CheckBox.value is not consistently published as a String on
        // macOS. Assert the actual model-backed selection count and action gate.
        XCTAssertTrue(app.staticTexts["已选 0 项，其中 0 项当前隐藏"].waitForExistence(timeout: 5))
        waitEnabled(app.buttons["review.open"], false)
    }
    private func openDemoAgents() {
        XCTAssertTrue(app.buttons["demo.load"].waitForExistence(timeout: 5))
        app.buttons["demo.load"].click()
        XCTAssertTrue(app.buttons["demo.exit"].waitForExistence(timeout: 5))
        navigate(to: "用户启动代理")
        XCTAssertTrue(app.staticTexts["record.demo.orphan"].waitForExistence(timeout: 5))
    }
    private func retainDemoOrphan() {
        // This source has synthetic.retention identity; the app stores it in memory only.
        app.staticTexts["record.demo.orphan"].click()
        let add = app.buttons["retention.add"]
        waitEnabled(add, true)
        add.click()
        waitEnabled(app.checkBoxes["select.demo.orphan"], false)
    }
    func testDemoRetentionProtectsWithoutHidingAndRemovalDoesNotSelect() {
        openDemoAgents()
        let checkbox = app.checkBoxes["select.demo.orphan"]
        waitEnabled(checkbox, true)
        assertNothingSelected()
        checkbox.click()
        waitEnabled(app.buttons["review.open"], true)
        retainDemoOrphan()

        // Adding protection invalidates prior selection, but keeps the observed record visible.
        XCTAssertTrue(app.staticTexts["record.demo.orphan"].exists)
        assertNothingSelected()
        waitEnabled(app.buttons["review.open"], false)
        navigate(to: "忽略规则")
        let state = app.staticTexts["retention.rule.state.session.demo.orphan"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        let text = (state.value as? String) ?? state.label
        XCTAssertTrue(text.contains("当前匹配"))
        XCTAssertTrue(app.staticTexts["本次演示规则 · 不持久保存"].exists)
        // Exact session-only ID: never click or remove a user's persisted local rule.
        let remove = app.buttons["retention.remove.session.demo.orphan"]
        waitEnabled(remove, true)
        remove.click()
        XCTAssertTrue(app.staticTexts["retention.session.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(remove.exists)

        navigate(to: "用户启动代理")
        XCTAssertTrue(app.staticTexts["record.demo.orphan"].waitForExistence(timeout: 5))
        waitEnabled(checkbox, true)
        assertNothingSelected()
        waitEnabled(app.buttons["review.open"], false)
        checkbox.click()
        waitEnabled(app.buttons["review.open"], true)
    }
    func testDemoRetentionDoesNotSurviveProcessRelaunch() {
        openDemoAgents()
        retainDemoOrphan()
        navigate(to: "忽略规则")
        XCTAssertTrue(app.buttons["retention.remove.session.demo.orphan"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        navigate(to: "忽略规则")
        XCTAssertTrue(app.staticTexts["retention.session.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["retention.remove.session.demo.orphan"].exists)
        openDemoAgents()
        let checkbox = app.checkBoxes["select.demo.orphan"]
        waitEnabled(checkbox, true)
        assertNothingSelected()
        waitEnabled(app.buttons["review.open"], false)
    }
}
