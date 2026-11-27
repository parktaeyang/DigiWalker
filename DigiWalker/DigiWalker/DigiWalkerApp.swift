//
//  DigiWalkerApp.swift
//  DigiWalker
//
//  Created by 박태양M1 on 11/22/26.
//

import SwiftUI

@main
struct DigiWalkerApp: App {
    @StateObject private var sync: PhoneSyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The app hosts the unit tests: keep them from writing the real widget copy or reloading timelines.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        _sync = StateObject(wrappedValue: PhoneSyncService(
            widget: testing ? InertPhoneWidgetPublisher() : PhoneWidgetPublisher()))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(sync: sync)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { sync.refreshWidget() }
        }
    }
}
