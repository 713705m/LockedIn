import Foundation
import Observation

@Observable
class ChatViewModel {
    var isLoading = false
    var errorMessage: String?
    
    // MARK: - Configuration API
    
    // ✅ URL de ton backend Vercel
    // Remplace par ton URL après déploiement
    private let apiURL = "https://lockedin-backend.vercel.app/api/chat"
    
    
    // MARK: - Send Message
    
    func sendMessage(_ text: String, history: [ChatMessage], athlete: Athlete?) async throws -> String {
        isLoading = true
        defer { isLoading = false }
        
        // Préparer les messages pour l'API
        var apiMessages: [[String: String]] = []
        
        // Ajouter les derniers messages de l'historique
        let recentHistory = history.suffix(20)
        for message in recentHistory {
            apiMessages.append(message.toAPIFormat)
        }
        
        // Ajouter le nouveau message
        apiMessages.append(["role": "user", "content": text])
        
        // Préparer le profil athlète
        var athleteData: [String: Any]? = nil
        if let athlete = athlete, athlete.onboardingComplete {
            athleteData = [
                "nom": athlete.nom,
                "typeObjectif": athlete.typeObjectif,
                "dateObjectif": athlete.dateObjectif.ISO8601Format(),
                "semainesRestantes": athlete.semainesRestantes,
                "heuresParSemaine": athlete.heuresParSemaine,
                "sports": athlete.sports,
                "onboardingComplete": true
            ]
            
            if let vma = athlete.vma {
                athleteData?["vma"] = vma
            }
            if let allureEndurance = athlete.allureEndurance {
                athleteData?["allureEndurance"] = Athlete.formatAllure(allureEndurance)
            }
            if let blessures = athlete.blessures {
                athleteData?["blessures"] = blessures
            }
        }
        
        // Préparer la requête
        var requestBody: [String: Any] = [
            "messages": apiMessages
        ]
        if let athleteData = athleteData {
            requestBody["athlete"] = athleteData
        }
        
        guard let url = URL(string: apiURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30
        
        // Effectuer la requête
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                throw APIError.serverError(errorMessage)
            }
            throw APIError.serverError("Code \(httpResponse.statusCode)")
        }
        
        // Parser la réponse
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            throw APIError.parsingError
        }
        
        return message
    }
}

// MARK: - Errors

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
