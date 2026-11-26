//
//  DigiWalkerApp.swift
//  DigiWalker Watch App
//
//  Created by 박태양M1 on 11/22/26.
//

import SwiftUI

@main
struct DigiWalker_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            WatchHomeView(game: delegate.game)
        }
    }
}
