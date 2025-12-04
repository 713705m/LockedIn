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
    
    // Identifiant du plan (pour le versioning)
    var planId: String?
    
    // Source de la séance (pour distinguer IA / Strava / Manuel)
    // Optionnel pour la rétrocompatibilité avec les séances existantes
    var source: SourceSeance?
    
    init(
        date: Date,
        type: TypeSeance,
        sport: String = "Course",
        dureeMinutes: Int,
        description: String,
        intensite: Intensite = .modere,
        planId: String? = nil,
        source: SourceSeance? = .manuel
    ) {
        self.id = UUID()
        self.date = date
        self.type = type
        self.sport = sport
        self.dureeMinutes = dureeMinutes
        self.description_ = description
        self.intensite = intensite
        self.statut = .planifie
        self.planId = planId
        self.source = source
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
    
    /// Indique si cette séance doit être comptée dans les stats
    /// Seules les séances Strava ou manuelles effectuées comptent
    /// Les séances IA (même effectuées) ne comptent PAS dans les stats
    var compterDansStats: Bool {
        guard statut == .effectue else { return false }
        // Si source est nil (anciennes séances) ou != .ia, on compte
        return source != .ia
    }
    
    /// Indique si c'est une séance planifiée par l'IA (pas encore réalisée)
    var estPlanifieeIA: Bool {
        return source == .ia && statut == .planifie
    }
    
    /// Source avec valeur par défaut pour l'affichage
    var sourceAffichage: SourceSeance {
        return source ?? .manuel
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

// MARK: - Source Seance

enum SourceSeance: String, Codable {
    case ia = "IA"           // Générée par l'IA
    case strava = "Strava"   // Importée de Strava
    case manuel = "Manuel"   // Créée manuellement par l'utilisateur
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
    
    static func from(string: String) -> TypeSeance {
        let normalized = string.lowercased()
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "è", with: "e")
        
        switch normalized {
        case "endurance": return .endurance
        case "seuil": return .seuil
        case "vma": return .vma
        case "intervalles", "intervalle", "fractionne": return .intervalles
        case "sortie longue", "sortie_longue", "long run": return .sortie_longue
        case "recuperation", "recup": return .recuperation
        case "renforcement", "musculation", "ppg": return .renforcement
        case "etirements", "stretching": return .etirements
        case "repos", "rest": return .repos
        case "competition", "course", "race": return .competition
        case "test": return .test
        default: return .endurance
        }
    }
}

enum Intensite: String, Codable, CaseIterable {
    case leger = "Léger"
    case modere = "Modéré"
    case intense = "Intense"
    case maximal = "Maximal"
    
    // Ajout de facile et maximum pour compatibilité avec l'IA
    static var facile: Intensite { .leger }
    static var maximum: Intensite { .maximal }
    
    var valeur: Int {
        switch self {
        case .leger: return 1
        case .modere: return 2
        case .intense: return 3
        case .maximal: return 4
        }
    }
    
    static func from(string: String) -> Intensite {
        let normalized = string.lowercased()
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "è", with: "e")
        
        switch normalized {
        case "leger", "light", "facile": return .leger
        case "modere", "moderate", "moyen": return .modere
        case "intense", "hard", "difficile": return .intense
        case "maximal", "max", "maximum": return .maximal
        default: return .modere
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

// MARK: - Seance From IA

struct SeanceFromIA: Codable {
    let date: String
    let type: String
    let sport: String
    let dureeMinutes: Int
    let description: String
    let intensite: String

    func toSeance(planId: String?) -> Seance? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let dateParsed = formatter.date(from: date) else { return nil }
        
        // On met la séance à 9h par défaut
        let dateFinale = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dateParsed) ?? dateParsed
        
        return Seance(
            date: dateFinale,
            type: TypeSeance.from(string: type),
            sport: sport,
            dureeMinutes: dureeMinutes,
            description: description,
            intensite: Intensite.from(string: intensite),
            planId: planId,
            source: .ia  // ← IMPORTANT : On marque la source comme IA
        )
    }
}
