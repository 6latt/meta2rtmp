import SwiftUI

// MARK: - DebugPanelView
// In-app debug screen for Oakley Meta compatibility testing.
// Shows live state from DebugLogger and a scrollable, time-stamped log.

struct DebugPanelView: View {
    @ObservedObject private var logger = DebugLogger.shared

    var body: some View {
        NavigationStack {
            List {
                // Device & Connection
                Section("Device & Connection") {
                    row(label: "Registration", value: logger.registrationState)
                    row(label: "Permission",   value: logger.permissionState)
                    row(label: "Device",       value: logger.deviceInfo)
                }

                // Streaming
                Section("Streaming") {
                    row(label: "Stream State",   value: logger.streamState)
                    row(label: "Glasses Frames", value: "\(logger.frameCount)")
                    row(label: "RTMP Frames",    value: "\(logger.rtmpFrameCount)")
                    row(label: "Last Error",     value: logger.lastError)
                }

                // Log
                Section {
                    if logger.logEntries.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(logger.logEntries.reversed()) { entry in
                            Text(entry.formatted)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Log (\(logger.logEntries.count))")
                        Spacer()
                        Button("Clear") {
                            logger.logEntries.removeAll()
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Debug Panel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

#Preview {
    DebugPanelView()
}
