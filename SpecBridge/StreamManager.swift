import Foundation
import SwiftUI
import Combine
import UIKit
import AVFoundation
import MWDATCore
import MWDATCamera

// MARK: - StreamQualityPreset
// Fallback quality configurations for Oakley Meta compatibility testing.
enum StreamQualityPreset: String, CaseIterable, Identifiable {
    case high24fps   = "High/24"
    case medium24fps = "Med/24"
    case medium15fps = "Med/15"
    case low15fps    = "Low/15"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var config: StreamSessionConfig {
        switch self {
        case .high24fps:
            return StreamSessionConfig(videoCodec: .raw, resolution: .high,   frameRate: 24)
        case .medium24fps:
            return StreamSessionConfig(videoCodec: .raw, resolution: .medium, frameRate: 24)
        case .medium15fps:
            return StreamSessionConfig(videoCodec: .raw, resolution: .medium, frameRate: 15)
        case .low15fps:
            return StreamSessionConfig(videoCodec: .raw, resolution: .low,    frameRate: 15)
        }
    }
}

// MARK: - StreamManager
@MainActor
class StreamManager: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var status = "Ready to Stream"
    @Published var isStreaming = false
    @Published var selectedPreset: StreamQualityPreset = .high24fps

    private var streamSession: StreamSession?
    private var token: AnyListenerToken?

    // Reference to Twitch Manager
    var twitchManager: TwitchManager?

    private func configureAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Sets iOS to allow Bluetooth audio (prevents "Video Paused" error)
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
            DebugLogger.shared.log("[Audio] AVAudioSession configured successfully")
        } catch {
            DebugLogger.shared.log("[Audio] AVAudioSession configuration FAILED: \(error)")
            DebugLogger.shared.setLastError("audio config failed: \(error.localizedDescription)")
        }
    }

    func startStreaming() async {
        let logger = DebugLogger.shared
        logger.resetSession()
        logger.setStreamState("Starting")
        status = "Checking permissions..."

        // --- Permission check ---
        logger.log("[Permission] Calling checkPermissionStatus(.camera)")
        let currentStatus = try? await Wearables.shared.checkPermissionStatus(.camera)
        logger.log("[Permission] Current camera permission status: \(String(describing: currentStatus))")
        logger.setPermissionState("\(String(describing: currentStatus))")

        if currentStatus != .granted {
            status = "Requesting permission..."
            logger.log("[Permission] Status not granted — calling requestPermission(.camera)")
            let requestResult = try? await Wearables.shared.requestPermission(.camera)
            logger.log("[Permission] requestPermission(.camera) result: \(String(describing: requestResult))")
            logger.setPermissionState("\(String(describing: requestResult))")

            if requestResult != .granted {
                let msg = "Permission denied (result: \(String(describing: requestResult))). Check Meta AI app."
                status = "Permission denied. Check Meta AI app."
                logger.setStreamState("Failed — Permission Denied")
                logger.setLastError(msg)
                return
            }
        }

        status = "Configuring Audio..."
        configureAudio()

        // --- Session setup ---
        status = "Configuring session..."
        logger.log("[Session] Creating AutoDeviceSelector")
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        logger.log("[Session] AutoDeviceSelector created: \(selector)")
        logger.setDeviceInfo("AutoDeviceSelector ready")

        let preset = selectedPreset
        logger.log("[Session] Selected quality preset: \(preset.rawValue)")
        let config = preset.config

        logger.log("[Session] Creating StreamSession")
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        self.streamSession = session
        logger.log("[Session] StreamSession created: \(session)")

        // --- Video handling ---
        token = session.videoFramePublisher.listen { [weak self] frame in
            // 1. Create the visual image for the iPhone screen
            if let image = frame.makeUIImage() {
                Task { @MainActor in
                    // Detect first frame safely on MainActor
                    let isFirst = self?.isStreaming == false
                    if isFirst {
                        DebugLogger.shared.log("[Frame] First video frame arrived — stream is delivering data")
                        DebugLogger.shared.setStreamState("Streaming — First Frame Received")
                    }
                    DebugLogger.shared.incrementFrameCount()
                    self?.currentFrame = image
                    self?.status = "Streaming Live"
                    self?.isStreaming = true
                }
            }

            // 2. Extract the RAW buffer for Twitch
            let buffer = frame.sampleBuffer

            // Hand off to TwitchManager (wrapped in Task to jump threads safely)
            Task { @MainActor in
                self?.twitchManager?.processVideoFrame(buffer)
            }
        }

        status = "Starting stream..."
        logger.log("[Session] Calling session.start()")
        await session.start()
        logger.log("[Session] session.start() returned")
        logger.setStreamState("Running")
    }

    func stopStreaming() async {
        let logger = DebugLogger.shared
        status = "Stopping..."
        logger.log("[Session] Stopping stream session")
        logger.setStreamState("Stopping")

        await streamSession?.stop()
        logger.log("[Session] streamSession.stop() completed")

        // Ensure Twitch stops when glasses stop
        await twitchManager?.stopBroadcast()
        logger.log("[Session] TwitchManager broadcast stopped")

        status = "Ready to Stream"
        isStreaming = false
        currentFrame = nil
        logger.setStreamState("Stopped")
        logger.log("[Session] Stream fully stopped and cleaned up")
    }
}
