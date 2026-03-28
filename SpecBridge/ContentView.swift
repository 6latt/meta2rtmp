import SwiftUI
import MWDATCore

struct ContentView: View {
    // This automatically saves "twitch_key" to the phone's storage
    @AppStorage("twitch_key") private var twitchStreamKey: String = ""

    // Our managers
    @StateObject private var streamManager = StreamManager()
    @StateObject private var twitchManager = TwitchManager()

    @State private var showDebugPanel = false

    var body: some View {
        Group {
            if twitchStreamKey.isEmpty {
                // 1. SETUP SCREEN
                SetupView(streamKey: $twitchStreamKey)
            } else {
                // 2. STREAMING SCREEN
                StreamingView(
                    streamManager: streamManager,
                    twitchManager: twitchManager,
                    streamKey: twitchStreamKey,
                    onLogout: {
                        twitchStreamKey = ""
                    }
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            // SF Symbols 'ladybug' is available from iOS 14+; this project targets iOS 17+
            Button {
                showDebugPanel = true
            } label: {
                Image(systemName: "ladybug")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showDebugPanel) {
            DebugPanelView()
        }
        .onAppear {
            // Link the two managers together
            streamManager.twitchManager = twitchManager
        }
        .onOpenURL { url in
            DebugLogger.shared.log("[URL] onOpenURL received: \(url.absoluteString)")
            Task {
                do {
                    try await Wearables.shared.handleUrl(url)
                    DebugLogger.shared.log("[URL] handleUrl(url) completed successfully")
                    DebugLogger.shared.setRegistrationState("Callback Handled")
                } catch {
                    DebugLogger.shared.log("[URL] handleUrl(url) FAILED: \(error)")
                    DebugLogger.shared.setLastError("handleUrl failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// --- SUB-VIEW: SETUP ---
struct SetupView: View {
    @Binding var streamKey: String
    @State private var inputKey = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Setup Twitch")
                .font(.largeTitle).bold()

            TextField("Enter Stream Key", text: $inputKey)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Connect to Meta AI Glasses") {
                DebugLogger.shared.log("[Registration] startRegistration() called")
                DebugLogger.shared.setRegistrationState("In Progress")
                do {
                    try Wearables.shared.startRegistration()
                    DebugLogger.shared.log("[Registration] startRegistration() launched (awaiting Meta View callback)")
                } catch {
                    DebugLogger.shared.log("[Registration] startRegistration() FAILED: \(error)")
                    DebugLogger.shared.setRegistrationState("Failed: \(error.localizedDescription)")
                    DebugLogger.shared.setLastError("startRegistration failed: \(error.localizedDescription)")
                }
            }
            .buttonStyle(.bordered)

            Button("Save & Continue") {
                if !inputKey.isEmpty {
                    streamKey = inputKey
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputKey.isEmpty)
        }
        .padding()
    }
}

// --- SUB-VIEW: STREAMING ---
struct StreamingView: View {
    @ObservedObject var streamManager: StreamManager
    @ObservedObject var twitchManager: TwitchManager
    var streamKey: String
    var onLogout: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Video Preview
            ZStack {
                Color.black
                if let videoImage = streamManager.currentFrame {
                    Image(uiImage: videoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("Glasses Offline").foregroundStyle(.gray)
                }
            }
            .frame(height: 500)
            .cornerRadius(12)

            // Status Info
            VStack {
                Text("Glasses: \(streamManager.status)")
                Text("Twitch: \(twitchManager.connectionStatus)")
                    .bold()
                    .foregroundStyle(twitchManager.isBroadcasting ? .green : .red)
            }

            // Quality Preset Picker
            Picker("Quality", selection: $streamManager.selectedPreset) {
                ForEach(StreamQualityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button(streamManager.isStreaming ? "Stop All" : "Go Live") {
                    Task {
                        if streamManager.isStreaming {
                            await streamManager.stopStreaming()
                            await twitchManager.stopBroadcast()
                        } else {
                            // Start Glasses
                            await streamManager.startStreaming()
                            // Start Twitch
                            await twitchManager.startBroadcast(streamKey: streamKey)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(streamManager.isStreaming ? .red : .green)

                Button("Logout") {
                    onLogout()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
