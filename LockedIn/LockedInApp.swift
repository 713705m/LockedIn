//
//  LockedInApp.swift
//  LockedIn
//
//  Created by Marianne Ninet on 03/12/2025.
//

import SwiftUI
import SwiftData

@main
struct LockedInApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [
            Athlete.self,
            Seance.self,
            ChatMessage.self
        ])
    }
}
