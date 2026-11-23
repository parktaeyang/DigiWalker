//
//  DigiWalkerApp.swift
//  DigiWalker
//
//  Created by 박태양M1 on 11/22/26.
//

import SwiftUI

@main
struct DigiWalkerApp: App {
    @StateObject private var sync = PhoneSyncService()

    var body: some Scene {
        WindowGroup {
            ContentView(sync: sync)
        }
    }
}
