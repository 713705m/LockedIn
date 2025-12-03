import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    
    private init() {}
    
    // MARK: - Permission
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            return granted
        } catch {
            print("Erreur autorisation notifications: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Schedule Workout Reminder
    
    /// Programme un rappel pour une séance
    func scheduleWorkoutReminder(for seance: Seance, reminderMinutesBefore: Int = 30) async {
        let content = UNMutableNotificationContent()
        content.title = "🏃 Séance dans \(reminderMinutesBefore) min"
        content.body = "\(seance.type.emoji) \(seance.type.rawValue) - \(seance.dureeFormatee)"
        content.sound = .default
        content.categoryIdentifier = "WORKOUT_REMINDER"
        
        // Calcul de la date de notification
        let triggerDate = seance.date.addingTimeInterval(TimeInterval(-reminderMinutesBefore * 60))
        
        // Vérifier que c'est dans le futur
        guard triggerDate > Date() else { return }
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "workout-\(seance.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Notification programmée pour \(triggerDate)")
        } catch {
            print("❌ Erreur programmation notification: \(error)")
        }
    }
    
    /// Programme les rappels pour toutes les séances à venir
    func scheduleAllWorkoutReminders(seances: [Seance]) async {
        // D'abord, annuler les anciennes notifications
        await cancelAllWorkoutReminders()
        
        // Filtrer les séances futures planifiées
        let futureSeances = seances.filter { seance in
            seance.date > Date() && seance.statut == .planifie
        }
        
        // Limiter à 64 notifications (limite iOS)
        let seancesToSchedule = Array(futureSeances.prefix(60))
        
        for seance in seancesToSchedule {
            await scheduleWorkoutReminder(for: seance)
        }
        
        print("✅ \(seancesToSchedule.count) notifications programmées")
    }
    
    // MARK: - Cancel
    
    func cancelWorkoutReminder(for seance: Seance) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["workout-\(seance.id.uuidString)"]
        )
    }
    
    func cancelAllWorkoutReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        
        let workoutIds = pending
            .filter { $0.identifier.hasPrefix("workout-") }
            .map { $0.identifier }
        
        center.removePendingNotificationRequests(withIdentifiers: workoutIds)
    }
    
    // MARK: - Daily Motivation
    
    /// Programme une notification de motivation quotidienne
    func scheduleDailyMotivation(at hour: Int = 8, minute: Int = 0) async {
        let content = UNMutableNotificationContent()
        content.title = "💪 Bonne journée !"
        content.body = motivationalQuote()
        content.sound = .default
        
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "daily-motivation",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Erreur notification motivation: \(error)")
        }
    }
    
    private func motivationalQuote() -> String {
        let quotes = [
            "Chaque pas te rapproche de ton objectif !",
            "La constance bat toujours l'intensité.",
            "Ton futur toi te remerciera.",
            "Pas de raccourci vers l'excellence.",
            "Aujourd'hui est un bon jour pour progresser.",
            "Les champions s'entraînent quand ils n'en ont pas envie.",
            "Ta seule limite, c'est toi.",
            "Un jour à la fois, un kilomètre à la fois."
        ]
        return quotes.randomElement() ?? quotes[0]
    }
    
    // MARK: - Weekly Summary
    
    /// Programme un résumé hebdomadaire le dimanche soir
    func scheduleWeeklySummary() async {
        let content = UNMutableNotificationContent()
        content.title = "📊 Résumé de la semaine"
        content.body = "Découvre tes stats de la semaine dans l'app !"
        content.sound = .default
        
        var components = DateComponents()
        components.weekday = 1  // Dimanche
        components.hour = 19
        components.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "weekly-summary",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Erreur notification résumé: \(error)")
        }
    }
}

// MARK: - Notification Categories & Actions

extension NotificationService {
    func setupNotificationCategories() {
        let doneAction = UNNotificationAction(
            identifier: "MARK_DONE",
            title: "✅ Fait !",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "⏰ Rappeler dans 1h",
            options: []
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP",
            title: "Passer",
            options: [.destructive]
        )
        
        let workoutCategory = UNNotificationCategory(
            identifier: "WORKOUT_REMINDER",
            actions: [doneAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([workoutCategory])
    }
}
