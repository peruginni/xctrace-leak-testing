//
//  LeakingAppUITests.swift
//  LeakingAppUITests
//
//  Created for the sample project.
//

import XCTest

final class LeakingAppUITests: XCTestCase {

    private let elementWaitTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRepeatedFlowForInstrumentsAndXctrace() {
        let app = XCUIApplication()
        app.launch()

        // Give xctrace time to attach to the app launched by this test.
        Thread.sleep(forTimeInterval: 5)

        for iteration in 1...3 {
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
            XCTAssertTrue(
                closeButton.waitForNonExistence(timeout: elementWaitTimeout),
                "Leaking screen did not close on iteration \(iteration)"
            )
        }

        // Give the Leaks instrument time to inspect the final state.
        Thread.sleep(forTimeInterval: 15)
    }

    @MainActor
    func testRepeatedFlowWithXCTestMemoryDiagnostics() {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart]

        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            app.launch()

            startMeasuring()

            for iteration in 1...3 {
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
                XCTAssertTrue(
                    closeButton.waitForNonExistence(timeout: elementWaitTimeout),
                    "Leaking screen did not close on iteration \(iteration)"
                )
            }
        }

    }
}
