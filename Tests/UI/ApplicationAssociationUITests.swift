import XCTest

@MainActor
final class ApplicationAssociationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-synthetic-scan", "--ui-ownership-fixture"]
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate() }

    private func openAssociations() {
        let sidebar = app.descendants(matching: .any)["workspace.sidebar"].firstMatch
        let target = app.staticTexts["page.应用关联"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if target.isHittable { break }
            sidebar.scroll(byDeltaX: 0, deltaY: 600)
        }
        XCTAssertTrue(target.isHittable)
        target.click()
    }
    private func text(_ element: XCUIElement) -> String { (element.value as? String) ?? element.label }
    private func scanFixture() {
        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 5))
        app.buttons["scan.start"].click()
        XCTAssertTrue(app.staticTexts["ownership.counts"].waitForExistence(timeout: 5))
    }
    func testDuplicateInstancesRemainCandidatesAndFilterIsExplicit() {
        openAssociations()
        XCTAssertTrue(app.staticTexts["ownership.notScanned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ownership.counts"].exists)
        scanFixture()
        let counts = text(app.staticTexts["ownership.counts"])
        XCTAssertTrue(counts.contains("2 个实例节点"))
        XCTAssertTrue(counts.contains("2 条候选关联"))
        XCTAssertTrue(text(app.staticTexts["ownership.coverage"]).contains("关联覆盖有限"))
        XCTAssertEqual(app.staticTexts.matching(identifier: "ownership.node.label").count, 2)
        XCTAssertFalse(app.buttons["review.open"].exists)
        XCTAssertFalse(app.buttons["review.confirmFirst"].exists)
        XCTAssertFalse(app.buttons["review.confirmSecond"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "执行")).count, 0)
        XCTAssertEqual(app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select.")).count, 0)
        let search = app.textFields["ownership.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click(); search.typeText("no-such-synthetic-instance")
        XCTAssertTrue(app.staticTexts["ownership.noMatches"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "ownership.node.label").count, 0)
        XCTAssertTrue(app.staticTexts["ownership.counts"].exists)
    }
    func testSwitchingToDemoClearsPriorOwnershipGraph() {
        openAssociations()
        scanFixture()
        let demo = app.buttons["demo.load"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: demo)
        waitForExpectations(timeout: 5)
        demo.click()
        XCTAssertTrue(app.buttons["demo.exit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ownership.notScanned"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app.staticTexts["ownership.notScanned"]).contains("合成演示未提供"))
        XCTAssertFalse(app.staticTexts["ownership.counts"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "ownership.node.label").count, 0)
    }
}
