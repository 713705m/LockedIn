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
        // Filtrer : effectuées, triées par date (récent en premier), prendre les 5 premières
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
            
            // Ajouter distance si disponible
            if let distance = seance.distanceKm, distance > 0 {
                data["distance"] = distance
            }
            
            // Calculer vitesse moyenne si on a distance et durée
            if let distance = seance.distanceKm, distance > 0, seance.dureeMinutes > 0 {
                let vitesse = distance / (Double(seance.dureeMinutes) / 60.0)
                data["vitesse"] = round(vitesse * 10) / 10 // Arrondi à 1 décimale
            }
            
            // Ajouter FC moyenne si disponible
            if let fc = seance.fcMoyenne {
                data["fcMoyenne"] = fc
            }
            
            return data
        }
    }
    
    func sendMessage(_ text: String, history: [ChatMessage], athlete: Athlete?, allSeances: [Seance]) async throws -> (String, [SeanceFromIA]) {
        isLoading = true
        defer { isLoading = false }
        
        // 1. Préparer l'historique
        var apiMessages: [[String: String]] = []
        let recentHistory = history.suffix(20)
        for message in recentHistory {
            apiMessages.append(message.toAPIFormat)
        }
        apiMessages.append(["role": "user", "content": text])
        
        // 2. Préparer les données de l'athlète
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
        
        // 3. Préparer l'activité récente (5 dernières séances effectuées)
        let recentActivityData = getRecentActivity(from: allSeances)
        
        // 4. Construire la requête
        var requestBody: [String: Any] = [
            "messages": apiMessages,
            "recentActivity": recentActivityData
        ]
        if let athleteData = athleteData {
            requestBody["athlete"] = athleteData
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
            // Essayer de parser le message d'erreur
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                throw APIError.serverError(errorMessage)
            }
            throw APIError.serverError("Code: \(httpResponse.statusCode)")
        }
        
        // 5. Parsing de la réponse
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageContent = json["message"] as? String else {
            throw APIError.parsingError
        }
        
        // Récupération des séances (optionnel) - utilise SeanceFromIA défini dans Seance.swift
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
