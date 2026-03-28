//
//  SpecBridgeApp.swift
//  SpecBridge
//
//  Created by Jason Dukes on 12/5/25.
//

import SwiftUI
import MWDATCore

@main
struct SpecBridgeApp: App {

    init() {
        let logger = DebugLogger.shared
        logger.log("[Startup] SpecBridgeApp.init — calling Wearables.configure()")
        do {
            try Wearables.configure()
            logger.log("[Startup] Wearables.configure() succeeded")
        } catch {
            logger.log("[Startup] Wearables.configure() FAILED: \(error.localizedDescription)")
            // Update lastError state field on MainActor asynchronously
            let description = error.localizedDescription
            Task { @MainActor in
                DebugLogger.shared.setLastError("configure() failed: \(description)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
