import XCTest

@MainActor
final class ResidueGuardUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }
    private func openDemoAgents() {
        app.buttons["demo.load"].click()
        XCTAssertTrue(app.buttons["demo.exit"].waitForExistence(timeout: 5))
        app.staticTexts["用户启动代理"].firstMatch.click()
    }
    func testDefaultIsUnscannedAndPermissionsAreUnavailable() {
        XCTAssertTrue(app.buttons["demo.load"].exists)
        XCTAssertFalse(app.checkBoxes["select.demo.orphan"].exists)
        app.staticTexts["辅助功能"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["permission.unavailable"].exists)
    }
    func testInspectionDoesNotSelectAndBlockedRowsCannotBeSelected() {
        openDemoAgents()
        XCTAssertFalse(app.buttons["review.open"].isEnabled)
        app.staticTexts["record.demo.orphan"].click()
        XCTAssertFalse(app.buttons["review.open"].isEnabled)
        XCTAssertFalse(app.checkBoxes["select.demo.offline"].isEnabled)
        XCTAssertFalse(app.checkBoxes["select.demo.unknown"].isEnabled)
        XCTAssertFalse(app.checkBoxes["select.demo.protected"].isEnabled)
    }
    func testFilteringPreservesSelectionAndPageChangeClearsIt() {
        openDemoAgents()
        app.checkBoxes["select.demo.orphan"].click()
        app.textFields["records.search"].click()
        app.textFields["records.search"].typeText("no-match")
        XCTAssertTrue(app.staticTexts["已选 1 项，其中 1 项当前隐藏"].exists)
        XCTAssertTrue(app.buttons["review.open"].isEnabled)
        app.staticTexts["后台登记"].firstMatch.click()
        app.staticTexts["用户启动代理"].firstMatch.click()
        XCTAssertFalse(app.buttons["review.open"].isEnabled)
    }
    func testOrphanDryRunRequiresOnlyOneConfirmationAfterImpactPreview() {
        openDemoAgents()
        app.checkBoxes["select.demo.orphan"].click()
        app.buttons["review.open"].click()
        app.buttons["review.approveImpact"].click()
        app.buttons["review.confirmFirst"].click()
        XCTAssertTrue(app.otherElements["review.complete"].waitForExistence(timeout: 3) || app.staticTexts["预演确认流程完成"].exists)
        XCTAssertFalse(app.buttons["review.confirmSecond"].exists)
    }
    func testInstalledSoftwareHasIndependentSecondConfirmation() {
        openDemoAgents()
        app.checkBoxes["select.demo.present"].click()
        app.buttons["review.open"].click()
        app.buttons["review.approveImpact"].click()
        app.buttons["review.confirmFirst"].doubleClick()
        XCTAssertTrue(app.buttons["review.confirmSecond"].exists)
        XCTAssertFalse(app.buttons["review.confirmSecond"].isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(app.buttons["review.confirmSecond"].isEnabled)
        app.textFields["review.riskPhrase"].click()
        app.textFields["review.riskPhrase"].typeText("清理仍安装软件的设置")
        app.buttons["review.confirmSecond"].click()
        XCTAssertTrue(app.staticTexts["预演确认流程完成"].waitForExistence(timeout: 3))
    }
    func testExpandedImpactShowsInstalledSoftwareBeforeConfirmation() {
        openDemoAgents()
        app.checkBoxes["select.demo.expanded"].click()
        app.buttons["review.open"].click()
        XCTAssertTrue(app.staticTexts["演示·今日笔记 · 已安装"].exists)
        app.buttons["review.approveImpact"].click()
        app.buttons["review.confirmFirst"].click()
        XCTAssertFalse(app.buttons["review.confirmSecond"].isEnabled)
        app.buttons["review.cancel"].click()
        XCTAssertTrue(app.buttons["review.open"].exists)
    }
}
