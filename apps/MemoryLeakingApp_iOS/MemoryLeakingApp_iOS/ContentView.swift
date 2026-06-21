//
//  ContentView.swift
//  MemoryLeakingApp
//
//  Created for the sample project.
//

import SwiftUI
import Foundation
import Combine

struct ContentView: View {
    @State private var leakingScreenWiring: LeakingScreenWiring?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Memory Leaking App")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Open and close the leaking screen repeatedly while xctrace records the process.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                let wiring = LeakingScreenWiring()
                wiring.router.onClose = {
                    wiring.markClosed()
                }
                leakingScreenWiring = wiring
            } label: {
                Label("Open leaking screen", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("open-leaking-screen")
        }
        .padding()
        .sheet(item: $leakingScreenWiring) { wiring in
            LeakingScreen {
                wiring.router.close()
                leakingScreenWiring = nil
            }
        }
    }
}

final class LeakingScreenWiring: Identifiable {
    let id = UUID()
    let router = LeakingScreenRouter()
    private(set) var isClosed = false

    func markClosed() {
        isClosed = true
    }
}

final class LeakingScreenRouter {
    var onClose: (() -> Void)?

    func close() {
        onClose?()
    }
}

struct LeakingScreen: View {
    let close: () -> Void
    @StateObject private var model = LeakingScreenModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "drop.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                Text("This screen intentionally leaks")
                    .font(.headline)

                Text(model.generatedText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Payload: \(model.payloadSizeInKilobytes) KB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Leaking Screen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        close()
                    }
                    .accessibilityIdentifier("close-leaking-screen")
                }
            }
            .accessibilityIdentifier("leaking-screen")
        }
    }
}

final class LeakingScreenModel: ObservableObject {
    @Published private(set) var generatedText = "Waiting"

    let payloadSizeInKilobytes = 512

    private let worker = LeakingWorker()
    private let payload: Data

    init() {
        payload = Data(repeating: 0x2A, count: payloadSizeInKilobytes * 1024)

        worker.onGenerate = { [self] number in
            generatedText = "Generated number: \(number)"
            _ = payload.count
        }

        worker.generate()
    }
}

final class LeakingWorker {
    var onGenerate: ((Int) -> Void)?

    func generate() {
        onGenerate?(Int.random(in: 0..<10_000))
    }
}

#Preview {
    ContentView()
}
