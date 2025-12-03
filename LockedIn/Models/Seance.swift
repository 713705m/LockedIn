import Foundation
import SwiftData

@Model
class Seance {
    var id: UUID
    var date: Date
    var type: TypeSeance
    var sport: String              // "Course", "Vélo", "Natation", "Renforcement"
    var dureeMinutes: Int
    var description_: String       // "description" est réservé, on utilise description_
    var intensite: Intensite
    
    // État de la séance
    var statut: StatutSeance
    
    // Données post-séance (optionnel)
    var distanceKm: Double?
    var fcMoyenne: Int?
    var ressenti: Int?             // 1-10
    var commentaire: String?
    
    // Lien Strava (si synchronisé)
    var stravaActivityId: String?
    
    init(
        date: Date,
        type: TypeSeance,
        sport: String = "Course",
        dureeMinutes: Int,
        description: String,
        intensite: Intensite = .modere
    ) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.sport = sport
        self.dureeMinutes = dureeMinutes
        self.description_ = description
        self.intensite = intensite
        self.statut = .planifie
    }
    
    // MARK: - Computed Properties
    
    var estAujourdhui: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var estPassee: Bool {
        date < Date() && !estAujourdhui
    }
    
    var estCetteSemaine: Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    var dateFormatee: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date).capitalized
    }
    
    var heureFormatee: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    var dureeFormatee: String {
        if dureeMinutes >= 60 {
            let heures = dureeMinutes / 60
            let minutes = dureeMinutes % 60
            if minutes == 0 {
                return "\(heures)h"
            }
            return "\(heures)h\(String(format: "%02d", minutes))"
        }
        return "\(dureeMinutes) min"
    }
}

// MARK: - Enums

enum TypeSeance: String, Codable, CaseIterable {
    case endurance = "Endurance"
    case seuil = "Seuil"
    case vma = "VMA"
    case intervalles = "Intervalles"
    case sortie_longue = "Sortie Longue"
    case recuperation = "Récupération"
    case renforcement = "Renforcement"
    case etirements = "Étirements"
    case repos = "Repos"
    case competition = "Compétition"
    case test = "Test"
    
    var emoji: String {
        switch self {
        case .endurance: return "🏃"
        case .seuil: return "🔥"
        case .vma: return "⚡️"
        case .intervalles: return "📊"
        case .sortie_longue: return "🛤️"
        case .recuperation: return "🧘"
        case .renforcement: return "💪"
        case .etirements: return "🤸"
        case .repos: return "😴"
        case .competition: return "🏆"
        case .test: return "📋"
        }
    }
    
    var couleur: String {
        switch self {
        case .endurance: return "blue"
        case .seuil: return "orange"
        case .vma, .intervalles: return "red"
        case .sortie_longue: return "purple"
        case .recuperation, .repos: return "green"
        case .renforcement: return "brown"
        case .etirements: return "teal"
        case .competition: return "yellow"
        case .test: return "gray"
        }
    }
}

enum Intensite: String, Codable, CaseIterable {
    case leger = "Léger"
    case modere = "Modéré"
    case intense = "Intense"
    case maximal = "Maximal"
    
    var valeur: Int {
        switch self {
        case .leger: return 1
        case .modere: return 2
        case .intense: return 3
        case .maximal: return 4
        }
    }
}

enum StatutSeance: String, Codable {
    case planifie = "Planifié"
    case effectue = "Effectué"
    case annule = "Annulé"
    case reporte = "Reporté"
    
    var emoji: String {
        switch self {
        case .planifie: return "📅"
        case .effectue: return "✅"
        case .annule: return "❌"
        case .reporte: return "↩️"
        }
    }
}
