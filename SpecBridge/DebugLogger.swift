import Foundation
import Combine

// MARK: - DebugLogger
// Centralized logging and state-tracking hub for Oakley Meta compatibility testing.
// All instrumented code paths write here; the DebugPanelView reads from this object.

@MainActor
final class DebugLogger: ObservableObject {

    // Singleton for easy access from any context
    static let shared = DebugLogger()

    // MARK: State properties (displayed in DebugPanelView)
    @Published var registrationState: String = "Not Started"
    @Published var permissionState: String   = "Unknown"
    @Published var deviceInfo: String        = "None"
    @Published var streamState: String       = "Idle"
    @Published var frameCount: Int           = 0
    @Published var lastError: String         = "None"
    @Published var logEntries: [LogEntry]    = []

    // MARK: Log entry model
    struct LogEntry: Identifiable {
        let id    = UUID()
        let date  = Date()
        let message: String

        var formatted: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return "[\(f.string(from: date))] \(message)"
        }
    }

    private init() {}

    // MARK: Logging

    /// Thread-safe log call. Console output is synchronous; UI update is dispatched to MainActor.
    nonisolated func log(_ message: String) {
        let ts = Date()
        let f  = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        print("[SpecBridge] [\(f.string(from: ts))] \(message)")
        Task { @MainActor in
            let entry = LogEntry(message: message)
            self.logEntries.append(entry)
            // Batch-trim: remove 50 oldest entries when the buffer reaches 550
            if self.logEntries.count > 550 {
                self.logEntries.removeFirst(50)
            }
        }
    }

    // MARK: State helpers (call on MainActor)

    func setRegistrationState(_ state: String) {
        registrationState = state
        log("[Registration] \(state)")
    }

    func setPermissionState(_ state: String) {
        permissionState = state
        log("[Permission] \(state)")
    }

    func setDeviceInfo(_ info: String) {
        deviceInfo = info
        log("[Device] \(info)")
    }

    func setStreamState(_ state: String) {
        streamState = state
        log("[Stream] \(state)")
    }

    func setLastError(_ error: String) {
        lastError = error
        log("[Error] \(error)")
    }

    func incrementFrameCount() {
        frameCount += 1
    }

    func resetSession() {
        frameCount   = 0
        streamState  = "Idle"
        lastError    = "None"
        deviceInfo   = "None"
    }
}
