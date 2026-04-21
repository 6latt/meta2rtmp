import Foundation
import Combine
import AVFoundation
import HaishinKit
import RTMPHaishinKit
import VideoToolbox

@MainActor
class TwitchManager: ObservableObject {
    // The connection to the Twitch Server
    private var rtmpConnection = RTMPConnection()
    // The stream object that sends the data (Now an Actor in v2.0)
    private var rtmpStream: RTMPStream!

    @Published var isBroadcasting = false
    @Published var connectionStatus = "Disconnected"

    private var rtmpFrameCount = 0

    init() {
        rtmpStream = RTMPStream(connection: rtmpConnection)
    }

    func startBroadcast(streamKey: String) async {
        let logger = DebugLogger.shared
        let twitchURL = "rtmp://live.twitch.tv/app"
        connectionStatus = "Connecting..."
        rtmpFrameCount = 0
        logger.rtmpFrameCount = 0

        do {
            // 1. Configure Video Settings for 720p Vertical (9:16)
            let videoSettings = VideoCodecSettings(
                videoSize: .init(width: 720, height: 1280),
                bitRate: 2500 * 1000, // 2.5 Mbps
                profileLevel: kVTProfileLevel_H264_High_3_1 as String,
                scalingMode: .trim,
                maxKeyFrameIntervalDuration: 2, // Twitch standard
                expectedFrameRate: 24
            )
            logger.log("[RTMP] Applying video settings: 720x1280, 2.5Mbps, H.264 High 3.1, 24fps")
            try await rtmpStream.setVideoSettings(videoSettings)
            logger.log("[RTMP] Video settings applied successfully")

            // 2. Connect
            logger.log("[RTMP] Connecting to \(twitchURL)")
            try await rtmpConnection.connect(twitchURL)
            logger.log("[RTMP] Connected to Twitch RTMP server")

            // 3. Publish
            logger.log("[RTMP] Publishing stream")
            try await rtmpStream.publish(streamKey)
            logger.log("[RTMP] Stream published — Live on Twitch")

            connectionStatus = "Live on Twitch!"
            isBroadcasting = true
        } catch {
            connectionStatus = "Connection Failed: \(error.localizedDescription)"
            isBroadcasting = false
            logger.log("[RTMP] Broadcast FAILED: \(error)")
            logger.setLastError("RTMP: \(error.localizedDescription)")
        }
    }

    func stopBroadcast() async {
        let logger = DebugLogger.shared
        logger.log("[RTMP] Stopping broadcast (rtmpFrameCount: \(rtmpFrameCount))")
        do {
            try await rtmpConnection.close()
            logger.log("[RTMP] Connection closed")
        } catch {
            logger.log("[RTMP] Error closing connection: \(error)")
        }
        isBroadcasting = false
        connectionStatus = "Disconnected"
    }

    // FIX: Handles the "Actor-isolated" error
    func processVideoFrame(_ buffer: CMSampleBuffer) {
        // We send frames even before broadcast starts — this primes the encoder
        // so HaishinKit detects the video format (width/height) from the buffer.
        if rtmpFrameCount == 0 {
            DebugLogger.shared.log("[RTMP] First video frame received by TwitchManager")
        }
        rtmpFrameCount += 1
        DebugLogger.shared.rtmpFrameCount = rtmpFrameCount

        Task {
            try? await rtmpStream.append(buffer)
        }
    }
}