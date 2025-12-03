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
    @StateObject private var stravaService = StravaService.shared
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onOpenURL { url in
                    // ✅ C'est ici que la magie opère au retour de Strava
                    print("🔗 URL reçue : \(url)")
                    stravaService.handleCallback(url: url)
                }
        }
        .modelContainer(for: [
            Athlete.self,
            Seance.self,
            ChatMessage.self
        ])
    }
}

