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
        // Observe each state transition instead of assuming the text input's
        // event dispatch also completed SwiftUI's filtering and AX publication.
        let review = app.buttons["review.open"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: review)
        waitForExpectations(timeout: 3)
        let search = app.textFields["records.search"]
        search.click()
        search.typeText("no-match")
        expectation(for: NSPredicate(format: "value == %@", "no-match"), evaluatedWith: search)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["已选 1 项，其中 1 项当前隐藏"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.checkBoxes["select.demo.orphan"].exists)
        XCTAssertTrue(review.isEnabled)
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

    private func relaunchSyntheticScan(slow: Bool = false) {
        app.terminate()
        app.launchArguments = ["--ui-synthetic-scan"] + (slow ? ["--ui-slow-scan"] : [])
        app.launch()
    }
    func testSyntheticScanCoverageAndReadOnlyRows() {
        relaunchSyntheticScan()
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.otherElements["coverage.synthetic.scan"].waitForExistence(timeout: 5) || app.staticTexts["synthetic.scan · 部分"].exists)
        XCTAssertTrue(app.staticTexts["测试注入 · 合成扫描结果，非本机数据"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scan.incompleteCoverage"].firstMatch.exists)
        app.staticTexts["用户启动代理"].firstMatch.click()
        let checkbox = app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select.")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 3))
        XCTAssertFalse(checkbox.isEnabled)
        XCTAssertFalse(app.buttons["review.open"].isEnabled)
    }
    func testScanModeInvalidatesDemoSelection() {
        relaunchSyntheticScan()
        openDemoAgents()
        app.checkBoxes["select.demo.orphan"].click()
        XCTAssertTrue(app.buttons["review.open"].isEnabled)
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.staticTexts["已选 0 项，其中 0 项当前隐藏"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.open"].isEnabled)
        XCTAssertFalse(app.checkBoxes["select.demo.orphan"].exists)
    }
    func testCancelInjectedScanNeverRunsHostProvider() {
        relaunchSyntheticScan(slow: true)
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["demo.load"].isEnabled)
        XCTAssertFalse(app.buttons["scan.start"].isEnabled)
        app.buttons["scan.cancel"].click()
        XCTAssertTrue(app.staticTexts["synthetic.scan · 取消"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scan.start"].isEnabled)
    }

    func testPermissionRelationshipGuidanceDoesNotOfferReset() {
        app.staticTexts["自动化"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["permission.unavailable"].exists)
        XCTAssertTrue(app.staticTexts["自动化保留调用者 → 被控制者关系。若底层能力影响调用者的全部关系，必须完整展开影响集合并重新批准；影响不明时阻断。"].exists)
        XCTAssertTrue(app.staticTexts["完整清单：不可读取；精确重置：禁用；后置验证：未验证。"].exists)
        XCTAssertFalse(app.buttons["重置"].exists)
    }

    func testRedactedReportMarksSyntheticScanAndOmitsIdentity() {
        app.terminate()
        app.launchArguments = ["--ui-synthetic-scan"]
        app.launch()
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.buttons["report.preview"].waitForExistence(timeout: 5))
        let preview = app.buttons["report.preview"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: preview)
        waitForExpectations(timeout: 5)
        preview.click()
        XCTAssertTrue(app.staticTexts["合成测试数据，非本机观察"].waitForExistence(timeout: 3))
        let content = (app.staticTexts["report.content"].value as? String ?? "")
        XCTAssertTrue(content.contains("synthetic"))
        XCTAssertFalse(content.contains("/Synthetic/"))
        XCTAssertFalse(content.contains("fixture-readonly"))
    }
}
