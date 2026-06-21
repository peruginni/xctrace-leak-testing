import Foundation
import SwiftUI

struct ContentView: View {
    @State private var leakingScreenWiring: MacLeakingScreenWiring?

    var body: some View {
        VStack(spacing: 16) {
            Text("macOS Leak Probe")
                .font(.title)

            Button("Open leaking screen") {
                let wiring = MacLeakingScreenWiring()
                wiring.router.onClose = {
                    wiring.markClosed()
                }
                leakingScreenWiring = wiring
            }
            .accessibilityIdentifier("open-leaking-screen")
        }
        .frame(width: 360, height: 220)
        .sheet(item: $leakingScreenWiring) { wiring in
            MacLeakingScreen {
                wiring.router.close()
                leakingScreenWiring = nil
            }
        }
    }
}

final class MacLeakingScreenWiring: Identifiable {
    let id = UUID()
    let router = MacLeakingScreenRouter()
    private(set) var isClosed = false

    func markClosed() {
        isClosed = true
    }
}

final class MacLeakingScreenRouter {
    var onClose: (() -> Void)?

    func close() {
        onClose?()
    }
}

struct MacLeakingScreen: View {
    let close: () -> Void
    private let model = MacLeakingScreenModel()

    var body: some View {
        VStack(spacing: 12) {
            Text(model.title)
                .font(.headline)

            Button("Close") {
                close()
            }
            .accessibilityIdentifier("close-leaking-screen")
        }
        .frame(width: 320, height: 180)
    }
}

final class MacLeakingScreenModel {
    let title = "This object intentionally leaks"
    private let worker = MacLeakingWorker()

    init() {
        worker.onEvent = {
            _ = self.title
        }
    }
}

final class MacLeakingWorker {
    var onEvent: (() -> Void)?
}
