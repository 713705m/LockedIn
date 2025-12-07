import Foundation
import Observation
import SwiftData

@Observable
class ChatViewModel {
    var isLoading = false
    var errorMessage: String?
    
    private let apiURL = "https://lockedin-backend.vercel.app/api/chat"
    
    // Fonction utilitaire pour formater les dernières séances avec plus de détails
    private func getRecentActivity(from seances: [Seance]) -> [[String: Any]] {
        let completed = seances
            .filter { $0.statut == .effectue }
            .sorted { $0.date > $1.date }
            .prefix(5)
        
        return completed.map { seance in
            var data: [String: Any] = [
                "date": seance.dateFormatee,
                "sport": seance.sport,
                "type": seance.type.rawValue,
                "duree": seance.dureeMinutes,
                "ressenti": seance.ressenti ?? 5,
                "commentaire": seance.commentaire ?? ""
            ]
            
            if let distance = seance.distanceKm, distance > 0 {
                data["distance"] = distance
            }
            
            if let distance = seance.distanceKm, distance > 0, seance.dureeMinutes > 0 {
                let vitesse = distance / (Double(seance.dureeMinutes) / 60.0)
                data["vitesse"] = round(vitesse * 10) / 10
            }
            
            if let fc = seance.fcMoyenne {
                data["fcMoyenne"] = fc
            }
            
            return data
        }
    }
    
    func sendMessage(
        _ text: String,
        history: [ChatMessage],
        athlete: Athlete?,
        allSeances: [Seance],
        wizardData: WizardData? = nil,
        isAdjustmentMode: Bool = false
    ) async throws -> (String, [SeanceFromIA]) {
        isLoading = true
        defer { isLoading = false }
        
        // 1. Préparer l'historique
        var apiMessages: [[String: String]] = []
        let recentHistory = history.suffix(20)
        for message in recentHistory {
            apiMessages.append(message.toAPIFormat)
        }
        apiMessages.append(["role": "user", "content": text])
        
        // 2. Préparer les données de l'athlète (enrichies avec wizardData si présent)
        var athleteData: [String: Any]? = nil
        if let athlete = athlete {
            var data: [String: Any] = [
                "nom": athlete.nom,
                "typeObjectif": athlete.typeObjectif,
                "dateObjectif": athlete.dateObjectif.ISO8601Format(),
                "semainesRestantes": athlete.semainesRestantes,
                "heuresParSemaine": athlete.heuresParSemaine,
                "sports": athlete.sports,
                "onboardingComplete": athlete.onboardingComplete
            ]
            
            if let vma = athlete.vma {
                data["vma"] = vma
            }
            if let allureEndurance = athlete.allureEndurance {
                data["allureEndurance"] = Athlete.formatAllure(allureEndurance)
            }
            if let allureSeuil = athlete.allureSeuil {
                data["allureSeuil"] = Athlete.formatAllure(allureSeuil)
            }
            if let blessures = athlete.blessures {
                data["blessures"] = blessures
            }
            if let fcMax = athlete.fcMax {
                data["fcMax"] = fcMax
            }
            
            athleteData = data
        }
        
        // 3. Préparer l'activité récente
        let recentActivityData = getRecentActivity(from: allSeances)
        
        // 3b. Préparer les séances planifiées (pour le mode ajustement)
        var plannedSeancesData: [[String: Any]] = []
        if isAdjustmentMode {
            let planned = allSeances
                .filter { $0.source == .ia && $0.statut == .planifie && $0.date >= Date() }
                .sorted { $0.date < $1.date }
            
            plannedSeancesData = planned.map { seance in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                
                return [
                    "date": formatter.string(from: seance.date),
                    "type": seance.type.rawValue,
                    "sport": seance.sport,
                    "dureeMinutes": seance.dureeMinutes,
                    "description": seance.description_,
                    "intensite": seance.intensite.rawValue
                ] as [String: Any]
            }
        }
        
        // 4. Préparer les données du wizard (contexte enrichi pour la génération)
        var wizardContext: [String: Any]? = nil
        if let wizard = wizardData {
            var ctx: [String: Any] = [
                "dateDebut": wizard.dateDebut.ISO8601Format()
            ]
            
            // Objectif (si modifié)
            if !wizard.garderObjectif {
                ctx["nouveauTypeObjectif"] = wizard.typeObjectif
                ctx["nouvelleDateObjectif"] = wizard.dateObjectif.ISO8601Format()
            }
            
            // Allures (si modifiées)
            if !wizard.garderAllures {
                if !wizard.allureEndurance.isEmpty {
                    ctx["allureEndurance"] = wizard.allureEndurance
                }
                if !wizard.allureSeuil.isEmpty {
                    ctx["allureSeuil"] = wizard.allureSeuil
                }
                if !wizard.vma.isEmpty {
                    ctx["vma"] = wizard.vma
                }
            }
            
            // Précisions
            if !wizard.precisions.isEmpty {
                ctx["precisions"] = wizard.precisions
            }
            
            // Mode d'estimation des allures
            if let mode = wizard.estimationMode {
                ctx["estimationMode"] = mode
                ctx["niveauEstime"] = wizard.niveauEstime
                
                if mode == "temps" {
                    ctx["distanceReference"] = wizard.distanceReference
                    let temps = "\(wizard.tempsHeures)h\(wizard.tempsMinutes)m\(wizard.tempsSecondes)s"
                    ctx["tempsReference"] = temps
                }
            }
            
            wizardContext = ctx
        }
        
        // 5. Construire la requête
        var requestBody: [String: Any] = [
            "messages": apiMessages,
            "recentActivity": recentActivityData,
            "isAdjustmentMode": isAdjustmentMode
        ]
        if let athleteData = athleteData {
            requestBody["athlete"] = athleteData
        }
        if let wizardContext = wizardContext {
            requestBody["wizardContext"] = wizardContext
        }
        if !plannedSeancesData.isEmpty {
            requestBody["plannedSeances"] = plannedSeancesData
        }
        
        // Configuration de la requête
        guard let url = URL(string: apiURL) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Gestion erreur HTTP
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                throw APIError.serverError(errorMessage)
            }
            throw APIError.serverError("Code: \(httpResponse.statusCode)")
        }
        
        // 6. Parsing de la réponse
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageContent = json["message"] as? String else {
            throw APIError.parsingError
        }
        
        // Récupération des séances (optionnel)
        var parsedSeances: [SeanceFromIA] = []
        if let seancesArray = json["seances"] as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: seancesArray)
            parsedSeances = try JSONDecoder().decode([SeanceFromIA].self, from: jsonData)
        }
        
        return (messageContent, parsedSeances)
    }
}

// MARK: - Erreurs API

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case parsingError
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide"
        case .invalidResponse:
            return "Réponse invalide du serveur"
        case .serverError(let message):
            return "Erreur serveur: \(message)"
        case .parsingError:
            return "Erreur de parsing de la réponse"
        case .networkError(let error):
            return "Erreur réseau: \(error.localizedDescription)"
        }
    }
}
