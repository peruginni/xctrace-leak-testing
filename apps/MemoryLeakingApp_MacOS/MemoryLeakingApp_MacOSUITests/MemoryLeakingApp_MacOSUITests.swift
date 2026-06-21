import XCTest

final class MemoryLeakingApp_MacOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenAndCloseLeakingScreenRepeatedly() {
        let elementWaitTimeout: TimeInterval = 10

        MemoryLeakUITestWorkflow().runRepeatedFlow { app, iteration in
            let openButton = app.buttons["open-leaking-screen"]
            XCTAssertTrue(
                openButton.waitForExistence(timeout: elementWaitTimeout),
                "Open button did not appear on iteration \(iteration)"
            )

            openButton.tap()

            let closeButton = app.buttons["close-leaking-screen"]
            XCTAssertTrue(
                closeButton.waitForExistence(timeout: elementWaitTimeout),
                "Close button did not appear on iteration \(iteration)"
            )

            closeButton.tap()
        }
    }
}
