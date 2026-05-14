//
//  MandacaruiOSApp.swift
//  MandacaruiOS
//
//  Created by Rubens Machion on 14/05/26.
//

import SwiftUI

@main
struct MandacaruiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundSync.register()
    }

    var body: some Scene {
        WindowGroup {
            HomeFactory.make()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                BackgroundSync.scheduleNextRun()
            case .active:
                BackgroundSync.cancel()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
