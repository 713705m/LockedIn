import Foundation
import SwiftData

@Model
class Athlete {
    // Infos de base
    var nom: String
    var dateObjectif: Date
    var typeObjectif: String  // "Marathon", "Semi", "10K", "Trail", etc.
    
    // Données physiologiques
    var vma: Double?          // km/h
    var fcMax: Int?           // bpm
    var fcRepos: Int?         // bpm
    
    // Allures (en min/km, stockées en secondes pour précision)
    var allureEndurance: Int?     // secondes par km
    var allureSeuil: Int?         // secondes par km
    var allureVMA: Int?           // secondes par km
    
    // Sports pratiqués
    var sports: [String]      // ["Course", "Vélo", "Natation"]
    
    // Disponibilités
    var joursDisponibles: [Int]   // 0=Dim, 1=Lun, ..., 6=Sam
    var heuresParSemaine: Int
    
    // Contraintes
    var blessures: String?
    var notes: String?
    
    // Onboarding complété ?
    var onboardingComplete: Bool
    
    // Date de création
    var dateCreation: Date
    
    init(
        nom: String = "",
        dateObjectif: Date = Date().addingTimeInterval(60*60*24*90), // 3 mois par défaut
        typeObjectif: String = "Marathon",
        sports: [String] = ["Course"],
        joursDisponibles: [Int] = [1, 3, 5], // Lun, Mer, Ven par défaut
        heuresParSemaine: Int = 5
    ) {
        self.nom = nom
        self.dateObjectif = dateObjectif
        self.typeObjectif = typeObjectif
        self.sports = sports
        self.joursDisponibles = joursDisponibles
        self.heuresParSemaine = heuresParSemaine
        self.onboardingComplete = false
        self.dateCreation = Date()
    }
    
    // MARK: - Helpers
    
    /// Convertit une allure en secondes vers un format "X'XX"
    static func formatAllure(_ secondesParKm: Int?) -> String {
        guard let sec = secondesParKm else { return "--'--" }
        let minutes = sec / 60
        let secondes = sec % 60
        return String(format: "%d'%02d", minutes, secondes)
    }
    
    /// Convertit un format "X'XX" vers des secondes
    static func parseAllure(_ allure: String) -> Int? {
        let parts = allure.split(separator: "'")
        guard parts.count == 2,
              let min = Int(parts[0]),
              let sec = Int(parts[1]) else { return nil }
        return min * 60 + sec
    }
    
    /// Nombre de jours jusqu'à l'objectif
    var joursRestants: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: dateObjectif).day ?? 0
    }
    
    /// Semaines jusqu'à l'objectif
    var semainesRestantes: Int {
        joursRestants / 7
    }
}
