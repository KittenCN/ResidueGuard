import XCTest
import Darwin

@MainActor
final class HistoryReportUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { app.terminate() }
    private func launch(_ arguments: [String] = []) {
        app.launchArguments = arguments; app.launch()
        app.staticTexts["操作历史与恢复"].firstMatch.click()
    }
    private func text(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
    func testHistoryStartsWithExplicitImportAndNoAutomaticHistory() {
        launch()
        XCTAssertTrue(app.buttons["history.import"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(app.staticTexts["history.status"]).contains("尚未导入"))
        XCTAssertFalse(app.staticTexts["history.untrusted"].exists)
        app.buttons["history.import"].click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(text(app.staticTexts["history.status"]).contains("已取消选择"))
    }
    func testSyntheticHistoryShowsSeparateEffectsAndUnresolvedStepWithoutSensitiveData() {
        launch(["--ui-history-fixture"])
        XCTAssertTrue(app.staticTexts["history.untrusted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["history.synthetic"].exists)
        XCTAssertTrue(app.staticTexts["history.unresolved"].exists)
        XCTAssertTrue(text(app.staticTexts["history.backupWarning"]).contains("另行核验"))
        XCTAssertTrue(app.staticTexts["后台登记：等待系统刷新；权限：未执行"].exists)
        XCTAssertFalse(app.debugDescription.contains("/Synthetic/Private.app"))
        XCTAssertFalse(app.debugDescription.contains("private-test-fingerprint"))
        XCTAssertFalse(app.buttons["恢复"].exists)
        XCTAssertFalse(app.buttons["执行"].exists)
        app.buttons["history.clear"].click()
        XCTAssertFalse(app.staticTexts["history.untrusted"].exists)
    }
    func testCorruptHistoryIsAnErrorInsteadOfEmptyHistory() {
        launch(["--ui-history-fixture", "--ui-history-invalid"])
        let status = app.staticTexts["history.status"]
        expectation(for: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "不是空历史", "不是空历史"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["history.counts"].exists)
    }
    func testHistoryImportCancellationDiscardsLateResults() {
        launch(["--ui-history-fixture", "--ui-history-slow"])
        XCTAssertTrue(app.buttons["history.cancel"].waitForExistence(timeout: 3))
        app.buttons["history.cancel"].click()
        XCTAssertTrue(text(app.staticTexts["history.status"]).contains("已取消"))
        XCTAssertFalse(app.staticTexts["history.counts"].exists)
        XCTAssertTrue(app.buttons["history.import"].isEnabled)
    }
    func testExplicitPickerReadsOnlySelectedSyntheticFile() throws {
        guard ProcessInfo.processInfo.environment["RESIDUEGUARD_PICKER_UI_INTEGRATION"] == "1" else {
            throw XCTSkip("显式环境集成测试：需在 test runner 设置 RESIDUEGUARD_PICKER_UI_INTEGRATION=1，并提供可访问系统文件选择器的桌面会话；默认不声称 picker 端到端通过。")
        }
        // This temporary file contains synthetic data only; it is selected through
        // the actual OS picker, exercising the sandbox read grant and bounded reader.
        let temporary = FileManager.default.temporaryDirectory
        guard let canonical = realpath(temporary.path, nil) else { throw NSError(domain: "HistoryFixture", code: 1) }
        defer { free(canonical) }
        let url = URL(fileURLWithPath: String(cString: canonical), isDirectory: true).appendingPathComponent("ResidueHistoryUITest-" + UUID().uuidString + ".json")
        let fixture = #"{"contentSHA256":"047d829714578c425dd0e576121dc0c6c3a947b43bf8564c260525e36abe5908","payload":"eyJhdWRpdENsb3NlZCI6ZmFsc2UsImJhY2t1cHMiOltdLCJvYnNlcnZhdGlvbnMiOlt7ImVmZmVjdHMiOnsiZmlsZSI6Im5vdEF0dGVtcHRlZCIsInBlcm1pc3Npb24iOiJub3RBdHRlbXB0ZWQiLCJyZWdpc3RyYXRpb24iOiJwZW5kaW5nU3lzdGVtUmVmcmVzaCIsInJ1bnRpbWUiOiJzdWNjZWVkZWQifSwicHJlcGFyZWRBdCI6MTAwMCwicmVzdWx0QXQiOjEwMDEsInN0ZXBJRCI6ImZpeHR1cmUtc3RvcCJ9XSwicGxhbiI6eyJjcmVhdGVkQXQiOjEwMDAsImRpZ2VzdCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEiLCJleHBpcmVzQXQiOjExMjAsImlkIjoiMTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTExIiwicG9saWN5VmVyc2lvbiI6InAxLWRyeS1ydW4tMSIsInByb2ZpbGVJRCI6InN5bnRoZXRpYy10cmFuc2FjdGlvbi12MSIsInJlcXVpcmVkQ29uZmlybWF0aW9ucyI6MSwic2NvcGUiOiJjdXJyZW50VXNlciIsInN0ZXBzIjpbeyJhY3Rpb24iOiJib290b3V0RXhhY3RTZXJ2aWNlIiwiZGVwZW5kZW5jaWVzIjpbXSwiZmluZ2VycHJpbnQiOiJmaXh0dXJlLWZpbmdlcnByaW50IiwiaWQiOiJmaXh0dXJlLXN0b3AiLCJ0YXJnZXRJRCI6ImZpeHR1cmUtdGFyZ2V0In1dLCJ0YXJnZXRzIjpbeyJkaXNwbGF5TmFtZSI6IlN5bnRoZXRpY09ubHkiLCJmaW5nZXJwcmludCI6ImZpeHR1cmUtZmluZ2VycHJpbnQiLCJpZCI6ImZpeHR1cmUtdGFyZ2V0IiwiaXNQcm90ZWN0ZWRPck1hbmFnZWQiOmZhbHNlLCJwcmVzZW5jZSI6ImhpZ2hDb25maWRlbmNlT3JwaGFuIn1dfX0=","schemaVersion":1}"#
        try Data(fixture.utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        launch()
        app.buttons["history.import"].click()
        let picker = XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService")
        let choose = picker.buttons["只读导入"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), picker.debugDescription)
        picker.typeKey("g", modifierFlags: [.command, .shift])
        picker.typeText(url.path)
        picker.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(choose.waitForExistence(timeout: 3), app.debugDescription)
        choose.click()
        XCTAssertTrue(app.staticTexts["history.untrusted"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(text(app.staticTexts["history.counts"]).contains("目标 1 项"))
        XCTAssertFalse(app.debugDescription.contains("SyntheticOnly"))
        XCTAssertFalse(app.debugDescription.contains("fixture-fingerprint"))
    }

}
