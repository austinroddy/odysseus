// BackendManager.swift — spawns and supervises the embedded Odysseus backend.
//
// Responsibilities: pick a port, reuse an already-running instance instead of
// spawning a duplicate (single-instance guard), launch the frozen backend
// binary as a child process with the right environment, poll its readiness
// endpoint, and clean up on quit.
import Foundation
import Combine

@MainActor
final class BackendManager: ObservableObject {
    enum State: Equatable {
        case idle
        case starting(String)
        case ready(port: UInt16)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?
    private let lastPortDefaultsKey = "OdysseusLastBackendPort"
    private let startupTimeout: TimeInterval = 120 // covers first-run embedding-model download

    var baseURL: URL? {
        guard case .ready(let port) = state else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    func start() async {
        state = .starting("Checking for a running instance…")

        if let savedPort = UserDefaults.standard.object(forKey: lastPortDefaultsKey) as? Int,
           let port = UInt16(exactly: savedPort),
           await probe(port: port, path: "/api/health") {
            state = .ready(port: port)
            return
        }

        guard let binaryURL = backendBinaryURL() else {
            state = .failed(
                "Couldn't find the embedded Odysseus backend inside the app bundle "
                    + "(expected at Contents/Resources/backend/Odysseus). "
                    + "This build may be incomplete — see macos/scripts/build.sh."
            )
            return
        }

        let port = PortFinder.findAvailablePort()
        let supportDir = applicationSupportDirectory()
        let logsDir = supportDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = binaryURL

        var env = ProcessInfo.processInfo.environment
        env["APP_BIND"] = "127.0.0.1"
        env["APP_PORT"] = String(port)
        env["ODYSSEUS_DATA_DIR"] = supportDir.path
        proc.environment = env

        let logURL = logsDir.appendingPathComponent("backend.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = FileHandle(forWritingAtPath: logURL.path) {
            handle.seekToEndOfFile()
            proc.standardOutput = handle
            proc.standardError = handle
        }

        process = proc
        state = .starting("Starting Odysseus…")

        do {
            try proc.run()
        } catch {
            state = .failed("Failed to launch the backend: \(error.localizedDescription)")
            return
        }

        state = .starting("Waiting for Odysseus to finish starting…")

        let deadline = Date().addingTimeInterval(startupTimeout)
        while Date() < deadline {
            if !proc.isRunning {
                state = .failed(
                    "Odysseus quit unexpectedly while starting. "
                        + "Check \(logURL.path) for details."
                )
                return
            }
            if await probe(port: port, path: "/api/ready") {
                UserDefaults.standard.set(Int(port), forKey: lastPortDefaultsKey)
                state = .ready(port: port)
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        state = .failed(
            "Odysseus is taking longer than expected to start. It may still be "
                + "downloading its embedding model on first run — this can take a "
                + "couple of minutes. Check \(logURL.path) for progress."
        )
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()

        let deadline = Date().addingTimeInterval(5)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
    }

    private func backendBinaryURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/backend/Odysseus")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Odysseus", isDirectory: true)
    }

    private func probe(port: UInt16, path: String) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
        } catch {
            return false
        }
        return false
    }
}
