import Foundation
import XCTest

@MainActor
final class MemoryLeakUITestWorkflow {
    private let targetAppBundleIdentifier = "com.example.MemoryLeakingApp-iOS"
    // Give xctrace time to attach to the app launched by the UI test.
    private let attachDelay: TimeInterval = 5
    // Give xctrace extra time to inspect the app for leaks after the flow finishes.
    private let postFlowDelay: TimeInterval = 5
    private let flowIterations = 5

    func runRepeatedFlow(
        _ performIteration: (XCUIApplication, Int) throws -> Void
    ) rethrows {
        let app = XCUIApplication(bundleIdentifier: targetAppBundleIdentifier)
        app.launch()
        defer { app.terminate() }

        Thread.sleep(forTimeInterval: attachDelay)

        for iteration in 1...flowIterations {
            try performIteration(app, iteration)
        }

        Thread.sleep(forTimeInterval: postFlowDelay)
    }
}
