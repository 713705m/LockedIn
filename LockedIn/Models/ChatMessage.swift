import Foundation
import SwiftData

@Model
class ChatMessage {
    var id: UUID
    var contenu: String
    var estUtilisateur: Bool      // true = user, false = coach IA
    var timestamp: Date
    
    // Pour regrouper les conversations
    var sessionId: UUID?
    
    init(contenu: String, estUtilisateur: Bool) {
        self.id = UUID()
        self.contenu = contenu
        self.estUtilisateur = estUtilisateur
        self.timestamp = Date()
    }
    
    // MARK: - Computed Properties
    
    var heureFormatee: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
    
    var dateFormatee: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - Extension pour conversion API

extension ChatMessage {
    /// Convertit en format pour l'API Groq/OpenAI
    var toAPIFormat: [String: String] {
        [
            "role": estUtilisateur ? "user" : "assistant",
            "content": contenu
        ]
    }
}

// MARK: - Messages prédéfinis

extension ChatMessage {
    static func messageBienvenue() -> ChatMessage {
        ChatMessage(
            contenu: """
            Salut ! 👋 Je suis ton coach IA personnel.
            
            Je vais t'aider à préparer ton objectif sportif. Pour commencer, j'aurais besoin de quelques infos :
            
            • Quel est ton objectif ? (Marathon, Semi, 10K, Trail...)
            • Quelle est la date de ta compétition ?
            • Quel est ton niveau actuel ?
            
            Dis-moi tout ! 🏃‍♂️
            """,
            estUtilisateur: false
        )
    }
    
    static func messageErreur() -> ChatMessage {
        ChatMessage(
            contenu: "Oups, j'ai eu un problème de connexion. Réessaie dans quelques secondes ! 🔄",
            estUtilisateur: false
        )
    }
}
