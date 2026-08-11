// ContentView.swift — top-level view switching between the startup/loading
// state, the embedded web UI, and a failure state with a way to inspect logs.
import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var backend: BackendManager

    var body: some View {
        Group {
            switch backend.state {
            case .idle:
                LoadingView(message: "Starting Odysseus…")
            case .starting(let message):
                LoadingView(message: message)
            case .ready:
                if let url = backend.baseURL {
                    WebViewContainer(url: url)
                } else {
                    LoadingView(message: "Starting Odysseus…")
                }
            case .failed(let message):
                FailedView(message: message)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct FailedView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Odysseus couldn't start")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Open Log Folder") {
                    let dir = FileManager.default
                        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Odysseus/logs", isDirectory: true)
                    NSWorkspace.shared.open(dir)
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
